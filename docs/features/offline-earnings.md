# Offline earnings (money while you were away)
**What:** When a player with a saved record joins, the server pays money for the time they were gone. The rule lives in `Progression.offline` and is reached as `Apartments.offline`. `SaveLoad.applySave` calls it. Pay is 25% of income for the time your home covers, never less than 10 minutes of income, never more than one next step, never enough to buy two steps. The HUD shows a WHILE YOU WERE AWAY card with COLLECT.
**How a player reaches it:**
1. Play, leave, come back later. The record has `rate` and `lastSeen` from the last save.
2. Join. `onJoin` calls `SaveLoad.loadOnce` (`src/ServerScriptService/SiliconCore.server.lua:3870`), which sets `Returning` (`src/ServerScriptService/SaveLoad.lua:392`) and calls `applySave`.
3. `applySave` adds cash and sets `OfflineEarned` and `OfflineApt` (`SaveLoad.lua:209-216`).
4. A "WELCOME BACK" flyover plays (`src/StarterPlayer/StarterPlayerScripts/IntroClient.client.lua:150-159`).
5. `HudClient` waits up to 12 s for `OfflineEarned`. A small amount is a line under the cash. A bigger one is a centre card with COLLECT (auto-collects after 20 s) (`src/StarterPlayer/StarterPlayerScripts/HudClient.client.lua:907-981`).
**Files:**
- `src/ServerScriptService/SaveLoad.lua`: `serialize` stamps `rate` :99 and `lastSeen` :100. `applySave` offline block :183-216 (away clamp :186, old formula :187-190, home rule :194-211, pay :212-216). `loadOnce` :378.
- `src/ServerScriptService/Progression.lua`: `WINDOW` :222, `OFFLINE_RATE` :223, `OFFLINE_FLOOR` :224, `ladder` :231, `offline` :246.
- `src/ServerScriptService/Apartments.lua`: aliases `WINDOW`, `ladder`, `offline` to Progression (:65-69). Rationale comment :55-64.
- `src/ServerScriptService/RoomEconomy.lua`: `OFFLINE_CAP` 600 s :238 (only the fallback now), `AFK_SECONDS` 300 and `AFK_RATE` 0.25 :207-208 (the in-session cousin).
- `src/StarterPlayer/StarterPlayerScripts/HudClient.client.lua`: `pendingOffline` holds cash back :466,476. The home gets the credit line :952.
**State:**
- Record: `rate`, `lastSeen`, `cash`, `apt`, `hq`, `wl`, `rec`, `spinoffs` (`SaveLoad.lua:78-142`). The pay is computed from these, not from a live recompute.
- Attributes: `Returning`, `OfflineEarned` (only when pay > 0), `OfflineApt` (set whenever the home rule runs), `WelcomeDone` (set by HudClient), `Away` (in-session AFK).
- Formula: `min(rate x 0.25 x min(away, WINDOW[apt]), max(rate x 600, nextStep), next + after - cash - 1)`. `away` is capped at 8 h. WINDOW is 40 min with no home, then 2 h, 4 h, 8 h for Studio, Loft, Penthouse.
**Drive it:**
- None yet. No SVDev action ages `lastSeen`. `peek` shows the record (`DevHook.lua:128`), `save` writes it (:100). A manual test needs a lower `lastSeen` written to `SVSave_v1` while Play is stopped.
- For the numbers only: `lune run tools/late_game` (the `nightCover` columns call `P.offline`).
- `DevScenarios.restore` sets `lastSeen = now` on purpose so a restore never pays offline money (`DevScenarios.lua:79-80`).
**Prove it:**
- `tests/offline/home.spec.luau:36-75`: no home pays the old 10 min, Penthouse covers a spin-off, 2 h pays less than 8, Studio window is 2 h, never two steps, 3,000 random returns.
- `tests/offline/progression.spec.luau:59-73`: a Penthouse night pays any spin-off; at the cap a Studio night pays under 30% and a Loft under 60%.
- `tools/late_game.luau` and `tools/bas baseline diff` track `nightCover` (`tools/bas.luau:309-343`).
- No automated check for the `applySave` wiring or the HUD card.
**Gotchas:**
- The old formula at `SaveLoad.lua:187-190` is overwritten by the home rule at :209 whenever `Econ.Apt` has both `offline` and `ladder`. The 600 s cap is only a fallback.
- Time away starts at the last save. A normal leave saves at exit (`SiliconCore.server.lua:3975-3978`). After a crash it is the last autosave, up to 120 s older (`SaveLoad.lua:403-408`). The saved `rate` is the rate at that save.
- At the top of the Wafers blueprint both steps are the spin-off price (`SaveLoad.lua:206`). `Progression.ladder` instead wraps to HQ 2 after the spin-off (`Progression.lua:237`).
- `OFFLINE_RATE` (`Progression.lua:223`) and `AFK_RATE` (`RoomEconomy.lua:208`) are both 0.25 but separate. Change both or neither.
- `WelcomeDone` is only set after 12 s when no offline pay came (`HudClient.client.lua:910-913`). `TalentRevealClient` (:304), `NameClient` (:146) and `DailyClient` (:311) wait for it.
- The server adds the money first. The HUD subtracts `pendingOffline` from the shown cash until COLLECT (`HudClient.client.lua:927,476`). If the card cannot show for 45 s the money is released (:933-938).
- A Studio Play, stop, Play loop pays almost nothing, because `lastSeen` is only seconds old.
**Last verified:** 2026-10-09 80ce687
