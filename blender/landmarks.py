"""Silicon Valley landmarks: Stanford's Dish, the Lick Observatory domes and
Moffett Field's Hangar One. Run: blender -b --python landmarks.py"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
from mathutils import Vector, Matrix
import svkit as K

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
os.makedirs(OUT, exist_ok=True)
WHITE = K.rgb(240, 240, 236)
CREAM = K.rgb(236, 230, 214)
STEEL = K.rgb(178, 182, 188)
DARK = K.rgb(44, 48, 56)
CONCRETE = K.rgb(176, 172, 164)


def box(name, size, loc, color, bev=0.0, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object; o.name = name
    o.scale = size; bpy.ops.object.transform_apply(scale=True, rotation=True)
    if bev > 0:
        K.bevel(o, bev, 2, 50); K.apply_mods(o)
    K.paint(o, K.shaded(color))
    return o


def rod(name, a, b, r, color, verts=8):
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=d.length, vertices=verts, location=(a + b) / 2)
    o = bpy.context.active_object; o.name = name
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    bpy.ops.object.transform_apply(rotation=True)
    K.paint(o, K.shaded(color))
    return o


# ---------------------------------------------------------------- THE DISH
def dish():
    K.reset()
    parts = []
    R, f = 20.0, 13.0                        # radius, focal length
    prof = [(R * k / 16, (R * k / 16) ** 2 / (4 * f)) for k in range(17)]
    bowl = K.lathe("Bowl", prof, 40)
    sol = bowl.modifiers.new("S", "SOLIDIFY"); sol.thickness = 0.5
    K.apply_mods(bowl)
    # radial ribs on the back of the bowl
    ribs = []
    for k in range(12):
        a = 2 * math.pi * k / 12
        pts = [Vector((r * math.cos(a), r * math.sin(a), r * r / (4 * f) - 0.6)) for r in (2, 8, 14, 19.5)]
        for i in range(3):
            ribs.append(rod("Rib", pts[i], pts[i + 1], 0.22, WHITE, 6))
    rim = K.lathe("Rim", [(R - 0.2, prof[-1][1] - 0.2), (R + 0.35, prof[-1][1]), (R - 0.2, prof[-1][1] + 0.35)], 40)
    # the feed: a tripod to a box at the focus
    feed = box("Feed", (2.2, 2.2, 2.6), (0, 0, f), WHITE, 0.3)
    legs = [rod("FeedLeg", Vector((14 * math.cos(a), 14 * math.sin(a), 196 / (4 * f))), Vector((0, 0, f - 1)), 0.2, WHITE, 6)
            for a in (math.radians(90), math.radians(210), math.radians(330))]
    dishp = [bowl, rim, feed] + ribs + legs
    K.paint(bowl, lambda p, n: tuple(min(1, c * (0.82 + 0.22 * (n.z * 0.5 + 0.5))) for c in WHITE))
    K.paint(rim, K.shaded(WHITE))
    d = K.join(dishp, "DishHead")
    # tilt the dish 40 degrees toward -Y (it looks north-up over the valley in the game)
    d.rotation_euler = (math.radians(-40), 0, 0)
    d.location = (0, 0, 26)
    bpy.context.view_layer.objects.active = d
    bpy.ops.object.transform_apply(location=True, rotation=True)
    parts.append(d)
    # the yoke and the tower
    parts.append(box("Yoke", (5, 3, 5), (0, 0, 22), WHITE, 0.4))
    for sx in (-1, 1):
        parts.append(box("YokeArm", (1.2, 2.4, 7), (sx * 4.2, 0, 25), WHITE, 0.3))
    base_pts = [Vector((sx * 6, sy * 6, 0)) for sx in (-1, 1) for sy in (-1, 1)]
    for p in base_pts:
        parts.append(rod("TowerLeg", p, Vector((p.x * 0.3, p.y * 0.3, 20)), 0.6, WHITE, 8))
    for z in (6, 13):
        s = 6 * (1 - 0.7 * z / 20)
        for (a, b) in (((-1, -1), (1, -1)), ((1, -1), (1, 1)), ((1, 1), (-1, 1)), ((-1, 1), (-1, -1))):
            parts.append(rod("Brace", Vector((a[0] * s, a[1] * s, z)), Vector((b[0] * s, b[1] * s, z)), 0.35, WHITE, 6))
    parts.append(box("Pad", (16, 16, 1.2), (0, 0, 0.4), CONCRETE, 0.3))
    o = K.join(parts, "TheDish")
    K.smooth(o, 40)
    return o


# ---------------------------------------------------------------- LICK
def lick():
    K.reset()
    parts = []
    def dome(name, x, r, h):
        drum = K.lathe(name + "Drum", [(r, 0), (r, h)], 36)
        K.paint(drum, K.shaded(CREAM))
        prof = [(r * math.cos(t), h + r * math.sin(t)) for t in [math.pi / 2 * k / 10 for k in range(11)]]
        cap = K.lathe(name + "Dome", prof, 36)
        # the observing slit: a dark band over the top
        def dpaint(p, n):
            if abs(p.x - 0) < r * 0.14 and p.y < 0.2:
                return DARK
            return tuple(min(1, c * (0.86 + 0.2 * (n.z * 0.5 + 0.5))) for c in WHITE)
        K.paint(cap, dpaint)
        for o in (drum, cap):
            o.location.x = x
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.transform_apply(location=True)
        return [drum, cap]
    parts += dome("Big", -16, 8.5, 7)
    parts += dome("Small", 15, 5.5, 5)
    parts.append(box("Hall", (26, 9, 7), (0, 0, 3.5), CREAM, 0.4))
    parts.append(box("Roof", (27, 10, 0.8), (0, 0, 7.3), K.rgb(196, 90, 66), 0.2))
    for k in range(5):
        parts.append(box("Window", (1.6, 0.2, 3), (-8 + k * 4, -4.55, 3.6), DARK, 0.1))
    parts.append(box("Plinth", (50, 16, 1), (0, 0, 0.3), CONCRETE, 0.3))
    o = K.join(parts, "LickObservatory")
    K.smooth(o, 40)
    return o


# ---------------------------------------------------------------- HANGAR ONE
def hangar():
    K.reset()
    parts = []
    L, Wd, Ht = 150.0, 56.0, 30.0
    # a pointed-parabolic arch section extruded along X
    sec = []
    n = 24
    for k in range(n + 1):
        t = k / n
        y = -Wd / 2 + Wd * t
        z = Ht * (1 - (2 * t - 1) ** 2) ** 0.62
        sec.append((y, z))
    bm = bmesh.new()
    a = [bm.verts.new((-L / 2, y, z)) for (y, z) in sec]
    b = [bm.verts.new((L / 2, y, z)) for (y, z) in sec]
    for i in range(n):
        bm.faces.new((a[i], a[i + 1], b[i + 1], b[i]))
    bm.faces.new(list(reversed(a))); bm.faces.new(b)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    shell = K.mesh_obj("Shell", bm)
    K.paint(shell, lambda p, nn: tuple(min(1, c * (0.78 + 0.3 * (nn.z * 0.5 + 0.5))) for c in STEEL))
    parts.append(shell)
    # ribs
    for k in range(-5, 6):
        x = k * (L / 11)
        rbm = bmesh.new()
        prev = None
        pts = [rbm.verts.new((x, y * 1.03, z * 1.03 + 0.1)) for (y, z) in sec]
        ptsb = [rbm.verts.new((x + 1.2, y * 1.03, z * 1.03 + 0.1)) for (y, z) in sec]
        for i in range(n):
            rbm.faces.new((pts[i], pts[i + 1], ptsb[i + 1], ptsb[i]))
        rib = K.mesh_obj("Rib", rbm)
        sol = rib.modifiers.new("S", "SOLIDIFY"); sol.thickness = 0.6; K.apply_mods(rib)
        K.paint(rib, K.shaded(K.rgb(120, 124, 130)))
        parts.append(rib)
    # the clamshell doors: vertical panels on each end face
    for end in (-1, 1):
        for k in range(-5, 6):
            y = k * 4.4
            zt = Ht * (1 - (2 * ((y + Wd / 2) / Wd) - 1) ** 2) ** 0.62 - 0.8
            if zt > 1:
                parts.append(box("DoorPanel", (0.4, 4.1, zt), (end * (L / 2 + 0.25), y, zt / 2), K.rgb(150, 154, 160), 0.1))
    parts.append(box("Apron", (L + 40, Wd + 30, 0.6), (0, 0, 0.3), K.rgb(150, 150, 146), 0.2))
    o = K.join(parts, "HangarOne")
    K.smooth(o, 35)
    return o


for fn, nm, view in ((dish, "TheDish", dict(elev=16, azim=150, cam_dist=110)),
                     (lick, "LickObservatory", dict(elev=18, azim=20, cam_dist=80)),
                     (hangar, "HangarOne", dict(elev=16, azim=40, cam_dist=260))):
    o = fn()
    print(nm, "tris", K.tris(o))
    K.export(os.path.join(OUT, nm + ".fbx"), [o])
    K.preview(os.path.join(OUT, nm + ".png"), [o], size=(1000, 560), **view)
print("EXPORTED")
