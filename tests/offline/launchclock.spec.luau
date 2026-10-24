-- launchclock.spec.luau: LAUNCH!'s half-pay clock stands still while LAUNCH is folded away.
-- 24 Oct (one instruction, rule A; ui/animation-review/judge/ONE-INSTRUCTION-OPTIONS.md): the
-- 60 s auto-launch kept ticking while the job in your hands hid LAUNCH, which would hide a
-- ticking half-pay timer. Now the clock pauses while you are mid-job, at most PAUSE_MAX in all.
local C = require("../../src/ServerScriptService/LaunchClock")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local function near(a, b) return math.abs(a - b) < 1e-6 end

test("hands free: it fires 60 s after the app is ready, not before", function()
	local c = C.new(100)
	assert(C.SECONDS == 60 and C.PAUSE_MAX == 60, "the numbers: 60 s clock, 60 s of pause at most")
	for now = 100.25, 159.75, 0.25 do
		C.update(c, now, false)
		assert(not C.due(c, now), "fired early at " .. (now - 100) .. " s")
	end
	C.update(c, 160, false)
	assert(C.due(c, 160), "not due at 60 s")
end)

test("a 30 s job at 10 s: 50 s left after it, fires at 90 s", function()
	local c = C.new(0)
	C.update(c, 10, false)
	assert(C.update(c, 10, true) == true, "starting the pause is a change")
	assert(C.paused(c), "paused while mid-job")
	for now = 11, 40 do C.update(c, now, true) end
	assert(near(C.left(c, 40), 50), "left after the job: " .. C.left(c, 40))
	assert(C.update(c, 40, false) == true, "ending the pause is a change")
	C.update(c, 89.5, false)
	assert(not C.due(c, 89.5), "fired before 90 s")
	C.update(c, 90, false)
	assert(C.due(c, 90), "not due at 90 s")
end)

test("update only reports a change when paused flips", function()
	local c = C.new(0)
	assert(C.update(c, 1, false) == false, "running -> running is no change")
	assert(C.update(c, 2, true) == true, "running -> paused is a change")
	assert(C.update(c, 3, true) == false, "paused -> paused is no change")
end)

test("busy forever: the pause runs out and it fires by 120 s (an AFK carry cannot stall it)", function()
	local c = C.new(0)
	local fired
	for now = 0.25, 200, 0.25 do
		C.update(c, now, true)
		if C.due(c, now) then fired = now break end
	end
	assert(fired and fired <= 120 + 1e-6 and fired >= 120 - 0.25, "fired at " .. tostring(fired))
	assert(not C.paused(c), "past the cap it shows as running")
end)

test("one long busy update charges the overflow past the cap to the clock", function()
	local c = C.new(0)
	C.update(c, 0, true)
	C.update(c, 100, true)        -- 100 s busy in one step: 60 s paused, 40 s ran
	assert(near(C.left(c, 100), 20), "left: " .. C.left(c, 100))
end)

test("left counts down live between updates while running, stands still while paused", function()
	local c = C.new(0)
	assert(near(C.left(c, 5), 55), "running: 55 s left at 5 s")
	C.update(c, 5, true)
	assert(near(C.left(c, 25), 55), "paused: still 55 s at 25 s")
	assert(C.autoAt(c, 25) == nil, "no fire time while paused")
	C.update(c, 25, false)
	assert(near(C.autoAt(c, 25), 80), "fires at 80 s after the pause")
end)

test("the pause allowance is spent for good: a second job gets only what is left", function()
	local c = C.new(0)
	C.update(c, 0, true)
	C.update(c, 50, true)         -- 50 of 60 s used
	C.update(c, 50, false)
	C.update(c, 60, true)
	C.update(c, 80, true)         -- only 10 more s pause, 10 s ran
	assert(near(C.left(c, 80), 60 - 10 - 10), "left: " .. C.left(c, 80))
end)

return T
