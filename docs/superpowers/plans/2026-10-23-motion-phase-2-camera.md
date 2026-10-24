# Motion phase 2: the camera under Reduce Motion. Implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** every script that moves the player's camera does less of it when Reduce Motion is on: no shake, no FOV punch, no speed zoom, cutscene flights become cuts. The decisions live in pure code.

**Architecture:** `MotionSpec.camera(reduced)` returns one small policy table, and `MotionSpec.cutShot(times, t)` picks the shot a cut holds. Each camera owner reads `UIKit.reducedMotion()` at the moment it acts (every frame for per-frame owners), so turning the setting on mid-session takes effect on the next frame. `motionguard.spec` gets two new rules so a new camera tween or shake without that read fails CI.

**Tech Stack:** Luau, Rojo, lune offline specs, selene.

**Spec:** `silicon-startup/ui/animation-review/judge/FINAL.md`, architecture item 6 ("Camera owners branch themselves under reduced motion ... Phase 2, its own PR"). Item 7 (server tweens) is out of scope.

**Sources:**
- Roblox `GuiService.ReducedMotionEnabled` (https://create.roblox.com/docs/reference/engine/classes/GuiService#ReducedMotionEnabled): read-only boolean. The page gives no behaviour guidance and lists no changed event of its own. UIKit already listens with `GetPropertyChangedSignal`.
- Roblox accessibility guide (https://create.roblox.com/docs/production/publishing/accessibility): the setting means the player wants motion "reduced or completely removed". Its examples are UI-only: a 0 s TweenInfo, or a fade in place of a move.
- Xbox Accessibility Guideline 117 (https://devdocs.xbox.com/gaming/accessibility/xbox-accessibility-guidelines/117): avoid camera shake and automatic camera movement, or give players a way to turn them off. Field-of-view changes are a known motion-sickness trigger. Roblox's page says nothing about the camera, so this guideline is what carries the setting over to the camera.

## Global Constraints

- Normal motion stays identical in effect: every change sits behind `reduced == true`, and with it off the policy returns 1 / true / "spline" / 1.5.
- Mid-session toggle must work: no site caches `UIKit.reducedMotion()` across frames or events.
- Plain-words `-- 23 Oct:` comments; no refactor beyond the sites below.

## The camera motion sites (found 23 Oct on goal-card-pill, 892c8da)

| # | Site | Today | Under Reduce Motion |
|---|---|---|---|
| 1 | `ChaseCamClient.client.lua:612-618` lunge shake | mode B lunge: random 0.55-stud offset decaying over 0.25 s | `shake = 0`: no offset |
| 2 | `ChaseCamClient.client.lua:431-433` release | FOV tweens back to the pre-chase value over 0.35 s | snaps back (`zoom = false`) |
| 3 | `ChaseFxClient.client.lua:156-158` boost | FOV punch to 84 (0.15 s), back to 70 after 0.9 s (0.4 s) | no punch (`punch = false`). The delayed return snaps if the setting was turned on mid-punch |
| 4 | `ChaseFxClient.client.lua:347-351` lunge seen (chase cam not owning) | FOV punch to 62 (0.08 s), back to 70 (0.35 s) | no punch; the return snaps |
| 5 | `CarClient.client.lua:162` stop driving | FOV tweens to 70 over 0.5 s | snaps to 70 |
| 6 | `Cine.lua:198-220` every cutscene (intro, home, lobby) | Catmull-Rom spline flight through the shots, eased in and out | cuts: each shot is held, and the cut lands at the midpoint of each leg (`MotionSpec.cutShot`). Linear time, same total length, captions follow the shot on screen |
| 7 | `GuideClient.client.lua:695-703` tap-to-look | Cubic InOut 0.35 s turn; pin pops 1.5 -> 1 | VERIFIED: the turn is already skipped (#73). BUG: the pin pop 1.5 -> 1 is a 0.5 scale change, so UIKit.tween snaps it and the "pin still pops" never shows. Fix: start the pop at `1 + SMALL_SCALE` (a pop UIKit keeps playing) |
| 8 | `RocketClient.client.lua:235-237` own launch (not in FINAL.md) | camera jitters 0.12 studs for 1.4 s | no jitter. The rocket model still shakes: it is an object, not the camera |
| 9 | `CarClient.client.lua:318` speed FOV (not in FINAL.md) | FOV eases to 70 + 10 x speed + 8 when boosting | holds 70 (`speedFov = 0`) |
| 10 | `ChaseCam.lua:402-403, 545` speed / wind-up FOV (not in FINAL.md) | lens widens with carry speed (+14, locked +5) and on the crouch tell (+10) | `s.still = true` drops both terms. The per-shot lens and the locked "lens gives way" framing math stay |

Left alone, and why:
- `ChaseCamClient.client.lua:601`, the per-frame FOV lerp: it smooths the framing solve, it is not an effect. Once sites 9-10 are in, its target only moves on a cut or with the hunter's distance.
- `IntroClient.client.lua:88` `glide()`: dead code, never called.
- `WaferClient.client.lua:335`, `TalentRevealClient`, `RigPortrait`, `Items`, `BuildModeClient`: ViewportFrame cameras (UI tiles), not the player's view. The wafer tile's slow orbit is UI motion for a later UI pass.
- `LiftClient.client.lua:212`: a steady camera that rides the cab. This is the comfort fix, not an effect.
- Server tweens: FINAL.md item 7.

## Review Focus

- Turning Reduce Motion on mid-punch (sites 3-4): the FOV must not stay stuck at 84 or 62. The delayed return always runs, and under Reduce Motion it snaps. (live check B)
- Turning it on or off mid-cutscene (site 6): the flight switches between spline and cut on the next frame. A one-frame jump is acceptable, a stuck camera is not. The loop reads the policy every frame.
- A 2-shot cutscene ("welcome back", t = 0 then 2.8): the cut version shows shot 1 for 1.4 s and shot 2 for 1.4 s. Pinned in `cutShot` tests.
- Legs with zero length (`t = 0` on a later shot): `cutShot` must not divide by zero and must still return an index in range. Pinned.
- The release snap (site 2) runs while a ChaseFx return tween may still be live on the lens. Snapping a property does not cancel that tween, but ChaseFx only punches when the chase camera does not own the lens, so the two never overlap. Not tested offline.

---

### Task 1: the camera policy in MotionSpec

**Files:** Modify `src/ReplicatedStorage/MotionSpec.lua`. Test `tests/offline/motionspec.spec.luau`.

**Produces:** `MotionSpec.camera(reduced: boolean) -> { shake: number, punch: boolean, zoom: boolean, speedFov: number, flight: "spline"|"cut", turn: boolean, pinPop: number }` and `MotionSpec.cutShot(times: {number}, t: number) -> integer`. `times` holds cumulative shot times with `times[1] = 0`.

- [ ] Failing tests:
  - `camera(false)` gives shake 1, punch true, zoom true, speedFov 1, flight "spline", turn true, pinPop 1.5
  - `camera(true)` gives shake 0, punch false, zoom false, speedFov 0, flight "cut", turn false, and pinPop = 1 + SMALL_SCALE, which `plan(...)` still tweens from 1.06 (float32) to 1
  - `cutShot({0, 2.8}, ...)` gives 1 at 0, 1 at 1.39, 2 at 1.41, 2 at 2.8 and 2 at 9
  - `cutShot({0, 2, 2, 5}, ...)` (a zero-length leg) always returns an index in 1..4, with 4 at the end
  - `cutShot({0}, 0)` gives 1
- [ ] Run `lune run tests/offline/run`. Expected: FAIL (`camera` is nil).
- [ ] Implement. Run again. Expected: PASS.

### Task 2: the guard

**Files:** Modify `tests/offline/motionguard.spec.luau`.

- [ ] Failing rules:
  - (a) a hand-built tween on the camera (a `TweenInfo.new` or `TweenService:Create(` line that mentions `FieldOfView`, or creates on `cam` / `camera` / `CurrentCamera`) must carry `-- motion: camera`, whatever the file's baseline says
  - (b) a camera shake (a `math.random(` line that assigns a camera's `.CFrame`, or `cf = cf * ...`) must carry the tag too
  - (c) every `-- motion: camera` line has `reducedMotion(` on it or on one of the 20 lines above it (the same block, not just somewhere in the file)
  - plus detector unit tests in the style of "only three words"
- [ ] Run. Expected: FAIL on ChaseCamClient, ChaseFxClient, CarClient and RocketClient (the untagged sites).

### Task 3: wire the sites (makes Task 2 pass)

Sites 1-8 per the table. Each reads `MotionSpec.camera(UIKit.reducedMotion())` where it acts. Tagged lines leave the count, so lower `BASELINE` to ChaseCamClient 5 and ChaseFxClient 3, and remove CarClient (now 0). RocketClient gets a UIKit require.

- [ ] Run the suite and selene. Expected: green, and the warning count does not grow (249 on the base).
- [ ] Commit.

### Task 4: speed FOV (sites 9-10; beyond FINAL.md, its own commit so it can be dropped)

- [ ] Failing test in `motionspec.spec`: `ChaseCam.solve` and `solveLocked` with `still = true` give the same fov at full carry speed as at speed 0, and a mode-B wind-up adds nothing. With `still` unset they are unchanged (speed still widens).
- [ ] Implement `s.still` in `ChaseCam.solve` / `solveLocked`. ChaseCamClient passes `still = lens.speedFov == 0`. CarClient's per-frame target becomes `70 + lens.speedFov * (...)`.
- [ ] Suite + selene, commit.

### Task 5: doctor probe (written here, run live by the main session)

Extend `DoctorProbes.motion` with camera checks that can run under `ForceReducedMotion`: `MotionSpec.camera(UIKit.reducedMotion())` returns the reduced table, and a ChaseFx-style punch is refused. See the report for the live chase and cutscene measurements.
