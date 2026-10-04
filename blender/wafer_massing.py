"""
wafer_massing.py -- old vs new silhouette, side by side.

A massing study, not a render of the real kit. Each wafer is drawn as the ring
it actually is (outer radius r, inner r - DEPTH, H tall per storey) at its real
centre and height, plus the garden decks between them. That is enough to judge
the one thing being changed -- whether the stack reads as a building or a pile --
and it takes seconds instead of assembling 40 FBX.

Run:  blender -b --python blender/wafer_massing.py
Out:  blender/out/wafer_massing.png
"""

import bpy
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import svkit as K  # noqa: E402
from mathutils import Vector  # noqa: E402

OUT = os.path.join(HERE, "out")
os.makedirs(OUT, exist_ok=True)

H, DEPTH, FLOOR_Y, SLAB = 13.0, 20.0, 1.0, 1.5

# (cx, cz, r) per wafer
OLD = {1: (0, 0, 60), 2: (8, -5, 64), 3: (-6, -6, 58), 4: (3, -8, 54)}
NEW = {1: (0, 0, 60), 2: (6, -4, 56), 3: (12, -8, 52), 4: (18, -12, 48)}

# wafer -> its office storeys; the deck sits on the storey after each wafer
STOREYS = {1: [0, 1], 2: [3, 4, 5], 3: [7, 8, 9], 4: [11, 12, 13]}
DECK_STOREY = {1: 2, 2: 6, 3: 10}
ROOF_STOREY = 14

SHELL = K.rgb(236, 232, 222)
GLASS = K.rgb(132, 172, 190)
DECK = K.rgb(122, 170, 80)
CORE = K.rgb(200, 206, 212)


def ring(name, cx, cz, r, y0, y1, color):
    """An annulus: outer cylinder minus the courtyard. Blender Z is up."""
    import bmesh

    bm = bmesh.new()
    segs = 48
    inner = max(r - DEPTH, 2.0)
    for i in range(segs):
        a0 = i / segs * math.tau
        a1 = (i + 1) / segs * math.tau
        for rr0, rr1, flip in ((inner, r, False),):
            p = [
                (cx + math.cos(a0) * rr0, cz + math.sin(a0) * rr0),
                (cx + math.cos(a1) * rr0, cz + math.sin(a1) * rr0),
                (cx + math.cos(a1) * rr1, cz + math.sin(a1) * rr1),
                (cx + math.cos(a0) * rr1, cz + math.sin(a0) * rr1),
            ]
            top = [bm.verts.new((x, z, y1)) for x, z in p]
            bot = [bm.verts.new((x, z, y0)) for x, z in p]
            bm.faces.new(top)
            bm.faces.new(bot[::-1])
            for k in range(4):
                n = (k + 1) % 4
                bm.faces.new([bot[k], bot[n], top[n], top[k]])
    bm.normal_update()
    o = K.mesh_obj(name, bm)
    K.paint(o, K.shaded(color))
    return o


def build(geo, ox, label):
    objs = []
    for w, st in STOREYS.items():
        cx, cz, r = geo[w]
        y0 = FLOOR_Y + st[0] * H
        y1 = FLOOR_Y + (st[-1] + 1) * H
        objs.append(ring(f"{label}_W{w}", cx + ox, cz, r, y0, y1, SHELL))
    for w, s in DECK_STOREY.items():
        cx, cz, r = geo[w]
        y = FLOOR_Y + s * H
        objs.append(ring(f"{label}_D{w}", cx + ox, cz, r - 2, y, y + 3.0, DECK))
    cx, cz, r = geo[4]
    objs.append(ring(f"{label}_Roof", cx + ox, cz, r - 4, FLOOR_Y + ROOF_STOREY * H,
                     FLOOR_Y + ROOF_STOREY * H + 3.0, DECK))
    # the lift core: vertical, never leans
    objs.append(ring(f"{label}_Core", 0 + ox, -26, 8, 0, FLOOR_Y + (ROOF_STOREY + 1) * H, CORE))
    return objs


def main():
    K.reset()
    objs = build(OLD, -150, "old") + build(NEW, 150, "new")
    # a ground plane so the two silhouettes share a baseline
    bpy.ops.mesh.primitive_plane_add(size=460, location=(0, 0, 0))
    g = bpy.context.object
    K.paint(g, K.flat(K.rgb(206, 200, 186)))
    objs.append(g)

    K.preview(os.path.join(OUT, "wafer_massing.png"), objs,
              size=(1700, 820), elev=10, azim=18,
              target=None)
    print("wrote", os.path.join(OUT, "wafer_massing.png"))
    print("OLD r:", [OLD[w][2] for w in (1, 2, 3, 4)], " centres:", [(OLD[w][0], OLD[w][1]) for w in (1, 2, 3, 4)])
    print("NEW r:", [NEW[w][2] for w in (1, 2, 3, 4)], " centres:", [(NEW[w][0], NEW[w][1]) for w in (1, 2, 3, 4)])


if __name__ == "__main__":
    main()
