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
	--[[ ... but never further back than this. Keeping a distant hunter in shot
		by falling back with it put the camera 48 studs behind the player, who
		became a dot you cannot steer. Past this the AIM holds the hunter on
		screen (HOLD_MAX) instead of the camera retreating to find it. ]]
	DIST_MAX = 22,
	SIDE = 4.5,           -- studs of lateral offset, so nothing walks into the lens

	--[[ The hunter is never allowed further than this off the centre of frame.

		"Keep it on screen the whole time" has to be a constraint, not a curve
		that happens to work. Measured before this existed: the hunter drifted
		from 30 degrees off axis at 4 studs to 46 at 30, and left the frame
		entirely at 40 -- so the one moment it is far enough to feel safe was
		the moment you lost sight of it.

		Now the look direction is rotated toward the hunter by whatever the
		excess is, so it sits at HOLD_MAX at worst. 40 degrees is inside the
		horizontal half-angle of a 70 FOV on any normal screen, so it is on
		screen at every distance, on every aspect. ]]
	HOLD_MAX = 40,

	--[[ ...but you come first. Holding a hunter that is BEHIND the camera
		swings the aim right round: measured at 26 studs the player sat 62
		degrees off centre, and by 34 it was 102 -- off screen, steering blind.
		No framing is worth losing the thing you are steering, so the turn
		toward the hunter is clamped by this. Past the point where both fit,
		the hunter leaves frame and the distance readout carries it instead,
		which is also the band (beyond ChaseRules.FAR = 20) where it is
		sprinting to catch up rather than able to strike. ]]
	PLAYER_MAX = 34,

	--[[ MODE "C": the movie chase.

		A and B answer "how much control does the camera take". This answers a
		different question -- how the chase FEELS. In a filmed chase the camera
		is not bolted to the car, it is a second vehicle: it swings wide on
		corners, falls behind under acceleration, and reels the gap back in on
		the straights. A camera that springs to a computed point every frame
		cannot do any of that, which is why A reads as locked rather than
		trailing.

		So C keeps A's visibility constraints and changes three things: it
		rides much lower so the ground rushes past, it sits closer, and it is
		given mass -- see ChaseCam.follow. ]]
	MOVIE = {
		DIST_FAR = 12,
		DIST_NEAR = 8.5,
		HEIGHT_FAR = 3.4,   -- near ground level: the road does the speed work
		HEIGHT_NEAR = 2.4,
		--[[ Measured: at ACCEL 42 / DAMP 6.2 the camera tracked so tightly that
			peak bank was 4.0 degrees against a 7 degree cap -- half a degree
			more than mode A's resting tilt, i.e. invisible. A chase camera
			banks because it is being thrown around, so it has to be allowed to
			be thrown around: looser spring, and roll that actually responds to
			the sideways speed it builds. ]]
		ACCEL = 30,         -- how hard the camera chases its mark
		DAMP = 4.4,         -- how much it resists overshoot (lower = looser)
		LAG_MAX = 11,       -- studs it is allowed to fall behind
		ROLL = 11,          -- degrees it banks into a turn
		ROLL_RATE = 4.5,
		ROLL_PER_SPEED = 1.1,   -- degrees of bank per stud/s of sideways drift
		--[[ A filmed chase is not shot from directly behind -- that is a
			bumper cam, and with a pursuer on your heels it just fills the
			frame with the pursuer's back. Measured: at a 9-stud gap the
			hunter sat 4.5 studs from the lens and 14 degrees off centre,
			eclipsing the runner completely.

			So C rides well off the centre line: a three-quarter tracking
			shot where the two of them are separated in depth, which is how
			you read a gap closing at all. ]]
		SIDE = 10.5,
	},
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
	local M = (s.mode == "C") and T.MOVIE or nil
	local distBack = lerp(M and M.DIST_FAR or T.DIST_FAR, M and M.DIST_NEAR or T.DIST_NEAR, fear)
	-- never let the hunter get between the camera and the player
	if s.dist then distBack = math.clamp(s.dist + T.CLEAR, distBack, T.DIST_MAX) end
	local height = lerp(M and M.HEIGHT_FAR or T.HEIGHT_FAR, M and M.HEIGHT_NEAR or T.HEIGHT_NEAR, fear)

	-- and slide off the centre line, so it passes beside the lens, not through it
	local right = Vector3.new(-travel.Z, 0, travel.X)
	local at = s.pos + back * distBack + right * ((M and M.SIDE or T.SIDE) * side) + Vector3.new(0, height, 0)
	local look = s.pos + travel * 6 + Vector3.new(0, 1.5, 0)

	--[[ Hold the hunter on screen. Rotate the aim toward it by however much it
		exceeds HOLD_MAX, and no further -- so the road ahead is given up only
		as much as keeping the threat visible actually costs. ]]
	if s.hunterPos then
		local dir = look - at
		dir = Vector3.new(dir.X, 0, dir.Z)
		local toH = s.hunterPos - at
		toH = Vector3.new(toH.X, 0, toH.Z)
		if dir.Magnitude > 0.1 and toH.Magnitude > 0.1 then
			dir, toH = dir.Unit, toH.Unit
			local ang = math.deg(math.acos(math.clamp(dir:Dot(toH), -1, 1)))
			-- how far the aim may swing before the player leaves frame
			local toP = s.pos - at
			toP = Vector3.new(toP.X, 0, toP.Z)
			local pAng = toP.Magnitude > 0.1
				and math.deg(math.acos(math.clamp(dir:Dot(toP.Unit), -1, 1))) or 0
			local allowed = math.max(0, T.PLAYER_MAX - pAng)
			local want = math.max(0, ang - T.HOLD_MAX)
			if want > 0 and allowed > 0 then
				local turn = math.min(want, allowed) / ang
				local aimed = dir:Lerp(toH, turn)
				if aimed.Magnitude > 0.01 then
					local reach = (look - at).Magnitude
					look = at + aimed.Unit * reach + Vector3.new(0, (look - at).Y, 0)
				end
			end
		end
	end

	local fov = T.FOV_BASE + T.FOV_SPEED * math.clamp((s.speed or 0) / math.max(s.carrySpeed or 16, 1), 0, 1)
	if s.mode == "B" and s.windup then fov += T.FOV_WINDUP end

	return CFrame.lookAt(at, look), fov, fear
end

--[[ THE CAMERA AS A SECOND VEHICLE.

	`solve` says where the camera WANTS to be. In modes A and B the caller eases
	straight to it, which tracks perfectly and therefore feels bolted on. In C
	the camera is given mass: it accelerates toward the mark, resists stopping,
	and is allowed to fall up to LAG_MAX studs behind. Corners are where you
	feel it -- the mark cuts the corner, the camera carries its momentum wide,
	then reels back in on the straight. That swing is the whole effect.

	It also banks. Lateral velocity relative to its own facing becomes roll, so
	a hard turn tips the horizon, which is the other half of the grammar.

	st is the caller's own table, carried between frames:
	    { pos = Vector3, vel = Vector3, roll = number }
	Returns the CFrame to use, and the roll in degrees.
]]
function ChaseCam.follow(st, target, dt, mode)
	local T = ChaseCam.T
	if mode ~= "C" then
		-- A and B keep the old behaviour: ease straight to the mark
		st.pos = target.Position
		st.vel = Vector3.zero
		st.roll = 0
		return target, 0
	end
	local M = T.MOVIE
	dt = math.clamp(dt or 1 / 60, 1 / 240, 1 / 15)

	st.pos = st.pos or target.Position
	st.vel = st.vel or Vector3.zero
	st.roll = st.roll or 0

	-- a spring with damping: accelerate at the mark, resist the overshoot
	local toMark = target.Position - st.pos
	if toMark.Magnitude > M.LAG_MAX then
		-- never fall so far behind that the shot stops being about the player
		st.pos = target.Position - toMark.Unit * M.LAG_MAX
		toMark = target.Position - st.pos
	end
	local accel = toMark * M.ACCEL - st.vel * M.DAMP
	st.vel += accel * dt
	st.pos += st.vel * dt

	-- bank into the turn: sideways speed relative to where it is pointing
	local look = target.LookVector
	local right = Vector3.new(-look.Z, 0, look.X)
	local lateral = st.vel:Dot(right)
	local wantRoll = math.clamp(-lateral * M.ROLL_PER_SPEED, -M.ROLL, M.ROLL)
	st.roll = st.roll + (wantRoll - st.roll) * math.clamp(dt * M.ROLL_RATE, 0, 1)

	local aim = CFrame.lookAt(st.pos, st.pos + target.LookVector * 20)
	return aim * CFrame.Angles(0, 0, math.rad(st.roll)), st.roll
end

return ChaseCam
