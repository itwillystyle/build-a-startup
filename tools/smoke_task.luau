--[[ smoke_task.luau -- runs INSIDE Roblox, on the TEST place, via Open Cloud Luau Execution.

	tools/cloud_smoke.luau uploads the smoke build (tools/smoke_project.luau) as a saved,
	unpublished version of the test place, then sends this file as the task's script. The
	place's own scripts do not start in a task, so this starts the server script itself
	(its ModuleScript copy, ServerStorage.SmokeBoot) and watches.

	Returns one table (Open Cloud serialises it to JSON):
	  env      what the task server is (running? server? players?)
	  boot     did SiliconCore start, how far it got ([SV] lines seen), how long
	  modules  every ModuleScript: "ok", "yield" (waits on something the boot makes), or the error
	  errors   every error the log printed while all this ran (the thing that fails the check)
	  world    surfaces you would sink into (WorldHealth.sinking): any one fails the check
	  chase    every plot's drop-off route and each chase tier's spot (TalentDrop.health) ]]
local RunService = game:GetService("RunService")
local LogService = game:GetService("LogService")
local SSS = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")

local BOOT_WAIT = 60        -- seconds to let the world build
local MODULE_WAIT = 3       -- seconds before a require counts as "yield"

local lines, errors, warns = {}, {}, {}
LogService.MessageOut:Connect(function(msg, kind)
	if kind == Enum.MessageType.MessageError then
		table.insert(errors, msg:sub(1, 300))
	elseif kind == Enum.MessageType.MessageWarning then
		table.insert(warns, msg:sub(1, 200))
	end
	if msg:find("^%[SV%]") or msg:find("^SILICON VALLEY") then table.insert(lines, msg:sub(1, 200)) end
end)

local out = {
	env = {
		running = RunService:IsRunning(), server = RunService:IsServer(), studio = RunService:IsStudio(),
		players = #game:GetService("Players"):GetPlayers(), placeVersion = game.PlaceVersion,
	},
}

-- 1. boot the game. A task does not run the place's scripts (the DataModel is not
-- running), so the smoke build carries the server script as a ModuleScript,
-- ServerStorage.SmokeBoot (tools/smoke_project.luau), and requiring it runs it.
local boot = game:GetService("ServerStorage"):FindFirstChild("SmokeBoot")
local t0 = os.clock()
local booted = false
if boot then
	task.spawn(function()
		local ok, err = pcall(require, boot)
		if not ok then table.insert(errors, "SmokeBoot: " .. tostring(err):sub(1, 300)) end
	end)
	while os.clock() - t0 < BOOT_WAIT do
		task.wait(1)
		for _, l in lines do
			if l:find("^SILICON VALLEY") then booted = true end
		end
		if booted then break end
	end
end
out.boot = { found = boot ~= nil, reachedBanner = booted, seconds = math.floor(os.clock() - t0), svLines = #lines, first = lines[1], last = lines[#lines] }

-- 2. every module: loads, waits, or errors
local modules = {}
for _, root in { SSS, RS } do
	for _, d in root:GetDescendants() do
		if d:IsA("ModuleScript") then
			local done, ok, err = false, nil, nil
			task.spawn(function()
				ok, err = pcall(require, d)
				done = true
			end)
			local m0 = os.clock()
			while not done and os.clock() - m0 < MODULE_WAIT do task.wait() end
			modules[d:GetFullName()] = (not done) and "yield" or (ok and "ok" or ("error: " .. tostring(err):sub(1, 200)))
		end
	end
end
out.modules = modules

-- 3. the two 10 Oct loops, on the world the boot just built: surfaces you would
-- sink into (WorldHealth) and the chase (TalentDrop.health: every plot's drop-off
-- joins the street, every chase tier finds a spot in its band)
if booted then
	local sv = workspace:FindFirstChild("SiliconValley")
	local okW, world = pcall(function()
		return require(SSS:WaitForChild("WorldHealth")).sinking(sv, { sv and sv:FindFirstChild("TalentRow") })
	end)
	out.world = okW and world or { error = tostring(world):sub(1, 300) }
	local okC, chase = pcall(function() return require(SSS:WaitForChild("TalentDrop")).health(3) end)
	out.chase = okC and chase or { error = tostring(chase):sub(1, 300) }
end
out.errors = errors
out.warnings = #warns
out.firstWarnings = { warns[1], warns[2], warns[3] }
out.svLines = lines
return out
