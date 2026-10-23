-- payoutbeats.spec.luau: the routine per-client payout's beats (PayoutBeats), 23 Oct 2026.
-- The animation review found the hand-over took about 2.4 s and fired six Back pops, on the
-- most repeated moment in the game. Picked mock: ui/animation-review/mp4/1-payout.mp4, panel B.
local PB = require("../../src/ReplicatedStorage/PayoutBeats")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

test("the payout is over by 1.4 s (the header promised about a second; it was 2.4 s)", function()
	local d = PB.duration()
	assert(d <= 1.4, ("%.2f s"):format(d))
	assert(d >= 1.0, ("%.2f s: a blink the player cannot read"):format(d))
end)

test("every star is in before the card leaves", function()
	local lastStarIn = PB.FLY.seconds + PB.STAR.first + 2 * PB.STAR.gap + PB.STAR.enter
	assert(lastStarIn < PB.FLY.seconds + PB.CARD.leaveAt, ("last star in at %.2f s"):format(lastStarIn))
end)

test("nothing starts from nothing", function()
	assert(PB.CARD.from >= 0.9, "card")
	assert(PB.STAR.from >= 0.9, "stars")
	assert(PB.MONEY.from >= 0.9, "money")
end)

test("UI moves stay under 300 ms", function()
	assert(PB.FLY.seconds <= 0.3, "fly")
	assert(PB.CARD.enter <= 0.3, "card in")
	assert(PB.CARD.leave <= 0.3, "card out")
	assert(PB.STAR.enter <= 0.3, "star in")
	assert(PB.MONEY.enter <= 0.3, "money in")
	assert(PB.MONEY.leave <= 0.3, "money out")
end)

return T
