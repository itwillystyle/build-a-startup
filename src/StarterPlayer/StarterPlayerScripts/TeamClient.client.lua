--[[
	TeamClient -- LocalScript in StarterPlayer -> StarterPlayerScripts.

	MANAGE STAFF phase 3 (14 Oct 2026): the TEAM screen. Spec:
	docs/superpowers/specs/2026-10-13-manage-staff-design.md §2.

	A TEAM tile in the MORE tray opens a list of everyone (sorted by $/s, or by
	talent) and a card for the person you tap: Skill, Speed and Loyalty as
	"level / max" bars with TRAIN beside each, and MOVE TO chips for every room
	the HQ has. Tapping the room someone is pinned to unpins them.

	This script only draws and asks. The server sends StaffData (each person,
	with every stat's level, cap and price) and StaffRooms (each room's free
	seats), owns every rule (StaffAction) and re-checks every request. What each
	button shows is decided by TeamView (pure, tests/offline/teamview.spec).

	Landscape first, like the Index: a phone held sideways is 360-390 px tall, so
	the card sits beside the list instead of a bottom sheet over it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local Moment = require(ReplicatedStorage:WaitForChild("Moment"))
local V = require(ReplicatedStorage:WaitForChild("TeamView"))
local remote = ReplicatedStorage:WaitForChild("SVRemotes"):WaitForChild("StaffAction", 30)

local ROLE = { engineer = "Engineer", designer = "Designer", sales = "Sales", recruiter = "Recruiter", research = "Researcher" }
local STATS = {   -- StaffStats.STATS, in its order; the blurb is the card's short form of it
	{ id = "skill", label = "Skill", blurb = "more money" },
	{ id = "speed", label = "Speed", blurb = "ships apps faster" },
	{ id = "loyalty", label = "Loyalty", blurb = "keeps training in a spin-off" },
}

-- ============ THE TILE (MORE tray, plot only) ============

local btn = UIKit.railButton("team", "TEAM", UIKit.BLUE, {
	Name = "TeamButton", LayoutOrder = 3, Size = UDim2.new(0, UIKit.RAIL, 0, UIKit.RAIL), Visible = false,
}, { iconSize = 28, tray = true, plotOnly = true })

-- ============ THE PANEL ============

local gui = Instance.new("ScreenGui")
gui.Name = "Team"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 12
gui.Enabled = false
UIKit.safe(gui)
gui.Parent = player:WaitForChild("PlayerGui")

--[[ Every tap is 52 px drawn, so it is still 44 after fitMenu shrinks the menu to a
	360-tall phone (scale 0.86; the doctor measured 44 px buttons at 41 at 0.94). The
	panel is 400 tall on a short screen (the scale floor that keeps 14 px text at 12)
	and 450 on a tall one; the card scrolls when it does not fit. ]]
local HEAD_H, W = 48, 680
local function heightFor() return workspace.CurrentCamera.ViewportSize.Y >= 560 and 450 or 400 end
local H = heightFor()
local LIST_W, GAP = 280, 12
local CARD_W = W - 22 - LIST_W - GAP
local ROW_H, TAP, BLOCK_H = 56, 52, 58
local TRAIN_W = 128

local panel, body, close = UIKit.menu(gui, "TEAM", UIKit.BLUE, {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0, W, 0, H),
}, { headerHeight = HEAD_H })
body.Position = UDim2.new(0, 11, 0, HEAD_H + 10)
body.Size = UDim2.new(1, -22, 1, -(HEAD_H + 20))
local fit = Instance.new("UIScale", panel)
local refit = UIKit.fitMenu(panel, W, nil, fit, 16)   -- nil: it reads the panel's height, which follows the screen
local function resize()
	if heightFor() ~= panel.Size.Y.Offset then
		panel.Size = UDim2.new(0, W, 0, heightFor())
		refit(0.5, 0)
	end
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)

local count = UIKit.label(panel:FindFirstChild("Header"), "", UIKit.TYPE.title, UIKit.TEXT, {
	Name = "Count", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -62, 0.5, -1), Size = UDim2.new(0, 120, 0, 28),
	TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3,
}, UIKit.HEAD)
UIKit.paintLabel(count, UIKit.BLUE)

-- ---- the list (left) ----
local sortBy = "rate"
local sortBtn = UIKit.button(body, "SORT: $/s", UIKit.BLUE_LIGHT, {
	Name = "Sort", Size = UDim2.new(0, LIST_W, 0, TAP),
}, { textSize = UIKit.TYPE.body, textColor = UIKit.BLUE_DEEP, stroke = UIKit.BLUE })

local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.Position = UDim2.new(0, 0, 0, TAP + 6)
list.Size = UDim2.new(0, LIST_W, 1, -(TAP + 6))
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.ScrollBarImageColor3 = UIKit.LINE_LIGHT
list.CanvasSize = UDim2.new(0, 0, 0, 0)
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ScrollingDirection = Enum.ScrollingDirection.Y
list.Parent = body
local lay = Instance.new("UIListLayout", list)
lay.Padding = UDim.new(0, 6)
lay.SortOrder = Enum.SortOrder.LayoutOrder

-- ---- the card (right) ----
local CONTENT_H = 66 + 3 * BLOCK_H + 18 + 2 * TAP + 6   -- name lines, the stats, MOVE TO, two rows of chips
local card = Instance.new("ScrollingFrame")   -- on a short screen the second row of chips is a scroll away
card.Name = "Card"
card.Position = UDim2.new(0, LIST_W + GAP, 0, 0)
card.Size = UDim2.new(0, CARD_W, 1, 0)
card.BackgroundColor3 = UIKit.CARD
card.BorderSizePixel = 0
card.ScrollBarThickness = 6
card.ScrollBarImageColor3 = UIKit.LINE_LIGHT
card.ScrollingDirection = Enum.ScrollingDirection.Y
card.CanvasSize = UDim2.new(0, 0, 0, CONTENT_H + 20)
card.Parent = body
Instance.new("UICorner", card).CornerRadius = UDim.new(0, UIKit.RADIUS.md)
local cst = Instance.new("UIStroke", card)
cst.Color = UIKit.CARD_LINE
cst.Thickness = 2
local cpad = Instance.new("UIPadding", card)
cpad.PaddingLeft, cpad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
cpad.PaddingTop, cpad.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10)

local empty = UIKit.label(card, "Tap someone to see their card.", UIKit.TYPE.body, UIKit.MUTED_TEXT, {
	Name = "Empty", Size = UDim2.new(1, 0, 0, 120), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true,
}, UIKit.BODY)

local face = Instance.new("Frame")   -- everything shown once someone is picked
face.Name = "Face"
face.BackgroundTransparency = 1
face.Size = UDim2.new(1, 0, 0, CONTENT_H)
face.Visible = false
face.Parent = card

local nameL = UIKit.label(face, "", UIKit.TYPE.title, UIKit.INK, {
	Name = "Name", Size = UDim2.new(1, -110, 0, 26), TextTruncate = Enum.TextTruncate.AtEnd,
}, UIKit.HEAD)
local rateL = UIKit.outlined(face, "", UIKit.TYPE.title, UIKit.MONEY, {
	Name = "Rate", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 108, 0, 26),
})
rateL.TextXAlignment = Enum.TextXAlignment.Right
local subL = UIKit.label(face, "", UIKit.TYPE.caption, UIKit.MUTED_TEXT, {
	Name = "Sub", Position = UDim2.new(0, 0, 0, 26), Size = UDim2.new(1, 0, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd,
}, UIKit.BODY)
local noteL = UIKit.label(face, "", UIKit.TYPE.caption, UIKit.ORANGE_DEEP, {
	Name = "Note", Position = UDim2.new(0, 0, 0, 44), Size = UDim2.new(1, 0, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd,
}, UIKit.HEAD)

local blocks = {}
for i, st in ipairs(STATS) do
	local y = 66 + (i - 1) * BLOCK_H
	local b = {}
	b.label = UIKit.label(face, st.label, UIKit.TYPE.body, UIKit.INK, {
		Name = st.label, Position = UDim2.new(0, 0, 0, y), Size = UDim2.new(0, 80, 0, 18),
	}, UIKit.HEAD)
	b.level = UIKit.label(face, "", UIKit.TYPE.caption, UIKit.INK_SOFT, {
		Name = st.label .. "Level", Position = UDim2.new(0, 80, 0, y), Size = UDim2.new(1, -(80 + TRAIN_W + 8), 0, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
	}, UIKit.HEAD)
	UIKit.label(face, st.blurb, UIKit.TYPE.caption, UIKit.MUTED_TEXT, {
		Position = UDim2.new(0, 0, 0, y + 17), Size = UDim2.new(1, -(TRAIN_W + 8), 0, 18), TextTruncate = Enum.TextTruncate.AtEnd,
	}, UIKit.BODY)
	local track = Instance.new("Frame")
	track.Name = st.label .. "Bar"
	track.Position = UDim2.new(0, 0, 0, y + 40)
	track.Size = UDim2.new(1, -(TRAIN_W + 8), 0, 8)
	track.BackgroundColor3 = UIKit.SURFACE_2
	track.BorderSizePixel = 0
	track.Parent = face
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
	b.fill = Instance.new("Frame")
	b.fill.Size = UDim2.new(0, 0, 1, 0)
	b.fill.BackgroundColor3 = UIKit.BLUE
	b.fill.BorderSizePixel = 0
	b.fill.Parent = track
	Instance.new("UICorner", b.fill).CornerRadius = UDim.new(1, 0)
	b.button = UIKit.button(face, "", UIKit.GREEN, {
		Name = "Train_" .. st.id, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, y + 1),
		Size = UDim2.new(0, TRAIN_W, 0, TAP),
	}, { textSize = UIKit.TYPE.body })
	b.stat = st
	blocks[i] = b
end

local moveY = 66 + #STATS * BLOCK_H
UIKit.label(face, "MOVE TO", UIKit.TYPE.caption, UIKit.MUTED_TEXT, {
	Name = "MoveTo", Position = UDim2.new(0, 0, 0, moveY), Size = UDim2.new(1, 0, 0, 16),
}, UIKit.HEAD)
local chipBox = Instance.new("Frame")
chipBox.Name = "Chips"
chipBox.BackgroundTransparency = 1
chipBox.Position = UDim2.new(0, 0, 0, moveY + 18)
chipBox.Size = UDim2.new(1, 0, 0, 2 * TAP + 6)
chipBox.Parent = face
local grid = Instance.new("UIGridLayout", chipBox)
grid.CellPadding = UDim2.new(0, 6, 0, 6)
grid.CellSize = UDim2.new(1 / 3, -4, 0, TAP)
grid.SortOrder = Enum.SortOrder.LayoutOrder

-- ============ STATE ============

local rows, rooms = {}, {}
local selectedId
local pending = false
local lastTrain   -- { id, rate } of the last TRAIN sent, for the count-up when it lands
local ringAt      -- the TRAIN button pressed, for the ring when the server says yes
local reply       -- { text, colour, at } shown in the note line for a few seconds

local function decode(attr)
	local raw = player:GetAttribute(attr)
	if type(raw) ~= "string" then return {} end
	local ok, v = pcall(HttpService.JSONDecode, HttpService, raw)
	return (ok and type(v) == "table") and v or {}
end

local function cash()
	local ls = player:FindFirstChild("leaderstats")
	local c = ls and ls:FindFirstChild("Cash")
	return c and c.Value or nil
end

local function perSec(n) return UIKit.money(n) .. "/s" end

-- the card's $/s counting up after a TRAIN lands (the small reward beat). Its own loop,
-- not Moment.countUp, so tapping someone else stops it (review: it kept writing the
-- last person's $/s under the new name)
local countSerial = 0
local function countRate(from, to)
	countSerial += 1
	local mine, t0 = countSerial, os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if countSerial ~= mine or not rateL.Parent then conn:Disconnect() return end
		local k = math.clamp((os.clock() - t0) / 0.7, 0, 1)
		rateL.Text = perSec(from + (to - from) * (1 - (1 - k) ^ 5))
		if k >= 1 then conn:Disconnect() end
	end)
end
local refreshCard   -- assigned below (the card); say() and a row tap call it
local refreshList   -- assigned below (the list); a row tap calls it

local function say(text, colour)
	reply = { text = text, colour = colour, at = os.clock() }
	noteL.Text = text
	noteL.TextColor3 = colour
	local mine = reply
	task.delay(4, function()
		if reply == mine then
			reply = nil
			if gui.Enabled and refreshCard then refreshCard() end
		end
	end)
end

local function send(kind, id, arg)
	if pending or not remote then return false end
	pending = true
	remote:FireServer(kind, id, arg)
	-- the rate limit drops a request without a reply: never leave the buttons stuck
	task.delay(1.5, function() pending = false end)
	return true
end

-- ---- list rows (a pool, reused as StaffData changes) ----
local pool = {}

local function rowFrame(i)
	if pool[i] then return pool[i] end
	local f = Instance.new("TextButton")
	f.Name = "Row_" .. i
	f.Text = ""
	f.AutoButtonColor = false
	f.Size = UDim2.new(1, -10, 0, ROW_H)
	f.BackgroundColor3 = UIKit.PAPER
	f.BorderSizePixel = 0
	f.Parent = list
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, UIKit.RADIUS.md)
	local st = Instance.new("UIStroke", f)
	st.Thickness = 2
	st.Color = UIKit.CARD_LINE
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(0, 0.5)
	disc.Position = UDim2.new(0, 8, 0.5, 0)
	disc.Size = UDim2.new(0, 36, 0, 36)
	disc.BorderSizePixel = 0
	disc.Parent = f
	Instance.new("UICorner", disc).CornerRadius = UDim.new(1, 0)
	local r = {
		frame = f, stroke = st, disc = disc,
		icon = UIKit.icon(disc, "person", 22, UIKit.INK, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0) }),
		name = UIKit.label(f, "", UIKit.TYPE.body, UIKit.INK, {
			Name = "PersonName", Position = UDim2.new(0, 52, 0, 8), Size = UDim2.new(1, -150, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd,
		}, UIKit.HEAD),
		sub = UIKit.label(f, "", UIKit.TYPE.caption, UIKit.MUTED_TEXT, {
			Name = "Sub", Position = UDim2.new(0, 52, 0, 29), Size = UDim2.new(1, -84, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd,
		}, UIKit.BODY),
		rate = UIKit.label(f, "", UIKit.TYPE.body, UIKit.GREEN_DEEP, {
			Name = "Rate", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.new(0, 92, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Right,
		}, UIKit.HEAD),
		check = UIKit.art(f, "check", 18, { Name = "Fit", AnchorPoint = Vector2.new(0, 0.5), Visible = false }),
	}
	-- the ✓ sits after the words. TextBounds is in screen pixels, after the panel's
	-- UIScale; Position is not (live 14 Oct: at 0.94 the ✓ covered the last letter)
	local function place()
		local k = fit.Scale > 0 and fit.Scale or 1
		r.check.Position = UDim2.new(0, 52 + r.sub.TextBounds.X / k + 6, 0, 38)
	end
	r.sub:GetPropertyChangedSignal("TextBounds"):Connect(place)
	fit:GetPropertyChangedSignal("Scale"):Connect(place)
	f.MouseButton1Click:Connect(function()
		UIKit.sfx("tap")
		if r.id then
			selectedId = r.id
			reply = nil          -- the last person's "Trained!" or refusal is not this person's
			countSerial += 1     -- nor is their count-up
			refreshList()        -- the highlight moves to this row (review: it stayed on the first)
			refreshCard()
		end
	end)
	pool[i] = r
	return r
end

refreshList = function()
	local sorted = V.sort(rows, sortBy)
	for i, row in ipairs(sorted) do
		local r = rowFrame(i)
		r.id = row.id
		r.frame.LayoutOrder = i
		r.frame.Visible = true
		local tint = UIKit.TIER[string.lower(V.talent(row.talent))] or UIKit.TIER.regular
		r.disc.BackgroundColor3 = tint
		r.icon.Image = UIKit.ICON[UIKit.ROLE_ICON[row.role] or "person"] or ""
		r.name.Text = row.name or "?"
		r.rate.Text = perSec(row.rate)
		local note = V.note(row)
		if note then
			r.sub.Text = note
			r.sub.TextColor3 = UIKit.ORANGE_DEEP
			r.check.Visible = false
		else
			r.sub.Text = ("%s · %s · %s"):format(V.talent(row.talent), V.seniority(row.tier), V.label(row.room))
			r.sub.TextColor3 = UIKit.MUTED_TEXT
			r.check.Visible = row.fit == true
		end
		local on = row.id == selectedId
		r.frame.BackgroundColor3 = on and UIKit.BLUE_LIGHT or UIKit.PAPER
		r.stroke.Color = on and UIKit.BLUE or UIKit.CARD_LINE
	end
	for i = #sorted + 1, #pool do
		pool[i].frame.Visible = false
		pool[i].id = nil
	end
	count.Text = #rows == 1 and "1 person" or ("%d people"):format(#rows)
	return sorted
end

-- ---- the card ----
local chips = {}
local function chipFrame(i)
	if chips[i] then return chips[i] end
	local c = {}
	c.button = UIKit.button(chipBox, "", UIKit.PAPER, { Name = "Chip_" .. i, LayoutOrder = i }, { textSize = UIKit.TYPE.caption, dark = true })
	local label = c.button:FindFirstChild("Label")
	label.Size = UDim2.new(1, -12, 0, 18)
	label.Position = UDim2.new(0, 6, 0, 6)
	c.free = UIKit.label(c.button, "", UIKit.TYPE.caption, UIKit.MUTED_TEXT, {
		Name = "Free", Position = UDim2.new(0, 6, 0, 24), Size = UDim2.new(1, -12, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = c.button.ZIndex + 1,
	}, UIKit.BODY)
	c.check = UIKit.art(c.button, "check", 18, {
		Name = "Best", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 4), ZIndex = c.button.ZIndex + 2,
	})
	c.button.MouseButton1Click:Connect(function()
		local row = V.find(rows, selectedId)
		if not (row and c.chip) then return end
		if c.chip.state == "full" then
			say(V.why("no free seat"), UIKit.ORANGE_DEEP)
			return
		end
		local dept = c.chip.state == "here" and "" or c.chip.key   -- tap your own room again: unpinned
		send("move", row.id, dept)
	end)
	chips[i] = c
	return c
end

refreshCard = function()
	local row = V.find(rows, selectedId)
	if not row then
		selectedId = nil
		face.Visible, empty.Visible = false, true
		return
	end
	face.Visible, empty.Visible = true, false
	nameL.Text = row.name or "?"
	rateL.Text = perSec(row.rate)
	subL.Text = ("%s %s · %s"):format(V.talent(row.talent), ROLE[row.role] or "Staff", V.seniority(row.tier))
	if reply then
		noteL.Text, noteL.TextColor3 = reply.text, reply.colour
	else
		noteL.Text = V.note(row) or ("Sits in " .. V.label(row.room) .. ((row.pin or "") ~= "" and " (pinned)" or ""))
		noteL.TextColor3 = V.note(row) and UIKit.ORANGE_DEEP or UIKit.INK_SOFT
	end
	local money = cash()
	for _, b in ipairs(blocks) do
		local stat = row.stats and row.stats[b.stat.id]
		local level, cap = stat and stat.level or 0, stat and stat.cap or 0
		b.level.Text = ("%d / %d"):format(level, cap)
		b.fill.Size = UDim2.new(cap > 0 and math.clamp(level / cap, 0, 1) or 0, 0, 1, 0)
		local t = V.train(stat, money)
		b.state = t.state
		local label = b.button:FindFirstChild("Label")
		if t.state == "max" then
			UIKit.setButtonColor(b.button, UIKit.SURFACE_2)
			label.Text = "MAX"
		elseif t.state == "poor" then
			UIKit.setButtonColor(b.button, UIKit.SURFACE_2)
			label.Text = UIKit.money(t.price)
		else
			UIKit.setButtonColor(b.button, UIKit.GREEN)
			label.Text = "TRAIN " .. UIKit.money(t.price)
		end
	end
	local list2 = V.chips(row, rooms)
	for i, chip in ipairs(list2) do
		local c = chipFrame(i)
		c.chip = chip
		c.button.Visible = true
		c.button:FindFirstChild("Label").Text = chip.label
		c.check.Visible = chip.best
		if chip.state == "here" then
			UIKit.setButtonColor(c.button, UIKit.BLUE_LIGHT)
			c.free.Text = "pinned · tap to free"
			c.free.TextColor3 = UIKit.BLUE_DEEP
		elseif chip.state == "full" then
			UIKit.setButtonColor(c.button, UIKit.SURFACE_2)
			c.free.Text = "full"
			c.free.TextColor3 = UIKit.MUTED_TEXT
		else
			UIKit.setButtonColor(c.button, UIKit.PAPER)
			c.free.Text = ("%d free"):format(chip.free)
			c.free.TextColor3 = UIKit.MUTED_TEXT
		end
	end
	for i = #list2 + 1, #chips do
		chips[i].button.Visible = false
		chips[i].chip = nil
	end
end

for _, b in ipairs(blocks) do
	b.button.MouseButton1Click:Connect(function()
		local row = V.find(rows, selectedId)
		if not row then return end
		if b.state == "max" then
			say(V.why("at max"), UIKit.INK_SOFT)
			return
		elseif b.state == "poor" then
			say(V.why("need cash"), UIKit.ORANGE_DEEP)
			return
		end
		if send("train", row.id, b.stat.id) then
			lastTrain = { id = row.id, rate = tonumber(row.rate) or 0 }
			ringAt = b.button
		end
	end)
end

local function refresh()
	local before = lastTrain and V.find(rows, lastTrain.id)
	rows = decode("StaffData")
	rooms = decode("StaffRooms")
	UIKit.setRailVisible(btn, #rows > 0)
	if not gui.Enabled then return end
	refreshList()
	refreshCard()
	-- a TRAIN landed: the new $/s counts up on the card (the small reward beat)
	local now = lastTrain and V.find(rows, lastTrain.id)
	if before and now and now.id == selectedId and (tonumber(now.rate) or 0) > lastTrain.rate then
		countRate(lastTrain.rate, tonumber(now.rate) or 0)
		lastTrain = nil
	end
end
refresh()
player:GetAttributeChangedSignal("StaffData"):Connect(refresh)
player:GetAttributeChangedSignal("StaffRooms"):Connect(refresh)

task.spawn(function()
	local ls = player:WaitForChild("leaderstats", 30)
	local c = ls and ls:WaitForChild("Cash", 30)
	if c then c.Changed:Connect(function() if gui.Enabled then refreshCard() end end) end
end)

if remote then
	remote.OnClientEvent:Connect(function(msg)
		pending = false
		if type(msg) ~= "table" then return end
		-- StaffData can land before or after this reply: give the count-up a moment, then
		-- forget the TRAIN (Speed and Loyalty never raise $/s, so nothing else clears it)
		local lt = lastTrain
		task.delay(1, function() if lastTrain == lt then lastTrain = nil end end)
		local at = ringAt
		ringAt = nil
		if msg.ok then
			if msg.kind == "train" then
				UIKit.sfx("ding")
				if at and at.Parent and at.Visible then Moment.ring(gui, Moment.centreOf(at), UIKit.GREEN, 150) end
				say("Trained!", UIKit.GREEN_DEEP)
			else
				UIKit.sfx("thunk")
				reply = nil
			end
		else
			lastTrain = nil
			say(V.why(msg.why), UIKit.ORANGE_DEEP)
		end
		refreshCard()
	end)
end

sortBtn.MouseButton1Click:Connect(function()
	sortBy = sortBy == "rate" and "talent" or "rate"
	sortBtn:FindFirstChild("Label").Text = sortBy == "rate" and "SORT: $/s" or "SORT: TALENT"
	refreshList()
end)

local function setOpen(v)
	if v then
		UIKit.solo(gui)
		resize()
	end
	gui.Enabled = v
	if v then
		local sorted = refreshList()
		if not V.find(rows, selectedId) and sorted[1] then selectedId = sorted[1].id end
		refreshList()
		refreshCard()
	end
end
UIKit.onRailPress(btn, function() setOpen(not gui.Enabled) end)
if close then close.MouseButton1Click:Connect(function() setOpen(false) end) end
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Q and gui.Enabled then setOpen(false) end
end)
UIKit.bindRail(btn, gui)

-- the game doctor opens the screen on a list position (DoctorProbes.team); Studio only
local open = Instance.new("BindableEvent")
open.Name = "Open"
open.Parent = gui
open.Event:Connect(function(index)
	if index == false then setOpen(false) return end
	setOpen(true)
	local sorted = V.sort(rows, sortBy)
	if sorted[tonumber(index) or 1] then selectedId = sorted[tonumber(index) or 1].id end
	refreshList()
	refreshCard()
end)
