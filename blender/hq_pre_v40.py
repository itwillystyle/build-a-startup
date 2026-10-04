"""hq.py -- PLAN v6 phase V3: the HQ as real architecture (27 Sep 2026).

One visual shell per HQ level, modelled around the EXACT footprint the game
already uses (SiliconCore HQ_LEVELS), so every existing collision part,
interior prop, pad, seat and furniture item keeps working. The game hides the
old part-built walls/glass/mullions (they stay as invisible collision) and
places these meshes instead. If a mesh is not imported, nothing changes.

Per level it writes:
  HQ_<n>_Shell.fbx   opaque architecture, vertex coloured, contact-shaded
  HQ_<n>_Glass.fbx   every pane as one mesh (the game makes it Glass + tint)
  HQ_1_Door.fbx      one sectional garage-door leaf (welded to each door part)
and out/hq_meta.lua: each mesh's bounding-box centre in PLOT-LOCAL studs, which
CampusArch needs because Roblox recentres an imported mesh on its part.

Coordinates. Modelled in Blender units = studs, Z up, the building's FRONT
(the road side, plot-local +Z) on Blender +Y. Measured in Phase W, the FBX
importer lands Blender (x, y, z) at Roblox (-x, z, y); every building here is
mirror-symmetric in X, so only front/back matters, and the game has a
one-constant flip if the first screenshot says otherwise.

Silhouettes (ART.md rule 4 -- tell the level from across the map):
  1 GARAGE          a mid-century flat-roof garage: deep eaves, exposed beam
                    ends, a sectional double door. Where the valley began.
  2 STARTUP OFFICE  one tall glass pavilion under a big floating roof, oak fins
  3 TECH HQ         two stacked slabs (the styleframe): mullioned glass lobby,
                    oak-finned office floor, parapet roof with solar
  4 GLASS TOWER     all glass between thin rounded floor bands, a halo crown
  5 CAMPUS HQ       an oak fin screen over every floor, roof garden, crown

Run:  blender -b --python hq.py
"""
import bpy
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import svkit as K  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Vector  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
IMP = os.path.join(OUT, "IMPORT_HQ")
os.makedirs(IMP, exist_ok=True)

# ------------------------------------------------------------------ palette (ART.md)
PAPER = K.rgb(243, 239, 230)
PAPER_WARM = K.rgb(236, 230, 218)
CONCRETE = K.rgb(207, 198, 182)
OAK = K.rgb(192, 138, 85)
OAK_DARK = K.rgb(132, 92, 60)
INK = K.rgb(30, 37, 48)
CHARCOAL = K.rgb(58, 62, 70)
METAL = K.rgb(176, 178, 182)
MEMBRANE = K.rgb(214, 210, 202)
CEILING = K.rgb(236, 234, 228)
SOLAR = K.rgb(40, 58, 96)
LEAF = K.rgb(96, 150, 78)
LEAF_DARK = K.rgb(72, 118, 62)
WHITE = K.rgb(255, 255, 255)
DOOR = K.rgb(240, 236, 226)
DOOR_WIN = K.rgb(62, 74, 88)

LEVELS = {
    1: dict(name="GARAGE", w=36, d=30, h=14),
    2: dict(name="STARTUP OFFICE", w=52, d=40, h=20),
    3: dict(name="TECH HQ", w=68, d=52, h=28),
    4: dict(name="GLASS TOWER", w=68, d=52, h=44),
    5: dict(name="CAMPUS HQ", w=68, d=52, h=60),
}
DOOR_W = 14          # the level 2+ entrance opening (SiliconCore buildShell)
FLOOR_TOP = 1.0      # GarageFloor top: the building stands on it


def slabs_for(h):
    """SiliconCore's StoreyBand heights for a level (range(16, h-6, 12))."""
    return [y for y in range(16, int(h - 6) + 1, 12) if y <= h - 6] if h >= 28 else []


# ------------------------------------------------------------------ contact shading
# Not a Cycles AO bake: at vertex resolution a bake on big flat walls is blotchy.
# An architect's model reads from three cues, all computed per corner:
# sky light by normal, darkening where a wall meets the ground, and a band of
# shade just under every slab and overhang.
CTX = {"under": []}


def shade(col, top=1.04, side=0.90, bottom=0.72):
    def f(p, n):
        if n.z > 0.5:
            k = top
        elif n.z < -0.5:
            k = bottom
        else:
            k = side
        if n.z < 0.5 and p.z < 3.0:
            k *= 0.80 + 0.20 * max(0.0, p.z) / 3.0
        if abs(n.z) < 0.5:
            for ub in CTX["under"]:
                if ub - 1.8 < p.z <= ub + 0.02:
                    k *= 0.88
                    break
        return tuple(min(1.0, c * k) for c in col)
    return f


def roof_shade(top_col, edge_col):
    """Pale membrane on the top face, the slab colour on its edge, oak soffit below."""
    edge = shade(edge_col)
    under = shade(OAK, bottom=0.86)
    def f(p, n):
        if n.z > 0.5:
            return tuple(min(1.0, c * 1.02) for c in top_col)
        if n.z < -0.5:
            return under(p, n)
        return edge(p, n)
    return f


# ------------------------------------------------------------------ primitives
PARTS = {"shell": [], "glass": []}


def _finish(o, col, bev, group, fn=None):
    if bev > 0:
        K.bevel(o, width=bev, segments=1, angle=40)
        K.apply_mods(o)
    K.paint(o, fn or shade(col))
    PARTS[group].append(o)
    return o


def box(size, loc, col, bev=0.0, group="shell", fn=None, rot=None):
    """size = (x, y, z) in Blender axes: x across, y front-back, z up."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object
    o.scale = size
    if rot:
        o.rotation_euler = rot
    bpy.ops.object.transform_apply(scale=True, rotation=True, location=False)
    return _finish(o, col, bev, group, fn)


def span(x0, x1, y0, y1, z0, z1, col, bev=0.0, group="shell", fn=None):
    """A box by its extents (the natural way to lay out facades)."""
    return box((abs(x1 - x0), abs(y1 - y0), abs(z1 - z0)),
               ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), col, bev, group, fn)


def rslab(w, d, h, loc, col, radius=2.0, bev=0.15, group="shell", fn=None, segs=6):
    """Rounded-rectangle slab: radius on the vertical corners, soft bevel elsewhere."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1)
    for v in bm.verts:
        v.co = Vector((v.co.x * w, v.co.y * d, v.co.z * h))
    vert_edges = [e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) > h * 0.5]
    if radius > 0:
        bmesh.ops.bevel(bm, geom=vert_edges, offset=min(radius, w / 2 - 0.01, d / 2 - 0.01),
                        offset_type="OFFSET", segments=segs, profile=0.5, affect="EDGES")
    o = K.mesh_obj("slab", bm)
    o.location = loc
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.transform_apply(location=True)
    o.select_set(False)
    return _finish(o, col, bev, group, fn)


def cyl(r, z0, z1, x, y, col, verts=12, group="shell"):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=z1 - z0, vertices=verts, location=(x, y, (z0 + z1) / 2))
    o = bpy.context.active_object
    return _finish(o, col, 0.0, group)


def blob(r, loc, col, sub=1):
    bpy.ops.mesh.primitive_ico_sphere_add(radius=r, subdivisions=sub, location=loc)
    o = bpy.context.active_object
    o.scale = (1.0, 1.0, 0.75)
    bpy.ops.object.transform_apply(scale=True)
    return _finish(o, col, 0.0, "shell", shade(col, top=1.06, side=0.9, bottom=0.7))


def pane(x0, x1, y0, y1, z0, z1):
    """Glass: 0.2 thick so it has two faces (Roblox renders meshes one-sided)."""
    return span(x0, x1, y0, y1, z0, z1, WHITE, group="glass", fn=K.flat(WHITE))


# ------------------------------------------------------------------ facade kit (level 2+)
def x_runs(x0, x1, every):
    """Evenly spaced positions strictly inside (x0, x1), about `every` apart."""
    n = max(1, int(round((x1 - x0) / every)))
    return [x0 + (x1 - x0) * k / n for k in range(1, n)]


def glass_face(axis, pos, a0, a1, z0, z1, out_sign, fins=None, mullions=None, fin_col=OAK):
    """A run of glass on one face. axis 'x' = the face spans X at y=pos (front/back);
    axis 'y' = spans Y at x=pos (sides). Fins stand outside the glass, mullions on it."""
    t = 0.1
    if axis == "x":
        pane(a0, a1, pos - t, pos + t, z0, z1)
        for a in (x_runs(a0, a1, fins) if fins else []):
            span(a - 0.22, a + 0.22, pos, pos + out_sign * 1.1, z0, z1, fin_col, bev=0.06)
        for a in (x_runs(a0, a1, mullions) if mullions else []):
            span(a - 0.14, a + 0.14, pos - 0.18, pos + 0.18, z0, z1, CHARCOAL)
    else:
        pane(pos - t, pos + t, a0, a1, z0, z1)
        for a in (x_runs(a0, a1, fins) if fins else []):
            span(pos, pos + out_sign * 1.1, a - 0.22, a + 0.22, z0, z1, fin_col, bev=0.06)
        for a in (x_runs(a0, a1, mullions) if mullions else []):
            span(pos - 0.18, pos + 0.18, a - 0.14, a + 0.14, z0, z1, CHARCOAL)


def build_office(level):
    L = LEVELS[level]
    w, d, h = L["w"], L["d"], L["h"]
    hw, hd = w / 2, d / 2
    slabs = slabs_for(h)
    roof_bot = h - 0.4
    CTX["under"] = [s - 0.9 for s in slabs] + [roof_bot, 11.5]

    # storeys: (bottom, top) of each band of glass
    cuts = [FLOOR_TOP + 0.6] + [s + 0.9 for s in slabs]
    tops = [s - 0.9 for s in slabs] + [roof_bot]
    storeys = list(zip(cuts, tops))

    # --- plinth: the architect's-model base the building stands on
    rslab(w + 6, d + 6, 1.5, (0, 0, 0.21), CONCRETE, radius=3.0, bev=0.2)
    # curb under the glass on every face (the old 3-stud FrontWall reads as this)
    for sx in (-1, 1):
        span(sx * (hw - 0.5), sx * (hw + 0.5), -hd, hd, FLOOR_TOP - 0.05, FLOOR_TOP + 0.6, CONCRETE, bev=0.1)
    span(-hw, -DOOR_W / 2 - 0.8, hd - 0.5, hd + 0.5, FLOOR_TOP - 0.05, FLOOR_TOP + 0.6, CONCRETE, bev=0.1)
    span(DOOR_W / 2 + 0.8, hw, hd - 0.5, hd + 0.5, FLOOR_TOP - 0.05, FLOOR_TOP + 0.6, CONCRETE, bev=0.1)

    # --- corner piers, full height
    for sx in (-1, 1):
        for sy in (-1, 1):
            span(sx * (hw - 1.2), sx * (hw + 1.0), sy * (hd - 1.2), sy * (hd + 1.0), FLOOR_TOP - 0.05, roof_bot + 0.1, PAPER, bev=0.25)

    # --- floor bands: rounded slab edges wrapping the building at every storey
    for s in slabs:
        rslab(w + 2.2, d + 2.2, 1.8, (0, 0, s), PAPER, radius=1.6, bev=0.2)

    fins_every = 3.6
    for i, (z0, z1) in enumerate(storeys):
        ground = (i == 0)
        # which cladding this storey gets, per level
        if level == 2:
            side_fins, side_mull, front_fins, front_mull = fins_every, None, fins_every, None
        elif level == 3:
            side_fins, side_mull = (None, 4.0) if ground else (fins_every, None)
            front_fins, front_mull = (None, 4.0) if ground else (fins_every, None)
        elif level == 4:
            side_fins, side_mull, front_fins, front_mull = None, 4.0, None, 4.0
        else:  # 5: plain glass behind a full-height oak screen (built after the storeys)
            side_fins, side_mull, front_fins, front_mull = None, None, None, None
        # sides
        for sx in (-1, 1):
            glass_face("y", sx * hw, -hd + 1.2, hd - 1.2, z0, z1, sx, fins=side_fins, mullions=side_mull)
        # front
        if ground:
            door_top = 11.4
            glass_face("x", hd, -hw + 1.2, -DOOR_W / 2 - 0.8, z0, z1, 1, fins=front_fins, mullions=front_mull)
            glass_face("x", hd, DOOR_W / 2 + 0.8, hw - 1.2, z0, z1, 1, fins=front_fins, mullions=front_mull)
            # the portal: jambs, a head, and a glass transom up to the storey top
            for sx in (-1, 1):
                span(sx * DOOR_W / 2, sx * (DOOR_W / 2 + 0.8), hd - 0.5, hd + 0.6, FLOOR_TOP - 0.05, z1, PAPER, bev=0.12)
            span(-DOOR_W / 2, DOOR_W / 2, hd - 0.5, hd + 0.6, door_top, door_top + 0.7, CHARCOAL, bev=0.08)
            if z1 > door_top + 1.5:
                pane(-DOOR_W / 2, DOOR_W / 2, hd - 0.1, hd + 0.1, door_top + 0.7, z1)
                for a in x_runs(-DOOR_W / 2, DOOR_W / 2, 3.5):
                    span(a - 0.12, a + 0.12, hd - 0.18, hd + 0.18, door_top + 0.7, z1, CHARCOAL)
            # a transom bar at door-head height across the whole front
            span(-hw + 1.2, -DOOR_W / 2 - 0.8, hd - 0.18, hd + 0.2, door_top, door_top + 0.35, CHARCOAL)
            span(DOOR_W / 2 + 0.8, hw - 1.2, hd - 0.18, hd + 0.2, door_top, door_top + 0.35, CHARCOAL)
        else:
            glass_face("x", hd, -hw + 1.2, hw - 1.2, z0, z1, 1, fins=front_fins, mullions=front_mull)
        # back: an opaque ground floor (the logo wall is behind it) with a glass door
        if ground:
            bw = 4.5
            span(-hw + 1.2, -bw, -hd - 0.5, -hd + 0.5, z0 - 0.6, z1, PAPER_WARM, bev=0.12)
            span(bw, hw - 1.2, -hd - 0.5, -hd + 0.5, z0 - 0.6, z1, PAPER_WARM, bev=0.12)
            span(-bw, bw, -hd - 0.5, -hd + 0.5, 10.6, z1, PAPER_WARM, bev=0.12)
            pane(-bw + 0.3, bw - 0.3, -hd - 0.1, -hd + 0.1, z0, 10.3)
            for sx in (-1, 1):
                span(sx * (bw - 0.3), sx * bw, -hd - 0.3, -hd + 0.3, z0 - 0.6, 10.6, CHARCOAL)
            span(-bw, bw, -hd - 0.3, -hd + 0.3, 10.3, 10.6, CHARCOAL)
            span(-0.12, 0.12, -hd - 0.25, -hd + 0.25, z0, 10.3, CHARCOAL)
            # back canopy over it
            rslab(12, 5, 0.6, (0, -hd - 2.6, 11.3), PAPER, radius=1.0, bev=0.12,
                  fn=roof_shade(MEMBRANE, PAPER))
        else:
            glass_face("x", -hd, -hw + 1.2, hw - 1.2, z0, z1, -1,
                       fins=front_fins or fins_every, mullions=None)

    if level == 5:
        # the oak screen: one fin per bay from the plinth to the roof, standing
        # 1.3 off the glass so the floor bands pass behind it (23k tris as
        # per-storey bevelled fins; ~1k like this, and it reads as one gesture)
        z0, z1 = FLOOR_TOP + 0.6, roof_bot
        for sx in (-1, 1):
            for a in x_runs(-hd + 1.2, hd - 1.2, 3.0):
                span(sx * (hw + 1.3), sx * (hw + 2.0), a - 0.2, a + 0.2, z0, z1, OAK)
        for sy in (-1, 1):
            for a in x_runs(-hw + 1.2, hw - 1.2, 3.0):
                if sy > 0 and abs(a) < DOOR_W / 2 + 2.5:
                    continue      # keep the entrance open
                span(a - 0.2, a + 0.2, sy * (hd + 1.3), sy * (hd + 2.0), z0, z1, OAK)

    # --- the roof: a floating slab, oak soffit, pale ceiling inside
    over = 3.0 if level == 2 else 2.2
    rslab(w + 2 * over, d + 2 * over, 1.4, (0, 0, roof_bot + 0.7), PAPER, radius=3.0 + over / 2, bev=0.25,
          fn=roof_shade(MEMBRANE, PAPER))
    span(-hw + 0.6, hw - 0.6, -hd + 0.6, hd - 0.6, roof_bot - 0.12, roof_bot - 0.02, CEILING, fn=K.flat(CEILING))
    # a charcoal reveal line where the roof meets the walls
    rslab(w + 0.6, d + 0.6, 0.5, (0, 0, roof_bot - 0.25), CHARCOAL, radius=1.0, bev=0.0)
    roof_top = roof_bot + 1.4

    if level >= 3:
        # parapet on the roof edge
        pw, pd = w + 2 * over - 1.0, d + 2 * over - 1.0
        for sy in (-1, 1):
            span(-pw / 2, pw / 2, sy * (pd / 2 - 0.6), sy * pd / 2, roof_top - 0.05, roof_top + 1.3, PAPER, bev=0.12)
        for sx in (-1, 1):
            span(sx * (pw / 2 - 0.6), sx * pw / 2, -pd / 2, pd / 2, roof_top - 0.05, roof_top + 1.3, PAPER, bev=0.12)

    # --- rooftop plant, behind the sign
    for x in (-w / 4, w / 4):
        span(x - 2.5, x + 2.5, -d / 4 - 2, -d / 4 + 2, roof_top - 0.05, roof_top + 2.4, METAL, bev=0.2)
        span(x - 1.6, x + 1.6, -d / 4 - 1.3, -d / 4 + 1.3, roof_top + 2.4, roof_top + 2.7, CHARCOAL, bev=0.05)
    if level in (3, 4):
        for k in range(4):
            y = 2 + k * 3.6
            box((w * 0.42, 3.0, 0.2), (0, y, roof_top + 1.0), SOLAR, rot=(math.radians(-14), 0, 0),
                fn=shade(SOLAR, top=1.2))
            span(-w * 0.2, -w * 0.2 + 0.3, y - 0.2, y + 0.2, roof_top - 0.05, roof_top + 0.9, METAL)
            span(w * 0.2 - 0.3, w * 0.2, y - 0.2, y + 0.2, roof_top - 0.05, roof_top + 0.9, METAL)
    if level == 5:
        # a roof garden: concrete planters of shrubs, a pergola, a deck
        span(-w * 0.32, w * 0.32, -2, hd - 4, roof_top - 0.05, roof_top + 0.2, OAK, fn=shade(OAK, top=0.98))
        rng = random.Random(5)
        for k in range(6):
            x = -w * 0.3 + k * (w * 0.6) / 5
            for y in (-5.0, hd - 6.0):      # the front row stays clear of the sign braces
                span(x - 2.4, x + 2.4, y - 1.2, y + 1.2, roof_top - 0.05, roof_top + 1.2, CONCRETE, bev=0.15)
                blob(1.3 + rng.random() * 0.4, (x - 0.9, y, roof_top + 1.9), LEAF)
                blob(1.1 + rng.random() * 0.4, (x + 1.0, y + 0.1, roof_top + 1.8), LEAF_DARK)
        for x in (-8, 8):
            for y in (2, 12):
                span(x - 0.2, x + 0.2, y - 0.2, y + 0.2, roof_top, roof_top + 5, OAK)
        for y in x_runs(0, 14, 1.4):
            span(-9, 9, y - 0.15, y + 0.15, roof_top + 5, roof_top + 5.4, OAK)

    if level >= 4:
        # the crown: a floating halo slab on slim posts -- the silhouette from across the map
        ch = roof_top + (7.5 if level == 4 else 9.0)    # clear of the raised name plate and its frame
        hw2, hd2 = w / 2 - 2, d / 2 - 2
        for sx in (-1, 1):
            for sy in (-1, 1):
                span(sx * hw2 - 0.6, sx * hw2 + 0.6, sy * hd2 - 0.6, sy * hd2 + 0.6, roof_top, ch, PAPER, bev=0.1)
        # a thick rounded ring, not a rail: it has to read from the street at 150 studs
        for sy in (-1, 1):
            span(-hw2 - 1.2, hw2 + 1.2, sy * hd2 - 1.3, sy * hd2 + 1.3, ch, ch + 1.6, PAPER, bev=0.3)
        for sx in (-1, 1):
            span(sx * hw2 - 1.3, sx * hw2 + 1.3, -hd2 - 1.2, hd2 + 1.2, ch, ch + 1.6, PAPER, bev=0.3)
        # a charcoal shadow line under it, so it floats
        for sy in (-1, 1):
            span(-hw2 - 1.0, hw2 + 1.0, sy * hd2 - 1.0, sy * hd2 + 1.0, ch - 0.3, ch, CHARCOAL)
        for sx in (-1, 1):
            span(sx * hw2 - 1.0, sx * hw2 + 1.0, -hd2 - 1.0, hd2 + 1.0, ch - 0.3, ch, CHARCOAL)

    # --- the entrance canopy, cantilevered toward the road on two slim columns
    CTX["under"] = [11.5]
    rslab(DOOR_W + 8, 7.4, 0.7, (0, hd + 3.4, 11.85), PAPER, radius=1.2, bev=0.12,
          fn=roof_shade(MEMBRANE, PAPER))
    for sx in (-1, 1):
        cyl(0.32, FLOOR_TOP - 0.3, 11.5, sx * (DOOR_W / 2 + 3), hd + 6.2, PAPER)

    # --- the sign stand the name plate sits on (the plate itself is a game part:
    # g(0, h + 2.2, d/2 - 0.8), 26 x 3.4 x 0.5; this frame stands just behind it)
    # the game raises the plate so it clears the parapet: centre = roof_top + parapet + 1.8
    # (CampusArch.skinHQ uses the same formula)
    pwid = min(w - 12, 26)
    plate_c = roof_top + (1.4 if level >= 3 else 0.0) + 1.8
    sy0 = hd - 1.05
    span(-pwid / 2 - 0.4, pwid / 2 + 0.4, sy0 - 0.35, sy0, roof_top - 0.05, plate_c + 2.1, CHARCOAL, bev=0.06)
    for sx in (-1, 1):
        span(sx * (pwid / 2 - 2) - 0.2, sx * (pwid / 2 - 2) + 0.2, sy0 - 2.6, sy0 - 0.35, roof_top - 0.05, roof_top + 0.4, CHARCOAL)
        # a brace from the roof up the back of the frame
        box((0.35, 0.35, 3.6), (sx * (pwid / 2 - 2), sy0 - 1.45, roof_top + 1.6), CHARCOAL,
            rot=(math.radians(-38), 0, 0))


# ------------------------------------------------------------------ level 1: the garage
def build_garage():
    L = LEVELS[1]
    w, d, h = L["w"], L["d"], L["h"]
    hw, hd = w / 2, d / 2
    CTX["under"] = [h - 0.9, 11.0]
    # walls: stucco, a concrete base course, oak corner boards
    t = 0.5
    win_y0, win_y1 = 6.2, 9.8
    for sx in (-1, 1):
        x0, x1 = sx * (hw - t), sx * (hw + t)
        # a window in the middle of each side wall
        span(x0, x1, -hd - t, -2.8, 0, h, PAPER_WARM)
        span(x0, x1, 2.8, hd + t, 0, h, PAPER_WARM)
        span(x0, x1, -2.8, 2.8, 0, win_y0, PAPER_WARM)
        span(x0, x1, -2.8, 2.8, win_y1, h, PAPER_WARM)
        pane(sx * hw - 0.1, sx * hw + 0.1, -2.8, 2.8, win_y0, win_y1)
        # trim around it, proud of the wall
        for yy in (-2.8, 2.8):
            span(sx * (hw + t) - 0.2 * sx, sx * (hw + t) + 0.25 * sx, yy - 0.3, yy + 0.3, win_y0 - 0.3, win_y1 + 0.3, PAPER)
        span(sx * (hw + t) - 0.2 * sx, sx * (hw + t) + 0.35 * sx, -3.1, 3.1, win_y0 - 0.45, win_y0, PAPER)
        span(sx * (hw + t) - 0.2 * sx, sx * (hw + t) + 0.25 * sx, -3.1, 3.1, win_y1, win_y1 + 0.3, PAPER)
        span(sx * hw - 0.08, sx * hw + 0.08, -0.08, 0.08, win_y0, win_y1, PAPER)
    # back wall, one window
    span(-hw - t, -3.5, -hd - t, -hd + t, 0, h, PAPER_WARM)
    span(3.5, hw + t, -hd - t, -hd + t, 0, h, PAPER_WARM)
    span(-3.5, 3.5, -hd - t, -hd + t, 0, win_y0, PAPER_WARM)
    span(-3.5, 3.5, -hd - t, -hd + t, win_y1, h, PAPER_WARM)
    pane(-3.5, 3.5, -hd - 0.1, -hd + 0.1, win_y0, win_y1)
    span(-3.8, 3.8, -hd - t - 0.35, -hd - t + 0.2, win_y0 - 0.45, win_y0, PAPER)
    span(-3.8, 3.8, -hd - t - 0.25, -hd - t + 0.2, win_y1, win_y1 + 0.3, PAPER)
    for xx in (-3.5, 3.5):
        span(xx - 0.3, xx + 0.3, -hd - t - 0.25, -hd - t + 0.2, win_y0, win_y1, PAPER)
    # front: jambs and the header over the double door (the doors are HQ_1_Door)
    for sx in (-1, 1):
        span(sx * 17.85, sx * (hw + t), hd - t, hd + t, 0, 11.0, PAPER_WARM)
    span(-hw - t, hw + t, hd - t, hd + t, 11.0, h, PAPER_WARM)
    # a slim door stop frame, the colour of the trim
    for sx in (-1, 1):
        span(sx * 17.75, sx * 18.0, hd + t - 0.1, hd + t + 0.15, 0, 11.0, PAPER)
    span(-18.0, 18.0, hd + t - 0.1, hd + t + 0.15, 10.85, 11.1, PAPER)
    # base course and corner boards
    span(-hw - t - 0.15, hw + t + 0.15, -hd - t - 0.15, -hd - t + 0.05, 0, 1.0, CONCRETE)
    for sx in (-1, 1):
        span(sx * (hw + t) - 0.05 * sx, sx * (hw + t + 0.15), -hd - t - 0.15, hd + t, 0, 1.0, CONCRETE)
        for sy in (-1, 1):
            span(sx * (hw + t) - 0.6 * sx, sx * (hw + t + 0.2), sy * (hd + t) - 0.6 * sy, sy * (hd + t + 0.2), 1.0, h, OAK, bev=0.05)
    # wall lamps either side of the door
    for sx in (-1, 1):
        span(sx * 19.6 - 0.35, sx * 19.6 + 0.35, hd + t, hd + t + 0.35, 8.2, 9.6, INK, bev=0.05)
        span(sx * 19.6 - 0.25, sx * 19.6 + 0.25, hd + t + 0.35, hd + t + 0.75, 8.4, 9.4, K.rgb(255, 222, 160),
             fn=K.flat(K.rgb(255, 226, 170)))
    # the roof: a flat Eichler roof, deep eaves, exposed beam ends
    over = 3.0
    CTX["under"] = [h - 0.9]
    rslab(w + 2 * over, d + 2 * over, 1.1, (0, 0, h + 0.55), OAK_DARK, radius=0.8, bev=0.1,
          fn=roof_shade(MEMBRANE, OAK_DARK))
    span(-hw + t, hw - t, -hd + t, hd - t, h - 0.08, h - 0.02, CEILING, fn=K.flat(CEILING))
    y = -hd + 1.6
    while y < hd - 1.0:
        span(-hw - over + 0.5, hw + over - 0.5, y - 0.25, y + 0.25, h - 0.9, h, OAK_DARK, bev=0.05)
        y += 3.2
    # a roof vent and a satellite dish: somebody lives in here, or at least works
    span(5, 8, -6, -3, h + 1.05, h + 2.2, METAL, bev=0.15)
    cyl(0.12, h + 1.05, h + 2.6, -8, -9, INK, verts=8)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1.1, segments=12, ring_count=6, location=(-8, -8.7, h + 3.1))
    dish = bpy.context.active_object
    dish.scale = (1, 0.35, 1)
    dish.rotation_euler = (math.radians(30), 0, 0)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    _finish(dish, PAPER, 0.0, "shell")


def build_door():
    """One sectional door leaf, 18.2 x 11 x 0.5, centred on the origin (the game
    welds one to each door part and fades it out as the door rolls up)."""
    W, H = 18.2, 11.0
    CTX["under"] = []
    span(-W / 2, W / 2, -0.12, 0.12, 0.05 - H / 2, H / 2, CHARCOAL)
    sec = (H - 0.3) / 4
    for i in range(4):
        z0 = -H / 2 + 0.15 + i * sec
        span(-W / 2 + 0.05, W / 2 - 0.05, -0.2, 0.2, z0 + 0.04, z0 + sec - 0.04, DOOR, bev=0.05)
        for k in range(4):
            x0 = -W / 2 + 0.6 + k * (W - 1.2) / 4
            x1 = x0 + (W - 1.2) / 4 - 0.4
            if i == 3:
                span(x0, x1, 0.18, 0.26, z0 + 0.45, z0 + sec - 0.45, DOOR_WIN, fn=K.flat(DOOR_WIN))
            else:
                span(x0, x1, 0.18, 0.26, z0 + 0.4, z0 + sec - 0.4, DOOR, bev=0.03)
    span(-2.0, 2.0, 0.2, 0.34, -H / 2 + 1.2, -H / 2 + 1.5, INK)


# ------------------------------------------------------------------ export
META = {}


def bbox(o):
    mins = [1e9] * 3
    maxs = [-1e9] * 3
    for v in o.data.vertices:
        c = o.matrix_world @ v.co
        for i in range(3):
            mins[i] = min(mins[i], c[i])
            maxs[i] = max(maxs[i], c[i])
    return mins, maxs


def finish_mesh(name, group):
    objs = PARTS[group]
    if not objs:
        return None
    o = K.join(objs, name)
    PARTS[group] = []
    mn, mx = bbox(o)
    c = [(mn[i] + mx[i]) / 2 for i in range(3)]
    s = [mx[i] - mn[i] for i in range(3)]
    # Blender (x, y, z) -> plot-local Roblox (-x, z, y)
    META[name] = dict(c=(-c[0], c[2], c[1]), s=(s[0], s[2], s[1]), tris=K.tris(o))
    return o


def run(level):
    K.reset()
    PARTS["shell"], PARTS["glass"] = [], []
    if level == 1:
        build_garage()
    else:
        build_office(level)
    shell = finish_mesh("HQ_%d_Shell" % level, "shell")
    glass = finish_mesh("HQ_%d_Glass" % level, "glass")
    objs = [o for o in (shell, glass) if o]
    K.preview(os.path.join(OUT, "hq_%d_preview.png" % level), objs=objs, size=(1100, 800), elev=16, azim=148)
    K.export(os.path.join(IMP, "HQ_%d_Shell.fbx" % level), [shell])
    if glass:
        K.export(os.path.join(IMP, "HQ_%d_Glass.fbx" % level), [glass])
    if level == 1:
        K.reset()
        PARTS["shell"] = []
        build_door()
        door = finish_mesh("HQ_1_Door", "shell")
        K.preview(os.path.join(OUT, "hq_1_door_preview.png"), objs=[door], size=(900, 600), elev=5, azim=172)
        K.export(os.path.join(IMP, "HQ_1_Door.fbx"), [door])


only = [int(a) for a in sys.argv[sys.argv.index("--") + 1:]] if "--" in sys.argv else [1, 2, 3, 4, 5]
for lv in only:
    run(lv)

with open(os.path.join(OUT, "hq_meta.lua"), "w") as f:
    f.write("-- generated by blender/hq.py: plot-local bbox centre and size of each HQ mesh\n")
    f.write("local HQ_MESH = {\n")
    for k in sorted(META):
        m = META[k]
        f.write("\t%s = { c = Vector3.new(%.3f, %.3f, %.3f), s = Vector3.new(%.3f, %.3f, %.3f) },  -- %d tris\n"
                % (k, m["c"][0], m["c"][1], m["c"][2], m["s"][0], m["s"][1], m["s"][2], m["tris"]))
    f.write("}\n")
print("HQ META", META)
