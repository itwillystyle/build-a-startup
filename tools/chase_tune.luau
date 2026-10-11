--[[ chase_tune -- the overnight chase tuner (11 Oct 2026). The judge and the search
	are in tools/chase_tune_lib.luau; this is the clock, the bookkeeping and the report.

	    lune run tools/chase_tune -- --minutes 360        a night (the routine starts it at 01:30)
	    lune run tools/chase_tune -- --minutes 2          a smoke run

	Writes outside the repo, never touches a source file:
	    ../tuning/chase-<date>.json     every number: baseline, best, history, the edits
	    ../tuning/CHASE-TUNE.md         the morning read
	    ../tuning/chase-discord.txt     the short version (routine.sh chase-tune-post)
	    ../tuning/chase-progress.json   the best so far, rewritten on every improvement

	Landing a tuning is a person's call (it changes how the chase feels): say
	"apply the chase tuning" and the edits go in on a branch, checked live in Studio. ]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local L = require("./chase_tune_lib")

local args = process.args
local function arg(name, default)
	local i = table.find(args, name)
	return i and tonumber(args[i + 1]) or default
end
local MINUTES = arg("--minutes", 360)
local SEED = arg("--seed", os.time() % 100000)
local QUICK_N, QUICK_CUTS = 150, 12
local FULL_N, FULL_CUTS = 2000, 60
local OUT = "../tuning"
if not fs.isDir(OUT) then fs.writeDir(OUT) end

local function now() return os.clock() end
local t0 = now()
local deadline = t0 + MINUTES * 60
local stamp = os.date("%Y-%m-%d")

local function log(...)
	print(("[%5.1f min] "):format((now() - t0) / 60) .. string.format(...))
end

-- ============ the baseline ============
local base = L.read()
L.apply(base)
local baseOk, baseFails = L.contract()
local baseScore = L.measure(QUICK_N, QUICK_CUTS)
log("today's tuning: quick score %.0f, contract %s", baseScore, baseOk and "passes" or ("FAILS: " .. table.concat(baseFails, "; ")))

-- ============ the search ============
local rnd = L.rng(SEED)
local cur, curScore = base, baseScore
local best, bestScore = base, baseScore
local evals, accepted, contractRuns, contractFails = 0, 0, 0, 0
local history = { { min = 0, score = baseScore } }

local function saveProgress()
	fs.writeFile(OUT .. "/chase-progress.json", serde.encode("json", {
		at = os.date("%Y-%m-%d %H:%M"), evals = evals, bestScore = bestScore, baseScore = baseScore, best = best,
	}, true))
end

while now() < deadline do
	local temp = math.max(0.15, 1 - (now() - t0) / (MINUTES * 60))
	local cand = L.neighbour(cur, rnd, temp)
	L.apply(cand)
	local s = L.measure(QUICK_N, QUICK_CUTS)
	evals += 1
	-- better, or (early in the night) a little worse: a random walk that cools
	local take = s < curScore or rnd() < math.exp(-(s - curScore) / (40 * temp))
	if take then
		contractRuns += 1
		local ok = L.contract()
		if ok then
			cur, curScore = cand, s
			accepted += 1
			if s < bestScore then
				best, bestScore = cand, s
				table.insert(history, { min = math.floor((now() - t0) / 6) / 10, score = s })
				log("new best %.0f after %d tries", s, evals)
				saveProgress()
			end
		else
			contractFails += 1
		end
	end
	if evals % 250 == 0 then
		log("%d tries, %d moves, best %.0f (start %.0f), %d tries broke the contract", evals, accepted, bestScore, baseScore, contractFails)
	end
	if bestScore <= 0 and now() - t0 > 60 then break end   -- every target met
end

-- ============ the verdict, at full size ============
log("checking the winner on %d runs per row", FULL_N)
L.apply(base)
local b0Score, b0Rows, b0Cuts = L.measure(FULL_N, FULL_CUTS)
-- the cleanup: keep only the knobs that matter, then the values a person would type
log("pruning knobs that do not pull their weight")
local pruned = L.prune(best, function(p) L.apply(p); return (L.measure(QUICK_N * 2, QUICK_CUTS)) end, 0.03)
local landing = L.rounded(pruned)
L.apply(landing)
local okFinal, finalFails = L.contract()
local b1Score, b1Rows, b1Cuts = L.measure(FULL_N, FULL_CUTS)
local edits = L.diff(base, landing)
L.restore()

local improved = okFinal and b1Score < b0Score * 0.9 and #edits > 0
local report = {
	tool = "chase_tune", date = stamp, minutes = MINUTES, seed = SEED, evals = evals, moves = accepted,
	contractChecks = contractRuns, contractBreaks = contractFails,
	before = { score = b0Score, rows = b0Rows, cutsPerSec = b0Cuts },
	after = { score = b1Score, rows = b1Rows, cutsPerSec = b1Cuts, contract = okFinal, contractFails = finalFails },
	edits = edits, improved = improved, history = history,
}
fs.writeFile(OUT .. "/chase-" .. stamp .. ".json", serde.encode("json", report, true))

-- ============ the morning read ============
local md = {}
local function w(s) table.insert(md, s) end
w(("# Chase tuning, %s"):format(os.date("%a %d %b %Y")))
w("")
w(("%d tunings tried in %d minutes (seed %d), each one scored on %d simulated chases per row; the winner re-checked on %d."):format(
	evals, MINUTES, SEED, QUICK_N, FULL_N))
w("")
if improved then
	w(("**Verdict: better.** Score %.0f -> %.0f (0 = every target met). The contract (tests/offline/chase.spec and chasecam.spec) passes."):format(b0Score, b1Score))
elseif not okFinal then
	w("**Verdict: nothing to land.** The best tuning broke the chase contract once its values were rounded: " .. table.concat(finalFails, "; "))
else
	w(("**Verdict: no real gain** (score %.0f -> %.0f). Today's tuning stays."):format(b0Score, b1Score))
end
w("")
w("| Target | Today | Tuned | Wanted |")
w("|---|---|---|---|")
for i, r in b0Rows do
	local a = b1Rows[i]
	w(("| %s | %.0f%% | %.0f%% | %.0f%%+ |"):format(r.what, r.value * 100, a.value * 100, r.target * 100))
end
w(("| Camera cuts per second (simulated) | %.2f | %.2f | 0.50 or less |"):format(b0Cuts, b1Cuts))
w("")
if #edits > 0 then
	w("**The edits** (only what moved):")
	w("")
	for _, e in edits do
		w(("- `%s` %s: %s -> **%s**"):format(e.file, e.name, tostring(e.from), tostring(e.to)))
	end
	w("")
end
w("**What this cannot tell you.** It is a simulator: the players are scripted behaviours, and the camera")
w("count is a proxy (it matched the doctor's live 0.66-1.28 cuts/s on the doctor's own run, 0.90). Whether")
w("the chase is FUN is a person's call; whether players escape this often is the game's own recruit-run")
w("log (carry_end on the Creator Dashboard) once real players run it.")
w("")
w("The design spec also wants a star you just hold W on to escape 50-85%; the chase contract in CI says")
w("30% or less. The contract wins here; that one is your call.")
w("")
w("To land it: say **\"apply the chase tuning\"**. The edits go in on a branch, the chase tests run, the")
w("doctor runs the three live chases in Studio, and it becomes a PR you review.")
fs.writeFile(OUT .. "/CHASE-TUNE.md", table.concat(md, "\n") .. "\n")

local short = {}
table.insert(short, ("**Chase tuning, %s**: %s"):format(os.date("%a %d %b"),
	improved and ("better, score %.0f -> %.0f"):format(b0Score, b1Score) or "no tuning worth landing tonight"))
for i, r in b0Rows do
	local a = b1Rows[i]
	table.insert(short, ("- %s: %.0f%% -> %.0f%% (wants %.0f%%+)"):format(r.what, r.value * 100, a.value * 100, r.target * 100))
end
table.insert(short, ("- camera cuts/s (simulated): %.2f -> %.2f (wants 0.5 or less)"):format(b0Cuts, b1Cuts))
table.insert(short, ("%d tries, %d edits. Full read: silicon-startup/tuning/CHASE-TUNE.md. To land it: \"apply the chase tuning\"."):format(evals, #edits))
fs.writeFile(OUT .. "/chase-discord.txt", table.concat(short, "\n"))
log("done: %s", improved and "better" or "no gain")
print(table.concat(md, "\n"))
