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
local LAWN = Color3.fromRGB(122, 170, 80)
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

local function domeFurnish(model, anchor, dept, r, L)
	local FK = api.FK
	local seats = {}
	if not FK then return seats end
	local rm = r - G.DEPTH / 2
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
		place("loungeChair", 0, rm - 5.0, 180)
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
			place("pictureframe_" .. (i == 0 and "large_A" or "medium"), i * 5.0, rm + 8.4, 0)
		end
	elseif dept == "cafe" then
		-- a kitchenette, which Bay View puts on every floor instead of one canteen
		place("kitchenBar", -3.0, rm + 7.6, 0)
		place("kitchenBar", 0.0, rm + 7.6, 0)
		place("kitchenBarEnd", 3.0, rm + 7.6, 0)
		place("kitchenCoffeeMachine", -3.0, rm + 7.0, 0)
		place("kitchenFridge", 7.4, rm + 7.6, 0)
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
			add(model, { Name = "RackLight", Size = Vector3.new(2.2, 0.2, 0.1), CFrame = base * CFrame.new(x, 5.6, rm + 1.85),
				Color = Color3.fromRGB(120, 240, 200), Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, CastShadow = false })
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
		place("loungeChairRelax", 0, rm - 4.5, 180)
		for _, x in ipairs({ -12, 12 }) do place("pottedPlant", x, rm + 5.0, 0) end
		place("bookcaseOpen", -11.5, rm + 7.8, 0)
	end
	return seats
end

local function furnish(model, anchor, dept, r, L)
	if CUR == "D_" then return domeFurnish(model, anchor, dept, r, L) end
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
			add(model, { Name = "RackLight", Size = Vector3.new(2.2, 0.2, 0.1), CFrame = base * CFrame.new(x, 5.6, rm + 1.85),
				Color = Color3.fromRGB(120, 240, 200), Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, CastShadow = false })
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
	local rm = r - G.DEPTH / 2
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
	-- radial partitions at both ends, with a doorway round the ring
	local rm = rin + G.DEPTH / 2
	for _, a in ipairs({ -half, half }) do
		for _, span in ipairs({ { rin, rm - 3 }, { rm + 3, r } }) do
			local len = span[2] - span[1]
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
	local btn = add(st.folder, { Name = "LiftCall", Size = Vector3.new(1.2, 2, 0.4),
		CFrame = core * CFrame.new(3.2 * side, 4.2, side * (G.CORE.r + 1.0)) * CFrame.Angles(0, side > 0 and 0 or math.pi, 0),
		Color = CHARCOAL, CanCollide = false, CastShadow = false })
	add(st.folder, { Name = "LiftCallLit", Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.5, 0.5), CFrame = btn.CFrame * CFrame.new(0, 0.3, -0.25),
		Color = GOLD, Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, CastShadow = false })
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
