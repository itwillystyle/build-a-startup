--[[ worldfloors.spec.luau -- a lower storey's picture standing in the floor above.

	WorldHealth.pokes is the rule behind throughFloors. The numbers are the ones
	measured on 11 Oct: the Dome's garden deck 2 ran from 77.5 to 95.9 and floor 7
	is at 92; its own segment starts at 90.5 (its slab), the lift core storey at 90.5. ]]
local W = require("../../src/ServerScriptService/WorldHealth")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

test("the deck's tent through floor 7 is caught", function()
	assert(W.pokes(77.5, 95.9, 92), "deck 2 (77.5..95.9) through floor 7 (92) was not caught")
	assert(W.pokes(25.5, 44.2, 40), "deck 1 through floor 3 was not caught")
end)

test("a storey's own pieces and things that stop at the floor are not", function()
	assert(not W.pokes(90.5, 103.5, 92), "floor 7's own segment (its slab starts 1.5 under) was flagged")
	assert(not W.pokes(77.8, 92.0, 92), "the deck columns that stop at floor 7 were flagged")
	assert(not W.pokes(77.5, 90.45, 92), "the deck squashed to fit under floor 7 was flagged")
end)

test("the tower lobby's entrance canopy is a roof, and only it is exempt (not every 'Canopy')", function()
	-- 14 Oct (HQ tower 1a): Wafers builds a 22 x 10 CanCollide-false canopy 10 studs over the forecourt;
	-- it sits under MAX_Y, so the sinking check measured an 11.3 gap. Final review: a bare "Canopy"
	-- entry also exempted three unrelated parts (CampusArch x2, ValleyGen), so the tower's has its own name.
	local why = W.ALLOW.LobbyCanopy
	assert(type(why) == "string" and #why > 0, "LobbyCanopy is not on WorldHealth.ALLOW with a reason")
	assert(W.ALLOW.Canopy == nil, "a bare 'Canopy' exempts every canopy in the world")
end)

return T
