# Phase 2: the morning run (outline, 9 Oct 2026, for Luke to iterate)

## What exists now (Phase 1, built and checked)
| Piece | Status |
|---|---|
| `bas check` (lint + 218 tests, 5 s) | works |
| `bas baseline save/diff` (sim numbers + drift, 5-pt tolerance) | works; caught a planted change |
| `bas sim`, `bas doctor`, `bas evidence`, `bas scenario list`, `bas map check` | work |
| SVDev `scenario` (chase:<tier>, vip-chase, hq, home, spinoff, tp, snapshot/restore) | chase:genius and chase:star verified live; the rest not yet |
| `compareSnapshot` (proves a save restore) | verified live: 43/43 fields |
| verify-game skill (13 steps + traps) | used once, live |
| Feature map, 18 pages | 97/97 modules, 0 stale |
| Committed on `verify-loop` | 3 commits, not pushed |

## What Phase 2 adds
One scheduled task, every morning, using the desktop app's scheduler. It runs while the
app is open; if the app is closed it runs on the next launch. **It never needs Studio
open**: it reads Studio's log files from disk instead.

### The run, in order
1. `bas doctor`: tools present, which branch.
2. `bas check`: lint + tests.
3. `bas baseline diff`: did any chase or economy number move since the baseline?
4. `bas map check`: any feature page gone stale?
5. **NEW `bas ship`** (the ship gap): see A below.
6. **NEW `bas world`** (world health from the log): see B below.
7. **NEW save round-trip test**: runs inside step 2 once it exists. See C below.
8. Write `HEALTH.md`:
   - one line on top: green or red
   - one line per check
   - what changed since yesterday
   - open findings

### A. `bas ship`: is the live game behind your work? (new)
- Reads git:
  - `main`'s last commit
  - each unmerged branch and how far ahead it is (today `chase-scene` is 63 ahead)
- Reads Studio logs on disk for the last `StudioSavePlaceToCloud` and `PublishPlaceTime`.
  They are there, measured: the newest log shows a save and a publish at 06:28 UTC on 9 Oct.
- Reports:
  - "live is N days behind your newest commit"
  - "M branches unmerged"
  - "last Studio save X hours ago"
- Flags red when live is more than 2 days behind, or a branch is more than 7 days old.
- **Limit:** without the Open Cloud key (Phase 3) it can't know *which commit* is live,
  only *when* the last publish happened.

### B. `bas world`: did anything in the world break? (new)
- Your server already prints its health:
  - `[SV] FurnitureKit: 33/33 meshes present`
  - `4568 hill trees`
  - `23 pieces of greenery are STILL standing in paving`
  - warnings and errors
- It parses the newest Studio log that has a Play run in it into numbers, compares them to
  the last good numbers, and flags any drop (a missing mesh, lost trees, a new error).
- **Limit:** it needs a Play run within the last day to have fresh lines. With no Play run,
  it says "no fresh log" instead of guessing.

### C. Save round-trip: can a save be lost? (new)
- An offline test, `tests/offline/save.spec.luau`:
  1. Loads real saves (a copy of `save_backup_11510645938.json` and Wilz's snapshot) as fixtures.
  2. Saves them, then loads them again.
  3. Fails if any field is dropped or changed.
- It runs in every `bas check`, the pre-commit hook and GitHub CI. About 1 second.
- **Risk:** `SaveLoad.lua` is built as `function(core)`, so the test needs a small fake
  "core". If SaveLoad touches live Instances too deeply, that's a refactor first. I'll
  measure before promising it.

## Decisions for you
1. **Time:** I suggest 10:00 am. You work late, so a 6 am run would only see last night's work at noon anyway.
2. **Commits:** the run never commits, pushes or publishes. It reports only. (Recommended.)
3. **Where findings go:** `HEALTH.md` only, or also a GitHub issue on red? Issues show up on GitHub. I'd start with `HEALTH.md` only.
4. **Stale feature pages:** report them, or let the run fix them? Report-only means no unattended edits. (Recommended.)
5. **Where `HEALTH.md` lives:** `silicon-startup/HEALTH.md`, next to your plans and outside the repo, so it doesn't make commits. (Recommended.)

## Done when
- The scheduled task exists and one run has written `HEALTH.md` on its own.
- `bas ship` reports the real branch and publish state.
- `bas world` reports today's numbers from the log, and flags a planted drop in a test copy of a log.
- The save round-trip test passes on both fixtures and fails when a field is removed on purpose.
- Committed on `verify-loop`.

## Later (not in Phase 2)
- **Exploit check** (fire junk at every remote): before your next public push.
- **Performance budget** (memory, parts, frame time): needs Studio open, so it's a weekly live run.
- **Bot economy run** (time to each HQ level and to spin-off): weekly, about 1 hour of Studio.
- **Playtest video review**: drop a recording in a folder, get issues back.
- **Roblox rule watch** (DevForum announcements): weekly.
- **Open-threads check** (unmerged branches, stale plans): Sunday. Cheap to add to this run.
- **Phase 3** cloud smoke (needs your API key).
- **Phase 4** player funnel. Note: the game **already fires a 9-step onboarding funnel**
  (`[FUNNEL] 1/9 joined`), so Phase 4 starts as reading, not building.

## Built (9 Oct 2026, PR #24) and where it differs
- Decisions taken: 10:00 daily, report only, HEALTH.md only, stale pages reported not fixed, HEALTH.md in `silicon-startup/`.
- `bas ship`, `bas world [save] [--log f]`, `bas health` in `tools/bas.luau`; the pure half in `tools/health_lib.luau` (8 tests on planted logs).
- **C changed:** a full load-save-load round trip needs SaveLoad split from the world building it does (buildShell, spawnStaff, offline pay, ~30 live functions). Built instead: `savecontract.spec.luau`, which checks from SaveLoad's text that every saved field is loaded, every loaded field is saved, and every field of a real v1 save is still read. It catches a deleted field and a one-sided rename (both planted and caught).
- Branch "merged?" is decided by patches, not ids: GitHub's rebase and squash merges rewrite commit ids.
- The scheduled task (`game-morning-health`) runs in a detached worktree `silicon-startup/game-health` on origin/main, so Luke's checkout is never touched.
