---
name: cutscene-review
description: Fix, change or review a scripted scene in Build a Startup! (Bob's cutscenes: BobScript, BobClips, BobSceneClient, or any keyframed animation). Use when Luke reports a pose that snaps, sinks, floats or resets too fast, something covering the action, or asks to "play" a scene for him. Measure before fixing; a fix is done when the measurement that showed the bug shows it gone.
---

# cutscene-review

25 Oct 2026, the get-up after Bob's kick: three fixes in a row were built on a wrong theory before
one was measured. A dark frame was nearly "fixed" as night; it was a capture artifact (9 AM and
2 PM both lit). The rule: **log it, find the cause, confirm it with a comparison, then fix.**

## Measure

- **Frame log.** In Play (Client), on `RenderStepped`, log what is wrong: the actor's root height,
  its one-frame moves, a joint's turn per frame. Run the scene for real (no hold) for this.
  The get-up log showed root 2.2 -> 3.4 studs in ONE frame (sit to stand) and 1.0 -> 3.25 -> 2.2
  (a sit-up that lifted him over sitting height). That is the bug, in numbers.
- **Pops, both scenes.** `require(ReplicatedStorage.DoctorProbes).bobscene({ name = "intro" })`
  runs every live check: sounds loaded before t = 0 and playing on cue, nothing snapping inside a
  shot (a body over 1 stud or a joint over 45 degrees in one frame, out of near-stillness), world
  ambience silent. The doctor's `bob` step runs it every check.
- **Frozen frames.** `BobSceneHold = t` (Studio only), then `screen_capture`; `BobSkipNow = true`
  ends a held scene. Clips start where their pose began, so a held frame shows the true pose.
  A held frame cannot show a one-frame glitch: use the frame log for those.

## What the body does (BobSceneClient `place`)

- On the ground the body's LOWEST point is put on the floor. A limb that swings below the body lifts
  the whole body: legs bending before a roll, a hand pushing down, a knee bent with a flat thigh.
- Land face UP if the next move is a sit-up (from face down, rolling up drives the legs into the floor).
- A sit-up keeps the legs flat: hips bend in step with the roll (same time, same ease). Sitting with
  bent knees: thighs tilt up by half the knee bend.
- Pose changes inside a shot blend over 0.2 s. If a clip must stay in step with a move, start the
  pose 0.2 s BEFORE the move, so the blend is over when the move begins.
- A clip that follows another starts in the other's last pose (bobclips.spec checks the seam).
- Fast-on-purpose moves (Bob's kick) are allowed; a snap out of stillness is not.

## Look at the frame, not only the actor

- An effect (BOING!, a burst) must not cover the action it is about: hold a frame mid-effect and look.
- Keep each beat on screen long enough to read (a get-up under 0.4 s reads as a snap).

## "Say play": showing Luke in his Studio

1. Studio in Edit, Rojo serving the branch (check a new line is in the Edit `Source`).
2. `start_stop_play` on; Server: `require(ServerScriptService.DevScenarios).snapshot(1688749216)`.
3. Client: `PlayerGui.SVBobScene:Fire("intro")`, wait for `BobScenePlaying` to clear, then
   `:Fire("payoff", { amount = 120000 })`. Clear `BobSceneHold` and `BobSkipNow` first.
4. Stop; Edit: `DevScenarios:Clone()` -> `restore(1688749216)` and `compareSnapshot` (0 differs).
5. Tell him what to watch, by second, and that Studio runs at 2-3 FPS while it is the focused window.

## Done means

The log or frame that showed the bug shows it gone; offline tests (`lune run tests/offline/run`)
green, with each new test seen failing first; the probe passes both scenes; Wilz restored; Edit mode.
