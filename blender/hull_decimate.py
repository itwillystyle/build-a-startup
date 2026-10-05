"""hull_decimate.py -- how cheap can the baked outline get? (v4.9)

THE RESULT SO FAR. The inverted hull works in Roblox: backfaces are culled,
three trees imported 4 Oct read as plain / thin line / bold line, and the line
survives LOD at Automatic fidelity out to ~130 studs. But it doubles
triangles exactly (128 -> 256), and the game's worst view already renders
923,000 against Roblox's documented 1,000,000 phone budget. Triangles are the
tighter of the two ceilings, so a full-detail hull is not affordable.

THE IDEA BEING TESTED. The hull is never SEEN -- every one of its faces is
either culled or hidden behind the real mesh. The only thing that reaches the
screen is the few pixels of rim poking past the silhouette. So it does not
need the model's detail; it needs the model's SHAPE. Decimate it first.

THE RISK, and the reason this is a test and not a change. A decimated hull
cuts corners -- literally. Where it cuts inside the original's silhouette,
the hull stops poking out and THE OUTLINE BREAKS, leaving gaps along exactly
the edges the eye follows. The offset has to grow to compensate, which costs
line weight. The trade is: how far can the triangle count fall before the
line starts coming apart?

So each variant pairs a decimate ratio with the offset it needs:

    full      ratio 1.00  width 0.22   the control, +100% tris
    half      ratio 0.50  width 0.26
    third     ratio 0.30  width 0.30
    fifth     ratio 0.18  width 0.36

Preview is rendered with backface culling ON and the camera close, because a
gap in the line is a few pixels and a wide shot would hide it.

    blender -b --python blender/hull_decimate.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import svkit as K
import bmesh
from mathutils import Vector

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "IMPORT_HULL2")
os.makedirs(OUT, exist_ok=True)

BARK = K.rgb(104, 74, 52)
LEAF = K.rgb(126, 196, 104)
INK = K.rgb(24, 22, 28)


def blob(name, at, r, scale):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=r)
    o = K.mesh_obj(name, bm)
    o.scale = scale
    o.location = at
    K.bpy.context.view_layer.objects.active = o
    K.bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return o


def tree(name):
    trunk = K.lathe("trunk", [(1.05, 0), (0.86, 2.4), (0.62, 6.4), (0.5, 8.2)], 9)
    K.paint(trunk, K.shaded(BARK))
    parts = [trunk]
    for i, (at, r, sc) in enumerate((
        ((0, 0, 8.2), 4.6, (1.2, 1.15, 0.78)),
        ((3.3, 1.0, 7.4), 3.2, (1, 1, 0.8)),
        ((-3.0, -1.4, 7.6), 3.0, (1, 1, 0.8)),
    )):
        b = blob("crown%d" % i, at, r, sc)
        K.paint(b, K.shaded(LEAF, 1.06, 0.74))
        parts.append(b)
    return K.join(parts, name)


def hull(src, width, ratio):
    """Decimate first, then push out along the normals and reverse the winding."""
    dup = src.copy()
    dup.data = src.data.copy()
    dup.name = src.name + "_Hull"
    K.bpy.context.collection.objects.link(dup)

    if ratio < 0.999:
        K.bpy.context.view_layer.objects.active = dup
        mod = dup.modifiers.new("dec", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = ratio
        K.bpy.ops.object.modifier_apply(modifier=mod.name)

    bm = bmesh.new()
    bm.from_mesh(dup.data)
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * width
    bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    bm.to_mesh(dup.data)
    bm.free()

    K.paint(dup, K.flat(INK))
    return dup


VARIANTS = [
    ("HULL2_full", 1.00, 0.22),
    ("HULL2_half", 0.50, 0.26),
    ("HULL2_third", 0.30, 0.30),
    ("HULL2_fifth", 0.18, 0.36),
]

rows = []
for name, ratio, width in VARIANTS:
    K.reset()
    base = tree(name)
    baseTris = K.tris(base)
    h = hull(base, width, ratio)
    hullTris = K.tris(h)
    joined = K.join([base, h], name)
    total = K.tris(joined)
    K.export(os.path.join(OUT, name + ".fbx"), [joined])
    rows.append((name, ratio, width, baseTris, hullTris, total))
    print("%-14s ratio %.2f width %.2f   model %4d + hull %4d = %4d tris" %
          (name, ratio, width, baseTris, hullTris, total))

plain = rows[0][3]
print("\nTRIANGLE COST, against the %d-triangle model:" % plain)
for name, ratio, width, b, hh, total in rows:
    print("  %-14s %4d tris   %+5.0f%%   (hull alone: %4d)" % (name, total, (total / plain - 1) * 100, hh))

# Close preview with culling on, because a gap in the line is only a few pixels
K.reset()
row = []
for i, (name, ratio, width) in enumerate(VARIANTS):
    t = tree(name + "_p")
    h = hull(t, width, ratio)
    j = K.join([t, h], name + "_p")
    j.location = (i * 17 - 25.5, 0, 0)
    row.append(j)
K.bpy.context.scene.display.shading.show_backface_culling = True
for scr in K.bpy.data.screens:
    for area in scr.areas:
        if area.type == "VIEW_3D":
            for space in area.spaces:
                if space.type == "VIEW_3D":
                    space.shading.show_backface_culling = True
K.preview(os.path.join(OUT, "hull_decimate_preview.png"), row, size=(1800, 700),
          elev=7, azim=12, cam_dist=108, target=Vector((0, 0, 7)))
print("\nEXPORTED %d to %s" % (len(VARIANTS), OUT))
