--[[ chasecam.spec.luau -- the EDIT, tested.

	The camera has now been "fixed" three times against the same complaint:
	the cuts do not mean anything. Each time the fix was judged by watching a
	recording, which can show that an edit is bad and cannot show why, so each
	time the wrong thing got fixed (flicker, then framing, then clearance).

	ChaseCam.direct is pure for this reason: a scripted chase can be driven
	through it frame by frame and the resulting edit asserted. What these tests
	check is not "does it look good" -- no test can -- but the properties that
	have to hold for an edit to be readable at all:

	  * a cut only ever happens because the world changed
	  * every cut carries the sentence it is making
	  * the shot taken on the tell survives the strike
	  * two opposite claims cannot both be made, and cannot chatter
	  * a cut actually changes the frame enough to be seen as a cut
]]
local C = require("../../src/ReplicatedStorage/ChaseCam")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local DT = 1 / 60
local function ChaseCam_headingFor(st, travel, dt) return C.headingFor(st, travel, dt) end

--[[ Run a scripted chase. `world(t, frame)` returns the director's input for
	that instant; everything else is bookkeeping. Returns the cut list. ]]
local function run(seconds, world)
	local st, cuts, t = {}, {}, 0
	local frames = math.floor(seconds / DT)
	for i = 1, frames do
		t += DT
		local w = world(t, i) or {}
		w.t, w.dt = t, DT
		w.carrySpeed = w.carrySpeed or 16
		w.speed = w.speed or 16
		local shot, cause, cut = C.direct(st, w)
		if cut then table.insert(cuts, { t = t, shot = shot, cause = cause }) end
	end
	return cuts, st
end

local function after(cuts, t)
	local out = {}
	for _, c in ipairs(cuts) do
		if c.t > t then table.insert(out, c) end
	end
	return out
end

local function names(cuts)
	local out = {}
	for _, c in ipairs(cuts) do table.insert(out, c.shot) end
	return table.concat(out, " -> ")
end

-- ===================================================================
-- 1. THE HEADLINE. A world that stops changing must stop cutting.
-- ===================================================================
--[[ This is the test the old director could not have passed. It cut whenever
	its hold expired, so a chase in which absolutely nothing happened still
	produced an edit -- a cut caused by the clock, which from the player's
	seat has no cause at all. That is the single likeliest source of "there is
	no reasoning to the angle switching", and it is now structurally
	impossible: there is no timer branch to fire. ]]
test("nothing happens, nothing cuts: 60s of a hunter holding station = 0 cuts after it settles", function()
	local cuts = run(60, function()
		return { dist = 15 }
	end)
	local late = after(cuts, 3)
	assert(#late == 0, ("%d cuts with a motionless world: %s"):format(#late, names(late)))
	-- and the opening still happened, so this is not just a dead director
	assert(#cuts >= 1, "the opening shot never gave way")
end)

test("every cut carries the sentence it is making", function()
	local cuts = run(45, function(t)
		local dist = 24 - 10 * math.sin(t * 0.35)       -- closes and opens, slowly
		return { dist = dist, windup = (t % 9 > 8.4 and t % 9 < 8.9), homeDist = 400 - t * 6 }
	end)
	assert(#cuts > 4, "a varied chase produced almost no edit: " .. #cuts)
	for _, c in ipairs(cuts) do
		assert(type(c.cause) == "string" and #c.cause > 8,
			("cut to %s at %.2fs has no cause"):format(c.shot, c.t))
	end
end)

-- ===================================================================
-- 2. YOU CUT BEFORE AN ACTION, NOT DURING IT.
-- ===================================================================
test("the tell cuts instantly, and the strike is HELD", function()
	--[[ ChaseRules: WINDUP 0.5 then LUNGE_TIME 0.8. The cut has to land on the
		crouch -- late is worse than never, because the player is being asked
		to react to it -- and then not move again until the lunge is over, or
		the edit hides the one frame the mechanic exists to show. ]]
	local cuts = run(12, function(t)
		local phase = t % 4
		return {
			dist = 11,
			windup = phase >= 2.0 and phase < 2.5,
			lunging = phase >= 2.5 and phase < 3.3,
		}
	end)
	local threats = 0
	for _, c in ipairs(cuts) do
		if c.shot == "threat" then
			threats += 1
			local phase = c.t % 4
			assert(phase >= 2.0 and phase < 2.55,
				("the tell cut landed at phase %.2f, not on the crouch"):format(phase))
		end
		-- nothing may cut while the lunge is in the air
		local p = c.t % 4
		assert(not (p >= 2.55 and p < 3.3),
			("cut to %s mid-lunge at phase %.2f"):format(c.shot, p))
	end
	--[[ ONE cut, held. The hunter never leaves lunge range here, so after the
		first tell takes the camera there is nothing left to cut for -- which
		is the point of rule 4, not a failure to notice the later tells. ]]
	assert(threats == 1, ("the tell should cut once and hold, got %d"):format(threats))
end)

test("MIN_HOLD covers windup + lunge, so the tell's shot cannot be cut out from under the strike", function()
	local R = 0.5 + 0.8                    -- ChaseRules.WINDUP + LUNGE_TIME
	assert(C.DIR.MIN_HOLD >= R,
		("MIN_HOLD %.2f is shorter than a whole lunge (%.2f)"):format(C.DIR.MIN_HOLD, R))
end)

-- ===================================================================
-- 3. THE RATE IS THE INFORMATION -- and it must not chatter.
-- ===================================================================
test("it is gaining / you got away are opposites, and both read correctly", function()
	-- closes hard from 26 to 7, then is shaken off back out to 30
	local cuts = run(24, function(t)
		local dist
		if t < 10 then dist = 26 - t * 1.9 else dist = 7 + (t - 10) * 1.7 end
		return { dist = math.clamp(dist, 5, 34) }
	end)
	local seq = names(cuts)
	local iC, iG = seq:find("closing"), seq:find("gaining")
	assert(iC, "closing in hard never cut to `closing`: " .. seq)
	assert(iG, "shaking it off never cut to `gaining`: " .. seq)
	assert(iC < iG, "the edit told the story backwards: " .. seq)
end)

--[[ Drive a chase sampled the way the client really receives it: ChaseDist is
	a replicated attribute arriving at about 10 Hz and held in between, so what
	the director sees is a staircase, which is a harsher signal than a sine.
	`at(t)` returns dist, windup, lunging. ]]
local function drive(seconds, at, settle)
	local st, cuts, t, peak = {}, {}, 0, 0
	local held, w, l, nextS = nil, false, false, 0
	for _ = 1, math.floor(seconds / DT) do
		t += DT
		if t >= nextS then
			nextS = t + 0.1
			held, w, l = at(t)
		end
		local shot, cause, cut = C.direct(st, {
			t = t, dt = DT, dist = held, windup = w, lunging = l,
			speed = 16, carrySpeed = 16,
		})
		if t > (settle or 3) then
			if cut then table.insert(cuts, { t = t, shot = shot, cause = cause }) end
			peak = math.max(peak, math.abs(st.trend or 0))
		end
	end
	return cuts, peak
end

--[[ THE PHYSICAL BOUND ON WOBBLE, and why it is in the test.

	My first version of this test swept amplitudes up to 2 studs at 1.5 Hz and
	"found" a 35-cut strobe. That signal is a relative speed of nearly 19
	studs/s between player and hunter. ChaseRules has the hunter jogging at
	0.94x your speed -- about 1 stud/s of drift -- and lunging at 1.4x, so
	outside a lunge the gap simply cannot move that fast. The test was finding
	noise that does not exist, which is worse than finding nothing: it would
	have sent the next fix at the filter instead of at the cause.

	So the sweep is bounded by what the rules allow. 3 studs/s is already
	generous -- it covers the junior second hunter at 0.86x plus the player's
	own speed changes -- and amplitude follows from the frequency. ]]
local MAX_REL = 3.0   -- studs/s of gap movement available outside a lunge

test("ANTI-FLICKER: nothing the jog can physically do makes the camera cut", function()
	local worst, worstCase, peak = 0, "", 0
	for _, hz in ipairs({ 0.4, 0.7, 1.0, 1.4, 2.0, 3.0 }) do
		local amp = MAX_REL / (2 * math.pi * hz)
		local cuts, p = drive(45, function(t)
			return 15 + amp * math.sin(t * 2 * math.pi * hz), false, false
		end)
		peak = math.max(peak, p)
		if #cuts > worst then
			worst, worstCase = #cuts, ("%.1f Hz at %.2f studs"):format(hz, amp)
		end
	end
	assert(worst == 0, ("%s produced %d cuts"):format(worstCase, worst))
	--[[ The margin as a number rather than as trust, so the next tuning change
		cannot quietly reintroduce the strobe without failing something. ]]
	local margin = math.abs(C.DIR.CLOSE_IN) / math.max(peak, 1e-6)
	assert(margin >= 1.6,
		("only %.2fx margin: peak reachable wobble %.2f studs vs CLOSE_IN %.2f"):format(
			margin, peak, C.DIR.CLOSE_IN))
end)

test("THE REAL STROBE: a hunter lunging every 3.2s must not re-cut on its own lunges", function()
	--[[ This is the one that was actually happening, and the only scenario in
		which either director ever flickered. Measured before the fix, with
		the lunge's distance change allowed to feed the trend: 28 cuts in 45
		seconds, one every 1.5 s, closing -> gaining -> closing forever.

		ChaseRules: WINDUP 0.5, LUNGE_TIME 0.8, LUNGE_EVERY 3.2. The gap slams
		shut by roughly 5 studs and drifts back out, every cycle, for the whole
		chase. An edit that reports that faithfully is a strobe; an edit that
		understands a lunge is an EVENT cuts once, on the tell, and holds.

		So: at most one cut per lunge cycle, and it has to be the one onto the
		tell. ]]
	local CYCLE = 3.2
	local cuts = drive(45, function(t)
		local p = t % CYCLE
		local windup = p >= 1.0 and p < 1.5
		local lunging = p >= 1.5 and p < 2.3
		-- closes hard through the lunge, then the jog lets it drift back out
		local dist
		if p < 1.5 then dist = 13
		elseif p < 2.3 then dist = 13 - (p - 1.5) * 5.6
		else dist = 8.5 + (p - 2.3) * 4.5 end
		return dist, windup, lunging
	end, 0)
	--[[ ONE cut, not one per blow. The hunter never leaves lunge range in this
		scenario, so the threat never recedes, so the shot never changes. ]]
	assert(#cuts <= 2, ("%d cuts over 13 lunge cycles: %s"):format(#cuts, names(cuts)))
	assert(cuts[1] and cuts[1].shot == "threat",
		"the tell did not take the camera: " .. names(cuts))
end)

test("after a strike the camera does not restate what the player just watched", function()
	--[[ One lunge, then a steady gap. The edit should be: cut onto the tell,
		hold through the strike, come home once -- and then nothing, because
		nothing further has happened. Any extra cut here is the camera
		announcing the ground the lunge covered, which the player saw. ]]
	local cuts = drive(16, function(t)
		local windup = t >= 5.0 and t < 5.5
		local lunging = t >= 5.5 and t < 6.3
		local dist
		if t < 5.5 then dist = 13
		elseif t < 6.3 then dist = 13 - (t - 5.5) * 5.6
		else dist = math.min(30, 8.5 + (t - 6.3) * 3.0) end
		return dist, windup, lunging
	end, 2)
	--[[ One lunge at 13 studs, then the player breaks away to 30. The edit is
		two cuts: onto the tell, then home once they are genuinely out of
		reach. Nothing in between, because nothing else happened. ]]
	assert(#cuts == 2, ("expected tell + release, got %d: %s"):format(#cuts, names(cuts)))
	assert(cuts[1].shot == "threat", "the tell did not take the camera: " .. names(cuts))
	assert(cuts[2].shot == "chase", "the camera never came home: " .. names(cuts))
	assert(cuts[2].cause:find("out of its reach"),
		"the release cut did not name itself: " .. cuts[2].cause)
	--[[ ...and it must only say that when it is TRUE. The same exit taken
		while still inside lunge range gets a different sentence, because a
		hunter at 16 studs with a 16-stud range has not been escaped. ]]
	assert(cuts[1].t < 5.6, ("the tell cut landed late, at %.2fs"):format(cuts[1].t))
end)

test("but a real change still gets through: a 2 stud/s close cuts within a second", function()
	local cuts = run(8, function(t)
		return { dist = 19 - t * 2.2 }
	end)
	local found
	for _, c in ipairs(cuts) do
		if c.shot == "closing" then found = c.t break end
	end
	assert(found, "a genuine 2.2 studs/s close never cut: " .. names(cuts))
	assert(found < C.DIR.ESTABLISH + 1.4,
		("took %.2fs to notice it was gaining"):format(found))
end)

test("`you got away` is only said of something that was actually on you", function()
	--[[ Without the wasNear gate this fires on any distance increase -- a
		hunter merely re-forming behind you after a corner -- which is a cut
		that asserts something that did not happen. ]]
	local cuts = run(20, function(t)
		return { dist = 24 + t * 0.4 }        -- drifting apart, never close
	end)
	for _, c in ipairs(cuts) do
		assert(c.shot ~= "gaining", "claimed an escape that never happened: " .. names(cuts))
	end
end)

test("leaving an attack has two different sentences, because they are two different facts", function()
	--[[ Caught by tools/chase_edit, not by me reading the code: a STAR hunter
		lunges from 16 studs, and the camera was announcing "you are out of
		its reach now" at a gap of 16.1. The claim was false, and a shot whose
		sentence can be false is a shot the player cannot learn to read.

		One lunge, then it backs off to 15 and just sits there: the attack has
		ended, the reach has not. ]]
	local cuts = drive(16, function(t)
		local windup = t >= 5.0 and t < 5.5
		local lunging = t >= 5.5 and t < 6.3
		return (t < 5.5 and 16 or 15), windup, lunging
	end, 2)
	local exit
	for _, c in ipairs(cuts) do
		if c.shot == "chase" then exit = c end
	end
	assert(exit, "the camera never left the attack: " .. names(cuts))
	assert(exit.cause:find("stopped pressing"),
		"claimed an escape from something still in range: " .. exit.cause)
	assert(not exit.cause:find("out of its reach"), "said a false thing: " .. exit.cause)
end)

-- ===================================================================
-- 4. THE TWO NUMBERS. Home is the other one.
-- ===================================================================
test("near the door the camera stops looking back", function()
	local cuts = run(14, function(t)
		return { dist = 14, homeDist = 300 - t * 22 }
	end)
	local hit
	for _, c in ipairs(cuts) do if c.shot == "homerun" then hit = c.t end end
	assert(hit, "arriving home never changed the shot: " .. names(cuts))
	--[[ and the shot has to actually give up the hunter, or "look forward" is
		a claim the framing immediately contradicts. ]]
	local s = C.SHOTS.homerun
	assert((s.lead or 0) >= 10, "homerun does not lead the look down the road")
	assert((s.hold or 0) > C.T.HOLD_MAX, "homerun still drags the aim back to the hunter")
end)

test("no hunter, no chase camera theatrics", function()
	local cuts = run(6, function()
		return { dist = nil }
	end)
	local last = cuts[#cuts]
	assert(last and last.shot == "carry",
		"a walk-in carry with nobody chasing still got the chase edit: " .. names(cuts))
end)

-- ===================================================================
-- 5. A CUT HAS TO BE VISIBLE AS A CUT.
-- ===================================================================
test("every shot is far enough from every other to read as a cut, not a wobble", function()
	--[[ The old set-ups differed by as little as 3 studs of distance and 1.4
		of height -- smaller than the camera's own spring overshoot. A cut you
		cannot perceive is worse than no cut: the frame twitches, and the
		player reads a glitch. Score each pair; anything under the threshold
		is two shots that are really one. ]]
	local function score(a, b)
		local d = math.abs((a.dist or 0) - (b.dist or 0))
		local h = math.abs((a.height or 0) - (b.height or 0))
		local y = math.abs((a.yaw or 0) - (b.yaw or 0))
		local f = math.abs((a.fov or 0) - (b.fov or 0))
		local flip = ((a.flip and 1 or 0) ~= (b.flip and 1 or 0)) and 30 or 0
		-- weights: a degree of yaw and a stud of height are not the same thing
		return d * 1.2 + h * 2.4 + y * 0.6 + f * 0.7 + flip
	end
	local keys = {}
	for k in pairs(C.SHOTS) do table.insert(keys, k) end
	table.sort(keys)
	local worst, wa, wb = math.huge, nil, nil
	for i = 1, #keys do
		for j = i + 1, #keys do
			local s = score(C.SHOTS[keys[i]], C.SHOTS[keys[j]])
			if s < worst then worst, wa, wb = s, keys[i], keys[j] end
		end
	end
	assert(worst >= 12, ("`%s` and `%s` are the same shot (%.1f)"):format(tostring(wa), tostring(wb), worst))
end)

test("the flip is spent on exactly one meaning, so the flip itself is a word", function()
	local flipped = {}
	for k, s in pairs(C.SHOTS) do
		if s.flip then table.insert(flipped, k) end
	end
	table.sort(flipped)
	--[[ `threat` and `hero` are the two that flip, and they can never be live
		at the same time (a windup outranks a boost), so the shoulder change
		still means "something just happened to you" either way. ]]
	assert(#flipped <= 2, "the shoulder flip is used too often to mean anything: " .. table.concat(flipped, ", "))
	local hasThreat = false
	for _, k in ipairs(flipped) do if k == "threat" then hasThreat = true end end
	assert(hasThreat, "the loudest cut is not spent on the most important beat")
end)

test("the old shot names still resolve, so an older caller gets a frame", function()
	for _, old in ipairs({ "low", "wide", "flank" }) do
		local k = C.SHOT_ALIAS[old]
		assert(k and C.SHOTS[k], "alias " .. old .. " is dead")
	end
end)

-- ===================================================================
-- 5b. THE SHOULDER. This was the actual flicker.
-- ===================================================================
--[[ Found by running the chase in Studio and recording the camera every frame:
	per-frame jumps of 46.5, 28.8, 22.7 and 23.4 studs while the SHOT NEVER
	CHANGED. No cut, no director -- the lens teleporting around the player.

	Cause: solve chose its shoulder with sign(toHunter . right), and the hunter
	is directly behind you (this file measured dot(forward) = -1.00), so that
	quantity is ~0 and its SIGN is noise. Same class of mistake as reading a
	trend off an instantaneous rate, in a different function.

	These two tests are the ones that would have caught it before any of this
	reached a recording. ]]

test("THE REAL FLICKER: a reversing travel direction must not swing the camera", function()
	--[[ Taken from a live chase, sampled every 0.09 s. The camera aims along
		travel; movement is camera-relative; so camera yaw -> move direction ->
		velocity -> camera yaw, with nothing damping it. Recorded travel
		directions, in order, with dot() against the previous sample:

		    +0.36,+0.93  (+0.03)   -0.91,+0.42  (+0.07)
		    +0.67,+0.74  (-0.30)   -0.91,+0.42  (-0.29)
		    +0.78,+0.62  (-0.44)   -0.91,+0.42  (-0.45)
		    +0.86,+0.51  (-0.60)   -0.96,+0.27  (-0.68)
		    +0.87,+0.49  (-0.70)   -0.99,+0.12  (-0.80)

		The player advanced three studs in a second while reporting speed 20,
		and the camera swung ~25 studs across on every frame. This replays that
		exact sequence and requires the camera to stay put. ]]
	local REAL = {
		{ 0.36, 0.93 }, { -0.91, 0.42 }, { 0.67, 0.74 }, { -0.91, 0.42 },
		{ 0.78, 0.62 }, { -0.91, 0.42 }, { 0.83, 0.55 }, { -0.93, 0.38 },
		{ 0.86, 0.51 }, { -0.96, 0.27 }, { 0.87, 0.49 }, { -0.99, 0.12 },
	}
	local pos = Vector3.new(0, 3, 0)
	local st, prev, worst, worstTurn, lastH = {}, nil, 0, 0, nil
	for pass = 1, 6 do
		for _, tv in ipairs(REAL) do
			local travel = Vector3.new(tv[1], 0, tv[2]).Unit
			local h = ChaseCam_headingFor(st, travel, 0.09)
			if lastH and pass > 1 then
				worstTurn = math.max(worstTurn,
					math.deg(math.acos(math.clamp(h:Dot(lastH), -1, 1))))
			end
			lastH = h
			local hunter = pos - h * 14
			C.sideFor(st, pos, h, hunter, 0.09)
			local cf = C.solve({ shot = "chase", pos = pos, travel = h, hunterPos = hunter,
				side = st.side, dist = 14, speed = 20, carrySpeed = 20, mode = "C" })
			if prev and pass > 1 then worst = math.max(worst, (cf.Position - prev).Magnitude) end
			prev = cf.Position
		end
	end
	--[[ The invariant the fix actually provides is ANGULAR: the shot may not
		turn faster than TURN_MAX, whatever the input does. Studs-per-frame
		then follows from how far the lens happens to sit from the player, so
		it is the consequence, not the guarantee -- asserted too, because it is
		the number that was 25 to 46 before and is what a player sees. ]]
	local cap = C.T.TURN_MAX * 0.09
	assert(worstTurn <= cap + 0.5,
		("the shot turned %.1f deg in one frame against a %.1f deg cap"):format(worstTurn, cap))
	assert(worst < 7,
		("a reversing travel still swung the camera %.1f studs in one frame (was 25-46)"):format(worst))
end)

test("...but the smoothed heading still follows a real turn", function()
	--[[ The fix must not freeze the camera's sense of direction. A genuine
		90-degree corner has to arrive, and within about half a second, or the
		camera is looking at where you used to be going. ]]
	local st = {}
	for _ = 1, 30 do ChaseCam_headingFor(st, Vector3.new(0, 0, -1), 1 / 60) end
	local turned
	for i = 1, 120 do
		local h = ChaseCam_headingFor(st, Vector3.new(1, 0, 0), 1 / 60)
		if not turned and h:Dot(Vector3.new(1, 0, 0)) > 0.95 then turned = i / 60 end
	end
	assert(turned, "the heading never completed a 90-degree turn")
	assert(turned < 0.75, ("the turn took %.2f s, which is a camera looking backwards"):format(turned))
end)

test("THE FLICKER: sub-stud wobble behind the player must not move the camera", function()
	local pos, travel = Vector3.new(0, 3, 0), Vector3.new(0, 0, -1)
	for _, shot in ipairs({ "chase", "threat", "closing", "gaining" }) do
		local st, prev, worst = {}, nil, 0
		-- a hunter dead behind, jittering across the line by a hundredth of a stud
		for i = 1, 200 do
			local lat = ((i % 2 == 0) and 0.01 or -0.01) + 0.004 * math.sin(i * 1.7)
			local h = pos + Vector3.new(lat, 0, 14)
			C.sideFor(st, pos, travel, h, DT)
			local cf = C.solve({ shot = shot, pos = pos, travel = travel,
				hunterPos = h, side = st.side, dist = 14, speed = 20,
				carrySpeed = 20, mode = "C" })
			if prev then worst = math.max(worst, (cf.Position - prev).Magnitude) end
			prev = cf.Position
		end
		assert(worst < 0.5,
			("shot `%s`: a 0.01-stud wobble moved the camera %.1f studs in one frame"):format(shot, worst))
	end
end)

test("a REAL crossing still changes the shoulder, as a sweep and not a teleport", function()
	--[[ The fix must not simply freeze the shoulder. When the hunter genuinely
		cuts across behind you the camera is supposed to change sides -- it
		just has to travel there. ]]
	local pos, travel = Vector3.new(0, 3, 0), Vector3.new(0, 0, -1)
	local st, prev, worst, frames = {}, nil, 0, 0
	local startSide, endSide
	for i = 1, 240 do
		-- hunter slides from 6 studs left of the line to 6 studs right
		local lat = -6 + 12 * math.min(1, i / 60)
		local h = pos + Vector3.new(lat, 0, 14)
		C.sideFor(st, pos, travel, h, DT)
		startSide = startSide or st.side
		endSide = st.side
        local cf = C.solve({ shot = "chase", pos = pos, travel = travel,
			hunterPos = h, side = st.side, dist = 14, speed = 20, carrySpeed = 20, mode = "C" })
		if prev then
			local d = (cf.Position - prev).Magnitude
			worst = math.max(worst, d)
			if d > 0.05 then frames += 1 end
		end
		prev = cf.Position
	end
	assert(startSide < -0.9 and endSide > 0.9,
		("the shoulder never actually changed: %.2f -> %.2f"):format(startSide, endSide))
	assert(worst < 6, ("the swap was still a teleport: %.1f studs in one frame"):format(worst))
	assert(frames * DT > 0.3,
		("the swap took only %.2f s, which reads as a glitch"):format(frames * DT))
end)

-- ===================================================================
-- 6. REGRESSION: the framing fixes must survive the new shots.
-- ===================================================================
test("no shot may eat the clearance that keeps the hunter out of the lens", function()
	--[[ The recording that started this showed a torso filling half the frame:
		CLEAR guaranteed 7 studs behind the hunter and then shot.dist was
		subtracted from the result, so `hero` left 3. solve re-enforces the
		clearance afterwards; this checks it still does, through every shot
		and at the distances where it bites. ]]
	local pos = Vector3.new(0, 3, 0)
	local travel = Vector3.new(0, 0, -1)
	for name in pairs(C.SHOTS) do
		for _, d in ipairs({ 4, 6, 9, 14, 20 }) do
			local hunterPos = pos - travel * d
			local cf = C.solve({
				shot = name, pos = pos, travel = travel, hunterPos = hunterPos,
				dist = d, speed = 18, carrySpeed = 16, mode = "C",
			})
			local gap = (cf.Position - hunterPos).Magnitude
			assert(gap >= 6.0,
				("shot `%s` at %d studs put the lens %.2f from the hunter"):format(name, d, gap))
		end
	end
end)

-- ===================================================================
-- 7. WALLS: the lens comes in front of a wall at once and goes back out eased.
-- ===================================================================
test("with nothing in the way the wall check changes nothing, every frame", function()
	local st = {}
	for _ = 1, 120 do
		local d = C.occlude(st, 30, nil, DT)
		assert(d == 30, ("open air moved the lens to %.3f"):format(d))
	end
end)

test("a wall pulls the lens in front of it on the very first frame", function()
	local O = C.OCCLUDE
	local d = C.occlude({}, 30, 12, DT)
	assert(math.abs(d - (12 - O.MARGIN)) < 1e-9, ("wanted %.2f, got %.3f"):format(12 - O.MARGIN, d))
end)

test("the lens never goes past a wall that is still there, even while easing out", function()
	local O = C.OCCLUDE
	local st = {}
	C.occlude(st, 30, 6, DT)                 -- a close wall: pulled in hard
	for _ = 1, 240 do                        -- the wall backs off to 20 and stays
		local d = C.occlude(st, 30, 20, DT)
		assert(d <= 20 - O.MARGIN + 1e-9, ("lens at %.3f is past the wall at 20"):format(d))
	end
end)

test("when the wall goes, the lens eases back out instead of snapping", function()
	local st = {}
	C.occlude(st, 30, 8, DT)
	local first = C.occlude(st, 30, nil, DT)
	assert(first < 12, ("one frame after the wall left the lens jumped to %.2f"):format(first))
	local d = first
	for _ = 1, 180 do                        -- 3 s, about 8.5 time constants
		local nd = C.occlude(st, 30, nil, DT)
		assert(nd >= d - 1e-9, "easing out must never move the lens back in")
		d = nd
	end
	assert(d > 29.9, ("3 s after the wall left the lens is still at %.2f"):format(d))
end)

test("a wall right at the player still leaves the lens MIN studs out", function()
	local O = C.OCCLUDE
	local d = C.occlude({}, 30, 0.2, DT)
	assert(math.abs(d - O.MIN) < 1e-9, ("got %.3f, wanted MIN %.1f"):format(d, O.MIN))
	-- and a shot that already sits closer than MIN is left alone
	assert(C.occlude({}, 1.5, 0.2, DT) == 1.5, "a shot already inside MIN was moved")
end)

return T
