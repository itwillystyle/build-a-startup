# The self-improving loop: design (9 Oct 2026)

**Goal.** You state what you want ("make the genius chase scarier"). An agent builds it,
proves it works with evidence (sim table, screenshot, console log), opens a PR, and keeps
it green. You review the evidence and approve the merge and the publish. A daily run
catches anything that drifted. Once players exist, a weekly run reads their data and
proposes the next change.

Sources: poteto's pstack Part 1 ("Verification is all you need"), Theo's loop and
babysitter patterns, Roblox's Open Cloud and Studio docs. Links are at the bottom.

---

## What their advice means for a Roblox game

| They say | For this game |
|---|---|
| Give agents a **CLI**, not markdown (`control-app doctor`, `screenshot`, ...) | `lune run tools/bas <cmd>`: one entry point over the 13 tools that exist today, JSON output, `--help` |
| The CLI drives the real app: navigate, seed the DB, test users | **DevScenarios**: Studio-only server hooks that jump straight to a state (`chase:genius`, `spinoff`, `hq:4`, `cash:1e9`). Simulated mouse input did not register on 8 Oct, so the agent sets up state directly instead of clicking |
| The verification skill (launch, exercise, record evidence, tear down) | `.claude/skills/verify-game/SKILL.md`: the exact Studio MCP procedure, with every rule that has cost a session baked in |
| **Feature map** = shared memory | `docs/features/`: one page per system (how a player reaches it, the files, the scenario that drives it, the check that proves it, the gotchas) |
| Maintain it daily | A scheduled run: checks, sims, compare to yesterday, update the map, write `HEALTH.md` |
| Cloud agents over local | Claude Code **routines** (cloud, since 14 Apr 2026) for everything that doesn't need Studio, plus **Open Cloud Luau Execution** on a TEST place |
| `/swarm`: fan out for statistical confidence | Seeded sim fan-out (chase_threat already runs 2,000 seeds). This is where parallel agents actually pay here |
| Theo's PR **babysitter** | Already built into the desktop app: PR monitor plus CI Auto-fix. CI already runs selene plus 13 spec files (218 tests) |
| Feedback → agent reproduces it | In-game feedback button → the Cloudflare Worker you already have → GitHub issue → a GitHub-triggered routine |
| The human reviews evidence, not steps | You approve merges and **every** publish. Nothing else |

## Hard limits (measured or documented, not guessed)

1. **Studio is a desktop app on your PC.** Cloud agents can't run it. Live Play checks need
   your PC on with Studio open, and one session at a time (two sessions on one Studio
   clobber each other).
2. **Open Cloud Luau Execution** runs your place headless: no physics, and your scripts
   don't auto-run. Limits: 5 minutes per task, 10 unfinished tasks per place, 5 creates
   per minute. That's good for "does every module load", world build + overlap checks,
   and economy curves on the real modules. It can't judge camera or chase *feel*.
3. **The player loop has no data yet.** 18 visits total. A third-party guide quotes Roblox
   as requiring >10 daily users for 7 days before all KPIs unlock. Funnel and custom events
   show up in the dashboards once they arrive, but n is ~0 until strangers play.
4. **Your credentials stay yours.** You create the Open Cloud API key and install the
   GitHub App. Agents never see the key outside a GitHub secret.
5. **Never auto-publish the live place, never touch the main save, never auto-merge main.**

## Phases

### Phase 1: the lever (local, no keys, about one session)
- `tools/bas.luau`, Lune CLI:
  - `doctor`: tool versions, git state, Rojo reachable, Studio running
  - `check`: selene + offline tests, JSON summary
  - `sim <name> [--n] [--json]`: wraps chase_threat, late_game, curve_check
  - `evidence <task>`: makes `evidence/<date>-<task>/` with a manifest
- `src/ServerScriptService/DevScenarios.lua`:
  - guarded by `RunService:IsStudio()`, so it is inert in live servers
  - named scenarios, called through `execute_luau` (Server)
  - destructive scenarios snapshot the DataStore record first and restore after Play stops
- `.claude/skills/verify-game/SKILL.md`. The procedure:
  1. list studios
  2. confirm Edit mode
  3. snapshot the save
  4. start Play
  5. run a scenario
  6. screen_capture plus console errors
  7. stop Play
  8. restore the save
  9. leave Studio in Edit
  10. write the evidence
- `docs/features/`: about 10 pages written by subagents from the code, plus a README index.

**Done when:**
- `lune run tools/bas check --json` passes.
- One live verify of `chase:genius` leaves an evidence folder (screenshot, console log, sim table).
- Every top-level system has a feature page.
- It's committed on branch `verify-loop`, stacked on `chase-scene`.

### Phase 2: the daily loop
- **Local scheduled task** (desktop app) each morning:
  - `bas check` and all sims
  - diff against yesterday (for example, genius escape rates moving more than 5 points)
  - update the feature map from `git log` since the last run
  - write `HEALTH.md`
  - open a GitHub issue on any regression
- A cloud routine runs the same minus Studio. Whether a local scheduled task can reach the
  Studio MCP is **unverified**.

**Done when:** one unattended run writes `HEALTH.md` and catches a planted regression.

### Phase 3: cloud verification (needs your API key)
- A TEST place, never the live one.
- CI steps:
  1. Rojo build
  2. upload to TEST
  3. Luau Execution smoke:
     - require every ModuleScript
     - build the world, then run world_overlap
     - run the economy curve on the real modules
  4. logs go into the PR

Pattern: Roblox's `place-ci-cd-demo` (archived reference, GitHub Actions + Python wrappers).

**Done when:** a PR shows a green cloud smoke, and a planted runtime-only error turns it red.

### Phase 4: the player loop (what actually improves the game)
- **AnalyticsService funnel:** join → first hire → first delivery → first chase → first HQ
  upgrade → spin-off.
- **Custom events:** chase outcome by tier, caught vs escaped.
- **Economy events:** cash sources and sinks.
- **Feedback button:** → Worker → GitHub issue.
- **Weekly routine:**
  1. pull the Analytics Query API (beta)
  2. find the biggest drop-off
  3. propose ONE experiment with a spec and a verify plan
  4. you approve
  5. build, verify
  6. you publish
  7. measure next week
- The events are cheap (about an hour). Ship them before the strangers test, so data
  starts on day one.

## Avoid
- Installing pstack or uni-pstack wholesale. They're built for web apps (Chrome DevTools),
  and third-party mirrors are unsigned. Take the ideas, build Roblox-specific.
- Agents publishing, touching the main DataStore key, or merging main on their own.
- Two sessions driving one Studio.
- Automating "feel". Camera and chase feel still need your eyes on a video.
- Building Phase 3 or 4 infrastructure before Phase 1 has proven useful on a real task.
- "Hundreds of subagents". Studio is one instance and plan caps are real. Parallelism here
  means seeded sims.

## Sources
- Open Cloud Luau Execution: https://create.roblox.com/docs/en-us/cloud/reference/features/luau-execution.md
- Studio command-line interface: https://create.roblox.com/docs/studio/command-line-interface
- place-ci-cd-demo: https://github.com/Roblox/place-ci-cd-demo
- Claude Code routines: https://claude.com/resources/articles/introducing-routines-in-claude-code
- pstack explained: https://www.theneuron.ai/explainer-articles/pstack-explained-lauren-tans-system-for-trustworthy-ai-agents/
- Analytics event types: https://create.roblox.com/docs/en-us/production/analytics/event-types
- Open Cloud Analytics Query API (community test): https://devforum.roblox.com/t/open-cloud-analytics-query-api-is-live-beta-%E2%80%94-tested-documented-with-a-client/4753664
