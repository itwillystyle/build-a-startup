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

return T
