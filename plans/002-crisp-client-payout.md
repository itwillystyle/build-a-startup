# 002 — Make the per-client payout crisp (about 1.4 s, no bounce, cash counts with the coins)

- **Status**: DONE (23 Oct, branch crisp-payout, verified live in Studio)
- **Commit**: 084bd8b
- **Severity**: HIGH
- **Category**: 1. Purpose & frequency, 2. Easing & duration, 3. Physicality
- **Estimated scope**: 1 new pure module + 1 new spec + ClientFxClient (~80 lines changed)

## Problem

Every client hand-over (every 10-60 s, all game long) plays this in
`src/StarterPlayer/StarterPlayerScripts/ClientFxClient.client.lua`. The file's own header says
it should take "About a second, so it stays quick on the fiftieth client" (line 10). It takes
about 2.4 s and fires up to six Back (overshoot) pops:

- `fly` (line 93): 0.32 s, cubic out `1 - (1 - a) ^ 3`, 70 px arc, -20° tilt. The start and end
  are screen points computed once, so a moving camera leaves the tile behind.
- `opened` (line 288): the stars card enters with `Moment.enter(sc, 0.4, 0.25)` (Back);
  three stars start at `isc.Scale = 0` and `Moment.enter(isc, 0, 0.3 or 0.18)` (Back, from
  nothing); the card leaves at 1.1 s over 0.3 s.
- `cash` (line 329) runs 0.45 s after the fly lands. `pop` (line 50) enters with
  `Moment.enter(sc, 0.4, 0.3)` (Back), holds 0.7 s, then rises 40 px and fades over 0.6 s.
  The tip pops the same way 0.25 s later.
- `Moment.landMoney(at, 6)` flies coins in, but passes no amount, so the cash counter has
  already jumped to the new total before any coin arrives.

```lua
-- ClientFxClient.client.lua:329-336 — current
local function cash(d, at, coder)
	pop("+" .. UIKit.money(d.pay), at, coder and UIKit.TYPE.title or UIKit.TYPE.headline, UIKit.MONEY)
	if (d.tip or 0) > 0 then
		pop("+" .. UIKit.money(d.tip) .. " TIP", at + Vector2.new(0, 34), UIKit.TYPE.label, UIKit.GOLD, 0.25)
	end
	Moment.landMoney(at, coder and 3 or 6)
	if not coder then UIKit.sfx("ding", 1.2, 0.5) end
end
```

The picked mock (`silicon-startup/ui/animation-review/mp4/1-payout.mp4`, panel B) is the target.

## Target

The beats (all times from the moment the tile leaves your hands), held in a new pure module:

| Beat | Value |
|---|---|
| fly | 0.28 s, Quint Out (`1 - (1 - a) ^ 5`), 50 px arc, -12° tilt; start and end re-projected from WORLD points every frame |
| stars card in | at 0.28 s: UIScale 0.94 → 1 and fade in, 0.15 s, Quint Out |
| each star | at 0.28 + 0.06 + (i-1) × 0.04 s: UIScale 0.9 → 1 and ImageTransparency 1 → 0, 0.12 s, Quint Out (the ding per star stays) |
| stars card out | at 0.28 + 0.75 s: rise 12 px and fade, 0.2 s, Quint Out |
| money in | at 0.40 s: "+$pay" and "+$tip tip" together (tip 30 px below), UIScale 0.94 → 1 and fade in, 0.15 s, Quint Out |
| money hold / out | holds 0.6 s, then rises 8 px and fades, 0.2 s, Quint Out |
| coins | at 0.40 s, 6 coins through `_G.SVCoinStream(at, 6, nil, pay + tip, { prepaid = true })`; the amount is held back with `_G.SVCashHold(pay + tip)` the moment the payout starts, so the counter counts up coin by coin (exactly as `wow()` does at line 268-282) |

No `Enum.EasingStyle.Back`, no `Moment.enter`, and no scale from 0 anywhere in the routine payout.
The first-ship `wow()` (line 166) is NOT changed.

New module `src/ReplicatedStorage/PayoutBeats.lua` (pure, no services), matching the style of
`src/ReplicatedStorage/ShipMoment.lua`:

```lua
local PayoutBeats = {}
PayoutBeats.FLY = { seconds = 0.28, arc = 50, tilt = -12 }
PayoutBeats.CARD = { from = 0.94, enter = 0.15, leaveAt = 0.75, leave = 0.2, rise = 12 }
PayoutBeats.STAR = { first = 0.06, gap = 0.04, from = 0.9, enter = 0.12 }
PayoutBeats.MONEY = { at = 0.40, from = 0.94, enter = 0.15, hold = 0.6, leave = 0.2, rise = 8, tipGap = 30 }
PayoutBeats.COINS = 6
-- the money label is the last thing on screen
function PayoutBeats.duration()
	local m = PayoutBeats.MONEY
	return m.at + m.enter + m.hold + m.leave
end
return PayoutBeats
```

## Repo conventions to follow

- TDD is the rule here: write `tests/offline/payoutbeats.spec.luau` first, run it, watch it fail,
  then write the module. Exemplar spec: `tests/offline/shipmoment.spec.luau` (same `test(name, fn)`
  list, `return T`). The runner is `lune run tests/offline/run`.
- Pure timing lives in a ReplicatedStorage module; the client script reads it
  (exemplar: `ShipMoment` used by `wow()` in ClientFxClient).
- Overshoot is only allowed on lines marked `-- reward` (`tests/offline/uistyle.spec.luau`); this
  plan removes overshoot from the routine payout, it must not add any.
- Fading outlined text: fade the UIStroke too, or a black ghost stays (see `fadeText` in
  HudClient.client.lua:78-80 and the stroke fades in `pop`).
- Comments: dated, plain words, say why (`-- 23 Oct (animation review): ...`).

## Steps

1. Write `tests/offline/payoutbeats.spec.luau` with these tests, run it, and see it fail
   (module missing):
   - "the payout is over by 1.4 s (the header promised about a second; it was 2.4 s)":
     `PayoutBeats.duration() <= 1.4` and `>= 1.0`.
   - "every star is in before the card leaves": the last star's start + enter
     (`FLY.seconds + STAR.first + 2 * STAR.gap + STAR.enter`) is `< FLY.seconds + CARD.leaveAt`.
   - "nothing starts from nothing": `CARD.from >= 0.9`, `STAR.from >= 0.9`, `MONEY.from >= 0.9`.
   - "UI moves stay under 300 ms": `FLY.seconds`, `CARD.enter`, `CARD.leave`, `STAR.enter`,
     `MONEY.enter`, `MONEY.leave` are all `<= 0.3`.
2. Create `src/ReplicatedStorage/PayoutBeats.lua` as in Target. Run the tests: all pass.
3. In ClientFxClient: `local PayoutBeats = require(ReplicatedStorage:WaitForChild("PayoutBeats"))`
   next to the ShipMoment require (line 19).
4. Rewrite `fly(fromWorld, toWorld, done)` to take Vector3 world points and re-project both with
   `screenAt` inside the RenderStepped loop; use `PayoutBeats.FLY` (Quint Out `1 - (1 - a) ^ 5`,
   arc, tilt). Keep the `UIKit.sfx("tap", 0.75, 0.5)` line and its comment.
5. Rewrite `opened(at, stars)` to the CARD and STAR beats above: card UIScale `CARD.from` → 1 plus
   BackgroundTransparency 1 → 0 and its UIStroke Transparency 1 → 0 over `CARD.enter`; each star's
   UIScale `STAR.from` → 1 plus ImageTransparency 1 → 0 over `STAR.enter` at its delay; the card
   leaves at `CARD.leaveAt` (rise `CARD.rise`, fade over `CARD.leave`, stars' ImageTransparency too).
   Use the file's `ease` helper (Quint Out). Keep the "thunk" and per-star "ding" sounds.
6. Rewrite `pop(text, at, size, colour, delay, hold)` to: UIScale `MONEY.from` → 1 plus
   TextTransparency 1 → 0 and the UIStroke's Transparency 1 → 0 over `MONEY.enter`; after `hold`
   (default `MONEY.hold`), rise `MONEY.rise` px and fade text and stroke over `MONEY.leave`; destroy after.
   (`pop` is only used by `cash`; `wow()` does not use it.)
7. Rewrite `cash(d, at, coder)` for a non-coder payout: pop "+$pay" (TYPE.headline, MONEY) and,
   if tipped, "+$tip tip" (TYPE.label, GOLD) `MONEY.tipGap` px below with NO extra delay; then
   coins: if both `_G.SVCashHold` and `_G.SVCoinStream` exist, call
   `stream(at, PayoutBeats.COINS, nil, d.pay + (d.tip or 0), { prepaid = true })`, else
   `Moment.landMoney(at, PayoutBeats.COINS)`. Keep the "ding". (Plan 003 changes the coder branch;
   leave `coder == true` behaving as today in this plan.)
8. In the `clientPaid.OnClientEvent` handler (line 341 onward), for the starred payout path
   (the one that calls `fly`): call `_G.SVCashHold(d.pay + (d.tip or 0))` FIRST (only when both
   `_G.SVCashHold` and `_G.SVCoinStream` exist), then
   `fly(d.from + Vector3.new(0, 1.5, 0), where + Vector3.new(0, 3, 0), function() ... end)`; inside,
   `opened(...)` immediately and `task.delay(PayoutBeats.MONEY.at - PayoutBeats.FLY.seconds, function() cash(d, at + Vector2.new(0, 30), false) end)`.
   The no-stars path (`cash(d, at, false)` at line 359) also holds first, then calls cash.
9. Update the header comment (lines 1-11) for 2A to say the payout is about 1.4 s with no bounce,
   dated 23 Oct, citing the animation review.

## Boundaries

- Do NOT touch `wow()`, `sparks`, `anchorAt`, `board`, `ShipMoment.lua` (the first-ship celebration, picked 22 Oct).
- Do NOT touch HudClient (the coin stream already supports `prepaid`).
- Do NOT change the server or the `ClientPaid` payload.
- No `Enum.EasingStyle.Back`, `Moment.enter`, or scale-from-0 in the routine payout.
- If the code at the cited lines differs, STOP and report.

## Verification

- **Mechanical**: from `Downloads/silicon-startup/game`: `~/.rokit/bin/selene src` → 0 errors;
  `~/.rokit/bin/lune run tests/offline/run` → all pass, including the new spec (and `uistyle.spec`).
- **Feel check** (Studio, Play, hand an app to a client): the tile arcs to the client in a blink;
  the stars card appears without a bounce and the stars come in quickly in order; "+$X" (and the
  tip, together) appear by the client and leave about a second later; the cash counter goes up as
  each coin lands, not before. Drive a car or turn the camera during the hand-over: the tile still
  lands on the client.
- **Done when**: the spec exists and passed after failing first; ClientFxClient uses PayoutBeats;
  no Back/`Moment.enter` remains in `fly`, `opened`, `pop`, `cash`; selene and all offline tests pass.
