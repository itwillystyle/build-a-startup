# Build a Startup! -- game code

Rojo project for the Roblox place (placeId 105976291385232). Files here ARE the game's scripts.

- `src/ReplicatedStorage`      shared ModuleScripts (UIKit, Notify, Cine, FurnitureKit, Items)
- `src/ServerScriptService`    `SiliconCore.server.lua` + server modules. Split out of SiliconCore (v4.2): `CoreConfig` (tuning constants), `SaveLoad`, `DevHook` (Studio-only SVDev), `Progression` (spin-off curve + offline earnings, pure). Generated: `LowPolyData/` by `../blender/lp_world.py`, `HQMeta/` by `../blender/hq.py` + `hq2.py`
- `src/StarterPlayer/StarterPlayerScripts`  `*.client.lua` LocalScripts

Assets (meshes, KenneyKit, SVMeshes, SVFurniture) live only in the place file; the project
marks every service `$ignoreUnknownInstances`, so Rojo never deletes them.

## Toolchain (pinned in rokit.toml)
- `rojo serve` then Studio > Plugins > Rojo > Connect: edits here sync into Studio live
- `selene src`            lint (catches undefined names, unbalanced assignments, shadowing)
- `hooks/pre-commit` runs selene on every commit and REFUSES it on any error (warnings pass). It is on for this repo via `git config core.hooksPath hooks`; after a fresh clone, run that once. It replaces the old install pipe's forward-use check: a local function called above its definition is selene `undefined_variable`.
- `hooks/pre-commit` also runs the offline tests and refuses the commit if one fails.
- `lune run tests/offline/run`   the offline tests (~0.2 s, no Studio): every `tests/offline/*.spec.luau`. Only PURE modules can be tested this way (no `game:GetService` at load): `Progression`, `RoomEconomy`, `CoreConfig`. Put new economy rules there.
- `lune run tools/late_game`     the late-game table (price, wait at HQ 5, what one night pays per apartment) from the same Progression code the game runs.
- `tests/smoke_core.luau`       refactor guard, run in Studio (Server, during Play): drives load / HQ 2-5 / offer / spin-off / save through SVDev and prints only deterministic numbers. Run before and after a change and diff; snapshot the save first (it spins off).
- `tests/notify_spec.luau`, `tests/ranks_spec.luau`  still Studio-only (their modules touch services at load).
- `stylua src`            format (not run yet: do it in its own commit)
- `rojo sourcemap default.project.json -o sourcemap.json` + `luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau src`   type check

Still true: Studio's Ctrl+S saves the place, Alt+P publishes it. Git saves the CODE history.
