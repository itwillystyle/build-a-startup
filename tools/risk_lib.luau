--[[ risk_lib.luau -- which changed files need Luke's eyes before a merge (13 Oct 2026). Pure.

	From the Anthropic source-control article (13 Oct): their review tooling expresses
	approval rules by MEANING (a comment-only change vs sensitive logic), and humans
	review intent. Here that becomes: given the files a branch changes, say which kind
	of change each is and whether the branch needs Luke. Used by `bas risk`; tested by
	tests/offline/risk.spec.luau.

	The kinds, most serious first (a file takes the first that matches):
	  judge     tests and the things that grade the game (doctor, sims, tuners, fuzzers,
	            SVCheck, SourceHash). A change here can make a broken game PASS: an agent
	            that edits the test instead of the code (ImpossibleBench) looks green.
	  ci        workflows, hooks, lint config, the Rojo project: what runs the judges.
	  save      the save path. A bug here costs a player their progress.
	  economy   the numbers (prices, rates, caps, gates).
	  gameplay  any other game code: what players see and do.
	  tooling   other tools/, art/ and blender/ scripts: routine.
	  docs      docs and markdown: routine.
	  unknown   a path no rule knows. Needs Luke: a new kind of file is blocked by
	            default, not waved through (review of #52: Packages/, which ships to
	            every player, and the sims used to fall through to "tooling").
	needs Luke = any judge, ci, save, economy, gameplay or unknown file. Matches CONSTRAINTS.md
	rule 5 (no auto-merge for gameplay, look, economy, save, judge or CI changes). ]]
local R = {}

R.ORDER = { "judge", "ci", "save", "economy", "gameplay", "tooling", "docs" }
R.NEEDS_LUKE = { judge = true, ci = true, save = true, economy = true, gameplay = true, unknown = true }
R.WHY = {
	judge = "a test or judge: a change here can make a broken game pass",
	ci = "CI, hooks or project config: what runs the judges",
	save = "the save path: a bug here costs a player their progress",
	economy = "the economy numbers",
	gameplay = "game code: what players see and do",
	tooling = "a tool script (routine)",
	docs = "docs (routine)",
	unknown = "no rule knows this path: Luke decides",
}

-- each rule: a Lua pattern on the forward-slash path, anchored by the caller
local RULES = {
	judge = {
		"^tests/", "^tools/[%w_]*_lib%.luau$", "^tools/staff_sim%.luau$", "^tools/chase_tune%.luau$",
		"^tools/fuzz_[%w_]*%.luau$", "^tools/cloud_smoke%.luau$", "^tools/smoke_[%w_]*%.luau$",
		"/GameDoctor[%w_.]*%.lua$", "/DoctorProbes%.lua$", "/DoctorClient[%w_.]*%.lua$",
		"/SVCheck%.lua$", "/SourceHash%.lua$", "^CONSTRAINTS%.md$",
		-- the seeded sims `bas sim` and `baseline diff` judge, and the Studio audits
		"^tools/chase_threat%.luau$", "^tools/late_game%.luau$", "^tools/chase_sim%.luau$",
		"^tools/curve_check%.luau$", "^tools/algo_check%.luau$", "^tools/world_overlap%.luau$",
		"^tools/ui_audit%.luau$", "^tools/ui_overlap%.luau$", "^art/STYLE%-SPEC%.md$",
	},
	ci = { "^%.github/", "^hooks/", "^selene%.toml$", "^stylua%.toml$", "^rokit%.toml$",
		"^default%.project%.json$", "^smoke%.project%.json$", "^tools/routine%.sh$", "^tools/bas%.luau$",
		"^Packages/", "^wally%.toml$", "^wally%.lock$", "^%.gitattributes$", "^%.gitignore$", "^serve%.cmd$" },
	save = { "/SaveLoad%.lua$", "/DataStore", "/Save[%w_]*%.lua$" },
	economy = { "/RoomEconomy%.lua$", "/Progression%.lua$", "/CoreConfig%.lua$", "/WaferPlan%.lua$",
		"/StaffStats%.lua$", "/Momentum%.lua$", "/Inventory%.lua$", "/DailyReward%.lua$" },
	gameplay = { "^src/" },
	tooling = { "^tools/", "^art/", "^blender/" },
	docs = { "^docs/", "%.md$" },
}
R.ORDER_ALL = table.clone(R.ORDER)
table.insert(R.ORDER_ALL, "unknown")

function R.kindOf(path)
	path = (path or ""):gsub("\\", "/")
	for _, kind in R.ORDER do
		for _, pat in RULES[kind] do
			if path:find(pat) then return kind end
		end
	end
	return "unknown"
end

-- paths -> { needsLuke, files = { {path, kind, why} } (most serious first), counts }
function R.classify(paths)
	local files, counts, needs = {}, {}, false
	local rank = {}
	for i, k in R.ORDER_ALL do rank[k] = i end
	for _, p in paths or {} do
		if p ~= "" then
			local k = R.kindOf(p)
			table.insert(files, { path = p, kind = k, why = R.WHY[k] })
			counts[k] = (counts[k] or 0) + 1
			if R.NEEDS_LUKE[k] then needs = true end
		end
	end
	table.sort(files, function(a, b)
		if rank[a.kind] ~= rank[b.kind] then return rank[a.kind] < rank[b.kind] end
		return a.path < b.path
	end)
	return { needsLuke = needs, files = files, counts = counts }
end

return R
