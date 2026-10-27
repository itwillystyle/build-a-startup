# Art pass 4: tower office interiors. Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

## Rulings (24 Oct)

Made by the main session on the 9 open questions (Luke delegated these calls). They override the plan's
own "Rulings" section where the two disagree. Ledger: `2026-10-23-art-pass-4-ledger.md`.

1. **Second monitor (and third plant): by COMPANY level.** Once the company reaches HQ level 13, every desk
   gets two (visible progress). This replaces the plan's ruling 1 (by the room's own level). Built rooms are
   re-dressed when the company crosses 13.
2. **Feature wall: flat oak COLOUR** (SmoothPlastic, no Wood material; ART.md's ban stands, no spec change).
3. **Window glass: keep 1d's Transparency 0.3** (no new translucent parts rule).
4. **Lobby: new floor colour only**; it keeps its reception, sofa, the 1c photo and TV.
5. **No plants on ground-floor (storey 0) rooms: OK.**
6. **Department colour drift** (the palette repaints 5 of 7 tints): leave it; logged as a separate item.
7. **Department table as proposed** (servers: dark navy wall, no rug or plants; Cafe and Boardroom get a rug).
8. **Far-room hiding (Task 5) is built, not optional, and also covers today's desks and chairs.**
9. **Floor material: no change now.** If the look review shows a shine, it comes back as a separate decision.

**Goal:** The HQ tower's office rooms look like Luke's picked `ui/art-pass/tower-office.png`: a matte grey floor,
an oak feature wall with a navy base, a navy rug with a coral border, plants, wall art in the department's colour, and a
second monitor on each desk from level 13. It works with all three finishes (Glass, Timber, Neon) and is measured on
review camera C3.

**Architecture:** One new pure module, `OfficeLayout`, holds each room as data, the way GarageLayout does for the
garage. That covers today's furniture (moved out of `Wafers.furnish` unchanged), the surfaces, the new dressing,
and a `check()` that proves nothing blocks a door, a seat, the station or the glass. It is injected with TowerPlan and
ServerRack (`.with(T, SR)`, the LiftPlan pattern, `Wafers.lua:29`). `Wafers.buildSegment` reads the surfaces, and a new
builder `OfficeDress` builds the dressing. Department identity goes through `Wafers.TINT` on the things that are
already the department's colour (monitor screens, `FurnitureKit.lua:635-636`) plus the new wall art. Everything else
is one shared look. If the far-room triangles go over budget, a client script hides the dressing in far rooms.

**Tech Stack:** Luau + Rojo, Lune offline specs, selene, GameDoctor, SVCheck, Studio MCP `screen_capture`, `tools/look_stats.py`.

**Spec:** `docs/superpowers/specs/2026-10-22-art-pass-design.md` (§1 pick, §3 targets, §4.4, §5, §6 C3, §7 AVOID).
Model and lessons: `plans/2026-10-22-art-pass-1-light-and-garage.md` and `plans/2026-10-22-art-pass-1-ledger.md`.

**Branch / worktree:** `art-pass-4` in `silicon-startup/game-tower`, from origin/main. Plan 3 (`art-pass-3-cars`,
`game-cars`) is in flight. It does not touch the files below, but rebase before the PR.

## Global Constraints

- Parts and built-in materials only. No meshes, uploads or textures (spec §7). Furniture comes from the kit already in the place (FurnitureKit).
- Zero new translucent parts (Transparency between 0.05 and 0.95). No new Neon: the only emissive look is the existing `Glow` screen (`Palette.EMISSIVE_OK`, `Palette.lua:104-110`).
- Every new colour must sit on an anchor: `Palette.map(c) == c` (`Palette.lua:213-250`). **No new anchors.** Navy lives in the ValleyBlue family at low value; Coral is exactly (236,104,84), because an accent anchor accepts only ±2 (`Palette.lua:181-188`).
- Grain (`SVKeepMaterial`) only on rugs (Fabric), per spec §5. The feature wall is architecture. ART.md:64 and :125 ban Wood on buildings, so it is oak-coloured SmoothPlastic.
- No change to TowerFinish, TowerArt's facade or glass, the lift, seats, the station, signs or WaferPlan. The 1c lobby moment and the 1d finishes must look unchanged from the plaza except through the glass.
- Targets on C3 (spec §3): near-white ≤ 10%, mean 0.45-0.68, contrast ≥ 0.50, colour strength ≥ 0.32. Night: near-black ≤ 40% (plan 1 accepted 40%, ledger Task 6). Graphics Quality 1: contrast ≥ 0.40.
- Captures come only from Studio `screen_capture`, never from Luke's screenshots. They were HDR, and that is the premise plan 1 got wrong (ledger Task 1).
- Wilz's save: take the `snapshot` scenario before any Play test, restore it after Stop, and leave Studio in Edit.

## Measured inputs (23 Oct, offline, by script; not yet live)

- **The mock**, `look_stats.py tower-office.png`: mean 0.497, spread 0.70, sat 0.444, blown 0.039 (PASS). Sampled colours: floor (214,199,195) / (183,192,214), rug navy (49,80,131), sofa navy (12,35,79), coral cushion (251,140,99), coral chair (193,75,49), wood wall (205,148,99).
- **The mock's navies fall off the palette.** Run through `Palette.map`: (49,80,131) becomes (73,96,131) and (12,35,79) becomes (44,58,79), both slate. These pass `Palette.compliant` as ValleyBlue and map onto themselves: NAVY (38,66,108) and NAVY_DEEP (26,48,80). FLOOR (196,188,174) is PaperWhite-compliant (luminance 0.74, not blown). Oak (192,138,85) and Coral are compliant. This is the same trap that hit plan 1's teal, and here it is avoided without a new anchor.
- **Rooms** (TowerPlan.room): storey 0 is 46.7 x 38.7, storey 1 is 33.3 x 30.7 (side rooms 30.7 x 33.3), storey 3 is 32.3 x 28.0. Each room's back wall (room -Z) is always a partition with a door (8 to the hall, 6 for a corner). `T.YAW` (`TowerPlan.lua:104`) and `T.room` sides (`:106-128`) show this.
- **The doctor's department mix** (`WaferPlan.recommend`, `WaferPlan.lua:158-173`, used by `hq:<n>` through `DevHook.lua:65-86`). At hq:18 the rooms are lobby, studio, cafe and servers only. **There is no desk room at level 13 or above**, so C3 needs a room built to order (Task 1). At hq:100 the 88 rooms are eng 40, labs 20, studio 10, cafe 9, servers 7, board 1, lobby 1.
- **Today's furniture is tinted by the pack wash.** `FK.put` renames vertex pieces ("Desk", "Chair") and sets Color white (`FurnitureKit.lua:418, 453-457`). So `Palette.needsWash` (`Palette.lua:277-282`) multiplies them by (240,229,211). `serverrack.spec.luau:34` exists because of this. Read in code, not measured. This plan does not change it.
- **Performance today.** Plaza view at hq:100 (1d method, `game/.superpowers/sdd/2026-10-16-hq-art-1d/progress.md:38`): 537-550k triangles and 259-282 draw calls across the three finishes (`progress.md:39, 56`). That is **already over** the 500k rule, an open item for Luke (1d final review I4).

## Part budget (counted from code; FK pieces assumed 1 MeshPart each, since the vertex kit is "joined into ONE mesh per piece", `blender/furniture.py:8`; Task 1 measures the real counts)

| Room today | shell | furniture | total |
|---|---|---|---|
| edge room (Floor, Ceiling, 7 walls, CeilingStrip, RoomTone, DeptSign: `Wafers.lua:548-560, 590, 946`) | 12 | | |
| corner room (6 walls) | 11 | | |
| eng / labs (2 workstations × desk, Monitor, Glow, Keyboard, Chair: `FurnitureKit.lua:624-644`) | | 10 | 21-22 |
| studio 3, cafe 5, board 2, servers 8 (4 rack meshes + 2 fans × 2; 12 with box racks) | | 2-8 | 13-20 |
| seg 3 adds the station (2, `Wafers.lua:392-407`); a room over a deck has no Floor (-1) | | | |

Facade art (`TowerArt.facade`) is not counted, because this plan leaves it alone.

**Budget for this plan:**
- **≤ 12 new BaseParts per room**: rug 2, wall base 2, art 1, plants 2-3, second monitors 2 × (screen + Glow).
- **≤ 96 per storey.** From the doctor's mix (servers 0, lobby 0, no plants on storey 0): **+91 at hq:18 and +859 at hq:100.**
- Triangles: plaza view at hq:100 **≤ +10,000 per finish** compared with Task 1's baseline. Draw calls stay ≤ 400.
- Server build of `hq:100` takes at most 20% longer than the baseline.
- Tasks 1 and 4 measure all of this. Over budget triggers Task 5.

## Rulings (where the spec or mock leaves a choice; each one is in the open questions)

1. **Second monitor and third plant by the room's own level** (`L >= 13`), not by the company's level. This is pure and needs no re-dress of built rooms. Cost if wrong: one rebuild pass in `buildUpTo`.
2. **The lobby (L2) changes only its floor colour.** It already has the reception, its queue, the sofa and the 1c art (`Clients.lua:223-233`, `Wafers.lua:445-447, 504-535`).
3. **No standing dressing on storey 0.** Saved decor that overlaps tower furniture is refunded on load (`SiliconCore.server.lua:2620-2630`, `Wafers.decorOk` `:155-186`). Flat and wall pieces join `CLEAR_OF` (`Wafers.lua:154`).
4. **Per department:** servers get a NAVY_DEEP wall and no dressing (no rug, base, art or plants: it is a machine room). eng, labs, studio, cafe and board get the full look. The department colour shows only on the screens and the wall art, which keeps each view at 3 accents (navy, coral, tint; spec §7).

## AVOID (each is a rejection in the look review)

- The mock's own navy values (they turn slate). Painting vertex meshes navy or coral: a tint multiplies the mesh's colours into mud, as the coral sofa did in plan 1 (ledger Task 4).
- Wood or Concrete grain on walls. Glossy floors. Art SurfaceGuis with LightInfluence 0 (they read as lit screens).
- Text or logos in the art. Purple. More than 3 accents in one view.
- Building the mock's sofa, TV, rack, ceiling slats or pendant lights in this plan (parts budget).
- Touching TowerFinish, the facade, or the glass transparency.

## Review Focus

1. **Saved decor refunded.** A player's decor on the lobby storey vanishes (refunded) because new dressing blocks it. Task 4's spec asserts that storey 0 gets no plants and that every flat or wall piece is in `OfficeLayout.FLAT_NAMES`, which Wafers' `CLEAR_OF` reads.
2. **Staff seats move.** Moving furnish into data must not shift a single seat (StaffRig and Seating read them through `Wafers.seats`, `Wafers.lua:1005-1018`). Task 2 snapshots every department's seats, and the doctor's "move pins and seats" check runs live.
3. **Night.** A darker floor and navy rug could make the 4-minute night black indoors. Task 6 captures C3 at ClockTime 22: near-black ≤ 40%, and the desk is findable.
4. **Phones (Quality 1, far towers).** Contrast must come from colour, and far rooms must cost nothing. Task 6 captures C3 at Quality 1. Task 5's spec asserts that the cull's near radius is larger than any room plus camera reach, so a player in a room never sees its dressing vanish.
5. **Rebuild time.** A save at hq:100 rebuilds 99 pieces at once on join. Task 4's live check times the `hq:100` scenario against the Task 1 baseline (≤ +20%).

---

### Task 1: The ruler for C3: a room built to order, the camera, a night metric, the baseline

**Files:**
- Modify: `src/ReplicatedStorage/DoctorProbes.lua:370-391` (C3, `REVIEW_ROOM`, `roomCam`)
- Modify: `src/ServerScriptService/DevHook.lua:65-86` (`wlevel` honours pins; new action `wdept`)
- Modify: `src/ServerScriptService/DevScenarios.lua:39-42, 259-264` (`office:<dept>`, `finish:<key>`, `hq` returns `secs`)
- Modify: `tools/look_stats.py`, `tools/look_targets.json` (`dark` metric, `--night`)
- Test: `tests/offline/doctor.spec.luau`
- Create (outside git): `../ui/art-pass/baseline-4.md`, captures in `../ui/art-pass/shots/t4-*.png`

**Interfaces:**
- Produces:
  - `Probes.REVIEW_ROOM = { eng = { L = 13, hq = 18 }, studio = { L = 13, hq = 18 }, cafe = { L = 13, hq = 18 }, servers = { L = 13, hq = 18 }, labs = { L = 22, hq = 26 }, board = { L = 72, hq = 72 }, lobby = { L = 2, hq = 18 } }`. Each L except the lobby is a seg 3 room, so the station is in view.
  - `Probes.roomCam(r) -> (eye: Vector3, at: Vector3)`, in the room frame (origin at the room centre on the floor, +Z toward the facade). The first pose is eye (-r.w/2 + 3.5, 6.5, r.d/2 - 7) and at (r.w/2 - 4, 3, -r.d/6), so the glass is on the right as in the mock.
  - `Probes.lookcam({ cam = "C3", level = L, hold = s })` finds the plot's `L%03d_segment_*` model, reads its `Storey`/`Seg` attributes, and builds the anchor from the plot folder's `Pivot` attribute (`SiliconCore.server.lua:1038`) the way `Wafers.anchor` does (`Wafers.lua:189-194`).
  - The scenario `office:<dept>` runs `wdept "L=dept"` from `REVIEW_ROOM`, then `wlevel "1!"`, then `wlevel "<hq>!"`.
  - The scenario `finish:<W_|T_|D_>` sets `s.hqPath` and `plot.hqPath` together, because `recompute` copies s into plot (`SiliconCore.server.lua:1315`). Run it before `office:`.
  - `look_stats.py` prints `dark` (share of pixels with luminance < 0.08). `--night` judges only `dark <= targets.night.dark_max` (0.40).

- [ ] **Step 1: Write the failing specs in `doctor.spec.luau`.**
  - For every `REVIEW_ROOM` entry: `WaferPlan.PIECES[L].kind == "segment"`, the department is in `WaferPlan.allowed(L)`, `L <= hq`, and seg is 3 except for the lobby.
  - For every segment room on storeys 0-13: `roomCam(r)`'s eye lies inside `T.inner(r)`, its y is in 5..8, `at` is inside the room, and the look has a +X component.
- [ ] **Step 2: Run** `~/.rokit/bin/lune run tests/offline/run`. Expected: the new cases fail (`REVIEW_ROOM` is nil).
- [ ] **Step 3: Implement** the probe, the DevHook pin (`s.deptPin[x] or recommend(...)`) and the two scenarios. Also: the `hq` scenario returns `secs = os.clock() - t0`; `look_stats` gets `dark` and `--night`; `look_targets.json` gets `"night": { "dark_max": 0.40 }`.
- [ ] **Step 4: Run** the suite and `python -I tools/look_stats.py --selftest`. Expected: all pass, `3 cases, 3 as expected`.
- [ ] **Step 5: Live baseline (main session, Studio).** Run scenario `snapshot`, then Play as Wilz. Set daytime with `workspace:SetAttribute("SVClockOverride", 13.5)` (`SkyClient.client.lua:456`). For each finish W_, T_, D_: run `finish:<key>`, then `office:eng`, then `lookcam {cam="C3", level=13, hold=8}`, then capture `t4-base-C3-eng-<key>.png`. In W_ also capture studio, cafe and servers (level 13), labs (22), board (72) and lobby (2). Then take eng at night (override 22) and eng at Quality 1 (method not in plan 1's ledger: write down how you set it). Record per capture: look_stats `mean spread sat blown dark`. Record per eng room model: BasePart and MeshPart counts. Record BaseParts under the plot's `Wafers` folder at hq:18 and hq:100. Record the plaza tris/draws at hq:100 for each finish (1d method). Record `secs` of `hq:100`. Then Stop, restore the save, and return to Edit.
- [ ] **Step 6: Stop rule (plan 1's lesson).** If baseline C3 eng already passes all four day targets on all three finishes, stop and ask Luke before Task 3. The surfaces may not be the problem, and dressing alone may be what is missing. Either way, put the numbers in `baseline-4.md` next to the mock's.
- [ ] **Step 7: Commit** "C3 review camera: any department's room built to order, a night metric, the tower baseline".

### Task 2: Today's furniture as data (no visible change)

**Files:**
- Create: `src/ReplicatedStorage/OfficeLayout.lua` (pure, `.with(T, SR)`)
- Modify: `src/ServerScriptService/Wafers.lua:429-471` (`furnish` iterates the data; racks and fans stay Wafers' local builders)
- Test: `tests/offline/officelayout.spec.luau`

**Interfaces:**
- Produces:
  - `OfficeLayout.with(T, SR) -> OfficeLayout`.
  - `OfficeLayout.furniture(dept: string, r: Room, L: number) -> { Piece }` with `Piece = { id: string, kind: "workstation"|"kit"|"racks"|"fan"|"rug"|"border"|"base"|"art"|"plant", key: string?, x: number, z: number, w: number, d: number, yaw: number (degrees), y0: number?, y1: number?, monitors: number?, canCollide: boolean? }`. All values are room frame, in studs.
  - `OfficeLayout.seats(dept, r) -> { { x: number, z: number, lookX: number, lookZ: number } }`.

- [ ] **Step 1: Write the failing spec: exactly today's rooms**, for `T.room(1, 1)`, `T.room(1, 3)` and `T.room(0, 1)`.
  - eng and labs: two workstations at x ±5.5, z `r.d/2 - 4`, yaw 180, monitors 1. Seats at (x - 0.3, r.d/2 - 6.6), looking +5 in z.
  - lobby: workstations at x ±r.w/4, plus `loungeSofa` at (T.LOBBY_SOFA.x, -r.d/2 + T.LOBBY_SOFA.zFromBack), yaw 0.
  - studio: `tableCross` (0,0), `chairModernCushion` (-3.7, 0.4, 90) and (3.7, 0.4, -90). Seats at (±3.7, 0.4), looking at (0, 0.4).
  - cafe: `tableRound` (0,0) with canCollide, chairs {0,2.6,180} {0,-2.6,0} {2.4,0,-90} {-2.4,0,90}. Seats look at (0,0).
  - servers: one `racks` piece with `rm = SR.midlineFor(T.inner(r).z)` and `doorway = r.terraceDoor ~= nil`, plus fans at x ±9, y 6.2, z `T.fanZ(r)`.
  - board: `tableCross` at x ±2.2.
- [ ] **Step 2: Run.** Expected: it fails to load (no module).
- [ ] **Step 3: Implement OfficeLayout.furniture/seats. `furnish` builds from them.** Seats become `CFrame.lookAt` at y 2.4, as in `Wafers.lua:433-437`.
- [ ] **Step 4: Run the suite and selene.** Expected: all pass.
- [ ] **Step 5: Live check.** At `office:eng`, count the room model's BaseParts and seats. They must equal Task 1's numbers, and `Wafers.seats(plot)` must give the same CFrames before and after (print them both ways). Run the doctor's `hq:18` step: no new BUG.
- [ ] **Step 6: Commit** "Office furniture as data (OfficeLayout); the rooms build exactly as before".

### Task 3: The surfaces: matte grey floor, oak feature wall, navy base

**Files:**
- Modify: `src/ReplicatedStorage/TowerPlan.lua` (add `T.backSide`)
- Modify: `src/ReplicatedStorage/OfficeLayout.lua` (`COLORS`, `surfaces`)
- Modify: `src/ServerScriptService/Wafers.lua:212-236` (`wallSide` returns its parts), `:545-558` (floor colour, back wall props)
- Test: `tests/offline/tower.spec.luau`, `tests/offline/officelayout.spec.luau`

**Interfaces:**
- Produces:
  - `T.backSide(r: Room) -> "px"|"nx"|"pz"|"nz"`: the plot side that is room -Z (yaw 0 gives nz, π/2 gives nx, π gives pz, -π/2 gives px).
  - `OfficeLayout.COLORS = { floor = {196,188,174}, oak = {192,138,85}, navy = {38,66,108}, navyDeep = {26,48,80}, coral = {236,104,84} }`.
  - `OfficeLayout.surfaces(dept) -> { floor: RGB, back: RGB?, base: RGB? }`. The lobby gets only the floor, servers get back = navyDeep with no base, and every other department gets back = oak with base = navy.
  - `wallSide(...) -> { BasePart }`.

- [ ] **Step 1: Write the failing specs.**
  - tower.spec: for every segment room on storeys 0-13, `r.sides[T.backSide(r)]` is a number, and on edge rooms it is 8.
  - officelayout.spec: every `COLORS` entry satisfies `Palette.map(c) == c` (load Palette with the `game` stub from `palette.spec.luau:7`). The navy entries are compliant as ValleyBlue. The floor's luminance is ≤ 0.80.
- [ ] **Step 2: Run.** Expected: the new cases fail.
- [ ] **Step 3: Implement.**
  - The floor uses `surfaces.floor` on every room. Storey 0 floors turn Concrete through FlatLook's ground rule (`FlatLook.lua:62-74`). Upper floors stay SmoothPlastic, Reflectance 0.
  - The back side's `partProps` take `surfaces.back` (SmoothPlastic).
  - The ceiling is unchanged; it is a Task 6 knob only.
- [ ] **Step 4: Run the suite and selene.**
- [ ] **Step 5: Live check.** Capture C3 eng in all 3 finishes and servers in W_. Then:
  - Run look_stats and ledger the numbers next to the baseline.
  - From the plaza, capture hq:18 in W_ (the floor shows through glass): Luke sees it in Task 6.
  - `SVCheck.run()`: "buried in a wall" and "through the glass" no higher than the baseline.
- [ ] **Step 6: Commit** "Tower floors go matte grey; each office gets an oak feature wall (navy in the server room)".

### Task 4: The dressing: rug, wall base, art, plants, a second monitor from level 13

**Files:**
- Modify: `src/ReplicatedStorage/OfficeLayout.lua` (`dressing`, `monitorSlots`, `doors`, `check`, `parts`, `SECOND_AT = 13`, `MORE_PLANTS_AT = 13`, `BUDGET = 12`, `FLAT_NAMES`)
- Create: `src/ServerScriptService/OfficeDress.lua` (builder)
- Modify: `src/ReplicatedStorage/FurnitureKit.lua:624-644` (`workstation` takes `opts.monitors`)
- Modify: `src/ServerScriptService/Wafers.lua:154` (`CLEAR_OF` adds `FLAT_NAMES`), `:588` (calls `OfficeDress.build` after furnish)
- Test: `tests/offline/officelayout.spec.luau`

**Interfaces:**
- Consumes: `furniture`, `surfaces`, `COLORS` (Tasks 2-3); `T.inner`, `T.corners`, `T.backSide`.
- Produces:
  - `OfficeLayout.dressing(dept, r, L, storey) -> { Piece }`. The piece ids are `OfficeRug`, `RugBorder`, `WallBase` (one per door span), `WallArt` and `Plant1..3`.
  - `OfficeLayout.monitorSlots(n) -> { { x: number, yaw: number, scale: number } }`. With 1 it gives `{ {0, 0, 1} }`, as today. With 2 it gives `{ {-1.05, 12, 0.9}, {1.05, -12, 0.9} }`.
  - `OfficeLayout.check(dept, r, L, storey, seg) -> { string }`.
  - `OfficeLayout.parts(pieces) -> number`.
  - `OfficeDress.build(model, anchor, r, dept, L, storey, deps: { FK, part, tint: Color3 }) -> number` (parts made).
  - `furniture()` now sets `monitors = (L >= SECOND_AT) and 2 or 1` on workstations.

**Dressing (room frame; the back wall's room face is at z = -r.d/2 + T.WALL_T):**

| Piece | Where | Look |
|---|---|---|
| OfficeRug + RugBorder | under the furniture group: eng/labs (0, r.d/2 - 5.2), min(r.w - 8, 20) × 7.5; studio (0, 0.2) 10 × 6; cafe (0,0) 8 × 8; board (0,0) 12 × 5.5. The border is 0.6 larger on every side | navy Fabric (top at +0.08) on a Coral Fabric border (top at +0.05), both tagged `SVKeepMaterial` |
| WallBase | the back wall's two spans, outside the door gap, y 0..1.2, 0.08 deep | navy SmoothPlastic |
| WallArt | the back wall, centre x = -(door/2 + 3.25), y 5.5..8.9, 4.5 wide, 0.15 deep | the part is Ink (30,37,48) as the frame. A SurfaceGui (LightInfluence 1, MaxDistance 90, no text) draws a PaperWhite mat, the top 60% in the dept tint, the bottom 30% NAVY, and a Coral circle |
| Plant1, Plant2 | the front corners (±(inner.x - 0.8), inner.z - 0.8) | FK `pottedPlant`; skipped if `FK.has` is false |
| Plant3 (L ≥ 13) | the back corner away from the station (inner.x - 0.8, -inner.z + 0.8) | same |
| MonitorB (L ≥ 13, desk rooms) | desk slot 2 of `monitorSlots(2)`, Glow in the tint | its SurfaceGui MaxDistance is 90 |

The servers room gets no dressing at all. Its look is the NAVY_DEEP wall from Task 3 (Ruling 4). The lobby gets nothing. Storey 0 gets no plants (Ruling 3).

- [ ] **Step 1: Write the failing spec.**
  - For storeys 0-13, every segment seg 1-8, every department allowed there, and L ∈ {12, 13}: `check(...)` returns `{}`. That means:
    - every standing piece is inside `T.inner(r)` and the corner panels (as `tower.spec.luau:388`);
    - no standing piece is in a door approach box `doors(r)` (door width + 2, 4 deep);
    - every plant is ≥ 1.5 from every seat;
    - the station's footprint + 1.5 on seg 3 is clear;
    - pieces don't overlap each other or the furniture (rugs excepted);
    - the art sits outside the door gap.
  - `parts(dressing ∪ the second-monitor delta) <= 12` in every room. eng at L 13 gives exactly 12.
  - `dressing("lobby", ...)` is empty. On storey 0 no piece has kind "plant". Every flat or wall id is in `FLAT_NAMES`.
  - `monitorSlots(2)`: each monitor at scale 0.9 (2.08 wide) lies within the desk's half width 2.16 (`FurnitureKit.lua:80`), and the two do not overlap. `monitorSlots(1)` is today's slot.
- [ ] **Step 2: Run.** Expected: it fails (no `dressing`).
- [ ] **Step 3: Implement** `dressing`, `check`, `doors` and `parts`; `OfficeDress.build`; `FK.workstation` with `opts.monitors`; the Wafers calls. OfficeDress tags every part it makes `SVDressing` (Task 5 uses the tag), including MonitorB and its Glow.
- [ ] **Step 4: Run the suite and selene.** Expected: all pass.
- [ ] **Step 5: Live check.**
  - Capture C3 for eng in W_, T_ and D_, and for studio, cafe, servers, labs, board and lobby in W_. Run look_stats on each.
  - Measure the eng L13 room's new BaseParts (≤ 12) and the plot's `Wafers` total delta at hq:18 (≤ 100; code count 91) and hq:100 (≤ 900; code count 859). A Kenney fallback plant has 2 parts (`FurnitureKit.lua:181-182`), so a bigger delta means the vertex kit is missing. Ledger which kit you found.
  - Measure the plaza tris/draws at hq:100 for each finish, and the `secs` of `hq:100` (≤ +20%).
  - `SVCheck.run()`: furniture inside furniture, buried and through-the-glass no higher than the baseline.
  - Doctor: "kept materials" ok, and "move pins and seats" ok.
  - Ledger every number.
- [ ] **Step 6: Commit** "Offices dressed like the pick: navy rug with a coral edge, oak wall, art in the department's colour, plants, two monitors from level 13".

### Task 5: Far rooms cost nothing (only if Task 4 measured a plaza delta over +10,000 triangles or draws over 400)

**Files:**
- Create: `src/StarterPlayer/StarterPlayerScripts/OfficeCullClient.client.lua`
- Modify: `src/ReplicatedStorage/OfficeLayout.lua` (`CULL = { far = 160, near = 140 }`)
- Test: `tests/offline/officelayout.spec.luau`

**Interfaces:**
- Consumes: the `SVDressing` tag (Task 4).
- Produces: a client loop twice a second, like `TreeCullClient` (`TreeCullClient.client.lua:1-60`). Each `SVDressing` part farther than `far` from the camera gets `LocalTransparencyModifier = 1`; under `near` it gets 0.

- [ ] **Step 1: Write the failing spec.** `CULL.near < CULL.far`. `CULL.near >=` the largest dressed room diagonal (storey 1: 45.3) + 60 (camera reach; this assumes a zoom limit we did not verify, so ledger the live value). `CULL.far` is less than the 1d plaza camera's distance (eye at plot (-60,18,230)) to the podium front (z 54, `T.rect(0)`), which is about 176.
- [ ] **Step 2: Run.** Expected: it fails (no `CULL`).
- [ ] **Step 3: Implement** `CULL` and the client script.
- [ ] **Step 4: Run the suite and selene.**
- [ ] **Step 5: Live check.** Re-measure the plaza at hq:100 for each finish; the delta against baseline must be ≤ +10,000. Walk into an L13 room and through the lift: nothing pops within 140.
- [ ] **Step 6: Commit** "Far offices hide their dressing on your screen (as trees do)". If this task is skipped, ledger "not needed" with the Task 4 numbers.

### Task 6: The look review, tuned to the targets, with all three finishes

**Files:**
- Modify: `src/ReplicatedStorage/OfficeLayout.lua` (tuning only: the `COLORS` values (floor value step), rug sizes, and a `ceiling` entry if it is the blown area)
- Create (outside git): `../ui/art-pass/review-4.md`

- [ ] **Step 1: Capture** every Task 4 view again. Add C3 eng in W_ at night (`SVClockOverride` 22) and at Quality 1.
- [ ] **Step 2: Tune.** Change only OfficeLayout values until C3 eng passes all four day targets on all three finishes. Quality 1 needs contrast ≥ 0.40. Night needs `--night` PASS and the desk findable. Each round gets a row in `review-4.md`. A colour that changes must still pass Task 3's palette spec.
- [ ] **Step 3: Gate.**
  - Doctor PR mode: no BLOCKER and no new BUG.
  - `SVStyle.scan(plot Wafers folder)` at `office:eng`: `offPalette` and `neonLoose` no higher than Task 1's scan.
  - The count of translucent parts in the folder is unchanged.
  - Draw calls ≤ 400.
- [ ] **Step 4: A fresh reviewer compares the captures against `tower-office.png` (rule 17).** Then Luke's look review: `review-4.md` with captures side by side, the mock, the baseline, and each finish. He says yes or no. A no goes back to Step 2. It never ships on numbers alone.
- [ ] **Step 5: Commit, PR, doctor gate**: "Art pass 4: tower offices to the picked mock, measured on C3 with all three finishes". The PR body carries the before/after table and the part/triangle budget lines.

---

## Open questions for Luke

1. **Second monitor (and third plant): by room or by company?** The plan gives them to rooms built at level 13+. At the guide's own department mix, nothing at hq:18 is a desk room at 13+, so you would only see it if you pick Engineering or AI Labs there. Do you want "the company hits 13, every desk gets two"?
2. **Feature wall: flat oak colour or real wood grain?** ART.md bans Wood on buildings. The grain would need spec §5 to allow it on walls.
3. **The window from inside is a blue panel, not the mock's city view.** 1d set the glass to Transparency 0.3 for the facade. Keep it, or let all finishes go clearer? The facade would then show the dressed rooms.
4. **The lobby only gets the new floor colour.** It keeps its reception, sofa and the 1c photo and TV. Do you want the full look there too?
5. **No plants on the ground-floor rooms**, so your placed decor there is never refunded. OK?
6. **Department colours drift in the world.** The palette repaints 5 of 7 tints (Design Studio pink becomes peach, `palette.spec.luau` snapshot), so a floor's station does not match its HUD chip. Fix it (the HUD chips change too) or leave it?
7. **The department table:** servers get a dark navy wall with no rug or plants; Cafe and Boardroom get a rug. OK?
8. **Triangles.** The tower was already 537-550k against 500k after 1d (I4, still yours). Should the far-room hiding (Task 5) also cover today's desks and chairs? It is a cheap win.
9. **Floor material.** The ground floor is Concrete (FlatLook's rule); upper floors are smooth plastic. If the upper floors show a shine, may tagged floors keep Concrete (a spec §5 change)?
