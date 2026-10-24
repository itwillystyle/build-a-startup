-- coachplace.spec.luau: where a coach tip's card goes (CoachPlace, pure), run outside Studio.
-- 24 Oct (F-6): the doctor's FEEL "cards over cards" at HQ 18/43/100 on a 1074 x 376 screen:
-- Coach.CoachCard over Quest.Holder.Quest (2,574 px2). The card is placed beside a rail tile under
-- the top bar, which on a short screen is the goal pill's row. The card now keeps clear of the
-- goal card, judged by the doctor's rule (DoctorProbes.ui: an overlap is > 6 px both ways).
local P = require("../../src/ReplicatedStorage/CoachPlace")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local VP = { X = 1074, Y = 376 }
local W, H = 290, 140
local PILL = { x = 387, y = 64, w = 300, h = 44 }   -- the goal pill, top centre (words showing)
local ICON = { x = 515, y = 64, w = 44, h = 44 }    -- folded to its icon under a tip

local function card(x, y) return { x = x, y = y, w = W, h = H } end

test("the doctor's overlap rule: more than 6 px both ways", function()
	assert(P.overlaps({ x = 0, y = 0, w = 10, h = 10 }, { x = 3, y = 3, w = 10, h = 10 }), "7 x 7 overlaps")
	assert(not P.overlaps({ x = 0, y = 0, w = 10, h = 10 }, { x = 4, y = 0, w = 10, h = 10 }), "6 px across is a touch")
	assert(not P.overlaps({ x = 0, y = 0, w = 10, h = 10 }, { x = 20, y = 0, w = 10, h = 10 }), "apart")
end)

test("a tip by a top rail tile on a short screen keeps off the goal pill and its icon", function()
	for _, goal in ipairs({ PILL, ICON }) do
		for _, ty in ipairs({ 64, 90, 120 }) do
			local side, x, y = P.place({ X = 12, Y = ty }, { X = 64, Y = 64 }, VP, W, H, { railRight = 90, avoid = { goal } })
			assert(not P.overlaps(card(x, y), goal),
				("card at %d,%d (%s) sits on the goal %d,%d %dx%d"):format(x, y, side, goal.x, goal.y, goal.w, goal.h))
			assert(x >= 8 and y >= 64 and x + W <= VP.X - 8 and y + H <= VP.Y - 8, "the card stays on screen")
			assert(x >= 90, "the card stays clear of the rail")
		end
	end
end)

test("nothing to avoid: the card sits beside the tile as before", function()
	local side, x, y = P.place({ X = 12, Y = 64 }, { X = 64, Y = 64 }, VP, W, H, { railRight = 90 })
	assert(side == "right" and x == 120 and y == 64, ("%s %d,%d"):format(side, x, y))
end)

return T
