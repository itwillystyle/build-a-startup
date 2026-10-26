--[[ ErrorLog (26 Oct 2026, safety net part 1): every live error, counted, where the morning
	report can read it. Before this, a crash on live servers was only seen if a player said so
	(the #64 economy-loop crash ran for days).

	Server errors come from ScriptContext.Error; client errors from ErrorReportClient through
	SVRemotes.ReportError (rate-limited per player, ErrorBook.allow). Once a minute, and when the
	server closes, the batch is merged into SVErrors_v1 "<live|studio>/<UTC day>" (ErrorBook).

	Read it (Edit datamodel, Studio command bar or MCP): the doctor routine does this every morning.
	  require(game.ServerScriptService.ErrorLog:Clone()).read(2)          -- live, today + yesterday
	  require(game.ServerScriptService.ErrorLog:Clone()).read(1, true)    -- this Studio's own runs ]]

local ErrorLog = {}

-- by service, not script.Parent: the Edit reader is a parentless :Clone() (docs/ROLLBACK.md step 2)
local Book = require(game:GetService("ServerScriptService"):WaitForChild("ErrorBook"))
local FLUSH = 60

function ErrorLog.init(a)
	local studio = game:GetService("RunService"):IsStudio()
	local store = game:GetService("DataStoreService"):GetDataStore(Book.STORE)
	local pending = Book.batch()
	local busy = false

	-- kept tiny and pcall'd: an error in here must never raise another error event
	game:GetService("ScriptContext").Error:Connect(function(message, stack)
		pcall(Book.note, pending, "server", message, stack, os.time())
	end)

	local buckets = {}
	a.remote("ReportError").OnServerEvent:Connect(function(player, message, stack)
		if type(message) ~= "string" or type(stack) ~= "string" then return end
		buckets[player] = buckets[player] or {}
		if not Book.allow(buckets[player], os.clock()) then return end
		pcall(Book.note, pending, "client", message:sub(1, 400), stack:sub(1, 400), os.time())
		if a.telemetry then pcall(a.telemetry, player, "script_error") end
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(p) buckets[p] = nil end)

	local function flush()
		if busy or pending.count == 0 then return end
		busy = true
		local batch = pending
		pending = Book.batch()
		local now = os.time()
		local ok, err = pcall(function()
			store:UpdateAsync(Book.key(now, studio), function(old) return Book.merge(old, batch, game.PlaceVersion, now) end)
		end)
		if not ok then
			Book.absorb(pending, batch)   -- keep them for the next minute rather than lose them
			warn("[SV] error log write failed, retrying next minute: " .. tostring(err))
		end
		busy = false
	end
	task.spawn(function()
		while true do
			task.wait(FLUSH)
			flush()
		end
	end)
	game:BindToClose(flush)
	ErrorLog.flush = flush   -- Studio proof: flush now instead of waiting a minute
end

-- Edit / Studio: the last `days` UTC days, newest first, each { key, total, dropped, kinds = ErrorBook.summary }
function ErrorLog.read(days, studio)
	local store = game:GetService("DataStoreService"):GetDataStore(Book.STORE)
	local out = {}
	for d = 0, math.clamp(days or 2, 1, 14) - 1 do
		local key = Book.key(os.time() - d * 86400, studio == true)
		local ok, rec = pcall(function() return store:GetAsync(key) end)
		if not ok then
			table.insert(out, { key = key, err = tostring(rec) })
		else
			table.insert(out, { key = key, total = rec and rec.total or 0, dropped = rec and rec.dropped or 0, kinds = Book.summary(rec) })
		end
	end
	return out
end

return ErrorLog
