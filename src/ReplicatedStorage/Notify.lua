--[[
	Notify -- ModuleScript in ReplicatedStorage. Client-side only.

	v4.2 THE CALM SCREEN. His note (28 Sep): "every interaction in the game
	shouldn't all pop up at once ... notifications from your phone, build
	notifications ... when you're driving there's also another UI pop-up."
	The audit counted 24 separate screen notifications with no shared queue:
	a phone text landed exactly on the headhunter warning mid-chase.

	One referee. Every transient asks here first:
	  Notify.show{ lane, priority, key, open(done), close?, ttl?, fallback?,
	               calm?, valid?, delay?, maxHold? }
	    lane      "top" | "centre" | "bottom"; one item per lane at a time
	    priority  0 danger · 1 earned · 2 progress · 3 ambient
	    open      draws it; call done() when it has gone
	    close     hides it early (danger needed the lane)
	    fallback  runs instead when it is dropped (e.g. the phone badge)
	    calm      only at a calm moment: centre and top idle 5 s, not busy
	    valid     checked before showing; false = drop quietly
	    delay     seconds before it may show
	  Notify.hold(lane, key) / Notify.release(key)   a live status owns a lane
	  Notify.state()   { driving, carrying, cutscene, menu }
	  Notify.toast(text, opts)   the one bottom toast (see Task 4)
	The rules are the table in docs/superpowers/specs/2026-09-28-v42-calm-ranks-home-design.md.
]]
local Notify = {}

local LANES = { "centre", "top", "bottom" }     -- centre first: top checks it
local MAX_HOLD = { top = 8, centre = 30, bottom = 8 }
local P3_GAP = 20
local P3_TTL = 15
local CALM_IDLE = 5

local Director = {}
Director.__index = Director

function Notify.new(env)
	local self = setmetatable({}, Director)
	self.env = env
	self.lanes = {}
	local now = env.now()
	for _, name in ipairs(LANES) do
		self.lanes[name] = { name = name, current = nil, hold = nil, idleSince = now }
	end
	self.queue = {}
	self.seq = 0
	self.lastAmbient = -math.huge
	return self
end

-- "wait", "drop" or nil (allowed now)
function Director:_rule(it, st)
	local p = it.priority
	if st.cutscene then return p == 3 and "drop" or "wait" end
	if p == 0 then return nil end
	if st.driving then return p == 3 and "drop" or "wait" end
	if p == 1 then return nil end
	if st.carrying or st.menu then return p == 3 and "drop" or "wait" end
	return nil
end

function Director:_canUse(it)
	local lane = self.lanes[it.lane]
	if lane.current or lane.hold then return false end
	-- a centre card reaches up into the top strip on a phone: only danger shares
	if it.lane == "top" and it.priority > 0 and self.lanes.centre.current then return false end
	if it.lane == "centre" and self.lanes.top.current and self.lanes.top.current.priority > 0 then return false end
	return true
end

function Director:_ready(it, st, now)
	if self:_rule(it, st) then return false end
	if it.delay and now - it.t0 < it.delay then return false end
	if it.priority == 3 and now - self.lastAmbient < P3_GAP then return false end
	if it.calm then
		local c, tp = self.lanes.centre, self.lanes.top
		if c.current or tp.current or tp.hold then return false end
		if now - c.idleSince < CALM_IDLE or now - tp.idleSince < CALM_IDLE then return false end
	end
	return self:_canUse(it)
end

function Director:_open(it, now)
	local lane = self.lanes[it.lane]
	lane.current = it
	it.shownAt = now
	if it.priority == 3 then self.lastAmbient = now end
	local run = {}
	it.run = run
	local function done() if it.run == run then self:_finish(it) end end
	task.spawn(function()
		local ok, err = pcall(it.open, done)
		if not ok then
			warn(("[Notify] %s failed to open: %s"):format(tostring(it.key), tostring(err)))
			done()
		end
	end)
end

function Director:_finish(it, forced)
	local lane = self.lanes[it.lane]
	if lane.current ~= it then return end
	lane.current = nil
	it.run = nil
	lane.idleSince = self.env.now()
	if forced and it.close then pcall(it.close) end
	self:pump()
end

-- take the lane from whatever shows: earned moments come back, the rest drop.
-- keepAll (a cutscene took the screen): danger, earned AND progress come back
function Director:_bump(lane, keepAll)
	local cur = lane.current
	if not cur then return end
	lane.current = nil
	cur.run = nil
	lane.idleSince = self.env.now()
	if cur.close then pcall(cur.close) end
	if cur.priority == 1 or (keepAll and cur.priority <= 2) then
		cur.t0 = self.env.now()
		cur.delay = nil
		table.insert(self.queue, cur)
	elseif cur.fallback then
		pcall(cur.fallback)
	end
end

function Director:show(it)
	assert(type(it) == "table" and self.lanes[it.lane], "Notify.show: bad lane " .. tostring(it and it.lane))
	assert(type(it.open) == "function", "Notify.show: open() required")
	self.seq += 1
	it.seq = self.seq
	it.t0 = self.env.now()
	it.priority = it.priority or 2
	if it.priority == 3 and it.ttl == nil then it.ttl = P3_TTL end
	local lane = self.lanes[it.lane]
	if it.priority == 0 and lane.current and lane.current.priority > 0 and not lane.hold then self:_bump(lane) end
	table.insert(self.queue, it)
	self:pump()
	return it
end

function Director:hold(laneName, key)
	local lane = self.lanes[laneName]
	if not lane or lane.hold == key then return end
	lane.hold = key
	self:_bump(lane)
end

function Director:release(key)
	for _, lane in pairs(self.lanes) do
		if lane.hold == key then
			lane.hold = nil
			lane.idleSince = self.env.now()
		end
	end
	self:pump()
end

function Director:pump()
	if self.pumping then self.again = true return end
	self.pumping = true
	repeat
		self.again = false
		local now = self.env.now()
		local st = self.env.state()
		-- the safety net: a card that never said done frees its lane
		for name, lane in pairs(self.lanes) do
			local cur = lane.current
			if cur and now - cur.shownAt > (cur.maxHold or MAX_HOLD[name]) then
				lane.current = nil
				cur.run = nil
				lane.idleSince = now
				if cur.close then pcall(cur.close) end
			end
		end
		-- a cutscene (the HQ orbit, a new car) hides every gui while it plays: it
		-- takes back whatever is showing, so an earned moment is never spent
		-- behind the letterbox (found live: the orbit swallowed a rare-hire card)
		if st.cutscene then
			for _, lane in pairs(self.lanes) do
				if lane.current then self:_bump(lane, true) end
			end
		end
		-- drop what is not allowed now, expired or no longer valid
		for i = #self.queue, 1, -1 do
			local it = self.queue[i]
			local invalid = it.valid and not it.valid()
			local expired = it.ttl and now - it.t0 > it.ttl
			if invalid or expired or self:_rule(it, st) == "drop" then
				table.remove(self.queue, i)
				if it.fallback and not invalid then pcall(it.fallback) end
			end
		end
		-- the most urgent ready item first, across all lanes (the top and centre
		-- lanes exclude each other, so lane order would decide who wins: found
		-- live, an item card beat a Unicorn card after a cutscene); oldest first
		local order = table.clone(self.queue)
		table.sort(order, function(a, b)
			if a.priority ~= b.priority then return a.priority < b.priority end
			return a.seq < b.seq
		end)
		for _, it in ipairs(order) do
			-- v4.3: an earned moment (P0/P1) never waits behind ambient news (P3).
			-- Found live: the Series A investor's opener banner (P3, top) held the
			-- lane over the HQ level-up banner (P1) for its whole 15 s TTL.
			if it.priority <= 1 and not self:_rule(it, st) and (not it.delay or now - it.t0 >= it.delay) then
				local mine = self.lanes[it.lane]
				if mine.current and mine.current.priority == 3 then self:_bump(mine) end
				local other = (it.lane == "top" and self.lanes.centre) or (it.lane == "centre" and self.lanes.top) or nil
				if other and other.current and other.current.priority == 3 then self:_bump(other) end
			end
			if self:_ready(it, st, now) then
				table.remove(self.queue, table.find(self.queue, it))
				self:_open(it, now)
			end
		end
	until not self.again
	self.pumping = false
end

-- ============ THE SHARED INSTANCE (the running game) ============

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

local default
local function realEnv(player)
	local okU, UIKit = pcall(function() return require(RS:WaitForChild("UIKit", 10)) end)
	local okC, Cine = pcall(function() return require(RS:WaitForChild("Cine", 10)) end)
	return {
		now = os.clock,
		state = function()
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			local seat = hum and hum.SeatPart
			local menu = player:GetAttribute("BuildModeOpen") == true or player:GetAttribute("NamingOpen") == true
			local pg = player:FindFirstChild("PlayerGui")
			if not menu and okU and UIKit and UIKit.MENUS and pg then
				for _, n in ipairs(UIKit.MENUS) do
					local g = pg:FindFirstChild(n)
					if g and g:IsA("ScreenGui") and g.Enabled then menu = true break end
				end
			end
			return {
				driving = seat ~= nil and seat:IsA("VehicleSeat"),
				carrying = player:GetAttribute("Carrying") ~= nil,
				cutscene = okC and Cine and Cine.busy() or false,
				menu = menu,
			}
		end,
	}
end

local function get()
	if default then return default end
	local player = Players.LocalPlayer
	assert(RunService:IsClient() and player, "Notify is client-side")
	default = Notify.new(realEnv(player))
	task.spawn(function()
		while true do
			task.wait(0.2)
			default:pump()
		end
	end)
	return default
end

function Notify.show(it) return get():show(it) end
function Notify.hold(lane, key) get():hold(lane, key) end
function Notify.release(key) get():release(key) end
function Notify.state() return get().env.state() end

-- v4.3: for overlays that must never HOLD a lane (the HUD tips, CoachClient): is
-- something on screen they should step aside for? A card or banner in the centre
-- or top lane, or driving / carrying / a cutscene / a menu.
function Notify.busy()
	local d = get()
	local c, tp = d.lanes.centre, d.lanes.top
	if c.current or tp.current or tp.hold then return true end
	local st = d.env.state()
	return (st.driving or st.carrying or st.cutscene or st.menu) and true or false
end

-- ============ THE ONE TOAST (bottom lane) ============
-- v4.2: three toasts (Product, Car, Lift) drew in three places, one of them on
-- top of another. Now one white pill just above WRITE CODE, one at a time.
local toastGui, toastPill, toastSerial
local function toastParts()
	if toastPill and toastPill.Parent then return toastPill end
	local player = Players.LocalPlayer
	local UIKit = require(RS:WaitForChild("UIKit"))
	toastGui = Instance.new("ScreenGui")
	toastGui.Name = "NotifyToast"
	toastGui.ResetOnSpawn = false
	toastGui.IgnoreGuiInset = true
	toastGui.DisplayOrder = 13
	UIKit.safe(toastGui)
	toastGui.Parent = player:WaitForChild("PlayerGui")
	local pill = Instance.new("TextLabel")
	pill.Name = "Toast"
	pill.AnchorPoint = Vector2.new(0.5, 1)
	pill.Position = UDim2.new(0.5, 0, 1, 60)
	pill.Size = UDim2.new(0.9, 0, 0, 44)
	pill.BackgroundColor3 = UIKit.CARD
	pill.Text = ""
	pill.TextColor3 = UIKit.CARD_TEXT
	pill.TextSize = 16
	UIKit.setFont(pill, UIKit.BODY)
	pill.TextTruncate = Enum.TextTruncate.AtEnd
	pill.Parent = toastGui
	Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)
	local st = Instance.new("UIStroke", pill)
	st.Color = UIKit.INK_SOFT
	st.Thickness = 2
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	UIKit.lip(pill, 4)
	local pad = Instance.new("UIPadding", pill)
	pad.PaddingLeft = UDim.new(0, 46); pad.PaddingRight = UDim.new(0, 18)
	UIKit.icon(pill, "info", 24, UIKit.BLUE, { Name = "Icon", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -34, 0.5, -1) })
	local cap = Instance.new("UISizeConstraint", pill)
	cap.MaxSize = Vector2.new(480, 44)
	toastPill = pill
	toastSerial = 0
	return pill
end

function Notify.toast(text, opts)
	opts = opts or {}
	local TweenService = game:GetService("TweenService")
	local player = Players.LocalPlayer
	local function away(pill)
		TweenService:Create(pill, TweenInfo.new(0.25), { Position = UDim2.new(0.5, 0, 1, 60) }):Play()
	end
	return Notify.show({ lane = "bottom", priority = opts.priority or 2, key = "toast",
		close = function() if toastPill then toastSerial += 1; away(toastPill) end end,
		open = function(done)
			local pill = toastParts()
			toastSerial += 1
			local mine = toastSerial
			pill.Text = tostring(text)
			-- v5: the icon says whose news it is (it was one blue "i" for everything)
			local UIKit = require(RS:WaitForChild("UIKit"))
			local ic = pill:FindFirstChild("Icon")
			if ic then
				ic.Image = UIKit.ICON[opts.icon or "info"] or UIKit.ICON.info
				ic.ImageColor3 = opts.iconColor or UIKit.BLUE
			end
			if opts.sfx then require(RS:WaitForChild("UIKit")).sfx(opts.sfx) end
			-- v5: above the bottom slot AND its caption (at -98 it covered "NEXT APP")
			TweenService:Create(pill, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { Position = UDim2.new(0.5, 0, 1, -118) }):Play()
			local conn
			local function finish()
				if conn then conn:Disconnect(); conn = nil end
				if toastSerial == mine then away(pill) end
				task.delay(0.3, done)
			end
			if opts.untilCarryEnds then
				-- a "Get home!" line leaves with the carry (25 Sep test: it sat under LOST!)
				conn = player:GetAttributeChangedSignal("Carrying"):Connect(function()
					if player:GetAttribute("Carrying") == nil then finish() end
				end)
			end
			task.delay(opts.hold or 4.5, function() if toastSerial == mine then finish() end end)
		end })
end

return Notify
