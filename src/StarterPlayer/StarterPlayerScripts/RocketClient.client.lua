--[[
	RocketClient -- LocalScript in StarterPlayer -> StarterPlayerScripts (v3.4 W3).

	THE LAUNCH IS A LAUNCH. The old ceremony was a green neon box that floated
	off the roof. Now every LAUNCH fires the game's own brand, the rocket,
	off that founder's HQ roof, and EVERY player in the server sees it:

	  0.0 s   ignition: smoke blasts out of the pad, the rocket shudders
	  0.6 s   lift-off: a green brand flame, a smoke column that hangs in
	          the sky, the app's name riding up with it
	  4.6 s   burst: fireworks at the apex in the launcher's colours

	A rocket climbing out of another campus is the clip, and it is the
	"someone is doing well here" signal the server never had. Built and
	animated here from the server's RocketLaunch event: nothing replicates.
	Particle textures are Roblox built-ins (rbxasset://textures/particles),
	sounds are Roblox Pro Sound Effects.

	When the Blender rocket mesh is imported (ReplicatedStorage.SVMeshes.Rocket)
	it is used instead of the part rocket.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("SVRemotes")

local WHITE = Color3.fromRGB(244, 244, 240)
local GOLD = Color3.fromRGB(255, 196, 64)
local SLATE = Color3.fromRGB(64, 74, 92)
local PORT = Color3.fromRGB(90, 180, 255)
local FLAME = Color3.fromRGB(90, 235, 120)          -- the brand flame is green
local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"
local SPARK_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE_TEX = "rbxasset://textures/particles/fire_main.dds"
local BURST = { Color3.fromRGB(255, 196, 64), Color3.fromRGB(90, 235, 120), Color3.fromRGB(90, 180, 255), Color3.fromRGB(255, 110, 150) }

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do p[k] = v end
	p.Parent = parent
	return p
end

-- the brand rocket, ~11 studs, built around its base at the origin
local function buildRocket()
	local m = Instance.new("Model")
	m.Name = "LaunchRocket"
	local mesh = ReplicatedStorage:FindFirstChild("SVMeshes") and ReplicatedStorage.SVMeshes:FindFirstChild("Rocket")
	if mesh then
		local c = mesh:Clone()
		for _, d in ipairs(c:IsA("BasePart") and { c } or c:GetDescendants()) do
			if d:IsA("BasePart") then d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false end
		end
		c.Parent = m
		local _, size = m:GetBoundingBox()
		m:ScaleTo(11 / math.max(size.Y, 0.1))
		-- stand it on the origin: bottom-centre of its box at (0, 0, 0)
		local cf, sz = m:GetBoundingBox()
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then d.CFrame = d.CFrame - (cf.Position - Vector3.new(0, sz.Y / 2, 0)) end
		end
	else
		part({ Name = "Body", Shape = Enum.PartType.Cylinder, Size = Vector3.new(6, 2.6, 2.6), CFrame = CFrame.new(0, 4, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = WHITE }, m)
		part({ Name = "Nose1", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.3, 2.2, 2.2), CFrame = CFrame.new(0, 7.6, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = GOLD }, m)
		part({ Name = "Nose2", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.1, 1.5, 1.5), CFrame = CFrame.new(0, 8.8, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = GOLD }, m)
		part({ Name = "Tip", Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.9, 0.9), CFrame = CFrame.new(0, 9.6, 0), Color = GOLD }, m)
		part({ Name = "Port", Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(0, 5.2, -1.05), Color = PORT, Material = Enum.Material.Neon }, m)
		for k = 0, 2 do
			local a = k * math.pi * 2 / 3
			part({ Name = "Fin", Size = Vector3.new(0.35, 2.6, 1.8), CFrame = CFrame.Angles(0, a, 0) * CFrame.new(0, 1.8, -1.6), Color = SLATE }, m)
		end
		part({ Name = "Nozzle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 1.6, 1.6), CFrame = CFrame.new(0, 0.7, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = SLATE }, m)
	end
	-- the pivot is an invisible root on the base, upright (a cylinder part's own
	-- frame is turned 90 degrees and would have launched the rocket sideways)
	local root = part({ Name = "Root", Size = Vector3.new(0.4, 0.4, 0.4), CFrame = CFrame.new(0, 0, 0), Transparency = 1 }, m)
	m.PrimaryPart = root
	-- the flame: a neon core that the particles pour out of
	local flame = part({ Name = "Flame", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), CFrame = CFrame.new(0, -0.3, 0), Color = FLAME, Material = Enum.Material.Neon, Transparency = 1 }, m)
	local att = Instance.new("Attachment"); att.Parent = flame
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = FIRE_TEX
	fire.Color = ColorSequence.new(FLAME, Color3.fromRGB(255, 240, 160))
	fire.LightEmission = 1
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.8), NumberSequenceKeypoint.new(1, 0.2) })
	fire.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	fire.Lifetime = NumberRange.new(0.25, 0.45)
	fire.Speed = NumberRange.new(14, 22)
	fire.SpreadAngle = Vector2.new(8, 8)
	fire.EmissionDirection = Enum.NormalId.Bottom
	fire.Rate = 0
	fire.Parent = att
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = SMOKE_TEX
	-- warm grey, not white: white smoke vanished against white cloud (measured on screen)
	smoke.Color = ColorSequence.new(Color3.fromRGB(214, 208, 200), Color3.fromRGB(148, 146, 150))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 14) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.6, 0.55), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(4, 6)
	smoke.Speed = NumberRange.new(2, 5)
	smoke.SpreadAngle = Vector2.new(25, 25)
	smoke.EmissionDirection = Enum.NormalId.Bottom
	smoke.RotSpeed = NumberRange.new(-30, 30)
	smoke.Rate = 0
	smoke.LockedToPart = false
	smoke.Parent = att
	-- the contrail: one continuous ribbon reads from across the valley where
	-- scattered particles don't. Two attachments either side of the nozzle.
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(-0.9, 0, 0); a0.Parent = flame
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0.9, 0, 0); a1.Parent = flame
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 236, 190), Color3.fromRGB(170, 168, 172))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3.5) })
	trail.Lifetime = 2.6
	trail.MinLength = 0.2
	trail.FaceCamera = true
	trail.LightInfluence = 0.3
	trail.Enabled = false
	trail.Parent = flame
	return m, flame, fire, smoke
end

local function burstAt(pos, color)
	local p = part({ Name = "Burst", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(pos), Transparency = 1 }, workspace)
	local att = Instance.new("Attachment"); att.Parent = p
	for i = 1, 3 do
		local e = Instance.new("ParticleEmitter")
		e.Texture = SPARK_TEX
		e.Color = ColorSequence.new(i == 1 and color or BURST[math.random(1, #BURST)])
		-- additive glow washes a saturated colour to white against a bright sky;
		-- mostly-opaque + unlit keeps gold gold and green green in daylight
		e.LightEmission = 0.3
		e.LightInfluence = 0
		pcall(function() e.Brightness = 2.5 end)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 1) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(1.4, 2.2)
		e.Speed = NumberRange.new(60, 100)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Drag = 2.5
		e.Acceleration = Vector3.new(0, -12, 0)
		e.Rate = 0
		e.Parent = att
		e:Emit(110)
	end
	-- a flash that lights the campus for a beat: readable from the far side of the valley
	local flash = Instance.new("PointLight")
	flash.Color = color
	flash.Range = 60
	flash.Brightness = 6
	flash.Parent = p
	TweenService:Create(flash, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	Debris:AddItem(p, 4)
end

local function sound(id, parent, vol, maxd)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol
	s.RollOffMinDistance = 40
	s.RollOffMaxDistance = maxd or 700
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 12)
	return s
end

local active = 0
local function launch(data)
	if type(data) ~= "table" or typeof(data.pos) ~= "Vector3" then return end
	local cam = workspace.CurrentCamera
	local dist = (cam.CFrame.Position - data.pos).Magnitude
	if dist > 1100 or active >= 3 then return end    -- too far to read, or the sky is full
	active += 1
	local mine = data.owner == player.UserId
	local rocket, flame, fire, smoke = buildRocket()
	local trail = flame:FindFirstChildOfClass("Trail")
	local base = CFrame.new(data.pos)
	rocket:PivotTo(base)
	rocket.Parent = workspace
	-- the app's name rides up with it
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.new(0, 220, 0, 36)
	tag.StudsOffset = Vector3.new(0, 13, 0)
	tag.AlwaysOnTop = true
	tag.MaxDistance = 600
	tag.Adornee = rocket.PrimaryPart
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, 0, 1, 0)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = GOLD
	t.TextStrokeTransparency = 0.2
	t.Text = tostring(data.name or "LAUNCH")
	t.Parent = tag
	tag.Parent = rocket

	-- ignition
	sound("rbxassetid://9114361763", rocket.PrimaryPart, mine and 0.55 or 0.35)   -- PSE Explosion Oxyacetylene Gas 1
	smoke.Rate = 60
	smoke:Emit(40)
	fire.Rate = 60
	local t0 = os.clock()
	local whistled = false
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local e = os.clock() - t0
		local y, shake = 0, 0
		if e < 0.6 then
			shake = 0.15
		else
			local u = e - 0.6
			y = 6 * u * u + 8 * u                         -- accelerating climb
			fire.Rate = 120
			if trail then trail.Enabled = true end
			if not whistled then
				whistled = true
				sound("rbxassetid://9114447104", rocket.PrimaryPart, mine and 0.6 or 0.4)   -- PSE Fireworks Fast 2 (whistler)
			end
		end
		rocket:PivotTo(base * CFrame.new(math.random() * shake - shake / 2, y, math.random() * shake - shake / 2)
			* CFrame.Angles(0, e * 0.6, 0))
		-- the owner's camera feels it
		if mine and e < 1.4 and (cam.CFrame.Position - data.pos).Magnitude < 160 then
			cam.CFrame = cam.CFrame * CFrame.new((math.random() - 0.5) * 0.12, (math.random() - 0.5) * 0.12, 0)
		end
		if e > 4.6 then
			conn:Disconnect()
			burstAt(rocket.PrimaryPart.Position + Vector3.new(0, 6, 0), data.color or GOLD)
			fire.Rate, smoke.Rate = 0, 0
			if trail then trail.Enabled = false end
			for _, d in ipairs(rocket:GetDescendants()) do
				if d:IsA("BasePart") then d.Transparency = 1 end
				if d:IsA("BillboardGui") then d.Enabled = false end
			end
			Debris:AddItem(rocket, 6)                        -- the smoke column lingers, then goes
			active -= 1
		end
	end)
end

task.spawn(function()
	local ev = remotes:WaitForChild("RocketLaunch", 60)
	if ev then ev.OnClientEvent:Connect(launch) end
end)
