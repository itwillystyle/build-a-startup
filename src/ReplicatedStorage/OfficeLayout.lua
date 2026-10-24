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

	return OL
end

return OfficeLayout
