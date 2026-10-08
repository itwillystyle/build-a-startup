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

	--[[ THE SHOULDER. This was the flicker, and it was never the director.

		`solve` used to choose which side to sit on with sign(toHunter . right)
		-- a SIGN TEST on a quantity that is zero when the hunter is directly
		behind you. This file's own notes record that the hunter sits at
		dot(forward) = -1.00, i.e. directly behind you, always. So the test ran
		on noise and its answer changed every frame.

		MEASURED, offline: moving the hunter 0.01 studs across the travel line
		moves the camera 37.8 studs on the `chase` shot and 50.0 on `threat`,
		because the two shoulders are a full 2 x SIDE apart plus the yaw. And
		measured in a live chase: per-frame camera jumps of 46.5, 28.8, 22.7
		and 23.4 studs while the SHOT NEVER CHANGED -- so no cut, no director,
		just the lens teleporting back and forth around the player.

		Two changes fix it and both are needed. SIDE_HOLD makes the choice
		hysteretic in STUDS, so sub-stud noise cannot reach it. SIDE_RATE makes
		the change a SWEEP rather than a snap, so that even a real crossing --
		the hunter genuinely cutting across behind you -- reads as the camera
		moving instead of the picture breaking. ]]
	--[[ THE HEADING, and the feedback loop it closes. THIS is the flicker.

		The camera aims along the player's travel, and travel was read straight
		off AssemblyLinearVelocity each frame. In Roblox, movement is
		CAMERA-RELATIVE: the direction W sends you is the direction the camera
		faces. So camera yaw -> move direction -> velocity -> camera yaw, with
		no damping anywhere in it. That is a closed positive loop, and it does
		what closed positive loops do.

		MEASURED in a live chase, sampling every 0.09 s: the travel direction
		reversed between consecutive samples, and the reversal GREW --
		dot(travel, previousTravel) went +0.03, -0.30, -0.45, -0.56, -0.70,
		-0.80. Meanwhile the player advanced three studs in a second while
		reporting a speed of 20. The camera was swinging about 25 studs across
		every frame, faithfully pointing along a direction that was tearing
		itself apart.

		So the camera never steers off an instantaneous physics quantity again.
		HEADING is a time constant on the direction: long enough that a frame
		of jitter cannot move it, short enough that a real corner still reads.
		Damping the camera's input is what opens the loop -- and it fixes the
		player's movement at the same time, because the loop ran both ways. ]]
	HEADING = 0.25,       -- seconds of smoothing on the travel direction
	--[[ ...and a hard ceiling on how fast the shot may turn, in degrees per
		second. Smoothing alone cannot absorb a 160-degree reversal: a 0.25 s
		constant still takes a 30% step toward the new direction, which at 14
		studs is a 10-stud swing (measured). A rate cap is also the honest
		model -- nothing in this game turns faster than this -- and it means a
		reversal costs one small step instead of half an arc. A real 90-degree
		corner still completes in 0.6 s. ]]
	TURN_MAX = 150,       -- degrees per second

	SIDE_HOLD = 2.5,      -- studs across the line before the shoulder changes at all
	SIDE_RATE = 2.2,      -- how fast it swings when it does (full swap ~0.9 s)

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
		--[[ v3 (7 Oct, phase B): stiffer and near-critically damped.

			The loose spring (ACCEL 30 / DAMP 4.4, damping ratio 0.40) was chosen
			to make the camera feel like a second vehicle. At chase speed it was
			most of what the player reported as swaying: an underdamped spring
			overshoots on every input and rings back. The "second vehicle" feel
			now comes from the cuts and the lag, not from the lens wandering.
			Damping ratio DAMP / (2 * sqrt(ACCEL)) = 12 / 13.4 = 0.89. ]]
		ACCEL = 45,         -- how hard the camera chases its mark
		DAMP = 12,          -- near-critical: settles without ringing
		LAG_MAX = 4,        -- studs it is allowed to fall behind (was 11)
		ROLL = 8,           -- degrees it banks into a turn (was 11)
		--[[ Bank comes from the player's STEERING rate, not from the spring's own
			sideways drift -- the drift was an artefact, so the horizon tilted for
			reasons the player never caused. Degrees per (rad/s) of yaw. ]]
		ROLL_PER_TURN = 2.6,
		STEP_Y = 0.12,      -- seconds; how fast the camera takes up a change in the root's height
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

--[[ THE SHOTS, AS A GRAMMAR.

	The first version had five set-ups and cut between them on whatever beat
	arrived. That is reaction, not direction, and it is why the edit read as
	random: the SAME angle could appear for different reasons at different
	moments, so no angle ever came to MEAN anything, so a cut could never be
	read as a statement.

	Two rules fix that, and they are the whole design.

	ONE SHOT, ONE MEANING. Each set-up below answers exactly one question the
	player is asking at that moment, and appears for no other reason. After a
	handful of chases the angle itself is the message -- you see the deck-level
	loom and you know it is gaining before you have read the number.

	A CUT HAS TO CHANGE THE FRAME. The old set-ups differed by three studs and
	a degree of yaw; at that size a cut is indistinguishable from a camera
	wobble, which is the other half of "it is just flickering". Every shot here
	moves at least two of: side of the shoulder, height class, lens.

	    carry      nobody is chasing you         calm, slightly high
	    establish  here is the situation         high and back: both of you, and the road
	    chase      it is holding station         the neutral three-quarter
	    closing    IT IS GAINING ON YOU          on the deck, loomed, tighter lens
	    gaining    you are pulling away          up and back, wide: the empty road reads
	    threat     it is about to lunge          the loudest cut: other shoulder, on the deck
	    hero       you boosted                   front three-quarter, the kick reads
	    homerun    the door is in reach          stop looking back; look where you are going

	Each entry is an OFFSET on whatever `solve` worked out, so every shot
	inherits the visibility constraints -- the hunter stays framed and the
	player never leaves screen, whichever one is running.

	forward always stays INTO the screen. A true side-on tracking shot looks
	superb and makes the player swerve, because the direction they push on the
	stick stops matching the direction they move. "side" here is a hard
	three-quarter, never a profile.

	flip  = swap to the other shoulder. The biggest change available for free,
	        and it cannot disorient, because the travel direction is unchanged.
	        Spent on ONE shot only -- `threat` -- so the flip itself is a word.
	lead  = push the look point further down the road. "Look where you are
	        going" instead of "look back at the thing behind you".
	hold  = this shot's own HOLD_MAX. `homerun` sets it wide on purpose: giving
	        up sight of the hunter IS the statement.
]]
ChaseCam.SHOTS = {
	-- yaw / lead / hold are read only by the legacy `solve` (modes A/B, the lab).
	-- The locked camera (`solveLocked`, mode C) ignores yaw entirely and reads
	-- screenY instead: where the player sits vertically, i.e. how much road
	-- ahead the shot shows.
	carry     = { dist = 3,  height = 2.0,  yaw = -6,  fov = -4, flip = false, screenY = 0.58 },
	establish = { dist = 9,  height = 6.0,  yaw = 14,  fov = -8, flip = false, screenY = 0.56 },
	chase     = { dist = 0,  height = 0,    yaw = 0,   fov = 0,  flip = false, screenY = 0.58 },
	closing   = { dist = 0,  height = -1.6, yaw = 12,  fov = 6,  flip = false, screenY = 0.62 },
	gaining   = { dist = 7,  height = 4.2,  yaw = -8,  fov = -10, flip = false, screenY = 0.54 },
	threat    = { dist = 0,  height = -1.8, yaw = 20,  fov = 4,  flip = true, hold = 24, screenY = 0.62 },
	hero      = { dist = -2, height = -0.8, yaw = -30, fov = 10, flip = true, screenY = 0.64 },
	homerun   = { dist = -1, height = 0.6,  yaw = -22, fov = 8,  flip = false, lead = 16, hold = 95, screenY = 0.68 },
}

--[[ Kept so an older caller asking for a shot by its old name still gets a
	frame rather than silently falling back to `chase`. ]]
ChaseCam.SHOT_ALIAS = { low = "closing", wide = "gaining", flank = "threat" }

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

	--[[ Which shoulder. `s.side` is the director's sticky, swept value in
		[-1, 1] (see ChaseCam.sideFor); a caller that does not keep state --
		the Edit lab, a one-off measurement -- falls back to the old sign test,
		which is fine for a single frame and is the thing that must never run
		frame after frame. ]]
	local side = s.side
	if side == nil then
		side = 1
		if s.hunterPos then
			local toH = s.hunterPos - s.pos
			local right = Vector3.new(-travel.Z, 0, travel.X)
			side = (toH:Dot(right) >= 0) and 1 or -1
		end
	end

	--[[ The shot is an offset on everything below, so each set-up inherits the
		visibility constraints rather than having to re-earn them. ]]
	local want = s.shot or "chase"
	local shot = ChaseCam.SHOTS[want] or ChaseCam.SHOTS[ChaseCam.SHOT_ALIAS[want] or ""] or ChaseCam.SHOTS.chase
	if shot.flip then side = -side end

	local yawDeg = lerp(T.YAW_FAR, T.YAW_NEAR, fear) + (shot.yaw or 0)
	if s.mode == "B" and s.windup then yawDeg += T.YAW_WINDUP end

	local back = CFrame.Angles(0, math.rad(yawDeg * side), 0) * (-travel)
	local M = (s.mode == "C") and T.MOVIE or nil
	local distBack = lerp(M and M.DIST_FAR or T.DIST_FAR, M and M.DIST_NEAR or T.DIST_NEAR, fear)
	-- never let the hunter get between the camera and the player
	if s.dist then distBack = math.clamp(s.dist + T.CLEAR, distBack, T.DIST_MAX) end
	distBack = math.max(4, distBack + (shot.dist or 0))
	--[[ RE-ENFORCE THE CLEARANCE, because the shot offset was allowed to eat it.

		CLEAR guarantees the camera stays 7 studs behind the hunter, and then
		shot.dist subtracted from the result -- "hero" takes 4 off, leaving 3.
		At 3 studs a torso is the entire frame, which is exactly what the
		recording showed: the hunter filling half the screen with the chase
		happening somewhere behind it.

		A shot may move the camera, but it may not move it closer to the hunter
		than the clearance the framing depends on. ]]
	if s.dist then distBack = math.max(distBack, s.dist + T.CLEAR) end
	local height = lerp(M and M.HEIGHT_FAR or T.HEIGHT_FAR, M and M.HEIGHT_NEAR or T.HEIGHT_NEAR, fear)
	--[[ Never below 1.2: a camera that dips under the kerb clips through the
		road and shows the underside of the world, which no amount of drama
		is worth. ]]
	height = math.max(1.2, height + (shot.height or 0))

	-- and slide off the centre line, so it passes beside the lens, not through it
	local right = Vector3.new(-travel.Z, 0, travel.X)
	local at = s.pos + back * distBack + right * ((M and M.SIDE or T.SIDE) * side) + Vector3.new(0, height, 0)
	--[[ `lead` is how far down the road the shot looks. The default 6 keeps
		the player low in frame with the threat behind them; a shot that adds
		lead is saying stop looking back. ]]
	local look = s.pos + travel * (6 + (shot.lead or 0)) + Vector3.new(0, 1.5, 0)

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
			--[[ A shot may widen its own tolerance (homerun does), because
				letting the hunter leave frame is sometimes the point. ]]
			local holdMax = shot.hold or T.HOLD_MAX
			local excess = math.max(0, ang - holdMax)
			if excess > 0 and allowed > 0 then
				local turn = math.min(excess, allowed) / ang
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
	fov = math.clamp(fov + (shot.fov or 0), 55, 100)

	return CFrame.lookAt(at, look), fov, fear
end


--[[ ======================================================================
	THE LOCKED CAMERA -- phase A + B of the 7 Oct control spec.

	THE RULE. The camera's YAW is the player's yaw, exactly, always. A shot may
	change how far back the camera sits, how high, which side, the lens and the
	roll. It may never change which way the camera faces.

	WHY IT HAS TO BE THIS STRICT. Roblox movement is camera-relative: W goes
	where the camera faces. Every control bug in this feature was a way for the
	camera's facing to come from somewhere other than the player:
	  * from velocity      -> a feedback loop that diverged (measured: travel
	                          reversing every frame, dot falling to -0.80)
	  * from a shot's yaw  -> W changing direction on every cut, and a profile
	                          shot where the stick stops matching the motion
	  * from the hero shot -> a camera in FRONT of the player inverts W outright
	The 7 Oct recording ("I don't even know if W is moving me forwards or
	backwards") was all three at once. With the yaw locked, none can happen.
	This is how racing-game chase cameras work: heading-locked, position lagged.

	THE HUNTER, IN SCREEN TERMS. The old clearance said "stay 7 studs behind
	the hunter". ChaseFrame measured what that means on screen: a 5.5-stud
	hunter 7 studs from the lens is about HALF the frame. So the clearance is
	now derived from the lens: the camera keeps the hunter at least
	HUNTER_HEIGHT / (HUNTER_MAX_H * 2 * tan(fov/2)) away, which is the distance
	at which it is HUNTER_MAX_H of the frame tall, and rises as it pulls back
	so the hunter sits low in the frame instead of across the player.
]]
ChaseCam.LOCKED = {
	DIST = 12,              -- studs behind the player at rest
	HEIGHT = 3.6,           -- studs above the root at rest
	LATERAL = 2.6,          -- studs off the centre line, toward the director's side
	HUNTER_HEIGHT = 5.5,    -- a hunter rig, roughly
	HUNTER_RANGE = 20,      -- inside this the hunter must be framed (ChaseFrame rule 5)
	--[[ FRAMING, with hysteresis, and the change is a CUT.

		The camera has two jobs that need two different places: framing a near
		hunter means sitting BEHIND it; with the hunter out of range the camera
		sits close behind the player. Switching on a single threshold at 20
		studs was a disaster on two counts, both found in a live chase:
		  * 20 studs is where the hunter LIVES -- ChaseRules sprints it beyond
		    20 and jogs it inside -- so it crossed the line constantly and the
		    camera target jumped ~16-20 studs each time (reproduced: 12 jumps
		    of more than 3 studs in a single frame);
		  * any continuous move between "behind the hunter" and "in front of
		    the hunter" passes THROUGH the hunter. Live: 168% of the frame.
		So it is hysteretic (frame from 20 in, release past 25) and the switch
		snaps -- a cut, which never has an in-between frame. ]]
	FRAME_IN = 20,
	FRAME_OUT = 25,
	--[[ A framing switch is a cut to the eye, so it waits out the director's
		MIN_HOLD after a cut like any other cut -- except framing IN with the
		hunter already this close, where an unframed hunter is the bigger harm.
		Live: a cut at 5.08 s, then a snap at 5.29 s, read as a stutter. ]]
	URGENT = 15,
	-- the push fades in across the frame edge (see solveLocked)
	EDGE_ASPECT = 2.2,      -- when the caller does not say: a landscape phone
	HUNTER_HALF_W = 1.5,    -- studs, shoulder to centre
	EDGE_BAND = 40,         -- degrees outside the frame edge where the push starts
	HUNTER_MAX_H = 0.25,    -- target; ChaseFrame's contract is 0.30, the gap is perspective margin
	PLAYER_H = 5,           -- the player, for the size floor below
	--[[ Target; the contract is 0.09. The size formula uses the flat distance,
		but the camera is raised and pitched, so the true slant distance is
		longer and the player measured ~5% smaller than predicted (0.090 against
		a 0.095 target). 0.10 absorbs that. ]]
	PLAYER_MIN_H = 0.10,
	DIST_MAX = 48,          -- room to stay behind a hunter out to FRAME_OUT with a narrowed lens
	--[[ Speed used to widen the lens by up to 14 degrees. A wide lens shrinks
		the player and swells nothing useful, and the speed lines and the wind
		now carry "fast" without touching the frame. ]]
	FOV_SPEED = 5,
	SHOT_FOV = 0.6,         -- scale on each shot's own lens change
	RISE = 0.24,            -- studs of extra height per stud pulled back past DIST
	PITCH_MIN = -4,         -- degrees; negative = looking slightly up
	PITCH_MAX = 30,
}

--[[ How much of the hunter is in the shot, 0..1, so that anything driven by
	it is continuous in the hunter's position. Measured as an ANGLE outside
	the frame's side edge: 0 at EDGE_BAND degrees out, 1 at the edge. An angle
	because the camera turns: at 120 deg/s a band measured in screen widths was
	crossed in a frame or two and the push it drove jumped 5 studs (offline).
	atan2 keeps it continuous behind the lens too. look/right are the
	camera's (flat right); returns weight and depth. ]]
local function inShot(at, look, right, hunterPos, tanV, aspect)
	local L = ChaseCam.LOCKED
	local rel = hunterPos - at
	local depth = rel:Dot(look)
	local tanH = tanV * (aspect or L.EDGE_ASPECT)
	local off = math.max(0, math.abs(rel:Dot(right)) - L.HUNTER_HALF_W)
	local outside = math.deg(math.atan2(off, depth) - math.atan(tanH))
	return math.clamp(1 - outside / L.EDGE_BAND, 0, 1), depth
end

--[[ The yaw a camera has, as a heading. Exposed so the client seeds its
	control yaw from wherever the default camera was looking when the chase
	took over, and the transition is seamless. ]]
function ChaseCam.yawOf(cf)
	local l = cf.LookVector
	return math.atan2(-l.X, -l.Z)
end

function ChaseCam.headingOfYaw(yaw)
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

--[[ s = {
	  pos        Vector3   the player's root
	  heading    Vector3   the player-owned direction (flat); the camera faces it
	  shot       string?
	  side       number?   the director's swept shoulder, -1..1
	  dist       number?   studs to the hunter
	  speed, carrySpeed
	  aspect     number?   the screen's width / height
	}
	returns cf, fov ]]
function ChaseCam.solveLocked(s)
	local T, L = ChaseCam.T, ChaseCam.LOCKED
	local shot = ChaseCam.SHOTS[s.shot or "chase"] or ChaseCam.SHOTS.chase

	local h = s.heading or Vector3.new(0, 0, -1)
	h = Vector3.new(h.X, 0, h.Z)
	h = h.Magnitude > 1e-3 and h.Unit or Vector3.new(0, 0, -1)
	local right = Vector3.new(-h.Z, 0, h.X)
	local up = Vector3.new(0, 1, 0)

	-- the lens first: the clearance below is a function of it
	local fov = T.FOV_BASE + L.FOV_SPEED * math.clamp((s.speed or 0) / math.max(s.carrySpeed or 16, 1), 0, 1)
	fov = math.clamp(fov + (shot.fov or 0) * L.SHOT_FOV, 55, 90)
	local tanV = math.tan(math.rad(fov) / 2)

	local dist = L.DIST + (shot.dist or 0)
	-- the director decides framing (with hysteresis); a caller without one gets the plain range test
	local framing = s.framing
	if framing == nil then framing = s.dist ~= nil and s.dist <= L.HUNTER_RANGE end
	if framing and s.dist then
		--[[ THE CONFLICT, solved rather than tuned. With the hunter d studs
			behind the player and the lens L studs behind the hunter:
			    hunter small enough  ->  L      >= HH / (2 tanV hMax)
			    player big enough    ->  d + L  <= PH / (2 tanV pMin)
			Both hold only if  tanV <= (PH/(2 pMin) - HH/(2 hMax)) / d.
			Measured before this: 99 of 648 framings had the player under 9% of
			the frame and 27 had the hunter over 30%, all at the far end of the
			range with a wide lens. So when a far hunter and a wide lens cannot
			both be framed, the LENS gives way -- never the player. ]]
		local k = L.PLAYER_H / (2 * L.PLAYER_MIN_H) - L.HUNTER_HEIGHT / (2 * L.HUNTER_MAX_H)
		local tanMax = k / math.max(s.dist, 1)
		if tanV > tanMax then
			tanV = tanMax
			fov = math.deg(2 * math.atan(tanV))
		end
		local lens = L.HUNTER_HEIGHT / (L.HUNTER_MAX_H * 2 * tanV)
		dist = math.max(dist, s.dist + lens)
	end
	--[[ ...and never so far back that the player stops being the subject.

		The cap is on the SLANT distance, not the flat one: the camera rises as
		it pulls back, so the lens is further from the player than `dist` says.
		Capping the flat distance left the player at 0.089 of the frame on the
		raised shots (measured) -- under the contract while the maths said 0.10.
		With height H = a + RISE*D past DIST, solve D^2 + H^2 = c^2 for D. ]]
	local base = L.HEIGHT + (shot.height or 0)
	local c = L.PLAYER_H / (2 * tanV * L.PLAYER_MIN_H)
	local a = base - L.DIST * L.RISE
	local q = 1 + L.RISE * L.RISE
	local disc = (a * L.RISE) ^ 2 - q * (a * a - c * c)
	local playerCap = disc > 0 and (-a * L.RISE + math.sqrt(disc)) / q or c
	-- below DIST the height does not rise, so the flat-height form applies there
	if playerCap < L.DIST then
		playerCap = math.sqrt(math.max(c * c - base * base, 1))
	end
	dist = math.clamp(dist, 6, math.min(L.DIST_MAX, playerCap))

	local height = base + math.max(0, dist - L.DIST) * L.RISE
	height = math.max(1.2, height)

	local side = s.side or 1
	if shot.flip then side = -side end
	local at = s.pos - h * dist + right * (L.LATERAL * side) + up * height

	--[[ CLEAR THE LENS OF THE HUNTER'S ACTUAL POSITION.

		Everything above assumes the hunter is behind the player, on the line
		to the camera. Found in a live chase: on a hard turn the camera swings
		round behind the new heading and passes right by a hunter that is now
		beside the player -- it measured 168% of the frame for two frames, its
		body flashing across the lens. So check where it really is: if it is in
		front of the lens and too big, pull straight back until it is not,
		never past the point where the player would get too small. ]]
	if s.hunterPos then
		local flatPitch = math.atan(height / dist)
		local fwd = h * math.cos(flatPitch) - up * math.sin(flatPitch)
		local need = L.HUNTER_HEIGHT / (L.HUNTER_MAX_H * 2 * tanV)
		--[[ ...but only as much as the hunter is actually IN the shot. The
			first version pushed whenever the hunter was anywhere in front of the
			lens, so a hunter swinging round beside the camera on a turn -- out
			of frame -- switched the push on all at once: a 14-stud move of the
			mark in one frame (live, 7 Oct, 5.12 s). Now the push fades in over
			the frame edge, so it is continuous in the hunter's position. The
			edge is the caller's real screen (s.aspect): a fixed guess either
			misses the hunter on Studio's 6:1 play window (measured 0.77 of the
			frame) or pushes for a hunter nobody on a 16:9 screen can see. ]]
		local w, depth = inShot(at, fwd, right, s.hunterPos, tanV, s.aspect)
		if w > 0 and depth < need then
			local push = w * math.min(need - depth, math.max(0, playerCap - dist))
			if push > 0 then
				dist += push
				height = math.max(1.2, base + math.max(0, dist - L.DIST) * L.RISE)
				at = s.pos - h * dist + right * (L.LATERAL * side) + up * height
			end
		end
	end

	--[[ Pitch so the player's root lands at the shot's screenY. The root sits
		atan(height / dist) below the horizontal; we want it atan(...) below the
		centre of frame, so the pitch is the difference. ]]
	local want = math.atan(((shot.screenY or 0.58) - 0.5) * 2 * tanV)
	local pitch = math.atan(height / dist) - want
	pitch = math.clamp(pitch, math.rad(L.PITCH_MIN), math.rad(L.PITCH_MAX))
	local dir = h * math.cos(pitch) - up * math.sin(pitch)

	return CFrame.lookAt(at, at + dir), fov
end

--[[ THE LENS, CLEARED AFTER THE SPRING.

	solveLocked already pulls the MARK back from a hunter in the shot, but the
	spring takes ~0.3 s to get there, and a hunter swinging round beside the
	lens on a hard turn gets there first: measured 0.61 of the frame while the
	camera was still catching up. So the same rule is applied once more to the
	camera the player actually sees: step away from the hunter, exactly as far
	as it needs, never so far that the player drops under PLAYER_MIN_H. Away,
	not back: the hunter that gets here is BESIDE the lens, and backing up the
	lens axis pulled it into the edge of a wide frame (0.53 against 0.37 at
	3.6:1, measured).
	The amount is continuous in the hunter's position (inShot), so this can
	never jump; it backs off at once, and the spring brings it home smoothly
	because the mark was pulled back too.

	s = { pos = player root, hunterPos?, aspect? }   returns cf ]]
function ChaseCam.clearLens(cf, fov, s)
	local L = ChaseCam.LOCKED
	if not s.hunterPos then return cf end
	local tanV = math.tan(math.rad(fov) / 2)
	local look = cf.LookVector
	local r = cf.RightVector
	local right = Vector3.new(r.X, 0, r.Z)
	right = right.Magnitude > 1e-3 and right.Unit or Vector3.new(1, 0, 0)
	local w, depth = inShot(cf.Position, look, right, s.hunterPos, tanV, s.aspect)
	local need = L.HUNTER_HEIGHT / (L.HUNTER_MAX_H * 2 * tanV)
	if w <= 0 or depth >= need then return cf end
	local cap = L.PLAYER_H / (2 * tanV * L.PLAYER_MIN_H)
	local room = math.max(0, cap - (cf.Position - s.pos).Magnitude)
	local push = w * math.min(need - depth, room)
	if push <= 0 then return cf end
	-- away from the hunter, level: backing straight up the lens axis drags a
	-- hunter that is BESIDE the camera into the edge of a wide frame
	local away = cf.Position - s.hunterPos
	away = Vector3.new(away.X, 0, away.Z)
	away = away.Magnitude > 1e-3 and away.Unit or -look
	return cf + away * push
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

	`frame` = { anchor = player root, heading = the player's yaw }, optional.
	With it, the spring runs in the PLAYER'S HEADING FRAME instead of the
	world: see the note in the body. The locked camera always passes it.
]]
function ChaseCam.follow(st, target, dt, mode, steerRate, frame)
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

	--[[ A damped spring, INTEGRATED IN FIXED SUBSTEPS.

		The first version advanced it once per frame with explicit Euler:
		    vel += (toMark * ACCEL - vel * DAMP) * dt
		At 60 fps, ACCEL * dt is 0.5 and that is stable. On a machine rendering
		the chase at 15-20 fps it is 1.5 to 2.0, and past 1.0 an explicit spring
		overshoots further on every step -- it does not settle, it diverges. The
		camera vibrated, which read as the shots flickering when nothing was
		cutting at all.

		Substepping at a fixed 1/120 makes stability independent of frame rate,
		which is the property this needs: the same chase has to look the same on
		a slow machine and a fast one. ]]
	local STEP = 1 / 120
	local function spring(pos, vel, mark, lagMax)
		local left = dt
		while left > 0 do
			local h = math.min(STEP, left)
			left -= h
			local toMark = mark - pos
			if lagMax and toMark.Magnitude > lagMax then
				-- never fall so far behind that the shot stops being about the player
				pos = mark - toMark.Unit * lagMax
				toMark = mark - pos
			end
			vel += (toMark * M.ACCEL - vel * M.DAMP) * h
			pos += vel * h
		end
		return pos, vel
	end

	if frame and frame.anchor and frame.heading then
		--[[ THE SPRING RUNS IN THE PLAYER'S FRAME (7 Oct, the 23:36 recording:
			"stuttering ... like it's locking to something").

			In world space the spring could not do its job. Running at 19
			studs/s its steady lag is v * DAMP / ACCEL = 5 studs, past LAG_MAX,
			so the clamp held it rigid for the whole chase and anything that
			moved the mark went straight to the screen. Measured live: the
			hunter, moved by the server with PivotTo, reaches the client in
			~20 Hz steps; the lens distance follows the hunter; the camera
			jolted 0.45-3 studs 46 times in 11 s, every third frame.

			So the mark is expressed as an offset in (right, up, back) of the
			player's own heading. Running does not move it at all, and neither
			does turning: the camera orbits WITH the player's yaw, rigidly,
			the way the default Roblox camera does, and the player stays put on
			screen. The spring is left to do the one job it is for, smoothing
			changes in the SHOT -- the dolly to a hunter, the shoulder, a lens
			push. The root's height is eased separately (STEP_Y), so a curb or
			a jump lifts the camera instead of jerking it.

			And NO LAG_MAX here. The clamp existed so world-space lag could not
			run away; in this frame nothing makes lag except the shot itself
			changing, and clamping that turns a dolly into a teleport. Measured:
			a hunter swinging in beside the lens on a turn moved the mark 14
			studs, and the clamp made it a 10-stud jump in one frame (live at
			5.12 s, and offline). Real cuts reset the follower anyway. ]]
		local hd = Vector3.new(frame.heading.X, 0, frame.heading.Z)
		hd = hd.Magnitude > 1e-3 and hd.Unit or Vector3.new(0, 0, -1)
		local right = Vector3.new(-hd.Z, 0, hd.X)
		local a = frame.anchor
		st.ay = st.ay and st.ay + (a.Y - st.ay) * (1 - math.exp(-dt / M.STEP_Y)) or a.Y
		local o = target.Position - a
		local mark = Vector3.new(o:Dot(right), o.Y, o:Dot(hd))
		st.loc = st.loc or mark
		st.lvel = st.lvel or Vector3.zero
		st.loc, st.lvel = spring(st.loc, st.lvel, mark, nil)
		st.pos = Vector3.new(a.X, st.ay, a.Z) + right * st.loc.X + Vector3.new(0, st.loc.Y, 0) + hd * st.loc.Z
	else
		st.pos, st.vel = spring(st.pos, st.vel, target.Position, M.LAG_MAX)
	end

	--[[ Bank. When the caller passes the player's steering rate, the bank
		comes from THAT: you turn hard, the horizon leans. The legacy path
		(no steerRate) reads the spring's own sideways drift, which is how the
		horizon used to tilt for reasons the player never caused. ]]
	local wantRoll
	if steerRate then
		wantRoll = math.clamp(steerRate * M.ROLL_PER_TURN, -M.ROLL, M.ROLL)
	else
		local look = target.LookVector
		local right = Vector3.new(-look.Z, 0, look.X)
		local lateral = st.vel:Dot(right)
		wantRoll = math.clamp(-lateral * M.ROLL_PER_SPEED, -M.ROLL, M.ROLL)
	end
	st.roll = st.roll + (wantRoll - st.roll) * math.clamp(dt * M.ROLL_RATE, 0, 1)

	local aim = CFrame.lookAt(st.pos, st.pos + target.LookVector * 20)
	return aim * CFrame.Angles(0, 0, math.rad(st.roll)), st.roll
end


--[[ ======================================================================
	THE DIRECTOR -- why the camera cuts, as pure logic.

	This is the part the earlier versions did not have. They cut when
	something happened, which sounds like direction and is not: a cut fired
	on a timer when nothing had happened, the same angle served several
	different beats, and a noisy threshold could cut twice in a second. The
	result was an edit with no argument in it.

	THE ARGUMENT. A chase is two numbers and nothing else: how close the
	threat is, and how close home is. Everything a player wants to know is a
	question about one of them, and in a readable chase every cut answers the
	question that is live at that instant.

	    is it about to hit me          -> threat     (and only ever this)
	    am I losing ground             -> closing
	    did I get away                 -> gaining
	    is it just sitting behind me   -> chase
	    am I nearly home               -> homerun
	    what is going on               -> establish  (the opening, once)

	THREE RULES THAT MAKE IT READ.

	1. NO CUT WITHOUT A CAUSE. There is no timer branch. Every return either
	   names the reason the shot changed or does not change the shot. The old
	   `t > holdUntil -> come home` branch was a cut caused by the clock, and
	   the clock is not something the player can see -- so that cut was, from
	   the player's seat, motiveless. It is gone.

	2. YOU CUT BEFORE AN ACTION, NOT DURING IT. The windup is the cue; the
	   lunge is HELD. Cutting as the thing leaves the ground hides the one
	   frame the whole mechanic exists to show. MIN_HOLD is set just above
	   WINDUP + LUNGE_TIME so the shot taken on the tell survives the strike.

	3. A STRIKE IS NOT A TREND. This is the one that was actually causing the
	   flicker, and it took measuring two directors side by side to find --
	   see scratchpad note in the spec. On the noise the client really gets
	   (ChaseDist replicated at ~10 Hz, held between samples) NEITHER a rate
	   director nor a trend director cuts at all: 0 cuts across a dead steady
	   gap, a jog opening at 1 stud/s, and the largest wobble the jog's 0.94x
	   speed can physically produce. What strobes is the LUNGE CYCLE.
	   ChaseRules lunges every 3.2 s and a lunge closes the gap at about 4.5
	   studs/s, so the gap genuinely slams shut and drifts back out, forever,
	   and a director reading movement faithfully reports it -- measured at 28
	   to 31 cuts in 45 seconds, roughly one every one and a half seconds,
	   which is precisely what "the angles are just flickering" looks like.

	   The distance a lunge covers IS the lunge. The camera has already shown
	   it, held, from the deck. Cutting afterwards to announce that the gap
	   shrank restates the thing the player just watched, which is the one
	   mistake an edit can make that feels worse than no edit at all. So the
	   trend FREEZES for the duration of windup and lunge and is re-seeded
	   when the strike ends: the attack is an event, and events are not
	   evidence about the trend.

	4. HOLD THE INTENSE ANGLE WHILE THE INTENSITY LASTS. Freezing the trend
	   through a strike removed the closing/gaining chatter and left a second
	   one behind it: threat -> chase -> threat -> chase, 26 cuts in 45
	   seconds, because the camera came home after every blow and the next
	   blow was 0.9 s away. Coming home was caused by the last strike ENDING,
	   and in a band where strikes repeat that is not information.

	   While the hunter is inside lunge range the threat has not receded, so
	   the shot does not change. The camera comes home when the player is
	   actually out of reach -- which is a thing they did, and therefore worth
	   a cut. One cut in, one cut out, however many blows land in between.

	5. THE TREND IS THE INFORMATION, NOT THE DISTANCE. "14 studs" means
	   nothing on its own; "14 and shrinking" is the entire chase.

	   The first attempt at this ran on d(dist)/dt, smoothed. MEASURED, in
	   tests/offline/chasecam.spec.luau: a hunter merely jogging produced 35
	   cuts in 60 seconds, closing -> chase -> closing -> chase, which is the
	   strobe the recordings showed. The filter was not too weak -- the SIGNAL
	   was wrong. A hunter holding station has a mean rate of zero and a large
	   oscillation around it, because it breathes: ChaseRules has it jogging at
	   0.94x your speed, so the gap opens and shuts by about a stud a couple of
	   times a second. Instantaneous rate cannot separate that from a chase.

	   What "it is gaining" actually means is THE GAP NOW VERSUS WHERE THE GAP
	   HAS BEEN. So distance is run through two exponential smoothers, a quick
	   one and a lagging one, and the director reads the difference between
	   them, in studs. A sustained approach separates them; breathing does not,
	   because both followers ride it out together. Measured on the same
	   signal: ~0.41 studs of noise against 2.31 studs for a real 2.2 studs/s
	   close -- a 5.6x margin where rate had none.

	   HYSTERESIS on top, because any single threshold on any noisy signal is
	   a strobe generator. `closing` and `gaining` are opposites, so the cut
	   between them can never be ambiguous.

	PURE on purpose: no services, no Instances, `t` and `dt` passed in. That
	is what lets tests/offline/chasecam.spec.luau drive a scripted chase and
	assert the cut sequence, instead of me asserting it.
]]
ChaseCam.DIR = {
	ESTABLISH = 1.1,     -- seconds the opening shot holds
	--[[ Just above ChaseRules.WINDUP (0.5) + LUNGE_TIME (0.8): the shot taken
		on the tell is not allowed to be cut away mid-strike. ]]
	MIN_HOLD = 1.35,
	HOME_NEAR = 52,      -- studs: close enough that the door is the story

	--[[ The two followers whose disagreement IS the trend. TREND_FAST tracks
		the gap, TREND_SLOW remembers what it has been; fast minus slow is
		therefore signed studs of sustained movement, negative when the gap is
		shrinking. Widening the split makes the reading stronger and slower in
		equal measure; 0.25/1.3 puts first detection of a real close at about
		1.1 s, which is inside human reaction time for a thing that then needs
		0.5 s of crouch before it can hit you. ]]
	TREND_FAST = 0.25,   -- seconds
	TREND_SLOW = 1.3,

	--[[ Hysteresis, in studs of trend. Entering a claim is easy; leaving it
		requires the claim to be clearly false rather than merely borderline.
		MEASURED: the fastest gap movement the jog can physically produce
		(3 studs/s, which is generous -- it allows for the junior second
		hunter and the player's own speed changes) peaks at 0.79 studs of
		trend. IN at 1.3 therefore cannot be reached by anything short of a
		real approach, and the cost is paid in latency: a genuine 2.2 studs/s
		close now reads at about 1.4 s instead of 1.1 s. That is affordable
		because the hunter still owes 0.5 s of crouch before it can touch
		you. ]]
	CLOSE_IN = -1.3,     -- studs: below this the gap IS shrinking
	CLOSE_OUT = -0.6,    -- ... and it stops shrinking only once above this
	AWAY_IN = 1.3,
	AWAY_OUT = 0.6,

	NEAR = 12,           -- studs: it was on you, so getting away is worth saying
	FAR = 20,            -- ChaseRules.FAR: past this it sprints, it is not stalking
	--[[ A STRIKE EPISODE: it has hit at you recently AND is still close enough
		to do it again. Both halves are needed.

		Gating the hold on distance alone (the first attempt) was far too
		blunt: a hunter merely sitting at 15 studs without ever lunging put the
		camera in a permanent hold, so the opening shot never gave way and a
		genuine 2.2 studs/s approach went unreported. The churn this rule
		exists to stop only happens BETWEEN BLOWS, so it is blows that have to
		arm it.

		STRIKE_BAND 17 covers the widest tier range (star, 16) with a stud
		spare. EPISODE 3.8 s bridges the gap between blows: ChaseRules re-arms
		LUNGE_EVERY = 3.2 s after a lunge ENDS, so anything over 3.2 keeps one
		continuous attack reading as one episode, and anything under about 4.5
		lets a hunter that has actually given up fall out of it. ]]
	STRIKE_BAND = 17,
	EPISODE = 3.8,       -- seconds a strike keeps the hold armed
	BOOST = 1.35,        -- x carry speed. Below ~1.3 the ordinary scooter wobble trips it.
}

--[[ The direction the shot is built around, smoothed.

	Returns a unit vector. Blending directions by lerping and renormalising is
	fine here because the step is small; the one case it cannot handle is an
	exact 180-degree reversal, where the blend passes through zero, so that
	falls back to the new direction rather than producing a NaN. ]]
function ChaseCam.headingFor(st, travel, dt)
	local t = travel and Vector3.new(travel.X, 0, travel.Z) or Vector3.zero
	if t.Magnitude < 0.01 then
		return st.heading or Vector3.new(0, 0, -1)
	end
	t = t.Unit
	if not st.heading then
		st.heading = t
		return t
	end
	dt = dt or 1 / 60
	local k = 1 - math.exp(-dt / ChaseCam.T.HEADING)
	local blended = st.heading + (t - st.heading) * k
	local want = (blended.Magnitude > 1e-3) and blended.Unit or t

	--[[ Clamp the turn rate. Rotate about Y by at most TURN_MAX * dt; the sense
		is chosen by trying both and keeping whichever ends closer, which is
		shorter than deriving it from a cross product and cannot get the sign
		backwards. ]]
	local step = math.rad(ChaseCam.T.TURN_MAX) * dt
	local cosang = math.clamp(st.heading:Dot(want), -1, 1)
	if math.acos(cosang) > step then
		local a = (CFrame.Angles(0, step, 0) * st.heading).Unit
		local b = (CFrame.Angles(0, -step, 0) * st.heading).Unit
		want = (a:Dot(want) >= b:Dot(want)) and a or b
	end
	st.heading = want
	return st.heading
end

--[[ The shoulder, held and swept rather than flipped.

	Hysteresis is in STUDS, not in the sign: the hunter has to be properly over
	on the other side (SIDE_HOLD) before the shot even wants to change. When it
	does, the value crosses gradually, so the camera arcs round behind the
	player instead of jumping across them.

	Returns a continuous value in [-1, 1]. Everything downstream multiplies by
	it, so a half-way value is a half-way camera, which is what makes the sweep
	work without any extra code in solve. ]]
function ChaseCam.sideFor(st, pos, travel, hunterPos, dt)
	local T = ChaseCam.T
	local want = st.sideWant or 1
	if hunterPos and pos and travel then
		local right = Vector3.new(-travel.Z, 0, travel.X)
		local lat = (hunterPos - pos):Dot(right)
		if lat > T.SIDE_HOLD then
			want = 1
		elseif lat < -T.SIDE_HOLD then
			want = -1
		end
	end
	st.sideWant = want
	local cur = st.side or want
	st.side = cur + (want - cur) * math.clamp((dt or 1 / 60) * T.SIDE_RATE, 0, 1)
	return st.side
end

--[[ st is the caller's table, carried between frames. s is the world:
	  { t, dt, dist?, windup, lunging, homeDist?, speed, carrySpeed,
	    pos?, travel?, hunterPos? }   -- the last three only to keep the shoulder
	Returns shot, cause, cut -- `cause` is the sentence the cut is making, and
	exists so a cut can be audited rather than trusted. ]]
function ChaseCam.direct(st, s)
	local D = ChaseCam.DIR
	--[[ The heading and the shoulder are director state, not per-frame
		geometry: one place decides them, one place holds them steady, and the
		caller passes `st.heading` and `st.side` straight into solve. The
		shoulder is measured against the SMOOTHED heading on purpose -- against
		the raw one its hysteresis is defeated by the same jitter it exists to
		reject, which is exactly what happened the first time. ]]
	--[[ A player-owned heading (the locked camera) is used as given: it is
		the player's own aim and must not lag. Only the legacy path, which
		derives a heading from velocity, gets smoothed. ]]
	local heading
	if s.heading then
		local hh = Vector3.new(s.heading.X, 0, s.heading.Z)
		heading = hh.Magnitude > 1e-3 and hh.Unit or Vector3.new(0, 0, -1)
		st.heading = heading
	else
		heading = ChaseCam.headingFor(st, s.travel, s.dt)
	end
	ChaseCam.sideFor(st, s.pos, heading, s.hunterPos, s.dt)

	--[[ Framing state, hysteretic. A flip sets st.snap: the caller resets its
		follower so the camera CUTS to the new position instead of travelling
		through the hunter to get there. ]]
	do
		local L = ChaseCam.LOCKED
		local was = st.framing
		local now
		if not s.dist then
			now = false
		elseif was then
			now = s.dist <= L.FRAME_OUT
		else
			now = s.dist <= L.FRAME_IN
		end
		if was ~= nil and was ~= now then
			-- a snap is a cut to the eye: it waits out the hold, and starts one
			local held = (s.t - (st.lastCut or -1e9)) < D.MIN_HOLD
			local urgent = now and s.dist ~= nil and s.dist < L.URGENT
			if held and not urgent then
				now = was
			else
				st.snap = true
				st.lastCut = s.t
			end
		end
		st.framing = now
	end
	st.started = st.started or s.t
	st.shot = st.shot or "establish"
	st.cause = st.cause or "opening: where it is, and where home is"
	local cut = false

	--[[ The trend, in signed studs. Negative = the gap is shrinking.

		Both followers are seeded to the first reading, so there is no startup
		transient to be mistaken for a chase -- otherwise the lagging one
		climbs from zero and the camera opens every chase by announcing that
		something is gaining on you. ]]
	local dt = s.dt or 0
	local striking = (s.windup or s.lunging) and true or false
	if striking then st.lastStrike = s.t end
	if not s.dist then
		st.fast, st.slow = nil, nil
	elseif not st.fast then
		st.fast, st.slow = s.dist, s.dist
	elseif striking then
		--[[ Rule 3: freeze. The ground a lunge covers is the lunge, not a
			trend, and must not be read as one. ]]
		st.struck = true
	elseif st.struck then
		--[[ The strike is over. Re-seed both followers to the gap it left, so
			the next reading is about what happens NEXT rather than about the
			attack the camera already showed. ]]
		st.fast, st.slow = s.dist, s.dist
		st.closing, st.away, st.struck = false, false, false
	elseif dt > 0 then
		st.fast += (s.dist - st.fast) * (1 - math.exp(-dt / D.TREND_FAST))
		st.slow += (s.dist - st.slow) * (1 - math.exp(-dt / D.TREND_SLOW))
	end
	local trend = (st.fast and st.slow) and (st.fast - st.slow) or 0
	st.trend = trend

	-- sticky bands, so neither claim can chatter around its threshold
	st.closing = st.closing and (trend < D.CLOSE_OUT) or (not st.closing and trend < D.CLOSE_IN)
	st.away = st.away and (trend > D.AWAY_OUT) or (not st.away and trend > D.AWAY_IN)
	--[[ "You pulled away" is only true of something that was ON you. Without
		this it fires on any distance increase, including the hunter merely
		re-forming behind you, which is a cut saying nothing. ]]
	if s.dist and s.dist < D.NEAR then st.wasNear = true end

	local function to(shot, cause, urgent)
		if shot == st.shot then
			st.cause = cause
			return
		end
		if not urgent and (s.t - (st.lastCut or -1e9)) < D.MIN_HOLD then return end
		st.shot, st.cause, st.lastCut, cut = shot, cause, s.t, true
	end

	local carrySpeed = math.max(s.carrySpeed or 16, 1)
	local boosting = (s.speed or 0) > carrySpeed * D.BOOST

	if s.lunging then
		--[[ Rule 2: hold. Deliberately not a cut. ]]
		st.cause = "holding the shot through the strike"
	elseif s.windup then
		to("threat", "it is winding up to lunge", true)
	elseif not s.dist then
		to("carry", "nobody is chasing you")
	elseif s.t - st.started < D.ESTABLISH then
		to("establish", "opening: where it is, and where home is", true)
	elseif s.homeDist and s.homeDist <= D.HOME_NEAR then
		--[[ Above the strike band on purpose. In the last fifty studs the
			player needs the door; the tell still outranks everything, so they
			do not lose the one thing they must react to. ]]
		to("homerun", "the door is in reach: look where you are going")
	elseif st.lastStrike and (s.t - st.lastStrike) <= D.EPISODE and s.dist <= D.STRIKE_BAND then
		--[[ RULE 4, and it needed to sit above the trend to work.

			Mid-attack the trend is not information. The gap slams shut and
			springs back on the hunter's own 3.2 second cycle, so "it is
			gaining" and "you got away" are both true several times a minute
			and neither is worth saying -- that alternation, measured at 26 to
			27 cuts in 45 seconds, is the flicker.

			The tell is what matters in here and it has already been handled
			above. So: hold. One cut in, one cut out, however many blows land
			in between. ]]
		st.cause = "mid-attack and still in reach: only the tell is worth cutting for"
	elseif st.shot == "threat" then
		--[[ Leaving the attack. There are two different ways out and they are
			not the same statement, so they do not get the same sentence.

			The first draft said "you are out of its reach now" for both, and
			the edit printed by tools/chase_edit caught it lying: a STAR
			hunter lunges from 16 studs, and the line appeared at a gap of
			16.1. Saying a true thing and saying it for the right reason are
			different problems, and only the second one survives a player
			learning what the angle means. ]]
		if s.dist > D.STRIKE_BAND then
			to("chase", "you are out of its reach now")
		else
			to("chase", "it has stopped pressing you")
		end
	elseif boosting then
		to("hero", "you boosted")
	elseif st.closing and s.dist <= D.FAR then
		to("closing", "it is gaining on you")
	elseif st.away and st.wasNear then
		if st.shot ~= "gaining" then st.wasNear = false end
		to("gaining", "you got away from it")
	else
		to("chase", "it is holding station behind you")
	end

	return st.shot, st.cause, cut
end

return ChaseCam
