-- towerfinish.spec.luau: the three finishes (16 Oct 2026, HQ part 1d). Spec:
-- silicon-startup/docs/superpowers/specs/2026-10-16-hq-art-1d-design.md §2.8
local TF = require("../../src/ReplicatedStorage/TowerFinish")
local Palette = require("../../src/ReplicatedStorage/Palette")
local TT = {}
local function test(name, fn) table.insert(TT, { name = name, fn = fn }) end

local COLOURS = { "glass", "fin", "band", "column", "line", "plate", "planter", "frame", "accent" }

test("three finishes on the saved prefixes, every key present", function()
	assert(#TF.KEYS == 3 and TF.DEFAULT == "W_", "W_, T_, D_; Glass is the default")
	local names = { W_ = "Glass", T_ = "Timber", D_ = "Neon" }
	for _, k in ipairs(TF.KEYS) do
		local f = TF.SPEC[k]
		assert(f and f.name == names[k], k .. " is " .. names[k])
		for _, c in ipairs(COLOURS) do assert(type(f[c]) == "table" and #f[c] == 3, k .. "." .. c .. " is {r,g,b}") end
		assert(f.finStep > 0 and f.finW > 0 and f.finD > 0, k .. " fins")
		assert(type(f.lineDay) == "boolean" and type(f.planters) == "boolean", k .. " flags")
	end
end)

test("every colour is on the palette (CONSTRAINTS rule 12)", function()
	local function ok(t, what)
		local c = TF.color(t)
		assert(Palette.compliant(c), what .. (" (%d,%d,%d) is off the palette"):format(t[1], t[2], t[3]))
	end
	for _, k in ipairs(TF.KEYS) do
		for _, c in ipairs(COLOURS) do ok(TF.SPEC[k][c], k .. "." .. c) end
	end
	ok(TF.LEAF, "LEAF"); ok(TF.STRIP, "STRIP"); ok(TF.INK, "INK"); ok(TF.GOLD, "GOLD")
end)

test("Neon's light lines glow by day too; Glass and Timber light up only at night; Timber has the planters", function()
	assert(TF.SPEC.D_.lineDay == true and TF.SPEC.W_.lineDay == false and TF.SPEC.T_.lineDay == false, "lineDay")
	assert(TF.SPEC.T_.planters == true and TF.SPEC.W_.planters == false and TF.SPEC.D_.planters == false, "planters")
	assert(TF.SPEC.T_.finStep < TF.SPEC.W_.finStep and TF.SPEC.T_.finW > TF.SPEC.W_.finW, "Timber's fins: closer and wider")
end)

test("a missing or unknown finish draws Glass", function()
	assert(TF.get(nil) == TF.SPEC.W_ and TF.get("X_") == TF.SPEC.W_ and TF.get(5) == TF.SPEC.W_, "fallback")
	assert(TF.get("D_") == TF.SPEC.D_, "a real key")
end)

-- look review (16 Oct, ui/2026-10-16-art-1d/look-review-1d.md): the fixes, pinned
local function hsv(t) return TF.color(t):ToHSV() end

test("look review: Glass has colour (blue glass you cannot see straight through)", function()
	local _, s = hsv(TF.SPEC.W_.glass)
	assert(s >= 0.3, ("Glass's glass saturation %.2f: it reads white"):format(s))
	for _, k in ipairs(TF.KEYS) do
		local t = TF.SPEC[k].glassT
		assert(type(t) == "number" and t >= 0.2 and t <= 0.4, k .. " glassT in 0.2..0.4 (0.45 showed the furniture)")
	end
end)

test("look review: the night light is warm (rooms and Glass/Timber lines), not cold white", function()
	local function warm(t, what)
		local h, s = hsv(t)
		assert(h * 360 >= 25 and h * 360 <= 50 and s >= 0.12, ("%s hue %.0f sat %.2f: not warm"):format(what, h * 360, s))
	end
	warm(TF.STRIP, "STRIP")
	warm(TF.SPEC.W_.line, "Glass line")
	warm(TF.SPEC.T_.line, "Timber line")
end)

test("look review: door and lift frames stand out from the wall they sit on", function()
	for _, k in ipairs(TF.KEYS) do
		local _, _, vf = hsv(TF.SPEC[k].frame)
		local _, _, vb = hsv(TF.SPEC[k].band)
		assert(math.abs(vf - vb) >= 0.3, k .. ": the frame is the band's brightness, it vanishes")
	end
end)

test("look review: each picker card shows its finish (Timber's wood, Neon's line)", function()
	assert(TF.SPEC.T_.accent[1] == TF.SPEC.T_.fin[1] and TF.SPEC.T_.accent[2] == TF.SPEC.T_.fin[2], "Timber's card bands are its wood")
	assert(TF.SPEC.D_.accent[1] == TF.SPEC.D_.line[1], "Neon's card shows its light line colour")
end)

return TT
