"""hq_concepts.py -- three concepts for ONE connected HQ that grows to level 100.

Build a Startup! today has a separate box per HQ level plus square wing rooms on
separate lots. The owner asked for "curvature, one large building, not a bunch
of square plots... every floor having a purpose... able to go to level 100".
These are CONCEPT RENDERS for that redesign (not game code), in the game's
low-poly style: curves are flat facets (the ring is a 64-gon, towers are 16-gons),
flat shading, colour in vertex colour, palette from art/ART.md.

  A  THE RING            grows AROUND (16 arc segments until the ring closes),
                         then UP (4 storeys), then a courtyard tower rises and
                         is tied to the ring by four skybridges
  B  THE CRESCENT TOWER  a C-shaped podium hugging a plaza; its storeys rise in
                         a wave into a twisting faceted tower at one end
  C  THE TERRACES        a curved amphitheatre of garden terraces that grows as
                         a hill (always a complete little hill, just bigger),
                         crowned by a faceted dome and spire

THE RULE FOR ALL THREE: one level = one module. A module is a segment-storey,
a tower floor, a bridge or a crown piece. plan_A/B/C() return the 100 modules
in build order. Stage L builds modules[:L], draws module L+1 as a bare concrete
skeleton with a crane beside it (the growth front), and stage 100 is complete.
Every module carries a floor function (engineering, studio, labs, servers...)
that shows as its glass tint, solid server panels or a planted sky garden.

Scale: 1 stud = 1 Blender unit, storey 13, person 5, plot 300 x 300.

Run (Blender 4.2 headless):
  blender -b --python hq_concepts.py -- concepts=ABC levels=5,30,100 samples=80 res=1280x960
  -> art/concepts/<X>_L<nn>.png + art/concepts/stats.json
Then (system python, PIL):  python make_sheets.py
"""
import bpy
import bmesh
import json
import math
import os
import random
import sys
import time
from mathutils import Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__))
BLEND = os.path.dirname(HERE)
ROOT = os.path.dirname(BLEND)
OUT = os.path.join(ROOT, "art", "concepts")
LPDIR = os.path.join(BLEND, "out", "IMPORT_LP_TREES")
os.makedirs(OUT, exist_ok=True)
sys.path.insert(0, BLEND)
import svkit as K  # noqa: E402


def _args():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = dict(concepts="ABC", levels="5,30,100", samples="80", res="1024x1280", tag="", zoom="1", aim="")
    for s in a:
        if "=" in s:
            k, v = s.split("=", 1)
            o[k] = v
    return o


OPT = _args()
SAMPLES = int(OPT["samples"])
RES = tuple(int(x) for x in OPT["res"].split("x"))
LEVELS = [int(x) for x in OPT["levels"].split(",")]
TAG = OPT["tag"]
ZOOM = float(OPT["zoom"])      # debug: tighter lens to inspect details
AIM = [float(v) for v in OPT["aim"].split(",")] if OPT["aim"] else None


# ------------------------------------------------------------------ palette (art/ART.md)
def rgb(r, g, b):
    return (r / 255.0, g / 255.0, b / 255.0)


PAPER = rgb(243, 239, 230)
FLOOR = rgb(222, 214, 200)
ROOF = rgb(216, 208, 194)
CONCRETE = rgb(207, 198, 182)
RAW = rgb(168, 162, 152)          # bare concrete: the growth front
OAK = rgb(192, 138, 85)
LAWN = rgb(122, 170, 80)
LAWN_DK = rgb(100, 146, 66)
GOLD = rgb(224, 182, 90)
BLUE = rgb(62, 110, 158)
INK = rgb(30, 37, 48)
INK_SOFT = rgb(52, 60, 74)
ACCENT = rgb(240, 110, 80)        # the player's company colour (example)
BRAND = rgb(255, 194, 61)
ASPHALT = rgb(88, 94, 108)
WILD = rgb(150, 178, 94)          # valley floor outside the plot
OLIVE = rgb(104, 124, 66)
HILL = rgb(222, 176, 78)          # the gold hills

H = 13.0      # storey
SLAB = 1.5    # slab thickness
OV = 1.2      # slab overhang past the glass line

# floor functions: what each module is FOR. glow = the lit-interior tint of its glass
FN = {
    "lobby":   dict(label="Lobby", glow=(255, 214, 160), kind="glass"),
    "cafe":    dict(label="Cafe", glow=(255, 166, 92), kind="glass"),
    "studio":  dict(label="Design studio", glow=(246, 150, 172), kind="glass"),
    "eng":     dict(label="Engineering", glow=(150, 196, 255), kind="glass"),
    "labs":    dict(label="AI labs", glow=(118, 226, 204), kind="glass"),
    "servers": dict(label="Server hall", glow=(80, 220, 255), kind="solid"),
    "garden":  dict(label="Sky garden", glow=(255, 232, 190), kind="garden"),
    "board":   dict(label="Boardroom", glow=(255, 198, 90), kind="glass"),
    "exec":    dict(label="Founder floor", glow=(255, 240, 216), kind="glass"),
}
GLOW = 0.55


def lin(c):
    return tuple(K.srgb_to_linear(x) for x in c)


def principled(m):
    return next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")


MATS = {}


def make_materials():
    MATS.clear()

    def vc(name, layer, rough, spec):
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        p = principled(m)
        v = m.node_tree.nodes.new("ShaderNodeVertexColor")
        v.layer_name = layer
        m.node_tree.links.new(v.outputs["Color"], p.inputs["Base Color"])
        p.inputs["Roughness"].default_value = rough
        p.inputs["Specular IOR Level"].default_value = spec
        return m

    MATS["vc"] = vc("vc", "Col", 0.62, 0.3)
    MATS["matte"] = vc("matte", "Col", 0.85, 0.15)
    MATS["tree"] = vc("tree", "Col", 0.8, 0.2)
    for k, f in FN.items():
        m = bpy.data.materials.new("glass_" + k)
        m.use_nodes = True
        p = principled(m)
        p.inputs["Base Color"].default_value = (*lin(rgb(70, 100, 118)), 1)
        p.inputs["Roughness"].default_value = 0.07
        p.inputs["Specular IOR Level"].default_value = 0.6
        p.inputs["Coat Weight"].default_value = 0.3
        p.inputs["Emission Color"].default_value = (*lin(rgb(*f["glow"])), 1)
        p.inputs["Emission Strength"].default_value = GLOW
        MATS["glass_" + k] = m
    m = bpy.data.materials.new("led")
    m.use_nodes = True
    p = principled(m)
    p.inputs["Base Color"].default_value = (*lin(rgb(80, 220, 255)), 1)
    p.inputs["Emission Color"].default_value = (*lin(rgb(80, 220, 255)), 1)
    p.inputs["Emission Strength"].default_value = 3.0
    MATS["led"] = m
    m = bpy.data.materials.new("solar")
    m.use_nodes = True
    p = principled(m)
    p.inputs["Base Color"].default_value = (*lin(rgb(44, 66, 110)), 1)
    p.inputs["Roughness"].default_value = 0.18
    p.inputs["Metallic"].default_value = 0.35
    MATS["solar"] = m
    m = bpy.data.materials.new("water")
    m.use_nodes = True
    p = principled(m)
    p.inputs["Base Color"].default_value = (*lin(rgb(72, 128, 158)), 1)
    p.inputs["Roughness"].default_value = 0.04
    MATS["water"] = m


# ------------------------------------------------------------------ geometry
def R(r, a):
    return r(a) if callable(r) else r


def rplus(r, d):
    if callable(r):
        return lambda a: r(a) + d
    return r + d


class Geo:
    """One flat-shaded mesh. Every face owns its vertices and one colour, so
    facets read as facets (the game's low-poly look). Faces carry a material slot."""

    def __init__(self):
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.color.new("Col")
        self.mats = []
        self.trees = []       # (template, x, y, z, height)
        self.tris = 0
        self.zmax = 0.0

    def mi(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def poly(self, pts, color, mat="vc", expect=None):
        vs = [self.bm.verts.new(p) for p in pts]
        f = self.bm.faces.new(vs)
        f.normal_update()
        if expect is not None and f.normal.dot(Vector(expect)) < 0:
            f.normal_flip()
        f.material_index = self.mi(mat)
        cx = sum(p[0] for p in pts) / len(pts)
        cy = sum(p[1] for p in pts) / len(pts)
        cz = sum(p[2] for p in pts) / len(pts)
        h = math.sin(cx * 12.9898 + cy * 78.233 + cz * 37.719) * 43758.5453
        k = 0.975 + 0.05 * (h - math.floor(h))          # a whisper of per-facet variation
        c = tuple(min(1.0, ch * k) for ch in color)
        for lp in f.loops:
            lp[self.col] = (c[0], c[1], c[2], 1.0)
        self.tris += len(pts) - 2
        self.zmax = max(self.zmax, max(p[2] for p in pts))
        return f

    # annular sector: an arc of a ring, n facets, z0..z1
    def sector(self, c, a0, a1, n, z0, z1, rin, rout, color, mat="vc", faces="tboicC", cols=None, mats=None):
        cols = cols or {}
        mats = mats or {}
        pi_, po_ = [], []
        for i in range(n + 1):
            a = a0 + (a1 - a0) * i / n
            ri, ro = R(rin, a), R(rout, a)
            pi_.append((c[0] + ri * math.cos(a), c[1] + ri * math.sin(a)))
            po_.append((c[0] + ro * math.cos(a), c[1] + ro * math.sin(a)))

        def C(k):
            return cols.get(k, color)

        def M(k):
            return mats.get(k, mat)

        for i in range(n):
            am = a0 + (a1 - a0) * (i + 0.5) / n
            rad = (math.cos(am), math.sin(am), 0.0)
            (x0, y0), (x1, y1) = pi_[i], pi_[i + 1]
            (X0, Y0), (X1, Y1) = po_[i], po_[i + 1]
            if "t" in faces:
                self.poly([(x0, y0, z1), (X0, Y0, z1), (X1, Y1, z1), (x1, y1, z1)], C("t"), M("t"), (0, 0, 1))
            if "b" in faces:
                self.poly([(x0, y0, z0), (x1, y1, z0), (X1, Y1, z0), (X0, Y0, z0)], C("b"), M("b"), (0, 0, -1))
            if "o" in faces:
                self.poly([(X0, Y0, z0), (X1, Y1, z0), (X1, Y1, z1), (X0, Y0, z1)], C("o"), M("o"), rad)
            if "i" in faces:
                self.poly([(x0, y0, z0), (x0, y0, z1), (x1, y1, z1), (x1, y1, z0)], C("i"), M("i"), (-rad[0], -rad[1], 0))
        if "c" in faces:
            (x0, y0), (X0, Y0) = pi_[0], po_[0]
            self.poly([(x0, y0, z0), (X0, Y0, z0), (X0, Y0, z1), (x0, y0, z1)], C("c"), M("c"),
                      (math.sin(a0), -math.cos(a0), 0))
        if "C" in faces:
            (x1, y1), (X1, Y1) = pi_[-1], po_[-1]
            self.poly([(x1, y1, z0), (x1, y1, z1), (X1, Y1, z1), (X1, Y1, z0)], C("C"), M("C"),
                      (-math.sin(a1), math.cos(a1), 0))

    def ngon(self, c, rx, ry, n, rot, z):
        cr, sr = math.cos(rot), math.sin(rot)
        out = []
        for i in range(n):
            t = 2 * math.pi * i / n
            x, y = rx * math.cos(t), ry * math.sin(t)
            out.append((c[0] + x * cr - y * sr, c[1] + x * sr + y * cr, z))
        return out

    # n-sided (elliptical) prism; the top may be rotated (twist) and scaled (taper)
    def prism(self, c, n, z0, z1, rx0, ry0, rot0, rx1=None, ry1=None, rot1=None, color=PAPER, mat="vc",
              faces="tbs", cols=None, mats=None):
        cols = cols or {}
        mats = mats or {}
        rx1 = rx0 if rx1 is None else rx1
        ry1 = ry0 if ry1 is None else ry1
        rot1 = rot0 if rot1 is None else rot1
        B = self.ngon(c, rx0, ry0, n, rot0, z0)
        T = self.ngon(c, rx1, ry1, n, rot1, z1)
        twisted = abs(rot1 - rot0) > 1e-6
        col_s, mat_s = cols.get("s", color), mats.get("s", mat)
        if "s" in faces:
            for i in range(n):
                j = (i + 1) % n
                out = ((B[i][0] + B[j][0] + T[i][0] + T[j][0]) / 4 - c[0], (B[i][1] + B[j][1] + T[i][1] + T[j][1]) / 4 - c[1], 0)
                if twisted:
                    self.poly([B[i], B[j], T[j]], col_s, mat_s, out)
                    self.poly([B[i], T[j], T[i]], col_s, mat_s, out)
                else:
                    self.poly([B[i], B[j], T[j], T[i]], col_s, mat_s, out)
        if "t" in faces:
            self.poly(T, cols.get("t", color), mats.get("t", mat), (0, 0, 1))
        if "b" in faces:
            self.poly(B, cols.get("b", color), mats.get("b", mat), (0, 0, -1))

    def box(self, ctr, size, color, mat="vc", yaw=0.0, cols=None, faces="tbxXyY"):
        cols = cols or {}
        cx, cy, cz = ctr
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        ca, sa = math.cos(yaw), math.sin(yaw)

        def P(x, y, z):
            return (cx + x * ca - y * sa, cy + x * sa + y * ca, cz + z)

        ex, ey = (ca, sa, 0), (-sa, ca, 0)
        C = lambda k: cols.get(k, color)  # noqa: E731
        if "t" in faces:
            self.poly([P(-hx, -hy, hz), P(hx, -hy, hz), P(hx, hy, hz), P(-hx, hy, hz)], C("t"), mat, (0, 0, 1))
        if "b" in faces:
            self.poly([P(-hx, -hy, -hz), P(-hx, hy, -hz), P(hx, hy, -hz), P(hx, -hy, -hz)], C("b"), mat, (0, 0, -1))
        if "X" in faces:
            self.poly([P(hx, -hy, -hz), P(hx, hy, -hz), P(hx, hy, hz), P(hx, -hy, hz)], C("X"), mat, ex)
        if "x" in faces:
            self.poly([P(-hx, -hy, -hz), P(-hx, -hy, hz), P(-hx, hy, hz), P(-hx, hy, -hz)], C("x"), mat, (-ex[0], -ex[1], 0))
        if "Y" in faces:
            self.poly([P(-hx, hy, -hz), P(-hx, hy, hz), P(hx, hy, hz), P(hx, hy, -hz)], C("Y"), mat, ey)
        if "y" in faces:
            self.poly([P(-hx, -hy, -hz), P(hx, -hy, -hz), P(hx, -hy, hz), P(-hx, -hy, hz)], C("y"), mat, (-ey[0], -ey[1], 0))

    def dome(self, c, z, r, segs, rings, color, mat="vc", rot=0.0):
        top = (c[0], c[1], z + r)

        def P(i, j):
            th = rot + 2 * math.pi * i / segs
            ph = (math.pi / 2) * j / rings
            return (c[0] + r * math.cos(ph) * math.cos(th), c[1] + r * math.cos(ph) * math.sin(th), z + r * math.sin(ph))

        for j in range(rings):
            for i in range(segs):
                if j == rings - 1:
                    pts = [P(i, j), P(i + 1, j), top]
                else:
                    pts = [P(i, j), P(i + 1, j), P(i + 1, j + 1), P(i, j + 1)]
                ctr = [sum(p[k] for p in pts) / len(pts) for k in range(3)]
                self.poly(pts, color, mat, (ctr[0] - c[0], ctr[1] - c[1], ctr[2] - z))

    def to_object(self, name):
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(MATS[m])
        for attr in ("active_color_name", "default_color_name"):
            try:
                setattr(me.color_attributes, attr, "Col")
            except Exception:
                pass
        o = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(o)
        return o


# ------------------------------------------------------------------ building parts
def arc_storey(g, m, skel=False):
    """One segment-storey of a curved wing: slab (oak soffit), glass band tinted by
    function (or solid server panels, or a set-back sky garden), oak fins."""
    c, a0, a1, n, z = m["c"], m["a0"], m["a1"], m["n"], m["z"]
    rin, rout = m["rin"], m["rout"]
    if skel:
        g.sector(c, a0, a1, n, z, z + SLAB, rplus(rin, -OV), rplus(rout, OV), RAW)
        for i in range(n + 1):
            a = a0 + (a1 - a0) * i / n
            for r in (R(rin, a) + 1.4, R(rout, a) - 1.4):
                g.box((c[0] + r * math.cos(a), c[1] + r * math.sin(a), z + SLAB + (H - SLAB) / 2), (1.2, 1.2, H - SLAB), RAW, yaw=a)
        return
    fn = m["fn"]
    kind = FN[fn]["kind"]
    g.sector(c, a0, a1, n, z, z + SLAB, rplus(rin, -OV), rplus(rout, OV), PAPER, cols={"t": FLOOR, "b": OAK})
    gin, gout = rplus(rin, 0.7), rplus(rout, -0.7)
    if kind == "garden":
        gout = rplus(rout, -6.0)
    z1, z2 = z + SLAB, z + H
    if kind == "solid":
        g.sector(c, a0, a1, n, z1, z2, gin, gout, INK_SOFT, faces="oicC")
        for fr in (0.34, 0.68):
            zz = z1 + (z2 - z1) * fr
            g.sector(c, a0, a1, n, zz, zz + 0.5, rplus(gin, -0.12), rplus(gout, 0.12), PAPER, mat="led", faces="oi")
    else:
        g.sector(c, a0, a1, n, z1, z2, gin, gout, PAPER, mat="glass_" + fn, faces="oicC")
    if kind == "garden":
        g.sector(c, a0, a1, n, z1, z1 + 1.1, rplus(rout, -5.4), rplus(rout, -0.3), CONCRETE, cols={"t": LAWN})
        for i in range(n):
            a = a0 + (a1 - a0) * (i + 0.5) / n
            r = R(rout, a) - 2.8
            g.trees.append(("LP_Oak_A" if i % 2 else "LP_Bush", c[0] + r * math.cos(a), c[1] + r * math.sin(a), z1 + 1.1, 6.5 if i % 2 else 3.0))
    fins = m.get("fins", "out")
    if kind != "solid":
        count = n * 2 if fn == "cafe" else n
        for i in range(count):
            a = a0 + (a1 - a0) * i / count
            if fins in ("out", "both") and kind != "garden":
                r = R(gout, a) + 0.75
                g.box((c[0] + r * math.cos(a), c[1] + r * math.sin(a), (z1 + z2) / 2), (1.5, 0.55, z2 - z1), OAK, yaw=a)
            if fins in ("in", "both"):
                r = R(gin, a) - 0.75
                g.box((c[0] + r * math.cos(a), c[1] + r * math.sin(a), (z1 + z2) / 2), (1.5, 0.55, z2 - z1), OAK, yaw=a)
    if m.get("canopy"):
        canopy_arc(g, m, m["canopy"])


def canopy_arc(g, m, side):
    """Entrance canopy with the company name band in the accent colour."""
    c = m["c"]
    amid = (m["a0"] + m["a1"]) / 2
    rr = R(m["rout"], amid) if side == "out" else R(m["rin"], amid)
    half = 9.0 / rr
    if side == "out":
        r0, r1 = rr + OV, rr + 10.0
        rb0, rb1, rc = r1 - 0.4, r1 + 0.4, r1 - 1.0
    else:
        r0, r1 = rr - 10.0, rr - OV
        rb0, rb1, rc = r0 - 0.4, r0 + 0.4, r0 + 1.0
    z = m["z"] + 10.0
    g.sector(c, amid - half, amid + half, 3, z, z + 0.8, r0, r1, PAPER, cols={"b": OAK})
    g.sector(c, amid - half, amid + half, 3, z + 0.8, z + 3.4, rb0, rb1, ACCENT)
    for a in (amid - half * 0.82, amid + half * 0.82):
        g.prism((c[0] + rc * math.cos(a), c[1] + rc * math.sin(a)), 8, m["z"], z, 0.4, 0.4, 0.0, color=PAPER, faces="s")


def arc_roof(g, m, style):
    c, a0, a1, n = m["c"], m["a0"], m["a1"], m["n"]
    z = m["z"] + H
    rin, rout = m["rin"], m["rout"]
    top = LAWN if style == "garden" else ROOF
    g.sector(c, a0, a1, n, z, z + SLAB, rplus(rin, -OV), rplus(rout, OV), PAPER, cols={"b": OAK, "t": top})
    if style == "solar":
        step = (a1 - a0) / n
        for i in range(n):
            b0 = a0 + i * step + step * 0.12
            g.sector(c, b0, b0 + step * 0.76, 1, z + SLAB, z + SLAB + 0.5, rplus(rin, 3.0), rplus(rout, -3.0), PAPER,
                     mats={"t": "solar"}, faces="toicC")
    elif style == "garden":
        for i in range(n):
            a = a0 + (a1 - a0) * (i + 0.5) / n
            r = (R(rin, a) + R(rout, a)) / 2 + (3.0 if i % 2 else -3.0)
            g.trees.append(("LP_Oak_B" if i % 2 else "LP_Bush", c[0] + r * math.cos(a), c[1] + r * math.sin(a), z + SLAB, 6.0 if i % 2 else 3.2))


def tower_storey(g, m, skel=False):
    """One tower floor. The glass band runs from this slab's angle to the next
    slab's (twist) and radius (taper), so a twisting tower shows faceted twist."""
    c, n, z = m["c"], m["n"], m["z"]
    rx0, ry0, rx1, ry1, r0, r1 = m["rx0"], m["ry0"], m["rx1"], m["ry1"], m["rot0"], m["rot1"]
    if skel:
        g.prism(c, n, z, z + SLAB, rx0 + OV, ry0 + OV, r0, color=RAW)
        for p in g.ngon(c, rx0 - 1.6, ry0 - 1.6, n, r0, 0)[::2]:
            g.box((p[0], p[1], z + SLAB + (H - SLAB) / 2), (1.3, 1.3, H - SLAB), RAW)
        return
    fn = m["fn"]
    kind = FN[fn]["kind"]
    g.prism(c, n, z, z + SLAB, rx0 + OV, ry0 + OV, r0, color=PAPER, cols={"t": FLOOR, "b": OAK})
    ins = 6.0 if kind == "garden" else 0.8
    z1, z2 = z + SLAB, z + H
    gx0, gy0, gx1, gy1 = rx0 - ins, ry0 - ins, rx1 - ins, ry1 - ins
    if kind == "solid":
        g.prism(c, n, z1, z2, gx0, gy0, r0, gx1, gy1, r1, color=INK_SOFT, faces="s")
        for fr in (0.34, 0.68):
            zz = z1 + (z2 - z1) * fr
            rot = r0 + (r1 - r0) * fr
            gx, gy = gx0 + (gx1 - gx0) * fr + 0.12, gy0 + (gy1 - gy0) * fr + 0.12
            g.prism(c, n, zz, zz + 0.5, gx, gy, rot, color=PAPER, mat="led", faces="s")
    else:
        g.prism(c, n, z1, z2, gx0, gy0, r0, gx1, gy1, r1, color=PAPER, mat="glass_" + fn, faces="s")
    if kind == "garden":
        g.prism(c, n, z1, z1 + 1.1, rx0 + 0.2, ry0 + 0.2, r0, color=CONCRETE, cols={"t": LAWN}, faces="ts")
        for i, p in enumerate(g.ngon(c, rx0 - 2.8, ry0 - 2.8, n, r0 + math.pi / n, 0)[::2]):
            g.trees.append(("LP_Oak_A" if i % 2 else "LP_Bush", p[0], p[1], z1 + 1.1, 6.5 if i % 2 else 3.2))
    if m.get("fins") and kind == "glass" and abs(r1 - r0) < 1e-6:
        for p in g.ngon(c, gx0 + 0.7, gy0 + 0.7, n, r0, 0):
            a = math.atan2(p[1] - c[1], p[0] - c[0])
            g.box((p[0], p[1], (z1 + z2) / 2), (1.4, 0.5, z2 - z1), OAK, yaw=a)
    if m.get("canopy") is not None:
        d = m["canopy"]
        rr = max(rx0, ry0) * 0.72 + 5.0
        cx, cy = c[0] + rr * math.cos(d), c[1] + rr * math.sin(d)
        g.box((cx, cy, z + 10.4), (12.0, 18.0, 0.8), PAPER, yaw=d, cols={"b": OAK})
        fx, fy = c[0] + (rr + 6.0) * math.cos(d), c[1] + (rr + 6.0) * math.sin(d)
        g.box((fx, fy, z + 12.0), (0.8, 18.0, 2.6), ACCENT, yaw=d)
        for s in (-1, 1):
            px = fx - 1.0 * math.cos(d) - s * 7.5 * math.sin(d)
            py = fy - 1.0 * math.sin(d) + s * 7.5 * math.cos(d)
            g.prism((px, py), 8, z, z + 10.0, 0.4, 0.4, 0.0, color=PAPER, faces="s")


def tower_roof(g, m):
    c, n = m["c"], m["n"]
    z = m["z"] + H
    g.prism(c, n, z, z + SLAB, m["rx1"] + OV, m["ry1"] + OV, m["rot1"], color=PAPER, cols={"t": ROOF, "b": OAK})
    g.prism(c, 8, z + SLAB, z + SLAB + 3.2, m["rx1"] * 0.35, m["ry1"] * 0.35, m["rot1"], color=CONCRETE)


def bridge(g, m):
    c, ang, r0, r1, z = m["c"], m["ang"], m["r0"], m["r1"], m["z"]
    L = r1 - r0
    rm = (r0 + r1) / 2
    x, y = c[0] + rm * math.cos(ang), c[1] + rm * math.sin(ang)
    g.box((x, y, z + SLAB / 2), (L, 11.0, SLAB), PAPER, yaw=ang, cols={"b": OAK})
    g.box((x, y, z + SLAB + 4.0), (L, 9.6, 8.0), PAPER, mat="glass_eng", yaw=ang, faces="yY")
    g.box((x, y, z + SLAB + 8.0 + 0.7), (L, 11.0, 1.4), PAPER, yaw=ang, cols={"b": OAK})
    for k in range(1, int(L // 7)):
        rr = r0 + k * 7.0
        for s in (-1, 1):
            px = c[0] + rr * math.cos(ang) - s * 5.1 * math.sin(ang)
            py = c[1] + rr * math.sin(ang) + s * 5.1 * math.cos(ang)
            g.box((px, py, z + SLAB + 4.0), (0.5, 0.6, 8.0), OAK, yaw=ang)


def deck(g, m):
    """Crown piece 1: a cantilevered sky deck, glazed, with a garden on top."""
    c, n, z, rx, ry, rot = m["c"], m["n"], m["z"], m["rx"], m["ry"], m["rot"]
    g.prism(c, n, z, z + SLAB, rx, ry, rot, color=PAPER, cols={"b": OAK, "t": FLOOR})
    g.prism(c, n, z + SLAB, z + SLAB + 7.5, rx - 1.5, ry - 1.5, rot, color=PAPER, mat="glass_exec", faces="s")
    zt = z + SLAB + 7.5
    g.prism(c, n, zt, zt + 1.4, rx + 1.0, ry + 1.0, rot, color=PAPER, cols={"t": LAWN, "b": OAK})
    for i, p in enumerate(g.ngon(c, rx - 4.0, ry - 4.0, n, rot + math.pi / n, 0)[::2]):
        g.trees.append(("LP_Oak_A" if i % 2 else "LP_Oak_B", p[0], p[1], zt + 1.4, 7.0))


def spire(g, m):
    c, z, h, r = m["c"], m["z"], m["h"], m["r"]
    g.prism(c, 8, z, z + h * 0.82, r, r, 0.0, r * 0.3, r * 0.3, 0.0, color=PAPER)
    g.prism(c, 8, z + h * 0.82, z + h, r * 0.3, r * 0.3, 0.0, 0.05, 0.05, 0.0, color=BRAND)
    if m.get("halo"):
        hr = m["halo"]
        zh = z + h * 0.3
        g.sector(c, 0.0, 2 * math.pi, 32, zh, zh + 1.4, hr - 1.2, hr, PAPER, faces="tboi", cols={"b": BRAND})
        rr = r * (1 - 0.7 * 0.3 / 0.82)
        for k in range(4):
            a = k * math.pi / 2 + math.pi / 4
            rm = (rr + hr - 1.2) / 2
            g.box((c[0] + rm * math.cos(a), c[1] + rm * math.sin(a), zh + 0.7), (hr - 1.2 - rr + 0.4, 0.7, 0.7), PAPER, yaw=a)


def blades(g, m):
    """Crown piece: slim fins rising from the deck edge (B's crown)."""
    c, n, z, rx, ry, rot, h = m["c"], m["n"], m["z"], m["rx"], m["ry"], m["rot"], m["h"]
    for p in g.ngon(c, rx, ry, n, rot, 0):
        a = math.atan2(p[1] - c[1], p[0] - c[0])
        g.box((p[0], p[1], z + h / 2), (3.0, 0.9, h), PAPER, yaw=a)


def halo(g, m):
    c, z, rx, ry, rot = m["c"], m["z"], m["rx"], m["ry"], m["rot"]

    def ell(scale):
        return lambda a: scale / math.sqrt((ry * math.cos(a - rot)) ** 2 + (rx * math.sin(a - rot)) ** 2) * rx * ry
    g.sector(c, 0.0, 2 * math.pi, 32, z, z + 2.2, ell(0.93), ell(1.07), BRAND, faces="tboi")


def terrace_roof(g, m, covered):
    """C: the roof of a terrace floor is a garden. If the next floor stands on it,
    only the strip in front of that floor is exposed."""
    c, a0, a1, n = m["c"], m["a0"], m["a1"], m["n"]
    z = m["z"] + H
    r0 = m["rin"] - OV
    r1 = (m["rin_next"] - OV) if covered else m["rout"] + OV
    if r1 - r0 < 0.5:
        return
    g.sector(c, a0, a1, n, z, z + SLAB, r0, r1, PAPER, cols={"t": LAWN, "b": OAK})
    g.sector(c, a0, a1, n, z + SLAB, z + SLAB + 1.0, r0, r0 + 1.6, CONCRETE, cols={"t": LAWN_DK})
    rows = [r0 + min(4.2, (r1 - r0) * 0.55)]
    if not covered and r1 - r0 > 30:
        rows.append((r0 + r1) / 2 + 6)
    for ri, rt in enumerate(rows):
        for i in range((m["o"] + m["k"]) % 2, n, 2):     # every other facet: ~200 garden trees at level 100
            a = a0 + (a1 - a0) * (i + 0.5) / n
            big = (i // 2 + ri + m["k"]) % 2 == 0
            g.trees.append(("LP_Oak_A" if big else "LP_Bush", c[0] + rt * math.cos(a), c[1] + rt * math.sin(a), z + SLAB,
                            6.5 if big else 3.0))


def crane(g, x, y, base, top, yaw):
    """The growth front: a tower crane, brand gold, jib over the next module."""
    mh = top + 20.0
    g.box((x, y, (base + mh) / 2), (2.4, 2.4, mh - base), BRAND)
    z = base + 5.0
    while z < mh - 2:
        g.box((x, y, z), (2.7, 2.7, 0.45), INK_SOFT)
        z += 7.0
    ca, sa = math.cos(yaw), math.sin(yaw)
    jl, cl = 42.0, 15.0
    g.box((x + ca * (jl / 2 - 1), y + sa * (jl / 2 - 1), mh + 1.0), (jl, 1.5, 1.5), BRAND, yaw=yaw)
    g.box((x - ca * (cl / 2), y - sa * (cl / 2), mh + 1.0), (cl, 1.7, 1.3), BRAND, yaw=yaw)
    g.box((x - ca * (cl - 2), y - sa * (cl - 2), mh - 0.6), (3.4, 2.8, 2.8), INK_SOFT, yaw=yaw)
    g.box((x, y, mh + 4.2), (1.1, 1.1, 6.4), BRAND)
    g.box((x + ca * 1.6, y + sa * 1.6, mh - 1.4), (2.4, 2.2, 2.0), PAPER, yaw=yaw)
    hx, hy = x + ca * (jl - 9), y + sa * (jl - 9)
    g.box((hx, hy, mh - 8), (0.22, 0.22, 16.0), INK)
    g.box((hx, hy, mh - 16.4), (1.1, 1.1, 1.1), INK)


# ------------------------------------------------------------------ the three plans (100 modules each)
def sym_order(n):
    order = [0]
    for i in range(1, n // 2):
        order += [i, n - i]
    order.append(n // 2)
    return order


A = dict(c=(0.0, 10.0), rin=80.0, rout=104.0, nseg=16)


def fn_tower_A(f):
    if f == 1:
        return "lobby"
    if f in (10, 20):
        return "garden"
    if f <= 3:
        return "servers"
    if f <= 9:
        return "eng"
    if f <= 19:
        return "labs"
    if f <= 26:
        return "studio"
    if f <= 29:
        return "board"
    return "exec"


def plan_A():
    c, rin, rout, ns = A["c"], A["rin"], A["rout"], A["nseg"]
    sa = 2 * math.pi / ns
    back = {6, 7, 8, 9, 10}
    mods = []
    for s in range(1, 5):
        for k in sym_order(ns):
            mid = -math.pi / 2 + k * sa
            if s == 1:
                fn = "lobby" if k == 0 else ("cafe" if k in back else "studio")
            elif s == 2:
                fn = "eng"
            elif s == 3:
                fn = "servers" if k in back else "labs"
            else:
                fn = "eng"
            mods.append(dict(t="arc", col=k, st=s, z=(s - 1) * H, c=c, a0=mid - sa / 2, a1=mid + sa / 2, n=4,
                             rin=rin, rout=rout, fn=fn, fins="both", canopy="out" if (s == 1 and k == 0) else None,
                             roof="solar", crane_side="out"))

    def trad(f):
        return 24.0 - 6.0 * (f - 1) / 29.0

    def tf(f):
        return dict(t="tower", col="T", st=f, z=(f - 1) * H, c=c, n=16, rx0=trad(f), ry0=trad(f), rx1=trad(f + 1),
                    ry1=trad(f + 1), rot0=0.0, rot1=0.0, fn=fn_tower_A(f), fins=True, crane_dir=math.pi)
    for f in range(1, 5):
        mods.append(tf(f))
    for deg in (45, 135, 225, 315):
        mods.append(dict(t="bridge", c=c, ang=math.radians(deg), r0=trad(4) - 2.0, r1=rin + 1.0, z=3 * H))
    for f in range(5, 31):
        mods.append(tf(f))
    top = 30 * H
    mods.append(dict(t="deck", c=c, z=top, rx=27.0, ry=27.0, rot=0.0, n=16))
    mods.append(dict(t="spire", c=c, z=top + SLAB + 7.5 + 1.4, h=74.0, r=3.4, halo=14.0))
    assert len(mods) == 100, len(mods)
    return mods


B = dict(c=(0.0, 28.0), rout=112.0, a_s=math.radians(-40.0), a_e=math.radians(200.0), nseg=18)
B_TW = math.radians(3.2)          # twist per floor: 93 degrees over the 29 floors above the lobby
B_TRX, B_TRY = 30.0, 15.0         # a flat ellipse, so the twist reads in silhouette
B_FLOORS = 30


def b_depth(a):
    t = (a - B["a_s"]) / (B["a_e"] - B["a_s"])
    return 15.0 + 17.0 * math.sin(math.pi * max(0.0, min(1.0, t)))


def b_rin(a):
    return B["rout"] - b_depth(a)


def b_tower_centre():
    ta = B["a_s"] - math.radians(15.0)
    return (B["c"][0] + 100.0 * math.cos(ta), B["c"][1] + 100.0 * math.sin(ta)), ta


def fn_tower_B(f):
    if f == 1:
        return "lobby"
    if f in (11, 20):
        return "garden"
    if f <= 4:
        return "servers"
    if f <= 10:
        return "eng"
    if f <= 19:
        return "labs"
    if f <= 26:
        return "studio"
    if f <= 29:
        return "board"
    return "exec"


def plan_B():
    c, rout, ns = B["c"], B["rout"], B["nseg"]
    sa = (B["a_e"] - B["a_s"]) / ns
    tc, ta = b_tower_centre()
    base = ta + math.pi / 2
    to_plaza = math.atan2(c[1] - tc[1], c[0] - tc[0])

    def ts(f):
        return 1.0 - 0.18 * (f - 1) / B_FLOORS

    def tf(f):
        return dict(t="tower", col="T", st=f, z=(f - 1) * H, c=tc, n=16,
                    rx0=B_TRX * ts(f), ry0=B_TRY * ts(f), rx1=B_TRX * ts(f + 1), ry1=B_TRY * ts(f + 1),
                    rot0=base + (f - 1) * B_TW, rot1=base + f * B_TW, fn=fn_tower_B(f), fins=False,
                    canopy=to_plaza if f == 1 else None, crane_dir=to_plaza + 0.9)
    # the crescent's storeys cover fewer segments the higher they go, counted
    # from the tower end: the podium rises in a wave into the tower
    cover = [18, 15, 12, 9, 7, 5]

    def cres(s):
        out = []
        for k in range(cover[s - 1]):
            a0 = B["a_s"] + k * sa
            if s == 1:
                fn = "cafe" if k >= 14 else "studio"
            else:
                fn = {2: "eng", 3: "labs", 4: "studio", 5: "labs", 6: "board"}[s]
            out.append(dict(t="arc", col=k, st=s, z=(s - 1) * H, c=c, a0=a0, a1=a0 + sa, n=3, rin=b_rin, rout=rout,
                            fn=fn, fins="both", roof="garden", crane_side="in"))
        return out
    mods = [tf(1)]
    mods += cres(1)
    mods += [tf(f) for f in range(2, 13)]
    mods += cres(2)
    mods += [tf(f) for f in range(13, 21)]
    mods += cres(3)
    mods += [tf(f) for f in range(21, 26)]
    mods += cres(4)
    mods += cres(5)
    mods += cres(6)
    mods += [tf(f) for f in range(26, B_FLOORS + 1)]
    top = B_FLOORS * H
    rot = base + B_FLOORS * B_TW
    rx, ry = B_TRX * ts(B_FLOORS + 1), B_TRY * ts(B_FLOORS + 1)
    dtop = top + SLAB + 7.5 + 1.4
    mods.append(dict(t="deck", c=tc, z=top, rx=rx + 4.0, ry=ry + 4.0, rot=rot, n=16))
    mods.append(dict(t="blades", c=tc, z=dtop, rx=rx + 2.5, ry=ry + 2.5, rot=rot, n=16, h=34.0))
    mods.append(dict(t="spire", c=tc, z=dtop, h=86.0, r=3.8))
    mods.append(dict(t="halo", c=tc, z=dtop + 34.0, rx=rx + 2.5, ry=ry + 2.5, rot=rot))
    assert len(mods) == 100, len(mods)
    return mods


CC = dict(c=(0.0, -48.0), rout=140.0, sa=math.radians(18.0), depth=34.0, step=6.0)


def c_rin(k):
    """Every terrace floor is the same 34-stud-deep curved bar, set 6 studs further
    back than the one below: the front steps up and back as a garden terrace, the
    back cantilevers 6 studs. Equal floors = every level buys the same space."""
    return 40.0 + CC["step"] * k


def c_rout(k):
    return c_rin(k) + CC["depth"]


def c_cover(k):
    return 5 - k // 3


def fn_C(k, o):
    if k == 0:
        return "lobby" if o == 0 else ("cafe" if abs(o) >= 4 else "studio")
    return {1: "studio", 2: "eng", 3: "eng", 4: "labs", 5: "labs", 6: "servers", 7: "studio", 8: "eng",
            9: "board", 10: "board", 11: "exec"}[k]


def plan_C():
    c, rout, sa = CC["c"], CC["rout"], CC["sa"]
    cells = [(k, o) for k in range(12) for o in range(-5, 6) if abs(o) <= c_cover(k)]
    cells.sort(key=lambda ko: (ko[0] + abs(ko[1]), ko[0], abs(ko[1]), ko[1] < 0))
    mods = []
    for (k, o) in cells:
        mid = math.pi / 2 + o * sa
        mods.append(dict(t="terrace", col=o, st=k, k=k, o=o, z=k * H, c=c, a0=mid - sa / 2, a1=mid + sa / 2, n=4,
                         rin=c_rin(k), rin_next=c_rin(k + 1), rout=c_rout(k), fn=fn_C(k, o), fins="both",
                         canopy="in" if (k == 0 and o == 0) else None))
    dc = (c[0], c[1] + (c_rin(11) + c_rout(11)) / 2)
    z0 = 12 * H + SLAB
    mods.append(dict(t="drum", c=dc, z=z0))
    mods.append(dict(t="dome", c=dc, z=z0 + 7.0))
    mods.append(dict(t="lantern", c=dc, z=z0 + 7.0 + 16.0))
    mods.append(dict(t="spire", c=dc, z=z0 + 7.0 + 16.0 + 6.0, h=78.0, r=1.9))
    assert len(mods) == 100, len(mods)
    return mods


PLANS = {"A": plan_A, "B": plan_B, "C": plan_C}
NAMES = {"A": "THE RING", "B": "THE CRESCENT TOWER", "C": "THE TERRACES"}
ROOF_STYLE = {"A": "solar", "B": "garden", "C": "garden"}


def build_modules(concept, plan, level, with_front=True):
    g = Geo()
    built = plan[:level]
    nxt = plan[level] if (with_front and level < len(plan)) else None
    tops = {}
    cells = set()
    for m in built:
        if m["t"] in ("arc", "tower"):
            tops[m["col"]] = max(tops.get(m["col"], 0), m["st"])
        if m["t"] == "terrace":
            cells.add((m["k"], m["o"]))
    nxt_cell = (nxt["col"], nxt["st"]) if nxt and nxt["t"] in ("arc", "tower") else None
    decked = any(m["t"] == "deck" for m in built)
    for m in built:
        T = m["t"]
        if T == "arc":
            arc_storey(g, m)
            if m["st"] == tops[m["col"]] and nxt_cell != (m["col"], m["st"] + 1):
                arc_roof(g, m, m["roof"])
        elif T == "tower":
            tower_storey(g, m)
            if m["st"] == tops[m["col"]] and nxt_cell != (m["col"], m["st"] + 1) and not decked:
                tower_roof(g, m)
        elif T == "terrace":
            arc_storey(g, m)
            above = (m["k"] + 1, m["o"])
            covered = above in cells or (nxt is not None and nxt["t"] == "terrace" and (nxt["k"], nxt["o"]) == above)
            terrace_roof(g, m, covered)
        elif T == "bridge":
            bridge(g, m)
        elif T == "deck":
            deck(g, m)
        elif T == "spire":
            spire(g, m)
        elif T == "blades":
            blades(g, m)
        elif T == "halo":
            halo(g, m)
        elif T == "drum":
            c, z = m["c"], m["z"]
            g.prism(c, 16, z, z + 1.5, 17.5, 17.5, 0.0, color=PAPER, cols={"b": OAK})
            g.prism(c, 16, z + 1.5, z + 6.0, 16.2, 16.2, 0.0, color=PAPER, mat="glass_exec", faces="s")
            g.prism(c, 16, z + 6.0, z + 7.0, 17.0, 17.0, 0.0, color=PAPER)
        elif T == "dome":
            g.dome(m["c"], m["z"], 16.0, 16, 4, PAPER, mat="glass_exec", rot=math.pi / 16)
            g.sector(m["c"], 0.0, 2 * math.pi, 16, m["z"], m["z"] + 0.8, 15.2, 16.6, PAPER, faces="toi")
        elif T == "lantern":
            c, z = m["c"], m["z"]
            g.prism(c, 8, z - 1.0, z + 5.0, 3.4, 3.4, 0.0, color=PAPER, mat="glass_exec", faces="s")
            g.prism(c, 8, z + 5.0, z + 6.0, 4.2, 4.2, 0.0, color=PAPER)
    # growth front: the next module as a bare concrete skeleton, and a crane
    front = None
    if nxt is not None:
        T = nxt["t"]
        if T in ("arc", "terrace"):
            arc_storey(g, nxt, skel=True)
            amid = (nxt["a0"] + nxt["a1"]) / 2
            c = nxt["c"]
            if T == "terrace":
                r = nxt["rin"] - 5.5
                base = nxt["z"] + SLAB if nxt["k"] > 0 else 0.0
                side_in = True
            else:
                side_in = nxt.get("crane_side") == "in"
                r = (R(nxt["rin"], amid) - 13.0) if side_in else (R(nxt["rout"], amid) + 13.0)
                base = 0.0
            x, y = c[0] + r * math.cos(amid), c[1] + r * math.sin(amid)
            yaw = amid if side_in else amid + math.pi
            front = (x, y, base, nxt["z"] + H, yaw)
        elif T == "tower":
            tower_storey(g, nxt, skel=True)
            d = nxt["crane_dir"]
            rr = max(nxt["rx0"], nxt["ry0"]) + 13.0
            x, y = nxt["c"][0] + rr * math.cos(d), nxt["c"][1] + rr * math.sin(d)
            front = (x, y, 0.0, nxt["z"] + H, d + math.pi)
    return g, front


# ------------------------------------------------------------------ the site
def smooth01(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def ground_h(x, y):
    d = math.hypot(x / 1.1, y - 80.0)
    rise = smooth01((d - 460.0) / 560.0)
    n = noise.fractal(Vector((x / 420.0, y / 420.0, 0.3)), 1.0, 2.0, 3)
    hills = (46.0 + 44.0 * n) * rise
    ridge = smooth01((y - 1350.0) / 700.0) * (90.0 + 40.0 * noise.noise(Vector((x / 300.0, 3.0, 1.0))))
    return max(0.0, hills + ridge)


def ground():
    """Faceted valley. One grid whose spacing grows toward the edges (50 studs near
    the plot, kilometres at the rim) so it reaches the horizon: rays that miss the
    ground would see Nishita's dark below-horizon sky as a murky band."""
    g = Geo()
    N = 104
    rng = random.Random(4)

    def ax(u, span, off):
        return off + 2600.0 * u + span * u ** 5

    V = {}
    for i in range(N + 1):
        for j in range(N + 1):
            u, v = -1 + 2 * i / N, -1 + 2 * j / N
            x, y = ax(u, 9000.0, 0.0), ax(v, 9000.0, 900.0)
            if 0 < i < N and 0 < j < N:
                sx = abs(ax(u + 1.0 / N, 9000.0, 0.0) - x)
                sy = abs(ax(v + 1.0 / N, 9000.0, 900.0) - y)
                x += rng.uniform(-0.28, 0.28) * sx
                y += rng.uniform(-0.28, 0.28) * sy
            V[(i, j)] = (x, y, ground_h(x, y) - 0.05)
    for i in range(N):
        for j in range(N):
            a, b, c, d = V[(i, j)], V[(i + 1, j)], V[(i + 1, j + 1)], V[(i, j + 1)]
            tris = [(a, b, c), (a, c, d)] if (i + j) % 2 == 0 else [(a, b, d), (b, c, d)]
            for t in tris:
                cx = sum(p[0] for p in t) / 3
                cy = sum(p[1] for p in t) / 3
                h = sum(p[2] for p in t) / 3
                gg = smooth01(h / 14.0)
                col = [WILD[k] * (1 - gg) + HILL[k] * gg for k in range(3)]
                wood = noise.noise(Vector((cx / 170.0, cy / 170.0, 7.0)))
                w = smooth01((wood + 0.08) / 0.3) * smooth01(h / 8.0) * 0.85
                col = [col[k] * (1 - w) + OLIVE[k] * w for k in range(3)]
                v = 1.0 + 0.07 * noise.noise(Vector((cx / 95.0, cy / 95.0, 3.3)))
                g.poly(list(t), tuple(min(1.0, ch * v) for ch in col), "matte", (0, 0, 1))
    return g


def site(concept, g):
    """Plot (300 x 300, mown lawn), road, paths and plaza for this concept."""
    # plot: a raised lawn slab with mowing stripes and a concrete kerb
    cells = 20
    s = 300.0 / cells
    for i in range(cells):
        for j in range(cells):
            x0, y0 = -150.0 + i * s, -150.0 + j * s
            k = 1.035 if (i % 2 == 0) else 0.965
            col = tuple(min(1, c * k) for c in LAWN)
            g.poly([(x0, y0, 0.5), (x0 + s, y0, 0.5), (x0 + s, y0 + s, 0.5), (x0, y0 + s, 0.5)], col, "matte", (0, 0, 1))
    for (cx, cy, sx, sy) in ((0, -150.8, 303, 1.6), (0, 150.8, 303, 1.6), (-150.8, 0, 1.6, 303), (150.8, 0, 1.6, 303)):
        g.box((cx, cy, 0.45), (sx, sy, 0.9), CONCRETE, mat="matte")
    # road + sidewalks + dashes
    g.box((0, -176, 0.15), (3200, 24, 0.3), ASPHALT, mat="matte")
    for sy in (-1, 1):
        g.box((0, -176 + sy * 14.6, 0.25), (3200, 5.2, 0.5), CONCRETE, mat="matte")
    for x in range(-1500, 1501, 18):
        g.box((x, -176, 0.32), (7, 0.5, 0.06), rgb(236, 226, 196), mat="matte")

    def path(x0, y0, x1, y1, w):
        L = math.hypot(x1 - x0, y1 - y0)
        g.box(((x0 + x1) / 2, (y0 + y1) / 2, 0.58), (L, w, 0.16), CONCRETE, mat="matte", yaw=math.atan2(y1 - y0, x1 - x0))

    def disc(c, r, col, z=0.6, n=40, mat="matte"):
        g.prism(c, n, 0.5, z, r, r, 0.0, color=col, mat=mat, faces="ts")

    def ring(c, r0, r1, col, z=0.6):
        g.sector(c, 0.0, 2 * math.pi, 64, 0.5, z, r0, r1, col, mat="matte", faces="toi")

    if concept == "A":
        c = A["c"]
        path(0, -158, 0, c[1] - 114.0, 10)
        ring(c, 116.0, 122.0, CONCRETE)
        ring(c, 46.0, 51.0, CONCRETE)
        disc(c, 36.0, CONCRETE)
        g.prism((c[0] + 40, c[1] + 44), 24, 0.5, 0.62, 13.0, 9.0, 0.5, color=CONCRETE, mat="matte", faces="ts")
        g.prism((c[0] + 40, c[1] + 44), 24, 0.5, 0.66, 12.0, 8.0, 0.5, color=PAPER, mat="water", faces="t")
    elif concept == "B":
        c = B["c"]
        path(0, -158, 0, c[1] - 70.0, 12)
        disc(c, 72.0, CONCRETE)
        disc(c, 26.0, LAWN, z=0.7)
        disc(c, 9.0, CONCRETE, z=1.1, n=24)
        disc(c, 8.0, PAPER, z=1.15, n=24, mat="water")
        tc, _ = b_tower_centre()
        path(tc[0], tc[1], c[0], c[1], 10)
    else:
        c = CC["c"]
        path(0, -158, 0, c[1] - 34.0, 12)
        disc(c, 36.0, CONCRETE)
        disc(c, 9.0, CONCRETE, z=1.1, n=24)
        disc(c, 8.0, PAPER, z=1.15, n=24, mat="water")


def blocked(concept, x, y):
    if abs(y + 176) < 21:
        return True
    if abs(x) < 9 and -160 < y < 40:
        return True
    if concept == "A":
        d = math.hypot(x - A["c"][0], y - A["c"][1])
        return 68 <= d <= 126 or d < 40 or 44 <= d <= 53
    if concept == "B":
        c = B["c"]
        d = math.hypot(x - c[0], y - c[1])
        if d < 76:
            return True
        a = math.atan2(y - c[1], x - c[0])
        if a < B["a_s"] - 0.25:
            a += 2 * math.pi
        if B["a_s"] - 0.2 <= a <= B["a_e"] + 0.2 and b_rin(min(max(a, B["a_s"]), B["a_e"])) - 12 <= d <= B["rout"] + 12:
            return True
        tc, _ = b_tower_centre()
        return math.hypot(x - tc[0], y - tc[1]) < 42
    c = CC["c"]
    d = math.hypot(x - c[0], y - c[1])
    if d < 40:
        return True
    a = math.degrees(math.atan2(y - c[1], x - c[0]))
    if a < -90:
        a += 360
    return -16 <= a <= 196 and d <= CC["rout"] + 12


# ------------------------------------------------------------------ trees, people, cars
_TT = {}


def tree_tpl(name):
    if name in _TT:
        return _TT[name]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.join(LPDIR, name + ".fbx"), axis_forward="-Z", axis_up="Y")
    new = [o for o in bpy.data.objects if o not in before]
    o = [x for x in new if x.type == "MESH"][0]
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for x in new:
        if x is not o:
            bpy.data.objects.remove(x)
    o.data.materials.clear()
    o.data.materials.append(MATS["tree"])
    xs = [v.co.x for v in o.data.vertices]
    ys = [v.co.y for v in o.data.vertices]
    zs = [v.co.z for v in o.data.vertices]
    o["h"] = max(zs) - min(zs)
    o["z0"] = min(zs)
    o["cx"] = (max(xs) + min(xs)) / 2
    o["cy"] = (max(ys) + min(ys)) / 2
    o["tris"] = sum(len(p.vertices) - 2 for p in o.data.polygons)
    for coll in list(o.users_collection):
        coll.objects.unlink(o)
    _TT[name] = o
    return o


TREE_TRIS = [0]


def tree(name, x, y, z, h, yaw=None, rng=None):
    t = tree_tpl(name)
    o = t.copy()
    bpy.context.scene.collection.objects.link(o)
    s = h / t["h"]
    yaw = (rng or random).uniform(0, 2 * math.pi) if yaw is None else yaw
    o.scale = (s, s, s)
    o.rotation_euler = (0, 0, yaw)
    cx, cy = t["cx"] * s, t["cy"] * s
    rx, ry = cx * math.cos(yaw) - cy * math.sin(yaw), cx * math.sin(yaw) + cy * math.cos(yaw)
    o.location = (x - rx, y - ry, z - t["z0"] * s)
    TREE_TRIS[0] += t["tris"]
    return o


def scatter_trees(concept):
    rng = random.Random(21)
    # palms along both sides of the road
    for x in range(-560, 561, 28):
        if abs(x) < 18:
            continue
        for yy in (-160.5, -191.5):
            tree("LP_Palm_A" if (x // 28) % 2 else "LP_Palm_B", x + rng.uniform(-2, 2), yy, 0.5, rng.uniform(20, 25), rng=rng)
    # campus trees inside the plot, clear of the building and paths
    placed, tries = 0, 0
    while placed < 42 and tries < 3000:
        tries += 1
        x, y = rng.uniform(-142, 142), rng.uniform(-142, 142)
        if blocked(concept, x, y):
            continue
        if rng.random() < 0.18:
            tree("LP_Eucalypt", x, y, 0.5, rng.uniform(20, 28), rng=rng)
        else:
            tree("LP_Oak_A" if rng.random() < 0.5 else "LP_Oak_B", x, y, 0.5, rng.uniform(11, 15), rng=rng)
        placed += 1
    if concept == "A":   # the courtyard orchard
        c = A["c"]
        for i in range(22):
            a = 2 * math.pi * i / 22 + 0.1
            r = 60.0 if i % 2 else 66.0
            tree("LP_Orchard", c[0] + r * math.cos(a), c[1] + r * math.sin(a), 0.5, rng.uniform(6, 7.5), rng=rng)
    # the valley around it
    placed, tries = 0, 0
    while placed < 320 and tries < 9000:
        tries += 1
        x, y = rng.uniform(-1100, 1100), rng.uniform(-150, 1500)
        if abs(x) < 170 and y < 170:
            continue
        if abs(y + 176) < 26:
            continue
        h = ground_h(x, y)
        wood = noise.noise(Vector((x / 170.0, y / 170.0, 7.0)))
        if h > 6 and wood < -0.08 and rng.random() < 0.7:
            continue
        if y > 1150 and h > 60:
            tree("LP_RedwoodGrove", x, y, h - 0.5, rng.uniform(26, 32), rng=rng)
        elif h > 8 and rng.random() < 0.4:
            tree("LP_Grove", x, y, h - 0.5, rng.uniform(12, 16), rng=rng)
        else:
            tree("LP_Oak_A" if rng.random() < 0.5 else "LP_Oak_B", x, y, h - 0.3, rng.uniform(11, 15), rng=rng)
        placed += 1


def person(g, x, y, yaw, shirt, pants, skin):
    ca, sa = math.cos(yaw), math.sin(yaw)

    def P(lx, ly):
        return (x + lx * ca - ly * sa, y + lx * sa + ly * ca)
    for lx in (-0.5, 0.5):
        px, py = P(lx, 0)
        g.box((px, py, 0.5 + 1.05), (0.9, 0.95, 2.1), pants, yaw=yaw)
    g.box((x, y, 0.5 + 3.1), (2.0, 1.05, 2.0), shirt, yaw=yaw)
    for lx in (-1.45, 1.45):
        px, py = P(lx, 0)
        g.box((px, py, 0.5 + 3.05), (0.85, 0.9, 2.0), shirt, yaw=yaw)
    g.box((x, y, 0.5 + 4.75), (1.25, 1.2, 1.25), skin, yaw=yaw)
    g.box((x, y, 0.5 + 5.35), (1.35, 1.3, 0.45), rgb(58, 40, 30), yaw=yaw)


def people_and_cars(concept):
    g = Geo()
    rng = random.Random(5)
    shirts = [ACCENT, BLUE, rgb(250, 208, 90), rgb(120, 190, 120), PAPER]
    skins = [rgb(236, 196, 160), rgb(200, 150, 110), rgb(150, 100, 70), rgb(110, 72, 50)]
    if concept == "A":
        spots = [(-3, -124), (3, -118), (-2, -136), (14, -120), (-15, -128)]
    elif concept == "B":
        spots = [(-4, -30), (8, -42), (-14, -52), (20, -10), (4, -120)]
    else:
        spots = [(-4, -92), (5, -100), (-16, -74), (18, -70), (2, -130)]
    for i, (x, y) in enumerate(spots):
        person(g, x, y, rng.uniform(0, 2 * math.pi), shirts[i % len(shirts)], INK if i % 2 else rgb(70, 90, 130), skins[i % 4])
    for (x, lane, col) in ((-140, -6, PAPER), (70, 6, ACCENT), (260, -6, BLUE), (-330, 6, PAPER)):
        yy = -176 + lane
        g.box((x, yy, 1.6), (9.4, 4.2, 1.8), col)
        g.box((x - 0.4, yy, 3.0), (5.4, 3.7, 1.4), INK_SOFT)
        for dx in (-3, 3):
            for dy in (-2.0, 2.0):
                g.box((x + dx, yy + dy, 0.9), (1.7, 0.7, 1.7), INK)
    return g


# ------------------------------------------------------------------ light, camera, render
def setup_gpu(scene):
    scene.render.engine = "CYCLES"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for dt in ("OPTIX", "CUDA"):
            try:
                prefs.compute_device_type = dt
                prefs.get_devices()
                if any(dv.type == dt for dv in prefs.devices):
                    break
            except Exception:
                pass
        for dv in prefs.devices:
            dv.use = (dv.type == prefs.compute_device_type)
        scene.cycles.device = "GPU"
    except Exception as e:
        print("GPU setup failed, CPU:", e)


SUN_ELEV = math.radians(22.0)
SUN_ROT = math.radians(262.0)


def light(scene):
    world = bpy.data.worlds.new("Sky")
    scene.world = world
    world.use_nodes = True
    wn = world.node_tree
    sky = wn.nodes.new("ShaderNodeTexSky")
    sky.sky_type = "NISHITA"
    sky.sun_elevation = SUN_ELEV
    sky.sun_rotation = SUN_ROT
    sky.altitude = 40
    sky.air_density = 1.0
    sky.dust_density = 1.0
    sky.ozone_density = 1.0
    sky.sun_disc = True
    sky.sun_intensity = 0.4
    bg = next(n for n in wn.nodes if n.type == "BACKGROUND")
    bg.inputs["Strength"].default_value = 0.3
    wn.links.new(sky.outputs["Color"], bg.inputs["Color"])
    sd = bpy.data.lights.new("Sun", "SUN")
    sd.energy = 5.0
    sd.angle = math.radians(1.4)
    sd.color = (1.0, 0.79, 0.58)
    sun = bpy.data.objects.new("Sun", sd)
    scene.collection.objects.link(sun)
    d = Vector((math.cos(SUN_ELEV) * math.sin(SUN_ROT), -math.cos(SUN_ELEV) * math.cos(SUN_ROT), math.sin(SUN_ELEV)))
    sun.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    return world


CAM_AZ = math.radians(236.0)
CAM_EL = math.radians(27.0)
LENS = 38.0


def fit_camera(points, aspect):
    dv = Vector((math.cos(CAM_EL) * math.cos(CAM_AZ), math.cos(CAM_EL) * math.sin(CAM_AZ), math.sin(CAM_EL)))
    f = -dv
    r = f.cross(Vector((0, 0, 1))).normalized()
    u = r.cross(f).normalized()
    tx = 18.0 / LENS * 0.93
    ty = tx / aspect
    pts = [Vector(p) for p in points]
    t = sum(pts, Vector()) / len(pts)
    d = 500.0
    for _ in range(6):
        d = 1.0
        for p in pts:
            q = p - t
            x, y, z = q.dot(r), q.dot(u), q.dot(f)
            d = max(d, abs(x) / tx - z, abs(y) / ty - z)
        sx = [(p - t).dot(r) / (d + (p - t).dot(f)) for p in pts]
        sy = [(p - t).dot(u) / (d + (p - t).dot(f)) for p in pts]
        cxs, cys = (max(sx) + min(sx)) / 2, (max(sy) + min(sy)) / 2
        t = t + r * (cxs * d) + u * (cys * d)
    return t + dv * d, t, d


def composite(scene, world, dist):
    scene.render.film_transparent = True
    vl = scene.view_layers[0]
    vl.use_pass_environment = True
    vl.use_pass_mist = True
    world.mist_settings.start = dist * 0.9
    world.mist_settings.depth = 2600
    world.mist_settings.falloff = "QUADRATIC"
    scene.use_nodes = True
    ct = scene.node_tree
    rl = next(n for n in ct.nodes if n.type == "R_LAYERS")
    comp = next(n for n in ct.nodes if n.type == "COMPOSITE")
    fac = ct.nodes.new("CompositorNodeMath")
    fac.operation = "MULTIPLY"
    fac.inputs[1].default_value = 0.5
    mix = ct.nodes.new("CompositorNodeMixRGB")
    mix.blend_type = "MIX"
    mix.inputs[2].default_value = (0.64, 0.68, 0.80, 1.0)
    ct.links.new(rl.outputs["Mist"], fac.inputs[0])
    ct.links.new(fac.outputs[0], mix.inputs[0])
    ct.links.new(rl.outputs["Image"], mix.inputs[1])
    keep = ct.nodes.new("CompositorNodeSetAlpha")
    ct.links.new(mix.outputs[0], keep.inputs["Image"])
    ct.links.new(rl.outputs["Alpha"], keep.inputs["Alpha"])
    over = ct.nodes.new("CompositorNodeAlphaOver")
    ct.links.new(rl.outputs["Env"], over.inputs[1])
    ct.links.new(keep.outputs[0], over.inputs[2])
    glare = ct.nodes.new("CompositorNodeGlare")
    glare.glare_type = "FOG_GLOW"
    glare.threshold = 1.2
    glare.size = 7
    glare.mix = -0.8
    ct.links.new(over.outputs[0], glare.inputs[0])
    ct.links.new(glare.outputs[0], comp.inputs["Image"])


_BOUNDS = {}


def full_bounds(concept):
    """The camera is fitted to the finished (level 100) building plus the plot and
    the road, so all three stages of a concept share one camera."""
    if concept in _BOUNDS:
        return _BOUNDS[concept]
    g, _ = build_modules(concept, PLANS[concept](), 100)
    xs = [v.co.x for v in g.bm.verts]
    ys = [v.co.y for v in g.bm.verts]
    zs = [v.co.z for v in g.bm.verts]
    g.bm.free()
    pts = []
    for x in (min(xs), max(xs)):
        for y in (min(ys), max(ys)):
            for z in (0.0, max(zs)):
                pts.append((x, y, z))
    for x in (-150.0, 150.0):
        for y in (-150.0, 150.0):
            pts.append((x, y, 0.0))
    # the detail camera: same direction, fitted to the finished building's lower
    # part only (the podium/ring/terraces), so early stages are legible
    zc = DETAIL_Z[concept]
    dpts = [(x, y, z) for x in (min(xs), max(xs)) for y in (min(ys), max(ys)) for z in (0.0, zc)]
    _BOUNDS[concept] = pts
    _BOUNDS[concept + "_d"] = dpts
    return pts


DETAIL_Z = {"A": 70.0, "B": 95.0, "C": 175.0}
DETAIL_RES = (1200, 800)


def render_stage(concept, level, stats):
    t0 = time.time()
    pts = full_bounds(concept)
    K.reset()
    _TT.clear()
    TREE_TRIS[0] = 0
    scene = bpy.context.scene
    setup_gpu(scene)
    make_materials()
    plan = PLANS[concept]()
    g, front = build_modules(concept, plan, level)
    tris, zmax, garden_trees = g.tris, g.zmax, list(g.trees)
    g.to_object("HQ")
    for (name, x, y, z, h) in garden_trees:
        tree(name, x, y, z, h, rng=random.Random(int(x * 7 + y * 13)))
    garden_tree_tris = TREE_TRIS[0]
    if front:
        cg = Geo()
        x, y, base, top, yaw = front
        crane(cg, x, y, base, top, yaw)
        cg.to_object("Crane")
    sg = ground()
    site(concept, sg)
    sg.to_object("Site")
    people_and_cars(concept).to_object("People")
    scatter_trees(concept)
    world = light(scene)
    aspect = RES[0] / RES[1]
    cam_pos, target, dist = fit_camera(pts, aspect)
    cd = bpy.data.cameras.new("Cam")
    cd.lens = LENS * ZOOM
    if AIM:
        target = Vector(AIM)
    cd.sensor_fit = "HORIZONTAL"
    cd.sensor_width = 36.0
    cd.clip_end = 12000
    cam = bpy.data.objects.new("Cam", cd)
    scene.collection.objects.link(cam)
    cam.location = cam_pos
    cam.rotation_euler = (target - cam_pos).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 4
    scene.cycles.diffuse_bounces = 2
    scene.cycles.glossy_bounces = 2
    scene.cycles.transmission_bounces = 2
    scene.render.resolution_x, scene.render.resolution_y = RES
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "AgX"
    for look in ("AgX - Punchy", "AgX - Medium High Contrast"):
        try:
            scene.view_settings.look = look
            break
        except Exception:
            pass
    composite(scene, world, dist)
    name = "%s_L%02d%s.png" % (concept, level, TAG)
    scene.render.filepath = os.path.join(OUT, name)
    tb = time.time()
    bpy.ops.render.render(write_still=True)
    if OPT.get("detail", "1") == "1" and not AIM and ZOOM == 1.0:
        dpos, dtarget, ddist = fit_camera(_BOUNDS[concept + "_d"], DETAIL_RES[0] / DETAIL_RES[1])
        cam.location = dpos
        cam.rotation_euler = (dtarget - dpos).to_track_quat("-Z", "Y").to_euler()
        world.mist_settings.start = ddist * 0.9
        scene.render.resolution_x, scene.render.resolution_y = DETAIL_RES
        scene.render.filepath = os.path.join(OUT, "%s_L%02d_detail%s.png" % (concept, level, TAG))
        bpy.ops.render.render(write_still=True)
    fns = {}
    for m in plan[:level]:
        if "fn" in m:
            fns[m["fn"]] = fns.get(m["fn"], 0) + 1
    st = dict(concept=concept, name=NAMES[concept], level=level, file=name, building_tris=tris,
              garden_trees=len(garden_trees), garden_tree_tris=garden_tree_tris, height=round(zmax, 1),
              modules=level, front=bool(front), functions=fns,
              build_s=round(tb - t0, 1), render_s=round(time.time() - tb, 1))
    stats.append(st)
    print("STAGE", json.dumps(st))


def main():
    stats_path = os.path.join(OUT, "stats%s.json" % TAG)
    stats = []
    if os.path.exists(stats_path):
        try:
            stats = [s for s in json.load(open(stats_path)) if not (s["concept"] in OPT["concepts"] and s["level"] in LEVELS)]
        except Exception:
            stats = []
    for concept in OPT["concepts"]:
        for level in LEVELS:
            render_stage(concept, level, stats)
    stats.sort(key=lambda s: (s["concept"], s["level"]))
    json.dump(stats, open(stats_path, "w"), indent=1)
    # the plan itself, for the report and the sheets: what each level adds
    meta = {}
    for c in "ABC":
        meta[c] = [dict(level=i + 1, t=m["t"], fn=m.get("fn", ""), st=m.get("st", 0)) for i, m in enumerate(PLANS[c]())]
    json.dump(dict(functions={k: dict(label=v["label"], glow=v["glow"], kind=v["kind"]) for k, v in FN.items()},
                   plans=meta), open(os.path.join(OUT, "plans.json"), "w"), indent=0)


main()
