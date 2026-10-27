# The chase, made dangerous: spec (8 Oct 2026)

From the 00:47 recording and his notes: "if you just go in a straight line, the thing cannot
catch you ... there's basically no skill required ... you just spam the shift". Also: lock the
mouse (decided), a wind-up, random chases (genius almost always), and a "whoa" he isn't getting.

## What the recording shows (measured)

- Genius run, HQ 4, carry speed 19. Delivered in ~9.5 s holding forward. Never lunged at.
- The camera sat 30-39 studs back (the "frame the hunter" rule). Both figures are tiny, so there
  is nothing to be afraid of on screen.

## Why it can't catch you (root cause, from ChaseRules)

1. Hunter speeds scale with the tier's REFERENCE scooter (genius = 18), not the one you ride.
   At HQ 4 you ride 19. Its jog (0.94 x 18 = 16.9) is slower than you, so you pull away.
2. It sprints only past FAR = 20, and it lunges only inside 13. Holding W, it hovers at about 20,
   in the gap between, and never lunges. A dead band, so there's no threat at all.
3. The simulator missed both: its players weave at 95% speed, at exactly the reference speed.
   A real player holding W runs 100%, at whatever speed they've upgraded to.
4. The lunge homes in on you the whole time, so steering can't dodge it. Only BOOST can, and
   BOOST on cooldown is the whole skill. That's why it feels like spamming Shift.

## Phase 1: tonight

| # | Change | Why |
|---|---|---|
| 1 | **Mouse locked during the chase.** No right-click. Moving the mouse steers. Cursor hidden, restored after. | His decision. |
| 2 | **The hunter keeps up with the scooter you actually ride.** Its sprint and stalk scale with your real carry speed (never below the tier's). | Cause 1. |
| 3 | **Stalk, don't hover.** Inside the band it closes slowly (genius 1.04x you, star 1.02x, skilled 0.99x) until it's in lunge range. | Cause 2. |
| 4 | **The lunge commits.** At the end of the tell it picks a direction (where you're heading) and goes straight. Turn hard during the tell and it misses. BOOST still works, but the cooldown (5 s) is longer than the lunge cycle (3.2 s), so spamming covers half the lunges at best. | Cause 4. Skill = read the tell, then steer or boost. |
| 5 | **Lunge speed stays tied to the tier.** A faster scooter makes lunges easier to outrun. | Upgrades stay an edge. |
| 6 | **Camera: close, always.** Drop the far "frame the hunter" placement. The camera stays ~12 studs behind you, and the lens-clear rule keeps the hunter from filling the frame. | Tiny figures at 35 studs. Keep the camera simple. |

**Done when, simulator (2,000 runs, same code the server runs):**

| Genius, at the speed you ride (18 and 20) | Target |
|---|---|
| Holds W perfectly, never boosts (the exploit) | caught **50% or more** |
| Spams BOOST whenever it's ready | caught **35% or more** |
| Steers on the tell (75% of tells) | escapes **80% or more** |
| Boosts on the tell (75% of tells) | escapes **80% or more** |
| Freezes 1.5 s / stands 3 s | caught |

Skilled, holding W: escapes 90% or more. Star: 50-85%.

**Done when, live:** a scripted straight-line genius run in Studio gets lunged at, and gets caught in
at least one of three runs. A scripted run that steers on each tell escapes.

## Phase 2: after he plays Phase 1 (his call on each)

- **The reveal:** on pickup, a 0.8 s beat. The hunter stops, turns, spots you ("!" and a sting),
  then runs. Chance of a chase by tier: skilled ~35%, star ~65%, genius ~95%. No chase means a calm carry.
- **The intercept:** genius only. A second hunter steps out AHEAD from a side street, so you have to
  curve around it. Uses the new mouse steering.
- **The stakes, shown:** when caught, a 1.5 s cutaway of the hunter walking off with your hire.
- **The whoa:** a near miss (lunge dodged inside 8 studs) gets a hit-stop. FOV punch, whoosh,
  the camera holds for 0.25 s, and a "CLOSE CALL" stamp. Client-side only, no server slow-mo.

## Avoid

- Rubber-banding you can see (a hunter that teleports or obviously speeds up off-screen).
- Catches that feel unfair: a lunge with no tell, or a catch from beside or ahead without warning.
- More camera systems. Phase 1 deletes one.
- Tuning by feel without the simulator table, or the simulator without a live run.
