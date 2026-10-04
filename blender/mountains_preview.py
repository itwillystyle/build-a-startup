"""Preview the mountain tiles from the campus (Cycles, sun + sky + haze).
Run: blender -b --python mountains_preview.py"""
import bpy
import glob
import math
import os
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
prefs = bpy.context.preferences.addons["cycles"].preferences
prefs.compute_device_type = "OPTIX"
prefs.get_devices()
for d in prefs.devices:
    d.use = (d.type == "OPTIX")
sc.cycles.device = "GPU"
sc.cycles.samples = 48
sc.cycles.use_denoising = True
sc.render.resolution_x, sc.render.resolution_y = 1600, 700
sc.view_settings.view_transform = "Standard"

m = bpy.data.materials.new("VC")
m.use_nodes = True
nt = m.node_tree
p = nt.nodes["Principled BSDF"]
p.inputs["Roughness"].default_value = 0.95
vc = nt.nodes.new("ShaderNodeVertexColor")
vc.layer_name = "Col"
nt.links.new(vc.outputs["Color"], p.inputs["Base Color"])
for f in sorted(glob.glob(os.path.join(OUT, "IMPORT_MOUNTAINS", "*.fbx"))):
    bpy.ops.import_scene.fbx(filepath=f)
    for o in bpy.context.selected_objects:
        if o.type == "MESH":
            o.data.materials.clear()
            o.data.materials.append(m)
            if o.data.color_attributes:
                vc.layer_name = o.data.color_attributes[0].name
# the valley floor, roughly
bpy.ops.mesh.primitive_plane_add(size=1700, location=(0, 0, -1))
g = bpy.context.active_object
gm = bpy.data.materials.new("G")
gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.36, 0.45, 0.2, 1)
g.data.materials.append(gm)
# sky, sun, haze
w = bpy.data.worlds.new("W")
sc.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.5, 0.64, 0.86, 1)
w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
sd = bpy.data.lights.new("Sun", "SUN")
sd.energy = 3.2
sun = bpy.data.objects.new("Sun", sd)
sc.collection.objects.link(sun)
sun.rotation_euler = (math.radians(55), 0, math.radians(-150))
vol = nt  # no volume: use mist pass-free approach -> a simple world-colour fog via compositor is overkill
cd = bpy.data.cameras.new("C")
cd.lens = 28
cd.clip_end = 8000
cam = bpy.data.objects.new("C", cd)
sc.collection.objects.link(cam)
sc.camera = cam


def shot(rx, ry, rz, lx, ly, lz, name):
    # Roblox (X, Y, Z) -> Blender (-X, Z, Y)
    cam.location = Vector((-rx, rz, ry))
    target = Vector((-lx, lz, ly))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(OUT, name)
    bpy.ops.render.render(write_still=True)


shot(0, 30, 140, 0, 90, 900, "mtn_north.png")
shot(0, 30, -140, 0, 90, -900, "mtn_south.png")
shot(300, 30, 0, 1200, 90, 0, "mtn_east.png")
