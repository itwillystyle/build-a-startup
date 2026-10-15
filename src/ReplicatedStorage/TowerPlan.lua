--[[ TowerPlan (14 Oct 2026, HQ overhaul project #1, part 1a): the HQ tower's geometry. Pure.

	Luke's pick: concept 2's glass spire with concept 3's terraces, 24-stud lobby storey and
	18-stud storeys (spec docs/superpowers/specs/2026-10-14-hq-tower-design.md). The 100-piece
	list, prices and departments stay in WaferPlan; this module only says WHERE things are.

	Plot-local studs: the garage's centre is the origin, +Z faces the road. Each storey is a
	3 x 3 grid: 8 rooms (WaferPlan's segs 1..8, seg 1 at the front centre, then clockwise seen
	from above) around a centre hall that holds the lift shaft. Every storey has its own
	rectangle (`rect`): a podium lobby wider than the tower, then each floor a step narrower, and
	at each garden storey (2, 6, 10) a setback: the front, then the back, then the front.
	The garage's desk, hire pad and build pad stand in the podium's centre hall. ]]
local T = {}

T.FLOOR_Y, T.LOBBY_H, T.H, T.SLAB = 1.0, 24, 18, 1.5
--[[ v9.1 (14 Oct, Luke: "fix the taper and the podium lobby"). Every storey has its own rectangle:
	the mock's taper (each floor steps in) plus its setbacks (the front, the back, the front at the
	three garden storeys), on a podium lobby that stands out past the tower on every side.
	The top is held at hx 40.8: the lift shaft must fit the top storey's centre hall. ]]
T.BASE = { hx = 50, hd = 46 }            -- floor 1, before setbacks
T.TAPER = { x = 10 / 13, z = 0.5 }       -- studs each storey steps in, per side (x: 100 wide at 1, 80 at 14)
T.SETBACK = 6
T.PODIUM = { x = 20, front = 8, back = 16 } -- how far the lobby stands out past floor 1: 1.4x its width (the mock: 70 under 52 = 1.35x)

-- storey s's rectangle: { hx, zf, zb } (x from -hx to hx, z from zb to zf)
function T.rect(s)
	s = math.floor(s or 0)
	if s <= 0 then
		local a = T.rect(1)
		return { hx = a.hx + T.PODIUM.x, zf = a.zf + T.PODIUM.front, zb = a.zb - T.PODIUM.back }
	end
	s = math.min(s, 14)
	local hd = T.BASE.hd - T.TAPER.z * (s - 1)
	local zf = hd - ((s >= 3) and T.SETBACK or 0) - ((s >= 11) and T.SETBACK or 0)
	local zb = -hd + ((s >= 7) and T.SETBACK or 0)
	return { hx = T.BASE.hx - T.TAPER.x * (s - 1), zf = zf, zb = zb }
end

T.DECKS = { [2] = 1, [6] = 2, [10] = 3 }                  -- a garden storey -> the section below it
T.SHAFT = { x0 = 5, x1 = 13, z0 = -12, z1 = -2 }          -- in every centre hall, clear of the garage's desks (x -4.4..4.4, measured)
T.STAND = { x = 9, z = 1.5 }                              -- where the lift lets you off: in front of its +Z doors
T.TOP = 15
-- the garage's working spots, plot-local, measured live 14 Oct: they stand in the lobby's centre hall
T.GARAGE_SPOTS = {
	{ x0 = -4.4, x1 = 4.4, z0 = -10.2, z1 = -7.8 },     -- the WRITE CODE desks (two, 4.3 wide at x -2.2 and 2.2, z -9)
	{ x0 = 1.5, x1 = 3.5, z0 = -7.1, z1 = -5.3 },       -- the desk chair at (2.5, -6.2)
	{ x0 = 1.7, x1 = 4.1, z0 = -9.8, z1 = -9.2 },       -- the monitor at (2.9, -9.5)
	{ x0 = -14.5, x1 = -7.5, z0 = 0.5, z1 = 7.5 },      -- the hire pad, 7x7 at (-11, 4)
	{ x0 = 10, x1 = 16, z0 = 5, z1 = 11 },               -- the build pad, 6x6 at (13, 8)
	{ x0 = -1, x1 = 1, z0 = -1, z1 = 1 },                -- the spawn at (0, 0)
}

--[[ v9.2 (14 Oct, Luke: "fix the garden storeys so they look like terraces"). A garden storey
	has no height: the floor above stands on its deck, and the garden is the strip the step-back
	leaves open (`terraces`), as in the mock. Before, each garden was a whole empty 18-stud storey
	and read from the plaza as a missing floor. ]]
function T.storeyH(s)
	if s == 0 then return T.LOBBY_H end
	if T.DECKS[s] then return 0 end
	return T.H
end

function T.floorY(s)
	s = math.max(0, math.floor(s or 0))
	if s == 0 then return T.FLOOR_Y end
	local y = T.FLOOR_Y + T.LOBBY_H
	for k = 1, s - 1 do y += T.storeyH(k) end
	return y
end

function T.section(s)
	if T.DECKS[s] then return T.rect(s - 1) end
	return T.rect(s)
end

-- the section that starts right above garden storey s (nil if none)
function T.above(s) return T.rect(s + 1) end

-- cell (col, row) of a section's 3 x 3 grid: col 1..3 from -x to +x, row 1..3 from back to front
local function cell(sec, col, row)
	local w = 2 * sec.hx / 3
	local dz = (sec.zf - sec.zb) / 3
	local x0 = -sec.hx + (col - 1) * w
	local z0 = sec.zb + (row - 1) * dz
	return { x0 = x0, x1 = x0 + w, z0 = z0, z1 = z0 + dz }
end

T.CELL = { { 2, 3 }, { 3, 3 }, { 3, 2 }, { 3, 1 }, { 2, 1 }, { 1, 1 }, { 1, 2 }, { 1, 3 } }   -- seg -> {col, row}
T.YAW = { 0, 0, math.pi / 2, math.pi, math.pi, math.pi, -math.pi / 2, 0 }                     -- furniture faces out

function T.room(storey, seg)
	local c = T.CELL[seg]
	local r = cell(T.section(storey), c[1], c[2])
	local function side(dc, dr)
		local nc, nr = c[1] + dc, c[2] + dr
		if nc < 1 or nc > 3 or nr < 1 or nr > 3 then return "glass" end
		if nc == 2 and nr == 2 then return 8 end
		return 6
	end
	r.cx, r.cz = (r.x0 + r.x1) / 2, (r.z0 + r.z1) / 2
	r.yaw = T.YAW[seg]
	r.sides = { px = side(1, 0), nx = side(-1, 0), pz = side(0, 1), nz = side(0, -1) }
	-- the lobby's entrance (14 wide) on the forecourt side; the middle room of the row that stands
	-- behind a terrace has a glass door onto it (final review 2: the terraces could not be reached)
	if storey == 0 and seg == 1 then r.entrance = { side = "pz", width = 14 } end
	if T.DECKS[storey - 1] then
		local back = (T.DECKS[storey - 1] == 2)   -- deck 6 steps the back in; 2 and 10 the front
		if not back and seg == 1 then r.terraceDoor = "pz" elseif back and seg == 5 then r.terraceDoor = "nz" end
	end
	local wx, wz = r.x1 - r.x0, r.z1 - r.z0
	if seg == 3 or seg == 7 then r.w, r.d = wz, wx else r.w, r.d = wx, wz end
	return r
end

function T.centre(s) return cell(T.section(s), 2, 2) end

-- a garden storey's deck, or the roof (14): the top of the storey below
function T.deck(s)
	local r = T.rect(math.min(s, 14) - 1)
	return { x0 = -r.hx, x1 = r.hx, z0 = r.zb, z1 = r.zf }
end

function T.pavilion(k)
	local roof = T.deck(14)
	local qx = ({ 1, 1, -1, -1 })[k] * roof.x1 / 2
	local qz = roof.z0 + (roof.z1 - roof.z0) * (({ 0.8, 0.2, 0.2, 0.8 })[k])
	return { x0 = qx - 6, x1 = qx + 6, z0 = qz - 6, z1 = qz + 6 }
end

function T.lantern()
	local s = T.SHAFT
	return { x0 = s.x0 - 3, x1 = s.x1 + 3, z0 = s.z0 - 3, z1 = s.z1 + 3 }
end

-- a piece's anchor in plot space (pc = a WaferPlan.PIECES entry)
function T.frame(pc)
	if pc.kind == "segment" then
		local r = T.room(pc.storey, pc.seg)
		return { x = r.cx, z = r.cz, yaw = r.yaw }
	elseif pc.kind == "pavilion" then
		local r = T.pavilion(pc.seg)
		return { x = (r.x0 + r.x1) / 2, z = (r.z0 + r.z1) / 2, yaw = 0 }
	elseif pc.kind == "halo" or pc.kind == "lantern" or pc.kind == "mast" then
		return { x = (T.SHAFT.x0 + T.SHAFT.x1) / 2, z = (T.SHAFT.z0 + T.SHAFT.z1) / 2, yaw = 0 }
	end
	local r = T.deck(pc.storey)
	return { x = 0, z = (r.z0 + r.z1) / 2, yaw = 0 }
end

-- ---------------------------------------------------------------- walls, the lift, edges (final review, 14 Oct)
T.WALL_T = 0.4          -- every wall and the facade glass, inside the room's rectangle
T.GLASS_BAND = 0.9      -- furniture keeps this far in from the glass (mullions; SVCheck's glass pass)

-- how far furniture may reach from a room's centre, in the room's own frame (x across w, z across d)
function T.inner(r)
	return { x = r.w / 2 - T.WALL_T - T.GLASS_BAND, z = r.d / 2 - T.WALL_T - T.GLASS_BAND }
end

-- the Servers room's wall fans (0.35 deep): just inside the facade glass, room frame
function T.fanZ(r) return r.d / 2 - T.WALL_T - 0.3 end

local CROWN = { halo = true, lantern = true, mast = true }

-- the highest storey with a piece that is not the crown, at this level (`pieces` = WaferPlan.PIECES)
function T.topStorey(pieces, level)
	local top = 0
	for L = 2, level do
		local pc = pieces[L]
		if pc and not CROWN[pc.kind] then top = math.max(top, pc.storey) end
	end
	if T.DECKS[top] then top += 1 end   -- a fresh garden deck: the floor above stands on it (and is the stop)
	return top
end

-- does the lift stop at storey s? the lobby always (once there is a tower), any other storey
-- once a piece that is not the crown stands on it
function T.landable(pieces, level, s)
	if level < 2 then return false end
	if s == 0 then return true end
	if T.DECKS[s] then return false end           -- the floor above it is the stop
	for L = 2, level do
		local pc = pieces[L]
		if pc and not CROWN[pc.kind] and (pc.storey == s or (pc.storey == s - 1 and T.DECKS[s - 1])) then return true end
	end
	return false
end

-- the landing hall floor of storey s (the centre cell), or nil where a deck carries the stand
function T.landing(s)
	if T.DECKS[s] or T.DECKS[s - 1] or s >= 14 then return nil end   -- a deck carries the stand
	return T.centre(s)
end

-- the room in the cell on `side` of seg's cell, or nil (the outside or the centre hall)
local SIDE = { px = { 1, 0 }, nx = { -1, 0 }, pz = { 0, 1 }, nz = { 0, -1 } }
function T.neighbour(seg, side)
	local c, d = T.CELL[seg], SIDE[side]
	local nc, nr = c[1] + d[1], c[2] + d[2]
	for k, v in ipairs(T.CELL) do
		if v[1] == nc and v[2] == nr then return k end
	end
	return nil
end

--[[ the doors of room L that open onto a room not built yet when L is built: side -> the level
	that builds it (math.huge if no piece ever does). The builder glazes those doorways and
	takes the glass out when that level is built; before this, storeys 1+ had an open door
	onto an 18-stud drop (final review I4). ]]
function T.edges(pieces, L)
	local pc = pieces[L]
	local out = {}
	if not pc or pc.kind ~= "segment" then return out end
	local levelAt = {}
	for _, q in ipairs(pieces) do
		if q.kind == "segment" and q.storey == pc.storey then levelAt[q.seg] = q.level end
	end
	for side, kind in pairs(T.room(pc.storey, pc.seg).sides) do
		if kind == 6 then
			local n = T.neighbour(pc.seg, side)
			local M = n and levelAt[n] or math.huge
			if M > L then out[side] = M end
		end
	end
	return out
end

--[[ where DECOR may stand once the tower stands (level 2+): the lobby storey's built rooms (inside
	their walls) and the centre hall around the lift shaft. A piece must fit inside ONE rect, so the
	hall is four rects around the shaft. nil before the tower (decor stays on the garage floor).
	Rooms higher up get their decor with project #2 (interiors). ]]
function T.decorRects(pieces, level)
	if level < 2 then return nil end
	local out = {}
	local w = T.WALL_T
	for L = 2, level do
		local pc = pieces[L]
		if pc and pc.kind == "segment" and pc.storey == 0 then
			local r = T.room(0, pc.seg)
			table.insert(out, { x0 = r.x0 + w, x1 = r.x1 - w, z0 = r.z0 + w, z1 = r.z1 - w })
		end
	end
	local c, sh = T.centre(0), T.SHAFT
	table.insert(out, { x0 = c.x0, x1 = sh.x0, z0 = c.z0, z1 = c.z1 })      -- left of the shaft
	table.insert(out, { x0 = sh.x1, x1 = c.x1, z0 = c.z0, z1 = c.z1 })      -- right of it
	table.insert(out, { x0 = c.x0, x1 = c.x1, z0 = sh.z1, z1 = c.z1 })      -- in front (the garage spots)
	table.insert(out, { x0 = c.x0, x1 = c.x1, z0 = c.z0, z1 = sh.z0 })      -- behind
	return out
end

--[[ may a decor piece's footprint b ({x0, x1, z0, z1}, plot-local) stand in the tower at this level?
	nil before the tower. It must lie inside one decorRects rect and clear of the keep-clear zones:
	the shaft and its landing (where the lift lets you off), the garage's working spots, and 3 studs
	either side of every doorway of the built lobby-storey rooms (final review 2, I3). ]]
local function hits(a, b)
	return math.min(a.x1, b.x1) - math.max(a.x0, b.x0) > 1e-6 and math.min(a.z1, b.z1) - math.max(a.z0, b.z0) > 1e-6
end
function T.decorKeepClear(pieces, level)
	local out = {}
	local sh = T.SHAFT
	table.insert(out, { x0 = sh.x0 - 0.5, x1 = sh.x1 + 0.5, z0 = sh.z0 - 0.5, z1 = sh.z1 + 5 })   -- the shaft + its landing
	for _, g in ipairs(T.GARAGE_SPOTS) do table.insert(out, g) end   -- exact: saved plants stand right beside the pads
	for L = 2, level do
		local pc = pieces[L]
		if pc and pc.kind == "segment" and pc.storey == 0 then
			local r = T.room(0, pc.seg)
			for side, kind in pairs(r.sides) do
				local w = (type(kind) == "number") and kind or nil
				if r.entrance and r.entrance.side == side then w = r.entrance.width end
				if w then
					local alongX = (side == "pz" or side == "nz")
					local at = (side == "pz" and r.z1) or (side == "nz" and r.z0) or (side == "px" and r.x1) or r.x0
					local mid = alongX and r.cx or r.cz
					if alongX then
						table.insert(out, { x0 = mid - w / 2, x1 = mid + w / 2, z0 = at - 3, z1 = at + 3 })
					else
						table.insert(out, { x0 = at - 3, x1 = at + 3, z0 = mid - w / 2, z1 = mid + w / 2 })
					end
				end
			end
		end
	end
	return out
end

function T.decorOk(pieces, level, b)
	local rects = T.decorRects(pieces, level)
	if not rects then return nil end
	local on = false
	for _, r in ipairs(rects) do
		if b.x0 >= r.x0 - 1e-6 and b.x1 <= r.x1 + 1e-6 and b.z0 >= r.z0 - 1e-6 and b.z1 <= r.z1 + 1e-6 then on = true break end
	end
	if not on then return false end
	for _, k in ipairs(T.decorKeepClear(pieces, level)) do
		if hits(b, k) then return false end
	end
	return true
end

-- the open strips of garden deck d around the storey that stands on it: side -> { x0, x1, z0, z1, depth }
function T.terraces(d)
	local deck, up = T.deck(d), T.rect(d + 1)
	local out = {}
	if deck.z1 - up.zf > 0 then out.front = { x0 = deck.x0, x1 = deck.x1, z0 = up.zf, z1 = deck.z1, depth = deck.z1 - up.zf } end
	if up.zb - deck.z0 > 0 then out.back = { x0 = deck.x0, x1 = deck.x1, z0 = deck.z0, z1 = up.zb, depth = up.zb - deck.z0 } end
	if deck.x1 - up.hx > 0 then
		out.right = { x0 = up.hx, x1 = deck.x1, z0 = up.zb, z1 = up.zf, depth = deck.x1 - up.hx }
		out.left = { x0 = deck.x0, x1 = -up.hx, z0 = up.zb, z1 = up.zf, depth = deck.x1 - up.hx }
	end
	return out
end

function T.label(s)
	if s == 0 then return "LOBBY" end
	if T.DECKS[s] then return "SKY GARDEN" end
	if s >= 14 then return "ROOF GARDEN" end
	if T.DECKS[s - 1] then return "FLOOR " .. s .. " · TERRACE" end
	return "FLOOR " .. s
end

-- the finished tower's silhouette (the intro flyover's ghost): one box per section + the crown
function T.spec()
	local out = {}
	for st = 0, 13 do
		if not T.DECKS[st] then
			local r = T.rect(st)
			table.insert(out, ("%g:%g:%g:%g:%g:%g"):format(-r.hx, r.hx, r.zb, r.zf, T.floorY(st) - T.SLAB, T.floorY(st) + T.storeyH(st) - T.SLAB))
		end
	end
	local l = T.lantern()
	table.insert(out, ("%g:%g:%g:%g:%g:%g"):format(l.x0, l.x1, l.z0, l.z1, T.floorY(14), T.floorY(15) + 4))
	return table.concat(out, "|")
end

function T.parseSpec(str)
	local out = {}
	if type(str) ~= "string" then return out end
	for chunk in str:gmatch("[^|]+") do
		local v = {}
		for n in chunk:gmatch("[^:]+") do table.insert(v, tonumber(n)) end
		if #v == 6 and v[1] and v[2] and v[3] and v[4] and v[5] and v[6] then
			table.insert(out, { x0 = v[1], x1 = v[2], z0 = v[3], z1 = v[4], y0 = v[5], y1 = v[6] })
		end
	end
	return out
end

return T
