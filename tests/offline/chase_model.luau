--[[ A human-like player carrying a recruit home. Shared by chase.spec.luau and
tools/chase_sim.luau; the hunter logic is passed in (`M.newRules(R, cfg)` wraps
ChaseRules, the code TalentDrop runs; `M.oldRules` is the v4.2 hunter, kept
only as the baseline the fix is measured against).

Route: from the candidate west along the road D studs, then a 40-stud turn into
your lot (where the carry counts as home). Every player starts moving 0.4-0.7 s
after the pickup and weaves a little (95-96% of top speed). The profiles below
are behaviours, not guesses at a population: novice (never boosts), good
(boosts on 75% of tells), hesitant (freezes once for 1.5 s), idle (3 s).
Hunter 1 starts START_BEHIND studs behind; hunter 2 joins after SECOND_DELAY
from SECOND_SIDE studs across the road. ]]
local M = {}

M.PROFILES = {
	-- holds forward the whole way, never touches BOOST (a new player)
	novice = { weave = 0.95, stopRate = 0, stopTime = 0, boostChance = 0, react = { 1, 1 } },
	-- BOOSTs on most tells (75%, 0.15-0.35 s after the crouch starts)
	good = { weave = 0.96, stopRate = 0, stopTime = 0, boostChance = 0.75, react = { 0.15, 0.35 } },
	-- a novice who freezes once for 1.5 s, somewhere 4-10 s into the run
	hesitant = { weave = 0.95, stopRate = 0, stopTime = 0, boostChance = 0, react = { 1, 1 }, standAt = "rand", standFor = 1.5 },
	-- stands still for 3 s, 6 s in
	idle = { weave = 0.96, stopRate = 0, stopTime = 0, boostChance = 0.75, react = { 0.15, 0.35 }, standAt = 6, standFor = 3 },
	--[[ 8 Oct, the three he described ("go in a straight line ... spam the shift"). The
		profiles above all weave at 95% speed, which is why the simulator never saw a
		perfect W-holder outrun the genius. ]]
	-- holds W perfectly: full speed, no weave, never boosts
	straight = { weave = 1, perfect = true, stopRate = 0, stopTime = 0, boostChance = 0, react = { 1, 1 } },
	-- holds W perfectly and presses BOOST every time it is ready, tell or not
	spammer = { weave = 1, perfect = true, stopRate = 0, stopTime = 0, boostChance = 0, react = { 1, 1 }, spam = true },
	-- steers hard on most tells (75%, 0.15-0.35 s after the crouch), never boosts
	dodger = { weave = 0.96, stopRate = 0, stopTime = 0, boostChance = 0, react = { 0.15, 0.35 }, dodgeChance = 0.75 },
	-- reads a tell (75% / 95%): BOOST if it is ready, otherwise a hard turn (v4.4's skill)
	reader = { weave = 0.96, stopRate = 0, stopTime = 0, boostChance = 0, react = { 0.15, 0.35 }, readChance = 0.75 },
	ace = { weave = 0.97, stopRate = 0, stopTime = 0, boostChance = 0, react = { 0.12, 0.28 }, readChance = 0.95 },
}
M.DODGE_ANGLE = math.rad(55)   -- a hard turn off the line
M.DODGE_TIME = 0.6

function M.newRules(R, cfg)
	-- home is where the route ends (see M.run): the lot, 40 studs off the road
	cfg.homeDist = function(x, z) return math.sqrt(x * x + (z + 40) ^ 2) end
	return {
		hunters = cfg.hunters or 1,
		start = R.START_BEHIND, secondDelay = R.SECOND_DELAY, secondSide = R.SECOND_SIDE,
		spawn = function(x, z, t, stagger, second) return R.newHunter(x, z, t, stagger, second) end,
		step = function(h, px, pz, vx, vz, ps, dt, t) return R.step(cfg, h, px, pz, vx, vz, ps, dt, t) end,
	}
end

-- the v4.2 hunter: pure pursuit, a dash every 5 s (0.4 s crouch, 1.2 s dash), alone, 30 back
function M.oldRules(walk, dash)
	return {
		hunters = 1, start = 30, secondDelay = math.huge, secondSide = 0,
		spawn = function(x, z) return { x = x, z = z } end,
		step = function(h, px, pz, _, _, _, dt, t)
			local cyc = t % 5
			local ph = (cyc >= 3.8) and "lunge" or ((cyc >= 3.4) and "windup" or "chase")
			local sp = ph == "lunge" and dash or (ph == "windup" and 0 or walk)
			local dx, dz = px - h.x, pz - h.z
			local d = math.sqrt(dx * dx + dz * dz)
			if d > 1e-6 and sp > 0 then
				local mv = math.min(sp * dt, math.max(0, d - 2.25))
				h.x, h.z = h.x + dx / d * mv, h.z + dz / d * mv
			end
			return ph, d
		end,
	}
end

-- returns escaped (bool), time, closeCalls
function M.run(R, rules, opts, seed)
	local st = seed
	local function rnd()
		st = (st * 1103515245 + 12345) % 2147483648
		return st / 2147483648
	end
	local prof = M.PROFILES[opts.skill or "good"]
	local D = opts.D
	local route = { { D, 0 }, { 0, 0 }, { 0, -40 } }
	local px, pz = D, 0
	local seg = 2
	local dt = 0.05
	local startDelay = 0.4 + rnd() * 0.3
	local standAt = prof.standAt == "rand" and (4 + rnd() * 6) or prof.standAt
	local stopUntil = -1
	local lastBoost, pendingBoostAt = nil, nil
	local pendingDodgeAt, dodgeUntil, dodgeSign = nil, -1, 1
	local hunters = { { h = rules.spawn(D + rules.start + (rnd() - 0.5) * 8, 0, 0, 0), active = true, last = "chase" } }
	local jitter, jitterAt = 1, 0
	local danger = 0
	if rules.hunters >= 2 then table.insert(hunters, { active = false, last = "chase" }) end
	local near, closeCalls = false, 0
	local deadline = opts.deadline or math.huge
	local t = 0
	while t < deadline do
		local vx, vz = 0, 0
		local moving = t >= startDelay and t >= stopUntil
		if standAt and t >= standAt and t < standAt + prof.standFor then moving = false end
		if moving and prof.stopRate > 0 and rnd() < prof.stopRate * dt then
			stopUntil = t + prof.stopTime
			moving = false
		end
		if prof.spam and R.boostReady(lastBoost, t) and t >= startDelay then lastBoost = t end
		if pendingDodgeAt and t >= pendingDodgeAt then
			dodgeUntil, dodgeSign, pendingDodgeAt = t + M.DODGE_TIME, (rnd() < 0.5) and -1 or 1, nil
		end
		if pendingBoostAt and t >= pendingBoostAt then
			if R.boostReady(lastBoost, t) then lastBoost = t end
			pendingBoostAt = nil
		end
		if moving then
			local tx, tz = route[seg][1], route[seg][2]
			local dx, dz = tx - px, tz - pz
			local dl = math.sqrt(dx * dx + dz * dz)
			if t >= jitterAt then jitter, jitterAt = 0.97 + rnd() * 0.06, t + 1 end   -- steering is never perfect
			if prof.perfect then jitter = 1 end
			local sp = opts.speed * prof.weave * jitter + R.boostAdd(lastBoost, t)
			if t < dodgeUntil and dl > sp * dt then
				-- the dodge: a hard turn off the line, then the route pulls you back
				local a = M.DODGE_ANGLE * dodgeSign
				local c, s2 = math.cos(a), math.sin(a)
				dx, dz = dx * c - dz * s2, dx * s2 + dz * c
			end
			if dl <= sp * dt then
				px, pz = tx, tz
				if seg == #route then return true, t, closeCalls, danger / math.max(t, 1e-6) end
				seg += 1
			else
				vx, vz = dx / dl * sp, dz / dl * sp
				px, pz = px + vx * dt, pz + vz * dt
			end
		end
		local minDist = math.huge
		for i, H in hunters do
			if not H.active and i == 2 and t >= rules.secondDelay then
				H.active = true
				H.h = rules.spawn(px, pz + rules.secondSide, t, 1.6, true)
			end
			if H.active then
				local ph, dist = rules.step(H.h, px, pz, vx, vz, opts.speed, dt, t)
				if dist <= R.CATCH then return false, t, closeCalls, danger / math.max(t, 1e-6) end
				minDist = math.min(minDist, dist)
				if ph == "windup" and H.last ~= "windup" and dist < 20 and not pendingBoostAt and rnd() < prof.boostChance then
					pendingBoostAt = t + prof.react[1] + rnd() * (prof.react[2] - prof.react[1])
				end
				if ph == "windup" and H.last ~= "windup" and dist < 20 and not pendingDodgeAt and rnd() < (prof.dodgeChance or 0) then
					pendingDodgeAt = t + prof.react[1] + rnd() * (prof.react[2] - prof.react[1])
				end
				if ph == "windup" and H.last ~= "windup" and dist < 20 and not pendingDodgeAt and not pendingBoostAt
					and rnd() < (prof.readChance or 0) then
					local at = t + prof.react[1] + rnd() * (prof.react[2] - prof.react[1])
					if R.boostReady(lastBoost, at) then pendingBoostAt = at else pendingDodgeAt = at end
				end
				H.last = ph
			end
		end
		if minDist < M.DANGER then danger += dt end
		if minDist < R.NEAR then near = true
		elseif near and minDist > R.NEAR * 1.8 then near = false; closeCalls += 1 end
		t += dt
	end
	return false, t, closeCalls, danger / math.max(t, 1e-6)
end

-- escape rate and close calls per run, over n seeded runs
M.DANGER = 12   -- studs: "it's right behind me"

-- escape rate, close calls per run, and the share of the run spent in danger
function M.rate(R, rules, opts, n)
	local ok, calls, dang = 0, 0, 0
	for i = 1, n do
		local e, _, c, d = M.run(R, rules, opts, 7919 * i + 13)
		if e then ok += 1 end
		calls += c
		dang += d or 0
	end
	return ok / n, calls / n, dang / n
end

return M
