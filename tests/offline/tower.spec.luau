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

test("heights: a 24-stud lobby storey, then 18; a garden storey has none (the floor above stands on its deck)", function()
	assert(T.storeyH(0) == 24 and T.storeyH(1) == 18 and T.storeyH(13) == 18, "storey heights")
	for d in pairs(T.DECKS) do
		assert(T.storeyH(d) == 0, "garden storey " .. d .. " still has height: it reads as a missing floor")
		assert(T.floorY(d) == T.floorY(d + 1), "floor " .. (d + 1) .. " does not stand on deck " .. d)
	end
	assert(T.floorY(0) == 1.0 and T.floorY(1) == 25 and T.floorY(2) == 43 and T.floorY(3) == 43, "floor tops")
	assert(T.floorY(14) == 25 + 10 * 18, ("the roof is at %g, want %g (10 office storeys above the lobby)"):format(T.floorY(14), 25 + 10 * 18))
end)

test("terraces: each storey above a garden stands inside the deck, leaving a terrace 6+ deep on its step-back side", function()
	local sideOf = { [2] = "front", [6] = "back", [10] = "front" }
	for d in pairs(T.DECKS) do
		local deck, up = T.deck(d), T.rect(d + 1)
		assert(inside({ x0 = -up.hx, x1 = up.hx, z0 = up.zb, z1 = up.zf }, deck), "storey " .. (d + 1) .. " overhangs deck " .. d)
		local depth = sideOf[d] == "front" and (deck.z1 - up.zf) or (up.zb - deck.z0)
		assert(depth >= 6, ("deck %d's %s terrace is only %.1f deep"):format(d, sideOf[d], depth))
		local t = T.terraces(d)
		assert(t[sideOf[d]] and math.abs(t[sideOf[d]].depth - depth) < 1e-6, "terraces() must report the " .. sideOf[d] .. " strip")
	end
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
	-- the mock's base is 70 wide under 52-wide floors (1.35x); at 1.2x it read as a skirt (shape review 2)
	assert(p.hx / a.hx >= 1.35, ("the podium is only %.2fx floor 1's width; the mock's is 1.35x"):format(p.hx / a.hx))
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
	local spots = T.GARAGE_SPOTS
	assert(#spots == 6, "the six measured spots")
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
	assert(T.label(0) == "LOBBY" and T.label(2) == "SKY GARDEN" and T.label(14) == "ROOF GARDEN" and T.label(4) == "FLOOR 4", "labels")
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
	if T.DECKS[s - 1] then return inside(pt, T.deck(s - 1)) end   -- the floor above a garden stands on its deck
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
	-- a garden is not a stop of its own: the floor above it is, as soon as the deck is built (level 18 = deck 2)
	for d in pairs(T.DECKS) do
		for level = 2, W.MAX do assert(not T.landable(W.PIECES, level, d), ("level %d: garden %d is a stop"):format(level, d)) end
	end
	assert(T.landable(W.PIECES, 18, 3), "deck 2 is built (level 18) but floor 3 is not a stop")
	assert(T.label(3) == "FLOOR 3 · TERRACE" and T.label(2) == "SKY GARDEN", "labels: " .. T.label(3) .. " / " .. T.label(2))
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

-- DECOR in the tower (final review I3): from level 2 the garage floor is gone, so decor stands on the
-- lobby storey: any built ground-floor room, and the centre hall around the lift shaft
test("decor floors: the lobby storey's built rooms and the hall, never the shaft; the garage floor before the tower", function()
	assert(T.decorRects(W.PIECES, 1) == nil, "level 1 has no tower: decor stays on the garage floor")
	for _, level in ipairs({ 2, 5, 9, 43, 100 }) do
		local rects = T.decorRects(W.PIECES, level)
		assert(rects and #rects > 0, "no decor floor at level " .. level)
		local floors = { T.centre(0) }
		for L = 2, level do
			local pc = W.PIECES[L]
			if pc.kind == "segment" and pc.storey == 0 then table.insert(floors, T.room(0, pc.seg)) end
		end
		for i, r in ipairs(rects) do
			assert(r.x1 > r.x0 and r.z1 > r.z0, "empty rect " .. i)
			assert(not overlap(r, T.SHAFT), ("level %d: decor rect %d is in the lift shaft"):format(level, i))
			local on = false
			for _, f in ipairs(floors) do if inside(r, f) then on = true break end end
			assert(on, ("level %d: decor rect %d is not on a built floor of the lobby storey"):format(level, i))
		end
	end
	-- a built room's decor stays clear of its walls
	local lobby = T.room(0, 1)
	for _, r in ipairs(T.decorRects(W.PIECES, 2)) do
		if inside(r, lobby) then
			assert(r.x0 >= lobby.x0 + T.WALL_T and r.x1 <= lobby.x1 - T.WALL_T and r.z0 >= lobby.z0 + T.WALL_T and r.z1 <= lobby.z1 - T.WALL_T,
				"decor rect touches the lobby's walls")
		end
	end
end)

-- final review 2, I1: a terrace you cannot reach is not a terrace. The middle room of the row that
-- stands behind each terrace has a glass door onto it.
test("terraces are reachable: the middle room of the row above each garden has a glass door onto it", function()
	local want = { [2] = { seg = 1, side = "pz" }, [6] = { seg = 5, side = "nz" }, [10] = { seg = 1, side = "pz" } }
	for d, w in pairs(want) do
		local r = T.room(d + 1, w.seg)
		assert(r.terraceDoor == w.side, ("storey %d seg %d has no %s terrace door"):format(d + 1, w.seg, w.side))
		local strip = T.terraces(d)[(w.side == "pz") and "front" or "back"]
		assert(strip and r.cx - 3 >= strip.x0 and r.cx + 3 <= strip.x1, "the door does not open onto the terrace strip")
	end
	for st = 0, 13 do
		for seg = 1, 8 do
			local r = T.room(st, seg)
			local w = want[st - 1]
			if r.terraceDoor then assert(w and w.seg == seg, ("storey %d seg %d has a stray terrace door"):format(st, seg)) end
		end
	end
	assert(T.room(0, 1).entrance and T.room(0, 1).entrance.side == "pz" and T.room(0, 1).entrance.width == 14, "the lobby's entrance")
end)

-- final review 2, I2-I4: decor keeps the lift landing, the garage spots and every doorway clear, and
-- the spots real saves already use stay valid (Wilz's 8 plants, measured live 14 Oct, plot-local)
local function box(x, z, s) s = s or 1.5; return { x0 = x - s / 2, x1 = x + s / 2, z0 = z - s / 2, z1 = z + s / 2 } end
test("decor keeps the landing, the garage spots and the doorways clear, and the saved plants still fit", function()
	assert(T.decorOk(W.PIECES, 1, box(0, 0)) == nil, "level 1: no tower, the garage floor decides")
	local L = 55
	for i, p in ipairs({ { -1.5, 4.3 }, { 4.0, 4.0 }, { 7.5, 8.9 }, { 3.7, 9.4 }, { -6.5, 3.7 }, { -11.6, 9.0 }, { -10.8, 10.3 }, { -5.5, 9.5 } }) do
		assert(T.decorOk(W.PIECES, L, box(p[1], p[2])), ("saved plant %d at (%.1f, %.1f) would be refunded"):format(i, p[1], p[2]))
	end
	assert(not T.decorOk(W.PIECES, L, box(T.STAND.x, T.STAND.z)), "decor on the lift landing")
	assert(not T.decorOk(W.PIECES, L, box(9, -7)), "decor in the shaft")
	for i, s in ipairs(T.GARAGE_SPOTS) do
		assert(not T.decorOk(W.PIECES, L, box((s.x0 + s.x1) / 2, (s.z0 + s.z1) / 2, 1)), "decor on garage spot " .. i)
	end
	local hall, lobby = T.centre(0), T.room(0, 1)
	assert(not T.decorOk(W.PIECES, L, box(0, hall.z1 - 1, 1)), "decor in the hall-to-lobby doorway")
	assert(not T.decorOk(W.PIECES, L, box(0, lobby.z1 - 1.5, 1)), "decor in the entrance")
	assert(not T.decorOk(W.PIECES, L, box(lobby.x1 - 0.3, lobby.cz, 0.4)), "decor in a wall")
	-- the rooms and the hall are really usable, not one sliver
	assert(T.decorOk(W.PIECES, L, box(lobby.x0 + 6, lobby.cz)), "decor in the lobby room")
	assert(T.decorOk(W.PIECES, L, box(hall.x0 + 4, hall.z0 + 4)), "decor in the hall's back corner")
	local side = T.room(0, 3)
	assert(T.decorOk(W.PIECES, L, box(side.cx, side.cz + 6)), "decor in a side room")
	assert(not T.decorOk(W.PIECES, 2, box(side.cx, side.cz + 6)), "decor in a room that is not built yet (level 2)")
end)

-- 1b: the lift's shaft is open from the lobby to the roof; landings and decks stop at it
local function area(r) return (r.x1 - r.x0) * (r.z1 - r.z0) end
test("landings and decks stop at the shaft and cover everything else", function()
	local sh = T.SHAFT
	for s = 0, 14 do
		local whole = T.landing(s) or ((T.DECKS[s] or s >= 14) and T.deck(s)) or nil
		local rects = T.landing(s) and T.landingRects(s) or T.deckRects(s)
		if whole then
			local sum = 0
			for _, r in ipairs(rects) do
				assert(not overlap(r, sh), ("storey %d: a slab over the shaft"):format(s))
				assert(inside(r, whole), ("storey %d: a slab outside its floor"):format(s))
				sum += area(r)
			end
			assert(math.abs(sum - (area(whole) - area(sh))) < 1e-6, ("storey %d: the slabs do not cover the floor minus the shaft"):format(s))
		end
	end
end)

test("the cab fits the shaft, its door faces the landing, and the roof stop opens onto the roof", function()
	local c, sh = T.CAB, T.SHAFT
	assert(c.x - c.w / 2 > sh.x0 + 0.39 and c.x + c.w / 2 < sh.x1 - 0.39, "the cab clears the shaft's side walls")
	assert(c.z - c.d / 2 > sh.z0 + 0.39 and c.z + c.d / 2 <= sh.z1, "the cab clears the back wall and reaches the door line")
	assert(c.door <= sh.x1 - sh.x0 - 0.8 and c.doorH < T.storeyH(1), "the door fits")
	local l = T.lantern()
	local stand = { x0 = T.STAND.x - 1, x1 = T.STAND.x + 1, z0 = T.STAND.z - 1, z1 = T.STAND.z + 1 }
	assert(overlap(l, stand), "precondition: the crown's lantern covers the roof stop's stand point")
	assert(T.LANTERN_SOLID == false, "so the lantern must not be solid (it enclosed the roof door, 1a review Minor 4)")
end)

test("the trophy panel's 12 slots fit the cab's side wall in two columns, from the bottom", function()
	local C = T.CAB
	local seen = {}
	for i = 1, 12 do
		local p = T.panelSlot(i)
		assert(p.y >= 1.5 and p.y <= C.h - 2, ("slot %d height %.2f"):format(i, p.y))
		assert(math.abs(p.z) <= C.d / 2 - 1.2, ("slot %d off the wall"):format(i))
		local key = ("%.2f:%.2f"):format(p.y, p.z)
		assert(not seen[key], "two slots in one place")
		seen[key] = true
	end
	assert(T.panelSlot(1).y < T.panelSlot(3).y, "the lobby is at the bottom")
end)

test("1c: the garage chair stands clear of the lift shaft and the cab", function()
	local c = T.GARAGE_CHAIR
	local r = 1.45   -- a 2 x 2 seat turned 28 degrees reaches about 1.4 studs from its centre
	local s = T.SHAFT
	assert(c.x + r < s.x0 - 0.2 or c.z + r < s.z0 - 0.2 or c.z - r > s.z1 + 0.2, "the chair's footprint misses the shaft")
	local spot = T.GARAGE_SPOTS[2]
	assert(c.x > spot.x0 and c.x < spot.x1 and c.z > spot.z0 and c.z < spot.z1, "it stands on the chair spot decor keeps clear")
	assert(T.GARAGE_KEEP.Chair and T.GARAGE_KEEP.Laptop and T.GARAGE_KEEP.HQPad and T.GARAGE_KEEP.Spawn, "the working parts are kept")
end)

test("1c: the photo and the TV hang on the lobby's hall-side wall, clear of its door, the shaft and each other", function()
	local room = T.room(0, 1)
	local door = room.sides.nz
	assert(type(door) == "number", "the lobby room has a door to the hall")
	local hall = T.centre(0)
	local items = { T.WALL_ART.photo, T.WALL_ART.tv }
	for _, a in ipairs(items) do
		assert(math.abs(a.x) - a.w / 2 >= door / 2 + 0.5, "clear of the door")
		assert(a.x - a.w / 2 >= hall.x0 + 1 and a.x + a.w / 2 <= hall.x1 - 1, "inside the hall's width")
		assert(a.x + a.w / 2 <= T.SHAFT.x0 or a.x - a.w / 2 >= T.SHAFT.x1, "not in front of the shaft")
		assert(a.y0 >= 2 and a.y1 <= T.LOBBY_H - 2 and a.y0 < a.y1, "on the wall, below the ceiling")
	end
	local p, tv = T.WALL_ART.photo, T.WALL_ART.tv
	assert(p.x + p.w / 2 <= tv.x - tv.w / 2 or tv.x + tv.w / 2 <= p.x - p.w / 2, "the photo and the TV do not overlap")
end)

return TT
