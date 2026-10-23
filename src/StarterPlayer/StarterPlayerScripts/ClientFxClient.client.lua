--[[ ClientFxClient (16 Oct 2026): the payout when you hand an app to a client.

	Mocks Luke picked (ui/2026-10-16-client-loop/mockups.html):
	  3A, every client: "+$X" pops over the client, "+$Y TIP" under it a beat later,
	     coins fly into the cash counter (Moment.landMoney).
	  3B, the first client only (16 Oct): gold rays and a tilted "SHIPPED!". REPLACED 22 Oct
	     by ShipMoment (mock A, the client's moment): see wow() below.
	  2A (17 Oct), every hand-over you GIVE: the app flies from you to the client, they
	     open it (a card over their head), stars pop (3 fast, 2 ok, 1 slow), then the cash.
	     About a second, so it stays quick on the fiftieth client.
	     23 Oct (animation review, picked mock 1-payout panel B): it had grown to about 2.4 s
	     with six Back pops; it is now about 1.4 s with no bounce, and the cash counter counts
	     up with the coins. The beats live in PayoutBeats (tested), not here.
	The server sends ClientPaid { pay, tip, wow, at, who, stars, from, tier } (ClientsServer). ]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local Moment = require(ReplicatedStorage:WaitForChild("Moment"))
local ShipMoment = require(ReplicatedStorage:WaitForChild("ShipMoment"))
local PayoutBeats = require(ReplicatedStorage:WaitForChild("PayoutBeats"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("SVRemotes")
local clientPaid = remotes:WaitForChild("ClientPaid", 30)
if not clientPaid then return end

local gui = Instance.new("ScreenGui")
gui.Name = "ClientFx"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 40
gui.Parent = player:WaitForChild("PlayerGui")

local function screenAt(world)
	local cam = workspace.CurrentCamera
	local v, onScreen = cam:WorldToViewportPoint(world)
	if not onScreen then
		local vp = cam.ViewportSize
		return Vector2.new(vp.X * 0.62, vp.Y * 0.45)
	end
	return Vector2.new(v.X, v.Y)
end

local function ease(obj, seconds, goal)
	local tw = TweenService:Create(obj, TweenInfo.new(seconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

-- a word that fades in at a screen point, holds, then rises a little and fades out
-- 23 Oct (animation review): it used to enter with a Back overshoot from nothing, hold 0.7 s and
-- drift 40 px over 0.6 s (1.4 s a client, all game). Now: fade in from 0.94 scale, hold, lift 8 px.
local function pop(text, at, size, colour, delay, hold)
	local M = PayoutBeats.MONEY
	hold = hold or M.hold
	task.delay(delay or 0, function()
		local l = UIKit.outlined(gui, text, size, colour, {
			AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 260, 0, size + 10),
			Position = UDim2.new(0, at.X, 0, at.Y), TextXAlignment = Enum.TextXAlignment.Center,
		})
		local st = l:FindFirstChildOfClass("UIStroke")
		local sc = Instance.new("UIScale")
		sc.Scale = M.from
		sc.Parent = l
		-- outlined text: the UIStroke has its own Transparency and must fade too
		l.TextTransparency = 1
		if st then st.Transparency = 1 end
		ease(sc, M.enter, { Scale = 1 })
		ease(l, M.enter, { TextTransparency = 0 })
		if st then ease(st, M.enter, { Transparency = 0 }) end
		task.delay(M.enter + hold, function()
			if not l.Parent then return end
			ease(l, M.leave, { Position = l.Position - UDim2.new(0, 0, 0, M.rise), TextTransparency = 1 })
			if st then ease(st, M.leave, { Transparency = 1 }) end
		end)
		task.delay(M.enter + hold + M.leave + 0.02, function() l:Destroy() end)
	end)
end

-- 2A, step 1: the app tile, from you to them along a little arc
local function appTile(parent, size)
	local tile = Instance.new("Frame")
	tile.AnchorPoint = Vector2.new(0.5, 0.5)
	tile.Size = UDim2.new(0, size, 0, size)
	tile.BackgroundColor3 = UIKit.BLUE
	tile.ZIndex = 6
	tile.Parent = parent
	Instance.new("UICorner", tile).CornerRadius = UDim.new(0, UIKit.RADIUS.md)
	local st = Instance.new("UIStroke")
	st.Thickness, st.Color = 2, UIKit.INK
	st.Parent = tile
	for i = 0, 2 do
		local line = Instance.new("Frame")
		line.BorderSizePixel = 0
		line.BackgroundColor3 = UIKit.PAPER
		line.Position = UDim2.new(0.22, 0, 0.22 + i * 0.2, 0)
		line.Size = UDim2.new(i == 2 and 0.36 or 0.56, 0, 0.1, 0)
		line.ZIndex = 7
		line.Parent = tile
	end
	return tile
end

-- 23 Oct (animation review): takes WORLD points and re-projects them every frame, so a moving
-- camera (or a car) no longer leaves the tile behind; 0.28 s, Quint Out, a 50 px arc.
local function fly(fromWorld, toWorld, done)
	-- 18 Oct (playtest 22-54-32, 3:49, Luke: "add a sound effect when we give the app"): a soft
	-- low click as it leaves your hands (no toss sound exists; "tap" pitched down is the closest)
	UIKit.sfx("tap", 0.75, 0.5)
	local F = PayoutBeats.FLY
	local tile = appTile(gui, 34)
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local a = math.min(1, (os.clock() - t0) / F.seconds)
		local e = 1 - (1 - a) ^ 5
		local p = screenAt(fromWorld):Lerp(screenAt(toWorld), e) - Vector2.new(0, math.sin(a * math.pi) * F.arc)
		tile.Position = UDim2.new(0, p.X, 0, p.Y)
		tile.Rotation = (1 - e) * F.tilt
		if a >= 1 then
			conn:Disconnect()
			tile:Destroy()
			done()
		end
	end)
end

--[[ THE FIRST SHIP (22 Oct, ShipMoment; Luke's pick, mock A "the client's moment").
	It replaced 3B (gold rays turning in the middle of the screen, a tilted "SHIPPED!", a
	count-up on its own clock): "really ugly". Now everything happens AT the client:
	the box lifts out of your hands and glows, flies to them, freezes for 80 ms on the
	handoff (the box shakes, the screen does not), they cheer (the server's StaffRig.cheer)
	under a "!", and their coins fly one by one into your cash while the "+$X" beside them
	counts in step. Banned (the references' slop list): rays, text that repeats what you
	just watched, a full-screen flash, a screen shake, anything pinned to the middle of the
	screen. No skip (22 Oct, Luke): it is 2.3 s, and on a phone the first touch of any
	camera drag would have skipped it. ]]
local function sparks(at, n)
	for i = 1, n do
		local s = Instance.new("Frame")
		s.BorderSizePixel = 0
		s.BackgroundColor3 = (i % 2 == 0) and UIKit.GOLD or UIKit.BLUE
		s.AnchorPoint = Vector2.new(0.5, 0.5)
		s.Size = UDim2.new(0, 7, 0, 7)
		s.Position = UDim2.new(0, at.X, 0, at.Y)
		s.ZIndex = 8
		s.Parent = gui
		Instance.new("UICorner", s).CornerRadius = UDim.new(1, 0)
		local a = math.random() * math.pi * 2
		local r = 22 + math.random() * 20
		ease(s, 0.38, { Position = UDim2.new(0, at.X + math.cos(a) * r, 0, at.Y + math.sin(a) * r), BackgroundTransparency = 1 })
		task.delay(0.4, function() s:Destroy() end)
	end
end

-- a BillboardGui held to a point in the world, so the "!" and the number stay on the client
local function anchorAt(world)
	local p = Instance.new("Part")
	p.Name = "ShipMomentAnchor"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Position = world
	p.Parent = workspace
	return p
end
local function board(anchor, size, offset)
	local b = Instance.new("BillboardGui")
	b.Adornee = anchor
	b.AlwaysOnTop = true
	b.Size = size
	b.StudsOffset = offset
	b.LightInfluence = 0
	b.Name = "ShipMoment"
	-- in the world, under its anchor, like DropOffClient's sign: a BillboardGui inside a
	-- ScreenGui is never drawn (found live, 22 Oct)
	b.Parent = anchor
	return b
end

local function wow(d)
	local B = ShipMoment.BEATS
	local where = typeof(d.at) == "Vector3" and d.at or Vector3.zero
	local total = ShipMoment.total(d)
	-- the server has already paid: hold it back so the counter takes it with the coins
	local hold = rawget(_G, "SVCashHold")
	local stream = rawget(_G, "SVCoinStream")
	local held = type(hold) == "function" and type(stream) == "function"
	if held then hold(total) end

	local anchor = anchorAt(where)
	local alive = {}   -- cleared when the moment ends (the billboards go with the anchor)
	local function gone(o) if o and o.Parent then o:Destroy() end end
	local function finish()
		for _, o in ipairs(alive) do gone(o) end
		task.delay(0.5, function() gone(anchor) end)
	end

	-- 0.0 s: the box lifts out of your hands and glows; a rising tone
	local hands = typeof(d.from) == "Vector3" and d.from + Vector3.new(0, 1.5, 0) or where + Vector3.new(0, 3, 0)
	local tile = appTile(gui, 34)
	table.insert(alive, tile)
	local glow = tile:FindFirstChildOfClass("UIStroke")
	if glow then glow.Color, glow.Thickness = UIKit.GOLD, 3 end
	local tileScale = Instance.new("UIScale")
	tileScale.Parent = tile
	UIKit.sfx("ding", 0.75, 0.3)
	task.delay(0.12, function() UIKit.sfx("ding", 0.95, 0.3) end)
	local t0 = os.clock()
	local liftAt = B.handoff * 0.3
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if not tile.Parent or t >= B.handoff + B.hitstop then
			conn:Disconnect()
			return
		end
		local start = screenAt(hands)
		local goal = screenAt(where + Vector3.new(0, 3, 0))
		local p
		if t < liftAt then
			local k = t / liftAt
			p = start - Vector2.new(0, 16 * k)
			tileScale.Scale = 1 + 0.12 * k
		elseif t < B.handoff then
			local k = (t - liftAt) / (B.handoff - liftAt)
			local e = 1 - (1 - k) ^ 3
			p = (start - Vector2.new(0, 16)):Lerp(goal, e) - Vector2.new(0, math.sin(k * math.pi) * 50)
		else
			-- 0.4 s: the hit-stop, 80 ms: the box shakes in place
			p = goal + Vector2.new((math.floor(t * 120) % 2 == 0) and 2 or -2, 0)
		end
		tile.Position = UDim2.new(0, p.X, 0, p.Y)
	end)
	task.delay(B.handoff, function()
		UIKit.sfx("thunk", 0.8, 0.45)
		sparks(screenAt(where + Vector3.new(0, 3, 0)), 10)
	end)
	task.delay(B.handoff + B.hitstop, function()
		if not tile.Parent then return end
		ease(tileScale, 0.1, { Scale = 0 })
		task.delay(0.1, function() gone(tile) end)
	end)

	-- 0.5 s: the client cheers (the server); a "!" pops over them
	task.delay(B.react, function()
		local bang = board(anchor, UDim2.new(0, 44, 0, 44), Vector3.new(0, 4.2, 0))
		table.insert(alive, bang)
		local dot = Instance.new("Frame")
		dot.Size = UDim2.fromScale(1, 1)
		dot.BackgroundColor3 = UIKit.GOLD
		dot.Parent = bang
		Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
		local st = Instance.new("UIStroke")
		st.Thickness, st.Color = 2, UIKit.INK
		st.Parent = dot
		UIKit.label(dot, "!", UIKit.TYPE.title, UIKit.INK, {
			Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
		}, UIKit.HEAD)
		local sc = Instance.new("UIScale")
		sc.Parent = dot
		Moment.enter(sc, 0.2, 0.22)
	end)

	-- 0.6 s: their coins fly to your cash; the number beside them counts in step
	task.delay(B.coins, function()
		local num = board(anchor, UDim2.new(0, 220, 0, 50), Vector3.new(3.4, 2.4, 0))
		table.insert(alive, num)
		local label = UIKit.outlined(num, "+" .. UIKit.money(held and 0 or total), UIKit.TYPE.headline, UIKit.MONEY, {
			Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Left,
		})
		local sc = Instance.new("UIScale")
		sc.Parent = label
		Moment.enter(sc, 0.4, 0.26)
		local function leave()
			if label.Parent then
				ease(label, ShipMoment.FADE, { TextTransparency = 1, Position = UDim2.new(0, 0, 0, -14) })
				local ls = label:FindFirstChildOfClass("UIStroke")
				if ls then ease(ls, ShipMoment.FADE, { Transparency = 1 }) end
			end
			task.delay(ShipMoment.FADE, finish)
		end
		local hands2 = screenAt(where + Vector3.new(0, 2.5, 0))
		if held then
			-- count LANDINGS, not which coin it was: they land out of order (ShipMoment.lander)
			local land = ShipMoment.lander(total, ShipMoment.COINS)
			stream(hands2, ShipMoment.COINS, leave, total, {
				prepaid = true,
				onCoin = function()
					local shown = land()
					if label.Parent then label.Text = "+" .. UIKit.money(shown) end
				end,
			})
		else
			Moment.landMoney(hands2, ShipMoment.COINS)
			task.delay(1.2, leave)
		end
	end)
end

-- 2A, step 2: they open it (a card over the client) and the stars pop, one by one
local function opened(at, stars)
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0, at.X, 0, at.Y - 6)
	card.Size = UDim2.new(0, 132, 0, 46)
	card.BackgroundColor3 = UIKit.PAPER
	card.ZIndex = 6
	card.Parent = gui
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, UIKit.RADIUS.md)
	local st = Instance.new("UIStroke")
	st.Thickness, st.Color = 2, UIKit.INK
	st.Parent = card
	-- 23 Oct (animation review): the card used to Back-bounce in, the stars Back-bounced from
	-- nothing, and it all lasted 1.4 s. Now the card fades in from 0.94 scale, each star from 0.9,
	-- 0.04 s apart, and the card is gone by 0.75 s (PayoutBeats.CARD / STAR).
	local C, S = PayoutBeats.CARD, PayoutBeats.STAR
	local sc = Instance.new("UIScale")
	sc.Scale = C.from
	sc.Parent = card
	card.BackgroundTransparency = 1
	st.Transparency = 1
	ease(sc, C.enter, { Scale = 1 })
	ease(card, C.enter, { BackgroundTransparency = 0 })
	ease(st, C.enter, { Transparency = 0 })
	-- 18 Oct (playtest 22-54-32): they open it with a click (the switch "thunk", pitched up), then the stars ding
	UIKit.sfx("thunk", 1.25, 0.4)
	for i = 1, 3 do
		local on = i <= stars
		local icon = UIKit.icon(card, "star", 34, on and UIKit.GOLD or UIKit.LINE_LIGHT, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, (i - 2) * 38, 0.5, 0), ZIndex = 7,
		})
		local isc = Instance.new("UIScale")
		isc.Scale = S.from
		isc.Parent = icon
		icon.ImageTransparency = 1
		task.delay(S.first + (i - 1) * S.gap, function()
			if on then UIKit.sfx("ding", 1 + i * 0.12, 0.35) end
			ease(isc, S.enter, { Scale = 1 })
			ease(icon, S.enter, { ImageTransparency = 0 })
		end)
	end
	task.delay(C.leaveAt, function()
		if not card.Parent then return end
		ease(card, C.leave, { Position = card.Position - UDim2.new(0, 0, 0, C.rise), BackgroundTransparency = 1 })
		ease(st, C.leave, { Transparency = 1 })
		for _, c in ipairs(card:GetChildren()) do
			if c:IsA("ImageLabel") then ease(c, C.leave, { ImageTransparency = 1 }) end
		end
		task.delay(C.leave + 0.02, function() card:Destroy() end)
	end)
end

-- the server has already paid: hold the amount back so the cash counter climbs coin by coin
-- instead of jumping before any coin arrives (the same trick as wow(); false = no HUD to hold it)
local function holdPayout(d)
	local hold = rawget(_G, "SVCashHold")
	local stream = rawget(_G, "SVCoinStream")
	if type(hold) == "function" and type(stream) == "function" then
		hold(d.pay + (d.tip or 0))
		return true
	end
	return false
end

local function cash(d, at, coder)
	if coder then
		-- a hired coder's delivery: unchanged in this pass (the 23 Oct coder pass is separate)
		pop("+" .. UIKit.money(d.pay), at, UIKit.TYPE.title, UIKit.MONEY)
		if (d.tip or 0) > 0 then
			pop("+" .. UIKit.money(d.tip) .. " TIP", at + Vector2.new(0, 34), UIKit.TYPE.label, UIKit.GOLD, 0.25)
		end
		Moment.landMoney(at, 3)
		return
	end
	-- 23 Oct (animation review): "+$X" and the tip arrive together (the tip 30 px below), and the
	-- 6 coins carry the amount, so the counter counts up with them (the caller held it back first)
	local tip = d.tip or 0
	pop("+" .. UIKit.money(d.pay), at, UIKit.TYPE.headline, UIKit.MONEY)
	if tip > 0 then
		pop("+" .. UIKit.money(tip) .. " TIP", at + Vector2.new(0, PayoutBeats.MONEY.tipGap), UIKit.TYPE.label, UIKit.GOLD)
	end
	local stream = rawget(_G, "SVCoinStream")
	if type(rawget(_G, "SVCashHold")) == "function" and type(stream) == "function" then
		stream(at, PayoutBeats.COINS, nil, d.pay + tip, { prepaid = true })
	else
		Moment.landMoney(at, PayoutBeats.COINS)
	end
	UIKit.sfx("ding", 1.2, 0.5)
end

clientPaid.OnClientEvent:Connect(function(d)
	if type(d) ~= "table" or type(d.pay) ~= "number" then return end
	local where = typeof(d.at) == "Vector3" and d.at or Vector3.zero
	if ShipMoment.plays(d) then
		-- the first ship: the moment carries its own handoff (no 2A fly and stars on top)
		wow(d)
		return
	end
	--[[ 17 Oct review: a coder's delivery fired every few seconds in the late game, and an
		off-screen client fell back to the middle of the screen, so a player driving or in a
		chase got "+$X" and coins at screen centre. A coder's pay shows only on a client you
		can see, within 60 studs; the cash counter still counts it. ]]
	if d.who == "coder" then
		local cam = workspace.CurrentCamera
		local v, onScreen = cam:WorldToViewportPoint(where + Vector3.new(0, 4, 0))
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if onScreen and root and (root.Position - where).Magnitude <= 60 then
			cash(d, Vector2.new(v.X, v.Y), true)
		end
		return
	end
	local at = screenAt(where + Vector3.new(0, 4, 0))
	if type(d.stars) ~= "number" or typeof(d.from) ~= "Vector3" then
		holdPayout(d)
		cash(d, at, false)
		return
	end
	holdPayout(d)
	fly(d.from + Vector3.new(0, 1.5, 0), where + Vector3.new(0, 3, 0), function()
		local head = screenAt(where + Vector3.new(0, 5.5, 0))
		opened(head, math.clamp(math.floor(d.stars), 1, 3))
		task.delay(PayoutBeats.MONEY.at - PayoutBeats.FLY.seconds, function() cash(d, at + Vector2.new(0, 30), false) end)
	end)
end)
