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

return T
