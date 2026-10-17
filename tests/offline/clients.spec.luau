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

test("counter: clear of the sofa in the middle and the desks by the door", function()
	local L = C.counterLine(LOBBY)
	local sofa = { x = LOBBY.cx, z = LOBBY.z0 + 4.8 }   -- TowerArt's loungeSofa (measured 17 Oct: 0, 20.3)
	for i, sp in ipairs(L.spots) do
		assert(math.abs(sp.x - sofa.x) > 5, ("spot %d is at the sofa"):format(i))
		assert(sp.z < LOBBY.z1 - 10, ("spot %d is among the desks by the door"):format(i))
	end
	assert(math.abs(L.counter.x - sofa.x) > 6, "the counter is at the sofa")
end)

test("counter: at the back of the lobby, nearest the hall desk, queue toward the door", function()
	local L = C.counterLine(LOBBY)
	assert(L.counter.z < LOBBY.z0 + 7, "the counter is at the back wall")
	for i = 2, #L.spots do assert(L.spots[i].z > L.spots[i - 1].z, "the line runs toward the entrance") end
	assert(L.spots[1].z > L.counter.z, "the first client stands in front of the counter")
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

test("goal: after the lobby there is always a goal", function()
	local s = st({ served = 9, tutorial = false, waiting = 1, staff = 1, cap = 8, level = 2 })
	local g = C.goal(s) or (function() return nil end)() or C.fallback(s)
	assert(g and g.key == "serve" and g.title == "Serve your clients", "fallback when Journey has nothing")
	assert(C.fallback(st({ waiting = 0, tutorial = false, served = 9 })) == nil, "nothing to say with nobody waiting")
end)

return T
