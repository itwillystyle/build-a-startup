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
local function refit()
	local vp = workspace.CurrentCamera.ViewportSize
	fit.Scale = math.min(1, (vp.X - 24) / W, (vp.Y - 24) / H)
end
refit()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)

local sub = UIKit.label(body, "", 17, UIKit.CARD_TEXT, {
	Name = "Sub", Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Center,
}, UIKit.HEAD)

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
	local day = UIKit.label(t, d == 7 and "DAY 7!" or ("DAY " .. d), 15, UIKit.CARD_MUTED, {
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
	ac.MinTextSize = 13
	local tick = UIKit.icon(t, "check", 30, UIKit.GREEN, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 44), Visible = false, ZIndex = 3,
	})
	-- v3.2: from day 2 each day also gives an item; it sits on the tile's corner
	local itemVpf = Instance.new("ViewportFrame")
	itemVpf.Name = "Item"
	itemVpf.AnchorPoint = Vector2.new(1, 0)
	itemVpf.Position = UDim2.new(1, 4, 0, 16)
	itemVpf.Size = UDim2.new(0, 32, 0, 32)
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
		and (player:GetAttribute("Returning") == true or (player:GetAttribute("HQLevel") or 1) >= 2)
end

local claimed = false
local function refresh()
	local ready = player:GetAttribute("DailyReady") == true
	local day = player:GetAttribute("DailyStreak") or 1
	local a = amounts()
	for d, t in ipairs(tiles) do
		local done = ready and d < day or (not ready and d <= day)
		local today = ready and d == day
		t.amt.Text = UIKit.money(a[d] or 0)
		t.tick.Visible = done
		t.coins.Visible = not done
		t.frame.BackgroundColor3 = today and Color3.fromRGB(255, 246, 214) or (done and UIKit.SURFACE_2 or UIKit.CARD)
		t.stroke.Color = today and UIKit.GOLD or UIKit.CARD_LINE
		t.stroke.Thickness = today and 4 or 2
		t.day.TextColor3 = today and UIKit.CARD_TEXT or UIKit.CARD_MUTED
		t.amt.TextColor3 = done and UIKit.CARD_MUTED or UIKit.CARD_TEXT
	end
	if ready then
		sub.Text = day == 1 and "Come back every day. Day 7 pays the most!" or ("Day %d in a row! Miss a day and it starts over."):format(day)
		claimLabel.Text = "CLAIM " .. UIKit.money(a[day] or 0)
		UIKit.setButtonColor(claimBtn, UIKit.GREEN)
	else
		local nextDay = (day % 7) + 1
		sub.Text = ("Come back tomorrow for Day %d: %s"):format(nextDay, UIKit.money(a[nextDay] or 0))
		claimLabel.Text = "CLAIMED!"
		UIKit.setButtonColor(claimBtn, UIKit.MUTED)
	end
	local items = string.split(player:GetAttribute("DailyItems") or "", ",")
	for d, t in ipairs(tiles) do
		local id = items[d]
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

-- today's tile breathes while it waits
task.spawn(function()
	while true do
		task.wait(0.05)
		if gui.Enabled and player:GetAttribute("DailyReady") == true then
			local day = player:GetAttribute("DailyStreak") or 1
			for d, t in ipairs(tiles) do t.scale.Scale = d == day and (1 + 0.05 * math.sin(os.clock() * 5)) or 1 end
		end
	end
end)

local function setOpen(v)
	if v then UIKit.solo(gui) end
	gui.Enabled = v
	if v then
		claimed = false
		panel.Position = UDim2.new(0.5, 0, 0.55, 0)
		TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { Position = UDim2.new(0.5, 0, 0.5, 0) }):Play()
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
if close then close.MouseButton1Click:Connect(function() setOpen(false) end) end
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Q and gui.Enabled then setOpen(false) end
end)

for _, a in ipairs({ "DailyReady", "DailyStreak", "DailyAmounts", "DailyItems", "Shipped", "HQLevel", "Returning" }) do
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
