--[[
	ValleyGen -- ModuleScript in ServerScriptService.

	v3.3 THE SANTA CLARA VALLEY. His verdict on v2: "the blocky pixelly
	mountains suck", and a friend's: "it feels like a Minecraft superflat
	world". Both right. v2 was an Alpine range (ridged noise, grey Rock faces,
	Snow crests) around one flat green lawn. Silicon Valley looks nothing
	like that:

	  south   the Santa Cruz Mountains: one long, rounded, FORESTED ridge
	          (redwood and fir read as a dark green crest), golden grass
	          foothills below it
	  north   the Diablo Range: separate, rounded, GOLDEN grass hills with
	          dark oak clusters in the folds, the Lick Observatory domes on
	          the highest one
	  west    the Bay: marsh, the red / orange / green salt ponds, open water,
	          and the low hills across it closing the view
	  floor   flat, but never one colour: golden fields, green irrigated
	          lawns, orchards (the "Valley of Heart's Delight")

	So: smooth fbm hills (no ridged noise, no high-frequency octave, which is
	what made the 4-stud voxels read as pixel stairs), no Snow, no grey Rock,
	materials chosen by region and slope and tinted with SetMaterialColor.
	Zero uploads.

	FLAT ZONES are passed in by the caller as world-space rectangles. Inside
	them the height is EXACTLY 0 (blended out over a margin), so slabs, pads
	and roads sit on a surface the generator guarantees. A rect may carry a
	kind ("rail"), which picks its ground material. MOUNDS are raised after
	flattening (the hill the train tunnels into).

	The half-cell correction stays: Roblox draws the surface half a cell above
	a full cell, so the top cell's occupancy is fractional and shifted.

	Everything here is scenery: no collision, no raycast hits, no shadows.
]]

local ValleyGen = {}

local CELL = 4

-- ============ NOISE ============

local function fbm(x, z, freq, octaves, seed)
	local v, amp, f, norm = 0, 1, freq, 0
	for _ = 1, octaves do
		v += math.noise(x * f + seed, z * f - seed, seed * 0.37) * amp
		norm += amp
		amp *= 0.5
		f *= 2.05
	end
	return v / norm             -- roughly -0.5 .. 0.5
end

local function smoothstep(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- ============ THE PALETTE ============
-- one colour per terrain material, so each material IS a land cover
local PALETTE = {
	-- v3.5 (ART.md quick wins): tuned on screen toward the art-guide palette.
	-- Terrain textures darken and saturate their tint, so these sit brighter
	-- and softer than the palette swatches they are aiming at.
	Grass      = Color3.fromRGB(200, 168, 96),    -- dry California grass (ART: California Gold)
	LeafyGrass = Color3.fromRGB(136, 172, 96),    -- irrigated lawns (ART: Campus Lawn); the texture darkens it ~35%
	Mud        = Color3.fromRGB(78, 100, 60),     -- oak woodland / redwood ridge, closer to the gold so the edge is not a cliff
	Ground     = Color3.fromRGB(150, 126, 94),    -- dirt: orchard floors, levees, the rail bed
	Sand       = Color3.fromRGB(150, 140, 116),    -- bay mudflats and the bed under the water
	Salt       = Color3.fromRGB(172, 88, 84),     -- salt pond, red (the brine shrimp colour)
	Limestone  = Color3.fromRGB(196, 136, 82),    -- salt pond, orange
	Basalt     = Color3.fromRGB(104, 128, 92),    -- salt pond, green-brown
	Sandstone  = Color3.fromRGB(170, 144, 96),    -- the rare steep face: gold-brown, reads as dry grass not sand
}

-- ============ THE HEIGHT FUNCTION ============

--[[
	opts:
	  flatRects  = { {x=, z=, w=, d=, kind=}, ... }  world AABBs held at height 0
	  margin     = blend distance around flat rects (studs)
	  basin      = radius where the floor stops and the hills begin
	  rim        = radius where the hills reach full height
	  peakSouth / peakNorth
	  stretchX   = the basin is an ellipse: x is divided by this (valley is wide)
	  bayX       = the Bay opens west of x = -bayX
	  mounds     = { {x0=, z=, halfW=, h=}, ... }   raised after flattening
	  seed
	Returns height(x, z), flatInfo(x, z) -> weight, rect, and region(x, z, h)
	-> a table the material classifier and the planters share.
]]
function ValleyGen.makeHeight(opts)
	local flat = opts.flatRects or {}
	local margin = opts.margin or 40
	local basin = opts.basin or 430
	local rim = opts.rim or 680
	local peakS = opts.peakSouth or 190
	local peakN = opts.peakNorth or 160
	local sx = opts.stretchX or 1.35
	local bayX = opts.bayX or 640
	local mounds = opts.mounds or {}
	local seed = opts.seed or 7

	local function flatInfo(x, z)
		local best, rect = 0, nil
		for _, r in ipairs(flat) do
			local dx = math.max(math.abs(x - r.x) - r.w / 2, 0)
			local dz = math.max(math.abs(z - r.z) - r.d / 2, 0)
			local dist = math.sqrt(dx * dx + dz * dz)
			local w = 1 - smoothstep(dist / margin)
			if w > best then best, rect = w, r end
		end
		return best, rect
	end

	-- 1 across the open bay (west end), 0 elsewhere; the hills curve round it
	local function bayWeight(x, z)
		local wx = smoothstep((-x - bayX) / 150)
		local wz = 1 - smoothstep((math.abs(z) - 320) / 220)
		return wx * wz
	end

	local function bayFloor(x, z)
		local deep = smoothstep((-x - 805) / 40)          -- marsh -> open water
		local far = smoothstep((-x - 925) / 55)           -- open water -> the hills across the bay
		local farHill = far * (36 + 22 * fbm(x, z, 1 / 160, 2, seed + 41))
		return -1.2 - 7 * deep * (1 - far) + farHill
	end

	local function sideOf(z) return smoothstep((z + 150) / 300) end   -- 0 south, 1 north

	local function height(x, z)
		local rx = x / sx
		local r = math.sqrt(rx * rx + z * z)
		local t = smoothstep((r - basin) / (rim - basin))
		local side = sideOf(z)
		local peak = peakS + (peakN - peakS) * side
		local base = (t ^ 1.25) * peak
		local n1 = fbm(x, z, 1 / 330, 3, seed)
		local n2 = fbm(x, z, 1 / 140, 2, seed + 3)
		-- the south is one continuous crest; the north breaks into separate round hills
		local shape = (0.72 + 0.55 * n1) * (1 - side) + (0.68 + 0.8 * n1) * side
		local mountain = base * math.max(0.12, shape + 0.28 * n2)
		-- the floor: a gentle roll, never enough to hide a building
		local roll = (fbm(x, z, 1 / 150, 3, seed + 9) * 7 + fbm(x, z, 1 / 45, 2, seed + 4) * 1.6) * (1 - t)
		local h = mountain + roll
		local bw = bayWeight(x, z)
		if bw > 0 then h = h * (1 - bw) + bayFloor(x, z) * bw end
		local w = flatInfo(x, z)
		h = h * (1 - w)
		for _, m in ipairs(mounds) do
			local along = smoothstep(((m.dir or 1) * (x - m.x0)) / 30)
			local across = 1 - smoothstep((math.abs(z - m.z) - m.halfW) / 26)
			local mh = m.h * along * across
			if mh > h then h = mh end
		end
		return h
	end

	-- what a point IS, for the classifier and the planters
	local function region(x, z, h)
		local rx = x / sx
		local r = math.sqrt(rx * rx + z * z)
		return {
			t = smoothstep((r - basin) / (rim - basin)),
			side = sideOf(z),
			bay = bayWeight(x, z),
			r = r,
		}
	end

	return height, flatInfo, region
end

-- ============ WHAT GROWS WHERE ============

local function inRect(x, z, r)
	return math.abs(x - r.x) <= r.w / 2 and math.abs(z - r.z) <= r.d / 2
end

--[[ One classifier for the terrain AND the tree planters, so an oak always
stands on oak-woodland ground and a pine on the forested ridge. ]]
function ValleyGen.classify(x, z, h, slope, fw, rect, rg, opts)
	local seed = opts.seed or 7
	if rect and fw > 0.35 then
		if rect.kind == "rail" and math.abs(z - rect.z) < 9 then return "Ground" end
		return "LeafyGrass"      -- the settlement: no grass blades through the slabs
	end
	for _, o in ipairs(opts.orchards or {}) do
		if inRect(x, z, o) then return "Ground" end
	end
	if rg.bay > 0.5 then
		if h < -3 then return "Sand" end                     -- the bed under the water
		if h < 1.5 and -x < 805 then
			-- the salt ponds: a grid of rectangles behind dirt levees
			local gx, gz = (x + 2000) % 46, (z + 2000) % 40
			if gx < 4 or gz < 4 then return "Ground" end
			local i, j = math.floor((x + 2000) / 46), math.floor((z + 2000) / 40)
			return ({ "Salt", "Limestone", "Basalt", "Sand" })[((i * 7 + j * 3) % 4) + 1]
		end
		if h < 1.5 then return "Sand" end
	end
	-- (no rock faces: the Sandstone texture rendered as pale sand ovals on every
	-- steep face. On these hills a steep face is still dry grass.)
	if rg.t > 0.04 or h > 12 then
		-- the south crest above ~45 studs is redwood forest; the lower
		-- slopes everywhere carry oak clusters in noise-shaped patches
		-- v3.5: redwoods only on the crest (from ~75 up, full by ~130), gold
		-- slopes with oak patches below it, as in the styleframe
		local forest = (1 - rg.side) * smoothstep((h - 75) / 55)
		-- v3.5: the forest line used to be one noise-bent contour, which read as
		-- a hard dark-green-to-gold cliff. A wide noise band with fine grain
		-- breaks it into oak patches, the way the real ridge thins out.
		local edge = 0.5 + 0.28 * fbm(x, z, 1 / 60, 1, seed + 23) + 0.14 * fbm(x, z, 1 / 18, 1, seed + 29)
		if forest > edge then return "Mud" end
		if h < 120 and fbm(x, z, 1 / 44, 2, seed + 21) > 0.16 then return "Mud" end
		return "Grass"
	end
	-- the valley floor: golden fields and green lawns, never one flat colour
	if fbm(x, z, 1 / 110, 2, seed + 31) > 0.06 then return "Grass" end
	return "LeafyGrass"
end

-- ============ THE MESH MOUNTAINS (v4.0) ============
--[[ His verdict: "the mountains still look plain... the pixelly visuals of the
structures and blockiness." Roblox draws distant terrain at a coarse level of
detail (voxel steps and facets) and low-end phones stop drawing it at ~500-600
studs. So past a seam the hills are MESHES (blender/mountains.py): built from
this terrain (sampled by raycast), then eroded -- branching ravines, ridgelines,
oak woodland down the folds, redwoods on the southern crest, rock on the steep
faces -- and a second range out to ~2,400 studs. Terrain stays for the walkable
valley and the Bay. Nothing changes unless the tiles are imported
(ReplicatedStorage.SVMeshes.Mountains), so a missing import never breaks it. ]]
local MTN_DATA = nil
local function mountainData()
	if MTN_DATA ~= nil then return MTN_DATA or nil end
	local lib = game:GetService("ReplicatedStorage"):FindFirstChild("SVMeshes")
	local folder = lib and lib:FindFirstChild("Mountains")
	local mod = game:GetService("ServerScriptService"):FindFirstChild("MountainData")
	local ok, data = pcall(function() return mod and require(mod) end)
	if folder and ok and type(data) == "table" and #folder:GetChildren() > 0 then
		MTN_DATA = { data = data, folder = folder }
	else
		MTN_DATA = false
	end
	return MTN_DATA or nil
end
ValleyGen.mountainData = mountainData

-- the Bay (water, salt ponds, the flats round Hangar One) always stays terrain
local function bayRect(x, z) return x < -640 and x > -1010 and math.abs(z) < 540 end
local WET = { [Enum.Material.Salt] = true, [Enum.Material.Limestone] = true, [Enum.Material.Basalt] = true,
	[Enum.Material.Sand] = true, [Enum.Material.Water] = true }
-- true where the mesh replaces the terrain completely (the overlap band keeps both)
local function meshColumn(x, z, mat, seam, sx)
	if bayRect(x, z) or (mat and WET[mat]) then return false end
	local rx = x / sx
	return math.sqrt(rx * rx + z * z) >= seam
end

-- ============ WRITE THE TERRAIN ============

function ValleyGen.writeTerrain(height, flatInfo, region, opts)
	local Terrain = workspace.Terrain
	local extentX = opts.extentX or opts.extent or 760
	local extentZ = opts.extentZ or opts.extent or 760
	local chunkCells = 40                       -- 160 studs per chunk
	local minY = -16                            -- room for the bay under the water line

	local colsX = math.floor((extentX * 2) / CELL)
	local colsZ = math.floor((extentZ * 2) / CELL)
	local originX, originZ = -extentX, -extentZ

	local mtn = mountainData()
	local seam = mtn and mtn.data.seam or math.huge
	local msx = opts.stretchX or 1.35
	local maxH = 0
	local cache = {}
	for ix = 0, colsX do
		cache[ix] = {}
		for iz = 0, colsZ do
			local h = height(originX + ix * CELL, originZ + iz * CELL)
			cache[ix][iz] = h
			if h > maxH then maxH = h end
		end
	end

	local MAT = {}
	for name in pairs(PALETTE) do MAT[name] = Enum.Material[name] end
	MAT.Grass = Enum.Material.Grass
	MAT.LeafyGrass = Enum.Material.LeafyGrass

	local written = 0
	local nX = math.ceil(colsX / chunkCells)
	local nZ = math.ceil(colsZ / chunkCells)
	for cx = 0, nX - 1 do
		for cz = 0, nZ - 1 do
			local x0, z0 = cx * chunkCells, cz * chunkCells
			local x1 = math.min(x0 + chunkCells, colsX) - 1
			local z1 = math.min(z0 + chunkCells, colsZ) - 1
			if x1 >= x0 and z1 >= z0 then
				local top = minY
				for ix = x0, x1 do
					for iz = z0, z1 do
						local h = cache[ix][iz]
						if h > top then top = h end
					end
				end
				local yCells = math.max(1, math.ceil((top - minY) / CELL) + 2)

				-- one classification per column, reused for every cell in it
				local colMat = {}
				for ix = x0, x1 do
					colMat[ix] = {}
					for iz = z0, z1 do
						local x, z = originX + ix * CELL, originZ + iz * CELL
						local h = cache[ix][iz]
						local hx = cache[math.min(ix + 1, colsX)][iz] - cache[math.max(ix - 1, 0)][iz]
						local hz = cache[ix][math.min(iz + 1, colsZ)] - cache[ix][math.max(iz - 1, 0)]
						local slope = math.sqrt(hx * hx + hz * hz) / (2 * CELL)
						local fw, rect = flatInfo(x, z)
						colMat[ix][iz] = MAT[ValleyGen.classify(x, z, h, slope, fw, rect, region(x, z, h), opts)] or Enum.Material.Grass
					end
				end

				local mats, occ = {}, {}
				for ix = x0, x1 do
					local mx, ox = {}, {}
					for iy = 1, yCells do
						local my, oy = {}, {}
						local cellBottom = minY + (iy - 1) * CELL
						for iz = z0, z1 do
							local h = cache[ix][iz]
							local m = colMat[ix][iz]
							if mtn and meshColumn(originX + ix * CELL, originZ + iz * CELL, m, seam, msx) then
								oy[iz - z0 + 1] = 0                -- the mesh mountain is here
								my[iz - z0 + 1] = Enum.Material.Air
							else
								oy[iz - z0 + 1] = math.clamp(((h - 2) - cellBottom) / CELL, 0, 1)   -- half-cell shift
								my[iz - z0 + 1] = m
							end
						end
						mx[iy] = my
						ox[iy] = oy
					end
					mats[ix - x0 + 1] = mx
					occ[ix - x0 + 1] = ox
				end

				local wx, wz = originX + x0 * CELL, originZ + z0 * CELL
				local reg = Region3.new(
					Vector3.new(wx, minY, wz),
					Vector3.new(wx + (x1 - x0 + 1) * CELL, minY + yCells * CELL, wz + (z1 - z0 + 1) * CELL)
				):ExpandToGrid(CELL)
				Terrain:WriteVoxels(reg, CELL, mats, occ)
				written += 1
			end
		end
	end

	-- THE BAY: every empty cell below the water line in the west becomes water.
	-- ReplaceMaterial only touches Air, so the causeway and the far hills stay dry.
	local water = Region3.new(Vector3.new(-extentX, minY, -520), Vector3.new(-(opts.bayX or 640) - 100, -4, 520)):ExpandToGrid(CELL)
	pcall(function() Terrain:ReplaceMaterial(water, CELL, Enum.Material.Air, Enum.Material.Water) end)

	return written, maxH
end

-- ============ TREES ============

local function scenery(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	p.Parent = parent
	return p
end
ValleyGen.scenery = scenery

-- ============ THE LOW-POLY VALLEY (v4.1) ============
--[[ His verdict on the old look: "the hills are blurry and trashy... the
blockiness and the imitation of realism are ugly in combination... the tree
assets look extremely ugly". From a side-by-side of the same two shots in three
styles (art/v402/STYLE_COMPARISON.png) he picked B: faceted, flat-coloured.

blender/lp_world.py builds the WHOLE landscape (valley floor, hills, the far
ranges, the Bay) as flat-shaded facets from the game's own terrain samples,
coloured by the terrain's own materials, so fields, lawns, woodland and orchards
stay where they were. It writes LowPolyData: tile centres, the hill trees, the
salt ponds, and the exact vertex grid. When the tiles are imported
(ReplicatedStorage.SVMeshes.LowPoly) the terrain is not written at all:
  * the tiles are visual only (no collision, no queries);
  * collision is built HERE from the same triangles: a flat slab at y 0 under
    the walkable valley, plus an invisible wedge pair for every walkable facet
    above it. Exact, no mesh decomposition, and raycasts (cars, recruits) hit it;
  * lpHeight reads the exact faceted surface, so every tree, landmark and verge
    planting stands on the facet it is drawn on. ]]
local LP = nil
local function lowPoly()
	if LP ~= nil then return LP or nil end
	local lib = game:GetService("ReplicatedStorage"):FindFirstChild("SVMeshes")
	local folder = lib and lib:FindFirstChild("LowPoly")
	local mod = game:GetService("ServerScriptService"):FindFirstChild("LowPolyData")
	local ok, data = pcall(function() return mod and require(mod) end)
	if folder and ok and type(data) == "table" and data.grid and #folder:GetChildren() > 0 then
		LP = { data = data, folder = folder }
	else
		LP = false
	end
	return LP or nil
end
ValleyGen.lowPoly = lowPoly

-- the old mesh names every planter asks for -> their low-poly stand-ins
local LP_ALIAS = {
	Oak_A = { "LP_Oak_A" }, Oak_B = { "LP_Oak_B" }, Redwood_A = { "LP_Redwood_A", "LP_Redwood_B" },
	Eucalypt_A = { "LP_Eucalypt" }, Palm_A = { "LP_Palm_A" }, Palm_B = { "LP_Palm_B" }, Orchard_A = { "LP_Orchard" },
	-- the Kenney names the campus and the street ask for
	tree_default = { "LP_Oak_A", "LP_Oak_B" }, tree_oak = { "LP_Oak_A", "LP_Oak_B" }, tree_detailed = { "LP_Oak_B", "LP_Oak_A" },
	tree_tall = { "LP_Eucalypt" }, tree_pineTallA = { "LP_Redwood_A", "LP_Redwood_B" }, tree_pineRoundA = { "LP_Redwood_B" },
	plant_bushLarge = { "LP_Bush" }, plant_bushDetailed = { "LP_Bush" },
}
local lpWrapped = {}
-- a Model template (one MeshPart, upright pivot) for the low-poly stand-in of
-- `name`, or nil when the low-poly set is not imported. Model, because the
-- campus and street planters scale and pivot Models.
function ValleyGen.lpTemplate(name)
	local list = LP_ALIAS[name]
	local lp = list and lowPoly()
	if not lp then return nil end
	local pick = list[math.random(1, #list)]
	if lpWrapped[pick] ~= nil then return lpWrapped[pick] or nil end
	local mp = lp.folder:FindFirstChild(pick)
	if not mp or not mp:IsA("BasePart") then lpWrapped[pick] = false return nil end
	local m = Instance.new("Model")
	m.Name = pick
	local c = mp:Clone()
	c.PivotOffset = CFrame.new()
	c.CFrame = CFrame.new()
	c.Anchored = true; c.CanCollide = false; c.CanQuery = false; c.CanTouch = false
	c.Parent = m
	m.PrimaryPart = c
	m.WorldPivot = c.CFrame
	lpWrapped[pick] = m
	return m
end

-- the exact faceted surface height at (x, z), or nil off the grid. The grid is
-- row-major (z rows, x columns); cell (i, j) splits along p00-p11 when i + j is
-- even, else along p10-p01 (blender/lp_world.py, the same order)
local function makeLpHeight(grid)
	local nx, nz, x0, z0, S, v = grid.nx, grid.nz, grid.x0, grid.z0, grid.S, grid.v
	local function at(i, j) local k = (i * nx + j) * 3; return v[k + 1], v[k + 2], v[k + 3] end
	local function inTri(px, pz, ax, ay, az, bx, by, bz, cx, cy, cz)
		local den = (bz - cz) * (ax - cx) + (cx - bx) * (az - cz)
		if math.abs(den) < 1e-9 then return nil end
		local l1 = ((bz - cz) * (px - cx) + (cx - bx) * (pz - cz)) / den
		local l2 = ((cz - az) * (px - cx) + (ax - cx) * (pz - cz)) / den
		local l3 = 1 - l1 - l2
		if l1 >= -1e-5 and l2 >= -1e-5 and l3 >= -1e-5 then return l1 * ay + l2 * by + l3 * cy end
		return nil
	end
	return function(x, z)
		local j0, i0 = math.floor((x - x0) / S), math.floor((z - z0) / S)
		for di = -1, 1 do
			for dj = -1, 1 do
				local i, j = i0 + di, j0 + dj
				if i >= 0 and j >= 0 and i < nz - 1 and j < nx - 1 then
					local ax, ay, az = at(i, j)
					local bx, by, bz = at(i, j + 1)
					local cx, cy, cz = at(i + 1, j)
					local ex, ey, ez = at(i + 1, j + 1)
					local h
					if (i + j) % 2 == 0 then
						h = inTri(x, z, ax, ay, az, bx, by, bz, ex, ey, ez) or inTri(x, z, ax, ay, az, ex, ey, ez, cx, cy, cz)
					else
						h = inTri(x, z, ax, ay, az, bx, by, bz, cx, cy, cz) or inTri(x, z, bx, by, bz, ex, ey, ez, cx, cy, cz)
					end
					if h then return h end
				end
			end
		end
		return nil
	end
end
ValleyGen.makeLpHeight = makeLpHeight

-- one invisible collision triangle as two wedges (the classic wedge-pair
-- decomposition), `thick` studs deep with its TOP face on the triangle
local function wedgeTri(a, b, c, parent, thick)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then c, a = a, c elseif acd > bcd and acd > abd then a, b = b, a end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab)
	if right.Magnitude < 1e-6 then return 0 end
	right = right.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local down = (right.Y > 0) and -right or right
	local off = down * (thick / 2)
	local n = 0
	for _, w in ipairs({
		{ (a + b) / 2, right, math.abs(ab:Dot(back)), back },
		{ (a + c) / 2, -right, math.abs(ac:Dot(back)), -back },
	}) do
		if height > 0.05 and w[3] > 0.05 then
			local p = Instance.new("WedgePart")
			p.Name = "Ground"
			p.Anchored = true
			p.CanCollide = true
			p.CanQuery = true
			p.CanTouch = false
			p.CastShadow = false
			p.Transparency = 1
			p.Size = Vector3.new(thick, height, w[3])
			p.CFrame = CFrame.fromMatrix(w[1] + off, w[2], up, w[4])
			p.Parent = parent
			n += 1
		end
	end
	return n
end

local LP_POND = {
	Color3.fromRGB(172, 88, 84),     -- salt pond red (the brine shrimp colour)
	Color3.fromRGB(196, 136, 82),    -- orange
	Color3.fromRGB(104, 128, 92),    -- green-brown
	Color3.fromRGB(214, 196, 152),   -- pale
}

-- the low-poly world: tiles, collision, hill trees, ponds, water, clouds
function ValleyGen.buildLowPoly(world, lp, placeH, opts)
	local data = lp.data
	local sx = opts.stretchX or 1.35
	local WATER = data.water or -1.6
	local f = Instance.new("Folder")
	f.Name = "LowPolyWorld"
	f.Parent = world
	local made = { tiles = 0, wedges = 0, trees = 0, ponds = 0, clouds = 0 }

	-- 1. THE TILES (visual only)
	local tf = Instance.new("Folder")
	tf.Name = "Tiles"
	tf.Parent = f
	for name, t in pairs(data.tiles) do
		local src = lp.folder:FindFirstChild(name)
		if src and src:IsA("BasePart") then
			local p = src:Clone()
			p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
			p.PivotOffset = CFrame.new()
			p.CFrame = CFrame.new(t.c)
			p.Parent = tf
			made.tiles += 1
		end
	end

	-- 2. COLLISION from the same triangles: the walkable valley (inside the
	-- ValleyEdge ring) and the Bay (the ring stops short of it)
	local cf = Instance.new("Folder")
	cf.Name = "Collision"
	cf.Parent = f
	local function inBay(x, z) return x < -640 and x > -1010 and math.abs(z) < 540 end
	-- the valley floor is never below 0, so one slab at 0 covers every flat facet
	scenery({ Name = "FloorSlab", Size = Vector3.new(1480, 4, 1250), CFrame = CFrame.new(100, -2, 0),
		Transparency = 1, CanCollide = true, CanQuery = true }, cf)
	-- the Bay bed: you wade (the water sheet is at WATER)
	scenery({ Name = "BayBed", Size = Vector3.new(370, 4, 1080), CFrame = CFrame.new(-825, WATER - 0.7 - 2, 0),
		Transparency = 1, CanCollide = true, CanQuery = true }, cf)
	local g = data.grid
	local nx, nz, v = g.nx, g.nz, g.v
	local function P(i, j) local k = (i * nx + j) * 3; return Vector3.new(v[k + 1], v[k + 2], v[k + 3]) end
	local limit = 600 + 20
	for i = 0, nz - 2 do
		for j = 0, nx - 2 do
			local a, b, c, d = P(i, j), P(i, j + 1), P(i + 1, j), P(i + 1, j + 1)
			local tris = ((i + j) % 2 == 0) and { { a, b, d }, { a, d, c } } or { { a, b, c }, { b, d, c } }
			for _, t in ipairs(tris) do
				local cen = (t[1] + t[2] + t[3]) / 3
				local rx = cen.X / sx
				local bay = inBay(cen.X, cen.Z)
				if math.sqrt(rx * rx + cen.Z * cen.Z) < limit or bay then
					local top = math.max(t[1].Y, t[2].Y, t[3].Y)
					local water = bay and top < WATER + 0.6
					-- flat facets on the valley floor are the slab's job; in the Bay the slab is absent
					if not water and (top > 0.05 or cen.X < -640) then
						made.wedges += wedgeTri(t[1], t[2], t[3], cf, 2)
					end
				end
			end
		end
		if i % 20 == 0 then task.wait() end
	end
	-- the Bay has no ring: wall its outer edges so nobody walks off the world
	for _, w in ipairs({
		{ CFrame.new(-1010, 30, 0), Vector3.new(2, 90, 1090) },
		{ CFrame.new(-825, 30, 545), Vector3.new(372, 90, 2) },
		{ CFrame.new(-825, 30, -545), Vector3.new(372, 90, 2) },
		{ CFrame.new(-640, 30, 438), Vector3.new(2, 90, 214) },
		{ CFrame.new(-640, 30, -438), Vector3.new(2, 90, 214) },
	}) do
		scenery({ Name = "ValleyEdge", Size = w[2], CFrame = w[1], Transparency = 1, CanCollide = true }, cf)
	end

	-- 3. THE HILL TREES (placed in Blender on the exact facets)
	local trees = Instance.new("Folder")
	trees.Name = "HillTrees"
	trees.Parent = f
	local rng = Random.new(29)
	for _, t in ipairs(data.trees) do
		local src = lp.folder:FindFirstChild(t[4])
		if src and src:IsA("BasePart") then
			local p = src:Clone()
			p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
			p.PivotOffset = CFrame.new()
			p.Size = p.Size * (t[5] / p.Size.Y)
			p.CFrame = CFrame.new(t[1], t[2] + p.Size.Y / 2 - 0.4, t[3]) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
			p.Parent = trees
			made.trees += 1
		end
		if made.trees % 400 == 0 then task.wait() end
	end

	-- 4. THE BAY: one flat water sheet at the water line (the facets under it are
	-- the bed) and the salt ponds on the marsh as crisp rectangles on dirt levees
	scenery({ Name = "BayWater", Size = Vector3.new(2048, 1, 2048), CFrame = CFrame.new(-640 - 1024, WATER - 0.5, 0),
		Color = Color3.fromRGB(98, 164, 198), Material = Enum.Material.SmoothPlastic }, f)
	for _, pd in ipairs(data.ponds or {}) do
		scenery({ Name = "Levee", Size = Vector3.new(46, 0.3, 40), CFrame = CFrame.new(pd[1] - 2, WATER + 0.05, pd[2] - 2),
			Color = Color3.fromRGB(170, 144, 104), Material = Enum.Material.SmoothPlastic }, f)
		scenery({ Name = "Pond", Size = Vector3.new(42, 0.3, 36), CFrame = CFrame.new(pd[1], WATER + 0.15, pd[2]),
			Color = LP_POND[pd[3]] or LP_POND[1], Material = Enum.Material.SmoothPlastic }, f)
		made.ponds += 1
	end

	-- 5. THE CLOUDS: faceted cumulus, drifting on the client (SkyClient, tag SVCloud)
	local CS = game:GetService("CollectionService")
	local cl = Instance.new("Folder")
	cl.Name = "Clouds"
	cl.Parent = f
	local names = { "LP_Cloud_A", "LP_Cloud_B", "LP_Cloud_C" }
	local crng = Random.new(53)
	for k = 1, 26 do
		local src = lp.folder:FindFirstChild(names[crng:NextInteger(1, #names)])
		if src then
			local a = crng:NextNumber(0, math.pi * 2)
			local r = crng:NextNumber(320, 1900)
			local p = src:Clone()
			p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
			p.PivotOffset = CFrame.new()
			p.Size = p.Size * crng:NextNumber(2.6, 4.6)
			p.CFrame = CFrame.new(math.cos(a) * r * 1.2, crng:NextNumber(300, 470), math.sin(a) * r) * CFrame.Angles(0, crng:NextNumber(0, 6.28), 0)
			p.Parent = cl
			CS:AddTag(p, "SVCloud")
			made.clouds += 1
		end
	end
	return made
end

local function kit(name)
	local k = game:GetService("ReplicatedStorage"):FindFirstChild("KenneyKit")
	return k and k:FindFirstChild(name) or nil
end

--[[ A Kenney Nature Kit tree (ReplicatedStorage.KenneyKit, parts named
trunk / leaf / snow, pivot at the base), scaled to a height and recoloured
per species. Returns nil when the import is missing so a primitive stands in. ]]
--[[ v3.4 PHASE W: custom meshes modelled in Blender (silicon-startup/blender/),
imported once into ReplicatedStorage.SVMeshes. Clone, scale to a height,
stand the bottom of the box on (x, y, z), turn by yaw. nil when the mesh has
not been imported, so every caller keeps its old build as the fallback. ]]
local function svMesh(name, x, y, z, height, yaw, parent)
	local lib = game:GetService("ReplicatedStorage"):FindFirstChild("SVMeshes")
	-- v4.1: when the low-poly set is imported it stands in for every old tree name
	local t = ValleyGen.lpTemplate(name) or (lib and lib:FindFirstChild(name))
	if not t then return nil end
	local c = t:Clone()
	local m = c
	if not c:IsA("Model") then m = Instance.new("Model"); m.Name = name; c.Parent = m end
	local only
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.CastShadow = false
			only = (only == nil) and d or false
		end
	end
	-- the FBX importer gives a Blender (Z-up) mesh a pivot turned 90 degrees
	-- about X; placed by that pivot the tree lies on its side. Upright pivot.
	if only then
		only.PivotOffset = CFrame.new()
		m.PrimaryPart = only
		m.WorldPivot = only.CFrame
	end
	local _, ext = m:GetBoundingBox()
	if ext.Y < 0.01 then m:Destroy() return nil end
	m:ScaleTo(m:GetScale() * height / ext.Y)
	m:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, yaw or 0, 0))
	local cf, e2 = m:GetBoundingBox()
	m:PivotTo(m:GetPivot() + (Vector3.new(x, y, z) - (cf.Position - Vector3.new(0, e2.Y / 2, 0))))
	m.Parent = parent
	return m
end
ValleyGen.svMesh = svMesh


--[[ v3.5 TREE SPACING (his report: "some assets are glitched in each other").
Measured: 124 valley tree pairs stood inside each other's crowns (a redwood
cluster had three trunks within 2.6 studs), and the Blender meshes are wider
than the Kenney trees they replaced (an oak is ~1.2x as wide as it is tall).
Every tree placement in the world now asks for room first: a crown radius from
the mesh's real proportions, and no new trunk closer than ROOM x (r1 + r2) to
an existing one. Crowns may touch; they may not grow through each other.
Shared with CampusArch and CityKit so the campus and the street respect the
valley's trees too (one registry, cleared at the start of each build). ]]
local ROOM = 0.8
local TREE_CELL = 16
local treeGrid = {}
local aspectCache = {}

function ValleyGen.resetTrees() treeGrid = {} end

-- width / height of a library mesh (SVMeshes), for a crown radius before placing
function ValleyGen.meshAspect(name)
	if aspectCache[name] then return aspectCache[name] end
	local lib = game:GetService("ReplicatedStorage"):FindFirstChild("SVMeshes")
	local t = lib and name and lib:FindFirstChild(name)
	local a = 0.6
	if t then
		local sz
		if t:IsA("Model") then sz = select(2, t:GetBoundingBox()) else sz = t.Size end
		if sz.Y > 0.01 then a = math.max(sz.X, sz.Z) / sz.Y end
	end
	aspectCache[name] = a
	return a
end

function ValleyGen.treeRoom(x, z, r)
	local reach = r + 12
	for gx = math.floor((x - reach) / TREE_CELL), math.floor((x + reach) / TREE_CELL) do
		for gz = math.floor((z - reach) / TREE_CELL), math.floor((z + reach) / TREE_CELL) do
			local cell = treeGrid[gx .. "," .. gz]
			if cell then
				for _, t in ipairs(cell) do
					local dx, dz = x - t[1], z - t[2]
					if dx * dx + dz * dz < (ROOM * (r + t[3])) ^ 2 then return false end
				end
			end
		end
	end
	return true
end

function ValleyGen.claimTree(x, z, r)
	local k = math.floor(x / TREE_CELL) .. "," .. math.floor(z / TREE_CELL)
	treeGrid[k] = treeGrid[k] or {}
	table.insert(treeGrid[k], { x, z, r })
end

local function kenneyTree(name, x, y, z, height, leaf, bark, yaw, parent)
	local t = kit(name)
	if not t or not t:IsA("Model") then return nil end
	local m = t:Clone()
	local _, ext = m:GetBoundingBox()
	if ext.Y < 0.05 then m:Destroy() return nil end
	m:ScaleTo(height / ext.Y)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.CastShadow = false
			local n = d.Name:lower()
			if n:find("trunk") then d.Color = bark elseif leaf then d.Color = leaf end
		end
	end
	m:PivotTo(CFrame.new(x, y - 0.2, z) * CFrame.Angles(0, yaw or 0, 0))
	m.Parent = parent
	return m
end
ValleyGen.kenneyTree = kenneyTree

-- species: leaf colour, bark colour, height range, Kenney models
local SPECIES = {
	oak      = { leaf = Color3.fromRGB(78, 102, 58),  bark = Color3.fromRGB(86, 68, 50),   h = { 11, 16 }, models = { "tree_oak", "tree_default", "tree_detailed" }, mesh = { "Oak_A", "Oak_B" } },
	redwood  = { leaf = Color3.fromRGB(46, 74, 52),   bark = Color3.fromRGB(110, 62, 44),  h = { 20, 30 }, models = { "tree_pineTallA", "tree_pineRoundA" }, mesh = { "Redwood_A" } },
	sycamore = { leaf = Color3.fromRGB(112, 150, 82), bark = Color3.fromRGB(196, 186, 168), h = { 12, 17 }, models = { "tree_default", "tree_tall" }, mesh = { "Oak_A", "Oak_B" } },
	eucalypt = { leaf = Color3.fromRGB(104, 128, 104), bark = Color3.fromRGB(200, 190, 172), h = { 22, 34 }, models = { "tree_tall", "tree_tall", "tree_default" }, mesh = { "Eucalypt_A" } },
	orchard  = { leaf = Color3.fromRGB(100, 146, 70), bark = Color3.fromRGB(96, 74, 54),    h = { 6, 7.5 }, models = { "tree_default", "tree_oak" }, mesh = { "Orchard_A" } },
}
local function grow(species, rng, x, y, z, parent)
	local sp = SPECIES[species]
	local h = rng:NextNumber(sp.h[1], sp.h[2])
	local meshName = sp.mesh and sp.mesh[rng:NextInteger(1, #sp.mesh)]
	local r = h * ValleyGen.meshAspect(meshName) / 2
	if not ValleyGen.treeRoom(x, z, r) then return false end     -- no room: never plant inside another tree
	ValleyGen.claimTree(x, z, r)
	if meshName and svMesh(meshName, x, y - 0.2, z, h, rng:NextNumber(0, 6.28), parent) then return true end
	if kenneyTree(sp.models[rng:NextInteger(1, #sp.models)], x, y, z, h, sp.leaf, sp.bark, rng:NextNumber(0, 6.28), parent) then return true end
	-- primitive fallback: trunk + two faceted blocks
	scenery({ Name = "Trunk", Size = Vector3.new(1.2, h * 0.5, 1.2), CFrame = CFrame.new(x, y + h * 0.25, z), Color = sp.bark, Material = Enum.Material.Wood }, parent)
	for k = 1, 2 do
		local s = h * (0.55 - k * 0.1)
		scenery({ Name = "Leaf", Size = Vector3.new(s, s * 0.8, s), CFrame = CFrame.new(x, y + h * (0.45 + k * 0.18), z) * CFrame.Angles(0, k, 0.3),
			Color = sp.leaf, Material = Enum.Material.SmoothPlastic }, parent)
	end
	return true
end
ValleyGen.grow = grow

--[[
	Plants by rejection sampling against the SAME height function and the SAME
	classifier the terrain was written from: oaks only on oak-woodland ground,
	redwoods only on the forested crest, nothing in a flat rect or the water.
	Only the near faces of the hills get trees: terrain past ~650 studs is
	culled on low-end phones, and a tree floating over culled ground is worse
	than none.
]]
function ValleyGen.plant(height, flatInfo, region, parent, opts)
	local rng = Random.new(opts.seed or 11)
	local function slopeAt(x, z)
		local hx = height(x + 3, z) - height(x - 3, z)
		local hz = height(x, z + 3) - height(x, z - 3)
		return math.sqrt(hx * hx + hz * hz) / 6
	end
	local sx = opts.stretchX or 1.35
	local made = { oaks = 0, redwoods = 0, verge = 0 }

	-- oak clusters on the hills: accept a seed point, then 1-3 neighbours
	local tries = 0
	while made.oaks < (opts.oaks or 150) and tries < 6000 do
		tries += 1
		local a = rng:NextNumber(0, math.pi * 2)
		local mtn = mountainData()
		local rmax = mtn and math.min(opts.treeMax or 640, mtn.data.seam - 10) or (opts.treeMax or 640)
		local r = rng:NextNumber((opts.basin or 430) - 20, rmax)
		local x, z = math.cos(a) * r * sx, math.sin(a) * r
		if math.abs(x) < 900 then
			local h = height(x, z)
			local fw, rect = flatInfo(x, z)
			local rg = region(x, z, h)
			if fw < 0.05 and h > 4 and rg.bay < 0.3 and ValleyGen.classify(x, z, h, slopeAt(x, z), fw, rect, rg, opts) == "Mud" then
				local south = rg.side < 0.5 and h > 55
				for k = 0, rng:NextInteger(1, 3) do
					local tx, tz = x + (k > 0 and rng:NextNumber(-11, 11) or 0), z + (k > 0 and rng:NextNumber(-11, 11) or 0)
					local th = height(tx, tz)
					local tfw, trect = flatInfo(tx, tz)
					local trg = region(tx, tz, th)
					if th > 3 and trg.bay < 0.3 and tfw < 0.05 and slopeAt(tx, tz) < 0.95
						and ValleyGen.classify(tx, tz, th, slopeAt(tx, tz), tfw, trect, trg, opts) == "Mud" then
						if south then
							if made.redwoods < (opts.redwoods or 90) and grow("redwood", rng, tx, th, tz, parent) then made.redwoods += 1 end
						else
							if grow("oak", rng, tx, th, tz, parent) then made.oaks += 1 end
						end
					end
				end
			end
		end
	end

	-- VERGE TREES: sycamores and oaks just outside the flat rects, so the
	-- campuses and the road are framed without anything standing on them
	local flatRects = opts.flatRects or {}
	local function edgeDist(x, z)
		local best = math.huge
		for _, r in ipairs(flatRects) do
			local dx = math.max(math.abs(x - r.x) - r.w / 2, 0)
			local dz = math.max(math.abs(z - r.z) - r.d / 2, 0)
			local dist = math.sqrt(dx * dx + dz * dz)
			if dist < best then best = dist end
		end
		return best
	end
	tries = 0
	while made.verge < (opts.vergeTrees or 0) and tries < 6000 do
		tries += 1
		local x = rng:NextNumber(-(opts.settlementX or 560), opts.settlementX or 560)
		local z = rng:NextNumber(-(opts.settlementZ or 280), opts.settlementZ or 280)
		local ed = edgeDist(x, z)
		local inOrchard = false
		for _, o in ipairs(opts.orchards or {}) do if inRect(x, z, o) then inOrchard = true end end
		if ed > 6 and ed < 44 and not inOrchard then
			if grow((rng:NextNumber() < 0.5) and "sycamore" or "oak", rng, x, height(x, z), z, parent) then made.verge += 1 end
		end
	end
	return made
end

-- ============ THE PLACE ITSELF ============

-- a California fan palm: a slightly bent, tapering trunk and a crown of fronds
local PALM_TRUNK = Color3.fromRGB(150, 122, 92)
local PALM_TRUNK_2 = Color3.fromRGB(128, 104, 80)
local PALM_LEAF = Color3.fromRGB(78, 124, 62)
local PALM_LEAF_2 = Color3.fromRGB(96, 140, 70)
local function palm(rng, x, y, z, parent)
	local pname = (rng:NextNumber() < 0.5) and "Palm_A" or "Palm_B"
	local ph = rng:NextNumber(20, 26)
	local pr = ph * ValleyGen.meshAspect(pname) / 2 * 0.7      -- fronds are sparse: a palm may lean into a neighbour's edge
	if not ValleyGen.treeRoom(x, z, pr) then return nil end
	ValleyGen.claimTree(x, z, pr)
	local mesh = svMesh(pname, x, y - 0.2, z, ph, rng:NextNumber(0, 6.28), parent)
	if mesh then return mesh end
	local m = Instance.new("Model")
	m.Name = "Palm"
	local h = rng:NextNumber(20, 27)
	local lean = CFrame.Angles(rng:NextNumber(-0.07, 0.07), 0, rng:NextNumber(-0.07, 0.07))
	local cf = CFrame.new(x, y, z) * lean
	-- round, ringed, tapering: four cylinder segments in two bark tones
	local seg = h / 4
	for k = 0, 3 do
		local d = 1.7 - k * 0.14
		scenery({ Name = "Trunk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(seg + 0.2, d, d),
			CFrame = cf * CFrame.new(0, seg * (k + 0.5), 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = (k % 2 == 0) and PALM_TRUNK or PALM_TRUNK_2, Material = Enum.Material.Wood }, m)
	end
	local top = cf * CFrame.new(0, h, 0)
	scenery({ Name = "Crown", Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 2.4, 2.4), CFrame = top, Color = PALM_TRUNK_2, Material = Enum.Material.Wood }, m)
	-- nine fronds: most droop, every third stands up (a real crown is layered)
	for k = 1, 9 do
		local a = (k / 9) * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local droop = (k % 3 == 0) and rng:NextNumber(-0.25, 0.05) or rng:NextNumber(0.5, 0.9)
		local len = rng:NextNumber(8, 10.5)
		scenery({ Name = "Frond", Size = Vector3.new(1.4, 0.2, len),
			CFrame = top * CFrame.Angles(0, a, 0) * CFrame.Angles(-droop, 0, 0) * CFrame.new(0, 0, -len / 2),
			Color = (k % 2 == 0) and PALM_LEAF or PALM_LEAF_2, Material = Enum.Material.SmoothPlastic }, m)
	end
	m.Parent = parent
	return m
end

local WHITE = Color3.fromRGB(236, 236, 232)
local CONCRETE = Color3.fromRGB(176, 172, 164)

-- THE DISH: Stanford's radio telescope, a white dish on a golden hill
local function theDish(height, x, z, parent)
	local y = height(x, z)
	if svMesh("TheDish", x, y - 0.8, z, 44, 0, parent) then return end
	local m = Instance.new("Model")
	m.Name = "TheDish"
	-- a deep pad: on a sloped foothill it is sunk into the uphill side, never floating on the downhill one
	scenery({ Name = "Pad", Size = Vector3.new(18, 14, 18), CFrame = CFrame.new(x, y - 5.4, z), Color = CONCRETE, Material = Enum.Material.Concrete }, m)
	for _, o in ipairs({ { -5, -5 }, { 5, -5 }, { -5, 5 }, { 5, 5 } }) do
		scenery({ Name = "Leg", Size = Vector3.new(1.2, 16, 1.2), CFrame = CFrame.new(x + o[1] * 0.6, y + 8, z + o[2] * 0.6) * CFrame.Angles(o[2] * 0.02, 0, -o[1] * 0.02),
			Color = WHITE, Material = Enum.Material.Metal }, m)
	end
	-- the dish faces north-up, toward the valley (and the sky)
	local tilt = CFrame.new(x, y + 20, z) * CFrame.Angles(math.rad(55), 0, 0)
	scenery({ Name = "Dish", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 40, 40), CFrame = tilt * CFrame.Angles(0, 0, math.rad(90)),
		Color = WHITE, Material = Enum.Material.SmoothPlastic }, m)
	scenery({ Name = "DishFace", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 34, 34), CFrame = tilt * CFrame.new(0, 0.7, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(214, 216, 214), Material = Enum.Material.SmoothPlastic }, m)
	scenery({ Name = "Feed", Size = Vector3.new(0.6, 14, 0.6), CFrame = tilt * CFrame.new(0, 7.5, 0), Color = WHITE, Material = Enum.Material.Metal }, m)
	scenery({ Name = "FeedHorn", Size = Vector3.new(2.2, 2.2, 2.2), CFrame = tilt * CFrame.new(0, 14.5, 0), Color = WHITE, Material = Enum.Material.Metal }, m)
	m.Parent = parent
end

-- LICK OBSERVATORY: two white domes on the highest peak of the Diablo Range
local function lick(height, x, z, parent)
	local y = height(x, z)
	if svMesh("LickObservatory", x, y - 0.6, z, 17, 0, parent) then return end
	local m = Instance.new("Model")
	m.Name = "LickObservatory"
	scenery({ Name = "Hall", Size = Vector3.new(34, 7, 10), CFrame = CFrame.new(x, y + 2.5, z), Color = WHITE, Material = Enum.Material.Concrete }, m)
	for _, d in ipairs({ { -15, 16 }, { 16, 11 } }) do
		local dx, size = d[1], d[2]
		scenery({ Name = "Drum", Shape = Enum.PartType.Cylinder, Size = Vector3.new(size * 0.55, size, size),
			CFrame = CFrame.new(x + dx, y + 1.5 + size * 0.275, z) * CFrame.Angles(0, 0, math.rad(90)), Color = WHITE, Material = Enum.Material.Concrete }, m)
		scenery({ Name = "Dome", Shape = Enum.PartType.Ball, Size = Vector3.new(size, size, size),
			CFrame = CFrame.new(x + dx, y + 1.5 + size * 0.55, z), Color = Color3.fromRGB(244, 244, 240), Material = Enum.Material.SmoothPlastic }, m)
	end
	m.Parent = parent
end

-- HANGAR ONE: Moffett Field's giant airship hangar by the Bay
local function hangarOne(height, x, z, parent)
	local y = math.max(height(x, z), 0)
	if svMesh("HangarOne", x, y - 0.2, z, 30, math.pi / 2, parent) then return end
	local m = Instance.new("Model")
	m.Name = "HangarOne"
	local len, dia = 150, 56
	scenery({ Name = "Shell", Shape = Enum.PartType.Cylinder, Size = Vector3.new(len, dia, dia), CFrame = CFrame.new(x, y - dia * 0.12, z),
		Color = Color3.fromRGB(176, 180, 184), Material = Enum.Material.Metal }, m)
	for k = -3, 3 do
		scenery({ Name = "Rib", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, dia + 0.8, dia + 0.8), CFrame = CFrame.new(x + k * (len / 7), y - dia * 0.12, z),
			Color = Color3.fromRGB(120, 124, 130), Material = Enum.Material.Metal }, m)
	end
	scenery({ Name = "Apron", Size = Vector3.new(len + 40, 0.6, dia + 30), CFrame = CFrame.new(x, y + 0.2, z), Color = Color3.fromRGB(150, 150, 146), Material = Enum.Material.Concrete }, m)
	m.Parent = parent
end

--[[ THE CALTRAIN LINE: a ballast bed and two rails on the rail flat rect,
a station behind the middle campus, and a tunnel portal where the line
enters the eastern hills. The TRAIN itself is client-side (LifeClient). ]]
local function railway(opts, parent)
	local rail = opts.rail
	local m = Instance.new("Model")
	m.Name = "Railway"
	local len = rail.x2 - rail.x1
	local cx = (rail.x1 + rail.x2) / 2
	local y = 0.3
	scenery({ Name = "Ballast", Size = Vector3.new(len, 0.6, 12), CFrame = CFrame.new(cx, y, rail.z), Color = Color3.fromRGB(128, 120, 110), Material = Enum.Material.Pebble }, m)
	for _, dz in ipairs({ -2.6, 2.6 }) do
		scenery({ Name = "Rail", Size = Vector3.new(len, 0.4, 0.4), CFrame = CFrame.new(cx, y + 0.5, rail.z + dz), Color = Color3.fromRGB(96, 92, 88), Material = Enum.Material.Metal }, m)
	end
	-- a portal at each end: two concrete walls, a header, and a dark mouth the
	-- train drives into (the line runs between two hills, never off the map)
	for _, end_ in ipairs({ { rail.x2, 1 }, { rail.x1, -1 } }) do
		local px, inward = end_[1], end_[2]
		for _, s in ipairs({ -1, 1 }) do
			scenery({ Name = "PortalWall", Size = Vector3.new(6, 24, 5), CFrame = CFrame.new(px, 12, rail.z + s * 10.5), Color = CONCRETE, Material = Enum.Material.Concrete }, m)
		end
		scenery({ Name = "PortalTop", Size = Vector3.new(6, 6, 26), CFrame = CFrame.new(px, 21, rail.z), Color = CONCRETE, Material = Enum.Material.Concrete }, m)
		scenery({ Name = "Mouth", Size = Vector3.new(1, 18, 16), CFrame = CFrame.new(px + inward * 1.5, 9, rail.z), Color = Color3.fromRGB(14, 14, 16), Material = Enum.Material.SmoothPlastic }, m)
	end
	-- the station: a platform, a canopy on posts, and the name
	local st = rail.station
	local pz = rail.z + 9
	scenery({ Name = "Platform", Size = Vector3.new(90, 1.2, 8), CFrame = CFrame.new(st, 0.6, pz), Color = CONCRETE, Material = Enum.Material.Concrete }, m)
	scenery({ Name = "Edge", Size = Vector3.new(90, 0.1, 0.8), CFrame = CFrame.new(st, 1.26, pz - 3.6), Color = Color3.fromRGB(240, 200, 60), Material = Enum.Material.SmoothPlastic }, m)
	for k = -2, 2 do
		scenery({ Name = "Post", Size = Vector3.new(0.6, 9, 0.6), CFrame = CFrame.new(st + k * 16, 5.7, pz + 2), Color = Color3.fromRGB(90, 94, 100), Material = Enum.Material.Metal }, m)
	end
	scenery({ Name = "Canopy", Size = Vector3.new(76, 0.6, 7), CFrame = CFrame.new(st, 10.4, pz + 1), Color = Color3.fromRGB(196, 42, 44), Material = Enum.Material.SmoothPlastic }, m)
	local sign = scenery({ Name = "Sign", Size = Vector3.new(22, 3, 0.4), CFrame = CFrame.new(st, 8, pz + 3.6), Color = Color3.fromRGB(28, 30, 36), Material = Enum.Material.SmoothPlastic }, m)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.PixelsPerStud = 24
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.Parent = sign
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, 0, 1, 0)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(245, 245, 240)
	t.Text = "CALTRAIN  ·  MOUNTAIN VIEW"
	t.Parent = sg
	-- the sign faces the track (north side of the platform faces -z)
	sign.CFrame = CFrame.new(st, 8, pz + 3.6) * CFrame.Angles(0, math.pi, 0)
	m.Parent = parent
	return m
end

--[[ Everything that makes the valley THIS valley: palms along the main road,
a eucalyptus windbreak behind the railway, orchards, the three landmarks,
the railway. ]]
function ValleyGen.dress(height, flatInfo, region, parent, opts)
	local rng = Random.new((opts.seed or 7) + 101)
	local made = { palms = 0, eucalypts = 0, orchard = 0, landmarks = 0 }

	-- PALMS: both verges of the main road, 25 studs off every street lamp,
	-- clear of the cross streets and each campus entrance path
	for _, side in ipairs({ -1, 1 }) do
		for x = -525, 600, 50 do
			local clear = true
			for _, cx in ipairs(opts.crossX or {}) do if math.abs(x - cx) < 40 then clear = false end end
			for _, px in ipairs(opts.plotX or {}) do if math.abs(x - px) < 18 then clear = false end end
			if clear then
				if palm(rng, x + rng:NextNumber(-3, 3), 0, side * 31, parent) then made.palms += 1 end
			end
		end
	end

	-- EUCALYPTUS WINDBREAK: the tall blue-grey row every valley farm planted
	-- (irregular on purpose: a planted row that grew for 80 years, not a fence;
	-- open behind the station so the train reads from the middle campus)
	if opts.rail then
		local x = opts.rail.x1 + 360
		while x < 470 do
			if math.abs(x - (opts.rail.station or 0)) > 80 and rng:NextNumber() > 0.16 then
				local z = opts.rail.z - 26 + rng:NextNumber(-5, 5)
				if grow("eucalypt", rng, x, height(x, z), z, parent) then made.eucalypts += 1 end
			end
			x += rng:NextNumber(11, 24)
		end
	end

	-- ORCHARDS: rows of small fruit trees on dirt, the old Santa Clara Valley
	for _, o in ipairs(opts.orchards or {}) do
		for x = o.x - o.w / 2 + 5, o.x + o.w / 2 - 5, 10 do
			for z = o.z - o.d / 2 + 5, o.z + o.d / 2 - 5, 9 do
				if grow("orchard", rng, x + rng:NextNumber(-0.6, 0.6), height(x, z), z, parent) then made.orchard += 1 end
			end
		end
	end

	-- LANDMARKS: placed by searching the terrain, not by guessing coordinates
	local function best(xs, zs, score)
		local bx, bz, bs = nil, nil, -math.huge
		for x = xs[1], xs[2], 12 do
			for z = zs[1], zs[2], 12 do
				local s = score(x, z)
				if s and s > bs then bx, bz, bs = x, z, s end
			end
		end
		return bx, bz
	end
	local function slopeAt(x, z)
		local hx = height(x + 4, z) - height(x - 4, z)
		local hz = height(x, z + 4) - height(x, z - 4)
		return math.sqrt(hx * hx + hz * hz) / 8
	end
	-- The Dish: a gentle south foothill, 45-95 studs up, facing the campuses
	local dx, dz = best({ -360, 240 }, { -600, -420 }, function(x, z)
		local h = height(x, z)
		if h < 25 or h > 110 or slopeAt(x, z) > 1.1 or flatInfo(x, z) > 0.05 then return nil end
		return -math.abs(x + 60) * 0.15 - slopeAt(x, z) * 60
	end)
	if dx then theDish(height, dx, dz, parent); made.landmarks += 1 end
	-- Lick: the highest point on the north side that still renders on a phone
	local lx, lz = best({ -560, 560 }, { 440, 620 }, function(x, z)
		if region(x, z, 0).r > 660 then return nil end
		return height(x, z)
	end)
	if lx then lick(height, lx, lz, parent); made.landmarks += 1 end
	-- Hangar One: on the flat by the salt ponds at the bay edge, where the real
	-- one stands at Moffett Field, its length along the shore (north-south).
	-- The mesh is 180 x 82; at x -564 (the old spot) its east end sat 6 studs
	-- off plot 4's campus edge. Measured flat (y 0) from x -940 to -790.
	local hx, hz = best({ -900, -830 }, { 60, 260 }, function(x, z)
		local h = height(x, z)
		if h < -0.5 or h > 3 or slopeAt(x, z) > 0.08 or flatInfo(x, z) > 0.05 then return nil end
		return -math.abs(h) - math.abs(x + 865) * 0.01 - math.abs(z - 150) * 0.005
	end)
	if hx then hangarOne(height, hx, hz, parent); made.landmarks += 1 end

	if opts.rail then railway(opts, parent) end
	return made
end

-- ============ ONE CALL ============

function ValleyGen.build(world, opts)
	ValleyGen.resetTrees()
	local Terrain = workspace.Terrain
	Terrain:Clear()
	for name, c in pairs(PALETTE) do
		pcall(function() Terrain:SetMaterialColor(Enum.Material[name], c) end)
	end
	-- v3.4 CUSTOM SURFACES, judged on screen A/B: of five Material Generator
	-- surfaces only the campus pavers beat the built-in material. The golden
	-- grass read burnt orange, the lawn neon, the oak canopy near-black blotches
	-- and the wall panel zebra stripes, so those are NOT applied (and any
	-- override a previous build left behind is cleared). Pavers: CampusArch.pathRun.
	local MS = game:GetService("MaterialService")
	for _, base in ipairs({ "Grass", "Mud", "LeafyGrass" }) do
		pcall(function() MS:SetBaseMaterialOverride(Enum.Material[base], "") end)
	end
	local pav = MS:FindFirstChild("SV_CampusPavers", true)
	if pav and pav:IsA("MaterialVariant") then pav.StudsPerTile = 8 end

	-- the Bay: grey-green, a little clear, small waves
	Terrain.WaterColor = Color3.fromRGB(62, 104, 112)
	Terrain.WaterTransparency = 0.45
	Terrain.WaterReflectance = 0.25
	Terrain.WaterWaveSize = 0.12
	Terrain.WaterWaveSpeed = 7

	-- LIFE the whole map shares: wind in the grass and drifting clouds
	workspace.GlobalWind = Vector3.new(6, 0, -2.5)
	local clouds = Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	-- v3.6: thinner, now that the skybox paints its own cumulus above the ridges
	-- (at 0.5 the grey undersides of these covered the painted sky); they stay
	-- because they are the sky's only motion
	clouds.Cover = 0.36
	clouds.Density = 0.3
	clouds.Color = Color3.fromRGB(255, 255, 255)
	clouds.Parent = Terrain

	local bp = workspace:FindFirstChild("Baseplate")
	if bp then bp:Destroy() end

	-- the shared Kenney trees (campus lawns, street trees) were a candy green
	-- that read as a toy next to golden hills: one natural palette for all of them
	local TONE = {
		tree_default = { Color3.fromRGB(88, 134, 70), Color3.fromRGB(110, 84, 60) },
		tree_oak = { Color3.fromRGB(80, 122, 64), Color3.fromRGB(104, 80, 58) },
		tree_detailed = { Color3.fromRGB(92, 138, 72), Color3.fromRGB(110, 84, 60) },
		tree_tall = { Color3.fromRGB(96, 132, 84), Color3.fromRGB(150, 130, 108) },
		tree_pineTallA = { Color3.fromRGB(62, 104, 74), Color3.fromRGB(104, 76, 56) },
		tree_pineRoundA = { Color3.fromRGB(66, 108, 76), Color3.fromRGB(104, 76, 56) },
		plant_bushLarge = { Color3.fromRGB(84, 128, 66), Color3.fromRGB(84, 128, 66) },
		plant_bushDetailed = { Color3.fromRGB(88, 132, 68), Color3.fromRGB(88, 132, 68) },
	}
	for name, c in pairs(TONE) do
		local t = kit(name)
		if t then
			for _, d in ipairs(t:GetDescendants()) do
				if d:IsA("BasePart") then d.Color = d.Name:lower():find("trunk") and c[2] or c[1] end
			end
		end
	end

	local height, flatInfo, region = ValleyGen.makeHeight(opts)
	local t0 = os.clock()
	local lp = lowPoly()
	local chunks, maxH = 0, 0
	local placeH = height
	if lp then
		-- v4.1: no terrain at all. Everything placed below stands on the facets.
		local lpH = makeLpHeight(lp.data.grid)
		placeH = function(x, z) return lpH(x, z) or height(x, z) end
		local tc = Terrain:FindFirstChildOfClass("Clouds")
		if tc then tc:Destroy() end        -- faceted clouds instead (buildLowPoly)
	else
		chunks, maxH = ValleyGen.writeTerrain(height, flatInfo, region, opts)
	end
	ValleyGen.groundHeight = placeH

	local folder = Instance.new("Folder")
	folder.Name = "Valley"
	folder.Parent = world
	local plantOpts = opts
	if lp then
		-- the hill oaks and redwoods come with the facets (LowPolyData.trees)
		plantOpts = table.clone(opts)
		plantOpts.oaks, plantOpts.redwoods = 0, 0
	end
	local made = ValleyGen.plant(placeH, flatInfo, region, folder, plantOpts)
	local dressed = ValleyGen.dress(placeH, flatInfo, region, folder, opts)

	-- the edge of the walkable valley: invisible, a ring round the seam (not across the Bay)
	local function edgeRing(parent, seam, sx)
		local N = 160
		for k = 0, N - 1 do
			local a0, a1 = 2 * math.pi * k / N, 2 * math.pi * (k + 1) / N
			local p0 = Vector3.new(math.cos(a0) * seam * sx, 0, math.sin(a0) * seam)
			local p1 = Vector3.new(math.cos(a1) * seam * sx, 0, math.sin(a1) * seam)
			local mid = (p0 + p1) / 2
			if not bayRect(mid.X, mid.Z) then
				local y = placeH(mid.X, mid.Z)
				local w = Instance.new("Part")
				w.Name = "ValleyEdge"
				w.Anchored = true
				w.CanQuery = false
				w.CanTouch = false
				w.CastShadow = false
				w.Transparency = 1
				w.Size = Vector3.new((p1 - p0).Magnitude + 2, 90, 2)
				w.CFrame = CFrame.lookAt(Vector3.new(mid.X, y + 30, mid.Z), Vector3.new(mid.X, y + 30, mid.Z) + (p1 - p0).Unit) * CFrame.Angles(0, math.pi / 2, 0)
				w.Parent = parent
			end
		end
	end

	if lp then
		local lm = ValleyGen.buildLowPoly(world, lp, placeH, opts)
		edgeRing(world:FindFirstChild("LowPolyWorld"), 600 - 18, opts.stretchX or 1.35)
		print(("[SV] low-poly valley: %d tiles, %d collision wedges, %d hill trees, %d ponds, %d clouds")
			:format(lm.tiles, lm.wedges, lm.trees, lm.ponds, lm.clouds))
	end

	-- THE MESH MOUNTAINS (v4.0, the painted ranges): only without the low-poly set
	local mtn = (not lp) and mountainData()
	if mtn then
		local mf = Instance.new("Folder")
		mf.Name = "Mountains"
		mf.Parent = world
		local tiles = 0
		for name, t in pairs(mtn.data.tiles) do
			local tpl = mtn.folder:FindFirstChild(name)
			local src = tpl and (tpl:IsA("BasePart") and tpl or tpl:FindFirstChildWhichIsA("MeshPart", true))
			if src then
				local p = src:Clone()
				p.Name = name
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.CastShadow = false
				p.PivotOffset = CFrame.new()
				p.CFrame = CFrame.new(t.c)
				p.Parent = mf
				tiles += 1
			end
		end
		local trng = Random.new(19)
		local trees = 0
		for _, t in ipairs(mtn.data.trees) do
			local kind = t[4]
			local h = kind == "Redwood_A" and trng:NextNumber(24, 32) or trng:NextNumber(12, 16)
			if svMesh(kind, t[1], t[2] - 0.4, t[3], h, trng:NextNumber(0, 6.28), mf) then trees += 1 end
		end
		-- the edge of the walkable valley: invisible, only where the terrain stops
		edgeRing(mf, mtn.data.seam - 18, opts.stretchX or 1.35)
		print(("[SV] mountains: %d mesh tiles, %d slope trees, seam %.0f"):format(tiles, trees, mtn.data.seam))
	end

	-- THE BAY TO THE HORIZON. Terrain past ~600 studs is not drawn on low-end
	-- phones (or in Studio at low quality), which left a grey hole where the Bay
	-- should be. A part draws much further: one flat sheet of bay water under
	-- the terrain water, visible wherever the terrain is culled or ends.
	if not lp then       -- (the low-poly world lays its own water at the water line)
		scenery({ Name = "BayWater", Size = Vector3.new(2048, 1, 2048), CFrame = CFrame.new(-(opts.bayX or 640) - 1060, -5.2, 0),
			Color = Color3.fromRGB(70, 108, 116), Material = Enum.Material.SmoothPlastic, Reflectance = 0.12 }, folder)
	end

	return {
		chunks = chunks, maxHeight = maxH, seconds = os.clock() - t0,
		oaks = made.oaks, redwoods = made.redwoods, verge = made.verge,
		palms = dressed.palms, eucalypts = dressed.eucalypts, orchard = dressed.orchard, landmarks = dressed.landmarks,
		height = height,
	}
end

return ValleyGen
