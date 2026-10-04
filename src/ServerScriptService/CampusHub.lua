--[[
	CampusHub -- the middle of the map.

	The six plots moved from two rows along a straight road onto a RING facing a
	shared centre (CoreConfig.PLOT_DEFS). This builds what that ring is around:
	a central park, and the two ring roads that serve it.

	Why the park is not a flat lawn. A disc of grass reads as a gap between
	buildings; a place reads as somewhere you go DOWN into and sit. So the
	middle steps down three courses to a sunken court with a fountain and a
	monument, with seating on the tiers. The rings around it, outward:

	    outer kerb .... tree walk .... reflecting pools and lawn
	    .... ring walk .... three tiers down .... fountain court

	Everything here is scenery: no prompts, no collisions the player can be
	trapped by, nothing saved. The park exists so the six towers have something
	to be a ring AROUND, and so a player walking out of their lobby has
	somewhere to walk to.

	BUDGET. This runs on phones. Every part here is CanCollide/CanQuery false
	except the ground the player stands on, CastShadow is off on everything
	small, and the whole hub is about 400 parts -- measured against the <1000
	draw call budget the valley already spends ~250-450 of.
]]

local CollectionService = game:GetService("CollectionService")

local CampusHub = {}

CampusHub.R_COURT = 40
CampusHub.R_STEP = 96
CampusHub.R_PARK = 162
CampusHub.R_ROAD_IN = 208
CampusHub.R_DIST = 452        -- the district band: shop, dealership, apartments, parking
CampusHub.R_ROAD_OUT = 596
CampusHub.ROAD_W = 26

local PAVE = Color3.fromRGB(222, 215, 200)
local PAVE_D = Color3.fromRGB(196, 188, 172)
local PAVE_W = Color3.fromRGB(236, 231, 220)
local CONCRETE = Color3.fromRGB(207, 198, 182)
local LAWN = Color3.fromRGB(122, 170, 80)
local WATER = Color3.fromRGB(96, 164, 196)
local ASPHALT = Color3.fromRGB(64, 64, 68)
local GOLD = Color3.fromRGB(224, 182, 90)
local TRUNK = Color3.fromRGB(150, 96, 62)
local LEAF = Color3.fromRGB(78, 168, 92)
local OAK = Color3.fromRGB(192, 138, 85)

local function part(parent, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

--[[ A ring of boxes approximating an annulus.

	A Cylinder part cannot be a ring, and a mesh would need an import, so every
	ring here is `seg` boxes laid round the circle. 48 segments on a 160-stud
	radius leaves a 0.4-stud chord error, which is under the width of the kerb
	it sits in -- invisible, and far cheaper than a mesh pipeline for scenery. ]]
local function ring(parent, name, rMid, width, y, height, colour, opts)
	opts = opts or {}
	local seg = opts.seg or 48
	local made = {}
	local chord = 2 * math.pi * rMid / seg + 0.6      -- +0.6 so neighbours overlap, no seams
	for i = 0, seg - 1 do
		local a = (i + 0.5) * 2 * math.pi / seg
		--[[ AXIS ORDER MATTERS HERE. CFrame.Angles(0, -a, 0) maps local X to the
			RADIAL direction and local Z to the TANGENT, not the other way round.
			Built as (chord, h, width) the segments pointed outward instead of
			along the arc, so the ring became dashes wherever the chord was
			longer than the width -- invisible on the park rings, obvious on the
			outer road where a 52-stud chord left 26-stud gaps. ]]
		local p = part(parent, {
			Name = name,
			Size = Vector3.new(width, height, chord),
			CFrame = CFrame.new(math.cos(a) * rMid, y + height / 2, math.sin(a) * rMid)
				* CFrame.Angles(0, -a, 0),
			Color = colour,
			Material = opts.material or Enum.Material.SmoothPlastic,
			CanCollide = opts.canCollide or false,
			CanQuery = opts.canQuery or false,
		})
		table.insert(made, p)
	end
	return made
end

local function disc(parent, name, r, y, height, colour, opts)
	opts = opts or {}
	return part(parent, {
		Name = name,
		Size = Vector3.new(r * 2, height, r * 2),
		CFrame = CFrame.new(0, y + height / 2, 0),
		Color = colour,
		Shape = Enum.PartType.Cylinder,
		Material = opts.material or Enum.Material.SmoothPlastic,
		CanCollide = opts.canCollide or false,
		CanQuery = opts.canQuery or false,
	})
end

-- a Cylinder part's length is its X axis, so a flat disc has to be stood on end
local function flatDisc(parent, name, r, y, height, colour, opts)
	local p = disc(parent, name, r, y, height, colour, opts)
	p.Size = Vector3.new(height, r * 2, r * 2)
	p.CFrame = CFrame.new(0, y + height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
	return p
end

local function tree(parent, x, z, s)
	s = s or 1
	part(parent, {
		Name = "ParkTreeTrunk",
		Size = Vector3.new(1.8 * s, 11 * s, 1.8 * s),
		CFrame = CFrame.new(x, 5.5 * s, z),
		Color = TRUNK,
		Material = Enum.Material.Wood,
	})
	part(parent, {
		Name = "ParkTreeLeaf",
		Size = Vector3.new(15 * s, 13 * s, 15 * s),
		CFrame = CFrame.new(x, 16 * s, z),
		Color = LEAF,
		Material = Enum.Material.Grass,
		Shape = Enum.PartType.Ball,
	})
end

local function bench(parent, x, z, yaw)
	part(parent, {
		Name = "ParkBench",
		Size = Vector3.new(8, 1.1, 2.4),
		CFrame = CFrame.new(x, 2.6, z) * CFrame.Angles(0, yaw, 0),
		Color = OAK,
		Material = Enum.Material.Wood,
	})
	part(parent, {
		Name = "ParkBenchBack",
		Size = Vector3.new(8, 2.6, 0.5),
		CFrame = CFrame.new(x, 4.0, z) * CFrame.Angles(0, yaw, 0) * CFrame.new(0, 0, -1.0),
		Color = OAK,
		Material = Enum.Material.Wood,
	})
end

--[[ Build the hub into `parent` (the world folder). Idempotent: an existing
	CampusHub folder is destroyed first, so a second Run cannot stack two. ]]
function CampusHub.build(parent)
	local old = parent:FindFirstChild("CampusHub")
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = "CampusHub"
	f.Parent = parent

	local R_COURT, R_STEP, R_PARK = CampusHub.R_COURT, CampusHub.R_STEP, CampusHub.R_PARK

	-- THE WALKING SURFACE. One collidable disc under the whole park, so a
	-- player can never fall between two scenery rings. Everything above it is
	-- CanCollide false, which is also why the steps do not need to be climbed:
	-- the player walks on this and the tiers read as depth.
	flatDisc(f, "ParkFloor", R_PARK + 4, -0.4, 1.2, PAVE_D, { canCollide = true, canQuery = true })

	-- outward from the middle
	flatDisc(f, "ParkCourt", R_COURT, 0.4, 0.5, PAVE_W)
	ring(f, "ParkTier3", (R_COURT + R_STEP - 38) / 2, (R_STEP - 38) - R_COURT, 0.4, 1.4, PAVE)
	ring(f, "ParkTier2", (R_STEP - 38 + R_STEP - 20) / 2, 18, 1.0, 1.6, PAVE_D)
	ring(f, "ParkTier1", (R_STEP - 20 + R_STEP) / 2, 20, 2.0, 1.8, PAVE)
	ring(f, "ParkLawn", (R_STEP + R_PARK - 36) / 2, (R_PARK - 36) - R_STEP, 3.2, 1.2, LAWN,
		{ material = Enum.Material.Grass })
	ring(f, "ParkWalk", R_PARK - 20, 32, 3.2, 1.3, PAVE)
	ring(f, "ParkKerb", R_PARK, 7, 3.2, 2.0, CONCRETE)

	-- eight walks cutting the lawn ring, so the park is crossed not skirted
	for i = 0, 7 do
		local a = i * math.pi / 4
		local rMid = (R_STEP + R_PARK - 36) / 2
		part(f, {
			Name = "ParkPath",
			-- same axis order as the rings: X is radial (the path's length), Z
			-- is tangential (its width)
			Size = Vector3.new((R_PARK - 36) - R_STEP + 4, 1.4, 14),
			CFrame = CFrame.new(math.cos(a) * rMid, 3.9, math.sin(a) * rMid) * CFrame.Angles(0, -a, 0),
			Color = PAVE_W,
		})
	end

	-- four reflecting pools on the diagonals
	for i = 0, 3 do
		local a = math.pi / 4 + i * math.pi / 2
		local rMid = (R_STEP + R_PARK - 36) / 2
		part(f, {
			Name = "ParkPool",
			Size = Vector3.new(46, 1.0, 34),
			CFrame = CFrame.new(math.cos(a) * rMid, 4.0, math.sin(a) * rMid) * CFrame.Angles(0, -a, 0),
			Color = WATER,
			Material = Enum.Material.Glass,
			Transparency = 0.25,
		})
	end

	-- the fountain, and the monument the whole ring points at
	flatDisc(f, "FountainRim", 20, 0.9, 1.4, CONCRETE)
	flatDisc(f, "FountainWater", 16, 1.1, 1.2, WATER, { material = Enum.Material.Glass })
	part(f, {
		Name = "Monument",
		Size = Vector3.new(5, 34, 5),
		CFrame = CFrame.new(0, 18, 0),
		Color = PAVE_W,
	})
	part(f, {
		Name = "MonumentCap",
		Size = Vector3.new(9, 4, 9),
		CFrame = CFrame.new(0, 37, 0),
		Color = GOLD,
		Material = Enum.Material.Neon,
	})

	-- seating on the tiers: an amphitheatre is where people sit
	for i = 0, 11 do
		local a = i * math.pi / 6 + 0.13
		bench(f, math.cos(a) * (R_STEP - 9), math.sin(a) * (R_STEP - 9), -a + math.pi / 2)
	end
	-- the tree walk
	for i = 0, 23 do
		local a = i * math.pi / 12
		tree(f, math.cos(a) * (R_PARK - 20), math.sin(a) * (R_PARK - 20), 1.1)
	end

	-- THE RING ROADS. Collidable so cars drive on them, and tagged so the
	-- traffic client can find them later.
	local inner = ring(f, "RingRoadIn", CampusHub.R_ROAD_IN, CampusHub.ROAD_W, 0, 1.0, ASPHALT,
		{ material = Enum.Material.Asphalt, canCollide = true, canQuery = true, seg = 56 })
	local outer = ring(f, "RingRoadOut", CampusHub.R_ROAD_OUT, CampusHub.ROAD_W, 0, 1.0, ASPHALT,
		{ material = Enum.Material.Asphalt, canCollide = true, canQuery = true, seg = 72 })
	for _, p in ipairs(inner) do
		CollectionService:AddTag(p, "SVRoad")
	end
	for _, p in ipairs(outer) do
		CollectionService:AddTag(p, "SVRoad")
	end

	-- SIDEWALKS beside the inner ring road. LifeClient walks its pedestrians
	-- here, and without them people would be strolling across bare terrain.
	ring(f, "RingWalkIn", CampusHub.R_ROAD_IN - 22, 16, 0, 1.2, PAVE_D, { seg = 56 })
	ring(f, "RingWalkOut", CampusHub.R_ROAD_IN + 22, 16, 0, 1.2, PAVE_D, { seg = 56 })

	-- a radial street out to each plot, so the ring is reachable by car
	local CFG = require(script.Parent:WaitForChild("CoreConfig"))
	for i = 0, 5 do
		local a = math.rad(30 + i * 60)
		local r0, r1 = CampusHub.R_ROAD_IN, CampusHub.R_ROAD_OUT
		local rMid = (r0 + r1) / 2
		local p = part(f, {
			Name = "RingStreet",
			Size = Vector3.new(CampusHub.ROAD_W, 1.0, r1 - r0),
			CFrame = CFrame.new(math.cos(a) * rMid, 0.5, math.sin(a) * rMid) * CFrame.Angles(0, -a + math.pi / 2, 0),
			Color = ASPHALT,
			Material = Enum.Material.Asphalt,
			CanCollide = true,
			CanQuery = true,
		})
		CollectionService:AddTag(p, "SVRoad")
	end
	-- `CFG` is read so a future change to PLOT_RING_R is visible here; the
	-- streets use the same angles the plots do.
	assert(CFG.PLOT_RING_R, "CoreConfig must export PLOT_RING_R")

	return f
end

return CampusHub
