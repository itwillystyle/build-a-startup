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
DATA_ONLY = os.environ.get("LP_DATA_ONLY") == "1"   # tiles already imported: write LowPolyData.lua only
FIX = os.environ.get("LP_FIX") == "1"               # export only the tiles that changed, to IMPORT_LP_FIX
FIX_DIR = os.path.join(OUT, "IMPORT_LP_FIX")
FIXED = []
if FIX:
    os.makedirs(FIX_DIR, exist_ok=True)
    for f_ in os.listdir(FIX_DIR):
        os.remove(os.path.join(FIX_DIR, f_))
    DATA_ONLY = True
os.makedirs(IMP, exist_ok=True)
if not DATA_ONLY:
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
    _rows = [line.strip().split(",") for line in f if line.strip()]
    MAT = [[c[-1] for c in row] for row in _rows]
    SH = [[float(c[:-1]) for c in row] for row in _rows]     # the terrain's own height per sample


def mat_at(x, z):
    i, j = int(round((z - sz0) / sstep)), int(round((x - sx0) / sstep))
    if 0 <= i < len(MAT) and 0 <= j < len(MAT[0]):
        return MAT[i][j]
    return None


def sample_h(x, z):
    i, j = int(round((z - sz0) / sstep)), int(round((x - sx0) / sstep))
    if 0 <= i < len(SH) and 0 <= j < len(SH[0]):
        return SH[i][j]
    return None


# every place something is built (SiliconCore's flat rects)
#
# v9 THE CAMPUS IS A RING. The old list held two rows of three plots at
# (+-360, +-150), a straight road 1520 studs wide across the middle, and two
# cross streets. All four are gone: the plots are on a ring at r=336, the park
# is in the middle, and the ring roads are at r=208 and r=596.
#
# This matters more than it looks. The valley the game actually renders is the
# BAKED low-poly data this script writes -- ValleyGen's `basin` and `rim`
# options only affect the heightmap path, which is not the one in use. So the
# hills move when this list moves and at no other time. Leave it stale and the
# outer ring road sits on a hillside 120 studs up, which is exactly what
# happened the first time.
RING_R_PLOT = 336.0
RING_R_IN, RING_R_DIST, RING_R_OUT = 208.0, 452.0, 596.0
RING_PARK = 162.0

FLAT = []
# the six plots, on the ring
for i in range(6):
    a = math.radians(30 + i * 60)
    FLAT.append((math.cos(a) * RING_R_PLOT, math.sin(a) * RING_R_PLOT, 250, 250))
# the central park
FLAT.append((0.0, 0.0, 2 * RING_PARK + 90, 2 * RING_PARK + 90))
# the east approach out to downtown, downtown itself, and the rail corridor
FLAT += [(760.0, 0.0, 820, 74), (780.0, 0.0, 320, 200),
         ((-915 + 648) / 2, -330, 648 + 915, 40)]

# The three ring bands are circles, not rectangles, so they get their own test
# rather than being approximated by dozens of rects (which would also make
# flat_pad O(vertices x rects) and slow the bake down).
RINGS = [(RING_R_IN - 62, RING_R_IN + 62),
         (RING_R_DIST - 96, RING_R_DIST + 96),
         (RING_R_OUT - 62, RING_R_OUT + 62)]
MOUNDS = [(648 - 18, -330, 22, 1), (-915 + 18, -330, 22, -1)]   # the rail tunnel hills (x0, z, halfW, dir)
FLAT_V1 = list(FLAT)
# v4.1b: Moffett Field -- dry flat land for Hangar One by the ponds (it stood in water)
FLAT.append((-865.0, 150.0, 130.0, 220.0))


def in_mound(x, z):
    for (x0, mz, hw, d) in MOUNDS:
        if d * (x - x0) > -4 and abs(z - mz) < hw + 30:
            return True
    return False


def flat_pad(x, z, pad, rects=None):
    for (fx, fz, fw, fd) in (rects or FLAT):
        if abs(x - fx) <= fw / 2 + pad and abs(z - fz) <= fd / 2 + pad:
            return True
    # the campus rings. Checked for the live list only: FLAT_V1 is the pre-v4.1
    # snapshot some callers pass to keep the Bay and the old tree placement
    # exactly as they were.
    if rects is None or rects is FLAT:
        r = math.hypot(x, z)
        for (r0, r1) in RINGS:
            if r0 - pad <= r <= r1 + pad:
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
CH = [[False] * NX for _ in range(NZ)]      # height differs from the first (imported) build


def old_y(x, z, m):
    # the v4.1 rule the imported tiles were built with (kept only to find what changed)
    y = h_at(x, z)
    if flat_pad(x, z, S * 0.9, FLAT_V1) and not in_mound(x, z):
        y = 0.0
    if bay(x, z) and not flat_pad(x, z, 6, FLAT_V1):
        if m == "s" or (m is None and y < 1.5):
            y = BED_Y
        elif m in ("i", "t", "b", "d") and y < 1.5:
            y = WATER_Y - 0.25
    return y


for i in range(NZ):
    for j in range(NX):
        edge = i in (0, NZ - 1) or j in (0, NX - 1)
        x = xs[j] + (0 if edge else rng.uniform(-JIT, JIT) * S)
        z = zs[i] + (0 if edge else rng.uniform(-JIT, JIT) * S)
        y = h_at(x, z)
        m = mat_at(x, z)
        if bay(x, z):
            # v4.1b: round the Bay the eroded field (mountains.py) had raised the salt
            # marsh into a 7-12 stud plateau; the terrain's own samples are the truth
            if m == "s" or (m is None and y < 1.5):
                y = BED_Y                        # open water: the bed, under the sheet
            elif m in ("i", "t", "b", "d"):
                y = WATER_Y - 0.25               # the marsh: the ponds sit on it as parts
            elif sample_h(x, z) is not None:
                y = sample_h(x, z)               # the low hills round the Bay, as the terrain had them
        if flat_pad(x, z, S * 0.9) and not in_mound(x, z):
            y = 0.0
        P[i][j] = (x, y, z)
        M[i][j] = m
        CH[i][j] = abs(y - old_y(x, z, m)) > 0.01

# ------------------------------------------------------------------ the slope limiter
# v4.1c: measured in game, 88 vertices stood 18-82 studs above all 8 neighbours:
# a flat zone forced to 0 out to 36 studs, then the next vertex at its full
# height -- one facet from 0 to 146 beside downtown, a pale pyramid. No vertex
# may rise more than MAX_RISE x distance above ANY neighbour. Only ever lowers,
# never raises; flat zones and water stay put. Real slopes here are well under.
MAX_RISE = 1.1


def limit_slopes():
    fixed = set()
    for i in range(NZ):
        for j in range(NX):
            x, y, z = P[i][j]
            if flat_pad(x, z, S * 0.9) or y <= WATER_Y:
                fixed.add((i, j))
    for _ in range(12):
        moved = 0
        for i in range(NZ):
            for j in range(NX):
                if (i, j) in fixed:
                    continue
                x, y, z = P[i][j]
                cap = y
                for di in (-1, 0, 1):
                    for dj in (-1, 0, 1):
                        if (di or dj) and 0 <= i + di < NZ and 0 <= j + dj < NX:
                            nx_, ny_, nz_ = P[i + di][j + dj]
                            d = math.hypot(x - nx_, z - nz_)
                            cap = min(cap, ny_ + MAX_RISE * d)
                if cap < y - 0.01:
                    P[i][j] = (x, cap, z)
                    moved += 1
        if moved == 0:
            break


limit_slopes()

# v4.2: data goes straight into the Rojo source tree (Rojo syncs it to Studio)
HERE_LP = os.path.dirname(os.path.abspath(__file__))
import gamedir  # noqa: E402

LP_DATA_DIR = os.path.join(gamedir.server_dir(HERE_LP), "LowPolyData")

PREV = None
_prev_dir = LP_DATA_DIR
if os.path.isdir(_prev_dir):
    import re as _re
    _nums = []
    for _n in sorted(f_ for f_ in os.listdir(_prev_dir) if f_.startswith("Grid")):
        _txt = open(os.path.join(_prev_dir, _n)).read()
        _txt = _txt.split("return {", 1)[1]
        _nums += [float(v) for v in _re.findall(r"-?\d+\.?\d*", _txt)]
    if len(_nums) == NX * NZ * 3:
        PREV = _nums
for i in range(NZ):
    for j in range(NX):
        if PREV is not None:
            k = (i * NX + j) * 3
            CH[i][j] = abs(P[i][j][1] - PREV[k + 1]) > 0.01
print("LP_SLOPE vertices changed vs imported: %d (prev data %s)" % (sum(1 for i in range(NZ) for j in range(NX) if CH[i][j]), "found" if PREV else "missing"))

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
    m = max(sorted(set(m for m in mats if m)), key=mats.count) if any(mats) else None
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
        changed = CH[i][j] or CH[i][j + 1] or CH[i + 1][j] or CH[i + 1][j + 1]
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
            faces.append((a, b, c, col, dict(cen=cen, n=n, mats=mats, changed=changed)))

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
    if FIX:
        # re-export ONLY the tiles whose facets changed since the first import
        if not any(fc[4]["changed"] for fc in fl):
            continue
        FIXED.append(name)
        target = os.path.join(FIX_DIR, name + ".fbx")
    elif DATA_ONLY:
        continue
    else:
        target = os.path.join(IMP, name + ".fbx")
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.export_scene.fbx(filepath=target, use_selection=True, apply_unit_scale=True,
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
    m = max(sorted(set(mats)), key=mats.count) if mats else None
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
    elif near and cen.y > 14 and n3(cen.x, cen.z, 1 / 190.0, 7.1) > 0.18:
        # v4.1c: oak groves on the golden slopes too (the terrain's own woodland
        # patches were sparse; the mock's groves are what read as California)
        for _ in range(2):
            if rng.random() < 0.55:
                p = surface_point(a, b, c)
                trees.append((p[0], p[1], p[2], "LP_Oak_" + rng.choice("AB"), rng.uniform(11, 17)))
    elif near and rng.random() < 0.06:
        p = surface_point(a, b, c)
        trees.append((p[0], p[1], p[2], "LP_Oak_" + rng.choice("AB"), rng.uniform(11, 16)))

# ------------------------------------------------------------------ the salt ponds
# ValleyGen.classify's own rule (bayWeight > 0.5, h < 1.5, east of the open water),
# on its own 46 x 40 grid with 4-stud levees: crisp rectangles, laid as parts in Lua
def smooth01(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def bay_weight(x, z):
    return smooth01((-x - 640) / 150) * (1 - smooth01((abs(z) - 320) / 220))


ponds = []
for i in range(int((-805 + 2000) // 46), int((-640 + 2000) // 46) + 1):
    for j in range(int((-560 + 2000) // 40), int((560 + 2000) // 40) + 1):
        x0p, z0p = i * 46 - 2000, j * 40 - 2000
        cx, cz = x0p + 25, z0p + 22
        if cx < -805 or cx > -640 or flat_pad(cx, cz, 4):
            continue
        if bay_weight(cx, cz) > 0.5 and mat_at(cx, cz) in ("i", "t", "b", "d"):
            ponds.append((cx, cz, ((i * 7 + j * 3) % 4) + 1))

# ------------------------------------------------------------------ data module
# A ModuleScript source is capped at 200,000 characters (measured: the one-file
# version was 478 K and Studio refused it). So: a small main module that
# assembles child modules -- the trees and the vertex grid -- each under ~150 K.
DATA = LP_DATA_DIR
os.makedirs(DATA, exist_ok=True)
for f_ in os.listdir(DATA):
    os.remove(os.path.join(DATA, f_))
CAP = 150000


def chunks(lines, prefix):
    """Write lines into as many 'return { ... }' modules as the cap needs."""
    names, buf, size, k = [], [], 0, 1
    def flush():
        nonlocal buf, size, k
        name = "%s%d" % (prefix, k)
        with open(os.path.join(DATA, name + ".lua"), "w", newline="\n") as f:
            f.write("-- generated by blender/lp_world.py (v4.1): part of LowPolyData\nreturn {\n")
            f.write("".join(buf))
            f.write("}\n")
        names.append(name)
        buf, size, k = [], 0, k + 1
    for line in lines:
        if size + len(line) > CAP and buf:
            flush()
        buf.append(line)
        size += len(line)
    if buf:
        flush()
    return names


tree_mods = chunks(["\t{ %.1f, %.1f, %.1f, \"%s\", %.1f },\n" % t for t in trees], "Trees")
grid_mods = chunks(["\t" + ",".join("%.1f,%.2f,%.1f" % P[i][j] for j in range(NX)) + ",\n" for i in range(NZ)], "Grid")

path = os.path.join(DATA, "init.lua")  # Rojo: a folder with init.lua = the ModuleScript, the rest its children
with open(path, "w", newline="\n") as f:
    f.write("--[[ generated by blender/lp_world.py (v4.1): the low-poly valley.\n")
    f.write("Children (ModuleScripts): %s -- a source is capped at 200,000\n" % ", ".join(tree_mods + grid_mods))
    f.write("characters, so the trees and the vertex grid are split across them. ]]\n")
    f.write("local d = {\n\tfacet = %.0f, water = %.1f,\n\ttiles = {\n" % (S, WATER_Y))
    for k in sorted(META):
        mm = META[k]
        f.write("\t\t%s = { c = Vector3.new(%.2f, %.2f, %.2f), s = Vector3.new(%.2f, %.2f, %.2f) },  -- %d tris\n"
                % (k, *mm["c"], *mm["s"], mm["tris"]))
    f.write("\t},\n\t-- the salt ponds: centre x, centre z, colour 1-4 (46 x 40 cells, 4-stud levees)\n\tponds = {\n")
    for (x, z, k) in ponds:
        f.write("\t\t{ %.1f, %.1f, %d },\n" % (x, z, k))
    f.write("\t},\n}\n")
    f.write("-- x, y, z, mesh, height\nd.trees = {}\n")
    f.write("for _, n in ipairs({ %s }) do\n" % ", ".join('"%s"' % n for n in tree_mods))
    f.write("\tfor _, t in ipairs(require(script:WaitForChild(n))) do table.insert(d.trees, t) end\nend\n")
    f.write("-- the exact faceted surface: row-major (z rows, x columns), x,y,z per vertex.\n")
    f.write("-- cell (i, j) splits along p00-p11 when (i + j) is even, else along p10-p01\n")
    f.write("local v = {}\n")
    f.write("for _, n in ipairs({ %s }) do\n" % ", ".join('"%s"' % n for n in grid_mods))
    f.write("\tfor _, x in ipairs(require(script:WaitForChild(n))) do v[#v + 1] = x end\nend\n")
    f.write("d.grid = { nx = %d, nz = %d, x0 = %.1f, z0 = %.1f, S = %.1f, v = v }\n" % (NX, NZ, FIELD[0], FIELD[2], S))
    f.write("return d\n")
print("LP_DATA modules " + " ".join(["LowPolyData"] + tree_mods + grid_mods))

total = sum(mm["tris"] for mm in META.values())
kinds = {}
for t in trees:
    kinds[t[3]] = kinds.get(t[3], 0) + 1
print("LP_WORLD tiles %d tris %d faces %d trees %d ponds %d kinds %s" % (len(META), total, len(faces), len(trees), len(ponds), kinds))
if FIX:
    print("LP_FIX tiles " + " ".join(FIXED))
if DATA_ONLY:
    raise SystemExit(0)

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
