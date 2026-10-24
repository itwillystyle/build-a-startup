-- transparency.spec.luau: Roblox's Background Transparency setting (TransparencySpec), 24 Oct 2026.
-- GuiService.PreferredTransparency is 1 by default and 0 when the player wants solid backgrounds.
-- Roblox: "Multiplying a UI element's BackgroundTransparency with PreferredTransparency is the
-- recommended way to use this setting" (create.roblox.com/docs/production/publishing/accessibility).
local TS = require("../../src/ReplicatedStorage/TransparencySpec")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local function near(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < 1e-9 end

test("the rule is Roblox's: designed times preferred", function()
	assert(near(TS.bg(0.3, 1), 0.3), "default setting: the design as drawn")
	assert(near(TS.bg(0.3, 0), 0), "setting at 0: fully solid")
	assert(near(TS.bg(0.3, 0.5), 0.15), "half way: half as see-through")
	assert(near(TS.bg(0.05, 0.2), 0.01), "0.05 * 0.2")
end)

test("a solid background stays solid and a missing one stays missing", function()
	assert(TS.bg(0, 0.5) == 0, "solid stays solid")
	-- 1 * 0.5 would draw a background on a frame that never had one (a layout box, a label)
	assert(TS.bg(1, 0.5) == 1 and TS.bg(1, 0) == 1, "no background stays no background")
end)

test("a bad or missing setting means the default (1), and it is kept inside 0..1", function()
	assert(near(TS.bg(0.4, nil), 0.4), "nil -> 1")
	assert(near(TS.bg(0.4, "x"), 0.4), "not a number -> 1")
	assert(near(TS.bg(0.4, 2), 0.4), "above 1 -> 1")
	assert(TS.bg(0.4, -1) == 0, "below 0 -> 0")
end)

test("only see-through surfaces follow the setting", function()
	assert(TS.follows(0.3) and TS.follows(0.05) and TS.follows(0.95), "0 < t < 1 follows")
	assert(not TS.follows(0), "solid: nothing to do")
	assert(not TS.follows(1), "invisible container: never")
	assert(not TS.follows(nil) and not TS.follows("0.3"), "not a number")
end)

test("the test attribute beats the real setting; without it the setting is used", function()
	assert(TS.resolve(1, 0) == 0, "ForcePreferredTransparency = 0 wins over the setting")
	assert(TS.resolve(0.2, nil) == 0.2, "no attribute: the setting")
	assert(TS.resolve(nil, nil) == 1, "nothing read: the default")
	assert(TS.resolve(0.2, 5) == 1 and TS.resolve(0.2, -3) == 0, "a forced value is clamped")
	assert(TS.resolve(0.2, "zero") == 0.2, "a non-number attribute is ignored")
end)

test("a live change moves a surface that is showing its designed value", function()
	-- at rest under setting 1 the frame shows 0.3; the player turns the setting to 0
	assert(TS.reapply(0.3, 0.3, 1, 0) == 0, "0.3 -> 0")
	-- and back
	assert(near(TS.reapply(0, 0.3, 0, 1), 0.3), "0 -> 0.3")
	-- Roblox stores BackgroundTransparency as a 32-bit float: 0.15 reads back as 0.1500000059604645
	assert(near(TS.reapply(0.1500000059604645, 0.3, 0.5, 1), 0.3), "float32 read-back still counts as at rest")
end)

test("a live change leaves a surface alone while something else is fading it", function()
	-- mid fade-out (0.7) or hidden (1): putting it back to 0 would pop it on screen
	assert(TS.reapply(0.7, 0.3, 1, 0) == nil, "mid fade: left alone")
	assert(TS.reapply(1, 0.3, 1, 0) == nil, "faded out: left alone")
end)

return T
