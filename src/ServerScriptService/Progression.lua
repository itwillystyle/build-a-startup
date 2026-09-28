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

-- ---------------------------------------------------------------- apartments
-- gateHQ: the HQ level you can't build without owning this apartment
P.APARTMENTS = {
	{ id = 1, key = "studio", name = "STUDIO", price = 20000, minHQ = 2, gateHQ = 3, bonus = 0.10,
	  blurb = "A place of your own. Floor-to-ceiling windows." },
	{ id = 2, key = "loft", name = "LOFT", price = 150000, minHQ = 3, gateHQ = 4, bonus = 0.10,
	  blurb = "Room to host: a kitchen island, a real bedroom." },
	{ id = 3, key = "penthouse", name = "PENTHOUSE", price = 2000000, minHQ = 4, gateHQ = 5, bonus = 0.10,
	  blurb = "The top of the tower. An indoor pool. A view of your valley." },
}

-- the apartment you must own before building HQ `level` (0 = none)
function P.aptNeeded(level)
	for _, t in ipairs(P.APARTMENTS) do
		if t.gateHQ == level then return t.id end
	end
	return 0
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

-- your next two steps: each HQ level with the apartment it needs, then the spin-off, then HQ 2
function P.ladder(level, apt, hqCost, spinCost)
	local steps = {}
	local l, a = level or 1, apt or 0
	while #steps < 2 do
		if l >= 5 then
			table.insert(steps, spinCost)
			l = 1                        -- a spin-off: the garage again (the apartment stays yours)
		else
			local c = hqCost(l + 1) or 0
			local need = P.aptNeeded(l + 1)
			if need > 0 and a < need then
				c += P.APARTMENTS[need].price
				a = need
			end
			table.insert(steps, c)
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
