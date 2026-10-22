-- palette.spec.luau: the accent anchors the art pass needs, and nothing else moves (22 Oct 2026).
-- Spec: silicon-startup/docs/superpowers/specs/2026-10-22-art-pass-design.md §5. The picked mocks
-- (ui/art-pass/) lean on teal and coral; with no anchor for them Palette.map pulled teal onto a grey
-- ValleyBlue (40,150,160 -> 96,140,160) and coral onto Oak.
-- Palette reads CollectionService at load; Lune has no `game`, so a stand-in answers HasTag
-- selene: allow(incorrect_standard_library_use)
game = game or { GetService = function() return { HasTag = function() return false end } end }
local Palette = require("../../src/ReplicatedStorage/Palette")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local function rgb(c) return { math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255) } end
local function near(a, b) return math.abs(a[1] - b[1]) <= 1 and math.abs(a[2] - b[2]) <= 1 and math.abs(a[3] - b[3]) <= 1 end

test("Teal and Coral are anchors and map onto themselves", function()
	for _, want in { { 40, 150, 160 }, { 236, 104, 84 } } do
		local got = rgb(Palette.map(Color3.fromRGB(want[1], want[2], want[3])))
		assert(near(got, want), ("%d,%d,%d mapped to %d,%d,%d"):format(want[1], want[2], want[3], got[1], got[2], got[3]))
	end
end)

-- Review Focus 4: every tower finish colour and department tint maps exactly as it did on 22 Oct
-- before the anchors were added (snapshot taken from Palette.map on main 292cb14)
local SNAPSHOT = {
	{ "W_glass", { 118, 158, 176 }, { 118, 158, 176 } },
	{ "W_fin", { 150, 156, 176 }, { 150, 156, 176 } },
	{ "W_band", { 243, 239, 230 }, { 243, 239, 230 } },
	{ "W_column", { 192, 138, 85 }, { 192, 138, 85 } },
	{ "W_line", { 250, 232, 205 }, { 245, 227, 201 } },
	{ "W_plate", { 30, 37, 48 }, { 30, 37, 48 } },
	{ "W_planter", { 192, 138, 85 }, { 192, 138, 85 } },
	{ "W_frame", { 56, 58, 66 }, { 56, 58, 66 } },
	{ "W_accent", { 243, 239, 230 }, { 243, 239, 230 } },
	{ "T_glass", { 140, 182, 200 }, { 140, 182, 200 } },
	{ "T_fin", { 150, 108, 66 }, { 150, 108, 66 } },
	{ "T_band", { 207, 198, 182 }, { 207, 198, 182 } },
	{ "T_column", { 150, 108, 66 }, { 150, 108, 66 } },
	{ "T_line", { 250, 232, 205 }, { 245, 227, 201 } },
	{ "T_plate", { 56, 58, 66 }, { 56, 58, 66 } },
	{ "T_planter", { 150, 108, 66 }, { 150, 108, 66 } },
	{ "T_frame", { 56, 58, 66 }, { 56, 58, 66 } },
	{ "T_accent", { 150, 108, 66 }, { 150, 108, 66 } },
	{ "D_glass", { 52, 66, 86 }, { 52, 66, 86 } },
	{ "D_fin", { 56, 58, 66 }, { 56, 58, 66 } },
	{ "D_band", { 30, 37, 48 }, { 30, 37, 48 } },
	{ "D_column", { 56, 58, 66 }, { 56, 58, 66 } },
	{ "D_line", { 90, 170, 240 }, { 90, 170, 240 } },
	{ "D_plate", { 30, 37, 48 }, { 30, 37, 48 } },
	{ "D_planter", { 56, 58, 66 }, { 56, 58, 66 } },
	{ "D_frame", { 207, 198, 182 }, { 207, 198, 182 } },
	{ "D_accent", { 90, 170, 240 }, { 90, 170, 240 } },
	{ "tint.lobby", { 236, 214, 170 }, { 236, 185, 73 } },
	{ "tint.eng", { 150, 188, 232 }, { 150, 188, 232 } },
	{ "tint.studio", { 236, 164, 192 }, { 236, 178, 121 } },
	{ "tint.cafe", { 246, 176, 116 }, { 246, 176, 116 } },
	{ "tint.servers", { 70, 78, 96 }, { 67, 78, 96 } },
	{ "tint.labs", { 122, 214, 198 }, { 129, 188, 214 } },
	{ "tint.board", { 236, 202, 112 }, { 224, 192, 106 } },
}
test("the new anchors repaint nothing that exists: all 3 finishes and 7 department tints", function()
	for _, row in SNAPSHOT do
		local c = row[2]
		local got = rgb(Palette.map(Color3.fromRGB(c[1], c[2], c[3])))
		assert(near(got, row[3]), ("%s now maps to %d,%d,%d (was %d,%d,%d)"):format(row[1], got[1], got[2], got[3], row[3][1], row[3][2], row[3][3]))
	end
end)

return T
