# One Instruction (rule A, "one voice") Implementation Plan

> **For agentic workers:** executed inline by the subagent that wrote it (superpowers:executing-plans + test-driven-development). Steps use checkbox (`- [ ]`) syntax.

**Goal:** At most one instruction on screen: the button you can press now, else the job in your hands, else LAUNCH!, else the goal. Lower ones fold away, and LAUNCH!'s half-pay auto-launch clock pauses while LAUNCH is folded away by a job or a button.

**Architecture:** One pure ladder, `ReplicatedStorage/OneVoice.lua`, used by the client (HudClient picks and publishes the voice as a client-local attribute; GuideClient, PromptClient and CoachClient read it) AND by the server (the same `launchHeld` rule decides when the clock pauses, so the chip's "paused" and the server's pause agree). One pure pausable clock, `ServerScriptService/LaunchClock.lua`, owned by the server session; the client only displays two server-set attributes.

**Tech Stack:** Luau, Rojo, lune offline specs, selene.

**Spec:** `silicon-startup/ui/animation-review/judge/ONE-INSTRUCTION-OPTIONS.md` (rule A, section 3 and the build-cost table), mock `ui/animation-review/scenes/7-one-instruction.html` (`ruleA`).

## Global Constraints

- Taps >= 44 px; text >= 14 px (12 floor on a 376 px tall screen); text sizes from `UIKit.TYPE`, colours from UIKit tokens (uistyle.spec).
- All new UI motion via `UIKit.tween` / `UIKit.set` (motionguard.spec ratchet: no new hand-built tween lines).
- Dated comments `-- 24 Oct:`.
- SiliconCore's main chunk is near the 200-local limit: NO new top-level locals there; require inside functions.
- Stay out of HudClient's money texts and `HudSlots.lua` (open PR #76 edits both).
- Cash, rewards, the celebration, the DONE! stamp: untouched.

## Review Focus

1. A player who carries an app forever (or AFKs at the laptop) must still get the auto-launch: total pause is capped (PAUSE_MAX 60 s), so it fires at most 120 s after ready. Test in Task 1.
2. A client cannot pause the clock by lying: the pause reads only server-owned state (the Clients queue, the Drop carry, server-set attributes); no remote carries a pause flag. Test: `launchHeld` takes only the server fields (Task 2); code review of Task 3.
3. A spin-off / reset while an app waits must not leave a stale clock or attributes (the loop exits on `s.pendingProduct ~= picks` and clears both attributes). Covered by Task 3's loop shape.
4. With LAUNCH folded the player can still launch: the chip is a 44 px tap target (and L / ButtonY still work). Task 4.
5. The first app (before `jr.launched`) never auto-launches: no clock, chip shows no time. Task 3 keeps the existing guard.

---

### Task 1: LaunchClock (pure, server)

**Files:** Create `src/ServerScriptService/LaunchClock.lua`; Test `tests/offline/launchclock.spec.luau`.

**Interfaces (produces):**
- `LaunchClock.SECONDS = 60`, `LaunchClock.PAUSE_MAX = 60`
- `LaunchClock.new(now: number, seconds: number?, pauseMax: number?) -> clock`
- `LaunchClock.update(c, now: number, wantPause: boolean) -> boolean` (true when the paused state changed: republish)
- `LaunchClock.left(c, now) -> number`, `LaunchClock.due(c, now) -> boolean`, `LaunchClock.paused(c) -> boolean`

- [ ] Tests (fail first): runs down to due at 60 s with no pause; a 30 s pause at 10 s leaves 50 s and fires at 90 s; pause beyond PAUSE_MAX runs again (fires by 120 s however long you stay busy, and `paused` turns false at the cap); `update` returns true only on a change; overflow inside one long update is charged to the clock (a 100 s update while busy from fresh leaves 20 s).
- [ ] Implement; tests pass; commit with Task 2.

### Task 2: OneVoice (pure, shared)

**Files:** Create `src/ReplicatedStorage/OneVoice.lua`; Test `tests/offline/onevoice.spec.luau`.

**Interfaces (produces):**
- `OneVoice.verbOf(a: {carrying, canGive, jobWaiting, atLaptop}) -> "give"|"code"|nil` (HudClient's current rule, moved)
- `OneVoice.pick(st: {verb, carrying, midJob, recruit, launch, goal}) -> {voice: "verb"|"job"|"launch"|"goal"|nil, goal: "words"|"icon"|"hidden", launch: "button"|"chip"|nil, marker: boolean}`
- `OneVoice.launchHeld(a: {carrying, canGive, jobWaiting, atLaptop, midJob, recruit}) -> boolean` (LAUNCH is folded = the clock pauses)
- `OneVoice.promptRole(actionText) -> "code"|"give"|"ask"|"world"` (HOLD TO CODE / GIVE / UPGRADE+BUILD / rest)
- `OneVoice.prompt(pick, role, nearGoal: boolean) -> "draw"|"quiet"|"off"`
- `OneVoice.coachOk(voice, tipTarget) -> boolean`
- `OneVoice.count(pick, promptsDrawn) -> number` (instructions on screen: the guard the doctor can use)

- [ ] Tests (fail first): the ladder (verb > job > launch > goal) with folds: verb -> goal icon + launch chip + no marker; job -> goal words + chip + marker; launch -> goal icon + button + no marker; goal only -> words + marker; the mock's 10 s timeline sampled every 0.1 s gives count <= 1 everywhere and exactly 2 changes of the card's words; launchHeld true mid-job/carrying/recruit/at-laptop-with-a-job, false hands free; prompt rules (the HUD's verb prompt is quiet, an ask prompt draws only under the goal voice and near the goal, world prompts are off while a verb is up); coachOk.
- [ ] Implement; pass; commit "OneVoice + LaunchClock".

### Task 3: Server clock (SiliconCore offerProduct V3 + ClientsServer MidJob)

**Files:** Modify `SiliconCore.server.lua` offerProduct V3 branch (the `task.delay(60, ...)`) and `launchProduct` (clear attrs); `ClientsServer.lua` publish `MidJob` beside `JobWaiting`.

- [ ] Replace the fixed delay with a 0.25 s loop per pending product (only when `s.jr.launched`): `LaunchClock.update(clk, now, OneVoice.launchHeld(server state))`; on change set attributes `LaunchAutoAt` (server time, nil when paused) and `LaunchLeft` (seconds, nil when running); fire `launchProduct(..., true)` when due; exit and clear both attributes when `s.pendingProduct ~= picks`. Requires inside the function.
- [ ] Suite + selene green.

### Task 4: Client (HudClient, GuideClient, PromptClient, CoachClient)

- [ ] HudClient `syncCode`: verb from `OneVoice.verbOf`; `pick`; LAUNCH button visible only when `pick.launch == "button"`; a 44 px tappable `LaunchChip` ("APP READY" + time, "II" when paused) in LAUNCH's slot when `"chip"`; publish `player:SetAttribute("OneVoice", pick.voice)` (client-local); time from `LaunchAutoAt`/`LaunchLeft` when present.
- [ ] GuideClient: `OneVoice` attr "verb"/"launch" folds the pill to its 44 px icon (title hidden, still tappable) via UIKit.tween; marker hidden while folded.
- [ ] PromptClient: per shown prompt, `OneVoice.prompt` -> quiet (not drawn), off (local MaxActivationDistance 0, restored later; the server never rewrites it after creation), draw.
- [ ] CoachClient: busy unless `OneVoice.coachOk`.
- [ ] Suite + selene green; commit.
