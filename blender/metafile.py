"""Write the HQ mesh metadata straight into the Rojo source tree (v4.2).

hq.py and hq2.py are often run for ONE level ("-- 5"), so a run must MERGE into
the module instead of replacing it: entries for the meshes built this run are
rewritten, every other entry is kept as it was. No bpy here, so it can be
tested with plain Python.
"""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
import gamedir  # noqa: E402

# resolved by walking up for src/ServerScriptService, not by a fixed hop, so a
# reorganised repo cannot silently write the metadata where nothing reads it
META_DIR = os.path.join(gamedir.server_dir(HERE), "HQMeta")
ROW = re.compile(r"^\t(\w+) = (\{.*)$")


def row(name, m):
    return "\t%s = { c = Vector3.new(%.3f, %.3f, %.3f), s = Vector3.new(%.3f, %.3f, %.3f) },  -- %d tris" % (
        name, m["c"][0], m["c"][1], m["c"][2], m["s"][0], m["s"][1], m["s"][2], m["tris"])


def write(module, header, meta):
    """module: "V1" or "V2". meta: {name: {"c": (x,y,z), "s": (x,y,z), "tris": n}}."""
    path = os.path.join(META_DIR, module + ".lua")
    rows = {}
    if os.path.exists(path):
        for line in open(path, encoding="utf-8").read().split("\n"):
            m = ROW.match(line)
            if m:
                rows[m.group(1)] = line
    for name, m in meta.items():
        rows[name] = row(name, m)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("-- " + header + "\n")
        f.write("-- generated: plot-local bbox centre (c) and size (s) of each mesh. Rerun the Blender script, don't edit.\n")
        f.write("return {\n")
        for name in sorted(rows):
            f.write(rows[name] + "\n")
        f.write("}\n")
    return path
