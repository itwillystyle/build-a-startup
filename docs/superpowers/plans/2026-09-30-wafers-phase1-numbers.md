# Wafers Phase 1 (The Numbers) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tune the Wafers HQ economy (levels 1-100, departments, milestones, blueprint caps, the 25% rebuild discount) in a simulator until it hits the spec's targets. Then lock the tuned numbers into a pure game module that a test proves matches the simulator.

**Architecture:**
- **The rules, in Python.** `sim/wafer_plan.py` mirrors the rules: the 100-piece plan, departments, caps, multipliers, prices, and the guide's department pick.
- **The simulator.** `sim/wafer_sim.py` plays companies 1-8 with the same pace-20 player as `sim/clock_sim.py`, which is already calibrated to the in-game bot within 1 minute.
- **The fitter.** `sim/wafer_fit.py` grid-searches the seven constants and writes `sim/wafer_params.json`.
- **The game module.** `game/src/ServerScriptService/WaferPlan.lua` is the pure game module. Its price, money and staff-cap tables are generated from Python.
- **The drift test.** `game/tests/offline/wafer.spec.luau` checks every number against a golden file that Python writes.
- **Nothing is wired into the game in this phase.**

**Tech Stack:** Python 3.11 (standard library only; `multiprocessing` for the fit), Luau under Lune 0.10.5 (`~/.rokit/bin/lune.exe`), selene.

## Global Constraints

These are from `docs/superpowers/specs/2026-09-30-wafers-hq-design.md`.

**The plan:**
- One level is one piece.
- L1 is the garage.
- Wafer 1 is L2-17 (2 storeys × 8 segments). L2 is the Lobby.
- L18 is garden deck 1.
- Wafer 2 is L19-42 (3 × 8), and L43 is deck 2.
- Wafer 3 is L44-67, and L68 is deck 3.
- Wafer 4 is L69-92.
- L93 is the roof garden, L94-97 the pavilion, and L98-100 the halo, lantern and mast.

**Departments:**

| Department | Seats | Effect | Fits | Unlocks |
|---|---|---|---|---|
| Engineering | +2 | none | engineers, researchers | from the start |
| Design Studio | +2 | quality +0.25 for the first, +0.10 each after (cap 1.5) | designers | from the start |
| Cafe | +4 | morale +0.20 for the first, +0.08 each after (cap 0.8) | sales, recruiters | from the start |
| Server Room | 0 | +1 compute | none | from the start |
| AI Labs | +2 | products 15% faster | researchers | L19 |
| Boardroom | 0 | +1 investor interest | none | L69 |

**Company 1 milestones (the old HQ 2-5):**

| Level | Unlocks | Money | Staff cap | Home needed to build it |
|---|---|---|---|---|
| L5 | car, STAR recruits, investors | ×1.6 | 14 | none |
| L9 | GENIUS recruits | ×2.6 | 20 | Studio |
| L13 | Series A | ×4.2 | 26 | Loft |
| L18 | GO PUBLIC | ×7 | 30 | Penthouse |

The homes are for sale from L5, L9 and L13.

**Later levels:**
- Staff cap: 32 at L43, 34 at L68, 36 at L93, 38 at L98, 40 at L100.
- Blueprint cap by company: 18 / 30 / 43 / 55 / 68 / 80 / 93 / 100.
- A piece costs 25% of its price when its level is at or below your record from before this company.
- Piece price = base(L) × `Progression.runScale(spinoffs)`. The spin-off, homes and cars are unchanged.
- Windfall caps stay as shipped. The "next goal" is now the next piece's price, or the spin-off at the cap.

**Targets. The fit must hit all of them:**
- Company 1 goes public in 21-25 min and spins off in 24-28 min.
- No company takes more than 120 min.
- No single wait for a new piece is longer than 10 min.
- L100 is reached in company 8, with 6-9 h of total play by the end of company 8.
- Rebuilding takes no more than 1/3 of any company's time.
- No single windfall is more than 25% of the next goal.

**Conventions:**
- Every Luau `assert` needs a message (the pre-commit hook's selene rule).
- Commit author: `-c user.name="Luke Williams" -c user.email="storekeeperservice@gmail.com"`, with the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

---

## File Structure

| File | Responsibility |
|---|---|
| `sim/wafer_plan.py` (create) | The source of truth for the Wafers rules and numbers. Commands: print / `golden` / `lua`. |
| `sim/test_wafer_plan.py` (create) | Plain-assert tests for `wafer_plan.py`. Run with `python sim/test_wafer_plan.py`. |
| `sim/wafer_sim.py` (create) | `WaferRun` (a subclass of `clock_sim.Run`), `play`, `summarize`, `report` (writes `sim/WAFERS-NUMBERS.md`) |
| `sim/wafer_fit.py` (create) | The grid-search fit. Writes `sim/wafer_params.json`. |
| `game/src/ServerScriptService/WaferPlan.lua` (create) | The pure game module: the plan, departments, rules, and the generated tables |
| `game/tests/offline/wafer.spec.luau` (create) | Checks the Luau module against `wafer_golden.json` |
| `game/tests/offline/wafer_golden.json` (generated) | The numbers the Luau module must match |

---

### Task 1: The Wafers rules in Python

**Files:**
- Create: `sim/wafer_plan.py`
- Test: `sim/test_wafer_plan.py`

**Interfaces:**
- Produces:
  - Constants: `PIECES` (a list of 100 dicts: level, kind, wafer, storey, seg), `DEPTS`, `BLUEPRINT`, `STAR_AT`, `GENIUS_AT`, `CAR_AT`, `PHONE_AT`, `SERIES_AT`, `APT_FROM` (a list of 3), `LABS_WORK`, `BOARD_INTEREST`.
  - Functions: `params()` → dict; `allowed(level)` → list[str]; `effects(counts)` → dict(quality, morale, compute, labs, board); `seats(counts)` → int; `apt_required(level)` → int; `blueprint(spins)` → int; `recommend(level, counts, free_seats)` → str; `cap_at(level)` → int; `mult_at(level, p)` → float; `base_price(level, p)` → int; `price(level, scale, record, p, base=None)` → int; `tables(p)`; `golden(p)`; `write_lua(p)`.

- [ ] **Step 1: Write the failing tests** in `sim/test_wafer_plan.py`:

```python
"""Tests for wafer_plan.py (plain asserts): python sim/test_wafer_plan.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wafer_plan as WP

P = dict(WP.DEFAULTS)


def test_plan_shape():
    assert len(WP.PIECES) == 100
    kinds = [pc["kind"] for pc in WP.PIECES]
    assert kinds[0] == "garage"
    assert kinds.count("segment") == 88, kinds.count("segment")
    assert [pc["level"] for pc in WP.PIECES if pc["kind"] == "deck"] == [18, 43, 68]
    assert kinds[92] == "roof" and kinds[93:97] == ["pavilion"] * 4
    assert kinds[97:] == ["halo", "lantern", "mast"]


def test_wafer_one_is_levels_2_to_17_front_first():
    w1 = [pc for pc in WP.PIECES if pc["wafer"] == 1 and pc["kind"] == "segment"]
    assert [pc["level"] for pc in w1] == list(range(2, 18))
    assert WP.PIECES[1]["seg"] == 1 and WP.PIECES[1]["storey"] == 0      # L2 faces the road
    assert all(pc["storey"] == 0 for pc in WP.PIECES[1:9])               # L2-9: the ground ring
    assert all(pc["storey"] == 1 for pc in WP.PIECES[9:17])              # L10-17: storey 2


def test_allowed_departments():
    assert WP.allowed(2) == ["lobby"]
    assert WP.allowed(3) == ["eng", "studio", "cafe", "servers"]
    assert "labs" in WP.allowed(19) and "board" not in WP.allowed(19)
    assert "board" in WP.allowed(69)
    assert WP.allowed(18) == [] and WP.allowed(1) == [] and WP.allowed(100) == []


def test_homes_gate_9_13_18():
    assert [WP.apt_required(L) for L in (8, 9, 12, 13, 17, 18, 60)] == [0, 1, 1, 2, 2, 3, 3]


def test_effects_and_caps():
    assert WP.effects({})["quality"] == 0 and WP.effects({})["morale"] == 0
    assert WP.effects({"studio": 1})["quality"] == 0.25
    assert abs(WP.effects({"studio": 3})["quality"] - 0.45) < 1e-12
    assert WP.effects({"studio": 30})["quality"] == 1.5
    assert WP.effects({"cafe": 30})["morale"] == 0.8
    assert WP.effects({"servers": 2, "labs": 3, "board": 1}) == dict(quality=0.0, morale=0.0, compute=2, labs=3, board=1)
    assert WP.seats({"lobby": 1, "eng": 2, "cafe": 1, "servers": 3}) == 2 + 4 + 4


def test_staff_cap_steps():
    assert [WP.cap_at(L) for L in (1, 4, 5, 9, 13, 17, 18, 42, 43, 68, 93, 98, 99, 100)] == \
        [8, 8, 14, 20, 26, 26, 30, 30, 32, 34, 36, 38, 38, 40]


def test_money_multiplier_company_one_matches_old_hq():
    assert [WP.mult_at(L, P) for L in (1, 4, 5, 8, 9, 13, 18)] == [1.0, 1.0, 1.6, 1.6, 2.6, 4.2, 7.0]
    assert abs(WP.mult_at(19, P) - 7.0 * (1 + P["g"])) < 1e-9
    assert abs(WP.mult_at(43, P) / WP.mult_at(42, P) - (1 + P["g"]) * P["deck"]) < 1e-9


def test_prices():
    assert WP.base_price(1, P) == 0
    assert WP.base_price(2, P) == int(P["p0"])
    plain = [L for L in range(2, 101) if L not in WP.MILESTONES]
    for a, b in zip(plain, plain[1:]):
        assert WP.base_price(b, P) >= WP.base_price(a, P), (a, b)
    assert WP.price(18, 1.0, 1, P) == WP.base_price(18, P)
    assert WP.price(18, 2.0, 18, P) == int(WP.base_price(18, P) * 2.0 * P["rebuild"])
    assert WP.price(19, 2.0, 18, P) == int(WP.base_price(19, P) * 2.0)


def test_blueprint():
    assert [WP.blueprint(n) for n in range(10)] == [18, 30, 43, 55, 68, 80, 93, 100, 100, 100]


def test_recommend():
    assert WP.recommend(2, {}, 1) == "lobby"
    assert WP.recommend(3, {"lobby": 1}, 3) == "studio"
    assert WP.recommend(4, {"lobby": 1, "studio": 1}, 3) == "cafe"
    assert WP.recommend(5, {"lobby": 1, "studio": 1, "cafe": 1}, 3) == "servers"
    base = {"lobby": 1, "studio": 1, "cafe": 1, "servers": 1}
    assert WP.recommend(6, base, 0) == "eng"                     # out of seats
    assert WP.recommend(6, base, 3) == "studio"                  # quality below cap, studio <= cafe
    assert WP.recommend(19, dict(base, eng=4), 3) == "labs"      # labs unlocks: shown once


if __name__ == "__main__":
    fails = 0
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            try:
                fn(); print("ok  ", name)
            except AssertionError as e:
                fails += 1; print("FAIL", name, e)
    print(f"{fails} failed")
    sys.exit(1 if fails else 0)
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cd /c/Users/lukex/Downloads/silicon-startup && python sim/test_wafer_plan.py`
Expected: `ModuleNotFoundError: No module named 'wafer_plan'`

- [ ] **Step 3: Write `sim/wafer_plan.py`**

```python
"""The Wafers HQ: the piece plan and its rules (phase 1 of
docs/superpowers/specs/2026-09-30-wafers-hq-design.md).

The numbers live HERE. game/src/ServerScriptService/WaferPlan.lua carries a
generated copy of the tables (python wafer_plan.py lua) and the same small
rules by hand; python wafer_plan.py golden writes the file the Lune test
checks the Luau against, so the game and the sim can't drift.

  python wafer_plan.py            print the plan with today's numbers
  python wafer_plan.py golden     write game/tests/offline/wafer_golden.json
  python wafer_plan.py lua        rewrite the generated block in WaferPlan.lua
"""
import json, math, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.join(os.path.dirname(HERE), "game")
PARAMS_FILE = os.path.join(HERE, "wafer_params.json")
GOLDEN_FILE = os.path.join(GAME, "tests", "offline", "wafer_golden.json")
LUA_FILE = os.path.join(GAME, "src", "ServerScriptService", "WaferPlan.lua")

# the knobs wafer_fit.py tunes (it writes wafer_params.json)
DEFAULTS = dict(p0=100.0, r1=1.7, ms=2.0, r2=1.05, g=0.03, deck=1.25, rebuild=0.25)


def params():
    p = dict(DEFAULTS)
    if os.path.exists(PARAMS_FILE):
        with open(PARAMS_FILE, encoding="utf-8") as f:
            p.update(json.load(f))
    return p


# ---------------------------------------------------------------- the plan
MAX = 100
BLUEPRINT = [18, 30, 43, 55, 68, 80, 93, 100]      # the highest level company n+1 may build
SEG_ORDER = [1, 2, 8, 3, 7, 4, 6, 5]               # segment 1 faces the road, then round both sides to the back
WAFERS = [(1, [0, 1]), (2, [3, 4, 5]), (3, [7, 8, 9]), (4, [11, 12, 13])]
DECK_STOREY = {1: 2, 2: 6, 3: 10}


def build_pieces():
    pieces = []

    def add(kind, wafer, storey, seg):
        pieces.append(dict(level=len(pieces) + 1, kind=kind, wafer=wafer, storey=storey, seg=seg))

    add("garage", 0, 0, 0)
    for w, storeys in WAFERS:
        for st in storeys:
            for seg in SEG_ORDER:
                add("segment", w, st, seg)
        if w in DECK_STOREY:
            add("deck", w, DECK_STOREY[w], 0)
    add("roof", 4, 14, 0)
    for k in range(1, 5):
        add("pavilion", 4, 14, k)
    for kind in ("halo", "lantern", "mast"):
        add(kind, 4, 15, 0)
    assert len(pieces) == MAX, len(pieces)
    return pieces


PIECES = build_pieces()

# ---------------------------------------------------------------- departments
DEPTS = {
    "lobby": dict(seats=2, fit=("engineer", "research"), min=2),
    "eng": dict(seats=2, fit=("engineer", "research"), min=3),
    "studio": dict(seats=2, fit=("designer",), min=3),
    "cafe": dict(seats=4, fit=("sales", "recruiter"), min=3),
    "servers": dict(seats=0, fit=(), min=3),
    "labs": dict(seats=2, fit=("research",), min=19),
    "board": dict(seats=0, fit=(), min=69),
}
CHOOSABLE = ["eng", "studio", "cafe", "servers", "labs", "board"]
QUALITY_FIRST, QUALITY_STEP, QUALITY_CAP = 0.25, 0.10, 1.5
MORALE_FIRST, MORALE_STEP, MORALE_CAP = 0.20, 0.08, 0.8
LABS_WORK = 0.15            # each AI Labs segment: products 15% faster
BOARD_INTEREST = 1          # a Boardroom: investors start one interest higher

STAR_AT, GENIUS_AT, CAR_AT, PHONE_AT, SERIES_AT = 5, 9, 5, 5, 13
APT_FROM = [5, 9, 13]                     # home k+1 is for sale from this level
APT_GATE = [(9, 1), (13, 2), (18, 3)]     # building this level needs this many homes


def allowed(level):
    if PIECES[level - 1]["kind"] != "segment":
        return []
    if level == 2:
        return ["lobby"]
    return [d for d in CHOOSABLE if DEPTS[d]["min"] <= level]


def effects(counts):
    s, c = counts.get("studio", 0), counts.get("cafe", 0)
    q = min(QUALITY_CAP, QUALITY_FIRST + QUALITY_STEP * (s - 1)) if s > 0 else 0.0
    m = min(MORALE_CAP, MORALE_FIRST + MORALE_STEP * (c - 1)) if c > 0 else 0.0
    return dict(quality=q, morale=m, compute=counts.get("servers", 0),
                labs=counts.get("labs", 0), board=counts.get("board", 0))


def seats(counts):
    return sum(DEPTS[d]["seats"] * n for d, n in counts.items())


def apt_required(level):
    need = 0
    for lv, k in APT_GATE:
        if level >= lv:
            need = k
    return need


def blueprint(spins):
    return BLUEPRINT[max(0, min(spins, len(BLUEPRINT) - 1))]


def recommend(level, counts, free_seats):
    """The guide's pick for the segment at `level` (the player can change it)."""
    opts = allowed(level)
    if opts == ["lobby"]:
        return "lobby"
    for d in ("studio", "cafe", "servers", "labs", "board"):      # show each department once
        if d in opts and counts.get(d, 0) == 0:
            return d
    if free_seats <= 1:
        return "eng"
    e = effects(counts)
    if e["quality"] < QUALITY_CAP and counts.get("studio", 0) <= counts.get("cafe", 0):
        return "studio"
    if e["morale"] < MORALE_CAP:
        return "cafe"
    if "labs" in opts and counts.get("labs", 0) * 2 < counts.get("eng", 0):
        return "labs"
    if counts.get("servers", 0) < level // 12:
        return "servers"
    return "eng"


# ---------------------------------------------------------------- the numbers
CAP_STEPS = [(1, 8), (5, 14), (9, 20), (13, 26), (18, 30), (43, 32), (68, 34), (93, 36), (98, 38), (100, 40)]
MULT_STEPS = [(1, 1.0), (5, 1.6), (9, 2.6), (13, 4.2), (18, 7.0)]   # company 1's milestones = the old HQ 1-5
DECKS = (43, 68, 93, 100)                 # later milestones: money x p["deck"] each
MILESTONES = (5, 9, 13, 18, 43, 68, 93, 100)


def cap_at(level):
    c = 0
    for lv, v in CAP_STEPS:
        if level >= lv:
            c = v
    return c


def mult_at(level, p):
    m = 1.0
    for lv, v in MULT_STEPS:
        if level >= lv:
            m = v
    if level > 18:
        m *= (1 + p["g"]) ** (level - 18)
        for d in DECKS:
            if level >= d:
                m *= p["deck"]
    return m


def base_price(level, p):
    if level <= 1:
        return 0
    if level <= 18:
        v = p["p0"] * p["r1"] ** (level - 2)
    else:
        v = p["p0"] * p["r1"] ** 16 * p["r2"] ** (level - 18)
    if level in MILESTONES:
        v *= p["ms"]
    return math.floor(v)


def price(level, scale, record, p, base=None):
    v = (base if base is not None else base_price(level, p)) * scale
    if level <= record:
        v *= p["rebuild"]
    return math.floor(v)


# ---------------------------------------------------------------- golden + Luau
def tables(p):
    return dict(base=[base_price(L, p) for L in range(1, MAX + 1)],
                mult=[mult_at(L, p) for L in range(1, MAX + 1)],
                cap=[cap_at(L) for L in range(1, MAX + 1)])


def golden(p):
    t = tables(p)
    steps, counts = [], {}
    for L in range(2, MAX + 1):
        if PIECES[L - 1]["kind"] != "segment":
            continue
        free = (L * 7) % 4                    # a spread of seat situations
        d = recommend(L, counts, free)
        steps.append(dict(level=L, counts=dict(counts), free=free, pick=d))
        counts[d] = counts.get(d, 0) + 1
    fx = [dict(counts=c, **effects(c)) for c in (
        {}, {"studio": 1}, {"studio": 3, "cafe": 2},
        {"studio": 20, "cafe": 20, "servers": 4, "labs": 3, "board": 1})]
    prices = [dict(level=L, scale=sc, record=rec, price=price(L, sc, rec, p, t["base"][L - 1]))
              for L, sc, rec in ((2, 1.0, 1), (18, 1.0, 1), (18, 2.535, 18), (30, 4.394, 18),
                                 (100, 292.5, 100), (55, 16.89, 43))]
    return dict(pieces=PIECES, blueprint=BLUEPRINT, rebuild=p["rebuild"], **t,
                allowed=[allowed(L) for L in range(1, MAX + 1)],
                apt=[apt_required(L) for L in range(1, MAX + 1)],
                recommend=steps, effects=fx, prices=prices)


def write_lua(p):
    t = tables(p)

    def fmt(xs):
        return ", ".join(repr(x) if isinstance(x, float) else str(x) for x in xs)

    block = ("-- BEGIN GENERATED by sim/wafer_plan.py (python wafer_plan.py lua): do not edit by hand\n"
             f"W.REBUILD = {p['rebuild']!r}\n"
             f"W.BASE = {{ {fmt(t['base'])} }}\n"
             f"W.MULT = {{ {fmt(t['mult'])} }}\n"
             f"W.CAP = {{ {fmt(t['cap'])} }}\n"
             "-- END GENERATED")
    with open(LUA_FILE, encoding="utf-8") as f:
        src = f.read()
    a = src.index("-- BEGIN GENERATED")
    b = src.index("-- END GENERATED") + len("-- END GENERATED")
    with open(LUA_FILE, "w", encoding="utf-8", newline="\n") as f:
        f.write(src[:a] + block + src[b:])


if __name__ == "__main__":
    p = params()
    cmd = sys.argv[1] if len(sys.argv) > 1 else "print"
    if cmd == "golden":
        with open(GOLDEN_FILE, "w", encoding="utf-8", newline="\n") as f:
            json.dump(golden(p), f, indent=1)
        print("wrote", GOLDEN_FILE)
    elif cmd == "lua":
        write_lua(p)
        print("rewrote the generated block in", LUA_FILE)
    else:
        for pc in PIECES:
            L = pc["level"]
            print(f"L{L:3d} {pc['kind']:8s} w{pc['wafer']} st{pc['storey']:2d} seg{pc['seg']}  "
                  f"base ${base_price(L, p):>16,}  x{mult_at(L, p):10.2f}  cap {cap_at(L):2d}  {','.join(allowed(L))}")
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `python sim/test_wafer_plan.py`
Expected: every line `ok`, then `0 failed`.

---

### Task 2: The simulator

**Files:**
- Create: `sim/wafer_sim.py`

**Interfaces:**
- Consumes: `clock_sim` (`Run`, `Player`, `Staff`, `CLOCK`, `spin_cost`, `spin_mult`, `nice_money`, `RECRUIT`, `APT`, `TIER_RATE`, `TALENT_MULT`, `ROLES`, `CODE_CASH`, `CODE_WORK`, `WORK_FIRST`, `WORK_GROWTH`, `LAUNCH_SECONDS`, `HIRE_BASE`, `HIRE_GROWTH`, `SAVE_WINDOW`), and `wafer_plan` from Task 1.
- Produces:
  - `run_scale(n)` → float.
  - `play(companies, seed, P, pace=20, tap_rate=0.9, log=False)` → a list of per-company dicts with keys n, cap, record0, done, t, listed, level, level_at, rate, rebuild, new, tail, max_wait (level, seconds, rebuilt), max_windfall, scale, pieces.
  - `summarize(P, companies=8, seeds=8, quiet=False)` → a list of row dicts with keys n, cap, record0, golive, t, total, rebuild, new, tail, max_wait, max_wait_level, max_windfall, rate, scale, or a `stalled=True` row.
  - `report(P)` writes `sim/WAFERS-NUMBERS.md`.

- [ ] **Step 1: Write `sim/wafer_sim.py`**

```python
"""The Wafers HQ economy, played (phase 1 of the Wafers spec).

The same player as clock_sim.py (the pace-20 bot, calibrated to the in-game
bot within a minute), but the HQ and its rooms are the Wafers' 100 pieces
(wafer_plan.py): each spin-off unlocks more of the blueprint, and a piece at
or below your record costs 25%.

  python wafer_sim.py                 companies 1-8, 8 seeds: the table
  python wafer_sim.py trace 1 3       seed 1, companies 1-3, every event
  python wafer_sim.py report          write WAFERS-NUMBERS.md
"""
import math, os, random, statistics as st, sys
import clock_sim as C
import wafer_plan as WP

HERE = os.path.dirname(os.path.abspath(__file__))
TIER_LEVEL = [1, 1, WP.STAR_AT, WP.GENIUS_AT]     # walk-in, skilled, STAR, GENIUS unlock at these levels
FENCE = "`" * 3                                  # a markdown code fence (kept out of this file's own text)


def run_scale(n):
    """Progression.runScale: the spin-off price scale, x1.3 for the homes from company 2 on."""
    k = max(0, min(n, 20))
    if k == 0:
        return 1.0
    return C.spin_mult(k) * min(1.3 ** k, 30) * 1.3


class WPlayer(C.Player):
    def __init__(self):
        super().__init__()
        self.record = 1          # the highest level ever built (lifetime)


class WaferRun(C.Run):
    def __init__(self, player, seed, P, pace=20, tap_rate=0.9, log=False):
        self.p, self.R, self.P, self.pace = player, C.CLOCK, P, pace
        self.rng = random.Random(seed * 7919 + player.spinoffs)
        self.tap_rate, self.log = tap_rate, log
        self.n = player.spinoffs
        self.scale = run_scale(self.n)
        self.cap = WP.blueprint(self.n)
        self.record0 = player.record
        self.t = 0
        self.cash = 0
        self.level = 1
        self.counts = {}
        self.staff = []
        self.shipped = False
        self.work, self.run_launches, self.pending = 0.0, 0, None
        self.busy_until = self.walk_until = self.next_buy = 0
        self.listed = self.series = self.genius_done = False
        self.restock = [0, 0, 0, 0]
        self.phone_at = self.series_at = self.listed_at = None
        self.rate = 0
        self.luck = 1.0
        self.decor = 0
        self.level_at = {1: 0}
        self.waits = []          # (level, seconds since the last piece, rebuilt?)
        self.pieces = []         # (level, company, wait s, price, rate before)
        self.last_piece_t = 0
        self.money = dict(passive=0, taps=0, launch=0, phone=0, series=0, gopublic=0)
        self.biggest = []
        for role, talent in player.kept:
            self.staff.append(C.Staff(role, talent))
        if player.kept:
            self.shipped = True
        self.seat_all()
        self.recompute()

    def ev(self, s):
        if self.log:
            print(f"c{self.n + 1} {self.t / 60:7.2f}m  L{self.level:3d}  rate {self.rate:>14,}/s  cash {self.cash:>17,}  {s}")

    def piece_price(self, level=None):
        return WP.price(level or self.level + 1, self.scale, self.record0, self.P)

    def next_goal(self):
        return self.piece_price() if self.level < self.cap else C.spin_cost(self.n)

    def capacity(self):
        return min(WP.cap_at(self.level), 1 + WP.seats(self.counts))

    def seat_all(self):
        free = {"garage": 1}
        for d, k in self.counts.items():
            if WP.DEPTS[d]["seats"]:
                free[d] = WP.DEPTS[d]["seats"] * k
        total = self.capacity()
        order = sorted(self.staff, key=lambda s: -s.talent)
        for s in order:
            s.seat = None
        placed = 0
        for s in order:                              # a seat that fits the role first
            if placed >= total:
                break
            for room, k in free.items():
                fits = (s.role == "engineer") if room == "garage" else (s.role in WP.DEPTS[room]["fit"])
                if k > 0 and fits:
                    free[room] -= 1
                    s.seat = (room, True)
                    placed += 1
                    break
        for s in order:                              # then any seat
            if placed >= total:
                break
            if s.seat is None:
                for room, k in free.items():
                    if k > 0:
                        free[room] -= 1
                        s.seat = (room, False)
                        placed += 1
                        break

    def recompute(self):
        e = WP.effects(self.counts)
        base = sum(C.TIER_RATE[s.tier - 1] * C.TALENT_MULT[s.talent - 1] * (1.5 if s.seat[1] else 1)
                   for s in self.staff if s.seat)
        F = ((1 + e["quality"]) * (1 + e["morale"]) * WP.mult_at(self.level, self.P) * C.spin_mult(self.n)
             * (1 + 0.02 * self.milestones()) * (1 + 0.05 * self.index_lines()) * (1 + 0.1 * self.p.apt))
        self.rate = math.floor(base * F) if self.staff else 0

    def buy_apt(self):
        k = self.p.apt
        if k >= 3 or self.level < WP.APT_FROM[k] or self.cash < C.APT[k][0]:
            return False
        self.cash -= C.APT[k][0]
        self.p.apt += 1
        self.busy_until = self.t + 36                       # drive down and back
        self.recompute()
        self.ev(f"home {k + 1} ${C.APT[k][0]:,}")
        return True

    def build_piece(self):
        L = self.level + 1
        if L > self.cap or self.p.apt < WP.apt_required(L):
            return False
        c = self.piece_price(L)
        if self.cash < c:
            return False
        self.cash -= c
        dept = None
        if WP.PIECES[L - 1]["kind"] == "segment":
            dept = WP.recommend(L, self.counts, self.capacity() - len(self.staff))
            self.counts[dept] = self.counts.get(dept, 0) + 1
        wait = self.t - self.last_piece_t
        self.pieces.append((L, self.n, wait, c, self.rate))
        self.waits.append((L, wait, L <= self.record0))
        self.last_piece_t = self.t
        self.level = L
        self.level_at[L] = self.t
        self.p.record = max(self.p.record, L)
        if L == WP.CAR_AT:
            self.busy_until = self.t + 41                   # walk to the car, drive downtown, drive home
        if L == WP.PHONE_AT and self.phone_at is None:
            self.phone_at = self.t + 25
        if L == WP.SERIES_AT and not self.series:
            self.series_at = self.t + 12 + 25
        self.seat_all()
        self.recompute()
        self.ev(f"build L{L} {WP.PIECES[L - 1]['kind']} {dept or ''} ${c:,}")
        return True

    def act(self):
        """The guide: a home when affordable, the first GENIUS, the next piece, else a recruit."""
        if not self.shipped or not self.staff:
            return False
        if self.n == 0 and self.t < 30:                    # company 1: the name box, then the door opens
            return False
        k = self.p.apt
        if k < 3 and self.level >= WP.APT_FROM[k] and self.cash >= C.APT[k][0]:
            return self.buy_apt()
        free = self.capacity() - len(self.staff)
        if self.level >= WP.GENIUS_AT and not self.genius_done and free > 0 \
                and self.cash >= self.fee(3) and self.t >= self.restock[3]:
            return self.recruit(3)
        saving = False
        if self.level < self.cap:
            if self.p.apt >= WP.apt_required(self.level + 1):
                c = self.piece_price()
                if self.cash >= c:
                    return self.build_piece()
                saving = self.rate > 0 and (c - self.cash) / self.rate <= C.SAVE_WINDOW
        else:
            saving = self.rate > 0 and (C.spin_cost(self.n) - self.cash) / self.rate <= C.SAVE_WINDOW
        if free > 0 and not saving and self.cash >= self.ladder():
            best = None
            for i in range(len(C.RECRUIT)):
                if self.level < TIER_LEVEL[i] or self.t < self.restock[i]:
                    continue
                if i == 0 or self.fee(i) <= self.cash * 0.8:
                    best = i
            return best is not None and self.recruit(best)
        return False

    def tick(self):
        t = self.t
        inc = self.rate
        self.cash += inc
        self.money["passive"] += inc
        self.p.earned += inc
        promoted = False
        for s in self.staff:
            if s.seat:
                before = s.tier
                s.seated_t += 1
                if s.tier != before:
                    promoted = True
        speed = 1 + WP.LABS_WORK * self.counts.get("labs", 0)
        self.work += sum(C.TIER_RATE[s.tier - 1] for s in self.staff if s.seat) / 2 * speed
        if t >= self.walk_until and self.rng.random() < self.tap_rate:
            gain = math.floor(max(5, self.rate * C.CODE_CASH))
            self.cash += gain
            self.money["taps"] += gain
            self.work += max(1, sum(C.TIER_RATE[s.tier - 1] for s in self.staff) * C.CODE_WORK) * speed
            if not self.shipped and t >= 3:
                self.shipped = True
                self.staff.append(C.Staff(self.rng.choice(C.ROLES), 1))       # the free intern
                self.p.index.add((self.staff[-1].role, 1))
                self.seat_all()
        need = math.floor(C.WORK_FIRST * C.WORK_GROWTH ** self.run_launches)
        if self.work >= need and self.pending is None and self.staff:
            self.pending = t
        if self.pending is not None and t - self.pending >= 2:
            compute = self.counts.get("servers", 0)
            self.windfall("launch", math.floor(self.rate * C.LAUNCH_SECONDS * (1 + 0.1 * compute)))
            self.pending = None
            self.work = 0
            self.run_launches += 1
            self.p.launches += 1
        interest = 6 + WP.BOARD_INTEREST * min(1, self.counts.get("board", 0))
        floor_amt = 200 * min(5, 1 + self.level // 4)
        if self.phone_at is not None and t >= self.phone_at:
            self.windfall("phone", C.nice_money(max(floor_amt, self.rate * (20 + 12 * interest))))
            self.phone_at = t + 25 + self.rng.randint(240, 360)
        if self.series_at is not None and t >= self.series_at and not self.series:
            self.series = True
            self.windfall("series", C.nice_money(max(floor_amt, self.rate * (20 + 12 * interest)) * 3))
        if self.level == self.cap and not self.listed and t - self.level_at[self.cap] >= 3:
            self.listed = True
            self.listed_at = t
            self.windfall("gopublic", math.floor(self.rate * 60))
        if self.level >= WP.CAR_AT and self.luck == 1.0 and t >= self.busy_until and t >= self.next_buy:
            self.decor += 1                                   # plant, lamp, box: one per pace
            self.cash -= min(self.cash, self.S(60))
            self.next_buy = t + self.pace
            if self.decor >= 3:
                self.luck = 1.2                               # one Vibe star
        if self.p.apt >= 1 and not self.p.vip_done and t >= self.busy_until and len(self.staff) < self.capacity():
            self.p.vip_done = True                            # once per UTC day: company 1 of a session
            self.busy_until = t + 75
            self.hire(3 if self.p.apt < 2 else 4)
            self.ev("VIP picked up")
        if t >= self.busy_until and t >= self.next_buy:
            if self.act():
                self.next_buy = max(self.next_buy, t + self.pace)
        if promoted or t % 5 == 0:
            self.recompute()
        self.t += 1

    def run(self, limit=4 * 3600):
        while self.t < limit:
            self.tick()
            if self.level == self.cap and self.listed and self.cash >= C.spin_cost(self.n):
                return True
        return False


def play(companies, seed, P, pace=20, tap_rate=0.9, log=False):
    pl = WPlayer()
    out = []
    for n in range(companies):
        r = WaferRun(pl, seed, P, pace, tap_rate, log)
        done = r.run()
        new = [w for w in r.waits if not w[2]]
        out.append(dict(n=n, cap=r.cap, record0=r.record0, done=done, t=r.t, listed=r.listed_at,
                        level=r.level, level_at=dict(r.level_at), rate=r.rate, scale=r.scale,
                        rebuild=sum(w[1] for w in r.waits if w[2]), new=sum(w[1] for w in new),
                        tail=r.t - r.last_piece_t,
                        max_wait=max(new, key=lambda w: w[1], default=(0, 0, False)),
                        max_windfall=max((b[4] for b in r.biggest if b[1] != "launch"), default=0.0),
                        pieces=list(r.pieces)))
        if not done:
            break
        r.spin_off()
    return out


def summarize(P, companies=8, seeds=8, quiet=False):
    per = [play(companies, s, P) for s in range(seeds)]
    rows, total = [], 0.0
    for n in range(companies):
        rs = [p[n] for p in per if len(p) > n and p[n]["done"]]
        if len(rs) < len(per):
            rows.append(dict(n=n, stalled=True))
            break

        def med(key):
            return st.median(r[key] for r in rs)

        t = med("t") / 60
        total += t
        rows.append(dict(n=n, cap=rs[0]["cap"], record0=rs[0]["record0"], golive=med("listed") / 60, t=t,
                         total=total / 60, rebuild=med("rebuild") / 60, new=med("new") / 60, tail=med("tail") / 60,
                         max_wait=st.median(r["max_wait"][1] for r in rs) / 60,
                         max_wait_level=st.median(r["max_wait"][0] for r in rs),
                         max_windfall=med("max_windfall"), rate=med("rate"), scale=rs[0]["scale"]))
    if not quiet:
        print_table(rows)
    return rows


def print_table(rows):
    print(" co  cap  rec | go public   spin | rebuild    new   tail | longest new wait | total h | $/s at cap   | top windfall")
    for r in rows:
        if r.get("stalled"):
            print(f" {r['n'] + 1:2d}  STALLED (no spin-off within 4 h)")
            break
        print(f" {r['n'] + 1:2d}  {r['cap']:3d}  {r['record0']:3d} | {r['golive']:8.1f} {r['t']:6.1f} | "
              f"{r['rebuild']:7.1f} {r['new']:6.1f} {r['tail']:6.1f} | {r['max_wait']:6.1f} min at L{r['max_wait_level']:<4.0f} | "
              f"{r['total']:7.2f} | {r['rate']:>12,.0f} | {100 * r['max_windfall']:5.0f}%")


def report(P, seeds=8):
    rows = summarize(P, 8, seeds, quiet=True)
    one = play(8, 0, P)
    lines = ["# The Wafers: the numbers (phase 1)", "",
             "Generated by `python sim/wafer_sim.py report` from `sim/wafer_params.json`:", "",
             FENCE, ", ".join(f"{k}={v}" for k, v in P.items()), FENCE, "",
             "Median of 8 seeds, pace-20 player (the in-game bot's pace). Minutes unless marked.", "",
             "| Company | Cap | Record in | Go public | Spin-off | Rebuild | New pieces | Longest new wait | Total h | $/s at cap | Top windfall |",
             "|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        if r.get("stalled"):
            lines.append(f"| {r['n'] + 1} | STALLED | | | | | | | | | |")
            break
        lines.append(f"| {r['n'] + 1} | {r['cap']} | {r['record0']} | {r['golive']:.1f} | {r['t']:.1f} | {r['rebuild']:.1f} | "
                     f"{r['new']:.1f} | {r['max_wait']:.1f} (L{r['max_wait_level']:.0f}) | {r['total']:.2f} | {r['rate']:,.0f} | "
                     f"{100 * r['max_windfall']:.0f}% |")
    lines += ["", "## Every level, the first time it is built (seed 0)", "",
              "| Level | Piece | Company | Wait (min) | Price | $/s before | Money x | Staff cap |", "|---|---|---|---|---|---|---|---|"]
    first = {}
    for c in one:
        for (L, n, wait, price, rate) in c["pieces"]:
            if L not in first:
                first[L] = (n, wait, price, rate)
    for L in range(2, 101):
        if L in first:
            n, wait, price, rate = first[L]
            lines.append(f"| {L} | {WP.PIECES[L - 1]['kind']} | {n + 1} | {wait / 60:.1f} | ${price:,} | {rate:,} | "
                         f"{WP.mult_at(L, P):.2f} | {WP.cap_at(L)} |")
    out = os.path.join(HERE, "WAFERS-NUMBERS.md")
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote", out)
    print_table(rows)


if __name__ == "__main__":
    a = sys.argv[1:]
    P = WP.params()
    if a and a[0] == "trace":
        seed = int(a[1]) if len(a) > 1 else 1
        play(int(a[2]) if len(a) > 2 else 1, seed, P, log=True)
    elif a and a[0] == "report":
        report(P)
    else:
        summarize(P)
```

- [ ] **Step 2: Smoke-run the simulator with the default constants**

Run: `cd /c/Users/lukex/Downloads/silicon-startup/sim && python wafer_sim.py trace 1 1 | tail -25 && python wafer_sim.py`
Expected: a company-1 trace ending in `build L18 deck`, then GO PUBLIC and the spin-off. The table prints eight rows, or a `STALLED` row. At this step, rows that miss the targets are fine; the numbers are fitted in Task 3.
- If the trace shows a pre-L9 stall waiting on a home: check that `APT_FROM` is indexed 0-based in `buy_apt`/`act`.
- If there's a crash: fix it, then re-run.

---

### Task 3: Fit the constants to the targets

**Files:**
- Create: `sim/wafer_fit.py`
- Writes: `sim/wafer_params.json`

**Interfaces:**
- Consumes: `wafer_sim.play`, `wafer_sim.summarize`, `wafer_plan.DEFAULTS`.
- Produces: `sim/wafer_params.json` with the keys p0, r1, ms, r2, g, deck, rebuild.

- [ ] **Step 1: Write `sim/wafer_fit.py`**

```python
"""Fit the Wafers constants to the spec's targets (phase 1).

Stage A tunes the levels company 1 builds (p0, r1, ms) so GO PUBLIC and the
spin-off land where today's first run does (22.7 / 26.1 min in the in-game
bot). Stage B, with A fixed, tunes the rest (r2, g, deck) against every other
target over companies 1-8. Stage C refines B's best on a finer grid.
Writes wafer_params.json.  python wafer_fit.py
"""
import itertools, json, os, statistics as st, sys
from multiprocessing import Pool
import wafer_plan as WP
import wafer_sim as S

HERE = os.path.dirname(os.path.abspath(__file__))
SEEDS_A, SEEDS_B = 8, 4


def score_a(P):
    runs = [S.play(1, s, P) for s in range(SEEDS_A)]
    if not all(r[0]["done"] for r in runs):
        return 1e9, P, None
    go = st.median(r[0]["listed"] for r in runs) / 60
    spin = st.median(r[0]["t"] for r in runs) / 60
    wait = st.median(r[0]["max_wait"][1] for r in runs) / 60
    s = (go - 23.0) ** 2 + (spin - 26.0) ** 2 + 10 * max(0.0, wait - 10) ** 2
    return s, P, dict(go=round(go, 2), spin=round(spin, 2), wait=round(wait, 2))


def score_b(P):
    rows = S.summarize(P, 8, SEEDS_B, quiet=True)
    if any(r.get("stalled") for r in rows) or len(rows) < 8:
        return 1e9, P, None
    s = 0.0
    for r in rows:
        s += max(0.0, r["t"] - 120) ** 2                          # no company over 2 h
        s += 10 * max(0.0, r["max_wait"] - 10) ** 2                # no new-piece wait over 10 min
        s += 400 * max(0.0, r["rebuild"] / r["t"] - 1 / 3) ** 2    # rebuilding <= a third of a company
        s += 400 * max(0.0, r["max_windfall"] - 0.25) ** 2         # windfalls stay capped
    total = rows[-1]["total"]
    s += 100 * (max(0.0, 6 - total) ** 2 + max(0.0, total - 9) ** 2) + (total - 7.5) ** 2
    s += (rows[0]["golive"] - 23.0) ** 2 + (rows[0]["t"] - 26.0) ** 2
    return s, P, dict(total=round(total, 2), longest=round(max(r["t"] for r in rows), 1),
                      wait=round(max(r["max_wait"] for r in rows), 1),
                      rebuild=round(max(r["rebuild"] / r["t"] for r in rows), 2))


def best_of(pool, fn, grid):
    res = sorted(pool.map(fn, grid), key=lambda x: x[0])
    for s, P, info in res[:5]:
        print(f"  {s:10.2f}  {info}  " + " ".join(f"{k}={P[k]}" for k in ("p0", "r1", "ms", "r2", "g", "deck")))
    return res[0]


def main():
    base = dict(WP.DEFAULTS)
    with Pool(max(1, (os.cpu_count() or 4) - 2)) as pool:
        print("stage A: company 1 (p0, r1, ms)")
        grid = [dict(base, p0=p0, r1=r1, ms=ms) for p0, r1, ms in itertools.product(
            (60.0, 80.0, 100.0, 130.0), (1.55, 1.6, 1.65, 1.7, 1.75, 1.8, 1.85, 1.9), (1.0, 1.5, 2.0, 3.0))]
        sa, A, _ = best_of(pool, score_a, grid)
        print("stage B: companies 1-8 (r2, g, deck)")
        grid = [dict(A, r2=r2, g=g, deck=deck) for r2, g, deck in itertools.product(
            (1.0, 1.02, 1.04, 1.06, 1.08, 1.1, 1.13), (0.0, 0.02, 0.04, 0.06, 0.08), (1.0, 1.25, 1.5, 2.0))]
        sb, B, _ = best_of(pool, score_b, grid)
        print("stage C: refine around B")
        grid = [dict(B, r2=round(B["r2"] + dr, 3), g=round(max(0.0, B["g"] + dg), 3), deck=round(max(1.0, B["deck"] + dd), 3))
                for dr, dg, dd in itertools.product((-0.01, -0.005, 0.0, 0.005, 0.01), (-0.01, 0.0, 0.01), (-0.125, 0.0, 0.125))]
        sc, Cbest, info = best_of(pool, score_b, grid)
    if sc >= 1e9:
        sys.exit("no feasible constants: every candidate stalled")
    with open(os.path.join(HERE, "wafer_params.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(Cbest, f, indent=1)
    print("wrote wafer_params.json", Cbest, info)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run the fit**

Run: `cd /c/Users/lukex/Downloads/silicon-startup/sim && time python wafer_fit.py`
Expected: three stages print their top 5, then `wrote wafer_params.json`. It takes a few minutes with 22 worker processes.

- [ ] **Step 3: Check the fitted numbers against every target**

Run: `python wafer_sim.py report && python test_wafer_plan.py`
Expected: `WAFERS-NUMBERS.md` is written, and the printed table shows:
- company 1 goes public in 21-25 and spins off in 24-28;
- every company is under 120 min;
- every longest new wait is 10 min or less;
- total hours after company 8 are between 6 and 9;
- the top windfall is 25% or less.

If a target is missed, widen the matching grid in `wafer_fit.py` (for example, add r2 values above 1.13, or g up to 0.12) and re-run from Step 2.
- Structural misses (for example, rebuilding over a third) are fixed by adding `rebuild` to the stage-C grid: 0.15 / 0.2 / 0.25.
- If `rebuild` changes from 0.25, record the new value in the spec.

---

### Task 4: The game module and the drift test

**Files:**
- Create: `game/src/ServerScriptService/WaferPlan.lua`
- Create: `game/tests/offline/wafer.spec.luau`
- Generate: `game/tests/offline/wafer_golden.json` (`python sim/wafer_plan.py golden`)

**Interfaces:**
- Consumes: `sim/wafer_plan.py` (`golden`, `write_lua`) and `sim/wafer_params.json` from Task 3.
- Produces (for phases 3-4):
  - Constants: `WaferPlan.MAX`, `BLUEPRINT`, `PIECES`, `DEPTS`, `CHOOSABLE`, `STAR_AT`, `GENIUS_AT`, `CAR_AT`, `PHONE_AT`, `SERIES_AT`, `APT_FROM`, `LABS_WORK`, `BOARD_INTEREST`, `QUALITY_CAP`, `MORALE_CAP`, `REBUILD`, `BASE`, `MULT`, `CAP`.
  - Functions: `allowed(level)` → {string}, `effects(counts)` → {quality, morale, compute, labs, board}, `seats(counts)` → number, `aptRequired(level)` → number, `blueprint(spins)` → number, `recommend(level, counts, freeSeats)` → string, `capAt(level)`, `multAt(level)`, `basePrice(level)`, `price(level, scale, record)` → number.

- [ ] **Step 1: Write the failing test** `game/tests/offline/wafer.spec.luau`:

```lua
-- wafer.spec.luau: the Wafers plan (WaferPlan.lua) against the sim's golden file.
-- The sim (sim/wafer_plan.py) owns the numbers; this proves the game module says the same.
local W = require("../../src/ServerScriptService/WaferPlan")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local G = serde.decode("json", fs.readFile("tests/offline/wafer_golden.json"))

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end
local function near(a, b) return math.abs(a - b) <= 1e-9 * math.max(1, math.abs(b)) end

test("100 pieces, each the sim's kind, wafer, storey and segment", function()
	assert(#W.PIECES == 100 and #G.pieces == 100, "100 pieces")
	for i, g in ipairs(G.pieces) do
		local p = W.PIECES[i]
		assert(p.level == g.level and p.kind == g.kind and p.wafer == g.wafer and p.storey == g.storey and p.seg == g.seg,
			("piece %d: %s w%d st%d seg%d vs %s w%d st%d seg%d"):format(i, p.kind, p.wafer, p.storey, p.seg, g.kind, g.wafer, g.storey, g.seg))
	end
end)

test("prices, money and staff caps match the sim's tables", function()
	assert(W.REBUILD == G.rebuild, "rebuild share")
	for L = 1, 100 do
		assert(W.basePrice(L) == G.base[L], ("base price L%d: %s vs %s"):format(L, W.basePrice(L), G.base[L]))
		assert(near(W.multAt(L), G.mult[L]), ("money x L%d"):format(L))
		assert(W.capAt(L) == G.cap[L], ("staff cap L%d"):format(L))
	end
end)

test("departments allowed and homes needed, per level", function()
	for L = 1, 100 do
		local a, g = W.allowed(L), G.allowed[L]
		assert(#a == #g, ("allowed L%d: %d vs %d"):format(L, #a, #g))
		for i = 1, #g do assert(a[i] == g[i], ("allowed L%d #%d: %s vs %s"):format(L, i, a[i], g[i])) end
		assert(W.aptRequired(L) == G.apt[L], ("homes needed L%d"):format(L))
	end
end)

test("the guide's department pick matches the sim at every segment", function()
	for _, s in ipairs(G.recommend) do
		local pick = W.recommend(s.level, s.counts, s.free)
		assert(pick == s.pick, ("L%d free %d: %s vs %s"):format(s.level, s.free, pick, s.pick))
	end
end)

test("department effects match the sim", function()
	for i, e in ipairs(G.effects) do
		local got = W.effects(e.counts)
		assert(near(got.quality, e.quality) and near(got.morale, e.morale), ("effects case %d"):format(i))
		assert(got.compute == e.compute and got.labs == e.labs and got.board == e.board, ("counts case %d"):format(i))
	end
end)

test("price: the company's scale, and 25% at or below your record", function()
	for _, c in ipairs(G.prices) do
		local got = W.price(c.level, c.scale, c.record)
		assert(got == c.price, ("L%d scale %s record %d: %s vs %s"):format(c.level, c.scale, c.record, got, c.price))
	end
end)

test("blueprint: 18, 30, 43 ... 100, and 100 after that", function()
	for n = 0, 9 do
		assert(W.blueprint(n) == G.blueprint[math.min(n + 1, #G.blueprint)], ("company %d"):format(n + 1))
	end
	assert(W.blueprint(-1) == 18, "never below the first blueprint")
end)

return T
```

- [ ] **Step 2: Generate the golden file and confirm the test fails**

Run:
```bash
cd /c/Users/lukex/Downloads/silicon-startup && python sim/wafer_plan.py golden && cd game && ~/.rokit/bin/lune.exe run tests/offline/run
```
Expected: `wafer.spec.luau: could not load` (no WaferPlan module yet), and the other specs still pass.

- [ ] **Step 3: Write `game/src/ServerScriptService/WaferPlan.lua`**

```lua
--[[ WaferPlan: the Wafers HQ as pure data and rules (phase 1 of
docs/superpowers/specs/2026-09-30-wafers-hq-design.md).

No services, no requires: tests/offline runs it in Lune. The price, money and
staff-cap tables below are GENERATED from sim/wafer_plan.py (the simulator
that tuned them to the spec's targets); tests/offline/wafer.spec.luau checks
every number and rule here against the sim's golden file, so the game and the
sim can't drift. Change a number in the sim, re-fit, then run
`python sim/wafer_plan.py lua` and `python sim/wafer_plan.py golden`.

One level is one piece: L1 the garage, L2-17 wafer 1 (L2 the Lobby), L18
garden deck 1, L19-42 wafer 2, L43 deck 2, L44-67 wafer 3, L68 deck 3, L69-92
wafer 4, L93 roof garden, L94-97 the founder pavilion, L98-100 the crown.
Not wired into the game yet (phase 3). ]]
local W = {}

W.MAX = 100
W.BLUEPRINT = { 18, 30, 43, 55, 68, 80, 93, 100 }   -- the highest level company n+1 may build
W.STAR_AT, W.GENIUS_AT, W.CAR_AT, W.PHONE_AT, W.SERIES_AT = 5, 9, 5, 5, 13
W.APT_FROM = { 5, 9, 13 }                           -- home k is for sale from this level
local APT_GATE = { { 9, 1 }, { 13, 2 }, { 18, 3 } }  -- building this level needs this many homes

-- BEGIN GENERATED
-- END GENERATED

-- ---------------------------------------------------------------- the plan
local SEG_ORDER = { 1, 2, 8, 3, 7, 4, 6, 5 }       -- segment 1 faces the road, then round both sides
local WAFERS = { { 1, { 0, 1 } }, { 2, { 3, 4, 5 } }, { 3, { 7, 8, 9 } }, { 4, { 11, 12, 13 } } }
local DECK_STOREY = { [1] = 2, [2] = 6, [3] = 10 }

W.PIECES = {}
local function add(kind, wafer, storey, seg)
	table.insert(W.PIECES, { level = #W.PIECES + 1, kind = kind, wafer = wafer, storey = storey, seg = seg })
end
add("garage", 0, 0, 0)
for _, wf in ipairs(WAFERS) do
	local w, storeys = wf[1], wf[2]
	for _, st in ipairs(storeys) do
		for _, seg in ipairs(SEG_ORDER) do add("segment", w, st, seg) end
	end
	if DECK_STOREY[w] then add("deck", w, DECK_STOREY[w], 0) end
end
add("roof", 4, 14, 0)
for k = 1, 4 do add("pavilion", 4, 14, k) end
for _, kind in ipairs({ "halo", "lantern", "mast" }) do add(kind, 4, 15, 0) end
assert(#W.PIECES == W.MAX, "the Wafers plan must have exactly 100 pieces")

-- ---------------------------------------------------------------- departments
W.DEPTS = {
	lobby = { seats = 2, fit = { engineer = true, research = true }, min = 2 },
	eng = { seats = 2, fit = { engineer = true, research = true }, min = 3 },
	studio = { seats = 2, fit = { designer = true }, min = 3 },
	cafe = { seats = 4, fit = { sales = true, recruiter = true }, min = 3 },
	servers = { seats = 0, fit = {}, min = 3 },
	labs = { seats = 2, fit = { research = true }, min = 19 },
	board = { seats = 0, fit = {}, min = 69 },
}
W.CHOOSABLE = { "eng", "studio", "cafe", "servers", "labs", "board" }
local QUALITY_FIRST, QUALITY_STEP = 0.25, 0.10
local MORALE_FIRST, MORALE_STEP = 0.20, 0.08
W.QUALITY_CAP, W.MORALE_CAP = 1.5, 0.8
W.LABS_WORK = 0.15            -- each AI Labs segment: products 15% faster
W.BOARD_INTEREST = 1          -- a Boardroom: investors start one interest higher

local function clampLevel(level) return math.clamp(math.floor(level or 1), 1, W.MAX) end

-- the departments you may choose for the segment at `level` ({} for fixed pieces)
function W.allowed(level)
	level = clampLevel(level)
	if W.PIECES[level].kind ~= "segment" then return {} end
	if level == 2 then return { "lobby" } end
	local out = {}
	for _, d in ipairs(W.CHOOSABLE) do
		if W.DEPTS[d].min <= level then table.insert(out, d) end
	end
	return out
end

-- what the built departments add: counts = { eng = 3, studio = 1, ... }
function W.effects(counts)
	local s, c = counts.studio or 0, counts.cafe or 0
	local q = s > 0 and math.min(W.QUALITY_CAP, QUALITY_FIRST + QUALITY_STEP * (s - 1)) or 0
	local m = c > 0 and math.min(W.MORALE_CAP, MORALE_FIRST + MORALE_STEP * (c - 1)) or 0
	return { quality = q, morale = m, compute = counts.servers or 0, labs = counts.labs or 0, board = counts.board or 0 }
end

-- seats the departments add (the garage's one seat is not counted here)
function W.seats(counts)
	local n = 0
	for d, k in pairs(counts) do
		local dept = W.DEPTS[d]
		if dept then n += dept.seats * k end
	end
	return n
end

-- how many homes you must own to build `level`
function W.aptRequired(level)
	local need = 0
	for _, g in ipairs(APT_GATE) do
		if level >= g[1] then need = g[2] end
	end
	return need
end

-- the highest level a company may build after `spins` spin-offs
function W.blueprint(spins)
	return W.BLUEPRINT[math.clamp(math.floor(spins or 0) + 1, 1, #W.BLUEPRINT)]
end

-- the guide's pick for the segment at `level` (the player can change it)
function W.recommend(level, counts, freeSeats)
	local opts = W.allowed(level)
	if #opts == 1 and opts[1] == "lobby" then return "lobby" end
	local has = {}
	for _, d in ipairs(opts) do has[d] = true end
	for _, d in ipairs({ "studio", "cafe", "servers", "labs", "board" }) do   -- show each department once
		if has[d] and (counts[d] or 0) == 0 then return d end
	end
	if freeSeats <= 1 then return "eng" end
	local e = W.effects(counts)
	if e.quality < W.QUALITY_CAP and (counts.studio or 0) <= (counts.cafe or 0) then return "studio" end
	if e.morale < W.MORALE_CAP then return "cafe" end
	if has.labs and (counts.labs or 0) * 2 < (counts.eng or 0) then return "labs" end
	if (counts.servers or 0) < level // 12 then return "servers" end
	return "eng"
end

-- ---------------------------------------------------------------- the numbers
function W.capAt(level) return W.CAP[clampLevel(level)] end
function W.multAt(level) return W.MULT[clampLevel(level)] end
function W.basePrice(level) return W.BASE[clampLevel(level)] end

-- a piece's price in a company: its base x the company's scale (Progression.runScale),
-- and REBUILD of that at or below the record the company started with
function W.price(level, scale, record)
	local v = W.basePrice(level) * scale
	if level <= record then v *= W.REBUILD end
	return math.floor(v)
end

return W
```

- [ ] **Step 4: Fill the generated block and run the tests**

Run:
```bash
cd /c/Users/lukex/Downloads/silicon-startup && python sim/wafer_plan.py lua && cd game && ~/.rokit/bin/selene.exe src/ServerScriptService/WaferPlan.lua tests/offline/wafer.spec.luau && ~/.rokit/bin/lune.exe run tests/offline/run
```
Expected: selene reports `0 errors`, and the runner prints `70 passed, 0 failed (6 spec files)` (63 old plus 7 new).
- If a `base price` case fails by 1, the float power differs between Python and Luau. That shouldn't happen, because the Luau reads the generated table instead of computing powers.
- If a `recommend` case fails, compare the Python and Luau rule line by line.

- [ ] **Step 5: Commit**

```bash
cd /c/Users/lukex/Downloads/silicon-startup/game && git checkout -b wafers && git add src/ServerScriptService/WaferPlan.lua tests/offline/wafer.spec.luau tests/offline/wafer_golden.json && git -c user.name="Luke Williams" -c user.email="storekeeperservice@gmail.com" commit -q -m "Wafers phase 1: WaferPlan (the 100-piece plan and its tuned numbers) + drift test

The numbers come from sim/wafer_plan.py + sim/wafer_fit.py (tuned to the
spec's targets, table in sim/WAFERS-NUMBERS.md). The Luau tables are
generated; wafer.spec.luau checks every number and rule against the sim's
golden file. Not wired into the game yet.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" && git log --oneline -1
```
Expected: one new commit on branch `wafers`.

---

## Self-review

- **Spec coverage (phase 1 = numbers):**
  - the 100-piece plan (Task 1, Task 4)
  - departments and their effects, unlock levels (Task 1)
  - company-1 milestones matching the old HQ 1-5 (Task 1 `MULT_STEPS`/`CAP_STEPS`, Task 3 stage A)
  - blueprint caps (Task 1)
  - the rebuild discount (Task 1 `price`, Task 2 `record0`)
  - the windfall caps' next goal (Task 2 `next_goal`)
  - every target (Task 3 `score_b` plus the Step 3 check)
  - the minutes table (Task 2 `report`)
  - no game wiring (a constraint)
- **Placeholders:** none. Every step has its code or command.
- **Names match across tasks:**
  - `apt_required` ↔ `aptRequired`, `blueprint`, `recommend`, `cap_at` ↔ `capAt`, `mult_at` ↔ `multAt`, `base_price` ↔ `basePrice`, `price(level, scale, record)`
  - The golden file's keys: pieces / base / mult / cap / allowed / apt / recommend / effects / prices / blueprint / rebuild. These are used verbatim in `wafer.spec.luau`.

---

## Amendments made while executing (30 Sep)

- **Storey rebuild.**
  - Added `wafer_plan.rebuild_last` / `batch_price`, the Luau `rebuildLast` / `batchPrice`, the golden `batches`, and 2 spec tests.
  - `WaferRun.build_piece` buys a whole rebuilt storey per tap.
  - Why: at one piece per tap, rebuilding was 76-80% of late companies.
- **The fit gained an income band and a floor on the money step.**
  - The band: 0.5-10× today's $/s at each company's top, from `OLD_RATE`.
  - `g >= 0.01`: floors must add money.
  - `rebuild` is now fitted as well, and it settled at 0.025.
- **The golden file gained targeted department-pick scenarios.** One per branch, at its boundary.
  - Why: a tamper of the Server Room rule was NOT caught by the generated walk.
  - After the fix, 4 of 4 branch tampers are caught.
- **The report's markdown fence became `FENCE = "`" * 3`.** A literal triple backtick inside the plan's code ended the code block early when it was extracted.
