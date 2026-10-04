"""sky_post.py -- finish the six skybox faces rendered by sky.py.

sky.py renders dark on purpose (Standard view, exposure -1.8) so nothing clips.
Here: lift the midtones (gamma 0.72) and saturation (x1.12), which rolls the
bright zenith off instead of burning it white, then paint below the horizon.
Nishita draws the ground as black; the game shows the skybox below the horizon
wherever the map ends (the bay, the east edge), so the four side faces get the
colour just above the horizon carried down and blended into one shared haze,
and Dn is that haze flat (its orientation then cannot matter).
Run:  python sky_post.py   (reads out/sky/raw_*.png, writes out/sky/SV_Sky_*.png)
"""
import os
import numpy as np
from PIL import Image, ImageEnhance

D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "sky")
SIDES = ["Ft", "Rt", "Bk", "Lf"]


def load(name):
    return np.asarray(Image.open(os.path.join(D, "raw_%s.png" % name)).convert("RGB")).astype(np.float64) / 255.0


def grade(a):
    a = np.clip(a, 0, 1) ** 0.72
    img = Image.fromarray((a * 255).astype(np.uint8))
    img = ImageEnhance.Color(img).enhance(1.12)
    return np.asarray(img).astype(np.float64) / 255.0


faces = {n: grade(load(n)) for n in SIDES + ["Up"]}
H = faces["Ft"].shape[0]
hz = H // 2
# the shared haze: the average colour a few rows above the horizon, a touch darker and warmer
ring = np.concatenate([faces[n][hz - 4] for n in SIDES])
# half the horizon colour, half SkyClient's daytime Atmosphere colour (214,210,200), so the map edge blends
haze = 0.5 * ring.mean(axis=0) + 0.5 * np.array([214, 210, 200]) / 255.0
for n in SIDES:
    a = faces[n].copy()
    edge = a[hz - 3].copy()                      # per column, so neighbouring faces meet
    for y in range(hz - 2, H):
        t = min(1.0, max(0.0, (y - (hz - 2)) / 60.0))
        a[y] = edge * (1 - t) + haze * t
    faces[n] = a
for n, a in faces.items():
    Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).save(os.path.join(D, "SV_Sky_%s.png" % n))
dn = np.ones((256, 256, 3)) * haze
Image.fromarray((dn * 255).astype(np.uint8)).save(os.path.join(D, "SV_Sky_Dn.png"))

# a strip for checking the seams by eye: Ft | Lf | Bk | Rt going round (+X is Lf)
order = ["Rt", "Ft", "Lf", "Bk"]         # looking -X, -Z, +X, +Z = turning right
strip = np.concatenate([faces[n] for n in order], axis=1)
Image.fromarray((strip * 255).astype(np.uint8)).resize((2048, 512)).save(os.path.join(D, "check_strip.png"))
print("haze", (haze * 255).round(), "faces", list(faces) + ["Dn"])
