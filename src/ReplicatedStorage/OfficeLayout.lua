--[[ OfficeLayout (24 Oct 2026, art pass 4): the HQ tower's office rooms, as data. Pure.

	Luke's pick is ui/art-pass/tower-office.png (plan
	silicon-startup/docs/superpowers/plans/2026-10-23-art-pass-4-tower-interiors.md). The garage has
	GarageLayout; this is the same idea for the tower's rooms: what stands where, in the room's own
	frame, so tests/offline/officelayout.spec can prove nothing blocks a door, a seat or the station
	before anything is built. Wafers builds the furniture from it, OfficeDress the dressing.

	The room frame: origin at the room centre on the floor top, +Z out to the facade, x across the
	room (r.w wide), z through it (r.d deep). The back wall (room -Z) is always a partition with a door.

	No pure module here requires a sibling: TowerPlan and ServerRack are passed in (LiftPlan.with). ]]
local OfficeLayout = {}

function OfficeLayout.with(T, SR)
	local OL = {}

	-- 24 Oct: the footprints this file checks with, copied from FurnitureKit's SIZE (x, y, z studs);
	-- officelayout.spec reads FurnitureKit.lua and fails if the two drift
	OL.SIZE = {
		desk = { 4.32, 2.26, 2.31 },
		chairDesk = { 1.97, 3.57, 1.85 },
		computerScreen = { 2.31, 1.73, 0.61 },
		tableRound = { 4.07, 2.16, 4.70 },
		chairModernCushion = { 1.18, 2.70, 1.18 },
		tableCross = { 5.01, 2.04, 2.63 },
		pottedPlant = { 1.25, 3.85, 1.42 },
	}

	--[[ 24 Oct (Task 3): the picked mock's surfaces, every one on a palette anchor (officelayout.spec:
		Palette.map(c) == c, no new anchors). The mock's own navies (49,80,131) and (12,35,79) map to
		slate, so these are ValleyBlue at a lower value. Oak is the anchor itself: the feature wall is
		architecture, so it is oak-COLOURED SmoothPlastic (ART.md bans Wood on buildings; ruling 2). ]]
	OL.COLORS = {
		floor = { 196, 188, 174 },     -- matte warm grey (luminance 0.74: not the blown near-white)
		oak = { 192, 138, 85 },        -- Palette Oak
		navy = { 38, 66, 108 },        -- ValleyBlue family
		navyDeep = { 26, 48, 80 },     -- ValleyBlue family, darker: the server room's wall
		coral = { 236, 104, 84 },      -- Palette Coral (an accent anchor keeps only itself)
		ink = { 30, 37, 48 },          -- Palette Ink: the art's frame
		paper = { 243, 239, 230 },     -- Palette PaperWhite: the art's mat
	}

	-- what a room's surfaces are painted: the floor everywhere; the back wall and its base by department.
	-- The lobby keeps its walls (ruling 4); servers is a machine room (ruling 7): a dark wall, no base
	function OL.surfaces(dept)
		local C = OL.COLORS
		if dept == "lobby" then return { floor = C.floor } end
		if dept == "servers" then return { floor = C.floor, back = C.navyDeep } end
		return { floor = C.floor, back = C.oak, base = C.navy }
	end

	-- the room's furniture as it stood before art pass 4 (Wafers.furnish, 23 Oct), one piece per thing:
	--   workstation  FurnitureKit.workstation (desk, monitors, keyboard, chair) at x, z, yaw (degrees)
	--   kit          FurnitureKit.onFloor(key) at x, z, yaw
	--   racks        the Servers racks (Wafers' own builder): rm = their midline, doorway = make way
	--   fan          a Servers wall fan at x, y, z (Wafers' own builder)
	-- `company` is the company's HQ level; it sets the monitors (Task 4), nil = 1
	function OL.furniture(dept, r, company)
		local out = {}
		local monitors = OL.monitorsAt and OL.monitorsAt(company) or 1
		local zOut = r.d / 2 - 4                 -- the desk row near the window
		if dept == "eng" or dept == "labs" or dept == "lobby" then
			local xs = (dept == "lobby") and { -r.w / 4, r.w / 4 } or { -5.5, 5.5 }
			for i, x in ipairs(xs) do
				table.insert(out, { id = "Desk" .. i, kind = "workstation", x = x, z = zOut, yaw = 180, monitors = monitors })
			end
			if dept == "lobby" then
				table.insert(out, { id = "Sofa", kind = "kit", key = "loungeSofa", x = T.LOBBY_SOFA.x, z = -r.d / 2 + T.LOBBY_SOFA.zFromBack, yaw = 0 })
			end
		elseif dept == "studio" then
			table.insert(out, { id = "Table", kind = "kit", key = "tableCross", x = 0, z = 0, yaw = 0 })
			table.insert(out, { id = "ChairL", kind = "kit", key = "chairModernCushion", x = -3.7, z = 0.4, yaw = 90 })
			table.insert(out, { id = "ChairR", kind = "kit", key = "chairModernCushion", x = 3.7, z = 0.4, yaw = -90 })
		elseif dept == "cafe" then
			table.insert(out, { id = "Table", kind = "kit", key = "tableRound", x = 0, z = 0, yaw = 0, canCollide = true })
			for i, o in ipairs({ { 0, 2.6, 180 }, { 0, -2.6, 0 }, { 2.4, 0, -90 }, { -2.4, 0, 90 } }) do
				table.insert(out, { id = "Chair" .. i, kind = "kit", key = "chairModernCushion", x = o[1], z = o[2], yaw = o[3] })
			end
		elseif dept == "servers" then
			-- the racks' backs on the glass band, the fans just inside the glass (Wafers final review I1)
			table.insert(out, { id = "Racks", kind = "racks", x = 0, z = 0, yaw = 0, rm = SR.midlineFor(T.inner(r).z), doorway = r.terraceDoor ~= nil })
			for i, x in ipairs({ -9, 9 }) do
				table.insert(out, { id = "Fan" .. i, kind = "fan", x = x, y = 6.2, z = T.fanZ(r), yaw = 0, size = 3.0, rpm = 170 })
			end
		elseif dept == "board" then
			table.insert(out, { id = "TableL", kind = "kit", key = "tableCross", x = -2.2, z = 0, yaw = 0 })
			table.insert(out, { id = "TableR", kind = "kit", key = "tableCross", x = 2.2, z = 0, yaw = 0 })
		end
		return out
	end

	-- the seats staff sit in (StaffRig and Seating read them through Wafers.seats): x, z and the point
	-- they look at, room frame; Wafers makes each one CFrame.lookAt at y 2.4
	function OL.seats(dept, r)
		local out = {}
		local zOut = r.d / 2 - 4
		if dept == "eng" or dept == "labs" or dept == "lobby" then
			local xs = (dept == "lobby") and { -r.w / 4, r.w / 4 } or { -5.5, 5.5 }
			for _, x in ipairs(xs) do
				local z = zOut - 2.6
				table.insert(out, { x = x - 0.3, z = z, lookX = x - 0.3, lookZ = z + 5 })
			end
		elseif dept == "studio" then
			for _, x in ipairs({ -3.7, 3.7 }) do table.insert(out, { x = x, z = 0.4, lookX = 0, lookZ = 0.4 }) end
		elseif dept == "cafe" then
			for _, o in ipairs({ { 0, 2.6 }, { 0, -2.6 }, { 2.4, 0 }, { -2.4, 0 } }) do
				table.insert(out, { x = o[1], z = o[2], lookX = 0, lookZ = 0 })
			end
		end
		return out
	end

	-- ------------------------------------------------------------ Task 4: the dressing (24 Oct)
	--[[ Ruling 1 (24 Oct): the second monitor and the third plant come with the COMPANY's level, so
		every desk gets two the moment the company reaches 13 (Wafers re-dresses the rooms built before). ]]
	OL.SECOND_AT, OL.MORE_PLANTS_AT = 13, 13
	OL.BUDGET, OL.STOREY_BUDGET = 12, 96        -- new parts a room, and a storey
	function OL.monitorsAt(company) return ((company or 0) >= OL.SECOND_AT) and 2 or 1 end

	--[[ one desk's monitor slots, in the desk's frame (x across it, yaw in degrees, scale of the kit
		screen). Two are toed in toward the seat. The plan's 1.05 / 0.9 overlapped in the middle once
		turned 12 degrees (officelayout.spec's separating-axis test), so: 1.07 and 0.88. ]]
	function OL.monitorSlots(n)
		if (n or 1) >= 2 then
			return { { x = -1.07, yaw = 12, scale = 0.88 }, { x = 1.07, yaw = -12, scale = 0.88 } }
		end
		return { { x = 0, yaw = 0, scale = 1 } }
	end

	-- the parts Wafers' station takes (Wafers.station, seg 3; officelayout.spec checks the source agrees)
	OL.STATION = {
		x = function(r) return -r.w / 2 + 3 end,
		z = function(r) return -r.d / 2 + 3 end,
		w = 3.2, d = 1.8, y0 = 1.5, y1 = 5.9,
	}

	-- the flat and wall pieces: Wafers.decorOk ignores them, so saved decor is never refunded for them
	OL.FLAT_NAMES = { OfficeRug = true, RugBorder = true, WallBase = true, WallArt = true }

	OL.RUG_BORDER = 0.6     -- the coral edge shows this much past the navy on every side
	-- the rug under each department's furniture group: centre x, z and size w x d (room frame)
	local RUGS = {
		-- eng/labs: under the desks and chairs. The plan's z (r.d/2 - 5.2) put the border 0.45 into the glass
		-- band; 5.7 keeps it inside T.inner (ledgered)
		eng = function(r) return 0, r.d / 2 - 5.7, math.min(r.w - 8, 20), 7.5 end,
		studio = function() return 0, 0.2, 10, 6 end,
		cafe = function() return 0, 0, 8, 8 end,
		board = function() return 0, 0, 12, 5.5 end,
	}
	RUGS.labs = RUGS.eng

	OL.ART = { w = 4.5, y0 = 5.5, y1 = 8.9, depth = 0.15, gap = 1.0 }
	OL.BASE = { y1 = 1.2, depth = 0.08 }

	local function backDoor(r) return r.sides[T.backSide(r)] end
	local function wallFace(r) return -r.d / 2 + T.WALL_T end   -- the back wall's room face (z)
	local function wallEnd(r) return r.w / 2 - T.WALL_T end     -- where the back wall meets the side walls (x)

	-- the station's x span, padded: wall art behind it would be hidden
	local function stationSpan(r, pad)
		local x = OL.STATION.x(r)
		return x - OL.STATION.w / 2 - pad, x + OL.STATION.w / 2 + pad
	end

	-- where the art hangs on the back wall: left of the door, or right of it where the station stands
	-- in front of the left half (a seg 3 room narrower than about 25 studs)
	local function artX(r, seg)
		local A = OL.ART
		local x = -(backDoor(r) / 2 + A.gap + A.w / 2)
		if seg == 3 then
			local s0, s1 = stationSpan(r, 1.5)
			if x - A.w / 2 < s1 and x + A.w / 2 > s0 then x = -x end
		end
		return x
	end

	--[[ the room's dressing (room frame). Pieces:
		  rug / border  flat on the floor: x, z, w, d, top height y1
		  base / art    on the back wall: x (centre along it), w, y0..y1, depth out from the wall face
		  plant         stands: FurnitureKit key at x, z
		Every piece says how many parts it makes (FurnitureKit pieces count as one MeshPart, the vertex kit). ]]
	function OL.dressing(dept, r, company, storey, seg)
		local out = {}
		if dept == "lobby" or dept == "servers" or not RUGS[dept] then return out end   -- rulings 4 and 7
		local C = OL.COLORS
		local x, z, w, d = RUGS[dept](r)
		local b = OL.RUG_BORDER
		table.insert(out, { id = "OfficeRug", kind = "rug", x = x, z = z, w = w, d = d, y1 = 0.08, color = C.navy, parts = 1 })
		table.insert(out, { id = "RugBorder", kind = "border", x = x, z = z, w = w + 2 * b, d = d + 2 * b, y1 = 0.05, color = C.coral, parts = 1 })
		local door, e = backDoor(r), wallEnd(r)
		for _, sp in ipairs({ { -e, -door / 2 }, { door / 2, e } }) do
			table.insert(out, { id = "WallBase", kind = "base", x = (sp[1] + sp[2]) / 2, w = sp[2] - sp[1], y0 = 0, y1 = OL.BASE.y1,
				depth = OL.BASE.depth, color = C.navy, parts = 1 })
		end
		local A = OL.ART
		table.insert(out, { id = "WallArt", kind = "art", x = artX(r, seg), w = A.w, y0 = A.y0, y1 = A.y1, depth = A.depth, color = C.ink, parts = 1 })
		if storey ~= 0 then   -- ruling 5: no standing dressing on the lobby storey (saved decor would be refunded)
			local inn = T.inner(r)
			table.insert(out, { id = "Plant1", kind = "plant", key = "pottedPlant", x = -(inn.x - 0.8), z = inn.z - 0.8, yaw = 0, parts = 1 })
			table.insert(out, { id = "Plant2", kind = "plant", key = "pottedPlant", x = inn.x - 0.8, z = inn.z - 0.8, yaw = 0, parts = 1 })
			if (company or 0) >= OL.MORE_PLANTS_AT then   -- the back corner away from the station
				table.insert(out, { id = "Plant3", kind = "plant", key = "pottedPlant", x = inn.x - 0.8, z = -inn.z + 0.8, yaw = 90, parts = 1 })
			end
		end
		return out
	end

	-- parts a list of pieces makes; a workstation's extra monitors are a screen and its Glow each
	function OL.parts(pieces)
		local n = 0
		for _, p in ipairs(pieces) do
			if p.kind == "workstation" then n += ((p.monitors or 1) - 1) * 2 else n += p.parts or 0 end
		end
		return n
	end

	-- what art pass 4 adds to one room: the dressing plus the second monitors
	function OL.newParts(dept, r, company, storey, seg)
		local all = OL.dressing(dept, r, company, storey, seg)
		for _, p in ipairs(OL.furniture(dept, r, company)) do table.insert(all, p) end
		return OL.parts(all)
	end

	--[[ ------------------------------------------------------------ Task 5 (24 Oct): far rooms cost nothing
		The tower was already 537-550k triangles from the plaza at hq:100 against the 500k rule (1d).
		Each client hides the dressing and the kit furniture (ruling 8) of every room whose centre is
		farther than `far` from its camera, and shows it again inside `near` (the band stops flicker),
		the way TreeCullClient does for trees. officelayout.spec pins the numbers: near clears the
		biggest room's diagonal plus a camera's reach, far is under the 1d plaza camera's distance. ]]
	OL.CULL = { far = 160, near = 140, every = 0.5, tags = { "SVDressing", "SVRoomKit" } }
	function OL.cullNext(hidden, dist)
		if not hidden and dist > OL.CULL.far then return true end
		if hidden and dist < OL.CULL.near then return false end
		return hidden
	end

	-- ------------------------------------------------------------ the checks
	-- an axis box from a centre, a local box and a yaw in degrees (CFrame.Angles(0, yaw, 0))
	local function turned(cx, cz, lx0, lx1, lz0, lz1, yaw)
		local a = math.rad(yaw or 0)
		local c, s = math.cos(a), math.sin(a)
		local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
		for _, p in ipairs({ { lx0, lz0 }, { lx1, lz0 }, { lx0, lz1 }, { lx1, lz1 } }) do
			local x, z = cx + p[1] * c + p[2] * s, cz - p[1] * s + p[2] * c
			x0, x1, z0, z1 = math.min(x0, x), math.max(x1, x), math.min(z0, z), math.max(z1, z)
		end
		return { x0 = x0, x1 = x1, z0 = z0, z1 = z1 }
	end
	local function sizeOf(key) local s = OL.SIZE[key]; return s or { 2, 2, 2 } end

	-- the box a piece takes up (room frame, y from the floor)
	function OL.box(p, r)
		local b
		if p.kind == "workstation" then
			-- the desk, its monitors (up to 4 high) and the chair pulled out 2.4 behind it
			local dk = sizeOf("desk")
			b = turned(p.x, p.z, -dk[1] / 2, dk[1] / 2, -dk[3] / 2, 3.4, p.yaw)
			b.y0, b.y1 = 0, dk[2] + sizeOf("computerScreen")[2]
		elseif p.kind == "kit" or p.kind == "plant" then
			local s = sizeOf(p.key)
			b = turned(p.x, p.z, -s[1] / 2, s[1] / 2, -s[3] / 2, s[3] / 2, p.yaw)
			b.y0, b.y1 = 0, s[2]
		elseif p.kind == "racks" then
			local zc = p.rm + SR.BACK
			b = { x0 = -7.5, x1 = 7.5, z0 = zc - SR.SLOT.Z / 2, z1 = zc + SR.SLOT.Z / 2, y0 = 0, y1 = SR.SLOT.Y }
		elseif p.kind == "fan" then
			b = { x0 = p.x - p.size / 2, x1 = p.x + p.size / 2, z0 = p.z - 0.2, z1 = p.z + 0.2, y0 = p.y - p.size / 2, y1 = p.y + p.size / 2 }
		elseif p.kind == "rug" or p.kind == "border" then
			b = { x0 = p.x - p.w / 2, x1 = p.x + p.w / 2, z0 = p.z - p.d / 2, z1 = p.z + p.d / 2, y0 = 0, y1 = p.y1 }
		elseif p.kind == "base" or p.kind == "art" then
			local f = wallFace(r)
			b = { x0 = p.x - p.w / 2, x1 = p.x + p.w / 2, z0 = f, z1 = f + (p.depth or 0.15), y0 = p.y0, y1 = p.y1 }
		end
		return b
	end

	-- the doors of room r, as the floor in front of each one that must stay clear: door width + 2, 4 deep
	function OL.doors(r)
		local out = {}
		local hx, hz = r.w / 2 - T.WALL_T, r.d / 2 - T.WALL_T
		for _, dir in ipairs({ "+x", "-x", "+z", "-z" }) do
			local side = T.sideAt(r, dir)
			local w = r.sides[side]
			if type(w) ~= "number" then w = nil end
			if r.entrance and r.entrance.side == side then w = r.entrance.width end
			if r.terraceDoor == side then w = 6 end
			if w then
				local h = w / 2 + 1
				if dir == "+x" then table.insert(out, { x0 = hx - 4, x1 = hx, z0 = -h, z1 = h, side = side })
				elseif dir == "-x" then table.insert(out, { x0 = -hx, x1 = -hx + 4, z0 = -h, z1 = h, side = side })
				elseif dir == "+z" then table.insert(out, { x0 = -h, x1 = h, z0 = hz - 4, z1 = hz, side = side })
				else table.insert(out, { x0 = -h, x1 = h, z0 = -hz, z1 = -hz + 4, side = side }) end
			end
		end
		return out
	end

	local function hit2(a, b, pad)
		pad = pad or 0
		return math.min(a.x1, b.x1 + pad) - math.max(a.x0, b.x0 - pad) > 1e-6 and math.min(a.z1, b.z1 + pad) - math.max(a.z0, b.z0 - pad) > 1e-6
	end
	local function hit3(a, b) return hit2(a, b) and math.min(a.y1, b.y1) - math.max(a.y0, b.y0) > 1e-6 end
	local function inside(b, inn) return b.x0 >= -inn.x - 1e-6 and b.x1 <= inn.x + 1e-6 and b.z0 >= -inn.z - 1e-6 and b.z1 <= inn.z + 1e-6 end

	--[[ what is wrong with a room's dressing (empty = nothing). `list` replaces the dressing (the spec
		uses it to prove the checks bite). A standing piece (a plant) stays inside T.inner (so inside the
		rounded corners too: tower.spec proves T.inner's corner is), out of every door's approach, 1.5
		from every seat, clear of the station by 1.5, and off the furniture and other plants. A rug stays
		inside T.inner and off the station. A wall piece stays on the back wall, out of the door gap, off
		the furniture, and art is never hung behind the station. ]]
	function OL.check(dept, r, company, storey, seg, list)
		list = list or OL.dressing(dept, r, company, storey, seg)
		local out = {}
		local inn = T.inner(r)
		local furn = {}
		for _, p in ipairs(OL.furniture(dept, r, company)) do table.insert(furn, { p = p, b = OL.box(p, r) }) end
		local seats = OL.seats(dept, r)
		local doors = OL.doors(r)
		local st
		if seg == 3 and dept ~= "lobby" then
			local sx, sz = OL.STATION.x(r), OL.STATION.z(r)
			st = { x0 = sx - OL.STATION.w / 2, x1 = sx + OL.STATION.w / 2, z0 = sz - OL.STATION.d / 2, z1 = sz + OL.STATION.d / 2,
				y0 = OL.STATION.y0, y1 = OL.STATION.y1 }
		end
		local door, e = backDoor(r), wallEnd(r)
		local standing = {}
		for _, p in ipairs(list) do
			local b = OL.box(p, r)
			if not b then
				table.insert(out, p.id .. ": unknown kind " .. tostring(p.kind))
			elseif p.kind == "plant" then
				if not inside(b, inn) then table.insert(out, p.id .. ": outside the room's inner box (the glass band, a wall)") end
				for _, dbox in ipairs(doors) do
					if hit2(b, dbox) then table.insert(out, p.id .. ": in front of the " .. dbox.side .. " door") end
				end
				for i, s in ipairs(seats) do
					local dx = math.max(b.x0 - s.x, 0, s.x - b.x1)
					local dz = math.max(b.z0 - s.z, 0, s.z - b.z1)
					if math.sqrt(dx * dx + dz * dz) < 1.5 then table.insert(out, ("%s: within 1.5 of seat %d"):format(p.id, i)) end
				end
				if st and hit2(b, st, 1.5) then table.insert(out, p.id .. ": in the station's way") end
				for _, f in ipairs(furn) do
					if hit2(b, f.b) then table.insert(out, p.id .. ": in " .. f.p.id) end
				end
				for _, o in ipairs(standing) do
					if hit2(b, o.b) then table.insert(out, p.id .. ": in " .. o.id) end
				end
				table.insert(standing, { id = p.id, b = b })
			elseif p.kind == "rug" or p.kind == "border" then
				if not inside(b, inn) then table.insert(out, p.id .. ": reaches into the glass band or a wall") end
				if st and hit2(b, st) then table.insert(out, p.id .. ": under the station") end
			elseif p.kind == "base" or p.kind == "art" then
				if b.x0 < -e - 1e-6 or b.x1 > e + 1e-6 then table.insert(out, p.id .. ": runs past the end of the back wall") end
				if b.x0 < door / 2 - 1e-6 and b.x1 > -door / 2 + 1e-6 then table.insert(out, p.id .. ": across the door gap") end
				for _, f in ipairs(furn) do
					if hit3(b, f.b) then table.insert(out, p.id .. ": in " .. f.p.id) end
				end
				if p.kind == "art" and st then
					local s0, s1 = stationSpan(r, 1.5)
					if b.x0 < s1 and b.x1 > s0 then table.insert(out, p.id .. ": hung behind the station") end
				end
			end
		end
		return out
	end

	return OL
end

return OfficeLayout
