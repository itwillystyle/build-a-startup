--[[ PayoutBeats (23 Oct 2026, animation review): the routine per-client payout's beats. Pure.

	Every hand-over you give (every 10-60 s, all game long) used to take about 2.4 s and fire
	six Back pops, against the file's own promise of "about a second". The picked mock
	(ui/animation-review/mp4/1-payout.mp4, panel B) is about 1.4 s with no bounce. Times are from
	the moment the app tile leaves your hands:

	  0.00 s   the tile flies to the client (0.28 s, Quint Out, re-projected from world points)
	  0.28 s   the stars card fades in (scale 0.94 -> 1), then each star, 0.04 s apart
	  0.40 s   "+$pay" and the tip together, coins start; the counter counts with the coins
	  1.03 s   the stars card leaves (rise 12 px, fade)
	  ~1.4 s   the money label is the last thing on screen, and is gone

	The first-ship celebration (ShipMoment) is separate and unchanged.
	Tested by tests/offline/payoutbeats.spec.luau. ]]
local PayoutBeats = {}
PayoutBeats.FLY = { seconds = 0.28, arc = 50, tilt = -12 }
PayoutBeats.CARD = { from = 0.94, enter = 0.15, leaveAt = 0.75, leave = 0.2, rise = 12,
	-- 23 Oct (FINAL.md W3, W4): a billboard at the client. It rises from where the app tile lands
	-- (fromY studs over the client) to the speech bubble's height (atY: MEASURED 23 Oct on live
	-- clients, 6.00 studs over the model pivot = head 2.40 + the bubble's 3.6; a first guess of 5.1 left
	-- the card 21 px inside the bubble up close), and BillboardGui.SizeOffset lifts it `lift` of its own
	-- height so it sits above a 74 px bubble at any distance (a stud offset alone shrinks with distance)
	w = 132, h = 46, fromY = 3.4, atY = 6.0, lift = 1.4 }
PayoutBeats.STAR = { first = 0.06, gap = 0.04, from = 0.9, enter = 0.12 }
PayoutBeats.MONEY = { at = 0.40, from = 0.94, enter = 0.15, hold = 0.6, leave = 0.2, rise = 8, tipGap = 30 }
PayoutBeats.COINS = 6
-- 23 Oct: a hired coder's delivery fires every few seconds late game, so it is a whisper next to
-- your own hand-over: a small "+$X" that fades in while rising 6 px (no scale) and no coins. The
-- first version flew 3 coins and called itself silent, but every coin ticks and the last one chings
-- (HudClient coinStream): the visual judge's finding W2 (ui/animation-review/judge/FINAL.md)
PayoutBeats.CODER = { enter = 0.12, rise = 6, hold = 0.3, leave = 0.15, coins = 0 }

-- the money label is the last thing on screen
function PayoutBeats.duration()
	local m = PayoutBeats.MONEY
	return m.at + m.enter + m.hold + m.leave
end

function PayoutBeats.coderDuration()
	local c = PayoutBeats.CODER
	return c.enter + c.hold + c.leave
end

return PayoutBeats
