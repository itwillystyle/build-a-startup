--[[
	IntroClient -- LocalScript in StarterPlayer -> StarterPlayerScripts.

	THE WELCOME. His ask: "similar to Sell Lemons -- they have a lemon pop-up
	intro, a welcoming thing, almost like a cutscene."

	Five seconds, three shots, then the game:
	  1. high over the valley -- SIX campuses, YOUR name on the card
	  2. swoop to your lot -- "this one is yours"
	  3. through the garage door to the laptop -- "start here"
	Then the camera hands back and the laptop glows for ten seconds, so the
	first verb is the one lit object in the room.

	RULES LEARNED THE HARD WAY:
	  - never capture a Scriptable camera as "previous" (the card shop froze a
	    camera dead that way); always restore to Custom
	  - touch skips ONLY via the visible SKIP button -- a finger-drag is the
	    mobile camera and would skip everything on frame one
	  - nothing here dims or blocks; it is a camera and a caption, not a gate
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local GOLD = Color3.fromRGB(255, 208, 70)
local UIKit = require(game:GetService("ReplicatedStorage"):WaitForChild("UIKit"))

-- ============ FIND MY PLOT ============

local function myPlot()
	local idx = player:GetAttribute("Plot")
	local sv = workspace:FindFirstChild("SiliconValley")
	local pf = idx and sv and sv:FindFirstChild("Plots") and sv.Plots:FindFirstChild("Plot" .. idx)
	if not pf then return nil end
	return pf, pf:GetAttribute("Pivot")
end

-- ============ UI ============

local gui = Instance.new("ScreenGui")
gui.Name = "Intro"
gui.ResetOnSpawn = false
gui.DisplayOrder = 12
gui.IgnoreGuiInset = true
gui.Enabled = false
UIKit.safe(gui)
gui.Parent = player:WaitForChild("PlayerGui")

-- v3.1: a white card like every other HUD card (the dark gold-rim panel was
-- the anti-reference), the name in the game's display font
local card = UIKit.card(gui, {
	Name = "Card", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40),
	Size = UDim2.new(0.9, 0, 0, 112),
}, { radius = 18, strokeWidth = 3, stroke = UIKit.darker(UIKit.GOLD, 0.8) })
local cap = Instance.new("UISizeConstraint", card)
cap.MaxSize = Vector2.new(620, 112)

local title = UIKit.outlined(card, "BUILD A STARTUP!", 30, GOLD, {
	Position = UDim2.new(0, 20, 0, 12), Size = UDim2.new(1, -40, 0, 38),
})

local line = UIKit.label(card, "", 18, UIKit.CARD_TEXT, {
	Position = UDim2.new(0, 20, 0, 54), Size = UDim2.new(1, -150, 0, 46), TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
}, UIKit.HEAD)

local skip = UIKit.button(card, "SKIP", UIKit.SURFACE_2, {
	AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -14), Size = UDim2.new(0, 110, 0, 48),
}, { textSize = 18, dark = true })

-- ============ THE SHOTS ============

local skipped = false
skip.MouseButton1Click:Connect(function() skipped = true end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not gui.Enabled or isTouch then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Keyboard then
		skipped = true
	end
end)

local function glide(cam, fromCF, toCF, seconds)
	local t0 = os.clock()
	while true do
		if skipped then return end
		local a = math.clamp((os.clock() - t0) / seconds, 0, 1)
		local e = a * a * (3 - 2 * a)
		cam.CFrame = fromCF:Lerp(toCF, e)
		if a >= 1 then return end
		RunService.RenderStepped:Wait()
	end
end

local function say(text)
	line.Text = text
	line.TextTransparency = 1
	TweenService:Create(line, TweenInfo.new(0.35), { TextTransparency = 0 }):Play()
end

local function lightTheLaptop(pf)
	local laptop = pf and pf:FindFirstChild("Garage") and pf.Garage:FindFirstChild("Laptop")
	if not laptop then return end
	local hl = Instance.new("Highlight")
	hl.FillColor = GOLD
	hl.OutlineColor = GOLD
	hl.FillTransparency = 0.7
	hl.OutlineTransparency = 0
	hl.Parent = laptop
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 10 and hl.Parent do
			hl.FillTransparency = 0.55 + 0.35 * (0.5 + 0.5 * math.sin((os.clock() - t0) * 4))
			task.wait(0.05)
		end
		hl:Destroy()
	end)
end

--[[ v4.0 THE FLYOVER. The old intro was three straight glides that stopped
dead between them (a slideshow), over a static caption card. Now one
continuous spline flight (Cine.lua) with letterbox bars and title cards:
the valley from the Bay, the six campuses, DOWNTOWN (where your apartment
will be), your lot, through the garage door to the laptop. ~10 s, SKIP any
time; returning players get a 3-second "welcome back" over their campus. ]]
local Cine = require(game:GetService("ReplicatedStorage"):WaitForChild("Cine"))

local function runIntro()
	local pf, pivot
	local t0 = os.clock()
	repeat
		pf, pivot = myPlot()
		if not pf then task.wait(0.2) end
	until pf or os.clock() - t0 > 8
	if not pf then return end
	local char = player.Character or player.CharacterAdded:Wait()
	char:WaitForChild("Humanoid", 5)
	local t1 = os.clock()
	while player:GetAttribute("MenuDone") ~= true and os.clock() - t1 < 600 do task.wait(0.1) end
	task.wait(0.3)

	local P = function(x, y, z) return pivot:PointToWorldSpace(Vector3.new(x, y, z)) end
	local hq = P(0, 8, 0)
	local laptop = P(0, 4, -9)
	local returning = player:GetAttribute("Returning") == true
	if returning then
		local away = player:GetAttribute("OfflineEarned") or 0
		Cine.play({
			{ pos = P(95, 60, 130), look = hq, t = 0, title = ("WELCOME BACK, %s"):format(string.upper(player.DisplayName)),
				sub = away > 0 and "Your team kept working while you were away." or "Pick up where you left off." },
			{ pos = P(40, 26, 70), look = hq, t = 2.8 },
		}, { fov = 58 })
		return
	end
	local ok = Cine.play({
		{ pos = Vector3.new(-980, 250, 420), look = Vector3.new(-200, 40, 0), t = 0,
			title = "SILICON VALLEY", sub = "Every giant started in a garage." },
		{ pos = Vector3.new(-420, 170, 230), look = Vector3.new(200, 20, 0), t = 2.3,
			title = ("SIX FOUNDERS. ONE VALLEY."), sub = ("Welcome, %s."):format(player.DisplayName) },
		{ pos = Vector3.new(430, 120, 150), look = Vector3.new(720, 80, 0), t = 2.3,
			title = "DOWNTOWN", sub = "Where you'll buy your first apartment." },
		{ pos = P(80, 60, 120), look = hq, t = 2.4, title = "THIS LOT IS YOURS", sub = "A garage, a laptop, and zero dollars." },
		{ pos = P(0, 7.5, 26), look = laptop, t = 1.7 },
		{ pos = P(6, 6.5, 6), look = laptop, t = 1.1, title = "START HERE",
			sub = isTouch and "Tap the laptop to write your first app." or "Click the laptop to write your first app." },
	}, { fov = 60, hold = 0.7 })
	local _ = ok
	lightTheLaptop(pf)
end

task.spawn(runIntro)
