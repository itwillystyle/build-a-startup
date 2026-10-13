--[[ staff_sim (13 Oct 2026): Manage Staff's four balance gates, from the game's own modules.

	    lune run tools/staff_sim            the table, PASS/FAIL per gate; exit 1 on a FAIL
	    lune run tools/staff_sim -- --json  the same rows for bas

	The gates were declared in the spec BEFORE this ran (docs/superpowers/specs/
	2026-10-13-manage-staff-design.md §6.2, amended in the phase 1 plan):
	  G1  a team trained to its caps earns at most 2.0x an untrained one, every stage
	  G2  every Skill purchase pays back in 3..30 minutes at the stage it unlocks
	  G3  time to the next stage with greedy Skill training >= 70% of untrained
	  G4  the next run's time to stage 2 with 5 max-trained, max-loyal Genius keepers
	      >= 60% of the same keepers untrained (fallback declared in advance: carried
	      levels clamp to the new run's cap, StaffStats.carried)

	MODEL INPUTS, not game code (printed with the results):
	  everyone is a Lead (12/s) in a fit room (x1.5); the team is WaferPlan.CAP people;
	  talents per stage: 1 none rare; 2 one Star; 3 a Genius, two Stars; 4 two Genius,
	  three Stars; 5 three Genius, four Stars; the rest 70% Regular, 30% Skilled.
	  Other multipliers (studio, cafe, spin) are 1: the gates are ratios and paybacks,
	  which they cancel out of.
	NOT MODELLED: Speed (launch paydays) and the hire curve (the team is always full). ]]
require("../tests/offline/roblox_globals")
local process = require("@lune/process")
local serde = require("@lune/serde")
local S = require("../src/ReplicatedStorage/StaffStats")
local W = require("../src/ServerScriptService/WaferPlan")
local CFG = require("../src/ServerScriptService/CoreConfig")
local P = require("../src/ServerScriptService/Progression")

local JSON = table.find(process.args, "--json") ~= nil
local say = JSON and function(_) end or print
local LEAD, FIT = CFG.TIER_RATE[#CFG.TIER_RATE], 1.5
local STAGE_FROM = { 1, 5, 9, 13, 18 }
local RARE = { {}, { 3 }, { 4, 3, 3 }, { 4, 4, 3, 3, 3 }, { 4, 4, 4, 3, 3, 3, 3 } }

local function team(stage, n)
	local t = {}
	for _, x in RARE[stage] do table.insert(t, x) end
	local k = 0
	while #t < n do
		k += 1
		table.insert(t, (k % 10 < 3) and 2 or 1)
	end
	return t
end

local function personRate(talent, level, tierRate) return (tierRate or LEAD) * CFG.TALENT[talent].mult * FIT * W.MULT[level] end

local results, allOk = {}, true
local function gate(name, ok, detail)
	table.insert(results, { gate = name, ok = ok, detail = detail })
	if not ok then allOk = false end
	say(("%s  %-4s %s"):format(ok and "PASS" or "FAIL", name, detail))
end

say(("StaffStats: skill step %.3f, speed step %.3f, loyalty step %.3f, talent bonus {%s}"):format(
	S.step("skill"), S.step("speed"), S.step("loyalty"), table.concat(S.TALENT_BONUS, ",")))
say("model: Leads in fit rooms, a full team (WaferPlan.CAP), the talent mix above; G4: only the 5 keepers, as Interns; Speed not modelled")
say("")

-- ---------------------------------------------------------------- G1
do
	local worst, at = 0, 0
	for st = 1, 5 do
		local L = STAGE_FROM[st]
		local un, tr = 0, 0
		for _, t in team(st, W.CAP[L]) do
			local v = personRate(t, L)
			un += v
			tr += v * S.mult("skill", S.cap(st, t))
		end
		if tr / un > worst then worst, at = tr / un, st end
	end
	gate("G1", worst <= 2.0, ("trained/untrained income, worst %.3f (stage %d); limit 2.0"):format(worst, at))
end

-- ---------------------------------------------------------------- G2
do
	local lo, hi, where = math.huge, 0, ""
	for st = 1, 5 do
		local L = STAGE_FROM[st]
		for t = 1, #CFG.TALENT do
			local v = personRate(t, L)
			for lv = 0, S.cap(st, t) - 1 do
				local sec = S.price(lv, v, 1) / (v * S.step("skill"))
				if sec < lo then lo = sec end
				if sec > hi then hi, where = sec, ("stage %d talent %d level %d"):format(st, t, lv) end
			end
		end
	end
	gate("G2", lo >= 180 and hi <= 1800, ("Skill payback %.1f..%.1f min (slowest: %s); limits 3..30 min"):format(lo / 60, hi / 60, where))
end

-- ---------------------------------------------------------------- G3 / G4: time to climb
-- seconds from level a to level b, buying wafer levels as soon as affordable; with
-- `train`, any affordable Skill level that pays back within 30 min is bought first.
-- Steps of DT seconds (v1 used whole seconds: stage 1 of a run is a few seconds in the
-- model, and both G4 variants rounded to the same 4/6 s, a fake 0.667)
local DT = 0.05
local function climb(a, b, opts)
	local scale = opts.scale or 1
	local level, cash, t = a, 0, 0
	local tierRate = opts.tierRate
	local people = {}
	local function fill()
		if opts.noFill then return end
		local want = team(W.stage(level), W.CAP[level])
		for i = #people + 1, #want do people[i] = { talent = want[i], skill = 0 } end
	end
	for i, k in opts.keepers or {} do people[i] = { talent = k.talent, skill = k.skill } end
	fill()
	while level < b do
		local rate = 0
		for _, p in people do rate += personRate(p.talent, level, tierRate) * S.mult("skill", p.skill) end
		cash += rate * DT
		t += DT
		local need = W.price(level + 1, scale, 0)
		if cash >= need then
			cash -= need
			level += 1
			fill()
		elseif opts.train then
			local best, bestPrice
			for _, p in people do
				if S.canTrain(p.skill, W.stage(level), p.talent) then
					local v = personRate(p.talent, level, tierRate)
					local pr = S.price(p.skill, v, scale)
					if pr / (v * S.step("skill")) <= 1800 and (not bestPrice or pr < bestPrice) then best, bestPrice = p, pr end
				end
			end
			if best and cash >= bestPrice then
				cash -= bestPrice
				best.skill += 1
			end
		end
		if t > 86400 * 3 then break end   -- a model that never gets there is a FAIL, not a hang
	end
	return t
end

do
	local worst, at = math.huge, 0
	for st = 1, 4 do
		local a, b = STAGE_FROM[st], STAGE_FROM[st + 1]
		local r = climb(a, b, { train = true }) / climb(a, b, {})
		if r < worst then worst, at = r, st end
	end
	gate("G3", worst >= 0.70, ("greedy-trained/untrained time to the next stage, worst %.3f (stage %d -> %d); limit 0.70"):format(worst, at, at + 1))
end

do
	local scale = P.runScale(1)
	local function keepers(skill)
		local k = {}
		for i = 1, 5 do k[i] = { talent = 4, skill = skill } end
		return k
	end
	-- a new company starts with only its keepers, back at Intern (seniority resets)
	local base = { scale = scale, noFill = true, tierRate = CFG.TIER_RATE[1] }
	local function with(skill) local o = table.clone(base) o.keepers = keepers(skill) return o end
	local untrained = climb(1, 5, with(0))
	local full = math.ceil(1 / S.step("loyalty"))
	local raw = climb(1, 5, with(S.carry(13, full))) / untrained
	local clamped = climb(1, 5, with(S.carried(13, full, 1, 4))) / untrained
	say(("      G4 untrained climb %.1f s"):format(untrained))
	say(("      G4 raw carry (13 levels kept): ratio %.3f %s"):format(raw, raw >= 0.60 and "(passes without the fallback)" or "(fails: the declared fallback applies)"))
	gate("G4", clamped >= 0.60, ("next run to stage 2 with 5 max-loyal Genius keepers, carried levels clamped to the new cap: ratio %.3f; limit 0.60"):format(clamped))
end

if JSON then print(serde.encode("json", { ok = allOk, rows = results }, false)) end
process.exit(allOk and 0 or 1)
