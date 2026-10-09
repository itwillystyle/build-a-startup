# Homes (apartments, the Residences, the daily VIP)
**What:** A player can buy one of three apartments (STUDIO, LOFT, PENTHOUSE) at The Residences tower. The home is a real floor of that tower. A home decides how many top staff survive a spin-off (1, 3 or 5), and it also sets the daily VIP and the offline pay window. Homes cost a share of the next spin-off, not a fixed price (`src/ServerScriptService/Progression.lua:208`).
**How a player reaches it:**
1. Reach HQ 2 (Studio), HQ 3 (Loft) or HQ 4 (Penthouse). Tiers must be bought in order (`src/ServerScriptService/Apartments.lua:416-429`).
2. Walk to The Residences lobby. Use the sales desk prompt "Buy an apartment" (`Apartments.lua:566`). The `AptMenu` remote opens the card.
3. Tap BUY. The client fires `AptBuy`. The server charges, sets `s.apt`, builds the unit and plays the move-in shot (`Apartments.lua:447-486`).
4. Later, use the lobby lift prompt "Go home" (`Apartments.lua:574`). The unit's own lift prompt "Go down" brings you back (`Apartments.lua:390`).
5. Spin-off: the card lets you pick who stays, up to your slot count (`src/ServerScriptService/SiliconCore.server.lua:2908-2919`).
6. The daily VIP: a loop checks every 20 s and calls `Apartments.trySpawnVip` (`Apartments.lua:533-535`).
**Files:**
- `src/ServerScriptService/Apartments.lua`: tiers, buy, go home, units, VIP. `priceOf` :49, `floorOf` :119, `buildUnit` :359, `goHome` :432, `buy` :447, `trySpawnVip` :502, `init` :529, `onLoad` :608.
- `src/ServerScriptService/Downtown.lua`: builds the city. `RES` and `DEALER` ring positions :63-64, `RES_SIZE` :71, lobby, sales desk and lift :276-298, `build` :182.
- `src/StarterPlayer/StarterPlayerScripts/HomeClient.client.lua`: sales card :72, fades :136, move-in and car shots :164, indoor zoom cap :209, HQ level-up orbit :244.
- `src/StarterPlayer/StarterPlayerScripts/LiftClient.client.lua`: floor picker for HQ lifts, NOT the Residences lift. Covered in hq-paths.md.
- `src/ServerScriptService/Progression.lua`: `APARTMENTS` :107, `KEEP_SLOTS` :126, `keepSlots` :128, `rankKeepers` :146, `chooseKeepers` :164, `HOME_SHARE` :208, `homePrice` :210.
- Keeper slots in the spin-off: `SiliconCore.server.lua:2662` (SpinConfirm), `:2908-2946` (offer and keep). Card UI: `HudClient.client.lua:700` (spinAsk).
**State:**
- Session: `s.apt` (0-3), `s.vipDay` (UTC day number), `s.lastBuy`. Price reads `s.spinoffs` (`Apartments.lua:49-52`).
- Player attribute: `Apt` (`Apartments.lua:463`). I found no reader in `src`. Unclear if it is used.
- Unit model `Apt_<userId>` has attributes `Owner`, `Tier`, `Stand`, `View` (`Apartments.lua:371-372, 408-410`).
- Saved: `apt`, `vipDay` (`src/ServerScriptService/SaveLoad.lua:133-134`). Load clamps `apt` to 0-3 (`SaveLoad.lua:358`).
- Plot, temporary: `plot.spinArmed`, `spinOffer`, `spinPickIds`. The card is armed for 30 s.
**Drive it:**
- `dev:Invoke("scenario", p, "home:<0-3>")` runs raw `apt <n>` (`src/ServerScriptService/DevScenarios.lua:232`, `DevHook.lua:488`).
- `"tp:apt"` goes to the sales desk (`DevScenarios.lua:251`). `"vip-chase"` sets apt 1, spawns the VIP, walks to it, picks it up (`DevScenarios.lua:216`).
- Raw `apt <0-3>`, `vip` (`DevHook.lua:493`), `vippick` (`:497`).
- Keeper pick on the spin-off card: `spinoff` scenario needs `snapshot` first (`DevScenarios.lua:237`). No scenario sets up "more Star staff than slots" yet.
**Prove it:**
- `tests/offline/home.spec.luau`: ladder is HQ steps only, offline pay windows, keeper slot table (1/3/5), a bad save cannot mint slots, home price shares, no money bonus left.
- `tests/offline/progression.spec.luau`: `chooseKeepers` cases (pick beats order, left or demoted staff dropped, stale ids ignored, no over-fill).
- `lune run tools/curve_check` prints home prices as a share of a spin-off. `lune run tools/late_game` prints the late loop (uses `P.offline` per apt).
- `SVCheck` (Studio, client) has a "downtown" camera view. Nothing checks the buy flow or the unit build. No automated check yet for those.
**Gotchas:**
- SVDev `apt` only sets `s.apt` and recomputes (`DevHook.lua:488-492`). It skips the price, the HQ gate, the `Apt` attribute and the objective refresh. The unit is built on the first "Go home" (`Apartments.lua:434`).
- `vipSpot` is `Vector3.new(640 + 9*plot, 0, 36)` (`Apartments.lua:498-501`). The Residences moved to the campus ring at 240 degrees (`Downtown.lua:43-64`). The comment says "outside the Residences" and the phone text says "outside your building". Unclear if the old plaza spot is still intended.
- `vipDay` is set at pickup, not at spawn, so an unclaimed VIP waits (`Apartments.lua:485-488`).
- `trySpawnVip` needs `s.shipped`, apt 1+, not Carrying, and no VIP already out (`Apartments.lua:504-508`).
- Floor = `(tier-1)*6 + (plot-1)`, so six players never share a floor (`Apartments.lua:119-123`).
- Arrival stands are placed well clear of the lift wall or the camera ends up inside it (`Apartments.lua:406-407`).
- If the Residences mesh is missing, no sales desk or lift exists. `init` waits 30 s, then gives up silently (`Apartments.lua:560-564`, `Downtown.lua:270`).
- While a keeper choice is pending, the pad's second tap cannot confirm. Only the card can (`SiliconCore.server.lua:2933-2936`). Picks are opaque ids matched to staff entries, never positions (`Progression.lua:140-145`).
- `SPINOFF_BASE` is asserted at load. A missing base would sell homes for $1 (`Apartments.lua:43-44`).
**Last verified:** 2026-10-09 cf0adc8
