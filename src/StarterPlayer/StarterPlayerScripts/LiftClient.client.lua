--[[
	LiftClient (v4.0) -- the floor picker for HQFloors' lifts.

	Press E at any lift: a panel lists the building's stops top to bottom, like
	the buttons in a real lift (ROOF GARDEN, 5 SKY CAFE ... LOBBY), with the
	floor you are on greyed out. Tap one: the screen fades to black, the server
	moves you, a ding, the screen fades back in at the new floor's lift.
	Walking away closes it. The server checks everything (HQFloors.LiftGo).
]]
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local UIKit = require(RS:WaitForChild("UIKit"))
local Notify = require(RS:WaitForChild("Notify"))
local remotes = RS:WaitForChild("SVRemotes")
local liftMenu = remotes:WaitForChild("LiftMenu")
local liftGo = remotes:WaitForChild("LiftGo")

local gui = Instance.new("ScreenGui")
gui.Name = "Lift"
gui.ResetOnSpawn = false
gui.DisplayOrder = 12
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")
UIKit.safe(gui)

local fadeGui = Instance.new("ScreenGui")
fadeGui.Name = "LiftFade"
fadeGui.ResetOnSpawn = false
fadeGui.DisplayOrder = 40
fadeGui.IgnoreGuiInset = true
fadeGui.Parent = player.PlayerGui
local fade = Instance.new("Frame")
fade.Size = UDim2.new(1, 0, 1, 0)
fade.BackgroundColor3 = Color3.fromRGB(12, 14, 20)
fade.BackgroundTransparency = 1
fade.BorderSizePixel = 0
fade.Parent = fadeGui

local menu, body, close = UIKit.menu(gui, "LIFT", UIKit.BLUE, {
	Name = "Panel", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -24, 0.5, 0), Size = UDim2.new(0, 300, 0, 200),
})
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 8)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = body

local openedAt
local busy = false

local function hide()
	gui.Enabled = false
	openedAt = nil
end
if close then close.MouseButton1Click:Connect(hide) end

-- v4.2: the shared toast (Notify), one bottom toast for the whole game
local function say(text)
	Notify.toast(text, { priority = 1, hold = 2.2, sfx = "thunk" })
end

local function ride(plotIndex, stopId)
	if busy then return end
	busy = true
	hide()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local from = root and root.Position
	TweenService:Create(fade, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0 }):Play()
	task.wait(0.22)
	liftGo:FireServer(plotIndex, stopId)
	local t0 = os.clock()
	while os.clock() - t0 < 1.4 do
		RunService.Heartbeat:Wait()
		if root and from and (root.Position - from).Magnitude > 4 then break end
	end
	task.wait(0.12)
	UIKit.sfx("ding", 1.05, 0.45)
	TweenService:Create(fade, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	task.wait(0.4)
	busy = false
end

liftMenu.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	if data.blocked then say(data.blocked) return end
	for _, c in ipairs(body:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	local stops = data.stops or {}
	-- top to bottom, the way a lift panel reads
	local order = {}
	for i = #stops, 1, -1 do table.insert(order, stops[i]) end
	for k, st in ipairs(order) do
		local here = st.id == data.here
		local label = (st.id == "R" and "ROOF") or (st.id == "L" and "LOBBY") or st.name
		local b = UIKit.button(body, "", here and Color3.fromRGB(200, 206, 216) or UIKit.BLUE, {
			Name = "Stop_" .. st.id, Size = UDim2.new(1, 0, 0, 48), LayoutOrder = k,
		})
		local num = UIKit.label(b, label, 22, here and UIKit.CARD_MUTED or UIKit.TEXT, {
			Size = UDim2.new(0, 84, 1, -5), Position = UDim2.new(0, 14, 0, 0),
		}, UIKit.HEAD)
		num.TextStrokeTransparency = here and 1 or 0.5
		UIKit.label(b, here and "YOU ARE HERE" or (st.sub or ""), 15, here and UIKit.CARD_MUTED or UIKit.TEXT, {
			Size = UDim2.new(1, -110, 1, -5), Position = UDim2.new(0, 100, 0, 0), TextXAlignment = Enum.TextXAlignment.Right,
		}, UIKit.BOLD)
		if not here then
			b.MouseButton1Click:Connect(function() ride(data.plot, st.id) end)
		end
	end
	menu.Size = UDim2.new(0, 300, 0, 48 + 24 + #order * 56)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	openedAt = root and root.Position
	gui.Enabled = true
	UIKit.solo(gui)
	UIKit.sfx("tap")
end)

-- walking away closes the picker
RunService.Heartbeat:Connect(function()
	if not gui.Enabled or not openedAt then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - openedAt).Magnitude > 12 then hide() end
end)
