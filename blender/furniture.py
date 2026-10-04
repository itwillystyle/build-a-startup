"""furniture.py -- v4.0: the Kenney Furniture Kit, with its colours (27 Sep 2026).

Roblox's FBX importer drops material colours, so the 20 Kenney pieces imported
in v2.0 arrived grey and were re-tinted by hand (FurnitureKit TINT): ONE colour
per part, so a sofa's legs, cushions and frame were all the same blue and a
monitor was one flat slab. This rebuilds each piece from the kit's OBJ + MTL:
every face takes its material's Kd as a VERTEX colour (which Roblox keeps), with
a little contact shading, and the parts are joined into ONE mesh per piece.

Scale: OBJ units x 5.88 = studs (measured: desk, chair, sofa, plant and fridge
all give 5.87-5.89 against FurnitureKit.SIZE), so these match the old pieces.
Facing: rotated so the front is Roblox +Z, the convention every FurnitureKit
call site already uses.

Writes out/IMPORT_FURN/FK_<name>.fbx, out/furniture_meta.lua (sizes in studs,
Roblox axes) and a contact sheet.

Run:  blender -b --python furniture.py
"""
import bpy
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import svkit as K  # noqa: E402

SRC = r"C:\Users\lukex\Downloads\kenney\furniture_full\Models\OBJ format"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
IMP = os.path.join(OUT, "IMPORT_FURN")
PREV = os.path.join(OUT, "furn_prev")
os.makedirs(IMP, exist_ok=True)
os.makedirs(PREV, exist_ok=True)
F = 5.88

NAMES = [
    # office
    "desk", "deskCorner", "chairDesk", "computerScreen", "computerKeyboard", "computerMouse", "laptop",
    "bookcaseClosedDoors", "bookcaseOpen", "bookcaseClosedWide", "books", "coatRackStanding", "trashcan",
    # seating and tables
    "chairModernCushion", "chairModernFrameCushion", "chairRounded", "chairCushion", "stoolBar", "stoolBarSquare",
    "tableRound", "tableCross", "tableGlass", "tableCoffee", "tableCoffeeGlass", "tableCoffeeSquare", "sideTable", "sideTableDrawers",
    "loungeSofa", "loungeSofaCorner", "loungeSofaLong", "loungeSofaOttoman", "loungeDesignSofa", "loungeDesignSofaCorner",
    "loungeChair", "loungeChairRelax", "loungeDesignChair", "benchCushion",
    # light, plants, rugs, decor
    "lampSquareFloor", "lampRoundFloor", "lampRoundTable", "lampSquareTable", "lampSquareCeiling", "ceilingFan",
    "pottedPlant", "plantSmall1", "plantSmall2", "plantSmall3",
    "rugRectangle", "rugRound", "rugRounded", "rugSquare", "pillow", "pillowBlue", "pillowLong",
    "speaker", "speakerSmall", "radio", "televisionModern", "cabinetTelevision", "cabinetTelevisionDoors",
    "cardboardBoxClosed", "cardboardBoxOpen",
    # kitchen
    "kitchenBar", "kitchenBarEnd", "kitchenCabinet", "kitchenCabinetDrawer", "kitchenCabinetUpper", "kitchenCabinetUpperDouble",
    "kitchenFridge", "kitchenFridgeLarge", "kitchenCoffeeMachine", "kitchenMicrowave", "kitchenSink", "kitchenStove",
    "kitchenBlender", "toaster", "hoodModern",
    # bedroom and bathroom (the apartments)
    "bedDouble", "bedSingle", "cabinetBed", "cabinetBedDrawer", "cabinetBedDrawerTable",
    "bathtub", "shower", "toilet", "bathroomSink", "bathroomMirror", "bathroomCabinet", "washerDryerStacked",
]


def read_mtl(path):
    mats, cur = {}, None
    if not os.path.exists(path):
        return mats
    for line in open(path, encoding="utf-8", errors="ignore"):
        p = line.split()
        if not p:
            continue
        if p[0] == "newmtl":
            cur = p[1]
        elif p[0] == "Kd" and cur:
            mats[cur] = tuple(min(1.0, max(0.0, float(v))) for v in p[1:4])
    return mats


def convert(name):
    K.reset()
    obj_path = os.path.join(SRC, name + ".obj")
    if not os.path.exists(obj_path):
        print("MISSING", name)
        return None
    kd = read_mtl(os.path.join(SRC, name + ".mtl"))
    bpy.ops.wm.obj_import(filepath=obj_path, forward_axis="NEGATIVE_Z", up_axis="Y")
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in objs:
        me = o.data
        if "Col" not in me.color_attributes:
            me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
        attr = me.color_attributes["Col"]
        for poly in me.polygons:
            mat = o.material_slots[poly.material_index].material if o.material_slots else None
            base = kd.get(mat.name if mat else "", (0.8, 0.8, 0.8))
            if mat and mat.name not in kd:
                # Blender may suffix duplicate names (wood.001)
                base = kd.get(mat.name.split(".")[0], base)
            nz = poly.normal.z if False else None
            n = (o.matrix_world.to_3x3() @ poly.normal).normalized()
            k = 1.04 if n.z > 0.5 else (0.78 if n.z < -0.5 else 0.94)
            c = tuple(min(1.0, v * k) for v in base)
            for li in poly.loop_indices:
                attr.data[li].color_srgb = (c[0], c[1], c[2], 1.0)
        me.color_attributes.active_color = attr
    o = K.join(objs, "FK_" + name) if len(objs) > 1 else objs[0]
    o.name = "FK_" + name
    o.data.name = "FK_" + name
    # scale to studs, front to +Y in Blender (= Roblox +Z), feet at 0
    o.scale = (F, F, F)
    o.rotation_euler = (o.rotation_euler[0], o.rotation_euler[1], o.rotation_euler[2] + math.pi)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    mn = [min((o.matrix_world @ v.co)[i] for v in o.data.vertices) for i in range(3)]
    mx = [max((o.matrix_world @ v.co)[i] for v in o.data.vertices) for i in range(3)]
    # Roblox axes: X = x, Y = z (up), Z = y
    size = (mx[0] - mn[0], mx[2] - mn[2], mx[1] - mn[1])
    K.export(os.path.join(IMP, "FK_" + name + ".fbx"), [o])
    K.preview(os.path.join(PREV, name + ".png"), objs=[o], size=(260, 220), elev=22, azim=200)
    return size, K.tris(o)


META = {}
for n in NAMES:
    r = convert(n)
    if r:
        META[n] = r
NL = chr(10)
with open(os.path.join(OUT, "furniture_meta.lua"), "w") as f:
    f.write("-- generated by blender/furniture.py: vertex-coloured Kenney pieces, true size in studs" + NL)
    f.write("return {" + NL)
    for k in sorted(META):
        (sx, sy, sz), tris = META[k]
        f.write(("\t%s = Vector3.new(%.2f, %.2f, %.2f),  -- %d tris" + NL) % (k, sx, sy, sz, tris))
    f.write("}" + NL)
print("FURN", len(META), "of", len(NAMES))
