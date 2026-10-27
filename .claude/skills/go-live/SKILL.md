---
name: go-live
description: Use when Luke says "merge", "check" or "publish", or before calling any PR ready to merge or any build safe to Alt+P. Runs the last steps to live in a fixed order and stops at the first red.
---

# go-live: from a green PR to live players

27 Oct 2026: Rojo served main while Studio still held 7 Bob scripts from another branch
(`$ignoreUnknownInstances` keeps what Rojo does not know). The doctor's compare passed it,
because it only asks "is each file in Studio?". A hand check caught it before Alt+P. Hand
checks are memory, not proof: every step below is a command whose output decides.

**Rules that never bend**
- Claude merges only after Luke says "merge" for THAT PR in chat. Never "full send", never `--admin`.
- Luke publishes (Alt+P). Claude never publishes, never asks to "just this once".
- A red step stops the run. Report the red line as printed; never edit a check to pass it.
- A new way to get this wrong = a new check here, test first (same rule as playtest-review).

## "merge" (Luke said it, naming the PR or clearly meaning one)
1. `gh pr view <N> --json headRefOid,baseRefName,state,mergeable` : open, base `main`, mergeable.
2. The merge guard hook (`~/.claude/hooks/guard_merge.py`) checks that `check`, `smoke` and `doctor`
   are all success on that head commit. If the PR touches `src/` and has no doctor status, run the
   doctor gate (game-doctor skill, PR mode) first. A PR with no game code still runs
   `lune run tools/bas checkup pr --post` with no files: it posts "not needed" as success.
3. `gh pr merge <N> -R itwillystyle/build-a-startup --squash` (always the number, always `-R`).
4. Stacked PRs whose base was this branch: `gh pr edit <M> --base main`, rebase, and gate again.
   They are NOT mergeable on the old verdict.
5. Pull main in `game/` (`git pull --ff-only`), tick the PR in `silicon-startup/GAME-OUTLINE.md`,
   then the work-map-rescan steps (`~/.claude/scheduled-tasks/work-map-rescan/SKILL.md`).
6. Tell Luke: merged as `<sha>`, NOT live until Alt+P, and that "check" is next.

## "check" (before Alt+P)
1. `game/` is on main, up to date, clean. Rojo serves `game/` (`rojo serve default.project.json`
   from that folder), and Studio's Rojo plugin says Connected. One Rojo plugin only.
2. Scripts from another branch survive a branch switch. If the last Rojo session served another
   branch, expect extras: the check below names them.
3. Fingerprint, Studio EDIT datamodel. Start the localhost receiver first (interactive sessions
   only; never in a routine): `python -I <scratchpad>/recv/recv.py ../doctor/fingerprint-publish.json`
   in the background, then `execute_luau` (Edit):

       local H = require(game.ReplicatedStorage.SourceHash:Clone())
       local function pathOf(i) local t = {} while i and i ~= game do table.insert(t, 1, i.Name); i = i.Parent end return table.concat(t, "/") end
       local out = {}
       for _, r in { game.ReplicatedStorage, game.ServerScriptService, game.StarterPlayer.StarterPlayerScripts } do
       	for _, d in r:GetDescendants() do
       		if d:IsA("LuaSourceContainer") then local p = pathOf(d); out[p] = out[p] or {}; table.insert(out[p], H.hash(d.Source)) end
       	end
       end
       local HS = game:GetService("HttpService")
       return HS:PostAsync("http://127.0.0.1:34999/", HS:JSONEncode({ kind = "publish", at = os.time(), scripts = out }))

   The roots are the folders `default.project.json` syncs. A new mount there = add it here, or its
   files show up as "missing" (the safe direction).
4. From `game/`: `lune run tools/bas checkup publish ../doctor/fingerprint-publish.json`
   - PASS: tell Luke "SAFE to Alt+P" with the commit (`bad9305`-style short sha).
   - FAIL on extra: those scripts are not on main. Show Luke the list; delete them in Studio only
     after he agrees (ChangeHistoryService recording), then fingerprint and check again.
   - FAIL on doubled: two Rojo plugins are syncing. Luke disables one; then check again.
   - FAIL on changed/missing: Rojo is not connected or serves another folder. Fix that, check again.
5. Leave Studio in Edit.

## "publish" / after Alt+P
1. Studio's log shows `PublishPlaceTime` (the Work Map's Needs-you list reads it).
2. The next morning's health run and the live error log (SVErrors_v1) are the first look.
   Anything broken and live: docs/ROLLBACK.md (kill switch first, a fix PR second).
3. Ask Luke for his recorded run when he has played it (playtest-review).
