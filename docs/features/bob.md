# Bob, the first boss investor (P-5: the story intro, PROVE BOB WRONG, the payoff)
**What:** A new save's intro is a 16 s cutscene, option A from `ui/storyboards/p5-bob`.
- You ask Bob for an offer; he and his investors laugh.
- He kicks you out of his door; you walk home and vow "He will rue the day."
- Until floor 13 the goal card's line is PROVE BOB WRONG.
- At the HQ 4 stage, walking into Bob's taped door plays the payoff and pays the best Series A the phone could have given. You show your REVENUE chart, he throws the money (x3), and you kick him out.
- After that you see his door open and him dizzy on the curb (only you).
- A BOB'S TOOTHPICK trophy stands at the front of your lot (everyone sees it).

Spec: `silicon-startup/docs/superpowers/specs/2026-10-25-bob-first-boss-investor-design.md`.

**How a player reaches it:**
1. A brand-new save (no DataStore record) gets `jr.bobArc` at load (`src/ServerScriptService/SaveLoad.lua`, `loadOnce`). Older saves never do, and keep the phone Series A.
2. After PLAY, `IntroClient` hands the intro to `BobSceneClient` (`PlayerGui.SVBobScene:Fire("intro")`) instead of the flyover.
3. Floors 1-12: `Journey.bobGoal` → `MilestoneBob` → the goal card's footer (`GuideClient`: Bob's face, the line, a gold bar of floors).
4. The HQ 4 stage: `Journey.task` returns `bob` ("Go to Bob's office"). Bob texts once a session (`Phone.notice`).
5. Walking into `SiliconValley.BobCapital.Trigger`:
   - the server pays `Progression.bobPayout` and sets `bobPaid` + `seriesA`
   - it saves, then fires `SVRemotes.BobPayoff`
   - the client plays the payoff (`SiliconCore.server.lua`, the P-5 do-block before PLAYERS)

**Files:**
- `src/ReplicatedStorage/BobScript.lua`: both cutscenes as data (shots, moves, looks, bubbles, fx, vals, shakes, cues) and the pure evaluator `at(name, t, reduced)`. `LINES` holds every exact word.
- `src/ReplicatedStorage/BobFace.lua`: faces, a SurfaceGui cartoon face on classic heads or FaceControls on dynamic heads.
- `src/StarterPlayer/StarterPlayerScripts/BobSceneClient.client.lua`: the scene player. It runs:
  - clones (cast + your avatar, or a stand-in)
  - Motor6D poses, bubbles, the letterbox
  - SKIP (button / tap only)
  - controls off, the HUD aside
  - local door/tape/front-wall overrides
  - one `finish()`
- `src/StarterPlayer/StarterPlayerScripts/BobDoorClient.client.lua`: the winner-only open door and Bob on the curb.
- `src/ServerScriptService/BobBuilding.lua`: Bob Capital next to The Residences (`Downtown.RES * (-60, 0, 4)`), its anchors (`AnchorBoard/Door/Street`), `ReplicatedStorage.BobCast`, and `trophy()`. Built from `Downtown.build`.
- `src/ServerScriptService/Journey.lua`: `FLAGS` (+bobArc, bobPaid), `bobPayoffDue`, `bobGoal`, `milestone`, the `bob` task.
- `src/ServerScriptService/Progression.lua`: `niceMoney`, `bobPayout`.
- `src/ReplicatedStorage/OneVoice.lua`: the `scene` voice (nothing else speaks during a Bob scene).
- `src/ReplicatedStorage/Sfx.lua`: `bobMusic`, `bobLaugh`, `boing`, `thud`, `money`, `victory`.

**State:**
- Saved in `jr`: `bobArc`, `bobPaid` (a spin-off keeps both; `seriesA` is cleared as before).
- Player attributes: `BobArc`, `BobPaid`, `MilestoneBob` (server), and `BobScenePlaying` (client, local).

**Drive it:** `dev:Invoke("scenario", p, "bob:intro")`, then on the client `PlayerGui.SVBobScene:Fire("intro")`. Or `"bob:due"`: the HQ 4 stage, unpaid, and it returns the door position.

**Prove it:**
- offline: `bobscript.spec`, `journey.spec` (Bob cases), `progression.spec` (payout), `onevoice.spec` (scene)
- live: the doctor's `bob` step
  - the intro end to end, then again skipped at 3 s, with the same end state each time
  - the payoff pays once and sets BobPaid
- The `bobscene` probe is in `DoctorProbes.lua`.

**Last verified:** 2026-10-25 (branch bob-intro)
