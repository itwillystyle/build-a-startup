# Loop complements: homes, the chase, and cars

**Date:** 2026-10-07
**Status:** design approved (spine), spec for review
**Repo:** `silicon-startup/game` (this doc lives outside it, with the other specs)

---

## 1. The problem

Three systems in the game hold a number instead of changing how you play.

**Apartments.** `Progression.APARTMENTS`: three tiers at $20K / $150K / $2M, each
giving `bonus = 0.10`. `Apartments.lua:40` sums those into a money multiplier.
A player at Penthouse is +30% on a rate that is already the product of HQ level,
room levels, talent, set bonuses, milestones, prestige and market share. It is
invisible. The player's own words: *"whatever that number even means."*

**The recruit chase.** Every candidate of every rarity stands on the player's own
drive. `TalentDrop.lua:105` compresses the authored spread (`east` 20 / 140 / 280
/ 440) into `20 .. DRIVE_MAX` on one strip of pavement. The map the player drives
through has nothing in it, and a Genius is found in the same place as a Walk-In.

**Cars.** Six tiers, $0 to $90M, speed 64 to 132 (`Cars.CATALOG`). Carrying speed
during a chase comes from `Econ.CARRY_SPEED` keyed on **HQ level**, not on the car.
So the $90M hypercar changes nothing about the one skill-based verb in the game.

### The failure mode to avoid

The first version of this design made each of these a shop: drive to Motors for
reach, to a cafe for consumables, home to brew. That is a chore chain — *go here
to buy the thing that lets you do the thing* — and it reads as friction wearing a
costume. It was rejected, correctly.

---

## 2. The rule

> **Nothing new may require a detour. Each thing must make a beat the player
> already hits land harder.**

The beats that already exist: tap WRITE CODE → ship → launch → recruit → buy a
level → spin off → come back tomorrow.

Every system below attaches to one of those beats. If a proposal needs a new trip
to a new building, it is cut.

---

## 3. Homes decide what survives a spin-off

**Beat:** the spin-off. The deepest decision in the game, and today the apartment
has nothing to do with it.

### Today

`SiliconCore.server.lua:2951` keeps every rig with `talent >= Econ.KEEP_TALENT`
(3, Star and above), then `:2955` trims to `Econ.KEEP_MAX` (3). Flat, for everyone,
regardless of anything the player owns.

### Change

The apartment is **keeper capacity**:

| Home | Price | At spin 1 | Keeper slots |
|---|---|---|---|
| none | — | — | 0 |
| STUDIO | 1% of the next spin-off | $40,000 | 1 |
| LOFT | 15% of the next spin-off | $600,000 | 3 |
| PENTHOUSE | 60% of the next spin-off | $2,400,000 | 5 |

**Homes are priced as a share of the spin-off they compete with, not in dollars.**
This is forced by the measured curve, not a preference. A real player reached
~$3M in about 20 minutes, which matches the recorded bot run (GO PUBLIC ~23.9 min,
spin-off $4M at ~26 min). Against that curve the authored prices are
0.5% / 3.8% / 50% of a spin-off, so all three homes are affordable *before a
player can spin off at all* and keeper slots would differentiate nobody — gates
removed or not.

As a share, the decision survives the curve: the Penthouse costs 60% of a
spin-off, so buying five slots visibly delays the restart you are saving for,
while the Loft keeps today's three for a sixth of that. The Studio stays trivial
on purpose — it is insurance, not a decision.

The price is taken as a share of `Progression.spinCost(n)`, which already carries
the per-company scaling, so the share holds in later companies rather than
collapsing to nothing. It is deliberately NOT routed through `P.runScale(n)`:
that is the same multiplier times `RUN_HOMES` (1.3), which would raise the home
1.3x per company *relative to the spin-off* and make the share drift upward.

The decision is made once, at the first spin-off, and the home then persists. That
is accepted: the first spin-off is the retention moment that matters most, and
five slots keep paying off more each run as Star+ staff accumulate.

`Econ.KEEP_MAX` stops being a constant and becomes `Progression.keepSlots(apt)`.
`Econ.KEEP_TALENT` (Star and above are eligible) is unchanged.

At spin-off the confirm card already lists what you keep versus what resets
(`SiliconCore.server.lua:2926`). It gains a **selection step**: if more staff are
eligible than you have slots, you pick who comes. Capacity is what you bought;
selection is the decision you make every run.

The `bonus = 0.10` field is **deleted**, along with its use in `Apartments.lua:40`.

The offline window (`P.WINDOW` = 40 min / 2h / 4h / 8h by tier) is **kept
unchanged**. It already works, it is already felt on return, and it is the one
part of the apartment that was never the problem.

### The gate must go

`P.aptNeeded(level)` makes the Studio/Loft/Penthouse mandatory for HQ 3/4/5.
Spin-off requires `s.listed` (GO PUBLIC), which is HQ 5, which requires the
Penthouse. **So every player who can spin off already owns every home**, and
keeper slots keyed to home tier would differentiate nobody.

So `gateHQ` is removed and homes become optional purchases. This is also the
right call under the rule in §2: a gate is a toll booth, not a complement.

The consequence is the design working as intended. With no gate, 60% of a
spin-off spent on a Penthouse is 60% not spent on restarting, so a first spin-off
typically happens on a Studio or a Loft, and losing people you recruited is what
sells the next home.

`Progression.ladder(level, apt, hqCost, spinCost)` currently returns the next HQ
step *and its apartment gate*. It is reduced to HQ steps and the spin-off. The
guide (`Journey`) stops telling players to buy a home to proceed, and instead
surfaces a home when a spin-off is within reach and their slots are short.

### Not doing

A fourth home tier. Three is enough to make the first spin-off a real decision,
and a fourth is content for a player who has not been shown to exist yet.

---

## 4. The chase, scattered

**Beat:** recruiting. Already the only skill-based verb.

### Scatter by rarity

| Tier | Where candidates stand | Distance from your plot |
|---|---|---|
| WALK-IN | your own drive (unchanged) | 20–60 studs |
| SKILLED | your district: the ring road and plaza serving your plot | 120–220 |
| STAR | downtown: the plaza between The Residences and Valley Motors (x 620–790) | 400–700 |
| GENIUS | the valley landmarks: The Dish (−108, −505), Lick Observatory (351, 596), Hangar One (−864, 144) | 700–1200 |

Landmark coordinates are the ones `ValleyGen.dress` already places them at, so
GENIUS candidates stand at objects that exist rather than at invented markers.

`TalentDrop.lua:105`'s compression into `20 .. DRIVE_MAX` is replaced by a
per-tier spawn region.

### Why this does not become a drag

**The offer deadline already scales with distance.** `TalentDrop.lua:438`:

```lua
c.deadline = now() + Econ.OFFER_BASE + dist * Econ.OFFER_PER_STUD
```

Distance already buys time, so scattering costs the player no pressure. It buys
variety and it gives the map and the car a reason to exist. `OFFER_PER_STUD` may
need retuning once the distances are real; that is a sim question, not a design one.

### Suspense without length

Longer walks are not tension. Three changes, in priority order:

1. **A second hunter at GENIUS.** `ChaseRules.TIERS` has `hunters = 1` for every
   tier, while `C.SECOND` (a junior that herds rather than hunts) already exists
   and is only used for the daily VIP. Give GENIUS `hunters = 2`. Being herded
   into the path of the one that lunges is tension that costs no extra distance.

2. **Drop and recover.** You may let the recruit go to sprint free, and come back
   for them before the offer expires. A chase you can only win or lose has one
   decision in it; a chase you can bail out of has one every few seconds.

3. **Stealing** — another founder can take the carried recruit. This is specified
   but **gated behind the two-player test**, because a mechanic designed for
   density that does not exist is exactly how the heist vote died
   ("i didnt care that much"). Build 1 and 2 first; build 3 only if the
   two-player test says the chase is fun with someone watching.

---

## 5. Cars become the chase

**Beat:** recruiting, again. Not a new errand — the car *is* how you run it.

**Carrying speed moves from HQ level to the car.** `Econ.CARRY_SPEED` is keyed on
HQ level today (16 → 20). It becomes a function of the car you own, so the ladder
in `Cars.CATALOG` (speed 64 → 132) finally does something for the verb it should
always have served. The on-foot scooter remains the floor for a player with no car.

**Valley Motors becomes a showroom you walk into.** The building exists with five
display pads and a sign (`Downtown.lua:322`). The pads are correct flat cylinders;
what is missing is that you cannot go in and the cars are not on them. Put the
catalog on the pads, let the player walk the floor, and let the pad you stand next
to be what the buy panel is showing.

This is the one place a *destination* is justified under §2, because looking at
the car you cannot afford yet is the point of a showroom — it is aspiration, not
an errand. Buying still works from the phone, so nobody is forced to drive there.

### Higher tiers

APEX $350M, PHANTOM $1.2B, ZENITH $5B, continuing the speed curve. These exist to
give late prestige runs something to convert money into. They are the cheapest
content in this spec (a row in a table each) and the first thing to cut if the
economy sim says the late game cannot reach them.

---

## 6. Items come from the phone

`Items.ITEMS` already has the right shape: Cold Brew (3× code speed, 60s), Energy
Drink (+5 scooter, 90s), Non-Compete (dismisses the headhunter), Scout Report (+1
talent on the next hire), Front Page (2× next launch). They change how you play.
They are only ever given out, never bought.

A **Supply** app is added to the phone, selling all five. Priced in seconds of
income so they scale with the run rather than inflating away, following the
precedent `packPrice` and `SALE_SECONDS` set: Cold Brew 20s, Energy Drink 30s,
Non-Compete 60s, Scout Report 90s, Front Page 150s. Stock is per session and
capped (two of each) so the shop cannot replace playing the game.

The phone is the shop because the player already carries it. Making someone drive
to a building to buy a Non-Compete is precisely the drag this spec exists to avoid.

### Founders Coffee and Valley Markets are not built

Neither exists in code today — downtown has exactly two destinations, The
Residences and Valley Motors. Under §2 neither earns its keep: a shop you must
drive to, selling what the phone already sells, is an errand with a sign on it.

If the world later needs more life, it should come from the environment work
(§8), not from buildings invented to host a transaction.

---

## 7. How this folds into the economy

Every change converts money into **capability the player carries**, and none of it
raises the rate:

| Sink | Buys | Felt at |
|---|---|---|
| Homes | keeper slots | spin-off |
| Cars | chase speed | every recruit |
| Items | a moment of advantage | when used |

Deleting the apartment bonus removes up to +30% from the top-end rate. That is
intended — rate inflation is the disease, not the cure — but it is a real economy
change and must be re-simmed, not assumed.

### Must be re-run before shipping

- `sim/clock_sim.py` — company timings with the apartment bonus gone and the HQ
  gates removed. Removing gates lets a player rush HQ levels without buying
  homes, which is a faster curve than the sim has ever modelled.
- `sim/first_hour_sim.py verify` — constants still match the Lua.
- The pace-20 bot — against the current baseline (HQ 4.0 / 7.6 / 12.3 / 19.5,
  spin 25.0) to confirm the first hour has not moved.

---

## 8. Build order

These are three separable pieces that share one rule and one economy re-sim.
They ship in this order, each verifiable on its own:

1. **Homes** — `Progression.keepSlots`, the gate removal, the selection step on
   the spin-off card, the bonus deletion. Biggest economy change, so it goes
   first and the sims run against it before anything else is layered on.
2. **Cars** — carrying speed moves to the car; the showroom becomes walkable.
   Small, self-contained, and it is what makes the scatter in step 3 pleasant.
3. **The chase** — scatter by tier, the second hunter at GENIUS, drop-and-recover.
   Last, because its tuning depends on the carry speeds set in step 2.

The Supply app (§6) can land with any of them; it depends on nothing here.

Stealing (§4.3) is not in this order at all. It waits on the two-player test.

---

## 9. Explicitly out of scope

- Asset cohesion and the blocky furniture. A real complaint, a separate piece of
  work, and an art problem rather than a loop problem.
- The barren ground around The Residences. Environment, not economy.
- Floating NPCs, the apartment roof you can jump through. Bugs, tracked separately.
- Stealing recruits (§4.3) until the two-player test says the chase holds up.

---

## 10. Risks

**The biggest one is unchanged and is not technical.** No stranger has ever played
this game. This spec adds three systems to a loop no outside player has tested.
The kill rule in the project's own plan (ten strangers, due 21 Sep) is long
overdue. Everything here is cheap to cut, and nothing in it should be built in
preference to putting the game in front of someone.

**The first prestige lands at ~26 minutes.** This is the scaling question worth
asking, and it is not about dollars. A player earning $3M in 20 minutes is on
curve; the issue is whether the climax arrives inside a first session at all.
Comparables in this lane: Anime Card Collection averages 30 min a session, TCG
Shop Simulator 7. At ~26 minutes to GO PUBLIC and the first spin-off, a player
with a 15-minute first session never sees either. Nothing in this spec fixes
that, and it may matter more than everything in this spec does.

**Removing the HQ gates is the largest single change.** It alters the critical
path of the whole game, and the sims above are the gate on shipping it.

**Carrying speed moving to the car** means a player with no car is slower than
today at the same HQ level. The scooter floor must be checked against
`ChaseRules.TIERS[*].ref` (16 / 17 / 18) so a car-less player can still escape a
SKILLED hunter, or the early chase becomes unwinnable.

---

## 11. Testing

- **Offline (Lune, `tests/offline/`)**: `keepSlots` per tier and the selection
  trim; spawn-region distance per tier against `OFFER_BASE + dist × OFFER_PER_STUD`
  to prove every tier is reachable in its window; carry speed versus hunter
  reference speed per tier.
- **In Play**: a scatter run that recruits one of each tier and confirms each is
  reachable and returnable; a spin-off at each home tier confirming slot counts
  and that selection persists through save and reload.
- **Bot**: pace-20 fresh save against the baseline above.
- **Two players**: the chase with someone watching, before stealing is built.
