# HQ overhaul, project #1, part 1c: the garage becomes the lobby (design, 15 Oct 2026)

Luke, 14 Oct (tower spec §1 and §4): the first upgrade replaces the garage with the tower's lobby in a
~4 s build moment, through `Cine`; the garage never exists again for that company. Process
(CONSTRAINTS rule 17): references -> mocks -> Luke's pick -> spec -> plan -> build. References:
`silicon-startup/ui/2026-10-15-garage/REPORT.md` (24 items, all opened). Mocks:
`ui/2026-10-15-garage/garage-concepts.html` (script `art/blender/garage_concepts.py`). Builds on 1a
and 1b (branch `hq-tower`, draft PR #56); ships with 1d, never alone.

## 1. Luke's pick
**B's time-lapse, with A's garage fold at the start and C's garage photo at the end. No title card.**
(Recommended in chat, "yes" 15 Oct.)

| From | What |
|---|---|
| B, Time-lapse | Scaffold and a blue "still building" band; the lobby builds itself in steps (columns, glass, roof), a tick per step, one sting on the roof; then a low look-up at the glass. |
| A, Move that bus | At the start the garage walls fold flat outward, inside the scaffold: the player sees the garage go. |
| C, The reveal | After the moment a framed photo of the old garage hangs in the lobby: "WHERE IT STARTED". |
| Left out | C's "YOUR FIRST HQ" title card (the references: a popup after a reveal feels cheap). One short line replaces it. |

## 2. What the player sees (one moment, about 4.4 s)
Trigger: the BUILD tap that takes a garage (level 1) to the lobby (level 2). On a company's very
first build the finish picker (Glass / Timber / Neon) comes first, as today; the moment follows it.

| Time | What happens | Sound |
|---|---|---|
| 0.0 | Letterbox bars, the HUD and prompts hide (`Cine` does this). The camera pulls back from the player to a wide shot of the plot (0.6 s). Steel scaffold poles shoot up around the lobby's footprint. | a whoosh |
| 0.6 | The garage walls fall outward flat, like an opened box; the roof lifts and fades; the boxes and the wall TV fade. The floor, the desk, the laptop and the hire pad stay. | a thud as the walls land |
| 1.2 | The wood columns rise into place; a blue band wraps the top of the scaffold. | tick |
| 1.8 | The glass walls rise into place. | tick (higher) |
| 2.4 | The roof band drops onto the top. The frame holds for 0.15 s. | the sting (loudest) |
| 2.6 | The scaffold drops away; the canopy and the company sign appear. The camera moves to a low shot looking up at the glass. | |
| 3.6 | The camera flies back to the player at the desk (0.8 s). The HUD returns. | |
| 4.4 | One line: "Your HQ is open! Next: floor 1." (the existing `Notify`). | |

Every step moves as one group with a small overshoot, not part by part. **Skip** (the `Cine`
button, a tap or a key) at any time: a 0.3 s fade to the end state, the camera back on the player.

**Never:** the floor or the desk moves; the player falls, is moved, or is left in a different place;
the camera is left stuck (CameraType and CameraSubject both handed back); the moment plays on a
reload, a rejoin, a dev `hq:<n>`, or for anyone but the owner; a popup after it; over 4.5 s.

## 3. When it plays
- **Plays:** each time a BUILD tap turns this plot's garage into the lobby: the first company, and
  the first build after each spin-off (the new company starts in a garage again, tower spec §4).
- **Never:** loading a save (`SaveLoad` rebuild), a rejoin, `releasePlot`, a dev `hq:<n>`, a build
  that does not start from level 1.
- **Open question for Luke (default chosen):** the 14 Oct pass rule says "never on a rebuild after a
  spin-off-and-back". This spec reads it as "never on a reload or rebuild", and plays the moment again
  after each spin-off, because the player is back in a garage and gets it back. If Luke wants it only
  once per player ever, the change is one condition (`s.record < 2`).

## 4. Who sees what (multiplayer)
- **The server builds the real lobby at once, as today.** Nothing in the final state depends on the
  moment: a visitor, a late joiner or a client that skipped sees the finished lobby.
- **Only the owner's client plays the moment.** It hides the new lobby's parts locally, animates them
  back group by group, and puts every part exactly where the server has it at the end (a snap on
  finish, also on Skip and on any error).
- **The garage fold needs the garage after the server has stashed it.** The owner's client keeps a
  local copy of the garage's look while the plot is at level 1; the fold animates that copy, then
  deletes it.
- Visitors standing in the garage see it vanish and the lobby appear in the same frame (as today).

## 5. The garage things in the lobby (tower spec §4: "things that lived in the garage move")
- The WRITE CODE laptop, the desk and the hire pad already stand in the lobby's centre hall (1a).
- **The garage chair is moved clear of the lift shaft.** Today the kept `Chair` stands at (4.6, -6.0),
  where it reaches into the shaft and the cab glass (the 1b "Ada clips the cab" finding). It moves to
  the `GARAGE_SPOTS` chair spot (2.5, -6.2), and a test keeps every kept garage part clear of the shaft.
- **The wall TV goes onto the lobby's back wall**, beside the photo (its bar-chart screen as today).
- **The photo:** a framed picture of the garage with "WHERE IT STARTED" under it, on the lobby's back
  wall, built with the lobby (so it is there for everyone and after every reload). Plain parts and a
  SurfaceGui now; the art is 1d.

## 6. Under the hood
- **A pure `LobbyMoment` module** (tested offline): the timeline (each step's start, length and
  sound; the camera shots' times), `at(t)` -> how far each group is (0..1, with the overshoot), the
  total (<= 4.5 s), and what Skip jumps to. Group names: scaffold, garage, columns, glass, roof,
  canopy.
- **The server** (`wafersBuild`) fires one remote to the owner, `LobbyMoment`, when a BUILD takes this
  plot from level 1 to 2, after the pieces are built.
- **Wafers** tags the lobby's parts with their group (an attribute), builds the photo and the TV, and
  fixes the chair. No saved data changes.
- **A client script** plays it: the garage copy, the scaffold and band (client-only parts), the
  groups, the `Cine` shots, the sounds (existing `UIKit.sfx` sounds; recorded audio is out of scope),
  Skip, and the final snap. It leaves nothing behind.

## 7. Pass rules (written before any results)
1. **Offline:** the timeline's steps are in order and do not overlap more than planned; the total is
   at most 4.5 s; every group ends at exactly 1 (in place); Skip from any time gives the end state;
   the chair and every kept garage part stand clear of the lift shaft; the photo and the TV stand on
   the lobby's back wall and clear of the shaft and doorways.
2. **Live (Studio, as Wilz):** from a garage, BUILD to level 2: the moment plays once and ends within
   4.5 s; the player is within 0.5 studs of where they stood and on the floor; the camera is Custom
   with the player's Humanoid as subject; every ScreenGui and prompt that was on is on again; every
   lobby part is visible and exactly where the server has it; the garage copy, the scaffold and the
   band are gone; 0 script errors. Skip at 1 s: the same end state within 0.4 s. A reload, `hq:2`
   and `hq:5` do not play it. The doctor's full run still passes (no new BLOCKER or BUG).
3. **Look:** frames from the live moment (start, fold, columns, roof, look-up) and the photo, compared
   with the mocks by a fresh reviewer.
4. **Phone:** the moment at a phone-size window: the letterbox, Skip and the last line fit; no frame
   longer than about 50 ms in the Studio measure (not a real phone; marked as such).
5. **The gate:** `bas checkup pr` passes.

## 8. Out of scope
The art (1d: the scaffold's look, the real photo, materials, the music sting), recorded sounds (need
audio uploads), the scaffold on later tower floors (a later idea), the wall TV's income (project #5),
the two-player test (later, Luke).

## 9. Risks
- **The garage copy:** if the client never saw the garage (it streamed in late), the fold has nothing
  to show. Then the moment starts at the scaffold step; no error.
- **Phone frame rate:** the moment moves up to three groups at once. Each group moves as one model,
  and the measure in rule 4 is the check.
- **The finish picker before it:** the picker closes, then the moment starts; the two must not fight
  over the camera or the HUD.
