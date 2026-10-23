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
PayoutBeats.CARD = { from = 0.94, enter = 0.15, leaveAt = 0.75, leave = 0.2, rise = 12 }
PayoutBeats.STAR = { first = 0.06, gap = 0.04, from = 0.9, enter = 0.12 }
PayoutBeats.MONEY = { at = 0.40, from = 0.94, enter = 0.15, hold = 0.6, leave = 0.2, rise = 8, tipGap = 30 }
PayoutBeats.COINS = 6
-- 23 Oct: a hired coder's delivery fires every few seconds late game, so it is a whisper next to
-- your own hand-over: a small "+$X" that fades in while rising 6 px (no scale), 3 coins, no sound
PayoutBeats.CODER = { enter = 0.12, rise = 6, hold = 0.3, leave = 0.15, coins = 3 }

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
