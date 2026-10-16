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
local GarageDress = require(SSS:WaitForChild("GarageDress"))
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")

local P = require(SSS:WaitForChild("WaferPlan"))
local T = require(RS:WaitForChild("TowerPlan"))   -- v9 (14 Oct): the tower's geometry (rectangular, 24/18-stud storeys)
local TF = require(RS:WaitForChild("TowerFinish"))       -- 1d: the three finishes
local TowerArt = require(SSS:WaitForChild("TowerArt"))   -- 1d: the art, from parts
local LiftPlan = require(RS:WaitForChild("LiftPlan")).with(T)   -- v9.3 (15 Oct, 1b): the lift's rules
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
local WOOD = Color3.fromRGB(158, 108, 66)
local CHARCOAL = Color3.fromRGB(46, 50, 58)
local GOLD = Color3.fromRGB(255, 194, 61)


--[[ THE FACADE (1d, 16 Oct). v7 pulled each department's tint most of the way to one glass colour
	because the stacked tints read as coloured static from the plaza. 1d finishes the job: the facade is
	the finish's one glass colour (TowerFinish); the department shows on its sign and inside. ]]
local function finOf(plot) return TF.get(Wafers.pathOf(plot)) end

--[[ the company's name on the tower (the entrance sign, the crown plate): every player sees it, so it is
	filtered for BROADCAST (the owner-only filter is not enough), once per name, off the build thread. ]]
local nameCache = {}
function Wafers.companyName(plot)
	local owner = plot and plot.owner and Players:GetPlayerByUserId(plot.owner)
	local raw = owner and owner:GetAttribute("Company")
	if type(raw) ~= "string" or raw == "" then return "YOUR STARTUP" end
	local key = plot.owner .. ":" .. raw
	if nameCache[key] == nil then
		nameCache[key] = false
		task.spawn(function()
			local ok, res = pcall(function()
				return TextService:FilterStringAsync(raw, plot.owner):GetNonChatStringForBroadcastAsync()
			end)
			nameCache[key] = (ok and type(res) == "string" and res ~= "") and string.upper(res) or "YOUR STARTUP"
		end)
	end
	return nameCache[key] or nil   -- nil while the filter runs: callers keep what the sign says now
end

--[[ the name signs follow a rename. A rename does not recompute income (refreshSigns' caller), so the
	plots that carry a name sign are checked every 2 s (live 16 Oct: 12 s after a rename the sign still
	showed the old name). Weak keys: a plot that goes away is forgotten. ]]
local namedPlots = setmetatable({}, { __mode = "k" })
local function refreshNames(plot)
	local st = plot and plot.wafer
	if not st then return end
	local name = Wafers.companyName(plot)
	if not name then return end
	for _, tl in ipairs(st.names or {}) do
		if tl.Parent and tl.Text ~= name then tl.Text = name end
	end
end
local function nameSign(plot, tl)
	tl.Text = Wafers.companyName(plot) or "YOUR STARTUP"
	local st = plot.wafer   -- built: the tower's state exists (stateOf is defined further down)
	st.names = st.names or {}
	table.insert(st.names, tl)
	namedPlots[plot] = true
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
local PATHS = { ["W_"] = "Glass", ["T_"] = "Timber", ["D_"] = "Neon" }   -- v9: the finishes (spec §3)

function Wafers.pathOf(plot)
	local v = plot and plot.hqPath
	return (v and PATHS[v]) and v or "W_"
end

function Wafers.pathName(prefix)
	return PATHS[prefix] or "Glass"
end

Wafers.PATHS = PATHS


function Wafers.floorY(s) return T.floorY(s) end

-- DECOR in the tower (level 2+): the floors decor may stand on, plot-local rects; nil before the tower
function Wafers.decorRects(plot)
	local st = plot.wafer
	if not st or st.level < 2 then return nil end
	return T.decorRects(P.PIECES, st.level)
end

--[[ may a decor footprint (plot-local x0..x1, z0..z1) stand here? The plan's rule (TowerPlan.decorOk:
	a lobby-storey floor, clear of the landing, the garage spots and the doorways), then nothing the
	tower itself built may be in the way: furniture, racks, the station, the shaft, the lift button. ]]
local CLEAR_OF = { Floor = true, Ceiling = true, Deck = true, RoofBand = true, DeptBand = true, LobbyCanopy = true, RoomTone = true }
function Wafers.decorOk(plot, b)
	local st = plot.wafer
	if not st or st.level < 2 then return nil end
	if not T.decorOk(P.PIECES, st.level, b) then return false end
	-- footprint against every part the tower built on the lobby storey, between the floor and head height.
	-- Not a spatial query: the room furniture is CanQuery false (measured 14 Oct: a plant went onto the
	-- lobby sofa), so compare boxes, as FurnitureKit.blocked does for the old rooms
	local y0 = T.floorY(0)
	local inv = plot.pivot:Inverse()
	for _, m in ipairs(st.folder:GetChildren()) do
		local lobbyStorey = (m:GetAttribute("Storey") == 0) or m:IsA("BasePart")   -- a room piece, or a core part
		if lobbyStorey then
			local parts = m:IsA("BasePart") and { m } or m:GetDescendants()
			for _, part in ipairs(parts) do
				if part:IsA("BasePart") and not CLEAR_OF[part.Name] and part.Transparency < 1 then
					local cf = inv * part.CFrame
					local sx, sy, sz = part.Size.X / 2, part.Size.Y / 2, part.Size.Z / 2
					local r = cf - cf.Position
					local hx = math.abs(r.XVector.X) * sx + math.abs(r.YVector.X) * sy + math.abs(r.ZVector.X) * sz
					local hy = math.abs(r.XVector.Y) * sx + math.abs(r.YVector.Y) * sy + math.abs(r.ZVector.Y) * sz
					local hz = math.abs(r.XVector.Z) * sx + math.abs(r.YVector.Z) * sy + math.abs(r.ZVector.Z) * sz
					local p = cf.Position
					if p.Y - hy < y0 + 3 and p.Y + hy > y0 + 0.2
						and p.X - hx < b.x1 - 0.05 and p.X + hx > b.x0 + 0.05 and p.Z - hz < b.z1 - 0.05 and p.Z + hz > b.z0 + 0.05 then
						return false
					end
				end
			end
		end
	end
	return true
end
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
local WALL_T = T.WALL_T
local function wallSide(model, plot, r, side, kind, y0, h, glassProps, partProps, cut)
	local glassy = (kind == "glass" or kind == "glassdoor")   -- glassdoor: a terrace door in the facade
	local props = glassy and glassProps or partProps
	local name = glassy and "Wall" or "Partition"
	local door = (type(kind) == "number") and kind or ((kind == "glassdoor") and 6) or nil
	local alongX = (side == "pz" or side == "nz")
	local lo, hi = alongX and r.x0 or r.z0, alongX and r.x1 or r.z1
	if glassy and cut then lo, hi = lo + cut.lo, hi - cut.hi end   -- 1d: stop short of a rounded corner
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
	local A = T.rect(0)   -- the podium, the widest storey
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
		plot.wafer = { level = 1, depts = {}, pieces = {}, folder = folder, core = {}, stops = {}, edges = {}, names = {} }
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
local function serverRacks(model, base, rm, doorway)
	local lib = RS:FindFirstChild("SVMeshes")
	local tpl = lib and lib:FindFirstChild(ServerRack.MESH)
	local mesh = tpl and (tpl:IsA("MeshPart") and tpl or tpl:FindFirstChildWhichIsA("MeshPart", true))
	if mesh and not ServerRack.fits(mesh.Size) then mesh = nil end     -- a wrong import: keep the boxes
	for _, x in ipairs(ServerRack.XS) do
		if doorway and math.abs(x) < 4 then continue end   -- the middle two make way for a terrace door
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
		-- the racks' backs on the glass band, the fans just inside the glass (final review I1: the backs
		-- stood 0.6 outside the facade, rm had been reused as an offset from it)
		serverRacks(model, anchor, ServerRack.midlineFor(T.inner(r).z), r.terraceDoor ~= nil)
		for _, x in ipairs({ -9, 9 }) do serverFan(model, anchor * CFrame.new(x, 6.2, T.fanZ(r)), 3.0, 170) end
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

-- 1c: the garage's TV and a framed photo of the garage ("WHERE IT STARTED") on the lobby room's
-- hall-side wall (TowerPlan.WALL_ART), facing the desk. Plain parts and a drawn photo; the art is 1d.
local function lobbyArt(model, plot, r, y)
	local A = T.WALL_ART
	local wallZ = r.z0                         -- the hall-side face of the lobby room's back wall (1d, 1c M2: flush)
	local p = A.photo
	local frame = slabBox(model, plot, "PhotoFrame", p.x - p.w / 2, p.x + p.w / 2, wallZ - 0.3, wallZ, y + p.y0, y + p.y1,
		{ Color = WOOD, Material = Enum.Material.SmoothPlastic, CanCollide = false })
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front               -- plot -Z: into the hall
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud, sg.LightInfluence = 40, 0
	sg.Parent = frame
	local function box(color, x, yy, w, h)
		local f = Instance.new("Frame")
		f.BackgroundColor3, f.BorderSizePixel = color, 0
		f.Position, f.Size = UDim2.fromScale(x, yy), UDim2.fromScale(w, h)
		f.Parent = sg
		return f
	end
	box(Color3.fromRGB(250, 246, 236), 0.04, 0.05, 0.92, 0.9)       -- the mat
	box(Color3.fromRGB(150, 196, 236), 0.1, 0.1, 0.8, 0.5)          -- sky
	box(Color3.fromRGB(110, 168, 90), 0.1, 0.6, 0.8, 0.1)           -- grass
	box(Color3.fromRGB(218, 208, 188), 0.3, 0.3, 0.4, 0.32)         -- the garage
	box(Color3.fromRGB(115, 107, 102), 0.27, 0.26, 0.46, 0.06)      -- its roof
	box(Color3.fromRGB(184, 189, 199), 0.4, 0.4, 0.2, 0.22)         -- the roll-up door
	local cap = Instance.new("TextLabel")
	cap.BackgroundTransparency, cap.TextScaled, cap.Font = 1, true, Enum.Font.FredokaOne
	cap.TextColor3, cap.Text = Color3.fromRGB(20, 22, 30), "WHERE IT STARTED"
	cap.Position, cap.Size = UDim2.fromScale(0.1, 0.74), UDim2.fromScale(0.8, 0.16)
	cap.Parent = sg
	local tv = A.tv
	GarageDress.tv(model, plot.pivot * CFrame.new(tv.x, y, wallZ), tv.w, tv.y0, tv.y1)
end

local function buildSegment(plot, L, dept, model)
	local pc = P.PIECES[L]
	local r = T.room(pc.storey, pc.seg)
	local y = T.floorY(pc.storey)
	local h = T.storeyH(pc.storey) - SLAB
	local fin = finOf(plot)
	local glassProps = { Color = TF.color(fin.glass), Material = Enum.Material.Glass, Transparency = 0.45, CastShadow = false }
	local cuts = T.cuts(pc.storey, pc.seg)
	local partProps = { Color = PAPER, Material = Enum.Material.SmoothPlastic }
	local parts = {}
	if not T.DECKS[pc.storey - 1] then   -- above a garden the deck is the floor (two slabs in one place would flicker)
		table.insert(parts, slabBox(model, plot, "Floor", r.x0, r.x1, r.z0, r.z1, y - SLAB, y, { Color = PAPER, Material = Enum.Material.SmoothPlastic }))
	end
	table.insert(parts, slabBox(model, plot, "Ceiling", r.x0, r.x1, r.z0, r.z1, y + h - 0.4, y + h,
		{ Color = Color3.fromRGB(250, 248, 242), Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false }))
	local lobby = (pc.storey == 0 and pc.seg == 1)
	for _, side in ipairs({ "px", "nx", "pz", "nz" }) do
		local kind = r.sides[side]
		if r.entrance and r.entrance.side == side then kind = r.entrance.width end   -- the lobby's entrance
		if r.terraceDoor == side then kind = "glassdoor" end                       -- the door onto the terrace
		wallSide(model, plot, r, side, kind, y, h, glassProps, partProps, cuts[side])
	end
	TowerArt.facade(model, plot, pc.storey, pc.seg, y, h, fin, glassProps)   -- 1d: fins, band, line, corners
	TowerArt.ceilingStrip(model, plot, r, y, h, T.darkRoom(L))                 -- 1d: the night's room light
	if pc.storey == 0 then   -- the podium (the mock): a white roof band past the glass, warm wood columns along the front
		local band = { Color = TF.color(fin.band), Material = Enum.Material.SmoothPlastic, CastShadow = false }
		local top, o = y + h, 1.5
		local b = { pz = { r.x0, r.x1, r.z1 - T.WALL_T, r.z1 + o }, nz = { r.x0, r.x1, r.z0 - o, r.z0 + T.WALL_T },
			px = { r.x1 - T.WALL_T, r.x1 + o, r.z0, r.z1 }, nx = { r.x0 - o, r.x0 + T.WALL_T, r.z0, r.z1 } }
		for side, q in pairs(b) do
			if r.sides[side] == "glass" then
				slabBox(model, plot, "RoofBand", q[1], q[2], q[3], q[4], top - 1.2, top + 0.6, band)
			end
		end
		if r.sides.pz == "glass" then
			local wood = { Color = TF.color(fin.column), Material = Enum.Material.SmoothPlastic }
			for x = r.x0 + 3, r.x1 - 3, 6 do
				if not (lobby and math.abs(x - r.cx) < 8) then   -- keep the doorway clear
					slabBox(model, plot, "Column", x - 0.4, x + 0.4, r.z1 + 0.6, r.z1 + 1.4, y, top - 1.2, wood)
				end
			end
		end
	end
	if lobby then   -- the entrance canopy over the forecourt
		slabBox(model, plot, "LobbyCanopy", r.cx - 11, r.cx + 11, r.z1, r.z1 + 10, y + 10, y + 11,
			{ Color = TF.color(fin.band), Material = Enum.Material.SmoothPlastic, CanCollide = false })
		lobbyArt(model, plot, r, y)
		nameSign(plot, TowerArt.entrance(model, plot, r, y, fin))   -- 1d: frames, the soffit light, the name
	end
	if pc.storey == 0 then TowerArt.podium(model, plot, r, y, h, fin) end   -- 1d: planters on the podium roof
	local anchor = Wafers.anchor(plot, L)
	local seats = furnish(model, anchor, dept, r)
	if pc.seg == 3 then station(model, anchor, dept, r, plot, L) end
	local label = (dept ~= "lobby") and sign(model, plot, r, pc.storey, dept) or nil
	return parts, {}, seats, label
end

-- ---------------------------------------------------------------- gardens, roof, pavilions, crown

-- a garden storey or the roof: the deck over the section below, glass rails, planters
local function buildGarden(plot, L, model)
	local pc = P.PIECES[L]
	local r = T.deck(pc.storey)
	local y = T.floorY(pc.storey)
	for _, q in ipairs(T.deckRects(pc.storey)) do   -- 1b: a hole over the shaft, the cab rides through
		slabBox(model, plot, "Deck", q.x0, q.x1, q.z0, q.z1, y - SLAB, y, { Color = Color3.fromRGB(214, 206, 190), Material = Enum.Material.SmoothPlastic })
	end
	local fin = finOf(plot)
	local rail = { Color = TF.color(fin.glass), Material = Enum.Material.Glass, Transparency = 0.4, CastShadow = false }
	local hand = { Color = TF.color(fin.band), Material = Enum.Material.SmoothPlastic, CastShadow = false }
	-- 1d: the main strips get the terrace kit (its planter edge carries the rail); the other edges keep a rail
	local kits = {}
	if T.DECKS[pc.storey] then
		for side, t in pairs(T.terraces(pc.storey)) do
			if (side == "front" or side == "back") and t.depth >= 4 then kits[side] = t end
		end
	end
	local edges = { pz = { r.x0, r.x1, r.z1 - 0.3, r.z1 }, nz = { r.x0, r.x1, r.z0, r.z0 + 0.3 },
		px = { r.x1 - 0.3, r.x1, r.z0, r.z1 }, nx = { r.x0, r.x0 + 0.3, r.z0, r.z1 } }
	for side, q in pairs(edges) do
		if not ((side == "pz" and kits.front) or (side == "nz" and kits.back)) then
			slabBox(model, plot, "Rail", q[1], q[2], q[3], q[4], y, y + 3.2, rail)
			slabBox(model, plot, "Handrail", q[1], q[2], q[3], q[4], y + 3.2, y + 3.5, hand)
		end
	end
	if not T.DECKS[pc.storey] then   -- the roof: planters along the front and back, the pavilions and the crown
		local wood = { Color = TF.color(fin.planter), Material = Enum.Material.SmoothPlastic }
		local leaf = { Color = TF.color(TF.LEAF), Material = Enum.Material.SmoothPlastic, CanCollide = false }
		for x = r.x0 + 6, r.x1 - 6, 10 do
			for _, z in ipairs({ r.z1 - 2.2, r.z0 + 2.2 }) do
				slabBox(model, plot, "Planter", x - 2, x + 2, z - 0.9, z + 0.9, y, y + 1.4, wood)
				slabBox(model, plot, "Plants", x - 1.8, x + 1.8, z - 0.7, z + 0.7, y + 1.4, y + 2.0, leaf)
			end
		end
		return
	end
	local best, bestSide
	for side, t in pairs(kits) do if not best or t.depth > best.depth then best, bestSide = t, side end end
	for side, t in pairs(kits) do TowerArt.terrace(model, plot, t, side, y, fin, side == bestSide) end
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
	slabBox(model, plot, "PavilionRoof", r.x0 - 1, r.x1 + 1, r.z0 - 1, r.z1 + 1, y + h, y + h + 0.8, { Color = TF.color(finOf(plot).band), Material = Enum.Material.SmoothPlastic })
end

local function buildCrown(plot, L, model)
	local pc = P.PIECES[L]
	local l = T.lantern()
	local roofY = T.floorY(14)
	if pc.kind == "lantern" then
		slabBox(model, plot, "Lantern", l.x0, l.x1, l.z0, l.z1, roofY, roofY + 14,   -- walk-through: it stands over the roof stop (1b)
			{ Color = Color3.fromRGB(190, 214, 226), Material = Enum.Material.Glass, Transparency = 0.35, CastShadow = false, CanCollide = T.LANTERN_SOLID })
	elseif pc.kind == "halo" then   -- 1d: the crown ring with the company's name on its front
		nameSign(plot, TowerArt.crownRing(model, plot, roofY, finOf(plot)))
	else -- mast
		local cx, cz = (T.SHAFT.x0 + T.SHAFT.x1) / 2, (T.SHAFT.z0 + T.SHAFT.z1) / 2
		slabBox(model, plot, "Mast", cx - 0.6, cx + 0.6, cz - 0.6, cz + 0.6, roofY + 14, roofY + 34, { Color = CHARCOAL, Material = Enum.Material.SmoothPlastic })
		TowerArt.beacon(model, plot, cx, cz, roofY + 34)   -- 1d
	end
end

-- ---------------------------------------------------------------- the lift
-- can the lift let you off on storey s? (the landing is part of the core; any built piece there will do)
local function liftButton(plot, st, s)
	local y = T.floorY(s)
	local bx = (T.SHAFT.x0 + T.SHAFT.x1) / 2 + 3.2
	local btn = add(st.folder, { Name = "LiftCall", Size = Vector3.new(1.2, 2, 0.4),
		CFrame = plot.pivot * CFrame.new(bx, y + 4.2, T.SHAFT.z1 + 0.35), Color = CHARCOAL, CanCollide = false, CastShadow = false })
	table.insert(st.core, btn)
	local id = LiftPlan.stopId(s)   -- 1b: one id scheme (L, F<n>, R) for the stops, the doors and the cab
	local lit = add(st.folder, { Name = "LiftCallLit", Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.5, 0.5),
		CFrame = btn.CFrame * CFrame.new(0, 0.3, 0.25), Color = GOLD, Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, CastShadow = false })
	lit:SetAttribute("Stop", id)
	table.insert(st.core, lit)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Lift"
	pp.ObjectText = T.label(s)
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 11
	pp.RequiresLineOfSight = false
	pp.Parent = btn
	pp.Triggered:Connect(function(player)   -- 1b: call the cab (LiftCab); the old fade-and-teleport menu is gone
		if api.LiftCab and api.LiftCab.call then api.LiftCab.call(player, plot.index, id) end
	end)
	local stand = CFrame.lookAt((plot.pivot * CFrame.new(T.STAND.x, y + 0.1, T.STAND.z)).Position,
		(plot.pivot * CFrame.new(T.STAND.x, y + 0.1, T.SHAFT.z1)).Position)
	table.insert(st.stops, { id = id, name = s == 0 and "LOBBY" or tostring(s), sub = T.label(s), stand = stand })
end

-- 1b: the landing doors (two leaves in the shaft's door gap), the wall over them, and the display
-- above them, on one stop. Closed and solid; LiftCab opens them when the cab is here.
local DOOR = Color3.fromRGB(214, 220, 228)
local function liftDoors(plot, st, s, y, h)
	local S, C = T.SHAFT, T.CAB
	local zf = S.z1 - 0.2
	local mid = (S.x0 + S.x1) / 2
	for side, x0 in pairs({ L = mid - C.door / 2, R = mid }) do
		local leaf = slabBox(st.folder, plot, "LiftDoor" .. side, x0, x0 + C.door / 2, zf - 0.1, zf + 0.1, y, y + C.doorH,
			{ Color = DOOR, Material = Enum.Material.SmoothPlastic, CastShadow = false })
		leaf:SetAttribute("Stop", LiftPlan.stopId(s))
		table.insert(st.core, leaf)
	end
	for _, p in ipairs(TowerArt.liftFrame(st.folder, plot, y, finOf(plot))) do table.insert(st.core, p) end   -- 1d
	if h > C.doorH then   -- the wall over the door gap
		table.insert(st.core, slabBox(st.folder, plot, "LiftHeader", mid - C.door / 2, mid + C.door / 2, S.z1 - 0.4, S.z1, y + C.doorH, y + h - SLAB,
			{ Color = Color3.fromRGB(190, 214, 226), Material = Enum.Material.Glass, Transparency = 0.45, CastShadow = false }))
	end
	-- mock A: one fat number (B's room label beside it, smaller). 2.6 tall: the number is a third of the door
	local disp = slabBox(st.folder, plot, "LiftDisplay", mid - 3.5, mid + 3.5, S.z1 + 0.05, S.z1 + 0.25, y + C.doorH + 0.3, y + C.doorH + 2.9,
		{ Color = Color3.fromRGB(20, 22, 30), Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false })
	disp:SetAttribute("Stop", LiftPlan.stopId(s))
	Wafers.displayText(disp, Enum.NormalId.Back)   -- the +Z side of the plate, toward the landing
	table.insert(st.core, disp)
end

-- 1b: the cab (one per tower), built once and kept across rebuilds; LiftCab moves it
local CAB_GLASS = { Color = Color3.fromRGB(190, 214, 226), Material = Enum.Material.Glass, Transparency = 0.5, CastShadow = false }
function Wafers.cabAt(plot, storey)
	return plot.pivot * CFrame.new(T.CAB.x, T.floorY(storey), T.CAB.z)
end
local function surfaceText(part, face, color)
	local sg = Instance.new("SurfaceGui")
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud   -- or PixelsPerStud is ignored (fixed 800 x 600 canvas)
	sg.Face, sg.PixelsPerStud, sg.LightInfluence = face, 40, 0
	sg.Parent = part
	local tl = Instance.new("TextLabel")
	tl.Name, tl.Size, tl.BackgroundTransparency, tl.TextScaled = "Text", UDim2.fromScale(1, 1), 1, true
	tl.Font, tl.TextColor3, tl.Text = Enum.Font.FredokaOne, color, ""
	tl.Parent = sg
	return tl
end
-- the floor display: "Num" (the fat number, the arrow under it) and "Label" (the room), mock A + B
function Wafers.displayText(part, face)
	local sg = Instance.new("SurfaceGui")
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud   -- or PixelsPerStud is ignored (fixed 800 x 600 canvas)
	sg.Face, sg.PixelsPerStud, sg.LightInfluence = face, 40, 0
	sg.Parent = part
	local function text(name, pos, size, color, align)
		local tl = Instance.new("TextLabel")
		tl.Name, tl.Position, tl.Size, tl.BackgroundTransparency, tl.TextScaled = name, pos, size, 1, true
		tl.Font, tl.TextColor3, tl.Text, tl.TextXAlignment = Enum.Font.FredokaOne, color, "", align
		tl.Parent = sg
		return tl
	end
	text("Num", UDim2.fromScale(0.03, 0.02), UDim2.fromScale(0.3, 0.96), Color3.fromRGB(110, 220, 255), Enum.TextXAlignment.Center)
	text("Label", UDim2.fromScale(0.36, 0.25), UDim2.fromScale(0.6, 0.5), Color3.fromRGB(110, 220, 255), Enum.TextXAlignment.Left)
	return sg
end

function Wafers.cab(plot)
	local st = stateOf(plot)
	if st.cab and st.cab.Parent then return st.cab end
	local C = T.CAB
	local m = Instance.new("Model")
	m.Name = "LiftCab"
	m:SetAttribute("Plot", plot.index)
	m:SetAttribute("State", "idle")
	local base0 = Wafers.cabAt(plot, 0)
	local function part(name, size, off, props)
		local p = add(m, props)
		p.Name, p.Size, p.CFrame = name, size, base0 * CFrame.new(off)
		return p
	end
	local baseP = part("CabBase", Vector3.new(C.w, 0.5, C.d), Vector3.new(0, -0.25, 0), { Color = PAPER, Material = Enum.Material.SmoothPlastic })
	m.PrimaryPart = baseP
	-- solid: a ceiling you can see is a ceiling you cannot pass (the doctor's sinking check, 15 Oct)
	part("CabCeiling", Vector3.new(C.w, 0.3, C.d), Vector3.new(0, C.h + 0.15, 0), { Color = PAPER, Material = Enum.Material.SmoothPlastic, CanCollide = true })
	part("CabLight", Vector3.new(C.w - 2.5, 0.1, 3), Vector3.new(0, C.h - 0.05, 0), { Color = Color3.fromRGB(255, 248, 230), Material = Enum.Material.Neon, CanCollide = true, CastShadow = false })
	part("CabBack", Vector3.new(C.w, C.h, 0.2), Vector3.new(0, C.h / 2, -C.d / 2 + 0.1), CAB_GLASS)
	part("CabLeft", Vector3.new(0.2, C.h, C.d), Vector3.new(-C.w / 2 + 0.1, C.h / 2, 0), CAB_GLASS)
	part("CabRight", Vector3.new(0.2, C.h, C.d), Vector3.new(C.w / 2 - 0.1, C.h / 2, 0), CAB_GLASS)
	local header = part("CabHeader", Vector3.new(C.w, C.h - C.doorH, 0.2), Vector3.new(0, (C.h + C.doorH) / 2, C.d / 2 - 0.1),
		{ Color = Color3.fromRGB(20, 22, 30), Material = Enum.Material.SmoothPlastic, CanCollide = false })
	Wafers.displayText(header, Enum.NormalId.Front)   -- faces the riders
	part("Panel", Vector3.new(0.12, 6.4, 3.0), Vector3.new(C.w / 2 - 0.25, 4.6, 0), { Color = Color3.fromRGB(150, 156, 166), Material = Enum.Material.Metal, CanCollide = false })
	-- 1d (1b minor): the talking sign hangs over the door opening, under the floor display, facing the riders
	-- (the ride camera looks at the doors); its bottom at 7.0 clears the 8-tall opening for a 5-tall avatar
	local signPlate = part("Sign", Vector3.new(4.4, 1.0, 0.12), Vector3.new(0, 7.5, C.d / 2 - 0.5), { Color = Color3.fromRGB(20, 22, 30), Material = Enum.Material.SmoothPlastic, CanCollide = false })
	surfaceText(signPlate, Enum.NormalId.Front, Color3.fromRGB(255, 170, 60))     -- -Z: into the cab (checked live)
	for _, p in ipairs(m:GetChildren()) do if p:IsA("BasePart") then p.Anchored = true end end
	CollectionService:AddTag(m, "LiftCab")
	m.Parent = st.folder
	st.cab = m
	return m
end

-- the trophy panel: one socket per possible stop, lit where built (LiftPlan.sockets)
function Wafers.refreshPanel(plot, onPick)
	local st = stateOf(plot)
	local m = Wafers.cab(plot)
	local C = T.CAB
	local base = m.PrimaryPart.CFrame * CFrame.new(0, 0.25, 0)
	for i, sk in ipairs(LiftPlan.sockets(P.PIECES, st.level)) do
		local b = m:FindFirstChild("Btn_" .. sk.id)
		if not b then
			local slot = T.panelSlot(i)
			b = add(m, { Name = "Btn_" .. sk.id, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 0.72, 0.72),
				CFrame = base * CFrame.new(C.w / 2 - 0.33, slot.y, slot.z), CanCollide = false, Anchored = true, CastShadow = false })
			local num = surfaceText(b, Enum.NormalId.Left, Color3.fromRGB(20, 22, 30))
			num.Text, num.Font = sk.num, Enum.Font.GothamBlack
			local cd = Instance.new("ClickDetector")
			cd.MaxActivationDistance = 14
			cd.Parent = b
			cd.MouseClick:Connect(function(player) if b:GetAttribute("Built") and onPick then onPick(player, sk.id) end end)
		end
		b:SetAttribute("Built", sk.built)
		-- lit = bright warm plastic, not Neon: Neon's glow swallowed the numbers (look review, 15 Oct)
		b.Color = sk.built and Color3.fromRGB(255, 232, 170) or Color3.fromRGB(52, 56, 68)
		b.Material = Enum.Material.SmoothPlastic
		local tl = b:FindFirstChildWhichIsA("SurfaceGui") and b:FindFirstChildWhichIsA("SurfaceGui"):FindFirstChild("Text")
		if tl then tl.Visible = sk.built end
	end
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
	local top = T.topStorey(P.PIECES, st.level)
	local S = T.SHAFT
	local shaft = { Color = Color3.fromRGB(190, 214, 226), Material = Enum.Material.Glass, Transparency = 0.45, CastShadow = false }
	for s = 0, top do
		local y, h = T.floorY(s), T.storeyH(s)
		-- the shaft's 4 walls this storey (a 6-wide door gap on +Z, closed by the cab in 1b); a garden has no height
		for _, w in ipairs(h <= 0 and {} or{ { S.x0, S.x1, S.z0, S.z0 + 0.4 }, { S.x0, S.x0 + 0.4, S.z0, S.z1 }, { S.x1 - 0.4, S.x1, S.z0, S.z1 },
			{ S.x0, (S.x0 + S.x1) / 2 - 3, S.z1 - 0.4, S.z1 }, { (S.x0 + S.x1) / 2 + 3, S.x1, S.z1 - 0.4, S.z1 } }) do
			table.insert(st.core, slabBox(st.folder, plot, "LiftShaft", w[1], w[2], w[3], w[4], y - SLAB, y + h - SLAB, shaft))
		end
		-- the landing hall's floor, around the shaft (1b: the cab rides through it)
		for _, c in ipairs(T.landingRects(s)) do
			table.insert(st.core, slabBox(st.folder, plot, "Floor", c.x0, c.x1, c.z0, c.z1, y - SLAB, y,
				{ Color = PAPER, Material = Enum.Material.SmoothPlastic }))
		end
		if h > 0 and T.landable(P.PIECES, st.level, s) then liftDoors(plot, st, s, y, h) end
		if T.landable(P.PIECES, st.level, s) then liftButton(plot, st, s) end
	end
	for _, p in ipairs(TowerArt.coreTop(st.folder, plot, P.PIECES, st.level, finOf(plot))) do table.insert(st.core, p) end   -- 1d
	if api.HQFloors and api.HQFloors.register then api.HQFloors.register(plot.index, plot, st.stops) end
	if api.LiftCab and api.LiftCab.sync then api.LiftCab.sync(plot) end   -- 1b: the cab follows the build
end

--[[ v9 (14 Oct, HQ tower 1a): the garage's shell and dress go away once the tower has a lobby
	(level 2) and come back with level 1 (a spin-off). The WRITE CODE desk, the hire pad and the
	build pad stay: they stand in the ground storey's centre hall (TowerPlan's spots test). The
	animated "garage folds into the lobby" moment is part 1c. ]]
local GARAGE_KEEP = T.GARAGE_KEEP   -- measured live 14 Oct: the working parts (prompts, the desk set, the pads, the spawn)
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
	model:SetAttribute("Storey", pc.storey)        -- SVCheck's glass pass reads these on the client
	if pc.kind == "segment" then model:SetAttribute("Seg", pc.seg) end
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
	-- this room's doorways onto rooms not built yet get glass; this level's own neighbours lose theirs
	for _, e in ipairs(st.edges[L] or {}) do if e.Parent then e:Destroy() end end
	st.edges[L] = nil
	if pc.kind == "segment" then
		local r = T.room(pc.storey, pc.seg)
		local y, h = T.floorY(pc.storey), T.storeyH(pc.storey) - SLAB
		for side, M in pairs(T.edges(P.PIECES, L)) do
			local alongX = (side == "pz" or side == "nz")
			local at = (side == "pz" and r.z1 - T.WALL_T / 2) or (side == "nz" and r.z0 + T.WALL_T / 2)
				or (side == "px" and r.x1 - T.WALL_T / 2) or (r.x0 + T.WALL_T / 2)
			local mid = alongX and (r.x0 + r.x1) / 2 or (r.z0 + r.z1) / 2
			local props = { Color = TF.color(finOf(plot).glass), Material = Enum.Material.Glass, Transparency = 0.45, CastShadow = false }
			local e = alongX and slabBox(model, plot, "EdgeGlass", mid - 3, mid + 3, at - T.WALL_T / 2, at + T.WALL_T / 2, y, y + h, props)
				or slabBox(model, plot, "EdgeGlass", at - T.WALL_T / 2, at + T.WALL_T / 2, mid - 3, mid + 3, y, y + h, props)
			st.edges[M] = st.edges[M] or {}
			table.insert(st.edges[M], e)
		end
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

-- 1c: tell the owner's client to play the garage-to-lobby moment over pieces from..to (built already)
function Wafers.lobbyMoment(player, plot, from, to, line)
	local folder = RS:FindFirstChild("SVRemotes")
	local ev = folder and folder:FindFirstChild("LobbyMoment")
	if not (ev and player) then return end
	local st = stateOf(plot)
	local models = {}
	for L = from, to do
		local pc = st.pieces[L]
		if pc and pc.model then table.insert(models, pc.model) end
	end
	ev:FireClient(player, { pivot = plot.pivot, models = models, core = st.core, cab = st.cab, line = line })
end

-- everything back to the garage (a spin-off, or the owner leaving)
function Wafers.clear(plot)
	local st = plot.wafer
	if not st then return end
	if api and api.LiftCab and api.LiftCab.reset then api.LiftCab.reset(plot) end   -- 1b: forget the cab and its riders
	for _, c in ipairs(st.folder:GetChildren()) do c:Destroy() end
	st.level, st.depts, st.pieces, st.core, st.stops, st.edges = 1, {}, {}, {}, {}, {}
	st.cab = nil   -- 1b: destroyed with the folder; Wafers.cab makes a new one
	st.names = {}   -- 1d: the entrance sign and the crown plate went with the folder
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
	refreshNames(plot)   -- 1d: the entrance sign and the crown plate
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
	TowerArt.init({ box = slabBox, part = function(props, parent) return add(parent, props) end })   -- 1d
	task.spawn(function()   -- 1d: the name signs follow a rename
		while true do
			task.wait(2)
			for plot in pairs(namedPlots) do pcall(refreshNames, plot) end
		end
	end)
	if api.LiftCab and api.LiftCab.init then api.LiftCab.init({ Wafers = Wafers, session = api.session }) end   -- 1b
	do   -- 1c: the garage-to-lobby moment (LobbyMomentClient plays it on the owner's screen)
		local folder = RS:WaitForChild("SVRemotes")
		local ev = folder:FindFirstChild("LobbyMoment") or Instance.new("RemoteEvent")
		ev.Name = "LobbyMoment"
		ev.Parent = folder
	end
end

return Wafers
