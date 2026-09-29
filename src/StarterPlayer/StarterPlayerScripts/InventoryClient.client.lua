--[[
	InventoryClient -- LocalScript in StarterPlayer -> StarterPlayerScripts (v3.2).

	THE BAG. Five items, each drawn in 3D (Items.icon, built from parts, no
	uploads), each with one job. Not a grid of mystery boxes:

	  - BAG on the left rail, with a red count of new items
	  - the bag: every item slot shows its count, its rarity, and when you
	    have none, where to get one. Pick a slot, read what it does, USE.
	  - items show up WHERE THEY MATTER, so you rarely open the bag at all:
	      a Cold Brew waits beside WRITE CODE
	      a Non-Compete or an Energy Drink appears under the headhunter warning
	  - what is running sits in the right column (BOOSTS): "3x code 0:42",
	    "next launch x2"
	  - a new item flies in from where it came from (the daily card, an
	    investor, a launch), so you learn the bag by watching it fill
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local Notify = require(ReplicatedStorage:WaitForChild("Notify"))
local Items = require(ReplicatedStorage:WaitForChild("Items"))
local remotes = ReplicatedStorage:WaitForChild("SVRemotes")
local useItem = remotes:WaitForChild("UseItem", 60)
local itemEvent = remotes:WaitForChild("ItemEvent", 60)
local itemsSeen = remotes:WaitForChild("ItemsSeen", 60)
if not useItem or not itemEvent then return end

local WHERE = {
	coffee = "Daily reward days 2 and 5, investors, and launches.",
	energy = "Daily reward day 3, and investors.",
	noncompete = "Daily reward day 6, and investors who really like you.",
	scout = "Daily reward day 4, and investors who really like you.",
	frontpage = "Daily reward day 7, and the best investor deals.",
}

local function counts() return Items.decode(player:GetAttribute("Items")) end
local function now() return workspace:GetServerTimeNow() end

-- ============ THE RAIL BUTTON ============

local railBtn = UIKit.railButton("bag", "BAG", UIKit.ORANGE, {
	Name = "BagButton", LayoutOrder = 3, Size = UDim2.new(0, UIKit.RAIL, 0, UIKit.RAIL), Visible = false,
}, { iconSize = 28 })
local badge, badgeText = UIKit.badge(railBtn)

-- ============ THE BAG ============

local gui = Instance.new("ScreenGui")
gui.Name = "Bag"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 12
gui.Enabled = false
UIKit.safe(gui)
gui.Parent = player:WaitForChild("PlayerGui")

local PW, PH = 560, 320
local panel, body, closeBtn = UIKit.menu(gui, "BAG", UIKit.ORANGE, {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 24, 0.5, 0), Size = UDim2.new(0, PW, 0, PH),
}, { headerHeight = 44 })
body.Position = UDim2.new(0, 12, 0, 54)
body.Size = UDim2.new(1, -24, 1, -64)
local fit = Instance.new("UIScale", panel)
local function refit()
	local vp = workspace.CurrentCamera.ViewportSize
	fit.Scale = math.min(1, (vp.X - 130) / PW, (vp.Y - 24) / PH)
end
refit()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)

-- five item slots on the left (3 x 2), what the picked one does on the right
local grid = Instance.new("Frame")
grid.Name = "Grid"
grid.BackgroundTransparency = 1
grid.Size = UDim2.new(0, 300, 1, 0)
grid.Parent = body
local gl = Instance.new("UIGridLayout", grid)
gl.CellSize = UDim2.new(0, 94, 0, 120)
gl.CellPadding = UDim2.new(0, 8, 0, 8)
gl.SortOrder = Enum.SortOrder.LayoutOrder

local detail = UIKit.card(body, { Name = "Detail", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
	Size = UDim2.new(1, -312, 1, 0) }, { radius = 14 })
local dPad = Instance.new("UIPadding", detail)
dPad.PaddingLeft, dPad.PaddingRight, dPad.PaddingTop, dPad.PaddingBottom = UDim.new(0, 12), UDim.new(0, 12), UDim.new(0, 10), UDim.new(0, 10)

local slots = {}
local selected = "coffee"
local spin = {}                 -- models that sway in their viewports: { model, base pivot, phase }

local function slot(it)
	local b = Instance.new("TextButton")
	b.Name = "Item_" .. it.id
	b.Text = ""
	b.AutoButtonColor = false
	b.LayoutOrder = it.order
	b.BackgroundColor3 = UIKit.CARD
	b.Parent = grid
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 14)
	local st = Instance.new("UIStroke", b)
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Color = UIKit.CARD_LINE
	st.Thickness = 1.5
	local vpf = Instance.new("ViewportFrame")
	vpf.BackgroundTransparency = 1
	vpf.Position = UDim2.new(0, 6, 0, 4)
	vpf.Size = UDim2.new(1, -12, 0, 66)
	vpf.Parent = b
	local m = Items.icon(it.id, vpf)
	-- a sway, never a full turn: a contract or a newspaper seen edge-on is a grey line
	if m then table.insert(spin, { m = m, base = m:GetPivot(), phase = it.order * 1.3 }) end
	UIKit.label(b, it.name, 14, UIKit.CARD_TEXT, { Position = UDim2.new(0, 4, 0, 70), Size = UDim2.new(1, -8, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd }, UIKit.HEAD)
	-- v5: rarity in words on its colour (a 6 px underline was colour as the only signal)
	local rc = Items.RARITY[it.rarity].color
	local rar = Instance.new("TextLabel")
	rar.Name = "Rarity"
	rar.AnchorPoint = Vector2.new(0.5, 1)
	rar.Position = UDim2.new(0.5, 0, 1, -6)
	rar.Size = UDim2.new(1, -16, 0, 20)
	rar.BackgroundColor3 = UIKit.light(rc)
	rar.BorderSizePixel = 0
	rar.Text = Items.RARITY[it.rarity].name
	rar.TextColor3 = UIKit.darker(rc, 0.5)
	rar.TextSize = 14
	rar.Font = UIKit.HEAD
	rar.Parent = b
	Instance.new("UICorner", rar).CornerRadius = UDim.new(1, 0)
	local cnt = Instance.new("Frame")
	cnt.Name = "Count"
	cnt.AnchorPoint = Vector2.new(1, 0)
	cnt.Position = UDim2.new(1, -4, 0, 4)
	cnt.Size = UDim2.new(0, 34, 0, 22)
	cnt.BackgroundColor3 = UIKit.INK
	cnt.BorderSizePixel = 0
	cnt.ZIndex = 3
	cnt.Parent = b
	Instance.new("UICorner", cnt).CornerRadius = UDim.new(1, 0)
	local ct = UIKit.label(cnt, "0", 14, UIKit.TEXT, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 }, UIKit.HEAD)
	b.MouseButton1Down:Connect(function() UIKit.sfx("tap") end)
	slots[it.id] = { button = b, stroke = st, vpf = vpf, count = cnt, countText = ct }
	return b
end
for _, it in ipairs(Items.LIST) do slot(it) end

local drawDetail
local function refresh()
	local c = counts()
	local any = false
	for _, it in ipairs(Items.LIST) do
		local n = c[it.id] or 0
		if n > 0 then any = true end
		local s = slots[it.id]
		s.countText.Text = "x" .. n
		s.count.BackgroundColor3 = n > 0 and UIKit.INK or UIKit.CARD_MUTED
		s.vpf.ImageTransparency = n > 0 and 0 or 0.55
		s.stroke.Color = (selected == it.id) and UIKit.ORANGE or UIKit.CARD_LINE
		s.stroke.Thickness = (selected == it.id) and 3 or 1.5
	end
	if any or player:GetAttribute("ArmedScout") or player:GetAttribute("ArmedPress") then railBtn.Visible = true end
	local new = player:GetAttribute("ItemsNew") or 0
	badge.Visible = new > 0 and not gui.Enabled
	badgeText.Text = new > 9 and "9+" or tostring(new)
	if gui.Enabled then drawDetail() end
end

drawDetail = function()
	for _, ch in ipairs(detail:GetChildren()) do
		if not ch:IsA("UIPadding") and not ch:IsA("UICorner") and not ch:IsA("UIStroke") then ch:Destroy() end
	end
	local it = Items.BY_ID[selected]
	if not it then return end
	local n = counts()[it.id] or 0
	local r = Items.RARITY[it.rarity]
	UIKit.label(detail, it.name, 22, UIKit.INK, { Size = UDim2.new(1, 0, 0, 26) }, UIKit.HEAD)
	UIKit.label(detail, r.name, 14, UIKit.darker(r.color, 0.55), { Position = UDim2.new(0, 0, 0, 26), Size = UDim2.new(1, 0, 0, 18) }, UIKit.HEAD)
	UIKit.label(detail, it.desc, 16, UIKit.INK_SOFT, { Position = UDim2.new(0, 0, 0, 50), Size = UDim2.new(1, 0, 0, 62),
		TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }, UIKit.BODY)
	if n == 0 then
		UIKit.label(detail, "HOW TO GET IT", 14, UIKit.MUTED_TEXT, { Position = UDim2.new(0, 0, 0, 118), Size = UDim2.new(1, 0, 0, 18) }, UIKit.HEAD)
		UIKit.label(detail, WHERE[it.id] or "", 16, UIKit.INK_SOFT, { Position = UDim2.new(0, 0, 0, 138), Size = UDim2.new(1, 0, 0, 60),
			TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }, UIKit.BODY)
		return
	end
	-- the USE button says what will happen; some items only work at their moment
	local label, color, ok = "USE", UIKit.GREEN, true
	if it.id == "noncompete" then
		local chased = player:GetAttribute("Carrying") ~= nil
		label, ok = chased and "USE NOW" or "Use it during a chase", chased
	elseif it.id == "scout" and player:GetAttribute("ArmedScout") then
		label, ok = "Waiting for your next hire", false
	elseif it.id == "frontpage" and player:GetAttribute("ArmedPress") then
		label, ok = "Waiting for your next launch", false
	elseif it.use == "arm" then
		label = "GET IT READY"
	end
	local b = UIKit.button(detail, label, ok and color or UIKit.MUTED, { Name = "Use", AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 48) }, { textSize = ok and 20 or 15, silent = true })
	b.MouseButton1Click:Connect(function()
		if not ok then UIKit.sfx("thunk", 0.8) return end
		useItem:FireServer(it.id)
	end)
end

for id, s in pairs(slots) do
	s.button.MouseButton1Click:Connect(function() selected = id; refresh() end)
end

local function setOpen(v)
	if v then UIKit.solo(gui) end
	gui.Enabled = v
	if v then
		if itemsSeen then itemsSeen:FireServer() end
		-- open on something you have
		local c = counts()
		if (c[selected] or 0) == 0 then
			for _, it in ipairs(Items.LIST) do if (c[it.id] or 0) > 0 then selected = it.id break end end
		end
	end
	refresh()
end
railBtn.MouseButton1Click:Connect(function() setOpen(not gui.Enabled) end)
if closeBtn then closeBtn.MouseButton1Click:Connect(function() setOpen(false) end) end
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Q and gui.Enabled then setOpen(false) end
end)

-- ============ BOOSTS (right column) ============
-- what is running right now, and how long it has left

local boosts = UIKit.card(UIKit.column(), { Name = "Boosts", LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 40), Visible = false }, { radius = 14 })
local bList = Instance.new("UIListLayout", boosts)
bList.Padding = UDim.new(0, 2)
local bPad = Instance.new("UIPadding", boosts)
bPad.PaddingLeft, bPad.PaddingTop, bPad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 6), UDim.new(0, 6)
local boostRows = {}
local function boostRow(id)
	local row = Instance.new("Frame")
	row.Name = "Boost_" .. id
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -8, 0, 28)
	row.Visible = false
	row.Parent = boosts
	local vpf = Instance.new("ViewportFrame")
	vpf.BackgroundTransparency = 1
	vpf.Size = UDim2.new(0, 28, 0, 28)
	vpf.Parent = row
	Items.icon(id, vpf)
	local t = UIKit.label(row, "", 16, UIKit.INK_SOFT, { Position = UDim2.new(0, 34, 0, 0), Size = UDim2.new(1, -34, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd }, UIKit.HEAD)
	boostRows[id] = { row = row, text = t }
end
for _, id in ipairs({ "coffee", "energy", "scout", "frontpage" }) do boostRow(id) end

local function clockText(sec) sec = math.max(0, math.floor(sec)); return ("%d:%02d"):format(sec // 60, sec % 60) end

-- ============ WHERE ITEMS MATTER ============

local quick = Instance.new("ScreenGui")
quick.Name = "ItemQuick"
quick.ResetOnSpawn = false
quick.IgnoreGuiInset = true
quick.DisplayOrder = 8
UIKit.safe(quick)
quick.Parent = player.PlayerGui

-- a Cold Brew beside WRITE CODE. v5: 30 px clear of it (it was 9 px from the
-- button you mash, so a drifting thumb burned a coffee), a sticker outline, and a
-- gold "3x" tag that says what it does
local brew = UIKit.button(quick, "", UIKit.CARD, { Name = "Brew", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(0.5, -148, 1, -22),
	Size = UDim2.new(0, 60, 0, 60), Visible = false }, { radius = 30, dark = true, silent = true, stroke = UIKit.INK_SOFT })
local brewTag = Instance.new("TextLabel")
brewTag.Name = "Tag"
brewTag.AnchorPoint = Vector2.new(0.5, 0.5)
brewTag.Position = UDim2.new(1, -4, 0, 4)
brewTag.Size = UDim2.new(0, 34, 0, 22)
brewTag.BackgroundColor3 = UIKit.GOLD
brewTag.Text = "3x"
brewTag.TextColor3 = UIKit.INK
brewTag.TextSize = 14
brewTag.Font = UIKit.HEAD
brewTag.ZIndex = brew.ZIndex + 4
brewTag.Parent = brew
Instance.new("UICorner", brewTag).CornerRadius = UDim.new(1, 0)
local tagStroke = Instance.new("UIStroke", brewTag)
tagStroke.Color = UIKit.INK
tagStroke.Thickness = 2
tagStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
local brewVpf = Instance.new("ViewportFrame")
brewVpf.BackgroundTransparency = 1
brewVpf.Position = UDim2.new(0, 6, 0, 4)
brewVpf.Size = UDim2.new(1, -12, 1, -14)
brewVpf.ZIndex = brew.ZIndex + 1
brewVpf.Parent = brew
Items.icon("coffee", brewVpf)
local brewCount = UIKit.label(brew, "", 14, UIKit.CARD_TEXT, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4),
	Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = brew.ZIndex + 2 }, UIKit.HEAD)
brew.MouseButton1Click:Connect(function() UIKit.sfx("tap"); useItem:FireServer("coffee") end)

-- a rescue under the headhunter warning (Non-Compete first, else an Energy Drink)
local rescue = UIKit.button(quick, "", UIKit.RED, { Name = "Rescue", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 152),
	Size = UDim2.new(0, 250, 0, 46), Visible = false }, { textSize = 16 })
local rescueId
rescue.MouseButton1Click:Connect(function() if rescueId then useItem:FireServer(rescueId) end end)

local function chased()
	local sv = workspace:FindFirstChild("SiliconValley")
	local row = sv and sv:FindFirstChild("TalentRow")
	if not row then return false end
	for _, m in ipairs(row:GetChildren()) do
		if m:GetAttribute("Chaser") and m:GetAttribute("ChasingUserId") == player.UserId then return true end
	end
	return false
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	if gui.Enabled then
		local t = os.clock()
		for _, sp in ipairs(spin) do
			if sp.m.Parent then sp.m:PivotTo(sp.base * CFrame.Angles(0, math.sin(t * 1.1 + sp.phase) * 0.42, 0)) end
		end
	end
	acc += dt
	if acc < 0.2 then return end
	acc = 0
	local c = counts()
	local t = now()
	-- boosts card
	local code, energy = (player:GetAttribute("BoostCode") or 0) - t, (player:GetAttribute("BoostEnergy") or 0) - t
	boostRows.coffee.row.Visible = code > 0
	boostRows.coffee.text.Text = ("3x code  %s"):format(clockText(code))
	boostRows.energy.row.Visible = energy > 0
	boostRows.energy.text.Text = ("+5 scooter speed  %s"):format(clockText(energy))
	boostRows.scout.row.Visible = player:GetAttribute("ArmedScout") == true
	boostRows.scout.text.Text = "Next hire +1 talent"
	boostRows.frontpage.row.Visible = player:GetAttribute("ArmedPress") == true
	boostRows.frontpage.text.Text = "Next launch x2"
	local shown = 0
	for _, r in pairs(boostRows) do if r.row.Visible then shown += 1 end end
	boosts.Visible = shown > 0
	boosts.Size = UDim2.new(1, 0, 0, 12 + shown * 30)
	-- the brew button: you have one and none is running
	local writeCode = player.PlayerGui:FindFirstChild("Hud") and player.PlayerGui.Hud:FindFirstChild("WriteCode")
	local codeLabel = writeCode and writeCode:FindFirstChild("Label")
	-- only beside WRITE CODE itself (not beside a waiting LAUNCH, where it would be the wrong tap)
	brew.Visible = (c.coffee or 0) > 0 and code <= 0 and writeCode ~= nil and writeCode.Visible
		and codeLabel ~= nil and codeLabel.Text == "WRITE CODE"
	brewCount.Text = "x" .. (c.coffee or 0)
	-- the rescue: only while something is chasing you, and only if you can do something
	local id = ((c.noncompete or 0) > 0 and "noncompete") or (((c.energy or 0) > 0 and energy <= 0) and "energy") or nil
	local show = id ~= nil and player:GetAttribute("Carrying") ~= nil and chased()
	if show then
		rescueId = id
		local it = Items.BY_ID[id]
		local lbl = rescue:FindFirstChild("Label")
		if lbl then lbl.Text = ("USE %s  (%d)"):format(string.upper(it.name), c[id] or 0) end
		UIKit.setButtonColor(rescue, id == "noncompete" and UIKit.RED or UIKit.GREEN)
		-- sit just under the headhunter chip
		local chip = player.PlayerGui:FindFirstChild("TalentRow") and player.PlayerGui.TalentRow:FindFirstChild("Danger")
		if chip and chip.Visible then
			rescue.Position = UDim2.new(0, chip.AbsolutePosition.X + chip.AbsoluteSize.X / 2, 0, chip.AbsolutePosition.Y + chip.AbsoluteSize.Y + 8)
			rescue.AnchorPoint = Vector2.new(0.5, 0)
		end
	end
	rescue.Visible = show
end)

-- ============ NEW ITEMS ============

local fx = Instance.new("ScreenGui")
fx.Name = "ItemFx"
fx.ResetOnSpawn = false
fx.IgnoreGuiInset = true
fx.DisplayOrder = 19
UIKit.safe(fx)
fx.Parent = player.PlayerGui

local function gotCard(id, n, source, done)
	local it = Items.BY_ID[id]
	if not it then
		if done then done() end
		return
	end
	local vp = workspace.CurrentCamera.ViewportSize
	local card = UIKit.card(fx, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.42, 0), Size = UDim2.new(0, 300, 0, 96) },
		{ radius = 18, strokeWidth = 3, stroke = Items.RARITY[it.rarity].color })
	local vpf = Instance.new("ViewportFrame")
	vpf.BackgroundTransparency = 1
	vpf.Position = UDim2.new(0, 8, 0, 8)
	vpf.Size = UDim2.new(0, 80, 0, 80)
	vpf.Parent = card
	local m = Items.icon(id, vpf)
	local base = m and m:GetPivot()
	UIKit.label(card, ("+%d %s"):format(n or 1, it.name), 20, UIKit.CARD_TEXT, { Position = UDim2.new(0, 96, 0, 12), Size = UDim2.new(1, -104, 0, 24),
		TextTruncate = Enum.TextTruncate.AtEnd }, UIKit.HEAD)
	UIKit.label(card, it.short, 16, UIKit.darker(Items.RARITY[it.rarity].color, 0.55), { Position = UDim2.new(0, 96, 0, 38), Size = UDim2.new(1, -104, 0, 18) }, UIKit.HEAD)
	UIKit.label(card, source or "", 14, UIKit.CARD_MUTED, { Position = UDim2.new(0, 96, 0, 60), Size = UDim2.new(1, -104, 0, 18),
		TextTruncate = Enum.TextTruncate.AtEnd }, UIKit.HEAD)
	local sc = Instance.new("UIScale", card)
	sc.Scale = 0.4
	TweenService:Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	UIKit.sfx("ding", 1.2)
	task.spawn(function()
		local t0 = os.clock()
		while card.Parent and os.clock() - t0 < 1.9 do
			if m then m:PivotTo(base * CFrame.Angles(0, math.sin((os.clock() - t0) * 3) * 0.4, 0)) end
			task.wait()
		end
		-- then it flies into the BAG button
		railBtn.Visible = true
		task.wait()
		local to = railBtn.AbsolutePosition + railBtn.AbsoluteSize / 2
		local tw = TweenService:Create(card, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
			{ Position = UDim2.new(0, to.X, 0, to.Y) })
		TweenService:Create(sc, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { Scale = 0.15 }):Play()
		tw:Play()
		tw.Completed:Wait()
		card:Destroy()
		if done then done() end
		local bs = railBtn:FindFirstChildOfClass("UIScale")
		if bs then
			bs.Scale = 1.25
			TweenService:Create(bs, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end)
	return card
end

itemEvent.OnClientEvent:Connect(function(e)
	if type(e) ~= "table" then return end
	if e.kind == "got" then
		-- v4.2: one card at a time through the director (centre lane, P2); it
		-- used to land on the Daily panel the moment a claim granted an item
		local shown
		Notify.show({ lane = "centre", priority = 2, key = "item",
			close = function() if shown then shown:Destroy() end end,
			open = function(done) shown = gotCard(e.id, e.n, e.source, done) end })
	elseif e.kind == "used" then
		local it = Items.BY_ID[e.id]
		UIKit.sfx(e.id == "coffee" and "coins" or "ding", 1.1, 0.4)
		if gui.Enabled and it and (it.use == "arm" or it.use == "chase") then setOpen(false) end
	elseif e.kind == "fired" then
		UIKit.sfx("levelup", 1.1, 0.4)
	elseif e.kind == "refused" then
		UIKit.sfx("thunk", 0.8)
		local lbl = detail:FindFirstChild("Refused")
		if lbl then lbl:Destroy() end
		if gui.Enabled then
			UIKit.label(detail, e.text or "", 14, UIKit.RED, { Name = "Refused", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -54),
				Size = UDim2.new(1, 0, 0, 36), TextWrapped = true }, UIKit.HEAD)
		end
	end
end)

for _, a in ipairs({ "Items", "ItemsNew", "ArmedScout", "ArmedPress", "Carrying" }) do
	player:GetAttributeChangedSignal(a):Connect(refresh)
end
refresh()

-- v5: the rail tile shows when this menu is open
UIKit.bindRail(railBtn, gui)
