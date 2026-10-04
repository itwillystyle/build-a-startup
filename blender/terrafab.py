"""terrafab.py -- the game-ready mesh kit for THE TERRAFAB, path 2 of 3.

Same skeleton as the Wafers (same storey height, same 100 levels, same deck
positions, same lift core, same 8 segments per storey) so the economy never
forks. Only the skin changes. It emits the SAME 40 piece names with a T_
prefix, so Wafers.lua can clone T_Seg_2 wherever it clones W_Seg_2.

Everything style-neutral is imported from wafers.py rather than copied: the
lift core, its cap, the bridge, the lantern, the mast. A lift is a lift.

THE RESEARCH (see CONCEPTS-THREE-PATHS.md):
A semiconductor fab is four stacked levels -- fan deck on top, cleanroom,
clean subfab, utility. The cleanroom is column-free under long-span trusses,
and the plan is "bay and chase": parallel tool bays either side of a central
service corridor. There are essentially no windows, because a cleanroom
cannot have them; the only glazing is a clerestory strip at the perimeter
office band.

Intel's Arizona site runs 30 MILES OF OVERHEAD TRACK moving wafers between
buildings. That track is this path's signature: it rides outside the bays,
it is the only part of the building that moves, and no Roblox tycoon has one.

So against the Wafers, piece by piece:
  Seg      curved glass facade  ->  flat clad bays, louvre bands, clerestory strip
  Deck     garden + running track -> FAN DECK: grille, plant units, pipe runs
  DeckCols columns              ->  exposed long-span trusses
  Roof     roof garden          ->  the final fan deck
  Pav      founder pavilion     ->  the control room, glazed, looking down the track
  Halo     gold ring            ->  THE OVERHEAD WAFER TRACK, with carriers on it

Run:   blender -b --python blender/terrafab.py
       blender -b --python blender/terrafab.py -- only=T_Seg_2
Out:   out/IMPORT_TERRAFAB/<name>.fbx
       game/src/ServerScriptService/HQMeta/Terrafab.lua
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import svkit as K  # noqa: E402
import wafers as W  # noqa: E402  (guarded: importing it does not export the Wafers kit)

MB = W.MB
band, obox, rbox, prism = W.band, W.obox, W.rbox, W.prism
glass_band, thick_wall, mullions = W.glass_band, W.thick_wall, W.mullions
door_frame, seg_angles, rails = W.door_frame, W.seg_angles, W.rails
P, v3 = W.P, W.v3

H, SLAB, DEPTH = W.H, W.SLAB, W.DEPTH
FLOOR_TOP, SILL, CEIL0, CEIL1, OVH = W.FLOOR_TOP, W.SILL, W.CEIL0, W.CEIL1, W.OVH
DECK_SURF, RAIL_H = W.DECK_SURF, W.RAIL_H
LOBBY_W, LOBBY_H, DOOR_W, DOOR_H = W.LOBBY_W, W.LOBBY_H, W.DOOR_W, W.DOOR_H
LANTERN_H, MAST_H = W.LANTERN_H, W.MAST_H
WAFER = W.WAFER
RING40, RING20 = W.RING40, W.RING20

# THE SHAPE. The first build of this path came out as "the Wafers with stripes":
# same smooth cylinder, different texture. The fix is one number. A Wafers
# segment is 5 facets across its 45 degrees, so the ring reads as a circle; a
# Terrafab segment is ONE facet, so the same skeleton reads as an inscribed
# OCTAGON -- flat machined faces meeting at hard corners. That is the honest
# shape for a building of parallel tool bays, and it is what makes the two
# paths read as different buildings from the plaza rather than two textures.
FAB_PH = W.angles(-22.5, 22.5, 1)        # one flat chord per segment
RING8 = W.angles(4.5, 364.5, 8)          # decks and roof follow the same octagon


def seg_angles():
    return FAB_PH

OUT = os.path.join(HERE, "out", "IMPORT_TERRAFAB")
os.makedirs(OUT, exist_ok=True)

# ---------------------------------------------------------------- palette
# A fab is white panel, raw steel and anodised grey. The one warm colour in
# the whole building is the track, because the track is what you look at.
rgb = K.rgb
PANEL = rgb(238, 238, 234)          # the white metal rainscreen
PANEL_D = rgb(214, 216, 214)        # its shadowed returns
STEEL = rgb(176, 182, 188)
STEEL_D = rgb(138, 146, 154)
ANOD = rgb(96, 102, 110)            # anodised grey: louvres, plant
DUCT = rgb(158, 166, 174)
GRILLE = rgb(120, 128, 136)
TRACK_C = rgb(236, 170, 70)         # the overhead track -- the signature colour
TRACK_D = rgb(196, 134, 48)
CARRIER = rgb(246, 246, 248)        # the FOUPs riding it
PAPER = W.PAPER
CHARCOAL = W.CHARCOAL
FLOOR = W.FLOOR
CEILING = W.CEILING
ROOF = W.ROOF

# clerestory: the only glass on a fab bay, a strip under the ceiling
CLERE0, CLERE1 = 9.1, CEIL0


# ------------------------------------------------------------------ helpers
def louvres(mb, rho0, rho1, ph, z0, z1, n=5):
    """Horizontal service banding. A fab has no windows, so the facade is read
    by its louvre courses -- the equivalent of a cornice line."""
    for i in range(n):
        t = (i + 0.5) / n
        z = z0 + (z1 - z0) * t
        band(mb, rho0, rho1, z, z + 1.05, ph, dict(t=ANOD, b=ANOD, o=ANOD, i=ANOD, c=ANOD), "tboi")


def plant_row(mb, rho0, rho1, ph, z, count=6, hgt=3.4):
    """Air handlers on the fan deck. Boxy on purpose: this is the one place on
    the building where ugly machinery is the point."""
    a0, a1 = ph[0], ph[-1]
    for i in range(count):
        t0 = a0 + (a1 - a0) * (i + 0.18) / count
        t1 = a0 + (a1 - a0) * (i + 0.82) / count
        sub = W.angles(t0, t1, 2)
        band(mb, rho0, rho1, z, z + hgt, sub, dict(t=DUCT, b=ANOD, o=ANOD, i=ANOD, c=ANOD), "tboi", "se")
        band(mb, rho0 + 0.6, rho1 - 0.6, z + hgt, z + hgt + 0.5, sub, dict(t=GRILLE, o=GRILLE, i=GRILLE), "toi")


def pipe_run(mb, rho, ph, z, r=0.5, col=DUCT):
    band(mb, rho - r, rho + r, z, z + 2 * r, ph, dict(t=col, b=col, o=col, i=col, c=col), "tboi")


# ------------------------------------------------------------------ 1. the bay
def build_segment(w, variant):
    """A tool bay. Flat clad wall, louvre courses, one clerestory strip.

    The Wafers segment is a glass box; this is its opposite, and that contrast
    is the whole reason the path exists. The only glazing is the clerestory,
    which is also what makes the inside readable at night.
    """
    r = WAFER[w][2]
    rin = r - DEPTH
    ph = seg_angles()
    unders = [CEIL0] + ([W.CANOPY_Z] if variant == "lobby" else [])
    mb = MB(floors=[FLOOR_TOP], unders=unders)
    gl = MB()

    # slabs. A fab floor is a deep waffle slab on close columns, so the soffit
    # reads heavier than the Wafers' oak one.
    band(mb, rin - OVH, r + OVH, 0.0, SLAB, ph,
         dict(t=FLOOR, b=STEEL_D, o=PANEL_D, i=PANEL_D, c=PANEL_D), "tboi", "se")
    band(mb, rin - OVH, r + OVH, CEIL0, CEIL1, ph,
         dict(t=ROOF, b=CEILING, o=PANEL_D, i=PANEL_D, c=PANEL_D), "tboi", "se")

    op_out = op_in = None
    if variant == "lobby":
        op_out = dict(x=(-LOBBY_W / 2, LOBBY_W / 2), z=FLOOR_TOP + LOBBY_H, y=1)
        op_in = dict(op_out)
    elif variant == "bridge":
        op_in = dict(x=(-DOOR_W / 2, DOOR_W / 2), z=FLOOR_TOP + DOOR_H, y=1)

    # OUTER: solid rainscreen floor-to-clerestory, then the glass strip
    thick_wall(mb, r - 0.7, r, FLOOR_TOP, CLERE0, ph, PANEL, op_out)
    louvres(mb, r - 0.9, r + 0.14, ph, FLOOR_TOP + 1.6, CLERE0 - 1.2, n=2)
    glass_band(gl, r - 0.35, CLERE0, CLERE1, ph, None)
    mullions(mb, r - 0.7, r - 0.05, ph, CLERE0, CLERE1, None)

    # INNER (chase side): service wall. The chase is where the pipes live, so
    # the courtyard face is the busy one -- the inverse of a normal building.
    thick_wall(mb, rin, rin + 0.7, FLOOR_TOP, CLERE0, ph, PANEL_D, op_in)
    for z in (FLOOR_TOP + 2.2, FLOOR_TOP + 4.6):
        pipe_run(mb, rin + 1.3, ph, z)
    glass_band(gl, rin + 0.35, CLERE0, CLERE1, ph,
               dict(op_in, z=CLERE1) if op_in else None)
    mullions(mb, rin + 0.05, rin + 0.7, ph, CLERE0, CLERE1, None)

    if variant == "lobby":
        # the one glazed thing on a fab: a visitor lobby bolted to the shed
        thick_wall(mb, r - 0.7, r, FLOOR_TOP, CLERE0, ph, PANEL, op_out)
        for rg in (r - 0.35, rin + 0.35):
            door_frame(mb, rg, ph, -LOBBY_W / 2, LOBBY_W / 2, FLOOR_TOP, FLOOR_TOP + LOBBY_H, 1)
        glass_band(gl, r - 0.35, FLOOR_TOP + 0.2, CLERE0, W.angles(-9, 9, 4), None)
        W.canopy(mb, r)
    elif variant == "bridge":
        door_frame(mb, rin + 0.35, ph, -DOOR_W / 2, DOOR_W / 2, FLOOR_TOP, FLOOR_TOP + DOOR_H, 1)

    # bay dividers: the structural grid you can see through the clerestory
    for phs in (-22.5, 22.5):
        W.partition(mb, gl, r, phs)
    return mb, gl


# -------------------------------------------------------------- 2. the fan deck
def build_deck(w):
    """The fan deck. Where the Wafers put a lawn and a running track, a fab puts
    the machinery that keeps the cleanroom below it clean: a walkable grille,
    rows of air handlers, and the pipe runs between them."""
    r = WAFER[w][2]
    rin = r - DEPTH
    mb = MB(floors=[DECK_SURF, 1.5])
    gl = MB()
    band(mb, rin - 0.3, r + 0.3, 0.0, DECK_SURF, RING40,
         dict(t=GRILLE, o=PANEL_D, i=PANEL_D), "toi")
    # the grille's own grain, so it does not read as flat paint from the plaza
    for i in range(10):
        rho = rin + 1.2 + (r - rin - 2.4) * i / 9.0
        band(mb, rho - 0.18, rho + 0.18, DECK_SURF, DECK_SURF + 0.1, RING8, dict(t=STEEL_D), "t")
    plant_row(mb, r - 13.0, r - 4.2, RING8, DECK_SURF, count=8, hgt=3.6)
    pipe_run(mb, rin + 3.0, RING8, DECK_SURF + 0.9, r=0.6)
    pipe_run(mb, rin + 4.6, RING8, DECK_SURF + 0.9, r=0.6, col=STEEL)
    track_ring(mb, r + 1.6, DECK_SURF + 6.4)
    rails(mb, gl, r - 0.35, RING8)
    rails(mb, gl, rin + 0.35, RING8, gap=3.4)
    return mb, gl


def build_deck_columns(w):
    """Long-span trusses instead of columns. A cleanroom is column-free, which
    is why a real fab roof is carried on deep trusses -- so the honest structure
    for this path is a truss, exposed, spanning the gap to the tier above."""
    cx1, cz1, r = WAFER[w]
    cx2, cz2, r2 = WAFER[w + 1]
    mb = MB(floors=[DECK_SURF], unders=[H])
    ox, oy = -(cx2 - cx1), (cz2 - cz1)
    top = H - 1.0
    for j in range(20):
        a = j / 20 * 360.0
        # the truss sits where the upper ring lands, offset by the lean
        for rho in (r2 - DEPTH + 3.0, r2 - 3.0):
            x, y = W.P(rho, a)
            x, y = x + ox, y + oy
            obox(mb, (x, y), W.radial(a), 0.55, 0.55, DECK_SURF, top, STEEL)
        # the diagonal web, drawn as a shallow box between the two chords
        x0, y0 = W.P(r2 - DEPTH + 3.0, a)
        x1, y1 = W.P(r2 - 3.0, a)
        mx, my = (x0 + x1) / 2 + ox, (y0 + y1) / 2 + oy
        obox(mb, (mx, my), W.radial(a), (DEPTH - 6.0) / 2, 0.3, top - 1.5, top, STEEL_D)
    return mb, None


# ---------------------------------------------------------------- 3. the roof
def build_roof():
    """The last fan deck, and the one a player stands on. Same language as the
    tier decks so the top does not suddenly become a different building."""
    r = WAFER[4][2]
    mb = MB(floors=[DECK_SURF])
    gl = MB()
    band(mb, 0, r + 0.3, 0.0, DECK_SURF, RING8, dict(t=GRILLE, o=PANEL_D), "to")
    for i in range(12):
        rho = 6.0 + (r - 8.0) * i / 11.0
        band(mb, rho - 0.18, rho + 0.18, DECK_SURF, DECK_SURF + 0.1, RING8, dict(t=STEEL_D), "t")
    plant_row(mb, r - 16.0, r - 6.0, RING8, DECK_SURF, count=10, hgt=4.2)
    pipe_run(mb, r - 20.0, RING8, DECK_SURF + 1.0, r=0.7)
    track_ring(mb, r + 1.6, DECK_SURF + 6.4)
    rails(mb, gl, r - 0.35, RING8)
    return mb, gl


# ------------------------------------------------------------ 4. control room
def build_pavilion():
    """Where the Wafers put a founder's pavilion, the fab puts the control room:
    the one glazed box on the whole building, looking down the track."""
    rin, rout = W.PAV_IN, W.PAV_OUT
    ph = W.angles(-44, 44, 10)
    mb = MB(floors=[SLAB], unders=[CEIL0])
    gl = MB()
    band(mb, rin, rout, 0.0, SLAB, ph, dict(t=FLOOR, b=STEEL_D, o=PANEL_D, i=PANEL_D, c=PANEL_D), "tboi", "se")
    band(mb, rin - 0.6, rout + 0.6, CEIL0, CEIL0 + 1.2, ph,
         dict(t=ROOF, b=CEILING, o=PANEL, i=PANEL, c=PANEL), "tboi", "se")
    # glazed on the outside, solid plant wall behind
    glass_band(gl, rout - 0.35, SLAB + 0.6, CEIL0 - 0.3, ph, None)
    mullions(mb, rout - 0.7, rout - 0.05, ph, SLAB + 0.6, CEIL0 - 0.3, None)
    thick_wall(mb, rin, rin + 0.7, SLAB, CEIL0, ph, PANEL_D, None)
    pipe_run(mb, rin + 1.4, ph, SLAB + 3.0)
    # the console: a desk ring facing the glass
    band(mb, rout - 5.0, rout - 3.2, SLAB, SLAB + 1.1, ph, dict(t=CHARCOAL, o=ANOD, i=ANOD), "toi")
    return mb, gl


# ---------------------------------------------- 5. THE OVERHEAD WAFER TRACK
def track_ring(mb, r, z):
    """One run of overhead track with its hangers and parked carriers."""
    ph = RING8
    band(mb, r - 0.9, r + 0.9, z, z + 1.3, ph, dict(t=TRACK_C, b=TRACK_D, o=TRACK_C, i=TRACK_C, c=TRACK_D), "tboi")
    band(mb, r - 1.3, r + 1.3, z - 0.45, z, ph, dict(t=TRACK_D, b=TRACK_D, o=TRACK_D, i=TRACK_D, c=TRACK_D), "tboi")
    for j in range(16):
        a = j / 16 * 360.0
        x, y = W.P(r, a)
        obox(mb, (x, y), W.radial(a), 0.34, 0.34, z + 1.3, z + 4.6, STEEL)
        if j % 3 != 1:
            obox(mb, (x, y), W.radial(a), 1.5, 1.1, z - 2.5, z - 0.45, CARRIER)


def build_halo():
    """The signature.

    Intel's Arizona site runs 30 miles of overhead track moving wafers between
    buildings. This is that track, as a ring the player can see from the plaza:
    a rail on hangers, with carriers parked along it.

    It replaces the Wafers' gold halo, sits in the same slot, and is the only
    warm colour on the building -- which is the point. On a white machine, the
    one thing that moves should be the one thing you can see.
    """
    r = WAFER[4][2] + 2.0
    mb = MB()
    ph = RING8
    # the rail: a box beam, with a lower flange so it reads as track not pipe
    band(mb, r - 0.9, r + 0.9, 0.0, 1.3, ph, dict(t=TRACK_C, b=TRACK_D, o=TRACK_C, i=TRACK_C, c=TRACK_D), "tboi")
    band(mb, r - 1.3, r + 1.3, -0.45, 0.0, ph, dict(t=TRACK_D, b=TRACK_D, o=TRACK_D, i=TRACK_D, c=TRACK_D), "tboi")
    # hangers up to the soffit above
    for j in range(24):
        a = j / 24 * 360.0
        x, y = W.P(r, a)
        obox(mb, (x, y), W.radial(a), 0.34, 0.34, 1.3, 5.0, STEEL)
    # carriers (FOUPs) parked along it, unevenly, so it reads as in use
    for j in range(24):
        if j % 3 == 1:
            continue
        a = (j + 0.5) / 24 * 360.0
        x, y = W.P(r, a)
        obox(mb, (x, y), W.radial(a), 1.5, 1.1, -2.5, -0.45, CARRIER)
        obox(mb, (x, y), W.radial(a), 0.5, 0.5, -0.45, 0.0, STEEL_D)
    return mb, None


# --------------------------------------------------------- BASE AND CROWN
def build_podium():
    """TERRAFAB: a service plinth. A fab meets the ground at a LOADING DOCK --
    roller shutters, a raised dock lip at truck-bed height, bollards. It is the
    least glamorous base of the three on purpose: this building is a machine and
    the base is where the machine is fed."""
    r = W.WAFER[1][2] + 6.0
    mb = MB(floors=[0.0], unders=[W.PODIUM_H])
    conc = rgb(198, 196, 190)
    conc_d = rgb(164, 162, 156)
    band(mb, r - W.DEPTH - 4.0, r, 0.0, 2.6, W.RING40, dict(t=conc, o=conc_d, i=conc_d), "toi")
    # ribbed precast wall
    band(mb, r - 2.2, r, 2.6, W.PODIUM_H, W.RING40,
         dict(t=conc, b=conc_d, o=conc, i=conc, c=conc_d), "tboi")
    for j in range(40):
        a = j / 40 * 360.0
        x, y = W.P(r - 0.3, a)
        obox(mb, (x, y), W.radial(a), 0.5, 0.42, 2.6, W.PODIUM_H - 1.0, conc_d)
    # the dock: a raised lip and four roller shutters on the road side
    half = math.degrees(math.asin(16.0 / r))
    ph = W.angles(-half, half, 8)
    band(mb, r - 6.0, r + 1.2, 0.0, 3.6, ph, dict(t=conc_d, b=conc_d, o=conc_d, i=conc_d, c=conc_d), "tboi")
    for k in range(-1, 3):
        w2 = math.degrees(math.asin(3.4 / r))
        c0 = (k - 0.5) * (w2 * 2.6)
        band(mb, r - 2.4, r - 1.9, 3.6, 12.0, W.angles(c0 - w2, c0 + w2, 3),
             dict(t=ANOD, b=ANOD, o=ANOD, i=ANOD, c=ANOD), "tboi")
    # bollards, because a dock has them and they say "trucks come here"
    for k in (-1.6, -0.55, 0.55, 1.6):
        a = k * half * 0.8
        x, y = W.P(r + 2.4, a)
        obox(mb, (x, y), W.radial(a), 0.5, 0.5, 0.0, 3.4, TRACK_C)
    band(mb, r - 3.4, r + 1.0, W.PODIUM_H, W.PODIUM_H + 2.0, W.RING40,
         dict(t=conc, b=conc_d, o=conc, i=conc, c=conc_d), "tboi", "se")
    return mb, None


def build_crown():
    """TERRAFAB: the plant cap. A fab's top level is the FAN DECK -- the deepest
    layer of machinery in the building sits above the cleanroom, not below it.
    So the crown is the one thing a fab genuinely has that nothing else does: a
    dense raft of air handlers, two exhaust stacks, and the wafer track running
    its last lap round the lot."""
    r = W.WAFER[4][2]
    mb = MB(floors=[0.0])
    band(mb, 0, r + 0.4, 0.0, 1.4, RING8, dict(t=GRILLE, o=PANEL_D), "to")
    # the raft
    for ring, n, h in ((r - 8.0, 10, 5.6), (r - 20.0, 8, 7.0), (r - 30.0, 6, 8.4)):
        plant_row(mb, ring - 7.0, ring, RING8, 1.4, count=n, hgt=h)
    # two stacks, offset so the top is not symmetrical
    for ox, oy, hh in ((9.0, -5.0, 30.0), (-11.0, 7.0, 22.0)):
        prism(mb, (ox, oy), 10, 2.6, 2.6, 1.4, hh, PANEL_D)
        prism(mb, (ox, oy), 10, 3.1, 3.1, hh, hh + 1.4, ANOD)
        band(mb, 0, 0.1, 0, 0.1, W.angles(0, 1, 1), dict(t=ANOD), "t")
    track_ring(mb, r + 1.6, 9.0)
    return mb, None


# ------------------------------------------------------------------- the kit
def kit():
    k = {}
    for w in (1, 2, 3, 4):
        k["T_Seg_%d" % w] = (lambda w=w: build_segment(w, "plain"), "T_Glass_%d" % w)
        k["T_SegB_%d" % w] = (lambda w=w: build_segment(w, "bridge"), "T_GlassB_%d" % w)
    k["T_Lobby"] = (lambda: build_segment(1, "lobby"), "T_LobbyGlass")
    for w in (1, 2, 3):
        k["T_Deck_%d" % w] = (lambda w=w: build_deck(w), "T_DeckGlass_%d" % w)
        k["T_DeckCols_%d" % w] = (lambda w=w: build_deck_columns(w), None)
    k["T_Roof"] = (build_roof, "T_RoofGlass")
    k["T_Pav"] = (build_pavilion, "T_PavGlass")
    k["T_Halo"] = (build_halo, None)
    k["T_Podium"] = (build_podium, None)
    k["T_Crown"] = (build_crown, None)
    # style-neutral: a lift is a lift, a bridge is a bridge
    k["T_Core"] = (W.build_core, "T_CoreGlass")
    k["T_CoreCap"] = (W.build_cap, None)
    k["T_Lantern"] = (W.build_lantern, "T_LanternGlass")
    k["T_Mast"] = (W.build_mast, None)
    k["T_Bridge"] = (W.build_bridge, "T_BridgeGlass")
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
    META[obj.name] = dict(c=(-c[0] + 0.0, c[2], c[1]), s=(s[0], s[2], s[1]), tris=K.tris(obj))


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    for a in args:
        if a.startswith("only="):
            only = set(a[5:].split(","))
    K.reset()
    total = 0
    for name, (fn, gname) in kit().items():
        if only and name not in only and gname not in only:
            continue
        shell, glass = fn()
        o = shell.to_object(name)
        record(o)
        K.export(os.path.join(OUT, name + ".fbx"), [o])
        total += META[name]["tris"]
        line = "%-16s %5d tris" % (name, META[name]["tris"])
        if glass is not None:
            g = glass.to_object(gname)
            record(g)
            K.export(os.path.join(OUT, gname + ".fbx"), [g])
            total += META[gname]["tris"]
            line += "   %-16s %5d tris" % (gname, META[gname]["tris"])
        print(line)
    import metafile
    if not only:
        stale = os.path.join(metafile.META_DIR, "Terrafab.lua")
        if os.path.exists(stale):
            os.remove(stale)
    path = metafile.write(
        "Terrafab", "blender/terrafab.py: the Terrafab kit (path 2 of 3). Same skeleton as the Wafers, "
        "fab skin. c/s are piece-local, Roblox axes. LANTERN_H = %.1f, MAST_H = %.1f" % (LANTERN_H, MAST_H), META)
    print("META ->", path)
    print("pieces: %d   total tris: %d" % (len(META), total))


if __name__ == "__main__":
    main()
