# The player loop (analytics and TELL US)
**What:** What real players do, sent to the Creator Dashboard: an onboarding funnel along the HQ ladder, a milestone per session for the core actions, every recruit run with its outcome, and every cash source and sink. Plus TELL US, an in-game box for a bug or an idea that lands in a DataStore you read in Studio. Analytics only records in published servers; Studio prints the same facts instead (`[FUNNEL]`, `[EVENT]`, `[MONEY]`).
**How a player reaches it:**
1. Nothing to do: playing sends it. The funnel's first step waits for the client's platform report, or 10 s (`src/ServerScriptService/Telemetry.lua:91`).
2. Ship the first app and the TELL US tile (pink, last on the rail) appears (`src/StarterPlayer/StarterPlayerScripts/FeedbackClient.client.lua:21-24`). Type up to 300 characters and tap SEND (:105). The server answers with one line (:120).
**Files:**
- `src/ServerScriptService/Telemetry.lua`: `FUNNEL` :40 (joined, play, first_code, first_ship, first_hire, hq_2 to hq_5, public, spinoff), money kinds `SHOP` / `TIMED` / `SUMMED` :57, `FLUSH_EVERY` 300 s :60, `flush` :84, `joined` :91, `step` :125, `reached` :152 (a returning player's furthest step), `event` :166, `mark` :186 (session milestone `m_<name>`), `money` :195, `carryStart` :207, `carryEnd` :213, `left` :218.
- Funnel steps are sent from `SiliconCore.server.lua`: the ladder at :2146, the backfill after load at :3874, `public` in `goPublic`, `spinoff` in `spinOff`. Income is summed at :3135.
- Recruit runs: `src/ServerScriptService/TalentDrop.lua` `endCarry` :439 (every end, with its outcome), `startCarry` :540, the poach :623.
- Money: one `Telemetry.money` call beside every cash change, in SiliconCore, Apartments, Cars, DailyReward, Phone, SaveLoad and Valley (the full list is what `tests/offline/telemetry.spec.luau` checks).
- `src/ServerScriptService/Feedback.lua`: `GAP` 60 s and 5 a session :20, `clean` :25 (pure), `key` :37, `receive` :44, `init` :71 (wired in `SiliconCore.server.lua:2809`), `latest` :82.
- `src/StarterPlayer/StarterPlayerScripts/FeedbackClient.client.lua`: the tile :21, the panel, the counter, SEND :105.
**State:**
- Dashboard: the onboarding funnel (once per user for life); custom events `m_recruit`, `m_chase`, `m_delivery`, `m_build`, `m_launch`, `m_room`, `m_rival`, `m_ten_minutes` (once per session, value = seconds in), `carry_start` (field `tier=`), `carry_end` (`tier=`, `out=`, value = seconds), `feedback`, `session_end`; economy events in currency `Cash` with the kind as the SKU.
- DataStore `SVFeedback_v1`: key `<unix time, 10 digits>_<userId>`, value `{ u, t, text, hq, wl, staff, spins, touch, place, studio }`.
**Drive it:**
- Read the feedback in Studio, in Play, SERVER datamodel: `game.ServerScriptService.SiliconCore.SVDev:Invoke("feedback", game.Players:GetPlayers()[1], 10)` (`DevHook.lua:511`). Studio entries say `studio = true`.
- Watch events in Studio: Output shows `[FUNNEL]`, `[EVENT]` and `[MONEY]` lines. A robot run (`dev-tools.md`) gives a full carry_start to carry_end.
- On the dashboard: Creator Hub, the experience, Analytics: Funnels, Economy, Custom Events. Charts fill daily; "View Events" shows calls within minutes.
**Prove it:**
- `tests/offline/telemetry.spec.luau`: the funnel order, every step name and money kind the code sends, and that no cash change goes unlogged.
- `tests/offline/feedback.spec.luau`: junk refused, the 300-character cut never splits a character, keys sort by time.
- Live on 9 Oct (Wilz): all 11 steps logged in order on join; a skilled run logged carry_start, m_recruit, m_chase, the hire sink, carry_end signed, m_delivery; a floor build logged the floor sink, m_build, hq_5; leaving flushed summed income and session_end; TELL US saved one message and refused a second inside a minute.
**Gotchas:**
- A funnel step that can come in any order lies: Roblox completes every earlier step when a later one arrives. Only add steps the game forces in order. The old `first_wing`, `first_product`, `first_rival` and `ten_minutes` became milestones for that reason (9 Oct). Read the funnel from the v2 publish date on.
- Custom fields keep about 20 values each. Fields here are platform, tier and outcome. Never put a name, an amount or free text in one.
- AnalyticsService allows about 120 + 20 per player calls a minute. Anything that happens every second is summed (income, code taps).
- TELL US text is shown to no other player, so it is stored as typed. If it is ever shown to anyone else, it must go through `TextService` first.
- Each feedback message is a DataStore write out of the shared budget every save comes from; keep the 60 s gap.
- Not built: the weekly routine that reads the dashboard needs the Analytics Query API and an Open Cloud key (Phase 3).

**Last verified:** 2026-10-10 a7700e2
