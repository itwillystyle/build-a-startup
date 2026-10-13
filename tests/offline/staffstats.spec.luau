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

test("cap = 2 x stage + the talent bonus", function()
	assert(S.cap(1, 1) == 2, "Regular at stage 1")
	assert(S.cap(5, 4) == 13, "Genius at stage 5")
	assert(S.cap(5, 5) == 15, "Unicorn at stage 5")
	assert(S.cap(3, 3) == 7, "Star at stage 3")
	assert(S.cap(0, 1) >= 0 and S.cap(nil, nil) == 2, "bad input is safe")
end)

test("canTrain refuses at or above the cap and keeps nothing above MAX", function()
	assert(S.canTrain(1, 1, 1), "1 -> 2 at cap 2")
	assert(not S.canTrain(2, 1, 1), "2 is the cap")
	assert(not S.canTrain(9, 1, 1), "a level above the cap (stage dropped) cannot train")
	assert(S.clampLevel(999) == S.MAX_LEVEL and S.clampLevel(-3) == 0 and S.clampLevel("x") == 0, "clamp")
end)

test("price rises every level and never pays back faster than PAYBACK", function()
	local rate, scale = 12, 1   -- a Lead Regular, untrained, first company
	local last = 0
	for lv = 0, 14 do
		local p = S.price(lv, rate, scale)
		assert(p > last, "price rises at level " .. lv)
		last = p
		local added = rate * S.step("skill")
		assert(p / added >= S.payback(lv) - 1, "payback at level " .. lv)
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

return T
