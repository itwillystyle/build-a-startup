"""Generate the tiling PBR detail maps for the HQ kits.

WHY THESE MAPS LOOK LIKE ALMOST NOTHING. The palette is the game's whole
cohesion strategy, and a normal ColorMap would throw it away: SurfaceAppearance
replaces the colour pipeline. The engine's one escape hatch is AlphaMode
Overlay (the default), which "reveals the base colour of the mesh anywhere
transparency is present" -- so the ColorMap here is ~92% transparent and
carries only grain. MeshPart.Color still drives the hue; the texture only adds
the dirt a flat surface does not have.

The real work is done by the normal and roughness maps, which do not touch
colour at all.

Everything is TILEABLE: the UVs are world-proportional (one tile per 8 studs),
so a seam would repeat across every building in the game. The noise is built on
a wrapped lattice for that reason.

    python pbr_maps.py            -> blender/out/pbr/*.png
"""
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out", "pbr")
SIZE = 1024
os.makedirs(OUT, exist_ok=True)

rng = np.random.default_rng(20261006)


def lattice(cells, size=SIZE):
    """Value noise on a WRAPPED lattice -- the last column equals the first, so
    the result tiles with no seam."""
    g = rng.random((cells, cells))
    g = np.vstack([g, g[:1]])
    g = np.hstack([g, g[:, :1]])
    y = np.linspace(0, cells, size, endpoint=False)
    x = np.linspace(0, cells, size, endpoint=False)
    xi, yi = np.meshgrid(x, y)
    x0, y0 = np.floor(xi).astype(int), np.floor(yi).astype(int)
    fx, fy = xi - x0, yi - y0
    # smoothstep, so the lattice does not show as diamonds
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    a = g[y0, x0] * (1 - fx) + g[y0, x0 + 1] * fx
    b = g[y0 + 1, x0] * (1 - fx) + g[y0 + 1, x0 + 1] * fx
    return a * (1 - fy) + b * fy


def fbm(octaves=(4, 8, 16, 32), weights=(0.5, 0.25, 0.15, 0.10)):
    out = np.zeros((SIZE, SIZE))
    for c, w in zip(octaves, weights):
        out += lattice(c) * w
    return (out - out.min()) / (np.ptp(out) + 1e-9)


def save(name, arr, mode="RGB"):
    img = Image.fromarray(arr.astype(np.uint8), mode)
    path = os.path.join(OUT, name)
    img.save(path, optimize=True)
    print("%-22s %s  %d KB" % (name, img.size, os.path.getsize(path) // 1024))


height = fbm()
fine = fbm(octaves=(64, 128), weights=(0.6, 0.4))
surface = height * 0.72 + fine * 0.28

# ---- normal: the slope of the height field, which is what sells a surface ----
# wrap the gradient so the derivative tiles too
gy, gx = np.gradient(surface * 2.4)
gx = np.roll(gx, 0, axis=1)
nz = np.ones_like(gx)
ln = np.sqrt(gx * gx + gy * gy + nz * nz)
normal = np.dstack([(-gx / ln * 0.5 + 0.5) * 255,
                    (-gy / ln * 0.5 + 0.5) * 255,
                    (nz / ln * 0.5 + 0.5) * 255])
save("sv_detail_normal.png", normal)

# ---- roughness: architectural concrete is matte and unevenly so ----
rough = 0.62 + 0.20 * (surface - 0.5) + 0.06 * (fine - 0.5)
rough = np.clip(rough, 0.35, 0.92) * 255
save("sv_detail_rough.png", np.dstack([rough, rough, rough]))

# ---- colour: nearly all transparent, so the palette shows through ----
# a faint darkening in the hollows plus a sparse fleck, nothing else
grime = np.clip((0.55 - surface) * 1.5, 0, 1)
fleck = (lattice(256) > 0.86).astype(float)
alpha = np.clip(grime * 0.10 + fleck * 0.05, 0, 0.14) * 255
tone = np.full((SIZE, SIZE), 86.0)      # a dark grey, only ever seen at low alpha
colour = np.dstack([tone, tone, tone, alpha])
save("sv_detail_color.png", colour, mode="RGBA")

print("\nmean colour alpha %.3f (0 = palette fully visible, 1 = palette destroyed)"
      % (alpha.mean() / 255.0))
