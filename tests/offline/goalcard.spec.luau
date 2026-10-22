-- goalcard.spec.luau: when the goal card is full and when it is a pill (GoalCard), 22 Oct 2026.
-- Luke, 22 Oct: "I'm also manually pressing the X, which is kind of annoying." Option A (his pick):
-- a new goal shows full for 4 s, then shrinks to a slim pill; tapping the pill opens it again.
local GC = require("../../src/ReplicatedStorage/GoalCard")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

test("a brand-new goal is full for 4 s once it shows, then a pill", function()
	local s = GC.new()
	GC.goal(s, "code", 100)
	GC.shown(s, 100)
	assert(GC.full(s, 100) == true, "full the moment it shows")
	assert(GC.full(s, 103.9) == true, "still full at 3.9 s")
	assert(GC.full(s, 104.1) == false, "a pill after 4 s")
end)

test("a goal seen again within 90 s stays a pill (the client loop: code, deliver, give every few seconds)", function()
	local s = GC.new()
	GC.goal(s, "give", 100); GC.shown(s, 100)
	GC.goal(s, "code", 110); GC.shown(s, 110)
	GC.goal(s, "give", 120); GC.shown(s, 120)
	assert(GC.full(s, 120) == false, "give came back 20 s later: pill")
	GC.goal(s, "give", 200); GC.shown(s, 200)
	assert(GC.full(s, 200) == false, "seen at 120, back at 200 (80 s): pill")
end)

test("a goal back after more than 90 s away gets its full look again", function()
	local s = GC.new()
	GC.goal(s, "hire", 100); GC.shown(s, 100)
	GC.goal(s, "serve", 105); GC.shown(s, 105)
	GC.goal(s, "hire", 196); GC.shown(s, 196)
	assert(GC.full(s, 196) == true, "hire was last seen at 100: full again")
end)

test("a tap opens the pill for 4 s from the tap", function()
	local s = GC.new()
	GC.goal(s, "upgrade", 0); GC.shown(s, 0)
	assert(GC.full(s, 10) == false, "a pill by 10 s")
	GC.tap(s, 10)
	assert(GC.full(s, 13.9) == true, "open after the tap")
	assert(GC.full(s, 14.1) == false, "a pill again 4 s after the tap")
end)

test("a goal that arrived while the card was hidden gets its 4 s when it shows, not before", function()
	local s = GC.new()
	GC.goal(s, "recruit", 100)   -- a level-up card held the screen
	assert(GC.full(s, 100) == false, "nothing is full until the card shows")
	GC.shown(s, 107)
	assert(GC.full(s, 110) == true, "its 4 s start at 107")
	assert(GC.full(s, 111.1) == false, "and end at 111")
end)

test("showing again with nothing new does not restart the 4 s", function()
	local s = GC.new()
	GC.goal(s, "code", 100); GC.shown(s, 100)
	GC.shown(s, 103)
	assert(GC.full(s, 104.5) == false, "a second render at 103 is not a new goal")
end)

test("no goal (nil key) never opens the card", function()
	local s = GC.new()
	GC.goal(s, nil, 100); GC.shown(s, 100)
	assert(GC.full(s, 100) == false, "nil key")
end)

return T
