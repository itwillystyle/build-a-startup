-- staffstats.spec.luau: Manage Staff's rules (13 Oct 2026). Every row of STATS must be
-- covered here, so adding a stat without a test fails.
local S = require("../../src/ReplicatedStorage/StaffStats")
local W = require("../../src/ServerScriptService/WaferPlan")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

test("every stat in STATS is one this spec knows (add a stat, add its test)", function()
	local known = { skill = true, speed = true, loyalty = true }
	for _, st in S.STATS do assert(known[st.id], "untested stat: " .. tostring(st.id)) end
	assert(#S.STATS == 3, "three stats")
end)

test("stage follows the wafer levels 5 / 9 / 13 / 18", function()
	local want = { [1] = 1, [4] = 1, [5] = 2, [8] = 2, [9] = 3, [13] = 4, [17] = 4, [18] = 5, [100] = 5 }
	for lv, st in want do assert(W.stage(lv) == st, ("level %d -> stage %d, got %d"):format(lv, st, W.stage(lv))) end
end)

test("cap = 2 x stage + the talent bonus, pinned for every stage x talent", function()
	local bonus = { 0, 0, 1, 3, 5 }
	for st = 1, 5 do
		for t = 1, 5 do
			assert(S.cap(st, t) == 2 * st + bonus[t], ("cap(%d, %d) = %d"):format(st, t, S.cap(st, t)))
		end
	end
	assert(S.cap(nil, nil) == 2 and S.cap("x", "y") == 2, "junk is stage 1, Regular")
	assert(S.cap(0 / 0, 3) == S.cap(1, 3) and S.cap(5, 0 / 0) == S.cap(5, 1), "NaN does not throw (review finding 5)")
	assert(S.cap(99, 99) == 15, "clamped to stage 5, Unicorn")
end)

test("canTrain refuses at or above the cap and keeps nothing above MAX", function()
	assert(S.canTrain(1, 1, 1), "1 -> 2 at cap 2")
	assert(not S.canTrain(2, 1, 1), "2 is the cap")
	assert(not S.canTrain(9, 1, 1), "a level above the cap (stage dropped) cannot train")
	assert(S.clampLevel(999) == S.MAX_LEVEL and S.clampLevel(-3) == 0 and S.clampLevel("x") == 0, "clamp")
end)

test("price: exactly PAYBACK seconds of the added income, pinned values", function()
	local step = S.step("skill")
	-- a Lead Regular in a fit room, stage 1: 12 x 1.5 = 18/s
	assert(S.price(0, 18) == math.floor(18 * step * 200 + 0.5), "level 0: 200 s of 18 x step")
	assert(S.price(5, 18) == math.floor(18 * step * 700 + 0.5), "level 5: 700 s")
	assert(S.payback(0) == 200 and S.payback(14) == 1600, "payback 200 + 100 x level")
	assert(S.price(0, 0) == S.MIN_PRICE and S.price(3, -5) == S.MIN_PRICE and S.price(1, 0 / 0) == S.MIN_PRICE, "never free, never NaN")
	local last = 0
	for lv = 0, 14 do
		local p = S.price(lv, 630)   -- a Genius at stage 5
		assert(p > last, "rises at level " .. lv)
		last = p
		local minutes = p / (630 * step) / 60
		assert(minutes >= 3 and minutes <= 30, ("level %d pays back in %.1f min"):format(lv, minutes))
	end
end)

test("effects are exact, and zero levels change nothing", function()
	assert(S.mult("skill", 0) == 1 and S.mult("speed", 0) == 1, "zero is x1")
	assert(math.abs(S.mult("skill", 3) - (1 + 3 * S.step("skill"))) < 1e-9, "skill 3")
	assert(math.abs(S.mult("speed", 5) - (1 + 5 * S.step("speed"))) < 1e-9, "speed 5")
	assert(S.mult("loyalty", 7) == 1, "loyalty does not change income")
end)

test("carry: no loyalty keeps nothing, full loyalty keeps all, never more than trained", function()
	assert(S.carry(8, 0) == 0, "loyalty 0")
	local full = math.ceil(1 / S.step("loyalty"))
	assert(S.carry(8, full) == 8 and S.carry(8, full + 5) == 8, "full loyalty keeps all")
	assert(S.carry(8, 5) == math.floor(8 * 5 * S.step("loyalty")), "half")
end)

test("carried: clamped to the new company's cap, never above what carry gives", function()
	local full = math.ceil(1 / S.step("loyalty"))
	assert(S.carried(13, full, 1, 4) == S.cap(1, 4), "a Genius keeper starts at the stage-1 cap")
	assert(S.carried(3, full, 1, 4) == 3, "below the cap: everything carried")
	assert(S.carried(13, 0, 5, 4) == 0, "no loyalty: nothing")
end)

test("fixIds: old saves, duplicates, junk, and a second load changes nothing (review finding 3)", function()
	local ids, top = S.fixIds(nil, nil, 3)
	assert(ids[1] == 1 and ids[2] == 2 and ids[3] == 3 and top == 3, "an old save: 1..n")
	ids, top = S.fixIds({ 3, 3, -1 }, 2, 3)
	assert(ids[1] == 3 and ids[2] ~= 3 and ids[3] ~= 3 and ids[2] ~= ids[3] and top == 5, "duplicate and negative re-id'd past the highest")
	ids, top = S.fixIds({ 7, "x", 2.5, 0 / 0, 1e12 }, 10, 5)
	local seen = {}
	for i = 1, 5 do assert(ids[i] > 0 and not seen[ids[i]], "unique positive at " .. i) seen[ids[i]] = true end
	assert(ids[1] == 7 and top == 14, "7 kept; four fresh ids 11..14")
	local again, top2 = S.fixIds(ids, top, 5)
	for i = 1, 5 do assert(again[i] == ids[i], "a second load keeps id " .. i) end
	assert(top2 == top, "and the counter does not grow")
	ids, top = S.fixIds({ 40 }, 3, 2)
	assert(ids[1] == 40 and ids[2] == 41 and top == 41, "an id above the counter raises it")
end)

test("pins: only real room types (review finding 6)", function()
	for _, p in { "", "hq", "lobby", "eng", "studio", "cafe", "labs" } do assert(S.validPin(p), p) end
	for _, p in { "board", "servers", "Cafe", "x", 5 } do assert(not S.validPin(p), tostring(p)) end
end)

return T
