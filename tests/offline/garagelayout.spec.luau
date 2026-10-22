-- garagelayout.spec.luau: the dressed garage keeps the game clear (12 Oct 2026)
local L = require("../../src/ReplicatedStorage/GarageLayout")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local function copy(list)
	local out = {}
	for _, p in list do
		local c = {}
		for k, v in p do c[k] = v end
		table.insert(out, c)
	end
	return out
end

local function with(extra)
	local list = copy(L.PIECES)
	table.insert(list, extra)
	return L.check(list)
end

local function says(problems, needle)
	for _, s in problems do
		if s:find(needle, 1, true) then return true end
	end
	return false
end

test("the real layout: nothing in the walkway, the pads, the desk or the door, nothing over a window", function()
	local problems = L.check()
	assert(#problems == 0, "the layout has problems:\n  " .. table.concat(problems, "\n  "))
end)

test("the spawn, the camera behind it and the laptop line all lie in kept floor", function()
	local w, d = L.KEEP.walkway, L.KEEP.desk
	local function inside(r, x, z) return x >= r[1] and x <= r[2] and z >= r[3] and z <= r[4] end
	assert(inside(w, 0, 0), "the spawn (0, 0) is on the walkway")
	assert(inside(w, 0, 12.5), "the camera behind the spawn (0, 12.5) is on the walkway")
	for z = -6.5, 0, 0.5 do assert(inside(w, 0, z), "spawn -> laptop at z " .. z) end
	assert(inside(d, 0, -9), "the laptop (0, -9) is in the desk zone")
end)

test("the check catches a sofa in the walkway", function()
	assert(says(with({ id = "x", kind = "floor", x = 0, z = 5, w = 2, d = 2, h = 2 }), "x: stands in the walkway"))
end)

test("the check catches a crate on the hire pad and one on the HQ pad", function()
	assert(says(with({ id = "x", kind = "floor", x = -11, z = 4, w = 1, d = 1, h = 1 }), "x: stands in the hirePad"))
	assert(says(with({ id = "y", kind = "floor", x = 13, z = 8, w = 1, d = 1, h = 1 }), "y: stands in the hqPad"))
end)

test("the check catches a poster over a window and a shelf through a wall", function()
	assert(says(with({ id = "x", kind = "wall", wall = "left", u = 0, w = 2, y0 = 6, y1 = 8, depth = 0.1 }), "x: covers the left window"))
	assert(says(with({ id = "y", kind = "floor", x = 17.2, z = -6, w = 1, d = 1, h = 1 }), "y: through a wall"))
end)

test("the check catches two things in each other and a lamp in front of the TV", function()
	assert(says(with({ id = "x", kind = "floor", x = -12.5, z = -9, w = 1, d = 1, h = 1 }), "table and x stand in each other"))
	assert(says(with({ id = "y", kind = "floor", x = 17.0, z = -5.5, w = 0.7, d = 0.7, h = 5.1 }), "y stands in front of tv"))
end)

test("a phone can afford the lights: at most 6 new ones", function()
	assert(L.lights() <= 6, ("%d lights"):format(L.lights()))
end)

-- 22 Oct, art pass 1 (Luke's picked mock ui/art-pass/garage-outside.png; spec
-- docs/superpowers/specs/2026-10-22-art-pass-design.md): a wood floor, string lights,
-- a teal wainscot and runner, a warmer wall. Colours live in L.COLORS so they can be
-- checked here against the palette (a colour the sweep repaints is not the mock's).
local function piece(id)
	for _, p in L.PIECES do if p.id == id then return p end end
	return nil
end

test("art pass: string lights hang overhead and add no light sources", function()
	local s = piece("stringLights")
	assert(s and s.kind == "ceil", "a ceiling piece named stringLights")
	assert(s.y0 >= 8, ("its lowest bulb at %.1f studs: it must clear every head"):format(s and s.y0 or -1))
	assert(not s.light, "bulbs are Neon only; the room's light budget is already spent")
	assert(#L.check() == 0, "the layout is still clean: " .. tostring(L.check()[1]))
end)

test("art pass: an oak floor under everything, below every rug and pad", function()
	local f = piece("floorBoards")
	assert(f and f.kind == "rug", "a floor-level piece named floorBoards")
	assert(f.w >= 2 * L.HALF_X - 1 and f.d >= (L.FRONT - L.BACK) - 1, "it covers the room wall to wall")
	assert((f.top or 1) <= 0.02, "its top sits under the rugs (0.05) and the pad glows (0.06)")
end)

test("art pass: the room's new colours are the mock's and stay on the palette", function()
	-- selene: allow(incorrect_standard_library_use)
	game = game or { GetService = function() return { HasTag = function() return false end } end }
	local Palette = require("../../src/ReplicatedStorage/Palette")
	local want = { wainscot = { 40, 150, 160 }, runner = { 40, 150, 160 }, cladding = { 226, 211, 183 }, floor = { 150, 104, 64 },
		sofa = { 62, 110, 158 } }
	for k, rgb in want do
		local c = L.COLORS and L.COLORS[k]
		assert(c and c[1] == rgb[1] and c[2] == rgb[2] and c[3] == rgb[3], "L.COLORS." .. k)
		local m = Palette.map(Color3.fromRGB(c[1], c[2], c[3]))
		local back = { math.round(m.R * 255), math.round(m.G * 255), math.round(m.B * 255) }
		assert(math.abs(back[1] - c[1]) <= 2 and math.abs(back[2] - c[2]) <= 2 and math.abs(back[3] - c[3]) <= 2,
			("%s %d,%d,%d is repainted to %d,%d,%d by the palette sweep"):format(k, c[1], c[2], c[3], back[1], back[2], back[3]))
	end
end)

return T
