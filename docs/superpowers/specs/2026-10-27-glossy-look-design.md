# The glossy look: from grey box to the mock (design, 27 Oct 2026)

**Status: APPROVED by Luke, 27 Oct 2026** (including the §7b calls). Next: the phase 1 plan (writing-plans).

Process (CONSTRAINTS rule 17): references → mocks → Luke's pick → **this spec** → plan → build → look review.
The mock was picked on 22 Oct: `ui/art-pass/tower-office.png` (cars: `ui/art-pass/cars-v2-chatgpt.png`).
This spec **supersedes** two earlier calls:
- the 4 Oct cartoon pass (`FlatLook.lua`) and the parts of `game/art/ART.md` built on it ("simple bevelled forms
  plus baked shading beat detailed textures");
- the 22 Oct art-pass spec's reading of the mock as having "a MATTE floor (no reflections)". Luke, 27 Oct: the
  glossy floor reflections are the first thing that makes the mock feel alive.

## 1. Intent (Luke, 27 Oct, in chat)

The interiors and cars look "blocky", "dull", "a gray box remake", "the same material" everywhere, "not filled
with life". What makes the mock alive to him: **glossy reflections on the floor, warm lighting, an organisation
that looks like an actual modern office with everything placed where it would be in real life**, chairs you can
sit in with a normal sitting animation. "Overall it just looks more satisfying."

He judges it done when he can tell **it was not mushed together from blocks like Minecraft**, and it is **a
functional, aesthetic room that doesn't look like it was made in a day**.

## 2. Decisions Luke made (27 Oct)

| Decision | His answer |
|---|---|
| Scope | **The whole world**, glossy like the mock (not only interiors and cars) |
| Phones | **Phones get a toned-down version, PC gets full shine** |
| Sources | **Mix all four**: Roblox built-in materials, Studio's AI material/texture generator, the Creator Store (clean licence only), Blender models with baked PBR maps |
| First room | **The engineering office in the tower**, like the mock. The rest of the world follows only after he approves that room |
| Wince | "If it still looks blocky and dull like a gray box", or "you just mush trash together" |

## 3. The problem, measured (27 Oct, live in Studio as Wilz at HQ 18, L13 engineering room; save restored)

| What he sees | Cause (measured or read in code) |
|---|---|
| One material everywhere | Plot1 (garage + tower): 1,294 parts, **1,138 SmoothPlastic (88%)**, Concrete 69, Glass 52, Fabric 20, Neon 14. `FlatLook.lua` sets SmoothPlastic on every part except Glass/Neon/ForceField and parts with a MaterialVariant |
| No texture | **0 SurfaceAppearance** on the plot; **1 MaterialVariant in the whole game** (SV_CampusPavers); 0 Decals/Textures |
| No shine | **0 parts with Reflectance**; `Lighting.EnvironmentSpecularScale = 0.35` (SkyClient line 86), down from 1.0 |
| No warm light | **1 Light instance on the whole plot**. Ambient (84,92,116), OutdoorAmbient (120,132,160): cool. Warmth comes only from ColorCorrection tints |
| Pale, washed | Every imported pack mesh is multiplied by `Palette.PACK_WASH` (240,229,211), cream (Palette.lua 306, 353) |
| Block on the monitor | Each monitor (Kenney `computerScreen` MeshPart, cream) carries a child Part "Glow": opaque SmoothPlastic (236,184,72), 1.63 x 0.79 studs, no content (FurnitureKit ~568). Laptop and lobby TV use SurfaceGuis; monitors do not |
| Cars | Your car: 7 parts, 5 SmoothPlastic + 2 Concrete. City cars: 67 of 71 SmoothPlastic. 0 SurfaceAppearance |
| Sparse room | The C3 view (review-4.png) shows one desk, two chairs, a framed print in a 30+ stud room. The mock has desk + laptop + 2 monitors, office chair, server rack, wall TV, shelf with books and plants, framed art x4, couch with cushions, coffee table, rug, floor plants, ceiling beams with strip lights. (Judged from the pictures; props not counted) |
| Doubled screen effects | Lighting holds 2 Bloom, 2 ColorCorrection, 2 SunRays, 2 DepthOfField: SiliconCore (~4482) and SkyClient/GarageMoodClient each add their own |

Engine facts (checked 27 Oct, sources at the end):
- `Lighting.LightingStyle = Realistic` (read in Studio), Roblox's top mode. PBR maps and local lights show fully
  only in Realistic.
- **No custom shaders, no outside renderer.** Shader injectors (RoShade etc.) change one player's own client and
  break the rules. Unity/Unreal scenes cannot be imported, only single meshes (FBX/GLB/OBJ, ~20k triangles each).
- **SurfaceAppearance** (MeshPart only): colour, normal, roughness, metalness, emissive. Smooth surfaces reflect a
  live indoor environment map (Future/Realistic lighting); rough ones get a blurred reflection.
  `EnvironmentSpecularScale` scales it (1 = full).
- Note: SmoothPlastic itself is smooth, not matte. It reads dull here because it has no texture, specular is at
  0.35, and there are no lights for it to reflect. The floor material is therefore a choice to make by A/B
  screenshot (§5.2), not by assumption.

## 4. Goals, non-goals, anti-goals

**Goals**
1. The L13 engineering room, seen from the C3 camera (`DoctorProbes.roomCam`), reads as the mock: glossy floor
   with reflections, warm lit ceiling, real materials (oak, fabric, carpet, metal, glass), dressed like a real
   modern office, screens with content.
2. One style system that the rest of the world then uses (§5), so phase 2 is applying rules, not re-deciding.
3. PC full quality; phones a toned-down tier that keeps the game smooth.
4. Office chairs a player can sit in, with Roblox's normal sit pose.

**Non-goals (this spec's first phase)**
- The rest of the world, the garage, the lobby, other departments, exteriors, downtown, the cars. They follow the
  same rules in later plans, each after Luke approves the first room.
- New gameplay. Sitting is a pose, not a mechanic.
- Changing the tower's floor plan or room sizes (TowerPlan).

**Anti-goals (fail even if it "works")**
- **Grey box**: flat blocks in one dull colour, however many props.
- **Mush**: random assets piled in. Mismatched styles, wrong scale, floating or clipping, a stretched block standing
  in for an object. Fewer, better props beat a crowded room.
- Looks "made in a day": nothing placed with intent.
- Phones dropping frames because of this.

## 5. The design

### 5.1 The style rules (replace ART.md's material and light sections when this ships)

**Materials, by surface**

| Surface | Source | Look |
|---|---|---|
| Office floor | Built-in material or AI-generated MaterialVariant, picked by A/B screenshot | Polished light concrete with a visible soft reflection |
| Rug | AI-generated MaterialVariant (Fabric base) | Deep navy, coral border, low-pile texture |
| Feature wall | AI-generated MaterialVariant (Wood base) | Light oak panels with grain |
| Other walls, ceiling | Built-in | White plaster; navy ceiling with oak beams |
| Glass | Built-in Glass | As now |
| Hero props: desk, office chair, couch, coffee table, server rack, monitor, shelf | Blender meshes with baked PBR (SurfaceAppearance) | Rounded, clean, modern; oak tops, black/navy metal, fabric couch with coral cushions |
| Small decor: plants, books, frames, laptop | Creator Store if the licence is clean and it matches the style; else Blender | Same palette, same roundness |
| Screens | SurfaceGui (+ emissive) | Code, a rising chart, the player's app. No solid block |

**Palette**: navy, coral, oak, white, black metal, plant green (the mock's). Every prop uses it. No cream wash
(`PACK_WASH`) on anything in the room.

**Light**: warm strip lights in the ceiling beams (warm white, about 3000 K), screens and the TV as small emissive
sources, daylight through the glass. Cool fill stays low. One owner for each post effect (no doubles).

**Placement**: as in a real office. Desk against a wall or window with the chair tucked in, monitors on the desk
facing the chair, couch facing a coffee table on the rug, shelf at eye height, plants in corners and on the shelf.
Nothing floats, sinks, or clips. Every prop is at the real size relative to a Roblox avatar.

### 5.2 FlatLook retires

`FlatLook.sweep/watch` stops flattening. Every surface gets its material from the table above (or keeps the
material its builder set). The ground rule in FlatLook ("the ground keeps its grain") stays. What happens to the
contact-shadow discs (`contact`) is the builder's call: GlobalShadows is already back on (SkyClient).

### 5.3 PC and phone tiers

- **PC**: `EnvironmentSpecularScale` back toward 1.0, all room lights, all props.
- **Phone**: lower specular, only the lights of the room the player is in, small props hidden in far rooms
  (OfficeCullClient already hides far furniture).
- How a phone is detected and the exact numbers are the builder's, set by measurement (§6).

### 5.4 Chairs

The office chair is a real Seat a player can sit in, with the default Roblox sit animation. Staff already sit on
chairs tagged `SVChair` (FurnitureKit `tagSeat`, StaffRig); a player never takes a seat a staff member is in, and
a staff member never sits on a player.

### 5.5 Uploads

Texture images (SurfaceAppearance maps, decals) and meshes are Roblox assets, reviewed by Roblox before they show.
**Decided 27 Oct:** they upload through the Open Cloud Assets API as the alt Wilz (`devmeistah`, 1688749216), with
an asset-only key Luke made. The key lives in `silicon-startup/.roblox-upload-key` (outside git; never printed,
logged or committed). Verified 27 Oct by Roblox's key introspect: name `glossy-look-uploads`, scope `asset`
read+write only, enabled, expires 2026-12-26. Images, decals and meshes are Open Use by default, so Wilz uploads
load in `itwillystyel`'s game; if Asset Privacy is on for Wilz, each asset needs universe 10764670399 added on its
Permissions page. Every upload is checked for its moderation result before the build uses its id.

## 6. How it is judged

1. **Luke's eye (the gate):** a side-by-side of the mock and the room from the C3 camera, then he walks the room
   in Studio. His verdict decides. "Grey box" or "mush" = not done.
2. **Numbers that keep it honest** (doctor checks, added with the room):
   - the room's parts: no more than a set share in plain SmoothPlastic; every hero prop has a SurfaceAppearance;
   - lights in the room > 0 on PC; no "Glow" block on any monitor;
   - nothing floating or clipping (bounding-box checks against floor and walls);
   - `tools/look_stats.py` on the C3 shot vs the mock (brightness, contrast, colour strength; 22 Oct spec);
   - one of each post effect in Lighting;
   - budgets: the tower plaza stays under 500k triangles / 400 draws (the #81 budget); phone-tier frame time is
     measured on a phone-size Studio emulation and must not get worse than today's.
3. Rule 17's look review: references → the plan's own mock if needed → build → match-the-mock review.

## 7. What's left to the builder

- Which built-in vs generated material wins each surface (by A/B screenshot).
- Mesh topology, triangle counts, texture sizes, within the budgets.
- How the phone tier is detected and its exact numbers.
- Light counts, brightness, range, and shadows per light.
- Which Creator Store items pass the licence and style checks.
- The order of tasks inside phase 1.

## 7b. Calls Claude made after the builder check (Luke: check these)

1. **Scope of side effects.** Phase 1 lives on its own branch and is never published before Luke approves the
   room. Global changes the room needs (specular back up, FlatLook no longer flattening, one owner per post
   effect) are allowed on that branch, because the whole world is the target anyway. FlatLook gets a room-scoped
   opt-out first (a tag it skips) so the outside does not all change in one step; the review shows Luke the
   plaza and garage too, so he sees the side effects before he decides. Cost if wrong: the outside changes
   before he wanted; it is a branch, so nothing reaches players.
2. **"The engineering office" = the `eng` template** (`OfficeLayout.furniture/dressing("eng", ...)`), so every
   engineering room on every plot gets it, at every company size. Rooms that share its code (`labs` rugs and
   desks, `lobby` workstations) change with it and are checked in the review. Cost if wrong: one special case.
3. **Seats and gameplay stay as they are.** The eng room keeps its seat count and seat positions (`OL.seats`,
   guarded by `officelayout.spec`); the mock's props (couch, coffee table, rug, server rack, TV, shelf, plants,
   art) are fitted around them. The couch is decor, not a staff seat. Cost if wrong: a later layout pass.
4. **Player seats.** A player can sit only on a chair no staff member is assigned to; an assigned chair is not
   sittable by players. Staff seating and income never change because of a player. Cost if wrong: a rule tweak.

## 8. Open before the plan (Luke)

- ~~Who uploads~~ Settled 27 Oct (§5.5): Wilz asset-only key, verified. Hero props can be planned as meshes with
  baked maps. Still unverified until the first upload: whether Asset Privacy is on for Wilz, and Wilz's upload cap.
- Luke's approval of this document, including the §7b calls.
- (Later, not phase 1) the order of the rest of the world after the first room.

## Sources (checked 27 Oct)

- Roblox SurfaceAppearance: https://create.roblox.com/docs/art/modeling/surface-appearance.md
- Roblox lighting (LightingStyle): https://create.roblox.com/docs/environment/lighting
- Indoor reflections for Future lighting (21 Jul 2021): https://devforum.roblox.com/t/better-indoor-reflections-live-for-future-lighting/1365721
- RDC25 recap (shaders "still in research" in the comments): https://devforum.roblox.com/t/rdc25-what-we-announced/3920245
- Shader injectors against the rules: https://www.itechguides.com/how-to-install-shaders-in-roblox-what-still-works-and-how-to-get-reflections-safely/
- Mesh import formats/limits: https://www.katsbits.com/codex/?p=10511
