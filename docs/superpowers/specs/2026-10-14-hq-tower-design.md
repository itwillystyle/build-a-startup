# HQ overhaul, project #1: the tower — design (14 Oct 2026)

Approved in conversation, 14 Oct. Luke: the HQ feels cramped and claustrophobic (low ceilings),
the garage inside the building looks unnatural, the outdoor glass lift looks sloppy, the night
lights look cheap, and the building looks "slapped into Blender in five seconds". This is project
#1 of the HQ overhaul (the order he approved: #1 the building, #2 interiors, #3 night lighting
inside rooms, #4 custom player cars, #5 the wall TV income, phase 4 of Manage Staff).

Process: CONSTRAINTS.md rule 17 (references → mocks → Luke's pick → code). The mocks are Blender
renders in `silicon-startup/ui/2026-10-14-hq/` (`heights.png`, `tower-concepts.html`,
`4-hybrid-day/night/close.png`; script `art/blender/tower_concepts.py`). Repo:
`Downloads/silicon-startup/game`. Re-check every file:line before editing.

## 1. Luke's decisions (each picked from options)

| Question | His pick |
|---|---|
| What happens to the building as the company grows | **It transforms**: you start in a real garage; your first upgrade replaces the garage with the tower's lobby |
| Floor height | **18-stud office floors, a 24-stud lobby** (today: 13 everywhere) |
| Elevator | **Doors in the core wall on every floor, a real ride** (cab moves, floor counter, ding) |
| The garage at the first upgrade | **The garage becomes the lobby**, in a ~4 s build moment |
| The look | **Concept 2's glass spire with concept 3's terraces**, with detail on every floor |
| The three HQ styles | **One shape, three finishes**: Glass, Timber, Neon |

## 2. The shape

- **Lobby (the first piece, built by the first upgrade; level and piece numbering stay as today, which the 1a plan checks against `wafer.spec`):** a 24-stud glass hall, 70 x 50 footprint with 12-stud rounded corners, warm
  wood columns along the front every 6 studs, a deep white canopy over the door, a thick white
  roof band. It stands where the garage stood; the forecourt, drop-off and street stay where they are.
- **Office floors (pieces 2 to 100):** 18 studs storey to storey (slab 1.5, so 16.5 clear).
  **8 rooms per floor** (the same 8 as today's segments per storey: 4 along the front, 4 along the
  back, either side of a central core), so 99 rooms make 13 floors (12 full + 3 rooms). (In chat this
  was "about 17 floors" at 6 rooms a floor; 8 keeps today's room code closer to working. Flagged to Luke.)
  Height: 24 + 13 x 18 = 258 studs, plus the crown (today's full tower: about 163).
- **Taper:** each floor is 3% narrower than the one below (concept 2).
- **Setbacks and terraces:** every 3rd floor the tower steps back 6 studs, alternating front and
  back (floors 3, 6, 9, 12), so a full tower stays balanced. Each step leaves a walkable terrace
  the length of the floor: glass railing with a handrail, planters, two small trees, two benches,
  two lamps. A floor above a terrace is shallower; its rooms shrink, their count does not.
- **Every floor's facade:** vertical fins on the long faces, window frames, a white floor band
  with a light line under it, rounded corners (the game's wafer motif).
- **The core:** a vertical shaft in the middle of every floor: the elevator doors, plus a small
  landing kept clear of furniture (the "walk in and it's in the way" fix starts here; project #2
  does the rooms).
- **The crown:** above the top floor, a glass crown with the company's lit logo plate and a mast.
- **Building in progress:** as today, each BUILD adds one piece (one room). An unfinished floor
  shows its built rooms and a clean edge (glass and frame) where the next room will go; the
  setback and terrace appear when their floor's first room is built.

> **Amended 14 Oct (evening), Luke: "fix the taper and the podium lobby"** after the shape review of the first build.
> Built (TowerPlan.rect): the lobby is a glass podium standing out past floor 1 by 9 studs at the sides, 6 at the
> front and 8 at the back, with a white roof band and wood columns every 6 studs along its front; every storey
> above steps in (100 wide at floor 1 to 80 at the roof, about 1.5% a floor, 20% in all) and the three setbacks stay
> at the garden storeys 2/6/10. Not the mock's 3% a floor on 52 x 34 floors: at 14 storeys that makes 13 x 11 rooms
> (the cramped rooms Luke asked to remove) and the top storey could not hold the lift shaft. Rooms stay >= 20 x 20.
> Still open: the garden storeys read as missing floors from the plaza (each is a whole open storey, not a terrace
> strip); rounded corners come with the 1d art.

## 3. Three finishes (the style picker stays; it now picks materials, not a shape)

| Finish | Look | Old style it replaces |
|---|---|---|
| **Glass** | blue glass, steel fins, white bands | Wafers (`W_`) |
| **Timber** | warm wood fins and columns, cream bands, many planters | Terrafab (`T_`) |
| **Neon** | dark glass, slim bright light lines, black bands | Dome (`D_`) |

A saved `hqPath` keeps working: `W_` reads as Glass, `T_` as Timber, `D_` as Neon. The picker's
three cards show the new tower in each finish.

## 4. Garage → lobby (the transform moment)

Before the first upgrade the player owns only the garage, as today. The first BUILD (after the
finish is picked) plays a ~4 s moment through the existing `Cine` module: the camera pulls back
to the plot, the garage folds down into the ground, the lobby rises in its place, the camera
returns to the player standing in the new lobby. After that the garage never exists again for
that company; a spin-off's new company starts in a garage again. Things that lived in the garage
move: the WRITE CODE laptop, the HIRE pad and the wall TV spot go into the lobby.

## 5. The elevator

A shaft in the core runs from the lobby to the top built floor. Every floor (and the lobby) has a
pair of doors in the core wall. Walking up to them shows a prompt; inside, a floor list (the
existing LiftMenu stops) picks the floor; the doors close, the cab travels with a floor counter
(about 1 s per floor, capped at 4 s), a ding, the doors open on the new floor. Only floors that
are landable (have a floor at the door, as `landable` does today) are offered. The outdoor glass
tube and the courtyard core go away.

## 6. Night

Dark glass with warm light behind it (low emission, never a flat glowing slab), one crisp light
line under each floor band, warm terrace lamps, a lit crown and logo. Finish-specific: Neon's
lines are brighter and coloured. The lighting inside rooms is project #3.

## 7. Under the hood

- **`WaferPlan` splits.** Its economy stays exactly as it is (MAX, BLUEPRINT, STAGE_AT, BASE,
  MULT, CAP, DEPTS, CHOOSABLE, allowed, effects, seats, recommend, prices). Its round geometry
  (`GEO`, `PIECES`, the inset and glass band) is replaced by a new pure module, **`TowerPlan`**:
  piece → floor, room slot, footprint rectangle, taper, setback side, terrace; floor → y; which
  floors are landable. Tested offline (`tower.spec`), with a golden file like `wafer_golden.json`.
- **The builder keeps the `Wafers` contract.** The 20-odd functions other code calls (`floorY`,
  `anchor`, `stage`, `counts`, `capacity`, `effects`, `seats`, `buildUpTo`, `clear`, `nextBuild`,
  `refreshSigns`, `stateOf`, `pathOf`, `pathName`, `PATHS`, `TINT`, `NAME`, `BLURB`, `towerSpec`,
  `level`, `init`, `clearFootprint`) keep their names and meanings, so SiliconCore, hiring,
  seating, StaffRooms, the TEAM screen, homes and the HUD do not change. `floorY(s)` returns the new
  heights.
- **Rooms keep their departments** (lobby, eng, studio, cafe, servers, labs, board), so staff pins
  and StaffRooms survive. Room furnishing is refitted to rectangular rooms at the new height (the
  existing furnish code, re-anchored); project #2 replaces it with detailed rooms.
- **Saves are safe:** the building is rebuilt from the saved level and path on every join; no
  saved field changes meaning.
- **Art** goes through the Blender pipeline (`rack_export.py` / `rack_check.luau` pattern): one
  facade module per room slot per finish, the terrace kit, the lobby, the core doors, the crown.
  The same few meshes repeat on every floor, so Roblox draws them as instances.

## 8. Verification (pass rules written now, before any results)

1. **Offline (`tower.spec`):** every piece 1..100 maps to exactly one floor and slot; floor y =
   24 + (f - 1) x 18 for office floors; 8 rooms per floor; setbacks on floors 3, 6, 9, 12 alternate
   sides; no room's footprint overlaps the core or another room; the tower's centre of mass at 100
   pieces stays within 4 studs of the lobby's centre (balanced); departments per piece match
   today's plan.
2. **Doctor, at HQ levels 5, 9, 13, 18, 43, 100:** stand on every storey (now 18-stud storeys),
   the elevator lands you on every landable floor, the camera never sits behind a wall, the
   drop-off is on the forecourt ground and the routes home reach the street, no meshes through a
   floor, no scripts twice, no script errors.
3. **Performance:** the full tower (level 100) seen from outside renders at **≤ 500k triangles
   and ≤ 400 draw calls** (ART.md; today's tower is 810k / 466). Measured with
   `Stats.SceneTriangleCount` as for the rack.
4. **Look:** every built part is compared with its mock by a fresh reviewer (rule 17) before Luke
   sees it, by day and at night, from the plaza and on a terrace.
5. **The transform moment** plays once per company, never on a rebuild after a spin-off-and-back,
   and leaves the player standing in the lobby (checked live).
6. **The gate:** `bas checkup pr` before each merge.

## 9. Parts (each its own plan and PR)

| Part | What | Goes live? |
|---|---|---|
| **1a** | `TowerPlan`, the builder on the new plan, new heights, rooms refitted, plain materials | No: branch only (plain boxes would look worse than today) |
| **1b** | The elevator (core, doors, cab ride) | With 1d |
| **1c** | The garage → lobby moment | With 1d |
| **1d** | The art: 3 finishes, terraces, lobby, crown, night lighting | Yes: 1a-1d ship together |

## 10. Out of scope

Room interiors and furniture (project #2), lighting inside rooms (#3), cars (#4), the wall TV
(#5), the economy (prices, caps, departments unchanged), the chase mechanics (only re-checked).

## 11. Risks

- **Height:** 258 studs is about 1.6x today's tower; long camera shots and the chase camera may
  frame it differently (the doctor's camera checks cover the chase).
- **Furnishing refit:** today's furnish code is written for 45-degree wedge rooms; rectangular
  rooms need new anchors. Seats must stay where staff can reach them (the doctor's seat checks).
- **Performance:** the new tower must be lighter than today's to pass check 8.3; the art is
  designed around instancing from the start.
- **Size:** this is the size of the original HQ build. It ships as 1a-1d so a stop part-way still
  leaves working code on a branch, not a broken live game.
