--[[ FeedbackClient (the player loop, 9 Oct 2026): the TELL US tile and its box.

	The quiet last tile on the rail, shown once you have shipped (a player who has
	not played yet has nothing to tell us). It opens one small panel: a question,
	a 300-character box with a counter, SEND. The server (Feedback.lua) stores it
	and answers with one line; nothing typed here is shown to any other player.
	PINK because it is the one accent no other tile uses (UIKit.railButton). ]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local remotes = ReplicatedStorage:WaitForChild("SVRemotes")
local send = remotes:WaitForChild("SendFeedback", 30)
local reply = remotes:WaitForChild("FeedbackReply", 30)
if not (send and reply) then return end   -- an older server without the box

local MAX = 300

-- ============ the tile ============
local railBtn = UIKit.railButton("info", "TELL US", UIKit.PINK, {
	Name = "FeedbackButton", LayoutOrder = 99, Size = UDim2.new(0, UIKit.RAIL, 0, UIKit.RAIL), Visible = false,
}, { iconSize = 26 })
local function refreshVisible() railBtn.Visible = player:GetAttribute("Shipped") == true end
player:GetAttributeChangedSignal("Shipped"):Connect(refreshVisible)
refreshVisible()

-- ============ the panel ============
local gui = Instance.new("ScreenGui")
gui.Name = "Feedback"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 12
gui.Enabled = false
UIKit.safe(gui)
gui.Parent = player:WaitForChild("PlayerGui")

local PW, PH = 460, 300
local panel, body, closeBtn = UIKit.menu(gui, "TELL US", UIKit.PINK, {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 24, 0.5, 0), Size = UDim2.new(0, PW, 0, PH),
}, { headerHeight = 44 })
body.Position = UDim2.new(0, 14, 0, 54)
body.Size = UDim2.new(1, -28, 1, -66)
local fit = Instance.new("UIScale")
fit.Parent = panel
UIKit.fitMenu(panel, PW, PH, fit)

UIKit.label(body, "A bug, an idea, something that annoyed you? We read every one.", 16, UIKit.MUTED_TEXT, {
	Name = "Ask", Size = UDim2.new(1, 0, 0, 40), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
}, UIKit.BODY)

local box = Instance.new("TextBox")
box.Name = "Message"
box.Position = UDim2.new(0, 0, 0, 44)
box.Size = UDim2.new(1, 0, 1, -100)
box.BackgroundColor3 = UIKit.CARD
box.PlaceholderText = "Type here..."
box.PlaceholderColor3 = UIKit.CARD_MUTED
box.Text = ""
box.TextColor3 = UIKit.CARD_TEXT
box.TextSize = 18
box.FontFace = UIKit.BODY
box.TextWrapped = true
box.MultiLine = true
box.ClearTextOnFocus = false
box.TextXAlignment = Enum.TextXAlignment.Left
box.TextYAlignment = Enum.TextYAlignment.Top
box.Parent = body
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, UIKit.RADIUS.md)
corner.Parent = box
local boxStroke = Instance.new("UIStroke")
boxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
boxStroke.Color = UIKit.CARD_LINE
boxStroke.Thickness = 2
boxStroke.Parent = box
local pad = Instance.new("UIPadding")
pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop = UDim.new(0, 12), UDim.new(0, 12), UDim.new(0, 8)
pad.Parent = box
box.Focused:Connect(function() boxStroke.Color = UIKit.PINK end)
box.FocusLost:Connect(function() boxStroke.Color = UIKit.CARD_LINE end)

local count = UIKit.label(body, "0/" .. MAX, 14, UIKit.MUTED_TEXT, {
	Name = "Count", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -8), Size = UDim2.new(0.5, 0, 0, 20),
	TextXAlignment = Enum.TextXAlignment.Left,
}, UIKit.BODY)

local sendBtn = UIKit.button(body, "SEND", UIKit.PINK, {
	Name = "Send", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.new(0, 120, 0, 44),
}, { textSize = 18 })

-- the counter, and a hard stop at 300 characters (the server cuts there too)
box:GetPropertyChangedSignal("Text"):Connect(function()
	local n = utf8.len(box.Text) or #box.Text
	if n > MAX then
		local cut = utf8.offset(box.Text, MAX + 1)
		if cut then box.Text = box.Text:sub(1, cut - 1) end
		n = MAX
	end
	count.Text = ("%d/%d"):format(n, MAX)
end)

local waiting = false
sendBtn.MouseButton1Click:Connect(function()
	if waiting then return end
	waiting = true
	sendBtn.Text = "..."
	send:FireServer(box.Text)
end)

local function setOpen(v)
	if v then UIKit.solo(gui) end
	gui.Enabled = v
	if v then
		task.defer(function() box:CaptureFocus() end)
	end
end

reply.OnClientEvent:Connect(function(ok, line)
	waiting = false
	sendBtn.Text = "SEND"
	count.Text = tostring(line)
	if ok then
		box.Text = ""            -- this resets the counter, so the thank-you goes back on after it
		count.Text = tostring(line)
		task.delay(2.5, function() if gui.Enabled then setOpen(false) end end)
	end
end)

railBtn.MouseButton1Click:Connect(function() setOpen(not gui.Enabled) end)
if closeBtn then closeBtn.MouseButton1Click:Connect(function() setOpen(false) end) end
UIKit.bindRail(railBtn, gui)
