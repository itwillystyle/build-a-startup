# CONSTRAINTS: the rules that have each cost a session

Every reviewer (a fresh agent, or Luke) checks a change against this list FIRST.
A broken rule is a Critical finding, whatever else the change gets right.
Why this file exists: the Anthropic source-control article (13 Oct 2026) found that
agents' main failure was breaking core constraints, and the engineers' main job
became saying "no". These are ours, short enough to check every time.

**Players and their data**
1. **Never publish the live place without Luke's go.** Saving is fine; publishing reaches players.
2. **Never touch the main account's save.** Studio tests run as Wilz (`1688749216`) only.
   After any Play: `require(game.ServerScriptService.DevScenarios:Clone()).restore(1688749216)`,
   and leave Studio in **Edit**.
3. **Every saved number is clamped on load, and every saved field is both written and read.**
   New save fields need a sanitizer, a `savecontract.spec` entry and a case in `savefuzz.spec`.

**The judges**
4. **Never edit a test, sim, gate or doctor check to make a change pass.** Fix the code.
   If a judge is wrong, change it in its own PR and say why (ImpossibleBench: models do this).
5. **No auto-merge for gameplay, look, economy, save, judge or CI changes.** `bas risk` says
   which a branch is. Luke merges those after reading the PR's intent card.
6. **Every PR opens with the intent card** (should do / must not break / measured / not
   measured), and every review finding names a concrete failure, or it is dropped.
7. **Measure, don't assert.** Every report marks what was verified by running something and
   what was not. A screenshot or a number, not "should work".

**Studio and the code**
8. **Files are the truth; Rojo pushes them into Studio.** Never edit a script's Source in
   Studio. Never remove `$ignoreUnknownInstances` (it protects the mesh folders). If Studio
   ignores a change, check that `rojo serve` is running before anything else.
9. **Play snapshots the place at start.** After a code change, stop and restart Play.
10. **`SiliconCore.server.lua` is at the 200-local limit.** New state hangs off `Econ` or a
    module; never a new top-level local there.
11. **Offline tests load pure modules only** (no `game:GetService` at load). Logic that must be
    tested goes in a pure module (like `ServerRack`, `StaffStats`, `GarageLayout`).

**The look**
12. **Colours stay on `Palette.ANCHORS`; no pure white or black; Neon only on lights, screens
    and effects; nothing sizeable has a sharp corner** (art/STYLE-SPEC.md, the wafer rule).
    Our own meshes carry an `SV`/`LP_`/`W_`/`D_`/`T_`/`HQ` name prefix or Palette washes them.
13. **Imported meshes live in the place, not git.** Code that uses one falls back to parts
    when it is missing, and refuses one that does not fit its slot. After an import, move it
    out of Workspace before saving. Our meshes face +Z (`rack_export.py` turns them).

**Secrets and other people's things**
14. **Never print or commit an API key or the Discord webhook token** (`../.discord-webhook`).
    Never use unverified Creator Store audio.
15. **Branch protection, required checks, Windows settings and Luke's mouse and keyboard are
    his.** Ask; don't take them over.
