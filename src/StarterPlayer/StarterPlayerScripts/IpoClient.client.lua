--[[ IpoClient (v4.3): the GO PUBLIC button and the bell.

At HQ 5 the company goes public before it can spin off (Journey: the HQ 5
task). The server says when (attribute CanGoPublic) and does the listing
(SVRemotes.GoPublic); this draws the big gold button at the top of the right
column and, on the server's "ipo" celebration, the moment itself: the bell,
the ticker, the money raised, confetti. One moment per company, so it is loud. ]]
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local UIKit = require(RS:WaitForChild("UIKit"))
local Notify = require(RS:WaitForChild("Notify"))
local remotes = RS:WaitForChild("SVRemotes")
local goRemote = remotes:WaitForChild("GoPublic")
local celebrate = remotes:WaitForChild("Celebrate", 30)

local BELL = "rbxassetid://9113584010"   -- PSE "Brass Hand Bell 4" (licensed, pre-moderated)

-- ============ THE BUTTON ============
local col = UIKit.column()
local btn = UIKit.button(col, "", UIKit.GOLD, {
	Name = "GoPublic", LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 96), Visible = false,
}, { textSize = 26 })
UIKit.outlined(btn, "GO PUBLIC!", 30, UIKit.TEXT, {
	Position = UDim2.new(0, 12, 0, 10), Size = UDim2.new(1, -24, 0, 36), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = btn.ZIndex + 2,
})
UIKit.label(btn, "Ring the bell on the Valley Exchange", 14, UIKit.INK, {
	Position = UDim2.new(0, 12, 0, 52), Size = UDim2.new(1, -24, 0, 20), TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex = btn.ZIndex + 2,
}, UIKit.HEAD)
local pulse = Instance.new("UIScale", btn)
local busy = false
btn.Activated:Connect(function()
	if busy then return end
	busy = true
	goRemote:FireServer()
	task.delay(2, function() busy = false end)
end)
local function refresh()
	btn.Visible = player:GetAttribute("CanGoPublic") == true
end
player:GetAttributeChangedSignal("CanGoPublic"):Connect(refresh)
refresh()
task.spawn(function()
	while true do
		if btn.Visible then
			TweenService:Create(pulse, TweenInfo.new(0.45, Enum.EasingStyle.Sine), { Scale = 1.06 }):Play()
			task.wait(0.45)
			TweenService:Create(pulse, TweenInfo.new(0.45, Enum.EasingStyle.Sine), { Scale = 1 }):Play()
		end
		task.wait(0.5)
	end
end)

-- ============ THE MOMENT ============
local gui = Instance.new("ScreenGui")
gui.Name = "IpoMoment"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 40
gui.Parent = player:WaitForChild("PlayerGui")

local function confetti(parent)
	local colours = { UIKit.GOLD, UIKit.GREEN, UIKit.BLUE, UIKit.ORANGE, Color3.fromRGB(236, 120, 170) }
	for i = 1, 70 do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = colours[(i % #colours) + 1]
		f.Size = UDim2.fromOffset(math.random(6, 12), math.random(8, 16))
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.new(math.random(), 0, 0, -20)
		f.Rotation = math.random(0, 180)
		f.ZIndex = 20
		f.Parent = parent
		TweenService:Create(f, TweenInfo.new(math.random(18, 30) / 10, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(f.Position.X.Scale + (math.random() - 0.5) * 0.2, 0, 1.1, 0),
			Rotation = f.Rotation + math.random(-360, 360),
		}):Play()
		task.delay(3.2, function() f:Destroy() end)
	end
end

local function moment(e, done)
	local s = Instance.new("Sound")
	s.SoundId = BELL
	s.Volume = 0.9
	s.Parent = SoundService
	s:Play()
	task.delay(6, function() s:Destroy() end)
	local shade = Instance.new("Frame")
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = UIKit.INK
	shade.BackgroundTransparency = 1
	shade.Parent = gui
	TweenService:Create(shade, TweenInfo.new(0.3), { BackgroundTransparency = 0.45 }):Play()
	local card = UIKit.card(shade, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.new(0, 460, 0, 250) }, { radius = 22, strokeWidth = 4 })
	local st = card:FindFirstChildOfClass("UIStroke")
	if st then st.Color = UIKit.GOLD end
	local sc = Instance.new("UIScale", card)
	sc.Scale = 0.4
	TweenService:Create(sc, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	UIKit.label(card, "DING DING DING!", 18, UIKit.CARD_MUTED, { Position = UDim2.new(0, 0, 0, 18), Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Center }, UIKit.HEAD)
	UIKit.label(card, ("%s IS PUBLIC!"):format(string.upper(e.name or "YOUR COMPANY")), 30, UIKit.INK, {
		Position = UDim2.new(0, 16, 0, 46), Size = UDim2.new(1, -32, 0, 40), TextXAlignment = Enum.TextXAlignment.Center,
		TextScaled = true }, UIKit.HEAD)
	local tick = Instance.new("Frame")
	tick.AnchorPoint = Vector2.new(0.5, 0)
	tick.Position = UDim2.new(0.5, 0, 0, 96)
	tick.Size = UDim2.new(0, 170, 0, 40)
	tick.BackgroundColor3 = UIKit.INK
	tick.Parent = card
	Instance.new("UICorner", tick).CornerRadius = UDim.new(1, 0)
	UIKit.label(tick, tostring(e.ticker or "?"), 24, UIKit.GOLD, { Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center }, UIKit.HEAD)
	UIKit.outlined(card, ("+%s raised"):format(UIKit.money(e.raise or 0)), 30, UIKit.MONEY, {
		Position = UDim2.new(0, 0, 0, 146), Size = UDim2.new(1, 0, 0, 38), TextXAlignment = Enum.TextXAlignment.Center })
	UIKit.label(card, "Next: SPIN OFF a new company for more money, forever.", 16, UIKit.INK_SOFT, {
		Position = UDim2.new(0, 20, 1, -46), Size = UDim2.new(1, -40, 0, 36), TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center }, UIKit.BODY)
	confetti(gui)
	task.delay(1.2, function() confetti(gui) end)
	UIKit.sfx("levelup", 1, 0.6)
	task.delay(5.5, function()
		TweenService:Create(shade, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(sc, TweenInfo.new(0.3), { Scale = 0.8 }):Play()
		task.delay(0.36, function()
			shade:Destroy()
			done()
		end)
	end)
end

if celebrate then
	celebrate.OnClientEvent:Connect(function(e)
		if type(e) ~= "table" or e.kind ~= "ipo" then return end
		Notify.show({ lane = "centre", priority = 0, key = "ipo", open = function(done) moment(e, done) end })
	end)
end
