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
local Moment = require(ReplicatedStorage:WaitForChild("Moment"))
local PopStack = require(ReplicatedStorage:WaitForChild("PopStack"))   -- 23 Oct: the pops over the cash stack (finding 6)
local HudSlots = require(ReplicatedStorage:WaitForChild("HudSlots"))   -- 20 Oct: the bottom centre's numbers, shared with CarClient
local OneVoice = require(ReplicatedStorage:WaitForChild("OneVoice"))   -- 24 Oct: one instruction at a time (rule A)
local remotes = ReplicatedStorage:WaitForChild("SVRemotes")

-- hide the default leaderboard (retry: CoreGui can refuse for the first frames)
-- v9 (12 Oct): and Roblox's tool hotbar. The game has no Tools (Backpack and
-- StarterPack measured empty), but the hotbar still owns the number keys 1-9, and
-- those now open the rail's tiles (UIKit.rail): measured, a 1 sent to Studio was
-- refused as "bound to a CoreGUI core action"
task.spawn(function()
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
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

-- 23 Oct: through the motion layer (UIKit.tween: Reduce Motion, finish-not-freeze); opts.kind = "progress"
-- for a fill that measures time
local function tween(o, t, props, style, dir, opts)
	return UIKit.tween(o, t, props, style, dir, opts)
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
--[[ v7: money moved OUT of top-centre.

Top-centre is the slot a player looks at first, and it was showing a number
that reads $0 to someone who has just joined. Restaurant Tycoon 3 -- the
reference -- puts the quest with a progress bar there and keeps money as a
small counter in a corner. The objective is a layer-2 signal (do I know what
I am doing); money is layer 4 (am I getting somewhere). The bottom layer wins
the better slot.

Bottom-left is the one free corner: the rail owns top-left, Roblox's own
buttons the top strip, WRITE CODE the bottom centre, and the mobile jump
button the bottom right. ]]
pill.AnchorPoint = Vector2.new(0, 1)
pill.Position = UDim2.new(0, 14, 1, -14)
pill.Size = UDim2.new(0, 230, 0, 46)
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
local dollar = UIKit.heading(coin, "$", UIKit.TYPE.headline, UIKit.INK, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center })
dollar.TextStrokeTransparency = 1
-- v3.6 (V8): the rendered gold coin replaces the flat disc and its "$"
if UIKit.ART and UIKit.ART.coin then
	coin.BackgroundTransparency = 1
	cst.Enabled = false
	dollar.Visible = false
	UIKit.art(coin, "coin", 40, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0) })
end
local cashText = UIKit.outlined(pill, "$0", UIKit.TYPE.display, UIKit.MONEY, {
	Name = "Amount", Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2,
})

-- income line (tap the money for the per-building breakdown)
--[[ v8 (11 Oct, UI step 5): the income line sits right above the cash. When v7
	moved the money to the bottom-left corner this line was left anchored by its
	BOTTOM edge at y -2, so it drew wholly above the screen on every device
	(measured: y -75 at 749x381), and its tap target stayed top centre, under the
	quest card. Placed by placeMoney below, with the tap target over both. ]]
local rateText = UIKit.outlined(gui, "", UIKit.TYPE.label, UIKit.MONEY, {
	Name = "Rate", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -62),
	Size = UDim2.new(0, 0, 0, 22), AutomaticSize = Enum.AutomaticSize.X, TextXAlignment = Enum.TextXAlignment.Left,
})
local rateHit = Instance.new("TextButton")
rateHit.Name = "RateHit"
rateHit.BackgroundTransparency = 1
rateHit.Text = ""
rateHit.AnchorPoint = Vector2.new(0, 1)
rateHit.Position = UDim2.new(0, 14, 1, -14)
rateHit.Size = UDim2.new(0, 230, 0, 70)
rateHit:SetAttribute("NoAutoScale", true)    -- sized from the measured cash pill; a shrink made it 136 x 30
rateHit.Parent = gui

local breakdown = UIKit.card(gui, {
	Name = "Breakdown", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -92),
	Size = UDim2.new(0, 240, 0, 40), Visible = false,
}, { radius = UIKit.RADIUS.md })
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
			local l = UIKit.label(breakdown, ("%s   %s%s / sec"):format(name, val < 0 and "-" or "+", UIKit.money(math.abs(val))), UIKit.TYPE.body,
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

--[[ v8 (11 Oct, UI step 5) THE MONEY BLOCK ON A PHONE. Measured in Studio's phone
	simulator (iPhone, 749 x 381): the cash pill (y 263-309) sat on the movement
	thumbstick's resting spot (y 230-304), where a thumb lands to walk, and the
	coffee button's left edge (x 160) was inside the pill (x 14-244). The bottom-left
	corner belongs to the thumbstick on a touch screen. So the money block (income
	line, cash, tap target, breakdown) rises above whatever shares its strip: the
	thumbstick, the item buttons, WRITE CODE on a narrow screen. Measured, not a
	per-device constant, and re-measured every second (items appear as you earn
	them, a phone rotates). ]]
local MONEY_X, MONEY_GAP = 14, 14
local moneyTop = 84        -- px from the bottom to the top of the money block (the income line)
local function placeMoney()
	local pg = player.PlayerGui
	local origin, h = gui.AbsolutePosition, gui.AbsoluteSize.Y
	local right = MONEY_X + math.max(pill.AbsoluteSize.X, 200) + 8
	local lift = MONEY_GAP
	local function clear(o, held)
		if not (o and o:IsA("GuiObject") and (o.Visible or held) and o.AbsoluteSize.X > 2) then return end
		local sg = o:FindFirstAncestorWhichIsA("ScreenGui")
		if sg and not sg.Enabled then return end
		local a = o.AbsolutePosition - origin
		if a.X < right and a.X + o.AbsoluteSize.X > MONEY_X and a.Y > h * 0.5 then
			lift = math.max(lift, h - a.Y + 8)
		end
	end
	local touch = pg:FindFirstChild("TouchGui")
	if touch then clear(touch:FindFirstChild("ThumbstickStart", true)) end
	local items = pg:FindFirstChild("ItemQuick")
	if items then for _, c in ipairs(items:GetDescendants()) do if c:IsA("GuiButton") then clear(c) end end end
	-- 18 Oct (option A): the bottom slot comes and goes as you reach the laptop or the client;
	-- its space stays held (SlotHeld, syncCode) so the money does not jump each time it pops in
	local slot = gui:FindFirstChild("WriteCode")      -- made further down this script
	clear(slot, slot ~= nil and slot:GetAttribute("SlotHeld") == true)
	local ph = pill.AbsoluteSize.Y > 0 and pill.AbsoluteSize.Y or 46
	pill.Position = UDim2.new(0, MONEY_X, 1, -lift)
	rateText.Position = UDim2.new(0, MONEY_X + 4, 1, -lift - ph - 2)
	rateHit.Position = UDim2.new(0, MONEY_X, 1, -lift)
	rateHit.Size = UDim2.new(0, right - 8 - MONEY_X, 0, ph + 26)
	breakdown.Position = UDim2.new(0, MONEY_X, 1, -lift - ph - 32)
	moneyTop = lift + ph + 24
end

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
principle 1). It pulses only when writing code IS the goal.

18 Oct (option A, Luke's pick): out of date above. LAUNCH! is its own button (16 Oct)
and the main button is only on screen when pressing it does something (HOLD TO CODE
at the laptop, GIVE next to your client); no quiet size, no GO TO. See syncCode. ]]
local Sfx = (function()
	local ok, m = pcall(require, game:GetService("ReplicatedStorage"):WaitForChild("Sfx", 5))
	return ok and m or nil
end)()
local keyFlip = false

local codeHold = remotes:WaitForChild("CodeHold", 10)   -- 16 Oct: WRITE CODE is held to code a client's job
local giveApp = remotes:WaitForChild("GiveApp", 10)     -- 17 Oct (pick 2A): GIVE hands the app over
local pickMarket = remotes:WaitForChild("PickMarket", 10)
local productReady = remotes:WaitForChild("ProductReady", 10)
local FULL = UDim2.new(0, HudSlots.CODE.width, 0, HudSlots.CODE.height)   -- 18 Oct (option A): no QUIET size; on screen, it is always the verb
local MINT = UIKit.GREEN_LIGHT
local codeBtn, codeLabel = UIKit.button(gui, "WRITE CODE", UIKit.GREEN, {
	Name = "WriteCode", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -HudSlots.CODE.bottom),
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
local payLabel = UIKit.label(codeBtn, "", UIKit.TYPE.body, UIKit.INK, {
	Name = "Pay", Position = UDim2.new(0, 56, 0, 33), Size = UDim2.new(1, -64, 0, 20), Visible = false,
	TextXAlignment = Enum.TextXAlignment.Center, ZIndex = codeBtn.ZIndex + 1,
}, UIKit.HEAD)
local codeCaption = UIKit.outlined(codeBtn, "NEXT APP", UIKit.TYPE.caption, UIKit.TEXT, {
	Name = "Caption", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -4),
	Size = UDim2.new(1, 40, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = codeBtn.ZIndex + 2,
})
local codeWrap = Instance.new("UIScale")   -- the button's own UIScale is the press squish; pulse the label
codeWrap.Parent = codeLabel
-- the full-pay time left on a waiting LAUNCH: a thin strip draining along the
-- bottom of the face. v5: it used to be a light fill over the WHOLE face, so the
-- loudest button in the game read pale gold for its first minute.
local LAUNCH_SIZE = UDim2.new(0, HudSlots.LAUNCH.width, 0, HudSlots.LAUNCH.height)
local TIME_W = LAUNCH_SIZE.X.Offset - 24
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
local timeText = UIKit.label(timeBadge, "", UIKit.TYPE.label, UIKit.TEXT, {
	Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = codeBtn.ZIndex + 4,
}, UIKit.HEAD)

--[[ 16 Oct (mock 2C, Luke's pick): LAUNCH! is its own gold button beside WRITE
	CODE instead of a relabel of it. WRITE CODE is now HELD to code a client's job,
	so a payday that turned the same button gold would take the coding away. ]]
local launchBtn, launchLabel = UIKit.button(gui, "LAUNCH!", UIKit.GOLD, {
	Name = "Launch", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -96),
	Size = LAUNCH_SIZE, Visible = false, ClipsDescendants = false,
}, { textSize = UIKit.TYPE.title, silent = true })
launchLabel.Position = UDim2.new(0, 0, 0, 2)
launchLabel.Size = UDim2.new(1, 0, 0, 30)
local launchWrap = Instance.new("UIScale")
launchWrap.Parent = launchLabel
payLabel.Parent = launchBtn
payLabel.Position = UDim2.new(0, 8, 0, 31)
payLabel.Size = UDim2.new(1, -16, 0, 20)
timeBar.Parent = launchBtn
timeBadge.Parent = launchBtn

--[[ 24 Oct (one instruction, rule A; ui/animation-review/judge/ONE-INSTRUCTION-OPTIONS.md): while
	the button you can press or the job in your hands speaks, LAUNCH! waits as this small chip in
	its slot, "APP READY" and its time ("II" while the server has the clock paused). Paper, not
	gold: it is a status, not a second ask. A tap still launches (44 px tall), and so do L / Y. ]]
local launchChip, chipLabel = UIKit.button(gui, "APP READY", UIKit.PAPER, {
	Name = "LaunchChip", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -HudSlots.CODE.bottom),
	Size = UDim2.new(0, 196, 0, 44), Visible = false,   -- "APP READY  II 0:42" at 16 px fits 184 px of label
}, { textSize = UIKit.TYPE.body, dark = true, silent = true, stroke = UIKit.GOLD_DEEP })

local launchState     -- { payday, autoAt } while an app waits to launch
--[[ 24 Oct: seconds to the half-pay auto-launch, and whether the clock is paused. The server's
	LaunchAutoAt (running) / LaunchLeft (paused, LaunchClock) win; the payload's autoAt is the
	fallback for the moment before they arrive. nil: no auto-launch (before your first launch). ]]
local function launchLeft()
	local held = tonumber(player:GetAttribute("LaunchLeft"))
	if held then return math.max(0, held), true end
	local at = tonumber(player:GetAttribute("LaunchAutoAt")) or (launchState and launchState.autoAt)
	if at then return math.max(0, at - workspace:GetServerTimeNow()), false end
	return nil, false
end
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
--[[ 18 Oct (option A, Luke's pick; board silicon-startup/ui/2026-10-18-button-vs-instruction):
	the button only names what pressing it does right now. At the laptop with a job waiting it
	is HOLD TO CODE (CODING n% while it fills); next to the client you carry for it is a gold
	GIVE. Anywhere else it is not on screen: GO TO LAPTOP and GO TO CLIENT were directions
	dressed as buttons (playtest 22-54-32, 0:12 and 4:04), and the way is the goal card, the
	marker and the ground line's job. It pops in quietly so the thumb notices it. ]]
local shownVerb   -- "code" | "give" | nil (hidden): the verb on screen at the last sync
local launchMode  -- 24 Oct: "button" | "chip" | nil, how a waiting app showed at the last sync
local function goalShown()   -- the goal card has words to show (the server's "wait" sends "")
	local t = player:GetAttribute("ObjectiveText")
	return type(t) == "string" and t ~= ""
end
local launchY     -- LAUNCH's slot offset last set (so a 4 Hz sync does not restart its slide)
local function syncCode()
	local inCar = seated()
	-- in a car the speedometer owns the bottom centre: a waiting LAUNCH sits above it
	-- v5: it also steps aside while the company-name box is up (it pulsed behind
	-- the box, two loud things at once, and its caption ran under the box's edge)
	local free = player:GetAttribute("BuildModeOpen") ~= true and player:GetAttribute("NamingOpen") ~= true and not menuOpen()
	local carrying = player:GetAttribute("CarryingApp") == true
	-- 24 Oct: the same rule the server pauses LAUNCH!'s clock by (OneVoice)
	local verb = OneVoice.verbOf({ carrying = carrying, canGive = player:GetAttribute("CanGive") == true,
		jobWaiting = player:GetAttribute("JobWaiting") == true, atLaptop = player:GetAttribute("AtLaptop") == true })
	local give = verb == "give"
	codeBtn.Visible = free and not inCar and verb ~= nil
	codeBtn:SetAttribute("SlotHeld", free and not inCar)   -- placeMoney keeps the slot's space
	--[[ 24 Oct (one instruction, rule A): one voice. The button you can press, else the job in your
		hands, else LAUNCH!, else the goal. The pick goes out as the client-local attribute OneVoice:
		GuideClient folds the goal card to its icon, PromptClient hides prompts, CoachClient waits. ]]
	local pick = OneVoice.pick({
		verb = codeBtn.Visible and verb or nil, carrying = carrying,
		midJob = player:GetAttribute("MidJob") == true, recruit = player:GetAttribute("Carrying") ~= nil,
		launch = launchState ~= nil, goal = goalShown(),
		tip = player:GetAttribute("CoachShowing") == true,   -- 24 Oct (F-6): a coach tip folds the goal
		phone = player:GetAttribute("PhoneBannerShowing") == true,   -- 24 Oct: so does a phone banner
	})
	if player:GetAttribute("OneVoice") ~= pick.voice then player:SetAttribute("OneVoice", pick.voice) end
	local wasMode = launchMode
	launchMode = free and pick.launch or nil
	launchBtn.Visible = launchMode == "button"
	launchChip.Visible = launchMode == "chip"
	-- a calm pop when LAUNCH! folds to the chip or opens back out (its first arrival has its own ding)
	if launchMode and wasMode and launchMode ~= wasMode then UIKit.popIn(launchMode == "chip" and launchChip or launchBtn, 0.85) end
	-- 17 Oct: above WRITE CODE (beside it, the CAR button covered it: Luke's recording 3:46)
	-- 18 Oct (option A): with the button hidden, LAUNCH sits in the bottom slot itself; it
	-- slides up when HOLD TO CODE or GIVE pops in under it
	-- 20 Oct (live run 5:56, 7:18): -126 left 24 px of it under the two-row speed panel; HudSlots
	-- holds both, and hudslots.spec lays them out against each other
	local y = -HudSlots.launchBottom(inCar, codeBtn.Visible)
	if y ~= launchY then
		launchY = y
		local at = UDim2.new(0.5, 0, 1, y)
		if launchBtn.Visible then tween(launchBtn, 0.2, { Position = at }) else UIKit.set(launchBtn, { Position = at }) end
		-- 24 Oct: the chip lives in LAUNCH!'s slot
		if launchChip.Visible then tween(launchChip, 0.2, { Position = at }) else UIKit.set(launchChip, { Position = at }) end
	end
	local prog = tonumber(player:GetAttribute("CodeProgress")) or 0
	-- 16 Oct, mock 2C: the button says what holding it does right now
	-- 17 Oct (pick 2A): next to them, a gold GIVE
	codeLabel.TextSize = UIKit.TYPE.title
	codeLabel.Text = give and "GIVE" or (prog > 0 and prog < 1) and ("CODING " .. math.floor(prog * 100) .. "%") or "HOLD TO CODE"
	UIKit.setButtonColor(codeBtn, give and UIKit.GOLD or UIKit.GREEN)
	local art = not give
	slotArt.Visible = art
	-- 18 Oct (playtest 22-54-32): the label kept the icon's 56 px inset with the icon hidden,
	-- so GIVE sat right of centre; no icon, the full width
	codeLabel.Position = art and UDim2.new(0, 56, 0, 0) or UDim2.new(0, 8, 0, 0)
	codeLabel.Size = art and UDim2.new(1, -64, 1, -5) or UDim2.new(1, -16, 1, -5)
	-- 18 Oct (option A): a short, calm pop (no overshoot) when it appears or its verb changes
	local now = codeBtn.Visible and verb or nil
	if now and now ~= shownVerb then UIKit.popIn(codeBtn, 0.85) end
	shownVerb = now
end
syncCode()
player:GetAttributeChangedSignal("Shipped"):Connect(syncCode)
player:GetAttributeChangedSignal("BuildModeOpen"):Connect(syncCode)
player:GetAttributeChangedSignal("NamingOpen"):Connect(syncCode)
for _, a in ipairs({ "CarryingApp", "CanGive", "JobWaiting", "AtLaptop" }) do player:GetAttributeChangedSignal(a):Connect(syncCode) end
-- 24 Oct (one voice): a started job, a recruit in your arms and the goal's words change the pick too
for _, a in ipairs({ "MidJob", "Carrying", "ObjectiveText", "CoachShowing", "PhoneBannerShowing" }) do player:GetAttributeChangedSignal(a):Connect(syncCode) end
UIKit.onMenuChange(function() syncCode() end)   -- menus are other scripts' guis: one shared watch
-- v4.2: in a car the speedometer owns the bottom centre (it sat on top of WRITE CODE)
local function watchSeat(char)
	local hum = char:WaitForChild("Humanoid", 10)
	if hum then hum:GetPropertyChangedSignal("SeatPart"):Connect(syncCode) end
	syncCode()
end
if player.Character then task.spawn(watchSeat, player.Character) end
player.CharacterAdded:Connect(watchSeat)

-- 16 Oct, mock 2C: the button IS the coding bar (CodeProgress, from ClientsServer)
charge.BackgroundColor3 = UIKit.GREEN_DEEP
local chargeTween
local CODE_TICK = 0.25 -- ClientsServer publishes CodeProgress every 0.25 s
local function setCoding()
	local p = math.clamp(tonumber(player:GetAttribute("CodeProgress")) or 0, 0, 1)
	if chargeTween then chargeTween:Cancel() end
	-- 23 Oct (animation review): the fill used Quint Out over 0.2 s, so it surged and stopped four
	-- times a second. Constant motion is linear, one update long, so it flows at one steady speed.
	if p < charge.Size.X.Scale then
		charge.Size = UDim2.new(p, 0, 1, -5) -- a reset (the app is finished) snaps; it never drains backwards
	else
		-- 23 Oct (FINAL.md W6, measured: the fill stalled to 0.010/s when an update came late): run a
		-- quarter past the update so a late one never stops the bar; the last step is quicker so the
		-- bar is SEEN full before the reset snaps it
		local span = p >= 1 and CODE_TICK * 0.6 or CODE_TICK * 1.25
		chargeTween = tween(charge, span, { Size = UDim2.new(p, 0, 1, -5) }, Enum.EasingStyle.Linear, nil, { kind = "progress" })
	end
	syncCode()
end
setCoding()
player:GetAttributeChangedSignal("CodeProgress"):Connect(setCoding)
-- the product bar is said once, and only when it is nearly ready (it is taught when it fills)
local function setCharge(p)
	p = math.clamp(tonumber(p) or 0, 0, 1)
	codeCaption.Visible = launchState == nil and p >= 0.75
	codeCaption.Text = ("NEXT APP  " .. math.floor(p * 100) .. "%")
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
	timeBar.Visible = o ~= nil and launchLeft() ~= nil
	timeBadge.Visible = timeBar.Visible
	payLabel.Text = payText()
	payLabel.Visible = o ~= nil
	if o and not was then
		UIKit.sfx("ding", 0.9)
		local sc = launchBtn:FindFirstChildOfClass("UIScale")
		if sc then sc.Scale = 1.15; tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Quint) end
	end
	setCharge(player:GetAttribute("ProductProgress"))
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

launchBtn.MouseButton1Click:Connect(doLaunch)
launchChip.MouseButton1Click:Connect(doLaunch)   -- 24 Oct: folded, it is still one tap away

--[[ 16 Oct, the client loop: WRITE CODE is HELD. Press (mouse or finger) = start
	coding the job at the door, let go = pause; the server counts the time
	(ClientsServer) and the fill shows it. A thumb that slides off lets go. ]]
local holdingCode = false
local function setHold(on)
	if holdingCode == on then return end
	holdingCode = on
	if codeHold then codeHold:FireServer(on) end
end
local function pressInput(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end
codeBtn.InputBegan:Connect(function(input)
	if not pressInput(input) then return end
	-- next to your client the same button is GIVE: one press, not a hold
	if player:GetAttribute("CanGive") == true and giveApp then giveApp:FireServer() return end
	setHold(true)
end)
codeBtn.InputEnded:Connect(function(input) if pressInput(input) then setHold(false) end end)
codeBtn.MouseLeave:Connect(function() setHold(false) end)
-- 17 Oct review: a button that hides mid-hold (a menu, the car, build mode) never sees
-- InputEnded, and the server kept coding with the thumb up
codeBtn:GetPropertyChangedSignal("Visible"):Connect(function() if not codeBtn.Visible then setHold(false) end end)
--[[ The verb the player presses most in the whole game made no sound at all.
	Two alternating key samples at a jittered pitch while the code is going in,
	so holding reads as typing rather than as one sample retriggering.
	18 Oct (playtest 22-54-32, 4:07, Luke: the keyboard "just goes blank sometimes"): it only
	played for a HUD-button hold, so holding E at the laptop prompt was silent. Now it types
	while the server's CodeProgress is going up, whatever is holding: the server publishes it
	every 0.25 s, so a rise in the last 0.45 s counts as coding. ]]
local lastCode, codeRoseAt = 0, -math.huge
player:GetAttributeChangedSignal("CodeProgress"):Connect(function()
	local p = tonumber(player:GetAttribute("CodeProgress")) or 0
	if p > lastCode then codeRoseAt = os.clock() end
	lastCode = p
end)
task.spawn(function()
	while true do
		task.wait(0.17)
		if Sfx and os.clock() - codeRoseAt < 0.45 then
			local head = player.Character and player.Character:FindFirstChild("Head")
			if head then
				keyFlip = not keyFlip
				Sfx.play(head, keyFlip and "keyboard" or "keyTap", {
					volume = 0.35, pitch = 0.92 + math.random() * 0.22, life = 2, max = 24,
				})
			end
		end
	end
end)

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
	-- 23 Oct: Reduce Motion (read every frame, it can change mid-session): the pulses hold still
	local still = UIKit.reducedMotion()
	if launchState then
		codeWrap.Scale = 1
		launchWrap.Scale = still and 1 or (1 + 0.07 * (0.5 + 0.5 * math.sin(t * 5.5)))
		local left, paused = launchLeft()
		if left then
			timeBar.Size = UDim2.new(0, math.floor(TIME_W * math.clamp(left / 60, 0, 1)), 0, 6)
			timeBar.BackgroundColor3 = left <= 15 and UIKit.ORANGE_DEEP or UIKit.GOLD_DEEP
			timeText.Text = math.ceil(left) .. "s"
			timeBadge.BackgroundColor3 = left <= 15 and UIKit.ORANGE_DEEP or UIKit.INK
		end
		-- 24 Oct: the chip says the same time; "II" while the server holds the clock (mid-job)
		local chip = left and ((paused and "II " or "") .. ("%d:%02d"):format(math.floor(math.ceil(left) / 60), math.ceil(left) % 60)) or ""
		chipLabel.Text = chip ~= "" and ("APP READY  " .. chip) or "APP READY"
	else
		launchWrap.Scale = 1
		-- a coach tip on screen has the stage: the pulse waits
		local coach = player.PlayerGui:FindFirstChild("Coach")
		local tip = coach and coach:FindFirstChild("CoachCard")
		codeWrap.Scale = (not still and pulsing and not (tip and tip.Visible) and player:GetAttribute("Celebrating") ~= true) and (1 + 0.06 * (0.5 + 0.5 * math.sin(t * 5))) or 1
	end
end)

-- ============ TICK ============

local shown = 0
local target = 0
local pendingOffline = 0      -- welcome-back money held back until COLLECT
local held = 0                -- money in flight (coinStream): the counter takes it coin by coin
local lastRate = ""

local function ls() return player:FindFirstChild("leaderstats") end

RunService.RenderStepped:Connect(function(dt)
	local l = ls()
	if not l then return end
	local cash = l:FindFirstChild("Cash")
	local rate = l:FindFirstChild("Per Sec")
	if cash then target = math.max(0, cash.Value - pendingOffline - held) end
	-- ease toward the real number so gains feel like counting, not popping
	local diff = target - shown
	-- coins in flight: never count DOWN to take them back (the server's payday can land
	-- a frame before the event that starts the coins; the counter just waits for them)
	if diff < 0 and held > 0 then diff = 0 end
	if math.abs(diff) < 1 then shown = target else shown += diff * math.min(1, dt * 6) end
	cashText.Text = UIKit.money(shown)
	if rate then
		local r = rate.Value
		local away = player:GetAttribute("Away") == true
		--[[ v5.0 MOMENTUM shares the income line rather than taking a new corner
			of the screen. It only appears when you have some, so a player who
			never leaves the garage sees exactly the HUD they saw before, and
			it reads as a DISCOUNT rather than a number -- "22% off" is a thing
			you can act on, "7 momentum" is a thing you have to be taught. ]]
		local mom = player:GetAttribute("Momentum") or 0
		local key = r .. "|" .. tostring(away) .. "|" .. tostring(mom)
		if key ~= lastRate then
			lastRate = key
			if away then
				rateText.Text = "Away: move to earn 100%"
				rateText.TextColor3 = UIKit.ORANGE
			elseif mom > 0 then
				local off = math.floor(math.min(mom, 12) * 3 + 0.5)
				rateText.Text = ("+%s / sec   ·   NEXT BUILD %d%% OFF"):format(UIKit.money(r), off)
				rateText.TextColor3 = UIKit.GOLD or UIKit.MONEY
			else
				rateText.Text = r > 0 and ("+" .. UIKit.money(r) .. " / sec") or ""
				rateText.TextColor3 = UIKit.MONEY
			end
		end
	end
end)

local function bumpCash(k)
	pillScale.Scale = k or 1.1
	tween(pillScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Quint)
end

-- a gold "+$X" under the cash
-- v8 (11 Oct, step 5): right above the money block. It still popped at the top
-- centre, where the cash was before v7 moved it to the bottom-left corner, so a
-- payday landed on the quest card or the level-up banner (found at phone size).
--[[ 23 Oct (the animation audit, finding 6; mockup ui/animation-review/mp4/4-money-pop.mp4, panel B):
	each pop grew from 40% size over 0.35 s at the SAME spot, so on an auto-launch "+$X" and, 0.4 s
	later, "Auto-launched: half pay" landed on each other. Now a pop fades in from 92% (T.fast), the
	newest takes the bottom line and pushes older ones up one line (Quint Out, T.ui), at most two
	lines (PopStack, tested), and each leaves with a fade in place (T.ui). ]]
local POP_LINE = 44   -- px between stacked pops: TYPE.display (36) + 8
local pops = PopStack.new(2)
local popLabels = {}
local popSerial = 0
local function popY(line) return UDim2.new(0, MONEY_X, 1, -(moneyTop + 4) - line * POP_LINE) end
local function placePops()
	for id, l in pairs(popLabels) do
		local line = PopStack.line(pops, id)
		-- ease OUT, not in-out: measured 23 Oct, an in-out push barely moves in its first ~50 ms, so the
		-- old pop still sat on the line while the new one faded in over it (16 double-exposed frames).
		-- Making room is a response: it must start moving at once
		if line and l.Parent then tween(l, UIKit.T.ui, { Position = popY(line) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out) end
	end
end
local function dropPop(id, t)
	local l = popLabels[id]
	local line = PopStack.line(pops, id) or 0
	popLabels[id] = nil
	PopStack.remove(pops, id)
	if l and l.Parent then
		-- a UIStroke does not fade with TextTransparency (fadeText fades both). The judge's review: it
		-- faded where it stood while a neighbour slid onto its line (two texts in one spot for ~0.2 s),
		-- so a leaving pop rises one line as it fades (Reduce Motion drops the rise: an exit fades in place)
		fadeText(l, t, { Position = popY(line + 1) })
		task.delay(t + 0.05, function() l:Destroy() end)
	end
end
local function popUnderCash(text, color, hold)
	popSerial += 1
	local id = popSerial
	local l = UIKit.outlined(gui, text, UIKit.TYPE.display, color or UIKit.GOLD, {
		AnchorPoint = Vector2.new(0, 1), Position = popY(0), Size = UDim2.new(0, 320, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	popLabels[id] = l
	for _, old in ipairs(PopStack.push(pops, id)) do dropPop(old, UIKit.T.fast) end
	placePops()
	local sc = Instance.new("UIScale", l)
	sc.Scale = 0.92
	l.TextTransparency = 1
	local st = l:FindFirstChildOfClass("UIStroke")
	if st then st.Transparency = 1 end
	tween(sc, UIKit.T.fast, { Scale = 1 })
	tween(l, UIKit.T.fast, { TextTransparency = 0 })
	if st then tween(st, UIKit.T.fast, { Transparency = 0 }) end
	task.delay(hold or 1.2, function()
		if popLabels[id] then
			dropPop(id, UIKit.T.ui)
			placePops()
		end
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
--[[ v9 (12 Oct) THE CASH MOMENT, after My Restaurant!'s dish collect (his recording,
	12 Oct: about 8 bills burst off the table and fly into the counter, 280 -> 296, a
	cha-ching; "maybe a little too fast": the whole flight was about 0.25 s).
	Ours, about 1.1 s for 12 coins:
	  BURST  the game's rendered coins pop out of where you earned it (Quint out, 0.24 s)
	  HOLD   a beat, staggered, so they leave one after another
	  FLY    each one accelerates into the money counter (Quad in, 0.42 s)
	  LAND   the counter jumps, a tick that rises in pitch coin by coin, and the
	         amount moves into the number with that coin (`held`), so it COUNTS UP
	         as they arrive instead of jumping before they get there
	  CHING  the last coin: a bright high ping and the coin sound, a bigger bump
	The ping and the coins are the game's licensed sounds (no unverified uploads).
	22 Oct (ShipMoment, the first-ship celebration): opts.prepaid = the amount was already
	held back (SVCashHold) when the moment began, so the counter never ran ahead of the
	coins; opts.onCoin(k, n) runs as each coin lands, so a number by the coins can count
	in step with the cash. ]]
-- the stream's beats (ShipMoment.COIN mirrors them); the Reduce Motion path keeps the same length
local STREAM_BURST, STREAM_HOLD, STREAM_STAGGER = 0.24, 0.08, 0.045
local STREAM_FLY_MIN, STREAM_FLY_SPREAD = 0.42, 0.08
local STREAM_FLY = STREAM_FLY_MIN + STREAM_FLY_SPREAD / 2   -- the average flight
local function coinStream(fromAbs, n, done, amount, opts)
	n = math.max(1, n or 12)
	amount = tonumber(amount) or 0
	opts = opts or {}
	-- 23 Oct: Reduce Motion: no coins fly; money held back for them is released at once, the
	-- counter bumps once and the ching still plays (feedback, not movement). Review of the layer:
	-- every coin is still REPORTED (the first-ship count is driven by onCoin calls; one call left it
	-- at 1/12 of the pay) and `done` keeps the stream's normal length (deferring it faded the
	-- first-ship number the frame it appeared). Quiet, so the big-jump pop does not add a second
	-- "+$X" for money that landed in one go. Measured by DoctorProbes.motion.
	if UIKit.reducedMotion() then
		if opts.prepaid then held = math.max(0, held - amount) end
		quietUntil = math.max(quietUntil, os.clock() + 1)
		bumpCash(1.06)
		UIKit.sfx("ding", 1.65, 0.5)
		if opts.onCoin then
			for k = 1, n do task.spawn(opts.onCoin, k, n) end
		end
		if done then task.delay(STREAM_BURST + STREAM_HOLD + (n - 1) * STREAM_STAGGER + STREAM_FLY, done) end
		return
	end
	if not opts.prepaid then held += amount end
	local per, given = amount / n, 0
	-- 22 Oct: coins land in LANDING order, not launch order (each flight is 0.42-0.50 s), so the
	-- last coin to arrive gives the remainder, rings the ching and calls done (ShipMoment.lander)
	local landed = 0
	local base = fx.AbsolutePosition
	local to = coin.AbsolutePosition + coin.AbsoluteSize / 2 - base
	local from = fromAbs - base
	for k = 1, n do
		local c = UIKit.art(fx, "coin", 30, { AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 30,
			Position = UDim2.new(0, from.X, 0, from.Y), Size = UDim2.new(0, 16, 0, 16), Rotation = math.random(-40, 40) })
		local ang = math.random() * math.pi * 2
		local r = 46 + math.random() * 50
		local out = UDim2.new(0, from.X + math.cos(ang) * r, 0, from.Y + math.sin(ang) * r * 0.7 - 28)
		tween(c, STREAM_BURST, { Position = out, Size = UDim2.new(0, 34, 0, 34) })
		local leave = STREAM_BURST + STREAM_HOLD + (k - 1) * STREAM_STAGGER
		task.delay(leave, function()
			if not c.Parent then return end
			local t = STREAM_FLY_MIN + math.random() * STREAM_FLY_SPREAD
			tween(c, t, { Position = UDim2.new(0, to.X, 0, to.Y), Size = UDim2.new(0, 22, 0, 22), Rotation = 0 },
				Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(t, function()
				c:Destroy()
				landed += 1
				local last = landed == n
				local give = last and (amount - given) or per
				given += give
				held = math.max(0, held - give)
				bumpCash(last and 1.14 or 1.06)
				UIKit.sfx("tap", 1 + 0.6 * (landed / n), 0.28)
				if opts.onCoin then task.spawn(opts.onCoin, landed, n) end
				if last then
					UIKit.sfx("ding", 1.65, 0.5)
					UIKit.sfx("coins", 1.05, 0.5)
					if done then done() end
				end
			end)
		end)
	end
end
_G.SVCoinStream = coinStream   -- DailyClient reuses it
-- hold money back from the counter until its coins fly (ClientFxClient's first ship: the server
-- pays before the moment's coins leave); quiet, so the big-jump pop does not say it twice
_G.SVCashHold = function(amount)
	held += math.max(0, tonumber(amount) or 0)
	quietUntil = os.clock() + 3
end
-- 23 Oct: quiet the big-jump pop without holding money back (a coder's delivery: it is not your
-- moment and it has no coins, FINAL.md W2)
_G.SVCashQuiet = function(seconds)
	quietUntil = math.max(quietUntil, os.clock() + (tonumber(seconds) or 1))
end

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
	--[[ v8 ONE NUMBER. The banner said "HQ LEVEL 5" over "LEVEL 18!": the HQ
		stage and the building level, two counters on one card, and only the
		second is the one the world shows ("BUILD LEVEL 18" on the pad, the
		founder boards). A building level is the headline alone; what the new
		stage hands you is the NEW pill. A named HQ (the other paths) keeps its
		stage number over the name, since there the name has no number. ]]
	local isLevel = type(e.name) == "string" and e.name:match("^LEVEL %d+$") ~= nil
	local lift = isLevel and 24 or 0          -- no caption line: everything moves up
	local card = UIKit.card(fx, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0, x, 0, -180), Size = UDim2.new(0, w, 0, (e.headline and 176 or 136) - lift),
	}, { radius = UIKit.RADIUS.lg, stroke = UIKit.GOLD, strokeWidth = 4 })
	local fit = Instance.new("UIScale")
	fit.Scale = scale
	fit.Parent = card
	if not isLevel then
		UIKit.label(card, ("HQ LEVEL %d"):format(e.level or 2), UIKit.TYPE.label, UIKit.GOLD_DEEP, {
			Position = UDim2.new(0, 0, 0, 10), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center,
		}, UIKit.HEAD)
	end
	local name = UIKit.outlined(card, (e.name or "NEW HQ") .. "!", UIKit.TYPE.display, UIKit.GOLD, {
		Position = UDim2.new(0, 0, 0, 32 - lift + (isLevel and 4 or 0)), Size = UDim2.new(1, 0, 0, 44), TextXAlignment = Enum.TextXAlignment.Center,
	})
	-- the number punches in as the card lands (Moment: hit, enter, payoff)
	local punch = Instance.new("UIScale", name)
	punch.Scale = 0
	task.delay(0.3, function() Moment.enter(punch, 1.5, 0.35) end)
	-- v4.3: the ONE new thing this level hands you (Journey.LADDER), then what to do with it
	if e.headline then
		local pill = Instance.new("Frame")
		pill.AnchorPoint = Vector2.new(0.5, 0)
		pill.Position = UDim2.new(0.5, 0, 0, 80 - lift)
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
		UIKit.label(pill, "NEW: " .. e.headline, UIKit.TYPE.label, UIKit.GOLD_DEEP, { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X }, UIKit.HEAD)
		-- v5: say it once. The "Next:" line repeated the goal card, and the
		-- headline was also one of the chips (GENIUS three times on one card)
	end
	local chips = Instance.new("Frame")
	chips.BackgroundTransparency = 1
	chips.Position = UDim2.new(0, 10, 0, (e.headline and 124 or 86) - lift)
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
		task.delay(0.55 + i * 0.15, function() tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back) end)   -- reward
	end
	tween(card, 0.45, { Position = UDim2.new(0, x, 0, Notify.topY(100)) }, Enum.EasingStyle.Back)   -- reward
	Notify.followTop(card, 100)
	-- v8: a ring opens behind it as it lands; confetti bursts from the card, and
	-- only when the HQ itself changed (e.big). It used to rain 40 pieces over the
	-- whole screen for every level.
	task.delay(0.42, function()          -- as the card's drop (0.45 s) lands
		if not card.Parent then return end
		local at = Moment.centreOf(card)
		Moment.ring(fx, at, UIKit.GOLD, w * scale * 1.1)
		if e.big ~= false then Moment.burst(fx, at, 36, w * scale * 0.7) end
	end)
	-- 4.4 s to read it (the biggest moment in the game), or tap it away sooner
	local gone = false
	local function leave()
		if gone then return end
		gone = true
		-- 23 Oct (finding 7): it left with ease-IN over 0.35 s, so a tap to dismiss started slow; out, 0.2 s
		tween(card, UIKit.T.ui, { Position = UDim2.new(0, x, 0, -180) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
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
local function spinAsk(e, done)
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
		Instance.new("UICorner", f).CornerRadius = UDim.new(0, UIKit.RADIUS.md)
		UIKit.label(f, title, UIKit.TYPE.label, color, { Position = UDim2.new(0, 12, 0, 8), Size = UDim2.new(1, -24, 0, 22) }, UIKit.HEAD)
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
	--[[ The home bought the slots; this is where you spend them. Shown only
		when there are more eligible people than seats -- with nothing to
		decide, a chooser is just a step between you and the button. The ids are
		the server's opaque ones (bound to the person, not their list position);
		the server re-checks every one at confirm, so this only expresses intent. ]]
	local picked = {}
	local eligible = e.eligible or {}
	local slots = e.slots or 0
	if #eligible > slots and slots > 0 then
		panel.Size = UDim2.new(0, w, 0, 280 + 96)
		for i = 1, slots do picked[eligible[i].id] = true end   -- default = the best, same as the server's fallback
		local strip = Instance.new("ScrollingFrame")
		strip.Name = "Keepers"
		strip.BackgroundTransparency = 1
		strip.BorderSizePixel = 0
		strip.Position = UDim2.new(0, 0, 0, 148)
		strip.Size = UDim2.new(1, 0, 0, 86)
		strip.ScrollBarThickness = 4
		strip.AutomaticCanvasSize = Enum.AutomaticSize.Y
		strip.CanvasSize = UDim2.new(0, 0, 0, 0)
		strip.Parent = body
		local layout = Instance.new("UIGridLayout")
		layout.CellSize = UDim2.new(0, 128, 0, 38)
		layout.CellPadding = UDim2.new(0, 6, 0, 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = strip
		local count = UIKit.label(body, "", UIKit.TYPE.caption, UIKit.INK_SOFT,
			{ Position = UDim2.new(0, 0, 0, 236), Size = UDim2.new(1, 0, 0, 18) }, UIKit.BODY)
		local chips = {}
		local function redraw()
			local n = 0
			for _ in pairs(picked) do n += 1 end
			count.Text = n == 0 and ("Nobody picked: your best %d come along"):format(slots)
				or ("%d of %d seats filled"):format(n, slots)
			for id, b in pairs(chips) do
				UIKit.setButtonColor(b, picked[id] and UIKit.GREEN or UIKit.MUTED)
			end
		end
		for i, who in ipairs(eligible) do
			-- LayoutOrder = the server's best-first rank (a grid sorts by Name on ties, and
			-- "Keep_10" < "Keep_2"), so the green pre-selected chips are the best, in order
			local chip = UIKit.button(strip, ("%s - %s"):format(who.name, who.talentName or "Star"), UIKit.MUTED,
				{ Name = "Keep_" .. who.id, LayoutOrder = i }, { textSize = 14 })
			chips[who.id] = chip
			chip.MouseButton1Click:Connect(function()
				if picked[who.id] then
					picked[who.id] = nil
				else
					local n = 0
					for _ in pairs(picked) do n += 1 end
					if n >= slots then return end          -- the home bought this many, no more
					picked[who.id] = true
				end
				redraw()
			end)
		end
		redraw()
	end
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
	panel.Destroying:Connect(function()
		player:SetAttribute("ModalOpen", nil)
		if done then done() end           -- every way out (NOT YET, the hold, the 30 s timeout) frees the lane
	end)
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
		local tw = TweenService:Create(fill, TweenInfo.new(1, Enum.EasingStyle.Linear), { Size = UDim2.new(1, 0, 1, -5) })   -- motion: progress
		tw.Completed:Connect(function(state)
			if holding ~= mine or state ~= Enum.PlaybackState.Completed then return end
			holding = nil
			local pick = {}
			for id in pairs(picked) do table.insert(pick, id) end
			table.sort(pick)
			remotes:WaitForChild("SpinConfirm"):FireServer({ pick = pick })
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
local function spinCeremony(e, done)
	UIKit.sfx("rebirth")
	local flash = Instance.new("Frame")
	flash.BackgroundColor3 = UIKit.PAPER
	flash.BorderSizePixel = 0
	flash.Size = UDim2.new(1, 0, 1, 0)
	flash.Parent = fx
	tween(flash, 0.9, { BackgroundTransparency = 1 })
	local title = UIKit.outlined(fx, ("SPIN-OFF %s!"):format(ROMAN[(e.number or 1) + 1] or tostring(e.number)), UIKit.TYPE.money, UIKit.ORANGE, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.36, 0), Size = UDim2.new(1, 0, 0, 64), TextXAlignment = Enum.TextXAlignment.Center,
	})
	local sub = UIKit.outlined(fx, "", UIKit.TYPE.headline, UIKit.GOLD, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.36, 56), Size = UDim2.new(1, 0, 0, 36), TextXAlignment = Enum.TextXAlignment.Center,
	})
	local sc = Instance.new("UIScale", title)
	Moment.enter(sc, 0.3, 0.5)
	-- the payoff counts: the multiplier climbs from where you were to where you are
	local function m(v) return (string.format("%.1f", v)):gsub("%.0$", "") end
	task.delay(0.35, function()
		local at = Moment.centreOf(title)
		Moment.ring(fx, at, UIKit.ORANGE, 420)
		Moment.burst(fx, at, 40, 300)
		Moment.countUp(sub, 1, e.mult or 1, function(v) return ("Money x%s forever"):format(m(v)) end, 1.1)
	end)
	task.delay(3.2, function()
		fadeText(title, 0.5); fadeText(sub, 0.5)
		task.delay(0.6, function()
			title:Destroy(); sub:Destroy(); flash:Destroy()
			if done then done() end
		end)
	end)
end

local celebrate = remotes:WaitForChild("Celebrate", 30)
if celebrate then
	celebrate.OnClientEvent:Connect(function(e)
		if type(e) ~= "table" then return end
		if e.kind == "launch" then
			quietUntil = os.clock() + 2
			local vp = fx.AbsoluteSize
			-- the coins fly out of the button you just pressed (they used to burst
			-- out of the top-right corner, over the goal card)
			-- 18 Oct (option A): from LAUNCH! itself (its own button since 16 Oct; WRITE CODE is often hidden now)
			local slot = gui:FindFirstChild("Launch")
			local from = slot and (slot.AbsolutePosition + slot.AbsoluteSize / 2) or (fx.AbsolutePosition + Vector2.new(vp.X / 2, vp.Y - 60))
			coinStream(from, 12, nil, e.payday)     -- the payday counts in as the coins land
			popUnderCash("+" .. UIKit.money(e.payday or 0), UIKit.GOLD, 1.4)
			if e.auto then task.delay(0.4, function() popUnderCash("Auto-launched: half pay", UIKit.ORANGE, 1.6) end) end
		elseif e.kind == "hq" and e.lobby then
			-- 1c: the garage-to-lobby moment replaces the banner; its toast carries the staff line
			player:SetAttribute("Celebrating", nil)
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
		--[[ v8: the spin-off card and the ceremony go through the director like
			every other card (they drew straight onto the screen, over whatever
			was there): centre lane, earned (P1), so they still come first ]]
		elseif e.kind == "spinAsk" then
			Notify.show({ lane = "centre", priority = 1, key = "spinAsk", maxHold = 32,
				close = function() if spinCard then spinCard:Destroy(); spinCard = nil end end,
				open = function(done) spinAsk(e, done) end })
		elseif e.kind == "spin" then
			Notify.show({ lane = "centre", priority = 1, key = "spin", maxHold = 6,
				open = function(done) spinCeremony(e, done) end })
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
		}, { radius = UIKit.RADIUS.lg, stroke = UIKit.GREEN, strokeWidth = 4 })
		UIKit.label(card, "WHILE YOU WERE AWAY", UIKit.TYPE.label, UIKit.CARD_MUTED, {
			Position = UDim2.new(0, 0, 0, 14), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center,
		}, UIKit.HEAD)
		UIKit.outlined(card, "+" .. UIKit.money(away), UIKit.TYPE.money, UIKit.MONEY, {
			Position = UDim2.new(0, 0, 0, 40), Size = UDim2.new(1, 0, 0, 56), TextXAlignment = Enum.TextXAlignment.Center,
		})
		-- v4.2 home turf: the apartment that did it gets the credit
		local aptN = player:GetAttribute("OfflineApt") or 0
		local aptName = ({ "STUDIO", "LOFT", "PENTHOUSE" })[aptN]
		UIKit.label(card, aptName and ("Your %s kept things running."):format(aptName) or "Your team kept working.", UIKit.TYPE.body, UIKit.CARD_TEXT, {
			Position = UDim2.new(0, 0, 0, 98), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center,
		}, UIKit.HEAD)
		local btn = UIKit.button(card, "COLLECT", UIKit.GREEN, {
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(0, 200, 0, 52),
		}, { textSize = 24 })
		local sc = Instance.new("UIScale", card)
		sc.Scale = 0.5
		tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Quint)
		player:SetAttribute("ModalOpen", true)     -- the bottom row steps aside: COLLECT is the one loud thing
		card.Destroying:Connect(function() player:SetAttribute("ModalOpen", nil) end)
		local done = false
		closeCard = function() done = true; card:Destroy() end   -- a cutscene took the screen: shown again after
		local function collect()
			if done then return end
			done = true
			local from = btn.AbsolutePosition + btn.AbsoluteSize / 2
			card:Destroy()
			quietUntil = os.clock() + 2
			-- the held money rides the coins in (it used to be released 0.3 s in, all at once)
			pendingOffline = 0
			coinStream(from, 14, nil, away)
			popUnderCash("+" .. UIKit.money(away), UIKit.MONEY, 1.4)
			player:SetAttribute("WelcomeDone", true)
			finished()
		end
		btn.MouseButton1Click:Connect(collect)
		task.delay(20, collect)   -- never hold the money hostage
		end })
end)

-- the money block keeps clear of the thumbstick and the bottom row (placeMoney)
task.spawn(function()
	while true do
		pcall(placeMoney)
		task.wait(1)
	end
end)
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function() task.defer(placeMoney) end)
