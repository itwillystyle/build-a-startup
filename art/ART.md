# ART.md: the look of Build a Startup!

PLAN v6, phase V1. 27 Sep 2026. Every visual change from here is judged by one question: **does the game look more like `styleframe.png` than it did yesterday?**

![target](styleframe.png)

The target image is rendered by `blender/styleframe.py` in 35 s on the RTX 5080. It uses the same trees and rocket as the game (the in-game FBX files). The comparison is `today_vs_target.png`; the palette sheet is `palette.png`.

## The style in one line

**Golden Hour Campus: a sunlit architect's model of Silicon Valley.** Soft-edged, warm, readable on a phone, and nothing a 2019 Roblox baseplate could produce.

Why this and not "bright cartoon": the fantasy is *building a company campus*. An architect's model is the image of a campus being built: clean forms, warm timber, tidy lawns, and the whole valley laid out around it. It's also cheap for phones. Simple bevelled forms plus baked shading beat detailed textures on every budget we measure.

## References: what we take from each

| Reference | What we take | What we don't |
|---|---|---|
| **Two Point Campus / Two Point Hospital** (management sims) | Everything slightly rounded and toy-like; props that tell jokes; warm, readable interiors | Their cartoon exaggeration of people |
| **Townscaper** | Shading in every crease; a restrained palette; softness | Pastel everything |
| **Run a Restaurant!** (Roblox, 98.7% liked) | UI grammar: light cards, full-colour icons, red badges, one arrow at the thing that matters | Their flat food art |
| **Apple Park, the Googleplex** | Glass, timber, stacked slabs, oak landscaping, bikes in primary colours; the ring as the HQ 5 silhouette | Photorealism |
| **The Santa Clara Valley at golden hour** | Gold hills with oak woodland in the folds, palms on the roads, the Dish on the ridge, Caltrain, long warm light | Fog, grey |

## Palette

![palette](palette.png)

| Name | RGB | Role | Share of frame |
|---|---|---|---|
| Paper White | 243, 239, 230 | Buildings, UI cards | ~40% |
| Warm Concrete | 207, 198, 182 | Plinths, paths, plazas | ~12% |
| Oak | 192, 138, 85 | Fins, soffits, benches, decks | ~6% |
| Tinted Glass | 118, 158, 176 | Glazing | ~10% |
| Campus Lawn | 118, 160, 92 | Lawns, near foliage | ~15% |
| California Gold | 224, 182, 90 | The hills | ~10% |
| Valley Blue | 62, 110, 158 | Shade tint, info, solar panels | ~3% |
| Ink | 30, 37, 48 | Text, mullions, asphalt | ~3% |
| **Company Accent** | 240, 110, 80 (example; the player's pick) | Their sign band, umbrellas, bikes | <1% |
| **Brand Gold** | 255, 194, 61 | The rocket, rare talent, rewards | <1% |

**The saturation budget:** the world is mid-saturation. Only the company accent, brand gold, UI actions and rare-talent effects are fully saturated. That's what makes *your* company and *your* rewards jump off the screen.

## Light

- **The reference moment is golden hour.** The 22-minute day keeps turning; the skybox, grade and palette are tuned so golden hour is the best-looking time.
- Warm key, cool shadow: sun ≈ (255, 174, 102), outdoor ambient cool ≈ (120, 132, 160), low ambient.
- ColorCorrection: slight warm tint, saturation +0.05 to +0.1, contrast +0.05. Bloom only catches real lights and the sun.
- Distance goes blue-lavender (Atmosphere haze), so the hills recede instead of flattening into one colour.
- Night: warm interiors (lit glass), cool exteriors, lamp pools. Already in SkyClient.

## Shape language: the rules that remove "2019"

1. **No sharp 90° edge on anything bigger than 2 studs.** Bevel = 2-4% of the smallest dimension, minimum 0.12 studs.
2. **Big corners are radiused.** Floor slabs have a corner radius of 3-6 studs. One shape carries the whole architecture: the rounded slab (`slab()` in styleframe.py).
3. **Architecture is horizontal:** stacked slabs, cantilevers, overhanging roofs, with vertical timber fins every 3.6 studs for rhythm.
4. **Every HQ level has its own silhouette:** garage → glass pavilion → stacked slabs (the styleframe) → the campus block → **the ring** (HQ 5). You can tell someone's level from across the map.
5. **Trees are lumpy clusters, never balls on sticks,** with uneven spacing and height. An even row of identical trees reads as a fence of lollipops (found in this phase; the eucalyptus crown was rebuilt because of it).
6. **People are real Roblox avatars** (phase V2). Never hand-built blocks.
7. **Hills roll.** Low-octave shapes, oak woodland in the folds. Colour changes **blend**; a hard per-point switch draws staircase edges that read as Minecraft (also found in this phase).

## Surface rules

- **Colour lives in vertex colour or in one shared texture atlas** (phase V4). No Roblox built-in textured materials on architecture: Brick, Wood, DiamondPlate and Cobblestone on a building read instantly as 2019. Allowed built-ins: SmoothPlastic and meshes for architecture, Glass for glazing, Neon only for lights/screens/effects, and terrain materials on the ground. Concrete with SV_CampusPavers stays on paths; it won its A/B.
- **Every mesh gets baked ambient occlusion** before export: Cycles bakes AO into the colour attribute (`svkit.bake_ao`, to write in V3). It's the single biggest "crafted by hand" cue, and it fakes the global illumination Roblox doesn't have.
- **Glass is tinted, never clear:** Tinted Glass colour, Transparency 0.35-0.45, a little Reflectance, always framed by mullions or fins, and **lit from inside** so it reads alive.
- **No pure white or pure black anywhere.** Paper White and Ink are the extremes.

## Scale (studs)

| Thing | Size |
|---|---|
| Character | 5 tall |
| Storey | 12 |
| Door | 8 tall, 7 wide |
| Desk | 2.6 tall |
| Oak | 11-16 tall |
| Palm | 20-26 |
| Eucalyptus | 22-34 |
| Redwood | 24-32 |

## Composition and world

- **From the default camera, every campus shows four things:** sky, a landmark, the player's HQ silhouette, and a path leading to the door.
- **Layered depth,** front to back:
  1. road and palms
  2. campus
  3. oak lawn
  4. gold hills with oaks
  5. the far ridge with redwoods, in haze
- **Landmarks appear once each,** placed where the default camera catches them: the Dish, Lick, Hangar One, Caltrain.
- **Motion everywhere, all of it quiet:** people, cars, the train, birds, the rocket.
- **Signs sit on surfaces** (the entrance band, the roof edge). Never floating text over a building.

## UI

- **Surfaces:** light paper cards (Paper White background, Ink text), 12-16 px corner radius, a 2 px stroke of Ink at 10%, and a soft drop shadow. Dark panels only for full-screen menus.
- **Icons are Cycles renders of the game's own models,** all under the same light rig:
  - warm key light from the upper left
  - cool rim light
  - soft contact shadow
  - 256 px, transparent

  No flat clip-art, no emoji. Style consistency comes from the rig, not from discipline.
- **Colours of meaning:**

  | Colour | Means |
  |---|---|
  | Green | Money, go |
  | Gold | Rare, brand |
  | Accent | Your company |
  | Blue | Info |
  | Red | Danger, badges |

- **Type:** Fredoka One for numbers and headings, Montserrat/Gotham for body text. The number is always the biggest thing on the card.
- **Motion:**
  - springs in, with overshoot of 8% or less, over 180-260 ms
  - nothing linear
  - rewards fly to where they're stored
- **Density:** one next action at a time. The centre of the screen belongs to the world (PRODUCT.md).

## Never (the 2019 list)

- Plain Parts as architecture: flat-coloured boxes with sharp edges
- Built-in Brick, Wood, DiamondPlate or Cobblestone on buildings
- Neon on anything that isn't a light, a screen or an effect (the yellow Neon roof sign today)
- Perfect rows of identical trees; spheres on sticks
- Hand-built block people
- Floating text labels over buildings
- Default particle sparkles
- Pure white, pure black
- UI whose whole look is flat rectangle + text + gradient
- Hard colour thresholds on terrain or meshes (staircases)
- Toy-coloured cars in random primaries

## Budgets

| Budget | Limit |
|---|---|
| Any gameplay view | ≤ 400 draw calls, ≤ 500k triangles (phones break near 1,000 / 1M). **Measured today: 156 / 188k worst case** |
| Tree | 700-1,700 triangles |
| Prop | 200-1,500 triangles |
| Building shell | 2k-6k triangles |
| Landmark | ≤ 5k triangles |

- **Textures:**
  - one 2048 atlas for all architecture
  - effect flipbooks at 1024
  - UI icons at 256
- **Uploads:** one batch per phase. Every mesh and texture is an upload plus a moderation queue on Luke's account.

## Pipeline (how the rules are enforced)

- All 3D goes through `blender/svkit.py`: vertex colour, one joined mesh, FBX with -Z forward and Y up.
- **After every import**, two fixes; both handled in code and noted in CLAUDE.md:
  - the importer's 90° pivot has to be reset
  - the importer's 180° turn about Y has to be undone
- Re-render the target any time: `blender -b --python styleframe.py -- 160 1920 1080`.
- A new asset is accepted only if it holds up **next to the styleframe**, on screen, in the game. That's the same rule as the materials A/B, where 4 of 5 generated textures lost.

## The gap: today vs target

Read off `today_vs_target.png`, with the phase that closes each:

| # | Today | Target | Closed by |
|---|---|---|---|
| 1 | HQ is a tall white box with black bands and a yellow Neon sign on top | Stacked bevelled slabs, timber fins, lit interiors, the name on an accent band at the entrance | **V3 + V4** |
| 2 | Hand-built block staff | Real Roblox avatars | **V2** |
| 3 | Lawn is saturated green with a dark noise texture | Campus Lawn, even and warm, faint mowing stripes | **quick win** (terrain colour) |
| 4 | Hills cut hard from dark forest green to gold; one hill shows a cliff-like cut; the golden wheat field is spiky noise | Rolling gold with oak woodland blended into the folds | **quick win** (ValleyGen colour blend) + V6 |
| 5 | Kenney toy cars in candy colours | EVs in the palette | **V5** |
| 6 | Flat midday light, cloudy stock skybox | Warm low key, cool shadows, a golden-hour sky | **V6** |
| 7 | Grey downtown towers on the right horizon | Hazed out, or restyled in the palette | **V5 / V6** |
| 8 | Default-looking UI over all of it | Paper cards, rendered icons, spring motion | **V8** |

**Quick wins (about an hour, no uploads):** the lawn and hill colours, softer terrain blends, the ColorCorrection grade, and swapping the Neon roof sign for a surface sign. They close items 3, 4 and part of 6 before any new asset exists.
