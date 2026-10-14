--[[ TowerPlan (14 Oct 2026, HQ overhaul project #1, part 1a): the HQ tower's geometry. Pure.

	Luke's pick: concept 2's glass spire with concept 3's terraces, 24-stud lobby storey and
	18-stud storeys (spec docs/superpowers/specs/2026-10-14-hq-tower-design.md). The 100-piece
	list, prices and departments stay in WaferPlan; this module only says WHERE things are.

	Plot-local studs: the garage's centre is the origin, +Z faces the road. Each storey is a
	3 x 3 grid: 8 rooms (WaferPlan's segs 1..8, seg 1 at the front centre, then clockwise seen
	from above) around a centre hall that holds the lift shaft. The building has 4 sections;
	at each garden storey (2, 6, 10) it steps back: the front, then the back, then the front.
	The garage's desk, hire pad and build pad stand in the ground storey's centre hall. ]]
local T = {}

T.FLOOR_Y, T.LOBBY_H, T.H, T.SLAB = 1.0, 24, 18, 1.5
T.SECTIONS = {
	{ from = 0, to = 1, hx = 46, zf = 46, zb = -46 },
	{ from = 3, to = 5, hx = 44, zf = 40, zb = -46 },     -- deck 2: the front steps back 6
	{ from = 7, to = 9, hx = 42, zf = 40, zb = -40 },     -- deck 6: the back steps in 6
	{ from = 11, to = 14, hx = 40, zf = 34, zb = -40 },   -- deck 10: the front steps back 6; 14 = the roof garden
}
T.DECKS = { [2] = 1, [6] = 2, [10] = 3 }                  -- a garden storey -> the section below it
T.SHAFT = { x0 = 3, x1 = 13, z0 = -12, z1 = -2 }          -- in every centre hall, clear of the garage's spots
T.STAND = { x = 8, z = 1.5 }                              -- where the lift lets you off: in front of its +Z doors
T.TOP = 15

function T.storeyH(s) return (s == 0) and T.LOBBY_H or T.H end

function T.floorY(s)
	s = math.max(0, math.floor(s or 0))
	if s == 0 then return T.FLOOR_Y end
	return T.FLOOR_Y + T.LOBBY_H + (s - 1) * T.H
end

function T.section(s)
	local d = T.DECKS[s]
	if d then return T.SECTIONS[d] end
	for _, sec in ipairs(T.SECTIONS) do
		if s >= sec.from and s <= sec.to then return sec end
	end
	return T.SECTIONS[#T.SECTIONS]
end

-- the section that starts right above garden storey s (nil if none)
function T.above(s)
	for _, sec in ipairs(T.SECTIONS) do if sec.from == s + 1 then return sec end end
	return nil
end

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

function T.deck(s)
	local sec = T.SECTIONS[T.DECKS[s] or #T.SECTIONS]
	return { x0 = -sec.hx, x1 = sec.hx, z0 = sec.zb, z1 = sec.zf }
end

function T.pavilion(k)
	local sec = T.SECTIONS[#T.SECTIONS]
	local qx = ({ 1, 1, -1, -1 })[k] * sec.hx / 2
	local qz = sec.zb + (sec.zf - sec.zb) * (({ 0.75, 0.25, 0.25, 0.75 })[k])
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

function T.label(s)
	if s == 0 then return "LOBBY" end
	if T.DECKS[s] then return "SKY GARDEN" end
	if s >= 14 then return "ROOF GARDEN" end
	return "FLOOR " .. s
end

-- the finished tower's silhouette (the intro flyover's ghost): one box per section + the crown
function T.spec()
	local out = {}
	for i, sec in ipairs(T.SECTIONS) do
		local top = (i < #T.SECTIONS) and T.floorY(sec.to + 1) or T.floorY(14)
		table.insert(out, ("%g:%g:%g:%g:%g:%g"):format(-sec.hx, sec.hx, sec.zb, sec.zf, T.floorY(sec.from) - T.SLAB, top))
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
