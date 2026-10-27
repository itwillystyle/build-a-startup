# Client Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace "tap WRITE CODE" with clients who walk up to your door, a job you code by holding the button at your laptop, and a hand-over that pays (first client = a 5x wow), plus contextual teaching and the five first-minute fixes.

**Architecture:** All rules live in one pure, offline-tested module (`Clients.lua`: queue, patience, job progress, coders, pay, the goal line). A server module (`ClientsServer.lua`) owns the NPCs, the hold remote, the hand-over and the cash, and is wired into `SiliconCore` from one `do` block (the file is at the 200-local limit). The HUD turns WRITE CODE into a hold button (2C); a new client script plays the payout (3A/3B); `GuideClient` becomes a one-line goal with floor arrows (4A). Two PRs: judges first (CONSTRAINTS rule 4), then the feature, stacked.

**Tech Stack:** Roblox Luau, Rojo 7.7 (files are the truth), Lune offline tests (`~/.rokit/bin/lune run tests/offline/run`), selene, `lune run tools/bas ...`, Studio MCP for live checks (Wilz only).

**Spec:** `silicon-startup/docs/superpowers/specs/2026-10-16-client-loop-design.md` (approved 16 Oct, with Luke's pick 1A, 2C, 3A + 3B first client, 4A). Mocks: `silicon-startup/ui/2026-10-16-client-loop/mockups.html`.

## Global Constraints

- CONSTRAINTS.md applies in full. Rule 3: prefer no new save fields (the queue is session-only); any new saved field gets a sanitizer, a `savecontract.spec` entry and a `savefuzz.spec` case. Rule 4: judges change in their own PR. Rule 10: no new top-level local in `SiliconCore.server.lua`. Rule 11: tested logic in pure modules. Rule 12: palette colours only; Neon only on lights, screens, effects. Rule 17: built screens match the picked mocks.
- Studio tests as Wilz (`1688749216`) only. After every Play: `require(game.ServerScriptService.DevScenarios:Clone()).restore(1688749216)`, 4 s after Stop. **Exception until Luke says "restore Wilz":** Wilz's save is throwaway; do not restore over it without asking.
- Phone first: 844 x 390, tap targets 44 px or more, nothing below 14 px, nothing in the top-left 230 x 58 Roblox bar or under the jump button.
- Server owns job progress, patience and pay; the client only draws.
- Player-facing copy, verbatim from the spec/mocks: first ask "A to-do app!"; hand-over line "Just what I needed!"; lost line "Too slow..."; button states "HOLD TO CODE", "CODING n%", "GO TO LAPTOP", "HAND IT OVER", "LAUNCH!"; pop word "SHIPPED!"; goals "Code the to-do app", "Take it to your client", "Too busy! Hire a coder", "Upgrade your HQ", "Recruit on the street"; toasts "Your coder takes the small jobs.", "Tap your sign to rename it."; BIG client bubble "BIG". No em dashes in player text.
- Pacing targets: first client served by 0:15; first hire by 0:40; garage to lobby 0:55-1:10; later milestones (lobby, first floor above the lobby, `hq_2`..`hq_5`, first spin-off) no later than the `c58ef2c` bot baseline, within 10%.
- Telemetry: money kinds `client` and `client_tip` (source); events `client_served` (extra `{"who", "you"|"coder"|"big"}`), `client_lost`; mark `first_big_client`. Funnel list unchanged.
- Words: "the lobby" = Wafers level 2. `hq_2`..`hq_5` = stages (`WaferPlan.STAGE_AT = {5, 9, 13, 18}`).

## Review Focus

1. **A player who dies, respawns or leaves while holding or carrying** must not keep a stuck "carrying" state or an NPC left behind. (Task 5: `onCharacterRemoving` clears hold; leaving destroys the plot's clients.)
2. **Holding the button away from the laptop** must not progress the job (a phone player walks while their thumb stays down). (Task 2 test `no progress when not at the laptop`.)
3. **Two players in one server**: clients belong to one plot; a player can never be paid for, or hand over to, another plot's client. (Task 5 live check with the two-plot dev scenario; Task 2 keeps state per queue.)
4. **A spin-off or `releasePlot` mid-job** leaves no orphan client rigs and resets the queue to the garage rules without replaying the tutorial. (Task 5 live check; Task 2 test `returning save gets no wow`.)
5. **Phone load**: never more than 3 client rigs per plot, and the server updates their bars at 4 Hz or less, not every frame. (Task 2 test `queue never exceeds 3`; Task 5 rate.)

---

### Task 0: Branches and the baseline bot run

**Files:** none changed. Output: `silicon-startup/tuning/client-loop-baseline-c58ef2c.txt` (outside git).

- [ ] **Step 1:** `git fetch && git checkout -b client-loop-judges origin/main` in `game/`; confirm `git rev-parse --short HEAD` = `c58ef2c`.
- [ ] **Step 2:** Make sure Studio matches the files (Rojo running; SourceHash compare as in the 16 Oct publish: 137/137, 0 differ).
- [ ] **Step 3:** Play as Wilz, then in the Server datamodel: `game.ServerScriptService.SiliconCore.SVDev:Invoke("scenario", p, "hq:1")` and `SVDev:Invoke("bot", p, "20 1")`. Poll `SVDev:Invoke("botlog", p)` every few minutes until the line `SPIN-OFF` appears (or TIMEOUT).
Expected: lines `HQ n staff ...` with minutes for every level, and one `SPIN-OFF`.
- [ ] **Step 4:** Save the full botlog to the baseline file. Stop Play. (Do not restore; see Global Constraints.)

### Task 1: The judges PR (telemetry spec, doctor check, bot mode)

**Files:**
- Modify: `tests/offline/telemetry.spec.luau:34-36` (KINDS)
- Modify: `src/ServerScriptService/GameDoctor.server.lua` (new step after `setup`)
- Modify: `src/ServerScriptService/DevHook.lua:194-477` (bot)

**Interfaces:**
- Consumes (only if present at runtime; on main they are absent): `core.clients` = the table Task 5 produces (`ClientsServer`), and the dev scenario `"fresh"` from Task 5.
- Produces: doctor step `"first client"`; bot mode that plays the client loop when `core.clients` exists.

- [ ] **Step 1:** Add `client = true, client_tip = true` to `KINDS`. Run the suite. Expected: all pass (nothing uses them yet).
- [ ] **Step 2:** Doctor step `step("first client", fn)`: call `sv:Invoke("scenario", player, "fresh")`; if it returns an error containing "unknown scenario", `info("first client", "skipped", "no client loop on this build")` and return. Otherwise check, with a 20 s timeout: a client rig exists for the plot (`check("client arrives", ...)`), `SVDev:Invoke("clients", player, "serve")` (Task 5 dev hook) ends with `player.leaderstats.Cash` up by at least `Clients.TUNE.FLOOR * Clients.TUNE.WOW` (`check("first client pays the wow", ...)`; require `Clients` only after `"fresh"` succeeded, since it does not exist on main), and `Shipped` attribute is true. Severity BUG for each.
- [ ] **Step 3:** Bot: if `core.clients` exists, replace the once-a-second `writeCode` tap with: when `core.clients.state(player).carrying`, PivotTo beside the front client; else if a job is waiting, PivotTo beside `plot.laptop` and call `core.clients.hold(player, true)`; release when nothing to code. Take BIG clients. Log `[BOT] ... client served (you|big)` on each pay. Without `core.clients`, behave exactly as today.
- [ ] **Step 4:** `selene src` and the offline suite pass. Live: the doctor `full` run on this branch passes with `first client: skipped`.
- [ ] **Step 5:** Commit `judges: client-loop kinds, doctor first-client check, bot client mode (no-ops on main)`; push; open PR "Judges for the client loop" explaining rule 4. Gate as usual (`bas checkup pr ... --post`). Luke merges it.

### Task 2: `Clients.lua`, the pure rules (queue, patience, jobs, coders, pay)

**Files:**
- Create: `src/ServerScriptService/Clients.lua`
- Test: `tests/offline/clients.spec.luau` (style of `momentum.spec.luau`: `test(name, fn)`, `assert`, `return T`; require `"../../src/ServerScriptService/Clients"`)
- Branch: `client-loop` from `client-loop-judges`.

**Interfaces:**
- Produces:
  - `Clients.TUNE` (starting values; Task 10 tunes): `FLOOR = 8`, `SECONDS = 3`, `TIP = 0.35`, `WOW = 5`, `BIG_MULT = 5`, `BIG_NEED = 4`, `BIG_CHANCE = 0.12`, `PLAYER_SPEED = 1`, `CODER_SPEED = 0.4`, `OFF_ROLE = 1 / 1.5`, `FIRST_NEED = 3`, `NEED = 4`, `PATIENCE = 30`, `BIG_PATIENCE = 45`, `CAP = 3`, `SPAWN_GARAGE = 9`, `SPAWN_LOBBY = 7`, `SPAWN_MIN = 4`.
  - `Clients.new(opts: {first: boolean, seed: number}) -> Q` where `Q = { line: {Client}, carrying: Client?, t: number, nextAt: number, served: number, lost: number, first: boolean }` and `Client = { id: number, kind: "first"|"normal"|"big", app: string, need: number, done: number, patience: number?, left: number?, by: "you"|"coder"? }`. With `first = true` the line starts with one `"first"` client asking `"A to-do app!"` (no patience).
  - `Clients.cap(level: number) -> number` (2 in the garage, 3 from the lobby; never above `TUNE.CAP`).
  - `Clients.spawnEvery(level: number, stage: number) -> number`.
  - `Clients.coderSpeed(tier: number, role: string) -> number` (`CODER_SPEED * (1 + 0.25 * (tier - 1))`, times `OFF_ROLE` unless role is `"engineer"`).
  - `Clients.tick(Q, dt: number, ctx) -> {Event}` with `ctx = { level, stage, rate, holding: boolean, atLaptop: boolean, coders: {number} }` and `Event = { kind: "arrive"|"shipped"|"served"|"lost", client: Client, pay: number?, tip: number? }`. Spawns, drains patience (not for `"first"`, not while you are coding that client), progresses the job you hold (front non-carried client), lets each coder speed work one non-BIG job from the front (coder-finished jobs are `"served"` at once with base pay, no tip), emits `"shipped"` and sets `Q.carrying` when your job completes.
  - `Clients.handOver(Q, ctx) -> Event?` (`"served"`, with `pay` and `tip`; nil when not carrying).
  - `Clients.pay(client: Client, rate: number, patienceLeft: number) -> (pay: number, tip: number)`: base `max(FLOOR, rate * SECONDS)`, times `WOW` for `"first"`, `BIG_MULT` for `"big"`; tip `floor(base * TIP)` only when `by == "you"` and patience left is at least half (the first client has no tip).

- [ ] **Step 1: Write the failing tests** (one `test` each; values from TUNE):
  - `first save starts with one first client`: `#Q.line == 1`, kind `"first"`, `need == TUNE.FIRST_NEED`, `patience == nil`.
  - `returning save gets no wow`: `Clients.new({first = false})` has no `"first"` client; its first served pay equals `max(FLOOR, rate*SECONDS)`.
  - `holding at the laptop ships the first app in about 3 s`: tick 3.0 s with `holding, atLaptop` → one `"shipped"` event, `Q.carrying ~= nil`.
  - `no progress when not at the laptop`: holding, `atLaptop = false`, 10 s → `done == 0`.
  - `letting go pauses, it does not reset`: hold 1.5 s, release 2 s, `done` unchanged.
  - `the first hand-over pays the wow`: `handOver` → `pay == FLOOR * WOW`, `tip == 0`.
  - `a fast hand-over pays a tip`, `a slow one does not`: patience left 0.8 vs 0.3.
  - `patience runs out: lost, no cash`: a normal client, 31 s, nobody codes → `"lost"`, `Q.lost == 1`.
  - `patience waits while you code that client`.
  - `coders work small jobs and pay base only`: `coders = {Clients.coderSpeed(1, "engineer")}`, not holding → `"served"` with `tip == 0`.
  - `coders skip BIG clients`.
  - `engineers code faster than other roles`.
  - `queue never exceeds 3` (and 2 in the garage): tick 120 s at level 1 and level 9 with nobody working.
  - `BIG clients only from the lobby`: 500 spawns at level 1 → no `"big"`.
  - `pay scales with income`: `rate = 100` → base `300`.
- [ ] **Step 2:** `lune run tests/offline/run`. Expected: FAIL in `clients.spec.luau` (module not found).
- [ ] **Step 3:** Implement `Clients.lua` (pure: no `game`, no `Instance`; randomness from a seeded `Random`-like LCG kept in `Q`, so tests are repeatable).
- [ ] **Step 4:** Run the suite. Expected: all pass.
- [ ] **Step 5:** Commit `clients: pure queue, patience, jobs, coders and pay`.

### Task 3: The goal line rules (`Clients.goal`)

**Files:** Modify `src/ServerScriptService/Clients.lua`; Test `tests/offline/clients.spec.luau`.

**Interfaces:**
- Produces: `Clients.goal(st) -> {key: string, title: string, target: string}?` with `st = { served, carrying, waiting, staff, cap, level, cash, upgradeCost, freeSeat, recruitTaught, tutorial: boolean }` and `target` one of `"laptop"`, `"client"`, `"hirePad"`, `"hqPad"`, `"sidewalk"`. Order:
  1. tutorial and `served == 0` and not carrying → `{key="code", title="Code the to-do app", target="laptop"}`
  2. tutorial and carrying and `served == 0` → `{key="deliver", title="Take it to your client", target="client"}`
  3. `staff == 0` and `waiting >= 2` → `{key="hire", title="Too busy! Hire a coder", target="hirePad"}`
  4. `level == 1` and `staff >= cap` and `waiting >= 2` → `{key="upgrade", title="Upgrade your HQ", target="hqPad"}`; also when `cash >= upgradeCost` at level 1
  5. `level >= 2` and `freeSeat` and `waiting >= 2` and not `recruitTaught` → `{key="recruit", title="Recruit on the street", target="sidewalk"}`
  6. otherwise nil (the caller falls through to `Journey.task`, and when that is nil too, to `{key="serve", title="Serve your clients", target="client"}` if anyone waits).

- [ ] **Step 1:** Tests: one per row above, plus `after the lobby there is always a goal` (level 2, nothing to buy, one waiting → non-nil from the caller's fallback, tested via `Clients.goal` + a fake `Journey.task` returning nil).
- [ ] **Step 2:** Run. Expected: FAIL (`goal` nil).
- [ ] **Step 3:** Implement `Clients.goal`.
- [ ] **Step 4:** Run. Expected: pass.
- [ ] **Step 5:** Commit `clients: the goal line, taught when needed`.

### Task 4: Generated company names

**Files:** Create `src/ServerScriptService/Names.lua`; Test `tests/offline/names.spec.luau`; Modify `SiliconCore.server.lua` (fresh save gets `s.name = Names.generate(userId)` where the session is created in `onJoin`, inside an existing block).

**Interfaces:**
- Produces: `Names.generate(seed: number) -> string` (two words, from two lists of about 20 each, e.g. "Rocket" + "Labs"; no player text, so no filter needed).

- [ ] **Step 1:** Tests: `same seed same name`, `two words, 3-20 characters`, `100 seeds give at least 40 different names`.
- [ ] **Step 2:** Run: FAIL. **Step 3:** Implement. **Step 4:** Run: pass.
- [ ] **Step 5:** Commit `names: a generated company name for new saves`.

### Task 5: `ClientsServer.lua`: NPCs, hold, hand-over, pay

**Files:**
- Create: `src/ServerScriptService/ClientsServer.lua` (non-pure; `return function(core) ... end`, the DevHook pattern)
- Modify: `src/ServerScriptService/SiliconCore.server.lua`: one `do ... end` block after `wirePlot` that requires `ClientsServer` with a `core` table; `writeCode` (1372) no longer pays per tap (WRITE CODE is now the hold); `shipFirstProduct` (1352) keeps `s.shipped` + `Telemetry.step("first_ship")`, drops its neon float and popup (3B replaces them), and is called by ClientsServer on the first hand-over; the beat driver (~4094-4140) no longer waits for 3 taps but for `s.shipped`.
- Modify: `src/ServerScriptService/DevScenarios.lua`: scenario `"fresh"` (session to new-save state in memory only, plot back to garage, first client spawned; never writes the DataStore) and dev hook `clients` (`"serve"` = run the first client to paid, `"state"` = JSON of the queue).

**Interfaces:**
- Consumes: `Clients` (Tasks 2-3), `Names` (Task 4), `StaffRig.build(roleKey, index) -> model, hum`, `StaffRig.animate(...)`, `Telemetry.money/event/mark/step`, core fields `sessions, plotOf, cashOf, openDoor, shipFirstProduct, popup, fmt`, plot fields `plot.laptop, plot.desk, plot.g(x, y, z), plot.hq.doorL/doorR`.
- Produces: `core.clients = { hold(player, on: boolean), state(player) -> {carrying, waiting, front}, reset(player), goalState(player) -> st }`; remote `CodeHold` (client → server, boolean); remote `ClientPaid` (server → client: `{pay, tip, wow: boolean, at: Vector3}`); player attributes `CodeProgress` (0-1), `AtLaptop` (bool), `Carrying` (bool), `ClientsWaiting` (number); client rig attributes `Patience` (0-1) and `Ask` (string).

- [ ] **Step 1:** Per-plot queue spots: three points just outside the garage door (`plot.g(...)` offsets from the door header; the lobby uses the lobby entrance). Clients walk in with PivotTo steps like TalentDrop (rigs are anchored), never on the HIRE pad, the lift or the chase routes.
- [ ] **Step 2:** A server loop at 0.1 s per player calls `Clients.tick`, with `atLaptop` = character within 12 studs of `plot.laptop`, `coders` from seated `s.rigs` (`tier`, rig attribute `"Role"`). Bubble (1A): a BillboardGui on each client's head with the app icon + ask text and a patience bar (green, then gold under half, red under a quarter); BIG uses the gold bubble with "BIG". Bars and attributes update at 4 Hz.
- [ ] **Step 3:** `CodeHold` handler: ignore toggles under 0.1 s apart; hold stops on release, on leaving laptop range (progress just stops), on CharacterRemoving and on leave. Each hold second also pushes the product bar like about two taps did (`s.work += team * Econ.CODE_WORK * 2 * dt`) once shipped. The first hold that starts a job calls `Telemetry.step(player, "first_code")`.
- [ ] **Step 4:** Hand-over: when `Carrying` and the character is within 8 studs of the client being carried for, call `Clients.handOver`, add cash (`cash.Value += pay` with `Telemetry.money(player, "source", pay, "client")` on the next line; tip likewise with `"client_tip"`), fire `ClientPaid`, play the client's hop and "Just what I needed!", walk them away, destroy the rig. First hand-over: call `core.shipFirstProduct`, `Telemetry.step(player, "first_ship")` happens there. `Telemetry.event(player, "client_served", 1, {{"who", who}})`; the first BIG client served calls `Telemetry.mark(player, "first_big_client")`; lost: `"client_lost"` and the bubble shows "Too slow..." for 2 s.
- [ ] **Step 5:** First client: on a new save (no `shipped`, `spinoffs == 0`, no launch on record), spawn it at join, open the door for it (`core.openDoor(plot)`), and keep the door open. Returning saves and spin-offs: `Clients.new({first = false})`.
- [ ] **Step 6:** Cleanup: on leave, `releasePlot` and spin-off, destroy every client rig of the plot and reset the queue.
- [ ] **Step 7:** Live checks in Studio (Wilz), each read back with `execute_luau`:
  - `scenario fresh` → one client rig at the door with `Ask == "A to-do app!"`; `Shipped == false`.
  - `clients serve` → Cash up by `FLOOR * WOW`; `Shipped == true`; funnel lines `[FUNNEL] first_code`, `[FUNNEL] first_ship` in Output; `[MONEY] source client`.
  - Hold with the character 30 studs away → `CodeProgress` stays 0.
  - Spin-off mid-job (`scenario spinoff` on a public save, or `releasePlot` via leaving) → 0 client rigs left for that plot.
  - Two-plot check via the existing two-player dev path if one exists; if not, record "not tested (two players)" per Luke's standing note.
- [ ] **Step 8:** `selene src`, suite (including `telemetry.spec`: every `cash.Value +=` has its `Telemetry.money`). Commit `clients: NPCs at the door, hold to code, hand-over and pay`.

### Task 6: HUD: the hold button (2C) and the payout (3A, 3B)

**Files:**
- Modify: `src/StarterPlayer/StarterPlayerScripts/HudClient.client.lua:254-449` (WriteCode button, `setLaunch`)
- Create: `src/StarterPlayer/StarterPlayerScripts/ClientFxClient.client.lua`

**Interfaces:**
- Consumes: remotes `CodeHold`, `ClientPaid`, `ProductReady`, `PickMarket`; attributes `CodeProgress`, `AtLaptop`, `Carrying`, `Shipped`.
- Produces: nothing other tasks call.

- [ ] **Step 1:** The WriteCode button (2C): `InputBegan` touch/mouse → `CodeHold:FireServer(true)`, `InputEnded` → `false` (keep `MouseButton1Click` only for LAUNCH when the old path still needs it). Labels: "HOLD TO CODE" at rest, "CODING n%" while `CodeProgress` is between 0 and 1, with a deep-green fill from the left; blue "GO TO LAPTOP" when a job waits and `AtLaptop` is false; gold "HAND IT OVER" while `Carrying`. Width 260 px at 844 wide, height 56 px or more. PC: holding the laptop's key does the same.
- [ ] **Step 2:** LAUNCH!: `setLaunch` shows a separate gold LAUNCH! button to the right of WRITE CODE instead of relabelling it (one slow pulse; it is the only thing that loops).
- [ ] **Step 3:** `ClientFxClient` on `ClientPaid`: normal (3A) = "+$X" pop over the client, "+$Y TIP" pop under it 0.35 s later, 6 coins fly to the cash counter, the counter bumps. `wow` (3B) = rays + a tilted "SHIPPED!" stamp centre for about 1.4 s, then a big "+$X" that flies to the cash counter (about 2.2 s total), then the 3A coins. Use `Moment.lua` / `UIKit` tokens; overshoot only on `-- reward` lines (uistyle rule).
- [ ] **Step 4:** `lune run tests/offline/run` (uistyle.spec passes); live in Studio: hold → `CodeProgress` rises and the label reads "CODING n%"; release → it stops; `ClientPaid` with `wow = true` shows the stamp (capture or read the GUI tree). Run `lune run tools/ui_audit` → 0 text under 14 px, 0 taps under 44 px.
- [ ] **Step 5:** Commit `hud: hold to code, hand it over, the payout and the first-client wow`.

### Task 7: The goal line (4A) and teaching order

**Files:**
- Modify: `SiliconCore.server.lua` `refreshObjective` (1680): before the old early branches, call `Clients.goal(core.clients.goalState(player))`; when nil, keep `Journey.task(st)`; when that is nil and a client waits, the `"serve"` goal. Remove the old `"code"`/"Write your first app" and `"watch"` branches. `ObjectivePos` = the target's position (laptop, front client, HIRE pad, HQ pad, sidewalk spot).
- Modify: `src/StarterPlayer/StarterPlayerScripts/GuideClient.client.lua` (`showGoal` 545): one pill top-centre (icon + `ObjectiveText`, Fredoka 22, no sub line, no cost line), nothing else from the old card.
- Create: `src/StarterPlayer/StarterPlayerScripts/GoalPathClient.client.lua`: 4-6 gold floor chevrons (client-side parts, palette gold, not Neon) from the character toward `ObjectivePos`, refreshed at 4 Hz, hidden when within 8 studs or when `ObjectiveText` is empty.

- [ ] **Step 1:** Live: `scenario fresh` → `ObjectiveText == "Code the to-do app"`; after `clients serve` with carrying staged → "Take it to your client"; with 2 waiting and no staff → "Too busy! Hire a coder"; at the lobby with nothing to buy → a goal is still set.
- [ ] **Step 2:** One message at a time: after the first hire, one toast "Your coder takes the small jobs." and no SEATS FULL (Task 9).
- [ ] **Step 3:** Suite, selene; commit `goal: one line at the top and arrows on the floor`.

### Task 8: No popups in the first two minutes

**Files:**
- Modify: `SiliconCore.server.lua` beat driver (~4094-4140): remove the `askName` wait (4113); `buildUnlocked` and the BUILD slots follow the first hire after 1.5 s.
- Modify: `src/ServerScriptService/Wafers.lua` name sign (`nameSign` ~105): a ProximityPrompt "RENAME" on the sign from the lobby on; it fires `askName` with the current name. After the garage-to-lobby moment, one world popup at the sign: "Tap your sign to rename it." (once per session).
- Modify: the style gate in the build (SiliconCore ~2140-2165): on the lobby build, set `s.hqPath = "W_"` silently; open the picker (`AskPath`) when building **level 3** while `level == 2`; a different pick rebuilds levels 1-2 with the new finish (the `hq:N` scenario's rebuild path). Picker cards in `WaferClient` sized so each tap target is 44 px or more on 844 x 390.
- Modify: `src/StarterPlayer/StarterPlayerScripts/TalentRevealClient.client.lua:310-318`: on a first session (`Returning` false), wait until `HQLevel >= 2` before showing.
- No change: the Daily Reward card already waits for `HQLevel >= 2` on a first session (`DailyClient.client.lua` `unlocked()` :151). Confirm it live in Step 1.

- [ ] **Step 1:** Live: `scenario fresh`, serve, hire, upgrade to the lobby; no `AskName` or `AskPath` fired (watch with a temporary listener in the Client datamodel); the sign shows the generated name; RENAME opens the name box; building level 3 opens the picker; picking Terrace restyles the lobby (TowerFinish colours on the lobby parts).
- [ ] **Step 2:** Suite, selene; commit `onboarding: no popups before the lobby; rename on the sign; style pick at level 3`.

### Task 9: The first-minute bug fixes

**Files:** `SiliconCore.server.lua`: `refreshHqPad` (2042-2108), `updateHirePad` hireLabel texts (1585-1603), the popup at 1949.

- [ ] **Step 1:** `refreshHqPad` with no session: return before touching the label (it stays empty) instead of "HQ MAXED"; never call `hqCostOf(nil, ...)`. Live: join a fresh save and read `plot.hqLabel.Text` in the first second → `""`, then "UPGRADE HQ · $..." once loaded.
- [ ] **Step 2:** World signs name only the thing: hire pad label "HIRE" (+ price when not free), no "SEATS FULL", "TEAM FULL", "HIRING HAPPENS ON THE STREET" or "WAITING FOR A SEAT" sentences (the goal line carries those). Delete the duplicate popup at 1949.
- [ ] **Step 3:** Live, the lobby: count visible text items above the lobby floor that are instructions (BillboardGuis/SurfaceGuis with more than 3 words) → 0; only the goal line instructs.
- [ ] **Step 4:** Suite, selene; commit `fix: no HQ MAXED on a new save, no stacked lobby text, no SEATS FULL after the first hire`.

### Task 10: Tune to the pacing targets

**Files:** `src/ServerScriptService/Clients.lua` (`TUNE` only).

- [ ] **Step 1:** Bot on the branch (`hq:1`, `bot 20 1`, which now plays the client loop). Compare with the Task 0 baseline: lobby, first floor above the lobby, `hq_2`..`hq_5`, spin-off. Expected: each no later than baseline + 10%.
- [ ] **Step 2:** A scripted "obvious human" run via `scenario fresh` + dev hooks (walk-to times as PivotTo + fixed delays of 2 s per trip): first client served by 0:15, first hire by 0:40, lobby 0:55-1:10.
- [ ] **Step 3:** Change only `TUNE` values until both pass; the offline suite still passes (tests read values from `TUNE`). Record each run in `silicon-startup/tuning/client-loop-tuning.md`.
- [ ] **Step 4:** Commit `clients: tuned to the pacing targets` with the before/after table in the message.

### Task 11: Docs, gate, look review, PR

**Files:** Create `docs/features/client-loop.md` (feature page format of `core-loop.md`, with `**Last verified:** date sha`); update `docs/features/README.md`, `core-loop.md` (tap → hold), `player-loop.md` (new kinds/events); `CHECKPOINT-2026-10-13.md` top section.

- [ ] **Step 1:** `lune run tools/bas map check` passes.
- [ ] **Step 2:** Gate: SourceHash collect in Edit → `grab.py` → `silicon-startup/doctor/`; fresh Play; doctor `full` → `done`; save `DoctorReport`; `bas checkup pr <report> <fingerprint> --post`. Expected: PASS, with `first client` checks passing (not skipped).
- [ ] **Step 3:** Look review: a fresh reviewer compares the built screens (doctor screenshots or captures) with `mock-1A`, `mock-2C`, `mock-3A`, `mock-3B`, `mock-4A` and the five rules; each difference named; Critical/Important fixed with a check.
- [ ] **Step 4:** Final whole-branch review (most capable model); fix pass per the executing skill.
- [ ] **Step 5:** PR "Clients at the door: the new core loop" (stacked on the judges PR), intent card, mock vs built side by side. Merge and publish stay Luke's.
- [ ] **Step 6 (Luke):** after publish, wipe Wilz (as on 16 Oct) and record a fresh phone run; "done" = the spec's Done-when list.

---

## Amendment, 17 Oct (after Luke's fresh-account playtest on v607)

Review: `silicon-startup/playtests/2026-10-17_00-41-14/notes.md`. Luke picked **B** for where clients wait from the lobby on (a front-desk counter inside the lobby, a rope-line queue), skipping mocks. "Step 1" = Tasks 7-9 below, each with its check; Tasks 10-11 unchanged after it.

- **Task 7 (as planned) + reuse:** the goal is one line top-centre (spec 4A); the guide's existing ground ring and beam from the player to `ObjectivePos` are the floor path (no new chevron script). The `product` goal is shown (it was hidden).
- **Task 7b, the reception counter (B):** from the lobby on, a counter at the back of the lobby room (the side nearest the centre-hall desk; lobby room x -23..23, z 15.3..54 plot-local, entrance x -7..7 at z 54); clients come in through the entrance and queue from the counter toward the door. Garage (level 1) keeps the door line. Check: a doctor/live check that every queue spot at levels 1, 2, 5 is clear of building parts (no part within 1.5 studs of a client's standing box except floor).
- **Task 7c, launches later:** no product work and no LAUNCH before the lobby (level 2); the first ready app is taught by the goal line "Your app is ready: LAUNCH it" (no clock on the first, as today). Test: income-loop work gate in a pure helper.
- **Task 8 (as planned) + coach tips:** no coach tip before the lobby; fix the BAG tip repeating (clearing a tip without GOT IT must also reset `s.tipAt`).
- **Task 9 (as planned) + two:** LAUNCH! moves above WRITE CODE (it sat under the CAR button); the "Drive to The Residences" goal only when the next home is affordable (journey.spec changes with it, flagged in the PR).
