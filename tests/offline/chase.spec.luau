-- chase.spec.luau: the headhunter chase, measured against a human-like player
-- (chase_model.luau) running the same ChaseRules code the game runs.
--
-- v4.4 (8 Oct). His recording: "if you just go in a straight line, the thing cannot
-- catch you ... you just spam the shift". Measured on v4.3 (tools/chase_threat):
-- holding W escaped 100% on every tier and scooter, BOOST-spamming 100%, and
-- steering on the tell was punished (genius 11%). These tests are the new contract:
-- the exploit is dead, reading the tell is the skill, and every catch had a tell.
local R = require("../../src/ServerScriptService/ChaseRules")
local M = require("./chase_model")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end
local N = 400

-- v4.6: D comes from the SAME bands TalentDrop spawns candidates in (the route home is
-- D along the road plus a 40-stud turn, so D = band middle - 40). Never type these by hand
-- again: on 8 Oct they said 140/280/300 while the live map ran 0/18/125 (see ChaseRules).
local function Dof(id) return R.bandMid(id) - 40 end
local RUNS = {
	skilled = { id = "skilled", D = Dof("skilled"), speed = 16 },
	star = { id = "star", D = Dof("star"), speed = 17 },
	genius = { id = "genius", D = Dof("genius"), speed = 18 },
	vipStar = { id = "star", D = 600, speed = 17, vip = true },
	vipGenius = { id = "genius", D = 600, speed = 19, vip = true },
}
local function opts(run, skill, speed)
	local D = run.D
	return { D = D, speed = speed or run.speed, skill = skill, deadline = 14 + (D + 40) * 0.11 }
end
local function rate(run, skill, speed, rules)
	local sp = speed or run.speed
	return M.rate(R, rules or M.newRules(R, R.config(run.id, run.vip, sp)), opts(run, skill, sp), N)
end

test("the OLD hunter was the bug: everyone escaped and it never got close", function()
	for _, k in { "skilled", "star", "genius" } do
		local run = RUNS[k]
		local old = ({ skilled = { 11, 17 }, star = { 12, 19 }, genius = { 13, 21 } })[k]
		local esc, _, danger = rate(run, "novice", nil, M.oldRules(old[1], old[2]))
		assert(esc >= 0.99 and danger < 0.02, ("%s old: %.0f%% escaped, %.0f%% in danger"):format(k, esc * 100, danger * 100))
	end
end)

test("THE EXPLOIT IS DEAD: holding W, or spamming BOOST, loses a genius hire", function()
	for _, sp in { 18, 20 } do
		for _, k in { "straight", "spammer" } do
			local e = rate(RUNS.genius, k, sp)
			assert(e <= 0.05, ("genius @%d %s escaped %.0f%%"):format(sp, k, e * 100))
		end
	end
	local s = rate(RUNS.star, "straight")
	assert(s <= 0.30, ("star straight escaped %.0f%%"):format(s * 100))
end)

test("READING THE TELL IS THE SKILL: an ace gets away on star and genius, faster scooter or not", function()
	for _, k in { "star", "genius" } do
		for _, sp in { RUNS[k].speed, 20 } do
			local a = rate(RUNS[k], "ace", sp)
			assert(a >= 0.80, ("%s @%d ace %.0f%%"):format(k, sp, a * 100))
		end
	end
	-- and reading most tells is a real chance even on a genius
	local r = rate(RUNS.genius, "reader")
	assert(r >= 0.35, ("genius reader %.0f%%"):format(r * 100))
end)

test("SKILLED teaches the tell: it lunges, and anyone who keeps moving gets away", function()
	for _, k in { "straight", "novice", "reader" } do
		local e = rate(RUNS.skilled, k)
		assert(e >= 0.95, ("skilled %s %.0f%%"):format(k, e * 100))
	end
	-- it does lunge (the lesson), it just cannot land one on a moving player
	local base = M.newRules(R, R.config("skilled", false, 16))
	local lunges, last = 0, {}
	local rules = setmetatable({ step = function(h, ...)
		local ph, d = base.step(h, ...)
		if ph == "windup" and last[h] ~= "windup" then lunges += 1 end
		last[h] = ph
		return ph, d
	end }, { __index = base })
	M.rate(R, rules, opts(RUNS.skilled, "straight"), 200)
	assert(lunges / 200 >= 0.3, ("skilled lunged %.2f times per run"):format(lunges / 200))
end)

test("freezing with it behind you gets you caught on star and genius", function()
	for _, k in { "star", "genius" } do
		assert(rate(RUNS[k], "hesitant") <= 0.10, k .. " hesitant")
	end
	assert(rate(RUNS.genius, "idle") <= 0.15, "genius idle")
end)

test("EVERY CATCH HAD A TELL: between lunges it never walks up and tags you", function()
	local base = M.newRules(R, R.config("genius", false, 19))
	local byPhase, last = {}, {}
	local rules = setmetatable({ step = function(h, ...)
		local ph, d = base.step(h, ...)
		last.ph = ph
		return ph, d
	end }, { __index = base })
	local caught = 0
	for i = 1, N do
		last.ph = nil
		local e = M.run(R, rules, opts(RUNS.genius, "reader", 19), 7919 * i + 13)
		if not e then
			caught += 1
			byPhase[last.ph or "?"] = (byPhase[last.ph or "?"] or 0) + 1
		end
	end
	-- "chase" catches are the player running INTO it after a dodge; they must be rare
	local plain = (byPhase.chase or 0) / math.max(caught, 1)
	assert(plain <= 0.12, ("%.0f%% of catches came with no lunge"):format(plain * 100))
end)

test("a faster scooter (HQ levels, an Energy Drink) is an edge, never a penalty", function()
	for _, k in { "star", "genius" } do
		for _, skill in { "reader", "ace" } do
			local base = rate(RUNS[k], skill)
			local fast = rate(RUNS[k], skill, 20)
			assert(fast >= base - 0.05, ("%s %s at %d: %.0f%%, at 20: %.0f%%"):format(k, skill, RUNS[k].speed, base * 100, fast * 100))
		end
	end
end)

test("the daily VIP stays the hardest run, and an ace can still win it", function()
	for _, k in { "vipStar", "vipGenius" } do
		assert(rate(RUNS[k], "straight") <= 0.05, k .. " straight")
		local a = rate(RUNS[k], "ace")
		assert(a >= 0.70, ("%s ace %.0f%%"):format(k, a * 100))
	end
end)

test("THE MAP CONTRACT: the sim runs the chase lengths the game spawns (v4.6)", function()
	for _, k in { "skilled", "star", "genius" } do
		local b = R.BANDS[k]
		assert(b and b[1] < b[2], k .. " has no band")
		local route = RUNS[k].D + 40
		assert(route >= b[1] and route <= b[2], ("%s sim route %d is outside the live band %d-%d"):format(k, route, b[1], b[2]))
	end
	assert(R.HOME_SAFE < R.BANDS.skilled[1] / 4, "the home stretch must be a small part of the shortest run")
	assert(R.DELIVER_R > 0 and R.DELIVER_R < R.HOME_SAFE, "you are home before the safe zone ends")
end)

test("the lunge is aimed: it meets a player who holds their line", function()
	-- player 12 studs ahead along -x at 19: the intercept is on their line, in reach
	local ax, az = R.intercept(-12, 0, -19, 0, 34, 1.0)
	assert(math.abs(az) < 1e-6 and ax < -12, "aim must be ahead on the player's line")
	local tau = (-ax) / 34
	assert(math.abs((-12 - 19 * tau) - ax) < 1e-3, "the lunge and the player arrive together")
end)

return T
