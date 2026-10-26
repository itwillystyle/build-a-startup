"""Sound work for Build a Startup!: find, measure and check sounds BEFORE they go in the game.

Born 25 Oct 2026 (P-5, Bob's cutscenes): sounds picked by their store names were wrong for their job
(a bike horn for a gasp), started late (the files open on up to 1.2 s of dead air) and sat 31 dB apart.
Procedure: .claude/skills/sound-design/SKILL.md. Needs numpy + mutagen, and ffmpeg.

  python tools/audio/sfx.py search "<words>" [--max-dur S] [--all]
      the Creator Store's audio, Pro Sound Effects and APM only (licensed, stable) unless --all,
      with each result's full description (category, what is in the recording)
  python tools/audio/sfx.py fetch LENGTHS.json OUTDIR [--minutes M]
      LENGTHS.json = {"<id>": TimeLength} from Studio (the skill has the snippet, which also makes
      Studio read each file). Finds each id's file in Studio's cache: that exact length, and the one
      Studio read last (within M minutes, default 30). Decodes it to OUTDIR/<id>.f32 (48 kHz stereo)
  python tools/audio/sfx.py measure OUTDIR <id> [<id> ...]
      where the sound starts (dead air), its phrases, pitch, loudness, and a ready SOUND line:
      at = where it starts, gain = the trim to -24 dB (capped at 8)
  python tools/audio/sfx.py mixcheck PLAN.json OUTDIR
      PLAN.json from `lune run tools/audio/plan_export <out.json>`: renders the scene's sound plan
      from the real files and reports, per event, its loudest 50 ms against the beds under it.
      Pass: every event 5 dB or more over the beds; the events within about 15 dB of each other
"""
import glob, io, json, os, shutil, subprocess, sys, time, urllib.parse, urllib.request

SR = 48000
REF_DB, GAIN_CAP = -24.0, 8.0
LICENSED = {"ProSoundEffects", "APMOfficial"}


def ffmpeg():
    exe = shutil.which("ffmpeg")
    if exe:
        return exe
    hits = glob.glob(os.path.expandvars(r"%LOCALAPPDATA%\Microsoft\WinGet\Packages\Gyan.FFmpeg*\ffmpeg-*\bin\ffmpeg.exe"))
    if not hits:
        sys.exit("ffmpeg not found (winget install Gyan.FFmpeg)")
    return hits[0]


# ------------------------------------------------------------------ search
def search(words, max_dur=None, everyone=False, pages=3):
    tok, seen = "", set()
    for _ in range(pages):
        u = "https://apis.roblox.com/toolbox-service/v2/assets:search?" + urllib.parse.urlencode(
            {"searchCategoryType": "Audio", "query": words, "maxPageSize": 100, "pageToken": tok})
        for attempt in range(4):
            try:
                d = json.load(urllib.request.urlopen(u, timeout=25))
                break
            except Exception as e:   # the API rate-limits bursts: back off
                if attempt == 3:
                    sys.exit(f"search failed: {e}")
                time.sleep(3 * (attempt + 1))
        for a in d.get("creatorStoreAssets", []):
            by, x = a["creator"]["name"], a["asset"]
            if (everyone or by in LICENSED) and x["id"] not in seen and (not max_dur or (x.get("durationSeconds") or 0) <= max_dur):
                seen.add(x["id"])
                desc = " ".join((x.get("description") or "").split())
                desc = desc.split("Courtesy of")[0].split("Asset Type")[0][:220]
                print(f"{x['id']} | {by[:3]} | {x['name'][:60]} | {x.get('durationSeconds')}s | {desc}")
        tok = d.get("nextPageToken")
        if not tok:
            break
        time.sleep(1)


# ------------------------------------------------------------------ fetch
def cache_index():
    """{file name: (length s, 'ogg'|'mp3', path, offset)} for every audio file in Studio's cache, kept in
    a side index so only new files are parsed"""
    from mutagen.oggvorbis import OggVorbis
    from mutagen.mp3 import MP3
    root = os.path.join(os.environ["LOCALAPPDATA"], "Roblox", "rbx-storage")
    side = os.path.join(os.environ.get("TEMP", "."), "sfx_cache_index.json")
    known = json.load(open(side)) if os.path.exists(side) else {}
    out = {}
    for dp, _, fs in os.walk(root):
        for f in fs:
            p = os.path.join(dp, f)
            key = f"{p}|{os.path.getsize(p)}"
            if key not in known:
                known[key] = None
                with open(p, "rb") as h:
                    head = h.read(4096)
                for magic, kind, cls in ((b"OggS", "ogg", OggVorbis), (b"ID3", "mp3", MP3)):
                    i = head.find(magic)
                    if i >= 0:
                        try:
                            known[key] = (cls(io.BytesIO(open(p, "rb").read()[i:])).info.length, kind, i)
                        except Exception:
                            pass
                        break
            if known[key]:
                L, kind, i = known[key]
                out[f] = (L, kind, p, i)
    json.dump(known, open(side, "w"))
    return out


def last_read():
    """{file name: ms since epoch Studio last read it}, from Studio's cache database (copied: it is
    open while Studio runs)"""
    import sqlite3
    src = os.path.join(os.environ["LOCALAPPDATA"], "Roblox", "rbx-storage.db")
    tmp = os.path.join(os.environ.get("TEMP", "."), "sfx_rbx_storage")
    os.makedirs(tmp, exist_ok=True)
    for ext in ("", "-wal", "-shm"):
        if os.path.exists(src + ext):
            shutil.copy(src + ext, os.path.join(tmp, "s.db" + ext))
    db = sqlite3.connect(os.path.join(tmp, "s.db"))
    return {bytes(i).hex(): t for i, t in db.execute("select id, atime from files")}


def fetch(lengths_path, outdir, minutes=30):
    """Studio must have loaded the ids in the last `minutes` (the skill's snippet does): among the
    files of that exact length, the one Studio read most recently is the one"""
    lengths = json.load(open(lengths_path))
    files, seen = cache_index(), last_read()
    since = (time.time() - minutes * 60) * 1000
    os.makedirs(outdir, exist_ok=True)
    for id_, L in lengths.items():
        # Ogg lengths match Studio's TimeLength to the sample; an MP3's estimate can be ~0.06 s off
        cands = [(name, f) for name, f in files.items()
                 if abs(f[0] - L) < 0.0006 or (f[1] == "mp3" and abs(f[0] - L) < 0.08)]
        fresh = sorted([c for c in cands if seen.get(c[0], 0) >= since], key=lambda c: -seen[c[0]])
        if not fresh:
            print(f"{id_}: not found ({len(cands)} file(s) of that length, none read in the last {minutes:g} min): load it in Studio, then fetch")
            continue
        name, (FL, kind, path, off) = fresh[0]
        note = "exact" if abs(FL - L) < 0.0006 else f"mp3 length {FL:.3f} vs {L:.3f}"
        if len(fresh) > 1:
            note += f" (newest of {len(fresh)} read lately: load fewer ids at once if unsure)"
        src = os.path.join(outdir, id_ + ".src")
        with open(path, "rb") as h:
            open(src, "wb").write(h.read()[off:])
        raw = subprocess.run([ffmpeg(), "-v", "error", "-i", src, "-ar", str(SR), "-ac", "2", "-f", "f32le", "-"],
                             capture_output=True).stdout
        open(os.path.join(outdir, id_ + ".f32"), "wb").write(raw)
        os.remove(src)
        print(f"{id_}: {note}")


# ------------------------------------------------------------------ measure
def load(outdir, id_):
    import numpy as np
    return np.fromfile(os.path.join(outdir, id_ + ".f32"), np.float32).reshape(-1, 2).astype(np.float64)


def envelope(m, hop=480):
    import numpy as np
    n = len(m) // hop
    return np.sqrt((m[: n * hop].reshape(n, hop) ** 2).mean(1)) + 1e-9   # 10 ms frames


def pitch(seg):
    import numpy as np
    fr, out = 1920, []
    for k in range(0, len(seg) - fr, 960):
        x = seg[k:k + fr] * np.hanning(fr)
        if np.sqrt((x ** 2).mean()) < 1e-3:
            continue
        ac = np.fft.irfft(np.abs(np.fft.rfft(x, 2 * fr)) ** 2)[:fr]
        lo, hi = SR // 900, SR // 70
        j = lo + int(np.argmax(ac[lo:hi]))
        if ac[j] / ac[0] > 0.45:
            out.append(SR / j)
    return out


def segments(e, gap=0.09, th=-32):
    import numpy as np
    on = 20 * np.log10(e / e.max()) > th
    segs, s, quiet = [], None, 0
    for k, v in enumerate(on):
        if v:
            s = k if s is None else s
            quiet = 0
        elif s is not None:
            quiet += 1
            if quiet * 0.01 >= gap:
                segs.append((s * 0.01, (k - quiet + 1) * 0.01))
                s = None
    if s is not None:
        segs.append((s * 0.01, len(on) * 0.01))
    return [x for x in segs if x[1] - x[0] >= 0.05]


def measure(outdir, ids):
    import numpy as np
    for id_ in ids:
        a = load(outdir, id_)
        m = a.mean(1)
        e = envelope(m)
        db = 20 * np.log10(e / e.max())
        loud = 20 * np.log10(np.sqrt((e[e > e.max() * 0.1] ** 2).mean()))
        segs = segments(e)
        start = segs[0][0] if segs else 0.0
        hit = float(np.argmax(db > -20)) * 0.01   # the transient: use this for an impact's `at`
        gain = min(GAIN_CAP, 10 ** ((REF_DB - loud) / 20))
        print(f"\n{id_}: {len(m) / SR:.2f} s, loudness {loud:.1f} dB, sound from {start:.2f} s, hit at {hit:.2f} s, {len(segs)} phrase(s)")
        for s0, s1 in segs[:10]:
            p = pitch(m[int(s0 * SR): int(s1 * SR)])
            shape = "no pitch"
            if len(p) >= 3:
                q = max(1, len(p) // 3)
                a0, a1 = np.median(p[:q]), np.median(p[-q:])
                shape = f"{a0:.0f} > {a1:.0f} Hz ({'rises' if a1 > a0 * 1.08 else 'falls' if a1 < a0 / 1.08 else 'level'})"
            print(f"   {s0:5.2f}-{s1:5.2f} s  {shape}")
        print(f"   SOUND: {{ \"<SfxKey>\", at = {start:.2f}, len = {(segs[-1][1] if segs else len(m) / SR) - start:.2f}, gain = {gain:.2f} }}"
              f"   (an impact: at = {hit:.2f})")


# ------------------------------------------------------------------ mixcheck
def speed(a, p):
    import numpy as np
    if not p or p == 1:
        return a
    x = np.arange(int(len(a) / p)) * p
    return np.stack([np.interp(x, np.arange(len(a)), a[:, c]) for c in range(2)], 1)


def mixcheck(plan_path, outdir):
    import numpy as np
    plan = json.load(open(plan_path))
    bad = 0
    for name, sc in plan["scenes"].items():
        L = sc["length"]
        n = int(L * SR)
        bg, events = np.zeros((n + SR, 2)), []
        for c in sc["cues"]:
            info = plan["SOUND"][c["id"]]
            a = load(outdir, info["id"])[int(info["at"] * SR): int((info["at"] + info["len"]) * SR)]
            a = speed(a, c.get("pitch")) * c["vol"] * info["gain"]
            if c.get("dur"):
                a = a[: int(c["dur"] * SR)].copy()
                f = min(len(a), int((c.get("fade") or 0.1) * SR))
                if f:
                    a[-f:] *= np.linspace(1, 0, f)[:, None]
            events.append((c["t"], c["id"], a[: max(0, n - int(c["t"] * SR))]))
        for b in sc["beds"]:
            info = plan["SOUND"][b["id"]]
            lv = np.array(b["level"])
            on = np.nonzero(lv > 0)[0]
            if not len(on):
                continue
            i0 = int(on[0] / 100 * SR)
            src = load(outdir, info["id"])[int(info["at"] * SR):]
            reps = int(np.ceil((n - i0) / len(src))) + 1
            loop = np.tile(src, (reps, 1))[: n - i0]
            k = np.interp(np.arange(i0, n) / SR * 100, np.arange(len(lv)), lv) * info["gain"]
            bg[i0:n] += loop * k[:, None]
        print(f"\n{name}:")
        levels = []
        for t, id_, a in sorted(events, key=lambda e: e[0]):
            if id_ == "pop" or not len(a):
                continue
            i, w = int(t * SR), min(len(a), int(0.4 * SR))
            seg = a[:w].mean(1)
            st = np.sqrt(np.convolve(seg ** 2, np.ones(2400) / 2400, "valid")) if len(seg) > 2400 else np.array([np.sqrt((seg ** 2).mean())])
            ev = 20 * np.log10(st.max() + 1e-9)
            back = 20 * np.log10(np.sqrt((bg[i: i + w] ** 2).mean()) + 1e-9)
            levels.append(ev)
            flag = "" if ev - back >= 5 else "   <-- under 5 dB over the beds"
            bad += 1 if flag else 0
            print(f"  {t:6.2f} {id_:14s} {ev:6.1f} dB over beds {back:6.1f} dB: {ev - back:+6.1f}{flag}")
        if levels:
            span = max(levels) - min(levels)
            print(f"  events span {span:.1f} dB" + ("   <-- over 15 dB" if span > 15 else ""))
            bad += span > 15
    print("\nmixcheck:", "PASS" if bad == 0 else f"{bad} problem(s)")
    return bad


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    cmd = args.pop(0)
    if cmd == "search":
        md = float(args[args.index("--max-dur") + 1]) if "--max-dur" in args else None
        search(args[0], md, "--all" in args)
    elif cmd == "fetch":
        mins = float(args[args.index("--minutes") + 1]) if "--minutes" in args else 30
        fetch(args[0], args[1], mins)
    elif cmd == "measure":
        measure(args[0], args[1:])
    elif cmd == "mixcheck":
        sys.exit(1 if mixcheck(args[0], args[1]) else 0)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")   # store names carry emoji and accents
    try:
        main()
    except (BrokenPipeError, OSError) as e:
        if isinstance(e, BrokenPipeError) or getattr(e, "errno", None) == 22:   # piped into head
            sys.exit(0)
        raise
