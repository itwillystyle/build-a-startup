-- serverrack.spec.luau: the Servers room's rack mesh stands where the plain rack stood, faces the room (13 Oct 2026)
local R = require("../../src/ReplicatedStorage/ServerRack")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-4) end

-- the exported rack, measured by rack_export.py and again in Studio after the import (13 Oct)
local MEASURED = Vector3.new(2.74, 6.71, 2.185)

test("the mesh's front (+Z) faces the room (-Z), not the wall: the first import showed its cables", function()
	local cf = R.pose(2, 10, MEASURED.Y)
	local front = cf:VectorToWorldSpace(Vector3.new(0, 0, 1))
	assert(near(front.X, 0) and near(front.Y, 0) and near(front.Z, -1), "front points " .. tostring(front))
end)

test("it stands on the floor, at the plain rack's spot (x, rm + 3)", function()
	for _, x in R.XS do
		local cf = R.pose(x, 10, MEASURED.Y)
		assert(near(cf.Position.Y - MEASURED.Y / 2, 0), "bottom off the floor at x " .. x)
		assert(near(cf.Position.X, x) and near(cf.Position.Z, 13), "moved off the old spot at x " .. x)
	end
	assert(#R.XS == 4, "four racks a room, as before")
end)

test("the measured mesh fits the plain rack's slot, and a bigger one would not", function()
	assert(R.fits(MEASURED), "the real rack must fit 3 x 7 x 2.2")
	assert(not R.fits(Vector3.new(3.5, 6.7, 2.1)), "too wide must fail (the winged rack was 10.6)")
	assert(not R.fits(Vector3.new(2.7, 7.4, 2.1)), "too tall must fail")
	assert(not R.fits(Vector3.new(2.7, 6.7, 2.4)), "too deep must fail")
end)

test("its in-game name carries a prefix Palette leaves alone (or the sweep washes it warm)", function()
	local fake = { GetService = function() return {} end }
	local hadGame = (getfenv(0) :: any).game
	pcall(function() (getfenv(0) :: any).game = hadGame or fake end)
	local ok, Palette = pcall(require, "../../src/ReplicatedStorage/Palette")
	assert(ok, "Palette must load offline: " .. tostring(Palette))
	assert(Palette.isOurs(R.NAME), R.NAME .. " is not an own-pipeline name")
	assert(not Palette.isOurs("Rack"), "the check must be able to fail")
end)

return T
