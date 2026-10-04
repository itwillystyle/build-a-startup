"""Caltrain: a Bombardier-style double-deck coach and a diesel locomotive.
Rounded roof profile, inset window bands on both decks, the red stripe,
doors, wheel trucks. X is the length (the train runs along X in the game).
Run: blender -b --python caltrain.py"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
from mathutils import Vector
import svkit as K

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
os.makedirs(OUT, exist_ok=True)

SILVER = K.rgb(200, 204, 208)
RED = K.rgb(200, 36, 40)
GLASS = K.rgb(34, 42, 56)
DARK = K.rgb(38, 40, 46)
ROOF = K.rgb(150, 154, 160)
DOOR = K.rgb(172, 176, 182)
LAMP = K.rgb(255, 238, 190)

L, W, H = 58.0, 9.6, 13.0


def section(w, h, roof=1.4, r=0.6, n=6):
    """Cross-section (y, z) of a coach: small rounded bottom corners, straight
    sides, an arched roof. Counter-clockwise."""
    pts = []
    hw = w / 2
    # bottom-left corner -> bottom-right
    for k in range(n + 1):
        a = math.pi + (math.pi / 2) * k / n
        pts.append((-hw + r + r * math.cos(a), r + r * math.sin(a)))
    for k in range(n + 1):
        a = 1.5 * math.pi + (math.pi / 2) * k / n
        pts.append((hw - r + r * math.cos(a), r + r * math.sin(a)))
    # right side up to the roof spring, then the roof arc to the left
    pts.append((hw, h - roof))
    for k in range(1, 2 * n):
        t = k / (2 * n)
        y = hw - w * t
        z = (h - roof) + roof * math.sin(math.pi * t)
        pts.append((y, z))
    pts.append((-hw, h - roof))
    return pts


def extrude_section(name, pts, x0, x1):
    bm = bmesh.new()
    a = [bm.verts.new((x0, y, z)) for (y, z) in pts]
    b = [bm.verts.new((x1, y, z)) for (y, z) in pts]
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(a)))
    bm.faces.new(b)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return K.mesh_obj(name, bm)


def box(name, size, loc, color, bev=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bev > 0:
        K.bevel(o, bev, 2, 50)
        K.apply_mods(o)
    K.paint(o, K.shaded(color))
    return o


def cyl(name, r, depth, loc, rot, color, verts=16):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, vertices=verts, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    K.paint(o, K.shaded(color))
    return o


def coach(name, cab=False, loco=False):
    K.reset()
    parts = []
    lift = 1.6
    body = extrude_section("Body", [(y, z + lift) for (y, z) in section(W, H - lift)], -L / 2, L / 2)
    K.bevel(body, 0.35, 2, 60); K.apply_mods(body)
    K.paint(body, lambda p, n: ROOF if (p.z > H - 1.1) else K.shaded(SILVER, 1.04, 0.82)(p, n))
    parts.append(body)
    for side in (-1, 1):
        y = side * (W / 2 + 0.03)
        # the red stripe along the lower body
        parts.append(box("Stripe", (L - 1.2, 0.08, 1.1), (0, y, lift + 1.6), RED, 0.02))
        if loco:
            continue                  # the locomotive has louvres, not passenger windows
        # inset window bands: lower and upper deck, broken by the doors
        for (x0, x1) in ((-L / 2 + 3.5, -8.5), (-4.5, 4.5), (8.5, L / 2 - 3.5)):
            cx, lx = (x0 + x1) / 2, (x1 - x0)
            parts.append(box("WinLow", (lx, 0.1, 2.1), (cx, y, lift + 4.3), GLASS, 0.3))
            parts.append(box("WinHigh", (lx, 0.1, 2.1), (cx, y, lift + 8.2), GLASS, 0.3))
        for dx in (-6.5, 6.5):
            parts.append(box("Door", (2.6, 0.1, 6.2), (dx, y, lift + 3.6), DOOR, 0.15))
            parts.append(box("DoorWin", (1.6, 0.12, 1.8), (dx, y, lift + 5.2), GLASS, 0.12))
    # wheel trucks
    for tx in (-L / 2 + 7.5, L / 2 - 7.5):
        parts.append(box("Truck", (7.0, 7.4, 1.0), (tx, 0, 1.2), DARK, 0.1))
        for wx in (-2.2, 2.2):
            for side in (-1, 1):
                parts.append(cyl("Wheel", 1.0, 0.5, (tx + wx, side * 3.6, 1.0), (math.radians(90), 0, 0), DARK))
    if cab or loco:
        # a raked cab face at the +X end: windscreen, the red nose, two headlights
        nose_x = L / 2
        parts.append(box("Nose", (1.2, W - 0.2, 5.2), (nose_x + 0.3, 0, lift + 2.8), RED, 0.4))
        parts.append(box("Windscreen", (0.3, W - 2.4, 2.8), (nose_x + 0.12, 0, lift + 8.4), GLASS, 0.25))
        parts.append(box("CabBand", (0.25, W - 0.6, 0.5), (nose_x + 0.1, 0, lift + 6.6), RED, 0.1))
        for side in (-1, 1):
            parts.append(cyl("Headlight", 0.45, 0.3, (nose_x + 0.95, side * 3.0, lift + 5.8), (0, math.radians(90), 0), LAMP, 12))
    if loco:
        # the locomotive: louvres and a roof fan housing instead of passenger windows
        for side in (-1, 1):
            y = side * (W / 2 + 0.05)
            for k in range(6):
                parts.append(box("Louvre", (2.4, 0.08, 2.6), (-L / 2 + 8 + k * 5.5, y, lift + 8.0), K.rgb(120, 124, 130), 0.05))
        for fx in (-14, -4, 6):
            parts.append(cyl("Fan", 1.6, 0.6, (fx, 0, H + 0.1), (0, 0, 0), DARK, 14))
    o = K.join(parts, name)
    K.smooth(o, 35)
    return o


made = []
for nm, cab, loco in (("Caltrain_Car", False, False), ("Caltrain_Cab", True, False), ("Caltrain_Loco", False, True)):
    o = coach(nm, cab, loco)
    if loco:
        # the loco's cab faces -X (it leads westbound in the game): mirror it
        o.scale.x = -1
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(scale=True)
        bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT"); bpy.ops.mesh.normals_make_consistent(inside=False); bpy.ops.object.mode_set(mode="OBJECT")
    print(nm, "tris", K.tris(o))
    K.export(os.path.join(OUT, nm + ".fbx"), [o])
    K.preview(os.path.join(OUT, nm + ".png"), [o], size=(1200, 500), elev=12, azim=(-58 if loco else 58), cam_dist=85)
print("EXPORTED")
