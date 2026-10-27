# Manage Staff — design (13 Oct 2026)

Approved in conversation, 12–13 Oct. His picks: see everyone in one list; move people
between rooms; a stats screen where stats go up, limited by where you are in the game.
Stats chosen: **Skill, Speed, Loyalty** (no role-signature stats). Upgrading: **train
with cash**. Moving: **pick a room type**. Plus the **wall TV shows real revenue**.

Repo: `Downloads/silicon-startup/game`. Code facts below are from the staff map of
12 Oct (file:line there); re-check lines before editing.

## 1. Why

Today staff are a count with a multiplier. Seating is automatic, there is no list of
people, and a person's only growth is seniority, which rises on its own by sitting.
The player makes no decisions about their people. My Restaurant's "Manage Workers"
showed the pattern he liked. This gives every person a face, a place he chooses, and
three numbers he can raise with money he has earned.

## 2. What the player sees

- **TEAM** tile in the rail's MORE tray (`UIKit.railButton`, `opts.tray`), icon
  `UIKit.ICON.team`, frameless like the other tiles. Plot-only like DECOR.
- **The list** (one row per person, sorted by $/s; toggle: by talent):
  name · role icon · talent badge (Regular … Unicorn) · seniority (Intern … Lead) ·
  room, with ✓ when it is a best-fit room · $/s.
- **The card** (tap a row):
  - three bars: Skill, Speed, Loyalty, each "level / max";
  - TRAIN beside each: price on the button; disabled at max ("MAX") or when you
    cannot afford it (price shown, button dim);
  - MOVE: a list of room types: Garage, Lobby, Engineering, Design Studio, Cafe,
    AI Labs. Each shows free seats; best-fit rooms are marked; a type with no free
    seat is greyed. Choosing one moves the person now and pins them there.
  - one line of what the stats mean ("Skill: more money. Speed: ships apps faster.
    Loyalty: keeps their training when they follow you to a new company.").
- Feedback: TRAIN plays the existing small reward beat (Moment, not a big moment);
  the $/s on the row updates at once; MOVE shows the person walking to the new room
  (they are re-seated, which already animates).

Phone first: the list is a scrolling column; the card is a bottom sheet. UIKit tokens
only (`uistyle.spec` enforces sizes, corners, colours, fonts).

## 3. The rules

### 3.1 Effects (per level)
| Stat | Changes | Formula change |
|---|---|---|
| Skill | that person's income | `v = TIER_RATE[tier] * TALENT.mult * fit * eff * (1 + SKILL_STEP * skill)` |
| Speed | that person's product work | `work += TIER_RATE[tier] / 2 * (1 + SPEED_STEP * speed) * (1 + labs * 0.15)` |
| Loyalty | spin-off carry-over | a keeper keeps `floor(L * min(1, LOYALTY_STEP * loyalty))` of each trained level L of Skill and Speed; Loyalty itself is kept |

Starting values: `SKILL_STEP = 0.10`, `SPEED_STEP = 0.10`, `LOYALTY_STEP = 0.10`. The
simulator sets the final values against the gates in §6. **Amended 13 Oct (phase 1):**
`SKILL_STEP = 0.065`. History: 0.10 failed G1 on the modelled team (2.106); 0.09 passed it (1.995) but the independent review showed G1 must hold for ANY team, whose worst case is all top talent: 0.09 gave 2.350, 0.08 2.200, 0.07 2.050, 0.065 1.975 (pass). Non-keepers leave at a
spin-off as today, so their training goes with them. Seniority still resets to Intern
at a spin-off (unchanged). The WRITE CODE tap is unchanged.

### 3.2 Caps (the progression limit)
`cap(stage, talent) = 2 * stage + TALENT_BONUS[talent]`, `TALENT_BONUS = {0, 0, 1, 3, 5}`
(Regular, Skilled, Star, Genius, Unicorn). `stage` = `Wafers.stage(level)` (1–5).
Regular at stage 1: 2. Genius at stage 5: 13. Unicorn at stage 5: 15. A stat above
the cap (after a spin-off lowers the stage) keeps its level and its effect but cannot
be trained further until the cap passes it. **Amended 13 Oct (phase 1):** levels CARRIED into a new company are
clamped to its cap (`StaffStats.carried`): the fallback declared before the simulator
ran, applied because the raw carry failed G4 (five max-loyal Genius keepers made the
next run's first stage 2.3x faster; clamped: 1.45x, ratio 0.690).

### 3.3 Price
`price(level) = max(BASE * GROWTH ^ level * Prog.runScale(spinoffs), rate * FLOOR_SECONDS[level])`,
where `level` is the current level (buying level+1). **Amended 13 Oct (phase 1, after the independent review):**
the price is exactly `payback(level) = 200 + 100 * level` seconds of the income that
level adds for THAT person (`personBaseRate * SKILL_STEP * payback`), at least
`MIN_PRICE = 10`; there is no BASE/GROWTH curve and no run scale (the rate already
carries the spin multiplier). Both earlier forms failed G2: the company-rate floor
(~47 min for a 14-person team) and the early curve (45 min for an Intern outside
their room). The income floor follows the rule decor already uses (`FurnitureKit.floorSeconds`):
training is never trivially cheap late in a run. Starting values: `BASE = 50`,
`GROWTH = 1.6`, `FLOOR_SECONDS = 20 + 10 * level`. Same price for all three stats.
Final values from the simulator (§6).

### 3.4 Moving and pinning
- Room types map to Wafers departments: Lobby `lobby`, Engineering `eng`, Design Studio
  `studio`, Cafe `cafe`, AI Labs `labs`, Garage = the garage bench (`"hq"`).
- A pinned person is seated first by `assignDesks`, in a free seat of their pinned
  department. Unpinned people are then seated as today (first fit, then any, then the
  waiting line).
- If a pinned department has no free seat (a seat was removed), the person is seated
  as unpinned and the pin stays; the card says "no free seat in Cafe".
- Best fit comes from `Econ.FIT[role]` through `SEAT_ROOM` (Wafers). Fit still gives
  `FIT_MULT = 1.5`.

## 4. Data and save

- Every person gets a permanent `id` (a per-save serial, `s.nextStaffId`). Old saves:
  ids are assigned on load in list order.
- Per person, saved beside the existing parallel arrays (`staff`, `tiers`, `talents`,
  `people`): `ids[i]`, `skill[i]`, `speed[i]`, `loyalty[i]`, `pin[i]` (department or
  ""). Missing arrays load as 0 / "" (old saves keep working).
- The spin-off keeper record (`{talent, who}`) gains `{skill, speed, loyalty, id}`
  after the Loyalty rule.
- Stats are clamped on load to `0..30` (a bad save cannot mint levels; same spirit as
  the keeper-slot clamp).

## 5. Server and client

- **`src/ReplicatedStorage/StaffStats.lua`** (pure, shared): `STATS` table (one row
  per stat: id, label, blurb, step), `cap(stage, talent)`, `price(level, rate,
  spinoffs)`, `effect(stat, level)`, `carry(level, loyalty)`. Adding a stat later =
  one row here + its test + the one place its effect is applied.
- **Remote** `SVRemotes.StaffAction` (RemoteEvent): `("train", id, statId)` and
  `("move", id, dept)`. The server checks: the plot is the player's, the id is theirs,
  the stat or department is valid, level < cap, cash ≥ price (charged server-side),
  a free seat exists; 4 actions a second at most. Ids are opaque (the spin-off pattern).
- **State to the client**: player attribute `StaffData` (JSON: per person id, name,
  role, talent, tier, room, fit, rate, skill/speed/loyalty, caps, prices, pin), written
  after any change, like `IndexData`.
- **`TeamClient.client.lua`**: the rail tile, list and card; reads `StaffData`, fires
  `StaffAction`.
- **Wall TV**: the server keeps a ring of the plot's income, sampled every 30 s
  (12 samples); the TV's bars (GarageDress `B.tv`) are redrawn from it and the latest
  $/s is printed under them. It replaces the static bars.

## 6. Verification (the pass rules are written now, before any results)

1. **`tests/offline/staffstats.spec.luau`**: caps for every stage × talent; price is
   increasing in level and never below the income floor; effects are exact; carry():
   0 loyalty keeps 0, max loyalty keeps all, never more than trained; adding a row to
   `STATS` without a test fails (the spec iterates `STATS`).
2. **Balance gates in the simulator** (`tools/curve_check` or a new `tools/staff_sim`),
   decided now:
   - G1: at each stage, a team trained to its caps earns **at most 2.0×** an untrained
     team at the same stage.
   - G2: every **Skill** purchase, at the stage it unlocks, **pays back in 3–30 minutes**
     of that person's added income. (Speed and Loyalty earn indirectly, through
     launches and spin-offs, so G3 and G4 cover them.)
   - G3: time to the next HQ stage with greedy training is **at least 70%** of today's
     (training speeds the loop up, it does not skip it).
   - G4: the per-run spin-off value with max Loyalty keepers stays under the existing
     late-game curve's ceiling (`tools/late_game`). **Amended 13 Oct:** made concrete
     before the run as "the next company's time to stage 2 with five max-trained,
     max-loyal Genius keepers is at least 60% of the same keepers untrained"; the
     simulator models Skill only (Speed's carry is not in G4).
   **Amended 13 Oct (review):** G1 is checked for the worst possible team, G2 for
   every seniority, fit or not, every spin-off count and every level.
   A value set is accepted only if G1–G4 all pass; otherwise keep the previous values.
3. **Save/load round trip** (offline, SaveLoad's pure half if it has one, else a Studio
   scenario): ids, stats and pins survive; an old save without the arrays loads with
   zeros; a save with skill = 999 loads clamped.
4. **Doctor step `team`**: via the server functions (not the UI): train one stat on
   one person, move one person to a department with a free seat; measure that the
   person's seat is in that department, that their income rose by the expected
   factor (±1%), that cash fell by the shown price, and that a train past the cap is
   refused. Severity BUG for each.
5. **UI**: the doctor's existing screen probes (cards over cards, taps under 44 px,
   text under 14 px) cover the TEAM screen once it is open during the step.
6. **The PR doctor gate** (`bas checkup pr`) before each merge.

## 7. Out of scope

Role-signature stats; points from promotions; picking an exact desk; swapping two
people; firing; staff on the leaderboard; poach offers (still off under V3).

## 8. Phases (each one a PR through the doctor gate)

1. **Data**: ids, the three stats, save/load, `StaffStats`, the income and work
   formulas, caps, prices, `staffstats.spec`, the simulator gates (§6.2). No UI.
2. **Actions**: `StaffAction` train/move, pinned seating in `assignDesks`, `StaffData`,
   the Loyalty carry at spin-off, the doctor `team` step.
3. **The screen**: TEAM tile, list, card, feedback.
4. **The wall TV** live income.

## 9. Risks

- `assignDesks` reseats everyone on every change; pins must be honoured first or
  people will jump rooms (the bug this feature would otherwise create).
- Income growth stacks multiplicatively with hqMult, spinMult and the index; G1 is
  there to stop a runaway.
- No stable id existed; any code that used list position for identity (spin-off picks
  use opaque serials already) must move to `id`.
