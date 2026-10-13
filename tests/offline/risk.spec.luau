-- risk.spec.luau: `bas risk` puts each changed file in the right kind, and says when Luke must look (13 Oct 2026)
local R = require("../../tools/risk_lib")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local CASES = {
	-- judges: a change here can make a broken game pass
	{ "tests/offline/savefuzz.spec.luau", "judge" },
	{ "tools/doctor_lib.luau", "judge" },
	{ "tools/staff_sim.luau", "judge" },
	{ "tools/chase_tune.luau", "judge" },
	{ "tools/fuzz_remotes.luau", "judge" },
	{ "src/ServerScriptService/GameDoctor.server.lua", "judge" },
	{ "src/ReplicatedStorage/SourceHash.lua", "judge" },
	{ "src/ReplicatedStorage/SVCheck.lua", "judge" },
	{ "CONSTRAINTS.md", "judge" },
	-- what runs the judges
	{ ".github/workflows/ci.yml", "ci" },
	{ "hooks/pre-commit", "ci" },
	{ "selene.toml", "ci" },
	{ "default.project.json", "ci" },
	{ "tools/bas.luau", "ci" },
	-- the save, the numbers, the rest of the game
	{ "src/ServerScriptService/SaveLoad.lua", "save" },
	{ "src/ServerScriptService/RoomEconomy.lua", "economy" },
	{ "src/ReplicatedStorage/StaffStats.lua", "economy" },
	{ "src/ServerScriptService/WaferPlan.lua", "economy" },
	{ "src/ServerScriptService/Wafers.lua", "gameplay" },
	{ "src/ReplicatedStorage/ServerRack.lua", "gameplay" },
	{ "src/StarterPlayer/StarterPlayerScripts/HudClient.client.lua", "gameplay" },
	-- routine
	{ "tools/ui_audit.luau", "tooling" },
	{ "docs/features/hq-paths.md", "docs" },
	{ "README.md", "docs" },
	{ "TOMORROW.md", "docs" },
}

test("every kind of file lands in its kind (judges before gameplay, save before gameplay)", function()
	for _, c in CASES do
		local got = R.kindOf(c[1])
		assert(got == c[2], ("%s: want %s, got %s"):format(c[1], c[2], got))
	end
end)

test("Windows backslash paths classify the same", function()
	assert(R.kindOf("tests\\offline\\x.spec.luau") == "judge", "backslash test path")
	assert(R.kindOf("src\\ServerScriptService\\SaveLoad.lua") == "save", "backslash save path")
end)

test("docs-only and tooling-only branches do not need Luke; one judge, save or game file does", function()
	assert(not R.classify({ "docs/features/garage.md", "README.md", "tools/ui_audit.luau" }).needsLuke, "routine branch flagged")
	for _, p in { "tests/offline/x.spec.luau", "src/ServerScriptService/SaveLoad.lua", "src/ServerScriptService/Wafers.lua", ".github/workflows/ci.yml" } do
		assert(R.classify({ "docs/a.md", p }).needsLuke, p .. " should need Luke")
	end
	assert(not R.classify({}).needsLuke, "an empty branch needs nobody")
end)

test("the list comes back most serious first, with counts and a reason on every file", function()
	local r = R.classify({ "docs/a.md", "src/ServerScriptService/Wafers.lua", "tests/offline/x.spec.luau", "" })
	assert(#r.files == 3, "the empty path must be dropped")
	assert(r.files[1].kind == "judge" and r.files[2].kind == "gameplay" and r.files[3].kind == "docs", "order")
	assert(r.counts.judge == 1 and r.counts.gameplay == 1 and r.counts.docs == 1, "counts")
	for _, f in r.files do assert(type(f.why) == "string" and #f.why > 0, "no reason for " .. f.path) end
end)

return T
