# Core loop (tap, hire, build, launch, climb)
**What:** The main game. You tap WRITE CODE, ship an app, hire people, build HQ floors, and launch apps for paydays. Income per second comes from seated staff times a stack of multipliers. The server owns all of it. `SiliconCore` (`SiliconCore.server.lua`) holds the state and the handlers. `CoreConfig`, `RoomEconomy`, `Progression`, `Momentum` and `Journey` hold the numbers and rules. `HudClient` and `ProductClient` draw it.
**How a player reaches it:**
1. Join. `onJoin` gives you a plot and spawns you in the garage (`src/ServerScriptService/SiliconCore.server.lua:3796`, `assignPlot` :2990).
2. Tap the laptop prompt "WRITE CODE" (`wirePlot` :2840) or the HUD button (`HudClient.client.lua:208,396`). A tap pays max($5, 0.18 s of income) with a combo (`CoreConfig.lua:10-16`).
3. Third tap ships the To-Do App (`CLICKS_TO_SHIP` `CoreConfig.lua:17`, `shipFirstProduct` :1291).
4. Step on the HIRE pad for a free intern (`hire` :1865, see hiring-talent.md). The company name box follows, then the door opens and BUILD pads turn on (beat driver :3859-3901).
5. HQ pad prompt "UPGRADE" (:2855) calls `tryUpgrade` :2161, then `wafersBuild` :2052. The first floor asks for an HQ style first (:2074-2080).
6. Seated staff fill the product bar. When full, the WRITE CODE button turns into LAUNCH! (`HudClient.client.lua:334`; key L :387-390). Launch pays a payday (`launchProduct` :3170).
7. The quest card walks you through each HQ level (`Journey.LADDER` `Journey.lua:37`). Top of the blueprint ends in GO PUBLIC and SPIN OFF (see ipo-spinoff.md).
**Files:**
- `src/ServerScriptService/SiliconCore.server.lua` (4,103 lines): `recompute` :1197 (rate = `base * F - wages`, :1237-1240), `writeCode` :1312, `journeyState` :1549, `refreshObjective` :1604, `refreshHqPad` :1965, `checkMilestones` :2035, income tick :3047, `offerProduct` :3257, `productLoop` :3334. Remotes `WriteCode` :2642, `PickMarket` :3246, `ProductReady` :525, `Celebrate` :2662.
- `src/ServerScriptService/CoreConfig.lua`: pure tuning data. `HQ_LEVELS` :46, `TALENT` :80, `MILESTONE_*` :61-63, `IPO_AT` :115.
- `src/ServerScriptService/RoomEconomy.lua`: price ladder `V3` :223, `HQ_COST` :228, `CAP_BY_HQ` :229, `LAUNCH_PAY` :233, `SPINOFF_BASE` :235; stations :37, role fit :64, recruit tiers :353.
- `src/ServerScriptService/Progression.lua`: `spinMult` :33, `spinCost` :38, `runScale` :63 (prices of company n+1), `capWindfall` :92.
- `src/ServerScriptService/Momentum.lua`: stock max 24 :37, `AWARD` :45, `discount` :70, `priceAfter` :75, `quote` :83. Up to 36% off the next build. A rebuild (a level at or below your record, after a spin-off) pays the plain price and spends no momentum.
- `src/ServerScriptService/Journey.lua`: `task` :71, `milestone` :122, `TIPS` :156. Pure. SiliconCore builds a plain table and asks it what to show.
- `src/StarterPlayer/StarterPlayerScripts/HudClient.client.lua`: cash and income line :472-505, `Celebrate` events :866, welcome-back card :903.
- `src/StarterPlayer/StarterPlayerScripts/ProductClient.client.lua`: old 3-market picker :195 (non-V3), acquisition offer card :333, toasts :356.
**State:**
- `sessions[userId]` made in `onJoin` :3790 (clicks, shipped, rate, staff, rigs, placed). Later fields: `valuation`, `earned`, `milestones`, `work`, `workNeed`, `pendingProduct`, `momentum`, `listed`, `spinoffs`, `jr`, `tips`.
- Attributes the HUD reads: `Objective*` :1839-1843, `Milestone*`, `CoachTip`, `CanGoPublic`, `Shipped`, `BuildOpen`, `HQLevel`, `ProductProgress`, `CodeTap`, `Momentum`, `PriceMult`, `IncomeRooms`, `Away`. Leaderstats: Cash, Per Sec, Staff, Valuation.
- Saved: see saving-data.md (`SaveLoad.lua:76-140`).
**Drive it:**
- `dev:Invoke("scenario", p, "ready")`: ship, $1e9 if under $1e8, one hire (`DevScenarios.lua:148-173`). `"rich"` adds $1e9. `"hq:<n>"` builds free to Wafers level n (:229).
- Raw SVDev: `ship`, `cash <n>`, `upgrade`, `work <n>`, `product` (LAUNCH now), `launch <1-6>`, `earned <n>`, `state` (`DevHook.lua:53,58,62,175,178,113,87,514`).
- `dev:Invoke("bot", p, "20 2")` plays the whole loop for 2 companies and logs `[BOT]` lines (`DevHook.lua:188`). Read with `botlog`.
**Prove it:**
- Offline specs (`lune run tests/offline/run`, 218 pass at 287a211): `journey.spec.luau`, `momentum.spec.luau`, `progression.spec.luau`, `clock.spec.luau`, `home.spec.luau`.
- `lune run tools/late_game` prints spin prices and waits from the same `Progression` code. `lune run tools/bas baseline diff` flags drift.
- `tests/smoke_core.luau` (Play, server) walks HQ ups, go public, spin-off, save. Diff before and after a refactor.
- No spec requires `CoreConfig` or `SiliconCore`. `HudClient` and `ProductClient` have no automated check. `SVCheck` screen pass only finds overlaps.
**Gotchas:**
- CoreConfig HQ costs are stale. `SiliconCore.server.lua:80` overwrites them with `RoomEconomy.HQ_COST`. HQ_MULT is also bypassed when Wafers is on (:98-100).
- `writeCode` drops any call within 0.35 s of the last (:1317). Fast scripted taps pay once.
- Wages are not charged under V3 (:1224). `Econ.WAGE` is unused for income now.
- Launch boost is dead under V3: `launchProduct` sets `s.launch = nil` (:3184). A launch is a payday only.
- Auto-launch after 60 s only happens once you have launched by hand (:3266-3271).
- SaveLoad sets `s.momentum` on load (`SaveLoad.lua:361`) but no code sets the `Momentum` attribute then (only :1952, :2092, :3199). The HUD may show 0 after a rejoin until the next change. Not run to confirm.
- The HUD copies momentum math: `math.min(mom, 12) * 3` (`HudClient.client.lua:497`). Changing `Momentum.SPEND_CAP` or `PER_POINT` will not change it.
- `SiliconCore` is at Luau's 200 local limit (:2659, :3786). New code goes in a module or a `do` block.
- The objective attributes refresh every 0.4 s (:3845-3857). Tests that read them right after an action can see the old value (`DevHook.lua:235`).
- `Journey.task` returns nil while you carry a recruit, a product waits, or nothing shipped (`Journey.lua:72`).
**Last verified:** 2026-10-09 f4cf91e
