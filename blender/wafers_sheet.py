"""wafers_sheet.py -- the contact sheet for the Wafers mesh kit (system python + PIL).

Reads art/concepts/wafers_kit/*.png, thumbs/ and stats.json (written by
wafers_render.py) and writes art/concepts/wafers_kit/kit_sheet.png.
Run:  python wafers_sheet.py
"""
import json
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(os.path.dirname(HERE), "art", "concepts", "wafers_kit")
PAPER = (243, 239, 230)
INK = (30, 37, 48)
MUTED = (104, 110, 122)
ACCENT = (240, 110, 80)
RULE = (214, 206, 192)
W = 2480
M = 40          # page margin
G = 16          # gap


def font(bold, size):
    try:
        return ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf" if bold else "C:/Windows/Fonts/segoeui.ttf", size)
    except OSError:
        return ImageFont.load_default()


F_T, F_H, F_B, F_S, F_SB = font(True, 64), font(True, 30), font(False, 24), font(False, 21), font(True, 21)


def load(name):
    p = os.path.join(ART, name)
    return Image.open(p).convert("RGB") if os.path.exists(p) else None


def row(page, draw, y, items, cap_h=40):
    """items: [(image, caption)]; scaled to one height so the row fills the page width."""
    items = [(im, c) for im, c in items if im is not None]
    aspect = sum(im.width / im.height for im, _ in items)
    h = int((W - 2 * M - G * (len(items) - 1)) / aspect)
    x = M
    for im, cap in items:
        w = int(h * im.width / im.height)
        draw.text((x, y), cap, fill=INK, font=F_SB)
        page.paste(im.resize((w, h), Image.LANCZOS), (x, y + cap_h))
        x += w + G
    return y + cap_h + h + 34


def main():
    st = json.load(open(os.path.join(ART, "stats.json")))
    lv = st["levels"]
    meshes = st["meshes"]
    thumbs = json.load(open(os.path.join(ART, "thumbs", "thumbs.json")))
    page = Image.new("RGB", (W, 6400), PAPER)
    d = ImageDraw.Draw(page)
    y = M
    d.text((M, y), "THE WAFERS  ·  the mesh kit", fill=INK, font=F_T)
    y += 86
    d.text((M, y), "Round wafers (one segment mesh repeats 8 times a storey), ribbon windows over paper spandrels, oak soffits, "
                   "garden decks with a running track, a glass lift in the courtyard.", fill=MUTED, font=F_B)
    y += 36
    d.text((M, y), "Every picture is the EXPORTED FBX, re-imported and placed with the game's rule "
                   "(pieceFrame * CFrame.new(meta.c), meta from HQMeta/Wafers.lua). Glass: lit from inside, tinted by department.",
           fill=MUTED, font=F_B)
    y += 50
    d.line((M, y, W - M, y), fill=RULE, width=2)
    y += 24

    def cap(L):
        s = lv.get(str(L))
        return "LEVEL %d  ·  %s tris  ·  %s studs tall" % (L, format(s["tris"], ","), s["height"]) if s else "LEVEL %d" % L
    d.text((M, y), "Same camera for all four", fill=ACCENT, font=F_H)
    y += 46
    y = row(page, d, y, [(load("L%03d_aerial.png" % L), cap(L)) for L in (5, 18, 43, 100)])
    d.text((M, y), "From the plaza (camera 6.5 studs up, 80 in front of the lobby, 70-degree FOV)", fill=ACCENT, font=F_H)
    y += 46
    y = row(page, d, y, [(load("L018_plaza.png"), "Level 18: company 1's finished HQ (wafer 1 + garden deck 1)"),
                         (load("L100_plaza.png"), "Level 100")])
    d.text((M, y), "Closer", fill=ACCENT, font=F_H)
    y += 46
    y = row(page, d, y, [(load("L005_close.png"), "Level 5: the lobby and 3 segments round the garage"),
                         (load("L018_close.png"), "Level 18: the lift stops at the deck, capped"),
                         (load("L100_top.png"), "Level 100: roof garden, pavilion, halo, lantern, mast"),
                         (load("L100_back.png"), "Level 100 from the back: cantilevers, deck columns")])
    y = row(page, d, y, [(load("part_segment.png"), "One segment, 2 storeys: end partition + door"),
                         (load("part_lobby.png"), "Lobby: 14 x 10 passage, floating canopy"),
                         (load("part_courtyard.png"), "Courtyard: bridge door, lift, skybridge"),
                         (load("L043_court.png"), "Level 43 courtyard: bridges to wafer 2, deck 1")])
    d.line((M, y - 10, W - M, y - 10), fill=RULE, width=2)
    d.text((M, y), "The kit", fill=ACCENT, font=F_H)
    y += 50
    cols, tw = 6, (W - 2 * M - 5 * G) // 6
    th = int(tw * 480 / 640)
    for i, t in enumerate(thumbs):
        cx = M + (i % cols) * (tw + G)
        cy = y + (i // cols) * (th + 90)
        im = Image.open(os.path.join(ART, "thumbs", t["file"])).convert("RGBA").resize((tw, th), Image.LANCZOS)
        page.paste(im, (cx, cy), im)
        name, _, rest = t["label"].partition("  ")
        d.text((cx, cy + th + 2), name, fill=INK, font=F_SB)
        d.text((cx, cy + th + 28), rest, fill=MUTED, font=F_S)
        d.text((cx, cy + th + 52), "%s tris" % format(t["tris"], ","), fill=MUTED, font=F_S)
    y += 2 * (th + 90) + 20
    d.line((M, y, W - M, y), fill=RULE, width=2)
    y += 20
    d.text((M, y), "Every mesh (triangles)", fill=ACCENT, font=F_H)
    y += 48
    names = sorted(meshes)
    per = (len(names) + 3) // 4
    for i, n in enumerate(names):
        cx = M + (i // per) * 600
        cy = y + (i % per) * 30
        d.text((cx, cy), n, fill=INK, font=F_S)
        d.text((cx + 330, cy), format(meshes[n], ","), fill=MUTED, font=F_S)
    y += per * 30 + 30
    curve = st["curve"]
    d.text((M, y), "Whole building: level 5 = %s  ·  18 = %s  ·  43 = %s  ·  68 = %s  ·  93 = %s  ·  100 = %s triangles "
                   "(shell + glass + 15 lift storeys + 14 bridges; budget 45,000)"
           % tuple(format(curve[str(L)], ",") for L in (5, 18, 43, 68, 93, 100)), fill=INK, font=F_B)
    y += 60
    page = page.crop((0, 0, W, y))
    out = os.path.join(ART, "kit_sheet.png")
    page.save(out)
    print("wrote", out, page.size)


main()
