--[[
	ChaseFrame -- does a chase camera frame show the player properly? Pure maths.

	WHY IT IS IN SCREEN SPACE. The framing rules used to be written in studs
	("stay 7 studs behind"), and framing bugs kept passing them. A stud count
	says nothing about what the player sees: the same 7 studs is a comfortable
	shot at 70 FOV and a hunter filling the lens at 2 studs. So every rule here
	is measured on the projected frame: where the player's point lands (sx, sy
	in 0..1), how big the player and hunter are as a fraction of frame height,
	how far the horizon leans, and how far the camera has turned off the
	travel line.

	No services, no Instances, no requires: only Vector3 and CFrame arithmetic,
	so it loads in Edit, in a LocalScript, and in an offline test.

	CONVENTIONS (Roblox's own):
	  * Camera.FieldOfView is VERTICAL, in degrees.
	  * A camera looks down its LookVector (-Z). RightVector is screen-right,
	    UpVector is screen-up.
	  * sx runs 0..1 left to right, sy runs 0..1 TOP to bottom, centre (0.5,0.5).
]]

local ChaseFrame = {}

--[[ Every threshold lives here so the framing can be tuned in one place. Each
	is a rule on the frame, not on the world: "player inside the middle 36% of
	the width" holds at every distance and on every aspect ratio. ]]
ChaseFrame.CONTRACT = {
	PLAYER_X = 0.18,       -- |sx - 0.5| at most: the player stays near centre
	PLAYER_Y_MIN = 0.45,   -- sy band: low enough to see the road ahead,
	PLAYER_Y_MAX = 0.70,   -- high enough that the player is not at the bottom edge
	PLAYER_MIN_H = 0.09,   -- player at least 9% of frame height: readable, not a dot
	HUNTER_RANGE = 20,     -- studs: inside this the hunter must be in shot
	HUNTER_MAX_H = 0.30,   -- hunter at most 30% of frame height: visible, not in the lens
	TILT_MAX = 8,          -- degrees of horizon lean, either way
	YAW_MAX = 25,          -- degrees the camera may turn off the travel heading
	PLAYER_HEIGHT = 5,     -- studs, for the apparent-height measurement
	HUNTER_HEIGHT = 5.5,   -- studs
}

local K = ChaseFrame.CONTRACT

--[[ Projects a world point into the camera's normalised frame.

	Returns sx, sy, depth, onScreen. Behind the camera there is no meaningful
	screen position, so sx and sy come back nil and onScreen is false: callers
	must check depth before using them. ]]
function ChaseFrame.project(camCF, fovDeg, aspect, worldPos)
	local p = camCF:PointToObjectSpace(worldPos)
	local depth = -p.Z
	if depth <= 0 then
		return nil, nil, depth, false
	end

	-- FOV is vertical, so the horizontal half-extent scales with the aspect.
	local tanV = math.tan(math.rad(fovDeg) / 2)
	local tanH = tanV * aspect
	local sx = 0.5 + (p.X / depth) / tanH / 2
	local sy = 0.5 - (p.Y / depth) / tanV / 2

	local onScreen = sx >= 0 and sx <= 1 and sy >= 0 and sy <= 1
	return sx, sy, depth, onScreen
end

--[[ How tall a vertical object of `height` studs appears, as a fraction of the
	frame height. Projects the base and the top and takes the vertical gap. This
	is the number a player's eye actually uses: it falls with distance and it
	rises as something closes on the lens. Returns 0 if either end is behind the
	camera, since there is no honest size to report. ]]
function ChaseFrame.apparentHeight(camCF, fovDeg, aspect, basePos, height)
	local _, syBottom, depthBottom = ChaseFrame.project(camCF, fovDeg, aspect, basePos)
	local _, syTop, depthTop = ChaseFrame.project(camCF, fovDeg, aspect, basePos + Vector3.new(0, height, 0))
	if depthBottom <= 0 or depthTop <= 0 then
		return 0
	end
	return math.abs(syTop - syBottom)
end

--[[ Horizon lean in degrees, signed. RightVector.Y is the sine of the roll, so
	asin reads it directly. Deliberately NOT ToEulerAnglesXYZ: that decomposition
	gimbal-flips on a look-at CFrame, which is exactly what a chase camera is. ]]
function ChaseFrame.tilt(camCF)
	return math.deg(math.asin(math.clamp(camCF.RightVector.Y, -1, 1)))
end

--[[ Unsigned angle in degrees between where the camera looks (flattened onto
	the ground) and the travel heading (also flattened). Flattening means a
	camera tilted up or down does not count as turning. A zero heading has no
	direction to be off, so it reads as 0. A camera pointing straight up or
	down has no heading at all, so it reads as 90: a failure, not a pass. ]]
function ChaseFrame.yawFrom(camCF, heading)
	local look = camCF.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	local flatHead = Vector3.new(heading.X, 0, heading.Z)
	if flatHead.Magnitude < 1e-6 then
		return 0
	end
	if flatLook.Magnitude < 1e-6 then
		return 90
	end
	local c = flatLook.Unit:Dot(flatHead.Unit)
	return math.deg(math.acos(math.clamp(c, -1, 1)))
end

--[[ Checks one camera frame against the contract.

	s = { playerPos = Vector3 (HumanoidRootPart, mid-body),
	      heading = Vector3 (travel direction),
	      hunterPos = Vector3? (optional) }

	Returns { ok, failures = { readable string per broken rule }, metrics }.
	Every failure names its rule and the measured value, so a failed frame
	says what to fix without a recording. ]]
function ChaseFrame.check(camCF, fovDeg, aspect, s)
	local failures = {}
	local function fail(message)
		table.insert(failures, message)
	end

	local playerPos = s.playerPos
	local sx, sy, depth, onScreen = ChaseFrame.project(camCF, fovDeg, aspect, playerPos)
	local playerH = ChaseFrame.apparentHeight(
		camCF, fovDeg, aspect,
		playerPos - Vector3.new(0, K.PLAYER_HEIGHT / 2, 0),
		K.PLAYER_HEIGHT
	)
	local tilt = ChaseFrame.tilt(camCF)
	local yaw = ChaseFrame.yawFrom(camCF, s.heading)

	local metrics = {
		sx = sx,
		sy = sy,
		playerH = playerH,
		tilt = tilt,
		yaw = yaw,
	}

	-- 1. the player is in front of the lens and inside the frame
	if depth <= 0 then
		fail(string.format("player behind camera: depth %.1f", depth))
	elseif not onScreen then
		fail(string.format("player off screen: sx %.2f, sy %.2f", sx, sy))
	end

	-- 2 and 3 only mean something in front of the camera
	if sx then
		if math.abs(sx - 0.5) > K.PLAYER_X then
			fail(string.format("player off-centre: sx %.2f (max ±%g)", sx, K.PLAYER_X))
		end
		if sy < K.PLAYER_Y_MIN or sy > K.PLAYER_Y_MAX then
			fail(string.format("player off vertical band: sy %.2f (band %g to %g)",
				sy, K.PLAYER_Y_MIN, K.PLAYER_Y_MAX))
		end
	end

	-- 4. the player is big enough to read
	if depth > 0 and playerH < K.PLAYER_MIN_H then
		fail(string.format("player too small: %.3f of frame height (min %g)", playerH, K.PLAYER_MIN_H))
	end

	-- 5 and 6. the hunter. Inside its range it must be in shot; in shot it must
	-- not fill the lens. Outside its range it is allowed to be anywhere.
	if s.hunterPos then
		local hunterPos = s.hunterPos
		local _, _, _, hunterOn = ChaseFrame.project(camCF, fovDeg, aspect, hunterPos)
		local hunterH = ChaseFrame.apparentHeight(
			camCF, fovDeg, aspect,
			hunterPos - Vector3.new(0, K.HUNTER_HEIGHT / 2, 0),
			K.HUNTER_HEIGHT
		)
		local dist = (hunterPos - playerPos).Magnitude
		metrics.hunterOnScreen = hunterOn
		metrics.hunterH = hunterH

		if dist <= K.HUNTER_RANGE and not hunterOn then
			fail(string.format("hunter out of frame: %.1f studs from the player (within %g)",
				dist, K.HUNTER_RANGE))
		end
		if hunterOn and hunterH > K.HUNTER_MAX_H then
			fail(string.format("hunter fills the frame: %.2f of frame height (max %g)",
				hunterH, K.HUNTER_MAX_H))
		end
	end

	-- 7. the horizon is level enough that the world does not look like it is sliding
	if math.abs(tilt) > K.TILT_MAX then
		fail(string.format("horizon tilted %.1f deg (max ±%g)", tilt, K.TILT_MAX))
	end

	-- 8. the camera is still looking where the player is going
	if yaw > K.YAW_MAX then
		fail(string.format("camera yaw %.1f deg off heading (max %g)", yaw, K.YAW_MAX))
	end

	return {
		ok = #failures == 0,
		failures = failures,
		metrics = metrics,
	}
end

return ChaseFrame
