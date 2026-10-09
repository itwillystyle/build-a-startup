--[[ fuzz_watch_server.luau -- the server half of tools/fuzz_remotes.luau.

	Studio, in Play, SERVER datamodel, pasted BEFORE the client fuzz. It records every
	server error and warning (grouped by shape, with counts) into ServerStorage.FuzzLog
	and the worst Heartbeat into ServerStorage.FuzzWorstFrame. Read both after:
	    return { game.ServerStorage.FuzzLog.Value, game.ServerStorage.FuzzWorstFrame.Value }
	A pass is an empty log. Left out: the MCP bridge's own errors, and "invocation queue
	exhausted" (the fuzz firing server -> client remotes, which have no server handler).
	The DataStore lines are the ones that matter: "StandardWriteGameServerThrottled"
	means a remote is spending the write budget every player's save comes out of. ]]
local SS = game:GetService("ServerStorage")
local box = SS:FindFirstChild("FuzzLog") or Instance.new("StringValue")
box.Name = "FuzzLog"
box.Value = ""
box.Parent = SS
local worst = SS:FindFirstChild("FuzzWorstFrame") or Instance.new("NumberValue")
worst.Name = "FuzzWorstFrame"
worst.Value = 0
worst.Parent = SS
local seen = {}
game:GetService("LogService").MessageOut:Connect(function(msg, kind)
	if kind ~= Enum.MessageType.MessageError and kind ~= Enum.MessageType.MessageWarning then return end
	if msg:find("AssistantCommand", 1, true) or msg:find("invocation queue exhausted", 1, true) then return end
	local key = (kind == Enum.MessageType.MessageError and "E " or "W ") .. msg:gsub("%d+%.?%d*", "#"):sub(1, 160)
	seen[key] = (seen[key] or 0) + 1
	local parts = {}
	for k, n in pairs(seen) do table.insert(parts, ("%dx %s"):format(n, k)) end
	table.sort(parts)
	box.Value = table.concat(parts, "\n")
end)
game:GetService("RunService").Heartbeat:Connect(function(dt)
	if dt > worst.Value then worst.Value = dt end
end)
return "recording"
