# The chase (Talent Row)
**What:** Talent Row is the sidewalk where hires wait for you, the rarer ones farther from your door. You recruit one, ride a scooter home with them, and a rival headhunter chases you. It stalks, crouches (the tell), then lunges down a line it picked. You live by steering off the line or hitting BOOST. The server owns the chase (`TalentDrop` runs `ChaseRules` at 20 Hz). The client only draws the camera, lane, sound and speed lines. The daily VIP run is the same chase with two hunters.
**How a player reaches it:**
1. Ship a product and have 1+ staff. The hire pad only gives the free first intern; every later hire is a recruit run (`SiliconCore.server.lua:1857-1873`, `TalentDrop.lua:486-487`).
2. Reach the tier's HQ level: SKILLED 1, STAR 2, GENIUS 3 (`RoomEconomy.lua:355-357`). A tier above your HQ is removed from the street (`TalentDrop.lua:683-690`).
3. Walk out your own drive. Rarer candidates stand farther out, up to 300 studs from the door (`TalentDrop.lua:98-110`). The quest guide points at the best one you can afford (`SiliconCore.server.lua:1711-1716`).
4. Hold the Recruit prompt (0.35 s, 10 studs). Only the plot owner has it enabled (`TalentDrop.lua:216-222`, `TalentRowClient.client.lua:40`).
5. `recruit()` passes its checks, then `startCarry` builds the scooter, starts the offer timer and spawns the hunter (`TalentDrop.lua:445-473`).
6. Ride home. `ChaseCamClient` takes the camera, locks the mouse for steering, and Shift is BOOST (`ChaseCamClient.client.lua:319-327, 347-368`, `ChaseFxClient.client.lua:124-129`).
7. Cross into your lot. The fee is paid there through `api.hire` (`TalentDrop.lua:543-550`). You lose them if caught, if the timer ends, or if you die (`:538-541, 552-555, 578-581`).

**Files:** (short names below mean these paths)
- `src/ServerScriptService/TalentDrop.lua`: all server logic. `spawnCandidate` :184, `scooterOn` :263, `endCarry` :345, `spawnHunter` :396, `startCarry` :445, `recruit` :475, `poach` :508, `stepCarry` :534 (the chase tick), `init` :623, `recruitVip` :742, `spawnVip` :773, `dismissHunter` :835, `devPickVip` :899, `devRecruit` :905.
- `src/ServerScriptService/ChaseRules.lua`: the hunter brain. Pure numbers, no Instances. Constants :48-78, `TIERS` :83-91, `config` :97, `newHunter` :104, `step` :139, `boostReady` :205.
- `src/ServerScriptService/RoomEconomy.lua`: `Econ.TIERS` :353-358, `OFFER_BASE` :359, `CARRY_SPEED` :402 (scooter speed 16 to 20 by HQ level).
- Tiers: `walkin` hq 1, fee 1x, restock 2 s, no chase. `skilled` hq 1, 3x (min $150), 45 s, chase. `star` hq 2, 8x (min $2500), 120 s, chase. `genius` hq 3, 20x (min $25000), 300 s, chase. Fee = max(hire ladder x fee, minFee x price scale) (`TalentDrop.lua:164-168`). `hhSpeed`, `hhDash` and `Econ.HH_*` (:361-376) are the old v4.2 hunter. Nothing reads them.
- `src/ReplicatedStorage/ChaseCam.lua`: pure camera maths. `SHOTS` :251, `LOCKED` :437 (`FRAME_HUNTER` :465), `solveLocked` :534, `clearLens` :658, `follow` :701 (the spring), `DIR` :905, `direct` :1028 (the director: picks the shot and says why). Old `solve` :307 serves modes A and B only.
- `src/ReplicatedStorage/ChaseFrame.lua`: the framing contract in screen space (`CONTRACT` :28, `check` :121). Only tests and `tools/turn_probe.luau` require it. No game script does.
- `src/ReplicatedStorage/ChaseSpeed.lua`: speed-line count and ring (`intensity` :263, `streaks` :284, `band` :313).
- `src/ReplicatedStorage/ChaseAudio.lua`: wind and footstep curves (`windVolume` :69, `windPitch` :89, `stepInterval` :99, `stepVolume` :110).
- `src/StarterPlayer/StarterPlayerScripts/ChaseCamClient.client.lua`: owns the camera in a carry. Default mode "C" :395, steering :310-344, `takeCamera` :347, `release` :370, frame loop :390-561.
- `src/StarterPlayer/StarterPlayerScripts/ChaseFxClient.client.lua`: BOOST button and Shift :89-129, CLOSE CALL :132-152, red lane and hunter outline :154-199, heartbeat and red edges :206-232.
- `src/StarterPlayer/StarterPlayerScripts/ChaseSpeedClient.client.lua`: 24 streaks at the screen edge, on only while `Carrying` and `ChaseCamOwns` :98.
- `src/StarterPlayer/StarterPlayerScripts/ChaseAudioClient.client.lua`: wind bed :124-135, hunter footsteps :137-186.
- `src/StarterPlayer/StarterPlayerScripts/HunterSmoothClient.client.lua`: draws hunters between 20 Hz server samples :49-80.
- `src/StarterPlayer/StarterPlayerScripts/TalentRowClient.client.lua`: prompts :36, timer over the carried hire :48, WindupFlash :74, "Headhunter Xm behind" chip :264-317, CarryLost card :223-252, restock chip :323-333.
- `src/StarterPlayer/StarterPlayerScripts/StaffAnimClient.client.lua`: hunter run animation :53, crouch and lunge poses :382-394.
- Dev drive: `src/ServerScriptService/DevScenarios.lua` (`chase` :188, `vip-chase` :216, `tp` :245), `src/ServerScriptService/DevHook.lua` (`vippick` :497, `recruit` :501).

**State:**
- Session: `s.shipped`, `s.staff` gate a recruit (`TalentDrop.lua:486-488`). `s.vipDay` is set at VIP pickup (`Apartments.lua:514`). Nothing chase-specific is saved.
- TalentDrop tables: `state[plot.index]` candidate slots with `readyAt` :43, `carries[player]` :44, `vips[player]` :726.
- Carry table `c`: `model, tier, fee, from, deadline, speed, baseSpeed, scooter, hunters, hunter, hunterRival, hunterY, chaseCfg, chaseT0, secondSpawned, near, lastBoost, vip, luck` (:498, 427-440, 561-563, 615, 647).
- Player attributes, server: `Carrying` (tier id), `CarryName`, `CarryDeadline` (server clock), `CarrySpeed` (:333, 453-455), `ChaseDist` (nearest hunter, studs, steps of 0.5, :612-613), `BoostAt` (:648, nothing reads it), `Restock_<tier>` (only when restock > 2 s, :362). Client: `ChaseCamOwns` (`ChaseCamClient.client.lua:360`). QA knobs read by `ChaseCamClient`: `ChaseCam`, `ChaseCamDebug`, `ChaseSteer`.
- Rig attributes: candidate `Candidate, Tier, Owner, RoleKey, Seed, RoleName, TierColor, TierName, Wander` (:195-203), `VIP` (:786). A carried hire gets `Carried`, `CarriedBy` and loses `Candidate` (:390-392). Hunter rig `Headhunter` under `Workspace.SiliconValley.TalentRow`: `Chaser`, `ChasingUserId` :413-414, `Windup`, `Lunging` :585-586, `LungeFrom`, `LungeTo` (Vector3) :596-597.
- Remotes in `ReplicatedStorage.SVRemotes`: `CarryBoost` (client to server, no args, :639-654), `ChaseFx` (server to client, `{kind="close"}`, :636, 618), `CarryLost` (server to client, text, :626-629, 339-343).
- recruit() needs all of these, in this order: candidate standing :479, plot owner :480, HQ >= `tier.hq` :481, not carrying :485, shipped and staff >= 1 :487, free seat :488, cash >= fee :494. There is no distance check.
- Hunter phases (`ChaseRules.step`, :139-202): `chase` stalks. Past `FAR` 20 it sprints, past tier `range` it stalks, inside range it jogs. It never gets nearer than `HOLD` 7 unless lunging (:61, :199). `windup` 0.5 s starts when dist <= range, the timer is ready and you are not within `HOME_SAFE` 45 of your lot (:158-160). It picks the line then and paces you (:161-174, :183-186). `lunge` 1.0 s max runs straight down the line at `ref x lunge`, ending 2 studs past the spot (:176-182). `recover` 0.4 s stands still, then back to `chase`. The next lunge waits tier `every` seconds from the end of the lunge (:154-157).
- Tier rows (:88-90): skilled range 8, every 7, lunge 1.10x. star 10, 5.5, 1.50x. genius 13, 5.0, 1.90x. Caught when distance <= `CATCH` 4.5 (`TalentDrop.lua:578`). First lunge waits `FIRST_GRACE` 2 s (:55). BOOST is +8 for 1 s, 5 s cooldown (:78), enforced on the server (`TalentDrop.lua:642-654`). The client's 5 s is a copy (`ChaseFxClient.client.lua:39`).
- VIP chase: two hunters. The first spawns at pickup. The second, "JUNIOR HEADHUNTER", joins 3 s later, 40 studs across the road, jog 0.86, lunge 1.35 (`ChaseRules.lua:76-77, 92-93`, `TalentDrop.lua:561-565`). VIP speeds follow the scooter you ride now (`ChaseRules.lua:97-100`). `Apartments.VIP_FLOOR` {3,4,4} makes STAR for apt 1, GENIUS for apt 2-3 (`Apartments.lua:489`).

**Drive it:** Play, SERVER datamodel, Wilz or a negative test id only (`DevScenarios.lua:22-24, 43-45`). Run `snapshot` first, because scenarios write cash and HQ into the save. Restore after Play stops (`DevScenarios.lua:17-21`). Prove the restore with `require(game.ServerScriptService.DevScenarios).compareSnapshot(1688749216)`, which must give `ok = true`, then leave Studio in Edit (`.claude/skills/verify-game/SKILL.md:59-65`).
- Setup: `local p = game.Players:GetPlayers()[1]` and `local dev = game.ServerScriptService.SiliconCore.SVDev` (`DevScenarios.lua:9-12`).
- `dev:Invoke("scenario", p, "chase:skilled")`, `"chase:star"`, `"chase:genius"`: ship, cash, first hire, HQ level, find the candidate, teleport beside it, recruit, count `Headhunter` models (`DevScenarios.lua:188-215`). Read `ok`, `err`, `did`, `hunters`. A failure names its step, for example a candidate still restocking.
- `"vip-chase"`: `apt 1`, spawn the VIP, walk to it, pick it up (`DevScenarios.lua:216-226`). Two hunters.
- `"tp:candidate:genius"`: teleport only, no recruit (`DevScenarios.lua:255-264`). Also `"tp:vip"` and `"list"`.
- SVDev `recruit <1-4>` (1 walk-in, 2 skilled, 3 star, 4 genius): the real `recruit()` with no teleport (`DevHook.lua:501-505`).
- Client knobs on `LocalPlayer`: `ChaseCam` = "A", "B" or "off". `ChaseCamDebug` = true shows why each cut happened. `ChaseSteer` = rad/s turns you without a mouse (`ChaseCamClient.client.lua:341, 395, 491`).
- Edit mode: paste `tools/chase_lab.luau` into the command bar, then set attributes on `workspace.ChaseLab`: `Mode`, `Dist`, `Windup`, `Speed`, `Turning`, `Run` (`tools/chase_lab.luau:14-38`).

**Prove it:** `lune run tests/offline/run` ran 218 passed, 0 failed on 9 Oct. Each file is under `tests/offline/`.
- `chase.spec.luau`: `ChaseRules` against the model player (400 seeded runs). The old hunter was too easy. Holding W or spamming BOOST loses a genius hire. An ace escapes. Freezing gets you caught. Every catch had a tell. A faster scooter is never a penalty. The VIP stays hardest. The lunge is aimed.
- `chase_model.luau`: not a spec. The human-like player and the v4.2 baseline hunter, shared by `chase.spec.luau`, `tools/chase_sim.luau` and `tools/chase_threat.luau`.
- `chasecam.spec.luau`: the director. No cuts when nothing happens. Every cut has a reason. The tell cuts and the strike is held. Closing and gaining do not chatter. Shots differ enough to read as cuts.
- `chaselocked.spec.luau`: `solveLocked`. Camera yaw equals player yaw, always behind. Every shot passes the `ChaseFrame` contract on three screen shapes. Framing is 20 in, 25 out. No jump at the threshold. The spring settles. Bank stays under 8 degrees.
- `chaseframe.spec.luau`: the projection maths and each rule's failure message in `ChaseFrame`.
- `chasespeed.spec.luau`: lines are 0 at or below 0.9x carry speed, full at boost, rise smoothly, never cover the centre. `ChaseSpeed.BOOST` equals `ChaseCam.DIR.BOOST`.
- `chaseaudio.spec.luau`: `ChaseAudio` endpoints, monotone, smooth, and the loudness caps.
- `lune run tools/chase_threat` (add `-- --json --n 500`; same as `lune run tools/bas sim chase_threat`): escape % by tier, scooter speed and 9 behaviours. On 9 Oct at n=200 a straight W-holder on genius escaped 0%.
- `tools/chase_sim.luau`: old hunter vs new, 5 runs including VIP. `tools/chase_edit.luau`: prints the camera cut list with reasons (`lune run tools/chase_edit -- genius good`). `tools/turn_probe.luau`: a steady mouse turn through `direct`, `solveLocked` and `follow` (`lune run tools/turn_probe 150 0`). `chase_sim`, `chase_edit`, `turn_probe` and `chase_threat` all exited 0 on 9 Oct.
- `lune run tools/bas baseline diff`: reruns tests, `chase_threat` (2000 runs) and `late_game`, then flags any escape % that moved more than 5 points (`tools/bas.luau:282-305, 330`). It said "no drift" on 9 Oct against baseline efeec28.
- No automated check covers `TalentDrop` or any client script. Camera feel and sound are only judged in Play.

**Gotchas:**
- The hunter spawns 22 studs east of the candidate, on world +X, not behind you (`TalentDrop.lua:470`). `recruit()` has no distance check, only the prompt's 10 studs (`:220`). A raw recruit from far away makes a hunter far from you. The scenarios teleport first (`DevScenarios.lua:201-202`).
- Where the candidates stand sets how long a run is. By my arithmetic from `spotFor` (`TalentDrop.lua:101-110`) and `inLot` (:77-80): SKILLED stands at lot-local (-72.6, -30), inside the lot, so its carry delivers on the next tick (:543). STAR stands about 18 studs outside the lot edge, inside `HOME_SAFE` 45, so it cannot start a lunge. GENIUS stands about 125 studs out. A live run on 9 Oct agrees: a star hunter held at 7.1 studs for 12 s, and a genius chase on an idle player lasted about 5 s (`SKILL.md:96-102`). I did not run it. The sims use 140, 280 and 300 studs (`tools/chase_threat.luau:21-25`), not these.
- The fee is checked at pickup but charged at the door. The carry can fail there if cash fell or the seat went (`TalentDrop.lua:494, 546-549`).
- Every pickup of a chase tier spawns a hunter. There is no chance roll (`TalentDrop.lua:469`). The reveal, intercept and random-chase ideas in the 8 Oct threat spec (Phase 2) are not built.
- Only the VIP gets a second hunter. `ChaseRules.lua:76` says "GENIUS / VIP", but genius has `hunters = 1` (:90) and the spawn needs `c.vip` (`TalentDrop.lua:561`).
- Hunters move in 20 Hz steps (`TalentDrop.lua:704-708`). `HunterSmoothClient` draws them about 50 ms behind (`HunterSmoothClient.client.lua:11-15`). A jump over 8 studs or a 0.25 s gap skips smoothing (:22-23, :65). The `ChaseRules.lua:3` header says "every server frame". Code says 20 Hz.
- The lane: `LungeFrom` and `LungeTo` are written once when the crouch starts and cleared after the lunge (`TalentDrop.lua:591-602`). `ChaseFxClient` paints it 9 studs wide, two catch radii (:40, :252-266).
- Camera yaw is the player's yaw. A shot may change distance, height, side, lens and roll, never facing, because W is camera-relative (`ChaseCam.lua:413-416`).
- `FRAME_HUNTER = true` cuts the camera behind the hunter, 30-39 studs back, when it is within 20, and back past 25 (`ChaseCam.lua:457-467`). Setting it false alone is no fix: the hunter stalks 7-13 studs back, so a camera 12 back sits inside it (:459-464). Spec row 6 (8 Oct) wanted "close, always". Code kept the framing, and code wins.
- `tools/chase_lab.luau` calls the old `ChaseCam.solve` (:175). It does not show the shipped locked camera. Use `chase_edit`, `turn_probe` or Play to judge that.
- The Studio MCP bridge resets `CameraType` after each call. `ChaseCamClient` only takes the camera when it is Custom (`ChaseCamClient.client.lua:351`). Set it back with a `task.delay` (`.claude/skills/verify-game/SKILL.md:88-89`). Without the camera, `ChaseCamOwns` is unset and the speed lines stay off (`ChaseSpeedClient.client.lua:98`).
- Injected mouse input did not register on 8 Oct. Use scenarios and `ChaseSteer`, do not click (`SKILL.md:87`). Play snapshots the place at start, so restart Play after code changes. A publish does not reach running servers (`SKILL.md:41, 91-92`).
- While the camera is ours, every ScreenGui except `ChaseFx`, `ChaseStage`, `ChaseSpeed` is switched off (`ChaseCamClient.client.lua:74-85, 187-196`). The `TalentRow` gui holds the "Headhunter Xm behind" chip (`TalentRowClient.client.lua:148`), so it is probably hidden in a default chase. Read, not run.
- Two writers touch `FieldOfView`. The lunge punch yields when `ChaseCamOwns` is set (`ChaseFxClient.client.lua:277`). The BOOST tween to 84 then 70 does not check (:119-121). Unclear if it flickers.
- `chaseCfg` is built once per carry (`TalentDrop.lua:426-439`). After a poach it keeps the first player's lot and speed (:508-530). Read, not run.
- Stale numbers: `chasecam.spec.luau:125` uses LUNGE_TIME 0.8, but `ChaseRules.lua:53` is 1.0. Windup plus lunge is 1.5 s, `DIR.MIN_HOLD` is 1.35 (`ChaseCam.lua:909`), and the test still passes. `tools/anim/hunter.luau:1-2` also says 0.8.
- The hunter's height is fixed at the pickup height (`TalentDrop.lua:415, 603`). Unclear if every road is flat. The sims assume a straight road west (`chase_model.luau:6-12`), but the game uses the player's own drive (`TalentDrop.lua:82-110`). Unclear how well escape % matches live play.
**Last verified:** 2026-10-09 cf0adc8
