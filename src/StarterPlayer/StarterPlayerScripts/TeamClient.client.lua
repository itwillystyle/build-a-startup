--[[
	TeamClient -- LocalScript in StarterPlayer -> StarterPlayerScripts.

	MANAGE STAFF: the TEAM screen. v2 (14 Oct 2026, the redesign): Luke's pick from three
	mock-ups (ui/2026-10-14-team/mockups.html#o2, "the showroom, no tabs"), built from his
	reference board (ui/references/, Board A). Spec:
	docs/superpowers/specs/2026-10-14-team-screen-redesign-design.md §2.

	  left    every person as their real head, outlined in their talent colour
	  middle  the picked person, whole body; their $/s; a row of rooms (gold = where they
	          sit, ✓ = a best room, faded = full; tap to move and pin, tap again to unpin)
	  right   TRAIN: Skill, Speed, Loyalty as block meters (one block per level up to the
	          cap) with the price on the button. Only an affordable Skill is green.

	v1 (phase 3) was a text list and a card: three green buttons at once, facts said twice,
	thin bars, a cut-off row of chips. It passed every size check; the doctor now also
	checks loud buttons, repeated facts and cut-off parts (SlopRules).

	This script only draws and asks. The server sends StaffData and StaffRooms, owns every
	rule (StaffAction) and re-checks every request. TeamView (pure, tested) decides what
	each part shows; RigPortrait draws the characters.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local Moment = require(ReplicatedStorage:WaitForChild("Moment"))
local V = require(ReplicatedStorage:WaitForChild("TeamView"))
local Portrait = require(ReplicatedStorage:WaitForChild("RigPortrait"))
local remote = ReplicatedStorage:WaitForChild("SVRemotes"):WaitForChild("StaffAction", 30)

local ROLE = { engineer = "Engineer", designer = "Designer", sales = "Sales", recruiter = "Recruiter", research = "Researcher" }
local STATS = {   -- StaffStats.STATS order; icons are UIKit art/icon keys
	{ id = "skill", label = "Skill", icon = "coin", tint = UIKit.GOLD_DEEP, well = UIKit.GOLD_LIGHT },
	{ id = "speed", label = "Speed", icon = "fast", tint = UIKit.BLUE_DEEP, well = UIKit.BLUE_LIGHT },
	{ id = "loyalty", label = "Loyalty", icon = "medal", tint = UIKit.RED_DEEP, well = UIKit.light(UIKit.RED) },
}
local ROOM_ICON = { hq = "hq", lobby = "office", eng = "code", studio = "studio", cafe = "cafe", labs = "zoom" }

-- ============ THE TILE (MORE tray, plot only) ============

local btn = UIKit.railButton("team", "TEAM", UIKit.BLUE, {
	Name = "TeamButton", LayoutOrder = 3, Size = UDim2.new(0, UIKit.RAIL, 0, UIKit.RAIL), Visible = false,
}, { iconSize = 28, tray = true, plotOnly = true })

-- ============ THE PANEL (744 x 368 drawn, the mock's size) ============

local gui = Instance.new("ScreenGui")
gui.Name = "Team"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 12
gui.Enabled = false
UIKit.safe(gui)
gui.Parent = player:WaitForChild("PlayerGui")

local W, H, HEAD_H = 744, 368, 44
local FACES_W, TRAIN_W = 80, 300
local TILE, TILE_GAP, TAP = 56, 8, 52
local MAX_TILES = 8   -- live heads; + 1 body = 9 ViewportFrames (spec §2 budget)

local panel, body, close = UIKit.menu(gui, "TEAM", UIKit.BLUE, {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0, W, 0, H),
}, { headerHeight = HEAD_H })
body.Position = UDim2.new(0, 0, 0, HEAD_H)
body.Size = UDim2.new(1, 0, 1, -HEAD_H)
local fit = Instance.new("UIScale", panel)
UIKit.fitMenu(panel, W, H, fit, 16)

local count = UIKit.label(panel:FindFirstChild("Header"), "", UIKit.TYPE.label, UIKit.TEXT, {
	Name = "Count", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -62, 0.5, -1), Size = UDim2.new(0, 120, 0, 24),
	TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3,
}, UIKit.HEAD)
UIKit.paintLabel(count, UIKit.BLUE)

local function edge(parent, x)   -- a 2 px divider
	local f = Instance.new("Frame")
	f.BackgroundColor3 = UIKit.LINE_LIGHT
	f.BorderSizePixel = 0
	f.Position = UDim2.new(0, x, 0, 0)
	f.Size = UDim2.new(0, 2, 1, 0)
	f.Parent = parent
	return f
end

-- ---- left: the faces ----
local faces = Instance.new("ScrollingFrame")
faces.Name = "Faces"
faces.Size = UDim2.new(0, FACES_W, 1, 0)
faces.BackgroundColor3 = UIKit.SURFACE_2
faces.BorderSizePixel = 0
faces.ScrollBarThickness = 4
faces.ScrollBarImageColor3 = UIKit.LINE_LIGHT
faces.ScrollingDirection = Enum.ScrollingDirection.Y
faces.AutomaticCanvasSize = Enum.AutomaticSize.Y
faces.CanvasSize = UDim2.new(0, 0, 0, 0)
faces.Parent = body
local flay = Instance.new("UIListLayout", faces)
flay.Padding = UDim.new(0, TILE_GAP)
flay.HorizontalAlignment = Enum.HorizontalAlignment.Center
flay.SortOrder = Enum.SortOrder.LayoutOrder
local fpad = Instance.new("UIPadding", faces)
fpad.PaddingTop, fpad.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10)
edge(body, FACES_W)

-- ---- right: TRAIN ----
local train = Instance.new("Frame")
train.Name = "Train"
train.AnchorPoint = Vector2.new(1, 0)
train.Position = UDim2.new(1, 0, 0, 0)
train.Size = UDim2.new(0, TRAIN_W, 1, 0)
train.BackgroundColor3 = UIKit.PAPER
train.BorderSizePixel = 0
train.Parent = body
edge(body, W - TRAIN_W - 2)
local tpad = Instance.new("UIPadding", train)
tpad.PaddingLeft, tpad.PaddingRight, tpad.PaddingTop = UDim.new(0, 14), UDim.new(0, 12), UDim.new(0, 10)
UIKit.label(train, "TRAIN", UIKit.TYPE.caption, UIKit.MUTED_TEXT, { Name = "Heading", Size = UDim2.new(1, 0, 0, 18) }, UIKit.HEAD)

local blocks = {}
for i, st in ipairs(STATS) do
	local y = 26 + (i - 1) * 76
	local b = { stat = st }
	local well = Instance.new("Frame")
	well.Name = st.label .. "Icon"
	well.Position = UDim2.new(0, 0, 0, y + 10)
	well.Size = UDim2.new(0, 32, 0, 32)
	well.BackgroundColor3 = st.well
	well.BorderSizePixel = 0
	well.Parent = train
	Instance.new("UICorner", well).CornerRadius = UDim.new(0, UIKit.RADIUS.sm)
	local ws = Instance.new("UIStroke", well)
	ws.Color = st.tint
	ws.Thickness = 2
	UIKit.art(well, st.icon, 24, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0) })
	UIKit.label(train, st.label, UIKit.TYPE.label, UIKit.INK, {
		Name = st.label, Position = UDim2.new(0, 42, 0, y + 15), Size = UDim2.new(0, 80, 0, 22),
	}, UIKit.HEAD)
	b.level = UIKit.label(train, "", UIKit.TYPE.caption, UIKit.INK_SOFT, {
		Name = st.label .. "Level", Position = UDim2.new(0, 122, 0, y + 17), Size = UDim2.new(0, 46, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
	}, UIKit.HEAD)
	b.button = UIKit.button(train, "", UIKit.PAPER, {
		Name = "Train_" .. st.id, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, y),
		Size = UDim2.new(0, 96, 0, TAP),
	}, { textSize = UIKit.TYPE.body })
	local meter = Instance.new("Frame")
	meter.Name = st.label .. "Meter"
	meter.BackgroundTransparency = 1
	meter.Position = UDim2.new(0, 0, 0, y + TAP + 6)
	meter.Size = UDim2.new(1, 0, 0, 14)
	meter.Parent = train
	local ml = Instance.new("UIListLayout", meter)
	ml.FillDirection = Enum.FillDirection.Horizontal
	ml.Padding = UDim.new(0, 3)
	ml.SortOrder = Enum.SortOrder.LayoutOrder
	b.meter, b.cells = meter, {}
	blocks[i] = b
end

-- ---- middle: the person ----
local person = Instance.new("Frame")
person.Name = "Person"
person.BackgroundTransparency = 1
person.Position = UDim2.new(0, FACES_W + 2, 0, 0)
person.Size = UDim2.new(1, -(FACES_W + 4 + TRAIN_W), 1, 0)
person.Parent = body

local glow = Instance.new("Frame")   -- a soft disc in the talent's light tint behind them
glow.Name = "Glow"
glow.AnchorPoint = Vector2.new(0.5, 0.5)
glow.Position = UDim2.new(0.5, 0, 0, 84)
glow.Size = UDim2.new(0, 170, 0, 170)
glow.BackgroundColor3 = UIKit.PAPER
glow.BackgroundTransparency = 0.35
glow.BorderSizePixel = 0
glow.Parent = person
Instance.new("UICorner", glow).CornerRadius = UDim.new(1, 0)

local function newViewport(parent, props)
	local v = Instance.new("ViewportFrame")
	v.BackgroundTransparency = 1
	v.Ambient = Color3.fromRGB(210, 210, 215)  -- world colour
	v.LightColor = Color3.fromRGB(255, 250, 240)  -- world colour
	v.LightDirection = Vector3.new(-0.4, -1, -0.6)
	for k, val in pairs(props) do v[k] = val end
	v.Parent = parent
	return v
end
local bodyView = newViewport(person, {
	Name = "Figure", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.new(0, 150, 0, 156),
})
local bodyFallback = UIKit.icon(person, "person", 96, UIKit.INK_SOFT, {
	Name = "BodyFallback", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 84), Visible = false,
})

local nameL = UIKit.label(person, "", UIKit.TYPE.headline, UIKit.INK, {
	Name = "PersonName", Position = UDim2.new(0, 8, 0, 160), Size = UDim2.new(1, -16, 0, 30),
	TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd,
}, UIKit.HEAD)
local tagRow = Instance.new("Frame")
tagRow.Name = "Tags"
tagRow.BackgroundTransparency = 1
tagRow.Position = UDim2.new(0, 0, 0, 191)
tagRow.Size = UDim2.new(1, 0, 0, 20)
tagRow.Parent = person
local tl = Instance.new("UIListLayout", tagRow)
tl.FillDirection = Enum.FillDirection.Horizontal
tl.HorizontalAlignment = Enum.HorizontalAlignment.Center
tl.VerticalAlignment = Enum.VerticalAlignment.Center
tl.Padding = UDim.new(0, 6)
tl.SortOrder = Enum.SortOrder.LayoutOrder
local pill = Instance.new("Frame")
pill.Name = "Talent"
pill.AutomaticSize = Enum.AutomaticSize.X
pill.Size = UDim2.new(0, 0, 0, 20)
pill.BorderSizePixel = 0
pill.Parent = tagRow
Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)
local ppad = Instance.new("UIPadding", pill)
ppad.PaddingLeft, ppad.PaddingRight = UDim.new(0, 9), UDim.new(0, 9)
local pillText = UIKit.label(pill, "", UIKit.TYPE.caption, UIKit.TEXT, {
	Name = "Text", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0),
}, UIKit.HEAD)
local roleL = UIKit.label(tagRow, "", UIKit.TYPE.caption, UIKit.MUTED_TEXT, {
	Name = "Role", LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0),
}, UIKit.BODY)
local rateL = UIKit.outlined(person, "", UIKit.TYPE.title, UIKit.MONEY, {
	Name = "Rate", Position = UDim2.new(0, 0, 0, 213), Size = UDim2.new(1, 0, 0, 26),
})
rateL.TextXAlignment = Enum.TextXAlignment.Center

local roomsRow = Instance.new("Frame")
roomsRow.Name = "Rooms"
roomsRow.BackgroundTransparency = 1
roomsRow.Position = UDim2.new(0, 0, 0, 246)
roomsRow.Size = UDim2.new(1, 0, 0, TAP)
roomsRow.Parent = person
local rl = Instance.new("UIListLayout", roomsRow)
rl.FillDirection = Enum.FillDirection.Horizontal
rl.HorizontalAlignment = Enum.HorizontalAlignment.Center
rl.Padding = UDim.new(0, 6)
rl.SortOrder = Enum.SortOrder.LayoutOrder
local lineL = UIKit.label(person, "", UIKit.TYPE.caption, UIKit.INK_SOFT, {
	Name = "Line", Position = UDim2.new(0, 8, 0, 302), Size = UDim2.new(1, -16, 0, 18),
	TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd,
}, UIKit.HEAD)

-- ============ STATE ============

local rows, rooms = {}, {}
local selectedId
local pending = false
local lastTrain   -- { id, rate, stat, level } of the last TRAIN sent: the pop and the count-up
local ringAt      -- the TRAIN button pressed, for the ring when the server says yes
local reply       -- { text, colour } shown on the line under the rooms for 4 s
local refreshCard

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
local function tierColour(t) return UIKit.TIER[string.lower(V.talent(t))] or UIKit.TIER.regular end

-- the $/s counting up after a TRAIN lands; tapping someone else stops it
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

local function say(text, colour)
	reply = { text = text, colour = colour }
	local mine = reply
	if refreshCard then refreshCard() end
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
	task.delay(1.5, function() pending = false end)   -- the rate limit drops a request without a reply
	return true
end

-- ---- face tiles (a pool, reused as StaffData changes) ----
local tiles = {}
local refreshFaces

local function tileFor(i)
	if tiles[i] then return tiles[i] end
	local t = {}
	t.button = Instance.new("TextButton")
	t.button.Name = "Face_" .. i
	t.button.Text = ""
	t.button.AutoButtonColor = false
	t.button.Size = UDim2.new(0, TILE, 0, TILE)
	t.button.BackgroundColor3 = UIKit.PAPER
	t.button.BorderSizePixel = 0
	t.button.Parent = faces
	Instance.new("UICorner", t.button).CornerRadius = UDim.new(0, UIKit.RADIUS.md)
	t.stroke = Instance.new("UIStroke", t.button)
	t.stroke.Thickness = 3
	t.stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	t.view = newViewport(t.button, { Name = "Head", Size = UDim2.new(1, 0, 1, 0) })
	Instance.new("UICorner", t.view).CornerRadius = UDim.new(0, UIKit.RADIUS.md)
	t.icon = UIKit.icon(t.button, "person", 30, UIKit.INK_SOFT, { Name = "Fallback", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0) })
	t.button.MouseButton1Click:Connect(function()
		UIKit.sfx("tap")
		if t.id then
			selectedId = t.id
			reply = nil
			countSerial += 1
			refreshFaces()
			refreshCard()
		end
	end)
	tiles[i] = t
	return t
end

-- draw (or clear) the head in one tile; only tiles in view get a live character
local function drawHead(t, row, live)
	local rig = live and Portrait.find(player.UserId, row.id) or nil
	if rig ~= t.rig then
		t.rig = rig
		t.drawn = rig and Portrait.show(t.view, rig, "head") or false
		if not rig then Portrait.clear(t.view) end
	end
	t.icon.Visible = not t.drawn
	t.icon.Image = UIKit.ICON[UIKit.ROLE_ICON[row.role] or "person"] or UIKit.ICON.person
	t.icon.ImageColor3 = UIKit.deep(tierColour(row.talent))
end

refreshFaces = function()
	local sorted = V.sort(rows, "rate")
	local first, last = V.visible(faces.CanvasPosition.Y, H - HEAD_H - 20, TILE, TILE_GAP, #sorted, MAX_TILES)
	for i, row in ipairs(sorted) do
		local t = tileFor(i)
		t.id = row.id
		t.button.LayoutOrder = i
		t.button.Visible = true
		local on = row.id == selectedId
		t.stroke.Color = on and UIKit.GOLD or tierColour(row.talent)
		t.stroke.Thickness = on and 4 or 3
		t.button.BackgroundColor3 = on and UIKit.GOLD_LIGHT or UIKit.PAPER
		drawHead(t, row, i >= first and i <= last)
	end
	for i = #sorted + 1, #tiles do
		local t = tiles[i]
		t.button.Visible = false
		t.id, t.rig, t.drawn = nil, nil, false
		Portrait.clear(t.view)
	end
	count.Text = #rows == 1 and "1 person" or ("%d people"):format(#rows)
	return sorted
end
faces:GetPropertyChangedSignal("CanvasPosition"):Connect(function() if gui.Enabled then refreshFaces() end end)

-- ---- room buttons (a pool) ----
local roomBtns = {}
local function roomFor(i)
	if roomBtns[i] then return roomBtns[i] end
	local r = {}
	r.button = Instance.new("TextButton")
	r.button.Name = "Room_" .. i
	r.button.Text = ""
	r.button.AutoButtonColor = false
	r.button.LayoutOrder = i
	r.button.Size = UDim2.new(0, TAP, 0, TAP)
	r.button.BorderSizePixel = 0
	r.button.Parent = roomsRow
	Instance.new("UICorner", r.button).CornerRadius = UDim.new(0, UIKit.RADIUS.md)
	r.stroke = Instance.new("UIStroke", r.button)
	r.stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	-- rendered art where the game has it, else a plain icon (two images: art keeps its own colours)
	r.art = UIKit.art(r.button, "hq", 32, { Name = "Art", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0) })
	r.glyph = UIKit.icon(r.button, "home", 28, UIKit.INK_SOFT, { Name = "Glyph", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0) })
	r.best = UIKit.art(r.button, "check", 20, { Name = "Best", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -3, 0, 3), ZIndex = r.button.ZIndex + 2 })
	r.button.MouseButton1Click:Connect(function()
		local row = V.find(rows, selectedId)
		if not (row and r.chip) then return end
		UIKit.sfx("tap")
		if r.chip.state == "full" then say(V.why("no free seat"), UIKit.ORANGE_DEEP) return end
		send("move", row.id, r.chip.state == "here" and "" or r.chip.key)   -- your own pin again: unpinned
	end)
	roomBtns[i] = r
	return r
end

local shownBody   -- the rig drawn in the middle (redrawn only when it changes)

refreshCard = function()
	local row = V.find(rows, selectedId)
	person.Visible, train.Visible = row ~= nil, row ~= nil
	if not row then return end
	-- the person
	local rig = Portrait.find(player.UserId, row.id)
	if rig ~= shownBody or not rig then
		-- (a missing rig is never "unchanged": live 14 Oct, the middle stayed blank with no fallback)
		shownBody = rig
		local ok = rig and Portrait.show(bodyView, rig, "body") or false
		if not rig then Portrait.clear(bodyView) end
		bodyFallback.Visible = not ok
	end
	local g = V.glow(row.talent)
	glow.BackgroundColor3 = (g == "genius" and UIKit.light(UIKit.PURPLE)) or (g == "unicorn" and UIKit.GOLD_LIGHT) or UIKit.PAPER
	nameL.Text = row.name or "?"
	local tc = tierColour(row.talent)
	pill.BackgroundColor3 = tc
	pillText.Text = string.upper(V.talent(row.talent))
	pillText.TextColor3 = UIKit.onColor(tc)
	roleL.Text = ("%s · %s"):format(ROLE[row.role] or "Staff", V.seniority(row.tier))
	rateL.Text = perSec(row.rate)
	-- rooms
	local chips = V.chips(row, rooms)
	for i, chip in ipairs(chips) do
		local r = roomFor(i)
		r.chip = chip
		r.button.Visible = true
		local key = ROOM_ICON[chip.key] or "home"
		r.art.Visible = UIKit.ART[key] ~= nil
		r.glyph.Visible = not r.art.Visible
		if r.art.Visible then r.art.Image = UIKit.ART[key] else r.glyph.Image = UIKit.ICON[key] or UIKit.ICON.home end
		local here = row.room == chip.key
		r.button.BackgroundColor3 = chip.state == "here" and UIKit.BLUE_LIGHT or UIKit.PAPER
		r.stroke.Color = here and UIKit.GOLD or UIKit.LINE_LIGHT
		r.stroke.Thickness = here and 3 or 2
		r.art.ImageTransparency = chip.state == "full" and 0.6 or 0
		r.glyph.ImageTransparency = r.art.ImageTransparency
		r.best.Visible = chip.best
	end
	for i = #chips + 1, #roomBtns do
		roomBtns[i].button.Visible = false
		roomBtns[i].chip = nil
	end
	if reply then
		lineL.Text, lineL.TextColor3 = reply.text, reply.colour
	else
		lineL.Text = V.roomLine(row)
		lineL.TextColor3 = V.note(row) and UIKit.ORANGE_DEEP or UIKit.INK_SOFT
	end
	-- training
	local money = cash()
	for _, b in ipairs(blocks) do
		local stat = row.stats and row.stats[b.stat.id]
		local level, cap = stat and stat.level or 0, stat and stat.cap or 0
		b.level.Text = ("%d/%d"):format(level, cap)
		local t = V.train(stat, money)
		local look = V.look(b.stat.id, t)
		b.look = look
		local label = b.button:FindFirstChild("Label")
		if look == "max" then
			UIKit.setButtonColor(b.button, UIKit.GOLD_LIGHT)
			label.Text = "MAX"
		elseif look == "go" then
			UIKit.setButtonColor(b.button, UIKit.GREEN)
			label.Text = UIKit.money(t.price)
		elseif look == "dim" then
			UIKit.setButtonColor(b.button, UIKit.SURFACE_2)
			label.Text = UIKit.money(t.price)
			label.TextColor3 = UIKit.MUTED_TEXT
		else
			UIKit.setButtonColor(b.button, UIKit.PAPER)
			label.Text = UIKit.money(t.price)
		end
		-- the block meter: one block per level up to the cap
		for i = 1, math.max(cap, #b.cells) do
			local c = b.cells[i]
			if i <= cap and not c then
				c = Instance.new("Frame")
				c.BorderSizePixel = 0
				c.LayoutOrder = i
				c.Parent = b.meter
				Instance.new("UICorner", c).CornerRadius = UDim.new(0, UIKit.RADIUS.sm / 2)   -- a block, not a pill (14 px tall)
				local cs = Instance.new("UIStroke", c)
				cs.Thickness = 1.5
				local pop = Instance.new("UIScale")   -- the new block pops in
				pop.Parent = c
				b.cells[i] = c
			end
			if c then
				c.Visible = i <= cap
				c.Size = UDim2.new(1 / math.max(cap, 1), -3, 1, 0)
				local full = i <= level
				local done = level >= cap
				c.BackgroundColor3 = full and (done and UIKit.GOLD or UIKit.BLUE) or UIKit.SURFACE_2
				c:FindFirstChildOfClass("UIStroke").Color = full and (done and UIKit.GOLD_DEEP or UIKit.BLUE_DEEP) or UIKit.LINE_LIGHT
			end
		end
	end
end

for _, b in ipairs(blocks) do
	b.button.MouseButton1Click:Connect(function()
		local row = V.find(rows, selectedId)
		if not row then return end
		if b.look == "max" then say(V.why("at max"), UIKit.INK_SOFT) return end
		if b.look == "dim" then say(V.why("need cash"), UIKit.ORANGE_DEEP) return end
		local stat = row.stats and row.stats[b.stat.id]
		if send("train", row.id, b.stat.id) then
			lastTrain = { id = row.id, rate = tonumber(row.rate) or 0, stat = b.stat.id, level = stat and stat.level or 0 }
			ringAt = b.button
		end
	end)
end

-- the new block pops in (scale 1.6 -> 1, Quint ease-out: no overshoot)
local function popBlock(statId, index)
	for _, b in ipairs(blocks) do
		local c = b.stat.id == statId and b.cells[index]
		if c then
			local sc = c:FindFirstChildOfClass("UIScale")
			sc.Scale = 1.6
			TweenService:Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end
end

local function refresh()
	local before = lastTrain and V.find(rows, lastTrain.id)
	rows = decode("StaffData")
	rooms = decode("StaffRooms")
	UIKit.setRailVisible(btn, #rows > 0)
	if not gui.Enabled then return end
	if not V.find(rows, selectedId) then
		local sorted = V.sort(rows, "rate")
		selectedId = sorted[1] and sorted[1].id or nil
	end
	refreshFaces()
	refreshCard()
	-- a TRAIN landed: the block pops and the $/s counts up (the small reward beat)
	local now = lastTrain and V.find(rows, lastTrain.id)
	if before and now and now.id == selectedId then
		local st = now.stats and now.stats[lastTrain.stat]
		if st and st.level > lastTrain.level then
			popBlock(lastTrain.stat, st.level)
			if (tonumber(now.rate) or 0) > lastTrain.rate then countRate(lastTrain.rate, tonumber(now.rate) or 0) end
			lastTrain = nil
		end
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
		local lt = lastTrain
		task.delay(1, function() if lastTrain == lt then lastTrain = nil end end)
		local at = ringAt
		ringAt = nil
		if msg.ok then
			if msg.kind == "train" then
				UIKit.sfx("ding")
				if at and at.Parent and at.Visible then Moment.ring(gui, Moment.centreOf(at), UIKit.GREEN, 150) end
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

-- characters are drawn only while the screen is open (none rendering while closed)
local function releaseAll()
	for _, t in ipairs(tiles) do
		t.rig, t.drawn = nil, false
		Portrait.clear(t.view)
	end
	shownBody = nil
	Portrait.clear(bodyView)
end

local function setOpen(v)
	if v then UIKit.solo(gui) end
	gui.Enabled = v
	if v then refresh() end
end
UIKit.onRailPress(btn, function() setOpen(not gui.Enabled) end)
if close then close.MouseButton1Click:Connect(function() setOpen(false) end) end
gui:GetPropertyChangedSignal("Enabled"):Connect(function() if not gui.Enabled then releaseAll() end end)   -- every close path, UIKit.solo included
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Q and gui.Enabled then setOpen(false) end
end)
UIKit.bindRail(btn, gui)

-- the game doctor opens the screen on a face (DoctorProbes.team); Fire(false) closes it
local open = Instance.new("BindableEvent")
open.Name = "Open"
open.Parent = gui
open.Event:Connect(function(index)
	if index == false then setOpen(false) return end
	setOpen(true)
	local sorted = V.sort(rows, "rate")
	if sorted[tonumber(index) or 1] then selectedId = sorted[tonumber(index) or 1].id end
	refreshFaces()
	refreshCard()
end)
