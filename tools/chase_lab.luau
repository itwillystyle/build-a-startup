--[[
	chase_lab -- look at the chase camera in EDIT, with nothing else running.

	WHY. The camera can only be judged by looking at it, and in Play that drags
	in four systems that each ended a test chase before it could be judged: the
	candidate stock, the offer timer (14 + distance x 0.11 seconds), the
	delivery radius, and the hunter's own catch. None of them are the camera.

	This builds a runner, a hunter and a road in the Edit viewport, and drives
	workspace.CurrentCamera through ReplicatedStorage.ChaseCam -- the SAME
	module the live LocalScript uses. Tuning here is tuning the game.

	RUN IT: paste this whole file into the Studio command bar (Edit mode).

	THEN STEER IT, one line at a time, while watching:

	    local L = workspace.ChaseLab
	    L:SetAttribute("Mode", "B")      -- "A" framing only | "B" beats | "off"
	    L:SetAttribute("Dist", 7)        -- studs to the hunter: 6 = on you, 26 = far
	    L:SetAttribute("Windup", true)   -- hold the crouch tell on screen
	    L:SetAttribute("Speed", 20)      -- how fast the runner is going
	    L:SetAttribute("Turning", true)  -- sweep the road, so the yaw is visible

	TUNE IT live (the module is shared, so these are the real numbers):

	    local C = require(game.ReplicatedStorage.ChaseCam)
	    C.T.YAW_NEAR = 44
	    C.T.HEIGHT_NEAR = 3

	STOP IT and give the camera back:

	    workspace.ChaseLab:SetAttribute("Run", false)
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Load the module FRESH rather than require()ing it.

	Roblox caches a require per ModuleScript instance for the life of the
	session, and Rojo updates that instance's Source in place -- so after an
	edit, require() hands back the OLD table and the lab silently tunes code
	that is no longer the code. That cost one confusing round here: a geometry
	fix measured as having no effect because the lab was still running the
	previous solve().

	So: pull the source over localhost (same path the install pipe uses) and
	compile it. Falls back to require when no server is up, which is correct
	for a plain look-at-it run. ]]
local ChaseCam
do
	local ok, src = pcall(function()
		return game:GetService("HttpService"):GetAsync("http://localhost:8731/src/ReplicatedStorage/ChaseCam.lua")
	end)
	if ok and src then
		local fn = loadstring(src)
		if fn then ChaseCam = fn() end
	end
	if not ChaseCam then
		ChaseCam = require(ReplicatedStorage:WaitForChild("ChaseCam"))
		warn("[chase lab] no localhost server: using the cached module, edits may not show")
	end
end

-- ---------------------------------------------------------------- the stage
local old = workspace:FindFirstChild("ChaseLab")
if old then old:Destroy() end

local lab = Instance.new("Folder")
lab.Name = "ChaseLab"
lab.Parent = workspace
lab:SetAttribute("Mode", "A")
lab:SetAttribute("Dist", 7)
lab:SetAttribute("Windup", false)
lab:SetAttribute("Speed", 20)
lab:SetAttribute("Turning", true)
lab:SetAttribute("Bend", 0.030)
lab:SetAttribute("Run", true)

local function block(parent, size, colour, name)
	local b = Instance.new("Part")
	b.Name = name
	b.Size = size
	b.Color = colour
	b.Anchored = true
	b.CanCollide = false
	b.Material = Enum.Material.SmoothPlastic
	b.Parent = parent
	return b
end

--[[ A figure, not a cube: the framing question is "can I read a person at the
	edge of frame", and a cube answers a different question. ]]
local function figure(name, shirt, trousers)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = lab
	local torso = block(m, Vector3.new(2, 2.6, 1.1), shirt, "Torso")
	block(m, Vector3.new(1.2, 1.2, 1.2), Color3.fromRGB(226, 182, 150), "Head").Shape = Enum.PartType.Ball
	block(m, Vector3.new(0.6, 2.2, 0.6), shirt, "ArmL")
	block(m, Vector3.new(0.6, 2.2, 0.6), shirt, "ArmR")
	block(m, Vector3.new(0.8, 2.4, 0.8), trousers, "LegL")
	block(m, Vector3.new(0.8, 2.4, 0.8), trousers, "LegR")
	m.PrimaryPart = torso
	return m
end

local function poseFigure(m, cf, crouch)
	local drop = crouch and -0.45 or 0
	m.Torso.CFrame = cf * CFrame.new(0, 1.4 + drop, 0)
	m.Head.CFrame = cf * CFrame.new(0, 3.3 + drop * 1.4, 0)
	m.ArmL.CFrame = cf * CFrame.new(-1.3, 1.4 + drop, crouch and -0.5 or 0)
	m.ArmR.CFrame = cf * CFrame.new(1.3, 1.4 + drop, crouch and -0.5 or 0)
	m.LegL.CFrame = cf * CFrame.new(-0.5, -0.4 + drop, 0)
	m.LegR.CFrame = cf * CFrame.new(0.5, -0.4 + drop, 0)
end

local runner = figure("Runner", Color3.fromRGB(70, 150, 230), Color3.fromRGB(40, 44, 54))
local hunter = figure("Hunter", Color3.fromRGB(200, 45, 45), Color3.fromRGB(30, 32, 40))

-- a strip of road under them, so speed and yaw are readable against something
local road = Instance.new("Folder")
road.Name = "Road"
road.Parent = lab
local CENTRE = Vector3.new(120, 0.5, 168)
for i = -20, 20 do
	local slab = block(road, Vector3.new(44, 1, 40), Color3.fromRGB(86, 84, 82), "Slab")
	slab.CFrame = CFrame.new(CENTRE + Vector3.new(0, 0, i * 40))
	local lineA = block(road, Vector3.new(1.2, 0.2, 16), Color3.fromRGB(230, 220, 160), "Line")
	lineA.CFrame = CFrame.new(CENTRE + Vector3.new(0, 0.6, i * 40))
end

-- ---------------------------------------------------------------- the loop
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable

local smoothed = cam.CFrame
local follow = {}          -- mode C carries its own position and velocity
local travelled = 0
local shakeUntil, lastWind = 0, false

if _G.SVChaseLab then pcall(function() _G.SVChaseLab:Disconnect() end) end
_G.SVChaseLab = RunService.RenderStepped:Connect(function(dt)
	if not lab.Parent or lab:GetAttribute("Run") == false then
		if _G.SVChaseLab then _G.SVChaseLab:Disconnect() _G.SVChaseLab = nil end
		workspace.CurrentCamera.CameraType = Enum.CameraType.Fixed
		return
	end

	local mode = tostring(lab:GetAttribute("Mode") or "A")
	local dist = tonumber(lab:GetAttribute("Dist")) or 7
	local wind = lab:GetAttribute("Windup") == true
	local speed = tonumber(lab:GetAttribute("Speed")) or 20
	local turning = lab:GetAttribute("Turning") == true

	-- the runner drives down the road, sweeping if asked, so the yaw is visible
	travelled += speed * dt
	--[[ A real corner, not a gentle weave: the swing only shows when the mark
		changes direction faster than the camera can follow it. ]]
	local bend = tonumber(lab:GetAttribute("Bend")) or 0.030
	local sway = turning and math.sin(travelled * bend) * 1.15 or 0
	local travel = Vector3.new(math.sin(sway), 0, -math.cos(sway)).Unit
	local pos = CENTRE + Vector3.new(math.sin(travelled * bend) * 110, 3.4, -((travelled % 1400) - 700))

	poseFigure(runner, CFrame.lookAt(pos, pos + travel), false)
	local hpos = pos - travel * dist
	poseFigure(hunter, CFrame.lookAt(hpos, pos), wind)

	if mode == "off" then
		-- stock-ish: straight behind, no yaw, so the A/B is honest
		local at = pos - travel * 14 + Vector3.new(0, 6, 0)
		smoothed = smoothed:Lerp(CFrame.lookAt(at, pos + travel * 6), 1 - math.exp(-dt / 0.12))
		cam.FieldOfView = 70
	else
		local target, fov = ChaseCam.solve({
			pos = pos, travel = travel, hunterPos = hpos, dist = dist,
			speed = speed, carrySpeed = 20, mode = mode, windup = wind,
		})
		if mode == "C" then
			-- the camera has mass in C: it lags, overshoots and banks
			smoothed = ChaseCam.follow(follow, target, dt, mode)
		else
			smoothed = smoothed:Lerp(target, 1 - math.exp(-dt / math.max(ChaseCam.T.SMOOTH, 0.01)))
		end
		cam.FieldOfView = ChaseCam.lerp(cam.FieldOfView, fov, 1 - math.exp(-dt / 0.18))
	end

	-- mode B shakes when the crouch ends, which is when the lunge lands
	if mode == "B" then
		if lastWind and not wind then shakeUntil = os.clock() + 0.25 end
		lastWind = wind
	end
	local cf = smoothed
	if os.clock() < shakeUntil then
		local a = ChaseCam.T.SHAKE * ((shakeUntil - os.clock()) / 0.25)
		cf = cf * CFrame.new((math.random() - 0.5) * a, (math.random() - 0.5) * a, 0)
	end

	cam.CFrame = cf
	cam.Focus = cf * CFrame.new(0, 0, -20)   -- Edit snaps the camera back without this
end)

return ("chase lab up. workspace.ChaseLab attributes: Mode/Dist/Windup/Speed/Turning/Run")
