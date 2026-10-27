---
name: go-live
description: Use when Luke says "merge" for a PR, asks for the pre-publish "check" (is Studio safe to Alt+P), or says he is about to publish. Runs the last steps to live in a fixed order and stops at the first red.
---

# go-live: from a green PR to live players

27 Oct 2026: Rojo served main while Studio still held 7 Bob scripts from another branch
(`$ignoreUnknownInstances` keeps what Rojo does not know). The doctor's compare passed it,
because it only asks "is each file in Studio?". A hand check caught it before Alt+P. Hand
checks are memory, not proof: every step below is a command whose output decides.

**Rules that never bend**
- Claude merges only after Luke says "merge" for THAT PR in chat. Never "full send".
- Luke publishes (Alt+P). Claude never publishes, never asks to "just this once".
- A red step stops the run. Report the red line as printed; never edit a check to pass it.
- A new way to get this wrong = a new check here, test first (same rule as playtest-review).

**What enforces it**
- `~/.claude/hooks/guard_merge.py` (Bash, PowerShell, the terminal tool, the auto-merge tool):
  the ONLY merge it lets through is
  `gh pr merge <N> -R itwillystyle/build-a-startup --squash --match-head-commit <sha>`
  as its own command, and only when check, smoke AND doctor are SUCCESS on that head. It refuses
  --admin, --auto, wrapped commands, GraphQL/REST merges, aliases and pushes to main.
  Side effect: a command that only MENTIONS "pr merge" (a grep, a commit message) is refused
  too. Use `git commit -F <file>` and search with the Grep tool.
- GitHub's wall (Luke's settings): `doctor` required on main + "Do not allow bypassing".
  Until both are on, a merge made outside Claude is not checked.

## "merge" (Luke said it, naming the PR or clearly meaning one)
1. `gh pr view <N> -R itwillystyle/build-a-startup --json headRefOid,baseRefName,state,mergeable,statusCheckRollup`
   : open, base `main`, mergeable. Note `headRefOid`.
2. check + smoke green on that head. doctor green on that head: if missing, run the doctor gate
   (game-doctor skill, PR mode). A PR that changes nothing Rojo syncs (src/, Packages/,
   default.project.json) runs `lune run tools/bas checkup pr --post` with no files: it posts
   "not needed" as success.
3. `gh pr merge <N> -R itwillystyle/build-a-startup --squash --match-head-commit <headRefOid>`
   If anything was pushed since step 1, GitHub refuses: go back to step 1.
4. Stacked PRs whose base was this branch: `gh pr edit <M> --base main`, rebase, gate again.
   They are NOT mergeable on the old verdict.
5. In `game/`: `git pull --ff-only`. Tick the PR in `silicon-startup/GAME-OUTLINE.md`, then the
   work-map-rescan steps (`~/.claude/scheduled-tasks/work-map-rescan/SKILL.md`).
6. Tell Luke: merged as `<sha>`, NOT live until Alt+P, and that "check" comes before it.

## "check" (before Alt+P)
1. `game/` is on main and pulled. Start Rojo from `game/`
   (`~/.rokit/bin/rojo.exe serve default.project.json`, in the background) and let Studio's
   plugin sync (Connected, one Rojo plugin only).
2. **Stop Rojo** (stop that background task). From here until Luke's Alt+P nothing may sync
   into Studio, so what the check sees is what ships.
3. Fingerprint, Studio EDIT datamodel. Start the receiver first (interactive sessions only;
   never in a routine): `python -I tools/recv_once.py ../doctor/fingerprint-publish.json`
   in the background, then `execute_luau` (Edit):

       local H = require(game.ReplicatedStorage.SourceHash:Clone())
       local function pathOf(i) local t = {} while i and i ~= game do table.insert(t, 1, i.Name); i = i.Parent end return table.concat(t, "/") end
       local out = {}
       for _, svc in game:GetChildren() do
       	local ok, kids = pcall(function() return svc:GetDescendants() end)
       	if ok then
       		for _, d in kids do
       			local ok2, isScript = pcall(function() return d:IsA("LuaSourceContainer") end)
       			if ok2 and isScript then
       				local p = pathOf(d)
       				local e = true
       				pcall(function() if d:IsA("BaseScript") then e = d.Enabled end end)
       				out[p] = out[p] or {}
       				table.insert(out[p], { h = H.hash(d.Source), c = d.ClassName, e = e })
       			end
       		end
       	end
       end
       local HS = game:GetService("HttpService")
       return HS:PostAsync("http://127.0.0.1:34999/", HS:JSONEncode({ kind = "publish", v = 2, at = os.time(), scripts = out }))

4. From `game/`: `lune run tools/bas checkup publish ../doctor/fingerprint-publish.json`
   (it uses the file up; a re-check needs a new fingerprint).
   - PASS: tell Luke "SAFE to Alt+P" with the commit's short sha, and that Rojo stays stopped
     until he has published.
   - FAIL extra: scripts in Studio that main does not have, anywhere in the place. Show Luke the
     list. Delete only what he agrees to (ChangeHistoryService recording), then fingerprint and
     check again. Never delete a Studio-only script he wants kept: it goes into main first.
   - FAIL doubled: two Rojo plugins are syncing. Luke disables one; start again at step 1.
   - FAIL changed / missing / wrong type / switched off: Rojo did not sync main. Start again at 1.
   - FAIL only scripts: a synced file this cannot read (.json, .rbxm, ...). Add support (test
     first) before publishing; never delete its instance to make the check pass.
5. Leave Studio in Edit.

## "publish" / after Alt+P
1. Studio's log shows `PublishPlaceTime` (the Work Map's Needs-you list reads it).
2. Not proven yet (27 Oct): that Alt+P with Team Create ships exactly the Edit datamodel. After
   the first publish with this check, reopen the place, fingerprint, check again: it must PASS.
3. Restart Rojo when Luke is done publishing.
4. The next morning's health run and the live error log (SVErrors_v1) are the first look.
   Anything broken and live: docs/ROLLBACK.md (kill switch first, a fix PR second).
5. Ask Luke for his recorded run when he has played it (playtest-review).
