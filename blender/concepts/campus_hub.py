"""
campus_hub.py -- Option B, iterated against the concept art: the ring campus
with the shop, the car dealership and the apartments worked into it.

What changed from campus_options.py option B:

  - The centre is a PAVED PARK, not a grass bowl. Fountain in the middle,
    concentric paved rings, radial walks, planted beds between them, two
    reflecting pools. It still steps DOWN two courses to the fountain court,
    because a flat disc was the thing to avoid -- but the material is paving,
    which is what the concept art shows and what a civic square actually is.
  - Six tower plots sit at the odd clock positions (30, 90, ... 330), so the
    SIX GAPS between them are free for everything else.
  - Those gaps carry the rest of the game: SHOP, CAR DEALERSHIP, APARTMENTS,
    two parking lots, and the main entrance road. The ring alternates
    tower / civic / tower / civic, so the campus reads as a town rather than
    as six towers and a lawn.
  - Two ring roads: an inner one round the park, an outer one round everything,
    joined by the six radial streets.

Scale is the game's: tower radius 70, so the whole hub is about 1000 studs
across and sits inside the valley with room to spare.

Run:  blender -b --python blender/concepts/campus_hub.py
Out:  blender/out/hub_top.png      the layout
      blender/out/hub_park.png     the park from the ring road
      blender/out/hub_civic.png    the dealership / shop side
      blender/out/hub_sheet.png    all three
"""

import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "concepts"))

import campus_options as CO  # noqa: E402  (box / cyl / tube / wedge / tree / bench / tower)
import svkit as K  # noqa: E402

OUT = os.path.join(HERE, "out")
os.makedirs(OUT, exist_ok=True)

box, cyl, tube, wedge, tree, bench = CO.box, CO.cyl, CO.tube, CO.wedge, CO.tree, CO.bench
LAWN, LAWN_D, CONCRETE, PAPER = CO.LAWN, CO.LAWN_D, CO.CONCRETE, CO.PAPER
ROAD, GLASS, OAK, GOLD, TRUNK, LEAF, VALLEY = CO.ROAD, CO.GLASS, CO.OAK, CO.GOLD, CO.TRUNK, CO.LEAF, CO.VALLEY
INK = CO.INK

PAVE = K.rgb(222, 215, 200)       # the park's paving, lighter than the kerbs
PAVE_D = K.rgb(196, 188, 172)
WATER = K.rgb(96, 164, 196)
BLUE = K.rgb(44, 96, 166)         # dealership brand
ORANGE = K.rgb(232, 138, 54)      # shop brand
ASPHALT = K.rgb(64, 64, 68)

# ---- the ring, in studs -------------------------------------------------
R_COURT = 46.0        # sunken fountain court
R_STEP = 92.0         # outer lip of the steps
R_PARK = 150.0        # the park's kerb
R_ROAD_IN = 196.0     # inner ring road, centre line
R_PLOT = 330.0        # the six tower plots
R_CIVIC = 440.0       # shop / dealership / apartments: OUTSIDE the tower ring,
                      # in the gaps. At the tower radius they were squeezed into
                      # the 200 studs left between two 140-wide towers.
R_ROAD_OUT = 596.0    # outer ring road, centre line (now outside the civic row)
ROAD_W = 26.0

TOWER_A = [math.radians(a) for a in (30, 90, 150, 210, 270, 330)]
GAP_A = {a: math.radians(a) for a in (0, 60, 120, 180, 240, 300)}


def ring_road(r, name="road"):
    tube(name, r + ROAD_W / 2, r - ROAD_W / 2, 1.2, 0, 0, 0.6, ASPHALT)


def radial_road(a, r0, r1, w=ROAD_W):
    half = math.atan2(w / 2, (r0 + r1) / 2)
    wedge("street", r0, r1, a - half, a + half, 1.2, 0.6, ASPHALT)


def car(x, y, a, col):
    o = box("car", 11, 5, 3.4, x, y, 2.3, col)
    o.rotation_euler = (0, 0, a)
    o2 = box("carglass", 5.4, 4.6, 2.0, x, y, 4.6, GLASS)
    o2.rotation_euler = (0, 0, a)


def parking(cx, cy, a, cols=5, rows=3, col_pad=15.0, row_pad=26.0):
    """A lot: asphalt pad, painted bays, and cars nose-in."""
    w, d = cols * col_pad + 10, rows * row_pad + 10
    p = box("lot", w, d, 1.4, cx, cy, 0.7, ASPHALT)
    p.rotation_euler = (0, 0, a)
    ca, sa = math.cos(a), math.sin(a)

    def place(u, v):
        return cx + ca * u - sa * v, cy + sa * u + ca * v

    import random
    rng = random.Random(int(cx * 7 + cy * 13))
    palette = [K.rgb(206, 72, 64), K.rgb(236, 236, 240), K.rgb(44, 58, 86),
               K.rgb(70, 72, 78), K.rgb(222, 176, 72), K.rgb(78, 136, 108)]
    for r in range(rows):
        for c in range(cols):
            u = (c - (cols - 1) / 2) * col_pad
            v = (r - (rows - 1) / 2) * row_pad
            x, y = place(u, v)
            if rng.random() < 0.78:
                car(x, y, a + math.pi / 2, rng.choice(palette))
            lx, ly = place(u - col_pad / 2, v)
            s = box("bay", 0.6, 20, 0.3, lx, ly, 1.5, PAPER)
            s.rotation_euler = (0, 0, a)


def pylon(x, y, a, col, h=26):
    box("pylonpost", 2.2, 2.2, h, x, y, h / 2, PAPER)
    o = box("pylonsign", 16, 1.6, 10, x, y, h + 3, col)
    o.rotation_euler = (0, 0, a)


def showroom(a):
    """Car dealership: a long glass box facing the ring, with its lot in front."""
    ca, sa = math.cos(a), math.sin(a)
    cx, cy = ca * R_CIVIC, sa * R_CIVIC
    yaw = a + math.pi / 2
    o = box("showroom", 150, 66, 30, cx, cy, 15, GLASS)
    o.rotation_euler = (0, 0, yaw)
    o2 = box("showroomroof", 158, 72, 4, cx, cy, 31, PAPER)
    o2.rotation_euler = (0, 0, yaw)
    o3 = box("showroomband", 152, 68, 5, cx, cy, 29, BLUE)
    o3.rotation_euler = (0, 0, yaw)
    # the lot sits between the building and the inner ring road
    px, py = ca * (R_CIVIC - 78), sa * (R_CIVIC - 78)
    parking(px, py, yaw, cols=6, rows=2)
    pylon(ca * (R_CIVIC - 118) - sa * 60, sa * (R_CIVIC - 118) + ca * 60, yaw, BLUE)


def market(a):
    """Shop / retail: a warm box with a deep awning, and its own lot."""
    ca, sa = math.cos(a), math.sin(a)
    cx, cy = ca * R_CIVIC, sa * R_CIVIC
    yaw = a + math.pi / 2
    o = box("market", 140, 62, 26, cx, cy, 13, PAPER)
    o.rotation_euler = (0, 0, yaw)
    o2 = box("marketroof", 148, 68, 4, cx, cy, 27, OAK)
    o2.rotation_euler = (0, 0, yaw)
    # the awning, on the side facing the park
    ax, ay = ca * (R_CIVIC - 40), sa * (R_CIVIC - 40)
    o3 = box("awning", 142, 18, 2.4, ax, ay, 20, ORANGE)
    o3.rotation_euler = (0, 0, yaw)
    for t in (-55, -18, 18, 55):
        bx, by = ca * (R_CIVIC - 46) - sa * t, sa * (R_CIVIC - 46) + ca * t
        box("awningpost", 1.6, 1.6, 19, bx, by, 9.5, PAPER)
    px, py = ca * (R_CIVIC - 76), sa * (R_CIVIC - 76)
    parking(px, py, yaw, cols=6, rows=2)
    pylon(ca * (R_CIVIC - 116) - sa * 58, sa * (R_CIVIC - 116) + ca * 58, yaw, ORANGE)


def residences(a):
    """The apartments: the one SLAB on a ring of round towers, so home is
    legible from anywhere in the hub."""
    ca, sa = math.cos(a), math.sin(a)
    cx, cy = ca * R_CIVIC, sa * R_CIVIC
    yaw = a + math.pi / 2
    box("resbase", 120, 70, 14, cx, cy, 7, CONCRETE).rotation_euler = (0, 0, yaw)
    # A SLAB, not a stack of plates. The first pass drew 11 separate floors each
    # with a band WIDER than the floor itself, so every band became a ledge and
    # the tower read as a venetian blind. Three setbacks, solid glass between,
    # and the bands sit flush.
    SET = [(96, 52, 14, 70), (84, 46, 84, 56), (68, 40, 140, 44)]
    for w, d, z0, h in SET:
        box("resslab", w, d, h, cx, cy, z0 + h / 2, GLASS).rotation_euler = (0, 0, yaw)
        box("rescap", w + 4, d + 4, 3, cx, cy, z0 + h, PAPER).rotation_euler = (0, 0, yaw)
    top = SET[-1][2] + SET[-1][3]
    box("rescrown", 54, 32, 7, cx, cy, top + 5, PAPER).rotation_euler = (0, 0, yaw)
    # a garden terrace on the podium roof, facing the park
    gx, gy = ca * (R_CIVIC - 44), sa * (R_CIVIC - 44)
    box("resterrace", 112, 22, 2, gx, gy, 15, LAWN).rotation_euler = (0, 0, yaw)
    for t in (-40, -14, 14, 40):
        tree(gx - sa * t, gy + ca * t, 0.85)


def park():
    """The centre: paved, formal, and it steps DOWN to a fountain court."""
    # outer planted ring, cut by eight radial walks
    tube("parkkerb", R_PARK, R_PARK - 6, 3.0, 0, 0, 1.5, CONCRETE)
    tube("parklawn", R_PARK - 6, R_STEP, 2.4, 0, 0, 1.2, LAWN)
    for i in range(8):
        a = i * math.pi / 4 + math.pi / 8
        wedge("walk", R_STEP - 2, R_PARK - 4, a - math.radians(4.6), a + math.radians(4.6), 2.8, 1.4, PAVE)
        rr = (R_STEP + R_PARK) / 2
        tree(math.cos(a + math.radians(14)) * rr, math.sin(a + math.radians(14)) * rr, 1.15)
        tree(math.cos(a - math.radians(14)) * rr, math.sin(a - math.radians(14)) * rr, 1.0)
    # two reflecting pools, on the axis the concept art puts them on
    for s in (-1, 1):
        wedge("poolkerb", R_STEP + 10, R_PARK - 16, math.radians(s * 46 - 11), math.radians(s * 46 + 11), 3.2, 1.6, PAVE_D)
        wedge("pool", R_STEP + 15, R_PARK - 21, math.radians(s * 46 - 8.4), math.radians(s * 46 + 8.4), 2.4, 1.8, WATER)

    # the paved ring walk, then two courses stepping down to the court
    tube("ringwalk", R_STEP, R_STEP - 16, 3.0, 0, 0, 1.5, PAVE)
    tube("step1", R_STEP - 16, R_STEP - 30, 5.0, 0, 0, -1.0, PAVE_D)
    tube("step2", R_STEP - 30, R_COURT, 5.0, 0, 0, -5.0, PAVE)
    cyl("court", R_COURT, 3, 0, 0, -9.0, PAVE_D, 48)

    # the fountain: basin, water, and a jet
    cyl("basinrim", 21, 5, 0, 0, -6.0, CONCRETE, 32)
    cyl("basin", 17, 4, 0, 0, -6.2, WATER, 32)
    cyl("jet", 3.2, 16, 0, 0, 0.5, WATER, 16)
    cyl("medallion", 7, 1.4, 0, 0, 1.0, GOLD, 24)

    for i in range(8):
        a = i * math.pi / 4
        bench(math.cos(a) * (R_STEP - 8), math.sin(a) * (R_STEP - 8), a + math.pi / 2)


def build():
    K.reset()
    CO._objs.clear()
    # the valley floor, holed under the sunken court so the paving is real
    tube("ground", 1600, R_COURT, 2, 0, 0, -1, VALLEY)

    park()
    ring_road(R_ROAD_IN)
    ring_road(R_ROAD_OUT)

    for a in TOWER_A:
        CO.tower(math.cos(a) * R_PLOT, math.sin(a) * R_PLOT)
        radial_road(a, R_ROAD_IN, R_ROAD_OUT)

    market(GAP_A[120])
    showroom(GAP_A[180])
    residences(GAP_A[240])

    for a in (GAP_A[60], GAP_A[300]):
        ca, sa = math.cos(a), math.sin(a)
        parking(ca * R_CIVIC, sa * R_CIVIC, a + math.pi / 2, cols=7, rows=3)

    # street trees: without them the ground between the rings reads as desert.
    # Lined along both ring roads and down each radial street, clear of the
    # carriageways.
    for i in range(36):
        a = i * math.pi / 18
        for r, off in ((R_ROAD_IN, -20), (R_ROAD_IN, 20), (R_ROAD_OUT, -20), (R_ROAD_OUT, 20)):
            rr = r + off
            if rr < R_PARK + 6:
                continue
            tree(math.cos(a) * rr, math.sin(a) * rr, 0.9)
    for a in TOWER_A:
        for t in range(4):
            rr = R_ROAD_IN + 40 + t * 70
            for s2 in (-1, 1):
                ang = a + s2 * math.atan2(22, rr)
                tree(math.cos(ang) * rr, math.sin(ang) * rr, 0.85)

    # a paved forecourt in front of each civic building, so they sit on
    # something instead of on bare ground
    for ang in (GAP_A[120], GAP_A[180], GAP_A[240]):
        wedge("forecourt", R_CIVIC - 96, R_CIVIC + 42,
              ang - math.radians(13), ang + math.radians(13), 1.6, 0.8, PAVE_D)

    # the main entrance, in from the east through the free gap
    a = GAP_A[0]
    radial_road(a, R_ROAD_IN, R_ROAD_OUT + 260, w=34)
    for s in (-1, 1):
        box("gatepost", 8, 8, 34, math.cos(a) * (R_ROAD_OUT + 30), math.sin(a) * (R_ROAD_OUT + 30) + s * 30, 17, PAPER)
    box("gatebeam", 8, 72, 7, math.cos(a) * (R_ROAD_OUT + 30), math.sin(a) * (R_ROAD_OUT + 30), 37, GOLD)


def shot(name, **kw):
    K.preview(os.path.join(OUT, name), CO._objs, **kw)
    print("wrote", name)


def main():
    build()
    shot("hub_top.png", size=(1400, 980), elev=52, azim=22, target=Vector((0, 0, 40)), cam_dist=2000)
    # azim = world angle + 90. Gaps are at 0/60/120..., towers at 30/90/150...
    # The first pass used azim 118 (world 28) and put the camera INSIDE the
    # tower at 30 degrees, which rendered as a wall of dark glass.
    shot("hub_park.png", size=(1400, 900), elev=9, azim=90, target=Vector((0, 0, 6)), cam_dist=330)
    # the three civic buildings sit at world 120 / 180 / 240, i.e. the whole
    # west side. azim 270 = world 180, looking straight down that face.
    shot("hub_civic.png", size=(1400, 900), elev=17, azim=270, target=Vector((-300, 0, 40)), cam_dist=1150)
    print("done")


if __name__ == "__main__":
    main()
