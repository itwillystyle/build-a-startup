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

test("setbacks: front, back, front at the three garden storeys", function()
	local A, B, C, D = T.SECTIONS[1], T.SECTIONS[2], T.SECTIONS[3], T.SECTIONS[4]
	assert(B.zf < A.zf and B.zb == A.zb, "deck 2 steps the front back")
	assert(C.zb > B.zb and C.zf == B.zf, "deck 6 steps the back in")
	assert(D.zf < C.zf and D.zb == C.zb, "deck 10 steps the front back")
	for d, below in pairs(T.DECKS) do
		local r = T.deck(d)
		local sec = T.SECTIONS[below]
		assert(r.x0 == -sec.hx and r.x1 == sec.hx and r.z0 == sec.zb and r.z1 == sec.zf, "deck " .. d .. " = the section below")
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
		{ x0 = -2.5, x1 = 2.5, z0 = -10.5, z1 = -7.5 },     -- the WRITE CODE desk at (0, -9)
		{ x0 = -14.5, x1 = -7.5, z0 = 0.5, z1 = 7.5 },      -- the hire pad, 7x7 at (-11, 4)
		{ x0 = 10, x1 = 16, z0 = 5, z1 = 11 },               -- the build pad, 6x6 at (13, 8)
		{ x0 = -1, x1 = 1, z0 = -1, z1 = 1 },                -- the spawn at (0, 0)
	}
	for i, s in ipairs(spots) do assert(not overlap(s, T.SHAFT), "spot " .. i .. " is in the shaft") end
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

test("silhouette: spec() round-trips through parseSpec, one box per section plus the crown", function()
	local boxes = T.parseSpec(T.spec())
	assert(#boxes == #T.SECTIONS + 1, "boxes: " .. #boxes)
	assert(boxes[1].x0 == -T.SECTIONS[1].hx and boxes[1].y0 == T.floorY(0) - T.SLAB, "first box")
	assert(#T.parseSpec("junk") == 0 and #T.parseSpec(nil) == 0, "bad input gives nothing")
end)

return TT
