--[[ ErrorReportClient (26 Oct 2026, safety net part 1): sends this client's script errors to
	the server's error log (ErrorLog), so a bug players hit on live shows up in the morning
	report. The same error is sent at most once every 30 s; the server also limits each player
	to 10 reports a minute. Only the error text and its stack, nothing a player typed. ]]

local RS = game:GetService("ReplicatedStorage")
local ScriptContext = game:GetService("ScriptContext")

local remotes = RS:WaitForChild("SVRemotes", 60)
local report = remotes and remotes:WaitForChild("ReportError", 60)
local sentAt = {}

ScriptContext.Error:Connect(function(message, stack)
	if not report then return end
	local k = tostring(message) .. "|" .. (tostring(stack):match("^[^\n]*") or "")
	local now = os.clock()
	if sentAt[k] and now - sentAt[k] < 30 then return end
	sentAt[k] = now
	pcall(function() report:FireServer(tostring(message):sub(1, 400), tostring(stack):sub(1, 400)) end)
end)
