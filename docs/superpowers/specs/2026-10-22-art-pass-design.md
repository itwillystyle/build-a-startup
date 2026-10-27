# Art pass: from washed out to the picked mocks (design, 22 Oct 2026)

Process (CONSTRAINTS rule 17): references → mocks → Luke's pick → **this spec** → plans → build → look review.
The tower's outside (facade, finishes, crown, night lights) already had its pass in 1d (#56,
`2026-10-16-hq-art-1d-design.md`). This spec does not redo it.

## 1. Luke's picks (22 Oct, in chat, run in ChatGPT from the prompts in `Downloads/ART-PASS-PROMPTS.txt`)

All in `silicon-startup/ui/art-pass/`:

| File | What it decides |
|---|---|
| `garage-outside.png` | **Early levels (the garage).** Cozy startup garage: warm wood, rugs, plants, string lights, a whiteboard, in daytime sun. Extra-chunky, bevelled, toy-like shapes. A full forecourt (path, bench, bike rack, planters, mailbox) and a fenced lot with a crane: "you are about to grow". |
| `tower-office.png` | **Later levels (tower offices).** Floor-to-ceiling glass, light wood, deep navy and coral, a MATTE floor (no reflections), more plants and a second monitor as signs of success. |
| `cars-v2-chatgpt.png` | **The 6 cars.** One silhouette and one main colour each, getting cooler left to right: hatch green, sedan blue, SUV red, coupe yellow, racer orange (open-wheel), hyper purple. |
| `clients-v1-chatgpt.png` | **The client, arrival to giving up.** Arrive and wave → wait (timer half) → impatient (timer red, foot tap, sweat drop) → leave sad, the lost pay floating up grey. |

Rejected: `cars-v1-gemini.png` (small wheels, two cars the same shape, the style ignored), and styles A, B and C
alone. The pair "garage → glass tower" was the pick because the look itself becomes the reward
(Tizzy Talk 6A, 47:52: "maybe if my giant started off small but got bigger").

## 2. The problem, measured (not a matter of taste)

The script that becomes `tools/look_stats.py` (plan 1, Task 1) on Luke's own screenshots against the picked mocks (centre 76% of the frame; HUD rows cut):

| | mean brightness | contrast (p90 - p10) | colour strength | near-white pixels |
|---|---|---|---|---|
| Live, first client inside (21 Oct) | 0.879 | 0.444 | 0.171 | **70%** |
| Live, garage outside (21 Oct) | 0.909 | 0.224 | 0.201 | **79%** |
| Live, inside from the laptop (21 Oct) | 0.739 | 0.676 | 0.329 | **46%** |
| Mock, garage outside | 0.566 | 0.603 | 0.470 | 1% |
| Mock, tower office | 0.497 | 0.702 | 0.446 | 4% |

"Too blocky and dull" is mostly **overexposure**: up to four-fifths of the screen is near white, so shape and colour
have nothing to show on. What causes it (read in code, 22 Oct):
- **Pale everything.** Walls PaperWhite / cladding (238,226,204), floors and forecourt pavers (214,208,196),
  every imported pack multiplied by a cream wash (240,229,211) (`Palette.PACK_WASH`).
- **FlatLook** (4 Oct cartoon pass) turns every part to SmoothPlastic, including the Wood, Fabric and Metal that
  GarageDress and Cars set, so there is no surface variety to break up the light.
- **Light**: high ambients, Bloom on, Atmosphere haze. The 22-minute day/night cycle (SkyClient) sets them at run
  time; Technology is not set in code (it comes from the place file).

## 3. Targets (the look review measures these; they are not taste)

On the 4 review cameras (§6), in Studio at 1280x720, daytime (ClockTime 13.5):

| Measure | Target | Why |
|---|---|---|
| near-white pixels | **≤ 10%** | the mocks sit at 1-4%; Roblox will not match a painted render |
| mean brightness | **0.45 to 0.68** | mocks 0.50-0.57 |
| contrast (p90 - p10) | **≥ 0.50** | mocks 0.60-0.70 |
| colour strength | **≥ 0.32** | mocks 0.45; live 0.17-0.33 |

And by eye, Luke's look review against the mock: can you find the laptop and the client in under a second?

## 4. What changes (one plan each, in this order)

1. **Light and the garage** (plan 1, `plans/2026-10-22-art-pass-1-light-and-garage.md`). What every new player
   sees in their first 10 minutes.
   - The daytime light: lower ambients, Bloom that only catches lights, less haze, a little more grade
     contrast and saturation.
   - FlatLook keeps real materials on a short tagged list (§5).
   - Two accent anchors (Teal, Coral).
   - The garage restyled to the mock.
   - The forecourt filled.
   - The growth lot.
2. **The client's timer and walk-off** (plan 2). It reworks the existing Patience bar into a round timer that
   goes red near the end, with a tick in the last 8 s and a sad walk-off. The lost pay floats up as **the game's
   own coin, grey** (never the Robux icon). Clients get their own looks and never wear the player's avatar.
   It is the missed-app effect Luke asked for (N8).
3. **The cars** (plan 3). Our own Blender meshes (svkit), replacing the Kenney packs, so each can be painted its
   one colour without the wash muddying it. The silhouettes follow the mock. The hypercar keeps the feel but
   NOT a real brand's shape. Head room is kept (the doctor's `cars` step).
4. **Tower office interiors** (plan 4). The B look inside office floors: matte floor, navy and coral accents,
   plants, and a second monitor from a set level. It goes per department through `Wafers.TINT`, and must work
   with all three finishes (Glass, Timber, Neon).

## 5. Decisions this reverses or extends (flagged)

- **FlatLook's "SmoothPlastic everywhere" (4 Oct).** The picks show wood floors, fabric rugs and soft shadows.
  Parts tagged `SVKeepMaterial` keep their authored material. Only Wood, WoodPlanks, Fabric and Metal, and only on
  floors, furniture, rugs and trim. **Lawns stay flat** (FlatLook's own rule, still right).
- **Palette anchors.** The mocks' accents (teal, coral) have no anchor today, so `Palette.map` would pull them
  onto ValleyBlue and Oak. Teal and Coral are added as accent families at full strength. Big areas keep their
  saturation ceilings.

## 6. Review cameras

| Id | Where | Matches |
|---|---|---|
| C1 | inside the garage, from beside the laptop, the client at the door (Luke's 21 Oct shot) | `garage-outside` interior, style A |
| C2 | outside, front of the garage plot, the forecourt in frame | `garage-outside.png` |
| C3 | inside a level-18 office floor, from the desk side | `tower-office.png` (plan 4) |
| C4 | the street by the plot, cars in frame | `cars-v2` (plan 3) |

## 7. AVOID (each one is a rejection in the look review)

- Photoreal textures. Grain on big lawns. Any texture that needs uploading (parts and materials only in plan 1).
- New translucent parts: they were measured as the largest fill-rate cost on phones (FlatLook header, v28).
- Neon that is not a light or a screen (`Palette.EMISSIVE_OK` is an allowlist).
- Purple gradients. Everything at full saturation. More than 3 accent colours in one view.
- The Robux icon anywhere. A client that looks like the player. Any new on-screen text.
- Losing the night: the 4-minute night must still read (laptop and client findable).
- Breaking the 1c garage → lobby moment or the 1d tower finishes.

## 8. Not in this spec
The thumbnail/icon (separate pick), the HQ camera's start distance (the garage mock's closer framing reads better,
but camera is gameplay; its own decision), sound.
