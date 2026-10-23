# Animation plans

From the improve-animations audit of 23 Oct 2026 (commit 084bd8b). The audit's findings
table and the side-by-side mockups live in `../../ui/animation-review/` (outside git). Luke's call:
plans for findings 1-3 (the moments players see most); the payout uses mockup B ("crisp").

| # | Plan | Severity | Status |
|---|---|---|---|
| 001 | [Make the HOLD TO CODE fill move at a steady speed](001-coding-bar-linear.md) | MEDIUM | DONE |
| 002 | [Make the per-client payout crisp](002-crisp-client-payout.md) | HIGH | DONE |
| 003 | [Quiet the coder's delivery pop](003-quiet-coder-pop.md) | HIGH | DONE |

**Order:** 001 (independent, one function), then 002, then 003.
**Dependencies:** 003 builds on 002 (`PayoutBeats`, its spec, and the rewritten `pop`/`cash`).

**Not planned yet** (in the audit table): Roblox's Reduce Motion setting (whole codebase),
the goal card morph, the money pop over the cash, the level-up banner exit, `UIKit.popReward`,
the tap-to-look camera, the hire and IPO card exits, and six LOW polish items.
