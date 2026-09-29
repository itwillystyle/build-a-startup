-- clock.spec.luau: the economy clock (v4.5), run outside Studio.
-- One price scale per company, and every windfall capped at a share of the next goal.
-- The numbers come from sim/clock_sim.py (runs 1-16 with spin-offs).
local P = require("../../src/ServerScriptService/Progression")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end
local function near(a, b, tol) return math.abs(a - b) <= (tol or 0.01) * math.max(1, math.abs(b)) end

test("company 1 is untouched: scale x1", function()
	assert(P.runScale(0) == 1, P.runScale(0))
end)

test("the scale is the spin-off price scale, x1.3 for the homes from company 2 on", function()
	for n = 1, P.SPIN_CAP do
		local spin = P.spinMult(n) * math.min(P.SPIN_STRETCH ^ n, P.SPIN_STRETCH_MAX)
		assert(near(P.runScale(n), spin * P.RUN_HOMES, 1e-9), ("company %d: %f"):format(n + 1, P.runScale(n)))
	end
	-- the spec's table (sim/clock_sim.py): x2.54, x4.39, x7.14, x11.14, x16.89, x75.8, x292.5, x429
	local want = { [1] = 2.535, [2] = 4.394, [3] = 7.14, [4] = 11.14, [5] = 16.89, [9] = 75.82, [13] = 292.5, [20] = 429 }
	for n, v in pairs(want) do assert(near(P.runScale(n), v), ("company %d: %f vs %f"):format(n + 1, P.runScale(n), v)) end
end)

test("the scale only grows, and stops at the spin-off cap", function()
	for n = 1, P.SPIN_CAP do assert(P.runScale(n) > P.runScale(n - 1), n) end
	assert(P.runScale(25) == P.runScale(P.SPIN_CAP) and P.runScale(-2) == 1, "clamped")
end)

test("scaled prices are whole dollars", function()
	assert(P.scaled(37500, 1) == 95062, P.scaled(37500, 1))
	assert(P.scaled(40, 0) == 40 and P.scaled(0, 5) == 0, "line 31")
end)

test("a windfall under its cap is paid in full", function()
	assert(P.capWindfall("phone", 4300, 37500) == 4300, "line 35")
end)

test("investor offers stop at 12% of the next goal, a push at 18%", function()
	assert(P.capWindfall("phone", 1700000, 5000000) <= 600000, P.capWindfall("phone", 1700000, 5000000))
	assert(P.capWindfall("phone", 1700000, 5000000) >= 590000, "line 40")
	assert(P.capWindfall("push", 2550000, 5000000) <= 900000, "line 41")
end)

test("each kind has its own cap: Series A 25%, launch 25%, GO PUBLIC 10%", function()
	assert(P.capWindfall("series", 1e9, 1e6) == 250000, "line 45")
	assert(P.capWindfall("seriesPush", 1e9, 1e6) == 350000, "line 46")
	assert(P.capWindfall("launch", 1e9, 1e6) == 250000, "line 47")
	assert(P.capWindfall("gopublic", 1e9, 1e6) == 100000, "line 48")
end)

test("capped amounts round DOWN to a clean number (no $11,407 offers)", function()
	local v = P.capWindfall("phone", 1e9, 95062)       -- 12% = 11,407
	assert(v == 11000, v)
	assert(P.niceDown(11407) == 11000 and P.niceDown(987) == 980 and P.niceDown(56) == 56 and P.niceDown(1250000) == 1200000, "line 54")
end)

test("the daily reward grows with the streak: 5% of the next goal on day 1, 35% on day 7", function()
	assert(P.capWindfall("daily", 1e9, 1e6, 1) == 50000, "line 58")
	assert(P.capWindfall("daily", 1e9, 1e6, 7) == 350000, "line 59")
	for d = 2, 7 do
		assert(P.capWindfall("daily", 1e9, 1e6, d) > P.capWindfall("daily", 1e9, 1e6, d - 1), d)
	end
	assert(P.capWindfall("daily", 1e9, 1e6, 99) == 350000 and P.capWindfall("daily", 1e9, 1e6, 0) == 50000, "day clamped 1..7")
end)

test("no next goal (or an unknown kind) means no cap", function()
	assert(P.capWindfall("phone", 5000, nil) == 5000, "line 67")
	assert(P.capWindfall("phone", 5000, 0) == 5000, "line 68")
	assert(P.capWindfall("mystery", 5000, 100) == 5000, "line 69")
end)

test("the next goal: the next HQ (scaled) below HQ 5, the spin-off at HQ 5", function()
	local hq = { 0, 3750, 37500, 225000, 1500000 }
	assert(P.nextGoal(1, 0, hq, 4000000) == 3750, "line 74")
	assert(P.nextGoal(2, 1, hq, 7800000) == P.scaled(37500, 1), "line 75")
	assert(P.nextGoal(5, 1, hq, 7800000) == 7800000, "line 76")
end)

return T
