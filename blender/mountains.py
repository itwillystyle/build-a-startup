"""mountains.py -- the valley's mountains as meshes (v4.0, 28 Sep 2026).

His verdict: "the mountains still look plain and should evoke more realism...
the colour is not the problem, it is the pixelly visuals... blockiness."
Cause: Roblox draws distant terrain at a coarse level of detail (big voxel
steps and facets), and low-end phones stop drawing terrain at ~500-600 studs.
No terrain setting fixes that. So:

  * the walkable valley stays terrain (stretched radius < ~600, and the Bay);
  * everything beyond is MESH, built from the game's own terrain (sampled by
    raycast in Studio -> out/terrain_samples.txt) so the seam matches, then
    given what real hills have: drainage gullies carved by flow accumulation,
    sharpened ridgelines, and colour by what grows where -- golden grass,
    oak woodland down the gullies and north slopes, redwood forest on the
    southern crest, bare rock on the steep faces;
  * a second, wider range out to ~2,400 studs (Santa Cruz Mountains south,
    Diablo Range east, the East Bay hills across the water) so the horizon is
    mountains, not haze.

Roblox <- Blender mapping (measured, Phase W): Roblox (X, Y, Z) is modelled at
Blender (-X, Z, Y); each tile is placed by its bounding-box centre (written to
out/mountains_meta.lua). Trees for the mesh slopes -> out/mountain_trees.lua.

Run:  blender -b --python mountains.py
"""
import bpy
import bmesh
import math
import os
import random
import sys

import numpy as np
from mathutils import Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import svkit as K  # noqa: E402

OUT = os.path.join(HERE, "out")
IMP = os.path.join(OUT, "IMPORT_MOUNTAINS")
os.makedirs(IMP, exist_ok=True)

SX = 1.35                 # the valley ellipse (ValleyGen stretchX)
SEAM = 600.0              # stretched radius where terrain hands over to mesh
BLEND = 60.0              # overlap band: the mesh tucks just under the terrain here
NEAR_STEP = 8             # the sampled ring, full detail
FAR_STEP = 32             # the backdrop range (broad ridges only: fine noise at this spacing turned jagged)
FIELD = (-2400, 2400, -2200, 2200)   # x0, x1, z0, z1 (Roblox studs)
LICK = (352.0, 596.0, 70.0)          # keep the observatory's hilltop as built


def c255(r, g, b):
    return np.array([r, g, b], dtype=np.float64) / 255.0


# ------------------------------------------------------------------ 1. the sampled terrain
def load_samples():
    path = os.path.join(OUT, "terrain_samples.txt")
    with open(path) as f:
        head = f.readline().split()
        x0, x1, z0, z1, step = (int(v) for v in head)
        rows = [line.strip().split(",") for line in f if line.strip()]
    nz, nx = len(rows), len(rows[0])
    h = np.zeros((nz, nx))
    mat = np.empty((nz, nx), dtype="<U1")
    for i, row in enumerate(rows):
        for j, cell in enumerate(row):
            h[i, j] = float(cell[:-1])
            mat[i, j] = cell[-1]
    return (x0, z0, step), h, mat


# ------------------------------------------------------------------ 2. the whole field
def fbm(x, z, freq, octaves, seed, ridged=False):
    v, amp, tot = 0.0, 1.0, 0.0
    for o in range(octaves):
        n = noise.noise(Vector((x * freq, z * freq, seed + o * 17.3)))
        if ridged:
            n = 1.0 - abs(n)
            n = n * n * 2 - 1
        v += n * amp
        tot += amp
        amp *= 0.5
        freq *= 2.0
    return v / tot


def procedural(x, z):
    """The ranges beyond the sampled valley. Heights in studs."""
    rs = math.sqrt((x / SX) ** 2 + z * z)
    # West: the Bay is open water to x ~ -1250, then the East Bay hills across it
    if x < -900 and abs(z) < 900:
        across = max(0.0, min(1.0, (-x - 1250) / 260))
        hills = 60 + 140 * max(0.0, fbm(x, z, 1 / 520, 4, 91) * 0.5 + 0.6)
        return -6 + across * (hills + 6)
    t = max(0.0, min(1.0, (rs - 620) / 700))
    south = z < 0
    peak = 320 if south else 250
    base = (t ** 0.8) * peak
    if x > 850:
        # east: downtown and the road carry on across a low plain; the Diablo
        # Range rises behind it (it used to drop into a steep canyon here)
        corridor = max(0.0, min(1.0, (abs(z) - 380) / 320))
        plain = max(0.0, min(1.0, (x - 1650) / 450))
        base = base * max(corridor, plain) + 6 * (1 - max(corridor, plain))
        if plain > 0:
            base = max(base, plain * 300 * (0.5 + 0.5 * max(corridor, 0.4)))
    ridge = fbm(x, z, 1 / 700, 5, 23, ridged=True)             # long ridgelines
    body = fbm(x, z, 1 / 380, 4, 29)
    return 40 + base * (0.62 + 0.28 * ridge + 0.22 * body)


def build_field():
    (sx0, sz0, sstep), hs, ms = load_samples()
    fx0, fx1, fz0, fz1 = FIELD
    xs = np.arange(fx0, fx1 + 1, NEAR_STEP, dtype=np.float64)
    zs = np.arange(fz0, fz1 + 1, NEAR_STEP, dtype=np.float64)
    H = np.zeros((len(zs), len(xs)))
    W = np.zeros_like(H)          # 1 where the sample is trusted
    mat = np.full(H.shape, "x", dtype="<U1")
    sxN = hs.shape[1]
    szN = hs.shape[0]
    for i, z in enumerate(zs):
        for j, x in enumerate(xs):
            p = procedural(x, z)
            si = int(round((z - sz0) / sstep))
            sj = int(round((x - sx0) / sstep))
            if 0 <= si < szN and 0 <= sj < sxN and hs[si, sj] > -90:
                # fade the sample into the procedural ranges over the outer 160 studs of the sampled box
                ex = min(x - sx0, (sx0 + (sxN - 1) * sstep) - x)
                ez = min(z - sz0, (sz0 + (szN - 1) * sstep) - z)
                w = max(0.0, min(1.0, min(ex, ez) / 160.0))
                H[i, j] = hs[si, sj] * w + p * (1 - w)
                W[i, j] = w
                mat[i, j] = ms[si, sj]
            else:
                H[i, j] = p
    return xs, zs, H, W, mat


# ------------------------------------------------------------------ 3. erosion (drainage gullies)
def flow_accumulation(H):
    nz, nx = H.shape
    order = np.argsort(-H, axis=None)
    A = np.ones(H.size)
    Hf = H.ravel()
    recv = np.full(H.size, -1, dtype=np.int64)
    # steepest-descent receiver (D8)
    best = np.zeros(H.size)
    for di, dj in ((-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)):
        dist = math.sqrt(di * di + dj * dj)
        shifted = np.full(H.shape, np.inf)
        si0, si1 = max(0, -di), nz - max(0, di)
        sj0, sj1 = max(0, -dj), nx - max(0, dj)
        shifted[si0:si1, sj0:sj1] = H[si0 + di:si1 + di, sj0 + dj:sj1 + dj]
        drop = (H - shifted).ravel() / dist
        idx = np.arange(H.size).reshape(H.shape)
        nb = np.full(H.shape, -1, dtype=np.int64)
        nb[si0:si1, sj0:sj1] = idx[si0 + di:si1 + di, sj0 + dj:sj1 + dj]
        better = drop > best
        best[better] = drop[better]
        recv[better] = nb.ravel()[better]
    for k in order:
        r = recv[k]
        if r >= 0:
            A[r] += A[k]
    return A.reshape(H.shape), best.reshape(H.shape)


def blur(H, n=1):
    for _ in range(n):
        P = np.pad(H, 1, mode="edge")
        H = (P[1:-1, 1:-1] * 4 + P[:-2, 1:-1] + P[2:, 1:-1] + P[1:-1, :-2] + P[1:-1, 2:]) / 8.0
    return H


def mesh_weight(xs, zs, mat):
    """0 inside the walkable valley, 1 out on the slopes; the Bay stays terrain."""
    X, Z = np.meshgrid(xs, zs)
    rs = np.sqrt((X / SX) ** 2 + Z ** 2)
    w = np.clip((rs - (SEAM - BLEND)) / BLEND, 0, 1)
    wet = (mat == "w") | (mat == "t") | (mat == "i") | (mat == "b") | (mat == "s")
    w[wet] = 0
    # the Bay flats and Hangar One: terrain
    bay = (X < -640) & (np.abs(Z) < 520) & (X > -1000)
    w[bay] = 0
    return w, rs, X, Z


def droplets(H, mask, n, rng, steps=48, inertia=0.05, capacity=5.0, min_cap=0.01, deposit=0.3,
             erode_rate=0.35, evaporate=0.02, gravity=4.0, batch=12000):
    """Particle hydraulic erosion (vectorised over a batch of drops). H is in
    CELL units of height. Drops start only where `mask` > 0 and carve by mask."""
    nz, nx = H.shape
    cand = np.argwhere(mask > 0.05)
    total = 0
    while total < n:
        m = min(batch, n - total)
        pick = cand[rng.integers(0, len(cand), m)]
        y = pick[:, 0] + rng.random(m)
        x = pick[:, 1] + rng.random(m)
        dx = np.zeros(m); dy = np.zeros(m)
        v = np.ones(m); w = np.ones(m); sed = np.zeros(m)
        alive = np.ones(m, dtype=bool)
        for _ in range(steps):
            ix = np.clip(np.floor(x).astype(np.int64), 0, nx - 2)
            iy = np.clip(np.floor(y).astype(np.int64), 0, nz - 2)
            fx = x - ix; fy = y - iy
            h00 = H[iy, ix]; h10 = H[iy, ix + 1]; h01 = H[iy + 1, ix]; h11 = H[iy + 1, ix + 1]
            gx = (h10 - h00) * (1 - fy) + (h11 - h01) * fy
            gy = (h01 - h00) * (1 - fx) + (h11 - h10) * fx
            h = h00 * (1 - fx) * (1 - fy) + h10 * fx * (1 - fy) + h01 * (1 - fx) * fy + h11 * fx * fy
            dx = dx * inertia - gx * (1 - inertia)
            dy = dy * inertia - gy * (1 - inertia)
            L = np.sqrt(dx * dx + dy * dy)
            still = L < 1e-6
            L[still] = 1
            dx /= L; dy /= L
            nxp = x + dx; nyp = y + dy
            alive &= (~still) & (nxp >= 0) & (nxp < nx - 1) & (nyp >= 0) & (nyp < nz - 1)
            nix = np.clip(np.floor(nxp).astype(np.int64), 0, nx - 2)
            niy = np.clip(np.floor(nyp).astype(np.int64), 0, nz - 2)
            nfx = nxp - nix; nfy = nyp - niy
            nh = (H[niy, nix] * (1 - nfx) * (1 - nfy) + H[niy, nix + 1] * nfx * (1 - nfy)
                  + H[niy + 1, nix] * (1 - nfx) * nfy + H[niy + 1, nix + 1] * nfx * nfy)
            dh = nh - h
            cap = np.maximum(-dh * v * w * capacity, min_cap)
            dep = np.where(dh > 0, np.minimum(dh, sed), np.where(sed > cap, (sed - cap) * deposit, 0.0))
            ero = np.where((dh <= 0) & (sed <= cap), np.minimum((cap - sed) * erode_rate, -dh), 0.0)
            k = mask[iy, ix]
            ero *= k
            delta = (dep - ero) * alive
            sed = np.minimum(sed - dep + ero, 8.0)
            # many drops in one batch can land on the same cell in the same step:
            # sum them, then cap each cell's net change (unbounded, they dug
            # pits that fed back to 1e48 -- measured)
            buf = np.zeros_like(H)
            for (oy, ox, wt) in ((0, 0, (1 - fx) * (1 - fy)), (0, 1, fx * (1 - fy)), (1, 0, (1 - fx) * fy), (1, 1, fx * fy)):
                np.add.at(buf, (iy + oy, ix + ox), delta * wt)
            np.clip(buf, -0.25, 0.25, out=buf)
            H += buf
            v = np.sqrt(np.maximum(0.0, v * v - dh * gravity))      # downhill speeds a drop up
            w *= (1 - evaporate)
            x = np.where(alive, nxp, x); y = np.where(alive, nyp, y)
            if not alive.any():
                break
        total += m
    return H


def erode(H, xs, zs, mat, rs):
    """Real hills have ridgelines and the branching ravines water cuts between
    them. Rough ridged detail first, then particle erosion. Both grow with
    distance past the seam (which must still match the terrain exactly)."""
    X, Z = np.meshgrid(xs, zs)
    strength = np.clip((rs - (SEAM + 20)) / 120, 0, 1)
    lx, lz, lr = LICK
    strength *= np.clip((np.sqrt((X - lx) ** 2 + (Z - lz) ** 2) - lr) / 60, 0, 1)
    idx = np.argwhere(strength > 0)
    det = np.zeros(H.shape)
    for (a, b) in idx:
        x, z = xs[b], zs[a]
        if abs(x) < 1050 and abs(z) < 850:
            # spurs at two scales so water has something to wind round (branching ravines, not stripes)
            det[a, b] = (fbm(x, z, 1 / 230.0, 5, 61, ridged=True) * 34 + fbm(x, z, 1 / 110.0, 4, 71, ridged=True) * 16
                         + fbm(x, z, 1 / 60.0, 3, 67) * 7)
        else:
            det[a, b] = fbm(x, z, 1 / 380.0, 4, 61, ridged=True) * 30 + fbm(x, z, 1 / 190.0, 3, 73) * 10
    tall = np.clip(H / 120.0, 0.25, 1.4)
    H = H + det * strength * tall
    H0 = H.copy()
    Hc = H / NEAR_STEP                                    # heights in cell units for the drops
    rng = np.random.default_rng(12)
    n = int((strength > 0.05).sum() * 3.5)
    Hc = droplets(Hc, strength, n, rng)
    H = Hc * NEAR_STEP
    # a whisper of smoothing on the CHANGE only: removes single-cell pits, keeps ravines
    d = blur(H - H0, 1)
    H = H0 + d
    # the backdrop is seen from 1,000+ studs at 32-stud spacing: broad and calm, never spiky
    far = ((np.abs(X) >= 1050) | (np.abs(Z) >= 850)).astype(np.float64)
    H = H * (1 - far) + blur(H, 3) * far
    A, _ = flow_accumulation(H)
    return H, A


# ------------------------------------------------------------------ 4. colour: what grows where
GOLD = c255(226, 186, 106)
GOLD_DRY = c255(236, 206, 138)
OAK = c255(58, 84, 44)
CHAP = c255(128, 128, 78)
RED = c255(40, 70, 48)
ROCK = c255(150, 138, 118)
WATER_EDGE = c255(120, 130, 96)


def colours(H, A, xs, zs, zone):
    X, Z = np.meshgrid(xs, zs)
    gz, gx = np.gradient(H, NEAR_STEP)
    slope = np.sqrt(gx ** 2 + gz ** 2)
    north = np.clip(-gz / (slope + 1e-6), -1, 1)           # +z is north in this map
    la = np.log1p(A)
    ref = la[zone] if zone.any() else la.ravel()
    lo, hi = np.percentile(ref, 45), np.percentile(ref, 90)
    wet = np.clip((la - lo) / max(1e-6, hi - lo), 0, 1)     # 0 on the spurs, 1 down the gullies
    dry = np.clip((H - 80) / 240, 0, 1)
    col = GOLD[None, None, :] * (1 - dry[..., None]) + GOLD_DRY[None, None, :] * dry[..., None]
    patch = np.vectorize(lambda x, z: noise.noise(Vector((x / 110.0, z / 110.0, 5.0))))(X, Z)
    wood = np.clip(wet * 1.0 + np.clip(north, 0, 1) * 0.35 * np.clip(slope * 2, 0, 1) + patch * 0.35 - 0.5, 0, 1)
    wood = np.clip(wood * 2.0, 0, 1)          # ~a third of a slope is oak woodland, the rest golden grass
    col = col * (1 - wood[..., None]) + OAK[None, None, :] * wood[..., None]
    chap = np.clip((slope - 0.45) * 1.8, 0, 1) * (1 - wood) * 0.55
    col = col * (1 - chap[..., None]) + CHAP[None, None, :] * chap[..., None]
    south = np.clip((-Z - 520) / 260, 0, 1) * np.clip((H - 110) / 70, 0, 1)
    col = col * (1 - south[..., None]) + RED[None, None, :] * south[..., None]
    rock = np.clip((slope - 1.05) * 2.2, 0, 1)
    col = col * (1 - rock[..., None]) + ROCK[None, None, :] * rock[..., None]
    var = np.vectorize(lambda x, z: noise.noise(Vector((x / 300.0, z / 300.0, 9.0))))(X, Z)
    col *= (1 + 0.08 * var)[..., None]
    return np.clip(col, 0, 1), wood, south, slope


# ------------------------------------------------------------------ 5. tiles
META = {}


def build_tile(name, xs, zs, H, C, keep, i0, i1, j0, j1, stride, sink):
    """Grid mesh over [i0:i1, j0:j1] with the given stride; only quads with a kept
    corner. Roblox (X,Y,Z) -> Blender (-X, Z, Y)."""
    bm = bmesh.new()
    col_layer = bm.loops.layers.color.new("Col")
    vid = {}
    rows = list(range(i0, i1 + 1, stride))
    cols = list(range(j0, j1 + 1, stride))
    if rows[-1] != i1 and i1 < H.shape[0]:
        rows.append(min(i1, H.shape[0] - 1))
    if cols[-1] != j1 and j1 < H.shape[1]:
        cols.append(min(j1, H.shape[1] - 1))
    rows = [r for r in rows if r < H.shape[0]]
    cols = [c for c in cols if c < H.shape[1]]
    for a in rows:
        for b in cols:
            y = H[a, b] - sink[a, b]
            vid[(a, b)] = bm.verts.new((-xs[b], zs[a], y))
    faces = 0
    for ia in range(len(rows) - 1):
        for ib in range(len(cols) - 1):
            a0, a1, b0, b1 = rows[ia], rows[ia + 1], cols[ib], cols[ib + 1]
            if not (keep[a0, b0] or keep[a0, b1] or keep[a1, b0] or keep[a1, b1]):
                continue
            quad = [(a0, b0), (a1, b0), (a1, b1), (a0, b1)]
            f = bm.faces.new([vid[q] for q in quad])
            for loop, q in zip(f.loops, quad):
                c = C[q[0], q[1]]
                loop[col_layer] = (c[0], c[1], c[2], 1.0)
            faces += 1
    if faces == 0:
        bm.free()
        return None
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.01)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # every face must point UP in Roblox (Blender +Z)
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    for p in me.polygons:
        p.use_smooth = True
    # Blender stores colours as linear floats in the byte layer? convert: we wrote sRGB-ish
    mins = [min(v.co[k] for v in me.vertices) for k in range(3)]
    maxs = [max(v.co[k] for v in me.vertices) for k in range(3)]
    c = [(mins[k] + maxs[k]) / 2 for k in range(3)]
    s = [maxs[k] - mins[k] for k in range(3)]
    META[name] = dict(c=(-c[0], c[2], c[1]), s=(s[0], s[2], s[1]), tris=len(me.polygons) * 2)
    return o


def export(o, path):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, apply_unit_scale=True, apply_scale_options="FBX_SCALE_ALL",
                             global_scale=1.0, mesh_smooth_type="OFF", use_mesh_modifiers=True, colors_type="SRGB",
                             add_leaf_bones=False, bake_anim=False, axis_forward="-Z", axis_up="Y")


def main():
    K.reset()
    xs, zs, H, W, mat = build_field()
    w, rs, X, Z = mesh_weight(xs, zs, mat)
    H, A = erode(H, xs, zs, mat, rs)
    C, wood, south, slope = colours(H, A, xs, zs, w > 0.5)
    np.save(os.path.join(OUT, "mountain_h.npy"), H)
    keep = w > 0.0
    # in the overlap band the mesh sits 0.8 under the terrain, so the terrain wins there
    sink = np.where(w < 1.0, 0.8, 0.0)
    nz, nx = H.shape
    tiles = []
    # inner ring (inside the sampled box): 512-stud tiles at full detail;
    # the backdrop: 1024-stud tiles at 24-stud detail, skipping what the inner tiles cover
    T, TO = 64, 128
    stride_o = FAR_STEP // NEAR_STEP
    covered = np.zeros(H.shape, dtype=bool)
    for i0 in range(0, nz - 1, T):
        for j0 in range(0, nx - 1, T):
            i1, j1 = min(i0 + T, nz - 1), min(j0 + T, nx - 1)
            zc, xc = zs[(i0 + i1) // 2], xs[(j0 + j1) // 2]
            if not (abs(xc) < 1050 and abs(zc) < 850):
                continue
            covered[i0:i1, j0:j1] = True
            name = "Mtn_%d_%d" % (i0 // T, j0 // T)
            o = build_tile(name, xs, zs, H, C, keep, i0, i1, j0, j1, 1, sink)
            if o:
                export(o, os.path.join(IMP, name + ".fbx"))
                tiles.append(o)
    keep_o = keep & ~covered
    for i0 in range(0, nz - 1, TO):
        for j0 in range(0, nx - 1, TO):
            i1, j1 = min(i0 + TO, nz - 1), min(j0 + TO, nx - 1)
            if not keep_o[i0:i1 + 1, j0:j1 + 1].any():
                continue
            name = "Far_%d_%d" % (i0 // TO, j0 // TO)
            o = build_tile(name, xs, zs, H, C, keep_o, i0, i1, j0, j1, stride_o, sink)
            if o:
                export(o, os.path.join(IMP, name + ".fbx"))
                tiles.append(o)
    # trees for the mesh slopes: oaks in the woodland, redwoods on the southern crest
    rng = random.Random(4)
    trees = []
    tries = 0
    while len(trees) < 420 and tries < 60000:
        tries += 1
        a, b = rng.randrange(nz), rng.randrange(nx)
        if w[a, b] < 1 or rs[a, b] > 1500:
            continue
        kind = None
        if south[a, b] > 0.55 and rng.random() < 0.9:
            kind = "Redwood_A"
        elif wood[a, b] > 0.55 and rng.random() < 0.8:
            kind = "Oak_A" if rng.random() < 0.5 else "Oak_B"
        if not kind:
            continue
        x, z, y = xs[b] + rng.uniform(-3, 3), zs[a] + rng.uniform(-3, 3), H[a, b] - 0.6
        if any((x - t[0]) ** 2 + (z - t[2]) ** 2 < 144 for t in trees[-60:]):
            continue
        trees.append((x, y, z, kind))
    with open(os.path.join(OUT, "mountains_meta.lua"), "w") as f:
        f.write("-- generated by blender/mountains.py: plot-free world placement of each mountain tile\n")
        f.write("return {\n\tseam = %.1f, blend = %.1f, stretchX = %.2f,\n\ttiles = {\n" % (SEAM, BLEND, SX))
        for k in sorted(META):
            m = META[k]
            f.write("\t\t%s = { c = Vector3.new(%.2f, %.2f, %.2f), s = Vector3.new(%.2f, %.2f, %.2f) },  -- %d tris\n"
                    % (k, *m["c"], *m["s"], m["tris"]))
        f.write("\t},\n\ttrees = {\n")
        for (x, y, z, kind) in trees:
            f.write("\t\t{ %.1f, %.1f, %.1f, \"%s\" },\n" % (x, y, z, kind))
        f.write("\t},\n}\n")
    total = sum(m["tris"] for m in META.values())
    print("MOUNTAINS tiles %d tris %d trees %d" % (len(META), total, len(trees)))
    return tiles


main()
