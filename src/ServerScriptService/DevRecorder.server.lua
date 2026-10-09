--[[ DevRecorder -- one live chase run, recorded (Studio only, v4.6, 9 Oct 2026).

	A real server Script, not code pasted through the Studio MCP bridge: pasted code is
	resumed only about every 0.39 s, which made a 0.25 s sampler a 0.39 s one.

	START A RUN (Server datamodel):
	    game.ServerScriptService.DevRecorder:SetAttribute("Request", "genius/dodger/" .. os.clock())
	(An attribute, not BindableEvent:Fire from the bridge: a Fire runs the handler in the
	CALLER's thread, and bridge threads are resumed only every 0.39 s, so the 0.1 s sampler
	sampled at 0.39 s. An attribute change runs the handler in this script's own thread.)
	READ IT when ServerStorage.ChaseRun.Value is not "" (JSON).

	A run: restock your candidates (new spots), give DevRobot its profile, its goal
	(your doorstep) and its start (so it routes before pickup), run the
	"chase:<tier>" scenario, and sample every 0.1 s until the carry ends.

	Per sample: t, phase (chase/windup/lunge), hunter (studs), toDoor, speed.
	Summary: result (home/caught/timeout, or error + err when it never ran), tier, profile, pathLen (the candidate's
	walk home), time, lunges, closest, minToDoor, staff before/after. ]]
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local ev = Instance.new("BindableEvent")
ev.Name = "Run"
ev.Parent = script

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

local function run(tier, profile)
	local p = Players:GetPlayers()[1]
	local core = script.Parent:FindFirstChild("SiliconCore")
	local dev = core and core:FindFirstChild("SVDev")
	local box = ServerStorage:FindFirstChild("ChaseRun") or Instance.new("StringValue")
	box.Name = "ChaseRun"
	box.Parent = ServerStorage
	box.Value = ""
	if not (p and dev) then
		box.Value = HttpService:JSONEncode({ result = "error", err = "no player or SVDev" })
		return
	end
	local geo = dev:Invoke("scenario", p, "geo")
	local door = geo and geo.door
	p:SetAttribute("TestGoal", door)
	p:SetAttribute("RobotProfile", profile)
	dev:Invoke("scenario", p, "restock")
	task.wait(9) -- each spawn tries up to 12 pathfinding routes
	geo = dev:Invoke("scenario", p, "geo")
	local cand = geo and geo.candidates and geo.candidates[tier]
	if cand then p:SetAttribute("TestFrom", cand.pos + Vector3.new(0, 1, 3)) end
	task.wait(3) -- DevRobot computes its route now, before pickup
	local staff0 = dev:Invoke("state", p).staff
	local r = dev:Invoke("scenario", p, "chase:" .. tier)
	-- a refused scenario or no door is not a chase: grading it would call it "caught",
	-- and flat(nil) would kill this thread with ChaseRun stuck at ""
	if not (door and type(r) == "table" and r.ok) then
		p:SetAttribute("RobotProfile", nil)
		box.Value = HttpService:JSONEncode({ result = "error", tier = tier, profile = profile,
			err = not door and "geo returned no door" or ("chase scenario refused: " .. tostring(type(r) == "table" and r.err or r)) })
		return
	end
	local s0 = os.clock()
	local samples, lunges, closest, minDoor, lastPhase = {}, 0, math.huge, math.huge, "chase"
	local row = workspace.SiliconValley:FindFirstChild("TalentRow")
	while os.clock() - s0 < 90 do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if not p:GetAttribute("Carrying") and os.clock() - s0 > 0.3 then break end
		local hd, phase = nil, "chase"
		for _, d in (row and row:GetChildren() or {}) do
			if d.Name == "Headhunter" and d:IsA("Model") and root then
				hd = math.min(hd or 1e9, (flat(d:GetPivot().Position) - flat(root.Position)).Magnitude)
				if d:GetAttribute("Lunging") then phase = "lunge" elseif d:GetAttribute("Windup") and phase ~= "lunge" then phase = "windup" end
			end
		end
		if phase == "windup" and lastPhase ~= "windup" then lunges += 1 end
		lastPhase = phase
		local toDoor = root and (flat(root.Position) - flat(door)).Magnitude
		if hd then closest = math.min(closest, hd) end
		if toDoor then minDoor = math.min(minDoor, toDoor) end
		table.insert(samples, { t = math.floor((os.clock() - s0) * 100) / 100, phase = phase,
			hunter = hd and math.floor(hd * 10) / 10, toDoor = toDoor and math.floor(toDoor),
			speed = root and math.floor(flat(root.AssemblyLinearVelocity).Magnitude * 10) / 10 })
		task.wait(0.1)
	end
	local staff1 = dev:Invoke("state", p).staff
	local result = staff1 > staff0 and "home" or (minDoor <= 20 and "timeout" or "caught")
	p:SetAttribute("RobotProfile", nil)
	box.Value = HttpService:JSONEncode({
		result = result, tier = tier, profile = profile, scenarioOk = r.ok, scenarioErr = r.err,
		pathLen = r.pathLen and math.floor(r.pathLen), time = math.floor((os.clock() - s0) * 10) / 10,
		lunges = lunges, closest = closest < math.huge and math.floor(closest * 10) / 10 or nil,
		minToDoor = minDoor < math.huge and math.floor(minDoor) or nil, staff = { staff0, staff1 },
		samples = samples,
	})
end

ev.Event:Connect(run)
script:GetAttributeChangedSignal("Request"):Connect(function()
	local tier, profile = tostring(script:GetAttribute("Request") or ""):match("^(%w+)/(%w+)")
	if tier then task.spawn(run, tier, profile) end
end)
