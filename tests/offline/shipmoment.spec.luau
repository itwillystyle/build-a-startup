-- shipmoment.spec.luau: the first-ship celebration's beats (ShipMoment), 22 Oct 2026.
-- Luke's pick, mock A (ui/2026-10-22-celebration/mocks.html): the box lifts and glows, the
-- handoff freezes for 80 ms, the client reacts, coins fly to your cash, and the "+$X" by the
-- coins counts in step with them. It replaces the 16 Oct gold rays + tilted "SHIPPED!" stamp.
local SM = require("../../src/ReplicatedStorage/ShipMoment")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

test("the beats come in the mock's order, never on one frame", function()
	local b = SM.BEATS
	assert(b.lift == 0, "the box lifts first")
	assert(b.handoff == 0.4, "handoff at 0.4 s")
	assert(b.hitstop == 0.08, "the freeze is 80 ms")
	assert(b.react == 0.5, "the client reacts at 0.5 s")
	assert(b.coins == 0.6, "coins at 0.6 s")
	assert(b.lift < b.handoff and b.handoff + b.hitstop <= b.react and b.react < b.coins, "in order")
end)

test("the whole moment is over by 2.5 s (the slop list: nothing longer you cannot skip)", function()
	assert(SM.duration(12) <= 2.5, ("12 coins: %.2f s"):format(SM.duration(12)))
	assert(SM.duration(12) >= 1.8, "and not a blink: the mock is about 2.2 s")
end)

test("the number by the coins counts in step: each coin adds its share, the last one lands the exact total", function()
	local total, n = 975, 12
	local prev = 0
	for k = 1, n do
		local g = SM.given(total, k, n)
		assert(g > prev, ("coin %d moved the number (%d -> %d)"):format(k, prev, g))
		prev = g
	end
	assert(SM.given(total, n, n) == 975, "the last coin lands the exact total")
	assert(SM.given(total, 0, n) == 0, "before any coin: 0")
end)

test("coins that land out of order still count up and end exact (live, 22 Oct: it ended on +$275)", function()
	-- each coin's flight is 0.42-0.50 s, so coin 12 can land before coin 11; the number counts
	-- LANDINGS, never which coin it was
	local land = SM.lander(300, 12)
	local prev, lastSeen = 0, 0
	for i = 1, 12 do
		local shown, isLast = land()
		assert(shown > prev, ("landing %d moved the number up (%d -> %d)"):format(i, prev, shown))
		assert(isLast == (i == 12), "only the 12th landing is the last")
		prev, lastSeen = shown, shown
	end
	assert(lastSeen == 300, "ends on the exact total, got " .. lastSeen)
	local after = land()
	assert(after == 300, "a stray extra landing stays at the total")
end)

test("an amount smaller than the coin count never counts down and still ends exact", function()
	local prev = 0
	for k = 1, 12 do
		local g = SM.given(5, k, 12)
		assert(g >= prev, "never down")
		prev = g
	end
	assert(SM.given(5, 12, 12) == 5, "ends at 5")
end)

test("only the first ship plays it, and its number is the pay plus the tip", function()
	assert(SM.plays({ wow = true, pay = 270 }) == true, "first client")
	assert(SM.plays({ wow = false, pay = 270 }) == false, "a regular client")
	assert(SM.plays({ pay = 270 }) == false, "no wow flag")
	assert(SM.total({ pay = 270, tip = 30 }) == 300, "pay + tip")
	assert(SM.total({ pay = 270 }) == 270, "no tip")
end)

return T
