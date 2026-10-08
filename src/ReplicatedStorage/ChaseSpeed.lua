--[[
	ChaseSpeed -- how many speed lines a carry shows, and where they may sit, as pure maths.

	WHY THIS IS NOT THE CAMERA. The chase camera is tuned to stay still, so the
	energy has to come from things passing through the frame. Speed lines are
	that: thin streaks at the screen edge that move outward while you run. They
	never touch the camera, and they never cover the centre, which is where the
	player's own character is.

	No services, no Instances, no requires: only numbers. That is what lets
	tests/offline/chasespeed.spec.luau check the ramp and the geometry without Play.
]]

local ChaseSpeed = {}

-- Must equal ChaseCam.DIR.BOOST. The spec asserts the two match, so that the
-- lines and the boost always switch on at the same speed.
local BOOST = 1.35
ChaseSpeed.BOOST = BOOST

--[[ The share of the half-diagonal, from the screen centre, inside which no
	streak may ever be drawn. The centre belongs to the player. ]]
ChaseSpeed.RING = 0.62  -- fraction of the way from the centre to the edge, per ray

-- Ramp anchors, as multiples of the carry speed.
local FLOOR = 0.9      -- at or below this there are no lines at all
local MID = 1.15       -- where the first ramp lands, at MID_LEVEL
local MID_LEVEL = 0.45 -- so ordinary scooter wobble stays quiet

-- Used when the carry speed is missing or unusable. Matches the walk speed.
local DEFAULT_CARRY = 16

-- A ray with less room than this between the ring and the screen edge gets
-- no streak. Anything thinner reads as a smudge, not a line.
local MIN_BAND = 24

local function smooth(t)
	if t <= 0 then return 0 end
	if t >= 1 then return 1 end
	return t * t * (3 - 2 * t) -- smoothstep: eases in and out, no kink at the joins
end

-- speed and carrySpeed are studs per second. Returns 0..1.
function ChaseSpeed.intensity(speed, carrySpeed)
	local carry = DEFAULT_CARRY
	if type(carrySpeed) == "number" and carrySpeed > 0 then
		carry = carrySpeed
	end
	if type(speed) ~= "number" or speed ~= speed or speed <= 0 then
		return 0
	end

	local r = speed / carry
	if r <= FLOOR then return 0 end
	-- the epsilon is float noise: 1.35 * 16 / 16 can land a hair under BOOST,
	-- and that must still read as fully boosting, not 0.99999999
	if r >= BOOST - 1e-9 then return 1 end
	if r <= MID then
		return MID_LEVEL * smooth((r - FLOOR) / (MID - FLOOR))
	end
	return MID_LEVEL + (1 - MID_LEVEL) * smooth((r - MID) / (BOOST - MID))
end

-- How many of the maxStreaks to show. Rounded, so 0 and maxStreaks are exact.
function ChaseSpeed.streaks(intensity, maxStreaks)
	local k = intensity
	if type(k) ~= "number" or k ~= k then k = 0 end
	if k < 0 then k = 0 end
	if k > 1 then k = 1 end
	local max = 0
	if type(maxStreaks) == "number" and maxStreaks > 0 then
		max = math.floor(maxStreaks)
	end
	return math.floor(k * max + 0.5)
end

-- Distance in pixels from the screen centre to the screen edge, along a ray at
-- angleDeg. Angles follow Frame.Rotation: 0 is rightwards, positive is clockwise.
function ChaseSpeed.edgeDistance(halfW, halfH, angleDeg)
	local rad = math.rad(angleDeg)
	local c = math.abs(math.cos(rad))
	local s = math.abs(math.sin(rad))
	local d = math.huge
	if c > 1e-9 then d = math.min(d, halfW / c) end
	if s > 1e-9 then d = math.min(d, halfH / s) end
	return d
end

--[[ The stretch a streak on this ray may occupy: from the ring to the edge.
	Returns inner, outer in pixels from the centre, or nil when the ray has no
	room (a 16:9 screen's top and bottom middles sit inside the ring, so they
	never get streaks). The client offsets by half a streak's length so that
	the streak's inner end, not its centre, is what stops at the ring. ]]
function ChaseSpeed.band(halfW, halfH, angleDeg)
	if halfW <= 0 or halfH <= 0 then return nil end
	--[[ PER-RAY ring: each ray starts RING of the way to ITS OWN edge.

		The first version measured the ring against the half-diagonal, a single
		circle. On a 16:9 screen the top and bottom middles sit inside that
		circle, so only 14 of 24 rays had room; on a landscape phone 10; on
		Studio's ultra-wide viewport 2. The streaks appeared at the far left
		and right and almost nowhere else.

		Scaling the ring by each ray's own edge distance makes the clear centre
		a scaled copy of the screen rectangle instead of a circle. Every ray
		gets the outer (1 - RING) of its length on any aspect, and the centre
		the player occupies stays just as clear. ]]
	local outer = ChaseSpeed.edgeDistance(halfW, halfH, angleDeg)
	local inner = ChaseSpeed.RING * outer
	if outer - inner < MIN_BAND then return nil end
	return inner, outer
end

return ChaseSpeed
