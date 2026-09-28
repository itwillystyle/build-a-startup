--[[
	ProductClient -- LocalScript in StarterPlayer -> StarterPlayerScripts.

	Two small things the product loop needs on screen:
	  1. THE MARKET PICK: three cards when a product is ready. One tap. The
	     server ships to card 1 on its own after 60s, so this never blocks.
	  2. TOASTS: a one-line banner for launches and IPOs (yours and others').

	All buttons >= 44px. Nothing here dims the screen or steals the camera.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("SVRemotes")
local productReady = remotes:WaitForChild("ProductReady")
local pickMarket = remotes:WaitForChild("PickMarket")
local toast = remotes:WaitForChild("Toast")
local offerEvent = remotes:WaitForChild("Offer")
local answerOffer = remotes:WaitForChild("AnswerOffer")

local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local Notify = require(ReplicatedStorage:WaitForChild("Notify"))
-- v3.1: one palette (UIKit); these names stay for the three-market picker below
local PANEL = UIKit.SURFACE
local CARD = UIKit.CARD
local INK = UIKit.CARD_TEXT
local MUTED = UIKit.CARD_MUTED
local GOLD = UIKit.GOLD
local GOOD = UIKit.GREEN

local gui = Instance.new("ScreenGui")
gui.Name = "Product"
gui.ResetOnSpawn = false
gui.DisplayOrder = 9
gui.IgnoreGuiInset = true
gui.Enabled = player:GetAttribute("MenuDone") == true     -- HUD waits for PLAY
player:GetAttributeChangedSignal("MenuDone"):Connect(function() gui.Enabled = true end)
gui.Parent = player:WaitForChild("PlayerGui")

-- ============ THE PICK ============

local panel = Instance.new("Frame")
panel.Name = "Pick"
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0, 150)      -- under cash pill (10..86) + guide strip (92..136)
panel.Size = UDim2.new(0.92, 0, 0, 236)
panel.BackgroundColor3 = UIKit.CARD           -- v3.0: HUD cards are white (Run a Restaurant!)
panel.BackgroundTransparency = 0
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
local cap = Instance.new("UISizeConstraint", panel)
cap.MaxSize = Vector2.new(640, 236)
local stroke = Instance.new("UIStroke", panel)
stroke.Color = UIKit.CARD_LINE
stroke.Thickness = 1.5

local title = Instance.new("TextLabel")
title.Position = UDim2.new(0, 16, 0, 10)
title.Size = UDim2.new(1, -32, 0, 26)
title.BackgroundTransparency = 1
title.Text = "PRODUCT READY!  Pick who it is for"
title.TextColor3 = UIKit.CARD_TEXT
title.TextSize = 20
title.Font = UIKit.HEAD
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local row = Instance.new("Frame")
row.Position = UDim2.new(0, 12, 0, 44)
row.Size = UDim2.new(1, -24, 1, -56)
row.BackgroundTransparency = 1
row.Parent = panel
local layout = Instance.new("UIListLayout", row)
layout.FillDirection = Enum.FillDirection.Horizontal
layout.Padding = UDim.new(0, 10)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

local cards = {}
for i = 1, 3 do
	local b = Instance.new("TextButton")
	b.Name = "Card" .. i
	b.LayoutOrder = i
	b.Size = UDim2.new(0.31, 0, 1, 0)
	b.BackgroundColor3 = CARD
	b.Text = ""
	b.AutoButtonColor = true
	b.Parent = row
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
	local st = Instance.new("UIStroke", b)
	st.Color = Color3.fromRGB(60, 68, 84)

	local nm = Instance.new("TextLabel")
	nm.Name = "Market"
	nm.Position = UDim2.new(0, 8, 0, 12)
	nm.Size = UDim2.new(1, -16, 0, 30)
	nm.BackgroundTransparency = 1
	nm.TextColor3 = INK
	nm.TextSize = 24
	nm.Font = UIKit.HEAD
	nm.TextScaled = true
	nm.Parent = b

	local bl = Instance.new("TextLabel")
	bl.Name = "Blurb"
	bl.Position = UDim2.new(0, 8, 0, 48)
	bl.Size = UDim2.new(1, -16, 0, 40)
	bl.BackgroundTransparency = 1
	bl.TextColor3 = MUTED
	bl.TextSize = 14
	bl.Font = Enum.Font.Gotham
	bl.TextWrapped = true
	bl.Parent = b

	-- v2.6.2: what it pays (shape) and who it wants (fit)
	local shp = Instance.new("TextLabel")
	shp.Name = "Shape"
	shp.Position = UDim2.new(0, 8, 0, 88)
	shp.Size = UDim2.new(1, -16, 0, 32)
	shp.BackgroundTransparency = 1
	shp.TextColor3 = INK
	shp.TextSize = 13
	shp.Font = Enum.Font.GothamBold
	shp.TextWrapped = true
	shp.RichText = true
	shp.Parent = b

	local fit = Instance.new("TextLabel")
	fit.Name = "Fit"
	fit.Position = UDim2.new(0, 8, 0, 122)
	fit.Size = UDim2.new(1, -16, 0, 26)
	fit.BackgroundTransparency = 1
	fit.TextSize = 13
	fit.Font = Enum.Font.GothamBold
	fit.TextWrapped = true
	fit.Parent = b

	local sp = Instance.new("TextLabel")
	sp.Name = "Spike"
	sp.Position = UDim2.new(0, 8, 1, -34)
	sp.Size = UDim2.new(1, -16, 0, 24)
	sp.BackgroundTransparency = 1
	sp.TextColor3 = GOLD
	sp.TextSize = 22
	sp.Font = UIKit.HEAD
	sp.Parent = b

	-- v2.8: the single LAUNCH card is a big green button with a rocket
	local ic = UIKit.icon(b, "rocket", 58, Color3.fromRGB(255, 255, 255), {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 18, 0.5, 0), Visible = false })

	b.MouseButton1Click:Connect(function()
		if not panel.Visible then return end
		pickMarket:FireServer(i)
		panel.Visible = false
	end)
	cards[i] = { btn = b, nm = nm, bl = bl, sp = sp, shp = shp, fit = fit, ic = ic, stroke = st }
end

local offerSerial = 0
-- v2.5.1 ONE DECISION AT A TIME. The picker, the build catalog and a poach
-- offer used to land in the same frame. Now: the picker never opens over
-- build mode (the bar says so and it opens on close), and an offer waits
-- until the picker is answered.
local pickerHeld = false
-- v2.8: the name modal counts as "busy" too (it stacked on top of the LAUNCH card)
local function building() return player:GetAttribute("BuildModeOpen") == true or player:GetAttribute("NamingOpen") == true end
--[[ v3.0.3: ONE PLACE FOR "PRODUCT READY". Measured on screen 25 Sep: the
same fact was said three times (guide strip, work bar, and a 640 x 148 card
dead centre over the player and the world). A single LAUNCH now takes over
the work bar's own spot, top-right, as a compact button; the three-market
picker (non-V3) stays centred because it is a real decision with three cards. ]]
local singleMode = false
local function home()
	if singleMode then return UDim2.new(1, -14, 0, 120), Vector2.new(1, 0) end
	return UDim2.new(0.5, 0, 0, 150), Vector2.new(0.5, 0)
end
local function showPicker()
	pickerHeld = false
	local pos, anchor = home()
	panel.AnchorPoint = anchor
	panel.Visible = true
	panel.Position = pos + UDim2.new(0, 0, 0, -30)
	TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Position = pos }):Play()
end
-- ============ THE LAUNCH CARD (v3.1) ============
--[[ "Your app is ready" was said three times (guide strip, work bar, and a
640 x 148 card dead centre over the player). Now it is ONE green card at the
top of the right column, above the quest card: rocket, LAUNCH!, the payday,
and a bar counting down to the half-pay auto-launch (the old game said
nothing about that and then scolded you with "AUTO-LAUNCHED (half pay)"). ]]
local launchCol = UIKit.column()
local launch, launchLabel = UIKit.button(launchCol, "", UIKit.GREEN, {
	Name = "Launch", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 106), Visible = false,
}, { textSize = 26, silent = false })
UIKit.art(launch, "rocket", 56, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0, 32), ZIndex = launch.ZIndex + 2 })
local lTitle = UIKit.outlined(launch, "LAUNCH!", 28, UIKit.TEXT, {
	Position = UDim2.new(0, 64, 0, 6), Size = UDim2.new(1, -72, 0, 32), ZIndex = launch.ZIndex + 2,
})
local lPay = UIKit.outlined(launch, "", 17, UIKit.TEXT, {
	Position = UDim2.new(0, 64, 0, 38), Size = UDim2.new(1, -72, 0, 20), ZIndex = launch.ZIndex + 2,
})
local lTrack = Instance.new("Frame")
lTrack.BackgroundColor3 = UIKit.darker(UIKit.GREEN, 0.7)
lTrack.BorderSizePixel = 0
lTrack.Position = UDim2.new(0, 10, 1, -22)
lTrack.Size = UDim2.new(1, -20, 0, 12)
lTrack.ZIndex = launch.ZIndex + 1
lTrack.Parent = launch
Instance.new("UICorner", lTrack).CornerRadius = UDim.new(1, 0)
local lFill = Instance.new("Frame")
lFill.BackgroundColor3 = UIKit.TEXT
lFill.BorderSizePixel = 0
lFill.Size = UDim2.new(1, 0, 1, 0)
lFill.ZIndex = launch.ZIndex + 2
lFill.Parent = lTrack
Instance.new("UICorner", lFill).CornerRadius = UDim.new(1, 0)
-- the auto-launch warning gets its own line (it sat on top of the payday at 12 px)
local lAuto = UIKit.label(launch, "", 14, UIKit.TEXT, {
	Position = UDim2.new(0, 12, 0, 62), Size = UDim2.new(1, -24, 0, 16), ZIndex = launch.ZIndex + 2,
	TextTruncate = Enum.TextTruncate.AtEnd,
}, UIKit.HEAD)
lAuto.TextStrokeTransparency = 0.6
lAuto.TextStrokeColor3 = UIKit.darker(UIKit.GREEN, 0.4)
local lWrap = Instance.new("UIScale", lTitle)
local autoAt, launchedSerial = nil, 0

local lastLaunch
-- v3.2: an armed Front Page doubles the payday; the card says so before you tap
local function payText(o)
	local press = player:GetAttribute("ArmedPress") == true
	return press and ("+%s  Front Page x2"):format(UIKit.money((o.payday or 0) * 2)) or ("+%s payday"):format(UIKit.money(o.payday or 0))
end
player:GetAttributeChangedSignal("ArmedPress"):Connect(function() if lastLaunch then lPay.Text = payText(lastLaunch) end end)
local function showLaunch(o)
	launchedSerial += 1
	lastLaunch = o
	lPay.Text = payText(o)
	autoAt = o.autoAt
	launch.Visible = true
	UIKit.sfx("ding", 0.9)
end
launch.MouseButton1Click:Connect(function()
	if not launch.Visible then return end
	pickMarket:FireServer(1)
	launch.Visible = false
end)
game:GetService("RunService").RenderStepped:Connect(function()
	if not launch.Visible then return end
	lWrap.Scale = 1 + 0.05 * (0.5 + 0.5 * math.sin(os.clock() * 5))
	if autoAt then
		local left = math.max(0, autoAt - workspace:GetServerTimeNow())
		lFill.Size = UDim2.new(math.clamp(left / 60, 0, 1), 0, 1, 0)
		lAuto.Text = ("Auto-launch in %ds (half pay)"):format(math.ceil(left))
	end
end)

productReady.OnClientEvent:Connect(function(options)
	if not options then panel.Visible = false; pickerHeld = false; launch.Visible = false return end   -- server shipped it
	if #options == 1 and options[1].launch then showLaunch(options[1]) return end
	-- v2.7.0: a single LAUNCH card fills the row; three market cards share it
	local single = #options == 1
	singleMode = single
	title.Text = single and "PRODUCT READY" or "PRODUCT READY!  Pick who it is for"
	title.TextSize = single and 14 or 20
	-- v2.8: one card needs a short panel, not the 236 px three-card frame
	-- v3.0.3: and a single LAUNCH is a compact button in the work bar's slot
	panel.Size = single and UDim2.new(0, 330, 0, 112) or UDim2.new(0.92, 0, 0, 236)
	row.Position = single and UDim2.new(0, 8, 0, 30) or UDim2.new(0, 12, 0, 44)
	row.Size = single and UDim2.new(1, -16, 1, -38) or UDim2.new(1, -24, 1, -56)
	title.Position = single and UDim2.new(0, 12, 0, 6) or UDim2.new(0, 16, 0, 10)
	for i = 1, 3 do
		local o = options[i]
		local c = cards[i]
		c.btn.Size = UDim2.new(single and 1 or 0.31, 0, 1, 0)
		local launchCard = o and o.launch and true or false
		c.ic.Visible = launchCard
		c.btn.BackgroundColor3 = launchCard and Color3.fromRGB(62, 196, 104) or CARD
		c.stroke.Color = launchCard and Color3.fromRGB(34, 120, 62) or Color3.fromRGB(60, 68, 84)
		c.nm.Position = launchCard and UDim2.new(0, 70, 0, 8) or UDim2.new(0, 8, 0, 12)
		c.nm.Size = launchCard and UDim2.new(1, -82, 0, 30) or UDim2.new(1, -16, 0, 30)
		c.nm.TextXAlignment = launchCard and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center
		c.shp.Position = launchCard and UDim2.new(0, 70, 0, 40) or UDim2.new(0, 8, 0, 88)
		c.shp.Size = launchCard and UDim2.new(1, -82, 0, 22) or UDim2.new(1, -16, 0, 32)
		c.shp.Font = launchCard and UIKit.HEAD or Enum.Font.GothamBold
		c.shp.TextSize = launchCard and 17 or 13
		c.ic.Size = launchCard and UDim2.new(0, 42, 0, 42) or c.ic.Size
		c.ic.Position = launchCard and UDim2.new(0, 14, 0.5, 0) or c.ic.Position
		c.shp.TextXAlignment = launchCard and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center
		c.nm.TextColor3 = launchCard and Color3.fromRGB(255, 255, 255) or INK
		c.bl.Visible = not launchCard
		if o and o.launch then
			c.nm.Text = "LAUNCH " .. string.upper(o.blurb or "")
			c.bl.RichText = false
			c.bl.Text = o.blurb or ""
			c.shp.Text = ("+%s cash now"):format(UIKit.money(o.payday or 0))
			c.fit.Text = ""
			c.sp.Text = ""
			c.btn.Visible = true
		elseif o then
			c.nm.Text = o.name
			c.bl.RichText = true
			if o.tag then
				c.bl.Text = ('<font color="%s"><b>%s</b></font>\n%s'):format(o.good and "#5AD282" or "#FF8C8C", o.tag, o.blurb)
			else
				c.bl.Text = o.blurb
			end
			if o.shape then
				c.shp.Text = ('<font color="#FFD046">%s</font>\n+%s now · x%.1f for %s min'):format(
					o.shape, UIKit.money and UIKit.money(o.payday or 0) or ("$" .. tostring(o.payday or 0)), o.boost or 1,
					(o.minutes or 5) % 1 == 0 and tostring(o.minutes) or ("%.1f"):format(o.minutes or 5))
			else
				c.shp.Text = ""
			end
			c.fit.Text = o.fit or ""
			c.fit.TextColor3 = (o.fitCount or 0) > 0 and GOOD or MUTED
			-- stars, not multipliers: a nine-year-old reads three stars instantly.
			-- v2.6.2: spike is now trend x saturation x team fit (base is equal)
			local spike = o.spike or 1
			local stars = spike >= 1.8 and 4 or spike >= 1.3 and 3 or spike >= 0.9 and 2 or 1
			c.sp.Text = string.rep("★", stars) .. string.rep("☆", 4 - stars)
			c.btn.Visible = true
		else
			c.btn.Visible = false
		end
	end
	if building() then pickerHeld = true else showPicker() end
	-- the server auto-ships at 60s; close the panel with it. v2.5.1: only THIS
	-- offer's timer may close it (an older offer's timer used to close a newer panel)
	offerSerial = (offerSerial or 0) + 1
	local mine = offerSerial
	task.delay(60, function() if offerSerial == mine then panel.Visible = false; pickerHeld = false end end)
end)

-- (v3.1: the NEXT PRODUCT bar is gone. Product progress fills INSIDE the
-- WRITE CODE button now, HudClient; the bar was 300 px from what filled it.)

-- ============ ACQUISITION OFFERS ============

local offer = Instance.new("Frame")
offer.Name = "OfferPanel"
offer.AnchorPoint = Vector2.new(0.5, 0)
offer.Position = UDim2.new(0.5, 0, 0, 150)      -- top, under the guide strip; the BUILD panel owns the bottom
offer.Size = UDim2.new(0.9, 0, 0, 136)
offer.BackgroundColor3 = PANEL
offer.BackgroundTransparency = 0.05
offer.Visible = false
offer.Parent = gui
Instance.new("UICorner", offer).CornerRadius = UDim.new(0, 14)
local ocap = Instance.new("UISizeConstraint", offer)
ocap.MaxSize = Vector2.new(520, 136)
local ostroke = Instance.new("UIStroke", offer)
ostroke.Color = GOLD
ostroke.Thickness = 2

local oTitle = UIKit.heading(offer, "", 20, GOLD, {
	Position = UDim2.new(0, 16, 0, 10), Size = UDim2.new(1, -32, 0, 26), TextTruncate = Enum.TextTruncate.AtEnd,
})
-- v1.8: the trade in TWO plain lines. Green = what you get, in money AND in
-- minutes of income (the one unit every player already understands). Grey =
-- the cost, one sentence, no numbers. ALUMNI is a reward, so it is told AFTER
-- the sale (server toast), never in the decision.
local oGain = UIKit.heading(offer, "", 19, GOOD, { Position = UDim2.new(0, 16, 0, 38), Size = UDim2.new(1, -32, 0, 24) })
local oLoss = UIKit.label(offer, "", 14, Color3.fromRGB(200, 204, 214), { Position = UDim2.new(0, 16, 0, 62), Size = UDim2.new(1, -32, 0, 18) })
local accept = UIKit.button(offer, "", GOOD, {
	AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -12), Size = UDim2.new(0, 170, 0, 46),
}, { dark = true, textSize = 18 })
local decline = UIKit.button(offer, "KEEP", CARD, {
	AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -196, 1, -12), Size = UDim2.new(0, 130, 0, 46),
}, { textSize = 16 })

local currentOffer = nil
local queuedOffer = nil
local function showOffer(o)
	currentOffer = o
	oTitle.Text = ("%s wants to hire %s away!"):format(o.rival, o.who)
	local mins = o.minutes or 0
	local minsText = mins >= 1 and ("%.0f min of income"):format(mins) or ("%.0f sec of income"):format(mins * 60)
	oGain.Text = ("+%s now   (%s)"):format(UIKit.money(o.amount), minsText)
	oLoss.Text = ("You lose %s. A new hire starts at the bottom."):format(o.who)
	accept.Label.Text = "TAKE  " .. UIKit.money(o.amount)
	-- if the product picker is open at the same spot, sit under it
	offer.Position = panel.Visible and UDim2.new(0.5, 0, 0, 150 + panel.AbsoluteSize.Y + 12) or UDim2.new(0.5, 0, 0, 150)
	offer.Visible = true
	local left = math.max(1, 30 - (os.clock() - (o._t or os.clock())))
	task.delay(left, function() if currentOffer == o then offer.Visible = false; currentOffer = nil end end)
end
local function flush()
	if pickerHeld and not building() then showPicker() end
	if queuedOffer and not building() and not panel.Visible and not pickerHeld then
		local o = queuedOffer
		queuedOffer = nil
		if os.clock() - o._t < 27 then task.delay(1.5, function() showOffer(o) end) end
	end
end
offerEvent.OnClientEvent:Connect(function(o)
	o._t = os.clock()
	if building() or panel.Visible or pickerHeld then queuedOffer = o else showOffer(o) end
end)
player:GetAttributeChangedSignal("BuildModeOpen"):Connect(flush)
player:GetAttributeChangedSignal("NamingOpen"):Connect(flush)
panel:GetPropertyChangedSignal("Visible"):Connect(flush)
accept.MouseButton1Click:Connect(function()
	if not currentOffer then return end
	answerOffer:FireServer(currentOffer.id, true)
	offer.Visible = false; currentOffer = nil
end)
decline.MouseButton1Click:Connect(function()
	if not currentOffer then return end
	answerOffer:FireServer(currentOffer.id, false)
	offer.Visible = false; currentOffer = nil
end)

-- ============ TOASTS ============
-- v4.2: through the director (Notify.toast, the one bottom toast). Other
-- players' news is ambient (P3, dropped while you are busy); your own lines are
-- progress (P2), or earned (P1) while you carry a recruit, and those leave with
-- the carry (the 25 Sep test showed "Get home!" under "LOST!").
toast.OnClientEvent:Connect(function(text, kind)
	local news = kind == "news"
	local carrying = player:GetAttribute("Carrying") ~= nil
	Notify.toast(tostring(text), {
		priority = news and 3 or (carrying and 1 or 2),
		untilCarryEnds = carrying and not news,
	})
end)
