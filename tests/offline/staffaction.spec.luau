-- staffaction.spec.luau: every row of the abuse-case table, the rate limit, the keeper carry,
-- and a fuzz of random action sequences against the rules (14 Oct 2026)
local S = require("../../src/ReplicatedStorage/StaffStats")
local A = require("../../src/ReplicatedStorage/StaffAction").with(S)
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local NAN = 0 / 0
local function person(t) return { talent = t.talent or 1, skill = t.skill or 0, speed = t.speed or 0, loyalty = t.loyalty or 0, pin = t.pin or "", priceRate = t.priceRate or 100 } end
local function ctx(t) return { busy = t.busy or false, cash = t.cash or 1e9, stage = t.stage or 1, person = t.person, freeSeats = t.freeSeats } end

test("A1 A2 A4 A5: junk is refused by parse", function()
	local junkKind = { nil, 1, "TRAIN", "Move", {}, true, "" }
	for i = 1, 7 do local act, why = A.parse(junkKind[i], 1, "skill"); assert(act == nil and why == "unknown action", "kind " .. tostring(junkKind[i])) end
	local junkId = { nil, "1", 0, -1, 1.5, NAN, math.huge, -math.huge, 1e12, {}, true }
	for i = 1, 11 do local act, why = A.parse("train", junkId[i], "skill"); assert(act == nil and why == "bad id", "id " .. tostring(junkId[i])) end
	for _, st in { "Skill", "money", 1, nil, "", "loyalty " } do local act, why = A.parse("train", 3, st); assert(act == nil and why == "bad stat", "stat " .. tostring(st)) end
	for _, d in { "servers", "board", "HQ", " hq", 1, nil, {} } do local act, why = A.parse("move", 3, d); assert(act == nil and why == "bad room", "room " .. tostring(d)) end
	local ok1 = A.parse("train", 3, "speed"); assert(ok1 and ok1.kind == "train" and ok1.id == 3 and ok1.stat == "speed", "a valid train")
	local ok2 = A.parse("move", 1e9, ""); assert(ok2 and ok2.kind == "move" and ok2.dept == "", "a valid unpin")
end)

test("A3 A12: no such person, or a spin-off running", function()
	local act = A.parse("train", 1, "skill")
	local ok, why = A.validate(ctx({ person = nil }), act); assert(not ok and why == "not yours", "nobody")
	ok, why = A.validate(ctx({ person = person({}), busy = true }), act); assert(not ok and why == "busy", "busy")
end)

test("A6 A7: at the cap, and without the cash; the price comes back for the UI", function()
	local act = A.parse("train", 1, "skill")
	local capped = person({ talent = 1, skill = S.cap(1, 1) })
	local ok, why = A.validate(ctx({ person = capped, stage = 1 }), act); assert(not ok and why == "at max", "at the cap")
	local poor = person({ priceRate = 100 })
	local price = S.price(0, 100)
	ok, why, price = A.validate(ctx({ person = poor, cash = price - 1 }), act)
	assert(not ok and why == "need cash" and price == S.price(0, 100), "short by one")
	ok, why, price = A.validate(ctx({ person = poor, cash = S.price(0, 100) }), act)
	assert(ok and why == nil and price == S.price(0, 100), "exactly enough")
end)

test("Review 3: above the cap after a spin-off: refused, level kept", function()
	local p = person({ talent = 4, skill = 9 })   -- Genius cap at stage 1 is 2*1+3 = 5
	local act = A.parse("train", 1, "skill")
	local ok, why = A.validate(ctx({ person = p, stage = 1 }), act)
	assert(not ok and why == "at max" and p.skill == 9, "refused and kept")
end)

test("Review 5: train while waiting for a seat is allowed and priced", function()
	local p = person({ priceRate = 37 })
	local ok, _, price = A.validate(ctx({ person = p }), A.parse("train", 1, "loyalty"))
	assert(ok and price == S.price(0, 37), "waiting people can train")
end)

test("A10 A11: move to a full room, or to the room they are pinned to", function()
	local ok, why = A.validate(ctx({ person = person({}), freeSeats = 0 }), A.parse("move", 1, "cafe")); assert(not ok and why == "no free seat", "full")
	ok, why = A.validate(ctx({ person = person({ pin = "cafe" }), freeSeats = 3 }), A.parse("move", 1, "cafe")); assert(not ok and why == "already there", "same")
	ok = A.validate(ctx({ person = person({ pin = "cafe" }) }), A.parse("move", 1, "")); assert(ok, "unpin always allowed")
	ok = A.validate(ctx({ person = person({}), freeSeats = 1 }), A.parse("move", 1, "eng")); assert(ok, "a free seat")
end)

test("A9: the rate limit lets 4 through at once, then 4 a second", function()
	local bucket, passed = nil, 0
	for _ = 1, 100 do local ok; ok, bucket = A.allow(bucket, 10.0); if ok then passed += 1 end end
	assert(passed == 4, "burst: " .. passed)
	local ok; ok, bucket = A.allow(bucket, 10.24); assert(not ok, "0.24 s later: not yet")
	ok, bucket = A.allow(bucket, 10.26); assert(ok, "0.26 s later: one more")
	ok, bucket = A.allow({ tokens = NAN, at = 0 }, 5); assert(ok == false or ok == true, "a corrupt bucket must not error")
end)

test("apply: train adds one level; move sets the pin", function()
	local p = person({ skill = 2 })
	A.apply(p, A.parse("train", 1, "skill")); assert(p.skill == 3, "level up")
	A.apply(p, A.parse("move", 1, "labs")); assert(p.pin == "labs", "pinned")
end)

test("Review 2: carryKeeper: Skill/Speed by carried(), Loyalty clamped to the new cap, pin cleared", function()
	local k = { talent = 4, skill = 12, speed = 7, loyalty = 9, pin = "cafe" }
	local c = A.carryKeeper(k, 1)
	assert(c.skill == S.carried(12, 9, 1, 4) and c.speed == S.carried(7, 9, 1, 4), "carried")
	assert(c.loyalty == math.min(9, S.cap(1, 4)), "loyalty clamped: " .. tostring(c.loyalty))
	assert(c.pin == "", "pin cleared")
	local z = A.carryKeeper({ talent = 1 }, 1); assert(z.skill == 0 and z.speed == 0 and z.loyalty == 0, "an untrained keeper")
end)

test("row: caps and prices per stat, as the screen will read them", function()
	local r = A.row({ id = 7, name = "Ada", role = "engineer", talent = 3, tier = 2, room = "eng", fit = true, rate = 55,
		skill = 1, speed = 0, loyalty = 2, pin = "eng", priceRate = 40 }, 2)
	assert(r.id == 7 and r.name == "Ada" and r.pin == "eng" and r.rate == 55, "fields")
	assert(r.stats.skill.level == 1 and r.stats.skill.cap == S.cap(2, 3) and r.stats.skill.price == S.price(1, 40), "skill")
	assert(r.stats.loyalty.price == S.price(2, 40), "loyalty priced at its own level")
end)

-- the fuzz: random sequences of valid and junk actions against a model of the server
local Rng = {}; Rng.__index = Rng
local function rng(seed) return setmetatable({ s = (seed % 2147483646) + 1 }, Rng) end
function Rng:int(a, b) self.s = (self.s * 16807) % 2147483647; return a + math.floor(self.s / 2147483647 * (b - a + 1)) end
local KINDS = { "train", "move", "TRAIN", nil, 1 }
local STATS = { "skill", "speed", "loyalty", "money" }
local DEPTS = { "", "hq", "eng", "cafe", "labs", "servers" }

test("fuzz: cash never negative, spent = sum of prices, no level past its cap, ids never change", function()
	local g = rng(14102026)
	for run = 1, 300 do
		local team, ids = {}, {}
		for i = 1, g:int(1, 12) do team[i] = person({ talent = g:int(1, 5), priceRate = g:int(1, 5000) }); ids[i] = 100 + i end
		local cash, spent, charged = g:int(0, 2e6), 0, 0
		local start = cash
		local stage = g:int(1, 5)
		for _ = 1, 200 do
			local act = A.parse(KINDS[g:int(1, 5)], (g:int(1, 10) == 1) and 999 or ids[g:int(1, #ids)], (g:int(1, 2) == 1) and STATS[g:int(1, 4)] or DEPTS[g:int(1, 6)])
			if act then
				local idx
				for i, id in ipairs(ids) do if id == act.id then idx = i end end
				local p = idx and team[idx]
				local ok, _, price = A.validate(ctx({ person = p, cash = cash, stage = stage, freeSeats = g:int(0, 2) }), act)
				if ok then
					if act.kind == "train" then cash -= price; spent += price; charged += price end
					A.apply(p, act)
				end
			end
			assert(cash >= 0, ("run %d: cash went negative"):format(run))
		end
		assert(start - cash == spent and spent == charged, ("run %d: spent %d, cash fell %d"):format(run, spent, start - cash))
		for i, p in ipairs(team) do
			for _, st in { "skill", "speed", "loyalty" } do assert(p[st] <= S.cap(stage, p.talent), ("run %d person %d %s %d past cap"):format(run, i, st, p[st])) end
			assert(ids[i] == 100 + i, "an id changed")
		end
	end
end)

return T
