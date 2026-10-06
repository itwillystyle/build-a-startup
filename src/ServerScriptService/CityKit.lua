--[[
	CityKit -- ModuleScript in ServerScriptService.

	The imported Quaternius Downtown City MegaKit (CC0), addressed by asset id
	so the world can be rebuilt from code without dragging anything by hand.

	WHY BACKDROP ONLY. Measured against a 5-stud Roblox character:
	  Door_1 is 4.40 studs tall -- a character CANNOT walk through it
	  Building_Small_1 is 34 studs over 4 storeys = 8.5 studs/storey
	  a player-scale storey wants ~12
	The kit reads about 1.4x small for humans. That is perfect for architecture
	seen from across a road and wrong for anything the player enters. So:

	  CITY  = imported meshes, across the street, never entered
	  GARAGE + ROOMS = script-built primitives at true player scale

	Interiors come from the Kenney Furniture Kit (CC0, imported 12 Sep; see
	FurnitureKit). Roads, cars and street furniture come from the Kenney Car
	Kit + City Kit Roads (CC0, imported 12 Sep) in ReplicatedStorage.KenneyKit.
]]

local CityKit = {}

--[[
	MeshPart.MeshId IS NOT WRITABLE FROM A SCRIPT AT RUNTIME.
	Setting it throws "lacking capability NotAccessible". So the world cannot
	be built from asset ids directly -- it must CLONE templates.

	The imported meshes live in
	  ReplicatedStorage.ImportedMeshes  (moved from ServerStorage when the build
	  mode arrived: the client makes ghosts and thumbnails from these)
	and this table maps a friendly key to the template's instance name.
	Keep the templates. Deleting them breaks the city.
]]
local TEMPLATE_FOLDER = "ImportedMeshes"

CityKit.MESH = {
	building_large   = "Building_Large_2",
	building_medium  = "Building_Medium_2",
	building_small   = "Building_Small_1",
	door             = "Door_1",
	entrance         = "Entrance_Concrete_2x2",
	ac_unit          = "Prop_ACUnit",
	bollard          = "Prop_Bollard",
	planter          = "Prop_Planter_Single",
	sidewalk_planter = "Sidewalk_Planter",
	stairs           = "Stairs_Entrance_Concrete",
	street_2lane     = "Street_2Lane",
	street_4way      = "Street_4WayIntersection",
	street_t         = "Street_TIntersection",
}

local templates
local Pal = (function()
	local ok, m = pcall(require, game:GetService("ReplicatedStorage"):WaitForChild("Palette", 5))
	return ok and m or nil
end)()

local function templateFor(key)
	if not templates then
		templates = game:GetService("ReplicatedStorage"):FindFirstChild(TEMPLATE_FOLDER)
	end
	if not templates then return nil end
	local name = CityKit.MESH[key]
	return name and templates:FindFirstChild(name) or nil
end

-- the measured size of a template, so callers can sit things on the ground
function CityKit.sizeOf(key)
	local t = templateFor(key)
	return t and t.Size or Vector3.new(1, 1, 1)
end

-- ============ SPAWN ============

--[[
	Build a MeshPart from the catalogue.

	EVERY import lands Anchored = false. An unanchored 50-stud building falls
	the instant Play starts and takes the physics solver with it, so anchoring
	is not optional and is done here rather than trusted to the caller.
]]
function CityKit.spawn(key, cframe, parent, opts)
	local t = templateFor(key)
	if not t then
		warn("[CityKit] no template for: " .. tostring(key))
		return nil
	end
	opts = opts or {}

	local m = t:Clone()
	m.Name = opts.name or key
	if opts.scale then m.Size = t.Size * opts.scale end
	m.CFrame = cframe
	m.Anchored = true                      -- never negotiable
	m.CanCollide = opts.canCollide ~= false
	-- backdrop geometry must not eat the camera or raycasts
	m.CanQuery = opts.canQuery ~= false
	m.CastShadow = opts.castShadow == true -- default OFF: this is a lot of mesh
	if opts.color then m.Color = opts.color end
	if opts.material then m.Material = opts.material end
	m.Parent = parent
	return m
end

-- put a mesh on the ground, given the ground height
function CityKit.spawnOnGround(key, x, z, groundY, parent, opts)
	opts = opts or {}
	local h = CityKit.sizeOf(key).Y * (opts.scale or 1)
	local cf = CFrame.new(x, groundY + h / 2, z)
	if opts.yaw then cf = cf * CFrame.Angles(0, math.rad(opts.yaw), 0) end
	return CityKit.spawn(key, cf, parent, opts)
end

-- ============ THE STREET ============

--[[
	The road is the SPINE of the map now, not its edge: six plots sit along it,
	three a side, and downtown is a tower cluster at the east end that you see
	looking down the road from any garage door. Everything is a primitive
	except the rooftop AC units and planters, where the imported kit earns its
	keep.

	opts: z (road centre line), x1..x2 (road extent), towersX (downtown start)
]]
local PALETTE = {
	Color3.fromRGB(210, 206, 198), Color3.fromRGB(146, 158, 172),
	Color3.fromRGB(196, 178, 152), Color3.fromRGB(120, 128, 140),
	Color3.fromRGB(184, 170, 158), Color3.fromRGB(158, 170, 178),
}
local GLASS = Color3.fromRGB(130, 185, 210)

local function prim(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do p[k] = v end
	-- author in the palette: an unnamed Color used to inherit Roblox default grey
	if Pal then
		p.Color = props.Color and Pal.map(props.Color) or Pal.map(Color3.fromRGB(163, 162, 165))
	end
	p.Parent = parent
	return p
end

-- a glass office tower. `face` is the sign of z the glass bands face.
local function tower(folder, groundY, x, z, wq, dq, floorsN, colour, face)
	local fh = 7
	local h = floorsN * fh
	prim({ Name = "Tower", Size = Vector3.new(wq, h, dq), Position = Vector3.new(x, groundY + h / 2, z),
		Color = colour, Material = Enum.Material.Concrete }, folder)
	for k = 1, floorsN do
		prim({ Name = "TowerGlass", Size = Vector3.new(wq - 3, fh - 2.6, 0.3),
			Position = Vector3.new(x, groundY + (k - 0.5) * fh + 0.6, z + face * (dq / 2 + 0.2)),
			CanCollide = false, Color = GLASS, Material = Enum.Material.Glass, Transparency = 0.25 }, folder)
	end
	prim({ Name = "Parapet", Size = Vector3.new(wq + 1.2, 1.4, dq + 1.2),
		Position = Vector3.new(x, groundY + h + 0.7, z), Color = colour }, folder)
	CityKit.spawn("ac_unit", CFrame.new(x + wq * 0.22, groundY + h + 1.6, z - face * dq * 0.15),
		folder, { name = "RoofAC", canQuery = false, canCollide = false })
end

function CityKit.buildStreet(parent, opts)
	opts = opts or {}
	local groundY = opts.groundY or 0
	local z = opts.z or 0
	local x1, x2 = opts.x1 or -560, opts.x2 or 940
	local len = x2 - x1
	local cx = (x1 + x2) / 2
	local folder = Instance.new("Folder")
	folder.Name = "City"
	folder.Parent = parent
	local made = { road = 1, buildings = 0, props = 0 }

	prim({ Name = "Road", Size = Vector3.new(len, 1, 26), Position = Vector3.new(cx, groundY + 0.5, z),
		Color = Color3.fromRGB(58, 57, 58), Material = Enum.Material.Asphalt }, folder)
	for x = x1 + 11, x2 - 11, 22 do
		prim({ Name = "RoadLine", Size = Vector3.new(11, 1.02, 0.7), Position = Vector3.new(x, groundY + 0.5, z),
			Color = Color3.fromRGB(224, 210, 140) }, folder)
	end
	for _, side in ipairs({ -1, 1 }) do
		prim({ Name = "Kerb", Size = Vector3.new(len, 1.2, 3), Position = Vector3.new(cx, groundY + 0.6, z + side * 14.5),
			Color = Color3.fromRGB(158, 156, 152), Material = Enum.Material.Concrete }, folder)
		prim({ Name = "Sidewalk", Size = Vector3.new(len, 0.9, 10), Position = Vector3.new(cx, groundY + 0.45, z + side * 21),
			Color = Color3.fromRGB(150, 148, 144), Material = Enum.Material.Concrete }, folder)
	end

	-- planters every 60 studs on both sidewalks: rhythm along the spine
	for x = x1 + 30, x2 - 30, 60 do
		for _, side in ipairs({ -1, 1 }) do
			CityKit.spawnOnGround("planter", x, z + side * 24, groundY + 0.9, folder,
				{ name = "Planter", canQuery = false, canCollide = false })
			made.props += 1
		end
	end

	-- v4.4 KayKit street furniture (CC0, ReplicatedStorage.KayKit.City) midway
	-- between the planters: a bench, then a fire hydrant at the kerb, alternating
	-- down the road and swapped across it. Clear of the cross streets and the
	-- campus entrance paths, like the palms. Scenery never collides (a bench is
	-- the height a humanoid snags on).
	local kk = game:GetService("ReplicatedStorage"):FindFirstChild("KayKit")
	local kkCity = kk and kk:FindFirstChild("City")
	if kkCity then
		local n = 0
		for x = x1 + 60, x2 - 60, 60 do
			local clear = true
			for _, crx in ipairs(CityKit.CROSS_X or {}) do if math.abs(x - crx) < 40 then clear = false end end
			for _, px in ipairs(opts.plotX or { -360, 0, 360 }) do if math.abs(x - px) < 20 then clear = false end end
			if clear then
				n += 1
				for _, side in ipairs({ -1, 1 }) do
					-- measured: the bench is backless (flat 1.2 top), so only its long axis matters: along the road
					local bench = (n + (side > 0 and 1 or 0)) % 2 == 0
					local t = kkCity:FindFirstChild(bench and "bench" or "firehydrant")
					if t then
						local m = t:Clone()
						if bench then m:ScaleTo(m:GetScale() * 1.3) end   -- a 1.2-stud seat is child height; 1.56 fits a 5-stud avatar
						local _, ext = m:GetBoundingBox()
						m:PivotTo(CFrame.new(x, groundY + 0.85 + ext.Y / 2, z + side * (bench and 25 or 22.5)))
						for _, d in ipairs(m:GetDescendants()) do
							if d:IsA("BasePart") then d.CanCollide = false; d.CanQuery = false; d.CanTouch = false end
						end
						m.Parent = folder
						made.props += 1
					end
				end
			end
		end
	end

	-- DOWNTOWN at the east end, both sides of the road, glass facing the road
	-- (v4.0: replaced by Downtown.lua when it is installed)
	if opts.noTowers then return folder, made end
	local tx = opts.towersX or 660
	local ROW = { { 9, 22, 20 }, { 6, 26, 22 }, { 12, 24, 24 }, { 8, 28, 22 } }
	for i, t in ipairs(ROW) do
		for _, side in ipairs({ -1, 1 }) do
			local x = tx + (i - 1) * 68 + ((side > 0) and 30 or 0)
			local tz = z + side * (52 + (i % 2) * 14)
			tower(folder, groundY, x, tz, t[2], t[3], t[1] + ((side > 0) and 2 or 0),
				PALETTE[((i + (side > 0 and 3 or 0)) - 1) % #PALETTE + 1], -side)
			made.buildings += 1
			made.props += 1
		end
	end
	return folder, made
end

-- ============ THE KENNEY CITY (v1.6) ============

--[[
	His ask: "a city like area where cars move everywhere, no people in them,
	feels like New York... plots stand out among others... a city inside a
	valley". Reorganise, not revamp: the six plots, the road line and the
	downtown cluster stay exactly where they are. This layer:
	  1. re-tiles the main road with Kenney road tiles (sidewalks + markings
	     baked in) and adds TWO cross streets in the gaps between plots
	  2. lines the cross streets with Quaternius buildings -- dense blocks at
	     the edges, the plots stay open and obvious
	  3. street lamps + traffic lights (no PointLights: it is daylight)
	  4. cars, placed once here, MOVED ON EACH CLIENT by TrafficClient off the
	     server clock (attributes LaneA/LaneB/Speed/Phase, tag TrafficCar)

	SCALE, measured after import: a Kenney road tile is 100x2x100, a car is
	~150x130x255 with the wheels attached and the nose on -Z (Roblox forward).
	TILE_SCALE 0.5 -> 50-stud tiles (road + both sidewalks), which is the
	width the primitive road + kerbs already occupied. CAR_SCALE 0.05 -> a
	12.75-stud sedan, the size Roblox cars are.
]]
local KENNEY_FOLDER = "KenneyKit"
local TILE = 50
local TILE_SCALE = 0.5
local CAR_SCALE = 0.05
local LAMP_SCALE = 0.2               -- 0.5 gave 34-stud lamps; 0.2 = 13.5, a real lamp
-- v9: NO CROSS STREETS. They ran at x -185 and 165, which is inside the ring
-- the campus now stands on -- they cut straight through the central park, and
-- their invisible RoadDecks did too. CampusHub's six radial streets replace
-- them. Kept as an empty list rather than deleted so every reader still works.
CityKit.CROSS_X = {}
CityKit.CROSS_LEN = 250                -- how far a cross street runs from the main road

local function kenney(name)
	local f = game:GetService("ReplicatedStorage"):FindFirstChild(KENNEY_FOLDER)
	return f and f:FindFirstChild(name) or nil
end

-- clone a Kenney model, scale it, drop it with its bounding-box bottom on groundY
local function placeKenney(name, x, z, groundY, yawDeg, scale, parent, tag)
	local t = kenney(name)
	if not t then warn("[CityKit] no Kenney model: " .. name) return nil end
	local m = t:Clone()
	m.Name = tag or name
	if m:IsA("Model") then
		m:ScaleTo(scale)
		local _, size = m:GetBoundingBox()
		m:PivotTo(CFrame.new(x, groundY + size.Y / 2, z) * CFrame.Angles(0, math.rad(yawDeg or 0), 0))
		-- pivot may not be the bbox centre: correct so the bottom sits on the ground
		local cf = m:GetBoundingBox()
		m:PivotTo(m:GetPivot() + Vector3.new(0, (groundY + size.Y / 2) - cf.Position.Y, 0))
	else
		m.Size = m.Size * scale
		m.CFrame = CFrame.new(x, groundY + m.Size.Y / 2, z) * CFrame.Angles(0, math.rad(yawDeg or 0), 0)
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.CastShadow = false
		end
	end
	if m:IsA("BasePart") then m.Anchored = true; m.CanCollide = false; m.CanQuery = false; m.CastShadow = false end
	m.Parent = parent
	return m
end

local CAR_NAMES = { "sedan", "sedan-sports", "hatchback-sports", "suv", "taxi", "van", "delivery", "truck", "police" }
local BUILDING_KEYS = { "building_small", "building_medium", "building_large" }
-- Kenney City Kit Commercial (import scale: building-a is 88x129x94, i.e. 100x). 0.35 gives a
-- 3-storey block ~45 studs tall and skyscrapers 140-190: big enough to be a skyline, small
-- enough that a 5-stud character still reads as a person on the street.
local BUILDING_SCALE = 0.35
local BUILDING_FRONT_YAW = 90          -- yaw that turns the model's front toward -x (checked by screenshot)
local KENNEY_LOW = { "building-a", "building-b", "building-c", "building-d", "building-e", "building-f", "building-g", "building-h", "building-i", "building-j", "building-k" }
local KENNEY_TALL = { "building-l", "building-m", "building-n", "building-skyscraper-a", "building-skyscraper-b", "building-skyscraper-c", "building-skyscraper-d", "building-skyscraper-e" }

-- v3.4 PHASE W: the Blender trees (ReplicatedStorage.SVMeshes) stand in for
-- the Kenney ones by name, so campus, street and valley share one look. A
-- missing mesh falls back to the Kenney template.
local SV_TREE = {
	tree_default = { "Oak_A", "Oak_B" }, tree_oak = { "Oak_A", "Oak_B" }, tree_detailed = { "Oak_B", "Oak_A" },
	tree_tall = { "Eucalypt_A" }, tree_pineTallA = { "Redwood_A" }, tree_pineRoundA = { "Redwood_A" },
}
local function treeTemplate(name)
	-- v4.1: the low-poly set first (ValleyGen.lpTemplate), then the older meshes
	local vgm = game:GetService("ServerScriptService"):FindFirstChild("ValleyGen")
	local okv, vg = pcall(function() return vgm and require(vgm) end)
	local lpt = okv and vg and vg.lpTemplate and vg.lpTemplate(name)
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

-- a Kenney Nature Kit tree (ReplicatedStorage.KenneyKit), 12-16 studs, no collision
local STREET_TREES = { "tree_default", "tree_oak", "tree_detailed" }
local VG_CACHE
local function valleyGen()
	if VG_CACHE == nil then
		local m = game:GetService("ServerScriptService"):FindFirstChild("ValleyGen")
		local ok, mod = pcall(function() return m and require(m) end)
		VG_CACHE = (ok and mod) or false
	end
	return VG_CACHE or nil
end

local function streetTree(x, z, groundY, parent, rng)
	local tpl = treeTemplate(STREET_TREES[rng:NextInteger(1, #STREET_TREES)])
	if not tpl then return nil end
	local _, size = tpl:GetBoundingBox()
	local h = rng:NextNumber(12, 16)
	-- v3.5: the same spacing registry as the valley and the campus
	local VG = valleyGen()
	if VG then
		local r = h * math.max(size.X, size.Z) / math.max(size.Y, 0.1) / 2
		if not VG.treeRoom(x, z, r) then return nil end
		VG.claimTree(x, z, r)
	end
	local t = tpl:Clone()
	t:ScaleTo(t:GetScale() * h / math.max(size.Y, 0.1))
	for _, d in ipairs(t:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CastShadow = false end
	end
	t:PivotTo(CFrame.new(x, groundY, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	local cf, s3 = t:GetBoundingBox()
	t:PivotTo(t:GetPivot() + Vector3.new(0, groundY - (cf.Position.Y - s3.Y / 2), 0))
	t.Name = "StreetTree"
	t.Parent = parent
	return t
end

function CityKit.buildKenneyCity(parent, opts)
	opts = opts or {}
	if not kenney("road-straight") then
		warn("[CityKit] KenneyKit missing; keeping the primitive road")
		return nil
	end
	local groundY = opts.groundY or 0
	local z = opts.z or 0
	local x1, x2 = opts.x1 or -560, opts.x2 or 940
	local folder = Instance.new("Folder")
	folder.Name = "KenneyCity"
	folder.Parent = parent
	local made = { tiles = 0, buildings = 0, lamps = 0, cars = 0 }
	local rng = Random.new(11)

	-- the primitive road is replaced by tiles: remove it so nothing z-fights
	local city = parent:FindFirstChild("City")
	if city then
		for _, c in ipairs(city:GetChildren()) do
			if c.Name == "Road" or c.Name == "RoadLine" or c.Name == "Kerb" or c.Name == "Sidewalk" then c:Destroy() end
		end
	end

	-- 1. MAIN ROAD: tiles along x, crossroad tiles where the cross streets meet it
	local crossSet = {}
	for _, cx in ipairs(CityKit.CROSS_X) do crossSet[cx] = true end
	local roadYaw = opts.roadYaw or 0           -- MEASURED: the straight tile's road runs along its local X
	for cx = x1 + TILE / 2, x2 - TILE / 2, TILE do
		local name = crossSet[cx] and "road-crossroad" or "road-straight"
		placeKenney(name, cx, z, groundY - 0.2, crossSet[cx] and 0 or roadYaw, TILE_SCALE, folder, "RoadTile")  -- bottom -0.2: top sits 0.8 above the grass, else the terrain swallows it
		made.tiles += 1
	end

	-- 2. CROSS STREETS + the dense blocks along them
	for _, cx in ipairs(CityKit.CROSS_X) do
		for _, side in ipairs({ -1, 1 }) do
			local n = math.floor(CityKit.CROSS_LEN / TILE)
			for k = 1, n do
				local cz = z + side * (TILE * k)
				local name = (k == n) and "road-end" or "road-straight"
				local yaw = (k == n) and ((side > 0) and -90 or 90) or 90   -- cross street runs along z = tile yaw 90; end cap closed side away from the junction
				placeKenney(name, cx, cz, groundY - 0.2, yaw, TILE_SCALE, folder, "RoadTile")
				made.tiles += 1
			end
			-- traffic light on each corner of the crossroad
			placeKenney("traffic-light", cx + side * 22, z + side * 22, groundY, (side > 0) and 180 or 0, LAMP_SCALE, folder, "TrafficLight")
			placeKenney("traffic-light", cx - side * 22, z + side * 22, groundY, (side > 0) and 90 or -90, LAMP_SCALE, folder, "TrafficLight")
			-- buildings both sides of the cross street, facing it, from 60 studs out.
			-- v1.9: Kenney City Kit Commercial (one colormap, same pipeline as the
			-- cars) when imported; the Quaternius trio stays as the fallback.
			--[[ v3.0.3: STREET TREES, not buildings. Measured 24 Sep: the cross
			streets run through the 140-stud gaps BETWEEN campuses, and the 30-50
			stud blocks that lined them ended at the campus edge -- every HQ was
			wedged between generic apartment blocks, and from the road the player's
			own building was hidden. The skyline stays downtown (east). ]]
			for _, bs in ipairs({ -1, 1 }) do
				local bz = z + side * 34
				local limit = z + side * (CityKit.CROSS_LEN - 14)
				while (side > 0 and bz < limit) or (side < 0 and bz > limit) do
					streetTree(cx + bs * (TILE / 2 + 4), bz, groundY, folder, rng)
					bz = bz + side * 17
				end
			end
		end
	end

	-- 3. STREET LAMPS along the main road, alternating sides every 100 studs
	local i = 0
	for lx = x1 + 60, x2 - 60, 100 do
		i += 1
		local side = (i % 2 == 0) and 1 or -1
		if not crossSet[lx - 15] and not crossSet[lx + 15] then
			placeKenney("light-curved", lx, z + side * 22, groundY, (side > 0) and 180 or 0, LAMP_SCALE, folder, "Lamp")
			made.lamps += 1
		end
	end

	-- 4. CARS: placed once, moved by every client (TrafficClient). Right-hand
	-- traffic: east-bound in the +z lane, west-bound in the -z lane.
	-- v1.7: ONE speed per lane and EVEN spacing, so cars in a lane can never
	-- drive through each other (random per-car speed did exactly that). Cross-
	-- street cars carry CrossAt = the world position of their intersection so
	-- the client can make them yield to main-road traffic.
	local CollectionService = game:GetService("CollectionService")
	local laneId = 0
	local function lane(a, b, count, speed, crossAt)
		laneId += 1
		local len = (b - a).Magnitude
		for k = 1, count do
			local name = CAR_NAMES[rng:NextInteger(1, #CAR_NAMES)]
			local m = placeKenney(name, a.X, a.Z, groundY + 0.4, 0, CAR_SCALE, folder, "Car")
			if m then
				m:SetAttribute("LaneA", a)
				m:SetAttribute("LaneB", b)
				m:SetAttribute("LaneId", laneId)
				m:SetAttribute("Speed", speed)
				m:SetAttribute("Phase", (k - 1) * (len / count))
				if crossAt then m:SetAttribute("CrossAt", crossAt) end
				CollectionService:AddTag(m, "TrafficCar")
				made.cars += 1
			end
		end
	end
	local y = groundY + 0.4
	lane(Vector3.new(x1, y, z + 7), Vector3.new(x2, y, z + 7), 6, 42)
	lane(Vector3.new(x2, y, z - 7), Vector3.new(x1, y, z - 7), 6, 36)
	for _, cx in ipairs(CityKit.CROSS_X) do
		local at = Vector3.new(cx, y, z)
		lane(Vector3.new(cx + 7, y, z - CityKit.CROSS_LEN), Vector3.new(cx + 7, y, z + CityKit.CROSS_LEN), 2, 28, at)
		lane(Vector3.new(cx - 7, y, z + CityKit.CROSS_LEN), Vector3.new(cx - 7, y, z - CityKit.CROSS_LEN), 2, 28, at)
	end

	-- 5. STREET AMBIENCE: a quiet freeway wash (Pro Sound Effects, licensed,
	-- pre-moderated) from four emitters along the boulevard, so it is loudest on
	-- the road and fades to nothing at the back of a plot. Volume deliberately low.
	for _, ax in ipairs({ x1 + 150, x1 + 450, x1 + 800, x1 + 1150 }) do
		local p = Instance.new("Part")
		p.Name = "Ambience"
		p.Size = Vector3.new(1, 1, 1)
		p.Transparency = 1
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
		p.Position = Vector3.new(ax, groundY + 4, z)
		local snd = Instance.new("Sound")
		snd.Name = "Traffic"
		snd.SoundId = "rbxassetid://9112784190"     -- PSE Freeway Traffic 3, 56s loop
		snd.Looped = true
		snd.Volume = 0.22
		snd.RollOffMode = Enum.RollOffMode.InverseTapered
		snd.RollOffMinDistance = 40
		snd.RollOffMaxDistance = 260
		snd.Parent = p
		p.Parent = folder
		snd:Play()
	end

	return folder, made
end

return CityKit
