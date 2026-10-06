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
    """Apply every modifier. modifier_apply needs OBJECT mode, the object
    selected AND active -- miss any of those and it fails silently, which is
    how a bevel pass once ran over a whole kit and changed nothing (424 tris
    in, 424 tris out)."""
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    for m in list(obj.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=m.name)
        except Exception as e:
            print("   apply_mods FAILED on %s/%s: %s" % (obj.name, m.name, e))
    obj.select_set(False)


def bevel(obj, width=0.1, segments=2, angle=40):
    m = obj.modifiers.new("Bevel", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(angle)
    return m


def ensure_col(obj, base=(1.0, 1.0, 1.0)):
    """A white CORNER colour layer, so there is something for AO to darken."""
    me = obj.data
    if "Col" not in me.color_attributes:
        me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
        attr = me.color_attributes["Col"]
        for d in attr.data:
            d.color_srgb = (base[0], base[1], base[2], 1.0)
    me.color_attributes.active_color = me.color_attributes["Col"]
    return obj


def dirty(obj, strength=0.35, blur=1, dirt_angle=0.0):
    """Multiply baked ambient occlusion into the vertex colours.

    ART.md calls baked AO "the single biggest 'crafted by hand' cue, and it
    fakes the global illumination Roblox doesn't have" -- and nothing in the
    pipeline ever did it. Roblox multiplies vertex colour by BasePart.Color, so
    a mesh that is white in the open and darker in its corners reads as a real
    object under any tint the game picks.

    IT HAS TO BE A MULTIPLY, not a blend. The first version ran the operator and
    then mixed the result toward white, which is only correct when the mesh
    starts white. On a mesh that already carries colour -- every valley tile --
    that lightened a 0.30/0.72/0.35 green to 0.73/0.84/0.74, washing the
    landscape out. So the original colours are saved, AO is baked against WHITE,
    and the two are multiplied.
    """
    ensure_col(obj)
    me = obj.data
    attr = me.color_attributes.get("Col")
    if attr is None:
        return obj

    def read(d):
        return d.color_srgb if hasattr(d, "color_srgb") else d.color

    def write(d, c):
        if hasattr(d, "color_srgb"):
            d.color_srgb = (c[0], c[1], c[2], 1.0)
        else:
            d.color = (c[0], c[1], c[2], 1.0)

    base = [tuple(read(d))[:3] for d in attr.data]
    for d in attr.data:                      # bake AO against white
        write(d, (1.0, 1.0, 1.0))

    bpy.context.view_layer.objects.active = obj
    try:
        bpy.ops.object.mode_set(mode="VERTEX_PAINT")
        #[[ normalize=True stretches the result to the full range, so on a mesh
        #   made of thin members -- mullions, rails, columns -- almost every
        #   corner reads as concave and the whole object comes out BLACK. ]]
        bpy.ops.paint.vertex_color_dirt(
            blur_strength=1.0, blur_iterations=int(blur),
            clean_angle=math.radians(180.0), dirt_angle=float(dirt_angle),
            dirt_only=False, normalize=False)
    except Exception as e:
        print("   dirty() skipped on %s: %s" % (obj.name, e))
    finally:
        try:
            bpy.ops.object.mode_set(mode="OBJECT")
        except Exception:
            pass

    k = max(0.0, min(1.0, float(strength)))
    for i, d in enumerate(attr.data):
        ao = tuple(read(d))[:3]
        src = base[i] if i < len(base) else (1.0, 1.0, 1.0)
        write(d, tuple(src[c] * (1.0 - (1.0 - ao[c]) * k) for c in range(3)))
    return obj

def weld(obj, dist=1e-4):
    """Merge coincident vertices so faces share edges.

    The kit builders emit loose quads: D_Lobby came out 212 polygons with 848
    vertices, which is exactly 4 unmerged verts per quad. With no shared edges
    there is no angle between adjacent faces, so a Bevel set to ANGLE has
    nothing to act on and silently does nothing -- which is why the whole kit
    bevelled to a zero-byte difference.
    """
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=dist)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return obj


def finish(obj, width=0.16, segments=1, angle=35, ao=0.35):
    """Bevel, shade and bake AO -- the two ART.md surface rules, in one call.

    Rule 1 is "no sharp 90 degree edge on anything bigger than 2 studs", and
    svkit has had a bevel() helper the whole time that none of the three HQ
    kits ever called. Applied BEFORE the caller measures its bounding box, so
    HQMeta records the geometry that actually ships. A bevel cuts corners off a
    convex box without moving its faces, so the box itself does not change size.
    """
    weld(obj)
    bevel(obj, width=width, segments=segments, angle=angle)
    apply_mods(obj)
    smooth(obj, angle)
    #[[ ONE segment, not two. A chamfer catches the same edge highlight as a
    #   rounded bevel and costs 2.4x the triangles instead of 4.5x; at 4.5x the
    #   kit alone would have pushed the worst view past the 500k budget. ]]
    if ao is not None:          # glass bevels but takes no AO: dark creases on glazing read as dirt
        dirty(obj, strength=ao)
    return obj


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
