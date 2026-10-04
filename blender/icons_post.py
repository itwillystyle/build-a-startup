"""icons_post.py -- finish icons.py renders: trim, sticker outline, 256 px.

The outline is what makes a rendered icon read on a saturated button at
40-60 px (the same job UIStroke does on the FredokaOne labels). Ink colour,
~3 px at 256. Also writes check_sheet.png: every icon on its real button
colour, at the size the HUD draws it, to judge before uploading.
Run:  python icons_post.py
"""
import os
from PIL import Image, ImageFilter

D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "icons")
INK = (30, 37, 48)
import sys
KEYS = sys.argv[1:] or ["phone", "bag", "grid", "home", "musicOn", "code", "rocket", "target", "coin"]
BUTTON = {"phone": (76, 196, 108), "bag": (246, 134, 58), "grid": (70, 140, 230), "home": (255, 194, 61),
          "musicOn": (243, 239, 230), "code": (76, 196, 108), "rocket": (76, 196, 108), "target": (243, 239, 230),
          "coin": (40, 44, 52), "hire": (243, 239, 230), "hq": (243, 239, 230), "key": (243, 239, 230),
          "car": (243, 239, 230), "office": (243, 239, 230), "studio": (243, 239, 230), "cafe": (243, 239, 230),
          "servers": (243, 239, 230), "check": (243, 239, 230), "gift": (243, 239, 230), "trophy": (243, 239, 230)}


def finish(key):
    im = Image.open(os.path.join(D, "raw_%s.png" % key)).convert("RGBA")
    # separate the object from its soft shadow: the shadow is dark and translucent
    a = im.getchannel("A")
    # the shadow is translucent: keep it as a light touch (35%) and frame the OBJECT
    im.putalpha(a.point(lambda v: v if v > 200 else int(v * 0.35)))
    bbox = a.point(lambda v: 255 if v > 200 else 0).getbbox()
    m = int(max(bbox[2] - bbox[0], bbox[3] - bbox[1]) * 0.06)
    bbox = (max(0, bbox[0] - m), max(0, bbox[1] - m), min(im.width, bbox[2] + m), min(im.height, bbox[3] + m))
    im = im.crop(bbox)
    side = max(im.size)
    pad = int(side * 0.06)
    sq = Image.new("RGBA", (side + 2 * pad, side + 2 * pad), (0, 0, 0, 0))
    sq.paste(im, ((sq.width - im.width) // 2, (sq.height - im.height) // 2))
    # outline from the SOLID object only (alpha > 200), not the translucent shadow
    solid = sq.getchannel("A").point(lambda v: 255 if v > 200 else 0)
    ring = solid.filter(ImageFilter.MaxFilter(13)).filter(ImageFilter.GaussianBlur(1.2))
    out = Image.new("RGBA", sq.size, INK + (0,))
    out.putalpha(ring)
    out.alpha_composite(sq)
    out = out.resize((256, 256), Image.LANCZOS)
    out.save(os.path.join(D, "SV_Icon_%s.png" % key))
    return out


icons = {k: finish(k) for k in KEYS}
cell = 150
sheet = Image.new("RGBA", (cell * len(KEYS), cell * 2), (250, 248, 244, 255))
for i, k in enumerate(KEYS):
    # top row: on its button colour at 64 px (the rail size); bottom: 128 px on paper
    bg = Image.new("RGBA", (cell - 20, cell - 20), BUTTON[k] + (255,))
    sheet.alpha_composite(bg, (i * cell + 10, 10))
    sheet.alpha_composite(icons[k].resize((96, 96), Image.LANCZOS), (i * cell + 27, 27))
    sheet.alpha_composite(icons[k].resize((128, 128), Image.LANCZOS), (i * cell + 11, cell + 11))
sheet.convert("RGB").save(os.path.join(D, "check_sheet.png"))
print("done", list(icons))
