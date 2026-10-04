# V8: rendered HUD icons + press motion (27 Sep 2026)

![icons](icons_v8_sheet.png)

**The problem:** every HUD button showed a flat white Kenney glyph on a coloured square, the "2019" tell ART.md names ("UI whose whole look is flat rectangle + text + gradient"). **The target** (ART.md): icons rendered from the game's own models under one light rig, the way the top Roblox games get "illustrated" icons.

## What changed

- **Nine icons**, modelled and rendered in Blender (`blender/icons.py`, then `icons_post.py`):

  | Icon | Where |
  |---|---|
  | phone | the PHONE rail button |
  | shopping bag | BAG |
  | fanned ID badges | INDEX |
  | potted plant | DECOR (decor = vibe) |
  | headphones | music |
  | laptop showing `</>` | WRITE CODE |
  | the game's own rocket | LAUNCH |
  | a target with a dart | the quest card |
  | a gold coin | the money counter |

- **One style for all nine:**
  - clay-like and bevelled, in the palette colours
  - the same light rig (warm key from the upper left, cool rim)
  - a dark sticker outline so each one reads on any button colour at 45 px
- **Nine image uploads** on your account. The IDs are in `UIKit.ART`.
- **One change in UIKit:** any button whose icon key has art uses it automatically. It's drawn larger than the glyph and pops 9 px above the button's top edge, like a sticker (Run a Restaurant!'s rail does the same). The small glyphs elsewhere (role icons, close, check) are unchanged; they're fine at their size.
- **Music:** muting now fades the headphones instead of swapping to a different glyph.
- **Press motion:** every button now squishes in fast and springs back with about a 6% overshoot (ART.md: springs, 8% overshoot at most). The old flat return read as dead.

**Verified in Play:**
- all four rail buttons carry their art
- the coin, WRITE CODE, the quest card, the LAUNCH card and the music toggle all show their art
- muting fades the headphones (60%) and unmuting restores them
- no console errors
- Studio matches disk for all 6 changed scripts
- your save was snapshotted (`11510645938_pre_v38`: HQ 4, $7.42M) and restored

**Dropped on purpose:** the render's soft contact shadow. Once cropped to the icon, it became a grey slab under every object; the sticker outline grounds each icon instead.

## Not done in this phase, and why

- **9-slice button and panel skins.** UIKit's buttons already have a lip, a stroke and now a spring. Re-skinning every panel with images touches every screen in the game, 15 days before launch, for a smaller gain than the icons. It's the first thing to do post-launch if the phone test says the HUD still reads flat.
- **Role icons in the Index** (engineer, designer, sales, recruiter, research): still glyphs. Five more renders is a small follow-up.

## Files

- **Changed:** UIKit (609 lines), HudClient (557), ProductClient (463), GuideClient (380), MusicClient (134).
- **Backups:** `*_pre_v38.lua`.
- **New:** `blender/icons.py`, `blender/icons_post.py`, `blender/out/icons/SV_Icon_*.png`.
