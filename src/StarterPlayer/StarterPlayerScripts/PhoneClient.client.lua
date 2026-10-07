--[[
	PhoneClient -- LocalScript in StarterPlayer -> StarterPlayerScripts (v3.2).

	The founder's phone. A real phone on screen (bezel, status bar, apps), held
	sideways because a phone game is played sideways: the conversation on the
	left, your replies on the right, so the thread never hides behind a
	keyboard.

	  MESSAGES  AI investors text you (server: Phone.lua). Pick one of three
	            replies built from your company's real numbers, or type your
	            own. Three messages, then a TERM SHEET: TAKE / PUSH FOR MORE /
	            PASS. Every investor is labelled AI.
	  CALLS     voice-call another founder in this server. The server rings and
	            connects; the audio is wired HERE: their AudioDeviceInput ->
	            an AudioFader -> a local AudioDeviceOutput. Faded out when you
	            stand next to each other (spatial voice already carries it).
	  REWARDS   the daily streak (opens the daily card).

	Outside the phone: a text banner when a message lands, a ringing card for an
	incoming call, and a call pill while you talk with the phone closed.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TextService = game:GetService("TextService")
local VoiceChatService = game:GetService("VoiceChatService")

local player = Players.LocalPlayer
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local Notify = require(ReplicatedStorage:WaitForChild("Notify"))
local Items = require(ReplicatedStorage:WaitForChild("Items"))
local remotes = ReplicatedStorage:WaitForChild("SVRemotes")
local ev = remotes:WaitForChild("PhoneEvent", 60)
local act = remotes:WaitForChild("PhoneAction", 60)
if not ev or not act then return end

local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local W, H = 584, 330                    -- the phone's design size (v5: 584 fits right of Roblox's top-left buttons on a phone)
local SIDE = 78
local BODY = UIKit.BODY               -- v5: Nunito ExtraBold (thin Gotham was the "web app" text)
local BUBBLE_TEXT = 16
-- the one-line width of a text in the body font (GetTextSize only takes the old Font enum)
local function lineWidth(text, size)
	local ok, v = pcall(function()
		local p = Instance.new("GetTextBoundsParams")
		p.Text = text
		p.Font = BODY
		p.Size = size
		p.Width = 10000
		return TextService:GetTextBoundsAsync(p)
	end)
	if ok and v then return v.X end
	return TextService:GetTextSize(text, size, Enum.Font.GothamBold, Vector2.new(10000, 10000)).X
end

-- ============ STATE ============

local threads, order = {}, {}            -- id -> thread; ids, newest first
local view = { app = "messages", thread = nil }
local call = {}                          -- { state, with, name, id, since, muted }

-- ============ THE RAIL BUTTON ============

local railBtn = UIKit.railButton("phone", "PHONE", UIKit.RED, {
	Name = "PhoneButton", LayoutOrder = 3, Size = UDim2.new(0, UIKit.RAIL, 0, UIKit.RAIL), Visible = false,
}, { iconSize = 28 })
local railBadge, railBadgeText = UIKit.badge(railBtn)

-- ============ THE PHONE ============

local gui = Instance.new("ScreenGui")
gui.Name = "Phone"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 15
gui.Enabled = false
UIKit.safe(gui)
gui.Parent = player:WaitForChild("PlayerGui")

local bezel = Instance.new("Frame")
bezel.Name = "Bezel"
bezel.AnchorPoint = Vector2.new(0.5, 0.5)
bezel.Position = UDim2.new(0.5, 30, 0.5, 26)
bezel.Size = UDim2.new(0, W, 0, H)
bezel.BackgroundColor3 = Color3.fromRGB(24, 26, 34)
bezel.BorderSizePixel = 0
bezel.Parent = gui
Instance.new("UICorner", bezel).CornerRadius = UDim.new(0, 30)
local rim = Instance.new("UIStroke", bezel)
rim.Color = Color3.fromRGB(70, 76, 96)
rim.Thickness = 2
local fit = Instance.new("UIScale", bezel)
local place = UIKit.fitMenu(bezel, W, H, fit)   -- v5: the shared rule (clears the rail, scales to fit)

local screen = Instance.new("Frame")
screen.Name = "Screen"
screen.Position = UDim2.new(0, 9, 0, 9)
screen.Size = UDim2.new(1, -18, 1, -18)
screen.BackgroundColor3 = UIKit.SURFACE_2
screen.BorderSizePixel = 0
screen.ClipsDescendants = true
screen.Parent = bezel
Instance.new("UICorner", screen).CornerRadius = UDim.new(0, 22)

-- status bar: time, the island, signal, battery (drawn, no images)
local status = Instance.new("Frame")
status.Name = "Status"
status.BackgroundTransparency = 1
status.Size = UDim2.new(1, 0, 0, 24)
status.Parent = screen
local clock = UIKit.label(status, "", 14, UIKit.CARD_TEXT, { Position = UDim2.new(0, 22, 0, 4), Size = UDim2.new(0, 60, 0, 18) }, UIKit.HEAD)
local island = Instance.new("Frame")
island.AnchorPoint = Vector2.new(0.5, 0)
island.Position = UDim2.new(0.5, 0, 0, 5)
island.Size = UDim2.new(0, 86, 0, 16)
island.BackgroundColor3 = Color3.fromRGB(24, 26, 34)
island.BorderSizePixel = 0
island.Parent = status
Instance.new("UICorner", island).CornerRadius = UDim.new(1, 0)
-- (v5: the drawn signal bars and battery are gone: decoration with no information,
-- and a green battery borrowed the colour that means "go". The clock and the
-- island are what make it read as a phone.)

-- the side dock: three apps
local dock = Instance.new("Frame")
dock.Name = "Dock"
dock.Position = UDim2.new(0, 0, 0, 24)
dock.Size = UDim2.new(0, SIDE, 1, -24)
dock.BackgroundColor3 = UIKit.CARD
dock.BorderSizePixel = 0
dock.Parent = screen
-- the divider lives on the screen, not in the dock: the dock's list layout
-- would stack it as the first "app" and push the icons off the phone
local dockLine = Instance.new("Frame")
dockLine.Name = "DockLine"
dockLine.Position = UDim2.new(0, SIDE - 1, 0, 24)
dockLine.Size = UDim2.new(0, 1, 1, -24)
dockLine.BackgroundColor3 = UIKit.CARD_LINE
dockLine.BorderSizePixel = 0
dockLine.ZIndex = 2
dockLine.Parent = screen
local dockList = Instance.new("UIListLayout", dock)
dockList.Padding = UDim.new(0, 8)
dockList.HorizontalAlignment = Enum.HorizontalAlignment.Center
dockList.SortOrder = Enum.SortOrder.LayoutOrder
local dockPad = Instance.new("UIPadding", dock)
dockPad.PaddingTop = UDim.new(0, 10)

local content = Instance.new("Frame")
content.Name = "Content"
content.BackgroundTransparency = 1
content.Position = UDim2.new(0, SIDE, 0, 24)
content.Size = UDim2.new(1, -SIDE, 1, -24)
content.Parent = screen

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.Text = ""
closeBtn.AutoButtonColor = false
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -10, 0, 28)
closeBtn.Size = UDim2.new(0, 44, 0, 44)
closeBtn.BackgroundColor3 = UIKit.CARD
closeBtn.ZIndex = 20
closeBtn.Parent = screen
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)
local cst = Instance.new("UIStroke", closeBtn)
cst.Color = UIKit.INK_SOFT
cst.Thickness = 2.5
UIKit.icon(closeBtn, "cross", 18, UIKit.INK_SOFT, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), ZIndex = 21 })

local apps = {}
local render   -- forward: draws the current view (defined below)
local refreshBadge   -- forward: the rail badge (defined at the end; the call handler calls it)

local function appButton(id, label, color, drawIcon, order)
	local b = Instance.new("TextButton")
	b.Name = "App_" .. id
	b.Text = ""
	b.AutoButtonColor = false
	b.LayoutOrder = order
	b.Size = UDim2.new(0, 58, 0, 72)
	b.BackgroundTransparency = 1
	b.Parent = dock
	local tile = Instance.new("Frame")
	tile.Name = "Tile"
	tile.AnchorPoint = Vector2.new(0.5, 0)
	tile.Position = UDim2.new(0.5, 0, 0, 0)
	tile.Size = UDim2.new(0, 50, 0, 50)
	tile.BackgroundColor3 = color
	tile.BorderSizePixel = 0
	tile.Parent = b
	Instance.new("UICorner", tile).CornerRadius = UDim.new(0, 14)
	local grad = Instance.new("UIGradient", tile)
	grad.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(210, 210, 210))
	grad.Rotation = 90
	local ring = Instance.new("UIStroke", tile)
	ring.Color = UIKit.BLUE
	ring.Thickness = 0
	drawIcon(tile)
	UIKit.label(b, label, 14, UIKit.CARD_TEXT, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 8, 0, 18), TextXAlignment = Enum.TextXAlignment.Center }, UIKit.HEAD)
	local dot, dotText = UIKit.badge(tile)
	b.MouseButton1Down:Connect(function() UIKit.sfx("tap") end)
	b.MouseButton1Click:Connect(function()
		view.app = id
		view.thread = nil
		render()
	end)
	apps[id] = { button = b, ring = ring, dot = dot, dotText = dotText }
end

-- app icons, drawn: a speech bubble, a handset, a medal
appButton("messages", "Texts", UIKit.GREEN, function(tile)
	local bub = Instance.new("Frame")
	bub.AnchorPoint = Vector2.new(0.5, 0.5)
	bub.Position = UDim2.new(0.5, 0, 0.46, 0)
	bub.Size = UDim2.new(0, 30, 0, 22)
	bub.BackgroundColor3 = UIKit.TEXT
	bub.BorderSizePixel = 0
	bub.Parent = tile
	Instance.new("UICorner", bub).CornerRadius = UDim.new(1, 0)
	local tail = Instance.new("Frame")
	tail.Position = UDim2.new(0, 4, 1, -6)
	tail.Size = UDim2.new(0, 9, 0, 9)
	tail.Rotation = 35
	tail.BackgroundColor3 = UIKit.TEXT
	tail.BorderSizePixel = 0
	tail.Parent = bub
end, 1)
appButton("calls", "Calls", Color3.fromRGB(60, 190, 150), function(tile)
	UIKit.icon(tile, "phone", 28, UIKit.TEXT, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0) })
end, 2)
-- (v5: the Daily app is gone: the daily gift has its own rail tile, DailyClient)

-- ============ SMALL PIECES ============

local function clear()
	for _, c in ipairs(content:GetChildren()) do c:Destroy() end
end

local function avatar(parent, th, size)
	local a = Instance.new("Frame")
	a.Name = "Avatar"
	a.Size = UDim2.new(0, size, 0, size)
	a.BackgroundColor3 = th.color or UIKit.BLUE
	a.BorderSizePixel = 0
	a.Parent = parent
	Instance.new("UICorner", a).CornerRadius = UDim.new(1, 0)
	local initials = (th.name or "?"):gsub("(%a)%a*%s*", "%1"):sub(1, 2):upper()
	-- the initials sit a little high so the AI tag under them never covers a letter
	-- (v5: at the old bottom-right spot "VL" read as "VI")
	local lift = th.system and 0 or math.floor(size * 0.12)
	local ini = UIKit.label(a, initials, math.floor(size * 0.42), UIKit.TEXT, { Position = UDim2.new(0, 0, 0, -lift), Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center }, UIKit.HEAD)
	UIKit.paintLabel(ini, a.BackgroundColor3)   -- v5: ink on a light face, outlined white on a dark one
	-- v4.2: a scripted sender (the front desk) is not AI, so it gets no badge
	if not th.system then
		-- the AI label rides on every investor's face (Roblox asks for disclosure; so does honesty)
		local tag = Instance.new("Frame")
		tag.AnchorPoint = Vector2.new(0.5, 0.5)
		tag.Position = UDim2.new(0.5, 0, 1, -1)
		tag.Size = UDim2.new(0, 26, 0, 18)
		tag.BackgroundColor3 = UIKit.INK
		tag.BorderSizePixel = 0
		tag.Parent = a
		Instance.new("UICorner", tag).CornerRadius = UDim.new(1, 0)
		local ring = Instance.new("UIStroke", tag)      -- a paper edge so it reads as a sticker on any face colour
		ring.Color = UIKit.PAPER
		ring.Thickness = 1.5
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		UIKit.label(tag, "AI", 14, UIKit.TEXT, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center }, UIKit.HEAD)
	end
	return a
end

local headshots = {}
local function headshot(parent, userId, size)
	local img = Instance.new("ImageLabel")
	img.Name = "Headshot"
	img.Size = UDim2.new(0, size, 0, size)
	img.BackgroundColor3 = UIKit.CARD_LINE
	img.BorderSizePixel = 0
	img.Parent = parent
	Instance.new("UICorner", img).CornerRadius = UDim.new(1, 0)
	if headshots[userId] then
		img.Image = headshots[userId]
	else
		task.spawn(function()
			local ok, url = pcall(function()
				return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
			end)
			if ok and url then headshots[userId] = url; if img.Parent then img.Image = url end end
		end)
	end
	return img
end

local function header(parent, title, sub)
	UIKit.label(parent, title, 22, UIKit.CARD_TEXT, { Position = UDim2.new(0, 16, 0, 8), Size = UDim2.new(1, -70, 0, 26) }, UIKit.HEAD)
	if sub then
		UIKit.label(parent, sub, 14, UIKit.CARD_MUTED, { Position = UDim2.new(0, 16, 0, 34), Size = UDim2.new(1, -70, 0, 18),
			TextTruncate = Enum.TextTruncate.AtEnd }, UIKit.HEAD)
	end
end

local function fmtClock(sec)
	sec = math.max(0, math.floor(sec))
	return ("%d:%02d"):format(sec // 60, sec % 60)
end

-- ============ MESSAGES ============

local convo      -- the open thread's ScrollingFrame (for live appends)
local typingRow

-- a chat bubble: the text measures itself (AutomaticSize), so a wrapped
-- line is never cut off; the width is the text's own, up to maxW
local function bubble(m, maxW)
	local mine = m.from == "me"
	local text = m.text or ""
	local w = math.min(maxW - 26, lineWidth(text, BUBBLE_TEXT) + 6)
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	local b = Instance.new("Frame")
	b.Name = "Bubble"
	b.AnchorPoint = Vector2.new(mine and 1 or 0, 0)
	b.Position = UDim2.new(mine and 1 or 0, mine and -6 or 6, 0, 0)
	b.Size = UDim2.new(0, 0, 0, 0)
	b.AutomaticSize = Enum.AutomaticSize.XY
	b.BackgroundColor3 = mine and UIKit.BLUE or UIKit.CARD
	b.BorderSizePixel = 0
	b.Parent = row
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 14)
	local pad = Instance.new("UIPadding", b)
	pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 13), UDim.new(0, 13), UDim.new(0, 8), UDim.new(0, 9)
	if not mine then
		local st = Instance.new("UIStroke", b)
		st.Color = UIKit.CARD_LINE
		st.Thickness = 1
	end
	local t = UIKit.label(b, text, BUBBLE_TEXT, mine and UIKit.TEXT or UIKit.CARD_TEXT, {
		Size = UDim2.new(0, w, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, BODY)
	return row
end

local function scrollDown()
	if not convo then return end
	task.defer(function()
		if convo and convo.Parent then
			convo.CanvasPosition = Vector2.new(0, math.max(0, convo.AbsoluteCanvasSize.Y - convo.AbsoluteSize.Y))
		end
	end)
end

local function setTyping(on, th)
	if typingRow then typingRow:Destroy(); typingRow = nil end
	if not on or not convo then return end
	typingRow = Instance.new("Frame")
	typingRow.Name = "Typing"
	typingRow.BackgroundTransparency = 1
	typingRow.Size = UDim2.new(1, 0, 0, 34)
	typingRow.LayoutOrder = 1e6
	typingRow.Parent = convo
	local b = Instance.new("Frame")
	b.Position = UDim2.new(0, 6, 0, 0)
	b.Size = UDim2.new(0, 62, 0, 34)
	b.BackgroundColor3 = UIKit.CARD
	b.BorderSizePixel = 0
	b.Parent = typingRow
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 14)
	local dots = {}
	for k = 1, 3 do
		local d = Instance.new("Frame")
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Position = UDim2.new(0, 16 + (k - 1) * 15, 0.5, 0)
		d.Size = UDim2.new(0, 8, 0, 8)
		d.BackgroundColor3 = UIKit.CARD_MUTED
		d.BorderSizePixel = 0
		d.Parent = b
		Instance.new("UICorner", d).CornerRadius = UDim.new(1, 0)
		dots[k] = d
	end
	task.spawn(function()
		local row = typingRow
		while row and row.Parent do
			for k, d in ipairs(dots) do
				d.BackgroundTransparency = 0.6 - 0.6 * math.max(0, math.sin(os.clock() * 6 - k * 0.9))
			end
			task.wait(0.05)
		end
	end)
	scrollDown()
end

local replyPanel     -- the right-hand panel of an open thread
local drawReplies    -- forward

local function send(msg) act:FireServer(msg) end

local function sendTyped(th, box)
	local text = box.Text:gsub("^%s+", ""):gsub("%s+$", "")
	if #text < 2 then return end
	box.Text = ""
	send({ a = "text", id = th.id, text = text })
end

local function itemLine(parent, id, y)
	local it = Items.BY_ID[id]
	if not it then return end
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.new(0, 0, 0, y)
	row.Size = UDim2.new(1, 0, 0, 34)
	row.Parent = parent
	local vpf = Instance.new("ViewportFrame")
	vpf.BackgroundTransparency = 1
	vpf.Size = UDim2.new(0, 34, 0, 34)
	vpf.Parent = row
	Items.icon(id, vpf)
	UIKit.label(row, "+ " .. it.name, 16, UIKit.INK, { Position = UDim2.new(0, 40, 0, 0), Size = UDim2.new(1, -40, 1, 0) }, UIKit.HEAD)
end

drawReplies = function(th)
	if not replyPanel then return end
	for _, c in ipairs(replyPanel:GetChildren()) do
		if not c:IsA("UIPadding") and not c:IsA("UICorner") and not c:IsA("UIStroke") then c:Destroy() end
	end
	if th.status == "offer" and th.offer then
		UIKit.label(replyPanel, "TERM SHEET", 14, UIKit.CARD_MUTED, { Size = UDim2.new(1, 0, 0, 18) }, UIKit.HEAD)
		UIKit.label(replyPanel, th.firm or "", 16, UIKit.INK, { Position = UDim2.new(0, 0, 0, 18), Size = UDim2.new(1, 0, 0, 18),
			TextTruncate = Enum.TextTruncate.AtEnd }, UIKit.HEAD)
		UIKit.outlined(replyPanel, UIKit.money(th.offer.amount), 30, UIKit.GREEN, { Position = UDim2.new(0, 0, 0, 36), Size = UDim2.new(1, 0, 0, 34) })
		if th.offer.item then itemLine(replyPanel, th.offer.item, 70) end
		local take = UIKit.button(replyPanel, "TAKE IT", UIKit.GREEN, { Name = "Take", Position = UDim2.new(0, 0, 1, -94), Size = UDim2.new(1, 0, 0, 46) }, { textSize = 20, silent = true })
		local push = UIKit.button(replyPanel, "PUSH FOR MORE", UIKit.GOLD, { Name = "Push", Position = UDim2.new(0, 0, 1, -44), Size = UDim2.new(0.62, -4, 0, 44) }, { textSize = 16, dark = true })
		local pass = UIKit.button(replyPanel, "PASS", UIKit.MUTED, { Name = "Pass", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 1, -44), Size = UDim2.new(0.38, -4, 0, 44) }, { textSize = 16 })
		take.MouseButton1Click:Connect(function()
			UIKit.sfx("coins")
			if _G.SVCoinStream then pcall(_G.SVCoinStream, take.AbsolutePosition + take.AbsoluteSize / 2, 12) end
			th.status = "busy"; drawReplies(th)
			send({ a = "offer", id = th.id, choice = "take" })
		end)
		push.MouseButton1Click:Connect(function() th.status = "busy"; drawReplies(th); send({ a = "offer", id = th.id, choice = "push" }) end)
		pass.MouseButton1Click:Connect(function() th.status = "busy"; drawReplies(th); send({ a = "offer", id = th.id, choice = "pass" }) end)
		return
	end
	if th.status == "closed" then
		local good = th.outcome == "deal"
		UIKit.label(replyPanel, good and "DEAL DONE" or "CHAT ENDED", 14, UIKit.CARD_MUTED, { Size = UDim2.new(1, 0, 0, 18) }, UIKit.HEAD)
		if good and th.paid then
			UIKit.outlined(replyPanel, "+" .. UIKit.money(th.paid), 30, UIKit.GREEN, { Position = UDim2.new(0, 0, 0, 22), Size = UDim2.new(1, 0, 0, 36) })
		end
		UIKit.label(replyPanel, "Another investor will text you soon. Build more, and you have more to tell them.", 16, UIKit.MUTED_TEXT, {
			Position = UDim2.new(0, 0, 0, good and 64 or 24), Size = UDim2.new(1, 0, 0, 80), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
		}, UIKit.BODY)
		return
	end
	if th.status ~= "wait" or not th.chips then
		UIKit.label(replyPanel, ("Waiting for %s..."):format(th.first or "them"), 16, UIKit.MUTED_TEXT, { Size = UDim2.new(1, 0, 0, 20) }, UIKit.BODY)
		return
	end
	UIKit.label(replyPanel, ("YOUR REPLY  %d of 3"):format(math.min(th.round or 1, 3)), 14, UIKit.MUTED_TEXT, { Size = UDim2.new(1, 0, 0, 18) }, UIKit.HEAD)
	-- v5: the replies are real buttons (paper, outline, lip), 44 px, in the reading font
	local y = 20
	for i, text in ipairs(th.chips) do
		local b, lbl = UIKit.button(replyPanel, text, UIKit.CARD, { Name = "Reply" .. i, Position = UDim2.new(0, 0, 0, y), Size = UDim2.new(1, 0, 0, 44) },
			{ textSize = 16, dark = true, radius = 12, stroke = UIKit.BLUE })
		lbl.TextWrapped = true
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		UIKit.setFont(lbl, BODY)
		lbl.TextSize = 16
		lbl.Position = UDim2.new(0, 10, 0, 0)
		lbl.Size = UDim2.new(1, -20, 1, -5)
		b.MouseButton1Click:Connect(function()
			if th.status ~= "wait" then return end
			th.status = "busy"
			th.chips = nil
			drawReplies(th)
			send({ a = "reply", id = th.id, chip = i })
		end)
		y += 46
	end
	-- or type it yourself (the power move: the model reads it)
	local box = Instance.new("TextBox")
	box.Name = "Type"
	-- pinned to the panel's floor: three chips + the box fit the 204 px inside
	box.Position = UDim2.new(0, 0, 1, -44)
	box.Size = UDim2.new(1, -52, 0, 44)
	box.BackgroundColor3 = UIKit.CARD
	box.ClearTextOnFocus = false
	box.PlaceholderText = "Or type your own..."
	box.PlaceholderColor3 = UIKit.CARD_MUTED
	box.Text = ""
	box.TextColor3 = UIKit.CARD_TEXT
	box.TextSize = 16
	box.FontFace = BODY
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextTruncate = Enum.TextTruncate.AtEnd
	box.Parent = replyPanel
	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 12)
	local bp = Instance.new("UIPadding", box)
	bp.PaddingLeft = UDim.new(0, 10)
	local bs = Instance.new("UIStroke", box)
	bs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bs.Color = UIKit.CARD_LINE
	bs.Thickness = 1.5
	box:GetPropertyChangedSignal("Text"):Connect(function() if #box.Text > 120 then box.Text = box.Text:sub(1, 120) end end)
	local sendBtn = UIKit.button(replyPanel, "", UIKit.BLUE, { Name = "Send", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 1, -44), Size = UDim2.new(0, 46, 0, 44) }, { radius = 12 })
	UIKit.icon(sendBtn, "up", 22, UIKit.TEXT, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -2), Rotation = 90, ZIndex = sendBtn.ZIndex + 2 })
	sendBtn.MouseButton1Click:Connect(function() if th.status == "wait" then sendTyped(th, box) end end)
	box.FocusLost:Connect(function(enter) if enter and th.status == "wait" then sendTyped(th, box) end end)
end

local function openThread(th)
	clear()
	local top = Instance.new("Frame")
	top.Name = "ThreadTop"
	top.BackgroundTransparency = 1
	top.Size = UDim2.new(1, 0, 0, 50)
	top.Parent = content
	local back = Instance.new("TextButton")
	back.Name = "Back"
	back.Text = "‹"
	back.Font = UIKit.HEAD
	back.TextSize = 34
	back.TextColor3 = UIKit.BLUE_DEEP
	back.BackgroundTransparency = 1
	back.Position = UDim2.new(0, 4, 0, 3)
	back.Size = UDim2.new(0, 44, 0, 44)
	back.Parent = top
	back.MouseButton1Click:Connect(function() view.thread = nil; render() end)
	local av = avatar(top, th, 36)
	av.Position = UDim2.new(0, 48, 0, 7)
	UIKit.label(top, th.name or "", 18, UIKit.INK, { Position = UDim2.new(0, 94, 0, 6), Size = UDim2.new(0.6, 0, 0, 22),
		TextTruncate = Enum.TextTruncate.AtEnd }, UIKit.HEAD)
	UIKit.label(top, ("AI investor  ·  %s"):format(th.firm or ""), 14, UIKit.CARD_MUTED, { Position = UDim2.new(0, 94, 0, 27), Size = UDim2.new(0.6, 0, 0, 18),
		TextTruncate = Enum.TextTruncate.AtEnd }, UIKit.HEAD)
	local line = Instance.new("Frame")
	line.Position = UDim2.new(0, 0, 1, -1)
	line.Size = UDim2.new(1, 0, 0, 1)
	line.BackgroundColor3 = UIKit.CARD_LINE
	line.BorderSizePixel = 0
	line.Parent = top

	convo = Instance.new("ScrollingFrame")
	convo.Name = "Convo"
	convo.BackgroundTransparency = 1
	convo.BorderSizePixel = 0
	convo.Position = UDim2.new(0, 4, 0, 54)
	convo.Size = UDim2.new(1, -250, 1, -60)
	convo.ScrollBarThickness = 4
	convo.ScrollBarImageColor3 = UIKit.CARD_MUTED
	convo.AutomaticCanvasSize = Enum.AutomaticSize.Y
	convo.CanvasSize = UDim2.new(0, 0, 0, 0)
	convo.ScrollingDirection = Enum.ScrollingDirection.Y
	convo.Parent = content
	local ll = Instance.new("UIListLayout", convo)
	ll.Padding = UDim.new(0, 6)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	local cp = Instance.new("UIPadding", convo)
	cp.PaddingTop = UDim.new(0, 4)
	cp.PaddingBottom = UDim.new(0, 8)
	local maxW = math.floor((W - SIDE - 18 - 250) * 0.8)
	for i, m in ipairs(th.msgs or {}) do
		local row = bubble(m, maxW)
		row.LayoutOrder = i
		row.Parent = convo
	end
	convo:SetAttribute("MaxW", maxW)
	convo:SetAttribute("Count", #(th.msgs or {}))
	if th.typing then setTyping(true, th) end
	scrollDown()

	replyPanel = Instance.new("Frame")
	replyPanel.Name = "Replies"
	replyPanel.AnchorPoint = Vector2.new(1, 0)
	replyPanel.Position = UDim2.new(1, -8, 0, 56)
	replyPanel.Size = UDim2.new(0, 236, 1, -64)
	replyPanel.BackgroundColor3 = UIKit.CARD
	replyPanel.BorderSizePixel = 0
	replyPanel.Parent = content
	Instance.new("UICorner", replyPanel).CornerRadius = UDim.new(0, 16)
	local rs = Instance.new("UIStroke", replyPanel)
	rs.Color = UIKit.CARD_LINE
	rs.Thickness = 1.5
	local rp = Instance.new("UIPadding", replyPanel)
	rp.PaddingLeft, rp.PaddingRight, rp.PaddingTop, rp.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10), UDim.new(0, 10), UDim.new(0, 10)
	drawReplies(th)
	send({ a = "read" })
end

local function threadList()
	clear()
	convo, replyPanel, typingRow = nil, nil, nil
	header(content, "Texts", "Investors text you about your company. They're AI.")
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.new(0, 8, 0, 60)
	list.Size = UDim2.new(1, -16, 1, -66)
	list.ScrollBarThickness = 4
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.Parent = content
	local ll = Instance.new("UIListLayout", list)
	ll.Padding = UDim.new(0, 6)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	if #order == 0 then
		local hq = player:GetAttribute("HQLevel") or 1
		UIKit.label(list, hq >= 2 and "No texts yet. An investor will reach out soon." or "No texts yet. Investors start texting once your HQ reaches level 2.",
			15, UIKit.CARD_MUTED, { Size = UDim2.new(1, -40, 0, 60), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }, UIKit.HEAD)
		return
	end
	for i, id in ipairs(order) do
		local th = threads[id]
		local row = Instance.new("TextButton")
		row.Name = "Thread" .. id
		row.Text = ""
		row.AutoButtonColor = false
		row.LayoutOrder = i
		row.Size = UDim2.new(1, -6, 0, 60)
		row.BackgroundColor3 = UIKit.CARD
		row.Parent = list
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 14)
		local av = avatar(row, th, 40)
		av.Position = UDim2.new(0, 10, 0.5, -20)
		UIKit.label(row, ("%s  ·  %s"):format(th.name or "", th.firm or ""), 16, UIKit.CARD_TEXT, {
			Position = UDim2.new(0, 60, 0, 9), Size = UDim2.new(1, -120, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd }, UIKit.HEAD)
		local last = th.msgs and th.msgs[#th.msgs]
		local preview = last and ((last.from == "me" and "You: " or "") .. last.text) or ""
		if th.status == "offer" then preview = "Offer: " .. UIKit.money(th.offer and th.offer.amount or 0) .. "  ·  tap to answer" end
		UIKit.label(row, preview, 14, th.status == "offer" and UIKit.darker(UIKit.GREEN, 0.7) or UIKit.CARD_MUTED, {
			Position = UDim2.new(0, 60, 0, 31), Size = UDim2.new(1, -120, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd }, UIKit.HEAD)
		local live = th.status ~= "closed"
		if live then
			local dot = Instance.new("Frame")
			dot.AnchorPoint = Vector2.new(1, 0.5)
			dot.Position = UDim2.new(1, -16, 0.5, 0)
			dot.Size = UDim2.new(0, 12, 0, 12)
			dot.BackgroundColor3 = UIKit.BLUE
			dot.BorderSizePixel = 0
			dot.Parent = row
			Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
		else
			row.BackgroundTransparency = 0.35
		end
		row.MouseButton1Down:Connect(function() UIKit.sfx("tap") end)
		row.MouseButton1Click:Connect(function() view.thread = id; render() end)
	end
end

-- ============ CALLS ============

-- a microphone drawn from frames (Kenney has no mic glyph; no upload needed)
local function micGlyph(parent, off)
	local g = Instance.new("Frame")
	g.BackgroundTransparency = 1
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.Position = UDim2.new(0.5, 0, 0.5, -2)
	g.Size = UDim2.new(0, 28, 0, 30)
	g.ZIndex = parent.ZIndex + 2
	g.Parent = parent
	local function bit(x, y, w, h, round)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0)
		f.Position = UDim2.new(0.5, x, 0, y)
		f.Size = UDim2.new(0, w, 0, h)
		f.BackgroundColor3 = UIKit.TEXT
		f.BorderSizePixel = 0
		f.ZIndex = g.ZIndex
		f.Parent = g
		if round then Instance.new("UICorner", f).CornerRadius = UDim.new(1, 0) end
		return f
	end
	bit(0, 0, 11, 18, true)                       -- the capsule
	local cup = bit(0, 8, 19, 14, false)          -- the U-shaped holder
	cup.BackgroundTransparency = 1
	Instance.new("UICorner", cup).CornerRadius = UDim.new(0, 9)
	local st = Instance.new("UIStroke", cup)
	st.Color = UIKit.TEXT
	st.Thickness = 2.5
	local mask = bit(0, 6, 25, 9, false)          -- hides the holder's top edge
	mask.BackgroundColor3 = parent.BackgroundColor3
	mask.ZIndex = g.ZIndex - 1
	bit(0, 22, 3, 5, false)                       -- stem
	bit(0, 27, 12, 3, true)                       -- base
	if off then
		local slash = bit(0, 13, 34, 3, true)
		slash.AnchorPoint = Vector2.new(0.5, 0.5)
		slash.Rotation = -45
		slash.ZIndex = g.ZIndex + 1
	end
	return g
end

local function roundButton(parent, color, iconKey, rot, label, pos)
	local b = UIKit.button(parent, "", color, { AnchorPoint = Vector2.new(0.5, 0), Position = pos, Size = UDim2.new(0, 60, 0, 60) }, { radius = 30, silent = false })
	if iconKey == "mic" or iconKey == "micOff" then
		micGlyph(b, iconKey == "micOff")
	else
		UIKit.icon(b, iconKey, 28, UIKit.TEXT, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -2), Rotation = rot or 0, ZIndex = b.ZIndex + 2 })
	end
	UIKit.label(parent, label, 14, UIKit.CARD_TEXT, { AnchorPoint = Vector2.new(0.5, 0), Position = pos + UDim2.new(0, 0, 0, 64),
		Size = UDim2.new(0, 90, 0, 18), TextXAlignment = Enum.TextXAlignment.Center }, UIKit.HEAD)
	return b
end

local callTimer   -- the TextLabel an active call screen updates
local callNote    -- { text, t }: why the last call ended, shown in the Calls list for a few seconds

local function callScreen()
	clear()
	local other = call.with and Players:GetPlayerByUserId(call.with)
	local hs = headshot(content, call.with or 0, 92)
	hs.AnchorPoint = Vector2.new(0.5, 0)
	hs.Position = UDim2.new(0.5, 0, 0, 14)
	UIKit.label(content, call.name or (other and other.DisplayName) or "", 22, UIKit.CARD_TEXT, { AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 112), Size = UDim2.new(1, -20, 0, 26), TextXAlignment = Enum.TextXAlignment.Center }, UIKit.HEAD)
	callTimer = UIKit.label(content, "", 16, UIKit.MUTED_TEXT, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 138),
		Size = UDim2.new(1, -20, 0, 20), TextXAlignment = Enum.TextXAlignment.Center }, UIKit.HEAD)
	if call.note then
		UIKit.label(content, call.note, 14, UIKit.RED_DEEP, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 262),
			Size = UDim2.new(1, -20, 0, 18), TextXAlignment = Enum.TextXAlignment.Center }, UIKit.HEAD)
	end
	if call.state == "ringing" then
		local acc = roundButton(content, UIKit.GREEN, "phone", 0, "Accept", UDim2.new(0.5, -60, 0, 170))
		local dec = roundButton(content, UIKit.RED, "cross", 0, "Decline", UDim2.new(0.5, 60, 0, 170))
		acc.MouseButton1Click:Connect(function() send({ a = "answer", accept = true }) end)
		dec.MouseButton1Click:Connect(function() send({ a = "answer", accept = false }) end)
		-- decline AND stop them calling again this session
		local blk = Instance.new("TextButton")
		blk.Name = "Block"
		blk.AnchorPoint = Vector2.new(0.5, 0)
		blk.Position = UDim2.new(0.5, 0, 0, 256)
		blk.Size = UDim2.new(0, 200, 0, 28)
		blk.BackgroundTransparency = 1
		blk.Font = UIKit.HEAD
		blk.TextSize = 14
		blk.TextColor3 = UIKit.darker(UIKit.RED, 0.8)
		blk.Text = "Block this caller"
		blk.Parent = content
		blk.MouseButton1Click:Connect(function() send({ a = "answer", accept = false, block = true }) end)
	else
		local mute = roundButton(content, call.muted and UIKit.GOLD or UIKit.MUTED, call.muted and "micOff" or "mic", 0, call.muted and "Unmute" or "Mute", UDim2.new(0.5, -60, 0, 170))
		local endb = roundButton(content, UIKit.RED, "cross", 0, "End", UDim2.new(0.5, 60, 0, 170))
		mute.MouseButton1Click:Connect(function()
			call.muted = not call.muted
			local mic = player:FindFirstChildOfClass("AudioDeviceInput")
			if mic then pcall(function() mic.Muted = call.muted end) end
			callScreen()
		end)
		endb.MouseButton1Click:Connect(function() send({ a = "hangup" }) end)
	end
end

local function callList()
	clear()
	header(content, "Calls", "Voice-call another founder in this server.")
	local y = 60
	if callNote and os.clock() - callNote.t < 6 then
		local note = UIKit.card(content, { Name = "CallNote", Position = UDim2.new(0, 12, 0, y), Size = UDim2.new(1, -24, 0, 40) }, { radius = 12 })
		UIKit.label(note, callNote.text, 14, UIKit.CARD_TEXT, { Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -24, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd }, UIKit.HEAD)
		y += 48
	end
	if not player:GetAttribute("HasVoice") then
		local warn = UIKit.card(content, { Position = UDim2.new(0, 12, 0, y), Size = UDim2.new(1, -24, 0, 50) }, { radius = 12 })
		UIKit.label(warn, "Voice chat is off for your account, so you can't call. Calls need voice chat (13+, verified).", 14, UIKit.CARD_MUTED, {
			Position = UDim2.new(0, 12, 0, 6), Size = UDim2.new(1, -24, 1, -12), TextWrapped = true }, UIKit.HEAD)
		y += 58
	end
	local list = Instance.new("ScrollingFrame")
	list.Name = "People"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.new(0, 8, 0, y)
	list.Size = UDim2.new(1, -16, 1, -(y + 6))
	list.ScrollBarThickness = 4
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.Parent = content
	local ll = Instance.new("UIListLayout", list)
	ll.Padding = UDim.new(0, 6)
	local others = {}
	for _, p in ipairs(Players:GetPlayers()) do if p ~= player then table.insert(others, p) end end
	if #others == 0 then
		local empty = UIKit.label(list, "Nobody else is in this server right now. When another founder joins, they show up here and you can call them.", 16, UIKit.MUTED_TEXT, {
			Size = UDim2.new(1, -40, 0, 60), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }, UIKit.HEAD)
		local ep = Instance.new("UIPadding", empty)
		ep.PaddingLeft = UDim.new(0, 10)
		return
	end
	for _, p in ipairs(others) do
		local row = UIKit.card(list, { Name = "Person" .. p.UserId, Size = UDim2.new(1, -6, 0, 58) }, { radius = 14 })
		local hs = headshot(row, p.UserId, 40)
		hs.Position = UDim2.new(0, 10, 0.5, -20)
		UIKit.label(row, p.DisplayName, 16, UIKit.CARD_TEXT, { Position = UDim2.new(0, 60, 0, 9), Size = UDim2.new(1, -150, 0, 20),
			TextTruncate = Enum.TextTruncate.AtEnd }, UIKit.HEAD)
		local company = p:GetAttribute("Company")
		local busy = p:GetAttribute("InCall") ~= nil
		local voice = p:GetAttribute("HasVoice") == true
		local sub = busy and "On a call" or (not voice and "No voice chat") or ((company and company ~= "") and company or "Founder")
		UIKit.label(row, sub, 14, UIKit.CARD_MUTED, { Position = UDim2.new(0, 60, 0, 30), Size = UDim2.new(1, -150, 0, 18),
			TextTruncate = Enum.TextTruncate.AtEnd }, UIKit.HEAD)
		local can = voice and not busy and player:GetAttribute("HasVoice") == true and not call.state
		local b = UIKit.button(row, "", can and UIKit.GREEN or UIKit.MUTED, { Name = "Call", AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0, 72, 0, 44) }, { radius = 12 })
		UIKit.icon(b, "phone", 22, UIKit.TEXT, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -2), ZIndex = b.ZIndex + 2 })
		b.MouseButton1Click:Connect(function()
			if not can then UIKit.sfx("thunk", 0.8) return end
			send({ a = "call", to = p.UserId })
		end)
	end
end

-- ============ RENDER ============

render = function()
	for id, a in pairs(apps) do a.ring.Thickness = (view.app == id) and 3 or 0 end
	if call.state and (view.app == "calls") then callScreen() return end
	if view.app == "messages" then
		local th = view.thread and threads[view.thread]
		if th then openThread(th) else threadList() end
	else
		callList()
	end
end

local function setOpen(v)
	if v then UIKit.solo(gui) end
	gui.Enabled = v
	if v then
		bezel.Position = place(0.5, 90)
		TweenService:Create(bezel, TweenInfo.new(0.28, Enum.EasingStyle.Quint), { Position = place(0.5, 26) }):Play()
		render()
	end
end

-- ============ NOTIFICATIONS (phone closed) ============

local notify = Instance.new("ScreenGui")
notify.Name = "PhoneNotify"
notify.ResetOnSpawn = false
notify.IgnoreGuiInset = true
notify.DisplayOrder = 16
UIKit.safe(notify)
notify.Parent = player.PlayerGui

-- v3.2.1: centred in THIS gui's own space. The old version mixed screen
-- coordinates (other guis' AbsolutePosition, the camera's ViewportSize) with
-- this gui's safe-area space, and on a real phone (notch inset) the banner
-- landed on top of the rail, 240 px wide, truncating every text. The rail
-- (left, ~90) and the quest column (right, 262) both live in safe-area guis
-- too, so a centred card up to W - 540 wide clears both.
-- v4.2: the rare-hire card and these share the top lane (Notify), one at a
-- time, so they no longer dodge each other (the v3.6 RevealShowing shuffle)
-- v5: in the gap between the rail and the goal card (UIKit.hudGap). Centred on
-- the screen, a phone's 280-wide banner ran 11 px into the goal card.
local function centreOn(frame, maxW, minW, h, y)
	frame.AnchorPoint = Vector2.new(0.5, 0)
	local cx, w = UIKit.hudGap(maxW)
	frame.Size = UDim2.new(0, math.max(minW, w), 0, h)
	-- v4.9: 96 was a guess that the top of the screen was empty. It is not.
	frame.Position = UDim2.new(0, cx - notify.AbsolutePosition.X, 0, y or Notify.topY(96))
	if not y then Notify.followTop(frame, 96) end
end
local function atY(frame, y) return UDim2.new(0, frame.Position.X.Offset, 0, y) end

local banner = Instance.new("TextButton")
banner.Name = "Banner"
banner.Text = ""
banner.AutoButtonColor = false
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Size = UDim2.new(0, 360, 0, 64)
banner.Position = UDim2.new(0.5, 0, 0, -80)
banner.BackgroundColor3 = UIKit.CARD
banner.Visible = false
banner.Parent = notify
Instance.new("UICorner", banner).CornerRadius = UDim.new(0, 18)
local bnst = Instance.new("UIStroke", banner)
bnst.Color = UIKit.CARD_LINE
bnst.Thickness = 2
bnst.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
UIKit.lip(banner, 4)          -- v5: the same sticker edge as every other HUD card
local bnAvatarHolder = Instance.new("Frame")
bnAvatarHolder.BackgroundTransparency = 1
bnAvatarHolder.Position = UDim2.new(0, 12, 0.5, -20)
bnAvatarHolder.Size = UDim2.new(0, 40, 0, 40)
bnAvatarHolder.Parent = banner
local bnTitle = UIKit.label(banner, "", 16, UIKit.INK, { Position = UDim2.new(0, 62, 0, 10), Size = UDim2.new(1, -74, 0, 20),
	TextTruncate = Enum.TextTruncate.AtEnd }, UIKit.HEAD)
local bnText = UIKit.label(banner, "", 14, UIKit.CARD_MUTED, { Position = UDim2.new(0, 62, 0, 32), Size = UDim2.new(1, -74, 0, 36),
	TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }, BODY)
local bannerSerial, bannerThread, bannerDone = 0, nil, nil
local function showBannerNow(th, text, done)
	bannerSerial += 1
	local mine = bannerSerial
	bannerDone = done
	local isCall = th and th.call
	if isCall then th = nil end
	bannerThread = th and th.id
	for _, c in ipairs(bnAvatarHolder:GetChildren()) do c:Destroy() end
	if th then avatar(bnAvatarHolder, th, 40) end
	local tx = th and 62 or 18            -- no sender, no empty avatar gap
	bnTitle.Position = UDim2.new(0, tx, 0, 10)
	bnTitle.Size = UDim2.new(1, -tx - 12, 0, 20)
	bnText.Position = UDim2.new(0, tx, 0, 32)
	bnText.Size = UDim2.new(1, -tx - 12, 0, 36)       -- two lines: the opener is a sentence
	bnTitle.Text = isCall and "Call" or (th and ("%s  ·  %s"):format(th.first or th.name or "", th.firm or "") or "Texts")
	bnText.Text = text or ""
	centreOn(banner, 380, 280, 78, -90)
	banner.Visible = true
	TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = atY(banner, 96) }):Play()
	UIKit.sfx("ding", 1.45, 0.45)
	task.delay(0.16, function() UIKit.sfx("ding", 1.7, 0.4) end)
	task.delay(7, function()
		if bannerSerial ~= mine then return end
		local tw = TweenService:Create(banner, TweenInfo.new(0.25), { Position = atY(banner, -90) })
		tw:Play()
		tw.Completed:Wait()
		if bannerSerial == mine then banner.Visible = false end
		if bannerDone == done then bannerDone = nil; done() end
	end)
end
-- v4.2: every banner asks the director; only a thread's FIRST text and a term
-- sheet raise one (a reply used to raise two banners two seconds apart). The
-- rest are counted by the server on the PHONE button (PhoneUnread).
local function showBanner(th, text, priority)
	Notify.show({ lane = "top", priority = priority or 3, key = "phone",
		close = function() bannerSerial += 1; banner.Visible = false end,
		open = function(done) showBannerNow(th, text, done) end })
end
banner.MouseButton1Click:Connect(function()
	banner.Visible = false
	if bannerDone then local f = bannerDone; bannerDone = nil; f() end
	view.app = "messages"
	view.thread = bannerThread
	setOpen(true)
end)

-- the ringing card, and the pill while you talk with the phone closed
local ringCard = UIKit.card(notify, { Name = "Incoming", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 96),
	Size = UDim2.new(0, 360, 0, 80), Visible = false }, { radius = 18, strokeWidth = 3, stroke = UIKit.GREEN })
local ringHolder = Instance.new("Frame")
ringHolder.BackgroundTransparency = 1
ringHolder.Position = UDim2.new(0, 12, 0.5, -24)
ringHolder.Size = UDim2.new(0, 48, 0, 48)
ringHolder.Parent = ringCard
local ringText = UIKit.label(ringCard, "", 16, UIKit.CARD_TEXT, { Position = UDim2.new(0, 70, 0, 12), Size = UDim2.new(1, -200, 0, 22),
	TextTruncate = Enum.TextTruncate.AtEnd }, UIKit.HEAD)
UIKit.label(ringCard, "is calling you", 14, UIKit.CARD_MUTED, { Position = UDim2.new(0, 70, 0, 36), Size = UDim2.new(1, -200, 0, 18) }, UIKit.HEAD)
local ringAccept = UIKit.button(ringCard, "", UIKit.GREEN, { Name = "Accept", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -66, 0.5, 0), Size = UDim2.new(0, 52, 0, 52) }, { radius = 26 })
UIKit.icon(ringAccept, "phone", 24, UIKit.TEXT, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -2), ZIndex = ringAccept.ZIndex + 2 })
local ringDecline = UIKit.button(ringCard, "", UIKit.RED, { Name = "Decline", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0, 52, 0, 52) }, { radius = 26 })
UIKit.icon(ringDecline, "cross", 22, UIKit.TEXT, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -2), ZIndex = ringDecline.ZIndex + 2 })
ringAccept.MouseButton1Click:Connect(function() send({ a = "answer", accept = true }) end)
ringDecline.MouseButton1Click:Connect(function() send({ a = "answer", accept = false }) end)
-- the small print under the name: decline and block them for this session
local ringBlock = Instance.new("TextButton")
ringBlock.Name = "Block"
ringBlock.Position = UDim2.new(0, 70, 0, 54)
ringBlock.Size = UDim2.new(0, 110, 0, 20)
ringBlock.BackgroundTransparency = 1
ringBlock.Font = UIKit.HEAD
ringBlock.TextSize = 14
ringBlock.TextXAlignment = Enum.TextXAlignment.Left
ringBlock.TextColor3 = UIKit.darker(UIKit.RED, 0.8)
ringBlock.Text = "Block caller"
ringBlock.Parent = ringCard
ringBlock.MouseButton1Click:Connect(function() send({ a = "answer", accept = false, block = true }) end)

local pill = UIKit.card(notify, { Name = "CallPill", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 96),
	Size = UDim2.new(0, 250, 0, 50), Visible = false }, { radius = 999, strokeWidth = 2, stroke = UIKit.GREEN })
local pillDot = Instance.new("Frame")
pillDot.Position = UDim2.new(0, 16, 0.5, -6)
pillDot.Size = UDim2.new(0, 12, 0, 12)
pillDot.BackgroundColor3 = UIKit.GREEN
pillDot.BorderSizePixel = 0
pillDot.Parent = pill
Instance.new("UICorner", pillDot).CornerRadius = UDim.new(1, 0)
local pillText = UIKit.label(pill, "", 16, UIKit.CARD_TEXT, { Position = UDim2.new(0, 36, 0, 0), Size = UDim2.new(1, -110, 1, 0),
	TextTruncate = Enum.TextTruncate.AtEnd }, UIKit.HEAD)
local pillEnd = UIKit.button(pill, "END", UIKit.RED, { Name = "End", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.new(0, 64, 0, 40) }, { textSize = 16, radius = 999 })
pillEnd.MouseButton1Click:Connect(function() send({ a = "hangup" }) end)
pill.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
		view.app = "calls"; setOpen(true)
	end
end)

-- ============ VOICE: the phone line ============
-- their microphone -> a fader -> your speakers, only while the call is live.
-- Near each other the line fades out: spatial voice already carries it.
local line = {}
local function unwire()
	for _, x in ipairs(line) do if x and x.Parent then x:Destroy() end end
	line = {}
end
local function wire(src, dst, parent)
	local w = Instance.new("Wire")
	w.SourceInstance = src
	w.TargetInstance = dst
	w.Parent = parent
	return w
end
local function wireTo(input)
	unwire()
	if not input then return false end
	local fader = Instance.new("AudioFader")
	fader.Name = "PhoneLine"
	fader.Volume = 1
	fader.Parent = SoundService
	local out = Instance.new("AudioDeviceOutput")
	out.Name = "PhoneSpeaker"
	pcall(function() out.Player = player end)
	out.Parent = SoundService
	line = { fader, out, wire(input, fader, fader), wire(fader, out, fader) }
	return true
end
_G.SVPhoneWire = wireTo       -- Studio test hook (voice cannot run in Studio)

--[[ WHY THE CALL CONNECTED AND STAYED SILENT.

	The old code asked for the other player's AudioDeviceInput once, waited
	five seconds, and gave up for the rest of the call. That object is created
	by the engine when a player's voice session comes up -- which is not
	necessarily before the call connects, and which can happen later if they
	turn voice on mid-session. One missed window and the line was dead for
	good, with the timer happily counting.

	So it now keeps looking for as long as the call is up, and wires the moment
	the input appears.

	The message also tells you WHICH precondition failed, because "their voice
	isn't coming through" is true of every cause and useful for none:

	  no input for EITHER of you  -> voice is not on for this experience, or
	                                 your own account cannot use it
	  input for you, not for them -> their account has no voice here

	The engine parents exactly one AudioDeviceInput per player to the Player
	object whenever VoiceChatService.EnableDefaultVoice is true, so its absence
	is a real signal and not a timing quirk once the call has been up a while. ]]
local voiceWatch = 0

local function voiceNote(other)
	local mine = player:FindFirstChildOfClass("AudioDeviceInput")
	if not mine then
		return "Voice is off for this experience, or for your account"
	end
	return (other and other.DisplayName or "They") .. " has no microphone here"
end

local function watchVoice(other)
	voiceWatch += 1
	local token = voiceWatch
	task.spawn(function()
		local waited = 0
		while token == voiceWatch and call.state == "connected" and other and other.Parent do
			local input = other:FindFirstChildOfClass("AudioDeviceInput")
			if input and wireTo(input) then
				call.note = nil
				if gui.Enabled then render() end
				return
			end
			-- say nothing for the first couple of seconds: a late input is
			-- normal and an instant error message is just noise
			if waited > 2 and call.note == nil then
				call.note = voiceNote(other)
				if gui.Enabled then render() end
			end
			task.wait(0.5)
			waited += 0.5
		end
	end)
end
task.spawn(function()
	while true do
		task.wait(0.4)
		local fader = line[1]
		if fader and fader.Parent and call.with then
			local other = Players:GetPlayerByUserId(call.with)
			local a = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local b = other and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
			local near = a and b and (a.Position - b.Position).Magnitude < 40
			local want = near and 0 or 1
			if math.abs(fader.Volume - want) > 0.01 then TweenService:Create(fader, TweenInfo.new(0.6), { Volume = want }):Play() end
		end
	end
end)

-- a ring that keeps going until you answer (engine sounds, two quick tones)
local ringing = false
local function ring(on)
	ringing = on
	if not on then return end
	task.spawn(function()
		while ringing do
			UIKit.sfx("ding", 1.2, 0.5); task.wait(0.18); UIKit.sfx("ding", 1.5, 0.5)
			task.wait(1.4)
		end
	end)
end

-- ============ EVENTS ============

local function upsert(t)
	local th = threads[t.id] or {}
	for k, v in pairs(t) do th[k] = v end
	th.msgs = th.msgs or {}
	threads[t.id] = th
	local idx = table.find(order, t.id)
	if idx then table.remove(order, idx) end
	table.insert(order, 1, t.id)
	return th
end

local function viewing(id) return gui.Enabled and view.app == "messages" and view.thread == id end

-- v4.2: an incoming call is danger (P0) in the top lane; the call pill sits
-- beside the PHONE button instead of in the top strip
local ringDone
local function showRing(e)
	Notify.show({ lane = "top", priority = 0, key = "ring",
		close = function() ringCard.Visible = false end,
		valid = function() return call.state == "ringing" end,
		open = function(done)
			ringDone = done
			for _, c in ipairs(ringHolder:GetChildren()) do c:Destroy() end
			headshot(ringHolder, e.with or 0, 48)
			ringText.Text = e.name or "Someone"
			centreOn(ringCard, 380, 320, 80, 96)
			ringCard.Visible = true
		end })
end
local function ringOver()
	ringCard.Visible = false
	if ringDone then local f = ringDone; ringDone = nil; f() end
end
local function placePill()
	local a = railBtn.AbsolutePosition - notify.AbsolutePosition
	pill.AnchorPoint = Vector2.new(0, 0.5)
	pill.Size = UDim2.new(0, 250, 0, 50)
	pill.Position = UDim2.new(0, a.X + railBtn.AbsoluteSize.X + 10, 0, a.Y + railBtn.AbsoluteSize.Y / 2)
end

ev.OnClientEvent:Connect(function(e)
	if type(e) ~= "table" then return end
	if e.kind == "thread" then
		upsert(e.thread)
		if gui.Enabled and view.app == "messages" and not view.thread then render() end
	elseif e.kind == "msg" then
		local th = threads[e.id] or upsert({ id = e.id, name = e.name, first = e.name, firm = e.firm, color = e.color, system = e.system, msgs = {} })
		table.insert(th.msgs, e.msg)
		if viewing(e.id) and convo then
			local row = bubble(e.msg, convo:GetAttribute("MaxW") or 240)
			row.LayoutOrder = #th.msgs
			row.Parent = convo
			if e.msg.from == "them" then UIKit.sfx("tap", 1.3, 0.3) end
			scrollDown()
			send({ a = "read" })
		elseif e.notify and not th.bannered then
			th.bannered = true
			showBanner(th, e.msg.text, 3)
		end
		if gui.Enabled and view.app == "messages" and not view.thread then render() end
	elseif e.kind == "typing" then
		local th = threads[e.id]
		if th then th.typing = e.on end
		if viewing(e.id) then setTyping(e.on, th) end
	elseif e.kind == "chips" then
		local th = threads[e.id]
		if th then th.chips = e.chips; th.round = e.round; th.status = "wait" end
		if viewing(e.id) then drawReplies(th) end
	elseif e.kind == "offer" then
		local th = threads[e.id]
		if th then th.status = "offer"; th.offer = { amount = e.amount, item = e.item }; th.chips = nil end
		if viewing(e.id) then drawReplies(th) elseif th then showBanner(th, "Sent you a term sheet: " .. UIKit.money(e.amount), 2) end
	elseif e.kind == "paid" then
		local th = threads[e.id]
		if th then th.paid = e.amount end
	elseif e.kind == "closed" then
		local th = threads[e.id]
		if th then th.status = "closed"; th.outcome = e.reason; th.chips = nil; th.typing = false end
		if viewing(e.id) then setTyping(false); drawReplies(th) end
	elseif e.kind == "call" then
		local prev = call.state
		if e.state == "ended" then
			call = {}
			ring(false)
			unwire()
			ringOver()
			pill.Visible = false
			if e.reason and e.reason ~= "" then
				if gui.Enabled and view.app == "calls" then
					callNote = { text = e.reason, t = os.clock() }
				else
					showBanner({ call = true }, e.reason, 3)
				end
			end
			if gui.Enabled and view.app == "calls" then render() end
			return
		end
		call.state, call.with, call.name, call.id = e.state, e.with, e.name, e.id
		refreshBadge()
		if e.state == "ringing" then
			ring(true)
			if gui.Enabled then
				view.app = "calls"; render()
			else
				showRing(e)
			end
		elseif e.state == "calling" then
			if gui.Enabled then view.app = "calls"; render() end
		elseif e.state == "connected" then
			ring(false)
			ringOver()
			call.since = player:GetAttribute("CallSince") or workspace:GetServerTimeNow()
			local other = Players:GetPlayerByUserId(e.with or 0)
			local input = other and other:FindFirstChildOfClass("AudioDeviceInput")
			call.note = nil
			if not wireTo(input) then
				-- not there yet, or not there at all: keep looking for the
				-- life of the call rather than giving up after one glance
				watchVoice(other)
			end
			UIKit.sfx("ding", 1.0, 0.5)
			if gui.Enabled then view.app = "calls"; render() end
		end
		if prev ~= call.state and not gui.Enabled and call.state == "connected" then
			placePill()
			pill.Visible = true
		end
	end
end)

-- live clocks: the status bar, the call timer, the call pill
RunService.Heartbeat:Connect(function()
	if gui.Enabled then clock.Text = os.date("%H:%M") end
	local t = call.since and fmtClock(workspace:GetServerTimeNow() - call.since)
	if callTimer and callTimer.Parent then
		callTimer.Text = (call.state == "connected" and t) or (call.state == "calling" and "Calling...") or (call.state == "ringing" and "Incoming call") or ""
	end
	if pill.Visible then
		if call.state ~= "connected" or gui.Enabled then pill.Visible = false
		else pillText.Text = ("%s  %s"):format(call.name or "", t or "") end
	elseif call.state == "connected" and not gui.Enabled then
		placePill()
		pill.Visible = true
	end
end)

-- ============ THE BADGE, THE BUTTON ============

refreshBadge = function()
	local unread = player:GetAttribute("PhoneUnread") or 0
	-- one verb at a time: the phone arrives with the first investor (HQ 2), or
	-- at once for a returning founder; the daily only counts once it is open
	local open = player:GetAttribute("Shipped") == true and ((player:GetAttribute("HQLevel") or 1) >= 2
		or player:GetAttribute("Returning") == true or unread > 0 or call.state ~= nil)
	railBtn.Visible = open
	-- v5: the badge means one thing, "an investor texted" (the daily gift has its own tile)
	railBadge.Visible = unread > 0 and not gui.Enabled
	railBadgeText.Text = unread > 9 and "9+" or tostring(unread)
	apps.messages.dot.Visible = unread > 0
	apps.messages.dotText.Text = unread > 9 and "9+" or tostring(unread)
	apps.calls.dot.Visible = false
end
for _, a in ipairs({ "PhoneUnread", "DailyReady", "Shipped", "HQLevel", "Returning" }) do player:GetAttributeChangedSignal(a):Connect(refreshBadge) end
gui:GetPropertyChangedSignal("Enabled"):Connect(refreshBadge)
refreshBadge()

railBtn.MouseButton1Click:Connect(function()
	if not gui.Enabled then
		-- open where it matters: the live chat, then an incoming call, then the list
		if call.state then view.app = "calls"
		elseif view.app == "messages" and not view.thread then
			for _, id in ipairs(order) do
				local th = threads[id]
				if th and th.status ~= "closed" then view.thread = id break end
			end
		end
	end
	setOpen(not gui.Enabled)
end)
closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Q and gui.Enabled then setOpen(false) end
end)
-- the people list stays current while it is open
Players.PlayerAdded:Connect(function() if gui.Enabled and view.app == "calls" and not call.state then render() end end)
Players.PlayerRemoving:Connect(function() if gui.Enabled and view.app == "calls" and not call.state then render() end end)

-- tell the server whether this account can use voice at all
task.spawn(function()
	local ok, enabled = pcall(function() return VoiceChatService:IsVoiceEnabledForUserIdAsync(player.UserId) end)
	send({ a = "voice", ok = ok and enabled == true })
end)

-- v5: the rail tile shows when this menu is open
UIKit.bindRail(railBtn, gui)
