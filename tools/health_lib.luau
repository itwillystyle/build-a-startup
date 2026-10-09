--[[ health_lib -- the pure half of `bas ship`, `bas world` and `bas health` (Phase 2, 9 Oct 2026).

	No fs, no git, no process: it takes text and numbers and returns tables, so
	tests/offline/health.spec.luau can check it against planted logs. bas.luau does the
	reading (Studio logs, git) and the writing (HEALTH.md). ]]
local H = {}

-- ============ time ============
-- days since 1970-01-01 for a civil date (Howard Hinnant's algorithm)
local function daysFromCivil(y, m, d)
	y = m <= 2 and y - 1 or y
	local era = (y >= 0 and y or y - 399) // 400
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = (153 * mp + 2) // 5 + d - 1
	local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
	return era * 146097 + doe - 719468
end

-- "2026-10-09T10:15:21" (UTC) -> unix seconds
function H.isoToUnix(iso)
	local y, mo, d, h, mi, s = iso:match("^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)")
	if not y then return nil end
	return daysFromCivil(tonumber(y), tonumber(mo), tonumber(d)) * 86400
		+ tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(s)
end

-- ============ the Studio log ============
--[[ One line of a Studio log:
	2026-10-09T10:15:21.540Z,112.54,5a90,6,Info [FLog::CreatorOutput] [SV] FurnitureKit: 33/33 ...
	2026-10-08T05:35:11.942Z,11411.94,ef04,6 [FLog::StudioTimingLog] PublishPlaceTime : 11411.9424 sec
	-> { iso, unix, level, channel, msg } or nil ]]
function H.parseLine(line)
	local iso, rest = line:match("^(%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d)[%.%d]*Z,[^,]*,[^,]*,(.*)$")
	if not iso then return nil end
	local level, channel, msg = rest:match("^%d+,?(%a*)%s*%[([^%]]+)%]%s?(.*)$")
	if not channel then return nil end
	return { iso = iso, unix = H.isoToUnix(iso), level = level, channel = channel, msg = msg }
end

-- the newest cloud save and publish in one log (either may be nil)
function H.saveAndPublish(text)
	local save, publish
	for line in text:gmatch("[^\r\n]+") do
		if line:find("StudioSavePlaceToCloud", 1, true) or line:find("PublishPlaceTime", 1, true) then
			local p = H.parseLine(line)
			if p then
				if line:find("PublishPlaceTime", 1, true) then publish = p.iso else save = p.iso end
			end
		end
	end
	return save, publish
end

--[[ The world prints its own health on every server boot. Each pattern is matched
	against the message; `keys` names the captures. A number in MUST_NOT_DROP that
	falls is a failure, one in MUST_NOT_RISE that climbs is a failure, and any other
	that moves by more than 10% is reported (these drift a little run to run: the
	shadow cache counted 8,917 and 8,943 on two clean boots, 9 Oct). ]]
H.METRICS = {
	{ pat = "%[SV%] FurnitureKit: (%d+)/(%d+) meshes present", keys = { "furnitureMeshes", "furnitureTotal" } },
	{ pat = "%[SV%] low%-poly valley: (%d+) tiles, (%d+) collision wedges, (%d+) hill trees, (%d+) ponds, (%d+) clouds",
		keys = { "tiles", "wedges", "hillTrees", "ponds", "clouds" } },
	{ pat = "%[SV%] palette: re%-tinted (%d+) parts, washed (%d+) pack meshes, tagged (%d+) emissives",
		keys = { "retinted", "washed", "emissives" } },
	{ pat = "%[SV%] flat look: (%d+) parts flattened", keys = { "flattened" } },
	{ pat = "%[SV%] placement final: .-| (%d+) left", keys = { "greeneryInPaving" } },
	{ pat = "%[StaffRig%] (%d+)/(%d+) avatar templates ready", keys = { "avatars", "avatarTotal" } },
	{ pat = "%[SV%] shadows: (%d+) candidate props cached", keys = { "shadowProps" } },
}
H.MUST_NOT_DROP = { furnitureMeshes = true, tiles = true, wedges = true, hillTrees = true, ponds = true,
	clouds = true, avatars = true, emissives = true }
H.MUST_NOT_RISE = { greeneryInPaving = true }
H.BOOT = "[SV] FurnitureKit:"     -- the first line every server boot prints

-- noise that is not the game's: the MCP bridge, Rojo reconnects, Studio's own UI
local NOISE = { "AssistantCommand", "AssistantBridge", "sabuiltin_Assistant", "Rojo%-Warn", "%[Roblox%]" }
local function isNoise(msg)
	for _, n in NOISE do if msg:find(n) then return true end end
	return false
end

-- numbers and quoted names vary run to run; the SHAPE of a warning is what is new or not
function H.shape(msg)
	return (msg:gsub("^Warning: ", ""):gsub("%d+%.?%d*", "#"):sub(1, 140))
end

--[[ The last server boot in a log (a Play run), or nil if the log has none.
	-> { startIso, startUnix, metrics = { name = n }, errors = { msg }, warnings = { shape = count } } ]]
function H.lastRun(text)
	local lines = {}
	for line in text:gmatch("[^\r\n]+") do table.insert(lines, line) end
	local start
	for i = #lines, 1, -1 do
		if lines[i]:find(H.BOOT, 1, true) then start = i break end
	end
	if not start then return nil end
	local first = H.parseLine(lines[start])
	local run = { startIso = first and first.iso, startUnix = first and first.unix, metrics = {}, errors = {}, warnings = {} }
	for i = start, #lines do
		local p = H.parseLine(lines[i])
		if p then
			if p.channel == "FLog::CreatorError" and not isNoise(p.msg) then
				table.insert(run.errors, p.msg:sub(1, 200))
			elseif p.channel == "FLog::CreatorWarning" and not isNoise(p.msg) then
				local k = H.shape(p.msg)
				run.warnings[k] = (run.warnings[k] or 0) + 1
			end
			for _, m in H.METRICS do
				local caps = { p.msg:match(m.pat) }
				if #caps > 0 then
					for j, key in m.keys do run.metrics[key] = tonumber(caps[j]) end
				end
			end
		end
	end
	return run
end

--[[ Compare a run with the last good one. -> list of { level = "fail"|"warn", text }.
	`good` may be nil (first run: only the absolute rules apply). ]]
function H.compareWorld(good, now)
	local out = {}
	local m = now.metrics
	if #now.errors > 0 then
		table.insert(out, { level = "fail", text = ("%d script error(s), first: %s"):format(#now.errors, now.errors[1]) })
	end
	if m.furnitureMeshes and m.furnitureTotal and m.furnitureMeshes < m.furnitureTotal then
		table.insert(out, { level = "fail", text = ("furniture meshes %d/%d"):format(m.furnitureMeshes, m.furnitureTotal) })
	end
	if m.avatars and m.avatarTotal and m.avatars < m.avatarTotal then
		table.insert(out, { level = "fail", text = ("avatar templates %d/%d"):format(m.avatars, m.avatarTotal) })
	end
	if not good then return out end
	local names = {}
	for k in good.metrics do table.insert(names, k) end
	table.sort(names)
	for _, k in names do
		local was, is = good.metrics[k], m[k]
		if is == nil then
			table.insert(out, { level = "fail", text = ("%s: the line that reports it is gone (was %d)"):format(k, was) })
		elseif H.MUST_NOT_DROP[k] and is < was then
			table.insert(out, { level = "fail", text = ("%s dropped %d -> %d"):format(k, was, is) })
		elseif H.MUST_NOT_RISE[k] and is > was then
			table.insert(out, { level = "fail", text = ("%s rose %d -> %d"):format(k, was, is) })
		elseif was > 0 and math.abs(is - was) / was > 0.10 then
			table.insert(out, { level = "warn", text = ("%s moved %d -> %d"):format(k, was, is) })
		end
	end
	local shapes = {}
	for k in now.warnings do if not good.warnings[k] then table.insert(shapes, k) end end
	table.sort(shapes)
	for _, k in shapes do table.insert(out, { level = "warn", text = "new warning: " .. k }) end
	return out
end

-- ============ the ship gap ============
H.SHIP_LIVE_DAYS = 2      -- unpublished work older than this is red
H.SHIP_BRANCH_DAYS = 7    -- a branch with unmerged work, untouched this long, is red

--[[ s = { now, lastPublish, lastSave (unix or nil), mainSince = { { sha, unix, subject } }
	(main commits newer than the last publish, newest first), branches = { { name, ahead,
	lastUnix } } (local branches with work NOT on main) }. -> list of checks. ]]
function H.ship(s)
	local checks = {}
	local function days(t) return (s.now - t) / 86400 end
	if not s.lastPublish then
		table.insert(checks, { name = "live", ok = false, level = "warn", detail = "no publish found in the Studio logs" })
	elseif #s.mainSince == 0 then
		table.insert(checks, { name = "live", ok = true, detail = ("published %.1f days ago; main has nothing newer"):format(days(s.lastPublish)) })
	else
		local oldest = s.mainSince[#s.mainSince]
		local waited = days(oldest.unix)
		table.insert(checks, { name = "live", ok = waited <= H.SHIP_LIVE_DAYS,
			detail = ("%d commit(s) on main since the last publish (%.1f days ago); the oldest has waited %.1f days"):format(
				#s.mainSince, days(s.lastPublish), waited) })
	end
	if s.lastSave then
		table.insert(checks, { name = "studio save", ok = true, detail = ("last cloud save %.1f h ago"):format((s.now - s.lastSave) / 3600) })
	end
	if #s.branches == 0 then
		table.insert(checks, { name = "branches", ok = true, detail = "no local branch holds work that is not on main" })
	else
		local stale, parts = {}, {}
		for _, b in s.branches do
			local d = days(b.lastUnix)
			table.insert(parts, ("%s (+%d, %.0f d)"):format(b.name, b.ahead, d))
			if d > H.SHIP_BRANCH_DAYS then table.insert(stale, b.name) end
		end
		table.insert(checks, { name = "branches", ok = #stale == 0,
			detail = ("%d unmerged: %s%s"):format(#s.branches, table.concat(parts, ", "),
				#stale > 0 and ("; older than %d days: %s"):format(H.SHIP_BRANCH_DAYS, table.concat(stale, ", ")) or "") })
	end
	return checks
end

return H
