--[[ StaffStats (13 Oct 2026): Manage Staff's rules, in one place.

	Spec: docs/superpowers/specs/2026-10-13-manage-staff-design.md. Three stats a
	player raises with cash: Skill (that person's income), Speed (their product
	work), Loyalty (how much of their training follows them into a spin-off). How
	high a stat may go depends on the HQ stage and the person's talent, so growing
	the company unlocks training and rare talent matters beyond its multiplier.

	Adding a stat: one row in STATS, its test in tests/offline/staffstats.spec, and
	the one place its effect is applied. The simulator (tools/staff_sim) must still
	pass its four gates. Pure: shared by server, client and the Lune tests. ]]
local S = {}

S.MAX_LEVEL = 30                          -- a save cannot claim more (clampLevel)
S.TALENT_BONUS = { 0, 0, 1, 3, 5 }        -- Regular, Skilled, Star, Genius, Unicorn
S.BASE, S.GROWTH = 50, 1.6                -- the early-game price (before income catches up)

S.STATS = {
	{ id = "skill", label = "Skill", blurb = "more money", step = 0.10 },
	{ id = "speed", label = "Speed", blurb = "ships apps faster", step = 0.10 },
	{ id = "loyalty", label = "Loyalty", blurb = "keeps their training when they follow you", step = 0.10 },
}

local BY = {}
for _, st in S.STATS do BY[st.id] = st end

function S.step(id) return BY[id] and BY[id].step or 0 end

function S.clampLevel(v)
	v = tonumber(v)
	if not v or v ~= v then return 0 end
	return math.clamp(math.floor(v), 0, S.MAX_LEVEL)
end

-- how high a stat may be trained at this HQ stage (1..5) for this talent (1..5)
function S.cap(stage, talent)
	stage = math.clamp(math.floor(tonumber(stage) or 1), 1, 5)
	talent = math.clamp(math.floor(tonumber(talent) or 1), 1, #S.TALENT_BONUS)
	return 2 * stage + S.TALENT_BONUS[talent]
end

function S.canTrain(level, stage, talent)
	return S.clampLevel(level) < S.cap(stage, talent)
end

-- seconds of the added income a level takes to pay back (G2 in the spec: 3..30 min)
function S.payback(level) return 200 + 100 * S.clampLevel(level) end

--[[ the price of the NEXT level, bought at `level`. Early in a run the BASE curve
	sets it; once the person earns, their own untrained rate does: the floor is
	"PAYBACK seconds of what this level adds", so training is never trivially cheap.
	personBaseRate: that person's untrained income per second (with every
	multiplier); spinScale: Progression.runScale(spinoffs). ]]
function S.price(level, personBaseRate, spinScale)
	level = S.clampLevel(level)
	local curve = S.BASE * S.GROWTH ^ level * (spinScale or 1)
	local floor = (personBaseRate or 0) * S.step("skill") * S.payback(level)
	return math.floor(math.max(curve, floor) + 0.5)
end

-- the multiplier a stat's level gives its effect (Loyalty has no running effect)
function S.mult(id, level)
	if id == "loyalty" then return 1 end
	return 1 + S.step(id) * S.clampLevel(level)
end

-- trained levels a keeper keeps at a spin-off
function S.carry(level, loyalty)
	local share = math.min(1, S.step("loyalty") * S.clampLevel(loyalty))
	return math.floor(S.clampLevel(level) * share + 1e-9)
end

return S
