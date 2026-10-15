-- tower.spec.luau: the HQ tower's geometry (14 Oct 2026, project #1 part 1a). Spec:
-- silicon-startup/docs/superpowers/specs/2026-10-14-hq-tower-design.md
local T = require("../../src/ReplicatedStorage/TowerPlan")
local W = require("../../src/ServerScriptService/WaferPlan")
local TT = {}
local function test(name, fn) table.insert(TT, { name = name, fn = fn }) end

local function overlap(a, b)
	return math.min(a.x1, b.x1) - math.max(a.x0, b.x0) > 0.01 and math.min(a.z1, b.z1) - math.max(a.z0, b.z0) > 0.01
end
local function inside(a, b) return a.x0 >= b.x0 - 1e-6 and a.x1 <= b.x1 + 1e-6 and a.z0 >= b.z0 - 1e-6 and a.z1 <= b.z1 + 1e-6 end

test("heights: a 24-stud lobby storey, then 18", function()
	assert(T.storeyH(0) == 24 and T.storeyH(1) == 18 and T.storeyH(13) == 18, "storey heights")
	assert(T.floorY(0) == 1.0 and T.floorY(1) == 25 and T.floorY(2) == 43 and T.floorY(14) == 25 + 13 * 18, "floor tops")
end)

test("every segment piece has a room inside its section, and rooms on a storey never overlap", function()
	local byStorey = {}
	for _, pc in ipairs(W.PIECES) do
		if pc.kind == "segment" then
			local r = T.room(pc.storey, pc.seg)
			local sec = T.section(pc.storey)
			assert(inside(r, { x0 = -sec.hx, x1 = sec.hx, z0 = sec.zb, z1 = sec.zf }), ("L%d outside its section"):format(pc.level))
			byStorey[pc.storey] = byStorey[pc.storey] or {}
			for _, o in ipairs(byStorey[pc.storey]) do assert(not overlap(r, o), ("L%d overlaps"):format(pc.level)) end
			assert(not overlap(r, T.SHAFT), ("L%d overlaps the shaft"):format(pc.level))
			assert(r.w >= 20 and r.d >= 20, ("L%d too small: %.1f x %.1f"):format(pc.level, r.w, r.d))
			table.insert(byStorey[pc.storey], r)
		end
	end
	for _, s in ipairs({ 0, 1, 3, 4, 5, 7, 8, 9, 11, 12, 13 }) do assert(#byStorey[s] == 8, "8 rooms on storey " .. s) end
end)

test("the shaft and the stand fit every storey's centre hall", function()
	for s = 0, 13 do
		if not T.DECKS[s] then
			local c = T.centre(s)
			assert(inside(T.SHAFT, c), "shaft outside the centre hall on storey " .. s)
			assert(T.STAND.x > c.x0 and T.STAND.x < c.x1 and T.STAND.z > c.z0 and T.STAND.z < c.z1, "stand outside on " .. s)
			assert(not overlap({ x0 = T.STAND.x - 1, x1 = T.STAND.x + 1, z0 = T.STAND.z - 1, z1 = T.STAND.z + 1 }, T.SHAFT), "stand in the shaft")
		end
	end
end)

-- 14 Oct (Luke: "fix the taper and the podium lobby"): the mock's podium is wider than the tower on every side,
-- and every floor steps in (concept 2's taper), with concept 3's setbacks kept at the garden storeys
test("the podium lobby is wider and deeper than the tower above it (the mock's glass base)", function()
	local p, a = T.rect(0), T.rect(1)
	assert(p.hx >= a.hx + 8, ("podium sides only %.1f wider than floor 1"):format(p.hx - a.hx))
	assert(p.zf >= a.zf + 4 and p.zb <= a.zb - 4, "the podium must stand out at the front and the back")
	assert(T.section(0).hx == p.hx, "storey 0's rooms are laid out on the podium")
end)

test("taper: every storey above the lobby is narrower than the one below, 18% or more in all", function()
	for s = 2, 14 do
		assert(T.rect(s).hx < T.rect(s - 1).hx - 0.25, ("storey %d does not step in"):format(s))
	end
	assert(T.rect(14).hx <= 0.82 * T.rect(1).hx, ("total taper only %.0f%%"):format(100 * (1 - T.rect(14).hx / T.rect(1).hx)))
end)

test("setbacks: front, back, front at the three garden storeys, and each deck is the roof below it", function()
	assert(T.rect(3).zf <= T.rect(1).zf - 6, "deck 2 steps the front back")
	assert(T.rect(7).zb >= T.rect(5).zb + 6, "deck 6 steps the back in")
	assert(T.rect(11).zf <= T.rect(9).zf - 6, "deck 10 steps the front back")
	for d in pairs(T.DECKS) do
		local r, below = T.deck(d), T.rect(d - 1)
		assert(r.x0 == -below.hx and r.x1 == below.hx and r.z0 == below.zb and r.z1 == below.zf, "deck " .. d .. " = the storey below")
	end
end)

test("the roof pavilions stand on the roof and clear of the crown", function()
	local roof, l = T.deck(14), T.lantern()
	for k = 1, 4 do
		local pv = T.pavilion(k)
		assert(inside(pv, { x0 = roof.x0, x1 = roof.x1, z0 = roof.z0, z1 = roof.z1 }), "pavilion " .. k .. " off the roof")
		assert(not overlap(pv, l), "pavilion " .. k .. " inside the crown")
	end
end)

test("balanced: the full tower's room area centre is within 4 studs of the lobby's centre line", function()
	local a, mz = 0, 0
	for _, pc in ipairs(W.PIECES) do
		if pc.kind == "segment" then
			local r = T.room(pc.storey, pc.seg)
			local area = (r.x1 - r.x0) * (r.z1 - r.z0)
			a += area
			mz += area * r.cz
		end
	end
	assert(math.abs(mz / a) <= 4, ("centre of mass z = %.2f"):format(mz / a))
end)

test("doors: edge rooms open to the centre hall (8), corners to their neighbours (6), the outside is glass", function()
	local r1 = T.room(1, 1)
	assert(r1.sides.pz == "glass" and r1.sides.nz == 8 and r1.sides.px == 6 and r1.sides.nx == 6, "front centre room")
	local r2 = T.room(1, 2)
	assert(r2.sides.pz == "glass" and r2.sides.px == "glass" and r2.sides.nx == 6 and r2.sides.nz == 6, "front right corner")
	local r5 = T.room(1, 5)
	assert(r5.sides.nz == "glass" and r5.sides.pz == 8, "back centre room")
end)

test("rooms face out: furniture yaw per seg, and w/d swap for the side rooms", function()
	assert(T.room(1, 1).yaw == 0 and T.room(1, 5).yaw == math.pi and math.abs(T.room(1, 3).yaw - math.pi / 2) < 1e-9, "yaw")
	local r3 = T.room(1, 3)
	assert(r3.w == r3.z1 - r3.z0 and r3.d == r3.x1 - r3.x0, "side room sizes are turned")
end)

test("the garage's working spots stay clear of the shaft (desk, hire pad, build pad, spawn)", function()
	local spots = {
		{ x0 = -4.4, x1 = 4.4, z0 = -10.2, z1 = -7.8 },     -- the WRITE CODE desks (two, 4.3 wide at x -2.2 and 2.2, z -9), measured 14 Oct
		{ x0 = 1.5, x1 = 3.5, z0 = -7.1, z1 = -5.3 },       -- the desk chair at (2.5, -6.2)
		{ x0 = 1.7, x1 = 4.1, z0 = -9.8, z1 = -9.2 },       -- the monitor at (2.9, -9.5)
		{ x0 = -14.5, x1 = -7.5, z0 = 0.5, z1 = 7.5 },      -- the hire pad, 7x7 at (-11, 4)
		{ x0 = 10, x1 = 16, z0 = 5, z1 = 11 },               -- the build pad, 6x6 at (13, 8)
		{ x0 = -1, x1 = 1, z0 = -1, z1 = 1 },                -- the spawn at (0, 0)
	}
	local hall = T.centre(0)
	for i, s in ipairs(spots) do
		assert(not overlap(s, T.SHAFT), "spot " .. i .. " is in the shaft")
		assert(inside(s, { x0 = hall.x0 + T.WALL_T, x1 = hall.x1 - T.WALL_T, z0 = hall.z0 + T.WALL_T, z1 = hall.z1 - T.WALL_T }),
			"spot " .. i .. " is not inside the lobby's centre hall (a wall stands on it)")
	end
end)

test("frames: a room's anchor is its centre at its floor, the crown stands over the shaft", function()
	local pc = W.PIECES[2]   -- L2: the lobby, storey 0 seg 1
	local f = T.frame(pc)
	local r = T.room(0, 1)
	assert(f.x == r.cx and f.z == r.cz and f.yaw == 0, "lobby frame")
	local mast = T.frame(W.PIECES[100])
	assert(mast.x == (T.SHAFT.x0 + T.SHAFT.x1) / 2 and mast.z == (T.SHAFT.z0 + T.SHAFT.z1) / 2, "mast over the shaft")
end)

test("labels: lobby, floors, sky gardens, roof", function()
	assert(T.label(0) == "LOBBY" and T.label(2) == "SKY GARDEN" and T.label(14) == "ROOF GARDEN" and T.label(3) == "FLOOR 3", "labels")
end)

test("silhouette: spec() round-trips through parseSpec, one box per storey with rooms plus the crown", function()
	local boxes = T.parseSpec(T.spec())
	local n = 0
	for st = 0, 13 do if not T.DECKS[st] then n += 1 end end
	assert(#boxes == n + 1, "boxes: " .. #boxes)
	assert(boxes[1].x0 == -T.rect(0).hx and boxes[1].y0 == T.floorY(0) - T.SLAB, "first box is the podium")
	assert(#T.parseSpec("junk") == 0 and #T.parseSpec(nil) == 0, "bad input gives nothing")
end)

-- the final review (14 Oct): I5 -- the landing rule lives in TowerPlan and is tested at every level
local function surfaceAtStand(s)
	local pt = { x0 = T.STAND.x, x1 = T.STAND.x, z0 = T.STAND.z, z1 = T.STAND.z }
	local land = T.landing(s)
	if land and inside(pt, land) then return true end
	if T.DECKS[s] or s >= 14 then return inside(pt, T.deck(s)) end
	return false
end

test("every lift stop at every level stands on a landing or a deck, and nothing above the top is a stop", function()
	for level = 2, W.MAX do
		local top = T.topStorey(W.PIECES, level)
		for s = 0, T.TOP do
			local stop = T.landable(W.PIECES, level, s)
			if stop then
				assert(s <= top, ("level %d: storey %d is a stop above the top storey %d"):format(level, s, top))
				assert(surfaceAtStand(s), ("level %d: storey %d is a stop with nothing under the stand"):format(level, s))
			end
		end
		assert(T.landable(W.PIECES, level, 0), ("level %d: the lobby is not a stop"):format(level))
	end
	-- the crown pieces (halo, lantern, mast) never make storey 15 a stop
	assert(not T.landable(W.PIECES, W.MAX, 15), "the crown storey became a stop")
	assert(T.topStorey(W.PIECES, W.MAX) == 14, "the top storey at 100 is the roof garden")
end)

-- I1 -- the Servers room's racks and fans stay inside the glass band of the smallest room
test("the server racks stand inside the glass band in every room (they poked 0.6 out of the facade)", function()
	local R = require("../../src/ReplicatedStorage/ServerRack")
	for _, pc in ipairs(W.PIECES) do
		if pc.kind == "segment" then
			local r = T.room(pc.storey, pc.seg)
			local lim = T.inner(r)
			local rm = R.midlineFor(lim.z)
			local back = rm + R.BACK + R.SLOT.Z / 2
			assert(back <= lim.z + 1e-6, ("L%d: rack back %.2f past the glass band %.2f"):format(pc.level, back, lim.z))
			assert(rm + R.BACK - R.SLOT.Z / 2 >= -r.d / 2, ("L%d: the racks left the room"):format(pc.level))
			for _, x in ipairs(R.XS) do
				assert(math.abs(x) + R.SLOT.X / 2 <= lim.x + 1e-6, ("L%d: rack at x %d past the side band"):format(pc.level, x))
			end
			assert(T.fanZ(r) + 0.35 / 2 <= r.d / 2 - T.WALL_T + 1e-6, ("L%d: the fan is in the glass"):format(pc.level))
		end
	end
end)

-- I4 -- a room's door toward a cell that is not built yet is glazed until that cell is built
test("no built room above the lobby has a door open to an unbuilt room, at any level", function()
	local levelAt = {}
	for _, pc in ipairs(W.PIECES) do
		if pc.kind == "segment" then levelAt[pc.storey .. ":" .. pc.seg] = pc.level end
	end
	for level = 2, W.MAX do
		for L = 2, level do
			local pc = W.PIECES[L]
			if pc.kind == "segment" and pc.storey >= 1 then
				local edges = T.edges(W.PIECES, L)
				local r = T.room(pc.storey, pc.seg)
				for side, kind in pairs(r.sides) do
					if kind == 6 then
						local nseg = T.neighbour(pc.seg, side)
						assert(nseg, ("L%d: a 6-stud door on %s with no neighbour"):format(L, side))
						local M = levelAt[pc.storey .. ":" .. nseg]
						if not M or M > level then
							assert(edges[side] and edges[side] == (M or math.huge),
								("level %d: L%d's %s door is open to an unbuilt room"):format(level, L, side))
						end
					end
				end
			end
		end
	end
end)

return TT
