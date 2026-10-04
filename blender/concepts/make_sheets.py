"""make_sheets.py -- contact sheets for the three HQ concepts (system python + PIL).

Reads art/concepts/<X>_L05/L30/L100.png (+ _detail), stats.json, plans.json
written by hq_concepts.py, and writes:
  art/concepts/concept_A_sheet.png, concept_B_sheet.png, concept_C_sheet.png
  art/concepts/concepts_all.png   (all nine stages, same camera per concept)
Run:  python make_sheets.py
"""
import json
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(os.path.dirname(HERE)), "art", "concepts")
LEVELS = (5, 30, 100)
PAPER = (243, 239, 230)
INK = (30, 37, 48)
MUTED = (104, 110, 122)
ACCENT = (240, 110, 80)
RULE = (214, 206, 192)
FONT_B = "C:/Windows/Fonts/segoeuib.ttf"
FONT_R = "C:/Windows/Fonts/segoeui.ttf"


def font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default()


TITLE = {"A": "A  ·  THE RING", "B": "B  ·  THE CRESCENT TOWER", "C": "C  ·  THE TERRACES"}
PITCH = {
    "A": "A faceted glass ring round a courtyard orchard. It grows around until the ring closes, then up, then a tower rises in the courtyard.",
    "B": "A crescent podium hugging a plaza. Its storeys rise in a wave into a twisting faceted tower at one end.",
    "C": "A curved amphitheatre of garden terraces facing a plaza. It grows as a hill and is crowned by a faceted dome and spire.",
}
GROWTH = {
    "A": [
        "One level = one module (a 22.5-degree ring segment one storey tall, a tower floor, a bridge or a crown piece).",
        "L1-16  ring segments, lobby first, alternating left and right until the circle closes at the back",
        "L17-64  storeys 2, 3, 4 around the ring (engineering, labs + server hall, engineering), solar roof on top",
        "L65-68 tower floors 1-4  ·  L69-72 four skybridges to the ring's 4th storey  ·  L73-98 tower floors 5-30",
        "L99 cantilevered sky deck with a roof garden  ·  L100 spire and halo. Sky gardens on tower floors 10 and 20.",
    ],
    "B": [
        "One level = one module (a 13-degree crescent segment one storey tall, a tower floor or a crown piece).",
        "L1  tower lobby  ·  L2-19 crescent ground floor (studio, cafe)  ·  L20-30 tower floors 2-12",
        "Crescent storeys come in bands: L31-45 storey 2  ·  L54-65 storey 3  ·  L71-91 storeys 4-6",
        "Each band covers fewer segments from the tower end, so the podium rises in a wave into the tower.",
        "Tower floors between bands (L46-53, L66-70, L92-96), 30 in all, twisting 3.2 deg per floor  ·  L97-100 deck, blades, spire, halo",
    ],
    "C": [
        "One level = one module (an 18-degree terrace segment one storey tall, or a crown piece).",
        "96 terrace modules: 12 floors x up to 11 segments. Every floor is the same 34-stud-deep curved bar set 6 studs back,",
        "so its roof becomes a garden terrace for the floor above. Built in 'hill order' (floor + distance from the centre):",
        "at every level it is a complete little stepped hill, just bigger. Upper floors cover fewer segments (the hill narrows).",
        "L97 drum  ·  L98 faceted glass dome  ·  L99 lantern  ·  L100 spire. Server hall on floor 7, boardrooms on 10-11.",
    ],
}


def load():
    stats = {(s["concept"], s["level"]): s for s in json.load(open(os.path.join(OUT, "stats.json")))}
    plans = json.load(open(os.path.join(OUT, "plans.json")))
    return stats, plans


def fit(im, w, h):
    return im.convert("RGB").resize((w, h), Image.LANCZOS)


def stat_line(s):
    parts = ["%d modules" % s["modules"], "{:,} building tris".format(s["building_tris"]), "%d studs tall" % round(s["height"])]
    if s["garden_trees"]:
        parts.append("%d roof trees" % s["garden_trees"])
    return "  ·  ".join(parts)


def legend(d, x, y, fns, used, fsize=22):
    f = font(FONT_R, fsize)
    for key, info in fns.items():
        if key not in used:
            continue
        col = tuple(info["glow"]) if info["kind"] != "solid" else (52, 60, 74)
        d.rounded_rectangle((x, y + 4, x + 26, y + 30), radius=6, fill=col, outline=(180, 172, 160))
        if info["kind"] == "solid":
            d.rectangle((x + 4, y + 13, x + 22, y + 16), fill=(80, 220, 255))
        if info["kind"] == "garden":
            d.ellipse((x + 7, y + 10, x + 19, y + 24), fill=(122, 170, 80))
        d.text((x + 36, y + 2), info["label"], font=f, fill=INK)
        x += 36 + int(d.textlength(info["label"], font=f)) + 34
    return x


def concept_sheet(c, stats, plans):
    W, H = 640, 800
    DW, DH = 640, 427
    G = 30
    width = 3 * W + 4 * G
    head = 190
    lab = 92
    height = head + lab + H + 24 + 40 + DH + 40 + 250
    im = Image.new("RGB", (width, height), PAPER)
    d = ImageDraw.Draw(im)
    d.text((G, 28), TITLE[c], font=font(FONT_B, 60), fill=INK)
    d.text((G, 112), PITCH[c], font=font(FONT_R, 27), fill=MUTED)
    d.rectangle((G, head - 14, width - G, head - 12), fill=RULE)
    y0 = head
    for i, lv in enumerate(LEVELS):
        x = G + i * (W + G)
        s = stats[(c, lv)]
        d.text((x, y0), "LEVEL %d" % lv, font=font(FONT_B, 40), fill=ACCENT if lv == 100 else INK)
        d.text((x, y0 + 50), stat_line(s), font=font(FONT_R, 20), fill=MUTED)
        im.paste(fit(Image.open(os.path.join(OUT, s["file"])), W, H), (x, y0 + lab))
    y1 = y0 + lab + H + 24
    d.text((G, y1), "Closer look (one camera for all three stages, aimed at the base of the finished building)",
           font=font(FONT_R, 22), fill=MUTED)
    y1 += 40
    for i, lv in enumerate(LEVELS):
        x = G + i * (W + G)
        p = os.path.join(OUT, "%s_L%02d_detail.png" % (c, lv))
        if os.path.exists(p):
            im.paste(fit(Image.open(p), DW, DH), (x, y1))
    y2 = y1 + DH + 30
    d.rectangle((G, y2 - 8, width - G, y2 - 6), fill=RULE)
    fy = y2 + 6
    for k, line in enumerate(GROWTH[c]):
        d.text((G, fy), line, font=font(FONT_B if k == 0 else FONT_R, 22), fill=INK)
        fy += 32
    used = {m["fn"] for m in plans["plans"][c] if m["fn"]}
    d.text((G, fy + 12), "Floor jobs (glass tint):", font=font(FONT_B, 22), fill=INK)
    legend(d, G + 270, fy + 10, plans["functions"], used)
    im = im.crop((0, 0, width, fy + 60))
    path = os.path.join(OUT, "concept_%s_sheet.png" % c)
    im.save(path, optimize=True)
    print("wrote", path, im.size)


def overview(stats, plans):
    W, H = 440, 550
    G = 22
    left = 300
    top = 170
    width = left + 3 * W + 4 * G
    height = top + 3 * (H + G) + 110
    im = Image.new("RGB", (width, height), PAPER)
    d = ImageDraw.Draw(im)
    d.text((G, 24), "ONE HQ, LEVEL 5 TO 100: THREE CONCEPTS", font=font(FONT_B, 48), fill=INK)
    d.text((G, 86), "Same camera across each row, so growth reads left to right. One level = one module (segment, floor, bridge or crown piece).",
           font=font(FONT_R, 23), fill=MUTED)
    for i, lv in enumerate(LEVELS):
        x = left + G + i * (W + G)
        d.text((x, top - 44), "LEVEL %d" % lv, font=font(FONT_B, 32), fill=ACCENT if lv == 100 else INK)
    short = {"A": ["THE RING", "around, then up,", "then a courtyard tower", "with skybridges"],
             "B": ["THE CRESCENT", "TOWER", "a podium wave into", "a twisting tower"],
             "C": ["THE TERRACES", "a garden amphitheatre", "that grows as a hill,", "dome + spire on top"]}
    for r, c in enumerate("ABC"):
        y = top + r * (H + G)
        d.text((G, y + 10), c, font=font(FONT_B, 84), fill=ACCENT)
        yy = y + 120
        for k, line in enumerate(short[c]):
            d.text((G, yy), line, font=font(FONT_B if k < (2 if c == "B" else 1) else FONT_R, 26 if k < (2 if c == "B" else 1) else 21),
                   fill=INK if k < (2 if c == "B" else 1) else MUTED)
            yy += 34
        s100 = stats[(c, 100)]
        d.text((G, yy + 16), "L100: {:,} tris".format(s100["building_tris"]), font=font(FONT_R, 20), fill=MUTED)
        d.text((G, yy + 42), "%d studs tall" % round(s100["height"]), font=font(FONT_R, 20), fill=MUTED)
        for i, lv in enumerate(LEVELS):
            x = left + G + i * (W + G)
            im.paste(fit(Image.open(os.path.join(OUT, stats[(c, lv)]["file"])), W, H), (x, y))
    used = set()
    for c in "ABC":
        used |= {m["fn"] for m in plans["plans"][c] if m["fn"]}
    ly = top + 3 * (H + G) + 20
    d.text((G, ly + 2), "Floor jobs:", font=font(FONT_B, 22), fill=INK)
    legend(d, G + 140, ly, plans["functions"], used, fsize=21)
    path = os.path.join(OUT, "concepts_all.png")
    im.save(path, optimize=True)
    print("wrote", path, im.size)


def main():
    stats, plans = load()
    for c in "ABC":
        concept_sheet(c, stats, plans)
    overview(stats, plans)


if __name__ == "__main__":
    main()
