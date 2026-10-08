--[[ turn_probe -- what a steady mouse turn does to the frame.

	    lune run tools/turn_probe            -- 90 deg/s, hunter 14 studs behind
	    lune run tools/turn_probe 150 0      -- 150 deg/s, no hunter

	The 23:36 recording: "it's stuttering as I'm moving it ... like it's
	locking to something". This replays the REAL director and locked camera
	(direct + solveLocked + follow) at 60 fps while the player runs at chase
	speed and turns at a steady rate, with a hunter that runs straight at
	them. Every few frames it prints where the player sits on screen, how far
	the lens is from the player, and how far the camera moved that frame. A
	smooth turn should give smooth columns; a step is the stutter. ]]
require("../tests/offline/roblox_globals")
local C = require("../src/ReplicatedStorage/ChaseCam")
local F = require("../src/ReplicatedStorage/ChaseFrame")

local args = {}
for _, a in ipairs(require("@lune/process").args) do if a ~= "--" then table.insert(args, a) end end
local RATE = tonumber(args[1]) or 90     -- deg/s of mouse turn
local GAP = tonumber(args[2]) or 14      -- studs the hunter starts behind; 0 = none
local SPEED = 19                         -- studs/s, measured live carry speed
local HUNTER_SPEED = 18
local dt = 1 / 60

local pos = Vector3.new(0, 3, 0)
local yaw = 0
local hunter = GAP > 0 and pos + Vector3.new(0, 0, GAP) or nil
local st, dir = {}, {}
local steerRate = 0
local last
local worstStep, worstAt = 0, 0
print(("turn %d deg/s for 1.5 s at %d studs/s, hunter %s"):format(RATE, SPEED, GAP > 0 and (GAP .. " studs behind") or "none"))
print("   t   steer   sx    lensToPlayer  camMove/frame  framing")
for i = 0, 300 do
	local t = i * dt
	local turning = t >= 0.5 and t < 2.0
	local dyaw = turning and math.rad(RATE) * dt or 0
	yaw += dyaw
	steerRate += ((dyaw / dt) - steerRate) * (1 - math.exp(-dt / 0.12))
	local h = C.headingOfYaw(yaw)
	pos += h * SPEED * dt
	local dist
	if hunter then
		local to = Vector3.new(pos.X - hunter.X, 0, pos.Z - hunter.Z)
		hunter += to.Unit * HUNTER_SPEED * dt
		dist = (pos - hunter).Magnitude
	end
	C.direct(dir, { t = t, dt = dt, dist = dist, speed = SPEED, carrySpeed = 16, pos = pos, travel = h, heading = h, hunterPos = hunter })
	local reset = false
	if dir.snap then dir.snap = false st = {} reset = true end
	local target = C.solveLocked({ shot = "chase", pos = pos, heading = h, side = dir.side, dist = dist,
		hunterPos = hunter, framing = dir.framing, speed = SPEED, carrySpeed = 16 })
	local cf = C.follow(st, target, dt, "C", steerRate, { anchor = pos, heading = h })
	local rel = cf.Position - pos
	local step = (last and not reset) and (rel - last).Magnitude or 0   -- the camera moving relative to the player
	last = rel
	if i > 2 and step > worstStep then worstStep, worstAt = step, t end
	local r = F.check(cf, 70, 16 / 9, { playerPos = pos, heading = h, hunterPos = hunter })
	if i % 3 == 0 or step > 1 then
		print(("%5.2f  %s  %.3f   %6.2f        %5.2f        %s"):format(t, turning and "TURN " or "     ",
			r.metrics.sx or -1, (cf.Position - pos).Magnitude, step, tostring(dir.framing)))
	end
end
print(("worst single-frame camera move beyond the player's own: %.2f studs at t=%.2f"):format(worstStep, worstAt))
