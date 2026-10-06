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

	v4.3 FEEL (his note: "improve the car mechanics"): turn hard at speed and the
	car SLIDES (lateral slip grows with speed; let go and it grips again), with
	tyre smoke and a squeal; NITRO on Shift (or the button on a phone): +35% top
	speed for 2.2 s, 7 s to recharge; an electric-motor hum that rises with
	speed; headlights at night; and a car pushing into a wall bumps back instead
	of staying glued at full throttle (the old "stops dead at the valley edge").
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
local driving = nil         -- { model, chassis, seat, align, axles, v, spin, steer, lat, fx }
--[[ Engine sound is per CAR TIER, not one hum for all six. The licensed
	library has no six separate car recordings, so the ladder is built from one
	base loop shifted in pitch and weight, a high whine layer the fast cars get
	and the slow ones do not, and a bark on hard acceleration. Sfx.CAR holds the
	numbers and the reasoning. ]]
local Sfx = require(game:GetService("ReplicatedStorage"):WaitForChild("Sfx"))
local SKID = Sfx.url("skid")
local NITRO_SND = "rbxassetid://9126228631"
local NITRO = { mult = 1.35, time = 2.2, recharge = 7 }
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
		yaw = select(2, chassis.CFrame:ToEulerAnglesYXZ()), up = Vector3.new(0, 1, 0), fov = camera.FieldOfView,
		lat = 0, blockT = 0, fx = {} }
	-- v4.3: the sound, the smoke and the lights live on the client (nobody else needs to hear your engine)
	local fx = driving.fx
	local size = chassis.Size
	local function att(name, pos)
		local a = Instance.new("Attachment")
		a.Name = name
		a.Position = pos
		a.Parent = chassis
		table.insert(fx, a)
		return a
	end
	local function snd(id, loop)
		local x = Instance.new("Sound")
		x.SoundId = id
		x.Looped = loop
		x.Volume = 0
		x.RollOffMaxDistance = 120
		x.Parent = chassis
		table.insert(fx, x)
		return x
	end
	local tier = Sfx.car(m:GetAttribute("CarId"))
	fx.tier = tier
	-- the door shuts behind you: the cheapest possible cue that you are IN a car
	Sfx.play(chassis, "carDoor", { volume = 0.55, pitch = 0.95, life = 3 })
	fx.motor = snd(Sfx.url(tier.base), true)
	fx.motor.PlaybackSpeed = tier.pitch
	fx.motor:Play()
	if tier.whine > 0 then
		fx.whine = snd(Sfx.url("engineLow"), true)
		fx.whine.PlaybackSpeed = tier.wpitch
		fx.whine:Play()
	end
	--[[ Tyre roar is separate from the engine so it can rise with SPEED while
		the engine rises with throttle. It is what stops a fast car sounding
		like a slow car played faster. ]]
	fx.tyres = snd(Sfx.url("tyres"), true)
	fx.tyres:Play()
	fx.skid = snd(SKID, true)
	for _, side in ipairs({ -1, 1 }) do
		local a = att("SmokeL" .. side, Vector3.new(side * size.X * 0.42, -size.Y * 0.4, size.Z * 0.42))
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
		pe.Color = ColorSequence.new(Color3.fromRGB(235, 235, 235))
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4.5) })
		pe.Lifetime = NumberRange.new(0.6, 1.1)
		pe.Speed = NumberRange.new(1, 3)
		pe.SpreadAngle = Vector2.new(40, 40)
		pe.Rate = 0
		pe.Parent = a
		table.insert(fx, pe)
		fx["smoke" .. side] = pe
		local la = att("Lamp" .. side, Vector3.new(side * size.X * 0.32, 0, -size.Z * 0.5))
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Front
		light.Angle = 70
		light.Range = 45
		light.Brightness = 2.2
		light.Color = Color3.fromRGB(255, 244, 214)
		light.Enabled = false
		light.Parent = la
		table.insert(fx, light)
		fx["light" .. side] = light
	end
	local flame = att("Nitro", Vector3.new(0, -size.Y * 0.2, size.Z * 0.52))
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/fire_main.dds"
	pe.Color = ColorSequence.new(Color3.fromRGB(120, 200, 255), Color3.fromRGB(255, 150, 60))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0.2) })
	pe.Lifetime = NumberRange.new(0.15, 0.3)
	pe.Speed = NumberRange.new(10, 16)
	pe.EmissionDirection = Enum.NormalId.Back
	pe.Rate = 0
	pe.Parent = flame
	table.insert(fx, pe)
	fx.flame = pe
end

local function stopDrive()
	if driving then
		for _, j in ipairs(driving.axles) do j.Transform = CFrame.new() end
		for _, x in ipairs(driving.fx or {}) do if x.Parent then x:Destroy() end end
		TweenService:Create(camera, TweenInfo.new(0.5), { FieldOfView = 70 }):Play()
	end
	driving = nil
end

local nitroUntil, nitroReadyAt = 0, 0
local function nitro()
	if not driving or os.clock() < nitroReadyAt then return end
	nitroUntil = os.clock() + NITRO.time
	nitroReadyAt = os.clock() + NITRO.recharge
	local x = Instance.new("Sound")
	x.SoundId = NITRO_SND
	x.Volume = 0.6
	x.Parent = driving.chassis
	x:Play()
	task.delay(3, function() x:Destroy() end)
end
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift or input.KeyCode == Enum.KeyCode.ButtonX then nitro() end
	--[[ The horn. Pitched DOWN as the car gets more expensive: a small car has
		a small horn. It is the one sound here a player makes on purpose, so it
		is worth having it say which car they are in. ]]
	if (input.KeyCode == Enum.KeyCode.H or input.KeyCode == Enum.KeyCode.ButtonY)
		and driving and driving.chassis then
		local t = driving.fx and driving.fx.tier
		Sfx.play(driving.chassis, "horn", {
			volume = 0.5, life = 3,
			pitch = t and (1.25 - 0.45 * (t.whine / 0.26)) or 1.1,
		})
	end
end)

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
	local now = os.clock()
	local boosting = now < nitroUntil
	local top = d.top * (boosting and NITRO.mult or 1)
	local target
	if throttle > 0.05 then target = throttle * top
	elseif throttle < -0.05 then target = throttle * d.top * 0.45
	else target = 0 end
	local rate
	if target ~= 0 and math.sign(target) ~= math.sign(d.v) and math.abs(d.v) > 2 then rate = d.accel * 2.4    -- braking
	elseif target == 0 then rate = d.accel * 0.6                                                            -- coasting
	else rate = d.accel * (boosting and 1.8 or 1) end
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
	-- v4.3 THE SLIDE: turn hard at speed and the back steps out (lateral slip grows
	-- from 30 studs/s to the top end); let go of the wheel and it grips again
	local speedAbs = math.abs(d.v)
	local slipK = math.clamp((speedAbs - 30) / math.max(1, d.top - 30), 0, 1) * 0.34
	local latTarget = -d.steer * speedAbs * slipK
	d.lat = approach(d.lat, latTarget, (math.abs(latTarget) > math.abs(d.lat) and 38 or 24) * dt)
	local right = along:Cross(up)
	local horiz = along * d.v + right * d.lat
	-- a wall: at full throttle against something, bump back instead of staying glued
	local planar = Vector3.new(vel.X, 0, vel.Z).Magnitude
	if speedAbs > 14 and planar < speedAbs * 0.35 then d.blockT += dt else d.blockT = 0 end
	if d.blockT > 0.25 then
		d.v = -d.v * 0.25
		d.lat = 0
		d.blockT = 0
	end
	ch.AssemblyLinearVelocity = Vector3.new(horiz.X, hit and vy + horiz.Y or vy, horiz.Z)
	-- v4.3: the sound, the smoke, the flame, the lights
	local fx = d.fx
	if fx then
		local sp = math.clamp(speedAbs / d.top, 0, 1.4)
		local tier = fx.tier or Sfx.car(nil)
		if fx.motor then
			fx.motor.PlaybackSpeed = tier.pitch + 0.85 * sp + (boosting and 0.15 or 0)
			fx.motor.Volume = tier.vol * (0.45 + 0.55 * math.min(sp, 1))
		end
		if fx.whine then
			fx.whine.PlaybackSpeed = tier.wpitch + 1.10 * sp + (boosting and 0.25 or 0)
			fx.whine.Volume = tier.whine * math.min(sp, 1) ^ 1.5
		end
		if fx.tyres then
			fx.tyres.PlaybackSpeed = 0.85 + 0.45 * sp
			fx.tyres.Volume = 0.16 * math.clamp((sp - 0.12) / 0.6, 0, 1)
		end
		--[[ The bark: one short note when the throttle is opened hard from low
			speed, rate-limited so it punctuates instead of stuttering. Only the
			tiers that have one -- the quiet cars stay quiet. ]]
		if tier.bark and throttle and throttle > 0.6 and sp < 0.55
			and (now - (fx.barkAt or 0)) > 2.2 then
			fx.barkAt = now
			Sfx.play(d.chassis, tier.bark, { volume = 0.35 + 0.25 * tier.whine, pitch = 0.9 + 0.3 * sp, life = 4 })
		end
		local slide = math.clamp((math.abs(d.lat) - 4) / 10, 0, 1)
		if fx.skid then
			if slide > 0.05 and not fx.skid.IsPlaying then fx.skid:Play() end
			if slide <= 0.05 and fx.skid.IsPlaying then fx.skid:Stop() end
			fx.skid.Volume = 0.45 * slide
		end
		for _, side in ipairs({ -1, 1 }) do
			local pe = fx["smoke" .. side]
			if pe then pe.Rate = slide > 0.05 and (18 + 40 * slide) or 0 end
			local l = fx["light" .. side]
			if l then
				local ct = game:GetService("Lighting").ClockTime
				l.Enabled = ct < 6.4 or ct > 17.8
			end
		end
		if fx.flame then fx.flame.Rate = boosting and 120 or 0 end
	end
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
	camera.FieldOfView = camera.FieldOfView + ((70 + 10 * math.clamp(math.abs(d.v) / 120, 0, 1) + (boosting and 8 or 0)) - camera.FieldOfView) * math.clamp(dt * 3, 0, 1)
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
-- v5: a paper tile like the rail's (green was a second "loud" next to WRITE CODE)
local carBtn = UIKit.iconButton(gui, "car", "CAR", UIKit.PAPER, {
	Name = "CarButton", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0.5, 162, 1, -20),   -- v5: 44 px right of the bottom slot (at 1,-190 it was 27 px from LAUNCH on a phone)
	Size = UDim2.new(0, UIKit.RAIL, 0, UIKit.RAIL), Visible = false,
}, { iconSize = 28, dark = true, stroke = UIKit.INK_SOFT, captionSize = 14 })
local function call()
	if driving then return end
	callCar:FireServer()
end
carBtn.MouseButton1Click:Connect(call)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.C and carBtn.Visible then call() end
end)
-- v5: an open menu owns the screen; the bottom row (WRITE CODE, CAR) steps aside
local function menuOpen() return UIKit.menuOpen() end
local function refreshBtn()
	-- v5: the decor sheet owns the bottom edge while it is open (it covered this button)
	carBtn.Visible = player:GetAttribute("CarOwned") == true and not driving and player:GetAttribute("BuildModeOpen") ~= true
		and not menuOpen()
end
UIKit.onMenuChange(function() refreshBtn() end)
player:GetAttributeChangedSignal("CarOwned"):Connect(refreshBtn)
player:GetAttributeChangedSignal("BuildModeOpen"):Connect(refreshBtn)
-- v5: while "Hop in your company car" is the goal, the CAR tile is the loud thing:
-- a pulsing gold ring (the goal card says "Tap CAR"; there is no world arrow)
do
	local ring = carBtn:FindFirstChildOfClass("UIStroke")
	local rest = ring and { color = ring.Color, width = ring.Thickness }
	RunService.Heartbeat:Connect(function()
		if not ring then return end
		-- a coach tip on screen has the stage: the goal ring waits (two gold pulses at once)
		local coach = player.PlayerGui:FindFirstChild("Coach")
		local tip = coach and coach:FindFirstChild("CoachCard")
		local goal = player:GetAttribute("Objective") == "car" and carBtn.Visible and not (tip and tip.Visible)
			and player:GetAttribute("Celebrating") ~= true     -- nor during a level-up / rare-hire moment
		if goal then
			ring.Color = UIKit.GOLD
			ring.Thickness = 3 + 2 * (0.5 + 0.5 * math.sin(os.clock() * 5))
		elseif ring.Color ~= rest.color then
			ring.Color, ring.Thickness = rest.color, rest.width
		end
	end)
end

-- the speedometer while driving
local speedo = UIKit.card and UIKit.card(gui, {
	Name = "Speedo", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.new(0, 210, 0, 64), Visible = false,
}) or Instance.new("Frame")
-- v5: two rows, so nothing overlaps: the key hints on top, the speed under them
local speedText = UIKit.label(speedo, "0", 30, UIKit.INK, {
	Size = UDim2.new(0, 96, 0, 34), Position = UDim2.new(0, 10, 0, 24), TextXAlignment = Enum.TextXAlignment.Right,
}, UIKit.HEAD)
UIKit.label(speedo, "MPH", 14, UIKit.MUTED_TEXT, { Size = UDim2.new(0, 40, 0, 24), Position = UDim2.new(0, 110, 0, 32) }, UIKit.BOLD)
local exitHint = UIKit.label(speedo, UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and "JUMP = OUT" or "SPACE = OUT", 14, UIKit.MUTED_TEXT, {
	Size = UDim2.new(1, -16, 0, 16), Position = UDim2.new(0, 8, 0, 5), TextXAlignment = Enum.TextXAlignment.Right,
}, UIKit.BOLD)
local _ = exitHint
-- v4.3 NITRO: a bar on the speedometer, and a button for phones
local nitroBar = Instance.new("Frame")
nitroBar.Name = "Nitro"
nitroBar.BackgroundColor3 = UIKit.SURFACE_2
nitroBar.BorderSizePixel = 0
nitroBar.Position = UDim2.new(0, 10, 0, -10)
nitroBar.Size = UDim2.new(1, -20, 0, 8)
nitroBar.Parent = speedo
Instance.new("UICorner", nitroBar).CornerRadius = UDim.new(1, 0)
local nitroFill = Instance.new("Frame")
nitroFill.BackgroundColor3 = UIKit.BLUE
nitroFill.BorderSizePixel = 0
nitroFill.Size = UDim2.new(1, 0, 1, 0)
nitroFill.Parent = nitroBar
Instance.new("UICorner", nitroFill).CornerRadius = UDim.new(1, 0)
local nitroLbl = UIKit.label(speedo, UserInputService.KeyboardEnabled and "SHIFT = NITRO" or "NITRO", 14, UIKit.MUTED_TEXT, {
	Size = UDim2.new(1, -16, 0, 16), Position = UDim2.new(0, 8, 0, 5), TextXAlignment = Enum.TextXAlignment.Left,
}, UIKit.BOLD)
local nitroBtn = UIKit.button(gui, "NITRO", UIKit.BLUE, {
	Name = "NitroButton", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -190, 1, -20), Size = UDim2.new(0, 110, 0, 70),
	Visible = false,
}, { textSize = 22 })
nitroBtn.Activated:Connect(nitro)

RunService.RenderStepped:Connect(function()
	local show = driving ~= nil
	if speedo.Visible ~= show then speedo.Visible = show; refreshBtn() end
	nitroBtn.Visible = show and UserInputService.TouchEnabled
	if show then
		local ready = math.clamp(1 - (nitroReadyAt - os.clock()) / NITRO.recharge, 0, 1)
		nitroFill.Size = UDim2.new(os.clock() < nitroUntil and math.clamp((nitroUntil - os.clock()) / NITRO.time, 0, 1) or ready, 0, 1, 0)
		nitroFill.BackgroundColor3 = (os.clock() < nitroUntil and UIKit.ORANGE) or (ready >= 1 and UIKit.BLUE or UIKit.CARD_MUTED)
		nitroLbl.TextColor3 = ready >= 1 and UIKit.BLUE_DEEP or UIKit.MUTED_TEXT
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
-- v5: never scaled for height (six rows scaled to 0.82 put the 44 px buttons at
-- 36 on a phone); the list scrolls instead, with the next row peeking out
local function refit()
	local vp = camera.ViewportSize
	fit.Scale = math.min(1, (vp.X * 0.55) / 360)
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)
refit()
if closeBtn then closeBtn.MouseButton1Click:Connect(function() dg.Enabled = false end) end
local shelf = Instance.new("ScrollingFrame")
shelf.Name = "Shelf"
shelf.BackgroundTransparency = 1
shelf.BorderSizePixel = 0
shelf.Size = UDim2.new(1, 0, 1, 0)
shelf.CanvasSize = UDim2.new(0, 0, 0, 0)
shelf.AutomaticCanvasSize = Enum.AutomaticSize.Y
shelf.ScrollingDirection = Enum.ScrollingDirection.Y
shelf.ScrollBarThickness = 6
shelf.ScrollBarImageColor3 = UIKit.INK_SOFT
shelf.Parent = body
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 6)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = shelf
local openedAt

local function money(n) return UIKit.money and UIKit.money(n) or ("$" .. tostring(n)) end
-- v5: your cash, in the shop's own header. On a phone the dealer covers the
-- money counter (fitting it below the counter would shrink its words under 14 px
-- and its buttons under 44), so the number you shop with lives here
local header = panel:FindFirstChild("Header")
local cashLbl = header and UIKit.outlined(header, "", 20, UIKit.MONEY, {
	Name = "Cash", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -62, 0.5, 0), Size = UDim2.new(0, 120, 0, 26),
	TextXAlignment = Enum.TextXAlignment.Right,
})
local function showCash()
	local ls = player:FindFirstChild("leaderstats")
	local c = ls and ls:FindFirstChild("Cash")
	if cashLbl and c then cashLbl.Text = money(c.Value) end
end
task.spawn(function()
	local ls = player:WaitForChild("leaderstats", 30)
	local c = ls and ls:WaitForChild("Cash", 30)
	if c then c.Changed:Connect(function() if dg.Enabled then showCash() end end) end
end)

local function showDealer(st)
	for _, c in ipairs(shelf:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
	for i, c in ipairs(st.cars) do
		if c.price > 0 or c.owned then
			local row = Instance.new("Frame")
			row.Name = "Car_" .. c.id
			row.LayoutOrder = i
			row.Size = UDim2.new(1, -10, 0, 54)      -- room for the scroll bar
			row.BackgroundColor3 = c.id == st.focus and UIKit.GOLD_LIGHT or UIKit.CARD
			row.Parent = shelf
			Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
			local stroke = Instance.new("UIStroke", row)
			stroke.Color = UIKit.CARD_LINE
			UIKit.label(row, c.name, 18, UIKit.INK, { Size = UDim2.new(0, 170, 0, 22), Position = UDim2.new(0, 10, 0, 5) }, UIKit.HEAD)
			-- top speed as a bar
			local bar = Instance.new("Frame")
			bar.BackgroundColor3 = UIKit.SURFACE_2
			bar.Size = UDim2.new(0, 150, 0, 6)
			bar.Position = UDim2.new(0, 10, 0, 36)
			bar.BorderSizePixel = 0
			bar.Parent = row
			Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
			local fill = bar:Clone()
			fill.BackgroundColor3 = UIKit.GREEN
			fill.Size = UDim2.new(c.speed / st.top, 0, 1, 0)
			fill.Position = UDim2.new(0, 0, 0, 0)
			fill.Parent = bar
			local label, color, enabled
			if c.driving then label, color, enabled = "DRIVING", UIKit.MUTED, false
			elseif c.owned then label, color, enabled = "DRIVE", UIKit.BLUE, true
			elseif st.cash >= c.price then label, color, enabled = money(c.price), UIKit.GREEN, true
			else label, color, enabled = money(c.price), UIKit.MUTED, false end
			local b, t = UIKit.button(row, label, color, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0, 124, 0, 44) }, { textSize = 18 })
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
	-- v5: as tall as its rows (a fixed 380 px ran off a phone), then fit to the screen
	local rows = 0
	for _, ch in ipairs(shelf:GetChildren()) do if ch:IsA("GuiObject") then rows += 1 end end
	panel.Size = UDim2.new(0, 360, 0, math.min(52 + 26 + rows * 60, camera.ViewportSize.Y - 24))
	shelf.CanvasPosition = Vector2.new(0, 0)
	refit()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	openedAt = root and root.Position
	showCash()
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
