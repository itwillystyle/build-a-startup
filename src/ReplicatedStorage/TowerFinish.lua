--[[ TowerFinish (16 Oct 2026, HQ tower part 1d): the three finishes of the one tower. Pure: no services,
	no requires (the picker on the client and TowerArt on the server both read it).
	Spec: docs/superpowers/specs/2026-10-16-hq-art-1d-design.md §2.8. Every colour is a Palette anchor
	or within its tolerance (towerfinish.spec checks it), so Palette.enforce leaves them alone.
	Look review (16 Oct, ui/2026-10-16-art-1d/look-review-1d.md): Glass had almost no colour and showed
	the furniture (bluer glass, `glassT` 0.3); the night light read cold white (a warm white now); the
	door and lift frames vanished on the band (`frame` contrasts); the picker cards needed each finish's
	tell-tale colour (`accent`: Glass's band, Timber's wood, Neon's line). ]]
local TF = {}

TF.KEYS = { "W_", "T_", "D_" }
TF.DEFAULT = "W_"

TF.LEAF = { 74, 150, 84 }      -- Foliage: planters, trees
TF.STRIP = { 250, 232, 205 }   -- a warm white: a room's ceiling light at night
TF.INK = { 30, 37, 48 }        -- small dark parts (the shaft cap's door)
TF.GOLD = { 255, 194, 61 }     -- BrandGold: the crane, the safety rail, the beacon, the names

TF.SPEC = {
	W_ = { name = "Glass", glass = { 118, 158, 176 }, glassT = 0.3, fin = { 150, 156, 176 }, band = { 243, 239, 230 },
		column = { 192, 138, 85 }, line = { 250, 232, 205 }, plate = { 30, 37, 48 }, planter = { 192, 138, 85 },
		frame = { 56, 58, 66 }, accent = { 243, 239, 230 },
		finStep = 5, finW = 0.5, finD = 1.1, lineDay = false, planters = false },
	T_ = { name = "Timber", glass = { 140, 182, 200 }, glassT = 0.35, fin = { 150, 108, 66 }, band = { 207, 198, 182 },
		column = { 150, 108, 66 }, line = { 250, 232, 205 }, plate = { 56, 58, 66 }, planter = { 150, 108, 66 },
		frame = { 56, 58, 66 }, accent = { 150, 108, 66 },
		finStep = 3.6, finW = 0.9, finD = 1.8, lineDay = false, planters = true },
	D_ = { name = "Neon", glass = { 52, 66, 86 }, glassT = 0.3, fin = { 56, 58, 66 }, band = { 30, 37, 48 },
		column = { 56, 58, 66 }, line = { 90, 170, 240 }, plate = { 30, 37, 48 }, planter = { 56, 58, 66 },
		frame = { 207, 198, 182 }, accent = { 90, 170, 240 },
		finStep = 5, finW = 0.5, finD = 1.1, lineDay = true, planters = false },
}

function TF.get(key)
	return (type(key) == "string" and TF.SPEC[key]) or TF.SPEC[TF.DEFAULT]
end

function TF.color(t) return Color3.fromRGB(t[1], t[2], t[3]) end

return TF
