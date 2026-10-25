--[[
	BobBuilding -- ModuleScript in ServerScriptService. P-5, Bob the first boss investor (25 Oct 2026).

	Spec: docs/superpowers/specs/2026-10-25-bob-first-boss-investor-design.md (3b, 3c, 3f).

	  BOB CAPITAL   a real building next door to The Residences (every player drives there
	                for the HQ 2 task, so everyone passes it early). Its door is taped shut
	                for the whole server; the player who beat Bob sees it open on their own
	                client only (BobDoorClient). Inside is the boardroom both cutscenes use.
	  BobCast       ReplicatedStorage templates the client clones for the cutscenes: Bob
	                (suit, belly, sunglasses, a GOLD TOOTHPICK, never tobacco), two investors,
	                and the REVENUE chart board.
	  trophy(plot)  BOB'S TOOTHPICK on a stand, for a save that beat him (everyone sees it).

	Anchors (attributes on the model, CFrames; BobScript's coordinates are relative to them):
	  AnchorBoard   the middle of the boardroom floor, -Z into the room (the camera side is +Z)
	  AnchorDoor    on the sidewalk at the front door, -Z into the building
	  AnchorStreet  a clear stretch of pavement beside it, -Z away from the road
]]

local CollectionService = game:GetService("CollectionService")
local RS = game:GetService("ReplicatedStorage")

local BobBuilding = {}

local Pal = require(RS:WaitForChild("PaletteLoad"))
local LINES = require(RS:WaitForChild("BobScript")).LINES

-- the building's frame: beside The Residences, front (+Z) facing the park like it (Downtown.RES)
BobBuilding.SIZE = { w = 30, d = 24, h = 30, room = 12 }
function BobBuilding.site()
	local Downtown = require(script.Parent:WaitForChild("Downtown"))
	return Downtown.RES * CFrame.new(65, 0, 4)   -- east of it: the kick throws you away from The Residences, not into it
end

local CHARCOAL = Color3.fromRGB(38, 41, 48)
local NAVY = Color3.fromRGB(38, 66, 108)
local STONE = Color3.fromRGB(196, 186, 170)
local GLASS = Color3.fromRGB(132, 172, 190)
local GOLD = Color3.fromRGB(224, 182, 90)
local OAK = Color3.fromRGB(192, 138, 85)
local DOORWOOD = Color3.fromRGB(110, 74, 48)
local TAPE = Color3.fromRGB(255, 200, 61)
local PAPER = Color3.fromRGB(243, 239, 230)
local RED = Color3.fromRGB(198, 72, 62)

local function part(parent, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.CastShadow = false
	for k, v in pairs(props) do p[k] = v end
	if Pal then Pal.author(p, props) end
	p.Parent = parent
	return p
end

local function label(p, face, text, color, size)
	local g = Instance.new("SurfaceGui")
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.FredokaOne
	t.Text = text
	t.TextColor3 = color
	t.TextScaled = true
	if size then
		local c = Instance.new("UITextSizeConstraint")
		c.MaxTextSize = size
		c.Parent = t
	end
	t.Parent = g
	g.Parent = p
	return g
end

-- ------------------------------------------------------------------ the building
function BobBuilding.build(world)
	local old = world:FindFirstChild("BobCapital")
	if old then old:Destroy() end
	local S = BobBuilding.SIZE
	local site = BobBuilding.site()
	local m = Instance.new("Model")
	m.Name = "BobCapital"
	local function at(x, y, z) return site * CFrame.new(x, y, z) end
	local W, D, H = S.w, S.d, S.h
	local front = D / 2

	-- the shell: back and side walls solid; the front wall is three pieces round the door
	part(m, { Name = "Floor", Size = Vector3.new(W, 0.4, D), CFrame = at(0, 0.2, 0), Color = OAK, Material = Enum.Material.WoodPlanks })
	part(m, { Name = "BackWall", Size = Vector3.new(W, H, 1), CFrame = at(0, H / 2, -front + 0.5), Color = NAVY })
	part(m, { Name = "SideL", Size = Vector3.new(1, H, D), CFrame = at(-W / 2 + 0.5, H / 2, 0), Color = NAVY })
	part(m, { Name = "SideR", Size = Vector3.new(1, H, D), CFrame = at(W / 2 - 0.5, H / 2, 0), Color = NAVY })
	part(m, { Name = "Roof", Size = Vector3.new(W, 1, D), CFrame = at(0, H + 0.5, 0), Color = CHARCOAL })
	local ceiling = part(m, { Name = "RoomCeiling", Size = Vector3.new(W - 2, 0.4, D - 2), CFrame = at(0, S.room, 0), Color = CHARCOAL })
	local doorX, doorW, doorH = 9, 4, 8
	local fw = Instance.new("Model")
	fw.Name = "FrontWall"   -- the client hides this during the boardroom shots (a cutaway)
	fw.Parent = m
	local leftW = (doorX - doorW / 2) - (-W / 2)
	part(fw, { Name = "FrontL", Size = Vector3.new(leftW, H, 1), CFrame = at(-W / 2 + leftW / 2, H / 2, front - 0.5), Color = NAVY })
	local rightW = W / 2 - (doorX + doorW / 2)
	part(fw, { Name = "FrontR", Size = Vector3.new(rightW, H, 1), CFrame = at(W / 2 - rightW / 2, H / 2, front - 0.5), Color = NAVY })
	part(fw, { Name = "Lintel", Size = Vector3.new(doorW, H - doorH, 1), CFrame = at(doorX, doorH + (H - doorH) / 2, front - 0.5), Color = NAVY })
	-- glass bands on the facade (outside only)
	for i = 0, 2 do
		part(fw, { Name = "Band", Size = Vector3.new(W - 14, 3, 0.2), CFrame = at(-4, 11 + i * 6.5, front + 0.05), Color = GLASS,
			Material = Enum.Material.Glass, Transparency = 0.2, CanCollide = false, CanQuery = false })
	end
	local sign = part(m, { Name = "Sign", Size = Vector3.new(12, 2.2, 0.3), CFrame = at(doorX - 3, doorH + 1.6, front + 0.2), Color = GOLD, CanCollide = false })
	label(sign, Enum.NormalId.Front, "BOB CAPITAL", CHARCOAL)

	-- the door (server: always shut) and the tape across it
	local door = part(m, { Name = "Door", Size = Vector3.new(doorW, doorH, 0.4), CFrame = at(doorX, doorH / 2 + 0.4, front - 0.5), Color = DOORWOOD })
	part(m, { Name = "Knob", Shape = Enum.PartType.Ball, Size = Vector3.new(0.4, 0.4, 0.4), CFrame = at(doorX - 1.4, 4, front - 0.2), Color = GOLD, CanCollide = false })
	local tape = Instance.new("Model")
	tape.Name = "Tape"
	tape.Parent = m
	for _, a in ipairs({ 1, -1 }) do
		part(tape, { Name = "Strip", Size = Vector3.new(0.6, doorH + 1.2, 0.1), CFrame = at(doorX, doorH / 2 + 0.4, front + 0.05) * CFrame.Angles(0, 0, math.rad(32 * a)),
			Color = TAPE, CanCollide = false, CanQuery = false })
	end
	part(m, { Name = "Trigger", Size = Vector3.new(doorW + 2, 7, 4), CFrame = at(doorX, 3.5, front + 2), Transparency = 1,
		CanCollide = false, CanQuery = false, CanTouch = true })

	-- the boardroom (both cutscenes): a long table, chairs, a window, a plant, the name inside
	part(m, { Name = "Table", Size = Vector3.new(16, 0.6, 3.4), CFrame = at(-4, 3, -3), Color = OAK })
	for _, x in ipairs({ -10.5, 2.5 }) do part(m, { Name = "TableLeg", Size = Vector3.new(0.6, 2.7, 2.6), CFrame = at(x, 1.65, -3), Color = DOORWOOD }) end
	for _, x in ipairs({ -12, -7, -2.5 }) do part(m, { Name = "Chair", Size = Vector3.new(2, 4, 0.5), CFrame = at(x, 2.4, -5.6), Color = CHARCOAL }) end
	part(m, { Name = "Window", Size = Vector3.new(20, 6, 0.2), CFrame = at(-2, 7, -front + 1.1), Color = GLASS, Material = Enum.Material.Neon, Transparency = 0.25, CanCollide = false })
	-- live 25 Oct: a closed room is black without its own light (both cutscenes play in here).
	-- The lights hang off the ceiling part (a flat lamp part read as a sinking surface to the doctor)
	for _, x in ipairs({ -8, 4 }) do
		local a = Instance.new("Attachment")
		a.Name = "Lamp"
		a.Parent = ceiling
		a.WorldCFrame = at(x, S.room - 0.6, 0)
		local light = Instance.new("PointLight")
		light.Range = 22
		light.Brightness = 1.6
		light.Color = Color3.fromRGB(255, 236, 210)
		light.Shadows = false
		light.Parent = a
	end
	local inner = part(m, { Name = "InnerSign", Size = Vector3.new(10, 1.4, 0.2), CFrame = at(-2, 10.8, -front + 1.1), Color = NAVY, CanCollide = false })
	label(inner, Enum.NormalId.Front, "BOB CAPITAL", GOLD)
	part(m, { Name = "Plant", Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3), CFrame = at(-13, 3.6, -9), Color = Color3.fromRGB(78, 168, 92), CanCollide = false })
	part(m, { Name = "Pot", Size = Vector3.new(2, 2, 2), CFrame = at(-13, 1.4, -9), Color = STONE })

	-- anchors (BobScript's coordinate frames) + where the winner sees Bob sit dizzy
	m:SetAttribute("AnchorBoard", at(0, 0.4, 0))
	m:SetAttribute("AnchorDoor", at(doorX, 0.4, front))
	m:SetAttribute("AnchorStreet", at(doorX + 36, 0.4, front + 14))
	-- where the winner sees Bob sit dizzy (BobDoorClient); facing the street (+Z)
	m:SetAttribute("AnchorCurb", at(doorX + 6, 0.4, front + 4))

	m.PrimaryPart = door
	m.Parent = world
	BobBuilding.model = m
	BobBuilding.buildCast()
	return m
end

-- ------------------------------------------------------------------ the cast
local function weldTo(base, p)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = base, p
	w.Parent = p
	p.Anchored = false
	p.CanCollide = false
	p.Massless = true
	p.Parent = base.Parent
end

local function faceGui(head)
	local g = Instance.new("SurfaceGui")
	g.Name = "Face"
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 100
	g.LightInfluence = 0.5
	g.Parent = head
	return g
end

local function castMember(name, index, shirt, pants)
	local StaffRig = require(script.Parent:WaitForChild("StaffRig"))
	local m = StaffRig.build("eng", index)
	m.Name = name
	StaffRig.setOutfit(m, shirt, pants)
	CollectionService:RemoveTag(m, StaffRig.TAG)   -- not staff: never counted, never tagged
	local head = m:FindFirstChild("Head")
	if head then
		local tag = head:FindFirstChild("Tag")
		if tag then tag:Destroy() end
		faceGui(head)
	end
	return m, head
end

function BobBuilding.buildCast()
	local old = RS:FindFirstChild("BobCast")
	if old then old:Destroy() end
	local f = Instance.new("Folder")
	f.Name = "BobCast"
	-- Bob: a dark suit, a red tie, a belly, slicked hair, black sunglasses and a GOLD TOOTHPICK
	local bob, head = castMember("Bob", 7001, CHARCOAL, CHARCOAL)
	for _, a in ipairs(bob:GetChildren()) do if a:IsA("Accessory") then a:Destroy() end end
	local torso = bob:FindFirstChild("UpperTorso")
	if torso then
		local belly = part(bob, { Name = "Belly", Shape = Enum.PartType.Ball, Size = Vector3.new(3.4, 3, 2.6), CFrame = torso.CFrame * CFrame.new(0, -0.5, -0.5), Color = CHARCOAL })
		weldTo(torso, belly)
		local tie = part(bob, { Name = "Tie", Size = Vector3.new(0.45, 1.5, 0.1), CFrame = torso.CFrame * CFrame.new(0, 0, -1.82), Color = RED })
		weldTo(torso, tie)
	end
	if head then
		local hs = head.Size
		local hair = part(bob, { Name = "Hair", Size = Vector3.new(hs.X * 1.02, 0.35, hs.Z * 1.02), CFrame = head.CFrame * CFrame.new(0, hs.Y / 2, 0), Color = Color3.fromRGB(59, 42, 30) })
		weldTo(head, hair)
		local glasses = part(bob, { Name = "Sunglasses", Size = Vector3.new(hs.X * 0.9, 0.3, 0.12), CFrame = head.CFrame * CFrame.new(0, hs.Y * 0.08, -hs.Z / 2 - 0.05), Color = Color3.fromRGB(17, 17, 17) })
		weldTo(head, glasses)
		local pick = part(bob, { Name = "Toothpick", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 0.08, 0.08),
			CFrame = head.CFrame * CFrame.new(hs.X * 0.28, -hs.Y * 0.28, -hs.Z / 2 - 0.15) * CFrame.Angles(0, math.rad(20), math.rad(18)),
			Color = GOLD, Material = Enum.Material.Metal })
		weldTo(head, pick)
	end
	bob.Parent = f
	local function noHats(m)
		for _, a in ipairs(m:GetChildren()) do
			if a:IsA("Accessory") and a.AccessoryType ~= Enum.AccessoryType.Hair then a:Destroy() end
		end
	end
	local inv1 = castMember("Inv1", 7002, Color3.fromRGB(74, 80, 104), Color3.fromRGB(47, 51, 66))
	noHats(inv1)
	inv1.Parent = f
	local inv2 = castMember("Inv2", 7003, Color3.fromRGB(94, 74, 110), Color3.fromRGB(47, 51, 66))
	noHats(inv2)
	inv2.Parent = f
	-- the REVENUE chart the player holds up in the payoff (the client draws the line)
	local chart = part(f, { Name = "Chart", Size = Vector3.new(5, 3.6, 0.2), CFrame = CFrame.new(), Color = PAPER, CanCollide = false })
	local g = Instance.new("SurfaceGui")
	g.Name = "ChartGui"
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 60
	g.LightInfluence = 0
	g.Parent = chart
	for _, d in ipairs(f:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end
	f.Parent = RS
	return f
end

-- ------------------------------------------------------------------ the trophy
-- BOB'S TOOTHPICK: a gold toothpick on a little stand, for a save that beat him. Everyone sees it.
function BobBuilding.trophy(parent, cf)
	local m = Instance.new("Model")
	m.Name = "BobTrophy"
	local base = part(m, { Name = "Stand", Size = Vector3.new(1.6, 3, 1.6), CFrame = cf * CFrame.new(0, 1.5, 0), Color = CHARCOAL })
	part(m, { Name = "Top", Size = Vector3.new(2, 0.2, 2), CFrame = cf * CFrame.new(0, 3.1, 0), Color = GOLD, Material = Enum.Material.Metal })
	part(m, { Name = "Toothpick", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 0.14, 0.14),
		CFrame = cf * CFrame.new(0, 3.5, 0) * CFrame.Angles(0, 0, math.rad(25)), Color = GOLD, Material = Enum.Material.Metal, CanCollide = false })
	local plate = part(m, { Name = "Plate", Size = Vector3.new(1.5, 0.5, 0.05), CFrame = cf * CFrame.new(0, 2.4, -0.83), Color = GOLD, CanCollide = false })
	label(plate, Enum.NormalId.Front, LINES.trophy, CHARCOAL)
	m.PrimaryPart = base
	m.Parent = parent
	return m
end

return BobBuilding
