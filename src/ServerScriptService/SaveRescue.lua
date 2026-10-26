--[[ SaveRescue (26 Oct 2026, safety net part 3): put a player's save back the way it was.
	Studio only, from the Edit datamodel (command bar or Studio MCP), like DevScenarios. Roblox
	keeps every version of a DataStore key for 30 days; this lists them and restores one.

	  local R = require(game.ServerScriptService.SaveRescue:Clone())
	  R.list(userId)                              -- newest first: version, when, cash, hq, ...
	  R.peek(userId, version)                     -- one version's numbers
	  R.restore(userId, version, "restore <userId>")

	Restore copies the CURRENT save into SVRescue_v1 first ("<userId>/<unix time>"), then writes
	the old version back with lastSeen = now, so a stale server session cannot overwrite it.
	The player must be OFFLINE: a live session saves over it within a minute (docs/ROLLBACK.md).
	tests/offline/saverescue.spec.luau ]]

local SaveRescue = {}

SaveRescue.STORE = "SVSave_v1"       -- SiliconCore's saveStore
SaveRescue.BACKUP = "SVRescue_v1"

-- versions newest first ({version, created (ms), deleted}) -> the newest kept one at or before `before` (unix s)
function SaveRescue.pick(versions, before)
	for _, v in versions do
		if not v.deleted and v.created <= before * 1000 then return v end
	end
	return nil
end

function SaveRescue.summary(data)
	if type(data) ~= "table" then return nil end
	local jr = type(data.jr) == "table" and data.jr or {}
	return { cash = data.cash, hq = data.hq, wl = data.wl, staff = data.staff, earned = data.earned,
		lastSeen = data.lastSeen, name = data.name, bobPaid = jr.bobPaid == true }
end

-- a save written in the last LIVE_S seconds belongs to a live session (autosave is every 120 s):
-- a restore now would be saved over (review I-4)
SaveRescue.LIVE_S = 200
function SaveRescue.live(data, now)
	return type(data) == "table" and type(data.lastSeen) == "number" and now - data.lastSeen < SaveRescue.LIVE_S
end

function SaveRescue.confirmed(userId, words)
	return words == ("restore %d"):format(userId)
end

local function store(name)
	return game:GetService("DataStoreService"):GetDataStore(name)
end

function SaveRescue.list(userId, n)
	local key = tostring(userId)
	local ok, pages = pcall(function()
		return store(SaveRescue.STORE):ListVersionsAsync(key, Enum.SortDirection.Descending, nil, nil, math.clamp(n or 20, 1, 100))
	end)
	if not ok then return { ok = false, err = tostring(pages) } end
	local out = {}
	for _, info in pages:GetCurrentPage() do
		table.insert(out, { version = info.Version, created = info.CreatedTime, deleted = info.IsDeleted,
			when = os.date("!%Y-%m-%d %H:%M UTC", math.floor(info.CreatedTime / 1000)) })
	end
	return { ok = true, versions = out }
end

function SaveRescue.peek(userId, version)
	local ok, data = pcall(function() return store(SaveRescue.STORE):GetVersionAsync(tostring(userId), version) end)
	if not ok then return { ok = false, err = tostring(data) } end
	return { ok = true, summary = SaveRescue.summary(data) }
end

-- force = true skips the "looks online" guard (only when you know the player has left)
function SaveRescue.restore(userId, version, words, force)
	if not SaveRescue.confirmed(userId, words) then
		return { ok = false, err = ("say exactly: restore %d"):format(userId) }
	end
	local key = tostring(userId)
	local okOld, old = pcall(function() return store(SaveRescue.STORE):GetVersionAsync(key, version) end)
	if not okOld or type(old) ~= "table" then return { ok = false, err = "could not read that version: " .. tostring(old) } end
	local okNow, now = pcall(function() return store(SaveRescue.STORE):GetAsync(key) end)
	if not okNow then return { ok = false, err = "could not read the current save, nothing changed: " .. tostring(now) } end
	if not force and SaveRescue.live(now, os.time()) then
		return { ok = false, err = ("the save was written %d s ago: the player looks online, and their next autosave would undo this. Wait until it is over %d s, or pass force = true"):format(os.time() - now.lastSeen, SaveRescue.LIVE_S) }
	end
	local backupKey = ("%s/%d"):format(key, os.time())
	local okB, errB = pcall(function() store(SaveRescue.BACKUP):SetAsync(backupKey, { at = os.time(), rec = now }) end)
	if not okB then return { ok = false, err = "backup failed, nothing changed: " .. tostring(errB) } end
	-- compare and swap: write only if the save is still the one just backed up (review I-4)
	local seen = type(now) == "table" and now.lastSeen or nil
	local changed = false
	old.lastSeen = os.time()
	local okW, errW = pcall(function()
		store(SaveRescue.STORE):UpdateAsync(key, function(cur)
			local curSeen = type(cur) == "table" and cur.lastSeen or nil
			if curSeen ~= seen then
				changed = true
				return nil   -- someone saved since: leave it
			end
			return old
		end)
	end)
	if not okW then return { ok = false, err = "write failed, nothing changed (backup at " .. backupKey .. "): " .. tostring(errW) } end
	if changed then return { ok = false, err = "the save changed while restoring (a live session?): nothing written. Try again once they are offline" } end
	return { ok = true, backup = backupKey, restored = SaveRescue.summary(old), was = SaveRescue.summary(now) }
end

return SaveRescue
