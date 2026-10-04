"""hq_formats.py -- round 2: five NEW formats for the one-building HQ (level 1-100).

Round 1 (hq_concepts.py: A ring, B crescent tower, C terraces) got the verdict
"investigate a better format; the terraces look is not the best". These are five
different FORMATS, not polish of the old three. Each is drawn from a real
building type, in the same low-poly look (flat facets, vertex colour, the
art/ART.md palette, the same light, valley, trees and glass-tint legend):

  W  THE WAFERS      Samsung America HQ (San Jose): four oval office rings, each
                     "wafer" turned and shifted on the one below, open-air garden
                     decks between them, one lift core in the courtyard
  T  THE TWIN LINK   Tencent Seafront / Marina Bay Sands: two curved towers on a
                     curved podium, tied by themed sky links, a sky park on top
  S  THE SPIRAL      BIG's 8 House ramp: a glass podium ring, then ONE ribbon of
                     offices winding up round a lift core, 2 storeys of rise per
                     turn, so every turn's roof is a garden ramp to the top
                     (a first pass as a stepped cone read as a wedding cake; cut)
  O  THE ORBIT       Jewel Changi / Amazon Spheres / Galaxy SOHO: a glass dome
                     garden, a ring promenade, and one round tower per department
  C  THE CANOPY      Google Bay View / Nvidia Voyager (both in the valley): one
                     shallow dragonscale roof of hex bays over one glass building,
                     facade tinted bay by bay; the middle rises into a mountain
                     (a first pass with tall tents over round pavilions read as silos; cut)

Rule for all five (same as round 1): one level = one module. plan_X() returns the
100 modules in build order; stage L draws modules[:L], draws module L+1 as a bare
concrete skeleton (where the type has one) with a crane, and 100 is complete.
Scale: 1 stud = 1 Blender unit, storey 13, person 5, plot 300 x 300.

Run (Blender 4.2 headless):
  blender -b --python hq_formats.py -- fmts=WTSOC lv=5,30,100 spp=64
  -> art/concepts/formats/<X>_L<nn>_<view>.png + stats.json + plans.json
Then (system python, PIL):  python make_format_sheets.py
"""
import bpy
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
OUT = os.path.join(ROOT, "art", "concepts", "formats")
os.makedirs(OUT, exist_ok=True)

# ------------------------------------------------------------ round 1's helpers
# hq_concepts.py ends with a bare main() call; load everything above it.
LIB = os.path.join(HERE, "hq_concepts.py")
_src = open(LIB, encoding="utf-8").read().rstrip()
assert _src.endswith("main()"), "hq_concepts.py changed shape"
_src = _src[: -len("main()")]
L = {"__file__": LIB, "__name__": "hq_concepts_lib"}
exec(compile(_src, LIB, "exec"), L)

K = L["K"]
Geo, R, rplus, rgb = L["Geo"], L["R"], L["rplus"], L["rgb"]
H, SLAB, OV = L["H"], L["SLAB"], L["OV"]
PAPER, FLOOR, ROOF, CONCRETE, RAW = L["PAPER"], L["FLOOR"], L["ROOF"], L["CONCRETE"], L["RAW"]
OAK, LAWN, LAWN_DK, BLUE, INK, INK_SOFT = L["OAK"], L["LAWN"], L["LAWN_DK"], L["BLUE"], L["INK"], L["INK_SOFT"]
ACCENT, BRAND, ASPHALT = L["ACCENT"], L["BRAND"], L["ASPHALT"]
FN = L["FN"]
MATS = L["MATS"]
TRACK = rgb(198, 98, 74)
SCALE = rgb(132, 152, 180)


def _args():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = dict(fmts="WTSOC", lv="5,30,100", spp="64")
    for s in a:
        if "=" in s:
            k, v = s.split("=", 1)
            o[k] = v
    return o


OPT = _args()
SPP = int(OPT["spp"])
LEVELS = [int(x) for x in OPT["lv"].split(",")]
AERIAL_RES = (1200, 900)
GROUND_RES = (1280, 720)


def make_mats():
    L["make_materials"]()

    def principled(m):
        return next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")

    # dragonscale roof: vertex colour, silvery
    m = bpy.data.materials.new("scale")
    m.use_nodes = True
    p = principled(m)
    v = m.node_tree.nodes.new("ShaderNodeVertexColor")
    v.layer_name = "Col"
    m.node_tree.links.new(v.outputs["Color"], p.inputs["Base Color"])
    p.inputs["Metallic"].default_value = 0.35
    p.inputs["Roughness"].default_value = 0.34
    MATS["scale"] = m
    # the dome: real see-through glass so the garden inside shows
    m = bpy.data.materials.new("domeglass")
    m.use_nodes = True
    p = principled(m)
    p.inputs["Base Color"].default_value = (*L["lin"](rgb(196, 222, 226)), 1)
    p.inputs["Roughness"].default_value = 0.04
    p.inputs["Transmission Weight"].default_value = 0.9
    p.inputs["IOR"].default_value = 1.05
    MATS["domeglass"] = m
    m = bpy.data.materials.new("falls")
    m.use_nodes = True
    p = principled(m)
    p.inputs["Base Color"].default_value = (*L["lin"](rgb(170, 214, 236)), 1)
    p.inputs["Roughness"].default_value = 0.15
    p.inputs["Transmission Weight"].default_value = 0.6
    p.inputs["Emission Color"].default_value = (*L["lin"](rgb(170, 214, 236)), 1)
    p.inputs["Emission Strength"].default_value = 0.35
    MATS["falls"] = m


# ------------------------------------------------------------ shared helpers
def ell(rx, ry, rot):
    """Radius of an ellipse (semi-axes rx, ry, turned by rot) at polar angle a."""
    def f(a):
        return rx * ry / math.sqrt((ry * math.cos(a - rot)) ** 2 + (rx * math.sin(a - rot)) ** 2)
    return f


def polar(c, r, a):
    return (c[0] + r * math.cos(a), c[1] + r * math.sin(a))


def column(g, x, y, z0, z1, r=0.9, color=PAPER):
    if z1 - z0 > 0.2:
        g.prism((x, y), 8, z0, z1, r, r, 0.0, color=color, faces="s")


def draw_arcs(g, built, nxt, roof_style):
    """Every 'arc' module (a segment-storey) + the roof of each column's top storey.
    roof_style(m) -> 'solar' | 'garden' | 'plain' | callable(g, m) | None."""
    tops = {}
    for m in built:
        if m["t"] == "arc":
            tops[m["col"]] = max(tops.get(m["col"], -99), m["st"])
    nxt_cell = (nxt["col"], nxt["st"] + 0) if nxt is not None and nxt["t"] == "arc" else None
    for m in built:
        if m["t"] != "arc":
            continue
        L["arc_storey"](g, m)
        if m["st"] == tops[m["col"]] and nxt_cell != (m["col"], m["st"] + m.get("step", 1)):
            s = roof_style(m)
            if callable(s):
                s(g, m)
            elif s:
                L["arc_roof"](g, m, s)


def draw_towers(g, built, nxt, roof_fn):
    tops = {}
    for m in built:
        if m["t"] == "tower":
            tops[m["col"]] = max(tops.get(m["col"], -99), m["st"])
    nxt_cell = (nxt["col"], nxt["st"]) if nxt is not None and nxt["t"] == "tower" else None
    for m in built:
        if m["t"] != "tower":
            continue
        L["tower_storey"](g, m)
        if m["st"] == tops[m["col"]] and nxt_cell != (m["col"], m["st"] + 1):
            roof_fn(g, m)


def pod_roof(g, m, style):
    c, n = m["c"], m["n"]
    z = m["z"] + H
    rx, ry = m["rx1"], m["ry1"]
    if style == "garden":
        g.prism(c, n, z, z + SLAB, rx + OV, ry + OV, 0.0, color=PAPER, cols={"t": LAWN, "b": OAK})
        g.prism(c, n, z + SLAB, z + SLAB + 1.0, rx + OV, ry + OV, 0.0, color=CONCRETE, faces="s")
        for i, p in enumerate(g.ngon(c, rx * 0.62, ry * 0.62, max(5, n // 2), 0.3, 0)):
            g.trees.append(("LP_Oak_A" if i % 2 else "LP_Oak_B", p[0], p[1], z + SLAB, 6.5))
    else:
        L["tower_roof"](g, m)


def roof_strip_garden(g, c, a0, a1, n, z, r0, r1):
    """A lawn roof strip with a row of small trees (used on garden decks)."""
    g.sector(c, a0, a1, n, z, z + SLAB, r0, r1, PAPER, cols={"t": LAWN, "b": OAK})


def crane_at(x, y, base, top, yaw):
    return (x, y, base, top, yaw)


# ================================================================ W  THE WAFERS
WF = dict(c=(0.0, 34.0), depth=20.0, nseg=8, nfac=5)
# each wafer: its own centre offset, size and turn, so the stack cantilevers like Samsung's
WAF = [dict(off=(0.0, 0.0), rx=66.0, ry=46.0, rot=0.0),
       dict(off=(9.0, -3.0), rx=70.0, ry=44.0, rot=math.radians(32.0)),
       dict(off=(-8.0, 3.0), rx=64.0, ry=47.0, rot=math.radians(-14.0)),
       dict(off=(5.0, 7.0), rx=60.0, ry=42.0, rot=math.radians(52.0))]
W_STOREYS = [(0, [0, 1]), (1, [3, 4, 5]), (2, [7, 8, 9]), (3, [11, 12, 13])]
W_GARDEN = {0: 2, 1: 6, 2: 10}          # the open garden storey above wafer w
W_BOTTOM = {w: s[0] for w, s in W_STOREYS}


def w_c(w):
    return (WF["c"][0] + WAF[w]["off"][0], WF["c"][1] + WAF[w]["off"][1])


def w_rot(w):
    return WAF[w]["rot"]


def w_rout(w):
    return ell(WAF[w]["rx"], WAF[w]["ry"], w_rot(w))


def w_rin(w):
    return ell(WAF[w]["rx"] - WF["depth"], WAF[w]["ry"] - WF["depth"], w_rot(w))


def ray_to_ellipse(p, ang, c, rx, ry, rot):
    """Distance from point p (inside) along angle ang to the ellipse (c, rx, ry, rot)."""
    ca, sa = math.cos(-rot), math.sin(-rot)
    px, py = p[0] - c[0], p[1] - c[1]
    px, py = px * ca - py * sa, px * sa + py * ca
    dx, dy = math.cos(ang - rot), math.sin(ang - rot)
    A = dx * dx / rx ** 2 + dy * dy / ry ** 2
    B = 2 * (px * dx / rx ** 2 + py * dy / ry ** 2)
    C = px * px / rx ** 2 + py * py / ry ** 2 - 1
    return (-B + math.sqrt(max(0.0, B * B - 4 * A * C))) / (2 * A)


def fn_W(w, sl, k):
    if w == 0:
        if sl == 0:
            return "lobby" if k == 0 else ("cafe" if k in (3, 4, 5) else "studio")
        return "studio"
    if w == 1:
        return "eng"
    if w == 2:
        return ["labs", "servers", "labs"][sl]
    return ["studio", "board", "exec"][sl]


def plan_W():
    ns = WF["nseg"]
    sa = 2 * math.pi / ns
    mods = []
    for w, storeys in W_STOREYS:
        rot = w_rot(w)
        for sl, st in enumerate(storeys):
            for k in L["sym_order"](ns):
                mid = -math.pi / 2 + rot + k * sa
                mods.append(dict(t="arc", col=("w", w, k), st=st, z=st * H, c=w_c(w), a0=mid - sa / 2, a1=mid + sa / 2,
                                 n=WF["nfac"], rin=w_rin(w), rout=w_rout(w), fn=fn_W(w, sl, k), fins="both",
                                 canopy="out" if (w == 0 and st == 0 and k == 0) else None, crane_side="out", wafer=w))
        if w in W_GARDEN:
            mods.append(dict(t="wgarden", w=w, st=W_GARDEN[w], fn="garden"))
    mods.append(dict(t="wroofgarden", fn="garden"))
    w3 = WAF[3]
    pout = ell(w3["rx"] - 8.0, w3["ry"] - 8.0, w3["rot"])
    pin = ell(w3["rx"] - 19.0, w3["ry"] - 19.0, w3["rot"])
    for k in range(5):
        a0 = -math.pi / 2 + w3["rot"] + k * 2 * math.pi / 5 - math.pi / 5
        mods.append(dict(t="arc", col=("pav", k), st=14, z=14 * H + 0.06, c=w_c(3), a0=a0, a1=a0 + 2 * math.pi / 5, n=6,
                         rin=pin, rout=pout, fn="exec", fins="out", crane_side="out", wafer=3))
    mods.append(dict(t="whalo"))
    mods.append(dict(t="wlantern"))
    mods.append(dict(t="wmast"))
    assert len(mods) == 100, len(mods)
    return mods


def draw_W(g, built, nxt):
    c = WF["c"]
    kinds = {m["t"] for m in built}
    gardened = {m["w"] for m in built if m["t"] == "wgarden"}
    roofgarden = "wroofgarden" in kinds

    def outer_garden(g2, m):
        # top wafer's roof garden: trees only on the outer band (the pavilion sits inside)
        cc = m["c"]
        g2.sector(cc, m["a0"], m["a1"], m["n"], m["z"] + H, m["z"] + H + SLAB, rplus(m["rin"], -OV), rplus(m["rout"], OV),
                  PAPER, cols={"t": LAWN, "b": OAK})
        for i in range(m["n"]):
            a = m["a0"] + (m["a1"] - m["a0"]) * (i + 0.5) / m["n"]
            r = R(m["rout"], a) - 3.2
            g2.trees.append(("LP_Oak_A" if i % 2 else "LP_Bush", cc[0] + r * math.cos(a), cc[1] + r * math.sin(a),
                             m["z"] + H + SLAB, 6.0 if i % 2 else 3.0))

    def style(m):
        if m["col"][0] == "pav":
            return "solar"
        w = m["wafer"]
        if w == 3:
            return outer_garden if roofgarden else "solar"
        return "garden" if w in gardened else "solar"

    draw_arcs(g, built, nxt, style)
    # garden decks: running track + columns up to the next wafer
    for m in built:
        if m["t"] != "wgarden":
            continue
        w, st = m["w"], m["st"]
        cw = w_c(w)
        z0 = st * H + SLAB
        g.sector(cw, 0.0, 2 * math.pi, 40, z0, z0 + 0.12, rplus(w_rin(w), 2.4), rplus(w_rin(w), 4.8), TRACK, faces="t")
        up = w + 1
        cu = w_c(up)
        rmid = ell(WAF[up]["rx"] - WF["depth"] / 2, WAF[up]["ry"] - WF["depth"] / 2, w_rot(up))
        for i in range(22):
            a = 2 * math.pi * i / 22
            x, y = polar(cu, rmid(a), a)
            al = math.atan2(y - cw[1], x - cw[0])
            rl = math.hypot(x - cw[0], y - cw[1])
            if R(w_rin(w), al) + 2.5 < rl < R(w_rout(w), al) - 2.0:
                column(g, x, y, z0, (st + 1) * H, r=1.0)
    # the lift core in the courtyard + a glass bridge to every wafer it serves
    top = max([m["st"] + 1 for m in built if m["t"] == "arc" and m["col"][0] == "w"] + [1])
    zt = top * H + SLAB
    g.prism(c, 12, 0.0, zt, 6.0, 6.0, 0.0, color=PAPER, mat="glass_lobby", faces="s")
    for k in range(4):
        x, y = polar(c, 6.1, k * math.pi / 2 + math.pi / 4)
        g.box((x, y, zt / 2), (1.8, 1.8, zt), CONCRETE)
    g.prism(c, 12, zt, zt + 1.2, 7.4, 7.4, 0.0, color=PAPER, cols={"b": OAK})
    for w, storeys in W_STOREYS:
        segs = [m for m in built if m["t"] == "arc" and m["col"][0] == "w" and m["wafer"] == w and m["st"] == storeys[0]]
        if len(segs) >= 6:
            for s in (1, -1):
                ang = w_rot(w) + s * math.pi / 2
                d = ray_to_ellipse(c, ang, w_c(w), WAF[w]["rx"] - WF["depth"], WAF[w]["ry"] - WF["depth"], w_rot(w))
                L["bridge"](g, dict(c=c, ang=ang, r0=5.5, r1=d + 1.6, z=W_BOTTOM[w] * H))
    ztop = 14 * H + SLAB
    if "whalo" in kinds:
        L["halo"](g, dict(c=w_c(3), z=ztop, rx=WAF[3]["rx"] - 2.0, ry=WAF[3]["ry"] - 2.0, rot=w_rot(3)))
    zl = zt + 1.2
    if "wlantern" in kinds:
        g.prism(c, 12, zl, zl + 9.0, 5.2, 5.2, 0.0, color=PAPER, mat="glass_exec", faces="s")
        g.prism(c, 12, zl + 9.0, zl + 10.2, 7.0, 7.0, 0.0, color=PAPER, cols={"b": OAK})
        zl += 10.2
    if "wmast" in kinds:
        L["spire"](g, dict(c=c, z=zl, h=62.0, r=2.4))


def front_W(nxt):
    return None


# ================================================================ T  THE TWIN LINK
TW = dict(pc=(0.0, -40.0), towers=[dict(c=(-44.0, 36.0), floors=23), dict(c=(44.0, 30.0), floors=19)],
          rx=28.0, ry=19.0, core=5.0)


def tw_geo(ti):
    c = TW["towers"][ti]["c"]
    rad = math.atan2(c[1] - TW["pc"][1], c[0] - TW["pc"][0])
    return c, rad, rad - math.pi / 2


def fn_T(ti, f):
    if f == 1:
        return "lobby"
    if ti == 0:
        if f == 10 or f == 17:
            return "garden"
        if f <= 9:
            return "eng"
        if f <= 16:
            return "eng" if f <= 13 else "labs"
        if f <= 21:
            return "board"
        return "exec"
    if f in (10, 17):
        return "garden"
    if f <= 3:
        return "servers"
    if f <= 16:
        return "studio"
    return "labs"


def tw_half(ti, f, h):
    c, rad, rot = tw_geo(ti)
    a0 = rad + math.pi / 2 if h == 0 else rad - math.pi / 2
    return dict(t="arc", col=("T", ti, h), st=f, z=(f - 1) * H, c=c, a0=a0, a1=a0 + math.pi, n=8, rin=TW["core"],
                rout=ell(TW["rx"], TW["ry"], rot), fn=fn_T(ti, f), fins="out",
                canopy=None, crane_side="out", tower=ti)


def tw_link(name, st, fn, a0, a1, r0, r1, canopy=None):
    return dict(t="arc", col=("link", name), st=st, z=(st - 1) * H, c=TW["pc"], a0=math.radians(a0), a1=math.radians(a1),
                n=max(3, int((a1 - a0) / 7)), rin=r0, rout=r1, fn=fn, fins="both", canopy=canopy, crane_side="in")


def plan_T():
    mods = [tw_half(0, 1, 0), tw_half(1, 1, 0), tw_half(0, 1, 1), tw_half(1, 1, 1)]
    segs = [("mid", 68, 112), ("l", 112, 148), ("r", 32, 68)]
    for st, fns in ((1, {"mid": "lobby", "l": "cafe", "r": "cafe"}), (2, {"mid": "studio", "l": "studio", "r": "studio"})):
        for name, a0, a1 in segs:
            mods.append(tw_link("pod_" + name, st, fns[name], a0, a1, 56.0, 76.0,
                                canopy="in" if (st == 1 and name == "mid") else None))
    queues = [[(0, f, h) for f in range(2, 24) for h in (0, 1)], [(1, f, h) for f in range(2, 20) for h in (0, 1)]]
    done = [2, 2]
    flags = set()

    def floors(ti):
        return done[ti] // 2
    while queues[0] or queues[1]:
        frac = [(floors(i) / TW["towers"][i]["floors"]) if queues[i] else 9 for i in (0, 1)]
        ti = 0 if frac[0] <= frac[1] else 1
        t, f, h = queues[ti].pop(0)
        mods.append(tw_half(t, f, h))
        done[ti] += 1
        if "health" not in flags and floors(0) >= 9 and floors(1) >= 9:
            flags.add("health")
            mods += [tw_link("health", 8, "cafe", 74, 106, 62.0, 90.0), tw_link("health", 9, "cafe", 74, 106, 62.0, 90.0)]
        if "know" not in flags and floors(0) >= 16 and floors(1) >= 16:
            flags.add("know")
            mods += [tw_link("know", 15, "labs", 74, 106, 62.0, 90.0), tw_link("know", 16, "labs", 74, 106, 62.0, 90.0)]
        if "sky" not in flags and floors(1) >= 19 and floors(0) >= 20:
            flags.add("sky")
            mods += [dict(t="sp_deck", half=0), dict(t="sp_deck", half=1), dict(t="sp_pool"), dict(t="sp_garden"),
                     dict(t="arc", col=("skypav",), st=20, z=19 * H + SLAB + 0.1, c=TW["pc"], a0=math.radians(80),
                          a1=math.radians(100), n=4, rin=76.0, rout=90.0, fn="exec", fins="both", crane_side="in")]
    mods.append(dict(t="tspire"))
    assert len(mods) == 100, len(mods)
    return mods


def draw_T(g, built, nxt):
    kinds = {m["t"] for m in built}
    pc = TW["pc"]
    sky = "sp_deck" in kinds

    def style(m):
        if m["col"][0] == "T":
            if m["tower"] == 1 and sky:
                return "plain"
            return "solar"
        return "garden"
    draw_arcs(g, built, nxt, style)
    zd = 19 * H + 0.08
    a0, a1 = math.radians(38), math.radians(142)
    for m in built:
        if m["t"] == "sp_deck":
            b0 = a0 if m["half"] == 0 else (a0 + a1) / 2
            b1 = (a0 + a1) / 2 if m["half"] == 0 else a1
            g.sector(pc, b0, b1, 8, zd, zd + SLAB, 68.0, 100.0, PAPER, cols={"t": FLOOR, "b": OAK})
            g.sector(pc, b0, b1, 8, zd + SLAB, zd + SLAB + 1.3, 99.2, 100.0, PAPER, mat="glass_exec", faces="oi")
        elif m["t"] == "sp_pool":
            g.sector(pc, a0 + 0.05, a1 - 0.05, 16, zd + SLAB, zd + SLAB + 0.6, 91.0, 98.5, CONCRETE, faces="toicC",
                     mats={"t": "water"})
        elif m["t"] == "sp_garden":
            g.sector(pc, a0 + 0.05, a1 - 0.05, 16, zd + SLAB, zd + SLAB + 0.8, 69.5, 75.0, CONCRETE, cols={"t": LAWN})
            for i in range(14):
                a = a0 + 0.12 + (a1 - a0 - 0.24) * i / 13
                x, y = polar(pc, 72.3, a)
                g.trees.append(("LP_Oak_A" if i % 2 else "LP_Oak_B", x, y, zd + SLAB + 0.8, 7.0))
        elif m["t"] == "tspire":
            c, _, _ = tw_geo(0)
            L["spire"](g, dict(c=c, z=23 * H + SLAB, h=78.0, r=3.2, halo=13.0))


def front_T(nxt):
    return None


# ================================================================ S  THE SPIRAL (helix on a podium)
# A one-storey glass podium ring, then ONE ribbon of offices that winds up round a
# lift core: 2 storeys of rise per turn, so every turn has an open-air garden
# ramp on its roof under the next turn. Walk (or drive) from the podium to the top.
SP = dict(c=(0.0, 30.0), r0=72.0, D=20.0, k=3.8, nseg=82, L=24.0, start=math.pi / 2, npod=12)
SP_FNS = ["studio", "eng", "eng", "labs", "labs", "board", "exec"]


def sp_rout(a):
    return SP["r0"] - SP["k"] * (a - SP["start"]) / (2 * math.pi)


def sp_rin(a):
    return sp_rout(a) - SP["D"]


def sp_z(th):
    return H + SLAB + 0.05 + 2 * H * th / (2 * math.pi)


def sp_thetas():
    """Segment boundaries of equal ARC LENGTH (SP L) along the ribbon's mid line."""
    a0 = SP["r0"] - SP["D"] / 2
    b = SP["k"] / (4 * math.pi)
    out = []
    for i in range(SP["nseg"] + 1):
        target = SP["L"] * i
        out.append((a0 - math.sqrt(max(0.0, a0 * a0 - 4 * b * target))) / (2 * b))
    return out


SP_THETA_END = sp_thetas()[-1]


def fn_S(th):
    rev = int(th // (2 * math.pi))
    if rev == 3 and (th % (2 * math.pi)) < math.pi:
        return "servers"
    return SP_FNS[min(rev, len(SP_FNS) - 1)]


def plan_S():
    c, npod = SP["c"], SP["npod"]
    sa = 2 * math.pi / npod
    mods = []
    for k in L["sym_order"](npod):
        mid = -math.pi / 2 + k * sa
        fn = "lobby" if k == 0 else ("cafe" if k in (5, 6, 7) else "studio")
        mods.append(dict(t="arc", col=("pod", k), st=0, z=0.0, c=c, a0=mid - sa / 2, a1=mid + sa / 2, n=4,
                         rin=SP["r0"] - SP["D"], rout=SP["r0"], fn=fn, fins="both",
                         canopy="out" if k == 0 else None, crane_side="out", part="pod"))
    ths = sp_thetas()
    for i in range(SP["nseg"]):
        t0, t1 = ths[i], ths[i + 1]
        mods.append(dict(t="arc", col=("S", i), st=i, z=sp_z(t0), c=c, a0=SP["start"] + t0, a1=SP["start"] + t1,
                         n=max(2, int(math.ceil((t1 - t0) / 0.2))), rin=sp_rin, rout=sp_rout, fn=fn_S(t0),
                         fins="both", crane_side="out", part="helix", th0=t0, th1=t1))
    for t in ("s_deck", "s_dome", "s_lantern", "s_halo", "s_spire", "s_band"):
        mods.append(dict(t=t))
    assert len(mods) == 100, len(mods)
    return mods


def draw_S(g, built, nxt):
    c = SP["c"]
    kinds = {m["t"] for m in built}

    def pod_roof(g2, m):
        z = H
        g2.sector(c, m["a0"], m["a1"], m["n"], z, z + SLAB, rplus(m["rin"], -OV), rplus(m["rout"], OV), PAPER,
                  cols={"t": LAWN, "b": OAK})
        for i in range(m["n"]):
            a = m["a0"] + (m["a1"] - m["a0"]) * (i + 0.5) / m["n"]
            th = (a - SP["start"]) % (2 * math.pi)
            if th > 2.4 and i % 2 == 0:            # only where the first turn is high enough above
                x, y = polar(c, (m["rin"] + m["rout"]) / 2, a)
                g2.trees.append(("LP_Oak_A", x, y, z + SLAB, 6.5))

    def helix_roof(g2, m):
        a0, a1, n, z = m["a0"], m["a1"], m["n"], m["z"] + H
        g2.sector(c, a0, a1, n, z, z + SLAB, rplus(sp_rin, -OV), rplus(sp_rout, OV), PAPER, cols={"t": LAWN, "b": OAK})
        g2.sector(c, a0, a1, n, z + SLAB, z + SLAB + 0.1, rplus(sp_rout, -12.5), rplus(sp_rout, -7.5), CONCRETE, faces="t")
        am = (a0 + a1) / 2
        if m["st"] % 2 == 0:
            x, y = polar(c, sp_rout(am) - 2.8, am)
            g2.trees.append(("LP_Oak_A" if m["st"] % 4 == 0 else "LP_Oak_B", x, y, z + SLAB, 6.8))
        else:
            x, y = polar(c, sp_rin(am) + 3.0, am)
            g2.trees.append(("LP_Bush", x, y, z + SLAB, 3.2))

    draw_arcs(g, built, nxt, lambda m: pod_roof if m["part"] == "pod" else helix_roof)
    # columns under every turn, down to the roof below it (the podium for the first turn)
    for m in built:
        if m.get("part") != "helix":
            continue
        thm = (m["th0"] + m["th1"]) / 2
        am = SP["start"] + thm
        bottom = (H + SLAB) if thm < 2 * math.pi else (sp_z(thm - 2 * math.pi) + H + SLAB)
        top = m["z"]
        for rr in (sp_rin(am) + 5.0, sp_rout(am) - 3.0):
            x, y = polar(c, rr, am)
            column(g, x, y, bottom, top, r=0.9)
    # the lift core the ribbon winds round, with one bridge per turn
    helix = [m for m in built if m.get("part") == "helix"]
    ztop = (max(m["z"] for m in helix) + H + SLAB) if helix else H + SLAB
    zend = sp_z(SP_THETA_END) + H + SLAB
    if "s_deck" in kinds:
        ztop = zend
    g.prism(c, 14, 0.0, ztop, 8.0, 8.0, 0.0, color=PAPER, mat="glass_labs", faces="s")
    for q in range(7):
        x, y = polar(c, 8.1, q * 2 * math.pi / 7)
        g.box((x, y, ztop / 2), (1.2, 1.2, ztop), PAPER)
    turns = int(max([m["th1"] for m in helix] + [0.0]) // (2 * math.pi))
    for j in range(1, turns + 1):
        th = 2 * math.pi * j
        L["bridge"](g, dict(c=c, ang=SP["start"] + th, r0=7.5, r1=sp_rin(SP["start"] + th) + 1.5, z=sp_z(th)))
    if "s_deck" in kinds:
        g.prism(c, 16, zend, zend + SLAB, 17.0, 17.0, 0.0, color=PAPER, cols={"t": LAWN, "b": OAK})
        for i, p in enumerate(g.ngon(c, 14.0, 14.0, 8, 0.2, 0)):
            g.trees.append(("LP_Bush", p[0], p[1], zend + SLAB, 3.0))
        ang = SP["start"] + SP_THETA_END - 0.15
        L["bridge"](g, dict(c=c, ang=ang, r0=16.0, r1=sp_rin(ang) + 1.5, z=zend - H - SLAB))
    zd = zend + SLAB
    if "s_dome" in kinds:
        g.prism(c, 14, zd, zd + 6.0, 10.0, 10.0, 0.0, color=PAPER, mat="glass_exec", faces="s")
        g.dome(c, zd + 6.0, 10.5, 14, 4, PAPER, mat="glass_exec", rot=math.pi / 14)
    if "s_lantern" in kinds:
        g.prism(c, 8, zd + 15.5, zd + 21.0, 2.6, 2.6, 0.0, color=PAPER, mat="glass_exec", faces="s")
        g.prism(c, 8, zd + 21.0, zd + 22.0, 3.4, 3.4, 0.0, color=PAPER)
    if "s_halo" in kinds:
        g.sector(c, 0.0, 2 * math.pi, 28, zd + 7.0, zd + 9.0, 12.5, 15.0, BRAND, faces="tboi")
    if "s_spire" in kinds:
        L["spire"](g, dict(c=c, z=zd + 22.0, h=52.0, r=2.2))
    if "s_band" in kinds:
        g.sector(c, 0.0, 2 * math.pi, 48, H + SLAB, H + SLAB + 1.8, SP["r0"] + OV - 1.0, SP["r0"] + OV + 0.2, BRAND,
                 faces="toi")


def front_S(nxt):
    return None


# ================================================================ O  THE ORBIT
OB = dict(c=(0.0, 42.0), ring=78.0, ring_d=16.0, dome=40.0, dome_h=30.0, oculus=6.0)
# (angle deg, radius, floors, job, roof style)
PODS = [(-90, 17.0, 4, "lobby", "garden"), (-30, 15.0, 16, "eng", "solar"), (30, 16.0, 22, "labs", "plain"),
        (90, 20.0, 7, "servers", "solar"), (150, 15.0, 12, "studio", "garden"), (210, 15.0, 11, "board", "garden")]


def pod_c(i):
    return polar(OB["c"], OB["ring"], math.radians(PODS[i][0]))


def fn_O(i, f):
    ang, r, F, job, _ = PODS[i]
    if job == "lobby":
        return ["lobby", "cafe", "cafe", "board"][f - 1]
    if job == "eng":
        return "garden" if f == 9 else "eng"
    if job == "labs":
        return "garden" if f in (12, 18) else "labs"
    if job == "studio":
        return "garden" if f == 7 else "studio"
    if job == "board":
        return "exec" if f >= 10 else "board"
    return job


def pod_mod(i, f):
    ang, r, F, job, style = PODS[i]
    return dict(t="tower", col=("P", i), st=f, z=(f - 1) * H, c=pod_c(i), n=14, rx0=r, ry0=r, rx1=r, ry1=r,
                rot0=0.0, rot1=0.0, fn=fn_O(i, f), fins=True, canopy=(-math.pi / 2) if (i == 0 and f == 1) else None,
                crane_dir=math.radians(ang), pod=i, final=F, style=style)


def ring_arcs():
    out = []
    for i in range(6):
        j = (i + 1) % 6
        a_i, a_j = math.radians(PODS[i][0]), math.radians(PODS[j][0])
        if a_j < a_i:
            a_j += 2 * math.pi
        gi = math.asin(PODS[i][1] * 0.75 / OB["ring"])
        gj = math.asin(PODS[j][1] * 0.75 / OB["ring"])
        out.append((a_i + gi, a_j - gj))
    return out


def ring_mod(k, st):
    a0, a1 = ring_arcs()[k]
    return dict(t="arc", col=("ring", k), st=st, z=(st - 1) * H, c=OB["c"], a0=a0, a1=a1, n=8,
                rin=OB["ring"] - OB["ring_d"] / 2, rout=OB["ring"] + OB["ring_d"] / 2, fn="cafe" if st == 1 else "studio",
                fins="both", crane_side="out")


def plan_O():
    mods = [pod_mod(0, 1), pod_mod(0, 2)]
    front_order = [5, 0, 4, 1, 3, 2]            # arcs nearest the lobby first
    mods += [ring_mod(k, 1) for k in front_order]
    mods += [pod_mod(i, 1) for i in (1, 5, 2, 4, 3)]
    mods += [pod_mod(0, 3), pod_mod(0, 4)]
    mods.append(dict(t="o_drum"))
    mods += [ring_mod(k, 2) for k in front_order]
    mods += [pod_mod(i, 2) for i in (1, 5, 2, 4, 3)]
    mods += [dict(t="o_wedge", k=k) for k in (4, 5, 3, 0, 2, 1)]
    mods.append(dict(t="o_lantern"))
    mods += [pod_mod(i, 3) for i in (1, 5, 2, 4, 3)]
    mods += [dict(t="o_bridge", pod=i) for i in (0, 1, 5, 2, 4, 3)]
    built = {i: (4 if i == 0 else 3) for i in range(6)}
    while True:
        cand = [i for i in range(1, 6) if built[i] < PODS[i][2]]
        if not cand:
            break
        i = min(cand, key=lambda q: (built[q] / PODS[q][2], q))
        built[i] += 1
        mods.append(pod_mod(i, built[i]))
    mods.append(dict(t="o_spire"))
    mods.append(dict(t="o_band"))
    assert len(mods) == 100, len(mods)
    return mods


def dome_wedge(g, k):
    c, r, hd, oc = OB["c"], OB["dome"], OB["dome_h"], OB["oculus"]
    z0 = 13.0
    a0, a1 = k * math.pi / 3, (k + 1) * math.pi / 3
    nlon, nlat = 4, 5
    ptop = math.acos(oc / r)

    def P(i, j):
        th = a0 + (a1 - a0) * i / nlon
        ph = ptop * j / nlat
        rr = r * math.cos(ph)
        return (c[0] + rr * math.cos(th), c[1] + rr * math.sin(th), z0 + hd * math.sin(ph))
    for j in range(nlat):
        for i in range(nlon):
            q = [P(i, j), P(i + 1, j), P(i + 1, j + 1), P(i, j + 1)]
            ctr = [sum(p[t] for p in q) / 4 for t in range(3)]
            out = (ctr[0] - c[0], ctr[1] - c[1], (ctr[2] - z0) * 1.5)
            inner = [tuple(ctr[t] + 0.8 * (p[t] - ctr[t]) for t in range(3)) for p in q]
            g.poly(inner, PAPER, "domeglass", out)
            for e in range(4):
                g.poly([q[e], q[(e + 1) % 4], inner[(e + 1) % 4], inner[e]], PAPER, "vc", out)


def draw_O(g, built, nxt):
    c = OB["c"]
    kinds = {m["t"] for m in built}
    draw_arcs(g, built, nxt, lambda m: "garden")

    def roof(g2, m):
        style = PODS[m["pod"]][4]
        pod_roof(g2, m, style)
    draw_towers(g, built, nxt, roof)
    r = OB["dome"]
    if "o_drum" in kinds:
        g.prism(c, 24, 0.0, SLAB, r + 1.5, r + 1.5, 0.0, color=PAPER, cols={"t": FLOOR})
        g.prism(c, 24, SLAB, 12.0, r, r, 0.0, color=PAPER, mat="domeglass", faces="s")
        for q in range(12):
            x, y = polar(c, r + 0.1, q * math.pi / 6)
            g.box((x, y, 6.75), (0.9, 0.9, 10.5), PAPER, yaw=q * math.pi / 6)
        g.prism(c, 24, 12.0, 13.0, r + 1.2, r + 1.2, 0.0, color=PAPER, cols={"b": OAK})
        g.prism(c, 24, SLAB, SLAB + 0.3, r - 0.6, r - 0.6, 0.0, color=LAWN, faces="t")
        g.prism(c, 20, SLAB, SLAB + 0.5, 9.0, 9.0, 0.0, color=CONCRETE, faces="ts")
        g.prism(c, 20, SLAB, SLAB + 0.6, 8.0, 8.0, 0.0, color=PAPER, mat="water", faces="t")
        for q in range(9):
            a = q * 2 * math.pi / 9 + 0.3
            x, y = polar(c, 22.0 if q % 2 else 27.0, a)
            g.trees.append(("LP_Eucalypt" if q % 3 == 0 else "LP_Oak_A", x, y, SLAB + 0.3, 16.0 if q % 3 == 0 else 9.0))
    for m in built:
        if m["t"] == "o_wedge":
            dome_wedge(g, m["k"])
    ztop = 13.0 + OB["dome_h"] * math.sin(math.acos(OB["oculus"] / r))
    if "o_lantern" in kinds:
        g.sector(c, 0.0, 2 * math.pi, 16, ztop - 0.6, ztop + 0.8, OB["oculus"] - 0.6, OB["oculus"] + 1.2, PAPER, faces="tboi")
        g.prism(c, 16, SLAB + 0.6, ztop, 2.4, 2.4, 0.0, color=PAPER, mat="falls", faces="s")
    for m in built:
        if m["t"] == "o_bridge":
            ang = math.radians(PODS[m["pod"]][0])
            L["bridge"](g, dict(c=c, ang=ang, r0=33.0, r1=OB["ring"] - PODS[m["pod"]][1] + 1.5, z=2 * H))
    if "o_spire" in kinds:
        L["spire"](g, dict(c=pod_c(2), z=22 * H + SLAB, h=66.0, r=3.0, halo=11.0))
    if "o_band" in kinds:
        for (a0, a1) in ring_arcs():
            z = 2 * H + SLAB
            g.sector(c, a0, a1, 8, z, z + 2.2, OB["ring"] + OB["ring_d"] / 2 - 0.2, OB["ring"] + OB["ring_d"] / 2 + OV,
                     BRAND, faces="tboicC")


def front_O(nxt):
    c = OB["c"]
    if nxt["t"] in ("o_wedge", "o_drum", "o_lantern"):
        x, y = polar(c, OB["dome"] + 6.0, math.radians(200))
        return crane_at(x, y, 0.0, 45.0, math.radians(20))
    return None


# ================================================================ C  THE CANOPY
# One continuous roof of shallow hex "dragonscale" bays (Google Bay View) over one
# glass building whose facade is tinted bay by bay by what the bay does. Later
# levels lift the middle bays into a stepped mountain (Nvidia Voyager).
CN = dict(c=(0.0, 18.0), R=20.0)
SQ3 = math.sqrt(3.0)


def hex_dist(q, r):
    return (abs(q) + abs(r) + abs(q + r)) // 2


def cell_xy(q, r):
    return (CN["c"][0] + CN["R"] * SQ3 * (q + r / 2.0), CN["c"][1] + CN["R"] * 1.5 * r)


def cn_cells():
    """26 cells in build order: centre, ring 1 and ring 2 from the front, then a back arc."""
    def ring(d):
        cs = [(q, r) for q in range(-d, d + 1) for r in range(-d, d + 1) if hex_dist(q, r) == d]

        def key(qr):
            x, y = cell_xy(*qr)
            a = math.atan2(y - CN["c"][1], x - CN["c"][0])
            return abs(((a + math.pi / 2 + math.pi) % (2 * math.pi)) - math.pi)
        return sorted(cs, key=key)
    back = sorted(ring(3), key=lambda qr: -cell_xy(*qr)[1])[:7]
    back.sort(key=lambda qr: abs(cell_xy(*qr)[0]))
    return [(0, 0)] + ring(1) + ring(2) + back


CN_R1 = [("lobby", "studio"), ("lobby", "eng"), ("studio", "cafe"), ("labs", "labs"), ("eng", "labs"), ("servers", "servers")]
CN_R2 = ["lobby", "eng", "cafe", "eng", "studio", "garden", "labs", "servers", "eng", "studio", "labs", "eng"]
CN_BACK = ["labs", "eng", "studio", "cafe", "eng", "labs", "board"]


def cn_fns():
    cells = cn_cells()
    fns = {}
    fns[cells[0]] = ["lobby", "cafe", "board", "board", "exec", "exec"]
    for i, cl in enumerate(cells[1:7]):
        a, b = CN_R1[i]
        fns[cl] = [a, b, "eng" if i % 2 else "labs", "labs" if i % 2 else "eng"]
    for i, cl in enumerate(cells[7:19]):
        f = CN_R2[i]
        fns[cl] = [f, "cafe" if f == "lobby" else f]
    for i, cl in enumerate(cells[19:]):
        fns[cl] = [CN_BACK[i], CN_BACK[i]]
    return fns


def plan_C():
    cells = cn_cells()
    fns = cn_fns()
    mods = []
    for cl in cells:
        mods.append(dict(t="tent", cell=cl))
        mods.append(dict(t="pav", cell=cl, s=1, fn=fns[cl][0]))
        mods.append(dict(t="pav", cell=cl, s=2, fn=fns[cl][1]))
    mods += [dict(t="trellis", k=k) for k in (2, 1, 3, 0, 4)]
    ctr, r1 = cells[0], cells[1:7]
    mods += [dict(t="pav", cell=ctr, s=3, fn=fns[ctr][2]), dict(t="pav", cell=ctr, s=4, fn=fns[ctr][3])]
    mods += [dict(t="pav", cell=cl, s=3, fn=fns[cl][2]) for cl in r1]
    mods.append(dict(t="pav", cell=ctr, s=5, fn=fns[ctr][4]))
    mods += [dict(t="pav", cell=cl, s=4, fn=fns[cl][3]) for cl in r1]
    mods.append(dict(t="pav", cell=ctr, s=6, fn=fns[ctr][5]))
    mods.append(dict(t="c_lantern"))
    assert len(mods) == 100, len(mods)
    return mods


def cn_corner(cx, cy, k, f=1.0):
    a = math.radians(30 + 60 * k)
    return (cx + f * CN["R"] * math.cos(a), cy + f * CN["R"] * math.sin(a))


TENT_F = [1.0, 0.86, 0.5, 0.2]
TENT_H = [0.0, 1.6, 4.4, 5.4]


def tent(g, cx, cy, e, open_court=False):
    """One shallow hex bay of the dragonscale roof: a paper rim, silver-blue scales,
    an oak soffit and a small skylight at the peak. open_court = rim only."""
    def P(k, i, dz=0.0):
        x, y = cn_corner(cx, cy, k % 6, TENT_F[i])
        return (x, y, e + TENT_H[i] + dz)
    for i in range(1 if open_court else 3):
        for k in range(6):
            q = [P(k, i), P(k + 1, i), P(k + 1, i + 1), P(k, i + 1)]
            mx = sum(p[0] for p in q) / 4 - cx
            my = sum(p[1] for p in q) / 4 - cy
            if i == 0:
                g.poly(q, PAPER, "vc", (mx, my, 30.0))
            else:
                g.poly(q, SCALE, "scale", (mx, my, 30.0))
            g.poly([P(k, i, -1.4), P(k, i + 1, -1.4), P(k + 1, i + 1, -1.4), P(k + 1, i, -1.4)], OAK, "vc", (0, 0, -1))
    for k in range(6):
        a = math.radians(60 + 60 * k)
        g.poly([P(k, 0, -1.4), P(k + 1, 0, -1.4), P(k + 1, 0), P(k, 0)], PAPER, "vc", (math.cos(a), math.sin(a), 0))
        if open_court:
            g.poly([P(k, 1, -1.4), P(k, 1), P(k + 1, 1), P(k + 1, 1, -1.4)], PAPER, "vc", (-math.cos(a), -math.sin(a), 0))
    if not open_court:
        rs = TENT_F[3] * CN["R"]
        zt = e + TENT_H[3]
        g.prism((cx, cy), 6, zt - 1.4, zt + 2.0, rs, rs, math.radians(30), color=PAPER, mat="glass_lobby", faces="s")
        g.prism((cx, cy), 6, zt + 2.0, zt + 2.8, rs + 0.8, rs + 0.8, math.radians(30), color=PAPER, cols={"b": OAK})


def draw_C(g, built, nxt):
    cells = cn_cells()
    pos = {cl: cell_xy(*cl) for cl in cells}
    by_xy = {(round(x, 1), round(y, 1)): cl for cl, (x, y) in pos.items()}
    tents = {m["cell"] for m in built if m["t"] == "tent"}
    fns = cn_fns()
    stor = {}
    for m in built:
        if m["t"] == "pav":
            stor[m["cell"]] = max(stor.get(m["cell"], 0), m["s"])

    def court(cl):
        return fns[cl][0] == "garden"

    def has(cl, s):
        return cl is not None and cl in tents and not court(cl) and stor.get(cl, 0) >= s

    def eave(cl):
        n = stor.get(cl, 0)
        return n * H if n >= 3 else 2 * H + 4.0

    def neighbour(cl, k):
        x, y = pos[cl]
        a = math.radians(60 + 60 * k)
        return by_xy.get((round(x + SQ3 * CN["R"] * math.cos(a), 1), round(y + SQ3 * CN["R"] * math.sin(a), 1)))
    cols = {}
    canopy_done = False
    for cl in sorted(tents, key=lambda q: pos[q][1]):
        x, y = pos[cl]
        e = eave(cl)
        n = stor.get(cl, 0)
        tent(g, x, y, e, open_court=court(cl))
        if court(cl):
            if n >= 1:
                g.prism((x, y), 6, 0.5, 0.9, CN["R"] - 0.5, CN["R"] - 0.5, math.radians(30), color=LAWN, faces="t")
                for q, (dx, dy, h) in enumerate(((0, 0, 14.0), (-7, -5, 9.0), (7, 4, 9.0))):
                    g.trees.append(("LP_Oak_A" if q else "LP_Eucalypt", x + dx, y + dy, 0.9, h))
            if n >= 2:
                g.prism((x, y + 7), 10, 0.5, 9.0, 4.5, 4.5, 0.0, color=PAPER, mat="glass_cafe", faces="s")
                g.prism((x, y + 7), 10, 9.0, 10.0, 5.5, 5.5, 0.0, color=PAPER, cols={"b": OAK})
        if n == 0 or court(cl):
            for k in (0, 2, 4):
                px, py = cn_corner(x, y, k)
                key = (round(px, 1), round(py, 1))
                cols[key] = max(cols.get(key, 0.0), e - 1.4)
            continue
        g.prism((x, y), 6, 0.0, 0.9, CN["R"], CN["R"], math.radians(30), color=PAPER, cols={"t": FLOOR}, faces="ts")
        for s in range(1, n + 1):
            z0 = 0.9 if s == 1 else (s - 1) * H
            z1 = (e - 1.4) if (s == n and s >= 2) else s * H
            fn = fns[cl][s - 1]
            for k in range(6):
                nb = neighbour(cl, k)
                if has(nb, s):
                    continue
                p0, p1 = cn_corner(x, y, k), cn_corner(x, y, k + 1)
                a = math.radians(60 + 60 * k)
                out = (math.cos(a), math.sin(a), 0)
                zg = z0
                if s > 1:
                    g.poly([(p0[0], p0[1], z0), (p1[0], p1[1], z0), (p1[0], p1[1], z0 + SLAB), (p0[0], p0[1], z0 + SLAB)],
                           PAPER, "vc", out)
                    zg = z0 + SLAB
                g.poly([(p0[0], p0[1], zg), (p1[0], p1[1], zg), (p1[0], p1[1], z1), (p0[0], p0[1], z1)],
                       PAPER, "glass_" + fn, out)
                for f in (0.0, 1 / 3, 2 / 3):
                    fx, fy = p0[0] + (p1[0] - p0[0]) * f, p0[1] + (p1[1] - p0[1]) * f
                    g.box((fx + out[0] * 0.35, fy + out[1] * 0.35, (zg + z1) / 2), (0.7, 0.7, z1 - zg), OAK)
                if s == 1 and fn == "lobby" and not canopy_done and out[1] < -0.4:
                    canopy_done = True
                    mx, my = (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2
                    yaw = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
                    g.box((mx + out[0] * 5, my + out[1] * 5, 10.4), (13.0, 10.0, 0.8), PAPER, yaw=yaw, cols={"b": OAK})
                    g.box((mx + out[0] * 9.8, my + out[1] * 9.8, 11.9), (13.0, 0.8, 2.4), ACCENT, yaw=yaw)
    for (px, py), top in cols.items():
        column(g, px, py, 0.0, top, r=0.85)
    # Voyager's solar trellis over the entrance plaza
    tc, tr0, tr1, zt = CN["c"], 94.0, 104.0, 34.0
    span = math.radians(84)
    seg = span / 5
    base = -math.pi / 2 - span / 2
    trel = sorted(m["k"] for m in built if m["t"] == "trellis")
    posts = set()
    for k in trel:
        a0, a1 = base + k * seg, base + (k + 1) * seg
        g.sector(tc, a0, a1, 4, zt, zt + 0.9, tr0, tr1, PAPER, cols={"b": OAK})
        for q in range(6):
            b0 = a0 + (a1 - a0) * (q + 0.1) / 6
            g.sector(tc, b0, b0 + (a1 - a0) * 0.7 / 6, 1, zt + 0.9, zt + 1.3, tr0 + 0.6, tr1 - 0.6, PAPER,
                     mats={"t": "solar"}, faces="toicC")
        posts.add(round(a0, 4))
        posts.add(round(a1, 4))
    for a in posts:
        for rr in (tr0 + 1.0, tr1 - 1.0):
            x, y = polar(tc, rr, a)
            column(g, x, y, 0.0, zt, r=0.7)
    if any(m["t"] == "c_lantern" for m in built):
        x, y = pos[(0, 0)]
        z = eave((0, 0)) + TENT_H[3] + 2.8
        g.prism((x, y), 6, z, z + 12.0, 3.0, 3.0, math.radians(30), color=PAPER, mat="glass_exec", faces="s")
        g.prism((x, y), 6, z + 12.0, z + 13.0, 4.2, 4.2, math.radians(30), color=PAPER)
        g.sector((x, y), 0.0, 2 * math.pi, 24, z + 5.0, z + 7.0, 6.0, 7.4, BRAND, faces="tboi")
        L["spire"](g, dict(c=(x, y), z=z + 13.0, h=40.0, r=1.8))


def front_C(nxt):
    if nxt["t"] in ("tent", "pav"):
        x, y = cell_xy(*nxt["cell"])
        a = math.atan2(y - CN["c"][1], x - CN["c"][0]) if nxt["cell"] != (0, 0) else -math.pi / 2
        cx, cy = x + (CN["R"] + 16) * math.cos(a), y + (CN["R"] + 16) * math.sin(a)
        return crane_at(cx, cy, 0.0, (nxt.get("s", 2)) * H + 14.0, a + math.pi)
    return None


# ================================================================ registry
FORMATS = {
    "W": dict(name="THE WAFERS", plan=plan_W, draw=draw_W, front=front_W,
              entrance=(0.0, -13.0), plaza=((0.0, -42.0), 24.0), ref="Samsung America HQ, San Jose (NBBJ)"),
    "T": dict(name="THE TWIN LINK", plan=plan_T, draw=draw_T, front=front_T,
              entrance=(0.0, 16.0), plaza=((0.0, -30.0), 34.0), ref="Tencent Seafront Towers; Marina Bay Sands"),
    "S": dict(name="THE SPIRAL", plan=plan_S, draw=draw_S, front=front_S,
              entrance=(0.0, -42.0), plaza=((0.0, -66.0), 22.0), ref="BIG 8 House ramp; a helix round a lift core"),
    "O": dict(name="THE ORBIT", plan=plan_O, draw=draw_O, front=front_O,
              entrance=(0.0, -55.0), plaza=((0.0, -80.0), 22.0), ref="Jewel Changi; Amazon Spheres; Galaxy SOHO"),
    "C": dict(name="THE CANOPY", plan=plan_C, draw=draw_C, front=front_C,
              entrance=(0.0, -58.0), plaza=((0.0, -84.0), 30.0), ref="Google Bay View; Nvidia Voyager"),
}


def build(fmt, level, with_front=True):
    F = FORMATS[fmt]
    plan = F["plan"]()
    g = Geo()
    built = plan[:level]
    nxt = plan[level] if (with_front and level < len(plan)) else None
    F["draw"](g, built, nxt)
    front = None
    if nxt is not None:
        if nxt["t"] in ("arc", "spiral"):
            L["arc_storey"](g, nxt, skel=True)
            amid = (nxt["a0"] + nxt["a1"]) / 2
            c = nxt["c"]
            side_in = nxt.get("crane_side") == "in"
            r = (R(nxt["rin"], amid) - 13.0) if side_in else (R(nxt["rout"], amid) + 13.0)
            x, y = c[0] + r * math.cos(amid), c[1] + r * math.sin(amid)
            front = (x, y, 0.0, nxt["z"] + H, amid if side_in else amid + math.pi)
        elif nxt["t"] == "tower":
            L["tower_storey"](g, nxt, skel=True)
            d = nxt["crane_dir"]
            rr = max(nxt["rx0"], nxt["ry0"]) + 13.0
            x, y = nxt["c"][0] + rr * math.cos(d), nxt["c"][1] + rr * math.sin(d)
            front = (x, y, 0.0, nxt["z"] + H, d + math.pi)
        else:
            front = F["front"](nxt)
    return g, front, plan


# ================================================================ site, trees, people
PLOT = 150.0
ROAD_Y = -176.0
_OCC = {}


def occupancy(fmt):
    """Cells (8 studs) covered by the finished building, dilated: no lawn trees there."""
    if fmt in _OCC:
        return _OCC[fmt]
    g, _, _ = build(fmt, 100, with_front=False)
    cells = set()
    for v in g.bm.verts:
        cells.add((int(math.floor(v.co.x / 8)), int(math.floor(v.co.y / 8))))
    for (name, x, y, z, h) in g.trees:
        cells.add((int(math.floor(x / 8)), int(math.floor(y / 8))))
    g.bm.free()
    dil = set()
    for (i, j) in cells:
        for di in (-1, 0, 1):
            for dj in (-1, 0, 1):
                dil.add((i + di, j + dj))
    _OCC[fmt] = dil
    return dil


def blocked(fmt, x, y):
    if abs(y - ROAD_Y) < 21:
        return True
    (px, py), pr = FORMATS[fmt]["plaza"]
    if abs(x) < 9 and ROAD_Y < y < py:
        return True
    if math.hypot(x - px, y - py) < pr + 6:
        return True
    cam, tgt = ground_cam(fmt)
    ex, ey = FORMATS[fmt]["entrance"]
    vx, vy = ex - cam.x, ey - cam.y
    t = max(0.0, min(1.0, ((x - cam.x) * vx + (y - cam.y) * vy) / (vx * vx + vy * vy)))
    if math.hypot(x - (cam.x + t * vx), y - (cam.y + t * vy)) < 16.0 + 26.0 * t:
        return True
    return (int(math.floor(x / 8)), int(math.floor(y / 8))) in occupancy(fmt)


def site(fmt, g):
    cells = 20
    s = 2 * PLOT / cells
    for i in range(cells):
        for j in range(cells):
            x0, y0 = -PLOT + i * s, -PLOT + j * s
            k = 1.035 if (i % 2 == 0) else 0.965
            col = tuple(min(1, c * k) for c in LAWN)
            g.poly([(x0, y0, 0.5), (x0 + s, y0, 0.5), (x0 + s, y0 + s, 0.5), (x0, y0 + s, 0.5)], col, "matte", (0, 0, 1))
    P2 = 2 * PLOT + 3
    for (cx, cy, sx, sy) in ((0, -PLOT - 0.8, P2, 1.6), (0, PLOT + 0.8, P2, 1.6), (-PLOT - 0.8, 0, 1.6, P2), (PLOT + 0.8, 0, 1.6, P2)):
        g.box((cx, cy, 0.45), (sx, sy, 0.9), CONCRETE, mat="matte")
    g.box((0, ROAD_Y, 0.15), (3200, 24, 0.3), ASPHALT, mat="matte")
    for sy in (-1, 1):
        g.box((0, ROAD_Y + sy * 14.6, 0.25), (3200, 5.2, 0.5), CONCRETE, mat="matte")
    for x in range(-1500, 1501, 18):
        g.box((x, ROAD_Y, 0.32), (7, 0.5, 0.06), rgb(236, 226, 196), mat="matte")
    (px, py), pr = FORMATS[fmt]["plaza"]
    L_ = math.hypot(0, py - (-PLOT - 8))
    g.box((0, (py + (-PLOT - 8)) / 2, 0.58), (10, L_, 0.16), CONCRETE, mat="matte")
    g.prism((px, py), 40, 0.5, 0.62, pr, pr, 0.0, color=CONCRETE, mat="matte", faces="ts")
    g.prism((px, py), 24, 0.5, 1.1, 7.0, 7.0, 0.0, color=CONCRETE, mat="matte", faces="ts")
    g.prism((px, py), 24, 0.5, 1.15, 6.0, 6.0, 0.0, color=PAPER, mat="water", faces="t")
    ex, ey = FORMATS[fmt]["entrance"]
    if ey > py + pr:
        g.box((ex, (ey + py + pr) / 2 - 2, 0.6), (12, ey - py - pr + 4, 0.18), CONCRETE, mat="matte")


def scatter(fmt):
    rng = random.Random(21)
    for x in range(-560, 561, 28):
        if abs(x) < 18:
            continue
        for yy in (-160.5, -191.5):
            L["tree"]("LP_Palm_A" if (x // 28) % 2 else "LP_Palm_B", x + rng.uniform(-2, 2), yy, 0.5, rng.uniform(20, 25), rng=rng)
    placed, tries = 0, 0
    while placed < 46 and tries < 4000:
        tries += 1
        x, y = rng.uniform(-142, 142), rng.uniform(-142, 142)
        if blocked(fmt, x, y):
            continue
        if rng.random() < 0.18:
            L["tree"]("LP_Eucalypt", x, y, 0.5, rng.uniform(20, 28), rng=rng)
        else:
            L["tree"]("LP_Oak_A" if rng.random() < 0.5 else "LP_Oak_B", x, y, 0.5, rng.uniform(11, 15), rng=rng)
        placed += 1
    placed, tries = 0, 0
    while placed < 320 and tries < 9000:
        tries += 1
        x, y = rng.uniform(-1100, 1100), rng.uniform(-150, 1500)
        if abs(x) < 170 and y < 170:
            continue
        if abs(y - ROAD_Y) < 26:
            continue
        h = L["ground_h"](x, y)
        wood = noise.noise(Vector((x / 170.0, y / 170.0, 7.0)))
        if h > 6 and wood < -0.08 and rng.random() < 0.7:
            continue
        if y > 1150 and h > 60:
            L["tree"]("LP_RedwoodGrove", x, y, h - 0.5, rng.uniform(26, 32), rng=rng)
        elif h > 8 and rng.random() < 0.4:
            L["tree"]("LP_Grove", x, y, h - 0.5, rng.uniform(12, 16), rng=rng)
        else:
            L["tree"]("LP_Oak_A" if rng.random() < 0.5 else "LP_Oak_B", x, y, h - 0.3, rng.uniform(11, 15), rng=rng)
        placed += 1


def ground_cam(fmt):
    ex, ey = FORMATS[fmt]["entrance"]
    cam = Vector((ex + 24.0, ey - 82.0, 6.5))
    tgt = Vector((ex - 4.0, ey + 18.0, 31.0))
    return cam, tgt


def people(fmt):
    g = Geo()
    rng = random.Random(5)
    shirts = [ACCENT, BLUE, rgb(250, 208, 90), rgb(120, 190, 120), PAPER]
    skins = [rgb(236, 196, 160), rgb(200, 150, 110), rgb(150, 100, 70), rgb(110, 72, 50)]
    (px, py), pr = FORMATS[fmt]["plaza"]
    spots = [(px - 10, py + 6), (px + 12, py - 4), (px - 4, py - 14), (px + 6, py + 14), (px + 2, -128)]
    for i, (x, y) in enumerate(spots):
        L["person"](g, x, y, rng.uniform(0, 2 * math.pi), shirts[i % 5], INK if i % 2 else rgb(70, 90, 130), skins[i % 4])
    # the player: 12 studs in front of the plaza camera, back to it (scale for the ground view)
    cam, tgt = ground_cam(fmt)
    d = Vector((tgt.x - cam.x, tgt.y - cam.y, 0)).normalized()
    p = cam + d * 13.0
    L["person"](g, p.x, p.y, math.atan2(d.y, d.x) + math.pi / 2, ACCENT, INK, skins[1])
    for (x, lane, col) in ((-140, -6, PAPER), (70, 6, ACCENT), (260, -6, BLUE), (-330, 6, PAPER)):
        yy = ROAD_Y + lane
        g.box((x, yy, 1.6), (9.4, 4.2, 1.8), col)
        g.box((x - 0.4, yy, 3.0), (5.4, 3.7, 1.4), INK_SOFT)
        for dx in (-3, 3):
            for dy in (-2.0, 2.0):
                g.box((x + dx, yy + dy, 0.9), (1.7, 0.7, 1.7), INK)
    return g


# ================================================================ cameras + render
_BB = {}


def bounds(fmt, level):
    key = (fmt, level)
    if key in _BB:
        return _BB[key]
    g, front, _ = build(fmt, level, with_front=True)
    xs = [v.co.x for v in g.bm.verts]
    ys = [v.co.y for v in g.bm.verts]
    zs = [v.co.z for v in g.bm.verts]
    g.bm.free()
    b = (min(xs), max(xs), min(ys), max(ys), max(zs))
    _BB[key] = b
    return b


def aerial_points(fmt, level, margin):
    x0, x1, y0, y1, z1 = bounds(fmt, level)
    (px, py), pr = FORMATS[fmt]["plaza"]
    y0 = min(y0, py - pr)
    pts = [(x, y, z) for x in (x0 - margin, x1 + margin) for y in (y0 - margin, y1 + margin) for z in (0.0, z1)]
    return pts


def set_cam(cam, scene, pos, tgt, lens=None, vfov=None, res=AERIAL_RES):
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


def render_level(fmt, level, stats):
    t0 = time.time()
    K.reset()
    L["_TT"].clear()
    L["TREE_TRIS"][0] = 0
    scene = bpy.context.scene
    L["setup_gpu"](scene)
    make_mats()
    g, front, plan = build(fmt, level)
    tris, zmax, gtrees = g.tris, g.zmax, list(g.trees)
    xs = [v.co.x for v in g.bm.verts]
    ys = [v.co.y for v in g.bm.verts]
    foot = (round(max(xs) - min(xs)), round(max(ys) - min(ys)))
    g.to_object("HQ")
    for (name, x, y, z, h) in gtrees:
        L["tree"](name, x, y, z, h, rng=random.Random(int(x * 7 + y * 13)))
    gtt = L["TREE_TRIS"][0]
    if front:
        cg = Geo()
        L["crane"](cg, *front)
        cg.to_object("Crane")
    sg = L["ground"]()
    site(fmt, sg)
    sg.to_object("Site")
    people(fmt).to_object("People")
    scatter(fmt)
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
        except Exception:
            pass
    L["composite"](scene, world, 500.0)
    views = ["aerial"]
    if level <= 30:
        views.append("close")
    if level >= 30:
        views.append("ground")
    files = {}
    tb = time.time()
    for v in views:
        if v == "aerial":
            pos, tgt, d = L["fit_camera"](aerial_points(fmt, 100, 14.0), AERIAL_RES[0] / AERIAL_RES[1])
            set_cam(cam, scene, pos, tgt, lens=L["LENS"])
            world.mist_settings.start = d * 0.9
        elif v == "close":
            pos, tgt, d = L["fit_camera"](aerial_points(fmt, 30, 10.0), AERIAL_RES[0] / AERIAL_RES[1])
            set_cam(cam, scene, pos, tgt, lens=L["LENS"])
            world.mist_settings.start = d * 0.9
        else:
            pos, tgt = ground_cam(fmt)
            set_cam(cam, scene, pos, tgt, vfov=70.0, res=GROUND_RES)
            world.mist_settings.start = 260.0
        name = "%s_L%03d_%s.png" % (fmt, level, v)
        scene.render.filepath = os.path.join(OUT, name)
        bpy.ops.render.render(write_still=True)
        files[v] = name
    fns = {}
    for m in plan[:level]:
        if m.get("fn"):
            fns[m["fn"]] = fns.get(m["fn"], 0) + 1
    st = dict(fmt=fmt, name=FORMATS[fmt]["name"], level=level, files=files, building_tris=tris,
              garden_trees=len(gtrees), garden_tree_tris=gtt, height=round(zmax, 1), footprint=foot,
              front=bool(front), functions=fns, build_s=round(tb - t0, 1), render_s=round(time.time() - tb, 1))
    stats.append(st)
    print("STAGE", json.dumps(st))


def dry():
    for fmt in OPT["fmts"]:
        for level in range(1, 101):
            g, front, plan = build(fmt, level)
            if level in (1, 5, 30, 60, 100):
                print("DRY", fmt, level, plan[level - 1]["t"], "tris", g.tris, "h", round(g.zmax, 1), "front", bool(front))
            g.bm.free()


def main():
    if OPT.get("dry") == "1":
        dry()
        return
    sp = os.path.join(OUT, "stats.json")
    stats = []
    if os.path.exists(sp):
        try:
            stats = [s for s in json.load(open(sp)) if not (s["fmt"] in OPT["fmts"] and s["level"] in LEVELS)]
        except Exception:
            stats = []
    for fmt in OPT["fmts"]:
        for level in LEVELS:
            render_level(fmt, level, stats)
    stats.sort(key=lambda s: (s["fmt"], s["level"]))
    json.dump(stats, open(sp, "w"), indent=1)
    meta = {}
    for f in FORMATS:
        meta[f] = [dict(level=i + 1, t=m["t"], fn=m.get("fn", "")) for i, m in enumerate(FORMATS[f]["plan"]())]
    json.dump(dict(functions={k: dict(label=v["label"], glow=v["glow"], kind=v["kind"]) for k, v in FN.items()},
                   names={f: FORMATS[f]["name"] for f in FORMATS}, refs={f: FORMATS[f]["ref"] for f in FORMATS},
                   plans=meta), open(os.path.join(OUT, "plans.json"), "w"), indent=0)


if __name__ == "__main__" or True:
    main()
