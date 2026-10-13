-- sourcehash.spec.luau: the PR doctor gate's two halves (12 Oct 2026). SourceHash proves
-- which code Studio ran; doctor_lib.prVerdict decides pass or fail from the findings.
local H = require("../../src/ReplicatedStorage/SourceHash")
local D = require("../../tools/doctor_lib")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

test("FNV-1a matches the published value, and Windows line endings do not change it", function()
	assert(H.hash("hello") == "4f9f2cab", "hello -> " .. H.hash("hello"))
	assert(H.hash("") == "811c9dc5", "the empty string is the offset basis")
	assert(H.hash("a\r\nb\r\n") == H.hash("a\nb\n"), "CRLF and LF hash the same")
	assert(H.hash("local x = 1") ~= H.hash("local x = 2"), "one character changes it")
	local big = string.rep("local x = 1\n", 2000)
	assert(H.hash(big) ~= H.hash(big .. " "), "the chunked loop reads past 4,000 bytes")
end)

test("file paths become the instance names Rojo gives them", function()
	assert(H.nameOf("src/ServerScriptService/SiliconCore.server.lua") == "SiliconCore", "a server script loses .server.lua")
	assert(H.nameOf("src/StarterPlayer/StarterPlayerScripts/HudClient.client.lua") == "HudClient", "a client script loses .client.lua")
	assert(H.nameOf("src/ReplicatedStorage/UIKit.lua") == "UIKit", "a module loses .lua")
	assert(H.nameOf("src\\ServerScriptService\\HQMeta\\init.lua") == "HQMeta", "init.lua takes its folder name")
	assert(H.nameOf("src/x/Thing.luau") == "Thing", ".luau works too")
end)

test("compare: same code passes; changed, missing or stale code is named", function()
	local files = {
		{ path = "src/A.server.lua", text = "print(1)" },
		{ path = "src/B.lua", text = "return 2" },
	}
	assert(#H.compare(files, { A = { H.hash("print(1)") }, B = { H.hash("return 2") }, Extra = { "00000000" } }) == 0,
		"an extra Studio script (a plugin, a Studio-only part) does not fail it")
	local bad = H.compare(files, { A = { H.hash("print(0)") } })
	assert(#bad == 2, "A differs and B is missing")
	assert(bad[1]:find("different code", 1, true) and bad[2]:find("not in Studio", 1, true), "each reason names its problem")
	assert(#H.compare(files, { A = { "x", H.hash("print(1)") }, B = { H.hash("return 2") } }) == 0,
		"two scripts with one name: either may match")
end)

local function f(key, sev) return { key = key, severity = sev } end

test("PR verdict: any BLOCKER fails; a BUG fails only when main did not have it", function()
	assert(D.prVerdict({}, {}).pass, "nothing found passes")
	assert(D.prVerdict({ f("hq:9 / cards over cards", "FEEL"), f("x / y", "MISSING") }, {}).pass, "FEEL and MISSING never block")
	local v = D.prVerdict({ f("chase:genius / the chase ran", "BLOCKER") }, { "chase:genius / the chase ran" })
	assert(not v.pass and #v.blockers == 1, "a BLOCKER fails even if main had it")
	assert(D.prVerdict({ f("hq:18 / lift lands you on a floor", "BUG") }, { "hq:9 / lift lands you on a floor" }).pass,
		"a BUG main already had (same family) is not this PR's")
	local n = D.prVerdict({ f("hq:9 / lift lands you on a floor", "BUG") }, {})
	assert(not n.pass and #n.newBugs == 1 and n.why[1]:find("new BUG", 1, true), "a new BUG fails, and says why")
end)

return T
