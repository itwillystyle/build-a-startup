# Quick wins + phase V2 (real avatar staff): 27 Sep 2026

Both done, installed, verified in Play. Screenshots are in `art/v2/` and `art/quickwins_before_after.png`.

## Quick wins (ART.md gap items 3, 4 and part of 6)

| Change | Where | Result on screen |
|---|---|---|
| Terrain palette moved onto the art guide: gold 200,168,96 · lawn 136,172,96 · oak woodland 78,100,60 | ValleyGen PALETTE | Hills read California gold; the lawn is lighter and less neon |
| Redwood forest only on the crest (from ~75 studs up, full by ~130), gold slopes with oak patches below | ValleyGen.classify | The dark forest no longer covers the ridge down to the valley floor |
| Forest edge broken with a second, finer noise band | ValleyGen.classify | The ridge line is a patchy transition, not a dark-green-to-gold cliff |
| Campus lawn parts match the terrain lawn | CampusArch LAWN / CAMPUS_LAWN | No colour seam between lawn beds and ground |
| Cooler, lower shadow fill (outdoor ambient 128,132,140 → 108,118,144) | SkyClient | Shadows are cool and darker instead of lifted grey |
| Warm tint on sunlit faces (ColorShift_Top, stronger at golden hour) | SkyClient | Warm key, cool shadow, per the art guide |
| Contrast +0.02 | SkyClient | Slightly more depth |
| Public company's roof plate: gold **painted**, no longer glowing Neon | SiliconCore refreshSign | The glowing yellow bar on the roof is gone |
| HQ 4+ roof beacon: 2x6x2 glowing Neon stick → slim white mast with one small aviation light at its tip | SiliconCore buildShell | Only real lights glow (ART.md rule) |

Not possible: switching off the terrain's grass blades (the "spiky wheat" near the rail). Roblox no longer exposes `Terrain.Decoration` to scripts.

## Phase V2: staff are real Roblox avatars

**What they are now:**
- **Body:** the default R15 body built from a HumanoidDescription, with one of 8 free Roblox-made hairs, each verified at price 0:
  - Chestnut Bun, Lavender Updo, Pal Hair, Brown Hair
  - Brown Charmer, Down to Earth, Shaggy, ROBLOX Girl
- **Clothes:** a shirt and trousers I drew once (`art/clothing/*.png`, **2 image uploads**: shirt `95943654717117`, trousers `88037629958570`). They're near-white and tinted per person, so:
  - the shirt is still the role colour (blue engineer, pink designer, and so on)
  - talent recolours the shirt
  - the headhunter wears a dark suit
- **Variety:** 5 skin tones, 5 trouser colours, and the 8 hairs, all picked from the person's seed, so a recruit keeps their look forever.

**How they drop into the existing game without breaking anything:**
- **Joints.** 2026 avatars use AnimationConstraints, which the pose, seat and carry code can't see. Each one is converted into a Motor6D with the same offsets (all identity rotations, measured), attached the way the old rig was. Every existing animation, seating pose and carry pose works unchanged.
- **Height.** From its joints, the avatar's root sits 3.19 above its soles. The game places people 2.61. The body is raised on the Root joint, so standing people land exactly on the floor: measured gap **0.00** on every candidate.
- **Sitting.** Seat height now comes from each rig's own hip and thigh (`ThighUnder` attribute), not the old rig's constant.
- **Speed.** Templates are built once per hair at server start (all **8/8 ready** within ~1 s of join) and cloned per hire. A hire never waits on Roblox's catalog. If the catalog can't be reached, the old block rig is still there as a fallback.

**Verified live, one check each:**

| Check | Result |
|---|---|
| Saved staff on load | 7/7 staff and candidates are avatars |
| Sitting and typing | Rosa at her desk, typing, facing her monitor (`v2_03`) |
| Candidates on the Talent Row | Standing, soles on the pavement (`v2_04`) |
| Carry | The recruit rides the scooter deck behind you, hands on your shoulders, soles 0.11 above the deck (`v2_06`) |
| Headhunter | Spawns as an avatar in the dark suit |
| Rare-hire reveal | Portrait shows the avatar (`v2_10`) |
| A new hire mid-game | Dana, recruiter, spawned and seated at the cafe table (`v2_11`) |
| Network | Unchanged: 0.43-0.45 KB/s idle |

### Two problems found and fixed while testing

1. **Instance bloat.** An avatar as Roblox builds it is **196 instances**, against about 40 for the old rig: scaling records, self-collision constraints and redundant joint attachments. That would have been ~35k instances replicated on join for a full server. Stripped to **67**.
2. **Triangle cost.** An avatar is ~3.3k triangles against ~400 for the old rig. Load test, 180 avatars on a full server, wide view: **724 draw calls / 1.51M triangles**, over the ~1M phone budget.
   - Staff beyond 210 studs are now hidden on each player's own machine (StaffAnimClient). Nothing is replicated, and candidates' tier rings and light pillars stay visible for wayfinding.
   - Same view after: **459 / 973k**. Street view **387 / 579k**.

**And one bug my own change introduced, caught the same session:** the reveal portrait is a copy of the rig, and the copy kept the staff tag. The animation script adopted it and the new cull hid it, so the card showed an empty disc (`v2_09`). Fixed at both ends: the copy drops the tag, and the animation script ignores anything outside the world.

### Measured cost worth knowing

**Clothing memory:** Roblox bakes each avatar's clothing into its own textures, about **0.45 MB per person**. Character textures went from 18 MB to 98 MB with 180 extra staff. That's the full-server worst case (six players with 30 staff each); a typical server is around a third of it. The distance cull hides bodies but doesn't free that memory. Watch this on the phone test.

## Found, not fixed (outside this phase)

- **The rare-hire reveal card can be covered** by the "While you were away" card (`v2_07`) or by an incoming phone text banner (`v2_08`). The one-menu-at-a-time rule doesn't cover these notification cards. It's a UI stacking fix for phase V8, or sooner if you want it.
- The dynamic heads Roblox now gives every default avatar ignore classic faces, so all staff share the default face. Face variety would need specific head assets. Hair, skin, clothing and role colour already make people distinguishable.

## Files

- **Changed:** ValleyGen, CampusArch, SkyClient, SiliconCore, StaffRig (803 lines), TalentDrop, StaffAnimClient, TalentRevealClient.
- **Disk == Studio:** 8/8 byte-compared.
- **Backups:** `*_pre_qw.lua` (quick wins), `StaffRig_pre_v2.lua`, `TalentDrop_pre_v2.lua`, `StaffAnimClient_pre_v2.lua`.

Your save was snapshotted before the live hire test (`11510645938_pre_v2avatars`) and restored after: HQ 5, $63.0M, 3 staff.

## Your steps

1. **Ctrl+S, then Alt+P.** Nothing since your 25 Sep save is saved, and that now includes the quick wins and the avatars.
2. **Phone check:** the avatars, frame rate in a busy campus, and the memory note above.
3. Still staged for your next Bulk Import: `blender/out/IMPORT_NEXT/Eucalypt_A.fbx`, the fuller eucalyptus crown from the styleframe work.
