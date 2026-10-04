"""lp_sky.py -- v4.1 the low-poly sky: a clean gradient, no painted clouds.

The old skybox (sky.py) painted soft Nishita cumulus near the horizon, which
argued with the faceted clouds and hills. Style B wants a flat, calm gradient.
Colour is a function of ELEVATION only, computed per pixel from each face's
view direction, so the faces meet without seams. The four sides are identical
(azimuth does not matter), so only three images upload: side, up, down.

Run with any Python that has Pillow:  python lp_sky.py -> out/lp_sky_{side,up,down}.png
"""
import math
import os
import random
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
N = 1024
ZENITH = (84, 142, 210)
HORIZON = (196, 220, 238)
HAZE = (224, 220, 208)          # meets the day Atmosphere colour at the horizon


def lerp(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[k] + (b[k] - a[k]) * t for k in range(3))


def colour(e):
    if e < 0:
        return HAZE
    if e < 5:
        return lerp(HAZE, HORIZON, e / 5)
    return lerp(HORIZON, ZENITH, ((e - 5) / 85) ** 0.62)


rng = random.Random(3)


def face(fn):
    im = Image.new("RGB", (N, N))
    px = im.load()
    for v in range(N):
        for u in range(N):
            a = (u + 0.5) / N * 2 - 1
            b = (v + 0.5) / N * 2 - 1
            d = fn(a, b)
            e = math.degrees(math.asin(d[1] / math.sqrt(d[0] ** 2 + d[1] ** 2 + d[2] ** 2)))
            c = colour(e)
            j = rng.uniform(-0.6, 0.6)      # a little dither: no banding in a big gradient
            px[u, v] = tuple(int(max(0, min(255, round(ch + j)))) for ch in c)
    return im


# a side face: image right = +X, image up = +Y, looking along -Z
face(lambda a, b: (a, -b, -1.0)).save(os.path.join(OUT, "lp_sky_side.png"))
# up: looking +Y
face(lambda a, b: (a, 1.0, b)).save(os.path.join(OUT, "lp_sky_up.png"))
# down: looking -Y
face(lambda a, b: (a, -1.0, b)).save(os.path.join(OUT, "lp_sky_down.png"))
print("sky faces written")
