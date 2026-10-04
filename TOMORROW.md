# Tomorrow — the full task list, in order

Written 1 Oct, ~4am. No time blocks. Tasks in the order that wastes the least.
**(you)** = your hands only. **(me)** = I do it, you just say go. **(both)** = I build, you verify.

The spine: Tizzy's pyramid says fix the bottom layer first and never build an upper
layer on a broken lower one. Layer 1 is done on my side. Everything below Layer 2 is
blocked on one fact — **the game is private, 0 visits, 1 save key, and no stranger has
ever played anything you have built.** So the order is: close Layer 1 → clear the two
compliance items that block going public → repair the instruments → then layers 2-6.

---

## 0. First thing, before you open Studio (you)

These are first because they unblock other people, or because they take 2 minutes and
protect 3 weeks of work.

1. **Send the ChatGPT plugin outreach.** 5 emails or 5 walk-ins, your name, your words.
   Script is in `Downloads/plugin-studio/OUTREACH.md`. Do this at the START of the day —
   replies take hours to days, so they arrive while you're doing Roblox. If you send them
   at 10pm you lose a day.
2. **Merge the branches.** 19 commits are sitting on three stacked branches
   (`wafers` → `economy-clock` → `ui-polish-v5` → `main`). Say go and I'll do the merge,
   but it's your repo so you decide. If any of this is wrong, it's easier to find on main.
3. **Ctrl+S then Alt+P in Studio.** Last publish was 27 Sep 23:03. Everything since —
   the Wafers HQ, the economy clock, the UI v5 pass — is in session recovery and on disk,
   not in the live game. You have lost work to an unsaved close twice.
4. **The cold phone join.** This is the last Layer 1 item and I cannot do it. Studio runs
   client and server on one machine, so there is no download — testing there is exactly
   the "only tested on my gaming PC" trap the deck names.
   - Close Studio completely first. Last time your phone session fought a running Studio
     Play and the autosave overwrote your phone progress.
   - Worst phone you can borrow, **mobile data not wifi**.
   - Time two things: tap Play → world loads, and world loads → you can move.
   - Under 10s total is fine. Over 20s and I turn streaming on (currently off, 10,228 parts).
   - While you're in there: can you reach SKIP, and does tapping anywhere skip? Both are new.

---

## 1. Compliance — the gate before any stranger sees this (me, then you)

Two items. Both are account risk on an experience that can earn Robux. Neither is
optional and both are cheap. Nothing in layers 2-6 matters if the place gets actioned.

5. **Voice calls use the wrong age check.** `Phone.lua` gates calls on `HasVoice` +
   `CanUsersDirectChatAsync`. Roblox's documented check is
   `VoiceChatService:GetChatGroupsAsync`, and there's an unanswered Mar 2026 forum report
   that this exact `AudioDeviceInput` wiring bypasses age groups. Two options: I rewire it
   to the documented call, or I disable calls for launch and keep texting. **My
   recommendation: disable calls.** Voice was never tested with two real humans, it's not
   the moat, and the AI texting is. Cut it, ship, add it back after the D+28 read.
6. **No distress handling on the AI investor text box.** A player can type anything into
   a box that reaches a model. Needs a keyword check in front of the send that returns
   crisis resources instead of an investor reply. 30 minutes, and it's the kind of thing
   that gets a game pulled rather than warned.
7. **Age gate admin (you).** A new experience in the kids-and-select bucket is visible
   only to age-checked 16+ until 250 unique plays by highly engaged users inside 60 days.
   So your "ten strangers" have to be age-verified 16+ or they literally cannot see it.
   Start the clock today:
   - Creator ID verification
   - 2-step verification on
   - Either a Roblox Premium subscription (needs 2+ months of history, so starting it
     today means it matures in December) **or** the one-time refundable fee
   - Open Creator Hub → **Audience Reach** and read where you actually stand
   - 50,000 Robux expedites it if you ever want to pay past the wait
8. **Update the maturity questionnaire** (you) — it now needs to cover AI text, and voice
   if you keep it.

---

## 2. Layer 2 — "I know what I'm doing"

The deck's layer for first-session retention. Its DO is *"watch five strangers play, do
not help them."* You can't do that yet, so this layer is: **make the instruments honest
first, so that when five people do play, you learn something.**

9. **The funnel is lying and would have lied in the dashboard.** `Telemetry.lua` logs
   `joined → play → first_code → first_ship → first_hire → first_wing → first_product →
   first_rival → ten_minutes`. Under the Wafers/V3 code there are no wings (they're wafer
   storeys) and rivals are turned off. So steps 6 and 8 can never fire, and the dashboard
   would show a false cliff at step 6 that you'd then spend a Saturday "fixing."
   Replace with the real forced path:
   `joined → play → first_code → first_ship → first_hire → first_storey → first_recruit →
   first_product → ten_minutes`
   **Do this before anyone plays.** Roblox's onboarding funnel keeps only the first
   instance of a step per user *for life*, so renaming steps makes old data incomparable —
   which costs nothing right now, because there is no old data. This window closes the
   moment a stranger joins.
10. **Add the bounce probe.** First-play bounce under 60s is one of Roblox's top-tier
    ranking signals and you currently cannot see it. One session event at 15s / 30s / 60s /
    180s, tagged mobile vs desktop. That single series tells you whether Layer 1 worked.
11. **Read the dashboard once with me** (both). Your funnel has been firing into
    AnalyticsService since v1.2 and neither of us has ever opened the page. Creator Hub →
    Analytics. Studio records nothing to it, so this only means anything after a publish
    and a real join.
12. **Audit the guide against the Wafers build** (me). `Journey.lua` + `GuideClient` were
    written for the HQ 1-5 + rooms world. The world is now one curved building with 100
    levels and a talent row. Check every rung of the ladder still points at a thing that
    exists, and that the quest card names the talent row at all — it's the signature verb
    and I'm not sure onboarding mentions it.
13. **Fix the D+28 read rule** (me). `D28-READ.md` sets keep/fix/freeze at "D1 ≥ 20% and
    avg session ≥ 10 min". Real benchmarks across 500+ games with 1M+ MAU: D1 median is
    **10.3%**, p75 is 12.9%, p90 is 15.9%. A 20% rule means you will freeze a game that is
    doing better than three quarters of Roblox. Rewrite to: D1 ≥ 10% keep, ≥ 13% push,
    < 8% rethink.
14. **Then, when it's public: five strangers, and you say nothing.** Not friends who ask
    questions. Watch where their hands stop. The rule is that you are not allowed to help,
    because the thing you'd say out loud is the thing the game has to say by itself.

---

## 3. Layer 3 — "this feels good to do"

Playtime and D1. Your own 18.9-minute recording was **40% idle** and you never pressed
LAUNCH once. That's the whole diagnosis: the game plays itself and the player watches.

15. **Name the verb out loud** (both). In v4.6 the repeatable active thing is: walk the
    street, grab a candidate, carry them home past a headhunter. That's Tizzy's "leave
    base, get thing" and it's the only part of your game that is a *game* rather than a
    readout. Everything in this layer should make that loop the heartbeat.
16. **Measure the idle percentage properly** (me). Instrument it: fraction of each session
    where the player is neither moving, tapping, nor in a menu. Then it's a number you can
    move instead of an impression from a video.
17. **Cut the dead air between recruits** (me, after 16). Restock cadence on the talent
    row versus how long a carry takes. If there's a 60-second gap where the only thing to
    do is watch money appear, that's the 40%.
18. **Make WRITE CODE matter or make it stop existing** (both). It's a tap with a combo
    multiplier that the recording shows you never used. Either it's the filler verb
    between recruits — in which case it needs to be visibly worth it — or it's noise
    competing with the real verb.
19. **One note on the ceiling:** Roblox caps playtime credit at 60 min/user/game/day, so
    chasing marathon sessions buys nothing. Target 12-20 minutes, repeated. That changes
    what "good" means in this layer.

---

## 4. Layer 4 — "I'm getting somewhere"

D2-7. You have more of this built than you think: daily reward + 7-day streak, offline
earnings scaled by home tier, milestone ladder, spin-off prestige with the late-game wall
fixed. What's missing is that **nothing tells the player tomorrow will be different.**

20. **Audit the return promise** (both). Open the game as a returning player and ask: in
    the first 10 seconds, what tells me something happened while I was gone, and what tells
    me what's new today? Right now it's a "While you were away" card with a number. A
    number is not a reason.
21. **Make the daily a reason, not a payout** (me). The daily already pays cards/talent
    rather than cash, which is right. The gap is that day 4 looks like day 3. Rarity floors
    exist; surface the *next* one ("tomorrow: guaranteed Star").
22. **The weekly board is the cheapest D2-7 lever you own and it's invisible** (me).
    `Ranks` already runs a THIS WEEK board that resets Monday 00:00 UTC. Nobody is told it
    resets, so it's a leaderboard rather than a deadline. A deadline is a return reason.
23. **Hold spend days.** It's a second-tier Roblox signal and it needs monetization.
    That's Layer 6. Not now.

---

## 5. Layer 5 — "I matter here"

**The biggest untouched lever in the project.** Intentional co-play days is a second-tier
ranking signal and it counts friends, invites and private servers only. Right now there
is nothing in your game you do *with* another person. MaxPlayers is 6, six plots, and the
only other names on screen are AI rivals on a board.

24. **The two-player poach test** (you + one real person, 15 minutes). `TalentDrop` already
    lets another founder steal the recruit you're carrying. It has never once been tested
    with two humans. This is the same shape as the heist vote: built, "technically works",
    shipped, then *"i didnt care that much."* Test it before building anything on top of it.
25. **Async first, always** (me). At quiet-launch density a server is 1-2 players, so
    anything requiring two live humans almost never fires. That's exactly how the heist
    vote died. Whatever co-play you add has to have a recorded/async version that works
    alone — a rival founder's recorded pitch, a ghost of someone's best run, a name on your
    street from yesterday.
26. **Make the other five plots legible** (me). Six founders share one valley. Right now
    another player's campus is a building. It should say, from the street, who they are and
    how far ahead they are. The fascia already encodes rank on the old HQ — that idea just
    never made it to Wafers.
27. **One invite reason** (me, last in this layer). Not a reward for inviting. A thing that
    is better with a second person in the server — the poach race is the obvious candidate
    if #24 says it's fun.

---

## 6. Layer 6 — "this is mine"

D8-28 and Robux per user. **The deck's named mistake for this layer is "trying to build
this first."** Do not touch it tomorrow. Written down so it's on the list and in the
right place.

28. Gamepasses under 500 R$ when the time comes: x2 Cash ~399, Auto-Collect ~249, extra
    desks, luck. Zero monetization exists in the game today.
29. The relevant fact: monetization drives impressions (devforum post, 6 Aug 2026), but
    the same post says retention-only games "will continue to receive" impressions. So
    launching at $0 costs you upside, not discovery. Launching broken costs you discovery.

---

## 7. The UI recordings — how to send them so they're actually usable (you)

You said you're recording top games' UI. Yes, send them. This is the right instinct and
it's the only reliable source — I checked, and Roblox game pages only carry promo art, so
there is no HUD evidence there at all.

30. **Record these four things per game**, and tell me the game's name:
    - the first 60 seconds from tapping Play (this is the layer-1/2 evidence)
    - the idle HUD, held still for 5 seconds, nothing open
    - every menu opened one at a time
    - a phone session if you can, because that's the device that decides
31. **Drop the mp4s in `Downloads/`** and tell me they're there. I pull frames with ffmpeg
    at 1fps — that pipeline is already proven on your own recordings. Audio doesn't matter.
32. **Worth recording specifically:** Run a Restaurant! (98.7% like, the UI I already used
    as the reference), Steal An Egg, and whichever game you personally keep reopening.
    That third one is the most valuable of the three and nobody else can pick it.
33. Once they're in, I do a side-by-side against your HUD and we change things against
    evidence instead of taste. Don't start UI work before the footage lands — that's how
    the last two UI passes ended up being my opinion rather than a reference.

---

## 8. ChatGPT plugin service — parallel track (you, mostly)

The kit is built and tested (16/16 checks). What's left is all people-work, which is why
it goes early in the day and then waits.

34. **Outreach, 5 contacts.** (This is task 1. Listed again so the track reads whole.)
35. **Pick 10 local businesses** with a website and a menu or price list — Market Square,
    near campus. Send me the list and I build each one a demo from their own site. Showing
    somebody *their own menu* inside a ChatGPT card is the entire pitch.
36. **Test the kit inside real ChatGPT** (both). Needs `cloudflared tunnel --url
    http://localhost:8787`, then ChatGPT → Settings → Developer mode on → add connector at
    `https://<tunnel>/mcp`. I can drive most of it; you have to flip developer mode and
    approve the connector.
37. **Hosting decision** before the first yes, not after (Render or Railway, `node
    server.js`, `CLIENT=<id>`).
38. **One-page agreement** before you take money. Scope, price, 50% up front, and the
    line that you don't control ChatGPT's recommendations. I'll draft it when you ask.
39. Pricing is already set in `OFFER.md`: $750 / $1,500 / $79-mo. Don't discount on the
    first call.

---

## 9. Tools — honest ranking

You asked to be pointed at MCP tools and plugins that would help the game a lot. The
honest headline first: **tooling is not what's wrong with this project.** You have 7,000+
lines, 20 scripts, Rojo, git, selene, StyLua, Lune, 47 offline tests and a pre-commit
hook. What you don't have is one stranger. No tool fixes that. With that said, three of
these are real:

### Already installed, never used — use these first
- **UI Labs** (Studio plugin, verified loading, never opened). Renders a single GUI
  component in isolation so you can iterate a card without playing the game to reach it.
  This is the correct tool for the UI rebuild once your recordings land. Highest-value
  thing you own and have never clicked.
- **Creator Hub → Analytics.** Your funnel has been firing for weeks into a page neither
  of us has opened. Free retention data, including the D1/D2-7/D8-28 windows Roblox now
  scores you on.
- **vidiq MCP** (`vidiq_score_thumbnail`, `vidiq_generate_thumbnail`,
  `vidiq_score_title`). You said thumbnails suck and you were right — the reason is that
  the thumbnail looks like the game because it *is* the game. This scores a thumbnail
  before you ship it instead of after.
- **youtube-transcript MCP.** Already connected. Pairs with your recordings for studying
  other games' loops without watching 40 minutes of video.
- **blender MCP.** Connected. Your asset pipeline (`blender/*.py` → FBX → Bulk Import)
  already works headless; the MCP makes iteration interactive when you want to eyeball a
  mesh instead of re-rendering a contact sheet.

### Genuinely new and worth adding — one thing
- **Roblox Open Cloud** (and the `rbxcloud` CLI wrapper, which I'll verify and install
  tomorrow). This is the real gap in your stack, and it solves three problems you have hit
  repeatedly:
  - **Publish without Studio.** Your single most repeated failure in this entire project
    is "NOT saved/published — Ctrl+S + Alt+P." Open Cloud publishes a place version over
    HTTP. That becomes one command, or a git hook, instead of a thing you forget at 4am.
  - **Read and write DataStore from outside Edit mode.** Every save snapshot and restore
    we've done has required Studio to be in Edit and me to not be mid-install. This makes
    backups scriptable.
  - **Pull analytics programmatically** into your existing `roblox-research` dashboard, so
    your own game sits in the same table as the games you're studying.
  Needs an API key from Creator Hub with scopes, which is your hands, 5 minutes.

### Plugins worth adding
- **Tag Editor.** You use CollectionService heavily (`SVStaff`, `SVChair`, `FKItem`,
  `TrafficCar`, `TalentRow`) and currently manage tags only from code. This makes them
  visible and editable in Edit.
- **Moon Animator** — installed and now switched on. The staff animations that landed
  (`SV_StaffCheer`, `SV_HunterWindup`, `SV_HunterLunge`) were built by script; Moon is how
  you'd do a walk cycle by hand if you want one.

### Explicitly not recommending
- Another AI coding tool or chat frontend. You asked about T3 Code earlier and the answer
  hasn't changed: your bottleneck is feedback from humans, not tokens.
- Any new concept tracker, planner or dashboard. You have `the_system` (published, and as
  of the last check had zero ticks logged since 14 Sep), `THE-PLAN.md`,
  `PLAN-v5-tizzy.md`, `PLAN-v6-visual.md`, and the sampler dashboard. Adding a sixth place
  to write plans is how the last five got abandoned.
- A Roblox market-data MCP. I checked — no public one exists. Your own
  `roblox-research/sampler.py` plus the omni-search endpoint already does this and runs on
  a schedule.

---

## The one thing to protect

SQL before Roblox. The tracker's own rule is that a day where SQL happened first is a HIT
and an eight-hour day that never reached SQL is a MISS. Two Roblox days in week one had
zero SQL, and the Sep 1 milestone is the kill rule for the game's Saturday. Tomorrow is
going to be a long Roblox day — do the hour first and it costs you nothing.

## And the honest sentence

Every task above is downstream of one thing: nobody has played this. 27 days published,
0 visits, 1 save key, and that key is yours. The phone test and the five strangers are
worth more than every other task on this page combined, and they're the only two I
can't do for you.
