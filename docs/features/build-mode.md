# Build mode (room picker, DECOR mode, FurnitureKit)
**What:** Two builders live here. DECOR mode lets a player browse a furniture catalog, aim a ghost at the floor and buy pieces. The room picker (BuildClient) sells whole wings on empty lots. `FurnitureKit` holds the catalog, sizes and placement maths for both server and client. In Wafers mode the room picker is never reached (see Gotchas).
**How a player reaches it:**
1. DECOR needs `BuildOpen` and `HQLevel` 2 or more (`src/StarterPlayer/StarterPlayerScripts/BuildModeClient.client.lua:126-128`, set at `src/ServerScriptService/SiliconCore.server.lua:1835-1836`). In Wafers mode HQLevel is the stage, so wafer level 5.
2. Press B or the DECOR rail tile. Pick a card (the sheet hides). A see-through ghost follows the cursor. Green fits, red does not.
3. R rotates, click or PLACE buys (`placeItem:FireServer`, `BuildModeClient.client.lua:631-637`). The trash tool fires `RemoveItem` and refunds half (:670-675, server :2598). Q or B leaves.
4. Room picker: the "BUILD" prompt on an empty lot (`SiliconCore.server.lua:980-995`) fires `OpenBuild`. The picker fires `PlaceRoom` (`BuildClient.client.lua:140`, server :2414).
**Files:**
- `src/ReplicatedStorage/FurnitureKit.lua`: `CATALOG` :202 (33 pieces), `BY_KEY` :241, `templateFor` :268, `has` :283, `footprint` :302, `stand` :312, `blocked` :386, `put` :410, `priceFor` :860, `vibePoints` :877, `vibe` :890.
- `src/StarterPlayer/StarterPlayerScripts/BuildModeClient.client.lua`: `unlocked` :126, `rescanFloors` :502, `previewLegal` :534, `aimGhost` :567, `commitPlace` :631, `aimDelete` :643, `setOpen` :819, keys :905.
- `src/StarterPlayer/StarterPlayerScripts/BuildClient.client.lua`: the lot picker. `makeRow` :88, `OpenBuild` listener :161.
- `src/ServerScriptService/SiliconCore.server.lua`: remotes :519-522, `buildWing` :2341, `floorRects` :2425, `roomBuilt` :2438, `placeAt` :2446, `PlaceItem` :2593, `RemoveItem` :2599, `furniturePriceOf` :183.
- `src/ServerScriptService/SaveLoad.lua`: items saved :67-70, restored through `placeAt(..., free)` :301.
**State:**
- Session: `s.placed` (entries: model, key, price, x, z, w, d, y, yaw, surfaceTop, room, slot), `s.placedDesks`, `s.placedMorale`.
- Placed model attributes: `owner`, `key`, `px`, `pz`, `pw`, `pd`, `py` (`SiliconCore.server.lua:2570-2574`), plus `FKItem` and `FKFlip` from the kit. The client reads these for its preview.
- Player attributes: `BuildOpen`, `HQLevel`, `PriceMult`, `IncomeRate`, `VibeStars`, `VibeLuck`, `VibePoints`, `SVRefunded`. Client only: `BuildModeOpen` (`BuildModeClient.client.lua:825`).
- Folders: plot `Placed` (all decor), `plot.fixed` (fixed furniture rects), `plot.slots` (lots).
- Saved: `placed` as k, x, z (plot-local), y (yaw), p (price paid) and `wings` (`SaveLoad.lua:67-76`).
**Drive it:**
- `ship` sets `shipped` and `buildUnlocked` (`DevHook.lua:54-57`). `cash <n>` adds money. `hq:5` reaches stage 2 so DECOR shows.
- No action or scenario places or removes a piece. "none yet". The `bot` places decor through `placeAt` (`DevHook.lua:412`).
- `wingup <slot>` needs a built wing, so in Wafers mode it answers "no wing there" (`DevHook.lua:120-122`).
**Prove it:** no automated check yet for the buy flow. `SVCheck` (Studio, client, `src/ReplicatedStorage/SVCheck.lua:373-795`) checks furniture inside furniture, buried in walls, and through the glass for plot `Garage`, `Rooms`, `Placed`, `Wafers` and `Apt_` folders. The server writes `SVRefunded` when a saved piece is refused on load.
**Gotchas:**
- Server rules in `placeAt`: must have shipped (:2449). Item must exist (:2452-2453). `needs` room must be built (:2454). Yaw snaps to 90 degrees, position to a 0.5 grid, and only X and Z of the client position are used (:2463-2466, :2595). Must fit inside a floor rect (:2473). Desks and tables only in their own room, up to its cap (:2475-2495). Surface items ride a desk (:2497-2512). No overlap unless tucking, stacking on a surface or on a rug (:2514-2533). Not on a seat, not inside room furniture (:2535-2547). Then pay (:2561-2565).
- A refused saved piece is refunded, not lost (:2491-2493, :2548-2551).
- Price: `base x HQ mult x (1 + 0.08 per piece) x scale`, rounded to two decimals. The client uses the same `FurnitureKit.priceFor` (`BuildModeClient.client.lua:87-92`, `SiliconCore.server.lua:183-191`).
- Wafers mode has no lots: `plot.slots = {}` (`SiliconCore.server.lua:1055-1056`), so `OpenBuild`, `PlaceRoom` and BuildClient never fire. `roomBuilt` reads `plot.slots` (:2438-2444), so COMFORT and KITCHEN pieces that have `needs` cannot be placed. By the code only. Not run in Studio.
- The client treats only `GarageFloor` and `Room_*/Floor` as floor (`BuildModeClient.client.lua:507-512`). The server floor is the old HQ rectangle for the stage plus built lots (`SiliconCore.server.lua:2425-2432`). The client is stricter.
- The header of `FurnitureKit.lua` says "ModuleScript in ServerScriptService". It lives in ReplicatedStorage so the client ghost uses the same templates (:2 vs :56-61).
- Pieces face a different way per kit. `FKFlip` fixes it, and `stand` and `put` both add it (`FurnitureKit.lua:246-258`, :312). Do not rotate templates by hand.
- A missing template means no placement at all, never a hole (`FurnitureKit.has`, `SiliconCore.server.lua:2454`).
- Rugs (`flat`) go under anything. Only the first 3 copies of a key count for vibe (`FurnitureKit.lua:872-886`).
**Last verified:** 2026-10-09 f4cf91e
