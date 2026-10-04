"""lp_trees.py -- v4.1 the low-poly tree set and clouds (28 Sep 2026).

Style B (art/v402/STYLE_COMPARISON.png): every tree is ONE mesh with its colour
in the facets (vertex colour per face, every face its own vertices so Roblox
shades it flat). Tops are lighter than undersides so the shape reads even in
flat light. Built Z-up in studs; the game scales each to a target height.

  LP_Oak_A / LP_Oak_B     valley oak: a broad, slightly flat-topped crown
  LP_Redwood_A / _B       stacked seven-sided tiers on a red trunk
  LP_Eucalypt             tall pale trunk, a loose grey-green crown
  LP_Palm_A / LP_Palm_B   ringed trunk, eight drooping fronds
  LP_Orchard              a small round fruit tree
  LP_Bush                 two low mounds
  LP_Grove                three crowns as one mesh (distant woodland)
  LP_RedwoodGrove         four redwoods as one mesh (the far crest)
  LP_Cloud_A/B/C          flat-bottomed faceted cumulus

Run:  blender -b --python lp_trees.py   -> out/IMPORT_LP_TREES/*.fbx + out/lp_trees_sheet.png
"""
import bpy
import bmesh
import math
import os
import random
import sys
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import svkit as K  # noqa: E402

OUT = os.path.join(HERE, "out")
IMP = os.path.join(OUT, "IMPORT_LP_TREES")
os.makedirs(IMP, exist_ok=True)
for f in os.listdir(IMP):
    os.remove(os.path.join(IMP, f))


def rgb(r, g, b):
    return (r / 255.0, g / 255.0, b / 255.0)


class Builder:
    """Collects faces into one bmesh with a colour per face."""

    def __init__(self, seed):
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.color.new("Col")
        self.rng = random.Random(seed)

    def add(self, verts, faces, colour_fn):
        vs = [self.bm.verts.new(v) for v in verts]
        for f in faces:
            face = self.bm.faces.new([vs[i] for i in f])
            face.normal_update()
            c = colour_fn(face, self.rng)
            for loop in face.loops:
                loop[self.col] = (c[0], c[1], c[2], 1.0)

    def blob(self, centre, radius, scale=(1, 1, 1), jitter=0.12, subdiv=1, colour_fn=None, flat_bottom=None):
        tmp = bmesh.new()
        bmesh.ops.create_icosphere(tmp, subdivisions=subdiv, radius=1.0)
        verts, faces = [], []
        idx = {}
        for v in tmp.verts:
            p = Vector(v.co)
            p += Vector((self.rng.uniform(-1, 1), self.rng.uniform(-1, 1), self.rng.uniform(-1, 1))) * jitter
            p = Vector((p.x * scale[0], p.y * scale[1], p.z * scale[2])) * radius
            if flat_bottom is not None and p.z < -flat_bottom * radius:
                p.z = -flat_bottom * radius
            idx[v.index] = len(verts)
            verts.append(tuple(Vector(centre) + p))
        for f in tmp.faces:
            faces.append([idx[v.index] for v in f.verts])
        tmp.free()
        self.add(verts, faces, colour_fn)

    def cone(self, base, r1, r2, h, sides, colour_fn, tilt=(0, 0), cap_bottom=True):
        verts, faces = [], []
        tx, ty = tilt
        for k in range(sides):
            a = 2 * math.pi * (k + self.rng.uniform(-0.12, 0.12)) / sides
            verts.append((base[0] + r1 * math.cos(a), base[1] + r1 * math.sin(a), base[2]))
        top_c = (base[0] + tx * h, base[1] + ty * h, base[2] + h)
        if r2 > 1e-3:
            for k in range(sides):
                a = 2 * math.pi * k / sides + 0.2
                verts.append((top_c[0] + r2 * math.cos(a), top_c[1] + r2 * math.sin(a), top_c[2]))
            for k in range(sides):
                j = (k + 1) % sides
                faces.append([k, j, sides + j, sides + k])
            faces.append(list(range(2 * sides - 1, sides - 1, -1)) and list(range(sides, 2 * sides)))
        else:
            verts.append(top_c)
            for k in range(sides):
                j = (k + 1) % sides
                faces.append([k, j, sides])
        if cap_bottom:
            faces.append(list(reversed(range(sides))))
        self.add(verts, faces, colour_fn)

    def finish(self, name):
        bm = self.bm
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bmesh.ops.triangulate(bm, faces=bm.faces)
        bmesh.ops.split_edges(bm, edges=bm.edges)           # every face its own vertices: flat shading
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        o = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(o)
        for p in me.polygons:
            p.use_smooth = False
        if me.color_attributes:
            me.color_attributes.active_color = me.color_attributes[0]
            me.color_attributes.render_color_index = 0
        return o


def leafy(light, mid, dark, var=0.05):
    """Tops light, sides mid, undersides dark, a little random per facet."""
    def f(face, rng):
        z = face.normal.z
        base = light if z > 0.45 else (mid if z > -0.25 else dark)
        k = 1 + rng.uniform(-var, var)
        return tuple(min(1.0, c * k) for c in base)
    return f


def solid(c, var=0.04):
    def f(face, rng):
        k = 1 + rng.uniform(-var, var)
        z = face.normal.z
        k *= 1.06 if z > 0.5 else (0.9 if z < -0.5 else 1.0)
        return tuple(min(1.0, v * k) for v in c)
    return f


OAK = leafy(rgb(124, 158, 78), rgb(100, 136, 66), rgb(74, 104, 54))
OAK2 = leafy(rgb(132, 162, 84), rgb(108, 142, 70), rgb(80, 108, 58))
BARK = solid(rgb(112, 86, 62))
RED_BARK = solid(rgb(138, 84, 62))
REDWOOD = leafy(rgb(78, 122, 86), rgb(62, 104, 74), rgb(46, 80, 58))
EUC_BARK = solid(rgb(198, 190, 172))
EUC = leafy(rgb(150, 172, 126), rgb(128, 152, 110), rgb(98, 120, 88))
PALM_BARK = solid(rgb(156, 126, 94))
PALM_RING = solid(rgb(128, 102, 76))
FROND = leafy(rgb(112, 156, 76), rgb(92, 136, 64), rgb(70, 110, 52))
ORCH = leafy(rgb(140, 176, 88), rgb(116, 156, 74), rgb(86, 120, 58))
CLOUD = leafy(rgb(252, 252, 250), rgb(238, 241, 246), rgb(212, 219, 232), var=0.015)


def oak(name, seed, blobs):
    b = Builder(seed)
    b.cone((0, 0, 0), 0.95, 0.55, 5.2, 6, BARK, tilt=(0.05, 0.02))
    b.cone((0.2, 0.1, 3.6), 0.45, 0.2, 2.6, 5, BARK, tilt=(0.55, 0.1), cap_bottom=False)
    b.cone((-0.1, 0, 3.8), 0.4, 0.18, 2.4, 5, BARK, tilt=(-0.5, -0.2), cap_bottom=False)
    for k, (c, r, s) in enumerate(blobs):
        # the main crown one step rounder (80 facets), the side crowns 20
        b.blob(c, r, s, jitter=0.1 if k == 0 else 0.14, subdiv=2 if k == 0 else 1,
               colour_fn=OAK if seed % 2 else OAK2, flat_bottom=0.55)
    return b.finish(name)


def redwood(name, seed, tiers):
    b = Builder(seed)
    b.cone((0, 0, 0), 0.9, 0.45, 7.5, 6, RED_BARK)
    z = 4.5
    for (r, h) in tiers:
        b.cone((0, 0, z), r, 0, h, 7, REDWOOD)
        z += h * 0.58
    return b.finish(name)


def palm(name, seed, segs, lean, frond_len):
    b = Builder(seed)
    z, x = 0.0, 0.0
    r = 0.62
    for k in range(segs):
        dx = lean * (k / segs) ** 2
        b.cone((x, 0, z), r, r * 0.93, 2.0, 6, PALM_BARK if k % 2 == 0 else PALM_RING, tilt=(dx / 2.0 * 0.4, 0), cap_bottom=(k == 0))
        x += dx * 0.4
        z += 2.0
        r *= 0.95
    top = Vector((x, 0, z))
    b.blob(tuple(top + Vector((0, 0, -0.2))), 0.75, jitter=0.05, subdiv=1, colour_fn=solid(rgb(110, 84, 56)))
    n = 8
    for k in range(n):
        a = 2 * math.pi * (k + b.rng.uniform(-0.15, 0.15)) / n
        d = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-d.y, d.x, 0))
        droop = b.rng.uniform(0.35, 0.6)
        L = frond_len * b.rng.uniform(0.85, 1.1)
        p0 = top
        p1 = top + d * L * 0.45 + side * 0.9 + Vector((0, 0, 0.9))
        p2 = top + d * L * 0.45 - side * 0.9 + Vector((0, 0, 0.9))
        p3 = top + d * L + Vector((0, 0, -L * droop))
        # a thin closed blade (a single face has no back in Roblox)
        dn = Vector((0, 0, -0.18))
        top_ = [p0, p1, p3, p2]
        verts = [tuple(p) for p in top_] + [tuple(p + dn) for p in top_]
        b.add(verts, [[0, 1, 2], [0, 2, 3], [6, 5, 4], [7, 6, 4],
                      [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]], FROND)
    return b.finish(name)


def eucalypt(name, seed):
    b = Builder(seed)
    b.cone((0, 0, 0), 0.8, 0.4, 13, 6, EUC_BARK, tilt=(0.04, 0.03))
    b.cone((0.4, 0.2, 9.5), 0.35, 0.15, 4, 5, EUC_BARK, tilt=(0.45, 0.2), cap_bottom=False)
    for (c, r, s) in [((0.6, 0.3, 15.5), 3.2, (1.0, 0.9, 1.35)), ((2.2, 0.8, 13.2), 2.4, (1, 1, 1.25)),
                      ((-1.6, -0.6, 13.8), 2.3, (1, 1, 1.3)), ((0.2, 0.2, 18.2), 1.9, (1, 1, 1.2))]:
        b.blob(c, r, s, jitter=0.18, colour_fn=EUC, flat_bottom=0.6)
    return b.finish(name)


def orchard(name, seed):
    b = Builder(seed)
    b.cone((0, 0, 0), 0.5, 0.35, 2.6, 6, BARK)
    b.blob((0, 0, 4.2), 2.6, (1.1, 1.1, 0.9), jitter=0.1, subdiv=2, colour_fn=ORCH, flat_bottom=0.6)
    return b.finish(name)


def bush(name, seed):
    b = Builder(seed)
    b.blob((0, 0, 0.9), 1.6, (1.2, 1.0, 0.8), jitter=0.15, colour_fn=OAK2, flat_bottom=0.55)
    b.blob((1.4, 0.4, 0.7), 1.1, (1.1, 1.0, 0.8), jitter=0.15, colour_fn=OAK2, flat_bottom=0.6)
    return b.finish(name)


def grove(name, seed):
    b = Builder(seed)
    for (c, r) in [((0, 0, 3.8), 4.2), ((6.5, 2.5, 3.2), 3.6), ((-4.5, 4.8, 3.0), 3.4)]:
        b.blob(c, r, (1.15, 1.15, 0.85), jitter=0.14, colour_fn=OAK, flat_bottom=0.7)
    return b.finish(name)


def redwood_grove(name, seed):
    b = Builder(seed)
    for (ox, oy, s) in [(0, 0, 1.0), (5, 2, 0.85), (-4, 4, 0.9), (2, -5, 0.8)]:
        z = 2.0 * s
        b.cone((ox, oy, 0), 0.8 * s, 0.4 * s, 6 * s, 5, RED_BARK)
        for (r, h) in [(4.0, 7), (3.1, 6), (2.1, 5)]:
            b.cone((ox, oy, z), r * s, 0, h * s, 6, REDWOOD)
            z += h * s * 0.6
    return b.finish(name)


def cloud(name, seed, puffs):
    b = Builder(seed)
    for (c, r) in puffs:
        b.blob(c, r, (1.25, 1.0, 0.72), jitter=0.1, colour_fn=CLOUD, flat_bottom=0.35)
    return b.finish(name)


K.reset()
assets = [
    oak("LP_Oak_A", 3, [((0, 0, 8.2), 4.6, (1.2, 1.15, 0.78)), ((3.3, 1.0, 7.4), 3.2, (1, 1, 0.8)), ((-3.0, -1.4, 7.6), 3.0, (1, 1, 0.8))]),
    oak("LP_Oak_B", 4, [((0.4, 0, 8.0), 4.8, (1.25, 1.1, 0.75)), ((-2.6, 1.8, 7.2), 3.0, (1, 1, 0.8))]),
    redwood("LP_Redwood_A", 5, [(4.2, 6.0), (3.5, 5.6), (2.7, 5.0), (1.8, 4.4), (1.0, 3.6)]),
    redwood("LP_Redwood_B", 6, [(3.8, 6.4), (3.0, 5.6), (2.1, 4.8), (1.2, 4.0)]),
    eucalypt("LP_Eucalypt", 7),
    palm("LP_Palm_A", 8, 8, 2.2, 5.2),
    palm("LP_Palm_B", 9, 10, 0.8, 4.8),
    orchard("LP_Orchard", 10),
    bush("LP_Bush", 11),
    grove("LP_Grove", 12),
    redwood_grove("LP_RedwoodGrove", 13),
    cloud("LP_Cloud_A", 14, [((0, 0, 0), 9), ((10, 2, -1), 7), ((-9, -1, -1.5), 6.5), ((3, -5, 2), 6)]),
    cloud("LP_Cloud_B", 15, [((0, 0, 0), 8), ((8, 3, 1), 6), ((-7, 0, -1), 5)]),
    cloud("LP_Cloud_C", 16, [((0, 0, 0), 10), ((11, -2, -1), 7.5), ((-10, 2, -1), 7), ((4, 6, 1), 6), ((-3, -6, 1.5), 5.5)]),
]
for o in assets:
    print("ASSET %s tris %d" % (o.name, K.tris(o)))
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.export_scene.fbx(filepath=os.path.join(IMP, o.name + ".fbx"), use_selection=True, apply_unit_scale=True,
                             apply_scale_options="FBX_SCALE_ALL", global_scale=1.0, mesh_smooth_type="OFF",
                             use_mesh_modifiers=True, colors_type="SRGB", add_leaf_bones=False, bake_anim=False,
                             axis_forward="-Z", axis_up="Y")

# contact sheet: trees in a row, clouds above
x = 0.0
for o in assets:
    w = max(o.dimensions.x, o.dimensions.y)
    if o.name.startswith("LP_Cloud"):
        continue
    o.location = (x + w / 2, 0, 0)
    x += w + 3
cx = 0.0
for o in assets:
    if o.name.startswith("LP_Cloud"):
        o.location = (cx + 12, 10, 34)
        cx += 34
scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "VERTEX"
scene.display.shading.show_shadows = False
scene.display.shading.show_cavity = False
scene.render.resolution_x, scene.render.resolution_y = 1800, 700
cam_data = bpy.data.cameras.new("Cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = x + 4
cam = bpy.data.objects.new("Cam", cam_data)
scene.collection.objects.link(cam)
cam.location = (x / 2, -120, 18)
cam.rotation_euler = (math.radians(82), 0, 0)
scene.camera = cam
scene.render.filepath = os.path.join(OUT, "lp_trees_sheet.png")
bpy.ops.render.render(write_still=True)
