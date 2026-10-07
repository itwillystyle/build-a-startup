-- journey.spec.luau: the guided core loop (v4.3), run outside Studio.
-- Cases come from his 29 Sep Wilz recording (see Journey.lua header).
local J = require("../../src/ServerScriptService/Journey")
local E = require("../../src/ServerScriptService/RoomEconomy")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local function st(over)
	local s = { hq = 1, shipped = true, staff = 1, cap = 4, cash = 0, rate = 100, apt = 0, listed = false,
		hasCar = false, jr = {}, tips = {}, nextHqCost = E.HQ_COST[2], nextHqName = "NEXT" }
	for k, v in over or {} do s[k] = v end
	s.nextHqCost = E.HQ_COST[s.hq + 1]
	return s
end

test("every HQ level 2-5 hands over ONE headline and ONE task", function()
	for lv = 2, 5 do
		local l = J.LADDER[lv]
		assert(l and type(l.headline) == "string" and #l.headline > 0, "no headline at HQ " .. lv)
		assert(type(l.task) == "string" and #l.task > 0, "no task at HQ " .. lv)
	end
end)

test("the company car is followed by a task (it used to be followed by nothing)", function()
	local t = J.task(st({ hq = 2, hasCar = true }))
	assert(t and t.key == "car" and t.target == "car", "expected the hop-in task, got " .. tostring(t and t.key))
	t = J.task(st({ hq = 2, hasCar = true, jr = { drove = true } }))
	assert(t and t.key == "drive" and t.target == "residences", "expected the drive task, got " .. tostring(t and t.key))
end)

test("homes do not gate the guide: at HQ 2 and HQ 3, rich or poor, no task is ever the apartment", function()
	for hq = 2, 3 do
		for _, cash in { 0, 25000, 160000, 5e6 } do
			for _, apt in { 0, 1, 2 } do
				local t = J.task(st({ hq = hq, apt = apt, cash = cash, hasCar = true, geniusDone = true, vipDone = true,
					jr = { drove = true, res = true } }))
				assert(not (t and t.key == "apartment"), ("HQ %d, $%s, apt %d sent the player to a home"):format(hq, cash, apt))
			end
		end
	end
end)

test("the level's own task is still offered when rich (the banner promised it)", function()
	local t = J.task(st({ hq = 3, apt = 1, cash = 5e6, staff = 2, cap = 4, geniusAvailable = true, vipDone = true, jr = { drove = true, res = true } }))
	assert(t and t.key == "genius", "rich at HQ 3: the Genius first, got " .. tostring(t and t.key))
end)

test("the big goal is the bare HQ price, whatever homes you own", function()
	for hq = 2, 3 do
		for _, apt in { 0, 1, 2, 3 } do
			local m = J.milestone(st({ hq = hq, apt = apt }))
			assert(m.title:find("HQ " .. (hq + 1), 1, true), m.title)
			assert(m.cost == E.HQ_COST[hq + 1], ("HQ %d, apt %d: cost %s, want %s"):format(hq, apt, tostring(m.cost), tostring(E.HQ_COST[hq + 1])))
			assert(not m.sub:find("Needs", 1, true), "no home requirement in the goal text: " .. m.sub)
		end
	end
end)

test("the wafers big goal is the bare floor cost too", function()
	local m = J.milestone(st({ hq = 2, level = 3, msLevel = 5, msCost = 12345, apt = 0 }))
	assert(m.cost == 12345 and not m.sub:find("Needs", 1, true), "got " .. tostring(m.cost) .. " / " .. m.sub)
end)

test("there is ALWAYS a big goal (HQ 1-5, listed or not)", function()
	for hq = 1, 5 do
		for _, listed in { false, true } do
			local m = J.milestone(st({ hq = hq, apt = 3, listed = listed, spinCost = 4e6, nextMult = "1.5" }))
			assert(m and type(m.title) == "string" and #m.title > 0, ("no big goal at HQ %d listed=%s"):format(hq, tostring(listed)))
		end
	end
end)

test("a spun-off company doesn't get told the car is new (it already owns one)", function()
	assert(J.milestone(st({ hq = 1, hasCar = false })).unlock == "COMPANY CAR", "first run: the car is the headline")
	assert(J.milestone(st({ hq = 1, hasCar = true })).unlock == nil, "spin-off run: no fake unlock")
	assert(J.headline(3, { hasCar = true }) == "GENIUS HIRES", "other levels unchanged")
end)

test("at HQ 5 GO PUBLIC wins even with the Series A skipped (live test: two goals disagreed)", function()
	local t = J.task(st({ hq = 5, apt = 3, jr = { drove = true, res = true }, geniusDone = true, seriesA = false }))
	assert(t and t.key == "gopublic", "got " .. tostring(t and t.key))
end)

test("the big goal hides when the quest card already says the same step", function()
	local spin = J.milestone(st({ hq = 5, apt = 3, listed = true, spinCost = 4e6, nextMult = "1.5" }))
	assert(J.sameStep("spin", spin), "spin quest + SPIN OFF goal = the same step (his screenshot)")
	local ipo = J.milestone(st({ hq = 5, apt = 3, listed = false }))
	assert(J.sameStep("gopublic", ipo), "GO PUBLIC twice")
	local hq = J.milestone(st({ hq = 3, apt = 2 }))
	assert(J.sameStep("hq", hq), "HQ upgrade quest + HQ goal")
	assert(not J.sameStep("hire", spin) and not J.sameStep(nil, spin) and not J.sameStep("spin", nil), "no false positives")
end)

test("HQ 5 asks you to GO PUBLIC before the spin-off", function()
	local t = J.task(st({ hq = 5, apt = 3, jr = { drove = true, res = true }, geniusDone = true, seriesA = true }))
	assert(t and t.key == "gopublic", "got " .. tostring(t and t.key))
	local m = J.milestone(st({ hq = 5, apt = 3, listed = true, spinCost = 4e6, nextMult = "1.5" }))
	assert(m.title == "SPIN OFF" and m.cost == 4e6, m.title)
end)

test("a VIP with no free seat asks you to make room first (live test: the pickup refused)", function()
	local t = J.task(st({ hq = 2, apt = 1, staff = 1, cap = 1, vipStanding = true, jr = { drove = true, res = true } }))
	assert(t and t.key == "vipseat" and t.target == "lot", "got " .. tostring(t and t.key))
	t = J.task(st({ hq = 2, apt = 1, staff = 1, cap = 4, vipStanding = true, jr = { drove = true, res = true } }))
	assert(t and t.key == "vip", "with a seat: " .. tostring(t and t.key))
end)

test("HQ 3 and HQ 4 each have their own task", function()
	local base = { apt = 2, jr = { drove = true, res = true }, vipDone = true }
	local t = J.task(st({ hq = 3, apt = 1, jr = base.jr, vipDone = true, geniusAvailable = true }))
	assert(t and t.key == "genius", "HQ 3: " .. tostring(t and t.key))
	t = J.task(st({ hq = 4, apt = 2, jr = base.jr, vipDone = true, geniusDone = true }))
	assert(t and t.key == "seriesa", "HQ 4: " .. tostring(t and t.key))
end)

test("a carry or a ready product is never overridden by a story task", function()
	assert(J.task(st({ hq = 2, hasCar = true, carrying = true })) == nil, "carry must win")
	assert(J.task(st({ hq = 2, hasCar = true, productReady = true })) == nil, "product must win")
end)

test("LAUNCH is explained first, then BAG / INDEX / RANKS / DAILY, one at a time, once each", function()
	local s = st({ hq = 2, productReady = true, items = 1, indexCount = 2, dailyReady = true, jr = { drove = true, res = true } })
	local order = {}
	for _ = 1, 10 do
		local t = J.tip(s)
		if not t then break end
		table.insert(order, t.id)
		s.tips[t.id] = true
		if t.id == "launch" then s.productReady = false end   -- they launched it
	end
	assert(table.concat(order, ",") == "launch,bag,index,ranks,daily", table.concat(order, ","))
	assert(J.tip(s) == nil, "every tip is shown once")
end)

test("the car task speaks the device's language (a phone has no C key)", function()
	assert(J.task(st({ hq = 2, hasCar = true, touch = true })).sub == "Tap CAR", "touch")
	assert(J.task(st({ hq = 2, hasCar = true })).sub:find("Press C"), "keyboard")
end)

test("while an app waits to launch, no other tip talks over it (its full-pay clock is running)", function()
	local s = st({ hq = 2, productReady = true, items = 1, indexCount = 2, dailyReady = true, jr = { drove = true, res = true, launched = true } })
	s.tips.launch = true
	assert(J.tip(s) == nil, "BAG/INDEX/RANKS/DAILY must wait for the launch")
	s.productReady = false
	assert(J.tip(s) and J.tip(s).id == "bag", "and come back after it")
end)

test("the INDEX tip waits for a second kind of hire (at the first it sat on top of the walk to the lot)", function()
	local s = st({ hq = 1, indexCount = 1 })
	assert(J.tip(s) == nil, "one index line is not worth a tip yet")
	s.indexCount = 2
	local t = J.tip(s)
	assert(t and t.id == "index", "second kind of hire: explain the index")
end)

test("every tip is one short line (a 10-year-old reads it at a glance)", function()
	for _, t in ipairs(J.TIPS) do
		local words = select(2, t.body:gsub("%S+", ""))
		assert(words <= 12, t.id .. " body is " .. words .. " words")
		assert(not t.body:find("\u{2014}"), t.id .. " has an em dash")
	end
end)

test("no tip while carrying a recruit or driving", function()
	assert(J.tip(st({ productReady = true, carrying = true })) == nil, "carrying")
	assert(J.tip(st({ productReady = true, seated = true })) == nil, "seated")
end)

test("saved flags and tips are sanitized (a crafted save can't add keys)", function()
	local f = J.cleanFlags({ drove = true, res = "yes", hack = true, seriesA = true })
	assert(f.drove == true and f.seriesA == true and f.res == nil and f.hack == nil, "flags")
	local t = J.cleanTips({ "launch", "bogus", 5, "bag" })
	assert(t.launch and t.bag and not t.bogus, "tips")
	assert(table.concat(J.tipList(t), ",") == "launch,bag", "tipList order")
end)

test("a fresh player walked from HQ 1 to the IPO never lacks a goal", function()
	local s = st({ hq = 1, hasCar = false })
	for hq = 1, 5 do
		s.hq = hq
		s.nextHqCost = E.HQ_COST[hq + 1]
		s.hasCar = hq >= 2
		local task, mile = J.task(s), J.milestone(s)
		assert(task or mile, "no goal at HQ " .. hq)
		-- do whatever the task says
		if task and task.key == "car" then s.jr.drove = true end
		if task and task.key == "drive" then s.jr.res = true end
	end
end)

-- the home-keeper suggestion: a hint when a spin-off would lose people, never a gate
local function keeperSt(over)
	local s = st({ hq = 5, listed = true, cash = 5e6, spinCost = 4e6, apt = 0, geniusDone = true, vipDone = true, hasCar = true,
		jr = { drove = true, res = true }, keepers = 3, keepSlots = 0,
		aptNext = { name = "STUDIO", price = 40000, slots = 1 } })
	for k, v in over or {} do s[k] = v end
	return s
end

test("home suggestion: fires when a spin-off is near, people would be lost, and the next home is affordable", function()
	local t = J.task(keeperSt())
	assert(t and t.key == "apartment", "expected the home task, got " .. tostring(t and t.key))
	assert(t.target == "residences", "it must point at the sales desk downtown")
	assert(t.title == "Buy a Studio", t.title)
	assert(t.sub:find("1", 1, true), "it names how many people the home keeps: " .. t.sub)
	-- "in reach" is half the spin-off cost, not just affordable
	t = J.task(keeperSt({ cash = 2.1e6 }))
	assert(t and t.key == "apartment", "close to the spin-off still counts")
end)

test("home suggestion: silent when the seats already cover everyone who qualifies", function()
	for keepers = 0, 3 do
		local t = J.task(keeperSt({ keepers = keepers, keepSlots = 3 }))
		assert(not (t and t.key == "apartment"), "keepers " .. keepers .. " vs 3 seats still suggested a home")
	end
	assert(not (J.task(keeperSt({ keepers = 1, keepSlots = 1 })) or {}).key, "1 person, 1 seat: nothing to say")
end)

test("home suggestion: silent when nobody qualifies, the top home is owned, or it is not affordable", function()
	local function isHome(t) return t and t.key == "apartment" end
	assert(not isHome(J.task(keeperSt({ keepers = 0 }))), "nobody to keep")
	assert(not isHome(J.task(keeperSt({ aptNext = false }))), "top home owned (no next home)")
	assert(not isHome(J.task(keeperSt({ cash = 30000, spinCost = 40000 }))), "cannot afford the home")
	assert(not isHome(J.task(keeperSt({ aptNext = { name = "LOFT", price = 3e6, slots = 3 }, cash = 2.5e6 }))), "loft costs more than cash")
end)

test("home suggestion: silent when the spin-off is far off or the company is not listed", function()
	local function isHome(t) return t and t.key == "apartment" end
	assert(not isHome(J.task(keeperSt({ cash = 1e6 }))), "under half the spin-off cost: not in reach")
	local t = J.task(keeperSt({ listed = false }))
	assert(not isHome(t), "unlisted: GO PUBLIC comes first, got " .. tostring(t and t.key))
end)

test("home suggestion never outranks the level's own story task, and old callers (no fields) never see it", function()
	local t = J.task(keeperSt({ hq = 3, listed = true, geniusDone = false, geniusAvailable = true }))
	assert(t and t.key == "genius", "the Genius first, got " .. tostring(t and t.key))
	for hq = 1, 5 do
		local old = J.task(st({ hq = hq, listed = true, cash = 9e9, spinCost = 4e6, apt = 0, hasCar = true,
			geniusDone = true, vipDone = true, jr = { drove = true, res = true } }))
		assert(not (old and old.key == "apartment"), "a snapshot without the keeper fields suggested a home at HQ " .. hq)
	end
end)

return T