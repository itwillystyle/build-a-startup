# Manage Staff Phase 2 (the actions) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Players' staff can be TRAINED (Skill / Speed / Loyalty, paid in cash) and MOVED (pinned to a room type) through one server remote that cannot be fooled, pins are honoured by seating, the client gets a `StaffData` attribute, and keepers carry their training through a spin-off. No screen (phase 3): nothing a player can see changes.

**Architecture:** Two new PURE modules carry every rule so they can be tested offline: `Seating` (who sits where: pins first, then exactly today's algorithm) and `StaffAction` (parse, validate, apply, rate limit, the StaffData row, the keeper carry). `SiliconCore` only wires them: `assignDesks` calls `Seating.assign`, a new `StaffAction` remote calls `Econ.staffAction`, `recompute` records each person's price rate and publishes `StaffData`, `spinOff` carries the stats. The doctor gets a `team` step through a `staffact` DevHook action.

**Tech Stack:** Luau (Roblox), Rojo 7.7, Lune offline tests (`tests/offline/run`), selene, `tools/bas`, Studio MCP for the live checks.

**Spec:** `silicon-startup/docs/superpowers/specs/2026-10-13-manage-staff-design.md` (§3.4, §4, §5, §6, §9 and its five "Amended 13 Oct" notes). Prompt: `silicon-startup/prompts/2026-10-14-manage-staff-phase2.md`.

## Global Constraints

- `CONSTRAINTS.md` rules hold, especially: 2 (Wilz only, restore the save after Play, Studio left in Edit), 3 (every saved number clamped on load), 4 (never edit a test, gate or sim to pass), 8 (files are the truth; check `rojo serve` is running), 10 (**`SiliconCore.server.lua` is at the 200-local limit: no new top-level locals; hang new state off `Econ`**), 11 (rules in pure modules).
- Same price for all three stats: `StaffStats.price(level, personBaseRate)`; `personBaseRate` = that person's UNTRAINED seated rate with every multiplier (spec §3.3 amended). Someone in the waiting line is priced at their unseated base (`TIER_RATE * talentMult`) times the same multipliers.
- Caps: `StaffStats.canTrain(level, stage, talent)`; `stage` = `s.hqLevel` (in Wafers mode this IS the stage, 1-5).
- Pins: `StaffStats.validPin(p)` (`""`, `hq`, `lobby`, `eng`, `studio`, `cafe`, `labs`). A seat's pin key is `h.dept or h.room` (the garage bench's room is `"hq"`).
- Rate limit: 4 actions a second per player, burst 4 (spec §5).
- The remote handler must NOT yield between the check and the cash debit (that is what makes two TRAINs in one frame safe).
- Keeper carry: Skill and Speed = `StaffStats.carried(level, loyalty, 1, talent)`; Loyalty = its level clamped to `StaffStats.cap(1, talent)` (decision 14 Oct: the spec says "Loyalty itself is kept"; the clamp is the same rule as `carried`, G4's spirit). New company stage = 1. Pins reset to `""`.
- Telemetry: training is a cash sink `Telemetry.money(player, "sink", price, "train_" .. stat)` (3 SKUs, low cardinality) and a milestone `Telemetry.mark(player, "trained")`.
- Phase 2 ships dark: no UI, no change to income or seating unless an action is sent.

## Review Focus

1. **A pin to a room the player no longer has** (they had a Cafe, the tower was rebuilt without it): expected, the person sits as unpinned and the pin stays (spec §3.4). Pinned in Task 1 (`pin to a room with no seats`).
2. **A saved `pin` from before a spin-off** (pins are saved; the new company has only the garage): expected, keepers start unpinned. Pinned in Task 2 (`carryKeeper clears the pin`) and Task 3 (spin-off code).
3. **A person above their cap after a spin-off** trying to train: expected, refused "at max", their level kept. Pinned in Task 2 (`above the cap: refused, kept`).
4. **Junk from a real client** (strings for numbers, NaN, a table, nil, a huge id): expected, refused with no state change. Pinned in Task 2 (abuse rows) and Task 4 (the live fuzz round).
5. **No seats at all** (a new company before its first floor; everyone waiting): expected, MOVE to a room refused "no free seat", TRAIN still priced and allowed. Pinned in Task 1 (`no homes`) and Task 2 (`train while waiting`).

## The abuse-case table (written before any code; every row is a test in Task 2 or a live check in Task 4)

| # | Bad action | Server answer | Where it is pinned |
|---|---|---|---|
| A1 | kind not "train"/"move" (nil, number, "TRAIN", table) | refused "unknown action", nothing changes | Task 2 parse rows |
| A2 | id not a whole number 1..1e9 (nil, "1", 0, -1, 1.5, NaN, inf, 1e12, table) | refused "bad id" | Task 2 parse rows |
| A3 | id of nobody on this plot (another player's staff, a fired person) | refused "not yours" (looked up only in the caller's own `s.rigs`) | Task 2 validate; Task 4 live |
| A4 | stat not one of skill/speed/loyalty ("Skill", "money", 1) | refused "bad stat" | Task 2 parse rows |
| A5 | room not a valid pin ("servers", "board", "HQ", " hq", 1) | refused "bad room" | Task 2 parse rows |
| A6 | TRAIN at or above the cap | refused "at max", level kept | Task 2; Task 4 doctor |
| A7 | TRAIN without the cash | refused "need cash" (price returned for the UI), cash kept | Task 2; Task 4 doctor |
| A8 | two TRAINs in the same frame with cash for one | the first passes, the second sees the debited cash and is refused: the handler does not yield between check and debit | Task 2 fuzz (sequential model); Global Constraints |
| A9 | spam (100 actions at once) | 4 a second pass the rate limit, the rest are dropped before any lookup | Task 2 `allow`; Task 4 fuzz SPAM round |
| A10 | MOVE to a room with no free seat (all its seats pinned by others) | refused "no free seat" | Task 1 `freeFor`; Task 2 validate |
| A11 | MOVE to the room they are already pinned to | refused "already there" (no reseat churn) | Task 2 |
| A12 | any action while a spin-off is running (`plot.busy`) | refused "busy" | Task 2 validate |
| A13 | an action while a save is being written | safe: the save builds its data table without yielding before `SetAsync`; an action lands wholly before or after | design (no test can interleave a non-yielding handler) |
| A14 | an action from a player with no session or no plot (joining, leaving) | refused "no plot" | Task 3 code |

---

### Task 1: Seating (pure): pins first, then exactly today's algorithm

**Files:**
- Create: `game/src/ReplicatedStorage/Seating.lua`
- Test: `game/tests/offline/seating.spec.luau`

**Interfaces:**
- Produces: `Seating.assign(people, homes, fits) -> seat, pinnedOk` where `people = { {role: string, pin: string?} }`, `homes = { {room: string, key: string} }`, `fits(role, room) -> boolean`; `seat[i]` = home index or nil; `pinnedOk[i] = true` when person i sits in their pin. `Seating.freeFor(people, homes, key, index) -> number` (seats with that key minus OTHER people pinned to it).

- [ ] **Step 1: Write the failing test** (`tests/offline/seating.spec.luau`)

```lua
-- seating.spec.luau: pins are honoured first; with no pins, seating is exactly what it was (14 Oct 2026)
local Seat = require("../../src/ReplicatedStorage/Seating")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

-- Lune has no Roblox Random: Park-Miller, as savefuzz.spec
local R = {}; R.__index = R
local function rng(seed) return setmetatable({ s = (seed % 2147483646) + 1 }, R) end
function R:int(a, b) self.s = (self.s * 16807) % 2147483647; return a + math.floor(self.s / 2147483647 * (b - a + 1)) end

local ROLES = { "engineer", "designer", "sales", "research", "recruiter" }
local KEYS = { "hq", "lobby", "eng", "studio", "cafe", "labs", "servers" }
local ROOM_OF = { hq = "hq", lobby = "lobby", eng = "office", studio = "studio", cafe = "cafe", labs = "lab", servers = "servers" }
local FIT = { engineer = { office = true, lobby = true }, designer = { studio = true }, sales = { cafe = true },
	research = { lab = true, office = true }, recruiter = { cafe = true } }
local function fits(role, room) return (FIT[role] or {})[room] == true end

-- assignDesks before phase 2, verbatim in shape: list order, fit first, then any
local function oldAssign(people, homes)
	local used, seat = {}, {}
	for i, p in ipairs(people) do
		local pick
		for k, h in ipairs(homes) do if not used[k] and fits(p.role, h.room) then pick = k break end end
		if not pick then for k in ipairs(homes) do if not used[k] then pick = k break end end end
		if pick then used[pick] = true; seat[i] = pick end
	end
	return seat
end

local function world(g, pinShare)
	local homes, people = {}, {}
	for _ = 1, g:int(0, 30) do local key = KEYS[g:int(1, #KEYS)]; table.insert(homes, { room = ROOM_OF[key], key = key }) end
	for _ = 1, g:int(0, 30) do
		local pin = (g:int(1, 100) <= pinShare) and KEYS[g:int(1, 6)] or ""   -- KEYS[1..6]: the valid pins
		table.insert(people, { role = ROLES[g:int(1, #ROLES)], pin = pin })
	end
	return people, homes
end

test("no pins: exactly the old seating, over 3,000 random teams", function()
	local g = rng(1014)
	for case = 1, 3000 do
		local people, homes = world(g, 0)
		local a, b = Seat.assign(people, homes, fits), oldAssign(people, homes)
		for i = 1, #people do assert(a[i] == b[i], ("case %d person %d: %s vs old %s"):format(case, i, tostring(a[i]), tostring(b[i]))) end
	end
end)

test("with pins: no seat twice; as many seated as fit; pins filled up to their room's seats", function()
	local g = rng(2026)
	for case = 1, 3000 do
		local people, homes = world(g, 40)
		local seat, ok = Seat.assign(people, homes, fits)
		local used, seated = {}, 0
		for i = 1, #people do
			if seat[i] then
				assert(not used[seat[i]], ("case %d: seat %d used twice"):format(case, seat[i]))
				used[seat[i]] = true; seated += 1
				if ok[i] then assert(homes[seat[i]].key == people[i].pin, ("case %d: pinnedOk but in the wrong room"):format(case)) end
			end
		end
		assert(seated == math.min(#people, #homes), ("case %d: %d seated of %d people, %d seats"):format(case, seated, #people, #homes))
		local want, got, have = {}, {}, {}
		for _, h in ipairs(homes) do have[h.key] = (have[h.key] or 0) + 1 end
		for i, p in ipairs(people) do
			if p.pin ~= "" then want[p.pin] = (want[p.pin] or 0) + 1; if ok[i] then got[p.pin] = (got[p.pin] or 0) + 1 end end
		end
		for key, n in pairs(want) do
			local expect = math.min(n, have[key] or 0)
			assert((got[key] or 0) == expect, ("case %d: %s has %d pinned seated, want %d"):format(case, key, got[key] or 0, expect))
		end
	end
end)

test("moving one person's pin never moves another PINNED person in a third room", function()
	local g = rng(77)
	for case = 1, 2000 do
		local people, homes = world(g, 50)
		if #people > 0 then
			local before = Seat.assign(people, homes, fits)
			local who = g:int(1, #people)
			local old = people[who].pin
			people[who].pin = KEYS[g:int(1, 6)]
			local after = Seat.assign(people, homes, fits)
			for i, p in ipairs(people) do
				if i ~= who and p.pin ~= "" and p.pin ~= old and p.pin ~= people[who].pin then
					assert(before[i] == after[i], ("case %d: person %d (pinned %s) moved when %d changed %s -> %s"):format(case, i, p.pin, who, old, people[who].pin))
				end
			end
		end
	end
end)

test("deterministic: the same input seats the same way", function()
	local g = rng(5)
	for _ = 1, 500 do
		local people, homes = world(g, 30)
		local a, b = Seat.assign(people, homes, fits), Seat.assign(people, homes, fits)
		for i = 1, #people do assert(a[i] == b[i], "not deterministic") end
	end
end)

test("pin to a room with no seats: seated as unpinned, pin kept by the caller", function()
	local homes = { { room = "office", key = "eng" } }
	local people = { { role = "engineer", pin = "cafe" } }
	local seat, ok = Seat.assign(people, homes, fits)
	assert(seat[1] == 1 and not ok[1], "should sit in the only seat, not as pinned")
end)

test("no homes: nobody seated, no error", function()
	local seat = Seat.assign({ { role = "engineer", pin = "eng" } }, {}, fits)
	assert(seat[1] == nil, "seated with no seats")
end)

test("freeFor: seats of that room minus OTHER people pinned there", function()
	local homes = { { room = "cafe", key = "cafe" }, { room = "cafe", key = "cafe" }, { room = "office", key = "eng" } }
	local people = { { role = "sales", pin = "cafe" }, { role = "sales", pin = "cafe" }, { role = "engineer", pin = "" } }
	assert(Seat.freeFor(people, homes, "cafe", 3) == 0, "both cafe seats are pinned by others")
	assert(Seat.freeFor(people, homes, "cafe", 1) == 1, "person 1's own pin does not count against them")
	assert(Seat.freeFor(people, homes, "eng", 3) == 1, "one free eng seat")
	assert(Seat.freeFor(people, homes, "labs", 3) == 0, "no labs at all")
end)

return T
```

- [ ] **Step 2: Run it to verify it fails**

Run (from `game/`): `~/.rokit/bin/lune run tests/offline/run`
Expected: `FAIL  seating.spec.luau: could not load` (no module yet).

- [ ] **Step 3: Write `src/ReplicatedStorage/Seating.lua`**

```lua
--[[ Seating (14 Oct 2026, Manage Staff phase 2): who sits where. Pure.

	Pass 1, PINS: in list order, each pinned person takes a free seat whose key (the Wafers
	department, or "hq" for the garage bench) is their pin, a seat that fits their job first.
	Pass 2, EVERYONE ELSE, exactly as assignDesks always did: list order, a free seat that
	fits their job, else any free seat. A pinned person whose room had no free seat is
	seated here as unpinned; the caller keeps their pin (spec §3.4).

	Proved offline (seating.spec): with no pins this is the old seating, seat for seat;
	no seat is used twice; pins are filled up to their room's seats; moving one person's
	pin never moves a pinned person in a third room. Unpinned people CAN shift when a pin
	takes their seat: that is the cost of a pin, and they were never promised a room. ]]
local Seating = {}

function Seating.assign(people, homes, fits)
	local used, seat, pinnedOk = {}, {}, {}
	for i, p in ipairs(people) do
		local pin = p.pin
		if type(pin) == "string" and pin ~= "" then
			local pick
			for k, h in ipairs(homes) do if not used[k] and h.key == pin and fits(p.role, h.room) then pick = k break end end
			if not pick then for k, h in ipairs(homes) do if not used[k] and h.key == pin then pick = k break end end end
			if pick then used[pick] = true; seat[i] = pick; pinnedOk[i] = true end
		end
	end
	for i, p in ipairs(people) do
		if not seat[i] then
			local pick
			for k, h in ipairs(homes) do if not used[k] and fits(p.role, h.room) then pick = k break end end
			if not pick then for k in ipairs(homes) do if not used[k] then pick = k break end end end
			if pick then used[pick] = true; seat[i] = pick end
		end
	end
	return seat, pinnedOk
end

-- how many seats of `key` person `index` could still take if they pinned there:
-- every seat of that room, minus the OTHER people already pinned to it
function Seating.freeFor(people, homes, key, index)
	local seats, taken = 0, 0
	for _, h in ipairs(homes) do if h.key == key then seats += 1 end end
	for i, p in ipairs(people) do if i ~= index and p.pin == key then taken += 1 end end
	return seats - taken
end

return Seating
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.rokit/bin/lune run tests/offline/run`
Expected: all pass, including the 7 new `seating.spec` tests.

- [ ] **Step 5: Plant and confirm, then commit**

Plant: in `Seating.assign` pass 1, delete `pinnedOk[i] = true`. Run: the "pins filled" test FAILS. Restore. Then:
```bash
git add src/ReplicatedStorage/Seating.lua tests/offline/seating.spec.luau
git commit -m "Seating: pins first, then exactly the old seating (pure, property-tested)"
```

---

### Task 2: StaffAction (pure): parse, validate, apply, rate limit, StaffData rows, keeper carry

**Files:**
- Create: `game/src/ReplicatedStorage/StaffAction.lua`
- Test: `game/tests/offline/staffaction.spec.luau`

**Interfaces:**
- Consumes: `StaffStats` (passed in: `StaffAction.with(StaffStats)`; no pure module in this repo requires a sibling); `Seating.freeFor` (Task 1) only through `ctx.freeSeats`.
- Produces (`local A = StaffAction.with(StaffStats)`):
  - `A.parse(kind, a, b) -> act | nil, reason`; `act = {kind="train", id, stat} | {kind="move", id, dept}`.
  - `A.validate(ctx, act) -> ok: boolean, reason: string?, price: number?`; `ctx = {busy: boolean, cash: number, stage: number, person: P?, freeSeats: number?}`; `P = {talent, skill, speed, loyalty, pin, priceRate}`.
  - `A.apply(person, act)`: mutates the person (level + 1, or pin = dept). The caller debits the price from `validate`.
  - `A.allow(bucket, now) -> ok: boolean, bucket`.
  - `A.carryKeeper(k, newStage) -> {skill, speed, loyalty, pin = ""}`.
  - `A.row(p, stage) -> table` (one StaffData row).

- [ ] **Step 1: Write the failing test** (`tests/offline/staffaction.spec.luau`)

```lua
-- staffaction.spec.luau: every row of the abuse-case table, the rate limit, the keeper carry,
-- and a fuzz of random action sequences against the rules (14 Oct 2026)
local S = require("../../src/ReplicatedStorage/StaffStats")
local A = require("../../src/ReplicatedStorage/StaffAction").with(S)
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local NAN = 0 / 0
local function person(t) return { talent = t.talent or 1, skill = t.skill or 0, speed = t.speed or 0, loyalty = t.loyalty or 0, pin = t.pin or "", priceRate = t.priceRate or 100 } end
local function ctx(t) return { busy = t.busy or false, cash = t.cash or 1e9, stage = t.stage or 1, person = t.person, freeSeats = t.freeSeats } end

test("A1 A2 A4 A5: junk is refused by parse", function()
	local junkKind = { nil, 1, "TRAIN", "Move", {}, true, "" }
	for i = 1, 7 do local act, why = A.parse(junkKind[i], 1, "skill"); assert(act == nil and why == "unknown action", "kind " .. tostring(junkKind[i])) end
	local junkId = { nil, "1", 0, -1, 1.5, NAN, math.huge, -math.huge, 1e12, {}, true }
	for i = 1, 11 do local act, why = A.parse("train", junkId[i], "skill"); assert(act == nil and why == "bad id", "id " .. tostring(junkId[i])) end
	for _, st in { "Skill", "money", 1, nil, "", "loyalty " } do local act, why = A.parse("train", 3, st); assert(act == nil and why == "bad stat", "stat " .. tostring(st)) end
	for _, d in { "servers", "board", "HQ", " hq", 1, nil, {} } do local act, why = A.parse("move", 3, d); assert(act == nil and why == "bad room", "room " .. tostring(d)) end
	local ok1 = A.parse("train", 3, "speed"); assert(ok1 and ok1.kind == "train" and ok1.id == 3 and ok1.stat == "speed", "a valid train")
	local ok2 = A.parse("move", 1e9, ""); assert(ok2 and ok2.kind == "move" and ok2.dept == "", "a valid unpin")
end)

test("A3 A12: no such person, or a spin-off running", function()
	local act = A.parse("train", 1, "skill")
	local ok, why = A.validate(ctx({ person = nil }), act); assert(not ok and why == "not yours", "nobody")
	ok, why = A.validate(ctx({ person = person({}), busy = true }), act); assert(not ok and why == "busy", "busy")
end)

test("A6 A7: at the cap, and without the cash; the price comes back for the UI", function()
	local act = A.parse("train", 1, "skill")
	local capped = person({ talent = 1, skill = S.cap(1, 1) })
	local ok, why = A.validate(ctx({ person = capped, stage = 1 }), act); assert(not ok and why == "at max", "at the cap")
	local poor = person({ priceRate = 100 })
	local price = S.price(0, 100)
	ok, why, price = A.validate(ctx({ person = poor, cash = price - 1 }), act)
	assert(not ok and why == "need cash" and price == S.price(0, 100), "short by one")
	ok, why, price = A.validate(ctx({ person = poor, cash = S.price(0, 100) }), act)
	assert(ok and why == nil and price == S.price(0, 100), "exactly enough")
end)

test("Review 3: above the cap after a spin-off: refused, level kept", function()
	local p = person({ talent = 4, skill = 9 })   -- Genius cap at stage 1 is 2*1+3 = 5
	local act = A.parse("train", 1, "skill")
	local ok, why = A.validate(ctx({ person = p, stage = 1 }), act)
	assert(not ok and why == "at max" and p.skill == 9, "refused and kept")
end)

test("Review 5: train while waiting for a seat is allowed and priced", function()
	local p = person({ priceRate = 37 })
	local ok, _, price = A.validate(ctx({ person = p }), A.parse("train", 1, "loyalty"))
	assert(ok and price == S.price(0, 37), "waiting people can train")
end)

test("A10 A11: move to a full room, or to the room they are pinned to", function()
	local ok, why = A.validate(ctx({ person = person({}), freeSeats = 0 }), A.parse("move", 1, "cafe")); assert(not ok and why == "no free seat", "full")
	ok, why = A.validate(ctx({ person = person({ pin = "cafe" }), freeSeats = 3 }), A.parse("move", 1, "cafe")); assert(not ok and why == "already there", "same")
	ok = A.validate(ctx({ person = person({ pin = "cafe" }) }), A.parse("move", 1, "")); assert(ok, "unpin always allowed")
	ok = A.validate(ctx({ person = person({}), freeSeats = 1 }), A.parse("move", 1, "eng")); assert(ok, "a free seat")
end)

test("A9: the rate limit lets 4 through at once, then 4 a second", function()
	local bucket, passed = nil, 0
	for _ = 1, 100 do local ok; ok, bucket = A.allow(bucket, 10.0); if ok then passed += 1 end end
	assert(passed == 4, "burst: " .. passed)
	local ok; ok, bucket = A.allow(bucket, 10.24); assert(not ok, "0.24 s later: not yet")
	ok, bucket = A.allow(bucket, 10.26); assert(ok, "0.26 s later: one more")
	ok, bucket = A.allow({ tokens = NAN, at = 0 }, 5); assert(ok == false or ok == true, "a corrupt bucket must not error")
end)

test("apply: train adds one level; move sets the pin", function()
	local p = person({ skill = 2 })
	A.apply(p, A.parse("train", 1, "skill")); assert(p.skill == 3, "level up")
	A.apply(p, A.parse("move", 1, "labs")); assert(p.pin == "labs", "pinned")
end)

test("Review 2: carryKeeper: Skill/Speed by carried(), Loyalty clamped to the new cap, pin cleared", function()
	local k = { talent = 4, skill = 12, speed = 7, loyalty = 9, pin = "cafe" }
	local c = A.carryKeeper(k, 1)
	assert(c.skill == S.carried(12, 9, 1, 4) and c.speed == S.carried(7, 9, 1, 4), "carried")
	assert(c.loyalty == math.min(9, S.cap(1, 4)), "loyalty clamped: " .. tostring(c.loyalty))
	assert(c.pin == "", "pin cleared")
	local z = A.carryKeeper({ talent = 1 }, 1); assert(z.skill == 0 and z.speed == 0 and z.loyalty == 0, "an untrained keeper")
end)

test("row: caps and prices per stat, as the screen will read them", function()
	local r = A.row({ id = 7, name = "Ada", role = "engineer", talent = 3, tier = 2, room = "eng", fit = true, rate = 55,
		skill = 1, speed = 0, loyalty = 2, pin = "eng", priceRate = 40 }, 2)
	assert(r.id == 7 and r.name == "Ada" and r.pin == "eng" and r.rate == 55, "fields")
	assert(r.stats.skill.level == 1 and r.stats.skill.cap == S.cap(2, 3) and r.stats.skill.price == S.price(1, 40), "skill")
	assert(r.stats.loyalty.price == S.price(2, 40), "loyalty priced at its own level")
end)

-- the fuzz: random sequences of valid and junk actions against a model of the server
local Rng = {}; Rng.__index = Rng
local function rng(seed) return setmetatable({ s = (seed % 2147483646) + 1 }, Rng) end
function Rng:int(a, b) self.s = (self.s * 16807) % 2147483647; return a + math.floor(self.s / 2147483647 * (b - a + 1)) end
local KINDS = { "train", "move", "TRAIN", nil, 1 }
local STATS = { "skill", "speed", "loyalty", "money" }
local DEPTS = { "", "hq", "eng", "cafe", "labs", "servers" }

test("fuzz: cash never negative, spent = sum of prices, no level past its cap, ids never change", function()
	local g = rng(14102026)
	for run = 1, 300 do
		local team, ids = {}, {}
		for i = 1, g:int(1, 12) do team[i] = person({ talent = g:int(1, 5), priceRate = g:int(1, 5000) }); ids[i] = 100 + i end
		local cash, spent, charged = g:int(0, 2e6), 0, 0
		local start = cash
		local stage = g:int(1, 5)
		for _ = 1, 200 do
			local act = A.parse(KINDS[g:int(1, 5)], (g:int(1, 10) == 1) and 999 or ids[g:int(1, #ids)], (g:int(1, 2) == 1) and STATS[g:int(1, 4)] or DEPTS[g:int(1, 6)])
			if act then
				local idx
				for i, id in ipairs(ids) do if id == act.id then idx = i end end
				local p = idx and team[idx]
				local ok, _, price = A.validate(ctx({ person = p, cash = cash, stage = stage, freeSeats = g:int(0, 2) }), act)
				if ok then
					if act.kind == "train" then cash -= price; spent += price; charged += price end
					A.apply(p, act)
				end
			end
			assert(cash >= 0, ("run %d: cash went negative"):format(run))
		end
		assert(start - cash == spent and spent == charged, ("run %d: spent %d, cash fell %d"):format(run, spent, start - cash))
		for i, p in ipairs(team) do
			for _, st in { "skill", "speed", "loyalty" } do assert(p[st] <= S.cap(stage, p.talent), ("run %d person %d %s %d past cap"):format(run, i, st, p[st])) end
			assert(ids[i] == 100 + i, "an id changed")
		end
	end
end)

return T
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/.rokit/bin/lune run tests/offline/run`
Expected: `FAIL  staffaction.spec.luau: could not load`.

- [ ] **Step 3: Write `src/ReplicatedStorage/StaffAction.lua`**

```lua
--[[ StaffAction (14 Oct 2026, Manage Staff phase 2): what a TRAIN or MOVE request may do. Pure.

	Every rule the StaffAction remote enforces lives here, so the abuse-case table in the
	phase 2 plan is a list of offline tests (staffaction.spec), not a hope. The server only
	looks the person up in the CALLER's own staff list, calls validate, debits the price it
	returns, and calls apply; it must not yield in between (two TRAINs in one frame).
	No pure module here requires a sibling, so StaffStats is passed in: StaffAction.with(S). ]]
local StaffAction = {}

StaffAction.RATE = 4          -- actions a second per player (spec §5)
StaffAction.BURST = 4
StaffAction.MAX_ID = 1e9

function StaffAction.with(S)
	local A = {}
	local STAT = {}
	for _, st in S.STATS do STAT[st.id] = true end

	function A.parse(kind, a, b)
		if kind ~= "train" and kind ~= "move" then return nil, "unknown action" end
		if type(a) ~= "number" or a ~= a or a < 1 or a > StaffAction.MAX_ID or a ~= math.floor(a) then return nil, "bad id" end
		if kind == "train" then
			if type(b) ~= "string" or not STAT[b] then return nil, "bad stat" end
			return { kind = "train", id = a, stat = b }
		end
		if not S.validPin(b) then return nil, "bad room" end
		return { kind = "move", id = a, dept = b }
	end

	function A.price(p, stat) return S.price(p[stat] or 0, p.priceRate or 0) end

	function A.validate(ctx, act)
		if ctx.busy then return false, "busy" end
		local p = ctx.person
		if not p then return false, "not yours" end
		if act.kind == "train" then
			if not S.canTrain(p[act.stat] or 0, ctx.stage, p.talent) then return false, "at max" end
			local price = A.price(p, act.stat)
			local cash = tonumber(ctx.cash) or 0
			if cash ~= cash or cash < price then return false, "need cash", price end
			return true, nil, price
		end
		if act.dept == (p.pin or "") then return false, "already there" end
		if act.dept ~= "" and (tonumber(ctx.freeSeats) or 0) < 1 then return false, "no free seat" end
		return true
	end

	function A.apply(p, act)
		if act.kind == "train" then
			p[act.stat] = S.clampLevel(p[act.stat]) + 1
		else
			p.pin = act.dept
		end
	end

	-- a token bucket: BURST at once, then RATE a second; a corrupt bucket starts fresh
	function A.allow(bucket, now)
		local tokens, at = StaffAction.BURST, now
		if type(bucket) == "table" and type(bucket.tokens) == "number" and bucket.tokens == bucket.tokens
			and type(bucket.at) == "number" and bucket.at == bucket.at then
			tokens = math.min(StaffAction.BURST, bucket.tokens + math.max(0, now - bucket.at) * StaffAction.RATE)
		end
		if tokens < 1 then return false, { tokens = tokens, at = now } end
		return true, { tokens = tokens - 1, at = now }
	end

	-- what a keeper starts the new company with (Loyalty kept, clamped like the rest)
	function A.carryKeeper(k, newStage)
		local loyalty = S.clampLevel(k.loyalty)
		return {
			skill = S.carried(k.skill, loyalty, newStage, k.talent),
			speed = S.carried(k.speed, loyalty, newStage, k.talent),
			loyalty = math.min(loyalty, S.cap(newStage, k.talent)),
			pin = "",
		}
	end

	-- one row of the StaffData attribute (the TEAM screen, phase 3, reads it)
	function A.row(p, stage)
		local stats = {}
		for _, st in S.STATS do
			stats[st.id] = { level = S.clampLevel(p[st.id]), cap = S.cap(stage, p.talent), price = A.price(p, st.id) }
		end
		return { id = p.id, name = p.name, role = p.role, talent = p.talent, tier = p.tier, room = p.room,
			fit = p.fit == true, rate = p.rate, pin = p.pin or "", stats = stats }
	end

	return A
end

return StaffAction
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.rokit/bin/lune run tests/offline/run`
Expected: all pass (the 11 new `staffaction.spec` tests included).

- [ ] **Step 5: Plant and confirm, then commit**

Plant each, run, see the named test FAIL, restore:
1. In `validate`, change `cash < price` to `cash < price - 1`: "A6 A7" fails, and the fuzz's "cash never negative" fails.
2. In `parse`, delete `or a ~= math.floor(a)`: "A1 A2 A4 A5" fails (1.5).
```bash
git add src/ReplicatedStorage/StaffAction.lua tests/offline/staffaction.spec.luau
git commit -m "StaffAction: the abuse-case table as rules (pure), with an action fuzz"
```

---

### Task 3: The server: pinned seating, the remote, StaffData, telemetry, the keeper carry

**Files:**
- Modify: `game/src/ServerScriptService/SiliconCore.server.lua` (line 63 area: requires; `recompute` ~1227; `assignDesks` ~1462; the `if Econ then` remotes block ~2720; `spinOff` ~2959)
- Modify: `game/src/ServerScriptService/DevHook.lua` (a `staffact` action after `staffstat`)

**Interfaces:**
- Consumes: `Seating.assign`, `Seating.freeFor` (Task 1); `StaffAction.with(StaffStats)` (Task 2).
- Produces: `Econ.staffAction(player, kind, a, b) -> ok, reasonOrKind, price`; the `SVRemotes.StaffAction` RemoteEvent (client sends `(kind, id, statOrDept)`, server answers `{ok, why, kind, id}` to that client); the player attribute `StaffData` (JSON array of `A.row`); `r.priceRate` on every staff entry; DevHook `staffact` (`"train:i:stat"` / `"move:i:dept"`, i = list position).

- [ ] **Step 1: The requires (no new top-level local)**

At line 63, after `if Econ then Econ.StaffStats = require(...) end`, add:
```lua
if Econ then
	Econ.Seating = require(game:GetService("ReplicatedStorage"):WaitForChild("Seating"))             -- v8 phase 2 (pure)
	Econ.StaffAction = require(game:GetService("ReplicatedStorage"):WaitForChild("StaffAction")).with(Econ.StaffStats)
end
```

- [ ] **Step 2: `assignDesks`: pins first through Seating**

Replace the loop head of `assignDesks` (from `local used = {}` through the `if pick then used[pick] = true end` line) with:
```lua
	-- v8 phase 2: pins first (Seating, tested offline: with no pins it is the old seating, seat for seat)
	local people, keyed = {}, {}
	for i, r in ipairs(s.rigs) do people[i] = { role = (r.rig and r.rig:GetAttribute("Role")) or "engineer", pin = r.pin } end
	for k, h in ipairs(homes) do keyed[k] = { room = h.room, key = h.dept or h.room } end
	local Seat = (Econ and Econ.Seating) or require(ReplicatedStorage:WaitForChild("Seating"))
	local seatOf = Seat.assign(people, keyed, function(role, room) return ((Econ and Econ.FIT[role]) or {})[room] and true or false end)
	for i, r in ipairs(s.rigs) do
		local role = people[i].role
		local fitSet = (Econ and Econ.FIT[role]) or {}
		local pick = seatOf[i]
		local h = pick and homes[pick]
```
Everything from `local home = h and h.cf` down is unchanged.

- [ ] **Step 3: `recompute`: each person's price rate, and StaffData**

Inside the per-person loop, before `if r.seated then`, add:
```lua
		-- v8 phase 2: the untrained seated rate (×F below) prices this person's training (spec §3.3)
		r.baseV = CFG.TIER_RATE[r.tier or 1] * talentMultOf(r) * ((r.seated and r.fit and Econ) and Econ.FIT_MULT or 1) * (r.seated and (r.eff or 1) or 1)
```
After `local F = ...` and `s.rate = ...`, add:
```lua
	if Econ and Econ.StaffAction then
		local rows = {}
		for _, r in ipairs(s.rigs or {}) do
			r.priceRate = (r.baseV or 0) * F
			table.insert(rows, Econ.StaffAction.row({ id = r.id, name = r.rig and r.rig:GetAttribute("PersonName"), role = r.rig and r.rig:GetAttribute("Role"),
				talent = r.talent, tier = r.tier, room = r.dept or r.room, fit = r.fit, skill = r.skill, speed = r.speed, loyalty = r.loyalty,
				pin = r.pin, priceRate = r.priceRate,
				rate = r.seated and math.floor(r.baseV * ((Econ.StaffStats and Econ.StaffStats.mult("skill", r.skill)) or 1) * F + 0.5) or 0 }, s.hqLevel or 1))
		end
		local json = game:GetService("HttpService"):JSONEncode(rows)
		if player:GetAttribute("StaffData") ~= json then player:SetAttribute("StaffData", json) end
	end
```
(`s.hqLevel` is set a few lines above `F` in the same function; move this block after that line if needed.)

- [ ] **Step 4: `Econ.staffAction` and the remote**, inside the existing `if Econ then` block that creates `SpinConfirm` (~2720), after `SpinCancel`:
```lua
	--[[ v8 MANAGE STAFF phase 2: TRAIN and MOVE. Every rule is StaffAction (pure, the abuse-case
		table as tests); this only looks the person up in the CALLER's own staff, validates,
		debits and applies, with no yield in between (two TRAINs in one frame see the debit). ]]
	Econ.staffAction = function(player, kind, a, b)
		local s, plot, cash = sessions[player.UserId], plotOf(player), cashOf(player)
		if not s or not plot or not cash then return false, "no plot" end
		local act, why = Econ.StaffAction.parse(kind, a, b)
		if not act then return false, why end
		local idx
		for i, r in ipairs(s.rigs or {}) do if r.id == act.id then idx = i break end end
		local r = idx and s.rigs[idx]
		local free
		if act.kind == "move" and act.dept ~= "" then
			local people, keyed = {}, {}
			for i, rr in ipairs(s.rigs) do people[i] = { pin = rr.pin } end
			for k, h in ipairs(deskHomes(s, plot)) do keyed[k] = { room = h.room, key = h.dept or h.room } end
			free = Econ.Seating.freeFor(people, keyed, act.dept, idx)
		end
		local ok, reason, price = Econ.StaffAction.validate({ busy = plot.busy == true, cash = cash.Value, stage = s.hqLevel or 1,
			person = r, freeSeats = free }, act)
		if not ok then return false, reason, price end
		if act.kind == "train" then
			cash.Value -= price
			Econ.StaffAction.apply(r, act)
			Telemetry.money(player, "sink", price, "train_" .. act.stat)
			Telemetry.mark(player, "trained")
			recompute(player)
		else
			Econ.StaffAction.apply(r, act)
			assignDesks(player)
		end
		return true, act.kind, price
	end
	local staffRemote = remote("StaffAction")
	staffRemote.OnServerEvent:Connect(function(player, kind, a, b)
		local s = sessions[player.UserId]
		if not s then return end
		local pass
		pass, s.staffBucket = Econ.StaffAction.allow(s.staffBucket, os.clock())
		if not pass then return end
		local ok, why = Econ.staffAction(player, kind, a, b)
		staffRemote:FireClient(player, { ok = ok, why = (not ok) and why or nil, kind = ok and why or nil, id = type(a) == "number" and a or nil })
	end)
```
Check `assignDesks` and `deskHomes` are defined above this block (they are, ~1411 and ~1462). `r` passed as `person` works because a staff entry has `talent/skill/speed/loyalty/pin/priceRate`.

- [ ] **Step 5: `spinOff`: carry the stats**

In the keeper loop, change `table.insert(keep, { talent = r.talent, who = r.who })` to:
```lua
			table.insert(keep, { talent = r.talent, who = r.who, skill = r.skill, speed = r.speed, loyalty = r.loyalty })
```
(Confirm `Prog.chooseKeepers` returns the staff ENTRIES; if it returns `{entry = ...}` wrappers, read `r.entry.skill` etc. instead.) In the spawn loop, after `spawnStaff(player, plot, i, k.talent, k.who)`:
```lua
		local e = s.rigs[#s.rigs]
		if e and Econ and Econ.StaffAction then
			local c = Econ.StaffAction.carryKeeper(k, 1)   -- v8: Loyalty keeps their training (StaffStats.carried)
			e.skill, e.speed, e.loyalty, e.pin = c.skill, c.speed, c.loyalty, c.pin
		end
```

- [ ] **Step 6: DevHook `staffact`** (after the `staffstat` branch):
```lua
		elseif action == "staffact" then
			-- v8 phase 2 (Studio): "train:i:stat" or "move:i:dept" through the REAL action code
			-- (Econ.staffAction), i = list position. The doctor's team step uses it.
			local kind, i, x = tostring(arg):match("^(%a+):(%d+):(%a*)$")
			local r = i and s.rigs and s.rigs[tonumber(i)]
			if not (kind and r and Econ and Econ.staffAction) then return "usage: staffact train:i:stat | move:i:dept" end
			local cash0 = (cashOf(player) or { Value = 0 }).Value
			local ok, why, price = Econ.staffAction(player, kind, r.id, x)
			return { ok = ok, why = why, price = price, cashSpent = cash0 - (cashOf(player) or { Value = 0 }).Value,
				id = r.id, skill = r.skill, speed = r.speed, loyalty = r.loyalty, pin = r.pin, room = r.dept or r.room, seated = r.seated, rate = s.rate }
```

- [ ] **Step 7: Checks and commit**

Run: `~/.rokit/bin/lune run tools/bas check` (selene catches a forward reference or an unknown global).
Expected: 0 errors, all tests pass.
```bash
git add src/ServerScriptService/SiliconCore.server.lua src/ServerScriptService/DevHook.lua
git commit -m "Staff actions on the server: pinned seating, the StaffAction remote, StaffData, telemetry, the keeper carry"
```

---

### Task 4: Live: the doctor's `team` step, the remote fuzz, the save round trip

**Files:**
- Modify: `game/src/ServerScriptService/GameDoctor.server.lua` (a `team` step before `errors`)
- Modify: `game/tools/fuzz_remotes.luau` (a StaffAction round with real-shaped actions)

**Interfaces:**
- Consumes: DevHook `staffact`, `staffstat`, `cash`, `state` (Task 3).

- [ ] **Step 1: The doctor step**, before `step("errors", ...)`:
```lua
	-- v8 Manage Staff phase 2: train and move through the real action code
	step("team", function()
		local st = sv:Invoke("scenario", player, "state") or {}
		check("someone to train", (st.staff or 0) >= 1, "BLOCKER", st.staff or 0, ">= 1")
		if (st.staff or 0) < 1 then return end
		sv:Invoke("cash", player, 1e12)
		sv:Invoke("staffstat", player, "1:skill:0")
		local t = sv:Invoke("staffact", player, "train:1:skill")
		check("train charges and raises", type(t) == "table" and t.ok and t.skill == 1 and t.cashSpent == t.price and t.price >= 10, "BUG",
			type(t) == "table" and ("ok=%s skill=%s spent=%s price=%s"):format(tostring(t.ok), tostring(t.skill), tostring(t.cashSpent), tostring(t.price)) or tostring(t),
			"ok, level 1, spent = price >= 10")
		sv:Invoke("staffstat", player, "1:skill:30")
		local m = sv:Invoke("staffact", player, "train:1:skill")
		check("refused past the cap", type(m) == "table" and not m.ok and m.why == "at max" and m.cashSpent == 0, "BUG",
			type(m) == "table" and tostring(m.why) or tostring(m), "at max, nothing spent")
		sv:Invoke("staffstat", player, "1:skill:0")
		local u = sv:Invoke("staffact", player, "move:1:hq")
		local back = sv:Invoke("staffact", player, "move:1:")
		check("move pins and seats", type(u) == "table" and ((u.ok and u.pin == "hq" and u.room == "hq") or u.why == "no free seat") and type(back) == "table" and back.pin == "", "BUG",
			type(u) == "table" and ("ok=%s why=%s pin=%s room=%s"):format(tostring(u.ok), tostring(u.why), tostring(u.pin), tostring(u.room)) or tostring(u),
			"pinned to hq and sitting there (or refused: no free seat), then unpinned")
		local junk = sv:Invoke("staffact", player, "train:1:money")
		check("junk refused", type(junk) == "table" and not junk.ok and junk.cashSpent == 0, "BUG", type(junk) == "table" and tostring(junk.why) or tostring(junk), "refused, nothing spent")
	end)
```
(The doctor's setup snapshot restores the save afterwards, so the cash and levels it sets are undone.)

- [ ] **Step 2: The fuzz round** — append to `tools/fuzz_remotes.luau`, before the report is printed:
```lua
-- v8 (14 Oct): StaffAction with REAL-shaped actions: real kinds, ids that are not ours, junk stats/rooms, spam
do
	local sa = RS:FindFirstChild("SVRemotes") and RS.SVRemotes:FindFirstChild("StaffAction")
	if sa then
		local before = cash()
		local calls = { { "train", 1, "skill" }, { "train", 999999, "skill" }, { "train", 1, "money" }, { "move", 1, "servers" },
			{ "move", 1, "board" }, { "train", 0 / 0, "skill" }, { "train", -1, "speed" }, { "move", 1.5, "cafe" }, { "train", "1", "skill" } }
		for _, c in ipairs(calls) do sa:FireServer(c[1], c[2], c[3]) end
		for _ = 1, SPAM do sa:FireServer("train", 1, "skill") end
		task.wait(WATCH)
		report.staffAction = { cashBefore = before, cashAfter = cash(), fired = #calls + SPAM }
	end
end
```
Expected live: `cashAfter >= cashBefore` minus at most 4 real training prices (the burst; ids 1.. may not exist, then 0).

- [ ] **Step 3: Run it all live** (Studio, Wilz, Rojo serving, Play; restore the save after; Studio left in Edit):
1. **Fingerprint** in Edit (the game-doctor skill, PR mode step 2).
2. **Play: the doctor** (full run).
   - Expected: `team` all pass.
   - Expected: no new BLOCKER or BUG.
3. **Same Play: the fuzz** (`fuzz_watch_server.luau` in the Server datamodel, then `fuzz_remotes.luau` in the Client).
   - Expected: no server errors from StaffAction.
   - Expected: the cash drop is within one burst.
4. **Same Play: the save round trip.**
   - Via `staffact`: train person 1's Skill and pin them to `hq`.
   - DevHook `save`.
   - Read `DataStoreService:GetDataStore(<the game's store>):GetAsync("1688749216")` on the Server: `skill[1]` and `pin[1]` match.
   - Stop and start Play: `state.staffStats` shows the same id, level and pin.
5. **Stop Play.** Restore Wilz's save, `restore(1688749216)`. Leave Studio in Edit.

- [ ] **Step 4: Commit**
```bash
git add src/ServerScriptService/GameDoctor.server.lua tools/fuzz_remotes.luau
git commit -m "Doctor team step and a StaffAction fuzz round (live: train, cap, move, junk)"
```

---

### Task 5: The sims, the docs, the gate, the review, the PR

- [ ] **Step 1: Run the sims.**
   - Run `lune run tools/bas sim staff_sim`: G1–G4 PASS.
   - Run `lune run tools/bas baseline diff`: no change. Phase 2 changes no formula. G3 already models a player who trains greedily.
   - If anything moved, STOP and ask Luke.
- [ ] **Step 2: Update the docs.**
   - `docs/features/hiring-talent.md`:
     - Files: `Seating`, `StaffAction`, the remote, `StaffData`.
     - Prove it: `seating.spec`, `staffaction.spec`, the doctor `team` step.
     - Gotchas: pins vs unpinned shifting, the 4/s limit, Loyalty clamped at a spin-off.
   - `dev-tools.md`: DevHook `staffact`.
   - Then remap the line references in `SiliconCore`, `DevHook` and `GameDoctor`. Check every ref by its content, not by shifting numbers.
   - Run `bas map check`: green.
- [ ] **Step 3: Pass the gate.**
   - Commit the docs **before** the fingerprint, so the report is newer than the last commit.
   - Run `bas checkup pr <report> <fingerprint> --post`.
   - Run `bas risk --label`: needs-luke (save, economy, gameplay).
- [ ] **Step 4: Fresh reviewer (Opus, read-only).**
   - Give it, in this order: `CONSTRAINTS.md`, then the abuse-case table above, then the diff.
   - Rule: every finding names a concrete failure.
   - Fix what is real. Re-review the fixes. If a fix touches `src/`, re-run the gate.
- [ ] **Step 5: Open the PR.**
   - Start with the intent card: should do / must not break / measured / not measured.
   - Under "measured", list the doctor `team` step, the fuzz numbers and the save round trip.
   - Label `needs-luke`. No auto-merge.
