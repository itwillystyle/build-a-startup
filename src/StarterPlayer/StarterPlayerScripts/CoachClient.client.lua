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

-- v5: where the card goes. Beside the target when there is room, else above or
-- below it; always fully on screen, under Roblox's top bar (58 px), clear of the
-- rail, and on a touch screen off the thumbstick and the jump button. Found on a
-- phone: the LAUNCH tip went left of the centred button, ran off the screen
-- ("UNCH your app!") and sat on the thumbstick.
local isTouch = game:GetService("UserInputService").TouchEnabled
local function place(tp, ts, vp, W, H)
	local centre = tp + ts / 2
	local function blocked(x, y)
		if x < 8 or y < 64 or x + W > vp.X - 8 or y + H > vp.Y - 8 then return true end
		if isTouch then
			if x < 170 and y + H > vp.Y - 170 then return true end              -- the thumbstick
			if x + W > vp.X - 180 and y + H > vp.Y - 160 then return true end   -- the jump button
		end
		return false
	end
	local rr = UIKit.railRight()
	local midY = math.clamp(centre.Y - H / 2, 64, math.max(64, vp.Y - H - 8))
	-- beside a target, the card also stays above the bottom action slot (WRITE CODE /
	-- LAUNCH and its caption own the bottom ~118 px of the screen)
	local sideY = math.min(midY, math.max(64, vp.Y - 118 - H))
	local midX = math.clamp(centre.X - W / 2, 8, math.max(8, vp.X - W - 8))
	local at = {
		right = function() return math.max(tp.X + ts.X + 40, tp.X < rr and rr + 30 or 0), sideY end,
		left = function() return tp.X - W - 40, sideY end,
		above = function() return midX, tp.Y - H - 40 end,
		below = function() return midX, tp.Y + ts.Y + 40 end,
	}
	local order
	if centre.Y > vp.Y * 0.6 then
		order = { "above", centre.X < vp.X / 2 and "right" or "left", "below" }
	elseif centre.X < vp.X * 0.4 then
		order = { "right", "below", "above", "left" }
	elseif centre.X > vp.X * 0.6 then
		order = { "left", "below", "above", "right" }
	else
		order = { "below", "above", "right", "left" }
	end
	for _, side in ipairs(order) do
		local x, y = at[side]()
		if not blocked(x, y) then return side, x, y end
	end
	local x, y = at[order[1]]()
	return order[1], math.clamp(x, 8, math.max(8, vp.X - W - 8)), math.clamp(y, 64, math.max(64, vp.Y - H - 8))
end
-- the bouncing arrow sits between the card and the target, pointing at the target
local ARROW = {
	right = function(x, y, W, H, c, bob) return -90, x - 20 - bob, c.Y end,
	left = function(x, y, W, H, c, bob) return 90, x + W + 20 + bob, c.Y end,
	-- off-centre: a bottom button carries its caption ("APP READY!") centred above it
	above = function(x, y, W, H, c, bob) return 180, math.clamp(c.X + 76, x + 24, x + W - 24), y + H + 20 + bob end,
	below = function(x, y, W, H, c, bob) return 0, c.X, y - 20 - bob end,
}

local function finish(report)
	local c = current
	if not c then return end
	current = nil
	for _, k in ipairs(c.conns) do k:Disconnect() end
	if c.frame then c.frame:Destroy() end
	if c.ring then c.ring:Destroy() end
	for _, w in ipairs(c.washes or {}) do w:Destroy() end
	if report then seenRemote:FireServer(c.id) end
	if c.done then c.done() end
end

local function build(id, target, done)
	local W, H = 290, 140
	local card = UIKit.card(gui, { Name = "CoachCard", Size = UDim2.new(0, W, 0, H), ZIndex = 2 }, { radius = 16, strokeWidth = 3 })
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then stroke.Color = UIKit.GOLD end
	UIKit.label(card, player:GetAttribute("CoachTitle") or "", 20, UIKit.INK, {
		Position = UDim2.new(0, 14, 0, 10), Size = UDim2.new(1, -28, 0, 24), ZIndex = 3,
	}, UIKit.HEAD)
	UIKit.label(card, player:GetAttribute("CoachBody") or "", 16, UIKit.INK_SOFT, {
		Position = UDim2.new(0, 14, 0, 38), Size = UDim2.new(1, -28, 0, 44), TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 3,
	}, UIKit.BODY)
	-- v5: a quiet button: the thing it points at is the loud one
	local ok = UIKit.button(card, "GOT IT", UIKit.SURFACE_2, {
		Name = "GotIt", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -12), Size = UDim2.new(0, 120, 0, 44), ZIndex = 4,
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

	-- v5: a rail target on a 2-wide grid: the arrow has to cross the neighbouring
	-- tile, so every other tile is washed out and only the target stays bright
	local washes = {}
	local railCol = player.PlayerGui:FindFirstChild("Rail") and player.PlayerGui.Rail:FindFirstChild("Column")
	if railCol and target:IsDescendantOf(railCol) then
		for _, tile in ipairs(railCol:GetChildren()) do
			if tile:IsA("GuiObject") and tile ~= target and tile.Visible then
				local w = Instance.new("Frame")
				w.Name = "CoachWash"
				w.BackgroundColor3 = UIKit.SURFACE
				w.BackgroundTransparency = 0.3
				w.BorderSizePixel = 0
				w.Size = UDim2.new(1, 0, 1, 0)
				w.ZIndex = 50
				w.Parent = tile
				Instance.new("UICorner", w).CornerRadius = UDim.new(0, UIKit.RADIUS.md)
				table.insert(washes, w)
			end
		end
	end
	local c = { id = id, frame = card, ring = ring, arrow = arrow, washes = washes, conns = {}, done = done }
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
		local side, x, y = place(tp, ts, vp, W, H)
		card.Position = UDim2.fromOffset(x, y)
		local rot, ax, ay = ARROW[side](x, y, W, H, centre, bob)
		arrow.Rotation = rot                                        -- the icon points up at 0
		arrow.Position = UDim2.fromOffset(ax, ay)
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

-- the tip shows after a calm moment and hides (does not close) while anything else is on screen.
-- v5: "anything else" includes the goal itself: never while the goal's edge arrow
-- is up (two gold arrows pointing different ways at minute 1), and never in the
-- first 20 s of a new goal (let the player start on it first)
local goalSince = os.clock()
player:GetAttributeChangedSignal("Objective"):Connect(function() goalSince = os.clock() end)
local function goalBusy()
	if os.clock() - goalSince < 20 then return true end
	local guide = player.PlayerGui:FindFirstChild("Guide")
	local edge = guide and guide.Enabled and guide:FindFirstChild("EdgeArrow")
	return (edge and edge.Visible) == true   -- edge is `false` while the guide is hidden (a cutscene)
end
local calmSince
local function setShown(c, on)
	if c.frame then c.frame.Visible = on end
	if c.ring then c.ring.Visible = on end
	if c.arrow then c.arrow.Visible = on end
	for _, w in ipairs(c.washes or {}) do w.Visible = on end
end
task.spawn(function()
	while true do
		task.wait(0.2)
		local id = player:GetAttribute("CoachTip")
		if current and current.id ~= id then finish(false) end
		-- v5: also any menu or decision card (a BAG tip opened on top of the spin-off confirm)
		local busy = Notify.busy() or goalBusy() or UIKit.menuOpen()
		if busy then calmSince = nil elseif not calmSince then calmSince = os.clock() end
		if current then
			setShown(current, not busy)
		elseif id and calmSince and os.clock() - calmSince > 1.5 then
			local target = findTarget(player:GetAttribute("CoachTarget"))
			if shownOnScreen(target) then build(id, target, nil) end
		end
	end
end)
