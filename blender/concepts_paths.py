"""
concepts_paths.py -- the three HQ paths, as massing concepts.

The player picks one at the start and their whole company is built in that
style. All three share ONE skeleton so the economy never forks: same storey
height, same 100 levels, same deck positions, same vertical lift core, same
8 segments per storey. Only the SKIN changes. That is the only version of
this that is shippable; three different plans would be three different
economies to balance and three sets of bugs.

  1  WAFERS    stacked leaning rings + open garden floors   (Samsung San Jose)
  2  TERRAFAB  orthogonal bays + central chase + fan deck   (a real chip fab)
  3  DOME      layered tent canopies tapering to ground     (Google Bay View)

Each is researched, not invented:

WAFERS -- Samsung's San Jose HQ is ten storeys read as three stacked "wafers"
of office (their word), separated by open garden floors, with 180ft
cantilevered trusses. Already built; drawn here for comparison.

TERRAFAB -- a real fab is four levels: fan deck on top, cleanroom, clean
subfab, utility. The cleanroom is column-free under long-span trusses, and
the floorplan is "bay and chase": parallel tool bays either side of a central
service corridor. Intel's Arizona site runs 30 miles of OVERHEAD TRACK moving
wafers between buildings -- that track is the signature nobody puts in a game,
and it is the one piece that moves.

DOME -- Bay View's roofs are tent-like, loosely domed, and taper toward
ground level, carried on slim white columns, with clerestory windows between
every curved panel letting light in at the seams. The solar skin is made of
overlapping scales.

Run:  blender -b --python blender/concepts_paths.py
Out:  blender/out/concepts_paths.png        all three, side by side
      blender/out/concept_<name>.png        one each, closer
"""

import bmesh
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

# ---- the shared skeleton (WaferPlan.lua W.GEO) ----
H, DEPTH, FLOOR_Y = 13.0, 20.0, 1.0
TIERS = {1: (0, 0, 60), 2: (6, -4, 56), 3: (12, -8, 52), 4: (18, -12, 48)}
STOREYS = {1: [0, 1], 2: [3, 4, 5], 3: [7, 8, 9], 4: [11, 12, 13]}
DECK_STOREY = {1: 2, 2: 6, 3: 10}
ROOF_STOREY = 14

PAPER = K.rgb(236, 232, 222)
STEEL = K.rgb(188, 192, 198)
GLASS = K.rgb(132, 172, 190)
LAWN = K.rgb(122, 170, 80)
CORE = K.rgb(200, 206, 212)
DARK = K.rgb(96, 100, 108)
SOLAR = K.rgb(150, 166, 188)
WARM = K.rgb(214, 170, 110)


def obj_from(bm, name, color):
    o = K.mesh_obj(name, bm)
    K.paint(o, K.shaded(color))
    return o


def ring_bm(bm, cx, cz, rin, rout, y0, y1, segs=48, arc=math.tau, a0=0.0):
    for i in range(segs):
        b0 = a0 + i / segs * arc
        b1 = a0 + (i + 1) / segs * arc
        p = [
            (cx + math.cos(b0) * rin, cz + math.sin(b0) * rin),
            (cx + math.cos(b1) * rin, cz + math.sin(b1) * rin),
            (cx + math.cos(b1) * rout, cz + math.sin(b1) * rout),
            (cx + math.cos(b0) * rout, cz + math.sin(b0) * rout),
        ]
        top = [bm.verts.new((x, z, y1)) for x, z in p]
        bot = [bm.verts.new((x, z, y0)) for x, z in p]
        bm.faces.new(top)
        bm.faces.new(bot[::-1])
        for k in range(4):
            n = (k + 1) % 4
            bm.faces.new([bot[k], bot[n], top[n], top[k]])


def box_bm(bm, x0, x1, z0, z1, y0, y1):
    p = [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]
    top = [bm.verts.new((x, z, y1)) for x, z in p]
    bot = [bm.verts.new((x, z, y0)) for x, z in p]
    bm.faces.new(top)
    bm.faces.new(bot[::-1])
    for k in range(4):
        n = (k + 1) % 4
        bm.faces.new([bot[k], bot[n], top[n], top[k]])


def lift_core(ox, label, top_y):
    bm = bmesh.new()
    ring_bm(bm, 0 + ox, -26, 5, 8, 0, top_y, segs=16)
    return obj_from(bm, f"{label}_core", CORE)


# ------------------------------------------------------------------ 1. WAFERS
def wafers(ox):
    objs = []
    for w, st in STOREYS.items():
        cx, cz, r = TIERS[w]
        y0, y1 = FLOOR_Y + st[0] * H, FLOOR_Y + (st[-1] + 1) * H
        bm = bmesh.new()
        ring_bm(bm, cx + ox, cz, r - DEPTH, r, y0, y1)
        objs.append(obj_from(bm, f"waf_{w}", PAPER))
        # every storey edge is a slab band: the horizontal ribbon that stops a
        # glass tower reading as one tall smear
        for s in st:
            bm2 = bmesh.new()
            ring_bm(bm2, cx + ox, cz, r - DEPTH - 0.6, r + 0.6, FLOOR_Y + s * H, FLOOR_Y + s * H + 1.4)
            objs.append(obj_from(bm2, f"waf_{w}_slab{s}", STEEL))
    for w, s in DECK_STOREY.items():
        cx, cz, r = TIERS[w]
        bm = bmesh.new()
        ring_bm(bm, cx + ox, cz, r - DEPTH - 2, r - 2, FLOOR_Y + s * H, FLOOR_Y + s * H + 2.4)
        objs.append(obj_from(bm, f"waf_deck{w}", LAWN))
    cx, cz, r = TIERS[4]
    bm = bmesh.new()
    ring_bm(bm, cx + ox, cz, 0, r - 6, FLOOR_Y + ROOF_STOREY * H, FLOOR_Y + ROOF_STOREY * H + 2.4)
    objs.append(obj_from(bm, "waf_roof", LAWN))
    objs.append(lift_core(ox, "waf", FLOOR_Y + (ROOF_STOREY + 1) * H))
    return objs


# ---------------------------------------------------------------- 2. TERRAFAB
def terrafab(ox):
    """
    Bay and chase, stacked. Each tier is a rectangular doughnut -- the bays --
    around the same courtyard the Wafers ring encloses, so the skeleton is
    untouched. The roof of every tier is a FAN DECK: the grille of plant that
    sits above a real cleanroom and is the reason fabs look like long low
    sheds rather than towers.

    The signature is the overhead wafer track: a loop that rides outside the
    bays and climbs between tiers. It is the only moving thing on the building.
    """
    objs = []
    for w, st in STOREYS.items():
        cx, cz, r = TIERS[w]
        y0, y1 = FLOOR_Y + st[0] * H, FLOOR_Y + (st[-1] + 1) * H
        o, i = r * 0.92, (r - DEPTH) * 1.04
        bm = bmesh.new()
        # four bays make the doughnut
        box_bm(bm, cx + ox - o, cx + ox + o, cz + i, cz + o, y0, y1)
        box_bm(bm, cx + ox - o, cx + ox + o, cz - o, cz - i, y0, y1)
        box_bm(bm, cx + ox - o, cx + ox - i, cz - i, cz + i, y0, y1)
        box_bm(bm, cx + ox + i, cx + ox + o, cz - i, cz + i, y0, y1)
        objs.append(obj_from(bm, f"fab_{w}", PAPER))

        # the fan deck: plant units in rows on top of each tier
        bmd = bmesh.new()
        box_bm(bmd, cx + ox - o, cx + ox + o, cz - o, cz + o, y1, y1 + 1.0)
        objs.append(obj_from(bmd, f"fab_{w}_deck", STEEL))
        bmu = bmesh.new()
        step = 13.0
        n = int((o * 2) // step)
        for a in range(n):
            x0 = cx + ox - o + 3 + a * step
            for zz in (cz + i + 4, cz - o + 5):
                box_bm(bmu, x0, x0 + 7.5, zz, zz + 7.0, y1 + 1.0, y1 + 4.2)
        objs.append(obj_from(bmu, f"fab_{w}_plant", DARK))

        # horizontal louvre banding on the long faces: a fab has no windows to
        # speak of, so the facade is read by its service bands
        bml = bmesh.new()
        for s in st:
            yy = FLOOR_Y + s * H + H * 0.55
            box_bm(bml, cx + ox - o - 0.5, cx + ox + o + 0.5, cz + o - 0.4, cz + o + 0.5, yy, yy + 2.2)
            box_bm(bml, cx + ox - o - 0.5, cx + ox + o + 0.5, cz - o - 0.5, cz - o + 0.4, yy, yy + 2.2)
        objs.append(obj_from(bml, f"fab_{w}_louvre", STEEL))

    # the overhead wafer track: a loop outside the bays, climbing tier to tier
    bmt = bmesh.new()
    for w, st in STOREYS.items():
        cx, cz, r = TIERS[w]
        y = FLOOR_Y + (st[-1] + 1) * H + 5.6
        ring_bm(bmt, cx + ox, cz, r * 0.99, r * 0.99 + 1.6, y, y + 1.2, segs=40)
        # the hangers
        for k in range(16):
            a = k / 16 * math.tau
            x = cx + ox + math.cos(a) * (r * 0.99 + 0.8)
            z = cz + math.sin(a) * (r * 0.99 + 0.8)
            box_bm(bmt, x - 0.5, x + 0.5, z - 0.5, z + 0.5, y - 4.4, y)
    objs.append(obj_from(bmt, "fab_track", WARM))

    for w, s in DECK_STOREY.items():
        cx, cz, r = TIERS[w]
        bm = bmesh.new()
        o, i = r * 0.86, (r - DEPTH) * 1.1
        box_bm(bm, cx + ox - o, cx + ox + o, cz - o, cz + o, FLOOR_Y + s * H, FLOOR_Y + s * H + 1.6)
        objs.append(obj_from(bm, f"fab_deck{w}", STEEL))
    objs.append(lift_core(ox, "fab", FLOOR_Y + (ROOF_STOREY + 1) * H))
    return objs


# -------------------------------------------------------------------- 3. DOME
def dome(ox):
    """
    Bay View's move is that the roof is the building. Each tier gets a shallow
    canopy that tapers toward its own base, carried on slim columns, with a
    CLERESTORY gap between one canopy and the next -- the seam Bay View glazes
    so daylight reaches the middle of a deep floor.

    Stacked, that reads as a layered tent: four overlapping shells, each a bit
    smaller, with a bright glass line at every seam.
    """
    objs = []
    for w, st in STOREYS.items():
        cx, cz, r = TIERS[w]
        y0, y1 = FLOOR_Y + st[0] * H, FLOOR_Y + (st[-1] + 1) * H
        # the floor plate, set well in: the canopy is what you see, not the slab
        bm = bmesh.new()
        ring_bm(bm, cx + ox, cz, r - DEPTH, r * 0.74, y0, y1 - 2.0)
        objs.append(obj_from(bm, f"dom_{w}", GLASS))

        # the canopy: rings of falling radius and rising height = a shallow dome
        bmc = bmesh.new()
        steps = 7
        for k in range(steps):
            t0, t1 = k / steps, (k + 1) / steps
            r0 = r * (1.0 - 0.52 * t0)
            r1 = r * (1.0 - 0.52 * t1)
            h0 = y1 - 2.0 + 7.5 * math.sin(t0 * math.pi * 0.5)
            h1 = y1 - 2.0 + 7.5 * math.sin(t1 * math.pi * 0.5)
            # each scale overlaps the one inside it: the dragonscale read
            ring_bm(bmc, cx + ox, cz, r1, r0 + 0.8, h0, h0 + 0.9, segs=40)
            if k == steps - 1:
                ring_bm(bmc, cx + ox, cz, 0, r1, h1, h1 + 0.9, segs=40)
        objs.append(obj_from(bmc, f"dom_{w}_canopy", SOLAR))

        # slim columns under the canopy edge
        bmp = bmesh.new()
        for k in range(20):
            a = k / 20 * math.tau
            x = cx + ox + math.cos(a) * (r * 0.9)
            z = cz + math.sin(a) * (r * 0.9)
            box_bm(bmp, x - 0.6, x + 0.6, z - 0.6, z + 0.6, y0 + 0.4, y1 - 2.0)
        objs.append(obj_from(bmp, f"dom_{w}_cols", PAPER))

        # the clerestory: the lit seam between this canopy and the tier above
        bmg = bmesh.new()
        ring_bm(bmg, cx + ox, cz, r * 0.70, r * 0.76, y1 - 2.0, y1 + 1.2, segs=40)
        objs.append(obj_from(bmg, f"dom_{w}_clere", K.rgb(255, 242, 206)))

    for w, s in DECK_STOREY.items():
        cx, cz, r = TIERS[w]
        bm = bmesh.new()
        ring_bm(bm, cx + ox, cz, r - DEPTH - 2, r * 0.66, FLOOR_Y + s * H, FLOOR_Y + s * H + 2.0)
        objs.append(obj_from(bm, f"dom_deck{w}", LAWN))
    objs.append(lift_core(ox, "dom", FLOOR_Y + (ROOF_STOREY + 1) * H))
    return objs


PATHS = [("wafers", wafers), ("terrafab", terrafab), ("dome", dome)]


def ground(size=720):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, 0))
    g = bpy.context.object
    K.paint(g, K.flat(K.rgb(206, 200, 186)))
    return g


def main():
    # one each, framed close
    for name, fn in PATHS:
        K.reset()
        objs = fn(0)
        objs.append(ground(420))
        K.preview(os.path.join(OUT, f"concept_{name}.png"), objs,
                  size=(900, 1000), elev=11, azim=24)
        print("wrote concept_" + name)

    # all three together, same camera, so the silhouettes can be compared
    K.reset()
    objs = []
    for i, (name, fn) in enumerate(PATHS):
        objs += fn((i - 1) * 185)
    objs.append(ground(620))
    K.preview(os.path.join(OUT, "concepts_paths.png"), objs,
              size=(1800, 760), elev=10, azim=20)
    print("wrote concepts_paths.png")


if __name__ == "__main__":
    main()
