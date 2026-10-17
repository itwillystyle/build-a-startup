# Client loop (clients at the door, hold to code, GIVE, get paid)
**What:** The core loop since 16 Oct. Clients walk up and ask for an app. You hold WRITE CODE at your laptop to code it, carry it to them and press GIVE. They open it, rate it in stars (speed), and pay; you also get a tip for 2-3 stars. Seated coders serve clients by themselves (slower than you). From the lobby on, clients queue at a reception desk in the middle of the lobby. Rules are pure in `Clients.lua` (offline-tested). `ClientsServer.lua` is the world (rigs, desk, bubbles, prompts, pay). `HudClient` draws the button, `ClientFxClient` the payout. Spec: `silicon-startup/docs/superpowers/specs/2026-10-16-client-loop-design.md`. Mocks Luke picked: 1A/2C/3A/3B/4A (16 Oct), then 1A desk, 2A GIVE + stars, 3A tiers (17 Oct, `silicon-startup/ui/2026-10-17-client-counter/`).
**How a player reaches it:**
1. Join a new save. The first client knocks and the garage door rolls up for them (`ClientsServer.start` :479, `core.openDoor`). The goal line says what to do (`Clients.goal` `Clients.lua:232`, read by `refreshObjective` `SiliconCore.server.lua:1648-1662`). The order: the tutorial (code the to-do app, take it to your client); with nobody hired, "Too busy! Hire a coder" once 2 clients wait or after `TUNE.HIRE_AFTER` (4) clients served, even if nobody waits; with staff >= 1 at level 1, "Upgrade your HQ" when the garage is full and busy or the upgrade is affordable (the HQ only builds with someone hired); from the lobby, "Recruit on the street" while a seat is free, until recruiting is taught (2 staff, or the first street pickup, `s.recruitTried`). Nothing else: Journey decides.
2. Hold WRITE CODE (HUD, `HudClient.client.lua:254,477`) or the laptop prompt within 12 studs of the laptop (`LAPTOP_RANGE` :25). The button fills (CodeProgress). When done you carry the app (CarryingApp); the button turns blue "GO TO CLIENT".
3. Walk within 10 studs of that client (`HAND_RANGE` :26). The button turns gold "GIVE" (CanGive) and E triggers the GivePrompt. Press it (`api.give` :622, remote `GiveApp` :698). Walking up alone does nothing.
4. The app flies over, they open it, 1-3 stars pop, then +$ and +TIP (`ClientFxClient.client.lua`). The first client gets the SHIPPED! stamp and 5x pay instead (3B; `TUNE.FLOOR` 5 x `WOW` 5 = $25 on a new save, `Clients.pay` :113), and ships your first product (`core.shipFirstProduct`).
5. From level 2 (the lobby) clients walk in through the entrance along a gold rug to the reception desk (`Clients.counterLine` `Clients.lua:214`, `setCounter` :144). Skilled clients start here, Star clients from HQ stage 3, BIG clients (gold) from level 2. Products and LAUNCH open here too (`Clients.productsOpen` `Clients.lua:261`, income gate `SiliconCore.server.lua:3353`).
**Files:**
- `src/ServerScriptService/Clients.lua` (280 lines, pure): `TUNE` :49 (pay floor, tip, tiers, stars, patience, cap, HIRE_AFTER, spawn), `cap` :60, `spawnEvery` :64, `coderSpeed` :69, `make` :76, `new` :91, `stars` :106, `pay` :113, `tick` :135, `counterLine` :214, `goal` :232, `fallback` :254, `productsOpen` :261, `handOver` :266.
- `src/ServerScriptService/ClientsServer.lua` (726 lines): `return function(core)`; door line :78, lobby spots :111, desk + rug + CLIENTS sign :144, RENAME prompt on the entrance sign :242, bubble (tier colours `TIER_LOOK` :48) :274, `paid` :424 (cash, Telemetry, `ClientPaid`), `handOverNow` :451, the loop `start` :479 (0.1 s tick, 4 Hz draw). API :616-695: `hold`, `give`, `tap`, `state`, `goal`, `fallback`, `productsOpen`, `goalState`, `reset`, `devServe`.
- `src/ServerScriptService/SiliconCore.server.lua`: wired in one do-block and kept at `Econ.Clients` (:4205); `refreshObjective` reads `Clients.goal` first (:1648-1662; recruiting counts as taught after the first street pickup, `s.recruitTried`).
- `src/StarterPlayer/StarterPlayerScripts/HudClient.client.lua`: the button's states (HOLD TO CODE / CODING n% / GO TO LAPTOP / GO TO CLIENT / GIVE) in `syncCode`; press = `CodeHold` hold, or `GiveApp` when CanGive (:477).
- `src/StarterPlayer/StarterPlayerScripts/ClientFxClient.client.lua`: 3A pops, 3B stamp, 2A fly + open + stars.
**State:**
- Per player `byUser[userId]` in ClientsServer: `Q` (the Clients queue: line, carrying, served, lost, tutorial), `rigs`, `hold`, `canGive`, `mode` (garage/lobby). Nothing is saved; a rejoin starts a new line (the tutorial client only on a first save).
- Player attributes: `CodeProgress`, `AtLaptop`, `CarryingApp`, `CanGive`, `ClientsWaiting`, `JobWaiting`. Client rig attributes: `ClientOf`, `Ask`, `Patience`, `Tier`, `Spot`.
- Remotes (SVRemotes): `CodeHold` (client -> server), `GiveApp` (client -> server), `ClientPaid` { pay, tip, wow, at, who, stars, from, tier } (server -> client).
- Telemetry: money kinds `client` and `client_tip`; events `client_served` (who, tier) and `client_lost`; mark `first_big_client`; funnel step `first_code`.
**Drive it:**
- `dev:Invoke("clients", p, "state")` (line, front, carrying, served), `"serve"` (finish the front job and hand it over now, `api.devServe` :684), `"fresh"` (a new line with the tutorial client) (`DevHook.lua:137-147`). `scenario fresh` does the same plus the first-client setup (`DevScenarios.lua:265`).
- `scenario hq:1` = garage line; `scenario hq:2` = the lobby desk.
- `bot "20 1"` plays the loop: walks to the laptop, holds, carries, presses GIVE (`DevHook.lua:230-251`). While it carries a street recruit it stands aside and lets go of the laptop (:234-237).
**Prove it:**
- `tests/offline/clients.spec.luau`: arrivals, patience, coders, pay, tips by stars, tiers, the desk layout clear of the sofa and the door desks, the goal line, launches gated on the lobby.
- GameDoctor step "first client" (`GameDoctor.server.lua:236`): a new line, the tutorial client served, 5x paid.
- Live (17 Oct, 0c9a994): GIVE flow, desk/rug/sign overlap check, Skilled paying 2x. Not automated: the E key on the prompt, how the FX and the desk look.
**Gotchas:**
- The garage door line is measured from the garage's DoorHeader at server start, for every plot. A line measured without the header is never cached (a level-16 save once left it beside the laptop).
- `levelOf` is the Wafer level (lobby = 2), not `HQLevel` (a stage: 5, 9, 13, 18 start stages 2-5).
- Client rigs are anchored StaffRig rigs moved by PivotTo slides; collisions are off. They glide (no walk animation yet).
- The GivePrompt uses the Custom style (no Roblox prompt UI): the HUD's gold GIVE is the look, E still triggers it.
- `api.give` re-checks range (HAND_RANGE + 2) on the server; a GiveApp spammer is limited to one every 0.3 s.
- A coder's delivery pays no tip and shows no stars; only your own GIVE does.
**Last verified:** 2026-10-17 f757f69
