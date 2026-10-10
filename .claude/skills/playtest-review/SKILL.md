---
name: playtest-review
description: Review Luke's screen recordings of Build a Startup! the same way every time (contact sheets, what he said, what the game printed) and turn each problem into a finding with a repro and a guard. Use when he sends a recording, says "check my playtest / my clips / the video", or on the playtest routine.
---

# Playtest review

His 23-second recording of 10 Oct found the week's two worst bugs (no drop-off,
sinking through the park). No check we had saw either. A recording is the only
proof of what a player actually meets, so every one gets reviewed, and every
problem in it ends with a GUARD: the check that would have caught it.

Report only, unless he asked for fixes: this skill never commits, publishes or
edits the game. Review output lives in `silicon-startup/playtests/` (outside git).

## 1. Find what is new (game folder)

    lune run tools/bas playtest list

- `new`: a Roblox log says OUR game was running (Studio Play, or the live game or
  the TEST place in the Roblox app) while it was filmed. Not yet reviewed.
- `not ours`: no session of this game overlaps it. Do not open it: his Videos
  folder holds other things too.
- `reviewed` / `skipped`: in `../playtests/reviewed.json`.

## 2. Prep

    lune run tools/bas playtest prep "<file name>"     one recording
    lune run tools/bas playtest prep --new             the last 3 days (--days N)

It writes `../playtests/<name>/`:
- `sheet_NN.jpg`: 6 frames per sheet, one a second, the time burned in top left
- `notes.md`: which build he was playing and when he joined; what he SAID
  (faster-whisper, `[m:ss] text`); what the game printed while he filmed, on the
  video's clock (Studio logs every print; the Roblox app's log only errors);
  an empty findings table

## 3. Look at sheet_01 FIRST

A running game does not mean the recording shows it (8 Oct: Studio ran while he
recorded another window). If sheet_01 is not the game:
`bas playtest done "<name>" --skip --note "not the game"`, delete that folder,
and move on. Never describe or quote what else was on his screen.

## 4. Review

Read every sheet in order, then the speech, then the game lines. For each thing that
is wrong or feels wrong, one row:

| t | what I see | feature page | severity | repro | guard |

- **t**: the burned-in time. Ranges for things that last (`0:12-0:16`).
- **what I see**: plain words, what a player meets ("the screen is the inside of
  a roof for 4 s"), not a guess at the cause.
- **feature page**: the `docs/features/*.md` page it belongs to.
- **severity**: BLOCKER (the loop stops: lost the hire, stuck, can't find it),
  BUG (wrong, playable), FEEL (works, feels bad), QUESTION (ask him).
- **repro**: the shortest way to see it again (an SVDev scenario if one fits:
  `lune run tools/bas scenario list`).
- **guard**: the check that catches it. Name an existing one if it already
  does (WorldHealth.sinking, TalentDrop.health, a spec), else `NONE` and what
  it should be. A suspected cause goes here marked `(unverified)`.

Then check each finding against `main`, not just the build he played:
`notes.md` says when he joined; `bas ship` and the Studio log say what was
published when (`PublishPlaceTime`). A bug main already fixes is
`FIXED on main by #N, not live yet`, which is a reason to publish, not a new bug.

What he says out loud is the best evidence there is: file each ask as a row in
his words, even when the frames show nothing wrong.

## 5. File it

Fill the table and the Verdict in `notes.md` (build played, new and open
findings), then:

    lune run tools/bas playtest done "<name>" --note "<one line>"

## 6. Report

Short, plain words, no em dashes. Findings ordered BLOCKER, BUG, FEEL. For each
new one: the time, what he would see, and the guard it needs. Say plainly what
was checked against main and what was not. Then ask which to fix; a fix ends
with its guard in place (`bas check` green) and is proven live per the
verify-game skill.
