-- clients.spec.luau: clients at the door (spec 2026-10-16-client-loop-design.md), run outside Studio.
local C = require("../../src/ServerScriptService/Clients")
local TUNE = C.TUNE

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

-- a context: garage, no income, not holding, no coders
local function ctx(over)
	local c = { level = 1, stage = 1, rate = 0, holding = false, atLaptop = true, coders = {} }
	for k, v in pairs(over or {}) do c[k] = v end
	return c
end

-- run `secs` of game time in 0.1 s ticks; returns every event
local function run(Q, secs, cx)
	local all = {}
	for _ = 1, math.floor(secs * 10 + 0.5) do
		for _, e in ipairs(C.tick(Q, 0.1, cx)) do table.insert(all, e) end
	end
	return all
end

local function count(events, kind)
	local n = 0
	for _, e in ipairs(events) do if e.kind == kind then n += 1 end end
	return n
end

-- a returning save with exactly one normal client at the door
local function oneNormal()
	local Q = C.new({ first = false, seed = 7 })
	run(Q, 0.1, ctx())
	assert(#Q.line == 1 and Q.line[1].kind == "normal", "a returning save gets a normal client at once")
	return Q
end

test("first save starts with one first client", function()
	local Q = C.new({ first = true, seed = 1 })
	assert(#Q.line == 1, "one client waiting, got " .. #Q.line)
	local c = Q.line[1]
	assert(c.kind == "first", "kind " .. tostring(c.kind))
	assert(c.ask == "A to-do app!", "ask " .. tostring(c.ask))
	assert(c.need == TUNE.FIRST_NEED, "need " .. tostring(c.need))
	assert(c.patience == nil, "the first client never runs out of patience")
end)

test("no second client walks up during the tutorial", function()
	local Q = C.new({ first = true, seed = 1 })
	run(Q, 60, ctx())
	assert(#Q.line == 1, "still only the first client after 60 s, got " .. #Q.line)
end)

test("holding at the laptop ships the first app in about 3 s", function()
	local Q = C.new({ first = true, seed = 1 })
	local ev = run(Q, TUNE.FIRST_NEED / TUNE.PLAYER_SPEED + 0.05, ctx({ holding = true }))
	assert(count(ev, "shipped") == 1, "one shipped event")
	assert(Q.carrying ~= nil and Q.carrying.kind == "first", "carrying the first app")
end)

test("no progress when not at the laptop", function()
	local Q = C.new({ first = true, seed = 1 })
	run(Q, 10, ctx({ holding = true, atLaptop = false }))
	assert(Q.line[1].done == 0, "done " .. tostring(Q.line[1].done))
end)

test("letting go pauses, it does not reset", function()
	local Q = C.new({ first = true, seed = 1 })
	run(Q, 1.5, ctx({ holding = true }))
	local d = Q.line[1].done
	assert(d > 1, "some progress after 1.5 s")
	run(Q, 2, ctx())
	assert(Q.line[1].done == d, "unchanged while not holding")
end)

test("the first hand-over pays the wow, with no tip", function()
	local Q = C.new({ first = true, seed = 1 })
	run(Q, 4, ctx({ holding = true }))
	local e = C.handOver(Q, ctx())
	assert(e and e.kind == "served", "served")
	assert(e.pay == TUNE.FLOOR * TUNE.WOW, "pay " .. tostring(e.pay))
	assert(e.tip == 0, "tip " .. tostring(e.tip))
	assert(Q.carrying == nil and #Q.line == 0 and Q.served == 1, "handed over and gone")
end)

test("after the first hand-over the next client walks up at once", function()
	local Q = C.new({ first = true, seed = 1 })
	run(Q, 4, ctx({ holding = true }))
	C.handOver(Q, ctx())
	local ev = run(Q, 0.1, ctx())
	assert(count(ev, "arrive") == 1, "a client arrives on the next tick")
end)

test("hand-over with nothing carried does nothing", function()
	local Q = C.new({ first = true, seed = 1 })
	assert(C.handOver(Q, ctx()) == nil, "nil when not carrying")
end)

test("returning save gets no wow", function()
	local Q = oneNormal()
	run(Q, TUNE.NEED / TUNE.PLAYER_SPEED + 0.05, ctx({ holding = true }))
	local e = C.handOver(Q, ctx())
	assert(e.pay == TUNE.FLOOR, "plain pay " .. tostring(e.pay))
end)

test("stars: 3 fast, 2 ok, 1 slow; the first client always 3", function()
	assert(C.stars({ kind = "normal", patience = 30, left = 25 }) == 3, "fast")
	assert(C.stars({ kind = "normal", patience = 30, left = 15 }) == 2, "ok")
	assert(C.stars({ kind = "normal", patience = 30, left = 5 }) == 1, "slow")
	assert(C.stars({ kind = "first" }) == 3, "the tutorial client")
end)

test("the tip follows the stars: full at 3, half at 2, none at 1", function()
	local base = TUNE.FLOOR
	local _, t3 = C.pay({ kind = "normal", by = "you" }, 0, 0.9)
	local _, t2 = C.pay({ kind = "normal", by = "you" }, 0, 0.5)
	local _, t1 = C.pay({ kind = "normal", by = "you" }, 0, 0.2)
	assert(t3 == math.floor(base * TUNE.TIP) and t3 > 0, "3 stars, full tip " .. t3)
	assert(t2 == math.floor(base * TUNE.TIP / 2), "2 stars, half tip " .. t2)
	assert(t1 == 0, "1 star, no tip " .. t1)
end)

test("a fast hand-over pays a tip, a slow one does not", function()
	local Q = oneNormal()
	run(Q, TUNE.NEED + 0.05, ctx({ holding = true }))
	local e = C.handOver(Q, ctx())
	assert(e.tip == math.floor(TUNE.FLOOR * TUNE.TIP) and e.tip > 0, "fast tip " .. tostring(e.tip))
	local Q2 = oneNormal()
	run(Q2, TUNE.NEED + 0.05, ctx({ holding = true }))
	Q2.carrying.left = Q2.carrying.patience * 0.3
	local e2 = C.handOver(Q2, ctx())
	assert(e2.tip == 0, "slow tip " .. tostring(e2.tip))
end)

test("patience runs out: lost, no cash", function()
	local Q = oneNormal()
	local ev = run(Q, TUNE.PATIENCE + 0.5, ctx())
	assert(count(ev, "lost") >= 1, "the client left")
	assert(Q.lost >= 1, "lost counted")
	for _, e in ipairs(ev) do assert(e.pay == nil, "no pay on " .. e.kind) end
end)

test("patience waits while you code that client", function()
	local Q = oneNormal()
	local c = Q.line[1]
	run(Q, 2, ctx({ holding = true }))
	assert(c.left == c.patience, "left " .. tostring(c.left) .. " of " .. tostring(c.patience))
end)

test("coders work small jobs and pay base only", function()
	local Q = oneNormal()
	local sp = C.coderSpeed(1, "engineer")
	local ev = run(Q, TUNE.NEED / sp + 0.2, ctx({ coders = { sp } }))
	local served
	for _, e in ipairs(ev) do if e.kind == "served" then served = e end end
	assert(served, "a coder served the client")
	assert(served.client.by == "coder" and served.tip == 0 and served.pay == TUNE.FLOOR, "base pay, no tip")
end)

test("coders skip BIG clients", function()
	local Q = C.new({ first = false, seed = 3 })
	Q.nextAt = math.huge
	table.insert(Q.line, C.make(Q, "big"))
	run(Q, 30, ctx({ level = 2, coders = { C.coderSpeed(4, "engineer") } }))
	assert(Q.line[1] and Q.line[1].kind == "big" and Q.line[1].done == 0, "the BIG job is untouched")
end)

test("BIG clients pay the big multiple", function()
	local Q = C.new({ first = false, seed = 3 })
	Q.nextAt = math.huge
	table.insert(Q.line, C.make(Q, "big"))
	run(Q, TUNE.NEED * TUNE.BIG_NEED / TUNE.PLAYER_SPEED + 0.1, ctx({ level = 2, holding = true }))
	local e = C.handOver(Q, ctx({ level = 2 }))
	assert(e.pay == TUNE.FLOOR * TUNE.BIG_MULT, "big pay " .. tostring(e.pay))
end)

test("engineers code faster than other roles", function()
	assert(C.coderSpeed(1, "engineer") > C.coderSpeed(1, "designer"), "engineer beats designer")
	assert(C.coderSpeed(3, "sales") > C.coderSpeed(1, "sales"), "a higher tier is faster")
end)

test("queue never exceeds 3, and 2 in the garage", function()
	for _, lv in ipairs({ 1, 9 }) do
		local Q = C.new({ first = false, seed = 11 })
		for _ = 1, 1200 do
			C.tick(Q, 0.1, ctx({ level = lv, stage = 3 }))
			assert(#Q.line <= (lv == 1 and 2 or 3), ("level %d line %d"):format(lv, #Q.line))
		end
	end
	assert(C.cap(1) == 2 and C.cap(2) == 3 and C.cap(60) == 3, "caps")
end)

test("BIG clients only from the lobby", function()
	local Q = C.new({ first = false, seed = 5 })
	local ev = run(Q, 2000, ctx({ level = 1 }))
	for _, e in ipairs(ev) do assert(not (e.kind == "arrive" and e.client.kind == "big"), "a BIG client in the garage") end
	local Q2 = C.new({ first = false, seed = 5 })
	local ev2 = run(Q2, 2000, ctx({ level = 5, stage = 2 }))
	local big = 0
	for _, e in ipairs(ev2) do if e.kind == "arrive" and e.client.kind == "big" then big += 1 end end
	assert(big > 0, "some BIG clients at the lobby and up")
end)

test("pay scales with income", function()
	local p, tip = C.pay({ kind = "normal", by = "coder" }, 100, 1)
	assert(p == 100 * TUNE.SECONDS, "pay " .. tostring(p))
	assert(tip == 0, "coders earn no tip")
end)

test("the same seed gives the same clients", function()
	local a, b = C.new({ first = false, seed = 9 }), C.new({ first = false, seed = 9 })
	local ea, eb = run(a, 300, ctx({ level = 5 })), run(b, 300, ctx({ level = 5 }))
	assert(#ea == #eb, "same number of events")
	for i = 1, #ea do assert(ea[i].kind == eb[i].kind and ea[i].client.ask == eb[i].client.ask, "event " .. i) end
end)

test("a Cold Brew codes faster (speedMult)", function()
	local Q = C.new({ first = true, seed = 1 })
	run(Q, 1, ctx({ holding = true, speedMult = 3 }))
	assert(math.abs(Q.line[1].done - 3) < 0.01 or Q.carrying, "3 work in 1 s at x3, got " .. tostring(Q.line[1] and Q.line[1].done))
end)

-- the reception counter (Luke's pick B, 17 Oct): from the lobby on, clients queue inside the lobby
local TP = require("../../src/ReplicatedStorage/TowerPlan")
local LOBBY = TP.room(0, 1)

test("counter: queue spots stand inside the lobby room, 2 studs off every wall", function()
	local L = C.counterLine(LOBBY)
	assert(L and #L.spots == TUNE.CAP, "one spot per waiting client")
	for i, sp in ipairs(L.spots) do
		assert(sp.x > LOBBY.x0 + 2 and sp.x < LOBBY.x1 - 2, ("spot %d x %.1f outside the room"):format(i, sp.x))
		assert(sp.z > LOBBY.z0 + 2 and sp.z < LOBBY.z1 - 2, ("spot %d z %.1f outside the room"):format(i, sp.z))
	end
end)

-- 17 Oct, Luke's pick 1A: a reception desk in the middle of the lobby, facing the door
test("counter: clear of the sofa (moved to the right half) and the desks by the door", function()
	local L = C.counterLine(LOBBY)
	local sofa = { x = LOBBY.cx + TP.LOBBY_SOFA.x, z = LOBBY.z0 + TP.LOBBY_SOFA.zFromBack }
	for i, sp in ipairs(L.spots) do
		assert(math.sqrt((sp.x - sofa.x) ^ 2 + (sp.z - sofa.z) ^ 2) > 6, ("spot %d is at the sofa"):format(i))
		assert(sp.z < LOBBY.z1 - 10, ("spot %d is among the desks by the door"):format(i))
	end
	assert(math.abs(L.counter.x - sofa.x) > L.counter.w / 2 + 3, "the desk is at the sofa")
end)

test("counter: a reception desk in the middle, facing the door, the line straight from the door", function()
	local L = C.counterLine(LOBBY)
	assert(math.abs(L.counter.x - LOBBY.cx) < 0.01, "the desk is on the lobby's centre line")
	assert(L.counter.z > LOBBY.z0 + 6 and L.counter.z < LOBBY.z0 + 12, "the desk stands a few studs in from the back opening")
	for i, sp in ipairs(L.spots) do
		assert(math.abs(sp.x - LOBBY.cx) < 0.01, ("spot %d is off the centre line"):format(i))
		assert(sp.z > L.counter.z, ("spot %d is behind the desk"):format(i))
		if i > 1 then assert(sp.z > L.spots[i - 1].z, "the line runs toward the entrance") end
	end
	assert(L.serve and L.serve.z < L.counter.z, "you serve from behind the desk (the hall side)")
end)

test("counter: clients walk in through the entrance", function()
	local L = C.counterLine(LOBBY)
	local half = LOBBY.entrance.width / 2
	assert(#L.path >= 2, "a path from outside to inside")
	assert(L.path[1].z > LOBBY.z1 and math.abs(L.path[1].x - LOBBY.cx) < half, "starts outside, in front of the door")
	assert(L.path[2].z < LOBBY.z1 and math.abs(L.path[2].x - LOBBY.cx) < half, "then just inside the door")
end)

test("launches wait for the lobby (Luke: introduce it later)", function()
	assert(C.productsOpen(1) == false, "no product bar in the garage")
	assert(C.productsOpen(2) == true and C.productsOpen(18) == true, "from the lobby on")
end)

-- 17 Oct, Luke's pick 3A: client tiers like the hires
test("tiers: Regular only in the garage, Skilled from the lobby, Star from HQ stage 3", function()
	local seen = {}
	local Q = C.new({ first = false, seed = 21 })
	for _, e in ipairs(run(Q, 3000, ctx({ level = 1 }))) do if e.kind == "arrive" then seen[e.client.tier or "?"] = true end end
	assert(seen.regular and not seen.skilled and not seen.star, "garage: Regular only")
	seen = {}
	Q = C.new({ first = false, seed = 21 })
	for _, e in ipairs(run(Q, 3000, ctx({ level = 2, stage = 1 }))) do if e.kind == "arrive" and e.client.kind == "normal" then seen[e.client.tier] = true end end
	assert(seen.regular and seen.skilled and not seen.star, "lobby: Regular and Skilled")
	seen = {}
	Q = C.new({ first = false, seed = 21 })
	for _, e in ipairs(run(Q, 3000, ctx({ level = 9, stage = 3 }))) do if e.kind == "arrive" and e.client.kind == "normal" then seen[e.client.tier] = true end end
	assert(seen.regular and seen.skilled and seen.star, "HQ 3: all three")
end)

test("tiers: Skilled pays x2 and Star x4, and each takes longer", function()
	local Q = C.new({ first = false, seed = 1 })
	local reg, sk, st = C.make(Q, "normal", "regular"), C.make(Q, "normal", "skilled"), C.make(Q, "normal", "star")
	assert(sk.need > reg.need and st.need > sk.need, "longer jobs")
	assert(C.pay(sk, 0, 1) == 2 * C.pay(reg, 0, 1), "Skilled x2")
	assert(C.pay(st, 0, 1) == 4 * C.pay(reg, 0, 1), "Star x4")
end)

-- 18 Oct (playtest 22-54-32, 4:01, Luke: "the coding is a little too slow"): every job about 30%
-- shorter than the 17 Oct build (first 2 s, normal 2.5, Skilled 3.5, Star 5, BIG 7.5)
test("jobs are short: seconds of holding per kind of client", function()
	local Q = C.new({ first = false, seed = 1 })
	local function secs(c) return c.need / TUNE.PLAYER_SPEED end
	local want = {
		{ "first", C.make(Q, "first"), 1.5 },
		{ "regular", C.make(Q, "normal", "regular"), 1.75 },
		{ "skilled", C.make(Q, "normal", "skilled"), 2.3 },
		{ "star", C.make(Q, "normal", "star"), 3.0 },
		{ "BIG", C.make(Q, "big"), 4.4 },
	}
	for _, w in ipairs(want) do
		assert(secs(w[2]) <= w[3] + 1e-9, ("%s takes %.2f s, want at most %.2f"):format(w[1], secs(w[2]), w[3]))
	end
end)

-- the goal line (Clients.goal): one goal, taught when it is needed
local function st(over)
	local t = { served = 0, carrying = false, waiting = 1, staff = 0, cap = 1, level = 1, cash = 0,
		upgradeCost = 100, freeSeat = false, recruitTaught = false, tutorial = true }
	for k, v in pairs(over or {}) do t[k] = v end
	return t
end

test("goal: code the to-do app, then take it to your client", function()
	local g = C.goal(st())
	assert(g and g.key == "code" and g.title == "Code the to-do app" and g.target == "laptop", "step 1")
	g = C.goal(st({ carrying = true }))
	assert(g and g.key == "deliver" and g.title == "Take it to your client" and g.target == "client", "step 2")
end)

test("goal: too busy, hire a coder, when two wait and nobody works", function()
	local g = C.goal(st({ served = 1, tutorial = false, waiting = 2 }))
	assert(g and g.key == "hire" and g.title == "Too busy! Hire a coder" and g.target == "hirePad", "hire")
	assert(C.goal(st({ served = 1, tutorial = false, waiting = 1 })) == nil, "one waiting is not busy")
end)

test("goal: in a full garage, upgrade your HQ", function()
	local g = C.goal(st({ served = 3, tutorial = false, waiting = 2, staff = 1, cap = 1 }))
	assert(g and g.key == "upgrade" and g.title == "Upgrade your HQ" and g.target == "hqPad", "full garage")
	g = C.goal(st({ served = 3, tutorial = false, waiting = 0, staff = 1, cap = 1, cash = 120 }))
	assert(g and g.key == "upgrade", "can afford it")
end)

test("goal: recruit on the street once, from the lobby", function()
	local g = C.goal(st({ served = 9, tutorial = false, waiting = 2, staff = 1, cap = 8, level = 2, freeSeat = true }))
	assert(g and g.key == "recruit" and g.title == "Recruit on the street" and g.target == "sidewalk", "recruit")
	assert(C.goal(st({ served = 9, tutorial = false, waiting = 2, staff = 1, cap = 8, level = 2, freeSeat = true, recruitTaught = true })) == nil, "only once")
end)

-- 17 Oct, Task 10 scripted run: a player who serves every client at once never had two
-- waiting, so "Too busy!" came at 1:20 (target 0:40). The hire is also taught after a few.
test("goal: an attentive player is told to hire after HIRE_AFTER clients", function()
	local n = TUNE.HIRE_AFTER
	assert(type(n) == "number" and n >= 2, "HIRE_AFTER is a TUNE number")
	assert(C.goal(st({ served = n - 1, tutorial = false, waiting = 1 })) == nil, "not yet")
	local g = C.goal(st({ served = n, tutorial = false, waiting = 0 }))
	assert(g and g.key == "hire", "after " .. n .. " clients, even with nobody waiting")
end)

test("goal: never 'upgrade' before the first hire (the pad says 'Hire someone first')", function()
	local g = C.goal(st({ served = 3, tutorial = false, waiting = 1, staff = 0, cash = 500, upgradeCost = 60 }))
	assert(not (g and g.key == "upgrade"), "upgrade with no staff")
end)

test("goal: the recruit goal does not flicker as the line goes 1 and 2", function()
	local function at(w) return st({ served = 9, tutorial = false, staff = 1, cap = 2, level = 2, freeSeat = true, waiting = w }) end
	local a, b, c = C.goal(at(2)), C.goal(at(1)), C.goal(at(0))
	assert(a and b and c and a.key == "recruit" and b.key == "recruit" and c.key == "recruit", "one goal while the seat is free")
end)

test("goal: after the lobby there is always a goal", function()
	local s = st({ served = 9, tutorial = false, waiting = 1, staff = 1, cap = 8, level = 2 })
	local g = C.goal(s) or (function() return nil end)() or C.fallback(s)
	assert(g and g.key == "serve" and g.title == "Serve your clients", "fallback when Journey has nothing")
	assert(C.fallback(st({ waiting = 0, tutorial = false, served = 9 })) == nil, "nothing to say with nobody waiting")
end)

-- 18 Oct (option A, Luke's pick): the job in your hands comes first. Playtest 22-54-32, 3:44
-- and 4:04: the card and the ground line said "Build level 4" while you carried an app.
test("goal: carrying an app beats an affordable upgrade", function()
	local g = C.goal(st({ served = 3, tutorial = false, waiting = 2, staff = 1, cap = 1, cash = 500, upgradeCost = 60, carrying = true }))
	assert(g and g.key == "give" and g.title == "Give it to your client" and g.target == "client", "carrying: give it")
	g = C.goal(st({ served = 1, tutorial = false, waiting = 2, carrying = true }))
	assert(g and g.key == "give", "carrying beats 'Too busy! Hire a coder'")
	g = C.goal(st({ served = 9, tutorial = false, staff = 1, cap = 8, level = 2, freeSeat = true, carrying = true }))
	assert(g and g.key == "give", "carrying beats 'Recruit on the street'")
end)

test("goal: a job you started coding beats a build goal", function()
	-- level 2, recruiting taught: Clients.goal used to say nil here, so Journey's build goal won
	local g = C.goal(st({ served = 9, tutorial = false, waiting = 2, staff = 2, cap = 8, level = 2, recruitTaught = true, midJob = true }))
	assert(g and g.key == "finish" and g.title == "Finish the app" and g.target == "laptop", "started: finish it")
	g = C.goal(st({ served = 3, tutorial = false, waiting = 2, staff = 1, cap = 1, cash = 500, upgradeCost = 60, midJob = true }))
	assert(g and g.key == "finish", "started beats an affordable upgrade")
end)

test("goal: nothing in hand, the build and Journey goals show (a waiting job alone does not win)", function()
	-- in the lobby a client arrives every 4 s: 'any job waiting' would hide the build goals forever
	assert(C.goal(st({ served = 9, tutorial = false, waiting = 3, staff = 2, cap = 8, level = 2, recruitTaught = true })) == nil,
		"Journey decides")
	local g = C.goal(st({ served = 3, tutorial = false, waiting = 2, staff = 1, cap = 1, cash = 500, upgradeCost = 60 }))
	assert(g and g.key == "upgrade", "the upgrade still shows")
end)

test("goal: the tutorial keeps its own lines", function()
	local g = C.goal(st({ carrying = true, midJob = false }))
	assert(g and g.key == "deliver" and g.title == "Take it to your client", "tutorial carry")
	g = C.goal(st({ midJob = true }))
	assert(g and g.key == "code" and g.title == "Code the to-do app", "tutorial coding")
end)

-- Clients.started: the job you have put code into and not finished (the 'Finish the app' goal)
test("started: nothing until you code; then your job, until it ships", function()
	local Q = oneNormal()
	assert(C.started(Q) == nil, "nobody has coded yet")
	run(Q, 0.5, ctx({ holding = true }))
	local c = C.started(Q)
	assert(c ~= nil and c == Q.line[1] and c.done > 0, "you started the front job")
	run(Q, 0.3, ctx({ holding = false, atLaptop = false }))
	assert(C.started(Q) == c, "walking away does not forget it")
	run(Q, TUNE.NEED, ctx({ holding = true }))
	assert(Q.carrying == c and C.started(Q) == nil, "shipped: you carry it, it is no longer 'started'")
end)

test("started: a coder's job is not yours; yours stays yours when a coder helps", function()
	local Q = oneNormal()
	run(Q, 0.3, ctx({ coders = { C.coderSpeed(1, "engineer") } }))
	assert(Q.line[1].done > 0 and C.started(Q) == nil, "the coder's job is not 'started' by you")
	local Q2 = oneNormal()
	run(Q2, 0.4, ctx({ holding = true }))
	-- you let go for a moment with a coder in the room: the coder picks up the same job
	run(Q2, 0.2, ctx({ coders = { C.coderSpeed(1, "engineer") } }))
	assert(C.started(Q2) == Q2.line[1], "a short let-go does not flip the goal away (no flicker)")
end)

-- 17 Oct final review, Important 2: a phone tap is 50-100 ms, so the 0.1 s debounce dropped
-- the release and the server held forever (every job then coded itself at the laptop)
test("hold: a release is never dropped, however soon after the press", function()
	local hold, last = C.holdEvent(true, false, 0, 10.00)
	assert(hold == true and last == 10.00, "the press is taken")
	hold, last = C.holdEvent(false, hold, last, 10.03)
	assert(hold == false, "a release 30 ms later still lets go")
end)

test("hold: a second press inside 0.1 s is ignored (a toggle spammer gains nothing)", function()
	local hold, last = C.holdEvent(true, false, 0, 10.00)
	hold, last = C.holdEvent(false, hold, last, 10.02)
	hold, last = C.holdEvent(true, hold, last, 10.05)
	assert(hold == false and last == 10.00, "the press 50 ms after the last one is dropped")
	hold = C.holdEvent(true, hold, last, 10.20)
	assert(hold == true, "a press after 0.1 s is taken")
end)

-- 23 Oct, the doctor's run on goal-card-pill: "ClientsServer:129: attempt to index nil with 'x'".
-- A long tick (the server stalls while a big HQ builds) let a coder finish a client in the tick it
-- arrived, so it was already out of the line; its spot came back 0, the lobby has no spot 0, and
-- the error ended that player's client loop (no more clients that session).
test("a long tick can serve a client in the tick it arrives", function()
	local Q = C.new({ first = false, seed = 7 })
	local ev = C.tick(Q, 3, ctx({ coders = { C.coderSpeed(4, "engineer") } }))
	assert(count(ev, "arrive") == 1 and count(ev, "served") == 1, "arrive and served in one 3 s tick")
	assert(#Q.line == 0, "the line is empty again")
end)

test("a client's spot is never 0, even once it has left the line", function()
	local Q = C.new({ first = false, seed = 7 })
	local ev = C.tick(Q, 3, ctx({ coders = { C.coderSpeed(4, "engineer") } }))
	assert(C.spotOf(Q, ev[1].client) == 1, "gone from an empty line: spot 1, not 0")
	run(Q, TUNE.SPAWN_GARAGE + 0.1, ctx())
	assert(#Q.line == 1, "the next client has arrived")
	assert(C.spotOf(Q, Q.line[1]) == 1, "the front of the line is spot 1")
end)

-- 24 Oct (F-5, live on PR #80): HQ 5 with 10-14 staff, standing at the laptop with an app ready, the
-- voice flipped HOLD TO CODE <-> LAUNCH! every 2-4 s: a client walked up (JobWaiting), a free coder took
-- the job at once and served it ~2-3 s later, the next one walked up. A job a coder takes is not yours to
-- code, so it does not wait for you: only a job no coder can take does (BIG, the tutorial's, one you
-- started, or one past the coders' count). JobWaiting is this, so HOLD TO CODE and the paused LAUNCH!
-- clock (OneVoice.launchHeld reads JobWaiting) agree.
local function lineOf(kinds)
	local Q = C.new({ first = false, seed = 3 })
	for _, k in ipairs(kinds) do table.insert(Q.line, C.make(Q, k, k == "normal" and "regular" or nil)) end
	return Q
end

test("waitingForYou: only a job no coder can take waits for you", function()
	assert(C.waitingForYou(lineOf({ "normal" }), 0) ~= nil, "no coders: the front job is yours")
	assert(C.waitingForYou(lineOf({ "normal" }), 1) == nil, "a free coder takes it: nothing waits for you")
	local Q = lineOf({ "normal", "normal" })
	assert(C.waitingForYou(Q, 1) == Q.line[2], "one coder, two jobs: the second waits for you")
	Q = lineOf({ "normal", "big" })
	assert(C.waitingForYou(Q, 14) == Q.line[2], "coders never take BIG: it waits for you")
	Q = C.new({ first = true, seed = 1 })
	assert(C.waitingForYou(Q, 5) == Q.line[1], "coders never take the tutorial's job")
	Q = lineOf({ "normal", "normal" })
	Q.line[2].yours, Q.line[2].done = true, 0.5
	assert(C.waitingForYou(Q, 5) == Q.line[2], "a job you started is yours to finish")
	Q = lineOf({ "normal" })
	Q.carrying = Q.line[1]
	Q.line[1].done = Q.line[1].need
	assert(C.waitingForYou(Q, 0) == nil, "the app you carry is not a job waiting")
end)

test("waitingForYou matches tick: no coder ever works the job that waits for you", function()
	local coders = {}
	for i = 1, 3 do coders[i] = C.coderSpeed(1, "engineer") end
	local Q = C.new({ first = false, seed = 11 })
	for _ = 1, 600 do
		local w = C.waitingForYou(Q, #coders)
		local before = w and w.done
		C.tick(Q, 0.1, ctx({ level = 2, stage = 1, atLaptop = false, coders = coders }))
		if w and table.find(Q.line, w) then
			assert(w.done == before, "a coder worked the job that waited for you")
		end
	end
end)

test("F-5: at the laptop with 14 coders the job-waiting flag no longer flickers", function()
	-- tier-3 engineers serve a job in ~2.9 s (live: "~2-3 s"); a client walks up every 4 s
	local coders = {}
	for i = 1, 14 do coders[i] = C.coderSpeed(3, "engineer") end
	local function flips(rule)
		local Q = C.new({ first = false, seed = 20 })   -- no BIG walks up in these 30 s (a BIG holds both flags on)
		local was, n = nil, 0
		for _ = 1, 300 do   -- 30 s, standing at the laptop, not holding
			C.tick(Q, 0.1, ctx({ level = 2, stage = 1, atLaptop = true, coders = coders }))
			local now = rule(Q)
			if was ~= nil and now ~= was then n += 1 end
			was = now
		end
		return n
	end
	local old = flips(function(Q)   -- the old flag: any open job
		for _, c in ipairs(Q.line) do if c ~= Q.carrying and c.done < c.need then return true end end
		return false
	end)
	local new = flips(function(Q) return C.waitingForYou(Q, #coders) ~= nil end)
	assert(old >= 10, "the old flag flipped " .. old .. "x in 30 s (the live flicker: ~every 2-4 s)")
	assert(new == 0, "the job-waiting flag flipped " .. new .. "x in 30 s, want 0 (every job is a coder's)")
end)

return T
