--[[ camerawalls.spec.luau -- which walls the camera stops at, and where.

	CameraWalls decides two things both cameras rely on: which invisible parts
	stand in for a wall you can see (inside the plots only: the valley's hill
	wedges must still be skipped), and how far the lens may stay out. ]]
local W = require("../../src/ReplicatedStorage/CameraWalls")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

test("a building's invisible collider is a wall; a hill wedge, a visible part or a ghost is not", function()
	assert(W.isStandIn(1, true, true, true), "an HQ Wall (invisible, solid, in the plots) was not a wall")
	assert(not W.isStandIn(1, true, true, false), "a hill wedge outside the plots counted: the chase lens would dive for it")
	assert(not W.isStandIn(0, true, true, true), "a visible wall counted (Poppercam already stops at those)")
	assert(not W.isStandIn(1, false, true, true), "an invisible part you walk through counted")
	assert(not W.isStandIn(1, true, false, true), "a part raycasts cannot hit counted")
end)

test("the lens stops just short of the wall, never past it, never inside your head", function()
	assert(W.distance(12, nil) == 12, "with no wall the lens should stay where Roblox put it")
	assert(W.distance(12, 20) == 12, "a wall beyond the lens should change nothing")
	local d = W.distance(12, 6.8)
	assert(d < 6.8 and d > 6, ("a partition 6.8 away: want just short of it, got %.2f"):format(d))
	assert(W.distance(12, 0.2) == W.MIN, "a wall at your shoulder should give the minimum, not a negative distance")
end)

return T
