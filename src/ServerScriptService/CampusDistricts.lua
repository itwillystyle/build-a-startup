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

local CollectionService = game:GetService("CollectionService")

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
		CFrame = CFrame.new(p.X, (opts.y or 0) + h / 2, p.Z) * CFrame.Angles(0, -a + math.pi / 2 + (opts.yaw or 0), 0),
		Color = colour,
		Material = opts.material or Enum.Material.SmoothPlastic,
		Shape = opts.shape,
		CanCollide = opts.solid or false,
		CanQuery = opts.solid or opts.query or false,
		Transparency = opts.transparency or 0,
	})
end

--[[ A district's ground plane, with a kerb round it.

	Pass 1 learned this on the park: a surface with no edge reads as a texture
	change rather than something you stand on. Every district pad was a bare
	slab dropped on the valley floor, so the retail plaza and the parking lot
	had no edges at all. The kerb sits 1.2 studs proud and 3 wider than the pad
	on each side, with a grass verge outside it. ]]
local Ground = require(script.Parent:WaitForChild("Ground"))   -- v4.9 footprint registry

local function pad(parent, a, r, t, w, d, colour, y)
	local base = (y or 0)
	--[[ v4.9: claim this ground. The valley plants its trees long before this
		runs, so without the claim they stay standing in the middle of the pad
		(measured 4 Oct: 18 of them). Reserving the VERGE covers the kerb and
		the pad inside it too, since it is the outermost piece. ]]
	local verge = slab(parent, "PadVerge", a, r, t, w + 22, 0.8, d + 22, LAWN, { y = base - 0.4, material = Enum.Material.Grass })
	Ground.reservePart(verge, "PadVerge")
	slab(parent, "PadKerb", a, r, t, w + 6, 1.4, d + 6, CONCRETE, { y = base - 0.4 })
	-- queryable: a pad is a floor, and anything asking what it is standing on
	-- (contact shadows, idle spots, candidates) has to be able to find it
	return slab(parent, "Pad", a, r, t, w, 1.0, d, colour, { y = base - 0.5 + 0.55, query = true })
end

local FlatLook = require(script.Parent:WaitForChild("FlatLook"))   -- v4.7 contact shadows

local function tree(parent, a, r, t, s)
	s = s or 1
	local p = at(a, r, t)
	FlatLook.contact(parent, p.X, p.Z, 6.6 * s)
	-- v4.7.1: a Model, so the outline is one line round the tree instead of two
	-- (a Highlight draws a silhouette, and two loose parts are two silhouettes)
	local m = Instance.new("Model")
	m.Name = "DistTree"
	m.Parent = parent
	local trunk = part(m, {
		Name = "DistTrunk", Size = Vector3.new(1.7 * s, 10 * s, 1.7 * s),
		CFrame = CFrame.new(p.X, 5 * s, p.Z), Color = TRUNK, Material = Enum.Material.Wood,
	})
	part(m, {
		Name = "DistLeaf", Size = Vector3.new(14 * s, 12 * s, 14 * s),
		CFrame = CFrame.new(p.X, 15 * s, p.Z), Color = LEAF, Material = Enum.Material.Grass,
		Shape = Enum.PartType.Ball,
	})
	m.PrimaryPart = trunk
	CollectionService:AddTag(m, "SVOutline")
end

--[[ A PARKED CAR. It was two boxes -- a 5x3.2x11 slab with a smaller glass
	slab on top -- repeated 27 times across the staff lot, which from the ring
	road read as a pallet yard. The kit the ring traffic already uses has real
	cars in it, so park those; the two boxes stay as the fallback so a missing
	kit can never empty the lot. ]]
local KENNEY = game:GetService("ReplicatedStorage"):FindFirstChild("KenneyKit")
local KENNEY_CARS = { "sedan", "sedan-sports", "hatchback-sports", "suv", "taxi", "van", "delivery", "truck" }

local function car(parent, a, r, t, colour)
	local tpl = KENNEY and KENNEY:FindFirstChild(KENNEY_CARS[rng:NextInteger(1, #KENNEY_CARS)])
	if tpl then
		local m = tpl:Clone()
		m.Name = "DistCar"
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
		local pos = at(a, r, t)
		-- the kit's cars face -Z; a quarter turn from the district frame parks
		-- them nose-in to the kerb instead of across the bay
		m:PivotTo(CFrame.new(pos.X, 1.6, pos.Z) * CFrame.Angles(0, -a + math.pi / 2, 0))
		m.Parent = parent
		CollectionService:AddTag(m, "SVOutline")                      -- v4.7.1
		return m
	end
	slab(parent, "DistCar", a, r, t, 5, 3.2, 11, colour or CAR_COLOURS[rng:NextInteger(1, #CAR_COLOURS)], { y = 0.6 })
	slab(parent, "DistCarGlass", a, r, t, 4.4, 1.8, 5.2, GLASS, { y = 3.8 })
end

local function lamp(parent, a, r, t)
	local p0 = at(a, r, t)
	if FlatLook.propMesh(parent, "SVP_Lamp", CFrame.new(p0.X, 0, p0.Z), 20.2) then return end
	parent = FlatLook.prop(parent, "DistLamp")
	local p = at(a, r, t)
	part(parent, { Name = "DistLampPost", Size = Vector3.new(0.7, 19, 0.7), CFrame = CFrame.new(p.X, 9.5, p.Z), Color = PAPER })
	local head = part(parent, {
		Name = "DistLampHead", Size = Vector3.new(2.2, 1.1, 2.2), CFrame = CFrame.new(p.X, 19.6, p.Z),
		Color = GOLD, Material = Enum.Material.Neon,
	})
	game:GetService("CollectionService"):AddTag(head, "SVLamp")
end

local function parasol(parent, a, r, t, colour)
	local p0 = at(a, r, t)
	if FlatLook.propMesh(parent, "SVP_Parasol", CFrame.new(p0.X, 1.05, p0.Z), 9.0) then return end
	parent = FlatLook.prop(parent, "Parasol")
	local p = at(a, r, t)
	part(parent, { Name = "DistParasolPost", Size = Vector3.new(0.5, 8.5, 0.5), CFrame = CFrame.new(p.X, 4.2, p.Z), Color = PAPER })
	part(parent, { Name = "DistParasol", Size = Vector3.new(7, 0.9, 7), CFrame = CFrame.new(p.X, 9.0, p.Z), Color = colour })
	part(parent, { Name = "DistTable", Size = Vector3.new(4.4, 0.4, 4.4), CFrame = CFrame.new(p.X, 2.9, p.Z), Color = PAPER })
end

--[[ A SIGN. The districts were built out of blank slabs -- a glowing yellow
	beam over the gate, a teal box for a bus -- and a blank board is the one
	thing the environment doctrine rules out: it takes the loudest surface in
	the frame and says nothing with it. `board` puts lines of text on the faces
	that look out of the district, so every big flat thing carries its name. ]]
local MONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold)

local function board(host, lines, opts)
	opts = opts or {}
	for _, face in ipairs(opts.faces or { Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = opts.ppu or 28
		sg.LightInfluence = 0
		sg.MaxDistance = opts.maxDistance or 420
		sg.Parent = host
		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Vertical
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.VerticalAlignment = Enum.VerticalAlignment.Center
		list.Padding = UDim.new(0, opts.padding or 2)
		list.Parent = sg
		for i, line in ipairs(lines) do
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Size = UDim2.new(0.92, 0, (opts.rowScale or 0.8) / #lines, 0)
			t.LayoutOrder = i
			t.TextScaled = true
			t.FontFace = MONT
			t.TextColor3 = (i == 1 and opts.firstColor) or opts.color or Color3.fromRGB(244, 243, 239)
			t.Text = line
			t.Parent = sg
		end
	end
	return host
end

--[[ A PLACE FOR SOMEBODY TO BE (pass 7). Every person in this game walks a
	lane, which makes the whole campus a crowd of commuters passing through and
	nobody who is anywhere. These are standing and sitting SPOTS: tiny invisible
	markers tagged SVIdle, each facing what the person should be looking at.
	LifeClient puts a figure on every one. Marking them here rather than listing
	coordinates in the client means a spot moves when its bench moves. ]]
local SPOT_RAY = RaycastParams.new()
SPOT_RAY.RespectCanCollide = false

local function spot(parent, a, r, t, seated, turn, lift)
	local p = at(a, r, t)
	-- The marker is the ground they stand on, or the SEAT they sit on: `lift`
	-- is the seat height above the paving. Measured, not assumed -- the pads
	-- themselves sit 1.05 above the valley floor.
	local hit = workspace:Raycast(Vector3.new(p.X, 60, p.Z), Vector3.new(0, -120, 0), SPOT_RAY)
	local y = (hit and hit.Position.Y or 0) + (lift or 0)
	local m = part(parent, {
		Name = "IdleSpot",
		Size = Vector3.new(0.4, 0.4, 0.4),
		CFrame = CFrame.new(p.X, y, p.Z) * CFrame.Angles(0, -a + math.pi / 2 + (turn or 0), 0),
		Transparency = 1,
	})
	m:SetAttribute("Seated", seated and true or false)
	CollectionService:AddTag(m, "SVIdle")
	return m
end

-- ------------------------------------------------------------------ gaps
--[[ ARRIVAL (pass 5). What a player sees first if they drive back from
	downtown. Before this pass it was a 150x130 white apron, a flat roof on
	eight bare posts, a glowing blank beam over the gate and a teal box called
	"Bus". Nothing said where you were or where anything was.

	So: the gate carries the campus name, the pavilion carries a DIRECTORY (the
	one thing a new player actually needs -- which way the shops, the cars and
	the flats are), the apron is broken up by a drop-off island and planting,
	and the bus is a bus. ]]
local function arrival(f, a, R)
	pad(f, a, R - 20, 0, 150, 130, PAVE)
	-- paving bands, so 150 studs of apron is not one flat tone
	for _, t in ipairs({ -46, 46 }) do
		slab(f, "PadBand", a, R - 20, t, 3, 0.1, 126, PAVE_D, { y = 1.0 })
	end
	slab(f, "PadBand", a, R - 20, 0, 144, 0.1, 3, PAVE_D, { y = 1.0 })

	-- the gate, on the outer road: a named lintel, not a glowing bar
	for _, sd in ipairs({ -1, 1 }) do
		slab(f, "GatePost", a, R + 140, sd * 34, 8, 36, 8, PAPER, { solid = true })
	end
	local beam = slab(f, "GateBeam", a, R + 140, 0, 76, 9, 5, Color3.fromRGB(44, 48, 56), { y = 33 })
	board(beam, { "SILICON VALLEY CAMPUS" }, { ppu = 34, maxDistance = 700, rowScale = 0.56 })
	slab(f, "GateBand", a, R + 140, 0, 76, 1.1, 5.4, GOLD, { y = 32.2 })

	-- the pavilion: roof, fascia, and a directory you can read from both sides
	slab(f, "PavRoof", a, R - 14, 0, 66, 3.2, 32, PAPER, { y = 22 })
	local fascia = slab(f, "PavFascia", a, R - 14, 0, 66, 2.6, 1.0, Color3.fromRGB(44, 48, 56), { y = 19.2 })
	board(fascia, { "ARRIVALS" }, { ppu = 30, maxDistance = 360, rowScale = 0.66 })
	for _, u in ipairs({ -28, -9, 9, 28 }) do
		for _, v in ipairs({ -13, 13 }) do
			slab(f, "PavCol", a, R - 14 + v, u, 1.4, 22, 1.4, PAPER, { solid = true })
		end
	end
	local dir = slab(f, "Directory", a, R - 14, 0, 30, 11, 1.2, Color3.fromRGB(38, 42, 50), { y = 3.4 })
	board(dir, {
		"THE CAMPUS",
		"SIX COMPANIES  -  ON THE RING",
		"SHOPS  >>      MOTORS  >>",
		"PARKING  <<      FLATS  <<",
		"EVENT LAWN  -  SOUTH",
	}, { ppu = 30, maxDistance = 300, firstColor = GOLD, rowScale = 0.92 })
	for _, t in ipairs({ -13, 13 }) do
		slab(f, "DirectoryLeg", a, R - 14, t, 1.2, 3.4, 1.6, Color3.fromRGB(70, 76, 86), { y = 0 })
	end
	for _, t in ipairs({ -22, 22 }) do
		slab(f, "PavBench", a, R - 22, t, 12, 1.2, 2.2, OAK, { y = 2.0, material = Enum.Material.Wood })
		slab(f, "PavBenchLeg", a, R - 22, t, 12.4, 2.0, 0.8, CONCRETE, { y = 0 })
	end

	-- a drop-off island between the pavilion and the road, with planting: the
	-- apron needs something to drive round, or it is a car park
	slab(f, "DropIsland", a, R + 24, 0, 56, 1.4, 14, CONCRETE, { y = 0 })
	slab(f, "DropSoil", a, R + 24, 0, 52, 0.5, 10, LAWN, { y = 1.4, material = Enum.Material.Grass })
	for _, t in ipairs({ -18, 0, 18 }) do
		tree(f, a, R + 24, t, 0.62)
	end
	-- four painted taxi bays along the kerb
	for i = -2, 1 do
		slab(f, "BayLine", a, R + 4, i * 13 + 6.5, 0.6, 0.1, 22, PAVE_W, { y = 1.0 })
	end
	slab(f, "BayLine", a, R - 7, 0, 52, 0.1, 0.6, PAVE_W, { y = 1.0 })

	--[[ THE BUS. It was one teal box with a glass stripe, 30 studs long and 10
		tall. A bus is: a body under a roof, a windscreen, a door, wheels, and a
		destination you can read. It stands on the kerb with its length along
		the road -- in this frame local X is the tangent, so that is its width
		argument. ]]
	local BUS_T = -12          -- pulled up at the shelter (SH_T -44), not parked across the apron
	slab(f, "BusBody", a, R + 44, BUS_T, 34, 7.0, 9, TEAL, { y = 1.9 })
	slab(f, "BusRoof", a, R + 44, BUS_T, 34.6, 0.9, 9.6, Color3.fromRGB(232, 232, 228), { y = 8.9 })
	slab(f, "BusBand", a, R + 44, BUS_T, 34.2, 0.9, 9.2, Color3.fromRGB(232, 232, 228), { y = 1.9 })
	for _, sd in ipairs({ -1, 1 }) do
		slab(f, "BusWindow", a, R + 44 + sd * 4.45, BUS_T, 29, 4.2, 0.35, GLASS, { y = 4.3, transparency = 0.32 })
	end
	slab(f, "BusScreen", a, R + 44, BUS_T + 17.15, 0.35, 4.2, 8.2, GLASS, { y = 4.3, transparency = 0.28 })
	local dest = slab(f, "BusDest", a, R + 44, BUS_T + 17.35, 0.4, 2.0, 7.0, Color3.fromRGB(32, 36, 42), { y = 6.6 })
	board(dest, { "CAMPUS LOOP" }, { ppu = 36, maxDistance = 200, rowScale = 0.7,
		faces = { Enum.NormalId.Right, Enum.NormalId.Left } })
	slab(f, "BusDoor", a, R + 39.55, BUS_T - 11, 7, 6.0, 0.35, Color3.fromRGB(44, 100, 98), { y = 1.9 })
	-- a Cylinder's axis is always its local X, so the wheels need a quarter
	-- turn: without it the axle runs along the bus instead of across it
	for _, u in ipairs({ -13, 2, 13 }) do
		slab(f, "BusWheel", a, R + 44, BUS_T + u, 9.6, 3.6, 3.6, Color3.fromRGB(40, 42, 46),
			{ y = 0.0, shape = Enum.PartType.Cylinder, yaw = math.pi / 2 })
	end

	-- the stop itself: a shelter, not a slab
	local SH_T = -44
	slab(f, "StopPad", a, R + 34, SH_T, 26, 1.1, 12, PAVE_W, { y = 0 })
	slab(f, "StopRoof", a, R + 34, SH_T, 22, 0.7, 10, Color3.fromRGB(44, 48, 56), { y = 10.4 })
	for _, u in ipairs({ -10, 10 }) do
		slab(f, "StopPost", a, R + 38.6, SH_T + u, 0.5, 9.4, 0.5, Color3.fromRGB(150, 155, 162), { y = 1.1 })
		slab(f, "StopPost", a, R + 29.4, SH_T + u, 0.5, 9.4, 0.5, Color3.fromRGB(150, 155, 162), { y = 1.1 })
	end
	slab(f, "StopGlass", a, R + 29.4, SH_T, 21, 7.6, 0.3, GLASS, { y = 1.1, transparency = 0.45 })
	slab(f, "StopBench", a, R + 31.4, SH_T, 17, 0.5, 2.0, OAK, { y = 3.4, material = Enum.Material.Wood })
	local flag = slab(f, "StopSign", a, R + 40.5, SH_T + 13, 0.4, 3.0, 5.4, Color3.fromRGB(44, 48, 56), { y = 9.0 })
	board(flag, { "BUS" }, { ppu = 36, maxDistance = 180, rowScale = 0.72,
		faces = { Enum.NormalId.Right, Enum.NormalId.Left } })
	slab(f, "StopPole", a, R + 40.5, SH_T + 13, 0.4, 9.0, 0.4, Color3.fromRGB(150, 155, 162), { y = 0 })

	for _, t in ipairs({ -52, 52 }) do
		lamp(f, a, R + 10, t)
	end
	for _, t in ipairs({ -66, 66 }) do
		tree(f, a, R - 56, t, 1.1)
	end
	-- people: waiting on the bench, standing at the bus door, reading the
	-- directory, sitting under the pavilion
	spot(f, a, R + 31.4, SH_T - 5, true, math.pi, 2.8)      -- on the shelter bench
	spot(f, a, R + 31.4, SH_T + 4, true, math.pi, 2.8)
	spot(f, a, R + 36, SH_T + 14, false, math.pi / 2)
	spot(f, a, R + 35, BUS_T - 13, false, math.pi)
	spot(f, a, R - 9, 0, false, math.pi)
	spot(f, a, R - 22, -22, true, 0, 2.15)                   -- on the pavilion benches
	spot(f, a, R - 22, 24, true, 0, 2.15)
end

--[[ PARKING (pass 5). It was 150x150 studs of flat asphalt with 27 box cars
	and four teal posts on it. A car park reads as a car park because of the
	PAINT -- bay lines, arrows, a hatched island -- and because something
	controls the way in. ]]
local function parking(f, a, R)
	pad(f, a, R - 14, 0, 150, 150, ASPHALT)
	for row, rr in ipairs({ R - 56, R - 12, R + 32 }) do
		-- the bay lines first, so a missing car still leaves a marked bay
		for c = -4, 5 do
			slab(f, "BayLine", a, rr, c * 15 - 7.5, 0.6, 0.12, 22, PAVE_W, { y = 1.0 })
		end
		slab(f, "BayLine", a, rr - 11, 0, 150, 0.12, 0.6, PAVE_W, { y = 1.0 })
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
	-- the way in: a hut, a barrier and a sign, at the road end of the lot
	slab(f, "GateHut", a, R + 62, -22, 10, 11, 10, PAPER, { solid = true })
	slab(f, "GateHutRoof", a, R + 62, -22, 12, 1.2, 12, Color3.fromRGB(44, 48, 56), { y = 11 })
	slab(f, "GateHutGlass", a, R + 57.2, -22, 7.6, 4.4, 0.4, GLASS, { y = 4.6, transparency = 0.35 })
	slab(f, "BarrierPost", a, R + 62, -14, 1.1, 6, 1.1, Color3.fromRGB(44, 48, 56), { y = 1.0 })
	slab(f, "BarrierArm", a, R + 62, -3, 22, 0.8, 0.8, Color3.fromRGB(214, 70, 60), { y = 6.0 })
	local sign = slab(f, "LotSign", a, R + 64, 20, 0.5, 6.5, 22, Color3.fromRGB(38, 42, 50), { y = 7.0 })
	board(sign, { "STAFF PARKING", "PERMIT HOLDERS ONLY" },
		{ ppu = 26, maxDistance = 300, firstColor = GOLD, rowScale = 0.8,
		  faces = { Enum.NormalId.Right, Enum.NormalId.Left } })
	for _, t in ipairs({ 11, 29 }) do
		slab(f, "LotSignLeg", a, R + 64, t, 0.5, 7.0, 0.5, Color3.fromRGB(150, 155, 162), { y = 0 })
	end
	-- chargers: a post is not a charger without a head and a cable
	for _, t in ipairs({ -58, -28, 28, 58 }) do
		slab(f, "Charger", a, R - 74, t, 1.1, 7.0, 1.1, TEAL, { y = 0.5 })
		slab(f, "ChargerHead", a, R - 74, t, 2.6, 2.4, 1.8, Color3.fromRGB(38, 42, 50), { y = 7.5 })
		slab(f, "ChargerLight", a, R - 75.0, t, 1.2, 0.5, 0.3, Color3.fromRGB(120, 230, 150),
			{ y = 8.6, material = Enum.Material.Neon })
		slab(f, "ChargerCable", a, R - 73.2, t + 1.0, 0.3, 4.0, 0.3, Color3.fromRGB(32, 34, 38), { y = 3.4 })
	end
	for _, t in ipairs({ -66, 66 }) do
		lamp(f, a, R + 46, t)
	end
	spot(f, a, R + 56, -22, false, math.pi / 2)        -- the attendant, by the hut
	spot(f, a, R - 70, -58, false, math.pi)            -- somebody charging a car
	spot(f, a, R - 20, 44, false, 0)
end

--[[ RETAIL (pass 5). Four featureless boxes -- a 56x26x100 white slab called
	"Grocery" and three coloured cubes -- with roofs and awnings and no window,
	no door and no name between them. A shop is a GLASS FRONT with a name over
	it: that is the whole of what makes a box read as a shop. ]]
local SHOPS = {
	{ name = "VALLEY BAKERY", colour = BRICK },
	{ name = "FOUNDER COFFEE", colour = PAPER },
	{ name = "PRINT + COPY", colour = TEAL },
}

local function retail(f, a, R)
	pad(f, a, R - 44, 0, 170, 120, PAVE_W)
	-- paving bands: 170x120 of one pale tone was the emptiest surface on the map
	for _, t in ipairs({ -54, 0, 54 }) do
		slab(f, "PlazaJoint", a, R - 44, t, 2.4, 0.08, 116, PAVE_D, { y = 1.0 })
	end
	for _, rr in ipairs({ R - 84, R - 44, R - 4 }) do
		slab(f, "PlazaJoint", a, rr, 0, 166, 0.08, 2.4, PAVE_D, { y = 1.0 })
	end

	-- the grocery anchor: glass front, entrance canopy, name band, trolleys
	slab(f, "Grocery", a, R + 42, -48, 56, 26, 100, PAPER, { solid = true })
	slab(f, "GroceryBand", a, R + 42, -48, 60, 5, 104, ORANGE, { y = 24 })
	local gName = slab(f, "GroceryName", a, R - 8.6, -48, 54, 7.0, 0.5, Color3.fromRGB(38, 42, 50), { y = 15.5 })
	board(gName, { "VALLEY MARKET" }, { ppu = 26, maxDistance = 420, rowScale = 0.62 })
	slab(f, "GroceryGlass", a, R - 8.2, -48, 50, 13, 0.5, GLASS, { y = 1.4, transparency = 0.34 })
	slab(f, "GroceryDoor", a, R - 8.5, -48, 14, 9.5, 0.6, Color3.fromRGB(70, 78, 90), { y = 1.0 })
	slab(f, "GroceryCanopy", a, R - 14, -48, 40, 1.2, 14, Color3.fromRGB(44, 48, 56), { y = 15.0 })
	for _, t in ipairs({ -16, 16 }) do
		slab(f, "CanopyPost", a, R - 20, -48 + t, 0.6, 15.0, 0.6, Color3.fromRGB(150, 155, 162), { y = 1.0 })
	end
	for i = 0, 3 do
		slab(f, "Trolley", a, R - 16, -14 + i * 3.2, 2.6, 3.0, 4.2, Color3.fromRGB(176, 182, 190), { y = 1.0 })
	end

	-- three units: each gets glazing, a door, a fascia and a name
	for i, shop in ipairs(SHOPS) do
		local t = 34 + (i - 1) * 46
		slab(f, "ShopUnit", a, R + 38, t, 44, 20, 42, shop.colour, { solid = true })
		-- a roof is ground too: 14 valley trees were measured standing on these
		Ground.reservePart(slab(f, "ShopRoof", a, R + 38, t, 48, 3, 46, PAVE_D, { y = 20 }), "ShopRoof")
		slab(f, "ShopGlass", a, R + 17.2, t, 34, 11, 0.5, GLASS, { y = 1.4, transparency = 0.34 })
		slab(f, "ShopDoor", a, R + 16.9, t - 12, 7, 9.0, 0.6, Color3.fromRGB(70, 78, 90), { y = 1.0 })
		local fascia = slab(f, "ShopFascia", a, R + 16.6, t, 40, 4.6, 0.5, Color3.fromRGB(38, 42, 50), { y = 13.4 })
		board(fascia, { shop.name }, { ppu = 28, maxDistance = 380, rowScale = 0.66 })
		slab(f, "ShopAwning", a, R + 12, t, 40, 1.4, 11, ORANGE, { y = 12.6 })
		slab(f, "ShopSill", a, R + 16.4, t, 40, 0.8, 1.6, CONCRETE, { y = 0.6 })
	end

	-- outdoor dining on the plaza, with chairs: a table under a parasol and
	-- nothing to sit on is set dressing, not a cafe
	for i = 0, 8 do
		local rr, tt = R - 30 - (i % 3) * 16, -64 + i * 16
		parasol(f, a, rr, tt, ({ ORANGE, RED, TEAL, PAPER })[(i % 4) + 1])
		for _, d in ipairs({ { -3.4, 0 }, { 3.4, 0 }, { 0, -3.4 }, { 0, 3.4 } }) do
			slab(f, "DistChair", a, rr + d[1], tt + d[2], 1.7, 1.5, 1.7, PAVE_D, { y = 1.0 })
			slab(f, "DistChairBack", a, rr + d[1] * 1.28, tt + d[2] * 1.28, 1.7, 2.0, 0.35, PAVE_D, { y = 2.5 })
		end
	end
	for _, t in ipairs({ -80, -38, 38, 80 }) do
		tree(f, a, R - 82, t, 1.1)
		lamp(f, a, R - 58, t)
	end
	-- at the tables, and at the market door
	for _, q in ipairs({ { R - 34, -64, math.pi / 2 }, { R - 26, -60, -math.pi / 2 },
		{ R - 50, -32, math.pi / 2 }, { R - 42, -28, -math.pi / 2 },
		{ R - 34, 0, math.pi / 2 }, { R - 26, 4, -math.pi / 2 } }) do
		spot(f, a, q[1], q[2], true, q[3], 1.45)                -- on a cafe chair
	end
	spot(f, a, R - 22, -48, false, 0)
	spot(f, a, R + 8, 34, false, 0)
end

--[[ EVENT LAWN (pass 5). A stage with a blank back wall, five flat coloured
	squares on legs called tents, and three boxes called food trucks. The lawn
	is where the campus says what it is FOR, so the backdrop carries the event,
	the tents get a pitch and a table under them, and a food truck gets a hatch
	you could be served from. ]]
local function eventLawn(f, a, R)
	pad(f, a, R - 20, 0, 150, 150, LAWN, 0)
	slab(f, "StageDeck", a, R + 42, 0, 70, 5, 30, OAK, { y = 0.6, solid = true })
	slab(f, "StageStep", a, R + 26, 0, 26, 2.8, 6, OAK, { y = 0.6, material = Enum.Material.Wood })
	local back = slab(f, "StageBack", a, R + 56, 0, 72, 26, 3, Color3.fromRGB(38, 42, 50), { y = 5 })
	board(back, { "DEMO DAY", "PITCH YOUR COMPANY  -  SATURDAY" },
		{ ppu = 22, maxDistance = 460, firstColor = GOLD, rowScale = 0.74 })
	slab(f, "StageRoof", a, R + 42, 0, 76, 3, 34, PAPER, { y = 27 })
	slab(f, "StageRig", a, R + 30, 0, 70, 1.0, 1.0, Color3.fromRGB(44, 48, 56), { y = 25.5 })
	for _, t in ipairs({ -22, -8, 8, 22 }) do
		slab(f, "StageLight", a, R + 30, t, 1.8, 1.4, 1.8, Color3.fromRGB(255, 236, 190),
			{ y = 24.0, material = Enum.Material.Neon })
	end
	for _, t in ipairs({ -34, 34 }) do
		slab(f, "StageCol", a, R + 42, t, 1.5, 27, 1.5, PAPER)
		-- speaker stacks, so the stage has a scale you can read against
		slab(f, "Speaker", a, R + 38, t * 0.82, 5, 11, 5, Color3.fromRGB(34, 36, 40), { y = 5.6 })
		slab(f, "SpeakerCone", a, R + 35.4, t * 0.82, 0.4, 3.4, 3.4, Color3.fromRGB(62, 66, 72),
			{ y = 9.0, shape = Enum.PartType.Cylinder, yaw = math.pi / 2 })
	end
	--[[ the expo tents: a flat square on four legs is a table, not a tent. Two
		slabs leaned against each other give a pitch, and a trestle under it
		gives the tent a reason to be there. ]]
	local tentCols = { TEAL, ORANGE, PAPER, RED, GOLD }
	for i = 0, 4 do
		local t = -60 + i * 30
		for _, sd in ipairs({ -1, 1 }) do
			local pos = at(a, R - 18 + sd * 6, t)
			part(f, {
				Name = "TentRoof",
				Size = Vector3.new(24, 0.7, 13.6),
				CFrame = CFrame.new(pos.X, 13.1, pos.Z)
					* CFrame.Angles(0, -a + math.pi / 2, 0) * CFrame.Angles(sd * math.rad(26), 0, 0),
				Color = tentCols[i + 1],
			})
		end
		slab(f, "TentRidge", a, R - 18, t, 24.4, 0.5, 0.9, PAPER, { y = 14.5 })
		for _, u in ipairs({ -10, 10 }) do
			for _, v in ipairs({ -10, 10 }) do
				slab(f, "TentLeg", a, R - 18 + v, t + u, 0.6, 12, 0.6, PAPER)
			end
		end
		slab(f, "TentTable", a, R - 18, t, 14, 0.5, 4.0, PAPER, { y = 3.2 })
		slab(f, "TentCloth", a, R - 18, t, 14.2, 3.2, 4.2, tentCols[i + 1], { y = 0 })
	end
	-- the food trucks: a hatch, a counter, a menu and wheels
	for i, col in ipairs({ RED, TEAL, ORANGE }) do
		local t = -38 + (i - 1) * 38
		slab(f, "FoodTruck", a, R - 72, t, 22, 8.4, 9, col, { y = 2.0, solid = true })
		slab(f, "FoodCab", a, R - 72, t + 13, 6, 5.6, 8.6, col, { y = 2.0 })
		slab(f, "FoodCabGlass", a, R - 72, t + 16.1, 0.4, 3.2, 7.4, GLASS, { y = 5.4, transparency = 0.3 })
		slab(f, "FoodHatch", a, R - 76.6, t - 1, 13, 5.0, 0.4, Color3.fromRGB(36, 38, 42), { y = 4.6 })
		slab(f, "FoodShutter", a, R - 78.0, t - 1, 13.4, 0.5, 3.4, PAPER, { y = 8.6 })
		slab(f, "FoodCounter", a, R - 78.4, t - 1, 13.4, 0.6, 3.0, PAPER, { y = 4.4 })
		local menu = slab(f, "FoodMenu", a, R - 76.8, t + 7.5, 6.0, 3.4, 0.4, Color3.fromRGB(38, 42, 50), { y = 9.0 })
		board(menu, { ({ "TACOS", "NOODLES", "COFFEE" })[i] },
			{ ppu = 30, maxDistance = 220, rowScale = 0.7 })
		for _, u in ipairs({ -7, 11 }) do
			slab(f, "FoodWheel", a, R - 72, t + u, 10, 3.2, 3.2, Color3.fromRGB(40, 42, 46),
				{ y = 0.2, shape = Enum.PartType.Cylinder, yaw = math.pi / 2 })
		end
	end
	for _, t in ipairs({ -84, 84 }) do
		tree(f, a, R - 78, t, 1.1)
		tree(f, a, R + 10, t, 1.1)
	end
	-- queueing at the hatches, and watching the stage
	for i = 0, 2 do
		spot(f, a, R - 84, -38 + i * 38 - 1, false, 0)
		spot(f, a, R - 90, -38 + i * 38 + 5, false, 0)
	end
	for _, q in ipairs({ { R + 8, -14 }, { R + 4, 10 }, { R - 6, 26 }, { R - 2, -34 } }) do
		spot(f, a, q[1], q[2], false, math.pi)
	end
end

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
