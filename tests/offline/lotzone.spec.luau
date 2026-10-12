-- lotzone.spec.luau: the rail's "on your lot" test (12 Oct 2026)
local L = require("../../src/ReplicatedStorage/LotZone")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

test("the whole measured lot is inside, the street outside, and a turned plot turns with it", function()
	local pivot = CFrame.new(100, 0, 50) * CFrame.Angles(0, math.rad(30), 0)
	local function at(x, z) return pivot:PointToWorldSpace(Vector3.new(x, 3, z)) end
	for _, c in { { 0, 0 }, { -117, -119 }, { 115, 116 }, { -117, 116 } } do
		assert(L.contains(pivot, at(c[1], c[2]), false), ("(%d, %d) is on the lot"):format(c[1], c[2]))
	end
	assert(not L.contains(pivot, at(0, 160), false), "the street (160 studs out) is not the lot")
	assert(not L.contains(pivot, at(200, 0), false), "200 studs to the side is not the lot")
end)

test("hysteresis: on at 122, off only past 132, so the edge does not blink", function()
	local p = CFrame.new()
	assert(not L.contains(p, Vector3.new(127, 0, 0), false), "127 out: not yet on")
	assert(L.contains(p, Vector3.new(127, 0, 0), true), "127 while on: still on")
	assert(not L.contains(p, Vector3.new(135, 0, 0), true), "135: off")
end)

test("neighbouring plots (336 apart on the ring) never share a zone", function()
	assert(L.HALF_OUT * 2 < 336, "two zones would touch")
end)

return T
