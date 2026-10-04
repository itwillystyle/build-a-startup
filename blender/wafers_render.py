"""wafers_render.py -- review renders of THE WAFERS, assembled from the EXPORTED kit.

Nothing here rebuilds geometry. Every piece is the FBX in out/IMPORT_WAFERS,
re-imported, recentred on its bounding box (as Roblox's importer does) and placed
with the game's rule: part.CFrame = pieceFrame * CFrame.new(meta.c), where meta
is parsed from the generated game file HQMeta/Wafers.lua and pieceFrame is
Wafers.lua's anchor (wafer centre, storey slab bottom, CFrame.Angles(0, turn, 0)).
So a wrong c, a wrong axis or a wrong turn shows up in these pictures.

Piece order: sim/wafer_plan.py PIECES (the same plan as WaferPlan.lua).
Departments: the guide's pick (wafer_plan.recommend) as the building fills.
The site (valley, trees, people) reuses blender/concepts/hq_concepts.py.

Run:  blender -b --python wafers_render.py [-- lv=5,18,43,100 spp=64 views=aerial,close,plaza,parts]
Out:  art/concepts/wafers_kit/*.png + stats.json;  then  python wafers_sheet.py
"""
import bpy
import json
import math
import os
import random
import re
import sys
import time
from mathutils import Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
KIT = os.path.join(HERE, "out", "IMPORT_WAFERS")
ART = os.path.join(ROOT, "art", "concepts", "wafers_kit")
META_LUA = os.path.join(ROOT, "game", "src", "ServerScriptService", "HQMeta", "Wafers.lua")
GARAGE = os.path.join(HERE, "out", "IMPORT_HQ")
os.makedirs(ART, exist_ok=True)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "sim"))
import svkit as K  # noqa: E402
import wafer_plan as WP  # noqa: E402

# the concept library (valley, trees, people, light, camera fit) without its main()
LIB = os.path.join(HERE, "concepts", "hq_concepts.py")
_src = open(LIB, encoding="utf-8").read().rstrip()
assert _src.endswith("main()")
L = {"__file__": LIB, "__name__": "hq_concepts_lib"}
exec(compile(_src[: -len("main()")], LIB, "exec"), L)
Geo, rgb, lin = L["Geo"], L["rgb"], L["lin"]


def _args():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = dict(lv="5,18,43,100", spp="64", views="aerial,close,plaza,top,back,court,parts,thumbs")
    for s in a:
        if "=" in s:
            k, v = s.split("=", 1)
            o[k] = v
    return o


OPT = _args()
LEVELS = [int(x) for x in OPT["lv"].split(",")]
SPP = int(OPT["spp"])
VIEWS = OPT["views"].split(",")

# ------------------------------------------------------------------ the contract, as the game has it
_WPY = os.path.join(HERE, "wafers.py")
wafers_py = {"__file__": _WPY, "__name__": "wafers_geo"}
exec(compile(open(_WPY, encoding="utf-8").read().split("# ------------------------------------------------------------------ palette")[0]
             .replace("import svkit as K  # noqa: E402", "K = None"), _WPY, "exec"), wafers_py)
GEO = wafers_py["GEO"]
H, SLAB, DEPTH, FLOOR_Y = GEO["H"], GEO["SLAB"], GEO["DEPTH"], GEO["FLOOR_Y"]
WAFER = GEO["WAFER"]
CORE_X, CORE_Z, CORE_R = GEO["CORE"]
DECK_SURF = 0.3


def read_meta():
    rows = {}
    head = open(META_LUA, encoding="utf-8").read()
    for m in re.finditer(r"\t(\w+) = \{ c = Vector3\.new\(([-\d.]+), ([-\d.]+), ([-\d.]+)\), s = Vector3\.new\(([-\d.]+), ([-\d.]+), ([-\d.]+)\) \},  -- (\d+) tris", head):
        v = [float(x) for x in m.groups()[1:7]]
        rows[m.group(1)] = dict(c=tuple(v[:3]), s=tuple(v[3:]), tris=int(m.group(8)))
    lh = re.search(r"LANTERN_H = ([\d.]+)", head)
    return rows, float(lh.group(1)) if lh else 11.2


META, LANTERN_H = read_meta()


def slab_bottom(s):
    return FLOOR_Y + s * H - SLAB


def floor_y(s):
    return FLOOR_Y + s * H


# ------------------------------------------------------------------ departments (the guide's pick)
TINT = dict(lobby=(236, 214, 170), eng=(150, 188, 232), studio=(236, 164, 192), cafe=(246, 176, 116),
            servers=(70, 78, 96), labs=(122, 214, 198), board=(236, 202, 112))


def departments():
    counts, out = {}, {}
    for pc in WP.PIECES:
        Lv = pc["level"]
        if pc["kind"] != "segment":
            continue
        seats = 1 + WP.seats(counts)
        free = max(0, seats - WP.cap_at(Lv) + 2)
        d = WP.recommend(Lv, counts, free)
        out[Lv] = d
        counts[d] = counts.get(d, 0) + 1
    return out


DEPT = departments()


# ------------------------------------------------------------------ placement (the game's CFrame math)
def ry(theta, v):
    """Roblox CFrame.Angles(0, theta, 0) applied to a vector (x, y, z)."""
    c, s = math.cos(theta), math.sin(theta)
    return (v[0] * c + v[2] * s, v[1], -v[0] * s + v[2] * c)


def to_blender(p):
    return (-p[0], p[2], p[1])


def placements(level):
    """[(mesh, frame_pos, turn, tint_key, stretch)] for a building at `level`, in Roblox plot space."""
    out = []
    built = WP.PIECES[:level]
    for pc in built:
        k, w, s, seg, Lv = pc["kind"], pc["wafer"], pc["storey"], pc["seg"], pc["level"]
        if k == "segment":
            cx, cz, r = WAFER[w]
            turn = math.radians(45 * (seg - 1))
            pos = (cx, slab_bottom(s), cz)
            if w == 1 and s == 0 and seg == 1:
                names = ("W_Lobby", "W_LobbyGlass")
            elif seg == 5:
                names = ("W_SegB_%d" % w, "W_GlassB_%d" % w)
            else:
                names = ("W_Seg_%d" % w, "W_Glass_%d" % w)
            out.append((names[0], pos, turn, None, 1.0))
            out.append((names[1], pos, turn, DEPT[Lv], 1.0))
        elif k in ("deck", "roof"):
            cx, cz, r = WAFER[w]
            nm = ("W_Deck_%d" % w, "W_DeckGlass_%d" % w) if k == "deck" else ("W_Roof", "W_RoofGlass")
            pos = (cx, slab_bottom(s), cz)
            out.append((nm[0], pos, 0.0, None, 1.0))
            out.append((nm[1], pos, 0.0, "rail", 1.0))
        elif k == "pavilion":
            cx, cz, r = WAFER[4]
            pos = (cx, slab_bottom(s), cz)
            turn = math.radians(90 * (seg - 1))
            out.append(("W_Pav", pos, turn, None, 1.0))
            out.append(("W_PavGlass", pos, turn, "pav", 1.0))
        elif k == "halo":
            cx, cz, r = WAFER[4]
            out.append(("W_Halo", (cx, floor_y(14) + 8, cz), 0.0, None, 1.0))
    # deck columns arrive with the first piece of the wafer they hold up
    for w in (1, 2, 3):
        decked = any(pc["kind"] == "deck" and pc["wafer"] == w for pc in built)
        upper = any(pc["kind"] == "segment" and pc["wafer"] == w + 1 for pc in built)
        if decked and upper:
            cx, cz, r = WAFER[w]
            out.append(("W_DeckCols_%d" % w, (cx, slab_bottom(WP.DECK_STOREY[w]), cz), 0.0, None, 1.0))
    # the lift: storeys 0..top, a bridge on every storey that has somewhere to land
    top = max([pc["storey"] for pc in built if pc["kind"] not in ("garage", "halo", "lantern", "mast")] + [0])
    kinds = {pc["kind"] for pc in built}
    if top >= 1:
        for s in range(0, top + 1):
            land = None
            for pc in built:
                if pc["storey"] != s or not pc["wafer"]:
                    continue
                cx, cz, r = WAFER[pc["wafer"]]
                rin = r - DEPTH
                if pc["kind"] == "segment" and pc["seg"] == 5:
                    land = ((cx, cz - rin * math.cos(math.radians(4.5))), floor_y(s))
                elif pc["kind"] in ("deck", "roof"):
                    land = ((cx, cz - (rin - 0.3) * math.cos(math.radians(4.5))), slab_bottom(s) + DECK_SURF)
            turn = 0.0
            if land and s >= 1:
                (qx, qz), y = land
                dx, dz = qx - CORE_X, qz - CORE_Z
                dist = math.hypot(dx, dz)
                ux, uz = dx / dist, dz / dist
                turn = math.atan2(-ux, -uz)                  # the core's -Z door faces the bridge
                bturn = math.atan2(ux, uz)                   # the bridge's +Z runs out to the landing
                start = (CORE_X + ux * (CORE_R - 0.2), y, CORE_Z + uz * (CORE_R - 0.2))
                length = dist - CORE_R + 0.2
                out.append(("W_Bridge", start, bturn, None, length / 10.0))
                out.append(("W_BridgeGlass", start, bturn, "rail", length / 10.0))
            out.append(("W_Core", (CORE_X, slab_bottom(s), CORE_Z), turn, None, 1.0))
            out.append(("W_CoreGlass", (CORE_X, slab_bottom(s), CORE_Z), turn, "core", 1.0))
        out.append(("W_CoreCap", (CORE_X, slab_bottom(top), CORE_Z), 0.0, None, 1.0))
        core_top = slab_bottom(top + 1)
        if "lantern" in kinds:
            out.append(("W_Lantern", (CORE_X, core_top, CORE_Z), 0.0, None, 1.0))
            out.append(("W_LanternGlass", (CORE_X, core_top, CORE_Z), 0.0, "lantern", 1.0))
        if "mast" in kinds:
            out.append(("W_Mast", (CORE_X, core_top + LANTERN_H, CORE_Z), 0.0, None, 1.0))
    return out


def tris_at(level):
    return sum(META[p[0]]["tris"] for p in placements(level))


# ------------------------------------------------------------------ materials
MAT = {}


def principled(m):
    return next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")


def make_mats():
    L["make_materials"]()
    MAT["vc"] = L["MATS"]["vc"]
    for key, t in TINT.items():
        m = bpy.data.materials.new("wg_" + key)
        m.use_nodes = True
        p = principled(m)
        base = tuple(t[i] * 0.45 + (70, 100, 118)[i] * 0.55 for i in range(3))
        p.inputs["Base Color"].default_value = (*lin(rgb(*base)), 1)
        p.inputs["Roughness"].default_value = 0.07
        p.inputs["Specular IOR Level"].default_value = 0.6
        p.inputs["Coat Weight"].default_value = 0.3
        p.inputs["Emission Color"].default_value = (*lin(rgb(*t)), 1)
        p.inputs["Emission Strength"].default_value = 0.12 if key == "servers" else 0.5
        MAT[key] = m
    for key, col, alpha, em in (("rail", (200, 222, 232), 0.28, 0.0), ("core", (190, 214, 226), 0.35, 0.0),
                                ("lantern", (255, 236, 190), 0.9, 1.4), ("pav", (240, 226, 190), 0.85, 0.55),
                                ("garage", (236, 214, 170), 0.85, 0.4)):
        m = bpy.data.materials.new("wg_" + key)
        m.use_nodes = True
        p = principled(m)
        p.inputs["Base Color"].default_value = (*lin(rgb(*col)), 1)
        p.inputs["Roughness"].default_value = 0.05
        p.inputs["Alpha"].default_value = alpha
        if em:
            p.inputs["Emission Color"].default_value = (*lin(rgb(*col)), 1)
            p.inputs["Emission Strength"].default_value = em
        MAT[key] = m


# ------------------------------------------------------------------ the kit, re-imported
TPL = {}


def import_fbx(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path, axis_forward="-Z", axis_up="Y")
    new = [o for o in bpy.data.objects if o not in before]
    o = [x for x in new if x.type == "MESH"][0]
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for x in new:
        if x is not o:
            bpy.data.objects.remove(x)
    if o.data.color_attributes:
        o.data.color_attributes[0].name = "Col"
    return o


def load_kit():
    """Import every mesh, check its size against the meta, and recentre it on its
    bounding box, as Roblox's importer does."""
    worst = 0.0
    for name, m in META.items():
        o = import_fbx(os.path.join(KIT, name + ".fbx"))
        vs = [v.co.copy() for v in o.data.vertices]
        mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
        mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
        c = (mn + mx) / 2
        s = mx - mn
        size_rbx = (s.x, s.z, s.y)
        c_rbx = (-c.x, c.z, c.y)
        err = max(max(abs(size_rbx[i] - m["s"][i]) for i in range(3)), max(abs(c_rbx[i] - m["c"][i]) for i in range(3)))
        worst = max(worst, err)
        for v in o.data.vertices:
            v.co -= c
        o.data.materials.clear()
        o.data.materials.append(MAT["vc"])
        for coll in list(o.users_collection):
            coll.objects.unlink(o)
        TPL[name] = o
    print("KIT: %d meshes re-imported; worst meta mismatch %.4f studs" % (len(TPL), worst))
    assert worst < 0.02, "the FBX files and HQMeta/Wafers.lua disagree"


BUILT = []


def put(name, pos, turn, tint, k=1.0):
    m = META[name]
    c = (m["c"][0], m["c"][1], m["c"][2] * k)
    wc = ry(turn, c)
    o = bpy.data.objects.new(name, TPL[name].data)
    bpy.context.scene.collection.objects.link(o)
    o.location = to_blender((pos[0] + wc[0], pos[1] + wc[1], pos[2] + wc[2]))
    o.rotation_euler = (0, 0, turn)
    o.scale = (1, k, 1)
    if tint:
        o.material_slots[0].link = "OBJECT"
        o.material_slots[0].material = MAT[tint]
    BUILT.append(o)


def clear_built():
    for o in BUILT:
        bpy.data.objects.remove(o)
    BUILT.clear()


def place(level):
    clear_built()
    for (name, pos, turn, tint, k) in placements(level):
        put(name, pos, turn, tint, k)
    bpy.context.view_layer.update()


def garage():
    if not os.path.exists(os.path.join(GARAGE, "HQ_1_Shell.fbx")):
        g = Geo()
        g.box((0, 0, 7.5), (36, 30, 14), L["PAPER"])
        g.to_object("GarageBox")
        return
    for nm, mat in (("HQ_1_Shell", "vc"), ("HQ_1_Glass", "garage")):
        p = os.path.join(GARAGE, nm + ".fbx")
        if os.path.exists(p):
            o = import_fbx(p)
            o.data.materials.clear()
            o.data.materials.append(MAT[mat])


# ------------------------------------------------------------------ the site (front = +Y = the road)
PLOT_X, PLOT_Y0, PLOT_Y1 = 120.0, -170.0, 130.0
ROAD_Y = 150.0
LOBBY_Y = WAFER[1][2]


def mirrored_ground():
    import bmesh
    g = L["ground"]()
    for v in g.bm.verts:
        v.co.y = -v.co.y
    bmesh.ops.reverse_faces(g.bm, faces=g.bm.faces[:])
    return g


def gh(x, y):
    return L["ground_h"](x, -y)


def site():
    g = mirrored_ground()
    lawn = L["LAWN"]
    cells_x, cells_y = 16, 20
    sx, sy = 2 * PLOT_X / cells_x, (PLOT_Y1 - PLOT_Y0) / cells_y
    for i in range(cells_x):
        for j in range(cells_y):
            x0, y0 = -PLOT_X + i * sx, PLOT_Y0 + j * sy
            k = 1.035 if i % 2 == 0 else 0.965
            g.poly([(x0, y0, 0.5), (x0 + sx, y0, 0.5), (x0 + sx, y0 + sy, 0.5), (x0, y0 + sy, 0.5)],
                   tuple(min(1, c * k) for c in lawn), "matte", (0, 0, 1))
    CON, PAV = L["CONCRETE"], rgb(224, 216, 200)
    W2 = 2 * PLOT_X + 3
    D = PLOT_Y1 - PLOT_Y0 + 3
    for (cx, cy, sx_, sy_) in ((0, PLOT_Y0 - 0.8, W2, 1.6), (0, PLOT_Y1 + 0.8, W2, 1.6),
                               (-PLOT_X - 0.8, (PLOT_Y0 + PLOT_Y1) / 2, 1.6, D), (PLOT_X + 0.8, (PLOT_Y0 + PLOT_Y1) / 2, 1.6, D)):
        g.box((cx, cy, 0.45), (sx_, sy_, 0.9), CON, mat="matte")
    g.box((0, ROAD_Y, 0.15), (3200, 24, 0.3), L["ASPHALT"], mat="matte")
    for s in (-1, 1):
        g.box((0, ROAD_Y + s * 14.6, 0.25), (3200, 5.2, 0.5), CON, mat="matte")
    for x in range(-1500, 1501, 18):
        g.box((x, ROAD_Y, 0.32), (7, 0.5, 0.06), rgb(236, 226, 196), mat="matte")
    # the courtyard (paved round the garage), the forecourt plaza and the path to the street
    g.prism((0, 0), 40, 0.5, 0.64, 39.0, 39.0, 0.0, color=PAV, mat="matte", faces="ts")
    g.box((0, (LOBBY_Y + PLOT_Y1) / 2 + 2, 0.6), (18, PLOT_Y1 - LOBBY_Y + 6, 0.2), PAV, mat="matte")
    g.prism((0, 98), 40, 0.5, 0.66, 26.0, 26.0, 0.0, color=PAV, mat="matte", faces="ts")
    g.prism((0, 98), 24, 0.5, 1.1, 7.0, 7.0, 0.0, color=CON, mat="matte", faces="ts")
    g.prism((0, 98), 24, 0.5, 1.15, 6.0, 6.0, 0.0, color=L["PAPER"], mat="water", faces="t")
    g.to_object("Site")


FOOT = []


def footprint_blocked(x, y):
    return any(math.hypot(x - px, y - py) < r for (px, py, r) in FOOT)


def plaza_cam():
    return Vector((18.0, LOBBY_Y + 80.0, 6.5)), Vector((-4.0, LOBBY_Y - 18.0, 31.0))


def scatter():
    rng = random.Random(21)
    for x in range(-560, 561, 28):
        if abs(x) < 18:
            continue
        for yy in (ROAD_Y - 16.5, ROAD_Y + 16.5):
            L["tree"]("LP_Palm_A" if (x // 28) % 2 else "LP_Palm_B", x + rng.uniform(-2, 2), yy, 0.5, rng.uniform(20, 25), rng=rng)
    cam, tgt = plaza_cam()
    placed, tries = 0, 0
    while placed < 58 and tries < 6000:
        tries += 1
        x, y = rng.uniform(-114, 114), rng.uniform(PLOT_Y0 + 6, PLOT_Y1 - 6)
        if footprint_blocked(x, y) or math.hypot(x, y - 98) < 34 or (abs(x) < 14 and y > 50):
            continue
        vx, vy = tgt.x - cam.x, tgt.y - cam.y          # keep the plaza view of the lobby clear
        t = max(0.0, min(1.0, ((x - cam.x) * vx + (y - cam.y) * vy) / (vx * vx + vy * vy)))
        if math.hypot(x - (cam.x + t * vx), y - (cam.y + t * vy)) < 14.0 + 22.0 * t:
            continue
        if rng.random() < 0.18:
            L["tree"]("LP_Eucalypt", x, y, 0.5, rng.uniform(20, 28), rng=rng)
        else:
            L["tree"]("LP_Oak_A" if rng.random() < 0.5 else "LP_Oak_B", x, y, 0.5, rng.uniform(11, 15), rng=rng)
        placed += 1
    placed, tries = 0, 0
    while placed < 340 and tries < 9000:
        tries += 1
        x, y = rng.uniform(-1100, 1100), rng.uniform(-1500, 170)
        if abs(x) < 150 and y > -200:
            continue
        if abs(y - ROAD_Y) < 26:
            continue
        h = gh(x, y)
        wood = noise.noise(Vector((x / 170.0, -y / 170.0, 7.0)))
        if h > 6 and wood < -0.08 and rng.random() < 0.7:
            continue
        if y < -1150 and h > 60:
            L["tree"]("LP_RedwoodGrove", x, y, h - 0.5, rng.uniform(26, 32), rng=rng)
        elif h > 8 and rng.random() < 0.4:
            L["tree"]("LP_Grove", x, y, h - 0.5, rng.uniform(12, 16), rng=rng)
        else:
            L["tree"]("LP_Oak_A" if rng.random() < 0.5 else "LP_Oak_B", x, y, h - 0.3, rng.uniform(11, 15), rng=rng)
        placed += 1


def people():
    g = Geo()
    rng = random.Random(5)
    shirts = [L["ACCENT"], L["BLUE"], rgb(250, 208, 90), rgb(120, 190, 120), L["PAPER"]]
    skins = [rgb(236, 196, 160), rgb(200, 150, 110), rgb(150, 100, 70), rgb(110, 72, 50)]
    for i, (x, y) in enumerate(((-12, 104), (14, 92), (-5, 84), (6, 112), (3, 74), (-20, 20))):
        L["person"](g, x, y, rng.uniform(0, 2 * math.pi), shirts[i % 5], L["INK"] if i % 2 else rgb(70, 90, 130), skins[i % 4])
    cam, tgt = plaza_cam()
    d = Vector((tgt.x - cam.x, tgt.y - cam.y, 0)).normalized()
    p = cam + d * 13.0
    L["person"](g, p.x, p.y, math.atan2(d.y, d.x) + math.pi / 2, L["ACCENT"], L["INK"], skins[1])
    for (x, lane, col) in ((-140, -6, L["PAPER"]), (70, 6, L["ACCENT"]), (260, -6, L["BLUE"]), (-330, 6, L["PAPER"])):
        yy = ROAD_Y + lane
        g.box((x, yy, 1.6), (9.4, 4.2, 1.8), col)
        g.box((x - 0.4, yy, 3.0), (5.4, 3.7, 1.4), L["INK_SOFT"])
    return g


# ------------------------------------------------------------------ cameras
def bounds():
    pts = [o.matrix_world @ Vector(c) for o in BUILT for c in o.bound_box]
    return (min(p.x for p in pts), max(p.x for p in pts), min(p.y for p in pts), max(p.y for p in pts), max(p.z for p in pts))


def fit_points(b, margin=12.0):
    x0, x1, y0, y1, z1 = b
    y1 = max(y1, 108.0)          # keep the forecourt plaza in frame
    return [(x, y, z) for x in (x0 - margin, x1 + margin) for y in (y0 - margin, y1 + margin) for z in (0.0, z1)]


def set_cam(cam, scene, pos, tgt, lens=None, vfov=None, res=(1200, 900)):
    cd = cam.data
    scene.render.resolution_x, scene.render.resolution_y = res
    if vfov is not None:
        cd.sensor_fit = "VERTICAL"
        cd.sensor_height = 24.0
        cd.lens = 12.0 / math.tan(math.radians(vfov) / 2)
    else:
        cd.sensor_fit = "HORIZONTAL"
        cd.sensor_width = 36.0
        cd.lens = lens
    cam.location = pos
    cam.rotation_euler = (tgt - pos).to_track_quat("-Z", "Y").to_euler()


def render(scene, path):
    scene.render.filepath = path
    t = time.time()
    bpy.ops.render.render(write_still=True)
    print("RENDER", os.path.basename(path), "%.1fs" % (time.time() - t))


# ------------------------------------------------------------------ main
def setup_scene():
    K.reset()
    L["_TT"].clear()
    scene = bpy.context.scene
    L["setup_gpu"](scene)
    make_mats()
    L["SUN_ELEV"] = math.radians(27.0)
    L["SUN_ROT"] = math.radians(222.0)           # low sun from the front-left
    L["CAM_AZ"] = math.radians(58.0)             # the aerial camera: front-right, above
    L["CAM_EL"] = math.radians(27.0)
    world = L["light"](scene)
    cd = bpy.data.cameras.new("Cam")
    cd.clip_end = 12000
    cam = bpy.data.objects.new("Cam", cd)
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.cycles.samples = SPP
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 4
    scene.cycles.diffuse_bounces = 2
    scene.cycles.glossy_bounces = 2
    scene.cycles.transmission_bounces = 4
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "AgX"
    for look in ("AgX - Punchy", "AgX - Medium High Contrast"):
        try:
            scene.view_settings.look = look
            break
        except Exception:  # noqa: BLE001
            pass
    L["composite"](scene, world, 500.0)
    return scene, world, cam


def main():
    t0 = time.time()
    scene, world, cam = setup_scene()
    load_kit()
    garage()
    place(100)                      # the finished footprint keeps lawn trees off it
    for o in BUILT:
        if o.name.startswith(("W_Seg", "W_Lobby", "W_Deck", "W_Roof")):
            FOOT.append((o.location.x, o.location.y, 26.0))
    FOOT.append((0.0, -5.0, 76.0))
    b100 = bounds()
    place(18)
    b18 = bounds()
    site()
    people().to_object("People")
    scatter()
    stats = dict(levels={}, meshes={k: v["tris"] for k, v in META.items()})
    for lv in LEVELS:
        place(lv)
        stats["levels"][str(lv)] = dict(tris=tris_at(lv), parts=len(BUILT), height=round(bounds()[4], 1),
                                        depts={d: sum(1 for lvl, x in DEPT.items() if lvl <= lv and x == d) for d in TINT})
        print("LEVEL", lv, stats["levels"][str(lv)])
        if "aerial" in VIEWS:
            pos, tgt, d = L["fit_camera"](fit_points(b100, 14.0), 1200 / 900)
            set_cam(cam, scene, pos, tgt, lens=L["LENS"])
            world.mist_settings.start = d * 0.9
            render(scene, os.path.join(ART, "L%03d_aerial.png" % lv))
        if "close" in VIEWS and lv <= 18:
            pos, tgt, d = L["fit_camera"](fit_points(b18, 8.0), 1200 / 900)
            set_cam(cam, scene, pos, tgt, lens=L["LENS"])
            world.mist_settings.start = d * 0.9
            render(scene, os.path.join(ART, "L%03d_close.png" % lv))
        if "top" in VIEWS and lv == 100:
            c4 = to_blender((WAFER[4][0], 0, WAFER[4][1]))
            set_cam(cam, scene, Vector((c4[0] + 70, c4[1] + 105, 250.0)), Vector((c4[0], c4[1] - 4, 186.0)), lens=30.0, res=(1200, 800))
            world.mist_settings.start = 500.0
            render(scene, os.path.join(ART, "L%03d_top.png" % lv))
        if "back" in VIEWS and lv in (43, 100):
            set_cam(cam, scene, Vector((-120.0, -190.0, 95.0)), Vector((0.0, -20.0, 40.0 if lv == 43 else 80.0)), lens=30.0, res=(1200, 800))
            world.mist_settings.start = 600.0
            render(scene, os.path.join(ART, "L%03d_back.png" % lv))
        if "court" in VIEWS and lv in (43, 100):
            set_cam(cam, scene, Vector((30.0, -8.0, 36.0)), Vector((-6.0, -46.0, 46.0 if lv == 43 else 70.0)), lens=18.0, res=(1200, 800))
            world.mist_settings.start = 600.0
            render(scene, os.path.join(ART, "L%03d_court.png" % lv))
        if "plaza" in VIEWS and lv in (18, 100):
            pos, tgt = plaza_cam()
            set_cam(cam, scene, pos, tgt, vfov=70.0, res=(1280, 720))
            world.mist_settings.start = 260.0
            render(scene, os.path.join(ART, "L%03d_plaza.png" % lv))
    stats["curve"] = {str(lv): tris_at(lv) for lv in range(1, 101)}
    json.dump(stats, open(os.path.join(ART, "stats.json"), "w"), indent=1)
    if "parts" in VIEWS:
        parts_views(scene, world, cam)
    if "thumbs" in VIEWS:
        thumbs(scene, world, cam)
    print("DONE in %.0fs" % (time.time() - t0))


def parts_views(scene, world, cam):
    """Close views of single pieces, in the same light, on the site's lawn."""
    clear_built()
    for o in list(scene.objects):
        if o.type == "MESH" and o.name != "Site":
            o.hide_render = True
    world.mist_settings.start = 400.0
    # 1. one standard wafer-1 segment, two storeys, from the street: the open end shows the partition
    for s in (0, 1):
        put("W_Seg_1", (0, slab_bottom(s), 0), 0.0, None)
        put("W_Glass_1", (0, slab_bottom(s), 0), 0.0, "eng" if s else "studio")
    set_cam(cam, scene, Vector((-52.0, 84.0, 20.0)), Vector((-8.0, 50.0, 9.0)), lens=30.0, res=(1200, 800))
    render(scene, os.path.join(ART, "part_segment.png"))
    # 2. the lobby between two neighbours, from the forecourt
    clear_built()
    put("W_Lobby", (0, slab_bottom(0), 0), 0.0, None)
    put("W_LobbyGlass", (0, slab_bottom(0), 0), 0.0, "lobby")
    for seg in (2, 8):
        t = math.radians(45 * (seg - 1))
        put("W_Seg_1", (0, slab_bottom(0), 0), t, None)
        put("W_Glass_1", (0, slab_bottom(0), 0), t, "cafe")
    set_cam(cam, scene, Vector((22.0, 108.0, 9.0)), Vector((-3.0, 55.0, 7.0)), lens=26.0, res=(1200, 800))
    render(scene, os.path.join(ART, "part_lobby.png"))
    # 3. the courtyard side: the bridge segment, its neighbours, the lift and a bridge
    clear_built()
    for seg in (4, 5, 6):
        t = math.radians(45 * (seg - 1))
        nm = ("W_SegB_1", "W_GlassB_1") if seg == 5 else ("W_Seg_1", "W_Glass_1")
        for s in (0, 1):
            put(nm[0], (0, slab_bottom(s), 0), t, None)
            put(nm[1], (0, slab_bottom(s), 0), t, "eng" if s else "labs")
    for s in (0, 1):
        put("W_Core", (CORE_X, slab_bottom(s), CORE_Z), 0.0, None)
        put("W_CoreGlass", (CORE_X, slab_bottom(s), CORE_Z), 0.0, "core")
    y = floor_y(1)
    start = CORE_Z - (CORE_R - 0.2)
    land = -(WAFER[1][2] - DEPTH) * math.cos(math.radians(4.5))
    length = start - land
    put("W_Bridge", (CORE_X, y, start), math.pi, None, length / 10.0)
    put("W_BridgeGlass", (CORE_X, y, start), math.pi, "rail", length / 10.0)
    set_cam(cam, scene, Vector((24.0, 8.0, 24.0)), Vector((0.0, -38.0, 9.0)), lens=24.0, res=(1200, 800))
    render(scene, os.path.join(ART, "part_courtyard.png"))


THUMBS = [   # (label, [(mesh, tint)], camera azimuth: 0 = from the front / +Z)
    ("Segment  W_Seg_1 + W_Glass_1", [("W_Seg_1", None), ("W_Glass_1", "eng")], 30),
    ("Bridge segment  W_SegB_1 (courtyard side)", [("W_SegB_1", None), ("W_GlassB_1", "labs")], 205),
    ("Lobby  W_Lobby + W_LobbyGlass", [("W_Lobby", None), ("W_LobbyGlass", "lobby")], 25),
    ("Garden deck  W_Deck_1 + W_DeckGlass_1", [("W_Deck_1", None), ("W_DeckGlass_1", "rail")], 25),
    ("Deck columns  W_DeckCols_1", [("W_DeckCols_1", None), ("W_Deck_1", None)], 25),
    ("Roof garden  W_Roof + W_RoofGlass", [("W_Roof", None), ("W_RoofGlass", "rail")], 25),
    ("Pavilion quarter  W_Pav + W_PavGlass", [("W_Pav", None), ("W_PavGlass", "pav")], 30),
    ("Halo  W_Halo", [("W_Halo", None)], 25),
    ("Lift storey  W_Core + W_CoreGlass + W_CoreCap", [("W_Core", None), ("W_CoreGlass", "core"), ("W_CoreCap", None)], 30),
    ("Lantern  W_Lantern + W_LanternGlass", [("W_Lantern", None), ("W_LanternGlass", "lantern")], 30),
    ("Mast  W_Mast", [("W_Mast", None)], 30),
    ("Skybridge  W_Bridge + W_BridgeGlass (10 long)", [("W_Bridge", None), ("W_BridgeGlass", "rail")], 60),
]


def thumbs(scene, world, cam):
    """One transparent picture per piece, for the sheet's kit grid."""
    out = os.path.join(ART, "thumbs")
    os.makedirs(out, exist_ok=True)
    for o in list(scene.objects):
        if o.type == "MESH":
            o.hide_render = True
    scene.use_nodes = False
    scene.render.film_transparent = True
    scene.render.image_settings.color_mode = "RGBA"
    listing = []
    for i, (label, parts, az) in enumerate(THUMBS):
        clear_built()
        for name, tint in parts:
            put(name, (0.0, 0.0, 0.0), 0.0, tint)
        bpy.context.view_layer.update()
        pts = [o.matrix_world @ Vector(c) for o in BUILT for c in o.bound_box]
        lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
        hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
        ctr = (lo + hi) / 2
        rad = (hi - lo).length / 2
        a, el = math.radians(az), math.radians(24.0)
        d = Vector((-math.sin(a) * math.cos(el), math.cos(a) * math.cos(el), math.sin(el)))
        vfov = 28.0
        dist = rad / math.sin(math.radians(vfov) / 2) * 0.92
        set_cam(cam, scene, ctr + d * dist, ctr, vfov=vfov, res=(640, 480))
        cam.data.clip_start = 0.1
        world.mist_settings.start = 5000.0
        fn = "thumb_%02d.png" % i
        render(scene, os.path.join(out, fn))
        listing.append(dict(label=label, file=fn, tris=sum(META[n]["tris"] for n, _ in parts if not (label.startswith("Deck columns") and n == "W_Deck_1"))))
    json.dump(listing, open(os.path.join(out, "thumbs.json"), "w"), indent=1)


main()
