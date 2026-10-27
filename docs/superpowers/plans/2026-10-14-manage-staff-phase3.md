# Manage Staff phase 3 (the TEAM screen) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (inline, chosen for phase 2 and kept). Steps use `- [ ]`.

**Goal:** A TEAM tile in the MORE tray opens a list of every person and a card where the player trains Skill, Speed and Loyalty and moves people between rooms, using phase 2's server actions.

**Architecture:** The server already publishes `StaffData` and owns every rule (`StaffAction`). Phase 3 adds the two facts the card needs and the server does not send yet (free seats per room, which rooms fit a role), a pure `TeamView` module that turns the data into what each button shows (tested offline), and `TeamClient`, which only draws and fires the remote. The doctor opens the screen during its `team` step and runs its screen probes on it.

**Tech Stack:** Roblox Luau, Rojo 7.7, Lune offline tests, selene, `tools/bas`, Studio MCP.

**Spec:** `docs/superpowers/specs/2026-10-13-manage-staff-design.md` §2 (what the player sees), §5 (`TeamClient`), §6.5 (UI probes), §8 phase 3.

## Global Constraints

- UIKit tokens only: `uistyle.spec` fails on typed fonts, text sizes, corners, colours, and on overshoot outside a `-- reward` line.
- Text ≥ 14 px (12 on a phone-height screen), taps ≥ 44 px, after scaling (DoctorProbes.ui).
- The client never decides a price, a cap or a free seat: it shows what `StaffData` / `StaffRooms` say and fires `StaffAction`; the server re-checks everything.
- TEAM is a tray tile (`opts.tray`), plot-only (`opts.plotOnly`), icon `team`, shown once you have staff.
- SiliconCore is at the 200-local limit: no new top-level locals there.
- Room labels (spec §2): Garage `hq`, Lobby `lobby`, Engineering `eng`, Design Studio `studio`, Cafe `cafe`, AI Labs `labs`.
- Feedback: TRAIN = a small reward beat (sound, a ring at the button, the $/s counting up), not a big moment. MOVE = the person re-seats (already animated).
- Doctor gate before the PR; commit docs BEFORE the fingerprint.

## Review Focus

1. A row whose person is not seated (the waiting line): room is nil. The row reads "waiting for a desk", fit ✓ is off, MOVE still works.
2. A pin the server could not honour (pin = cafe, room = lobby): the card says "No free seat in Cafe" and the Cafe chip shows the pin.
3. StaffData changes while the card is open (a hire, a spin-off, a train): the card follows the same person by id; if they are gone the card closes to the list.
4. Cash changes while the card is open: TRAIN dims and undims without reopening.
5. A failed action (rate limit drops it silently; "need cash", "at max", "no free seat", "busy"): the button never stays stuck in a pending state.

---

### Task 1: The server sends what the card needs

**Files:**
- Modify: `src/ReplicatedStorage/Seating.lua` (add `Seating.rooms`)
- Modify: `src/ReplicatedStorage/StaffAction.lua` (`A.row` passes `fits`)
- Modify: `src/ServerScriptService/SiliconCore.server.lua` (assignDesks publishes `StaffRooms`; recompute passes `fits`)
- Test: `tests/offline/seating.spec.luau`, `tests/offline/staffaction.spec.luau`

**Interfaces:**
- Produces: `Seating.rooms(people, homes) -> { {key, room, seats, free} }` in the order hq, lobby, eng, studio, cafe, labs, only keys present in `homes`; `free = seats - (people pinned to key)`, which is `freeFor(..., nil)`.
- Produces: StaffData row field `fits` = sorted array of room kinds the role fits (`Econ.FIT[role]` keys, e.g. `{"hq","office"}`).
- Produces: player attribute `StaffRooms` = JSON of `Seating.rooms` (each entry also carries `room`, the fit kind).

- [ ] Tests first (seating.spec): rooms in ORDER, only present keys, `free` counts pins and matches `freeFor(people, homes, key, nil)` for every key, a key not in ORDER is ignored, a pin to a missing room makes no entry. (staffaction.spec): `row` returns `fits` as given, `{}` when missing, drops non-strings.
- [ ] Run `lune run tests/offline/run` → the new tests FAIL (no `rooms`, no `fits`).
- [ ] Implement; run → PASS. selene clean.
- [ ] Wire SiliconCore inside existing functions (no new top-level locals). Commit.

### Task 2: TeamView (pure: what every part of the screen shows)

**Files:** Create `src/ReplicatedStorage/TeamView.lua`; Test `tests/offline/teamview.spec.luau`.

**Interfaces (Produces):**
- `TeamView.ROOMS` (key, label) in spec order; `TeamView.label(key)`; `TeamView.TALENT` (Regular..Unicorn); `TeamView.SENIORITY` (Intern..Lead).
- `TeamView.sort(rows, by)`: new array. `"rate"`: $/s high→low, ties by talent high→low, then id. `"talent"`: talent, then $/s, then id. Bad/missing numbers sort as 0.
- `TeamView.train(stat, cash) -> {state = "max"|"poor"|"ok", price}`: max when level ≥ cap.
- `TeamView.chips(row, rooms) -> { {key, label, free, best, state = "here"|"full"|"ok"} }`: one per room present; here = pinned there; full = free < 1; best = `row.fits` contains the room's kind.
- `TeamView.note(row) -> string|nil`: "No free seat in Cafe" (pin not honoured), "Waiting for a desk" (not seated), else nil.
- `TeamView.why(reason) -> string`: the player's words for every server reason (busy, not yours, at max, need cash, already there, no free seat, bad stat/room/id, unknown).

- [ ] Write teamview.spec covering each line above, including Review Focus 1 and 2. Run → FAIL (module missing). Implement. Run → PASS. Commit.

### Task 3: TeamClient (the tile, the list, the card)

**Files:** Create `src/StarterPlayer/StarterPlayerScripts/TeamClient.client.lua`; Modify `src/ReplicatedStorage/UIKit.lua` (`UIKit.MENUS` gains `"Team"`).

- Landscape-first two panes like the Index (a phone held sideways is 360–390 tall, so a bottom sheet would cover the list): list (left, scrolling, a sort toggle on top) and card (right). ScreenGui `Team`, menu title TEAM, accent BLUE. `UIKit.fitMenu` scales it.
- Row (a 52 px button): role icon, name, "Star · Senior · Cafe ✓" (or the note), $/s.
- Card: name and subtitle; three stat blocks (label, "level / cap", a bar, TRAIN button with `UIKit.money(price)`, "MAX" at cap, dim when poor); MOVE TO chips (label + "N free", ✓ best fit, the pinned one highlighted, full greyed) plus AUTO (unpin); one line for the note or the last reply.
- Follows a person by id across StaffData updates (Review Focus 3), re-reads cash on change (4), clears pending on reply or after 1.5 s (5).
- A `BindableEvent` named `Open` under the ScreenGui (arg: list position to select) for the doctor probe.
- [ ] Write it; `lune run tests/offline/run` (uistyle.spec covers the file) → PASS; selene clean. Commit.

### Task 4: The doctor sees the screen

**Files:** Modify `src/ReplicatedStorage/DoctorProbes.lua` (`Probes.team`), `src/ServerScriptService/GameDoctor.server.lua` (team step).

- `Probes.team(args)`: fires `Team.Open` with 1, waits, returns `{rows, id, name, price}` from what is drawn, plus `Probes.ui()`; closes the screen after.
- Team step checks: "TEAM lists everyone" (rows drawn = StaffData rows, BUG); "card shows the server's price" (drawn TRAIN text = `UIKit.money` of that person's Skill price, BUG); cards over cards (FEEL), buttons something covers (BUG), text under 14 px (FEEL), taps under 44 px (BUG).
- [ ] Implement; run the doctor live; all team checks pass. Commit.

### Task 5: Live proof, docs, gate

- [ ] In Play: open TEAM by clicking the tile, TRAIN by clicking the button (cash falls by the price shown, the level rises, $/s rises), MOVE by clicking a chip (the person re-seats there), AUTO unpins. Screenshots at desktop size and a phone-landscape size.
- [ ] Docs: `docs/features/hiring-talent.md` (the screen), `dev-tools.md` (the probe), remap shifted line refs. Commit docs.
- [ ] Fingerprint (Edit) → full doctor (Play) → restore Wilz's save → `bas checkup pr --post`. PR with the intent card, label by `bas risk`.
