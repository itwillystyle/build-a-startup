# Overlap fix: 27 Sep 2026

Your report: "some assets are glitched in each other." I measured every overlap with a server sweep (bounding boxes for trees, props, staff and buildings), fixed each kind, then ran the same sweep again.

| What was inside what | Before | After | Fix |
|---|---|---|---|
| Valley trees growing through each other (redwood clusters had 3 trunks within 2.6 studs) | 124 deep pairs | **0** (877 trees) | One tree-spacing list shared by the valley, the campus and the street. Every tree asks for room before it is planted. Crowns may touch but can't overlap. A crowded campus spot gets a smaller tree or none. |
| Lobby trees poking through the HQ glass, mullions and walls | 18 hits | **0** | The lobby trees are now the tall, narrow eucalyptus, scaled to fit the room (max crown 4.2 studs). The oaks were as wide as they were tall. |
| Decor placed on a staff seat (avatar arms went through it) | possible | refused | The seat zone grew from 2.2 to 4.0 studs, which fits avatar arms. |
| Decor placed inside a room's own furniture (tables, desks, bookcases) | possible | refused | Room furniture is tagged `FKItem`. `FurnitureKit.blocked` checks it before a placement is allowed. |
| Staff vs furniture | | **none** | |
| Avatar name tag sitting inside the head | yes | fixed | Tag raised to 2.5 studs; speech bubble to 3.9. |

**Old saves:** decor that is already inside something is **refunded at its paid price** when the save loads. It is not deleted without the money coming back. The HQ 5 test save had 21 such items. Your real save is HQ 1, so few or none apply.

**Accepted:** one redwood and oak pair whose crown edges touch. Nothing passes through the other.

**Eucalyptus:** your IMPORT_NEXT file is filed in `ReplicatedStorage.SVMeshes` as `Eucalypt_A` (16.1 studs wide, the fuller crown). The pivot is reset, and it's used by the valley windbreak and the lobby trees.

## Files

- Changed: ValleyGen (893 lines), CampusArch (1247), CityKit (473), FurnitureKit (807), SiliconCore (3665), StaffRig (804).
- **Disk == Studio:** 6/6 compared.
- Backups: `*_pre_ov.lua`.

Your save was restored after the test: HQ 1, 2 spin-offs, $13,613, 3 staff. The snapshot is `11510645938_pre_audit`.
