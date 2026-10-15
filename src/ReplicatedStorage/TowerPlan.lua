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
T.PODIUM = { x = 9, front = 6, back = 8 } -- how far the lobby stands out past floor 1 (the mock: 70 x 50 under 52 x 34)

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

function T.storeyH(s) return (s == 0) and T.LOBBY_H or T.H end

function T.floorY(s)
	s = math.max(0, math.floor(s or 0))
	if s == 0 then return T.FLOOR_Y end
	return T.FLOOR_Y + T.LOBBY_H + (s - 1) * T.H
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
	return top
end

-- does the lift stop at storey s? the lobby always (once there is a tower), any other storey
-- once a piece that is not the crown stands on it
function T.landable(pieces, level, s)
	if level < 2 then return false end
	if s == 0 then return true end
	for L = 2, level do
		local pc = pieces[L]
		if pc and pc.storey == s and not CROWN[pc.kind] then return true end
	end
	return false
end

-- the landing hall floor of storey s (the centre cell), or nil where a deck carries the stand
function T.landing(s)
	if T.DECKS[s] or s >= 14 then return nil end
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

function T.label(s)
	if s == 0 then return "LOBBY" end
	if T.DECKS[s] then return "SKY GARDEN" end
	if s >= 14 then return "ROOF GARDEN" end
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
