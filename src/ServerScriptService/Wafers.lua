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
local T = require(RS:WaitForChild("TowerPlan"))   -- v9 (14 Oct): the tower's geometry (rectangular, 24/18-stud storeys)
local SLAB = T.SLAB

local Wafers = {}
Wafers.Plan = P

local api          -- from SiliconCore: part, rise, FK, HQFloors, popup

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
local GOLD = Color3.fromRGB(255, 194, 61)


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


-- ---------------------------------------------------------------- geometry (v9, 14 Oct: the tower)
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

function Wafers.pathOf(plot)
	local v = plot and plot.hqPath
	return (v and PATHS[v]) and v or "W_"
end

function Wafers.pathName(prefix)
	return PATHS[prefix] or "Wafers"
end

Wafers.PATHS = PATHS


function Wafers.floorY(s) return T.floorY(s) end
function Wafers.towerSpec() return T.spec() end

function Wafers.anchor(plot, L)
	local pc = P.PIECES[L]
	if pc.kind == "garage" then return plot.pivot end
	local f = T.frame(pc)
	return plot.pivot * CFrame.new(f.x, T.floorY(pc.storey), f.z) * CFrame.Angles(0, f.yaw, 0)
end

local function add(model, props)
	local p = api.part(props, model)
	return p
end

-- a world-aligned box in plot space (rect + y span), for walls, slabs and rails
local function slabBox(model, plot, name, x0, x1, z0, z1, y0, y1, props)
	local p = table.clone(props or {})
	p.Name = name
	p.Size = Vector3.new(math.max(0.2, x1 - x0), math.max(0.2, y1 - y0), math.max(0.2, z1 - z0))
	p.CFrame = plot.pivot * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	return add(model, p)
end

-- one wall on a room side: `kind` "glass", or a door width (6, 8, 14) centred on the side
local WALL_T = 0.4
local function wallSide(model, plot, r, side, kind, y0, h, glassProps, partProps)
	local props = (kind == "glass") and glassProps or partProps
	local name = (kind == "glass") and "Wall" or "Partition"
	local door = (type(kind) == "number") and kind or nil
	local alongX = (side == "pz" or side == "nz")
	local lo, hi = alongX and r.x0 or r.z0, alongX and r.x1 or r.z1
	local at = (side == "pz" and r.z1 - WALL_T / 2) or (side == "nz" and r.z0 + WALL_T / 2)
		or (side == "px" and r.x1 - WALL_T / 2) or (r.x0 + WALL_T / 2)
	local spans = { { lo, hi } }
	if door then
		local mid = (lo + hi) / 2
		spans = { { lo, mid - door / 2 }, { mid + door / 2, hi } }
	end
	for _, sp in ipairs(spans) do
		if sp[2] - sp[1] > 0.2 then
			if alongX then
				slabBox(model, plot, name, sp[1], sp[2], at - WALL_T / 2, at + WALL_T / 2, y0, y0 + h, props)
			else
				slabBox(model, plot, name, at - WALL_T / 2, at + WALL_T / 2, sp[1], sp[2], y0, y0 + h, props)
			end
		end
	end
end

-- the old HQ level (1-5) this level stands for: recruit tiers, homes, the journey
function Wafers.stage(level)
	return P.stage(level)   -- v8 (13 Oct): one table, WaferPlan.STAGE_AT (StaffStats caps read it too)
end

-- ---------------------------------------------------------------- state
--[[ the campus grounds were laid out for the old campus: anything taller than the paving inside the
tower's footprint (the ground section, with a margin, and the entrance canopy) goes, and so do the
spurs. Once per plot. ]]
local function clearFootprint(plot)
	local grounds = plot.folder and plot.folder:FindFirstChild("Grounds")
	if not (grounds and plot.pivot) then return end
	local A = T.SECTIONS[1]
	local function inside(pos)
		local lp = plot.pivot:PointToObjectSpace(pos)
		if math.abs(lp.X) <= A.hx + 3 and lp.Z >= A.zb - 3 and lp.Z <= A.zf + 3 then return true end
		return math.abs(lp.X) <= 13 and lp.Z >= A.zf and lp.Z <= A.zf + 12      -- the entrance canopy
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

--[[ THE SERVERS RACKS (13 Oct 2026). The imported rack (ServerRack: the wafer crown,
	walnut slats, rails and patch cables, art/blender/rack_v6.py) where the place has
	the mesh; the plain box and its pulsing light strip where it does not (the TEST
	experience, a place without the import). Same four slots either way. ]]
local ServerRack = require(RS:WaitForChild("ServerRack"))
local function serverRacks(model, base, rm)
	local lib = RS:FindFirstChild("SVMeshes")
	local tpl = lib and lib:FindFirstChild(ServerRack.MESH)
	local mesh = tpl and (tpl:IsA("MeshPart") and tpl or tpl:FindFirstChildWhichIsA("MeshPart", true))
	if mesh and not ServerRack.fits(mesh.Size) then mesh = nil end     -- a wrong import: keep the boxes
	for _, x in ipairs(ServerRack.XS) do
		if mesh then
			local mp = mesh:Clone()
			mp.Name = ServerRack.NAME
			mp.Anchored = true
			mp.CanCollide = true
			mp.CanTouch = false
			mp.CastShadow = false
			mp.Color = Color3.new(1, 1, 1)       -- vertex colour shows as authored
			mp.CFrame = base * ServerRack.pose(x, rm, mp.Size.Y)
			mp.Parent = model
		else
			add(model, { Name = "Rack", Size = ServerRack.SLOT, CFrame = base * CFrame.new(x, 3.5, rm + ServerRack.BACK),
				Color = Color3.fromRGB(38, 42, 52), Material = Enum.Material.Metal, CastShadow = false })
			local lit = add(model, { Name = "RackLight", Size = Vector3.new(2.2, 0.2, 0.1), CFrame = base * CFrame.new(x, 5.6, rm + 1.85),
				Color = Color3.fromRGB(120, 240, 200), Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, CastShadow = false })
			CollectionService:AddTag(lit, "SVPulse")
			lit:SetAttribute("Hz", 0.35)
			lit:SetAttribute("Depth", 0.30)
		end
	end
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
	local body = add(model, {
		Name = "Station",
		Size = Vector3.new(3.2, 4.4, 1.8),
		CFrame = anchor * CFrame.new(-r.w / 2 + 3, SLAB + 2.2, -r.d / 2 + 3),
		Color = Wafers.TINT[dept] or PAPER,
		Material = Enum.Material.SmoothPlastic,
		CastShadow = false,
	})
	add(model, {
		Name = "StationGlow",
		Size = Vector3.new(2.4, 0.3, 1.2),
		CFrame = anchor * CFrame.new(-r.w / 2 + 3, SLAB + 4.5, -r.d / 2 + 3),
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

-- the room's furniture in its own frame: origin at the room centre on the floor, +Z out to the facade
local function furnish(model, anchor, dept, r)
	local FK = api.FK
	local seats = {}
	local zOut = r.d / 2 - 4            -- the desk row near the window
	local function seatAt(x, z, faceOut)
		local pos = (anchor * CFrame.new(x, 2.4, z)).Position
		local look = (anchor * CFrame.new(x, 2.4, z + (faceOut and 5 or -5))).Position
		table.insert(seats, CFrame.lookAt(pos, look))
	end
	if not FK then return seats end
	if dept == "eng" or dept == "labs" or dept == "lobby" then
		local xs = (dept == "lobby") and { -r.w / 4, r.w / 4 } or { -5.5, 5.5 }
		for _, x in ipairs(xs) do
			pcall(FK.workstation, anchor, x, zOut, 0, model, { yaw = 180, accent = Wafers.TINT[dept] })
			seatAt(x - 0.3, zOut - 2.6, true)
		end
		if dept == "lobby" and FK.has and FK.has("loungeSofa") then
			pcall(FK.onFloor, "loungeSofa", anchor, 0, -r.d / 2 + 5, 0, model, { yaw = 0 })
		end
	elseif dept == "studio" then
		pcall(FK.onFloor, "tableCross", anchor, 0, 0, 0, model)
		pcall(FK.onFloor, "chairModernCushion", anchor, -3.7, 0.4, 0, model, { yaw = 90 })
		pcall(FK.onFloor, "chairModernCushion", anchor, 3.7, 0.4, 0, model, { yaw = -90 })
		for _, x in ipairs({ -3.7, 3.7 }) do
			table.insert(seats, CFrame.lookAt((anchor * CFrame.new(x, 2.4, 0.4)).Position, (anchor * CFrame.new(0, 2.4, 0.4)).Position))
		end
	elseif dept == "cafe" then
		pcall(FK.onFloor, "tableRound", anchor, 0, 0, 0, model, { canCollide = true })
		for _, o in ipairs({ { 0, 2.6, 180 }, { 0, -2.6, 0 }, { 2.4, 0, -90 }, { -2.4, 0, 90 } }) do
			pcall(FK.onFloor, "chairModernCushion", anchor, o[1], o[2], 0, model, { yaw = o[3] })
			table.insert(seats, CFrame.lookAt((anchor * CFrame.new(o[1], 2.4, o[2])).Position, (anchor * CFrame.new(0, 2.4, 0)).Position))
		end
	elseif dept == "servers" then
		serverRacks(model, anchor, r.d / 2 - 3.5)       -- ServerRack.pose puts the racks at rm + 3: against the facade
		for _, x in ipairs({ -9, 9 }) do serverFan(model, anchor * CFrame.new(x, 6.2, r.d / 2 - 0.4), 3.0, 170) end
	elseif dept == "board" then
		pcall(FK.onFloor, "tableCross", anchor, -2.2, 0, 0, model)
		pcall(FK.onFloor, "tableCross", anchor, 2.2, 0, 0, model)
	end
	return seats
end

-- the department's name sign, inside, over the door to the centre hall (or the corner's first door)
local function sign(model, plot, r, s, dept)
	local inward = (r.sides.nz == 8 and "nz") or (r.sides.pz == 8 and "pz") or (r.sides.px == 8 and "px")
		or (r.sides.nx == 8 and "nx") or ((r.sides.nz ~= "glass") and "nz") or "pz"
	local y = T.floorY(s) + T.storeyH(s) - SLAB - 2.6
	local cfs = {
		pz = CFrame.new(r.cx, y, r.z1 - 0.6) * CFrame.Angles(0, math.pi, 0), nz = CFrame.new(r.cx, y, r.z0 + 0.6),
		px = CFrame.new(r.x1 - 0.6, y, r.cz) * CFrame.Angles(0, -math.pi / 2, 0), nx = CFrame.new(r.x0 + 0.6, y, r.cz) * CFrame.Angles(0, math.pi / 2, 0),
	}
	local p = add(model, { Name = "DeptSign", Size = Vector3.new(12, 1.6, 0.2), CFrame = plot.pivot * cfs[inward],
		Color = CHARCOAL, CanCollide = false, CanQuery = false, CastShadow = false })
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
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

-- columns from a garden storey's deck up to the section above, with that section's first room
local function deckColumns(model, plot, s)
	local deckS = s - 1
	if not T.DECKS[deckS] then return end
	local sec = T.above(deckS)
	if not sec then return end
	local y0, y1 = T.floorY(deckS), T.floorY(s) - SLAB
	for _, x in ipairs({ -sec.hx + 1.5, sec.hx - 1.5 }) do
		for _, z in ipairs({ sec.zb + 1.5, sec.zf - 1.5 }) do
			slabBox(model, plot, "Column", x - 1.5, x + 1.5, z - 1.5, z + 1.5, y0, y1, { Color = PAPER, Material = Enum.Material.SmoothPlastic })
		end
	end
end

local function buildSegment(plot, L, dept, model)
	local pc = P.PIECES[L]
	local r = T.room(pc.storey, pc.seg)
	local y = T.floorY(pc.storey)
	local h = T.storeyH(pc.storey) - SLAB
	local tint = Wafers.TINT[dept] or PAPER
	local glassProps = { Color = facadeTint(dept), Material = Enum.Material.Glass, Transparency = 0.45, CastShadow = false }
	local partProps = { Color = PAPER, Material = Enum.Material.SmoothPlastic }
	local parts = {}
	table.insert(parts, slabBox(model, plot, "Floor", r.x0, r.x1, r.z0, r.z1, y - SLAB, y, { Color = PAPER, Material = Enum.Material.SmoothPlastic }))
	table.insert(parts, slabBox(model, plot, "Ceiling", r.x0, r.x1, r.z0, r.z1, y + h - 0.4, y + h,
		{ Color = Color3.fromRGB(250, 248, 242), Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false }))
	local lobby = (pc.storey == 0 and pc.seg == 1)
	for _, side in ipairs({ "px", "nx", "pz", "nz" }) do
		local kind = r.sides[side]
		if lobby and side == "pz" then kind = 14 end           -- the entrance
		wallSide(model, plot, r, side, kind, y, h, glassProps, partProps)
		if r.sides[side] == "glass" and dept ~= "lobby" then  -- the department band on the facade's slab edge
			local o = 0.55
			local b = { pz = { r.x0, r.x1, r.z1, r.z1 + o }, nz = { r.x0, r.x1, r.z0 - o, r.z0 },
				px = { r.x1, r.x1 + o, r.z0, r.z1 }, nx = { r.x0 - o, r.x0, r.z0, r.z1 } }
			local q = b[side]
			slabBox(model, plot, "DeptBand", q[1], q[2], q[3], q[4], y - SLAB - 0.05, y - SLAB + 2.0,
				{ Color = tint, Material = Enum.Material.SmoothPlastic, CastShadow = false, CanQuery = false, CanCollide = false })
		end
	end
	if lobby then   -- the entrance canopy over the forecourt
		slabBox(model, plot, "Canopy", r.cx - 11, r.cx + 11, r.z1, r.z1 + 10, y + 10, y + 11,
			{ Color = PAPER, Material = Enum.Material.SmoothPlastic, CanCollide = false })
	end
	if pc.seg == 1 then deckColumns(model, plot, pc.storey) end
	local anchor = Wafers.anchor(plot, L)
	local seats = furnish(model, anchor, dept, r)
	if pc.seg == 3 then station(model, anchor, dept, r, plot, L) end
	local label = (dept ~= "lobby") and sign(model, plot, r, pc.storey, dept) or nil
	return parts, {}, seats, label
end

-- ---------------------------------------------------------------- gardens, roof, pavilions, crown
local GREEN = Color3.fromRGB(118, 160, 92)
local WOOD = Color3.fromRGB(158, 108, 66)

-- a garden storey or the roof: the deck over the section below, glass rails, planters
local function buildGarden(plot, L, model)
	local pc = P.PIECES[L]
	local r = T.deck(pc.storey)
	local y = T.floorY(pc.storey)
	slabBox(model, plot, "Deck", r.x0, r.x1, r.z0, r.z1, y - SLAB, y, { Color = Color3.fromRGB(214, 206, 190), Material = Enum.Material.SmoothPlastic })
	local rail = { Color = Color3.fromRGB(200, 222, 232), Material = Enum.Material.Glass, Transparency = 0.4, CastShadow = false }
	slabBox(model, plot, "Rail", r.x0, r.x1, r.z1 - 0.3, r.z1, y, y + 3.2, rail)
	slabBox(model, plot, "Rail", r.x0, r.x1, r.z0, r.z0 + 0.3, y, y + 3.2, rail)
	slabBox(model, plot, "Rail", r.x1 - 0.3, r.x1, r.z0, r.z1, y, y + 3.2, rail)
	slabBox(model, plot, "Rail", r.x0, r.x0 + 0.3, r.z0, r.z1, y, y + 3.2, rail)
	for x = r.x0 + 6, r.x1 - 6, 10 do
		for _, z in ipairs({ r.z1 - 2.2, r.z0 + 2.2 }) do
			slabBox(model, plot, "Planter", x - 2, x + 2, z - 0.9, z + 0.9, y, y + 1.4, { Color = WOOD, Material = Enum.Material.SmoothPlastic })
			slabBox(model, plot, "Plants", x - 1.8, x + 1.8, z - 0.7, z + 0.7, y + 1.4, y + 2.0, { Color = GREEN, Material = Enum.Material.SmoothPlastic, CanCollide = false })
		end
	end
end

local function buildPavilion(plot, L, model)
	local pc = P.PIECES[L]
	local r = T.pavilion(pc.seg)
	local y = T.floorY(pc.storey)
	local glass = { Color = Color3.fromRGB(190, 214, 226), Material = Enum.Material.Glass, Transparency = 0.45, CastShadow = false }
	local h = 10
	slabBox(model, plot, "Wall", r.x0, r.x1, r.z0, r.z0 + 0.4, y, y + h, glass)
	slabBox(model, plot, "Wall", r.x0, r.x1, r.z1 - 0.4, r.z1, y, y + h, glass)
	slabBox(model, plot, "Wall", r.x0, r.x0 + 0.4, r.z0, r.z1, y, y + h, glass)
	slabBox(model, plot, "Wall", r.x1 - 0.4, r.x1, r.z0, (r.z0 + r.z1) / 2 - 3, y, y + h, glass)   -- a door on +x
	slabBox(model, plot, "Wall", r.x1 - 0.4, r.x1, (r.z0 + r.z1) / 2 + 3, r.z1, y, y + h, glass)
	slabBox(model, plot, "PavilionRoof", r.x0 - 1, r.x1 + 1, r.z0 - 1, r.z1 + 1, y + h, y + h + 0.8, { Color = PAPER, Material = Enum.Material.SmoothPlastic })
end

local function buildCrown(plot, L, model)
	local pc = P.PIECES[L]
	local l = T.lantern()
	local roofY = T.floorY(14)
	if pc.kind == "lantern" then
		slabBox(model, plot, "Lantern", l.x0, l.x1, l.z0, l.z1, roofY, roofY + 14,
			{ Color = Color3.fromRGB(190, 214, 226), Material = Enum.Material.Glass, Transparency = 0.35, CastShadow = false })
	elseif pc.kind == "halo" then
		local sec = T.SECTIONS[#T.SECTIONS]
		local hy = roofY + 4
		local band = { Color = GOLD, Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false }
		slabBox(model, plot, "Halo", -sec.hx, sec.hx, sec.zf - 0.6, sec.zf, hy, hy + 1.2, band)
		slabBox(model, plot, "Halo", -sec.hx, sec.hx, sec.zb, sec.zb + 0.6, hy, hy + 1.2, band)
		slabBox(model, plot, "Halo", sec.hx - 0.6, sec.hx, sec.zb, sec.zf, hy, hy + 1.2, band)
		slabBox(model, plot, "Halo", -sec.hx, -sec.hx + 0.6, sec.zb, sec.zf, hy, hy + 1.2, band)
	else -- mast
		local cx, cz = (T.SHAFT.x0 + T.SHAFT.x1) / 2, (T.SHAFT.z0 + T.SHAFT.z1) / 2
		slabBox(model, plot, "Mast", cx - 0.6, cx + 0.6, cz - 0.6, cz + 0.6, roofY + 14, roofY + 34, { Color = CHARCOAL, Material = Enum.Material.SmoothPlastic })
	end
end

-- ---------------------------------------------------------------- the lift
-- can the lift let you off on storey s? (the landing is part of the core; any built piece there will do)
local function landable(st, s)
	for L = 2, st.level do
		local pc = P.PIECES[L]
		if pc.storey == s and pc.kind ~= "halo" and pc.kind ~= "lantern" and pc.kind ~= "mast" then return true end
	end
	return false
end

local function liftButton(plot, st, s)
	local HQ = api.HQFloors
	local y = T.floorY(s)
	local bx = (T.SHAFT.x0 + T.SHAFT.x1) / 2 + 3.2
	local btn = add(st.folder, { Name = "LiftCall", Size = Vector3.new(1.2, 2, 0.4),
		CFrame = plot.pivot * CFrame.new(bx, y + 4.2, T.SHAFT.z1 + 0.2), Color = CHARCOAL, CanCollide = false, CastShadow = false })
	table.insert(st.core, btn)
	table.insert(st.core, add(st.folder, { Name = "LiftCallLit", Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.5, 0.5),
		CFrame = btn.CFrame * CFrame.new(0, 0.3, 0.25), Color = GOLD, Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, CastShadow = false }))
	local id = (s == 0) and "L" or ("F" .. s)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Take the lift"
	pp.ObjectText = T.label(s)
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 11
	pp.RequiresLineOfSight = false
	pp.Parent = btn
	pp.Triggered:Connect(function(player)
		if HQ and HQ.menu then HQ.menu(player, plot.index, id) end
	end)
	local stand = CFrame.lookAt((plot.pivot * CFrame.new(T.STAND.x, y + 0.1, T.STAND.z)).Position,
		(plot.pivot * CFrame.new(T.STAND.x, y + 0.1, T.SHAFT.z1)).Position)
	table.insert(st.stops, { id = id, name = s == 0 and "LOBBY" or tostring(s), sub = T.label(s), stand = stand })
end

local function topStorey(st)
	local top = 0
	for L = 2, st.level do
		local pc = P.PIECES[L]
		if pc.kind ~= "halo" and pc.kind ~= "lantern" and pc.kind ~= "mast" then top = math.max(top, pc.storey) end
	end
	return top
end

-- (re)build the shaft, each storey's landing hall floor and its lift stop
local function buildCore(plot)
	local st = stateOf(plot)
	for _, p in ipairs(st.core) do if p.Parent then p:Destroy() end end
	st.core, st.stops = {}, {}
	if st.level < 2 then
		if api.HQFloors and api.HQFloors.register then api.HQFloors.register(plot.index, plot, {}) end
		return
	end
	local top = topStorey(st)
	local S = T.SHAFT
	local shaft = { Color = Color3.fromRGB(190, 214, 226), Material = Enum.Material.Glass, Transparency = 0.45, CastShadow = false }
	for s = 0, top do
		local y, h = T.floorY(s), T.storeyH(s)
		-- the shaft's 4 walls this storey (a 6-wide door gap on +Z, closed by the cab in 1b)
		for _, w in ipairs({ { S.x0, S.x1, S.z0, S.z0 + 0.4 }, { S.x0, S.x0 + 0.4, S.z0, S.z1 }, { S.x1 - 0.4, S.x1, S.z0, S.z1 },
			{ S.x0, (S.x0 + S.x1) / 2 - 3, S.z1 - 0.4, S.z1 }, { (S.x0 + S.x1) / 2 + 3, S.x1, S.z1 - 0.4, S.z1 } }) do
			table.insert(st.core, slabBox(st.folder, plot, "LiftShaft", w[1], w[2], w[3], w[4], y - SLAB, y + h - SLAB, shaft))
		end
		if not T.DECKS[s] and s < 14 then   -- the landing hall's floor (gardens and the roof have their decks)
			local c = T.centre(s)
			table.insert(st.core, slabBox(st.folder, plot, "Floor", c.x0, c.x1, c.z0, c.z1, y - SLAB, y,
				{ Color = PAPER, Material = Enum.Material.SmoothPlastic }))
		end
		if landable(st, s) or s == 0 then liftButton(plot, st, s) end
	end
	if api.HQFloors and api.HQFloors.register then api.HQFloors.register(plot.index, plot, st.stops) end
end

--[[ v9 (14 Oct, HQ tower 1a): the garage's shell and dress go away once the tower has a lobby
	(level 2) and come back with level 1 (a spin-off). The WRITE CODE desk, the hire pad and the
	build pad stay: they stand in the ground storey's centre hall (TowerPlan's spots test). The
	animated "garage folds into the lobby" moment is part 1c. ]]
local GARAGE_KEEP = { -- measured live 14 Oct: the working parts (prompts, the desk set, the pads, the spawn)
	Laptop = true, Desk = true, Chair = true, Monitor2 = true, Keyboard = true, HQPad = true, HirePad = true, Spawn = true,
}
function Wafers.garage(plot, show)
	local g = plot.folder and plot.folder:FindFirstChild("Garage")
	local stash = plot.garageStash
	if show then
		if stash then for _, c in ipairs(stash:GetChildren()) do c.Parent = g end end
		return
	end
	if not g then return end
	if not stash then
		stash = Instance.new("Folder")
		stash.Name = "GarageStash_" .. tostring(plot.index)
		stash.Parent = game:GetService("ServerStorage")
		plot.garageStash = stash
	end
	for _, c in ipairs(g:GetChildren()) do
		if not GARAGE_KEEP[c.Name] then c.Parent = stash end
	end
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
		buildGarden(plot, L, model)
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
	Wafers.garage(plot, st.level < 2)
end

-- everything back to the garage (a spin-off, or the owner leaving)
function Wafers.clear(plot)
	local st = plot.wafer
	if not st then return end
	for _, c in ipairs(st.folder:GetChildren()) do c:Destroy() end
	st.level, st.depts, st.pieces, st.core, st.stops = 1, {}, {}, {}, {}
	if api and api.HQFloors and api.HQFloors.register then api.HQFloors.register(plot.index, plot, {}) end
	Wafers.garage(plot, true)
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
