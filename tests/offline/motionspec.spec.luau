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

-- 23 Oct: phase 2, the camera (docs/superpowers/plans/2026-10-23-motion-phase-2-camera.md)
test("the camera with Reduce Motion OFF is exactly what it was: shake, punches, zooms, spline flights", function()
	local c = MS.camera(false)
	assert(c.shake == 1 and c.punch == true and c.zoom == true and c.speedFov == 1, "effects on")
	assert(c.flight == "spline" and c.turn == true and c.pinPop == 1.5, "flight, turn, pin pop")
end)

test("the camera with Reduce Motion ON: no shake, no punch, no zoom, cuts not flights, no turn", function()
	local c = MS.camera(true)
	assert(c.shake == 0, "no shake")
	assert(c.punch == false, "no FOV punch")
	assert(c.zoom == false, "a lens going back snaps")
	assert(c.speedFov == 0, "no speed zoom")
	assert(c.flight == "cut", "a cutscene cuts between its shots")
	assert(c.turn == false, "tap-to-look does not turn the camera")
end)

test("under Reduce Motion the goal pin still pops, small enough that the layer keeps playing it", function()
	-- found 23 Oct: the pin popped from 1.5, a 0.5 change, which UIKit.tween SNAPS under Reduce
	-- Motion, so "the pin still pops" showed nothing at all
	local from = MS.camera(true).pinPop
	assert(from > 1, "it still pops")
	local f32 = 1.0599999427795410   -- 1.06 as Roblox stores it in a UIScale
	assert(math.abs(from - 1.06) < 1e-9, "1 + SMALL_SCALE")
	local p = MS.plan({ Scale = 1 }, { Scale = f32 }, true)
	assert(keys(p.tween) == "Scale", "the pop plays: " .. keys(p.tween))
end)

test("a cut holds each shot; the cut lands half way along each leg", function()
	-- the 'welcome back' shot list: shot 2 is 2.8 s after shot 1
	local times = { 0, 2.8 }
	assert(MS.cutShot(times, 0) == 1, "starts on shot 1")
	assert(MS.cutShot(times, 1.39) == 1, "shot 1 until half way")
	assert(MS.cutShot(times, 1.41) == 2, "then shot 2")
	assert(MS.cutShot(times, 2.8) == 2, "ends on the last shot")
	assert(MS.cutShot(times, 9) == 2, "past the end holds the last shot")
	local three = { 0, 2, 6 }
	assert(MS.cutShot(three, 0.9) == 1 and MS.cutShot(three, 1.1) == 2, "leg 1 cuts at 1")
	assert(MS.cutShot(three, 3.9) == 2 and MS.cutShot(three, 4.1) == 3, "leg 2 cuts at 4")
end)

test("a cut survives a zero-length leg and a one-shot list", function()
	local times = { 0, 2, 2, 5 }
	for i = 0, 60 do
		local s = MS.cutShot(times, i / 10)
		assert(type(s) == "number" and s >= 1 and s <= 4 and s % 1 == 0, ("t=%.1f -> %s"):format(i / 10, tostring(s)))
	end
	assert(MS.cutShot(times, 5) == 4, "ends on the last shot")
	assert(MS.cutShot({ 0 }, 0) == 1, "one shot")
end)

-- 23 Oct: the chase lens widens with speed and on the crouch tell; under Reduce Motion (s.still) it does not
local C = require("../../src/ReplicatedStorage/ChaseCam")
test("the chase lens: speed and the wind-up widen it, unless the camera is still (Reduce Motion)", function()
	local function lens(fn, extra)
		local s = { shot = "chase", pos = Vector3.new(0, 3, 0), travel = Vector3.new(0, 0, -1), heading = Vector3.new(0, 0, -1),
			side = 1, carrySpeed = 16, mode = "B" }
		for k, v in pairs(extra) do s[k] = v end
		local _, fov = fn(s)
		return fov
	end
	for _, fn in { C.solve, C.solveLocked } do
		local rest, fast = lens(fn, { speed = 0 }), lens(fn, { speed = 16 })
		assert(fast > rest + 1, ("speed widens the lens today: %.2f -> %.2f"):format(rest, fast))
		assert(math.abs(lens(fn, { speed = 16, still = true }) - lens(fn, { speed = 0, still = true })) < 1e-9, "still: speed adds nothing")
		assert(math.abs(lens(fn, { speed = 0, still = true }) - rest) < 1e-9, "still: the shot's own lens is kept")
	end
	local wound = lens(C.solve, { speed = 0, windup = true })
	assert(wound > lens(C.solve, { speed = 0 }) + 1, "the crouch tell widens it today")
	assert(math.abs(lens(C.solve, { speed = 0, windup = true, still = true }) - lens(C.solve, { speed = 0 })) < 1e-9, "still: no wind-up zoom")
end)

return T
