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
local LEAF_D = Color3.fromRGB(62, 142, 76)
local STEEL = Color3.fromRGB(150, 155, 162)
local CHARCOAL = Color3.fromRGB(58, 62, 70)
local HEDGE = Color3.fromRGB(74, 132, 66)
local LAMP_GLASS = Color3.fromRGB(255, 240, 205)
local JOINT = Color3.fromRGB(182, 174, 158)
local LINE = Color3.fromRGB(238, 234, 222)

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

--[[ A TREE, not a lollipop. The first version was one 15-stud sphere on a
	square 11-stud post: at eye level that reads as a plank holding a balloon,
	and 24 identical ones read as wallpaper. This is a tapered trunk and three
	offset masses of falling size, seeded off its own position so no two in the
	ring are the same. ]]
local function tree(parent, x, z, s, seed)
	s = s or 1
	local rng = Random.new(seed or math.floor(x * 31 + z * 17))
	local h = (9 + rng:NextNumber() * 2.5) * s
	part(parent, {
		Name = "ParkTrunk", Size = Vector3.new(2.2 * s, h * 0.55, 2.2 * s),
		CFrame = CFrame.new(x, h * 0.275, z), Color = TRUNK, Material = Enum.Material.Wood,
	})
	part(parent, {
		Name = "ParkTrunk", Size = Vector3.new(1.5 * s, h * 0.6, 1.5 * s),
		CFrame = CFrame.new(x, h * 0.72, z), Color = TRUNK, Material = Enum.Material.Wood,
	})
	local lift = h * 0.95
	local masses = { { 0, 0, 8.2 }, { 2.1, -1.4, 6.0 }, { -1.9, 1.7, 5.4 } }
	for i, m in ipairs(masses) do
		local w = m[3] * s * (0.92 + rng:NextNumber() * 0.2)
		part(parent, {
			Name = "ParkLeaf", Size = Vector3.new(w, w * 0.86, w),
			CFrame = CFrame.new(x + m[1] * s, lift + (i == 1 and w * 0.34 or w * 0.12) + rng:NextNumber() * 1.4, z + m[2] * s),
			Color = (i == 1) and LEAF or LEAF_D, Material = Enum.Material.Grass,
			Shape = Enum.PartType.Ball,
		})
	end
end

-- a bench with a seat, a back, arms and legs: the old one was two slabs
local function bench(parent, x, z, yaw)
	local base = CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0)
	local function at(dx, dy, dz, sx, sy, sz, col, name)
		part(parent, {
			Name = name, Size = Vector3.new(sx, sy, sz),
			CFrame = base * CFrame.new(dx, dy, dz), Color = col,
			Material = (col == OAK) and Enum.Material.Wood or Enum.Material.Metal,
		})
	end
	for i, dz in ipairs({ -0.85, 0, 0.85 }) do
		at(0, 2.5, dz, 7.6, 0.4, 0.68, OAK, "BenchSlat")
	end
	for i, dy in ipairs({ 3.3, 4.1 }) do
		at(0, dy, -1.35, 7.6, 0.55, 0.35, OAK, "BenchBack")
	end
	for _, dx in ipairs({ -3.4, 3.4 }) do
		at(dx, 1.25, 0, 0.42, 2.5, 2.3, STEEL, "BenchLeg")
		at(dx, 3.0, -0.55, 0.38, 1.6, 1.3, STEEL, "BenchArm")
	end
end

local function bollard(parent, x, z)
	part(parent, {
		Name = "Bollard", Size = Vector3.new(1.0, 3.6, 1.0),
		CFrame = CFrame.new(x, 1.8, z), Color = STEEL, Material = Enum.Material.Metal,
	})
	part(parent, {
		Name = "BollardCap", Size = Vector3.new(1.3, 0.35, 1.3),
		CFrame = CFrame.new(x, 3.75, z), Color = CHARCOAL, Material = Enum.Material.Metal,
	})
end

local function litterBin(parent, x, z)
	part(parent, {
		Name = "Bin", Size = Vector3.new(2.4, 3.4, 2.4),
		CFrame = CFrame.new(x, 1.7, z), Color = CHARCOAL, Material = Enum.Material.Metal,
	})
	part(parent, {
		Name = "BinLid", Size = Vector3.new(2.8, 0.4, 2.8),
		CFrame = CFrame.new(x, 3.6, z), Color = STEEL, Material = Enum.Material.Metal,
	})
end

local function parkLamp(parent, x, z)
	part(parent, {
		Name = "ParkLampBase", Size = Vector3.new(1.5, 1.0, 1.5),
		CFrame = CFrame.new(x, 0.5, z), Color = CHARCOAL, Material = Enum.Material.Metal,
	})
	part(parent, {
		Name = "ParkLampPost", Size = Vector3.new(0.6, 15, 0.6),
		CFrame = CFrame.new(x, 8, z), Color = CHARCOAL, Material = Enum.Material.Metal,
	})
	part(parent, {
		Name = "ParkLampHead", Size = Vector3.new(2.2, 1.4, 2.2),
		CFrame = CFrame.new(x, 15.6, z), Color = LAMP_GLASS, Material = Enum.Material.Neon,
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

	--[[ OUTWARD FROM THE MIDDLE.

	The first pass laid this out as four flat discs of one colour, and at eye
	level it was a white plane with a lollipop tree on it. Everything below is
	about giving the eye something to measure: a kerb wherever one material
	meets another, banding so the paving has a grain, step nosings so the tiers
	read as steps from the side, and a hedge so the lawn has an edge instead of
	fading into stone. ]]

	-- the sunken court and the three tiers down to it
	flatDisc(f, "ParkCourt", R_COURT, 0.4, 0.5, PAVE_W)
	ring(f, "ParkTier3", (R_COURT + R_STEP - 38) / 2, (R_STEP - 38) - R_COURT, 0.4, 1.4, PAVE)
	ring(f, "ParkTier2", (R_STEP - 38 + R_STEP - 20) / 2, 18, 1.0, 1.6, PAVE_D)
	ring(f, "ParkTier1", (R_STEP - 20 + R_STEP) / 2, 20, 2.0, 1.8, PAVE)
	-- a pale nosing on each tread edge: without it the steps vanish side-on
	for _, nz in ipairs({ { R_STEP - 38, 1.8 }, { R_STEP - 20, 2.6 }, { R_STEP, 3.8 } }) do
		ring(f, "ParkNosing", nz[1] - 0.9, 2.2, nz[2] - 0.35, 0.4, PAVE_W, { seg = 40 })
	end

	-- the lawn, kerbed on both sides and hedged on the outside
	ring(f, "ParkKerbIn", R_STEP + 1.6, 3.2, 3.2, 1.5, CONCRETE, { seg = 40 })
	ring(f, "ParkLawn", (R_STEP + R_PARK - 36) / 2, (R_PARK - 36) - R_STEP, 3.2, 1.2, LAWN,
		{ material = Enum.Material.Grass })
	ring(f, "ParkKerbMid", R_PARK - 37, 3.2, 3.2, 1.5, CONCRETE, { seg = 40 })
	ring(f, "ParkHedge", R_PARK - 39.5, 4.0, 4.4, 3.2, HEDGE, { material = Enum.Material.Grass, seg = 40 })

	-- the outer walk: banded, so a 32-stud ring of stone has a grain
	ring(f, "ParkWalk", R_PARK - 28, 14, 3.2, 1.3, PAVE, { seg = 44 })
	ring(f, "ParkWalkBand", R_PARK - 20, 2.0, 3.2, 1.35, JOINT, { seg = 44 })
	ring(f, "ParkWalk", R_PARK - 12, 14, 3.2, 1.3, PAVE_D, { seg = 44 })
	ring(f, "ParkKerb", R_PARK, 7, 3.2, 2.0, CONCRETE)
	-- radial joints across the walk, every 15 degrees
	for i = 0, 23 do
		local a = i * math.pi / 12
		part(f, {
			Name = "ParkJoint",
			Size = Vector3.new(32, 1.42, 0.7),
			CFrame = CFrame.new(math.cos(a) * (R_PARK - 20), 3.9, math.sin(a) * (R_PARK - 20)) * CFrame.Angles(0, -a, 0),
			Color = JOINT,
		})
	end

	-- eight walks cutting the lawn ring, so the park is crossed not skirted
	for i = 0, 7 do
		local a = i * math.pi / 4
		local rMid = (R_STEP + R_PARK - 36) / 2
		part(f, {
			Name = "ParkPath",
			-- X is radial (the path's length), Z is tangential (its width)
			Size = Vector3.new((R_PARK - 36) - R_STEP + 4, 1.4, 14),
			CFrame = CFrame.new(math.cos(a) * rMid, 3.9, math.sin(a) * rMid) * CFrame.Angles(0, -a, 0),
			Color = PAVE_W,
		})
		for _, side in ipairs({ -7.6, 7.6 }) do
			part(f, {
				Name = "ParkPathKerb",
				Size = Vector3.new((R_PARK - 36) - R_STEP + 4, 1.9, 1.2),
				CFrame = CFrame.new(math.cos(a) * rMid, 4.1, math.sin(a) * rMid)
					* CFrame.Angles(0, -a, 0) * CFrame.new(0, 0, side),
				Color = CONCRETE,
			})
		end
	end

	-- four reflecting pools on the diagonals, each with a raised stone lip
	for i = 0, 3 do
		local a = math.pi / 4 + i * math.pi / 2
		local rMid = (R_STEP + R_PARK - 36) / 2
		local base = CFrame.new(math.cos(a) * rMid, 0, math.sin(a) * rMid) * CFrame.Angles(0, -a, 0)
		part(f, { Name = "PoolLip", Size = Vector3.new(50, 2.2, 38), CFrame = base * CFrame.new(0, 4.3, 0), Color = CONCRETE })
		part(f, {
			Name = "ParkPool", Size = Vector3.new(44, 1.0, 32), CFrame = base * CFrame.new(0, 5.0, 0),
			Color = WATER, Material = Enum.Material.Glass, Transparency = 0.25,
		})
	end

	--[[ THE FOUNTAIN. Three basins falling into each other, which is what makes
	a fountain read as a fountain rather than a lit puddle: a wide low pool, a
	stem, a mid bowl, and a crown bowl under the monument. ]]
	flatDisc(f, "FountainBasin", 22, 0.4, 2.2, CONCRETE)
	flatDisc(f, "FountainWater", 19, 1.4, 1.0, WATER, { material = Enum.Material.Glass })
	ring(f, "FountainLip", 21, 2.6, 0.4, 2.6, PAVE_W, { seg = 36 })
	flatDisc(f, "FountainStem", 5.5, 2.4, 6.0, CONCRETE)
	flatDisc(f, "FountainBowl2", 11, 8.4, 1.3, CONCRETE)
	flatDisc(f, "FountainWater2", 9.4, 9.0, 0.8, WATER, { material = Enum.Material.Glass })
	flatDisc(f, "FountainStem2", 3.2, 9.4, 4.6, CONCRETE)
	flatDisc(f, "FountainBowl3", 6.4, 13.6, 1.1, CONCRETE)
	flatDisc(f, "FountainWater3", 5.2, 14.1, 0.7, WATER, { material = Enum.Material.Glass })
	for i = 0, 7 do
		local a = i * math.pi / 4
		part(f, {
			Name = "FountainJet", Size = Vector3.new(0.8, 7 + (i % 3) * 3, 0.8),
			CFrame = CFrame.new(math.cos(a) * 13, 4.5, math.sin(a) * 13),
			Color = WATER, Material = Enum.Material.Glass, Transparency = 0.45,
		})
	end
	part(f, { Name = "Monument", Size = Vector3.new(4.2, 26, 4.2), CFrame = CFrame.new(0, 27, 0), Color = PAVE_W })
	part(f, { Name = "MonumentCap", Size = Vector3.new(8, 3.6, 8), CFrame = CFrame.new(0, 41.5, 0), Color = GOLD, Material = Enum.Material.Neon })

	-- seating on the tiers, facing the water
	for i = 0, 11 do
		local a = i * math.pi / 6 + 0.13
		bench(f, math.cos(a) * (R_STEP - 9), math.sin(a) * (R_STEP - 9), -a + math.pi / 2)
	end
	-- the tree walk, with lamps, bins and bollards along the kerb
	for i = 0, 23 do
		local a = i * math.pi / 12
		tree(f, math.cos(a) * (R_PARK - 20), math.sin(a) * (R_PARK - 20), 1.0, i * 977)
	end
	for i = 0, 11 do
		local a = i * math.pi / 6 + math.pi / 12
		parkLamp(f, math.cos(a) * (R_PARK - 6), math.sin(a) * (R_PARK - 6))
	end
	for i = 0, 7 do
		local a = i * math.pi / 4 + math.pi / 8
		litterBin(f, math.cos(a) * (R_PARK - 8), math.sin(a) * (R_PARK - 8))
	end
	for i = 0, 35 do
		local a = i * math.pi / 18
		bollard(f, math.cos(a) * (R_PARK + 5), math.sin(a) * (R_PARK + 5))
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

	--[[ KERBS AND MARKINGS (pass 2).

	A road is not a grey slab lying on grass. Without a kerb the asphalt has no
	edge, so the eye reads it as a texture change rather than a surface you
	stand above -- which is exactly how the radial streets looked: paint on a
	lawn. Every carriageway now has a raised kerb on both sides, a centre line,
	and a crossing where it meets a ring. ]]
	local ROAD_HALF = CampusHub.ROAD_W / 2

	local function kerbRing(r, seg)
		ring(f, "RoadKerb", r, 2.4, 0, 1.5, CONCRETE, { seg = seg })
	end
	kerbRing(CampusHub.R_ROAD_IN - ROAD_HALF - 1.2, 56)
	kerbRing(CampusHub.R_ROAD_IN + ROAD_HALF + 1.2, 56)
	kerbRing(CampusHub.R_ROAD_OUT - ROAD_HALF - 1.2, 72)
	kerbRing(CampusHub.R_ROAD_OUT + ROAD_HALF + 1.2, 72)
	-- centre lines, solid: dashes round a 3700-stud circumference cost hundreds
	-- of parts and read the same at the distance anyone sees them from
	ring(f, "RoadLine", CampusHub.R_ROAD_IN, 0.9, 1.0, 0.12, LINE, { seg = 64 })
	ring(f, "RoadLine", CampusHub.R_ROAD_OUT, 0.9, 1.0, 0.12, LINE, { seg = 80 })
	-- a verge of grass between the outer kerb and the bare valley, so the road
	-- does not end in dirt
	ring(f, "RoadVerge", CampusHub.R_ROAD_OUT + ROAD_HALF + 10, 16, 0, 0.9, LAWN,
		{ material = Enum.Material.Grass, seg = 72 })
	ring(f, "RoadVerge", CampusHub.R_ROAD_IN - ROAD_HALF - 10, 14, 0, 0.9, LAWN,
		{ material = Enum.Material.Grass, seg = 56 })

	-- a radial street out to each plot, so the ring is reachable by car
	local CFG = require(script.Parent:WaitForChild("CoreConfig"))
	for i = 0, 5 do
		local a = math.rad(30 + i * 60)
		local r0, r1 = CampusHub.R_ROAD_IN, CampusHub.R_ROAD_OUT
		local rMid = (r0 + r1) / 2
		local base = CFrame.new(math.cos(a) * rMid, 0, math.sin(a) * rMid) * CFrame.Angles(0, -a + math.pi / 2, 0)
		-- base's local X is tangential (across the street), local Z is radial
		-- (along it), the same axis order the rings use
		local street = part(f, {
			Name = "RingStreet",
			Size = Vector3.new(CampusHub.ROAD_W, 1.0, r1 - r0),
			CFrame = base * CFrame.new(0, 0.5, 0),
			Color = ASPHALT, Material = Enum.Material.Asphalt,
			CanCollide = true, CanQuery = true,
		})
		CollectionService:AddTag(street, "SVRoad")

		for _, side in ipairs({ -1, 1 }) do
			part(f, {
				Name = "StreetKerb",
				Size = Vector3.new(2.4, 1.5, r1 - r0),
				CFrame = base * CFrame.new(side * (ROAD_HALF + 1.2), 0.75, 0),
				Color = CONCRETE,
			})
			part(f, {
				Name = "StreetWalk",
				Size = Vector3.new(14, 1.2, r1 - r0 - 30),
				CFrame = base * CFrame.new(side * (ROAD_HALF + 9.6), 0.6, 0),
				Color = PAVE_D,
			})
			part(f, {
				Name = "StreetVerge",
				Size = Vector3.new(10, 0.9, r1 - r0 - 30),
				CFrame = base * CFrame.new(side * (ROAD_HALF + 21), 0.45, 0),
				Color = LAWN, Material = Enum.Material.Grass,
			})
		end
		-- dashed centre line: a straight street is short enough to afford it
		local len = r1 - r0
		local n = math.floor(len / 26)
		for k = 0, n - 1 do
			part(f, {
				Name = "StreetLine",
				Size = Vector3.new(0.9, 0.12, 12),
				CFrame = base * CFrame.new(0, 1.0, -len / 2 + 13 + k * 26),
				Color = LINE,
			})
		end
		-- a crossing at each end, where the street meets a ring road
		for _, endZ in ipairs({ -len / 2 + 16, len / 2 - 16 }) do
			for b = -2, 2 do
				part(f, {
					Name = "Crossing",
					Size = Vector3.new(3.0, 0.14, 11),
					CFrame = base * CFrame.new(b * 5.2, 1.0, endZ),
					Color = LINE,
				})
			end
		end
		-- street trees along the walk, and a lamp at the midpoint
		for k = 0, 3 do
			local z = -len / 2 + 60 + k * ((len - 120) / 3)
			for _, side in ipairs({ -1, 1 }) do
				local wp = (base * CFrame.new(side * (ROAD_HALF + 9.6), 0, z)).Position
				tree(f, wp.X, wp.Z, 0.85, i * 131 + k * 7 + (side > 0 and 1 or 0))
			end
		end
	end
	--[[ TRAFFIC ON THE RINGS (pass 3).

	Cars are placed once here and moved by every client (TrafficClient), which
	is why they are anchored, no-collide and no-query: scenery that moves, never
	an obstacle. A ring car carries RingR (its radius) and RingDir instead of
	LaneA/LaneB, because a straight lane cannot describe a circle.

	One speed per lane and even spacing, the rule v1.7 established for the
	straight road: random per-car speed made cars in a lane drive through each
	other. Inner ring runs one way, outer the other, so the campus reads as a
	one-way gyratory rather than two lanes of oncoming traffic 26 studs apart. ]]
	local kit = game:GetService("ReplicatedStorage"):FindFirstChild("KenneyKit")
	local CAR_NAMES = { "sedan", "sedan-sports", "hatchback-sports", "suv", "taxi", "van", "delivery", "truck" }
	local rng = Random.new(4242)
	local laneId = 900
	local function ringLane(r, dir, count, speed, y)
		if not kit then return 0 end
		laneId = laneId + 1
		local made = 0
		local len = 2 * math.pi * r
		for k = 1, count do
			local t = kit:FindFirstChild(CAR_NAMES[rng:NextInteger(1, #CAR_NAMES)])
			if t then
				local m = t:Clone()
				m.Name = "RingCar"
				if m:IsA("Model") then
					m:ScaleTo(0.05)
					for _, d in ipairs(m:GetDescendants()) do
						if d:IsA("BasePart") then
							d.Anchored = true
							d.CanCollide = false
							d.CanQuery = false
							d.CanTouch = false
							d.CastShadow = false
						end
					end
					m:PivotTo(CFrame.new(r, y, 0))
					m:SetAttribute("RingR", r)
					m:SetAttribute("RingDir", dir)
					m:SetAttribute("LaneId", laneId)
					m:SetAttribute("Speed", speed)
					m:SetAttribute("Phase", (k - 1) * (len / count))
					m.Parent = f
					CollectionService:AddTag(m, "TrafficCar")
					made = made + 1
				end
			end
		end
		return made
	end
	local carY = 1.9
	local nCars = 0
	nCars = nCars + ringLane(CampusHub.R_ROAD_IN - 7, 1, 7, 26, carY)
	nCars = nCars + ringLane(CampusHub.R_ROAD_IN + 7, 1, 7, 30, carY)
	nCars = nCars + ringLane(CampusHub.R_ROAD_OUT - 7, -1, 12, 34, carY)
	nCars = nCars + ringLane(CampusHub.R_ROAD_OUT + 7, -1, 12, 38, carY)
	CampusHub.cars = nCars

	--[[ BUS STOPS AND SIGNS. A road with nothing beside it is a conveyor; a
	shelter and a sign are what say people arrive here. One stop on the inner
	ring at each district gap, and a fingerpost at every radial street mouth. ]]
	for i = 0, 5 do
		local a = math.rad(i * 60)                       -- the gaps, where the districts are
		local rr = CampusHub.R_ROAD_IN + 24
		local base = CFrame.new(math.cos(a) * rr, 0, math.sin(a) * rr) * CFrame.Angles(0, -a + math.pi / 2, 0)
		part(f, { Name = "StopPad", Size = Vector3.new(22, 1.3, 9), CFrame = base * CFrame.new(0, 0.65, 0), Color = PAVE_W })
		part(f, { Name = "StopRoof", Size = Vector3.new(18, 0.6, 7), CFrame = base * CFrame.new(0, 10.4, 0), Color = CHARCOAL })
		for _, dx in ipairs({ -8, 8 }) do
			part(f, { Name = "StopPost", Size = Vector3.new(0.5, 9.5, 0.5), CFrame = base * CFrame.new(dx, 5.4, -2.6), Color = STEEL, Material = Enum.Material.Metal })
			part(f, { Name = "StopPost", Size = Vector3.new(0.5, 9.5, 0.5), CFrame = base * CFrame.new(dx, 5.4, 2.6), Color = STEEL, Material = Enum.Material.Metal })
		end
		part(f, { Name = "StopGlass", Size = Vector3.new(17, 7.4, 0.3), CFrame = base * CFrame.new(0, 5.4, 3.0),
			Color = Color3.fromRGB(180, 212, 228), Material = Enum.Material.Glass, Transparency = 0.5 })
		part(f, { Name = "StopBench", Size = Vector3.new(13, 0.5, 2.0), CFrame = base * CFrame.new(0, 3.2, 1.6), Color = OAK, Material = Enum.Material.Wood })
	end
	for i = 0, 5 do
		local a = math.rad(30 + i * 60)                  -- the streets, where the plots are
		local rr = CampusHub.R_ROAD_IN + 26
		local base = CFrame.new(math.cos(a) * rr, 0, math.sin(a) * rr) * CFrame.Angles(0, -a + math.pi / 2, 0)
		for _, dx in ipairs({ -22, 22 }) do
			part(f, { Name = "SignPost", Size = Vector3.new(0.5, 13, 0.5), CFrame = base * CFrame.new(dx, 6.5, 0), Color = STEEL, Material = Enum.Material.Metal })
			part(f, { Name = "SignBlade", Size = Vector3.new(9, 2.4, 0.3), CFrame = base * CFrame.new(dx, 12, 0), Color = CHARCOAL })
		end
	end

	-- `CFG` is read so a future change to PLOT_RING_R is visible here; the
	-- streets use the same angles the plots do.
	assert(CFG.PLOT_RING_R, "CoreConfig must export PLOT_RING_R")

	return f
end

return CampusHub
