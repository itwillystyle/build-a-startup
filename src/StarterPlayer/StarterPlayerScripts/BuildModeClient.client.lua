--[[
	BuildModeClient -- LocalScript in StarterPlayer -> StarterPlayerScripts.

	DECOR MODE. Retail Tycoon 2 feels premium because YOU place things: a
	catalog you browse, a ghost that follows your cursor, snap, rotate, and the
	thing stays where you put it. So:

	  B (or the DECOR button)  -> catalog sheet with live 3D thumbnails
	  click an item            -> a see-through ghost follows the cursor,
	                              green = fits, red = does not
	  R / ROTATE               -> quarter turns
	  click                    -> placed (server checks money/bounds/overlap)
	  trash button             -> hover highlights yours, click refunds half
	  B / Q / close            -> out

	The ghost is built from THE SAME ReplicatedStorage templates the server
	spawns from, positioned by the same FurnitureKit.stand(), so the preview
	cannot drift from the real thing.

	Mobile: the ghost is aimed from a fixed reticle (the finger drag is the
	camera), and PLACE / ROTATE buttons commit. Touch targets >= 44 px.

	v3.1 (25 Sep reviews):
	  - renamed BUILD -> DECOR. Buildings go up on the lots ("+ BUILD HERE"),
	    so a BUILD button that opened a furniture shop sent players to the
	    wrong place. It appears at HQ 2, when the first four minutes are over.
	  - the reason to decorate is on screen: "Money +7%  (max 15%)"
	    (the server caps placed decor at +15% money; nothing said so)
	  - under the V3 economy desks and tables are decor (rooms come furnished);
	    the cards no longer promise "+1 hire slot"
	  - light sheet, 14 px minimum text, one money format, trash icon, round close

	v3.2.1 (his phone test: "the build UI blocks any building placements,
	building is kind of pointless or it doesn't tell the player what to do"):
	  - DECOR has one job now: VIBE. Every piece adds vibe points, stars make
	    rare hires likelier (FurnitureKit.vibe; the server rolls with it).
	    Restaurant Tycoon 2 / Retail Tycoon 2 do the same: decor -> a star
	    rating -> better customers. The +1% money that most items did not
	    even give is gone.
	  - the header shows the stars, the first card in the shelf says what
	    they do and how far the next star is, every card says "+2 vibe"
	  - picking an item HIDES the catalog. You place from one slim action bar
	    (back / name / rotate / place) with the whole world visible above it.
	    Same bar for removing. The jump button keeps its corner.
	  - touch aims from a fixed point mid-world (ViewportPointToRay from a
	    full-screen, non-inset reticle), and the bar says why a spot is red
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local FK = require(ReplicatedStorage:WaitForChild("FurnitureKit"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local remotes = ReplicatedStorage:WaitForChild("SVRemotes")
local placeItem = remotes:WaitForChild("PlaceItem")
local removeItem = remotes:WaitForChild("RemoveItem")

local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local GOOD = UIKit.GREEN
local BAD = UIKit.RED

local CATS = { "OFFICE", "COMFORT", "DECOR", "KITCHEN" }
local CAT_NAME = { OFFICE = "Office", COMFORT = "Lounge", DECOR = "Plants", KITCHEN = "Kitchen" }
local NEEDS_NAME = { cafe = "Needs a CAFE", studio = "Needs a STUDIO" }
local SHEET_H = 196
local ACTION_H = 64            -- v3.2.1: the slim bar you place and remove from
local AIM_Y = 0.52             -- touch: the reticle sits mid-world, above the action bar

-- ============ STATE ============

local open = false
local mode = "place"          -- "place" | "delete"
local selectedKey = nil
local ghost = nil
local ghostYaw = 0
local ghostCF = nil           -- last legal stand point, what PLACE sends
local ghostOK = false
local hoverTarget = nil       -- delete mode: the model under the cursor
local hoverHighlight = nil

-- one formula for server and client, so the shown price is the charged price
local function priceOf(item)
	if FK.priceFor then
		return FK.priceFor(item, player:GetAttribute("PriceMult") or 1, player:GetAttribute("IncomeRate") or 0)
	end
	return math.floor(item.price * (player:GetAttribute("PriceMult") or 1))
end

local function cash()
	local ls = player:FindFirstChild("leaderstats")
	local c = ls and ls:FindFirstChild("Cash")
	return c and c.Value or 0
end

-- ============ UI SHELL ============

local gui = Instance.new("ScreenGui")
gui.Name = "BuildMode"
gui.ResetOnSpawn = false
gui.DisplayOrder = 10          -- above the guide arrow and the column
gui.IgnoreGuiInset = true
UIKit.safe(gui)
gui.Enabled = player:GetAttribute("MenuDone") == true     -- HUD waits for PLAY
player:GetAttributeChangedSignal("MenuDone"):Connect(function() gui.Enabled = true end)
gui.Parent = player:WaitForChild("PlayerGui")

-- the rail button. Home icon + one word; desktop gets a small key cap.
local toggle = UIKit.railButton("home", "DECOR", UIKit.GREEN, {
	Name = "BuildToggle", LayoutOrder = 5, Size = UDim2.new(0, UIKit.RAIL, 0, UIKit.RAIL), Visible = false,
}, { iconSize = 28 })
if not isTouch then
	local cap = UIKit.panel(toggle, { Name = "KeyCap", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.new(0, 24, 0, 24), ZIndex = toggle.ZIndex + 2 }, { radius = 7, color = UIKit.INK, stroke = UIKit.TEXT, strokeWidth = 1.5 })
	UIKit.heading(cap, "B", 15, UIKit.TEXT, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 1, ZIndex = toggle.ZIndex + 3 })
end

-- a verb that does nothing yet is noise. Decor unlocks at HQ 2 (about minute 4).
local function unlocked()
	return player:GetAttribute("BuildOpen") == true and (player:GetAttribute("HQLevel") or 1) >= 2
end

-- a new button nobody notices is a verb nobody uses: it pulses for 10 s when it appears
local pulseScale = Instance.new("UIScale")
pulseScale.Parent = toggle
local pulseUntil = 0
local pulsing = false
local function pulse(seconds)
	pulseUntil = math.max(pulseUntil, os.clock() + seconds)
	if pulsing then return end
	pulsing = true
	task.spawn(function()
		while os.clock() < pulseUntil and toggle.Visible do
			TweenService:Create(pulseScale, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Scale = 1.12 }):Play()
			task.wait(0.35)
			TweenService:Create(pulseScale, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { Scale = 1 }):Play()
			task.wait(0.55)
		end
		pulseScale.Scale = 1
		pulsing = false
	end)
end
local announced = unlocked()
local function syncToggle()
	local v = unlocked()
	toggle.Visible = v
	if v and not announced then
		announced = true
		pulse(10)
	end
end
syncToggle()
player:GetAttributeChangedSignal("BuildOpen"):Connect(syncToggle)
player:GetAttributeChangedSignal("HQLevel"):Connect(syncToggle)

-- the catalog sheet: rises from the bottom, the world stays visible above it
-- right of the left rail, so DAILY / INDEX / DECOR stay visible and tappable
local RAIL_R = 12 + UIKit.RAIL + 12
local bar, body, closeBtn, title = UIKit.menu(gui, "", UIKit.BLUE, {
	Name = "CatalogBar", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, SHEET_H + 40),
	Size = UDim2.new(1, -(RAIL_R + 12), 0, SHEET_H), Visible = false,
}, { headerHeight = 44 })
local cap = Instance.new("UISizeConstraint", bar)
cap.MaxSize = Vector2.new(860, SHEET_H)
body.Position = UDim2.new(0, 12, 0, 44 + 8)
body.Size = UDim2.new(1, -24, 1, -(44 + 16))
title.Size = UDim2.new(0.32, 0, 1, 0)
title.TextSize = 20
title.TextScaled = true
local tsc = Instance.new("UITextSizeConstraint", title)
tsc.MaxTextSize = 20
tsc.MinTextSize = 14

-- v3.2.1 the header says what decor is for: VIBE stars and what they buy
title.Visible = false
local vibeRow = Instance.new("Frame")
vibeRow.Name = "Vibe"
vibeRow.BackgroundTransparency = 1
vibeRow.AnchorPoint = Vector2.new(0, 0.5)
vibeRow.Position = UDim2.new(0, 16, 0.5, 0)
vibeRow.Size = UDim2.new(0.33, -16, 0, 30)
vibeRow.ZIndex = 3
vibeRow.Parent = bar:FindFirstChild("Header")
local vrl = Instance.new("UIListLayout", vibeRow)
vrl.FillDirection = Enum.FillDirection.Horizontal
vrl.VerticalAlignment = Enum.VerticalAlignment.Center
vrl.Padding = UDim.new(0, 3)
vrl.SortOrder = Enum.SortOrder.LayoutOrder
UIKit.heading(vibeRow, "VIBE", 18, UIKit.TEXT, { Name = "Word", LayoutOrder = 0, Size = UDim2.new(0, 46, 1, 0), ZIndex = 3 })
local starIcons = {}
for i = 1, 5 do
	starIcons[i] = UIKit.icon(vibeRow, "star", 17, UIKit.TEXT, { Name = "Star" .. i, LayoutOrder = i, ZIndex = 3 })
end
local luckLabel = UIKit.heading(vibeRow, "x1.0", 16, UIKit.TEXT, { Name = "Luck", LayoutOrder = 6, Size = UDim2.new(0, 44, 1, 0), ZIndex = 3 })

-- category tabs sit in the header, between the bonus and the buttons
local tabRow = Instance.new("Frame")
tabRow.Name = "Tabs"
tabRow.AnchorPoint = Vector2.new(0, 0.5)
tabRow.Position = UDim2.new(0.34, 0, 0.5, 0)
tabRow.Size = UDim2.new(0.66, -112, 0, 34)
tabRow.BackgroundTransparency = 1
tabRow.ZIndex = 3
tabRow.Parent = bar:FindFirstChild("Header")
local tabLayout = Instance.new("UIListLayout", tabRow)
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 6)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder

-- delete is a round trash button next to the close
local delTab = Instance.new("TextButton")
delTab.Name = "Delete"
delTab.Text = ""
delTab.AutoButtonColor = false
delTab.AnchorPoint = Vector2.new(1, 0.5)
delTab.Position = UDim2.new(1, -54, 0.5, 0)
delTab.Size = UDim2.new(0, 40, 0, 40)
delTab.BackgroundColor3 = UIKit.TEXT
delTab.ZIndex = 3
delTab.Parent = bar:FindFirstChild("Header")
Instance.new("UICorner", delTab).CornerRadius = UDim.new(1, 0)
local delIcon = UIKit.icon(delTab, "trash", 22, UIKit.RED, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), ZIndex = 4 })

-- the scrolling shelf of item cards
local shelf = Instance.new("ScrollingFrame")
shelf.Name = "Shelf"
shelf.Size = UDim2.new(1, 0, 1, 0)
shelf.BackgroundTransparency = 1
shelf.ScrollingDirection = Enum.ScrollingDirection.X
shelf.ScrollBarThickness = 5
shelf.ScrollBarImageColor3 = UIKit.CARD_MUTED
shelf.AutomaticCanvasSize = Enum.AutomaticSize.X
shelf.CanvasSize = UDim2.new(0, 0, 0, 0)
shelf.BorderSizePixel = 0
shelf.Parent = body
local shelfLayout = Instance.new("UIListLayout", shelf)
shelfLayout.FillDirection = Enum.FillDirection.Horizontal
shelfLayout.Padding = UDim.new(0, 8)
shelfLayout.SortOrder = Enum.SortOrder.LayoutOrder

-- v3.2.1 the first card answers "why would I place this?" in one breath
local info = UIKit.panel(shelf, { Name = "WhyDecor", LayoutOrder = 0, Size = UDim2.new(0, 184, 1, -8) },
	{ radius = 12, color = UIKit.GOLD, stroke = UIKit.darker(UIKit.GOLD, 0.7), strokeWidth = 2 })
UIKit.label(info, "Decor = VIBE", 17, UIKit.CARD_TEXT, { Position = UDim2.new(0, 10, 0, 8), Size = UDim2.new(1, -20, 0, 20) }, UIKit.HEAD)
UIKit.label(info, "More stars, more rare hires. Place pieces inside your buildings.", 13, UIKit.CARD_TEXT, {
	Position = UDim2.new(0, 10, 0, 30), Size = UDim2.new(1, -20, 0, 52), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }, UIKit.BODY)
local infoNext = UIKit.label(info, "", 14, UIKit.CARD_TEXT, { Name = "Next", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -8),
	Size = UDim2.new(1, -20, 0, 36), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Bottom }, UIKit.HEAD)

-- delete-mode hint replaces the shelf
local delHint = UIKit.label(body, "", 18, UIKit.CARD_TEXT, {
	Name = "DeleteHint", Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, Visible = false,
	TextWrapped = true,
}, UIKit.HEAD)
delHint.Text = isTouch and "Aim the circle at something you placed, then tap REMOVE. You get half back."
	or "Click something you placed to remove it. You get half back."

-- v3.2.1 THE ACTION BAR. Picking an item used to leave the 196 px catalog up
-- with PLACE / ROTATE stacked on top of it: on a 430 px phone that left a
-- ~110 px strip of world to aim into. Now the catalog steps aside while you
-- place or remove, and this one slim bar carries the verbs. It stops 150 px
-- short of the right edge, so the jump button keeps its corner.
local actionBar = UIKit.panel(gui, { Name = "ActionBar", AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, RAIL_R, 1, -12), Size = UDim2.new(1, -(RAIL_R + 150), 0, ACTION_H), Visible = false },
	{ radius = 16, color = UIKit.CARD, stroke = UIKit.CARD_LINE, strokeWidth = 2 })
local abCap = Instance.new("UISizeConstraint", actionBar)
abCap.MaxSize = Vector2.new(620, ACTION_H)
local backBtn = UIKit.button(actionBar, "", UIKit.BLUE, { Name = "Back", AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.new(0, 48, 0, 48) }, { radius = 12 })
UIKit.icon(backBtn, "up", 24, UIKit.TEXT, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -2), Rotation = -90, ZIndex = backBtn.ZIndex + 2 })
local actName = UIKit.label(actionBar, "", 17, UIKit.CARD_TEXT, { Name = "ItemName", Position = UDim2.new(0, 66, 0, 9),
	Size = UDim2.new(1, -66 - (isTouch and 250 or 136), 0, 22), TextTruncate = Enum.TextTruncate.AtEnd }, UIKit.HEAD)
local actSub = UIKit.label(actionBar, "", 14, UIKit.CARD_MUTED, { Name = "Hint", Position = UDim2.new(0, 66, 0, 33),
	Size = UDim2.new(1, -66 - (isTouch and 250 or 136), 0, 20), TextTruncate = Enum.TextTruncate.AtEnd }, UIKit.HEAD)
local placeBtn, placeLabel = UIKit.button(actionBar, "PLACE", GOOD, {
	Name = "PlaceButton", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0),
	Size = UDim2.new(0, 116, 0, 48), Visible = isTouch,
}, { textSize = 20 })
local rotateBtn, rotateLabel = UIKit.button(actionBar, isTouch and "ROTATE" or "ROTATE (R)", UIKit.SURFACE_2, {
	Name = "RotateButton", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, isTouch and -132 or -8, 0.5, 0),
	Size = UDim2.new(0, isTouch and 110 or 120, 0, 48),
}, { textSize = isTouch and 17 or 15, dark = true })

-- TOUCH AIM: on a phone the finger drag IS the camera, so the ghost is aimed
-- from a fixed on-screen reticle and the camera moves it. One gesture, one owner.
-- v3.2.1: the reticle lives in a full-screen gui with NO safe-area inset, so its
-- scale position is exactly the viewport point the ray is cast from.
local aimGui = Instance.new("ScreenGui")
aimGui.Name = "BuildAim"
aimGui.ResetOnSpawn = false
aimGui.IgnoreGuiInset = true
aimGui.DisplayOrder = 9
pcall(function() aimGui.ScreenInsets = Enum.ScreenInsets.None end)
aimGui.Parent = player:WaitForChild("PlayerGui")
local reticle = Instance.new("Frame")
reticle.Name = "Reticle"
reticle.AnchorPoint = Vector2.new(0.5, 0.5)
reticle.Position = UDim2.new(0.5, 0, AIM_Y, 0)
reticle.Size = UDim2.new(0, 26, 0, 26)
reticle.BackgroundTransparency = 1
reticle.Visible = false
reticle.Parent = aimGui
local rst = Instance.new("UIStroke", reticle)
rst.Color = UIKit.TEXT
rst.Thickness = 3
Instance.new("UICorner", reticle).CornerRadius = UDim.new(1, 0)
local dot = Instance.new("Frame")
dot.AnchorPoint = Vector2.new(0.5, 0.5)
dot.Position = UDim2.new(0.5, 0, 0.5, 0)
dot.Size = UDim2.new(0, 6, 0, 6)
dot.BackgroundColor3 = UIKit.TEXT
dot.BorderSizePixel = 0
dot.Parent = reticle
Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

-- ============ THUMBNAILS ============

--[[ Live 3D thumbnails, not icons: each card holds a ViewportFrame with a
clone of the real template at a three-quarter angle. Costs nothing, because
the templates already replicate to the client. ]]
local function thumbnail(parent, key)
	local vpf = Instance.new("ViewportFrame")
	vpf.Name = "Thumb"
	vpf.Size = UDim2.new(1, -8, 1, -46)
	vpf.Position = UDim2.new(0, 4, 0, 4)
	-- a tinted well, so a white lamp still reads on a white card
	vpf.BackgroundColor3 = UIKit.SURFACE_2
	vpf.BackgroundTransparency = 0
	Instance.new("UICorner", vpf).CornerRadius = UDim.new(0, 9)
	vpf.Ambient = Color3.fromRGB(200, 200, 205)
	vpf.LightColor = Color3.fromRGB(255, 250, 240)
	vpf.Parent = parent

	local m = FK.put(key, CFrame.new(0, 0, 0), vpf)
	if not m then return vpf end
	local cf, size
	if m:IsA("Model") then cf, size = m:GetBoundingBox()
	else cf, size = m.CFrame, m.Size end
	local radius = math.max(size.X, size.Y, size.Z)
	local cam = Instance.new("Camera")
	cam.CFrame = CFrame.new(cf.Position + Vector3.new(radius * 0.9, radius * 0.8, radius * 1.2), cf.Position)
	cam.Parent = vpf
	vpf.CurrentCamera = cam
	return vpf
end

-- ============ CARDS ============

local cards = {}     -- key -> { btn, price, item, ... }

-- what a piece does for you, or nothing (a card that says nothing is better than one that lies)
-- (under the V3 economy rooms come furnished and seats come from room level,
-- so a desk is decor; the only real bonus a piece can carry is money)
local function benefitText(item)
	if item.vibe then return ("+%d vibe"):format(item.vibe) end
	return nil
end

-- locked until the containing building exists; the server enforces the same rule
local function roomBuilt(roomId)
	local idx = player:GetAttribute("Plot")
	local sv = workspace:FindFirstChild("SiliconValley")
	local pf = idx and sv and sv:FindFirstChild("Plots") and sv.Plots:FindFirstChild("Plot" .. idx)
	if not pf then return false end
	for _, m in ipairs(pf:GetDescendants()) do
		if m:IsA("Model") and m.Name:match("^Room_" .. roomId .. "_") then return true end
	end
	return false
end

local selectKey   -- assigned below; the card click fires long after
local showAction  -- v3.2.1: assigned below; the catalog <-> action bar switch

local function makeCard(item, order)
	local btn = Instance.new("TextButton")
	btn.Name = "Item_" .. item.key
	btn.LayoutOrder = order
	btn.Size = UDim2.new(0, 112, 1, -8)
	btn.BackgroundColor3 = UIKit.CARD
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.Visible = false
	btn.Parent = shelf
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 12)
	local st = Instance.new("UIStroke", btn)
	st.Color = UIKit.CARD_LINE
	st.Thickness = 1.5
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	local vpf = thumbnail(btn, item.key)

	local nm = UIKit.label(btn, item.name, 15, UIKit.CARD_TEXT, {
		Name = "ItemName", Position = UDim2.new(0, 8, 1, -40), Size = UDim2.new(1, -16, 0, 17),
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, UIKit.HEAD)
	local pr = UIKit.label(btn, "", 16, GOOD, {
		Name = "Price", Position = UDim2.new(0, 8, 1, -22), Size = UDim2.new(1, -16, 0, 18),
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, UIKit.HEAD)

	-- the money bonus, as a green chip on the thumbnail
	local chip, chipLabel
	local bt = benefitText(item)
	if bt then
		chip = Instance.new("Frame")
		chip.Name = "Bonus"
		chip.Position = UDim2.new(0, 6, 0, 6)
		chip.Size = UDim2.new(0, 66, 0, 22)
		chip.BackgroundColor3 = GOOD
		chip.BorderSizePixel = 0
		chip.ZIndex = 3
		chip.Parent = btn
		Instance.new("UICorner", chip).CornerRadius = UDim.new(1, 0)
		chipLabel = UIKit.label(chip, bt, 14, UIKit.TEXT, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 }, UIKit.HEAD)
	end
	local lock = UIKit.icon(btn, "lock", 28, UIKit.CARD_MUTED, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -18), ZIndex = 3, Visible = false,
	})

	btn.MouseButton1Down:Connect(function() UIKit.sfx("tap") end)
	btn.MouseButton1Click:Connect(function() selectKey(item.key, btn) end)
	cards[item.key] = { btn = btn, price = pr, name = nm, stroke = st, item = item, vpf = vpf, chip = chip, chipLabel = chipLabel, lock = lock }
end

-- ============ GHOST ============

local function clearGhost()
	if ghost then ghost:Destroy() ghost = nil end
	ghostCF = nil
	ghostOK = false
end

local function clearHover()
	if hoverHighlight then hoverHighlight:Destroy() hoverHighlight = nil end
	hoverTarget = nil
end

local function unselectCards()
	for _, c in pairs(cards) do
		c.stroke.Color = UIKit.CARD_LINE
		c.stroke.Thickness = 1.5
	end
end

selectKey = function(key, btn)
	local it = FK.BY_KEY[key]
	if it and it.needs and not roomBuilt(it.needs) then
		UIKit.sfx("thunk", 0.8)
		return
	end
	mode = "place"
	clearHover()
	clearGhost()
	selectedKey = key
	unselectCards()
	if btn then
		local c = cards[key]
		c.stroke.Color = UIKit.BLUE
		c.stroke.Thickness = 3
	end
	ghost = FK.put(key, CFrame.new(0, -500, 0), workspace)
	if ghost then
		for _, d in ipairs(ghost:IsA("BasePart") and { ghost } or ghost:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Transparency = 0.55
				d.CanCollide = false
				d.CanQuery = false
			end
		end
		local hl = Instance.new("Highlight")
		hl.Name = "GhostGlow"
		hl.FillTransparency = 0.75
		hl.OutlineTransparency = 0.1
		hl.Parent = ghost
	end
	if open then showAction() end
end

-- ============ FLOORS + AIM ============

local floorParts = {}
local placedFolder = nil
local surfaceModels = {}     -- bench desks + placed items: aim targets with attributes

-- SIX PLOTS: everything here is scoped to the player's own plot folder, named
-- by the Plot attribute the server stamps on the player. Another founder's
-- floor must never read as buildable.
local function myPlotFolder()
	local idx = player:GetAttribute("Plot")
	local sv = workspace:FindFirstChild("SiliconValley")
	local plotsF = sv and sv:FindFirstChild("Plots")
	return idx and plotsF and plotsF:FindFirstChild("Plot" .. idx) or nil
end

local function rescanFloors()
	floorParts = {}
	surfaceModels = {}
	local pf = myPlotFolder()
	if not pf then placedFolder = nil return end
	placedFolder = pf:FindFirstChild("Placed")
	for _, d in ipairs(pf:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "GarageFloor" or
			(d.Name == "Floor" and d.Parent and d.Parent.Name:match("^Room_"))) then
			table.insert(floorParts, d)
		end
	end
	for _, d in ipairs(pf:GetDescendants()) do
		if d:GetAttribute("px") ~= nil then table.insert(surfaceModels, d) end
	end
end

-- how many of this piece you have placed (vibe counts the first VIBE_PER_KEY)
local function countOf(key)
	local pf = myPlotFolder()
	local placed = pf and pf:FindFirstChild("Placed")
	local n = 0
	if placed then
		for _, m in ipairs(placed:GetChildren()) do
			if m:GetAttribute("owner") == player.UserId and m:GetAttribute("key") == key then n += 1 end
		end
	end
	return n
end

-- overlap preview off the attributes the server stamps on every placed model,
-- so both ends run the same numbers
local function previewLegal(x, z, w, d, item)
	local surfaceY = nil
	local targets = {}
	for _, m in ipairs(surfaceModels) do table.insert(targets, m) end
	if placedFolder then
		for _, m in ipairs(placedFolder:GetChildren()) do table.insert(targets, m) end
	end
	for _, m in ipairs(targets) do
		local px, pz = m:GetAttribute("px"), m:GetAttribute("pz")
		if px then
			local pw, pd = m:GetAttribute("pw"), m:GetAttribute("pd")
			local overl = math.abs(x - px) * 2 < (w + pw) - 0.05
				and math.abs(z - pz) * 2 < (d + pd) - 0.05
			if overl then
				local pkey = m:GetAttribute("key")
				local pit = FK.BY_KEY[pkey]
				if item.flat or (pit and pit.flat) then
					-- v4.4 a rug: under anything, and anything may stand on it
				elseif item.surface and pit and pit.surfaceTop then
					surfaceY = pit.surfaceTop           -- rides the desk: legal
				elseif item.tuck and pit and (pit.surfaceTop or pit.desk) then
					-- chair tucking under desk family: legal
				else
					return false, nil
				end
			end
		end
	end
	return true, surfaceY
end

local ghostWhy = nil          -- v3.2.1: why the spot is red, for the action bar

local function aimGhost(screenX, screenY)
	if not ghost or not selectedKey then return end
	local cam = workspace.CurrentCamera
	local ray = cam:ViewportPointToRay(screenX, screenY)
	local params = RaycastParams.new()
	-- floors AND surfaces: pointing at a desk must land ON it, not through it
	local targets = {}
	for _, f in ipairs(floorParts) do table.insert(targets, f) end
	for _, m in ipairs(surfaceModels) do table.insert(targets, m) end
	if placedFolder then table.insert(targets, placedFolder) end
	params.FilterDescendantsInstances = targets
	params.FilterType = Enum.RaycastFilterType.Include
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 260, params)
	local hl = ghost:FindFirstChild("GhostGlow")
	if not hit then
		ghostOK = false
		ghostCF = nil
		ghostWhy = "Aim at a floor inside your buildings"
		if hl then hl.FillColor = BAD hl.OutlineColor = BAD end
		return
	end

	local item = FK.BY_KEY[selectedKey]
	local x = math.floor(hit.Position.X / 0.5 + 0.5) * 0.5
	local z = math.floor(hit.Position.Z / 0.5 + 0.5) * 0.5
	local w, d = FK.footprint(selectedKey, ghostYaw)

	-- the ray may have hit a SURFACE, not a floor: bounds and height come from the floor under the point
	local fp = nil
	for _, f in ipairs(floorParts) do
		local l = f.CFrame:PointToObjectSpace(Vector3.new(x, 0, z))
		if math.abs(l.X) <= f.Size.X / 2 and math.abs(l.Z) <= f.Size.Z / 2 then
			fp = f
			break
		end
	end
	if not fp then
		ghostOK = false
		ghostCF = nil
		ghostWhy = "Aim at a floor inside your buildings"
		if hl then hl.FillColor = BAD hl.OutlineColor = BAD end
		return
	end
	local l = fp.CFrame:PointToObjectSpace(Vector3.new(x, 0, z))
	local inBounds = math.abs(l.X) + w / 2 <= fp.Size.X / 2
		and math.abs(l.Z) + d / 2 <= fp.Size.Z / 2

	local legal, surfaceY = previewLegal(x, z, w, d, item)
	local floorTop = fp.Position.Y + fp.Size.Y / 2
	local y = floorTop + (surfaceY or 0)

	local afford = cash() >= priceOf(item)
	ghostOK = inBounds and legal and afford
	ghostWhy = (not inBounds and "Too close to the wall") or (not legal and "Something is in the way")
		or (not afford and ("Need " .. UIKit.money(priceOf(item)))) or nil
	ghostCF = CFrame.new(x, y, z)
	FK.stand(ghost, ghostCF, ghostYaw)

	if hl then
		hl.FillColor = ghostOK and GOOD or BAD
		hl.OutlineColor = ghostOK and GOOD or BAD
	end
end

local function commitPlace()
	if not (ghost and ghostOK and ghostCF and selectedKey) then
		if ghost then UIKit.sfx("thunk", 0.8) end
		return
	end
	placeItem:FireServer(selectedKey, ghostCF.Position, ghostYaw)
	UIKit.sfx("thunk", 1.2)
	-- ghost stays armed: RT2 lets you lay a row of desks without re-picking
end

-- ============ DELETE MODE ============

local function aimDelete(screenX, screenY)
	if not placedFolder then return end
	local cam = workspace.CurrentCamera
	local ray = cam:ViewportPointToRay(screenX, screenY)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { placedFolder }
	params.FilterType = Enum.RaycastFilterType.Include
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 260, params)
	local target = nil
	if hit then
		local m = hit.Instance
		while m and m.Parent ~= placedFolder do m = m.Parent end
		if m and m:GetAttribute("owner") == player.UserId then target = m end
	end
	if target ~= hoverTarget then
		clearHover()
		hoverTarget = target
		if target then
			hoverHighlight = Instance.new("Highlight")
			hoverHighlight.FillColor = BAD
			hoverHighlight.OutlineColor = BAD
			hoverHighlight.FillTransparency = 0.6
			hoverHighlight.Parent = target
		end
	end
end

local function commitDelete()
	if hoverTarget then
		removeItem:FireServer(hoverTarget)
		UIKit.sfx("thunk", 0.7)
		clearHover()
	end
end

-- ============ TABS ============

local activeCat = "OFFICE"
local tabBtns = {}

local function refreshTitle()
	-- the server owns these numbers (it rolls hires with them)
	local stars = player:GetAttribute("VibeStars") or 0
	local luck = player:GetAttribute("VibeLuck") or 1
	local pts = player:GetAttribute("VibePoints") or 0
	for i, icon in ipairs(starIcons) do
		icon.ImageColor3 = (i <= stars) and UIKit.GOLD or UIKit.TEXT
		icon.ImageTransparency = (i <= stars) and 0 or 0.55
	end
	luckLabel.Text = ("x%.1f"):format(luck)
	local _, _, nextAt = FK.vibe(pts)
	infoNext.Text = nextAt and ("%d more vibe for star %d"):format(nextAt - pts, stars + 1) or "5 stars! Best odds for rare hires"
end

local function refreshShelf()
	local deleting = mode == "delete"
	shelf.Visible = not deleting
	delHint.Visible = deleting
	for _, c in pairs(cards) do
		c.btn.Visible = (c.item.cat == activeCat)
		local locked = c.item.needs and not roomBuilt(c.item.needs)
		local p = priceOf(c.item)
		local afford = cash() >= p
		c.lock.Visible = locked and true or false
		c.vpf.ImageTransparency = locked and 0.6 or 0
		if c.chip then
			c.chip.Visible = not locked
			-- the first VIBE_PER_KEY copies count; after that the card says so
			local full = countOf(c.item.key) >= (FK.VIBE_PER_KEY or 3)
			c.chip.BackgroundColor3 = full and UIKit.CARD_MUTED or GOOD
			if c.chipLabel then c.chipLabel.Text = full and "max" or benefitText(c.item) end
		end
		if locked then
			c.price.Text = NEEDS_NAME[c.item.needs] or ("Needs a " .. string.upper(c.item.needs))
			c.price.TextColor3 = UIKit.ORANGE
			c.price.TextSize = 14
			c.btn.BackgroundColor3 = UIKit.SURFACE_2
		else
			c.price.Text = UIKit.money(p)
			c.price.TextColor3 = afford and GOOD or UIKit.CARD_MUTED
			c.price.TextSize = 16
			c.btn.BackgroundColor3 = UIKit.CARD
		end
	end
	for cat, b in pairs(tabBtns) do
		local on = (cat == activeCat) and not deleting
		UIKit.setButtonColor(b.btn, on and UIKit.TEXT or UIKit.darker(UIKit.BLUE, 0.8))
		b.label.TextColor3 = on and UIKit.darker(UIKit.BLUE, 0.6) or UIKit.TEXT
		b.label.TextStrokeTransparency = 1
	end
	delTab.BackgroundColor3 = deleting and BAD or UIKit.TEXT
	delIcon.ImageColor3 = deleting and UIKit.TEXT or BAD
	refreshTitle()
end

for i, cat in ipairs(CATS) do
	local b, t = UIKit.button(tabRow, CAT_NAME[cat] or cat, UIKit.darker(UIKit.BLUE, 0.8), {
		Name = "Tab_" .. cat, LayoutOrder = i, Size = UDim2.new(0.25, -5, 1, 0), ZIndex = 3,
	}, { textSize = 16, radius = 10 })
	t.ZIndex = 4
	t.TextScaled = true
	local tc = Instance.new("UITextSizeConstraint", t)
	tc.MaxTextSize = 16
	tc.MinTextSize = 13
	tabBtns[cat] = { btn = b, label = t }
	b.MouseButton1Click:Connect(function()
		activeCat = cat
		mode = "place"
		shelf.CanvasPosition = Vector2.new(0, 0)
		refreshShelf()
	end)
end

delTab.MouseButton1Down:Connect(function() UIKit.sfx("tap") end)
delTab.MouseButton1Click:Connect(function()
	if mode == "delete" then
		mode = "place"
		refreshShelf()
		showAction()
		return
	end
	mode = "delete"
	clearGhost()
	selectedKey = nil
	unselectCards()
	refreshShelf()
	showAction()
end)

-- ============ OPEN / CLOSE ============

local heartbeatConn = nil

-- the quest card and boosts sit where the ghost goes; they step aside while decorating
local function setColumn(visible)
	local col = player.PlayerGui:FindFirstChild("RightColumn")
	if col then col.Enabled = visible end
end

-- catalog <-> action bar. The action bar is up while placing or removing.
showAction = function()
	local placing = mode == "place" and selectedKey ~= nil
	local deleting = mode == "delete"
	local act = open and (placing or deleting)
	actionBar.Visible = act
	bar.Visible = open and not act
	rotateBtn.Visible = placing
	placeBtn.Visible = isTouch or deleting
	if placing then
		local it = FK.BY_KEY[selectedKey]
		local n = countOf(selectedKey)
		actName.Text = ("%s  ·  %s"):format(it and it.name or "", UIKit.money(it and priceOf(it) or 0))
		if n >= (FK.VIBE_PER_KEY or 3) then
			actName.Text ..= "  ·  vibe maxed"
		elseif it and it.vibe then
			actName.Text ..= ("  ·  +%d vibe"):format(it.vibe)
		end
	elseif deleting then
		actName.Text = "Remove something you placed"
	end
end

backBtn.MouseButton1Click:Connect(function()
	clearGhost()
	clearHover()
	selectedKey = nil
	mode = "place"
	unselectCards()
	refreshShelf()
	showAction()
end)

local function setOpen(v)
	if v and not unlocked() then return end
	open = v
	bar.Visible = v
	actionBar.Visible = false
	setColumn(not v)
	player:SetAttribute("BuildModeOpen", v)   -- client-local: ProductClient holds its panels while this is true
	UIKit.setRailActive(toggle, v)
	if v then
		rescanFloors()
		refreshShelf()
		bar.Position = UDim2.new(1, -12, 1, SHEET_H + 40)
		TweenService:Create(bar, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { Position = UDim2.new(1, -12, 1, -12) }):Play()
		heartbeatConn = RunService.Heartbeat:Connect(function()
			-- GetMouseLocation includes the top GUI inset; ScreenPointToRay
			-- expects viewport coordinates without it (skipping this aimed ~36 px high)
			-- v3.2.1: viewport coordinates both ways (GetMouseLocation already is),
			-- cast with ViewportPointToRay: no inset arithmetic to get wrong
			local ax, ay
			if isTouch then
				local vp = workspace.CurrentCamera.ViewportSize
				ax, ay = vp.X * 0.5, vp.Y * AIM_Y
			else
				local m = UserInputService:GetMouseLocation()
				ax, ay = m.X, m.Y
			end
			if mode == "place" and ghost then
				aimGhost(ax, ay)
			elseif mode == "delete" then
				aimDelete(ax, ay)
			end
			reticle.Visible = isTouch and actionBar.Visible
			-- the second line of the action bar: what to do next, or why it is red
			local hint
			if mode == "delete" then
				hint = hoverTarget and "Refunds half its price" or (isTouch and "Aim the circle at something you placed" or "Click something you placed")
			elseif ghost then
				hint = ghostWhy or (isTouch and "Tap PLACE  ·  drag to look around" or "Click the floor to place  ·  R rotates")
			end
			if hint and actSub.Text ~= hint then
				actSub.Text = hint
				actSub.TextColor3 = (mode == "place" and ghostWhy) and BAD or UIKit.CARD_MUTED
			end
			local del = mode == "delete"
			placeLabel.Text = del and "REMOVE" or "PLACE"
			local want = del and BAD or ((ghostOK or not ghost) and GOOD or UIKit.MUTED)
			if placeBtn:GetAttribute("Face") ~= want then UIKit.setButtonColor(placeBtn, want) end
		end)
	else
		if heartbeatConn then heartbeatConn:Disconnect() heartbeatConn = nil end
		reticle.Visible = false
		clearGhost()
		clearHover()
		selectedKey = nil
		mode = "place"
		unselectCards()
		actionBar.Visible = false
	end
end

toggle.MouseButton1Click:Connect(function() setOpen(not open) end)

-- an HQ upgrade replaces the floor part and a room adds one: rescan on change;
-- placing or removing decor moves the bonus
task.spawn(function()
	local pf
	repeat task.wait(0.5); pf = myPlotFolder() until pf
	pf.DescendantAdded:Connect(function(d)
		if open and (d.Name == "GarageFloor" or d.Name == "Floor") then task.defer(rescanFloors) end
		if open and d.Parent and d.Parent.Name == "Placed" then task.defer(function() rescanFloors(); refreshShelf(); showAction() end) end
	end)
	pf.DescendantRemoving:Connect(function(d)
		if open and d.Parent and d.Parent.Name == "Placed" then task.defer(function() rescanFloors(); refreshShelf(); showAction() end) end
	end)
end)
if closeBtn then closeBtn.MouseButton1Click:Connect(function() setOpen(false) end) end
placeBtn.MouseButton1Click:Connect(function()
	if mode == "delete" then commitDelete() else commitPlace() end
end)
rotateBtn.MouseButton1Click:Connect(function() ghostYaw = (ghostYaw + 90) % 360 end)

UserInputService.InputBegan:Connect(function(input, processed)
	if (input.KeyCode == Enum.KeyCode.B) and not processed and unlocked() then
		setOpen(not open)
		return
	end
	if not open or processed then return end
	if input.KeyCode == Enum.KeyCode.R then
		ghostYaw = (ghostYaw + 90) % 360
	elseif input.KeyCode == Enum.KeyCode.Q then
		setOpen(false)
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 and not isTouch then
		-- desktop: the world IS the button. Touch uses PLACE, because this
		-- event fires on every camera drag.
		if mode == "place" then commitPlace()
		elseif mode == "delete" then commitDelete() end
	end
end)

-- the server re-rates vibe after every place / remove
for _, a in ipairs({ "VibeStars", "VibeLuck", "VibePoints" }) do
	player:GetAttributeChangedSignal(a):Connect(function() if open then refreshTitle() end end)
end
-- v3.2.1: when the guide says "Decorate your office", the DECOR button pulses
local function decorNudge()
	if player:GetAttribute("Objective") == "decor" and toggle.Visible and not open then pulse(6) end
end
player:GetAttributeChangedSignal("Objective"):Connect(decorNudge)
task.delay(2, decorNudge)

-- money changes re-grey the cards live
player:WaitForChild("leaderstats"):WaitForChild("Cash"):GetPropertyChangedSignal("Value")
	:Connect(function()
		if open then refreshShelf() end
	end)

-- ============ CARDS, BUILT ONCE ============

for i, item in ipairs(FK.CATALOG) do
	makeCard(item, i)
end
refreshShelf()
