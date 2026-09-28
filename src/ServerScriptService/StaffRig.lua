--[[
	StaffRig -- ModuleScript in ServerScriptService.

	Builds staff as REAL R15 rigs driven by Roblox's built-in Humanoid animation
	set, instead of two anchored blocks standing still.

	WHY THIS AND NOT MESHES: the complaint was that the people look dead. Meshes
	would make them prettier and still dead. Motion is what reads as alive, and
	the default animation set is free, built in, needs no upload and no
	moderation queue. This is the cheapest large win available.

	WHAT EACH STAFF MEMBER DOES:
	  - idles with a real breathing animation at their desk
	  - periodically walks to another point in the room and back
	  - types when at a desk (arm bob driven in Lua, not an animation upload)
	  - carries a role colour and a floating name/role tag

	R15 IS BUILT MANUALLY. Roblox has no server-side "make me a rig" call, so
	the parts and Motor6Ds are assembled here. Humanoid then drives it.
]]

local StaffRig = {}

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

--[[
	v2.8.1 MOTION LIVES ON THE CLIENT. Measured on a full server (6 plots x 30
	staff): the old loops wrote 3 Motor6D.C0 per rig every 0.06 s ON THE
	SERVER, and every write replicated to every player -- 8,637 joint updates/s,
	246.5 KB/s sent per player. The same 180 rigs with no server motion: 10.0
	KB/s (and that 10 was the 7 real staff still animating). Roblox's own
	performance guide: "Play NPC animations on the client rather than server",
	"Update Motor6D.Transform instead of C0 and C1".

	Now the server only BUILDS, PLACES and SEATS staff (one-time property
	changes) and publishes intent as attributes; StaffAnimClient (StarterPlayer
	Scripts) does typing, head glances, wandering and the launch cheer locally
	on Motor6D.Transform, only for rigs near the camera. Zero per-frame traffic.
	  tag "SVStaff"      -- every rig
	  attr "Wander"      -- Vector3 room bounds when the rig may wander
	  attr "Seated"      -- seated rigs do not wander
	  attr "CheerAt"     -- workspace:GetServerTimeNow() of the last launch cheer
]]
StaffRig.TAG = "SVStaff"
local PhysicsService = game:GetService("PhysicsService")

-- COLLISION GROUP, not per-part CanCollide. Roblox's Humanoid FORCES
-- UpperTorso and LowerTorso back to CanCollide=true on any R15 rig -- it is
-- engine behaviour, not something you can just set false and walk away from.
-- A collision group is the only way to guarantee staff can never body-block
-- the player, which is the bug he actually hit.
local STAFF_GROUP = "SVStaff"
do
	local ok = pcall(function() PhysicsService:RegisterCollisionGroup(STAFF_GROUP) end)
	-- already registered on a re-run is fine; just make sure the rule is set
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(STAFF_GROUP, "Default", false)
		PhysicsService:CollisionGroupSetCollidable(STAFF_GROUP, STAFF_GROUP, false)
	end)
end

-- animation ids from Roblox's default R15 set. These are public, free, and
-- require no upload -- they are what every default avatar already plays.
local ANIM = {
	idle = "rbxassetid://507766666",
	walk = "rbxassetid://507777826",
}

local SKIN = {
	Color3.fromRGB(234, 194, 158), Color3.fromRGB(205, 160, 120),
	Color3.fromRGB(160, 116, 80),  Color3.fromRGB(120, 84, 56),
	Color3.fromRGB(90, 62, 44),
}

local HAIR = {
	Color3.fromRGB(40, 32, 28), Color3.fromRGB(90, 60, 36),
	Color3.fromRGB(180, 140, 80), Color3.fromRGB(60, 44, 40),
	Color3.fromRGB(150, 60, 50),
}

-- ROLE COLOURS. The shirt tells you what someone does, at a glance, from across
-- the room. Information, never decoration -- same rule as everything else.
StaffRig.ROLES = {
	engineer = { name = "ENGINEER",    color = Color3.fromRGB(90, 170, 255) },
	designer = { name = "DESIGNER",    color = Color3.fromRGB(255, 150, 190) },
	sales    = { name = "SALES",       color = Color3.fromRGB(90, 210, 130) },
	recruiter= { name = "RECRUITER",   color = Color3.fromRGB(255, 208, 70) },
	research = { name = "RESEARCHER",  color = Color3.fromRGB(180, 140, 255) },
}

-- ============ HELPERS (above every caller) ============

local function limb(name, size, color, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false          -- staff must never block the player
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function joint(part0, part1, c0, c1, name)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1
	m.Parent = part0
	return m
end

local function nameTag(adornee, text, sub, color)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 190, 0, 44)
	bb.StudsOffset = Vector3.new(0, 1.9, 0)
	bb.AlwaysOnTop = false        -- noTop: it must not punch through walls
	-- v2.8: names show when you walk up to someone, not across the campus
	-- (six floating name+title stacks through the office glass read as clutter)
	-- v3.0.3: 14 -- at 24 a full cafe showed six overlapping name + title stacks
	bb.MaxDistance = 14
	bb.Name = "Tag"
	bb.Adornee = adornee
	bb.Parent = adornee

	local n = Instance.new("TextLabel")
	n.Size = UDim2.new(1, 0, 0.55, 0)
	n.BackgroundTransparency = 1
	n.Text = text
	n.TextColor3 = Color3.new(1, 1, 1)
	n.TextStrokeTransparency = 0.25
	n.TextSize = 16
	n.Font = Enum.Font.FredokaOne
	n.Parent = bb

	local r = Instance.new("TextLabel")
	r.Name = "Sub"
	r.Position = UDim2.new(0, 0, 0.52, 0)
	r.Size = UDim2.new(1, 0, 0.45, 0)
	r.BackgroundTransparency = 1
	r.Text = sub
	r.TextColor3 = color
	r.TextStrokeTransparency = 0.4
	r.TextSize = 12
	r.Font = Enum.Font.GothamMedium
	r.Parent = bb
	return bb
end

-- ============ THE RIG ============
-- R15 assembled by hand. Roblox exposes no server-side rig builder, so the
-- parts and Motor6Ds are made here and Humanoid drives them from there.

local FIRST = { "Ada", "Sam", "Kai", "Noor", "Ivan", "Mei", "Theo", "Priya",
	"Luca", "Rosa", "Omar", "Yuki", "Dana", "Cole", "Iris", "Milo" }

local function buildBlock(roleKey, index)
	local role = StaffRig.ROLES[roleKey] or StaffRig.ROLES.engineer
	local rng = Random.new(index * 7919)
	local skin = SKIN[rng:NextInteger(1, #SKIN)]
	local hair = HAIR[rng:NextInteger(1, #HAIR)]
	local personName = FIRST[((index - 1) % #FIRST) + 1]

	local m = Instance.new("Model")
	m.Name = "Staff_" .. personName

	-- torso is the root. HumanoidRootPart must exist and must be named exactly.
	local hrp = limb("HumanoidRootPart", Vector3.new(2, 2, 1), skin, m)
	hrp.Transparency = 1
	local torso = limb("UpperTorso", Vector3.new(2, 1.6, 1), role.color, m)
	local lower = limb("LowerTorso", Vector3.new(2, 0.8, 1), role.color, m)
	local head = limb("Head", Vector3.new(1.2, 1.2, 1.2), skin, m)
	head.Shape = Enum.PartType.Ball

	local hairP = limb("Hair", Vector3.new(1.3, 0.5, 1.3), hair, m)
	-- v3.0.3 ELBOWS AND KNEES. The old rig had one stiff block per limb, so a
	-- seated person's legs stuck straight out past the chair and nobody could
	-- hold a keyboard or a handlebar. Same overall length (arm 1.4, leg 1.6),
	-- now in two pieces: sleeve in the role colour, forearm in skin, trousers,
	-- shoes. Every joint is a Motor6D, so StaffAnimClient can pose it.
	local PANTS = Color3.fromRGB(52, 56, 66)
	local SHOE = Color3.fromRGB(30, 32, 38)
	local lArm = limb("LeftUpperArm", Vector3.new(0.62, 0.74, 0.62), role.color, m)
	local rArm = limb("RightUpperArm", Vector3.new(0.62, 0.74, 0.62), role.color, m)
	local lFore = limb("LeftLowerArm", Vector3.new(0.54, 0.72, 0.54), skin, m)
	local rFore = limb("RightLowerArm", Vector3.new(0.54, 0.72, 0.54), skin, m)
	local lLeg = limb("LeftUpperLeg", Vector3.new(0.72, 0.84, 0.72), PANTS, m)
	local rLeg = limb("RightUpperLeg", Vector3.new(0.72, 0.84, 0.72), PANTS, m)
	local lShin = limb("LeftLowerLeg", Vector3.new(0.64, 0.78, 0.64), PANTS, m)
	local rShin = limb("RightLowerLeg", Vector3.new(0.64, 0.78, 0.64), PANTS, m)
	for _, shin in ipairs({ lShin, rShin }) do
		local shoe = limb("Shoe", Vector3.new(0.68, 0.24, 0.92), SHOE, m)
		local sw = Instance.new("Weld")
		sw.Part0, sw.Part1 = shin, shoe
		sw.C0 = CFrame.new(0, -0.29, -0.12)
		sw.Parent = shin
	end

	-- eyes, so it reads as a person and not a mannequin
	for _, sx in ipairs({ -0.28, 0.28 }) do
		local e = limb("Eye", Vector3.new(0.16, 0.22, 0.1), Color3.fromRGB(24, 24, 30), m)
		e.Shape = Enum.PartType.Block
		local w = Instance.new("Weld")
		w.Part0 = head
		w.Part1 = e
		w.C0 = CFrame.new(sx, 0.08, -0.58)
		w.Parent = head
	end

	m.PrimaryPart = hrp

	-- joints. Motor6D, not Weld -- animations only drive Motor6Ds.
	joint(hrp, lower, CFrame.new(0, -0.6, 0), CFrame.new(), "Root")
	joint(lower, torso, CFrame.new(0, 1.2, 0), CFrame.new(), "Waist")
	joint(torso, head, CFrame.new(0, 1.4, 0), CFrame.new(), "Neck")
	joint(torso, lArm, CFrame.new(-1.31, 0.3, 0), CFrame.new(0, 0.33, 0), "LeftShoulder")
	joint(torso, rArm, CFrame.new(1.31, 0.3, 0), CFrame.new(0, 0.33, 0), "RightShoulder")
	joint(lArm, lFore, CFrame.new(0, -0.33, 0), CFrame.new(0, 0.34, 0), "LeftElbow")
	joint(rArm, rFore, CFrame.new(0, -0.33, 0), CFrame.new(0, 0.34, 0), "RightElbow")
	joint(lower, lLeg, CFrame.new(-0.5, -0.4, 0), CFrame.new(0, 0.4, 0), "LeftHip")
	joint(lower, rLeg, CFrame.new(0.5, -0.4, 0), CFrame.new(0, 0.4, 0), "RightHip")
	joint(lLeg, lShin, CFrame.new(0, -0.4, 0), CFrame.new(0, 0.4, 0), "LeftKnee")
	joint(rLeg, rShin, CFrame.new(0, -0.4, 0), CFrame.new(0, 0.4, 0), "RightKnee")

	local hw = Instance.new("Weld")
	hw.Part0 = head
	hw.Part1 = hairP
	hw.C0 = CFrame.new(0, 0.55, 0)
	hw.Parent = head

	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.WalkSpeed = 6
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.Parent = m

	-- THEY FELL THROUGH THE MAP. Every part is non-collidable (so they cannot
	-- body-block the player) and the SVStaff group does not collide with
	-- Default -- so gravity pulled the whole rig through the floor with
	-- nothing to stand on.
	--
	-- Fix: anchor ONLY the HumanoidRootPart. Motor6D-connected parts follow an
	-- anchored root, so the body still animates; anchoring every part instead
	-- would freeze the joints and kill the motion. They never need physics --
	-- they stand at desks and are moved with PivotTo.
	hrp.Anchored = true
	-- and stop the Humanoid state machine from fighting an anchored root
	pcall(function()
		hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		hum:ChangeState(Enum.HumanoidStateType.Physics)
	end)

	-- assign AFTER the Humanoid exists, because creating it flips the torsos
	-- back to collidable. The group makes that harmless.
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			pcall(function() d.CollisionGroup = STAFF_GROUP end)
			d.Massless = true
		end
	end

	nameTag(head, personName, role.name, role.color)
	CollectionService:AddTag(m, StaffRig.TAG)
	m:SetAttribute("Role", roleKey)
	m:SetAttribute("PersonName", personName)
	return m, hum
end

--[[ ============ v3.5 REAL AVATARS (PLAN v6 phase V2) ============
	The block rig above was the loudest "2019 Roblox" tell in every screenshot
	(art/today_vs_target.png). Staff are now real Roblox R15 avatars built from
	a HumanoidDescription: the default body, a free Roblox-made hair, a shirt
	and trousers painted once (art/clothing/*.png, uploaded) and TINTED per
	person with Clothing.Color3, so the role colour still tells you what
	someone does from across the room.

	Three things make them drop-in for every caller and every pose:
	  1. JOINTS. A 2026 avatar is built on AnimationConstraints. Each one is
	     turned into a Motor6D with the same attachment offsets (all identity
	     rotations, measured), parented to its Part0 -- the block rig's
	     convention -- so StaffAnimClient, setSeated and the carry pose find the
	     same joints by the same names, with the same sign conventions.
	  2. HEIGHT. The avatar's root sits 3.01 above its soles; the game places
	     people with feet 2.61 below the root (desks, candidates, the scooter).
	     The body is raised on the Root joint by the measured difference.
	  3. SEAT. Root-above-cushion is computed from THIS rig's hip and thigh and
	     stored as the ThighUnder attribute that sitOn reads.
	Templates are built once per hair at server start and cloned per hire, so
	a hire never waits on the catalog. If the catalog is unreachable the block
	rig above is still there.
]]
local AVATAR_HAIR = {                 -- free, Roblox-made, verified 27 Sep (economy API, price 0)
	62724852,    -- Chestnut Bun
	451220849,   -- Lavender Updo
	63690008,    -- Pal Hair
	62234425,    -- Brown Hair
	376548738,   -- Brown Charmer Hair
	1772336109,  -- Down to Earth Hair
	20573078,    -- Shaggy
	48474294,    -- ROBLOX Girl - Hair
}
local SHIRT_TEMPLATE = "rbxassetid://95943654717117"   -- art/clothing/shirt_template.png: near-white, tinted per person
local PANTS_TEMPLATE = "rbxassetid://88037629958570"   -- art/clothing/pants_template.png: shoes stay dark under any tint
local ROOT_TO_SOLE = 2.61                              -- what every caller already assumes
local TROUSERS = {
	Color3.fromRGB(58, 62, 74), Color3.fromRGB(70, 76, 92), Color3.fromRGB(150, 128, 96),
	Color3.fromRGB(96, 100, 110), Color3.fromRGB(44, 48, 60),
}
local STRIP = { Animate = true, HumanoidDescription = true, BodyColors = true }

local templates = {}          -- hair index -> prepared Model (in ServerStorage)
local prewarmDone = false

local function convertJoints(m)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("AnimationConstraint") and d.Attachment0 and d.Attachment1 then
			local a0, a1 = d.Attachment0, d.Attachment1
			local mo = Instance.new("Motor6D")
			mo.Name = d.Name
			mo.Part0, mo.Part1 = a0.Parent, a1.Parent
			mo.C0, mo.C1 = a0.CFrame, a1.CFrame
			mo.Parent = a0.Parent
		end
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("AnimationConstraint") or d:IsA("BallSocketConstraint") or d:IsA("NoCollisionConstraint")
			or d:IsA("WrapTarget") or (d:IsA("Vector3Value") and d.Name:find("Original"))
			or (d:IsA("Attachment") and d.Name:find("RigAttachment")) then   -- the Motor6Ds carry these offsets now
			d:Destroy()
		end
	end
end

-- An anchored NPC never rescales or self-collides, but the Humanoid adds its
-- scaling records (OriginalSize/OriginalPosition, 70 of them) and 19
-- self-collision constraints when the model enters the world. Measured: 196
-- instances per avatar; ~35k on a full server of 180 staff, all replicated on
-- join. Stripped once the rig is placed.
local function stripLive(m)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("NoCollisionConstraint") or (d:IsA("Vector3Value") and d.Name:find("Original")) then d:Destroy() end
	end
end

local function prepareTemplate(hairId)
	local desc = Instance.new("HumanoidDescription")
	desc.HairAccessory = tostring(hairId)
	local ok, m = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not m then
		warn("[StaffRig] avatar template failed for hair " .. hairId .. ": " .. tostring(m))
		return nil
	end
	local hrp = m:FindFirstChild("HumanoidRootPart")
	if not hrp then m:Destroy() return nil end
	for _, c in ipairs(m:GetChildren()) do if STRIP[c.Name] or STRIP[c.ClassName] then c:Destroy() end end
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum then
		pcall(function() hum.AutomaticScalingEnabled = false end)
		for _, c in ipairs(hum:GetChildren()) do
			if STRIP[c.ClassName] or c:IsA("NumberValue") then c:Destroy() end   -- the body scale values: default scale, never rescaled
		end
	end
	convertJoints(m)
	local root = hrp:FindFirstChild("Root")
	if not root then m:Destroy() return nil end
	-- root-to-sole from the JOINT CHAIN, not from part positions: the freshly
	-- built constraint rig is not settled (its parts read 3.01, the joints put
	-- the sole at 3.19; measuring the parts left every standing person 0.19
	-- studs inside the floor)
	local rts = 3.0
	do
		local lower, ul, ll, foot = m:FindFirstChild("LowerTorso"), m:FindFirstChild("LeftUpperLeg"), m:FindFirstChild("LeftLowerLeg"), m:FindFirstChild("LeftFoot")
		local hip = lower and lower:FindFirstChild("LeftHip")
		local knee = ul and ul:FindFirstChild("LeftKnee")
		local ankle = ll and ll:FindFirstChild("LeftAnkle")
		if hip and knee and ankle and foot then
			local cf = root.C0 * root.C1:Inverse() * hip.C0 * hip.C1:Inverse() * knee.C0 * knee.C1:Inverse() * ankle.C0 * ankle.C1:Inverse()
			rts = -(cf.Position.Y - foot.Size.Y / 2)
		end
	end
	m:SetAttribute("RawRootToSole", rts)
	root.C0 = CFrame.new(0, rts - ROOT_TO_SOLE, 0) * root.C0
	-- seat geometry from this rig: hip height under the root, plus half the thigh's depth
	local lower = m:FindFirstChild("LowerTorso")
	local hip = lower and lower:FindFirstChild("LeftHip")
	local thigh = m:FindFirstChild("LeftUpperLeg")
	if hip and thigh then
		local hipY = (root.C0.Position.Y - root.C1.Position.Y) + hip.C0.Position.Y
		m:SetAttribute("ThighUnder", -hipY + thigh.Size.Z / 2)
	end
	m:SetAttribute("Avatar", true)
	m.PrimaryPart = hrp
	m.Name = "AvatarTemplate"
	return m
end

task.spawn(function()
	local store = Instance.new("Folder")
	store.Name = "SVAvatarTemplates"
	store.Parent = game:GetService("ServerStorage")
	for i, id in ipairs(AVATAR_HAIR) do
		local m = prepareTemplate(id)
		if m then
			m.Parent = store
			templates[i] = m
		end
	end
	prewarmDone = true
	local n = 0
	for _ in pairs(templates) do n += 1 end
	print(("[StaffRig] %d/%d avatar templates ready"):format(n, #AVATAR_HAIR))
end)

local function templateFor(hairIndex)
	-- only the first hires after a server starts can arrive before the prewarm
	local deadline = os.clock() + 12
	while not prewarmDone and not templates[hairIndex] and os.clock() < deadline do task.wait(0.1) end
	if templates[hairIndex] then return templates[hairIndex] end
	for _, t in pairs(templates) do return t end
	return nil
end

local function buildAvatar(tpl, roleKey, index)
	local role = StaffRig.ROLES[roleKey] or StaffRig.ROLES.engineer
	local rng = Random.new(index * 7919)
	local skin = SKIN[rng:NextInteger(1, #SKIN)]
	rng:NextInteger(1, #AVATAR_HAIR)               -- the hair draw (the template already wears it)
	local trousers = TROUSERS[rng:NextInteger(1, #TROUSERS)]
	local personName = FIRST[((index - 1) % #FIRST) + 1]

	local m = tpl:Clone()
	m.Name = "Staff_" .. personName
	for _, p in ipairs(m:GetChildren()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then p.Color = skin end
	end
	local shirt = Instance.new("Shirt")
	shirt.ShirtTemplate = SHIRT_TEMPLATE
	shirt.Color3 = role.color
	shirt.Parent = m
	local pants = Instance.new("Pants")
	pants.PantsTemplate = PANTS_TEMPLATE
	pants.Color3 = trousers
	pants.Parent = m

	local hrp = m:FindFirstChild("HumanoidRootPart")
	hrp.Transparency = 1
	hrp.Anchored = true                            -- same reason as the block rig: see "THEY FELL THROUGH THE MAP"
	local hum = m:FindFirstChildOfClass("Humanoid")
	hum.WalkSpeed = 6
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	pcall(function()
		hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		hum:ChangeState(Enum.HumanoidStateType.Physics)
	end)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CastShadow = false
			d.Massless = true
			pcall(function() d.CollisionGroup = STAFF_GROUP end)
		end
	end
	local head = m:FindFirstChild("Head")
	local tag = nameTag(head, personName, role.name, role.color)
	tag.StudsOffset = Vector3.new(0, 2.5, 0)       -- avatars wear hair: the tag floats clear of it (1.9 suited the bald block rig)
	CollectionService:AddTag(m, StaffRig.TAG)
	m:SetAttribute("Role", roleKey)
	m:SetAttribute("PersonName", personName)
	local conn
	conn = m.AncestryChanged:Connect(function()
		if m:IsDescendantOf(workspace) then
			conn:Disconnect()
			task.defer(stripLive, m)
		end
	end)
	return m, hum
end

function StaffRig.build(roleKey, index)
	local rng = Random.new(index * 7919)
	rng:NextInteger(1, #SKIN)
	local hairIndex = rng:NextInteger(1, #AVATAR_HAIR)
	local tpl = templateFor(hairIndex)
	if tpl then
		local ok, m, hum = pcall(buildAvatar, tpl, roleKey, index)
		if ok and m then return m, hum end
		warn("[StaffRig] avatar build failed, block rig instead: " .. tostring(m))
	end
	return buildBlock(roleKey, index)
end

-- the outfit colours: shirt and trousers on an avatar, the torso parts on a block rig
function StaffRig.setOutfit(model, shirtColor, pantsColor)
	local shirt, pants = model:FindFirstChildOfClass("Shirt"), model:FindFirstChildOfClass("Pants")
	if shirt and shirtColor then shirt.Color3 = shirtColor end
	if pants and pantsColor then pants.Color3 = pantsColor end
	if not shirt and shirtColor then
		for _, n in ipairs({ "UpperTorso", "LowerTorso" }) do
			local p = model:FindFirstChild(n)
			if p then p.Color = shirtColor end
		end
	end
end

-- ============ LIFE ============
-- Idle breathing + a typing bob + occasional wandering. All Lua-driven, so it
-- works whether or not the default animation set loads.

-- ============ PERSONHOOD ============
-- His note: "the employees have to be more lively, like they are another
-- person." Three things do that without any upload: a TITLE that changes as
-- they grow, SPEECH now and then, and a reaction when the company wins.

-- v2.5 TALENT: shirt takes the talent colour; Star+ gets a Neon halo ring
-- above the head so a rare hire reads from across the campus.
function StaffRig.setTalent(model, talent, color, label)
	local head = model:FindFirstChild("Head")
	StaffRig.setOutfit(model, color, nil)
	model:SetAttribute("Talent", talent)
	model:SetAttribute("TalentName", label)
	if head and talent >= 3 and not head:FindFirstChild("Halo") then
		local halo = Instance.new("Part")
		halo.Name = "Halo"
		halo.Shape = Enum.PartType.Cylinder
		halo.Size = Vector3.new(0.12, 1.5, 1.5)
		halo.Color = color
		halo.Material = Enum.Material.Neon
		halo.CanCollide = false
		halo.CanQuery = false
		halo.CastShadow = false
		halo.Massless = true
		halo.Parent = head
		local w = Instance.new("Weld")
		w.Part0 = head
		w.Part1 = halo
		-- v3.5: avatars wear hair, so the halo floats clear of it
		w.C0 = CFrame.new(0, model:GetAttribute("Avatar") and 1.55 or 1.05, 0) * CFrame.Angles(0, 0, math.rad(90))
		w.Parent = halo
		-- v3.0: recruiting makes Star+ common (~12 a run), so only Genius+ carry a
		-- light; ~72 PointLights on a full server would blow the lighting budget
		if talent >= 4 then
			local light = Instance.new("PointLight")
			light.Color = color
			light.Brightness = talent >= 5 and 1.2 or 0.5
			light.Range = 8
			light.Parent = halo
		end
	end
	-- v3.0: a rare hire is labelled from across the room, in its talent colour
	-- (Steal An Egg labels every pet with its rarity); commons stay close-range
	local tag = head and head:FindFirstChild("Tag")
	if tag and talent >= 3 then
		tag.MaxDistance = 70
		for _, l in ipairs(tag:GetChildren()) do
			if l:IsA("TextLabel") and l.Name ~= "Sub" then
				l.TextColor3 = color
				if label and not string.find(l.Text, "·", 1, true) then l.Text = l.Text .. "  ·  " .. string.upper(label) end
			end
		end
	end
end

-- the second line of the name tag: "Senior Engineer"
function StaffRig.setTitle(model, title)
	local head = model:FindFirstChild("Head")
	local tag = head and head:FindFirstChild("Tag")
	local sub = tag and tag:FindFirstChild("Sub")
	if sub then sub.Text = title end
end

-- a speech bubble above the head for a few seconds
function StaffRig.say(model, text, seconds)
	local head = model:FindFirstChild("Head")
	if not head then return end
	local old = head:FindFirstChild("Bubble")
	if old then old:Destroy() end
	local bb = Instance.new("BillboardGui")
	bb.Name = "Bubble"
	bb.Size = UDim2.new(0, 220, 0, 40)
	bb.StudsOffset = Vector3.new(0, model:GetAttribute("Avatar") and 3.9 or 3.4, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 60
	bb.Parent = head
	local f = Instance.new("TextLabel")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.new(0.5, 0, 0.5, 0)
	f.AutomaticSize = Enum.AutomaticSize.X
	f.Size = UDim2.new(0, 0, 0, 32)
	f.BackgroundColor3 = Color3.fromRGB(244, 246, 250)
	f.Text = "  " .. text .. "  "
	f.TextColor3 = Color3.fromRGB(28, 32, 40)
	f.TextSize = 14
	f.Font = Enum.Font.GothamMedium
	f.Parent = bb
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 10)
	-- one label at a time: the bubble sits 1.5 studs above the name tag, so
	-- from a few metres away the two stacked into "RosaYahhhGENI". The tag
	-- hides while they talk; only the bubble still showing puts it back.
	local tag = head:FindFirstChild("Tag")
	if tag then tag.Enabled = false end
	task.delay(seconds or 3.2, function()
		if bb.Parent then
			bb:Destroy()
			if tag and tag.Parent then tag.Enabled = true end
		end
	end)
end

-- arms up, a little hop: the whole room reacts to a launch. v2.8.1: one
-- attribute write; StaffAnimClient plays it (was 42 replicated writes per rig)
function StaffRig.cheer(model)
	if model and model.Parent then model:SetAttribute("CheerAt", workspace:GetServerTimeNow()) end
end

-- home positions are read LIVE so a hire can be moved to a newly placed desk
-- without restarting its animation loops
StaffRig.homes = {}
StaffRig.seated = {}
local SEAT_DROP = 0.75          -- fallback only: root drop when no chair is found near the seat
local THIGH_UNDER = 1.36        -- root height above the cushion: hip 1.0 below the root + half a thigh
local jointBase = setmetatable({}, { __mode = "k" })

--[[
	v3.0.3 SITTING, MEASURED. His report: "the employees' rigged parts are not
	even sitting on the chair." Measured 24 Sep: thighs 0.6 studs INSIDE the
	cushion (seat top y 2.37, thigh bottom 1.50), the office chair turned 165
	degrees away from the person, and legs with no knees sticking out past it.
	Now: thighs forward, knees bent, shins down, and the body is set from the
	REAL chair -- its seat height and which side its backrest is on are read
	off the mesh with raycasts once, then the chair is turned to face the desk
	and the pelvis is placed on the cushion.
]]
function StaffRig.setSeated(model, on)
	local lower = model:FindFirstChild("LowerTorso")
	local lLeg, rLeg = model:FindFirstChild("LeftUpperLeg"), model:FindFirstChild("RightUpperLeg")
	local j = {
		lower and lower:FindFirstChild("LeftHip"), lower and lower:FindFirstChild("RightHip"),
		lLeg and lLeg:FindFirstChild("LeftKnee"), rLeg and rLeg:FindFirstChild("RightKnee"),
	}
	if not (j[1] and j[2]) then return end
	if not jointBase[model] then jointBase[model] = { j[1].C0, j[2].C0, j[3] and j[3].C0, j[4] and j[4].C0 } end
	local b = jointBase[model]
	if on then
		-- +90 about X swings a thigh from hanging (-Y) to forward (-Z); -90 at the knee drops the shin
		j[1].C0 = b[1] * CFrame.Angles(math.rad(90), 0, 0)
		j[2].C0 = b[2] * CFrame.Angles(math.rad(90), 0, 0)
		if j[3] then j[3].C0 = b[3] * CFrame.Angles(math.rad(-90), 0, 0) end
		if j[4] then j[4].C0 = b[4] * CFrame.Angles(math.rad(-90), 0, 0) end
	else
		for k = 1, 4 do if j[k] and b[k] then j[k].C0 = b[k] end end
	end
	StaffRig.seated[model] = on and true or nil
	model:SetAttribute("Seated", on and true or false)   -- StaffAnimClient: seated rigs do not wander
end

-- read a chair's seat off its mesh: seat centre + cushion height and the
-- direction its front faces, both in the chair's own pivot space. Cached on the
-- chair as attributes, so each chair is probed once in its life.
local function chairInfo(chair)
	local seatL, frontL = chair:GetAttribute("SeatLocal"), chair:GetAttribute("FrontLocal")
	if typeof(seatL) == "Vector3" and typeof(frontL) == "Vector3" then return seatL, frontL end
	local parts = {}
	for _, d in ipairs(chair:IsA("BasePart") and { chair } or chair:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(parts, d) end
	end
	if #parts == 0 then return nil end
	local was = {}
	for i, d in ipairs(parts) do was[i] = d.CanQuery; d.CanQuery = true end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = parts
	local pivot = chair:GetPivot()
	local bcf, bsz
	if chair:IsA("Model") then bcf, bsz = chair:GetBoundingBox() else bcf, bsz = chair.CFrame, chair.Size end
	local hits = {}
	local N = 7
	for gx = 0, N - 1 do
		for gz = 0, N - 1 do
			local lx = (gx / (N - 1) - 0.5) * bsz.X * 0.92
			local lz = (gz / (N - 1) - 0.5) * bsz.Z * 0.92
			local top = bcf * Vector3.new(lx, bsz.Y / 2 + 1, lz)
			local h = workspace:Raycast(top, Vector3.new(0, -(bsz.Y + 2), 0), params)
			if h then table.insert(hits, pivot:PointToObjectSpace(h.Position)) end
		end
	end
	for i, d in ipairs(parts) do d.CanQuery = was[i] end
	if #hits < 4 then return nil end
	-- the cushion is the lowest broad surface the rays land on; the backrest is what stands above it
	local ys = {}
	for _, h in ipairs(hits) do table.insert(ys, h.Y) end
	table.sort(ys)
	local seatY = ys[math.max(1, math.floor(#ys * 0.2))]
	local sx, sz, n, bx, bz, nb = 0, 0, 0, 0, 0, 0
	for _, h in ipairs(hits) do
		if h.Y <= seatY + 0.25 then sx += h.X; sz += h.Z; n += 1
		elseif h.Y >= seatY + 0.6 then bx += h.X; bz += h.Z; nb += 1 end
	end
	if n == 0 then return nil end
	sx, sz = sx / n, sz / n
	local front = Vector3.new(0, 0, -1)
	if nb > 0 then
		local back = Vector3.new(bx / nb - sx, 0, bz / nb - sz)
		if back.Magnitude > 0.05 then front = -back.Unit end
	end
	seatL, frontL = Vector3.new(sx, seatY, sz), front
	chair:SetAttribute("SeatLocal", seatL)
	chair:SetAttribute("FrontLocal", frontL)
	return seatL, frontL
end

-- the chair nearest a seat point (chairs are tagged by FurnitureKit)
local function chairNear(pos, within)
	local best, bestD
	for _, c in ipairs(CollectionService:GetTagged("SVChair")) do
		if c.Parent and c:IsDescendantOf(workspace) then
			local p = c:GetPivot().Position
			local d = Vector3.new(p.X - pos.X, 0, p.Z - pos.Z).Magnitude
			-- v4.0: same storey only (the HQ has floors above the lobby now)
			if d <= within and math.abs(p.Y - pos.Y) < 5 and (not bestD or d < bestD) then best, bestD = c, d end
		end
	end
	return best
end

-- turn and slide the chair so it faces the way the person faces with its seat
-- under their pelvis, and return where the root goes to sit on it
local function sitOn(model, homeCFrame)
	local chair = chairNear(homeCFrame.Position, 3.4)
	if not chair then return nil end
	local seatL, frontL = chairInfo(chair)
	if not seatL then return nil end
	local look = homeCFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.01 then return nil end
	look = look.Unit
	local aW = math.atan2(-look.X, -look.Z)
	local aL = math.atan2(-frontL.X, -frontL.Z)
	local pivot = chair:GetPivot()
	local rot = CFrame.Angles(0, aW - aL, 0)
	local off = rot * Vector3.new(seatL.X, 0, seatL.Z)
	-- the pelvis sits a little back from the cushion centre, toward the backrest
	local at = homeCFrame.Position - look * 0.15
	chair:PivotTo(CFrame.new(at.X - off.X, pivot.Position.Y, at.Z - off.Z) * rot)
	local seatTop = chair:GetPivot().Position.Y + seatL.Y
	local under = model:GetAttribute("ThighUnder") or THIGH_UNDER
	return CFrame.new(at.X, seatTop + under, at.Z) * (homeCFrame - homeCFrame.Position)
end

local function homeFor(model, homeCFrame)
	if not StaffRig.seated[model] then return homeCFrame end
	local ok, cf = pcall(sitOn, model, homeCFrame)
	if ok and cf then return cf end
	return homeCFrame * CFrame.new(0, -SEAT_DROP, 0)
end

function StaffRig.rehome(model, homeCFrame)
	StaffRig.homes[model] = homeCFrame
	if model.Parent then model:PivotTo(homeFor(model, homeCFrame)) end
end

function StaffRig.animate(model, hum, homeCFrame, roomBounds)
	StaffRig.homes[model] = homeCFrame
	local torso = model:FindFirstChild("UpperTorso")
	local lArm = model:FindFirstChild("LeftUpperArm")
	local rArm = model:FindFirstChild("RightUpperArm")
	local head = model:FindFirstChild("Head")
	if not (torso and lArm and rArm and head) then return end

	local lShoulder = torso:FindFirstChild("LeftShoulder")
	local rShoulder = torso:FindFirstChild("RightShoulder")
	local neck = torso:FindFirstChild("Neck")
	if not (lShoulder and rShoulder and neck) then return end

	-- try the real animation set (breathing); the typing/glance motion is client-side
	pcall(function()
		local animator = hum:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = hum
		end
		local a = Instance.new("Animation")
		a.AnimationId = ANIM.idle
		local track = animator:LoadAnimation(a)
		track.Looped = true
		track:Play()
	end)

	-- v2.8.1: typing, head glances and wandering are drawn by StaffAnimClient
	-- on each player's machine (Motor6D.Transform, near the camera only). The
	-- server publishes only whether this rig may wander.
	if roomBounds then model:SetAttribute("Wander", roomBounds) end
end

return StaffRig
