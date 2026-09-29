"""ui_scan.py: static scan of the UI code (the code half of the deterministic audit).

Counts, per file: hard-coded colours outside UIKit, fonts, text sizes, easing
styles, corner radii, and user-facing strings with em dashes or double hyphens.
Run from game/: python tools/ui_scan.py
"""
import collections
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent / "src"
FILES = sorted(list((ROOT / "StarterPlayer" / "StarterPlayerScripts").glob("*.lua"))
               + [ROOT / "ReplicatedStorage" / "UIKit.lua", ROOT / "ReplicatedStorage" / "Notify.lua",
                  ROOT / "ReplicatedStorage" / "Cine.lua"])
SKIP = {"LifeClient", "TrafficClient", "TreeCullClient", "SkyClient", "StaffAnimClient", "RocketClient", "ClientInfoClient"}

rgb = re.compile(r"Color3\.fromRGB\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)")
font = re.compile(r"Enum\.Font\.(\w+)|Font\.fromName\(\"(\w+)\"|UIKit\.(HEAD|BODY|BOLD)\b")
tsize = re.compile(r"TextSize\s*=\s*(\d+)|UIKit\.(?:label|heading|outlined)\([^,]+,[^,]+,\s*(\d+)")
ease = re.compile(r"EasingStyle\.(\w+)")
corner = re.compile(r"CornerRadius\s*=\s*UDim\.new\(\s*([\d.]+)\s*,\s*(\d+)\s*\)")
string = re.compile(r'"([^"\n]{3,})"')

tot = collections.Counter()
fonts = collections.Counter()
sizes = collections.Counter()
eases = collections.Counter()
corners = collections.Counter()
colours = collections.Counter()
dash = []
per_file = []
for f in FILES:
    name = f.stem.replace(".client", "")
    if name in SKIP:
        continue
    src = f.read_text(encoding="utf-8")
    lines = src.splitlines()
    n_rgb = 0
    for i, line in enumerate(lines, 1):
        code = line.split("--", 1)[0] if not line.strip().startswith("--") else ""
        for m in rgb.finditer(code):
            n_rgb += 1
            colours[m.group(0).replace(" ", "")] += 1
        for m in font.finditer(code):
            fonts[m.group(1) or m.group(2) or ("UIKit." + m.group(3))] += 1
        for m in tsize.finditer(code):
            sizes[int(m.group(1) or m.group(2))] += 1
        for m in ease.finditer(code):
            eases[m.group(1)] += 1
        for m in corner.finditer(code):
            corners[("scale " + m.group(1)) if float(m.group(1)) > 0 else (m.group(2) + "px")] += 1
        for m in string.finditer(code):
            s = m.group(1)
            if ("—" in s or " -- " in s or "–" in s) and not s.startswith("rbxasset"):
                dash.append(f"{name}:{i}  {s[:70]}")
    per_file.append((name, len(lines), n_rgb))
    tot["lines"] += len(lines)
    tot["rgb"] += n_rgb

print(f"files {len(per_file)}  lines {tot['lines']}  hard-coded fromRGB {tot['rgb']}")
print("per file (lines, fromRGB):")
for name, n, r in sorted(per_file, key=lambda x: -x[2]):
    print(f"  {name:22s} {n:5d}  {r:3d}")
print("fonts:", dict(fonts.most_common()))
print("text sizes:", dict(sorted(sizes.items())))
print("easing:", dict(eases.most_common()))
print("corner radii:", dict(corners.most_common()))
print(f"distinct hard-coded colours: {len(colours)}; top 15:")
for c, n in colours.most_common(15):
    print(f"  {n:3d}  {c}")
print(f"strings with dashes: {len(dash)}")
for d in dash[:30]:
    print("  " + d)
