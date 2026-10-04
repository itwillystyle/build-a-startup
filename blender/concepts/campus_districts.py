"""
campus_districts.py -- the hub with every gap turned into a destination.

The note that drove this: the previous version was tower / grass / tower /
grass, which reads as a diagram rather than a place. Six towers is a game rule
(plotX, the blueprint caps and spin-off all assume six plots), so the density
has to come from the SIX GAPS between them, not from more towers.

Each gap is a district. The three that already have a mechanic behind them get
the best positions -- the ones a player walks to on purpose:

  E   ARRIVAL     the gate, bus stop, taxi lane, arrival pavilion
  NE  PARKING     staff lot, EV chargers, planted islands
  NW  RETAIL      grocery, cafes, food court, outdoor dining
  W   DEALERSHIP  glass showroom, service bays, test-drive loop
  SW  APARTMENTS  curved 7-storey block, pool deck, courtyard
  SE  EVENT LAWN  stage, expo tents, food trucks

THE APARTMENTS ARE DELIBERATELY LOW. In the last pass they were a 180-stud
slab, which made them read as a seventh tower and broke the rule that the six
plots are the player's. Seven storeys, curved on the ring, about a third of a
tower's height: clearly a different KIND of building.

The park is a three-tier sunken plaza now, not a lawn with a fountain in it:
outer tree walk, reflecting pools, lawn ring, then steps down to an
amphitheatre and an interactive fountain under a monument.

Run:  blender -b --python blender/concepts/campus_districts.py
Out:  blender/out/dist_top.png, dist_park.png, dist_retail.png, dist_sheet.png
"""

import math
import os
import random
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "concepts"))

import campus_options as CO  # noqa: E402
import svkit as K  # noqa: E402

OUT = os.path.join(HERE, "out")
os.makedirs(OUT, exist_ok=True)

box, cyl, tube, wedge, tree, bench = CO.box, CO.cyl, CO.tube, CO.wedge, CO.tree, CO.bench
LAWN, LAWN_D, CONCRETE, PAPER = CO.LAWN, CO.LAWN_D, CO.CONCRETE, CO.PAPER
ROAD, GLASS, OAK, GOLD, TRUNK, LEAF, VALLEY = CO.ROAD, CO.GLASS, CO.OAK, CO.GOLD, CO.TRUNK, CO.LEAF, CO.VALLEY

PAVE = K.rgb(222, 215, 200)
PAVE_D = K.rgb(196, 188, 172)
PAVE_W = K.rgb(236, 231, 220)
WATER = K.rgb(96, 164, 196)
BLUE = K.rgb(44, 96, 166)
ORANGE = K.rgb(232, 138, 54)
RED = K.rgb(198, 72, 62)
TEAL = K.rgb(70, 160, 150)
ASPHALT = K.rgb(64, 64, 68)
BRICK = K.rgb(170, 104, 78)

R_COURT = 40.0
R_STEP = 96.0
R_PARK = 162.0
R_ROAD_IN = 208.0
R_PLOT = 336.0
R_DIST = 452.0          # the district band, outside the tower ring
R_ROAD_OUT = 596.0
ROAD_W = 26.0

TOWER_A = [math.radians(a) for a in (30, 90, 150, 210, 270, 330)]
GAP = {a: math.radians(a) for a in (0, 60, 120, 180, 240, 300)}

rng = random.Random(7)


# ---------------------------------------------------------------- small stuff
def at(a, r, t=0.0):
    """World xy at angle `a`, radius `r`, offset `t` along the tangent."""
    ca, sa = math.cos(a), math.sin(a)
    return ca * r - sa * t, sa * r + ca * t


def person(x, y, col=None):
    c = col or rng.choice([K.rgb(214, 96, 86), K.rgb(60, 92, 150), K.rgb(236, 206, 128),
                           K.rgb(96, 150, 120), K.rgb(228, 228, 232), K.rgb(120, 96, 160)])
    cyl("personbody", 1.1, 4.2, x, y, 2.1, c, 8)
    cyl("personhead", 0.85, 1.6, x, y, 5.0, K.rgb(226, 190, 160), 8)


def crowd(cx, cy, n, spread):
    for _ in range(n):
        person(cx + rng.uniform(-spread, spread), cy + rng.uniform(-spread, spread))


def planter(x, y, a, w=14, d=5):
    o = box("planter", w, d, 3.0, x, y, 1.5, CONCRETE)
    o.rotation_euler = (0, 0, a)
    o2 = box("planterfill", w - 2, d - 2, 1.2, x, y, 3.2, LAWN)
    o2.rotation_euler = (0, 0, a)


def lamp(x, y):
    cyl("lamppost", 0.7, 20, x, y, 10, PAPER, 6)
    cyl("lamphead", 2.0, 1.2, x, y, 20.4, GOLD, 8)


def parasol(x, y, col):
    cyl("parasolpost", 0.5, 9, x, y, 4.5, PAPER, 6)
    cyl("parasoltop", 7.0, 1.0, x, y, 9.4, col, 8)


def car(x, y, a, col=None):
    c = col or rng.choice([K.rgb(206, 72, 64), K.rgb(236, 236, 240), K.rgb(44, 58, 86),
                           K.rgb(70, 72, 78), K.rgb(222, 176, 72), K.rgb(78, 136, 108)])
    o = box("car", 11, 5, 3.2, x, y, 2.2, c)
    o.rotation_euler = (0, 0, a)
    o2 = box("carglass", 5.2, 4.4, 1.9, x, y, 4.4, GLASS)
    o2.rotation_euler = (0, 0, a)


def bus(x, y, a, col=TEAL):
    o = box("bus", 30, 9, 10, x, y, 5, col)
    o.rotation_euler = (0, 0, a)
    o2 = box("busglass", 26, 9.4, 3.4, x, y, 8, GLASS)
    o2.rotation_euler = (0, 0, a)


def lot(a, t, rows, cols, rr):
    """A parking block in the district band."""
    cx, cy = at(a, rr, t)
    yaw = a + math.pi / 2
    o = box("lot", cols * 15 + 8, rows * 26 + 8, 1.4, cx, cy, 0.7, ASPHALT)
    o.rotation_euler = (0, 0, yaw)
    for r in range(rows):
        for c in range(cols):
            u = (c - (cols - 1) / 2) * 15
            v = (r - (rows - 1) / 2) * 26
            x, y = at(a, rr + v, t + u)
            if rng.random() < 0.8:
                car(x, y, yaw + math.pi / 2)


# ---------------------------------------------------------------- the park
def park():
    """Three tiers down to an amphitheatre, not a lawn with a fountain in it."""
    tube("parkkerb", R_PARK, R_PARK - 7, 3.4, 0, 0, 1.7, CONCRETE)
    # outer tree walk
    tube("treewalk", R_PARK - 7, R_PARK - 34, 2.6, 0, 0, 1.3, PAVE)
    for i in range(30):
        a = i * math.pi / 15
        tree(*at(a, R_PARK - 20), 1.2)
    # reflecting pools on the four diagonals
    for i in range(4):
        a = math.pi / 4 + i * math.pi / 2
        wedge("poolkerb", R_PARK - 36, R_STEP + 16, a - math.radians(15), a + math.radians(15), 3.0, 1.5, PAVE_D)
        wedge("pool", R_PARK - 40, R_STEP + 20, a - math.radians(12), a + math.radians(12), 2.2, 1.9, WATER)
    # lawn ring, cut by eight walks
    tube("lawnring", R_PARK - 36, R_STEP, 2.4, 0, 0, 1.2, LAWN)
    for i in range(8):
        a = i * math.pi / 4
        wedge("walk", R_STEP - 2, R_PARK - 34, a - math.radians(4), a + math.radians(4), 2.8, 1.4, PAVE_W)
    # three tiers down
    tube("tier1", R_STEP, R_STEP - 20, 5.0, 0, 0, -1.0, PAVE)
    tube("tier2", R_STEP - 20, R_STEP - 38, 5.0, 0, 0, -5.5, PAVE_D)
    tube("tier3", R_STEP - 38, R_COURT, 5.0, 0, 0, -10.0, PAVE)
    cyl("court", R_COURT, 3, 0, 0, -14.0, PAVE_W, 48)
    # seating on the tiers: an amphitheatre is where people SIT
    for ring, rr, z in ((14, R_STEP - 8, 0.8), (12, R_STEP - 28, -3.6)):
        for i in range(ring):
            a = i * 2 * math.pi / ring + 0.12
            x, y = at(a, rr)
            bench(x, y, a + math.pi / 2)
            if rng.random() < 0.5:
                person(*at(a, rr - 4))
    # the interactive fountain, and the monument over it
    cyl("basinrim", 20, 5, 0, 0, -11.5, CONCRETE, 32)
    cyl("basin", 16, 4, 0, 0, -11.8, WATER, 32)
    for i in range(8):
        a = i * math.pi / 4
        cyl("jet", 0.9, rng.uniform(8, 16), *at(a, 10), 0, K.rgb(180, 220, 240), 6)
    cyl("monubase", 7.5, 6, 0, 0, -8.5, PAVE_D, 16)
    cyl("monument", 3.0, 30, 0, 0, 9.0, PAPER, 12)
    cyl("monucap", 5.0, 3.0, 0, 0, 25.0, GOLD, 12)
    crowd(0, 0, 10, 30)


# ---------------------------------------------------------------- districts
def arrival(a):
    """E -- the gate, the bus stop, the taxi lane, a pavilion to stand under."""
    wedge("plaza", R_DIST - 90, R_DIST + 60, a - math.radians(15), a + math.radians(15), 1.8, 0.9, PAVE)
    for s in (-1, 1):
        box("gatepost", 9, 9, 40, *at(a, R_ROAD_OUT - 24, s * 34), 20, PAPER)
    box("gatebeam", 9, 80, 8, *at(a, R_ROAD_OUT - 24), 42, GOLD)
    # pavilion: a roof on columns, the cheapest thing that makes a place
    px, py = at(a, R_DIST - 10)
    box("pavroof", 70, 34, 3.4, px, py, 24, PAPER).rotation_euler = (0, 0, a + math.pi / 2)
    for u in (-30, -10, 10, 30):
        for v in (-14, 14):
            cyl("pavcol", 1.3, 24, *at(a, R_DIST - 10 + v, u), 12, PAPER, 8)
    bus(*at(a, R_DIST + 34, -40), a)
    for t in (-18, 0, 18):
        car(*at(a, R_DIST + 34, t + 30), a)
    crowd(px, py, 9, 24)
    for t in (-54, 54):
        lamp(*at(a, R_DIST + 4, t))


def parking(a):
    """NE -- staff parking, EV chargers, planted islands so it is not a sea of tar."""
    wedge("lotpad", R_DIST - 86, R_DIST + 56, a - math.radians(15), a + math.radians(15), 1.5, 0.75, ASPHALT)
    for row, rr in enumerate((R_DIST - 60, R_DIST - 16, R_DIST + 28)):
        for c in range(9):
            t = (c - 4) * 15
            if rng.random() < 0.82:
                car(*at(a, rr, t), a + math.pi / 2)
        planter(*at(a, rr + 17, 0), a + math.pi / 2, w=130, d=7)
    for t in (-62, -30, 30, 62):
        cyl("charger", 1.0, 9, *at(a, R_DIST - 78, t), 4.5, TEAL, 8)
    for t in (-70, 0, 70):
        lamp(*at(a, R_DIST + 50, t))


def retail(a):
    """NW -- grocery, cafes, a food court, and dining out on the paving."""
    wedge("plaza", R_DIST - 96, R_DIST + 20, a - math.radians(16), a + math.radians(16), 1.8, 0.9, PAVE_W)
    yaw = a + math.pi / 2
    # the grocery anchor, then a row of smaller units beside it
    gx, gy = at(a, R_DIST + 44, -46)
    box("grocery", 104, 56, 26, gx, gy, 13, PAPER).rotation_euler = (0, 0, yaw)
    box("groceryband", 108, 60, 5, gx, gy, 25, ORANGE).rotation_euler = (0, 0, yaw)
    for i, (w, col) in enumerate(((44, BRICK), (44, PAPER), (44, TEAL))):
        ux, uy = at(a, R_DIST + 40, 36 + i * 48)
        box("unit", w, 46, 20, ux, uy, 10, col).rotation_euler = (0, 0, yaw)
        box("unitroof", w + 4, 50, 3, ux, uy, 20.5, PAVE_D).rotation_euler = (0, 0, yaw)
        box("awning", w - 6, 12, 1.8, *at(a, R_DIST + 14, 36 + i * 48), 13, ORANGE).rotation_euler = (0, 0, yaw)
    # outdoor dining on the plaza: parasols, tables, people
    for i in range(10):
        t = -70 + i * 15
        rr = R_DIST - 30 + (i % 3) * 16
        parasol(*at(a, rr, t), rng.choice([ORANGE, RED, TEAL, PAPER]))
        cyl("table", 2.6, 1.0, *at(a, rr, t), 3.0, PAPER, 10)
    crowd(*at(a, R_DIST - 40), 16, 44)
    for t in (-86, -40, 40, 86):
        tree(*at(a, R_DIST - 86, t), 1.1)
        lamp(*at(a, R_DIST - 62, t))


def dealership(a):
    """W -- glass showroom, service bays behind, and a test-drive loop."""
    yaw = a + math.pi / 2
    wedge("forecourt", R_DIST - 96, R_DIST + 10, a - math.radians(15), a + math.radians(15), 1.6, 0.8, PAVE_D)
    sx, sy = at(a, R_DIST + 44)
    box("showroom", 128, 60, 32, sx, sy, 16, GLASS).rotation_euler = (0, 0, yaw)
    box("showroomroof", 136, 66, 4, sx, sy, 33, PAPER).rotation_euler = (0, 0, yaw)
    box("showroomband", 130, 62, 5, sx, sy, 30, BLUE).rotation_euler = (0, 0, yaw)
    # service bays behind, with roller doors
    bx, by = at(a, R_DIST + 92)
    box("service", 112, 40, 22, bx, by, 11, PAVE_D).rotation_euler = (0, 0, yaw)
    for t in (-36, -12, 12, 36):
        box("rollerdoor", 18, 1.2, 15, *at(a, R_DIST + 72, t), 7.5, ANOD_OR_BLUE()).rotation_euler = (0, 0, yaw)
    # stock out front, angled, the way a forecourt actually looks
    for i in range(10):
        t = -72 + i * 16
        car(*at(a, R_DIST - 4, t), yaw + math.radians(28))
    for i in range(6):
        t = -46 + i * 18
        car(*at(a, R_DIST - 34, t), yaw + math.radians(28))
    # the test-drive loop: a ribbon of road inside the district
    tube("testloop", 86, 70, 1.2, *at(a, R_DIST - 66), 0.6, ASPHALT)
    box("pylonpost", 2.4, 2.4, 30, *at(a, R_DIST - 96, 70), 15, PAPER)
    box("pylonsign", 18, 1.8, 11, *at(a, R_DIST - 96, 70), 33, BLUE).rotation_euler = (0, 0, yaw)
    crowd(*at(a, R_DIST - 20), 7, 30)


def ANOD_OR_BLUE():
    return K.rgb(96, 102, 110)


def apartments(a):
    """SW -- curved, SEVEN storeys, pool deck and courtyard.

    Low on purpose. At 180 studs it read as a seventh tower and the six plots
    are supposed to be the only towers a player owns. At a third of that height
    and curved along the ring it reads as somewhere people LIVE."""
    FL, FH = 7, 11.0
    half = math.radians(13)
    for i in range(FL):
        z = 4 + i * FH
        inset = (i // 3) * 7
        wedge("apt", R_DIST - 26 + inset, R_DIST + 26 - inset, a - half, a + half, FH - 2.6, z, GLASS)
        wedge("aptband", R_DIST - 28 + inset, R_DIST + 28 - inset, a - half, a + half, 2.6, z + FH - 2.6,
              PAPER if i % 2 == 0 else PAVE_D)
    wedge("aptbase", R_DIST - 34, R_DIST + 34, a - half - math.radians(2), a + half + math.radians(2), 4.0, 0.0, CONCRETE)
    # the courtyard side: pool deck, loungers, planting, a cafe box
    wedge("deck", R_DIST - 86, R_DIST - 36, a - math.radians(12), a + math.radians(12), 2.0, 1.0, PAVE_W)
    wedge("pool", R_DIST - 76, R_DIST - 50, a - math.radians(7), a + math.radians(7), 1.6, 1.6, WATER)
    for t in (-44, -28, 28, 44):
        box("lounger", 7, 2.6, 1.4, *at(a, R_DIST - 62, t), 2.4, PAPER)
        parasol(*at(a, R_DIST - 62, t * 1.18), TEAL)
    cx, cy = at(a, R_DIST - 96, -56)
    box("aptcafe", 36, 24, 14, cx, cy, 7, BRICK).rotation_euler = (0, 0, a + math.pi / 2)
    box("aptcafeawn", 38, 10, 1.6, *at(a, R_DIST - 110, -56), 11, ORANGE).rotation_euler = (0, 0, a + math.pi / 2)
    for t in (-80, -20, 20, 80):
        tree(*at(a, R_DIST - 100, t), 1.1)
    crowd(*at(a, R_DIST - 66), 9, 34)


def event_lawn(a):
    """SE -- stage, expo tents, food trucks. The flexible one."""
    wedge("lawn", R_DIST - 96, R_DIST + 46, a - math.radians(15), a + math.radians(15), 2.0, 1.0, LAWN)
    yaw = a + math.pi / 2
    sx, sy = at(a, R_DIST + 44)
    box("stagedeck", 72, 30, 5, sx, sy, 2.5, OAK).rotation_euler = (0, 0, yaw)
    box("stageback", 74, 3, 26, *at(a, R_DIST + 58), 16, PAVE_D).rotation_euler = (0, 0, yaw)
    box("stageroof", 78, 34, 3, sx, sy, 28, PAPER).rotation_euler = (0, 0, yaw)
    for t in (-36, 36):
        cyl("stagecol", 1.4, 26, *at(a, R_DIST + 44, t), 13, PAPER, 8)
    # expo tents, a row of them, alternating colours
    for i in range(5):
        t = -64 + i * 32
        tx, ty = at(a, R_DIST - 18, t)
        col = (TEAL, ORANGE, PAPER, RED, BLUE)[i]
        box("tentroof", 26, 26, 2.0, tx, ty, 13, col).rotation_euler = (0, 0, yaw)
        for u in (-11, 11):
            for v in (-11, 11):
                cyl("tentleg", 0.6, 13, *at(a, R_DIST - 18 + v, t + u), 6.5, PAPER, 6)
    # food trucks along the back
    for i, col in enumerate((RED, TEAL, ORANGE)):
        box("truck", 22, 9, 11, *at(a, R_DIST - 74, -40 + i * 40), 5.5, col).rotation_euler = (0, 0, yaw)
    crowd(*at(a, R_DIST - 30), 22, 60)
    for t in (-88, 88):
        for rr in (R_DIST - 80, R_DIST + 10):
            tree(*at(a, rr, t), 1.1)


# ---------------------------------------------------------------- the world
def build():
    K.reset()
    CO._objs.clear()
    tube("ground", 1700, R_COURT, 2, 0, 0, -1, VALLEY)

    park()
    tube("roadin", R_ROAD_IN + ROAD_W / 2, R_ROAD_IN - ROAD_W / 2, 1.2, 0, 0, 0.6, ASPHALT)
    tube("roadout", R_ROAD_OUT + ROAD_W / 2, R_ROAD_OUT - ROAD_W / 2, 1.2, 0, 0, 0.6, ASPHALT)

    for a in TOWER_A:
        CO.tower(*at(a, R_PLOT))
        half = math.atan2(ROAD_W / 2, (R_ROAD_IN + R_ROAD_OUT) / 2)
        wedge("street", R_ROAD_IN, R_ROAD_OUT, a - half, a + half, 1.2, 0.6, ASPHALT)
        # a paved approach and a few people at every tower door
        wedge("approach", R_ROAD_IN, R_PLOT - 66, a - math.radians(7), a + math.radians(7), 1.6, 0.8, PAVE)
        crowd(*at(a, R_PLOT - 84), 4, 14)

    arrival(GAP[0])
    parking(GAP[60])
    retail(GAP[120])
    dealership(GAP[180])
    apartments(GAP[240])
    event_lawn(GAP[300])

    # street trees and lamps down both ring roads
    for i in range(44):
        a = i * math.pi / 22
        for r in (R_ROAD_IN - 20, R_ROAD_IN + 20, R_ROAD_OUT - 20, R_ROAD_OUT + 20):
            if r > R_PARK + 6:
                tree(*at(a, r), 0.95)
    for i in range(16):
        a = i * math.pi / 8
        lamp(*at(a, R_ROAD_IN + 20))
        lamp(*at(a, R_ROAD_OUT - 20))

    # traffic on both rings
    for i in range(20):
        a = i * math.pi / 10
        car(*at(a, R_ROAD_OUT + 7), a + math.pi / 2)
        if i % 2 == 0:
            car(*at(a + 0.08, R_ROAD_IN - 7), a + math.pi / 2 + math.pi)
    bus(*at(math.radians(42), R_ROAD_OUT - 7), math.radians(42) + math.pi / 2)
    bus(*at(math.radians(196), R_ROAD_IN + 7), math.radians(196) + math.pi / 2)

    # the entrance road, in from the east
    half = math.atan2(17, R_ROAD_OUT + 200)
    wedge("entry", R_ROAD_OUT, R_ROAD_OUT + 300, GAP[0] - half, GAP[0] + half, 1.2, 0.6, ASPHALT)


def shot(name, **kw):
    K.preview(os.path.join(OUT, name), CO._objs, **kw)
    print("wrote", name, "/", len(CO._objs), "objects")


def main():
    build()
    shot("dist_top.png", size=(1500, 1050), elev=54, azim=20, target=Vector((0, 0, 40)), cam_dist=2050)
    shot("dist_park.png", size=(1500, 950), elev=11, azim=90, target=Vector((0, 0, 4)), cam_dist=360)

    # A district shot must look OUTWARD from inside the ring -- that is how a
    # player arrives at one. K.preview puts the camera at target + dist*(sin a,
    # -cos a), so for a district at world angle W the camera lands INSIDE only
    # at azim = W - 90. The first pass used W + 90, which put the camera out
    # past the buildings and framed the plaza and the park instead of the shops.
    for name, W in (("retail", 120), ("dealer", 180), ("apts", 240), ("event", 300)):
        a = math.radians(W)
        shot("dist_%s.png" % name, size=(1500, 950), elev=13, azim=W - 90,
             target=Vector((math.cos(a) * R_DIST, math.sin(a) * R_DIST, 22)), cam_dist=440)
    print("done")


if __name__ == "__main__":
    main()
