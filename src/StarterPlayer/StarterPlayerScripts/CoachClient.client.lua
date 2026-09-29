--[[ CoachClient (v4.3): one-time HUD explanations.

His Wilz run: LAUNCH was never pressed in 19 minutes, and BAG, INDEX, RANKS and
the daily reward were never explained. The server (Journey.tip) decides WHICH
button to explain and WHEN (one at a time, never while carrying or driving,
25 s apart); this draws a card beside that button with a bouncing arrow and a
pulsing ring on the button, and reports it read on GOT IT or when the button
itself is used. It never HOLDS a Notify lane (a tip waiting for you would
queue the level-up banner and the rare-hire reveal behind it: caught live).
It shows after 1.5 s of calm (Notify.busy() false) and steps aside, hidden,
whenever something else takes the screen, then comes back. ]]
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local UIKit = require(RS:WaitForChild("UIKit"))
local Notify = require(RS:WaitForChild("Notify"))
local seenRemote = RS:WaitForChild("SVRemotes"):WaitForChild("CoachSeen")

local gui = Instance.new("ScreenGui")
gui.Name = "Coach"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 30
gui.Parent = player:WaitForChild("PlayerGui")

local function findTarget(path)
	local node = player:FindFirstChild("PlayerGui")
	for part in string.gmatch(path or "", "[^%.]+") do
		node = node and node:FindFirstChild(part)
	end
	return node
end

local function shownOnScreen(g)
	if not g or not g:IsA("GuiObject") or not g.Visible then return false end
	local sg = g:FindFirstAncestorOfClass("ScreenGui")
	if sg and not sg.Enabled then return false end
	local p = g.Parent
	while p and p:IsA("GuiObject") do
		if not p.Visible then return false end
		p = p.Parent
	end
	return g.AbsoluteSize.X > 4
end

local current   -- { id, frame, ring, conns, done }

local function finish(report)
	local c = current
	if not c then return end
	current = nil
	for _, k in ipairs(c.conns) do k:Disconnect() end
	if c.frame then c.frame:Destroy() end
	if c.ring then c.ring:Destroy() end
	if report then seenRemote:FireServer(c.id) end
	if c.done then c.done() end
end

local function build(id, target, done)
	local W, H = 290, 132
	local card = UIKit.card(gui, { Name = "CoachCard", Size = UDim2.new(0, W, 0, H), ZIndex = 2 }, { radius = 16, strokeWidth = 3 })
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then stroke.Color = UIKit.GOLD end
	UIKit.label(card, player:GetAttribute("CoachTitle") or "", 20, UIKit.INK, {
		Position = UDim2.new(0, 14, 0, 10), Size = UDim2.new(1, -28, 0, 24), ZIndex = 3,
	}, UIKit.HEAD)
	UIKit.label(card, player:GetAttribute("CoachBody") or "", 14, UIKit.CARD_MUTED, {
		Position = UDim2.new(0, 14, 0, 38), Size = UDim2.new(1, -28, 0, 44), TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 3,
	}, UIKit.HEAD)
	local ok = UIKit.button(card, "GOT IT", UIKit.GREEN, {
		Name = "GotIt", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -10), Size = UDim2.new(0, 110, 0, 36), ZIndex = 4,
	}, { textSize = 18 })
	local arrow = UIKit.icon(gui, "up", 40, UIKit.GOLD, { Name = "CoachArrow", AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 3 })
	arrow.Parent = card.Parent
	-- a ring on the button itself
	local ring = Instance.new("Frame")
	ring.Name = "CoachRing"
	ring.BackgroundTransparency = 1
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.ZIndex = 1
	ring.Parent = gui
	Instance.new("UICorner", ring).CornerRadius = UDim.new(0, 18)
	local rs = Instance.new("UIStroke", ring)
	rs.Color = UIKit.GOLD
	rs.Thickness = 4

	local c = { id = id, frame = card, ring = ring, arrow = arrow, conns = {}, done = done }
	current = c
	table.insert(c.conns, ok.Activated:Connect(function() finish(true) end))
	if target:IsA("GuiButton") then
		table.insert(c.conns, target.Activated:Connect(function() finish(true) end))
	end
	local t0 = os.clock()
	table.insert(c.conns, RunService.RenderStepped:Connect(function()
		if not target.Parent or not shownOnScreen(target) then return end
		-- AbsolutePosition is in one shared space for every ScreenGui, but this gui
		-- ignores the top-bar inset: subtract its own origin or everything sits 58 px high
		local vp = gui.AbsoluteSize
		local tp, ts = target.AbsolutePosition - gui.AbsolutePosition, target.AbsoluteSize
		local centre = tp + ts / 2
		local bob = math.sin((os.clock() - t0) * 6) * 6
		ring.Position = UDim2.fromOffset(centre.X, centre.Y)
		ring.Size = UDim2.fromOffset(ts.X + 14, ts.Y + 14)
		rs.Transparency = 0.25 + 0.35 * (0.5 + 0.5 * math.sin((os.clock() - t0) * 5))
		local leftSide = centre.X < vp.X / 2
		local x = leftSide and (tp.X + ts.X + 40) or (tp.X - W - 40)
		local y = math.clamp(centre.Y - H / 2, 8, vp.Y - H - 8)
		card.Position = UDim2.fromOffset(x, y)
		arrow.Rotation = leftSide and -90 or 90                    -- the icon points up at 0
		arrow.Position = UDim2.fromOffset(leftSide and (tp.X + ts.X + 20 + bob) or (tp.X - 20 - bob), centre.Y)
	end))
	table.insert(c.conns, player:GetAttributeChangedSignal("CoachTip"):Connect(function()
		if player:GetAttribute("CoachTip") ~= id then finish(false) end
	end))
	card.Destroying:Connect(function() if arrow then arrow:Destroy() end end)
	local sc = Instance.new("UIScale", card)
	sc.Scale = 0.7
	TweenService:Create(sc, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	UIKit.sfx("ding", 1.25, 0.4)
end

-- the tip shows after a calm moment and hides (does not close) while anything else is on screen
local calmSince
local function setShown(c, on)
	if c.frame then c.frame.Visible = on end
	if c.ring then c.ring.Visible = on end
	if c.arrow then c.arrow.Visible = on end
end
task.spawn(function()
	while true do
		task.wait(0.2)
		local id = player:GetAttribute("CoachTip")
		if current and current.id ~= id then finish(false) end
		local busy = Notify.busy()
		if busy then calmSince = nil elseif not calmSince then calmSince = os.clock() end
		if current then
			setShown(current, not busy)
		elseif id and calmSince and os.clock() - calmSince > 1.5 then
			local target = findTarget(player:GetAttribute("CoachTarget"))
			if shownOnScreen(target) then build(id, target, nil) end
		end
	end
end)
