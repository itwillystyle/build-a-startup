--[[ Feedback (the player loop, 9 Oct 2026): the in-game TELL US box.

	A player types up to 300 characters. It goes into the SVFeedback_v1 DataStore
	with what was true when they sent it (HQ level, staff, wafer level, platform,
	the place version), keyed "<unix time>_<userId>" so the keys sort by time.

	No other player ever sees this text, so it is stored as typed: Roblox filters
	text shown to OTHER players, and this is shown to none. One message a minute
	and five a session, because each one is a DataStore write out of the server's
	shared budget, the one every player's save comes from (the 9 Oct exploit
	check drained it with renames).

	Read it in Studio: SVDev action `feedback` (newest first, Studio entries marked).
	`clean` is pure (tests/offline/feedback.spec.luau); every service lookup waits
	for init, so Lune can load this file. ]]
local Feedback = {}

Feedback.MAX_LEN = 300       -- characters, not bytes
Feedback.MIN_LEN = 3
Feedback.GAP = 60            -- seconds between two messages from one player
Feedback.PER_SESSION = 5
Feedback.STORE = "SVFeedback_v1"

-- -> the text to store, or nil, why
function Feedback.clean(raw)
	if type(raw) ~= "string" then return nil, "type" end
	if not utf8.len(raw) then return nil, "utf8" end
	local t = raw:gsub("%c", " ")
	t = t:gsub("^%s+", "")
	t = t:gsub("%s+$", "")
	if utf8.len(t) < Feedback.MIN_LEN then return nil, "short" end
	local cut = utf8.offset(t, Feedback.MAX_LEN + 1)   -- never splits a character
	if cut then t = t:sub(1, cut - 1) end
	return t
end

function Feedback.key(unix, userId)
	return ("%010d_%d"):format(unix, userId)
end

local store, studio, api
local sent = {}   -- userId -> { n, nextAt }

local function receive(player, raw)
	local s = api.session(player)
	if not s then return end
	local mine = sent[player.UserId] or { n = 0, nextAt = 0 }
	sent[player.UserId] = mine
	local reply = api.reply
	if mine.n >= Feedback.PER_SESSION then reply:FireClient(player, false, "That's plenty for one visit. Thank you!") return end
	if os.clock() < mine.nextAt then reply:FireClient(player, false, "One message a minute, please.") return end
	local text = Feedback.clean(raw)
	if not text then reply:FireClient(player, false, "Write a few words first.") return end
	mine.n += 1
	mine.nextAt = os.clock() + Feedback.GAP
	local plot = api.plotOf(player)
	local entry = {
		u = player.UserId, t = os.time(), text = text,
		hq = plot and plot.hq and plot.hq.level or 0,
		wl = plot and plot.wafer and plot.wafer.level or 0,
		staff = s.staff or 0, spins = s.spinoffs or 0,
		touch = player:GetAttribute("Touch") == true,
		place = game.PlaceVersion,
		studio = studio or nil,
	}
	local ok = pcall(function() store:SetAsync(Feedback.key(entry.t, player.UserId), entry) end)
	api.telemetry.event(player, "feedback", utf8.len(text), { { "saved", ok } })
	reply:FireClient(player, ok, ok and "Got it. Thank you! We read every one." or "Couldn't send that one. Try again in a minute.")
end

function Feedback.init(a)
	api = a
	studio = game:GetService("RunService"):IsStudio()
	store = game:GetService("DataStoreService"):GetDataStore(Feedback.STORE)
	api.telemetry = require(script.Parent:WaitForChild("Telemetry"))
	api.reply = a.remote("FeedbackReply")          -- server -> client: (ok, line to show)
	a.remote("SendFeedback").OnServerEvent:Connect(receive)
	game:GetService("Players").PlayerRemoving:Connect(function(p) sent[p.UserId] = nil end)
end

-- Studio (SVDev `feedback`): the newest n entries, newest first
function Feedback.latest(n)
	n = math.clamp(tonumber(n) or 10, 1, 100)
	local s = store or game:GetService("DataStoreService"):GetDataStore(Feedback.STORE)
	local keys = {}
	local ok, pages = pcall(function() return s:ListKeysAsync() end)
	if not ok then return { error = tostring(pages) } end
	while true do
		for _, k in ipairs(pages:GetCurrentPage()) do table.insert(keys, k.KeyName) end
		if pages.IsFinished then break end
		pages:AdvanceToNextPageAsync()
	end
	table.sort(keys)
	local out = {}
	for i = #keys, math.max(1, #keys - n + 1), -1 do
		local okG, v = pcall(function() return s:GetAsync(keys[i]) end)
		table.insert(out, okG and v or { key = keys[i], error = "read failed" })
	end
	return { total = #keys, newest = out }
end

return Feedback
