--[[ cloud_smoke.luau -- Phase 3: boot the real game on Roblox's servers for every PR.

	From the game folder, with the env set (GitHub Actions does this, see
	.github/workflows/cloud-smoke.yml):
	    ROBLOX_API_KEY   an Open Cloud key: universe-places:write + luau-execution-session:write,
	                     restricted to the TEST experience only (made by the Wilz alt)
	    SMOKE_UNIVERSE   the TEST experience's universe id
	    SMOKE_PLACE      the TEST place id
	    lune run tools/cloud_smoke [build.rbxl]

	1. Uploads the Rojo build as a SAVED version of the test place (versionType=Saved: never
	   published, nobody can join it). The live game is a different experience; the key cannot
	   reach it.
	2. Runs tools/smoke_task.luau there (Open Cloud Luau Execution), polls until it ends,
	   prints its result and logs, and writes a summary for the GitHub job page.
	Exit 0 = the task ran and reported no script errors; 1 = it failed or errored; 2 = setup.

	Limits (Roblox docs): 5 task creations a minute per key owner, 5 minutes a task, 10 at once
	per place. The workflow runs one smoke at a time. ]]
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")

local KEY = process.env.ROBLOX_API_KEY
local UNIVERSE = process.env.SMOKE_UNIVERSE
local PLACE = process.env.SMOKE_PLACE
local BUILD = process.args[1] or "build.rbxl"
local SUMMARY = process.env.GITHUB_STEP_SUMMARY

local function die(code, msg)
	print("cloud_smoke: " .. msg)
	process.exit(code)
end
if not (KEY and KEY ~= "" and UNIVERSE and PLACE) then die(2, "ROBLOX_API_KEY, SMOKE_UNIVERSE and SMOKE_PLACE must be set") end
if not fs.isFile(BUILD) then die(2, "no " .. BUILD .. " (rojo build default.project.json -o " .. BUILD .. ")") end

local function call(method, url, body, contentType)
	local ok, res = pcall(net.request, {
		url = url, method = method, body = body,
		headers = { ["x-api-key"] = KEY, ["Content-Type"] = contentType or "application/json" },
	})
	if not ok then die(1, method .. " " .. url .. " failed: " .. tostring(res)) end
	local decoded = nil
	pcall(function() decoded = serde.decode("json", res.body) end)
	return res.statusCode, decoded, res.body
end

-- 1. upload the build as a saved version
local bytes = fs.readFile(BUILD)
print(("uploading %s (%d KB) to place %s as a saved version"):format(BUILD, #bytes // 1024, PLACE))
-- 409 "Server is busy": usually the place is open in Studio (an edit session holds it);
-- it clears on its own, so wait and retry before failing the check
local code, up, raw
for attempt = 1, 4 do
	code, up, raw = call("POST",
		("https://apis.roblox.com/universes/v1/%s/places/%s/versions?versionType=Saved"):format(UNIVERSE, PLACE),
		bytes, "application/octet-stream")
	if code ~= 409 then break end
	print(("  upload busy (409), attempt %d of 4; is the TEST place open in Studio? retrying in 60 s"):format(attempt))
	if attempt < 4 then task.wait(60) end
end
if code ~= 200 or not (up and up.versionNumber) then die(1, ("upload: HTTP %d %s"):format(code, tostring(raw):sub(1, 400))) end
local version = up.versionNumber
print("saved as version " .. version)

-- 2. run the smoke task on exactly that version
local script = fs.readFile("tools/smoke_task.luau")
code, up, raw = call("POST",
	("https://apis.roblox.com/cloud/v2/universes/%s/places/%s/versions/%d/luau-execution-session-tasks"):format(UNIVERSE, PLACE, version),
	serde.encode("json", { script = script, timeout = "240s" }))
if code ~= 200 or not (up and up.path) then die(1, ("create task: HTTP %d %s"):format(code, tostring(raw):sub(1, 400))) end
local path = up.path
print("task " .. path)

local t0 = os.clock()
local result
repeat
	task.wait(5)
	code, result, raw = call("GET", "https://apis.roblox.com/cloud/v2/" .. path)
	if code ~= 200 then die(1, ("poll: HTTP %d %s"):format(code, tostring(raw):sub(1, 400))) end
	print(("  %s (%ds)"):format(tostring(result.state), math.floor(os.clock() - t0)))
until result.state == "COMPLETE" or result.state == "FAILED" or result.state == "CANCELLED"

-- the task's own log (print/warn/error from inside the place)
local logCode, logs = call("GET", "https://apis.roblox.com/cloud/v2/" .. path .. "/logs?view=FLAT")
local logLines = {}
if logCode == 200 and logs and logs.luauExecutionSessionTaskLogs then
	for _, page in logs.luauExecutionSessionTaskLogs do
		for _, m in page.messages or {} do table.insert(logLines, m) end
	end
end

local out = result.output and result.output.results and result.output.results[1]
print("---- result")
print(serde.encode("json", result.state == "COMPLETE" and out or result.error, true))
print(("---- log (%d lines)"):format(#logLines))
for i = 1, math.min(#logLines, 200) do print(logLines[i]) end

-- the verdict
local problems = {}
if result.state ~= "COMPLETE" then table.insert(problems, "task " .. tostring(result.state) .. ": " .. serde.encode("json", result.error or {})) end
if type(out) == "table" then
	for _, e in out.errors or {} do table.insert(problems, "script error: " .. e) end
	for name, state in out.modules or {} do
		if type(state) == "string" and state:find("^error") then table.insert(problems, name .. " " .. state) end
	end
	-- the world check: a visible surface you would sink into
	if type(out.world) == "table" then
		if out.world.error then table.insert(problems, "world check failed to run: " .. out.world.error) end
		for _, e in out.world.sinks or {} do
			table.insert(problems, ("you would sink %.1f studs into %s at (%d, %d): make it solid, or add it to WorldHealth.ALLOW with why"):format(e.gap, e.path, e.x, e.z))
		end
	end
	-- the chase check: every plot's drop-off reaches the street, every chase tier finds a spot
	if type(out.chase) == "table" then
		if out.chase.error then table.insert(problems, "chase check failed to run: " .. out.chase.error) end
		for _, p in out.chase.plots or {} do
			if type(p.door) == "string" and not p.door:find("^ok") then
				table.insert(problems, ("plot %s: no route from the drop-off to the street (%s)"):format(tostring(p.index), p.door))
			end
			for id, t in p.tiers or {} do
				if (t.found or 0) == 0 then
					table.insert(problems, ("plot %s: %s candidates found no spot in their band (they fall back to the drive)"):format(tostring(p.index), id))
				end
			end
		end
	end
	if out.boot and out.boot.found and not out.boot.reachedBanner then
		table.insert(problems, ("the server did not finish booting in %ds (%d [SV] lines)"):format(out.boot.seconds or 0, out.boot.svLines or 0))
	end
end

if SUMMARY then
	local md = { ("## Cloud smoke: %s"):format(#problems == 0 and "PASS" or "FAIL"), "",
		("Place version %d of the TEST experience (saved, never published). Task: %s."):format(version, tostring(result.state)) }
	if type(out) == "table" and out.boot then
		table.insert(md, ("Boot: banner %s after %ss, %s [SV] lines."):format(out.boot.reachedBanner and "reached" or "NOT reached",
			tostring(out.boot.seconds), tostring(out.boot.svLines)))
	end
	if type(out) == "table" and out.world then
		table.insert(md, ("World: %s surfaces checked, %s you would sink into."):format(tostring(out.world.checked), tostring(out.world.found)))
	end
	if type(out) == "table" and out.chase and out.chase.plots then
		for _, p in out.chase.plots do
			local t = {}
			for id, v in p.tiers or {} do table.insert(t, ("%s %d/%d"):format(id, v.found or 0, v.tries or 0)) end
			table.sort(t)
			table.insert(md, ("Chase, plot %s: drop-off %s; %s"):format(tostring(p.index), tostring(p.door), table.concat(t, ", ")))
		end
	end
	for _, p in problems do table.insert(md, "- " .. p) end
	pcall(fs.writeFile, SUMMARY, table.concat(md, "\n") .. "\n")
end
if #problems > 0 then
	print("---- FAIL")
	for _, p in problems do print("  " .. p) end
	process.exit(1)
end
print("---- PASS")
