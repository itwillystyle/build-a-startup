--[[ chasespeed.spec.luau -- the speed lines, tested without Play.

	The lines are only allowed to say one thing: "you are going fast". So the
	properties that must hold are: nothing shows at ordinary running speed, the
	amount rises monotonically with speed, boost is reached at the same speed the
	camera's boost is, and no streak can ever be drawn over the centre of the
	screen where the player is.
]]
local S = require("../../src/ReplicatedStorage/ChaseSpeed")
local C = require("../../src/ReplicatedStorage/ChaseCam")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

-- sweep the speed from 0 to 2x carry in small steps, carry = 20
local function sweep(carry)
	local out = {}
	for i = 0, 400 do
		local speed = (i / 200) * carry
		table.insert(out, { speed = speed, k = S.intensity(speed, carry) })
	end
	return out
end

test("zero at and below 0.9 x carry speed", function()
	local v1 = S.intensity(0.9 * 16, 16)
	assert(v1 == 0, ("intensity at 0.9x carry was %.6f, expected 0"):format(v1))
	local v2 = S.intensity(0.5 * 16, 16)
	assert(v2 == 0, ("intensity at 0.5x carry was %.6f, expected 0"):format(v2))
	local v3 = S.intensity(0, 16)
	assert(v3 == 0, ("intensity at standstill was %.6f, expected 0"):format(v3))
end)

test("the ramp lands at 0.45 at 1.15 x carry speed", function()
	local v = S.intensity(1.15 * 16, 16)
	assert(math.abs(v - 0.45) < 1e-9, ("intensity at 1.15x carry was %.6f, expected 0.45"):format(v))
end)

test("full at and above boost", function()
	local at = S.intensity(S.BOOST * 16, 16)
	assert(at == 1, ("intensity at boost was %.6f, expected 1"):format(at))
	local above = S.intensity(2 * 16, 16)
	assert(above == 1, ("intensity at 2x carry was %.6f, expected 1"):format(above))
	local way = S.intensity(1e9, 16)
	assert(way == 1, ("intensity at 1e9 was %.6f, expected 1"):format(way))
end)

test("always within 0..1 across a sweep", function()
	for _, p in sweep(20) do
		assert(p.k >= 0 and p.k <= 1, ("intensity %.6f outside 0..1 at speed %.4f"):format(p.k, p.speed))
	end
	assert(S.intensity(-5, 16) == 0, ("negative speed gave %.6f, expected 0"):format(S.intensity(-5, 16)))
end)

test("monotonic non-decreasing across a sweep", function()
	local prev = -1
	for _, p in sweep(20) do
		assert(p.k >= prev - 1e-12, ("intensity fell from %.6f to %.6f at speed %.4f"):format(prev, p.k, p.speed))
		prev = p.k
	end
end)

test("nil or zero carry speed is safe and means 16", function()
	local base = S.intensity(20, 16)
	local fromNil = S.intensity(20, nil)
	local fromZero = S.intensity(20, 0)
	assert(fromNil == base, ("nil carry gave %.6f, expected the 16 value %.6f"):format(fromNil, base))
	assert(fromZero == base, ("zero carry gave %.6f, expected the 16 value %.6f"):format(fromZero, base))
	local bad = S.intensity(nil, 16)
	assert(bad == 0, ("nil speed gave %.6f, expected 0"):format(bad))
end)

test("streaks: 0 at zero intensity, max at full", function()
	local lo = S.streaks(0, 24)
	local hi = S.streaks(1, 24)
	assert(lo == 0, ("streaks(0, 24) was %s, expected 0"):format(tostring(lo)))
	assert(hi == 24, ("streaks(1, 24) was %s, expected 24"):format(tostring(hi)))
end)

test("streaks: always an integer within 0..max, and monotonic", function()
	local prev = -1
	for i = 0, 100 do
		local k = i / 100
		local n = S.streaks(k, 24)
		assert(n == math.floor(n), ("streaks(%.2f) = %s is not an integer"):format(k, tostring(n)))
		assert(n >= 0 and n <= 24, ("streaks(%.2f) = %d outside 0..24"):format(k, n))
		assert(n >= prev, ("streaks fell from %d to %d at intensity %.2f"):format(prev, n, k))
		prev = n
	end
end)

test("BOOST matches ChaseCam.DIR.BOOST", function()
	assert(S.BOOST == C.DIR.BOOST,
		("ChaseSpeed.BOOST = %s but ChaseCam.DIR.BOOST = %s"):format(tostring(S.BOOST), tostring(C.DIR.BOOST)))
end)

test("RING is 0.62 of the half-diagonal", function()
	assert(S.RING == 0.62, ("RING was %s, expected 0.62"):format(tostring(S.RING)))
end)

test("edgeDistance: right edge and top edge of a 1280x720 screen", function()
	local right = S.edgeDistance(640, 360, 0)
	assert(math.abs(right - 640) < 1e-6, ("edge at 0 deg was %.4f, expected 640"):format(right))
	local down = S.edgeDistance(640, 360, 90)
	assert(math.abs(down - 360) < 1e-6, ("edge at 90 deg was %.4f, expected 360"):format(down))
end)

test("band: every ray has room on every aspect, because the ring is per-ray", function()
	--[[ The half-diagonal ring left 14/24 rays on 16:9, 10 on a landscape phone
		and 2 on Studio's ultra-wide viewport. The per-ray ring must leave all
		24 on every one of them. ]]
	for _, scr in ipairs({ { 1280, 720 }, { 844, 390 }, { 390, 844 }, { 1530, 255 }, { 713, 418 } }) do
		local hw, hh = scr[1] / 2, scr[2] / 2
		local rays = 0
		for i = 0, 23 do
			if S.band(hw, hh, i * 15) then rays += 1 end
		end
		assert(rays == 24, ("%dx%d gave room to only %d of 24 rays"):format(scr[1], scr[2], rays))
	end
end)

test("band: the inner end is exactly RING of the way to that ray's own edge", function()
	local hw, hh = 640, 360
	for a = 0, 345, 15 do
		local inner, outer = S.band(hw, hh, a)
		assert(inner and outer, ("ray %d deg has no band"):format(a))
		assert(math.abs(inner - S.RING * outer) < 1e-6,
			("ray %d deg starts at %.3f, expected %.3f"):format(a, inner, S.RING * outer))
	end
end)

test("band: the player's framing zone is always clear of streaks", function()
	--[[ ChaseFrame keeps the player within +-18% of centre horizontally and
		45-70% from the top. Every streak must start outside that box. ]]
	for _, scr in ipairs({ { 1280, 720 }, { 844, 390 }, { 1530, 255 } }) do
		local hw, hh = scr[1] / 2, scr[2] / 2
		for a = 0, 345, 15 do
			local inner = S.band(hw, hh, a)
			local r = math.rad(a)
			local x, y = math.cos(r) * inner, math.sin(r) * inner
			local insideBox = math.abs(x) <= 0.18 * scr[1] and (y >= -0.05 * scr[2] and y <= 0.20 * scr[2])
			assert(not insideBox, ("%dx%d ray %d deg starts inside the player zone"):format(scr[1], scr[2], a))
		end
	end
end)

test("band: degenerate screen sizes give no band", function()
	assert(S.band(0, 360, 0) == nil, "a zero-width screen should have no band")
	assert(S.band(640, 0, 0) == nil, "a zero-height screen should have no band")
end)

return T
