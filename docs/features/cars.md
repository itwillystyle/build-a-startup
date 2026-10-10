# Cars (company car, dealer, driving, ambient traffic)
**What:** At HQ stage 2 the company gives the player a free hatchback. Valley Motors sells five faster cars. The player drives with a VehicleSeat that the client steers. Separate from that, ambient traffic is scenery that each client moves on its own.
**How a player reaches it:**
1. Build to stage 2 (wafer level 5). The server calls `Cars.grant(player, "hatch", "COMPANY CAR!")` after 3.5 s (`src/ServerScriptService/SiliconCore.server.lua:2149-2150`). The car parks in the plot's bay (`src/ServerScriptService/Cars.lua:227-229`).
2. Walk up and press the "Drive" prompt (owner only), or tap the CAR button or press C to call the car (`CallCar`, `Cars.lua:272`).
3. Move with WASD or thumbstick. Jump to get out. Shift is nitro, H is the horn (`src/StarterPlayer/StarterPlayerScripts/CarClient.client.lua:167-192`).
4. Buy more at the campus showroom car (prompt "Cars", `Cars.lua:560`) or the dealership display pads (prompt "Look", `Cars.lua:580`). `DealerMenu` opens the list, `BuyCar` buys or switches (`Cars.lua:305-334`, `CarClient.client.lua:551-616`).
**Files:**
- `src/ServerScriptService/Cars.lua`: `CATALOG` :30 (six cars), `build` :84, Drive prompt :160-176, parking on empty :177-192, `spawn` :211, `grant` :255, `callCar` :272, `buyCar` :305, `status` :336, `init` :346, no-cars-in-a-chase watch :383, showroom :399-595, `save` :597, `onLoad` :603.
- `src/ServerScriptService/Downtown.lua`: `dealerPads` :333-338 and `dealerForecourt` :345 (where bought cars wait).
- `src/StarterPlayer/StarterPlayerScripts/CarClient.client.lua`: drive loop :199 (starts when `SeatPart` is an `SVCar`), `call` :335, dealer card :551, turntables :625.
- `src/StarterPlayer/StarterPlayerScripts/TrafficClient.client.lua`: moves every `TrafficCar` tagged model (:98-100, loop :155). Cars are placed by `src/ServerScriptService/CityKit.lua:482` (straight lanes) and `src/ServerScriptService/CampusHub.lua:612` (ring lanes, `RingR`).
**State:**
- Session: `s.cars` (owned ids), `s.car` (the one you drive), `s.jr.drove`.
- Player attributes: `CarOwned`, `CarId`, `CarName`, `CarTop` (`Cars.lua:217-222, 261`). Client only: `BuildModeOpen` hides the CAR button (`CarClient.client.lua:348`).
- Car model: tag `SVCar`, attributes `Owner`, `CarId`, `Speed`, `Accel` (`Cars.lua:196-200`). One unanchored `Chassis`, owned by the driver's client.
- Traffic model: tag `TrafficCar`, attributes `LaneA`, `LaneB`, `LaneId`, `Speed`, `Phase`, `CrossAt` or `RingR`, `RingDir`.
- Saved: `cars`, `car` (`src/ServerScriptService/SaveLoad.lua:140-141`). Load keeps only known ids (`Cars.lua:597-617`).
**Drive it:**
- `dev:Invoke("scenario", p, "tp:car")` goes to the spawned car (`DevScenarios.lua:230`). It fails with "no position" if no car exists yet.
- `hq:<n>` does NOT grant the car. `wlevel` sets the stage directly (`DevHook.lua:65-81`) and skips the grant. Untested recipe from the code: `wlevel 4`, then `upgrade` across level 5 (`DevHook.lua:62`).
- No raw action buys or grants a car. "none yet".
- The `bot` action fakes the car and drive steps by setting `s.jr.drove` (`DevHook.lua:292-301`). It never drives.
**Prove it:** no automated check yet. `tests/smoke_core.luau` only reads `cars` and `car` from the saved record. `SVCheck` skips `TrafficCar` models when it looks for overlaps (`src/ReplicatedStorage/SVCheck.lua:300`).
**Gotchas:**
- `Cars.spawn` destroys the old car and builds a new one (`Cars.lua:211-214`). "Call car" and "switch car" both replace it.
- Calling the car tries four spots beside you. It needs open sky above and ground below, else the toast "Step outside to call your car" (`Cars.lua:292-302`). It returns silently if you are seated (:281).
- No cars in a chase: Drive is refused while Carrying, and a carry that starts mid-drive stands you up (`Cars.lua:170-173, 383-395`).
- The driver's client sets velocity on the chassis. Server and client both depend on network ownership (`Cars.lua:182-186`). An empty car anchors itself after 2 s (:188-193).
- `buyCar` has no HQ stage check. Any player who reaches a dealer prompt can buy (`Cars.lua:305-334`).
- The free hatchback is hidden in the dealer list until owned (`CarClient.client.lua:553`).
- `Cars.forecourt` is set only after the Downtown dealer pads exist. It waits 30 s, else cars appear in the plot bay (`Cars.lua:404-409`, `buyCar` :314).
- Old saves past HQ 2 with no cars get the hatchback on load (`Cars.lua:611-615`).
- Lifts: `LiftGo` stands you up first, because moving a seated player drags the car (`HQFloors.lua:113-127`).
- The CAR button pulses only while the Journey objective is "car" (`CarClient.client.lua:359-366`).
- The header comment says "HQ 2". In Wafers mode that means wafer level 5 (`Wafers.lua:166-171`).
- Security (9 Oct exploit check): `CallCar`, and `BuyCar` on a car you already own, respawn the car for every client, so both share a 2 s gate (`Cars.lua:284, 312`).
**Last verified:** 2026-10-10 d49543c
