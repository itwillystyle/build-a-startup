--[[
	SVStyle -- does the world obey art/ART.md? (S1 of art/STYLE-SPEC.md)

	WHY THIS EXISTS. ART.md has been a good art bible since 27 Sep and the game
	drifted anyway: 1,962 distinct colours against a 9-colour palette, 730 parts
	still at Roblox default grey, 2,955 hard-edged blocks. One rule held
	perfectly -- no Brick/Wood/Cobblestone on architecture, 0 violations -- and
	that is the evidence that matters. The bible is followable. What was missing
	was anything that reads it.

	A written rule with no instrument behind it is a preference. This is the
	instrument.

	THE RATCHET. A rule broken 2,955 times cannot fail a build on day one, and a
	check that only prints a number gets ignored by week two. So this stores a
	baseline of today's counts and fails only when a number goes UP. Nothing has
	to be fixed to switch it on; the gap simply stops widening, and every number
	becomes a score to drive down.

	WHAT IT DELIBERATELY DOES NOT DO. It does not judge whether the game looks
	good. It measures six things that are facts, and leaves taste to the
	styleframe.

		SVStyle.run()        the report, ratcheted against the baseline
		SVStyle.scan()       raw counts + detail, no judgement
		SVStyle.sweep()      pass rate at several tolerances, for tuning
		SVStyle.baselineSrc()  Lua source for StyleBaseline.lua
]]

local SVStyle = {}

--[[ The anchors are ART.md's palette table, unchanged. They are HUE FAMILIES,
	not swatches: nine flat colours cannot build a world, which is why the
	palette was quietly abandoned. Lightness is free, hue and saturation are
	not. So Oak is not one brown, it is every brown on that hue. ]]
--[[ ONE anchor list, shared with Palette. Two copies of a palette is two
	palettes: the check would pass colours the fixer rewrites, or flag the ones
	it just wrote. Palette owns it; this reads it. ]]
SVStyle.ANCHORS = require(game:GetService("ReplicatedStorage"):WaitForChild("Palette")).ANCHORS

--[[ Meshes our own Blender pipeline produced. svkit.py guarantees these
	prefixes, so this reads a contract rather than guessing at a name. They
	arrive already painted in the palette as vertex colour, so leaving them
	untinted is correct. Anything else untinted is an imported pack showing
	its own colours. ]]
SVStyle.OWN_PREFIX = { "LP_", "W_", "D_", "T_", "HQ", "SV" }

function SVStyle.isOurs(name)
	for _, p in ipairs(SVStyle.OWN_PREFIX) do
		if name:sub(1, #p) == p then return true end
	end
	return false
end

-- starting tolerances. STYLE-SPEC calls these a guess; SVStyle.sweep() exists
-- so they get tuned against real numbers before S2 rewrites any colour.
SVStyle.HUE_TOL = 0.02          -- about 7 degrees, wrap-aware
SVStyle.SAT_TOL = 0.08
SVStyle.NEUTRAL_MIN = 0.02      -- below this a colour is an untinted grey
SVStyle.SHARP_MIN = 2           -- ART.md: no sharp 90 degree edge over 2 studs
SVStyle.RESERVED_SAT = 0.75     -- full saturation belongs to accent/brand/UI only
SVStyle.TINT_NEUTRAL = 0.80     -- above this a MeshPart's Color is a tint, not a colour

local CS = game:GetService("CollectionService")

local anchorHSV
local function anchors()
	if not anchorHSV then
		anchorHSV = {}
		for _, a in ipairs(SVStyle.ANCHORS) do
			local c = Color3.fromRGB(a.rgb[1], a.rgb[2], a.rgb[3])
			local h, s, v = c:ToHSV()
			table.insert(anchorHSV, { name = a.name, h = h, s = s, v = v })
		end
	end
	return anchorHSV
end

-- hue lives on a circle, so 0.99 and 0.01 are neighbours, not opposites
local function hueGap(a, b)
	local d = math.abs(a - b)
	return d > 0.5 and (1 - d) or d
end

--[[ Returns anchorName, ok. A colour passes if some anchor shares its hue and
	saturation; its lightness may be anything. Saturation below NEUTRAL_MIN is
	rejected before hue is even considered, because hue is meaningless on a
	grey -- and an untinted grey is precisely the fault (ART.md: no pure white,
	no pure black, every neutral tinted toward the brand hue). ]]
--[[ The rule lives in Palette and this reads it. Two implementations of one
	rule is how a checker starts passing colours the fixer rewrites, and
	flagging the ones it just wrote -- which is exactly what happened: enforce
	changed 150 parts per pass and the off-palette count moved by two. ]]
function SVStyle.classify(c)
	local _, s = c:ToHSV()
	if s < SVStyle.NEUTRAL_MIN then return "neutral", false end
	local Pal = require(game:GetService("ReplicatedStorage"):WaitForChild("Palette"))
	local ok, name = Pal.compliant(c)
	return ok and name or "offPalette", ok
end

-- which top-level system owns this part, for pointing the work at a file
local function systemOf(part, root)
	local node, prev = part, part
	while node and node.Parent ~= root do
		prev = node
		node = node.Parent
	end
	return prev and prev.Name or "?"
end

--[[ People are exempt. Staff are real Roblox avatars by design (ART.md phase
	V2) and their skin tones, hair and clothing are not palette colours. ]]
local function isPerson(d)
	if CS:HasTag(d, "SVStaff") then return true end
	local m = d:FindFirstAncestorOfClass("Model")
	return (m and m:FindFirstChildOfClass("Humanoid")) ~= nil
end

local function bump(t, k)
	t[k] = (t[k] or 0) + 1
end

local function topList(t, n)
	local o = {}
	for k, v in pairs(t) do
		table.insert(o, { v, k })
	end
	table.sort(o, function(a, b)
		if a[1] ~= b[1] then return a[1] > b[1] end
		return a[2] < b[2]
	end)
	local out = {}
	for i = 1, math.min(n or 10, #o) do
		table.insert(out, string.format("%6d  %s", o[i][1], o[i][2]))
	end
	return out
end

--[[ The scan. Six counts, each a fact rather than an opinion:

	  parts         every BasePart considered (people and fully invisible excluded)
	  offPalette    a tinted part whose hue/saturation matches no anchor
	  flatNeutral   saturation under NEUTRAL_MIN: the 730 default-grey parts
	  untintedMesh  a MeshPart left at pure white, so it renders in the PACK'S
	                own colours. This is the "assets dropped in" feeling stated
	                as a number, and the palette gate structurally cannot see it
	                -- a mesh's real pixels live in vertex colour or a texture,
	                neither of which is readable from Luau.
	  sharp         a Block Part over SHARP_MIN studs: a hard 90 degree edge
	  neonLoose     Neon on something not tagged SVEmissive
	  colours       distinct Color values in the world
]]
function SVStyle.scan(root)
	root = root or workspace:FindFirstChild("SiliconValley")
	if not root then return nil, "no SiliconValley" end

	local c = {
		parts = 0, offPalette = 0, flatNeutral = 0,
		untintedOwn = 0, untintedPack = 0,
		sharp = 0, neonLoose = 0, colours = 0,
	}
	local detail = {
		offBySystem = {}, offByColour = {}, flatBySystem = {},
		untintedByName = {}, sharpBySystem = {}, neonByName = {},
		reserved = {},
	}
	local seen = {}

	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.95 and not isPerson(d) then
			c.parts += 1
			local col = d.Color
			local key = string.format("%d,%d,%d",
				math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5))

			--[[ On a MeshPart, Color is a MULTIPLIER over the asset's own vertex
				colours or texture, not a colour. Near white means "show the
				asset as authored"; the per-instance variation pass leaves hill
				trees at 223,225,227 and the like, which is a 2% tint, not a
				grey tree.

				Reading those as colours was wrong and loud: 4,568 hill-tree
				parts landed in the palette gate at mean saturation 0.04,
				producing 45% of the off-palette count and 65% of the flat-grey
				count. The world was fine; the instrument was measuring the
				wrong property. A mesh tinted to a real colour has a channel
				well below this line and is still judged. ]]
			local assetColoured = d:IsA("MeshPart")
				and math.min(col.R, col.G, col.B) > SVStyle.TINT_NEUTRAL
			--[[ Distinct AUTHORED colours only. Counting tint multipliers too
				measured the per-instance variation pass -- which is deliberate
				and good -- and reported it as sprawl. ]]
			if not assetColoured and not seen[key] then
				seen[key] = true
				c.colours += 1
			end
			if assetColoured then
				--[[ Untinted, so whatever the asset shipped is what renders.
					Split by whose asset it is, because only one half is a
					fault: our own Blender meshes carry vertex colour already
					painted in the palette, while an imported pack carries the
					pack's colours into the frame. That second number is the
					"assets dropped in" feeling stated as a count.

					Read off the OWN_PREFIX naming contract that svkit.py
					guarantees, not off a guess about what a name means. ]]
				if SVStyle.isOurs(d.Name) or CS:HasTag(d, "SVWashed") then
					c.untintedOwn += 1
				else
					c.untintedPack += 1
					bump(detail.untintedByName, d.Name)
				end
			else
				local anchorName, ok = SVStyle.classify(col)
				if anchorName == "neutral" then
					c.flatNeutral += 1
					bump(detail.flatBySystem, systemOf(d, root))
					bump(detail.offByColour, key)
				elseif not ok then
					c.offPalette += 1
					bump(detail.offBySystem, systemOf(d, root))
					bump(detail.offByColour, key)
				end
				local _, sat = col:ToHSV()
				if sat > SVStyle.RESERVED_SAT then bump(detail.reserved, d.Name) end
			end

			--[[ The corner rule. Invisible collision boxes are exempt by TAG,
				not by name: nobody ever sees them, and name-guessing is what
				made the Neon rule ambiguous. A builder that wants an exemption
				has to say so. ]]
			if d.ClassName == "Part" and d.Shape == Enum.PartType.Block
				and math.max(d.Size.X, d.Size.Y, d.Size.Z) > SVStyle.SHARP_MIN
				and not CS:HasTag(d, "SVStructural")
			then
				c.sharp += 1
				bump(detail.sharpBySystem, systemOf(d, root))
			end

			if d.Material == Enum.Material.Neon and not CS:HasTag(d, "SVEmissive") then
				c.neonLoose += 1
				bump(detail.neonByName, d.Name)
			end
		end
	end

	return c, detail
end

--[[ Tolerance sweep. STYLE-SPEC says the 0.02/0.08 figures are a starting
	guess and must be tuned against real numbers before any colour is
	rewritten, because a tolerance set too tight turns a palette into busywork
	and one set too loose passes the whole problem. ]]
function SVStyle.sweep(root)
	local h0, s0 = SVStyle.HUE_TOL, SVStyle.SAT_TOL
	local rows = {}
	for _, pair in ipairs({ { 0.01, 0.05 }, { 0.02, 0.08 }, { 0.03, 0.12 }, { 0.05, 0.20 }, { 0.08, 0.30 } }) do
		SVStyle.HUE_TOL, SVStyle.SAT_TOL = pair[1], pair[2]
		local c = SVStyle.scan(root)
		if c then
			table.insert(rows, string.format("   hue %.2f  sat %.2f  ->  off-palette %5d  (%.0f%% of %d pass)",
				pair[1], pair[2], c.offPalette, (c.parts - c.offPalette - c.flatNeutral) / c.parts * 100, c.parts))
		end
	end
	SVStyle.HUE_TOL, SVStyle.SAT_TOL = h0, s0
	return table.concat(rows, "\n")
end

local function baselineModule()
	local rs = game:GetService("ReplicatedStorage")
	local m = rs:FindFirstChild("StyleBaseline")
	if not m then return nil end
	local ok, data = pcall(require, m)
	return ok and data or nil
end

--[[ Lua source for StyleBaseline.lua, so the baseline is a committed file and
	a diff shows the ratchet moving. ]]
function SVStyle.baselineSrc(root)
	local c = SVStyle.scan(root)
	if not c then return "-- scan failed" end
	local keys = {}
	for k in pairs(c) do table.insert(keys, k) end
	table.sort(keys)
	local lines = {
		"-- StyleBaseline: the counts SVStyle ratchets against. Generated by",
		"-- SVStyle.baselineSrc(). Numbers may go DOWN in a commit, never up.",
		"-- Regenerate only when lowering a number on purpose.",
		"return {",
	}
	for _, k in ipairs(keys) do
		table.insert(lines, string.format("\t%s = %d,", k, c[k]))
	end
	table.insert(lines, "}")
	return table.concat(lines, "\n")
end

--[[ The report. Everything except `parts` and `colours` is a fault count that
	must not rise; `parts` is printed so a reader can tell whether the world had
	finished building, which is the mistake that made an earlier check report 1
	fault and then 859 for the same world a minute later. ]]
function SVStyle.run(root)
	local out = {}
	local function say(f, ...)
		table.insert(out, select("#", ...) > 0 and string.format(f, ...) or f)
	end

	local c, detail = SVStyle.scan(root)
	if not c then
		say("SVSTYLE  %s", tostring(detail))
		return table.concat(out, "\n")
	end

	say("SVStyle  %s", os.date("%Y-%m-%d %H:%M"))
	say("   %d parts considered, %d distinct colours (ART.md allows 9 hue families)", c.parts, c.colours)
	say("")
	say("   off-palette:      %5d   hue or saturation matches no anchor", c.offPalette)
	say("   flat neutral:     %5d   untinted grey, white or black", c.flatNeutral)
	say("   pack-coloured:    %5d   imported mesh rendering in the pack's own colours", c.untintedPack)
	say("   (ours-coloured:   %5d   our own vertex-coloured meshes, not a fault)", c.untintedOwn)
	say("   sharp blocks:     %5d   hard 90 degree edge over %d studs", c.sharp, SVStyle.SHARP_MIN)
	say("   loose Neon:       %5d   not tagged SVEmissive", c.neonLoose)
	say("")

	local base = baselineModule()
	local worse, better = {}, {}
	if base then
		for _, k in ipairs({ "offPalette", "flatNeutral", "untintedPack", "sharp", "neonLoose", "colours" }) do
			local was, now = base[k], c[k]
			if was then
				if now > was then
					table.insert(worse, string.format("%s %d -> %d (+%d)", k, was, now, now - was))
				elseif now < was then
					table.insert(better, string.format("%s %d -> %d (-%d)", k, was, now, was - now))
				end
			end
		end
	end

	for _, pair in ipairs({
		{ "WORST NON-COMPLIANT COLOURS", detail.offByColour },
		{ "OFF-PALETTE BY SYSTEM", detail.offBySystem },
		{ "UNTINTED GREY BY SYSTEM", detail.flatBySystem },
		{ "UNTINTED PACK MESHES BY NAME", detail.untintedByName },
		{ "SHARP BLOCKS BY SYSTEM", detail.sharpBySystem },
		{ "LOOSE NEON BY NAME", detail.neonByName },
	}) do
		local rows = topList(pair[2], 8)
		if #rows > 0 then
			say("   %s", pair[1])
			for _, r in ipairs(rows) do say("   %s", r) end
			say("")
		end
	end

	if not base then
		say("VERDICT  no StyleBaseline yet -- nothing to ratchet against.")
		say("         Save SVStyle.baselineSrc() to StyleBaseline.lua to arm it.")
	elseif #worse > 0 then
		say("VERDICT  WORSE: " .. table.concat(worse, ", "))
	else
		say("VERDICT  held" .. (#better > 0 and (" -- improved: " .. table.concat(better, ", ")) or ""))
	end
	return table.concat(out, "\n")
end

return SVStyle
