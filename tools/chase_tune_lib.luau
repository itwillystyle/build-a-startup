--[[ chase_tune_lib -- the overnight chase tuner's judge and search (11 Oct 2026).

	WHY. The doctor measures the chase every morning and the simulator can play
	thousands of chases a second, but nobody was turning the knobs between the
	two. On 11 Oct the live numbers missed the design spec
	(docs/superpowers/specs/2026-10-08-chase-threat-design.md) and the camera cut
	0.66-1.28 times a second on a genius run (limit 0.5). This is a judge and a
	search, so a machine can try tens of thousands of tunings overnight against
	numbers instead of feel.

	THE JUDGE, three layers:
	  1. HARD: tests/offline/chase.spec.luau must pass, as is. It is run in this
	     process against the mutated ChaseRules, so the tuner can never trade away
	     the contract (the exploit stays dead, an ace gets away, every catch had a
	     tell, a faster scooter never hurts, the VIP stays hardest).
	  2. SOFT, the design spec: steering or boosting on the tell escapes a genius
	     80%+, a star 85%+; the genius still sits within 12 studs of a good player
	     for 30%+ of the run (the fear). Score = sum of squared shortfalls (points).
	  3. SOFT, the edit: the camera director (ChaseCam.direct) watches the same
	     simulated chases and must cut 0.5 times a second or less. A cut here is a
	     shot change or a framing snap, the two things the client turns into a jump
	     cut. It is a PROXY: the live doctor's count is the truth.

	The design spec also asks "star, holding W: escapes 50-85%"; chase.spec says
	30% or less. The spec in CI wins (layer 1); the report names the conflict.

	Pure: only the two modules' tables are mutated, and `restore` puts them back. ]]
local L = {}

require("../tests/offline/roblox_globals")   -- Vector3 for the camera director
local R = require("../src/ServerScriptService/ChaseRules")
local C = require("../src/ReplicatedStorage/ChaseCam")
local M = require("../tests/offline/chase_model")
L.R, L.C, L.M = R, C, M

-- what may move, and how far. Everything is read at call time (BEHIND_DEG is not:
-- it is baked into a cosine when ChaseRules loads, so it is not on the list).
L.PARAMS = {
	{ key = "genius.stalk", lo = 1.00, hi = 1.20 },
	{ key = "genius.jog", lo = 0.90, hi = 1.02 },
	{ key = "genius.lunge", lo = 1.50, hi = 2.20 },
	{ key = "genius.range", lo = 10, hi = 15 },
	{ key = "genius.every", lo = 5.0, hi = 8.5 },
	{ key = "star.stalk", lo = 0.98, hi = 1.10 },
	{ key = "star.jog", lo = 0.90, hi = 1.00 },
	{ key = "star.lunge", lo = 1.30, hi = 1.80 },
	{ key = "star.range", lo = 8, hi = 13 },
	{ key = "star.every", lo = 4.5, hi = 7.5 },
	{ key = "WINDUP", lo = 0.45, hi = 0.70 },
	{ key = "LUNGE_TIME", lo = 0.80, hi = 1.20 },
	{ key = "OVERSHOOT", lo = 1, hi = 4 },
	{ key = "HOLD", lo = 6, hi = 9 },
	{ key = "LEAD_MAX", lo = 0.5, hi = 1.0 },
	{ key = "cam.MIN_HOLD", lo = 1.35, hi = 2.6 },
	{ key = "cam.EPISODE", lo = 3.2, hi = 5.5 },
	{ key = "cam.CLOSE_IN", lo = -2.4, hi = -1.0 },
	{ key = "cam.CLOSE_OUT", lo = -1.0, hi = -0.3 },
	{ key = "cam.AWAY_IN", lo = 1.0, hi = 2.4 },
	{ key = "cam.AWAY_OUT", lo = 0.3, hi = 1.0 },
	{ key = "cam.STRIKE_BAND", lo = 14, hi = 20 },
}

-- where each key lives: the table, the field, and the file a human edits
local function slot(key)
	local tier, f = key:match("^(%a+)%.([%w_]+)$")
	if tier == "cam" then return C.DIR, f, "src/ReplicatedStorage/ChaseCam.lua", "ChaseCam.DIR." .. f end
	if tier then return R.TIERS[tier], f, "src/ServerScriptService/ChaseRules.lua", "C.TIERS." .. tier .. "." .. f end
	return R, key, "src/ServerScriptService/ChaseRules.lua", "C." .. key
end
L.slot = slot

function L.read()
	local p = {}
	for _, d in L.PARAMS do
		local t, f = slot(d.key)
		p[d.key] = t[f]
	end
	return p
end

-- the director's own rules: the shot taken on the tell survives the strike, and
-- each claim needs a gap between entering and leaving it (hysteresis)
function L.legal(p)
	local q = table.clone(p)
	q["cam.MIN_HOLD"] = math.max(q["cam.MIN_HOLD"], q.WINDUP + q.LUNGE_TIME - 0.2)   -- today 1.35 vs 0.5 + 1.0
	if q["cam.CLOSE_OUT"] <= q["cam.CLOSE_IN"] + 0.3 then q["cam.CLOSE_OUT"] = q["cam.CLOSE_IN"] + 0.3 end
	if q["cam.AWAY_OUT"] >= q["cam.AWAY_IN"] - 0.3 then q["cam.AWAY_OUT"] = q["cam.AWAY_IN"] - 0.3 end
	-- the director waits out a strike: a strike episode longer than a lunge cycle
	q["cam.EPISODE"] = math.max(q["cam.EPISODE"], q.WINDUP + q.LUNGE_TIME + 1.5)
	return q
end

function L.apply(p)
	for k, v in p do
		local t, f = slot(k)
		t[f] = v
	end
end

local ORIGINAL = L.read()
function L.restore() L.apply(ORIGINAL) end
L.ORIGINAL = ORIGINAL

-- ============ layer 1: the contract, the two specs as they stand ============
-- chase.spec (the hunter) and chasecam.spec (the edit: a cut needs a cause, no
-- chatter, the tell's shot survives the strike). Both read the same module tables
-- this file mutates (checked 11 Oct: breaking genius.lunge here fails chase.spec).
local SPECS
function L.contract()
	SPECS = SPECS or { require("../tests/offline/chase.spec"), require("../tests/offline/chasecam.spec") }
	local fails = {}
	for _, spec in SPECS do
		for _, c in spec do
			local ok, err = pcall(c.fn)
			if not ok then table.insert(fails, c.name .. ": " .. tostring(err):match("[^\n]*$")) end
		end
	end
	return #fails == 0, fails
end

-- ============ layers 2 and 3 ============
local function Dof(id) return R.bandMid(id) - 40 end
local function opts(id, skill, speed, extra)
	local D = Dof(id)
	local o = { D = D, speed = speed, skill = skill, deadline = 14 + (D + 40) * 0.11 }
	for k, v in extra or {} do o[k] = v end
	return o
end
local function rules(id, speed) return M.newRules(R, R.config(id, false, speed)) end

-- the camera director watching a simulated chase: cuts per second
local function cutsOn(id, skill, speed, n)
	local cuts, secs = 0, 0
	for i = 1, n do
		local st = {}
		local last = 0
		local home = Vector3.new(0, 0, -40)
		local o = opts(id, skill, speed, {
			onFrame = function(t, px, pz, vx, vz, h, ph, dist)
				local pos = Vector3.new(px, 0, pz)
				local trav = Vector3.new(vx, 0, vz)
				local _, _, cut = C.direct(st, {
					t = t, dt = 0.05, dist = dist < math.huge and dist or nil,
					windup = ph == "windup", lunging = ph == "lunge",
					homeDist = (home - pos).Magnitude, speed = trav.Magnitude, carrySpeed = speed,
					pos = pos, travel = trav.Magnitude > 0.1 and trav or nil,
					hunterPos = h and Vector3.new(h.x, 0, h.z) or nil,
				})
				if cut then cuts += 1 end
				if st.snap then cuts += 1; st.snap = nil end
				last = t
			end,
		})
		M.run(R, rules(id, speed), o, 104729 * i + 7)
		secs += last
	end
	return cuts / math.max(secs, 1e-6)
end

L.TARGETS = {
	-- { what, tier, speed, skill, kind, target } ; kind "escape" = at least, "danger" = share at least
	{ "genius @18 steers on the tell", "genius", 18, "dodger", "escape", 0.80 },
	{ "genius @20 steers on the tell", "genius", 20, "dodger", "escape", 0.80 },
	{ "genius @18 boosts on the tell", "genius", 18, "good", "escape", 0.80 },
	{ "genius @20 boosts on the tell", "genius", 20, "good", "escape", 0.80 },
	{ "star @17 steers on the tell", "star", 17, "dodger", "escape", 0.85 },
	{ "star @17 boosts on the tell", "star", 17, "good", "escape", 0.85 },
	{ "genius @18 stays scary (time within 12 studs, good player)", "genius", 18, "good", "danger", 0.30 },
}
L.CUTS_MAX = 0.5
--[[ The doctor's live robot holds W on a genius run and is caught in about 3 s; on
	that run this proxy reads 0.90 cuts/s against the doctor's live 0.66-1.28
	(measured 11 Oct), so it is in the mix. Long chases (good, dodger) read
	0.37-0.46: most of a short run's cuts are the opening shot and the catch. ]]
L.CUT_RUNS = { { "genius", 18, "straight" }, { "genius", 18, "good" }, { "genius", 18, "dodger" }, { "star", 17, "good" } }

-- n: runs per row. Returns score (0 = every target met), and the measured rows
function L.measure(n, cutN)
	local rows, score = {}, 0
	for _, t in L.TARGETS do
		local esc, _, danger = M.rate(R, rules(t[2], t[3]), opts(t[2], t[4], t[3]), n)
		local v = t[5] == "escape" and esc or danger
		local short = math.max(0, t[6] - v) * 100            -- percentage points under target
		score += short * short
		table.insert(rows, { what = t[1], value = v, target = t[6], short = short })
	end
	local cps, nRuns = 0, 0
	for _, c in L.CUT_RUNS do
		cps += cutsOn(c[1], c[3], c[2], cutN or math.max(10, math.floor(n / 10)))
		nRuns += 1
	end
	cps /= nRuns
	local over = math.max(0, cps - L.CUTS_MAX) * 100             -- hundredths of a cut per second over
	score += over * over
	return score, rows, cps
end

-- ============ the search ============
-- a seeded random walk in the box, one to three knobs at a time
function L.rng(seed)
	local s = seed
	return function()
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end
local function gauss(rnd)
	local u, v = math.max(rnd(), 1e-9), rnd()
	return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v)
end
function L.neighbour(p, rnd, temp)
	local q = table.clone(p)
	local k = 1 + math.floor(rnd() * 3)
	for _ = 1, k do
		local d = L.PARAMS[1 + math.floor(rnd() * #L.PARAMS)]
		local span = d.hi - d.lo
		q[d.key] = math.clamp(q[d.key] + gauss(rnd) * span * 0.15 * temp, d.lo, d.hi)
	end
	return L.legal(q)
end

-- the edits a human makes to land a tuning: only what moved, rounded the way the files write them
-- digits: nil = the way the files write them (1 decimal at 5 or more, else 2); a number = that many decimals
function L.diff(from, to, digits)
	local out = {}
	for _, d in L.PARAMS do
		local a, b = from[d.key], to[d.key]
		local k = digits and 10 ^ digits or ((math.abs(b) >= 5) and 10 or 100)
		local r = math.floor(b * k + 0.5) / k
		if math.abs(r - a) > 1e-9 then
			local _, _, file, name = slot(d.key)
			table.insert(out, { key = d.key, file = file, name = name, from = a, to = r })
		end
	end
	return out
end

-- drop every edit that is not pulling its weight: put each knob back alone, and keep
-- it back if the score stays within `slack` (a PR should only touch what matters)
function L.prune(p, measure, slack)
	local q = table.clone(p)
	local score = measure(q)
	for _, d in L.PARAMS do
		if math.abs(q[d.key] - ORIGINAL[d.key]) > 1e-9 then
			local try = table.clone(q)
			try[d.key] = ORIGINAL[d.key]
			try = L.legal(try)
			L.apply(try)
			if L.contract() then
				local s = measure(try)
				if s <= score * (1 + slack) + 1 then q, score = try, math.min(score, s) end
			end
		end
	end
	return q, score
end

function L.rounded(p, digits)
	local q = table.clone(p)
	for _, e in L.diff(ORIGINAL, p, digits) do q[e.key] = e.to end
	for k, v in ORIGINAL do if q[k] == nil then q[k] = v end end
	return q
end

return L
