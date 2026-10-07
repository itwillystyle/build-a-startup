--[[
	HomeClient (v4.0) -- the apartment sales card, screen fades, and the
	game's "moments" (Cine.lua):

	  movein  the camera rises up THE RESIDENCES to your floor, a fade, then a
	          slow move across your new living room: WELCOME HOME
	  car     an orbit round your new car on the forecourt (or the company car
	          in your bay): the name, the top speed
	  hq      a short orbit round your HQ when it grows a level (after the
	          building has risen)
	All skippable; none of them fire during a recruit run or in a car.
]]
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local UIKit = require(RS:WaitForChild("UIKit"))
local Cine = require(RS:WaitForChild("Cine"))
local remotes = RS:WaitForChild("SVRemotes")
local aptMenu = remotes:WaitForChild("AptMenu")
local aptBuy = remotes:WaitForChild("AptBuy")
local screenFade = remotes:WaitForChild("ScreenFade")
local cinema = remotes:WaitForChild("Cinema")

-- ============ THE SALES CARD ============
local gui = Instance.new("ScreenGui")
gui.Name = "Apartments"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 12
gui.Enabled = false
UIKit.safe(gui)
gui.Parent = player:WaitForChild("PlayerGui")

-- v5: 318 tall so it sits below the money line on a phone (at 330 it covered
-- the counter and reached Roblox's top-left buttons); the blurb box was 17 px too tall
local PANEL_W, PANEL_H = 620, 318
local panel, body, closeBtn = UIKit.menu(gui, "THE RESIDENCES", Color3.fromRGB(38, 41, 48), {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 10), Size = UDim2.new(0, PANEL_W, 0, PANEL_H),
})
local fit = Instance.new("UIScale", panel)
UIKit.fitMenu(panel, PANEL_W, PANEL_H, fit, 40)   -- v5: the shared rule (clears the rail, scales to fit)
if closeBtn then closeBtn.MouseButton1Click:Connect(function() gui.Enabled = false end) end
local row = Instance.new("UIListLayout")
row.FillDirection = Enum.FillDirection.Horizontal
row.Padding = UDim.new(0, 10)
row.SortOrder = Enum.SortOrder.LayoutOrder
row.Parent = body

local TIER_COLOR = { Color3.fromRGB(92, 170, 230), Color3.fromRGB(240, 150, 70), Color3.fromRGB(255, 200, 60) }
local openedAt

-- v5: your cash in the header (the menu covers the money counter on a phone),
-- as at the car dealer: the two shops read the same
local header = panel:FindFirstChild("Header")
local cashLbl = header and UIKit.outlined(header, "", 20, UIKit.MONEY, {
	Name = "Cash", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -62, 0.5, 0), Size = UDim2.new(0, 120, 0, 26),
	TextXAlignment = Enum.TextXAlignment.Right,
})
local function showCash()
	local ls = player:FindFirstChild("leaderstats")
	local c = ls and ls:FindFirstChild("Cash")
	if cashLbl and c then cashLbl.Text = UIKit.money(c.Value) end
end
task.spawn(function()
	local ls = player:WaitForChild("leaderstats", 30)
	local c = ls and ls:WaitForChild("Cash", 30)
	if c then c.Changed:Connect(function() if gui.Enabled then showCash() end end) end
end)

local function showMenu(st)
	for _, c in ipairs(body:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
	for i, t in ipairs(st.tiers) do
		local c = Instance.new("Frame")
		c.Name = "Tier_" .. t.id
		c.LayoutOrder = i
		c.Size = UDim2.new(1 / 3, -7, 1, 0)
		c.BackgroundColor3 = UIKit.CARD
		c.Parent = body
		Instance.new("UICorner", c).CornerRadius = UDim.new(0, 12)
		local stroke = Instance.new("UIStroke", c)
		stroke.Color = t.state == "buy" and TIER_COLOR[i] or UIKit.CARD_LINE
		stroke.Thickness = t.state == "buy" and 3 or 1.5
		local band = Instance.new("Frame")
		band.BackgroundColor3 = TIER_COLOR[i]
		band.Size = UDim2.new(1, 0, 0, 8)
		band.BorderSizePixel = 0
		band.Parent = c
		Instance.new("UICorner", band).CornerRadius = UDim.new(0, 12)
		UIKit.art(c, "key", 46, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14) })
		UIKit.label(c, t.name, 22, UIKit.CARD_TEXT, { Size = UDim2.new(1, -16, 0, 26), Position = UDim2.new(0, 8, 0, 66), TextXAlignment = Enum.TextXAlignment.Center }, UIKit.HEAD)
		UIKit.label(c, t.blurb or "", 14, UIKit.INK_SOFT, {
			Size = UDim2.new(1, -20, 0, 32), Position = UDim2.new(0, 10, 0, 100), TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top }, UIKit.BODY)
		local label, color, enabled
		if t.state == "owned" then label, color, enabled = "YOURS", UIKit.MUTED, false
		elseif t.state == "locked" then label, color, enabled = "LOCKED", UIKit.MUTED, false
		elseif st.cash >= t.price then label, color, enabled = "BUY " .. UIKit.money(t.price), UIKit.GREEN, true
		else label, color, enabled = UIKit.money(t.price), UIKit.MUTED, false end
		local b = UIKit.button(c, label, color, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -20, 0, 44) },
			{ textSize = 18 })
		if t.why then
			UIKit.label(c, t.why, 14, UIKit.RED_DEEP, { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.new(1, -16, 0, 16),
				Position = UDim2.new(0.5, 0, 1, -56), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true }, UIKit.BOLD)
		elseif t.state == "buy" and st.cash < t.price then
			UIKit.label(c, ("Need %s more"):format(UIKit.money(t.price - st.cash)), 14, UIKit.MUTED_TEXT, { AnchorPoint = Vector2.new(0.5, 1),
				Size = UDim2.new(1, -16, 0, 16), Position = UDim2.new(0.5, 0, 1, -56), TextXAlignment = Enum.TextXAlignment.Center }, UIKit.BOLD)
		end
		if enabled then
			b.MouseButton1Click:Connect(function()
				gui.Enabled = false
				aptBuy:FireServer(t.id)
			end)
		end
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	openedAt = root and root.Position
	showCash()
	gui.Enabled = true
	UIKit.solo(gui)
end
aptMenu.OnClientEvent:Connect(function(st) if type(st) == "table" and st.tiers then showMenu(st) end end)
RunService.Heartbeat:Connect(function()
	if not gui.Enabled or not openedAt then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - openedAt).Magnitude > 16 then gui.Enabled = false end
end)

-- ============ FADES ============
screenFade.OnClientEvent:Connect(function(dir)
	Cine.fade(dir == "out", dir == "out" and 0.25 or 0.4)
end)

-- ============ THE MOMENTS ============
local function busy()
	if Cine.busy() then return true end
	if player:GetAttribute("Carrying") then return true end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart then return true end
	return workspace.CurrentCamera.CameraType ~= Enum.CameraType.Custom
end

local function orbit(focus, radius, height, seconds, title, sub, startAngle)
	local shots = {}
	local n = 5
	for k = 0, n - 1 do
		local a = (startAngle or 0) + k * (math.pi * 0.9) / (n - 1)
		table.insert(shots, {
			pos = focus + Vector3.new(math.cos(a) * radius, height - k * height * 0.08, math.sin(a) * radius),
			look = focus + Vector3.new(0, 1, 0),
			t = seconds / (n - 1), title = k == 1 and title or nil, sub = k == 1 and sub or nil,
		})
	end
	shots[1].t = 0
	return Cine.play(shots, { fov = 52 })
end

cinema.OnClientEvent:Connect(function(e)
	if type(e) ~= "table" then return end
	if e.kind == "movein" then
		-- straight after a purchase: take over even if the camera is busy with nothing important
		if Cine.busy() then return end
		local tower, facing, floorY = e.tower, e.facing, e.floorY
		if typeof(tower) ~= "Vector3" or typeof(facing) ~= "Vector3" then return end
		local out = tower + facing * 110
		local shots = {
			{ pos = out + Vector3.new(0, 48, 0), look = tower + Vector3.new(0, 40, 0), t = 0,
				title = "WELCOME HOME", sub = ("Your %s at The Residences"):format(e.name or "apartment") },
			{ pos = tower + facing * 80 + Vector3.new(24, floorY * 0.55, 0), look = Vector3.new(tower.X, floorY, tower.Z), t = 1.2 },
			{ pos = tower + facing * 40 + Vector3.new(8, floorY - tower.Y + 2, 0), look = Vector3.new(tower.X, floorY, tower.Z), t = 1.1 },
		}
		Cine.play(shots, { fov = 55, handBack = false, skippable = false })
		Cine.fade(true, 0.25)
		task.wait(0.55)          -- the server moves you inside at 2.6 s
		Cine.fade(false, 0.5)
		local view = e.view
		if typeof(view) == "CFrame" then
			local p0 = view.Position
			local fwd = view.LookVector
			Cine.play({
				{ pos = p0 + Vector3.new(-6, 0, 0), look = p0 + fwd * 30, t = 0 },
				{ pos = p0 + Vector3.new(2, 0.5, 0) + fwd * 6, look = p0 + fwd * 34 + Vector3.new(6, -2, 0), t = 2.4,
					title = e.name or "HOME", sub = "Your people have somewhere to land" },
			}, { fov = 62, hold = 0.6 })
		else
			Cine.handBack()
		end
		UIKit.sfx("levelup")
	elseif e.kind == "car" then
		if typeof(e.focus) ~= "Vector3" then return end
		task.wait(e.delay or 0)
		if busy() then return end
		UIKit.sfx("star")
		orbit(e.focus, 18, 7, 3.4, e.title or "NEW CAR", ("%s   ·   top speed %d mph"):format(e.name or "", math.floor((e.speed or 60) * 0.28 * 2.237 * 1.6 + 0.5)), 0.4)
	end
end)

-- ============ THE CAMERA STAYS INDOORS ============
--[[ Inside an apartment or on an upper HQ floor the walls are invisible
collision, which the default camera ignores (it only stops at solid, opaque,
collidable parts), so a zoomed-out camera drifted outside the glass and filmed
the curtains: a grey screen right after moving in. Up there the zoom is capped. ]]
local defaultMaxZoom = player.CameraMaxZoomDistance
local indoors = false
local function inside()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	local p = root.Position
	if p.Y < 15 then return false end
	local sv = workspace:FindFirstChild("SiliconValley")
	local dt = sv and sv:FindFirstChild("Downtown")
	local res = dt and dt:FindFirstChild("Residences_Tower")
	if res and math.abs(p.X - res.Position.X) < 25 and math.abs(p.Z - res.Position.Z) < 22 then return true end
	local plots = sv and sv:FindFirstChild("Plots")
	for _, pf in ipairs(plots and plots:GetChildren() or {}) do
		local pivot = pf:GetAttribute("Pivot")
		if typeof(pivot) == "CFrame" then
			local rel = pivot:PointToObjectSpace(p)
			if math.abs(rel.X) < 48 and math.abs(rel.Z) < 28 and rel.Y < 62 then return true end
		end
	end
	return false
end
task.spawn(function()
	while true do
		local now = inside()
		if now ~= indoors then
			indoors = now
			player.CameraMaxZoomDistance = now and 9 or defaultMaxZoom
		end
		task.wait(0.3)
	end
end)

-- the HQ level-up orbit (the server's Celebrate event, after the new floors rise)
local celebrate = remotes:WaitForChild("Celebrate", 20)
if celebrate then
	celebrate.OnClientEvent:Connect(function(e)
		if type(e) ~= "table" or e.kind ~= "hq" then return end
		task.wait(1.4)
		if busy() then return end
		local idx = player:GetAttribute("Plot")
		local sv = workspace:FindFirstChild("SiliconValley")
		local pf = idx and sv and sv:FindFirstChild("Plots") and sv.Plots:FindFirstChild("Plot" .. idx)
		local pivot = pf and pf:GetAttribute("Pivot")
		if typeof(pivot) ~= "CFrame" then return end
		local h = ({ 14, 20, 28, 44, 60 })[e.level or 2] or 30
		local focus = pivot:PointToWorldSpace(Vector3.new(0, h * 0.45, 0))
		local shots = {
			{ pos = pivot:PointToWorldSpace(Vector3.new(70, h * 0.35, 95)), look = focus, t = 0 },
			{ pos = pivot:PointToWorldSpace(Vector3.new(20, h * 0.7 + 10, 105)), look = focus, t = 1.3, title = e.name, sub = "Your company just got bigger" },
			{ pos = pivot:PointToWorldSpace(Vector3.new(-45, h * 0.9 + 14, 90)), look = focus, t = 1.4 },
		}
		Cine.play(shots, { fov = 55 })
	end)
end
