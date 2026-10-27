# Bob, the first boss investor: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** New players get a 16 s story intro: Bob laughs them out and kicks them out, and they vow revenge. Bob's taped-up building waits downtown, and "PROVE BOB WRONG" drives them to floor 13. There a 17 s payoff pays the Series A, and a BOB'S TOOTHPICK trophy appears in their HQ.

**Architecture:**
- **Rules** live in pure modules, tested offline in Lune:
  - Journey: the goal card, the floor-13 task, the save flags
  - Progression: the payout
  - BobScript: both cutscene timelines as data
- **The server** owns money, flags, Bob's building, the cast templates and the trophy.
- **The client** plays each cutscene locally with one scene player (BobSceneClient) that reads BobScript every frame. It also shows the winner-only open door and dizzy Bob.

**Tech Stack:** Luau, Rojo 7.7 (file → Studio), Lune offline tests, selene, the game doctor (Studio MCP).

**Spec:** `silicon-startup/docs/superpowers/specs/2026-10-25-bob-first-boss-investor-design.md`. Approved by Luke 25 Oct. Sections 3f and 5b are binding.

**Storyboard (the look to match):** `silicon-startup/ui/storyboards/p5-bob/` (option A + D). The shot times in `cartoon.js` are the source for BobScript's numbers.

## Global Constraints

- Work on branch `bob-intro` in a worktree `silicon-startup/game-bob`, based on origin/main (dcbe807 or later).
- Never commit to main. Never merge or publish: Luke says "merge", and Luke presses Alt+P.
- **Intro:** new saves only, never when `Returning` is true. Option A. Length 15-17 s (storyboard: 16.2 s), never over 20 s.
- **SKIP from frame 1.** Only the SKIP button, or a tap on touch, skips the intro. Keys and clicks do not (spec 5b-1). Skipping goes straight to the end state.
- **The player can't move during the intro.** Controls come back on the last frame or on skip.
- **Camera hand-back is always `Enum.CameraType.Custom` + the humanoid.** Never restore a stored Scriptable camera.
- **Reduce Motion** (`UIKit.reducedMotion()` read every frame): no shake, no camera push inside a shot, hard cuts stay. Every camera line carries `-- motion: camera` and reads `UIKit.reducedMotion(` within 20 lines above it (`motionguard.spec`).
- **The server owns money and flags.** No remote may pay or set `bobPaid`. Clients only play, report telemetry, and draw their own view.
- **Payout:** the best phone Series A, as in spec 5b-2:
  - `amount = capWindfall("seriesPush", niceMoney(niceMoney(max(200*hq, rate*(20+12*8))*3)*1.5), nextGoal)`
  - plus the item `"frontpage"`
- **Only saves with `jr.bobArc`** see "PROVE BOB WRONG", Bob's text and the payoff (spec 5b-3).
  - `jr.bobArc` and `jr.bobPaid` are in `Journey.J.FLAGS`.
  - A spin-off never clears them.
- **Goal card:** floors, not HQ (spec 5b-4).
  - Title: `PROVE BOB WRONG`
  - Sub: `Floor N of 13 · his door opens at 13`
  - HQ 4 = floor 13.
- **No tobacco anywhere.** Bob's prop is a gold toothpick.
- **Exact words** (copy verbatim):
  - Intro: `Can I get an offer?` · `HA! An OFFER?` · `HAHAHA!` · `He will rue the day.`
  - Bob's text: `...Ok. I may have been hasty. Come to my office.`
  - Task: `Go to Bob's office`
  - Payoff: `What are YOU doing here?` · `W-WHAT?!` · `Take it! TAKE IT ALL!` · `PROVED WRONG!`
  - Toast: `SERIES A CLOSED · x3`
  - Taped door touched: `Bob isn't taking meetings... yet.`
  - Trophy label: `BOB'S TOOTHPICK`
- **Code delivery:** files only. Every file is UTF-8 (pre-commit hook). selene 0 errors. `lune run tests/offline/run` all pass before every commit.
- **Budgets:** plaza view stays under 500k tris / 400 draws (#81). Bob's building uses the far-hiding rule (OfficeCullClient style).
- **Commit messages** end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A player leaves or crashes mid-payoff.**
   - Expected: the money and `bobPaid` were already saved when the server triggered the payoff, so a rejoin never replays it or pays twice.
   - Pinned by Task 1 `payoff not due once paid` and Task 5 (pay before firing the cutscene).
2. **A spin-off after beating Bob.**
   - Expected: the next company's floor-13 task is the ordinary phone Series A, and the trophy stays.
   - Pinned by Task 1 `after a spin-off a paid save gets the phone Series A`.
3. **The player's avatar can't be cloned** (`CreateHumanoidModelFromDescription` errors or times out).
   - Expected: the intro still plays with a plain blocky stand-in, and never hangs on a black screen.
   - Pinned by Task 6 step "fallback rig" + live check.
4. **SKIP at any moment** (second 0, mid-kick, the last frame).
   - Expected: the same end state every time: camera Custom, controls on, cast destroyed, goal card up, no orphan GUI.
   - Pinned by Task 3 `the end frame is the hand-off` + Task 6 one `finish()` path + the doctor step in Task 10.
5. **Two players at Bob's door, only one has beaten him.**
   - Expected: the other still sees tape, still collides with the door, and touching it never triggers a payoff for them.
   - Pinned by Task 1 `payoff not due without the arc / below floor 13` + Task 7 (client-only door).

---

### Task 1: Journey rules for Bob (pure)

**Files:**
- Modify: `game/src/ServerScriptService/Journey.lua`
  - `J.FLAGS` (line 219)
  - `J.task` (around line 111)
  - `J.milestone` (around line 142)
- Test: `game/tests/offline/journey.spec.luau` (add cases)

**Interfaces:**
- Produces:
  - `J.FLAGS` now includes `"bobArc"` and `"bobPaid"`.
  - New `st` fields: `st.bobArc: boolean`, `st.bobPaid: boolean`, `st.level: number` (floor; already exists).
  - `J.BOB_FLOOR = 13`
  - `J.bobGoal(st) -> { title, sub, bob: number (0..1) } | nil`: nil unless `st.bobArc and not st.bobPaid and (st.level or 1) < J.BOB_FLOOR`.
  - `J.milestone(st)` returns `J.bobGoal(st)`'s title/sub/bob, keeping the normal `cost`/`unlock` of the milestone it replaces.
  - `J.task(st)` at the HQ 4 stage, when `st.bobArc and not st.bobPaid and not st.seriesA`, returns `{ key = "bob", title = "Go to Bob's office", sub = "He wants to talk. Bring your numbers.", target = "bob" }`.
  - `J.bobPayoffDue(st) -> boolean`: `bobArc and not bobPaid and not seriesA and hq >= 4`.

- [ ] **Step 1: Write the failing tests** in `journey.spec.luau`:
  - `bob flags survive cleanFlags`: `J.cleanFlags({ bobArc = true, bobPaid = true, junk = true })` → has bobArc and bobPaid, no junk.
  - `goal card reads PROVE BOB WRONG on floor 7`: st `{ bobArc = true, level = 7, hq = 2, msLevel = 9, msCost = 1000 }` → title `"PROVE BOB WRONG"`, sub `"Floor 7 of 13 · his door opens at 13"`, `bob == 7/13`, cost `1000`.
  - `no Bob goal without the arc`: same st with `bobArc = nil` → title starts with `"LEVEL"`.
  - `no Bob goal once paid` (bobPaid = true, level 7) → normal title.
  - `no Bob goal from floor 13`: level 13 → normal title.
  - `floor-13 task is Go to Bob's office`: `{ bobArc = true, hq = 4, level = 13 }` → key `"bob"`, title `"Go to Bob's office"`, target `"bob"`.
  - `after a spin-off a paid save gets the phone Series A`: `{ bobArc = true, bobPaid = true, hq = 4 }` → key `"seriesa"`.
  - `payoff not due once paid`, `payoff not due without the arc`, `payoff not due below floor 13 (hq 3)`, `payoff due at hq 4 with the arc` → `J.bobPayoffDue` false, false, false, true.
- [ ] **Step 2: Run** `lune run tests/offline/run` (from `game-bob`). Expected: the new cases FAIL (`bobGoal`/`bobPayoffDue` nil, flags dropped).
- [ ] **Step 3: Implement** the Interfaces above in `Journey.lua`. Keep Journey free of requires. Use `·` (U+00B7) in the sub, as the file already does in its other copy.
- [ ] **Step 4: Run** `lune run tests/offline/run`. Expected: all pass, 0 failed.
- [ ] **Step 5: Commit** `feat(journey): Bob's goal card, floor-13 task and save flags`.

### Task 2: The payout (pure) and niceMoney moved

**Files:**
- Modify: `game/src/ServerScriptService/Progression.lua`
  - add `P.niceMoney`
  - add `P.bobPayout`
- Modify: `game/src/ServerScriptService/Phone.lua:318`
  - delete the local `niceMoney`
  - use `Prog.niceMoney` (Prog is already required at line 336; move the require above line 318)
- Test: `game/tests/offline/progression.spec.luau`

**Interfaces:**
- Produces:
  - `P.niceMoney(n: number) -> number`: Phone's current body, unchanged.
  - `P.bobPayout(rate: number, hq: number, nextGoal: number?) -> (amount: number, item: string)`. Constraint formula, `item = "frontpage"`.
  - `P.BOB_INTEREST = 8`

- [ ] **Step 1: Failing tests:**
  - `bobPayout is the pushed interest-8 Series A`: for rate 50, hq 4, nextGoal nil → `amount == P.niceMoney(P.niceMoney(math.max(800, 50*(20+96))*3)*1.5)`, item `"frontpage"`.
  - `bobPayout respects the seriesPush cap`: nextGoal 10000 → `amount <= math.floor(10000 * P.CAPS.seriesPush)`.
  - `niceMoney keeps Phone's rounding`: pin 3 values taken by running the old local on 1234, 98765, 4321000 before you move it.
- [ ] **Step 2: Run** the tests. Expected: FAIL (bobPayout nil).
- [ ] **Step 3: Implement.** Move the function; Phone's behaviour must not change.
- [ ] **Step 4: Run.** Expected: all pass.
- [ ] **Step 5: Commit** `feat(progression): Bob's payout; niceMoney shared`.

### Task 3: BobScript, both cutscenes as data (pure)

**Files:**
- Create: `game/src/ReplicatedStorage/BobScript.lua`
- Test: `game/tests/offline/bobscript.spec.luau`

**Interfaces:**
- Produces:
  - `BobScript.LINES`: a table of every exact string from Global Constraints, keyed by short ids (`offer`, `haOffer`, `haha`, `rue`, `text`, `task`, `whatHere`, `what`, `takeIt`, `proved`, `toast`, `taped`, `trophy`).
  - `BobScript.length(name: "intro"|"payoff") -> number`
  - `BobScript.at(name, t: number, reduced: boolean) -> Frame`, where Frame =
    `{ shot: number, cam: { anchor: string, offset: Vector3, look: Vector3, fov: number }, shake: number, actors: { [id]: { anchor: string, pos: Vector3, rot: number, pose: string, face: string, visible: boolean } }, bubbles: { { actor: string, text: string, k: number } }, fx: { { text: string, anchor: string, pos: Vector3, k: number } }, door: number (0 shut..1 open), tape: number (0 on..1 gone), lid: number, glow: number, handoff: number (0..1) }`
  - `BobScript.cues(name, t0, t1) -> { string }`: sound cue ids whose time is in `(t0, t1]`. Ids: `music`, `laugh`, `boing`, `thud`, `money`, `victory`.
  - Anchors are names only. The client turns them into world CFrames (Task 4 produces them):
    - `board`: Bob's boardroom
    - `door`: outside Bob's door
    - `street`: the road beside it
    - `garage`: the player's own laptop
  - Actor ids: `hero`, `bob`, `inv1`, `inv2`.
  - Poses: `stand`, `gesture`, `laugh`, `walk`, `kick`, `fly`, `lie`, `sit`, `cheer`, `holdChart`, `throw`.
  - Faces: `neutral`, `hope`, `laugh`, `shock`, `sad`, `determined`, `smug`, `dizzy`, `grin`.

  Timing comes from the storyboard. Intro shots: 0-3.4, 3.4-6.2, 6.2-9.0, 9.0-10.4, 10.4-12.0, 12.0-16.2; kick 6.3, land 7.25, door shut 7.9-8.1, laptop 12.2, vow bubble 13.2, hand-off 15.2-15.8. Payoff: storyboard D, with the same numbers as `cartoon.js` `payoffAt`/`camPayoff`.

- [ ] **Step 1: Failing tests** (`bobscript.spec.luau`):
  - `intro is 15 to 17 s and payoff is at most 20 s`
  - `intro words are exact`: the bubble texts seen over a 0.1 s sweep, in order, equal `{LINES.offer, LINES.haOffer, LINES.haha, LINES.rue}`.
  - `hero's faces go hope, sad, shock, dizzy, sad, determined`: the distinct faces in order over a 0.1 s sweep.
  - `shake only on the kick, and never reduced`: `shake > 0` somewhere in 6.3-6.8 with reduced false; `shake == 0` at every sample with reduced true.
  - `reduced: the camera holds still inside a shot`: for every shot, `cam.offset` and `cam.look` at its start and its last sample are equal when reduced.
  - `one shot per range, hard cuts`: `at(t).shot` is non-decreasing, with 6 intro shots and 7 payoff shots.
  - `the end frame is the hand-off`: `at(name, length, false).handoff == 1`; hero face `determined` (intro) / `grin` (payoff).
  - `cues fire once`: summing `cues("intro", t, t+1/60)` over 0..length gives each of `music`, `laugh`, `boing`, `thud` exactly once.
  - `no tobacco words`: no string in `LINES` contains `cigar`, `cigarette`, `smoke` or `vape`.
- [ ] **Step 2: Run.** Expected: FAIL (module missing).
- [ ] **Step 3: Implement** BobScript as keyframe tables plus a small evaluator: linear/eased interpolation between keys, and a shot table for the camera. The camera's `offset`/`look` are relative to its anchor. Pure, with only `Vector3` from Roblox globals (the offline globals already provide it).
- [ ] **Step 4: Run.** Expected: all pass.
- [ ] **Step 5: Commit** `feat(bob): BobScript, the intro and payoff timelines`.

### Task 4: Bob's building, the cast and the anchors (server)

**Files:**
- Create: `game/src/ServerScriptService/BobBuilding.lua`
- Modify: `game/src/ServerScriptService/Downtown.lua` (call `BobBuilding.build(parent)` where downtown builds; place it on the HQ 2 drive to The Residences)
- Modify: `game/src/ServerScriptService/StaffRig.lua` only if a helper is needed. Prefer building on `StaffRig.build` + `setOutfit`.

**Interfaces:**
- Produces, in Workspace: `SiliconValley.BobCapital` (Model) with:
  - `Sign` ("BOB CAPITAL", gold)
  - `Door` (Part, server state: always shut, CanCollide true)
  - `Tape` (two crossed yellow parts)
  - `Board` (the boardroom: long table, window, chairs)
  - `CurbSeat` (Attachment, where the winner sees dizzy Bob)
  - `Trigger` (non-collide Part in front of the door, used by Task 5)
- Produces, attributes on `BobCapital`: `AnchorBoard`, `AnchorDoor`, `AnchorStreet` (CFrame). BobScript's `board`/`door`/`street` anchors resolve to these. `garage` is the player's plot laptop: `plot pivot * (0,4,-9)`, as in IntroClient.
- Produces, in ReplicatedStorage: `BobCast` (Folder) with `Bob`, `Inv1`, `Inv2` R15 models (anchored templates the client clones):
  - Bob: wide suit body (body width/depth scale ~1.5), dark suit + red tie, black sunglasses part named `Sunglasses`, gold toothpick part named `Toothpick`, slicked dark hair.
  - Each head has a front `SurfaceGui` named `Face` (Task 6 draws expressions on it).
  - `Chart`: a board with a SurfaceGui reading `REVENUE`, with axes and a green line the client draws from 0 to 1 (`holdChart` pose). It shows drawn data, not real data (spec 3e).
- Produces: `BobBuilding.trophy(plotModel) -> Model`: a stand with the gold toothpick and a `BOB'S TOOTHPICK` label (used by Task 8).

- [ ] **Step 1:** Build the model. No offline test (services).
- [ ] **Step 2: Live check** (Studio Play via MCP, Wilz, the verify-game skill):
  - `BobCapital` exists downtown, its door is taped, and the anchors are set.
  - The doctor's `world` step still passes, with no overlap with roads or Downtown buildings.
  - Plaza view tris/draws are under 500k/400 with far-hiding on.
  - Record the numbers.
- [ ] **Step 3: Commit** `feat(bob): Bob's building downtown and the cast templates`.

### Task 5: Server wiring: flags, Bob's text, the payoff trigger, the money

**Files:**
- Modify: `game/src/ServerScriptService/SiliconCore.server.lua`
  - load: set `s.jr.bobArc = true` when this load created a NEW save (the same condition that leaves `Returning` false). Never set it on an existing save.
  - `st` build around line 1627: add `bobArc`, `bobPaid`, `level` (if not present)
  - the `seriesa` block around line 1725: skip `Phone.seriesA` when `Journey.bobPayoffDue(st)`; instead send Bob's text once via `Phone.notice(player, "bob", "Bob", "Bob Capital", LINES.text)`
  - target `"bob"` → `posOf(BobCapital.Trigger)`
  - spin-off around line 3206: leave `bobArc`/`bobPaid` alone (comment why)
- Create: remote `BobPayoff` (server → client: `{ amount, item }`), remote `BobIntro` (client → server: telemetry only, `"start"|"skip:<sec>"|"end"`).
- Modify: `BobBuilding.lua`: `Trigger.Touched` → server checks `Journey.bobPayoffDue(st)` for that player. Then, in this order:
  1. set `jr.bobPaid = true` and `jr.seriesA = true`
  2. pay `Prog.bobPayout(s.rate, hq, api.nextGoal(player))` to cash, with `Telemetry.money(... "investor")`
  3. grant `"frontpage"`
  4. call `onSeriesA`
  5. save-dirty
  6. fire `BobPayoff`
  7. `Telemetry.event(player, "bob_payoff", amount)`

  Debounce per player. A touch with nothing due (an unpaid arc below floor 13) shows `LINES.taped` once per 10 s through the existing Notify path.

**Interfaces:**
- Consumes:
  - `J.bobPayoffDue`, `J.FLAGS` (Task 1)
  - `Prog.bobPayout` (Task 2)
  - `BobScript.LINES` (Task 3)
  - `BobCapital.Trigger` (Task 4)
- Produces:
  - player attributes `BobArc` (bool), `BobPaid` (bool), mirrored from `jr` every economy tick, for the client
  - remotes `BobPayoff`, `BobIntro`

- [ ] **Step 1: Failing offline test** `savecontract.spec.luau`: `bobArc and bobPaid round-trip through save and load`, using the existing save-contract helper.
- [ ] **Step 2: Run.** Expected: FAIL until the flags are in the saved `jr` (Task 1 makes `cleanFlags` keep them; this test pins SaveLoad's path).
- [ ] **Step 3: Implement** the wiring above.
- [ ] **Step 4: Run** offline (all pass). Then live:
  - DevScenario `bob:due` (Task 10 adds it; for now set the flags with execute_luau) reaches floor 13.
  - Touching the trigger pays once. A second touch pays nothing.
  - Cash delta equals `Prog.bobPayout`.
  - `BobPaid` is true after a rejoin.
  - Restore Wilz's save after (snapshot first).
- [ ] **Step 5: Commit** `feat(bob): server flags, Bob's text and the paid-once payoff`.

### Task 6: The scene player and the new-player intro (client)

**Files:**
- Create: `game/src/StarterPlayer/StarterPlayerScripts/BobSceneClient.client.lua`
- Create: `game/src/ReplicatedStorage/BobFace.lua`: draws a face on a `Face` SurfaceGui (Frames for eyes, brows, mouth; the expressions from BobScript). On a player clone:
  - classic head: hide the `face` Decal, add the SurfaceGui
  - dynamic head: set `FaceControls` values per expression on the client
- Modify: `game/src/StarterPlayer/StarterPlayerScripts/IntroClient.client.lua`: in the new-player branch (not `returning`), when `player:GetAttribute("BobArc")` is true, hand off to BobSceneClient (BindableEvent `SVBobScene` with `"intro"`) instead of the v4.9 flyover. Keep the v5 clock override (bright afternoon).

**Interfaces:**
- Consumes:
  - `BobScript.at` / `length` / `cues` / `LINES` (Task 3)
  - `ReplicatedStorage.BobCast`, `BobCapital` anchors (Task 4)
  - `BobPayoff`, `BobIntro` remotes (Task 5)
  - `Sfx.play(parent, key)` (Task 9 adds the keys; a missing key must stay silent)
- Produces:
  - `SVBobScene` BindableEvent: `Fire("intro")` / `Fire("payoff", {amount, item})`
  - `BobSceneClient.busy` (exposed as player attribute `BobScenePlaying`). OneVoice and HudClient treat it like `Cine.busy()`.

What the player does each frame:
1. Clone the cast from `BobCast`.
2. Clone the player's avatar with `Players:CreateHumanoidModelFromDescription(humanoid:GetAppliedDescription(), R15)`.
   - **Fallback rig:** if that errors or takes over 2 s, use a plain blocky stand-in (StaffRig-like colours).
3. Each RenderStepped, apply `BobScript.at(name, t, UIKit.reducedMotion())`:
   - poses through Motor6D `Transform` (code-driven, no animation uploads)
   - faces through BobFace
   - bubbles as BillboardGuis
   - camera Scriptable at `anchor * offset`, looking at `anchor * look`, plus the shake. This line is tagged `-- motion: camera`, with the reducedMotion read above it.
4. Sounds through `BobScript.cues`.
5. Disable controls with `PlayerModule:GetControls():Disable()` for the intro.
6. Own SKIP button: UIKit style, top-right on desktop, above the jump button on touch. A tap anywhere skips on touch only. No key or click skip.
7. One `finish()` used by both skip and the end:
   - destroy the clones and GUIs
   - camera Custom + humanoid
   - controls on
   - clear `BobScenePlaying`
   - fire `BobIntro` telemetry
   - show the goal card

- Modify: `game/src/ReplicatedStorage/OneVoice.lua`: while `BobScenePlaying` is true, `OneVoice.pick` returns no voice. That means no goal card, no phone banner and no coach tip, the same as during a Cine.
- Test: `game/tests/offline/onevoice.spec.luau`, add `nothing speaks while a Bob scene plays`.

- [ ] **Step 1:** Write the `onevoice.spec` case first and run it: FAIL. Then, after implementing, run all offline tests: PASS. `motionguard.spec` must also pass with the new camera lines.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Live check** (fresh Wilz save via DevScenario `fresh`, Studio unfocused so it isn't at 2 FPS):
  - the intro plays 15-17 s with all six shots
  - it ends with the camera Custom, controls on, and the goal card `PROVE BOB WRONG`
  - a second run, skipped at 3 s, gives the same end state
  - pressing W during the intro neither skips it nor moves the player
  - ForceReducedMotion gives 0 shake frames
  - forcing the clone to fail (dev flag) still plays with the fallback rig
  - a returning save gets the WELCOME BACK card and no intro

  Record the measured numbers in the ledger.
- [ ] **Step 4: Commit** `feat(bob): scene player and the new-player intro (option A)`.

### Task 7: The payoff scene, the winner's view of Bob's building

**Files:**
- Modify: `BobSceneClient.client.lua`: on `BobPayoff`, play `"payoff"`. The cash pill counts to `amount` on screen; the money was already paid. End with the toast `LINES.toast`.
- Create: `game/src/StarterPlayer/StarterPlayerScripts/BobDoorClient.client.lua`: when `BobPaid` is true, on this client only:
  - hide `Tape`
  - the `Door` shows open: local transparency or CFrame, and `CanCollide=false` locally
  - clone `Bob` to `CurbSeat`, sitting dizzy, with stars over his head
  - far-hidden like the building

  When `BobPaid` is false (or nil), touch nothing.

- [ ] **Step 1: Live check** (DevScenario `bob:due`):
  - the payoff plays about 17 s, with 7 shots, and skip gives the same end
  - the cash delta equals the paid amount, and replaying is impossible
  - after it: this client sees the open door and dizzy Bob
  - a second client (Studio's 2-player test) still sees tape and collides with the door
- [ ] **Step 2: Commit** `feat(bob): the payoff scene and the winner-only open door`.

### Task 8: The goal card shows Bob

**Files:**
- Modify: `SiliconCore.server.lua` around line 1888: set the player attribute `MilestoneBob` = `m.bob` (number or nil) next to MilestoneTitle/Sub.
- Modify: `game/src/StarterPlayer/StarterPlayerScripts/HudClient.client.lua`: when `MilestoneBob` is a number, the goal card shows Bob's face icon (a small ImageLabel or BobFace on a frame) and fills its bar to `MilestoneBob`. It stays one card (OneVoice unchanged).
- Test: `goalcard.spec.luau` only if GoalCard's pure rules change. They shouldn't.

- [ ] **Step 1: Live check** at floors 1, 7 and 12 (DevScenario `hq:<n>` on a bobArc save):
  - the text is exact
  - the bar is at 1/13, 7/13 and 12/13
  - at 13 the normal card returns
  - the doctor's "cards over cards" stays 0
- [ ] **Step 2: Commit** `feat(bob): PROVE BOB WRONG on the goal card`.

### Task 9: Trophy and sounds

**Files:**
- Modify: the HQ build path that runs on every HQ rebuild and floor change (find where `OfficeDress`/`GarageDress` place lobby dressing). When `jr.bobPaid`, place `BobBuilding.trophy` in the lobby, at a spot that passes `OfficeLayout.check` (never on a door, seat, station or glass). Remove it if the flag is false.
- Modify: `game/src/ReplicatedStorage/Sfx.lua` `Sfx.ID`: add `bobMusic`, `bobLaugh`, `boing`, `thud`, `money`, `victory`.
  - Only Roblox Creator Store audio the game may use. Note each asset id + name in a comment.
  - A key with no id stays nil (silent).
- Test: `officelayout.spec.luau`: add `the trophy spot passes the dressing check in every lobby size`, if the spot is chosen by a pure OfficeLayout helper. If it's placed by hand, the live check below covers it.

- [ ] **Step 1: Live check:**
  - a paid save shows the trophy at HQ 1-5 and after a tower floor change
  - an unpaid save shows none
  - a second client sees it (it replicates)
  - each sound plays at its cue, and the game's volume setting lowers it
- [ ] **Step 2: Commit** `feat(bob): BOB'S TOOTHPICK trophy and the cutscene sounds`.

### Task 10: Dev scenarios, the doctor step, the gate, the PR

**Files:**
- Modify: `game/src/ServerScriptService/DevScenarios.lua`:
  - `bob:intro`: a fresh save with bobArc; replays the intro
  - `bob:due`: a bobArc save at floor 13, not paid, standing at the door
  - add both to the list on line 40
- Modify: `game/src/ServerScriptService/GameDoctor.server.lua`: a `bob` step:
  - intro: plays to the end, then again with a skip at 3 s. Checks: 0 script errors, camera Custom after, controls on, `BobScenePlaying` false.
  - payoff once: cash delta == `Prog.bobPayout` value, `BobPaid` true, a second touch pays 0
  - restore the save
- Modify: `game/docs/features/`: add a `bob.md` feature page (what, files, guards).

- [ ] **Step 1:** Offline: `lune run tests/offline/run`, all pass; `selene src` 0 errors.
- [ ] **Step 2: Doctor PR gate**, the usual way:
  - fingerprint
  - a fresh Play with Studio unfocused
  - `Request = "full/"..os.clock()`
  - save the report
  - `bas checkup pr <report> <fingerprint>`

  Expected: 0 script errors, no BLOCKER, no new BUG, and the `bob` step ok.
- [ ] **Step 3:** Leave Studio in Edit and restore Wilz's save (1688749216).
- [ ] **Step 4: Push and open the PR.**
  - In the description: what's checked live with numbers, and what's not checked.
  - Mention that the look check is Luke's.
  - Ask Luke to publish main (#72-#82) first, for the clean bounce baseline (spec 5b-5).
  - Don't merge.
