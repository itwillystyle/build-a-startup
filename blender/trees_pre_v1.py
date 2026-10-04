"""The valley's trees, modelled instead of stacked: a Canary date palm, two
California live oaks, a coast redwood, a blue gum eucalyptus and an orchard
tree. Organic silhouettes, painted gradients (lighter crowns, darker
undersides), one mesh each, triangle-budgeted because there are ~400 trees
on the map. Run: blender -b --python trees.py"""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
from mathutils import Vector, noise
import svkit as K

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
os.makedirs(OUT, exist_ok=True)


def tube(name, pts, radii, sides=10, cap=True):
    """Sweep circles along a polyline (points = Vectors), radius per point."""
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        a = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
        u = d.cross(a).normalized()
        v = d.cross(u).normalized()
        ring = [bm.verts.new(p + (u * math.cos(2 * math.pi * k / sides) + v * math.sin(2 * math.pi * k / sides)) * radii[i]) for k in range(sides)]
        rings.append(ring)
    for r in range(len(rings) - 1):
        for k in range(sides):
            j = (k + 1) % sides
            bm.faces.new((rings[r][k], rings[r][j], rings[r + 1][j], rings[r + 1][k]))
    if cap:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return K.mesh_obj(name, bm)


def blob_canopy(name, centers, voxel=0.5, lumps=0.55, target_tris=1200, seed=1):
    """Merge spheres into one lumpy canopy: remesh, displace, smooth, decimate."""
    objs = []
    for (c, r) in centers:
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=r, location=c)
        objs.append(bpy.context.active_object)
    o = K.join(objs, name)
    m = o.modifiers.new("Remesh", "REMESH"); m.mode = "VOXEL"; m.voxel_size = voxel
    # big soft lumps, then small leafy clumps on top of them; light smoothing so
    # the clumps survive (six smoothing passes turned the first oak into a balloon)
    tex = bpy.data.textures.new(name + "Tex", "CLOUDS"); tex.noise_scale = 1.9; tex.noise_depth = 2
    d = o.modifiers.new("Displace", "DISPLACE"); d.texture = tex; d.strength = lumps * 2.2; d.mid_level = 0.45
    tex2 = bpy.data.textures.new(name + "Tex2", "VORONOI"); tex2.noise_scale = 0.9
    d2 = o.modifiers.new("Clumps", "DISPLACE"); d2.texture = tex2; d2.strength = lumps * 0.9; d2.mid_level = 0.3
    s = o.modifiers.new("Smooth", "SMOOTH"); s.factor = 0.6; s.iterations = 2
    K.apply_mods(o)
    tri = K.tris(o)
    if tri > target_tris:
        dec = o.modifiers.new("Dec", "DECIMATE"); dec.ratio = target_tris / tri
        K.apply_mods(o)
    return o


def canopy_paint(base, top, under, seed=0):
    def f(p, n):
        h = n.z * 0.5 + 0.5
        k = noise.noise(p * 0.35 + Vector((seed, seed, seed))) * 0.12
        c = [under[i] + (top[i] - under[i]) * h for i in range(3)]
        c = [max(0, min(1, x * (0.92 + k) + (base[i] - x) * 0.25)) for i, x in enumerate(c)]
        return tuple(c)
    return f


# ---------------------------------------------------------------- PALM
def palm(name, seed, height=23, lean=2.2):
    random.seed(seed)
    parts = []
    n = 26
    pts, radii = [], []
    for i in range(n + 1):
        t = i / n
        pts.append(Vector((lean * t ** 1.7, 0.4 * math.sin(t * 2.5), height * t)))
        r = 0.95 * (1 - 0.33 * t) + (0.35 if t < 0.06 else 0) + (0.06 if i % 2 == 0 else 0)   # base flare, leaf-scar rings
        radii.append(r)
    trunk = tube("Trunk", pts, radii, sides=14)
    RING_A, RING_B = K.rgb(152, 120, 88), K.rgb(120, 94, 68)
    K.paint(trunk, lambda p, nn: tuple(c * (0.85 + 0.2 * (nn.z * 0.5 + 0.5)) for c in (RING_A if int(p.z / 0.9) % 2 == 0 else RING_B)))
    parts.append(trunk)
    top = pts[-1]
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.25, location=top + Vector((0, 0, 0.2)))
    knob = bpy.context.active_object
    K.paint(knob, K.shaded(K.rgb(118, 110, 64))); parts.append(knob)
    # fronds: arched, V-folded, serrated leaves; young ones stand up, old ones droop
    fronds = 13
    for f in range(fronds):
        a = 2 * math.pi * f / fronds + random.uniform(-0.15, 0.15)
        tier = f % 3
        elev = [0.85, 0.35, -0.15][tier] + random.uniform(-0.1, 0.1)
        L = random.uniform(8.5, 10.5) * (0.85 if tier == 0 else 1)
        W = random.uniform(1.5, 1.9)
        droop = [0.25, 0.55, 0.8][tier]
        dirh = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-math.sin(a), math.cos(a), 0))
        bm = bmesh.new()
        seg = 14
        rows = []
        for k in range(seg + 1):
            s = k / seg
            base = top + dirh * (L * s * math.cos(elev)) + Vector((0, 0, L * s * math.sin(elev) - droop * L * s * s))
            w = W * (math.sin(math.pi * min(1, s * 1.05)) ** 0.7) * (1.18 if k % 2 == 0 else 0.82)
            fold = 0.3 * w
            rows.append((bm.verts.new(base + side * w - Vector((0, 0, fold))), bm.verts.new(base), bm.verts.new(base - side * w - Vector((0, 0, fold)))))
        for k in range(seg):
            l0, c0, r0 = rows[k]; l1, c1, r1 = rows[k + 1]
            bm.faces.new((l0, c0, c1, l1)); bm.faces.new((c0, r0, r1, c1))
        o = K.mesh_obj("Frond", bm)
        sol = o.modifiers.new("S", "SOLIDIFY"); sol.thickness = 0.07
        K.apply_mods(o)
        dark, light = K.rgb(56, 108, 50), K.rgb(128, 170, 74)
        def fpaint(p, nn, top=top, L=L):
            s = min(1, (p - top).length / L)
            c = [dark[i] + (light[i] - dark[i]) * s for i in range(3)]
            k = 0.78 + 0.3 * (nn.z * 0.5 + 0.5)
            return tuple(min(1, x * k) for x in c)
        K.paint(o, fpaint)
        parts.append(o)
    obj = K.join(parts, name)
    K.smooth(obj, 50)
    return obj


# ---------------------------------------------------------------- LIVE OAK
def oak(name, seed, scale=1.0, tris=1100):
    random.seed(seed)
    parts = []
    trunk = tube("Trunk", [Vector((0, 0, 0)), Vector((0.2, 0.1, 2.2)), Vector((0.1, 0.3, 4.0))], [1.05, 0.8, 0.7], sides=10)
    parts.append(trunk)
    centers = [(Vector((0, 0, 7.0)) * scale, 4.3 * scale)]
    for k in range(3):
        a = 2 * math.pi * k / 3 + random.uniform(-0.4, 0.4)
        end = Vector((math.cos(a) * 3.6, math.sin(a) * 3.6, 5.6 + random.uniform(-0.4, 0.6))) * scale
        limb = tube("Limb", [Vector((0.1, 0.3, 3.6)), (Vector((0.1, 0.3, 3.6)) + end) / 2 + Vector((0, 0, 0.4)), end], [0.55, 0.42, 0.3], sides=8)
        parts.append(limb)
        centers.append((end + Vector((0, 0, 1.2 * scale)), random.uniform(3.2, 3.8) * scale))
    for k in range(3):
        a = random.uniform(0, 2 * math.pi)
        centers.append((Vector((math.cos(a) * 2.5, math.sin(a) * 2.5, 8.5)) * scale, random.uniform(2.6, 3.2) * scale))
    bark = K.rgb(92, 72, 54)
    for p in parts:
        K.paint(p, K.shaded(bark))
    can = blob_canopy("Canopy", centers, voxel=0.55 * scale, lumps=0.7 * scale, target_tris=tris, seed=seed)
    K.paint(can, canopy_paint(K.rgb(84, 118, 62), K.rgb(142, 176, 88), K.rgb(46, 72, 44), seed))
    obj = K.join(parts + [can], name)
    K.smooth(obj, 48)
    return obj


# ---------------------------------------------------------------- REDWOOD
def redwood(name, seed, height=27):
    random.seed(seed)
    trunk = K.lathe("Trunk", [(1.2, 0), (1.0, 1.5), (0.8, 6), (0.45, height * 0.8), (0.2, height)], 10)
    K.paint(trunk, K.shaded(K.rgb(122, 66, 46)))
    parts = [trunk]
    tiers = 7
    for k in range(tiers):
        t = k / tiers
        z0 = height * (0.28 + 0.66 * t)
        r = 4.6 * (1 - t * 0.78)
        h = 5.2 * (1 - t * 0.35)
        prof = [(0.3, z0), (r, z0 + 0.6), (r * 0.82, z0 + 1.0), (0.2, z0 + h)]
        o = K.lathe("Tier", prof, 12)
        # ragged edge: push alternate rim verts out/in
        for i, v in enumerate(o.data.vertices):
            if abs(v.co.z - (z0 + 0.6)) < 0.05:
                f = 1.18 if i % 2 == 0 else 0.88
                v.co.x *= f; v.co.y *= f; v.co.z -= random.uniform(0, 0.5)
        dark, light = K.rgb(38, 68, 46), K.rgb(70, 108, 66)
        K.paint(o, lambda p, n, zz=z0: tuple(min(1, (dark[i] + (light[i] - dark[i]) * (n.z * 0.5 + 0.5))) for i in range(3)))
        parts.append(o)
    obj = K.join(parts, name)
    K.smooth(obj, 45)
    return obj


# ---------------------------------------------------------------- EUCALYPTUS
def eucalypt(name, seed, height=28):
    random.seed(seed)
    parts = []
    trunk = tube("Trunk", [Vector((0, 0, 0)), Vector((0.4, 0.2, height * 0.35)), Vector((0.1, 0.5, height * 0.62))], [1.0, 0.7, 0.5], sides=10)
    parts.append(trunk)
    centers = []
    for k in range(4):
        a = 2 * math.pi * k / 4 + random.uniform(-0.5, 0.5)
        end = Vector((math.cos(a) * 3.2, math.sin(a) * 3.2, height * random.uniform(0.66, 0.9)))
        br = tube("Branch", [Vector((0.1, 0.5, height * 0.55)), end], [0.4, 0.22], sides=7)
        parts.append(br)
        centers.append((end + Vector((0, 0, 1.4)), random.uniform(2.6, 3.4)))
    centers.append((Vector((0.2, 0.4, height * 0.95)), 3.0))
    pale = K.rgb(206, 196, 178)
    for p in parts:
        K.paint(p, lambda q, n: tuple(c * (0.8 + 0.25 * (0.5 + 0.5 * math.sin(q.z * 1.7 + q.x))) for c in pale))
    can = blob_canopy("Canopy", centers, voxel=0.55, lumps=0.9, target_tris=1000, seed=seed)
    K.paint(can, canopy_paint(K.rgb(104, 128, 104), K.rgb(140, 162, 132), K.rgb(70, 92, 76), seed))
    obj = K.join(parts + [can], name)
    K.smooth(obj, 60)
    return obj


K.reset()
assets = []
specs = [
    ("Palm_A", lambda: palm("Palm_A", 3, 23, 2.2)),
    ("Palm_B", lambda: palm("Palm_B", 7, 20, -1.6)),
    ("Oak_A", lambda: oak("Oak_A", 11, 1.0, 1100)),
    ("Oak_B", lambda: oak("Oak_B", 23, 1.15, 1200)),
    ("Redwood_A", lambda: redwood("Redwood_A", 5, 27)),
    ("Eucalypt_A", lambda: eucalypt("Eucalypt_A", 9, 28)),
    ("Orchard_A", lambda: oak("Orchard_A", 31, 0.55, 500)),
]
x = 0
for (nm, fn) in specs:
    o = fn()
    print(nm, "tris", K.tris(o))
    K.export(os.path.join(OUT, nm + ".fbx"), [o])     # at the origin: the base is the pivot
    o.location = (x, 0, 0)                              # then spaced out for the preview only
    assets.append(o)
    x += 18
K.preview(os.path.join(OUT, "trees.png"), assets, size=(1600, 600), elev=8, azim=0, cam_dist=150, target=Vector((54, 0, 11)))
print("EXPORTED")
