--[[
	ChaseCam -- where the camera goes during a chase, as pure maths.

	WHY IT IS ITS OWN MODULE. The framing has to be tuned by looking at it, and
	a LocalScript can only be looked at inside Play, which drags in the carry,
	the offer timer, candidate stock and the delivery radius -- four systems
	that each ended a test chase before the camera could be judged. Pulling the
	maths out means the Edit-mode lab (tools/chase_lab.luau) drives THE SAME
	code the game runs, instead of a copy that drifts away from it.

	No services, no Instances, no requires: only Vector3 and CFrame arithmetic.
	That is what lets it load in Edit, in a LocalScript, and in a test.

	THE IDEA. The hunter is always behind you -- measured in a running game at
	dot(forward) = -1.00. A camera on your travel line therefore frames the one
	thing that cannot hurt you and hides the one thing that can. So the camera
	sits behind you and YAWS toward whichever side the hunter is on, by more
	as it closes. At full fear that is enough to hold it at the edge of frame
	without losing the road ahead.
]]

local ChaseCam = {}

--[[ Every number here is meant to be changed while looking at it. They are
	grouped by the question they answer. The lab writes to this table live. ]]
ChaseCam.T = {
	-- where the camera sits, at rest and at full fear
	DIST_FAR = 15,        -- studs behind when the hunter is nowhere near
	DIST_NEAR = 11,       -- ... and when it is on you
	HEIGHT_FAR = 6.5,
	HEIGHT_NEAR = 4.0,    -- lower as it closes: more ground rushing past

	-- how far the camera turns off your travel line, so the hunter is visible
	YAW_FAR = 8,          -- degrees
	YAW_NEAR = 34,

	-- the lens
	FOV_BASE = 70,
	FOV_SPEED = 14,       -- added at full carry speed
	FOV_WINDUP = 10,      -- the crouch tell WIDENS (see the note below)

	-- the yaw added on the crouch tell, so the thing about to hit you is on screen
	YAW_WINDUP = 14,      -- degrees

	-- what counts as far and near, in studs
	FEAR_FAR = 26,
	FEAR_NEAR = 6,

	SMOOTH = 0.12,        -- camera easing; lower is snappier
	SHAKE = 0.55,         -- studs at a full lunge

	--[[ Keep the camera clear of the hunter itself.

		Found in the lab: the camera sits 11-15 studs behind the player and the
		hunter ranges over 6-26, so whenever those two numbers meet, the hunter
		is BETWEEN the camera and the player. It then fills the foreground and
		hides the very thing it is chasing -- the exact opposite of the point.

		So the camera is pushed back to stay at least this far behind the
		hunter, and slid sideways so it passes beside the camera rather than
		through it. ]]
	CLEAR = 7,            -- studs the camera keeps behind the hunter
	SIDE = 4.5,           -- studs of lateral offset, so nothing walks into the lens
}

--[[ WHY THE WINDUP WIDENS INSTEAD OF TIGHTENING.

	The first version punched the lens IN on the crouch, because that is the
	film grammar for "something is about to happen". Measured on screen, it
	moved the hunter from (1056, 424) to (1102, 457) on a 434-tall viewport --
	i.e. off the bottom edge, at the exact moment the player most needs to see
	it. The tell became less visible, not more.

	So the tell now widens the lens AND adds yaw. Both push the hunter further
	into frame rather than out of it. The drama comes from the shake and the
	letterbox, which do not fight the thing they are dramatising.
]]

local function lerp(a, b, t) return a + (b - a) * t end
ChaseCam.lerp = lerp

-- 0 = safe, 1 = it is on you. `dist` nil means no hunter: no fear.
function ChaseCam.fear(dist)
	if not dist then return 0 end
	local T = ChaseCam.T
	return math.clamp((T.FEAR_FAR - dist) / (T.FEAR_FAR - T.FEAR_NEAR), 0, 1)
end

--[[ The one function. Give it the world, get back a camera.

	s = {
	  pos        Vector3  the player
	  travel     Vector3  unit, flat: the direction they are going
	  hunterPos  Vector3? where the hunter is, if there is one
	  dist       number?  studs to the hunter (the server's ChaseDist)
	  speed      number   current speed
	  carrySpeed number   the speed they can do
	  mode       string   "A" framing only, "B" framing plus beats
	  windup     boolean  the hunter is crouching to lunge
	}
	returns cf, fov, fear
]]
function ChaseCam.solve(s)
	local T = ChaseCam.T
	local fear = ChaseCam.fear(s.dist)

	local travel = s.travel or Vector3.new(0, 0, -1)
	travel = Vector3.new(travel.X, 0, travel.Z)
	travel = travel.Magnitude > 0.01 and travel.Unit or Vector3.new(0, 0, -1)

	-- which side is the hunter on? yaw that way, so it comes into frame
	local side = 1
	if s.hunterPos then
		local toH = s.hunterPos - s.pos
		local right = Vector3.new(-travel.Z, 0, travel.X)
		side = (toH:Dot(right) >= 0) and 1 or -1
	end

	local yawDeg = lerp(T.YAW_FAR, T.YAW_NEAR, fear)
	if s.mode == "B" and s.windup then yawDeg += T.YAW_WINDUP end

	local back = CFrame.Angles(0, math.rad(yawDeg * side), 0) * (-travel)
	local distBack = lerp(T.DIST_FAR, T.DIST_NEAR, fear)
	-- never let the hunter get between the camera and the player
	if s.dist then distBack = math.max(distBack, s.dist + T.CLEAR) end
	local height = lerp(T.HEIGHT_FAR, T.HEIGHT_NEAR, fear)

	-- and slide off the centre line, so it passes beside the lens, not through it
	local right = Vector3.new(-travel.Z, 0, travel.X)
	local at = s.pos + back * distBack + right * (T.SIDE * side) + Vector3.new(0, height, 0)
	local look = s.pos + travel * 6 + Vector3.new(0, 1.5, 0)

	local fov = T.FOV_BASE + T.FOV_SPEED * math.clamp((s.speed or 0) / math.max(s.carrySpeed or 16, 1), 0, 1)
	if s.mode == "B" and s.windup then fov += T.FOV_WINDUP end

	return CFrame.lookAt(at, look), fov, fear
end

return ChaseCam
