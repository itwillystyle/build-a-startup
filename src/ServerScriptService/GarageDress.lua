--[[ GarageDress (12 Oct 2026): builds the dressed garage from GarageLayout.

	The look is his "image 5" (silicon-startup/art/): warm wood, a glowing rocket,
	sticky notes, a server rack, a coffee bar, a lounge, pendant lamps, glowing pad
	edges. WHERE everything stands is GarageLayout's job (and its test's); this file
	only knows HOW each piece is made.

	Rules every builder here keeps:
	  - nothing new is solid except the server rack, and nothing new can be hit by
	    a ray (CanQuery false), so the camera never pops in on a pendant and the
	    build-mode aim never lands on a poster
	  - colours sit on the Palette's anchors (Palette.lua), so the sweep leaves them
	  - Neon is for light: bulbs, LEDs, the pad edges, the sign's rim (ART.md)
	  - floor pieces carry FKItem, so a player's decor cannot be dropped inside them
	  - one Model per piece, named by its layout id: SVCheck treats a Model as one
	    object, so a piece's own parts may touch, two pieces may not ]]
local RS = game:GetService("ReplicatedStorage")
local L = require(RS:WaitForChild("GarageLayout"))

local GarageDress = {}

local F = L.FLOOR
local ROCKET = "rbxassetid://87541273840200"    -- UIKit.ICON.rocket, a white glyph: tinted it glows

local C = {
	paper = Color3.fromRGB(243, 239, 230),
	concrete = Color3.fromRGB(207, 198, 182),
	oak = Color3.fromRGB(192, 138, 85),
	oakDark = Color3.fromRGB(138, 96, 58),
	ink = Color3.fromRGB(30, 37, 48),
	asphalt = Color3.fromRGB(56, 58, 66),
	gold = Color3.fromRGB(255, 194, 61),
	calGold = Color3.fromRGB(224, 182, 90),
	blue = Color3.fromRGB(62, 110, 158),
	glass = Color3.fromRGB(118, 158, 176),
	lawn = Color3.fromRGB(118, 160, 92),
	leaf = Color3.fromRGB(74, 150, 84),
	warm = Color3.fromRGB(255, 214, 160),
	cyan = Color3.fromRGB(132, 214, 236),
}

local function rgb(t) return t and Color3.fromRGB(t[1], t[2], t[3]) end

local function part(parent, name, size, cf, color, extra)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.Size = size
	p.CFrame = cf
	p.Color = color
	for k, v in extra or {} do p[k] = v end
	p.Parent = parent
	return p
end

-- an upright cylinder (Roblox cylinders lie along X)
local function cyl(parent, name, height, dia, cf, color, extra)
	local e = { Shape = Enum.PartType.Cylinder }
	for k, v in extra or {} do e[k] = v end
	return part(parent, name, Vector3.new(height, dia, dia), cf * CFrame.Angles(0, 0, math.rad(90)), color, e)
end

local function neon(extra)
	local e = { Material = Enum.Material.Neon }
	for k, v in extra or {} do e[k] = v end
	return e
end

local function light(host, range, brightness, shadows)
	local pl = Instance.new("PointLight")
	pl.Color = C.warm
	pl.Range = range
	pl.Brightness = brightness
	pl.Shadows = shadows == true
	pl.Parent = host
	return pl
end

-- ---------------------------------------------------------------- frames
local NORMAL = { left = Vector3.new(1, 0, 0), right = Vector3.new(-1, 0, 0), back = Vector3.new(0, 0, 1) }

-- a frame on the wall's inner face at (u, y), looking into the room
local function wallFrame(pivot, wall, u, y)
	local p
	if wall == "left" then p = Vector3.new(-L.HALF_X, y, u)
	elseif wall == "right" then p = Vector3.new(L.HALF_X, y, u)
	else p = Vector3.new(u, y, L.BACK) end
	return pivot * CFrame.lookAt(p, p + NORMAL[wall])
end

-- in a wall frame: a = to the right as you face the wall, y up, o out of the wall
local function at(f, a, y, o) return f * CFrame.new(-a, y, -o) end

-- a straight stroke on a wall from (a1, y1) to (a2, y2)
local function stroke(parent, f, a1, y1, a2, y2, o, thick, color, extra)
	local da, dy = a2 - a1, y2 - y1
	local len = math.sqrt(da * da + dy * dy)
	return part(parent, "Stroke", Vector3.new(len + thick * 0.6, thick, 0.04),
		at(f, (a1 + a2) / 2, (y1 + y2) / 2, o) * CFrame.Angles(0, 0, math.atan2(dy, -da)), color, extra)
end

-- ---------------------------------------------------------------- builders
local B = {}

function B.kit(p, M, pivot, FK)
	local m = FK.put(p.key, pivot * CFrame.new(p.x, F, p.z), M, { yaw = p.yaw, scale = p.scale })
	if m and p.light then
		local host = FK.body(m)
		if host then light(host, 12, 0.9) end
	end
end

function B.runner(p, M, pivot)
	part(M, "Runner", Vector3.new(p.w, 0.06, p.d), pivot * CFrame.new(p.x, F + 0.03, p.z), Color3.fromRGB(44, 70, 98))
	for _, s in { -1, 1 } do
		part(M, "RunnerLine", Vector3.new(0.22, 0.07, p.d - 0.7), pivot * CFrame.new(p.x + s * (p.w / 2 - 0.45), F + 0.035, p.z), C.concrete)
	end
end

function B.rug(p, M, pivot)
	part(M, "Rug", Vector3.new(p.w, 0.05, p.d), pivot * CFrame.new(p.x, F + 0.025, p.z), rgb(p.color) or C.concrete,
		{ Material = Enum.Material.Fabric })
	local ins = 0.45
	for _, s in { -1, 1 } do
		part(M, "RugEdge", Vector3.new(p.w - 2 * ins, 0.055, 0.14), pivot * CFrame.new(p.x, F + 0.028, p.z + s * (p.d / 2 - ins)), C.paper)
		part(M, "RugEdge", Vector3.new(0.14, 0.055, p.d - 2 * ins), pivot * CFrame.new(p.x + s * (p.w / 2 - ins), F + 0.028, p.z), C.paper)
	end
end

-- the coffee bar's top: the machine, three mugs, a jar
function B.coffee(p, M, pivot, FK)
	local top = F + FK.SIZE.kitchenBar.Y
	FK.put("kitchenCoffeeMachine", pivot * CFrame.new(p.x + 0.05, top, p.z - 1.1), M, { yaw = 90 })
	for k, col in { C.paper, C.blue, C.gold } do
		cyl(M, "Mug", 0.4, 0.34, pivot * CFrame.new(p.x + 0.15, top + 0.2, p.z + 0.1 + k * 0.42), col)
	end
	cyl(M, "Jar", 0.7, 0.5, pivot * CFrame.new(p.x - 0.1, top + 0.35, p.z + 1.55), C.glass, { Transparency = 0.25 })
	cyl(M, "Beans", 0.4, 0.42, pivot * CFrame.new(p.x - 0.1, top + 0.22, p.z + 1.55), C.oakDark)
end

-- six servers, their status lights, a vent top; the front faces into the room (-x)
function B.rack(p, M, pivot)
	local h = p.h
	local body = part(M, "RackBody", Vector3.new(p.w - 0.1, h, p.d - 0.1), pivot * CFrame.new(p.x, F + h / 2, p.z), C.ink,
		{ CanCollide = true, CastShadow = true })
	local front = p.x - (p.w - 0.1) / 2
	part(M, "RackCap", Vector3.new(p.w, 0.2, p.d), pivot * CFrame.new(p.x, F + h + 0.1, p.z), C.asphalt)
	local cols = { C.lawn, C.cyan, C.lawn, C.gold, C.cyan, C.lawn }
	for k = 1, 6 do
		local y = F + 0.55 + (k - 1) * 0.98
		part(M, "Unit", Vector3.new(0.06, 0.78, p.d - 0.5), pivot * CFrame.new(front - 0.03, y + 0.39, p.z), C.asphalt)
		for j = 0, 2 do
			if not (k == 4 and j == 2) then
				part(M, "Led", Vector3.new(0.05, 0.13, 0.13), pivot * CFrame.new(front - 0.07, y + 0.39, p.z + 0.65 - j * 0.3),
					cols[(k + j - 1) % #cols + 1], neon())
			end
		end
		part(M, "Vent", Vector3.new(0.05, 0.08, 0.9), pivot * CFrame.new(front - 0.07, y + 0.39, p.z - 0.55), C.ink)
	end
	return body
end

function B.beanbag(p, M, pivot)
	local b = part(M, "BeanBag", Vector3.new(p.w, p.h, p.d), pivot * CFrame.new(p.x, F + p.h / 2 - 0.08, p.z), rgb(p.color) or C.blue,
		{ Material = Enum.Material.Fabric })
	local sm = Instance.new("SpecialMesh")
	sm.MeshType = Enum.MeshType.Sphere
	sm.Parent = b
	local dent = part(M, "BeanSeat", Vector3.new(p.w * 0.6, 0.4, p.d * 0.6), pivot * CFrame.new(p.x, F + p.h - 0.22, p.z),
		(rgb(p.color) or C.blue):Lerp(C.ink, 0.12), { Material = Enum.Material.Fabric })
	local sm2 = Instance.new("SpecialMesh")
	sm2.MeshType = Enum.MeshType.Sphere
	sm2.Parent = dent
end

function B.lowTable(p, M, pivot)
	part(M, "TableTop", Vector3.new(p.w, 0.18, p.d), pivot * CFrame.new(p.x, F + p.h - 0.09, p.z), C.oak, { Material = Enum.Material.Wood })
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(M, "Leg", Vector3.new(0.14, p.h - 0.18, 0.14), pivot * CFrame.new(p.x + sx * (p.w / 2 - 0.2), F + (p.h - 0.18) / 2, p.z + sz * (p.d / 2 - 0.2)), C.ink)
		end
	end
	cyl(M, "Mug", 0.4, 0.34, pivot * CFrame.new(p.x - 0.2, F + p.h + 0.2, p.z + 0.6), C.paper)
	cyl(M, "Pot", 0.45, 0.5, pivot * CFrame.new(p.x + 0.1, F + p.h + 0.22, p.z - 0.8), C.concrete)
	part(M, "Leaves", Vector3.new(0.7, 0.55, 0.7), pivot * CFrame.new(p.x + 0.1, F + p.h + 0.7, p.z - 0.8), C.leaf, { Shape = Enum.PartType.Ball })
end

-- v2: our own floor lamp. The Kenney one is a single mesh tinted as its shade, so
-- the whole thing glowed: a yellow pillar beside the sofa
function B.floorLamp(p, M, pivot)
	cyl(M, "LampBase", 0.12, 0.9, pivot * CFrame.new(p.x, F + 0.06, p.z), C.ink, { Material = Enum.Material.Metal })
	part(M, "LampPole", Vector3.new(0.1, p.h - 1.3, 0.1), pivot * CFrame.new(p.x, F + (p.h - 1.3) / 2, p.z), C.ink)
	cyl(M, "LampShade", 1.1, p.w, pivot * CFrame.new(p.x, F + p.h - 0.6, p.z), Color3.fromRGB(246, 232, 204), { Transparency = 0.1 })
	local bulb = part(M, "LampBulb", Vector3.new(0.4, 0.4, 0.4), pivot * CFrame.new(p.x, F + p.h - 0.7, p.z), C.warm,
		neon({ Shape = Enum.PartType.Ball }))
	if p.light then light(bulb, 12, 0.9) end
end

-- a thin glowing frame on the floor round a pad (the pad itself is not touched)
function B.padGlow(p, M, pivot)
	local t = 0.22
	for _, s in { -1, 1 } do
		part(M, "PadGlow", Vector3.new(p.w, 0.12, t), pivot * CFrame.new(p.x, F + 0.06, p.z + s * (p.d / 2 - t / 2)), C.cyan, neon())
		part(M, "PadGlow", Vector3.new(t, 0.12, p.d - 2 * t), pivot * CFrame.new(p.x + s * (p.w / 2 - t / 2), F + 0.06, p.z), C.cyan, neon())
	end
end

-- slatted oak over a dark backing, a warm light strip on the outer edge
function B.slats(p, f, M)
	local h = p.y1 - p.y0
	local mid = p.y0 + h / 2
	-- v2: walnut, not oak. Oak renders gold (hq2.py found the same), and beside the
	-- orange Kenney bookcases the whole back wall read as one orange curtain
	part(M, "Backing", Vector3.new(p.w, h, 0.1), at(f, 0, mid, 0.06), Color3.fromRGB(70, 50, 34), { Material = Enum.Material.Wood })
	local n = math.floor((p.w - 0.4) / 0.72)
	for k = 0, n do
		local a = -p.w / 2 + 0.35 + k * ((p.w - 0.7) / n)
		part(M, "Slat", Vector3.new(0.4, h, p.depth - 0.1), at(f, a, mid, 0.1 + (p.depth - 0.1) / 2), Color3.fromRGB(128, 88, 56), { Material = Enum.Material.Wood })
	end
	local outer = (p.u < 0) and -1 or 1
	part(M, "Uplight", Vector3.new(0.14, h - 0.6, 0.14), at(f, outer * (p.w / 2 + 0.12), mid, 0.12), C.warm, neon())
end

-- the dark panel above the back window, the game's rocket glowing on it
function B.sign(p, f, M)
	local h = p.y1 - p.y0
	-- v2: a dark NEON face. Measured 12 Oct: a shaded ink panel 6 studs from the desk
	-- pendants and the ceiling bulb rendered tan, and the rocket washed out on it. A
	-- backlit sign is not lit by the room; Neon ignores the room's lights.
	local panel = part(M, "SignPanel", Vector3.new(p.w, h, p.depth), at(f, 0, p.y0 + h / 2, p.depth / 2 + 0.02),
		Color3.fromRGB(22, 26, 34), neon())
	for _, s in { -1, 1 } do
		part(M, "SignRim", Vector3.new(p.w - 0.3, 0.1, 0.05), at(f, 0, p.y0 + h / 2 + s * (h / 2 - 0.15), p.depth + 0.05), C.warm, neon())
		part(M, "SignRim", Vector3.new(0.1, h - 0.3, 0.05), at(f, s * (p.w / 2 - 0.15), p.y0 + h / 2, p.depth + 0.05), C.warm, neon())
	end
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0
	sg.MaxDistance = 140
	sg.Parent = panel
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Position = UDim2.fromScale(0.5, 0.5)
	img.Size = UDim2.fromScale(0.92, 0.92)
	img.Image = ROCKET
	img.ImageColor3 = Color3.fromRGB(255, 204, 120)
	img.ScaleType = Enum.ScaleType.Fit
	img.Parent = sg
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.Parent = img
	local sl = Instance.new("SurfaceLight")
	sl.Face = Enum.NormalId.Front
	sl.Color = C.warm
	sl.Range = 10
	sl.Angle = 80
	sl.Brightness = 1.2
	sl.Parent = panel
end

local function trophy(M, f, a, y, o)
	part(M, "TrophyBase", Vector3.new(0.5, 0.3, 0.45), at(f, a, y + 0.15, o), C.ink)
	part(M, "TrophyStem", Vector3.new(0.14, 0.4, 0.14), at(f, a, y + 0.5, o), C.gold, { Material = Enum.Material.Metal })
	part(M, "TrophyCup", Vector3.new(0.62, 0.62, 0.62), at(f, a, y + 0.95, o), C.gold, { Material = Enum.Material.Metal, Shape = Enum.PartType.Ball })
end

local BOOKS = { C.blue, C.paper, C.oak, C.ink, C.glass, C.calGold, C.lawn }

local function books(M, f, a0, a1, y, depth, seed)
	local a, k = a0, seed
	while a < a1 - 0.3 do
		k += 1
		local wdt = 0.26 + (k % 3) * 0.06
		local ht = 0.8 + (k % 4) * 0.12
		part(M, "Book", Vector3.new(wdt, ht, depth * 0.7), at(f, a + wdt / 2, y + ht / 2, depth * 0.45), BOOKS[k % #BOOKS + 1])
		a += wdt + 0.03
	end
end

local function shelfPlank(M, f, w, y, depth)
	part(M, "Plank", Vector3.new(w, 0.2, depth), at(f, 0, y, depth / 2 + 0.02), C.oak, { Material = Enum.Material.Wood })
	for _, s in { -1, 1 } do
		part(M, "Bracket", Vector3.new(0.14, 0.45, depth * 0.7), at(f, s * (w / 2 - 0.4), y - 0.32, depth * 0.35 + 0.02), C.ink)
	end
end

function B.trophyShelf(p, f, M)
	local lo, hi = p.y0 + 0.2, p.y0 + (p.y1 - p.y0) / 2 + 0.3
	shelfPlank(M, f, p.w, lo, p.depth)
	shelfPlank(M, f, p.w, hi, p.depth)
	trophy(M, f, -1.7, lo + 0.1, p.depth / 2)
	trophy(M, f, -0.6, lo + 0.1, p.depth / 2)
	books(M, f, 0.4, p.w / 2 - 0.3, lo + 0.1, p.depth, 2)
	books(M, f, -p.w / 2 + 0.3, 0.9, hi + 0.1, p.depth, 5)
	trophy(M, f, 1.7, hi + 0.1, p.depth / 2)
end

local function picture(M, f, a, y, w, h, scene)
	part(M, "FrameEdge", Vector3.new(w, h, 0.1), at(f, a, y, 0.07), scene == 1 and C.oakDark or C.ink)
	part(M, "Mat", Vector3.new(w - 0.24, h - 0.24, 0.04), at(f, a, y, 0.14), C.paper)
	local pw, ph = w - 0.5, h - 0.5
	part(M, "Sky", Vector3.new(pw, ph, 0.03), at(f, a, y, 0.17), scene == 1 and C.glass or Color3.fromRGB(170, 196, 214))
	part(M, "Hill", Vector3.new(pw, ph * 0.38, 0.03), at(f, a, y - ph * 0.31, 0.19), scene == 1 and C.lawn or C.leaf)
	stroke(M, f, a - pw * 0.45, y - ph * 0.08, a - pw * 0.05, y + ph * 0.3, 0.2, 0.22, C.blue)
	stroke(M, f, a - pw * 0.05, y + ph * 0.3, a + pw * 0.4, y - ph * 0.12, 0.2, 0.22, C.blue)
	part(M, "Sun", Vector3.new(0.34, 0.34, 0.03), at(f, a + pw * 0.28, y + ph * 0.3, 0.21), C.gold)
end

function B.frames(p, f, M)
	local h = p.y1 - p.y0
	local wEach = (p.w - 0.4) / 2
	picture(M, f, -p.w / 4 - 0.05, p.y0 + h / 2 + 0.2, wEach, h - 0.4, 1)
	picture(M, f, p.w / 4 + 0.05, p.y0 + h / 2 - 0.15, wEach, h - 0.9, 2)
end

local NOTES = { C.gold, Color3.fromRGB(176, 214, 140), Color3.fromRGB(170, 204, 230), Color3.fromRGB(240, 170, 110), C.gold }

function B.whiteboard(p, f, M)
	local h = p.y1 - p.y0
	local cy = p.y0 + h / 2
	part(M, "BoardFrame", Vector3.new(p.w, h, 0.12), at(f, 0, cy, 0.08), C.asphalt)
	part(M, "Board", Vector3.new(p.w - 0.3, h - 0.3, 0.05), at(f, 0, cy, 0.16), C.paper)
	-- the sticky notes, left 55%
	local k = 0
	for row = 0, 2 do
		for col = 0, 3 do
			k += 1
			if k ~= 7 then
				local a = -p.w / 2 + 0.55 + col * 0.72 + (row % 2) * 0.12
				local y = p.y1 - 0.7 - row * 0.85
				part(M, "Note", Vector3.new(0.55, 0.55, 0.03), at(f, a, y, 0.2) * CFrame.Angles(0, 0, math.rad(((k * 7) % 11) - 5)),
					NOTES[k % #NOTES + 1])
			end
		end
	end
	-- the growth chart, right 40%: axes, a rising line, its arrow
	local ax, ay = p.w * 0.12, p.y0 + 0.55
	local aw, ah = p.w * 0.34, h - 1.2
	stroke(M, f, ax, ay, ax + aw, ay, 0.2, 0.07, C.ink)
	stroke(M, f, ax, ay, ax, ay + ah, 0.2, 0.07, C.ink)
	local pts = { { 0.05, 0.1 }, { 0.3, 0.28 }, { 0.5, 0.22 }, { 0.72, 0.55 }, { 0.95, 0.92 } }
	for i = 1, #pts - 1 do
		stroke(M, f, ax + pts[i][1] * aw, ay + pts[i][2] * ah, ax + pts[i + 1][1] * aw, ay + pts[i + 1][2] * ah, 0.21, 0.1, C.blue)
	end
	local tipA, tipY = ax + 0.95 * aw, ay + 0.92 * ah
	stroke(M, f, tipA, tipY, tipA - 0.35, tipY - 0.05, 0.21, 0.1, C.blue)
	stroke(M, f, tipA, tipY, tipA - 0.08, tipY - 0.36, 0.21, 0.1, C.blue)
	-- the tray and two markers
	part(M, "Tray", Vector3.new(p.w * 0.6, 0.08, 0.3), at(f, 0, p.y0 - 0.02, 0.25), C.asphalt)
	part(M, "Marker", Vector3.new(0.5, 0.1, 0.1), at(f, -0.6, p.y0 + 0.06, 0.25), C.blue)
	part(M, "Marker", Vector3.new(0.5, 0.1, 0.1), at(f, 0.1, p.y0 + 0.06, 0.25), C.ink)
end

function B.mugShelf(p, f, M)
	shelfPlank(M, f, p.w, p.y0 + 0.1, p.depth)
	local top = p.y0 + 0.2
	for k, col in { C.paper, C.blue, C.paper, C.gold } do
		local a = -p.w / 2 + 0.45 + (k - 1) * 0.5
		part(M, "Cup", Vector3.new(0.4, 0.34, 0.34), at(f, a, top + 0.2, p.depth / 2) * CFrame.Angles(0, 0, math.rad(90)), col, { Shape = Enum.PartType.Cylinder })
	end
	part(M, "Canister", Vector3.new(0.6, 0.45, 0.45), at(f, 0.9, top + 0.3, p.depth / 2) * CFrame.Angles(0, 0, math.rad(90)), C.ink, { Shape = Enum.PartType.Cylinder })
	part(M, "PotS", Vector3.new(0.4, 0.42, 0.42), at(f, 1.45, top + 0.2, p.depth / 2) * CFrame.Angles(0, 0, math.rad(90)), C.concrete, { Shape = Enum.PartType.Cylinder })
	part(M, "LeavesS", Vector3.new(0.6, 0.6, 0.6), at(f, 1.45, top + 0.65, p.depth / 2), C.leaf, { Shape = Enum.PartType.Ball })
end

function B.pinboard(p, f, M)
	local h = p.y1 - p.y0
	local cy = p.y0 + h / 2
	part(M, "CorkFrame", Vector3.new(p.w, h, 0.1), at(f, 0, cy, 0.06), C.oakDark, { Material = Enum.Material.Wood })
	part(M, "Cork", Vector3.new(p.w - 0.28, h - 0.28, 0.04), at(f, 0, cy, 0.13), Color3.fromRGB(206, 160, 108))
	local items = {
		{ -1.1, 0.55, 1.0, 1.3, C.paper, -4 }, { 0.15, 0.6, 0.9, 0.7, C.glass, 3 }, { 1.2, 0.4, 0.8, 1.1, C.paper, 6 },
		{ -0.9, -0.75, 1.1, 0.8, C.calGold, 5 }, { 0.4, -0.55, 0.9, 1.0, C.paper, -3 }, { 1.35, -0.85, 0.6, 0.6, C.lawn, -7 },
	}
	for _, it in items do
		part(M, "Pinned", Vector3.new(it[3], it[4], 0.02), at(f, it[1], cy + it[2], 0.16) * CFrame.Angles(0, 0, math.rad(it[6])), it[5])
		part(M, "Pin", Vector3.new(0.12, 0.12, 0.08), at(f, it[1], cy + it[2] + it[4] / 2 - 0.12, 0.19), C.blue)
	end
end

-- the wall TV: a rising bar chart (later: the player's own revenue)
function B.tv(p, f, M)
	local h = p.y1 - p.y0
	local cy = p.y0 + h / 2
	part(M, "TvBody", Vector3.new(p.w, h, 0.22), at(f, 0, cy, 0.13), C.ink)
	local screen = part(M, "TvScreen", Vector3.new(p.w - 0.25, h - 0.25, 0.03), at(f, 0, cy, 0.25), Color3.fromRGB(20, 34, 52))
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 50
	sg.LightInfluence = 0
	sg.MaxDistance = 90
	sg.Parent = screen
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(18, 32, 50)
	bg.BorderSizePixel = 0
	bg.Parent = sg
	local heights = { 0.18, 0.26, 0.24, 0.38, 0.5, 0.62, 0.82 }
	for i, v in heights do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0, 1)
		bar.Position = UDim2.fromScale(0.08 + (i - 1) * 0.12, 0.88)
		bar.Size = UDim2.fromScale(0.08, v * 0.8)
		bar.BackgroundColor3 = C.blue:Lerp(C.cyan, i / #heights)
		bar.BorderSizePixel = 0
		bar.Parent = bg
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.15, 0)
		corner.Parent = bar
	end
	local base = Instance.new("Frame")
	base.Position = UDim2.fromScale(0.05, 0.88)
	base.Size = UDim2.new(0.9, 0, 0, 3)
	base.BackgroundColor3 = C.paper
	base.BorderSizePixel = 0
	base.Parent = bg
	part(M, "TvMount", Vector3.new(0.8, 0.8, 0.12), at(f, 0, cy, 0.03), C.asphalt)
end

-- along-the-wall offset du (u - the piece's own u) -> "a" (to the right as you face it)
local function aOf(wall, du) return (wall == "left") and -du or du end

-- v3: the wall's own skin, warm cream, cut round the window (the mesh is a flat white)
function B.cladding(p, f, M)
	local col = Color3.fromRGB(238, 226, 204)
	local u0, u1 = p.u - p.w / 2, p.u + p.w / 2
	local win = L.WINDOWS[p.wall]
	local function slab(a0, a1, y0, y1)
		if a1 - a0 < 0.05 or y1 - y0 < 0.05 then return end
		local da = aOf(p.wall, (a0 + a1) / 2 - p.u)
		part(M, "Skin", Vector3.new(a1 - a0, y1 - y0, 0.04), at(f, da, (y0 + y1) / 2, 0.025), col)
	end
	slab(u0, win.u0, p.y0, p.y1)
	slab(win.u1, u1, p.y0, p.y1)
	slab(win.u0, win.u1, p.y0, win.y0)
	slab(win.u0, win.u1, win.y1, p.y1)
end

-- v3: image 2's sage band, an oak rail on top, a dark skirting under it
function B.wainscot(p, f, M)
	local h = p.y1 - p.y0
	part(M, "Band", Vector3.new(p.w, h, 0.05), at(f, 0, p.y0 + h / 2, 0.07), Color3.fromRGB(146, 170, 136))
	part(M, "Rail", Vector3.new(p.w, 0.2, 0.12), at(f, 0, p.y1, 0.1), C.oak, { Material = Enum.Material.Wood })
	part(M, "Skirting", Vector3.new(p.w, 0.3, 0.1), at(f, 0, p.y0 + 0.15, 0.1), C.asphalt)
end

local function pot(M, f, a, y, o, size, leafCol)
	part(M, "Pot", Vector3.new(size * 0.85, size * 0.75, size * 0.85), at(f, a, y + size * 0.375, o), C.concrete)
	part(M, "Leaves", Vector3.new(size * 1.3, size * 1.1, size * 1.3), at(f, a, y + size * 1.15, o), leafCol or C.leaf,
		{ Shape = Enum.PartType.Ball })
end

function B.plantShelf(p, f, M)
	shelfPlank(M, f, p.w, p.y0 + 0.1, p.depth)
	local top = p.y0 + 0.2
	pot(M, f, -p.w / 2 + 0.7, top, p.depth / 2, 0.6)
	pot(M, f, 0.1, top, p.depth / 2, 0.75, C.lawn)
	pot(M, f, p.w / 2 - 0.7, top, p.depth / 2, 0.55)
	-- a trailing vine over the edge
	for k = 0, 4 do
		part(M, "Vine", Vector3.new(0.32, 0.32, 0.32), at(f, -p.w / 2 + 0.75 + (k % 2) * 0.12, top - 0.2 - k * 0.32, p.depth - 0.15), C.leaf,
			{ Shape = Enum.PartType.Ball })
	end
end

-- a chalkboard menu over the coffee bar: lines of chalk and a cup, no words
function B.menuBoard(p, f, M)
	local h = p.y1 - p.y0
	local cy = p.y0 + h / 2
	part(M, "MenuFrame", Vector3.new(p.w, h, 0.1), at(f, 0, cy, 0.06), C.oakDark, { Material = Enum.Material.Wood })
	part(M, "Chalkboard", Vector3.new(p.w - 0.25, h - 0.25, 0.04), at(f, 0, cy, 0.12), Color3.fromRGB(40, 54, 50))
	for k = 0, 3 do
		local y = p.y1 - 0.55 - k * 0.42
		stroke(M, f, -p.w / 2 + 0.4, y, -p.w / 2 + 0.4 + 1.1 + (k % 2) * 0.35, y, 0.15, 0.06, C.paper)
		stroke(M, f, p.w / 2 - 1.0, y, p.w / 2 - 0.45, y, 0.15, 0.06, C.calGold)
	end
	-- the cup
	local ca, cyb = 0.05, p.y0 + 0.45
	stroke(M, f, ca - 0.3, cyb + 0.55, ca - 0.22, cyb, 0.15, 0.07, C.paper)
	stroke(M, f, ca + 0.3, cyb + 0.55, ca + 0.22, cyb, 0.15, 0.07, C.paper)
	stroke(M, f, ca - 0.22, cyb, ca + 0.22, cyb, 0.15, 0.07, C.paper)
	stroke(M, f, ca + 0.3, cyb + 0.45, ca + 0.5, cyb + 0.3, 0.15, 0.06, C.paper)
end

function B.poster(p, f, M)
	local h = p.y1 - p.y0
	picture(M, f, 0, p.y0 + h / 2, p.w, h, (p.wall == "back") and 2 or 1)
end

function B.tvShelf(p, f, M)
	shelfPlank(M, f, p.w, p.y0 + 0.1, p.depth)
	local top = p.y0 + 0.2
	books(M, f, -p.w / 2 + 0.3, -0.2, top, p.depth, 3)
	trophy(M, f, 0.45, top, p.depth / 2)
	pot(M, f, p.w / 2 - 0.6, top, p.depth / 2, 0.6)
end

-- v3: a neon rocket on the right wall, no backing (image 5's corner sign)
function B.neonRocket(p, f, M)
	local h = p.y1 - p.y0
	local host = part(M, "NeonRocket", Vector3.new(p.w, h, 0.05), at(f, 0, p.y0 + h / 2, 0.08), C.paper, { Transparency = 1 })
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0
	sg.Brightness = 2
	sg.MaxDistance = 120
	sg.Parent = host
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.Image = ROCKET
	img.ImageColor3 = Color3.fromRGB(255, 196, 96)
	img.ScaleType = Enum.ScaleType.Fit
	img.Parent = sg
end

-- pendant lamps in a row along x: cord, shade, bulb; the first one lights the room
function B.pendants(p, M, pivot)
	local n = p.n or 2
	for i = 1, n do
		local x = (n == 1) and p.x or (p.x - (p.w - 1.2) / 2 + (i - 1) * (p.w - 1.2) / (n - 1))
		local top = L.CEIL + 0.8
		local shadeY = p.y0 + 0.55
		part(M, "Cord", Vector3.new(0.07, top - shadeY, 0.07), pivot * CFrame.new(x, (top + shadeY) / 2, p.z), C.ink)
		cyl(M, "Shade", 0.7, 1.35, pivot * CFrame.new(x, shadeY, p.z), C.ink, { Material = Enum.Material.Metal })
		cyl(M, "ShadeRim", 0.08, 1.45, pivot * CFrame.new(x, shadeY - 0.36, p.z), C.asphalt)
		local bulb = part(M, "Bulb", Vector3.new(0.5, 0.5, 0.5), pivot * CFrame.new(x, shadeY - 0.38, p.z), C.warm,
			neon({ Shape = Enum.PartType.Ball }))
		if p.light and i == 1 then light(bulb, 15, 1.1, p.id == "deskLamps") end
	end
end

function B.duct(p, M, pivot)
	local y = (p.y0 + p.y1) / 2
	local dia = p.y1 - p.y0
	part(M, "Duct", Vector3.new(p.d, dia, dia), pivot * CFrame.new(p.x, y, p.z) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(150, 152, 156),
		{ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal })
	local n = math.floor(p.d / 4)
	for k = 0, n do
		local z = p.z - p.d / 2 + 0.5 + k * ((p.d - 1) / n)
		part(M, "DuctRing", Vector3.new(0.18, dia + 0.12, dia + 0.12), pivot * CFrame.new(p.x, y, z) * CFrame.Angles(0, math.rad(90), 0), C.asphalt,
			{ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal })
		if k % 2 == 0 then
			part(M, "Hanger", Vector3.new(0.08, L.CEIL + 0.8 - p.y1, 0.08), pivot * CFrame.new(p.x, (L.CEIL + 0.8 + p.y1) / 2, z), C.ink)
		end
	end
end

function B.track(p, M, pivot)
	local y = p.y1 - 0.1
	part(M, "Rail", Vector3.new(p.w, 0.14, 0.14), pivot * CFrame.new(p.x, y, p.z), C.ink)
	for _, s in { -1, 1 } do
		part(M, "Hanger", Vector3.new(0.07, L.CEIL + 0.8 - y, 0.07), pivot * CFrame.new(p.x + s * (p.w / 2 - 0.4), (L.CEIL + 0.8 + y) / 2, p.z), C.ink)
	end
	for k = 0, 4 do
		local x = p.x - p.w / 2 + 1.2 + k * ((p.w - 2.4) / 4)
		local head = pivot * CFrame.new(x, y - 0.42, p.z) * CFrame.Angles(math.rad(35), 0, 0)
		part(M, "Spot", Vector3.new(0.55, 0.36, 0.36), head * CFrame.Angles(0, math.rad(90), math.rad(90)), C.ink,
			{ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal })
		part(M, "SpotLens", Vector3.new(0.05, 0.3, 0.3), head * CFrame.new(0, -0.29, 0) * CFrame.Angles(0, 0, math.rad(90)), C.warm,
			neon({ Shape = Enum.PartType.Cylinder }))
	end
end

-- ---------------------------------------------------------------- the room
local SOLIDISH = { rack = true, beanbag = true, lowTable = true, coffee = true }

-- garage: plot.garage; g: plot.g; FK: FurnitureKit. Returns the number of pieces built.
function GarageDress.dress(garage, g, FK)
	local problems = L.check()
	if #problems > 0 then
		warn("[SV] garage layout refused: " .. problems[1])
		return 0
	end
	local pivot = g(0, 0, 0)
	local root = Instance.new("Folder")
	root.Name = "Dressing"
	local built = 0
	for _, p in L.PIECES do
		local fn = p.build and B[p.build]
		if fn then
			local M = Instance.new("Model")
			M.Name = p.id
			M.Parent = root
			local ok, err
			if p.kind == "wall" then
				local f = wallFrame(pivot, p.wall, p.u, 0)
				ok, err = pcall(fn, p, f, M)
			else
				ok, err = pcall(fn, p, M, pivot, FK)
			end
			if not ok then
				warn(("[SV] garage piece %s failed: %s"):format(p.id, tostring(err)))
				M:Destroy()
			elseif #M:GetChildren() == 0 then
				M:Destroy()
			else
				if SOLIDISH[p.build] then M:SetAttribute("FKItem", p.id) end
				built += 1
			end
		end
	end
	root.Parent = garage
	return built
end

return GarageDress
