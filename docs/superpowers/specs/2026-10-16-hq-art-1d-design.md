# HQ tower part 1d: the art — design (16 Oct 2026)

Project #1 (the tower), part 1d. Parent spec: `2026-10-14-hq-tower-design.md` (§3 finishes, §6 night, §8
verification). 1a (shape), 1b (lift) and 1c (garage → lobby) are done on branch `hq-tower` (draft PR #56);
1a-1d ship together.

Process (CONSTRAINTS rule 17): references → mocks → Luke's pick → this spec → plan → build → look review.
- References: `silicon-startup/ui/2026-10-16-art-1d/REPORT.md` (+ `research-a.md`, `research-b.md`).
- Mocks: `ui/2026-10-16-art-1d/mocks/01..17` (script `art/blender/art1d_mocks.py`, built from TowerPlan's
  real numbers). These are the target the look review compares against.

## 1. Luke's picks (16 Oct, "go" on my recommendations)

| Question | Pick |
|---|---|
| Default finish (built and checked first) | **Glass** (Timber and Neon ship too) |
| Crown ring with the logo plate on its front | Yes |
| Planters on the lobby roof | Yes |
| A tidy box on the shaft's top (no open hole) | Yes |
| Yellow safety rail + a small crane on an unfinished floor | Yes |
| Terrace depth | Stays 6 studs (no shape change) |

## 2. What changes, part by part

Everything is built from **Parts** (no new meshes, no uploads): the same few part sizes repeat on every
floor, so Roblox instances them. Mesh polish can come later; it is not in 1d.

### 2.1 Facade, per room (every office room on a glass side)
Today each room draws its own glass walls (`wallSide`) and a 2-stud department-coloured strip
(`DeptBand`). 1d adds, on every glass side of a room:
- **Fins**: vertical, about every 5 studs (Timber: every 3.6, wider and deeper), skipping the corner.
- **The floor band**: the finish's band colour, 1.5 tall at the slab, with a **lip** 1.2 studs out.
- **The light line**: a 0.3-tall strip tucked under the lip (§2.7 lights it at night).
- **Timber only**: a planter with hanging green on the lip, every ~7 studs on the long faces.
- **The department colour leaves the outside.** `DeptBand` goes; the department shows on its sign and
  inside, as v7 already wanted ("a real curtain wall is one glass colour"). The facade glass loses
  `facadeTint` and takes the finish's glass colour. *Flagged to Luke: departments are no longer
  colour-coded from the plaza.*

### 2.2 Rounded corners (the wafer motif)
Corner rooms (segs 2, 4, 6, 8; and the lobby's) get a **faceted round corner**: the two glass walls stop
short of the corner and **three angled panels** close it (radius 6 on office floors, 12 on the lobby). The
band, lip and light line follow the same three facets. Low-poly, parts only. A pure function in TowerPlan
gives the cut so furniture is checked against it (no chair through the corner glass).

### 2.3 Lobby (storey 0)
Keeps 1a's podium, wood columns, canopy and roof band, and adds:
- **The entrance**: thick door frames (finish band colour) around the 14-wide entrance; a lit strip under
  the canopy's soffit; a **sign board over the canopy with the company's name** (the same name as the plot
  sign; falls back to `YOUR STARTUP`).
- **Planters on the podium roof**: along its front and side edges, where the tower doesn't cover it.
- **The wall art** (1c): the photo and TV sit flush on the wall (fixes 1c minor M2: 0.2 off the wall).

### 2.4 Terraces (garden decks 2, 6, 10)
Same shape (6 deep). Research (Bosco Verticale, Oasia): it reads as a garden when the plants are on the
edge and rise above the rail. So:
- **A planter edge**: a continuous low planter along the outer edge, the glass rail standing on it, a
  wood handrail (today: a bare glass rail with planters 1.6 in from it).
- **Four trees taller than the rail** (today: two small balls), two benches by the glass, two lamps.
- The fins, band and corners of the floor above carry on (they are part of every room, §2.1).

### 2.5 The crown (roof, storey 14)
- **The crown ring** (the `halo` piece's new look): a 12-tall glass screen round the roof's edge with
  fins every 4 studs, a band on top with a light line, and on its **front a dark plate with the
  company's name**, lit. The mocks showed why: from the plaza the roof edge hides the lantern, so without a
  ring the top of a finished tower reads as nothing.
- The lantern (over the shaft) and the mast stay; the mast gets a small red light on top.
- Roof planters stay; the pavilions get the finish's band on their roof.

### 2.6 The core: lift doors, the shaft's top, an unfinished floor
- **Door frames**: a thick frame (finish band colour) round the lift doors on every landing.
- **The lift's talking sign** hangs over the doors, beside the floor display (1b minor: it was a plate on
  the side wall seen at an angle).
- **The shaft cap**: wherever the shaft ends (the top built storey, until the roof's lantern takes over),
  a tidy box in the band colour with a small door, closing the open hole over the shaft (1c ruling: "the
  open roof hole at the sting").
- **An unfinished floor** (the top storey with some of its 8 rooms built): a **small yellow crane** on the
  shaft cap, and a **yellow-and-white safety rail** along the open roof edges where the next rooms go. Both
  go away when the floor is complete. Which edges are open is a pure TowerPlan function (tested).

### 2.7 Night (replaces today's "glass turns Neon" rule)
Today (`SkyClient`, 5 Oct): after dark every facade pane farther than 46 studs turns **Neon orange**, so
whole walls glow: the "cheap night lights" Luke named. 1d:
- **Facade glass never turns Neon.** At night it just goes darker.
- **Each room has a ceiling light strip** behind the glass (a thin part at the top of the room). At night,
  seen from beyond 46 studs (the same distance gate), it turns on: warm, and **about 1 room in 5 stays
  dark** (fixed per room, so it doesn't flicker). Close up you see the room, not a glowing slab.
- **The light lines** under each band, under the canopy and on the crown ring turn on at night (Glass and
  Timber: warm white; **Neon: one bright colour, cyan**, and softly lit by day too).
- The crown plate, terrace lamps and mast light glow. Street lamps are unchanged.
- One tag drives it: `SVNightLight` parts switch on and off; `SkyClient` stops collecting facade glass.

### 2.8 The three finishes (one table, one module)
A pure `TowerFinish` module maps finish → colours and materials; every builder reads it.

| | Glass (default) | Timber | Neon |
|---|---|---|---|
| Glass | light blue | pale teal | dark smoky |
| Fins | silver-grey | dark wood, wider, closer | charcoal |
| Bands | off-white | cream | near-black |
| Lobby columns | wood | wood | charcoal |
| Light lines | warm white, night only | warm white, night only | cyan, always (brighter at night) |
| Extra | — | planters with hanging green on the lips | — |

`hqPath` mapping is unchanged: `W_` Glass, `T_` Timber, `D_` Neon. Colours stay on `Palette.ANCHORS` (no
pure white or black, CONSTRAINTS rule 12); Neon material only on the light lines, strips, lamps and the
crown plate (rule 12).

### 2.9 The finish picker
Its three cards show the tower in each finish (mock 17), rendered once from the mocks and uploaded as
images, or drawn from the new tower in a ViewportFrame, whichever the plan finds cheaper. *If both are
blocked, the cards keep their current art and this is noted, not faked.*

## 3. Not in 1d
- Interiors and in-room lighting (projects #2 and #3).
- Deeper terraces (a shape change; Luke kept 6).
- Meshes from Blender for the facade (parts only now; a later polish pass can swap them in).
- The two-player test (Luke: later).

## 4. Pass rules (written before building)
1. **Offline** (Lune): `TowerFinish` covers all three finishes with every key; colours are on the palette;
   the corner cut keeps every furniture box inside the room (`T.inner` against the cut); the open-edge
   function gives no rail on a complete floor and a rail on every edge next to an unbuilt room; suite green.
2. **Doctor, at HQ 5/9/13/18/43/100**: stand on every storey, the lift lands on every floor, no scripts
   twice, no errors (as 1a-1c). Nothing collides that didn't before (fins, lips, planters, rails: no
   collision where a player walks except the terrace planter edge and rails).
3. **Performance**: the full tower (level 100), seen from the plaza, **≤ 500k triangles and ≤ 400 draw
   calls** (parent spec §8.3), measured with the same method as the rack; plus the change against today's
   measured number, both reported.
4. **Night**: at night, from the plaza, no facade glass is Neon; about 1 in 5 room strips is dark; from
   inside a room (closer than 46) its strip is off.
5. **Look**: every mock 01-17 is compared with a live screenshot by a fresh reviewer (rule 17), by day and
   at night, Glass first, then Timber and Neon.
6. **Gate**: `bas checkup pr` before the push.

## 5. Risks
- **Part count.** ~10 more parts per room × ~80 rooms. If §4.3 fails, the fins go first (every other
  fin), then the corner facets on far floors.
- **Saved towers of other finishes.** Timber/Neon players see their finish change look on join (same
  shape). That is the point of 1d, but it is a visible change for existing players.
- **The department colour leaving the facade** (§2.1) is a judgement call; easy to revert (one band).
