-- officelayout.spec.luau: the tower offices as data (24 Oct 2026, art pass 4). Plan:
-- silicon-startup/docs/superpowers/plans/2026-10-23-art-pass-4-tower-interiors.md
local fs = require("@lune/fs")
-- Palette reads CollectionService at load; Lune has no `game`, so a stand-in answers HasTag (palette.spec)
-- selene: allow(incorrect_standard_library_use)
game = game or { GetService = function() return { HasTag = function() return false end } end }
local Palette = require("../../src/ReplicatedStorage/Palette")
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

-- ---------------------------------------------------------------- Task 3: the surfaces
local function c3(rgb) return Color3.fromRGB(rgb[1], rgb[2], rgb[3]) end
local function rgbOf(c) return { math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255) } end

test("every office colour is on the palette and maps onto itself (no new anchors)", function()
	assert(type(OL.COLORS) == "table", "OfficeLayout.COLORS is missing")
	for name, rgb in pairs(OL.COLORS) do
		local got = rgbOf(Palette.map(c3(rgb)))
		assert(got[1] == rgb[1] and got[2] == rgb[2] and got[3] == rgb[3],
			("%s %d,%d,%d maps to %d,%d,%d"):format(name, rgb[1], rgb[2], rgb[3], got[1], got[2], got[3]))
	end
	for _, name in ipairs({ "navy", "navyDeep" }) do
		local ok, anchor = Palette.compliant(c3(OL.COLORS[name]))
		assert(ok and anchor == "ValleyBlue", name .. " must sit in the ValleyBlue family, not turn slate (the mock's own navies do)")
	end
	local f = OL.COLORS.floor
	local lum = (0.2126 * f[1] + 0.7152 * f[2] + 0.0722 * f[3]) / 255
	assert(lum <= 0.80, ("the floor's luminance is %.2f: a near-white floor is what blew the old shots out"):format(lum))
	assert(OL.COLORS.coral[1] == 236 and OL.COLORS.coral[2] == 104 and OL.COLORS.coral[3] == 84, "Coral is the accent anchor exactly")
end)

test("surfaces: the lobby only gets the floor, servers a navy wall with no base, the rest oak over a navy base", function()
	local C = OL.COLORS
	local lobby = OL.surfaces("lobby")
	assert(lobby.floor == C.floor and lobby.back == nil and lobby.base == nil, "the lobby keeps its walls (ruling 4)")
	local sv = OL.surfaces("servers")
	assert(sv.floor == C.floor and sv.back == C.navyDeep and sv.base == nil, "servers: a dark navy wall, nothing else")
	for _, d in ipairs({ "eng", "labs", "studio", "cafe", "board" }) do
		local s = OL.surfaces(d)
		assert(s.floor == C.floor and s.back == C.oak and s.base == C.navy, d .. ": oak over navy")
	end
end)

-- ---------------------------------------------------------------- Task 4: the dressing
local DEPTS = { "eng", "studio", "cafe", "servers", "labs", "board" }
local function eachRoom(fn)
	for s = 0, 13 do
		if not T.DECKS[s] then
			for seg = 1, 8 do
				local depts = (s == 0 and seg == 1) and { "lobby" } or DEPTS
				for _, d in ipairs(depts) do fn(s, seg, T.room(s, seg), d) end
			end
		end
	end
end

test("nothing the dressing adds blocks a door, a seat, the station or the glass, at company 12 and 13", function()
	assert(type(OL.check) == "function" and type(OL.dressing) == "function", "OfficeLayout.check / dressing are missing")
	local bad = {}
	eachRoom(function(s, seg, r, d)
		for _, company in ipairs({ 12, 13 }) do
			for _, problem in ipairs(OL.check(d, r, company, s, seg)) do
				table.insert(bad, ("storey %d seg %d %s @%d: %s"):format(s, seg, d, company, problem))
			end
		end
	end)
	assert(#bad == 0, #bad .. " problems: " .. table.concat(bad, " | ", 1, math.min(#bad, 12)))
end)

test("check() is not blind: a plant in the back door, on a seat and behind the station are all caught", function()
	local r = T.room(1, 3)
	local seat = OL.seats("eng", r)[1]
	local function with(extra)
		local list = OL.dressing("eng", r, 13, 1, 3)
		table.insert(list, extra)
		return OL.check("eng", r, 13, 1, 3, list)
	end
	local plant = function(x, z) return { id = "PlantX", kind = "plant", key = "pottedPlant", x = x, z = z, yaw = 0, parts = 1 } end
	assert(#with(plant(0, -r.d / 2 + 1.5)) > 0, "a plant in the back door")
	assert(#with(plant(seat.x, seat.z)) > 0, "a plant on a seat")
	assert(#with(plant(OL.STATION.x(r), OL.STATION.z(r) + 1.6)) > 0, "a plant in front of the station")
	assert(#with(plant(r.w / 2, 0)) > 0, "a plant through the glass band")
	assert(#with({ id = "WallArt", kind = "art", x = 0, y0 = 5.5, y1 = 8.9, w = 4.5, parts = 1 }) > 0, "art over the door")
end)

test("the budget: at most 12 new parts a room and 96 a storey; an engineering room at 13 uses exactly 12", function()
	eachRoom(function(s, seg, r, d)
		for _, company in ipairs({ 12, 13 }) do
			local n = OL.newParts(d, r, company, s, seg)
			assert(n <= OL.BUDGET, ("storey %d seg %d %s @%d: %d new parts"):format(s, seg, d, company, n))
		end
	end)
	for s = 0, 13 do
		if not T.DECKS[s] then
			local sum = 0
			for seg = 1, 8 do sum += OL.newParts((s == 0 and seg == 1) and "lobby" or "eng", T.room(s, seg), 13, s, seg) end
			assert(sum <= OL.STOREY_BUDGET, ("storey %d: %d new parts if every room were engineering"):format(s, sum))
		end
	end
	assert(OL.newParts("eng", T.room(1, 3), 13, 1, 3) == 12, "eng at company 13: rug 2, base 2, art 1, plants 3, second monitors 4")
	assert(OL.newParts("eng", T.room(1, 3), 12, 1, 3) == 7, "eng at company 12: no third plant, one monitor")
end)

test("the lobby gets nothing, servers nothing, storey 0 no plants; every flat or wall piece is FLAT_NAMES", function()
	assert(#OL.dressing("lobby", T.room(0, 1), 100, 0, 1) == 0, "the lobby keeps its look (ruling 4)")
	assert(#OL.dressing("servers", T.room(1, 3), 100, 1, 3) == 0, "a server room is a machine room (ruling 7)")
	eachRoom(function(s, seg, r, d)
		for _, p in ipairs(OL.dressing(d, r, 13, s, seg)) do
			if s == 0 then assert(p.kind ~= "plant", ("storey 0 seg %d %s: a plant would refund saved decor (ruling 5)"):format(seg, d)) end
			if p.kind ~= "plant" then assert(OL.FLAT_NAMES[p.id], p.id .. " is flat or on the wall but not in FLAT_NAMES") end
		end
	end)
end)

test("by company level (ruling 1): 12 is one monitor and two plants; 13 two monitors and a third plant", function()
	local r = T.room(1, 1)
	local function plants(company)
		local n = 0
		for _, p in ipairs(OL.dressing("eng", r, company, 1, 1)) do if p.kind == "plant" then n += 1 end end
		return n
	end
	assert(plants(12) == 2 and plants(13) == 3 and plants(100) == 3, "the third plant arrives at 13")
	assert(only(OL.furniture("eng", r, 12), "workstation")[1].monitors == 1, "one monitor at 12")
	assert(only(OL.furniture("labs", r, 13), "workstation")[1].monitors == 2, "two monitors at 13")
	assert(OL.monitorsAt(nil) == 1 and OL.monitorsAt(13) == 2, "monitorsAt")
end)

test("two monitors fit the desk (half width 2.16) side by side, turned in toward the seat", function()
	local one = OL.monitorSlots(1)
	assert(#one == 1 and one[1].x == 0 and one[1].yaw == 0 and one[1].scale == 1, "one monitor is today's slot")
	local two = OL.monitorSlots(2)
	assert(#two == 2, "two slots")
	local sz = OL.SIZE.computerScreen
	local function corners(sl)
		local w, d = sz[1] * sl.scale / 2, sz[3] * sl.scale / 2
		local a = math.rad(sl.yaw)
		local out = {}
		for _, c in ipairs({ { -w, -d }, { w, -d }, { w, d }, { -w, d } }) do
			table.insert(out, { sl.x + c[1] * math.cos(a) + c[2] * math.sin(a), -c[1] * math.sin(a) + c[2] * math.cos(a) })
		end
		return out
	end
	for _, sl in ipairs(two) do
		for _, c in ipairs(corners(sl)) do assert(math.abs(c[1]) <= 2.16, ("a monitor corner at x %.3f is off the desk"):format(c[1])) end
	end
	-- the two do not overlap: separating axis test on their footprints
	local A, B = corners(two[1]), corners(two[2])
	local function proj(poly, ax)
		local lo, hi = math.huge, -math.huge
		for _, p in ipairs(poly) do local v = p[1] * ax[1] + p[2] * ax[2]; lo, hi = math.min(lo, v), math.max(hi, v) end
		return lo, hi
	end
	local apart = false
	for _, poly in ipairs({ A, B }) do
		for k = 1, 4 do
			local p, q = poly[k], poly[k % 4 + 1]
			local ax = { q[2] - p[2], p[1] - q[1] }
			local a0, a1 = proj(A, ax)
			local b0, b1 = proj(B, ax)
			if a1 < b0 or b1 < a0 then apart = true end
		end
	end
	assert(apart, "the two monitors overlap")
	assert(two[1].x < 0 and two[1].yaw > 0 and two[2].x > 0 and two[2].yaw < 0, "each is turned in toward the middle")
end)

test("Wafers keeps saved decor clear of the flat pieces only, and its station is where check() thinks", function()
	local src = fs.readFile("src/ServerScriptService/Wafers.lua")
	assert(src:find("OfficeLayout.FLAT_NAMES", 1, true), "Wafers' CLEAR_OF must take OfficeLayout.FLAT_NAMES")
	assert(src:find("CFrame.new(-r.w / 2 + 3, SLAB + 2.2, -r.d / 2 + 3)", 1, true), "the station moved: update OfficeLayout.STATION")
	assert(src:find("Vector3.new(3.2, 4.4, 1.8)", 1, true), "the station's size changed: update OfficeLayout.STATION")
	local r = T.room(1, 3)
	assert(near(OL.STATION.x(r), -r.w / 2 + 3) and near(OL.STATION.z(r), -r.d / 2 + 3) and OL.STATION.w == 3.2 and OL.STATION.d == 1.8, "STATION")
end)

-- ---------------------------------------------------------------- Task 5: far rooms cost nothing
test("the cull: a band so it never flickers, near enough that your own room never hides, far enough to pay", function()
	local C = OL.CULL
	assert(type(C) == "table" and C.near < C.far, "CULL.near must be below CULL.far")
	local diag = 0
	for s = 0, 13 do
		if not T.DECKS[s] then
			for seg = 1, 8 do
				local r = T.room(s, seg)
				diag = math.max(diag, math.sqrt(r.w ^ 2 + r.d ^ 2))
			end
		end
	end
	-- 60 = how far the camera may stand from its player (an assumption: the zoom limit is not measured)
	assert(C.near >= diag + 60, ("near %d is under the biggest room's diagonal %.1f + 60"):format(C.near, diag))
	-- the 1d plaza camera (eye at plot -60, 18, 230) to the podium's front: every room is farther than this
	local plaza = 230 - T.rect(0).zf
	assert(C.far < plaza, ("far %d must be under the plaza camera's %.0f, or the plaza view pays for every room"):format(C.far, plaza))
	assert(table.find(C.tags, "SVDressing") and table.find(C.tags, "SVRoomKit"), "the dressing and today's furniture (ruling 8)")
end)

test("cullNext: hides past far, shows inside near, and holds its state in the band", function()
	local C = OL.CULL
	assert(OL.cullNext(false, C.far + 1) == true, "past far: hide")
	assert(OL.cullNext(true, C.near - 1) == false, "inside near: show")
	assert(OL.cullNext(true, (C.near + C.far) / 2) == true and OL.cullNext(false, (C.near + C.far) / 2) == false, "the band holds")
end)

return TT
