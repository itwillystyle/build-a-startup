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
--[[ The framing lives in ReplicatedStorage.ChaseCam so the Edit-mode lab
	(tools/chase_lab.luau) can drive THE SAME maths without Play. Tune there,
	not here; this file only owns the beats (letterbox, slam, shake, hush). ]]
local ChaseCam = require(ReplicatedStorage:WaitForChild("ChaseCam"))
local T = ChaseCam.T

local BEATS = {
	ENTRY = 0.8,
	EXIT = 0.6,
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
--[[ EVERYTHING GOES except the chase itself.

	The recording settled this: mid-chase the screen still carried WRITE CODE,
	the car dashboard, the item slots and the cash line, none of which you can
	act on while something is running you down. A chase is the one moment the
	game asks for undivided attention, so it gets the whole screen.

	KEEP is the exception list, and it has one entry on purpose: ChaseFx draws
	the distance to the hunter and the "BOOST now" prompt, and boosting is a
	mechanic -- hiding it would remove the only thing you can DO about the
	chase. Everything else is restored exactly as it was on the way out. ]]
local KEEP = { ChaseFx = true, ChaseStage = true }

local bars                    -- letterbox
local label                   -- the rival's name
local cause                   -- QA: why the camera just cut

--[[ THE DIRECTOR lives in ReplicatedStorage.ChaseCam (ChaseCam.direct) --
	pure, so tests/offline/chasecam.spec.luau can drive a scripted chase and
	assert the cut sequence. This file only carries its state between frames
	and performs the cut.

	A cut SNAPS: the follower's position, its velocity and the eased CFrame are
	thrown away and rebuilt at the new set-up, because that is what a cut is.
	Gliding between set-ups is what makes a game camera read as a camera being
	moved rather than as an edit.

	Every cut is logged with the sentence it is making, so the edit can be
	audited after a run instead of taken on trust:

	    _G.SVChaseCuts()                                -- the log
	    player:SetAttribute("ChaseCamDebug", true)      -- draw the cause on screen
]]
local dir = {}                -- the director's own carried state
local shot = "establish"
local follow = {}             -- mode C's position and velocity
local cutLog = {}

local function note(shotName, why, t)
	table.insert(cutLog, { t = t, shot = shotName, cause = why })
	if #cutLog > 60 then table.remove(cutLog, 1) end
end

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
	--[[ QA only, off unless ChaseCamDebug is set: the sentence the current
		cut is making. Reading it back during a chase is the only way to tell
		a motivated edit from one that merely looks busy. ]]
	cause = label:Clone()
	cause.TextSize = 16
	cause.Font = Enum.Font.Gotham
	cause.Position = UDim2.new(0.5, 0, 0.88, 0)
	cause.TextTransparency = 1
	cause.Parent = gui
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
		for _, g in ipairs(pg:GetChildren()) do
			if g:IsA("ScreenGui") and g.Enabled and not KEEP[g.Name] then
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

-- ---------------------------------------------------------------- home
--[[ The delivery point, read the same way IntroClient and HomeClient read it:
	the player's `Plot` index, then that plot folder's `Pivot` attribute.
	Cached, because the plot does not move. ]]
local homeCF
local function homePos()
	if homeCF then return homeCF.Position end
	local idx = player:GetAttribute("Plot")
	local sv = workspace:FindFirstChild("SiliconValley")
	local pf = idx and sv and sv:FindFirstChild("Plots") and sv.Plots:FindFirstChild("Plot" .. idx)
	local pivot = pf and pf:GetAttribute("Pivot")
	if typeof(pivot) == "CFrame" then
		homeCF = pivot
		return homeCF.Position
	end
	return nil
end
player:GetAttributeChangedSignal("Plot"):Connect(function() homeCF = nil end)

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
	--[[ Claim the lens. ChaseFxClient punches the FOV to 62 and back to 70 on
		every lunge with its own tweens, and this file lerps the FOV toward its
		own value every frame -- two owners of one property, fighting for it
		continuously. Whoever wrote last won, which is a flicker by
		construction. The attribute is how the other one knows to stand down. ]]
	player:SetAttribute("ChaseCamOwns", true)
	smoothed = camera.CFrame
	active = true
	hush(true)
	return true
end

local function release()
	if not active then return end
	active = false
	player:SetAttribute("ChaseCamOwns", nil)
	camera.CameraType = prevType or Enum.CameraType.Custom
	if prevFov then
		TweenService:Create(camera, TweenInfo.new(0.35), { FieldOfView = prevFov }):Play()
	end
	letterbox(false, 0.35)
	hush(false)
	shakeUntil = 0
end

-- ---------------------------------------------------------------- the frame
RunService.RenderStepped:Connect(function(dt)
	camera = workspace.CurrentCamera
	--[[ C by default: a chase with the stock camera is the thing we are fixing.
		Setting the attribute to "A", "B" or "off" still overrides, which is
		how the comparison is run. ]]
	mode = tostring(player:GetAttribute("ChaseCam") or "C")
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
		dir = {}
		shot = "establish"
		follow = {}
		cutLog = {}
		if mode == "B" then
			entryUntil = os.clock() + BEATS.ENTRY
			letterbox(true, 0.25)
			local tier = tostring(player:GetAttribute("Carrying") or ""):upper()
			slam(tier ~= "" and (tier .. "  ·  GET THEM HOME") or "GET THEM HOME")
		end
	end

	local t = os.clock()
	if t > nextScan then nextScan = t + 0.4 rescan() end
	local hunter, dist, wind, lunge = nearestHunter(hrp.Position)

	-- the direction you are travelling: velocity when moving, facing when not
	local vel = hrp.AssemblyLinearVelocity
	local flat = Vector3.new(vel.X, 0, vel.Z)
	local speed = flat.Magnitude
	local travel = speed > 2 and flat or hrp.CFrame.LookVector

	--[[ How far is the door? The second of the chase's two numbers, and the
		one nothing was reading. Client-side off the plot's own Pivot
		attribute (same lookup IntroClient and HomeClient use), so this stays
		a camera change with no server work behind it. ]]
	local homeDist
	local hd = homePos()
	if hd then
		homeDist = (Vector3.new(hd.X, 0, hd.Z) - Vector3.new(hrp.Position.X, 0, hrp.Position.Z)).Magnitude
	end

	local hunterPos = hunter and hunter.PrimaryPart and hunter.PrimaryPart.Position or nil
	local newShot, why, didCut = ChaseCam.direct(dir, {
		t = t,
		dt = dt,
		dist = dist,
		windup = wind,
		lunging = lunge,
		homeDist = homeDist,
		speed = speed,
		carrySpeed = player:GetAttribute("CarrySpeed") or 16,
		--[[ The director keeps the shoulder, so it is decided once and held.
			Passing the geometry straight to solve every frame is what made the
			camera teleport between shoulders on sub-stud noise. ]]
		pos = hrp.Position,
		travel = travel,
		hunterPos = hunterPos,
	})
	if didCut then
		shot = newShot
		--[[ The cut itself. Dropping both the follower and the eased CFrame is
			what makes the next frame build the new angle from nothing. ]]
		follow = {}
		smoothed = nil
		note(shot, why, t)
	end
	if player:GetAttribute("ChaseCamDebug") and cause then
		ensureStage()
		bars.gui.Enabled = true
		cause.Text = shot:upper() .. "  ·  " .. tostring(why)
		cause.TextTransparency = 0.15
	elseif cause then
		cause.TextTransparency = 1
	end

	local target, fov = ChaseCam.solve({
		shot = shot,
		pos = hrp.Position,
		travel = travel,
		hunterPos = hunterPos,
		side = dir.side,
		dist = dist,
		speed = speed,
		carrySpeed = player:GetAttribute("CarrySpeed") or 16,
		mode = mode,
		windup = wind,
	})

	-- the entry beat eases from wherever the camera was; after it, it tracks
	if mode == "C" then
		-- C has mass: it lags, overshoots and banks. A cut reset `follow`, so
		-- the first frame after one builds the angle from scratch.
		smoothed = ChaseCam.follow(follow, target, dt, mode)
	else
		local k = 1 - math.exp(-dt / math.max(T.SMOOTH, 0.01))
		if mode == "B" and t < entryUntil then k = 1 - math.exp(-dt / 0.06) end
		smoothed = smoothed and smoothed:Lerp(target, k) or target
	end
	camera.FieldOfView = ChaseCam.lerp(camera.FieldOfView, fov, 1 - math.exp(-dt / 0.18))

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
		if mode == "B" then letterbox(false, BEATS.EXIT) end
		release()
	end
end)

--[[ A switch for QA. `_G` so the command bar can reach it without an attribute
	round trip; the attribute remains the real control. ]]
_G.SVChaseCam = function(m)
	player:SetAttribute("ChaseCam", m)
	return "ChaseCam = " .. tostring(m)
end

--[[ The edit, after the fact. Every line is a cut and the sentence it made; a
	cut with no sentence is the bug this whole design exists to prevent, so the
	log is the test for it. ]]
_G.SVChaseCuts = function()
	local out = {}
	local t0 = cutLog[1] and cutLog[1].t or 0
	for _, c in ipairs(cutLog) do
		table.insert(out, ("%5.2fs  %-9s  %s"):format(c.t - t0, c.shot, c.cause))
	end
	return #out > 0 and table.concat(out, "\n") or "no cuts yet"
end
