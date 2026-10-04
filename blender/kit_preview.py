"""
kit_preview.py -- assemble a real kit and render it, so a path can be judged
before 40 FBX get imported.

It calls the kit's own builders and places each piece where WaferPlan puts it,
rather than round-tripping through FBX. Same geometry, no import step.

Run:  blender -b --python blender/kit_preview.py -- kit=terrafab
      blender -b --python blender/kit_preview.py -- kit=wafers
Out:  blender/out/kit_<name>.png
"""

import bpy
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import svkit as K  # noqa: E402
import wafers as W  # noqa: E402

OUT = os.path.join(HERE, "out")
os.makedirs(OUT, exist_ok=True)

H, SLAB = W.H, W.SLAB
FLOOR_Y = 1.0
WAFER = W.WAFER
STOREYS = {1: [0, 1], 2: [3, 4, 5], 3: [7, 8, 9], 4: [11, 12, 13]}
DECK_STOREY = {1: 2, 2: 6, 3: 10}
ROOF_STOREY = 14
SEG_DEG = 45.0


def place(obj, cx, cz, y, deg):
    """The game anchors a piece at its wafer centre, rotated to its segment.
    Blender here: X = -Roblox X, Y = Roblox Z, Z = Roblox Y (wafers.py frame)."""
    a = math.radians(deg)
    obj.rotation_euler = (0.0, 0.0, a)
    obj.location = (-cx, cz, y)


def build(kitmod, prefix):
    made = []

    def mk(name, builder, cx, cz, y, deg):
        shell, glass = builder()
        o = shell.to_object("%s_%d" % (name, len(made)))
        place(o, cx, cz, y, deg)
        made.append(o)
        if glass is not None:
            g = glass.to_object("%sG_%d" % (name, len(made)))
            place(g, cx, cz, y, deg)
            made.append(g)

    for w, sts in STOREYS.items():
        cx, cz, r = WAFER[w]
        for st in sts:
            y = FLOOR_Y + st * H - SLAB      # the mesh frame starts at the slab bottom
            for seg in range(1, 9):
                deg = (seg - 1) * SEG_DEG
                # segment 5 is the back, where the lift bridge lands
                if seg == 5:
                    mk("segB", lambda w=w: kitmod.build_segment(w, "bridge"), cx, cz, y, deg)
                elif w == 1 and st == 0 and seg == 1:
                    mk("lobby", lambda: kitmod.build_segment(1, "lobby"), cx, cz, y, deg)
                else:
                    mk("seg", lambda w=w: kitmod.build_segment(w, "plain"), cx, cz, y, deg)

    for w, st in DECK_STOREY.items():
        cx, cz, r = WAFER[w]
        y = FLOOR_Y + st * H - SLAB
        mk("deck", lambda w=w: kitmod.build_deck(w), cx, cz, y, 0)
        shell, _ = kitmod.build_deck_columns(w)
        o = shell.to_object("cols_%d" % w)
        place(o, cx, cz, y, 0)
        made.append(o)

    cx, cz, r = WAFER[4]
    y = FLOOR_Y + ROOF_STOREY * H - SLAB
    mk("roof", kitmod.build_roof, cx, cz, y, 0)
    for k in range(4):
        mk("pav", kitmod.build_pavilion, cx, cz, y + SLAB, k * 90.0)
    shell, _ = kitmod.build_halo()
    o = shell.to_object("halo")
    place(o, cx, cz, y + SLAB + H * 0.9, 0)
    made.append(o)

    # v7 BASE AND CROWN: the two pieces that stop the tower being pure shaft
    if hasattr(kitmod, "build_podium"):
        cx1, cz1, _ = WAFER[1]
        mk("podium", kitmod.build_podium, cx1, cz1, 0.0, 0)
    if hasattr(kitmod, "build_crown"):
        mk("crown", kitmod.build_crown, cx, cz, y + SLAB + H * 0.2, 0)
    return made


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    which = "terrafab"
    for a in args:
        if a.startswith("kit="):
            which = a[4:]
    kitmod = __import__(which)

    K.reset()
    objs = build(kitmod, which)
    bpy.ops.mesh.primitive_plane_add(size=360, location=(0, 0, 0))
    g = bpy.context.object
    K.paint(g, K.flat(K.rgb(206, 200, 186)))
    objs.append(g)

    K.preview(os.path.join(OUT, "kit_%s.png" % which), objs, size=(1000, 1150), elev=10, azim=26)
    print("wrote kit_%s.png  (%d objects)" % (which, len(objs)))


if __name__ == "__main__":
    main()
