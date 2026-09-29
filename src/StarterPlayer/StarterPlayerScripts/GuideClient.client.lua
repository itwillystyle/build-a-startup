--[[
	GuideClient v1 -- LocalScript in StarterPlayer -> StarterPlayerScripts.

	THE ARROW. Ghost Drivers' onboarding, copied: one objective at a time,
	a floating marker over the thing to touch, an arrow at the edge of the
	screen when it is off-screen, and one sentence at the top that says what
	to do. Nothing blocks, nothing dims, nothing needs reading twice.

	The SERVER decides the objective (player attributes Objective /
	ObjectiveText / ObjectivePos). This script only draws. If the attributes
	are nil the guide hides itself, so a finished player never sees it.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local UIKit = require(game:GetService("ReplicatedStorage"):WaitForChild("UIKit"))

local GOLD = UIKit.GOLD     -- v3.1: one palette (UIKit)
local INK = UIKit.INK

-- ============ 3D MARKER (one part, reused) ============

local marker = Instance.new("Part")
marker.Name = "GuideMarker"
marker.Shape = Enum.PartType.Cylinder     -- a fat cone reads as an arrow head from every angle
marker.Size = Vector3.new(1.2, 3.2, 3.2)
marker.Color = GOLD
marker.Material = Enum.Material.Neon
marker.Anchored = true
marker.CanCollide = false
marker.CanQuery = false
marker.CanTouch = false
marker.CastShadow = false
marker.Transparency = 1

local tip = Instance.new("WedgePart")
tip.Name = "Tip"
tip.Size = Vector3.new(2.2, 2.2, 2.2)
tip.Color = GOLD
tip.Material = Enum.Material.Neon
tip.Anchored = true
tip.CanCollide = false
tip.CanQuery = false
tip.CanTouch = false
tip.CastShadow = false
tip.Transparency = 1
tip.Parent = marker

local light = Instance.new("PointLight", marker)
light.Color = GOLD
light.Range = 14
light.Brightness = 1.4

local bb = Instance.new("BillboardGui")
bb.Name = "Label"
bb.Size = UDim2.new(0, 220, 0, 44)
bb.StudsOffset = Vector3.new(0, 3.4, 0)
bb.AlwaysOnTop = true
bb.MaxDistance = 200
bb.Parent = marker
local bbFrame = Instance.new("Frame")
bbFrame.Size = UDim2.new(1, 0, 1, 0)
bbFrame.BackgroundColor3 = INK
bbFrame.BackgroundTransparency = 0.15
bbFrame.BorderSizePixel = 0
bbFrame.Parent = bb
Instance.new("UICorner", bbFrame).CornerRadius = UDim.new(0, 10)
local bbStroke = Instance.new("UIStroke", bbFrame)
bbStroke.Color = GOLD
bbStroke.Thickness = 2
local bbText = Instance.new("TextLabel")
bbText.Size = UDim2.new(1, -12, 1, 0)
bbText.Position = UDim2.new(0, 6, 0, 0)
bbText.BackgroundTransparency = 1
bbText.Font = Enum.Font.FredokaOne
bbText.TextSize = 20
bbText.TextColor3 = GOLD
bbText.TextScaled = true
bbText.Text = ""
bbText.Parent = bbFrame

-- a beam from your feet to the target: the path, not just the destination
local beamEnd = Instance.new("Part")
beamEnd.Name = "GuideBeamEnd"
beamEnd.Size = Vector3.new(0.2, 0.2, 0.2)
beamEnd.Anchored = true
beamEnd.CanCollide = false
beamEnd.CanQuery = false
beamEnd.CanTouch = false
beamEnd.Transparency = 1
local a1 = Instance.new("Attachment", beamEnd)
local beam = Instance.new("Beam")
beam.Color = ColorSequence.new(GOLD)
beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0.15) })
beam.Width0 = 0.5
beam.Width1 = 1.4
beam.FaceCamera = true
beam.LightEmission = 0.6
beam.Segments = 1
beam.Attachment1 = a1
beam.Parent = beamEnd

local function attachBeam(char)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if not root then return end
	local a0 = root:FindFirstChild("GuideBeamStart") or Instance.new("Attachment")
	a0.Name = "GuideBeamStart"
	a0.Position = Vector3.new(0, -2.6, 0)
	a0.Parent = root
	beam.Attachment0 = a0
end
if player.Character then attachBeam(player.Character) end
player.CharacterAdded:Connect(attachBeam)

-- ============ SCREEN LAYER ============
--[[ v3.1 THE QUEST CARD. The top-centre strip collided with the right-hand
card at phone widths and truncated its own sentence ("Upgrade to GLASS…").
Now it is a card in the RIGHT COLUMN (Run a Restaurant!'s quest card), in
the same vertical list as the LAUNCH card so the two can never overlap: a
short title, a sub line, and for a purchase a GOAL METER (your cash / the
price) that turns into READY when you can afford it. The server sends
title / sub / cost separately. ]]

local UIS = game:GetService("UserInputService")
local isTouch = UIS.TouchEnabled and not UIS.KeyboardEnabled
local function words(t)
	if not t then return "" end
	if not isTouch then t = t:gsub("^Tap ", "Click "):gsub(" Tap ", " Click ") end
	return t
end

local gui = Instance.new("ScreenGui")
gui.Name = "Guide"
gui.ResetOnSpawn = false
gui.DisplayOrder = 9
gui.IgnoreGuiInset = true
gui.Enabled = false
UIKit.safe(gui)
gui.Parent = player:WaitForChild("PlayerGui")

--[[ v4.0 THE QUEST CARD, redesigned. His note: "'Build a design studio' UI and
similar titles still look like slop." It was a white box with one target icon
for every goal, grey text and a flat bar. Now a goal is a game object: a NEXT
GOAL tab, the goal's own rendered icon on a tinted tile, the title big, the
reward as a green chip, a chunky bar with a shine that sweeps while you save and
pulses READY, and a real completion beat (a check stamps down, confetti, the
next goal springs in). ]]
local ICON_FOR = { code = "code", watch = "code", wait = "code", hire = "hire", hire2 = "hire", recruit = "hire",
	carry = "hire", product = "rocket", spin = "rocket", hq = "hq", decor = "home", desk = "office",
	apartment = "key", car = "car" }
local ROOM_WORDS = { { "office", "office" }, { "studio", "studio" }, { "caf", "cafe" }, { "server", "servers" } }
local TINT = { code = UIKit.GREEN, hire = UIKit.BLUE, rocket = UIKit.ORANGE, hq = UIKit.BLUE, home = GOLD,
	office = UIKit.BLUE, studio = Color3.fromRGB(236, 120, 170), cafe = UIKit.ORANGE, servers = Color3.fromRGB(126, 136, 156),
	key = GOLD, car = UIKit.GREEN, target = GOLD }
local function iconFor(key, text)
	local t = string.lower(text or "")
	if key == "build" or key == "wing" or key == "wingup" then
		for _, w in ipairs(ROOM_WORDS) do if string.find(t, w[1], 1, true) then return w[2] end end
		return "hq"
	end
	if string.find(t, "apartment", 1, true) or string.find(t, "loft", 1, true) or string.find(t, "penthouse", 1, true) then return "key" end
	return ICON_FOR[key] or "target"
end

local column = UIKit.column()
local card = UIKit.card(column, { Name = "Quest", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 84), Visible = false }, { radius = 16, strokeWidth = 2 })
local cardStroke = card:FindFirstChildOfClass("UIStroke")
local tab = Instance.new("Frame")
tab.Name = "Tab"
tab.AnchorPoint = Vector2.new(0, 0.5)
tab.Position = UDim2.new(0, 12, 0, 0)
tab.Size = UDim2.new(0, 86, 0, 20)
tab.BackgroundColor3 = UIKit.INK
tab.BorderSizePixel = 0
tab.ZIndex = 4
tab.Parent = card
Instance.new("UICorner", tab).CornerRadius = UDim.new(1, 0)
UIKit.label(tab, "NEXT GOAL", 12, GOLD, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 }, UIKit.HEAD)
local disc = Instance.new("Frame")
disc.Name = "Tile"
disc.Position = UDim2.new(0, 10, 0, 16)
disc.Size = UDim2.new(0, 58, 0, 58)
disc.BackgroundColor3 = GOLD
disc.BorderSizePixel = 0
disc.Parent = card
Instance.new("UICorner", disc).CornerRadius = UDim.new(0, 14)
local tileStroke = Instance.new("UIStroke", disc)
tileStroke.Thickness = 2
local tileIcon = UIKit.art(disc, "target", 56, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -3), ZIndex = 3 })
local stamp = UIKit.art(disc, "check", 62, { Name = "Stamp", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), ZIndex = 6, Visible = false })
local function tint(name)
	local c = TINT[name] or GOLD
	disc.BackgroundColor3 = c:Lerp(Color3.new(1, 1, 1), 0.72)
	tileStroke.Color = c
end
local title = UIKit.label(card, "", 20, UIKit.INK, {
	Name = "Title", Position = UDim2.new(0, 78, 0, 14), Size = UDim2.new(1, -88, 0, 24),
	TextTruncate = Enum.TextTruncate.AtEnd,
}, UIKit.HEAD)
local chip = Instance.new("Frame")
chip.Name = "Reward"
chip.Position = UDim2.new(0, 78, 0, 44)
chip.Size = UDim2.new(0, 0, 0, 24)
chip.AutomaticSize = Enum.AutomaticSize.X
chip.BackgroundColor3 = UIKit.GREEN
chip.BorderSizePixel = 0
chip.Visible = false
chip.Parent = card
Instance.new("UICorner", chip).CornerRadius = UDim.new(1, 0)
local chipPad = Instance.new("UIPadding", chip)
chipPad.PaddingLeft = UDim.new(0, 10)
chipPad.PaddingRight = UDim.new(0, 10)
local chipText = UIKit.label(chip, "", 13, UIKit.TEXT, { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X }, UIKit.HEAD)
local sub = UIKit.label(card, "", 14, UIKit.CARD_MUTED, {
	Name = "Sub", Position = UDim2.new(0, 78, 0, 42), Size = UDim2.new(1, -88, 0, 32),
	TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
}, UIKit.HEAD)
local meter = Instance.new("Frame")
meter.Name = "Meter"
meter.BackgroundColor3 = UIKit.SURFACE_2
meter.BorderSizePixel = 0
meter.Position = UDim2.new(0, 10, 1, -32)
meter.Size = UDim2.new(1, -20, 0, 22)
meter.Visible = false
meter.ClipsDescendants = true
meter.Parent = card
Instance.new("UICorner", meter).CornerRadius = UDim.new(1, 0)
local fill = Instance.new("Frame")
fill.BackgroundColor3 = GOLD
fill.BorderSizePixel = 0
fill.Size = UDim2.new(0, 0, 1, 0)
fill.Parent = meter
Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
local fillGrad = Instance.new("UIGradient", fill)
fillGrad.Rotation = 90
fillGrad.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 205))
local shine = Instance.new("Frame")
shine.Name = "Shine"
shine.BackgroundColor3 = Color3.new(1, 1, 1)
shine.BorderSizePixel = 0
shine.Size = UDim2.new(1, 0, 1, 0)
shine.ZIndex = 2
shine.Parent = fill
Instance.new("UICorner", shine).CornerRadius = UDim.new(1, 0)
local shineGrad = Instance.new("UIGradient", shine)
shineGrad.Rotation = 20
shineGrad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1),
	NumberSequenceKeypoint.new(0.5, 0.5), NumberSequenceKeypoint.new(0.58, 1), NumberSequenceKeypoint.new(1, 1) })
local price = UIKit.label(meter, "", 15, UIKit.CARD_TEXT, {
	Size = UDim2.new(1, -12, 1, 0), Position = UDim2.new(0, 6, 0, 0), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3,
}, UIKit.HEAD)
local cardScale = Instance.new("UIScale", card)

--[[ v4.3 THE BIG GOAL. His Wilz run: "I don't see that I need the Loft, and
there are no goals at certain points." The quest card shows the NEXT step
(often a cheap one), so the thing the whole level is working toward was
invisible until the moment it became the cheapest buy. This small card sits
under the quest card all the time: the next HQ level with the apartment it
needs, then GO PUBLIC, then the spin-off, with a bar toward its full price. ]]
local big = UIKit.card(column, { Name = "BigGoal", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 82), Visible = false }, { radius = 14, strokeWidth = 2 })
local bigTab = Instance.new("Frame")
bigTab.AnchorPoint = Vector2.new(0, 0.5)
bigTab.Position = UDim2.new(0, 12, 0, 0)
bigTab.Size = UDim2.new(0, 74, 0, 18)
bigTab.BackgroundColor3 = UIKit.BLUE
bigTab.BorderSizePixel = 0
bigTab.ZIndex = 4
bigTab.Parent = big
Instance.new("UICorner", bigTab).CornerRadius = UDim.new(1, 0)
UIKit.label(bigTab, "BIG GOAL", 11, UIKit.TEXT, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 }, UIKit.HEAD)
local bigTitle = UIKit.label(big, "", 16, UIKit.INK, {
	Name = "Title", Position = UDim2.new(0, 12, 0, 12), Size = UDim2.new(1, -24, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd,
}, UIKit.HEAD)
local bigSub = UIKit.label(big, "", 12, UIKit.CARD_MUTED, {
	Name = "Sub", Position = UDim2.new(0, 12, 0, 32), Size = UDim2.new(1, -24, 0, 14), TextTruncate = Enum.TextTruncate.AtEnd,
}, UIKit.HEAD)
local bigUnlock = UIKit.label(big, "", 12, UIKit.darker(UIKit.GOLD, 0.6), {
	Name = "Unlock", Position = UDim2.new(0, 12, 0, 48), Size = UDim2.new(1, -24, 0, 14), TextTruncate = Enum.TextTruncate.AtEnd,
}, UIKit.HEAD)
local bigBar = Instance.new("Frame")
bigBar.Name = "Bar"
bigBar.BackgroundColor3 = UIKit.SURFACE_2
bigBar.BorderSizePixel = 0
bigBar.Position = UDim2.new(0, 12, 1, -14)
bigBar.Size = UDim2.new(1, -24, 0, 6)
bigBar.Parent = big
Instance.new("UICorner", bigBar).CornerRadius = UDim.new(1, 0)
local bigFill = Instance.new("Frame")
bigFill.BackgroundColor3 = UIKit.BLUE
bigFill.BorderSizePixel = 0
bigFill.Size = UDim2.new(0, 0, 1, 0)
bigFill.Parent = bigBar
Instance.new("UICorner", bigFill).CornerRadius = UDim.new(1, 0)
local bigCost
local function readBig()
	local t = player:GetAttribute("MilestoneTitle")
	local unlock = player:GetAttribute("MilestoneUnlock")
	bigTitle.Text = t or ""
	bigUnlock.Text = unlock and ("UNLOCKS: " .. unlock) or ""
	big.Size = UDim2.new(1, 0, 0, unlock and 82 or 66)
	bigSub.Text = player:GetAttribute("MilestoneSub") or ""
	bigCost = tonumber(player:GetAttribute("MilestoneCost"))
	bigBar.Visible = bigCost ~= nil and bigCost > 0
	big.Visible = t ~= nil and player:GetAttribute("NamingOpen") ~= true
end
for _, a in ipairs({ "MilestoneTitle", "MilestoneSub", "MilestoneCost", "MilestoneUnlock", "NamingOpen" }) do
	player:GetAttributeChangedSignal(a):Connect(readBig)
end
task.defer(readBig)

-- a finished goal: confetti bursts out of the tile and falls away
local function confetti()
	local colours = { UIKit.GREEN, GOLD, UIKit.BLUE, UIKit.ORANGE, Color3.fromRGB(236, 120, 170) }
	for i = 1, 16 do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = colours[(i % #colours) + 1]
		f.Size = UDim2.new(0, math.random(5, 9), 0, math.random(5, 9))
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.new(0, 39, 0, 45)
		f.ZIndex = 8
		f.Parent = card
		local a = math.random() * math.pi * 2
		local r = math.random(40, 90)
		TweenService:Create(f, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0, 39 + math.cos(a) * r, 0, 45 + math.sin(a) * r * 0.7 + 18),
			Rotation = math.random(-200, 200), BackgroundTransparency = 1,
		}):Play()
		task.delay(0.75, function() f:Destroy() end)
	end
end

-- edge arrow: sits on its own dark disc so it reads as a pointer, not part of a button
local edge = Instance.new("Frame")
edge.Name = "EdgeArrow"
edge.AnchorPoint = Vector2.new(0.5, 0.5)
edge.Size = UDim2.new(0, 70, 0, 70)
edge.BackgroundColor3 = INK
edge.BackgroundTransparency = 0.35
edge.Visible = false
edge.Parent = gui
Instance.new("UICorner", edge).CornerRadius = UDim.new(1, 0)
local arrow = UIKit.icon(edge, "up", 44, GOLD, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0) })
local edgeDist = UIKit.outlined(edge, "", 16, GOLD, {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 2), Size = UDim2.new(0, 110, 0, 20),
	TextXAlignment = Enum.TextXAlignment.Center,
})

-- ============ STATE ============

local target      -- Vector3 or nil
local lastKey
local cost        -- number or nil
local readyFor    -- the objective key we already chimed READY for

local function layout()
	local hasCost = cost ~= nil and cost > 0
	meter.Visible = hasCost
	-- the tile is 58 tall from y 16; the words sit beside it; the meter below both
	-- measure the wrapped height with TextService: TextBounds on a 1-px-tall label
	-- only reports the lines that fit, so the card stayed one line tall ("It's...")
	local w = math.max(40, sub.AbsoluteSize.X)
	local need = (sub.Text ~= "") and game:GetService("TextService"):GetTextSize(sub.Text, sub.TextSize, sub.Font, Vector2.new(w, 1000)).Y or 0
	local subH = (sub.Text ~= "") and (math.max(18, need) + 4) or 0
	sub.Size = UDim2.new(1, -88, 0, math.max(subH, 1))
	local words = math.max(74, 44 + math.max(subH, chip.Visible and 26 or 0))
	card.Size = UDim2.new(1, 0, 0, words + 10 + (hasCost and 32 or 0))
end
sub:GetPropertyChangedSignal("TextBounds"):Connect(layout)
sub:GetPropertyChangedSignal("Text"):Connect(layout)
sub:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() task.defer(layout) end)

--[[ v4.4 a reward reads as a green chip ("+25% money", "Unlocks STAR hires");
anything else as a hint line. His screenshot: the chip grows with its text and
nothing capped it, so "Start over with x1.5 money forever" ran out of the card
("...money forev"). Now the chip shrinks its text to fit (13 down to 10 pt) and
a line too long even then becomes the wrapped grey hint instead. ]]
local TextService = game:GetService("TextService")
local function chipSizeFor(text)
	local avail = (card.AbsoluteSize.X > 0 and card.AbsoluteSize.X or 250) - 88 - 22
	for size = 13, 10, -1 do
		if TextService:GetTextSize(text, size, chipText.Font, Vector2.new(2000, 100)).X <= avail then return size end
	end
	return nil
end
local function applySub()
	local subText = words(player:GetAttribute("ObjectiveSub"))
	local reward = subText ~= "" and (string.sub(subText, 1, 1) == "+" or string.find(subText, "Unlocks", 1, true) ~= nil
		or string.find(subText, "Room for", 1, true) ~= nil or string.find(subText, "money", 1, true) ~= nil)
	local size = reward and chipSizeFor(subText)
	if reward and not size then reward = false end
	chip.Visible = reward
	chipText.TextSize = size or 13
	chipText.Text = reward and subText or ""
	sub.Text = reward and "" or subText
	layout()
end
card:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() task.defer(applySub) end)

local function readObjective()
	local key = player:GetAttribute("Objective")
	local text = player:GetAttribute("ObjectiveText")
	local pos = player:GetAttribute("ObjectivePos")
	target = typeof(pos) == "Vector3" and pos or nil
	cost = tonumber(player:GetAttribute("ObjectiveCost"))

	if key ~= lastKey then
		if lastKey and key then
			-- the previous goal just finished: a check stamps down, confetti, then the next springs in
			title.Text = "DONE!"
			title.TextColor3 = UIKit.darker(UIKit.GREEN, 0.8)
			if cardStroke then cardStroke.Color = UIKit.GREEN end
			tileIcon.Visible = false
			stamp.Visible = true
			local ss = stamp:FindFirstChild("StampScale") or Instance.new("UIScale")
			ss.Name = "StampScale"
			ss.Parent = stamp
			ss.Scale = 2.2
			TweenService:Create(ss, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			confetti()
			UIKit.sfx("ding", 1.1)
			task.delay(1.0, function()
				stamp.Visible = false
				tileIcon.Visible = true
				title.TextColor3 = UIKit.INK
				if cardStroke then cardStroke.Color = UIKit.CARD_LINE end
				title.Text = words(player:GetAttribute("ObjectiveText"))
				local ic = iconFor(player:GetAttribute("Objective"), player:GetAttribute("ObjectiveText"))
				tileIcon.Image = UIKit.ART[ic] or UIKit.ART.target
				tint(ic)
				cardScale.Scale = 0.88
				TweenService:Create(cardScale, TweenInfo.new(0.34, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			end)
		else
			title.Text = words(text)
			local ic = iconFor(key, text)
			tileIcon.Image = UIKit.ART[ic] or UIKit.ART.target
			tint(ic)
		end
		lastKey = key
		readyFor = nil
	elseif title.TextColor3 == UIKit.INK then
		title.Text = words(text)
	end
	applySub()

	local show = key ~= nil and text ~= nil
	-- the LAUNCH card says "your app is ready" itself; the name box sits over everything
	card.Visible = show and key ~= "product" and player:GetAttribute("NamingOpen") ~= true
	gui.Enabled = show and player:GetAttribute("NamingOpen") ~= true
	local showMarker = show and target ~= nil
	marker.Transparency = showMarker and 0 or 1
	tip.Transparency = showMarker and 0 or 1
	bb.Enabled = false
	light.Enabled = showMarker
	marker.Parent = showMarker and workspace or nil
	beamEnd.Parent = showMarker and workspace or nil
	beam.Enabled = showMarker
end

for _, name in ipairs({ "Objective", "ObjectiveText", "ObjectivePos", "ObjectiveSub", "ObjectiveCost" }) do
	player:GetAttributeChangedSignal(name):Connect(readObjective)
end
readObjective()
player:GetAttributeChangedSignal("NamingOpen"):Connect(readObjective)

-- ============ PER-FRAME ============

local function cashNow()
	local l = player:FindFirstChild("leaderstats")
	local c = l and l:FindFirstChild("Cash")
	return c and c.Value or 0
end

-- where the arrow may sit: right of the left rail, left of the right column,
-- clear of the money at the top and WRITE CODE at the bottom (the old clamp put
-- it on the music button, pointing at it)
-- the arrow stays clear of the rail and of the right column's cards; below the
-- last card the whole right edge is free (the column frame is taller than its cards)
local function bounds(vp)
	local pg = player.PlayerGui
	local left, right = 60, vp.X - 60
	local rail = pg:FindFirstChild("Rail") and pg.Rail:FindFirstChild("Column")
	if rail then left = math.max(left, rail.AbsolutePosition.X + 90 + 44) end
	local col = pg:FindFirstChild("RightColumn") and pg.RightColumn:FindFirstChild("Column")
	local colBottom = 0
	if col then
		right = math.min(right, col.AbsolutePosition.X - 44)
		local l = col:FindFirstChildOfClass("UIListLayout")
		colBottom = col.AbsolutePosition.Y + (l and l.AbsoluteContentSize.Y or 0)
	end
	-- tiny or not-yet-laid-out screens: never hand math.clamp a max below its min
	-- (the column reports x = 0 for a frame at join, which made right < left)
	local top, bottom = 130, vp.Y - 140
	if right < left then right = left end
	if bottom < top then bottom = top end
	return left, right, top, bottom, colBottom
end

RunService.RenderStepped:Connect(function()
	-- v4.3 the big goal's bar
	if bigCost and bigCost > 0 and big.Visible then
		local pb = math.clamp(cashNow() / bigCost, 0, 1)
		bigFill.Size = UDim2.new(pb, 0, 1, 0)
		bigFill.BackgroundColor3 = pb >= 1 and UIKit.GREEN or UIKit.BLUE
	end
	-- the goal meter: cash / price, then READY
	if cost and cost > 0 and card.Visible then
		local have = cashNow()
		local p = math.clamp(have / cost, 0, 1)
		fill.Size = UDim2.new(p, 0, 1, 0)
		shineGrad.Offset = Vector2.new(((os.clock() * 0.55) % 2.4) - 1.2, 0)
		if p >= 1 then
			fill.BackgroundColor3 = UIKit.GREEN
			price.Text = "READY!  GO  >"
			if cardStroke then
				cardStroke.Color = UIKit.GREEN
				cardStroke.Thickness = 2 + 1.5 * (0.5 + 0.5 * math.sin(os.clock() * 5))
			end
			if readyFor ~= lastKey then
				readyFor = lastKey
				UIKit.sfx("ding")
				cardScale.Scale = 1.08
				TweenService:Create(cardScale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			end
		else
			fill.BackgroundColor3 = GOLD
			price.Text = UIKit.money(have) .. " / " .. UIKit.money(cost)
			if cardStroke and title.TextColor3 == UIKit.INK then
				cardStroke.Color = UIKit.CARD_LINE
				cardStroke.Thickness = 2
			end
		end
	end

	if not target then edge.Visible = false return end
	local t = os.clock()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local dist = root and (root.Position - target).Magnitude or 0
	-- bob + spin over the target; lower when close, so a ceiling or the HUD never hides it
	local y = (dist < 24 and 4.5 or 7.5) + math.sin(t * 3.2) * 0.5
	local at = target + Vector3.new(0, y, 0)
	marker.CFrame = CFrame.new(at) * CFrame.Angles(0, t * 1.6, 0) * CFrame.Angles(0, 0, math.rad(90))
	tip.CFrame = CFrame.new(at - Vector3.new(0, 2.4, 0)) * CFrame.Angles(0, t * 1.6, 0) * CFrame.Angles(math.rad(180), 0, 0)
	beamEnd.Position = target + Vector3.new(0, 0.6, 0)

	-- screen-edge arrow when the target is off-screen
	local vp = camera.ViewportSize
	local sp, onScreen = camera:WorldToViewportPoint(target + Vector3.new(0, 4, 0))
	if (onScreen and sp.Z > 0) or dist < 16 then edge.Visible = false return end
	-- a menu or the decor sheet owns the screen while it is open
	if player:GetAttribute("BuildModeOpen") == true or player:GetAttribute("NamingOpen") == true then edge.Visible = false return end
	local left, right, top, bottom, colBottom = bounds(vp)
	local centre = Vector2.new(vp.X / 2, vp.Y / 2)
	if sp.Z < 0 then
		-- behind you: a "turn" arrow on the side you should turn to, at mid
		-- height (it used to sit dead centre, on top of your own character)
		local rel = camera.CFrame:PointToObjectSpace(target)
		local goRight = rel.X >= 0
		if goRight then
			-- the right screen edge, just under the column's last card
			local y = math.clamp(math.max(vp.Y * 0.5, colBottom + 56), top, bottom)
			edge.Position = UDim2.new(0, vp.X - 60, 0, y)
		else
			edge.Position = UDim2.new(0, left, 0, math.clamp(vp.Y * 0.5, top, bottom))
		end
		arrow.Rotation = goRight and 90 or -90
		edgeDist.Text = ("turn  %dm"):format(math.floor(dist / 3.5 + 0.5))
		edge.Visible = true
		return
	end
	local dir = Vector2.new(sp.X - centre.X, sp.Y - centre.Y)
	if dir.Magnitude < 1 then dir = Vector2.new(0, -1) end
	dir = dir.Unit
	local half = Vector2.new(vp.X / 2 - 56, vp.Y / 2 - 56)
	local scale = math.min(half.X / math.max(math.abs(dir.X), 1e-3), half.Y / math.max(math.abs(dir.Y), 1e-3))
	local p = centre + dir * scale
	local r = math.max(left, (p.Y > colBottom + 40) and (vp.X - 60) or right)
	p = Vector2.new(math.clamp(p.X, left, r), math.clamp(p.Y, top, bottom))
	edge.Position = UDim2.new(0, p.X, 0, p.Y)
	arrow.Rotation = math.deg(math.atan2(dir.Y, dir.X)) + 90
	edgeDist.Text = ("%dm"):format(math.floor(dist / 3.5 + 0.5))
	edge.Visible = true
end)
