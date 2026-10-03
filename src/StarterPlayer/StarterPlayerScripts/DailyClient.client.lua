--[[
	DailyClient -- LocalScript in StarterPlayer -> StarterPlayerScripts.

	v3.1 THE DAILY REWARD, the client half of DailyReward (server).

	The 25 Sep retention review found nothing that brings a player back the
	next day, and Roblox's discovery scores exactly that. Every reference game
	has a streak ladder; this is the plain version:

	  - a DAILY button on the left rail, with a red "!" when a reward waits
	  - a card with the seven days: past days ticked, today lit, the future
	    visible (you can see what day 7 pays, which is the point)
	  - CLAIM -> coins fly into your money (the HUD's coin stream)
	  - it opens by itself ONCE per session when a reward is waiting: for a
	    returning player after the WHILE YOU WERE AWAY card, for a new
	    player at HQ 2 (never during the first four minutes of teaching;
	    the first live test opened it on top of "Hire your first intern")

	Amounts are the server's (attribute DailyAmounts), in seconds of your own
	income with a floor, so day 7 is worth wanting at every stage.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local Notify = require(ReplicatedStorage:WaitForChild("Notify"))
local claimRemote = ReplicatedStorage:WaitForChild("SVRemotes"):WaitForChild("ClaimDaily", 60)
if not claimRemote then return end

-- v3.2: no rail button of its own. The PHONE's Daily app opens this card
-- (a BindableEvent in PlayerGui), and the phone's badge carries the "!".
local Items = require(ReplicatedStorage:WaitForChild("Items"))
local openEvent = player:WaitForChild("PlayerGui"):FindFirstChild("SVOpenDaily") or Instance.new("BindableEvent")
openEvent.Name = "SVOpenDaily"
openEvent.Parent = player.PlayerGui

-- ============ THE CARD ============

local gui = Instance.new("ScreenGui")
gui.Name = "Daily"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 14
gui.Enabled = false
UIKit.safe(gui)
gui.Parent = player:WaitForChild("PlayerGui")

local TILE_W, TILE_H, GAP = 76, 96, 6
local W = 7 * TILE_W + 6 * GAP + 28
local H = 48 + 12 + 30 + TILE_H + 14 + 56 + 14

local panel, body, close = UIKit.menu(gui, "DAILY REWARD", UIKit.GREEN, {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, W, 0, H),
})
local fit = Instance.new("UIScale", panel)
local place = UIKit.fitMenu(panel, W, H, fit)   -- v5: the shared rule (clears the rail, scales to fit)

local sub = UIKit.label(body, "", 16, UIKit.CARD_TEXT, {
	Name = "Sub", Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Center,
}, UIKit.BODY)

local tiles = {}
for d = 1, 7 do
	local t = Instance.new("Frame")
	t.Name = "Day" .. d
	t.Position = UDim2.new(0, (d - 1) * (TILE_W + GAP), 0, 30)
	t.Size = UDim2.new(0, TILE_W, 0, TILE_H)
	t.BackgroundColor3 = UIKit.CARD
	t.BorderSizePixel = 0
	t.Parent = body
	Instance.new("UICorner", t).CornerRadius = UDim.new(0, 12)
	local st = Instance.new("UIStroke", t)
	st.Thickness = 2
	st.Color = UIKit.CARD_LINE
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local day = UIKit.label(t, d == 7 and "DAY 7!" or ("DAY " .. d), 14, UIKit.CARD_MUTED, {
		Position = UDim2.new(0, 0, 0, 6), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center,
	}, UIKit.HEAD)
	-- a pile that grows with the day: one coin on day 1, a stack by day 7
	local coins = Instance.new("Frame")
	coins.Name = "Coins"
	coins.BackgroundTransparency = 1
	coins.Position = UDim2.new(0.5, 0, 0, 28)
	coins.Size = UDim2.new(0, 0, 0, 32)
	coins.Parent = t
	local n = math.min(4, 1 + math.floor((d - 1) / 2))
	for k = 1, n do
		local c = Instance.new("Frame")
		c.AnchorPoint = Vector2.new(0.5, 0.5)
		c.Size = UDim2.new(0, 22, 0, 22)
		c.Position = UDim2.new(0, (k - (n + 1) / 2) * 12, 0, 16 - (k % 2) * 4)
		c.BackgroundColor3 = UIKit.GOLD
		c.BorderSizePixel = 0
		c.Parent = coins
		Instance.new("UICorner", c).CornerRadius = UDim.new(1, 0)
		local cs = Instance.new("UIStroke", c)
		cs.Color = UIKit.darker(UIKit.GOLD, 0.55)
		cs.Thickness = 2
	end
	local amt = UIKit.label(t, "", 16, UIKit.CARD_TEXT, {
		Position = UDim2.new(0, 2, 1, -28), Size = UDim2.new(1, -4, 0, 20), TextXAlignment = Enum.TextXAlignment.Center,
		TextScaled = true,
	}, UIKit.HEAD)
	local ac = Instance.new("UITextSizeConstraint", amt)
	ac.MaxTextSize = 16
	ac.MinTextSize = 14
	local tick = UIKit.icon(t, "check", 30, UIKit.GREEN, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 44), Visible = false, ZIndex = 3,
	})
	-- v3.2: from day 2 each day also gives an item. v5: it sits beside the coins
	-- (on the corner it covered the DAY label)
	local itemVpf = Instance.new("ViewportFrame")
	itemVpf.Name = "Item"
	itemVpf.AnchorPoint = Vector2.new(0.5, 0.5)
	itemVpf.Position = UDim2.new(0.78, 0, 0, 44)
	itemVpf.Size = UDim2.new(0, 30, 0, 30)
	itemVpf.BackgroundColor3 = UIKit.SURFACE
	itemVpf.BackgroundTransparency = 0
	itemVpf.ZIndex = 4
	itemVpf.Visible = false
	itemVpf.Parent = t
	Instance.new("UICorner", itemVpf).CornerRadius = UDim.new(1, 0)
	tiles[d] = { frame = t, stroke = st, day = day, amt = amt, tick = tick, coins = coins, scale = Instance.new("UIScale", t), item = itemVpf }
end

local claimBtn, claimLabel = UIKit.button(body, "CLAIM", UIKit.GREEN, {
	Name = "Claim", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(0, 280, 0, 56),
}, { textSize = 24, silent = true })
-- v5 critique: once claimed, the countdown is a flat chip; a lipped button that
-- does nothing reads as broken (the old quest card's "GO >" problem)
local nextChip = UIKit.label(body, "", 18, UIKit.INK_SOFT, {
	Name = "NextGift", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.new(0, 280, 0, 44),
	TextXAlignment = Enum.TextXAlignment.Center, BackgroundColor3 = UIKit.SURFACE_2, BackgroundTransparency = 0, Visible = false,
}, UIKit.HEAD)
Instance.new("UICorner", nextChip).CornerRadius = UDim.new(1, 0)

-- ============ STATE ============

local function amounts()
	local out = {}
	for v in string.gmatch(player:GetAttribute("DailyAmounts") or "", "[^,]+") do table.insert(out, tonumber(v) or 0) end
	return out
end

-- a new player meets the daily ladder after the teaching is over (HQ 2, about
-- minute 4); a returning player meets it straight away
local function unlocked()
	return player:GetAttribute("Shipped") == true and player:GetAttribute("DailyAmounts") ~= nil
		and (player:GetAttribute("Returning") == true
			-- v4.3: a new player meets it after the first drive downtown (Journey), not over the car reveal
			or ((player:GetAttribute("HQLevel") or 1) >= 2 and player:GetAttribute("JrRes") == true))
end

local claimed = false
-- the daily day turns over at 00:00 UTC (the server stores the UTC day)
local function nextGiftText()
	local left = 86400 - (math.floor(workspace:GetServerTimeNow()) % 86400)
	local h, m = left // 3600, (left % 3600) // 60
	return h > 0 and ("NEXT GIFT IN %dH %02dM"):format(h, m) or ("NEXT GIFT IN %dM"):format(math.max(1, m))
end
local function refresh()
	local ready = player:GetAttribute("DailyReady") == true
	local day = player:GetAttribute("DailyStreak") or 1
	local a = amounts()
	-- v5: once today is claimed, tomorrow's tile is the one that is lit (gold
	-- edge, TOMORROW): the reason to come back, where the eye already is
	local nextDay = (day % 7) + 1
	for d, t in ipairs(tiles) do
		local today = ready and d == day
		local tomorrow = not ready and d == nextDay
		local done = not tomorrow and (ready and d < day or (not ready and d <= day))
		t.amt.Text = UIKit.money(a[d] or 0)
		t.tick.Visible = done
		t.coins.Visible = not done
		t.frame.BackgroundColor3 = today and UIKit.GOLD_LIGHT or (done and UIKit.SURFACE_2 or UIKit.CARD)
		t.stroke.Color = (today or tomorrow) and UIKit.GOLD or UIKit.CARD_LINE
		t.stroke.Thickness = today and 4 or (tomorrow and 3 or 2)
		t.day.Text = tomorrow and "TOMORROW" or (d == 7 and "DAY 7!" or ("DAY " .. d))
		t.day.TextColor3 = today and UIKit.CARD_TEXT or (tomorrow and UIKit.GOLD_DEEP or UIKit.CARD_MUTED)
		t.amt.TextColor3 = done and UIKit.CARD_MUTED or UIKit.CARD_TEXT
	end
	if ready then
		sub.Text = day == 1 and "Come back every day. Day 7 pays the most!" or ("Day %d in a row! Miss a day and it starts over."):format(day)
		claimLabel.Text = "CLAIM " .. UIKit.money(a[day] or 0)
		claimLabel.TextSize = 24
		claimBtn.Visible, nextChip.Visible = true, false
		UIKit.setButtonColor(claimBtn, UIKit.GREEN)
	else
		-- v5: say "tomorrow" once (the lit TOMORROW tile). The sub is the streak, and
		-- the dead CLAIMED! button counts down to the next gift instead
		sub.Text = day <= 1 and "Your streak starts today." or ("%d days in a row!"):format(day)
		nextChip.Text = nextGiftText()
		claimBtn.Visible, nextChip.Visible = false, true
	end
	local items = string.split(player:GetAttribute("DailyItems") or "", ",")
	for d, t in ipairs(tiles) do
		local id = items[d]
		local withItem = id and id ~= "" and Items.BY_ID[id] and true or false
		t.coins.Position = UDim2.new(withItem and 0.34 or 0.5, 0, 0, 28)
		local cs = t.coins:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", t.coins)
		cs.Scale = withItem and 0.82 or 1
		if id and id ~= "" and Items.BY_ID[id] then
			if t.itemId ~= id then
				t.item:ClearAllChildren()
				Instance.new("UICorner", t.item).CornerRadius = UDim.new(1, 0)
				t.item.CurrentCamera = nil
				Items.icon(id, t.item)
				t.itemId = id
			end
			t.item.Visible = true
		else
			t.item.Visible = false
		end
	end
end

-- ============ THE RAIL TILE (v5) ============
--[[ The daily gift is the day-2 return hook, and it lived three taps deep in
the phone (PHONE > Daily > SEE THE WEEK), sharing the phone's badge with
investor texts. Now it has the first rail slot: a red "!" and a wiggle when a
gift is waiting, quiet when today's is claimed. ]]
local railBtn = UIKit.railButton("gift", "DAILY", UIKit.GOLD, {
	Name = "DailyButton", LayoutOrder = 5, Size = UDim2.new(0, UIKit.RAIL, 0, UIKit.RAIL), Visible = false,
}, { iconSize = 28 })
local railBadge, railBadgeText = UIKit.badge(railBtn)
railBadgeText.Text = "!"
local railIcon = railBtn:FindFirstChild("Icon")

-- today's tile breathes while it waits, and the rail icon wiggles
task.spawn(function()
	while true do
		task.wait(0.05)
		local ready = player:GetAttribute("DailyReady") == true
		if gui.Enabled and ready then
			local day = player:GetAttribute("DailyStreak") or 1
			for d, t in ipairs(tiles) do t.scale.Scale = d == day and (1 + 0.05 * math.sin(os.clock() * 5)) or 1 end
		elseif gui.Enabled then
			local txt = nextGiftText()          -- the countdown ticks while the card is open
			if nextChip.Text ~= txt then nextChip.Text = txt end
		end
		if railIcon then
			-- a short wiggle every 2.5 s (a constant shake would be noise)
			local phase = os.clock() % 2.5
			railIcon.Rotation = (ready and railBtn.Visible and not gui.Enabled and phase < 0.5) and (12 * math.sin(phase * 25)) or 0
		end
	end
end)

local function setOpen(v)
	if v then UIKit.solo(gui) end
	gui.Enabled = v
	if v then
		claimed = false
		panel.Position = place(0.55, 0)     -- the slide-in keeps the fitted x (clear of the rail)
		TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { Position = place(0.5, 0) }):Play()
	end
	refresh()
end

claimBtn.MouseButton1Click:Connect(function()
	if claimed or player:GetAttribute("DailyReady") ~= true then
		UIKit.sfx("thunk", 0.8)
		return
	end
	claimed = true
	UIKit.sfx("coins")
	local from = claimBtn.AbsolutePosition + claimBtn.AbsoluteSize / 2
	if _G.SVCoinStream then pcall(_G.SVCoinStream, from, 14) end
	claimRemote:FireServer()
	claimLabel.Text = "CLAIMED!"
	UIKit.setButtonColor(claimBtn, UIKit.MUTED)
	task.delay(1.6, function() if gui.Enabled then setOpen(false) end end)
end)

openEvent.Event:Connect(function() setOpen(true) end)
railBtn.MouseButton1Click:Connect(function() setOpen(not gui.Enabled) end)
UIKit.bindRail(railBtn, gui)
local function syncRail()
	railBtn.Visible = unlocked()
	railBadge.Visible = railBtn.Visible and player:GetAttribute("DailyReady") == true and not gui.Enabled
end
for _, a in ipairs({ "DailyReady", "DailyAmounts", "Shipped", "HQLevel", "Returning", "JrRes" }) do
	player:GetAttributeChangedSignal(a):Connect(syncRail)
end
gui:GetPropertyChangedSignal("Enabled"):Connect(syncRail)
syncRail()
if close then close.MouseButton1Click:Connect(function() setOpen(false) end) end
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Q and gui.Enabled then setOpen(false) end
end)

for _, a in ipairs({ "DailyReady", "DailyStreak", "DailyAmounts", "DailyItems", "Shipped", "HQLevel", "Returning", "JrRes" }) do
	player:GetAttributeChangedSignal(a):Connect(refresh)
end
refresh()

-- ============ OPEN BY ITSELF, ONCE ============
-- v4.2: at a calm moment only. The director waits for 5 quiet seconds and never
-- opens it while you drive, carry a recruit, watch a cutscene or have another
-- menu open (it used to open over a rare-hire card or an HQ level-up).
task.spawn(function()
	local t0 = os.clock()
	while os.clock() - t0 < 3600 do
		task.wait(1)
		local returning = player:GetAttribute("Returning") == true
		local settled = not returning or player:GetAttribute("WelcomeDone") == true
		if player:GetAttribute("DailyReady") == true and unlocked() and settled then
			-- once open it is an ordinary menu (the director's "menu" state holds
			-- progress items until it closes); holding the lane as well kept an
			-- earned rare-hire card waiting behind a menu nobody closed (live test)
			Notify.show({ lane = "centre", priority = 2, key = "daily", calm = true,
				valid = function() return player:GetAttribute("DailyReady") == true and not gui.Enabled end,
				open = function(done)
					setOpen(true)
					task.delay(0.5, done)
				end })
			return
		end
	end
end)
