"""wafers.py -- the game-ready mesh kit for THE WAFERS HQ (30 Sep 2026).

Spec: docs/superpowers/specs/2026-09-30-wafers-hq-design.md. Look: the W concept
(art/concepts/formats/formats_W_sheet.png) with ROUND wafers, so one segment
mesh repeats 8 times per storey. Facade grammar from hq2.py: ribbon windows over
solid spandrels, slim charcoal mullions, no oak fin screens.

THE GEOMETRY CONTRACT is WaferPlan.lua W.GEO (read from the game file at run
time, so the kit can't drift from the collision): storey H 13, slab 1.5, rings
20 deep, 8 segments of 45 degrees per storey, 5 flat facets per segment.

Every mesh is modelled in its PIECE-LOCAL frame (studs, Blender Z up, the piece's
front = plot-local +Z = Blender +Y). The FBX importer lands Blender (x, y, z) at
Roblox (-x, z, y). Frames (the game places the MeshPart at frame * CFrame.new(c)):
  W_Seg_<w> / W_Glass_<w>     origin = wafer centre, at the storey's SLAB BOTTOM
  W_SegB_<w> / W_GlassB_<w>   (-0.5 + 13 s); segment centred on +Z, -22.5..+22.5 deg
  W_Lobby / W_LobbyGlass      floor slab 0-1.5, ceiling slab 11.9-13
  W_Deck_<w> / W_DeckGlass_<w>  origin = wafer w centre at the deck storey's slab
  W_DeckCols_<w>                (columns up to wafer w+1: add with its first piece)
  W_Roof / W_RoofGlass          bottom (= the top of the ring below); walking
                                surface at +0.3 (Wafers.lua DECK_TOP)
  W_Pav / W_PavGlass          one quarter, W4 centre at the roof base, +-45 deg
  W_Halo                      W4 centre; the ring is centred ON the origin (Wafers.lua
                              puts it at floorY(14) + 8)
  W_Core / W_CoreGlass        one storey of the lift: core centre, slab bottom, 13 tall;
                              doors on +Z (the courtyard) and -Z (the bridges)
  W_CoreCap                   same frame as the TOP W_Core: its roof (13 - 13.6)
  W_Lantern / W_LanternGlass  core centre, its base on top of the core; LANTERN_H tall
  W_Mast                      core centre, its base on top of the lantern; 60 tall
  W_Bridge / W_BridgeGlass    10 long along +Z, origin at the near end on the walking
                              surface; the game stretches Z (size and c.Z)
Glass meshes are vertex WHITE: the game tints them (Material Glass).

Colour is vertex colour with baked contact shading (sky light by normal, a shade
band under every slab, darkening where walls meet floors), as in hq.py.

Run:   blender -b --python wafers.py [-- only=W_Seg_1,W_Deck_1]
Out:   out/IMPORT_WAFERS/<name>.fbx, game/src/ServerScriptService/HQMeta/Wafers.lua
Then:  blender -b --python wafers_render.py   (the assembled building, from the FBX)
"""
import bmesh
import bpy
import math
import os
import re
import sys
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import svkit as K  # noqa: E402

OUT = os.path.join(HERE, "out", "IMPORT_WAFERS")
ART = os.path.join(ROOT, "art", "concepts", "wafers_kit")
#[[ gamedir walks up to the directory that actually holds src/ServerScriptService.
#   The old hardcoded ROOT/game/... hop resolved to game/game/... once the
#   blender folder moved inside game/, so the WaferPlan contract silently failed
#   to load and every kit since has been built against the fallback instead --
#   exactly the silent half-wiring gamedir.py was written to stop. ]]
import gamedir  # noqa: E402
PLAN_LUA = os.path.join(gamedir.server_dir(HERE), "WaferPlan.lua")
os.makedirs(OUT, exist_ok=True)
os.makedirs(ART, exist_ok=True)


# ------------------------------------------------------------------ the contract (W.GEO)
def read_geo():
    g = dict(H=13.0, SLAB=1.5, FLOOR_Y=1.0, DEPTH=20.0,
             WAFER={1: (0.0, 0.0, 60.0), 2: (8.0, -5.0, 64.0), 3: (-6.0, -6.0, 58.0), 4: (3.0, -8.0, 54.0)},
             CORE=(0.0, -26.0, 6.0), PAV=(36.0, 44.0))
    try:
        src = open(PLAN_LUA, encoding="utf-8").read()
        geo = src[src.index("W.GEO"):]
        geo = geo[:geo.index("\n}\n")]
        for k in ("H", "SLAB", "FLOOR_Y", "DEPTH"):
            m = re.search(r"\b%s = ([-\d.]+)" % k, geo)
            if m:
                g[k] = float(m.group(1))
        for m in re.finditer(r"\[(\d)\] = \{ cx = ([-\d.]+), cz = ([-\d.]+), r = ([-\d.]+) \}", geo):
            g["WAFER"][int(m.group(1))] = (float(m.group(2)), float(m.group(3)), float(m.group(4)))
        m = re.search(r"CORE = \{ x = ([-\d.]+), z = ([-\d.]+), r = ([-\d.]+) \}", geo)
        if m:
            g["CORE"] = tuple(float(v) for v in m.groups())
        m = re.search(r"PAVILION = \{ rin = ([-\d.]+), rout = ([-\d.]+) \}", geo)
        if m:
            g["PAV"] = tuple(float(v) for v in m.groups())
        print("W.GEO read from WaferPlan.lua:", g)
    except Exception as e:  # noqa: BLE001
        print("W.GEO not readable, using the built-in contract:", e)
    return g


GEO = read_geo()
H, SLAB, DEPTH = GEO["H"], GEO["SLAB"], GEO["DEPTH"]
WAFER = GEO["WAFER"]
CORE_X, CORE_Z, CORE_R = GEO["CORE"]
PAV_IN, PAV_OUT = GEO["PAV"]

# (depth, height) of the shadow gap under a slab edge -- see band()
SLAB_GAP = (0.22, 0.30)

# piece-local heights (slab-bottom frame)
FLOOR_TOP = SLAB           # 1.5: the walking surface of a storey
SILL = 3.7                 # top of the solid spandrel
CEIL0, CEIL1 = 11.9, H     # the ceiling slab: stacked storeys meet exactly at 13
OVH = 0.8                  # slab overhang past both facades
DECK_SURF = 0.3            # deck / roof walking surface (Wafers.lua DECK_TOP + SLAB)
RAIL_H = 3.2               # balustrade height (the game's collision rails)
NFAC = 5                   # facets per 45-degree segment
LOBBY_W, LOBBY_H = 14.0, 10.0
DOOR_W, DOOR_H = 6.0, 8.0
LANTERN_H = 11.2
MAST_H = 60.0

# ------------------------------------------------------------------ palette (art/ART.md)
rgb = K.rgb
PAPER = rgb(243, 239, 230)
SPANDREL = rgb(234, 228, 216)
FLOOR = rgb(222, 212, 194)
CEILING = rgb(236, 232, 222)
ROOF = rgb(216, 208, 194)
OAK = rgb(192, 138, 85)            # the wafer soffits (the concept's warm undersides)
CONCRETE = rgb(207, 198, 182)
PAVE = rgb(224, 216, 200)
CHARCOAL = rgb(58, 62, 70)
LAWN = rgb(122, 170, 80)
LEAF = rgb(96, 150, 78)
LEAF_DARK = rgb(72, 118, 62)
LEAF_LIGHT = rgb(132, 178, 96)
TRACK = rgb(198, 98, 74)
LINE = rgb(240, 232, 212)
BRAND = rgb(255, 194, 61)
WHITE = (1.0, 1.0, 1.0)


# ------------------------------------------------------------------ plane geometry
def P(r, phi):
    """Point at radius r, angle phi (degrees). phi 0 = the front (+Y = Roblox +Z);
    positive phi turns toward Blender -X = Roblox +X, the same way the game's
    CFrame.Angles(0, +a, 0) turns a segment."""
    a = math.radians(phi)
    return (-r * math.sin(a), r * math.cos(a))


def radial(phi):
    return P(1.0, phi)


def angles(a0, a1, n):
    return [a0 + (a1 - a0) * k / n for k in range(n + 1)]


def lerp2(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def v3(p, z):
    return (p[0], p[1], z)


def newell(pts):
    n = Vector((0.0, 0.0, 0.0))
    for i, p in enumerate(pts):
        q = pts[(i + 1) % len(pts)]
        n.x += (p[1] - q[1]) * (p[2] + q[2])
        n.y += (p[2] - q[2]) * (p[0] + q[0])
        n.z += (p[0] - q[0]) * (p[1] + q[1])
    return n


# ------------------------------------------------------------------ the mesh builder
class MB:
    """One flat-shaded mesh: every face owns its vertices and one base colour.
    Contact shading is baked per corner when the object is made."""

    def __init__(self, floors=(), unders=()):
        self.bm = bmesh.new()
        self.meta = []
        self.floors = list(floors)     # z of floor tops: walls darken just above them
        self.unders = list(unders)     # z of slab undersides: walls darken just below them

    def face(self, pts, col, out=None, kind="std"):
        pts = [tuple(p) for p in pts]
        if out is not None and newell(pts).dot(Vector(out)) < 0:
            pts = list(reversed(pts))
        vs = [self.bm.verts.new(p) for p in pts]
        self.bm.faces.new(vs)
        self.meta.append((col, kind))

    def quad(self, a, b, z0, z1, col, out, kind="std"):
        """A vertical quad from plane point a to b, z0..z1."""
        self.face([v3(a, z0), v3(b, z0), v3(b, z1), v3(a, z1)], col, out, kind)

    def shade(self, col, kind, p, n, fc):
        if kind == "flat":
            return col
        if n.z > 0.5:
            k = 1.04
        elif n.z < -0.5:
            k = 0.80
        else:
            k = 0.92
        if abs(n.z) < 0.5:
            for f in self.floors:
                if f - 0.01 <= p.z < f + 1.6:
                    k *= 0.80 + 0.20 * (p.z - f) / 1.6
                    break
            for u in self.unders:
                if u - 1.6 < p.z <= u + 0.01:
                    k *= 0.90
                    break
        h = math.sin(fc.x * 12.9898 + fc.y * 78.233 + fc.z * 37.719) * 43758.5453
        k *= 0.978 + 0.044 * (h - math.floor(h))          # a whisper of per-facet variation
        return tuple(min(1.0, c * k) for c in col)

    def to_object(self, name):
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        attr = me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
        for poly, (col, kind) in zip(me.polygons, self.meta):
            fc = poly.center
            for li in poly.loop_indices:
                p = me.vertices[me.loops[li].vertex_index].co
                c = self.shade(col, kind, p, poly.normal, fc)
                attr.data[li].color_srgb = (c[0], c[1], c[2], 1.0)
        me.color_attributes.active_color = attr
        obj = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(obj)
        return obj


# ------------------------------------------------------------------ primitives
def band(mb, r0, r1, z0, z1, ph, cols, faces="tboi", caps="", gap=None):
    """An annular band on chords between the angles ph, r0 < r1. cols: t b o i c.

    `gap` = (depth, height) cuts a SHADOW GAP into the bottom of the outer
    face: the fascia stops short, a soffit returns inward, and a recessed strip
    runs beneath it. It is the detail that separates a drawn building from an
    extruded box -- every real slab edge has one, and at any distance it reads
    as a crisp dark line under each floor.

    It costs three faces instead of one, on slabs only, and it pairs with the
    baked AO: a recess is concave, so the AO pass darkens it for free.
    """
    C = lambda k: cols.get(k, cols.get("*", PAPER))  # noqa: E731
    for a, b in zip(ph, ph[1:]):
        i0, i1, o0, o1 = P(r0, a), P(r0, b), P(r1, a), P(r1, b)
        rd = radial((a + b) / 2)
        if "t" in faces:
            mb.face([v3(i0, z1), v3(o0, z1), v3(o1, z1), v3(i1, z1)], C("t"), (0, 0, 1))
        if "b" in faces:
            mb.face([v3(i0, z0), v3(i1, z0), v3(o1, z0), v3(o0, z0)], C("b"), (0, 0, -1))
        if "o" in faces and gap:
            gd, gh = gap
            zg = z0 + gh
            rg = r1 - gd
            g0, g1 = P(rg, a), P(rg, b)
            mb.quad(o0, o1, zg, z1, C("o"), (rd[0], rd[1], 0))              # the fascia
            mb.face([v3(g0, zg), v3(g1, zg), v3(o1, zg), v3(o0, zg)],       # soffit, facing down
                    C("b"), (0, 0, -1))
            mb.quad(g0, g1, z0, zg, C("o"), (rd[0], rd[1], 0))              # the recess
        elif "o" in faces:
            mb.quad(o0, o1, z0, z1, C("o"), (rd[0], rd[1], 0))
        if "i" in faces:
            mb.quad(i0, i1, z0, z1, C("i"), (-rd[0], -rd[1], 0))
    if "s" in caps:
        a = ph[0]
        mb.quad(P(r0, a), P(r1, a), z0, z1, C("c"), (math.cos(math.radians(a)), math.sin(math.radians(a)), 0))
    if "e" in caps:
        b = ph[-1]
        mb.quad(P(r0, b), P(r1, b), z0, z1, C("c"), (-math.cos(math.radians(b)), -math.sin(math.radians(b)), 0))


def obox(mb, c, u, hu, hv, z0, z1, col, faces="tbUuVv"):
    """A box centred at plane point c, axis u (unit 2D) with half-size hu, the
    perpendicular v with half-size hv, z0..z1. faces: t b U u V v (U = +u side)."""
    v = (-u[1], u[0])

    def pt(su, sv):
        return (c[0] + u[0] * hu * su + v[0] * hv * sv, c[1] + u[1] * hu * su + v[1] * hv * sv)
    if "U" in faces:
        mb.quad(pt(1, -1), pt(1, 1), z0, z1, col, (u[0], u[1], 0))
    if "u" in faces:
        mb.quad(pt(-1, -1), pt(-1, 1), z0, z1, col, (-u[0], -u[1], 0))
    if "V" in faces:
        mb.quad(pt(-1, 1), pt(1, 1), z0, z1, col, (v[0], v[1], 0))
    if "v" in faces:
        mb.quad(pt(-1, -1), pt(1, -1), z0, z1, col, (-v[0], -v[1], 0))
    if "t" in faces:
        mb.face([v3(pt(-1, -1), z1), v3(pt(1, -1), z1), v3(pt(1, 1), z1), v3(pt(-1, 1), z1)], col, (0, 0, 1))
    if "b" in faces:
        mb.face([v3(pt(-1, -1), z0), v3(pt(1, -1), z0), v3(pt(1, 1), z0), v3(pt(-1, 1), z0)], col, (0, 0, -1))


def rbox(mb, rho0, rho1, phi, w, z0, z1, col, faces="UuVv", off=0.0):
    """A box pointing along the radius at phi: rho0..rho1 radially, w wide, shifted
    `off` sideways (toward +phi)."""
    u = radial(phi)
    t = (-u[1], u[0])          # +phi side
    m = P((rho0 + rho1) / 2, phi)
    c = (m[0] + t[0] * off, m[1] + t[1] * off)
    obox(mb, c, u, (rho1 - rho0) / 2, w / 2, z0, z1, col, faces)


def prism(mb, c, n, r0, r1, z0, z1, col, faces="s", rot=0.0, cols=None):
    """A regular n-gon prism (r1 = top radius, for tapers; r1 = 0 = a point)."""
    cols = cols or {}
    B = [(c[0] + r0 * math.cos(rot + 2 * math.pi * i / n), c[1] + r0 * math.sin(rot + 2 * math.pi * i / n)) for i in range(n)]
    T = [(c[0] + r1 * math.cos(rot + 2 * math.pi * i / n), c[1] + r1 * math.sin(rot + 2 * math.pi * i / n)) for i in range(n)]
    if "s" in faces:
        for i in range(n):
            j = (i + 1) % n
            mid = ((B[i][0] + B[j][0]) / 2 - c[0], (B[i][1] + B[j][1]) / 2 - c[1], 0)
            if r1 < 1e-6:
                mb.face([v3(B[i], z0), v3(B[j], z0), (c[0], c[1], z1)], cols.get("s", col), mid)
            else:
                mb.face([v3(B[i], z0), v3(B[j], z0), v3(T[j], z1), v3(T[i], z1)], cols.get("s", col), mid)
    if "t" in faces and r1 > 1e-6:
        mb.face([v3(p, z1) for p in T], cols.get("t", col), (0, 0, 1))
    if "b" in faces:
        mb.face([v3(p, z0) for p in B], cols.get("b", col), (0, 0, -1))


def icosa(mb, c, z, r, col, squash=0.78, seed=0):
    """A lumpy low-poly shrub: an icosahedron with jittered vertices (20 tris)."""
    t = (1 + 5 ** 0.5) / 2
    vs = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
          (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    fs = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6),
          (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7),
          (9, 8, 1)]
    L = (1 + t * t) ** 0.5
    pts = []
    for i, (x, y, zz) in enumerate(vs):
        h = math.sin((i + 1) * 12.9898 + seed * 78.233) * 43758.5453
        j = 0.86 + 0.28 * (h - math.floor(h))
        pts.append((c[0] + x / L * r * j, c[1] + y / L * r * j, z + r * squash + zz / L * r * squash * j))
    for f in fs:
        tri = [pts[i] for i in f]
        ctr = [sum(p[k] for p in tri) / 3 for k in range(3)]
        mb.face(tri, col, (ctr[0] - c[0], ctr[1] - c[1], ctr[2] - (z + r * squash)))


# ------------------------------------------------------------------ facades with openings
def chord_pieces(r, a, b, op):
    """The chord at radius r from angle a to b, split where an opening's x-range
    crosses it. Returns [(p0, p1, inside)]. op = dict(x=(xl, xr), z=height, y=+1/-1/0)."""
    A, B = P(r, a), P(r, b)
    if not op:
        return [(A, B, False)]
    if op.get("y", 0) and (A[1] + B[1]) * op["y"] < 0:
        return [(A, B, False)]
    xl, xr = op["x"]
    ts = [0.0, 1.0]
    dx = B[0] - A[0]
    if abs(dx) > 1e-9:
        for x in (xl, xr):
            t = (x - A[0]) / dx
            if 1e-6 < t < 1 - 1e-6:
                ts.append(t)
    ts.sort()
    out = []
    for t0, t1 in zip(ts, ts[1:]):
        xm = A[0] + dx * (t0 + t1) / 2
        out.append((lerp2(A, B, t0), lerp2(A, B, t1), xl < xm < xr))
    return out


def panel(mb, r, z0, z1, ph, col, side, op=None, kind="std"):
    """One face per chord piece, facing out (side +1) or in (-1); an opening
    removes the part below op['z'] inside its x-range."""
    for a, b in zip(ph, ph[1:]):
        rd = radial((a + b) / 2)
        for p0, p1, inside in chord_pieces(r, a, b, op):
            lo = max(z0, op["z"]) if inside else z0
            if lo < z1 - 1e-6:
                mb.quad(p0, p1, lo, z1, col, (side * rd[0], side * rd[1], 0), kind)


def glass_band(mb, r, z0, z1, ph, op=None, t=0.1):
    """Glass, two-sided (Roblox renders meshes one-sided), 2t thick, vertex white."""
    panel(mb, r + t, z0, z1, ph, WHITE, 1, op, "flat")
    panel(mb, r - t, z0, z1, ph, WHITE, -1, op, "flat")


def thick_wall(mb, r0, r1, z0, z1, ph, col, op=None, top=True):
    """A solid wall between radii r0 < r1 (a spandrel): outer and inner faces, the
    top, and reveals where an opening cuts it."""
    panel(mb, r1, z0, z1, ph, col, 1, op)
    panel(mb, r0, z0, z1, ph, col, -1, op)
    for a, b in zip(ph, ph[1:]):
        po = chord_pieces(r1, a, b, op)
        pi = chord_pieces(r0, a, b, op)
        if len(po) != len(pi):
            continue
        for k, ((o0, o1, ins), (i0, i1, _)) in enumerate(zip(po, pi)):
            lo = max(z0, op["z"]) if ins else z0
            if lo >= z1 - 1e-6:
                continue
            if top:
                mb.face([v3(i0, z1), v3(o0, z1), v3(o1, z1), v3(i1, z1)], col, (0, 0, 1))
            if ins and lo > z0:
                mb.face([v3(i0, lo), v3(i1, lo), v3(o1, lo), v3(o0, lo)], col, (0, 0, -1))
            # reveals: where this piece is solid next to an opening piece
            if not ins:
                for j, (q_o, q_i) in ((k - 1, (o0, i0)), (k + 1, (o1, i1))):
                    if 0 <= j < len(po) and po[j][2]:
                        zr = min(z1, op["z"])
                        inward = lerp2(po[j][0], po[j][1], 0.5)
                        d = (inward[0] - q_o[0], inward[1] - q_o[1], 0)
                        mb.quad(q_i, q_o, z0, zr, col, d)


def point_at_x(r, ph, x, ysign):
    """Where the facade chord at radius r crosses plan x (on the ysign side):
    (point, unit chord direction)."""
    for a, b in zip(ph, ph[1:]):
        A, B = P(r, a), P(r, b)
        if (A[1] + B[1]) * ysign < 0:
            continue
        dx = B[0] - A[0]
        if abs(dx) < 1e-9:
            continue
        t = (x - A[0]) / dx
        if -1e-6 <= t <= 1 + 1e-6:
            L = math.hypot(B[0] - A[0], B[1] - A[1])
            return lerp2(A, B, t), ((B[0] - A[0]) / L, (B[1] - A[1]) / L)
    return None, None


def door_frame(mb, rg, ph, xl, xr, zb, zh, ysign, depth=0.9):
    """Charcoal jambs at both sides of an opening at the glass radius rg, and a
    head across it (zh..zh+0.4)."""
    for x, s in ((xl, -1), (xr, 1)):
        p, u = point_at_x(rg, ph, x + s * 0.2, ysign)
        if p is None:
            continue
        obox(mb, p, u, 0.2, depth / 2, zb, zh + 0.4, CHARCOAL, "UuVvt")
    op = dict(x=(xl, xr), z=1e9, y=ysign)       # "inside only": everything outside is removed
    for a, b in zip(ph, ph[1:]):
        for (o0, o1, ins), (i0, i1, _) in zip(chord_pieces(rg + depth / 2, a, b, op), chord_pieces(rg - depth / 2, a, b, op)):
            if not ins:
                continue
            rd = radial((a + b) / 2)
            mb.quad(o0, o1, zh, zh + 0.4, CHARCOAL, (rd[0], rd[1], 0))
            mb.quad(i0, i1, zh, zh + 0.4, CHARCOAL, (-rd[0], -rd[1], 0))
            mb.face([v3(i0, zh), v3(i1, zh), v3(o1, zh), v3(o0, zh)], CHARCOAL, (0, 0, -1))


def mullions(mb, rho0, rho1, ph, z0, z1, op=None, w=0.34):
    """Slim charcoal mullions at the facet vertices strictly inside ph."""
    for phi in ph[1:-1]:
        lo = z0
        if op:
            x, y = P((rho0 + rho1) / 2, phi)
            if (not op.get("y") or y * op["y"] > 0) and op["x"][0] - 0.45 < x < op["x"][1] + 0.45:
                if op["z"] + 0.4 >= z1:
                    continue
                lo = op["z"] + 0.4
        rbox(mb, rho0, rho1, phi, w, lo, z1, CHARCOAL, "UuVv")


# ------------------------------------------------------------------ the segment
def seg_angles():
    return angles(-22.5, 22.5, NFAC)


def partition(mb, gl, r, phs):
    """A radial glass partition at the segment end phs (+-22.5), set inside the
    seam, with a 6 x 8 doorway round the ring; charcoal posts and door frame."""
    rin = r - DEPTH
    u = radial(phs)
    s = 1.0 if phs > 0 else -1.0
    a = math.radians(phs)
    n = (s * math.cos(a), s * math.sin(a))       # toward the segment's centre

    def Q(rho, off):
        return (u[0] * rho + n[0] * off, u[1] * rho + n[1] * off)
    rm = r - DEPTH / 2
    d0, d1 = rm - DOOR_W / 2, rm + DOOR_W / 2
    zd = FLOOR_TOP + DOOR_H
    # glass: two faces, 0.15 and 0.3 in from the seam
    for (ra, rb, za, zb) in ((rin + 0.75, d0, FLOOR_TOP, CEIL0), (d1, r - 0.75, FLOOR_TOP, CEIL0), (d0, d1, zd + 0.4, CEIL0)):
        gl.quad(Q(ra, 0.15), Q(rb, 0.15), za, zb, WHITE, (-n[0], -n[1], 0), "flat")
        gl.quad(Q(ra, 0.30), Q(rb, 0.30), za, zb, WHITE, (n[0], n[1], 0), "flat")
    # posts where it meets the facades (they read as the seam mullions)
    c_off = 0.22
    for (ra, rb) in ((r - 0.75, r - 0.05), (rin + 0.05, rin + 0.75), (d0 - 0.35, d0), (d1, d1 + 0.35)):
        top = CEIL0 if ra < rin + 1 or rb > r - 1 else zd + 0.4
        c = Q((ra + rb) / 2, c_off)
        obox(mb, c, u, (rb - ra) / 2, 0.2, FLOOR_TOP, top, CHARCOAL, "UuVv")
    # door head
    c = Q(rm, c_off)
    obox(mb, c, u, DOOR_W / 2, 0.2, zd, zd + 0.4, CHARCOAL, "Vvb")


def build_segment(w, variant):
    """variant: 'plain' | 'bridge' (a door in the inner facade) | 'lobby'."""
    r = WAFER[w][2]
    rin = r - DEPTH
    ph = seg_angles()
    unders = [CEIL0] + ([CANOPY_Z] if variant == "lobby" else [])
    mb = MB(floors=[FLOOR_TOP], unders=unders)
    gl = MB()
    # slabs: the floor (oak soffit under it, seen at cantilevers) and the ceiling
    band(mb, rin - OVH, r + OVH, 0.0, SLAB, ph, dict(t=FLOOR, b=OAK, o=PAPER, i=PAPER, c=PAPER), "tboi", "se", SLAB_GAP)
    band(mb, rin - OVH, r + OVH, CEIL0, CEIL1, ph, dict(t=ROOF, b=CEILING, o=PAPER, i=PAPER, c=PAPER), "tboi", "se", SLAB_GAP)
    op_out = op_in = None
    if variant == "lobby":
        op_out = dict(x=(-LOBBY_W / 2, LOBBY_W / 2), z=FLOOR_TOP + LOBBY_H, y=1)
        op_in = dict(op_out)
    elif variant == "bridge":
        op_in = dict(x=(-DOOR_W / 2, DOOR_W / 2), z=FLOOR_TOP + DOOR_H, y=1)
    # outer facade: spandrel r-0.6..r, glass centred r-0.35, mullions r-0.7..r-0.05
    thick_wall(mb, r - 0.6, r, FLOOR_TOP, SILL, ph, SPANDREL, op_out)
    glass_band(gl, r - 0.35, SILL, CEIL0, ph, dict(op_out, z=CEIL0 + 1) if op_out else None)
    mullions(mb, r - 0.7, r - 0.05, ph, SILL, CEIL0, op_out)
    # inner (courtyard) facade, mirrored
    thick_wall(mb, rin, rin + 0.6, FLOOR_TOP, SILL, ph, SPANDREL, op_in)
    gop = None
    if op_in:
        # the lobby opening takes the glass to the ceiling (a charcoal head fills 11.5-11.9);
        # above the bridge door a glass transom starts on the door head
        gop = dict(op_in, z=CEIL0 + 1) if variant == "lobby" else dict(op_in, z=op_in["z"] + 0.4)
    glass_band(gl, rin + 0.35, SILL, CEIL0, ph, gop)
    mullions(mb, rin + 0.05, rin + 0.7, ph, SILL, CEIL0, op_in)
    # openings: frames
    if variant == "lobby":
        for rg in (r - 0.35, rin + 0.35):
            door_frame(mb, rg, ph, -LOBBY_W / 2, LOBBY_W / 2, FLOOR_TOP, FLOOR_TOP + LOBBY_H, 1)
        canopy(mb, r)
    elif variant == "bridge":
        door_frame(mb, rin + 0.35, ph, -DOOR_W / 2, DOOR_W / 2, FLOOR_TOP, FLOOR_TOP + DOOR_H, 1)
    for phs in (-22.5, 22.5):
        partition(mb, gl, r, phs)
    return mb, gl


def canopy(mb, r):
    """The lobby's floating paper canopy over the street: detached from the facade
    by a shadow gap, an oak soffit, on two slim columns at its far corners."""
    r0, r1 = r + 1.0, r + 12.5
    half = math.degrees(math.asin(13.0 / r1))
    ph = angles(-half, half, 3)
    band(mb, r0, r1, CANOPY_Z, CANOPY_Z + 0.8, ph, dict(t=ROOF, b=OAK, o=PAPER, i=PAPER, c=PAPER), "tboi", "se")
    for phi in (-half * 0.86, half * 0.86):
        prism(mb, P(r1 - 1.0, phi), 8, 0.28, 0.28, 0.6, CANOPY_Z, PAPER, "s")


CANOPY_Z = 10.2


# ------------------------------------------------------------------ decks and the roof
RING40 = angles(4.5, 364.5, 40)       # the building's facet rhythm (every 9 deg, vertices at 4.5 + 9k)
RING20 = angles(4.5, 364.5, 20)


def rails(mb, gl, rho, ph, gap=None):
    """A frameless glass balustrade with a paper cap at radius rho."""
    op = dict(x=(-gap, gap), z=1e9, y=-1) if gap else None
    glass_band(gl, rho, DECK_SURF, DECK_SURF + RAIL_H, ph, op, t=0.08)
    for a, b in zip(ph, ph[1:]):
        for (o0, o1, ins), (i0, i1, _) in zip(chord_pieces(rho + 0.2, a, b, op), chord_pieces(rho - 0.2, a, b, op)):
            if ins:
                continue
            z0, z1 = DECK_SURF + RAIL_H, DECK_SURF + RAIL_H + 0.22
            rd = radial((a + b) / 2)
            mb.face([v3(i0, z1), v3(o0, z1), v3(o1, z1), v3(i1, z1)], PAPER, (0, 0, 1))
            mb.quad(o0, o1, z0, z1, PAPER, (rd[0], rd[1], 0))
            mb.quad(i0, i1, z0, z1, PAPER, (-rd[0], -rd[1], 0))
    if gap:  # posts at the gap ends
        for x in (-gap - 0.15, gap + 0.15):
            p, u = point_at_x(rho, ph, x, -1)
            if p is not None:
                obox(mb, p, u, 0.15, 0.25, DECK_SURF, DECK_SURF + RAIL_H + 0.22, CHARCOAL, "UuVvt")


def beds(mb, rho0, rho1, n=8, span=17.0, seed=0, per=3):
    """Raised planted beds (lawn tops, concrete sides) with lumpy shrubs."""
    greens = (LEAF, LEAF_DARK, LEAF_LIGHT)
    for j in range(n):
        c = j * 360.0 / n
        band(mb, rho0, rho1, DECK_SURF, 1.5, angles(c - span, c + span, 4),
             dict(t=LAWN, o=CONCRETE, i=CONCRETE, c=CONCRETE), "toi", "se")
        for k in range(per):
            h = math.sin((j * 7 + k + seed) * 91.3) * 43758.5453
            f = h - math.floor(h)
            phi = c + (k - (per - 1) / 2) * (2 * span / per) * 0.9 + (f - 0.5) * 4
            rr = (rho0 + rho1) / 2 + (f - 0.5) * (rho1 - rho0) * 0.35
            icosa(mb, P(rr, phi), 1.5 - 0.3, 1.25 + 0.7 * f, greens[(j + k) % 3], seed=j * 5 + k + seed)


def build_deck(w):
    """Garden deck on top of wafer w: paving, a terracotta running track, planted
    beds and glass balustrades (the inner one open at the back for the lift bridge)."""
    r = WAFER[w][2]
    rin = r - DEPTH
    mb = MB(floors=[DECK_SURF, 1.5])
    gl = MB()
    band(mb, rin - 0.3, r + 0.3, 0.0, DECK_SURF, RING40, dict(t=PAVE, o=PAPER, i=PAPER), "toi")
    tr0, tr1 = track(r)
    band(mb, tr0, tr1, DECK_SURF, DECK_SURF + 0.06, RING40, dict(t=TRACK), "t")
    band(mb, (tr0 + tr1) / 2 - 0.14, (tr0 + tr1) / 2 + 0.14, DECK_SURF + 0.06, DECK_SURF + 0.1, RING40, dict(t=LINE), "t")
    beds(mb, r - 7.4, r - 1.3, seed=w * 13)
    rails(mb, gl, r - 0.35, RING20)
    rails(mb, gl, rin + 0.35, RING20, gap=3.4)
    return mb, gl


def track(r):
    return r - 12.4, r - 8.4


def build_deck_columns(w):
    """W_DeckCols_<w>: the columns from deck w up to wafer w+1's underside, where
    both rings overlap. Its own mesh (same frame as W_Deck_<w>) so the game adds it
    with wafer w+1's first piece: company 1 ends on deck 1, with nothing above it."""
    cx1, cz1, r = WAFER[w]
    cx2, cz2, r2 = WAFER[w + 1]
    rin = r - DEPTH
    tr0, tr1 = track(r)
    mb = MB(floors=[DECK_SURF], unders=[H])
    ox, oy = -(cx2 - cx1), (cz2 - cz1)              # the upper centre, in this Blender frame
    placed = []
    for rho in (r2 - DEPTH + 3.0, r2 - DEPTH / 2, r2 - 3.0):     # the upper ring's structural rows
        for j in range(24):
            q = P(rho, 15.0 * j + (7.5 if rho == r2 - DEPTH / 2 else 0.0))
            x, y = ox + q[0], oy + q[1]
            d = math.hypot(x, y)
            if not (rin + 1.6 < d < r - 1.7):
                continue
            if tr0 - 1.1 < d < tr1 + 1.1:              # never on the running track
                continue
            if y < 0 and abs(x) < 5.0 and d < rin + 7:        # the bridge landing
                continue
            if any(math.hypot(x - a, y - b) < 7.0 for a, b in placed):
                continue
            placed.append((x, y))
            prism(mb, (x, y), 8, 0.85, 0.85, DECK_SURF, H, PAPER, "s", rot=math.pi / 8)
    print("  deck %d: %d columns up to wafer %d" % (w, len(placed), w + 1))
    return mb, None


def build_roof():
    """The roof garden on wafer 4: paving under the pavilion, a planted band
    outside it, glass balustrades (a gap at the back where the lift bridge lands)."""
    r = WAFER[4][2]
    rin = r - DEPTH
    mb = MB(floors=[DECK_SURF, 1.5])
    gl = MB()
    band(mb, rin - 0.3, r + 0.3, 0.0, DECK_SURF, RING40, dict(t=PAVE, o=PAPER, i=PAPER), "toi")
    beds(mb, PAV_OUT + 3.6, r - 1.3, n=12, span=11.0, seed=71, per=2)
    rails(mb, gl, r - 0.35, RING20)
    rails(mb, gl, rin + 0.35, RING20, gap=3.4)
    return mb, gl


def build_pavilion():
    """One quarter of the founder pavilion: glass on both faces with a door in the
    middle of each, charcoal mullions, a slim flat roof. Centred on +Y, +-45 deg."""
    ph = angles(-45.0, 45.0, 10)
    z0, z1 = DECK_SURF, DECK_SURF + 9.0
    mb = MB(floors=[z0], unders=[z1])
    gl = MB()
    op = dict(x=(-DOOR_W / 2, DOOR_W / 2), z=z0 + DOOR_H, y=1)
    for rg in (PAV_OUT, PAV_IN):
        glass_band(gl, rg, z0, z1, ph, dict(op, z=op["z"] + 0.4))
        mullions(mb, rg - 0.35, rg + 0.35, ph, z0, z1, op, w=0.3)
        door_frame(mb, rg, ph, -DOOR_W / 2, DOOR_W / 2, z0, z0 + DOOR_H, 1, depth=0.7)
        for phi in (-45.0, 45.0):     # end posts, set inside the seam
            s = 1.0 if phi < 0 else -1.0
            rbox(mb, rg - 0.35, rg + 0.35, phi, 0.34, z0, z1, CHARCOAL, "UuVv", off=s * 0.19)
    band(mb, PAV_IN - 1.4, PAV_OUT + 1.4, z1, z1 + 0.8, ph, dict(t=ROOF, b=CEILING, o=PAPER, i=PAPER, c=PAPER), "tboi", "se")
    return mb, gl


# ------------------------------------------------------------------ BASE AND CROWN
#
# THE DIAGNOSIS (3 Oct). All three paths were pure SHAFT. They started at the
# ground and stopped at the top, which is why every render read as "a stack of
# rings" however much the rings themselves differed.
#
# Tall buildings have been solved this way since 1899: BASE, SHAFT, CROWN -- the
# tripartite division, borrowed from the classical column, and the reason a
# setback tower has a recognisable silhouette at all. A shaft with no base has
# nothing to stand on; a shaft with no crown does not end, it just stops.
#
# So every path now gets:
#   PODIUM  a storey-and-a-half plinth WIDER than the shaft, with a deep
#           entrance recess on the road side. The building sits on something.
#   CROWN   a real termination. The old one was a single 1.6-stud hoop.
#
# Each path expresses both in its own language, which is also the cheapest way
# to make them further apart: the base and the crown are the two parts of a
# tower a person actually looks at.


def podium_ring(mb, r, z0, z1, cols, step=0.0):
    """The plinth itself: a ring, optionally stepped in as it rises."""
    band(mb, r - DEPTH - 2.0, r, z0, z1, RING40, cols, "tboi", "se")
    if step > 0:
        band(mb, r - DEPTH - 2.0 + step, r - step, z1, z1 + 1.2, RING40, cols, "tboi", "se")


def entrance_recess(mb, r, z0, z1, col, width=26.0):
    """A deep notch on the road side (+Y). An entrance you can see from the
    plaza is the one thing a podium has to do."""
    half = math.degrees(math.asin(min(0.99, width / 2 / max(r, 1))))
    ph = angles(-half, half, 6)
    band(mb, r - 7.0, r + 0.4, z0, z1, ph, dict(t=col, b=col, o=col, i=col, c=col), "tboi")


PODIUM_H = 16.0        # a storey and a quarter: enough to read as a base
CROWN_H = 22.0


def build_podium():
    """WAFERS: a stone colonnade. Deep piers, a shadowed reveal behind them, and
    a broad flat canopy over the entrance -- Samsung's podium is a quiet plinth
    that lets the wafers above do the talking."""
    r = WAFER[1][2] + 6.0
    mb = MB(floors=[0.0], unders=[PODIUM_H])
    gl = MB()
    stone = rgb(214, 206, 190)
    stone_d = rgb(182, 174, 158)
    # the plinth
    band(mb, r - DEPTH - 4.0, r, 0.0, 2.2, RING40, dict(t=stone, o=stone_d, i=stone_d), "toi")
    # the colonnade: deep piers on a regular beat, with the wall set back behind
    band(mb, r - 5.4, r - 4.2, 2.2, PODIUM_H, RING40, dict(t=stone_d, b=stone_d, o=stone_d, i=stone_d, c=stone_d), "tboi")
    for j in range(24):
        a = j / 24 * 360.0
        x, y = P(r - 2.2, a)
        obox(mb, (x, y), radial(a), 1.5, 1.6, 2.2, PODIUM_H, stone)
    # the lintel the piers carry, and the cap the shaft lands on
    band(mb, r - 4.4, r + 0.6, PODIUM_H, PODIUM_H + 2.4, RING40, dict(t=stone, b=stone_d, o=stone, i=stone, c=stone_d), "tboi", "se")
    # entrance: the piers stop and a glazed recess takes their place
    entrance_recess(mb, r, 2.2, PODIUM_H, stone_d, 30.0)
    half = math.degrees(math.asin(15.0 / r))
    glass_band(gl, r - 3.2, 2.6, PODIUM_H - 1.0, angles(-half, half, 6))
    return mb, gl


def build_crown():
    """WAFERS: a stepped parapet. Three rings setting back as they rise, which is
    the 1916 ziggurat move and still the clearest way to say 'this is the top'.
    A slim brand mast finishes it."""
    r = WAFER[4][2]
    mb = MB(floors=[0.0])
    pale = rgb(236, 232, 222)
    for k, (inset, h) in enumerate(((0.0, 0.0), (4.5, 5.0), (9.0, 9.4))):
        band(mb, r - DEPTH + inset, r - inset, h, h + 4.6, RING40,
             dict(t=pale, b=CONCRETE, o=pale, i=pale, c=CONCRETE), "tboi", "se")
    # the planted top step
    band(mb, r - DEPTH + 10.5, r - 10.5, 14.0, 14.6, RING40, dict(t=LAWN, o=LAWN, i=LAWN), "toi")
    # a mast, and the brand ring held off it
    prism(mb, (0.0, 0.0), 8, 0.7, 0.7, 14.6, CROWN_H + 10.0, pale)
    band(mb, 6.0, 7.6, CROWN_H + 2.0, CROWN_H + 3.0, RING40, dict(t=BRAND, b=BRAND, o=BRAND, i=BRAND), "tboi")
    return mb, None          # no glass on this crown: an empty mesh is a wasted import


def build_halo():
    mb = MB()
    band(mb, 54.2, 55.8, -0.5, 0.5, RING40, dict(t=BRAND, b=BRAND, o=BRAND, i=BRAND), "tboi")
    return mb, None


def ngon(r, n=12, rot=0.0):
    return [(r * math.cos(rot + 2 * math.pi * i / n), r * math.sin(rot + 2 * math.pi * i / n)) for i in range(n)]


def build_core():
    """One storey of the glass lift: a floor disc with a charcoal edge, the glass
    tube (doors 6 wide on +Y and -Y), charcoal posts at the door jambs and sides."""
    mb = MB(floors=[FLOOR_TOP])
    gl = MB()
    rot = math.pi / 2          # a vertex on +Y: the doors are the two facets either side
    prism(mb, (0, 0), 12, CORE_R + 0.6, CORE_R + 0.6, 0.0, SLAB, CHARCOAL, "stb", rot=rot,
          cols=dict(t=FLOOR, b=CEILING, s=CHARCOAL))
    ph = angles(0.0, 360.0, 12)
    zd = FLOOR_TOP + DOOR_H
    # the tube: doors where |x| < 3 on both the +Y and -Y sides
    for a, b in zip(ph, ph[1:]):
        mid = P(CORE_R, (a + b) / 2)
        door = abs(mid[0]) < 3.0
        lo = zd if door else FLOOR_TOP
        rd = radial((a + b) / 2)
        for rr, s in ((CORE_R + 0.1, 1), (CORE_R - 0.1, -1)):
            gl.quad(P(rr, a), P(rr, b), lo, H, WHITE, (s * rd[0], s * rd[1], 0), "flat")
        if door:
            rbox_band = [(P(CORE_R + 0.35, a), P(CORE_R + 0.35, b)), (P(CORE_R - 0.35, a), P(CORE_R - 0.35, b))]
            (o0, o1), (i0, i1) = rbox_band
            mb.quad(o0, o1, zd, zd + 0.4, CHARCOAL, (rd[0], rd[1], 0))
            mb.quad(i0, i1, zd, zd + 0.4, CHARCOAL, (-rd[0], -rd[1], 0))
            mb.face([v3(i0, zd), v3(i1, zd), v3(o1, zd), v3(o0, zd)], CHARCOAL, (0, 0, -1))
    for phi in (-30.0, 30.0, 150.0, 210.0, 90.0, 270.0):
        rbox(mb, CORE_R - 0.35, CORE_R + 0.35, phi, 0.42, FLOOR_TOP, H, CHARCOAL, "UuVv")
    return mb, gl


def build_cap():
    """W_CoreCap: a roof on the top storey of the lift (same frame as that W_Core),
    so the tube never ends open. The lantern sits over it at level 99."""
    mb = MB()
    prism(mb, (0, 0), 12, CORE_R + 0.6, CORE_R + 0.6, H, H + 0.6, CHARCOAL, "stb", rot=math.pi / 2,
          cols=dict(t=ROOF, b=CEILING, s=CHARCOAL))
    return mb, None


def build_lantern():
    mb = MB(floors=[1.0], unders=[9.2])
    gl = MB()
    rot = math.pi / 2
    prism(mb, (0, 0), 12, CORE_R + 0.8, CORE_R + 0.8, 0.0, 1.0, PAPER, "stb", rot=rot, cols=dict(t=FLOOR, b=CEILING))
    ph = angles(0.0, 360.0, 12)
    for a, b in zip(ph, ph[1:]):
        rd = radial((a + b) / 2)
        for rr, s in ((5.7, 1), (5.5, -1)):
            gl.quad(P(rr, a), P(rr, b), 1.0, 9.2, WHITE, (s * rd[0], s * rd[1], 0), "flat")
    for k in range(6):
        rbox(mb, 5.25, 5.95, 60.0 * k, 0.4, 1.0, 9.2, CHARCOAL, "UuVv")
    prism(mb, (0, 0), 12, 7.6, 7.6, 9.2, 10.4, PAPER, "stb", rot=rot, cols=dict(t=ROOF, b=CEILING))
    prism(mb, (0, 0), 12, 3.4, 3.4, 10.4, LANTERN_H, PAPER, "st", rot=rot, cols=dict(t=BRAND))
    return mb, gl


def build_mast():
    mb = MB()
    prism(mb, (0, 0), 8, 2.2, 2.2, 0.0, 1.6, PAPER, "st", rot=math.pi / 8)
    prism(mb, (0, 0), 8, 1.3, 0.5, 1.6, 48.0, PAPER, "s", rot=math.pi / 8)
    prism(mb, (0, 0), 8, 0.5, 0.0, 48.0, MAST_H, BRAND, "s", rot=math.pi / 8)
    return mb, None


def build_bridge():
    """A glass skybridge 10 long along +Y (the game stretches it): floor, roof,
    charcoal edge rails, glass sides. Origin = near end, on the walking surface."""
    L, hw = 10.0, 2.8
    mb = MB(floors=[0.0], unders=[8.0])
    gl = MB()
    obox(mb, (0, L / 2), (0, 1), L / 2, hw, -1.0, 0.0, PAPER, "tbUuVv")
    obox(mb, (0, L / 2), (0, 1), L / 2, hw, 8.0, 8.6, PAPER, "tbUuVv")
    for x in (-2.6, 2.6):
        obox(mb, (x, L / 2), (0, 1), L / 2, 0.16, 0.0, 0.35, CHARCOAL, "tVv")
        obox(mb, (x, L / 2), (0, 1), L / 2, 0.16, 7.65, 8.0, CHARCOAL, "bVv")
        for s in (1, -1):
            gl.quad((x + s * 0.06, 0.0), (x + s * 0.06, L), 0.35, 7.65, WHITE, (s, 0, 0), "flat")
    return mb, gl


# ------------------------------------------------------------------ the kit
def kit():
    k = {}
    for w in (1, 2, 3, 4):
        k["W_Seg_%d" % w] = (lambda w=w: build_segment(w, "plain"), "W_Glass_%d" % w)
        k["W_SegB_%d" % w] = (lambda w=w: build_segment(w, "bridge"), "W_GlassB_%d" % w)
    k["W_Lobby"] = (lambda: build_segment(1, "lobby"), "W_LobbyGlass")
    for w in (1, 2, 3):
        k["W_Deck_%d" % w] = (lambda w=w: build_deck(w), "W_DeckGlass_%d" % w)
        k["W_DeckCols_%d" % w] = (lambda w=w: build_deck_columns(w), None)
    k["W_Roof"] = (build_roof, "W_RoofGlass")
    k["W_Pav"] = (build_pavilion, "W_PavGlass")
    k["W_Halo"] = (build_halo, None)
    k["W_Podium"] = (build_podium, "W_PodiumGlass")
    k["W_Crown"] = (build_crown, None)
    k["W_Core"] = (build_core, "W_CoreGlass")
    k["W_CoreCap"] = (build_cap, None)
    k["W_Lantern"] = (build_lantern, "W_LanternGlass")
    k["W_Mast"] = (build_mast, None)
    k["W_Bridge"] = (build_bridge, "W_BridgeGlass")
    return k


META = {}


def record(obj):
    mn = [1e9] * 3
    mx = [-1e9] * 3
    for v in obj.data.vertices:
        for i in range(3):
            mn[i] = min(mn[i], v.co[i])
            mx[i] = max(mx[i], v.co[i])
    c = [(mn[i] + mx[i]) / 2 for i in range(3)]
    s = [mx[i] - mn[i] for i in range(3)]
    # Blender (x, y, z) -> Roblox (-x, z, y), piece-local
    META[obj.name] = dict(c=(-c[0] + 0.0, c[2], c[1]), s=(s[0], s[2], s[1]), tris=K.tris(obj))


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    for a in args:
        if a.startswith("only="):
            only = set(a[5:].split(","))
    K.reset()
    made = []
    for name, (fn, gname) in kit().items():
        if only and name not in only and gname not in only:
            continue
        shell, glass = fn()
        o = shell.to_object(name)
        K.finish(o)                      # ART.md: bevelled edges + baked AO
        record(o)
        K.export(os.path.join(OUT, name + ".fbx"), [o])
        made.append(o)
        if glass is not None:
            g = glass.to_object(gname)
            K.finish(g, width=0.08, ao=None)
            record(g)
            K.export(os.path.join(OUT, gname + ".fbx"), [g])
            made.append(g)
        print("%-16s %5d tris%s" % (name, META[name]["tris"], ("   %-16s %5d tris" % (gname, META[gname]["tris"])) if glass else ""))
    import metafile
    if not only:
        stale = os.path.join(metafile.META_DIR, "Wafers.lua")
        if os.path.exists(stale):
            os.remove(stale)       # a full run owns every row: drop names that no longer exist
    path = metafile.write(
        "Wafers", "blender/wafers.py: the Wafers kit. For THIS module c/s are in each mesh's PIECE-LOCAL frame "
        "(wafers.py header), Roblox axes; the stock 'plot-local' line below is metafile.py's. "
        "LANTERN_H = %.1f, MAST_H = %.1f" % (LANTERN_H, MAST_H), META)
    print("META ->", path)


# Guarded so terrafab.py can `import wafers` and reuse the geometry helpers
# without triggering a full Wafers export. Blender runs a -P script with
# __name__ == "__main__", so a direct run is unchanged.
if __name__ == "__main__":
    main()
