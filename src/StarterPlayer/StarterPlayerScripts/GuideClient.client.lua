--[[
	GuideClient v5 -- LocalScript in StarterPlayer -> StarterPlayerScripts.

	THE GOAL. One objective at a time, drawn three ways that agree:
	  - the GOAL CARD (top of the right column): the goal's own icon, a short
	    title, one sub line, and for a purchase a meter (cash / price)
	  - the PIN over the target in the world: the SAME icon on a paper disc,
	    bobbing, with a pulsing ring on the ground and a beam from your feet
	  - the EDGE ARROW when the target is off screen

	The SERVER decides the objective (player attributes Objective /
	ObjectiveText / ObjectivePos / ObjectiveSub / ObjectiveCost, and the long
	goal as Milestone*). This script only draws. No attributes = no guide.

	v5 (29 Sep UI pass; ui_audit/CRITIQUE-v45.md):
	  - ONE card. BIG GOAL was a second card with 11-12 px text; it is now a
	    footer line of this card, hidden during the first minutes (a $3.8K goal
	    at $0 was a second "next" before you had done anything)
	  - nothing under 14 px, and nothing shrinks to fit: long lines wrap
	  - the card is tappable: the camera turns to face the goal (the old
	    "READY! GO >" looked like a button and did nothing)
	  - DONE! only when a goal was actually finished (a purchase landed, or a
	    free goal moved on). A goal swapping for a cheaper one says nothing,
	    and the LAUNCH interruption never stamps DONE on the goal underneath
	  - the world marker is the goal's icon on a pin, not two Neon slabs
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local Cine = ReplicatedStorage:FindFirstChild("Cine") and require(ReplicatedStorage.Cine)

local GOLD, INK = UIKit.GOLD, UIKit.INK

local function tween(o, t, props, style)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- which rendered icon a goal wears (the card and the pin show the same one)
local ICON_FOR = { code = "code", watch = "code", wait = "code", hire = "hire", hire2 = "hire", recruit = "hire",
	carry = "hire", product = "rocket", spin = "rocket", hq = "hq", decor = "home", desk = "office",
	apartment = "key", car = "car" }
local ROOM_WORDS = { { "office", "office" }, { "studio", "studio" }, { "caf", "cafe" }, { "server", "servers" } }
local TINT = { code = UIKit.GREEN, hire = UIKit.BLUE, rocket = UIKit.ORANGE, hq = UIKit.BLUE, home = UIKit.GREEN,
	office = UIKit.BLUE, studio = UIKit.PINK, cafe = UIKit.ORANGE, servers = Color3.fromRGB(126, 136, 156),
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

local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local function words(t)
	if not t then return "" end
	if not isTouch then t = t:gsub("^Tap ", "Click "):gsub(" Tap ", " Click ") end
	return t
end

-- ============ THE PIN (world) ============

local pinPart = Instance.new("Part")
pinPart.Name = "GuidePin"
pinPart.Size = Vector3.new(0.2, 0.2, 0.2)
pinPart.Transparency = 1
pinPart.Anchored = true
pinPart.CanCollide = false
pinPart.CanQuery = false
pinPart.CanTouch = false
pinPart.CastShadow = false

local pin = Instance.new("BillboardGui")
pin.Name = "Pin"
pin.Size = UDim2.new(0, 72, 0, 88)
pin.AlwaysOnTop = true          -- a goal behind a wall still shows where it is
pin.MaxDistance = 600
pin.LightInfluence = 0
pin.Parent = pinPart
local pinScale = Instance.new("UIScale", pin)
-- the tail: a paper diamond under the disc, so the pin points at the spot
local tail = Instance.new("Frame")
tail.AnchorPoint = Vector2.new(0.5, 0.5)
tail.Position = UDim2.new(0.5, 0, 0, 64)
tail.Size = UDim2.new(0, 22, 0, 22)
tail.Rotation = 45
tail.BackgroundColor3 = UIKit.PAPER
tail.BorderSizePixel = 0
tail.Parent = pin
local tailStroke = Instance.new("UIStroke", tail)
tailStroke.Color = INK
tailStroke.Thickness = 3
local disc = Instance.new("Frame")
disc.AnchorPoint = Vector2.new(0.5, 0)
disc.Position = UDim2.new(0.5, 0, 0, 2)
disc.Size = UDim2.new(0, 64, 0, 64)
disc.BackgroundColor3 = UIKit.PAPER
disc.BorderSizePixel = 0
disc.ZIndex = 2
disc.Parent = pin
Instance.new("UICorner", disc).CornerRadius = UDim.new(1, 0)
local discStroke = Instance.new("UIStroke", disc)
discStroke.Color = INK
discStroke.Thickness = 3
local pinIcon = UIKit.art(disc, "target", 50, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -1), ZIndex = 3 })

-- a ring on the ground where you should stand
local ring = Instance.new("Part")
ring.Name = "GuideRing"
ring.Shape = Enum.PartType.Cylinder
ring.Size = Vector3.new(0.12, 8, 8)
ring.Color = GOLD
ring.Material = Enum.Material.Neon
ring.Transparency = 0.6
ring.Anchored = true
ring.CanCollide = false
ring.CanQuery = false
ring.CanTouch = false
ring.CastShadow = false

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
beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0.25) })
beam.Width0 = 0.4
beam.Width1 = 1.1
beam.FaceCamera = true
beam.LightEmission = 0.4
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
if player.Character then task.spawn(attachBeam, player.Character) end
player.CharacterAdded:Connect(attachBeam)

-- ============ THE GOAL CARD (screen) ============

local gui = Instance.new("ScreenGui")
gui.Name = "Guide"
gui.ResetOnSpawn = false
gui.DisplayOrder = 9
gui.IgnoreGuiInset = true
gui.Enabled = false
UIKit.safe(gui)
gui.Parent = player:WaitForChild("PlayerGui")

local PAD, TILE = 10, 52
local TEXT_X = PAD + TILE + 10
local column = UIKit.column()
local card = UIKit.card(column, { Name = "Quest", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 84), Visible = false })
local cardStroke = card:FindFirstChildOfClass("UIStroke")
local cardScale = Instance.new("UIScale", card)

local tile = Instance.new("Frame")
tile.Name = "Tile"
tile.Position = UDim2.new(0, PAD, 0, PAD)
tile.Size = UDim2.new(0, TILE, 0, TILE)
tile.BackgroundColor3 = UIKit.GOLD_LIGHT
tile.BorderSizePixel = 0
tile.Parent = card
Instance.new("UICorner", tile).CornerRadius = UDim.new(0, UIKit.RADIUS.md)
local tileStroke = Instance.new("UIStroke", tile)
tileStroke.Thickness = 2
local tileIcon = UIKit.art(tile, "target", 50, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -2), ZIndex = 3 })
local stamp = UIKit.art(tile, "check", 56, { Name = "Stamp", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), ZIndex = 6, Visible = false })
local function tint(name)
	local c = TINT[name] or GOLD
	tile.BackgroundColor3 = UIKit.light(c)
	tileStroke.Color = UIKit.deep(c)
end

local title = UIKit.label(card, "", 20, UIKit.INK, {
	Name = "Title", Position = UDim2.new(0, TEXT_X, 0, PAD), Size = UDim2.new(1, -(TEXT_X + PAD), 0, 24),
	TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
}, UIKit.HEAD)
local sub = UIKit.label(card, "", 16, UIKit.MUTED_TEXT, {
	Name = "Sub", Position = UDim2.new(0, TEXT_X, 0, 36), Size = UDim2.new(1, -(TEXT_X + PAD), 0, 20),
	TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
}, UIKit.BODY)
-- a reward reads as a green chip ("x1.5 money, forever", "Unlocks STAR hires"); it
-- wraps to a second line instead of shrinking (v4.4 shrank it to 10 pt)
local chip = Instance.new("TextLabel")
chip.Name = "Reward"
chip.Position = UDim2.new(0, TEXT_X, 0, 36)
chip.Size = UDim2.new(1, -(TEXT_X + PAD), 0, 24)
chip.BackgroundColor3 = UIKit.GREEN_LIGHT
chip.BorderSizePixel = 0
chip.TextColor3 = UIKit.GREEN_DEEP
chip.TextSize = 14
chip.TextWrapped = true
chip.TextXAlignment = Enum.TextXAlignment.Left
chip.Visible = false
UIKit.setFont(chip, UIKit.BODY)
chip.Parent = card
Instance.new("UICorner", chip).CornerRadius = UDim.new(0, UIKit.RADIUS.sm)
local chipPad = Instance.new("UIPadding", chip)
chipPad.PaddingLeft = UDim.new(0, 8); chipPad.PaddingRight = UDim.new(0, 8)
chipPad.PaddingTop = UDim.new(0, 3); chipPad.PaddingBottom = UDim.new(0, 3)

local meter = Instance.new("Frame")
meter.Name = "Meter"
meter.BackgroundColor3 = UIKit.SURFACE_2
meter.BorderSizePixel = 0
meter.Size = UDim2.new(1, -2 * PAD, 0, 22)
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
local shine = Instance.new("Frame")
shine.Name = "Shine"
shine.BackgroundColor3 = UIKit.PAPER
shine.BorderSizePixel = 0
shine.Size = UDim2.new(1, 0, 1, 0)
shine.ZIndex = 2
shine.Parent = fill
Instance.new("UICorner", shine).CornerRadius = UDim.new(1, 0)
local shineGrad = Instance.new("UIGradient", shine)
shineGrad.Rotation = 20
shineGrad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1),
	NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(0.58, 1), NumberSequenceKeypoint.new(1, 1) })
local price = UIKit.label(meter, "", 14, UIKit.INK, {
	Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 8, 0, 0), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3,
}, UIKit.HEAD)

-- the BIG GOAL, as a quiet footer (v5: was its own card)
local footer = Instance.new("Frame")
footer.Name = "BigGoal"
footer.BackgroundTransparency = 1
footer.Size = UDim2.new(1, -2 * PAD, 0, 46)
footer.Visible = false
footer.Parent = card
local rule = Instance.new("Frame")
rule.BackgroundColor3 = UIKit.LINE_LIGHT
rule.BorderSizePixel = 0
rule.Size = UDim2.new(1, 0, 0, 2)
rule.Parent = footer
local bigTitle = UIKit.label(footer, "", 14, UIKit.INK_SOFT, {
	Position = UDim2.new(0, 0, 0, 8), Size = UDim2.new(1, 0, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd,
}, UIKit.HEAD)
local bigSub = UIKit.label(footer, "", 14, UIKit.MUTED_TEXT, {
	Position = UDim2.new(0, 0, 0, 26), Size = UDim2.new(1, 0, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd,
}, UIKit.BODY)
local bigBar = Instance.new("Frame")
bigBar.BackgroundColor3 = UIKit.SURFACE_2
bigBar.BorderSizePixel = 0
bigBar.AnchorPoint = Vector2.new(1, 0)
bigBar.Position = UDim2.new(1, 0, 0, 13)
bigBar.Size = UDim2.new(0, 56, 0, 8)
bigBar.Parent = footer
Instance.new("UICorner", bigBar).CornerRadius = UDim.new(1, 0)
local bigFill = Instance.new("Frame")
bigFill.BackgroundColor3 = UIKit.BLUE
bigFill.BorderSizePixel = 0
bigFill.Size = UDim2.new(0, 0, 1, 0)
bigFill.Parent = bigBar
Instance.new("UICorner", bigFill).CornerRadius = UDim.new(1, 0)

-- the whole card is a button: tap it and the camera turns to face the goal
local hit = Instance.new("TextButton")
hit.Name = "Hit"
hit.BackgroundTransparency = 1
hit.Text = ""
hit.Size = UDim2.new(1, 0, 1, 0)
hit.ZIndex = 20
hit.Parent = card

-- edge arrow: a gold sticker with an ink arrow and the distance under it
local edge = Instance.new("Frame")
edge.Name = "EdgeArrow"
edge.AnchorPoint = Vector2.new(0.5, 0.5)
edge.Size = UDim2.new(0, 60, 0, 60)
edge.BackgroundColor3 = GOLD
edge.Visible = false
edge.Parent = gui
Instance.new("UICorner", edge).CornerRadius = UDim.new(1, 0)
local edgeStroke = Instance.new("UIStroke", edge)
edgeStroke.Color = INK
edgeStroke.Thickness = 3
local arrow = UIKit.icon(edge, "up", 36, INK, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0) })
local edgeDist = UIKit.outlined(edge, "", 16, UIKit.TEXT, {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 4), Size = UDim2.new(0, 110, 0, 20),
	TextXAlignment = Enum.TextXAlignment.Center,
})

-- ============ STATE ============

local target      -- Vector3 or nil
local lastKey
local cost        -- number or nil
local lastCost
local readyFor    -- the objective key we already chimed READY for
local stamping = false

local function cashNow()
	local l = player:FindFirstChild("leaderstats")
	local c = l and l:FindFirstChild("Cash")
	return c and c.Value or 0
end
-- the last 2.5 s of cash, so a goal change can tell "you bought it" from "a cheaper goal came up"
local history = {}
local function recentMax()
	local m = cashNow()
	for _, h in ipairs(history) do m = math.max(m, h[2]) end
	return m
end

local function textHeight(label, width)
	if label.Text == "" then return 0 end
	local fontSize = label.TextSize
	local ok, size = pcall(function()
		local p = Instance.new("GetTextBoundsParams")
		p.Text = label.Text
		p.Font = label.FontFace
		p.Size = fontSize
		p.Width = width
		return TextService:GetTextBoundsAsync(p)
	end)
	if ok and size then return size.Y end
	return TextService:GetTextSize(label.Text, fontSize, Enum.Font.FredokaOne, Vector2.new(width, 1000)).Y
end

local function bigVisible()
	if player:GetAttribute("NamingOpen") == true then return false end
	if not player:GetAttribute("MilestoneTitle") then return false end
	-- not in the first minutes: before the first building a $3.8K goal at $0 is a second "next"
	local raw = player:GetAttribute("IncomeRooms") or ""
	local built = raw:find("OFFICE", 1, true) or raw:find("STUDIO", 1, true) or raw:find("CAFE", 1, true) or raw:find("SERVER", 1, true)
	return (player:GetAttribute("HQLevel") or 1) >= 2 or built ~= nil
end

local function layout()
	local w = card.AbsoluteSize.X > 0 and card.AbsoluteSize.X or 250
	local textW = w - TEXT_X - PAD
	local th = math.max(24, textHeight(title, textW) + 2)
	title.Size = UDim2.new(1, -(TEXT_X + PAD), 0, th)
	local y = PAD + th + 4
	local lineH = 0
	if chip.Visible then
		local ch = textHeight(chip, textW - 16) + 6
		chip.Position = UDim2.new(0, TEXT_X, 0, y)
		chip.Size = UDim2.new(1, -(TEXT_X + PAD), 0, ch)
		lineH = ch
	elseif sub.Visible and sub.Text ~= "" then
		local sh = textHeight(sub, textW) + 2
		sub.Position = UDim2.new(0, TEXT_X, 0, y)
		sub.Size = UDim2.new(1, -(TEXT_X + PAD), 0, sh)
		lineH = sh
	end
	local bottom = math.max(PAD + TILE, y + lineH)
	if meter.Visible then
		meter.Position = UDim2.new(0, PAD, 0, bottom + 8)
		bottom += 8 + 22
	end
	if footer.Visible then
		footer.Position = UDim2.new(0, PAD, 0, bottom + 8)
		bottom += 8 + 46
	end
	card.Size = UDim2.new(1, 0, 0, bottom + PAD + 4)
end
card:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	-- width changes (viewport) re-wrap the text; height changes are ours
	local w = card.AbsoluteSize.X
	if w ~= card:GetAttribute("LaidW") then card:SetAttribute("LaidW", w); task.defer(layout) end
end)

local function applySub()
	local subText = words(player:GetAttribute("ObjectiveSub"))
	local reward = subText ~= "" and (string.sub(subText, 1, 1) == "+" or string.find(subText, "Unlocks", 1, true) ~= nil
		or string.find(subText, "Room for", 1, true) ~= nil or string.find(subText, "money", 1, true) ~= nil)
	chip.Visible = reward and not stamping
	chip.Text = reward and subText or ""
	sub.Text = reward and "" or subText
	sub.Visible = not stamping
	meter.Visible = cost ~= nil and cost > 0 and not stamping
	footer.Visible = bigVisible() and not stamping
	layout()
end

local function readBig()
	local t = player:GetAttribute("MilestoneTitle")
	local c = tonumber(player:GetAttribute("MilestoneCost"))
	local unlock = player:GetAttribute("MilestoneUnlock")
	bigTitle.Text = t and ("BIG GOAL:  " .. t) or ""
	local bits = {}
	if c and c > 0 then table.insert(bits, UIKit.money(c)) end
	if unlock then table.insert(bits, "unlocks " .. string.lower(unlock)) end
	if #bits == 0 then table.insert(bits, player:GetAttribute("MilestoneSub") or "") end
	bigSub.Text = table.concat(bits, "  ·  ")
	bigBar.Visible = c ~= nil and c > 0
	applySub()
end
for _, a in ipairs({ "MilestoneTitle", "MilestoneSub", "MilestoneCost", "MilestoneUnlock", "NamingOpen", "HQLevel", "IncomeRooms" }) do
	player:GetAttributeChangedSignal(a):Connect(readBig)
end

-- a finished goal: confetti bursts out of the tile and falls away
local function confetti()
	local colours = { UIKit.GREEN, GOLD, UIKit.BLUE, UIKit.ORANGE, UIKit.PINK }
	for i = 1, 16 do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = colours[(i % #colours) + 1]
		f.Size = UDim2.new(0, math.random(5, 9), 0, math.random(5, 9))
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.new(0, PAD + TILE / 2, 0, PAD + TILE / 2)
		f.ZIndex = 8
		f.Parent = card
		local a = math.random() * math.pi * 2
		local r = math.random(40, 90)
		TweenService:Create(f, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0, PAD + TILE / 2 + math.cos(a) * r, 0, PAD + TILE / 2 + math.sin(a) * r * 0.7 + 18),
			Rotation = math.random(-200, 200), BackgroundTransparency = 1,
		}):Play()
		task.delay(0.75, function() f:Destroy() end)
	end
end

local function showGoal(key, text)
	title.Text = words(text)
	title.TextColor3 = UIKit.INK
	local ic = iconFor(key, text)
	tileIcon.Image = UIKit.ART[ic] or UIKit.ART.target
	pinIcon.Image = tileIcon.Image
	tint(ic)
end

-- was the goal that just went away actually FINISHED?
local PASSIVE = { wait = true, watch = true, product = true }
local function finished(prevKey, prevCost, newKey)
	if not prevKey or not newKey then return false end
	if PASSIVE[prevKey] or newKey == "product" then return false end
	if prevCost and prevCost > 0 then
		-- a purchase goal is done when the money for it left your pocket
		return recentMax() - cashNow() >= prevCost * 0.8
	end
	return true
end

local function readObjective()
	local key = player:GetAttribute("Objective")
	local text = player:GetAttribute("ObjectiveText")
	local pos = player:GetAttribute("ObjectivePos")
	target = typeof(pos) == "Vector3" and pos or nil
	cost = tonumber(player:GetAttribute("ObjectiveCost"))

	if key ~= lastKey then
		if finished(lastKey, lastCost, key) then
			-- a check stamps down, confetti, then the next goal springs in
			stamping = true
			title.Text = "DONE!"
			title.TextColor3 = UIKit.GREEN_DEEP
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
			task.delay(0.9, function()
				stamping = false
				stamp.Visible = false
				tileIcon.Visible = true
				if cardStroke then cardStroke.Color = UIKit.CARD_LINE end
				showGoal(player:GetAttribute("Objective"), player:GetAttribute("ObjectiveText"))
				applySub()
				cardScale.Scale = 0.94
				tween(cardScale, 0.25, { Scale = 1 })
			end)
		elseif not stamping then
			showGoal(key, text)
		end
		lastKey = key
		readyFor = nil
	elseif not stamping then
		title.Text = words(text)
	end
	lastCost = cost
	applySub()

	local show = key ~= nil and text ~= nil
	-- a waiting LAUNCH is the bottom slot's (HudClient); the name box sits over everything
	card.Visible = show and key ~= "product" and player:GetAttribute("NamingOpen") ~= true
	gui.Enabled = show and player:GetAttribute("NamingOpen") ~= true
	local showMarker = show and target ~= nil
	pin.Enabled = showMarker
	pinPart.Parent = showMarker and workspace or nil
	ring.Parent = showMarker and workspace or nil
	beamEnd.Parent = showMarker and workspace or nil
	beam.Enabled = showMarker
end

for _, name in ipairs({ "Objective", "ObjectiveText", "ObjectivePos", "ObjectiveSub", "ObjectiveCost" }) do
	player:GetAttributeChangedSignal(name):Connect(readObjective)
end
player:GetAttributeChangedSignal("NamingOpen"):Connect(readObjective)
readObjective()
readBig()

-- ============ TAP THE CARD: LOOK AT THE GOAL ============
--[[ The camera turns to face the target for a moment and the pin pops, then
control is yours again. Rotation only, from where the camera already is, so it
cannot clip a wall. Handing the camera back as Custom makes the camera module
adopt the new yaw (the v2.3 join-card lesson). Never during a cutscene, in a
car, or while the camera is scripted by someone else. ]]
local looking = false
local function inCar()
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum and hum.SeatPart ~= nil
end
local function popPin()
	pinScale.Scale = 1.5
	tween(pinScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
end
local function lookAtGoal()
	if looking then return end
	cardScale.Scale = 0.96
	tween(cardScale, 0.2, { Scale = 1 })
	if not target then return end
	popPin()
	if camera.CameraType ~= Enum.CameraType.Custom or (Cine and Cine.busy and Cine.busy()) or inCar() then return end
	looking = true
	local from = camera.CFrame
	local goal = CFrame.lookAt(from.Position, target + Vector3.new(0, 3, 0))
	camera.CameraType = Enum.CameraType.Scriptable
	local tw = tween(camera, 0.45, { CFrame = goal })
	tw.Completed:Wait()
	task.wait(0.35)
	if camera.CameraType == Enum.CameraType.Scriptable then camera.CameraType = Enum.CameraType.Custom end
	looking = false
end
hit.MouseButton1Click:Connect(function()
	UIKit.sfx("tap")
	task.spawn(lookAtGoal)
end)

-- ============ PER-FRAME ============

-- where the arrow may sit: right of the left rail, left of the right column,
-- clear of the money at the top and the bottom slot
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
	local top, bottom = 130, vp.Y - 150
	if right < left then right = left end
	if bottom < top then bottom = top end
	return left, right, top, bottom, colBottom
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	table.insert(history, { now, cashNow() })
	while history[1] and now - history[1][1] > 2.5 do table.remove(history, 1) end

	-- the big goal's bar
	local bc = tonumber(player:GetAttribute("MilestoneCost"))
	if footer.Visible and bc and bc > 0 then
		local pb = math.clamp(cashNow() / bc, 0, 1)
		bigFill.Size = UDim2.new(pb, 0, 1, 0)
		bigFill.BackgroundColor3 = pb >= 1 and UIKit.GREEN or UIKit.BLUE
	end
	-- the goal meter: cash / price, then READY
	if cost and cost > 0 and card.Visible and meter.Visible then
		local have = cashNow()
		local p = math.clamp(have / cost, 0, 1)
		fill.Size = UDim2.new(p, 0, 1, 0)
		shineGrad.Offset = Vector2.new(((now * 0.55) % 2.4) - 1.2, 0)
		if p >= 1 then
			fill.BackgroundColor3 = UIKit.GREEN
			price.Text = "READY!"
			if cardStroke and not stamping then
				cardStroke.Color = UIKit.GREEN
				cardStroke.Thickness = 2 + 1.5 * (0.5 + 0.5 * math.sin(now * 5))
			end
			if readyFor ~= lastKey then
				readyFor = lastKey
				UIKit.sfx("ding")
				cardScale.Scale = 1.06
				tween(cardScale, 0.3, { Scale = 1 })
				popPin()
			end
		else
			fill.BackgroundColor3 = GOLD
			price.Text = UIKit.money(have) .. " / " .. UIKit.money(cost)
			if cardStroke and not stamping then
				cardStroke.Color = UIKit.CARD_LINE
				cardStroke.Thickness = 2
			end
		end
	elseif cardStroke and not stamping then
		cardStroke.Color = UIKit.CARD_LINE
		cardStroke.Thickness = 2
	end

	if not target then edge.Visible = false return end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local dist = root and (root.Position - target).Magnitude or 0
	-- the pin bobs over the target; lower when close, so a ceiling or the HUD never hides it
	local lift = (dist < 24 and 5 or 8) + math.sin(now * 3.2) * 0.5
	pinPart.Position = target + Vector3.new(0, lift, 0)
	pin.StudsOffset = Vector3.new(0, 1.2, 0)
	local pulse = 0.5 + 0.5 * math.sin(now * 3)
	ring.CFrame = CFrame.new(target + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Size = Vector3.new(0.12, 7 + pulse * 2, 7 + pulse * 2)
	ring.Transparency = 0.55 + 0.25 * pulse
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
		-- behind you: a "turn" arrow on the side you should turn to, at mid height
		local rel = camera.CFrame:PointToObjectSpace(target)
		local goRight = rel.X >= 0
		if goRight then
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
