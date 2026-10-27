# Manage Staff, Phase 1 (Data) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every staff member gets a permanent id and three saved stats (Skill, Speed, Loyalty) that already change income and product speed, with caps and prices proven safe by a simulator; no UI yet (stats are 0 until Phase 2 adds TRAIN).

**Architecture:** One pure shared module `StaffStats` holds every rule (stats table, cap, price, effect, carry). SiliconCore applies two multipliers (income, work) and stamps ids; SaveLoad persists four new parallel arrays. A Lune simulator built on the game's own modules (WaferPlan, CoreConfig, StaffStats) checks the four balance gates declared in the spec before anything ships.

**Tech Stack:** Luau (Roblox), Rojo, Lune offline tests (`lune run tests/offline/run`), selene, the `bas` CLI.

**Spec:** `silicon-startup/docs/superpowers/specs/2026-10-13-manage-staff-design.md` (§3, §4, §6, §8 phase 1).

## Global Constraints

- Stats: `skill`, `speed`, `loyalty`; integer levels, `0` for everyone until Phase 2.
- `cap(stage, talent) = 2 * stage + TALENT_BONUS[talent]`, `TALENT_BONUS = {0, 0, 1, 3, 5}`; stage 1..5 from wafer level thresholds 5/9/13/18.
- Price = `max(BASE * GROWTH ^ level * Prog.runScale(spinoffs), personBaseRate * STEP * PAYBACK(level))`, `PAYBACK(level) = 200 + 100 * level` seconds. `personBaseRate` = that person's UNTRAINED income per second (changed from the spec's company rate: with a whole-company floor a 14-person team paid back in ~47 min, failing G2; the spec is amended in Task 5).
- Effects: income `x (1 + SKILL_STEP * skill)`; work `x (1 + SPEED_STEP * speed)`. Starting steps 0.10; the simulator (Task 4) sets final values.
- Save: new arrays `ids`, `skill`, `speed`, `loyalty`, `pin` beside `tiers`/`talents`/`people`; missing arrays load as 0 / ""; stat levels clamped to 0..30 on load.
- Balance gates (spec §6.2), declared before results: G1 trained/untrained income at each stage <= 2.0; G2 every Skill purchase pays back in 3..30 min; G3 time to the next stage with greedy training >= 70% of untrained; G4 next run's time to stage 2 with 5 max-trained, max-loyal keepers >= 60% of the same keepers untrained. **If a value set fails, keep the previous values.** If G4 fails at every tried LOYALTY setting, the fallback rule (declared now) is: carried levels are clamped to the new run's cap.
- Code style: match the files (tabs, `--[[ ]]` version notes with dates, plain-English comments). Code delivered as files, never pasted.
- Every PR: CI `check` + required `smoke`, map check clean, and `bas checkup pr` (the doctor gate) before merge. No auto-merge (it changes the economy).

## Review Focus

1. An old save with no `ids`/`skill` arrays: everyone loads with stats 0 and fresh unique ids (Task 2 test via savecontract + a live load).
2. A tampered save (`skill = 999`, `ids` duplicated or negative): clamped to 30, duplicate/invalid ids re-assigned (Task 2).
3. Stats 0 everywhere: income and product speed identical to today, to the cent (Task 3 live check).
4. A spin-off: kept people get NEW ids (no collision with the old run's ids) and stats 0 in Phase 1 (Task 2; the Loyalty carry is Phase 2).
5. A stage that drops after a spin-off (cap lower than a level): `cap` never returns below 0 and `StaffStats.canTrain` refuses, the level is kept (Task 1 test).

---

### Task 1: StaffStats, the rules in one pure module

**Files:**
- Create: `src/ReplicatedStorage/StaffStats.lua`
- Modify: `src/ServerScriptService/WaferPlan.lua` (add `W.STAGE_AT`, `W.stage`)
- Modify: `src/ServerScriptService/Wafers.lua:166-170` (`Wafers.stage` delegates to `P.stage`)
- Test: `tests/offline/staffstats.spec.luau`

**Interfaces:**
- Produces: `StaffStats.STATS` (array of `{ id, label, blurb, step }`), `StaffStats.TALENT_BONUS`, `StaffStats.MAX_LEVEL = 30`, `StaffStats.cap(stage, talent) -> int`, `StaffStats.canTrain(level, stage, talent) -> bool`, `StaffStats.price(level, personBaseRate, spinScale) -> int`, `StaffStats.mult(statId, level) -> number`, `StaffStats.carry(level, loyalty) -> int`, `StaffStats.clampLevel(v) -> int`. `WaferPlan.stage(level) -> 1..5`.

- [ ] **Step 1: Write the failing test** `tests/offline/staffstats.spec.luau`

```lua
-- staffstats.spec.luau: Manage Staff's rules (13 Oct 2026). Every row of STATS must be
-- covered here, so adding a stat without a test fails.
local S = require("../../src/ReplicatedStorage/StaffStats")
local W = require("../../src/ServerScriptService/WaferPlan")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

test("every stat in STATS is one this spec knows (add a stat, add its test)", function()
	local known = { skill = true, speed = true, loyalty = true }
	for _, st in S.STATS do assert(known[st.id], "untested stat: " .. tostring(st.id)) end
	assert(#S.STATS == 3, "three stats")
end)

test("stage follows the wafer levels 5 / 9 / 13 / 18", function()
	local want = { [1] = 1, [4] = 1, [5] = 2, [8] = 2, [9] = 3, [13] = 4, [17] = 4, [18] = 5, [100] = 5 }
	for lv, st in want do assert(W.stage(lv) == st, ("level %d -> stage %d, got %d"):format(lv, st, W.stage(lv))) end
end)

test("cap = 2 x stage + the talent bonus", function()
	assert(S.cap(1, 1) == 2, "Regular at stage 1")
	assert(S.cap(5, 4) == 13, "Genius at stage 5")
	assert(S.cap(5, 5) == 15, "Unicorn at stage 5")
	assert(S.cap(3, 3) == 7, "Star at stage 3")
	assert(S.cap(0, 1) >= 0 and S.cap(nil, nil) == 2, "bad input is safe")
end)

test("canTrain refuses at or above the cap and keeps nothing above MAX", function()
	assert(S.canTrain(1, 1, 1), "1 -> 2 at cap 2")
	assert(not S.canTrain(2, 1, 1), "2 is the cap")
	assert(not S.canTrain(9, 1, 1), "a level above the cap (stage dropped) cannot train")
	assert(S.clampLevel(999) == S.MAX_LEVEL and S.clampLevel(-3) == 0 and S.clampLevel("x") == 0, "clamp")
end)

test("price rises every level and never pays back faster than PAYBACK", function()
	local rate, scale = 12, 1   -- a Lead Regular, untrained, first company
	local last = 0
	for lv = 0, 14 do
		local p = S.price(lv, rate, scale)
		assert(p > last, "price rises at level " .. lv)
		last = p
		local added = rate * S.step("skill")
		assert(p / added >= S.payback(lv) - 1, "payback at level " .. lv)
	end
end)

test("effects are exact, and zero levels change nothing", function()
	assert(S.mult("skill", 0) == 1 and S.mult("speed", 0) == 1, "zero is x1")
	assert(math.abs(S.mult("skill", 3) - (1 + 3 * S.step("skill"))) < 1e-9, "skill 3")
	assert(math.abs(S.mult("speed", 5) - (1 + 5 * S.step("speed"))) < 1e-9, "speed 5")
	assert(S.mult("loyalty", 7) == 1, "loyalty does not change income")
end)

test("carry: no loyalty keeps nothing, full loyalty keeps all, never more than trained", function()
	assert(S.carry(8, 0) == 0, "loyalty 0")
	local full = math.ceil(1 / S.step("loyalty"))
	assert(S.carry(8, full) == 8 and S.carry(8, full + 5) == 8, "full loyalty keeps all")
	assert(S.carry(8, 5) == math.floor(8 * 5 * S.step("loyalty")), "half")
end)

return T
```

- [ ] **Step 2: Run it, expect failure**

Run: `lune run tests/offline/run`
Expected: `FAIL  staffstats.spec.luau: could not load` (module missing).

- [ ] **Step 3: Implement** `src/ReplicatedStorage/StaffStats.lua`

```lua
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
```

Add to `src/ServerScriptService/WaferPlan.lua` after `W.APT_FROM`:

```lua
W.STAGE_AT = { 5, 9, 13, 18 }   -- wafer level where the old HQ stage 2..5 begins
-- the old HQ level (1-5) a wafer level stands for (Wafers.stage reads this)
function W.stage(level)
	local s = 1
	for i, at in ipairs(W.STAGE_AT) do if (level or 1) >= at then s = i + 1 end end
	return s
end
```

Replace the body of `Wafers.stage` (`src/ServerScriptService/Wafers.lua:166-170`) with `return P.stage(level)` (the module already holds WaferPlan as `P`).

- [ ] **Step 4: Run the tests, expect pass**

Run: `lune run tests/offline/run` → `... 0 failed`; `selene src tests` → 0 errors. Also `lune run tests/offline/run` must still pass `wafer.spec` (stage unchanged).

- [ ] **Step 5: Commit**

`git add src/ReplicatedStorage/StaffStats.lua src/ServerScriptService/WaferPlan.lua src/ServerScriptService/Wafers.lua tests/offline/staffstats.spec.luau` then commit "Staff stats: the rules in one pure module (StaffStats)".

### Task 2: ids and stats on every person, saved

**Files:**
- Modify: `src/ServerScriptService/SiliconCore.server.lua` (`spawnStaff` ~1495-1525: stamp `id`, `skill`, `speed`, `loyalty`, `pin`)
- Modify: `src/ServerScriptService/SaveLoad.lua` (serialize ~89-121; load ~322-343)
- Test: `tests/offline/savecontract.spec.luau` (already checks every written field is read; it must pass with the five new arrays)

**Interfaces:**
- Consumes: `StaffStats.clampLevel`.
- Produces: staff entry fields `id` (int), `skill`, `speed`, `loyalty` (int), `pin` (string, "" = unpinned); session `s.nextStaffId` (int). Saved arrays `ids`, `skill`, `speed`, `loyalty`, `pin`, and `nsid` (next id).

- [ ] **Step 1: In `spawnStaff`, stamp the new fields** right after `local entry = {...}`:

```lua
	-- v8 (13 Oct) MANAGE STAFF: a permanent id (list position is not one) and the
	-- three trained stats (StaffStats); 0 until the TEAM screen trains them
	s.nextStaffId = (s.nextStaffId or 0) + 1
	entry.id, entry.skill, entry.speed, entry.loyalty, entry.pin = s.nextStaffId, 0, 0, 0, ""
```

- [ ] **Step 2: Serialize** (SaveLoad, beside `talents`):

```lua
			-- v8 (13 Oct) MANAGE STAFF: per person, beside tiers/talents/people
			ids = (function() local t = {} for i, r in ipairs(s.rigs or {}) do t[i] = r.id or 0 end return t end)(),
			skill = (function() local t = {} for i, r in ipairs(s.rigs or {}) do t[i] = r.skill or 0 end return t end)(),
			speed = (function() local t = {} for i, r in ipairs(s.rigs or {}) do t[i] = r.speed or 0 end return t end)(),
			loyalty = (function() local t = {} for i, r in ipairs(s.rigs or {}) do t[i] = r.loyalty or 0 end return t end)(),
			pin = (function() local t = {} for i, r in ipairs(s.rigs or {}) do t[i] = r.pin or "" end return t end)(),
			nsid = s.nextStaffId or 0,
```

- [ ] **Step 3: Load** (SaveLoad, in the staff loop after `r.tier = tier`): ids are restored only when valid and unique; otherwise a fresh id. `s.nextStaffId` starts at `clampInt(data.nsid, 0, 1e9, 0)` BEFORE the loop (set `s.nextStaffId` before calling `spawnStaff`, then overwrite `r.id` when the saved id is good):

```lua
		s.nextStaffId = clampInt(data.nsid, 0, 1e9, 0)
		local usedIds = {}
		-- (inside the loop, after r.tier = tier:)
			if r then
				local function arr(name) return type(data[name]) == "table" and data[name][i] or nil end
				local sid = clampInt(arr("ids"), 0, 1e9, 0)
				if sid > 0 and not usedIds[sid] then r.id = sid end
				usedIds[r.id] = true
				s.nextStaffId = math.max(s.nextStaffId, r.id)
				r.skill = StaffStats.clampLevel(arr("skill"))
				r.speed = StaffStats.clampLevel(arr("speed"))
				r.loyalty = StaffStats.clampLevel(arr("loyalty"))
				local pn = arr("pin")
				r.pin = (type(pn) == "string" and #pn <= 12 and pn:match("^%a*$")) and pn or ""
			end
```

(`StaffStats` is required at the top of SaveLoad: `local StaffStats = require(game:GetService("ReplicatedStorage"):WaitForChild("StaffStats"))`. Note: a fresh id from `spawnStaff` can collide with a later saved id; after the loop, re-run a uniqueness pass: walk `s.rigs`, and any id seen twice gets `s.nextStaffId + 1`.)

- [ ] **Step 4: Run** `lune run tests/offline/run` → `savecontract.spec` passes (every new field written is read). selene clean.

- [ ] **Step 5: Live check (Studio, Wilz):** Play; on the server: every `s.rigs[i].id` is unique and > 0; stats are 0. Stop Play (save-on-leave), Play again: the same ids come back. Restore Wilz's save after.

- [ ] **Step 6: Commit** "Staff: permanent ids and three stats, saved per person".

### Task 3: the two effects

**Files:**
- Modify: `src/ServerScriptService/SiliconCore.server.lua` `recompute` (~1255) and the work loop (~3173)

**Interfaces:**
- Consumes: `StaffStats.mult(id, level)`.

- [ ] **Step 1: Income** (`recompute`): multiply `v` by `StaffStats.mult("skill", r.skill)`:

```lua
			local v = CFG.TIER_RATE[r.tier or 1] * talentMultOf(r) * ((r.fit and Econ) and Econ.FIT_MULT or 1) * (r.eff or 1)
				* StaffStats.mult("skill", r.skill)   -- v8 MANAGE STAFF: trained Skill
```

- [ ] **Step 2: Work** (the per-second loop): `work += CFG.TIER_RATE[r.tier or 1] / 2 * StaffStats.mult("speed", r.speed)`.

`StaffStats` is required once near the other ReplicatedStorage requires at the top of SiliconCore (watch the 200-local limit: SiliconCore notes it is at the top-level local cap; if so, read it through an existing table, e.g. `Econ.StaffStats = require(...)` in RoomEconomy, and use `Econ.StaffStats`).

- [ ] **Step 3: Live check (Studio):** Play; record `s.rate`; set one seated person's `skill = 3`, call recompute (SVDev or the server function); `s.rate` rises by that person's share x 0.3 (+-1%). Set it back to 0: `s.rate` equals the first value exactly. Same for Speed against `s.work` per second. Restore the save.

- [ ] **Step 4: Run** offline tests + selene; **Commit** "Staff: Skill multiplies income, Speed multiplies product work".

### Task 4: the simulator and its four gates

**Files:**
- Create: `tools/staff_sim.luau`
- Modify: `tools/bas.luau` (`sim list` table: add `staff_sim`)

**Interfaces:**
- Consumes: `StaffStats`, `WaferPlan` (`BASE`, `MULT`, `CAP`, `stage`, `price`), `CoreConfig` (`TIER_RATE`, `TALENT`), `Progression.runScale`.
- Produces: `lune run tools/staff_sim` prints G1–G4 with PASS/FAIL and exits 1 on any FAIL; `--json` for `bas`.

Model inputs (not game code; printed at the top of the output): every seated person is a Lead (12/s) in a fit room (x1.5); the team is `W.CAP[level]` people with a talent mix per stage: stage 1 all Regular; 2: 1 Star; 3: 1 Genius, 2 Star; 4: 2 Genius, 3 Star; 5: 3 Genius, 4 Star; everyone else is 70% Regular, 30% Skilled. Other multipliers (quality, morale, spin) are 1: the gates are ratios or paybacks, which they cancel out of.

- [ ] **Step 1: Write `tools/staff_sim.luau`:**
  - G1: for each stage's first level, income with every person at `cap(stage, talent)` Skill / income untrained; PASS if <= 2.0 everywhere.
  - G2: for each stage and talent present, every Skill level 0..cap-1: `price(level, personBaseRate, 1) / (personBaseRate * step)` in seconds; PASS if all within [180, 1800].
  - G3: simulate seconds from each stage's first level to the next stage's first level, buying wafer levels with `W.price(level, 1, 0)` when affordable; variant A never trains; variant B buys any Skill level whose payback is under 30 min, cheapest first; PASS if time(B) / time(A) >= 0.70 at every stage.
  - G4: a new run (scale `Progression.runScale(1)`), stage 1, 5 Genius keepers with carried Skill = `carry(13, loyalty=10)` vs 0; time to stage 2 as in G3 (no further training); PASS if ratio >= 0.60. If FAIL, re-run with carried levels clamped to `cap(1, 4)` and report that the fallback rule applies.
- [ ] **Step 2: Run** `lune run tools/staff_sim`. For any FAIL, change ONLY the step values or `TALENT_BONUS` in `StaffStats` toward weaker training, re-run, and record each try in the commit message. Stop at the first set that passes all four; if none passes in 6 tries, stop and report.
- [ ] **Step 3: Add** `staff_sim` to `bas sim list`; run `lune run tools/bas sim staff_sim`.
- [ ] **Step 4: Commit** "Staff: the simulator and its four gates (all pass with STEP=..., ...)".

### Task 5: docs, spec amendment, PR through the gate

**Files:**
- Modify: `docs/features/hiring-talent.md` (Files: `StaffStats`, `staff_sim`; State: the new fields and save arrays; Prove it: `staffstats.spec`, `staff_sim`)
- Modify (outside git): the spec §3.3, the price floor uses the person's untrained rate (reason: G2 math)

- [ ] **Step 1:** `lune run tools/bas map check` → coverage and staleness pass.
- [ ] **Step 2:** push the branch, open the PR (no auto-merge), then the doctor gate: fingerprint in Edit, doctor run, `lune run tools/bas checkup pr <report> <fingerprint> --post`.
- [ ] **Step 3:** report to Luke: what is verified, what is not, and that nothing is visible to players until Phase 2.
