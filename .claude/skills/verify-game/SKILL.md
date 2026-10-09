---
name: verify-game
description: Prove a change to Build a Startup works, with evidence, before calling it done. Use after any code change to the game (offline checks), and once per task for a live Studio check (Play, a scenario, a screenshot, console errors, restore the save, back to Edit). Use when asked to verify, test, check, or show proof.
---

# verify-game

A task is not done until its evidence folder passes `bas evidence done`.
Run everything from the game folder: `C:\Users\lukex\Downloads\silicon-startup\game`.
Every command takes `--json`.

## Loop 1: after every change (about 7 s)
```
lune run tools/bas check
```
selene errors or any failing offline test: fix it before doing anything else.

## Loop 2: when you touched chase or economy code (3-30 s)
```
lune run tools/bas baseline diff
```
- Every moved number must be one you **meant** to move. Say which, and why.
- If the move was intended and you checked it, run `lune run tools/bas baseline save`, and
  say so in the report.
- Other sims: `lune run tools/bas sim list`.

## Loop 3: once per task, live in Studio (2-5 min)
Start the proof folder first:
```
lune run tools/bas evidence new <short-task-name>
lune run tools/bas check --save
lune run tools/bas doctor          (Studio and Rojo serve must say running)
```
If Studio or Rojo is not running, stop and ask Luke to open Studio and run `serve.cmd`.
Do not open them yourself.

Then, with the Roblox Studio MCP tools:
1. `list_roblox_studios`. The id changes on every Studio restart. Pick the instance whose
   name has place 105976291385232.
2. `get_studio_state`. Must be Edit. If Play is running from an old session, stop it first:
   Play snapshots the place at start, so a stale Play runs old code.
3. `start_stop_play` with is_start true. Wait until the Server datamodel shows the player
   loaded:
   `return game.ServerScriptService.SiliconCore.SVDev:Invoke("state", game.Players:GetPlayers()[1]).loaded`
4. Snapshot the test save (Server):
   `local p = game.Players:GetPlayers()[1] return game.ServerScriptService.SiliconCore.SVDev:Invoke("scenario", p, "snapshot")`
5. Run the scenario for your task (Server). See `lune run tools/bas scenario list`, e.g.
   `... :Invoke("scenario", p, "chase:genius")`. Read `ok`, `err` and `did`. A refusal names
   the step that failed. Fix the setup, not the check.
6. Look at it:
   - `screen_capture` to see the frame yourself
   - `lune run tools/bas evidence shot <name>` to file a copy (Studio must be in front)
7. `get_console_output`. Save it to a text file, then
   `lune run tools/bas evidence add <file> --kind console`.
   Any error or warning from our scripts fails the run.
8. UI changed? Client datamodel: `return require(game.ReplicatedStorage.SVCheck).run()`.
   File the result.
9. `start_stop_play` with is_start false.
10. Restore the save **after** the stop. The stop's save-on-leave would overwrite an earlier
    restore. In the Edit datamodel:
    `return require(game.ServerScriptService.DevScenarios).restore(1688749216)`
11. Prove the restore (Edit):
    `return require(game.ServerScriptService.DevScenarios).compareSnapshot(1688749216)`
    It must return `ok = true, differs = {}`. File the result as a note.
    Then leave Studio in **Edit**. `get_studio_state` must say so.
12. `lune run tools/bas evidence note "not verified: <everything you did not check>"`
13. `lune run tools/bas evidence done` must pass.

## The report Luke gets
- the evidence folder path
- what passed (numbers, not adjectives)
- what moved in the baseline and why
- what was **not** verified

Feel (camera, fun, readability) is never "verified" by these tools. Say so.

## Known traps (each one has cost a session; add new ones here)
- `require()` from `execute_luau` returns a **fresh copy** of a module, so changes land on an
  unused copy. Drive the game through SVDev (`scenario` or its raw actions), never around it
  (DevHook.lua, "bell").
- `recruit()` has no distance check. The `chase:*` scenarios pivot the player to the
  candidate first. Raw `recruit` does not.
- A recruit needs all of these: shipped, staff ≥ 1, a free seat, cash ≥ fee, HQ ≥ the tier's
  level (genius = stage 3), and the candidate standing. Genius restock is 300 s.
- Studio plays as **Wilz (1688749216)**. Scenarios refuse every other account. Never touch the
  main account's save.
- Injected mouse input did not register (8 Oct). Set state through scenarios. Don't click.
- The Studio MCP bridge resets CameraType after each call. If a camera test needs Custom, set
  it again with a `task.delay`.
- Another Claude window can drive the same Studio. Only one session at a time.
- A publish does not reach running servers. Never publish from this skill. Publishing is
  Luke's.
- After a Bulk Import, move meshes out of Workspace before any save.
- `x and nil or y` in Lua is ALWAYS y. Use an explicit `if` (bit DevScenarios on its first live run, 9 Oct).
- Don't compare two `JSONEncode` strings: key order is not stable. Use `compareSnapshot` (canonical, sorted keys).
- A screenshot taken after `scenario` returns can miss the moment (a genius chase on an idle player
  was over in ~5 s). For timing proof, record a timeline in the same server call (sample every 0.5 s
  into a StringValue in ServerStorage), then screen_capture while it runs.
- `chase:skilled` and `chase:star` start near home: delivery = stepping onto the lot
  (TalentDrop.lua:543), the skilled candidate stands inside the lot, and the star candidate is about
  18 studs out, inside the 45-stud no-lunge zone. A star hunter cannot lunge there (measured 9 Oct:
  it held at 7.1 studs for 12 s). Live chase lengths are not the simulator's 140/280/300.

## Where things are
- feature map: `docs/features/README.md` (what each system is, how to drive and prove it)
- the CLI: `tools/bas.luau`
- scenarios: `src/ServerScriptService/DevScenarios.lua`
- Studio-only debug actions: `src/ServerScriptService/DevHook.lua`
