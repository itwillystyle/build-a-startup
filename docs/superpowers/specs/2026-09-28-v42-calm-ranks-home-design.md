# v4.2 design: calm screen, ranks, home turf

28 Sep 2026. You approved all three recommendations and the build order: **1 calm screen → 2 ranks → 3 home turf**. Each part ships and gets verified before the next one starts.

Evidence behind it: `AUDIT-TIZZY-2026-09-28.md` (the 24-notification inventory, the grades, the voice check).

Not in scope: trading, co-op, new currencies, new buildings, any change to HQ prices or the spin-off.

---

## Part 1: the calm screen (notification director)

### Goal
One thing per screen area at a time. The warnings that matter (the headhunter, a call) always win. Nothing ambient appears while you drive, carry a recruit or watch a cutscene.

### The unit
A client ModuleScript, **`ReplicatedStorage.Notify`**. Every LocalScript that requires it gets the same copy, so it can act as the one referee.

- `Notify.show(item)` queues or shows a transient. `item` is:
  - `lane`: `"top"`, `"centre"` or `"bottom"`
  - `priority`: 0 danger, 1 earned, 2 progress, 3 ambient
  - `key`: a name for logs and duplicate checks
  - `open(done)`: draws the element and calls `done()` when it has finished
  - `close()`: optional. Hides it early when a P0 needs the lane.
  - `ttl`: optional. How long it may wait before being dropped.
  - `fallback()`: optional. Runs instead of showing, e.g. bump the phone badge.
- `Notify.hold(lane, key)` and `Notify.release(key)` let a live status keep its lane for as long as it lasts (the headhunter chip, the LOST card).
- `Notify.state()` returns `{ driving, carrying, cutscene, menu }`:
  - `driving` = Humanoid.SeatPart is a VehicleSeat
  - `carrying` = the player's `Carrying` attribute
  - `cutscene` = `Cine.busy()`
  - `menu` = any `UIKit.MENUS` gui enabled, or `BuildModeOpen` / `NamingOpen`
- **Safety net:** if an item never calls `done()`, the lane frees itself after `maxHold` (8 s for top/bottom, 30 s for centre). A broken card can never jam the screen.

### Rules

| State | P0 danger | P1 earned | P2 progress | P3 ambient |
|---|---|---|---|---|
| normal | shows, bumps lower | shows when the lane is free | shows when the lane is free | at most 1 every 20 s; TTL 15 s |
| menu open | shows | shows | waits | fallback (badge) or dropped |
| carrying | shows | shows | waits | fallback or dropped |
| driving | shows | waits (never dropped) | waits | fallback or dropped |
| cutscene | waits | waits | waits | fallback or dropped |

"Fallback or dropped":
- Phone texts fall back to the red count on the PHONE button; the message is still in the phone.
- Every other P3 item is dropped. Other players' news also lives on the ranks board.

"Calm moment" (for the Daily auto-open, Name your company, While You Were Away):
- the centre lane has been idle for at least 5 s
- no driving, carrying or cutscene
- `WelcomeDone` is set

### Where each notification goes (from the inventory)

| # | Element | Lane | P | Change beyond routing |
|---|---|---|---|---|
| 1 | Toast | bottom | 2 own / 3 other players' news | none |
| 2 | Car toast | bottom | 1 ("Out of the car! Recruits walk.") / 2 | draws through the shared toast; its own spot is removed |
| 3 | Lift toast | bottom | 2 | same |
| 4 | Phone text banner | top | 3 | only the thread **opener** raises a banner; the reaction and next question are badge-only unless the phone is open |
| 5 | Incoming call card | top | 0 | none |
| 6 | Call pill | — | status | moves beside the PHONE rail button, out of the top lane |
| 7 | Talent reveal | top | 1 | none |
| 8 | HQ level-up banner | top | 1 | the HQ orbit shot runs **first** and the banner shows after it (today the orbit hides the banner after 1.4 s) |
| 9 | Milestone chip | top | 2 | none |
| 10-11 | "+$" money pops under the cash | — | — | unchanged: tiny, direct feedback for your own action |
| 12 | While You Were Away | centre | 2, calm | none |
| 13 | Spin-off confirm | centre | player-initiated | bypasses the queue (you tapped for it) |
| 15 | Daily auto-open | centre | 2, calm | none |
| 16 | Name your company | centre | 2, calm | none |
| 20 | Headhunter chip | top | hold 0 | holds the top lane for the whole chase |
| 23 | LOST card | top | 0 | none |
| 24 | Item "got" card | centre | 2 | its own queue stays; each card asks the director first |

Also:
- **WRITE CODE hides while you're in a car** (today the speedometer sits on top of it).
- Menus you open yourself (phone, bag, index, dealer, lift, apartments, decor) are not notifications and bypass the director.
- World-space pop-ups ("+$5", chatter bubbles, tags) are unchanged; they're already distance-limited.
- The dead code behind `Econ.V3` (picker, offer panel) is untouched.

### Verification
- Fire every remote at once from the server (reveal + HQ level-up + phone text + toast + item + daily) and list which frames are visible each second: at most one per lane.
- Repeat while seated in a car: only P0 visible, the phone badge counts up, WRITE CODE hidden.
- Repeat during a headhunter chase: the chip is never covered.
- Pace-20 bot run: HQ timings unchanged, 0 errors.

---

## Part 2: ranks (global leaderboard)

### Goal
From the HUD, see where your company stands against every company that has ever started, plus a weekly board a new player can climb.

### The number
**Company value** = the existing lifetime `valuation`.
- It never drops, not on spending and not on a spin-off (`spinOff` resets only cash).
- Cash-based net worth would drop every time you buy something, which punishes playing.

### Server: `ServerScriptService.Ranks` (ModuleScript)
SiliconCore sits at Luau's 200-local limit, so this lives in its own module and SiliconCore calls it.

- **All time:** the existing OrderedDataStore `SVTicker_v1` (key = userId), used as-is.
  - The $250K "must be public" gate in `pushTicker` goes. IPO stays as a cosmetic moment (gold sign, ticker symbol).
  - A company appears once its value passes $1,000.
- **Weekly:** OrderedDataStore `SVWeek_<weekId>`, with `weekId = floor((unixTime + 3·86400) / 604800)`, so each week starts Monday 00:00 UTC.
  - Value = `valuation − weekBase`.
  - Save gains two integers: `weekId` and `weekBase`.
  - On load, or when the week changes mid-session, `weekBase = valuation`.
- **Writes:** once a minute per player, only if the value changed. That's 2 writes per player-minute, far inside Roblox's budget of 60 + 10 × players.
- **Reads:** once a minute per server, `GetSortedAsync(false, 25)` for both boards.
  - Names come from the existing `nameStore` through a server-side cache: at most 10 new lookups per refresh, then "Startup #<last 4 digits>".
  - A live player's current name always wins.
- **AI rivals:** the existing 5 stay, so a board is never empty, and each carries an **AI** tag.
  - All-time value: `rivalValuation()` (existing, capped at 1.2× the best human).
  - Weekly value: that × the fraction of the week elapsed.
- **Your row:** if you're in the top 25, it's highlighted with the gap to the row above. If not: "Top 25 needs $X more". An OrderedDataStore can't give an exact rank outside the page it returns, so the game won't pretend to.
- **Remote:** a RemoteFunction `GetRanks` returns the cached boards plus your own row. It's never a live DataStore call per click.
- **Errors:** every DataStore call is pcall'd. On failure the last good cache is served, marked "updated N min ago".

### Client: `RanksClient` (LocalScript)
- A **RANKS** rail button (existing `medal` icon), below INDEX. It's added to `UIKit.MENUS`, so it closes other menus.
- A light `UIKit.menu` panel with two tabs, **THIS WEEK** and **ALL TIME**:
  - 25 rows: rank, company name, AI tag, value
  - your row pinned at the bottom
  - fits a 390 px tall phone screen
- One bottom-lane toast (P2) the first time each week you enter the weekly top 10: "You're #7 this week."
- The existing "just overtook" toasts become P3 through the director.

### World board
The Valley Exchange board keeps its place and now shows the all-time top 10 from the same cache, with AI tags. No extra reads.

### Verification
- Run against test stores (`SVTicker_test`, `SVWeek_test_*`) seeded with 40 fake companies:
  - order is correct
  - your-row gap text is correct
  - the week rollover resets `weekBase`
  - a failed read serves the cache
- Then one live check on the real stores with your own key.

---

## Part 3: home turf (apartments that feed the loop)

### Goal
Owning an apartment helps the core loop (recruit, hire, grow) and gives two reasons to come back tomorrow. The existing +10% money per tier and the HQ 3 / 4 / 5 gates stay as they are.

### A. Your home keeps the business running (offline earnings)

Today, offline earnings are 25% of your rate, capped at 600 s of full income.

New rule:

```
offline = min( rate × 0.25 × min(awaySeconds, WINDOW[apt]),
               NEXT_STEP_SHARE × costOfYourNextStep )
```

| Apartment | none | Studio | Loft | Penthouse |
|---|---|---|---|---|
| WINDOW | 40 min (same as today) | 2 h | 4 h | 8 h |

- `costOfYourNextStep` = the next HQ upgrade, or the spin-off at HQ 5.
- **The cap is what stops the "$3M overnight, never had to build" problem you hit on 19 Sep.** You come back to enough for the next big step, not five of them.
- `NEXT_STEP_SHARE` starts at 1.0 and is set by simulation (see below).
- The While You Were Away card gains one line: "Your Penthouse kept things running."

### B. The VIP recruit (once a day)
- If you own an apartment, one **VIP candidate** a day (UTC) waits outside the Residences entrance downtown, on the road side so it's visible.
  - Gold ring and pillar.
  - Only you can pick yours up. Other founders can still poach during the carry (existing PvP).
- **Tier floor:**
  - Studio: STAR
  - Loft: GENIUS
  - Penthouse: GENIUS, with the talent roll at luck × 2
- **Fee:** the tier's normal signing fee, paid at your door, and you need a free seat, the same as every recruit. The economy's spine doesn't change.
- **The run:** the full road home, the longest carry in the game, with that tier's headhunter. It extends the "rarer = further" lane to its natural end.
- **Announcement:** one phone text a day (P3 banner through the director): "A VIP candidate is waiting outside your building downtown."
- **Save:** one integer, `vipDay`. An unclaimed VIP expires at the UTC day change. Nothing piles up and nothing is taken away.
- Built on TalentDrop's existing candidate / carry / hunter code: a new `TalentDrop.spawnVip(player, pos, tierFloor)`, not a second chase system.

### Numbers get simulated before install
1. Extend `sim/first_hour_sim.py` with a day-2 return (8 h away at each apartment tier). `NEXT_STEP_SHARE` must never let one return skip more than one HQ step.
2. Extend `sim/recruit_sim.py` with the VIP route (Residences → each plot) and set the chase so the bot (weave + one 1.5 s stop) gets home at least 80% of the time. Today's carries are 23 of 23.

### Verification
- Offline:
  - Set `lastSeen` back 8 h on a test save at each apartment tier.
  - The paid amount equals the formula.
  - The card names the apartment.
- VIP:
  - A new UTC day spawns one VIP.
  - Only the owner can pick it up.
  - The talent is at least the floor over 200 rolls.
  - `vipDay` saves.
  - A second VIP never spawns the same day.
- Bot run: HQ 2/3/4/5 and spin-off timings within 1 min of the current 4.0 / 7.6 / 12.3 / 19.5 / 25.0.

---

## Rules that apply to all three parts
- Every install goes through the localhost pipe with the compile check and the forward-use check.
- Snapshot your DataStore record before any test that touches saves; restore it after.
- Disk == Studio check after each part. Studio left in Edit.
- One report per part, with screenshots, and one CLAUDE.md note.
