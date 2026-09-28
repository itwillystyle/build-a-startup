--[[
	BuildClient -- LocalScript in StarterPlayer -> StarterPlayerScripts.

	The building picker. Opens when you tap BUILD on an empty lot.

	Why a picker and not drag-to-place: choosing WHAT goes WHERE is the whole
	expression, and it costs a fraction of free-form placement (no grid maths,
	no collision, no undo, no save format, no drag on a phone).

	v3.1 (25 Sep reviews):
	  - a light menu that rises from the bottom, so your money stays readable
	    while you choose (the old centred box covered the cash and the income)
	  - one icon per building that means something: office = code, server
	    room = gear, studio = design, cafe = people (the old set used a
	    fast-forward arrow for servers and a house for the cafe)
	  - the price is a button: green BUY when you can afford it, grey with
	    "need $X more" when you cannot, instead of a silent red flash
	  - one money format (UIKit.money), 15 px minimum text
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("SVRemotes")
local openBuild = remotes:WaitForChild("OpenBuild")
local placeRoom = remotes:WaitForChild("PlaceRoom")
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local ROW_H = 58
local ROW_GAP = 6
local ROOM_ICON = { office = "code", servers = "gear", studio = "contrast", cafe = "team" }

-- ============ UI ============

local gui = Instance.new("ScreenGui")
gui.Name = "BuildPicker"
gui.ResetOnSpawn = false
gui.DisplayOrder = 11
gui.IgnoreGuiInset = true
gui.Enabled = false
UIKit.safe(gui)
gui.Parent = player:WaitForChild("PlayerGui")

local panel, body, closeBtn = UIKit.menu(gui, "BUILD ON THIS LOT", UIKit.BLUE, {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(0.92, 0, 0, 300),
})
local cap = Instance.new("UISizeConstraint", panel)
cap.MaxSize = Vector2.new(460, 520)
-- phones in landscape are ~390 px tall: shrink to keep the money line (top 84 px) visible
local fit = Instance.new("UIScale", panel)
local function refit()
	local vp = workspace.CurrentCamera.ViewportSize
	fit.Scale = math.min(1, (vp.Y - 96) / math.max(1, panel.Size.Y.Offset), (vp.X - 24) / 460)
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)
local list = Instance.new("Frame")
list.Name = "List"
list.BackgroundTransparency = 1
list.Size = UDim2.new(1, 0, 1, 0)
list.Parent = body
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, ROW_GAP)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

-- ============ STATE ============

local currentSlot = nil
local rows = {}

local function cash()
	local ls = player:FindFirstChild("leaderstats")
	local c = ls and ls:FindFirstChild("Cash")
	return c and c.Value or 0
end

local function close()
	gui.Enabled = false
	currentSlot = nil
end
if closeBtn then closeBtn.MouseButton1Click:Connect(close) end

-- ============ ROWS ============

local function makeRow(room, i)
	local row = Instance.new("Frame")
	row.Name = "Room_" .. room.id
	row.LayoutOrder = i
	row.Size = UDim2.new(1, 0, 0, ROW_H)
	row.BackgroundColor3 = UIKit.CARD
	row.Parent = list
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 12)
	local st = Instance.new("UIStroke", row)
	st.Color = UIKit.CARD_LINE
	st.Thickness = 1.5

	-- the tile is the colour of the building's sign
	local tile = Instance.new("Frame")
	tile.Name = "IconTile"
	tile.Size = UDim2.new(0, ROW_H - 16, 0, ROW_H - 16)
	tile.Position = UDim2.new(0, 8, 0.5, -(ROW_H - 16) / 2)
	tile.BackgroundColor3 = room.accent
	tile.BorderSizePixel = 0
	tile.Parent = row
	Instance.new("UICorner", tile).CornerRadius = UDim.new(0, 10)
	UIKit.icon(tile, ROOM_ICON[room.id] or "plus", ROW_H - 30, UIKit.INK, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0) })

	local nm = UIKit.label(row, room.name, 18, UIKit.CARD_TEXT, {
		Name = "RoomName", Position = UDim2.new(0, ROW_H + 2, 0, 7), Size = UDim2.new(1, -(ROW_H + 132), 0, 22),
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, UIKit.HEAD)
	local blurb = UIKit.label(row, room.blurb or "", 15, UIKit.CARD_MUTED, {
		Name = "RoomBlurb", Position = UDim2.new(0, ROW_H + 2, 0, 30), Size = UDim2.new(1, -(ROW_H + 132), 0, 20),
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, UIKit.HEAD)

	local buy, buyLabel = UIKit.button(row, "", UIKit.GREEN, {
		Name = "Buy", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0, 116, 0, 44),
	}, { textSize = 18 })
	local need = UIKit.label(row, "", 14, UIKit.RED, {
		Name = "Need", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -8, 1, -2), Size = UDim2.new(0, 116, 0, 15),
		TextXAlignment = Enum.TextXAlignment.Center, Visible = false,
	}, UIKit.HEAD)

	-- read the CURRENT price at click time (v2.7.1: a stale closure once refused a $100 office)
	local entry = { row = row, buy = buy, buyLabel = buyLabel, need = need, blurb = blurb, room = room }
	buy.MouseButton1Click:Connect(function()
		if not currentSlot then return end
		local r = entry.room
		if cash() < r.cost then
			UIKit.sfx("thunk", 0.7)
			local sc = need:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", need)
			sc.Scale = 1.25
			TweenService:Create(sc, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { Scale = 1 }):Play()
			return
		end
		placeRoom:FireServer(currentSlot, r.id)
		close()
	end)
	return entry
end

local function refresh()
	for _, r in ipairs(rows) do
		local have = cash()
		local afford = have >= r.room.cost
		r.buyLabel.Text = afford and ("BUY  " .. UIKit.money(r.room.cost)) or UIKit.money(r.room.cost)
		UIKit.setButtonColor(r.buy, afford and UIKit.GREEN or UIKit.MUTED)
		r.need.Visible = not afford
		r.need.Text = ("need %s more"):format(UIKit.money(r.room.cost - have))
		r.buy.Position = afford and UDim2.new(1, -8, 0.5, 0) or UDim2.new(1, -8, 0.5, -8)
		r.buy.Size = afford and UDim2.new(0, 116, 0, 44) or UDim2.new(0, 116, 0, 34)
	end
end

-- ============ OPEN ============

openBuild.OnClientEvent:Connect(function(slotIndex, roomDefs)
	currentSlot = slotIndex
	if #rows == 0 then
		for i, room in ipairs(roomDefs) do rows[i] = makeRow(room, i) end
		-- height derives from the row count so a new building type can never fall off the panel
		panel.Size = UDim2.new(0.92, 0, 0, 48 + 24 + #roomDefs * (ROW_H + ROW_GAP) - ROW_GAP)
		refit()
	end
	-- the server re-prices every open (more buildings, HQ level): take its numbers
	for i, room in ipairs(roomDefs) do
		local r = rows[i]
		if r then r.room = room; r.blurb.Text = room.blurb or "" end
	end
	refresh()
	gui.Enabled = true
	panel.Position = UDim2.new(0.5, 0, 1, 80)
	TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { Position = UDim2.new(0.5, 0, 1, -12) }):Play()
end)

-- prices react to money while the picker is open
task.spawn(function()
	while true do
		task.wait(0.4)
		if gui.Enabled then refresh() end
	end
end)

-- Escape is bound to CoreGui and cannot be used. Q closes.
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not gui.Enabled then return end
	if input.KeyCode == Enum.KeyCode.Q then close() end
end)
