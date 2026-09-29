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

-- v5: centred like every menu (at the right edge it sat on the goal card)
local menu, body, close = UIKit.menu(gui, "LIFT", UIKit.BLUE, {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 360, 0, 200),
})
local list = Instance.new("UIGridLayout")
list.CellSize = UDim2.new(0.5, -4, 0, 52)
list.CellPadding = UDim2.new(0, 8, 0, 8)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = body
local fit = Instance.new("UIScale", menu)
local place = UIKit.fitMenu(menu, 360, nil, fit, 16)   -- v5: the shared rule (clears the rail, scales to fit)
menu:GetPropertyChangedSignal("Size"):Connect(function() place(menu.Position.Y.Scale, menu.Position.Y.Offset) end)   -- the stop count sets its height

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
	-- v5: two columns, a floor badge and the floor's name (six full-width rows were
	-- 414 px tall, taller than a phone, and "ROOF / ROOF GARDEN" said it twice)
	-- v5 critique: like a real lift panel, it counts up from the bottom-left:
	-- the stops pair up in twos (L 2 / 3 4 / 5 R) and the rows stack upward
	local rowsOf = {}
	for i = 1, #stops, 2 do table.insert(rowsOf, { stops[i], stops[i + 1] }) end
	local order = {}
	for r = #rowsOf, 1, -1 do
		for _, st in ipairs(rowsOf[r]) do table.insert(order, st) end
	end
	for k, st in ipairs(order) do
		local here = st.id == data.here
		-- the server sends { id = "L" | "F2".."F5" | "R", name = "LOBBY" | "2" | "R",
		-- sub = theme name }: the badge is the floor's number, the title its name
		local num = tostring(st.id):match("^F(%d+)$")
		local badgeText = num or tostring(st.id)
		local name = (st.id == "L" and "LOBBY") or ((st.sub and st.sub ~= "") and st.sub)
			or (num and ("FLOOR " .. num)) or st.name or ""
		local b = UIKit.button(body, "", here and UIKit.SURFACE_2 or UIKit.BLUE, {
			Name = "Stop_" .. st.id, Size = UDim2.new(0, 0, 0, 0), LayoutOrder = k,
		}, { silent = here })
		local badge = Instance.new("TextLabel")
		badge.AnchorPoint = Vector2.new(0, 0.5)
		badge.Position = UDim2.new(0, 8, 0.5, -2)
		badge.Size = UDim2.new(0, 36, 0, 36)
		badge.BackgroundColor3 = here and UIKit.PAPER or UIKit.BLUE_DEEP
		badge.Text = badgeText
		badge.TextColor3 = here and UIKit.MUTED_TEXT or UIKit.TEXT
		badge.TextSize = 20
		badge.Font = UIKit.HEAD
		badge.ZIndex = b.ZIndex + 1
		badge.Parent = b
		Instance.new("UICorner", badge).CornerRadius = UDim.new(1, 0)
		local nm = UIKit.label(b, name, 16, here and UIKit.INK or UIKit.TEXT, {
			Position = UDim2.new(0, 52, 0, 4), Size = UDim2.new(1, -58, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = b.ZIndex + 1,
		}, UIKit.HEAD)
		if not here then UIKit.paintLabel(nm, UIKit.BLUE) end
		local sub = here and "YOU ARE HERE" or ""
		if sub ~= "" then
			local sl = UIKit.label(b, sub, 14, here and UIKit.MUTED_TEXT or UIKit.TEXT, {
				Position = UDim2.new(0, 52, 0, 25), Size = UDim2.new(1, -58, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = b.ZIndex + 1,
			}, UIKit.BODY)
			if not here then UIKit.paintLabel(sl, UIKit.BLUE) end
		else
			nm.Position = UDim2.new(0, 52, 0, 0)
			nm.Size = UDim2.new(1, -58, 1, -5)
		end
		if not here then
			b.MouseButton1Click:Connect(function() ride(data.plot, st.id) end)
		end
	end
	local rows = math.ceil(#order / 2)
	menu.Size = UDim2.new(0, 360, 0, 52 + 26 + rows * 60)
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
