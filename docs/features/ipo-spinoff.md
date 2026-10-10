# GO PUBLIC (IPO) and SPIN OFF (prestige)
**What:** At the top of the HQ blueprint a company must GO PUBLIC first. `goPublic` in `SiliconCore` lists it, pays a small raise and tells the server. Then `spinOff` can run: pay the spin cost, choose who stays (the home sets how many), and restart in the garage with a permanent +0.5x revenue. `IpoClient` draws the button and the bell. The rules for price and multiplier are `Progression.spinCost` and `Progression.spinMult`.
**How a player reaches it:**
1. Build to the top floor allowed. The cap rises with spin-offs: 18, 30, 43, 55, 68, 80, 93, 100 (`src/ServerScriptService/WaferPlan.lua:19,146`).
2. The quest card says "GO PUBLIC!" (`src/ServerScriptService/Journey.lua:94-97`) and a gold GO PUBLIC button shows when `CanGoPublic` is true (`src/StarterPlayer/StarterPlayerScripts/IpoClient.client.lua:23-46`, attribute set at `SiliconCore.server.lua:1833-1835`).
3. Tap it. The client fires `GoPublic` (`IpoClient.client.lua:39`). The server runs `goPublic` (`SiliconCore.server.lua:3574`). The HQ pad at the top calls it too (`wafersBuild` :2063). The bell card is `moment` (`IpoClient.client.lua:86`).
4. The pad now reads "SPIN OFF $X revenue xN forever" (`refreshHqPad` :2024). Tap the pad, or the guide's "Spin off!". The first tap arms it and sends a `spinAsk` card (`SiliconCore.server.lua:2937-2964`, `HudClient.client.lua:700`).
5. On the card, pick who comes along if more people qualify than the home has seats, then HOLD TO SPIN OFF (`HudClient.client.lua:795`). That fires `SpinConfirm {pick}` (:829) and the server runs `spinOff` again. NOT YET fires `SpinCancel` (:810).
6. `Celebrate` kind `spin` plays the ceremony (`HudClient.client.lua:843`).
**Files:**
- `src/ServerScriptService/SiliconCore.server.lua`: price helpers :112-120, `refreshHqPad` :1971, `SpinConfirm` :2689, `SpinCancel` :2710, `spinOff` :2924-3027, `goPublic` :3574-3595, `GoPublic` remote :543 and :3596, `checkIPO` :3601 (old), `pushTicker` :3612.
- `src/ServerScriptService/Progression.lua`: `SPIN_STEP` :23, `SPIN_CAP` :24, `spinMult` :33, `spinCost` :38, `runScale` :63, `CAPS` :59, `capWindfall` :92, `KEEP_SLOTS` :126, `rankKeepers` :146, `chooseKeepers` :164.
- `src/ServerScriptService/RoomEconomy.lua`: `SPINOFF_BASE` 4,000,000 :235, `KEEP_TALENT` 3 (Star+) :236.
- `src/ServerScriptService/Journey.lua`: `IPO_RAISE` 60 s :31, `milestone` :136-139.
- `src/StarterPlayer/StarterPlayerScripts/IpoClient.client.lua` (button, bell) and `HudClient.client.lua` (`spinAsk` :700, `spinCeremony` :843).
**State:**
- Session: `s.listed` (this company is public; saved), `s.ipo` (set by `goPublic`, never reset), `s.ticker`, `s.spinoffs` (0-20; saved), `s.apt` (seats).
- Plot (temporary): `plot.spinArmed` (clock time, valid 30 s), `plot.spinOffer` ({byId, choose}), `plot.spinSerial`, `plot.spinPickIds`, `plot.spinFromCard`, `plot.busy` (:2938, cleared 1.5 s later :2986).
- Attributes: `CanGoPublic`, `Spinoffs`, `Prestige`. Cost: floor(4M x spinMult(n) x min(1.3^n, 30)). Measured with `lune run tools/late_game`: n=0 $4.0M, n=1 $7.8M, n=2 $13.5M.
**Drive it:**
- Setup: `dev:Invoke("scenario", p, "snapshot")`, then `"rich"`, then `"hq:18"` (free build to the cap, `DevHook.lua:65`), then `"spinoff"` (`DevScenarios.lua:239-246`). The scenario needs the snapshot first.
- Raw: `gopublic` returns `listed=... ticker=...` (`DevHook.lua:167`). `spinoff` back-dates `spinArmed` to skip the confirm tap and keeps the best N (no card) (:82-86).
- After Play stops, restore: `require(game.ServerScriptService.DevScenarios).restore(1688749216)` in EDIT (`DevScenarios.lua:20`).
- No scenario builds "more Star staff than seats" to test the pick card yet.
**Prove it:**
- `tests/offline/progression.spec.luau`: cost, multiplier, wait cap (:26-75) and `chooseKeepers` (:109-200). `clock.spec.luau:44` GO PUBLIC raise cap 10%. `home.spec.luau:83` keeper slots. `journey.spec.luau:80,95` GO PUBLIC before spin-off.
- `lune run tools/late_game` (also `tools/bas sim late_game`) prints price and wait per spin. `bas baseline diff` flags changes (`tools/bas.luau:283-344`).
- `tests/smoke_core.luau:58-62` runs `gopublic` then `spinoff` in Play and snapshots the result.
- No automated check for `goPublic`, `spinOff` or `IpoClient`.
**Gotchas:**
- Two taps, 30 s window (`SiliconCore.server.lua:2937-2964`). While a choice is pending, the pad's second tap cannot confirm: "Choose who comes with you" (:2971-2972).
- `spinOff` only shows a popup when it refuses: "GO PUBLIC first" (:2890), "Need $..." (:2892). `goPublic` returns silently if you are not at the cap (:3525).
- `scenario spinoff` always returns ok = true (`DevScenarios.lua:243-246`). Check `spinoffs` in the result yourself.
- GO PUBLIC raise is 60 s of income, capped at 10% of the spin cost, rounded down (:3530, `Progression.lua:59,104`).
- Kept people come back as Interns and need a seat (`spawnStaff` `tier = 1`, :1477; popup "build a floor" :2974).
- Not reset by a spin-off: `s.apt`, `s.earned`, `s.index`, `s.momentum`, `s.hqPath`. A comment says the style is "committed until a spin-off" (:2072) but `spinOff` never clears `s.hqPath`. Unclear which is intended.
- `checkIPO` (valuation at `IPO_AT` 250,000, `CoreConfig.lua:115`) is only reached from SVDev `valuation` (`DevHook.lua:186`). The real path is `goPublic`.
- At 20 spin-offs `s.spinoffs` stops growing (:2963), so price and multiplier stop too (`Progression.lua:24,28-30`).
- The keep list is built only when `Econ.V3` is on (:2941).
**Last verified:** 2026-10-09 80ce687
