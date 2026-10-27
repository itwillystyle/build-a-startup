# Client Timer + Sad Walk-off Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The client's patience bar becomes option C (a pie badge that turns into a red disc counting 8..1 in the last 8 s, with a soft tick), and a client who runs out says "Too slow...", shows the lost pay as a grey coin, and walks off slumped and slower.

**Architecture:** Every rule is in a new pure module `ReplicatedStorage/ClientMood.lua` (offline spec). The server (`ClientsServer.lua`) builds the badge once, publishes seconds left + whether patience is draining as attributes at 4 Hz, marks a lost client `Mood = "sad"`, holds the spot the leaver stands on, and fires `ClientLost`. A new LocalScript `ClientTimerClient` draws the badge every frame (smooth pie, count, tick, pop); `StaffAnimClient` holds the slump pose; `ClientFxClient` draws the grey coin chip.

**Tech Stack:** Luau, Rojo, lune offline tests, selene.

**Status (24 Oct):** Tasks 1-5 done on branch `client-timer` (worktree `game-clienttimer`), commits d4bd10b + 7bb2fc6; 602 offline tests pass, selene 0 errors. NOT live-checked in Studio.

**Spec:** `ui/animation-review/judge/CLIENT-TIMER-OPTIONS.md` (variant C), mock `ui/animation-review/scenes/6-client-timer.html`, list in `docs/superpowers/plans/2026-10-22-art-pass-1-light-and-garage.md` ("Plan 2").

## Global Constraints

- Real numbers: `Clients.TUNE.PATIENCE` 30 s, `BIG_PATIENCE` 45 s. Red and the tick ONLY with <= 8 s left (absolute seconds, not a share).
- Count shown 8, 7 ... 1 (ceil of seconds left); ticks at 8..1, the last 3 "hi" (higher pitch).
- Only the player's own client nearest to running out ticks (sound + pop). Sound only the owner hears.
- Tick pop: UIScale 1.00 -> 1.06 over T.press (0.12), back over T.fast (0.15); colour change over T.ui (0.2). All UI motion through `UIKit.tween`; no new `TweenInfo`/`TweenService:Create` (ratchet guard).
- Sad walk-off: 7 studs/s (the game walks at 10). Slump eases in over 0.4 s; under Reduce Motion it is a held pose at once. The grey coin and "Too slow..." still show.
- Lost-pay chip: UI moves stay <= 0.3 s (house rule, payoutbeats spec); fades in over T.ui, holds 1.2 s, rises and fades.
- Text >= 14 px at the design size (count 18, chip 18). Fonts/sizes/colours from UIKit tokens in client UI code (uistyle spec).
- No asset upload: the tick reuses an existing Sfx id under a clearly named entry.
- Dated `-- 24 Oct:` comments, plain words.

## Review Focus

- Patience pauses while you code a job or carry the app: the client must not keep counting down (estimate only extrapolates while `Draining`, at most 0.5 s). Test in Task 1 (`estimate`) and Task 2 (`draining`).
- A pause that starts right after a guess can make the estimate jump back up: the badge must never tick the same second twice or flip back from red. Test in Task 1 (`ticks` never re-fires; sticky stage lives in the client).
- BIG clients (45 s) must still go red at 8 s, not at a share. Test in Task 1 (`stage` via `leftOf`).
- Two clients run low together: only one ticks. Test in Task 1 (`ticker`).
- A served or lost client still standing at its spot while the next walks in. Test in Task 1 (`freeAt`/`walkDelay`).

---

### Task 1: ClientMood (pure rules)

**Files:**
- Create: `src/ReplicatedStorage/ClientMood.lua`
- Test: `tests/offline/clientmood.spec.luau`

**Interfaces (Produces):**
- `ClientMood.WARN = 8`, `SAY = 1.8`, `WALK = 10`, `SAD_WALK = 7`, `CLEAR = 2.5` (studs the leaver walks before the spot counts free), `GUESS = 0.5`, `SLUMP_IN = 0.4`
- `ClientMood.POP = { to = 1.06, up = 0.12, down = 0.15 }`, `ClientMood.LOST = { enter = 0.2, hold = 1.2, leave = 0.3, rise = 16 }`
- `ClientMood.leftOf(share, patience) -> seconds`
- `ClientMood.stage(left) -> "calm" | "worried" | "lost"` (lost at <= 0, worried at <= 8)
- `ClientMood.count(left) -> integer 1..8 | nil`
- `ClientMood.ticks(prevLeft, nowLeft) -> { {n, hi} }`, n = whole seconds 8..1 crossed (prev > n >= now), descending
- `ClientMood.sweep(left, patience) -> degrees elapsed 0..360`
- `ClientMood.estimate(left, since, draining) -> seconds` (left - min(since, GUESS) while draining, never below 0)
- `ClientMood.ticker(list) -> key | nil` (list of `{ key, left }`; smallest left in (0, 8])
- `ClientMood.slump(since, reduced) -> 0..1` (Quint Out over SLUMP_IN; reduced -> 1)
- `ClientMood.freeAt(leftAt, say, speed) -> time`, `ClientMood.walkDelay(now, freeAt) -> seconds >= 0`
- `ClientMood.nearest(rgb, palette) -> index`, `ClientMood.lookOk(look, avatar) -> bool`, `ClientMood.pickIndex(base, lookOf, avatar, tries?) -> index`

- [ ] Step 1: write `clientmood.spec.luau` with: red starts at exactly 8.0 s (8.01 calm, 8.0 worried, 0 lost); BIG at share 0.18 of 45 is calm, 30 s at share 0.26 worried; count 8.0->8, 7.99->8, 7.0->7, 0.01->1, 8.01->nil, 0->nil; ticks over a full 30 s drain in 0.1 s steps = exactly 8, in order 8..1, hi only for 3,2,1; ticks(7.5, 7.6) empty (time going back never ticks); estimate stops at GUESS and never moves while not draining; ticker picks the lowest of two worried, nil when all calm; slump 0 -> 0, 0.4 -> 1, reduced -> 1 at 0; freeAt = leftAt + 1.8 + 2.5/speed, walkDelay 0 when free; lookOk false on same skin or same hair; pickIndex skips a matching index; POP/LOST durations equal MotionSpec.T and are <= 0.3; POP.to - 1 <= MotionSpec.SMALL_SCALE (Reduce Motion keeps the pop).
- [ ] Step 2: `lune run tests/offline/run` -> FAIL (clientmood.spec could not load).
- [ ] Step 3: implement `ClientMood.lua`.
- [ ] Step 4: suite green.

### Task 2: Clients.tick marks who is draining

**Files:** Modify `src/ServerScriptService/Clients.lua` (patience loop), Test `tests/offline/clients.spec.luau`.

**Produces:** every client in `Q.line` has `c.draining` (bool) after each tick: true when its patience went down this tick.

- [ ] Step 1: test "draining: a waiting client drains, the job you hold and the app you carry do not".
- [ ] Step 2: FAIL. Step 3: set the flag in the patience loop. Step 4: green.

### Task 3: Server: the badge, the attributes, the sad leave, the held spot, the looks

**Files:** Modify `src/ServerScriptService/ClientsServer.lua`, `src/ServerScriptService/StaffRig.lua` (add `StaffRig.SKIN`, `StaffRig.HAIR_IDS`, `StaffRig.lookOf(index) -> { skin = i, hair = id }`, mirroring build's draws), `src/ServerScriptService/DevHook.lua` (`clients hurry`).

- `bubble()`: no bar row (bubble 240 x 50), a 30 px `Timer` badge after the text (LayoutOrder 3): `Disc` (INK circle), `R`/`L` clip halves each holding a `Sweep` circle (WELL) with a hard-edged `UIGradient` (R opaque first half, L opaque second half; rotation R = clamp(a, 0, 180), L = clamp(a - 180, 0, 180) for a sweep of `a` degrees clockwise from 12), `Ring` (INK 2 px stroke), `Count` (FredokaOne 18, white, hidden), `UIScale "Pop"`.
- `say()` hides `Timer`.
- 4 Hz draw: attributes `PatienceLeft` (seconds) and `Draining`; the GO/GOLD/RED ladder goes.
- `makeRig`: tag `SVClient`, attribute `PatienceSecs`; seed via `ClientMood.pickIndex(900 + id*13 + UserId%97, StaffRig.lookOf, avatarOf(player))` where `avatarOf` reads the character's Head colour (nearest `StaffRig.SKIN`) and `GetAppliedDescription().HairAccessory`.
- `walk(model, to, faceAfter, done, opts)` / `walkPath(..., opts)`: `opts.speed` (default 10), `opts.after` (start delay; a newer walk still cancels).
- `leave(P, client, line, lost)`: records `P.spotHeld[spot] = ClientMood.freeAt(now, SAY, speed)`; lost -> `Mood = "sad"`, `SadAt = GetServerTimeNow()`, walk-off at `SAD_WALK`.
- `placeLine`: `opts.after = ClientMood.walkDelay(now, P.spotHeld[i])`.
- Lost event: fires `ClientLost` `{ at, pay = Clients.pay(c, rate, 0) }` to the owner.
- `api.devHurry(player, secs)`: every waiting client's `left = min(left, secs)` (live checks); DevHook `clients` arg `hurry[:secs]`.

- [ ] selene + suite green (no new pure rules here; they were tested in Tasks 1-2).

### Task 4: ClientTimerClient (the badge, the tick)

**Files:** Create `src/StarterPlayer/StarterPlayerScripts/ClientTimerClient.client.lua`; Modify `src/ReplicatedStorage/Sfx.lua` (`clientTick` = 9113145647, the keyTap recording, named for the tick).

- Watches `SVClient` rigs; per frame: `estimate` -> sticky stage; calm draws the sweep; worried hides the sweep, shows `count`, tweens `Disc` to RED over T.ui once; `ticks` for the `ticker` (own clients only): `Sfx.play(SoundService, "clientTick", { pitch = hi and 1.25 or 1 })` + pop through `UIKit.tween`.
- [ ] uistyle + motionguard + selene green.

### Task 5: slump pose + grey coin

**Files:** Modify `StaffAnimClient.client.lua` (Mood "sad": neck down and tipped, waist lean, arms hang in, blended by `ClientMood.slump`, `UIKit.reducedMotion()`); `ClientFxClient.client.lua` (`ClientLost` -> a dark chip with a grey coin disc and a struck-through `$X`, beats from `ClientMood.LOST`, exit through `UIKit.tween` so Reduce Motion fades it in place).
- [ ] suite + selene green; commit.
