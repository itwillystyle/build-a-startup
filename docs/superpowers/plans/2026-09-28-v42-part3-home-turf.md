# v4.2 Part 3: Home Turf Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Owning an apartment feeds the core loop and gives reasons to come back:
- a return pays more of the wait for your next step (offline earnings by apartment tier)
- one VIP recruit a day waits outside your building, the longest run home

**Architecture:**
- **Apartments** gets two pure functions, testable in Edit:
  - `Apartments.ladder` (your next two steps' costs)
  - `Apartments.offline` (the payout rule)
- **Apartments** also gets a daily VIP loop that asks **TalentDrop** to spawn an owner-only candidate at the Residences.
- **TalentDrop:**
  - `recruit` is split so a VIP uses the same carry, hunter, offer timer and door roll (`startCarry`)
  - the door roll can carry a luck multiplier
- **SiliconCore** (no new top-level locals):
  - the offline block calls `Apartments.offline`
  - `hire` multiplies luck
  - save/load `vipDay`
  - dev actions `apt` and `vip`
- **HudClient:** the While You Were Away line names the apartment.

**Tech Stack:** Roblox Luau, Studio MCP, the localhost install pipe, Python sims (`sim/offline_sim*.py`).

## The offline rule: CHANGED FROM THE SPEC BY SIMULATION (the spec said "set by simulation")

- **The spec's rule fails.** `min(raw, 1.0 × next step)` pays LESS than today at 3 of 4 tiers (Penthouse 4 min vs 10 min today). The 2 h / 8 h / 24 h returns were identical, because the cap always binds. (`sim/offline_sim.py`, 10,440 returns.)
- **The rule used instead (C3s):**

  ```
  offline = min( rate × 0.25 × min(away, WINDOW[apt]),
                 max(rate × 600, nextStep),
                 nextStep + stepAfter − cash − 1 )     (floored at 0)
  WINDOW = 40 min (none, the same as today) / 2 h / 4 h / 8 h
  ```

- **What it guarantees:**
  - never below today's 10 minutes of income
  - up to one whole next step when the window allows
  - never enough to buy two steps in one return
- **Where it matters: late spin-off loops** (`sim/offline_sim3.py`). The wait at HQ 5 grows about 1.67x per spin-off. The share of that wait one 8 h return covers:

  | Spin-off | Wait at HQ 5 | Today | Studio | Loft | Penthouse |
  |---|---|---|---|---|---|
  | 4 | 52 min | 19% | 58% | 100% | 100% |
  | 5 | 112 min | 9% | 27% | 54% | 100% |

- **Separate finding:** by spin-off 7–8 the wait at HQ 5 is 9–20 hours. That's a late-game wall and belongs in its own economy pass.

## Global Constraints
- VIP:
  - one per UTC day, owner-only pickup
  - tier floor Studio STAR (3), Loft GENIUS (4), Penthouse GENIUS with luck × 2
  - the tier's normal fee at the door, and a free seat
- One saved integer (`vipDay`), set when the VIP is picked up. Unclaimed VIPs expire; nothing piles up.
- No new top-level locals in SiliconCore. Snapshot/restore around live tests. Disk == Studio. Studio left in Edit.

### Task 1: Pure rules + tests
- [ ] `tests/home_spec.luau` (fails first: `Apartments.offline` missing). It checks:
  - `ladder` next/after with and without gates, and at HQ 5 (spin, then HQ 2)
  - the payout is never below today
  - never two steps
  - window scaling: 2 h vs 8 h Penthouse on a long wait
  - apt 0 equals today
- [ ] `Apartments.WINDOW`, `Apartments.ladder(level, apt, hqCost(level), spinCost)`, `Apartments.offline(rate, away, apt, cash, nextStep, stepAfter)`
- [ ] Install, then `PASS`

### Task 2: Offline in SiliconCore + HudClient
- [ ] In applySave, the offline block uses `Econ.Apt.offline` with a ladder from `HQ_LEVELS[l].cost` and `SPINOFF_BASE × SPINOFF_GROWTH ^ spinoffs`. It sets the attribute `OfflineApt`. The old rule is kept when `Econ.Apt` is absent.
- [ ] HudClient: "Your team kept working." becomes "Your <STUDIO/LOFT/PENTHOUSE> kept things running." when `OfflineApt > 0`.

### Task 3: VIP
- [ ] TalentDrop: extract `startCarry(player, plot, c)` from `recruit` (no behaviour change).
- [ ] TalentDrop: `TalentDrop.spawnVip(player, pos, tierIndex, luck, onPickup)`:
  - gold ring + pillar, label "VIP · <TIER>"
  - an owner-only prompt that checks seat, fee and shipped exactly like `recruit`
  - `c.luck`
  - `onPickup` fires when the carry starts
- [ ] TalentDrop: `TalentDrop.clearVip(player)` removes a standing VIP; called on leave.
- [ ] `stepCarry` passes `luck = c.luck` to `api.hire`. SiliconCore `hire` rolls `TALENT.roll(VibeLuck × (recruit.luck or 1))` (the roll clamps luck at 3).
- [ ] Apartments: a 20 s loop. For each player with `apt ≥ 1`, shipped, `vipDay ≠ today`, no VIP standing, and not carrying:
  - spawn at `(640 + 9 × plotIndex, ground, 36)`, outside the Residences on the road side
  - send a Phone notice once per spawn
- [ ] Phone: `Phone.notice(player, id, first, firm, text)` (unread +1, a `msg` with notify).
- [ ] SiliconCore: save/load `vipDay`. Dev actions `apt <n>` (sets `s.apt`, recompute) and `vip` (spawns now, ignoring the day).
- [ ] Install all; compile; forward-use only the known false positives.

### Task 4: Live verification
1. Snapshot the record.
2. **Offline:** write a test save (HQ 5, apt 3, spinoffs 4, rate, lastSeen 8 h ago). Join. The paid amount equals `Apartments.offline(...)`, and the card names PENTHOUSE. Restore.
3. **VIP:**
   - dev `apt 3` + dev `vip` → a VIP stands at the Residences with the phone notice
   - a second `vip` the same day (without dev) does not spawn
   - pickup starts a carry with a headhunter, and `vipDay` = today
   - delivery: talent ≥ GENIUS
   - 200 in-engine rolls of `TALENT.roll(2)` with floor 4 are always ≥ 4
4. Notify, Ranks and home specs all pass. Disk == Studio. Report + CLAUDE.md. Restore.
