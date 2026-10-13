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

S.STATS = {
	{ id = "skill", label = "Skill", blurb = "more money", step = 0.065 },
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
local function int(v, lo, hi, default)
	v = tonumber(v)
	if not v or v ~= v then return default end   -- nil, a string, NaN
	return math.clamp(math.floor(v), lo, hi)
end

function S.cap(stage, talent)
	stage = int(stage, 1, 5, 1)
	talent = int(talent, 1, #S.TALENT_BONUS, 1)
	return 2 * stage + S.TALENT_BONUS[talent]
end

function S.canTrain(level, stage, talent)
	return S.clampLevel(level) < S.cap(stage, talent)
end

-- seconds of the added income a level takes to pay back (G2 in the spec: 3..30 min)
function S.payback(level) return 200 + 100 * S.clampLevel(level) end

--[[ the price of the NEXT level, bought at `level`: exactly PAYBACK seconds of the
	income that level adds, for THIS person (so it always pays back in 3.3..28 min,
	G2, whoever they are). v2 (13 Oct, independent review): v1 also had an early
	curve (50 x 1.6^level x run scale); for low earners (an Intern outside their
	room) the curve set the price and a level took 45 min to pay back, failing G2.
	personBaseRate: what that person earns per second UNTRAINED, seated, with every
	multiplier (phase 2 passes the seated rate even for someone in the waiting line). ]]
S.MIN_PRICE = 10
function S.price(level, personBaseRate)
	level = S.clampLevel(level)
	local v = tonumber(personBaseRate) or 0
	if v ~= v or v < 0 then v = 0 end
	return math.max(S.MIN_PRICE, math.floor(v * S.step("skill") * S.payback(level) + 0.5))
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

--[[ what a keeper actually starts the new company with: the carry, clamped to the
	new company's cap (the fallback declared before the simulator ran, G4: carried
	unclamped, five max-loyal Genius keepers made the next run's first stage 2x
	faster). Training above the cap is still never possible; this stops it
	arriving that way too. ]]
function S.carried(level, loyalty, newStage, talent)
	return math.min(S.carry(level, loyalty), S.cap(newStage, talent))
end

-- the room types a person can be pinned to (Wafers departments, and the garage bench)
S.PINS = { hq = true, lobby = true, eng = true, studio = true, cafe = true, labs = true }
function S.validPin(p) return type(p) == "string" and (p == "" or S.PINS[p] == true) end

--[[ ids after a load: keep each saved id that is a positive whole number not already
	taken; give everyone else a fresh one past the highest of (the saved counter, every
	kept id). Returns ids (1..n) and the new counter. Pure, so the tampered-save cases
	are tested offline (v1 did this inline in SaveLoad and needed a live fix: the
	counter grew by the staff count on every join). Loading its own output again gives
	the same ids and the same counter. ]]
function S.fixIds(saved, nsid, n)
	saved = type(saved) == "table" and saved or {}
	local top = int(nsid, 0, 1e9, 0)
	local out, seen = {}, {}
	for i = 1, n do
		local v = tonumber(saved[i])
		if v and v == v and v > 0 and v <= 1e9 and v == math.floor(v) and not seen[v] then
			out[i] = v
			seen[v] = true
			if v > top then top = v end
		end
	end
	for i = 1, n do
		if not out[i] then top += 1; out[i] = top end
	end
	return out, top
end

return S
