-- popstack.spec.luau: the pops over your cash stack instead of landing on each other (PopStack),
-- 23 Oct 2026. The animation audit (finding 6) and the mockup (ui/animation-review/mp4/4-money-pop.mp4):
-- on an auto-launch the game sends "+$X" and, 0.4 s later, "Auto-launched: half pay" to the SAME spot.
local PS = require("../../src/ReplicatedStorage/PopStack")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

test("one pop sits on the bottom line", function()
	local s = PS.new(2)
	assert(#PS.push(s, "a") == 0, "nothing evicted")
	assert(PS.line(s, "a") == 0, "line 0")
end)

test("a new pop takes the bottom line and pushes the older one up", function()
	local s = PS.new(2)
	PS.push(s, "a")
	PS.push(s, "b")
	assert(PS.line(s, "b") == 0 and PS.line(s, "a") == 1, ("b %s, a %s"):format(tostring(PS.line(s, "b")), tostring(PS.line(s, "a"))))
end)

test("at most two lines: a third pop evicts the oldest", function()
	local s = PS.new(2)
	PS.push(s, "a")
	PS.push(s, "b")
	local out = PS.push(s, "c")
	assert(#out == 1 and out[1] == "a", "a is evicted")
	assert(PS.line(s, "a") == nil and PS.line(s, "b") == 1 and PS.line(s, "c") == 0, "b up, c bottom")
end)

test("a pop that leaves lets the others drop back down", function()
	local s = PS.new(2)
	PS.push(s, "a")
	PS.push(s, "b")
	PS.remove(s, "b")
	assert(PS.line(s, "a") == 0, "a back on the bottom line")
	PS.remove(s, "zzz")   -- removing an unknown id is harmless
	assert(PS.line(s, "a") == 0, "still 0")
end)

return T
