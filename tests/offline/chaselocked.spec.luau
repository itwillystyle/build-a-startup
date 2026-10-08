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
		a named cut or snap. Player runs at 20, turns at 57 deg/s from 3-5 s. ]]
	local worst, worstAt, unexplained, detail = 0, "", 0, ""
	for _, turn in ipairs({ 0, 57.3, -57.3 }) do
		for _, aspect in ipairs(ASPECTS) do
			local pos, yaw = POS, 0
			local hunter = pos - C.headingOfYaw(yaw) * 24
			local st, dir, lastCam = {}, {}, nil
			for i = 0, 600 do
				local t = i / 60
				if t > 3 and t < 5 then yaw += math.rad(turn) / 60 end
				local h = C.headingOfYaw(yaw)
				pos += h * (20 / 60)
				local to = pos - hunter
				local sp = (to.Magnitude > 20) and 22.5 or 17
				if to.Magnitude > 0.1 then hunter += Vector3.new(to.X, 0, to.Z).Unit * (sp / 60) end
				local d = (pos - hunter).Magnitude
				local shot, _, cut = C.direct(dir, { t = t, dt = 1 / 60, dist = d, pos = pos, heading = h, hunterPos = hunter })
				local snap = dir.snap
				dir.snap = false
				if cut or snap then st = {} end
				local target, fov = C.solveLocked({ pos = pos, heading = h, side = dir.side, shot = shot, dist = d,
					hunterPos = hunter, framing = dir.framing, speed = 20, carrySpeed = 18 })
				local cf = C.follow(st, target, 1 / 60, "C", 0)
				if lastCam and (cf.Position - lastCam).Magnitude > 3 and not (cut or snap) then
					unexplained += 1
					detail = ("turn %.0f t %.2f d %.1f jump %.1f"):format(turn, t, d, (cf.Position - lastCam).Magnitude)
				end
				lastCam = cf.Position
				local r = F.check(cf, fov, aspect, { playerPos = pos, heading = h, hunterPos = hunter })
				local hh = r.metrics.hunterOnScreen and r.metrics.hunterH or 0
				if hh > worst then worst, worstAt = hh, ("turn %.0f t %.2f d %.1f"):format(turn, t, d) end
			end
		end
	end
	assert(unexplained == 0, ("%d camera jumps over 3 studs with no cut or snap behind them, e.g. %s"):format(unexplained, detail))
	assert(worst <= 0.30, ("the hunter reached %.2f of the frame at %s"):format(worst, worstAt))
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
	assert(dir.framing == false and dir.snap == true, "past FRAME_OUT it must release, with a snap")
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

return T
