--[[ chaseaudio.spec.luau -- the chase's sound, tested as maths.

	ChaseAudio is pure, so every property the ear depends on can be checked
	here: the endpoints it is tuned to, that it rises and falls the right way,
	that nothing jumps, and that the caps hold. What these tests cannot tell is
	whether a sound is pleasant. That is a Studio listen, and the asset ids are
	not verified until someone hears them.

	Every assert carries a message with the measured value, so a failure reads
	as a number, not a bare "assertion failed".
]]
local A = require("../../src/ReplicatedStorage/ChaseAudio")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local EPS = 1e-9
local function near(got, want, what)
	assert(math.abs(got - want) <= EPS, ("%s: got %.9f, want %.9f"):format(what, got, want))
end

-- A sweep of `n` evenly spaced points from a to b, inclusive.
local function sweep(a, b, n)
	local out = {}
	for i = 0, n do
		table.insert(out, a + (b - a) * i / n)
	end
	return out
end

-- ================= windVolume =================

test("windVolume is silent at and below 0.6 x carry speed", function()
	near(A.windVolume(0, 16), 0, "windVolume(0, 16)")
	near(A.windVolume(5, 16), 0, "windVolume(5, 16)")
	near(A.windVolume(9.6, 16), 0, "windVolume(9.6 = 0.6 x 16, 16)")
end)

test("windVolume starts rising just above the silent floor", function()
	local v = A.windVolume(9.6 + 0.01, 16)
	assert(v > 0 and v < 0.01, ("just above floor: windVolume(9.61, 16) = %.6f, want (0, 0.01)"):format(v))
end)

test("windVolume is 0.3 at carry speed", function()
	near(A.windVolume(16, 16), 0.3, "windVolume(16, 16)")
end)

test("windVolume reaches the 0.45 cap at the boost ceiling (1.35 x carry)", function()
	near(A.windVolume(16 * 1.35, 16), 0.45, "windVolume(21.6, 16)")
end)

test("windVolume never exceeds 0.45, even at absurd speed", function()
	local v = A.windVolume(1e6, 16)
	near(v, 0.45, "windVolume(1e6, 16) clamped")
	assert(v <= 0.45, ("cap: windVolume(1e6, 16) = %.6f, want <= 0.45"):format(v))
end)

test("windVolume is monotone non-decreasing across a speed sweep", function()
	local prev = -1
	for _, s in sweep(0, 40, 400) do
		local v = A.windVolume(s, 16)
		assert(v >= prev - EPS, ("monotone: windVolume(%.3f) = %.6f fell below previous %.6f"):format(s, v, prev))
		prev = v
	end
end)

test("windVolume stays inside 0..0.45 across a speed sweep", function()
	for _, s in sweep(0, 60, 300) do
		local v = A.windVolume(s, 16)
		assert(v >= 0 and v <= 0.45 + EPS, ("range: windVolume(%.3f) = %.6f, want 0..0.45"):format(s, v))
	end
end)

test("windVolume rises smoothly: no step bigger than 0.01 per 0.1 stud", function()
	local prev = A.windVolume(0, 16)
	local worst = 0
	for _, s in sweep(0, 40, 400) do
		local v = A.windVolume(s, 16)
		worst = math.max(worst, math.abs(v - prev))
		prev = v
	end
	assert(worst <= 0.01, ("smooth: largest 0.1-stud step = %.6f, want <= 0.01"):format(worst))
end)

test("windVolume with a nil or zero carry speed uses 16", function()
	near(A.windVolume(16, nil), A.windVolume(16, 16), "windVolume(16, nil) vs 16")
	near(A.windVolume(16, 0), A.windVolume(16, 16), "windVolume(16, 0) vs 16")
	near(A.windVolume(16, -4), A.windVolume(16, 16), "windVolume(16, -4) vs 16")
end)

test("windVolume with a nil speed is silent, not an error", function()
	near(A.windVolume(nil, 16), 0, "windVolume(nil, 16)")
end)

test("windVolume scales with carry speed: a faster carry is silent at a higher speed", function()
	-- At carry 24 the floor is 0.6 x 24 = 14.4, so 9.6 studs/s is still silent.
	near(A.windVolume(9.6, 24), 0, "windVolume(9.6, 24)")
	near(A.windVolume(24, 24), 0.3, "windVolume(24, 24)")
end)

-- ================= windPitch =================

test("windPitch is 0.9 at rest", function()
	near(A.windPitch(0, 16), 0.9, "windPitch(0, 16)")
end)

test("windPitch reaches 1.25 at the boost ceiling", function()
	near(A.windPitch(16 * 1.35, 16), 1.25, "windPitch(21.6, 16)")
end)

test("windPitch is clamped to 1.25 at absurd speed", function()
	local p = A.windPitch(1e6, 16)
	assert(p <= 1.25 + EPS, ("clamp: windPitch(1e6, 16) = %.6f, want <= 1.25"):format(p))
	near(p, 1.25, "windPitch(1e6, 16) clamped")
end)

test("windPitch stays inside 0.9..1.25 across a sweep", function()
	for _, s in sweep(0, 60, 300) do
		local p = A.windPitch(s, 16)
		assert(p >= 0.9 - EPS and p <= 1.25 + EPS, ("range: windPitch(%.3f) = %.6f, want 0.9..1.25"):format(s, p))
	end
end)

test("windPitch is monotone non-decreasing across a sweep", function()
	local prev = -1
	for _, s in sweep(0, 40, 400) do
		local p = A.windPitch(s, 16)
		assert(p >= prev - EPS, ("monotone: windPitch(%.3f) = %.6f fell below previous %.6f"):format(s, p, prev))
		prev = p
	end
end)

test("windPitch with a nil or zero carry speed uses 16", function()
	near(A.windPitch(10, nil), A.windPitch(10, 16), "windPitch(10, nil) vs 16")
	near(A.windPitch(10, 0), A.windPitch(10, 16), "windPitch(10, 0) vs 16")
end)

test("windPitch with a nil speed is the resting pitch", function()
	near(A.windPitch(nil, 16), 0.9, "windPitch(nil, 16)")
end)

-- ================= stepInterval =================

test("stepInterval is 3.2 / speed at ordinary chase speeds", function()
	near(A.stepInterval(16), 0.2, "stepInterval(16)")
end)

test("stepInterval is math.huge for a stationary hunter (speed 0)", function()
	assert(A.stepInterval(0) == math.huge, ("stationary: stepInterval(0) = %s, want math.huge"):format(tostring(A.stepInterval(0))))
end)

test("stepInterval is math.huge below 1 stud/s, so a crawling hunter is silent", function()
	assert(A.stepInterval(0.5) == math.huge, ("crawl: stepInterval(0.5) = %s, want math.huge"):format(tostring(A.stepInterval(0.5))))
	assert(A.stepInterval(0.99) == math.huge, ("crawl: stepInterval(0.99) = %s, want math.huge"):format(tostring(A.stepInterval(0.99))))
end)

test("stepInterval with a nil speed is silent", function()
	assert(A.stepInterval(nil) == math.huge, ("nil: stepInterval(nil) = %s, want math.huge"):format(tostring(A.stepInterval(nil))))
end)

test("stepInterval clamps to 0.16 at a very fast hunter", function()
	near(A.stepInterval(100), 0.16, "stepInterval(100) clamp min")
end)

test("stepInterval clamps to 0.6 at the slowest moving hunter", function()
	near(A.stepInterval(1), 0.6, "stepInterval(1) clamp max")
	near(A.stepInterval(5), 0.6, "stepInterval(5) clamp max")
end)

test("stepInterval times speed is the 3.2-stud stride inside the clamp band", function()
	for _, v in ipairs({ 5.5, 8, 12, 16, 19.5 }) do
		local stride = A.stepInterval(v) * v
		assert(math.abs(stride - 3.2) <= 1e-9, ("stride at speed %.2f: interval x speed = %.9f, want 3.2"):format(v, stride))
	end
end)

test("stepInterval is monotone non-increasing as the hunter speeds up", function()
	local prev = math.huge
	for _, v in sweep(1, 40, 390) do
		local i = A.stepInterval(v)
		assert(i <= prev + EPS, ("monotone: stepInterval(%.3f) = %.6f rose above %.6f"):format(v, i, prev))
		prev = i
	end
end)

-- ================= stepVolume =================

test("stepVolume is 0.1 at 26 studs (the quiet floor)", function()
	near(A.stepVolume(26), 0.1, "stepVolume(26)")
end)

test("stepVolume is 0.8 at 6 studs (the loud ceiling)", function()
	near(A.stepVolume(6), 0.8, "stepVolume(6)")
end)

test("stepVolume holds the 0.1 floor beyond 26 studs", function()
	near(A.stepVolume(30), 0.1, "stepVolume(30)")
	near(A.stepVolume(500), 0.1, "stepVolume(500)")
end)

test("stepVolume holds the 0.8 ceiling inside 6 studs", function()
	near(A.stepVolume(3), 0.8, "stepVolume(3)")
	near(A.stepVolume(0), 0.8, "stepVolume(0)")
end)

test("stepVolume is 0.45 at the midpoint, 16 studs", function()
	near(A.stepVolume(16), 0.45, "stepVolume(16) midpoint")
end)

test("stepVolume stays inside 0..0.8 across a distance sweep", function()
	for _, d in sweep(0, 60, 300) do
		local v = A.stepVolume(d)
		assert(v >= 0 and v <= 0.8 + EPS, ("range: stepVolume(%.3f) = %.6f, want 0..0.8"):format(d, v))
	end
end)

test("stepVolume is monotone non-increasing: closer is never quieter", function()
	local prev = math.huge
	for _, d in sweep(0, 60, 600) do
		local v = A.stepVolume(d)
		assert(v <= prev + EPS, ("monotone: stepVolume(%.3f) = %.6f rose above %.6f"):format(d, v, prev))
		prev = v
	end
end)

test("stepVolume rises smoothly: no step bigger than 0.02 per 0.1 stud", function()
	local prev = A.stepVolume(0)
	local worst = 0
	for _, d in sweep(0, 40, 400) do
		local v = A.stepVolume(d)
		worst = math.max(worst, math.abs(v - prev))
		prev = v
	end
	assert(worst <= 0.02, ("smooth: largest 0.1-stud step = %.6f, want <= 0.02"):format(worst))
end)

test("stepVolume with a nil distance is the quiet floor, not an error", function()
	near(A.stepVolume(nil), 0.1, "stepVolume(nil)")
	near(A.stepVolume(math.huge), 0.1, "stepVolume(math.huge)")
end)

-- ================= the caps together =================

test("MAX_TOTAL is the 0.8 step ceiling", function()
	assert(A.MAX_TOTAL == 0.8, ("MAX_TOTAL = %s, want 0.8"):format(tostring(A.MAX_TOTAL)))
end)

test("the wind and step ceilings together stay within 1.25", function()
	local wind = A.windVolume(1e6, 16)
	local step = A.stepVolume(0)
	assert(wind <= 0.45 + EPS, ("wind ceiling: windVolume(1e6) = %.6f, want <= 0.45"):format(wind))
	assert(step <= A.MAX_TOTAL + EPS, ("step ceiling: stepVolume(0) = %.6f, want <= MAX_TOTAL %.2f"):format(step, A.MAX_TOTAL))
	assert(wind + step <= 1.25 + EPS, ("combined: wind %.6f + step %.6f = %.6f, want <= 1.25"):format(wind, step, wind + step))
end)

test("the module exposes exactly the four curves and the cap", function()
	assert(type(A.windVolume) == "function", ("windVolume is a %s"):format(type(A.windVolume)))
	assert(type(A.windPitch) == "function", ("windPitch is a %s"):format(type(A.windPitch)))
	assert(type(A.stepInterval) == "function", ("stepInterval is a %s"):format(type(A.stepInterval)))
	assert(type(A.stepVolume) == "function", ("stepVolume is a %s"):format(type(A.stepVolume)))
	assert(type(A.MAX_TOTAL) == "number", ("MAX_TOTAL is a %s"):format(type(A.MAX_TOTAL)))
end)

return T
