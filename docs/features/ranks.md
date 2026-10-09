# Ranks (leaderboards: this week and all time)
**What:** Two boards of company value (lifetime valuation, so spending never lowers it). ALL TIME lists every company from $1,000. THIS WEEK lists value gained since Monday 00:00 UTC, so a new player can reach the top 10. Five AI rival companies fill the boards, wear an AI tag, and keep a board from being empty.
**How a player reaches it:**
1. Reach HQ 2. A round trophy button appears top right (`src/StarterPlayer/StarterPlayerScripts/RanksClient.client.lua:34-43, 248`). It hides while any menu is open.
2. Tap the trophy. The panel opens at once from cached data, then asks the server (`setOpen` :225, `fetch` :213).
3. `GetRanks:InvokeServer()` returns the cached boards plus your own row. It repeats every 20 s while open (:240-244). The server never reads a DataStore for this call.
4. Behind it, every 60 s the server writes each player's value (only if changed), reads both boards, and caches them (`src/ServerScriptService/Ranks.lua:36, 192-250`).
5. The first time each week you are in the weekly top 10, you get a toast (`Ranks.lua:244-246`).
6. A first-time tip points at the trophy (`src/ServerScriptService/Journey.lua:170`).
**Files:**
- `src/ServerScriptService/Ranks.lua`: constants :33-37, `weekId` :40, `rollWeek` :46, `merge` :55, `mine` :79, `newBoard` :114 (`nameFor` :117, `push` :132, `read` :148, `refresh` :158), `init` :192 (`GetRanks` :202), `pushPlayer` :218.
- `src/StarterPlayer/StarterPlayerScripts/RanksClient.client.lua`: corner button :34-43, panel :60, `render` :166, `fetch` :213, `setOpen` :225, `sync` :248.
- Wiring in `src/ServerScriptService/SiliconCore.server.lua`: stores :553-555, `pushTicker` :3558 (hands off to `Ranks.pushPlayer`), road board `refreshBoard` :3622, `Econ.Ranks` init :3671-3692 (rivals closure).
- Save fields: `src/ServerScriptService/SaveLoad.lua:91-92` (write), `:175-176` (load).
**State:**
- Session: `s.valuation`, `s.weekId`, `s.weekBase` (value at week start), `s.ranksToastWeek` (not saved, so a rejoin can toast again).
- Saved: `weekId`, `weekBase`. `Ranks.rollWeek` resets a stale or impossible base (`Ranks.lua:46`).
- DataStores: ordered `SVTicker_v1` (key userId, value = valuation), ordered `SVWeek_<weekId>` (key userId, value = gain), plain `SVNames_v1` for names.
- Server memory: `board.cache = { all, week, updated, weekId, weekEnds, stale }`, plus last-written tables that skip unchanged writes.
- Remote: `SVRemotes.GetRanks` (RemoteFunction). Reply: `all`, `week`, `updated`, `stale`, `weekEnds`, `now`, `mine = { all, week }`, or `{ pending = true }` before the first read (`Ranks.lua:205-216`).
**Drive it:**
- `valuation <n>` sets `s.valuation` (`DevHook.lua:184`). Side effect: at 250,000 or more with a name it runs the IPO check and sends a world toast (`SiliconCore.server.lua:3547-3555`).
- `name <s>` changes the live name shown on your row (`DevHook.lua:181`).
- Wait up to 60 s for the board to refresh. There is no SVDev action to force a refresh yet. `scenario hq:5` reaches HQ 2 for the button.
- Studio Edit datamodel: run `tests/ranks_spec.luau` to test the rules with fake stores.
**Prove it:**
- `tests/ranks_spec.luau` (Studio, Edit datamodel, "PASS 6 groups"): week start is Monday, `rollWeek`, `merge`, `mine`, a board on fake stores, a failed read serves the last good boards as stale. See `README.md:37`.
- `tests/offline/journey.spec.luau`: the RANKS tip comes after BAG and INDEX (:122-132).
- No automated check for the panel itself. `SVCheck` screen pass and `tools/ui_audit.luau` work if the panel is open.
**Gotchas:**
- The rank number is lifetime valuation. `s.valuation` is only ever added to (`SiliconCore.server.lua:3095, 3205, 3499`, `Valley.lua:140`), so spending and spin-offs never lower it (`Ranks.lua:10-12`).
- Budget: one write per board per player per minute, only on change, and one read per board per server per minute (`Ranks.lua:20-22`). Do not add a per-tap DataStore call.
- Only the top 25 are listed (`Ranks.TOP` :33). Below that you get "needTop", not an exact rank (`Ranks.lua:106-107`).
- A company under $1,000 is unranked and not written (`Ranks.lua:83, 135`).
- The weekly AI rival value is its all-time value times the share of the week gone, so rivals climb all week (`Ranks.lua:165`).
- `SVWeek_<id>` is a new store every week. Nothing deletes old ones.
- Names: 10 new lookups per refresh. Unknown ones show "Startup #" plus 4 digits (`Ranks.lua:37, 128`). A company with no name shows that.
- `Econ.Ranks` is wired late in `SiliconCore` because its rivals closure needs locals defined just above (`SiliconCore.server.lua:3671-3675`). Do not move it up.
- `RanksClient` header says the button is on the left rail. It was moved top right in v5 (`RanksClient.client.lua:34-43`).
- The Journey tip finds `RanksCorner.RanksButton` by name (`Journey.lua:170`). Renaming either breaks the tip.
- If `Ranks` fails to load, the road board and `pushTicker` fall back to the old IPO-only ticker (`SiliconCore.server.lua:3641, 3560`).
**Last verified:** 2026-10-09 287a211
