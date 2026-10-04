"""icons.py -- PLAN v6 phase V8: the HUD's icons as renders (27 Sep 2026).

ART.md: "Icons are Cycles renders of the game's own models, all under the
same light rig: warm key light from the upper left, cool rim light, soft
contact shadow, 256 px, transparent. No flat clip-art." The HUD was flat
white Kenney glyphs on coloured squares -- the "2019" tell.

One clay-like style for all nine (bevelled, a little coat, palette colours),
one rig, one camera angle. icons_post.py adds the dark sticker outline and
downsamples to 256.

Keys match the UIKit.ICON keys they replace:
  phone   the PHONE rail button      grid   INDEX (fanned ID badges)
  bag     BAG                        home   DECOR (a potted plant = vibe)
  musicOn music toggle (headphones)  code   WRITE CODE (open laptop, </>)
  rocket  LAUNCH (the game's rocket) target the quest card
  coin    the money counter

Run:  blender -b --python icons.py [-- key key ...]
"""
import bpy
import bmesh
import math
import os
import sys
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import svkit as K  # noqa: E402

OUT = os.path.join(HERE, "out", "icons")
os.makedirs(OUT, exist_ok=True)
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
FONT = "C:/Windows/Fonts/segoeuib.ttf"


def lin(c):
    return tuple(K.srgb_to_linear(x / 255.0) for x in c) + (1.0,)


PAPER = (243, 239, 230)
INK = (30, 37, 48)
GOLD = (255, 194, 61)
ORANGE = (246, 134, 58)
GREEN = (76, 196, 108)
BLUE = (70, 140, 230)
PURPLE = (150, 110, 230)
RED = (228, 72, 72)
OAK = (192, 138, 85)
SKIN = (238, 196, 160)
LEAF = (86, 170, 84)
LEAF2 = (60, 138, 70)
SILVER = (206, 210, 216)


# ------------------------------------------------------------------ scene
def setup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = (d.type == "OPTIX")
    sc.cycles.device = "GPU"
    sc.cycles.samples = 128
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = 512
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.exposure = 0.0
    w = bpy.data.worlds.new("W")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.62, 0.68, 0.8, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.75
    return sc


MATS = {}


def mat(color, rough=0.42, metal=0.0, coat=0.35, emit=0.0):
    key = (color, rough, metal, coat, emit)
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new("M%d" % len(MATS))
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = lin(color)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    try:
        p.inputs["Coat Weight"].default_value = coat
    except KeyError:
        pass
    if emit > 0:
        p.inputs["Emission Color"].default_value = lin(color)
        p.inputs["Emission Strength"].default_value = emit
    MATS[key] = m
    return m


def put(o, m, smooth=True):
    o.data.materials.clear()
    o.data.materials.append(m)
    if smooth:
        K.smooth(o, 40)
    return o


def rbox(size, loc, m, bev=0.08, seg=4, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bev > 0:
        b = o.modifiers.new("B", "BEVEL")
        b.width = bev
        b.segments = seg
        K.apply_mods(o)
    return put(o, m)


def cyl(r, depth, loc, m, rot=(0, 0, 0), verts=48, bev=0.03):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, vertices=verts, location=loc, rotation=rot)
    o = bpy.context.active_object
    if bev > 0:
        b = o.modifiers.new("B", "BEVEL")
        b.width = bev
        b.segments = 3
        b.limit_method = "ANGLE"
        K.apply_mods(o)
    return put(o, m)


def ball(r, loc, m, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=32, ring_count=16, location=loc)
    o = bpy.context.active_object
    o.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    return put(o, m)


def torus(R, r, loc, m, rot=(0, 0, 0), arc=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=48, minor_segments=16,
                                     location=loc, rotation=rot)
    o = bpy.context.active_object
    if arc is not None:
        # keep only the part of the ring above local z >= arc (a handle / a headband)
        bm = bmesh.new()
        bm.from_mesh(o.data)
        kill = [v for v in bm.verts if v.co.y < arc]
        bmesh.ops.delete(bm, geom=kill, context="VERTS")
        bm.to_mesh(o.data)
        bm.free()
    return put(o, m)


def text(body, size, loc, m, rot=(math.radians(90), 0, 0), extrude=0.04):
    bpy.ops.object.text_add(location=loc, rotation=rot)
    o = bpy.context.active_object
    o.data.body = body
    if os.path.exists(FONT):
        o.data.font = bpy.data.fonts.load(FONT, check_existing=True)
    o.data.size = size
    o.data.extrude = extrude
    o.data.align_x = "CENTER"
    o.data.align_y = "CENTER"
    bpy.ops.object.convert(target="MESH")
    return put(bpy.context.active_object, m, smooth=False)


def group(objs, rot=(0, 0, 0), loc=(0, 0, 0)):
    """Parent everything to one empty so the whole icon can be posed."""
    e = bpy.data.objects.new("Pose", None)
    bpy.context.scene.collection.objects.link(e)
    for o in objs:
        o.parent = e
    e.rotation_euler = rot
    e.location = loc
    bpy.context.view_layer.update()
    return e


# ------------------------------------------------------------------ the rig
def rig_and_render(name, elev=18, azim=24, margin=1.12):
    sc = bpy.context.scene
    objs = [o for o in sc.objects if o.type == "MESH"]
    mins = Vector((1e9, 1e9, 1e9))
    maxs = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            for i in range(3):
                mins[i] = min(mins[i], w[i])
                maxs[i] = max(maxs[i], w[i])
    center = (mins + maxs) / 2
    radius = (maxs - mins).length / 2
    # soft contact shadow: a shadow catcher just under the object
    # (no shadow catcher: cropped to the icon its soft shadow became a grey slab
    # under every object; the sticker outline grounds the icon instead)
    # camera
    cd = bpy.data.cameras.new("C")
    cd.lens = 70
    cam = bpy.data.objects.new("C", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    fov = 2 * math.atan(18 / cd.lens)
    dist = radius * margin / math.sin(fov / 2)
    e, a = math.radians(elev), math.radians(azim)
    cam.location = center + Vector((dist * math.cos(e) * math.sin(a), -dist * math.cos(e) * math.cos(a), dist * math.sin(e)))
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()

    # lights scaled to the object: warm key upper-left, cool rim back-right, soft fill
    def area(n, pos, energy, size, color):
        ld = bpy.data.lights.new(n, "AREA")
        ld.energy = energy * radius * radius
        ld.size = size * radius
        ld.color = color
        lo = bpy.data.objects.new(n, ld)
        sc.collection.objects.link(lo)
        lo.location = center + Vector(pos) * radius
        lo.rotation_euler = (center - lo.location).to_track_quat("-Z", "Y").to_euler()
    area("Key", (-1.8, -1.9, 4.4), 240, 1.6, (1.0, 0.93, 0.84))   # high: a short shadow
    area("Rim", (2.4, 2.8, 2.2), 230, 1.2, (0.72, 0.82, 1.0))
    area("Fill", (3.0, -2.6, 0.6), 80, 2.5, (0.85, 0.9, 1.0))
    sc.render.filepath = os.path.join(OUT, "raw_%s.png" % name)
    bpy.ops.render.render(write_still=True)


# ------------------------------------------------------------------ the nine
def icon_phone():
    body = rbox((1.0, 0.14, 2.0), (0, 0, 1.0), mat(INK, 0.3), bev=0.16)
    screen = rbox((0.86, 0.02, 1.8), (0, -0.075, 1.0), mat((24, 34, 52), 0.25, emit=0.6), bev=0.1)
    b1 = rbox((0.56, 0.03, 0.26), (-0.12, -0.09, 1.45), mat(PAPER, 0.4, emit=0.25), bev=0.1)
    b2 = rbox((0.52, 0.03, 0.26), (0.13, -0.09, 1.08), mat(GREEN, 0.4, emit=0.35), bev=0.1)
    b3 = rbox((0.44, 0.03, 0.26), (-0.15, -0.09, 0.71), mat(PAPER, 0.4, emit=0.25), bev=0.1)
    cam_dot = cyl(0.04, 0.03, (0, -0.08, 1.84), mat((60, 70, 86)), rot=(math.radians(90), 0, 0))
    group([body, screen, b1, b2, b3, cam_dot], rot=(math.radians(8), 0, math.radians(-14)))


def icon_bag():
    m = mat(ORANGE, 0.55, coat=0.15)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1)
    for v in bm.verts:
        s = 1.0 if v.co.z > 0 else 0.86          # a little wider at the top
        v.co = Vector((v.co.x * 1.3 * s, v.co.y * 0.66 * s, v.co.z * 1.3 + 0.65))
    body = K.mesh_obj("Bag", bm)
    bv = body.modifiers.new("B", "BEVEL")
    bv.width = 0.05
    bv.segments = 3
    K.apply_mods(body)
    put(body, m)
    rim = rbox((1.34, 0.7, 0.12), (0, 0, 1.28), mat((214, 108, 40), 0.55, coat=0.1), bev=0.04)
    h1 = torus(0.34, 0.045, (0, -0.2, 1.3), mat(INK, 0.4), rot=(math.radians(90), 0, 0), arc=0.0)
    h2 = torus(0.34, 0.045, (0, 0.2, 1.3), mat(INK, 0.4), rot=(math.radians(90), 0, 0), arc=0.0)
    tag = rbox((0.36, 0.03, 0.24), (0.34, -0.35, 0.95), mat(PAPER, 0.5), bev=0.04)
    dot = cyl(0.07, 0.02, (0.34, -0.37, 0.95), mat(GOLD, 0.35), rot=(math.radians(90), 0, 0), bev=0.0)
    group([body, rim, h1, h2, tag, dot], rot=(0, 0, math.radians(-18)))


def badge(x, rot_y, color, z=1.0):
    card = rbox((1.0, 0.07, 1.38), (0, 0, 0), mat(PAPER, 0.45), bev=0.1)
    band = rbox((1.0, 0.075, 0.34), (0, -0.004, 0.52), mat(color, 0.45), bev=0.08)
    face = cyl(0.23, 0.02, (0, -0.045, 0.05), mat(SKIN, 0.5), rot=(math.radians(90), 0, 0), bev=0.0)
    hair = cyl(0.24, 0.018, (0, -0.052, 0.13), mat((70, 50, 40), 0.5), rot=(math.radians(90), 0, 0), bev=0.0)
    hair.scale = (1.0, 0.55, 1.0)
    line1 = rbox((0.6, 0.02, 0.07), (0, -0.045, -0.3), mat((180, 184, 192), 0.5), bev=0.02)
    line2 = rbox((0.42, 0.02, 0.07), (0, -0.045, -0.44), mat((200, 204, 210), 0.5), bev=0.02)
    clip = torus(0.1, 0.03, (0, 0, 0.78), mat(SILVER, 0.25, metal=0.9), rot=(math.radians(90), 0, 0))
    e = group([card, band, face, hair, line1, line2, clip], rot=(0, rot_y, 0), loc=(x, 0, z))
    return e


def icon_grid():
    badge(-0.55, math.radians(16), PURPLE, 0.95)
    badge(0.55, math.radians(-16), GOLD, 0.95)
    b = badge(0.0, 0.0, BLUE, 1.05)
    b.location.y = -0.12


def icon_home():
    pot = K.lathe("Pot", [(0.0, 0.0), (0.42, 0.0), (0.5, 0.06), (0.62, 0.78), (0.66, 0.84), (0.66, 0.92), (0.58, 0.92)], segments=48)
    put(pot, mat((236, 232, 222), 0.45, coat=0.4))
    soil = cyl(0.57, 0.04, (0, 0, 0.88), mat((88, 62, 44), 0.9), bev=0.0)
    band = cyl(0.645, 0.1, (0, 0, 0.62), mat(OAK, 0.5), bev=0.02)
    leaves = []
    for k, (a, tilt, h, col) in enumerate([(0, 12, 1.25, LEAF), (72, 30, 1.0, LEAF2), (144, 26, 1.1, LEAF),
                                           (216, 32, 0.95, LEAF2), (288, 24, 1.15, LEAF), (40, 5, 1.35, LEAF2)]):
        lf = ball(0.25, (0, 0, 0), mat(col, 0.5, coat=0.2), scale=(0.55, 0.22, 1.0))
        lf.location = (0, 0, 0.9 + h * 0.5)
        pivot = group([lf], rot=(math.radians(tilt), 0, math.radians(a)))
        pivot.location = (0, 0, 0)
        lf.location = (0, 0, h * 0.5 + 0.15)
        pivot.location = (0, 0, 0.88)
        leaves.append(pivot)
    bpy.context.view_layer.update()


def icon_musicOn():
    band = torus(0.78, 0.09, (0, 0, 1.0), mat(INK, 0.35), rot=(math.radians(90), 0, 0), arc=-0.1)
    pad = torus(0.78, 0.06, (0, 0.0, 1.0), mat((70, 78, 92), 0.6), rot=(math.radians(90), 0, 0), arc=0.35)
    cups = []
    for sx in (-1, 1):
        c1 = cyl(0.3, 0.26, (sx * 0.8, 0, 0.9), mat(GOLD, 0.3, metal=0.3), rot=(0, math.radians(90), 0), bev=0.05)
        c2 = cyl(0.26, 0.1, (sx * 0.62, 0, 0.9), mat(INK, 0.7), rot=(0, math.radians(90), 0), bev=0.03)
        cups += [c1, c2]
    group([band, pad] + cups, rot=(math.radians(-8), 0, math.radians(-22)))


def icon_code():
    base = rbox((1.8, 1.2, 0.1), (0, 0, 0.05), mat(SILVER, 0.3, metal=0.6), bev=0.05)
    keys = rbox((1.5, 0.66, 0.02), (0, 0.06, 0.105), mat((150, 156, 166), 0.5), bev=0.01)
    pad = rbox((0.5, 0.3, 0.012), (0, -0.4, 0.103), mat((176, 182, 190), 0.4), bev=0.01)
    lid = rbox((1.8, 0.08, 1.16), (0, 0.62, 0.66), mat(SILVER, 0.3, metal=0.6), bev=0.05, rot=(math.radians(-14), 0, 0))
    scr = rbox((1.6, 0.02, 0.98), (0, 0.575, 0.67), mat((22, 30, 44), 0.3, emit=0.3), bev=0.02, rot=(math.radians(-14), 0, 0))
    code = text("</>", 0.72, (0, 0.555, 0.68), mat(GREEN, 0.3, emit=2.6), rot=(math.radians(90 - 14), 0, 0), extrude=0.02)
    group([base, keys, pad, lid, scr, code], rot=(math.radians(10), 0, math.radians(-10)))   # screen toward the camera


def icon_rocket():
    path = os.path.join(HERE, "out", "IMPORT_THESE", "Rocket.fbx")
    bpy.ops.import_scene.fbx(filepath=path)
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    m = bpy.data.materials.new("VC")
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Roughness"].default_value = 0.4
    try:
        p.inputs["Coat Weight"].default_value = 0.35
    except KeyError:
        pass
    at = nt.nodes.new("ShaderNodeVertexColor")
    nt.links.new(at.outputs["Color"], p.inputs["Base Color"])
    for o in objs:
        if o.data.color_attributes:
            at.layer_name = o.data.color_attributes[0].name
        put(o, m)
    # stand it on the diagonal like a launch: nose up-right
    mins = min((o.matrix_world @ Vector(c)).z for o in objs for c in o.bound_box)
    group(objs, rot=(0, math.radians(38), 0), loc=(0, 0, -mins))


def icon_target():
    rings = [(1.0, RED), (0.8, PAPER), (0.6, RED), (0.4, PAPER), (0.2, RED)]
    parts = []
    for k, (r, c) in enumerate(rings):
        parts.append(cyl(r, 0.12 + 0.03 * k, (0, -0.015 * k, 1.05), mat(c, 0.45), rot=(math.radians(90), 0, 0), bev=0.03))
    stand = rbox((0.14, 0.14, 0.9), (0, 0.18, 0.45), mat(OAK, 0.5), bev=0.03, rot=(math.radians(-12), 0, 0))
    shaft = cyl(0.05, 1.0, (0.28, -0.42, 1.25), mat(GOLD, 0.3, metal=0.5), rot=(math.radians(62), 0, math.radians(-35)))
    tip = cyl(0.05, 0.14, (0.05, -0.18, 1.08), mat(INK, 0.4), rot=(math.radians(62), 0, math.radians(-35)))
    fl = rbox((0.4, 0.03, 0.3), (0.48, -0.66, 1.42), mat(GREEN, 0.5), bev=0.02, rot=(math.radians(62), 0, math.radians(-35)))
    group(parts + [stand, shaft, tip, fl], rot=(0, 0, math.radians(-16)))


def icon_coin():
    c = cyl(1.0, 0.24, (0, 0, 0), mat(GOLD, 0.28, metal=0.85, coat=0.3), rot=(math.radians(90), 0, 0), verts=64, bev=0.07)
    rim = torus(0.86, 0.04, (0, -0.125, 0), mat((230, 164, 40), 0.3, metal=0.85), rot=(math.radians(90), 0, 0))
    d = text("$", 1.15, (0, -0.15, -0.02), mat((170, 102, 22), 0.35, metal=0.7), extrude=0.09)
    group([c, rim, d], rot=(math.radians(-6), math.radians(-6), math.radians(-12)), loc=(0, 0, 1.05))


def icon_hire():
    """A new hire: a friendly bust holding up an ID badge."""
    body = ball(0.78, (0, 0, 0.62), mat(BLUE, 0.5), scale=(1.0, 0.72, 0.8))
    head = ball(0.46, (0, 0, 1.55), mat(SKIN, 0.55))
    hair = ball(0.48, (0, 0.06, 1.72), mat((70, 50, 40), 0.6), scale=(1.0, 1.0, 0.62))
    eyes = [ball(0.06, (sx * 0.16, -0.43, 1.6), mat(INK, 0.3)) for sx in (-1, 1)]
    card = rbox((0.6, 0.05, 0.78), (0.42, -0.62, 0.72), mat(PAPER, 0.45), bev=0.06, rot=(math.radians(-8), 0, math.radians(-10)))
    band = rbox((0.6, 0.055, 0.18), (0.42, -0.64, 0.99), mat(GOLD, 0.4), bev=0.04, rot=(math.radians(-8), 0, math.radians(-10)))
    group([body, head, hair, card, band] + eyes, rot=(0, 0, math.radians(-10)))


def icon_hq():
    """The HQ: stacked rounded slabs, glass between, a green roof."""
    parts = []
    for i, (w, z) in enumerate([(2.2, 0.0), (2.0, 0.62), (1.7, 1.24)]):
        parts.append(rbox((w, 1.4, 0.14), (0, 0, z + 0.07), mat(PAPER, 0.4), bev=0.06))
        parts.append(rbox((w - 0.16, 1.24, 0.46), (0, 0, z + 0.37), mat((96, 150, 190), 0.12, metal=0.2, coat=0.6), bev=0.03))
        for k in range(5):
            x = -w / 2 + 0.2 + k * (w - 0.4) / 4
            parts.append(rbox((0.05, 0.02, 0.46), (x, -0.63, z + 0.37), mat(OAK, 0.5), bev=0.0))
    parts.append(rbox((1.8, 1.3, 0.14), (0, 0, 1.93), mat(PAPER, 0.4), bev=0.06))
    parts.append(rbox((1.4, 1.0, 0.1), (0, 0, 2.03), mat(LEAF, 0.6), bev=0.04))
    parts.append(rbox((0.5, 0.06, 0.16), (0, -0.72, 0.5), mat(ORANGE, 0.4), bev=0.02))
    group(parts, rot=(0, 0, math.radians(-24)))


def icon_key():
    """The apartment: a house key on a tag."""
    gold = mat(GOLD, 0.25, metal=0.9)
    ring = torus(0.42, 0.11, (0, 0, 1.6), gold, rot=(math.radians(90), 0, 0))
    shaft = rbox((0.2, 0.1, 1.3), (0, 0, 0.62), gold, bev=0.03)
    t1 = rbox((0.34, 0.1, 0.14), (0.24, 0, 0.18), gold, bev=0.02)
    t2 = rbox((0.26, 0.1, 0.14), (0.2, 0, 0.46), gold, bev=0.02)
    tag = rbox((0.62, 0.05, 0.42), (-0.62, -0.02, 1.9), mat(ORANGE, 0.45), bev=0.06, rot=(0, math.radians(20), 0))
    house = rbox((0.24, 0.06, 0.18), (-0.64, -0.06, 1.86), mat(PAPER, 0.4), bev=0.02, rot=(0, math.radians(20), 0))
    group([ring, shaft, t1, t2, tag, house], rot=(0, math.radians(-28), math.radians(-12)))


def icon_car():
    """A sleek EV coupe in the brand green."""
    body = rbox((1.0, 2.2, 0.42), (0, 0, 0.42), mat(GREEN, 0.25, metal=0.4, coat=0.8), bev=0.18)
    cab = rbox((0.86, 1.1, 0.38), (0, 0.12, 0.8), mat((40, 52, 70), 0.1, metal=0.3, coat=0.9), bev=0.16)
    parts = [body, cab]
    for sx in (-1, 1):
        for sy in (-0.72, 0.72):
            parts.append(cyl(0.24, 0.18, (sx * 0.48, sy, 0.24), mat(INK, 0.6), rot=(0, math.radians(90), 0), bev=0.04))
            parts.append(cyl(0.13, 0.19, (sx * 0.49, sy, 0.24), mat(SILVER, 0.2, metal=0.9), rot=(0, math.radians(90), 0), bev=0.02))
    parts.append(rbox((0.8, 0.04, 0.06), (0, -1.1, 0.5), mat((255, 240, 200), 0.2, emit=2.0), bev=0.01))
    group(parts, rot=(0, 0, math.radians(-35)))


def icon_office():
    """The open office: a desk, a monitor, a chair."""
    top = rbox((1.8, 0.9, 0.08), (0, 0, 0.9), mat(OAK, 0.45), bev=0.03)
    legs = [rbox((0.07, 0.07, 0.86), (sx * 0.8, sy * 0.38, 0.43), mat(INK, 0.4), bev=0.0) for sx in (-1, 1) for sy in (-1, 1)]
    mon = rbox((0.9, 0.05, 0.55), (0, 0.22, 1.35), mat(INK, 0.3), bev=0.03)
    scr = rbox((0.82, 0.02, 0.47), (0, 0.19, 1.35), mat((70, 150, 230), 0.2, emit=0.8), bev=0.02)
    stand = rbox((0.06, 0.06, 0.3), (0, 0.24, 1.0), mat(INK, 0.4), bev=0.0)
    seat = rbox((0.6, 0.6, 0.12), (0.2, -0.75, 0.55), mat(BLUE, 0.5), bev=0.05)
    back = rbox((0.6, 0.1, 0.6), (0.2, -1.02, 0.9), mat(BLUE, 0.5), bev=0.05)
    post = cyl(0.04, 0.5, (0.2, -0.75, 0.28), mat(INK, 0.4))
    group([top, mon, scr, stand, seat, back, post] + legs, rot=(0, 0, math.radians(-28)))


def icon_studio():
    """The design studio: a palette of paint and a pencil."""
    pal = cyl(1.0, 0.08, (0, 0, 0.5), mat(OAK, 0.45), rot=(math.radians(70), 0, 0), verts=40, bev=0.03)
    dots = []
    for k, c in enumerate([RED, GOLD, GREEN, BLUE, PURPLE]):
        a = math.radians(40 + k * 42)
        dots.append(ball(0.14, (math.cos(a) * 0.62, -0.1, 0.5 + math.sin(a) * 0.5), mat(c, 0.35, coat=0.6), scale=(1, 0.5, 1)))
    pencil = cyl(0.07, 1.8, (0.3, -0.25, 0.7), mat(GOLD, 0.4), rot=(math.radians(20), math.radians(55), 0), verts=6, bev=0.0)
    group([pal, pencil] + dots, rot=(0, 0, math.radians(-10)))


def icon_cafe():
    """The cafe: a coffee cup on a saucer, steam rising."""
    saucer = cyl(0.8, 0.08, (0, 0, 0.04), mat(PAPER, 0.35), verts=40, bev=0.03)
    cup = K.lathe("Cup", [(0.0, 0.1), (0.42, 0.1), (0.55, 0.3), (0.62, 0.9), (0.56, 0.9)], segments=40)
    put(cup, mat(PAPER, 0.35))
    coffee = cyl(0.56, 0.02, (0, 0, 0.84), mat((96, 60, 36), 0.3), verts=40, bev=0.0)
    handle = torus(0.2, 0.06, (0.66, 0, 0.55), mat(PAPER, 0.35), rot=(math.radians(90), 0, 0))
    band = cyl(0.61, 0.14, (0, 0, 0.55), mat(GREEN, 0.4), verts=40, bev=0.02)
    steam = [ball(0.12 + 0.03 * k, (math.sin(k) * 0.15, 0, 1.05 + k * 0.25), mat((236, 236, 236), 0.6), scale=(1, 1, 1.2)) for k in range(3)]
    group([saucer, cup, coffee, handle, band] + steam, rot=(0, 0, math.radians(-20)))


def icon_servers():
    """The server room: a rack of blades with status lights."""
    rack = rbox((1.1, 0.9, 2.0), (0, 0, 1.0), mat((52, 58, 70), 0.4, metal=0.3), bev=0.06)
    parts = [rack]
    for i in range(6):
        z = 0.3 + i * 0.28
        parts.append(rbox((0.94, 0.04, 0.2), (0, -0.46, z), mat((78, 86, 100), 0.35, metal=0.4), bev=0.01))
        parts.append(ball(0.035, (0.34, -0.49, z), mat(GREEN if i % 3 else (80, 170, 255), 0.2, emit=3.0)))
        parts.append(ball(0.035, (0.25, -0.49, z), mat(GREEN, 0.2, emit=3.0)))
    group(parts, rot=(0, 0, math.radians(-24)))


def icon_check():
    """Done: a green badge with a white tick."""
    badge = cyl(1.0, 0.22, (0, 0, 0), mat(GREEN, 0.3, coat=0.7), rot=(math.radians(90), 0, 0), verts=48, bev=0.06)
    a = rbox((0.22, 0.08, 0.6), (-0.26, -0.14, -0.08), mat(PAPER, 0.3), bev=0.05, rot=(0, math.radians(-45), 0))
    b = rbox((0.22, 0.08, 1.05), (0.18, -0.14, 0.08), mat(PAPER, 0.3), bev=0.05, rot=(0, math.radians(35), 0))
    group([badge, a, b], rot=(0, 0, math.radians(-8)), loc=(0, 0, 1.0))


def icon_gift():
    """DAILY: a gift box with a gold ribbon and bow (v5 UI pass, 29 Sep)."""
    red = mat(RED, 0.45, coat=0.3)
    gold = mat(GOLD, 0.3, metal=0.35, coat=0.5)
    box = rbox((1.3, 1.3, 1.0), (0, 0, 0.5), red, bev=0.07)
    lid = rbox((1.44, 1.44, 0.3), (0, 0, 1.12), mat((200, 56, 56), 0.45, coat=0.3), bev=0.07)
    rib1 = rbox((0.26, 1.47, 1.32), (0, 0, 0.64), gold, bev=0.03)
    rib2 = rbox((1.47, 0.26, 1.32), (0, 0, 0.64), gold, bev=0.03)
    bow1 = torus(0.26, 0.085, (-0.24, 0, 1.44), gold, rot=(math.radians(90), 0, math.radians(18)))
    bow2 = torus(0.26, 0.085, (0.24, 0, 1.44), gold, rot=(math.radians(90), 0, math.radians(-18)))
    knot = ball(0.13, (0, 0, 1.32), gold)
    group([box, lid, rib1, rib2, bow1, bow2, knot], rot=(0, 0, math.radians(-22)))


def icon_trophy():
    """RANKS: a gold cup on a dark plinth (v5 UI pass, 29 Sep)."""
    gold = mat(GOLD, 0.25, metal=0.55, coat=0.55)
    cup = K.lathe("Cup", [(0.0, 1.0), (0.18, 1.0), (0.55, 1.2), (0.72, 1.62), (0.77, 2.05), (0.69, 2.05)], segments=48)
    put(cup, gold)
    knob = ball(0.2, (0, 0, 0.98), gold)
    stem = cyl(0.12, 0.5, (0, 0, 0.72), gold, verts=32)
    base = rbox((1.0, 0.8, 0.4), (0, 0, 0.22), mat(INK, 0.4), bev=0.06)
    plate = rbox((0.62, 0.03, 0.2), (0, -0.41, 0.22), gold, bev=0.02)
    h1 = torus(0.26, 0.06, (-0.8, 0, 1.6), gold, rot=(math.radians(90), 0, 0))
    h2 = torus(0.26, 0.06, (0.8, 0, 1.6), gold, rot=(math.radians(90), 0, 0))
    group([cup, knob, stem, base, plate, h1, h2], rot=(0, 0, math.radians(-12)))


ICONS = {
    "phone": icon_phone, "bag": icon_bag, "grid": icon_grid, "home": icon_home, "musicOn": icon_musicOn,
    "code": icon_code, "rocket": icon_rocket, "target": icon_target, "coin": icon_coin,
    "hire": icon_hire, "hq": icon_hq, "key": icon_key, "car": icon_car, "office": icon_office,
    "studio": icon_studio, "cafe": icon_cafe, "servers": icon_servers, "check": icon_check,
    "gift": icon_gift, "trophy": icon_trophy,
}
for key in (ARGS or list(ICONS)):
    setup()
    MATS.clear()
    ICONS[key]()
    rig_and_render(key)
print("ICONS DONE")
