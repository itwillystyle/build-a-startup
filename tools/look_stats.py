"""look_stats.py -- the look review's ruler (art pass 1, 22 Oct 2026).

Turns a screenshot into the four numbers the art-pass spec targets
(silicon-startup/docs/superpowers/specs/2026-10-22-art-pass-design.md, section 3):

    mean    mean luminance (Rec.709), 0..1
    spread  contrast: luminance p90 - p10
    sat     colour strength: mean HSV saturation
    blown   share of near-white pixels (luminance > 0.92)

Measured on 22 Oct: Luke's live shots were 46-79% near white against 1-4% in the
picked mocks. That number is what "too blocky and dull" was.

The top and bottom 12% are cut (the HUD rows: goal card, money, the bottom
button), so the numbers are about the world, not the UI.

Usage:
    python -I tools/look_stats.py shot1.png [shot2.png ...] [--targets tools/look_targets.json] [--lowq]
    python -I tools/look_stats.py --selftest
Exit 1 if any image misses a target.
"""
import json
import os
import sys

from PIL import Image

CROP = 0.12
WIDTH = 320
BLOWN = 0.92
HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_TARGETS = os.path.join(HERE, "look_targets.json")
MOCK = os.path.join(HERE, "..", "..", "ui", "art-pass", "garage-outside.png")


def stats(im):
    im = im.convert("RGB")
    w, h = im.size
    im = im.crop((0, int(h * CROP), w, int(h * (1 - CROP))))
    w, h = im.size
    im = im.resize((WIDTH, max(1, round(WIDTH * h / w))))
    lum, sat, blown = [], 0.0, 0
    for r, g, b in im.getdata():
        l = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
        lum.append(l)
        mx, mn = max(r, g, b), min(r, g, b)
        sat += (mx - mn) / mx if mx else 0.0
        if l > BLOWN:
            blown += 1
    n = len(lum)
    lum.sort()
    p = lambda q: lum[int(q * (n - 1))]
    return {
        "mean": round(sum(lum) / n, 3),
        "spread": round(p(0.9) - p(0.1), 3),
        "sat": round(sat / n, 3),
        "blown": round(blown / n, 3),
    }


def judge(s, t, lowq=False):
    spread_min = t.get("lowq", {}).get("spread_min", t["spread_min"]) if lowq else t["spread_min"]
    return {
        "blown": s["blown"] <= t["blown_max"],
        "mean": t["mean_min"] <= s["mean"] <= t["mean_max"],
        "spread": s["spread"] >= spread_min,
        "sat": s["sat"] >= t["sat_min"],
    }


def load_targets(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def selftest():
    t = load_targets(DEFAULT_TARGETS)
    white = Image.new("RGB", (64, 64), (255, 255, 255))
    checker = Image.new("RGB", (64, 64))
    checker.putdata([(0, 0, 0) if (x // 8 + y // 8) % 2 else (255, 255, 255) for y in range(64) for x in range(64)])
    cases = [
        ("all white", white, {"blown": False}),
        ("black/white checker", checker, {"sat": False}),
        ("the picked mock", Image.open(MOCK), {"blown": True, "mean": True, "spread": True, "sat": True}),
    ]
    good = 0
    for name, im, want in cases:
        got = judge(stats(im), t)
        ok = all(got[k] == v for k, v in want.items())
        good += ok
        print(("ok  " if ok else "BAD ") + name, stats(im), got)
    print(f"{len(cases)} cases, {good} as expected")
    return 0 if good == len(cases) else 1


def main(argv):
    if "--selftest" in argv:
        return selftest()
    tpath = DEFAULT_TARGETS
    if "--targets" in argv:
        tpath = argv[argv.index("--targets") + 1]
    lowq = "--lowq" in argv
    files = [a for i, a in enumerate(argv) if not a.startswith("--") and (i == 0 or argv[i - 1] != "--targets")]
    if not files:
        print(__doc__)
        return 2
    t = load_targets(tpath)
    bad = 0
    for f in files:
        s = stats(Image.open(f))
        got = judge(s, t, lowq)
        verdict = "PASS" if all(got.values()) else "FAIL " + ",".join(k for k, v in got.items() if not v)
        bad += not all(got.values())
        print(f"{os.path.basename(f)}  mean {s['mean']}  spread {s['spread']}  sat {s['sat']}  blown {s['blown']}  {verdict}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
