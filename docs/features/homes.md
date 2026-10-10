# Homes (apartments, the Residences, the daily VIP)
**What:** A player can buy one of three apartments (STUDIO, LOFT, PENTHOUSE) at The Residences tower. The home is a real floor of that tower. A home decides how many top staff survive a spin-off (1, 3 or 5), and it also sets the daily VIP and the offline pay window. Homes cost a share of the next spin-off, not a fixed price (`src/ServerScriptService/Progression.lua:208`).
**How a player reaches it:**
1. Reach HQ 2 (Studio), HQ 3 (Loft) or HQ 4 (Penthouse). Tiers must be bought in order (`src/ServerScriptService/Apartments.lua:412-425`).
2. Walk to The Residences lobby. Use the sales desk prompt "Buy an apartment" (`Apartments.lua:563`). The `AptMenu` remote opens the card.
3. Tap BUY. The client fires `AptBuy`. The server charges, sets `s.apt`, builds the unit and plays the move-in shot (`Apartments.lua:443-483`).
4. Later, use the lobby lift prompt "Go home" (`Apartments.lua:571`). The unit's own lift prompt "Go down" brings you back (`Apartments.lua:386`).
5. Spin-off: the card lets you pick who stays, up to your slot count (`src/ServerScriptService/SiliconCore.server.lua:2946-2957`).
6. The daily VIP: a loop checks every 20 s and calls `Apartments.trySpawnVip` (`Apartments.lua:530-532`).
**Files:**
- `src/ServerScriptService/Apartments.lua`: tiers, buy, go home, units, VIP. `priceOf` :50, `floorOf` :115, `buildUnit` :355, `goHome` :428, `buy` :443, `trySpawnVip` :499, `init` :526, `onLoad` :606.
- `src/ServerScriptService/Downtown.lua`: builds the city. `RES` and `DEALER` ring positions :60-61, `RES_SIZE` :68, lobby, sales desk and lift :271-293, `build` :177.
- `src/StarterPlayer/StarterPlayerScripts/HomeClient.client.lua`: sales card :72, fades :136, move-in and car shots :164, indoor zoom cap :209, HQ level-up orbit :244.
- `src/StarterPlayer/StarterPlayerScripts/LiftClient.client.lua`: floor picker for HQ lifts, NOT the Residences lift. Covered in hq-paths.md.
- `src/ServerScriptService/Progression.lua`: `APARTMENTS` :107, `KEEP_SLOTS` :126, `keepSlots` :128, `rankKeepers` :146, `chooseKeepers` :164, `HOME_SHARE` :208, `homePrice` :210.
- Keeper slots in the spin-off: `SiliconCore.server.lua:2689` (SpinConfirm), `:2946-2984` (offer and keep). Card UI: `HudClient.client.lua:700` (spinAsk).
**State:**
- Session: `s.apt` (0-3), `s.vipDay` (UTC day number), `s.lastBuy`. Price reads `s.spinoffs` (`Apartments.lua:50-53`).
- Player attribute: `Apt` (`Apartments.lua:460`). I found no reader in `src`. Unclear if it is used.
- Unit model `Apt_<userId>` has attributes `Owner`, `Tier`, `Stand`, `View` (`Apartments.lua:367-368, 404-406`).
- Saved: `apt`, `vipDay` (`src/ServerScriptService/SaveLoad.lua:135-136`). Load clamps `apt` to 0-3 (`SaveLoad.lua:361`).
- Plot, temporary: `plot.spinArmed`, `spinOffer`, `spinPickIds`. The card is armed for 30 s.
**Drive it:**
- `dev:Invoke("scenario", p, "home:<0-3>")` runs raw `apt <n>` (`src/ServerScriptService/DevScenarios.lua:250-254`, `DevHook.lua:488`).
- `"tp:apt"` goes to the sales desk (`DevScenarios.lua:271-272`). `"vip-chase"` sets apt 1, spawns the VIP, walks to it, picks it up (`DevScenarios.lua:234-244`).
- Raw `apt <0-3>`, `vip` (`DevHook.lua:493`), `vippick` (`:497`).
- Keeper pick on the spin-off card: `spinoff` scenario needs `snapshot` first (`DevScenarios.lua:256`). No scenario sets up "more Star staff than slots" yet.
**Prove it:**
- `tests/offline/home.spec.luau`: ladder is HQ steps only, offline pay windows, keeper slot table (1/3/5), a bad save cannot mint slots, home price shares, no money bonus left.
- `tests/offline/progression.spec.luau`: `chooseKeepers` cases (pick beats order, left or demoted staff dropped, stale ids ignored, no over-fill).
- `lune run tools/curve_check` prints home prices as a share of a spin-off. `lune run tools/late_game` prints the late loop (uses `P.offline` per apt).
- `SVCheck` (Studio, client) has a "downtown" camera view. Nothing checks the buy flow or the unit build. No automated check yet for those.
**Gotchas:**
- SVDev `apt` only sets `s.apt` and recomputes (`DevHook.lua:488-492`). It skips the price, the HQ gate, the `Apt` attribute and the objective refresh. The unit is built on the first "Go home" (`Apartments.lua:430`).
- `vipSpot` is `Vector3.new(640 + 9*plot, 0, 36)` (`Apartments.lua:495-498`). The Residences moved to the campus ring at 240 degrees (`Downtown.lua:43-61`). The comment says "outside the Residences" and the phone text says "outside your building". Unclear if the old plaza spot is still intended.
- The VIP run ends at your HQ doorstep (within 14 studs, `Chase.DELIVER_R`), not at the Residences (`src/ServerScriptService/TalentDrop.lua:647`). The VIP has no `pathLen`, so its offer timer uses the straight line from the VIP to your door (`TalentDrop.lua:533`). The VIP hunter spawns 22 studs from the VIP, away from your door (`TalentDrop.lua:557-561`).
- `vipDay` is set at pickup, not at spawn, so an unclaimed VIP waits (`Apartments.lua:482-485`).
- `trySpawnVip` needs `s.shipped`, apt 1+, not Carrying, and no VIP already out (`Apartments.lua:501-505`).
- Floor = `(tier-1)*6 + (plot-1)`, so six players never share a floor (`Apartments.lua:115-119`).
- Arrival stands are placed well clear of the lift wall or the camera ends up inside it (`Apartments.lua:402-403`).
- If the Residences mesh is missing, no sales desk or lift exists. `init` waits 30 s, then gives up silently (`Apartments.lua:557-561`, `Downtown.lua:265`).
- While a keeper choice is pending, the pad's second tap cannot confirm. Only the card can (`SiliconCore.server.lua:2971-2974`). Picks are opaque ids matched to staff entries, never positions (`Progression.lua:140-145`).
- `SPINOFF_BASE` is asserted at load. A missing base would sell homes for $1 (`Apartments.lua:44-45`).
**Last verified:** 2026-10-09 80ce687
