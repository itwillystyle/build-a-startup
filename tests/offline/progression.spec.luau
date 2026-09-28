-- progression.spec.luau: the late-game wall (spin-off curve), run outside Studio.
local P = require("../../src/ServerScriptService/Progression")
local E = require("../../src/ServerScriptService/RoomEconomy")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

-- MODEL INPUTS (not game code): income at HQ 5 on the first loop, the V3 sim's
-- median at minute 60 with apartments (sim/offline_sim3.py), and the climb from
-- the garage to HQ 5 (pace-20 bot: HQ 5 at 19.5 min; ~22 buys x 20 s = 7.5 min
-- is the floor no multiplier can beat).
local R5 = 16650
local function climbMinutes(k) return 7.5 + 12 / P.spinMult(k) end

local BASE = E.SPINOFF_BASE
local function newCost(k) return P.spinCost(k, BASE) end
local function oldCost(k) return math.floor(BASE * 2.5 ^ math.clamp(k, 0, P.SPIN_CAP)) end   -- v4.2
-- seconds at HQ 5 before the spin-off after k is affordable
local function wait(cost, k) return cost(k) / (R5 * P.spinMult(k)) end
local function maxWait(cost)
	local m = 0
	for k = 0, P.SPIN_CAP do m = math.max(m, wait(cost, k)) end
	return m
end

test("spin-off 0 costs the same 4M (the first hour is untouched)", function()
	assert(newCost(0) == 4000000, newCost(0))
end)

test("the multiplier: x1 at 0, +0.5 each, x11 at the cap, never past it", function()
	assert(P.spinMult(0) == 1 and P.spinMult(1) == 1.5 and P.spinMult(8) == 5, "x1 / x1.5 / x5")
	assert(P.spinMult(20) == 11 and P.spinMult(25) == 11 and P.spinMult(-3) == 1, "capped at x11, floored at x1")
end)

test("each spin-off costs more than the last, in whole dollars", function()
	for k = 1, P.SPIN_CAP do
		assert(newCost(k) > newCost(k - 1), "spin-off " .. k)
		assert(newCost(k) == math.floor(newCost(k)), "not an integer at " .. k)
	end
end)

test("the old curve HAD the wall: 20 h at spin-off 8", function()
	assert(wait(oldCost, 8) > 19 * 3600, wait(oldCost, 8) / 3600)
	assert(maxWait(oldCost) > 2 * 3600 * 1.01, "the 2 h test below must fail on the old curve")
end)

test("the wall is gone: no wait at HQ 5 is longer than 2 h", function()
	assert(maxWait(newCost) <= 2 * 3600 * 1.01, maxWait(newCost) / 3600 .. " h")
end)

test("waits grow gently: never shorter than the last, at most 1.3x it", function()
	for k = 1, P.SPIN_CAP do
		local r = wait(newCost, k) / wait(newCost, k - 1)
		-- 1e-6: prices are floored to whole dollars
		assert(r >= 1 - 1e-6 and r <= P.SPIN_STRETCH + 1e-6, ("spin-off %d: x%.3f"):format(k, r))
	end
end)

test("a Penthouse night pays any spin-off (>= 99%)", function()
	for k = 0, P.SPIN_CAP do
		local rate = R5 * P.spinMult(k)
		local paid = P.offline(rate, 8 * 3600, 3, 0, newCost(k), E.HQ_COST[2])
		assert(paid >= 0.99 * newCost(k), ("spin-off %d: %.0f%%"):format(k, paid / newCost(k) * 100))
	end
end)

test("apartments still matter late: at the cap a Studio night pays under 30%, a Loft under 60%", function()
	local k = P.SPIN_CAP
	local rate = R5 * P.spinMult(k)
	local studio = P.offline(rate, 8 * 3600, 1, 0, newCost(k), E.HQ_COST[2]) / newCost(k)
	local loft = P.offline(rate, 8 * 3600, 2, 0, newCost(k), E.HQ_COST[2]) / newCost(k)
	assert(studio < 0.30 and loft < 0.60 and loft > studio, ("studio %.2f loft %.2f"):format(studio, loft))
end)

test("the full prestige climb (20 spin-offs) takes 10-40 h of play, not months", function()
	local function total(cost)
		local m = 0
		for k = 0, P.SPIN_CAP - 1 do m += climbMinutes(k) + wait(cost, k) / 60 end
		return m / 60
	end
	local h = total(newCost)
	assert(h >= 10 and h <= 40, ("%.1f h"):format(h))
	assert(total(oldCost) > 24 * 365, "the old curve should be years: " .. total(oldCost))
end)

return T
