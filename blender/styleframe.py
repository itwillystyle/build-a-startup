"""THE STYLEFRAME (PLAN v6, phase V1): what Build a Startup! should look like.

A campus at golden hour built by the rules in art/ART.md: bevelled paper-white
architecture, timber soffits, tinted glass with lit interiors, one company
accent colour, the real in-game trees and rocket (imported from the same FBX
files the game uses), golden hills, a Nishita sky. Every later visual phase is
judged against this image. Rendered with Cycles, but with bounces capped so the
target stays reachable by Roblox's Realistic lighting plus baked AO.

Run: blender -b --python styleframe.py -- [samples] [width] [height]
"""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
from mathutils import Vector, noise
import svkit as K
import time
T0 = time.time()

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SAMPLES = int(ARGS[0]) if len(ARGS) > 0 else 128
RES_X = int(ARGS[1]) if len(ARGS) > 1 else 1920
RES_Y = int(ARGS[2]) if len(ARGS) > 2 else 1080

# ------------------------------------------------------------------ palette
# the eight colours of ART.md, plus the one company accent
PAPER = K.rgb(243, 239, 230)      # buildings (never pure white)
CONCRETE = K.rgb(207, 198, 182)   # plinths, paths, plaza
OAK = K.rgb(192, 138, 85)         # timber soffits, fins, benches
GLASS = K.rgb(118, 158, 176)      # tinted glazing
LAWN = K.rgb(122, 170, 80)        # campus lawn
GOLD = K.rgb(224, 182, 90)        # the California hills
SHADE = K.rgb(62, 110, 158)       # cool accent: solar, signage backs
INK = K.rgb(30, 37, 48)           # mullions, asphalt, text
ACCENT = K.rgb(240, 110, 80)      # the player's company colour (example: coral)
BRAND = K.rgb(255, 194, 61)       # brand gold (the rocket)

K.reset()
scene = bpy.context.scene
col = scene.collection
random.seed(7)


# ------------------------------------------------------------------ materials
def vc_material(name, rough=0.55, spec=0.35):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    v = nt.nodes.new("ShaderNodeVertexColor")
    v.layer_name = ""
    nt.links.new(v.outputs["Color"], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = rough
    p.inputs["Specular IOR Level"].default_value = spec
    return m


def plain_material(name, color, rough=0.5, metal=0.0, emit=0.0, emit_color=None, transmission=0.0, ior=1.45, coat=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*[K.srgb_to_linear(c) for c in color], 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    p.inputs["IOR"].default_value = ior
    p.inputs["Transmission Weight"].default_value = transmission
    p.inputs["Coat Weight"].default_value = coat
    if emit > 0:
        ec = emit_color or color
        p.inputs["Emission Color"].default_value = (*[K.srgb_to_linear(c) for c in ec], 1)
        p.inputs["Emission Strength"].default_value = emit
    return m


MAT_VC = vc_material("VertexColour")
MAT_VC_SOFT = vc_material("VertexColourMatte", rough=0.8, spec=0.2)
MAT_GLASS = plain_material("Glass", GLASS, rough=0.03, transmission=0.72, ior=1.45, coat=0.5)
MAT_WARM = plain_material("InteriorLight", (1.0, 0.86, 0.66), emit=12.0)
MAT_SCREEN = plain_material("Screen", (0.62, 0.8, 1.0), emit=3.0)
MAT_SOLAR = plain_material("Solar", (0.10, 0.16, 0.30), rough=0.12, metal=0.3)


def assign(o, mat):
    o.data.materials.clear()
    o.data.materials.append(mat)
    return o


# ------------------------------------------------------------------ geometry helpers
def finish(o, color, mat=MAT_VC, bev=0.0, seg=2, smooth_angle=35):
    if bev > 0:
        m = o.modifiers.new("Bevel", "BEVEL")
        m.width = bev
        m.segments = seg
        m.limit_method = "ANGLE"
        m.angle_limit = math.radians(40)
        K.apply_mods(o)
    if color is not None:
        K.paint(o, K.flat(color))
    assign(o, mat)
    K.smooth(o, smooth_angle)
    return o


def box(name, size, loc, color, bev=0.12, mat=MAT_VC, rot=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=(0, 0, rot))
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True, rotation=False, location=False)
    return finish(o, color, mat, bev)


def slab(name, w, d, h, loc, color, radius=3.0, bev=0.25, mat=MAT_VC):
    """A rounded-rectangle slab: big radius on the vertical corners, a soft
    bevel on every other edge. The single shape the whole architecture uses."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1)
    for v in bm.verts:
        v.co = Vector((v.co.x * w, v.co.y * d, v.co.z * h))
    vert_edges = [e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) > h * 0.5]
    if radius > 0:
        bmesh.ops.bevel(bm, geom=vert_edges, offset=min(radius, w / 2 - 0.01, d / 2 - 0.01), offset_type="OFFSET",
                        segments=8, profile=0.5, affect="EDGES")
    o = K.mesh_obj(name, bm)
    o.location = loc
    return finish(o, color, mat, bev, seg=2)


def cyl(name, r, depth, loc, color, verts=16, mat=MAT_VC, rot=(0, 0, 0), bev=0.05):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, vertices=verts, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    return finish(o, color, mat, bev)


def ribbon(name, pts, width, z, color, closed=False):
    """A flat path along a polyline, width across, sitting at z."""
    bm = bmesh.new()
    left, right = [], []
    n = len(pts)
    for i, p in enumerate(pts):
        a = pts[(i - 1) % n] if (closed or i > 0) else p
        b = pts[(i + 1) % n] if (closed or i < n - 1) else p
        t = (Vector(b) - Vector(a))
        t.z = 0
        t.normalize()
        nrm = Vector((-t.y, t.x, 0))
        left.append(bm.verts.new((p[0] + nrm.x * width / 2, p[1] + nrm.y * width / 2, z)))
        right.append(bm.verts.new((p[0] - nrm.x * width / 2, p[1] - nrm.y * width / 2, z)))
    segs = n if closed else n - 1
    for i in range(segs):
        j = (i + 1) % n
        bm.faces.new((left[i], right[i], right[j], left[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = K.mesh_obj(name, bm)
    sol = o.modifiers.new("S", "SOLIDIFY")
    sol.thickness = 0.35
    K.apply_mods(o)
    return finish(o, color, MAT_VC_SOFT, 0.0)


# ------------------------------------------------------------------ in-game assets (the real FBX files)
_templates = {}


def template(name):
    if name in _templates:
        return _templates[name]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.join(OUT, name + ".fbx"), axis_forward="-Z", axis_up="Y")
    new = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    o = new[0]
    for other in bpy.context.selected_objects:
        other.select_set(False)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    assign(o, MAT_VC_SOFT)
    # measure it, park it out of frame
    zs = [(o.matrix_world @ Vector(c)).z for c in o.bound_box]
    o["h"] = max(zs) - min(zs)
    o["z0"] = min(zs)
    o.location = (0, 0, -5000)
    _templates[name] = o
    return o


def place(name, x, y, z, height=None, yaw=None):
    t = template(name)
    o = t.copy()                      # linked duplicate: shares the mesh
    col.objects.link(o)
    s = (height / t["h"]) if height else 1.0
    o.scale = (s, s, s)
    o.rotation_euler = (0, 0, random.uniform(0, 2 * math.pi) if yaw is None else yaw)
    o.location = (x, y, z - t["z0"] * s)
    return o


# ------------------------------------------------------------------ the land
CAMPUS_R = 250.0


def ground_h(x, y):
    """Flat campus in the middle; golden hills rising behind (north, +y) and to the east."""
    d = math.sqrt((x / 1.25) ** 2 + (max(y, -200) + 40) ** 2)
    rise = max(0.0, (d - CAMPUS_R) / 260.0)
    rise = min(rise, 1.0)
    rise = rise * rise * (3 - 2 * rise)
    back = 1.0 if y > -150 else max(0.0, 1 - (-150 - y) / 120)
    # rolling, not alpine: smooth low-octave noise, modest heights, a soft far ridge
    n = noise.fractal(Vector((x / 330.0, y / 330.0, 0.3)), 1.1, 2.0, 3)
    hills = (42 + 38 * n) * rise * back
    ridge = min(1.0, max(0.0, (y - 650) / 450.0)) * 85 * (0.75 + 0.35 * noise.noise(Vector((x / 260.0, 5.0, 1.0))))
    return hills + ridge


def ground_color(x, y, h, n):
    if h < 1.5:
        v = noise.noise(Vector((x / 40.0, y / 40.0, 2.0))) * 0.06
        stripe = 0.035 if (math.floor((x + y * 0.3) / 12.0) % 2 == 0) else -0.035   # mowing stripes
        return tuple(min(1, c * (0.95 + v + stripe)) for c in LAWN)
    # Bay Area hills: oak woodland in the folds and on north-facing slopes, gold
    # on the rest. BLENDED, never thresholded: a hard per-vertex switch drew
    # staircase edges that read as Minecraft shadows (found on the first final).
    wood = noise.noise(Vector((x / 70.0, y / 70.0, 9.0))) + max(0.0, n.y) * 0.9
    w = max(0.0, min(1.0, (wood - 0.05) / 0.35))
    w = w * w * (3 - 2 * w) * min(1.0, h / 6.0)
    blend = min(1.0, h / 12.0)
    base = [LAWN[i] * (1 - blend) + GOLD[i] * blend for i in range(3)]
    v = noise.noise(Vector((x / 25.0, y / 25.0, 4.0))) * 0.07
    base = [c * (0.96 + v) for c in base]
    woodc = K.rgb(86, 108, 58)
    return tuple(min(1, base[i] * (1 - w) + woodc[i] * w) for i in range(3))


bpy.ops.mesh.primitive_grid_add(x_subdivisions=520, y_subdivisions=520, size=2400, location=(0, 300, 0))
land = bpy.context.active_object
land.name = "Land"
for v in land.data.vertices:
    w = land.matrix_world @ v.co
    v.co.z = ground_h(w.x, w.y)
K.paint(land, lambda p, n: ground_color(p.x, p.y, p.z, n))
assign(land, MAT_VC_SOFT)
K.smooth(land, 80)

# ------------------------------------------------------------------ road, paths, plaza
ROAD_Y = -130
box("Road", (900, 26, 0.3), (0, ROAD_Y, 0.15), INK, bev=0.0)
for x in range(-440, 441, 16):
    box("Dash", (7, 0.5, 0.05), (x, ROAD_Y, 0.33), K.rgb(236, 226, 196), bev=0.0)
for sy in (-1, 1):
    box("Kerb", (900, 0.8, 0.5), (0, ROAD_Y + sy * 13.4, 0.25), CONCRETE, bev=0.08)
    box("Sidewalk", (900, 6, 0.25), (0, ROAD_Y + sy * 17, 0.12), CONCRETE, bev=0.0)

loop = [(math.cos(a) * 100, -18 + math.sin(a) * 72, 0) for a in [2 * math.pi * k / 64 for k in range(64)]]
ribbon("LoopPath", loop, 6, 0.2, CONCRETE, closed=True)
ribbon("Spur", [(0, -112, 0), (0, -100, 0), (0, -80, 0), (0, -40, 0), (0, -24, 0)], 8, 0.21, CONCRETE)
ribbon("StudioSpur", [(-100, -18, 0), (-88, -14, 0), (-80, -8, 0)], 5, 0.21, CONCRETE)
ribbon("CafeSpur", [(100, -18, 0), (88, -12, 0), (82, -6, 0)], 5, 0.21, CONCRETE)
cyl("Plaza", 16, 0.4, (0, -84, 0.2), CONCRETE, verts=48, mat=MAT_VC_SOFT, bev=0.1)
cyl("PlazaRing", 16.8, 0.3, (0, -84, 0.15), K.rgb(176, 166, 150), verts=48, mat=MAT_VC_SOFT, bev=0.05)

# the rocket monument: the brand, on a pedestal
slab("Pedestal", 7, 7, 2.4, (0, -84, 1.6), PAPER, radius=1.5)
rk = place("Rocket", 0, -84, 2.8, height=13, yaw=math.radians(200))


# ------------------------------------------------------------------ architecture
def lit_floor(cx, cy, w, d, z, rng):
    """Interior life seen through the glass: ceiling light strips, desks, screens."""
    for k in range(-2, 3):
        box("LightStrip", (w * 0.7, 0.5, 0.12), (cx, cy + k * d * 0.17, z + 9.4), None, bev=0.0, mat=MAT_WARM)
    for _ in range(int(w * d / 90)):
        x = cx + rng.uniform(-w / 2 + 3, w / 2 - 3)
        y = cy + rng.uniform(-d / 2 + 3, d / 2 - 3)
        box("Desk", (3.2, 1.6, 0.25), (x, y, z + 2.6), OAK, bev=0.04)
        box("Screen", (1.3, 0.12, 0.9), (x, y + 0.5, z + 3.3), None, bev=0.0, mat=MAT_SCREEN)


def storey(name, cx, cy, w, d, z, rng, fins=True, radius=4.0):
    slab(name + "Slab", w + 2, d + 2, 1.4, (cx, cy, z + 0.7), PAPER, radius=radius + 1)
    box(name + "Soffit", (w - 1, d - 1, 0.2), (cx, cy, z - 0.05), OAK, bev=0.0)
    slab(name + "Glass", w - 1.2, d - 1.2, 10.2, (cx, cy, z + 1.4 + 5.1), None, radius=max(0.1, radius - 0.6), bev=0.0, mat=MAT_GLASS)
    box(name + "Floor", (w - 2, d - 2, 0.3), (cx, cy, z + 1.5), K.rgb(214, 204, 188), bev=0.0)
    lit_floor(cx, cy, w - 4, d - 4, z + 1.4, rng)
    if fins:
        # vertical fins on the long faces (straight runs only, not the rounded corners)
        for sy in (-1, 1):
            x = -w / 2 + radius + 1
            while x < w / 2 - radius - 0.5:
                box(name + "Fin", (0.45, 1.3, 10.2), (cx + x, cy + sy * (d / 2 - 0.2), z + 6.5), OAK, bev=0.08)
                x += 3.6


rng = random.Random(3)
HQ = (0, 10)
HQW, HQD = 60, 38
# ground floor: double height lobby, then two office floors, the top one cantilevered east
storey("L0", HQ[0], HQ[1], HQW, HQD, 1.2, rng, fins=False)
storey("L1", HQ[0], HQ[1], HQW, HQD, 13.2, rng)
storey("L2", HQ[0] + 11, HQ[1] + 3, HQW - 6, HQD - 4, 25.2, rng)
slab("Roof", HQW - 4, HQD - 2, 1.6, (HQ[0] + 11, HQ[1] + 3, 37.6), PAPER, radius=5)
slab("Plinth", HQW + 8, HQD + 8, 1.2, (HQ[0], HQ[1], 0.6), CONCRETE, radius=6)
# roof garden + solar: the roof is the part players see most from the default camera
for i in range(4):
    slab("Planter", 6, 3, 1.4, (HQ[0] - 12 + i * 8, HQ[1] + 12, 39.1), CONCRETE, radius=0.8)
    place("Orchard_A", HQ[0] - 12 + i * 8, HQ[1] + 12, 39.8, height=4.2)
for i in range(3):
    for j in range(2):
        box("Solar", (6, 3.6, 0.2), (HQ[0] + 16 + i * 7, HQ[1] - 6 + j * 5, 39.3), None, bev=0.02, mat=MAT_SOLAR).rotation_euler = (math.radians(-18), 0, 0)
# entrance: a canopy on two slim columns, the company name on its face in the accent
slab("Canopy", 22, 9, 0.9, (HQ[0], HQ[1] - HQD / 2 - 4, 11.8), PAPER, radius=2)
box("CanopySoffit", (21, 8, 0.15), (HQ[0], HQ[1] - HQD / 2 - 4, 11.3), OAK, bev=0.0)
for sx in (-1, 1):
    cyl("Column", 0.45, 10.4, (HQ[0] + sx * 9.5, HQ[1] - HQD / 2 - 7.5, 6.2), PAPER)
box("SignBand", (24, 0.6, 2.6), (HQ[0], HQ[1] - HQD / 2 - 8.6, 13.4), ACCENT, bev=0.2)

font_path = "C:/Windows/Fonts/segoeuib.ttf"
bpy.ops.object.text_add(location=(HQ[0], HQ[1] - HQD / 2 - 8.95, 12.6), rotation=(math.radians(90), 0, 0))
sign = bpy.context.active_object
sign.data.body = "POCKET ROCKET"
if os.path.exists(font_path):
    sign.data.font = bpy.data.fonts.load(font_path)
sign.data.size = 1.8
sign.data.extrude = 0.08
sign.data.align_x = "CENTER"
sign.data.materials.append(plain_material("SignText", PAPER, rough=0.4))

# the two wings, joined to the HQ by glass links
def pavilion(name, cx, cy, w, d, kind):
    slab(name + "Plinth", w + 4, d + 4, 1.0, (cx, cy, 0.5), CONCRETE, radius=3)
    slab(name + "Glass", w - 1, d - 1, 9.6, (cx, cy, 1.0 + 4.8), None, radius=2.2, bev=0.0, mat=MAT_GLASS)
    box(name + "Floor", (w - 2, d - 2, 0.3), (cx, cy, 1.1), K.rgb(214, 204, 188), bev=0.0)
    lit_floor(cx, cy, w - 4, d - 4, 1.0, rng)
    slab(name + "Roof", w + 5, d + 5, 1.1, (cx, cy, 11.2), PAPER, radius=4)
    box(name + "Soffit", (w + 3, d + 3, 0.15), (cx, cy, 10.6), OAK, bev=0.0)
    if kind == "studio":
        # sawtooth north lights: the design studio's silhouette
        for k in range(4):
            x = cx - w / 2 + 4 + k * (w - 8) / 3
            bpy.ops.mesh.primitive_cube_add(size=1, location=(x, cy, 13.2))
            t = bpy.context.active_object
            t.scale = (5.6, d - 2, 3.2)
            bpy.ops.object.transform_apply(scale=True)
            bm = bmesh.new()
            bm.from_mesh(t.data)
            for v in bm.verts:
                if v.co.z > 0 and v.co.x < 0:
                    v.co.z = -1.6            # a wedge: tall face to the north
            bm.to_mesh(t.data)
            bm.free()
            finish(t, PAPER, MAT_VC, 0.1)
    else:
        # the cafe: a terrace with umbrellas in the company accent
        for k in range(4):
            ux, uy = cx - w / 2 + 3 + k * 7, cy - d / 2 - 9
            cyl("Pole", 0.15, 5.0, (ux, uy, 2.9), PAPER, verts=8)
            bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=3.2, radius2=0.2, depth=1.4, location=(ux, uy, 5.6))
            u = bpy.context.active_object
            finish(u, ACCENT if k % 2 == 0 else PAPER, MAT_VC, 0.05)
            cyl("Table", 1.0, 0.2, (ux, uy, 1.8), PAPER, verts=16)
        slab(name + "Terrace", w + 2, 12, 0.4, (cx, cy - d / 2 - 8, 0.4), OAK, radius=1.5, mat=MAT_VC_SOFT)


pavilion("Studio", -86, 0, 28, 24, "studio")
pavilion("Cafe", 86, 4, 26, 22, "cafe")
for sx, x0, x1 in ((-1, -HQW / 2, -72), (1, HQW / 2, 73)):
    cx = (x0 + x1) / 2
    ln = abs(x1 - x0)
    box("Link", (ln, 6, 0.8), (cx, 6, 9.6), PAPER, bev=0.15)
    box("LinkGlass", (ln, 5.4, 8), (cx, 6, 5.2), None, bev=0.0, mat=MAT_GLASS)
    box("LinkFloor", (ln, 6, 0.4), (cx, 6, 1.2), CONCRETE, bev=0.05)

# ------------------------------------------------------------------ trees (the game's own meshes)
tr = random.Random(11)
for x in range(-420, 421, 30):
    if abs(x) < 16:
        continue
    for side in (-1, 1):
        place("Palm_A" if (x // 30 + side) % 2 == 0 else "Palm_B", x + tr.uniform(-2, 2), ROAD_Y + side * 22, 0, height=tr.uniform(20, 25))
for (cx, cy, n) in ((-46, -62, 3), (48, -66, 3), (-128, 34, 4), (132, 40, 4), (-58, 60, 3), (62, 66, 3), (0, 62, 2), (-150, -40, 2), (150, -52, 2)):
    for _ in range(n):
        place("Oak_A" if tr.random() < 0.5 else "Oak_B", cx + tr.uniform(-12, 12), cy + tr.uniform(-10, 10), 0, height=tr.uniform(11, 15))
x = -250
while x < 250:
    place("Eucalypt_A", x, 124 + tr.uniform(-9, 9), 0, height=tr.uniform(22, 34))
    x += tr.uniform(11, 26)
placed = 0
while placed < 420:
    x, y = tr.uniform(-900, 900), tr.uniform(160, 1200)
    h = ground_h(x, y)
    if h > 4 and noise.noise(Vector((x / 70.0, y / 70.0, 9.0))) > 0.22:
        place("Oak_A" if tr.random() < 0.5 else "Oak_B", x, y, h - 0.6, height=tr.uniform(12, 16))
        placed += 1
placed = 0
while placed < 80:
    x, y = tr.uniform(-900, 900), tr.uniform(700, 1400)
    h = ground_h(x, y)
    if h > 60:
        place("Redwood_A", x, y, h - 0.5, height=tr.uniform(24, 32))
        placed += 1


dx, dy = 70, 430
place("TheDish", dx, dy, ground_h(dx, dy) - 0.8, height=44, yaw=math.radians(200))

# ------------------------------------------------------------------ people (Roblox proportions, not block rigs)
def person(x, y, yaw, shirt, pants, skin, stride=0.0):
    parts = []
    def limb(name, size, loc, colr):
        parts.append(box(name, size, loc, colr, bev=0.22))
    limb("LegL", (0.9, 0.95, 2.1), (-0.5, stride * 0.6, 1.05), pants)
    limb("LegR", (0.9, 0.95, 2.1), (0.5, -stride * 0.6, 1.05), pants)
    limb("Torso", (2.0, 1.05, 2.0), (0, 0, 3.1), shirt)
    limb("ArmL", (0.85, 0.9, 2.0), (-1.45, -stride * 0.5, 3.05), shirt)
    limb("ArmR", (0.85, 0.9, 2.0), (1.45, stride * 0.5, 3.05), skin)
    limb("Head", (1.25, 1.2, 1.25), (0, 0, 4.75), skin)
    limb("Hair", (1.35, 1.3, 0.45), (0, 0.05, 5.35), K.rgb(58, 40, 30))
    o = K.join(parts, "Person")
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)   # origin to the feet-centre (0,0,0)
    o.rotation_euler = (0, 0, yaw)
    o.location = (x, y, 0.4)
    return o


SHIRTS = [ACCENT, SHADE, K.rgb(250, 208, 90), K.rgb(120, 190, 120), PAPER, K.rgb(170, 120, 200)]
SKINS = [K.rgb(236, 196, 160), K.rgb(200, 150, 110), K.rgb(150, 100, 70), K.rgb(110, 72, 50)]
pr = random.Random(5)
for (x, y) in ((-4, -96), (3, -70), (-2, -52), (6, -40), (-62, -68), (66, -60), (-94, -30), (95, -22), (40, -84), (-30, -86), (10, -118), (-18, -120)):
    person(x + pr.uniform(-1, 1), y, pr.uniform(0, 2 * math.pi), pr.choice(SHIRTS), INK if pr.random() < 0.6 else K.rgb(70, 90, 130), pr.choice(SKINS), pr.uniform(-0.4, 0.4))

# benches and lamps along the loop
for a in (0.9, 2.2, 4.0, 5.4):
    x, y = math.cos(a) * 92, -18 + math.sin(a) * 64
    b = box("Bench", (4.8, 1.6, 0.35), (x, y, 1.4), OAK, bev=0.08, rot=a + math.pi / 2)
    box("BenchBase", (4.4, 1.2, 1.2), (x, y, 0.7), CONCRETE, bev=0.1, rot=a + math.pi / 2)
for a in [2 * math.pi * k / 10 for k in range(10)]:
    x, y = math.cos(a) * 106, -18 + math.sin(a) * 78
    cyl("LampPost", 0.18, 7, (x, y, 3.5), INK, verts=8)
    box("LampHead", (1.6, 0.5, 0.3), (x, y, 7.1), None, bev=0.0, mat=MAT_WARM)


# ------------------------------------------------------------------ cars: two EVs on the road
def ev(x, lane, color):
    parts = [box("Body", (9.4, 4.2, 1.8), (x, ROAD_Y + lane, 1.6), color, bev=0.6),
             box("Cabin", (5.4, 3.7, 1.5), (x - 0.4, ROAD_Y + lane, 3.1), INK, bev=0.5)]
    for dx in (-3, 3):
        for dy in (-2.0, 2.0):
            parts.append(cyl("Wheel", 0.85, 0.7, (x + dx, ROAD_Y + lane + dy, 0.9), INK, rot=(math.radians(90), 0, 0)))
    K.join(parts, "EV")


ev(-60, -6, PAPER)
ev(70, 6, ACCENT)
ev(170, -6, SHADE)

# ------------------------------------------------------------------ light and sky: golden hour
world = bpy.data.worlds.new("Sky")
scene.world = world
world.use_nodes = True
wn = world.node_tree
sky = wn.nodes.new("ShaderNodeTexSky")
sky.sky_type = "NISHITA"
SUN_ELEV = math.radians(7.5)
SUN_ROT = math.radians(289)
sky.sun_elevation = SUN_ELEV
sky.sun_rotation = SUN_ROT
sky.altitude = 40
sky.air_density = 1.0
sky.dust_density = 1.1
sky.ozone_density = 1.0
sky.sun_disc = True
sky.sun_intensity = 0.4
bg = wn.nodes["Background"]
bg.inputs["Strength"].default_value = 0.28
wn.links.new(sky.outputs["Color"], bg.inputs["Color"])

sun_data = bpy.data.lights.new("Sun", "SUN")
sun_data.energy = 5.2
sun_data.angle = math.radians(1.6)
sun_data.color = (1.0, 0.68, 0.40)
sun = bpy.data.objects.new("Sun", sun_data)
col.objects.link(sun)
# point the lamp from the same direction the sky draws the sun
d = Vector((math.cos(SUN_ELEV) * math.sin(SUN_ROT), -math.cos(SUN_ELEV) * math.cos(SUN_ROT), math.sin(SUN_ELEV)))
sun.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()

# ------------------------------------------------------------------ camera: the player's zoomed-out view
cam_data = bpy.data.cameras.new("Cam")
cam_data.lens = 30
cam_data.clip_end = 6000
cam = bpy.data.objects.new("Cam", cam_data)
col.objects.link(cam)
cam.location = Vector((-128, -206, 50))
target = Vector((14, 8, 20))
cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
scene.camera = cam

# ------------------------------------------------------------------ render
scene.render.engine = "CYCLES"
try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for dt in ("OPTIX", "CUDA"):
        try:
            prefs.compute_device_type = dt
            prefs.get_devices()
            if any(dv.type == dt for dv in prefs.devices):
                break
        except Exception:
            pass
    for dv in prefs.devices:
        dv.use = (dv.type == prefs.compute_device_type)
    scene.cycles.device = "GPU"
    print("DEVICE", prefs.compute_device_type, [dv.name for dv in prefs.devices if dv.use])
except Exception as e:
    print("GPU setup failed, CPU:", e)
scene.cycles.samples = SAMPLES
scene.cycles.use_denoising = True
# bounces capped: Roblox has no global illumination, so the target shouldn't lean on it
scene.cycles.max_bounces = 4
scene.cycles.diffuse_bounces = 2
scene.cycles.glossy_bounces = 2
scene.cycles.transmission_bounces = 4
scene.render.resolution_x = RES_X
scene.render.resolution_y = RES_Y
scene.render.film_transparent = True
scene.view_layers[0].use_pass_environment = True
scene.view_settings.view_transform = "AgX"
for look in ("AgX - Punchy", "AgX - Medium High Contrast"):
    try:
        scene.view_settings.look = look
        break
    except Exception:
        pass
scene.view_layers[0].use_pass_mist = True
world.mist_settings.start = 180
world.mist_settings.depth = 1500
world.mist_settings.falloff = "QUADRATIC"
scene.use_nodes = True
ct = scene.node_tree
rl = ct.nodes["Render Layers"]
comp = ct.nodes["Composite"]
fac = ct.nodes.new("CompositorNodeMath")
fac.operation = "MULTIPLY"
fac.inputs[1].default_value = 0.42
mix = ct.nodes.new("CompositorNodeMixRGB")
mix.blend_type = "MIX"
mix.inputs[2].default_value = (0.62, 0.66, 0.80, 1.0)     # looking away from the sun, distance goes blue-lavender
ct.links.new(rl.outputs["Mist"], fac.inputs[0])
ct.links.new(fac.outputs[0], mix.inputs[0])
ct.links.new(rl.outputs["Image"], mix.inputs[1])
keep_alpha = ct.nodes.new("CompositorNodeSetAlpha")
ct.links.new(mix.outputs[0], keep_alpha.inputs["Image"])
ct.links.new(rl.outputs["Alpha"], keep_alpha.inputs["Alpha"])
over = ct.nodes.new("CompositorNodeAlphaOver")
ct.links.new(rl.outputs["Env"], over.inputs[1])
ct.links.new(keep_alpha.outputs[0], over.inputs[2])
glare = ct.nodes.new("CompositorNodeGlare")
glare.glare_type = "FOG_GLOW"
glare.threshold = 1.2
glare.size = 7
glare.mix = -0.75
ct.links.new(over.outputs[0], glare.inputs[0])
ct.links.new(glare.outputs[0], comp.inputs["Image"])
print("BUILD", round(time.time() - T0, 1), "s")
scene.render.filepath = os.path.join(OUT, "styleframe.png")
bpy.ops.render.render(write_still=True)
print("STYLEFRAME", scene.render.filepath, "total", round(time.time() - T0, 1), "s")
