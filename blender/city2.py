"""city2.py -- v4.0 DOWNTOWN (27 Sep 2026).

His note: "the city in the back still looks trash." It was eight grey boxes
with glass strips, standing past the valley's walkable edge (x ~786) on the
hillside. This is a real downtown on the flat end of the valley, in the same
architectural language as the HQ (hq2.py): rounded plans, slab edges, ribbon
glass, terraces, planting.

  Residences_Tower   THE RESIDENCES: 18 floors of apartments over a double-height
                     lobby, stacked balconies, curtains in some windows, a crown.
                     The player's apartment is a real floor of this tower.
  Dealer_Showroom    VALLEY MOTORS: a glass showroom under a floating roof with a
                     curved canopy over the entrance, a service block behind.
  Tower_Spire        a slim rounded tower that tapers into an open crown: the
                     landmark at the end of the main road.
  Tower_Stack        five glass boxes, each turned and shifted a little.
  Tower_Stepped      an office tower that steps back twice, gardens on the steps.

Blender +Y = the building's front (Roblox +Z). Game X = -Blender X.
Writes out/IMPORT_CITY/*.fbx and out/city_meta.lua (size + centre).

Run:  blender -b --python city2.py
"""
import bpy
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import svkit as K  # noqa: E402
import hq as H  # noqa: E402
import hq2 as Q  # noqa: E402

OUT = H.OUT
IMP = os.path.join(OUT, "IMPORT_CITY")
os.makedirs(IMP, exist_ok=True)
span, box, rslab, pane, cyl, blob, shade = H.span, H.box, H.rslab, H.pane, H.cyl, H.blob, H.shade
PAPER, PAPER_WARM, CONCRETE, CHARCOAL, METAL = H.PAPER, H.PAPER_WARM, H.CONCRETE, H.CHARCOAL, H.METAL
LEAF, LEAF_DARK, OAK, WHITE, MEMBRANE = H.LEAF, H.LEAF_DARK, H.OAK, H.WHITE, H.MEMBRANE
SPANDREL = Q.SPANDREL
STONE = K.rgb(196, 186, 170)
TERRACOTTA = K.rgb(196, 122, 92)
CURTAIN = [K.rgb(236, 228, 210), K.rgb(214, 204, 186), K.rgb(190, 200, 206)]
roof_shade = Q.roof_shade


def storey_ring(hw, hd, R, s, top, rng=None, curtains=0.0, spandrel=2.4, mull=5.0):
    """One floor on a rounded plan: slab edge band, a spandrel, glass above it."""
    ring = Q.plan(hw, hd, R)
    Q.ring_slab(hw, hd, R, -0.1, 1.0, s - 0.7, s + 0.7, PAPER)
    if spandrel > 0:
        Q.wall(ring, s + 0.7, s + 0.7 + spandrel, 0.6, SPANDREL, out=0.15)
    g0 = s + 0.7 + spandrel
    Q.glass(ring, g0, top, out=-0.35)
    Q.posts(ring, g0, top, mull, out=-0.2)
    if rng and curtains > 0:
        # curtains behind the glass in some bays: a lived-in tower, not a display case
        for a, b, tag in ring:
            if tag in ("F", "S", "B"):
                L = math.hypot(b[0] - a[0], b[1] - a[1])
                n = max(1, int(L / 5))
                nx, ny = Q.outward(a, b)
                for k in range(n):
                    if rng.random() < curtains:
                        f0 = (k + 0.1) / n
                        f1 = f0 + 0.8 / n * rng.uniform(0.5, 1.0)
                        px = a[0] + (b[0] - a[0]) * (f0 + f1) / 2 - nx * 0.9
                        py = a[1] + (b[1] - a[1]) * (f0 + f1) / 2 - ny * 0.9
                        ang = math.atan2(b[1] - a[1], b[0] - a[0])
                        col = CURTAIN[rng.randrange(len(CURTAIN))]
                        box((L * (f1 - f0), 0.15, top - g0 - 0.4), (px, py, (g0 + top) / 2), col, rot=(0, 0, ang),
                            fn=K.flat(col))


def floor_plate(hw, hd, R, s):
    rslab(hw * 2 - 0.2, hd * 2 - 0.2, 1.2, (0, 0, s), Q.FLOORPLATE, radius=R - 0.1, bev=0.0, fn=K.flat(Q.FLOORPLATE))


def balcony(x0, x1, y_face, s, depth, sign=1):
    """A balcony slab off a front/back face with a glass rail and a white cap."""
    yo = y_face + sign * depth
    rslab(x1 - x0, depth + 1.2, 0.8, ((x0 + x1) / 2, y_face + sign * (depth / 2 - 0.4), s + 0.3), PAPER, radius=1.2, bev=0.1)
    pane(x0 + 0.3, x1 - 0.3, yo - 0.1 * sign - 0.1, yo - 0.1 * sign + 0.1, s + 0.7, s + 3.4)
    span(x0 + 0.2, x1 - 0.2, yo - 0.25 * sign - 0.15, yo - 0.25 * sign + 0.15, s + 3.4, s + 3.6, PAPER)
    for xx in (x0 + 0.3, x1 - 0.3):
        lo, hi = sorted((y_face, yo))
        pane(xx - 0.1, xx + 0.1, lo, hi, s + 0.7, s + 3.4)


def plinth(w, d, R, h=1.4):
    rslab(w + 5, d + 5, h + 3, (0, 0, h / 2 - 1.5), STONE, radius=R + 2.5, bev=0.15)


# ------------------------------------------------------------------ THE RESIDENCES
RES = dict(w=50, d=40, R=7, lobby=14, floor=10, floors=18)


def residences():
    w, d, R = RES["w"], RES["d"], RES["R"]
    hw, hd = w / 2, d / 2
    rng = random.Random(11)
    H.CTX["under"] = []
    plinth(w, d, R)
    lobby = RES["lobby"]
    ring = Q.plan(hw, hd, R)
    gap = 7.0
    front = Q.clip_door(ring, gap)
    for run in Q.chain_split(front):
        Q.glass(run, 1.4, lobby - 0.7, out=-0.3)
        Q.posts(run, 1.4, lobby - 0.7, 4.2, out=-0.15)
        Q.wall(run, 10.2, 10.5, 0.4, CHARCOAL, out=0.1)
    for sx in (-1, 1):
        span(sx * 6.2, sx * 7.4, hd - 0.6, hd + 0.6, 0.0, lobby - 0.7, STONE, bev=0.1)
    span(-6.2, 6.2, hd - 0.4, hd + 0.4, 10.2, lobby - 0.7, STONE)
    # the entrance canopy: a deep rounded slab on two slim columns, sign board on its lip
    rslab(22, 9, 0.8, (0, hd + 4.2, 10.6), PAPER, radius=2.6, bev=0.12, fn=roof_shade(MEMBRANE, PAPER))
    span(-9, 9, hd + 8.6, hd + 8.9, 9.6, 11.4, CHARCOAL)          # sign board (the game paints the name)
    for sx in (-1, 1):
        cyl(0.3, 0.0, 10.2, sx * 8.5, hd + 7.6, PAPER)
    # planters either side of the door
    for sx in (-1, 1):
        span(sx * 11 - 3, sx * 11 + 3, hd + 1.5, hd + 3.5, 0.0, 1.4, STONE, bev=0.1)
        for k in range(4):
            blob(0.8, (sx * 11 - 2.2 + k * 1.5, hd + 2.5, 1.9), [LEAF, LEAF_DARK][k % 2])
    # floors
    fl = RES["floor"]
    for n in range(RES["floors"]):
        s = lobby + n * fl
        top = s + fl - 0.7
        floor_plate(hw, hd, R, s)
        storey_ring(hw, hd, R, s, top, rng, curtains=0.35, spandrel=1.0, mull=4.6)
        # stacked balconies: front and back, alternating halves; wrapped on the top six
        if n >= 12:
            for sy in (-1, 1):
                balcony(-hw + R, hw - R, sy * hd, s, 3.2, sy)
        else:
            left = (n % 2 == 0)
            x0, x1 = (-hw + R, -2.0) if left else (2.0, hw - R)
            balcony(x0, x1, hd, s, 3.0, 1)
            x0, x1 = (2.0, hw - R) if left else (-hw + R, -2.0)
            balcony(x0, x1, -hd, s, 3.0, -1)
    roof = lobby + RES["floors"] * fl
    floor_plate(hw, hd, R, roof)
    Q.ring_slab(hw, hd, R, -0.1, 1.4, roof - 0.7, roof + 1.2, PAPER)
    # the crown: an open white frame over a rooftop pavilion
    rslab(w * 0.5, d * 0.5, 7, (0, 0, roof + 4.2), PAPER_WARM, radius=3, bev=0.15)
    Q.glass(Q.plan(w * 0.25 + 0.1, d * 0.25 + 0.1, 3.1), roof + 1.5, roof + 6.8)
    for sx in (-1, 1):
        for sy in (-1, 1):
            span(sx * (hw - 3) - 0.7, sx * (hw - 3) + 0.7, sy * (hd - 3) - 0.7, sy * (hd - 3) + 0.7, roof + 1, roof + 16, PAPER, bev=0.1)
    Q.ring_slab(hw - 3, hd - 3, R - 2, -1.4, 0.7, roof + 15, roof + 17, PAPER)


# ------------------------------------------------------------------ VALLEY MOTORS
def dealer():
    w, d, R, h = 72, 44, 10, 16
    hw, hd = w / 2, d / 2
    H.CTX["under"] = [h - 0.9]
    plinth(w, d, R, 1.0)
    ring = Q.plan(hw, hd, R)
    # the showroom: glass on the front two-thirds, the service block solid behind
    show = [sg for sg in ring if sg[2] in ("F", "CF")] + [sg for sg in ring if sg[2] == "S"]
    front = Q.clip_door(Q.pick(ring, ("F", "CF", "S")), 6.5)
    for run in Q.chain_split(front):
        Q.glass(run, 1.2, h - 1.4, out=-0.3)
        Q.posts(run, 1.2, h - 1.4, 6.0, out=-0.15)
    Q.wall(Q.pick(ring, ("B", "CB")), 0.0, h - 1.4, 0.8, PAPER_WARM)
    # the service block (back third): a solid volume with two roll doors on the left side
    span(-hw + 1, hw - 1, -hd + 1, -hd + 14, 0.0, h - 1.4, PAPER_WARM)
    for k in range(2):
        yy = -hd + 3.5 + k * 6
        span(-hw - 0.05, -hw + 0.4, yy - 2.4, yy + 2.4, 0.2, 7.5, METAL)
        for z in range(1, 8):
            span(-hw - 0.12, -hw + 0.4, yy - 2.4, yy + 2.4, z - 0.04, z + 0.04, CHARCOAL)
    # the floating roof, deeper over the front, and a curved canopy over the drive
    rslab(w + 8, d + 8, 1.4, (0, 1.0, h + 0.1), PAPER, radius=R + 4, bev=0.2, fn=roof_shade(MEMBRANE, PAPER))
    Q.ring_slab(hw + 3.5, hd + 4.5, R + 3.5, -1.2, 0.3, h - 0.9, h - 0.5, CHARCOAL)
    rslab(26, 14, 1.0, (0, hd + 9, h - 1.6), PAPER, radius=6, bev=0.15, fn=roof_shade(MEMBRANE, PAPER))
    for sx in (-1, 1):
        cyl(0.45, 0.0, h - 2.1, sx * 10, hd + 13.5, PAPER, verts=16)
    # the sign band on the roof's front edge (the game paints the name)
    span(-16, 16, hd + 4.9, hd + 5.2, h + 0.9, h + 3.6, CHARCOAL)
    # roof plant and a rooftop logo frame
    for x in (-18, 0, 18):
        span(x - 2.5, x + 2.5, -hd + 3, -hd + 7, h + 0.8, h + 2.8, METAL, bev=0.2)


# ------------------------------------------------------------------ THE TOWERS
def tower_spire():
    rng = random.Random(21)
    H.CTX["under"] = []
    w0, R0 = 34.0, 12.0
    plinth(w0, w0, R0)
    fl = 7.0
    n_floors = 24
    z = 1.0
    Q.glass(Q.plan(w0 / 2, w0 / 2, R0), 1.4, 13.3, out=-0.3)
    Q.posts(Q.plan(w0 / 2, w0 / 2, R0), 1.4, 13.3, 4.0, out=-0.15)
    z = 14.0
    for n in range(n_floors):
        t = max(0.0, (n - 14) / (n_floors - 14))            # taper above floor 14
        half = w0 / 2 * (1.0 - 0.28 * t)
        R = R0 * (1.0 - 0.28 * t)
        floor_plate(half, half, R, z)
        storey_ring(half, half, R, z, z + fl - 0.7, rng, curtains=0.0, spandrel=1.2, mull=3.6)
        z += fl
    half = w0 / 2 * 0.72
    floor_plate(half, half, R0 * 0.72, z)
    Q.ring_slab(half, half, R0 * 0.72, -0.1, 0.9, z - 0.7, z + 1.0, PAPER)
    # the open crown: four tall blades leaning in, tied by two rings
    for k in range(4):
        a = math.radians(45 + 90 * k)
        x, y = math.cos(a) * half * 0.9, math.sin(a) * half * 0.9
        box((1.4, 1.4, 30), (x * 0.8, y * 0.8, z + 15), PAPER, rot=(-math.sin(a) * 0.12, math.cos(a) * 0.12, a))
    for zz, sc in ((z + 12, 0.78), (z + 24, 0.55)):
        Q.ring_slab(half * sc, half * sc, R0 * 0.72 * sc, -0.8, 0.0, zz, zz + 1.0, PAPER)
    cyl(0.35, z + 24, z + 42, 0, 0, PAPER, verts=10)


def tower_stack():
    rng = random.Random(31)
    H.CTX["under"] = []
    w, d, R = 36.0, 28.0, 4.0
    plinth(w, d, R)
    z = 1.0
    shifts = [(0, 0, 0), (3, -2, 8), (-2, 3, -6), (2, 1, 10), (-3, -2, -4), (1, 2, 6)]
    for i, (sx, sy, rot) in enumerate(shifts):
        hbox = 22 if i else 24
        objs_before = len(H.PARTS["shell"]), len(H.PARTS["glass"])
        floors = [z + k * 7 for k in range(int(hbox / 7))]
        for s in floors:
            floor_plate(w / 2, d / 2, R, s)
            storey_ring(w / 2, d / 2, R, s, min(s + 6.3, z + hbox - 1.0), rng, curtains=0.0, spandrel=0.8, mull=4.0)
        # a thick white frame at the box's top: the stack reads as separate boxes
        Q.ring_slab(w / 2, d / 2, R, -1.0, 1.2, z + hbox - 1.2, z + hbox + 0.4, PAPER)
        rslab(w, d, 1.0, (0, 0, z + hbox - 0.4), PAPER, radius=R, bev=0.0)
        # move + turn this box's parts
        new_shell = H.PARTS["shell"][objs_before[0]:]
        new_glass = H.PARTS["glass"][objs_before[1]:]
        for o in new_shell + new_glass:
            o.rotation_euler = (0, 0, math.radians(rot))
            o.location = (o.location[0] + sx, o.location[1] + sy, o.location[2])
            bpy.context.view_layer.objects.active = o
            for s2 in bpy.context.selected_objects:
                s2.select_set(False)
            o.select_set(True)
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=False)
            o.select_set(False)
        z += hbox + 0.4
    # a roof garden on the top box
    for k in range(5):
        blob(1.2, (-12 + k * 6, 0, z + 1.2), [LEAF, LEAF_DARK][k % 2])


def tower_stepped():
    rng = random.Random(41)
    H.CTX["under"] = []
    tiers = [(46, 36, 6, 1.0, 31.0), (36, 28, 5, 31.0, 101.0), (28, 20, 4, 101.0, 143.0)]
    plinth(46, 36, 6)
    for i, (w, d, R, z0, z1) in enumerate(tiers):
        hw, hd = w / 2, d / 2
        s = z0
        while s + 7 <= z1 + 0.1:
            floor_plate(hw, hd, R, s)
            storey_ring(hw, hd, R, s, s + 6.3, rng, curtains=0.0, spandrel=2.0, mull=4.4)
            s += 7
        # the setback terrace: a planted roof with a glass rail
        floor_plate(hw, hd, R, z1)
        Q.ring_slab(hw, hd, R, -0.1, 1.0, z1 - 0.7, z1 + 0.9, PAPER)
        if i < len(tiers) - 1:
            nw, nd = tiers[i + 1][0], tiers[i + 1][1]
            for sx in (-1, 1):
                x0 = sx * (nw / 2 + 1.5)
                span(min(x0, sx * (hw - 2)), max(x0, sx * (hw - 2)), -hd + 2, hd - 2, z1 + 0.6, z1 + 1.4, CONCRETE)
                for k in range(4):
                    blob(1.0, (sx * ((nw / 2 + hw) / 2), -hd + 5 + k * ((d - 10) / 3), z1 + 2.0), [LEAF, LEAF_DARK][k % 2])
            Q.glass(Q.plan(hw + 0.6, hd + 0.6, R + 0.6), z1 + 0.9, z1 + 3.4)
        else:
            for x in (-6, 6):
                span(x - 2.5, x + 2.5, -3, 3, z1 + 0.9, z1 + 3.2, METAL, bev=0.2)
            cyl(0.3, z1 + 0.9, z1 + 22, 0, 4, PAPER, verts=8)


BUILD = {
    "Residences_Tower": residences,
    "Dealer_Showroom": dealer,
    "Tower_Spire": tower_spire,
    "Tower_Stack": tower_stack,
    "Tower_Stepped": tower_stepped,
}


def run(name):
    K.reset()
    H.PARTS["shell"], H.PARTS["glass"] = [], []
    BUILD[name]()
    shell = H.finish_mesh(name, "shell")
    glass = H.finish_mesh(name + "_Glass", "glass")
    objs = [o for o in (shell, glass) if o]
    K.preview(os.path.join(OUT, "city_%s.png" % name), objs=objs, size=(700, 900), elev=12, azim=200)
    K.export(os.path.join(IMP, name + ".fbx"), [shell])
    if glass:
        K.export(os.path.join(IMP, name + "_Glass.fbx"), [glass])


if __name__ == "__main__":
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(BUILD)
    for n in only:
        run(n)
    NL = chr(10)
    with open(os.path.join(OUT, "city_meta.lua"), "w") as f:
        f.write("-- generated by blender/city2.py: bbox centre (relative to the building origin) and size" + NL)
        for k in sorted(H.META):
            m = H.META[k]
            f.write(("\t%s = { c = Vector3.new(%.3f, %.3f, %.3f), s = Vector3.new(%.3f, %.3f, %.3f) },  -- %d tris" + NL)
                    % (k, m["c"][0], m["c"][1], m["c"][2], m["s"][0], m["s"][1], m["s"][2], m["tris"]))
    print("CITY META", H.META)
