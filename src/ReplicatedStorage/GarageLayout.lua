--[[ GarageLayout (12 Oct 2026): where everything in the dressed garage stands.

	The garage is the room every player lives in: the founder's desk, WRITE CODE,
	the hire pad, the HQ pad (BUILD, spin-off, the end of every recruit chase) and
	the door. His target look is "image 5" (silicon-startup/art/, a warm startup
	office: a slatted wood wall with a glowing rocket, a whiteboard of sticky notes,
	a server rack, a coffee bar, a lounge with bean bags, pendant lamps, glowing pad
	edges). This file is that room as DATA, so a test can prove nothing blocks the
	game before anything is built. GarageDress (server) builds from it.

	Pure: no game services, so tests/offline/garagelayout.spec runs it.

	Garage-local studs (plot.g): x across (-17.5 left wall .. 17.5 right wall, inner
	faces), z depth (-14.5 back wall .. the door at 15), y up (floor top 1). Measured
	12 Oct in Play: raycasts hit WallL/WallR at +-17.5 and WallBack at -14.5. The
	windows and beams are from blender/hq.py build_garage (one window mid each side
	wall and one in the back wall, all y 6.2-9.8; oak beams every 3.2 studs whose
	undersides are at 13.1).

	Kinds:
	  floor  stands on the floor: footprint x/z/w(along x)/d(along z), height h
	  rug    lies on the floor (things stand on it): footprint only
	  wall   hangs on a wall: wall = left|right|back, u = centre along it (z on the
	         side walls, x on the back wall), w wide, y0..y1, depth out from it
	  ceil   hangs from the ceiling: footprint and y0..y1
	  fixed  already in the garage (built elsewhere): checked, never built here
	`backdrop` marks a wall piece that things may stand in front of (the slatted wall).
	`coversWindow` marks the one piece allowed over a window (the rocket sign, deliberately).
	`cutsWindow` marks a wall skin that is built with the window cut out of it.
	`may` lists the KEEP zones a piece is allowed in (a rug may lie under the desk). ]]
local L = {}

L.FLOOR = 1.0
L.CEIL = 13.1                    -- the underside of the oak beams
L.HALF_X = 17.5
L.BACK = -14.5
L.FRONT = 14.5                   -- the door leaves stand at 15

-- head-height windows: nothing may hang over them
L.WINDOWS = {
	left = { u0 = -3.1, u1 = 3.1, y0 = 5.75, y1 = 10.1 },
	right = { u0 = -3.1, u1 = 3.1, y0 = 5.75, y1 = 10.1 },
	back = { u0 = -3.8, u1 = 3.8, y0 = 5.75, y1 = 10.1 },
}

--[[ The game's floor, as rectangles nothing may stand in.
	  walkway  the door to the founder's desk; the spawn (0,0) and the camera
	           behind it (z ~12.5) sit on it, and so does the line the opening
	           depends on: spawn -> the glowing laptop at (0, -9)
	  desk     the workbench (x +-4.3, z -9), its keyboard and the chair at (2.5, -6.2)
	  hirePad  the 7x7 pad at (-11, 4) and two studs round it to walk up to it
	  hqPad    the 6x6 pad at (13, 8) and two studs round it
	  door     the strip inside the door: the whole front wall opens ]]
L.KEEP = {
	walkway = { -2.6, 2.6, -6.8, 14.5 },
	desk = { -4.6, 4.6, -10.6, -5.0 },
	hirePad = { -16.5, -5.5, -1.5, 9.5 },
	hqPad = { 8.0, 17.5, 3.0, 13.0 },
	door = { -17.5, 17.5, 12.5, 14.5 },
}

-- 22 Oct, art pass 1 (Luke's picked mock, ui/art-pass/garage-outside.png): the room's colours,
-- here so garagelayout.spec can check each one stays on the palette (the sweep repaints what is off it)
L.COLORS = {
	floor = { 150, 104, 64 },      -- oak planks (WoodPlanks, kept by SVKeepMaterial)
	cladding = { 226, 211, 183 },  -- a warmer, darker wall than v3's (238, 226, 204); the nearest on-palette tone to the mock's
	wainscot = { 40, 150, 160 },   -- Palette Teal: the band under the oak rail (was v3's sage)
	runner = { 40, 150, 160 },     -- Palette Teal: the rug down the middle (was navy)
	sofa = { 236, 104, 84 },       -- Palette Coral: the lounge sofa, the room's one warm accent
}

L.PIECES = {
	-- ---------------------------------------------------------- already here
	{ id = "bench", kind = "fixed", x = 0, z = -9, w = 8.64, d = 2.31, h = 2.26, may = { "desk" } },
	{ id = "chair", kind = "fixed", x = 2.5, z = -6.2, w = 2.0, d = 1.9, h = 3.6, may = { "desk" } },
	{ id = "boxes", kind = "fixed", x = 13.9, z = -13.3, w = 4.3, d = 1.9, h = 3.3 },

	-- ---------------------------------------------------------- the floor
	-- 22 Oct (art pass): oak planks wall to wall, under every rug, pad and glow (top 0.02)
	{ id = "floorBoards", kind = "rug", build = "boards", x = 0, z = 0, w = 35, d = 29, top = 0.02,
		may = { "walkway", "desk", "hirePad", "hqPad", "door" } },
	{ id = "runner", kind = "rug", build = "runner", x = 0, z = 3.7, w = 4.8, d = 20.8, may = { "walkway", "desk", "door" },
		color = L.COLORS.runner },
	{ id = "deskRug", kind = "rug", build = "rug", x = 0, z = -9.3, w = 11, d = 5.4, may = { "desk", "walkway" },
		color = { 192, 138, 85 } },
	{ id = "loungeRug", kind = "rug", build = "rug", x = 13.2, z = -0.6, w = 6.4, d = 6.6,
		color = { 214, 170, 120 } },
	{ id = "meetingRug", kind = "rug", build = "rug", x = -12.5, z = -9.2, w = 6.6, d = 6.4,
		color = { 207, 198, 182 } },

	-- the meeting corner (back left): a round table, three chairs, two bookcases
	-- solid: a 4-stud table top you can jump on must hold you (the doctor's "sinking surfaces", 12 Oct)
	{ id = "table", kind = "floor", build = "kit", key = "tableRound", x = -12.5, z = -9.0, w = 4.1, d = 4.7, h = 2.2, solid = true },
	{ id = "seatFront", kind = "floor", build = "kit", key = "chairModernCushion", yaw = 180, x = -12.5, z = -5.85, w = 1.2, d = 1.2, h = 2.7 },
	{ id = "seatLeft", kind = "floor", build = "kit", key = "chairModernCushion", yaw = 90, x = -15.4, z = -9.0, w = 1.2, d = 1.2, h = 2.7 },
	{ id = "seatRight", kind = "floor", build = "kit", key = "chairModernCushion", yaw = -90, x = -9.6, z = -9.0, w = 1.2, d = 1.2, h = 2.7 },
	{ id = "bookcaseA", kind = "floor", build = "kit", key = "bookcaseClosedDoors", x = -15.9, z = -13.7, w = 2.4, d = 1.5, h = 5.0 },
	{ id = "bookcaseB", kind = "floor", build = "kit", key = "bookcaseClosedDoors", x = -13.4, z = -13.7, w = 2.4, d = 1.5, h = 5.0 },

	-- the coffee bar (left wall, back of the hire pad): two counters, a machine, mugs
	{ id = "counterA", kind = "floor", build = "kit", key = "kitchenBar", yaw = 90, x = -16.85, z = -5.55, w = 1.25, d = 2.55, h = 2.5 },
	{ id = "counterB", kind = "floor", build = "kit", key = "kitchenBar", yaw = 90, x = -16.85, z = -3.0, w = 1.25, d = 2.55, h = 2.5 },
	{ id = "coffee", kind = "floor", build = "coffee", x = -16.85, z = -4.3, w = 1.2, d = 3.6, h = 3.6, on = true },

	-- the server rack (right wall, by the boxes): "we run our own servers"
	{ id = "rack", kind = "floor", build = "rack", x = 16.25, z = -10.3, w = 2.4, d = 2.6, h = 6.5 },

	-- the lounge (right side, under the window): sofa, two bean bags, a low table, a lamp
	{ id = "sofa", kind = "floor", build = "kit", key = "loungeDesignSofa", yaw = -90, x = 16.1, z = -0.6, w = 2.4, d = 6.6, h = 2.4,
		tint = L.COLORS.sofa },
	{ id = "beanA", kind = "floor", build = "beanbag", x = 11.0, z = -2.9, w = 2.4, d = 2.4, h = 1.7, color = { 224, 182, 90 } },
	{ id = "beanB", kind = "floor", build = "beanbag", x = 11.2, z = 1.4, w = 2.4, d = 2.4, h = 1.7, color = { 62, 110, 158 } },
	{ id = "lowTable", kind = "floor", build = "lowTable", x = 13.4, z = -0.6, w = 1.6, d = 3.2, h = 1.4 },
	{ id = "lamp", kind = "floor", build = "floorLamp", x = 14.3, z = 2.4, w = 1.1, d = 1.1, h = 5.2, light = true },

	-- plants: either side of the slatted wall, and a tall one inside the door
	{ id = "plantL", kind = "floor", build = "kit", key = "pottedPlant", scale = 1.6, x = -7.2, z = -13.2, w = 2.0, d = 2.3, h = 6.2 },
	{ id = "plantR", kind = "floor", build = "kit", key = "pottedPlant", scale = 1.6, x = 7.2, z = -13.2, w = 2.0, d = 2.3, h = 6.2 },
	{ id = "plantDoor", kind = "floor", build = "kit", key = "pottedPlant", scale = 2.0, x = -15.4, z = 11.0, w = 2.5, d = 2.9, h = 7.7 },

	-- the glow round each pad (part of the pad, so it lives in the pad's own zone)
	{ id = "hireGlow", kind = "rug", build = "padGlow", x = -11, z = 4, w = 7.9, d = 7.9, may = { "hirePad" } },
	{ id = "hqGlow", kind = "rug", build = "padGlow", x = 13, z = 8, w = 6.9, d = 6.9, may = { "hqPad" } },

	-- ---------------------------------------------------------- the walls
	-- v3 (12 Oct, the second pass): the walls themselves. The first screenshots were
	-- right about the props and wrong about the room: big flat white walls. A warm
	-- cream skin (cut round the windows) and image 2's sage band under an oak rail.
	{ id = "skinLeft", kind = "wall", build = "cladding", wall = "left", u = 0, w = 29, y0 = 1.0, y1 = 13.1, depth = 0.05, backdrop = true, cutsWindow = true },
	{ id = "skinRight", kind = "wall", build = "cladding", wall = "right", u = 0, w = 29, y0 = 1.0, y1 = 13.1, depth = 0.05, backdrop = true, cutsWindow = true },
	{ id = "skinBack", kind = "wall", build = "cladding", wall = "back", u = 0, w = 35, y0 = 1.0, y1 = 13.1, depth = 0.05, backdrop = true, cutsWindow = true },
	{ id = "bandLeft", kind = "wall", build = "wainscot", wall = "left", u = 0, w = 29, y0 = 1.0, y1 = 3.75, depth = 0.12, backdrop = true },
	{ id = "bandRight", kind = "wall", build = "wainscot", wall = "right", u = 0, w = 29, y0 = 1.0, y1 = 3.75, depth = 0.12, backdrop = true },
	{ id = "bandBack", kind = "wall", build = "wainscot", wall = "back", u = 0, w = 35, y0 = 1.0, y1 = 3.75, depth = 0.12, backdrop = true },
	-- and the upper walls, which were empty above head height
	{ id = "plantShelfL", kind = "wall", build = "plantShelf", wall = "left", u = -9.85, w = 4.4, y0 = 9.9, y1 = 11.8, depth = 1.0 },
	{ id = "menuBoard", kind = "wall", build = "menuBoard", wall = "left", u = -5.0, w = 3.2, y0 = 6.4, y1 = 8.6, depth = 0.12 },
	{ id = "posterL", kind = "wall", build = "poster", wall = "left", u = 7.0, w = 3.0, y0 = 8.6, y1 = 11.8, depth = 0.15 },
	{ id = "tvShelf", kind = "wall", build = "tvShelf", wall = "right", u = -5.5, w = 3.8, y0 = 9.0, y1 = 10.6, depth = 0.9 },
	{ id = "rackFrames", kind = "wall", build = "frames", wall = "right", u = -11.0, w = 3.4, y0 = 8.4, y1 = 11.0, depth = 0.15 },
	{ id = "printBack", kind = "wall", build = "poster", wall = "back", u = -14.65, w = 3.0, y0 = 10.4, y1 = 12.7, depth = 0.15 },
	{ id = "plantShelfB", kind = "wall", build = "plantShelf", wall = "back", u = 13.6, w = 4.4, y0 = 10.5, y1 = 12.4, depth = 1.0 },
	-- back: the slatted oak wall either side of the window, the rocket above it
	{ id = "slatsL", kind = "wall", build = "slats", wall = "back", u = -6.6, w = 5.2, y0 = 1.0, y1 = 13.0, depth = 0.35, backdrop = true },
	{ id = "slatsR", kind = "wall", build = "slats", wall = "back", u = 6.6, w = 5.2, y0 = 1.0, y1 = 13.0, depth = 0.35, backdrop = true },
	-- v2: the sign covers the back window on purpose (it is the room's hero, image 5); 2.6 tall it read as a sticker
	{ id = "rocket", kind = "wall", build = "sign", wall = "back", u = 0, w = 7.4, y0 = 5.6, y1 = 12.9, depth = 0.3, coversWindow = true },
	{ id = "trophies", kind = "wall", build = "trophyShelf", wall = "back", u = -14.65, w = 5.2, y0 = 6.4, y1 = 9.9, depth = 1.0 },
	{ id = "framesBack", kind = "wall", build = "frames", wall = "back", u = 13.6, w = 6.0, y0 = 6.4, y1 = 10.0, depth = 0.15 },
	-- left: the whiteboard over the meeting table, a shelf over the coffee bar, a pinboard
	{ id = "whiteboard", kind = "wall", build = "whiteboard", wall = "left", u = -9.85, w = 5.6, y0 = 4.6, y1 = 8.4, depth = 0.25 },
	{ id = "mugShelf", kind = "wall", build = "mugShelf", wall = "left", u = -5.05, w = 3.5, y0 = 5.0, y1 = 5.9, depth = 0.9 },
	{ id = "pinboard", kind = "wall", build = "pinboard", wall = "left", u = 7.0, w = 4.0, y0 = 4.6, y1 = 7.6, depth = 0.2 },
	-- right: the wall TV over the lounge, pictures and a neon bolt over the HQ pad
	{ id = "tv", kind = "wall", build = "tv", wall = "right", u = -5.5, w = 4.2, y0 = 5.0, y1 = 7.6, depth = 0.3 },
	{ id = "framesRight", kind = "wall", build = "frames", wall = "right", u = 6.0, w = 4.6, y0 = 6.6, y1 = 9.6, depth = 0.15 },
	{ id = "neonRocket", kind = "wall", build = "neonRocket", wall = "right", u = 10.5, w = 2.8, y0 = 6.6, y1 = 10.4, depth = 0.1 },

	-- ---------------------------------------------------------- the ceiling
	{ id = "deskLamps", kind = "ceil", build = "pendants", x = 0, z = -8.6, w = 6.4, d = 1.2, y0 = 10.2, y1 = 13.1, n = 2, light = true },
	{ id = "meetingLamps", kind = "ceil", build = "pendants", x = -12.5, z = -9.0, w = 3.4, d = 1.2, y0 = 10.2, y1 = 13.1, n = 2, light = true },
	{ id = "duct", kind = "ceil", build = "duct", x = -9.5, z = -7.2, w = 0.9, d = 14, y0 = 12.0, y1 = 12.9 },
	{ id = "track", kind = "ceil", build = "track", x = 0, z = 4.2, w = 16, d = 0.6, y0 = 12.1, y1 = 12.9 },
	-- 22 Oct (art pass): a run of warm bulbs across the front, the mock's string lights. Neon only
	-- (no light sources: the room's budget of 6 is spent), sagging from 12.9 to 11.0
	{ id = "stringLights", kind = "ceil", build = "stringLights", x = 0, z = 10.5, w = 30, d = 0.6, y0 = 11.0, y1 = 12.9 },
}

local function overlap(a0, a1, b0, b1) return a0 < b1 and b0 < a1 end

local function rect(p) return p.x - p.w / 2, p.x + p.w / 2, p.z - p.d / 2, p.z + p.d / 2 end

local function allowed(p, zone)
	for _, m in p.may or {} do if m == zone then return true end end
	return false
end

-- the floor rect a wall piece's mount covers, so a lamp cannot stand in front of a TV
local function wallStrip(p)
	if p.wall == "left" then return -L.HALF_X, -L.HALF_X + p.depth + 0.6, p.u - p.w / 2, p.u + p.w / 2 end
	if p.wall == "right" then return L.HALF_X - p.depth - 0.6, L.HALF_X, p.u - p.w / 2, p.u + p.w / 2 end
	return p.u - p.w / 2, p.u + p.w / 2, L.BACK, L.BACK + p.depth + 0.6
end

-- every problem with the layout, as readable lines (empty = the room is clear)
function L.check(pieces)
	pieces = pieces or L.PIECES
	local out = {}
	local function bad(s) table.insert(out, s) end
	local seen = {}
	for _, p in pieces do
		if seen[p.id] then bad(p.id .. ": the id is used twice") end
		seen[p.id] = true
		if p.kind == "wall" then
			local half = (p.wall == "back") and L.HALF_X or ((L.FRONT - L.BACK) / 2)
			local mid = (p.wall == "back") and 0 or ((L.FRONT + L.BACK) / 2)
			if p.u - p.w / 2 < mid - half or p.u + p.w / 2 > mid + half then bad(p.id .. ": runs off the end of the " .. p.wall .. " wall") end
			if p.y0 < L.FLOOR or p.y1 > L.CEIL then bad(p.id .. ": above the beams or below the floor") end
			local win = L.WINDOWS[p.wall]
			if win and not p.coversWindow and not p.cutsWindow and overlap(p.u - p.w / 2, p.u + p.w / 2, win.u0, win.u1) and overlap(p.y0, p.y1, win.y0, win.y1) then
				bad(p.id .. ": covers the " .. p.wall .. " window")
			end
		else
			local x0, x1, z0, z1 = rect(p)
			if x0 < -L.HALF_X or x1 > L.HALF_X or z0 < L.BACK or z1 > L.FRONT then bad(p.id .. ": through a wall") end
			if p.kind == "ceil" then
				if p.y0 < 9.5 or p.y1 > L.CEIL then bad(p.id .. ": hangs below 9.5 or into the beams") end
			elseif p.kind ~= "fixed" then
				for zone, r in L.KEEP do
					if not allowed(p, zone) and overlap(x0, x1, r[1], r[2]) and overlap(z0, z1, r[3], r[4]) then
						bad(("%s: stands in the %s"):format(p.id, zone))
					end
				end
			end
		end
	end
	-- things that stand may not stand in each other, nor in front of what hangs low on a wall
	local standing, hung = {}, {}
	for _, p in pieces do
		if p.kind == "floor" or p.kind == "fixed" then table.insert(standing, p) end
		if p.kind == "wall" and not p.backdrop then table.insert(hung, p) end
	end
	for i = 1, #standing do
		for j = i + 1, #standing do
			local a, b = standing[i], standing[j]
			local onTop = (a.on and not b.on) or (b.on and not a.on)
			local ax0, ax1, az0, az1 = rect(a)
			local bx0, bx1, bz0, bz1 = rect(b)
			if not onTop and overlap(ax0, ax1, bx0, bx1) and overlap(az0, az1, bz0, bz1) then
				bad(("%s and %s stand in each other"):format(a.id, b.id))
			end
		end
		local s = standing[i]
		local sx0, sx1, sz0, sz1 = rect(s)
		for _, w in hung do
			local wx0, wx1, wz0, wz1 = wallStrip(w)
			if overlap(sx0, sx1, wx0, wx1) and overlap(sz0, sz1, wz0, wz1) and overlap(L.FLOOR, L.FLOOR + s.h, w.y0, w.y1) then
				bad(("%s stands in front of %s"):format(s.id, w.id))
			end
		end
	end
	for i = 1, #hung do
		for j = i + 1, #hung do
			local a, b = hung[i], hung[j]
			if a.wall == b.wall and overlap(a.u - a.w / 2, a.u + a.w / 2, b.u - b.w / 2, b.u + b.w / 2)
				and overlap(a.y0, a.y1, b.y0, b.y1) then
				bad(("%s and %s hang on each other"):format(a.id, b.id))
			end
		end
	end
	return out
end

-- how many real lights the room adds (phones pay for every one)
function L.lights(pieces)
	local n = 0
	for _, p in pieces or L.PIECES do
		if p.light then n += 1 end
		if p.build == "sign" then n += 1 end
	end
	return n
end

return L
