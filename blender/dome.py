"""dome.py -- the game-ready mesh kit for THE DOME, path 3 of 3.

Same skeleton as the Wafers and the Terrafab (same storey height, same 100
levels, same deck positions, same lift core, same 8 segments per storey), and
the SAME 40 piece names under a D_ prefix, so one placer builds any path.

Everything style-neutral is imported from wafers.py: the lift core, its cap,
the bridge, the lantern, the mast.

THE RESEARCH (see CONCEPTS-THREE-PATHS.md):
Google Bay View, by BIG and Heatherwick Studio. Its roofs are tent-like and
loosely domed, and they TAPER TOWARD GROUND LEVEL rather than stopping at a
parapet. They are carried on slim white columns, and between every curved
panel is a CLERESTORY window, so daylight reaches the middle of a very deep
floor. The solar skin is made of overlapping scales -- "dragonscale".

So against the Wafers, piece by piece:
  Seg      flat glass facade      ->  glass set well in, under an overhanging canopy
  Deck     garden + track         ->  a planted terrace under the canopy edge
  DeckCols columns                ->  slim white columns, Bay View's whole structure
  Roof     roof garden            ->  the big tent, tapering to a point
  Pav      founder pavilion       ->  a glass room under the apex
  Halo     gold ring              ->  the lit CLERESTORY seam

The canopy is the building. Everything else gets out of its way.

Run:   blender -b --python blender/dome.py
Out:   out/IMPORT_DOME/<name>.fbx
       game/src/ServerScriptService/HQMeta/Dome.lua
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import svkit as K  # noqa: E402
import wafers as W  # noqa: E402

MB = W.MB
band, obox = W.band, W.obox
glass_band, thick_wall, mullions = W.glass_band, W.thick_wall, W.mullions
door_frame, rails = W.door_frame, W.rails

H, SLAB, DEPTH = W.H, W.SLAB, W.DEPTH
FLOOR_TOP, SILL, CEIL0, CEIL1, OVH = W.FLOOR_TOP, W.SILL, W.CEIL0, W.CEIL1, W.OVH
DECK_SURF = W.DECK_SURF
LOBBY_W, LOBBY_H, DOOR_W, DOOR_H = W.LOBBY_W, W.LOBBY_H, W.DOOR_W, W.DOOR_H
LANTERN_H, MAST_H = W.LANTERN_H, W.MAST_H
WAFER = W.WAFER
RING40, RING20 = W.RING40, W.RING20

OUT = os.path.join(HERE, "out", "IMPORT_DOME")
os.makedirs(OUT, exist_ok=True)

rgb = K.rgb
WHITE = rgb(246, 244, 238)           # the columns and the soffits
SCALE_A = rgb(158, 174, 196)         # the dragonscale, lit face
SCALE_B = rgb(132, 150, 176)         # and its shadowed overlap
CLERE = rgb(255, 244, 212)           # the lit seam -- the signature
TIMBER = rgb(198, 154, 102)          # Bay View's ceilings are wood
GREEN = W.LAWN
PAPER = W.PAPER
FLOOR = W.FLOOR

# The glass is set IN from the canopy edge: the overhang is the whole point,
# and a facade flush with it would read as an ordinary tower with a hat.
INSET = 7.0
SCALES = 6                            # overlapping rings per canopy


def seg_ph():
    return W.angles(-22.5, 22.5, W.NFAC)


def canopy(mb, r, z0, rise, segs=W.NFAC * 8, ph=None, close=False):
    """One tent: rings of falling radius and rising height, each overlapping the
    one inside it, so the edge of every scale catches light the way Bay View's
    panels do. `close` caps the apex."""
    ph = ph or RING40
    for k in range(SCALES):
        t0, t1 = k / SCALES, (k + 1) / SCALES
        r0 = r * (1.0 - 0.46 * t0)
        r1 = r * (1.0 - 0.46 * t1)
        h0 = z0 + rise * math.sin(t0 * math.pi * 0.5)
        col = SCALE_A if k % 2 == 0 else SCALE_B
        # the scale, with its lower lip hanging past the ring inside it
        band(mb, r1, r0 + 1.1, h0, h0 + 0.85, ph,
             dict(t=col, b=WHITE, o=col, i=col, c=col), "tboi")
    if close:
        rtop = r * (1.0 - 0.46)
        band(mb, 0, rtop + 0.6, z0 + rise, z0 + rise + 0.85, ph,
             dict(t=SCALE_A, b=WHITE, o=SCALE_A), "tbo")


def build_segment(w, variant):
    """A floor under the tent. The glass sits INSET from the canopy edge, with
    slim columns carrying the overhang -- so from outside you read roof, shade,
    then glass, which is the Bay View order."""
    r = WAFER[w][2]
    rin = r - DEPTH
    rg = r - INSET                     # where the glass actually stands
    ph = seg_ph()
    unders = [CEIL0] + ([W.CANOPY_Z] if variant == "lobby" else [])
    mb = MB(floors=[FLOOR_TOP], unders=unders)
    gl = MB()

    # slabs. Bay View's soffits are timber, and the overhang is deep.
    band(mb, rin - OVH, r + OVH, 0.0, SLAB, ph,
         dict(t=FLOOR, b=TIMBER, o=WHITE, i=WHITE, c=WHITE), "tboi", "se")
    band(mb, rin - OVH, r + OVH, CEIL0, CEIL1, ph,
         dict(t=PAPER, b=TIMBER, o=WHITE, i=WHITE, c=WHITE), "tboi", "se")

    op_out = op_in = None
    if variant == "lobby":
        op_out = dict(x=(-LOBBY_W / 2, LOBBY_W / 2), z=FLOOR_TOP + LOBBY_H, y=1)
        op_in = dict(op_out)
    elif variant == "bridge":
        op_in = dict(x=(-DOOR_W / 2, DOOR_W / 2), z=FLOOR_TOP + DOOR_H, y=1)

    # the facade: almost all glass, because the roof does the shading
    thick_wall(mb, rg - 0.5, rg, FLOOR_TOP, FLOOR_TOP + 1.1, ph, WHITE, op_out)
    glass_band(gl, rg - 0.3, FLOOR_TOP + 1.1, CEIL0 - 0.4, ph, op_out)
    mullions(mb, rg - 0.6, rg - 0.05, ph, FLOOR_TOP + 1.1, CEIL0 - 0.4, op_out)

    thick_wall(mb, rin, rin + 0.5, FLOOR_TOP, FLOOR_TOP + 1.1, ph, WHITE, op_in)
    glass_band(gl, rin + 0.3, FLOOR_TOP + 1.1, CEIL0 - 0.4, ph,
               dict(op_in, z=CEIL0 - 0.4) if op_in else None)
    mullions(mb, rin + 0.05, rin + 0.6, ph, FLOOR_TOP + 1.1, CEIL0 - 0.4, op_in)

    # the columns that carry the overhang: slim, white, outboard of the glass
    for a in (-16.0, 0.0, 16.0):
        x, y = W.P(r - 2.2, a)
        obox(mb, (x, y), W.radial(a), 0.46, 0.46, SLAB, CEIL0, WHITE)

    if variant == "lobby":
        for g in (rg - 0.3, rin + 0.3):
            door_frame(mb, g, ph, -LOBBY_W / 2, LOBBY_W / 2, FLOOR_TOP, FLOOR_TOP + LOBBY_H, 1)
        W.canopy(mb, r)
    elif variant == "bridge":
        door_frame(mb, rin + 0.3, ph, -DOOR_W / 2, DOOR_W / 2, FLOOR_TOP, FLOOR_TOP + DOOR_H, 1)

    for phs in (-22.5, 22.5):
        W.partition(mb, gl, rg, phs)
    return mb, gl


def build_deck(w):
    """A planted terrace, sheltered by the canopy above it. Where the Wafers put
    a running track, Bay View puts ground cover and a path."""
    r = WAFER[w][2]
    rin = r - DEPTH
    mb = MB(floors=[DECK_SURF, 1.5])
    gl = MB()
    band(mb, rin - 0.3, r + 0.3, 0.0, DECK_SURF, RING40, dict(t=PAPER, o=WHITE, i=WHITE), "toi")
    band(mb, rin + 2.0, r - 2.0, DECK_SURF, DECK_SURF + 0.12, RING40, dict(t=GREEN), "t")
    W.beds(mb, r - 8.0, r - 2.4, n=10, span=15.0, seed=w * 7, per=3)
    # the canopy over the terrace: this is the tier's own tent
    canopy(mb, r + 1.0, DECK_SURF + 10.5, 7.0)
    rails(mb, gl, r - 0.35, RING20)
    rails(mb, gl, rin + 0.35, RING20, gap=3.4)
    return mb, gl


def build_deck_columns(w):
    """Slim white columns. At Bay View the columns ARE the structure -- there is
    no core frame to hide behind -- so they are regular, thin and many."""
    cx1, cz1, r = WAFER[w]
    cx2, cz2, r2 = WAFER[w + 1]
    mb = MB(floors=[DECK_SURF], unders=[H])
    ox, oy = -(cx2 - cx1), (cz2 - cz1)
    for j in range(28):
        a = j / 28 * 360.0
        for rho in (r2 - DEPTH + 2.5, r2 - 2.5):
            x, y = W.P(rho, a)
            obox(mb, (x + ox, y + oy), W.radial(a), 0.42, 0.42, DECK_SURF, H - 0.8, WHITE)
    return mb, None


def build_roof():
    """The big tent, tapering to its apex. The one piece of this path somebody
    could pick out of a line-up."""
    r = WAFER[4][2]
    mb = MB(floors=[DECK_SURF])
    gl = MB()
    band(mb, 0, r + 0.3, 0.0, DECK_SURF, RING40, dict(t=PAPER, o=WHITE), "to")
    band(mb, 4.0, r - 4.0, DECK_SURF, DECK_SURF + 0.12, RING40, dict(t=GREEN), "t")
    canopy(mb, r + 1.5, DECK_SURF + 11.0, 13.0, close=True)
    rails(mb, gl, r - 0.35, RING20)
    return mb, gl


def build_pavilion():
    """A glass room under the apex, so the top of the building is somewhere you
    stand rather than a lid."""
    rin, rout = W.PAV_IN, W.PAV_OUT
    ph = W.angles(-44, 44, 10)
    mb = MB(floors=[SLAB], unders=[CEIL0])
    gl = MB()
    band(mb, rin, rout, 0.0, SLAB, ph, dict(t=FLOOR, b=TIMBER, o=WHITE, i=WHITE, c=WHITE), "tboi", "se")
    band(mb, rin - 0.8, rout + 0.8, CEIL0, CEIL0 + 1.0, ph,
         dict(t=PAPER, b=TIMBER, o=WHITE, i=WHITE, c=WHITE), "tboi", "se")
    glass_band(gl, rout - 0.3, SLAB + 0.8, CEIL0 - 0.4, ph, None)
    mullions(mb, rout - 0.6, rout - 0.05, ph, SLAB + 0.8, CEIL0 - 0.4, None)
    glass_band(gl, rin + 0.3, SLAB + 0.8, CEIL0 - 0.4, ph, None)
    for a in (-38.0, 0.0, 38.0):
        x, y = W.P(rout - 1.4, a)
        obox(mb, (x, y), W.radial(a), 0.42, 0.42, SLAB, CEIL0, WHITE)
    return mb, gl


def build_halo():
    """THE CLERESTORY. At Bay View a lit seam runs between every curved panel so
    daylight reaches the middle of a deep floor. It replaces the Wafers' gold
    ring, and at night it is what the building is recognised by."""
    r = WAFER[4][2] + 1.0
    mb = MB()
    band(mb, r - 1.4, r + 1.4, 0.0, 2.1, RING40,
         dict(t=CLERE, b=CLERE, o=CLERE, i=CLERE, c=CLERE), "tboi")
    band(mb, r - 1.8, r + 1.8, 2.1, 2.7, RING40, dict(t=WHITE, o=WHITE, i=WHITE), "toi")
    for j in range(28):
        a = j / 28 * 360.0
        x, y = W.P(r, a)
        obox(mb, (x, y), W.radial(a), 0.3, 0.3, -3.2, 0.0, WHITE)
    return mb, None


# --------------------------------------------------------- BASE AND CROWN
def build_podium():
    """DOME: a glass pavilion that FLARES OUT to the ground. Bay View's roofs
    taper toward ground level rather than stopping at a parapet, and the base is
    where that move actually lands -- the building gets wider as it comes down,
    so it looks grown rather than placed."""
    r = WAFER[1][2] + 6.0
    mb = MB(floors=[0.0], unders=[W.PODIUM_H])
    gl = MB()
    # the flare: rings of falling radius as they rise, the inverse of the canopy
    steps = 5
    for k in range(steps):
        t0, t1 = k / steps, (k + 1) / steps
        r0 = r * (1.0 + 0.10 * (1.0 - t0))
        r1 = r * (1.0 + 0.10 * (1.0 - t1))
        z0 = W.PODIUM_H * t0
        band(mb, r1 - DEPTH - 6.0, r0, z0, z0 + W.PODIUM_H / steps + 0.4, RING40,
             dict(t=WHITE, b=WHITE, o=WHITE, i=WHITE, c=WHITE), "tboi", "se")
    # glazed between the flare and the shaft, on slim columns
    glass_band(gl, r - 4.0, 2.0, W.PODIUM_H - 1.0, RING40)
    for j in range(28):
        a = j / 28 * 360.0
        x, y = W.P(r - 4.0, a)
        obox(mb, (x, y), W.radial(a), 0.4, 0.4, 2.0, W.PODIUM_H - 1.0, WHITE)
    # the entrance: the flare lifts into a wide porch on the road side
    half = math.degrees(math.asin(16.0 / r))
    ph = W.angles(-half, half, 8)
    band(mb, r - 2.0, r + 7.0, W.PODIUM_H - 2.6, W.PODIUM_H - 0.8, ph,
         dict(t=WHITE, b=TIMBER, o=WHITE, i=WHITE, c=WHITE), "tboi", "se")
    for k in (-1.0, -0.34, 0.34, 1.0):
        x, y = W.P(r + 5.0, k * half * 0.85)
        obox(mb, (x, y), W.radial(k * half * 0.85), 0.4, 0.4, 0.0, W.PODIUM_H - 2.6, WHITE)
    return mb, gl


def build_crown():
    """DOME: the apex. Every tier below is a canopy that stops short; this is the
    one that CLOSES, to a lit oculus ring. Bay View's clerestory seam is the
    building's signature, so the top is the seam turned into a halo."""
    r = WAFER[4][2]
    mb = MB(floors=[0.0])
    canopy(mb, r + 1.0, 0.0, 17.0, close=True)
    # the oculus: a lit ring at the apex, the clerestory's last run
    rtop = r * (1.0 - 0.46)
    band(mb, rtop - 3.0, rtop + 1.6, 16.6, 18.4, RING40,
         dict(t=CLERE, b=CLERE, o=CLERE, i=CLERE, c=CLERE), "tboi")
    for j in range(20):
        a = j / 20 * 360.0
        x, y = W.P(rtop - 0.7, a)
        obox(mb, (x, y), W.radial(a), 0.34, 0.34, 11.0, 16.6, WHITE)
    return mb, None


def kit():
    k = {}
    for w in (1, 2, 3, 4):
        k["D_Seg_%d" % w] = (lambda w=w: build_segment(w, "plain"), "D_Glass_%d" % w)
        k["D_SegB_%d" % w] = (lambda w=w: build_segment(w, "bridge"), "D_GlassB_%d" % w)
    k["D_Lobby"] = (lambda: build_segment(1, "lobby"), "D_LobbyGlass")
    for w in (1, 2, 3):
        k["D_Deck_%d" % w] = (lambda w=w: build_deck(w), "D_DeckGlass_%d" % w)
        k["D_DeckCols_%d" % w] = (lambda w=w: build_deck_columns(w), None)
    k["D_Roof"] = (build_roof, "D_RoofGlass")
    k["D_Pav"] = (build_pavilion, "D_PavGlass")
    k["D_Halo"] = (build_halo, None)
    k["D_Podium"] = (build_podium, "D_PodiumGlass")
    k["D_Crown"] = (build_crown, None)
    k["D_Core"] = (W.build_core, "D_CoreGlass")
    k["D_CoreCap"] = (W.build_cap, None)
    k["D_Lantern"] = (W.build_lantern, "D_LanternGlass")
    k["D_Mast"] = (W.build_mast, None)
    k["D_Bridge"] = (W.build_bridge, "D_BridgeGlass")
    return k


META = {}


def record(obj):
    mn, mx = [1e9] * 3, [-1e9] * 3
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
        stale = os.path.join(metafile.META_DIR, "Dome.lua")
        if os.path.exists(stale):
            os.remove(stale)
    path = metafile.write(
        "Dome", "blender/dome.py: the Dome kit (path 3 of 3). Same skeleton as the Wafers, Bay View skin. "
        "c/s are piece-local, Roblox axes. LANTERN_H = %.1f, MAST_H = %.1f" % (LANTERN_H, MAST_H), META)
    print("META ->", path)
    print("pieces: %d   total tris: %d" % (len(META), total))


if __name__ == "__main__":
    main()
