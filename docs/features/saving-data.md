# Saving, DataStores, telemetry and voice report
**What:** `SaveLoad` writes one record per player to the DataStore `SVSave_v1` and reads it on join. It saves every 120 s, on leave and on server close. Other stores hold the leaderboards (`SVTicker_v1`, `SVWeek_<id>`) and company names (`SVNames_v1`). `Telemetry`, `VoiceCheck` and `ClientInfoClient` save nothing. Telemetry sends funnel steps to Roblox Analytics. `VoiceCheck` publishes a voice status line. `ClientInfoClient` reports touch or desktop once.
**How a player reaches it:** Invisible. Join: `onJoin` calls `SaveLoad.loadOnce` (`src/ServerScriptService/SiliconCore.server.lua:3820`). Play: autosave loop (`src/ServerScriptService/SaveLoad.lua:400-405`). Leave: `PlayerRemoving` runs `Telemetry.left`, `saveNow`, `pushTicker` (`SiliconCore.server.lua:3919-3923`). Server close: `BindToClose` (`SaveLoad.lua:396`). Typing a company name writes `SVNames_v1` (:3164). RANKS and the Valley Exchange board read the leaderboards.
**Files:**
- `src/ServerScriptService/SaveLoad.lua`: `serialize` :60, `saveNow` :143, `clampInt` :158, `applySave` :163, `loadOnce` :375. Wired at `SiliconCore.server.lua:3755`.
- `src/ServerScriptService/SiliconCore.server.lua`: stores created :552-557, `loaded`/`loading` :558-559, `cleanName` :3132, `setName` :3151, `pushTicker` :3562, `refreshBoard` :3628, Ranks wiring :3681-3699.
- `src/ServerScriptService/Ranks.lua`: `weekId` :43, `push` :135 (all-time write :138-140, week write :141-147), `read` :151, `refresh` :161, `init` :195, store names :197-198.
- `src/ServerScriptService/Telemetry.lua`: `FUNNEL` :32, `joined` :52, `platform` :72, `step` :79, `event` :108, `left` :124.
- `src/ServerScriptService/VoiceCheck.lua`: `report` :96, `init` :132. Started by `Phone.init` (`src/ServerScriptService/Phone.lua:565-572`).
- `src/StarterPlayer/StarterPlayerScripts/ClientInfoClient.client.lua:16-17`: sends `TouchEnabled and not KeyboardEnabled`. Server: `SiliconCore.server.lua:3941-3946`.
**State:**
- DataStore `SVSave_v1` (normal store, key `tostring(UserId)`). The record: `v, layout, cash, hq, wings, wl, wd, rec, bp, placed, staff, shipped, name, valuation, weekId, weekBase, ipo, launches, rl, mo, rate, lastSeen, tiers, talents, index, people, playtime, muted, dailyDay, streak, alumni, work, spinoffs, hqPath, earned, items, apt, vipDay, jr, tips, listed, cars, car` (`SaveLoad.lua:76-140`). Studio plays as Wilz, so the key is `1688749216` (`DevScenarios.lua:34`).
- `SVTicker_v1` (ordered): key UserId, value floor(valuation), from $1,000 up. Written by `Ranks` `push` (`Ranks.lua:138-140`). Old path `pushTicker` runs only if Ranks failed to load (`SiliconCore.server.lua:3562-3572`).
- `SVNames_v1` (normal): key UserId, value the company name. Written on `SetName` only.
- `SVWeek_<weekId>` (ordered, one per week): key UserId, value valuation gained this week. Weeks start Monday 00:00 UTC (`Ranks.lua:43`, `push` :141-147).
- `SVSnap_v1` (normal): test snapshots `{ at, rec }` of `SVSave_v1`. Test accounts in Studio only (`DevScenarios.lua:35,45-47,58-70`).
- Session: `loaded[userId]` true only after a good read. Attributes: `Returning`, `Touch`, `VoiceState`, `HasVoice` (set from the client, `Phone.lua:636`).
**Drive it:** `dev:Invoke("save", p)` forces a save (`DevHook.lua:100`). `"peek"` returns the stored record (:128). `"wipe"` deletes it (:131). `dev:Invoke("scenario", p, "snapshot")` copies it to `SVSnap_v1` (`DevScenarios.lua:58`). After Play stops, in EDIT: `require(game.ServerScriptService.DevScenarios).restore(1688749216)` (:72). Check a restore with `require(game.ServerScriptService.DevScenarios).compareSnapshot(1688749216)`, which returns `{ ok, fields, differs }` (`DevScenarios.lua:99`). No action forces a load.
**Prove it:**
- `tests/ranks_spec.luau`: Ranks rules and board against fake stores, in the Edit datamodel (header :1).
- Pure sanitizers have specs: `journey.spec.luau:170` (flags and tips), `momentum.spec.luau:56` (a crafted save cannot mint a discount), `home.spec.luau:90` (keeper slots).
- `tests/smoke_core.luau:63-77` saves, peeks and prints the record keys. Diff before and after a refactor.
- Telemetry prints `[FUNNEL]` and `[LEFT]` lines in Studio (`Telemetry.lua:96,130`). No automated check for the `serialize` to `applySave` round trip.
**Gotchas:**
- The file header says "60 s autosave" (`SaveLoad.lua:2`). The loop waits 120 (:402).
- A failed read never saves, so a veteran is never stomped by a blank (`SaveLoad.lua:382,387`). A player with no record reads fine and can save.
- `saveNow` returns true even when its guard skipped the write. The guard refuses a record whose `lastSeen` is older than the stored one (:147-155). SVDev `save` then says "saved".
- That guard is why `restore` sets `lastSeen = os.time()` (`DevScenarios.lua:79-80`). Restore must run after Play stops, because the stop's save-on-leave overwrites it (:18-19).
- Compare saves with `compareSnapshot`, not two JSON strings: key order is not stable (`DevScenarios.lua:86-88`).
- `wipe` has no test-account check (`DevHook.lua:131-133`). Only `scenario` does. It deletes whichever account is playing.
- Names are filtered and a name containing `#` is refused (`SiliconCore.server.lua:3132-3142`).
- The onboarding funnel keeps only a user's first time at each step. Studio sends nothing to the dashboard (`Telemetry.lua:16-22`). Step 1 waits for `ClientInfo` or 10 s (:56-63).
- A tablet with a keyboard counts as desktop (`ClientInfoClient.client.lua:1-8`).
- Studio cannot test voice. The mic is always "not recording" there (`VoiceCheck.lua:27-33`). `VoiceCheck` only reads and changes nothing.
**Last verified:** 2026-10-09 f4cf91e
