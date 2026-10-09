# Dev tools (SVDev, scenarios, SVCheck, bas, the bot)
**What:** Tools to put the game in a known state and to prove a change. Studio only: the `SVDev` BindableFunction (`DevHook`), `DevScenarios`, `SVCheck`, `StyleBaseline` with `SVStyle`, and `tests/smoke_core.luau`. Plain Lune from the game folder: `tools/bas.luau` plus the offline tests and sims. The bot is SVDev action `bot`. It plays the real handlers by following the on-screen guide.
**How a player reaches it:** Not a player feature. `SiliconCore` mounts `DevHook` only when `RunService:IsStudio()` (`src/ServerScriptService/SiliconCore.server.lua:3942-3943`), so a published server has no `SVDev`. Reach it in Play, SERVER datamodel: `local p = game.Players:GetPlayers()[1]; local dev = game.ServerScriptService.SiliconCore.SVDev; return dev:Invoke("scenario", p, "list")` (`src/ServerScriptService/DevScenarios.lua:9-12`). Lune tools run as `lune run tools/bas help` from the game folder (`tools/bas.luau:566`).
**Files:**
- `src/ServerScriptService/DevHook.lua`: makes `SVDev` under the SiliconCore script (:44-46). `handle(action, player, arg)` :49, `dev.OnInvoke` :525. 38 actions, one `elseif action ==` each (:53-514): ship, cash, upgrade, wlevel, spinoff, earned, talent, save, bell, rival, launch, buzzoff, wingup, share, peek, wipe, offer, tier, phone, phoneoffer, gopublic, hire, work, product, name, valuation, bot, rolls, item, seats, apt, vip, vippick, recruit, botlog, botstop, scenario, state. Unknown returns "unknown" (:523). No session returns "no session" (:52).
- `src/ServerScriptService/DevScenarios.lua`: `Scen.LIST` :37-41 = snapshot, rich, ready, chase:skilled, chase:star, chase:genius, vip-chase, hq:<n>, home:<0-3>, spinoff, tp:hq, tp:apt, tp:car, tp:candidate:<tier>, tp:vip, list. `allowed` :43, `snapshot` :56, `restore` :70, `run` :117, `compareSnapshot` :97 (after a restore: does the live save equal the snapshot, ignoring `lastSeen`?).
- `src/ReplicatedStorage/SVCheck.lua`: `run()` :924 runs five passes: budget :69, screen :125, world :220, placement :373, errors :796. `shot(i)` :848 and `endShots()` :902 take 7 fixed camera framings (`SHOTS` :836).
- `src/ReplicatedStorage/StyleBaseline.lua`: the counts `src/ReplicatedStorage/SVStyle.lua` ratchets against (`run` :303, `baselineSrc` :280). Keys: colours, flatNeutral, neonLoose, offPalette, sharp, untintedPack (parts, untintedOwn are context).
- `tests/smoke_core.luau`: Play, SERVER. Drives SVDev through HQ ups, tier, offer, launch, gopublic, spinoff, save, peek. Returns numbers only, so two runs can be diffed.
- `tools/bas.luau`: `check` :172, `doctor` :177, `sim` :249 (`SIMS` :205), `baseline` :318, `evidence` :341, `scenario list` :425, `map check` :452.
- Other tools: `tools/late_game.luau`, `chase_threat`, `chase_sim`, `chase_edit`, `turn_probe`, `curve_check` (Lune); `ui_audit`, `algo_check`, `world_overlap`, `ui_overlap`, `chase_lab` (paste into Studio); `ui_scan.py`.
**State:**
- Bot: `s.bot = { runs, t0, log, pace, paid, earnedStart, lastBuy, longest, buys, fails, running }` (`DevHook.lua:198`). It prints `[BOT]` lines (:203).
- Scenarios: `snapped[userId]` marks a snapshot taken in this server (`DevScenarios.lua:35`).
- Lune side: `.bas/baseline.json` and `.evidence/<date>-<slug>/`. Both are git-ignored (`tools/bas.luau:19-20,267`).
**Drive it:**
- Scenarios: `dev:Invoke("scenario", p, "chase:genius")`. Order for a destructive one: `snapshot`, setup, test, stop Play, then `require(game.ServerScriptService.DevScenarios).restore(1688749216)` in EDIT.
- Bot: `dev:Invoke("bot", p, "20 2")` = a buy every 20 s, 2 companies. `botlog` returns the log. `botstop` stops it (`DevHook.lua:188,506,508`).
- Other: `lune run tools/bas check | doctor | sim all | baseline save | baseline diff | scenario list | map check`. Add `--json` for one JSON object. Exit 0 ok, 1 failed, 2 usage.
**Prove it:**
- `bas check` = selene on `src tests tools` plus `lune run tests/offline/run` (218 pass, 13 spec files at 287a211) (`tools/bas.luau:137-175`).
- `bas baseline diff` compares tests passed, chase escape rates (default tolerance 5 points) and spin price, wait and night cover (:282-316).
- `bas map check` checks every `src` module is named on a page here, and that no cited file changed after the page's commit (:452-527).
- `SVCheck` cannot see server errors, a second player, or whether the game is fun (`SVCheck.lua:24-28`). Nothing tests `DevHook` or `DevScenarios` themselves.
**Gotchas:**
- Use `SVDev`, not `require`. A `require` from execute_luau returns a fresh module copy, so it drives an unused copy of the game (`DevHook.lua:103-106`, `DevScenarios.lua:14-15`).
- `scenario` is limited to Wilz and negative ids (`DevScenarios.lua:43-45`). The raw actions `wipe`, `cash`, `spinoff` and `save` check nothing.
- `scenario spinoff` needs a snapshot taken in this server (:238) and always returns ok = true (:241-244).
- `hire` only adds the first intern while TalentDrop is on (`SiliconCore.server.lua:1870`). Use `recruit`.
- The bot stops after `runs` spin-offs or 45 minutes per company (`DevHook.lua:434,465`). It stops if the session is replaced (:208).
- `StyleBaseline.lua:6` says SVStyle "fails on any rise". `SVStyle.run` only returns a text VERDICT line (`SVStyle.lua:357-364`). It is not part of `SVCheck.run` or `bas`.
- `SVCheck` budget numbers are fake when the Studio window is not rendering. It says so when all four views match (`SVCheck.lua:103-111`).
- `smoke_core` mutates the save (apt, HQ, spin-off). Snapshot first (`smoke_core.luau:6-7`).
- `bas scenario list` reads `Scen.LIST` with the pattern `Scen%.LIST = (%b{})` (`tools/bas.luau:426-427`). Keep it a plain list of strings.
- `bas` must run from the game folder, where `default.project.json` is (`tools/bas.luau:566`).
**Last verified:** 2026-10-09 cf0adc8
