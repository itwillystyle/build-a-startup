--[[
	BobSceneClient -- LocalScript in StarterPlayer -> StarterPlayerScripts. P-5 (25 Oct 2026).

	Plays Bob's two cutscenes from BobScript's data, on this client only:
	  "intro"   a new save meets Bob (IntroClient hands off via PlayerGui.SVBobScene)
	  "payoff"  the server paid you at Bob's door (SVRemotes.BobPayoff, money ALREADY paid)

	Spec: docs/superpowers/specs/2026-10-25-bob-first-boss-investor-design.md (3a, 3e, 5, 5b-1).
	Rules it keeps:
	  * SKIP from frame 1. Only the SKIP button, or a TAP on touch, skips; keys and clicks
	    do not (5b-1). The player cannot move while it plays.
	  * ONE finish() for skip and the end: clones gone, camera Custom + the humanoid, controls
	    on, the HUD back, BobScenePlaying false. Never a stored Scriptable camera.
	  * Reduce Motion is read EVERY frame (BobScript drops the shake and the pushes).
	  * It never touches the server's world: door, tape and front wall are local overrides
	    that finish() puts back.
	Actors are clones (Bob and the investors from ReplicatedStorage.BobCast; you from your own
	HumanoidDescription, or a plain stand-in if that fails or takes over 2 s), posed by code
	through Motor6D.Transform: no animation uploads.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local UIKit = require(RS:WaitForChild("UIKit"))
local BobScript = require(RS:WaitForChild("BobScript"))
local BobFace = require(RS:WaitForChild("BobFace"))
local BobClips = require(RS:WaitForChild("BobClips"))
local Sfx = require(RS:WaitForChild("Sfx"))
local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local SOUND = { music = "bobMusic", laugh = "bobLaugh", boing = "boing", thud = "thud", money = "money", victory = "victory" }
local INK = UIKit.INK
local PAPER = UIKit.PAPER

local playing = false
local event = Instance.new("BindableEvent")
event.Name = "SVBobScene"
event.Parent = player:WaitForChild("PlayerGui")

-- ------------------------------------------------------------------ anchors
local function anchors()
	local sv = workspace:FindFirstChild("SiliconValley")
	local bc = sv and sv:FindFirstChild("BobCapital")
	if not bc then return nil end
	local a = { board = bc:GetAttribute("AnchorBoard"), door = bc:GetAttribute("AnchorDoor"), street = bc:GetAttribute("AnchorStreet") }
	local idx = player:GetAttribute("Plot")
	local pf = idx and sv:FindFirstChild("Plots") and sv.Plots:FindFirstChild("Plot" .. idx)
	local pivot = pf and pf:GetAttribute("Pivot")
	a.garage = pivot and pivot * CFrame.new(0, 0, -9) or a.street
	if not (a.board and a.door and a.street) then return nil end
	return a, bc
end

-- ------------------------------------------------------------------ actors
local function prep(model, name)
	model.Name = name
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = d.Name == "HumanoidRootPart"
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end
	-- review I-8: an Animator would overwrite the code-driven poses every frame
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Animator") or d:IsA("AnimationController") then d:Destroy() end
	end
	local motors = {}
	for _, m in ipairs(model:GetDescendants()) do
		if m:IsA("Motor6D") then
			motors[m.Name] = m
		elseif m:IsA("AnimationConstraint") then
			motors[m.Name] = m
			pcall(function() m.IsKinematic = true end)   -- a pose is a pose, not a spring
		end
	end
	return { model = model, root = model:FindFirstChild("HumanoidRootPart"), hum = hum, motors = motors,
		face = BobFace.attach(model), head = model:FindFirstChild("Head") }
end

local function heroModel()
	-- review I-2: Players:CreateHumanoidModelFromDescription is server-only; a client clones its
	-- own character instead (TalentRevealClient and RigPortrait do the same)
	local char = player.Character
	if char and char:FindFirstChildOfClass("Humanoid") then
		local was = char.Archivable
		char.Archivable = true
		local ok, m = pcall(function() return char:Clone() end)
		char.Archivable = was
		if ok and m and m:FindFirstChild("HumanoidRootPart") then
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("ForceField") or d:IsA("BillboardGui") then d:Destroy() end
			end
			return m
		end
	end
	-- the stand-in: a cast member in your-avatar colours (never a hang on a black screen)
	local cast = RS:FindFirstChild("BobCast")
	local m = cast and cast:FindFirstChild("Inv1") and cast.Inv1:Clone()
	if m then
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") then
				if p.Name:find("Torso") or p.Name:find("Arm") then p.Color = Color3.fromRGB(58, 134, 255)   -- world colour
				elseif p.Name:find("Leg") then p.Color = Color3.fromRGB(43, 58, 103)   -- world colour
				elseif p.Name == "Head" or p.Name:find("Hand") then p.Color = Color3.fromRGB(245, 205, 48) end   -- world colour
			elseif p:IsA("Shirt") or p:IsA("Pants") or p:IsA("Accessory") then p:Destroy() end
		end
	end
	return m
end

-- code-driven poses: Motor6D.Transform per joint (radians). t = scene time, for cycles
local R = math.rad
local function pose(a, name, t)
	local m = a.motors
	local function set(joint, cf) if m[joint] then m[joint].Transform = cf end end
	for _, j in pairs(m) do j.Transform = CFrame.new() end
	local breathe = math.sin(t * 2) * 0.03
	set("Waist", CFrame.Angles(breathe, 0, 0))
	if name == "gesture" then
		set("RightShoulder", CFrame.Angles(R(150), 0, R(-10)))
	elseif name == "laugh" then
		local b = math.abs(math.sin(t * 13))
		set("Waist", CFrame.Angles(R(-14 - 6 * b), 0, 0))
		set("Neck", CFrame.Angles(R(-18), 0, 0))
		set("RightShoulder", CFrame.Angles(R(40), 0, R(-25)))
		set("LeftShoulder", CFrame.Angles(R(40), 0, R(25)))
	elseif name == "walk" then
		local s = math.sin(t * 9)
		set("RightHip", CFrame.Angles(R(35 * s), 0, 0))
		set("LeftHip", CFrame.Angles(R(-35 * s), 0, 0))
		set("RightShoulder", CFrame.Angles(R(-25 * s), 0, 0))
		set("LeftShoulder", CFrame.Angles(R(25 * s), 0, 0))
		set("Neck", CFrame.Angles(R(10), 0, 0))
	elseif name == "kick" then
		set("RightHip", CFrame.Angles(R(80), 0, 0))
		set("Waist", CFrame.Angles(R(-15), 0, 0))
		set("RightShoulder", CFrame.Angles(0, 0, R(-40)))
		set("LeftShoulder", CFrame.Angles(0, 0, R(40)))
	elseif name == "fly" then
		set("RightShoulder", CFrame.Angles(0, 0, R(-110)))
		set("LeftShoulder", CFrame.Angles(0, 0, R(110)))
		set("RightHip", CFrame.Angles(0, 0, R(-30)))
		set("LeftHip", CFrame.Angles(0, 0, R(30)))
	elseif name == "lie" then
		set("RightShoulder", CFrame.Angles(0, 0, R(-60)))
		set("LeftShoulder", CFrame.Angles(0, 0, R(60)))
	elseif name == "sit" then
		set("RightHip", CFrame.Angles(R(80), 0, 0))
		set("LeftHip", CFrame.Angles(R(80), 0, 0))
	elseif name == "cheer" then
		local b = math.sin(t * 8) * 10
		set("RightShoulder", CFrame.Angles(R(170), 0, R(-15 + b)))
		set("LeftShoulder", CFrame.Angles(R(170), 0, R(15 - b)))
	elseif name == "holdChart" then
		set("RightShoulder", CFrame.Angles(R(165), 0, 0))
		set("LeftShoulder", CFrame.Angles(R(165), 0, 0))
	elseif name == "throw" then
		local s = math.sin(t * 16)
		set("RightShoulder", CFrame.Angles(R(110 + 50 * s), 0, 0))
		set("LeftShoulder", CFrame.Angles(R(110 - 50 * s), 0, 0))
	end
end

-- 25 Oct (Luke: "the emotive animations are very static"): the body moves by keyframed CLIPS
-- (BobClips, the shot list's clips as data). A clip starts when it first appears and runs on
-- through looks that share it (the vow is one 4.2 s take across "stand" and "gesture").
local function clipFor(scene, id, pose, t)
	if id == "hero" then
		if pose == "gesture" then return (scene == "intro" and t >= 12) and "hero_vow" or "hero_ask" end
		if pose == "stand" then
			if scene == "intro" and t >= 3.4 and t < 6.3 then return "hero_hurt" end
			if scene == "intro" and t >= 12 then return "hero_vow" end
			return "hero_idle"
		end
		return ({ fly = "hero_fly", lie = "hero_land", sit = "hero_situp", kick = "hero_kick", holdChart = "hero_ipad",
			cheer = "hero_cheer", walk = scene == "intro" and "hero_sadwalk" or "hero_strut" })[pose]
	elseif id == "bob" then
		if pose == "stand" then return scene == "payoff" and "bob_shock" or "bob_smug" end
		return ({ laugh = "bob_laugh", kick = "bob_kick", throw = "bob_throw", fly = "bob_fly", lie = "bob_dizzy", sit = "bob_dizzy" })[pose]
	end
	if pose == "laugh" then return "inv_laugh" end
	if scene == "payoff" and t >= 6.6 then return "inv_shock" end
	return "inv_idle"
end

-- feet at pos (anchor space); rot 0 faces the camera (+Z), 90 faces +X; roll spins round Z
-- live 25 Oct (Luke: "phasing through the floor"): an anchor's height is not the floor's (the
-- garage floor sits above the lot), so each actor stands on the real floor under its feet
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function floorAt(world, ignore)
	local skip = table.clone(ignore)
	for _ = 1, 5 do
		rayParams.FilterDescendantsInstances = skip
		local hit = workspace:Raycast(world + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0), rayParams)
		if not hit then return nil end
		if hit.Position.Y <= world.Y + 1.2 then return hit.Position.Y end
		table.insert(skip, hit.Instance)   -- a desk, a table, a chair: not the floor
	end
	return nil
end
-- the lowest visible point of the body, relative to the root (last frame's pose: a joint's
-- Transform reaches its parts on the next step, so this lags one frame)
local function lowestBelowRoot(a)
	local low
	for _, p in ipairs(a.model:GetDescendants()) do
		if p:IsA("BasePart") and p ~= a.root and p.Transparency < 1 then
			local cf, h = p.CFrame, p.Size / 2
			local y = cf.Y - math.abs(cf.RightVector.Y) * h.X - math.abs(cf.UpVector.Y) * h.Y - math.abs(cf.LookVector.Y) * h.Z
			if not low or y < low then low = y end
		end
	end
	return low and low - a.root.Position.Y
end

local function place(a, anchorCF, pos, rot, roll, ignore)
	if not (a.root and anchorCF) then return end
	-- live 25 Oct: lying flat or sitting, an actor floated at standing height (2.4 studs over the
	-- street). On the ground, the body's lowest point goes on the floor, whatever the pose; in the
	-- air (pos.Y > 0), it blends from standing height to half a torso as it rolls flat
	local stand = (a.hum and a.hum.HipHeight or 2) + a.root.Size.Y / 2
	local torso = a.model:FindFirstChild("UpperTorso") or a.model:FindFirstChild("Torso")
	local lie = torso and torso.Size.Z / 2 + 0.1 or 0.6
	local lift = stand + (lie - stand) * math.abs(math.sin(R(roll or 0)))
	if pos.Y <= 0.05 then
		local rel = lowestBelowRoot(a)
		if rel and rel < 0 then lift = -rel end
	end
	local at = (anchorCF * CFrame.new(pos.X, 0, pos.Z)).Position
	local floor = floorAt(at, ignore or {}) or at.Y
	local target = CFrame.new(at.X, floor + pos.Y + lift, at.Z) * anchorCF.Rotation * CFrame.Angles(0, 0, R(roll or 0))
		* CFrame.Angles(0, R(180 + (rot or 0)), 0)
	if (target.Position - a.root.Position).Magnitude > 5 then
		-- a jump (the first frame, a cut to another set): the limbs follow the root one physics step
		-- late, so for a frame the body was missing (live 25 Oct: Bob's tie floated alone). Move it all.
		a.model:PivotTo(target * a.root.CFrame:ToObjectSpace(a.model:GetPivot()))
	else
		a.root.CFrame = target
	end
end

local function setVisible(a, on)
	for _, d in ipairs(a.model:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = on and 0 or 1 end
	end
	for _, d in ipairs(a.model:GetDescendants()) do
		if d:IsA("SurfaceGui") or d:IsA("BillboardGui") then d.Enabled = on end
	end
end

-- ------------------------------------------------------------------ GUI
-- live 25 Oct (Luke's review of the recording): a 3D speech bubble above a head went off the top of
-- the frame in close shots ("He will rue the day.", "W-WHAT?!") and off the side on narrow screens.
-- A bubble is a 2D card now, placed every frame over the speaker's head and kept inside the frame:
-- with no room above the head it sits beside it, on the side with more room.
local function bubbleFor(a)
	local card = Instance.new("TextLabel")
	card.Name = "Bubble"
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.AutomaticSize = Enum.AutomaticSize.X
	card.Size = UDim2.fromOffset(0, 54)
	card.BackgroundColor3 = PAPER
	card.TextColor3 = INK
	card.Font = UIKit.HEAD
	card.TextSize = UIKit.TYPE.headline
	card.ZIndex = 6
	card.Visible = false
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 18), UDim.new(0, 18)
	pad.Parent = card
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, UIKit.RADIUS.lg); c.Parent = card
	local s = Instance.new("UIStroke"); s.Thickness = 3; s.Color = INK; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = card
	local sc = Instance.new("UIScale"); sc.Parent = card
	return { card = card, scale = sc, head = a.head }
end

-- where a bubble goes this frame, in viewport pixels (the scene's gui ignores the inset)
local SKIP_ZONE = 150   -- the SKIP button's corner, top right
local function bubbleAt(cam, head, w, h)
	local vp = cam.ViewportSize
	local top = cam:WorldToViewportPoint(head.Position + Vector3.new(0, head.Size.Y / 2 + 0.5, 0))
	local mid, onScreen = cam:WorldToViewportPoint(head.Position)
	if top.Z <= 0 or not onScreen and mid.Z <= 0 then return nil end
	local safeTop, safeBot, edge = vp.Y * 0.1 + 12, vp.Y * 0.9 - 12, 16
	local x, y = top.X, top.Y - 6
	if y - h < safeTop then
		-- no room above the head: beside it, on the side with more room
		local r = math.max(mid.Y - top.Y, 20)
		local side = mid.X < vp.X / 2 and 1 or -1
		x = mid.X + side * (r + 18 + w / 2)
		y = math.max(mid.Y + h / 2, safeTop + h)
	end
	local right = (y - h < SKIP_ZONE * 0.6) and vp.X - SKIP_ZONE or vp.X - edge
	x = math.clamp(x, edge + w / 2, math.max(edge + w / 2, right - w / 2))
	y = math.clamp(y, safeTop + h, safeBot)
	return x, y
end

local function worldText(parent, text, color)
	local p = Instance.new("Part")
	p.Name = "FxAnchor"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Transparency = true, false, false, false, 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Parent = parent
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(420, 110)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Adornee = p
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = UIKit.HEAD
	t.TextScaled = true
	t.Text = text
	t.TextColor3 = color or UIKit.GOLD
	t.Rotation = -6
	local st = Instance.new("UIStroke"); st.Thickness = 4; st.Color = INK; st.Parent = t
	local sc = Instance.new("UIScale"); sc.Parent = t
	t.Parent = bb
	bb.Parent = p
	return { part = p, gui = bb, scale = sc }
end

-- ------------------------------------------------------------------ one scene
local function play(name, info)
	if playing then return false end
	player:SetAttribute("BobSceneState", "loading")
	local A, bc = anchors()
	-- review I-3: build every actor BEFORE the scene takes the screen, so there is never a moment
	-- with the HUD gone and no SKIP, and a missing cast fails before anything has changed
	local cast = A and RS:WaitForChild("BobCast", 10)
	if not (A and cast) then
		warn("[Bob] no Bob Capital or BobCast in the world: scene skipped")
		player:SetAttribute("BobSceneState", "failed")
		return false
	end
	playing = true
	-- live 25 Oct: on a fresh join the AI meshes were not loaded yet, so for the first frames only Bob's
	-- tie and toothpick showed. Load the cast while still "loading" (at most 4 s; IntroClient waits 15)
	local loaded = false
	task.spawn(function()
		pcall(function() game:GetService("ContentProvider"):PreloadAsync({ cast }) end)
		loaded = true
	end)
	local tLoad = os.clock()
	while not loaded and os.clock() - tLoad < 4 do task.wait() end
	local folder = Instance.new("Folder")
	folder.Name = "BobScene"
	local actors = {}
	local function add(id, model)
		if not model then return end
		model.Parent = folder
		actors[id] = prep(model, id)
	end
	add("bob", cast and cast:FindFirstChild("Bob") and cast.Bob:Clone())
	add("inv1", cast and cast:FindFirstChild("Inv1") and cast.Inv1:Clone())
	add("inv2", cast and cast:FindFirstChild("Inv2") and cast.Inv2:Clone())
	add("hero", heroModel())
	local bubbles = {}
	for id, a in pairs(actors) do bubbles[id] = bubbleFor(a) end

	-- everything the scene changes, so finish() -- or a failure anywhere below -- puts it all back
	local restore, hidden, controls, gui, conn = {}, {}, nil, nil, nil
	local door, tape, front = bc:FindFirstChild("Door"), bc:FindFirstChild("Tape"), bc:FindFirstChild("FrontWall")
	local doorCF = door and door.CFrame
	local knob = bc:FindFirstChild("Knob")
	local knobRel = knob and doorCF and doorCF:ToObjectSpace(knob.CFrame)
	local char = player.Character
	local cam = workspace.CurrentCamera
	local fov0 = cam.FieldOfView
	local function putBack()
		if conn then conn:Disconnect() end
		folder:Destroy()
		for inst, props in pairs(restore) do
			for prop, v in pairs(props) do pcall(function() inst[prop] = v end) end
		end
		if door and doorCF then door.CFrame = doorCF end
		cam.CameraType = Enum.CameraType.Custom
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then cam.CameraSubject = hum end
		cam.FieldOfView = fov0
		if controls then controls:Enable() end
		for _, g in ipairs(hidden) do if g.Parent then g.Enabled = true end end
		player:SetAttribute("BobScenePlaying", false)
		playing = false
	end

	local okRun, result = pcall(function()
	player:SetAttribute("BobScenePlaying", true)
	player:SetAttribute("BobSceneState", "playing")
	folder.Parent = workspace
	local remotes = RS:FindFirstChild("SVRemotes")
	local tele = remotes and remotes:FindFirstChild("BobIntro")
	if name == "intro" and tele then tele:FireServer("start") end
	local function override(inst, prop, value)
		if not inst then return end
		if restore[inst] == nil then restore[inst] = {} end
		if restore[inst][prop] == nil then restore[inst][prop] = inst[prop] end
		inst[prop] = value
	end
	if char then
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Decal") then override(d, "LocalTransparencyModifier", 1) end
		end
	end
	-- the HUD steps aside (a cutscene owns the screen); the chosen ScreenGuis come back after
	for _, g in ipairs(player.PlayerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled and g.Name ~= "BobSceneGui" then g.Enabled = false; table.insert(hidden, g) end
	end
	pcall(function()
		local pm = player.PlayerScripts:FindFirstChild("PlayerModule")
		controls = pm and require(pm):GetControls()
	end)
	if controls then controls:Disable() end
	local myRoot = char and char:FindFirstChild("HumanoidRootPart")
	if myRoot then override(myRoot, "Anchored", true) end

	-- letterbox, SKIP, the money counter
	gui = Instance.new("ScreenGui")
	gui.Name = "BobSceneGui"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30
	gui.ResetOnSpawn = false
	gui.Parent = player.PlayerGui
	local function bar(top)
		local f = Instance.new("Frame")
		f.BackgroundColor3 = INK
		f.BorderSizePixel = 0
		f.Size = UDim2.new(1, 0, 0.1, 0)
		f.AnchorPoint = Vector2.new(0, top and 0 or 1)
		f.Position = UDim2.fromScale(0, top and 0 or 1)
		f.Parent = gui
		return f
	end
	local barT, barB = bar(true), bar(false)
	for _, bb in pairs(bubbles) do bb.card.Parent = gui end
	-- in from black (0.5 s): covers the first frames, when the cast's textures are still arriving
	-- (live 25 Oct: grey heads for about 0.15 s on a fresh join)
	local fadeIn = Instance.new("Frame")
	fadeIn.BackgroundColor3 = INK
	fadeIn.BorderSizePixel = 0
	fadeIn.Size = UDim2.fromScale(1, 1)
	fadeIn.ZIndex = 20
	fadeIn.Parent = gui
	local skipped = false
	local skip = UIKit.button(gui, "SKIP", PAPER, {
		Name = "Skip", AnchorPoint = Vector2.new(1, isTouch and 1 or 0),
		Position = isTouch and UDim2.new(1, -24, 1, -150) or UDim2.new(1, -24, 0, 24),
		Size = UDim2.new(0, 104, 0, 48), ZIndex = 8,
	}, { textSize = 18, dark = true })
	skip.MouseButton1Click:Connect(function() skipped = true end)
	-- the doctor's hand on the SKIP button (DoctorProbes.bobscene): it can only skip your own scene
	local c0 = player:GetAttributeChangedSignal("BobSkipNow"):Connect(function()
		if player:GetAttribute("BobSkipNow") == true then skipped = true end
	end)
	local tapAt, tapPos
	local c1 = UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then tapAt, tapPos = os.clock(), input.Position end
	end)
	local c2 = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch or not tapAt then return end
		if os.clock() - tapAt < 0.4 and (input.Position - tapPos).Magnitude < 12 then skipped = true end
		tapAt = nil
	end)
	local money
	if name == "payoff" then
		money = Instance.new("TextLabel")
		money.BackgroundTransparency = 1
		money.AnchorPoint = Vector2.new(0, 1)
		money.Position = UDim2.new(0, 24, 0.88, 0)
		money.Size = UDim2.fromOffset(420, 48)
		money.Font = UIKit.HEAD
		money.TextSize = UIKit.TYPE.display
		money.TextXAlignment = Enum.TextXAlignment.Left
		money.TextColor3 = UIKit.MONEY
		local st = Instance.new("UIStroke"); st.Thickness = 2; st.Color = INK; st.Parent = money
		money.Visible = false
		money.Parent = gui
	end

	-- props: the chart, bills, the rain cloud / dizzy stars, BOING / x3 / PROVED WRONG
	local chart = cast and cast:FindFirstChild("Chart") and cast.Chart:Clone()
	if chart then chart.Parent = folder; chart.Transparency = 1 end
	-- Luke 25 Oct: "an iPad that I pull out from behind my back" (the paper board was "super bright").
	-- A dark screen: REVENUE, a green line that shoots up, and the number counting up with it
	local chartLine, chartNum = {}, nil
	if chart and chart:FindFirstChild("ChartGui") then
		local g = chart.ChartGui
		local W, H = chart.Size.X * g.PixelsPerStud, chart.Size.Y * g.PixelsPerStud
		local screen = Instance.new("Frame")
		screen.BorderSizePixel = 0
		screen.BackgroundColor3 = Color3.fromRGB(15, 21, 36)   -- world colour (the screen)
		screen.Position, screen.Size = UDim2.fromScale(0.05, 0.07), UDim2.fromScale(0.9, 0.86)
		local sr = Instance.new("UICorner"); sr.CornerRadius = UDim.new(0.04, 0); sr.Parent = screen
		screen.Parent = g
		for k = 1, 3 do
			local grid = Instance.new("Frame")
			grid.BorderSizePixel = 0
			grid.BackgroundColor3 = Color3.fromRGB(38, 48, 72)   -- world colour (grid line)
			grid.Position, grid.Size = UDim2.fromScale(0.06, 0.32 + k * 0.17), UDim2.new(0.88, 0, 0, 2)
			grid.Parent = screen
		end
		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Position, title.Size = UDim2.fromScale(0.12, 0.1), UDim2.fromScale(0.5, 0.13)   -- clear of the holding hand
		title.Font = UIKit.HEAD; title.TextScaled = true; title.TextXAlignment = Enum.TextXAlignment.Left
		title.Text = "REVENUE"; title.TextColor3 = Color3.fromRGB(148, 163, 184)   -- world colour (muted label)
		title.Parent = screen
		chartNum = Instance.new("TextLabel")
		chartNum.BackgroundTransparency = 1
		chartNum.Position, chartNum.Size = UDim2.fromScale(0.12, 0.22), UDim2.fromScale(0.6, 0.19)
		chartNum.Font = UIKit.HEAD; chartNum.TextScaled = true; chartNum.TextXAlignment = Enum.TextXAlignment.Left
		chartNum.TextColor3 = Color3.fromRGB(74, 222, 128)   -- world colour (money up)
		chartNum.Text = "+0%"
		chartNum.Parent = screen
		local pts = { { 0.06, 0.9 }, { 0.2, 0.87 }, { 0.34, 0.84 }, { 0.48, 0.78 }, { 0.62, 0.72 }, { 0.74, 0.6 }, { 0.84, 0.44 }, { 0.94, 0.26 } }
		local sw, sh = W * 0.9, H * 0.86
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundColor3 = Color3.fromRGB(34, 197, 94)   -- world colour (the line)
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			local dx, dy = (b[1] - a[1]) * sw, (b[2] - a[2]) * sh
			f.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + 3, 6)
			f.Position = UDim2.fromScale((a[1] + b[1]) / 2, (a[2] + b[2]) / 2)
			f.Rotation = math.deg(math.atan2(dy, dx))
			f.Visible = false
			f.Parent = screen
			chartLine[i] = f
		end
	end
	local bills = {}
	if name == "payoff" then
		for i = 1, 18 do
			local p = Instance.new("Part")
			p.Name = "Bill"
			p.Size = Vector3.new(0.9, 0.05, 0.5)
			p.Color = Color3.fromRGB(91, 227, 142)   -- world colour
			p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Transparency = true, false, false, false, 1
			p.Parent = folder
			bills[i] = p
		end
	end
	local cloud = {}
	for i = 1, 3 do
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(2.2, 1.6, 1.6) * (i == 2 and 1.2 or 1)
		p.Color = Color3.fromRGB(109, 115, 131)   -- world colour
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Transparency = true, false, false, false, 1
		p.Parent = folder
		cloud[i] = p
	end
	local fxs = {}
	local f0 = BobScript.at(name, 0, true)
	for i, x in ipairs(f0.fx) do
		if x.kind == "text" then fxs[i] = worldText(folder, x.text) end
		if x.kind == "stars" then fxs[i] = worldText(folder, "* * *", UIKit.GOLD) end
		if x.kind == "debris" then
			-- the door coming down: wood splinters and a puff of dust out of the doorway
			local d = { splinters = {} }
			for k = 1, 10 do
				d.splinters[k] = Instance.new("Part")
				d.splinters[k].Size = Vector3.new(0.18, 0.18, 0.5 + (k % 3) * 0.3)
				d.splinters[k].Color = Color3.fromRGB(110, 74, 48)   -- world colour (the door's wood)
				d.splinters[k].Material = Enum.Material.Wood
			end
			for _, p in ipairs(d.splinters) do
				p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Transparency, p.CastShadow = true, false, false, false, 1, false
				p.Parent = folder
			end
			-- live 25 Oct: dust as balls read as soap bubbles; a burst of Roblox's own smoke instead
			local holder = Instance.new("Part")
			holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch, holder.Transparency = true, false, false, false, 1
			holder.Size = Vector3.new(4, 0.2, 0.4)
			holder.Parent = folder
			local puff = Instance.new("ParticleEmitter")
			puff.Texture = "rbxasset://textures/particles/smoke_main.dds"
			puff.Color = ColorSequence.new(Color3.fromRGB(205, 196, 180))   -- world colour (plaster dust)
			puff.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
			puff.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 5) })
			puff.Lifetime = NumberRange.new(0.7, 1.2)
			puff.Speed = NumberRange.new(3, 8)
			puff.SpreadAngle = Vector2.new(70, 25)
			puff.Drag = 3
			puff.Rate = 0
			puff.LightInfluence = 0.6
			puff.EmissionDirection = Enum.NormalId.Front
			puff.Parent = holder
			d.holder, d.puff = holder, puff
			fxs[i] = d
		end
	end

	-- the camera owns the view until finish()
	cam.CameraType = Enum.CameraType.Scriptable

	local t0, lastT, finished = os.clock(), 0, false
	local lastExtras
	-- everyone with a Humanoid: one scan now, then only the ones that arrive (a full scan a second hitched)
	local people = {}
	for _, d in ipairs(workspace:GetDescendants()) do if d:IsA("Humanoid") then people[d] = true end end
	local cPeople = workspace.DescendantAdded:Connect(function(d) if d:IsA("Humanoid") then people[d] = true end end)
	local length = BobScript.length(name)

	local function finish(wasSkipped)
		if finished then return end
		finished = true
		c0:Disconnect(); c1:Disconnect(); c2:Disconnect(); cPeople:Disconnect()
		local endT = os.clock() - t0
		-- a skipped intro still ends where the story ends: you at your laptop
		if name == "intro" and char and char.PrimaryPart and A.garage then
			local hero = BobScript.at(name, length, true).actors.hero
			pcall(function() char:PivotTo(A.garage * CFrame.new(hero.pos + Vector3.new(0, 3, 0)) * CFrame.Angles(0, R(180 + hero.rot), 0)) end)
		end
		putBack()
		player:SetAttribute("BobSceneState", "done")
		if tele and name == "intro" then tele:FireServer(wasSkipped and ("skip:" .. math.floor(endT)) or "end") end
		if name == "payoff" and money then
			-- the toast lingers 3 s over the game, it blocks nothing
			barT:Destroy(); barB:Destroy(); skip:Destroy()
			money.Text = BobScript.LINES.toast
			money.Visible = true
			task.delay(3, function() gui:Destroy() end)
		else
			gui:Destroy()
		end
	end

	conn = RunService.RenderStepped:Connect(function()
		-- live 25 Oct: a client walking into the garage stood in front of the camera. Anyone else near
		-- the set (staff, clients, other players) steps out of the shot, once a second
		if os.clock() - (lastExtras or 0) > 1 then
			lastExtras = os.clock()
			for mdl in pairs(people) do
				if mdl.Parent and not mdl:IsDescendantOf(folder) then
					local who = mdl.Parent
					local root = who:FindFirstChild("HumanoidRootPart") or who.PrimaryPart
					local near = false
					if root then
						for _, a in pairs(A) do
							if (root.Position - a.Position).Magnitude < 45 then near = true break end
						end
					end
					if near then
						for _, d in ipairs(who:GetDescendants()) do
							if d:IsA("BasePart") or d:IsA("Decal") then override(d, "LocalTransparencyModifier", 1)
							elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then override(d, "Enabled", false) end
						end
					end
				end
			end
		end
		for _, g in ipairs(player.PlayerGui:GetChildren()) do
			if g:IsA("ScreenGui") and g.Enabled and g ~= gui and not table.find(hidden, g) then
				g.Enabled = false
				table.insert(hidden, g)
			end
		end
		local t = os.clock() - t0
		-- Studio only: hold the scene at one moment (BobSceneHold = seconds) so each shot can be screenshotted
		local hold = RunService:IsStudio() and player:GetAttribute("BobSceneHold")
		if type(hold) == "number" then t = math.clamp(hold, 0, length - 0.01); t0 = os.clock() - t end
		if skipped or t >= length then finish(skipped) return end
		local reduced = UIKit.reducedMotion()
		local f = BobScript.at(name, t, reduced)
		-- actors
		for id, a in pairs(actors) do
			local st = f.actors[id]
			if st then
				setVisible(a, st.visible)
				place(a, A[st.anchor], st.pos, st.rot, st.roll, { folder, char, bc:FindFirstChild("Dressing") })
				local clip = clipFor(name, id, st.pose, t)
				if clip ~= a.clip then a.clip, a.clipStart = clip, t end
				if clip and BobClips.has(clip) then
					for _, j in pairs(a.motors) do j.Transform = CFrame.new() end
					for joint, cf in pairs(BobClips.sample(clip, math.max(0, t - a.clipStart))) do
						local j = a.motors[joint]
						if j then j.Transform = cf end
					end
				else
					pose(a, st.pose, t)
				end
				a.face.set(st.face)
				if st.visible then BobFace.facing(a.model, cam.CFrame.Position) end
			end
		end
		-- Bob's sunglasses fly off and the toothpick drops (payoff)
		local bob = actors.bob
		if bob then
			local g, pk = f.vals.glasses or 0, f.vals.pick or 0
			local sg, tp = bob.model:FindFirstChild("Sunglasses"), bob.model:FindFirstChild("Toothpick")
			-- review I-7: anchoring a welded part drags Bob with it, so unweld each one as it moves
			if sg and g > 0 and sg:FindFirstChildOfClass("WeldConstraint") then sg:FindFirstChildOfClass("WeldConstraint"):Destroy() end
			if tp and pk > 0 and tp:FindFirstChildOfClass("WeldConstraint") then tp:FindFirstChildOfClass("WeldConstraint"):Destroy() end
			if sg and g > 0 and bob.head then sg.Anchored = true; sg.CFrame = bob.head.CFrame * CFrame.new(g * 1.2, 1 + g * 3, -0.7) * CFrame.Angles(0, 0, g * 1.2) end
			if tp and pk > 0 and bob.head then tp.Anchored = true; tp.CFrame = bob.head.CFrame * CFrame.new(0.4, -0.6 - pk * 2.6, -0.8) * CFrame.Angles(0, 0, pk * 3) end
		end
		-- bubbles (placed after the camera moves, below)
		for id, bb in pairs(bubbles) do
			bb.on = nil
			for _, b in ipairs(f.bubbles) do
				if b.actor == id and b.k > 0 then bb.on = b end
			end
			if bb.on then bb.card.Text = bb.on.text; bb.scale.Scale = bb.on.k else bb.card.Visible = false end
		end
		-- fx: words, the rain cloud over you, stars over Bob
		for i, x in ipairs(f.fx) do
			local fx = fxs[i]
			if x.kind == "cloud" then
				local hero = actors.hero
				for k, p in ipairs(cloud) do
					p.Transparency = x.k > 0 and 0.1 or 1
					if hero and hero.head and x.k > 0 then p.CFrame = hero.head.CFrame * CFrame.new((k - 2) * 1.1, 2.3 + (k == 2 and 0.35 or 0), 0) end
				end
			elseif x.kind == "debris" and fx then
				local base = A[x.anchor] and A[x.anchor] * CFrame.new(x.pos)
				local age = x.age or 0
				local on = x.k > 0 and base ~= nil
				for k, p in ipairs(fx.splinters) do
					if on then
						-- out of the doorway toward us and up, then down to the pavement
						local dir = Vector3.new(math.cos(k * 2.4) * 0.9, 1.1 + (k % 4) * 0.25, 0.9 + math.sin(k * 1.7) * 0.4)
						local s = dir * 9 * age - Vector3.new(0, 30 * age * age, 0)
						local pos = base * CFrame.new(math.cos(k) * 1.4, 1 + (k % 5) * 1.2, 0)
						local at = pos.Position + base:VectorToWorldSpace(Vector3.new(s.X, 0, s.Z)) + Vector3.new(0, s.Y, 0)
						at = Vector3.new(at.X, math.max(at.Y, base.Position.Y + 0.1), at.Z)
						p.CFrame = CFrame.new(at) * CFrame.Angles(age * (6 + k), age * 4, k)
						p.Transparency = age > 0.7 and math.clamp((age - 0.7) / 0.25, 0, 1) or 0
					else
						p.Transparency = 1
					end
				end
				if on and not fx.puffed then
					-- out of the doorway toward the street (the holder's front faces +Z, out of the building)
					fx.holder.CFrame = base * CFrame.new(0, 0.6, 0.4) * CFrame.Angles(0, math.pi, 0)
					fx.puff:Emit(30)
					fx.puffed = true
				end
			elseif fx then
				fx.gui.Enabled = x.k > 0
				fx.scale.Scale = x.k
				if x.follow and actors[x.follow] and actors[x.follow].head then
					fx.part.CFrame = actors[x.follow].head.CFrame * CFrame.new(0, 2.2, 0)
				elseif x.anchor and A[x.anchor] then
					fx.part.CFrame = A[x.anchor] * CFrame.new(x.pos)
				end
			end
		end
		-- the iPad: out of sight behind your back, round in your right hand, then held in both
		if chart then
			local hero = actors.hero
			local clipT = hero and hero.clip == "hero_ipad" and (t - hero.clipStart) or -1
			local shown = (f.vals.chartShown or 0) > 0.5 and hero ~= nil and clipT >= BobClips.IPAD_IN_HAND
			chart.Transparency = shown and 0 or 1
			if chart:FindFirstChild("ChartGui") then chart.ChartGui.Enabled = shown end
			if shown then
				local m = hero.model
				local rh = m:FindFirstChild("RightHand")
				-- held out in front of the chest (live 25 Oct: placed between the hands it rode up over his
				-- face), screen to Bob, tipped up a little
				local torso = m:FindFirstChild("UpperTorso") or m:FindFirstChild("Torso") or hero.root
				local look = hero.root.CFrame.LookVector
				local at = torso.Position + look * (torso.Size.Z / 2 + 1.25) + Vector3.new(0, -0.1, 0)
				local held = CFrame.lookAt(at, at + look) * CFrame.Angles(R(12), 0, 0)
				if clipT < BobClips.IPAD_HELD and rh then
					local inHand = rh.CFrame * CFrame.new(0, -0.15, 0) * CFrame.Angles(R(90), 0, 0)
					chart.CFrame = inHand:Lerp(held, math.clamp((clipT - (BobClips.IPAD_HELD - 0.3)) / 0.3, 0, 1))
				else
					chart.CFrame = held
				end
			end
			local k = f.vals.chart or 0
			local n = math.floor(k * #chartLine + 0.5)
			for i, seg in ipairs(chartLine) do seg.Visible = i <= n end
			if chartNum then chartNum.Text = ("+%d%%"):format(math.floor(k * 312)) end
		end
		-- money flying from Bob to you, and the counter
		if #bills > 0 then
			local prog = f.vals.bills or 0
			local from = actors.bob and actors.bob.root and actors.bob.root.Position + Vector3.new(0, 1.5, 0)
			local to = actors.hero and actors.hero.root and actors.hero.root.Position + Vector3.new(0, 1, 0)
			for i, p in ipairs(bills) do
				local k = math.clamp(prog * 1.6 - (i - 1) * 0.035, 0, 1)
				if from and to and k > 0 and k < 1 then
					local pos = from:Lerp(to, k) + Vector3.new(math.sin(i * 7) * 1.2, 4 * 2.2 * k * (1 - k), math.cos(i * 5))
					p.CFrame = CFrame.new(pos) * CFrame.Angles(k * 9 + i, k * 7, i)
					p.Transparency = 0
				else
					p.Transparency = 1
				end
			end
			if money then
				money.Visible = prog > 0
				money.Text = ("+%s  SERIES A x3"):format(UIKit.money and UIKit.money(math.floor((info and info.amount or 0) * math.min(1, prog * 1.15)))
					or tostring(math.floor((info and info.amount or 0) * math.min(1, prog * 1.15))))
			end
		end
		-- Bob's door, the tape, and the front wall (hidden for the boardroom shots: a cutaway)
		if door and doorCF then
			if f.doorDown > 0 then
				-- Luke 25 Oct: "you slam the door down": it falls flat into the room about its bottom
				-- edge (the scene's door is -Z into the building) and lies there
				local edge = doorCF * CFrame.new(0, -door.Size.Y / 2 + door.Size.Z / 2, 0)
				door.CFrame = edge * CFrame.Angles(R(-90 * f.doorDown), 0, 0) * CFrame.new(0, door.Size.Y / 2 - door.Size.Z / 2, 0)
			else
				local hinge = doorCF * CFrame.new(-door.Size.X / 2, 0, 0)
				door.CFrame = hinge * CFrame.Angles(0, R(-100 * f.door), 0) * CFrame.new(door.Size.X / 2, 0, 0)
			end
			override(door, "CanCollide", false)
			if knob and knobRel then override(knob, "CFrame", door.CFrame * knobRel) end
		end
		if tape then
			-- the tape tears off as the door goes: each strip flies its own way and fades
			for i, p in ipairs(tape:GetChildren()) do
				if p:IsA("BasePart") then
					local side = i % 2 == 0 and 1 or -1
					local k = f.tape
					if restore[p] == nil or restore[p].CFrame == nil then override(p, "CFrame", p.CFrame) end
					local p0 = restore[p].CFrame
					p.CFrame = p0 * CFrame.new(side * k * 2.2, -k * 3.2, k * 1.6) * CFrame.Angles(k * 1.4, 0, side * k * 1.8)
					override(p, "LocalTransparencyModifier", math.clamp(k * 1.4 - 0.4, 0, 1))
				end
			end
		end
		local cutaway = f.cam.anchor == "board" and 1 or 0
		if front then
			for _, p in ipairs(front:GetDescendants()) do
				if p:IsA("BasePart") then override(p, "LocalTransparencyModifier", cutaway)
				elseif p:IsA("SurfaceGui") then override(p, "Enabled", cutaway == 0) end   -- a hidden part still draws its gui
			end
		end
		for _, n in ipairs({ "Door", "Knob", "Sign" }) do
			local p = bc:FindFirstChild(n)
			if p then override(p, "LocalTransparencyModifier", cutaway) end
		end
		local sign = bc:FindFirstChild("Sign")
		local sg = sign and sign:FindFirstChildOfClass("SurfaceGui")
		if sg then override(sg, "Enabled", cutaway == 0) end
		-- sound cues crossed since the last frame
		for _, cue in ipairs(BobScript.cues(name, lastT, t)) do
			local isMusic = cue == "music" or cue == "victory"
			if SOUND[cue] and not (isMusic and player:GetAttribute("MenuMuted") == true) then
				Sfx.play(folder, SOUND[cue], { volume = 0.6, life = cue == "music" and 18 or 6 })
			end
		end
		lastT = t
		fadeIn.BackgroundTransparency = math.clamp((t - 0.2) / 0.3, 0, 1)   -- black 0.2 s, then a fade (kept under Reduce Motion)
		fadeIn.Visible = t < 0.5   -- gone after, so it never sits over SKIP
		-- letterbox out at the hand-off
		barT.Position = UDim2.new(0, 0, -0.1 * f.handoff, 0)
		barB.Position = UDim2.new(0, 0, 1 + 0.1 * f.handoff, 0)
		-- the camera: hard cuts between shots; pushes and shake are gone under Reduce Motion
		local base = A[f.cam.anchor]
		if base then
			local shake = f.shake > 0 and Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * 2 * f.shake or Vector3.zero
			-- motion: camera (reduced read above: BobScript.at(name, t, UIKit.reducedMotion()))
			if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end   -- anything that resets it loses
			cam.CFrame = CFrame.lookAt(base * f.cam.offset, base * f.cam.look) * CFrame.new(shake)
			cam.FieldOfView = f.cam.fov
			-- the iPad close-up: framed from the tablet itself, so it holds on any avatar's size
			if f.cam.aim == "tablet" and chart and chart.Transparency < 1 and f.cam.dist then
				local c = chart.CFrame
				local from = c.Position + c.LookVector * f.cam.dist + c.UpVector * 0.25 + c.RightVector * 0.35
				cam.CFrame = CFrame.lookAt(from, c.Position + c.UpVector * 0.1) * CFrame.new(shake)
			end
			-- Studio only: BobSceneLook = an actor id ("hero", "bob", "inv1", "inv2") frames that actor's head
			-- up close, from its front-left (BobSceneLookDist studs, default 9), so a held clip or a face
			-- can be checked by eye
			local look = RunService:IsStudio() and actors[player:GetAttribute("BobSceneLook") or ""]
			if look and look.root then
				local r = look.root.CFrame
				local d = player:GetAttribute("BobSceneLookDist") or 9
				local at = look.head and look.head.Position or r.Position + Vector3.new(0, 0.6, 0)
				cam.CFrame = CFrame.lookAt(at + r.LookVector * d - r.RightVector * d * 0.35 + Vector3.new(0, d * 0.12, 0), at)
				cam.FieldOfView = 50
			end
		end
		for _, bb in pairs(bubbles) do
			if bb.on and bb.head then
				local w = bb.card.TextBounds.X + 36
				local x, y = bubbleAt(cam, bb.head, w, 54)
				bb.card.Visible = x ~= nil
				if x then bb.card.Position = UDim2.fromOffset(x, y) end
			end
		end
	end)

	while not finished do task.wait(0.1) end
	return not skipped
	end)
	if not okRun then
		warn("[Bob] the scene failed and was put back: " .. tostring(result))
		putBack()
		if gui then gui:Destroy() end
		player:SetAttribute("BobSceneState", "failed")
		return false
	end
	return result
end

event.Event:Connect(function(name, info)
	task.spawn(play, name, info)
end)

-- the server paid you at Bob's door: play the payoff (the money is already yours)
task.spawn(function()
	local remotes = RS:WaitForChild("SVRemotes", 60)
	local ev = remotes and remotes:WaitForChild("BobPayoff", 60)
	if ev then ev.OnClientEvent:Connect(function(info) task.spawn(play, "payoff", info) end) end
end)
