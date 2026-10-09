--[[
	Palette -- one world, one set of colours. (S2-S4 of art/STYLE-SPEC.md)

	WHY. Five asset sources each arrived with their own colour decisions and
	nothing ever mapped them onto one world. That is the whole of the "assets
	dropped in" feeling: not quality, not low-poly, just five hands.

	SVStyle measured it on 6 Oct: 191 authored colours against a 9-colour
	bible, 719 parts still at Roblox default grey, 418 imported meshes
	rendering in the pack's own colours.

	WHAT MAP DOES. It is a MINIMAL correction, not a repaint. A colour keeps
	its lightness -- which is what carries the world's value structure -- and
	only its hue and saturation are pulled onto the nearest anchor family. A
	pale thing stays pale, a dark thing stays dark, and both start agreeing
	with everything around them.

	WHY LIGHTNESS IS FREE. Nine flat swatches cannot build a world, which is
	why the palette was quietly abandoned the first time. Anchors are hue
	FAMILIES: Oak is not one brown, it is every brown on that hue.

	WHERE IT RUNS. Builders call map() so new work is authored correctly.
	enforce() then sweeps the built world, because cloned packs -- cars,
	furniture, imported meshes -- never pass through any helper we own, and
	they are the largest single source of the problem.
]]

local Palette = {}

local CS = game:GetService("CollectionService")

--[[ The nine from ART.md, plus two that S1 proved the world needs. Both
	additions are judgement calls and both are recorded in STYLE-SPEC.md:

	  Foliage  CampusLawn is hue 0.270 and every tree canopy in the game sits
	           near 0.36. A mown lawn and a tree canopy are not the same green
	           in any real palette, and forcing them together would have made
	           the valley one flat sheet of colour.
	  Asphalt  Ink is one very specific dark blue-grey at saturation 0.375.
	           Roads and kerbs share its hue but are far less saturated, so
	           they failed on saturation alone against the only dark we had.
]]
Palette.ANCHORS = {
	{ name = "PaperWhite", rgb = { 243, 239, 230 } },
	{ name = "WarmConcrete", rgb = { 207, 198, 182 } },
	{ name = "Oak", rgb = { 192, 138, 85 } },
	{ name = "TintedGlass", rgb = { 118, 158, 176 } },
	{ name = "CampusLawn", rgb = { 118, 160, 92 }, vmax = 0.66 },
	{ name = "Foliage", rgb = { 74, 150, 84 }, vmax = 0.64 },
	{ name = "CaliforniaGold", rgb = { 224, 182, 90 }, vmax = 0.88 },
	{ name = "ValleyBlue", rgb = { 62, 110, 158 } },
	{ name = "Asphalt", rgb = { 56, 58, 66 } },
	{ name = "Ink", rgb = { 30, 37, 48 } },
	{ name = "BrandGold", rgb = { 255, 194, 61 } },
}

Palette.HUE_TOL = 0.02
Palette.SAT_TOL = 0.08
Palette.NEUTRAL_MIN = 0.02
Palette.TINT_NEUTRAL = 0.80     -- above this a MeshPart's Color is a tint, not a colour
Palette.VALUE_FLOOR = 0.10      -- no pure black
Palette.VALUE_CEIL = 0.97       -- no pure white

--[[ A VALUE CEILING ON THE COLOURS THAT COVER THE MOST GROUND.

	Freeing lightness is what makes nine anchors able to carry a world, but it
	cut both ways: the lawn and the canopy came out hue-correct and far too
	bright, so the least important object in the frame was still the loudest
	thing in it. ART.md already says this -- "the world is mid-saturation",
	full strength reserved for the company accent, brand gold and rewards.

	So the three big-area families get a ceiling and nothing else does. The
	buildings keep their full range. ]]

--[[ Meshes our own Blender pipeline made. svkit.py guarantees these prefixes,
	so this reads a contract rather than guessing at a name. They arrive already
	painted in the palette as vertex colour and must not be touched. ]]
Palette.OWN_PREFIX = { "LP_", "W_", "D_", "T_", "HQ", "SV" }

--[[ THE PACK WASH. An imported mesh carries its own colours in a texture or in
	vertex colour, and Luau cannot read either -- so they cannot be mapped onto
	an anchor the way a Part's Color can.

	What CAN be done is multiply them. A MeshPart's Color multiplies the asset,
	so one shared warm wash over every imported pack pulls five kits toward a
	single tone without flattening any of them to one hue. That is the classic
	unifier and it is the closest thing to "re-tinted on entry" that an opaque
	asset allows.

	Deliberately gentle: a light warm concrete, so it reads as one light falling
	on everything rather than as paint. ]]
Palette.PACK_WASH = Color3.fromRGB(240, 229, 211)

--[[ Reviewed 6 Oct: every Neon part in the game, checked by eye, and these are
	lights, screens, lit glass or effects -- which is what ART.md allows Neon
	for. It is an allowlist rather than a name heuristic: a NEW Neon part will
	not be on it, so it shows up in the count instead of quietly passing. ]]
Palette.EMISSIVE_OK = {
	Clerestory = true, RackLight = true, LiftCallLit = true, Bulb = true,
	Glow = true, Screen = true, StationGlow = true, ChargerLight = true,
	ToolLamp = true, ConsoleScreen = true, ScopeGlow = true, TierRing = true,
	TierPillar = true, Halo = true, MonumentCap = true, RoofBeacon = true,
	SignBand = true, PadGlow = true, Beacon = true, Lamp = true, LampHead = true,
}

function Palette.isOurs(name)
	for _, pre in ipairs(Palette.OWN_PREFIX) do
		if name:sub(1, #pre) == pre then return true end
	end
	return false
end

local hsv
local function anchors()
	if not hsv then
		hsv = {}
		for _, a in ipairs(Palette.ANCHORS) do
			local c = Color3.fromRGB(a.rgb[1], a.rgb[2], a.rgb[3])
			local h, s, v = c:ToHSV()
			table.insert(hsv, { name = a.name, h = h, s = s, v = v, vmax = a.vmax })
		end
	end
	return hsv
end

--[[ BasePart.Color QUANTISES TO 8 BITS on assignment, but Color3 equality is
	float-exact. So map() kept returning a value that renders identically and
	compares unequal, and enforce rewrote the same 148 parts on every pass
	forever -- 150, 148, 148 - while the off-palette count sat still.

	Nothing was wrong with the world. The comparison was wrong. Everything that
	decides whether to WRITE a colour has to ask the question in the space the
	colour is actually stored in. ]]
local function same8(a, b)
	return math.floor(a.R * 255 + 0.5) == math.floor(b.R * 255 + 0.5)
		and math.floor(a.G * 255 + 0.5) == math.floor(b.G * 255 + 0.5)
		and math.floor(a.B * 255 + 0.5) == math.floor(b.B * 255 + 0.5)
end
Palette.same8 = same8

local function hueGap(a, b)
	local d = math.abs(a - b)
	return d > 0.5 and (1 - d) or d
end

--[[ Compliant if ANY anchor accepts it. Testing only the nearest-by-hue
	anchor is wrong here: PaperWhite, WarmConcrete, CaliforniaGold and
	BrandGold all sit within 0.01 of hue 0.11 and differ only in saturation,
	so a warm off-white gets assigned to BrandGold and fails for being 0.68
	less saturated, while PaperWhite would have taken it. ]]
--[[ HUE TOLERANCE WIDENS AS COLOUR DRAINS OUT, for two reasons that agree.

	The measured one: Color3 stores 8-bit RGB, and at low saturation the whole
	hue circle is encoded in a handful of levels. Mapping a near-neutral to
	hue 0.1067 and reading it back gives something quite different, so map()
	was not a fixed point -- enforce rewrote the same 150 parts on every pass
	and they never became compliant. A rule that cannot be satisfied is worse
	than no rule.

	The perceptual one: nobody can see the hue of a 5%-saturated grey. What
	matters down there is only that it is WARM rather than dead neutral, which
	is the saturation test, and that survives untouched.

	So: full strictness above saturation 0.3, relaxing to 0.10 at zero. ]]
local function hueTolFor(s)
	local k = math.clamp(s / 0.3, 0, 1)
	return Palette.HUE_TOL + (1 - k) * 0.08
end

function Palette.compliant(c)
	local h, s = c:ToHSV()
	if s < Palette.NEUTRAL_MIN then return false end
	local tol = hueTolFor(s)
	for _, a in ipairs(anchors()) do
		if hueGap(h, a.h) <= tol and math.abs(s - a.s) <= Palette.SAT_TOL then
			return true, a.name
		end
	end
	return false
end

--[[ A flat grey has no hue to preserve, so it is assigned by LIGHTNESS -- the
	one piece of information it does carry. This is what turns 719 parts of
	Roblox default grey into warm concrete without anyone repainting them. ]]
local function neutralAnchor(v)
	local want = (v < 0.22 and "Ink") or (v < 0.45 and "Asphalt")
		or (v < 0.80 and "WarmConcrete") or "PaperWhite"
	for _, a in ipairs(anchors()) do
		if a.name == want then return a end
	end
	return anchors()[1]
end

--[[ The minimal correction. Hue moves onto the anchor; saturation is CLAMPED
	into the anchor's band rather than replaced, so a pale lawn stays pale
	instead of snapping to full strength; lightness is untouched except at the
	two extremes, because lightness is the value structure and overwriting it
	would flatten the world to fix its colour. ]]
function Palette.map(c)
	if typeof(c) ~= "Color3" then return c end
	local h, s, v = c:ToHSV()
	-- clear the floor and ceiling by a margin: landing exactly on them needs a
	-- correction finer than one 8-bit step, so the stored value bounces back
	if v < Palette.VALUE_FLOOR then v = Palette.VALUE_FLOOR + 0.02 end
	if v > Palette.VALUE_CEIL then v = Palette.VALUE_CEIL - 0.01 end

	if s < Palette.NEUTRAL_MIN then
		local a = neutralAnchor(v)
		return Color3.fromHSV(a.h, a.s, v)
	end

	local ok, name = Palette.compliant(c)
	if ok then
		for _, a in ipairs(anchors()) do
			if a.name == name and a.vmax then v = math.min(v, a.vmax) end
		end
		local out = Color3.fromHSV(h, s, v)
		return same8(out, c) and c or out
	end

	local best, bestGap = nil, math.huge
	for _, a in ipairs(anchors()) do
		local g = hueGap(h, a.h)
		if g < bestGap then best, bestGap = a, g end
	end
	if not best then return c end
	--[[ Snap INSIDE the band, not onto its edge. A colour sitting 0.0017 past
		the limit needs a correction smaller than one 8-bit colour step, so the
		stored result quantises straight back to where it started and the part
		is non-compliant forever. Landing at 85% of the tolerance puts the
		result comfortably inside the band after quantisation. ]]
	local margin = Palette.SAT_TOL * 0.85
	local s2 = math.clamp(s, math.max(0, best.s - margin), best.s + margin)
	if best.vmax then v = math.min(v, best.vmax) end
	return Color3.fromHSV(best.h, s2, v)
end

--[[ Who is exempt, and why each one.

	People        staff are real Roblox avatars by design; skin, hair and
	              clothing are not palette colours.
	Tint meshes   a MeshPart's Color near white is a MULTIPLIER over the
	              asset's own vertex colours, not a colour. Repainting it
	              would tint the whole mesh a flat hue and destroy the art
	              it is multiplying.
	SVNoPalette   a deliberate, tagged exemption, so an exception has to be
	              stated by the builder rather than guessed from a name.
]]
function Palette.exempt(d)
	if not d:IsA("BasePart") then return true end
	if CS:HasTag(d, "SVNoPalette") then return true end
	if CS:HasTag(d, "SVStaff") then return true end
	local m = d:FindFirstAncestorOfClass("Model")
	if m and m:FindFirstChildOfClass("Humanoid") then return true end
	if d:IsA("MeshPart") then
		local c = d.Color
		if math.min(c.R, c.G, c.B) > Palette.TINT_NEUTRAL then return true end
	end
	return false
end

-- an untinted imported mesh: shows the pack's colours and is not one of ours
function Palette.needsWash(d)
	if not d:IsA("MeshPart") or CS:HasTag(d, "SVWashed") then return false end
	if Palette.isOurs(d.Name) or CS:HasTag(d, "SVNoPalette") then return false end
	local c = d.Color
	return math.min(c.R, c.G, c.B) > Palette.TINT_NEUTRAL
end

--[[ The authoring rule every part builder shares. Call it after the props are
	applied: a named Color maps into the palette, and a part with none gets the
	palette's version of Roblox's default grey (left alone, 719 parts once ended
	up identical and off-palette). ]]
local DEFAULT_GREY = Color3.fromRGB(163, 162, 165)
function Palette.author(p, props)
	p.Color = Palette.map(props.Color or DEFAULT_GREY)
end

--[[ Re-tint on entry, applied to the built world. Cloned packs never pass
	through a builder helper, and they are the biggest single source of
	disagreement -- 201 ring cars, 115 district cars, 418 pack meshes. This is
	the only place that can reach them.

	Returns how many parts it changed, so a caller can log it and so the
	number can be watched rather than assumed. ]]
function Palette.enforce(root)
	if not root then return 0 end
	local changed, washed, tagged = 0, 0, 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			if Palette.needsWash(d) then
				d.Color = Palette.PACK_WASH
				CS:AddTag(d, "SVWashed")
				washed += 1
			elseif not Palette.exempt(d) then
				local want = Palette.map(d.Color)
				if not same8(want, d.Color) then
					d.Color = want
					changed += 1
				end
			end
			-- a reviewed emissive states itself with a tag, so a NEW one shows up
			if d.Material == Enum.Material.Neon and not CS:HasTag(d, "SVEmissive")
				and Palette.EMISSIVE_OK[d.Name] then
				CS:AddTag(d, "SVEmissive")
				tagged += 1
			end
		end
	end
	return changed, washed, tagged
end

--[[ "Re-tinted ON ENTRY", meant literally.

	Routing every builder's helper caught most of it, and the world sweep
	caught the clones, but neither reaches a part that is coloured AFTER it is
	created, or built minutes later when a player buys a storey or a car. Those
	left 112 parts off-palette and 14 still at Roblox default grey, scattered
	across eight systems -- a fountain jet, a levee, a tent roof, a charger -- 
	and chasing them one site at a time is how a rule rots.

	So the rule becomes structural instead. Anything that enters the world is
	mapped as it arrives. A builder cannot forget, and a new builder inherits
	it for free.

	Deferred by one step so a part that is created and then coloured in the
	same tick is read after the colour is set, not before. That is the only
	re-read: there is no Color listener, so a colour set on a part that is
	already in the world (a later frame, a tween, a recolour) is NOT mapped
	here, and stays off-palette unless something runs Palette.enforce over it
	again (today only the build passes in SiliconCore and Wafers do). ]]
function Palette.watch(root)
	if not root or Palette._watching then return end
	Palette._watching = true

	local function apply(d)
		if not d:IsA("BasePart") or not d.Parent then return end
		if Palette.needsWash(d) then
			d.Color = Palette.PACK_WASH
			CS:AddTag(d, "SVWashed")
		elseif not Palette.exempt(d) then
			local want = Palette.map(d.Color)
			if not same8(want, d.Color) then d.Color = want end
		end
		if d.Material == Enum.Material.Neon and not CS:HasTag(d, "SVEmissive")
			and Palette.EMISSIVE_OK[d.Name] then
			CS:AddTag(d, "SVEmissive")
		end
	end

	root.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then task.defer(apply, d) end
	end)
	return true
end

return Palette
