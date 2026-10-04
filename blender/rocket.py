"""The brand rocket (logo_512.png made real): white body, gold stepped nose,
porthole, three swept slate fins, a nozzle bell. One mesh, vertex coloured.
Run: blender -b --python rocket.py"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
from mathutils import Vector
import svkit as K

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
os.makedirs(OUT, exist_ok=True)
K.reset()

WHITE = K.rgb(246, 246, 242)
GOLD = K.rgb(255, 190, 60)
SLATE = K.rgb(62, 72, 92)
GLASS = K.rgb(96, 190, 255)
DARK = K.rgb(46, 50, 60)

parts = []
nozzle = K.lathe("Nozzle", [(0.95, 0.0), (0.86, 0.12), (0.68, 0.45), (0.56, 0.8), (0.6, 1.05)], 32)
K.paint(nozzle, K.shaded(DARK)); parts.append(nozzle)

body = K.lathe("Body", [(0.6, 1.05), (1.05, 1.15), (1.3, 1.6), (1.4, 2.6), (1.42, 4.2), (1.38, 5.6), (1.28, 6.45)], 40)
K.paint(body, K.shaded(WHITE, 1.02, 0.8)); parts.append(body)

# the gold stepped nose: a lip ring, then an ogive
nose = K.lathe("Nose", [(1.28, 6.45), (1.36, 6.52), (1.36, 6.86), (1.18, 6.95), (1.14, 7.5), (0.98, 8.2),
                        (0.76, 8.9), (0.5, 9.5), (0.24, 9.95), (0.0, 10.15)], 40)
K.paint(nose, K.shaded(GOLD)); parts.append(nose)

# a thin gold band low on the body
band = K.lathe("Band", [(1.36, 2.0), (1.44, 2.05), (1.44, 2.3), (1.36, 2.35)], 40)
K.paint(band, K.shaded(GOLD)); parts.append(band)

# porthole: gold ring + domed glass, facing -Y (the front)
bpy.ops.mesh.primitive_torus_add(major_radius=0.56, minor_radius=0.12, major_segments=28, minor_segments=10,
                                 location=(0, -1.38, 4.7), rotation=(math.radians(90), 0, 0))
ring = bpy.context.active_object; ring.name = "PortRing"
K.paint(ring, K.shaded(GOLD)); parts.append(ring)
bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=0.5, location=(0, -1.32, 4.7))
glass = bpy.context.active_object; glass.name = "Port"
glass.scale = (1, 0.35, 1)
bpy.ops.object.transform_apply(scale=True)
K.paint(glass, lambda p, n: tuple(min(1, c * (0.85 + 0.35 * max(0, n.z))) for c in GLASS)); parts.append(glass)

# three swept fins
def fin(angle):
    bm = bmesh.new()
    pts = [(0.0, 0.15), (1.55, -0.35), (2.0, 0.25), (1.05, 2.4), (0.0, 3.0)]
    top, bot = [], []
    for (x, z) in pts:
        top.append(bm.verts.new((x, 0.15, z)))
        bot.append(bm.verts.new((x, -0.15, z)))
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((top[i], bot[i], bot[j], top[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = K.mesh_obj("Fin", bm)
    K.bevel(o, 0.07, 2, 30)
    K.apply_mods(o)
    o.location = (1.15 * math.cos(angle), 1.15 * math.sin(angle), 0.7)
    o.rotation_euler = (0, 0, angle)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True)
    K.paint(o, K.shaded(SLATE))
    return o

for k in range(3):
    parts.append(fin(math.radians(90 + k * 120)))   # one fin straight back, porthole clear in front

rocket = K.join(parts, "Rocket")
K.smooth(rocket, 35)
print("ROCKET tris", K.tris(rocket))
K.preview(os.path.join(OUT, "rocket.png"), [rocket], elev=12, azim=25)
K.export(os.path.join(OUT, "Rocket.fbx"), [rocket])
print("EXPORTED")
