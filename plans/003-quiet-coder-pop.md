# 003 — Quiet the coder's delivery pop (it fires every few seconds late game)

- **Status**: DONE (23 Oct, branch crisp-payout, verified live in Studio)
- **Commit**: 084bd8b
- **Severity**: HIGH
- **Category**: 1. Purpose & frequency
- **Estimated scope**: ClientFxClient + PayoutBeats + its spec (~25 lines). Depends on plan 002.

## Problem

When a hired coder delivers an app, the client pays, and late game that happens every few
seconds. If the client is on screen and within 60 studs, `cash(d, at, true)` pops "+$X" at
`UIKit.TYPE.title` (22 px) with the same Back overshoot and 1.4 s life as the payout you made
yourself, plus 3 coins:

```lua
-- src/StarterPlayer/StarterPlayerScripts/ClientFxClient.client.lua:330 and :334 — current
pop("+" .. UIKit.money(d.pay), at, coder and UIKit.TYPE.title or UIKit.TYPE.headline, UIKit.MONEY)
...
Moment.landMoney(at, coder and 3 or 6)
```

Something seen tens of times a minute must be drastically reduced (AUDIT.md section 1), and a
background event should not look like the player's own reward.

## Target

| Beat | Value |
|---|---|
| "+$X" | `UIKit.TYPE.label` (18 px), MONEY colour; fade in 0.12 s while rising 6 px; NO scale, NO overshoot |
| hold / out | holds 0.3 s, then fades over 0.15 s (Quint Out) |
| coins | 3, through `_G.SVCoinStream(at, 3, nil, d.pay, { prepaid = true })` with `_G.SVCashHold(d.pay)` called when the pop starts, so the counter counts with them (fallback `Moment.landMoney(at, 3)`) |
| tip | none shown (coder deliveries carry no tip line) |
| sound | none (unchanged: `cash` only plays the ding when `not coder`) |

Add to `src/ReplicatedStorage/PayoutBeats.lua`:

```lua
PayoutBeats.CODER = { enter = 0.12, rise = 6, hold = 0.3, leave = 0.15, coins = 3 }
function PayoutBeats.coderDuration()
	local c = PayoutBeats.CODER
	return c.enter + c.hold + c.leave
end
```

## Repo conventions to follow

- Same as plan 002 (TDD with the offline spec first; pure module; dated why-comments; fade the
  UIStroke with the text).
- The existing gate stays exactly as is: a coder's pay shows only on a client you can see within
  60 studs (the comment block at ClientFxClient.client.lua:343-346 explains why).

## Steps

1. Add to `tests/offline/payoutbeats.spec.luau`, run, watch it fail:
   - "a coder's pop is under 0.6 s (it fires every few seconds late game)":
     `PayoutBeats.coderDuration() <= 0.6`.
   - "a coder's pop is quieter than your own payout": `PayoutBeats.CODER.coins < PayoutBeats.COINS`
     and `PayoutBeats.coderDuration() < PayoutBeats.duration()`.
2. Add `CODER` and `coderDuration` to PayoutBeats. Tests pass.
3. In ClientFxClient, give the coder branch of `cash` its own path (a small local function
   `coderPop(d, at)` is fine): fade-and-rise label per Target (TYPE.label, no UIScale), then the
   coins per Target with the hold. Remove the `coder and ... or ...` ternaries from `cash` so
   `cash` is only the player's own payout.
4. In the `clientPaid.OnClientEvent` coder branch (the `if d.who == "coder" then` block), call
   `coderPop(d, Vector2.new(v.X, v.Y))` where it called `cash(d, Vector2.new(v.X, v.Y), true)`.
   Off-screen or far deliveries still show nothing (unchanged).

## Boundaries

- Do NOT change the 60-stud / on-screen gate.
- Do NOT touch `wow()` or the player's own payout beyond removing the coder ternaries.
- If plan 002 is not applied yet, STOP: this plan builds on its `pop`, `PayoutBeats` and spec.

## Verification

- **Mechanical**: selene 0 errors; `lune run tests/offline/run` all pass.
- **Feel check** (Studio, Play, `hq:9` or later with coders seated, stand near the line): coder
  deliveries show a small "+$X" that fades in and out in about half a second, no bounce; the cash
  counter climbs with their 3 coins; your own hand-over is still the bigger moment.
- **Done when**: spec failed first then passed; the coder pop has no UIScale/Back; checks pass.
