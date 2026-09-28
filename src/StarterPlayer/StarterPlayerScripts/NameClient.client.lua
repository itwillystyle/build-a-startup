--[[
	NameClient -- LocalScript in StarterPlayer -> StarterPlayerScripts.

	"Name your company." Asked once, right after your first hire. The name goes
	on the plate above your door and on your building. Server filters it; a
	refused name comes back as a message here and the box stays open.

	v3.1 (25 Sep reviews):
	  - light menu, like every other menu (the dark gold-rim box was the anti-reference)
	  - LATER tells the server, which stops waiting for a name: it used to close
	    only on the client, and the lot stayed shut for ~26 s with nothing to do
	  - no keyboard grab on open (CaptureFocus sent W/A/S/D into the box)
	  - closes itself after 25 s, so it can never block the game
	  - plain words: SAVE, not "FOUND IT"; no "Valley Exchange" (never introduced)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("SVRemotes")
local askName = remotes:WaitForChild("AskName")
local setName = remotes:WaitForChild("SetName")
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local Notify = require(ReplicatedStorage:WaitForChild("Notify"))

local HINT = "It goes on your building's sign."

local gui = Instance.new("ScreenGui")
gui.Name = "CompanyName"
gui.ResetOnSpawn = false
gui.DisplayOrder = 10
gui.IgnoreGuiInset = true
gui.Enabled = false
UIKit.safe(gui)
gui.Parent = player:WaitForChild("PlayerGui")
-- other panels (the LAUNCH card) wait while this is open: one decision at a time
gui:GetPropertyChangedSignal("Enabled"):Connect(function() player:SetAttribute("NamingOpen", gui.Enabled) end)

local panel, body, close = UIKit.menu(gui, "NAME YOUR COMPANY", UIKit.BLUE, {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.45, 0), Size = UDim2.new(0.9, 0, 0, 226),
})
local cap = Instance.new("UISizeConstraint", panel)
cap.MaxSize = Vector2.new(440, 226)

local hint = UIKit.label(body, HINT, 16, UIKit.CARD_MUTED, {
	Size = UDim2.new(1, 0, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd,
}, UIKit.HEAD)

local box = Instance.new("TextBox")
box.Position = UDim2.new(0, 0, 0, 28)
box.Size = UDim2.new(1, 0, 0, 50)
box.BackgroundColor3 = UIKit.CARD
box.PlaceholderText = "Pocket Rocket Labs"
box.PlaceholderColor3 = UIKit.CARD_MUTED
box.Text = ""
box.TextColor3 = UIKit.CARD_TEXT
box.TextSize = 22
box.Font = UIKit.HEAD
box.TextXAlignment = Enum.TextXAlignment.Left
box.ClearTextOnFocus = false
box.Parent = body
Instance.new("UICorner", box).CornerRadius = UDim.new(0, 12)
local boxStroke = Instance.new("UIStroke", box)
boxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
boxStroke.Color = UIKit.CARD_LINE
boxStroke.Thickness = 2
box.Focused:Connect(function() boxStroke.Color = UIKit.BLUE end)
box.FocusLost:Connect(function() boxStroke.Color = UIKit.CARD_LINE end)
local pad = Instance.new("UIPadding", box)
pad.PaddingLeft = UDim.new(0, 14)

local ok = UIKit.button(body, "SAVE", UIKit.GREEN, {
	AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.new(0.5, -6, 0, 50),
}, { textSize = 22 })
local later = UIKit.button(body, "LATER", UIKit.MUTED, {
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(0.5, -6, 0, 50),
}, { textSize = 20 })

-- 20 characters, hard cap, typed or pasted
box:GetPropertyChangedSignal("Text"):Connect(function()
	if #box.Text > 20 then box.Text = box.Text:sub(1, 20) end
end)

local openSerial = 0
local function skip()
	if not gui.Enabled then return end
	gui.Enabled = false
	setName:FireServer("")          -- the server stops waiting and opens your lot now
end

local function submit()
	local t = box.Text:gsub("^%s+", ""):gsub("%s+$", "")
	if #t < 2 then
		hint.Text = "Two letters at least."
		hint.TextColor3 = UIKit.RED
		return
	end
	setName:FireServer(t)
	gui.Enabled = false
end

ok.MouseButton1Click:Connect(submit)
box.FocusLost:Connect(function(enterPressed) if enterPressed then submit() end end)
later.MouseButton1Click:Connect(skip)
if close then close.MouseButton1Click:Connect(skip) end

askName.OnClientEvent:Connect(function(message)
	-- one decision at a time: a returning player sees WHILE YOU WERE AWAY first
	-- (the first returning test stacked this box under the welcome card)
	if player:GetAttribute("Returning") == true then
		local t0 = os.clock()
		while player:GetAttribute("WelcomeDone") ~= true and os.clock() - t0 < 30 do task.wait(0.2) end
		task.wait(0.6)
	end
	if message and message ~= "" then
		hint.Text = message
		hint.TextColor3 = UIKit.RED
	else
		hint.Text = HINT
		hint.TextColor3 = UIKit.CARD_MUTED
	end
	-- v4.2: through the director (centre lane, P2, at a calm moment)
	Notify.show({ lane = "centre", priority = 2, key = "name", calm = true, maxHold = 180,
		open = function(done)
			gui.Enabled = true
			local sc = panel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", panel)
			sc.Scale = 0.6
			TweenService:Create(sc, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			openSerial += 1
			local mine = openSerial
			task.delay(25, function() if openSerial == mine and gui.Enabled and not box:IsFocused() then skip() end end)
			local conn
			conn = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
				if not gui.Enabled then conn:Disconnect(); done() end
			end)
		end })
end)
