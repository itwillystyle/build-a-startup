# Homes as keeper slots — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the apartment you own decide how many of your rare staff survive a spin-off, instead of paying an invisible +10% and acting as a toll booth on HQ levels.

**Architecture:** All new rules go in `Progression.lua`, which is pure (no services, no `Instance`) and therefore testable in Lune outside Studio. `RoomEconomy`, `Apartments`, `WaferPlan` and `SiliconCore` consume those rules; no new module is created. The home gates are deleted from both places they exist — `Progression.gateHQ` (old HQ path) and `WaferPlan.APT_GATE` (the live wafers path).

**Tech Stack:** Luau, Rojo (file → Studio, file-authoritative), selene (lint; catches forward references as `undefined_variable`), Lune (offline tests), git with a pre-commit hook that runs both.

## Global Constraints

- Phase 1 of `docs/superpowers/specs/2026-10-07-loop-complements-design.md`. Phases 2 (cars) and 3 (the chase) are **not** in this plan.
- Keeper slots: **none 0 / STUDIO 1 / LOFT 3 / PENTHOUSE 5**.
- Home prices: **1% / 15% / 60% of the next spin-off**. `homePrice(tierId, spinCost)` takes the
  already-computed spin cost, which carries the per-company scaling itself. Do NOT route it through
  `P.runScale(n)`: that is `spinCost`'s multiplier x `RUN_HOMES` (1.3), so it would push the home 1.3x
  higher per company *relative to the spin-off* and the 60% share would drift upward every run.
- `Econ.KEEP_TALENT = 3` (Star and above are eligible) is **unchanged**.
- The offline window `P.WINDOW = { [0] = 40*60, 2*3600, 4*3600, 8*3600 }` is **unchanged**. It works and was never the problem.
- The `bonus = 0.10` field and `Apartments.mult` are **deleted**.
- Homes persist across spin-offs. That is existing behaviour and stays.
- A crafted save must never mint slots: every read of `s.apt` is clamped, exactly as `sanitizeTiers` does elsewhere.
- Run from the `game/` folder. Lune is `%USERPROFILE%/.rokit/bin/lune.exe`, selene is `%USERPROFILE%/.rokit/bin/selene.exe`.
- Rojo is file-authoritative: never edit `.Source` in Studio, edit the file.
- After any change that builds world objects, **count what it created** — a placement bug is invisible to the lint and to the type checker.

---

## File Structure

| File | Responsibility after this plan |
|---|---|
| `src/ServerScriptService/Progression.lua` | Owns `keepSlots`, `homePrice`, `HOME_SHARE`, `KEEP_SLOTS`. Loses `gateHQ`, `bonus`, `aptNeeded`. `ladder` stops adding home prices. |
| `src/ServerScriptService/WaferPlan.lua` | Loses `APT_GATE` and `aptRequired`. Wafer levels are gated by blueprint and money only. |
| `src/ServerScriptService/Apartments.lua` | Loses `mult` and `need`. Prices come from `Progression.homePrice`. |
| `src/ServerScriptService/RoomEconomy.lua` | `KEEP_MAX` deleted; the cap is now per-player via `Progression.keepSlots`. |
| `src/ServerScriptService/SiliconCore.server.lua` | Spin-off keeps `keepSlots(s.apt)` staff, honouring a selection. All gate call sites removed. |
| `src/StarterPlayer/StarterPlayerScripts/HudClient.client.lua` | The spin-off card shows slots and, when you have more eligible staff than slots, lets you pick who comes. |
| `tests/offline/home.spec.luau` | Lune tests for slots, pricing, and the gate-free ladder. |

---

## Task 1: Keeper slots and share pricing in Progression

Pure, additive, nothing else consumes it yet. Ships green.

**Files:**
- Modify: `src/ServerScriptService/Progression.lua` (after the `P.APARTMENTS` table, ~line 116)
- Test: `tests/offline/home.spec.luau`

**Interfaces:**
- Consumes: `P.niceDown(v)`, `P.spinCost(n, base)`, `P.runScale(n)` — all already in this file.
- Produces: `P.KEEP_SLOTS` (table), `P.keepSlots(apt) -> number`, `P.HOME_SHARE` (table), `P.homePrice(tierId, spinCost) -> number`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/offline/home.spec.luau`, before the final `return T`:

```lua
test("keeper slots are decided by the home you own", function()
	assert(P.keepSlots(0) == 0, "no home keeps nobody")
	assert(P.keepSlots(1) == 1, "studio")
	assert(P.keepSlots(2) == 3, "loft")
	assert(P.keepSlots(3) == 5, "penthouse")
end)

test("a crafted save cannot mint keeper slots", function()
	assert(P.keepSlots(99) == 5, "clamped to the top home")
	assert(P.keepSlots(-4) == 0, "clamped to none")
	assert(P.keepSlots(nil) == 0, "missing is none")
	assert(P.keepSlots(2.9) == 3, "a fractional save floors to a real tier")
end)

test("a home costs a share of the spin-off it competes with", function()
	local spin = P.spinCost(0, 4e6)
	assert(spin == 4000000, "spin 1 is $4M, got " .. tostring(spin))
	assert(P.homePrice(1, spin) == 40000, "studio 1%, got " .. tostring(P.homePrice(1, spin)))
	assert(P.homePrice(2, spin) == 600000, "loft 15%, got " .. tostring(P.homePrice(2, spin)))
	assert(P.homePrice(3, spin) == 2400000, "penthouse 60%, got " .. tostring(P.homePrice(3, spin)))
end)

test("the penthouse stays a real fraction of a spin-off in later companies", function()
	for n = 0, 6 do
		local spin = P.spinCost(n, 4e6)
		local share = P.homePrice(3, spin) / spin
		assert(share > 0.55 and share <= 0.60,
			("company %d: penthouse is %.3f of a spin-off"):format(n + 1, share))
	end
end)

test("homePrice refuses a tier that does not exist", function()
	assert(P.homePrice(0, 4e6) == 0)
	assert(P.homePrice(4, 4e6) == 0)
	assert(P.homePrice(nil, 4e6) == 0)
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
"$USERPROFILE/.rokit/bin/lune.exe" run tests/offline/run
```

Expected: FAIL, `attempt to call a nil value` on `P.keepSlots`.

- [ ] **Step 3: Implement**

In `src/ServerScriptService/Progression.lua`, immediately after the `P.APARTMENTS` table:

```lua
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
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
"$USERPROFILE/.rokit/bin/lune.exe" run tests/offline/run
```

Expected: PASS, and every pre-existing case still passes.

- [ ] **Step 5: Lint**

```bash
"$USERPROFILE/.rokit/bin/selene.exe" src/ServerScriptService/Progression.lua
```

Expected: `0 errors`.

- [ ] **Step 6: Commit**

```bash
git add src/ServerScriptService/Progression.lua tests/offline/home.spec.luau
git commit -m "feat: keeper slots and share-priced homes in Progression"
```

---

## Task 2: Delete the home gates

Homes stop being a toll booth. This touches the most call sites of any task, so it goes before the repricing — a home that costs more **and** still gates would stall a new player.

**Files:**
- Modify: `src/ServerScriptService/WaferPlan.lua:22` and `:146-153`
- Modify: `src/ServerScriptService/Progression.lua` (the `gateHQ` fields, `P.aptNeeded`, `P.ladder`)
- Modify: `src/ServerScriptService/Apartments.lua:35`
- Modify: `src/ServerScriptService/SiliconCore.server.lua` at `:1559`, `:1585`, `:1808-1811`, `:2012`, `:2015`, `:2024-2025`, `:2038-2040`, `:2113-2116`, `:2119-2120`
- Test: `tests/offline/home.spec.luau`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `P.ladder(level, apt, hqCost, spinCost)` keeps its four-argument signature but no longer adds home prices. `P.aptNeeded` and `W.aptRequired` no longer exist.

- [ ] **Step 1: Replace the gate tests with gate-free ones**

In `tests/offline/home.spec.luau`, **delete** the existing case `"ladder: HQ 2 with no apartment is HQ 3 + Studio, then HQ 4 + Loft"` and any other case that asserts a home price inside a ladder step. Add:

```lua
test("the ladder is HQ steps and the spin-off: homes do not gate it", function()
	local n, a = P.ladder(2, 0, hqCost, 4e6)
	assert(n == 37500 and a == 225000, ("got %s, %s"):format(n, a))
end)

test("owning no home changes nothing about the ladder", function()
	local n0, a0 = P.ladder(3, 0, hqCost, 4e6)
	local n3, a3 = P.ladder(3, 3, hqCost, 4e6)
	assert(n0 == n3 and a0 == a3, "the ladder must not look at the home any more")
end)

test("the gates are gone from both paths", function()
	assert(P.aptNeeded == nil, "Progression.aptNeeded must be deleted")
	local W = require("../../src/ServerScriptService/WaferPlan")
	assert(W.aptRequired == nil, "WaferPlan.aptRequired must be deleted")
end)
```

- [ ] **Step 2: Run to verify they fail**

```bash
"$USERPROFILE/.rokit/bin/lune.exe" run tests/offline/run
```

Expected: FAIL on the ladder values (it still adds `20000`) and on `aptNeeded` still existing.

- [ ] **Step 3: Strip the gate from WaferPlan**

In `src/ServerScriptService/WaferPlan.lua`, delete line 22:

```lua
local APT_GATE = { { 9, 1 }, { 13, 2 }, { 18, 3 } }  -- building this level needs this many homes
```

and delete the whole function at lines 146-153:

```lua
-- how many homes you must own to build `level`
function W.aptRequired(level)
	local need = 0
	for _, g in ipairs(APT_GATE) do
		if level >= g[1] then need = g[2] end
	end
	return need
end
```

- [ ] **Step 4: Strip the gate from Progression**

Remove `gateHQ = N,` from all three entries of `P.APARTMENTS`, and delete:

```lua
-- the apartment you must own before building HQ `level` (0 = none)
function P.aptNeeded(level)
	for _, t in ipairs(P.APARTMENTS) do
		if t.gateHQ == level then return t.id end
	end
	return 0
end
```

Replace `P.ladder` with:

```lua
--[[ Your next two steps: each HQ level, then the spin-off, then HQ 2.

	`apt` is still taken so no caller needs an edit, and is deliberately unused:
	homes stopped gating HQ levels, so the step to the next level is its price
	and nothing else. If selene flags the unused parameter, rename it `_apt`. ]]
function P.ladder(level, apt, hqCost, spinCost)
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
```

- [ ] **Step 5: Remove the one alias in Apartments**

In `src/ServerScriptService/Apartments.lua`, delete line 35:

```lua
-- the apartment you must own before building HQ `level`
Apartments.need = Prog.aptNeeded
```

- [ ] **Step 6: Remove the gate call sites in SiliconCore**

All of these currently tell the player to buy a home before building. Each becomes unconditional.

At `:1556-1562`, the `need` block in the HQ payload — delete it and every later use of that `need` local in the same function, so the payload no longer carries a home requirement:

```lua
	local nxt = CFG.HQ_LEVELS[lv + 1]
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
```

At `:1584-1587`, the wafers payload — delete:

```lua
		local id = WP.aptRequired(msLevel or wlevel)
		local t = id > (s.apt or 0) and Econ.Apt and Econ.Apt.TIERS[id]
		need = t and { tier = t.id, name = ..., price = t.price } or nil
```

and remove `need` from the returned table.

At `:1806-1815`, the guide's apartment rung — delete the whole `aptNeed` branch so the guide never diverts to a home:

```lua
			local aptNeed = Econ and Econ.Apt and Econ.Apt.need(plot.hq.level + 1) or 0
			if Econ and Econ.WAFERS and plot.wafer then aptNeed = Econ.Wafers.Plan.aptRequired(plot.wafer.level + 1) end
			if best and best.k == "hq" and Econ and Econ.Apt and (s.apt or 0) < aptNeed then
				...
			end
```

At `:2012`, replace the attribute with a constant zero so the client keeps a field it already reads:

```lua
			owner:SetAttribute("WaferNeed", 0)   -- homes no longer gate a level
```

At `:2015` and `:2024-2026`, delete `local need = WP.aptRequired(L)` and the branch that uses it:

```lua
			if s and (s.apt or 0) < need and Econ.Apt then
				plot.hqLabel.Text = ("BUILD  ·  needs a %s downtown"):format(Econ.Apt.TIERS[need].name)
				plot.hqPad.Color = Color3.fromRGB(150, 146, 140)
			elseif last > L then
```

becomes:

```lua
			if last > L then
```

At `:2038-2041`, delete the `needApt` branch:

```lua
	local needApt = nxt and s and Econ and Econ.Apt and (s.apt or 0) < Econ.Apt.need(plot.hq.level + 1)
	if needApt then
		plot.hqLabel.Text = ("UPGRADE HQ  ·  needs a %s downtown"):format(...)
		plot.hqPad.Color = Color3.fromRGB(150, 146, 140)
	elseif nxt then
```

becomes:

```lua
	if nxt then
```

At `:2112-2124`, delete both the refusal and the storey truncation:

```lua
	local need = WP.aptRequired(L)
	if (s.apt or 0) < need and Econ.Apt then
		popup(plot.hqPad, ("Buy your %s downtown first"):format(Econ.Apt.TIERS[need].name), CFG.BAD)
		return
	end
	-- a home gate inside a rebuilt storey stops the storey there
	if WP.aptRequired(last) > (s.apt or 0) then
		while last > L and WP.aptRequired(last) > (s.apt or 0) do last -= 1 end
		price = 0
		for x = L, last do price += WP.price(x, scaleOf(s), s.record or 1) end
		price = Mom.priceAfter(price, s.momentum or 0)
	end
```

Delete all of it. Nothing replaces it.

- [ ] **Step 7: Run tests and lint**

```bash
"$USERPROFILE/.rokit/bin/lune.exe" run tests/offline/run
"$USERPROFILE/.rokit/bin/selene.exe" src/
```

Expected: tests PASS; selene `0 errors`. selene is the guard here — a missed `need` or `aptRequired` reference shows up as `undefined_variable`.

- [ ] **Step 8: Verify in Play that nothing gates**

Start Play, then in the **Server** datamodel:

```lua
local SSS = game:GetService("ServerScriptService")
local WP = require(SSS:WaitForChild("WaferPlan"))
local P = require(SSS:WaitForChild("Progression"))
assert(WP.aptRequired == nil and P.aptNeeded == nil, "a gate survived")
print("no gates; pad reads:", workspace.SiliconValley.Plots.Plot1:FindFirstChild("HQLabel", true)
	and workspace.SiliconValley.Plots.Plot1:FindFirstChild("HQLabel", true).Text)
```

Expected: no assertion, and the pad never says "needs a … downtown". Check the console shows **0 errors**.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: homes stop gating HQ and wafer levels"
```

---

## Task 3: Homes stop paying a bonus and start costing a share

**Files:**
- Modify: `src/ServerScriptService/Progression.lua` (the `price` and `bonus` fields of `P.APARTMENTS`)
- Modify: `src/ServerScriptService/Apartments.lua:37-43` (`mult`), `:413-421` (catalog), `:442-452` (buy), `:586-589` (bot buy)
- Test: `tests/offline/home.spec.luau`

**Interfaces:**
- Consumes: `P.homePrice(tierId, spinCost)` from Task 1.
- Produces: `Apartments.priceOf(s, tierId) -> number`. `Apartments.mult` no longer exists.

- [ ] **Step 1: Write the failing tests**

`Apartments.lua` calls `game:GetService` at load, so Lune cannot require it. These
tests therefore assert only the pure `Progression` fields; `Apartments.mult`'s
removal is verified by selene and in Play at Step 5.

```lua
test("the money bonus is gone", function()
	for _, t in ipairs(P.APARTMENTS) do
		assert(t.bonus == nil, t.name .. " still carries a bonus")
	end
end)

test("the authored price field is gone: price comes from the spin-off", function()
	for _, t in ipairs(P.APARTMENTS) do
		assert(t.price == nil, t.name .. " still carries a fixed price")
	end
end)
```

- [ ] **Step 2: Run to verify they fail**

```bash
"$USERPROFILE/.rokit/bin/lune.exe" run tests/offline/run
```

Expected: FAIL — `STUDIO still carries a bonus`.

- [ ] **Step 3: Strip the fields**

`P.APARTMENTS` becomes (note: no `price`, no `bonus`, no `gateHQ`):

```lua
P.APARTMENTS = {
	{ id = 1, key = "studio", name = "STUDIO", minHQ = 2,
	  blurb = "A place of your own. Floor-to-ceiling windows." },
	{ id = 2, key = "loft", name = "LOFT", minHQ = 3,
	  blurb = "Room to host: a kitchen island, a real bedroom." },
	{ id = 3, key = "penthouse", name = "PENTHOUSE", minHQ = 4,
	  blurb = "The top of the tower. An indoor pool. A view of your valley." },
}
```

- [ ] **Step 4: Price from the spin-off in Apartments**

Delete `Apartments.mult` entirely (lines 37-43). Add, after `Apartments.TIERS`:

```lua
--[[ RoomEconomy owns SPINOFF_BASE and does NOT require this module (SiliconCore
	wires Econ.Apt at startup), so requiring it here is safe and not circular.
	Checked before writing this, because a circular require fails at load with a
	message that blames the wrong file. ]]
local Econ = require(SSS:WaitForChild("RoomEconomy"))

--[[ What this home costs YOU, now. A share of the spin-off you are saving for,
	so the choice between five keeper slots and restarting sooner is the same
	choice in company one and company nine. ]]
function Apartments.priceOf(s, tierId)
	local spin = Prog.spinCost((s and s.spinoffs) or 0, Econ.SPINOFF_BASE)
	return Prog.homePrice(tierId, spin)
end
```

Put the `local Econ` line beside the existing `local Prog` at line 31, not inside
the function.

Then replace every `t.price` read:

- `:418-419` catalog → `price = Apartments.priceOf(s, t.id)`, and delete `gate = t.gateHQ, bonus = ...` from the payload.
- `:447` and `:451` buy → `local price = Apartments.priceOf(s, t.id)`, compare and subtract `price`.
- `:464` move-in cinematic → delete `bonus = ...` from the payload.
- `:588-589` bot buy → `local price = Apartments.priceOf(s, t.id)`, compare and subtract `price`.

Each of these needs the session `s` in scope; it already is at every one of those sites (they all read `s.apt` nearby).

- [ ] **Step 5: Verify in Play**

Start Play, then in the **Server** datamodel:

```lua
local SSS = game:GetService("ServerScriptService")
local A = require(SSS:WaitForChild("Apartments"))
assert(A.mult == nil, "Apartments.mult survived")
local fake = { spinoffs = 0 }
for id = 1, 3 do print(("tier %d costs $%d"):format(id, A.priceOf(fake, id))) end
```

Expected: `40000`, `600000`, `2400000`. Then open the phone's home catalog in game and confirm those are the prices shown and that buying one deducts exactly that.

- [ ] **Step 6: Lint, test, commit**

```bash
"$USERPROFILE/.rokit/bin/selene.exe" src/
"$USERPROFILE/.rokit/bin/lune.exe" run tests/offline/run
git add -A
git commit -m "feat: homes cost a share of the spin-off, and pay no money bonus"
```

---

## Task 4: Keeper slots at the spin-off

**Files:**
- Modify: `src/ServerScriptService/RoomEconomy.lua:359` (delete `KEEP_MAX`)
- Modify: `src/ServerScriptService/SiliconCore.server.lua:2933-2935` (card count) and `:2947-2956` (the keep loop)
- Test: in Play (the spin-off path needs a session, a plot and rigs)

**Interfaces:**
- Consumes: `Progression.keepSlots(apt)` from Task 1.
- Produces: the `spinAsk` payload gains `slots` (number) and `eligible` (array of `{ idx, name, talent }`).

- [ ] **Step 1: Delete the flat cap**

In `src/ServerScriptService/RoomEconomy.lua`, delete line 359:

```lua
Econ.KEEP_MAX = 3              -- the spin-off keeps your 3 best (recruiting makes Star+ common: sim kept ~12)
```

- [ ] **Step 2: Build the eligible list once, in the card branch**

Replace `SiliconCore.server.lua:2933-2941` with:

```lua
		--[[ The home decides how many come with you; the player decides which.
			Eligibility is still KEEP_TALENT (Star and above). Sorted best-first
			so the default selection -- the top `slots` -- is already the one a
			player would pick, and the choice only appears when it is real. ]]
		local slots = Prog.keepSlots(s.apt)
		local eligible = {}
		for i, r in ipairs(s.rigs or {}) do
			if (r.talent or 1) >= ((Econ and Econ.KEEP_TALENT) or 3) then
				table.insert(eligible, { idx = i, talent = r.talent or 1,
					name = (r.rig and r.rig:GetAttribute("PersonName")) or "someone" })
			end
		end
		table.sort(eligible, function(a, b) return a.talent > b.talent end)
		if Econ and Econ.celebrate then
			Econ.celebrate:FireClient(player, { kind = "spinAsk", cost = cost, from = spinMultOf(s), to = nextSpinMultOf(s),
				keep = math.min(#eligible, slots), slots = slots, eligible = eligible,
				number = (s.spinoffs or 0) + 1 })
		end
```

`Prog` must be in scope. If `SiliconCore` does not already hold a local for `Progression`, add it beside the other module locals near the top — the file is at its 200 top-level local limit, so if the limit bites, call `Econ.Prog` if that alias exists, else reuse the existing `Econ.Apt`-style access rather than adding a new local.

- [ ] **Step 3: Honour the slot count in the keep loop**

Replace `:2947-2956` with:

```lua
	-- v2.7.0: Star and above follow you to the next startup (the chase across runs)
	-- 2026-10-07: how many of them is the home you bought
	local keep = {}
	if Econ and Econ.V3 then
		for _, r in ipairs(s.rigs or {}) do
			if (r.talent or 1) >= Econ.KEEP_TALENT then table.insert(keep, { talent = r.talent, who = r.who }) end
		end
		table.sort(keep, function(a, b) return a.talent > b.talent end)
		local slots = Prog.keepSlots(s.apt)
		while #keep > slots do table.remove(keep) end
	end
```

- [ ] **Step 4: Verify in Play, at three home tiers**

Start Play. In the **Server** datamodel, snapshot the save first so a destructive dev command cannot cost real progress:

```lua
local ds = game:GetService("DataStoreService"):GetDataStore("SVSave_v1")
local key = "1688749216"
local rec = ds:GetAsync(key)
ds:SetAsync(key .. "_pre_slots", rec)
print("snapshot written")
```

Then for each of `apt = 1, 2, 3`: set the session's `apt`, give enough cash, grant six Star+ staff via `SVDev`, trigger the spin-off, and count the rigs that survive.

Expected: 1, 3 and 5 survivors respectively. Restore the snapshot afterwards with `ds:SetAsync(key, ds:GetAsync(key .. "_pre_slots"))` — bind the read to a local first, because `SetAsync(k, ds:GetAsync(x))` forwards two returns and errors with "Unable to cast Instance to Array".

- [ ] **Step 5: Lint and commit**

```bash
"$USERPROFILE/.rokit/bin/selene.exe" src/
git add -A
git commit -m "feat: the home you own decides how many staff survive a spin-off"
```

---

## Task 5: Pick who comes

Only appears when `#eligible > slots`. With fewer eligible than slots there is no decision and no UI.

**Files:**
- Modify: `src/StarterPlayer/StarterPlayerScripts/HudClient.client.lua:700-760` (the `spinAsk` card)
- Modify: `src/ServerScriptService/SiliconCore.server.lua:2711` (`SpinConfirm` accepts a selection) and the keep loop from Task 4
- Test: in Play

**Interfaces:**
- Consumes: `slots` and `eligible` from the Task 4 payload.
- Produces: `SpinConfirm:FireServer({ pick = { <idx>, ... } })`. The server validates and falls back to the top `slots` when `pick` is absent, malformed, or names an index that is not eligible.

- [ ] **Step 1: Let the card carry a selection**

In `HudClient.client.lua`, inside `spinAsk(e)`, after the two `col(...)` calls and before the buttons, add:

```lua
	--[[ The home bought the slots; this is where you spend them. Shown only
		when there are more eligible people than seats -- with nothing to
		decide, a chooser is just a step between you and the button. ]]
	local picked = {}
	local eligible = e.eligible or {}
	local slots = e.slots or 0
	if #eligible > slots and slots > 0 then
		panel.Size = UDim2.new(0, w, 0, 280 + 96)
		for i = 1, slots do picked[eligible[i].idx] = true end
		local strip = Instance.new("ScrollingFrame")
		strip.Name = "Keepers"
		strip.BackgroundTransparency = 1
		strip.BorderSizePixel = 0
		strip.Position = UDim2.new(0, 0, 0, 148)
		strip.Size = UDim2.new(1, 0, 0, 86)
		strip.ScrollBarThickness = 4
		strip.AutomaticCanvasSize = Enum.AutomaticSize.Y
		strip.CanvasSize = UDim2.new(0, 0, 0, 0)
		strip.Parent = body
		local layout = Instance.new("UIGridLayout")
		layout.CellSize = UDim2.new(0, 128, 0, 38)
		layout.CellPadding = UDim2.new(0, 6, 0, 6)
		layout.Parent = strip
		local count = UIKit.label(body, "", 14, UIKit.INK_SOFT,
			{ Position = UDim2.new(0, 0, 0, 236), Size = UDim2.new(1, 0, 0, 18) }, UIKit.BODY)
		local chips = {}
		local function redraw()
			local n = 0
			for _ in pairs(picked) do n += 1 end
			count.Text = ("%d of %d seats filled"):format(n, slots)
			for idx, b in pairs(chips) do
				UIKit.setButtonColor(b, picked[idx] and UIKit.GREEN or UIKit.MUTED)
			end
		end
		for _, who in ipairs(eligible) do
			local chip = UIKit.button(strip, ("%s  ·  %d"):format(who.name, who.talent), UIKit.MUTED,
				{ Name = "Keep_" .. who.idx }, { textSize = 14 })
			chips[who.idx] = chip
			chip.MouseButton1Click:Connect(function()
				if picked[who.idx] then
					picked[who.idx] = nil
				else
					local n = 0
					for _ in pairs(picked) do n += 1 end
					if n >= slots then return end          -- the home bought this many, no more
					picked[who.idx] = true
				end
				redraw()
			end)
		end
		redraw()
	end
```

- [ ] **Step 2: Send the selection**

At `HudClient.client.lua:768`, replace:

```lua
			remotes:WaitForChild("SpinConfirm"):FireServer()
```

with:

```lua
			local pick = {}
			for idx in pairs(picked) do table.insert(pick, idx) end
			remotes:WaitForChild("SpinConfirm"):FireServer({ pick = pick })
```

- [ ] **Step 3: Accept and validate it on the server**

At `SiliconCore.server.lua:2711`, change the handler signature to take the payload and stash a validated selection on the session:

```lua
	remote("SpinConfirm").OnServerEvent:Connect(function(player, msg)
		local s = sessions[player]
		--[[ Never trust the client with WHO survives: the picks are matched
			against the eligible set computed here, and anything unrecognised is
			dropped rather than honoured. An empty or missing pick falls back to
			the best `slots`, which is what the card defaulted to anyway. ]]
		if s and type(msg) == "table" and type(msg.pick) == "table" then
			local want = {}
			for _, idx in ipairs(msg.pick) do
				local r = s.rigs and s.rigs[idx]
				if type(idx) == "number" and r and (r.talent or 1) >= ((Econ and Econ.KEEP_TALENT) or 3) then
					want[idx] = true
				end
			end
			s.spinPick = next(want) and want or nil
		else
			s.spinPick = nil
		end
```

leaving the rest of the handler body unchanged.

- [ ] **Step 4: Honour it in the keep loop**

In the Task 4 keep loop, replace the body of the `if Econ and Econ.V3 then` block with:

```lua
		local slots = Prog.keepSlots(s.apt)
		local pick = s.spinPick
		for i, r in ipairs(s.rigs or {}) do
			if (r.talent or 1) >= Econ.KEEP_TALENT and (not pick or pick[i]) then
				table.insert(keep, { talent = r.talent, who = r.who })
			end
		end
		table.sort(keep, function(a, b) return a.talent > b.talent end)
		while #keep > slots do table.remove(keep) end
		s.spinPick = nil
```

- [ ] **Step 5: Verify in Play**

Snapshot the save as in Task 4, Step 4. Then with `apt = 2` (3 slots) and six Star+ staff:

1. Trigger the spin-off; confirm the card shows a chip per eligible person and "3 of 3 seats filled".
2. Deselect one chip, select a different person, confirm the counter tracks.
3. Hold to spin off. Confirm the three who survive are **the three you selected**, by name, not the top three by talent.
4. Fire `SpinConfirm` with `{ pick = { 999, "x" } }` from a client context and confirm the server keeps the top three instead of erroring.

Restore the snapshot.

- [ ] **Step 6: Lint and commit**

```bash
"$USERPROFILE/.rokit/bin/selene.exe" src/
git add -A
git commit -m "feat: choose which staff follow you to the next company"
```

---

## Task 6: Re-sim and verify the curve

The spec names this as the gate on shipping, because removing gates lets a player rush HQ levels without buying homes — a faster curve than the sim has ever modelled.

**Files:**
- Modify: `../sim/clock_sim.py` (home prices and the removed gates)
- Modify: `../sim/wafer_plan.py`, `../sim/wafer_sim.py`, `../sim/test_wafer_plan.py` — all three still
  model the apartment gate the game no longer has
- Run: `../sim/first_hour_sim.py verify`, the in-game pace-20 bot

**The sims are NOT in the game repo.** They live at `silicon-startup/sim/`, a sibling of
`silicon-startup/game`, and are untracked by this git repository. Do not try to `git add sim/` —
it will fail. Edit them in place and say so in the report; there is nothing to commit for them.

- [ ] **Step 1: Teach the sim the new rules**

In `sim/clock_sim.py`, remove the apartment gate from the purchase order and replace the fixed home prices with `0.01 / 0.15 / 0.60 × spin_cost(n)`. Remove the +10%-per-home money multiplier from the rate calculation.

- [ ] **Step 2: Check the sim still matches the Lua**

```bash
python sim/first_hour_sim.py verify
```

Expected: `CLEAN`. If it reports a constant mismatch, the Lua changed in a way the sim has not been told about — fix the sim, not the game.

- [ ] **Step 3: Run the curve**

```bash
python sim/clock_sim.py
```

Record HQ 2/3/4/5 and the first spin-off for companies 1 and 2.

- [ ] **Step 4: Compare against the recorded baseline**

Baseline (pace 20, fresh save): HQ 4.0 / 7.6 / 12.3 / 19.5 min, spin-off 25.0.

Expected: HQ timings move **earlier** (no home purchases on the critical path) but by less than two minutes. If the first spin-off arrives before ~22 minutes, the home prices are too cheap relative to the curve and `HOME_SHARE` needs raising — change the share, not the slots.

- [ ] **Step 5: Run the live bot**

In Play, `SVDev` → `bot 20` on a wiped save. Compare against the sim; live and sim have historically agreed within about a minute.

- [ ] **Step 5b: Strip the gate from the wafer sims**

`../sim/wafer_plan.py`, `../sim/wafer_sim.py` and `../sim/test_wafer_plan.py` still carry
`APT_GATE` / `apt_required`. The generated Lua block in `WaferPlan.lua` does not depend on them, so
nothing is broken today — but a sim that prices a gate the game does not have will drift from live
on every future comparison, which is the whole reason the sims exist. Remove the gate from all
three, and re-run `python sim/wafer_plan.py lua` from the `silicon-startup` folder to confirm the
generated block is byte-identical to what is already in `src/ServerScriptService/WaferPlan.lua`.
If it differs, STOP and report — that means the gate was load-bearing after all.

- [ ] **Step 6: Record the result**

The sims are untracked, so there is nothing to commit for them. Append the before/after curve
numbers to the task report instead, and commit only any game-code change this task produced:

```bash
git status --short          # expect: clean, unless a tuning change was needed
```

---

## Self-review

**Spec coverage.** §3 of the spec maps to Tasks 1-5: keeper slots (Task 4), share pricing (Tasks 1, 3), gate removal (Task 2), bonus deletion (Task 3), selection step (Task 5). The offline window is explicitly untouched, as specified. §7's "must be re-run before shipping" list is Task 6. §4, §5 and §6 (chase, cars, items) are out of scope for this plan, per the spec's build order.

**Known gap, deliberate.** The spec says `Journey` should "surface a home when a spin-off is within reach and their slots are short". Task 2 deletes the guide's apartment rung but does not add that replacement — the guide would otherwise never mention homes again. This is left out on purpose: it needs the slot economy to exist first so the prompt can be written against real numbers, and it is one `Journey.task` branch. Add it after Task 6 confirms the curve.

**Risk carried from the spec.** Removing the gates changes the critical path of the whole game. Task 6 is the gate on shipping, not a formality.
