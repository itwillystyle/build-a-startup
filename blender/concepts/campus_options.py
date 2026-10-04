"""
campus_options.py -- the two campus-green layouts, at true game scale, so the
choice can be made by looking instead of by reading a description.

Both use the real numbers: six plots, a tower on each, and the road the game
already has. Nothing here is a game asset -- it is a concept render only.

  A  THREE GREENS      the road stays the spine and splits around a planted
                       square at each plot pair. Nothing moves.
  B  THE SUN           a sunken circular lawn in the middle, six paved spokes
                       out to six plots on a ring, raised planted wedges
                       between the spokes. The plots move.

Run:  blender -b --python blender/concepts/campus_options.py
Out:  blender/out/campus_A_three_greens.png
      blender/out/campus_B_sun.png
      blender/out/campus_B_eye.png      (low angle: the depth is the point)
      blender/out/campus_options.png    (A and B side by side)
"""

import bmesh
import bpy
import math
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
from mathutils import Vector  # noqa: E402

import svkit as K  # noqa: E402

OUT = os.path.join(HERE, "out")
os.makedirs(OUT, exist_ok=True)

# ART.md palette
LAWN = K.rgb(122, 170, 80)
LAWN_D = K.rgb(96, 142, 62)
VALLEY = K.rgb(200, 168, 96)      # the game's golden valley floor: a green lawn has to read AGAINST this
CONCRETE = K.rgb(207, 198, 182)
PAPER = K.rgb(243, 239, 230)
ROAD = K.rgb(74, 74, 78)
GLASS = K.rgb(118, 158, 176)
OAK = K.rgb(192, 138, 85)
GOLD = K.rgb(224, 182, 90)
TRUNK = K.rgb(150, 96, 62)
LEAF = K.rgb(78, 168, 92)
INK = K.rgb(30, 37, 48)

# the game's real numbers
PLOT_X = (-360.0, 0.0, 360.0)
ROAD_W = 26.0
TOWER_R = 60.0        # wafer 1 radius
TOWER_H = 150.0

_objs = []


def box(name, sx, sy, sz, x, y, z, col, shade=True):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, z))
    o = bpy.context.object
    o.name = name
    o.scale = (sx, sy, sz)
    # location and rotation default to TRUE on this operator. Applying them bakes
    # the position into the mesh and moves the object origin to (0,0,0), so any
    # later `o.rotation_euler = ...` spins the thing around the WORLD origin and
    # flings it across the map instead of turning it in place. Only the scale
    # should be baked.
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    K.paint(o, K.shaded(col) if shade else K.flat(col))
    _objs.append(o)
    return o


def cyl(name, r, h, x, y, z, col, seg=32, shade=True):
    bpy.ops.mesh.primitive_cylinder_add(vertices=seg, radius=r, depth=h, location=(x, y, z))
    o = bpy.context.object
    o.name = name
    K.paint(o, K.shaded(col) if shade else K.flat(col))
    _objs.append(o)
    return o


def tube(name, r_out, r_in, h, x, y, z, col, seg=48):
    """A ring: an outer cylinder with an inner one cut out. Used for the sunken steps."""
    o = cyl(name, r_out, h, x, y, z, col, seg)
    inner = cyl(name + "_cut", r_in, h * 3, x, y, z, col, seg)
    _objs.remove(inner)
    m = o.modifiers.new("cut", "BOOLEAN")
    m.operation = "DIFFERENCE"
    m.object = inner
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier="cut")
    bpy.data.objects.remove(inner)
    K.paint(o, K.shaded(col))
    return o


def wedge(name, r_in, r_out, a0, a1, h, z, col, seg=14):
    """An annular sector: the shape a sun-ray stripe actually is.

    A rotated rectangle only looks like a ray near the middle -- its sides stay
    parallel while the ring opens out, so it reads as a loose plank lying on a
    circle. A sector's sides follow the radius, so it widens with the ring and
    the six of them together read as one sun."""
    bm = bmesh.new()
    angs = [a0 + (a1 - a0) * i / seg for i in range(seg + 1)]
    outer = [bm.verts.new((math.cos(a) * r_out, math.sin(a) * r_out, 0.0)) for a in angs]
    inner = [bm.verts.new((math.cos(a) * r_in, math.sin(a) * r_in, 0.0)) for a in angs]
    bm.faces.new(outer + list(reversed(inner)))
    o = K.mesh_obj(name, bm)
    o.location = (0, 0, z)
    m = o.modifiers.new("solid", "SOLIDIFY")
    m.thickness = h
    m.offset = 0
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier="solid")
    K.paint(o, K.shaded(col))
    _objs.append(o)
    return o


def tower(x, y, label_gold=False):
    """A simplified wafer stack, enough to read as one of the player's buildings."""
    cyl("podium", TOWER_R + 10, 18, x, y, 9, CONCRETE, 32)
    for i in range(4):
        z = 24 + i * 34
        r = TOWER_R - i * 4
        cyl("storey", r, 26, x, y, z + 13, GLASS, 32)
        cyl("deck", r + 6, 5, x, y, z + 28, PAPER, 32)
    cyl("crown", TOWER_R - 18, 14, x, y, 24 + 4 * 34 + 7, GOLD if label_gold else PAPER, 32)


def tree(x, y, s=1.0):
    cyl("trunk", 1.6 * s, 10 * s, x, y, 5 * s, TRUNK, 8)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=9 * s, location=(x, y, 15 * s))
    o = bpy.context.object
    o.name = "leaf"
    K.paint(o, K.shaded(LEAF))
    _objs.append(o)


def bench(x, y, rot=0.0):
    o = box("bench", 7, 2.2, 1.2, x, y, 2.4, OAK)
    o.rotation_euler = (0, 0, rot)


def ground(size=1000.0):
    box("ground", size, size, 2, 0, 0, -1, VALLEY)


# ------------------------------------------------------------------ OPTION A
def option_a():
    """The road stays the spine and splits around a planted square at each pair.

    A green per plot pair, between the two buildings that face each other.
    The road already connects the six plots, so the cheapest place to put a
    destination is in the road itself -- a planted median, the oldest
    town-square move there is. No plot moves."""
    K.reset()
    _objs.clear()
    ground(1300)

    GREEN_W, GREEN_D = 190.0, 150.0
    PLOT_Y = 185.0                       # clear of the green: tower radius is 70

    for x in PLOT_X:
        # the road splits into two carriageways, one each side of the green
        for sgn in (-1, 1):
            box("road", 360, ROAD_W, 1.2, x, sgn * (GREEN_D / 2 + ROAD_W / 2 + 4), 0.6, ROAD, False)
        # the green: kerbed, and a step up from the road
        box("kerb", GREEN_W + 8, GREEN_D + 8, 2.0, x, 0, 1.0, CONCRETE)
        box("green", GREEN_W, GREEN_D, 2.6, x, 0, 1.5, LAWN)
        # a path from each plot's door across the road into the middle
        for sgn in (-1, 1):
            box("path", 16, GREEN_D / 2 + 30, 0.8, x, sgn * (GREEN_D / 2 + 30) / 2, 2.9, CONCRETE)
        box("path", GREEN_W, 16, 0.8, x, 0, 2.9, CONCRETE)
        # the paved centre, with benches and trees round it
        cyl("plaza", 30, 1.0, x, 0, 3.1, CONCRETE, 24)
        cyl("medallion", 11, 0.6, x, 0, 3.7, GOLD, 24)
        for i in range(4):
            a = math.pi / 4 + i * math.pi / 2
            bench(x + math.cos(a) * 44, math.sin(a) * 36, a)
        for i in range(8):
            a = i * math.pi / 4
            tree(x + math.cos(a) * 76, math.sin(a) * 58, 1.1)
        # the pair of towers facing each other across it
        tower(x, -PLOT_Y)
        tower(x, PLOT_Y)

    # the road running on between the three greens
    for i in range(2):
        xm = (PLOT_X[i] + PLOT_X[i + 1]) / 2
        box("road", abs(PLOT_X[i + 1] - PLOT_X[i]) - 360, ROAD_W, 1.2, xm, 0, 0.6, ROAD, False)
    for sgn in (-1, 1):
        box("road", 240, ROAD_W, 1.2, sgn * (PLOT_X[2] + 180), 0, 0.6, ROAD, False)


# ------------------------------------------------------------------ OPTION B
def option_b():
    """The sun: a sunken circular lawn, six spokes, six plots on a ring.

    The centre is NOT a flat disc -- that was the thing to avoid. It steps DOWN
    in three rings to a paved floor with a gold medallion at the bottom, so it
    reads as a bowl you walk into. That is where the depth comes from.

    Round it, six paved spokes run out to the six plots, and between every pair
    of spokes sits a RAISED planted wedge. Those are the stripes: because they
    are true annular sectors they widen as the ring opens out, so the six of
    them read as one sun with rays rather than as six planks on a circle. They
    are also where the trees and benches go, so the ring has something in it at
    eye level instead of being an empty doughnut."""
    K.reset()
    _objs.clear()

    R_BOWL = 120.0          # outer lip of the sunken lawn
    R_RING = 330.0          # the ring the plots stand on
    STEPS = 3
    STEP_W = 26.0
    SPOKE_HALF = math.radians(7.5)
    R_FLOOR = R_BOWL - STEPS * STEP_W

    # the valley floor, with a HOLE under the bowl. Without the hole the ground
    # slab sits above the sunken floor and you see dirt where the paving is --
    # the bowl has to actually cut into the ground to be a bowl.
    tube("ground", 1500, R_FLOOR, 2, 0, 0, -1, VALLEY)

    # the bowl: rings stepping DOWN to a paved floor
    for i in range(STEPS):
        r_out = R_BOWL - i * STEP_W
        r_in = R_BOWL - (i + 1) * STEP_W
        tube("step", r_out, r_in, 7 + i * 3, 0, 0, 2 - i * 6, LAWN if i % 2 == 0 else LAWN_D)
    cyl("bowlfloor", R_FLOOR, 3, 0, 0, -17, CONCRETE, 48)
    cyl("medallion", 18, 1.4, 0, 0, -15, GOLD, 32)

    r0, r1 = R_BOWL + 4, R_RING - TOWER_R - 12
    for i in range(6):
        a = i * math.pi / 3
        ca, sa = math.cos(a), math.sin(a)
        # the paved spoke out to this plot's door
        wedge("spoke", r0, r1 + 12, a - SPOKE_HALF, a + SPOKE_HALF, 2.0, 1.0, CONCRETE)
        # the raised planted stripe between this spoke and the next
        b0, b1 = a + SPOKE_HALF + math.radians(3), a + math.pi / 3 - SPOKE_HALF - math.radians(3)
        wedge("stripekerb", r0 + 4, r1, b0, b1, 7.0, 1.0, CONCRETE)
        wedge("stripe", r0 + 9, r1 - 5, b0 + math.radians(1.6), b1 - math.radians(1.6), 7.4, 1.4, LAWN)
        bm_mid = (b0 + b1) / 2
        for t in (0.22, 0.52, 0.82):
            rr = r0 + (r1 - r0) * t
            tree(math.cos(bm_mid) * rr, math.sin(bm_mid) * rr, 1.15)
        bench(ca * (R_BOWL + 30), sa * (R_BOWL + 30), a + math.pi / 2)
        tower(ca * R_RING, sa * R_RING)

    # the ring road outside the plots, with one approach in from the east
    tube("ringroad", R_RING + TOWER_R + 40, R_RING + TOWER_R + 40 - ROAD_W, 1.2, 0, 0, 0.6, ROAD)
    box("approach", 320, ROAD_W, 1.2, R_RING + TOWER_R + 200, 0, 0.6, ROAD, False)


def shot(path, elev, azim, size=(1280, 900), target=None, dist=None):
    K.preview(path, _objs, size=size, elev=elev, azim=azim, target=target, cam_dist=dist)
    print("wrote", os.path.basename(path))


def main():
    option_a()
    # explicit distance: the ground slab is far bigger than the content, so
    # auto-framing fits the SLAB and the campus becomes a speck
    shot(os.path.join(OUT, "campus_A_three_greens.png"), elev=46, azim=26, target=Vector((0, 0, 40)), dist=1250)
    # standing on the road at the middle green, the view a player gets
    shot(os.path.join(OUT, "campus_A_eye.png"), elev=7, azim=18, target=Vector((0, 0, 12)), dist=430)

    option_b()
    shot(os.path.join(OUT, "campus_B_sun.png"), elev=50, azim=26, target=Vector((0, 0, 30)), dist=1150)
    # azim is offset 90 from world angle, so 120 puts the camera over a STRIPE
    # at world 30 deg -- looking into the bowl with no tower blocking it
    shot(os.path.join(OUT, "campus_B_eye.png"), elev=8, azim=120, target=Vector((0, 0, 10)), dist=470)
    shot(os.path.join(OUT, "campus_B_bowl.png"), elev=16, azim=120, target=Vector((0, 0, -6)), dist=300)

    print("done")


if __name__ == "__main__":
    main()
