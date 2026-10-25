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
		if m:IsA("Motor6D") then motors[m.Name] = m end
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

-- feet at pos (anchor space); rot 0 faces the camera (+Z), 90 faces +X; roll spins round Z
-- live 25 Oct (Luke: "phasing through the floor"): an anchor's height is not the floor's (the
-- garage floor sits above the lot), so each actor stands on the real floor under its feet
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function floorAt(world, ignore)
	rayParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(world + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0), rayParams)
	return hit and hit.Position.Y or nil
end
local function place(a, anchorCF, pos, rot, roll, ignore)
	if not (a.root and anchorCF) then return end
	local lift = (a.hum and a.hum.HipHeight or 2) + a.root.Size.Y / 2
	local at = (anchorCF * CFrame.new(pos.X, 0, pos.Z)).Position
	local floor = floorAt(at, ignore or {}) or at.Y
	a.root.CFrame = CFrame.new(at.X, floor + pos.Y + lift, at.Z) * anchorCF.Rotation * CFrame.Angles(0, 0, R(roll or 0))
		* CFrame.Angles(0, R(180 + (rot or 0)), 0)
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
local function bubbleFor(a)
	local bb = Instance.new("BillboardGui")
	bb.Name = "BobBubble"
	bb.Size = UDim2.fromOffset(360, 90)
	bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Adornee = a.head
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = bb
	local card = Instance.new("TextLabel")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.fromScale(0.5, 1)
	card.AutomaticSize = Enum.AutomaticSize.X
	card.Size = UDim2.fromOffset(0, 54)
	card.BackgroundColor3 = PAPER
	card.TextColor3 = INK
	card.Font = UIKit.HEAD
	card.TextSize = UIKit.TYPE.headline
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 18), UDim.new(0, 18)
	pad.Parent = card
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, UIKit.RADIUS.lg); c.Parent = card
	local s = Instance.new("UIStroke"); s.Thickness = 3; s.Color = INK; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = card
	local sc = Instance.new("UIScale"); sc.Parent = card
	card.Parent = holder
	bb.Parent = a.model
	return { gui = bb, card = card, scale = sc }
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
	local chartLine = {}
	if chart and chart:FindFirstChild("ChartGui") then
		local g = chart.ChartGui
		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1; title.Size = UDim2.fromScale(1, 0.24); title.Font = UIKit.HEAD
		title.TextScaled = true; title.Text = "REVENUE"; title.TextColor3 = INK; title.Parent = g
		local pts = { { 0.1, 0.9 }, { 0.25, 0.86 }, { 0.4, 0.8 }, { 0.55, 0.7 }, { 0.7, 0.62 }, { 0.82, 0.42 }, { 0.92, 0.28 } }
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundColor3 = Color3.fromRGB(22, 163, 74)   -- world colour
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			local dx, dy = (b[1] - a[1]) * 300, (b[2] - a[2]) * 216
			f.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + 4, 9)
			f.Position = UDim2.fromScale((a[1] + b[1]) / 2, (a[2] + b[2]) / 2)
			f.Rotation = math.deg(math.atan2(dy, dx))
			f.Visible = false
			f.Parent = g
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
		if x.kind == "text" then fxs[i] = worldText(folder, x.text, x.text == BobScript.LINES.proved and UIKit.GOLD or nil) end
		if x.kind == "stars" then fxs[i] = worldText(folder, "* * *", UIKit.GOLD) end
	end

	-- the camera owns the view until finish()
	cam.CameraType = Enum.CameraType.Scriptable

	local t0, lastT, finished = os.clock(), 0, false
	local length = BobScript.length(name)

	local function finish(wasSkipped)
		if finished then return end
		finished = true
		c0:Disconnect(); c1:Disconnect(); c2:Disconnect()
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
		local t = os.clock() - t0
		if skipped or t >= length then finish(skipped) return end
		local reduced = UIKit.reducedMotion()
		local f = BobScript.at(name, t, reduced)
		-- actors
		for id, a in pairs(actors) do
			local st = f.actors[id]
			if st then
				setVisible(a, st.visible)
				place(a, A[st.anchor], st.pos, st.rot, st.roll, { folder, char })
				pose(a, st.pose, t)
				a.face.set(st.face)
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
		-- bubbles
		for _, b in ipairs(f.bubbles) do
			local bb = bubbles[b.actor]
			if bb and b.k > 0 then bb.card.Text = b.text; bb.scale.Scale = b.k; bb.gui.Enabled = true end
		end
		for id, bb in pairs(bubbles) do
			local any = false
			for _, b in ipairs(f.bubbles) do if b.actor == id and b.k > 0 then any = true end end
			if not any then bb.gui.Enabled = false end
		end
		-- fx: words, the rain cloud over you, stars over Bob
		for i, x in ipairs(f.fx) do
			local fx = fxs[i]
			if x.kind == "cloud" then
				local hero = actors.hero
				for k, p in ipairs(cloud) do
					p.Transparency = x.k > 0 and 0.1 or 1
					if hero and hero.head and x.k > 0 then p.CFrame = hero.head.CFrame * CFrame.new((k - 2) * 1.1, 3.2 + (k == 2 and 0.4 or 0), 0) end
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
		-- the chart in your hands
		if chart then
			local shown = (f.vals.chartShown or 0) > 0.5
			chart.Transparency = shown and 0 or 1
			if chart:FindFirstChild("ChartGui") then chart.ChartGui.Enabled = shown end
			local hero = actors.hero
			if shown and hero and hero.head then chart.CFrame = hero.head.CFrame * CFrame.new(0, 2.3, -1.2) end
			local n = math.floor((f.vals.chart or 0) * #chartLine + 0.5)
			for i, seg in ipairs(chartLine) do seg.Visible = i <= n end
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
			local hinge = doorCF * CFrame.new(-door.Size.X / 2, 0, 0)
			door.CFrame = hinge * CFrame.Angles(0, R(-100 * f.door), 0) * CFrame.new(door.Size.X / 2, 0, 0)
			override(door, "CanCollide", false)
		end
		if tape then for _, p in ipairs(tape:GetChildren()) do if p:IsA("BasePart") then override(p, "LocalTransparencyModifier", f.tape) end end end
		if front then
			for _, p in ipairs(front:GetDescendants()) do
				if p:IsA("BasePart") then override(p, "LocalTransparencyModifier", f.cam.anchor == "board" and 1 or 0) end
			end
		end
		-- sound cues crossed since the last frame
		for _, cue in ipairs(BobScript.cues(name, lastT, t)) do
			local isMusic = cue == "music" or cue == "victory"
			if SOUND[cue] and not (isMusic and player:GetAttribute("MenuMuted") == true) then
				Sfx.play(folder, SOUND[cue], { volume = 0.6, life = cue == "music" and 18 or 6 })
			end
		end
		lastT = t
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
