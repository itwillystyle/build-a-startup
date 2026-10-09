# Hiring, talent, staff rigs and the Index
**What:** The HIRE pad only gives the first intern, free. Every later hire is a recruit run on the street. `hire()` in `SiliconCore` signs the person, rolls their talent once (Regular, Skilled, Star, Genius, Unicorn), builds a real R15 rig with `StaffRig`, and seats them. Rare hires get a reveal card (`TalentRevealClient`) and fill a 5 by 5 collection (`IndexClient`). `StaffAnimClient` draws all staff motion on each player's machine. Seniority (Intern to Lead) is separate from talent: it grows with seated time.
**How a player reaches it:**
1. Ship the first app, then step on the HIRE pad: "HIRE YOUR FIRST INTERN FREE" (`src/ServerScriptService/SiliconCore.server.lua:1520`, pad handler :2845-2853).
2. After that the pad reads "HIRING HAPPENS ON THE STREET" (:1523). Walk east on the sidewalk to a candidate and use the "Recruit" prompt (`src/ServerScriptService/TalentDrop.lua:216-226`). Tiers: WALK-IN, SKILLED, STAR (HQ 2), GENIUS (HQ 3) (`RoomEconomy.lua:353-358`).
3. Carry them home before the timer ends while a headhunter chases (TalentDrop; see chase.md). At your lot `stepCarry` calls `hire(player, plot, {floor, fee, luck, kind})` (`TalentDrop.lua:546`).
4. Skilled or better: the TalentReveal card, a screen glow and a halo on Star and up. A new Index entry flies to the INDEX button (`TalentRevealClient.client.lua:257,191`).
5. INDEX button on the right rail opens the grid. Q closes it (`IndexClient.client.lua:274-288`).
**Files:**
- `src/ServerScriptService/SiliconCore.server.lua`: `hire` :1865-1962, `spawnStaff` :1465, `assignDesks` :1429, `updateHirePad` :1497, `CFG.TALENT.roll` :294, `talentMultOf` :302, remote `TalentReveal` :530, `Econ.publishIndex` :2649, `IndexSeen` :2655.
- `src/ServerScriptService/StaffRig.lua`: `ROLES` :85, avatar template prewarm :422, `build` :505, `setTalent` :542, `setTitle` :590, `say` :598, `cheer` :637, `setSeated` :659, `animate` :826. Server builds and places only.
- `src/ServerScriptService/CoreConfig.lua`: `TALENT` odds and multipliers :80-86, `TIER_RATE`/`TIER_TITLE` :77-78, `PROMOTE_EVERY` :79, `ROLE_ORDER` :27.
- `src/ServerScriptService/RoomEconomy.lua`: `FIT` :64, `TIERS` :353, `INDEX_*` :383-385, `indexLines` :386, `indexMult` :401.
- `src/StarterPlayer/StarterPlayerScripts/StaffAnimClient.client.lua`: `add` :146, `wander` :210, Heartbeat loop :338. Typing, glances, wander, cheer, hunter anims.
- `src/StarterPlayer/StarterPlayerScripts/TalentRevealClient.client.lua`: `showCard` :257, listener :300.
- `src/StarterPlayer/StarterPlayerScripts/IndexClient.client.lua`: `refresh` :229, `setOpen` :274.
**State:**
- `s.rigs[i] = { rig, hum, tier, seatedTime, talent, who = {role, seed}, seated, room, fit, eff, seg, dept, home }` (`SiliconCore.server.lua:1477-1478`, `assignDesks` :1446-1458). Also `s.staff`, `s.hireCost`, `s.index` (set of `"role:talent"`), `s.alumni`.
- Player attributes: `IndexData` (comma list), `IndexNew` (badge count), `VibeLuck`. Rig attributes: `Role`, `PersonName`, `Talent`, `TalentName`, `Avatar`, `Seated`, `Wander`, `CheerAt`. Rigs carry tag `SVStaff`.
- Saved: `staff`, `tiers[]`, `talents[]`, `people[]` (`"role:seed"`), `index[]` (`src/ServerScriptService/SaveLoad.lua:99-119`). Load rebuilds staff one by one (:319-340).
**Drive it:**
- `dev:Invoke("recruit", p, 1-4)` starts a recruit through the real path (`DevHook.lua:501`). You still carry them to the lot. `"chase:skilled|star|genius"` does setup, teleport and recruit (`DevScenarios.lua:188-215`).
- `dev:Invoke("hire", p)` works only for the first intern (`DevHook.lua:171`).
- `dev:Invoke("talent", p, 1-5)` sets the last hire's talent, no card (`DevHook.lua:90`). `"tier"` sets the first hire's seniority (:155).
- `dev:Invoke("rolls", p, 20000)` rolls the talent n times and returns counts (`DevHook.lua:472`).
- `tests/notify_live_server.luau` fires a fake Genius reveal to see the card.
**Prove it:**
- No offline spec covers `hire`, `StaffRig` or the three clients. `momentum.spec.luau` covers the momentum a hire pays.
- SVDev `rolls` checks the odds (1 in 5, 25, 150, 1491 from `CoreConfig.lua:81-85`).
- `tests/smoke_core.luau` prints saved `talents`, `people`, `index` and `tiers` (:24, :70).
- Funnel step `first_hire` (`SiliconCore.server.lua:1887`).
**Gotchas:**
- The pad refuses a second hire: "Recruit on the street" (:1870-1873). "No desks free" when `s.staff >= capacityOf` (:1875).
- Talent is `max(roll, recruit.floor)`. The tier they wore is a floor (:1888-1889). The card says "Signed from the street" for a floor, "Lucky! 1 in N" for a roll above it (`TalentRevealClient.client.lua:271`).
- Draws run rarest first so a Unicorn is exactly 1 in 1491 (:290). A Scout Report can raise talent after the roll (:1891).
- `recruit` refuses unless you own the plot, HQ meets the tier, no carry is active, you shipped, staff >= 1, a seat is free and cash >= fee (`TalentDrop.lua:475-496`). It has no distance check, so raw SVDev `recruit` starts the hunter far from you (`DevScenarios.lua:201`).
- Genius floor sets `s.jr.genius` for the HQ 3 task (:1890).
- The reveal waits for `WelcomeDone` up to 25 s (`TalentRevealClient.client.lua:301-304`). Right after a rejoin it can lag.
- Index keys are `role:1-5`. Load keeps only keys that match `^(%a+):(%d)$` and a known role (`SaveLoad.lua:313-315`). Spin-off does not clear `s.index`.
- A person's look comes from a seed. New hires use their staff number unless `who` is given (`SiliconCore.server.lua:1468-1472`), so a rejoin keeps faces only through `people[]`.
- Avatar templates build at server start. A hire in the first seconds waits up to 12 s, then falls back to the block rig (`StaffRig.lua:439-447,505-515`).
- Do not move motion back to the server. The header measured 246.5 KB/s per player when it was there (`StaffRig.lua:29-33`).
- A kept spin-off hire returns as an Intern (`spawnStaff` sets `tier = 1`, :1477).
- `StaffAnimClient.client.lua:47` says the run animation id is empty. `HUNTER_ANIM.run` is set (:52-53). The comment is stale.
**Last verified:** 2026-10-09 cf0adc8
