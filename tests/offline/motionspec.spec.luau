-- motionspec.spec.luau: the motion layer's rules (MotionSpec), 23 Oct 2026.
-- The consensus plan (silicon-startup/ui/animation-review/judge/FINAL.md, signed off by a visual
-- judge and an architecture reviewer): one layer every UI tween goes through, which also honours
-- Roblox's Reduce Motion setting (GuiService.ReducedMotionEnabled).
local MS = require("../../src/ReplicatedStorage/MotionSpec")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local function keys(t)
	local out = {}
	for k in pairs(t) do table.insert(out, k) end
	table.sort(out)
	return table.concat(out, ",")
end

test("the durations are the playbook's: everything a UI does is 0.3 s or less", function()
	for name, v in pairs(MS.T) do
		assert(type(v) == "number" and v > 0 and v <= 0.3, ("T.%s = %s"):format(name, tostring(v)))
	end
	assert(MS.T.press <= MS.T.fast and MS.T.fast <= MS.T.ui and MS.T.ui <= MS.T.move and MS.T.move <= MS.T.max, "ordered")
end)

test("the curves: out for enter/exit, Quart in-out for moves, Cubic in-out for the camera", function()
	assert(MS.CURVE.OUT[1] == "Quint" and MS.CURVE.OUT[2] == "Out", "OUT")
	assert(MS.CURVE.MOVE[1] == "Quart" and MS.CURVE.MOVE[2] == "InOut", "MOVE: AUDIT 2's cubic-bezier(0.77,0,0.175,1)")
	assert(MS.CURVE.CAMERA[1] == "Cubic" and MS.CURVE.CAMERA[2] == "InOut", "CAMERA")
	assert(MS.CURVE.LINEAR[1] == "Linear", "LINEAR")
end)

test("fades and colours are appearance; anything else, even an unknown prop, is movement", function()
	for _, p in { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency", "ImageTransparency",
		"Transparency", "GroupTransparency", "BackgroundColor3", "TextColor3", "ImageColor3", "Color" } do
		assert(MS.classify(p) == "appearance", p .. " is appearance")
	end
	for _, p in { "Position", "Size", "Rotation", "Scale", "StudsOffset", "CFrame", "FieldOfView", "SomethingNew" } do
		assert(MS.classify(p) == "movement", p .. " is movement (default-deny)")
	end
end)

test("motion on: every prop tweens as written", function()
	local p = MS.plan({ Position = 1, TextTransparency = 0, Scale = 1 }, { Scale = 0.4 }, false)
	assert(keys(p.tween) == "Position,Scale,TextTransparency", "tween: " .. keys(p.tween))
	assert(next(p.instant) == nil and next(p.drop) == nil, "nothing instant or dropped")
end)

test("reduced: fades still play, movement lands at once", function()
	local p = MS.plan({ Position = 1, Size = 2, BackgroundTransparency = 0 }, {}, true)
	assert(keys(p.tween) == "BackgroundTransparency", "tween: " .. keys(p.tween))
	assert(keys(p.instant) == "Position,Size", "instant: " .. keys(p.instant))
end)

test("reduced: a hold bar that measures time is never touched (the spin-off confirm, the coding bar)", function()
	local p = MS.plan({ Size = 1 }, {}, true, { kind = "progress" })
	assert(keys(p.tween) == "Size" and next(p.instant) == nil, "progress keeps its tween")
end)

test("reduced: an exit (a fade to fully transparent) stays put instead of jumping, then fades", function()
	local p = MS.plan({ Position = 1, TextTransparency = 1 }, {}, true)
	assert(keys(p.tween) == "TextTransparency", "the fade plays")
	assert(keys(p.drop) == "Position", "the drift is dropped, not snapped: " .. keys(p.drop))
	assert(next(p.instant) == nil, "nothing jumps")
end)

test("reduced: a small scale change is feedback and keeps playing; a big one lands at once", function()
	local small = MS.plan({ Scale = 1 }, { Scale = 0.94 }, true)
	assert(keys(small.tween) == "Scale", "0.94 -> 1 is a press/pop: keeps its tween")
	local big = MS.plan({ Scale = 1 }, { Scale = 0.4 }, true)
	assert(keys(big.instant) == "Scale", "0.4 -> 1 is movement: instant")
	local unknown = MS.plan({ Scale = 1 }, {}, true)
	assert(keys(unknown.instant) == "Scale", "no current value: default-deny, instant")
end)

test("a press from 0.94 counts as small even after Roblox stores it as a 32-bit float (live, 23 Oct)", function()
	-- the doctor's motion probe: UIScale.Scale = 0.94 reads back as 0.9399999976158142, so
	-- 1 - Scale was 0.0600000024 and the press snapped under Reduce Motion
	local p = MS.plan({ Scale = 1 }, { Scale = 0.9399999976158142 }, true)
	assert(keys(p.tween) == "Scale", "0.94 (float32) -> 1 still plays: " .. keys(p.tween) .. " / instant " .. keys(p.instant))
end)

test("overlap: a new tween replaces an old one only when they share a property", function()
	assert(MS.overlaps({ Size = 1, BackgroundTransparency = 0 }, { Size = 2 }) == true, "Size shared")
	assert(MS.overlaps({ Position = 1 }, { TextTransparency = 1 }) == false, "different props run side by side")
	assert(MS.overlaps({}, { Size = 1 }) == false, "empty")
end)

return T
