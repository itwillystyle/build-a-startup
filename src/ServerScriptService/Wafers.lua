--[[ Wafers (phase 3 of docs/superpowers/specs/2026-09-30-wafers-hq-design.md):
the one-building HQ, on the server.

The numbers and the plan live in WaferPlan (pure, tested against the sim).
This module turns a plot's level into a building:
  - every piece is placed around the garage (the garage never goes away);
  - a segment is one storey of one 45-degree slice of a wafer, with the
    department its owner chose: glass tint, furniture, seats and a money sign;
  - collision is simple rotated boxes (floors, walls, partitions with doors);
    the look is the imported mesh kit (blender/wafers.py, HQMeta.Wafers) when
    it is there, and the collision boxes made visible when it is not;
  - the glass lift in the courtyard reaches every built storey (HQFloors' lift
    menu and remotes, so LiftClient is unchanged).

SiliconCore owns the economy and asks this module for: the level, the stage
(the old HQ 1-5, which recruit tiers, homes and the journey still key off),
seats, capacity, department effects, and the price of the next BUILD tap. ]]
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")

local P = require(SSS:WaitForChild("WaferPlan"))
local G = P.GEO

local Wafers = {}
Wafers.Plan = P

local api          -- from SiliconCore: part, rise, FK, HQFloors, popup
local META = {}
do
	local ok, m = pcall(function() return require(SSS:WaitForChild("HQMeta", 5)) end)
	if ok and type(m) == "table" then META = m end
end

-- ---------------------------------------------------------------- look
Wafers.TINT = {
	lobby = Color3.fromRGB(236, 214, 170),
	eng = Color3.fromRGB(150, 188, 232),
	studio = Color3.fromRGB(236, 164, 192),
	cafe = Color3.fromRGB(246, 176, 116),
	servers = Color3.fromRGB(70, 78, 96),
	labs = Color3.fromRGB(122, 214, 198),
	board = Color3.fromRGB(236, 202, 112),
}
Wafers.NAME = {
	lobby = "LOBBY", eng = "ENGINEERING", studio = "DESIGN STUDIO", cafe = "CAFE",
	servers = "SERVER ROOM", labs = "AI LABS", board = "BOARDROOM",
}
Wafers.BLURB = {
	eng = "+2 seats for engineers and researchers",
	studio = "+2 seats for designers, more money",
	cafe = "+4 seats for sales and recruiters, more output",
	servers = "bigger launch paydays",
	labs = "+2 seats for researchers, products 15% faster",
	board = "investors start one interest higher",
}
-- which room kind a department seats (RoomEconomy.FIT reads these)
local SEAT_ROOM = { lobby = "office", eng = "office", studio = "studio", cafe = "cafe", labs = "labs" }
local PAPER = Color3.fromRGB(243, 239, 230)
local CHARCOAL = Color3.fromRGB(46, 50, 58)
local LAWN = Color3.fromRGB(118, 160, 92)   -- ART.md Campus Lawn (see CampusHub)
local GOLD = Color3.fromRGB(255, 194, 61)

-- tinted glass for the kit's glass meshes (they are vertex white)
local function glassOf(color, t)
	return { Material = Enum.Material.Glass, Transparency = t or 0.45, CastShadow = false, Color = color }
end

--[[ THE FACADE TINT (v7).

From the plaza the tower read as coloured static -- pink, orange, green and
blue bands stacked up it. The cause was not interior furniture, as first
assumed: it was the DEPARTMENT TINT painted straight onto the exterior glass,
at full saturation, with a different department on nearly every floor.

A real curtain wall is one glass colour for the whole building. Departments
still need to be legible, so the tint is kept but pulled most of the way
toward a common glass blue-grey: the floor still reads warm or cool up close
and on its sign, and the tower reads as one building from across the map.

Inside, and on the sign, the full-strength colour is unchanged. ]]
local GLASS_BASE = Color3.fromRGB(176, 202, 214)
local FACADE_MIX = 0.78          -- how far toward the common colour

local function facadeTint(dept)
	local c = Wafers.TINT[dept] or PAPER
	return c:Lerp(GLASS_BASE, FACADE_MIX)
end

-- ---------------------------------------------------------------- geometry
local RAD45 = math.rad(45)
local DECK_TOP = -G.SLAB + 0.3     -- a deck / roof surface, relative to its storey's floor top

-- storey s: its walkable floor top (plot-local y)
--[[ THE PATH PREFIX.

The Wafers and the Terrafab kits emit the SAME 40 piece names under different
prefixes (W_Seg_2 / T_Seg_2), so ONE placer builds either path and the economy
never forks. A player's choice is a single string on their plot.

Wafers.anchor(plot, L) runs at the top of every build function, so setting the
current prefix there means it is always right for the piece being built, per
piece. Nothing to keep in sync, and no assumption that the build path never
yields.

An unknown value falls back to W_, so a corrupt save can never make a player's
whole HQ invisible. ]]
local PATHS = { ["W_"] = "Wafers", ["T_"] = "Terrafab", ["D_"] = "Dome" }
local CUR = "W_"

function Wafers.pathOf(plot)
	local v = plot and plot.hqPath
	return (v and PATHS[v]) and v or "W_"
end

function Wafers.pathName(prefix)
	return PATHS[prefix] or "Wafers"
end

Wafers.PATHS = PATHS

local function pname(name)
	if CUR == "W_" then return name end
	return (name:gsub("^W_", CUR))
end

function Wafers.floorY(s) return G.FLOOR_Y + s * G.H end

--[[ THE SILHOUETTE (v4.9). The massing of the FINISHED tower -- every wafer's
	radius and the y band it occupies -- derived from the same PIECES plan the
	real building is built from, so the two can never drift.

	The opening flyover draws this as a translucent ghost on an empty lot, which
	is the only way a brand-new player can see where they are going: on a fresh
	server nobody has built anything yet, so there is no real tower to point at.

	Encoded as a string because attributes cannot hold tables:
		"r:y0:y1|r:y0:y1|..."   (plot-local studs) ]]
function Wafers.towerSpec()
	local band = {}
	for _, pc in ipairs(P.PIECES) do
		if pc.kind == "segment" then
			local b = band[pc.wafer]
			if b then
				b.lo, b.hi = math.min(b.lo, pc.storey), math.max(b.hi, pc.storey)
			else
				band[pc.wafer] = { lo = pc.storey, hi = pc.storey }
			end
		end
	end
	local out = {}
	for w = 1, 4 do
		local b = band[w]
		if b then
			table.insert(out, ("%d:%d:%d"):format(G.WAFER[w].r,
				math.floor(Wafers.floorY(b.lo) - G.SLAB), math.floor(Wafers.floorY(b.hi) + G.H)))
		end
	end
	-- the crown: the pavilion ring and the mast above wafer 4
	table.insert(out, ("%d:%d:%d"):format(G.PAVILION.rout,
		math.floor(Wafers.floorY(14)), math.floor(Wafers.floorY(15) + 8)))
	return table.concat(out, "|")
end

-- the old HQ level (1-5) this level stands for: recruit tiers, homes, the journey
function Wafers.stage(level)
	if level >= 18 then return 5 elseif level >= 13 then return 4 elseif level >= 9 then return 3
	elseif level >= 5 then return 2 end
	return 1
end

-- a wafer's centre (plot-local)
local function centre(w)
	local g = G.WAFER[w]
	return g.cx, g.cz, g.r
end

-- the anchor of piece L: wafer centre, turned to its segment, at its storey's floor top
function Wafers.anchor(plot, L)
	CUR = Wafers.pathOf(plot)        -- every build function starts here
	local pc = P.PIECES[L]
	if pc.kind == "garage" then return plot.pivot end
	if pc.kind == "halo" or pc.kind == "lantern" or pc.kind == "mast" then
		return plot.pivot * CFrame.new(G.CORE.x, Wafers.floorY(pc.storey), G.CORE.z)
	end
	local cx, cz = centre(pc.wafer)
	local turn = 0
	if pc.kind == "segment" then turn = (pc.seg - 1) * RAD45
	elseif pc.kind == "pavilion" then turn = (pc.seg - 1) * math.rad(90) end
	return plot.pivot * CFrame.new(cx, Wafers.floorY(pc.storey), cz) * CFrame.Angles(0, turn, 0)
end

-- the straight-line chord of an arc of `ang` radians at radius r
local function chord(r, ang) return 2 * r * math.sin(ang / 2) end

-- ---------------------------------------------------------------- state
--[[ the campus grounds (CampusArch.grounds) were laid out for the old six-lot campus:
lawn trees, benches and lamps stand where the ring rises, and the spur paths lead to
lots that no longer exist. Anything taller than the paving inside the building's
footprint (every wafer's band, with a margin) goes, and so do the spurs. Once per plot. ]]
local function clearFootprint(plot)
	local grounds = plot.folder and plot.folder:FindFirstChild("Grounds")
	if not (grounds and plot.pivot) then return end
	local function inside(pos)
		local lp = plot.pivot:PointToObjectSpace(pos)
		-- the lobby's entrance canopy reaches out over the plaza (W_Lobby: to z ~72, x +-23)
		local w1 = G.WAFER[1]
		if math.abs(lp.X - w1.cx) <= 25 and lp.Z - w1.cz >= w1.r - G.DEPTH and lp.Z - w1.cz <= 76 then return true end
		for _, w in pairs(G.WAFER) do
			local r = Vector2.new(lp.X - w.cx, lp.Z - w.cz).Magnitude
			if r >= w.r - G.DEPTH - 3 and r <= w.r + 4 then return true end
		end
		return false
	end
	for _, c in ipairs(grounds:GetChildren()) do
		local pos, top
		if c:IsA("Model") then
			local cf, size = c:GetBoundingBox()
			pos, top = cf.Position, cf.Position.Y + size.Y / 2
		elseif c:IsA("BasePart") then
			pos, top = c.Position, c.Position.Y + c.Size.Y / 2
		end
		if c.Name == "Spur" or (pos and top > 1.2 and inside(pos)) then c:Destroy() end
	end
end

local function stateOf(plot)
	if not plot.wafer then
		local folder = Instance.new("Folder")
		folder.Name = "Wafers"
		folder.Parent = plot.folder
		plot.wafer = { level = 1, depts = {}, pieces = {}, folder = folder, core = {}, stops = {} }
		clearFootprint(plot)
	end
	return plot.wafer
end
Wafers.stateOf = stateOf

function Wafers.level(plot) return plot.wafer and plot.wafer.level or 1 end

function Wafers.counts(plot)
	local c = {}
	local st = plot.wafer
	if not st then return c end
	for L = 2, st.level do
		local d = st.depts[L]
		if d then c[d] = (c[d] or 0) + 1 end
	end
	return c
end

function Wafers.capacity(plot)
	return math.min(P.capAt(Wafers.level(plot)), 1 + P.seats(Wafers.counts(plot)))
end

function Wafers.effects(plot) return P.effects(Wafers.counts(plot)) end

-- ---------------------------------------------------------------- building blocks
local function add(model, props)
	local p = api.part(props, model)
	return p
end

-- boxes along an arc, facet k of n between angles ang0..ang1 (piece-local), at radius r,
-- from y0 up h; `gap` leaves a doorway that wide in the middle facet (n odd)
local function arcBoxes(ang0, ang1, n, r, width, y0, h, props, gap)
	local made = {}
	local step = (ang1 - ang0) / n
	for k = 1, n do
		local a = ang0 + (k - 0.5) * step
		local len = chord(r + width / 2, step) + 0.3
		local cf = CFrame.Angles(0, a, 0) * CFrame.new(0, y0 + h / 2, r)
		if gap and k == math.ceil(n / 2) and n % 2 == 1 then
			-- a doorway in the middle facet: two narrower boxes either side
			local side = (len - gap) / 2
			if side > 0.2 then
				for _, sx in ipairs({ -1, 1 }) do
					local p = table.clone(props)
					p.Size = Vector3.new(side, h, width)
					p.CFrame = cf * CFrame.new(sx * (gap + side) / 2, 0, 0)
					table.insert(made, p)
				end
			end
		else
			local p = table.clone(props)
			p.Size = Vector3.new(len, h, width)
			p.CFrame = cf
			table.insert(made, p)
		end
	end
	return made
end

-- place a list of {props with a LOCAL CFrame} under `model` at `anchor`
local function placeAll(model, anchor, list)
	local parts = {}
	for _, p in ipairs(list) do
		p.CFrame = anchor * p.CFrame
		table.insert(parts, add(model, p))
	end
	return parts
end

-- the imported template for `name`, or nil (the metadata ships with the code; the
-- meshes arrive with a Bulk Import, so "has a mesh" means the template is in the place)
local function template(name)
	name = pname(name)
	local lib = RS:FindFirstChild("SVMeshes")
	local tpl = lib and (lib:FindFirstChild(name) or lib:FindFirstChild(name, true))
	if tpl and META[name] then return tpl end
	return nil
end

-- the imported mesh named `name`, placed in the piece's local frame (HQMeta.Wafers)
local function mesh(model, anchor, name, color, props)
	local tpl = template(name)
	local m = META[pname(name)]      -- template() already resolved the prefix
	if not tpl then return nil end
	local mp = tpl:IsA("Model") and tpl:FindFirstChildWhichIsA("MeshPart", true) or tpl
	if not mp then return nil end
	mp = mp:Clone()
	mp.Anchored = true
	mp.CanCollide = false
	mp.CanQuery = false
	mp.CanTouch = false
	mp.PivotOffset = CFrame.new()
	mp.CFrame = anchor * CFrame.new(m.c)
	if color then mp.Color = color end
	for k, v in pairs(props or {}) do mp[k] = v end
	mp.Parent = model
	return mp
end

-- ---------------------------------------------------------------- a segment
local function segmentVariant(pc)
	if pc.wafer == 1 and pc.storey == 0 and pc.seg == 1 then return "lobby" end
	if pc.seg == 5 then return "bridge" end
	return "plain"
end

--[[ ============ THE DOME'S INTERIOR ============

All three paths shared one `furnish`, so the inside of a Dome looked exactly
like the inside of a chip fab. The outside was three buildings and the inside
was one.

Bay View, which this path is drawn from, works on a few specific ideas, and
they are all things the other two paths deliberately do NOT do:

  - Workstations and team areas live UPSTAIRS, communal space BELOW. A floor
    here is one storey, so instead the Dome leans communal everywhere the
    Wafers lean rows.
  - Flexible team "NEIGHBOURHOODS", not desk rows: a cluster angled in on
    itself around a rug.
  - Indoor COURTYARDS linking everything, with kitchenettes and soft seating
    rather than corridors.
  - CLERESTORY daylight at the roof seam, and timber everywhere the Terrafab
    has steel.
  - "Variety over standardization" -- so the cluster is seeded per floor and
    no two look the same.

Sources: BIG + Heatherwick via Dezeen and Architectural Record.

The Wafers and the Terrafab keep the original rows: a fab SHOULD look like
rows of tool bays, and Samsung's floors genuinely are open-plan desks. ]]
local TIMBER = Color3.fromRGB(198, 154, 102)

--[[ THE DOME'S ROOM IS NOT THE FULL DEPTH, and this furnisher did not know.

	dome.py sets INSET = 7.0: the Dome's glass stands seven studs INSIDE the
	slab edge, under the canopy overhang, which is the whole look of the path.
	The Wafers and the Terrafab have no inset -- their glass is at the slab
	edge -- so only this one is affected.

	Everything here was laid out around `r - DEPTH/2`, the centre of the FULL
	twenty-stud slab, which for the Dome is 3.5 studs outboard of the real
	room. Pieces near the middle looked merely pushed out; anything with a
	large outward offset went straight through the glass and stood on the
	apron. That is the lobby bookcase, the cafe's kitchen run and the studio's
	pin-up wall -- the three things he kept photographing.

	Nothing could catch it from inside the game: the glass is baked into the
	shell mesh, which is CanQuery = false with Box collision, so no raycast,
	no collision test and no part-versus-part sweep can see where it is. The
	only place that fact exists is dome.py, so the number is mirrored here
	with a comment pointing at it.

	The partition code at the bottom of this file already compensated for the
	same inset. This function simply never did. ]]

--[[ THE MIDDLE OF THE ROOM YOU CAN ACTUALLY WALK IN.

	Not `r - DEPTH/2`, which is the middle of the structural slab. The Dome
	glazes seven studs inside that edge, so for the Dome those are different
	numbers and every placer that used the slab centre pushed its furniture
	out through the glass.

	Three separate functions had their own copy of `r - G.DEPTH / 2`:
	domeFurnish, station, and the two other paths' furnishers. Correcting one
	of them simply moved the collision to the next. One helper, so the room is
	the same room to everything that furnishes it. ]]
--[[ A SERVER-ROOM EXTRACT FAN. Two parts: a static housing and a blade cross
	that MotionClient spins, because a tagged part costs nothing until a player
	is near enough to resolve it.

	Server floors were the one department with no sign of life -- racks and a
	light strip, all of it frozen. A turning fan behind glass is the cheapest
	thing in the game that says a building is running. ]]
local function serverFan(model, cf, size, rpm)
	add(model, {
		Name = "FanHousing", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.35, size, size),
		CFrame = cf * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(48, 52, 60), Material = Enum.Material.Metal,
		CanCollide = false, CanQuery = false, CastShadow = false,
	})
	local blades = add(model, {
		Name = "FanBlades", Size = Vector3.new(size * 0.86, size * 0.14, 0.08),
		CFrame = cf * CFrame.new(0, 0, 0.12),
		Color = Color3.fromRGB(86, 92, 102), Material = Enum.Material.Metal,
		CanCollide = false, CanQuery = false, CastShadow = false,
	})
	CollectionService:AddTag(blades, "SVSpin")
	blades:SetAttribute("Rpm", rpm or 150)
	blades:SetAttribute("Axis", "Z")
	return blades
end

local function roomMid(r)
	local inset = P.INSET[CUR] or 0
	local rin = r - G.DEPTH
	local rout = r - inset - P.GLASS_BAND
	return (rin + rout) / 2, rin, rout
end

local function domeFurnish(model, anchor, dept, r, L)
	local FK = api.FK
	local seats = {}
	if not FK then return seats end
	local rm, rin, rout = roomMid(r)
	--[[ Flush against that glass -- and the lateral offset has to be part of
		the sum. The wall is an ARC but `place` takes a straight z, so a piece
		set at the same z as its neighbour sits progressively closer to the
		glass the further it is from the segment's centre line. A bookcase at
		x -11.5 reached 1.33 studs further out than its z implied.

		So: the far corner is what has to clear the arc. Solve for the z whose
		outermost corner lands on the glass, given how wide the piece is and
		how far off centre it stands. ]]
	local function wall(depth, x, width)
		local lat = math.abs(x or 0) + (width or 0) / 2
		local z = math.sqrt(math.max(rout * rout - lat * lat, 1))
		return z - depth / 2 - 0.2
	end
	--[[ The same for the courtyard side. Pulling the layout in off the outer
		glass pushed whatever faced the courtyard through the INNER glass --
		18 lounge chairs, by up to a stud. A room has two walls and a fix that
		only respects one of them just moves the fault across the floor. ]]
	local rinner = rin + 0.6                     -- the outside face of the inner glass
	local function courtyard(depth) return rinner + depth / 2 + 0.2 end
	local base = anchor
	local rng = Random.new(L * 7919)          -- variety, but the same every rebuild

	local function seatAt(x, z, lookX, lookZ)
		local pos = (base * CFrame.new(x, 2.4, z)).Position
		local look = (base * CFrame.new(lookX or 0, 2.4, lookZ or rm)).Position
		table.insert(seats, CFrame.lookAt(pos, look))
	end
	local function place(key, x, z, yaw, opts)
		local o = opts or {}
		o.yaw = yaw
		pcall(FK.onFloor, key, base, x, z, 0, model, o)
	end
	--[[ The same, but standing on a surface instead of the floor. A kettle or a
		coffee machine belongs on the worktop; placed with `place` it ends up on
		the floor at the counter's feet, which from the room reads as a machine
		buried in the cabinetry. ]]
	local function onTop(key, x, z, yaw, surfaceY, opts)
		local o = opts or {}
		o.yaw = yaw
		pcall(FK.onFloor, key, base, x, z, surfaceY, model, o)
	end

	-- every Dome floor: a timber soffit band and the lit clerestory seam.
	-- This is the path's signature indoors, the way the track is outdoors.
	add(model, { Name = "Soffit", Size = Vector3.new(chord(r - 2, RAD45) , 0.6, G.DEPTH - 3),
		CFrame = anchor * CFrame.new(0, G.H - 2.0, rm), Color = TIMBER,
		Material = Enum.Material.WoodPlanks, CanCollide = false, CanQuery = false, CastShadow = false })
	add(model, { Name = "Clerestory", Size = Vector3.new(chord(r - 1, RAD45), 0.3, 1.6),
		CFrame = anchor * CFrame.new(0, G.H - 2.6, rm + G.DEPTH / 2 - 1.4),
		Color = Color3.fromRGB(255, 244, 212), Material = Enum.Material.Neon,
		CanCollide = false, CanQuery = false, CastShadow = false })

	if dept == "eng" or dept == "labs" then
		-- a neighbourhood: two desks turned in on each other, not a row at a window
		local sp = 4.6 + rng:NextNumber() * 1.2
		place("rugRounded", 0, rm, 0)
		place("desk", -sp, rm + 1.6, 150, { accent = Wafers.TINT[dept] })
		place("desk", sp, rm + 1.6, -150, { accent = Wafers.TINT[dept] })
		place("chairDesk", -sp + 0.4, rm - 1.0, -30)
		place("chairDesk", sp - 0.4, rm - 1.0, 30)
		seatAt(-sp + 0.4, rm - 1.0, 0, rm + 4)
		seatAt(sp - 0.4, rm - 1.0, 0, rm + 4)
		place("loungeChair", 0, courtyard(2.41), 180)
		place("pottedPlant", -10.5, rm + 2.0, 0)
		place("plantSmall" .. (1 + rng:NextInteger(0, 2)), 10.5, rm + 2.0, 0)
	elseif dept == "studio" then
		place("rug_oval_A", 0, rm, 0)
		place("loungeDesignSofa", 0, rm + 4.2, 180)
		place("loungeDesignChair", -4.4, rm - 1.6, 60)
		place("loungeDesignChair", 4.4, rm - 1.6, -60)
		place("tableCoffeeGlass", 0, rm, 0)
		seatAt(-4.4, rm - 1.6, 0, rm + 4)
		seatAt(4.4, rm - 1.6, 0, rm + 4)
		-- the pin-up wall: Bay View's "playful materials", and a reason to look
		for i = -1, 1 do
			place("pictureframe_" .. (i == 0 and "large_A" or "medium"), i * 5.0, wall(0.3, i * 5.0, 5.0), 0)
		end
	elseif dept == "cafe" then
		--[[ THE KITCHENETTE, rebuilt 5 Oct from his report that furniture is
			"misplaced to be overlapping". Both faults were real and both were
			visible from inside the room:

			  THE RUN HAD GAPS. Units were spaced on a 3.0 grid while a
			  kitchenBar is 2.53 wide, so every joint showed 0.47 studs of
			  daylight, and the end cap sat 1.4 studs clear of the run
			  entirely. Apartments.lua and HQFloors.lua both lay the same
			  pieces at 2.53 and look right -- this was a copy whose spacing
			  had drifted off the piece width.

			  THE COFFEE MACHINE WAS ON THE FLOOR. It was placed with the same
			  floor-level call as the cabinets, 0.6 studs in front of one, so
			  it interpenetrated the counter by 0.72 studs and read as a
			  machine half-buried in the joinery. It stands on the worktop now.

			Laid out from a measured left edge rather than by eye, so the run
			is flush by construction and a different piece width cannot
			silently reopen the gaps. ]]
		local BAR_W, END_W, FRIDGE_W = 2.53, 0.60, 2.53
		local BAR_TOP = 2.47                     -- the worktop height
		local runW = BAR_W * 2 + END_W
		local left = -runW / 2                   -- the run, centred on the wedge
		local b1 = left + BAR_W / 2
		local b2 = b1 + BAR_W
		local cap = b2 + BAR_W / 2 + END_W / 2
		-- ONE z for the whole run, set by its outermost corner (the fridge's far
		-- edge) so the counter stays a straight line and still clears the arc
		local fridgeX = cap + END_W / 2 + 0.2 + FRIDGE_W / 2
		local z = wall(1.72, fridgeX, FRIDGE_W)
		place("kitchenBar", b1, z, 0)
		place("kitchenBar", b2, z, 0)
		place("kitchenBarEnd", cap, z, 0)
		onTop("kitchenCoffeeMachine", b1, z, 0, BAR_TOP)
		-- the fridge closes the run, with a hand's width to open its door
		place("kitchenFridge", cap + END_W / 2 + 0.2 + FRIDGE_W / 2, z, 0)
		place("tableRound", 0, rm - 1.2, 0, { canCollide = true })
		for _, o in ipairs({ { 0, 2.6, 180 }, { 0, -2.6, 0 }, { 2.4, 0, -90 }, { -2.4, 0, 90 } }) do
			place("chairRounded", o[1], rm - 1.2 + o[2], o[3])
			seatAt(o[1], rm - 1.2 + o[2], 0, rm - 1.2)
		end
		place("pottedPlant", -9.5, rm + 1.0, 0)
	elseif dept == "servers" then
		-- still a machine room, but screened in timber rather than left raw
		for _, x in ipairs({ -6, -2, 2, 6 }) do
			add(model, { Name = "Rack", Size = Vector3.new(3, 7, 2.2), CFrame = base * CFrame.new(x, 3.5, rm + 3),
				Color = Color3.fromRGB(38, 42, 52), Material = Enum.Material.Metal, CastShadow = false })
			local lit = add(model, { Name = "RackLight", Size = Vector3.new(2.2, 0.2, 0.1), CFrame = base * CFrame.new(x, 5.6, rm + 1.85),
				Color = Color3.fromRGB(120, 240, 200), Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, CastShadow = false })
			CollectionService:AddTag(lit, "SVPulse")
			lit:SetAttribute("Hz", 0.35)
			lit:SetAttribute("Depth", 0.30)
		end
		for _, x in ipairs({ -9, 9 }) do
			serverFan(model, base * CFrame.new(x, 6.2, rm + 3.1), 3.0, 170)
		end
		add(model, { Name = "Screen", Size = Vector3.new(20, 5.2, 0.4), CFrame = base * CFrame.new(0, 3.1, rm - 2.2),
			Color = TIMBER, Material = Enum.Material.WoodPlanks, CanCollide = false, CanQuery = false, CastShadow = false })
		place("pottedPlant", -11, rm - 4.0, 0)
	elseif dept == "board" then
		place("rug_rectangle_A", 0, rm, 0)
		place("tableCross", -2.2, rm, 0)
		place("tableCross", 2.2, rm, 0)
		for _, x in ipairs({ -5.2, -1.8, 1.8, 5.2 }) do
			place("loungeDesignChair", x, rm + 3.4, 180)
			place("loungeDesignChair", x, rm - 3.4, 0)
		end
		place("lampRoundFloor", -10, rm + 2, 0)
	else   -- lobby
		-- the indoor courtyard: the thing you walk into, soft and planted
		place("rugRound", 0, rm, 0)
		place("loungeSofaLong", -6.5, rm + 2.0, 90)
		place("loungeSofaLong", 6.5, rm + 2.0, -90)
		place("tableCoffee", 0, rm + 2.0, 0)
		place("loungeChairRelax", 0, courtyard(3.97), 180)
		for _, x in ipairs({ -12, 12 }) do place("pottedPlant", x, wall(1.42, x, 1.25), 0) end
		--[[ THE BOOKCASE IS GONE, and that is the fix rather than a fourth
			position for it. It was buried 56% into the outer glass at x -11.5,
			landed on the planter when pulled flush, and hit the long sofa when
			moved along the wall. The only clear span left on that wall is the
			2.46 studs between the sofa's end and the planter, for a piece 2.35
			wide -- a 0.06-stud clearance, which is the near-miss this whole
			pass exists to stop shipping.

			A lobby is reception, seating, a table and plants. It was never
			short of a bookcase; the bookcase was short of a wall. ]]
	end
	return seats
end

--[[ ============ THE TERRAFAB'S INTERIOR ============

The Dome got its own interior and the Terrafab did not, so the inside of a chip
fab was an open-plan office with a potted plant in it. The outside says
semiconductor plant and the inside said startup.

What a real fab floor actually has, and what each of these is for:

  - BAY AND CHASE. Tools stand in a row (the bay); the pipework, pumps and
    power that feed them live in a service strip behind (the chase), reached
    without entering the clean side. So: machines along the outer wall, a
    cable-and-pipe strip behind them, and the walkway on the courtyard side.
  - OVERHEAD TRANSPORT. Wafers never travel by hand. They ride sealed carriers
    (FOUPs) on a track near the ceiling -- Intel's Arizona fab runs about 30
    miles of it. It is the single most recognisable thing in a modern fab and
    nothing else in this game has a ceiling rail, so it reads instantly.
  - YELLOW LIGHT IN LITHOGRAPHY. Photoresist is sensitive to blue and UV, so
    litho bays are lit through yellow filters. That is why fab photographs are
    yellow. AI Labs is this path's litho bay and is lit that way.
  - GOWNING. You do not walk into a cleanroom. The lobby is an airlock with a
    bench and suit lockers.

The Wafers path deliberately keeps the plain rows below: Samsung San Jose's
floors genuinely are open-plan desks facing the glass, so "rows" is right
there and would be wrong here.

Seat counts match the generic furnish exactly (eng/labs/lobby 2, studio 2,
cafe 4, servers and board 0) -- the room economy counts seats, so changing the
furniture must not change the capacity. ]]
local STEEL = Color3.fromRGB(176, 182, 188)
local ANOD = Color3.fromRGB(96, 102, 110)
local LITHO = Color3.fromRGB(255, 206, 92)

local function fabFurnish(model, anchor, dept, r, L)
	local FK = api.FK
	local seats = {}
	local rm = r - G.DEPTH / 2
	local base = anchor
	local litho = (dept == "labs")

	local function box(name, sx, sy, sz, x, y, z, col, mat, extra)
		local t = { Name = name, Size = Vector3.new(sx, sy, sz), CFrame = base * CFrame.new(x, y, z),
			Color = col, Material = mat or Enum.Material.SmoothPlastic, CastShadow = false }
		for k, v in pairs(extra or {}) do t[k] = v end
		return add(model, t)
	end
	local function seatAt(x, z, lookZ)
		local pos = (base * CFrame.new(x, 2.4, z)).Position
		local look = (base * CFrame.new(x, 2.4, lookZ)).Position
		table.insert(seats, CFrame.lookAt(pos, look))
	end

	-- THE CHASE: the service strip against the outer wall, behind the tools
	box("Chase", 34, 0.9, 1.6, 0, 7.4, rm + 6.2, ANOD, Enum.Material.DiamondPlate)
	for _, x in ipairs({ -13, -4.5, 4.5, 13 }) do
		box("ChaseDrop", 0.5, 5.4, 0.5, x, 4.6, rm + 6.2, ANOD, Enum.Material.Metal)
	end

	--[[ THE OVERHEAD TRACK runs over the AISLE, at rm - 0.4, not over the
		tools at rm + 3.4. It used to share both the tools' z and their x, so
		each hanging carrier passed 0.75 studs through a ToolHead and 0.55
		into the Tool body -- a 1.9-stud box hanging inside a machine.

		A real fab hangs the hoist over the walkway in front of the tool
		fronts, which is also the only z here that clears the load ports
		(rm + 0.3) below and the service chase (rm + 6.2) behind. ]]
	local OHT_Z = rm - 0.4
	box("OHTRail", 32, 0.45, 0.9, 0, G.H - 3.1, OHT_Z, STEEL, Enum.Material.Metal)
	for _, x in ipairs({ -8.5, 7.0 }) do
		-- strap, pod and lid are one carrier: the strap grips the lid, so they
		-- share space on purpose (same reason the process tool is a Model)
		local pod = box("FOUP", 2.2, 1.9, 1.9, x, G.H - 5.0, OHT_Z, Color3.fromRGB(226, 232, 238))
		local carrier = Instance.new("Model")
		carrier.Name = "OHTCarrier"
		for _, prt in ipairs({ pod,
			box("OHTHanger", 0.3, 1.1, 0.3, x, G.H - 3.8, OHT_Z, ANOD, Enum.Material.Metal),
			box("FOUPLid", 2.3, 0.3, 2.0, x, G.H - 4.0, OHT_Z, litho and LITHO or Color3.fromRGB(120, 190, 210)) })
		do
			prt.Parent = carrier
		end
		carrier.PrimaryPart = pod
		carrier.Parent = model
	end

	if dept == "eng" or dept == "labs" then
		-- TOOL BAY: two process tools, a loadport each, and an operator at a
		-- console facing the tool (not a desk facing a window)
		for _, x in ipairs({ -8.5, 7.0 }) do
			--[[ ONE MODEL PER MACHINE. The head sits on the body and the load
				port is bolted to its face, so those overlaps are how the tool
				is built, not faults -- but a flat pile of parts cannot say so,
				and SVCheck read them as three separate things colliding.

				Grouping them states the relationship in the geometry, so the
				checker learns it from the builder instead of from a list of
				names it has to be taught. A carrier swinging into the tool is
				still a different object, and still gets caught. ]]
			local body = box("Tool", 7.0, 7.6, 4.4, x, 3.8, rm + 3.4, Color3.fromRGB(228, 230, 234))
			local parts = { body,
				box("ToolHead", 5.6, 1.0, 3.6, x, 8.1, rm + 3.4, ANOD, Enum.Material.Metal),
				box("LoadPort", 2.4, 1.2, 1.4, x, 4.3, rm + 1.0, STEEL, Enum.Material.Metal),
				box("ToolLamp", 4.2, 0.18, 2.6, x, 7.55, rm + 3.4,
					litho and LITHO or Color3.fromRGB(190, 240, 255), Enum.Material.Neon,
					{ CanCollide = false, CanQuery = false }) }
			local machine = Instance.new("Model")
			machine.Name = "ProcessTool"
			for _, prt in ipairs(parts) do prt.Parent = machine end
			machine.PrimaryPart = body
			machine.Parent = model
			box("Console", 2.6, 0.2, 1.4, x, 3.5, rm - 1.6, CHARCOAL)
			box("ConsoleScreen", 2.4, 1.4, 0.12, x, 4.4, rm - 2.2,
				litho and LITHO or Color3.fromRGB(150, 220, 240), Enum.Material.Neon,
				{ CanCollide = false, CanQuery = false })
			seatAt(x, rm - 3.2, rm + 3.4)          -- the operator faces the tool
		end

	elseif dept == "lobby" then
		-- GOWNING: a bench down the middle, suit lockers on the wall, and the
		-- air shower you step through to reach the floor
		box("GownBench", 14, 0.5, 2.0, 0, 2.2, rm - 1.0, STEEL, Enum.Material.Metal, { CanCollide = true })
		box("BenchLeg", 13, 2.0, 0.4, 0, 1.1, rm - 1.0, ANOD, Enum.Material.Metal)
		for i = -3, 3 do
			box("Locker", 2.1, 7.0, 1.6, i * 2.4, 3.6, rm + 5.6,
				(i % 2 == 0) and Color3.fromRGB(214, 218, 224) or Color3.fromRGB(198, 204, 212))
			box("LockerVent", 1.5, 0.16, 0.1, i * 2.4, 6.2, rm + 4.78, ANOD, Enum.Material.Metal,
				{ CanCollide = false, CanQuery = false })
		end
		box("AirShower", 0.4, 8.6, 5.0, -11.0, 4.3, rm + 1.0, STEEL, Enum.Material.Metal)
		box("AirShowerGlow", 0.12, 7.0, 4.2, -10.75, 4.3, rm + 1.0, Color3.fromRGB(190, 240, 255),
			Enum.Material.Neon, { CanCollide = false, CanQuery = false })
		seatAt(-3.2, rm - 1.0, rm + 5.6)
		seatAt(3.2, rm - 1.0, rm + 5.6)

	elseif dept == "studio" then
		-- the metrology bench: where a wafer gets measured, not a design studio
		box("Metrology", 9.0, 3.4, 3.0, 0, 1.7, rm + 2.6, Color3.fromRGB(226, 228, 232))
		box("Scope", 2.0, 3.2, 2.0, 0, 5.0, rm + 2.6, ANOD, Enum.Material.Metal)
		box("ScopeGlow", 1.4, 0.16, 1.4, 0, 3.35, rm + 2.6, Color3.fromRGB(150, 230, 255),
			Enum.Material.Neon, { CanCollide = false, CanQuery = false })
		for _, x in ipairs({ -4.2, 4.2 }) do
			box("Stool", 1.6, 0.3, 1.6, x, 2.4, rm - 1.4, CHARCOAL)
			box("StoolLeg", 0.4, 2.2, 0.4, x, 1.3, rm - 1.4, STEEL, Enum.Material.Metal)
			seatAt(x, rm - 1.4, rm + 2.6)
		end

	elseif dept == "cafe" then
		-- the break room is OUTSIDE the clean side, so it is the one warm room
		if FK then
			pcall(FK.onFloor, "tableRound", base, 0, rm, 0, model, { canCollide = true })
			local ring = { { 0, 2.6, 180 }, { 0, -2.6, 0 }, { 2.4, 0, -90 }, { -2.4, 0, 90 } }
			for _, o in ipairs(ring) do
				pcall(FK.onFloor, "chairModernCushion", base, o[1], rm + o[2], 0, model, { yaw = o[3] })
				seatAt(o[1], rm + o[2], rm)
			end
			pcall(FK.onFloor, "coffeeMachine", base, -9.5, rm + 5.4, 0, model, { yaw = 180 })
		else
			for _, o in ipairs({ { 0, 2.6 }, { 0, -2.6 }, { 2.4, 0 }, { -2.4, 0 } }) do
				seatAt(o[1], rm + o[2], rm)
			end
		end
		box("Vending", 3.0, 7.0, 2.0, 9.5, 3.6, rm + 5.4, Color3.fromRGB(196, 92, 72))
		box("VendingGlass", 2.2, 4.4, 0.12, 9.5, 4.4, rm + 4.36, Color3.fromRGB(120, 200, 230),
			Enum.Material.Neon, { CanCollide = false, CanQuery = false })

	elseif dept == "servers" then
		-- the subfab: pumps and gas cabinets, not an IT rack room
		for _, x in ipairs({ -9, -3, 3, 9 }) do
			box("GasCabinet", 4.2, 7.4, 2.6, x, 3.8, rm + 4.2, Color3.fromRGB(206, 210, 216))
			box("CabinetLamp", 3.0, 0.18, 0.12, x, 6.9, rm + 2.88, Color3.fromRGB(255, 150, 110),
				Enum.Material.Neon, { CanCollide = false, CanQuery = false })
			box("Pump", 2.6, 2.2, 2.2, x, 1.2, rm - 1.6, ANOD, Enum.Material.Metal)
		end
		box("GasLine", 26, 0.5, 0.5, 0, 8.6, rm + 3.0, STEEL, Enum.Material.Metal)

	elseif dept == "board" then
		box("FabBoard", 12, 0.4, 4.0, 0, 3.0, rm + 1.0, Color3.fromRGB(226, 228, 232))
		box("YieldScreen", 10, 4.0, 0.14, 0, 6.4, rm + 5.6, Color3.fromRGB(150, 220, 240),
			Enum.Material.Neon, { CanCollide = false, CanQuery = false })
	end

	return seats
end

local function furnish(model, anchor, dept, r, L)
	if CUR == "D_" then return domeFurnish(model, anchor, dept, r, L) end
	if CUR == "T_" then return fabFurnish(model, anchor, dept, r, L) end
	local FK = api.FK
	local seats = {}
	local rm = r - G.DEPTH / 2
	local base = anchor
	local function seatAt(x, z, faceOut)
		local pos = (base * CFrame.new(x, 2.4, z)).Position
		local look = (base * CFrame.new(x, 2.4, z + (faceOut and 5 or -5))).Position
		table.insert(seats, CFrame.lookAt(pos, look))
	end
	if not FK then return seats end
	if dept == "eng" or dept == "labs" or dept == "lobby" then
		local xs = (dept == "lobby") and { -12, 12 } or { -5.5, 5.5 }
		for _, x in ipairs(xs) do
			-- the desk faces the outer window, the chair sits on the courtyard side of it
			pcall(FK.workstation, base, x, rm + 3, 0, model, { yaw = 180, accent = Wafers.TINT[dept] })
			seatAt(x - 0.3, rm + 3 - 2.6, true)
		end
		if dept == "lobby" and FK.has and FK.has("desk") then
			pcall(FK.onFloor, "loungeSofa", base, -9, rm - 4, 0, model, { yaw = 0 })
		end
	elseif dept == "studio" then
		pcall(FK.onFloor, "tableCross", base, 0, rm, 0, model)
		pcall(FK.onFloor, "chairModernCushion", base, -3.7, rm + 0.4, 0, model, { yaw = 90 })
		pcall(FK.onFloor, "chairModernCushion", base, 3.7, rm + 0.4, 0, model, { yaw = -90 })
		for _, x in ipairs({ -3.7, 3.7 }) do
			local pos = (base * CFrame.new(x, 2.4, rm + 0.4)).Position
			local look = (base * CFrame.new(0, 2.4, rm + 0.4)).Position
			table.insert(seats, CFrame.lookAt(pos, look))
		end
	elseif dept == "cafe" then
		pcall(FK.onFloor, "tableRound", base, 0, rm, 0, model, { canCollide = true })
		local ring = { { 0, 2.6, 180 }, { 0, -2.6, 0 }, { 2.4, 0, -90 }, { -2.4, 0, 90 } }
		for _, o in ipairs(ring) do
			pcall(FK.onFloor, "chairModernCushion", base, o[1], rm + o[2], 0, model, { yaw = o[3] })
			local pos = (base * CFrame.new(o[1], 2.4, rm + o[2])).Position
			local look = (base * CFrame.new(0, 2.4, rm)).Position
			table.insert(seats, CFrame.lookAt(pos, look))
		end
	elseif dept == "servers" then
		for _, x in ipairs({ -6, -2, 2, 6 }) do
			add(model, { Name = "Rack", Size = Vector3.new(3, 7, 2.2), CFrame = base * CFrame.new(x, 3.5, rm + 3),
				Color = Color3.fromRGB(38, 42, 52), Material = Enum.Material.Metal, CastShadow = false })
			local lit = add(model, { Name = "RackLight", Size = Vector3.new(2.2, 0.2, 0.1), CFrame = base * CFrame.new(x, 5.6, rm + 1.85),
				Color = Color3.fromRGB(120, 240, 200), Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, CastShadow = false })
			CollectionService:AddTag(lit, "SVPulse")
			lit:SetAttribute("Hz", 0.35)
			lit:SetAttribute("Depth", 0.30)
		end
		for _, x in ipairs({ -9, 9 }) do
			serverFan(model, base * CFrame.new(x, 6.2, rm + 3.1), 3.0, 170)
		end
	elseif dept == "board" then
		pcall(FK.onFloor, "tableCross", base, -2.2, rm, 0, model)
		pcall(FK.onFloor, "tableCross", base, 2.2, rm, 0, model)
	end
	return seats
end

-- the money sign on the courtyard face of a segment
local function sign(model, anchor, rin, dept)
	local p = add(model, { Name = "DeptSign", Size = Vector3.new(12, 1.6, 0.2),
		CFrame = anchor * CFrame.new(0, G.H - 3.2, math.sqrt(rin * rin - 36) - 0.45),
		Color = CHARCOAL, CanCollide = false, CanQuery = false, CastShadow = false })
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(480, 64)
	sg.LightInfluence = 0
	sg.MaxDistance = 160
	sg.Parent = p
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(255, 255, 255)
	t.Text = Wafers.NAME[dept] or ""
	t.Parent = sg
	return t
end

--[[ ============ FLOOR STATIONS (v7) ============

The floors had furniture and a money sign but nothing to DO, so there was no
reason to walk into your own building -- you took the lift to the top once and
never went back.

One station per floor, department-specific, on a cooldown. It hands out the
same boost items the game already has, so this adds a reason to explore without
adding a new economy to balance. Walking your own tower now pays.

Cooldown lives on the session, not the save: a free boost that survives a
rejoin is a relog exploit, and nothing here is worth a save-format change. ]]
local STATION = {
	eng     = { item = "coffee",    label = "GRAB A COLD BREW",  obj = "Brew" },
	labs    = { item = "scout",     label = "READ THE RESEARCH", obj = "Bench" },
	studio  = { item = "frontpage", label = "PITCH THE PRESS",   obj = "Board" },
	cafe    = { item = "energy",    label = "ENERGY DRINK",      obj = "Fridge" },
	servers = { item = "frontpage", label = "RUN THE NUMBERS",   obj = "Terminal" },
	board   = { item = "noncompete", label = "CALL LEGAL",       obj = "Phone" },
}
local STATION_COOLDOWN = 420      -- 7 minutes per floor

local function station(model, anchor, dept, r, plot, L)
	local def = STATION[dept]
	if not (def and api and api.prompt and api.grant) then return end
	local rm = roomMid(r)          -- the room, not the slab: see roomMid above
	local body = add(model, {
		Name = "Station",
		Size = Vector3.new(3.2, 4.4, 1.8),
		CFrame = anchor * CFrame.new(-7.5, G.SLAB + 2.2, rm - 3.2),
		Color = Wafers.TINT[dept] or PAPER,
		Material = Enum.Material.SmoothPlastic,
		CastShadow = false,
	})
	add(model, {
		Name = "StationGlow",
		Size = Vector3.new(2.4, 0.3, 1.2),
		CFrame = anchor * CFrame.new(-7.5, G.SLAB + 4.5, rm - 3.2),
		Color = Color3.fromRGB(255, 236, 190),
		Material = Enum.Material.Neon,
		CanCollide = false, CanQuery = false, CastShadow = false,
	})
	local pr = api.prompt(body, def.label, def.obj, 10)
	pr.Triggered:Connect(function(player)
		if api.plotOf and api.plotOf(player) ~= plot then return end     -- your own building only
		local sess = api.session and api.session(player)
		if not sess then return end
		sess.floorUsed = sess.floorUsed or {}
		local now = os.clock()
		local last = sess.floorUsed[L] or -1e9
		local left = STATION_COOLDOWN - (now - last)
		if left > 0 then
			if api.popup then api.popup(body, ("Ready in %dm"):format(math.ceil(left / 60)), Color3.fromRGB(226, 112, 96)) end
			return
		end
		if api.grant(player, def.item, 1) then
			sess.floorUsed[L] = now
			if api.popup then api.popup(body, "+1 " .. def.label:gsub("^%u+ ", ""), Color3.fromRGB(122, 190, 110)) end
		end
	end)
end

local function buildSegment(plot, L, dept, model)
	local pc = P.PIECES[L]
	local anchor = Wafers.anchor(plot, L)
	local _, _, r = centre(pc.wafer)
	local rin = r - G.DEPTH
	local variant = segmentVariant(pc)
	local half = RAD45 / 2
	local wallH = G.H - G.SLAB
	local tint = Wafers.TINT[dept] or PAPER
	-- collision (and the fallback look when the mesh kit is missing)
	local hasMesh = template("W_Seg_" .. pc.wafer) ~= nil
	local slabProps = { Name = "Floor", Color = PAPER, Material = Enum.Material.SmoothPlastic, CastShadow = not hasMesh,
		Transparency = hasMesh and 1 or 0 }
	local glassProps = { Name = "Wall", Color = tint, Material = hasMesh and Enum.Material.SmoothPlastic or Enum.Material.Glass,
		Transparency = hasMesh and 1 or 0.45, CastShadow = false }
	local list = {}
	local y0 = -G.SLAB   -- the slab sits below the floor top
	for _, p in ipairs(arcBoxes(-half, half, 3, rin + G.DEPTH / 2, G.DEPTH + 0.6, y0, G.SLAB, slabProps)) do
		p.Size = Vector3.new(chord(r + 0.6, RAD45 / 3) + 0.3, G.SLAB, G.DEPTH + 0.6)
		table.insert(list, p)
	end
	for _, p in ipairs(arcBoxes(-half, half, 3, r - 0.5, 1, 0, wallH, glassProps, variant == "lobby" and 14 or nil)) do
		table.insert(list, p)
	end
	local innerGap = (variant == "lobby" and 14) or (variant == "bridge" and 6) or nil
	for _, p in ipairs(arcBoxes(-half, half, 3, rin + 0.5, 1, 0, wallH, glassProps, innerGap)) do
		table.insert(list, p)
	end
	--[[ RADIAL PARTITIONS, with a doorway round the ring.

	v7, from his report: "i cant even walk between each interior opening door".
	Measured before changing anything -- a lap of the ring at walking height
	showed the floor blocked at radius 42-45 and 54-58 and clear only at 48-52.
	So the doorway was real and intentional, and 6 studs wide in a floor 20
	studs deep: you had to find the one line through it, and anywhere else you
	walked into a wall. A door you have to aim at is a wall with a rumour of a
	door.

	Now 12 studs, and CENTRED ON THE WALKABLE DEPTH rather than on the
	structure. That matters for the Dome, whose glass is set in 7 studs: its
	usable floor is rin..r-7, so a door centred at rin + DEPTH/2 sat against the
	outer glass instead of in the middle of the room. ]]
	local inset = (CUR == "D_") and 7.0 or 0.0
	-- The MESH's doorway sits at (partition radius) - DEPTH/2, and dome.py calls
	-- W.partition with the INSET radius, so the Dome's visible door is 7 studs
	-- further in than every other path's. The collision has to follow it, or
	-- the hole in the wall and the hole you can walk through are different holes
	-- -- which is exactly what an invisible barrier is.
	local rm = rin + G.DEPTH / 2 - inset
	-- the mesh frames a 6-stud opening; collision is a touch wider so the frame
	-- is the limit you can see, never an invisible lip just inside it
	local halfDoor = 3.5
	for _, a in ipairs({ -half, half }) do
		for _, span in ipairs({ { rin, rm - halfDoor }, { rm + halfDoor, r } }) do
			local len = span[2] - span[1]
			if len <= 0.2 then continue end     -- the door can eat a whole span
			local p = table.clone(glassProps)
			p.Name = "Partition"
			p.Size = Vector3.new(0.4, wallH, len)
			p.CFrame = CFrame.Angles(0, a, 0) * CFrame.new(0, wallH / 2, span[1] + len / 2)
			table.insert(list, p)
		end
	end
	local parts = placeAll(model, anchor, list)
	-- the look
	local visual = {}
	if hasMesh then
		local suffix = (variant == "lobby" and "Lobby") or (variant == "bridge" and "SegB_" .. pc.wafer) or ("Seg_" .. pc.wafer)
		local glassName = (variant == "lobby" and "W_LobbyGlass") or (variant == "bridge" and "W_GlassB_" .. pc.wafer) or ("W_Glass_" .. pc.wafer)
		local shellA = anchor * CFrame.new(0, -G.SLAB, 0)       -- the mesh frame starts at the slab bottom
		local shell = mesh(model, shellA, "W_" .. suffix, nil, { CastShadow = true })
		local glass = mesh(model, shellA, glassName, facadeTint(dept), { Material = Enum.Material.Glass, Transparency = 0.28, CastShadow = false })
		if shell then table.insert(visual, shell) end
		if glass then table.insert(visual, glass) end
	end

	--[[ THE DEPARTMENT BAND (v5.0).

		Choosing a department is a decision the player makes up to 100 times,
		and until now it was INVISIBLE from more than a few studs away. The
		glass already carries the department colour, but FACADE_MIX dilutes it
		78% toward a common blue-grey so the tower reads as one building --
		which it should -- and what survives is 22% of a hue, seen through
		glass at 0.28 transparency. From the ring road that is grey.

		Both things can be true at once, and real curtain walls solve it the
		same way: the MASS stays one colour, and a narrow solid spandrel at
		each floor line carries the accent. So the glass is left exactly as it
		was and the band is new. Up close it labels the floor; from across the
		campus the stack of bands is a readable record of how somebody built
		their company.

		It sits on the slab edge, just proud of the facade, and is opaque --
		a tinted band would lose the one job it has. ]]
	do
		local bandC = Wafers.TINT[dept]
		if bandC and variant ~= "bridge" then
			local bandProps = { Name = "DeptBand", Color = bandC,
				Material = Enum.Material.SmoothPlastic, CastShadow = false, CanQuery = false }
			local band = {}
			--[[ Sizing, after looking at it from both distances. At 0.8 deep and
				2.2 tall it was tucked behind the mesh's slab edge and read as
				two pixels from the ring road -- visible up close, useless at
				the range that matters. Pushed proud of the slab and raised to
				3.0, which is still under a quarter of a 13-stud storey, so the
				tower stays mostly glass. ]]
			for _, q in ipairs(arcBoxes(-half, half, 3, r + 0.55, 1.05, -G.SLAB - 0.05, 3.0, bandProps)) do
				table.insert(band, q)
			end
			for _, q in ipairs(placeAll(model, anchor, band)) do table.insert(visual, q) end
		end
	end
	--[[ THE PODIUM (v7). The base half of the tripartite division: a plinth
	wider than the shaft with a deep entrance on the road side, so the tower
	stands on something instead of meeting the ground.

	It wraps the ground floor on purpose -- a podium IS the ground-floor
	envelope -- which is why it is G.H * 1.4 tall and overlaps storey 0.

	So it waits for wafer 1 to be finished and arrives with the FIRST PIECE OF
	WAFER 2 -- the moment the building stops being one ring and becomes a stack.
	The podium is 18.4 studs tall against a 13-stud storey and is wider than a
	single ring, so a player who owned only storey 0 watched their whole
	building vanish inside its own base: it read as an empty grey stadium and
	the floors looked deleted. Measured on all three paths: at level 9 the base
	buries everything, at level 10 it still out-masses the single storey above
	it, and at level 19 the shaft is 2.2x the base and it finally reads as a
	base. This also makes it a reward instead of a surprise.

	It is gated on a SEGMENT, not on wafer 1's deck, because this whole block
	lives in buildSegment -- a deck-kind test here would never fire and the
	podium would disappear from the game entirely. ]]
	if pc.wafer == 2 and pc.seg == 1 and pc.storey == 3 then
		--[[ AN OPEN COLONNADE, NOT A DRUM (4 Oct). Measured on a real save: the
		podium mesh is 144.8 x 16.4 x 145.4 studs, so it wrapped the ground
		storey (13 tall) completely and its edge reached 72.4 out -- past the
		drive kerb at 67.6, i.e. the base of the building stood in the road.
		The player reported the ground floor "blocked" for the second time.

		It is not blocked physically: the mesh is CanCollide false. It is
		blocked to the EYE, which is the same thing to a player -- you cannot
		see the floor you are standing on or find the way into it.

		So: no wall, and no mesh. A plinth you can step over, a ring of piers
		with a 45-degree gap facing the forecourt, and a lintel over it. The
		tower still stands on something; the ground floor is visible between
		every bay. Measurable geometry, which the mesh was not (CanQuery false
		means you cannot even raycast it to check). ]]
		local px, pz = centre(1)
		local pa = plot.pivot * CFrame.new(px, 0, pz)
		local _, _, r1 = centre(1)
		local R = r1 + 6                 -- 66: outer face 67.5, kerb inner 77.6
		local PH, PLINTH = 16, 1.6
		local GAP = math.rad(22.5)       -- half the entrance, centred on +Z
		local stone = (CUR == "T_") and Color3.fromRGB(198, 196, 190)
			or (CUR == "D_") and Color3.fromRGB(246, 244, 238) or Color3.fromRGB(214, 206, 190)
		-- the plinth, broken for the entrance and low enough to step over
		for _, q in ipairs(arcBoxes(GAP, math.pi * 2 - GAP, 21, R - 2, 7, 0, PLINTH,
			{ Name = "Podium", Color = stone, Material = Enum.Material.SmoothPlastic, CastShadow = true })) do
			table.insert(visual, placeAll(model, pa, { q })[1])
		end
		-- the piers: 24 bays, the two either side of the entrance left out
		for k = 1, 24 do
			local a = (k - 0.5) * (math.pi * 2 / 24)
			if a > GAP and a < math.pi * 2 - GAP then
				table.insert(visual, add(model, { Name = "PodiumPier", Size = Vector3.new(3.0, PH - PLINTH, 3.2),
					CFrame = pa * CFrame.Angles(0, a, 0) * CFrame.new(0, PLINTH + (PH - PLINTH) / 2, R - 2.2),
					Color = stone, Material = Enum.Material.SmoothPlastic, CastShadow = true }))
			end
		end
		-- and the building's own shadow: with GlobalShadows off (v4.7) the tower
		-- floated, which was the one thing the cartoon A/B clearly cost
		local fl = require(script.Parent:WaitForChild("FlatLook"))
		local pod = pa.Position
		fl.contact(model, pod.X, pod.Z, R + 3, 0.22)
		-- the lintel they carry, full circle: it spans the entrance as a portal
		for _, q in ipairs(arcBoxes(0, math.pi * 2, 24, R - 2, 5.5, PH, 2.4,
			{ Name = "PodiumCap", Color = stone, Material = Enum.Material.SmoothPlastic, CastShadow = true })) do
			table.insert(visual, placeAll(model, pa, { q })[1])
		end
	end

	-- the columns from the deck below up to this wafer: with its first piece, so a
	-- finished deck never shows columns holding up nothing
	local below = pc.wafer - 1
	if pc.seg == 1 and below >= 1 then
		for _, q in ipairs(P.PIECES) do
			if q.kind == "deck" and q.wafer == below and q.storey + 1 == pc.storey then
				local bx, bz = centre(below)
				local deckA = plot.pivot * CFrame.new(bx, Wafers.floorY(q.storey) - G.SLAB, bz)
				local cols = mesh(model, deckA, "W_DeckCols_" .. below, nil, { CastShadow = true })
				if cols then table.insert(visual, cols) end
			end
		end
	end
	local seats = furnish(model, anchor, dept, r, L)
	-- one station per FLOOR, not per segment: seg 3 is a side bay, clear of the
	-- lobby (seg 1) and the lift bridge (seg 5)
	if P.PIECES[L] and P.PIECES[L].seg == 3 then
		station(model, anchor, dept, r, plot, L)
	end
	local label = (dept ~= "lobby") and sign(model, anchor, rin, dept) or nil
	return parts, visual, seats, label
end

-- ---------------------------------------------------------------- decks, roof, pavilion, crown
local function buildRing(plot, L, model, planted)
	local pc = P.PIECES[L]
	local anchor = Wafers.anchor(plot, L)
	local _, _, r = centre(pc.wafer)
	local rin = r - G.DEPTH
	local hasMesh = template(pc.kind == "roof" and "W_Roof" or ("W_Deck_" .. pc.wafer)) ~= nil
	local list = {}
	local n = 16
	local deckProps = { Name = "Deck", Color = planted and LAWN or PAPER, Material = Enum.Material.SmoothPlastic,
		Transparency = hasMesh and 1 or 0 }
	local railProps = { Name = "Rail", Color = Color3.fromRGB(200, 220, 230), Material = Enum.Material.Glass,
		Transparency = hasMesh and 1 or 0.5, CastShadow = false }
	for k = 1, n do
		local a = (k - 0.5) * (2 * math.pi / n)
		table.insert(list, { Name = deckProps.Name, Color = deckProps.Color, Material = deckProps.Material, Transparency = deckProps.Transparency,
			Size = Vector3.new(chord(r + 0.5, 2 * math.pi / n) + 0.4, 0.3, G.DEPTH + 0.5),
			CFrame = CFrame.Angles(0, a, 0) * CFrame.new(0, DECK_TOP - 0.15, rin + G.DEPTH / 2), CastShadow = false })
		for _, rr in ipairs({ r - 0.3, rin + 0.3 }) do
			-- the back of the ring (angle pi) is where the lift bridge lands: the
			-- inner rail leaves a 7-stud doorway there
			local a0, a1 = (k - 1) * (2 * math.pi / n), k * (2 * math.pi / n)
			local spans = { { a0, a1 } }
			local gapA = 3.5 / rr
			if rr < r - 1 and a0 < math.pi + gapA and a1 > math.pi - gapA then
				spans = {}
				if a0 < math.pi - gapA then table.insert(spans, { a0, math.pi - gapA }) end
				if a1 > math.pi + gapA then table.insert(spans, { math.pi + gapA, a1 }) end
			end
			for _, sp in ipairs(spans) do
				local am = (sp[1] + sp[2]) / 2
				table.insert(list, { Name = railProps.Name, Color = railProps.Color, Material = railProps.Material, Transparency = railProps.Transparency,
					CastShadow = false, Size = Vector3.new(chord(rr, sp[2] - sp[1]) + 0.3, 3.2, 0.3),
					CFrame = CFrame.Angles(0, am, 0) * CFrame.new(0, DECK_TOP + 1.6, rr) })
			end
		end
	end
	local parts = placeAll(model, anchor, list)
	local visual = {}
	local name = (pc.kind == "deck" and "W_Deck_" .. pc.wafer) or (pc.kind == "roof" and "W_Roof") or nil
	if name then
		local frame = anchor * CFrame.new(0, -G.SLAB, 0)
		local v = mesh(model, frame, name, nil, { CastShadow = true })
		if v then table.insert(visual, v) end
		local gname = (pc.kind == "deck" and "W_DeckGlass_" .. pc.wafer) or "W_RoofGlass"
		local gv = mesh(model, frame, gname, nil, glassOf(Color3.fromRGB(200, 222, 232), 0.5))
		if gv then table.insert(visual, gv) end
	end
	return parts, visual
end

local function buildPavilion(plot, L, model)
	local anchor = Wafers.anchor(plot, L)
	local hasMesh = template("W_Pav") ~= nil
	local list = {}
	local props = { Name = "PavWall", Color = Color3.fromRGB(236, 224, 196), Material = hasMesh and Enum.Material.SmoothPlastic or Enum.Material.Glass,
		Transparency = hasMesh and 1 or 0.4, CastShadow = false }
	for _, p in ipairs(arcBoxes(-math.rad(45), math.rad(45), 5, G.PAVILION.rout, 0.8, DECK_TOP, 9, props, 6)) do table.insert(list, p) end
	for _, p in ipairs(arcBoxes(-math.rad(45), math.rad(45), 5, G.PAVILION.rin, 0.8, DECK_TOP, 9, props, 6)) do table.insert(list, p) end
	local parts = placeAll(model, anchor, list)
	local visual = {}
	for _, nm in ipairs({ "W_Pav", "W_PavGlass" }) do
		local v = mesh(model, anchor * CFrame.new(0, -G.SLAB, 0), nm, nm == "W_PavGlass" and Color3.fromRGB(240, 226, 190) or nil,
			nm == "W_PavGlass" and { Material = Enum.Material.Glass, Transparency = 0.35 } or { CastShadow = true })
		if v then table.insert(visual, v) end
	end
	return parts, visual
end

local function buildCrown(plot, L, model)
	local pc = P.PIECES[L]
	local visual = {}
	local top = Wafers.floorY(14)
	local coreTop = top - G.SLAB + G.H          -- the top of the lift's highest storey (the roof's)
	local LANTERN_H = 11.2
	if pc.kind == "halo" then
		local cx, cz = centre(4)
		local a = plot.pivot * CFrame.new(cx, top + 8, cz)
		--[[ THE CROWN (v7). Tall buildings have had a base, a shaft and a crown
		since 1899 -- the tripartite division, borrowed from the classical
		column, and the reason a setback tower has a silhouette at all. All three
		paths here were pure shaft: they started at the ground and stopped at the
		top, which is why every render read as a stack of rings.

		The old crown was literally one 1.6-stud hoop. This is a real
		termination, and each path speaks its own language: the Wafers step back
		to a planted parapet and a mast, the Terrafab piles its fan-deck plant
		and two stacks, the Dome closes its canopy on a lit oculus. ]]
		local crA = plot.pivot * CFrame.new(cx, top + G.H * 0.2, cz)
		local cr = mesh(model, crA, "W_Crown", nil, { CastShadow = true })
		if cr then
			table.insert(visual, cr)
		else
			--[[ PRIMITIVE CROWNS, one per path.

			The mesh crowns are the better version, but they need an import, and
			the import needs Studio's Asset Manager UI. A building whose top only
			exists after an upload is a building with no top, so each path's crown
			is built here from parts as well. The mesh wins when it is present;
			this is what you get until then, and it is the same idea either way. ]]
			local _, _, r4 = centre(4)
			local pale = Color3.fromRGB(236, 232, 222)
			local function ring(rad, width, y, h, name, col, mat)
				for _, q in ipairs(arcBoxes(0, math.pi * 2, 24, rad, width, y, h,
					{ Name = name, Color = col, Material = mat or Enum.Material.SmoothPlastic, CastShadow = true })) do
					table.insert(visual, placeAll(model, crA, { q })[1])
				end
			end

			if CUR == "T_" then
				-- TERRAFAB: the fan deck. A fab's heaviest machinery sits ABOVE
				-- the cleanroom, so the top of the building is a raft of plant.
				local steel = Color3.fromRGB(176, 182, 188)
				local anod = Color3.fromRGB(96, 102, 110)
				ring(r4 - G.DEPTH / 2, G.DEPTH + 2, 0, 1.6, "Crown", Color3.fromRGB(120, 128, 136), Enum.Material.DiamondPlate)
				for _, spec in ipairs({ { r4 - 6, 10, 5.6 }, { r4 - 17, 8, 7.0 }, { r4 - 27, 6, 8.4 } }) do
					for k = 1, spec[2] do
						local a = (k - 0.5) * (math.pi * 2 / spec[2])
						table.insert(visual, add(model, { Name = "CrownPlant", Size = Vector3.new(8, spec[3], 7),
							CFrame = crA * CFrame.Angles(0, a, 0) * CFrame.new(0, 1.6 + spec[3] / 2, spec[1]),
							Color = anod, Material = Enum.Material.Metal, CastShadow = true }))
					end
				end
				for _, st in ipairs({ { 9, -5, 30 }, { -11, 7, 22 } }) do
					table.insert(visual, add(model, { Name = "CrownStack", Size = Vector3.new(5.2, st[3], 5.2),
						CFrame = crA * CFrame.new(st[1], 1.6 + st[3] / 2, st[2]),
						Color = pale, Material = Enum.Material.SmoothPlastic, CastShadow = true }))
					table.insert(visual, add(model, { Name = "CrownStackCap", Size = Vector3.new(6.2, 1.4, 6.2),
						CFrame = crA * CFrame.new(st[1], 1.6 + st[3] + 0.7, st[2]),
						Color = anod, Material = Enum.Material.Metal, CastShadow = false }))
				end
				ring(r4 + 1.6, 1.8, 9.0, 1.3, "CrownTrack", Color3.fromRGB(236, 170, 70))
			elseif CUR == "D_" then
				-- DOME: the apex. Every canopy below stops short; this one closes,
				-- on the lit clerestory seam the path is recognised by at night.
				local scaleA = Color3.fromRGB(158, 174, 196)
				local steps = 6
				for k = 0, steps - 1 do
					local t0, t1 = k / steps, (k + 1) / steps
					local r0 = (r4 + 1) * (1.0 - 0.46 * t0)
					local r1 = (r4 + 1) * (1.0 - 0.46 * t1)
					local h0 = 17.0 * math.sin(t0 * math.pi * 0.5)
					ring((r0 + r1) / 2, math.max(r0 - r1, 2) + 1.1, h0, 0.9, "Crown",
						k % 2 == 0 and scaleA or scaleA:Lerp(Color3.new(0, 0, 0), 0.12))
				end
				local rtop = (r4 + 1) * 0.54
				ring(rtop - 0.7, 4.6, 16.6, 1.8, "CrownOculus", Color3.fromRGB(255, 244, 212), Enum.Material.Neon)
			else
				-- WAFERS: a stepped parapet. The 1916 ziggurat move, and still the
				-- clearest way a tower says "this is the top".
				for _, st in ipairs({ { 0, 0 }, { 4.5, 5.0 }, { 9.0, 9.4 } }) do
					ring(r4 - st[1] - G.DEPTH / 2, G.DEPTH - st[1] * 2, st[2], 4.6, "Crown", pale)
				end
				ring(r4 - 10.5 - (G.DEPTH - 21) / 2, math.max(G.DEPTH - 21, 3), 14.0, 0.6, "CrownBed", LAWN, Enum.Material.Grass)
				ring(6.8, 1.6, 20.0, 1.0, "CrownRing", GOLD)
			end
			table.insert(visual, add(model, { Name = "CrownMast", Size = Vector3.new(1.4, 18, 1.4),
				CFrame = crA * CFrame.new(0, 23, 0), Color = pale,
				Material = Enum.Material.SmoothPlastic, CastShadow = false }))
		end
		local v = mesh(model, a, "W_Halo", nil, { CastShadow = false })
		if v then table.insert(visual, v) else
			for k = 1, 24 do
				local ang = (k - 0.5) * (2 * math.pi / 24)
				table.insert(visual, add(model, { Name = "Halo", Size = Vector3.new(chord(55, 2 * math.pi / 24) + 0.4, 0.8, 1.2),
					CFrame = a * CFrame.Angles(0, ang, 0) * CFrame.new(0, 0, 55), Color = GOLD, Material = Enum.Material.SmoothPlastic,
					CanCollide = false, CanQuery = false, CastShadow = false }))
			end
		end
	elseif pc.kind == "lantern" then
		local a = plot.pivot * CFrame.new(G.CORE.x, coreTop, G.CORE.z)
		local v = mesh(model, a, "W_Lantern", nil, {})
		if v then
			table.insert(visual, v)
			local gv = mesh(model, a, "W_LanternGlass", nil, glassOf(Color3.fromRGB(255, 236, 190), 0.3))
			if gv then table.insert(visual, gv) end
		else
			table.insert(visual, add(model, { Name = "Lantern", Shape = Enum.PartType.Cylinder, Size = Vector3.new(9, 12, 12),
				CFrame = a * CFrame.new(0, 4.5, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(255, 236, 190),
				Material = Enum.Material.Glass, Transparency = 0.3, CanCollide = false, CanQuery = false }))
		end
	elseif pc.kind == "mast" then
		local a = plot.pivot * CFrame.new(G.CORE.x, coreTop + LANTERN_H, G.CORE.z)
		local v = mesh(model, a, "W_Mast", nil, {})
		if v then table.insert(visual, v) else
			table.insert(visual, add(model, { Name = "Mast", Size = Vector3.new(1.2, 60, 1.2), CFrame = a * CFrame.new(0, 30, 0),
				Color = PAPER, Material = Enum.Material.SmoothPlastic, CanCollide = false, CanQuery = false }))
		end
	end
	return {}, visual
end

-- ---------------------------------------------------------------- the lift
local function stopName(s)
	for L = 1, P.MAX do
		local pc = P.PIECES[L]
		if pc.storey == s then
			if pc.kind == "deck" then return "GARDEN DECK" end
			if pc.kind == "roof" or pc.kind == "pavilion" then return "ROOF GARDEN" end
			if pc.kind == "segment" then return "WAFER " .. pc.wafer end
		end
	end
	return ""
end

-- the highest storey any built piece stands on (0 = the ground)
local function topStorey(st)
	local top = 0
	for L = 2, st.level do
		local pc = P.PIECES[L]
		if pc.kind ~= "halo" and pc.kind ~= "lantern" and pc.kind ~= "mast" then top = math.max(top, pc.storey) end
	end
	return top
end

-- the wafer whose ring the lift's bridge reaches at storey s (nil for the ground)
local function waferAt(s)
	for L = 2, P.MAX do
		local pc = P.PIECES[L]
		if pc.storey == s and pc.wafer >= 1 then return pc.wafer end
	end
	return nil
end

-- a storey whose lift stop is a deck or the roof: people walk on it DECK_TOP below the floor top
local function deckStorey(s)
	for L = 2, P.MAX do
		local pc = P.PIECES[L]
		if pc.storey == s and (pc.kind == "deck" or pc.kind == "roof") then return true end
	end
	return false
end

-- `core` is the storey's lift frame (its -Z faces that storey's bridge; the ground's +Z faces the garage)
local function liftButton(plot, st, s, core, stand)
	local HQ = api.HQFloors
	local side = (s == 0) and 1 or -1           -- ground: facing the garage; above: at the bridge
	--[[ BOTH PARTS GO IN st.core, and that is the whole bug fix.

		buildCore destroys st.core and rebuilds, and bridgeBetween tracks
		every part it makes -- but liftButton parented its two straight to
		st.folder and tracked neither. So every rebuild left the previous set
		behind: measured 14 LiftCallLit at exactly 7 positions, each one built
		twice, each carrying its own live "Take the lift" prompt.

		Found by the furniture gate only after it was widened to plain Parts.
		Nothing else in the project would have reported it, because two parts
		in exactly the same place look like one part. ]]
	local btn = add(st.folder, { Name = "LiftCall", Size = Vector3.new(1.2, 2, 0.4),
		CFrame = core * CFrame.new(3.2 * side, 4.2, side * (G.CORE.r + 1.0)) * CFrame.Angles(0, side > 0 and 0 or math.pi, 0),
		Color = CHARCOAL, CanCollide = false, CastShadow = false })
	table.insert(st.core, btn)
	table.insert(st.core, add(st.folder, { Name = "LiftCallLit", Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.5, 0.5), CFrame = btn.CFrame * CFrame.new(0, 0.3, -0.25),
		Color = GOLD, Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, CastShadow = false }))
	local id = (s == 0) and "L" or ("F" .. s)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Take the lift"
	pp.ObjectText = s == 0 and "COURTYARD" or stopName(s)
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 11
	pp.RequiresLineOfSight = false
	pp.Parent = btn
	pp.Triggered:Connect(function(player)
		if HQ and HQ.menu then HQ.menu(player, plot.index, id) end
	end)
	table.insert(st.stops, { id = id, name = s == 0 and "LOBBY" or tostring(s), sub = s == 0 and "COURTYARD" or stopName(s), stand = stand })
	table.insert(st.core, btn)
end

-- a glass walkway from `from` to `to` (plot space, on the walking surface): the kit's
-- bridge stretched to length, or a visible slab and rails without it
local function bridgeBetween(st, from, to)
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local len = math.max(2, flat.Magnitude)
	local dir = flat.Unit
	local frame = CFrame.lookAt(from, from - dir)       -- +Z runs along the bridge
	local tpl = template("W_Bridge")
	local mid = frame * CFrame.new(0, 0, len / 2)
	-- collision: the deck and two rails (the look when the kit is missing)
	local walk = add(st.folder, { Name = "Bridge", Size = Vector3.new(5, 0.6, len), CFrame = mid * CFrame.new(0, -0.3, 0),
		Color = Color3.fromRGB(200, 220, 230), Material = Enum.Material.Glass, Transparency = tpl and 1 or 0.3, CastShadow = false })
	table.insert(st.core, walk)
	for _, sx in ipairs({ -2.6, 2.6 }) do
		table.insert(st.core, add(st.folder, { Name = "BridgeRail", Size = Vector3.new(0.2, 3.2, len), CFrame = mid * CFrame.new(sx, 1.6, 0),
			Color = Color3.fromRGB(200, 220, 230), Material = Enum.Material.Glass, Transparency = tpl and 1 or 0.5, CastShadow = false }))
	end
	if tpl then
		for _, nm in ipairs({ "W_Bridge", "W_BridgeGlass" }) do
			local m = META[nm]
			local v = mesh(st.folder, frame, nm, nm == "W_BridgeGlass" and Color3.fromRGB(200, 222, 232) or nil,
				nm == "W_BridgeGlass" and glassOf(Color3.fromRGB(200, 222, 232), 0.5) or { CastShadow = true })
			if v and m then
				-- the kit's bridge is 10 long: stretch it (size and centre) to this one
				local k = len / m.s.Z
				v.Size = Vector3.new(v.Size.X, v.Size.Y, v.Size.Z * k)
				v.CFrame = frame * CFrame.new(m.c.X, m.c.Y, m.c.Z * k)
				table.insert(st.core, v)
			end
		end
	end
end

-- (re)build the glass lift up to the top storey, with a bridge and a stop on each one
local function buildCore(plot)
	local st = stateOf(plot)
	for _, p in ipairs(st.core) do if p.Parent then p:Destroy() end end
	st.core = {}
	st.stops = {}
	local top = topStorey(st)
	if top < 1 then
		if api.HQFloors and api.HQFloors.register then api.HQFloors.register(plot.index, plot, {}) end
		return
	end
	local coreCentre = plot.pivot * CFrame.new(G.CORE.x, 0, G.CORE.z)
	-- the ground stop: in the courtyard, in front of the core (facing the garage)
	liftButton(plot, st, 0, coreCentre + Vector3.new(0, Wafers.floorY(0), 0),
		plot.pivot * CFrame.new(G.CORE.x, G.FLOOR_Y + 0.1, G.CORE.z + G.CORE.r + 3))
	for s = 0, top do
		local y = Wafers.floorY(s)
		local walkY = deckStorey(s) and (y + DECK_TOP) or y
		-- this storey's bridge: from the core to the door at the back of that storey's ring
		-- (the middle of segment 5, which faces -Z from its wafer's centre)
		local w = waferAt(s)
		local frame = coreCentre + Vector3.new(0, y, 0)
		local door
		if s >= 1 then
			local cx, cz, r = centre(w or 1)
			local rin = r - G.DEPTH
			door = (plot.pivot * CFrame.new(cx, walkY, cz - rin - 0.5)).Position
			local here = (coreCentre + Vector3.new(0, walkY, 0)).Position
			local dir = Vector3.new(door.X - here.X, 0, door.Z - here.Z).Unit
			frame = CFrame.lookAt(frame.Position, frame.Position + dir)   -- -Z (the bridge door) faces the bridge
		end
		local base = frame * CFrame.new(0, -G.SLAB, 0)
		local tube = mesh(st.folder, base, "W_Core", nil, { CastShadow = true })
		if tube then
			table.insert(st.core, tube)
			local gl = mesh(st.folder, base, "W_CoreGlass", nil, glassOf(Color3.fromRGB(190, 214, 226), 0.45))
			if gl then table.insert(st.core, gl) end
			if s == top then
				local cap = mesh(st.folder, base, "W_CoreCap", nil, { CastShadow = true })
				if cap then table.insert(st.core, cap) end
			end
			-- the kit's tube has no collision: a plain cylinder keeps people out of the shaft
			table.insert(st.core, add(st.folder, { Name = "LiftShaft", Shape = Enum.PartType.Cylinder, Size = Vector3.new(G.H, G.CORE.r * 2, G.CORE.r * 2),
				CFrame = frame * CFrame.new(0, G.H / 2 - G.SLAB, 0) * CFrame.Angles(0, 0, math.rad(90)), Transparency = 1,
				CanCollide = true, CastShadow = false }))
		else
			table.insert(st.core, add(st.folder, { Name = "LiftTube", Shape = Enum.PartType.Cylinder, Size = Vector3.new(G.H, G.CORE.r * 2, G.CORE.r * 2),
				CFrame = frame * CFrame.new(0, G.H / 2 - G.SLAB, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(190, 214, 226),
				Material = Enum.Material.Glass, Transparency = 0.45, CanCollide = true, CastShadow = false }))
		end
		if s >= 1 then
			local from = (frame * CFrame.new(0, walkY - y, -(G.CORE.r + 0.6))).Position
			bridgeBetween(st, from, door)
			local stand = CFrame.lookAt((frame * CFrame.new(0, walkY - y + 0.1, -(G.CORE.r + 3.5))).Position,
				(frame * CFrame.new(0, walkY - y + 0.1, -(G.CORE.r + 9))).Position)
			liftButton(plot, st, s, frame + Vector3.new(0, walkY - y, 0), stand)
		end
	end
	if api.HQFloors and api.HQFloors.register then api.HQFloors.register(plot.index, plot, st.stops) end
end

-- ---------------------------------------------------------------- the piece
local function buildPiece(plot, L, dept, animate)
	local st = stateOf(plot)
	local pc = P.PIECES[L]
	local model = Instance.new("Model")
	model.Name = ("L%03d_%s%s"):format(L, pc.kind, dept and ("_" .. dept) or "")
	model:SetAttribute("Level", L)
	model:SetAttribute("Dept", dept)
	model.Parent = st.folder
	local seats, label = {}, nil
	if pc.kind == "segment" then
		local _, _
		_, _, seats, label = buildSegment(plot, L, dept or "eng", model)
	elseif pc.kind == "deck" or pc.kind == "roof" then
		buildRing(plot, L, model, true)
	elseif pc.kind == "pavilion" then
		buildPavilion(plot, L, model)
	elseif pc.kind == "halo" or pc.kind == "lantern" or pc.kind == "mast" then
		buildCrown(plot, L, model)
	end
	CollectionService:AddTag(model, "WaferPiece")
	st.pieces[L] = { model = model, seats = seats, label = label, dept = dept }
	if animate and api.rise then
		local list = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 then table.insert(list, d) end
		end
		pcall(api.rise, list, 6, 0.8)
	end
	--[[ Storeys are built DURING play, long after the world sweep ran, and a
		storey is full of cloned pack furniture. Without this, every level a
		player buys arrives in the pack's own colours while the rest of the
		campus is in the palette. ]]
	if api.Palette then api.Palette.enforce(model) end
	--[[ THE FLOOR SOUNDS LIKE WHAT YOU BUILT ON IT. Department is a choice the
		player makes on every one of a hundred levels and, until now, one you
		could only see. A floor of engineers murmurs, a server floor hums, the
		cafe has a room full of people in it, and all of it fades a few studs
		past the glass so walking in and out is audible.

		Parented to its own anchor part rather than to a wall, so a rebuild of
		the storey takes the sound with it and nothing is left playing in an
		empty sky. ]]
	if api.Sfx and dept then
		local room = api.Sfx.ROOM[dept]
		if room then
			local ok, cf = pcall(function() return select(1, model:GetBoundingBox()) end)
			if ok and cf then
				local anchor = add(model, {
					Name = "RoomTone", Size = Vector3.new(1, 1, 1), CFrame = cf,
					Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false,
					CastShadow = false,
				})
				api.Sfx.emitter(anchor, room.key, {
					volume = room.volume, pitch = room.pitch, min = 14, max = 58,
					-- stagger the loops so forty floors do not pulse in unison
					offset = (L * 3.7) % 30,
				})
			end
		end
	end
	return model
end

-- ---------------------------------------------------------------- public
-- build pieces from the current level up to `to` (a rebuilt storey is several at once)
function Wafers.buildUpTo(plot, to, deptOf, animate)
	local st = stateOf(plot)
	for L = st.level + 1, math.min(to, P.MAX) do
		local pc = P.PIECES[L]
		local dept = pc.kind == "segment" and deptOf(L) or nil
		st.depts[L] = dept
		buildPiece(plot, L, dept, animate)
		st.level = L
	end
	buildCore(plot)
end

-- everything back to the garage (a spin-off, or the owner leaving)
function Wafers.clear(plot)
	local st = plot.wafer
	if not st then return end
	for _, c in ipairs(st.folder:GetChildren()) do c:Destroy() end
	st.level, st.depts, st.pieces, st.core, st.stops = 1, {}, {}, {}, {}
	if api and api.HQFloors and api.HQFloors.register then api.HQFloors.register(plot.index, plot, {}) end
end

-- every seat in the building: { cf, room (the FIT room kind), seg (its level), dept }
function Wafers.seats(plot)
	local out = {}
	local st = plot.wafer
	if not st then return out end
	for L = 2, st.level do
		local piece = st.pieces[L]
		if piece and piece.dept then
			for _, cf in ipairs(piece.seats) do
				table.insert(out, { cf = cf, room = SEAT_ROOM[piece.dept] or "office", seg = L, dept = piece.dept })
			end
		end
	end
	return out
end

-- the money signs: income per segment, formatted by `fmt`
function Wafers.refreshSigns(plot, perSeg, fmt)
	local st = plot.wafer
	if not st then return end
	for L, piece in pairs(st.pieces) do
		if piece.label then
			local v = perSeg[L]
			local name = Wafers.NAME[piece.dept] or ""
			local txt
			if piece.dept == "servers" then txt = name .. "  ·  BIGGER PAYDAYS"
			elseif piece.dept == "board" then txt = name .. "  ·  BETTER DEALS"
			elseif v and v > 0 then txt = ("%s  ·  $%s/s"):format(name, fmt(v))
			else txt = name .. "  ·  EMPTY SEATS" end
			if piece.label.Text ~= txt then piece.label.Text = txt end
		end
	end
end

-- the next BUILD tap: its first and last level and its price for this company
function Wafers.nextBuild(plot, record, scale, cap)
	local L = Wafers.level(plot) + 1
	if L > math.min(cap, P.MAX) then return nil end
	local last = math.min(P.rebuildLast(L, record), cap)
	local price = 0
	for x = L, last do price += P.price(x, scale, record) end
	return L, last, price
end

function Wafers.init(a)
	api = a
end

return Wafers
