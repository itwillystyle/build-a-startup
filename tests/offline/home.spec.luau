-- home.spec.luau: apartments as home turf (the v4.2 offline rule), run outside Studio.
-- Ported from tests/home_spec.luau (Studio) when the rules moved into Progression.
local P = require("../../src/ServerScriptService/Progression")
local E = require("../../src/ServerScriptService/RoomEconomy")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end
local H = 3600
local function hqCost(l) return E.HQ_COST[l] end
local function today(rate, away) return math.floor(math.min(rate * 0.25 * math.min(away, 8 * H), rate * 600)) end

test("the HQ price ladder the tests assume is the live one", function()
	local want = { 0, 3750, 37500, 225000, 1500000 }
	for i, v in want do assert(E.HQ_COST[i] == v, "HQ_COST[" .. i .. "] = " .. tostring(E.HQ_COST[i])) end
end)

test("ladder: HQ 2 with no apartment is HQ 3 + Studio, then HQ 4 + Loft", function()
	local n, a = P.ladder(2, 0, hqCost, 4e6)
	assert(n == 37500 + 20000 and a == 225000 + 150000, ("got %s, %s"):format(n, a))
end)
test("ladder: a Studio already owned is not charged again", function()
	local n, a = P.ladder(2, 1, hqCost, 4e6)
	assert(n == 37500 and a == 375000, ("got %s, %s"):format(n, a))
end)
test("ladder: HQ 4 with a Penthouse is HQ 5, then the spin-off", function()
	local n, a = P.ladder(4, 3, hqCost, 4e6)
	assert(n == 1500000 and a == 4e6, ("got %s, %s"):format(n, a))
end)
test("ladder: HQ 5 is the spin-off, then HQ 2 again", function()
	local n, a = P.ladder(5, 3, hqCost, 39062500)
	assert(n == 39062500 and a == 3750, ("got %s, %s"):format(n, a))
end)

test("offline: no apartment pays the old 10-minute cap", function()
	assert(P.offline(1000, 8 * H, 0, 0, 5e6, 5e6) == today(1000, 8 * H), "expected: P.offline(1000, 8 * H, 0, 0, 5e6, 5e6) == today(1000, 8 * H)")
end)
test("offline: a small next step never pays below the old cap", function()
	assert(P.offline(1000, 8 * H, 3, 0, 50000, 1e6) == 600000, "expected: P.offline(1000, 8 * H, 3, 0, 50000, 1e6) == 600000")
end)
test("offline: a Penthouse night can cover a whole spin-off", function()
	assert(P.offline(1000, 8 * H, 3, 0, 3e6, 3750) == 3e6, "expected: P.offline(1000, 8 * H, 3, 0, 3e6, 3750) == 3e6")
end)
test("offline: two hours away pays less than eight", function()
	assert(P.offline(1000, 2 * H, 3, 0, 3e6, 3750) == 1800000, "expected: P.offline(1000, 2 * H, 3, 0, 3e6, 3750) == 1800000")
end)
test("offline: a Studio's window is 2 h", function()
	assert(P.offline(1000, 8 * H, 1, 0, 3e6, 3750) == 1800000, "expected: P.offline(1000, 8 * H, 1, 0, 3e6, 3750) == 1800000")
end)
test("offline: never enough to buy two steps", function()
	local o = P.offline(10000, 8 * H, 3, 2e6, 1e6, 1.5e6)
	assert(2e6 + o < 1e6 + 1.5e6, "paid " .. o)
end)
test("offline: no time away or no income pays 0", function()
	assert(P.offline(1000, -50, 3, 0, 3e6, 3750) == 0 and P.offline(0, 8 * H, 3, 0, 3e6, 3750) == 0, "expected: P.offline(1000, -50, 3, 0, 3e6, 3750) == 0 and P.offline(0, 8 * H, 3, 0, 3e6, 3750) == 0")
end)

test("offline property over 3,000 random returns", function()
	math.randomseed(42)
	local bad = 0
	for _ = 1, 3000 do
		local rate = math.random(1, 200000)
		local away = math.random(0, 48 * H)
		local apt = math.random(0, 3)
		local nxt = math.random(1000, 5e8)
		local aft = math.random(1000, 5e8)
		local cash = math.random(0, nxt - 1)              -- you could not already afford it
		local v = P.offline(rate, away, apt, cash, nxt, aft)
		local floor = math.min(today(rate, away), math.max(0, nxt + aft - cash - 1))
		if v < 0 or cash + v >= nxt + aft or v < floor - 1 then bad += 1 end
	end
	assert(bad == 0, bad .. " bad returns: >= the old cap (unless that buys two steps), never two steps, never negative")
end)

test("the apartment gates: Studio for HQ 3, Loft for HQ 4, Penthouse for HQ 5", function()
	assert(P.aptNeeded(2) == 0 and P.aptNeeded(3) == 1 and P.aptNeeded(4) == 2 and P.aptNeeded(5) == 3, "expected: P.aptNeeded(2) == 0 and P.aptNeeded(3) == 1 and P.aptNeeded(4) == 2 and P.aptNeeded(5) == 3")
end)

return T
