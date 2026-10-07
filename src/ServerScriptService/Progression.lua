--[[ Progression: the late-game economy, as pure functions (v4.3).

No services, no requires, no Instances: tests/offline runs this file in Lune
(outside Studio, about a second) and tools/late_game.luau prints the loop table
from the SAME code the game runs, so the numbers can't drift.

THE WALL (found in v4.2): a spin-off cost 4M x 2.5^n but only added +0.5x revenue,
so the price outran the income that pays it. The wait at HQ 5 for the next
spin-off went 4 min, 7, 13, 25, 52, 112 min, 4 h, 9 h, 20 h (spin-offs 0-8).

THE FIX: the price follows the income that pays it. A spin-off costs
	base x spinMult(n) x min(STRETCH^n, STRETCH_MAX)
spinMult(n) is the revenue multiplier the player already has, so it cancels out
of the wait, and what is left is the stretch: each spin-off's wait is 1.3x the
last, until it reaches 30x the first (4 min -> 2 h). 2 h of income is exactly what
one night in a Penthouse pays (8 h away x 25%), so a veteran who owns one can
still spin off once a day. Spin-off 0 costs the same 4M as before: the first
hour, which the bot and the sims were tuned on, does not change. ]]

local P = {}

-- ---------------------------------------------------------------- spin-offs
P.SPIN_STEP = 0.5            -- +0.5x revenue per spin-off (x1.5, x2.0, x2.5 ... on the HUD)
P.SPIN_CAP = 20              -- spin-offs past this add no more revenue (x11 max)
P.SPIN_STRETCH = 1.3         -- each spin-off's wait at HQ 5 is 1.3x the previous one ...
P.SPIN_STRETCH_MAX = 30      -- ... until it is 30x the first, then it stops growing

local function spins(n)
	return math.clamp(math.floor(tonumber(n) or 0), 0, P.SPIN_CAP)
end

-- the permanent revenue multiplier after n spin-offs
function P.spinMult(n)
	return 1 + P.SPIN_STEP * spins(n)
end

-- the price of the next spin-off when you have done n (base = RoomEconomy.SPINOFF_BASE)
function P.spinCost(n, base)
	local k = spins(n)
	return math.floor(base * P.spinMult(k) * math.min(P.SPIN_STRETCH ^ k, P.SPIN_STRETCH_MAX))
end

-- ---------------------------------------------------------------- the economy clock
--[[ v4.5 THE ECONOMY CLOCK (docs/superpowers/specs/2026-09-29-economy-clock-design.md,
sim/clock_sim.py). Prices were fixed ladders while a spin-off multiplied income
(the spin-off bonus, the homes, kept rare hires, the Index, milestones): company 3
reached HQ 5 in 6 minutes, one investor offer could pay the whole next goal, and
day 7's reward was 3x the spin-off price.

ONE NUMBER PER COMPANY scales every price inside it (hires, recruits, rooms, room
levels, HQ upgrades, decor): the spin-off price's own scale, x1.3 from company 2 on
for the +30% the three homes pay forever (they are bought once, in company 1).
Company 1 is x1: the first hour does not change. The spin-off price, homes and cars
are NOT scaled (the spin-off IS the clock; homes and cars are one ladder for life).

EVERY WINDFALL is capped at a share of the next goal (the next HQ, or the spin-off
at HQ 5), and a capped amount rounds down to a clean number. ]]
P.RUN_HOMES = 1.3
P.CAPS = { phone = 0.12, push = 0.18, series = 0.25, seriesPush = 0.35, launch = 0.25, gopublic = 0.10 }
P.DAILY_SHARE = { 0.05, 0.08, 0.12, 0.16, 0.20, 0.25, 0.35 }   -- streak day 1..7

-- the price scale of company n+1 (n = spin-offs done so far)
function P.runScale(n)
	local k = spins(n)
	if k == 0 then return 1 end
	return P.spinMult(k) * math.min(P.SPIN_STRETCH ^ k, P.SPIN_STRETCH_MAX) * P.RUN_HOMES
end

-- a base price in company n+1, in whole dollars
function P.scaled(price, n)
	return math.floor((price or 0) * P.runScale(n))
end

-- round DOWN to two significant figures (11,407 -> 11,000; 987 -> 980)
function P.niceDown(v)
	v = math.floor(math.max(0, v or 0))
	local digits = #tostring(v)
	if digits <= 2 then return v end
	local mag = 10 ^ (digits - 2)
	return math.floor(v / mag) * mag
end

-- what you are saving for: the next HQ level (scaled), or the spin-off at HQ 5
-- hqCosts = the base ladder { [1] = 0, [2] = 3750, ... }
function P.nextGoal(level, n, hqCosts, spinCost)
	local c = hqCosts[(level or 1) + 1]
	if c then return P.scaled(c, n) end
	return spinCost
end

-- a windfall of `kind` (P.CAPS key, or "daily" with its streak day) against the next goal
function P.capWindfall(kind, amount, nextGoal, day)
	amount = math.floor(math.max(0, amount or 0))
	local share
	if kind == "daily" then
		share = P.DAILY_SHARE[math.clamp(math.floor(day or 1), 1, #P.DAILY_SHARE)]
	else
		share = P.CAPS[kind]
	end
	if not share or not nextGoal or nextGoal <= 0 then return amount end
	local cap = math.floor(nextGoal * share)
	if amount <= cap then return amount end
	return P.niceDown(cap)
end

-- ---------------------------------------------------------------- apartments
P.APARTMENTS = {
	{ id = 1, key = "studio", name = "STUDIO", minHQ = 2,
	  blurb = "A place of your own. Floor-to-ceiling windows." },
	{ id = 2, key = "loft", name = "LOFT", minHQ = 3,
	  blurb = "Room to host: a kitchen island, a real bedroom." },
	{ id = 3, key = "penthouse", name = "PENTHOUSE", minHQ = 4,
	  blurb = "The top of the tower. An indoor pool. A view of your valley." },
}


--[[ HOW MANY OF YOUR PEOPLE SURVIVE A SPIN-OFF.

	This is what a home is for. Before this it paid +10% money, which against a
	rate already multiplied by HQ level, room levels, talent, set bonuses,
	milestones, prestige and market share was invisible -- the player's own
	verdict was "whatever that number even means".

	Now the home is capacity at the one moment the loss is felt. Eligibility is
	still KEEP_TALENT (Star and above); the home decides how many of them fit. ]]
P.KEEP_SLOTS = { [0] = 0, 1, 3, 5 }

function P.keepSlots(apt)
	local n = math.floor(tonumber(apt) or 0)
	return P.KEEP_SLOTS[math.clamp(n, 0, #P.KEEP_SLOTS)] or 0
end

--[[ WHO FILLS THOSE SLOTS.

	`rigs` is the session's staff list (entries carry `.talent`). Two rules the
	selection depends on, both learned from how this could go wrong:

	1. Ranking is a TOTAL order (talent, then list position). table.sort is not
	   stable, so a comparator that only looks at talent can order equal-talent
	   staff differently on the card than at confirm time.
	2. A pick is an ENTRY, not a position. The confirm card stays armed for 30 s
	   and s.rigs can change under it (a poach sale, a hire), so "slot 4" can be a
	   different person by then. The card hands out opaque ids bound to the entry
	   tables themselves; at confirm each id is re-resolved against the CURRENT
	   rigs and dropped if that entry is gone or no longer eligible. ]]
function P.rankKeepers(rigs, minTalent)
	local ranked = {}
	for i, r in ipairs(rigs or {}) do
		if (r.talent or 1) >= minTalent then
			table.insert(ranked, { entry = r, index = i, talent = r.talent or 1 })
		end
	end
	table.sort(ranked, function(a, b)
		if a.talent ~= b.talent then return a.talent > b.talent end
		return a.index < b.index
	end)
	return ranked
end

-- offer = { byId = { [id] = entry } }; ids = what the client sent (untrusted).
-- Returns the entries that survive, and whether the player's own selection was
-- honoured. With no valid selection it is the best `slots`; never a re-sort of
-- an explicit choice.
function P.chooseKeepers(rigs, minTalent, slots, offer, ids)
	local ranked = P.rankKeepers(rigs, minTalent)
	if slots <= 0 then return {}, false end
	if type(ids) == "table" and offer and type(offer.byId) == "table" then
		local pos = {}
		for _, k in ipairs(ranked) do pos[k.entry] = k end
		local chosen, seen = {}, {}
		for _, id in ipairs(ids) do
			local entry = type(id) == "number" and offer.byId[id] or nil
			local k = entry and pos[entry]           -- still in the rigs AND still eligible
			if k and not seen[entry] then
				seen[entry] = true
				table.insert(chosen, k)
				if #chosen >= slots then break end
			end
		end
		if #chosen > 0 then
			table.sort(chosen, function(a, b)       -- seat order only; membership is already decided
				if a.talent ~= b.talent then return a.talent > b.talent end
				return a.index < b.index
			end)
			local out = {}
			for _, k in ipairs(chosen) do table.insert(out, k.entry) end
			return out, true
		end
	end
	local out = {}
	for i = 1, math.min(slots, #ranked) do out[i] = ranked[i].entry end
	return out, false
end

--[[ A HOME COSTS A SHARE OF THE SPIN-OFF IT COMPETES WITH.

	Not a fixed sum, and this is forced by measurement rather than taste. A real
	player reached ~$3M in about 20 minutes, matching the recorded bot run
	(GO PUBLIC ~23.9 min, spin-off $4M at ~26 min). Against that curve the
	authored prices -- $20K / $150K / $2M -- are 0.5% / 3.8% / 50% of a
	spin-off, so every home was affordable before a player could spin off at
	all, and slots keyed to the home would have differentiated nobody.

	As a share the decision survives the curve: the penthouse costs 60% of a
	spin-off, so five slots visibly delay the restart you are saving for, while
	the loft keeps today's three for a sixth of that. The studio is trivial on
	purpose -- it is insurance, not a decision. ]]
P.HOME_SHARE = { 0.01, 0.15, 0.60 }

function P.homePrice(tierId, spinCost)
	local share = P.HOME_SHARE[math.floor(tonumber(tierId) or 0)]
	if not share then return 0 end
	return P.niceDown(math.max(1, (tonumber(spinCost) or 0) * share))
end

-- ---------------------------------------------------------------- coming back
--[[ v4.2 HOME TURF: your apartment decides how much of the wait for your next
step one return covers (sim/offline_sim2/3.py):
	offline = min( rate x 0.25 x min(away, WINDOW[apt]),     the time your home covers
	               max(10 min of income, your next step),     never below the old cap; up to one step
	               next + the step after - cash - 1 )          never two steps in one return ]]
P.WINDOW = { [0] = 40 * 60, 2 * 3600, 4 * 3600, 8 * 3600 }
P.OFFLINE_RATE = 0.25
P.OFFLINE_FLOOR = 600        -- seconds of full income: the old cap, now the floor

--[[ Your next two steps: each HQ level, then the spin-off, then HQ 2.

	`apt` is still taken so no caller needs an edit, and is deliberately unused:
	homes stopped gating HQ levels, so the step to the next level is its price
	and nothing else. ]]
function P.ladder(level, _apt, hqCost, spinCost)
	local steps = {}
	local l = level or 1
	while #steps < 2 do
		if l >= 5 then
			table.insert(steps, spinCost)
			l = 1                        -- a spin-off: the garage again (the home stays yours)
		else
			table.insert(steps, hqCost(l + 1) or 0)
			l += 1
		end
	end
	return steps[1], steps[2]
end

function P.offline(rate, away, apt, cash, nextStep, stepAfter)
	rate = math.max(0, rate or 0)
	local window = P.WINDOW[math.clamp(math.floor(apt or 0), 0, 3)]
	local raw = rate * P.OFFLINE_RATE * math.min(math.max(0, away or 0), window)
	local top = math.max(rate * P.OFFLINE_FLOOR, nextStep or 0)
	local never2 = math.max(0, (nextStep or 0) + (stepAfter or 0) - (cash or 0) - 1)
	return math.floor(math.max(0, math.min(raw, top, never2)))
end

return P
