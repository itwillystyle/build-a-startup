--[[ health.spec.luau -- the morning run's parsers, checked against planted logs.

	`bas world` and `bas ship` read Studio's log files. A parser that silently
	matches nothing reports a healthy world forever, so every rule here is
	tested both ways: the clean log passes, and a planted fault is caught. ]]
local H = require("../../tools/health_lib")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

-- lines in the exact shape Studio writes (copied from the 9 Oct log, numbers kept)
local function out(t, msg) return ("2026-10-09T10:15:%02d.540Z,112.5,5a90,6,Info [FLog::CreatorOutput] %s"):format(t, msg) end
local function warnL(t, msg) return ("2026-10-09T10:15:%02d.540Z,112.5,5a90,6,Warning [FLog::CreatorWarning] Warning: %s"):format(t, msg) end
local function errL(t, msg) return ("2026-10-09T10:15:%02d.540Z,112.5,5a90,6,Error [FLog::CreatorError] Error: %s"):format(t, msg) end

local function boot(t0, o)
	o = o or {}
	return {
		out(t0, ("[SV] FurnitureKit: %d/33 meshes present"):format(o.meshes or 33)),
		out(t0 + 1, ("[SV] low-poly valley: 100 tiles, 1232 collision wedges, %d hill trees, 8 ponds, 26 clouds"):format(o.trees or 4568)),
		warnL(t0 + 2, "[SV] HQ_1_Shell: roof collision was 14.50, mesh top is 18.05 -- realigned"),
		out(t0 + 3, ("[SV] placement final: 37 in paving -> 0 pits, 37 moved, 0 removed | %d left"):format(o.left or 0)),
		out(t0 + 4, "[SV] palette: re-tinted 2033 parts, washed 78 pack meshes, tagged 23 emissives"),
		out(t0 + 5, "[SV] flat look: 3860 parts flattened, watching for more"),
		out(t0 + 6, "[StaffRig] 8/8 avatar templates ready"),
		out(t0 + 7, ("[SV] shadows: %d candidate props cached"):format(o.shadows or 8917)),
	}
end
local function log(...)
	local all = {}
	for _, chunk in { ... } do for _, l in chunk do table.insert(all, l) end end
	return table.concat(all, "\n")
end

test("a log line parses in both shapes Studio writes", function()
	local a = H.parseLine("2026-10-09T10:15:21.540Z,112.540138,5a90,6,Info [FLog::CreatorOutput] [SV] FurnitureKit: 33/33 meshes present")
	assert(a and a.channel == "FLog::CreatorOutput" and a.level == "Info", "info line")
	assert(a.msg == "[SV] FurnitureKit: 33/33 meshes present", "message: " .. tostring(a.msg))
	assert(a.unix == 1791540921, "unix time " .. tostring(a.unix))
	local b = H.parseLine("2026-10-08T05:35:11.942Z,11411.942383,ef04,6 [FLog::StudioTimingLog] PublishPlaceTime : 11411.9424 sec")
	assert(b and b.channel == "FLog::StudioTimingLog" and b.level == "", "timing line")
	assert(H.parseLine("not a log line") == nil, "junk must not parse")
	assert(H.isoToUnix("2000-02-29T23:59:59") == 951868799, "leap day")
end)

test("the newest save and publish are found", function()
	local text = table.concat({
		"2026-10-08T05:35:03.106Z,1,ef04,6,Info [DFLog::StudioPerformanceMeasurementsSummary] StudioPerformanceMeasurements summary for StudioSavePlaceToCloud: 1592ms",
		"2026-10-08T05:35:11.942Z,1,ef04,6 [FLog::StudioTimingLog] PublishPlaceTime : 11411.9424 sec",
		"2026-10-09T06:28:06.906Z,1,fc78,6,Info [DFLog::StudioPerformanceMeasurementsSummary] StudioPerformanceMeasurements summary for StudioSavePlaceToCloud: 1444ms",
		"2026-10-09T06:28:12.465Z,1,fc78,6 [FLog::StudioTimingLog] PublishPlaceTime : 4531.4653 sec",
	}, "\n")
	local save, publish = H.saveAndPublish(text)
	assert(save == "2026-10-09T06:28:06", "save " .. tostring(save))
	assert(publish == "2026-10-09T06:28:12", "publish " .. tostring(publish))
end)

test("the LAST boot in a log is the run that counts, and every metric is read", function()
	local text = log(boot(0, { trees = 1 }), boot(20))
	local run = H.lastRun(text)
	assert(run, "no run found")
	assert(run.metrics.hillTrees == 4568, "read the first boot, not the last: " .. tostring(run.metrics.hillTrees))
	local want = { "furnitureMeshes", "furnitureTotal", "tiles", "wedges", "hillTrees", "ponds", "clouds", "retinted",
		"washed", "emissives", "flattened", "greeneryInPaving", "avatars", "avatarTotal", "shadowProps" }
	for _, k in want do assert(run.metrics[k] ~= nil, "metric not read: " .. k) end
	assert(#run.errors == 0, "a clean boot has no errors")
	assert(H.lastRun("no boot here") == nil, "a log with no boot has no run")
end)

test("a clean run against itself raises nothing; normal drift is not a fault", function()
	local good = H.lastRun(log(boot(0)))
	local now = H.lastRun(log(boot(0, { shadows = 8943 })))
	local flags = H.compareWorld(good, now)
	assert(#flags == 0, "flagged a clean run: " .. (flags[1] and flags[1].text or ""))
end)

test("planted faults are caught: lost trees, a missing mesh, greenery left in paving", function()
	local good = H.lastRun(log(boot(0)))
	local function levels(o)
		local f = H.compareWorld(good, H.lastRun(log(boot(0, o))))
		local fails = 0
		for _, x in f do if x.level == "fail" then fails += 1 end end
		return fails, f
	end
	assert(levels({ trees = 4000 }) >= 1, "4568 -> 4000 hill trees was not caught")
	assert(levels({ meshes = 32 }) >= 1, "a missing furniture mesh was not caught")
	assert(levels({ left = 3 }) >= 1, "greenery left standing in paving was not caught")
end)

test("a script error fails the run; the MCP bridge's own errors do not", function()
	local good = H.lastRun(log(boot(0)))
	local bridge = H.lastRun(log(boot(0), { errL(30, "AssistantCommand:1: attempt to index nil with 'Value'") }))
	assert(#bridge.errors == 0, "counted the bridge's error as the game's")
	local real = H.lastRun(log(boot(0), { errL(30, "ServerScriptService.TalentDrop:52: attempt to index nil") }))
	local f = H.compareWorld(good, real)
	assert(f[1] and f[1].level == "fail" and f[1].text:find("TalentDrop", 1, true), "a real script error was not a failure")
end)

test("a new kind of warning is reported; the same warning with new numbers is not", function()
	local good = H.lastRun(log(boot(0)))
	local same = H.lastRun(log(boot(0), { warnL(40, "[SV] HQ_1_Shell: roof collision was 12.00, mesh top is 19.00 -- realigned") }))
	assert(#H.compareWorld(good, same) == 0, "a known warning with other numbers was reported as new")
	local new = H.lastRun(log(boot(0), { warnL(40, "Infinite yield possible on 'Players.devmeistah.PlayerGui:WaitForChild(\"CallCar\")'") }))
	local f = H.compareWorld(good, new)
	assert(f[1] and f[1].level == "warn" and f[1].text:find("Infinite yield", 1, true), "a new warning was not reported")
end)

test("the ship gap: nothing unpublished is green, old unpublished work and stale branches are red", function()
	local now = 1791540921
	local day = 86400
	local function find(checks, name) for _, c in checks do if c.name == name then return c end end return nil end
	local clean = H.ship({ now = now, lastPublish = now - day, mainSince = {}, branches = {} })
	assert(find(clean, "live").ok and find(clean, "branches").ok, "a fully published, fully merged repo was not green")
	local behind = H.ship({ now = now, lastPublish = now - 5 * day,
		mainSince = { { sha = "b", unix = now - day }, { sha = "a", unix = now - 3 * day } }, branches = {} })
	assert(find(behind, "live").ok == false, "work unpublished for 3 days was not red")
	local fresh = H.ship({ now = now, lastPublish = now - 2 * day,
		mainSince = { { sha = "a", unix = now - day } }, branches = {} })
	assert(find(fresh, "live").ok, "a day-old commit is not late yet")
	local stale = H.ship({ now = now, lastPublish = now, mainSince = {},
		branches = { { name = "old-idea", ahead = 4, lastUnix = now - 10 * day } } })
	assert(find(stale, "branches").ok == false, "a 10-day-old unmerged branch was not red")
	local none = H.ship({ now = now, mainSince = {}, branches = {} })
	assert(find(none, "live").level == "warn", "no publish in the logs must be a warning, not a pass")
end)

return T
