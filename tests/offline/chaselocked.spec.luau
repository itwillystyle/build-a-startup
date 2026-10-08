--[[ chaselocked.spec.luau -- the locked chase camera (7 Oct control spec, A + B).

	Two promises, both checked here rather than trusted:

	  W IS FORWARD. The camera faces the player's own heading exactly, on every
	  shot, so no cut, no shoulder change and no framing rule can ever change
	  which way the movement keys go. The recording that prompted this:
	  "I don't even know if W is moving me forwards or backwards."

	  THE FRAME IS READABLE. Every shot, at every hunter distance, on every
	  screen shape, passes ChaseFrame's screen-space contract -- player centred
	  and big enough, hunter framed and not filling the frame, horizon level.
	  Before the lens-gives-way rule: 126 of 648 framings failed it.
]]
local C = require("../../src/ReplicatedStorage/ChaseCam")
local F = require("../../src/ReplicatedStorage/ChaseFrame")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local SHOTS = { "carry", "establish", "chase", "closing", "gaining", "threat", "hero", "homerun" }
local ASPECTS = { 16 / 9, 844 / 390, 1530 / 255 }   -- desktop, landscape phone, Studio's viewport
local POS = Vector3.new(0, 3, 0)

local function headingAt(deg)
	return C.headingOfYaw(math.rad(deg))
end

--[[ Yaw error measured with asin(|a x b|), not acos(a . b). acos is
	ill-conditioned near 1: float32 rounding alone reads as ~0.02 deg there
	(measured: 0.0198 deg by acos, 0.000043 deg by asin(cross), same frames).
	ChaseFrame.yawFrom uses acos and that is fine for its 25-degree rule; this
	test asserts the lock to a thousandth of a degree, which acos cannot. ]]
local function yawError(cf, h)
	local l = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z).Unit
	local hh = Vector3.new(h.X, 0, h.Z).Unit
	return math.deg(math.asin(math.min(math.abs(l.X * hh.Z - l.Z * hh.X), 1))), l:Dot(hh)
end

-- ===================================================================
-- W IS FORWARD
-- ===================================================================
test("W IS FORWARD: on every shot and heading, the camera faces the heading exactly", function()
	for deg = 0, 345, 15 do
		local h = headingAt(deg)
		for _, shot in ipairs(SHOTS) do
			for _, side in ipairs({ 1, -1, 0.3 }) do
				local cf = C.solveLocked({ pos = POS, heading = h, shot = shot, side = side,
					dist = 10, speed = 20, carrySpeed = 18 })
				local yaw, facing = yawError(cf, h)
				assert(facing > 0, ("heading %d shot %s: camera faces BACKWARDS"):format(deg, shot))
				assert(yaw < 0.001, ("heading %d shot %s side %.1f: camera is %.5f deg off the heading"):format(deg, shot, side, yaw))
			end
		end
	end
end)

test("a cut never changes which way W goes", function()
	local h = headingAt(37)
	local ref = C.solveLocked({ pos = POS, heading = h, shot = "chase", side = 1, dist = 9 })
	for _, shot in ipairs(SHOTS) do
		local cf = C.solveLocked({ pos = POS, heading = h, shot = shot, side = -1, dist = 9 })
		local a = Vector3.new(ref.LookVector.X, 0, ref.LookVector.Z).Unit
		local b = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z).Unit
		assert(a:Dot(b) > 0.99999, ("cutting to %s turned W by %.4f deg"):format(shot, math.deg(math.acos(math.clamp(a:Dot(b), -1, 1)))))
	end
end)

test("the camera is always BEHIND the player, never in front of them", function()
	--[[ A camera in front of the player inverts W -- the old `hero` shot did. ]]
	for _, shot in ipairs(SHOTS) do
		local h = headingAt(0)
		local cf = C.solveLocked({ pos = POS, heading = h, shot = shot, side = 1, dist = 6 })
		local along = (POS - cf.Position):Dot(h)
		assert(along > 0, ("shot %s put the camera %.2f studs in FRONT of the player"):format(shot, -along))
	end
end)

test("yawOf / headingOfYaw round-trip, so the chase starts facing where you were", function()
	for deg = -170, 170, 20 do
		local h = headingAt(deg)
		local cf = CFrame.lookAt(Vector3.zero, h)
		local back = C.headingOfYaw(C.yawOf(cf))
		assert(back:Dot(h) > 0.99999, ("yaw %d did not round-trip"):format(deg))
	end
end)

-- ===================================================================
-- THE FRAME IS READABLE
-- ===================================================================
test("THE CONTRACT: every shot, every hunter distance, three screen shapes", function()
	local fails, total, first = 0, 0, nil
	for _, aspect in ipairs(ASPECTS) do
		for _, shot in ipairs(SHOTS) do
			for _, d in ipairs({ 4, 6, 8, 10, 14, 18, 20, 25, 0 }) do
				for _, lat in ipairs({ 0, 2.5, -2.5 }) do
					for _, speed in ipairs({ 0, 18, 26 }) do
						total += 1
						local h = Vector3.new(0, 0, -1)
						local hunterPos = d > 0 and (POS - h * d + Vector3.new(lat, 0, 0)) or nil
						local cf, fov = C.solveLocked({ pos = POS, heading = h, shot = shot, side = 1,
							dist = d > 0 and d or nil, speed = speed, carrySpeed = 18 })
						local r = F.check(cf, fov, aspect, { playerPos = POS, heading = h, hunterPos = hunterPos })
						if not r.ok then
							fails += 1
							first = first or ("aspect %.2f shot %s d %d lat %.1f speed %d: %s"):format(
								aspect, shot, d, lat, speed, table.concat(r.failures, "; "))
						end
					end
				end
			end
		end
	end
	assert(fails == 0, ("%d of %d framings break the contract, e.g. %s"):format(fails, total, tostring(first)))
end)

test("when a far hunter and a wide lens cannot both be framed, the LENS gives way", function()
	local h = Vector3.new(0, 0, -1)
	local _, near = C.solveLocked({ pos = POS, heading = h, shot = "hero", dist = 6, speed = 26, carrySpeed = 18 })
	local _, far = C.solveLocked({ pos = POS, heading = h, shot = "hero", dist = 20, speed = 26, carrySpeed = 18 })
	assert(far < near, ("a far hunter should narrow the lens: near %.1f far %.1f"):format(near, far))
end)

test("THE THRESHOLD: a hunter breathing across 20 studs never flashes through the lens", function()
	--[[ The live 168% frame, reproduced. ChaseRules sprints the hunter beyond
		20 studs and jogs it inside, so it SETTLES at 20 -- exactly where the
		camera used to switch between "behind the hunter" and "close behind the
		player". Each crossing jumped the camera target 16-20 studs, and any
		continuous move between those places passes through the hunter.

		Measured against the single-threshold version: the hunter reached 0.31
		of the frame and the camera made 12 moves of more than 3 studs in one
		frame with NO cut or snap behind them. With hysteresis (frame at 20,
		release past 25) and a snap on the switch: 0.25, and every big move is
		a named cut or snap. Player runs at 20, turns at 57 deg/s from 3-5 s.

		7 Oct, later: also at 69 and 120 deg/s, the rates measured from the
		recordings, and with the spring the client actually uses (the player's
		heading frame). A jump is measured RELATIVE TO THE PLAYER, because the
		player moving is not the camera jumping. ]]
	--[[ The size bound is 0.30 on every real screen. On a window wider than a
		landscape phone (Studio's play strip) a 75-degree vertical lens sees
		~150 degrees across, and a trailing hunter that ends up BESIDE the lens
		on a hard turn passes the extreme edge for a moment; measured 0.37 of
		the frame for 0.12 s at 3.6:1 and 0.51 for 0.20 s at 6:1. That is
		allowed as a pass at the edge, never as a hold: at most 0.25 s. ]]
	local worst, worstAt, unexplained, detail = 0, "", 0, ""
	local longest, longestAt = 0, ""
	--[[ Two hunters: one that BREATHES across 20 (sprints out there, jogs in
		here), and one that TRAILS -- a touch slower than you, starting just
		outside the framing range, so on a turn it cuts the corner and swings
		in beside the lens. The trailing one is the 7 Oct live jump: 10 studs in
		one frame, mid-turn, no cut behind it. ]]
	for _, kind in ipairs({ "breathe", "trail" }) do
	for _, turn in ipairs({ 0, 57.3, -57.3, 69, -120 }) do
		for _, aspect in ipairs(ASPECTS) do
			local pos, yaw = POS, 0
			local hunter = pos - C.headingOfYaw(yaw) * (kind == "trail" and 21 or 24)
			local st, dir, lastCam = {}, {}, nil
			local run = 0
			for i = 0, 600 do
				local t = i / 60
				if t > 3 and t < 5 then yaw += math.rad(turn) / 60 end
				local h = C.headingOfYaw(yaw)
				pos += h * (20 / 60)
				local to = pos - hunter
				local sp = kind == "trail" and 18 or ((to.Magnitude > 20) and 22.5 or 17)
				if to.Magnitude > 0.1 then hunter += Vector3.new(to.X, 0, to.Z).Unit * (sp / 60) end
				local d = (pos - hunter).Magnitude
				local shot, _, cut = C.direct(dir, { t = t, dt = 1 / 60, dist = d, pos = pos, heading = h, hunterPos = hunter })
				local snap = dir.snap
				dir.snap = false
				if cut or snap then st = {} end
				local target, fov = C.solveLocked({ pos = pos, heading = h, side = dir.side, shot = shot, dist = d,
					hunterPos = hunter, framing = dir.framing, speed = 20, carrySpeed = 18, aspect = aspect })
				local cf = C.follow(st, target, 1 / 60, "C", 0, { anchor = pos, heading = h })
				cf = C.clearLens(cf, fov, { pos = pos, hunterPos = hunter, aspect = aspect })
				local rel = cf.Position - pos
				if lastCam and (rel - lastCam).Magnitude > 3 and not (cut or snap) then
					unexplained += 1
					detail = ("%s turn %.0f t %.2f d %.1f jump %.1f"):format(kind, turn, t, d, (rel - lastCam).Magnitude)
				end
				lastCam = rel
				local r = F.check(cf, fov, aspect, { playerPos = pos, heading = h, hunterPos = hunter })
				local hh = r.metrics.hunterOnScreen and r.metrics.hunterH or 0
				if aspect <= 2.2 then
					if hh > worst then worst, worstAt = hh, ("%s turn %.0f aspect %.2f t %.2f d %.1f"):format(kind, turn, aspect, t, d) end
				else
					run = hh > 0.30 and run + 1 or 0
					if run > longest then longest, longestAt = run, ("%s turn %.0f aspect %.2f t %.2f"):format(kind, turn, aspect, t) end
				end
			end
		end
	end
	end
	assert(unexplained == 0, ("%d camera jumps over 3 studs with no cut or snap behind them, e.g. %s"):format(unexplained, detail))
	assert(worst <= 0.30, ("the hunter reached %.2f of the frame at %s"):format(worst, worstAt))
	assert(longest <= 15, ("on a wide window the hunter stayed over 0.30 for %d frames at %s"):format(longest, longestAt))
end)

test("framing is hysteretic: in at 20, out only past 25, and the switch asks for a snap", function()
	local L = C.LOCKED
	local dir = {}
	local function feed(d, i) return C.direct(dir, { t = i / 60, dt = 1 / 60, dist = d, pos = POS, heading = headingAt(0) }) end
	feed(30, 0)
	assert(dir.framing == false, "a hunter at 30 studs should not be framed")
	feed(L.FRAME_IN - 0.1, 1)
	assert(dir.framing == true and dir.snap == true, "crossing in to FRAME_IN must frame it and request a snap")
	dir.snap = false
	for i, d in ipairs({ 21, 23, L.FRAME_OUT - 0.1 }) do feed(d, 1 + i) end
	assert(dir.framing == true and not dir.snap, "between 20 and 25 the framing must HOLD, without a snap")
	feed(L.FRAME_OUT + 0.1, 9)
	assert(dir.framing == true and not dir.snap, "a release 0.15 s after the last snap must wait out MIN_HOLD")
	feed(L.FRAME_OUT + 0.1, 1 + math.ceil(C.DIR.MIN_HOLD * 60) + 1)
	assert(dir.framing == false and dir.snap == true, "past FRAME_OUT, after the hold, it must release with a snap")
end)

-- ===================================================================
-- MOTION: the spring and the bank
-- ===================================================================
local function settle(st, target, frames, steer)
	local cf
	for _ = 1, frames do cf = C.follow(st, target, 1 / 60, "C", steer) end
	return cf
end

test("the horizon is level when you are not steering", function()
	local target = C.solveLocked({ pos = POS, heading = headingAt(0), dist = 12 })
	local cf = settle({}, target, 120, 0)
	assert(math.abs(F.tilt(cf)) < 0.05, ("tilt %.3f deg with no steering"):format(F.tilt(cf)))
end)

test("steering banks the horizon, never past 8 degrees", function()
	local target = C.solveLocked({ pos = POS, heading = headingAt(0), dist = 12 })
	for _, rate in ipairs({ 0.5, 2, 6, 40 }) do
		for _, sign in ipairs({ 1, -1 }) do
			local cf = settle({}, target, 180, rate * sign)
			local tilt = F.tilt(cf)
			assert(math.abs(tilt) <= 8.01, ("steer %.1f rad/s banked %.2f deg"):format(rate * sign, tilt))
			assert(math.abs(tilt) > 0.5, ("steer %.1f rad/s did not bank at all (%.3f)"):format(rate * sign, tilt))
		end
	end
	-- and the bank follows the direction of the turn
	local left = F.tilt(settle({}, target, 180, 2))
	local right = F.tilt(settle({}, target, 180, -2))
	assert(left * right < 0, ("turning left and right banked the same way (%.2f, %.2f)"):format(left, right))
end)

test("the spring settles without ringing: overshoot under 4% of a step", function()
	--[[ The old spring (damping ratio 0.40) overshot on every input and rang
		back, which is most of what was reported as swaying. ]]
	local a = C.solveLocked({ pos = POS, heading = headingAt(0), dist = 12 })
	local st = {}
	settle(st, a, 120, 0)
	local b = C.solveLocked({ pos = POS + Vector3.new(0, 0, -3), heading = headingAt(0), dist = 12 })
	local start = st.pos
	local step = (b.Position - start).Magnitude
	local maxPast = 0
	for _ = 1, 240 do
		C.follow(st, b, 1 / 60, "C", 0)
		local past = (st.pos - start):Dot((b.Position - start).Unit) - step
		maxPast = math.max(maxPast, past)
	end
	assert(maxPast <= 0.04 * step, ("overshot by %.3f studs on a %.2f-stud step"):format(maxPast, step))
end)

--[[ THE 20 HZ HUNTER. Measured live on 7 Oct, 11 s of chase with no mouse
	input: the camera jolted 0.45-3 studs 46 times, every third frame. The
	server moves the hunter with PivotTo on an anchored rig, so on the client
	it arrives in network-rate steps (~20 Hz), and the camera distance is a
	function of the hunter distance. The spring should have absorbed it, but
	it ran in WORLD space: at 19 studs/s its steady lag (v * DAMP / ACCEL = 5
	studs) is past LAG_MAX, so the clamp held it rigid and every step went
	straight to the screen. The recording called it "stuttering ... like it's
	locking to something". ]]
local function chaseRun(opts)
	local dt = 1 / 60
	local pos, yaw = Vector3.new(0, 3, 0), 0
	local hunterTrue = pos + Vector3.new(0, 0, 16)
	local hunterSeen = hunterTrue
	local st, dir, steerRate = {}, {}, 0
	local last, worst, sxs = nil, 0, {}
	for i = 0, opts.frames do
		local t = i * dt
		local dyaw = (opts.turn and t >= 1 and t < 2) and math.rad(opts.turn) * dt or 0
		yaw += dyaw
		steerRate += ((dyaw / dt) - steerRate) * (1 - math.exp(-dt / 0.12))
		local h = C.headingOfYaw(yaw)
		pos += h * 19 * dt
		-- the hunter breathes 15..18 studs behind, and the client only sees it every 3rd frame
		local back = 16.5 + 1.5 * math.sin(t * 2.1)
		hunterTrue = pos - h * back
		if i % 3 == 0 then hunterSeen = hunterTrue end
		local dist = (pos - hunterSeen).Magnitude
		C.direct(dir, { t = t, dt = dt, dist = dist, speed = 19, carrySpeed = 16, pos = pos, travel = h,
			heading = h, hunterPos = hunterSeen })
		if dir.snap then dir.snap = false st = {} last = nil end
		local target = C.solveLocked({ shot = "chase", pos = pos, heading = h, side = dir.side, dist = dist,
			hunterPos = hunterSeen, framing = dir.framing, speed = 19, carrySpeed = 16 })
		local frame = nil
		if not opts.world then frame = { anchor = pos, heading = h } end
		local cf = C.follow(st, target, dt, "C", steerRate, frame)
		local rel = cf.Position - pos
		if last and i > 90 then worst = math.max(worst, (rel - last).Magnitude) end
		last = rel
		if opts.turn and t >= 1 and t < 2 then
			local r = F.check(cf, 70, 16 / 9, { playerPos = pos, heading = h })
			table.insert(sxs, r.metrics.sx)
		end
	end
	return worst, sxs
end

test("a hunter that moves in 20 Hz steps does not shake the camera", function()
	-- the camera moving relative to the player, per frame, on a straight run
	local worst = chaseRun({ frames = 300 })
	assert(worst < 0.1, ("camera jolted %.2f studs in one frame"):format(worst))
	-- and the test can see the bug: the world-space spring fails it
	local before = chaseRun({ frames = 300, world = true })
	assert(before > 0.25, ("the old spring only jolted %.2f -- test is not sensitive"):format(before))
end)

test("a steady turn keeps the player where they were on screen", function()
	local _, sxs = chaseRun({ frames = 180, turn = 120 })
	local lo, hi = math.huge, -math.huge
	for _, v in ipairs(sxs) do lo, hi = math.min(lo, v), math.max(hi, v) end
	assert(#sxs > 30, "no turn frames sampled")
	assert(hi - lo < 0.02, ("the player slid %.3f of the screen width during a steady turn"):format(hi - lo))
end)

--[[ TWO JUMPS IN ONE BREATH. Measured live on 7 Oct: a shot cut at 5.08 s and
	a framing snap at 5.29 s -- the hunter crossed 20 studs a fifth of a second
	after the director had cut. Each is motivated alone; together they read as
	the camera stuttering. A snap is a cut to the eye, so it obeys the same
	hold: no framing switch within MIN_HOLD of a cut (unless the hunter is
	already close, URGENT), and a snap starts the hold for the next cut. ]]
test("a framing snap never lands right after a cut, and starts the hold itself", function()
	local D, L = C.DIR, C.LOCKED
	local dir = {}
	local dt = 1 / 60
	local lastJump, worst, pairs = nil, math.huge, 0
	local pos = Vector3.new(0, 3, 0)
	for i = 0, 60 * 90 do
		local t = i * dt
		local dist = 20.5 + 5 * math.sin(t * 0.9) + 2.2 * math.sin(t * 2.3 + 1)
		local cyc = t % 3.2
		local windup = dist < 17 and cyc > 2.4 and cyc < 2.8
		local lunging = dist < 17 and cyc >= 2.8 and cyc < 3.0
		local _, _, cut = C.direct(dir, { t = t, dt = dt, dist = dist, windup = windup, lunging = lunging,
			speed = 19, carrySpeed = 16, pos = pos, travel = Vector3.new(0, 0, -1), heading = Vector3.new(0, 0, -1),
			hunterPos = pos + Vector3.new(0, 0, dist) })
		local snap = dir.snap
		dir.snap = false
		if (cut and not windup) or (snap and dist >= L.URGENT) then
			if lastJump and t > D.ESTABLISH + 0.1 then
				local gap = t - lastJump
				worst = math.min(worst, gap)
				if gap < D.MIN_HOLD - 1e-6 then pairs += 1 end
			end
		end
		if cut or snap then lastJump = t end
	end
	assert(pairs == 0, ("%d jumps landed within MIN_HOLD of the last one (closest %.2f s)"):format(pairs, worst))
end)

return T
