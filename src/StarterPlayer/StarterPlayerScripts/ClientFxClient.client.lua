--[[ ClientFxClient (16 Oct 2026): the payout when you hand an app to a client.

	Mocks Luke picked (ui/2026-10-16-client-loop/mockups.html):
	  3A, every client: "+$X" pops over the client, "+$Y TIP" under it a beat later,
	     coins fly into the cash counter (Moment.landMoney).
	  3B, the first client only: gold rays, a tilted "SHIPPED!" stamp in the middle,
	     then a big "+$X" that counts up and flies into the cash (Tizzy's 5x wow).
	The server sends ClientPaid { pay, tip, wow, at, who } (ClientsServer). ]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local Moment = require(ReplicatedStorage:WaitForChild("Moment"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("SVRemotes")
local clientPaid = remotes:WaitForChild("ClientPaid", 30)
if not clientPaid then return end

local gui = Instance.new("ScreenGui")
gui.Name = "ClientFx"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 40
gui.Parent = player:WaitForChild("PlayerGui")

local function screenAt(world)
	local cam = workspace.CurrentCamera
	local v, onScreen = cam:WorldToViewportPoint(world)
	if not onScreen then
		local vp = cam.ViewportSize
		return Vector2.new(vp.X * 0.62, vp.Y * 0.45)
	end
	return Vector2.new(v.X, v.Y)
end

local function ease(obj, seconds, goal)
	local tw = TweenService:Create(obj, TweenInfo.new(seconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

-- a word that pops up at a screen point, rises and fades
local function pop(text, at, size, colour, delay)
	task.delay(delay or 0, function()
		local l = UIKit.outlined(gui, text, size, colour, {
			AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 260, 0, size + 10),
			Position = UDim2.new(0, at.X, 0, at.Y), TextXAlignment = Enum.TextXAlignment.Center,
		})
		local sc = Instance.new("UIScale")
		sc.Parent = l
		Moment.enter(sc, 0.4, 0.3)
		task.delay(0.7, function()
			if not l.Parent then return end
			ease(l, 0.6, { Position = l.Position - UDim2.new(0, 0, 0, 40), TextTransparency = 1 })
			local st = l:FindFirstChildOfClass("UIStroke")
			if st then ease(st, 0.6, { Transparency = 1 }) end
		end)
		task.delay(1.4, function() l:Destroy() end)
	end)
end

-- 3B: rays turning behind the stamp
local function rays(centre)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.new(0, centre.X, 0, centre.Y)
	holder.Size = UDim2.new(0, 520, 0, 520)
	holder.ZIndex = 1
	holder.Parent = gui
	for i = 0, 11 do
		local ray = Instance.new("Frame")
		ray.BorderSizePixel = 0
		ray.BackgroundColor3 = UIKit.GOLD
		ray.BackgroundTransparency = 1
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.new(0, 34, 1, 0)
		ray.Rotation = i * 15
		ray.ZIndex = 1
		ray.Parent = holder
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = ray
		ease(ray, 0.3, { BackgroundTransparency = 0.35 })
	end
	ease(holder, 2.2, { Rotation = 40 })
	task.delay(1.8, function()
		for _, r in ipairs(holder:GetChildren()) do
			if r:IsA("Frame") then ease(r, 0.4, { BackgroundTransparency = 1 }) end
		end
	end)
	task.delay(2.3, function() holder:Destroy() end)
end

local function wow(d)
	local vp = workspace.CurrentCamera.ViewportSize
	local centre = Vector2.new(vp.X / 2, vp.Y * 0.42)
	UIKit.sfx("ding", 1)
	rays(centre)
	Moment.ring(gui, centre, UIKit.GOLD, 320)
	local stamp = UIKit.outlined(gui, "SHIPPED!", UIKit.TYPE.money, UIKit.GREEN, {
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 420, 0, 70),
		Position = UDim2.new(0, centre.X, 0, centre.Y - 30), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5,
	})
	stamp.Rotation = -8
	local sc = Instance.new("UIScale")
	sc.Parent = stamp
	Moment.enter(sc, 0.3, 0.45)
	task.delay(0.9, function()
		local big = UIKit.outlined(gui, "+$0", UIKit.TYPE.money, UIKit.MONEY, {
			AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 320, 0, 60),
			Position = UDim2.new(0, centre.X, 0, centre.Y + 50), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5,
		})
		Moment.countUp(big, 0, d.pay, function(n) return "+" .. UIKit.money(math.floor(n)) end, 0.8)
		Moment.burst(gui, centre, 28, 260)
		task.delay(1.3, function()
			Moment.landMoney(Vector2.new(centre.X, centre.Y + 50), 16)
			ease(big, 0.4, { TextTransparency = 1 })
			ease(stamp, 0.4, { TextTransparency = 1 })
			for _, l in ipairs({ big, stamp }) do
				local st = l:FindFirstChildOfClass("UIStroke")
				if st then ease(st, 0.4, { Transparency = 1 }) end
			end
			task.delay(0.45, function() big:Destroy(); stamp:Destroy() end)
		end)
	end)
end

clientPaid.OnClientEvent:Connect(function(d)
	if type(d) ~= "table" or type(d.pay) ~= "number" then return end
	if d.wow then wow(d) return end
	local at = screenAt((typeof(d.at) == "Vector3" and d.at or Vector3.zero) + Vector3.new(0, 4, 0))
	local coder = d.who == "coder"
	pop("+" .. UIKit.money(d.pay), at, coder and UIKit.TYPE.title or UIKit.TYPE.headline, UIKit.MONEY)
	if (d.tip or 0) > 0 then
		pop("+" .. UIKit.money(d.tip) .. " TIP", at + Vector2.new(0, 34), UIKit.TYPE.label, UIKit.GOLD, 0.35)
	end
	Moment.landMoney(at, coder and 3 or 6)
	if not coder then UIKit.sfx("ding", 1.2, 0.5) end
end)
