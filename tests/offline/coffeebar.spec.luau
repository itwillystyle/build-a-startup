-- coffeebar.spec.luau: the cafe's coffee bar stands where the kitchenette stood, faces the room, clears the fridge (14 Oct 2026)
local C = require("../../src/ReplicatedStorage/CoffeeBar")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-4) end

-- the exported bar, measured by rack_export.py and again in Studio after the import (14 Oct)
local MEASURED = Vector3.new(5.74, 5.07, 1.895)

test("the mesh's front (+Z) faces the room (-Z), like the rack", function()
	local front = C.pose(20, MEASURED):VectorToWorldSpace(Vector3.new(0, 0, 1))
	assert(near(front.X, 0) and near(front.Y, 0) and near(front.Z, -1), "front points " .. tostring(front))
end)

test("on the floor, centred on the wedge, its back flush with the run's back (so it clears the glass as the run did)", function()
	local z = 20
	local cf = C.pose(z, MEASURED)
	assert(near(cf.Position.Y - MEASURED.Y / 2, 0), "bottom off the floor")
	assert(near(cf.Position.X, 0), "not centred on the wedge")
	local back = cf.Position.Z + MEASURED.Z / 2
	assert(near(back, z + C.RUN.DEPTH / 2), ("back at %.3f, the run's back at %.3f"):format(back, z + C.RUN.DEPTH / 2))
end)

test("the layout is the 5 Oct run: flush bars, the cap, the fridge a hand's width on", function()
	local L = C.layout()
	assert(near(L.b2 - L.b1, C.RUN.BAR_W), "the two bars must touch (the 5 Oct gaps)")
	assert(near(L.runLeft, -(C.RUN.BAR_W * 2 + C.RUN.END_W) / 2), "the run is centred")
	assert(near(L.fridgeX - C.RUN.FRIDGE_W / 2 - L.runRight, C.RUN.FRIDGE_GAP), "the fridge gap")
	-- pinned against the numbers the old inline code used, so a drift is caught
	assert(near(L.b1, -1.565) and near(L.cap, 2.53) and near(L.fridgeX, 4.295), ("layout moved: %.3f %.3f %.3f"):format(L.b1, L.cap, L.fridgeX))
end)

test("the measured bar clears the fridge, and a wider one would not", function()
	local L = C.layout()
	local fridgeLeft = L.fridgeX - C.RUN.FRIDGE_W / 2
	assert(MEASURED.X / 2 < fridgeLeft, ("bar edge %.2f into the fridge at %.2f"):format(MEASURED.X / 2, fridgeLeft))
	assert(C.SLOT.X / 2 < fridgeLeft, "the slot itself must clear the fridge, or fits() lets a bar into it")
	assert(not (6.2 / 2 < fridgeLeft), "a 6.2-wide bar must be shown to reach the fridge (the check can fail)")
end)

test("fits: the real bar yes; too wide, tall, deep or a wrong-scale speck no", function()
	assert(C.fits(MEASURED), "the real bar must fit")
	assert(not C.fits(Vector3.new(6.0, 5.0, 1.8)), "too wide")
	assert(not C.fits(Vector3.new(5.7, 6.5, 1.8)), "too tall")
	assert(not C.fits(Vector3.new(5.7, 5.0, 2.1)), "too deep: would push into the glass")
	assert(not C.fits(Vector3.new(0.0574, 0.0507, 0.019)), "a wrong-scale import must fall back to the run")
end)

test("its in-game name carries a prefix Palette leaves alone", function()
	local fake = { GetService = function() return {} end }
	local hadGame = (getfenv(0) :: any).game
	pcall(function() (getfenv(0) :: any).game = hadGame or fake end)
	local ok, Palette = pcall(require, "../../src/ReplicatedStorage/Palette")
	assert(ok, "Palette must load offline: " .. tostring(Palette))
	assert(Palette.isOurs(C.NAME), C.NAME .. " is not an own-pipeline name")
end)

return T
