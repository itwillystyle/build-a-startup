# UI, HUD, Goal Guide, Intro, Naming and Music
**What:** One shared look (`UIKit`), one referee for pop-ups (`Notify`), one camera tool (`Cine`), and the first-minute screens built on them: intro flyover, goal card, one-time button tips, the "name your company" box and the music button. `Palette` and `SVStyle` are world colour rules, not UI colours. `Sfx` holds world and vehicle sound ids.
**How a player reaches it:**
1. Join. `MenuClient` fires `MenuDone` once (`MenuClient.client.lua:19`). The server sets the attribute (`SiliconCore.server.lua:3955-3958`). HUD guis wait for it.
2. `IntroClient` waits for `MenuDone` (:144), then `Cine.play` flies to the laptop (:290). Returning players get a short "WELCOME BACK" shot (:152-160).
3. `GuideClient` draws the goal the server picks (`GuideClient.client.lua:554-621`).
4. After the first app ships and the first hire, the server fires `AskName` (`SiliconCore.server.lua:3906`). `NameClient` shows the box through `Notify` (:159). SAVE fires `SetName` (:125-136). LATER sends an empty string (:119-123).
5. The server picks a button tip (`SiliconCore.server.lua:1822-1831`). `CoachClient` draws it after 1.5 s of calm (:231). GOT IT fires `CoachSeen` (:113).
6. `MusicClient` puts a round button top right (:60-64). A tap flips `MenuMuted` and fires `SetMuted` (:108-113).
**Files:**
- `src/ReplicatedStorage/UIKit.lua`: colours :23-58, `button` :152, `card` :307, `menu` :1013, `railButton` :490, `fitMenu` :750, `sfx` :904, `MENUS` :1113, `menuOpen` :1118, `solo` :1214, `autoScale` :1295.
- `src/ReplicatedStorage/Notify.lua`: `Notify.show` :269, `hold`, `reserveTop` :296, `topY` :301, `followTop` :326, `busy` :357, `toast` :412. Rules in the header :1-22.
- `src/ReplicatedStorage/Cine.lua`: `play` :165, `fade` :114, `busy` :112, `handBack` :157.
- `src/ReplicatedStorage/Palette.lua`: `ANCHORS` :43, `compliant` :170, `map` :199, `author` :275 (the one rule every part builder applies: a named Color maps into the palette, no Color gets the palette's default grey), `enforce` :286, `watch` :332.
- `src/ReplicatedStorage/PaletteLoad.lua`: how the server's part builders get Palette. It returns Palette, or `false` (one warning) if Palette failed to load, so each caller's `if Pal then` still builds the world unmapped.
- `src/ReplicatedStorage/SVStyle.lua`: `scan` :131, `run` :287. `src/ReplicatedStorage/StyleBaseline.lua`: the counts it must not exceed.
- `src/ReplicatedStorage/Sfx.lua`: `ID` :22, `CAR` :71, `ROOM` :88, `emitter` :100, `play` :120.
- `src/StarterPlayer/StarterPlayerScripts/MenuClient.client.lua`: only the `MenuDone` handshake.
- `src/StarterPlayer/StarterPlayerScripts/GuideClient.client.lua`: goal card, world pin, edge arrow. Dismiss attribute :267.
- `src/StarterPlayer/StarterPlayerScripts/CoachClient.client.lua`: `place` :57, `build` :117, loop :220-233.
- `src/StarterPlayer/StarterPlayerScripts/IntroClient.client.lua`: `runIntro` :133, ghost tower and neighbour shot :175-260.
- `src/StarterPlayer/StarterPlayerScripts/NameClient.client.lua`: gui `CompanyName` :31, `suggest` :59.
- `src/StarterPlayer/StarterPlayerScripts/MusicClient.client.lua`: five tracks :28-34, volume 0.16 :35, `play` :84.
- Server half of naming: `SiliconCore.server.lua` `cleanName` :3144, `tickerOf` :3157, `SetName` handler :3163.
**State:**
- Server attributes: `MenuDone`, `Objective`, `ObjectiveText`, `ObjectivePos`, `ObjectiveSub`, `ObjectiveCost` (`SiliconCore.server.lua:1844-1849`), `Milestone*`, `CoachTip`, `CoachTitle`, `CoachBody`, `CoachTarget` (:1824-1830).
- Client attributes: `NamingOpen` (`NameClient.client.lua:39`), `MenuMuted`, `MusicTrack`, `MusicTrackName`, `MusicTrackCount`, `GuideDismissed`.
- Session: `s.name`, `s.ticker`, `s.nameSkipped` (not saved), `s.tips`, `s.muted`.
- Saved: `name` (`SaveLoad.lua:89`), `tips` (:136), `muted` (:121). Name is also in DataStore `SVNames_v1`, key = userId (`SiliconCore.server.lua:560, 3185`).
**Drive it:**
- `name <s>` sets name, ticker and sign with no box (`DevHook.lua:181-183`).
- None opens the naming box, a tip or the flyover. `dev:Invoke("scenario", p, "ready")` hires one person, which may start the name ask on a fresh save (not verified).
- Studio SERVER datamodel, likely works, not run: `game.ReplicatedStorage.SVRemotes.AskName:FireClient(p, "")`. See how `tests/notify_live_server.luau` fires remotes.
**Prove it:**
- `tests/notify_spec.luau` (Studio Edit datamodel, "PASS 17 groups"): the lane rules against fake elements.
- `tests/notify_live_server.luau` plus `tests/notify_live_client.luau` (Play): fires 7 events, client samples how many cards share a lane.
- `SVCheck` screen pass `checkUI` (`SVCheck.lua:125`), `tools/ui_audit.luau`, `tools/ui_overlap.luau`, `tools/algo_check.luau` (Play CLIENT). `SVStyle.run()` for colours.
- No automated check for `Cine`, `IntroClient`, `NameClient`, `CoachClient`, `MusicClient`.
**Gotchas:**
- A new menu must be added to `UIKit.MENUS` (`UIKit.lua:1113`) with its ScreenGui name, or `solo`, `menuOpen` and `Notify` will not see it open.
- Every transient asks `Notify.show` first. One card per lane. A card that never says done is freed after `MAX_HOLD` (`Notify.lua:29`).
- Top lane cards must use `Notify.followTop` (:326). `GuideClient` reports the quest card bottom every 0.4 s (`GuideClient.client.lua:809-822`).
- `Cine.play` disables every enabled ScreenGui and the prompts, then re-enables only non-menu guis (`Cine.lua:173-182, 228-231`). It returns false if one is already playing (:168).
- `UIKit.autoScale` adds a `UIScale` named `SVAutoScale` to every top-level child of every ScreenGui (:1246-1316). A frame honours one `UIScale`, so `popIn` and `fitMenu` share it (:1150-1152).
- Tips find buttons by path, such as `Rail.Column.BagButton` (`Journey.lua:156-175`). Rename a button and its tip never shows (`CoachClient.client.lua:29-36`).
- Naming: 20 characters, filtered, a `#` means refused (`SiliconCore.server.lua:3144-3155`). After 25 s idle the client submits the suggested name (`NameClient.client.lua:165`). The header says "closes itself", the code submits.
- Saved mute probably does not return. The server sends `MenuStats` with `muted` (`SiliconCore.server.lua:3844-3847`), but no client listens and nothing sets `MenuMuted` from it. Not run.
- `MusicClient` header mentions a SETTINGS picker. `MenuClient` no longer has one, and nothing else sets `MusicTrack`.
- The colour rule lives in `Palette.compliant`. `SVStyle.classify` calls it (`SVStyle.lua:71-77`). Change it in `Palette` only.
- Two sound tables: `UIKit.SOUNDS` (:892) for UI, `Sfx.ID` for the world. A bad id plays silence (`Sfx.lua:5-8`).
- Security (9 Oct exploit check): `SetName` only works while the company has no name, one attempt in flight and one a second (`SiliconCore.server.lua:3174`). Each attempt costs a text filter and a DataStore write from the server's shared budget; spammed renames drained it (280 throttled writes) before the fix. Refusal popups are capped at one per anchor every 0.3 s (`popup`, `SiliconCore.server.lua:426`).
**Last verified:** 2026-10-09 d6a64f6
