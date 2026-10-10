--[[ movement.spec.luau -- the teleport rule, checked against real speeds.

	Movement.judge decides whether a move over the last half second is more than the
	character could have walked. Too strict and a lag burst rubber-bands an honest
	player mid-chase; too loose and a teleport onto the drop-off counts. The numbers
	here are the game's own: walk 16, the scooter's top carry speed and the BOOST dash
	(TalentDrop / RoomEconomy), and replication that arrives in bursts. ]]
local M = require("../../src/ServerScriptService/Movement")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local function far(dist, dt, speed)
	local tooFar = M.judge(0, 0, dist, 0, dt, speed)
	return tooFar
end

test("walking, sprinting on the scooter and dashing are never flagged", function()
	for _, case in { { 16, 0.5 }, { 27, 0.5 }, { 40, 0.5 }, { 60, 0.25 } } do
		local speed, dt = case[1], case[2]
		assert(not far(speed * dt, dt, speed), ("an honest %d stud/s move over %.2fs was flagged"):format(speed, dt))
	end
end)

test("a lag burst (half a second arriving at once, 30% fast) is not a teleport", function()
	assert(not far(27 * 0.5 * 1.3, 0.5, 27), "a 30%-fast burst at scooter speed was flagged")
	assert(not far(16 * 0.65, 0.5, 16), "a burst longer than the window was flagged at walking speed")
end)

test("teleports are flagged: onto the drop-off, next to a victim, to the lift", function()
	assert(far(140, 0.5, 27), "140 studs in half a second on the scooter (a skilled hire's walk home) passed")
	assert(far(40, 0.1, 16), "40 studs in a tenth of a second passed")
	assert(far(30, 0.5, 16), "30 studs in half a second at walking speed passed")
end)

test("falling is not teleporting: only horizontal distance counts", function()
	local tooFar = M.judge(0, 0, 0, 0, 0.5, 16)
	assert(not tooFar, "a straight drop was flagged")
end)

test("a slow WalkSpeed still gets the minimum allowance", function()
	-- a frozen or slowed character (WalkSpeed 0) must not be flagged for a nudge
	assert(not far(8, 0.5, 0), "an 8-stud nudge at WalkSpeed 0 was flagged")
end)

return T
