-- chase.spec.luau: the headhunter chase (v4.3), measured against a human-like
-- player (chase_model.luau) running the same ChaseRules code the game runs.
local R = require("../../src/ServerScriptService/ChaseRules")
local M = require("./chase_model")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end
local N = 400

local RUNS = {
	skilled = { id = "skilled", D = 140, speed = 16, old = { 11, 17 } },
	star = { id = "star", D = 280, speed = 17, old = { 12, 19 } },
	genius = { id = "genius", D = 440, speed = 18, old = { 13, 21 } },
	vipStudio = { id = "star", D = 600, speed = 17, vip = true },
	vipLoft = { id = "genius", D = 600, speed = 19, vip = true },
}
local function rate(run, skill, rules)
	local o = { D = run.D, speed = run.speed, skill = skill, deadline = 14 + (run.D + 40) * 0.11 }
	return M.rate(R, rules or M.newRules(R, R.config(run.id, run.vip, run.speed)), o, N)
end

test("the OLD hunter was the bug: everyone escaped and it never got close", function()
	for _, k in { "skilled", "star", "genius" } do
		local run = RUNS[k]
		local esc, _, danger = rate(run, "novice", M.oldRules(run.old[1], run.old[2]))
		assert(esc >= 0.99 and danger < 0.02, ("%s old: %.0f%% escaped, %.0f%% in danger"):format(k, esc * 100, danger * 100))
	end
end)

test("a new player holding forward: SKILLED safe, STAR a fight, GENIUS a coin flip at best", function()
	local s = rate(RUNS.skilled, "novice")
	local st = rate(RUNS.star, "novice")
	local g = rate(RUNS.genius, "novice")
	assert(s >= 0.95, ("SKILLED %.0f%%"):format(s * 100))
	assert(st >= 0.60 and st <= 0.95, ("STAR %.0f%%"):format(st * 100))
	assert(g >= 0.15 and g <= 0.60, ("GENIUS %.0f%%"):format(g * 100))
end)

test("BOOST on the tell is the skill: 95%+ escapes on every run, VIP included", function()
	for k, run in RUNS do
		local g = rate(run, "good")
		assert(g >= 0.95, ("%s: %.0f%% with boost"):format(k, g * 100))
	end
end)

test("freezing for 1.5 s or standing 3 s with it behind you gets you caught", function()
	for _, k in { "star", "genius", "vipLoft" } do
		assert(rate(RUNS[k], "hesitant") <= 0.10, k .. " hesitant")
		assert(rate(RUNS[k], "idle") <= 0.02, k .. " idle")
	end
end)

test("the fear: on a GENIUS run it is within 12 studs for a quarter of the run or more", function()
	local _, _, danger = rate(RUNS.genius, "novice")
	assert(danger >= 0.25, ("danger %.0f%%"):format(danger * 100))
end)

test("the VIP's second hunter is a junior: a Loft VIP run is winnable without boost", function()
	local v = rate(RUNS.vipLoft, "novice")
	assert(v >= 0.15, ("VIP (Loft) novice %.0f%%"):format(v * 100))
end)

test("a faster scooter (HQ levels, an Energy Drink) is an edge, never a penalty", function()
	local base = rate({ id = "star", D = 280, speed = 17 }, "novice")
	local fast = rate({ id = "star", D = 280, speed = 20 }, "novice")
	assert(fast >= base - 0.02, ("STAR at 17: %.0f%%, at 20: %.0f%%"):format(base * 100, fast * 100))
end)

return T
