# Clients at the door: the new core loop (design)

**Date:** 16 Oct 2026. **Repo:** `Downloads/silicon-startup/game`, from main `c58ef2c` (v602 live).
**Status:** written from Luke's "A and B together" (16 Oct) and his OK on the Tizzy playback.
Not yet approved. Mocks and Luke's pick (rule 17) come before any code; see "Screens".

## Why

Luke recorded a fresh account on the live game (v602, `ui/references/e0-first-minute-ours.mp4`, 1:51).
His verdict: "I don't think it's good. Not just the video, but the loop."

What the recording shows:
- The main thing a player does is **tap a WRITE CODE button**. Money also comes in at $3/s on its own.
  Nobody in the world wants anything from you. What you do with your hands barely changes your income.
- The first minute is fast (first app at 0:22, garage to lobby at 1:04), but it has **two popups**
  (naming 0:34-0:48 with the keyboard over the screen; the building pick 0:58-1:02 with cards too small to read).
- After the lobby there is **no goal**: four messages stack at once (1:08), then 35 s of wandering.

The reference board (`ui/references/board.html`, boards E-H, Luke's pick 16 Oct = the Steal lists as written)
points at Sell Fries! (released Sept 2026, ~60K playing): you do a job with your hands at a station,
a customer at the window has a speech bubble and a patience bar, you hand over the order, the cash pops.

Tizzy's lessons (his transcript, `Downloads/This video is called I made three v.txt`), which this design follows:
1. **The first payout is a wow.** His first feed made the pet 5x bigger than normal "to teach that wow moment".
2. **Teach only the core loop, then set them free:** get the thing, get money from the thing, progress.
3. **Contextual tutorials:** teach a system the moment the player needs it (food is taught when you run out).
4. **Let them feel one upgrade before teaching the next.** Don't context-switch fast.
5. **Track every step,** so you can see where players drop.

## The moment we are building toward

You hand your first app to your first client. The client cheers, cash bursts out (far more than a normal job),
and a second client is already walking up. Soon clients arrive faster than you can code, and that is why you hire.

## Goals

1. **A new core verb.** Clients walk up to your door and ask for an app. You code it at your desk by holding a
   button. You carry it out and hand it over. You get paid, with a tip for speed.
2. **The first client is the tutorial and the wow.** No timer, a scripted ask, a payout about 5x a normal job.
3. **Hiring is taught when the queue backs up** (contextual), and a hired coder works client jobs on their own
   (like Sell Fries' Auto Peeler). The player "moves up": greets clients and takes BIG clients only they can do.
4. **Zero popups in the first two minutes.** The company gets a generated name; the building style defaults to Glass.
5. **One goal on screen at a time,** top-centre, two to five words, with a path on the floor to where it happens.
6. **Fix the five first-minute bugs** (list below).
7. **Track the new loop** in the funnel and as events.

## Non-goals

- No change to the economy past the first company's early game: staff income per second, launches and markets,
  HQ prices, momentum, spin-offs and IPO keep working as they do today. Client pay is added on top.
- No Demo Day, no walk-in showroom, no daily perks (board I ideas; later).
- No monetization.
- No redesign of screens other than those listed in "Screens".

## Anti-goals (would make this a failure even if it works)

- **The new verb is slower or more boring than the tap it replaces.** If the first client takes longer to serve
  than three taps took (0:12 to 0:22), or holding feels like waiting, it failed.
- **The first minute gets longer.** Garage to lobby must stay at or under ~1:10 for a player who does the obvious thing.
- **A popup, a wall of text, or two goals at once** in the first two minutes.
- **Clients punish a new player.** Losing a client must cost a little, never stall progress.
- **More systems, not a better loop.** If the build adds a system the first two minutes don't need, cut it.

## The loop, step by step

**1. A client arrives.** An NPC walks up the street to your front door (the garage door; later the lobby entrance)
and stops in a queue spot outside. Above them: a speech bubble with what they want ("A to-do app!") and a
patience bar. Up to 3 wait in line; the first in line is "at the door".

**2. You code it.** Go to your laptop and hold WRITE CODE (the existing big HUD button; on PC also hold the
laptop's key). While you hold, your character types (sits or stands at the desk), a progress bar over the laptop
fills, and the button fills too. Let go and it pauses; it does not reset. A job is sized in work units; your speed
is work per second. Holding away from the laptop does nothing; the button then reads "GO TO LAPTOP" and the floor
path points there.

**3. Shipped.** When the bar fills: the pop word **"SHIPPED!"** over the laptop, and you are holding the app
(a small glowing box in your hand).

**4. Hand it over.** Walk to the client at the door. In range, the hand-over is automatic (no extra tap).
The client reacts (cheer, a line like "Just what I needed!"), cash pops into your counter, the client leaves.
Pay = a base for the job + a speed tip if the patience bar was still above half.

**5. The next client** is already on the way. The queue refills over time.

**If patience runs out,** the client leaves sad ("Too slow..."). You lose that job only. No cash is taken.

**Job pay scales with the company,** so clients stay worth serving after the garage: a job pays at least a floor
amount, or a few seconds of your income, whichever is larger (the same idea as today's tap, which pays
max($5, 0.18 s of income)). The builder tunes the numbers; the targets are in "Pacing".

## The first client (the tutorial)

- Spawns at once on a brand-new save, already at the door, asking for "a to-do app". It replaces today's
  "tap the laptop 3 times" first app; serving it is the first ship (`first_ship`).
- No patience bar on this one.
- The job is short: about 3 seconds of holding.
- The payout is the **wow**: about 5x a normal early job, with a bigger cash burst and the client cheering.
- The goal line walks the three steps only: "Code the to-do app" (arrow to the laptop), "Take it to your client"
  (arrow to the door), then nothing for a beat while the cash lands.

## Teaching the rest when it's needed

| System | Taught when | How |
|---|---|---|
| Hiring | 2 or more clients are waiting (the queue backs up) | Goal line: "Too busy! Hire a coder", path to the HIRE pad. The first hire stays free. |
| Coders work jobs | Right after the first hire | One toast: "Your coder takes the small jobs." The coder sits and starts on the client at the door. |
| HQ upgrade | Cash first reaches the upgrade price | Goal line: "Upgrade your HQ", path to the pad. |
| Company name | It already has a generated name from the start | After the garage-to-lobby moment, one toast: "Tap your sign to rename it." Tapping the sign opens today's name box. Never forced. |
| Building style | The first floor **above** the lobby | Today's picker moves here (from the lobby build). It must restyle the lobby too. Cards big enough to read on a phone (tap targets 44 px or more, per MenuFit). Default if closed: Glass. |
| Launches and markets | As today (when the product bar first fills) | Unchanged. |
| More room | The garage's one seat is taken and the queue backs up again | Goal line: "Upgrade your HQ" (the lobby fits more people). |
| Street recruiting | After the lobby, the first time a seat is free and the queue backs up | Goal line: "Recruit on the street", path to the sidewalk. Replaces the "SEATS FULL" sign showing right after the first hire. |

## Coders and "moving up"

- A seated coder works the job of the client at the door when you are not holding WRITE CODE on it.
  Coders are slower than you at first. Their speed comes from the staff stats that already exist (tier, skill).
  A job a coder finishes is handed over by itself (no carrying) and pays the base only, no speed tip.
- More coders = more jobs at once (one job per seated coder, front of the queue first). The queue grows with
  the HQ level, so the line keeps pressure on you to hire and build.
- **BIG clients:** from the lobby on, now and then a gold-bubble client arrives who only the player can
  serve (coders skip them). Bigger job, bigger pay (about 5x a normal job). This is "moving up": you greet the
  big ones while your team handles the rest.

## Pacing targets (the builder tunes numbers to hit these)

Measured with the existing bot (`dev:Invoke("bot", ...)`) and one recorded human run on a fresh save:
- First client served: **by 0:15** after spawning.
- First hire: **by 0:40.**
- Garage to lobby (first HQ upgrade bought): **0:55 to 1:10**, as today.
- A player who stands still after the lobby is never without a goal line.
- Later milestones (HQ 3, HQ 5, spin-off) land no later than on main today, within 10%. Measure that baseline
  with the bot on `c58ef2c` before changing anything (the 28 Sep numbers are out of date: HQ 2 then took 4.0 min,
  the recording shows 1:04 now).

## The five first-minute bugs (from the recording)

1. **"HQ MAXED" on a brand-new account** (0:12 and 0:34). `refreshHqPad` falls through to "HQ MAXED" when it has
   no session (`SiliconCore.server.lua:2106`). Likely set before the save loaded and not refreshed. Never show it
   without a loaded session; show nothing until there is one.
2. **Stacked lobby text** (1:08): "BUILD LEVEL 3 · DESIGN STUDIO", "Recruit on the street...",
   "HIRING HAPPENS ON THE STREET..." and "Your HQ is open!" at once. Two say the same thing (`:1600` and `:1948`).
   Rule: the goal line is the only instruction; world signs only name the thing they sit on; one toast at a time.
3. **"SEATS FULL" right after the first hire** (0:32). Covered by contextual hiring above: after a hire the player
   sees what the coder does, not that seats are full.
4. **Two popups in the first minute.** Covered by the naming and style rows above.
5. **No goal after the lobby.** Covered by goal 5 and the queue: there is always a client to serve and a next goal.

## Screens (mocks first, rule 17)

Before code: clickable mocks at 844 x 390 in `ui/2026-10-16-client-loop/`, two or three options each, Luke picks,
the pick is written into this spec. Then code. A fresh reviewer compares the built screens with the picked mocks
and the five rules (one loud thing, show don't write, say it once, big and solid, space not boxes).

1. **The client at the door:** bubble with the ask (picture first: an app icon, then 1-3 words) and the
   patience bar. Board G: Sell Fries order, bubble + bar with a number. A BIG client's gold variant.
2. **Coding at the desk:** the progress bar over the laptop, and the WRITE CODE button filling while held,
   plus its "GO TO LAPTOP" state, and LAUNCH! appearing beside it when the product bar is full. Board F: Sell Fries "Peeling 57%".
3. **SHIPPED! and the payout:** the pop word, the box in hand, the client's reaction, the cash burst.
   The first-client wow version is bigger. Board G: TIMBER!, GOLDEN!, "Thanks! Just what I wanted".
4. **The goal line:** one line top-centre, two to five words, with a floor path. Board E: "Peel it!",
   "Go to your Pen!" and Chop A Forest's beam.

What to avoid (from the board): a card in the middle of the screen over the thing you need to see;
sentences in bubbles; several Robux-style buttons; thin text on dark; more than one goal on screen.

## Tracking

- Funnel (in order, once per user): today's `first_code` becomes "first hold on a job"; `first_ship` = the first
  client served; `first_hire` stays. No other new funnel steps (a step that can come out of order lies; see
  `docs/features/player-loop.md`).
- New events: `client_served` (field: `who` = you / coder / big), `client_lost`, summed like income where they
  happen often. `m_first_big_client` as a session milestone.
- Money: client pay is a new source kind `client` (and `client_tip`), logged beside the cash change.
  `telemetry.spec` gets the two new kinds in its own PR first (call 7).

## Constraints

- **CONSTRAINTS.md applies in full.** In particular: rule 3 (any new saved field gets a sanitizer, a
  `savecontract.spec` entry and a `savefuzz.spec` case; prefer no new save fields: the queue is session-only),
  rule 4 (never edit a judge to pass), rule 10 (`SiliconCore` is at the 200-local limit: new code goes in modules),
  rule 11 (logic that needs tests goes in a pure module), rule 12 (palette colours only; Neon only on lights,
  screens and effects), rule 17 (mocks, pick, then code).
- Studio tests as Wilz only, and restore the save after every Play (`DevScenarios.restore(1688749216)`).
- The doctor's existing checks keep passing; the doctor gains a check that a fresh save serves its first client.
- Phone first: everything works with touch at 844 x 390; tap targets 44 px or more.
- Clients must not block doors, the HIRE pad, the lift or the hunters' chase routes.
- The server owns all of it (job progress, pay, patience). The client only shows it. The remote for holding is
  rate-limited like `writeCode` (which drops calls within 0.35 s), so a script can't code faster than holding.

## Calls made after the builder check (Claude's calls, 16 Oct; Luke to check)

1. **Words.** "The lobby" = Wafers level 2 (the garage's first upgrade). The funnel's `hq_2`..`hq_5` are the
   stages (`WaferPlan.STAGE_AT = {5, 9, 13, 18}`), not levels. BIG clients start at the lobby. The baseline
   measures: lobby, first floor above the lobby, `hq_2`..`hq_5`, first spin-off.
2. **The garage has one seat** (`Wafers.capacity` = 1 + department seats), so after the free intern the garage
   is full. When the queue backs up again in the garage, the goal line says "Upgrade your HQ" (the lobby fits
   more people). Street recruiting is taught only after the lobby, the first time there is a free seat and the
   queue backs up. Garage seats do not change.
3. **Client income replaces tap income for an active player.** Target: a player who keeps serving clients earns
   about what a steady tapper earns today (about +0.5 to +0.9 s of income per second on top of staff income),
   so the mid and late game don't get poorer. **The bot plays like a person:** walks to the laptop, holds, carries,
   hands over, takes BIG clients. The 10% baseline is the old bot on `c58ef2c` vs the new bot on the branch.
4. **Who codes:** every seated person works client jobs. Engineers at full speed, other roles slower, using the
   role-fit numbers that exist (`RoomEconomy` role fit). This gives role choice a visible meaning.
5. **Popups:** on a fresh save, the Daily Reward card and the TalentReveal card wait until after the lobby moment.
   The garage-to-lobby cinematic stays (it is the reward, and it has SKIP). The welcome-back card never shows
   on a first session anyway.
6. **One big button:** holding a job keeps WRITE CODE. When the product bar fills, LAUNCH! appears as its own
   button next to it instead of replacing it. Both states go in the "Coding at the desk" mock.
7. **Judges first:** per CONSTRAINTS rule 4, the judge changes ship as their own PR before the feature:
   `telemetry.spec` (new money kinds `client`, `client_tip`), the bot (holding instead of tapping), the doctor's
   first-client check, and the `first_code` / `first_ship` comments. The bot counts as a judge.
8. **After a spin-off:** clients come back in the garage (they are the loop), but the first-client wow and the
   teaching lines do not replay. Decided from save state that exists (`spinoffs > 0`, or a launch on record),
   so no new save field.

9. **The garage door is shut until the first app ships** today (the beat driver opens it after the naming step).
   The first client knocks, the door rolls up for them, and they wait just inside. With naming gone, the door
   opens on the first client's arrival and stays open.

**Mocks:** `ui/2026-10-16-client-loop/mockups.html` (12 options, 4 screens; PNGs `mock-1A.png`..`mock-4C.png`,
all in `all-options.jpg`). **Luke's pick (16 Oct): 1A, 2C, 3A for every client + 3B for the first client, 4A.**
- **1A:** speech bubble (app icon + 1-3 words) and a patience bar under it (green, then gold, then red). BIG client: gold bubble with "BIG".
- **2C:** the WRITE CODE button is the progress bar: it reads HOLD TO CODE, fills while held ("CODING 57%"), pauses on release. The laptop screen flickers while coding. Away from the laptop: blue "GO TO LAPTOP". LAUNCH! is its own gold button beside it.
- **3A (every client):** the hand-over button is gold "HAND IT OVER" while carrying; on hand-over, "+$X" and "+$Y TIP" pop over the client, coins fly to the cash counter, the counter bumps; the client says "Just what I needed!" and hops.
- **3B (first client only):** rays + a tilted "SHIPPED!" stamp in the middle, then a big "+$X" count-up that flies to the cash counter.
- **4A:** one goal line top-centre (icon + 2-5 words) and gold chevrons on the floor toward the target.

## Left to the builder

- All numbers (job sizes, coding speed, patience, pay, tip, queue size per HQ level, BIG-client odds), to hit
  the pacing targets.
- Client looks (reuse the existing NPC rigs, as `TalentDrop` / `StaffRig` do) and their walk-up path per plot.
- How "hold" reaches the server (hold-start / hold-end events or a heartbeat), within the rate-limit rule.
- What happens to today's tap combo (`CODE_COMBO_*`): it can go, since holding replaces tapping.
- What the product bar's "every click pushes it" (`SiliconCore.server.lua:1399`) becomes under holding.
- The generated company names (list of fun two-word names, filtered like player text).

## Done when

- A fresh save, played on a phone, matches the pacing targets in a recorded run, and the recording shows
  zero popups and one goal line at a time through 2:00.
- The bot reaches HQ 5 and a spin-off within 10% of the baseline measured on `c58ef2c`.
- Offline tests cover the pure parts (queue, patience, job progress, pay, teaching order); the doctor passes,
  including the new first-client check; Luke has approved the built screens against the mocks.
