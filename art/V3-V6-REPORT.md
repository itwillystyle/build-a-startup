# V3 (the HQ buildings) + V6 (sky and light): 27 Sep 2026

Plus two small fixes found along the way. Everything is installed in Studio and matches disk (7/7 scripts compared). The HQ buildings are waiting on one Bulk Import, which is yours.

## V3: the HQ as real architecture

![sheet](hq_v3_sheet.png)

**The five buildings** (`blender/hq.py`), one per HQ level:

| Level | Name | Look | Triangles |
|---|---|---|---|
| 1 | Garage | Mid-century flat roof, deep eaves, exposed beam ends, oak corner boards, a lamp by the door, and a sectional double door with a window row. The name plate is painted over the door. | 1,528 + door 776 |
| 2 | Startup Office | One tall glass pavilion under a big floating roof, oak fins, and an entrance canopy on two slim columns | 3,224 |
| 3 | Tech HQ | Two stacked slabs (the styleframe): a mullioned glass lobby, an oak-finned office floor, a parapet roof with solar | 5,644 |
| 4 | Glass Tower | All glass between rounded floor bands, with a floating halo crown | 6,008 |
| 5 | Campus HQ | A full-height oak screen over every floor, a roof garden and pergola, and the crown | 8,508 |

**How it plugs in:** `CampusArch.skinHQ`, called at the end of `buildShell`.
- The meshes are modelled around the exact footprint the game already uses.
- The old part walls, roof, glass and header stay as **invisible collision**, so walking, doors, pads, furniture and seats behave exactly as before.
- Decorative parts the mesh now draws are removed: mullions, fins, bands, canopies and rooftop units.
- The name plate moves onto the building: over the garage door at level 1, and on a sign frame clear of the parapet from level 2 up.
- **The garage doors:** the door parts still slide up 11 studs when the door opens, which would push a visible door through a real roof. So a door leaf mesh rides each part, welded, and fades out as it rolls up.
- **If a mesh isn't imported, nothing changes.** That's the same rule as the trees.

**Tested before your import:**
- **How:** plain block stand-ins of the exact modelled sizes, on a fresh save.
- **Level 1** on all six plots:
  - walls, roof and header invisible but still solid
  - plate on the header
  - door leaves welded at the modelled offset
  - rolling a door up the way the game does: the leaf rides with it and has fully faded by the time it's up
- **Levels 2 and 3:**
  - shell and glass placed
  - all decoration parts removed (0 left)
  - the front glass invisible and still solid
  - plate at the new heights (22.8 and 32.2)
- **Level 4 without a stand-in** kept the old look, so the fallback works.
- 0 errors. Your save was snapshotted (`11510645938_pre_v36`) and restored.

**Not testable until the import:** whether the importer honours the modelled axes. The code compares each imported mesh's size with the modelled size and writes a warning to the Output if they differ by more than 1.5 studs. If a building ever faces backwards, one constant flips it (`HQ_MESH_FLIP`).

## V6: sky and light

![sky](sky_v6_pano.png)

- **Our own skybox** (`blender/sky.py` + `sky_post.py`):
  - a clear California blue with a warm haze at the horizon
  - flat-bottomed cartoon cumulus riding just above the ridge line (the hills rise about 18° from the campus, so lower clouds would be hidden)
  - no painted sun, because the game's sun moves through a 22-minute day
- **Face slots were measured, not assumed.** I put six asymmetric icons on the six faces and looked each way in Studio.
  - Roblox's **Rt face is at -X and Lf is at +X**, the reverse of what the names suggest.
  - The Up face is mirrored.
  - Guessing would have produced seams.
- **Six image uploads** on your account: Ft 75537082085995, Bk 121291280517397, Lf 72836466733855, Rt 138882095629253, Up 102168875629160, Dn 75343774974248. The old "Sunny Sky 1" IDs are kept in a comment in SiliconCore for rollback.
- **Depth of field (distance only):** your whole campus (within ~230 studs) stays sharp and the far valley softens slightly, the tilt-shift cue of an architect's model. Roblox drops it at low graphics settings, so weak phones don't pay for it.
- **Roblox's moving clouds** were thinned (cover 0.5 → 0.36). They were covering the painted sky but are kept because they're its only motion.
- Checked at 13:00 and at golden hour (17:18) in Play.

## Two fixes found along the way

1. **The rare-hire reveal card was being covered.**
   - The reveal now waits until the WHILE YOU WERE AWAY card is collected.
   - Phone texts, incoming calls and the call pill slide down below the reveal card while it shows.
2. **Rare staff labels stacked into an unreadable smear.**
   - Seen live: "Rosa · GENIUS" printed over "Cole · GENIUS" in your garage waiting line.
   - Four times a second, labels that would overlap on screen now yield to the rarer or nearer person.
   - Only the text fades, and only locally, so it never fights the server hiding a tag during a speech bubble.

Also: at night, the game's glow script would have lit the invisible collision glass. It now skips hidden parts.

## Files

- **Changed:** CampusArch (1,384 lines), SiliconCore (3,677), ValleyGen (896), SkyClient (203), StaffAnimClient (299), TalentRevealClient (298), PhoneClient (1,250).
- **Backups:** `*_pre_v36.lua`.
- **New:** `blender/hq.py`, `blender/sky.py`, `blender/sky_post.py`, `blender/out/hq_meta.lua` (generated placement data, pasted into CampusArch).

## Your steps

1. **Bulk Import the 11 files in `blender/out/IMPORT_HQ/`** (HQ_1_Door, HQ_1-5 Shell, HQ_1-5 Glass). Tell me when they're in. I'll move them into SVMeshes, fix the import pivots, and check every level on screen.
2. **Ctrl+S, then Alt+P.** The sky, the depth of field and both fixes are live in Studio but not yet published.
3. **Phone check** (you said later).
4. **The 2-player test and ten strangers.** As of this morning the game's data has exactly one player's save, yours.

## Import check (27 Sep, 8:30am)

- **All 11 meshes came in at exactly their modelled sizes**, and the front canopy landed on +Z. The axes held, so no flip was needed.
- **They were left loose in Workspace, which is where Bulk Import drops them, and that's the state the 8:15 publish went out with.** In the live game they're 11 unanchored buildings floating above the map centre, and they'll have dropped onto the hub. They're now in `ReplicatedStorage.SVMeshes`: anchored, no collision, import pivot reset, collision fidelity set to Box. **A republish fixes the live game.**
- **Every level checked on screen**, on a fresh save from garage to campus HQ:
  - the garage doors fade as they roll up
  - the name plate is over the garage door, then on the roof frame
  - the lobby and lit floors show through the glass
  - the crown sits above the sign
  - at night the glass glows, and the hidden collision glass stays dark
- **Candidate signs** (STAR, SKILLED) are now covered by the label declutter too. Labels are measured from the camera's focus point, which is how Roblox measures a label's range. The overlap seen in one test shot came from my detached test camera; from a real player position only the nearest candidate's sign draws.
- Your save was snapshotted (`11510645938_pre_v36b`: HQ 4, $311,250) and restored.
