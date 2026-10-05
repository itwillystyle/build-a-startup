"""hull_test.py -- can the cartoon outline be baked into the mesh? (v4.9)

THE QUESTION. Roblox has no post-process outline, and a Highlight is one
adornment per object: it can only ever outline the ~556 things the game tags,
never the hills, roads, buildings or the 4,568 valley trees. A whole-scene
outline has exactly one route -- bake it into the geometry.

THE TECHNIQUE (the classic inverted hull, and the oldest trick in toon
rendering). Duplicate the mesh, push every vertex out along its normal, and
REVERSE the winding. From outside, the hull's near faces now point away from
the camera and are culled; its far faces are hidden behind the real mesh --
except around the silhouette, where the hull pokes out past it. That rim is
the outline. Paint the hull black and join it to the original, and the whole
thing is ONE mesh: one draw call, no script, no distance limit, forever.

WHAT THIS RESTS ON, AND WHY IT IS A TEST AND NOT A ROLLOUT. The entire
technique assumes Roblox culls backfaces on MeshParts. If it renders them
double-sided instead, the hull does not become an outline -- it becomes a
solid black blob swallowing the model. That is exactly the failure I already
hit in October trying the runtime version of this (a negative-scaled
SpecialMesh rendered as a black box), so the assumption has earned no trust.

So this exports THREE files for one tree and nothing else:

    HULL_Oak_plain.fbx    the control, no hull
    HULL_Oak_thin.fbx     a 0.09-stud hull
    HULL_Oak_thick.fbx    a 0.22-stud hull, so the effect is unmissable

Import the three, stand them side by side, and look. Plain vs thin tells you
whether culling works at all. Thin vs thick tells you what width reads at
distance. Only then is it worth re-exporting a hundred meshes.

    blender -b --python blender/hull_test.py
"""
import os
import sys
import math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import svkit as K
import bmesh
from mathutils import Vector

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "IMPORT_HULL")
os.makedirs(OUT, exist_ok=True)

BARK = K.rgb(104, 74, 52)
LEAF_HI = K.rgb(126, 196, 104)
LEAF_LO = K.rgb(72, 140, 82)
INK = K.rgb(24, 22, 28)          # the outline colour, the same ink the UI uses


def blob(name, at, r, scale, seed):
    """One faceted leaf mass: an icosphere squashed, so it reads low-poly."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=r)
    o = K.mesh_obj(name, bm)
    o.scale = scale
    o.location = at
    K.bpy.context.view_layer.objects.active = o
    K.bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return o


def tree(name):
    """A stand-in for LP_Oak_A: one trunk, three crown blobs."""
    trunk = K.lathe("trunk", [(1.05, 0), (0.86, 2.4), (0.62, 6.4), (0.5, 8.2)], 9)
    K.paint(trunk, K.shaded(BARK))
    parts = [trunk]
    for i, (at, r, sc) in enumerate((
        ((0, 0, 8.2), 4.6, (1.2, 1.15, 0.78)),
        ((3.3, 1.0, 7.4), 3.2, (1, 1, 0.8)),
        ((-3.0, -1.4, 7.6), 3.0, (1, 1, 0.8)),
    )):
        b = blob("crown%d" % i, at, r, sc, i)
        K.paint(b, K.shaded(LEAF_HI, 1.0, 0.0) if False else K.shaded(LEAF_HI, 1.06, 0.74))
        parts.append(b)
    return K.join(parts, name)


def hull(src, width):
    """The inverted hull: push out along the normals, then reverse the winding.

    Pushing along the VERTEX normal (one averaged normal per vertex, which is
    what bmesh gives) rather than the face normal matters: on a flat-shaded
    low-poly mesh the face normals disagree at every edge, and offsetting by
    those splits the hull open at the corners.
    """
    dup = src.copy()
    dup.data = src.data.copy()
    dup.name = src.name + "_Hull"
    K.bpy.context.collection.objects.link(dup)

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


def build(name, width):
    K.reset()
    t = tree(name)
    objs = [t]
    if width > 0:
        objs.append(hull(t, width))
    joined = K.join(objs, name)
    n = K.tris(joined)
    path = os.path.join(OUT, name + ".fbx")
    K.export(path, [joined])
    return joined, n


made = []
for name, width in (("HULL_Oak_plain", 0.0), ("HULL_Oak_thin", 0.09), ("HULL_Oak_thick", 0.22)):
    obj, n = build(name, width)
    made.append((name, width, n))
    print("%-18s hull %.2f  tris %d" % (name, width, n))

base = made[0][2]
print("\nTRIANGLE COST OF THE HULL:")
for name, width, n in made:
    print("  %-18s %5d tris  (%+.0f%% vs the plain mesh)" % (name, n, (n / base - 1) * 100))

# Rebuild all three side by side and preview them WITH BACKFACE CULLING ON,
# which is the whole point: that is what Roblox is assumed to do, so this
# picture is the prediction the import either confirms or kills.
K.reset()
row = []
for i, (name, width, _) in enumerate(made):
    t = tree(name + "_preview")
    objs = [t]
    if width > 0:
        objs.append(hull(t, width))
    j = K.join(objs, name + "_preview")
    j.location = (i * 16 - 16, 0, 0)
    row.append(j)
for area_shading in ():
    pass
for scr in K.bpy.data.screens:
    for area in scr.areas:
        if area.type == "VIEW_3D":
            for space in area.spaces:
                if space.type == "VIEW_3D":
                    space.shading.show_backface_culling = True
K.bpy.context.scene.display.shading.show_backface_culling = True
K.preview(os.path.join(OUT, "hull_preview.png"), row, size=(1500, 620),
          elev=8, azim=20, cam_dist=52, target=Vector((0, 0, 6)))
print("\nEXPORTED 3 to", OUT)
print("preview (backface culling ON, the way Roblox is assumed to render):",
      os.path.join(OUT, "hull_preview.png"))
