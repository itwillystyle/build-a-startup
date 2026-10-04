"""make_format_sheets.py -- contact sheets for round 2 (hq_formats.py), system python + PIL.

Reads art/concepts/formats/<X>_L<nnn>_<view>.png + stats.json + plans.json and writes
  art/concepts/formats/formats_<X>_sheet.png   one per format
  art/concepts/formats/formats_all.png         every format as a row (L5, L30, L100, plaza view)
Run:  python make_format_sheets.py
"""
import json
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(os.path.dirname(HERE)), "art", "concepts", "formats")
PAPER = (243, 239, 230)
INK = (30, 37, 48)
MUTED = (104, 110, 122)
ACCENT = (240, 110, 80)
RULE = (214, 206, 192)
FONT_B = "C:/Windows/Fonts/segoeuib.ttf"
FONT_R = "C:/Windows/Fonts/segoeui.ttf"
ORDER = "WTSOC"


def font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default()


PITCH = {
    "W": "Four oval office 'wafers', each turned and shifted on the one below, with open-air garden decks between them. "
         "One glass lift core in the courtyard is bridged to every wafer.",
    "T": "Two curved towers splayed toward the plaza on a curved two-storey podium. Themed sky links join them as they rise; "
         "a sky park with a pool bridges the tops.",
    "S": "A one-storey glass podium ring, then ONE ribbon of offices winding up round a glass lift core, two storeys of rise per turn. "
         "Each turn's roof is an open-air garden ramp you can walk to the top.",
    "O": "A glass dome garden inside a ring promenade, with one round tower per department standing on the ring, "
         "linked to the dome by glass bridges.",
    "C": "One continuous roof of shallow hex 'dragonscale' bays over one glass building, its facade tinted bay by bay by what "
         "each bay does. The last levels lift the middle into a stepped mountain.",
}
GROWTH = {
    "W": ["One level = one module: a 45-degree wafer segment one storey tall, a garden deck, or a crown piece.",
          "L1-16 wafer 1 (lobby, cafe, studio), front segments first  ·  L17 garden deck with running track",
          "L18-41 wafer 2, engineering  ·  L42 garden deck  ·  L43-66 wafer 3, AI labs with the server floor in the middle  ·  L67 garden deck",
          "L68-91 wafer 4: studio, boardroom, founder floor  ·  L92 roof garden  ·  L93-97 founder pavilion  ·  L98 gold crown band  ·  L99 lantern  ·  L100 mast"],
    "T": ["One level = one module: half a tower floor, a podium segment, a link storey or a sky-park piece.",
          "L1-4 both tower lobbies  ·  L5-10 the curved podium (lobby, cafe, studio)  ·  then both towers rise half a floor at a time, kept in step",
          "L45-46 Health link (cafe + gym) at floors 8-9, the moment both towers pass floor 9  ·  L91-92 Knowledge link (AI labs) at floors 15-16",
          "L93-97 sky park on the 19-floor tower, plugged into the 23-floor one: 2 deck halves, pool, garden, pavilion  ·  L100 spire  ·  sky gardens on floors 10 and 17"],
    "S": ["One level = one module: a podium segment, a 24-stud ribbon segment one storey tall, or a crown piece.",
          "L1-12 the podium ring (lobby, cafe, studio)  ·  L13-94 the ribbon: 82 segments, 6.25 turns, one bridge to the core per turn",
          "Each turn is one department: studio, engineering x2, AI labs (server hall on half a turn), AI labs, boardroom, founder floor",
          "L95 sky deck on the core  ·  L96 dome  ·  L97 lantern  ·  L98 gold halo  ·  L99 spire  ·  L100 gold band round the podium"],
    "O": ["One level = one module: a tower floor, a ring segment, a dome wedge, a bridge or a crown piece.",
          "L1-15 lobby tower, ring storey 1, every tower's first floor  ·  L16 dome drum  ·  L17-27 ring storey 2 + second floors",
          "L28-34 six dome wedges, then the lantern and indoor waterfall  ·  L35-45 third floors + six glass bridges to the dome",
          "L46-98 the towers rise in step (engineering 16, AI labs 22, server hall 7, studio 12, boardroom 11 floors)  ·  L99 spire  ·  L100 gold band"],
    "C": ["One level = one module: a roof bay, one storey of a bay, a trellis segment, or the lantern.",
          "Each bay = roof, then ground floor, then upper floor  ·  L1-57 centre, ring 1, ring 2 (19 bays; one is an open garden court)",
          "L58-78 seven more bays at the back  ·  L79-83 the solar trellis over the plaza (Nvidia Voyager)  ·  the lobby bay moves to the front as it grows",
          "L84-99 the mountain: centre bay rises to 6 storeys, ring 1 to 4 (boardroom, founder floor, labs)  ·  L100 lantern + spire"],
}
SHORT = {"W": ["stacked oval wafers,", "garden decks between"],
         "T": ["two towers, sky links,", "sky park on top"],
         "S": ["one ribbon winding up", "round a lift core"],
         "O": ["dome garden, ring,", "a tower per department"],
         "C": ["one dragonscale roof,", "rising to a mountain"]}


def load():
    stats = {(s["fmt"], s["level"]): s for s in json.load(open(os.path.join(OUT, "stats.json")))}
    plans = json.load(open(os.path.join(OUT, "plans.json")))
    return stats, plans


def img(name, w, h):
    return Image.open(os.path.join(OUT, name)).convert("RGB").resize((w, h), Image.LANCZOS)


def legend(d, x, y, fns, used, fsize=21, maxx=10 ** 9):
    f = font(FONT_R, fsize)
    x0 = x
    for key, info in fns.items():
        if key not in used:
            continue
        wlab = 36 + int(d.textlength(info["label"], font=f)) + 30
        if x + wlab > maxx:
            x, y = x0, y + 36
        col = tuple(info["glow"]) if info["kind"] != "solid" else (52, 60, 74)
        d.rounded_rectangle((x, y + 4, x + 26, y + 30), radius=6, fill=col, outline=(180, 172, 160))
        if info["kind"] == "solid":
            d.rectangle((x + 4, y + 13, x + 22, y + 16), fill=(80, 220, 255))
        if info["kind"] == "garden":
            d.ellipse((x + 7, y + 10, x + 19, y + 24), fill=(122, 170, 80))
        d.text((x + 36, y + 2), info["label"], font=f, fill=INK)
        x += wlab
    return y


def stat_line(s):
    return "{:,} building tris  ·  {} studs tall  ·  footprint {} x {} studs".format(
        s["building_tris"], round(s["height"]), s["footprint"][0], s["footprint"][1])


def sheet(f, stats, plans):
    G = 30
    W3, H3 = 640, 480
    WG, HG = 975, 548
    width = 3 * W3 + 4 * G
    im = Image.new("RGB", (width, 3200), PAPER)
    d = ImageDraw.Draw(im)
    d.text((G, 24), "%s  ·  %s" % (f, plans["names"][f]), font=font(FONT_B, 58), fill=INK)
    d.text((G, 100), "From: " + plans["refs"][f], font=font(FONT_B, 24), fill=ACCENT)
    d.text((G, 136), PITCH[f], font=font(FONT_R, 23), fill=MUTED)
    y = 190
    d.rectangle((G, y - 8, width - G, y - 6), fill=RULE)
    for i, lv in enumerate((5, 30, 100)):
        x = G + i * (W3 + G)
        s = stats[(f, lv)]
        d.text((x, y), "LEVEL %d" % lv, font=font(FONT_B, 36), fill=ACCENT if lv == 100 else INK)
        d.text((x, y + 46), stat_line(s), font=font(FONT_R, 18), fill=MUTED)
        im.paste(img(s["files"]["aerial"], W3, H3), (x, y + 80))
    y += 80 + H3 + 16
    d.text((G, y), "Same camera for all three (fitted to level 100). Below: closer camera for L5 and L30, then the plaza view "
                   "(camera 6.5 studs up, ~80 studs out, Roblox's 70-degree FOV).", font=font(FONT_R, 20), fill=MUTED)
    y += 40
    for i, lv in enumerate((5, 30)):
        x = G + i * (W3 + G)
        d.text((x, y), "L%d close" % lv, font=font(FONT_B, 24), fill=INK)
        im.paste(img(stats[(f, lv)]["files"]["close"], W3, H3), (x, y + 36))
    x = G + 2 * (W3 + G)
    d.text((x, y), "Floor jobs (glass tint)", font=font(FONT_B, 24), fill=INK)
    used = {m["fn"] for m in plans["plans"][f] if m["fn"]}
    legend(d, x, y + 44, plans["functions"], used, fsize=22, maxx=width - G)
    s100 = stats[(f, 100)]
    fy = y + 44 + 5 * 38
    for line in ("Level 100:", "{:,} building triangles".format(s100["building_tris"]),
                 "+ {} roof trees".format(s100["garden_trees"]), "{} studs tall".format(round(s100["height"])),
                 "footprint {} x {} studs".format(*s100["footprint"])):
        d.text((x, fy), line, font=font(FONT_B if line.endswith(":") else FONT_R, 22), fill=INK if line.endswith(":") else MUTED)
        fy += 32
    y += 36 + H3 + 20
    for i, lv in enumerate((30, 100)):
        x = G + i * (WG + G)
        d.text((x, y), "L%d from the plaza" % lv, font=font(FONT_B, 24), fill=INK)
        im.paste(img(stats[(f, lv)]["files"]["ground"], WG, HG), (x, y + 36))
    y += 36 + HG + 26
    d.rectangle((G, y - 8, width - G, y - 6), fill=RULE)
    for k, line in enumerate(GROWTH[f]):
        d.text((G, y + 4), line, font=font(FONT_B if k == 0 else FONT_R, 22), fill=INK)
        y += 34
    im = im.crop((0, 0, width, y + 24))
    p = os.path.join(OUT, "formats_%s_sheet.png" % f)
    im.save(p, optimize=True)
    print("wrote", p, im.size)


def overview(stats, plans):
    G = 14
    left = 250
    WA, HA = 400, 300
    WGr = 533
    top = 150
    width = left + 3 * (WA + G) + WGr + G
    height = top + len(ORDER) * (HA + G) + 90
    im = Image.new("RGB", (width, height), PAPER)
    d = ImageDraw.Draw(im)
    d.text((G + 4, 18), "ONE HQ, LEVEL 1 TO 100: FIVE NEW FORMATS", font=font(FONT_B, 44), fill=INK)
    d.text((G + 4, 76), "L30 and L100 share one camera per row; L5 uses a closer camera. Last column: L30 as a player sees it "
                        "from the plaza. One level = one module.", font=font(FONT_R, 20), fill=MUTED)
    heads = ["LEVEL 5 (closer)", "LEVEL 30", "LEVEL 100", "LEVEL 30 FROM THE PLAZA"]
    for i, h in enumerate(heads):
        x = left + i * (WA + G)
        d.text((x, top - 36), h, font=font(FONT_B, 24), fill=ACCENT if i == 2 else INK)
    for r, f in enumerate(ORDER):
        y = top + r * (HA + G)
        d.text((G + 4, y + 4), f, font=font(FONT_B, 64), fill=ACCENT)
        d.text((G + 4, y + 86), plans["names"][f], font=font(FONT_B, 24), fill=INK)
        yy = y + 120
        for line in SHORT[f]:
            d.text((G + 4, yy), line, font=font(FONT_R, 19), fill=MUTED)
            yy += 26
        s = stats[(f, 100)]
        d.text((G + 4, yy + 10), "L100: {:,} tris".format(s["building_tris"]), font=font(FONT_R, 18), fill=MUTED)
        d.text((G + 4, yy + 34), "{} studs tall".format(round(s["height"])), font=font(FONT_R, 18), fill=MUTED)
        d.text((G + 4, yy + 58), "{} x {} footprint".format(*s["footprint"]), font=font(FONT_R, 18), fill=MUTED)
        im.paste(img(stats[(f, 5)]["files"]["close"], WA, HA), (left, y))
        im.paste(img(stats[(f, 30)]["files"]["aerial"], WA, HA), (left + WA + G, y))
        im.paste(img(stats[(f, 100)]["files"]["aerial"], WA, HA), (left + 2 * (WA + G), y))
        im.paste(img(stats[(f, 30)]["files"]["ground"], WGr, HA), (left + 3 * (WA + G), y))
    used = set()
    for f in ORDER:
        used |= {m["fn"] for m in plans["plans"][f] if m["fn"]}
    ly = top + len(ORDER) * (HA + G) + 16
    d.text((G + 4, ly + 2), "Floor jobs:", font=font(FONT_B, 21), fill=INK)
    legend(d, G + 140, ly, plans["functions"], used, fsize=20)
    p = os.path.join(OUT, "formats_all.png")
    im.save(p, optimize=True)
    print("wrote", p, im.size)


def main():
    stats, plans = load()
    for f in ORDER:
        sheet(f, stats, plans)
    overview(stats, plans)


if __name__ == "__main__":
    main()
