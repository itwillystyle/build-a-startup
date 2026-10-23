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

test("a coder's pop is under 0.6 s (it fires every few seconds late game)", function()
	local d = PB.coderDuration()
	assert(d <= 0.6, ("%.2f s"):format(d))
end)

test("a coder's pop is quieter than your own payout", function()
	assert(PB.CODER.coins < PB.COINS, "fewer coins")
	assert(PB.coderDuration() < PB.duration(), "shorter")
end)

test("the stars card rises from where the app lands to above the client's speech bubble (FINAL.md W3, W4)", function()
	-- the app tile ends ~3 studs over the client; the bubble (ClientsServer: head + 3.6) sits ~5.1; the
	-- card is pushed up a fraction of its OWN pixel height (BillboardGui.SizeOffset), so it clears a
	-- 50-74 px bubble at any distance, where a stud offset alone would not
	local C = PB.CARD
	assert(C.fromY and C.atY and C.fromY < C.atY, "it rises")
	assert(C.fromY >= 3 and C.fromY < C.atY, "starts at or above where the tile lands")
	assert(C.lift and C.lift * C.h >= 74 / 2 + C.h / 2, ("lift %.2f x %d px clears a 74 px bubble"):format(C.lift or 0, C.h or 0))
	assert(C.h == 46 and C.w == 132, "the card is 132 x 46 px, offset-sized (does not scale with distance)")
end)

test("the card's height is the bubble's MEASURED height, so the pixel lift alone clears it at any distance", function()
	-- measured live 23 Oct on four waiting clients: the bubble sits 6.00 studs over the model pivot
	-- (head 2.40 + StudsOffset 3.6), 190 x 74 px. The first guess (5.1) left the card's bottom 21 px
	-- inside the bubble with the camera close. With the card's point AT the bubble's centre, the card's
	-- bottom (lift x board height - half the board) must clear half the bubble (37 px)
	local C = PB.CARD
	assert(C.atY == 6.0, "atY " .. tostring(C.atY))
	local board = C.h + C.rise
	assert(C.lift * board - board / 2 >= 74 / 2, ("card bottom %.0f px above the bubble centre, need 37"):format(C.lift * board - board / 2))
end)

test("a coder's delivery flies no coins (23 Oct, FINAL.md W2: 3 coins every few seconds meant 3 ticks and a ching)", function()
	-- coinStream always plays a tick per coin and a ching on the last (HudClient), and asking it for
	-- 0 coins still flies 1 (math.max(1, n)); so the coder path skips it and flies none
	assert(PB.CODER.coins == 0, "coder coins: " .. tostring(PB.CODER.coins))
end)

return T
