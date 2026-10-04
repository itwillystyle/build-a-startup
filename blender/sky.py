"""sky.py -- PLAN v6 phase V6: the valley's own skybox (27 Sep 2026).

A Nishita physical sky (California haze: dust up, a high sun so no single
direction glows -- the game's sun MOVES, 22-minute day, and a painted sun or a
painted glow would sit in the wrong place for most of it) plus stylised
cumulus in a band just above the horizon: flat bottoms, soft tops, the same
"architect's model" softness as everything else. Golden hour and night are
the game's job (SkyClient tints the Atmosphere and swaps the skybox out at
night); this is the daytime canvas they tint.

Face mapping was MEASURED in Studio (27 Sep) with six asymmetric icons, each
face seen from inside the box:
  Ft  looks -Z   image right = +X   image up = +Y
  Bk  looks +Z   image right = -X   image up = +Y
  Rt  looks -X   image right = -Z   image up = +Y      (Rt is at -X, Lf at +X:
  Lf  looks +X   image right = +Z   image up = +Y       the names mislead)
  Up  looks +Y   image right = +X   image up = -Z
  Dn  a flat haze colour, so its orientation cannot matter
Roblox -> Blender here is (x, y, z) -> (x, -z, y).

Run:  blender -b --python sky.py            (faces -> out/sky/)
      blender -b --python sky.py -- pano    (one equirect preview)
"""
import bpy
import math
import os
import random
import sys
from mathutils import Vector, Matrix

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "sky")
os.makedirs(OUT, exist_ok=True)
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

SUN_EL, SUN_AZ = 86.0, 215.0        # degrees: overhead, so the sky's glow sits where nobody looks and never argues with the game's moving sun
SIZE = 1024


def rb(x, y, z):
    """Roblox direction -> Blender."""
    return Vector((x, -z, y))


FACES = {
    "Ft": (rb(0, 0, -1), rb(1, 0, 0), rb(0, 1, 0)),
    "Bk": (rb(0, 0, 1), rb(-1, 0, 0), rb(0, 1, 0)),
    "Rt": (rb(-1, 0, 0), rb(0, 0, -1), rb(0, 1, 0)),
    "Lf": (rb(1, 0, 0), rb(0, 0, 1), rb(0, 1, 0)),
    "Up": (rb(0, 1, 0), rb(1, 0, 0), rb(0, 0, -1)),
}

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
prefs = bpy.context.preferences.addons["cycles"].preferences
prefs.compute_device_type = "OPTIX"
prefs.get_devices()
for d in prefs.devices:
    d.use = (d.type == "OPTIX")
scene.cycles.device = "GPU"
scene.cycles.samples = 96
scene.cycles.use_denoising = True
scene.view_settings.view_transform = "Standard"   # rendered dark so nothing clips; sky_post.py lifts it (Filmic/AgX greyed the blue)
try:
    scene.view_settings.look = "None"
except TypeError:
    pass
scene.view_settings.exposure = -1.8

# ------------------------------------------------------------------ the sky
world = bpy.data.worlds.new("Sky")
scene.world = world
world.use_nodes = True
nt = world.node_tree
bg = nt.nodes["Background"]
sky = nt.nodes.new("ShaderNodeTexSky")
sky.sky_type = "NISHITA"
sky.sun_disc = False
sky.sun_elevation = math.radians(SUN_EL)
sky.sun_rotation = math.radians(SUN_AZ)
sky.altitude = 120.0
sky.air_density = 1.0
sky.dust_density = 0.45         # a light valley haze (2.6 read as overcast, 1.1 blew a white blob round the sun)
sky.ozone_density = 1.0
nt.links.new(sky.outputs["Color"], bg.inputs["Color"])
bg.inputs["Strength"].default_value = 0.55

# ------------------------------------------------------------------ the sun (lights the clouds)
sun_dir = Vector((math.cos(math.radians(SUN_EL)) * math.sin(math.radians(SUN_AZ)),
                  -math.cos(math.radians(SUN_EL)) * math.cos(math.radians(SUN_AZ)),
                  math.sin(math.radians(SUN_EL))))
sd = bpy.data.lights.new("Sun", "SUN")
sd.energy = 3.2
sd.angle = math.radians(6)
sd.color = (1.0, 0.96, 0.9)
sun = bpy.data.objects.new("Sun", sd)
scene.collection.objects.link(sun)
sun.rotation_euler = (-sun_dir).to_track_quat("-Z", "Y").to_euler()

# ------------------------------------------------------------------ cumulus
mat = bpy.data.materials.new("Cloud")
mat.use_nodes = True
p = mat.node_tree.nodes["Principled BSDF"]
p.inputs["Base Color"].default_value = (0.93, 0.93, 0.95, 1)
p.inputs["Roughness"].default_value = 1.0
try:
    p.inputs["Subsurface Weight"].default_value = 0.25
    p.inputs["Subsurface Radius"].default_value = (40, 40, 40)
    p.inputs["Emission Color"].default_value = (0.78, 0.8, 0.86, 1)
    p.inputs["Emission Strength"].default_value = 0.4    # brighter whites (sides were grey under an overhead sun)
except KeyError:
    pass

rng = random.Random(7)
R = 2600.0


def cluster(az, el, size):
    """A cumulus: metaballs (they merge smoothly -- overlapping spheres showed
    hard creases, bubble wrap), converted to a mesh, the bottom planed flat."""
    c = Vector((math.cos(el) * math.sin(az), -math.cos(el) * math.cos(az), math.sin(el))) * R
    tangent = Vector((math.cos(az), math.sin(az), 0))          # along the horizon
    mb = bpy.data.metaballs.new("Cu")
    mb.resolution = size / 14.0
    mb.render_resolution = size / 14.0
    mb.threshold = 0.6
    o = bpy.data.objects.new("Cu", mb)
    scene.collection.objects.link(o)
    o.location = c
    n = rng.randint(7, 11)
    for k in range(n):
        t = (k / max(1, n - 1) - 0.5) * 2
        r = size * rng.uniform(0.5, 0.8) * (1.0 - 0.35 * abs(t))
        off = tangent * (t * size * 0.8 + rng.uniform(-0.08, 0.08) * size)
        off += Vector((0, 0, r * rng.uniform(0.05, 0.5)))
        off += c.normalized() * rng.uniform(-0.25, 0.25) * size
        e = mb.elements.new()
        e.co = off
        e.radius = r
    # the domed tops: two or three puffs stacked over the middle
    for _ in range(rng.randint(2, 3)):
        e = mb.elements.new()
        e.co = tangent * rng.uniform(-0.35, 0.35) * size + Vector((0, 0, size * rng.uniform(0.35, 0.6)))
        e.radius = size * rng.uniform(0.45, 0.62)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.convert(target="MESH")
    m = bpy.context.active_object
    base_z = c.z - size * 0.1
    for v in m.data.vertices:
        w = m.matrix_world @ v.co
        if w.z < base_z:
            w.z = base_z + (w.z - base_z) * 0.06
            v.co = m.matrix_world.inverted() @ w
    m.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return m


# a band of cumulus just above the hills (they rise ~18 degrees from the
# campus), thicker in the west over the bay where the horizon is open
az = 0.0
while az < 360:
    west = 1.0 + 0.5 * max(0.0, math.cos(math.radians(az - 270)))
    lo = 2.0 if abs(((az - 270 + 180) % 360) - 180) < 50 else 9.0
    el = rng.uniform(lo, lo + 12.0)
    size = rng.uniform(220, 460) * west
    cluster(math.radians(az), math.radians(el), size)
    if rng.random() < 0.45:      # a second, smaller cloud tucked behind: depth in the band
        cluster(math.radians(az + rng.uniform(4, 9)), math.radians(el + rng.uniform(2.0, 5.0)), size * 0.55)
    az += rng.uniform(14, 30) / west
# fair-weather cumulus higher up
for _ in range(14):
    cluster(math.radians(rng.uniform(0, 360)), math.radians(rng.uniform(24, 46)), rng.uniform(160, 300))

# ------------------------------------------------------------------ camera
cd = bpy.data.cameras.new("Cam")
cam = bpy.data.objects.new("Cam", cd)
scene.collection.objects.link(cam)
scene.camera = cam
cam.location = (0, 0, 0)
cd.clip_end = 20000

if "pano" in ARGS:
    cd.type = "PANO"
    try:
        cd.panorama_type = "EQUIRECTANGULAR"
    except AttributeError:
        cd.cycles.panorama_type = "EQUIRECTANGULAR"
    cam.rotation_euler = (math.radians(90), 0, 0)
    scene.render.resolution_x, scene.render.resolution_y = 2048, 1024
    scene.render.filepath = os.path.join(OUT, "pano.png")
    bpy.ops.render.render(write_still=True)
else:
    cd.type = "PERSP"
    cd.angle = math.radians(90)
    cd.sensor_fit = "HORIZONTAL"
    scene.render.resolution_x = scene.render.resolution_y = SIZE
    for name, (d, right, up) in FACES.items():
        back = -d
        m = Matrix((right, up, back)).transposed()
        cam.rotation_euler = m.to_euler()
        scene.render.filepath = os.path.join(OUT, "raw_%s.png" % name)
        bpy.ops.render.render(write_still=True)
print("SKY DONE")
