--[[ chaseframe.spec.luau -- the framing contract, in screen space.

	ChaseFrame measures what the player SEES: where a point lands in the frame,
	how big a body is as a fraction of frame height, how far the horizon leans.
	These tests pin the projection maths to values that can be worked out by
	hand, so a sign error or a swapped axis fails here rather than in a recording.
]]
local F = require("../../src/ReplicatedStorage/ChaseFrame")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local FOV = 70
local ASPECT = 16 / 9
local ORIGIN = CFrame.new(0, 0, 0)

local function near(actual, expected, eps, what)
	assert(math.abs(actual - expected) <= eps,
		string.format("%s: got %.4f, want %.4f (+/- %g)", what, actual, expected, eps))
end

local function joined(failures)
	return table.concat(failures, " | ")
end

local function hasFailure(result, fragment)
	for _, f in result.failures do
		if string.find(f, fragment, 1, true) then return true end
	end
	return false
end

-- The well-framed shot from the brief: 12 studs behind the player, 4 up, looking at them.
local PLAYER = Vector3.new(0, 3, 0)
local HEADING = Vector3.new(0, 0, -1)
local FRAMED = CFrame.lookAt(Vector3.new(0, 7, 12), PLAYER)

-- ------------------------------------------------------------------ projection

test("a point straight ahead projects to the centre of the frame", function()
	local sx, sy, depth, on = F.project(ORIGIN, FOV, ASPECT, Vector3.new(0, 0, -10))
	near(sx, 0.5, 1e-6, "centre sx")
	near(sy, 0.5, 1e-6, "centre sy")
	near(depth, 10, 1e-6, "centre depth")
	assert(on, "a point straight ahead must be on screen")
end)

test("a point to the camera's right has sx > 0.5, and a point above has sy < 0.5", function()
	local sxRight = F.project(ORIGIN, FOV, ASPECT, Vector3.new(3, 0, -10))
	assert(sxRight > 0.5, string.format("right of camera should give sx > 0.5, got %.4f", sxRight))
	local _, syAbove = F.project(ORIGIN, FOV, ASPECT, Vector3.new(0, 3, -10))
	assert(syAbove < 0.5, string.format("above the camera should give sy < 0.5 (top is 0), got %.4f", syAbove))
end)

test("a point exactly half the vertical FOV above the axis lands on the top edge", function()
	-- tan(half FOV) * distance is the height that subtends exactly half the frame
	local y = math.tan(math.rad(FOV) / 2) * 10
	local _, sy = F.project(ORIGIN, FOV, ASPECT, Vector3.new(0, y, -10))
	near(sy, 0, 1e-6, "top edge sy")
end)

test("aspect widens the horizontal: the same angle off-axis is nearer centre on a wider screen", function()
	local narrow = F.project(ORIGIN, FOV, 1, Vector3.new(5, 0, -10))
	local wide = F.project(ORIGIN, FOV, 2, Vector3.new(5, 0, -10))
	assert(math.abs(wide - 0.5) < math.abs(narrow - 0.5),
		string.format("aspect 2 should pull sx toward centre: narrow %.4f, wide %.4f", narrow, wide))
end)

test("a point behind the camera is not on screen and reports a negative depth", function()
	local _, _, depth, on = F.project(ORIGIN, FOV, ASPECT, Vector3.new(0, 0, 10))
	assert(not on, "a point behind the camera must not be on screen")
	assert(depth < 0, string.format("behind-camera depth should be negative, got %.3f", depth))
end)

-- ----------------------------------------------------------- apparent height

test("apparent height roughly halves when the distance doubles", function()
	local near10 = F.apparentHeight(ORIGIN, FOV, ASPECT, Vector3.new(0, 0, -10), 2)
	local far20 = F.apparentHeight(ORIGIN, FOV, ASPECT, Vector3.new(0, 0, -20), 2)
	assert(near10 > 0, "a 2-stud object 10 studs away must have a positive apparent height")
	local ratio = far20 / near10
	assert(math.abs(ratio - 0.5) < 0.01,
		string.format("doubling distance should halve apparent height, ratio was %.4f", ratio))
end)

test("apparent height is zero when the object is behind the camera", function()
	local h = F.apparentHeight(ORIGIN, FOV, ASPECT, Vector3.new(0, 0, 10), 5)
	assert(h == 0, string.format("behind-camera apparent height should be 0, got %.4f", h))
end)

-- -------------------------------------------------------------- tilt and yaw

test("tilt of a camera rolled 10 degrees is about 10 (either sign), and a level camera is 0", function()
	local rolled = CFrame.lookAt(Vector3.new(0, 5, 10), Vector3.new(0, 5, 0)) * CFrame.Angles(0, 0, math.rad(10))
	local t = F.tilt(rolled)
	assert(math.abs(math.abs(t) - 10) < 0.2,
		string.format("a 10 degree roll should read as about +/-10 deg of tilt, got %.3f", t))
	local level = CFrame.lookAt(Vector3.new(0, 5, 10), Vector3.new(0, 5, 0))
	assert(math.abs(F.tilt(level)) < 1e-6,
		string.format("a level camera should have zero tilt, got %.6f", F.tilt(level)))
end)

test("yaw is 0 when looking along the heading and about 30 when turned 30 degrees about Y", function()
	local along = CFrame.lookAt(Vector3.new(0, 5, 10), Vector3.new(0, 5, 0))
	local y0 = F.yawFrom(along, Vector3.new(0, 0, -1))
	assert(y0 < 1e-3, string.format("looking along the heading should give yaw 0, got %.4f", y0))
	local turned = along * CFrame.Angles(0, math.rad(30), 0)
	local y30 = F.yawFrom(turned, Vector3.new(0, 0, -1))
	assert(math.abs(y30 - 30) < 0.5, string.format("a 30 degree turn should give yaw about 30, got %.3f", y30))
end)

test("yaw ignores camera pitch: looking steeply down along the heading is still yaw 0", function()
	local down = CFrame.lookAt(Vector3.new(0, 30, 0), Vector3.new(0, 0, -1))
	local y = F.yawFrom(down, Vector3.new(0, 0, -1))
	assert(y < 1, string.format("pitch alone must not count as yaw, got %.3f", y))
end)

-- ------------------------------------------------------------------- check()

test("check passes a well-framed shot: 12 studs behind, 4 up, the player centred", function()
	-- The hunter is 25 studs back, outside the 20-stud range, and behind the camera.
	local r = F.check(FRAMED, FOV, ASPECT, {
		playerPos = PLAYER,
		heading = HEADING,
		hunterPos = Vector3.new(0, 3, 25),
	})
	assert(r.ok, "a well-framed shot should pass, failures: " .. joined(r.failures))
	near(r.metrics.sx, 0.5, 1e-3, "framed sx")
	assert(r.metrics.playerH >= 0.09 and r.metrics.playerH <= 0.7,
		string.format("framed player height should be readable, got %.3f", r.metrics.playerH))
end)

test("check passes a well-framed shot with no hunter at all", function()
	local r = F.check(FRAMED, FOV, ASPECT, { playerPos = PLAYER, heading = HEADING })
	assert(r.ok, "a shot with no hunter should pass, failures: " .. joined(r.failures))
	assert(r.metrics.hunterH == nil, "hunter metrics must be absent when no hunter is given")
end)

test("check fails a hunter 8 studs behind the player as filling the frame", function()
	-- The brief placed the hunter 8 studs behind the player, between camera and player.
	-- That puts it 5.7 studs from the lens, and it covers about 63% of the frame height.
	-- No camera 12 studs back can keep an 8-stud-behind hunter under the 30% cap, so
	-- this is the bug class the contract exists to catch, not a fixture to pass.
	local r = F.check(FRAMED, FOV, ASPECT, {
		playerPos = PLAYER,
		heading = HEADING,
		hunterPos = Vector3.new(0, 3, 8),
	})
	assert(not r.ok, "a hunter 8 studs behind at 12 studs camera distance must fail")
	assert(hasFailure(r, "hunter fills the frame"),
		"expected the hunter-fills-the-frame rule, got: " .. joined(r.failures))
	assert(#r.failures == 1, "only the hunter rule should fail here, got: " .. joined(r.failures))
end)

test("check fails, naming the rule, when the player is off-centre", function()
	-- Camera looks at the origin; the player stands 7 studs to the right, which is sx 0.72.
	local cam = CFrame.lookAt(Vector3.new(0, 7, 12), PLAYER)
	local r = F.check(cam, FOV, ASPECT, { playerPos = Vector3.new(7, 3, 0), heading = HEADING })
	assert(not r.ok, "an off-centre player must fail")
	assert(hasFailure(r, "player off-centre"),
		"expected the off-centre rule, got: " .. joined(r.failures))
end)

test("check fails, naming the rule, when the player is too small (camera 80 studs away)", function()
	local cam = CFrame.lookAt(Vector3.new(0, 7, 80), PLAYER)
	local r = F.check(cam, FOV, ASPECT, { playerPos = PLAYER, heading = HEADING })
	assert(not r.ok, "a player 80 studs away must fail")
	assert(hasFailure(r, "player too small"),
		"expected the too-small rule, got: " .. joined(r.failures))
end)

test("check fails, naming the rule, when a hunter 2 studs from the camera fills the frame", function()
	local hunter = FRAMED.Position + FRAMED.LookVector * 2
	local r = F.check(FRAMED, FOV, ASPECT, {
		playerPos = PLAYER,
		heading = HEADING,
		hunterPos = hunter,
	})
	assert(not r.ok, "a hunter 2 studs from the lens must fail")
	assert(hasFailure(r, "hunter fills the frame"),
		"expected the hunter-fills-the-frame rule, got: " .. joined(r.failures))
end)

test("check fails, naming the rule, when the horizon is tilted 15 degrees", function()
	local rolled = FRAMED * CFrame.Angles(0, 0, math.rad(15))
	local r = F.check(rolled, FOV, ASPECT, { playerPos = PLAYER, heading = HEADING })
	assert(not r.ok, "a 15 degree roll must fail")
	assert(hasFailure(r, "horizon tilted"),
		"expected the tilt rule, got: " .. joined(r.failures))
end)

test("check fails, naming the rule, when the camera yaws 40 degrees off the heading", function()
	-- Keep the camera on the player and rotate the travel heading 40 degrees instead.
	local heading = Vector3.new(math.sin(math.rad(40)), 0, -math.cos(math.rad(40)))
	local r = F.check(FRAMED, FOV, ASPECT, { playerPos = PLAYER, heading = heading })
	assert(not r.ok, "a 40 degree yaw must fail")
	assert(hasFailure(r, "camera yaw"),
		"expected the yaw rule, got: " .. joined(r.failures))
end)

test("the contract exposes every threshold the rules read", function()
	local C = F.CONTRACT
	for _, key in
		{ "PLAYER_X", "PLAYER_Y_MIN", "PLAYER_Y_MAX", "PLAYER_MIN_H", "HUNTER_RANGE",
		  "HUNTER_MAX_H", "TILT_MAX", "YAW_MAX", "PLAYER_HEIGHT", "HUNTER_HEIGHT" }
	do
		assert(type(C[key]) == "number", "CONTRACT is missing a numeric threshold: " .. key)
	end
end)

return T
