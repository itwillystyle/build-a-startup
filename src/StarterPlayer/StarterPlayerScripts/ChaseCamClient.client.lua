--[[
	ChaseCamClient -- the chase, staged. Two versions, switchable live.

	WHY THIS EXISTS. The chase already is a predator simulation and the player
	cannot see any of it. Measured in a running game: the hunter sits at
	dot(forward) = -1.00, i.e. exactly behind you, and nothing in the project
	touched the camera during a carry. So a mechanic with a 0.5-second crouch
	tell and a 1.4x lunge reached the player as a slightly faster heartbeat.

	Everything needed to stage it is already on the wire. The server writes
	`Windup` and `Lunging` onto the hunter rig every frame, and `ChaseDist` onto
	the player. This file only reads them. No server change, nothing new to
	persist, and deleting this file returns the game to exactly what it was.

	THE TWO VERSIONS

	  "A"  FRAMING ONLY. Never takes control. The camera drops, pulls back,
	       widens with speed, and yaws off the travel line so the hunter rides
	       the edge of frame instead of living behind your head.

	  "B"  A, PLUS SCRIPTED BEATS. A 0.8s entry whip when you pick someone up,
	       a tighter beat on the crouch tell, a shake on the lunge, and an
	       ending that frames whoever won. Control returns the instant the
	       entry beat ends.

	  "off"  stock camera, for an honest A/B against what shipped.

	SWITCH IT LIVE (Studio command bar, client):
	    game:GetService("Players").LocalPlayer:SetAttribute("ChaseCam", "B")

	SAFETY. It stands down whenever something else owns the camera: a real
	cutscene (Cine.busy), or a CameraType that is not Custom when a carry
	starts. It captures the previous CameraType only when that type is Custom,
	because the Rip cutscene once captured Scriptable and handed the camera
	back to nobody, freezing it for the rest of the session.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local okCine, Cine = pcall(function()
	return require(ReplicatedStorage:WaitForChild("Cine", 10))
end)
if not okCine then Cine = nil end

-- ---------------------------------------------------------------- tuning
--[[ Every number here is meant to be changed while we look at it. They are
	grouped by the question they answer rather than by type. ]]
local T = {
	-- where the camera sits, relative to the player, at rest and at full fear
	DIST_FAR = 15,        -- studs behind when the hunter is nowhere near
	DIST_NEAR = 11,       -- ... and when it is breathing down your neck
	HEIGHT_FAR = 6.5,     -- studs above
	HEIGHT_NEAR = 4.0,    -- lower as it closes: more ground rushing past
	-- how far the camera turns off your travel line so the hunter is visible
	YAW_FAR = 8,          -- degrees, when it is far behind
	YAW_NEAR = 34,        -- degrees, when it is on you
	-- the lens
	FOV_BASE = 70,
	FOV_SPEED = 14,       -- added at full carry speed
	FOV_WINDUP = -8,      -- the crouch tell punches IN (B only)
	-- how fast the camera reacts. Lower is snappier.
	SMOOTH = 0.12,
	-- distances that define "far" and "near" for all of the above
	FEAR_FAR = 26,
	FEAR_NEAR = 6,
	-- beats (B only)
	ENTRY = 0.8,
	EXIT = 0.6,
	SHAKE = 0.55,         -- studs of shake at a full lunge
}

-- ---------------------------------------------------------------- state
local camera = workspace.CurrentCamera
local mode = "off"
local active = false          -- we currently own the camera
local prevType, prevFov
local smoothed                -- the eased camera CFrame
local shakeUntil, shakeAmt = 0, 0
local entryUntil = 0
local hidden = {}             -- ScreenGuis we switched off, to restore exactly

-- the peacetime HUD has no business being up during this. Named rather than
-- blanket-hidden so a gui we did not think about cannot vanish silently.
local HUSH = { "Rail", "Guide", "ProductBar", "RightColumn", "WorkBar", "Quest" }

local bars                    -- letterbox
local label                   -- the rival's name

local function ensureStage()
	if bars then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "ChaseStage"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 9
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local function bar(y, anchor)
		local f = Instance.new("Frame")
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0, anchor)
		f.Position = UDim2.new(0, 0, y, 0)
		f.Size = UDim2.new(1, 0, 0, 0)
		f.Parent = gui
		return f
	end
	bars = { gui = gui, top = bar(0, 0), bottom = bar(1, 1) }
	label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4
	label.TextSize = 30
	label.Text = ""
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0.12, 0)
	label.Size = UDim2.new(1, -40, 0, 36)
	label.TextTransparency = 1
	label.Parent = gui
end

local function letterbox(on, seconds)
	ensureStage()
	bars.gui.Enabled = true
	local h = on and UDim2.new(1, 0, 0.11, 0) or UDim2.new(1, 0, 0, 0)
	local info = TweenInfo.new(seconds or 0.3, Enum.EasingStyle.Quad)
	TweenService:Create(bars.top, info, { Size = h }):Play()
	TweenService:Create(bars.bottom, info, { Size = h }):Play()
	if not on then
		task.delay((seconds or 0.3) + 0.05, function()
			if bars and not active then bars.gui.Enabled = false end
		end)
	end
end

local function slam(text)
	ensureStage()
	label.Text = text or ""
	label.TextTransparency = 1
	label.TextSize = 44
	TweenService:Create(label, TweenInfo.new(0.18), { TextTransparency = 0, TextSize = 30 }):Play()
	task.delay(1.6, function()
		if label then TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 }):Play() end
	end)
end

--[[ Hide the peacetime HUD, remembering exactly what we switched off so the
	restore cannot leave a player without their rail. ]]
local function hush(on)
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then return end
	if on then
		for _, name in ipairs(HUSH) do
			local g = pg:FindFirstChild(name)
			if g and g:IsA("ScreenGui") and g.Enabled then
				g.Enabled = false
				table.insert(hidden, g)
			end
		end
	else
		for _, g in ipairs(hidden) do
			if g and g.Parent then g.Enabled = true end
		end
		hidden = {}
	end
end

-- ---------------------------------------------------------------- the hunter
--[[ Same place ChaseFxClient looks: the TalentRow folder, models carrying
	`Chaser` and a `ChasingUserId` that matches us. Cached and refreshed on a
	timer rather than scanned every frame. ]]
local row, hunters, nextScan = nil, {}, 0

local function rescan()
	if not row then
		for _, d in ipairs(workspace:GetDescendants()) do
			if d.Name == "TalentRow" and (d:IsA("Folder") or d:IsA("Model")) then row = d break end
		end
	end
	hunters = {}
	if not row then return end
	for _, m in ipairs(row:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("Chaser")
			and m:GetAttribute("ChasingUserId") == player.UserId and m.PrimaryPart then
			table.insert(hunters, m)
		end
	end
end

local function nearestHunter(from)
	local best, bestD, wind, lunge
	for _, m in ipairs(hunters) do
		if m.Parent and m.PrimaryPart then
			local d = (m.PrimaryPart.Position - from).Magnitude
			if not bestD or d < bestD then best, bestD = m, d end
			wind = wind or m:GetAttribute("Windup") == true
			lunge = lunge or m:GetAttribute("Lunging") == true
		end
	end
	return best, bestD, wind, lunge
end

-- ---------------------------------------------------------------- lifecycle
local function takeCamera()
	if active then return true end
	--[[ Never capture a CameraType we do not own. The Rip cutscene captured
		Scriptable once and handed the camera back to nobody. ]]
	if camera.CameraType ~= Enum.CameraType.Custom then return false end
	if Cine and Cine.busy and Cine.busy() then return false end
	prevType, prevFov = camera.CameraType, camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	smoothed = camera.CFrame
	active = true
	hush(true)
	return true
end

local function release()
	if not active then return end
	active = false
	camera.CameraType = prevType or Enum.CameraType.Custom
	if prevFov then
		TweenService:Create(camera, TweenInfo.new(0.35), { FieldOfView = prevFov }):Play()
	end
	letterbox(false, 0.35)
	hush(false)
	shakeUntil = 0
end

-- ---------------------------------------------------------------- the frame
local function lerp(a, b, t) return a + (b - a) * t end

RunService.RenderStepped:Connect(function(dt)
	camera = workspace.CurrentCamera
	mode = tostring(player:GetAttribute("ChaseCam") or "off")
	local carrying = player:GetAttribute("Carrying") ~= nil

	if mode == "off" or not carrying then
		if active then release() end
		return
	end

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		if active then release() end
		return
	end

	-- something with more authority took the camera mid-chase: stand down
	if active and Cine and Cine.busy and Cine.busy() then release() return end
	if not active then
		if not takeCamera() then return end
		if mode == "B" then
			entryUntil = os.clock() + T.ENTRY
			letterbox(true, 0.25)
			local tier = tostring(player:GetAttribute("Carrying") or ""):upper()
			slam(tier ~= "" and (tier .. "  ·  GET THEM HOME") or "GET THEM HOME")
		end
	end

	local t = os.clock()
	if t > nextScan then nextScan = t + 0.4 rescan() end
	local hunter, dist, wind, lunge = nearestHunter(hrp.Position)

	-- 0 = safe, 1 = it is on you
	local fear = 0
	if dist then
		fear = math.clamp((T.FEAR_FAR - dist) / (T.FEAR_FAR - T.FEAR_NEAR), 0, 1)
	end

	-- the direction you are travelling: velocity when moving, facing when not
	local vel = hrp.AssemblyLinearVelocity
	local flat = Vector3.new(vel.X, 0, vel.Z)
	local speed = flat.Magnitude
	local travel = speed > 2 and flat.Unit or hrp.CFrame.LookVector
	travel = Vector3.new(travel.X, 0, travel.Z)
	travel = travel.Magnitude > 0.01 and travel.Unit or Vector3.new(0, 0, -1)

	--[[ THE WHOLE IDEA. The camera sits behind you on the travel line, then
		yaws toward the side the hunter is on. At full fear that is 34 degrees,
		which is enough to hold the hunter in frame without losing the road. ]]
	local yawDeg = lerp(T.YAW_FAR, T.YAW_NEAR, fear)
	local side = 1
	if hunter and hunter.PrimaryPart then
		local toH = hunter.PrimaryPart.Position - hrp.Position
		local right = Vector3.new(-travel.Z, 0, travel.X)
		side = (toH:Dot(right) >= 0) and 1 or -1
	end
	local back = CFrame.Angles(0, math.rad(yawDeg * side), 0) * (-travel)

	local distBack = lerp(T.DIST_FAR, T.DIST_NEAR, fear)
	local height = lerp(T.HEIGHT_FAR, T.HEIGHT_NEAR, fear)
	local want = hrp.Position + back * distBack + Vector3.new(0, height, 0)
	local look = hrp.Position + travel * 6 + Vector3.new(0, 1.5, 0)
	local target = CFrame.lookAt(want, look)

	-- the entry beat eases from wherever the camera was; after it, it tracks
	local k = 1 - math.exp(-dt / math.max(T.SMOOTH, 0.01))
	if mode == "B" and t < entryUntil then k = 1 - math.exp(-dt / 0.06) end
	smoothed = smoothed and smoothed:Lerp(target, k) or target

	-- the lens
	local carrySpeed = player:GetAttribute("CarrySpeed") or 16
	local fov = T.FOV_BASE + T.FOV_SPEED * math.clamp(speed / math.max(carrySpeed, 1), 0, 1)
	if mode == "B" and wind then fov += T.FOV_WINDUP end
	camera.FieldOfView = lerp(camera.FieldOfView, fov, 1 - math.exp(-dt / 0.18))

	-- the strike
	if mode == "B" and lunge then shakeUntil, shakeAmt = t + 0.25, T.SHAKE end
	local cf = smoothed
	if t < shakeUntil then
		local a = shakeAmt * ((shakeUntil - t) / 0.25)
		cf = cf * CFrame.new((math.random() - 0.5) * a, (math.random() - 0.5) * a, 0)
	end
	camera.CFrame = cf
end)

-- a respawn or a lost carry must never leave the camera ours
player.CharacterAdded:Connect(function() if active then release() end end)
player:GetAttributeChangedSignal("Carrying"):Connect(function()
	if player:GetAttribute("Carrying") == nil and active then
		if mode == "B" then letterbox(false, T.EXIT) end
		release()
	end
end)

--[[ A switch for QA. `_G` so the command bar can reach it without an attribute
	round trip; the attribute remains the real control. ]]
_G.SVChaseCam = function(m)
	player:SetAttribute("ChaseCam", m)
	return "ChaseCam = " .. tostring(m)
end
