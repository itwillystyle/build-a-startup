# The Economy Clock (29 Sep 2026)

Status: **approved 29 Sep, built on branch `economy-clock`** (game repo). Live checks and the bot run are in the report at the end.

Sim: `sim/clock_sim.py` (runs 1 to 16 with spin-offs; live rules vs the clock). Run 1 is calibrated to the in-game bot: HQ 2 / 3 / 4 / 5 at 3.6 / 8.1 / 13.0 / 22.2 min in the sim vs 4.0 / 8.2 / 13.9 / 23.4 min for the bot.

## What's broken, measured

The sim plays exactly what you described.

**Prices never move, but your income does.** Every price is a fixed ladder (HQ 3 is $37,500 in every company). A spin-off multiplies your income: the spin-off bonus, the three homes (+30%), up to three kept rare hires, the Index and milestones. So each new company is richer, and the ladder stays where it was.

| Live rules | Company 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| Minutes to HQ 5 | 22.2 | 6.8 | 6.4 | 5.2 | 5.0 |
| Minutes stuck at HQ 5 waiting to spin off | 3.7 | 7.9 | 9.2 | 11.0 | 11.9 |
| First investor, as a share of the next goal | 11% | 37% | 53% | 73% | 71% |
| Biggest single windfall, as a share of the next goal | 36% | 73% | 64% | 87% | 103% |
| Biggest investor offer in the first 10 min | $52K | $360K | $490K | $1.45M | $1.7M |

That last row is your $1.8M offer 10 minutes into a spin-off.

**Investors aren't only for spin-offs.** They text from HQ 2 in every company. They're sized by your income (about 1.5 min of it), so when income jumps and prices don't, an offer can pay for the whole next goal.

**The daily reward is worse.** Day 7 pays 15 minutes of income: 3x the spin-off price at HQ 5 in company 1, and 5x the next HQ one minute into company 3.

**LAUNCH dies after company 1.** The work needed for the next product carries over between companies, so companies 2 to 5 launch about once each (company 1 launches 18 times).

## The rule

**One number per company scales every price inside it.**

- `scale(n) = spin-off price(n) / spin-off price(0)`, x1.3 from company 2 on.
- The x1.3 prices in the three homes: they pay +30% forever, but you only buy them in company 1.
- The spin-off price itself does not change (you said it feels right), so the clock is anchored to it.

| Company | 1 | 2 | 3 | 4 | 5 | 6 | 10 | 14 | 21+ |
|---|---|---|---|---|---|---|---|---|---|
| Price scale | x1 | x2.5 | x4.4 | x7.1 | x11 | x17 | x76 | x293 | x429 (stops) |
| HQ 3 costs | $37.5K | $95K | $165K | $268K | $418K | $634K | $2.8M | $11M | $16M |

**Scaled by the clock:** hires, recruit fees and their minimums, new rooms, room levels, HQ upgrades, decor.

**Not scaled:**
- **The spin-off** (it is the clock).
- **Homes.** One-time, bought in company 1.
- **Cars and luxuries.** One fixed ladder for the whole game, priced against where you'll be when you buy them (below).

**Windfalls are capped at a share of your next goal** (the next HQ, or the spin-off at HQ 5):

| Windfall | Today | Cap |
|---|---|---|
| Investor offer | ~92 s of income | 12% of the next goal (PUSH: 18%) |
| Series A | ~4.6 min of income | 25% |
| LAUNCH payday | 30 s of income | 25% (only bites in a company's first minutes) |
| GO PUBLIC | 60 s of income | 10% |
| Daily reward | 1-15 min of income | Day 1 5% ... day 7 35% of the next goal (the streak still grows) |
| Offline earnings | already capped at the next goal | unchanged |

- Capped amounts round down to a clean number, so an offer never reads "$11,407".
- **LAUNCH restarts each company.** The work needed for a product starts from the bottom again, so LAUNCH stays the active verb in every company (16 to 19 launches each).

## Results

| Clock | Company 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| Minutes to HQ 2 / 3 / 4 / 5 | 3.6 / 8.1 / 13.2 / 22.7 | 1.4 / 4.1 / 7.5 / 12.8 | 1.8 / 4.5 / 8.0 / 14.2 | 2.1 / 4.9 / 8.9 / 15.8 | 2.4 / 5.4 / 9.9 / 18.3 |
| Whole company (to spin-off) | 26.4 min | 17.5 | 19.2 | 21.1 | 24.0 |
| Biggest windfall / next goal | 25% | 25% | 24% | 21% | 19% |
| Investor offers | always 12% | 12% | 12% | 12% | 12% |

- **Company 1 barely changes** (HQ 5 half a minute later: the 12% investor cap).
- **Later companies:** you still skip the garage fast, since your rare hires come with you. After that, every HQ level is a real goal again.
- **Time moves from waiting to climbing.** Live company 3 spends 6.4 min climbing and 9.2 min idle at HQ 5; the clock spends 14.2 climbing and 5 idle.
- **The long tail** (16 companies simulated): companies grow from 18 min to about 105 min by company 14, then hold there (past 14 the spin-off price only grows as fast as its own bonus). That's about 13 hours to company 16.
  - At no point does a single windfall pay more than a quarter of what you're saving for.
- **A slower player** (a purchase every 30 s, tapping a third as often) lands 1 to 3 minutes behind per company. Same shape.

**Rejected:** option A (the spin-off scale without the homes' x1.3). Companies 2 to 5 took 16 to 22 min, and the homes stayed a free +30%.

## Cars and luxuries on the same clock

Cars keep fixed prices (you said the $90M hypercar feels right). Income at HQ 5 by company, from the sim:

| Company | 1 | 2 | 3 | 5 | 7 | 9 | 12+ |
|---|---|---|---|---|---|---|---|
| $/sec at HQ 5 | 13K | 21K | 35K | 78K | 224K | 322K | ~400K |

The $90M hypercar is 1.9 hours of HQ 5 income in company 1 and 19 min in company 5.

**Proposed new cars**, each faster than the one before (the Hyper does 132):

| Car | Price | Top speed | When it becomes a real goal |
|---|---|---|---|
| APEX | $350M | 146 | companies 7-8 (~25 min of income) |
| PHANTOM | $1.2B | 160 | companies 10-12 (~55 min) |
| ZENITH | $5B | 175 | company 14+ (~3.5 h): the long goal |

These are built in the luxuries phase. Your luxury ideas list is in the report.

## HQ 100

The clock is one formula, so it extends. Each new HQ level gets a price of "T minutes of the income you'll have at that level", and the company scale on top. How the levels past 5 work (what each one unlocks, where the spin-off sits) is decided with the building design, not now.

## Code changes (after approval)

- **`Progression.lua`** (pure, tested offline):
  - `runScale(n)`
  - `capWindfall(kind, amount, nextGoal, day)`
  - the daily share table
- **`SiliconCore`:**
  - `hireCostOf`, room / level / HQ costs and `furniturePriceOf` multiply by `runScale(s.spinoffs)`.
  - Launch work per company: add a `runLaunches` field, reset at spin-off.
- **Windfall caps:**
  - `TalentDrop` fees: scale the ladder and the minimum.
  - `Phone` and PUSH: `capWindfall`.
  - `goPublic`: `capWindfall`.
  - `DailyReward`: `capWindfall` with the streak day.
  - The payday in `launchProduct`: `capWindfall`.
- **The guide, HUD and pads** already read the same cost functions, so their labels follow automatically.
- **Saves:** there's nothing to migrate (prices are computed, never saved). A save mid-company keeps its cash; the new prices apply on the next join.

**Tests:**
- Offline (Lune): runScale values, each cap, daily shares, work need resets at spin-off.
- In-engine bot: company 1 at pace 20 (must stay within 1 min of 23.4 to HQ 5), then a forced spin-off and company 2 (sim says ~12.8 min to HQ 5).
- Snapshot the save first.

## Found while building

**Recruiting never checked your HQ level.** A spin-off drops you to HQ 1, but last company's STAR and GENIUS candidates kept standing on the sidewalk, and the server let you recruit them. That skipped the HQ 2 and HQ 3 unlocks in every later company, which was another reason those companies ran fast.
- Fixed in `TalentDrop`: the server now refuses a locked tier ("Unlocks at HQ n").
- Locked candidates leave the sidewalk until their tier unlocks.

## Verified live (29 Sep, Studio, in-engine bot at pace 20, fresh save, two companies)

| | HQ 2 | HQ 3 | HQ 4 | HQ 5 | Spin-off |
|---|---|---|---|---|---|
| Company 1, live bot | 4.0 | 8.1 | 13.3 | 22.7 | 26.1 min |
| Company 1, old baseline | 4.0 | 8.2 | 13.9 | 23.4 | ~26 |
| Company 2, live bot (min into the company) | 1.5 | 4.0 | 7.3 | 12.6 | 16.7 |
| Company 2, sim | 1.4 | 4.1 | 7.5 | 12.8 | 17.5 |

- **Prices matched the scale exactly:**
  - Company 2: office $253, studio $3,244, cafe $9,734, HQ 3 $95K.
  - Company 3: HQ 2 $16.5K, office $439, walk-in recruit $316.
- **Windfall caps matched:**
  - The investor at HQ 5 in company 2 paid $930K; uncapped it would have been $1.51M.
  - The Series A paid $370K in company 1 (the old code paid $580K) and $950K in company 2 (25% of $3.8M).
  - Daily day 1 to day 7 in company 2 at HQ 5 ran $390K to $2.7M against the $7.8M spin-off.
- **Spin-off and recruits:** after the spin-off only the walk-in and skilled recruits stand at HQ 1, and the product need restarts at 90. The bot refused 0 buys and brought 29 of 29 carries home.
- Your save was restored from `1688749216_pre_clock` (company 2, HQ 5, $28.29M).
