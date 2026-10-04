"""props.py -- the chunky street kit (v4.8, the Blender geometry pass).

WHY THIS EXISTS. The cartoon pass (v4.7) did light and colour, and the honest
note at the end of it was that the geometry is still the last 20%: the campus
is built out of script Parts, and a Part has a hard 90-degree edge at every
corner. Roblox has no bevel. Flat colour on a razor-edged box reads as a
render of a box; the same shape with a fat rounded edge reads as drawn.

So: the things a player walks past at arm's length -- lamps, benches, bins,
bollards, planters, parasols -- are modelled here instead, with the three
things that make geometry read as cartoon:

  * BEVEL. Every edge is rounded by 4-10% of the part's own size. That is far
    more than an architect would draw and is the whole point.
  * EXAGGERATED PROPORTION. Fat posts, heavy caps, thick seats. A real bollard
    is slim; a drawn one is a fat capsule.
  * SILHOUETTE OVER DETAIL. No fittings, no bolts, no slats you cannot see
    from four studs away. Each prop is one joined mesh, one draw call.

Vertex colours only, like the rest of the kit (the importer drops material
colours and keeps vertex ones). 1 unit = 1 stud.

    blender -b --python blender/props.py

Everything lands in blender/out/IMPORT_PROPS/ for one Bulk Import, and every
caller in the game falls back to the old part-built version if the mesh is
missing -- so this can be imported late, or never, without breaking anything.
"""
import os
import sys
import math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import svkit as K
from mathutils import Vector

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "IMPORT_PROPS")
os.makedirs(OUT, exist_ok=True)

CHARCOAL = K.rgb(54, 58, 66)
STEEL = K.rgb(150, 155, 162)
OAK = K.rgb(186, 134, 84)
PAPER = K.rgb(238, 235, 228)
LAMP = K.rgb(255, 238, 198)
LEAF = K.rgb(96, 158, 92)
SOIL = K.rgb(86, 70, 54)
RED = K.rgb(206, 78, 66)
TEAL = K.rgb(70, 160, 150)
CONCRETE = K.rgb(204, 198, 186)


def box(name, size, at=(0, 0, 0), bev=None, segs=3):
    """A box whose edges are rounded by `bev` (default: 9% of its smallest side)."""
    import bmesh
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    o = K.mesh_obj(name, bm)
    o.scale = size
    o.location = at
    K.bpy.context.view_layer.objects.active = o
    K.bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    K.bevel(o, width=bev if bev is not None else min(size) * 0.09, segments=segs, angle=30)
    K.apply_mods(o)
    return o


def capsule(name, r, h, at=(0, 0, 0), segs=16):
    """A fat rounded post: the shape a drawn bollard or lamp column has."""
    prof = []
    for i in range(5):                                   # rounded foot
        a = math.pi / 2 * i / 4
        prof.append((r * math.sin(a), r * 0.35 * (1 - math.cos(a))))
    prof.append((r, h - r * 0.9))
    for i in range(1, 6):                                # rounded cap
        a = math.pi / 2 * i / 5
        prof.append((r * math.cos(a), h - r * 0.9 + r * 0.9 * math.sin(a)))
    o = K.lathe(name, prof, segments=segs)
    o.location = at
    K.bpy.context.view_layer.objects.active = o
    K.bpy.ops.object.transform_apply(location=True)
    return o


# ---------------------------------------------------------------- the props
def lamp():
    """A street lamp: fat tapered column, heavy rounded head. 14 studs tall."""
    base = K.lathe("base", [(1.5, 0), (1.5, 0.5), (1.15, 0.9), (1.0, 1.1)], 16)
    K.paint(base, K.shaded(CHARCOAL))
    col = K.lathe("col", [(0.62, 1.0), (0.54, 7.0), (0.5, 11.2)], 14)
    K.paint(col, K.shaded(CHARCOAL))
    neck = K.lathe("neck", [(0.5, 11.2), (0.95, 11.9), (1.25, 12.3)], 14)
    K.paint(neck, K.shaded(CHARCOAL))
    head = box("head", (3.4, 3.4, 1.5), (0, 0, 13.0), bev=0.5, segs=4)
    K.paint(head, K.shaded(CHARCOAL, 1.0, 0.85))
    glass = box("glass", (2.7, 2.7, 0.55), (0, 0, 12.4), bev=0.22, segs=3)
    K.paint(glass, K.flat(LAMP))
    o = K.join([base, col, neck, head, glass], "SVP_Lamp")
    K.smooth(o, 45)
    return o


def bench():
    """A bench: one thick rounded slab and two fat legs. 7 x 2.6 x 3 studs."""
    seat = box("seat", (7.0, 2.4, 0.75), (0, 0, 2.05), bev=0.3, segs=4)
    K.paint(seat, K.shaded(OAK))
    back = box("back", (7.0, 0.7, 1.9), (0, -1.0, 3.2), bev=0.28, segs=4)
    K.paint(back, K.shaded(OAK))
    parts = [seat, back]
    for sx in (-1, 1):
        leg = box("leg", (0.95, 2.1, 2.1), (sx * 2.7, 0, 1.05), bev=0.3, segs=4)
        K.paint(leg, K.shaded(CHARCOAL))
        parts.append(leg)
    o = K.join(parts, "SVP_Bench")
    K.smooth(o, 45)
    return o


def bin_():
    """A litter bin: a rounded barrel with a fat lid. 2.8 x 2.8 x 4."""
    body = K.lathe("body", [(1.05, 0.2), (1.3, 0.55), (1.35, 2.9), (1.25, 3.2)], 16)
    K.paint(body, K.shaded(CHARCOAL))
    lid = K.lathe("lid", [(1.45, 3.2), (1.5, 3.5), (1.25, 3.95), (0, 4.1)], 16)
    K.paint(lid, K.shaded(STEEL))
    o = K.join([body, lid], "SVP_Bin")
    K.smooth(o, 45)
    return o


def bollard():
    """A bollard: a fat capsule with a band. Real ones are slim; drawn ones are not."""
    post = capsule("post", 0.78, 3.6)
    K.paint(post, K.shaded(STEEL))
    band = K.lathe("band", [(0.88, 2.5), (0.9, 3.0), (0.86, 3.05)], 16)
    K.paint(band, K.flat(CHARCOAL))
    o = K.join([post, band], "SVP_Bollard")
    K.smooth(o, 45)
    return o


def planter():
    """A planter: a rounded tub with soil and a clipped shrub. 6 x 6 x 5."""
    tub = K.lathe("tub", [(2.4, 0), (2.9, 0.5), (3.0, 2.2), (2.75, 2.6), (2.5, 2.5)], 18)
    K.paint(tub, K.shaded(CONCRETE))
    soil = K.lathe("soil", [(2.5, 2.45), (2.4, 2.6), (0, 2.65)], 18)
    K.paint(soil, K.flat(SOIL))
    bush = K.lathe("bush", [(0, 2.5), (2.0, 3.1), (2.3, 4.0), (1.5, 4.9), (0, 5.2)], 14)
    K.paint(bush, K.shaded(LEAF, 1.12, 0.74))
    o = K.join([tub, soil, bush], "SVP_Planter")
    K.smooth(o, 50)
    return o


def parasol():
    """A cafe table under a thick scalloped parasol. 8 across, 9 tall."""
    foot = K.lathe("foot", [(1.3, 0), (1.4, 0.35), (1.1, 0.5)], 14)
    K.paint(foot, K.shaded(CHARCOAL))
    post = K.lathe("post", [(0.3, 0.4), (0.3, 8.2)], 10)
    K.paint(post, K.shaded(STEEL))
    top = box("top", (4.6, 4.6, 0.4), (0, 0, 2.85), bev=0.18, segs=3)
    K.paint(top, K.shaded(PAPER))
    # the canopy: a low cone with a fat rolled edge, not a flat disc
    canopy = K.lathe("canopy", [(0, 9.0), (2.6, 8.4), (4.0, 7.7), (4.15, 7.45), (3.9, 7.5)], 12)
    K.paint(canopy, K.shaded(RED, 1.1, 0.78))
    o = K.join([foot, post, top, canopy], "SVP_Parasol")
    K.smooth(o, 45)
    return o


def hydrant():
    """A fat hydrant. Pure silhouette: a body, two shoulders, a domed cap."""
    body = K.lathe("body", [(0.75, 0), (0.9, 0.35), (0.85, 2.3), (1.0, 2.6), (0.8, 2.9), (0.55, 3.2), (0, 3.4)], 14)
    K.paint(body, K.shaded(RED))
    parts = [body]
    for sx in (-1, 1):
        arm = capsule("arm", 0.42, 1.0, (sx * 1.05, 0, 1.5), segs=10)
        arm.rotation_euler = (0, math.radians(90 * sx), 0)
        K.bpy.context.view_layer.objects.active = arm
        K.bpy.ops.object.transform_apply(rotation=True)
        K.paint(arm, K.shaded(RED, 1.05, 0.8))
        parts.append(arm)
    o = K.join(parts, "SVP_Hydrant")
    K.smooth(o, 45)
    return o


def shelter():
    """A bus shelter: fat posts, a thick rounded roof, a bench. 22 x 10 x 11."""
    roof = box("roof", (22.0, 10.0, 1.1), (0, 0, 10.2), bev=0.45, segs=4)
    K.paint(roof, K.shaded(TEAL, 1.06, 0.8))
    parts = [roof]
    for sx in (-1, 1):
        for sy in (-1, 1):
            post = capsule("post", 0.5, 9.8, (sx * 9.6, sy * 4.2, 0), segs=12)
            K.paint(post, K.shaded(STEEL))
            parts.append(post)
    seat = box("seat", (17.0, 1.9, 0.6), (0, 3.0, 3.1), bev=0.26, segs=4)
    K.paint(seat, K.shaded(OAK))
    parts.append(seat)
    for sx in (-1, 1):
        leg = box("leg", (0.8, 1.7, 2.8), (sx * 7.4, 3.0, 1.4), bev=0.25, segs=3)
        K.paint(leg, K.shaded(CHARCOAL))
        parts.append(leg)
    o = K.join(parts, "SVP_Shelter")
    K.smooth(o, 45)
    return o


K.reset()
specs = [
    ("SVP_Lamp", lamp), ("SVP_Bench", bench), ("SVP_Bin", bin_),
    ("SVP_Bollard", bollard), ("SVP_Planter", planter), ("SVP_Parasol", parasol),
    ("SVP_Hydrant", hydrant), ("SVP_Shelter", shelter),
]
assets, x, total = [], 0, 0
for (nm, fn) in specs:
    o = fn()
    n = K.tris(o)
    total += n
    print(nm, "tris", n)
    K.export(os.path.join(OUT, nm + ".fbx"), [o])        # exported at the origin: base = pivot
    o.location = ((x % 4) * 15, -(x // 4) * 15, 0)        # a 4x2 grid, for the contact sheet only
    assets.append(o)
    x += 1
print("TOTAL TRIS", total)
K.preview(os.path.join(OUT, "props_sheet.png"), assets, size=(1500, 900),
          elev=17, azim=14, cam_dist=62, target=Vector((22, -7, 4)))
print("EXPORTED", len(specs))
