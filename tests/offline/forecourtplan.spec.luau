-- forecourtplan.spec.luau: what stands in front of the garage, against everything that moves there (22 Oct 2026).
-- Spec: silicon-startup/docs/superpowers/specs/2026-10-22-art-pass-design.md (Luke's picked mock
-- ui/art-pass/garage-outside.png: a bench, a bike rack, planters, a mailbox, and a fenced lot with a crane).
-- Measured 22 Oct (Studio, camera C2): the view outside had contrast 0.28 against 0.60 in the mock: a pale
-- empty court in front of a small bare garage. Nothing placed there may block the game.
local FP = require("../../src/ReplicatedStorage/ForecourtPlan")
local W = require("../../src/ReplicatedStorage/WalkLanes")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local function kinds()
	local k = {}
	for _, p in FP.PROPS do k[p.kind] = (k[p.kind] or 0) + 1 end
	return k
end

test("the mock's pieces are all there", function()
	local k = kinds()
	for _, want in { "bench", "bikerack", "planter", "mailbox", "lotFence", "crane", "comingSoon" } do
		assert(k[want], "missing " .. want)
	end
	assert(k.planter >= 3, "at least 3 planters")
end)

test("the real plan is clean: nothing on the path, the client line, the clients' walk-in, the promenade, the garage, the drop-off or the car", function()
	local problems = FP.check()
	assert(#problems == 0, problems[1])
end)

test("check() catches a bench dropped on the client line", function()
	local bad = { { name = "BadBench", kind = "bench", x = 0, z = 25, w = 5, d = 1.6, h = 2.2 } }
	local problems = FP.check(bad)
	assert(#problems >= 1, "a bench in the door line must be refused")
end)

test("check() catches a planter on the clients' diagonal walk-in", function()
	local bad = { { name = "BadPlanter", kind = "planter", x = -8, z = 40, w = 3, d = 3, h = 2 } }
	assert(#FP.check(bad) >= 1, "a planter on the walk-in line must be refused")
end)

test("everything stays clear of the drive pavements' walkers (WalkLanes)", function()
	local reach = W.ARM_WALK - W.ARM_KEEP - 1.9 - 1
	for _, p in FP.PROPS do
		assert(math.abs(p.x) + p.w / 2 <= reach, ("%s reaches x %.1f; the walkers start at %.1f"):format(p.name, math.abs(p.x) + p.w / 2, reach))
	end
end)

test("the coming-soon frame carries no words", function()
	for _, p in FP.PROPS do
		if p.kind == "comingSoon" then assert(p.text == nil, "the world never draws words for this") end
	end
end)

test("the court's colour is a value step down and stays on the palette", function()
	-- selene: allow(incorrect_standard_library_use)
	game = game or { GetService = function() return { HasTag = function() return false end } end }
	local Palette = require("../../src/ReplicatedStorage/Palette")
	local c = FP.COURT
	local h, s, v = Color3.fromRGB(c[1], c[2], c[3]):ToHSV()
	local _, _, v0 = Color3.fromRGB(214, 208, 196):ToHSV()
	assert(v <= v0 - 0.05, ("value %.2f, was %.2f"):format(v, v0))
	local m = Palette.map(Color3.fromRGB(c[1], c[2], c[3]))
	local back = { math.round(m.R * 255), math.round(m.G * 255), math.round(m.B * 255) }
	assert(math.abs(back[1] - c[1]) <= 2 and math.abs(back[2] - c[2]) <= 2 and math.abs(back[3] - c[3]) <= 2,
		("%d,%d,%d is repainted to %d,%d,%d"):format(c[1], c[2], c[3], back[1], back[2], back[3]))
	local _ = h + s
end)

-- 22 Oct, the look review (Task 6): the outside camera measured contrast 0.32 after the yard went
-- in; a live experiment with dark hedges along the court and bushes on the lawn took it to 0.495
-- (the mock's dark greens are what carry its contrast). They are part of the plan now.
test("the yard has the mock's dark greens: court hedges, path hedges and bushes", function()
	local k = kinds()
	assert((k.hedge or 0) >= 4, "hedges along both court sides and both sides of the path")
	assert((k.bush or 0) >= 6, "bushes on the lawn either side of the garage")
end)

test("the hedge green is the mock's deep green and stays on the palette", function()
	-- selene: allow(incorrect_standard_library_use)
	game = game or { GetService = function() return { HasTag = function() return false end } end }
	local Palette = require("../../src/ReplicatedStorage/Palette")
	local c = FP.HEDGE
	local _, _, v = Color3.fromRGB(c[1], c[2], c[3]):ToHSV()
	assert(v <= 0.40, ("hedge value %.2f: it must be the frame's darkest green"):format(v))
	local m = Palette.map(Color3.fromRGB(c[1], c[2], c[3]))
	local back = { math.round(m.R * 255), math.round(m.G * 255), math.round(m.B * 255) }
	assert(math.abs(back[1] - c[1]) <= 2 and math.abs(back[2] - c[2]) <= 2 and math.abs(back[3] - c[3]) <= 2,
		("%d,%d,%d is repainted to %d,%d,%d"):format(c[1], c[2], c[3], back[1], back[2], back[3]))
end)

-- 22 Oct, Luke's look review at night: "a little too dark" at the door, where the first client
-- stands. Two porch lamps by the door; SkyClient lights SVLamp heads near the camera after dark.
test("two porch lamps light the door at night", function()
	local lamps = {}
	for _, p in FP.PROPS do if p.kind == "lamp" then table.insert(lamps, p) end end
	assert(#lamps >= 2, "a lamp either side of the door")
	for _, l in lamps do
		assert(math.abs(l.x) <= 14 and l.z <= 24, ("%s at (%d, %d): it must stand by the door"):format(l.name, l.x, l.z))
	end
end)

-- 22 Oct (the doctor's "sinking surfaces", WorldHealth): a 3 x 3 planter you can step onto must hold
-- you; as decor with no collision a player sank 0.9 studs into it. Anything that wide and that low is solid.
test("anything 3 studs wide and under 2.5 tall you could step onto is solid", function()
	for _, p in FP.PROPS do
		if math.min(p.w, p.d) >= 3 and p.h <= 2.5 and p.kind ~= "lotFence" then
			assert(p.solid, ("%s (%s) is %.1f x %.1f and %.1f tall: a player would sink into it"):format(p.name, p.kind, p.w, p.d, p.h))
		end
	end
end)

return T
