# Core loop (clients, hire, build, launch, climb)
**What:** The main game. You code apps for clients at the door (client-loop.md), ship your first app, hire people, build HQ floors, and launch apps for paydays. Income per second comes from seated staff times a stack of multipliers; client pay comes on top. The server owns all of it. `SiliconCore` (`SiliconCore.server.lua`) holds the state and the handlers. `CoreConfig`, `RoomEconomy`, `Progression`, `Momentum` and `Journey` hold the numbers and rules. `ClientsServer` runs the clients. `HudClient` and `ProductClient` draw it.
**How a player reaches it:**
1. Join. `onJoin` gives you a plot and spawns you in the garage (`src/ServerScriptService/SiliconCore.server.lua:4045`, `assignPlot` :3221). A new company gets a generated name (`Names.lua`, called at `SiliconCore.server.lua:4074-4081`), no name box.
2. The first client knocks and the door opens. Hold WRITE CODE (the laptop prompt "HOLD TO CODE", `wirePlot` :3056-3064, or the HUD button, `HudClient.client.lua:262,474`) to code their job, then GIVE it. The whole loop is on client-loop.md. Money comes from clients (`ClientsServer.paid`) plus products and launches; coding pays nothing by itself.
3. Handing the first client their to-do app ships your first product (`core.shipFirstProduct`, `shipFirstProduct` :1352). `CLICKS_TO_SHIP` (`CoreConfig.lua:17`) is no longer used to ship.
4. Step on the HIRE pad for a free intern (`hire` :1934, see hiring-talent.md). Then the BUILD pads turn on (beat driver :4130-4161).
5. HQ pad prompt "UPGRADE" (:3078) calls `tryUpgrade` :2258, then `wafersBuild` :2127. The lobby goes up as Glass; the HQ style picker (AskPath) opens once, on the first floor above the lobby (:2153-2164).
6. From the lobby (Wafer level 2) seated staff fill the product bar (`Clients.productsOpen`, income gate :3352-3355). When full, LAUNCH! shows as its own gold button above WRITE CODE (`HudClient.client.lua:326`, `setLaunch` :427; key L :454-457). Launch pays a payday (`launchProduct` :3416).
7. The quest card walks you through each HQ level (`Journey.LADDER` `Journey.lua:37`). Top of the blueprint ends in GO PUBLIC and SPIN OFF (see ipo-spinoff.md).
**Files:**
- `src/ServerScriptService/SiliconCore.server.lua` (4,377 lines): `recompute` :1234 (rate = `base * F - wages`, :1278-1281), `writeCode` :1362 (a tap, see Gotchas), `journeyState` :1579, `refreshObjective` :1634, `refreshHqPad` :2033, `checkMilestones` :2109, income tick :3278, `offerProduct` :3502, `productLoop` :3579. Remotes `WriteCode` :2791, `PickMarket` :3491, `ProductReady` :549, `Celebrate` :2811. The client loop is wired at :4200-4214 (`Econ.Clients`).
- `src/ServerScriptService/CoreConfig.lua`: pure tuning data. `HQ_LEVELS` :46, `TALENT` :80, `MILESTONE_*` :61-63, `IPO_AT` :115.
- `src/ServerScriptService/RoomEconomy.lua`: price ladder `V3` :223, `HQ_COST` :228, `CAP_BY_HQ` :229, `LAUNCH_PAY` :233, `SPINOFF_BASE` :235; stations :37, role fit :64, recruit tiers :353.
- `src/ServerScriptService/Progression.lua`: `spinMult` :33, `spinCost` :38, `runScale` :63 (prices of company n+1), `capWindfall` :92.
- `src/ServerScriptService/Momentum.lua`: stock max 24 :37, `AWARD` :45, `discount` :70, `priceAfter` :75, `quote` :83. Up to 36% off the next build. A rebuild (a level at or below your record, after a spin-off) pays the plain price and spends no momentum.
- `src/ServerScriptService/Journey.lua`: `task` :71, `milestone` :125, `TIPS` :159. Pure. SiliconCore builds a plain table and asks it what to show.
- `src/StarterPlayer/StarterPlayerScripts/HudClient.client.lua`: cash and income line :545-581, `Celebrate` events :988, welcome-back card :1033.
- `src/StarterPlayer/StarterPlayerScripts/ProductClient.client.lua`: old 3-market picker :195 (non-V3), acquisition offer card :333, toasts :356.
**State:**
- `sessions[userId]` made in `onJoin` :4048 (clicks, shipped, rate, staff, rigs, placed). Later fields: `valuation`, `earned`, `milestones`, `work`, `workNeed`, `pendingProduct`, `momentum`, `listed`, `spinoffs`, `jr`, `tips`.
- Attributes the HUD reads: `Objective*` :1908-1913, `Milestone*`, `CoachTip`, `CanGoPublic`, `Shipped`, `BuildOpen`, `HQLevel`, `ProductProgress`, `Momentum`, `PriceMult`, `IncomeRooms`, `Away`. Leaderstats: Cash, Per Sec, Staff, Valuation.
- Saved: see saving-data.md (`SaveLoad.lua:80-151`).
**Drive it:**
- `dev:Invoke("scenario", p, "ready")`: ship, $1e9 if under $1e8, one hire (`DevScenarios.lua:148-173`). `"rich"` adds $1e9. `"hq:<n>"` builds exactly Wafers level n, past the blueprint cap and down by a rebuild, and returns `level` (:259).
- Raw SVDev: `ship`, `cash <n>`, `upgrade`, `work <n>`, `product` (LAUNCH now), `launch <1-6>`, `earned <n>`, `state` (`DevHook.lua:53,58,62,194,197,119,93,559`). `clients state|serve|fresh` drives the client loop (client-loop.md).
- `dev:Invoke("bot", p, "20 2")` plays the whole loop for 2 companies and logs `[BOT]` lines (`DevHook.lua:207`). With the client loop it walks to the laptop, holds, carries and presses GIVE (:230-251). Read with `botlog`.
**Prove it:**
- Offline specs (`lune run tests/offline/run`, 218 pass at 287a211): `journey.spec.luau`, `momentum.spec.luau`, `progression.spec.luau`, `clock.spec.luau`, `home.spec.luau`.
- `lune run tools/late_game` prints spin prices and waits from the same `Progression` code. `lune run tools/bas baseline diff` flags drift.
- `tests/smoke_core.luau` (Play, server) walks HQ ups, go public, spin-off, save. Diff before and after a refactor.
- No spec requires `CoreConfig` or `SiliconCore`. `HudClient` and `ProductClient` have no automated check. `SVCheck` screen pass only finds overlaps.
**Gotchas:**
- CoreConfig HQ costs are stale. `SiliconCore.server.lua:87` overwrites them with `RoomEconomy.HQ_COST`. HQ_MULT is also bypassed when Wafers is on (:105-107).
- A tap (the `WriteCode` remote, a laptop click) is `writeCode` :1362 -> `ClientsServer` `api.tap`: a 0.35 s hold, no pay per tap.
- Wages are not charged under V3 (:1262). `Econ.WAGE` is unused for income now.
- Launch boost is dead under V3: `launchProduct` sets `s.launch = nil` (:3430). A launch is a payday only.
- Auto-launch after 60 s only happens once you have launched by hand (:3514-3519).
- SaveLoad sets `s.momentum` on load (`SaveLoad.lua:400`) and the `Momentum` attribute the HUD reads (:401); the game also sets it at `SiliconCore.server.lua:2021`, :2179, :3446. (An older note here said nothing set it on load; that is no longer true, checked 14 Oct.)
- The HUD copies momentum math: `math.min(mom, 12) * 3` (`HudClient.client.lua:573`). Changing `Momentum.SPEND_CAP` or `PER_POINT` will not change it.
- `SiliconCore` is at Luau's 200 local limit (:440, :4043). New code goes in a module or a `do` block.
- The objective attributes refresh every 0.4 s (:4116-4128). Tests that read them right after an action can see the old value (`DevHook.lua:276`).
- `Journey.task` returns nil while you carry a recruit, a product waits, or nothing shipped (`Journey.lua:72`).
**Last verified:** 2026-10-17 0358b25
