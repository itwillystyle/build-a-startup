# Phase 1: the verification lever (spec, 9 Oct 2026)

Parent design: `2026-10-09-self-improving-loop-design.md`.
Branch: `verify-loop`, stacked on `chase-scene` (63 commits ahead of main; the new CLI
wraps chase tools that only exist there).

---

## 1. What I learned before writing this

**Most of the lever already exists, scattered.** Measured on `chase-scene` today:

| Piece | What it does | Where |
|---|---|---|
| **SVDev** | Studio-only BindableFunction, 40+ actions: `cash`, `wlevel`, `hire`, `recruit <1-4>`, `apt`, `vip`, `spinoff`, `gopublic`, `save`, `peek`, `wipe`, `state` | `src/ServerScriptService/DevHook.lua`, mounted only when `RunService:IsStudio()` |
| **The bot** | Plays the real handlers by following the guide (write code, launch, buy), logs HQ times and the spin-off | SVDev `bot "20 2"`, `botlog`, `botstop` |
| **smoke_core** | Server smoke test: runs the core through SVDev and prints deterministic lines; diff before and after a change | `tests/smoke_core.luau` |
| **SVCheck** | Every client check in one call: UI overlap, blocked buttons, world footprint | `ReplicatedStorage/SVCheck.run()` |
| **Lune sims** | chase_threat, chase_sim, chase_edit, turn_probe, late_game, curve_check | `tools/` |
| **Offline tests** | 13 spec files, 218 tests | `tests/offline/run.luau` |
| **CI** | selene plus offline tests on every PR | `.github/workflows/ci.yml` |

**What's missing:**
- one entry point
- machine-readable output
- scenario recipes (each test today re-does its own setup by hand)
- an evidence folder
- the live procedure written down
- a feature map
- any memory of yesterday's numbers

**Measured cost** of the inner check: selene 1.2 s, offline tests 5.1 s, chase_threat 3.4 s.
**Under 10 seconds total**, so it can run after every change.

**Traps already in the code, which the skill must respect:**
- `require` from `execute_luau` returns a **fresh copy** of a module, so changes land on an
  unused copy (`DevHook.lua:101-104`). Every scenario goes through SVDev, never around it.
- `recruit` has no distance check. Without pivoting the player to the candidate first, the
  hunter spawns far away (the bot pivots, `DevHook.lua:318-327`).
- A recruit is refused unless all of these hold:
  - `shipped`
  - staff ≥ 1
  - a free seat
  - cash ≥ fee
  - HQ ≥ the tier's level (genius needs stage 3)
  - the candidate is standing
- The plain `hire` action only works for the first hire.
- Saves go to `SVSave_v1` under `tostring(UserId)`, every 120 s and on leave. Studio plays
  as **Wilz (1688749216)**, never the main account.
- Injected mouse input never registered on 8 Oct. Scenarios set state directly instead of
  clicking.
- **Valley Markets and Founders Coffee are not built.** The map will say so, not invent them.

---

## 2. What the loop learns

| It learns | From | Stored in |
|---|---|---|
| **Numbers:** tests passed, sim escape rates per tier and behaviour, smoke lines, SVCheck findings, console errors | every run | `.evidence/<date>-<task>/report.json` |
| **Drift:** which numbers moved since the last good run | `bas baseline diff` against the last saved baseline | `.bas/baseline.json` |
| **Gotchas:** a verify that fails for a reason not yet written down | the failed run | the skill's *Known traps* plus that feature page's *Gotchas* |
| **The map:** what exists, how a player reaches it, how to drive it, how to prove it | the code, cited file:line | `docs/features/` |

The gotcha row is the self-improving part: the next run doesn't repeat a mistake the last
one paid for. That's poteto's "maintain" step, and the same reason CLAUDE.md has a
"Rules that have each cost a session" list.

**What it cannot learn:**
- **Whether the game is fun.** That needs players (Phase 4).
- **Camera and chase feel.** Those need your eyes on a video.

---

## 3. How often it runs

| Loop | Trigger | How often | Takes | Needs Studio |
|---|---|---|---|---|
| **Inner check** (`bas check`) | the agent after every edit batch; the pre-commit hook; CI on every push | every change (dozens a day while working) | ~7 s | no |
| **Sims** (`bas sim`) | any change under chase or economy files | every relevant change | 3-30 s | no |
| **Drift** (`bas baseline diff`) | after sims; before every commit that touches tuned numbers | every relevant change | <1 s | no |
| **Live verify** (the skill) | once per task, before the agent may say "done" | about 1-5 a day | 2-5 min | **yes**, one session |
| **Smoke diff** (smoke_core) | changes to SiliconCore, DevHook or SaveLoad | every relevant change | ~1 min | yes |
| **Daily health** (Phase 2) | scheduled | **once a day**, morning, only if the PC is on | ~1 min offline (+3 min live if Studio is open) | optional |
| **Feature map maintain** | part of daily health | daily for changed files; **full regen weekly** (Sunday) | a few min | no |
| **Player loop** (Phase 4) | scheduled | **weekly** | — | no |

Phase 1 builds the first five (they run on demand, per change and per task). Phase 2 adds
the schedule.

**Why daily and not hourly:**
- Code only changes when you work, so an hourly run finds nothing new.
- Cloud routine runs are capped per plan (a third-party summary says Max = 15 a day).
- There's one Studio.

---

## 4. Components

### 4a. `tools/bas.luau` (Lune CLI)
Contract:
- Every command takes `--json`.
- JSON shape: `{ ok, command, checks:[{name, ok, detail, ms}], ms, evidence? }`.
- Exit code 0 means ok, 1 means a check failed, 2 means a usage error.
- `--help` on every command.

| Command | Does |
|---|---|
| `doctor` | Checks rokit tools and versions, git branch and dirty files, whether the Rojo serve port answers, and whether RobloxStudio.exe is running |
| `check` | selene (errors fail, warnings pass, same rule as CI) + offline tests |
| `sim list \| <name> \| all` | Runs the Lune sims. `chase_threat` and `late_game` gain a `--json` mode that returns their table rows |
| `baseline save \| diff` | Saves sim numbers; diff flags any escape rate that moved more than 5 points and any changed smoke line |
| `evidence new <slug>` | Makes `.evidence/<date>-<slug>/manifest.json` (task, commit, branch, start time) |
| `evidence add <file> [--kind screenshot\|log\|table]` | Adds to the manifest |
| `scenario list` | Prints every scenario and the one Luau line that runs it, for the agent to send through `execute_luau` (Server) |
| `map check` | Feature map **coverage** (every `src` module is named by some page) and **staleness** (pages whose files changed after their *Last verified* commit) |

`.evidence/` and `.bas/` are git-ignored, so screenshots never go in the repo.

### 4b. Scenarios (`src/ServerScriptService/DevScenarios.lua`)
- Loaded by DevHook as one new SVDev action: `dev:Invoke("scenario", player, "chase:genius")`.
- Inert outside Studio (it lives inside DevHook).
- Each scenario returns `{ ok, did = {...}, state = <SVDev state> }`.

| Scenario | Composed of |
|---|---|
| `rich` | `cash +1e9` |
| `ready` | `ship`, cash, first `hire` if staff is 0, `wlevel 3` |
| `chase:skilled\|star\|genius` | `ready`, pivot to that tier's candidate, `recruit 2/3/4`; returns Carrying and the hunter count |
| `vip-chase` | `ready`, `apt 1`, `vip`, `vippick` |
| `hq:<n>` | `wlevel n` |
| `home:<0-3>` | `apt n` |
| `spinoff` | `gopublic`, `spinoff` (**destructive**) |
| `tp:<hq\|apt\|car\|candidate:<tier>\|vip>` | new: pivot the character (the bot's positions) |
| `snapshot` / `restore` | copies the `SVSave_v1` record to `SVSnap_v1` and back |

Guards:
- Destructive scenarios refuse to run unless `snapshot` ran first in this session.
- **Every** scenario refuses any UserId other than Wilz (1688749216) or a negative test id.

### 4c. The skill: `.claude/skills/verify-game/SKILL.md` (in the game repo)
The procedure, in order:
1. `bas doctor`
2. `list_roblox_studios` (the id changes on every restart)
3. Confirm Edit mode
4. Start Play
5. `scenario snapshot`
6. `scenario <x>`
7. Wait for the state
8. `screen_capture`
9. `get_console_output`; any error fails the run
10. Client-side `SVCheck.run()` if UI changed
11. Stop Play
12. Restore the save in Edit, **after** the stop's save-on-leave
13. `peek` diff shows the save matches the snapshot
14. Leave Studio in **Edit**
15. Write `report.json`

The "done" report must contain:
- `bas check` JSON
- the sim table if the change touched the chase or economy
- the screenshot
- server and client errors
- the scenario's return value
- a **Not verified** list

*Known traps* starts with the eight traps in §1 and grows.

### 4d. Feature map (`docs/features/`, in the repo)
- A README index plus one page per system:
  - core loop
  - hiring and talent
  - the chase
  - homes
  - HQ and paths
  - cars
  - IPO and spin-off
  - offline earnings
  - phone and investors
  - daily, bag and items
  - the valley bell
  - ranks
  - build mode
  - UI and HUD
  - world build
  - saving and data
- Plus a short **Not built** page: Valley Markets, Founders Coffee.
- Each page has:
  - **What**
  - **How a player reaches it**
  - **Files** (file:line)
  - **State** (session and save fields)
  - **Drive it** (scenario)
  - **Prove it** (checks)
  - **Gotchas**
  - **Last verified** (date and commit)
- Subagents draft the pages from the code; I check each one against the code before commit.

---

## 5. Done when (all measured, nothing asserted)
1. `lune run tools/bas check --json` exits 0 and prints valid JSON.
2. `bas sim chase_threat --json` emits rows. `bas baseline diff` shows 0 drift on a clean
   tree and flags a planted 10-point change.
3. Live: `scenario chase:genius` from Wilz's save starts a genius chase in one call
   (`Carrying` set, hunter present).
4. One full skill run leaves `.evidence/2026-10-09-chase-genius/` with:
   - the manifest
   - a screenshot
   - the console log
   - the sim table

   Studio ends in Edit, and the save's `peek` matches the snapshot.
5. `bas map check` reports full `src` coverage and 0 stale pages.
6. Committed on `verify-loop`; selene and the offline tests pass locally and in CI.

## 6. Not in Phase 1
- the schedule (Phase 2)
- Open Cloud (Phase 3)
- analytics (Phase 4)
- auto-merge or auto-publish (never)

**Stretch, only if time allows:** a Studio-only localhost bridge, so a scheduled run can drive
Play without a Claude session.

## 7. Avoid
- New test actions that go around SVDev, or `require`-ing game modules from `execute_luau`.
- Any scenario that can run outside Studio or touch the main account's save key.
- Evidence in git.
- Feature pages that describe what the code *should* do. Every claim cites file:line.
- Calling anything "verified" without its evidence folder.
- Rewriting the existing tools. Wrap them; change them only to add `--json`.
