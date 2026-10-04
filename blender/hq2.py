"""hq2.py -- v4.0 THE HQ, REBUILT (27 Sep 2026).

His verdict on the V3 shells: "extremely blocky and linear... floors 2 3 4 and 5
look like jewelry storefronts and the golden bars make it look like a prison."
Both were true, and both had one cause each:
  - full-height glass on every storey, lit from inside, with a row of small
    objects behind it = a display case
  - a full-height oak fin screen (oak renders gold) = bars

So this generation changes the facade grammar, not the colours:
  1. EVERY storey above the lobby is a RIBBON WINDOW over a solid SPANDREL:
     the lower 2.7 studs of each floor are opaque, the glass is a horizontal
     band. Desks sit behind the spandrel; you see ceilings, lamps and people.
  2. The plan is a ROUNDED RECTANGLE (radius 5-8): slab edges, spandrels,
     glass and mullions all wrap the corners. Nothing reads as a box.
  3. No fin screens anywhere. Mullions are slim and charcoal.
  4. Each level is a FINISHED building, and each is the previous one grown:
       2 STARTUP OFFICE  a one-storey pavilion: glass at door height, a white
                         clerestory band, a big floating roof
       3 TECH HQ         glass lobby + one ribbon floor, a lift core on the roof
       4 GLASS TOWER     three storeys, a cantilevered front terrace with
                         planters, a living wall, solar on the roof
       5 CAMPUS HQ       five storeys, staggered terraces (front, sides, front),
                         the living wall, and a ROOF GARDEN you can walk on
                         (deck, glass balustrade, planters, pergola, lift core)
The game keeps its box collision (made invisible) and adds the floors, the lift
and the rounded-corner collision (HQFloors.lua).

Footprints grow (v4.0): 2 = 56x44, 3 = 72x52, 4 = 84x56, 5 = 96x56 (heights
unchanged: 20 / 28 / 44 / 60). Game X = -Blender X (see hq.py), so anything
not mirror-symmetric is placed with gx().

Run:  blender -b --python hq2.py [-- 2 3 4 5]
"""
import bpy
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import svkit as K  # noqa: E402
import hq as H  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Vector  # noqa: E402

OUT = H.OUT
IMP = os.path.join(OUT, "IMPORT_HQ2")
os.makedirs(IMP, exist_ok=True)

LEVELS = {
    2: dict(name="STARTUP OFFICE", w=56, d=44, h=20, R=5.0),
    3: dict(name="TECH HQ", w=72, d=52, h=28, R=7.0),
    4: dict(name="GLASS TOWER", w=84, d=56, h=44, R=8.0),
    5: dict(name="CAMPUS HQ", w=96, d=56, h=60, R=8.0),
}
DOOR_W = H.DOOR_W
FLOOR_TOP = H.FLOOR_TOP
PAPER, PAPER_WARM, CONCRETE, OAK, OAK_DARK = H.PAPER, H.PAPER_WARM, H.CONCRETE, H.OAK, H.OAK_DARK
INK, CHARCOAL, METAL, MEMBRANE, CEILING = H.INK, H.CHARCOAL, H.METAL, H.MEMBRANE, H.CEILING
SOLAR, LEAF, LEAF_DARK, WHITE = H.SOLAR, H.LEAF, H.LEAF_DARK, H.WHITE
SPANDREL = K.rgb(226, 221, 211)
LEAF_LIGHT = K.rgb(132, 178, 96)
FLOWER = [K.rgb(236, 176, 72), K.rgb(214, 110, 96), K.rgb(236, 232, 214)]
DECK = K.rgb(176, 128, 84)
span, box, rslab, pane, cyl, blob, shade = H.span, H.box, H.rslab, H.pane, H.cyl, H.blob, H.shade
SOFFIT = K.rgb(226, 220, 208)
FLOORPLATE = K.rgb(222, 218, 210)


def roof_shade(top_col, edge_col):
    """Pale membrane on top, the slab colour on its edge, a warm white soffit below."""
    edge = shade(edge_col)
    under = shade(SOFFIT, bottom=0.9)

    def f(p, n):
        if n.z > 0.5:
            return tuple(min(1.0, c * 1.02) for c in top_col)
        if n.z < -0.5:
            return under(p, n)
        return edge(p, n)
    return f


def rrect_loop(hw, hd, R, off, segs=8):
    """A rounded rectangle's outline, offset `off` outward, counter-clockwise."""
    pts = []
    r = max(0.05, R + off)
    for cx, cy, a0 in ((hw - R, hd - R, 0), (-(hw - R), hd - R, 90), (-(hw - R), -(hd - R), 180), (hw - R, -(hd - R), 270)):
        for k in range(segs + 1):
            a = math.radians(a0 + 90 * k / segs)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def ring_slab(hw, hd, R, off_in, off_out, z0, z1, col, fn=None):
    """A HOLLOW rounded slab edge (a band round the building): the floor inside
    stays the game's. A solid slab here covered the floors' finishes."""
    outer = rrect_loop(hw, hd, R, off_out)
    inner = rrect_loop(hw, hd, R, off_in)
    bm = bmesh.new()
    ot = [bm.verts.new((x, y, z1)) for x, y in outer]
    ob = [bm.verts.new((x, y, z0)) for x, y in outer]
    it = [bm.verts.new((x, y, z1)) for x, y in inner]
    ib = [bm.verts.new((x, y, z0)) for x, y in inner]
    n = len(outer)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((ot[i], ot[j], it[j], it[i]))
        bm.faces.new((ob[i], ib[i], ib[j], ob[j]))
        bm.faces.new((ob[i], ob[j], ot[j], ot[i]))
        bm.faces.new((ib[i], it[i], it[j], ib[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    o = K.mesh_obj("ring", bm)
    return H._finish(o, col, 0.0, "shell", fn)


def gx(x):
    """Game plot-local X -> Blender X (the importer mirrors X)."""
    return -x


# ------------------------------------------------------------------ the rounded plan
def plan(hw, hd, R, segs=6):
    """Segments (a, b, tag) round a rounded rectangle, starting at the front
    centre and heading to +X. Tags: F front, CF front corner, S side, CB back
    corner, B back. Outward normal of a segment = its direction turned +90."""
    out = []

    def arc(cx, cy, a0, a1, tag):
        for k in range(segs):
            t0 = math.radians(a0 + (a1 - a0) * k / segs)
            t1 = math.radians(a0 + (a1 - a0) * (k + 1) / segs)
            out.append(((cx + R * math.cos(t0), cy + R * math.sin(t0)),
                        (cx + R * math.cos(t1), cy + R * math.sin(t1)), tag))

    # this traversal runs CLOCKWISE seen from +Z
    out.append(((0, hd), (hw - R, hd), "F"))
    arc(hw - R, hd - R, 90, 0, "CF")
    out.append(((hw, hd - R), (hw, -hd + R), "S"))
    arc(hw - R, -hd + R, 0, -90, "CB")
    out.append(((hw - R, -hd), (-hw + R, -hd), "B"))
    arc(-hw + R, -hd + R, -90, -180, "CB")
    out.append(((-hw, -hd + R), (-hw, hd - R), "S"))
    arc(-hw + R, hd - R, 180, 90, "CF")
    out.append(((-hw + R, hd), (0, hd), "F"))
    return out


def outward(a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    L = math.hypot(dx, dy) or 1.0
    return (-dy / L, dx / L)          # clockwise traversal: the outside is to the left


def clip_door(segs, gap):
    """Remove |x| < gap from the front straights (the entrance), keeping direction."""
    res = []
    for a, b, tag in segs:
        if tag != "F":
            res.append((a, b, tag))
            continue
        xa, xb = a[0], b[0]
        lo, hi = min(xa, xb), max(xa, xb)
        keep = []
        if lo < -gap:
            keep.append((lo, min(hi, -gap)))
        if hi > gap:
            keep.append((max(lo, gap), hi))
        for k0, k1 in keep:
            if k1 - k0 < 0.05:
                continue
            if xb >= xa:
                res.append(((k0, a[1]), (k1, a[1]), tag))
            else:
                res.append(((k1, a[1]), (k0, a[1]), tag))
    return res


def pick(segs, tags):
    return [s for s in segs if s[2] in tags]


def wall(segs, z0, z1, t, col, out=0.0, group="shell", fn=None, over=0.06):
    """A wall of thickness t following the segments, centred `out` outside the line."""
    for a, b, _ in segs:
        dx, dy = b[0] - a[0], b[1] - a[1]
        L = math.hypot(dx, dy)
        if L < 0.05:
            continue
        nx, ny = outward(a, b)
        cx, cy = (a[0] + b[0]) / 2 + nx * out, (a[1] + b[1]) / 2 + ny * out
        ang = math.atan2(dy, dx)
        box((L + over * 2, t, z1 - z0), (cx, cy, (z0 + z1) / 2), col, group=group,
            fn=fn if fn else (K.flat(col) if group == "glass" else None), rot=(0, 0, ang))


def glass(segs, z0, z1, out=0.0):
    wall(segs, z0, z1, 0.2, WHITE, out=out, group="glass", over=0.02)


def posts(segs, z0, z1, every, size=(0.26, 0.34), col=None, out=0.12, ends=True):
    """Mullions: evenly spaced along the run, square to the local face."""
    col = col or CHARCOAL
    # walk the whole chain by arc length
    total = sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b, _ in segs)
    if total < 0.1:
        return
    n = max(1, int(round(total / every)))
    step = total / n
    targets = [step * k for k in range(0 if ends else 1, n + (1 if ends else 0))]
    acc = 0.0
    ti = 0
    for a, b, _ in segs:
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        if L < 1e-6:
            continue
        while ti < len(targets) and targets[ti] <= acc + L + 1e-6:
            f = (targets[ti] - acc) / L
            px, py = a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f
            nx, ny = outward(a, b)
            ang = math.atan2(b[1] - a[1], b[0] - a[0])
            box((size[0], size[1], z1 - z0), (px + nx * out, py + ny * out, (z0 + z1) / 2), col, rot=(0, 0, ang))
            ti += 1
        acc += L


def chain_split(segs):
    """Split a clipped chain into continuous runs (so posts restart at the door)."""
    runs, cur = [], []
    for s in segs:
        if cur and (abs(cur[-1][1][0] - s[0][0]) > 0.01 or abs(cur[-1][1][1] - s[0][1]) > 0.01):
            runs.append(cur)
            cur = []
        cur.append(s)
    if cur:
        runs.append(cur)
    return runs


# ------------------------------------------------------------------ pieces
def living_wall(x0, x1, z0, z1, y, rng):
    """A vertical garden standing proud of the facade, framed in white: leafy
    clumps (smooth-shaded, flattened blobs) in three greens with a few flowers.
    A per-cell random colour grid read as pixels; clumps read as planting."""
    span(x0 - 0.6, x1 + 0.6, y - 0.4, y - 0.05, z0 - 0.6, z1 + 0.6, K.rgb(70, 82, 60))
    for zz in (z0 - 0.6, z1):
        span(x0 - 0.8, x1 + 0.8, y - 0.4, y + 1.1, zz, zz + 0.6, PAPER, bev=0.08)
    for xx in (x0 - 0.8, x1):
        span(xx, xx + 0.8, y - 0.4, y + 1.1, z0 - 0.6, z1 + 0.6, PAPER, bev=0.08)
    step = 1.55
    z = z0 + 0.7
    row = 0
    while z < z1 - 0.4:
        x = x0 + 0.7 + (0.75 if row % 2 else 0.0)
        while x < x1 - 0.5:
            r = 0.85 + rng.random() * 0.35
            jx, jz = rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.25)
            bpy.ops.mesh.primitive_ico_sphere_add(radius=r, subdivisions=1, location=(x + jx, y + 0.2, z + jz))
            o = bpy.context.active_object
            o.scale = (1.0, 0.55, 0.9)
            o.rotation_euler = (0, rng.uniform(0, 6.28), 0)
            bpy.ops.object.transform_apply(scale=True, rotation=True)
            bpy.ops.object.shade_smooth()
            if rng.random() < 0.07:
                col = FLOWER[rng.randrange(len(FLOWER))]
            else:
                base = [LEAF, LEAF_DARK, LEAF_LIGHT, LEAF][rng.randrange(4)]
                k = rng.uniform(0.9, 1.06)
                col = tuple(min(1.0, c * k) for c in base)
            H._finish(o, col, 0.0, "shell", shade(col, top=1.08, side=0.96, bottom=0.78))
            x += step
        z += step * 0.86
        row += 1


def planter_run(x0, x1, y, z, rng, depth=1.2, trail=True):
    """A concrete trough with shrubs, and greenery trailing over the front edge."""
    span(x0, x1, y - depth / 2, y + depth / 2, z, z + 1.0, CONCRETE, bev=0.1)
    x = x0 + 0.9
    while x < x1 - 0.6:
        blob(0.55 + rng.random() * 0.25, (x, y, z + 1.35), [LEAF, LEAF_DARK, LEAF_LIGHT][rng.randrange(3)])
        if trail and rng.random() < 0.55:
            box((0.9, 0.25, 1.3 + rng.random()), (x + 0.2, y + depth / 2 + 0.1, z + 0.2), LEAF_DARK,
                fn=shade(LEAF_DARK, top=1.0, side=0.95, bottom=0.8))
        x += 1.2 + rng.random() * 0.5


def terrace_front(hw, hd, s, width, depth, rng):
    """A cantilevered terrace off the front slab: rounded slab, glass balustrade
    with a white cap rail, and a planter run behind the glass."""
    y0 = hd + 1.2
    rslab(width, depth + 2.4, 1.8, (0, y0 + depth / 2 - 1.2, s), PAPER, radius=2.8, bev=0.2)
    ye = y0 + depth - 0.2
    top = s + 0.9 + 3.0
    pane(-width / 2 + 0.6, width / 2 - 0.6, ye - 0.1, ye + 0.1, s + 0.9, top)
    span(-width / 2 + 0.4, width / 2 - 0.4, ye - 0.18, ye + 0.18, top, top + 0.22, PAPER)
    for sx in (-1, 1):
        pane(sx * (width / 2 - 0.6) - 0.1, sx * (width / 2 - 0.6) + 0.1, y0 + 0.4, ye, s + 0.9, top)
        span(sx * (width / 2 - 0.6) - 0.18, sx * (width / 2 - 0.6) + 0.18, y0 + 0.4, ye + 0.18, top, top + 0.22, PAPER)
    planter_run(-width / 2 + 1.4, width / 2 - 1.4, ye - 0.9, s + 0.9, rng, depth=1.0)


def terrace_side(hw, s, length, depth, rng):
    for sx in (-1, 1):
        x0 = sx * (hw + 1.2)
        rslab(depth + 2.4, length, 1.8, (sx * (hw + 1.2 + depth / 2 - 1.2), 0, s), PAPER, radius=2.8, bev=0.2)
        xe = sx * (hw + 1.2 + depth - 0.2)
        top = s + 0.9 + 3.0
        pane(xe - 0.1, xe + 0.1, -length / 2 + 0.6, length / 2 - 0.6, s + 0.9, top)
        span(xe - 0.18, xe + 0.18, -length / 2 + 0.4, length / 2 - 0.4, top, top + 0.22, PAPER)
        # planters along it: build as a run in X then rotate by building straight in Y
        y = -length / 2 + 1.6
        while y < length / 2 - 1.2:
            span(xe - sx * 1.4, xe - sx * 0.4, y - 0.8, y + 0.8, s + 0.9, s + 1.9, CONCRETE, bev=0.1)
            blob(0.6 + rng.random() * 0.25, (xe - sx * 0.9, y, s + 2.3), [LEAF, LEAF_DARK, LEAF_LIGHT][rng.randrange(3)])
            y += 2.4


def lift_core(x, y, w, d, z0, z1, door_front=True):
    """The roof end of the lift: a rounded white volume, a glass door onto the roof."""
    rslab(w, d, z1 - z0, (x, y, (z0 + z1) / 2), PAPER, radius=1.6, bev=0.2)
    rslab(w + 0.8, d + 0.8, 0.6, (x, y, z1 + 0.3), PAPER, radius=2.0, bev=0.1, fn=roof_shade(MEMBRANE, PAPER))
    if door_front:
        pane(x - 2.4, x + 2.4, y + d / 2 - 0.02, y + d / 2 + 0.18, z0 + 0.1, z0 + 7.6)
        span(x - 2.8, x + 2.8, y + d / 2 - 0.05, y + d / 2 + 0.3, z0 + 7.6, z0 + 8.1, CHARCOAL)
        for sx in (-1, 1):
            span(x + sx * 2.8 - 0.2, x + sx * 2.8 + 0.2, y + d / 2 - 0.05, y + d / 2 + 0.3, z0, z0 + 8.1, CHARCOAL)
        # a slim vertical slot window up the side, it reads as a stair from the street
    pane(x + w / 2 - 0.02, x + w / 2 + 0.18, y - 1.0, y + 1.0, z0 + 1.0, z1 - 1.0)


def solar(w, roof_top, rows=4, y0=2.0):
    for k in range(rows):
        y = y0 + k * 3.6
        box((w * 0.4, 3.0, 0.2), (0, y, roof_top + 1.0), SOLAR, rot=(math.radians(-14), 0, 0),
            fn=shade(SOLAR, top=1.2))
        for sx in (-1, 1):
            span(sx * w * 0.19 - 0.15, sx * w * 0.19 + 0.15, y - 0.2, y + 0.2, roof_top - 0.05, roof_top + 0.9, METAL)


def plant_units(w, d, roof_top):
    for x in (-w / 4, w / 4):
        span(x - 2.5, x + 2.5, -d / 4 - 2, -d / 4 + 2, roof_top - 0.05, roof_top + 2.2, METAL, bev=0.2)
        span(x - 1.6, x + 1.6, -d / 4 - 1.3, -d / 4 + 1.3, roof_top + 2.2, roof_top + 2.5, CHARCOAL, bev=0.05)


def sign_frame(w, hd, roof_top, level):
    """Same geometry and formula as hq.py: CampusArch.skinHQ places the plate there."""
    pwid = min(w - 12, 26)
    plate_c = roof_top + (1.4 if level >= 3 else 0.0) + 1.8
    sy0 = hd - 1.05
    span(-pwid / 2 - 0.4, pwid / 2 + 0.4, sy0 - 0.35, sy0, roof_top - 0.05, plate_c + 2.1, CHARCOAL, bev=0.06)
    for sx in (-1, 1):
        span(sx * (pwid / 2 - 2) - 0.2, sx * (pwid / 2 - 2) + 0.2, sy0 - 2.6, sy0 - 0.35, roof_top - 0.05, roof_top + 0.4, CHARCOAL)
        box((0.35, 0.35, 3.6), (sx * (pwid / 2 - 2), sy0 - 1.45, roof_top + 1.6), CHARCOAL, rot=(math.radians(-38), 0, 0))


# ------------------------------------------------------------------ the building
def build(level):
    L = LEVELS[level]
    w, d, h, R = L["w"], L["d"], L["h"], L["R"]
    hw, hd = w / 2, d / 2
    rng = random.Random(40 + level)
    slabs = H.slabs_for(h)
    roof_bot = h - 0.4
    H.CTX["under"] = [s - 0.9 for s in slabs] + [roof_bot, 11.5]
    ring = plan(hw, hd, R)
    gap = DOOR_W / 2 + 0.8

    # --- plinth and curb
    rslab(w + 6, d + 6, 1.5, (0, 0, 0.21), CONCRETE, radius=R + 3, bev=0.2)
    wall(clip_door(pick(ring, ("F", "CF", "S", "CB")), gap), FLOOR_TOP - 0.05, FLOOR_TOP + 0.6, 1.0, CONCRETE)

    # --- the lobby
    lobby_top = (slabs[0] - 0.9) if slabs else 12.1
    door_top = 11.4
    front = clip_door(pick(ring, ("F", "CF", "S", "CB")), gap)
    for run in chain_split(front):
        glass(run, FLOOR_TOP + 0.6, lobby_top, out=-0.3)
        posts(run, FLOOR_TOP + 0.6, lobby_top, 4.6, out=-0.15)
        # a transom line at door-head height: human scale on a tall lobby
        if lobby_top > door_top + 1.0:
            wall(run, door_top, door_top + 0.35, 0.36, CHARCOAL, out=0.12)
    # the portal: jambs, head, transom glass
    for sx in (-1, 1):
        span(sx * DOOR_W / 2, sx * gap, hd - 0.5, hd + 0.6, FLOOR_TOP - 0.05, lobby_top, PAPER, bev=0.12)
    span(-DOOR_W / 2, DOOR_W / 2, hd - 0.5, hd + 0.6, door_top, door_top + 0.7, CHARCOAL, bev=0.08)
    if lobby_top > door_top + 1.5:
        pane(-DOOR_W / 2, DOOR_W / 2, hd - 0.1, hd + 0.1, door_top + 0.7, lobby_top)
        for a in H.x_runs(-DOOR_W / 2, DOOR_W / 2, 3.5):
            span(a - 0.12, a + 0.12, hd - 0.18, hd + 0.18, door_top + 0.7, lobby_top, CHARCOAL)
    # the back: opaque (the logo wall is behind it) with a glass back door + canopy
    bw = 4.5
    span(-hw + R, -bw, -hd - 0.5, -hd + 0.5, FLOOR_TOP - 0.05, lobby_top, PAPER_WARM, bev=0.1)
    span(bw, hw - R, -hd - 0.5, -hd + 0.5, FLOOR_TOP - 0.05, lobby_top, PAPER_WARM, bev=0.1)
    span(-bw, bw, -hd - 0.5, -hd + 0.5, 10.6, lobby_top, PAPER_WARM, bev=0.1)
    pane(-bw + 0.3, bw - 0.3, -hd - 0.1, -hd + 0.1, FLOOR_TOP + 0.6, 10.3)
    for sx in (-1, 1):
        span(sx * (bw - 0.3), sx * bw, -hd - 0.3, -hd + 0.3, FLOOR_TOP - 0.05, 10.6, CHARCOAL)
    span(-bw, bw, -hd - 0.3, -hd + 0.3, 10.3, 10.6, CHARCOAL)
    rslab(12, 5, 0.6, (0, -hd - 2.6, 11.3), PAPER, radius=1.0, bev=0.12, fn=roof_shade(MEMBRANE, PAPER))

    # --- level 2: the clerestory over the lobby
    if level == 2:
        H.CTX["under"] = [roof_bot, 11.5]
        wall(ring, lobby_top, 14.6, 0.7, SPANDREL, out=0.1)
        glass(ring, 14.6, roof_bot - 0.6)
        posts(ring, 14.6, roof_bot - 0.6, 5.2)
        wall(ring, roof_bot - 0.6, roof_bot, 0.7, CHARCOAL, out=0.1)
        # a charcoal line on top of the clerestory band
        wall(ring, 14.45, 14.6, 0.9, CHARCOAL, out=0.15)

    # --- the storeys above the lobby: slab edge, spandrel, ribbon of glass
    for i, s in enumerate(slabs):
        top = (slabs[i + 1] - 0.9) if i + 1 < len(slabs) else roof_bot
        rslab(w - 0.2, d - 0.2, 1.2, (0, 0, s), FLOORPLATE, radius=R - 0.1, bev=0.0, fn=K.flat(FLOORPLATE))
        ring_slab(hw, hd, R, -0.1, 1.2, s - 0.9, s + 0.9, PAPER)
        # a low top floor (HQ 5's Sky Cafe is 7 studs) gets a low spandrel, or it reads as a basement
        sp_top = s + 0.9 + (2.7 if top - s > 9 else 1.2)
        wall(ring, s + 0.9, sp_top, 0.7, SPANDREL, out=0.2)
        wall(ring, sp_top - 0.12, sp_top, 0.9, CHARCOAL, out=0.25)
        glass(ring, sp_top, top, out=-0.45)
        posts(ring, sp_top, top, 5.6, out=-0.3)

    # --- terraces and the living wall (4 and 5)
    # the terraces stop short of the living wall, which runs up the front-left
    if level == 4:
        terrace_front(hw, hd, 28, w * 0.44, 4.2, rng)
    if level == 5:
        terrace_front(hw, hd, 28, w * 0.5, 4.2, rng)
        terrace_side(hw, 40, d * 0.56, 4.0, rng)
        terrace_front(hw, hd, 52, w * 0.4, 4.2, rng)
    if level >= 4:
        # near the front-left corner (game -X), from the top of the lobby to the roof
        lx0, lx1 = gx(-(hw - R - 1)), gx(-(hw - R - 13))
        living_wall(min(lx0, lx1), max(lx0, lx1), slabs[0] + 1.2, roof_bot - 1.0, hd + 1.5, rng)

    # --- the roof
    over = 3.6 if level == 2 else 2.2
    rslab(w + 2 * over, d + 2 * over, 1.4, (0, 0, roof_bot + 0.7), PAPER, radius=R + over, bev=0.25,
          fn=roof_shade(MEMBRANE, PAPER))
    rslab(w - 0.4, d - 0.4, 0.12, (0, 0, roof_bot - 0.07), CEILING, radius=R - 0.2, bev=0.0, fn=K.flat(CEILING))
    roof_top = roof_bot + 1.4
    # a charcoal reveal where the roof meets the walls
    wall(ring, roof_bot - 0.5, roof_bot, 0.5, CHARCOAL, out=0.35)
    edge = plan(hw + over - 0.5, hd + over - 0.5, R + over - 0.5)
    if level in (3, 4):
        wall(edge, roof_top - 0.05, roof_top + 1.3, 0.6, PAPER, out=-0.3)
        wall(edge, roof_top + 1.3, roof_top + 1.45, 0.7, CHARCOAL, out=-0.3)
        plant_units(w, d, roof_top)
        solar(w, roof_top, rows=4 if level == 3 else 5)
        lift_core(gx(22), -hd + 7, 10, 8, roof_top, roof_top + 8.5)
    if level == 5:
        # THE ROOF GARDEN: the game's Parapet block is the floor, its top is h + 1.6
        deck_top = h + 1.6
        rslab(w + 2 * over - 1.4, d + 2 * over - 1.4, deck_top - roof_top + 0.1, (0, 0, (roof_top + deck_top) / 2),
              DECK, radius=R + over - 0.7, bev=0.05,
              fn=lambda p, n: tuple(min(1.0, c * (1.03 if n.z > 0.5 and int((p.x + 60) / 1.2) % 2 == 0 else 0.97 if n.z > 0.5 else 0.85)) for c in DECK))
        # glass balustrade round the edge with a white cap rail
        rail = plan(hw + over - 1.2, hd + over - 1.2, R + over - 1.2)
        glass(rail, deck_top, deck_top + 3.2)
        wall(rail, deck_top + 3.2, deck_top + 3.45, 0.45, PAPER)
        posts(rail, deck_top, deck_top + 3.2, 7.0, size=(0.2, 0.2), col=PAPER, out=0.0)
        # planters: a ring of troughs inside the rail, clear of the sign frame
        for x0, x1 in ((-hw + 2, -16), (16, hw - 2)):
            planter_run(x0, x1, -hd - over + 3.2, deck_top, rng, depth=1.4, trail=False)
        for sx in (-1, 1):
            y = -hd + 6
            while y < hd - 8:
                span(sx * (hw + over - 3.2) - 0.7, sx * (hw + over - 3.2) + 0.7, y - 2.0, y + 2.0, deck_top, deck_top + 1.1, CONCRETE, bev=0.12)
                blob(1.0 + rng.random() * 0.3, (sx * (hw + over - 3.2), y - 0.8, deck_top + 1.7), LEAF)
                blob(0.9 + rng.random() * 0.3, (sx * (hw + over - 3.2), y + 0.9, deck_top + 1.6), LEAF_DARK)
                y += 6.0
        # a pergola over a lounge (game +X side of centre), slatted shade
        px, py = gx(-20), 2.0
        for ox in (-7, 7):
            for oy in (-5, 5):
                span(px + ox - 0.25, px + ox + 0.25, py + oy - 0.25, py + oy + 0.25, deck_top, deck_top + 7.2, OAK_DARK)
        for oy in (-5, 5):
            span(px - 7.6, px + 7.6, py + oy - 0.3, py + oy + 0.3, deck_top + 7.0, deck_top + 7.6, OAK_DARK)
        for x in H.x_runs(px - 7.4, px + 7.4, 1.1):
            span(x - 0.18, x + 0.18, py - 6.0, py + 6.0, deck_top + 7.6, deck_top + 7.95, OAK)
        # the lift core: its door faces the front, onto the garden
        lift_core(gx(22), -hd + 7, 10, 8, deck_top, deck_top + 9.0)
        plant_units(w * 0.5, d, deck_top)

    # --- the entrance canopy, cantilevered toward the road
    H.CTX["under"] = [11.5]
    rslab(DOOR_W + 10, 7.8, 0.7, (0, hd + 3.6, 11.85), PAPER, radius=2.4, bev=0.12, fn=roof_shade(MEMBRANE, PAPER))
    for sx in (-1, 1):
        cyl(0.32, FLOOR_TOP - 0.3, 11.5, sx * (DOOR_W / 2 + 3.5), hd + 6.4, PAPER)
    sign_frame(w, hd, roof_top, level)


def run(level):
    K.reset()
    H.PARTS["shell"], H.PARTS["glass"] = [], []
    build(level)
    shell = H.finish_mesh("HQv2_%d_Shell" % level, "shell")
    glass_o = H.finish_mesh("HQv2_%d_Glass" % level, "glass")
    objs = [o for o in (shell, glass_o) if o]
    K.preview(os.path.join(OUT, "hqv2_%d_preview.png" % level), objs=objs, size=(1200, 800), elev=18, azim=148)
    K.preview(os.path.join(OUT, "hqv2_%d_street.png" % level), objs=objs, size=(1200, 800), elev=6, azim=195)
    K.export(os.path.join(IMP, "HQv2_%d_Shell.fbx" % level), [shell])
    if glass_o:
        K.export(os.path.join(IMP, "HQv2_%d_Glass.fbx" % level), [glass_o])


if __name__ == "__main__":
    only = [int(a) for a in sys.argv[sys.argv.index("--") + 1:]] if "--" in sys.argv else [2, 3, 4, 5]
    for lv in only:
        run(lv)
    # v4.2: merged straight into game/src/ServerScriptService/HQMeta/V2.lua (Rojo syncs it)
    import metafile
    metafile.write("V2", "blender/hq2.py: the v4.0 HQ meshes (HQv2_<n>_Shell / _Glass), preferred from HQ 2 up", H.META)
    print("HQv2 META", H.META)
