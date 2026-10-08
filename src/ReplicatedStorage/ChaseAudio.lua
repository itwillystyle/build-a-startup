--[[
	ChaseAudio -- what a chase should SOUND like, as pure maths.

	WHY AUDIO, AND WHY IT IS NOT THE CAMERA. The camera has to stay stable: a
	shaking or swinging lens reads as the cause of the danger, and the chase
	camera has already been fixed three times for exactly that. Speed can still
	be felt without moving the picture: a wind bed that rises with your speed,
	and footsteps that get louder as the hunter closes. Sound carries the sense
	of speed and the camera keeps the frame still.

	No services, no Instances, no requires. That is what lets this load in the
	offline Lune runner, which has no `game`, so the tests prove it is pure.

	Every number is a first guess to be judged by ear in Studio. The shape of
	each curve matters more than the exact values: volume rises with speed
	(wind) and with closeness (steps), and nothing jumps.
]]

local ChaseAudio = {}

-- No combined loudness budget is enforced here. This is the step-volume
-- ceiling (stepVolume never exceeds it); the offline tests check the wind and
-- step caps together stay under 1.25.
ChaseAudio.MAX_TOTAL = 0.8

-- Used when the client has no CarrySpeed attribute yet (the walking speed the
-- game starts a carry at, before any HQ upgrade).
local DEFAULT_CARRY = 16

-- Wind: silent until the scooter is doing most of its speed, a clear bed at
-- its cruising speed, and the boost cap as the ceiling.
local WIND_FLOOR_RATIO = 0.6   -- silent at or below this share of carry speed
local WIND_BOOST_RATIO = 1.35  -- the cap is reached at carry speed x this
local WIND_AT_CARRY = 0.3
local WIND_MAX = 0.45

-- Wind pitch sweeps 0.9 -> 1.25 across 0 -> the boost ratio.
local PITCH_MIN = 0.9
local PITCH_MAX = 1.25

-- Footsteps: one step per STEP_STRIDE studs of the hunter's travel.
local STEP_STRIDE = 3.2
local STEP_MIN_INTERVAL = 0.16
local STEP_MAX_INTERVAL = 0.6
local STEP_STILL_SPEED = 1     -- below this the hunter is standing still

-- Footstep volume: quiet from far away, loud when it is on you.
local STEP_FAR = 26            -- studs; at or beyond this is the quiet floor
local STEP_NEAR = 6            -- studs; at or inside this is the loud ceiling
local STEP_QUIET = 0.1
local STEP_LOUD = 0.8

-- Smoothstep: 0 at t=0, 1 at t=1, with zero slope at both ends, so a curve
-- built from it never has a corner that the ear can hear as a click.
local function smooth(t)
	return t * t * (3 - 2 * t)
end

-- An absent or zero carry speed means the default, so a missing attribute can
-- never divide by zero or silence the wind.
local function carryOf(carrySpeed)
	if carrySpeed == nil or carrySpeed <= 0 then
		return DEFAULT_CARRY
	end
	return carrySpeed
end

--[[ Wind bed volume, 0..WIND_MAX, for the player's flat speed. ]]
function ChaseAudio.windVolume(speed, carrySpeed)
	local cs = carryOf(carrySpeed)
	local v = math.max(speed or 0, 0)
	local lo = WIND_FLOOR_RATIO * cs
	local hi = WIND_BOOST_RATIO * cs
	if v <= lo then
		return 0
	end
	if v < cs then
		return WIND_AT_CARRY * smooth((v - lo) / (cs - lo))
	end
	if v < hi then
		return WIND_AT_CARRY + (WIND_MAX - WIND_AT_CARRY) * smooth((v - cs) / (hi - cs))
	end
	return WIND_MAX
end

--[[ Wind bed pitch (PlaybackSpeed), PITCH_MIN..PITCH_MAX, monotonic in speed.
	It reaches PITCH_MAX at the boost cap, the same point the volume tops out,
	so a boost is heard as both louder and higher. ]]
function ChaseAudio.windPitch(speed, carrySpeed)
	local cs = carryOf(carrySpeed)
	local v = math.max(speed or 0, 0)
	local r = math.clamp(v / (WIND_BOOST_RATIO * cs), 0, 1)
	return PITCH_MIN + (PITCH_MAX - PITCH_MIN) * r
end

--[[ Seconds between footsteps for a hunter moving at `hunterSpeed` studs/s.
	One step per STEP_STRIDE studs, so the cadence follows its real pace. A
	hunter that is not moving makes no sound: math.huge means never. ]]
function ChaseAudio.stepInterval(hunterSpeed)
	local v = hunterSpeed or 0
	if v < STEP_STILL_SPEED then
		return math.huge
	end
	return math.clamp(STEP_STRIDE / v, STEP_MIN_INTERVAL, STEP_MAX_INTERVAL)
end

--[[ Footstep volume, STEP_QUIET..STEP_LOUD, for the hunter's distance in studs.
	Non-increasing in distance: the closer it is, the louder. A missing distance
	counts as far away, so it stays quiet rather than silent. ]]
function ChaseAudio.stepVolume(dist)
	local d = dist or math.huge
	local t = math.clamp((STEP_FAR - d) / (STEP_FAR - STEP_NEAR), 0, 1)
	return STEP_QUIET + (STEP_LOUD - STEP_QUIET) * smooth(t)
end

return ChaseAudio
