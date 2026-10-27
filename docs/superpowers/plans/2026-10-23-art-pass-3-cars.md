# Art pass 3: the cars, Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the six Kenney cars with our own svkit Blender meshes that match Luke's picked mock
`ui/art-pass/cars-v2-chatgpt.png`, one vertex colour each, with the head room #65 fixed kept.

**Architecture:** A pure module `CarLook` holds what the game must not guess about each new mesh: its
template name, its paint, its length in studs, its measured roof height over the driver's head, its seat
drop and seat side. `blender/cars.py` reads the paint FROM `CarLook.lua` (one source), builds the six
meshes, measures the roof where the seated head is, exports FBX and renders. `Cars.lua` uses an `SVCars`
template when the place has one and falls back to the Kenney model (old scale, old seat drop) when not,
so nothing breaks before the Studio import lands.

**Tech Stack:** Luau (Rojo, Lune offline specs, selene), Blender 4.2 headless (svkit), Python + PIL for the sheet.

**Spec:** `docs/superpowers/specs/2026-10-22-art-pass-design.md` (§1 picks, §4.3 the cars, §7 AVOID) and
`plans/2026-10-22-art-pass-1-light-and-garage.md` "The plans after this one", Plan 3.

**Branch / worktree:** `art-pass-3-cars` in `silicon-startup/game-cars` (from origin/main 6e3d31d).

## Global Constraints

- Silhouettes and colours follow `cars-v2-chatgpt.png`, left to right: hatch green, sedan blue, SUV red,
  coupe yellow, racer orange (open-wheel), hyper purple. `cars-v1-gemini.png` was NOT picked.
- "The hypercar keeps the feel but NOT a real brand's shape."
- Colour is VERTEX colour (svkit); every part name starts `SV` so `Palette.needsWash` skips it
  (`Palette.OWN_PREFIX`), and the MeshPart Color stays white so `Palette.exempt` leaves it alone.
- Six colours pairwise distinct: ΔE ≥ 25 (CIE76, sRGB D65 -> Lab).
- Head room: the doctor's `cars` step needs roof - head top ≥ 0.10 studs on every closed car.
- §7: no textures to upload, no translucent parts, no Neon, no new on-screen text.
- Phones: under 2,000 tris per car, wheels included (chosen budget; the Kenney cars are textured, ~1-2k).
- Fit the parking bay (9 x 15, lines at x ±4.1): width ≤ 8.0, length ≤ 14.5.
- Offline only in this plan: no Studio MCP, no Play, no upload, no push.

## Rulings (spec vs mock; the mock wins)

1. **The hypercar is open-top** in the mock (a speedster: windscreen, two seats showing). Cars.CATALOG
   already marks it `open`; it stays open, so it is info-only in the doctor step, like the racer.
2. **The racer is a single-seater with a centred cockpit.** build() puts every seat at -0.18 of the width;
   the racer gets `seatSide = 0` so the driver sits in the middle of the tub.
3. **All six colours at once breaks "more than 3 accent colours in one view" (§7)** in the dealer row.
   The mock IS six colours in one view and Luke picked it, so the dealer row is exempt; the street (C4)
   still shows at most the cars that are parked there.
4. **Colours are the mock's lit body colour, sampled** (median of the mid-bright band of each car's hue
   mask), not palette anchors: CarLook comments the sample.

## Measured inputs (23 Oct, offline, by script)

- **The seated head top is 3.93 studs above the seat's centre** (Wilz's R15). Derived from #65's
  doctor numbers (clearance -0.63 hatch, +0.36 sedan, +0.38 SUV, -0.64 coupe at seatDrop 0) and the
  Kenney OBJ roofs at the head point (OBJ x 5 = studs: import x100, CAR_SCALE 0.05; the sedan is
  150x130x255 in Studio). All four cars give 3.92-3.94. The seat centre is 2.2 - seatDrop above the
  ground (RIDE 0.8 + chassis half 0.8 + 0.6), so the head top is **6.13 - seatDrop**.
  Check: Kenney hatch, seatDrop 1.0: 5.50 - 5.13 = 0.37; the doctor read 0.36-0.37 after #65.
- Head point: x = -seatSide x width, z = +0.08 x length behind the centre (Roblox +Z = back; Blender -Y).

## Review Focus

1. A place WITHOUT `SVCars` (the TEST experience, a fresh copy): every car must still build from Kenney
   at CAR_SCALE with its old seatDrop -> spec on `CarLook.pick` with no SV template.
2. The importer's unit guess (FBX cm vs studs): the mesh must be scaled by its LENGTH, not a constant
   -> spec on `CarLook.scaleFor` with a 100x-too-big size.
3. Wheels named `SV_Wheel_*` must still get Motor6D axles (build() matched only `wheel*`) and must not
   be washed -> spec on `CarLook.isWheel` (Kenney and SV names) and the SV prefix.
4. A head that is not exactly at the seat's centre: roof measured as the MIN over the head's 1.2 x 1.2
   footprint, not one ray -> the Blender measure and the spec use the footprint value.
5. Cars.lua drifting from CarLook's copy of the seat formula -> spec reads Cars.lua's source and
   asserts the seat line and RIDE still match.

---

### Task 1: CarLook, the colours and the head-room rule (pure)

**Files:**
- Create: `src/ReplicatedStorage/CarLook.lua`
- Test: `tests/offline/carlook.spec.luau`

**Interfaces:**
- Produces: `CarLook.FOLDER = "SVCars"`; `CarLook.CARS[id] = { mesh, rgb = {r,g,b}, length, width,
  roof (number|nil for open), open, seatDrop, seatSide }` for ids hatch, sedan, suv, sports, racer,
  hyper; `CarLook.HEAD = 3.93`; `CarLook.SEAT_UP = 2.2`; `CarLook.MIN_CLEAR = 0.10`;
  `CarLook.DESIGN_CLEAR = 0.30`; `CarLook.headTop(seatDrop) -> number`;
  `CarLook.clearance(id) -> number|nil`; `CarLook.deltaE(rgbA, rgbB) -> number` (CIE76);
  `CarLook.isWheel(name) -> boolean`; `CarLook.scaleFor(id, sizeZ) -> number`.

- [ ] Step 1: spec, failing: "six colours, each pair ΔE >= 25"; "deltaE is CIE76 (black/white = 100)";
  "the rule reproduces #65: Kenney hatch roof 5.50 at seatDrop 0 -> -0.63 (±0.02), at 1.0 -> +0.37";
  "every name starts SV"; "isWheel: wheel-default, SV_Wheel_FL yes; SV_Car_hatch, Chassis no";
  "scaleFor turns a 100x import back to the length"; "every car fits the bay".
- [ ] Step 2: `lune run tests/offline/run` -> FAIL (module missing).
- [ ] Step 3: write CarLook with the sampled colours (roof = nil for now).
- [ ] Step 4: run -> PASS; selene clean. Step 5: commit.

### Task 2: blender/cars.py, the six meshes

**Files:** Create `blender/cars.py` (outputs in `blender/out/cars/`, gitignored).

**Interfaces:** Consumes `CarLook.lua` (parses `rgb = { r, g, b }` and `seatDrop`/`seatSide`/`length`
per id). Produces `out/cars/SV_Car_<id>.fbx` (one body `SV_Car_<id>` + four wheels `SV_Wheel_FL/FR/RL/RR`,
nose to Blender +Y = Roblox -Z), `out/cars/cars_meta.lua` (size, tris, roof at the head centre, roof
min over the head footprint), `out/cars/render_<id>.png` from the mock's angle, `out/cars/row.png`.

- [ ] Step 1: build the six with svkit (prisms from side profiles, cabins tapered, windows inset and
  painted glass, dark bumpers, lights, 12-sided wheels with hubs), bevel 1-2 segments.
- [ ] Step 2: run headless; read the printed tris (< 2,000 each) and roof numbers.
- [ ] Step 3: look at every render against the mock; fix and rerun. Step 4: commit the script.

### Task 3: the measured roofs into CarLook, head room pinned

**Files:** Modify `src/ReplicatedStorage/CarLook.lua`; Test `tests/offline/carlook.spec.luau`.

- [ ] Step 1: spec, failing: "every closed car has a measured roof"; "every closed car clears the head
  by >= DESIGN_CLEAR (0.30), so the doctor's 0.10 holds with room"; "open cars are hyper and racer".
- [ ] Step 2: run -> FAIL (roof nil). Step 3: paste the footprint-min roofs from `cars_meta.lua`.
- [ ] Step 4: run -> PASS. Step 5: commit.

### Task 4: Cars.lua uses the new templates

**Files:** Modify `src/ServerScriptService/Cars.lua` (CATALOG :30-37, template :50-53, display :67-81,
build :84-149); Test `tests/offline/carlook.spec.luau`.

**Interfaces:** Consumes `CarLook.pick(entry, hasSV) -> { scaleMode = "length"|"kenney", seatDrop,
seatSide }` (added here) and `CarLook.isWheel`.

- [ ] Step 1: spec, failing: "pick with an SV template uses CarLook's drop/side and length scaling";
  "pick without one keeps the Kenney model's seatDrop (hatch/coupe 1.0) and CAR_SCALE";
  "Cars.lua's seat line and RIDE match CarLook (source read)"; "CATALOG models are CarLook's meshes".
- [ ] Step 2: run -> FAIL. Step 3: CATALOG `model = LOOK.<id>.mesh, kenney = "<old>"`; template()
  looks in `RS.SVCars` first; one `prepare(entry)` clones and scales for both build() and display();
  wheels by `CarLook.isWheel`; seat from `pick`.
- [ ] Step 4: run -> PASS; selene clean. Step 5: commit.

### Task 5: the review sheet for Luke

**Files:** `ui/art-pass/cars-review-1.png` (mock on top, our row below at the same angle),
`ui/art-pass/cars-review-1.md` (what matches, what doesn't, tris, roof clearance per car).

- [ ] Step 1: build the sheet with PIL from the mock + `out/cars/row.png`. Step 2: write the md.

## Live checks for the Studio lane (S-1, after Luke's look OK)

1. Import each `out/cars/SV_Car_<id>.fbx` (3D Importer, as a Model, keep vertex colours, do NOT merge
   meshes) into `ReplicatedStorage.SVCars`, named `SV_Car_<id>`; five MeshParts each; anchored,
   CanCollide off. Check MeshPart.Color is white (else the Palette maps it).
2. `GetBoundingBox` of each: the length/width ratio matches `cars_meta.lua` (scale is by length).
3. Doctor `cars` step (dev action `carfit`): every closed car `clear >= 0.10`; compare with CarLook
   (hatch, sedan, suv, sports predicted clearances in cars-review-1.md); open cars seated.
4. Sit in each: the head is not through the roof or a pillar; the feet don't show under the body.
5. Drive each: wheels spin the right way and the fronts steer (Front = chassis z < 0), no wobble.
6. Showroom + dealer pads + campus showroom: the six display, the right way round, on the pads.
7. Night: the cars read under the 4-minute night.

## Status (23 Oct, end of the offline lane)

Tasks 1-5 done on `art-pass-3-cars` (ced68cd, cfcbdcf, 898cb90, 3c21d9f, 7ad76b0, d8f1df5): 576 specs
pass, selene 0 errors. Measured: tris 1,680-1,980; clearances hatch 0.82, sedan 0.62, SUV 1.06, coupe 0.46.
Review: `ui/art-pass/cars-review-1.png` + `.md`. Next: Luke's look review, then the live checks above (S-1).
