"""lp_world.py -- v4.1 THE LOW-POLY VALLEY (28 Sep 2026).

His verdict on the old look: "the hills are blurry and trashy... the blockiness
and the imitation of realism are ugly in combination... the trees look
extremely ugly". He picked style B from the side-by-side (art/v402): faceted,
flat-coloured hills and low-poly trees.

What this builds, from the game's OWN data so nothing moves:
  * heights: out/mountain_h.npy (the sampled terrain inside the valley, the
    eroded ranges outside) on a jittered 40-stud grid -> big flat facets;
  * colours: out/terrain_samples.txt carries the terrain MATERIAL of every
    8-stud sample, so golden fields, green lawns, orchard dirt and oak woodland
    stay exactly where they are -- as clean flat colours, one per facet;
  * flat places (plots, road, downtown, cross streets, rail) are held at y 0
    one grid step past their edges, so no facet can rise through a sidewalk;
  * the Bay: open water and the salt-pond marsh sit under the water line
    (ValleyGen lays the water and the ponds as parts: crisp rectangles).

Outputs
  out/IMPORT_LP_WORLD/LP_<i>_<j>.fbx   visual tiles (480 studs), every face its
                                       own vertices -> flat shading in Roblox
  out/LowPolyData.lua                  tile centres, the hill trees, and the
                                       walkable triangles (collision is built in
                                       Lua from these: exact, no mesh decomposition)
  out/lp_world_preview.png

Roblox (X, Y, Z) is modelled at Blender (-X, Z, Y) (measured, Phase W).
Run:  blender -b --python lp_world.py
"""
import bpy
import bmesh
import math
import os
import random
import sys

import numpy as np
from mathutils import Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import svkit as K  # noqa: E402

OUT = os.path.join(HERE, "out")
IMP = os.path.join(OUT, "IMPORT_LP_WORLD")
os.makedirs(IMP, exist_ok=True)
for f in os.listdir(IMP):
    os.remove(os.path.join(IMP, f))

SX = 1.35
SEAM = 600.0                 # stretched radius of the walkable valley (ValleyEdge sits at SEAM - 18)
S = 40.0                     # facet size
JIT = 0.3
FIELD = (-2400.0, 2400.0, -2200.0, 2200.0)
TILE = 480.0
WATER_Y = -1.6               # ValleyGen lays the water sheet here
BED_Y = -3.2

H = np.load(os.path.join(OUT, "mountain_h.npy"))
HX0, HZ0, HSTEP = -2400.0, -2200.0, 8.0


def h_at(x, z):
    fx, fz = (x - HX0) / HSTEP, (z - HZ0) / HSTEP
    j = int(min(max(math.floor(fx), 0), H.shape[1] - 2))
    i = int(min(max(math.floor(fz), 0), H.shape[0] - 2))
    tx, tz = min(max(fx - j, 0.0), 1.0), min(max(fz - i, 0.0), 1.0)
    a = H[i, j] * (1 - tx) + H[i, j + 1] * tx
    b = H[i + 1, j] * (1 - tx) + H[i + 1, j + 1] * tx
    return float(a * (1 - tz) + b * tz)


# the terrain's material per 8-stud sample: g Grass, l LeafyGrass, m Mud,
# d Ground, s Sand (the bay bed), i/t/b the salt ponds
with open(os.path.join(OUT, "terrain_samples.txt")) as f:
    sx0, sx1, sz0, sz1, sstep = (int(v) for v in f.readline().split())
    MAT = [[c[-1] for c in line.strip().split(",")] for line in f if line.strip()]


def mat_at(x, z):
    i, j = int(round((z - sz0) / sstep)), int(round((x - sx0) / sstep))
    if 0 <= i < len(MAT) and 0 <= j < len(MAT[0]):
        return MAT[i][j]
    return None


# every place something is built (SiliconCore's flat rects)
FLAT = []
for (px, pz) in [(-360, -150), (0, -150), (360, -150), (-360, 150), (0, 150), (360, 150)]:
    FLAT.append((px, pz, 240, 220))
FLAT += [(190, 0, 1520, 74), (780, 0, 320, 200), (-185, 0, 120, 540), (165, 0, 120, 540),
         ((-915 + 648) / 2, -330, 648 + 915, 40)]
MOUNDS = [(648 - 18, -330, 22, 1), (-915 + 18, -330, 22, -1)]   # the rail tunnel hills (x0, z, halfW, dir)


def in_mound(x, z):
    for (x0, mz, hw, d) in MOUNDS:
        if d * (x - x0) > -4 and abs(z - mz) < hw + 30:
            return True
    return False


def flat_pad(x, z, pad):
    for (fx, fz, fw, fd) in FLAT:
        if abs(x - fx) <= fw / 2 + pad and abs(z - fz) <= fd / 2 + pad:
            return True
    return False


def bay(x, z):
    return x < -640 and abs(z) < 560


def stretched(x, z):
    return math.sqrt((x / SX) ** 2 + z * z)


# ------------------------------------------------------------------ the vertex grid
rng = random.Random(41)
xs = np.arange(FIELD[0], FIELD[1] + 1, S)
zs = np.arange(FIELD[2], FIELD[3] + 1, S)
NX, NZ = len(xs), len(zs)
P = [[None] * NX for _ in range(NZ)]
M = [[None] * NX for _ in range(NZ)]
for i in range(NZ):
    for j in range(NX):
        edge = i in (0, NZ - 1) or j in (0, NX - 1)
        x = xs[j] + (0 if edge else rng.uniform(-JIT, JIT) * S)
        z = zs[i] + (0 if edge else rng.uniform(-JIT, JIT) * S)
        y = h_at(x, z)
        m = mat_at(x, z)
        if flat_pad(x, z, S * 0.9) and not in_mound(x, z):
            y = 0.0
        if bay(x, z) and not flat_pad(x, z, 6):
            if m == "s" or (m is None and y < 1.5):
                y = BED_Y                        # open water: the bed, under the sheet
            elif m in ("i", "t", "b", "d") and y < 1.5:
                y = WATER_Y - 0.25               # the marsh: the ponds sit on it as parts
        P[i][j] = (x, y, z)
        M[i][j] = m

# ------------------------------------------------------------------ colour
def rgb(r, g, b):
    return (r / 255.0, g / 255.0, b / 255.0)


LAWN = rgb(136, 172, 96)          # = the campus lawn (CampusArch)
FIELD_GOLD = rgb(206, 178, 106)
GOLD = rgb(224, 188, 110)
DRY = rgb(234, 208, 150)
OLIVE = rgb(192, 170, 100)
WOOD = rgb(150, 150, 84)          # the ground under oak woodland (the trees stand on it)
FOREST = rgb(98, 118, 74)         # the redwood crest's floor
ROCK = rgb(198, 180, 150)
DIRT = rgb(170, 144, 104)         # orchard floors, levees, the rail bed
SAND = rgb(214, 196, 152)
MARSH = rgb(164, 150, 104)


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[k] * (1 - t) + b[k] * t for k in range(3))


def n3(x, z, f, s):
    return noise.noise(Vector((x * f, z * f, s)))


def face_colour(c, n, mats):
    cx, cy, cz = c
    slope = math.sqrt(max(0.0, 1 - n[1] * n[1])) / max(0.05, n[1])      # rise over run
    m = max(set(m for m in mats if m), key=mats.count) if any(mats) else None
    if cy < WATER_Y + 0.5 and bay(cx, cz):
        col = SAND if cy < WATER_Y - 1 else MARSH
    elif m == "l":
        col = LAWN
    elif m == "d":
        col = DIRT
    elif m in ("i", "t", "b", "s"):
        col = MARSH
    elif m == "g" and cy < 6:
        col = FIELD_GOLD
    else:
        # the hills: gold, drier higher up; oak woodland and the redwood crest
        col = mix(GOLD, DRY, (cy - 150) / 90)
        wood = (m == "m")
        if m is None:
            wet = n3(cx, cz, 1 / 230.0, 3.7) > 0.12 and slope < 0.9 and 14 < cy < 240
            wood = wet
        south = cz < -300 and cy > 75
        if wood:
            col = mix(col, FOREST if south else WOOD, 0.75 if south else 0.6)
        elif south and cy > 110:
            col = mix(col, FOREST, 0.5)
        if slope > 0.75 and cy > 14:
            col = mix(col, OLIVE, 0.45)
        if slope > 1.4 and cy > 30:
            col = ROCK
    k = 1 + 0.035 * n3(cx, cz, 1 / 23.0, 11.0) + rng.uniform(-0.02, 0.02)
    return tuple(min(1.0, max(0.0, v * k)) for v in col), (m == "m") or (m is None and False)


# ------------------------------------------------------------------ faces
faces = []           # (a, b, c, colour, info)
for i in range(NZ - 1):
    for j in range(NX - 1):
        p00, p10, p01, p11 = P[i][j], P[i][j + 1], P[i + 1][j], P[i + 1][j + 1]
        m00, m10, m01, m11 = M[i][j], M[i][j + 1], M[i + 1][j], M[i + 1][j + 1]
        if (i + j) % 2 == 0:
            tris = [((p00, p10, p11), (m00, m10, m11)), ((p00, p11, p01), (m00, m11, m01))]
        else:
            tris = [((p00, p10, p01), (m00, m10, m01)), ((p10, p11, p01), (m10, m11, m01))]
        for (a, b, c), mats in tris:
            va, vb, vc = Vector(a), Vector(b), Vector(c)
            n = (vb - va).cross(vc - va)
            if n.length < 1e-6:
                continue
            n.normalize()
            if n.y < 0:
                n = -n
            cen = (va + vb + vc) / 3
            col, wood = face_colour(tuple(cen), tuple(n), list(mats))
            faces.append((a, b, c, col, dict(cen=cen, n=n, mats=mats)))

# ------------------------------------------------------------------ tiles
def tile_of(cx, cz):
    return int((cx - FIELD[0]) // TILE), int((cz - FIELD[2]) // TILE)


tiles = {}
for fc in faces:
    key = tile_of(fc[4]["cen"].x, fc[4]["cen"].z)
    tiles.setdefault(key, []).append(fc)

K.reset()
META = {}
objs = []
for (ti, tj), fl in sorted(tiles.items()):
    name = "LP_%d_%d" % (ti, tj)
    bm = bmesh.new()
    col_layer = bm.loops.layers.color.new("Col")
    for (a, b, c, col, info) in fl:
        vs = [bm.verts.new((-p[0], p[2], p[1])) for p in (a, b, c)]      # own vertices: flat shading
        f = bm.faces.new(vs)
        f.normal_update()
        if f.normal.z < 0:
            f.normal_flip()
        for loop in f.loops:
            loop[col_layer] = (col[0], col[1], col[2], 1.0)
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
    mins = [min(v.co[k] for v in me.vertices) for k in range(3)]
    maxs = [max(v.co[k] for v in me.vertices) for k in range(3)]
    cb = [(mins[k] + maxs[k]) / 2 for k in range(3)]
    sb = [maxs[k] - mins[k] for k in range(3)]
    META[name] = dict(c=(-cb[0], cb[2], cb[1]), s=(sb[0], sb[2], sb[1]), tris=len(me.polygons))
    objs.append(o)
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.export_scene.fbx(filepath=os.path.join(IMP, name + ".fbx"), use_selection=True, apply_unit_scale=True,
                             apply_scale_options="FBX_SCALE_ALL", global_scale=1.0, mesh_smooth_type="OFF",
                             use_mesh_modifiers=True, colors_type="SRGB", add_leaf_bones=False, bake_anim=False,
                             axis_forward="-Z", axis_up="Y")

# ------------------------------------------------------------------ the hill trees
def surface_point(a, b, c):
    r1, r2 = rng.random(), rng.random()
    if r1 + r2 > 1:
        r1, r2 = 1 - r1, 1 - r2
    return tuple(a[k] + r1 * (b[k] - a[k]) + r2 * (c[k] - a[k]) for k in range(3))


trees = []
for (a, b, c, col, info) in faces:
    cen, n = info["cen"], info["n"]
    if cen.y < 10 or n.y < 0.62 or flat_pad(cen.x, cen.z, 30) or bay(cen.x, cen.z):
        continue
    mats = [m for m in info["mats"] if m]
    m = max(set(mats), key=mats.count) if mats else None
    r = stretched(cen.x, cen.z)
    south = cen.z < -300 and cen.y > 75
    wood = (m == "m") or (m is None and n3(cen.x, cen.z, 1 / 230.0, 3.7) > 0.12 and 14 < cen.y < 240)
    near = r < 1250
    if wood and south:
        k = 1
        for _ in range(k):
            if rng.random() < (0.85 if near else 0.4):
                p = surface_point(a, b, c)
                if near:
                    trees.append((p[0], p[1], p[2], "LP_Redwood_" + rng.choice("AB"), rng.uniform(24, 34)))
                else:
                    trees.append((p[0], p[1], p[2], "LP_RedwoodGrove", rng.uniform(30, 40)))
    elif wood:
        if near:
            for _ in range(2):
                if rng.random() < 0.7:
                    p = surface_point(a, b, c)
                    trees.append((p[0], p[1], p[2], "LP_Oak_" + rng.choice("AB"), rng.uniform(12, 18)))
        elif rng.random() < 0.38:
            p = surface_point(a, b, c)
            trees.append((p[0], p[1], p[2], "LP_Grove", rng.uniform(18, 24)))
    elif near and rng.random() < 0.05:
        p = surface_point(a, b, c)
        trees.append((p[0], p[1], p[2], "LP_Oak_" + rng.choice("AB"), rng.uniform(11, 16)))

# ------------------------------------------------------------------ walkable triangles
walk = []
for (a, b, c, col, info) in faces:
    cen = info["cen"]
    if stretched(cen.x, cen.z) < SEAM + 20 and not (bay(cen.x, cen.z) and cen.y < WATER_Y + 0.6):
        walk.append((a, b, c))

# ------------------------------------------------------------------ data module
path = os.path.join(OUT, "LowPolyData.lua")
with open(path, "w", newline="\n") as f:
    f.write("-- generated by blender/lp_world.py (v4.1): the low-poly valley\n")
    f.write("return {\n\tfacet = %.0f, water = %.1f,\n\ttiles = {\n" % (S, WATER_Y))
    for k in sorted(META):
        mm = META[k]
        f.write("\t\t%s = { c = Vector3.new(%.2f, %.2f, %.2f), s = Vector3.new(%.2f, %.2f, %.2f) },  -- %d tris\n"
                % (k, *mm["c"], *mm["s"], mm["tris"]))
    f.write("\t},\n\t-- x, y, z, mesh, height\n\ttrees = {\n")
    for (x, y, z, kind, h) in trees:
        f.write("\t\t{ %.1f, %.1f, %.1f, \"%s\", %.1f },\n" % (x, y, z, kind, h))
    f.write("\t},\n\t-- the walkable facets, 9 numbers each: collision is built from these exactly\n\twalk = {\n")
    for (a, b, c) in walk:
        f.write("\t\t%.1f,%.1f,%.1f, %.1f,%.1f,%.1f, %.1f,%.1f,%.1f,\n" % (*a, *b, *c))
    f.write("\t},\n}\n")

total = sum(mm["tris"] for mm in META.values())
kinds = {}
for t in trees:
    kinds[t[3]] = kinds.get(t[3], 0) + 1
print("LP_WORLD tiles %d tris %d faces %d trees %d walk %d kinds %s" % (len(META), total, len(faces), len(trees), len(walk), kinds))

# ------------------------------------------------------------------ preview (from the campus, looking north)
scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "VERTEX"
scene.display.shading.show_shadows = False
scene.render.resolution_x, scene.render.resolution_y = 1600, 700
cam_data = bpy.data.cameras.new("Cam")
cam_data.lens = 22
cam_data.clip_end = 20000
cam = bpy.data.objects.new("Cam", cam_data)
scene.collection.objects.link(cam)
eye = Vector((40, -60 * -1, 0))
# Roblox eye (-40, 70, -60) looking at (100, 110, 700) -> Blender (-x, z, y)
e = Vector((40.0, -60.0, 70.0))
t = Vector((-100.0, 700.0, 110.0))
cam.location = e
cam.rotation_euler = (t - e).to_track_quat("-Z", "Y").to_euler()
scene.camera = cam
scene.render.filepath = os.path.join(OUT, "lp_world_preview.png")
bpy.ops.render.render(write_still=True)
