--[[ ErrorReportClient (26 Oct 2026, safety net part 1): sends this client's script errors to
	the server's error log (ErrorLog), so a bug players hit on live shows up in the morning
	report. The same error (numbers folded) is sent at most once every 30 s, and at most 10
	reports leave this client a minute (review I-3: an error every frame with changing text
	sent ~60 a second and grew the memo without end). Only the error text and its stack. ]]

local RS = game:GetService("ReplicatedStorage")
local ScriptContext = game:GetService("ScriptContext")

local remotes = RS:WaitForChild("SVRemotes", 60)
local report = remotes and remotes:WaitForChild("ReportError", 60)
local sentAt, kinds = {}, 0
local minuteAt, inMinute = 0, 0

ScriptContext.Error:Connect(function(message, stack)
	if not report then return end
	local now = os.clock()
	if now - minuteAt >= 60 then minuteAt, inMinute = now, 0 end
	if inMinute >= 10 then return end
	local k = (tostring(message):sub(1, 200) .. "|" .. (tostring(stack):match("^[^\n]*") or "")):gsub("%d+", "#")
	if sentAt[k] and now - sentAt[k] < 30 then return end
	if kinds >= 200 then sentAt, kinds = {}, 0 end   -- the memo stays small
	if not sentAt[k] then kinds += 1 end
	sentAt[k] = now
	inMinute += 1
	pcall(function() report:FireServer(tostring(message):sub(1, 300), tostring(stack):sub(1, 300)) end)
end)
