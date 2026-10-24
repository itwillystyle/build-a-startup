--[[ LabelLook (24 Oct 2026, look pass L3): the rules for the labels that float in the world.

	The visual judge (ui/animation-review/judge/FINAL.md, L3) found three things wrong against
	Luke's picked mock (ui/art-pass/garage-outside.png). Each one is a rule here, in pure code,
	so tests/offline/labellook.spec.luau holds it:

	1. A client's speech bubble sat on a staff member's nameplate (shots/after-C1.jpg).
	   `claim` is the screen-space rule: the bubble claims its rectangle first and never fades;
	   a name tag that would touch it (GAP_PX) fades, as tags already fade for each other.
	   `stackClear` is the stud rule for one rig wearing two labels: pixel-sized billboards
	   stacked a few studs apart only clear each other close up.
	2. Night nameplates were hard to read (shots/final-C1-night.jpg). `reads` is the contrast
	   rule in OKLab lightness; `plateText` lifts a role or talent colour until it passes.
	3. The "#1 NEON GAMES" board was out of scale (shots/final-C2-day.jpg). `garageBoard` sizes
	   it off the garage door with the mock's proportions while the plot is still the garage.

	Pure: no game services, only Color3 / math. ]]
local LL = {}

-- ------------------------------------------------------------------ 1. bubble vs nameplate

-- 24 Oct: pixels kept clear between a client's bubble and any name tag (the bubble is a solid card)
LL.GAP_PX = 6
-- tags may overlap each other this many pixels in y before one fades (StaffAnimClient v3.6, kept)
LL.TAG_SLACK_PX = 6

--[[ 24 Oct: which labels fade. Each entry is a screen rectangle { x, y (centre), w, h, pri,
	solid }. Solid entries (client bubbles) claim first and are never faded; the rest claim
	in pri order (highest first) and fade if they touch anything already placed. Returns a
	table entry -> true for every entry that should fade. ]]
function LL.claim(list)
	local order = table.clone(list)
	table.sort(order, function(a, b)
		if (a.solid and true or false) ~= (b.solid and true or false) then return a.solid == true end
		return (a.pri or 0) > (b.pri or 0)
	end)
	local placed, faded = {}, {}
	for _, e in ipairs(order) do
		local clash = false
		if not e.solid then
			for _, q in ipairs(placed) do
				local gapX = q.solid and LL.GAP_PX or 0
				local slackY = q.solid and -LL.GAP_PX or LL.TAG_SLACK_PX
				if math.abs(e.x - q.x) < (e.w + q.w) / 2 + gapX and math.abs(e.y - q.y) < (e.h + q.h) / 2 - slackY then
					clash = true
					break
				end
			end
		end
		if clash then faded[e] = true else table.insert(placed, e) end
	end
	return faded
end

-- pixels one stud spans at `dist` studs (a billboard sized in pixels keeps its pixels; studs shrink)
function LL.pxPerStud(dist, viewportH, fovDeg)
	return viewportH / (2 * dist * math.tan(math.rad(fovDeg) / 2))
end

--[[ 24 Oct: two pixel-sized billboards on ONE head, the upper at `upper.offset` studs with a
	box `upper.px` tall, the lower at `lower.offset` / `lower.px`. They clear each other at
	`dist` only if the studs between them span the two half-heights plus GAP_PX. ]]
function LL.stackClear(upper, lower, dist, viewportH, fovDeg)
	local sep = (upper.offset - lower.offset) * LL.pxPerStud(dist, viewportH or 720, fovDeg or 70)
	return sep >= (upper.px + lower.px) / 2 + LL.GAP_PX, sep
end

-- ------------------------------------------------------------------ 2. night nameplates

local function toLinear(c) return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4 end
local function toSrgb(c) return c <= 0.0031308 and 12.92 * c or 1.055 * c ^ (1 / 2.4) - 0.055 end
local function cbrt(x) return x < 0 and -((-x) ^ (1 / 3)) or x ^ (1 / 3) end

-- OKLab (Ottosson 2020): L is perceived lightness 0..1
function LL.oklab(c)
	local r, g, b = toLinear(c.R), toLinear(c.G), toLinear(c.B)
	local l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
	local m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
	local s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
	return 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
end

-- back to sRGB 0..1, unclamped (so a caller can tell when it left the gamut)
local function fromOklab(L, a, b)
	local l = (L + 0.3963377774 * a + 0.2158037573 * b) ^ 3
	local m = (L - 0.1055613458 * a - 0.0638541728 * b) ^ 3
	local s = (L - 0.0894841775 * a - 1.2914855480 * b) ^ 3
	return 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
		-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
		-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
end

--[[ 24 Oct, measured off the art-pass shots with Pillow (8th-brightest pixel of each label's fill):
	a white label renders (235, 217, 195) by day (after-C1.jpg, "Ada") and (174, 171, 190) at
	night (final-C1-night.jpg). The bubble's paper card shifts by the same ratio (0.73, 0.79,
	1.01), so the night look is the SkyClient grade (TintColor 196,206,255), not the lights. ]]
LL.DAY_WHITE = Color3.fromRGB(235, 217, 195)
LL.NIGHT_WHITE = Color3.fromRGB(174, 171, 190)
-- what sits behind a nameplate, measured in the same shots
LL.BACKDROPS = {
	nightStreet = Color3.fromRGB(5, 6, 2),       -- behind "Lead Researcher" at night (the dark street)
	nightWall = Color3.fromRGB(177, 158, 137),   -- the cream wall at night
	dayWall = Color3.fromRGB(247, 223, 177),     -- the cream wall by day
	dayLawn = Color3.fromRGB(127, 138, 68),      -- the lawn behind "Lead Researcher" by day
}
--[[ 24 Oct: the two thresholds, set by the night shot. "Ada" (white, stroke 0.25) reads there:
	letter against outline 0.68. "Lead Researcher" (180,140,255, stroke 0.4) does not: 0.47.
	plateText colours in the opaque outline score 0.66 at night, 0.78 by day. ]]
LL.EDGE_MIN = 0.6     -- OKLab L between a letter and its own outline
LL.GROUND_MIN = 0.3   -- OKLab L between the label (letter or outline) and what is behind it
LL.TEXT_L = 0.88      -- plateText lifts a colour to this lightness

-- the nameplate's look (StaffRig.nameTag): a light letter in an opaque dark outline, the HUD's sticker
LL.PLATE = { stroke = Color3.new(0, 0, 0), strokeT = 0, nameSize = 16, subSize = 14 }

local function mul(a, b) return Color3.new(a.R * b.R, a.G * b.G, a.B * b.B) end
local function mix(a, b, t) return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t) end

-- a label colour as it lands on screen: "day" or "night" (the measured white scaled by the colour)
function LL.seen(c, when)
	return mul(c, when == "night" and LL.NIGHT_WHITE or LL.DAY_WHITE)
end

--[[ 24 Oct: does a label read? `fill` letter colour, `stroke` / `strokeT` its TextStroke, `back`
	what is behind it (already on screen), `when` day|night. A part-transparent outline is
	partly the backdrop. Returns ok, edge, ground. ]]
function LL.reads(fill, stroke, strokeT, back, when)
	local f = LL.seen(fill, when)
	local s = mix(LL.seen(stroke, when), back, strokeT)
	local lf, ls, lb = LL.oklab(f), LL.oklab(s), LL.oklab(back)
	local edge = math.abs(lf - ls)
	local ground = math.max(math.abs(lf - lb), math.abs(ls - lb))
	return edge >= LL.EDGE_MIN and ground >= LL.GROUND_MIN, edge, ground
end

--[[ 24 Oct: a role or talent colour made into nameplate text: the same hue, lifted in OKLab to
	TEXT_L, its chroma cut only as far as sRGB needs. Lighter colours are left alone. ]]
function LL.plateText(c)
	local L, a, b = LL.oklab(c)
	if L >= LL.TEXT_L then return c end
	local function fits(k)
		local r, g, bl = fromOklab(LL.TEXT_L, a * k, b * k)
		return r >= -1e-4 and r <= 1 + 1e-4 and g >= -1e-4 and g <= 1 + 1e-4 and bl >= -1e-4 and bl <= 1 + 1e-4
	end
	local lo, hi = 0, 1
	if fits(1) then lo = 1 else
		for _ = 1, 24 do
			local mid = (lo + hi) / 2
			if fits(mid) then lo = mid else hi = mid end
		end
	end
	local r, g, bl = fromOklab(LL.TEXT_L, a * lo, b * lo)
	local function clamp(x) return math.clamp(toSrgb(math.clamp(x, 0, 1)), 0, 1) end
	return Color3.new(clamp(r), clamp(g), clamp(bl))
end

-- ------------------------------------------------------------------ 3. the board over the garage

--[[ 24 Oct, measured off garage-outside.png with Pillow (tools: PIL, max(r,g,b) < 75 = the sign):
	the dark sign over the door runs x 651..1155 on row 170 (505 px), 76 px tall at its centre
	column; the opening between the front posts' inner edges is x 478..1219 on rows 300-450
	(741 px). Sign / door = 0.68 across, 0.10 tall. The live board (final-C2-day.jpg) was 397 px
	over a 332 px opening: 1.20 across, 0.38 tall. ]]
LL.MOCK_SIGN_OF_DOOR = 505 / 741
LL.BOARD_ASPECT = 58 / 19    -- the founder board's own shape: two rows of text (the mock's sign is blank)
LL.GARAGE = {
	door = 35,       -- the opening: CoreConfig HQ_LEVELS[1].w 36 less the walls; GarageLayout HALF_X * 2
	roofTop = 18.05, -- HQMeta/V1 HQ_1_Shell: c.Y 9.026 + s.Y / 2
	front = 18,      -- HQMeta/V1 HQ_1_Shell: the shell's front face, s.Z / 2
	gap = 1,         -- studs between the roof and the board
}

-- the plot is still the garage (Valley publishes the tower level; 1 = nothing built on it yet)
function LL.isGarage(level) return (tonumber(level) or 1) <= 1 end

--[[ 24 Oct: the founder board while the plot is the garage, in the plot's frame: w x h studs,
	centred at (0, y, z). As wide across the door as the mock's sign; the board's own aspect,
	so both rows still read; sitting just over the roof at the front, not floating over the
	middle of the plot. ]]
function LL.garageBoard()
	local G = LL.GARAGE
	local w = G.door * LL.MOCK_SIGN_OF_DOOR
	local h = w / LL.BOARD_ASPECT
	return { w = w, h = h, y = G.roofTop + G.gap + h / 2, z = G.front }
end

return LL
