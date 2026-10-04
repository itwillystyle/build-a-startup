"""
sun.py -- the big cartoon sun, as a Roblox sun texture.

Why a sun TEXTURE and not a sun painted on the skybox:
the game runs a 22-minute day/night cycle (SkyClient), so ClockTime moves and
Roblox's own sun tracks across the sky and sets. A sun painted into the skybox
would sit still while the real one moved, and would still be hanging there at
midnight. Restyling the real sun keeps every bit of that behaviour and only
changes how it looks.

v2 -- CARTOON, 3 Oct. The first version chased the LA travel poster: a pale
disc with a soft edge and a wide halo. It read as natural, which is what it was
aimed at, and natural is not what this game is. Low-poly flat-shaded world,
hard facets everywhere, and then one photographic glow in the sky.

What actually makes a drawn sun read as drawn, in order of strength:

  1. AN OUTLINE. A line darker than the fill, following the rim. This is the
     single strongest cue and the one the old version explicitly refused --
     the comment said "a sticker outline is the one thing a cartoon sun must
     not have", which is true of a GREY outline on a soft disc and false of a
     deeper-orange outline on a flat one. The outline is the cartoon.
  2. A HARD EDGE. Flat alpha to the rim, then 2px of anti-aliasing and stop.
     A soft falloff is the thing the eye reads as photographic bloom.
  3. A FLAT FILL. One colour across the whole disc. Any radial gradient makes
     a sphere; a drawn sun is a circle.
  4. SATURATION. Cream reads as light. Yellow reads as a drawing of the sun.

The halo stays, much tighter and fainter, because without any bleed at all the
disc sits ON the sky rather than in it, and Roblox composites the sun over the
skybox with no atmosphere of its own.

Output:
    art/out/sun_disc.png        the chosen sun
    art/out/moon_disc.png       the same treatment, cool, so nights match
    art/out/sun_preview.png     chosen sun + moon on the real sky grade
    art/out/sun_variants.png    all three candidates side by side

Run:  python art/sun.py            build the chosen variant
      python art/sun.py variants   also write the comparison sheet
"""

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
os.makedirs(OUT, exist_ok=True)

SIZE = 512
AA = 2.0          # px of anti-aliasing on every hard edge: enough to not crawl, too little to read as glow


def _radius():
    s = SIZE
    y, x = np.mgrid[0:s, 0:s]
    c = (s - 1) / 2.0
    return np.sqrt((x - c) ** 2 + (y - c) ** 2), (x - c), (y - c)


def _edge(r, at, soft=AA):
    """1 inside `at`, 0 outside, with `soft` px of anti-aliasing. A step, not a falloff."""
    return np.clip((at - r) / soft + 0.5, 0.0, 1.0)


def cartoon_disc(fill, line, core_r, line_w, halo_rgb, halo_r, halo_alpha,
                 rays=0, ray_len=0.0, ray_w=0.0, inner=None, inner_r=0.0):
    """
    Flat fill, hard rim, darker outline on the rim, optional rays and an
    optional lighter inner circle. Everything is a step with AA -- there is no
    smooth falloff anywhere except the halo.
    """
    r, dx, dy = _radius()
    s = SIZE

    rgb = np.zeros((s, s, 3), float)
    a = np.zeros((s, s), float)

    # --- the halo: the only soft thing, and it sits OUTSIDE the outline -------
    if halo_alpha > 0:
        t = np.clip((r - core_r) / max(halo_r - core_r, 1e-6), 0.0, 1.0)
        tail = (halo_alpha / 255.0) * (1.0 - t) ** 3
        tail = np.where(r < core_r, halo_alpha / 255.0, tail)
        tail = np.where(r >= halo_r, 0.0, tail)
        rgb[:] = np.array(halo_rgb, float)
        a = tail

    # --- rays: fixed to the disc, drawn under it -----------------------------
    if rays > 0 and ray_len > 0:
        ang = np.arctan2(dy, dx)
        k = rays
        # distance to the nearest ray centre line, in radians
        d = np.abs(((ang * k / (2 * math.pi)) % 1.0) - 0.5) * (2 * math.pi / k)
        # a ray is a wedge that narrows with distance
        reach = core_r + ray_len
        along = np.clip((r - core_r) / max(ray_len, 1e-6), 0.0, 1.0)
        halfw = ray_w * (1.0 - along)                     # taper to a point
        inside = (r > core_r * 0.9) & (r < reach) & (d < halfw)
        ray_a = np.where(inside, 1.0, 0.0)
        ray_a = np.clip(ray_a, 0.0, 1.0)
        rgb = np.where(ray_a[..., None] > 0, np.array(line, float), rgb)
        a = np.maximum(a, ray_a)

    # --- the outline, then the fill drawn inside it --------------------------
    line_m = _edge(r, core_r)                              # everything inside the rim
    fill_m = _edge(r, core_r - line_w)                     # everything inside the outline

    rgb = np.where(line_m[..., None] > 0, np.array(line, float), rgb)
    a = np.maximum(a, line_m)

    rgb = np.where(fill_m[..., None] > 0, np.array(fill, float), rgb)
    a = np.maximum(a, fill_m)

    # --- optional lighter inner circle (the classic two-tone drawn sun) ------
    if inner is not None and inner_r > 0:
        im = _edge(r, inner_r)
        rgb = np.where(im[..., None] > 0, np.array(inner, float), rgb)
        a = np.maximum(a, im)

    out = np.zeros((s, s, 4), np.uint8)
    out[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    out[..., 3] = np.clip(a * 255.0, 0, 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


# Palette. The fill is a real yellow; the outline is the same hue pushed down
# in value and up in chroma, never grey -- a grey line on a warm disc is the
# "sticker" failure the v1 comment was worried about.
SUN_FILL = (255, 226, 112)
SUN_LINE = (244, 158, 54)
SUN_INNER = (255, 243, 190)
SUN_HALO = (255, 198, 112)

MOON_FILL = (226, 236, 255)
MOON_LINE = (142, 170, 226)
MOON_INNER = (245, 249, 255)
MOON_HALO = (170, 196, 248)


def variant_a():
    """Flat fill + outline. The minimum that reads as drawn."""
    return cartoon_disc(SUN_FILL, SUN_LINE, core_r=150, line_w=9,
                        halo_rgb=SUN_HALO, halo_r=236, halo_alpha=40)


def variant_b():
    """A, plus short tapered rays."""
    return cartoon_disc(SUN_FILL, SUN_LINE, core_r=142, line_w=9,
                        halo_rgb=SUN_HALO, halo_r=232, halo_alpha=38,
                        rays=12, ray_len=56, ray_w=0.055)


def variant_c():
    """A, plus a lighter inner circle -- the classic two-tone drawn sun."""
    return cartoon_disc(SUN_FILL, SUN_LINE, core_r=150, line_w=9,
                        halo_rgb=SUN_HALO, halo_r=236, halo_alpha=40,
                        inner=SUN_INNER, inner_r=96)


VARIANTS = {"A flat + outline": variant_a, "B + rays": variant_b, "C + inner circle": variant_c}

# The one that ships. A, not B or C:
#   B's rays are clipart, and because the sun TRACKS and SETS, spiky rays
#     crossing the hills read as a sticker pasted on the sky.
#   C's inner circle reads as a fried egg and adds a second concentric shape
#     that means nothing -- it is the sphere problem in reverse.
#   A is the same language as the world: flat fill, hard edge, one colour
#     per surface, one line around it.
CHOSEN = "A flat + outline"


def build_moon():
    # same rule as the sun: flat + outline, no inner circle
    return cartoon_disc(MOON_FILL, MOON_LINE, core_r=118, line_w=7,
                        halo_rgb=MOON_HALO, halo_r=190, halo_alpha=28)


def sky(W, H):
    """The grade the sun is actually seen against, so it is judged in context."""
    bg = Image.new("RGB", (W, H))
    px = bg.load()
    top, mid, low = (86, 170, 180), (252, 226, 170), (238, 134, 62)
    for y in range(H):
        t = y / (H - 1)
        if t < 0.55:
            k = t / 0.55
            c = [top[i] + (mid[i] - top[i]) * k for i in range(3)]
        else:
            k = (t - 0.55) / 0.45
            c = [mid[i] + (low[i] - mid[i]) * k for i in range(3)]
        row = tuple(int(v) for v in c)
        for x in range(W):
            px[x, y] = row
    return bg


def hills(bg):
    W, H = bg.size
    d = ImageDraw.Draw(bg)
    d.polygon([(0, H), (0, int(H * 0.83)), (int(W * 0.22), int(H * 0.68)),
               (int(W * 0.43), int(H * 0.81)), (int(W * 0.65), int(H * 0.65)),
               (int(W * 0.87), int(H * 0.78)), (W, int(H * 0.71)), (W, H)],
              fill=(58, 74, 66))
    return bg


def write_variants():
    cell = 420
    pad = 24
    W = pad + (cell + pad) * len(VARIANTS)
    H = cell + 96
    sheet = hills(sky(W, H))
    d = ImageDraw.Draw(sheet)
    for i, (name, fn) in enumerate(VARIANTS.items()):
        img = fn().resize((cell, cell), Image.LANCZOS)
        x = pad + i * (cell + pad)
        sheet.paste(img, (x, 20), img)
        d.text((x + 8, H - 60), name, fill=(28, 34, 44))
    sheet.save(os.path.join(OUT, "sun_variants.png"))
    print("wrote sun_variants.png")


def write_preview(sun, moon):
    W, H = 1200, 520
    bg = sky(W, H)
    s = sun.resize((430, 430), Image.LANCZOS)
    bg.paste(s, (160, 140), s)
    m = moon.resize((300, 300), Image.LANCZOS)
    bg.paste(m, (770, 60), m)
    hills(bg)
    bg.save(os.path.join(OUT, "sun_preview.png"))


def build():
    sun = VARIANTS[CHOSEN]()
    sun.save(os.path.join(OUT, "sun_disc.png"))
    moon = build_moon()
    moon.save(os.path.join(OUT, "moon_disc.png"))
    write_preview(sun, moon)
    print("wrote sun_disc.png (%s), moon_disc.png, sun_preview.png to %s" % (CHOSEN, OUT))


if __name__ == "__main__":
    if "variants" in sys.argv:
        write_variants()
    build()
