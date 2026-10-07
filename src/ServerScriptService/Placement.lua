--[[
	Placement -- the one place that decides whether a spot is free (v5.0).

	WHY THIS EXISTS, and why the same bug kept coming back.

	Five separate systems grew up to stop things overlapping, one per
	screenshot:

	    ValleyGen.claimTree    a tree may not grow inside another tree
	    Ground.sweep           greenery standing on reserved paving is removed
	    Wafers.clearFootprint  anything inside a building footprint is removed
	    FurnitureKit.blocked   placed decor may not sit inside room furniture
	    CampusArch.tree        try three scales, then give up

	Each knows about exactly ONE pair of categories. The number of PAIRS grows
	with the square of the number of builders, so every new builder reopened
	the bug somewhere none of the five were looking. That is the whole answer
	to "why does this keep happening": a rule was added per incident instead
	of an invariant per world.

	Two specific ways the old rules went blind, both measured 5 Oct:

	  1. THEY ENUMERATE NAMES. Ground's sweep knew ParkWalk and RoadKerb but
	     not RingStreet or StreetWalk, because those were invented later. A
	     check written as a list of names keeps PASSING while it quietly
	     covers less of the world. Of 967 paved parts in the live game, only
	     8 zones had ever been reserved -- the ring roads, the longest paved
	     thing in the valley, were never registered at all.

	  2. THEY ONLY SWEPT THE VALLEY. The sweep spared each builder's own
	     decor so it could not delete something planted on purpose. 100 of
	     the 169 overlaps turned out to be CampusHub's own trees standing in
	     CampusHub's own footpaths -- inside the one folder the sweep was
	     told never to touch.

	SO SURFACES ARE IDENTIFIED BY GEOMETRY, NOT BY NAME. A hard surface is a
	broad, thin, horizontal part that is not green. That test cannot go stale
	when somebody adds a builder, because a new road is still broad, thin,
	horizontal and grey.

	AND IT DOES NOT ONLY DELETE. A tree at a kerb is not wrong -- real
	streets are lined with them. What is wrong is a trunk bursting through
	tarmac with nothing around it. So a small intrusion gets a PIT: a stone
	surround set into the paving, which is what a street tree has in life.
	Only an intrusion too large for a pit is moved, and only a tree with
	nowhere to move is removed.

	Shape of the thing: a uniform grid of claims, which is ValleyGen's
	existing tree grid generalised. ValleyGen.treeRoom / claimTree delegate
	here, so every caller it already had -- the valley, the campus and the
	street -- becomes surface-aware with no change at the call site.
]]

local CollectionService = game:GetService("CollectionService")

local Placement = {}

-- ---------------------------------------------------------------- tuning
local CELL = 16                  -- grid cell, studs
local ROOM = 0.8                 -- two crowns may touch at 0.8 x (r1 + r2)
local PIT_MAX = 4.0              -- how far from the kerb a tree pit still reads as deliberate
--[[ 14 was too short: the first live run moved only 13 trees and DELETED 145,
	because a tree standing in the middle of a ring road has no clear ground
	within 14 studs and removal was the only branch left. 30 reaches past a
	carriageway to the verge on the far side, which is where a tree wants to
	be anyway, and turns most of those deletions into moves. ]]
local NUDGE_MAX = 30
local NUDGE_STEPS = 16
local EDGE = 0.3                 -- a trunk this close to the kerb line is on it, not in it

-- what counts as a hard surface, by shape alone
local FLAT_DOT = 0.9             -- upright enough to be a floor
local MAX_THICK = 5              -- thicker than this is a wall or a block
local MIN_AREA = 60              -- smaller than this is a prop, not a surface

-- ---------------------------------------------------------------- state
local claims = {}                -- cell -> { {x, z, r} }
local surfaces = {}              -- { cf, hx, hz, top, part }
local surfGrid = {}              -- cell -> { index into surfaces }
local known = {}                 -- parts already registered, so a rescan is cheap

function Placement.reset()
	claims, surfaces, surfGrid, known = {}, {}, {}, {}
end

local function cellKey(x, z)
	return math.floor(x / CELL) .. "," .. math.floor(z / CELL)
end

-- ---------------------------------------------------------------- claims

function Placement.claim(x, z, r)
	local k = cellKey(x, z)
	claims[k] = claims[k] or {}
	table.insert(claims[k], { x, z, r })
end

-- room for a crown of radius r at (x, z), ignoring surfaces
function Placement.clearOfProps(x, z, r)
	local reach = r + 12
	for gx = math.floor((x - reach) / CELL), math.floor((x + reach) / CELL) do
		for gz = math.floor((z - reach) / CELL), math.floor((z + reach) / CELL) do
			local cell = claims[gx .. "," .. gz]
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

-- ---------------------------------------------------------------- surfaces

--[[ Green things are ground you may plant in; everything else broad, thin and
	horizontal is paving you may not. Tested against the live world: RoadVerge
	(122,170,80) and PadVerge read green, while RingRoadOut (64,64,68),
	RingWalkOut (196,188,172) and ParkWalk (222,215,200) do not. Judging by
	colour rather than by name is the point -- a builder added next month is
	classified correctly without telling anyone. ]]
local SOFT_MATERIAL = {
	[Enum.Material.Grass] = true, [Enum.Material.LeafyGrass] = true,
	[Enum.Material.Ground] = true, [Enum.Material.Mud] = true,
	[Enum.Material.Sand] = true, [Enum.Material.Snow] = true,
	[Enum.Material.Water] = true,
}

function Placement.isSoft(part)
	if SOFT_MATERIAL[part.Material] then return true end
	local c = part.Color
	return c.G > c.R + 0.06 and c.G > c.B + 0.06
end

--[[ A ROAD is a surface with vehicles on it, and the rule for greenery is
	stricter there than anywhere else: a branch over a FOOTPATH is what a
	street is supposed to look like, while a branch over a ROAD is a car
	driving through a tree. So trunks are banned from all paving and crowns
	are banned only from roads. ]]
function Placement.isRoad(part)
	if CollectionService:HasTag(part, "SVRoad") then return true end
	if part.Material == Enum.Material.Asphalt then return true end
	-- the invisible deck under the decorative city tiles
	return part.Transparency > 0.9 and part.CanCollide
		and part.Size.Y <= 2 and part.Size.X * part.Size.Z >= 600
end

function Placement.isHardSurface(part)
	--[[ The ground is not paving. ValleyGen tags what it builds as terrain,
		because shape alone cannot separate a car park from the field it was
		poured on: both are broad, thin, horizontal and not green. ]]
	if CollectionService:HasTag(part, "SVTerrain") then return false end
	--[[ AN INVISIBLE SURFACE IS STILL A SURFACE.

		Skipping transparent parts hid the one that matters most: the Kenney
		city tiles are decoration with no collision, and the thing cars
		actually drive on is RoadDeck -- 114 x 1 x 50, Transparency 1.00. So
		the checker could not see the road, and 99 trees ended up with their
		trunks standing in it while the pass reported "0 left".

		Third time this project has been bitten by filtering on visibility:
		the collision walls in the furniture check, the shell glass, and now
		the road. If it is collidable, something stands on it, and it counts. ]]
	if part.Transparency > 0.9 and not part.CanCollide then return false end
	local s = part.Size
	if s.Y > MAX_THICK then return false end
	if s.X * s.Z < MIN_AREA then return false end
	if part.CFrame.UpVector.Y < FLAT_DOT then return false end
	return not Placement.isSoft(part)
end

function Placement.addSurface(part)
	if known[part] then return nil end
	known[part] = true
	local s = part.Size
	local e = {
		cf = part.CFrame, hx = s.X / 2, hz = s.Z / 2,
		top = part.Position.Y + s.Y / 2, part = part,
		road = Placement.isRoad(part),
	}
	table.insert(surfaces, e)
	local i = #surfaces
	local p = part.Position
	local reach = math.max(s.X, s.Z) / 2
	for gx = math.floor((p.X - reach) / CELL), math.floor((p.X + reach) / CELL) do
		for gz = math.floor((p.Z - reach) / CELL), math.floor((p.Z + reach) / CELL) do
			local k = gx .. "," .. gz
			surfGrid[k] = surfGrid[k] or {}
			table.insert(surfGrid[k], i)
		end
	end
	return e
end

--[[ Register every hard surface under `root` by shape. Returns how many were
	taken and how many skipped, so a build that suddenly finds none is loud
	rather than silently permissive. ]]
function Placement.scanSurfaces(root)
	local found, skipped = 0, 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			if Placement.isHardSurface(d) then
				if Placement.addSurface(d) then found += 1 end
			else
				skipped += 1
			end
		end
	end
	return found, skipped
end

--[[ How far a disc of radius r at (x, z) reaches INTO hard paving, and which
	surface it is. 0 means clear. Measuring the intrusion rather than
	answering yes or no is what makes a pit possible: a trunk 1.5 studs over
	a kerb is a different problem from a bush 10 studs into a carriageway. ]]
function Placement.intrusion(x, z, r, y)
	local worst, which = 0, nil
	local reach = r + CELL
	for gx = math.floor((x - reach) / CELL), math.floor((x + reach) / CELL) do
		for gz = math.floor((z - reach) / CELL), math.floor((z + reach) / CELL) do
			local cell = surfGrid[gx .. "," .. gz]
			if cell then
				for _, i in ipairs(cell) do
					local s = surfaces[i]
					if (not y) or (s.top >= y - 8 and s.top <= y + 10) then
						local lp = s.cf:PointToObjectSpace(Vector3.new(x, s.cf.Position.Y, z))
						local dx = s.hx + r - math.abs(lp.X)
						local dz = s.hz + r - math.abs(lp.Z)
						if dx > 0 and dz > 0 then
							local pen = math.min(dx, dz, r * 2)
							if pen > worst then worst, which = pen, s end
						end
					end
				end
			end
		end
	end
	return worst, which
end

--[[ IS THE TRUNK ACTUALLY STANDING IN PAVING, and how far from the edge?

	The distinction matters and the first live run got it wrong. `intrusion`
	above tests a DISC against the surface, so a bush whose crown merely
	leans over a footpath came back as a violation and was given a stone pit
	standing half on the lawn. A crown over a path is not a fault -- it is
	what every street in the world looks like. A TRUNK in the carriageway is.

	So the audit asks the narrower question: is the centre of the thing
	inside the surface? Only then is there something to fix, and how far it
	is from the nearest edge decides whether a pit is honest or it has to
	move. ]]
function Placement.standingIn(x, z, y)
	local cell = surfGrid[cellKey(x, z)]
	if not cell then return nil, 0 end
	local best, bestDepth = nil, 0
	for _, i in ipairs(cell) do
		local s = surfaces[i]
		if (not y) or (s.top >= y - 8 and s.top <= y + 10) then
			local lp = s.cf:PointToObjectSpace(Vector3.new(x, s.cf.Position.Y, z))
			local dx = s.hx - math.abs(lp.X)
			local dz = s.hz - math.abs(lp.Z)
			--[[ EDGE is a tie-break, not slack. A trunk whose centre lands
				exactly on a kerb line measures 0.0 studs in, and a kerbside
				tree is what a street is supposed to look like. Below this the
				tree is ON the edge; above it the tree is IN the paving. ]]
			if dx > EDGE and dz > EDGE then
				local d = math.min(dx, dz)
				if d > bestDepth then best, bestDepth = s, d end
			end
		end
	end
	return best, bestDepth
end

--[[ Does this canopy reach out over a road? Same grid as standingIn, but the
	test is the crown circle against the road rectangle rather than the trunk
	centre against any paving. ]]
function Placement.overRoad(x, z, r, y)
	local reach = math.ceil(r / CELL)
	local gx, gz = math.floor(x / CELL), math.floor(z / CELL)
	for ix = gx - reach, gx + reach do
		for iz = gz - reach, gz + reach do
			local cell = surfGrid[ix .. "," .. iz]
			if cell then
				for _, i in ipairs(cell) do
					local sf = surfaces[i]
					if sf.road and ((not y) or (sf.top >= y - 8 and sf.top <= y + 10)) then
						local lp = sf.cf:PointToObjectSpace(Vector3.new(x, sf.cf.Position.Y, z))
						local dx = math.abs(lp.X) - sf.hx
						local dz = math.abs(lp.Z) - sf.hz
						if dx <= r and dz <= r then return sf, math.max(r - math.max(dx, dz), 0) end
					end
				end
			end
		end
	end
	return nil, 0
end

--[[ The one question a builder asks before planting: may I? Claims the spot
	on success, so two callers can never both be told yes for the same
	ground. `hard` lets a caller say "this prop belongs on paving" (a bollard,
	a bench, a lamp), which skips the surface test. ]]
function Placement.request(x, z, r, opts)
	opts = opts or {}
	if not Placement.clearOfProps(x, z, r) then return false, "prop" end
	if not opts.hard then
		local pen = Placement.intrusion(x, z, r * (opts.trunk or 0.35), opts.y)
		if pen > (opts.allow or 0) then return false, "paving" end
	end
	Placement.claim(x, z, r)
	return true
end

--[[ Walk a prop outward in a spiral until it is clear, within NUDGE_MAX.
	Returns the new x, z, or nil if nowhere within reach works. ]]
function Placement.nudge(x, z, r, opts)
	opts = opts or {}
	for step = 1, NUDGE_STEPS do
		local d = NUDGE_MAX * step / NUDGE_STEPS
		for k = 0, 7 do
			local a = (k / 8) * math.pi * 2 + step * 0.4
			local nx, nz = x + math.cos(a) * d, z + math.sin(a) * d
			--[[ The destination has to satisfy BOTH rules, or the move is not a
				fix. Checking only standingIn is why the final pass reported
				"68 moved, 36 left": a tree with its canopy over the road was
				relocated to ground that was clear of paving and still had its
				canopy over the road. ]]
			if Placement.clearOfProps(nx, nz, r)
				and not Placement.standingIn(nx, nz, opts.y)
				and not Placement.overRoad(nx, nz, r, opts.y) then
				return nx, nz
			end
		end
	end
	return nil
end

-- ---------------------------------------------------------------- the pit

--[[ A street tree in a stone surround. This is the creative half of the fix:
	where a trunk legitimately wants to stand at a kerb, the overlap stops
	being a glitch and becomes the detail that says somebody planted it. ]]
function Placement.pit(prop, surface, radius)
	local pos
	if prop:IsA("Model") then
		pos = select(1, prop:GetBoundingBox()).Position
	else
		pos = prop.Position
	end
	local r = math.max(2.2, math.min(radius or 2.6, 4.2))

	local ring = Instance.new("Part")
	ring.Name = "TreePit"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.34, r * 2, r * 2)
	ring.CFrame = CFrame.new(pos.X, surface.top + 0.06, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Slate
	ring.Color = Color3.fromRGB(122, 116, 106)
	ring.Parent = prop.Parent
	--[[ A tree in a pit still overlaps the paving -- that is the whole point of
		a pit -- so without this marker the audit counts it as unresolved and
		the first live run reported "70 still standing in paving" when those 70
		were the 70 it had just finished planting properly. The resolution is
		recorded on the object so the recount and SVCheck both agree. ]]
	prop:SetAttribute("SVPitted", true)

	local soil = Instance.new("Part")
	soil.Name = "TreePitSoil"
	soil.Shape = Enum.PartType.Cylinder
	soil.Size = Vector3.new(0.3, r * 1.62, r * 1.62)
	soil.CFrame = CFrame.new(pos.X, surface.top + 0.1, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	soil.Anchored = true
	soil.CanCollide = false
	soil.CanQuery = false
	soil.CastShadow = false
	soil.Material = Enum.Material.Ground
	soil.Color = Color3.fromRGB(78, 66, 54)
	soil.Parent = prop.Parent
	return ring
end

-- ---------------------------------------------------------------- the audit

local PROPWORDS = { "tree", "bush", "palm", "oak", "pine", "redwood", "eucalypt", "orchard",
	"grove", "shrub", "plant", "hedge" }

--[[ MATCH WHOLE WORDS, NOT SUBSTRINGS. The first version asked
	string.find(name, "tree"), and "RingSTREEt" contains "tree" -- so every
	ring-road part in the campus was classified as a tree standing in a road,
	and the resolver was dutifully moving and deleting the road. SVCheck
	printed the giveaway: "worst 8.0 studs: RingStreet on RingStreet".

	So the name is split into words first -- on underscores, digits and
	camelCase humps -- and a word has to match outright. LP_Oak_B gives
	{lp, oak, b}; RingStreet gives {ring, street}, and street is not tree. ]]
local function words(name)
	local out = {}
	local spaced = name:gsub("(%l)(%u)", "%1_%2"):gsub("(%a)(%d)", "%1_%2")
	for w in spaced:lower():gmatch("[%a]+") do out[#out + 1] = w end
	return out
end

--[[ The veto is checked across ALL the words before any match is accepted.
	It was inside the loop at first, and "TreePit" yields {tree, pit} in that
	order -- so the pits this module had just planted were classified as
	trees standing in paving, and the next pass would have pitted the pits. ]]
local VETO = { pit = true, soil = true }

function Placement.isGreenery(name)
	local w = words(name)
	for _, x in ipairs(w) do
		if VETO[x] then return false end
	end
	for _, x in ipairs(w) do
		for _, p in ipairs(PROPWORDS) do
			if x == p or x == p .. "s" then return true end
		end
	end
	return false
end

--[[ IS THIS PLANT INDOORS? Cast up from the top of it: if something solid is
	directly overhead within a storey, it is in a room and none of this
	module's business. SVCheck found the need for it -- 272 "violations"
	whose worst case was "pottedPlant on Soffit", a plant beside a wafer's
	ceiling band. A soffit is broad, thin, horizontal and not green, so the
	shape test calls it paving, correctly and uselessly.

	A raycast rather than a list of interior part names, for the same reason
	as everywhere else here: a roof overhead is still a roof overhead after
	somebody adds a new kind of building. ]]
--[[ Two tests, because one does not cover it. The overhead ray catches a
	plant under a wafer soffit; it misses a plant in a penthouse whose glass
	ceiling does not answer raycasts. GROUND_BAND catches those instead:
	nothing in the valley landscape stands twelve studs in the air, so
	anything that does is on a floor, a terrace or a roof, and is decor
	somebody placed deliberately rather than a tree in a road. ]]
local ROOF = 40
local GROUND_BAND = 12

function Placement.elevated(pos, sz)
	return (pos.Y - sz.Y / 2) > GROUND_BAND
end

function Placement.indoors(pos, sz, inst)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { inst }
	params.IgnoreWater = true
	local from = pos + Vector3.new(0, sz.Y / 2 + 0.5, 0)
	return workspace:Raycast(from, Vector3.new(0, ROOF, 0), params) ~= nil
end

--[[ Collect free-standing greenery anywhere under `root`. A model's own parts
	are not counted twice. The word list is the fallback for the four
	generations of trees in this project that predate any tagging. ]]
function Placement.collect(root)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do
		if (d:IsA("Model") or d:IsA("BasePart")) and Placement.isGreenery(d.Name) then
			local p = d.Parent
			if not (p and p ~= root and Placement.isGreenery(p.Name)) then
				local cf, sz
				if d:IsA("Model") then
					local ok, c, e = pcall(function()
						local a, b = d:GetBoundingBox()
						return a, b
					end)
					if ok and e then cf, sz = c, e end
				else
					cf, sz = d.CFrame, d.Size
				end
				if cf and sz and sz.Y > 0.6
					and not Placement.elevated(cf.Position, sz)
					and not Placement.indoors(cf.Position, sz, d) then
					table.insert(out, { inst = d, pos = cf.Position, size = sz,
						base = cf.Position.Y - sz.Y / 2, r = math.max(sz.X, sz.Z) / 2 })
				end
			end
		end
	end
	return out
end

--[[ Every piece of greenery standing in hard paving, with how deep. This is
	what SVCheck gates on: the number has to be zero, and if it is not the
	build says so out loud instead of shipping a tree in a road. ]]
function Placement.violations(roots)
	local bad = {}
	for _, root in ipairs(roots) do
		if root then
			for _, g in ipairs(Placement.collect(root)) do
				local surf, depth = Placement.standingIn(g.pos.X, g.pos.Z, g.base)
				if surf and not g.inst:GetAttribute("SVPitted") then
					table.insert(bad, { g = g, pen = depth, surf = surf })
				else
					-- trunk is clear, but is the canopy hanging over the road?
					local road, over = Placement.overRoad(g.pos.X, g.pos.Z, g.r, g.base)
					if road then
						table.insert(bad, { g = g, pen = over, surf = road, crown = true })
					end
				end
			end
		end
	end
	return bad
end

--[[ Fix them: a pit where the intrusion is small enough for one to be honest,
	a nudge where there is clear ground within reach, removal only as a last
	resort. Returns pitted, moved, removed. ]]
function Placement.resolve(roots)
	local pitted, moved, removed = 0, 0, 0
	for _, v in ipairs(Placement.violations(roots)) do
		local g, surf = v.g, v.surf
		if g.inst.Parent then
			if v.pen <= PIT_MAX and not v.crown then
				Placement.pit(g.inst, surf, g.r * 0.5)
				pitted += 1
			else
				local nx, nz = Placement.nudge(g.pos.X, g.pos.Z, g.r, { y = g.base })
				if nx then
					local d = Vector3.new(nx - g.pos.X, 0, nz - g.pos.Z)
					if g.inst:IsA("Model") then
						g.inst:PivotTo(g.inst:GetPivot() + d)
					else
						g.inst.CFrame = g.inst.CFrame + d
					end
					Placement.claim(nx, nz, g.r)
					moved += 1
				else
					g.inst:Destroy()
					removed += 1
				end
			end
		end
	end
	return pitted, moved, removed
end

--[[ Scan then resolve, over whatever has been built so far. The world build
	is not one event: plots pave their own forecourts and plant their own
	lawns when a player claims them, long after the opening pass. SVCheck
	caught exactly that -- 910 surfaces known at world build, 1,370 present
	once a plot existed, and a tree standing in a ForecourtField that had not
	been poured yet when the sweep ran. So the pass is re-runnable, and the
	surface scan skips what it already holds. ]]
function Placement.pass(root, roots)
	local found = select(1, Placement.scanSurfaces(root))
	local before = #Placement.violations(roots or { root })
	local pitted, moved, gone = Placement.resolve(roots or { root })
	return found, before, pitted, moved, gone, #Placement.violations(roots or { root })
end

function Placement.stats()
	local n = 0
	for _, cell in pairs(claims) do
		n += #cell
	end
	return #surfaces, n
end

return Placement
