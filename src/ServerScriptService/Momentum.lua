--[[
	Momentum -- what you bring back from outside (v5.0).

	THE PROBLEM THIS IS FOR.

	The game has two halves that never touched each other. Idle income builds
	the tower; the recruit run down the street is the only thing that leaves
	the base and it is the best part of the game. They ran in PARALLEL --
	neither multiplied the other -- so the arithmetic said ignore one of them,
	and standing on the pad tapping WRITE CODE was never worse than going out.

	Every tycoon that retains makes the active verb and the idle number
	multiply. This is the smallest honest version of that: a stock you can
	only earn OUTSIDE, spent on the one thing you care about INSIDE.

	WHY A DISCOUNT AND NOT A GATE. The first draft made momentum a
	requirement: no points, no build. That is a strictly worse game. It
	punishes the player who cannot find a candidate, it turns a dead restock
	timer into a wall, and it makes a bad session feel like a bug. A discount
	takes nothing away from anyone -- the player who never leaves the garage
	progresses exactly as fast as they did before this file existed, and the
	player who runs the street gets there sooner. Carrot, not stick.

	WHY IT IS SPENT RATHER THAN HELD. If points were a permanent multiplier
	they would be a stat, and a stat you can only go up is something you stop
	thinking about by minute ten. Spending them makes the loop a cycle: go
	out, come back, build cheap, go out. The decision "do I build now at 12%
	off, or run one more recruit and build at 36%" is the whole point, and it
	only exists because the stock is consumed.

	Pure: no services, no instances. tests/offline/momentum.spec.luau runs it
	without Studio.
]]

local Momentum = {}

Momentum.MAX = 24                -- the stock ceiling
Momentum.SPEND_CAP = 12          -- the most one build may consume
Momentum.PER_POINT = 0.03        -- discount per point spent

--[[ What each trip home is worth. Rarer candidates pay more because they are
	harder to get home: the headhunter chases the higher tiers and does not
	bother with a walk-in. VIP pays most because it is the only one with a
	hard timer on it. ]]
Momentum.AWARD = {
	walkin = 1,
	skilled = 2,
	star = 3,
	genius = 5,
	unicorn = 8,
	vip = 6,
	launch = 2,
}

function Momentum.award(kind)
	return Momentum.AWARD[kind] or 0
end

function Momentum.add(points, kind)
	local v = (points or 0) + Momentum.award(kind)
	return math.clamp(v, 0, Momentum.MAX)
end

-- how many points one build consumes out of the stock
function Momentum.spend(points)
	return math.clamp(math.floor(points or 0), 0, Momentum.SPEND_CAP)
end

-- the fraction off the next build, 0 .. 0.36
function Momentum.discount(points)
	return Momentum.spend(points) * Momentum.PER_POINT
end

-- the price after the discount this stock would buy
function Momentum.priceAfter(price, points)
	return math.floor((price or 0) * (1 - Momentum.discount(points)) + 0.5)
end

--[[ What one build tap actually charges and consumes. A rebuild (a level the
	company already reached before a spin-off) is priced at a sliver of the
	real thing, so spending the stock on it would burn the whole bank for a
	few dollars. Rebuilds keep the stock for the next new level. ]]
function Momentum.quote(price, points, rebuild)
	if rebuild then return math.floor(price or 0), 0 end
	return Momentum.priceAfter(price, points), Momentum.spend(points)
end

-- a short line for the HUD: "MOMENTUM 7  ·  next build 21% off"
function Momentum.label(points)
	local d = Momentum.discount(points)
	if d <= 0 then return "MOMENTUM 0" end
	return ("MOMENTUM %d  ·  next build %d%% off"):format(math.floor(points or 0), math.floor(d * 100 + 0.5))
end

-- clamp whatever a save hands back, the same doctrine as every other saved number
function Momentum.sanitize(v)
	if type(v) ~= "number" or v ~= v then return 0 end
	return math.clamp(math.floor(v), 0, Momentum.MAX)
end

return Momentum
