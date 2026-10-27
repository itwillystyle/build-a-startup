-- publishcheck.spec.luau: `bas checkup publish`, the check before Alt+P (27 Oct 2026).
-- On 27 Oct Rojo served main while Studio still held 7 Bob scripts from another branch
-- ($ignoreUnknownInstances keeps what Rojo does not know). SourceHash.compare passed it: it only
-- asks "is each file in Studio?". This check also asks "is anything in Studio that is not a file?"
-- v2 (same day, after review): script type and enabled state count, every service is fingerprinted,
-- files the check cannot verify fail it, and the fingerprint must be fresh and honest.
local H = require("../../src/ReplicatedStorage/SourceHash")
local P = require("../../tools/publish_lib")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local MOUNTS = P.mounts({
	["$className"] = "DataModel",
	ReplicatedStorage = { ["$path"] = "src/ReplicatedStorage", Packages = { ["$path"] = "Packages" } },
	ServerScriptService = { ["$path"] = "src/ServerScriptService" },
	StarterPlayer = { StarterPlayerScripts = { ["$path"] = "src/StarterPlayer/StarterPlayerScripts" } },
})
local NESTED = { { dir = "Packages/_Index/littensy_ripple@0.10.2/ripple", sub = "src" } }

-- a Studio entry: what the fingerprint snippet records for one script
local function S(text, class, enabled)
	return { h = H.hash(text), c = class or "ModuleScript", e = enabled == nil and true or enabled }
end

test("mounts come from the project tree, deepest instance path kept", function()
	local m = {}
	for _, x in MOUNTS do m[x.dir] = x.inst end
	assert(m["src/ReplicatedStorage"] == "ReplicatedStorage", "ReplicatedStorage")
	assert(m["Packages"] == "ReplicatedStorage/Packages", "Packages sits inside ReplicatedStorage")
	assert(m["src/StarterPlayer/StarterPlayerScripts"] == "StarterPlayer/StarterPlayerScripts", "nested service")
	assert(#MOUNTS == 4, "four mounts, got " .. #MOUNTS)
end)

test("file paths become the instance paths Studio shows", function()
	local function ip(p) return P.instancePath(p, MOUNTS, NESTED) end
	assert(ip("src/ServerScriptService/SiliconCore.server.lua") == "ServerScriptService/SiliconCore", "server script")
	assert(ip("src/StarterPlayer/StarterPlayerScripts/HudClient.client.lua") == "StarterPlayer/StarterPlayerScripts/HudClient", "client")
	assert(ip("src/ServerScriptService/HQMeta/init.lua") == "ServerScriptService/HQMeta", "init takes its folder")
	assert(ip("src/ServerScriptService/HQMeta/Dome.lua") == "ServerScriptService/HQMeta/Dome", "child of an init module")
	assert(ip("src\\ReplicatedStorage\\UIKit.lua") == "ReplicatedStorage/UIKit", "Windows slashes")
	assert(ip("Packages/Ripple.lua") == "ReplicatedStorage/Packages/Ripple", "a package link")
	assert(ip("Packages/_Index/littensy_ripple@0.10.2/ripple/src/init.luau")
		== "ReplicatedStorage/Packages/_Index/littensy_ripple@0.10.2/ripple", "a nested project's src is its folder")
	assert(ip("Packages/_Index/littensy_ripple@0.10.2/ripple/src/utils/oklab.luau")
		== "ReplicatedStorage/Packages/_Index/littensy_ripple@0.10.2/ripple/utils/oklab", "deeper in a nested project")
	assert(ip("tools/bas.luau") == nil, "a file outside every mount is not synced")
end)

test("init.server / init.client are their folder; init.spec is an ordinary module (review M1)", function()
	local function ip(p) return P.instancePath(p, MOUNTS, NESTED) end
	assert(ip("src/ServerScriptService/Boot/init.server.lua") == "ServerScriptService/Boot", "init.server")
	assert(ip("src/StarterPlayer/StarterPlayerScripts/Ui/init.client.luau") == "StarterPlayer/StarterPlayerScripts/Ui", "init.client")
	assert(ip("src/ReplicatedStorage/Foo/init.spec.lua") == "ReplicatedStorage/Foo/init.spec", "init.spec stays in Foo")
	assert(ip("src/ReplicatedStorage/Foo.Bar.lua") == "ReplicatedStorage/Foo.Bar", "a dotted name keeps its dot")
	assert(ip("src/ReplicatedStorage/Deep/A/B.luau") == "ReplicatedStorage/Deep/A/B", "plain folders, .luau")
end)

test("the class Rojo makes comes from the file suffix (review I8)", function()
	assert(P.classOf("src/ServerScriptService/X.server.lua") == "Script", "server")
	assert(P.classOf("src/StarterPlayer/StarterPlayerScripts/X.client.luau") == "LocalScript", "client")
	assert(P.classOf("src/ServerScriptService/Boot/init.server.lua") == "Script", "init.server")
	assert(P.classOf("src/ReplicatedStorage/X.lua") == "ModuleScript", "module")
	assert(P.classOf("src/ReplicatedStorage/Foo/init.lua") == "ModuleScript", "init module")
end)

test("files the check cannot verify are named (review I9)", function()
	for _, bad in { "src/ReplicatedStorage/Config.json", "src/ReplicatedStorage/X.model.json", "src/ReplicatedStorage/X.meta.json",
		"src/ReplicatedStorage/Y.rbxm", "src/ReplicatedStorage/Y.rbxmx", "src/ReplicatedStorage/Z.toml" } do
		assert(P.unverifiable(bad), bad .. " must be refused")
	end
	for _, fine in { "src/ReplicatedStorage/A.lua", "src/ReplicatedStorage/B.luau", "src/ReplicatedStorage/notes.md" } do
		assert(not P.unverifiable(fine), fine .. " is fine")
	end
end)

local function files(t)
	local out = {}
	for inst, v in t do
		local text, class = v, "ModuleScript"
		if type(v) == "table" then text, class = v[1], v[2] end
		table.insert(out, { inst = inst, text = text, class = class })
	end
	return out
end

test("audit: the same code everywhere passes", function()
	local a = P.audit(files({ ["ServerScriptService/A"] = { "print(1)", "Script" }, ["ReplicatedStorage/B"] = "return 2" }),
		{ ["ServerScriptService/A"] = { S("print(1)", "Script") }, ["ReplicatedStorage/B"] = { S("return 2") } })
	assert(P.clean(a), table.concat(P.describe(a, 5), "; "))
end)

test("audit: 27 Oct, seven scripts from another branch left in Studio, fail as extra", function()
	local studio = { ["ServerScriptService/A"] = { S("print(1)") } }
	local stale = { "ReplicatedStorage/BobClips", "ReplicatedStorage/BobFace", "ReplicatedStorage/BobRig",
		"ReplicatedStorage/BobScript", "ServerScriptService/BobBuilding",
		"StarterPlayer/StarterPlayerScripts/BobDoorClient", "StarterPlayer/StarterPlayerScripts/BobSceneClient" }
	for _, s in stale do studio[s] = { S("old") } end
	local a = P.audit(files({ ["ServerScriptService/A"] = "print(1)" }), studio)
	assert(not P.clean(a), "it must fail")
	assert(#a.extra == 7, "all seven named, got " .. #a.extra)
	assert(a.extra[1] == "ReplicatedStorage/BobClips", "sorted, by full path")
	assert(#a.changed == 0 and #a.missing == 0 and #a.doubled == 0, "only extras")
end)

test("audit: a stray script outside the synced folders is extra (review I7)", function()
	local a = P.audit(files({ ["ServerScriptService/A"] = "print(1)" }),
		{ ["ServerScriptService/A"] = { S("print(1)") }, ["Workspace/FreeModel/Script"] = { S("evil", "Script") } })
	assert(#a.extra == 1 and a.extra[1] == "Workspace/FreeModel/Script", "the toolbox script is named")
end)

test("audit: a script synced twice (two Rojo plugins) fails as doubled even if one copy matches", function()
	local a = P.audit(files({ ["ServerScriptService/A"] = "print(1)" }),
		{ ["ServerScriptService/A"] = { S("print(1)"), S("print(1)") } })
	assert(not P.clean(a) and #a.doubled == 1 and a.doubled[1] == "ServerScriptService/A", "doubled")
end)

test("audit: changed and missing code are named", function()
	local a = P.audit(files({ ["ServerScriptService/A"] = "print(1)", ["ReplicatedStorage/B"] = "return 2" }),
		{ ["ServerScriptService/A"] = { S("print(0)") } })
	assert(#a.changed == 1 and a.changed[1] == "ServerScriptService/A", "A changed")
	assert(#a.missing == 1 and a.missing[1] == "ReplicatedStorage/B", "B missing")
end)

test("audit: same text, wrong script type or switched off, fails (review I8)", function()
	local a = P.audit(files({ ["StarterPlayer/StarterPlayerScripts/Hud"] = { "x()", "Script" } }),
		{ ["StarterPlayer/StarterPlayerScripts/Hud"] = { S("x()", "LocalScript") } })
	assert(#a.wrongType == 1, "a LocalScript where main has a Script")
	local b = P.audit(files({ ["ServerScriptService/A"] = { "x()", "Script" } }),
		{ ["ServerScriptService/A"] = { S("x()", "Script", false) } })
	assert(#b.disabled == 1 and not P.clean(b), "a script switched off by hand")
end)

test("audit: a Script whose RunContext was changed by hand fails (review round 2, M2)", function()
	local client = S("x()", "Script")
	client.r = "Client"
	local a = P.audit(files({ ["ServerScriptService/A"] = { "x()", "Script" } }), { ["ServerScriptService/A"] = { client } })
	assert(#a.wrongType == 1 and a.wrongType[1]:find("RunContext Client", 1, true), "a server Script running on the client")
	local legacy = S("x()", "Script")
	legacy.r = "Legacy"
	assert(P.clean(P.audit(files({ ["ServerScriptService/A"] = { "x()", "Script" } }), { ["ServerScriptService/A"] = { legacy } })),
		"Legacy is what Rojo makes")
end)

test("summary lines: one per kind, capped, empty when clean", function()
	local a = P.emptyAudit()
	for i = 1, 12 do table.insert(a.extra, "ReplicatedStorage/X" .. i) end
	local lines = P.describe(a, 5)
	assert(#lines == 1 and lines[1]:find("12 extra", 1, true) and lines[1]:find("and 7 more", 1, true), lines[1] or "none")
	assert(#P.describe(P.emptyAudit(), 5) == 0, "clean has no lines")
end)

test("freshness: newer than the commit, under 10 minutes, not from the future, a real number (review I10, M3)", function()
	local now, commit = 100000, 99000
	assert(P.fresh(now - 60, now, commit), "a minute old is fresh")
	assert(not P.fresh(now - 11 * 60, now, commit), "eleven minutes is stale")
	assert(not P.fresh(commit - 1, now, commit), "older than the commit")
	assert(not P.fresh(now + 120, now, commit), "from the future")
	assert(not P.fresh("100000", now, commit), "a string is not a time")
	assert(not P.fresh(nil, now, commit), "missing")
end)

return T
