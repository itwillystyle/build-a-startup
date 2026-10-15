-- menufit.spec.luau: where a menu goes and how small it may draw (14 Oct 2026)
-- The doctor measured TEAM's 52 px taps at 42 px on a 1074 x 395 window: fitMenu
-- shrank the panel to 0.8237 (its gui was 712.8 wide, rail one 66 px tile wide).
local F = require("../../src/ReplicatedStorage/MenuFit")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local TEAM_W, TEAM_H, TAP, MIN_TAP = 744, 368, 52, 44
local floor = MIN_TAP / TAP

local function team(pw, ph, railRight)
	return F.place({ w = TEAM_W, h = TEAM_H, px = 0, pw = pw, ph = ph, railRight = railRight, vMargin = 16, floor = floor })
end

test("no floor: the old rule (0.8237 in the measured case)", function()
	local s = F.place({ w = TEAM_W, h = TEAM_H, px = 0, pw = 712.8, ph = 395.2, railRight = 78, vMargin = 16 })
	assert(math.abs(s - 0.8237) < 0.001, tostring(s))
end)

test("TEAM taps stay >= 44 px at the doctor's measured size, rail on", function()
	local s = team(712.8, 395.2, 78)
	assert(TAP * s >= MIN_TAP - 1e-6, ("tap %.2f px"):format(TAP * s))
end)

test("a big window still draws at 1, centred", function()
	local s, cx = team(1074.4, 395.2, 148)
	assert(s == 1, tostring(s))
	assert(math.abs(cx - 1074.4 / 2) < 1e-6, tostring(cx))
end)

-- the doctor's window and the phones UI step 5 measured, rail one and two tiles wide
local SIZES = { { 1074.4, 395.2 }, { 712.8, 395.2 }, { 844, 390 }, { 749, 381 }, { 667, 375 }, { 1074, 355 } }
test("every size: taps >= 44 and the panel stays on screen", function()
	for _, sz in ipairs(SIZES) do
		for _, rail in ipairs({ 78, 148 }) do
			local s, cx = team(sz[1], sz[2], rail)
			local tag = ("%gx%g rail %d"):format(sz[1], sz[2], rail)
			assert(TAP * s >= MIN_TAP - 1e-6, tag .. (" tap %.2f"):format(TAP * s))
			local half = TEAM_W * s / 2
			assert(cx - half >= 12 - 1e-6 and cx + half <= sz[1] - 12 + 1e-6, tag .. (" x %.1f..%.1f"):format(cx - half, cx + half))
			assert(TEAM_H * s <= sz[2] - 16 + 1e-6, tag .. (" h %.1f"):format(TEAM_H * s))
		end
	end
end)

test("at the floor and too wide for the strip, it covers as little rail as it can", function()
	local s, cx = team(712.8, 395.2, 78)
	local half = TEAM_W * s / 2
	-- right edge on the right margin: the overlap with the rail is the smallest possible
	assert(math.abs(cx + half - (712.8 - 12)) < 1e-6, tostring(cx + half))
end)

test("fits beside the rail: never covers it", function()
	local s, cx = team(1074.4, 395.2, 148)
	assert(cx - TEAM_W * s / 2 >= 158 - 1e-6, tostring(cx))
end)

return T
