--[[
	CampusArch (v2.8) -- the company HQ look.

	His verdict on v2.7: "a garage style layout as the open office and
	cafeteria just looks visually terrible, it should represent the actual HQ
	of a company. Not mundane buildings with text above it."

	What changed, and why:
	- Rooms were beige boxes with a neon fascia and a floating name. They are
	  now glass PAVILIONS in one architectural language: concrete plinth,
	  floor-to-ceiling glass on three sides with slim dark mullions, a solid
	  white back wall (furniture stands against it), a thin white roof that
	  overhangs, a charcoal reveal under the roof edge, a door canopy.
	- No floating text over buildings. Each wing is named the way a real
	  campus names buildings: a dark sign panel over the door, painted ON the
	  building (SurfaceGui), department name + level.
	- Wings in the same column are joined by glass link corridors, so the
	  campus reads as ONE headquarters with a courtyard, not six sheds.
	- HQ levels 2+ get the same language (white walls, mullions, overhang
	  roof, entrance canopy, rooftop plant). Level 1 stays the garage: the
	  story is garage -> headquarters.
	- Grounds: pale pavers, lawn beds with Kenney Nature Kit trees (already
	  imported, CC0), benches, and a company monument sign at the path.

	No uploads. Interiors stay Kenney Furniture Kit (FurnitureKit.dressRoom).
	Everything decorative is CanCollide false unless it is a wall: scenery
	must never trap a player (his rule from 30 Aug).
	v3.2 (25 Sep): the campus plan. Lots ring a promenade loop round the HQ
	(doors facing in, staggered), covered walkways join neighbours, the ground
	is lawn with paths, empty lots are construction sites, every lot has its
	own massing and buildings grow with level. See THE CAMPUS PLAN below.
]]

local CampusArch = {}

local RS = game:GetService("ReplicatedStorage")

-- palette: one language for every building
local WHITE = Color3.fromRGB(240, 239, 235)
local WHITE_WARM = Color3.fromRGB(232, 228, 220)
local CHARCOAL = Color3.fromRGB(38, 41, 48)
local MULLION = Color3.fromRGB(52, 56, 64)
local GLASS = Color3.fromRGB(164, 204, 226)
local PLINTH = Color3.fromRGB(196, 193, 186)
local PAVER = Color3.fromRGB(184, 180, 171)
local LAWN = Color3.fromRGB(136, 172, 96)          -- v3.5: matches the terrain lawn (ART.md Campus Lawn)
local WOOD = Color3.fromRGB(168, 122, 82)

local MONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.SemiBold)

-- the building's sign uses the room's game name, so the sign, the guide and
-- the picker all say the same word (only the café gets its accent)
CampusArch.DEPT = { cafe = "CAFÉ" }

-- interior floor per department: the floor says what the room is from outside
local FLOOR_LOOK = {
	office = { Color3.fromRGB(206, 204, 198), Enum.Material.SmoothPlastic },
	servers = { Color3.fromRGB(70, 74, 82), Enum.Material.DiamondPlate },
	studio = { Color3.fromRGB(196, 160, 118), Enum.Material.WoodPlanks },
	cafe = { Color3.fromRGB(184, 138, 96), Enum.Material.WoodPlanks },
}

local function mk(parent, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do p[k] = v end
	p.Parent = parent
	return p
end

-- a sign painted on a part's face: accent bar + name + small right label
local function sign(part, face, name, accent, withLevel)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 36
	sg.LightInfluence = 0
	sg.MaxDistance = 150
	sg.Parent = part
	local bar = Instance.new("Frame")
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = accent
	bar.Size = UDim2.new(0, 10, 0.7, 0)
	bar.AnchorPoint = Vector2.new(0, 0.5)
	bar.Position = UDim2.new(0.05, 0, 0.5, 0)
	bar.Parent = sg
	local t = Instance.new("TextLabel")
	t.Name = "DeptText"
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0, 0.5)
	t.Position = UDim2.new(0.05, 22, 0.5, 0)
	t.Size = UDim2.new(withLevel and 0.66 or 0.86, -22, 0.72, 0)
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextScaled = true
	t.FontFace = MONT
	t.TextColor3 = WHITE
	t.Text = name
	t.Parent = sg
	local lv
	if withLevel then
		lv = Instance.new("TextLabel")
		lv.Name = "LevelText"
		lv.BackgroundTransparency = 1
		lv.AnchorPoint = Vector2.new(1, 0.5)
		lv.Position = UDim2.new(0.95, 0, 0.5, 0)
		lv.Size = UDim2.new(0.2, 0, 0.56, 0)
		lv.TextXAlignment = Enum.TextXAlignment.Right
		lv.TextScaled = true
		lv.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Medium)
		lv.TextColor3 = Color3.fromRGB(255, 208, 70)
		lv.Text = "LV 1"
		lv.Parent = sg
	end
	return t, lv
end

-- vertical mullions across a glass run from a to b (local x or z), on a line
local function mullions(parent, cf, axis, from, to, fixed, y0, y1, every)
	local n = math.max(1, math.floor((to - from) / every + 0.5))
	local step = (to - from) / n
	for k = 1, n - 1 do
		local c = from + step * k
		local pos = axis == "x" and Vector3.new(c, (y0 + y1) / 2, fixed) or Vector3.new(fixed, (y0 + y1) / 2, c)
		mk(parent, { Name = "Mullion", Size = Vector3.new(0.3, y1 - y0, 0.3), CFrame = cf * CFrame.new(pos),
			Color = MULLION, Material = Enum.Material.Metal, CastShadow = false })
	end
end

local function wedge(parent, props)
	local p = Instance.new("WedgePart")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do p[k] = v end
	p.Parent = parent
	return p
end

-- Kenney furniture for the HQ lobby (FurnitureKit lives in ReplicatedStorage)
local FK
do
	local ok, m = pcall(function() return require(RS:WaitForChild("FurnitureKit", 5)) end)
	if ok then FK = m end
end
local function furn(key, cf, parent, opts)
	if FK and FK.has and FK.has(key) then
		local ok, m = pcall(FK.put, key, cf, parent, opts or {})
		if ok then return m end
	end
	return nil
end


-- v3.4 PHASE W: the Blender trees (ReplicatedStorage.SVMeshes) stand in for
-- the Kenney ones by name, so campus, street and valley share one look. A
-- missing mesh falls back to the Kenney template.
local SV_TREE = {
	tree_default = { "Oak_A", "Oak_B" }, tree_oak = { "Oak_A", "Oak_B" }, tree_detailed = { "Oak_B", "Oak_A" },
	tree_tall = { "Eucalypt_A" }, tree_pineTallA = { "Redwood_A" }, tree_pineRoundA = { "Redwood_A" },
}
local VG_CACHE
local function valleyGen()
	if VG_CACHE == nil then
		local m = game:GetService("ServerScriptService"):FindFirstChild("ValleyGen")
		local ok, mod = pcall(function() return m and require(m) end)
		VG_CACHE = (ok and mod) or false
	end
	return VG_CACHE or nil
end

local function treeTemplate(name)
	-- v4.1: the low-poly set first (ValleyGen.lpTemplate), then the older meshes
	local vg = valleyGen()
	local lpt = vg and vg.lpTemplate and vg.lpTemplate(name)
	if lpt then return lpt end
	local RSv = game:GetService("ReplicatedStorage")
	local sv, alt = RSv:FindFirstChild("SVMeshes"), SV_TREE[name]
	if sv and alt then
		local t = sv:FindFirstChild(alt[math.random(1, #alt)])
		if t then return t end
	end
	local kit = RSv:FindFirstChild("KenneyKit")
	return kit and kit:FindFirstChild(name)
end

-- a Kenney Nature Kit model (ReplicatedStorage.KenneyKit) scaled to a height,
-- its feet on cf (not the furniture kit: bushes and trees live in KenneyKit)
local function kit(name, cf, parent, height)
	local tpl = treeTemplate(name)
	if not tpl then return nil end
	local t = tpl:Clone()
	local _, size = t:GetBoundingBox()
	t:ScaleTo(t:GetScale() * height / math.max(size.Y, 0.1))
	for _, d in ipairs(t:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CastShadow = false end
	end
	t:PivotTo(cf)
	local now, s3 = t:GetBoundingBox()
	t:PivotTo(t:GetPivot() + Vector3.new(0, cf.Position.Y - (now.Position.Y - s3.Y / 2), 0))
	t.Parent = parent
	return t
end

local function glass(parent, cf, size, pos)
	return mk(parent, { Name = "Glass", Size = size, CFrame = cf * CFrame.new(pos),
		Color = GLASS, Material = Enum.Material.Glass, Transparency = 0.55, CastShadow = false })
end

--[[ v3.2 THE CAMPUS PLAN (25 Sep). His note: "still too linear and on square
build plots with no connectivity, and it sucks". Measured from above: a grey
paved rectangle holding two straight columns of three gold-outlined squares,
every door facing the road, nothing joining anything.

  - the six lots ring a PROMENADE LOOP around the HQ, doors facing IN, at
    staggered positions: a campus quad, not a parking grid
  - the loop joins every door, the entrance court and the plaza; a covered
    walkway goes up between two neighbouring buildings once both exist
  - the ground is LAWN with paths; the paved rectangle read as a car park
  - an empty lot is a CONSTRUCTION SITE (hoarding, gravel, a gate sign, and a
    crane only when you can build there right now), not a gold square
  - no two buildings share a shape: each lot has its own massing (a pod, timber
    fins, a green roof, a vestibule, a walled garden, a cantilever), and every
    building GROWS as it levels up (Lv 4 second storey, Lv 7 roof terrace,
    Lv 10 crown), so progress shows from across the campus

Rotations stay multiples of 90 degrees: decor snaps to the world grid, and a
room turned 37 degrees would hold crooked furniture. ]]
local function lotCF(x, z, yaw) return CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yaw), 0) end
CampusArch.LAYOUT = 3
CampusArch.LOTS = {
	lotCF(-92, 14, 90),     -- 1 west, front   (door faces +x, onto the loop)
	lotCF(92, -2, -90),     -- 2 east, front   (door faces -x)
	lotCF(-92, -54, 90),    -- 3 west, back
	lotCF(92, -64, -90),    -- 4 east, back
	lotCF(-38, -100, 0),    -- 5 back, left    (door faces +z, toward the HQ)
	lotCF(30, -100, 0),     -- 6 back, right
}
CampusArch.VARIANT = { "cantilever", "pod", "fins", "greenroof", "vestibule", "garden" }
-- the two earlier layouts, only to carry saved furniture into the moved rooms
local LOTS_V2 = {
	Vector3.new(-66, 0, 14), Vector3.new(66, 0, 14), Vector3.new(-66, 0, -26),
	Vector3.new(66, 0, -26), Vector3.new(-66, 0, -66), Vector3.new(66, 0, -66),
}
local LOTS_V1 = {
	Vector3.new(-52, 0, 4), Vector3.new(52, 0, 4), Vector3.new(-52, 0, -24),
	Vector3.new(52, 0, -24), Vector3.new(-52, 0, -52), Vector3.new(52, 0, -52),
}
-- neighbours on the same side of the loop share a covered walkway
local PAIRS = { { 1, 3 }, { 2, 4 }, { 5, 6 } }
-- the promenade: a rounded rectangle round the HQ (plot-local), 10 wide.
-- The largest HQ is 68 x 52 plus a 7-stud canopy, so its front edge is z 33.
local LOOP = { x = 72, zFront = 44, zBack = -80, r = 32, w = 10 }
CampusArch.LOOP = LOOP
local function loopPoint(p)
	local L = LOOP
	local qx = math.clamp(p.X, -(L.x - L.r), L.x - L.r)
	local qz = math.clamp(p.Z, L.zBack + L.r, L.zFront - L.r)
	local d = Vector3.new(p.X - qx, 0, p.Z - qz)
	if d.Magnitude < 0.01 then return Vector3.new(p.X, 0, p.Z) end
	return Vector3.new(qx, 0, qz) + d.Unit * L.r
end

local PATH = Color3.fromRGB(214, 208, 196)
local PATH_EDGE = Color3.fromRGB(168, 162, 150)
local CAMPUS_LAWN = Color3.fromRGB(136, 172, 96)

-- a saved furniture position (plot-local) in an older layout -> this layout
function CampusArch.migrate(lx, lz, yaw, layout, W, D)
	layout = tonumber(layout) or 1
	if layout >= CampusArch.LAYOUT then return lx, lz, yaw end
	local function inside(c) return math.abs(lx - c.X) <= W / 2 and math.abs(lz - c.Z) <= D / 2 end
	if layout < 2 then
		for i, old in ipairs(LOTS_V1) do
			if inside(old) then lx += LOTS_V2[i].X - old.X; lz += LOTS_V2[i].Z - old.Z; break end
		end
	end
	for i, old in ipairs(LOTS_V2) do
		if inside(old) then
			local new = CampusArch.LOTS[i]
			local p = new:PointToWorldSpace(Vector3.new(lx - old.X, 0, lz - old.Z))
			local _, ry = new:ToEulerAnglesYXZ()
			return p.X, p.Z, (yaw + math.floor(math.deg(ry) + 0.5)) % 360
		end
	end
	return lx, lz, yaw
end

-- the lot index a room model was built on ("Room_office_3" -> 3)
local function lotIndexOf(m)
	return tonumber(string.match(m.Name, "_(%d+)$")) or 0
end


--[[
	A department pavilion. cf = room centre at ground (the slot CFrame), W x D
	footprint, entrance on local +Z (onto the promenade). Returns the door
	canopy (the UPGRADE prompt lives there) and the level TextLabel. The
	interior floor keeps the name "Floor" so SiliconCore's rise() skips it.
]]
local ROOF_FEATURES = { Solar = true, RoofUnit1 = true, RoofUnit2 = true, RoofFan1 = true, RoofFan2 = true,
	Sawtooth = true, Skylight = true, CoolerBase = true, Fan = true, RoofBush = true }

function CampusArch.wing(m, cf, room, W, D)
	local H = 11
	local accent = room.accent
	local look = FLOOR_LOOK[room.id] or FLOOR_LOOK.office
	local lot = lotIndexOf(m)
	local variant = CampusArch.VARIANT[lot]
	m:SetAttribute("Variant", variant or "")

	mk(m, { Name = "Floor", Size = Vector3.new(W + 2, 0.6, D + 2), CFrame = cf * CFrame.new(0, 0.3, 0),
		Color = PLINTH, Material = Enum.Material.Concrete })
	mk(m, { Name = "Floor", Size = Vector3.new(W - 0.4, 1, D - 0.4), CFrame = cf * CFrame.new(0, 0.5, 0),
		Color = look[1], Material = look[2] })

	-- structure: four white corner columns
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			mk(m, { Name = "Column", Size = Vector3.new(1, H, 1),
				CFrame = cf * CFrame.new(sx * (W / 2 - 0.5), H / 2 + 0.5, sz * (D / 2 - 0.5)), Color = WHITE })
		end
	end
	-- solid back wall: bookcases, the bar and the fridge stand against it
	mk(m, { Name = "WallBack", Size = Vector3.new(W - 2, H, 0.8), CFrame = cf * CFrame.new(0, H / 2 + 0.5, -D / 2 + 0.4),
		Color = WHITE_WARM })
	mk(m, { Name = "AccentLine", Size = Vector3.new(W - 4, 0.35, 0.1), CFrame = cf * CFrame.new(0, 7.2, -D / 2 + 0.85),
		Color = accent, Material = Enum.Material.Neon, CastShadow = false })

	-- glass on the two sides with mullions (the SERVER ROOM is clad: a data hall has no windows)
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (W / 2 - 0.5)
		if room.id == "servers" then
			mk(m, { Name = "Cladding", Size = Vector3.new(0.4, H - 1.2, D - 2), CFrame = cf * CFrame.new(x, (H - 1.2) / 2 + 1.1, 0),
				Color = Color3.fromRGB(62, 66, 76), Material = Enum.Material.Metal, CastShadow = false })
			for k = 0, 4 do
				mk(m, { Name = "Vent", Size = Vector3.new(0.5, 0.25, D * 0.5), CFrame = cf * CFrame.new(x + sx * 0.05, 3 + k * 0.7, -D * 0.12),
					Color = Color3.fromRGB(34, 36, 42), Material = Enum.Material.Metal, CastShadow = false })
			end
			mk(m, { Name = "StatusLights", Size = Vector3.new(0.5, 0.18, D - 4), CFrame = cf * CFrame.new(x + sx * 0.05, H - 1.6, 0),
				Color = accent, Material = Enum.Material.Neon, CastShadow = false })
		else
			glass(m, cf, Vector3.new(0.3, H - 1.2, D - 2), Vector3.new(x, (H - 1.2) / 2 + 1.1, 0))
			mullions(m, cf, "z", -D / 2 + 1, D / 2 - 1, x, 1.1, H - 0.1, 4)
		end
		mk(m, { Name = "Sill", Size = Vector3.new(0.6, 0.3, D - 2), CFrame = cf * CFrame.new(x, 1.15, 0),
			Color = MULLION, Material = Enum.Material.Metal, CastShadow = false })
	end
	-- the front: glass either side of a 7-wide doorway, glass transom above it
	local doorW, doorH = 7, 8
	local sideW = (W - 2 - doorW) / 2
	for _, sx in ipairs({ -1, 1 }) do
		local cx = sx * (doorW / 2 + sideW / 2)
		glass(m, cf, Vector3.new(sideW, H - 1.2, 0.3), Vector3.new(cx, (H - 1.2) / 2 + 1.1, D / 2 - 0.5))
		mullions(m, cf, "x", sx > 0 and doorW / 2 or -W / 2 + 1, sx > 0 and W / 2 - 1 or -doorW / 2, D / 2 - 0.5, 1.1, H - 0.1, 3.6)
		mk(m, { Name = "DoorFrame", Size = Vector3.new(0.5, doorH, 0.5), CFrame = cf * CFrame.new(sx * doorW / 2, doorH / 2 + 1, D / 2 - 0.5),
			Color = MULLION, Material = Enum.Material.Metal, CastShadow = false })
	end
	glass(m, cf, Vector3.new(doorW, H - doorH - 1.2, 0.3), Vector3.new(0, doorH + 1 + (H - doorH - 1.2) / 2, D / 2 - 0.5))

	-- roof: thin white slab that overhangs, charcoal reveal under the edge
	local roof = mk(m, { Name = "Roof", Size = Vector3.new(W + 3, 0.7, D + 3), CFrame = cf * CFrame.new(0, H + 0.85, 0), Color = WHITE })
	mk(m, { Name = "Reveal", Size = Vector3.new(W + 0.2, 0.5, D + 0.2), CFrame = cf * CFrame.new(0, H + 0.3, 0),
		Color = CHARCOAL, CastShadow = false })
	mk(m, { Name = "CeilingLight", Size = Vector3.new(W * 0.55, 0.2, 1.4), CFrame = cf * CFrame.new(0, H + 0.05, -2),
		Color = Color3.fromRGB(255, 246, 228), Material = Enum.Material.Neon, CastShadow = false })
	-- v3.2: the roof edge carries the department colour (a campus read by colour from any distance)
	for _, sz in ipairs({ -1, 1 }) do
		mk(m, { Name = "RoofBand", Size = Vector3.new(W + 3.1, 0.4, 0.2), CFrame = cf * CFrame.new(0, H + 0.85, sz * (D / 2 + 1.55)),
			Color = accent, CastShadow = false })
	end
	for _, sx in ipairs({ -1, 1 }) do
		mk(m, { Name = "RoofBand", Size = Vector3.new(0.2, 0.4, D + 3.1), CFrame = cf * CFrame.new(sx * (W / 2 + 1.55), H + 0.85, 0),
			Color = accent, CastShadow = false })
	end

	-- the door canopy: the building's front door and its UPGRADE button
	local canopy = mk(m, { Name = "DoorHeader", Size = Vector3.new(doorW + 4, 0.5, 4), CFrame = cf * CFrame.new(0, doorH + 1.35, D / 2 + 1.5),
		Color = CHARCOAL })
	local panel = mk(m, { Name = "Sign", Size = Vector3.new(16, 1.9, 0.25), CFrame = cf * CFrame.new(0, H - 0.6, D / 2 - 0.2),
		Color = CHARCOAL, CastShadow = false })
	local _, level = sign(panel, Enum.NormalId.Back, CampusArch.DEPT[room.id] or room.name, accent, true)

	local roofY = H + 1.2
	--[[ ONE SILHOUETTE PER DEPARTMENT (v3.0.3): you can tell what a building
	does from across the campus.
	  studio -> sawtooth north-light roof, wood back wall
	  cafe   -> an awning in the cafe colour and a two-table terrace
	  servers-> clad, windowless, a bank of cooling fans on the roof
	  office -> the glass box with solar (the baseline) ]]
	if room.id == "studio" then
		local back = m:FindFirstChild("WallBack")
		if back then back.Color = Color3.fromRGB(176, 128, 86); back.Material = Enum.Material.WoodPlanks end
		for k = -1, 1 do
			local z = k * (D / 3.2)
			wedge(m, { Name = "Sawtooth", Size = Vector3.new(W + 1, 3.2, D / 3.4),
				CFrame = cf * CFrame.new(0, roofY + 1.6, z) * CFrame.Angles(0, math.rad(180), 0), Color = WHITE })
			mk(m, { Name = "Skylight", Size = Vector3.new(W, 3, 0.2), CFrame = cf * CFrame.new(0, roofY + 1.6, z - D / 6.8 + 0.1),
				Color = GLASS, Material = Enum.Material.Glass, Transparency = 0.35, CastShadow = false })
		end
	elseif room.id == "servers" then
		for k = 0, 3 do
			local x = -W / 2 + W * (k + 0.5) / 4
			mk(m, { Name = "CoolerBase", Size = Vector3.new(W / 4 - 1.2, 1.4, D / 2), CFrame = cf * CFrame.new(x, roofY + 0.7, 0),
				Color = Color3.fromRGB(176, 178, 182), Material = Enum.Material.Metal, CastShadow = false })
			for _, z in ipairs({ -D / 8, D / 8 }) do
				mk(m, { Name = "Fan", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, W / 4 - 2.2, W / 4 - 2.2),
					CFrame = cf * CFrame.new(x, roofY + 1.5, z) * CFrame.Angles(0, 0, math.rad(90)),
					Color = Color3.fromRGB(58, 62, 70), Material = Enum.Material.Metal, CastShadow = false })
			end
		end
	else
		if room.id == "cafe" then
			canopy.Color = accent
			for _, sx in ipairs({ -1, 1 }) do
				local base = cf * CFrame.new(sx * (W / 2 - 3.5), 0, D / 2 + 3.4)
				mk(m, { Name = "TerraceTable", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 2.6, 2.6),
					CFrame = base * CFrame.new(0, 2.7, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = WHITE, CanCollide = false })
				mk(m, { Name = "Pole", Size = Vector3.new(0.2, 7, 0.2), CFrame = base * CFrame.new(0, 4.2, 0),
					Color = CHARCOAL, Material = Enum.Material.Metal, CanCollide = false, CastShadow = false })
				mk(m, { Name = "Umbrella", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 6.4, 6.4),
					CFrame = base * CFrame.new(0, 7.6, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = accent, CanCollide = false })
				for _, dz in ipairs({ -1.9, 1.9 }) do
					mk(m, { Name = "TerraceStool", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 1.2, 1.2),
						CFrame = base * CFrame.new(0, 1.9, dz) * CFrame.Angles(0, 0, math.rad(90)), Color = WOOD, CanCollide = false })
				end
			end
		end
		-- rooftop plant: two condenser boxes and a solar strip (read from the camera above)
		for k, x in ipairs({ -W / 4, W / 4 - 2 }) do
			mk(m, { Name = "RoofUnit" .. k, Size = Vector3.new(3.2, 1.6, 2.4), CFrame = cf * CFrame.new(x, roofY + 0.8, -D / 4),
				Color = Color3.fromRGB(176, 178, 182), Material = Enum.Material.Metal, CastShadow = false })
			mk(m, { Name = "RoofFan" .. k, Size = Vector3.new(0.2, 1.8, 1.8), Shape = Enum.PartType.Cylinder,
				CFrame = cf * CFrame.new(x, roofY + 1.62, -D / 4) * CFrame.Angles(0, 0, math.rad(90)),
				Color = Color3.fromRGB(70, 74, 82), Material = Enum.Material.Metal, CastShadow = false })
		end
		for k = 0, 2 do
			mk(m, { Name = "Solar", Size = Vector3.new(W * 0.5, 0.2, 2.6),
				CFrame = cf * CFrame.new(0, roofY + 0.5, D / 6 + k * 3) * CFrame.Angles(math.rad(-14), 0, 0),
				Color = Color3.fromRGB(40, 58, 96), Material = Enum.Material.Glass, CastShadow = false })
		end
	end

	--[[ v3.2 ONE MASSING PER LOT. The department sets the roof; the lot sets
	the shape, so two offices on two lots still look like two buildings. ]]
	if variant == "pod" then
		-- a glass meeting pod off the right side, table and chairs inside
		local base = cf * CFrame.new(W / 2 + 5.4, 0, -D / 2 + 6.5)
		mk(m, { Name = "PodFloor", Size = Vector3.new(9.4, 0.8, 9.4), CFrame = base * CFrame.new(0, 0.4, 0), Color = PLINTH, Material = Enum.Material.Concrete })
		mk(m, { Name = "PodGlass", Size = Vector3.new(8.8, 7, 8.8), CFrame = base * CFrame.new(0, 4.3, 0),
			Color = GLASS, Material = Enum.Material.Glass, Transparency = 0.6, CastShadow = false })
		mk(m, { Name = "PodRoof", Size = Vector3.new(10, 0.6, 10), CFrame = base * CFrame.new(0, 8.1, 0), Color = WHITE })
		mk(m, { Name = "PodLink", Size = Vector3.new(1.6, 7.4, 5), CFrame = cf * CFrame.new(W / 2 + 0.3, 4.5, -D / 2 + 6.5), Color = WHITE_WARM })
		furn("tableRound", base * CFrame.new(0, 0.8, 0), m)
		furn("chairModernCushion", base * CFrame.new(0, 0.8, 2.3), m, { yaw = 180 })
		furn("chairModernCushion", base * CFrame.new(0, 0.8, -2.3), m)
		mk(m, { Name = "PodLamp", Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1), CFrame = base * CFrame.new(0, 6.6, 0),
			Color = Color3.fromRGB(255, 226, 170), Material = Enum.Material.Neon, CastShadow = false, CanCollide = false })
	elseif variant == "fins" then
		-- vertical timber fins across the front glass: a warmer, crafted face
		for k = -6, 6 do
			local x = k * 2.1
			if math.abs(x) > doorW / 2 + 0.6 and math.abs(x) < W / 2 - 0.8 then
				mk(m, { Name = "Fin", Size = Vector3.new(0.35, H - 0.6, 1.3), CFrame = cf * CFrame.new(x, (H - 0.6) / 2 + 0.8, D / 2 + 0.35),
					Color = WOOD, Material = Enum.Material.WoodPlanks, CastShadow = false })
			end
		end
		canopy.Color = WOOD
		canopy.Material = Enum.Material.WoodPlanks
	elseif variant == "greenroof" then
		roof.Material = Enum.Material.SmoothPlastic
		roof.Color = CAMPUS_LAWN
		for _, x in ipairs({ -W / 3, W / 3 }) do
			local b = kit("plant_bushLarge", cf * CFrame.new(x, roofY, D / 3), m, 2.6)
			if not b then
				mk(m, { Name = "RoofBush", Shape = Enum.PartType.Ball, Size = Vector3.new(3, 2.4, 3), CFrame = cf * CFrame.new(x, roofY + 1, D / 3),
					Color = LAWN, Material = Enum.Material.SmoothPlastic, CastShadow = false, CanCollide = false })
			end
		end
	elseif variant == "vestibule" then
		-- a glass porch in front of the door, under the canopy
		mk(m, { Name = "Vestibule", Size = Vector3.new(doorW + 2, 0.6, 3.4), CFrame = cf * CFrame.new(0, 0.3, D / 2 + 1.7), Color = PLINTH, Material = Enum.Material.Concrete })
		for _, sx in ipairs({ -1, 1 }) do
			mk(m, { Name = "VestibuleGlass", Size = Vector3.new(0.3, doorH, 3.2), CFrame = cf * CFrame.new(sx * (doorW / 2 + 0.8), doorH / 2 + 0.6, D / 2 + 1.7),
				Color = GLASS, Material = Enum.Material.Glass, Transparency = 0.55, CastShadow = false })
		end
	elseif variant == "garden" then
		-- a walled garden off the left side: lawn, a tree, a bench
		local base = cf * CFrame.new(-(W / 2 + 5), 0, 0)
		mk(m, { Name = "GardenLawn", Size = Vector3.new(9, 0.3, D - 2), CFrame = base * CFrame.new(0, 0.5, 0), Color = CAMPUS_LAWN,
			Material = Enum.Material.SmoothPlastic, CanCollide = false })
		mk(m, { Name = "GardenWall", Size = Vector3.new(0.6, 1.8, D - 2), CFrame = base * CFrame.new(-4.8, 0.9, 0), Color = PLINTH,
			Material = Enum.Material.Concrete, CanCollide = false })
		for _, sz in ipairs({ -1, 1 }) do
			mk(m, { Name = "GardenWall", Size = Vector3.new(10, 1.8, 0.6), CFrame = base * CFrame.new(0, 0.9, sz * (D / 2 - 1)), Color = PLINTH,
				Material = Enum.Material.Concrete, CanCollide = false })
		end
		kit("tree_oak", base * CFrame.new(0, 0.6, -D / 5), m, 12)
		mk(m, { Name = "GardenBench", Size = Vector3.new(1.8, 1.2, 5), CFrame = base * CFrame.new(-3, 0.9, D / 5), Color = WOOD,
			Material = Enum.Material.WoodPlanks, CanCollide = false })
	end
	return canopy, level
end

--[[ GROWTH. A building gets taller as it levels up, so progress is visible
from across the campus instead of living only on the sign:
  Lv 4  a second storey (the "cantilever" lot pushes it out over the door)
  Lv 7  a roof terrace with a glass rail and planters
  Lv 10 a crown of light in the department colour
Returns the new parts so SiliconCore can play the rise on clients. ]]
local function stageOf(level) return (level >= 10 and 3) or (level >= 7 and 2) or (level >= 4 and 1) or 0 end

function CampusArch.grow(m, cf, room, W, D, level)
	if not m or not m.Parent then return {} end
	local old = m:FindFirstChild("Growth")
	local st = stageOf(level or 1)
	if old and old:GetAttribute("Stage") == st then return {} end
	if old then old:Destroy() end
	if st == 0 then return {} end
	local g = Instance.new("Model")
	g.Name = "Growth"
	g:SetAttribute("Stage", st)
	g.Parent = m
	local made = {}
	local function add(props)
		local p = mk(g, props)
		table.insert(made, p)
		return p
	end
	local H = 11
	local roofTop = H + 1.2
	local variant = m:GetAttribute("Variant")
	local cantilever = variant == "cantilever"
	local uw = cantilever and (W - 2) or (W - 4)
	local ud = cantilever and D or (D - 9)
	local uz = cantilever and 3.5 or (-D / 2 + 1 + ud / 2)
	local ux = 0
	if variant == "garden" or variant == "pod" then
		-- an L: a narrower upper floor pushed to one side
		uw = W * 0.55
		ux = (variant == "pod") and (W / 2 - uw / 2 - 0.5) or -(W / 2 - uw / 2 - 0.5)
		ud = D - 4
		uz = -2
	elseif variant == "vestibule" then
		ud = D - 3
		uz = -1.5
	end
	local uh = 8
	-- the roof plant under the new storey moves out of the way
	for _, p in ipairs(m:GetChildren()) do
		if p:IsA("BasePart") and ROOF_FEATURES[p.Name] then
			local l = cf:PointToObjectSpace(p.Position)
			if math.abs(l.X - ux) < uw / 2 + 1 and l.Z > uz - ud / 2 - 1.5 and l.Z < uz + ud / 2 + 1.5 then
				p.Transparency = 1
				p.CanCollide = false
			end
		elseif p:IsA("Model") and p.Name ~= "Growth" then
			local ok, pcf = pcall(function() return p:GetPivot() end)
			if ok and pcf.Position.Y > cf.Position.Y + roofTop - 1 then
				local l = cf:PointToObjectSpace(pcf.Position)
				if math.abs(l.X - ux) < uw / 2 + 1 and l.Z > uz - ud / 2 - 1.5 and l.Z < uz + ud / 2 + 1.5 then
					for _, d in ipairs(p:GetDescendants()) do if d:IsA("BasePart") then d.Transparency = 1 end end
				end
			end
		end
	end
	local ucf = cf * CFrame.new(ux, roofTop, uz)
	add({ Name = "UpperSlab", Size = Vector3.new(uw + 0.6, 0.6, ud + 0.6), CFrame = ucf * CFrame.new(0, 0.3, 0), Color = WHITE })
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			add({ Name = "UpperColumn", Size = Vector3.new(0.9, uh, 0.9),
				CFrame = ucf * CFrame.new(sx * (uw / 2 - 0.45), uh / 2 + 0.6, sz * (ud / 2 - 0.45)), Color = WHITE })
		end
	end
	add({ Name = "UpperGlass", Size = Vector3.new(uw - 0.8, uh - 0.4, ud - 0.8), CFrame = ucf * CFrame.new(0, uh / 2 + 0.6, 0),
		Color = GLASS, Material = Enum.Material.Glass, Transparency = 0.5, CastShadow = false })
	-- it is occupied: a lit ceiling strip and a row of desks read through the glass
	add({ Name = "UpperLight", Size = Vector3.new(uw * 0.7, 0.2, 1), CFrame = ucf * CFrame.new(0, uh + 0.1, 0),
		Color = Color3.fromRGB(255, 244, 222), Material = Enum.Material.Neon, CastShadow = false })
	for _, x in ipairs({ -uw / 4, uw / 4 }) do
		add({ Name = "UpperDesk", Size = Vector3.new(uw / 3, 2.2, 2.2), CFrame = ucf * CFrame.new(x, 1.7, -ud / 4),
			Color = WOOD, Material = Enum.Material.WoodPlanks, CastShadow = false })
		add({ Name = "UpperScreen", Size = Vector3.new(uw / 3 - 1, 1, 0.15), CFrame = ucf * CFrame.new(x, 3.4, -ud / 4 - 0.6),
			Color = Color3.fromRGB(150, 205, 255), Material = Enum.Material.Neon, CastShadow = false })
	end
	add({ Name = "UpperRoof", Size = Vector3.new(uw + 2, 0.6, ud + 2), CFrame = ucf * CFrame.new(0, uh + 0.9, 0), Color = WHITE })
	add({ Name = "UpperReveal", Size = Vector3.new(uw + 0.2, 0.4, ud + 0.2), CFrame = ucf * CFrame.new(0, uh + 0.45, 0),
		Color = CHARCOAL, CastShadow = false })
	mullions(g, ucf, "x", -uw / 2 + 0.5, uw / 2 - 0.5, ud / 2 - 0.4, 0.6, uh + 0.4, 3.2)
	-- the department colour runs round the upper floor too
	for _, sz in ipairs({ -1, 1 }) do
		add({ Name = "UpperBand", Size = Vector3.new(uw + 2.1, 0.35, 0.2), CFrame = ucf * CFrame.new(0, uh + 0.75, sz * (ud / 2 + 1.05)),
			Color = room.accent, CastShadow = false })
	end
	if variant == "fins" then
		-- timber fins carry up the upper floor
		for k = -4, 4 do
			add({ Name = "UpperFin", Size = Vector3.new(0.3, uh - 0.4, 1), CFrame = ucf * CFrame.new(k * (uw / 9), uh / 2 + 0.6, ud / 2 + 0.2),
				Color = WOOD, Material = Enum.Material.WoodPlanks, CastShadow = false })
		end
	elseif variant == "greenroof" then
		-- the green roof climbs with the building
		local ur = g:FindFirstChild("UpperRoof")
		if ur then ur.Material = Enum.Material.SmoothPlastic; ur.Color = CAMPUS_LAWN end
	end
	local top = uh + 1.2
	if st >= 2 then
		-- a roof terrace: timber deck, glass rail on three sides, two planters
		add({ Name = "TerraceDeck", Size = Vector3.new(uw, 0.25, ud), CFrame = ucf * CFrame.new(0, top + 0.12, 0),
			Color = WOOD, Material = Enum.Material.WoodPlanks, CastShadow = false })
		add({ Name = "TerraceRail", Size = Vector3.new(uw, 1.4, 0.2), CFrame = ucf * CFrame.new(0, top + 0.95, ud / 2 - 0.2),
			Color = GLASS, Material = Enum.Material.Glass, Transparency = 0.4, CastShadow = false })
		for _, sx in ipairs({ -1, 1 }) do
			add({ Name = "TerraceRail", Size = Vector3.new(0.2, 1.4, ud), CFrame = ucf * CFrame.new(sx * (uw / 2 - 0.2), top + 0.95, 0),
				Color = GLASS, Material = Enum.Material.Glass, Transparency = 0.4, CastShadow = false })
			local pl = add({ Name = "TerracePlanter", Size = Vector3.new(2.4, 1.2, 2.4), CFrame = ucf * CFrame.new(sx * (uw / 2 - 2), top + 0.85, -ud / 2 + 2),
				Color = PLINTH, Material = Enum.Material.Concrete, CastShadow = false })
			local bush = kit("plant_bushDetailed", pl.CFrame * CFrame.new(0, 0.6, 0), g, 2.2)
			if not bush then
				add({ Name = "TerraceBush", Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 2, 2.4), CFrame = pl.CFrame * CFrame.new(0, 1.4, 0),
					Color = LAWN, Material = Enum.Material.SmoothPlastic, CastShadow = false, CanCollide = false })
			end
		end
		add({ Name = "TerraceUmbrella", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 5, 5),
			CFrame = ucf * CFrame.new(0, top + 4, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = room.accent, CastShadow = false, CanCollide = false })
		add({ Name = "TerracePole", Size = Vector3.new(0.2, 3.8, 0.2), CFrame = ucf * CFrame.new(0, top + 2, 0),
			Color = CHARCOAL, Material = Enum.Material.Metal, CastShadow = false, CanCollide = false })
	end
	if st >= 3 then
		-- the crown: a band of the department colour round the top storey
		for _, sz in ipairs({ -1, 1 }) do
			add({ Name = "Crown", Size = Vector3.new(uw + 2.1, 0.35, 0.15), CFrame = ucf * CFrame.new(0, uh + 0.9, sz * (ud / 2 + 1.03)),
				Color = room.accent, Material = Enum.Material.Neon, CastShadow = false })
		end
		for _, sx in ipairs({ -1, 1 }) do
			add({ Name = "Crown", Size = Vector3.new(0.15, 0.35, ud + 2.1), CFrame = ucf * CFrame.new(sx * (uw / 2 + 1.03), uh + 0.9, 0),
				Color = room.accent, Material = Enum.Material.Neon, CastShadow = false })
		end
	end
	for _, d in ipairs(g:GetDescendants()) do
		if d:IsA("BasePart") and not table.find(made, d) then table.insert(made, d) end
	end
	return made
end


--[[
	COVERED WALKWAYS (v3.2). Neighbours on the same side of the promenade are
	joined by a colonnade over the loop, door canopy to door canopy, once both
	are built: the walk from one department to the next is under one roof.
	Open, not a glass tube: you can walk in and out of it anywhere, so it
	connects without fencing the path. Columns stand on the building side and
	never collide (scenery must never trap a player). Rebuilt on every build;
	parented to plot.rooms, which releasePlot clears.
]]
function CampusArch.links(plot, W, D)
	local old = plot.rooms:FindFirstChild("Links")
	if old then old:Destroy() end
	local f = Instance.new("Folder")
	f.Name = "Links"
	f.Parent = plot.rooms
	local RH = 10.2           -- over the door canopies (9.35), so they tuck under
	for _, pr in ipairs(PAIRS) do
		local a, b = plot.slots[pr[1]], plot.slots[pr[2]]
		if a and b and a.built and b.built then
			-- each door canopy's outer edge, in plot space
			local pa = plot.pivot:PointToObjectSpace(a.cf:PointToWorldSpace(Vector3.new(0, 0, D / 2 + 2.6)))
			local pb = plot.pivot:PointToObjectSpace(b.cf:PointToWorldSpace(Vector3.new(0, 0, D / 2 + 2.6)))
			local along = pb - pa
			local len = along.Magnitude
			if len > 4 then
				local dir = along.Unit
				local mid = (pa + pb) / 2
				-- the side the buildings are on: columns go there, the loop stays open
				local perp = Vector3.new(-dir.Z, 0, dir.X)
				local lotSide = plot.pivot:PointToObjectSpace(a.cf.Position) - mid
				if lotSide:Dot(perp) < 0 then perp = -perp end
				local cf = plot.pivot * CFrame.lookAt(mid, mid + dir) * CFrame.new(0, 0, 0)
				local function at(off) return cf * CFrame.new(off) end
				-- lookAt faces -Z along `dir`; local X is the cross direction
				local xSide = (cf.RightVector:Dot(plot.pivot:VectorToWorldSpace(perp)) >= 0) and 1 or -1
				mk(f, { Name = "WalkRoof", Size = Vector3.new(6.4, 0.5, len + 3), CFrame = at(Vector3.new(0, RH, 0)), Color = WHITE })
				mk(f, { Name = "WalkFascia", Size = Vector3.new(0.3, 0.7, len + 3), CFrame = at(Vector3.new(-xSide * 3.2, RH - 0.1, 0)),
					Color = CHARCOAL, CastShadow = false })
				mk(f, { Name = "WalkLight", Size = Vector3.new(1.2, 0.1, len), CFrame = at(Vector3.new(0, RH - 0.3, 0)),
					Color = Color3.fromRGB(255, 240, 214), Material = Enum.Material.Neon, CastShadow = false })
				-- columns every ~8 studs, none right at a door
				local n = math.max(1, math.floor((len - 10) / 8))
				for k = 0, n do
					local z = -len / 2 + 5 + (len - 10) * (k / math.max(n, 1))
					mk(f, { Name = "WalkColumn", Size = Vector3.new(0.5, RH - 0.3, 0.5), CFrame = at(Vector3.new(xSide * 2.9, (RH - 0.3) / 2 + 0.3, z)),
						Color = WHITE, CanCollide = false, CastShadow = false })
				end
				-- a line of planters along the building side, under the roof
				for k = 1, math.max(0, n - 1) do
					local z = -len / 2 + 5 + (len - 10) * ((k - 0.5) / math.max(n, 1))
					mk(f, { Name = "WalkPlanter", Size = Vector3.new(1.4, 1, 3), CFrame = at(Vector3.new(xSide * 2.9, 0.9, z)),
						Color = PLINTH, Material = Enum.Material.Concrete, CanCollide = false, CastShadow = false })
					mk(f, { Name = "WalkShrub", Size = Vector3.new(1.2, 0.8, 2.8), CFrame = at(Vector3.new(xSide * 2.9, 1.7, z)),
						Color = LAWN, Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false })
				end
			end
		end
	end
	return f
end


--[[
	HQ levels 2+: the same language as the wings. `add` makes a tracked shell
	part (so an HQ upgrade rebuilds cleanly); `shell` is the list so existing
	parts can be restyled by name.
]]
-- a Kenney tree in a concrete planter, for the lobby (clone of ReplicatedStorage.KenneyKit)
local function indoorTree(add, g, x, z, F, parent, height, maxWidth)
	add({ Name = "Planter", Size = Vector3.new(3, 1.4, 3), CFrame = g(x, F + 0.7, z), Color = PLINTH, Material = Enum.Material.Concrete })
	-- v3.5: the tall, narrow eucalyptus, scaled to FIT: the lobby oaks (an oak is
	-- as wide as it is tall) pushed their crowns through the side glass,
	-- mullions and walls -- 18 hits in the sweep. Height is capped by the room
	-- as well as by the ceiling.
	local tpl = treeTemplate("tree_tall")
	if not tpl then return end
	local t = tpl:Clone()
	local _, size = t:GetBoundingBox()
	local k = height / math.max(size.Y, 0.1)
	if maxWidth then k = math.min(k, maxWidth / math.max(size.X, size.Z, 0.1)) end
	t:ScaleTo(t:GetScale() * k)
	for _, d in ipairs(t:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CastShadow = false end
	end
	t:PivotTo(g(x, F + 1.4, z))
	local cf, s3 = t:GetBoundingBox()
	t:PivotTo(t:GetPivot() + Vector3.new(0, (g(0, F + 1.4, 0).Position.Y) - (cf.Position.Y - s3.Y / 2), 0))
	t.Parent = parent
end

function CampusArch.dressHQ(add, g, level, w, d, h, shell, plot)
	if level < 2 then return end
	for _, p in ipairs(shell) do
		if p.Name == "WallBack" or p.Name == "WallL" or p.Name == "WallR" or p.Name == "FrontWall" or p.Name == "Parapet" then
			p.Color = WHITE_WARM
		elseif p.Name == "Roof" then
			p.Color = WHITE
			p.Size = Vector3.new(w + 4, 0.8, d + 5)
		elseif p.Name == "EntranceHeader" or p.Name == "StoreyBand" then
			p.Color = CHARCOAL
		elseif p.Name == "FrontGlass" or p.Name == "SideGlass" then
			p.Color = GLASS
			p.Transparency = 0.55
		end
	end
	add({ Name = "Reveal", Size = Vector3.new(w + 0.4, 0.6, d + 0.4), CFrame = g(0, h - 0.5, 0), Color = CHARCOAL, CastShadow = false })
	-- mullions on the front glass runs and the side glass
	local doorW = 14
	local sideW = (w - doorW) / 2
	for _, side in ipairs({ -1, 1 }) do
		local x0 = side * (doorW / 2 + 1)
		local x1 = side * (doorW / 2 + sideW - 1)
		local lo, hi = math.min(x0, x1), math.max(x0, x1)
		local n = math.max(2, math.floor((hi - lo) / 4))
		for k = 1, n - 1 do
			add({ Name = "Mullion", Size = Vector3.new(0.35, h - 7, 0.5), CFrame = g(lo + (hi - lo) * k / n, (h - 7) / 2 + 3, d / 2 + 0.05),
				Color = MULLION, Material = Enum.Material.Metal, CastShadow = false })
		end
		local zn = math.max(2, math.floor((d - 6) / 4))
		for k = 1, zn - 1 do
			add({ Name = "Mullion", Size = Vector3.new(0.5, h - 9, 0.35),
				CFrame = g(side * (w / 2 + 0.36), (h - 9) / 2 + 4, -(d - 6) / 2 + (d - 6) * k / zn),
				Color = MULLION, Material = Enum.Material.Metal, CastShadow = false })
		end
	end
	-- v3.2: the back faces the courtyard and two buildings, so it gets a facade
	-- (it was a 68 x 60 blank white slab): vertical fins, a band at every
	-- floor, and a back door with its own canopy onto the promenade
	do
		local n = math.max(4, math.floor((w - 4) / 4))
		for k = 0, n do
			local x = -w / 2 + 2 + (w - 4) * k / n
			if math.abs(x) > 5 then
				add({ Name = "BackFin", Size = Vector3.new(0.45, h - 3, 0.9), CFrame = g(x, (h - 3) / 2 + 1.5, -d / 2 - 0.7),
					Color = MULLION, Material = Enum.Material.Metal, CastShadow = false })
			end
		end
		for y = 16, h - 4, 12 do
			add({ Name = "BackBand", Size = Vector3.new(w + 0.4, 0.8, 0.6), CFrame = g(0, y, -d / 2 - 0.5), Color = CHARCOAL, CastShadow = false })
		end
		add({ Name = "BackDoor", Size = Vector3.new(8, 9, 0.3), CFrame = g(0, 5.5, -d / 2 - 0.6), Color = GLASS, Material = Enum.Material.Glass,
			Transparency = 0.35, CastShadow = false })
		add({ Name = "BackCanopy", Size = Vector3.new(14, 0.6, 5), CFrame = g(0, 11, -d / 2 - 2.8), Color = WHITE })
		add({ Name = "BackCanopyEdge", Size = Vector3.new(14.2, 0.35, 0.3), CFrame = g(0, 10.7, -d / 2 - 5.3), Color = CHARCOAL, CastShadow = false })
	end
	-- entrance canopy, cantilevered toward the road
	add({ Name = "Canopy", Size = Vector3.new(doorW + 8, 0.7, 7), CFrame = g(0, 11.5, d / 2 + 3.3), Color = WHITE })
	add({ Name = "CanopyEdge", Size = Vector3.new(doorW + 8.2, 0.35, 0.3), CFrame = g(0, 11.2, d / 2 + 6.8), Color = CHARCOAL, CastShadow = false })
	-- rooftop plant and, from level 3, a solar array
	for k, x in ipairs({ -w / 4, w / 4 }) do
		add({ Name = "RoofUnit" .. k, Size = Vector3.new(5, 2.4, 4), CFrame = g(x, h + 1.7, -d / 4),
			Color = Color3.fromRGB(176, 178, 182), Material = Enum.Material.Metal, CastShadow = false })
	end
	if level >= 3 then
		for k = 0, 3 do
			add({ Name = "Solar", Size = Vector3.new(w * 0.45, 0.25, 3),
				CFrame = g(0, h + 1.4, 2 + k * 3.6) * CFrame.Angles(math.rad(-14), 0, 0),
				Color = Color3.fromRGB(40, 58, 96), Material = Enum.Material.Glass, CastShadow = false })
		end
	end

	--[[ v3.0.3 THE LOBBY. Measured 24 Sep: at HQ 5 the ground floor was a 68 x 52
	white hall with one garage desk in it, blown out by white floor + white walls
	+ neon, and the tower above it empty and dark through the glass. His note:
	the building look "sucks". Now the ground floor is a company lobby (reception
	at the door, a lounge, a meeting table, bookcases, plants) on a darker floor,
	and every upper floor is lit and furnished so the tower reads as occupied.
	Everything stays clear of the path door -> founder desk and both pads. ]]
	for _, p in ipairs(shell) do
		if p.Name == "GarageFloor" then p.Color = Color3.fromRGB(150, 146, 140); p.Material = Enum.Material.Concrete end
	end
	local anchor = add({ Name = "LobbyAnchor", Size = Vector3.new(1, 1, 1), CFrame = g(0, -6, 0), Transparency = 1,
		CanCollide = false, CanQuery = false, CastShadow = false })
	local F = 1.0                                       -- the lobby floor's top
	local side = w / 2
	-- v4.0: the plan has rounded corners (hq2.py); keep the back-wall pieces off them
	local RC = ({ [2] = 5, [3] = 7, [4] = 8, [5] = 8 })[level] or 0
	-- reception: a counter left of the door, the receptionist's screen facing into it
	add({ Name = "Reception", Size = Vector3.new(9, 3, 2.4), CFrame = g(-(side - 10), F + 1.5, d / 2 - 8), Color = WOOD, Material = Enum.Material.WoodPlanks })
	add({ Name = "ReceptionTop", Size = Vector3.new(9.6, 0.3, 3), CFrame = g(-(side - 10), F + 3.15, d / 2 - 8), Color = WHITE })
	add({ Name = "ReceptionLine", Size = Vector3.new(9.02, 0.25, 0.1), CFrame = g(-(side - 10), F + 2.5, d / 2 - 6.78),
		Color = Color3.fromRGB(255, 208, 70), Material = Enum.Material.Neon, CastShadow = false })
	furn("computerScreen", g(-(side - 10) - 2, F + 3.3, d / 2 - 8.3), anchor, { yaw = 180 })
	furn("chairDesk", g(-(side - 10), F, d / 2 - 11), anchor, { yaw = 180 })
	-- lounge on the right: rug, sofa facing into the room, lamp, plant
	add({ Name = "Rug", Size = Vector3.new(9, 0.06, 11), CFrame = g(side - 9, F + 0.03, -d / 2 + 13),
		Color = Color3.fromRGB(92, 102, 120), CastShadow = false, CanCollide = false })
	furn("loungeDesignSofa", g(side - 5.5, F, -d / 2 + 13), anchor, { yaw = -90 })
	furn("lampSquareFloor", g(side - 4, F, -d / 2 + 6.5), anchor)
	furn("pottedPlant", g(side - 4, F, -d / 2 + 19.5), anchor)
	-- meeting table on the left, clear of the hire pad
	local mx, mz = -(side - 8), -d / 2 + 13
	furn("tableRound", g(mx, F, mz), anchor, { canCollide = true })
	for j, o in ipairs({ { 0, 2.6, 180 }, { 0, -2.6, 0 }, { 2.4, 0, -90 }, { -2.4, 0, 90 } }) do
		furn("chairModernCushion", g(mx + o[1], F, mz + o[2]), anchor, { yaw = o[3] })
	end
	-- back wall: bookcases either side of the logo; plants by the door
	for _, sx in ipairs({ -1, 1 }) do
		furn("bookcaseClosedDoors", g(sx * (side - RC - 3), F, -d / 2 + 1.6), anchor)
		furn("bookcaseClosedDoors", g(sx * (side - RC - 5.6), F, -d / 2 + 1.6), anchor)
		furn("pottedPlant", g(sx * 10, F, d / 2 - 2.6), anchor)
	end

	-- the room itself: a wood feature wall behind the logo (the dark logo panel
	-- now reads against it), a runner from the door to the founder's desk (it is
	-- also the path the guide sends a new player down), a dark skirting line,
	-- a waiting sofa by the door, pendant lamps over the meeting table
	local ceilY = (h >= 28) and 15.4 or (h - 0.5)
	add({ Name = "FeatureWall", Size = Vector3.new(w - 2 * RC - 2, ceilY - F, 0.3), CFrame = g(0, F + (ceilY - F) / 2, -d / 2 + 0.66),
		Color = Color3.fromRGB(150, 108, 72), Material = Enum.Material.WoodPlanks, CastShadow = false })
	add({ Name = "Runner", Size = Vector3.new(6, 0.05, d - 16), CFrame = g(0, F + 0.03, 3),
		Color = Color3.fromRGB(64, 78, 104), CastShadow = false, CanCollide = false })
	for _, sx in ipairs({ -1, 1 }) do
		add({ Name = "Skirting", Size = Vector3.new(0.2, 1, d - 2 * RC - 2), CFrame = g(sx * (side - 0.6), F + 0.5, 0),
			Color = Color3.fromRGB(58, 62, 70), CastShadow = false })
	end
	furn("loungeDesignSofa", g(side - 5, F, d / 2 - 9), anchor, { yaw = -90 })
	furn("pottedPlant", g(side - 4, F, d / 2 - 3.5), anchor)
	for _, o in ipairs({ { -1.6, -1.6 }, { 1.6, 1.6 }, { 0, 0 } }) do
		add({ Name = "PendantCord", Size = Vector3.new(0.08, ceilY - F - 6.4, 0.08),
			CFrame = g(mx + o[1], F + 6.4 + (ceilY - F - 6.4) / 2, mz + o[2]), Color = Color3.fromRGB(40, 40, 44), CastShadow = false, CanCollide = false })
		add({ Name = "Pendant", Shape = Enum.PartType.Ball, Size = Vector3.new(1.1, 1.1, 1.1),
			CFrame = g(mx + o[1], F + 6.2, mz + o[2]), Color = Color3.fromRGB(255, 226, 170), Material = Enum.Material.Neon, CastShadow = false, CanCollide = false })
	end

	-- a pale ceiling under the slab (the charcoal slab read as a heavy lid from inside)
	if h >= 28 then
		add({ Name = "Ceiling", Size = Vector3.new(w - 1.5, 0.2, d - 1.5), CFrame = g(0, 15.25, 0),
			Color = Color3.fromRGB(236, 234, 228), CastShadow = false })
	end
	-- indoor trees in planters along both side walls, clear of pads, rugs and furniture
	for _, z in ipairs({ -3, 6 }) do
		-- the planter stands 2.6 from the side wall: the crown may be at most ~4.2 wide
		indoorTree(add, g, -(side - 2.6), z, F, anchor, math.min(ceilY - F - 2.5, 11), 4.2)
		indoorTree(add, g, side - 2.6, z, F, anchor, math.min(ceilY - F - 2.5, 11), 4.2)
	end

	--[[ v4.0: the storeys above are REAL floors now (HQFloors: a lift, Engineering,
	Design Studio, Boardroom, Sky Cafe, the roof garden). The v3.0.3 rows of lit
	wooden blocks and neon strips behind full-height glass are gone: that was
	the "jewelry storefront". ]]
	local HQF = game:GetService("ServerScriptService"):FindFirstChild("HQFloors")
	local okR, mod = pcall(function() return HQF and require(HQF) end)
	if okR and mod then
		local ok, err = pcall(mod.build, add, g, level, w, d, h, shell, plot)
		if not ok then warn("[SV] HQFloors failed: " .. tostring(err)) end
	end
end

-- a Kenney Nature Kit tree (already imported to ReplicatedStorage.KenneyKit),
-- scaled to a height; primitive fallback so a missing import never breaks a plot
local function tree(parent, cf, height, pool, rng)
	local name = pool[rng:NextInteger(1, #pool)]
	local tpl = treeTemplate(name)
	-- v3.5: one spacing registry with the valley (ValleyGen): a smaller tree if
	-- the spot is crowded, none at all if even that would grow into a neighbour
	local VG = valleyGen()
	if tpl and VG then
		local _, sz = tpl:GetBoundingBox()
		local aspect = math.max(sz.X, sz.Z) / math.max(sz.Y, 0.1)
		local p = cf.Position
		local fitted
		for _, k in ipairs({ 1, 0.8, 0.62 }) do
			if VG.treeRoom(p.X, p.Z, height * k * aspect / 2) then fitted = k break end
		end
		if not fitted then return nil end
		height = height * fitted
		VG.claimTree(p.X, p.Z, height * aspect / 2)
	end
	if tpl then
		local t = tpl:Clone()
		local _, size = t:GetBoundingBox()
		t:ScaleTo(t:GetScale() * height / math.max(size.Y, 0.1))
		for _, d in ipairs(t:GetDescendants()) do
			if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanQuery = false end
		end
		t:PivotTo(cf * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
		-- sit the bounding box bottom on the bed
		local now, s3 = t:GetBoundingBox()
		t:PivotTo(t:GetPivot() + Vector3.new(0, cf.Position.Y - (now.Position.Y - s3.Y / 2), 0))
		t.Parent = parent
		return t
	end
	mk(parent, { Name = "Trunk", Size = Vector3.new(0.8, height * 0.45, 0.8), CFrame = cf * CFrame.new(0, height * 0.225, 0),
		Color = Color3.fromRGB(120, 86, 60), CanCollide = false })
	mk(parent, { Name = "Crown", Shape = Enum.PartType.Ball, Size = Vector3.new(height * 0.6, height * 0.6, height * 0.6),
		CFrame = cf * CFrame.new(0, height * 0.7, 0), Color = LAWN, CanCollide = false })
end

local function bench(parent, cf)
	mk(parent, { Name = "BenchBase", Size = Vector3.new(6, 1.2, 1.8), CFrame = cf * CFrame.new(0, 0.6, 0),
		Color = PLINTH, Material = Enum.Material.Concrete, CanCollide = false })
	mk(parent, { Name = "BenchTop", Size = Vector3.new(6.4, 0.3, 2), CFrame = cf * CFrame.new(0, 1.35, 0),
		Color = WOOD, Material = Enum.Material.WoodPlanks, CanCollide = false })
end

--[[
	GROUNDS (v3.2). The base is a mown lawn and paths are the only paving (a
	paved rectangle read as a car park). One promenade loop joins every door;
	the main axis runs road -> plaza -> loop -> HQ; trees sit in the lawn
	between buildings, never on a path, a lot or the largest HQ footprint.
	Returns the monument's TextLabel so refreshSign can put the company name
	on it.
]]
-- a straight run of path between two plot-local points, w wide, with kerb lines
local function pathRun(f, g, a, b, w, color, name, edges)
	local d = b - a
	local len = d.Magnitude
	if len < 0.1 then return end
	local mid = (a + b) / 2
	local cf = CFrame.lookAt(Vector3.new(mid.X, 0, mid.Z), Vector3.new(b.X, 0, b.Z))
	local base = g(0, 0, 0) * cf
	mk(f, { Name = name or "Path", Size = Vector3.new(w, 0.5, len + 0.6), CFrame = base * CFrame.new(0, 0.35, 0),
		Color = color or PATH, Material = Enum.Material.Concrete, MaterialVariant = "SV_CampusPavers", CanQuery = false, CastShadow = false })
	if edges then
		for _, sx in ipairs({ -1, 1 }) do
			mk(f, { Name = "PathEdge", Size = Vector3.new(0.5, 0.52, len + 0.6), CFrame = base * CFrame.new(sx * (w / 2 - 0.25), 0.36, 0),
				Color = PATH_EDGE, Material = Enum.Material.Concrete, CanQuery = false, CastShadow = false })
		end
	end
end

local function lamp(f, cf)
	mk(f, { Name = "LampPole", Size = Vector3.new(0.4, 7, 0.4), CFrame = cf * CFrame.new(0, 4, 0), Color = CHARCOAL,
		Material = Enum.Material.Metal, CanCollide = false, CastShadow = false })
	mk(f, { Name = "LampHead", Size = Vector3.new(1.6, 0.35, 1.6), CFrame = cf * CFrame.new(0, 7.6, 0),
		Color = Color3.fromRGB(255, 238, 200), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
end

function CampusArch.grounds(folder, pivot, slab, path, seed)
	local rng = Random.new(seed or 7)
	local g = function(x, y, z) return pivot * CFrame.new(x, y, z) end
	local f = Instance.new("Folder")
	f.Name = "Grounds"
	f.Parent = folder
	if slab then
		slab.Size = Vector3.new(240, 0.8, 214)
		slab.CFrame = g(0, -0.1, -21)
		slab.Color = CAMPUS_LAWN
		slab.Material = Enum.Material.SmoothPlastic
	end
	-- the main axis: the garage door (z 15) to the road (z 98)
	if path then
		path.Size = Vector3.new(10, 0.5, 84)
		path.CFrame = g(0, 0.35, 56)
		path.Color = PATH
		path.Material = Enum.Material.Pavement
	end

	-- the promenade loop: four straights and four rounded corners
	local L = LOOP
	local x1, zf, zb, r = L.x, L.zFront, L.zBack, L.r
	pathRun(f, g, Vector3.new(-(x1 - r), 0, zf), Vector3.new(x1 - r, 0, zf), L.w, PATH, "Promenade", true)
	pathRun(f, g, Vector3.new(-(x1 - r), 0, zb), Vector3.new(x1 - r, 0, zb), L.w, PATH, "Promenade", true)
	pathRun(f, g, Vector3.new(-x1, 0, zf - r), Vector3.new(-x1, 0, zb + r), L.w, PATH, "Promenade", true)
	pathRun(f, g, Vector3.new(x1, 0, zf - r), Vector3.new(x1, 0, zb + r), L.w, PATH, "Promenade", true)
	for _, c in ipairs({
		{ x1 - r, zf - r, 0 }, { -(x1 - r), zf - r, 90 }, { -(x1 - r), zb + r, 180 }, { x1 - r, zb + r, 270 },
	}) do
		local steps = 9
		for k = 0, steps - 1 do
			local a0 = math.rad(c[3] + 90 * k / steps)
			local a1 = math.rad(c[3] + 90 * (k + 1) / steps)
			local p0 = Vector3.new(c[1] + r * math.cos(a0), 0, c[2] + r * math.sin(a0))
			local p1 = Vector3.new(c[1] + r * math.cos(a1), 0, c[2] + r * math.sin(a1))
			pathRun(f, g, p0, p1, L.w, PATH, "Promenade", false)
		end
	end
	-- a spur from every lot's door to the loop, framed by two shrubs: every
	-- building (and every site you have not built yet) is on the network
	for _, lot in ipairs(CampusArch.LOTS) do
		local door = lot:PointToWorldSpace(Vector3.new(0, 0, 24 / 2 + 3.5))
		local onLoop = loopPoint(door)
		if (onLoop - door).Magnitude > 3 then pathRun(f, g, door, onLoop, 6, PATH, "Spur", false) end
		for _, sx in ipairs({ -1, 1 }) do
			local b = lot:PointToWorldSpace(Vector3.new(sx * 6.5, 0, 24 / 2 + 3))
			if not kit("plant_bushDetailed", g(b.X, 0.3, b.Z), f, 2.4) then
				mk(f, { Name = "Shrub", Shape = Enum.PartType.Ball, Size = Vector3.new(2.6, 2.2, 2.6), CFrame = g(b.X, 1.3, b.Z),
					Color = LAWN, Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false })
			end
		end
	end
	-- the entrance court in front of the HQ door, joining the axis to the loop
	mk(f, { Name = "EntranceCourt", Size = Vector3.new(34, 0.5, 18), CFrame = g(0, 0.34, 30),
		Color = PATH, Material = Enum.Material.Pavement, CanQuery = false, CastShadow = false })
	-- the plaza where the axis meets the road side: a round paved square
	mk(f, { Name = "Plaza", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 28, 28),
		CFrame = g(0, 0.36, 66) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(198, 190, 176),
		Material = Enum.Material.Pavement, CanQuery = false, CastShadow = false })
	mk(f, { Name = "PlazaRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.52, 29.2, 29.2),
		CFrame = g(0, 0.34, 66) * CFrame.Angles(0, 0, math.rad(90)), Color = PATH_EDGE,
		Material = Enum.Material.Concrete, CanQuery = false, CastShadow = false })
	-- a round planter and a tree at the centre (you walk round it, as in any square)
	mk(f, { Name = "PlazaPlanter", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 7, 7),
		CFrame = g(0, 1, 66) * CFrame.Angles(0, 0, math.rad(90)), Color = PLINTH, Material = Enum.Material.Concrete })
	mk(f, { Name = "PlazaSoil", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 6, 6),
		CFrame = g(0, 1.62, 66) * CFrame.Angles(0, 0, math.rad(90)), Color = CAMPUS_LAWN, Material = Enum.Material.SmoothPlastic, CanCollide = false })
	tree(f, g(0, 1.7, 66), 13, { "tree_detailed", "tree_oak" }, rng)
	for k = 0, 3 do
		local a = math.rad(45 + 90 * k)
		local bx, bz = math.cos(a) * 9.5, 66 + math.sin(a) * 9.5
		bench(f, g(bx, 0.6, bz) * CFrame.Angles(0, -a + math.rad(90), 0))
	end

	-- trees in the lawn: inside the loop (clear of the largest HQ, x +-54, z -34..38),
	-- round the outside, and along the front
	local TREES = { "tree_default", "tree_oak", "tree_detailed" }
	local TALL = { "tree_tall", "tree_pineTallA", "tree_pineRoundA" }
	local spots = {
		{ -60, -48, TREES }, { -61, -12, TREES }, { -60, 18, TREES }, { 60, -40, TREES }, { 61, -4, TREES }, { 60, 22, TREES },
		{ -22, -58, TREES }, { 4, -64, TREES }, { 26, -56, TREES },
		{ -114, 44, TALL }, { -114, -28, TALL }, { -114, -96, TALL }, { 114, 36, TALL }, { 114, -34, TALL }, { 114, -100, TALL },
		{ -84, -118, TALL }, { 0, -120, TALL }, { 74, -118, TALL },
		{ -46, 86, TREES }, { -62, 66, TREES }, { -96, 78, TREES }, { -104, 40, TREES },
		{ 30, 80, TREES }, { 62, 66, TREES }, { 96, 78, TREES }, { 104, 32, TREES },
	}
	for _, s in ipairs(spots) do
		local jx, jz = rng:NextNumber(-3, 3), rng:NextNumber(-3, 3)
		local tall = s[3] == TALL
		tree(f, g(s[1] + jx, 0.3, s[2] + jz), tall and rng:NextNumber(16, 22) or rng:NextNumber(11, 15), s[3], rng)
	end
	-- benches looking at the lawn from the loop, both sides and the back
	for _, b in ipairs({ { -62, -30, 90 }, { 62, -30, -90 }, { -10, -70, 0 }, { 14, -70, 0 } }) do
		bench(f, g(b[1], 0.3, b[2]) * CFrame.Angles(0, math.rad(b[3]), 0))
	end
	-- lamp posts: along the axis and at the loop corners (no PointLights: daylight game, neon heads read as lamps)
	for _, p in ipairs({ { -7, 50 }, { 7, 50 }, { -7, 84 }, { 7, 84 }, { -86, 38 }, { 86, 38 }, { -86, -86 }, { 86, -86 } }) do
		lamp(f, g(p[1], 0.3, p[2]))
	end

	-- the company monument on the plaza, facing the road
	local mono = mk(f, { Name = "Monument", Size = Vector3.new(16, 4.2, 1.6), CFrame = g(-24, 2.4, 80),
		Color = CHARCOAL, CanCollide = false })
	mk(f, { Name = "MonumentBase", Size = Vector3.new(18, 0.8, 3), CFrame = g(-24, 0.5, 80),
		Color = PLINTH, Material = Enum.Material.Concrete, CanCollide = false })
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 36
	sg.LightInfluence = 0
	sg.MaxDistance = 220
	sg.Parent = mono
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(0.9, 0, 0.56, 0)
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.new(0.5, 0, 0.44, 0)
	t.TextScaled = true
	t.FontFace = MONT
	t.TextColor3 = WHITE
	t.Text = ""
	t.Parent = sg
	local line = Instance.new("Frame")
	line.BorderSizePixel = 0
	line.BackgroundColor3 = Color3.fromRGB(255, 208, 70)
	line.AnchorPoint = Vector2.new(0.5, 0)
	line.Position = UDim2.new(0.5, 0, 0.8, 0)
	line.Size = UDim2.new(0.22, 0, 0, 6)
	line.Parent = sg
	return t
end

--[[
	AN EMPTY LOT (v4.0) is a finished, empty glass suite with a leasing sign
	(it was a construction site with a crane in v3.2). The pad keeps the name "Slot<i>" (the
	prompt, the click and the guide use it); everything else lives in the
	model "Slot<i>Edge", which SiliconCore deletes when the building goes up.
	Returns the pad and the sign's small right-hand TextLabel (slot.text).
]]

function CampusArch.lot(folder, cf, i, W, D)
	--[[ v4.0 A FINISHED, EMPTY SUITE -- not a construction site. His note: "the HQ
	should be a large building that eventually finishes but doesn't look like a
	construction site as you progress... see the design studio plot empty but it
	doesn't look like an unfinished product." So an empty lot is the same glass
	pavilion every department lives in, finished, clean and lit, with an
	AVAILABLE sign: space ready to move into. Building a department fits it out.
	A lot the HQ has not unlocked yet is the same shell, dark, "UNLOCKS AT HQ n".
	(The hoarding, pallets and tower crane are gone.) ]]
	local name = "Slot" .. i
	local pad = mk(folder, { Name = name, Size = Vector3.new(W - 0.4, 0.4, D - 0.4), CFrame = cf * CFrame.new(0, 0.8, 0),
		Color = Color3.fromRGB(214, 210, 202), Material = Enum.Material.SmoothPlastic })
	local site = Instance.new("Model")
	site.Name = name .. "Edge"
	site.Parent = folder
	local function s(props)
		if props.CastShadow == nil then props.CastShadow = false end
		return mk(site, props)
	end
	local H = 11
	s({ Name = "Plinth", Size = Vector3.new(W + 2, 0.6, D + 2), CFrame = cf * CFrame.new(0, 0.3, 0), Color = PLINTH, Material = Enum.Material.Concrete })
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			s({ Name = "Column", Size = Vector3.new(1, H, 1), CFrame = cf * CFrame.new(sx * (W / 2 - 0.5), H / 2 + 0.5, sz * (D / 2 - 0.5)), Color = WHITE, CastShadow = true })
		end
	end
	s({ Name = "WallBack", Size = Vector3.new(W - 2, H, 0.8), CFrame = cf * CFrame.new(0, H / 2 + 0.5, -D / 2 + 0.4), Color = WHITE_WARM, CastShadow = true })
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (W / 2 - 0.5)
		glass(site, cf, Vector3.new(0.3, H - 1.2, D - 2), Vector3.new(x, (H - 1.2) / 2 + 1.1, 0))
		mullions(site, cf, "z", -D / 2 + 1, D / 2 - 1, x, 1.1, H - 0.1, 4)
		s({ Name = "Sill", Size = Vector3.new(0.6, 0.3, D - 2), CFrame = cf * CFrame.new(x, 1.15, 0), Color = MULLION, Material = Enum.Material.Metal })
	end
	local doorW, doorH = 7, 8
	local sideW = (W - 2 - doorW) / 2
	for _, sx in ipairs({ -1, 1 }) do
		local cx = sx * (doorW / 2 + sideW / 2)
		glass(site, cf, Vector3.new(sideW, H - 1.2, 0.3), Vector3.new(cx, (H - 1.2) / 2 + 1.1, D / 2 - 0.5))
		mullions(site, cf, "x", sx > 0 and doorW / 2 or -W / 2 + 1, sx > 0 and W / 2 - 1 or -doorW / 2, D / 2 - 0.5, 1.1, H - 0.1, 3.6)
		s({ Name = "DoorFrame", Size = Vector3.new(0.5, doorH, 0.5), CFrame = cf * CFrame.new(sx * doorW / 2, doorH / 2 + 1, D / 2 - 0.5), Color = MULLION, Material = Enum.Material.Metal })
	end
	glass(site, cf, Vector3.new(doorW, H - doorH - 1.2, 0.3), Vector3.new(0, doorH + 1 + (H - doorH - 1.2) / 2, D / 2 - 0.5))
	s({ Name = "Roof", Size = Vector3.new(W + 3, 0.7, D + 3), CFrame = cf * CFrame.new(0, H + 0.85, 0), Color = WHITE, CastShadow = true })
	s({ Name = "Reveal", Size = Vector3.new(W + 0.2, 0.5, D + 0.2), CFrame = cf * CFrame.new(0, H + 0.3, 0), Color = CHARCOAL })
	s({ Name = "Canopy", Size = Vector3.new(doorW + 4, 0.5, 4), CFrame = cf * CFrame.new(0, doorH + 1.35, D / 2 + 1.5), Color = CHARCOAL })
	-- ceiling light strips: on while the space is open to build in
	for _, z in ipairs({ -D / 4, D / 4 }) do
		s({ Name = "SuiteLight", Size = Vector3.new(W * 0.6, 0.2, 1.2), CFrame = cf * CFrame.new(0, H + 0.02, z),
			Color = Color3.fromRGB(255, 246, 228), Material = Enum.Material.Neon })
	end
	-- a leasing sign over the door, like a real vacant unit
	local board = s({ Name = "GateSign", Size = Vector3.new(16, 1.9, 0.25), CFrame = cf * CFrame.new(0, H - 0.6, D / 2 - 0.2), Color = CHARCOAL })
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0
	sg.MaxDistance = 200
	sg.Parent = board
	local main = Instance.new("TextLabel")
	main.Name = "Main"
	main.BackgroundTransparency = 1
	main.Size = UDim2.new(0.6, 0, 0.62, 0)
	main.Position = UDim2.new(0.03, 0, 0.19, 0)
	main.TextScaled = true
	main.TextXAlignment = Enum.TextXAlignment.Left
	main.FontFace = MONT
	main.TextColor3 = WHITE
	main.Text = "SPACE AVAILABLE"
	main.Parent = sg
	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.BackgroundTransparency = 1
	sub.Size = UDim2.new(0.34, 0, 0.5, 0)
	sub.Position = UDim2.new(0.63, 0, 0.25, 0)
	sub.TextScaled = true
	sub.TextXAlignment = Enum.TextXAlignment.Right
	sub.FontFace = MONT
	sub.TextColor3 = Color3.fromRGB(255, 208, 70)
	sub.Text = ""
	sub.Parent = sg
	-- two potted plants by the door: someone looks after this building
	furn("pottedPlant", cf * CFrame.new(-(doorW / 2 + 2), 0.6, D / 2 + 1.6), site)
	furn("pottedPlant", cf * CFrame.new(doorW / 2 + 2, 0.6, D / 2 + 1.6), site)
	-- glass never blocks the BUILD prompt or a click from outside
	for _, d in ipairs(site:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "Glass" or d.Name == "Mullion") then d.CanQuery = false end
	end
	-- slot.text is the small right-hand line (SiliconCore writes "BUILD HERE" there)
	return pad, sub
end

--[[ What every empty lot says right now: COMING SOON before the lot opens,
+ BUILD HERE (with the crane) while you can build, HQ LEVEL n when the HQ
caps it. Called from the objective tick; writes only when something changed. ]]
function CampusArch.lotState(plot, unlocked, cap, nextHq)
	local built = 0
	for _, sl in ipairs(plot.slots or {}) do if sl.built then built += 1 end end
	local state = (not unlocked) and "soon" or ((built < cap) and "open" or "locked")
	-- texts are written every call (other code writes slot.text too; an unchanged
	-- property set is free), the lights only when the state changes
	local key = state .. ":" .. built .. ":" .. tostring(nextHq)
	local changed = plot.lotKey ~= key
	plot.lotKey = key
	for _, sl in ipairs(plot.slots or {}) do
		if not sl.built and sl.pad then
			local site = plot.slotFolder and plot.slotFolder:FindFirstChild(sl.pad.Name .. "Edge")
			local sub = site and site:FindFirstChild("Sub", true)
			local main = site and site:FindFirstChild("Main", true)
			if main then
				main.Text = (state == "open" and "SPACE AVAILABLE") or (state == "locked" and "RESERVED") or "COMING SOON"
			end
			if sub then
				sub.Text = (state == "open" and "BUILD HERE") or (state == "locked" and ("UNLOCKS AT HQ " .. tostring(nextHq or "?"))) or "SHIP AN APP"
			end
			-- v4.0: an open suite is lit; a reserved one is a dark, finished shell
			if site and changed then
				for _, p in ipairs(site:GetChildren()) do
					if p.Name == "SuiteLight" then
						p.Material = (state == "open") and Enum.Material.Neon or Enum.Material.SmoothPlastic
						p.Color = (state == "open") and Color3.fromRGB(255, 246, 228) or Color3.fromRGB(150, 148, 144)
					end
				end
			end
		end
	end
	return state
end

--[[ v3.6 PLAN v6 phase V3: THE HQ AS ARCHITECTURE (blender/hq.py).
One Blender shell per HQ level, modelled around the EXACT footprint
SiliconCore's buildShell already uses. The part-built envelope stays as
INVISIBLE collision (walls, roof, glass runs, header, parapet), every
decorative part it drew (mullions, fins, bands, canopies, rooftop plant) is
removed, and two meshes take over the look: HQ_<n>_Shell (opaque, vertex
coloured, contact-shaded) and HQ_<n>_Glass (made Glass + tint here, so the
night glow in SkyClient picks it up). Level 1 also welds a sectional door
leaf to each door part and fades it as the door rolls up: the parts still
slide up 11 studs, which would push a visible door through a real roof.
Nothing imported = nothing changes (same rule as svMesh for the trees). ]]
local HQ_MESH = require(script.Parent:WaitForChild("HQMeta"))   -- generated by blender/hq.py + hq2.py
local HQ_MESH_FLIP = 0          -- math.pi if an import ever lands facing the back
local HQ_GLASS_COLOR = Color3.fromRGB(132, 172, 190)   -- ART.md tinted glass, a touch lighter for Roblox's glass shader
local HQ_GLASS_T = 0.45
-- the envelope: kept, invisible, still collides
local HQ_COLLIDE = { WallBack = true, WallL = true, WallR = true, Roof = true, FrontWall = true, FrontGlass = true,
	SideGlass = true, EntranceHeader = true, Parapet = true, DoorHeader = true }
-- decoration the mesh now draws: removed
local HQ_DECOR = { Reveal = true, Mullion = true, BackFin = true, BackBand = true, BackDoor = true, BackCanopy = true,
	BackCanopyEdge = true, Canopy = true, CanopyEdge = true, RoofUnit1 = true, RoofUnit2 = true, Solar = true }

local function hqMesh(name)
	local lib = RS:FindFirstChild("SVMeshes")
	local t = lib and lib:FindFirstChild(name)
	if not t then return nil end
	local src = t:IsA("BasePart") and t or t:FindFirstChildWhichIsA("MeshPart", true)
	if not src then return nil end
	local m = src:Clone()
	m.Name = name
	m.PivotOffset = CFrame.new()          -- the importer's 90-degree pivot (Phase W quirk 1)
	m.Anchored = true
	m.CanCollide = false
	m.CanQuery = false
	m.CanTouch = false
	m.Massless = true
	m.Color = Color3.new(1, 1, 1)         -- vertex colours carry the look
	local want = HQ_MESH[name] and HQ_MESH[name].s
	if want and (m.Size - want).Magnitude > 1.5 then
		warn(("[SV] %s imported at %s, modelled at %s: check the import axes"):format(name, tostring(m.Size), tostring(want)))
	end
	return m
end

function CampusArch.skinHQ(plot, level, w, d, h, parent)
	-- v4.0: the rebuilt HQ (hq2.py) wins when it is imported; else the V3 shell
	local lib = RS:FindFirstChild("SVMeshes")
	local ver = (level >= 2 and HQ_MESH["HQv2_" .. level .. "_Shell"] and lib and lib:FindFirstChild("HQv2_" .. level .. "_Shell")) and "HQv2_" or "HQ_"
	local shellName = ver .. level .. "_Shell"
	local shell = HQ_MESH[shellName] and hqMesh(shellName)
	if not shell then return false end
	local g = plot.g
	local list = plot.hq.shell
	-- 1. the envelope goes invisible (collision kept); the decoration goes
	for i = #list, 1, -1 do
		local p = list[i]
		if HQ_COLLIDE[p.Name] then
			p.Transparency = 1
			p.CastShadow = false
		elseif HQ_DECOR[p.Name] then
			p:Destroy()
			table.remove(list, i)
		end
	end
	-- 2. the meshes, centred where hq.py measured them (Roblox recentres an import)
	local function put(m, name)
		local c = HQ_MESH[name].c
		m.CFrame = g(c.X, c.Y, c.Z) * CFrame.Angles(0, HQ_MESH_FLIP, 0)
		m.Parent = parent
		table.insert(list, m)
	end
	shell.CastShadow = true
	put(shell, shellName)
	local glassName = ver .. level .. "_Glass"
	local glass = HQ_MESH[glassName] and hqMesh(glassName)
	if glass then
		glass.Material = Enum.Material.Glass
		glass.Color = HQ_GLASS_COLOR
		glass.Transparency = HQ_GLASS_T
		glass.CastShadow = false
		put(glass, glassName)
	end
	-- 3. the name plate: over the garage door, or on its roof frame clear of the parapet
	local plate = plot.signPlate
	if plate then
		if level == 1 then
			plate.CFrame = g(0, h - 1.3, d / 2 + 0.75)
		else
			plate.CFrame = g(0, h + 1.0 + (level >= 3 and 1.4 or 0) + 1.8, d / 2 - 0.8)   -- hq.py plate_c
		end
	end
	-- 4. level 1: a sectional door leaf on each door part
	if level == 1 then
		local TweenService = game:GetService("TweenService")
		for _, door in ipairs({ plot.hq.doorL, plot.hq.doorR }) do
			local leaf = door and hqMesh("HQ_1_Door")
			if leaf then
				door.Transparency = 1
				door.CastShadow = false
				leaf.Anchored = false
				leaf.CastShadow = true
				leaf.CFrame = door.CFrame * CFrame.new(HQ_MESH.HQ_1_Door.c) * CFrame.Angles(0, HQ_MESH_FLIP, 0)
				local wc = Instance.new("WeldConstraint")
				wc.Part0, wc.Part1 = door, leaf
				wc.Parent = leaf
				leaf.Parent = door                  -- destroyed with the door
				if plot.doorOpened then
					leaf.Transparency = 1
				else
					local y0 = door.Position.Y
					local conn
					conn = door:GetPropertyChangedSignal("CFrame"):Connect(function()
						local dy = door.Position.Y - y0
						if dy > 5 then                  -- set in one step (load, spin-off): already open
							conn:Disconnect()
							leaf.Transparency = 1
						elseif dy > 0.05 then           -- rolling up: fade as it goes
							conn:Disconnect()
							TweenService:Create(leaf, TweenInfo.new(1.4, Enum.EasingStyle.Quad), { Transparency = 1 }):Play()
						end
					end)
				end
			end
		end
	end
	return true
end


return CampusArch
