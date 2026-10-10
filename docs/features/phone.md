# Phone (AI investor texts, term sheets, Series A, voice calls)
**What:** A phone on the left rail. AI investors text you, ask three questions, then offer money (a term sheet). You TAKE, PUSH FOR MORE, or PASS. The game scores your answers; the model only writes the words. At HQ 4 a big investor sends a Series A worth about 3x. The phone also rings other players for voice calls.
**How a player reaches it:**
1. Ship the first app. The PHONE tile shows at HQ 2, or at once for a returning player (`src/StarterPlayer/StarterPlayerScripts/PhoneClient.client.lua:1290-1299`).
2. At HQ 2 the first investor texts about 25 s later (`src/ServerScriptService/Phone.lua:674`). A banner drops in the top lane (`PhoneClient.client.lua:954`). Tap it or the tile.
3. Pick one of three replies, or type your own, three times (`Phone.lua:384`). The investor answers each time.
4. A term sheet arrives. TAKE pays the cash and maybe an item (`takeOffer` `Phone.lua:357`). PUSH may pay 1.5x or walk (`:616-634`). PASS ends it.
5. At HQ 4 the quest says "Close your Series A" (`src/ServerScriptService/Journey.lua:99-101`). The server then calls `Phone.seriesA` (`SiliconCore.server.lua:1657-1661`).
6. Next investor: 240 to 360 s after a thread closes (`Phone.lua:324`).
**Files:**
- `src/ServerScriptService/Phone.lua`: `PERSONAS` :40, `THESIS` :52, `facts` :124, `sanitize` :194, `aiReact` :223, `makeOffer` :336, `respond` :371, `reply` :397, `startThread` :431, `startCall` :502, `answer` :530, `init` :560, `seriesA` :698, `notice` :709, dev hooks :726-757.
- `src/StarterPlayer/StarterPlayerScripts/PhoneClient.client.lua`: rail tile :68, apps Texts :218 and Calls :235, `setOpen` :855, `showBanner` :954, ring card :968, `upsert` :1142, event handler :1182, `refreshBadge` :1290.
- Wiring: `SiliconCore.server.lua` `Econ.Phone` init :2762-2780 (gives `session`, `nextGoal`, `grant`, `onSeriesA`).
- Remotes (made in `Phone.init`): `PhoneEvent` server to client, `PhoneAction` client to server (`Phone.lua:579-584`). Actions: `reply`, `text`, `offer`, `read`, `voice`, `call`, `answer`, `hangup` (:595-645).
- Related, not in this page: `src/ServerScriptService/VoiceCheck.lua` (voice state), `Apartments.lua:517` (front desk text through `Phone.notice`).
**State:**
- In memory only, per player: threads (up to 6), active thread, `nextAt` (`Phone.lua:259`, :446). Not saved.
- Session: `s.board` (Boardroom floors, makes investors keener, max 2, `:438`), `s.jr.seriesA`, `s.seriesAt`.
- Player attributes: `PhoneUnread`, `Company`, `HasVoice`, `InCall`, `CallSince`.
- Saved: only the Series A flag, inside `jr` (`SaveLoad.lua:137`). A spin-off clears it (`SiliconCore.server.lua:2998`). Item gifts go to the bag (see daily-bag.md).
**Drive it:**
- `phone`: returns the live thread (id, firm, status, offer). Studio only (`DevHook.lua:160`, `Phone.lua:726`).
- `phoneoffer <n>`: sets interest n (default 8) and makes the term sheet through the real `makeOffer` (`DevHook.lua:164`, `Phone.lua:734`). Needs a live thread.
- To get a thread: `dev:Invoke("scenario", p, "ready")` then `"hq:5"` (stage 2). To get Series A: `"hq:13"` (stage 4, `Wafers.lua:166-170`). Waiting for the clock is still needed.
- `item <id>` gives a gift item to check the reward path (`DevHook.lua:479`).
**Prove it:**
- `tests/offline/journey.spec.luau`: HQ 4 gives the `seriesa` task (:114), HQ 5 order (:81, :96).
- `tests/offline/clock.spec.luau`: offer caps for `phone`, `push`, `series`, `seriesPush` (:35-52).
- `tests/notify_live_server.luau` sends a fake investor text so you can watch the banner lane.
- No test calls `Phone._test` (:755). No automated check for replies, offers or calls.
**Gotchas:**
- Both headers are stale on apps. `PhoneClient` header lists REWARDS, but the Daily app is gone (`PhoneClient.client.lua:238`). `Phone.lua` says "Two apps": Texts and Calls.
- `Phone.snapshot` (:713) is never called, and the comment says the client asks on join. No remote asks. A rejoin has no thread history. Unverified in play.
- Dev hooks return nil outside Studio (`Phone.lua:726-749`).
- Typed replies are scored on the raw text, but the filtered text is shown. If the filter fails the reply is dropped (`Phone.lua:406-425`).
- Model text is dropped if it has a digit, `$`, a question, or "as an ai" (`Phone.lua:194-216`). Then a scripted line is used. A bucket of 20 calls refills 30 a minute (:184-191). The wait is 4 s (:253).
- Offers are capped by `Progression.capWindfall` against the next goal (`Phone.lua:331`, `Progression.lua:59`, `capWindfall` :92). Caps: phone 12 percent, push 18, series 25, series push 35. No goal means no cap.
- Series A retries every 90 s until a deal and never stacks (`SiliconCore.server.lua:1657`, `Phone.lua:698-707`). It waits 12 s after an HQ level-up so it will not hit the banner.
- `PhoneAction` drops any action sooner than 0.25 s after the last (`Phone.lua:590`).
- Calls need `HasVoice` on both players, a 25 s ring, and a 45 s cooldown after a decline (`Phone.lua:502-529`, :469).
- Investors wear an AI badge. Scripted notices do not (`PhoneClient.client.lua:255-275`).
- Security (9 Oct exploit check): a typed reply marks the thread busy BEFORE the text filter yields, so a second reply sent during the yield cannot count twice (`Phone.lua:412`).
**Last verified:** 2026-10-09 80ce687
