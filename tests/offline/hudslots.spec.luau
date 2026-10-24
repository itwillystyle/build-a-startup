-- hudslots.spec.luau: the bottom-centre HUD, laid out as rectangles, run outside Studio.
-- 20 Oct (Luke's live run, 5:52-5:56 and 7:18): LAUNCH! sat half under the car's speed panel
-- while he drove, so he never saw it and the app auto-launched at half pay. Each script placed
-- its own piece with its own number; nothing checked the pieces against each other.
local H = require("../../src/ReplicatedStorage/HudSlots")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

-- a slot as a rectangle in pixels up from the bottom edge: { bottom, top }
local function span(bottom, height) return { bottom = bottom, top = bottom + height } end
local function gap(a, b)   -- vertical clearance between two spans (negative = they overlap)
	return math.max(a.bottom - b.top, b.bottom - a.top)
end

test("in a car, LAUNCH! sits fully above the speed panel", function()
	local launch = span(H.launchBottom(true, false), H.LAUNCH.height)
	local speedo = span(H.SPEEDO.bottom, H.SPEEDO.height)
	local g = gap(launch, speedo)
	assert(g >= H.GAP, ("LAUNCH! and the speed panel: %d px apart, want >= %d"):format(g, H.GAP))
end)

test("on foot, LAUNCH! clears HOLD TO CODE when both are up", function()
	local launch = span(H.launchBottom(false, true), H.LAUNCH.height)
	local code = span(H.CODE.bottom, H.CODE.height)
	local g = gap(launch, code)
	assert(g >= 8, ("LAUNCH! and HOLD TO CODE: %d px apart"):format(g))
end)

test("on foot with no verb, LAUNCH! takes the bottom slot itself", function()
	assert(H.launchBottom(false, false) == H.CODE.bottom, "LAUNCH! should drop into the empty bottom slot")
end)

test("in a car, LAUNCH! is still on a 375 px-tall phone screen", function()
	local top = H.launchBottom(true, false) + H.LAUNCH.height
	assert(top <= 375 - 120, ("LAUNCH! top at %d px up: the goal card owns the top 120 px of a phone"):format(top))
end)

--[[ 23 Oct (doctor, every HQ step at 1074 x 376): the money texts ran under an open menu.
	Hud.Rate ("+$13.6K / sec   ·   NEXT BUILD 33% OFF", 231 px) under Daily.Panel, the
	"+$X" pop (Hud.TextLabel, now CashPop) under Daily.Panel and Team.Panel. The HUD draws
	below every menu (DisplayOrder 4 vs 12-14), so what ran under was text cut by a panel
	edge. They step aside while a panel covers them, as the goal card already does. ]]
local F = require("../../src/ReplicatedStorage/MenuFit")
local SW, SH, RAIL = 1074, 376, 78          -- the doctor's screen; rail column right edge
-- a centred menu as fitMenu places it (y: centred, then pushed below the money line at 64)
local function menuRect(w, h, vMargin, floor)
	local s, cx = F.place({ w = w, h = h, px = 0, pw = SW, ph = SH, railRight = RAIL, vMargin = vMargin, floor = floor })
	local hh = h * s / 2
	local dy = (hh * 2 <= SH - 72) and math.max(0, 64 + hh - SH / 2) or 0
	return { cx - w * s / 2, SH / 2 + dy - hh, w * s, h * s }
end
local DAILY = menuRect(7 * 76 + 6 * 6 + 28, 48 + 12 + 30 + 96 + 14 + 56 + 14)   -- DailyClient W x H
local TEAM = menuRect(744, 368, 16, 44 / 52)                                     -- TeamClient, its tap floor
-- the income line where placeMoney puts it with nothing in the corner (bottom at 62 px up)
local function rateRect(w) return { 18, SH - 62 - 19, w, 19 } end

test("the full income line (231 px) is under the Daily panel, so it steps aside", function()
	assert(H.underMenu(rateRect(231), { DAILY }, SW), ("Daily at x %.0f, line ends at 249"):format(DAILY[1]))
end)

test("a short income line clear of the Daily panel stays on screen", function()
	assert(not H.underMenu(rateRect(110), { DAILY }, SW), "+$13.6K / sec alone should stay")
end)

test("the income line and the cash pop step aside for TEAM", function()
	assert(H.underMenu(rateRect(231), { TEAM }, SW), ("TEAM at x %.0f"):format(TEAM[1]))
	local pop = { 14, SH - (62 + 46 + 24) - 4 - 40, 320, 40 }
	assert(H.underMenu(pop, { TEAM }, SW), "the +$X pop under TEAM")
end)

test("no menu open: nothing steps aside", function()
	assert(not H.underMenu(rateRect(231), {}, SW), "no panels")
end)

test("only a panel counts: a full-screen layer or a small chip does not hide the money", function()
	assert(not H.underMenu(rateRect(231), { { 0, 0, SW, SH } }, SW), "a full-screen layer is not a panel")
	assert(not H.underMenu(rateRect(231), { { 200, 280, 60, 40 } }, SW), "a 60 x 40 chip is not a panel")
end)

test("touching edges is not under", function()
	local r = rateRect(231)
	assert(not H.underMenu(r, { { r[1] + r[3], 0, 400, SH } }, SW), "a panel starting where the line ends")
end)

return T
