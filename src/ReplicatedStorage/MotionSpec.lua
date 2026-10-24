--[[ MotionSpec (23 Oct 2026): the rules every UI tween goes through. Pure.

	The animation audit (improve-animations, 23 Oct) found ~190 tween calls across ~28 files,
	each with hand-typed durations and curves, and nothing that read Roblox's Reduce Motion
	setting. The consensus plan (silicon-startup/ui/animation-review/judge/FINAL.md, signed off by
	a visual judge and an architecture reviewer after three rounds) puts the rules here, and
	UIKit.tween applies them on the client.

	Tokens. Durations and curves from Emil Kowalski's playbook: UI motion stays under 0.3 s
	(emilkowal.ski/ui/7-practical-animation-tips); enter and exit ease OUT; things moving on screen
	ease IN-OUT; the playbook's in-out curve cubic-bezier(0.77, 0, 0.175, 1) is closest to Roblox's
	Quart InOut. A camera the player triggers gets the gentler Cubic InOut (lower peak speed).

	Reduced motion (GuiService.ReducedMotionEnabled; Roblox: "reduced or removed entirely",
	create.roblox.com/docs/production/publishing/accessibility). "Fewer and gentler, not zero":
	  * a fill that MEASURES TIME (opts.kind = "progress": the spin-off hold, the coding bar) is
	    never touched; it is information, not motion
	  * fades and colours (appearance) still play
	  * an EXIT (something fading to fully transparent) drops its drift and fades in place;
	    snapping a rising "+$X" 40 px then fading would be worse than either
	  * a small scale change (|delta| <= SMALL_SCALE: a press, a pop-in from 0.94) is feedback
	    and keeps playing
	  * every other movement lands at once
	  * DEFAULT-DENY: a prop this file does not know is movement
	Tested by tests/offline/motionspec.spec.luau. ]]
local MotionSpec = {}

MotionSpec.T = { press = 0.12, fast = 0.15, ui = 0.2, move = 0.26, max = 0.3 }

-- { EasingStyle name, EasingDirection name }: names, so this module stays pure
MotionSpec.CURVE = {
	OUT = { "Quint", "Out" },
	MOVE = { "Quart", "InOut" },
	CAMERA = { "Cubic", "InOut" },
	LINEAR = { "Linear", "Out" },
}

MotionSpec.SMALL_SCALE = 0.06
-- Roblox stores a UIScale as a 32-bit float: 0.94 reads back as 0.9399999976 (found by the doctor's
-- motion probe, 23 Oct), so the edge needs more slack than a Lua double does
local FLOAT32 = 1e-4

local APPEARANCE = {
	BackgroundTransparency = true, TextTransparency = true, TextStrokeTransparency = true,
	ImageTransparency = true, Transparency = true, GroupTransparency = true,
	ScrollBarImageTransparency = true,
	BackgroundColor3 = true, TextColor3 = true, ImageColor3 = true, TextStrokeColor3 = true, Color = true,
}

function MotionSpec.classify(prop)
	return APPEARANCE[prop] and "appearance" or "movement"
end

-- props: { prop = goal }, current: { prop = value now } (only Scale is read), reduced: bool,
-- opts: { kind = "progress" | nil } -> { tween = {}, instant = {}, drop = {} }
function MotionSpec.plan(props, current, reduced, opts)
	local out = { tween = {}, instant = {}, drop = {} }
	opts = opts or {}
	current = current or {}
	if not reduced or opts.kind == "progress" then
		for k, v in pairs(props) do out.tween[k] = v end
		return out
	end
	local exit = false
	for k, v in pairs(props) do
		if MotionSpec.classify(k) == "appearance" and type(v) == "number" and v >= 1 and string.find(k, "Transparency", 1, true) then
			exit = true
		end
	end
	for k, v in pairs(props) do
		local appearance = MotionSpec.classify(k) == "appearance"
		local feedback = not exit and k == "Scale" and type(v) == "number" and type(current.Scale) == "number"
			and math.abs(v - current.Scale) <= MotionSpec.SMALL_SCALE + FLOAT32
		if appearance or feedback then
			out.tween[k] = v
		elseif exit then
			out.drop[k] = v
		else
			out.instant[k] = v
		end
	end
	return out
end

--[[ 23 Oct: THE CAMERA (phase 2; FINAL.md item 6; docs/superpowers/plans/2026-10-23-motion-phase-2-camera.md).
	Roblox's own guidance stops at UI tweens, but the camera is the strongest motion there is: Xbox
	Accessibility Guideline 117 names camera shake and automatic camera movement as the things to
	drop or make optional. Each camera owner asks this at the moment it acts (per frame, for the
	per-frame owners), so turning Reduce Motion on mid-session lands on the next frame.
	  shake     a multiplier on any camera shake (the chase lunge, the rocket launch)
	  punch     may an event kick the FOV (boost 84, lunge 62)
	  zoom      may the lens ANIMATE back to rest; false = it snaps
	  speedFov  a multiplier on the FOV that widens with speed (the car, the chase)
	  flight    "spline" (Cine flies through its shots) | "cut" (it holds each shot)
	  turn      may tap-to-look turn the camera
	  pinPop    the scale the goal pin pops from (1 + SMALL_SCALE is a pop UIKit.tween still plays) ]]
local CAMERA = {
	[false] = { shake = 1, punch = true, zoom = true, speedFov = 1, flight = "spline", turn = true, pinPop = 1.5 },
	[true] = { shake = 0, punch = false, zoom = false, speedFov = 0, flight = "cut", turn = false, pinPop = 1 + MotionSpec.SMALL_SCALE },
}
function MotionSpec.camera(reduced)
	return table.clone(CAMERA[reduced == true])
end

-- times: cumulative shot times (times[1] = 0), t: seconds into the flight -> the shot a cut holds.
-- The cut lands half way along each leg, so the first and last shots get half a leg each and the
-- whole thing keeps the flight's length (captions and anything timed to the end still line up)
function MotionSpec.cutShot(times, t)
	local n = #times
	if n <= 1 or t >= times[n] then return math.max(n, 1) end
	local seg = 1
	while seg < n - 1 and t > times[seg + 1] do seg += 1 end
	return t < (times[seg] + times[seg + 1]) / 2 and seg or seg + 1
end

-- does a tween with goal `a` share a property with new props `b`? (TweenService cancels the
-- older of two tweens that share a property)
function MotionSpec.overlaps(a, b)
	for k in pairs(b) do
		if a[k] ~= nil then return true end
	end
	return false
end

return MotionSpec
