# HQ overhaul, project #1, part 1b: the lift (design, 15 Oct 2026)

Luke, 15 Oct: "I don't want it to just be a stock elevator, even though it's a very small part of the
game loop." Process (CONSTRAINTS rule 17): references -> mocks -> Luke's pick -> spec -> plan -> build.
References: `silicon-startup/ui/2026-10-15-lift/REPORT.md` (43 items, 38 opened). Mocks:
`ui/2026-10-15-lift/lift-concepts.html` (script `art/blender/lift_concepts.py`). Builds on the tower
from 1a (branch `hq-tower`, PR #56); ships with 1a, 1c and 1d, never alone.

## 1. Luke's pick
**A's trophy panel + C's voice, with B's room label.** (Recommended in chat, "yes" 15 Oct.)

| From | What |
|---|---|
| A, Trophy | A clear glass cab in the glass core. The cab panel is a trophy board: one socket per stop; a built floor's button is lit, a new one arrives with a gold flash and "NEW!"; floors not built yet are empty sockets. One big floor number above the doors. |
| C, Personality | A calm announcer and a sign that talks ("GOING UP!", "PLEASE REMAIN CALM :)"); rare, harmless events. |
| B, Tour | The room label next to the floor number above the doors ("7 · STUDIO"). |
| All | Lit call button, tick per floor + louder last tick + ding, a real ride (1 s per floor, never over 4 s), riders held steady in the cab, the big phone floor list. |

## 2. What the player does (one ride)
1. **Walk up to the doors.** A prompt "Lift" shows. Tap it (E / tap): the call button lights amber
   and stays lit until the doors open.
2. **The cab comes.** If it is on another floor it rides to you (same speed as a ride; the counter
   above the doors counts). If it is already here (the usual case: you came up in it), the doors open
   at once. Doors open in 0.5 s.
3. **Step in.** Entering the cab opens the floor list (phone and desktop), and the trophy panel
   in the cab can be clicked too (desktop). The floor you are on is greyed "You are here".
4. **Pick a floor.** It lights above the doors inside ("did it take my tap?" is answered). The doors
   close in 0.5 s; nobody can step in once they start closing.
5. **The ride.** 1 s per floor, capped at 4 s (12 floors still take 4 s). A quiet tick per floor
   passed, a louder tick on the last, then the ding. The counter inside and outside shows the floor.
   The camera holds a steady view inside the cab facing the doors (no camera inside walls).
6. **Arrive.** Ding, the doors open, the counter shows "7 · STUDIO", the player walks out.

Longest case: call wait 4 s + doors 1 s + ride 4 s = 9 s. Usual case (cab already here): about 5 s.
Today's fade-and-teleport takes about 1 s; the ride is the point (research: a teleport reads as a
loading screen), and the cap keeps it far under the 14-52 s rides players complained about.

**Never:** a ride over 4 s; a door that opens onto an empty shaft; a rider who shakes or falls
through the cab; a voice line that delays the doors.

## 3. Multiplayer and who may ride
- One cab per tower. Anyone standing at the tower's lift may ride it (as today: `LiftGo` checks
  you are within 16 studs of one of THIS tower's stops, not Carrying, a 1.2 s cooldown, and stands
  you up from a car first).
- Calls queue: the cab serves them in order; riders already inside go first. Everyone inside rides
  together. While the cab is moving, doors stay closed everywhere.
- More than 6 riders: the sign says the "maximum capacity" joke and the doors stay open until
  someone steps out (C's personality).

## 4. The trophy panel (the A part)
- One socket per possible stop, bottom to top: LOBBY, then every storey that is not a garden (the
  floor above a garden carries "TERRACE"), then ROOF GARDEN. A built (landable) stop is a lit button
  with its number; an unbuilt one is an empty dark socket.
- When the player builds a piece that makes a new stop, the next time they enter the cab that
  button pops in with a click, a gold flash and "NEW!" (once). Seen-state is per session; nothing
  new is saved.
- The panel is decoration that also works: on desktop, clicking a lit button picks that floor.

## 5. The voice (the C part)
- The sign over the inside of the doors shows: "GOING UP!" / "GOING DOWN!" while moving, the floor
  label on arrival, and rare lines.
- Rare events, at most one per ride, about 1 ride in 12, never on a player's first 3 rides, never
  longer than the ride:
  - "PLEASE REMAIN CALM :)" with one ceiling panel flickering off for half a second;
  - "THIS LIFT WAS BUILT BY " + the player's own company name (a little pride line);
  - "MAXIMUM CAPACITY. SOMEONE HAS TO GO." (only when over 6 riders; doors wait).
- Sound: 1b uses existing sounds (`UIKit.sfx` ding, a tick). Recorded voice lines need audio
  uploaded to Luke's account, so they are out of 1b: the sign carries the voice now.

## 6. Above the doors (every landing and inside)
One fat number and an arrow, plus the room label of that floor: the department with the most built
rooms on it (a tie: the lowest seg's), coloured in its department colour; "LOBBY", "TERRACE",
"ROOF GARDEN" for those. The landing display shows where the cab is now.

## 7. The shaft and the cab (geometry)
- The shaft stays where 1a put it (`TowerPlan.SHAFT`, x 5..13, z -12..-2), glass walls, the 6-wide
  door gap on +Z. **The cab** fills it (about 7.2 x 9.2, 10 studs tall), glass back and sides, a
  paper floor and ceiling with a light panel.
- **The landings and deck slabs stop at the shaft** (they span it in 1a; the 1a review flagged it):
  the landing floor becomes the centre hall minus the shaft; garden decks get a hole over it.
- **Landing doors** (two leaves in the door gap) on every stop, closed unless the cab is there; a
  closed door is solid. The doctor's stop stand point stays on the landing in front of the doors.

## 8. Under the hood
- **A pure `LiftPlan` module** (tested offline): the stop list from the pieces and the level (from
  `TowerPlan.landable`), each stop's floor y, ride time (1 s per floor, cap 4 s) and the tick times,
  the call queue and the cab's state machine (idle, doors opening, open, closing, moving), the
  trophy sockets, the floor label, the rare-event roll (seeded, with the rules in section 5).
- **The server owns the cab's state**, as attributes on the cab model: state, from-stop, to-stop,
  start time, duration. It moves nothing every frame.
- **Every client animates the cab itself** from those attributes (smooth for riders and watchers),
  and the doors with it. The server sets the cab's final position when a ride ends, and door
  collision on every state change.
- **Riders are held by their own client:** while riding, the client anchors its own character and
  places it relative to the cab every frame (the "move with the cab" fix from the DevForum thread
  in the references); when the ride ends it lets go on the new floor. A rider who leaves the cab's
  box during a ride is placed back (and checked by `Movement.check`, as today).
- `LiftClient` keeps the floor list (rebuilt as the big phone list from the mock); the fade and
  the teleport go. `HQFloors.LiftGo` becomes "call" and "pick" with the same checks.
- No save change.

## 9. Pass rules (written before any results)
1. **Offline:** ride time is 1 s per floor and never over 4 s; ticks equal the floors passed; the
   cab never stops between stops; the queue serves riders inside first, then calls in order; the
   trophy shows exactly the landable stops lit at every level 2..100; the label rules; the rare
   event never fires on rides 1-3 and never twice in a row.
2. **Live (doctor + a live ride):** ride from the lobby to every stop at HQ 100 and back: the rider
   stays inside the cab box every frame (no shake over 0.3 studs, no fall), arrives standing on the
   stop's floor, ride times within 0.2 s of the plan; doors are solid when the cab is away; a player
   cannot walk into the shaft at any stop; two players: one calls while the other rides, both get
   served.
3. **Phone:** the floor list at 375-wide: rows at least 44 px after scaling, nothing cut off
   (the doctor's UI checks).
4. **Look:** the landing and the inside compared with mock A (and C's sign) by a fresh reviewer.
5. **The gate:** `bas checkup pr` passes.

## 10. Out of scope
The art (1d: the cab's materials, the crown, door frames), the garage-to-lobby moment (1c), recorded
voice lines (needs audio upload), lift music, cosmetic door/chime unlocks and lift-speed upgrades
(good ideas from the research; later).

## 11. Risks
- **Rider movement on Roblox** is the hard part: client-held riders must not fight physics or the
  anti-exploit `Movement.check`. The pass rule measures it every frame.
- **Longer than today:** about 5 s usual vs about 1 s now. If it feels slow in a playtest, the
  first lever is the cab waiting at the most-used floor, not a shorter ride.
- **Rotated plots** (4 of 6 at 60 or 120 degrees): everything is placed in plot space, as in 1a.
