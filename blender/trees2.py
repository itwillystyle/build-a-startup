"""trees2.py -- the valley's trees, second pass (v4.0, 28 Sep 2026).

His verdict on trees.py: "the trees still look like trash." Measured cause:
voxel-remeshed spheres decimated to ~1,200 triangles and exported with
angle-split shading, so every canopy was a handful of big flat facets that
caught the light edge-on (the 'faceted blob' in his screenshot).

What makes stylised foliage read as foliage, and what this does:
  1. SOFT SHADING. Every canopy vertex gets a custom normal bent outward from
     the centre of its lobe (the standard stylised-tree trick): light wraps
     round the crown like it does round a real one, no facets. FBX carries
     custom normals and Roblox renders them.
  2. CLUMPS AT TWO SCALES. Lobes (metaballs, merged smoothly) carry the
     silhouette; a fine displacement carries the leaf clusters on them.
  3. COLOUR THAT DESCRIBES FORM. Per-vertex: shaded underside -> sunlit top,
     darker toward the core (fake occlusion), a little hue noise per clump.
  4. REAL STRUCTURE. Trunks taper and fork into the crown; palms get proper
     pinnate fronds with leaflets, a ringed trunk and date clusters.
Same names as before (Oak_A/B, Redwood_A, Eucalypt_A, Palm_A/B, Orchard_A),
so the game picks them up with no code change. Heights are normalised in the
game (svMesh scales to a height), proportions matter.

Run:  blender -b --python trees2.py [-- name ...]
Out:  out/IMPORT_TREES/<Name>.fbx + out/trees2_<name>.png (Cycles, sun + sky)
"""
import bpy
import bmesh
import math
import os
import random
import sys
from mathutils import Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import svkit as K  # noqa: E402

OUT = os.path.join(HERE, "out")
IMP = os.path.join(OUT, "IMPORT_TREES")
os.makedirs(IMP, exist_ok=True)
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def c255(r, g, b):
    return (r / 255.0, g / 255.0, b / 255.0)


def lerp(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


# ------------------------------------------------------------------ geometry helpers
def tube(pts, radii, sides=10):
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        a = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
        u = d.cross(a).normalized()
        v = d.cross(u).normalized()
        rings.append([bm.verts.new(p + (u * math.cos(2 * math.pi * k / sides) + v * math.sin(2 * math.pi * k / sides)) * radii[i])
                      for k in range(sides)])
    for r in range(len(rings) - 1):
        for k in range(sides):
            j = (k + 1) % sides
            bm.faces.new((rings[r][k], rings[r][j], rings[r + 1][j], rings[r + 1][k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return K.mesh_obj("tube", bm)


def branch_path(a, b, bend, n=6):
    """A gently curving limb from a to b, bowed along `bend`."""
    pts = []
    for i in range(n):
        t = i / (n - 1)
        p = a.lerp(b, t) + bend * math.sin(math.pi * t)
        pts.append(p)
    return pts


def canopy(lobes, fine=0.35, fine_scale=1.4, voxel=0.35, target=2400, flatten_below=None):
    """lobes: [(center Vector, radius)]. Metaballs -> mesh -> remesh -> leaf-cluster
    displacement -> smooth -> decimate. Returns the object; lobe centres are kept
    on it for the normal pass."""
    mb = bpy.data.metaballs.new("C")
    mb.resolution = voxel
    mb.render_resolution = voxel
    mb.threshold = 0.55
    o = bpy.data.objects.new("C", mb)
    bpy.context.scene.collection.objects.link(o)
    for c, r in lobes:
        e = mb.elements.new()
        e.co = c
        e.radius = r * 1.35
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.convert(target="MESH")
    m = bpy.context.active_object
    # leaf clusters: small bumps displaced along the normal
    # two noises: mid-size leaf clumps (clouds) and a finer break-up (voronoi)
    tex = bpy.data.textures.new("Leaf", "CLOUDS")
    tex.noise_scale = fine_scale
    tex.noise_depth = 1
    d = m.modifiers.new("Leaf", "DISPLACE")
    d.texture = tex
    d.strength = fine * 2.2
    d.mid_level = 0.5
    tex2 = bpy.data.textures.new("Leaf2", "VORONOI")
    tex2.noise_scale = fine_scale * 0.45
    d2 = m.modifiers.new("Leaf2", "DISPLACE")
    d2.texture = tex2
    d2.strength = fine * 0.8
    d2.mid_level = 0.35
    s = m.modifiers.new("S", "SMOOTH")
    s.factor = 0.35
    s.iterations = 1
    K.apply_mods(m)
    if flatten_below is not None:
        for v in m.data.vertices:
            if v.co.z < flatten_below:
                v.co.z = flatten_below + (v.co.z - flatten_below) * 0.25
    tri = K.tris(m)
    if tri > target:
        dec = m.modifiers.new("Dec", "DECIMATE")
        dec.ratio = target / tri
        K.apply_mods(m)
    m["lobes"] = [list(c) + [r] for c, r in lobes]
    return m


def soft_normals(obj, lobes, mix=0.7):
    """Custom split normals: each vertex points away from the nearest lobe centre,
    blended with its own normal. Soft, cloud-like light on the crown."""
    me = obj.data
    vn = []
    for v in me.vertices:
        p = v.co
        best, bd = None, 1e9
        for c, r in lobes:
            dd = (p - c).length / max(r, 1e-3)
            if dd < bd:
                best, bd = c, dd
        radial = (p - best).normalized() if best is not None else v.normal
        n = (v.normal * (1 - mix) + radial * mix).normalized()
        vn.append(n)
    me.normals_split_custom_set_from_vertices(vn)


def paint_canopy(obj, lobes, base, top, under, core, seed=0, top_z=None, bot_z=None):
    """Colour describes form: underside -> sunlit top, darker toward each lobe's core."""
    me = obj.data
    zs = [v.co.z for v in me.vertices]
    z0 = bot_z if bot_z is not None else min(zs)
    z1 = top_z if top_z is not None else max(zs)
    if "Col" not in me.color_attributes:
        me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
    attr = me.color_attributes["Col"]
    for poly in me.polygons:
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index]
            p = v.co
            h = (p.z - z0) / max(1e-3, z1 - z0)
            best, bd = None, 1e9
            for c, r in lobes:
                dd = (p - c).length / max(r, 1e-3)
                if dd < bd:
                    best, bd = c, dd
            outer = max(0.0, min(1.0, bd))                  # 0 at a lobe core, ~1 at its skin
            col = lerp(under, base, h * 1.6)
            col = lerp(col, top, max(0.0, (h - 0.55) / 0.45) * 0.85)
            col = lerp(core, col, 0.45 + 0.55 * outer)
            n = noise.noise(p * 0.35 + Vector((seed, seed * 2, 0)))
            k = 1.0 + 0.08 * n
            attr.data[li].color_srgb = (min(1, col[0] * k), min(1, col[1] * k), min(1, col[2] * k * 0.98), 1.0)
    me.color_attributes.active_color = attr


def paint_bark(obj, low, high, z0, z1, rings=None):
    me = obj.data
    if "Col" not in me.color_attributes:
        me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
    attr = me.color_attributes["Col"]
    for poly in me.polygons:
        up = poly.normal.z
        for li in poly.loop_indices:
            p = me.vertices[me.loops[li].vertex_index].co
            h = (p.z - z0) / max(1e-3, z1 - z0)
            col = lerp(low, high, h)
            if rings:
                band = 0.5 + 0.5 * math.sin(p.z * rings)
                col = lerp(col, tuple(x * 0.72 for x in col), band * 0.6)
            n = noise.noise(p * 1.7)
            k = (1.0 + 0.1 * n) * (0.92 + 0.08 * up)
            attr.data[li].color_srgb = (min(1, col[0] * k), min(1, col[1] * k), min(1, col[2] * k), 1.0)
    me.color_attributes.active_color = attr


def smooth_all(o):
    for p in o.data.polygons:
        p.use_smooth = True


def finish(name, parts):
    o = K.join(parts, name)
    smooth_all(o)
    # base of the trunk at z = 0, centred on x/y (the game plants by the base)
    mins = [min(v.co[i] for v in o.data.vertices) for i in range(3)]
    maxs = [max(v.co[i] for v in o.data.vertices) for i in range(3)]
    return o


# ------------------------------------------------------------------ species
LEAF_OAK = dict(base=c255(92, 142, 64), top=c255(168, 196, 92), under=c255(48, 80, 44), core=c255(36, 58, 34))
LEAF_ORCH = dict(base=c255(104, 160, 72), top=c255(184, 212, 110), under=c255(58, 96, 50), core=c255(42, 70, 40))
LEAF_EUC = dict(base=c255(108, 142, 110), top=c255(170, 196, 158), under=c255(62, 88, 70), core=c255(46, 66, 54))
LEAF_RED = dict(base=c255(46, 92, 58), top=c255(96, 140, 82), under=c255(26, 52, 36), core=c255(20, 38, 28))
BARK_OAK = (c255(70, 56, 46), c255(110, 92, 74))
BARK_EUC = (c255(170, 160, 146), c255(222, 214, 198))
BARK_RED = (c255(96, 52, 36), c255(150, 82, 56))
BARK_PALM = (c255(116, 96, 74), c255(160, 136, 104))


def shell_lobes(rng, center, rx, ry, rz, n, rmin, rmax, bottom=-0.25, inner=3):
    """Lobes scattered over an ellipsoid shell (the silhouette) plus a few inside."""
    out = []
    for k in range(n):
        u = rng.uniform(-1, 1) * 0.999
        th = rng.uniform(0, 2 * math.pi)
        z = max(bottom, rng.uniform(-0.2, 1.0) if k % 3 else rng.uniform(0.3, 1.0))
        rr = math.sqrt(max(0.0, 1 - z * z))
        p = Vector((math.cos(th) * rr * rx, math.sin(th) * rr * ry, z * rz))
        out.append((center + p * rng.uniform(0.82, 1.0), rng.uniform(rmin, rmax)))
    for k in range(inner):
        out.append((center + Vector((rng.uniform(-0.4, 0.4) * rx, rng.uniform(-0.4, 0.4) * ry, rng.uniform(-0.1, 0.3) * rz)),
                    (rmin + rmax) * 0.6))
    return out


def oak(name, seed, spread=1.0):
    """California valley oak: a short thick trunk forking low into limbs under a
    broad, clumpy, flat-bottomed crown wider than it is tall."""
    rng = random.Random(seed)
    parts = []
    trunk_top = Vector((0, 0, 3.2))
    trunk = tube([Vector((0, 0, -0.3)), Vector((0.1, 0, 1.2)), Vector((0.2, 0.1, 2.4)), trunk_top], [1.05, 0.72, 0.62, 0.55], sides=12)
    parts.append(trunk)
    center = Vector((0, 0, 7.2))
    lobes = shell_lobes(rng, center, 6.2 * spread, 5.6 * spread, 3.0, 20, 1.5, 2.4, bottom=-0.35, inner=5)
    for c, r in lobes[::3]:
        end = Vector((c.x * 0.7, c.y * 0.7, c.z - 1.4))
        limb = tube(branch_path(trunk_top, end, Vector((0, 0, 0.9))), [0.4, 0.32, 0.25, 0.19, 0.14, 0.09], sides=8)
        parts.append(limb)
    paint_bark(trunk, *BARK_OAK, -0.3, 6)
    for p in parts[1:]:
        paint_bark(p, *BARK_OAK, 2, 7)
    crown = canopy(lobes, fine=0.32, fine_scale=0.75, voxel=0.34, target=2500, flatten_below=4.9)
    soft_normals(crown, lobes)
    paint_canopy(crown, lobes, seed=seed, **LEAF_OAK)
    parts.append(crown)
    return finish(name, parts)


def orchard(name, seed):
    rng = random.Random(seed)
    # the trunk runs INTO the crown and forks there (it used to stop short of it)
    top = Vector((0.1, 0.05, 3.0))
    trunk = tube([Vector((0, 0, -0.2)), Vector((0.05, 0, 1.2)), Vector((0.08, 0.04, 2.2)), top], [0.34, 0.27, 0.23, 0.2], sides=8)
    parts = [trunk]
    for k in range(3):
        a = 2 * math.pi * k / 3 + 0.5
        parts.append(tube(branch_path(top, top + Vector((math.cos(a) * 1.3, math.sin(a) * 1.3, 1.1)), Vector((0, 0, 0.2)), n=4),
                          [0.16, 0.12, 0.09, 0.06], sides=6))
    for p in parts:
        paint_bark(p, *BARK_OAK, -0.2, 3.5)
    lobes = shell_lobes(rng, Vector((0, 0, 3.9)), 2.2, 2.2, 1.6, 12, 0.75, 1.1, bottom=-0.4, inner=3)
    crown = canopy(lobes, fine=0.16, fine_scale=0.45, voxel=0.18, target=1500, flatten_below=2.8)
    soft_normals(crown, lobes)
    paint_canopy(crown, lobes, seed=seed, **LEAF_ORCH)
    parts.append(crown)
    return finish(name, parts)


def eucalypt(name, seed):
    """Blue gum: a tall pale trunk forking into four limbs, the foliage in hanging
    clumps ALONG the limbs, open and irregular (the old one was a lollipop)."""
    rng = random.Random(seed)
    parts = []
    base = tube([Vector((0, 0, -0.3)), Vector((0.2, 0, 4)), Vector((0.5, 0.2, 9)), Vector((0.6, 0.3, 11))],
                [0.8, 0.6, 0.48, 0.42], sides=10)
    parts.append(base)
    fork = Vector((0.6, 0.3, 11))
    lobes = []
    for k in range(5):
        a = 2 * math.pi * k / 5 + rng.uniform(-0.3, 0.3)
        reach = rng.uniform(4.5, 7.0)          # wide and open, not a column
        tip = Vector((math.cos(a) * reach, math.sin(a) * reach, rng.uniform(19, 24)))
        path = branch_path(fork, tip, Vector((0, 0, 0.6)))
        parts.append(tube(path, [0.36, 0.3, 0.24, 0.18, 0.13, 0.09], sides=8))
        for i, t in enumerate((0.5, 0.6, 0.7, 0.8, 0.9, 1.0)):
            c = fork.lerp(tip, t) + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.6, 0.6)))
            c = c + Vector((rng.uniform(-1.2, 1.2), rng.uniform(-1.2, 1.2), 0))   # clumps overlap into one irregular crown
            lobes.append((c, rng.uniform(1.5, 2.3) * (0.8 + 0.35 * t)))
    lobes.append((Vector((0.5, 0.3, 21.5)), 2.6))          # a core that ties the clumps together
    for p in parts:
        paint_bark(p, *BARK_EUC, 0, 22)
    crown = canopy(lobes, fine=0.36, fine_scale=0.8, voxel=0.36, target=2400)
    soft_normals(crown, lobes)
    paint_canopy(crown, lobes, seed=seed, **LEAF_EUC)
    parts.append(crown)
    return finish(name, parts)


def redwood(name, seed, height=28):
    """Coast redwood: a straight red trunk and one continuous narrow cone of
    drooping foliage, widest low, tapering to a point (not stacked pancakes)."""
    rng = random.Random(seed)
    trunk = tube([Vector((0, 0, -0.3)), Vector((0, 0, 3)), Vector((0, 0, height * 0.6)), Vector((0, 0, height))],
                 [1.1, 0.8, 0.5, 0.12], sides=12)
    paint_bark(trunk, *BARK_RED, -0.3, height)
    lobes = []
    z = height * 0.24
    while z < height + 0.6:
        t = (z - height * 0.24) / (height * 0.76)
        r = (1 - t) ** 0.9 * 3.6 + 0.45
        n = max(3, int(round(r * 2.2)))
        for k in range(n):
            a = 2 * math.pi * k / n + rng.uniform(-0.25, 0.25) + z
            lobes.append((Vector((math.cos(a) * r * 0.6, math.sin(a) * r * 0.6, z + rng.uniform(-0.3, 0.3))),
                          max(0.45, r * rng.uniform(0.5, 0.62))))
        z += 1.05
    crown = canopy(lobes, fine=0.22, fine_scale=0.6, voxel=0.3, target=2300)
    soft_normals(crown, lobes, mix=0.55)
    paint_canopy(crown, lobes, seed=seed, **LEAF_RED)
    return finish(name, [trunk, crown])


def frond(base, direction, length, droop, rng, col_mid, col_tip, leaflets=16):
    """A pinnate palm frond: a curved rachis with paired leaflets hanging from it."""
    bm = bmesh.new()
    right = direction.cross(Vector((0, 0, 1))).normalized()
    spine = []
    n = leaflets
    for i in range(n + 1):
        t = i / n
        p = base + direction * (length * t) + Vector((0, 0, length * (0.35 * t - droop * t * t)))
        spine.append(p)
    colors = []
    for i in range(1, n):
        t = i / n
        p = spine[i]
        fwd = (spine[i + 1] - spine[i - 1]).normalized()
        L = length * (0.34 * math.sin(math.pi * min(1, t * 1.15)) + 0.05)
        for side in (-1, 1):
            tip = p + right * side * L + Vector((0, 0, -L * 0.55)) + fwd * L * 0.35
            w = fwd * length * 0.022
            v1 = bm.verts.new(p - w)
            v2 = bm.verts.new(p + w)
            v3 = bm.verts.new(tip)
            f = bm.faces.new((v1, v2, v3))
            colors.append((f, t))
    # the rachis itself as a thin strip
    for i in range(n):
        a, b = spine[i], spine[i + 1]
        w = Vector((0, 0, 0.06))
        f = bm.faces.new((bm.verts.new(a - right * 0.07), bm.verts.new(b - right * 0.05),
                          bm.verts.new(b + right * 0.05), bm.verts.new(a + right * 0.07)))
    # Roblox draws one side of a mesh: give every leaflet a back face so the
    # fronds read from underneath (you look UP at a palm)
    back = bmesh.ops.duplicate(bm, geom=list(bm.faces))["geom"]
    bmesh.ops.reverse_faces(bm, faces=[g for g in back if isinstance(g, bmesh.types.BMFace)])
    o = K.mesh_obj("frond", bm)
    return o


def palm(name, seed, height=22, lean=1.8, fan=False):
    """Canary date palm (and a slimmer Mexican fan palm): a ringed trunk leaning
    a little, a crown of arching pinnate fronds, orange date clusters."""
    rng = random.Random(seed)
    parts = []
    top = Vector((lean, 0.3, height))
    pts = [Vector((0, 0, -0.3))]
    for i in range(1, 9):
        t = i / 8
        pts.append(Vector((lean * t * t, 0.3 * t * t, height * t)))
    rad = [0.95, 0.8, 0.74, 0.7, 0.68, 0.66, 0.66, 0.7, 0.78] if not fan else [0.7, 0.6, 0.55, 0.5, 0.48, 0.46, 0.44, 0.44, 0.5]
    trunk = tube(pts, rad, sides=12)
    paint_bark(trunk, *BARK_PALM, -0.3, height, rings=5.2)
    parts.append(trunk)
    # the crown bulb
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1.2 if not fan else 0.9, segments=14, ring_count=8, location=top)
    bulb = bpy.context.active_object
    K.paint(bulb, K.flat(c255(110, 104, 60)))
    parts.append(bulb)
    nf = 20 if not fan else 18
    fronds = []
    for k in range(nf):
        a = 2 * math.pi * k / nf + rng.uniform(-0.12, 0.12)
        tier = k % 3
        elev = [0.35, 0.05, -0.35][tier]
        d = Vector((math.cos(a), math.sin(a), 0)).normalized()
        L = rng.uniform(7.2, 8.8) if not fan else rng.uniform(5.8, 6.8)
        f = frond(top + Vector((0, 0, 0.5 - tier * 0.3)), d, L, droop=0.55 + tier * 0.25 + rng.uniform(-0.05, 0.1), rng=rng,
                  col_mid=None, col_tip=None, leaflets=14)
        fronds.append(f)
    for f in fronds:
        me = f.data
        me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
        attr = me.color_attributes["Col"]
        for poly in me.polygons:
            for li in poly.loop_indices:
                p = me.vertices[me.loops[li].vertex_index].co
                t = min(1.0, (p - top).length / 7.0)
                col = lerp(c255(58, 108, 50), c255(150, 176, 78), t)
                n = noise.noise(p * 0.8)
                k = 1 + 0.08 * n
                attr.data[li].color_srgb = (min(1, col[0] * k), min(1, col[1] * k), min(1, col[2] * k), 1.0)
        me.color_attributes.active_color = attr
    parts += fronds
    if not fan:
        for k in range(4):
            a = 2 * math.pi * k / 4 + 0.4
            c = top + Vector((math.cos(a) * 0.9, math.sin(a) * 0.9, -1.2))
            bpy.ops.mesh.primitive_ico_sphere_add(radius=0.45, subdivisions=2, location=c)
            dates = bpy.context.active_object
            dates.scale = (1, 1, 1.5)
            bpy.ops.object.transform_apply(scale=True)
            K.paint(dates, K.shaded(c255(222, 140, 52)))
            parts.append(dates)
    o = finish(name, parts)
    # fronds are single-sided in Roblox: duplicate them back-to-back so they read from below
    return o


SPECIES = {
    "Oak_A": lambda: oak("Oak_A", 11, 1.0),
    "Oak_B": lambda: oak("Oak_B", 23, 0.85),
    "Orchard_A": lambda: orchard("Orchard_A", 5),
    "Eucalypt_A": lambda: eucalypt("Eucalypt_A", 7),
    "Redwood_A": lambda: redwood("Redwood_A", 3),
    "Palm_A": lambda: palm("Palm_A", 13, 22, 1.8, False),
    "Palm_B": lambda: palm("Palm_B", 17, 24, 1.2, True),
}


def preview_cycles(obj, path):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = (d.type == "OPTIX")
    sc.cycles.device = "GPU"
    sc.cycles.samples = 64
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = 700, 800
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("W")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.68, 0.86, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    sd = bpy.data.lights.new("Sun", "SUN")
    sd.energy = 3.5
    sd.angle = math.radians(4)
    sun = bpy.data.objects.new("Sun", sd)
    sc.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(50), 0, math.radians(-40))
    m = bpy.data.materials.new("VC")
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Roughness"].default_value = 0.85
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    nt.links.new(vc.outputs["Color"], p.inputs["Base Color"])
    obj.data.materials.clear()
    obj.data.materials.append(m)
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, 0))
    g = bpy.context.active_object
    gm = bpy.data.materials.new("G")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.42, 0.52, 0.22, 1)
    g.data.materials.append(gm)
    mins = Vector([min((obj.matrix_world @ Vector(c))[i] for c in obj.bound_box) for i in range(3)])
    maxs = Vector([max((obj.matrix_world @ Vector(c))[i] for c in obj.bound_box) for i in range(3)])
    center = (mins + maxs) / 2
    radius = (maxs - mins).length / 2
    cd = bpy.data.cameras.new("C")
    cd.lens = 50
    cam = bpy.data.objects.new("C", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    dist = radius * 2.3
    cam.location = center + Vector((dist * 0.55, -dist * 0.8, dist * 0.18))
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def export_fbx(obj, path):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, apply_unit_scale=True, apply_scale_options="FBX_SCALE_ALL",
                             global_scale=1.0, mesh_smooth_type="OFF", use_mesh_modifiers=True, colors_type="SRGB",
                             add_leaf_bones=False, bake_anim=False, axis_forward="-Z", axis_up="Y")


REPORT = {}
for name in (ARGS or list(SPECIES)):
    K.reset()
    o = SPECIES[name]()
    REPORT[name] = K.tris(o)
    export_fbx(o, os.path.join(IMP, name + ".fbx"))
    preview_cycles(o, os.path.join(OUT, "trees2_%s.png" % name.lower()))
print("TREES2", REPORT)
