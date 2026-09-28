--[[
	CarClient (v4.0) -- drives the car you are sitting in, and the car UI.

	The server builds the car (Cars.lua) and gives the driver network
	ownership, so this script moves it directly and the server sees it:
	  - speed: eases toward throttle x top speed along the heading (reverse at
	    45%), brakes hard when you press against the way you are going
	  - steering: yaw rate grows with speed and eases off at the top end, so
	    parking is tight and the highway is stable
	  - a HOVER spring on a ground ray holds the chassis at ride height, which
	    is what lets it climb kerbs and follow the hills; in the air, gravity
	  - AlignOrientation leans the car to the ground normal, yaw from steering
	  - the wheels spin with speed (Motor6D.Transform) and the fronts steer
	UI: the CAR button (calls your car to you; C on a keyboard), a speedometer
	while driving, the dealership card, and turntables in the showroom.
]]
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local UIKit = require(RS:WaitForChild("UIKit"))
local Notify = require(RS:WaitForChild("Notify"))
local remotes = RS:WaitForChild("SVRemotes")
local callCar = remotes:WaitForChild("CallCar")
local buyCar = remotes:WaitForChild("BuyCar")
local dealerMenu = remotes:WaitForChild("DealerMenu")
local carToast = remotes:WaitForChild("CarToast")

-- ============ DRIVING ============
local RIDE = 0.8
local driving = nil         -- { model, chassis, seat, align, axles, v, spin, steer }
local camera = workspace.CurrentCamera

local function carOf(seat)
	local m = seat and seat.Parent
	if m and seat:IsA("VehicleSeat") and CollectionService:HasTag(m, "SVCar") then return m end
	return nil
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function startDrive(m, seat)
	local chassis = m:FindFirstChild("Chassis")
	if not chassis then return end
	local axles = {}
	for _, j in ipairs(chassis:GetChildren()) do
		if j:IsA("Motor6D") and j.Name == "Axle" then table.insert(axles, j) end
	end
	driving = { model = m, chassis = chassis, seat = seat, align = chassis:FindFirstChild("Keep"), axles = axles,
		v = 0, spin = 0, steer = 0, top = m:GetAttribute("Speed") or 70, accel = m:GetAttribute("Accel") or 44,
		yaw = select(2, chassis.CFrame:ToEulerAnglesYXZ()), up = Vector3.new(0, 1, 0), fov = camera.FieldOfView }
end

local function stopDrive()
	if driving then
		for _, j in ipairs(driving.axles) do j.Transform = CFrame.new() end
		TweenService:Create(camera, TweenInfo.new(0.5), { FieldOfView = 70 }):Play()
	end
	driving = nil
end

local function approach(v, target, rate)
	if v < target then return math.min(v + rate, target) end
	return math.max(v - rate, target)
end

RunService.Heartbeat:Connect(function(dt)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	local m = carOf(seat)
	if m and (not driving or driving.model ~= m) then startDrive(m, seat) end
	if not m and driving then stopDrive() end
	if not driving then return end
	local d = driving
	local ch = d.chassis
	if ch.Anchored then return end               -- the server hasn't handed it over yet
	local throttle = d.seat.ThrottleFloat
	local steer = d.seat.SteerFloat
	-- speed along the heading
	local target
	if throttle > 0.05 then target = throttle * d.top
	elseif throttle < -0.05 then target = throttle * d.top * 0.45
	else target = 0 end
	local rate
	if target ~= 0 and math.sign(target) ~= math.sign(d.v) and math.abs(d.v) > 2 then rate = d.accel * 2.4    -- braking
	elseif target == 0 then rate = d.accel * 0.6                                                            -- coasting
	else rate = d.accel end
	d.v = approach(d.v, target, rate * dt)
	-- steering: stronger at low speed, gentler at the top end
	local speedK = math.clamp(math.abs(d.v) / 18, 0, 1) * (1 - 0.4 * math.clamp(math.abs(d.v) / d.top, 0, 1))
	d.steer = approach(d.steer, steer, 4 * dt)
	d.yaw -= d.steer * 1.9 * speedK * (d.v >= 0 and 1 or -1) * dt
	-- the ground under the middle of the car
	rayParams.FilterDescendantsInstances = { d.model, char }
	local hit = workspace:Raycast(ch.Position, Vector3.new(0, -(0.8 + RIDE + 3), 0), rayParams)
	local vel = ch.AssemblyLinearVelocity
	local vy = vel.Y
	if hit then
		local h = (ch.Position.Y - 0.8) - hit.Position.Y
		if h < RIDE + 1.2 then
			vy = math.clamp((RIDE - h) * 14 - vy * 0.15, -40, 40)
			d.up = d.up:Lerp(hit.Normal, math.clamp(dt * 8, 0, 1))
		end
	else
		d.up = d.up:Lerp(Vector3.new(0, 1, 0), math.clamp(dt * 3, 0, 1))
	end
	local fwd = Vector3.new(-math.sin(d.yaw), 0, -math.cos(d.yaw))
	-- project the heading onto the ground plane so slopes don't fight the hover
	local up = d.up.Magnitude > 0.1 and d.up.Unit or Vector3.new(0, 1, 0)
	local along = (fwd - up * fwd:Dot(up))
	along = along.Magnitude > 0.01 and along.Unit or fwd
	local horiz = along * d.v
	ch.AssemblyLinearVelocity = Vector3.new(horiz.X, hit and vy + horiz.Y or vy, horiz.Z)
	if d.align then
		d.align.CFrame = CFrame.lookAt(Vector3.zero, along, up)
	end
	-- wheels: spin with distance travelled, fronts turn with the steer
	d.spin = (d.spin + d.v * dt / 1.3) % (math.pi * 2)
	for _, j in ipairs(d.axles) do
		local steerA = j:GetAttribute("Front") and (-d.steer * 0.45) or 0
		j.Transform = CFrame.Angles(0, steerA, 0) * CFrame.Angles(-d.spin, 0, 0)
	end
	-- a touch more field of view with speed
	camera.FieldOfView = camera.FieldOfView + ((70 + 10 * math.clamp(math.abs(d.v) / 120, 0, 1)) - camera.FieldOfView) * math.clamp(dt * 3, 0, 1)
end)

-- ============ THE HUD ============
local gui = Instance.new("ScreenGui")
gui.Name = "CarHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 6
UIKit.safe(gui)
gui.Parent = player:WaitForChild("PlayerGui")

-- the CAR button, bottom-right, left of where a phone's jump button sits
local carBtn = UIKit.iconButton(gui, "car", "CAR", UIKit.GREEN, {
	Name = "CarButton", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -190, 1, -20),
	Size = UDim2.new(0, UIKit.RAIL, 0, UIKit.RAIL), Visible = false,
}, { iconSize = 28 })
local function call()
	if driving then return end
	callCar:FireServer()
end
carBtn.MouseButton1Click:Connect(call)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.C and carBtn.Visible then call() end
end)
local function refreshBtn()
	carBtn.Visible = player:GetAttribute("CarOwned") == true and not driving
end
player:GetAttributeChangedSignal("CarOwned"):Connect(refreshBtn)

-- the speedometer while driving
local speedo = UIKit.card and UIKit.card(gui, {
	Name = "Speedo", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.new(0, 190, 0, 56), Visible = false,
}) or Instance.new("Frame")
local speedText = UIKit.label(speedo, "0", 30, UIKit.CARD_TEXT, {
	Size = UDim2.new(0, 90, 1, 0), Position = UDim2.new(0, 14, 0, 0), TextXAlignment = Enum.TextXAlignment.Right,
}, UIKit.HEAD)
UIKit.label(speedo, "MPH", 14, UIKit.CARD_MUTED, { Size = UDim2.new(0, 40, 1, -6), Position = UDim2.new(0, 108, 0, 4) }, UIKit.BOLD)
local exitHint = UIKit.label(speedo, UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and "JUMP = OUT" or "SPACE = OUT", 11, UIKit.CARD_MUTED, {
	Size = UDim2.new(1, -16, 0, 14), Position = UDim2.new(0, 8, 1, -16), TextXAlignment = Enum.TextXAlignment.Right,
}, UIKit.BOLD)
local _ = exitHint

RunService.RenderStepped:Connect(function()
	local show = driving ~= nil
	if speedo.Visible ~= show then speedo.Visible = show; refreshBtn() end
	if show then
		-- 1 stud = 0.28 m; mph for the feel of it
		speedText.Text = tostring(math.floor(math.abs(driving.v) * 0.28 * 2.237 * 1.6 + 0.5))
	end
end)

-- toasts from the car system: the shared toast (v4.2), answers to what you just did
carToast.OnClientEvent:Connect(function(text)
	Notify.toast(tostring(text), { priority = 1, hold = 2.6, sfx = "thunk" })
end)

-- ============ THE DEALERSHIP ============
local dg = Instance.new("ScreenGui")
dg.Name = "Dealer"
dg.ResetOnSpawn = false
dg.IgnoreGuiInset = true
dg.DisplayOrder = 12
dg.Enabled = false
UIKit.safe(dg)
dg.Parent = player.PlayerGui
local panel, body, closeBtn = UIKit.menu(dg, "VALLEY MOTORS", Color3.fromRGB(38, 41, 48), {
	Name = "Panel", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -20, 0.5, 0), Size = UDim2.new(0, 360, 0, 380),
})
local fit = Instance.new("UIScale", panel)
local function refit()
	local vp = camera.ViewportSize
	fit.Scale = math.min(1, (vp.Y - 40) / 380, (vp.X * 0.55) / 360)
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)
refit()
if closeBtn then closeBtn.MouseButton1Click:Connect(function() dg.Enabled = false end) end
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 6)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = body
local openedAt

local function money(n) return UIKit.money and UIKit.money(n) or ("$" .. tostring(n)) end

local function showDealer(st)
	for _, c in ipairs(body:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
	for i, c in ipairs(st.cars) do
		if c.price > 0 or c.owned then
			local row = Instance.new("Frame")
			row.Name = "Car_" .. c.id
			row.LayoutOrder = i
			row.Size = UDim2.new(1, 0, 0, 50)
			row.BackgroundColor3 = c.id == st.focus and Color3.fromRGB(255, 244, 214) or UIKit.CARD
			row.Parent = body
			Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
			local stroke = Instance.new("UIStroke", row)
			stroke.Color = UIKit.CARD_LINE
			UIKit.label(row, c.name, 17, UIKit.CARD_TEXT, { Size = UDim2.new(0, 170, 0, 22), Position = UDim2.new(0, 10, 0, 5) }, UIKit.HEAD)
			-- top speed as a bar
			local bar = Instance.new("Frame")
			bar.BackgroundColor3 = Color3.fromRGB(226, 230, 238)
			bar.Size = UDim2.new(0, 150, 0, 6)
			bar.Position = UDim2.new(0, 10, 0, 33)
			bar.BorderSizePixel = 0
			bar.Parent = row
			Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
			local fill = bar:Clone()
			fill.BackgroundColor3 = UIKit.GREEN
			fill.Size = UDim2.new(c.speed / st.top, 0, 1, 0)
			fill.Position = UDim2.new(0, 0, 0, 0)
			fill.Parent = bar
			local label, color, enabled
			if c.driving then label, color, enabled = "DRIVING", Color3.fromRGB(200, 206, 216), false
			elseif c.owned then label, color, enabled = "DRIVE", UIKit.BLUE, true
			elseif st.cash >= c.price then label, color, enabled = money(c.price), UIKit.GREEN, true
			else label, color, enabled = money(c.price), Color3.fromRGB(200, 206, 216), false end
			local b, t = UIKit.button(row, label, color, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0, 116, 0, 38) })
			if t then t.Text = label end
			if not t then UIKit.label(b, label, 16, UIKit.TEXT, { Size = UDim2.new(1, 0, 1, -5), TextXAlignment = Enum.TextXAlignment.Center }, UIKit.HEAD) end
			if enabled then
				b.MouseButton1Click:Connect(function() dg.Enabled = false; buyCar:FireServer(c.id) end)
			elseif not c.owned then
				b.MouseButton1Click:Connect(function()
					if not t then return end
					t.Text = "NEED " .. money(c.price - st.cash)
					UIKit.sfx("thunk")
					local x0 = b.Position
					for k = 1, 4 do
						b.Position = x0 + UDim2.new(0, (k % 2 == 0) and -5 or 5, 0, 0)
						task.wait(0.04)
					end
					b.Position = x0
					task.delay(1.6, function() if t and t.Parent then t.Text = label end end)
				end)
			end
		end
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	openedAt = root and root.Position
	dg.Enabled = true
	UIKit.solo(dg)
end
dealerMenu.OnClientEvent:Connect(function(st) if type(st) == "table" and st.cars then showDealer(st) end end)
RunService.Heartbeat:Connect(function()
	if not dg.Enabled or not openedAt then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - openedAt).Magnitude > 22 then dg.Enabled = false end
end)

-- the showroom turntable: the featured car turns slowly (client-side, free)
local turning = {}
local function addTurn(m)
	if m:IsA("Model") then turning[m] = m:GetPivot() end
end
CollectionService:GetInstanceAddedSignal("SVTurntable"):Connect(addTurn)
for _, m in ipairs(CollectionService:GetTagged("SVTurntable")) do addTurn(m) end
RunService.RenderStepped:Connect(function()
	local a = (os.clock() * 0.35) % (math.pi * 2)
	for m, base in pairs(turning) do
		if m.Parent then
			m:PivotTo(CFrame.new(base.Position) * CFrame.Angles(0, a, 0) * base.Rotation)
		else
			turning[m] = nil
		end
	end
end)
refreshBtn()
