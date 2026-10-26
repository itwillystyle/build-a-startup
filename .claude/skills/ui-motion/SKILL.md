---
name: ui-motion
description: Build or fix any GUI that appears, moves, fades or animates in Build a Startup! (speech bubbles, pop-ups, toasts, cards, burst words, HUD transitions). Use when Luke says a pop-up looks static, glitchy, sloppy, "inverted" or pops in wrong, and before writing any UIScale, GroupTransparency or tween code. Emil Kowalski's motion rules, translated to Roblox.
---

# ui-motion

Emil Kowalski's rules (installed skill `emil-design-eng`; also `animate`, `improve-animations`)
are written for the web. This is what each one is in Roblox, plus the traps hit on 25 Oct 2026,
when the "He will rue the day." bubble flashed up "in the middle, inverted".

| Emil's rule | In Roblox | Trap we hit |
|---|---|---|
| Never animate from scale(0) | `UIScale` from 0.6 (playful) to 0.95 (UI), with a fade | From 0 the first frame was a 44x9 px sliver |
| Scale from the origin (transform-origin) | `UIScale` scales about the object's `AnchorPoint`: put the anchor where it comes from (a bubble's tail) and position by that point | Anchored at the bottom middle, a bubble beside a head grew out of its middle and its tail swept across |
| Fade a group as one (opacity on a group) | Put it in a `CanvasGroup`, fade `GroupTransparency`. It clips to its bounds: pad it for tails and shadows. Low-memory devices fall back to no fade | Fading each piece let them show through each other: the ink shadow greyed the card, the tail doubled |
| Ease-out, short: UI under 0.3 s; a small overshoot only if playful | 0.2-0.3 s, overshoot 4% at most | 0.35 s with a 10% overshoot looked rubbery |
| Exit faster than enter | Shrink to 0.94 and fade in the last 0.12-0.15 s, BEFORE the content ends (so it never crosses a cut) | Bubbles vanished in one frame |
| Purpose: make it alive, not busy | Typewriter with `TextLabel.MaxVisibleGraphemes` (layout does not reflow; count the plain text, not RichText tags); a shout ("...!") shakes 2 degrees and settles | Static boxes |
| Reduced motion: gentler, not none | `UIKit.reducedMotion()`: keep the fade, drop scale, typing and shake | |

## How to build it

- Put the LOOK in a pure function in a ReplicatedStorage module (example: `BobScript.bubbleLook(b, t, reduced)`
  returns `{ scale, alpha, reveal, shake }`). The client only applies it. Then the offline tests
  can check: first frame scale >= 0.6 and nearly transparent, overshoot <= 1.06, opaque by 0.12 s,
  gone before the line ends, Reduce Motion = no motion.
- New UI motion goes through `UIKit.tween` or a tagged line (the motionguard test counts hand-built
  tweens). An AUDIO fade is not UI motion: step the volume yourself (see `fadeOut` in BobSceneClient).
- Fonts and sizes come from UIKit (`UIKit.COMIC`, `UIKit.IMPACT`, `UIKit.TYPE`); the uistyle spec enforces them.

## How to check it (I can't trust a glance)

- Log the first frames: every frame, `AbsolutePosition`, `AbsoluteSize`, `UIScale.Scale`,
  `GroupTransparency`, `AnchorPoint`. A pop that grows from its origin keeps the origin's pixel fixed.
- `screen_capture` does NOT show `GroupTransparency`: confirm a fade from the properties, not the picture.
- Frozen frames: `BobSceneHold = t` (Studio only), `BobSkipNow = true` ends a held scene.
- Phones: most players are on phones (UI autoScale 0.69x). Check sizes there before calling it done.
