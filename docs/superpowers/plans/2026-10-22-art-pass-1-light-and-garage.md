# Art pass 1: Light and the garage. Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new player's first 10 minutes look like `ui/art-pass/garage-outside.png`. The daytime frame stops
being overexposed (near-white pixels from 46-79% down to ≤ 10%). The garage reads as a cozy startup. The forecourt
is full, and a growth lot shows what is coming.

**Architecture:** The light's daytime numbers move into one pure module (`LookTune`) that SkyClient and SiliconCore
read, so the look review tunes ONE table. FlatLook gains a tagged exception (`SVKeepMaterial`) for a short list of
materials. The garage restyle stays in its existing pair: GarageLayout (pure placement, already spec-checked) and
GarageDress (builder). The forecourt's new props go through a new pure `ForecourtPlan`, checked against the path,
door, drop-off ring, client queue and WalkLanes. A Python tool (`tools/look_stats.py`) turns screenshots into the
spec's four numbers.

**Tech Stack:** Luau + Rojo, Lune offline specs, selene, GameDoctor, Studio MCP (`screen_capture`), Python 3 + Pillow (tool only).

**Spec:** `silicon-startup/docs/superpowers/specs/2026-10-22-art-pass-design.md`

## Global Constraints

- Parts and built-in materials only. No new meshes, no uploads, no textures (spec §7).
- Zero new translucent parts (Transparency between 0.05 and 0.95) on any plot (spec §7, the v28 fill-rate rule).
- Neon only on names in `Palette.EMISSIVE_OK`. New light parts get added there by name (`Bulb` already is).
- `SVKeepMaterial` is allowed on Wood, WoodPlanks, Fabric and Metal only. Never on ground wider than 60 studs² that is lawn-coloured.
- New colours go through `Palette.map` (builders) and stay on an anchor; Teal and Coral are the only new anchors.
- Targets on cameras C1 and C2 (spec §3): near-white ≤ 10%, mean 0.45-0.68, contrast ≥ 0.50, colour strength ≥ 0.32.
- The day/night cycle stays 22 minutes; night must still show the laptop and the client.
- No change to gameplay positions: the walkway, pads, desk, door, drop-off and client queue keep their places (GarageLayout.check and the doctor already guard them).
- Wilz's save is snapshotted before any Play test and restored after (DevScenarios).

## Review Focus

1. **Night (4 of 22 minutes).** Darker daytime ambients must not make the night black inside the garage. Covered by the C1 night capture in Task 6 (laptop and client still findable, near-black pixels ≤ 35%).
2. **Low graphics quality (most phones).** Shadows and some materials drop out, so the contrast must come from colour, not shadows. Task 6 captures C1/C2 at Graphics Quality 1 and the same targets apply with contrast ≥ 0.40.
3. **Players past the garage.** The 1c garage → lobby moment and every level ≥ 2 must look unchanged except the light. Task 6 runs the full doctor (HQ 5-100, lift, chase) and compares SVStyle counts with StyleBaseline.
4. **Other finishes (Timber, Neon) and other plots.** The Teal/Coral anchors must not repaint existing tower colours. Task 3's spec asserts `Palette.map` of every TowerFinish colour is unchanged.
5. **Forecourt props in the way.** Cars park and drive on the forecourt edge; chases run home over it. Task 5's spec checks every prop against the path, door, drop-off ring, client queue and WalkLanes, and the doctor's "drop-off reaches the street" and walker sweep re-run.

---

### Task 1: The measuring stick: `look_stats.py`, review cameras, baseline

**Files:**
- Create: `tools/look_stats.py`
- Create: `tools/look_targets.json`
- Modify: `src/ReplicatedStorage/DoctorProbes.lua` (add `Probes.lookcam(args)`)
- Create: `../ui/art-pass/baseline.md` (outside git)

**Interfaces:**
- Produces: `python tools/look_stats.py <image>... [--targets tools/look_targets.json]`. It prints one line per image (`mean`, `spread`, `sat`, `blown`, and PASS/FAIL per target) and exits 1 if any image fails. `Probes.lookcam({ cam = "C1"|"C2"|"C3"|"C4", hold = seconds })`: puts the client camera at the named review CFrame (plot-relative, from the plot's pivot) for `hold` seconds, then hands it back.

- [ ] **Step 1: Write `look_stats.py --selftest`** with three cases built in memory: an all-white 64×64 image (blown 1.0 → FAIL), a 50/50 black/white checker (spread 1.0, sat 0 → FAIL on sat), and `../ui/art-pass/garage-outside.png` (→ PASS on all four). Metrics exactly as measured on 22 Oct: crop 12% top and bottom, resize to 320 wide, Rec.709 luminance, `blown` = share with luminance > 0.92, `spread` = p90 - p10, `sat` = mean HSV saturation.
- [ ] **Step 2: Run** `python -I tools/look_stats.py --selftest`. Expected: before the metrics exist, FAIL (it does not run); after, `3 cases, 3 as expected`.
- [ ] **Step 3: `look_targets.json`**: `{ "blown_max": 0.10, "mean_min": 0.45, "mean_max": 0.68, "spread_min": 0.50, "sat_min": 0.32 }`, and a `"lowq"` block with `spread_min` 0.40.
- [ ] **Step 4: `Probes.lookcam`**. C1: beside the laptop desk looking at the door (GarageLayout desk + door positions). C2: outside, 38 studs in front of the garage door, 9 up, looking at the door. C3 and C4: stubs that return `{ ok = false, why = "plan 3/4" }`.
- [ ] **Step 5: Baseline.** Play as Wilz at the garage (scenario `fresh`), ClockTime 13.5. Run `lookcam` C1, then C2. Studio `screen_capture` each and save as `../ui/art-pass/shots/baseline-C1.png` and `baseline-C2.png`. Run look_stats on both and write the numbers into `baseline.md`. Expected: both FAIL `blown_max` (the live shots measured 46-79%).
- [ ] **Step 6: Commit** `tools/look_stats.py tools/look_targets.json src/ReplicatedStorage/DoctorProbes.lua`: "The look review gets a ruler: four numbers per screenshot, two review cameras".

### Task 2: `LookTune`, the daytime light in one table

**Files:**
- Create: `src/ReplicatedStorage/LookTune.lua` (pure)
- Modify: `src/StarterPlayer/StarterPlayerScripts/SkyClient.client.lua:364-369` and its 4 Hz update (`:450-484`) to read LookTune
- Modify: `src/ServerScriptService/SiliconCore.server.lua:4290-4400` (the Bloom and Atmosphere set-up reads LookTune)
- Test: `tests/offline/looktune.spec.luau`

**Interfaces:**
- Produces: `LookTune.DAY = { ambient: Color3, outdoor: Color3, bloomIntensity: number, bloomThreshold: number, haze: number, density: number, gradeContrast: number, gradeSaturation: number }` and `LookTune.NIGHT` with the same fields. `LookTune.at(day: number 0..1) -> same shape`: the blend SkyClient applies. `LookTune.luma(c: Color3) -> number`.

- [ ] **Step 1: Write the failing spec.**
  - `day ambient luma <= 0.30` and `outdoor luma <= 0.45`. Today's DAY_AMB (84,92,116) measures 0.36 and DAY_OUT (120,132,160) measures 0.52, so both fail: this is part of the overexposure.
  - `bloomThreshold >= 1.8` and `bloomIntensity <= 0.3` (bloom catches lights, not white walls).
  - `haze <= 0.25`, `gradeContrast` in 0.05..0.20, `gradeSaturation` in 0.05..0.20.
  - `at(1)` equals DAY and `at(0)` equals NIGHT.
  - Night ambient luma >= 0.10 (Review Focus 1: the night is not black).
- [ ] **Step 2: Run** `lune run tests/offline/run`. Expected: `looktune.spec` fails to load (no module).
- [ ] **Step 3: Implement LookTune** with today's values as the starting point (DAY_AMB, DAY_OUT and SVBloom 0.4/1.6 from SiliconCore:4300, haze 0.7), and move them into the spec's bounds: day ambient (70,76,96) (luma 0.30), day outdoor (100,110,134) (luma 0.43), bloom intensity 0.25, threshold 2.0, haze 0.2, contrast 0.10, saturation 0.10. The night values stay as they are; night ambient (30,34,54) is luma 0.14. SkyClient and SiliconCore read them; no other value moves in this task.
- [ ] **Step 4: Run the specs.** Expected: all pass.
- [ ] **Step 5: Live check.** In Play, Lighting's Bloom and Atmosphere read the new values at ClockTime 13.5 (execute_luau, Client). Capture C1/C2 and run look_stats. Record the numbers in `baseline.md` under "after Task 2". Not expected to pass yet: the surfaces are still pale.
- [ ] **Step 6: Commit**: "One table for the daytime light (LookTune); bloom only on lights, a quarter of the haze".

### Task 3: Real materials where they carry meaning, and two accent anchors

**Files:**
- Modify: `src/ServerScriptService/FlatLook.lua` (`flatten`: tagged parts keep their material)
- Modify: `src/ReplicatedStorage/Palette.lua:43-55` (anchors Teal, Coral)
- Test: `tests/offline/palette.spec.luau` (new; load Palette with the `roblox_globals` stubs, or move the anchor table and `map` into a pure `PaletteCore` the spec can load if Palette's `GetService` at load blocks Lune)

**Interfaces:**
- Produces: tag `SVKeepMaterial` (CollectionService). FlatLook leaves a tagged part's material if it is Wood, WoodPlanks, Fabric or Metal. Any other tagged material is flattened, and a `warn` names the part. Anchors `Teal` (40,150,160) and `Coral` (236,104,84) at full strength.

- [ ] **Step 1: Write the failing spec.**
  - `Palette.map(Teal) == Teal` and `Palette.map(Coral) == Coral` (today teal maps onto ValleyBlue and coral onto Oak).
  - For every colour in `TowerFinish` (all three finishes) and `Wafers.TINT`, `Palette.map(c)` is the same before and after the change. Snapshot the before-values into the spec. This is Review Focus 4.
- [ ] **Step 2: Run.** Expected: the Teal and Coral cases fail.
- [ ] **Step 3: Add the two anchors.** Add the `SVKeepMaterial` branch at the top of `flatten`, before the ground branch, with the four-material allowlist.
- [ ] **Step 4: Run the specs.** Expected: all pass. Then selene.
- [ ] **Step 5: Doctor check.** Add to GameDoctor's world step `"kept materials"`: every `SVKeepMaterial` part still has an allowed material and none is lawn-coloured ground (BUG).
- [ ] **Step 6: Commit**: "FlatLook keeps wood, fabric and metal where they are tagged; Teal and Coral join the palette".

### Task 4: The garage, restyled to the mock

**Files:**
- Modify: `src/ReplicatedStorage/GarageLayout.lua:62-149` (new pieces: 3 plants, a string-light run, a desk lamp)
- Modify: `src/ServerScriptService/GarageDress.lua` (colours `:26-41`, cladding `:437`, wainscot `:456`, floor, rugs `:69-75` via layout, the new pieces)
- Test: `tests/offline/garagelayout.spec.luau`

**Interfaces:**
- Consumes: `SVKeepMaterial` and the Teal/Coral anchors (Task 3).
- Produces: GarageLayout pieces `Plant1..3`, `StringLights`, `DeskLamp`. Each is a normal layout piece, so `L.check` covers it.

**Target colours, read off `garage-outside.png` and mapped through the palette:**

| Surface | Colour | Material |
|---|---|---|
| floor | oak (150,104,64) | WoodPlanks, tagged |
| wall cladding | warm (226,206,176) | was (238,226,204) |
| wainscot band | Teal (40,150,160) | was sage |
| rugs | Teal | Fabric, tagged |
| sofa | Coral | Fabric, tagged |
| slats | stay Wood (128,88,56) | now tagged so they keep the grain |

- [ ] **Step 1: Write the failing spec cases.**
  - The 5 new pieces exist.
  - `L.check()` still reports no problems: nothing in the walkway, pads, desk or door, nothing over a window.
  - Every new piece is at least 2 studs from the client queue spot and the laptop's E-prompt reach.
  - The string-light run is above head height (bottom ≥ 8 studs off the floor).
- [ ] **Step 2: Run.** Expected: the new-piece cases fail.
- [ ] **Step 3: Add the pieces to GarageLayout, and dress them plus the recolours in GarageDress.**
  - `Bulb` parts are Neon, 0.4 studs, one every 2.5 studs along the run.
  - The desk lamp is a warm PointLight (Range 10, Brightness 1.2) aimed at the laptop. It is the one thing that makes the laptop the brightest object (spec §6, C1).
- [ ] **Step 4: Run the specs and selene.** Expected: all pass.
- [ ] **Step 5: Live check.** `lookcam` C1 capture, then look_stats. Record it in `baseline.md`.
- [ ] **Step 6: Commit**: "The garage looks like a startup: oak floor, teal wainscot, coral sofa, plants, string lights, a lamp on the laptop".

### Task 5: The forecourt and the growth lot

**Files:**
- Create: `src/ReplicatedStorage/ForecourtPlan.lua` (pure)
- Modify: `src/ServerScriptService/CampusArch.lua:1006-1200` (`grounds`: build ForecourtPlan's props; ForecourtField colour)
- Modify: `src/ServerScriptService/SiliconCore.server.lua` (the growth lot shows only while the HQ is at garage levels and a next level exists)
- Test: `tests/offline/forecourtplan.spec.luau`

**Interfaces:**
- Consumes: `WalkLanes.build()` (lanes), the GarageLayout door and the drop-off/queue positions (read the plot-relative values CampusArch already uses; name them in ForecourtPlan as constants with their source line).
- Produces: `ForecourtPlan.PROPS`: a list of `{ name: string, kind: "bench"|"bikerack"|"planter"|"mailbox"|"lotFence"|"crane"|"comingSoon", cf: CFrame (plot-relative), size: Vector3 }`. `ForecourtPlan.check(props?) -> { string }`: problems, empty when clean.

- [ ] **Step 1: Write the failing spec.**
  - `check()` returns `{}`.
  - Each prop's footprint is at least 3 studs from the main path, the entrance court, the door, the drop-off ring and the client queue.
  - At plot 1's world pivot, no prop is within `WalkLanes` reach (lane centre ± keep ± 1.9) of any lane. This is Review Focus 5.
  - Every prop lies inside the plot slab.
  - The growth lot (`lotFence`, `crane`, `comingSoon`) sits on the garage's right side, as in the mock.
  - `comingSoon` is a frame with NO text: the game never draws words in the world for this.
- [ ] **Step 2: Run.** Expected: it fails to load.
- [ ] **Step 3: Implement ForecourtPlan and build the props in `CampusArch.grounds`.**
  - Parts only, bevelled with the existing `SVStyle`/motif helpers.
  - The bench is oak and charcoal, the mailbox charcoal with a Coral flag, the planters concrete with Foliage.
  - ForecourtField moves from (214,208,196) to (190,182,170), a value step down so the frame stops going white.
  - The crane and its lot show only at garage levels with a next level available.
- [ ] **Step 4: Run the specs and selene.** Expected: all pass.
- [ ] **Step 5: Live check.** `lookcam` C2 capture, then look_stats. Then the doctor's world step: "walkers through walls and props" 0, "drop-off reaches the street" ok.
- [ ] **Step 6: Commit**: "The forecourt is a place: bench, bike rack, planters, a mailbox, and a fenced lot with a crane while the next level is coming".

### Task 6: The look review, tuned to the targets

**Files:**
- Modify: `src/ReplicatedStorage/LookTune.lua` (tuning only)
- Modify: `src/ReplicatedStorage/StyleBaseline.lua` (new counts, with the reason on each changed line)
- Create: `../ui/art-pass/review-1.md` (outside git)

- [ ] **Step 1: Capture.** C1 and C2 at ClockTime 13.5. Then C1 at night (ClockTime 22). Then C1 and C2 at Graphics Quality 1. Run look_stats.
- [ ] **Step 2: Tune.** Adjust only LookTune numbers until C1 and C2 day pass all four targets, and Quality 1 passes with contrast ≥ 0.40. At night, near-black (luminance < 0.08) must be ≤ 35%, and the laptop and client must be findable on the capture. Each round of tuning gets a row in `review-1.md`.
- [ ] **Step 3: The full doctor and SVStyle.**
  - The doctor (PR mode) shows no BLOCKER and no new BUG.
  - Run SVStyle: `offPalette` and `neonLoose` must not rise. `colours` and `sharp` may change; update StyleBaseline with one comment line saying why.
  - Part count per plot rises by ≤ 150, and zero translucent parts are added.
- [ ] **Step 4: Luke's look review.** Show `review-1.md`: captures side by side with `garage-outside.png` and the baseline. He answers "can you find the laptop and the client in under a second?" and says yes or no. A "no" goes back to Step 2. It is never shipped on the numbers alone.
- [ ] **Step 5: Commit, PR, doctor gate**: "Art pass 1: the light and the garage, measured against the picked mock". The PR body has the before/after table from `review-1.md`.

---

## The plans after this one (written when this one ships; spec §4)

- **Plan 2, the client's timer and walk-off (N8):**
  - The existing ClientBubble Patience bar (ClientsServer.lua:285-370, colours :627-634) becomes a round timer that turns red only near the end.
  - A tick sound in the last 8 s.
  - A sad walk-off (`leave` :577, walk-back :407-421) with a slumped pose.
  - The lost pay rises as the game's coin icon in grey.
  - Client looks are picked so none matches the player's avatar.
  - Specs on a pure `ClientMood` (stage from patience share, tick schedule).
- **Plan 3, the cars:**
  - Six svkit Blender meshes (game/blender) to the `cars-v2` silhouettes, painted in their one colour as vertex colour (exempt from the pack wash by the `SV` prefix).
  - `Cars.CATALOG` swaps template names.
  - The doctor's `cars` step keeps head room at ≥ 0.10. A spec checks the six colours are distinct (each pair ΔE ≥ 25).
- **Plan 4, tower office interiors:**
  - The `tower-office` look per department through `Wafers.TINT` and `furnish`: matte floors, navy and Coral accents, plants, and a second monitor from level 13.
  - Checked with all three finishes and camera C3.
