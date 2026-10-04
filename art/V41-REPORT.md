# v4.1: the low-poly valley (style B), in the game

28 Sep 2026. You picked **B** from `art/v402/STYLE_COMPARISON.png`. This is B built for real, replacing the blurry painted hills, the terrain and the lollipop trees.

Screenshots: `art/v41/V41_SHOTS.png` (plus the single shots in `art/v41/`). They're ultra-wide because the Asset Manager and Import Queue panels squash Studio's viewport right now. The game itself is not ultra-wide.

## What changed

- **Hills:** 100 faceted mesh tiles (flat colour per facet, no texture, no blur), built in Blender from the same height data (`blender/lp_world.py`). No Roblox terrain at all.
- **Walking on hills:** invisible wedge collision built from the exact same triangles. I tested 3,000 random points and the difference between what you see and what you stand on was **0.00 studs**.
- **Trees:** 14 new low-poly models (`blender/lp_trees.py`): oaks, redwoods, eucalyptus, palms, orchard, bush, and grove clumps for the far hills. The same set is used everywhere: hills, campus, street and downtown.
  - 4,958 hill trees, all on the ground (0 floating, 0 sunk).
- **Sky:** a clean gradient with no painted clouds (`blender/lp_sky.py`), plus 26 real faceted clouds that drift slowly on the client.
- **Blur (depth of field): off.** Half of "the hills are blurry" was the blur itself.
- **Apartments and furniture** (v4.0.2, earlier tonight): couches and chairs face the right way, and every kitchen, bed and toilet backs onto a solid wall instead of glass.

## Fixed this round

1. **Spikes.** Before, 88 points on the hills stood 18 to 82 studs above everything around them (pale pyramids by downtown and the bay rim). A slope limit now stops any point rising more than 1.1 studs per stud above its neighbours. **0 points break that limit.** The 4 that still stand out are real hilltops 1,000+ studs away. 47 tiles were re-exported and re-imported.
2. **Thicker woodland** on the golden slopes: oak groves, 3,918 → 4,958 hill trees.
3. **A real join bug.** The world build pauses every few rows so the server never freezes. A player who arrived during a pause got **no plot, no money and no game**, because the join handler was only hooked up after the build. That would have hit the first player on every fresh live server. Players already in the server are now caught up. Verified: plot 1, leaderstats and the funnel all fire.

## Measured

| | draw calls | triangles |
|---|---|---|
| Aerial (style-comparison camera) | 270 | 320K |
| On the road, looking down the valley (worst case) | 336 | 449K |
| Your HQ 5 campus | 254 | 275K |
| Phone budget (Roblox docs) | < 1,000 | < 1M |

The old look (A) was 818K triangles on the aerial camera, and today's viewport shows more of the world than that one did.

- 0 game errors in the console.
- World build 1.5 s.
- All 14 changed scripts/modules match the files on disk.

## Honest notes

- **The bay is a strip of salt ponds by Hangar One**, not open water. That's how the source height data is shaped. A real open bay would mean lowering the west hills; that's a design choice, and yours to make.
- **Sun-facing slopes read pale cream** at midday, same as in the mock. If you want them richer, the one knob is the gold colour in `lp_world.py` (re-export + re-import of the tiles).
- Not checked on a phone.

## Yours

1. **Ctrl+S, then Alt+P.** Nothing since your 11:03 PM publish is saved: the v4.0.1 video fixes, the apartments, and all of this. It survived last night's forced restart only through AutoRecovery, so don't count on that twice.
2. Walk the hills yourself and tell me what still looks wrong.

Your save was restored after my test (snapshot `11510645938_pre_v41b`: HQ 5, $12.33M, apartment 3, 3 spin-offs). Studio is in Edit.
