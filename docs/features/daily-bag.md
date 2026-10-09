# Daily Reward and the Bag (items)
**What:** A 7 day streak gift pays cash once per UTC day. From day 2 it also drops an item into the bag. The bag holds five items, each with one job: 3x code, faster scooter, stop a headhunter, next hire rolls higher, next launch pays double. Investors and launches also give items.
**How a player reaches it:**
1. Ship the first app. The DAILY rail tile shows for a returning player, or at HQ 2 after the first drive downtown (`src/StarterPlayer/StarterPlayerScripts/DailyClient.client.lua:151-157`).
2. With a gift waiting, the card opens once by itself at a calm moment (`DailyClient.client.lua:300-325`). The tile also wiggles and shows a "!".
3. Tap CLAIM. The client fires `ClaimDaily` (:273). The server pays cash and grants the day's item (`src/ServerScriptService/DailyReward.lua:69-83`).
4. A "you got" card flies into the BAG tile (`src/StarterPlayer/StarterPlayerScripts/InventoryClient.client.lua:423-430`). Opening the bag fires `ItemsSeen` and clears the red count (:216).
5. Use an item: pick it in the bag and tap USE (fires `UseItem`, :204). Shortcuts: a COFFEE button beside WRITE CODE (:276-288) and a rescue button under the headhunter warning (:291-294).
**Files:**
- `src/ServerScriptService/DailyReward.lua`: `SECONDS` :26, `FLOOR` :27, `ITEMS` :30, `today` :34, `nextDay` :37, `amountFor` :47, `refresh` :53, `claim` :69, `init` :85 (re-checks every 60 s :92).
- `src/StarterPlayer/StarterPlayerScripts/DailyClient.client.lua`: gui `Daily` :44, rail tile :226, `nextGiftText` :160, claim click :264-277.
- `src/ServerScriptService/Inventory.lua`: `load` :36, `save` :49, `grant` :56, `use` :74, `codeMult` :115, `scooterBonus` :119, `launchMult` :123, `onHire` :132, `onLaunch` :143, `init` :153 (makes `ItemEvent`, `UseItem`, `ItemsSeen`).
- `src/ReplicatedStorage/Items.lua`: `LIST` :31 (ids `coffee`, `energy`, `noncompete`, `scout`, `frontpage`), `MAX` 99 :45, `encode` :48, `decode` :56, 3D icons `icon` :135.
- `src/StarterPlayer/StarterPlayerScripts/InventoryClient.client.lua`: BAG tile :48, gui `Bag` :56, `WHERE` text :35-41, boost rows :235, `setOpen` :212.
- Callers in `src/ServerScriptService/SiliconCore.server.lua`: `Econ.Daily` init :2687, `Econ.Inv` init :2724, `codeMult` :1320, `onHire` :1891, `launchMult` :3212, `onLaunch` :3215. Also `TalentDrop.lua:272, 828` (`scooterBonus`) and `SaveLoad.lua:391-392`.
**State:**
- Session: `s.dailyDay` (UTC day number), `s.streak` (0 to 7), `s.items` (id to count), `s.lastUse`, `s.gotFirstCoffee`.
- Attributes: `DailyReady`, `DailyStreak`, `DailyLast`, `DailyAmounts`, `DailyItems` (`DailyReward.lua:57-66`). `Items` as `coffee=2;energy=1`, `ItemsNew`, `BoostCode`, `BoostEnergy`, `ArmedScout`, `ArmedPress` (`Inventory.lua:1-12`).
- Saved: `dailyDay`, `streak` (`SaveLoad.lua:122-123`, clamped :355-356). Item counts only (:132, load :391).
- Not saved: boost timers, armed flags, `gotFirstCoffee`.
**Drive it:**
- `item <id>` puts one in the bag (`DevHook.lua:479`).
- `ship` sets `s.shipped` so a claim works (`DevHook.lua:53`). `scenario hq:5` then `scenario home:1` unlocks the tile (HQ 2 and `JrRes`, `SiliconCore.server.lua:1830`).
- Nothing resets `dailyDay` yet, so a second claim the same day is not testable. `wipe` deletes the whole save (`DevHook.lua:131`), so avoid it.
**Prove it:**
- `tests/offline/clock.spec.luau`: daily pay is 5 percent of the goal on day 1 up to 35 percent on day 7 (:57-63).
- `tests/offline/journey.spec.luau`: tip order launch, bag, index, ranks, daily (:122-132).
- `tests/notify_live_server.luau` fires an `ItemEvent` "got" card (coffee) to check the lane.
- No offline spec for `nextDay` or `Inventory.use`: both load game services or `Progression` at load.
**Gotchas:**
- The day is `os.time() / 86400`, so it turns at 00:00 UTC (`DailyReward.lua:34`). A missed day goes back to day 1. After day 7 it wraps to day 1 (:37-43).
- Pay is capped by `Progression.capWindfall("daily", ...)` against the next goal (`DailyReward.lua:47-51`). The card numbers change when the goal moves (`SiliconCore.server.lua:1968`).
- The item grant is in a `pcall`. If it fails the claim still counts (`DailyReward.lua:80-82`).
- Item id `coffee` is shown as "Cold Brew" in `Items.lua` and as "COFFEE" on the quick button (`InventoryClient.client.lua:284`).
- `InventoryClient` `WHERE` text is hard coded. Keep it in step with `DailyReward.ITEMS` and `Phone.lua:347-349`.
- A refused use is not consumed (`Inventory.lua:69, 83-107`). Use has a 0.4 s cooldown. Cold Brew stops stacking at 120 s ahead, Energy at 90 s.
- Armed Scout and Front Page are attributes, not saved. Leaving after arming loses an item that was already spent.
- Stale: `DailyClient.client.lua:34-35` says there is no rail tile and the phone opens the card. There is a DAILY tile (:226), and the `SVOpenDaily` event (:37) is never fired in `src`.
- Tips find `Rail.Column.BagButton` and `Rail.Column.DailyButton` by name (`Journey.lua:164, 173`). Do not rename them.
**Last verified:** 2026-10-09 287a211
