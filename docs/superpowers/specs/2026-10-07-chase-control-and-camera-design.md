# The chase: control, camera, and what makes it feel fast

**Date:** 2026-10-07
**Status:** draft for review — nothing built
**Supersedes the camera half of:** the `chase-scene` branch work (shot grammar, director, heading fix). That work stays; this changes the frame it runs in.

---

## 1. What is wrong, from the recording

The flicker is gone — the heading fix held. What is left is worse, because it is
not a glitch, it is the design.

**You cannot steer.** The chase camera sets `CameraType = Scriptable`, which
kills Roblox's mouse look. Movement is camera-relative, so the world direction
of `W` is whatever the cinematic camera happens to be pointing at this frame.
The camera is swinging, banking and cutting — so `W` means something different
every second. "I don't even know if W is moving me forwards or backwards" is
the correct description of the system as built.

**The camera frames the wrong character.** At 7.0 s the headhunter is centre
frame and large; the player is a small blue figure off to the left. At 11.0 s
the shot is almost a profile — the module's own notes forbid exactly this,
because in a profile the stick stops matching the direction you move.

**The horizon tilts constantly.** `ROLL = 11°` driven by `ROLL_PER_SPEED` off
the camera's own lateral velocity. Combined with the spring (`LAG_MAX = 11`,
`ACCEL 30`, `DAMP 4.4`) the result reads as swaying, which is what the player
reported before reading any code.

**It ended in `LOST!`** — caught, about eight seconds in. That is the cost of
the above, not a difficulty problem.

---

## 2. The principle this all comes down to

> **The control frame and the camera frame must be separate.**
> You may have a cinematic camera, or camera-relative controls. You may not
> have both unless the cinematic part is forbidden from touching the control
> part.

Every bug in this feature so far is one violation of that line:

- the feedback loop (camera yaw → move direction → velocity → camera yaw)
- `W` meaning a different direction each second
- cuts nudging the player's heading (measured: `dot` dipped to −0.08 the frame
  after a cut)
- the mouse doing nothing

The second principle, which is the answer to "how do I get the ideal
high-speed chase":

> **The camera is the stable thing. The world is what moves.**
> Speed is perceived against a fixed reference. A camera that swings with the
> subject destroys the reference and makes everything feel slower and
> seasick at once. Chase cinematography is a locked frame with chaos passing
> through it.

The current camera tries to generate the energy itself. That is backwards, and
it is why more camera motion has made it feel worse every time.

---

## 3. Control: give the player the yaw back

**Recommendation: keep Roblox's exact control model, and treat the cinematic
camera as decoration that may never touch it.**

This is deliberately the least exotic option. Players already know this model,
and it needs no relearning mid-chase.

### 3.1 `controlYaw` is player-owned

- The chase keeps a single number, `controlYaw`, seeded from the camera's yaw
  at the moment the carry starts.
- Mouse X, right stick, and the touch drag region rotate `controlYaw`, with the
  same sensitivity the default camera uses. This is the normal Roblox feel.
- Nothing the camera does writes to `controlYaw`. Ever. Not the spring, not the
  bank, not a cut, not the shot offsets.

### 3.2 Movement is computed against `controlYaw`, not the camera

- The chase disables the default move controller for the duration of the carry
  and drives `Humanoid:Move(worldDir, false)` itself.
- `worldDir` = WASD vector rotated by `controlYaw`. So `W` is forward along the
  direction the player is aiming, always, with no exceptions and no smoothing.
- On release of the carry, controls are restored exactly as they were.

**Why not simply leave `CameraType = Custom` and offset the camera?** Because
the default camera module would keep writing `CFrame` every frame and we would
be back to two owners of one property — the bug already paid for once.

### 3.3 Pitch

Mouse Y does **not** control pitch during a chase. The shot owns height and
pitch, because that is where the cinematic value is, and a player fighting the
pitch during a sprint is how you get a camera pointed at the sky. Mouse Y is
simply ignored. (If this feels wrong in testing, the fallback is a ±10° trim,
not full control.)

### 3.4 Look back

Hold right mouse (or the existing BOOST-adjacent button on touch) to swing the
shot 180° and look at the hunter, without changing `controlYaw`. You keep
running the way you were running. This is the one piece of camera control the
player gets, it is momentary, and it answers "where is it" without costing
them steering.

---

## 4. Camera: derived from the control yaw, never from velocity

### 4.1 The base

`heading = controlYaw` — full stop. Velocity is removed as an input to camera
orientation permanently. The `HEADING`/`TURN_MAX` smoothing added this morning
becomes unnecessary for the loop (there is no loop any more) but is kept as a
cheap guard, with a much shorter constant, so a teleport or a respawn cannot
snap the shot.

### 4.2 Cinematic offsets are render-only

Distance, height, lateral offset, roll, FOV and the shot table stay as they
are and keep their current meanings. They move the lens. They never move the
control frame.

### 4.3 Yaw deviation is capped hard

Total deviation of the shot from `controlYaw` is capped at **25°**, including
the shot's own yaw. Current values reach `YAW_NEAR 34 + shot.yaw 20 = 54°`,
which is how it reached a profile. The three-quarter look survives at 25°; the
profile does not.

### 4.4 Roll means "you are turning", not "the camera is drifting"

`ROLL_PER_SPEED` currently reads the camera's own lateral velocity, which is an
artefact of the spring — so the horizon tilts for reasons the player did not
cause. Replace the input with the **rate of change of `controlYaw`**: bank
because *you* are turning hard. Cap at 8° (down from 11). Now the tilt is
feedback, not noise.

### 4.5 The spring gets much stiffer

`LAG_MAX 11` studs of lag was chosen to make the camera feel like a second
vehicle. At chase speeds it is most of the sway. Proposal: `LAG_MAX 4`,
`DAMP` raised so the camera settles rather than overshoots. The "second
vehicle" feel should come from the *shot change*, not from the lens wandering.

---

## 5. The framing contract — and it must be testable

Today's constraints are expressed in studs ("stay 7 behind the hunter"), which
is why framing bugs keep surviving them: studs are not what the player sees.
Restate them in **screen space**, and assert them.

For every frame of a chase, projecting to the viewport:

| Rule | Value |
|---|---|
| The player is on screen | always, no exception |
| Player horizontal position | within ±18% of centre |
| Player vertical position | between 45% and 70% from the top |
| Player apparent height | ≥ 9% of frame height |
| Hunter on screen when within 20 studs | always |
| Hunter apparent height | ≤ 30% of frame height |
| Horizon tilt | ≤ 8° |
| Shot yaw vs `controlYaw` | ≤ 25° |

These become offline assertions by projecting with the real FOV and aspect, run
over a scripted chase, exactly as `tests/offline/chasecam.spec.luau` already
drives the director. A framing rule that is not asserted is a framing rule that
regresses — this feature has proved that four times.

**The 7.0 s frame fails three of these at once** (player off-centre and tiny,
hunter centre and large). That is the value of writing them down.

---

## 6. What actually makes it feel fast

The energy belongs in the world, not the lens.

1. **Ground rush.** Low camera, near the deck, so the road passes close to the
   lens. Already the right instinct in `MOVIE.HEIGHT_NEAR`; keep it.
2. **FOV, tied to speed, not to drama.** Already there. Widen on boost, settle
   back. Do not let two systems write it — that bug is fixed, keep it fixed.
3. **Speed lines / particles** streaming past at the frame edges during boost.
   Cheap, and it is the single strongest "fast" cue available.
4. **Near misses.** The hunter passing close on a lunge, the camera *holding
   still* while it does. A stable frame makes a near miss read; a swinging
   frame hides it.
5. **Cuts on beats.** Already built and tested this session — keep the shot
   grammar and the "no cut without a cause" rule exactly as is.
6. **Shake on impact only** — the lunge landing, nothing else.
7. **Audio** doing the work the camera should not: wind rising with speed, the
   hunter's footsteps panned and closing.

And the deletions:

- **Delete the continuous bank-from-drift.** (Replaced by steer-bank, §4.4.)
- **Delete most of the spring lag.** (§4.5.)
- **Delete the lateral `SIDE 10.5` at close range** — at a 9-stud gap it is
  most of what pushes the shot toward profile. Scale it down as the hunter
  closes rather than up.

---

## 7. Readability

The recording is at night with a heavy red vignette over everything. During a
chase the player needs to read geometry at speed, and both of those fight it.
Proposal: during a carry, lift exposure slightly and cut the vignette's opacity
by half, keeping the colour cue but not the dimming. Worth one A/B.

---

## 8. Open decisions — yours

1. **Mouse Y:** ignored (recommended), or a ±10° trim?
2. **Look-back on right mouse:** worth the button, or cut for launch?
3. **Does the chase keep the scooter's fixed speed**, or does steering cost
   speed (turning tight slows you)? The second is more skillful and makes the
   chase a driving problem rather than a holding-W problem. I lean toward it,
   but it changes `ChaseRules` balance and every escape-rate number in
   `chase.spec.luau`, so it is not a free change.
4. **Readability pass** (§7) — in scope now, or after the control fix?

---

## 9. Phases

| Phase | Work | Proves |
|---|---|---|
| **A** | `controlYaw` + own movement input + camera derived from it | W is forward; the mouse steers |
| **B** | Yaw cap, steer-bank, stiffer spring, SIDE taper | the swaying is gone |
| **C** | Screen-space framing contract + offline assertions | framing cannot regress again |
| **D** | Speed cues (lines, audio, near-miss hold) | it feels fast |
| **E** | Readability A/B | it can be read at speed |

A and B are the fix. C is what stops this costing another four rounds. D is
where the "ideal high-speed chase" actually comes from, and it is deliberately
last, because none of it reads until the frame is stable.

**A and B together are the smallest change that makes the chase playable.** If
only one thing ships, ship A.
