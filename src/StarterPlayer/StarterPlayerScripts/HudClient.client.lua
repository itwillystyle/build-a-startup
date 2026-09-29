--[[
	HudClient -- LocalScript in StarterPlayer -> StarterPlayerScripts.

	THE ONE NUMBER, and every moment the game pays you.

	Top centre is money and income, nothing else (the default leaderboard is
	hidden: it was the "too many numbers"). Bottom centre is WRITE CODE, the
	verb you can always do; since v3.1 it also shows the next product filling
	up inside it, so cause and effect sit in one place (the old NEXT PRODUCT
	bar was 300 px away from the button that fills it).

	v3.1 REWARDS THAT ARE FELT (both 25 Sep reviews: "almost nothing makes a
	sound", "a Star hire looks the same as scooter trivia"). This script owns
	the celebrations the server sends on SVRemotes.Celebrate:
	  launch     coins stream from the launch button into your cash, +$X under it
	  hq         a banner: HQ LEVEL n, the new name, what it unlocked, confetti
	  milestone  a chip under the cash: "$100K earned · +2% money forever"
	  spinAsk    the spin-off confirm card: what you keep vs what resets
	  spin       the spin-off ceremony
	and the WELCOME BACK card: offline earnings you COLLECT, coins and all
	(before, they were added silently before the HUD even loaded).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
-- v3.2.1: a phone held upright squeezed the whole HUD under Roblox's chat and
-- top bar (his portrait test). Tycoons play sideways: landscape, either way up.
pcall(function() player:WaitForChild("PlayerGui").ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor end)
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local Notify = require(ReplicatedStorage:WaitForChild("Notify"))
local remotes = ReplicatedStorage:WaitForChild("SVRemotes")

-- hide the default leaderboard (retry: CoreGui can refuse for the first frames)
task.spawn(function()
	for _ = 1, 20 do
		local ok = pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false) end)
		if ok then break end
		task.wait(0.25)
	end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "Hud"
gui.ResetOnSpawn = false
gui.DisplayOrder = 4
gui.IgnoreGuiInset = true
UIKit.safe(gui)
gui.Parent = player:WaitForChild("PlayerGui")

-- celebrations sit above every menu
local fx = Instance.new("ScreenGui")
fx.Name = "Celebrate"
fx.ResetOnSpawn = false
fx.DisplayOrder = 20
fx.IgnoreGuiInset = true
UIKit.safe(fx)
fx.Parent = player.PlayerGui

local function tween(o, t, props, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end
-- fading outlined text: the UIStroke has its own Transparency and must fade too,
-- or a black ghost of the words stays on screen
local function fadeText(l, t, extra)
	local props = { TextTransparency = 1 }
	for k, v in pairs(extra or {}) do props[k] = v end
	tween(l, t, props)
	for _, st in ipairs(l:GetChildren()) do
		if st:IsA("UIStroke") then tween(st, t, { Transparency = 1 }) end
	end
end

-- ============ MONEY ============
-- Steal An Egg: big green outlined text with a coin, no box.
local pill = Instance.new("Frame")
pill.Name = "Cash"
pill.AnchorPoint = Vector2.new(0.5, 0)
pill.Position = UDim2.new(0.5, 0, 0, 8)
pill.Size = UDim2.new(0, 280, 0, 56)
pill.BackgroundTransparency = 1
pill.Parent = gui
local pillScale = Instance.new("UIScale", pill)
local row = Instance.new("UIListLayout", pill)
row.FillDirection = Enum.FillDirection.Horizontal
row.HorizontalAlignment = Enum.HorizontalAlignment.Center
row.VerticalAlignment = Enum.VerticalAlignment.Center
row.SortOrder = Enum.SortOrder.LayoutOrder   -- v5: coin first (it sorted by name and sat on the right)
row.Padding = UDim.new(0, 8)
local coin = Instance.new("Frame")
coin.Name = "Coin"
coin.Size = UDim2.new(0, 40, 0, 40)
coin.BackgroundColor3 = UIKit.GOLD
coin.BorderSizePixel = 0
coin.LayoutOrder = 1
coin.Parent = pill
Instance.new("UICorner", coin).CornerRadius = UDim.new(1, 0)
local cst = Instance.new("UIStroke", coin)
cst.Color = UIKit.INK
cst.Thickness = 3
local dollar = UIKit.heading(coin, "$", 28, UIKit.INK, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center })
dollar.TextStrokeTransparency = 1
-- v3.6 (V8): the rendered gold coin replaces the flat disc and its "$"
if UIKit.ART and UIKit.ART.coin then
	coin.BackgroundTransparency = 1
	cst.Enabled = false
	dollar.Visible = false
	UIKit.art(coin, "coin", 52, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0) })
end
local cashText = UIKit.outlined(pill, "$0", 44, UIKit.MONEY, {
	Name = "Amount", Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2,
})

-- income line (tap it for the per-building breakdown)
local rateText = UIKit.outlined(gui, "", 18, UIKit.MONEY, {
	Name = "Rate", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 64),
	Size = UDim2.new(0, 220, 0, 22), TextXAlignment = Enum.TextXAlignment.Center,
})
local rateHit = Instance.new("TextButton")
rateHit.Name = "RateHit"
rateHit.BackgroundTransparency = 1
rateHit.Text = ""
rateHit.AnchorPoint = Vector2.new(0.5, 0)
rateHit.Position = UDim2.new(0.5, 0, 0, 54)
rateHit.Size = UDim2.new(0, 200, 0, 44)      -- v5: 200 wide (300 reached the goal card on a phone)
rateHit.Parent = gui

local breakdown = UIKit.card(gui, {
	Name = "Breakdown", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 94),
	Size = UDim2.new(0, 240, 0, 40), Visible = false,
}, { radius = 12 })
local bList = Instance.new("UIListLayout", breakdown)
bList.Padding = UDim.new(0, 2)
local bPad = Instance.new("UIPadding", breakdown)
bPad.PaddingTop = UDim.new(0, 8); bPad.PaddingBottom = UDim.new(0, 8)
bPad.PaddingLeft = UDim.new(0, 12); bPad.PaddingRight = UDim.new(0, 12)
local function drawBreakdown()
	for _, c in ipairs(breakdown:GetChildren()) do if c:IsA("TextLabel") then c:Destroy() end end
	local raw = player:GetAttribute("IncomeRooms") or ""
	local n = 0
	for part in string.gmatch(raw, "[^|]+") do
		local name, v = part:match("^(.-)=(%-?%d+)$")
		if name then
			n += 1
			local val = tonumber(v)
			local l = UIKit.label(breakdown, ("%s   %s%s / sec"):format(name, val < 0 and "-" or "+", UIKit.money(math.abs(val))), 16,
				val < 0 and UIKit.RED_DEEP or UIKit.CARD_TEXT, { Size = UDim2.new(1, 0, 0, 20) }, UIKit.BODY)
			l.LayoutOrder = n
		end
	end
	breakdown.Size = UDim2.new(0, 240, 0, 16 + n * 22)
end
local openSerial = 0
rateHit.MouseButton1Click:Connect(function()
	breakdown.Visible = not breakdown.Visible
	if breakdown.Visible then
		drawBreakdown()
		openSerial += 1
		local mine = openSerial
		task.delay(6, function() if openSerial == mine then breakdown.Visible = false end end)
	end
end)
player:GetAttributeChangedSignal("IncomeRooms"):Connect(function() if breakdown.Visible then drawBreakdown() end end)

-- ============ THE NEXT-ACTION SLOT (v5) ============
--[[ The bottom-centre button is whatever you should do next with your thumb.
Normally WRITE CODE: the verb you can always do, with the next app filling
INSIDE it (a mint fill you can actually see now; the old one was pale green on
green). When the app is ready the SAME button becomes a gold LAUNCH!, with the
payday on it and the full-pay time draining out of it (it used to be a card in
the top-right corner, the hardest reach on a phone, 300 px from the button
that filled it: his Wilz run never pressed it in 19 minutes).

When something else is the goal (build, hire, upgrade), WRITE CODE steps down
a size so the goal card and the world marker are the loud things (DESIGN.md
principle 1). It pulses only when writing code IS the goal. ]]
local writeCodeRemote = remotes:WaitForChild("WriteCode", 10)
local pickMarket = remotes:WaitForChild("PickMarket", 10)
local productReady = remotes:WaitForChild("ProductReady", 10)
local FULL = UDim2.new(0, 236, 0, 64)
local QUIET = UDim2.new(0, 206, 0, 56)
local MINT = Color3.fromRGB(176, 242, 198)
local codeBtn, codeLabel = UIKit.button(gui, "WRITE CODE", UIKit.GREEN, {
	Name = "WriteCode", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -22),
	Size = FULL, ClipsDescendants = false,
}, { textSize = 24, silent = true })
local charge = Instance.new("Frame")
charge.Name = "Charge"
charge.BackgroundColor3 = MINT
charge.BorderSizePixel = 0
charge.Size = UDim2.new(0, 0, 1, -5)
charge.ZIndex = codeBtn.ZIndex
charge.Parent = codeBtn
Instance.new("UICorner", charge).CornerRadius = UDim.new(0, UIKit.RADIUS.md)
local slotArt = UIKit.art(codeBtn, "code", 50, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, -3), ZIndex = codeBtn.ZIndex + 1 })
codeLabel.Position = UDim2.new(0, 56, 0, 0)
codeLabel.Size = UDim2.new(1, -64, 1, -5)
-- the payday line under LAUNCH! (hidden while it is WRITE CODE)
local payLabel = UIKit.label(codeBtn, "", 16, UIKit.INK, {
	Name = "Pay", Position = UDim2.new(0, 56, 0, 33), Size = UDim2.new(1, -64, 0, 20), Visible = false,
	TextXAlignment = Enum.TextXAlignment.Center, ZIndex = codeBtn.ZIndex + 1,
}, UIKit.HEAD)
local codeCaption = UIKit.outlined(codeBtn, "NEXT APP", 14, UIKit.TEXT, {
	Name = "Caption", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -4),
	Size = UDim2.new(1, 40, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = codeBtn.ZIndex + 2,
})
local codeWrap = Instance.new("UIScale")   -- the button's own UIScale is the press squish; pulse the label
codeWrap.Parent = codeLabel
-- the full-pay time left on a waiting LAUNCH: a thin strip draining along the
-- bottom of the face. v5: it used to be a light fill over the WHOLE face, so the
-- loudest button in the game read pale gold for its first minute.
local TIME_W = FULL.X.Offset - 24
local timeBar = Instance.new("Frame")
timeBar.Name = "TimeLeft"
timeBar.BackgroundColor3 = UIKit.GOLD_DEEP
timeBar.BorderSizePixel = 0
timeBar.Position = UDim2.new(0, 12, 1, -13)
timeBar.Size = UDim2.new(0, TIME_W, 0, 6)
timeBar.Visible = false
timeBar.ZIndex = codeBtn.ZIndex + 1
timeBar.Parent = codeBtn
Instance.new("UICorner", timeBar).CornerRadius = UDim.new(1, 0)
-- v5 critique: the seconds live ON the button (a badge on its corner, like a
-- count badge), not in a 14 px caption above it; orange for the last 15 s
local timeBadge = Instance.new("Frame")
timeBadge.Name = "TimeBadge"
timeBadge.AnchorPoint = Vector2.new(1, 0.5)
timeBadge.Position = UDim2.new(1, 24, 0, 0)      -- clear of the "!" in LAUNCH! (at 1,8 it covered it)
timeBadge.Size = UDim2.new(0, 58, 0, 30)
timeBadge.BackgroundColor3 = UIKit.INK
timeBadge.BorderSizePixel = 0
timeBadge.Visible = false
timeBadge.ZIndex = codeBtn.ZIndex + 3
timeBadge.Parent = codeBtn
Instance.new("UICorner", timeBadge).CornerRadius = UDim.new(1, 0)
local tbStroke = Instance.new("UIStroke", timeBadge)
tbStroke.Color = UIKit.PAPER
tbStroke.Thickness = 2
tbStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
local timeText = UIKit.label(timeBadge, "", 18, UIKit.TEXT, {
	Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = codeBtn.ZIndex + 4,
}, UIKit.HEAD)

local launchState     -- { payday, autoAt } while an app waits to launch
local pulsing = false

local function seated()
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local st = hum and hum.SeatPart
	return st ~= nil and st:IsA("VehicleSeat")
end
-- v5: an open menu owns the screen; the slot (a pulsing gold LAUNCH) half under
-- it was a second loud thing next to the menu's own button
-- ModalOpen (client-local): a decision card with its own buttons is up (the
-- while-away COLLECT, the spin-off confirm). The bottom row, WRITE CODE and CAR,
-- steps aside for it, so a thumb slip can't hit the wrong thing
local function menuOpen() return UIKit.menuOpen() end
local function syncCode()
	local inCar = seated()
	-- in a car the speedometer owns the bottom centre: a waiting LAUNCH sits above it
	-- v5: it also steps aside while the company-name box is up (it pulsed behind
	-- the box, two loud things at once, and its caption ran under the box's edge)
	codeBtn.Visible = player:GetAttribute("Shipped") == true and player:GetAttribute("BuildModeOpen") ~= true
		and player:GetAttribute("NamingOpen") ~= true and not menuOpen() and (not inCar or launchState ~= nil)
	codeBtn.Position = UDim2.new(0.5, 0, 1, inCar and -126 or -22)
	local loud = launchState ~= nil or pulsing
	codeBtn.Size = loud and FULL or QUIET
	codeLabel.TextSize = loud and 24 or 22
	-- v5: when the goal is out in the world (hire, build, drive...), WRITE CODE is
	-- a quiet paper button, still one tap away, and the goal is the loud thing
	if not launchState then
		codeBtn:SetAttribute("FixedStroke", (not loud) and UIKit.GREEN or nil)
		codeBtn:SetAttribute("FixedText", (not loud) and UIKit.GREEN_DEEP or nil)
		UIKit.setButtonColor(codeBtn, loud and UIKit.GREEN or UIKit.PAPER)
	end
end
syncCode()
player:GetAttributeChangedSignal("Shipped"):Connect(syncCode)
player:GetAttributeChangedSignal("BuildModeOpen"):Connect(syncCode)
player:GetAttributeChangedSignal("NamingOpen"):Connect(syncCode)
UIKit.onMenuChange(function() syncCode() end)   -- menus are other scripts' guis: one shared watch
-- v4.2: in a car the speedometer owns the bottom centre (it sat on top of WRITE CODE)
local function watchSeat(char)
	local hum = char:WaitForChild("Humanoid", 10)
	if hum then hum:GetPropertyChangedSignal("SeatPart"):Connect(syncCode) end
	syncCode()
end
if player.Character then task.spawn(watchSeat, player.Character) end
player.CharacterAdded:Connect(watchSeat)

local chargeTween
local function setCharge(p)
	if launchState then return end
	p = math.clamp(tonumber(p) or 0, 0, 1)
	if chargeTween then chargeTween:Cancel() end
	chargeTween = tween(charge, 0.25, { Size = UDim2.new(p, 0, 1, -5) })
	codeCaption.Text = p >= 1 and "APP READY!" or ("NEXT APP  " .. math.floor(p * 100) .. "%")
	codeCaption.TextColor3 = UIKit.TEXT
end
setCharge(player:GetAttribute("ProductProgress"))
player:GetAttributeChangedSignal("ProductProgress"):Connect(function() setCharge(player:GetAttribute("ProductProgress")) end)

-- v3.2: an armed Front Page doubles the payday; the button says so before you tap
local function payText()
	if not launchState then return "" end
	local press = player:GetAttribute("ArmedPress") == true
	local pay = (launchState.payday or 0) * (press and 2 or 1)
	return "+" .. UIKit.money(pay) .. (press and "  Front Page" or "")
end
local function setLaunch(o)
	local was = launchState
	launchState = o
	-- a progress tween still running from the last tap would cut the time-left fill short
	if chargeTween then chargeTween:Cancel(); chargeTween = nil end
	if o then
		codeBtn:SetAttribute("FixedStroke", nil)
		codeBtn:SetAttribute("FixedText", nil)
		UIKit.setButtonColor(codeBtn, UIKit.GOLD)
		charge.Size = UDim2.new(0, 0, 1, -5)
		-- solid gold; the full-pay time drains along the bottom and counts on the
		-- corner badge (neither on your first launch, which has no clock)
		timeBar.Visible = o.autoAt ~= nil
		timeBadge.Visible = o.autoAt ~= nil
		codeCaption.Visible = false
		slotArt.Image = UIKit.ART.rocket
		codeLabel.Text = "LAUNCH!"
		codeLabel.Position = UDim2.new(0, 56, 0, 3)
		codeLabel.Size = UDim2.new(1, -64, 0, 30)
		payLabel.Text = payText()
		payLabel.Visible = true
		if not was then
			UIKit.sfx("ding", 0.9)
			local sc = codeBtn:FindFirstChildOfClass("UIScale")
			if sc then sc.Scale = 1.15; tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back) end
		end
	else
		UIKit.setButtonColor(codeBtn, UIKit.GREEN)
		charge.BackgroundColor3 = MINT
		timeBar.Visible = false
		timeBadge.Visible = false
		codeCaption.Visible = true
		slotArt.Image = UIKit.ART.code
		codeLabel.Text = "WRITE CODE"
		codeLabel.Position = UDim2.new(0, 56, 0, 0)
		codeLabel.Size = UDim2.new(1, -64, 1, -5)
		payLabel.Visible = false
		setCharge(player:GetAttribute("ProductProgress"))
	end
	syncCode()
end
player:GetAttributeChangedSignal("ArmedPress"):Connect(function() payLabel.Text = payText() end)
if productReady then
	productReady.OnClientEvent:Connect(function(options)
		if not options then setLaunch(nil) return end
		if #options == 1 and options[1].launch then setLaunch(options[1]) end
	end)
end
local function doLaunch()
	if not launchState or not pickMarket then return end
	pickMarket:FireServer(1)
	setLaunch(nil)
end
-- v4.3: L on a keyboard, Y on a gamepad (his run: LAUNCH was never pressed in 19 minutes)
game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.L or input.KeyCode == Enum.KeyCode.ButtonY then doLaunch() end
end)

local combo, lastTap = 0, 0
codeBtn.MouseButton1Click:Connect(function()
	if launchState then doLaunch() return end
	if writeCodeRemote then writeCodeRemote:FireServer() end
	local now = os.clock()
	combo = (now - lastTap < 0.8) and math.min(combo + 1, 10) or 0
	lastTap = now
	UIKit.sfx("tap", 1 + 0.04 * combo, 0.4)
end)
-- v4.3: what the tap actually paid flies up off the button (the server scales it
-- with your income and your combo), with the combo when it is building
local function floatGain()
	local gain = player:GetAttribute("CodeGain")
	if not gain then return end
	local combo = player:GetAttribute("CodeCombo") or 0
	local text = "+" .. UIKit.money(gain) .. (combo >= 2 and ("  x%.1f"):format(1 + 0.1 * combo) or "")
	local g = UIKit.outlined(gui, text, 20 + math.min(combo, 8), combo >= 5 and UIKit.GOLD or UIKit.MONEY, {
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 200, 0, 28), TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0.5, math.random(-70, 70), 1, -112),
	})
	fadeText(g, 0.7, { Position = g.Position - UDim2.new(0, 0, 0, 56) })
	task.delay(0.75, function() g:Destroy() end)
end
player:GetAttributeChangedSignal("CodeTap"):Connect(floatGain)

-- pulse when writing code IS the objective (and when a launch is waiting)
local function syncPulse()
	local k = player:GetAttribute("Objective")
	pulsing = (k == "wait" or k == "watch")
	syncCode()
end
syncPulse()
player:GetAttributeChangedSignal("Objective"):Connect(syncPulse)
RunService.RenderStepped:Connect(function()
	local t = os.clock()
	if launchState then
		codeWrap.Scale = 1 + 0.07 * (0.5 + 0.5 * math.sin(t * 5.5))
		local at = launchState.autoAt
		if at then
			local left = math.max(0, at - workspace:GetServerTimeNow())
			timeBar.Size = UDim2.new(0, math.floor(TIME_W * math.clamp(left / 60, 0, 1)), 0, 6)
			timeBar.BackgroundColor3 = left <= 15 and UIKit.ORANGE_DEEP or UIKit.GOLD_DEEP
			timeText.Text = math.ceil(left) .. "s"
			timeBadge.BackgroundColor3 = left <= 15 and UIKit.ORANGE_DEEP or UIKit.INK
			codeCaption.Text = ("FULL PAY  %ds"):format(math.ceil(left))
			codeCaption.TextColor3 = left <= 15 and UIKit.ORANGE or UIKit.TEXT
		else
			codeCaption.Text = "APP READY!"
		end
	else
		-- a coach tip on screen has the stage: the pulse waits
		local coach = player.PlayerGui:FindFirstChild("Coach")
		local tip = coach and coach:FindFirstChild("CoachCard")
		codeWrap.Scale = (pulsing and not (tip and tip.Visible) and player:GetAttribute("Celebrating") ~= true) and (1 + 0.06 * (0.5 + 0.5 * math.sin(t * 5))) or 1
	end
end)

-- ============ TICK ============

local shown = 0
local target = 0
local pendingOffline = 0      -- welcome-back money held back until COLLECT
local lastRate = ""

local function ls() return player:FindFirstChild("leaderstats") end

RunService.RenderStepped:Connect(function(dt)
	local l = ls()
	if not l then return end
	local cash = l:FindFirstChild("Cash")
	local rate = l:FindFirstChild("Per Sec")
	if cash then target = math.max(0, cash.Value - pendingOffline) end
	-- ease toward the real number so gains feel like counting, not popping
	local diff = target - shown
	if math.abs(diff) < 1 then shown = target else shown += diff * math.min(1, dt * 6) end
	cashText.Text = UIKit.money(shown)
	if rate then
		local r = rate.Value
		local away = player:GetAttribute("Away") == true
		local key = r .. "|" .. tostring(away)
		if key ~= lastRate then
			lastRate = key
			if away then
				rateText.Text = "Away: move to earn 100%"
				rateText.TextColor3 = UIKit.ORANGE
			else
				rateText.Text = r > 0 and ("+" .. UIKit.money(r) .. " / sec") or ""
				rateText.TextColor3 = UIKit.MONEY
			end
		end
	end
end)

local function bumpCash(k)
	pillScale.Scale = k or 1.1
	tween(pillScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- a gold "+$X" under the cash
local function popUnderCash(text, color, hold)
	local l = UIKit.outlined(gui, text, 34, color or UIKit.GOLD, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 100), Size = UDim2.new(0, 320, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local sc = Instance.new("UIScale", l)
	sc.Scale = 0.4
	tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(hold or 1.2, function()
		-- fade in place: rising put it over the income line, and a UIStroke
		-- does not fade with TextTransparency (it left a black ghost of the number)
		fadeText(l, 0.4)
		tween(sc, 0.4, { Scale = 0.85 })
		task.delay(0.45, function() l:Destroy() end)
	end)
end

-- ordinary big jumps (not announced by the server) still pop: 4 s of income or more
local lastTarget = 0
local quietUntil = 0
task.spawn(function()
	while true do
		task.wait(0.3)
		local l = ls()
		local r = l and l:FindFirstChild("Per Sec")
		local perSec = r and r.Value or 0
		local jump = target - lastTarget
		if lastTarget > 0 and os.clock() > quietUntil and jump > math.max(50, perSec * 4) then
			popUnderCash("+" .. UIKit.money(jump), UIKit.MONEY, 0.9)
			bumpCash(1.08)
		end
		lastTarget = target
	end
end)

-- ============ COINS INTO THE CASH ============
-- n coins fly from a screen point into the coin icon; each arrival bumps the cash
local function coinStream(fromAbs, n, done)
	local base = fx.AbsolutePosition
	local to = coin.AbsolutePosition + coin.AbsoluteSize / 2 - base
	local from = fromAbs - base
	for k = 1, n do
		task.delay((k - 1) * 0.05, function()
			local c = Instance.new("Frame")
			c.AnchorPoint = Vector2.new(0.5, 0.5)
			c.Size = UDim2.new(0, 22, 0, 22)
			c.BackgroundColor3 = UIKit.GOLD
			c.BorderSizePixel = 0
			c.Position = UDim2.new(0, from.X + math.random(-30, 30), 0, from.Y + math.random(-20, 20))
			c.Parent = fx
			Instance.new("UICorner", c).CornerRadius = UDim.new(1, 0)
			local st = Instance.new("UIStroke", c)
			st.Color = UIKit.INK
			st.Thickness = 2
			local t = 0.45 + math.random() * 0.25
			tween(c, t, { Position = UDim2.new(0, to.X, 0, to.Y), Size = UDim2.new(0, 14, 0, 14) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(t, function()
				c:Destroy()
				bumpCash(1.06)
				if k == n and done then done() end
			end)
		end)
	end
end
_G.SVCoinStream = coinStream   -- DailyClient reuses it

-- ============ CELEBRATIONS ============

-- the HQ level-up banner
-- v5: centred under the money, clear of the rail; the goal card steps aside
-- for its few seconds (Celebrating). Laid out at 440 and scaled down only when
-- the screen is narrower, never below 0.78 (18 px chips stay 14 px on screen).
local BANNER_W = 440
local function hqBanner(e, done)
	UIKit.sfx("levelup")
	player:SetAttribute("Celebrating", true)
	local cx, gap = UIKit.hudGap(480, nil, true)
	local scale = math.clamp(gap / BANNER_W, 0.78, 1)
	local w = scale < 1 and BANNER_W or gap
	local x = cx - fx.AbsolutePosition.X
	local card = UIKit.card(fx, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0, x, 0, -180), Size = UDim2.new(0, w, 0, e.headline and 176 or 136),
	}, { radius = 18, stroke = UIKit.GOLD, strokeWidth = 4 })
	local fit = Instance.new("UIScale")
	fit.Scale = scale
	fit.Parent = card
	local top = UIKit.label(card, ("HQ LEVEL %d"):format(e.level or 2), 18, UIKit.GOLD_DEEP, {
		Position = UDim2.new(0, 0, 0, 10), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center,
	}, UIKit.HEAD)
	local name = UIKit.outlined(card, (e.name or "NEW HQ") .. "!", 38, UIKit.GOLD, {
		Position = UDim2.new(0, 0, 0, 32), Size = UDim2.new(1, 0, 0, 44), TextXAlignment = Enum.TextXAlignment.Center,
	})
	-- v4.3: the ONE new thing this level hands you (Journey.LADDER), then what to do with it
	if e.headline then
		local pill = Instance.new("Frame")
		pill.AnchorPoint = Vector2.new(0.5, 0)
		pill.Position = UDim2.new(0.5, 0, 0, 80)
		pill.Size = UDim2.new(0, 0, 0, 34)
		pill.AutomaticSize = Enum.AutomaticSize.X
		pill.BackgroundColor3 = UIKit.GOLD_LIGHT     -- v5 critique: a black pill read as the navy-pill anti-reference
		pill.Parent = card
		Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)
		local ps = Instance.new("UIStroke", pill)
		ps.Color = UIKit.GOLD
		ps.Thickness = 2
		ps.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		local pp = Instance.new("UIPadding", pill)
		pp.PaddingLeft = UDim.new(0, 16); pp.PaddingRight = UDim.new(0, 16)
		UIKit.label(pill, "NEW: " .. e.headline, 20, UIKit.GOLD_DEEP, { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X }, UIKit.HEAD)
		-- v5: say it once. The "Next:" line repeated the goal card, and the
		-- headline was also one of the chips (GENIUS three times on one card)
	end
	local chips = Instance.new("Frame")
	chips.BackgroundTransparency = 1
	chips.Position = UDim2.new(0, 10, 0, e.headline and 124 or 86)
	chips.Size = UDim2.new(1, -20, 0, 36)
	chips.Parent = card
	local cl = Instance.new("UIListLayout", chips)
	cl.FillDirection = Enum.FillDirection.Horizontal
	cl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	cl.Padding = UDim.new(0, 8)
	local shown = 0
	for _, text in ipairs(e.chips or {}) do
		if e.headline and text == e.headline then continue end
		shown += 1
		local i = shown
		-- the payoff leads: the money chip is the green one
		local money = text:sub(1, 5) == "Money"
		local c = Instance.new("Frame")
		c.BackgroundColor3 = money and UIKit.GREEN_LIGHT or UIKit.SURFACE_2
		c.AutomaticSize = Enum.AutomaticSize.X
		c.Size = UDim2.new(0, 0, 1, 0)
		c.LayoutOrder = i
		c.Parent = chips
		Instance.new("UICorner", c).CornerRadius = UDim.new(1, 0)
		local pad = Instance.new("UIPadding", c)
		pad.PaddingLeft = UDim.new(0, 12); pad.PaddingRight = UDim.new(0, 12)
		-- one style for every chip: caps, the multiplier's x kept lower-case
		UIKit.label(c, (text:upper():gsub("X(%d)", "x%1")), 18, money and UIKit.GREEN_DEEP or UIKit.CARD_TEXT, { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X }, UIKit.HEAD)
		local sc = Instance.new("UIScale", c)
		sc.Scale = 0
		task.delay(0.35 + i * 0.15, function() tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back) end)
	end
	tween(card, 0.45, { Position = UDim2.new(0, x, 0, 100) }, Enum.EasingStyle.Back)
	-- confetti
	local colours = { UIKit.GOLD, UIKit.GREEN, UIKit.BLUE, UIKit.RED, UIKit.ORANGE }
	for k = 1, 40 do
		local p = Instance.new("Frame")
		p.BorderSizePixel = 0
		p.BackgroundColor3 = colours[(k % #colours) + 1]
		p.Size = UDim2.new(0, math.random(8, 14), 0, math.random(12, 18))
		p.Rotation = math.random(0, 360)
		p.Position = UDim2.new(math.random(), 0, 0, -20)
		p.Parent = fx
		local t = 1.3 + math.random() * 0.7
		tween(p, t, { Position = UDim2.new(p.Position.X.Scale + (math.random() - 0.5) * 0.2, 0, 1, 20), Rotation = p.Rotation + math.random(-360, 360) },
			Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(t, function() p:Destroy() end)
	end
	-- 4.4 s to read it (the biggest moment in the game), or tap it away sooner
	local gone = false
	local function leave()
		if gone then return end
		gone = true
		tween(card, 0.35, { Position = UDim2.new(0, x, 0, -180) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.delay(0.4, function()
			card:Destroy()
			player:SetAttribute("Celebrating", nil)
			if done then done() end
		end)
	end
	local tap = Instance.new("TextButton")
	tap.Name = "Dismiss"
	tap.Text = ""
	tap.BackgroundTransparency = 1
	tap.Size = UDim2.new(1, 0, 1, 0)
	tap.ZIndex = 10
	tap.Parent = card
	tap.Activated:Connect(leave)
	task.delay(4.4, leave)
	return card
end

-- the spin-off confirm card: what you keep vs what resets
local spinCard
local function spinAsk(e)
	if spinCard then spinCard:Destroy() end
	local w = math.min(440, fx.AbsoluteSize.X * 0.92)
	local panel, body = UIKit.menu(fx, ("SPIN OFF #%d?"):format(e.number or 1), UIKit.ORANGE, {
		Name = "SpinCard", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, w, 0, 280),
	}, { noClose = true })
	spinCard = panel
	local function col(x, title, lines, color, lead)
		local f = Instance.new("Frame")
		f.BackgroundColor3 = UIKit.SURFACE_2
		f.Position = UDim2.new(x, x > 0 and 6 or 0, 0, 0)
		f.Size = UDim2.new(0.5, -6, 0, 140)
		f.Parent = body
		Instance.new("UICorner", f).CornerRadius = UDim.new(0, 12)
		UIKit.label(f, title, 18, color, { Position = UDim2.new(0, 12, 0, 8), Size = UDim2.new(1, -24, 0, 22) }, UIKit.HEAD)
		-- v5: the reason to press it is the loud line (it was the same body text as "Keep your bag")
		local y = 36
		for i, line in ipairs(lines) do
			local lead = i == 1 and lead
			UIKit.label(f, line, lead and 20 or 16, lead and color or UIKit.INK_SOFT,
				{ Position = UDim2.new(0, 12, 0, y), Size = UDim2.new(1, -24, 0, lead and 28 or 24), TextWrapped = true }, lead and UIKit.HEAD or UIKit.BODY)
			y += lead and 30 or 24
		end
	end
	local function m(v) return (string.format("%.1f", v)):gsub("%.0$", "") end
	col(0, "YOU GET", {
		("x%s money forever"):format(m(e.to or 1.5)),
		(e.keep or 0) > 0 and ("Keep %d rare hire%s"):format(e.keep, e.keep == 1 and "" or "s") or "A fresh garage",
		"Keep your Talent Index",
		"Keep your bag",
	}, UIKit.GREEN_DEEP, true)
	col(0.5, "STARTS OVER", { "Cash", "Buildings", "HQ level" }, UIKit.ORANGE_DEEP)
	local no = UIKit.button(body, "NOT YET", UIKit.MUTED, {
		Name = "NotYet", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(0.5, -6, 0, 50),
	}, { textSize = 20 })
	-- v5 critique: it resets an hour of play, so it is a 1 s HOLD with a fill,
	-- not a tap; and while this card is up the bottom row steps aside (ModalOpen)
	local yes, yesLabel = UIKit.button(body, "HOLD TO SPIN OFF", UIKit.ORANGE, {
		Name = "SpinHold", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.new(0.5, -6, 0, 50),
	}, { textSize = 18, silent = true })
	local fill = Instance.new("Frame")
	fill.Name = "Hold"
	fill.BackgroundColor3 = UIKit.ORANGE_DEEP
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(0, 0, 1, -5)
	fill.ZIndex = yes.ZIndex
	fill.Parent = yes
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, UIKit.RADIUS.md)
	if yesLabel then yesLabel.ZIndex = yes.ZIndex + 1 end
	player:SetAttribute("ModalOpen", true)
	panel.Destroying:Connect(function() player:SetAttribute("ModalOpen", nil) end)
	no.MouseButton1Click:Connect(function()
		remotes:WaitForChild("SpinCancel"):FireServer()
		panel:Destroy(); spinCard = nil
	end)
	local holding
	local function press(input)
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end
	yes.InputBegan:Connect(function(input)
		if not press(input) or holding then return end
		local mine = {}
		holding = mine
		UIKit.sfx("tap")
		local tw = TweenService:Create(fill, TweenInfo.new(1, Enum.EasingStyle.Linear), { Size = UDim2.new(1, 0, 1, -5) })
		tw.Completed:Connect(function(state)
			if holding ~= mine or state ~= Enum.PlaybackState.Completed then return end
			holding = nil
			remotes:WaitForChild("SpinConfirm"):FireServer()
			panel:Destroy(); spinCard = nil
		end)
		tw:Play()
	end)
	yes.InputEnded:Connect(function(input)
		if not press(input) or not holding then return end
		holding = nil                      -- let go early: nothing happens, the fill runs back
		TweenService:Create(fill, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { Size = UDim2.new(0, 0, 1, -5) }):Play()
	end)
	task.delay(30, function() if spinCard == panel then panel:Destroy(); spinCard = nil end end)
end

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }
local function spinCeremony(e)
	UIKit.sfx("rebirth")
	local flash = Instance.new("Frame")
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BorderSizePixel = 0
	flash.Size = UDim2.new(1, 0, 1, 0)
	flash.Parent = fx
	tween(flash, 0.9, { BackgroundTransparency = 1 })
	local title = UIKit.outlined(fx, ("SPIN-OFF %s!"):format(ROMAN[(e.number or 1) + 1] or tostring(e.number)), 56, UIKit.ORANGE, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.36, 0), Size = UDim2.new(1, 0, 0, 64), TextXAlignment = Enum.TextXAlignment.Center,
	})
	local sub = UIKit.outlined(fx, ("Money x%s forever"):format((string.format("%.1f", e.mult or 1)):gsub("%.0$", "")), 30, UIKit.GOLD, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.36, 56), Size = UDim2.new(1, 0, 0, 36), TextXAlignment = Enum.TextXAlignment.Center,
	})
	local sc = Instance.new("UIScale", title)
	sc.Scale = 0.3
	tween(sc, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(3.2, function()
		fadeText(title, 0.5); fadeText(sub, 0.5)
		task.delay(0.6, function() title:Destroy(); sub:Destroy(); flash:Destroy() end)
	end)
end

local celebrate = remotes:WaitForChild("Celebrate", 30)
if celebrate then
	celebrate.OnClientEvent:Connect(function(e)
		if type(e) ~= "table" then return end
		if e.kind == "launch" then
			quietUntil = os.clock() + 2
			UIKit.sfx("coins")
			local vp = fx.AbsoluteSize
			-- the coins fly out of the button you just pressed (they used to burst
			-- out of the top-right corner, over the goal card)
			local slot = gui:FindFirstChild("WriteCode")
			local from = slot and (slot.AbsolutePosition + slot.AbsoluteSize / 2) or (fx.AbsolutePosition + Vector2.new(vp.X / 2, vp.Y - 60))
			coinStream(from, 12)
			popUnderCash("+" .. UIKit.money(e.payday or 0), UIKit.GOLD, 1.4)
			if e.auto then task.delay(0.4, function() popUnderCash("Auto-launched: half pay", UIKit.ORANGE, 1.6) end) end
		elseif e.kind == "hq" then
			-- v4.2: the orbit shot (HomeClient, at 1.4 s) goes first; the banner
			-- waits for it instead of being hidden by it after 1.4 s
			local hqCard
			Notify.show({ lane = "top", priority = 1, key = "hq", delay = 1.6,
				close = function() if hqCard then hqCard:Destroy() end; player:SetAttribute("Celebrating", nil) end,
				open = function(done) hqCard = hqBanner(e, done) end })
		elseif e.kind == "milestone" then
			Notify.show({ lane = "top", priority = 2, key = "milestone",
				open = function(done)
					UIKit.sfx("ding")
					popUnderCash(("%s earned!  +%d%% money"):format(UIKit.money(e.earned or 0), e.bonus or 2), UIKit.GOLD, 2.4)
					task.delay(2.9, done)
				end })
		elseif e.kind == "spinAsk" then
			spinAsk(e)
		elseif e.kind == "spin" then
			spinCeremony(e)
		end
	end)
end

-- ============ WELCOME BACK ============
-- Offline earnings, felt: a card with the amount and a COLLECT button. The
-- server already added the money; the HUD holds it back until you collect, so
-- the number you watch actually goes up with the coins.
task.spawn(function()
	local away = player:GetAttribute("OfflineEarned")
	local t0 = os.clock()
	while not away and os.clock() - t0 < 12 do task.wait(0.25); away = player:GetAttribute("OfflineEarned") end
	if not away or away <= 0 or player:GetAttribute("Returning") ~= true then
		player:SetAttribute("WelcomeDone", true)
		return
	end
	-- v5 critique: a card in the middle of the screen for $43 (1.5 s of income)
	-- is noise. Under a minute of income and under 5% of your cash, it is a line
	-- under the money instead
	local ls = player:WaitForChild("leaderstats", 10)
	local rate = ls and ls:FindFirstChild("Per Sec") and ls["Per Sec"].Value or 0
	local cash = ls and ls:FindFirstChild("Cash") and ls.Cash.Value or 0
	if away < math.max(rate * 60, cash * 0.05) then
		task.wait(1.5)
		popUnderCash("+" .. UIKit.money(away) .. " while you were away", UIKit.MONEY, 2.4)
		player:SetAttribute("WelcomeDone", true)
		return
	end
	pendingOffline = away
	-- v4.2: through the director (centre lane, P2, at a calm moment). The intro
	-- flight is a cutscene and the director waits for it (the old wait watched
	-- an "Intro" gui that v4 never enables). If it cannot show for 45 s (you
	-- got straight into a car), the money is released and the card skipped.
	local closeCard
	Notify.show({ lane = "centre", priority = 2, key = "welcome", calm = true, maxHold = 25, ttl = 45,
		close = function() if closeCard then closeCard() end end,
		fallback = function()
			pendingOffline = 0
			player:SetAttribute("WelcomeDone", true)
		end,
		open = function(finished)
		local w = math.min(380, fx.AbsoluteSize.X * 0.9)
		-- v5: under the income line (at 0.45 on a phone it covered "+$20 / sec")
		local card = UIKit.card(fx, {
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 96), Size = UDim2.new(0, w, 0, 200),
		}, { radius = 18, stroke = UIKit.GREEN, strokeWidth = 4 })
		UIKit.label(card, "WHILE YOU WERE AWAY", 18, UIKit.CARD_MUTED, {
			Position = UDim2.new(0, 0, 0, 14), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center,
		}, UIKit.HEAD)
		UIKit.outlined(card, "+" .. UIKit.money(away), 48, UIKit.MONEY, {
			Position = UDim2.new(0, 0, 0, 40), Size = UDim2.new(1, 0, 0, 56), TextXAlignment = Enum.TextXAlignment.Center,
		})
		-- v4.2 home turf: the apartment that did it gets the credit
		local aptN = player:GetAttribute("OfflineApt") or 0
		local aptName = ({ "STUDIO", "LOFT", "PENTHOUSE" })[aptN]
		UIKit.label(card, aptName and ("Your %s kept things running."):format(aptName) or "Your team kept working.", 16, UIKit.CARD_TEXT, {
			Position = UDim2.new(0, 0, 0, 98), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center,
		}, UIKit.HEAD)
		local btn = UIKit.button(card, "COLLECT", UIKit.GREEN, {
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(0, 200, 0, 52),
		}, { textSize = 24 })
		local sc = Instance.new("UIScale", card)
		sc.Scale = 0.5
		tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		player:SetAttribute("ModalOpen", true)     -- the bottom row steps aside: COLLECT is the one loud thing
		card.Destroying:Connect(function() player:SetAttribute("ModalOpen", nil) end)
		local done = false
		closeCard = function() done = true; card:Destroy() end   -- a cutscene took the screen: shown again after
		local function collect()
			if done then return end
			done = true
			UIKit.sfx("coins")
			local from = btn.AbsolutePosition + btn.AbsoluteSize / 2
			card:Destroy()
			quietUntil = os.clock() + 2
			coinStream(from, 14, function() end)
			task.delay(0.3, function() pendingOffline = 0 end)
			popUnderCash("+" .. UIKit.money(away), UIKit.MONEY, 1.4)
			player:SetAttribute("WelcomeDone", true)
			finished()
		end
		btn.MouseButton1Click:Connect(collect)
		task.delay(20, collect)   -- never hold the money hostage
		end })
end)
