# TEAM screen redesign + the anti-slop system — design (14 Oct 2026)

Approved in conversation, 14 Oct. Luke: the phase 3 TEAM screen (PR #55) is "pretty
sloppy"; make it extremely good, and fix the system so UI stops shipping sloppy, before
moving on. He picked **Option 2 (the showroom), with its weakness removed (no tabs)**.

Repo: `Downloads/silicon-startup/game`. Re-check every file:line before editing.

## 1. Why the old screen was sloppy (and why nothing caught it)

Measured against DESIGN.md's own principles, the PR #55 screen breaks all five rules
taught in UI School (artifact `claude.ai/artifact/EX5zrmzCK2KmgZZR1qDy2z`):
1. One loud thing: three identical green TRAIN buttons, a pale-blue SORT bar the size of a header, purple discs.
2. Show, don't write: rows of identical text ("Genius · Lead · $12.9K/s"), no faces.
3. Say it once: $/s and talent/seniority in the row and on the card.
4. Big and solid: 8 px grey bars with the level off to the side.
5. Space, not boxes: rows, chips and the sort bar are the same rounded box; the second chip row was cut off.

The doctor measures geometry (overlaps, text ≥ 14 px, taps ≥ 44 px) and `uistyle.spec`
checks tokens. Nothing checked composition, and the screen was built in code with no
reference and no mock for Luke to approve. Sections 3 and 4 fix that.

## 2. The screen (Option 2, no tabs)

References: `ui/references/` Board A (Showroom, Squad, Hangar rows, Character cards).
Mock Luke picked: `ui/2026-10-14-team/mockups.html#o2` (clickable), screenshot `mock-o2.png`.
The built screen must match the mock's layout; colours and type come from UIKit tokens.

**Layout** (a phone held sideways is 360–390 px tall; drawn at 844 x 390):
- **Menu**: ScreenGui `Team`, header TEAM (blue) with "N people" and the round close.
  744 x 368 drawn, placed right of the rail, fit-scaled by `UIKit.fitMenu` like every menu.
- **Left column (80 wide): faces.** One 56 px tile per person, sorted by $/s, scrolling.
  The tile is the person's **real head** (a ViewportFrame showing a clone of their rig),
  with a 3 px outline in their talent colour (`UIKit.TIER`). The selected tile gets a gold
  outline and lifts 2 px. No text in the column.
- **Middle: the person.** Their **real character, full body**, in a ViewportFrame (the hire
  reveal's pattern, `TalentRevealClient`), on a soft glow tinted by talent (Genius purple,
  Unicorn gold, others paper). Under it: name (Fredoka 26), talent pill + role · seniority
  (one line), $/s in the money style (24). Then **the rooms row**: one 52 x 52 button per
  room the HQ has (icon only: Garage, Lobby, Engineering, Studio, Cafe, AI Labs), in
  `Seating.ORDER`, 6 px apart (6 rooms = 342 px, inside the middle column). The room they sit in now has a gold outline; best-fit rooms carry a
  green ✓ badge; a full room is faded. Under the row, one line: "✓ AI Labs · pinned", or
  the note when a pin is not honoured ("No free seat in Cafe") or they wait for a desk.
  Tap a room = move and pin there; tap the room they are pinned to = unpin.
- **Right column (300 wide): TRAIN.** A small "TRAIN" label, then one row per stat:
  stat icon (Skill = coin, Speed = bolt, Loyalty = heart), name, "level/cap", the price
  button (96 x 52), and under it a **block meter**: one block per level up to the cap,
  filled blocks blue, all gold at the cap.
- **One loud thing:** the Skill price button is the only green element, and only when it
  can be bought. Speed and Loyalty prices are paper buttons. A stat at its cap shows a
  gold MAX button (not loud). A price you cannot afford is a dim paper button.
- **Feedback** (unchanged rules from phase 3): TRAIN → the new block pops, a green ring at
  the button, the $/s counts up; MOVE → the person walks to the new room (in the world)
  and the gold outline moves. A refusal shows its reason in the line under the rooms for
  4 s (TeamView.why).
- **Every tap ≥ 52 px drawn** (stays ≥ 44 after fit-scaling to a 360-tall phone).
- **Gone from the old screen:** the SORT bar (the face column is always by $/s), the
  list's text rows, the per-stat blurbs, repeated $/s and talent text, the room text chips.

**Rendering budget (phones):** at most 9 live ViewportFrames while TEAM is open (1 body +
the 8 face tiles in view); tiles scrolled out of view release their clone. Nothing renders
while the screen is closed.

**Data:** everything comes from phase 2/3's `StaffData` and `StaffRooms` (unchanged) and
`TeamView` (pure; kept, gains what the new layout needs, tested offline). One server
addition: `spawnStaff` stamps the rig with attribute `StaffId` so the client finds a row's
rig in its plot. No rule moves to the client.

## 3. Automatic slop checks (the doctor sees composition, not just geometry)

`DoctorProbes.ui` gains three measurements, reported for every screen it already probes
(the HQ level-up cards and the TEAM screen), each with a fixed rule:

| Check | Rule (measured on the player's screen) | Severity |
|---|---|---|
| **Loud buttons** | Visible, active GuiButtons whose face (`Face` attribute, else BackgroundColor3) is a saturated role colour (UIKit GREEN, BLUE, ORANGE, RED, PURPLE, GOLD; not their -light tints) inside one open menu: **at most 1**. HUD outside menus is not counted. | FEEL |
| **Said twice** | Two visible non-button TextLabels in the same ScreenGui with identical text of 4+ characters. | FEEL |
| **Cut off** | A visible TextLabel/TextButton whose `TextFits` is false, or a visible GuiButton whose rectangle extends past its nearest `ClipsDescendants` ancestor that is not a ScrollingFrame. | BUG |

Each rule gets an offline test of its pure core (a list of rects/colours/texts in, findings
out), so the judge itself is tested, and a planted-slop live check: the old PR #55 screen
must fail "loud buttons" (3) and the new one must pass.

## 4. The process rules (so the next screen starts right)

- **CONSTRAINTS.md rule 17 (UI):** a new or changed screen needs, in order: a reference
  board in `ui/references/` (real games; Luke's picks), clickable mocks at 844 x 390 in
  `ui/<date>-<screen>/`, Luke's pick written into the spec, then code. The PR shows the
  built screen side by side with the mock Luke picked.
- **Match-the-mock review:** before Luke sees a built screen, a fresh reviewer gets the
  mock screenshot, the in-game screenshot and the 5 rules, and must name each concrete
  difference or rule break (same must-name-a-failure rule as code review). Fix, then show.
- **DESIGN.md amendment:** menus stay max 560 wide, except a full character screen (TEAM),
  max 760, which must leave the rail visible. Add the 5 rules (one loud thing, show don't
  write, say it once, big and solid, space not boxes) to §6 as the review checklist.
- **UI School stays** as the shared vocabulary; reference boards are per screen job.

## 5. Verification (pass rules, written before any results)

1. Offline: TeamView additions tested; each slop-check core tested with planted cases
   (3 green buttons → 1 finding; same text twice → 1; TextFits false → 1; clean → 0).
2. Live, real clicks in Studio Play: TRAIN Skill charges exactly the shown price and the
   $/s rises x1.065; a room tap pins and re-seats; tapping the pinned room unpins; MAX and
   unaffordable states render; the selected face follows a tap.
3. Doctor `team` step, at the doctor's viewport: every existing check passes (lists
   everyone, server's price, 0 overlaps, 0 covered, 0 small text, 0 small taps) **plus**
   loud buttons ≤ 1, said twice = 0, cut off = 0, live ViewportFrames ≤ 9.
4. Match-the-mock review finds no unresolved difference.
5. `bas checkup pr` gate passes.

## 6. Delivery

The redesign goes on the `staff-phase3` branch and updates PR #55 (unmerged; its server
data, TeamView, StaffRooms and doctor probe stay; only TeamClient's drawing is replaced).
One PR ships one good screen instead of a sloppy one plus a fix.

## 7. Out of scope

The TEAM screen's mechanics (prices, caps, the price trick, the Loyalty clamp: still Luke's
open decisions); redesigning other screens (they get boards and mocks when touched, under
rule 17); a portrait (vertical) phone layout; the wall TV (phase 4).
