--[[
	TrafficClient -- LocalScript in StarterPlayer -> StarterPlayerScripts.

	AMBIENT TRAFFIC, the Brookhaven / Ghost Drivers way: the server places each
	car once with attributes (LaneA, LaneB, LaneId, Speed, Phase, CrossAt) and
	never touches it again. Every client moves every car itself. Cars are
	anchored, no-collide, no-query: scenery that moves, never an obstacle.

	v1.7 -- cars drive like cars:
	  * each car keeps its own distance along the lane and INTEGRATES it per
	    frame (starting from the shared-clock formula, so a late joiner sees
	    roughly the same traffic everyone else does)
	  * FOLLOWING: a car eases off to keep >= GAP studs behind the car ahead in
	    the same lane, so nothing ever overlaps
	  * YIELDING: a cross-street car slows to a stop before its intersection
	    while a main-road car is inside the box, then pulls away again
	  * speed changes are eased (accel/brake limits), never stepped
	  * a quiet electric whir plays on a car the moment it passes the player
	    (Silicon Valley = EVs; Pro Sound Effects, licensed, one-shot, 3D)
]]

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local GAP = 16            -- studs bumper-to-bumper minimum
local ACCEL = 14          -- studs/s^2
local BRAKE = 30
local BOX = 34            -- half-size of the intersection box (main road is 30 wide + margin)
local STOP_AT = 30        -- cross car stops this far before the intersection centre
local WHIR_DIST = 24
local WHIRS = { "rbxassetid://9114240232", "rbxassetid://9114239617", "rbxassetid://9114240067" }

local cars = {}           -- model -> state
local lanes = {}          -- laneId -> { states }
local mains = {}          -- states of main-road cars (no CrossAt)

--[[ v9: RING LANES.

	The campus is a ring, so its roads are circles and a straight a->b lane
	cannot describe one. A car with a RingR attribute drives that circle
	instead: its distance `d` is arc length, its position comes off the angle
	d/R, and its heading is the tangent, recomputed each frame rather than
	cached. Everything else -- following, easing, the pass-by whir -- is shared
	with the straight lanes, because they all work on `d` along a length.

	A ring has no ends, so the end fade is skipped: it would pulse the cars
	transparent once a lap for no reason. ]]
local function track(model)
	if not model:IsA("Model") or cars[model] then return end
	local ringR = model:GetAttribute("RingR")
	local a, b = model:GetAttribute("LaneA"), model:GetAttribute("LaneB")
	local isRing = typeof(ringR) == "number" and ringR > 1
	local dir, len
	if isRing then
		len = 2 * math.pi * ringR
		dir = Vector3.new(0, 0, 1)                  -- replaced per frame
	else
		if typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" then return end
		dir = b - a
		len = dir.Magnitude
		if len < 1 then return end
		dir = dir.Unit
	end
	local speed = model:GetAttribute("Speed") or 40
	local phase = model:GetAttribute("Phase") or 0
	local t = workspace:GetServerTimeNow()
	local st = {
		model = model, a = a or Vector3.zero, dir = dir, len = len,
		ring = isRing and ringR or nil,
		spin = (model:GetAttribute("RingDir") == -1) and -1 or 1,
		vmax = speed, v = speed,
		d = (t * speed + phase) % len,
		laneId = model:GetAttribute("LaneId") or 0,
		crossAt = model:GetAttribute("CrossAt"),
		look = isRing and CFrame.new() or CFrame.lookAt(Vector3.zero, dir).Rotation,
		near = false,
		parts = {}, fade = 0,
	}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(st.parts, d) end
	end
	cars[model] = st
	lanes[st.laneId] = lanes[st.laneId] or {}
	table.insert(lanes[st.laneId], st)
	if not st.crossAt then table.insert(mains, st) end
end

local function untrack(model)
	local st = cars[model]
	if not st then return end
	cars[model] = nil
	local l = lanes[st.laneId]
	if l then for i, s in ipairs(l) do if s == st then table.remove(l, i) break end end end
	for i, s in ipairs(mains) do if s == st then table.remove(mains, i) break end end
end

for _, m in ipairs(CollectionService:GetTagged("TrafficCar")) do track(m) end
CollectionService:GetInstanceAddedSignal("TrafficCar"):Connect(track)
CollectionService:GetInstanceRemovedSignal("TrafficCar"):Connect(untrack)

local function posOf(st)
	if st.ring then
		local ang = st.spin * st.d / st.ring
		return Vector3.new(math.cos(ang) * st.ring, st.y or 1.4, math.sin(ang) * st.ring)
	end
	return st.a + st.dir * st.d
end

-- the heading of a ring car: the tangent at its current angle
local function ringLook(st)
	local ang = st.spin * st.d / st.ring
	local tangent = Vector3.new(-math.sin(ang) * st.spin, 0, math.cos(ang) * st.spin)
	return CFrame.lookAt(Vector3.zero, tangent).Rotation
end

-- distance to the car ahead in the same lane (wrapping), or math.huge
local function gapAhead(st)
	local best = math.huge
	for _, o in ipairs(lanes[st.laneId]) do
		if o ~= st then
			local g = (o.d - st.d) % st.len
			if g < best then best = g end
		end
	end
	return best
end

-- is a main-road car inside (or about to enter) the intersection box?
local function mainInBox(crossAt)
	for _, o in ipairs(mains) do
		local p = posOf(o)
		local dx = p.X - crossAt.X
		local toward = (o.dir.X > 0 and dx < 0) or (o.dir.X < 0 and dx > 0)
		if math.abs(dx) < BOX or (toward and math.abs(dx) < BOX + o.v * 1.2) then return true end
	end
	return false
end

local function whirAt(model)
	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not root then return end
	local s = Instance.new("Sound")
	s.SoundId = WHIRS[math.random(1, #WHIRS)]
	s.Volume = 0.35
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 8
	s.RollOffMaxDistance = 60
	s.PlaybackSpeed = 0.9 + math.random() * 0.25
	s.Parent = root
	s:Play()
	s.Ended:Once(function() s:Destroy() end)
end

RunService.RenderStepped:Connect(function(dt)
	dt = math.min(dt, 0.1)
	local char = Players.LocalPlayer.Character
	local me = char and char:FindFirstChild("HumanoidRootPart")
	for model, st in pairs(cars) do
		if not model.Parent then untrack(model) continue end
		local target = st.vmax

		-- follow the car ahead
		local g = gapAhead(st)
		if g < GAP then target = 0
		elseif g < GAP * 2.5 then target = math.min(target, st.vmax * (g - GAP) / (GAP * 1.5)) end

		-- yield before the intersection (cross lanes are centred on the main road)
		if st.crossAt then
			local toStop = (st.len / 2 - STOP_AT) - st.d        -- >0: stop line still ahead
			if toStop > 0 and toStop < 60 and mainInBox(st.crossAt) then
				target = math.min(target, st.vmax * math.clamp((toStop - 4) / 40, 0, 1))
			end
		end

		-- eased speed
		if target > st.v then st.v = math.min(target, st.v + ACCEL * dt)
		else st.v = math.max(target, st.v - BRAKE * dt) end
		st.d = (st.d + st.v * dt) % st.len
		local p = posOf(st)
		model:PivotTo(CFrame.new(p) * (st.ring and ringLook(st) or st.look))
		-- v4.0: fade in and out at the lane ends (the main road now ends at the
		-- downtown roundabout, in plain view) instead of popping
		-- a circle has no ends, so a ring car never fades
		local edge = st.ring and 1e9 or math.min(st.d, st.len - st.d)
		local fade = math.clamp((14 - edge) / 14, 0, 1)
		if math.abs(fade - st.fade) > 0.04 or (fade == 0 and st.fade ~= 0) or (fade == 1 and st.fade ~= 1) then
			st.fade = fade
			for _, part in ipairs(st.parts) do part.LocalTransparencyModifier = fade end
		end

		-- pass-by whir
		if me then
			local near = (p - me.Position).Magnitude < WHIR_DIST
			if near and not st.near and st.v > 8 then whirAt(model) end
			st.near = near
		end
	end
end)
