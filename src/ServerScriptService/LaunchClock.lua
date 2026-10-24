--[[ LaunchClock (24 Oct 2026): LAUNCH!'s half-pay auto-launch clock, pausable. Pure.

	One instruction at a time, rule A (Luke delegated the pick; ui/animation-review/judge/
	ONE-INSTRUCTION-OPTIONS.md): while a button you can press or the job in your hands is on
	screen, LAUNCH! folds to a small "APP READY" chip. A hidden button with a ticking half-pay
	timer would be worse than today, so the clock stands still while LAUNCH is folded that way
	(OneVoice.launchHeld). It was a fixed task.delay(60) in SiliconCore's offerProduct.

	The server owns it (one per pending app, in the session). The pause reads only server state,
	and the client only draws the two attributes the server sets from it, so a client cannot
	pause it by lying. Pausing never pays anything: it only keeps the full-pay window open. It
	is still capped (PAUSE_MAX in all, per app) so a carry you never hand over, or an AFK at the
	laptop, cannot stall the auto-launch: it fires at most SECONDS + PAUSE_MAX after the app is
	ready. Tested by tests/offline/launchclock.spec.luau. ]]
local LaunchClock = {}

LaunchClock.SECONDS = 60
LaunchClock.PAUSE_MAX = 60

function LaunchClock.new(now, seconds, pauseMax)
	return { left = seconds or LaunchClock.SECONDS, at = now, paused = false, pausedFor = 0,
		pauseMax = pauseMax or LaunchClock.PAUSE_MAX }
end

-- seconds of `dt` (since the last update) that ran the clock down, and the pause they used
local function split(c, dt)
	if not c.paused then return dt, 0 end
	local room = math.max(0, c.pauseMax - c.pausedFor)
	if dt <= room then return 0, dt end
	return dt - room, room
end

-- bring the clock to `now`, then pause it or not. True when the paused state changed (republish).
function LaunchClock.update(c, now, wantPause)
	local ran, held = split(c, math.max(0, now - c.at))
	c.left -= ran
	c.pausedFor += held
	c.at = now
	local paused = wantPause == true and c.pausedFor < c.pauseMax
	local changed = paused ~= c.paused
	c.paused = paused
	return changed
end

function LaunchClock.left(c, now)
	local ran = split(c, math.max(0, now - c.at))
	return c.left - ran
end

function LaunchClock.due(c, now)
	return LaunchClock.left(c, now) <= 0
end

function LaunchClock.paused(c)
	return c.paused
end

-- the server time it fires at while running; nil while paused (the chip shows the frozen seconds)
function LaunchClock.autoAt(c, now)
	if c.paused then return nil end
	return now + LaunchClock.left(c, now)
end

return LaunchClock
