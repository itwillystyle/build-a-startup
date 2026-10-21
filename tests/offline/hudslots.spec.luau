-- hudslots.spec.luau: the bottom-centre HUD, laid out as rectangles, run outside Studio.
-- 20 Oct (Luke's live run, 5:52-5:56 and 7:18): LAUNCH! sat half under the car's speed panel
-- while he drove, so he never saw it and the app auto-launched at half pay. Each script placed
-- its own piece with its own number; nothing checked the pieces against each other.
local H = require("../../src/ReplicatedStorage/HudSlots")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

-- a slot as a rectangle in pixels up from the bottom edge: { bottom, top }
local function span(bottom, height) return { bottom = bottom, top = bottom + height } end
local function gap(a, b)   -- vertical clearance between two spans (negative = they overlap)
	return math.max(a.bottom - b.top, b.bottom - a.top)
end

test("in a car, LAUNCH! sits fully above the speed panel", function()
	local launch = span(H.launchBottom(true, false), H.LAUNCH.height)
	local speedo = span(H.SPEEDO.bottom, H.SPEEDO.height)
	local g = gap(launch, speedo)
	assert(g >= H.GAP, ("LAUNCH! and the speed panel: %d px apart, want >= %d"):format(g, H.GAP))
end)

test("on foot, LAUNCH! clears HOLD TO CODE when both are up", function()
	local launch = span(H.launchBottom(false, true), H.LAUNCH.height)
	local code = span(H.CODE.bottom, H.CODE.height)
	local g = gap(launch, code)
	assert(g >= 8, ("LAUNCH! and HOLD TO CODE: %d px apart"):format(g))
end)

test("on foot with no verb, LAUNCH! takes the bottom slot itself", function()
	assert(H.launchBottom(false, false) == H.CODE.bottom, "LAUNCH! should drop into the empty bottom slot")
end)

test("in a car, LAUNCH! is still on a 375 px-tall phone screen", function()
	local top = H.launchBottom(true, false) + H.LAUNCH.height
	assert(top <= 375 - 120, ("LAUNCH! top at %d px up: the goal card owns the top 120 px of a phone"):format(top))
end)

return T
