--[[ DevRobot -- a scripted player for live chase runs (Studio only, v4.6, 9 Oct 2026).

	WHY A REAL LOCALSCRIPT. The first version was pasted through the Studio MCP bridge,
	and code run that way is only resumed about every 0.39 s (a 0.1 s wait took 0.39 s,
	measured). The robot reacted to a pickup 1.5 s late and to a crouch far too late to
	dodge. A LocalScript runs every frame, like a player's hands.

	Inert unless Studio and a test run: it does nothing until the player has a
	RobotProfile attribute (set by DevRecorder on the server). Then, the instant the
	player starts carrying a hire, it rides home to TestGoal (your doorstep) along a
	PathfindingService route computed BEFORE pickup from TestFrom.

	Play styles (the simulator's names, tests/offline/chase_model.luau):
	  straight  follow the route, never react               (the W-holder)
	  dodger    on every crouch (a hunter's Windup), turn hard 55 deg for 0.6 s
	  spammer   follow the route, press BOOST whenever it is ready
	  idle      stand still for the first 3 s, then go     (freezing) ]]
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local p = Players.LocalPlayer

local DODGE = math.rad(55)
local remotes = ReplicatedStorage:WaitForChild("SVRemotes")
local boost = remotes:WaitForChild("CarryBoost", 30)
local row = workspace:WaitForChild("SiliconValley"):WaitForChild("TalentRow")

local function windupNow()
	for _, d in row:GetChildren() do
		if d.Name == "Headhunter" and d:IsA("Model") and d:GetAttribute("Windup") == true then return d end
	end
	return nil
end

local function route(from, to)
	local path = PathfindingService:CreatePath({ AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 6 })
	local ok = pcall(function() path:ComputeAsync(from, to) end)
	if ok and path.Status == Enum.PathStatus.Success then
		local pts = {}
		for _, w in path:GetWaypoints() do table.insert(pts, w.Position) end
		return pts
	end
	return { to }
end

local pre -- { from, pts }
p:GetAttributeChangedSignal("TestFrom"):Connect(function()
	local from, goal = p:GetAttribute("TestFrom"), p:GetAttribute("TestGoal")
	if from and goal then pre = { from = from, pts = route(from, goal) } end
end)

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

local function runOnce()
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local goal = p:GetAttribute("TestGoal")
	local profile = p:GetAttribute("RobotProfile")
	if not (hum and root and goal and profile) then return end
	local t0 = os.clock()
	if profile == "idle" then
		while p:GetAttribute("Carrying") and os.clock() - t0 < 3 do RunService.Heartbeat:Wait() end
	end
	local pts
	if pre and (flat(pre.from) - flat(root.Position)).Magnitude < 15 then
		pts = pre.pts
	else
		task.spawn(function() pts = route(root.Position, goal) end)
		while not pts and p:GetAttribute("Carrying") do
			hum:MoveTo(goal)
			RunService.Heartbeat:Wait()
		end
		pts = pts or { goal }
	end
	local len = 0
	for k = 2, #pts do len += (pts[k] - pts[k - 1]).Magnitude end
	print(("[robot] %s: route %d points, %.0f studs, reacted in %.2f s"):format(profile, #pts, len, os.clock() - t0))
	local i, lastWind, dodgeUntil, sign = 1, nil, 0, 1
	while p:GetAttribute("Carrying") and i <= #pts do
		local d = flat(pts[i]) - flat(root.Position)
		if d.Magnitude < 4 then
			i += 1
		else
			local dir = d.Unit
			if profile == "dodger" then
				local w = windupNow()
				if w and w ~= lastWind then
					lastWind, dodgeUntil, sign = w, os.clock() + 0.6, (math.random() < 0.5) and -1 or 1
				elseif not w then
					lastWind = nil
				end
				if os.clock() < dodgeUntil then
					local c, s = math.cos(DODGE * sign), math.sin(DODGE * sign)
					dir = Vector3.new(dir.X * c - dir.Z * s, 0, dir.X * s + dir.Z * c)
				end
			end
			if profile == "spammer" and boost then boost:FireServer() end
			-- MoveTo, not Move: the PlayerModule calls Move every frame with your (empty) input
			hum:MoveTo(root.Position + dir * 12)
		end
		RunService.Heartbeat:Wait()
	end
	print(("[robot] %s: stopped at waypoint %d/%d, %.0f studs from home"):format(profile, i, #pts, (flat(goal) - flat(root.Position)).Magnitude))
	hum:MoveTo(root.Position)
end

local busy = false
p:GetAttributeChangedSignal("Carrying"):Connect(function()
	if busy or not p:GetAttribute("Carrying") or not p:GetAttribute("RobotProfile") then return end
	busy = true
	local ok, err = pcall(runOnce)
	if not ok then warn("[robot] " .. tostring(err)) end
	busy = false
end)
