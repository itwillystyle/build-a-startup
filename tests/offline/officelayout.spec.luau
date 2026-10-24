-- officelayout.spec.luau: the tower offices as data (24 Oct 2026, art pass 4). Plan:
-- silicon-startup/docs/superpowers/plans/2026-10-23-art-pass-4-tower-interiors.md
local fs = require("@lune/fs")
local T = require("../../src/ReplicatedStorage/TowerPlan")
local SR = require("../../src/ReplicatedStorage/ServerRack")
local OL = require("../../src/ReplicatedStorage/OfficeLayout").with(T, SR)
local TT = {}
local function test(name, fn) table.insert(TT, { name = name, fn = fn }) end
local function near(a, b) return math.abs(a - b) < 1e-6 end

local function only(list, kind)
	local out = {}
	for _, p in ipairs(list) do if p.kind == kind then table.insert(out, p) end end
	return out
end
local function find(list, key, x, z)
	for _, p in ipairs(list) do
		if p.key == key and near(p.x, x) and near(p.z, z) then return p end
	end
	return nil
end

-- ---------------------------------------------------------------- Task 2: today's furniture, exactly
local ROOMS = { { 1, 1 }, { 1, 3 }, { 0, 1 } }

test("eng and labs: two workstations by the window, one monitor each, seats facing out", function()
	for _, rs in ipairs(ROOMS) do
		local r = T.room(rs[1], rs[2])
		for _, dept in ipairs({ "eng", "labs" }) do
			local ws = only(OL.furniture(dept, r, 1), "workstation")
			assert(#ws == 2, dept .. ": two workstations")
			for i, x in ipairs({ -5.5, 5.5 }) do
				assert(near(ws[i].x, x) and near(ws[i].z, r.d / 2 - 4) and ws[i].yaw == 180 and ws[i].monitors == 1,
					("%s desk %d at %.2f, %.2f yaw %s"):format(dept, i, ws[i].x, ws[i].z, tostring(ws[i].yaw)))
			end
			local seats = OL.seats(dept, r)
			assert(#seats == 2, dept .. ": two seats")
			for i, x in ipairs({ -5.5, 5.5 }) do
				local s = seats[i]
				assert(near(s.x, x - 0.3) and near(s.z, r.d / 2 - 6.6) and near(s.lookX, x - 0.3) and near(s.lookZ, r.d / 2 - 6.6 + 5),
					dept .. ": seat " .. i)
			end
		end
	end
end)

test("lobby: two workstations a quarter in, and the sofa on the back wall's right half", function()
	local r = T.room(0, 1)
	local f = OL.furniture("lobby", r, 1)
	local ws = only(f, "workstation")
	assert(#ws == 2 and near(ws[1].x, -r.w / 4) and near(ws[2].x, r.w / 4), "the lobby desks")
	assert(find(f, "loungeSofa", T.LOBBY_SOFA.x, -r.d / 2 + T.LOBBY_SOFA.zFromBack), "the sofa")
	assert(#OL.seats("lobby", r) == 2, "two lobby seats")
end)

test("studio: the cross table and two chairs, seats looking at the table", function()
	local r = T.room(1, 1)
	local f = OL.furniture("studio", r, 1)
	assert(find(f, "tableCross", 0, 0), "the table")
	local a, b = find(f, "chairModernCushion", -3.7, 0.4), find(f, "chairModernCushion", 3.7, 0.4)
	assert(a and a.yaw == 90 and b and b.yaw == -90, "the chairs face the table")
	local seats = OL.seats("studio", r)
	assert(#seats == 2, "two seats")
	for i, x in ipairs({ -3.7, 3.7 }) do
		assert(near(seats[i].x, x) and near(seats[i].z, 0.4) and near(seats[i].lookX, 0) and near(seats[i].lookZ, 0.4), "studio seat " .. i)
	end
end)

test("cafe: the round table (solid) and four chairs round it, seats looking at its centre", function()
	local r = T.room(1, 1)
	local f = OL.furniture("cafe", r, 1)
	local t = find(f, "tableRound", 0, 0)
	assert(t and t.canCollide == true, "the table, solid")
	local want = { { 0, 2.6, 180 }, { 0, -2.6, 0 }, { 2.4, 0, -90 }, { -2.4, 0, 90 } }
	local seats = OL.seats("cafe", r)
	assert(#seats == 4, "four seats")
	for i, o in ipairs(want) do
		local c = find(f, "chairModernCushion", o[1], o[2])
		assert(c and c.yaw == o[3], "cafe chair " .. i)
		assert(near(seats[i].x, o[1]) and near(seats[i].z, o[2]) and near(seats[i].lookX, 0) and near(seats[i].lookZ, 0), "cafe seat " .. i)
	end
end)

test("servers: the racks on the glass band (a doorway where a terrace door is), two fans, no seats", function()
	for _, rs in ipairs({ { 1, 1 }, { 3, 1 }, { 1, 3 } }) do
		local r = T.room(rs[1], rs[2])
		local f = OL.furniture("servers", r, 1)
		local racks = only(f, "racks")
		assert(#racks == 1 and near(racks[1].rm, SR.midlineFor(T.inner(r).z)), "the racks' midline")
		assert(racks[1].doorway == (r.terraceDoor ~= nil), "the doorway follows the terrace door")
		local fans = only(f, "fan")
		assert(#fans == 2, "two fans")
		for i, x in ipairs({ -9, 9 }) do
			assert(near(fans[i].x, x) and near(fans[i].y, 6.2) and near(fans[i].z, T.fanZ(r)), "fan " .. i)
		end
		assert(#OL.seats("servers", r) == 0, "no seats")
	end
end)

test("board: two cross tables side by side, no seats", function()
	local r = T.room(1, 1)
	local f = OL.furniture("board", r, 1)
	assert(find(f, "tableCross", -2.2, 0) and find(f, "tableCross", 2.2, 0), "two tables")
	assert(#OL.seats("board", r) == 0, "no seats")
end)

test("the footprint sizes OfficeLayout checks with are FurnitureKit's own", function()
	local src = fs.readFile("src/ReplicatedStorage/FurnitureKit.lua")
	for key, sz in pairs(OL.SIZE) do
		local x, y, z = src:match("\n%s*" .. key .. "%s*=%s*Vector3%.new%(([%d%.]+),%s*([%d%.]+),%s*([%d%.]+)%)")
		assert(x, key .. " is not in FurnitureKit's SIZE")
		assert(near(tonumber(x), sz[1]) and near(tonumber(y), sz[2]) and near(tonumber(z), sz[3]), key .. " differs from FurnitureKit")
	end
end)

return TT
