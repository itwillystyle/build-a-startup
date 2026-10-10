--[[ smoke_project.luau -- the cloud smoke's build: the real project plus a way to start it.

	An Open Cloud Luau Execution task does not run the place's scripts (the DataModel is
	not running: RunService:IsRunning() is false, measured on the first cloud run, 9 Oct
	2026). ModuleScripts still load. So the smoke build carries a ModuleScript copy of the
	server script (ServerStorage.SmokeBoot, with a `return true` added at the end), and
	tools/smoke_task.luau requires it: the same code, started by hand.

	Writes (both git-ignored):
	    .smoke/SmokeBoot.lua       src/ServerScriptService/SiliconCore.server.lua + "return true"
	    smoke.project.json         default.project.json + ServerStorage.SmokeBoot
	Then: rojo build smoke.project.json -o build.rbxl
	Your real game never contains SmokeBoot: only this build does. ]]
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local CORE = "src/ServerScriptService/SiliconCore.server.lua"
local src = fs.readFile(CORE)
if not fs.isDir(".smoke") then fs.writeDir(".smoke") end
fs.writeFile(".smoke/SmokeBoot.lua", src .. "\n\nreturn true   -- added by tools/smoke_project.luau: a ModuleScript must return one value\n")

local project = serde.decode("json", fs.readFile("default.project.json"))
project.name = "BuildAStartupSmoke"
project.tree.ServerStorage = project.tree.ServerStorage or { ["$className"] = "ServerStorage" }
project.tree.ServerStorage.SmokeBoot = { ["$path"] = ".smoke/SmokeBoot.lua" }
fs.writeFile("smoke.project.json", serde.encode("json", project, true))
print(("smoke.project.json written (SmokeBoot = %s, %d KB)"):format(CORE, #src // 1024))
