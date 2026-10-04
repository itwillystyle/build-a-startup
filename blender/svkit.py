"""svkit -- the Blender side of Build a Startup's asset pipeline (v3.4 Phase W).

Every asset script does:  reset() -> build parts -> paint() each part ->
join() into ONE mesh (one MeshPart, one draw call in Roblox) -> preview()
to a PNG I can look at -> export() an FBX for Roblox's 3D importer.

Colour is VERTEX colour, not materials: Roblox's importer drops per-material
diffuse colours (measured on the Kenney nature kit: every tree came in grey)
but keeps vertex colours (the Quaternius buildings kept theirs).
1 Blender unit = 1 Roblox stud while modelling; scale is normalised in the
game by bounding box anyway (ScaleTo), so the importer's unit guess is harmless.
"""
import bpy
import bmesh
import math
import random
from mathutils import Vector, Matrix, noise


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def mesh_obj(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return link(bpy.data.objects.new(name, me))


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgb(r, g, b):
    return (r / 255.0, g / 255.0, b / 255.0)


def paint(obj, color_fn):
    """color_fn(world_pos, normal) -> (r, g, b) in 0..1 sRGB. Paints every face corner."""
    me = obj.data
    if "Col" not in me.color_attributes:
        me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
    attr = me.color_attributes["Col"]
    mw = obj.matrix_world
    for poly in me.polygons:
        n = (mw.to_3x3() @ poly.normal).normalized()
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            c = color_fn(mw @ v, n)
            attr.data[li].color_srgb = (c[0], c[1], c[2], 1.0) if hasattr(attr.data[li], "color_srgb") else (c[0], c[1], c[2], 1.0)
    me.color_attributes.active_color = attr
    return obj


def flat(color):
    return lambda p, n: color


def shaded(color, top=1.08, bottom=0.72):
    """Fake sky light: tops lighter, undersides darker -- reads as form in any lighting."""
    def f(p, n):
        k = bottom + (top - bottom) * (n.z * 0.5 + 0.5)
        return tuple(min(1.0, c * k) for c in color)
    return f


def apply_mods(obj):
    bpy.context.view_layer.objects.active = obj
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def bevel(obj, width=0.1, segments=2, angle=40):
    m = obj.modifiers.new("Bevel", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(angle)
    return m


def smooth(obj, angle=40):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle))
    except Exception:
        bpy.ops.object.shade_smooth()
    obj.select_set(False)


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    o.data.name = name
    return o


def lathe(name, profile, segments=24):
    """Revolve a list of (radius, z) points around Z. Returns an object."""
    bm = bmesh.new()
    rings = []
    for (r, z) in profile:
        ring = []
        for i in range(segments):
            a = 2 * math.pi * i / segments
            ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
        rings.append(ring)
    for k in range(len(rings) - 1):
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
    # caps where the radius is non-zero
    if profile[0][0] > 1e-4:
        bm.faces.new(list(reversed(rings[0])))
    if profile[-1][0] > 1e-4:
        bm.faces.new(rings[-1])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_obj(name, bm)


def tris(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def preview(path, objs=None, size=(900, 700), cam_dist=None, elev=18, azim=35, target=None):
    """A quick Workbench render with vertex colours, so the asset can be judged by eye."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "VERTEX"
    scene.display.shading.show_cavity = True
    scene.display.shading.show_shadows = True
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.film_transparent = False
    scene.world = bpy.data.worlds.new("W") if not scene.world else scene.world
    scene.display.shading.background_type = "VIEWPORT"
    objs = objs or [o for o in scene.objects if o.type == "MESH"]
    mins = Vector((1e9, 1e9, 1e9)); maxs = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            mins = Vector((min(mins[i], w[i]) for i in range(3)))
            maxs = Vector((max(maxs[i], w[i]) for i in range(3)))
    center = target or (mins + maxs) / 2
    radius = (maxs - mins).length / 2
    dist = cam_dist or radius * 2.6
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 50
    # Blender's default far clip is 100. These scripts work in STUDS, so a
    # campus or a valley is over a thousand units across and renders as an
    # empty frame with the default. Scale the clip planes to the shot.
    cam_data.clip_start = max(0.01, dist * 0.001)
    cam_data.clip_end = max(1000.0, dist * 6.0)
    cam = link(bpy.data.objects.new("Cam", cam_data))
    e, a = math.radians(elev), math.radians(azim)
    cam.location = center + Vector((dist * math.cos(e) * math.sin(a), -dist * math.cos(e) * math.cos(a), dist * math.sin(e)))
    direction = center - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


def export(path, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=path, use_selection=True, apply_unit_scale=True, apply_scale_options="FBX_SCALE_ALL",
        global_scale=1.0, mesh_smooth_type="FACE", use_mesh_modifiers=True, colors_type="SRGB",
        add_leaf_bones=False, bake_anim=False, axis_forward="-Z", axis_up="Y")
