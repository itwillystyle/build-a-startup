-- publishcheck.spec.luau: `bas checkup publish`, the check before Alt+P (27 Oct 2026).
-- On 27 Oct Rojo served main while Studio still held 7 Bob scripts from another branch
-- ($ignoreUnknownInstances keeps what Rojo does not know). SourceHash.compare passed it: it only
-- asks "is each file in Studio?". This check also asks "is anything in Studio that is not a file?"
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

local function files(t)
	local out = {}
	for inst, text in t do table.insert(out, { inst = inst, text = text }) end
	return out
end

test("audit: the same code everywhere passes", function()
	local a = P.audit(files({ ["ServerScriptService/A"] = "print(1)", ["ReplicatedStorage/B"] = "return 2" }),
		{ ["ServerScriptService/A"] = { H.hash("print(1)") }, ["ReplicatedStorage/B"] = { H.hash("return 2") } })
	assert(P.clean(a), "nothing changed, missing, extra or doubled")
end)

test("audit: 27 Oct, seven scripts from another branch left in Studio, fail as extra", function()
	local studio = { ["ServerScriptService/A"] = { H.hash("print(1)") } }
	local stale = { "ReplicatedStorage/BobClips", "ReplicatedStorage/BobFace", "ReplicatedStorage/BobRig",
		"ReplicatedStorage/BobScript", "ServerScriptService/BobBuilding",
		"StarterPlayer/StarterPlayerScripts/BobDoorClient", "StarterPlayer/StarterPlayerScripts/BobSceneClient" }
	for _, s in stale do studio[s] = { "0badc0de" } end
	local a = P.audit(files({ ["ServerScriptService/A"] = "print(1)" }), studio)
	assert(not P.clean(a), "it must fail")
	assert(#a.extra == 7, "all seven named, got " .. #a.extra)
	assert(a.extra[1] == "ReplicatedStorage/BobClips", "sorted, by full path")
	assert(#a.changed == 0 and #a.missing == 0 and #a.doubled == 0, "only extras")
end)

test("audit: a script synced twice (two Rojo plugins) fails as doubled even if one copy matches", function()
	local a = P.audit(files({ ["ServerScriptService/A"] = "print(1)" }),
		{ ["ServerScriptService/A"] = { H.hash("print(1)"), H.hash("print(1)") } })
	assert(not P.clean(a) and #a.doubled == 1 and a.doubled[1] == "ServerScriptService/A", "doubled")
end)

test("audit: changed and missing code are named", function()
	local a = P.audit(files({ ["ServerScriptService/A"] = "print(1)", ["ReplicatedStorage/B"] = "return 2" }),
		{ ["ServerScriptService/A"] = { H.hash("print(0)") } })
	assert(#a.changed == 1 and a.changed[1] == "ServerScriptService/A", "A changed")
	assert(#a.missing == 1 and a.missing[1] == "ReplicatedStorage/B", "B missing")
end)

test("summary lines: one per kind, capped, empty when clean", function()
	local a = { changed = {}, missing = {}, doubled = {}, extra = {} }
	for i = 1, 12 do table.insert(a.extra, "ReplicatedStorage/X" .. i) end
	local lines = P.describe(a, 5)
	assert(#lines == 1 and lines[1]:find("12 extra", 1, true) and lines[1]:find("and 7 more", 1, true), lines[1] or "none")
	assert(#P.describe({ changed = {}, missing = {}, doubled = {}, extra = {} }, 5) == 0, "clean has no lines")
end)

return T
