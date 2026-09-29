--[[
	RanksClient -- LocalScript, StarterPlayerScripts.

	v4.2 RANKS. His ask (28 Sep): "a global leaderboard that shows the net worth
	of every person's company that started, to create a competitive aspect".

	A RANKS button on the left rail opens two boards:
	  THIS WEEK  value gained since Monday 00:00 UTC; it resets, so a new
	             player can reach the top 10 in their first week
	  ALL TIME   lifetime company value (never drops when you spend or spin off)
	Your own row is pinned at the bottom with what it takes to pass the next
	company: that line is the competitive pull. AI rival companies carry an AI
	tag: a global board does not pass bots off as players.

	Data: ServerScriptService.Ranks answers SVRemotes.GetRanks from a cache (no
	DataStore call per tap). Fetched on open and every 20 s while open.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local remotes = ReplicatedStorage:WaitForChild("SVRemotes")
local getRanks = remotes:WaitForChild("GetRanks", 60)
if not getRanks then return end

-- ============ THE BUTTON ============
-- v5: a small round button in the top-right corner, beside music. The rail
-- holds the five things you use every few minutes; a leaderboard is a glance
-- now and then, and a sixth rail tile shrank every tile below readable on a phone.
local corner = Instance.new("ScreenGui")
corner.Name = "RanksCorner"
corner.ResetOnSpawn = false
corner.IgnoreGuiInset = true
corner.DisplayOrder = 7
UIKit.safe(corner)
corner.Parent = player:WaitForChild("PlayerGui")
local btn = UIKit.iconButton(corner, "trophy", nil, UIKit.CARD, {
	Name = "RanksButton", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -64, 0, 10), Size = UDim2.new(0, 44, 0, 44), Visible = false,
}, { iconSize = 22, dark = true, radius = 22 })
btn:SetAttribute("Accent", UIKit.GOLD)

-- ============ THE PANEL ============
local gui = Instance.new("ScreenGui")
gui.Name = "Ranks"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 12
gui.Enabled = false
UIKit.safe(gui)
gui.Parent = player:WaitForChild("PlayerGui")

-- v5: sized to a 360 px phone at full scale (it was 394 px and shrank everywhere):
-- five rows show, the rest scroll; 44 px tabs
local W, HEAD_H, TAB_H, ROW_H, MINE_H = 440, 44, 44, 34, 54
local ROWS_H = 5 * ROW_H
local H = HEAD_H + 12 + TAB_H + 8 + ROWS_H + 8 + MINE_H + 14
local panel, body, close = UIKit.menu(gui, "RANKS", UIKit.GOLD, {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, W, 0, H),
}, { headerHeight = HEAD_H })
local fit = Instance.new("UIScale", panel)            -- a phone held sideways is ~390 px tall
UIKit.fitMenu(panel, W, H, fit)   -- v5: the shared rule (clears the rail, scales to fit)

local status = UIKit.label(panel:FindFirstChild("Header"), "", 14, UIKit.TEXT, {
	Name = "Status", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -58, 0.5, 0), Size = UDim2.new(0, 190, 0, 20),
	TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3,
}, UIKit.HEAD)
status.TextColor3 = UIKit.INK_SOFT      -- v5: ink on gold (white on gold was 1.5:1)

-- tabs
local current = "week"
local tabs = {}
local render     -- forward: draws the current board (defined below)
local function tab(key, text, x)
	local b = UIKit.button(body, text, UIKit.MUTED, {
		Name = "Tab_" .. key, Position = UDim2.new(x, x > 0 and 4 or 0, 0, 0), Size = UDim2.new(0.5, -4, 0, TAB_H),
	}, { textSize = 18 })
	tabs[key] = b
	b.MouseButton1Click:Connect(function()
		current = key
		render()
	end)
end
tab("week", "THIS WEEK", 0)
tab("all", "ALL TIME", 0.5)

local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.Position = UDim2.new(0, 0, 0, TAB_H + 8)
list.Size = UDim2.new(1, 0, 0, ROWS_H)
list.ScrollBarThickness = 5
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new(0, 0, 0, 0)
list.Parent = body
local ll = Instance.new("UIListLayout", list)
ll.Padding = UDim.new(0, 2)
ll.SortOrder = Enum.SortOrder.LayoutOrder

-- the pinned YOU card
local mine = Instance.new("Frame")
mine.Name = "Mine"
mine.Position = UDim2.new(0, 0, 0, TAB_H + 8 + ROWS_H + 8)
mine.Size = UDim2.new(1, 0, 0, MINE_H)
mine.BackgroundColor3 = UIKit.GOLD
mine.BorderSizePixel = 0
mine.Parent = body
Instance.new("UICorner", mine).CornerRadius = UDim.new(0, 12)
local mineStroke = Instance.new("UIStroke", mine)
mineStroke.Color = UIKit.GOLD_DEEP
mineStroke.Thickness = 2
local mineTop = UIKit.label(mine, "", 18, UIKit.CARD_TEXT, {
	Name = "Top", Position = UDim2.new(0, 14, 0, 6), Size = UDim2.new(1, -28, 0, 24), TextTruncate = Enum.TextTruncate.AtEnd,
}, UIKit.HEAD)
local mineSub = UIKit.label(mine, "", 16, UIKit.INK_SOFT, {
	Name = "Sub", Position = UDim2.new(0, 14, 0, 28), Size = UDim2.new(1, -28, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd,
}, UIKit.BODY)

-- ============ DRAW ============
local data
local RANK_COLOR = { UIKit.GOLD_DEEP, Color3.fromRGB(96, 104, 120), Color3.fromRGB(158, 92, 40) }   -- v5: readable on paper

local function row(i, r, me)
	local f = Instance.new("Frame")
	f.Name = "Row" .. i
	f.LayoutOrder = i
	f.Size = UDim2.new(1, -8, 0, ROW_H - 2)
	f.BackgroundColor3 = (r.key == me) and UIKit.GOLD or (i % 2 == 0 and UIKit.SURFACE_2 or UIKit.CARD)
	f.BorderSizePixel = 0
	f.Parent = list
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 8)
	-- your own row is gold, so its rank is dark (a gold #1 on gold vanished)
	UIKit.label(f, "#" .. tostring(r.rank or i), 16, (r.key == me) and UIKit.CARD_TEXT or (RANK_COLOR[r.rank or i] or UIKit.CARD_MUTED), {
		Position = UDim2.new(0, 8, 0, 0), Size = UDim2.new(0, 44, 1, 0),
	}, UIKit.HEAD)
	local nameW = r.ai and -(54 + 116 + 40) or -(54 + 116)
	UIKit.label(f, tostring(r.name or "?"), 16, UIKit.CARD_TEXT, {
		Position = UDim2.new(0, 54, 0, 0), Size = UDim2.new(1, nameW, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd,
	}, UIKit.HEAD)
	if r.ai then
		local tag = Instance.new("Frame")
		tag.AnchorPoint = Vector2.new(1, 0.5)
		tag.Position = UDim2.new(1, -124, 0.5, 0)
		tag.Size = UDim2.new(0, 34, 0, 20)
		tag.BackgroundColor3 = UIKit.CARD_MUTED
		tag.BorderSizePixel = 0
		tag.Parent = f
		Instance.new("UICorner", tag).CornerRadius = UDim.new(1, 0)
		UIKit.label(tag, "AI", 14, UIKit.TEXT, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center }, UIKit.HEAD)
	end
	UIKit.label(f, UIKit.money(r.value or 0), 16, (r.key == me) and UIKit.INK or UIKit.GREEN_DEEP, {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0), Size = UDim2.new(0, 110, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
	}, UIKit.HEAD)
end

local function ago(sec)
	sec = math.max(0, math.floor(sec or 0))
	if sec < 90 then return "just now" end
	return ("%d min ago"):format(math.floor(sec / 60 + 0.5))
end

render = function()
	for key, b in pairs(tabs) do
		UIKit.setButtonColor(b, key == current and UIKit.GOLD or UIKit.MUTED)
	end
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	if not data then
		mineTop.Text = "Loading..."
		mineSub.Text = ""
		return
	end
	local me = tostring(player.UserId)
	local rows = data[current] or {}
	for i, r in ipairs(rows) do row(i, r, me) end
	if #rows == 0 then
		UIKit.label(list, "No companies yet. Yours could be first.", 16, UIKit.CARD_MUTED, {
			Size = UDim2.new(1, -8, 0, ROW_H), TextXAlignment = Enum.TextXAlignment.Center,
		}, UIKit.HEAD)
	end
	-- the pinned YOU card
	local m = data.mine and data.mine[current] or {}
	local label = current == "week" and "this week" or "all time"
	if m.unranked then
		mineTop.Text = ("YOU  ·  %s %s"):format(UIKit.money(m.value or 0), label)
		mineSub.Text = ("Earn %s more to join the board"):format(UIKit.money(m.need or 0))
	elseif m.rank then
		mineTop.Text = ("YOU  ·  #%d %s  ·  %s"):format(m.rank, label, UIKit.money(m.value or 0))
		mineSub.Text = m.gapName and ("%s more to pass %s"):format(UIKit.money(m.gapNeed or 0), m.gapName)
			or "You're #1. Stay there."
	else
		mineTop.Text = ("YOU  ·  %s %s"):format(UIKit.money(m.value or 0), label)
		mineSub.Text = ("Top 25 needs %s more"):format(UIKit.money(m.needTop or 0))
	end
	-- header: when the weekly board resets, or how fresh the all-time board is
	local now = data.now or os.time()
	if data.stale then
		status.Text = "offline  ·  " .. ago(now - (data.updated or now))
	elseif current == "week" and data.weekEnds then
		local left = math.max(0, data.weekEnds - now)
		status.Text = ("resets in %dd %dh"):format(left // 86400, (left % 86400) // 3600)
	else
		status.Text = "updated " .. ago(now - (data.updated or now))
	end
end

local fetching = false
local function fetch()
	if fetching then return end
	fetching = true
	local ok, res = pcall(function() return getRanks:InvokeServer() end)
	fetching = false
	if ok and type(res) == "table" then
		data = res
		if gui.Enabled then render() end
	end
end

-- ============ OPEN / CLOSE ============
local function setOpen(v)
	if v then UIKit.solo(gui) end
	gui.Enabled = v
	if v then
		render()
		task.spawn(fetch)
	end
end
btn.MouseButton1Click:Connect(function() setOpen(not gui.Enabled) end)
if close then close.MouseButton1Click:Connect(function() setOpen(false) end) end
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Q and gui.Enabled then setOpen(false) end
end)
task.spawn(function()
	while true do
		task.wait(20)
		if gui.Enabled then fetch() end
	end
end)

-- v5: the board arrives with HQ 2 (at 0:30 it was a leaderboard where a new player is last)
local function sync() btn.Visible = (player:GetAttribute("HQLevel") or 1) >= 2 end
sync()
player:GetAttributeChangedSignal("HQLevel"):Connect(sync)

-- v5: the rail tile shows when this menu is open
UIKit.bindRail(btn, gui)
