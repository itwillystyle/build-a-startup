# The Wafers HQ: one building, levels 1 to 100 (30 Sep 2026)

Status: **built and published (30 Sep 2026, 07:42 UTC).** HQ 100 rises with spin-offs. The plot extension is deferred (see Phase 3 results).

Concept: `art/concepts/formats/formats_W_sheet.png`, modelled on Samsung's San Jose HQ. Stacked office rings ("wafers"), each turned and shifted on the one below, with open garden decks between them and a glass lift core in the courtyard.

## What you asked for, and what this changes

| You said | Today | With the Wafers |
|---|---|---|
| One large connected building, not a bunch of square plots | An HQ box in the middle plus 6 separate room buildings on lots | One building. The rooms *are* the building: every piece is a curved segment of a wafer. |
| Curvature, low-poly look | Rounded boxes | Faceted rings (8 segments per storey), the same flat low-poly style as the valley. |
| Every floor has a purpose | The HQ's upper floors are themed but decorative; staff sit and earn in the outside rooms | Every segment is a department where staff sit and earn, or it has one stated effect (servers, decks). |
| Rooms should show the money they make | Only the HUD breakdown shows it | Each department floor shows its $/sec on the building, in the lift and on the HUD. |
| A bigger plot for a campus | Each plot is a flat 240 × 220 studs | The plot gets 80 studs deeper, to 240 × 300 (see "The plot"). The building sits back behind a real forecourt, with open land behind it for later creations. |
| HQ to level 100 | HQ 1-5 plus room levels | Level = pieces built, 1 to 100. Each spin-off unlocks more of the blueprint. |

## Decisions I made (change any of them)

1. **Your garage stays.** Level 1 is the garage, and the HQ grows *around* it: wafer 1's ring closes around the garage in the courtyard. You still spawn in the garage every company, write code on the same laptop, and walk out into your own courtyard. This is the image for the thumbnail.
2. **One level = one piece.** A piece is one storey of one 45° segment, a garden deck, or a crown part.
3. **You choose each segment's department** from the ones you've unlocked. The guide pre-selects the best one for your staff, so building is still one tap. Choice is what made Restaurant Tycoon's building worth doing.
4. **The blueprint grows with each spin-off** *(you confirmed this, 30 Sep)*. Company 1 can build to level 18 (wafer 1 plus the first garden deck, where you GO PUBLIC). Each spin-off unlocks the next half-wafer, and level 100 is reachable in company 8. That makes a spin-off's reward visible: "your next HQ can be 12 floors taller."
5. **Rebuilding is fast.** A spin-off still starts you in the garage. Below your record height, one BUILD tap rebuilds the rest of that storey (up to 8 pieces) with the departments you had, at 2.5% of the price. Your time goes to the new floors. *(Phase 1 set this: at 25%, and one piece per tap, rebuilding filled 75-80% of late companies.)*
6. **Round wafers, not ovals.** Circles let one segment mesh repeat 8 times per wafer, and they make collision, desk rows and lift bridges simpler. The offsets and cantilevers stay, so it still stacks like Samsung's. I'll render the round version for you to compare before anything is imported.
7. **You build from a BUILD button on the HUD**, with a pad in the lobby as the walk-up alternative. You don't walk to every segment, since 99 walks would be a chore. Normal pieces rise in place with a sound and a money pop. Only milestones get a camera shot.

## The building

Storey height 13 studs, slab 1.5. Each wafer is a ring 20 studs deep, 8 segments per storey. The lift core stands in the courtyard, with glass bridges to every wafer and deck.

| Levels | Piece | Departments you can choose |
|---|---|---|
| 1 | The garage (courtyard) | the garage desk (1 seat) |
| 2-17 | **Wafer 1**, 2 storeys × 8 segments. Level 2 is the Lobby (the entrance through the ring into the courtyard). | Engineering, Design Studio, Cafe, Server Room |
| 18 | **Garden deck 1**: open-air, running track, trees. Company 1 goes public here. | fixed |
| 19-42 | **Wafer 2**, 3 storeys × 8 | + **AI Labs** unlocks |
| 43 | Garden deck 2 | fixed |
| 44-67 | **Wafer 3**, 3 storeys × 8 | all |
| 68 | Garden deck 3 | fixed |
| 69-92 | **Wafer 4**, 3 storeys × 8 | + **Boardroom** unlocks |
| 93 | Roof garden | fixed |
| 94-97 | Founder pavilion (4 pieces) | fixed |
| 98-100 | Crown: halo, lantern, mast | fixed |

**Departments.** The seat and bonus values are today's room-level values. The sim will tune them.

| Department | Glass tint | Job | Staff who fit (earn x1.5) |
|---|---|---|---|
| Engineering | blue | +2 seats | engineers, researchers |
| Design Studio | pink | +2 seats, +10% money (studio cap +150%) | designers |
| Cafe | orange | +4 seats, +8% output (cafe cap +80%) | sales, recruiters |
| Server Room | dark, blinking | +1 compute: +10% launch payday | nobody sits here |
| AI Labs (level 19+) | teal | +2 seats, +15% product speed | researchers |
| Boardroom (level 69+) | gold | better investor offers (+1 interest) | nobody sits here |
| Garden decks, roof, pavilion, crown | trees / gold | milestone unlocks and money multipliers (below) | nobody sits here |

**Staff cap:** 1 plus your seats, up to the milestone cap: 8 / 14 / 20 / 26 / 30 as in today's HQ 1-5, then +2 per later deck, up to **40**. The hard stop is for performance, since avatars are about 3,300 triangles each. Past the cap, levels grow money through multipliers, not headcount.

## The plot

You said the plot can grow if it helps. Measured:
- **Today:** each plot is a flat 240 × 220 studs. Plots sit 360 apart along the main road, with the two cross streets in the gaps between them.
- **The Wafers:** about 150 × 120 studs, so the building alone fits today's plot, with room for a forecourt.

**Depth grows by 80 studs, to 240 × 300. Width stays the same.**
- **Width stays.** Widening means moving the cross streets and spreading all six plots apart, which reworks the whole map for no gain to the building.
- **Depth grows at the back.** Away from the road, nothing has to move except the two things behind the plots.

What the extra depth buys:
1. **A real setback.** In plot-local terms, the road side is the front:

   | From the road side | Depth |
   |---|---|
   | Forecourt: the arrival plaza, the car bay, and the lobby pad where recruits are dropped off | 70 studs |
   | The Wafers building | 120 studs |
   | A back garden | 110 studs |

   You drive in and see the whole building from the plaza, the way real HQs are set back from the street.
2. **Land for what comes next.** The back garden is empty lawn and trees for now, reserved for the luxury items that need ground (a rocket launch pad, a helipad) and your "other creations later". Reshaping the valley once now is cheaper than doing it twice.

What it costs:
- **The Caltrain line** moves 90 studs south, and **the two orchards** move 80 north, clear of the deeper plots.
- **The valley tiles near them are regenerated.** That's the existing `lp_world.py` pipeline, which exports only the tiles that changed, in one import batch.
- **Recruits have a longer carry.** The lobby door sits about 40 studs further from the sidewalk than today's HQ pad, so the headhunter chase simulator is re-run and the carry times re-tuned.

This is done in phase 3, while the plot is being re-laid anyway.

## Company 1: the same 26 minutes, new milestones

Today's HQ 2-5 become company 1's milestone levels, so the first run keeps its tuned pace: HQ 5 at 22.7 min in the bot, spin-off at 26.

| Level | Old equivalent | What it hands you |
|---|---|---|
| 5 | HQ 2 | the company car, STAR recruits, money ×1.6 |
| 9 (ground ring closes around the garage) | HQ 3 | GENIUS recruits, ×2.6. Needs the Studio home. |
| 13 | HQ 4 | the Series A, ×4.2. Needs the Loft. |
| 18 (garden deck 1) | HQ 5 | GO PUBLIC, ×7. Needs the Penthouse. |

In later companies, every garden deck is a milestone with its own banner and a bigger multiplier. The GO PUBLIC ceremony happens at the top of that company's blueprint.

## The economy (on the clock)

This extends the economy clock (`2026-09-29-economy-clock-design.md`); it doesn't replace it.

- **Piece price** = a base ladder by level × `runScale(company)`. Below your record, pieces cost 2.5% and are bought a storey at a time.
- **Money multiplier** by level: milestone steps plus a small per-piece step past level 18.
- **Blueprint cap by company:**

| Company | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8+ |
|---|---|---|---|---|---|---|---|---|
| Can build to | 18 | 30 | 43 | 55 | 68 | 80 | 93 | 100 |

- **Windfall caps** stay as shipped: a share of the next goal, which is now the next piece's price, or the spin-off at the cap.

**Targets. The simulator must hit these before any game code:**

- Company 1: GO PUBLIC 21-25 min and spin-off 24-28 min (today 22.7 and 26.1).
- No company longer than **2 hours**, and no single wait for a piece longer than **10 minutes**.
- **Level 100 in company 8**, at about **6-9 hours** of total play.
- Rebuilding to your record takes no more than about **a third** of each company's time.
- No single windfall pays more than a quarter of the next goal (already true).

The numbers (base ladder, multiplier step, rebuild discount, the cap table) come out of `sim/clock_sim.py`, extended to pieces. I'll show you the table before building, like last time.

## Every floor shows its money

- **On the building:** each department storey has a sign on its courtyard face, like "ENGINEERING · $4.2K/s", updated every 2 seconds. At night the lit floors show which departments are busy.
- **In the lift:** each stop shows its department and $/sec.
- **On the HUD:** the income breakdown (tap the $/sec line) lists departments instead of rooms. It uses the same numbers the server already computes per room (`IncomeRooms`).

## What changes in the code

| Today | Becomes |
|---|---|
| `HQ_LEVELS` (5 boxes), `buildShell`, `CampusArch.skinHQ`, `HQFloors`, `HQMeta` | **`WaferPlan.lua`** (pure, tested offline): the 100-piece plan, positions, departments allowed, milestones, caps. **`WaferBuild.lua`**: places, removes and dresses pieces, collision, the lift stops, signs. |
| Rooms on 6 lots, room levels, `BuildClient` picker, `CampusArch` lots / links / grow | Department segments. **`BuildClient`** becomes the "next piece" card: the department choice, price, what it adds, and BUILD. |
| `RoomEconomy` V3 seats / caps / slots / levels | Per-piece seats and effects, from `WaferPlan` |
| `Journey` HQ 2-5 beats, apartment gates, `TalentDrop` tier gates (`tier.hq`) | The same beats keyed to levels 5 / 9 / 13 / 18 |
| `Progression` (clock, offline ladder) | `nextGoal` = the next piece, or the spin-off at the cap; the blueprint cap; the rebuild discount |
| Save: `hq`, `wings` | Save: `lv` (level), `dep` (department per segment), `rec` (record level). Old saves migrate: old HQ 1-5 map to levels 1 / 5 / 9 / 13 / 18, and old room types fill the first segments. Cash is kept. A one-time card says "your HQ was rebuilt as The Wafers". |
| The HQ pad (recruit drop-off, upgrade pad) | The lobby door pad |
| DevHook bot, sim | Both play pieces |

Unchanged: staff avatars and seating (desks and chairs placed along each arc keep the `SVChair` seating), the talent row, the phone, the bag, ranks, homes, cars, the valley.

**Performance budget** (the numbers we already hold):
- Full server: under 1,000 draw calls and under 1M triangles.
- About 1,500 parts per plot. Today it's about 1,150.
- The Wafers shell is about 21K triangles at level 100.
- Interiors of other players' buildings more than about 200 studs away are hidden on your client, the same way distant trees are culled today.

## Build order (each phase gets its own plan and your OK)

1. **Numbers.** Extend the sim to pieces, blueprint caps and the rebuild discount. Show you minutes per company and per level. *No game code.*
2. **The look.** A round-wafer Blender kit (about 10 meshes: 4 segment shells, 4 glass bands, deck, lobby gate, crown parts). Render levels 5 / 18 / 43 / 100 and a plaza view for you to approve, then import.
3. **Company 1 in the game** (levels 1-18). Replace HQ 1-5 and the rooms end to end, with departments, seating, the lift, signs, the journey, homes and recruit gates, the save migration, and a bot run. This phase also makes the plot 80 studs deeper: move the Caltrain line and orchards, regenerate the changed valley tiles, re-run the chase simulator.
   - This phase is where your current game becomes the Wafers. It has to match today's 26 minutes.
4. **Levels 19-100.** The blueprint caps, the rebuild discount, decks and the crown, then a bot run over 3 companies.
5. **Polish.** Night lights, department interiors, a phone check of the build card.

## Risks

- **This is the biggest rewrite since the Rojo move.** It touches about 15 files. Phase 3 keeps company 1's measured pace as the test, so a regression shows up as minutes on the clock.
- **Curved floors:** walkability, the camera inside rings, desk rows along arcs. Collision is simple rotated boxes per segment, not mesh collision.
- **Late companies could feel like re-grinding.** The rebuild discount is the fix, and the sim sets how strong it is.
- **Six buildings per server.** The interior cull and the 40-staff cap are there for this. We'll measure it on a full test server.

## Not in this spec

- **Luxuries and the new cars.** That's phase 3 of your list, and their prices are already in the economy spec.
- **Anything outside the HQ** ("other creations later").
- **Monetisation.**

## Phase 1 results (30 Sep): the numbers, tuned

- **Where they live:**
  - The simulator `sim/wafer_sim.py` (built on `clock_sim.py`, calibrated to the in-game bot) and the rules `sim/wafer_plan.py`.
  - The fit `sim/wafer_fit.py` writes `sim/wafer_params.json`, and the full table is in `sim/WAFERS-NUMBERS.md`.
  - The game module `game/src/ServerScriptService/WaferPlan.lua` has generated tables. `tests/offline/wafer.spec.luau` checks every number and rule against the simulator.
- **Tuned constants:**

  | Constant | Value | What it sets |
  |---|---|---|
  | p0 | 60 | the base price of level 2 |
  | r1 | 1.85 | the price step per level, levels 2-18 |
  | ms | 2.0 | the price multiplier on milestone pieces |
  | r2 | 1.035 | the price step per level past 18 |
  | g | 0.01 | money +1% for every floor past 18 |
  | deck | 1.25 | money ×1.25 at each later milestone |
  | rebuild | 0.025 | the price share of a rebuilt piece |

| Company | Can build to | Goes public | Spin-off | Rebuild | New floors | Longest new wait | Total | $/s at the top |
|---|---|---|---|---|---|---|---|---|
| 1 | 18 | 23.2 min | 25.8 | 0 | 23.2 | 6.7 (L18) | 0.43 h | 20K |
| 2 | 30 | 21.2 | 23.7 | 3.4 | 17.7 | 2.6 | 0.82 h | 39K |
| 3 | 43 | 29.9 | 31.1 | 5.2 | 24.6 | 2.9 | 1.34 h | 119K |
| 4 | 55 | 33.2 | 34.2 | 7.4 | 25.8 | 2.9 | 1.91 h | 200K |
| 5 | 68 | 46.0 | 46.8 | 9.6 | 36.5 | 4.2 | 2.69 h | 495K |
| 6 | 80 | 52.0 | 53.0 | 12.8 | 39.2 | 5.2 | 3.58 h | 712K |
| 7 | 93 | 83.6 | 84.3 | 17.9 | 65.6 | 8.5 | 4.98 h | 1.19M |
| 8 | 100 | 70.9 | 71.3 | 23.7 | 47.0 | 9.8 (L100) | 6.17 h | 1.89M |

Every target is met:
- company 1 at 23 / 26 min;
- no company over 85 min;
- no new-piece wait over 10 min;
- level 100 at 6.2 h;
- rebuilding at most a third of any company;
- windfalls capped at 25%.

**Three changes phase 1 forced, beyond the spec above:**
1. **Storey rebuilds.** At one piece per 20-second tap, rebuilding 92 pieces is at least 30 minutes of tapping whatever the price. One tap now rebuilds a whole storey.
2. **Every floor adds money (+1%).** The first fit set that to zero to hold income down. Floors that add nothing are the thing you asked to fix, so it's now at least 1%.
3. **Income stays within 0.5-10× of today's curve.** Company 8 tops out at $1.9M/s against $282K today. The luxuries phase prices the new cars on this curve: at $1.9M/s the $90M hypercar is 47 seconds, which is why the ladder goes up to $5B.

## Phase 3 results (30 Sep): in the game, published

**Where it lives:** `Wafers.lua` (the building), `WaferPlan.lua` (the numbers), `WaferClient.client.lua` (the BUILD tile and card), and patches to SiliconCore, SaveLoad, HQFloors, Journey, Phone, RoomEconomy and DevHook. The mesh kit is `blender/wafers.py`, which produced 40 meshes and `HQMeta/Wafers.lua`. Commits d891d29 and a1cc873 on branch `wafers`.

**Measured live (fresh save, pace-20 bot, `sim/BOT-v46-wafers-run.txt`):**

| | Live | Sim |
|---|---|---|
| Level 5 (stage 2) | 2.1 min | 2.1 |
| Level 9 (stage 3) | 9.8 | 10.0 |
| Level 13 (stage 4) | 13.8 | 13.5 |
| Level 18 + GO PUBLIC | 23.9 | 23.2 |
| Spin-off | **26.3** | 25.8 |
| Company 2, first tap | rebuilt levels 2-9 for $911 | |

- **What else was checked:**
  - Every lift bridge ends at its storey's door, at walking height, on all 14 storeys.
  - A character walks from the bridge into every storey tested, and from the garage through the lobby to the plaza.
  - A level-100 view costs 325 draw calls and 248K triangles.
  - Idle network is 0.4-0.6 KB/s. There were 0 errors.
  - The save round trip is exact, and an old HQ 5 save migrates to level 18.

**Changes this phase forced:**
1. **The guide kept everyone saving for a home.** "Save for a Studio" blocked recruiting for minutes: level 13 at 17.1 min, with 5 staff. Now, while a home is out of reach, the guide shows an affordable recruit (the sim's rule), and the BIG GOAL card still names the home.
2. **The Boardroom had no effect in the phone.** Each boardroom now starts an investor one interest keener, up to 2.
3. **The old campus grounds stood inside the ring.** Trees, benches and lamps in the footprint (and under the lobby canopy) are cleared, along with the spur paths to the old lots.
4. **The kit review found 5 placement bugs** (bridges, crown, deck heights, dead-end roof bridge, signs behind glass). All are fixed and measured.

**The plot extension is deferred, with a reason.** The building at level 100 fits today's 240 × 220 plot (its widest wafer is about 145 studs). The extra depth is only needed for the luxury items (launch pad, helipad), so it moves to the luxuries phase. It needs a terrain tile re-import, and doing it once then is cheaper than now.

**Not done yet:**
- A full company-2 timing run (the rebuild tap is verified).
- A phone check of the BUILD card.
- Night lights on the Wafers.
- Department interiors beyond one desk or table set per segment.
