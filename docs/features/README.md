# Feature map

One page per system: what it is, how a player reaches it, the files (file:line), the state,
how to **drive** it (an SVDev scenario) and how to **prove** it (which check covers it).
This is shared memory for agents and for you. Code wins when a page and the code disagree.

**Keep it true:** `lune run tools/bas map check`
- **Coverage:** every module under `src/` is named on some page.
- **Staleness:** a page is stale when a file it cites changed after its `Last verified` commit.
  When you touch a system, fix its page and move the stamp.

| Page | System |
|---|---|
| [core-loop](core-loop.md) | write code, products, income, momentum, the guide |
| [hiring-talent](hiring-talent.md) | hiring, staff rigs, talent tiers, the staff index |
| [chase](chase.md) | Talent Row and the headhunter chase |
| [homes](homes.md) | apartments, downtown, the lift, the daily VIP |
| [hq-paths](hq-paths.md) | HQ upgrades, the three building paths, Wafers floors |
| [cars](cars.md) | company car, the dealer, traffic |
| [ipo-spinoff](ipo-spinoff.md) | going public and spinning off (prestige) |
| [offline-earnings](offline-earnings.md) | what you earn while away |
| [saving-data](saving-data.md) | the save, DataStores, telemetry and the onboarding funnel |
| [phone](phone.md) | investor texts, Series A |
| [daily-bag](daily-bag.md) | daily reward, the bag, items |
| [valley](valley.md) | the shared server, the market bell |
| [ranks](ranks.md) | leaderboards |
| [build-mode](build-mode.md) | rooms and furniture |
| [ui-hud](ui-hud.md) | HUD, menus, guide, coach, naming, music, the UI kit |
| [world-build](world-build.md) | the runtime world build (none of it exists in Edit) |
| [dev-tools](dev-tools.md) | SVDev, scenarios, the bot, SVCheck, smoke_core, `bas` |
| [not-built](not-built.md) | Valley Markets and Founders Coffee: planned, not built |

## Found while mapping (9 Oct)
- "Code" = read in the code.
- "Live" = measured in Studio.
- "Agent" = flagged by a mapping agent, not yet checked.

| Finding | Status |
|---|---|
| Live chase lengths are not the sim's. Delivery = stepping onto the lot: the skilled candidate stands inside it, and the star candidate is ~18 studs out, inside the 45-stud no-lunge zone. A star hunter can't lunge there | **Live** (held at 7.1 studs for 12 s) + code |
| The saved mute never restores: the server sends it in `MenuStats` (SiliconCore.server.lua:3819), and no client listens to `MenuStats` | **Code** |
| `s.hqPath` is never cleared, so the path picker never returns after a spin-off, though the comment says it should (SiliconCore.server.lua:2072-2074, 2825) | **Code** |
| Wafers mode builds no lots, so build mode may never place `needs` furniture | Agent |
| `Apartments.vipSpot` still uses the old plaza coordinates | Agent |
| `Phone.snapshot` and the `SVOpenDaily` event have no caller or listener | Agent |
| No code sets the momentum attribute on load; the HUD may show 0 after a rejoin | Agent |
| The `hq:<n>` scenario skips `Cars.grant` (the company car comes at HQ 2) | Agent |
