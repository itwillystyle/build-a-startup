--[[
	CampusDistricts -- the four gaps between tower plots that are not already
	taken by something with a mechanic.

	Six plots sit on a ring at the odd clock positions (30, 90 ... 330), so the
	six GAPS land on the even ones. Two of those already have real buildings in
	them -- Downtown.DEALER at 180 and Downtown.RES at 240, which carry the car
	dealership and the apartments and are built by Downtown.lua. This fills the
	other four:

	    0    ARRIVAL   the gate, a bus stop, a pavilion to stand under
	    60   PARKING   staff lot, planted islands, chargers
	    120  RETAIL    grocery anchor, three units, awnings, outdoor dining
	    300  EVENT     stage, expo tents, food trucks

	THIS IS SCENERY. Nothing here is saved, nothing has a ProximityPrompt and
	nothing can trap a player: every part is CanCollide false except the
	building shells, which are solid so you cannot walk through a wall. If a
	district later earns a mechanic it gets its own module -- this one only
	makes the campus read as a place instead of six towers and a lawn.

	BUDGET. Measured against the <1000 draw-call phone budget the valley
	already spends ~250-450 of: this adds about 420 parts, nearly all of them
	small and shadowless, and no district is visible from more than two others.
]]

local CampusDistricts = {}

local PAVE = Color3.fromRGB(222, 215, 200)
local PAVE_D = Color3.fromRGB(196, 188, 172)
local PAVE_W = Color3.fromRGB(236, 231, 220)
local CONCRETE = Color3.fromRGB(207, 198, 182)
local LAWN = Color3.fromRGB(122, 170, 80)
local ASPHALT = Color3.fromRGB(64, 64, 68)
local GLASS = Color3.fromRGB(118, 158, 176)
local PAPER = Color3.fromRGB(243, 239, 230)
local OAK = Color3.fromRGB(192, 138, 85)
local GOLD = Color3.fromRGB(224, 182, 90)
local ORANGE = Color3.fromRGB(232, 138, 54)
local RED = Color3.fromRGB(198, 72, 62)
local TEAL = Color3.fromRGB(70, 160, 150)
local BRICK = Color3.fromRGB(170, 104, 78)
local TRUNK = Color3.fromRGB(150, 96, 62)
local LEAF = Color3.fromRGB(78, 168, 92)

local CAR_COLOURS = {
	Color3.fromRGB(206, 72, 64), Color3.fromRGB(236, 236, 240), Color3.fromRGB(44, 58, 86),
	Color3.fromRGB(70, 72, 78), Color3.fromRGB(222, 176, 72), Color3.fromRGB(78, 136, 108),
}

local rng = Random.new(90210)

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

--[[ Everything is placed in the gap's own frame: `at(a, r, t)` is radius `r`
	out along angle `a`, then `t` studs along the tangent. Writing a district in
	(r, t) instead of (x, z) means it can be moved to another gap by changing
	one angle, the same way the plots move. ]]
local function at(a, r, t)
	local ca, sa = math.cos(a), math.sin(a)
	return Vector3.new(ca * r - sa * (t or 0), 0, sa * r + ca * (t or 0))
end

-- a box standing on the ground at (r, t), turned to face the park
local function slab(parent, name, a, r, t, w, h, d, colour, opts)
	opts = opts or {}
	local p = at(a, r, t)
	return part(parent, {
		Name = name,
		Size = Vector3.new(w, h, d),
		-- -a + pi/2 turns local +Z to point at the centre, the same convention
		-- the plots and Downtown use
		CFrame = CFrame.new(p.X, (opts.y or 0) + h / 2, p.Z) * CFrame.Angles(0, -a + math.pi / 2, 0),
		Color = colour,
		Material = opts.material or Enum.Material.SmoothPlastic,
		CanCollide = opts.solid or false,
		CanQuery = opts.solid or false,
		Transparency = opts.transparency or 0,
	})
end

local function pad(parent, a, r, t, w, d, colour, y)
	return slab(parent, "Pad", a, r, t, w, 1.0, d, colour, { y = (y or 0) - 0.5 })
end

local function tree(parent, a, r, t, s)
	s = s or 1
	local p = at(a, r, t)
	part(parent, {
		Name = "DistTrunk", Size = Vector3.new(1.7 * s, 10 * s, 1.7 * s),
		CFrame = CFrame.new(p.X, 5 * s, p.Z), Color = TRUNK, Material = Enum.Material.Wood,
	})
	part(parent, {
		Name = "DistLeaf", Size = Vector3.new(14 * s, 12 * s, 14 * s),
		CFrame = CFrame.new(p.X, 15 * s, p.Z), Color = LEAF, Material = Enum.Material.Grass,
		Shape = Enum.PartType.Ball,
	})
end

local function car(parent, a, r, t, colour)
	slab(parent, "DistCar", a, r, t, 5, 3.2, 11, colour or CAR_COLOURS[rng:NextInteger(1, #CAR_COLOURS)], { y = 0.6 })
	slab(parent, "DistCarGlass", a, r, t, 4.4, 1.8, 5.2, GLASS, { y = 3.8 })
end

local function lamp(parent, a, r, t)
	local p = at(a, r, t)
	part(parent, { Name = "DistLampPost", Size = Vector3.new(0.7, 19, 0.7), CFrame = CFrame.new(p.X, 9.5, p.Z), Color = PAPER })
	part(parent, {
		Name = "DistLampHead", Size = Vector3.new(2.2, 1.1, 2.2), CFrame = CFrame.new(p.X, 19.6, p.Z),
		Color = GOLD, Material = Enum.Material.Neon,
	})
end

local function parasol(parent, a, r, t, colour)
	local p = at(a, r, t)
	part(parent, { Name = "DistParasolPost", Size = Vector3.new(0.5, 8.5, 0.5), CFrame = CFrame.new(p.X, 4.2, p.Z), Color = PAPER })
	part(parent, { Name = "DistParasol", Size = Vector3.new(7, 0.9, 7), CFrame = CFrame.new(p.X, 9.0, p.Z), Color = colour })
	part(parent, { Name = "DistTable", Size = Vector3.new(4.4, 0.4, 4.4), CFrame = CFrame.new(p.X, 2.9, p.Z), Color = PAPER })
end

-- ------------------------------------------------------------------ gaps
local function arrival(f, a, R)
	pad(f, a, R - 20, 0, 150, 130, PAVE)
	-- the gate, on the outer road
	for _, s in ipairs({ -1, 1 }) do
		slab(f, "GatePost", a, R + 140, s * 34, 8, 36, 8, PAPER, { solid = true })
	end
	slab(f, "GateBeam", a, R + 140, 0, 76, 7, 8, GOLD, { y = 36, material = Enum.Material.Neon })
	-- a pavilion: a roof on columns is the cheapest thing that makes a place
	slab(f, "PavRoof", a, R - 14, 0, 66, 3.2, 32, PAPER, { y = 22 })
	for _, u in ipairs({ -28, -9, 9, 28 }) do
		for _, v in ipairs({ -13, 13 }) do
			slab(f, "PavCol", a, R - 14 + v, u, 1.4, 22, 1.4, PAPER, { solid = true })
		end
	end
	slab(f, "BusStop", a, R + 42, -46, 10, 4, 28, TEAL, { y = 0.6 })
	slab(f, "Bus", a, R + 50, 14, 9, 10, 30, TEAL, { y = 0.6 })
	slab(f, "BusGlass", a, R + 50, 14, 9.4, 3.2, 26, GLASS, { y = 7.2 })
	for _, t in ipairs({ -52, 52 }) do
		lamp(f, a, R + 10, t)
	end
	for _, t in ipairs({ -66, 66 }) do
		tree(f, a, R - 56, t, 1.1)
	end
end

local function parking(f, a, R)
	pad(f, a, R - 14, 0, 150, 150, ASPHALT)
	for row, rr in ipairs({ R - 56, R - 12, R + 32 }) do
		for c = -4, 4 do
			if rng:NextNumber() < 0.8 then
				car(f, a, rr, c * 15)
			end
		end
		if row < 3 then
			slab(f, "LotIsland", a, rr + 18, 0, 128, 2.4, 6, CONCRETE, { y = 0.5 })
			slab(f, "LotIslandGreen", a, rr + 18, 0, 124, 1.0, 4, LAWN, { y = 2.9, material = Enum.Material.Grass })
		end
	end
	for _, t in ipairs({ -58, -28, 28, 58 }) do
		slab(f, "Charger", a, R - 74, t, 1.1, 8.5, 1.1, TEAL, { y = 0.5 })
	end
	for _, t in ipairs({ -66, 66 }) do
		lamp(f, a, R + 46, t)
	end
end

local function retail(f, a, R)
	pad(f, a, R - 44, 0, 170, 120, PAVE_W)
	-- grocery anchor, then three smaller units beside it
	slab(f, "Grocery", a, R + 42, -48, 56, 26, 100, PAPER, { solid = true })
	slab(f, "GroceryBand", a, R + 42, -48, 60, 5, 104, ORANGE, { y = 24 })
	local cols = { BRICK, PAPER, TEAL }
	for i = 0, 2 do
		local t = 34 + i * 46
		slab(f, "ShopUnit", a, R + 38, t, 44, 20, 42, cols[i + 1], { solid = true })
		slab(f, "ShopRoof", a, R + 38, t, 48, 3, 46, PAVE_D, { y = 20 })
		slab(f, "ShopAwning", a, R + 14, t, 12, 1.8, 38, ORANGE, { y = 13 })
	end
	-- outdoor dining on the plaza
	for i = 0, 8 do
		parasol(f, a, R - 30 - (i % 3) * 16, -64 + i * 16, ({ ORANGE, RED, TEAL, PAPER })[(i % 4) + 1])
	end
	for _, t in ipairs({ -80, -38, 38, 80 }) do
		tree(f, a, R - 82, t, 1.1)
		lamp(f, a, R - 58, t)
	end
end

local function eventLawn(f, a, R)
	pad(f, a, R - 20, 0, 150, 150, LAWN, 0)
	slab(f, "StageDeck", a, R + 42, 0, 30, 5, 70, OAK, { y = 0.6, solid = true })
	slab(f, "StageBack", a, R + 56, 0, 3, 26, 72, PAVE_D, { y = 5 })
	slab(f, "StageRoof", a, R + 42, 0, 34, 3, 76, PAPER, { y = 27 })
	for _, t in ipairs({ -34, 34 }) do
		slab(f, "StageCol", a, R + 42, t, 1.5, 27, 1.5, PAPER)
	end
	local tentCols = { TEAL, ORANGE, PAPER, RED, GOLD }
	for i = 0, 4 do
		local t = -60 + i * 30
		slab(f, "TentRoof", a, R - 18, t, 24, 2.0, 24, tentCols[i + 1], { y = 12 })
		for _, u in ipairs({ -10, 10 }) do
			for _, v in ipairs({ -10, 10 }) do
				slab(f, "TentLeg", a, R - 18 + v, t + u, 0.7, 12, 0.7, PAPER)
			end
		end
	end
	for i, col in ipairs({ RED, TEAL, ORANGE }) do
		slab(f, "FoodTruck", a, R - 72, -38 + (i - 1) * 38, 9, 11, 21, col, { y = 0.6, solid = true })
	end
	for _, t in ipairs({ -84, 84 }) do
		tree(f, a, R - 78, t, 1.1)
		tree(f, a, R + 10, t, 1.1)
	end
end

--[[ Build the four scenery districts into `parent`. Idempotent. `R` is the
	district band radius -- the same CampusHub.R_DIST the dealership and the
	apartments were moved to, so all six gaps line up. ]]
function CampusDistricts.build(parent, R)
	local old = parent:FindFirstChild("CampusDistricts")
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = "CampusDistricts"
	f.Parent = parent

	arrival(f, math.rad(0), R)
	parking(f, math.rad(60), R)
	retail(f, math.rad(120), R)
	-- 180 is the car dealership and 240 the apartments: both are real buildings
	-- with mechanics, built by Downtown.lua around Downtown.DEALER / .RES
	eventLawn(f, math.rad(300), R)

	return f
end

return CampusDistricts
