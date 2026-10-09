--[[
	SILICON VALLEY TYCOON -- SiliconCore v2 (six plots)
	Server Script in ServerScriptService.

	THE WORLD IS A VALLEY WITH A ROAD DOWN THE MIDDLE. Six plots sit along the
	road, three a side, each a full campus: garage -> startup office -> tech HQ
	in the middle, six build slots for wings around it, a concrete apron and a
	path to the road. Downtown is a glass-tower cluster at the east end of the
	road; the mountains are a noise heightmap (ValleyGen).

	A player is ASSIGNED a free plot on join and spawns INSIDE its garage, so
	the onboarding sheet is untouched:

	  0:00  spawn INSIDE the garage, laptop lit, one prompt: WRITE CODE
	  0:08  first click -> +$5, number pops
	  0:20  third click -> ship the To-Do App, small ceremony
	  0:35  HIRE pad lights up, first intern is free
	  1:00  the intern earns while you watch; income/sec appears
	  1:30  BUILD pads light up -- place your first wing
	  2:30  garage door opens on the road; five rival campuses visible
	  B     build mode: furnish your floors (BuildModeClient)

	EVERY SYSTEM IS PER-PLOT. Sessions carry `plot`; every handler resolves
	`plotOf(player)` and refuses to act on a plot the player does not own.
	Prompts are wired in wirePlot(), AFTER every handler exists, so no closure
	can capture a nil.

	DESIGN RULES CARRIED OVER (do not relearn these):
	  - helpers live ABOVE their first caller (the card shop was bitten 7 times)
	  - information, never decoration: every object here does a job
	  - world objects are built at runtime; they do not exist in edit mode
	  - COUNT what a world-building loop creates; a stacked build is invisible
	  - the install runs a forward-use check; keep it that way
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")

-- every module is pcall'd behind a stub: a missing module degrades a feature,
-- never the server
local function tryRequire(where, name)
	local ok, mod = pcall(function()
		return require(where:WaitForChild(name, 5))
	end)
	if not ok then warn("[SV] " .. name .. " missing: " .. tostring(mod)) end
	return ok and mod or nil
end

local StaffRig = tryRequire(ServerScriptService, "StaffRig")
local CityKit = tryRequire(ServerScriptService, "CityKit")
local ValleyGen = tryRequire(ServerScriptService, "ValleyGen")
local FurnitureKit = tryRequire(ReplicatedStorage, "FurnitureKit")
-- funnel telemetry (AnalyticsService); a missing module degrades to no-ops
local Telemetry = tryRequire(ServerScriptService, "Telemetry")
local CampusArch = tryRequire(ServerScriptService, "CampusArch")   -- v2.8 HQ architecture (glass wings, links, grounds)
local CampusHub = tryRequire(ServerScriptService, "CampusHub")
local FlatLook = tryRequire(ServerScriptService, "FlatLook")     -- v4.7 the cartoon pass: flat materials, contact shadows     -- v9 the central park and the two ring roads
local CampusDistricts = tryRequire(ServerScriptService, "CampusDistricts")   -- v9 the four scenery gaps
local Econ = tryRequire(ServerScriptService, "RoomEconomy")   -- v2.6.0 room economy (stations, caps, fit, wages)
local Journey = require(ServerScriptService:WaitForChild("Journey"))   -- v4.3 the guided loop (pure, tested offline)
local Prog = require(ServerScriptService:WaitForChild("Progression"))   -- v4.3 spin-off curve + offline rule (pure, tested offline)
local Mom = require(ServerScriptService:WaitForChild("Momentum"))       -- v5.0 what you bring back from outside (pure, tested offline)
if not Telemetry then
	local noop = function() end
	Telemetry = { joined = noop, step = noop, platform = noop, event = noop, left = noop }
end
if FurnitureKit then
	local have, missing = FurnitureKit.report()
	print(("[SV] FurnitureKit: %d/%d meshes present"):format(have, have + #missing))
	if #missing > 0 then print("[SV] not imported: " .. table.concat(missing, ", ")) end
end

-- ============ CONFIG ============
local CFG = require(ServerScriptService:WaitForChild("CoreConfig"))   -- tuning constants (v4.2: moved out, the script was at 196/200 locals)

for _, r in ipairs(CFG.ROOMS) do CFG.ROOM_BY_ID[r.id] = r end
-- v2.7.0: HQ prices come from RoomEconomy when V3 is on (overrides CoreConfig.HQ_LEVELS[i].cost)
if Econ and Econ.V3 then for i, c in ipairs(Econ.HQ_COST) do if CFG.HQ_LEVELS[i] then CFG.HQ_LEVELS[i].cost = c end end end

--[[
	ECONOMY v1.0 -- economies of scale, both directions. His note: "$30 for
	a chair while making hundreds of thousands is broken; buying is supposed
	to scale as you build more."
	The lever every lasting Roblox tycoon uses: unit COUNT grows linearly and
	costs a little more each time (1.2-1.35x, never 1.6x), while MULTIPLIERS
	are the exponential. Here the multiplier is the HQ: a bigger company earns
	more per head AND pays more per hire, per wing, per chair. So the next
	purchase always costs roughly 30s-3min of income, from the garage to the
	campus, and the HQ upgrade is the thing you save for (8-15 min each).
	Launches also pay a cash PAYDAY (seconds of income x spike), so shipping
	is a cash source, not just a valuation number.
]]

local sessions = {}   -- userId -> session (v4.5: declared here, the price helpers read it)

local function hqMultOf(plot)
	if plot and plot.wafer and Econ and Econ.WAFERS then return Econ.Wafers.Plan.multAt(plot.wafer.level) end   -- v4.6
	return CFG.HQ_MULT[plot and plot.hq and plot.hq.level or 1] or 1
end
--[[
	v2.4 SPIN-OFF (prestige) + MILESTONE LADDER -- the sink after HQ 5.
	Spin-off: at HQ 5, pay Progression.spinCost(n) (v4.3: follows your income, so
	the wait grows 1.3x per spin-off to 2 h max), reset to the garage with $0,
	keep a permanent +Progression.SPIN_STEP revenue multiplier per
	spin-off (Sell Lemons' Rebirth shape: the reset BUYS a multiplier).
	Milestones: every power of ten of lifetime earnings past MILESTONE_BASE
	is +MILESTONE_STEP revenue forever. Saved: spinoffs (int), earned (int).
	milestones is DERIVED from earned at load, never trusted from a save.
]]
local SPINOFF_BASE = (Econ and Econ.V3) and Econ.SPINOFF_BASE or 5000000
local function spinMultOf(s) return Prog.spinMult(s and s.spinoffs or 0) end
local function nextSpinMultOf(s) return Prog.spinMult((s and s.spinoffs or 0) + 1) end
local function milestoneMultOf(s) return 1 + CFG.MILESTONE_STEP * (s and s.milestones or 0) end
local function spinoffCostOf(s) return Prog.spinCost(s and s.spinoffs or 0, SPINOFF_BASE) end
-- v4.5 THE ECONOMY CLOCK (Progression.runScale): every price inside company n+1 is
-- scaled by one number, so a spin-off's richer company still climbs a real ladder
local function scaleOf(s) return Prog.runScale(s and s.spinoffs or 0) end
local function plotScale(plot) return scaleOf(plot and plot.owner and sessions[plot.owner]) end
local function hqCostOf(s, level)
	local L = CFG.HQ_LEVELS[level]
	return L and math.floor(L.cost * scaleOf(s)) or nil
end
-- what the player is saving for: the next HQ level, or the spin-off at HQ 5 (windfalls are capped against it)
-- v4.6 THE WAFERS: the next BUILD tap for this company: first level, last level (a rebuilt
-- storey is several), price. nil at the top of the blueprint.
--[[ v5.0: MOMENTUM comes off here, in the one function that both the pads and
	the purchase read. Applying it at the till instead would mean the sign
	says one number and the register takes another, which is a bug this file
	has shipped before and should not ship again. Returns the stock that would
	be spent as a fourth value so the caller can deduct exactly what it
	charged for. ]]
local function wafersNext(s, plot)
	if not (Econ and Econ.WAFERS and plot and plot.wafer and s) then return nil end
	local L, last, price = Econ.Wafers.nextBuild(plot, s.record or 1, scaleOf(s), Econ.Wafers.Plan.blueprint(s.spinoffs or 0))
	if not L then return nil end
	-- a rebuild (at or below the record, same rule as WaferPlan.price) keeps the stock
	local p, spent = Mom.quote(price, s.momentum or 0, L <= (s.record or 1))
	return L, last, p, spent
end
local function nextGoalOf(s, plot)
	if Econ and Econ.WAFERS and plot and plot.wafer then
		local L, _, price = wafersNext(s, plot)
		return L and price or spinoffCostOf(s)
	end
	return hqCostOf(s, (plot and plot.hq and plot.hq.level or 1) + 1) or spinoffCostOf(s)
end
local function milestonesFromEarned(earned)
	if (earned or 0) < CFG.MILESTONE_BASE then return 0 end
	return math.min(CFG.MILESTONE_MAX, math.floor(math.log10(earned / CFG.MILESTONE_BASE)) + 1)
end
local function companyLabel(s)
	local n = s and s.name or ""
	local k = s and s.spinoffs or 0
	return k > 0 and (n .. " " .. (CFG.ROMAN[k + 1] or tostring(k + 1))) or n
end
local function fmt(n)
	n = math.floor(n)
	if n >= 1e9 then return string.format("%.1fB", n / 1e9) end
	if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
	if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
	return tostring(n)
end

-- what a hire, a wing, or a piece of furniture costs THIS company right now
-- v2.5.1: a hire costs at least HIRE_SECONDS of current income. Measured in
-- the 18 Sep playtest: $64 per hire while holding $8K made the talent roll a
-- free slot machine. The old curve stays as the floor for new players.
local function hireCostOf(s, plot)   -- floor: 15 s of current income
	if Econ and Econ.V3 then return math.floor(s.hireCost * scaleOf(s)) end   -- v2.7.0: a fixed ladder you outgrow (v4.5 x the company's scale)
	return math.max(math.floor(s.hireCost * hqMultOf(plot)), math.floor((s.rate or 0) * 15))
end
local function wingCostOf(room, plot, rate)
	local built = 0
	for _, slot in ipairs(plot.slots or {}) do if slot.built then built += 1 end end
	if Econ and Econ.V3 then return math.floor(room.cost * (Econ.WING_GROWTH ^ built) * plotScale(plot)) end
	local base = math.floor(room.cost * hqMultOf(plot) * (1 + CFG.WING_STEP * built))
	-- v2.6.4: never cheaper than N seconds of this company's income
	local secs = Econ and Econ.WING_SECONDS and Econ.WING_SECONDS[room.id] or 0
	return math.max(base, math.floor((rate or 0) * secs))
end
local function furniturePriceOf(item, s, plot)
	local mult = hqMultOf(plot) * (1 + CFG.FURNITURE_INFLATION * #(s.placed or {})) * scaleOf(s)
	if FurnitureKit and FurnitureKit.priceFor then
		-- v2.6.3: rounded exactly like the PriceMult attribute the client reads
		-- v2.7.0: no income floor -- furniture is decoration now
		return FurnitureKit.priceFor(item, math.floor(mult * 100 + 0.5) / 100, (Econ and Econ.V3) and 0 or (s.rate or 0))
	end
	return math.floor(item.price * mult)
end

--[[
	WING LEVELS (v1.1) -- the Sell Lemons layer. Every income source there
	has its own upgrade counter with no ceiling and a cost that climbs a step
	per purchase; that counter is why the game never runs out of a next
	button. Here every built wing carries a level: each level costs a step
	more and adds the wing's own effect again (office +2 seats, servers +1
	compute, studio +10% revenue, cafeteria +8% output). This is the sink
	the campus was missing after HQ 5, and a reason to keep a wing instead
	of just filling all six slots.
	Hire cost tapers after 12 people (Restaurant Tycoon 2 grows worker cost
	by a flat +$500 a head, never geometrically -- 1.3^n past 25 was a wall).
]]
-- v2.3: wing levels END. Five levels, each priced in seconds of your CURRENT
-- income (the Sell Lemons shape: the ladder climbs with you, so "cheap and
-- infinite" cannot happen at HQ 5). The old flat formula is only a floor for
-- brand-new players whose rate is still tiny.
local WING_MAX_LEVEL = (Econ and Econ.V3) and Econ.MAX_LEVEL or 5

local function wingUpgradeCostOf(room, level, plot, rate)
	if Econ and Econ.V3 then return math.floor(room.cost * Econ.LEVEL_FIRST * (Econ.LEVEL_GROWTH ^ (level - 1)) * plotScale(plot)) end
	local base = math.floor(room.cost * CFG.WING_UP_BASE * (CFG.WING_UP_GROWTH ^ (level - 1)) * hqMultOf(plot))
	local secs = CFG.WING_UP_SECONDS[level] or CFG.WING_UP_SECONDS[#CFG.WING_UP_SECONDS]
	return math.max(base, math.floor((rate or 0) * secs))
end
local function hireGrowthAt(staff)
	if Econ and Econ.V3 then return Econ.HIRE_GROWTH end
	return staff <= CFG.HIRE_TAPER_AT and CFG.HIRE_GROWTH or CFG.HIRE_GROWTH_LATE
end

-- one more level of a wing: the effect applied again, no charge here
local function applyWingLevel(s, room)
	local amt = CFG.WING_LEVEL_AMOUNT[room.id] or 0
	if room.id == "office" then s.desks += amt
	elseif room.id == "servers" then s.compute = (s.compute or 0) + amt
	elseif room.id == "studio" then s.quality = (s.quality or 0) + amt
	elseif room.id == "cafe" then s.morale = (s.morale or 0) + amt end
end

-- a wing is maxed at WING_MAX_LEVEL, or earlier once its effect is capped
-- (a studio past QUALITY_CAP or a cafe past MORALE_CAP would take money for nothing)
local function wingMaxed(s, slot)
	local lv = slot.level or 1
	if lv >= WING_MAX_LEVEL then return true end
	if Econ and Econ.V3 then
		if lv >= (Econ.LV_BY_HQ[s and s.hqLevel or 1] or WING_MAX_LEVEL) then return true end
		if not Econ.levelUseful(slot) then return true end
	end
	local id = slot.room and slot.room.id
	if id == "studio" and (s.quality or 0) >= CFG.QUALITY_CAP then return true end
	if id == "cafe" and (s.morale or 0) >= CFG.MORALE_CAP then return true end
	return false
end

local function refreshWingPrompt(slot, plot, s)
	if not slot.upPrompt or not slot.room then return end
	local lv = slot.level or 1
	if s and wingMaxed(s, slot) then
		local hqCapped = Econ and Econ.V3 and lv < WING_MAX_LEVEL and Econ.levelUseful(slot)
		slot.upPrompt.ObjectText = hqCapped and ("%s Lv%d  ·  bigger HQ unlocks more"):format(slot.room.name, lv)
			or ("%s Lv%d  ·  MAX"):format(slot.room.name, lv)
		slot.upPrompt.Enabled = false
	else
		local cost = wingUpgradeCostOf(slot.room, lv, plot, s and s.rate)
		slot.upPrompt.ObjectText = ("%s Lv%d  ·  $%s  ·  %s"):format(slot.room.name, lv, fmt(cost), CFG.WING_LEVEL_TEXT[slot.room.id] or "")
		slot.upPrompt.Enabled = true
	end
	if slot.levelTag then slot.levelTag.Text = lv >= WING_MAX_LEVEL and "MAX" or ("LV %d"):format(lv) end
end

--[[
	THE PRODUCT LOOP -- the "repetitive" fix. Every cycle your team finishes a
	product; you pick its MARKET from three cards; it launches with a ceremony;
	revenue SPIKES then DECAYS over five minutes, so the next launch is always
	the next goal. Compute raises the tier, the studio raises the spike, the
	cafeteria shortens the cycle. Names are hand-written: free, and funnier
	than anything a model would produce for a nine-year-old.
]]
--[[
	PRODUCTS ARE GATED ON WORK, NOT A CLOCK. His note: one intern and a
	product popped up -- "wouldn't it make more sense to build more, and then
	you get an offer?" Yes. A work bar fills from the team's output (tier-
	weighted), and each product needs more than the last. One intern takes
	minutes; a floor of seniors takes seconds. The bar is on screen so the
	cause is visible: hire, seat, build -> products faster.
]]

--[[
	SENIORITY. An employee seated at a desk grows: Intern -> Junior -> Senior
	-> Lead, one step every PROMOTE_EVERY seconds, and earns more at each.
	Standing in the waiting line does not count. This is the value a rival
	pays for, and the value you cannot buy back.
]]

--[[
	v2.5 TALENT. Every hire rolls a talent tier ONCE, server-side, at the
	moment of hiring. Talent multiplies output for life and is visible from
	across the room (shirt colour, halo, "1/1491" on the tag). Seniority still
	promotes on top. This is the roll-to-chase loop: the person is the pull.
	Draws run rarest -> commonest so a Unicorn is exactly 1 in 1491 per hire.
]]

-- v3.2.1: luck multiplies every rare tier's chance (Office Vibe, x1.0..x2.0)
CFG.TALENT.roll = function(luck)
	luck = math.clamp(tonumber(luck) or 1, 1, 3)
	for t = #CFG.TALENT, 2, -1 do
		if math.random() * CFG.TALENT[t].odds < luck then return t end
	end
	return 1
end

local function talentMultOf(r)
	local t = CFG.TALENT[r and r.talent or 1] or CFG.TALENT[1]
	return t.mult
end

--[[
	ACQUISITION OFFERS. Every few minutes a rival wants your best person. The
	money is real (three minutes of their output, plus a premium) and so is the
	loss: the replacement is an Intern again, hire cost never drops, and the
	next offer will not come for a while. You can rebuy the body, never the
	seniority -- that is the whole anti-abuse.
]]
--[[
	v1.5 OFFERS THAT PAY. Measured: a sale paid <= 180s of output while the
	replacement Intern needed 6 min to become a Lead again (~4.6 min of Lead
	output lost, plus the rehire fee) -- every sale was a net loss, which is
	why it felt pointless. v2.3: a sale pays income time (offerAmountOf) instead of that person's
	output (cash now vs income later, the one trade-off a nine-year-old
	already understands) and every sale adds to ALUMNI: promotions run
	ALUMNI_STEP faster per sale, capped. Selling is a ladder, not a leak.
]]

local function offerAmountOf(s, cashValue)
	local rate = s.rate or 0
	local worth = (cashValue or 0) + (s.valuation or 0)
	local amount = math.min(rate * CFG.OFFER_INCOME_SECONDS, worth * CFG.OFFER_WORTH_CAP)
	amount = math.max(amount, rate * CFG.OFFER_MIN_SECONDS, 25)
	return math.floor(amount)
end

--[[
	IPO. Valuation is cumulative revenue plus a premium per launch. Cross the
	threshold and the company goes PUBLIC: gold sign, a ticker symbol, and a
	permanent seat on the global ticker board at the road (OrderedDataStore).
	His ask: "a permanent leaderboard, like a stock ticker, shown globally."
]]

--[[
	RIVALS + MARKET SHARE (v0.9). The "99 Nights" pressure, done the way
	tycoons survive it: a rival launches in one of YOUR markets and your share
	slips -- but only while you are ONLINE, never below SHARE_FLOOR, never
	while a launch buzz is running, and only shipping restores it. Nothing
	here is saved; every session starts at 100%. A returning player never
	comes back to a smaller number.
	The Exchange board also lists five AI companies whose valuations grow
	with server uptime, capped just above the best human, so there is always
	someone to overtake and a toast when you do.
]]
local serverStart = os.clock()

-- clear of the LARGEST HQ (68 wide): wings, not storage units glued to a box
-- v2.6.1: rooms were 4 studs apart (28-stud rows for 24-stud rooms) and 4
-- studs off a full-size HQ, so every back-row door opened into a wall. Now an
-- 18-stud walkway beside the 68-wide HQ and a 16-stud aisle in front of each door.
-- Flat ground per plot is local x +-120, z -130..+90, so this still fits.
-- v3.2: the lots ring a promenade round the HQ, doors facing in (CampusArch.LOTS,
-- plot-local CFrames). The old two-column grid is the fallback, and the old
-- layouts live in CampusArch.migrate, which carries saved furniture across.
local SLOT_LOCAL = (CampusArch and CampusArch.LOTS) or {
	Vector3.new(-66, 0, 14),  Vector3.new(66, 0, 14),
	Vector3.new(-66, 0, -26), Vector3.new(66, 0, -26),
	Vector3.new(-66, 0, -66), Vector3.new(66, 0, -66),
}

--[[
	THE LAYOUT. Road on z=0 running east. South plots face +z (toward the
	road); north plots are rotated 180 so they face -z, also toward the road.
	Rotations are 0 or 180 ONLY: the placement engine's overlap math is an
	axis-aligned box test in world space, and it stays exact under 180.
]]

local Pal = require(game:GetService("ReplicatedStorage"):WaitForChild("PaletteLoad"))

-- ============ HELPERS (above every caller, always) ============

--[[ Every part this game builds comes through here or through one of the
	module helpers that mirrors it, so this is where the palette is applied at
	AUTHORING time. A part with no Color named used to inherit Roblox's default
	grey, which is how 719 of them ended up identical and off-palette. ]]
local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	for k, v in pairs(props) do p[k] = v end
	if Pal then Pal.author(p, props) end
	p.Parent = parent
	return p
end

local function label(parent, text, size, offsetY, maxDist, noTop)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 260, 0, 54)
	bb.StudsOffset = Vector3.new(0, offsetY or 3, 0)
	bb.AlwaysOnTop = not noTop
	bb.MaxDistance = maxDist or 90
	bb.Parent = parent
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, 0, 1, 0)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.2
	t.TextSize = size or 20
	t.Font = Enum.Font.FredokaOne       -- v2.8: the game's one display font (was GothamBlack)
	t.Parent = bb
	return t
end

-- v2.8.1: world effects are drawn by WorldFxClient. A server-side tween sends
-- every frame of it to every player: one WRITE CODE tap per second measured
-- 13.7 KB/s (idle 0.49), a room build ~199 KB, an HQ upgrade ~266 KB. The
-- server now sends one small event and each client animates it locally
-- (Roblox perf guide: "Tween objects on the client rather than the server").
-- Looked up at call time (SVRemotes is created further down the file), and
-- inlined: this file sits at Luau's 200 top-level local limit.

local popup
do
-- a refusal ("Need $..", "Outside your floor") goes to every client, and a spammed
-- remote can trigger one per call: one per anchor every 0.3 s is plenty to read
local lastRefusal = setmetatable({}, { __mode = "k" })
function popup(anchor, text, color)
	if not anchor then return end
	if color and color ~= CFG.GOOD then
		local now = os.clock()
		if now < (lastRefusal[anchor] or 0) then return end
		lastRefusal[anchor] = now + 0.3
	end
	local fx = ReplicatedStorage:FindFirstChild("SVRemotes")
	fx = fx and fx:FindFirstChild("Popup")
	if fx then fx:FireAllClients(anchor, text, color or CFG.GOOD) return end
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 240, 0, 44)
	bb.StudsOffset = Vector3.new(0, 3.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 80
	bb.Parent = anchor
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, 0, 1, 0)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextColor3 = color or CFG.GOOD
	t.TextStrokeTransparency = 0.15
	t.TextSize = 28
	t.Font = Enum.Font.FredokaOne
	t.Parent = bb
	TweenService:Create(bb, TweenInfo.new(1.1), { StudsOffset = Vector3.new(0, 6.5, 0) }):Play()
	TweenService:Create(t, TweenInfo.new(1.1),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.2, function() bb:Destroy() end)
end
end


-- two ways in, one code path
local function alsoClickable(target, dist, handler)
	local cd = Instance.new("ClickDetector")
	cd.MaxActivationDistance = dist
	cd.Parent = target
	cd.MouseClick:Connect(handler)
	return cd
end

local function prompt(parent, action, object, dist)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = object
	pp.HoldDuration = 0
	pp.MaxActivationDistance = dist
	pp.RequiresLineOfSight = false
	pp.Parent = parent
	return pp
end

local function cashOf(player)
	local ls = player:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild("Cash")
end

local function rise(parts, drop, seconds)
	-- v2.8.1: parts are already at their final place on the server; clients play the rise
	local fx = ReplicatedStorage:FindFirstChild("SVRemotes")
	fx = fx and fx:FindFirstChild("Rise")
	if fx then fx:FireAllClients(parts, drop, seconds) return end
	for _, p in ipairs(parts) do
		local final = p.CFrame
		p.CFrame = final * CFrame.new(0, -drop, 0)
		TweenService:Create(p, TweenInfo.new(seconds, Enum.EasingStyle.Back,
			Enum.EasingDirection.Out), { CFrame = final }):Play()
	end
end

-- ============ SESSIONS ============

-- (sessions is declared above the price helpers)
local plots = {}      -- index -> plot

local function plotOf(player)
	local s = sessions[player.UserId]
	return s and s.plot or nil
end

-- ============ REMOTES ============

do
	local old = ReplicatedStorage:FindFirstChild("SVRemotes")
	if old then old:Destroy() end
end
local remotes = Instance.new("Folder")
remotes.Name = "SVRemotes"
remotes.Parent = ReplicatedStorage
local function remote(name)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local openBuild = remote("OpenBuild")
local placeRoom = remote("PlaceRoom")
local placeItem = remote("PlaceItem")
local removeItem = remote("RemoveItem")
local askName = remote("AskName")           -- server -> client: name your company
local setName = remote("SetName")           -- client -> server
local productReady = remote("ProductReady") -- server -> client: three market cards
local pickMarket = remote("PickMarket")     -- client -> server
remote("RocketLaunch")                      -- v3.4 server -> all clients: a launch lifts off a roof (RocketClient)
local toast = remote("Toast")               -- server -> client(s): a banner line
remote("Popup")                             -- v2.8.1 server -> clients: (anchor, text, color), drawn by WorldFxClient
remote("Rise")                              -- v2.8.1 server -> clients: (parts, drop, seconds), drawn by WorldFxClient
local talentReveal = remote("TalentReveal") -- server -> client: a rare hire, full-screen moment
local offerEvent = remote("Offer")          -- server -> client: a rival wants your person
local answerOffer = remote("AnswerOffer")   -- client -> server: accept / decline
local menuStats = remote("MenuStats")       -- server -> client: the numbers on the menu
local setMuted = remote("SetMuted")         -- client -> server: remember the mute
local menuDone = remote("MenuDone")         -- client -> server: PLAY pressed (the SERVER owns the attribute;
                                            -- a client-set attribute never replicates up, so rivals were dead)
local clientInfo = remote("ClientInfo")     -- client -> server: touch device or not, once
local goPublicRemote = remote("GoPublic")   -- v4.3 client -> server: ring the bell at HQ 5
local coachSeen = remote("CoachSeen")       -- v4.3 client -> server: a HUD tip was read

-- ============ DATASTORES ============

--[[
	Saved per player, as NUMBERS AND STRINGS ONLY (never AI transcripts, never
	context tokens -- criterion (b) for 18+ is saved AI context). Furniture is
	stored PLOT-LOCAL so a returning player can be seated on any free plot.
	Every read is pcall'd; a failed load NEVER saves (it would stomp a veteran
	with a blank), same doctrine as the card shop.
]]
local DataStoreService = game:GetService("DataStoreService")
local saveStore, tickerStore, nameStore
pcall(function()
	saveStore = DataStoreService:GetDataStore("SVSave_v1")
	tickerStore = DataStoreService:GetOrderedDataStore("SVTicker_v1")
	nameStore = DataStoreService:GetDataStore("SVNames_v1")
end)
local loading = {}     -- userId -> true while a load is in flight
local loaded = {}      -- userId -> true once a load SUCCEEDED (only then may we save)

-- ============ WORLD ============

do
	local old = workspace:FindFirstChild("SiliconValley")
	if old then old:Destroy() end
	for _, d in ipairs(workspace:GetChildren()) do
		if d:IsA("SpawnLocation") then d:Destroy() end
	end
end

local world = Instance.new("Folder")
world.Name = "SiliconValley"
world.Parent = workspace

local plotsFolder = Instance.new("Folder")
plotsFolder.Name = "Plots"
plotsFolder.Parent = world

-- THE VALLEY. Flat rects are every place something is built; the generator
-- holds them at exactly 0 and blends the terrain out around them.
do
	local flat = {}
	for _, def in ipairs(CFG.PLOT_DEFS) do
		local c = def.pivot:PointToWorldSpace(Vector3.new(0, 0, -20))
		table.insert(flat, { x = c.X, z = c.Z, w = 240, d = 220 })
	end
	--[[ v9: the campus is a RING now, so the flat ground has to be a ring too.
	ValleyGen only takes axis-aligned rects, so each ring road is laid as 24
	short rects round the circle -- the same trick CampusHub uses to draw them.
	The park inside is one big rect; it is flat ground either way. ]]
	if CampusHub then
		table.insert(flat, { x = 0, z = 0, w = 2 * CampusHub.R_PARK + 80, d = 2 * CampusHub.R_PARK + 80 })
		for _, r in ipairs({ CampusHub.R_ROAD_IN, CampusHub.R_DIST, CampusHub.R_ROAD_OUT }) do
			for i = 0, 23 do
				local a = i * math.pi / 12
				table.insert(flat, { x = math.cos(a) * r, z = math.sin(a) * r, w = 118, d = 118 })
			end
		end
	end
	-- the east approach: the only straight road left, out to downtown
	table.insert(flat, { x = 760, z = CFG.ROAD_Z, w = 820, d = 74 })
	table.insert(flat, { x = 780, z = CFG.ROAD_Z, w = 320, d = 200 })    -- downtown
	-- v1.6: the two cross streets and their building blocks (CityKit.CROSS_X)
	for _, cx in ipairs((CityKit and CityKit.CROSS_X) or { -185, 165 }) do
		table.insert(flat, { x = cx, z = CFG.ROAD_Z, w = 120, d = 2 * ((CityKit and CityKit.CROSS_LEN) or 250) + 40 })
	end
	if ValleyGen then
		-- v3.3 the Caltrain corridor behind the south campuses, from the Bay
		-- causeway (west) to a tunnel portal in the eastern hills
		--[[ v4.6 pass 5: the line used to run x -915..648 with the Mountain View
		platform centred on x = 0. The campus moved onto a ring after that was
		written, and x 0, z -330 is now INSIDE the plot at 270 degrees: the
		track ran through that player's tower, across the event lawn and over
		two ring roads, and the platform stood in the building. The line is
		short now and lives entirely southwest of the campus, still inside the
		terrain's baked flat strip (lp_world.py FLAT, x -915..648 at z -330),
		so no terrain changes. ]]
		local rail = { x1 = -915, x2 = -600, z = -330, station = -740, berm = true }
		table.insert(flat, { x = (rail.x1 + rail.x2) / 2, z = rail.z, w = rail.x2 - rail.x1, d = 40, kind = "rail" })
		local info = ValleyGen.build(world, {
			-- v3.3 the Santa Clara Valley: a forested ridge south, golden hills
			-- north, the Bay west. The hills start 160 studs past the plots and
			-- crest ~600 out: close enough to render at LOW graphics quality
			-- (low-end phones cull terrain past ~500-600 studs, measured)
			--[[ v9: basin 430 -> 700. The campus is a ring 596 studs out now, so at
			the old basin the OUTER RING ROAD sat on the hillside. The floor has to
			reach past the whole campus before the ground is allowed to rise.
			rim 680 -> 980 keeps the slope about as steep as it was (250 studs of
			rise before, 280 now) instead of making a wall out of it. The terrain
			is capped at 2048 studs, so extentX stays at 1000 -- the hills are
			pushed out, the map is not made bigger. ]]
			flatRects = flat, margin = 46, basin = 700, rim = 980, peakSouth = 190, peakNorth = 205,
			stretchX = 1.35, seed = 7, extentX = 1000, extentZ = 800, bayX = 640,
			-- the hills the line tunnels into at both ends
			mounds = { { x0 = rail.x2 - 18, z = rail.z, halfW = 22, h = 50, dir = 1 }, { x0 = rail.x1 + 18, z = rail.z, halfW = 22, h = 50, dir = -1 } },
			orchards = { { x = -360, z = 335, w = 120, d = 70 }, { x = 330, z = 335, w = 110, d = 70 } },
			rail = rail, crossX = (CityKit and CityKit.CROSS_X) or {}, plotX = {},
			-- v9: palms line the ring and the east approach, not a road through the park
			palmRing = CampusHub and { r = CampusHub.R_ROAD_OUT, w = 30 } or nil,
			palmRoad = { x1 = ((CampusHub and CampusHub.R_ROAD_OUT) or 596) + 70, x2 = 900, z = 31 },
			oaks = 230, redwoods = 100, treeMax = 640, vergeTrees = 50, settlementX = 560, settlementZ = 280,
		})
		print(("[SV] valley: %d chunks, peak %.0f, %d oaks, %d redwoods, %d verge, %d palms, %d eucalypts, %d orchard, %d landmarks, %.1fs")
			:format(info.chunks, info.maxHeight, info.oaks, info.redwoods, info.verge, info.palms, info.eucalypts, info.orchard, info.landmarks, info.seconds))
	else
		local bp = workspace:FindFirstChild("Baseplate")
		if bp then bp:Destroy() end
		part({ Name = "Ground", Size = Vector3.new(1600, 1, 1600), Position = Vector3.new(0, -0.5, 0),
			Color = Color3.fromRGB(104, 150, 80), Material = Enum.Material.Grass }, world)
	end
end

--[[
	NO FAKE BACKDROP RANGE. Tried it twice: wedge silhouettes read as pale
	paper triangles at one tint and vanished into the horizon band at the
	next. Fake geometry loses both ways. The real range starts 430 studs out
	so it renders on low-quality devices; on his Studio the fix is
	File > Studio Settings > Rendering > Quality Level 21.
]]

-- THE STREET
if CityKit then
	-- v4.0: the street ends at the downtown roundabout (x 700); Downtown.lua builds the city
	local okD, Downtown = pcall(function() return require(ServerScriptService:WaitForChild("Downtown", 5)) end)
	local roadEnd = (okD and Downtown and Downtown.ROAD_END) or 940
	-- v9: x1 was -560, which drove the straight road straight through the middle
		-- of what is now the park. It starts at the outer ring road and runs east.
		local _, made = CityKit.buildStreet(world, { groundY = 0, z = CFG.ROAD_Z, x1 = (CampusHub and CampusHub.R_ROAD_OUT or 596) - 10, x2 = roadEnd, towersX = 660, noTowers = okD and Downtown ~= nil })
	print(("[SV] street: %d buildings, %d props"):format(made.buildings, made.props))
	if CityKit.buildKenneyCity then
		local _, k = CityKit.buildKenneyCity(world, { groundY = 0, z = CFG.ROAD_Z, x1 = (CampusHub and CampusHub.R_ROAD_OUT or 596) - 10, x2 = roadEnd })
		if k then print(("[SV] kenney city: %d tiles, %d blocks, %d lamps, %d cars"):format(k.tiles, k.buildings, k.lamps, k.cars)) end
	end
	if okD and Downtown and Downtown.build then
		local okB, err = pcall(Downtown.build, world)
		print(okB and "[SV] downtown built" or ("[SV] downtown failed: " .. tostring(err)))
	end
else
	part({ Name = "Road", Size = Vector3.new(1500, 1, 26), Position = Vector3.new(190, 0.5, CFG.ROAD_Z),
		Color = Color3.fromRGB(58, 57, 58), Material = Enum.Material.Asphalt }, world)
end

-- v9: the park and the ring roads the six plots stand around
if CampusHub then
	local okH, errH = pcall(CampusHub.build, world)
	if okH then
		print("[SV] campus hub: park + ring roads")
	else
		warn("[SV] CampusHub failed: " .. tostring(errH))
	end
	if CampusDistricts then
		local okD2, errD2 = pcall(CampusDistricts.build, world, CampusHub.R_DIST)
		if okD2 then
			print("[SV] districts: arrival, parking, retail, event lawn")
		else
			warn("[SV] CampusDistricts failed: " .. tostring(errD2))
		end
	end
	--[[ v4.9 THE GROUND SWEEP. Everything that paves ground has now run, so
		this is the one place where "who built first" stops mattering: any
		valley greenery still standing on reserved ground goes, and the zones
		are published for tools/world_overlap.luau to check from outside. ]]
	local Ground = tryRequire(ServerScriptService, "Ground")
	if Ground then
		local okG, removed, byZone = pcall(Ground.sweep, { world:FindFirstChild("LowPolyWorld"), world:FindFirstChild("Valley") })
		if okG then
			local parts = {}
			for k, v in pairs(byZone or {}) do table.insert(parts, ("%s %d"):format(k, v)) end
			print(("[SV] ground sweep: %d pieces of greenery cleared off paving%s"):format(
				removed or 0, #parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or ""))
		else
			warn("[SV] ground sweep failed: " .. tostring(removed))
		end
		pcall(Ground.publish, world)
	end

	--[[ v5.0 THE PLACEMENT PASS -- the one that is not allowed to go stale.

		Ground.sweep above still runs, because clearing valley greenery off a
		district slab is a job it does well. What it could not do is notice
		paving nobody had named: it knew 8 reserved zones out of 967 paved
		parts, and it was forbidden from touching a builder's own folder, so
		100 of CampusHub's trees stood in CampusHub's own footpaths.

		This pass finds surfaces by SHAPE -- broad, thin, horizontal, not
		green -- across the whole world, including every folder the sweep was
		told to spare. A tree with a small intrusion gets a stone pit, which
		is what a street tree has in life; a tree too far in is walked to
		clear ground; one with nowhere to go is removed. ]]
	local Place = tryRequire(ServerScriptService, "Placement")
	if Place then
		local okS, found, skipped = pcall(Place.scanSurfaces, world)
		if okS then
			local roots = { world }
			local before = #Place.violations(roots)
			local okR, pitted, moved, gone = pcall(Place.resolve, roots)
			if okR then
				local after = #Place.violations(roots)
				print(("[SV] placement: %d hard surfaces (%d parts skipped) | %d greenery in paving -> %d pits, %d moved, %d removed | %d left")
					:format(found, skipped, before, pitted, moved, gone, after))
				if after > 0 then
					warn(("[SV] placement: %d pieces of greenery are STILL standing in paving"):format(after))
				end
			else
				warn("[SV] placement resolve failed: " .. tostring(pitted))
			end
		else
			warn("[SV] placement scan failed: " .. tostring(found))
		end
	end
end

-- hub spawn: only used before a plot is assigned, or by a 7th body
do
	local sp = Instance.new("SpawnLocation")
	sp.Name = "HubSpawn"
	sp.Size = Vector3.new(6, 1, 6)
	-- v9: (0, ROAD_Z) is the middle of the fountain now. Stand on the park's
	-- south walk instead, looking in at the monument.
	sp.CFrame = CFrame.new(0, 1.5, (CampusHub and CampusHub.R_PARK - 22) or CFG.ROAD_Z)
	sp.Transparency = 1
	sp.CanCollide = false
	sp.Anchored = true
	sp.Neutral = true
	sp.Duration = 0
	sp.Parent = world
end

-- ============ PLOT GEOMETRY ============

local function shellPart(plot, props)
	local p = part(props, plot.garage)
	table.insert(plot.hq.shell, p)
	return p
end

--[[
	THE HQ SHELL, per level. Each upgrade tears the old shell down and raises
	a bigger one around the furniture; placed items sit at world coordinates
	on a floor that only grows, so nothing built is touched. Level 2+ get a
	permanent open entrance flanked by glass, so the interior you furnished
	shows from the road -- the aspiration mechanic doing its job.
]]
local function buildShell(plot, level, animate)
	for _, p in ipairs(plot.hq.shell) do p:Destroy() end
	plot.hq.shell = {}
	plot.hq.doorL, plot.hq.doorR = nil, nil
	plot.hq.level = level
	local g = plot.g
	local L = CFG.HQ_LEVELS[level]
	local w, d, h = L.w, L.d, L.h

	-- v5: 6 studs thick, top still at 1.0. There is no ground under a plot (void to
	-- the -500 kill height), and a 1-stud slab is thin enough for the solver to
	-- push a character through ("stuck in the floor and die" on an HQ upgrade)
	shellPart(plot, { Name = "GarageFloor", Size = Vector3.new(w, 6, d), CFrame = g(0, -2, 0),
		Color = CFG.FLOOR, Material = Enum.Material.Concrete })
	shellPart(plot, { Name = "WallBack", Size = Vector3.new(w, h, 1), CFrame = g(0, h / 2, -d / 2), Color = CFG.WALL })
	shellPart(plot, { Name = "WallL", Size = Vector3.new(1, h, d), CFrame = g(-w / 2, h / 2, 0), Color = CFG.WALL })
	shellPart(plot, { Name = "WallR", Size = Vector3.new(1, h, d), CFrame = g(w / 2, h / 2, 0), Color = CFG.WALL })
	shellPart(plot, { Name = "Roof", Size = Vector3.new(w, 1, d + 1), CFrame = g(0, h, 0), Color = CFG.TRIM })

	-- the company name plate: on every level, readable from the road. Gold
	-- once the company is public.
	local plate = shellPart(plot, { Name = "NamePlate", Size = Vector3.new(math.min(w - 12, 26), 3.4, 0.5),
		CFrame = g(0, h + 2.2, d / 2 - 0.8), Color = CFG.TRIM, Material = Enum.Material.SmoothPlastic })
	-- The name is painted ON the plate (SurfaceGui), not floated over it. A
	-- billboard centred in the 0.5-stud plate was half-clipped by the plate's
	-- own face from any raised camera (the menu orbit shot showed it), and a
	-- billboard pushed in front still fought the Neon bloom. The plate's +Z
	-- face (NormalId.Back) is the plot's front, toward the road.
	do
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Back
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 40
		sg.LightInfluence = 0
		sg.MaxDistance = 260
		sg.Parent = plate
		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, 0, 1, 0)
		t.BackgroundTransparency = 1
		t.Text = ""
		t.TextScaled = true
		-- dark letters: the plate is Neon from level 2, and white-on-glow has no edge
		t.TextColor3 = Color3.fromRGB(14, 17, 23)
		t.TextStrokeTransparency = 1
		t.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold)   -- v2.8: building signage, same family as the wings
		t.Parent = sg
		local pad = Instance.new("UIPadding", t)
		pad.PaddingLeft = UDim.new(0.04, 0); pad.PaddingRight = UDim.new(0.04, 0)
		pad.PaddingTop = UDim.new(0.12, 0); pad.PaddingBottom = UDim.new(0.12, 0)
		plot.signTag = t
	end
	plot.signPlate = plate

	if level == 1 then
		shellPart(plot, { Name = "DoorHeader", Size = Vector3.new(w, 3, 1),
			CFrame = g(0, h - 1.5, d / 2), Color = CFG.TRIM })
		plot.hq.doorL = shellPart(plot, { Name = "DoorL", Size = Vector3.new(w / 2 - 0.5, h - 3, 0.6),
			CFrame = g(-(w / 4 + 0.1), (h - 3) / 2, d / 2),
			Color = Color3.fromRGB(150, 148, 146), Material = Enum.Material.DiamondPlate })
		plot.hq.doorR = shellPart(plot, { Name = "DoorR", Size = Vector3.new(w / 2 - 0.5, h - 3, 0.6),
			CFrame = g(w / 4 + 0.1, (h - 3) / 2, d / 2),
			Color = Color3.fromRGB(150, 148, 146), Material = Enum.Material.DiamondPlate })
		if plot.doorOpened then
			plot.hq.doorL.CFrame = plot.hq.doorL.CFrame * CFrame.new(0, 11, 0)
			plot.hq.doorR.CFrame = plot.hq.doorR.CFrame * CFrame.new(0, 11, 0)
		end
	else
		local doorW = 14
		local sideW = (w - doorW) / 2
		for _, side in ipairs({ -1, 1 }) do
			shellPart(plot, { Name = "FrontWall", Size = Vector3.new(sideW, 3, 1),
				CFrame = g(side * (doorW / 2 + sideW / 2), 2, d / 2), Color = CFG.WALL })
			shellPart(plot, { Name = "FrontGlass", Size = Vector3.new(sideW - 2, h - 7, 0.4),
				CFrame = g(side * (doorW / 2 + sideW / 2), (h - 7) / 2 + 3, d / 2),
				Color = Color3.fromRGB(150, 200, 220), Material = Enum.Material.Glass, Transparency = 0.45 })
			shellPart(plot, { Name = "SideGlass", Size = Vector3.new(0.4, h - 9, d - 6),
				CFrame = g(side * (w / 2 + 0.31), (h - 9) / 2 + 4, 0),
				Color = Color3.fromRGB(150, 200, 220), Material = Enum.Material.Glass, Transparency = 0.45 })
		end
		shellPart(plot, { Name = "EntranceHeader", Size = Vector3.new(w, 4, 1),
			CFrame = g(0, h - 2, d / 2), Color = CFG.TRIM })
		--[[
			INTERIOR. His verdict: "not just some garage-looking area, I want
			this to be a company building." Level 2+ reads as an office from
			inside: pale tile floor, ceiling light strips, four columns tucked
			to the walls (nothing in the buildable middle), and a LOGO WALL
			behind the founder's bench carrying the company name.
		]]
		local floor = plot.hq.shell[1]
		floor.Color = Color3.fromRGB(214, 212, 206)
		floor.Material = Enum.Material.SmoothPlastic
		for _, lx in ipairs({ -w / 2 + 3, w / 2 - 3 }) do
			for _, lz in ipairs({ -d / 2 + 3, d / 2 - 5 }) do
				shellPart(plot, { Name = "Column", Size = Vector3.new(1.6, h - 1, 1.6),
					CFrame = g(lx, (h - 1) / 2 + 0.5, lz), Color = Color3.fromRGB(226, 224, 220) })
			end
		end
		for k = 1, math.floor(d / 12) do
			shellPart(plot, { Name = "CeilingLight", Size = Vector3.new(w * 0.6, 0.3, 1.2),
				CFrame = g(0, h - 0.7, -d / 2 + k * 12 - 4), Color = Color3.fromRGB(255, 244, 222),
				Material = Enum.Material.Neon })
		end
		local logo = shellPart(plot, { Name = "LogoWall", Size = Vector3.new(math.min(w - 20, 30), 6, 0.6),
			CFrame = g(0, 8, -d / 2 + 0.8), Color = level >= 3 and Color3.fromRGB(38, 40, 48) or CFG.ACCENT,
			Material = level >= 3 and Enum.Material.SmoothPlastic or Enum.Material.SmoothPlastic })
		-- v3.0.3: painted ON the panel (SurfaceGui on its room-facing face), like every
		-- other sign. The old floating billboard slid behind the wall at an angle and
		-- clipped the company name ("faka" read "fak" from the lounge).
		do
			local sg = Instance.new("SurfaceGui")
			sg.Face = Enum.NormalId.Back
			sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			sg.PixelsPerStud = 16      -- TextScaled stops at 100 px; at 40 px/stud the name filled a third of the panel
			sg.LightInfluence = 0
			sg.MaxDistance = 120
			sg.Parent = logo
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Size = UDim2.new(0.9, 0, 0.62, 0)
			t.AnchorPoint = Vector2.new(0.5, 0.5)
			t.Position = UDim2.new(0.5, 0, 0.5, 0)
			t.TextScaled = true
			t.Font = Enum.Font.FredokaOne
			t.TextColor3 = level >= 3 and CFG.GOLD or Color3.new(1, 1, 1)
			t.Text = ""
			t.Parent = sg
			plot.logoTag = t
		end
		if level >= 3 then
			shellPart(plot, { Name = "Parapet", Size = Vector3.new(w + 2, 1.6, d + 2),
				CFrame = g(0, h + 0.8, 0), Color = CFG.WALL })
		end
		-- storey slabs every 12 studs: height reads as floors, and they are the
		-- floors CampusArch furnishes (v3.0.3: from level 3, whose 28-stud hall was one room)
		if level >= 3 then
			for y = 16, h - 6, 12 do
				shellPart(plot, { Name = "StoreyBand", Size = Vector3.new(w + 0.6, 1.2, d + 0.6),
					CFrame = g(0, y, 0), Color = CFG.TRIM })
			end
		end
		if level >= 4 then
			-- v3.5: was a 2x6x2 glowing Neon stick. Now a slim white mast; only the
			-- aviation light at its tip glows, which is what Neon is for (ART.md)
			shellPart(plot, { Name = "RoofBeacon", Size = Vector3.new(0.6, 8, 0.6),
				CFrame = g(0, h + 5.5, -d / 4), Color = Color3.fromRGB(243, 239, 230) })
			shellPart(plot, { Name = "RoofBeaconLight", Shape = Enum.PartType.Ball, Size = Vector3.new(1.1, 1.1, 1.1),
				CFrame = g(0, h + 9.9, -d / 4), Color = level >= 5 and CFG.GOLD or Color3.fromRGB(255, 96, 80), Material = Enum.Material.Neon })
		end
		-- v2.8: the same architecture as the wings (white, mullions, canopy, roof plant)
		if CampusArch then
			local ok, err = pcall(CampusArch.dressHQ, function(props) return shellPart(plot, props) end, g, level, w, d, h, plot.hq.shell, plot)
			if not ok then warn("[SV] dressHQ failed: " .. tostring(err)) end
		end
	end

	-- v3.6: the Blender architecture (PLAN v6 V3) when imported; the parts above stay as collision
	if CampusArch and CampusArch.skinHQ then
		local ok, err = pcall(CampusArch.skinHQ, plot, level, w, d, h, plot.garage)
		if not ok then warn("[SV] skinHQ failed: " .. tostring(err)) end
	end

	if animate then
		local movers = {}
		for _, p in ipairs(plot.hq.shell) do
			if p.Name ~= "GarageFloor" then table.insert(movers, p) end
		end
		rise(movers, h + 6, 1.1)
	end
	-- refreshSign is defined later; buildShell is called from tryUpgrade and
	-- load, both of which call refreshSign themselves
end

-- the six wing lots. v3.2: each is a construction site (CampusArch.lot: gravel,
-- hoarding, a gate sign, a crane while you can build) instead of a square pad
-- with gold dashed edges. Idempotent: called on construction and on release.
local function buildSlots(plot)
	if plot.slotFolder then plot.slotFolder:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = "Slots"
	folder.Parent = plot.folder
	plot.slotFolder = folder
	plot.slots = {}
	plot.lotKey = nil

	for i, off in ipairs(SLOT_LOCAL) do
		local cf = plot.pivot * (typeof(off) == "CFrame" and off or CFrame.new(off))
		local pad, t
		if CampusArch and CampusArch.lot then
			local ok, a1, a2 = pcall(CampusArch.lot, folder, cf, i, CFG.SLOT_W, CFG.SLOT_D)
			if ok then pad, t = a1, a2 else warn("[SV] lot " .. i .. " failed: " .. tostring(a1)) end
		end
		if not pad then
			pad = part({ Name = "Slot" .. i, Size = Vector3.new(CFG.SLOT_W, 0.4, CFG.SLOT_D), CFrame = cf * CFrame.new(0, 0.2, 0),
				Color = Color3.fromRGB(120, 118, 116), Material = Enum.Material.Concrete }, folder)
			t = label(pad, "", 20, 3, 120)
		end
		local pp = prompt(pad, "BUILD", "Empty lot", 16)
		pp.Enabled = false
		local slot = { pad = pad, text = t, prompt = pp, cf = cf, built = nil, index = i }
		plot.slots[i] = slot
		local function openFor(player)
			if plotOf(player) ~= plot then return end
			if slot.built or not pp.Enabled then return end
			-- the picker shows THIS company's prices, not the base table
			local priced = {}
			for k, r in ipairs(CFG.ROOMS) do
				local sess = sessions[player.UserId]
				priced[k] = { id = r.id, name = r.name, blurb = r.blurb, cost = wingCostOf(r, plot, sess and sess.rate),
					color = r.color, accent = r.accent }
			end
			openBuild:FireClient(player, i, priced)
		end
		pp.Triggered:Connect(openFor)
		alsoClickable(pad, 20, openFor)
	end
end

-- the garage contents, the apron and the path. Built ONCE per plot.
local function buildPlot(index, def)
	local plot = {
		index = index, pivot = def.pivot, owner = nil,
		hq = { level = 1, shell = {} }, doorOpened = false,
	}
	plot.g = function(x, y, z) return def.pivot * CFrame.new(x, y, z) end
	local g = plot.g

	local folder = Instance.new("Folder")
	folder.Name = "Plot" .. index
	folder:SetAttribute("Pivot", def.pivot)
	folder.Parent = plotsFolder
	plot.folder = folder

	for _, n in ipairs({ "Garage", "Rooms", "Staff", "Placed" }) do
		local f = Instance.new("Folder")
		f.Name = n
		f.Parent = folder
		plot[string.lower(n)] = f
	end

	-- apron: top at 0.3, under the pads (0.4) and above the ground (0)
	local slab = part({ Name = "CampusSlab", Size = Vector3.new(220, 0.8, 170), CFrame = g(0, -0.1, -20),
		Color = Color3.fromRGB(148, 146, 142), Material = Enum.Material.Concrete, CanQuery = false }, folder)
	-- the path to the road: from the widest HQ front (local z 26) to the kerb
	local path = part({ Name = "Path", Size = Vector3.new(12, 0.5, 92), CFrame = g(0, 0.35, 74),
		Color = Color3.fromRGB(168, 164, 150), Material = Enum.Material.Concrete, CanQuery = false }, folder)
	-- v2.8: the apron becomes a campus (lawns, Kenney trees, benches, monument)
	if CampusArch then
		local ok, tag = pcall(CampusArch.grounds, folder, def.pivot, slab, path, index * 31)
		if ok then plot.monumentTag = tag else warn("[SV] grounds failed: " .. tostring(tag)) end
	end

	--[[ A plot pours its own paving and plants its own lawn, which is new
		ground the world-build placement pass never saw. Re-run it over this
		plot so a campus tree cannot end up standing in the forecourt it was
		planted next to. ]]
	do
		local Place = tryRequire(ServerScriptService, "Placement")
		if Place and Place.pass then
			local okP, _, before, pits, moved, gone, left = pcall(Place.pass, folder, { folder })
			if okP and (before or 0) > 0 then
				print(("[SV] placement %s: %d in paving -> %d pits, %d moved, %d removed | %d left")
					:format(folder.Name, before, pits, moved, gone, left))
			end
		end
		if Pal then
			local n = Pal.enforce(folder)
			if n > 0 then print(("[SV] palette %s: re-tinted %d parts"):format(folder.Name, n)) end
		end
	end

	buildShell(plot, 1, false)
	if Econ and Econ.WAFERS then
		plot.slots = {}
		Econ.Wafers.stateOf(plot)   -- v4.6: the building grows round the garage
	else
		buildSlots(plot)
	end

	local garage = plot.garage
	-- y 3.0 not 2.5: at 2.5 its base was 0.50 and the floor top is 1.00, so it
	-- stood half a stud inside the floor (measured 5 Oct)
	part({ Name = "Shelf", Size = Vector3.new(6, 4, 1.2), CFrame = g(-14, 3.0, -13.5),
		Color = Color3.fromRGB(120, 92, 60), Material = Enum.Material.WoodPlanks }, garage)
	part({ Name = "Boxes", Size = Vector3.new(3, 3, 3), CFrame = g(14.5, 2, -13),
		Color = Color3.fromRGB(150, 118, 80), Material = Enum.Material.Cardboard }, garage)
	local desk = part({ Name = "Desk", Size = Vector3.new(7, 0.4, 3.4), CFrame = g(0, 3.2, -9),
		Color = Color3.fromRGB(150, 120, 86), Material = Enum.Material.WoodPlanks }, garage)
	part({ Name = "DeskLegL", Size = Vector3.new(0.4, 3, 0.4), CFrame = g(-3, 1.5, -9), Color = CFG.TRIM }, garage)
	part({ Name = "DeskLegR", Size = Vector3.new(0.4, 3, 0.4), CFrame = g(3, 1.5, -9), Color = CFG.TRIM }, garage)
	local laptop = part({ Name = "Laptop", Size = Vector3.new(2.6, 0.15, 1.8), CFrame = g(0, 3.5, -9),
		Color = Color3.fromRGB(60, 64, 74), Material = Enum.Material.Metal }, garage)
	local screen = part({ Name = "Screen", Size = Vector3.new(2.6, 1.7, 0.12),
		CFrame = g(0, 4.35, -9.8) * CFrame.Angles(math.rad(-15), 0, 0),
		Color = CFG.ACCENT, Material = Enum.Material.Neon }, garage)
	part({ Name = "Chair", Size = Vector3.new(2, 1.0, 2),
		CFrame = g(4.6, 1.5, -6.0) * CFrame.Angles(0, math.rad(-28), 0), Color = CFG.TRIM }, garage)
	part({ Name = "ChairBack", Size = Vector3.new(2, 1.8, 0.3),
		CFrame = g(4.6, 2.9, -5.15) * CFrame.Angles(0, math.rad(-28), 0), Color = CFG.TRIM }, garage)

	if FurnitureKit then
		local swapped = { desk = desk, laptop = laptop }
		FurnitureKit.dressGarage(garage, g, swapped)
		desk, laptop = swapped.desk, swapped.laptop
		-- the kit lays the lit panel flush on the laptop's own screen and hands
		-- it back; that part is what writeCode() flashes from here on
		if swapped.screen then screen = swapped.screen end

		--[[ NO OUTLINE ON THE GARAGE FURNITURE, and it is not for want of trying.
			Measured 5 Oct: a Highlight on these imported furniture meshes does not
			render, adorning the MeshPart or a Model wrapped round it, at nine studs,
			in pure red with DepthMode AlwaysOnTop, with every other Highlight in the
			world destroyed. The same Highlight settings on a staff rig draw fine.
			The cause is not the count (13 in the world), the adornee, the parenting,
			the transparency or the depth mode -- all ruled out by experiment. Left
			unexplained rather than papered over with structure that does nothing. ]]
	end
	plot.desk, plot.laptop, plot.screen = desk, laptop, screen

	-- the workbench as placement surfaces, in WORLD coordinates for this plot
	plot.fixed = {}
	for _, lx in ipairs({ -2.16, 2.16 }) do
		local wp = def.pivot:PointToWorldSpace(Vector3.new(lx, 0, -9))
		table.insert(plot.fixed, { key = "desk", x = wp.X, z = wp.Z, w = 4.32, d = 2.31, top = 2.26, y = 1.0 })
	end

	--[[ CFG.TRIM is near-black, and on a dark garage floor a 7x7 charcoal slab
		does not read as a pad, it reads as a HOLE. Pale paving with a painted
		look says "stand here" instead. ]]
	plot.hirePad = part({ Name = "HirePad", Size = Vector3.new(7, 0.3, 7), CFrame = g(-11, 1.15, 4),
		Color = Color3.fromRGB(206, 201, 190), Material = Enum.Material.SmoothPlastic }, garage)
	plot.hireLabel = label(plot.hirePad, "", 20, 3, 34)

	--[[ NOT NEON. Reported 5 Oct as "a yellow blob through the wall", and that
		is exactly what a 6x6 Neon slab becomes once bloom gets hold of it at
		three studs: the halo is screen-space, so it spills past the garage wall
		and loses its own edges. ART.md already says Neon is for lights and
		screens only, and v3.5 took the IPO roof plate off Neon for this same
		reason. Painted gold keeps the colour and gets its shape back. ]]
	plot.hqPad = part({ Name = "HQPad", Size = Vector3.new(6, 0.4, 6), CFrame = g(13, 1.2, 8),
		Color = CFG.GOLD, Material = Enum.Material.SmoothPlastic }, garage)
	plot.hqLabel = label(plot.hqPad, "", 18, 3, 34)

	local bulb = part({ Name = "Bulb", Size = Vector3.new(1.6, 0.3, 1.6), CFrame = g(0, 13.2, -8),
		Color = Color3.fromRGB(255, 232, 190), Material = Enum.Material.Neon }, garage)
	local pl = Instance.new("PointLight")
	pl.Range = 26
	pl.Brightness = 1.6
	pl.Color = Color3.fromRGB(255, 226, 180)
	pl.Parent = bulb

	local sp = Instance.new("SpawnLocation")
	sp.Name = "Spawn"
	sp.Size = Vector3.new(6, 1, 6)
	-- z=0, not 6: the default camera sits ~12.5 studs behind the character,
	-- and from z=6 that is OUTSIDE the closed door (door at z=15). Seen live:
	-- the first frame after the intro was diamond plate with a slit.
	sp.CFrame = g(0, 1.5, 0)        -- 1.1 put its base at 0.60, inside the 1.00 floor
	sp.Transparency = 1
	sp.CanCollide = false
	sp.Anchored = true
	sp.Neutral = false          -- nobody lands here by chance; RespawnLocation targets it
	sp.Duration = 0             -- v3.1: the default 10 s force-field bubble covered the laptop on the first frame
	sp.Parent = garage
	plot.spawn = sp

	return plot
end

-- ============ GAME LOGIC ============

-- what the plate says: company name if set, else the building's name.
-- Gold plate + ticker symbol once public.
local function refreshSign(plot)
	local s = plot.owner and sessions[plot.owner]
	if not plot.signTag then return end
	local L = CFG.HQ_LEVELS[plot.hq.level]
	if plot.logoTag and plot.logoTag.Parent then
		plot.logoTag.Text = (s and s.name) or ""
	end
	if plot.monumentTag then plot.monumentTag.Text = (s and s.name and s.name ~= "") and string.upper(s.name) or "" end
	if s and s.name and s.name ~= "" then
		if s.ipo then
			plot.signTag.Text = ("%s  ·  %s"):format(companyLabel(s), s.ticker or "")
			-- v3.5 (ART.md: Neon only for lights/screens): a painted gold plate, not a glowing bar
			plot.signPlate.Color = CFG.GOLD
			plot.signPlate.Material = Enum.Material.SmoothPlastic
		else
			plot.signTag.Text = companyLabel(s)
			plot.signPlate.Color = CFG.TRIM
			plot.signPlate.Material = Enum.Material.SmoothPlastic
		end
	else
		plot.signTag.Text = L.name
		plot.signPlate.Color = CFG.TRIM
		plot.signPlate.Material = Enum.Material.SmoothPlastic
	end
	-- v2.8: a charcoal plate with white letters on the white HQ (the cyan neon
	-- plate clashed with the new architecture); dark letters only on the gold IPO plate
	plot.signTag.TextColor3 = (s and s.ipo) and Color3.fromRGB(14, 17, 23) or Color3.fromRGB(244, 244, 240)
end

-- the launch boost: 1 + spike that decays linearly to 0 over LAUNCH_DURATION
local function boostOf(s)
	local l = s.launch
	if not l then return 1 end
	local t = os.clock() - l.t0
	if t >= l.duration then s.launch = nil return 1 end
	local remaining = 1 - t / l.duration
	if Econ and l.curve then remaining = Econ.curveAt(l.curve, remaining)
	elseif l.slow then remaining = math.sqrt(remaining) end
	return 1 + l.spike * remaining
end

local function recompute(player)
	local s = sessions[player.UserId]
	if not s then return end
	local plotW = Econ and Econ.WAFERS and plotOf(player)
	if plotW and plotW.wafer then   -- v4.6: the departments built ARE the studio / cafe / servers
		local e = Econ.Wafers.effects(plotW)
		s.quality, s.morale, s.compute, s.labs, s.board = e.quality, e.morale, e.compute, e.labs, e.board
	end
	local q = math.min(s.quality or 0, CFG.QUALITY_CAP)
	local mo = math.min(s.morale or 0, CFG.MORALE_CAP)
	local mult = (1 + q) * (1 + mo)
	-- v3.2.1 OFFICE VIBE: placed decor no longer adds +1% money (capped at 15%,
	-- and most items added nothing). It builds a star rating that makes rare
	-- hires likelier (FurnitureKit.vibe). Server-set, so the roll can trust it.
	if FurnitureKit and FurnitureKit.vibe then
		local keys = {}
		for _, e in ipairs(s.placed or {}) do keys[#keys + 1] = e.key end
		local pts = FurnitureKit.vibePoints(keys)
		local stars, luck = FurnitureKit.vibe(pts)
		if player:GetAttribute("VibePoints") ~= pts then player:SetAttribute("VibePoints", pts) end
		if player:GetAttribute("VibeStars") ~= stars then player:SetAttribute("VibeStars", stars) end
		if player:GetAttribute("VibeLuck") ~= luck then player:SetAttribute("VibeLuck", luck) end
	end
	-- v2.6.0 ROOM ECONOMY: only SEATED people earn (the waiting line earns 0),
	-- a seat in the room that fits your job pays x1.5, bigger stations are more
	-- efficient per seat, and everyone draws a wage by seniority (not talent)
	local base, wages, perRoom, perSeg = 0, 0, {}, {}
	for _, r in ipairs(s.rigs or {}) do
		if not (Econ and Econ.V3) then wages += Econ and Econ.wageOf(r.tier) or 0 end
		if r.seated then
			local v = CFG.TIER_RATE[r.tier or 1] * talentMultOf(r) * ((r.fit and Econ) and Econ.FIT_MULT or 1) * (r.eff or 1)
			base += v
			local roomKey = (r.dept and Econ and Econ.Wafers and Econ.Wafers.NAME[r.dept]) or r.room or "hq"
			perRoom[roomKey] = (perRoom[roomKey] or 0) + v
			if r.seg then perSeg[r.seg] = (perSeg[r.seg] or 0) + v end
		end
	end
	if #(s.rigs or {}) == 0 then base = s.staff * CFG.INTERN_RATE end   -- rigs missing (no StaffRig)
	local plot = plotOf(player)
	s.hqLevel = plot and plot.hq and plot.hq.level or 1
	local F = mult * hqMultOf(plot) * spinMultOf(s) * milestoneMultOf(s) * ((Econ and Econ.indexMult) and Econ.indexMult(s.index) or 1)
	local wageTotal = wages * hqMultOf(plot)
	s.wages = wageTotal
	s.rate = math.max(0, math.floor(base * F - wageTotal))   -- never negative: absence is never punished
	if Econ then
		for k, v in pairs(perRoom) do perRoom[k] = v * F end
		player:SetAttribute("IncomeRooms", Econ.breakdown(perRoom, wageTotal))
		if plotW and plotW.wafer then
			for k, v in pairs(perSeg) do perSeg[k] = v * F end
			pcall(Econ.Wafers.refreshSigns, plotW, perSeg, fmt)
		end
	end
	player:SetAttribute("Prestige", math.floor(spinMultOf(s) * milestoneMultOf(s) * ((Econ and Econ.indexMult) and Econ.indexMult(s.index) or 1) * 100 + 0.5) / 100)
	player:SetAttribute("Spinoffs", s.spinoffs or 0)
	-- THE HQ STYLE. The session owns it; the plot is what the mesh placer reads,
	-- so they are synced here, where both are in scope and which runs on every
	-- state change. HQPathChosen tells the client whether to offer the picker.
	if plot and Econ and Econ.Wafers then
		plot.hqPath = s.hqPath or plot.hqPath
		player:SetAttribute("HQPath", Econ.Wafers.pathOf(plot))
		player:SetAttribute("HQPathChosen", s.hqPath ~= nil)
	end
	-- the client shows catalog prices; tell it what to multiply them by
	local priceMult = hqMultOf(plot) * (1 + CFG.FURNITURE_INFLATION * #(s.placed or {})) * scaleOf(s)
	player:SetAttribute("PriceMult", math.floor(priceMult * 100 + 0.5) / 100)
	player:SetAttribute("IncomeRate", (Econ and Econ.V3) and 0 or (s.rate or 0))   -- v2.6.3 floor; v2.7.0 none
	if Econ and Econ.V3 then player:SetAttribute("EconV3", true) end
	if plot and plot.slots then
		for _, sl in ipairs(plot.slots) do if sl.built then refreshWingPrompt(sl, plot, s) end end
	end
end


local function titleOf(r)
	local role = r.rig and r.rig:GetAttribute("Role") or "engineer"
	local roleName = (StaffRig and StaffRig.ROLES[role] and StaffRig.ROLES[role].name) or "ENGINEER"
	local title = (CFG.TIER_TITLE[r.tier or 1] or "Intern") .. " " .. roleName:sub(1, 1) .. roleName:sub(2):lower()
	local t = CFG.TALENT[r.talent or 1]
	if t and (r.talent or 1) > 1 then title = title .. ("  ·  1/%d"):format(t.odds) end
	return title
end

local function capacityOf(player)
	local s = sessions[player.UserId]
	if s and Econ and Econ.WAFERS then   -- v4.6: the floors you built, up to the staff cap
		local plot = plotOf(player)
		return plot and plot.wafer and Econ.Wafers.capacity(plot) or 1
	end
	if s and Econ and Econ.V3 then
		local plot = plotOf(player)
		return plot and Econ.capacity(plot) or 1
	end
	return s and (CFG.GARAGE_DESKS + s.desks + (s.placedDesks or 0)) or 0
end

local function shipFirstProduct(player, plot)
	local s = sessions[player.UserId]
	if not s or s.shipped then return end
	s.shipped = true
	Telemetry.step(player, "first_ship")
	local g = plot.g
	local prod = part({ Name = "Product", Size = Vector3.new(1.6, 2.2, 0.2),
		CFrame = g(0, 3.9, -9), Color = CFG.GOOD, Material = Enum.Material.Neon }, plot.garage)
	local tag = label(prod, "TO-DO APP", 22, 2.2, 60)
	tag.TextColor3 = CFG.GOOD
	TweenService:Create(prod, TweenInfo.new(1.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ CFrame = g(0, 9.2, -9) }):Play()
	task.delay(2.6, function()
		TweenService:Create(prod, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		TweenService:Create(tag, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		task.delay(0.6, function() prod:Destroy() end)
	end)
	popup(plot.desk, "SHIPPED!", CFG.GOLD)
end

local function writeCode(player, plot)
	if plotOf(player) ~= plot then return end
	local s = sessions[player.UserId]
	local cash = cashOf(player)
	if not s or not cash then return end
	-- a prompt/click spammer fired this hundreds of times a second for $5 each
	if s.lastCode and os.clock() - s.lastCode < 0.35 then return end
	s.lastCode = os.clock()
	s.clicks += 1
	local brew = (Econ and Econ.Inv and Econ.Inv.codeMult(player)) or 1     -- v3.2: a Cold Brew runs x3
	-- v4.3: a tap is worth a slice of your income, and fast taps build a combo:
	-- the one active verb while you save up (CoreConfig CODE_SECONDS / CODE_COMBO_*)
	local tNow = os.clock()
	s.codeCombo = (s.lastCodeAt and tNow - s.lastCodeAt < 0.9) and math.min((s.codeCombo or 0) + 1, CFG.CODE_COMBO_MAX) or 0
	s.lastCodeAt = tNow
	local gain = math.floor(math.max(CFG.CODE_REWARD, (s.rate or 0) * CFG.CODE_SECONDS) * (1 + CFG.CODE_COMBO_STEP * s.codeCombo) * brew)
	cash.Value += gain
	player:SetAttribute("CodeCombo", s.codeCombo)
	player:SetAttribute("CodeGain", gain)
	player:SetAttribute("CodeTap", (player:GetAttribute("CodeTap") or 0) + 1)   -- what the HUD watches (a repeat gain still counts)
	Telemetry.step(player, "first_code")
	popup(plot.laptop, "+$" .. fmt(gain))
	plot.screen.Color = CFG.GOOD
	task.delay(0.12, function() plot.screen.Color = CFG.ACCENT end)
	if s.clicks == CFG.CLICKS_TO_SHIP then shipFirstProduct(player, plot) end
	-- v2.7.0 the active verb: every click after the first ship pushes the product bar
	if Econ and Econ.V3 and s.shipped and s.clicks > CFG.CLICKS_TO_SHIP and not s.pendingProduct then
		local team = 0
		for _, r in ipairs(s.rigs or {}) do team += CFG.TIER_RATE[r.tier or 1] end
		s.work = (s.work or 0) + math.max(1, team * Econ.CODE_WORK) * brew
	end
end

--[[
	EMPLOYEES SIT AT THE DESKS YOU PLACED. A hire without a desk is not a
	number on a pad: it is a person standing by the hire pad waiting for one.
	The first intern takes the second bench desk in the garage; every hire
	after that is seated at your placed desks in the order you placed them.
	Delete a desk and its occupant walks back to the waiting line. This is what
	makes "desks = capacity" visible instead of abstract.
]]
--[[ v2.5.1 OFFICE SEATS. Capacity counted the office's desks (2 on build,
	+2 per level) but nothing gave those desks a seat, so hires stood in the
	waiting line forever and never promoted (seniority only runs seated).
	Measured 18 Sep: capacity 3, staff 3, "2 WAITING FOR A DESK". Every
	office desk now has a workstation in the room and a seat in front of it. ]]
local officeSeat, officeDesk
do
local OFFICE_DESKS = {
	{ -4.5, -8.6 }, { 4.5, -8.6 },                              -- the starters (FurnitureKit.dressRoom)
	{ -8, -1.5 }, { -2.7, -1.5 }, { 2.7, -1.5 }, { 8, -1.5 },    -- levels 2-3
	{ -8, 4.5 }, { -2.7, 4.5 }, { 2.7, 4.5 }, { 8, 4.5 },        -- levels 4-5
}
officeSeat = function(slot, k)
	local d = OFFICE_DESKS[k]
	if not d then return nil end
	local c = slot.cf * CFrame.new(d[1], 0, d[2]) * CFrame.new(0.3, 0, 2.6)
	return CFrame.new(c.Position.X, 3.4, c.Position.Z) * (c - c.Position)
end
officeDesk = function(slot, k)
	-- a real workstation for level-up desks (the first two are dressed by FurnitureKit)
	local d = OFFICE_DESKS[k]
	if not d or k <= 2 or not slot.model or not FurnitureKit or not FurnitureKit.has("desk") then return end
	pcall(FurnitureKit.workstation, slot.cf, d[1], d[2], 1.0, slot.model, { yaw = 0, accent = slot.room and slot.room.accent })
end
end

local function deskHomes(s, plot)
	-- v2.6.0: every seat knows its ROOM and its station's efficiency
	-- the garage bench, right-hand desk: seat in front, looking at the desk
	local homes = { { cf = plot.g(2.46, 3.4, -6.4), room = "hq", eff = 1 } }
	if Econ and Econ.WAFERS and plot.wafer then   -- v4.6: the Wafers' desks and tables, floor by floor
		for _, seat in ipairs(Econ.Wafers.seats(plot)) do
			table.insert(homes, { cf = seat.cf, room = seat.room, eff = 1, seg = seat.seg, dept = seat.dept })
		end
		return homes
	end
	if Econ and Econ.V3 then
		-- v2.7.0: rooms come furnished; placed furniture is decoration
		for _, slot in ipairs(plot.slots or {}) do
			if slot.built then
				for k = 1, Econ.roomSeats(slot.built, slot.level) do
					local seat
					if slot.built == "office" then
						seat = officeSeat(slot, k)
					else
						local x, z, lx, lz = Econ.seatSpot(slot.built, k)
						if x then
							local at = slot.cf * CFrame.new(x, 0, z)
							local look = slot.cf * CFrame.new(lx, 0, lz)
							seat = CFrame.lookAt(Vector3.new(at.X, 3.4, at.Z), Vector3.new(look.X, 3.4, look.Z))
						end
					end
					if seat then table.insert(homes, { cf = seat, room = slot.built, eff = 1 }) end
				end
			end
		end
		return homes
	end
	for _, slot in ipairs(plot.slots or {}) do
		if slot.built == "office" then
			for k = 1, 2 * (slot.level or 1) do
				local seat = officeSeat(slot, k)
				if seat then table.insert(homes, { cf = seat, room = "office", eff = 1 }) end
			end
		end
	end
	for _, e in ipairs(s.placed) do
		local st = Econ and Econ.STATIONS[e.key]
		if st then
			for _, cf in ipairs(Econ.seatsFor(e)) do
				table.insert(homes, { cf = cf, room = e.room or "hq", eff = st.eff })
			end
		end
	end
	return homes
end

local function assignDesks(player)
	local s = sessions[player.UserId]
	local plot = plotOf(player)
	if not s or not plot or not StaffRig then return end
	local homes = deskHomes(s, plot)
	local waiting = 0
	local used = {}
	for _, r in ipairs(s.rigs) do
		-- v2.6.0 ROLE FIT: take a free seat in a room that matches the job, else any free seat
		local role = r.rig and r.rig:GetAttribute("Role") or "engineer"
		local fitSet = (Econ and Econ.FIT[role]) or {}
		local pick
		for k, h in ipairs(homes) do if not used[k] and fitSet[h.room] then pick = k break end end
		if not pick then for k in ipairs(homes) do if not used[k] then pick = k break end end end
		local h = pick and homes[pick]
		if pick then used[pick] = true end
		local home = h and h.cf
		r.seated = home ~= nil
		r.room = h and h.room or nil
		r.fit = h and fitSet[h.room] or false
		r.eff = h and h.eff or 1
		r.seg = h and h.seg or nil      -- v4.6: which floor they sit on (its money sign)
		r.dept = h and h.dept or nil
		if StaffRig.setSeated then StaffRig.setSeated(r.rig, r.seated) end
		if not home then
			-- no desk: stand in a line beside the hire pad, facing the room
			home = plot.g(-15 + waiting * 3, 3.62, 9) * CFrame.Angles(0, math.rad(180), 0)   -- floor top 1.0 + root-to-sole 2.61
			waiting += 1
		end
		r.home = home        -- remembered so the tilt sweep can put a rig back exactly
		StaffRig.rehome(r.rig, home)
	end
	s.waitingStaff = waiting
	recompute(player)   -- v2.6.0: who sits where IS the income now
end

local function spawnStaff(player, plot, n, talent, who)
	if not StaffRig then return nil end
	local s = sessions[player.UserId]
	local roleKey = CFG.ROLE_ORDER[((n - 1) % #CFG.ROLE_ORDER) + 1]
	-- v3.0: a recruited candidate keeps the role and face you carried home
	-- (same StaffRig seed = same name, skin and hair)
	if who and who.role and who.seed then roleKey = who.role end
	local rig, hum = StaffRig.build(roleKey, (who and who.seed) or n)
	local home = plot.g(-15, 3.4, 9)
	rig:PivotTo(home)
	rig.Parent = plot.staff
	StaffRig.animate(rig, hum, home, Vector3.new(1.5, 0, 1.5))
	local entry = { rig = rig, hum = hum, tier = 1, seatedTime = 0, talent = talent or 1,
		who = (who and who.role and who.seed) and { role = who.role, seed = who.seed } or nil }
	-- v3.0 TALENT INDEX: every role x talent you have ever hired (25 entries)
	if s and Econ and Econ.publishIndex then
		s.index = s.index or {}
		local key = roleKey .. ":" .. (talent or 1)
		if not s.index[key] then
			s.index[key] = true
			if not s.indexQuiet then player:SetAttribute("IndexNew", (player:GetAttribute("IndexNew") or 0) + 1) end
			Econ.publishIndex(player, s)
		end
	end
	table.insert(s.rigs, entry)
	local t = CFG.TALENT[entry.talent]
	if t and t.color and StaffRig.setTalent then StaffRig.setTalent(rig, entry.talent, t.color, t.name) end
	StaffRig.setTitle(rig, titleOf(entry))
	assignDesks(player)
	return rig:FindFirstChild("UpperTorso") or rig.PrimaryPart
end

local function updateHirePad(player)
	local s = sessions[player.UserId]
	local plot = plotOf(player)
	if not s or not plot then return end
	local cap = capacityOf(player)
	--[[ PAD_OFF, not CFG.TRIM. TRIM is near-black, and a 7x7 near-black slab on a
		dark garage floor does not read as a dormant pad -- it reads as a hole in
		the floor, which is what it looked like in his 5 Oct screenshot. Pale
		stone reads as "a pad, not yet active". ]]
	local PAD_OFF = Color3.fromRGB(176, 172, 164)
	if not s.shipped then
		plot.hireLabel.Text = ""
		plot.hirePad.Color = PAD_OFF
	elseif s.staff >= cap then
		plot.hireLabel.Text = "SEATS FULL  ·  add a station (B) or upgrade a room"
		if Econ and Econ.V3 then
			local atCap = cap >= (Econ.CAP_BY_HQ[plot.hq.level] or 30)
			plot.hireLabel.Text = atCap and "TEAM FULL  ·  a bigger HQ fits more people" or "SEATS FULL  ·  build or upgrade a room"
		elseif (s.waitingStaff or 0) > 0 then
			plot.hireLabel.Text = ("%d WAITING FOR A SEAT  ·  add a station (B)"):format(s.waitingStaff)
		end
		plot.hirePad.Color = Color3.fromRGB(120, 90, 90)
	elseif s.staff == 0 then
		plot.hireLabel.Text = "HIRE YOUR FIRST INTERN  ·  FREE"
		plot.hirePad.Color = CFG.GOLD
	elseif Econ and Econ.RECRUIT and Econ.Drop then
		plot.hireLabel.Text = "HIRING HAPPENS ON THE STREET  ·  candidates wait on the sidewalk"
		plot.hirePad.Color = PAD_OFF
	else
		plot.hireLabel.Text = string.format("HIRE  ·  $%s  ·  rolls talent", fmt(hireCostOf(s, plot)))
		plot.hirePad.Color = CFG.GOLD
	end
	-- the HQ is not a verb until someone works here (it competed with the laptop at 0:00)
	if plot.hqPrompt then plot.hqPrompt.Enabled = s.staff >= 1 end
end

--[[
	ONBOARDING GUIDE (v1.3). Ghost Drivers' arrow: one objective at a time,
	the SERVER decides which, the client only draws. Published as three
	player attributes -- Objective (key), ObjectiveText, ObjectivePos
	(Vector3, world) -- because attributes cannot hold Instances and the
	client must not have to know plot internals. Derived from state every
	second (not event-wired) so it can never be stuck on a stale beat.
]]
local function posOf(x)   -- FurnitureKit swaps the laptop for a Model; a Model has no .Position
	if typeof(x) ~= "Instance" then return nil end
	if x:IsA("BasePart") then return x.Position end
	if x:IsA("Model") then return x:GetPivot().Position end
	return nil
end
-- v4.3 THE JOURNEY: the plain snapshot Journey.lua (pure, tested offline) decides from
local function journeyState(player, s, plot)
	s.jr = s.jr or {}
	s.tips = s.tips or {}
	s.tipAt = s.tipAt or (os.clock() - 10)
	local held = cashOf(player)
	local cash = held and held.Value or 0
	local lv = plot.hq.level
	local nxt = CFG.HQ_LEVELS[lv + 1]
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local desk = Econ and Econ.Apt and Econ.Apt.deskPosition and Econ.Apt.deskPosition()
	local nearRes = (root and desk and (root.Position - desk).Magnitude < 120) or false
	local seated = (Econ and Econ.Cars and Econ.Cars.driving and Econ.Cars.driving(player)) or false
	if seated then s.jr.drove = true end
	if nearRes then s.jr.res = true end
	local idx = 0
	for _ in pairs(s.index or {}) do idx += 1 end
	local items = player:GetAttribute("Items")
	local cap = capacityOf(player)
	local gen = Econ and Econ.Drop and Econ.Drop.candidate and Econ.Drop.candidate(player, "genius", cash)
	local aptNext
	do   -- the next home up (the guide suggests it only when a spin-off would lose people)
		local tier = Econ and Econ.Apt and Econ.Apt.TIERS and Econ.Apt.TIERS[(s.apt or 0) + 1]
		if tier then aptNext = { name = tier.name, price = Econ.Apt.priceOf(s, tier.id), slots = Prog.keepSlots(tier.id) } end
	end
	local wlevel, wcap, msLevel, msCost, atCap
	if Econ and Econ.WAFERS and plot.wafer then   -- v4.6
		local WP = Econ.Wafers.Plan
		wlevel, wcap = plot.wafer.level, WP.blueprint(s.spinoffs or 0)
		atCap = wlevel >= wcap
		for _, m in ipairs({ 5, 9, 13, 18 }) do if m > wlevel and not msLevel then msLevel = m end end
		if not msLevel or msLevel > wcap then msLevel = (not atCap) and wcap or nil end
		if msLevel then
			msCost = 0
			for L = wlevel + 1, msLevel do msCost += WP.price(L, scaleOf(s), s.record or 1) end
		end
	end
	return {
		level = wlevel, capLevel = wcap, msLevel = msLevel, msCost = msCost, atCap = atCap,
		touch = player:GetAttribute("Touch") == true,
		hq = lv, shipped = s.shipped == true, staff = s.staff or 0, cap = cap, cash = cash, rate = s.rate or 0,
		apt = s.apt or 0, listed = s.listed == true, spinCost = spinoffCostOf(s),
		nextMult = (string.format("%.1f", nextSpinMultOf(s)):gsub("%.0$", "")),
		nextHqCost = nxt and hqCostOf(s, lv + 1) or nil, nextHqName = nxt and nxt.name or nil,
		keepers = #Prog.rankKeepers(s.rigs, (Econ and Econ.KEEP_TALENT) or 3), keepSlots = Prog.keepSlots(s.apt),
		aptNext = aptNext,
		hasCar = (Econ and Econ.Cars and Econ.Cars.hasCar(player)) and true or false, seated = seated, nearRes = nearRes,
		vipStanding = (Econ and Econ.Drop and Econ.Drop.hasVip and Econ.Drop.hasVip(player)) or false,
		vipDone = (s.vipDay or 0) ~= 0, geniusAvailable = gen ~= nil and (s.staff or 0) < cap, geniusPos = gen and gen.pos or nil,
		geniusDone = s.jr.genius == true, seriesA = s.jr.seriesA == true,
		productReady = s.pendingProduct ~= nil, items = (type(items) == "string" and items ~= "") and 1 or 0,
		indexCount = idx, dailyReady = player:GetAttribute("DailyReady") == true,
		carrying = (Econ and Econ.Drop and Econ.Drop.carrying(player) ~= nil) or false,
		jr = s.jr, tips = s.tips,
	}
end
local function refreshObjective(player)
	--[[ v3.1 THE QUEST CARD. The guide used to send one string built from
	middle-dot clauses ("You can afford it!  Upgrade to GLASS TOWER  ·  $225.0K"),
	which truncated on phones and left the subtraction to a nine-year-old. Now it
	sends a short TITLE, a SUB line and the COST, and the client draws a goal
	meter (cash / cost) with the price in its own chip. "Tap" is swapped for
	"Click" on keyboards client-side. A ready product outranks everything but a
	carry: it is the one action with a clock on it. ]]
	local s = sessions[player.UserId]
	local plot = plotOf(player)
	if not s or not plot then return end
	local st = journeyState(player, s, plot)
	local key, text, pos, sub, cost
	if not s.shipped then
		key, text, pos = "code", "Write your first app", posOf(plot.laptop)
		sub = ("Tap the laptop  (%d of %d)"):format(math.min(s.clicks or 0, CFG.CLICKS_TO_SHIP), CFG.CLICKS_TO_SHIP)
	elseif s.staff < 1 then
		key, text, pos, sub = "hire", "Hire your first intern", posOf(plot.hirePad), "Step on the HIRE pad. It's free!"
	elseif not s.buildUnlocked then
		key, text, pos, sub = "watch", "Your intern is coding", nil, "Tap WRITE CODE to help"
	elseif Econ and Econ.Drop and Econ.Drop.carrying(player) then
		-- v3.0: walking a candidate home is the only thing that matters right now
		local c = Econ.Drop.carrying(player)
		local left = math.max(0, math.floor(c.deadline - workspace:GetServerTimeNow()))
		key, text, pos, sub = "carry", ("Bring %s home!"):format(c.name), posOf(plot.hqPad), ("%d seconds left"):format(left)
	elseif s.pendingProduct then
		key, text, pos, sub = "product", "Your app is ready!", nil, "Tap LAUNCH for a payday"
	else
		-- v4.3 THE JOURNEY: a story task (the car, the drive, the home, the VIP, the
		-- first Genius, the Series A, GO PUBLIC) beats the cheapest-next-buy guide
		local jt = Journey.task(st)
		if jt then
			local at
			-- v5: no world arrow for the car: the goal says "Tap CAR" (the button calls
			-- the car to you) and an arrow to the parked car 27 m away said otherwise
			if jt.target == "car" then at = nil
			elseif jt.target == "residences" then at = Econ and Econ.Apt and Econ.Apt.deskPosition and Econ.Apt.deskPosition()
			elseif jt.target == "vip" then at = Econ and Econ.Drop and Econ.Drop.vipPos and Econ.Drop.vipPos(player)
			elseif jt.target == "genius" then at = st.geniusPos
			elseif jt.target == "gopublic" then at = posOf(plot.hqPad)
			elseif jt.target == "lot" then
				for _, slot in ipairs(plot.slots) do
					if not slot.built then at = posOf(slot.pad) break end
				end
				at = at or posOf(plot.hqPad)
			end
			key, text, pos, sub = jt.key, jt.title, at, jt.sub
			-- 12 s after a level-up: the investor's text must not land on the level-up banner
			if jt.key == "seriesa" and Econ and Econ.Phone and Econ.Phone.seriesA and os.clock() - (s.seriesAt or -1e9) > 90
				and os.clock() - (plot.hqUpAt or -1e9) > 12 then
				s.seriesAt = os.clock()
				task.spawn(Econ.Phone.seriesA, player)
			end
		else
		local empty
		local built = 0
		for _, slot in ipairs(plot.slots) do
			if slot.built then built += 1 elseif not empty then empty = slot end
		end
		local cap = capacityOf(player)
		local nxtHq = CFG.HQ_LEVELS[plot.hq.level + 1]
		local nxtCost = nxtHq and hqCostOf(s, plot.hq.level + 1)
		local wTease
		if Econ and Econ.WAFERS and plot.wafer then   -- v4.6: the next floor (or rebuilt storey)
			local L, last, price = wafersNext(s, plot)
			nxtHq, nxtCost = nil, nil
			if L then
				local rec = player:GetAttribute("WaferRec")
				local name = (last > L) and ("levels %d-%d"):format(L, last)
					or (rec and rec ~= "" and ("level %d: %s"):format(L, Econ.Wafers.NAME[rec] or rec)) or ("level %d"):format(L)
				nxtHq = { name = name }
				nxtCost = price
				wTease = (last > L) and "Rebuild a whole storey in one tap" or (rec and Econ.Wafers.BLURB[rec]) or "A new piece of your HQ"
			end
		end
		local upWing
		for _, slot in ipairs(plot.slots) do
			if slot.built and not wingMaxed(s, slot) then upWing = slot break end
		end
		-- what the next HQ level unlocks: the reason to save for it
		local function hqTease()
			if not nxtHq then return nil end
			if wTease then return wTease end
			for _, tier in ipairs(Econ and Econ.RECRUIT and Econ.TIERS or {}) do
				if tier.hq == plot.hq.level + 1 then return ("Unlocks %s hires"):format(tier.name) end
			end
			local capN = Econ and Econ.CAP_BY_HQ and Econ.CAP_BY_HQ[plot.hq.level + 1]
			return capN and ("Room for %d staff"):format(capN) or nil
		end
		if built == 0 and empty then
			local r = CFG.ROOM_BY_ID.office
			key, text, pos, sub = "build", "Build an Open Office", posOf(empty.pad), "Walk to your empty lot"
			cost = r and wingCostOf(r, plot, s.rate) or nil
		else
			-- v2.5.1: the guide points at the CHEAPEST next purchase (the Airport
			-- Tycoon "next buy" ghost). A ladder of fixed priorities sent a player
			-- holding $5 with a $40 hire open to a $2,500 HQ.
			local best
			local function offer(c, k, t, at, sb)
				if c and (not best or c < best.c) then best = { c = c, k = k, t = t, at = at, sub = sb } end
			end
			if Econ and Econ.V3 then
				-- v2.7.0: rooms are furnished; no station step. Hire, build, level, HQ.
				s.guideRecruit = nil
				if s.staff < cap then
					local hc = hireCostOf(s, plot)
					-- v3.0: ranked at the walk-in fee (the sim's rule), pointed at the best
					-- candidate standing that you can afford
					local cand = Econ.Drop and Econ.Drop.bestFor(player, (cashOf(player) or { Value = 0 }).Value)
					if cand then
						offer(hc, "recruit", ("Recruit a %s hire"):format(cand.tier.name), cand.pos, "They wait on the sidewalk")
						best.cost = cand.fee
						s.guideRecruit = { c = hc, k = "recruit", t = ("Recruit a %s hire"):format(cand.tier.name), at = cand.pos,
							sub = "They wait on the sidewalk", cost = cand.fee }
					elseif not (Econ.RECRUIT and Econ.Drop) then
						offer(hc, "hire2", "Hire someone new", posOf(plot.hirePad), "Every hire could be rare")
						best.cost = hc
					end
				end
			elseif s.staff >= cap then
				-- v2.6.0: point at the room that still has station space, with its station
				local rid, sidx = nil, nil
				if Econ then rid, sidx = Econ.roomWithSpace(plot, s.placed, plot.hq.level) end
				if rid then
					local fkey = (rid == "cafe" and "tableRound") or (rid == "studio" and "tableCross") or "desk"
					local item = FurnitureKit and FurnitureKit.BY_KEY and FurnitureKit.BY_KEY[fkey]
					local dc = item and furniturePriceOf(item, s, plot) or 0
					offer(dc, "desk", "Seats are full", posOf(sidx and plot.slots[sidx].pad or plot.hqPad), Econ.STATION_HINT[rid] or "Place a station")
				end
			else
				local hc = hireCostOf(s, plot)
				offer(hc, "hire2", "Hire someone new", posOf(plot.hirePad), "Every hire could be rare")
			end
			-- v3.2.1: DECOR has a job now (Vibe -> rare hires), so the guide teaches it
			-- until the first star. Not as "the cheapest buy": a plant costs 15 s of
			-- income and a room is a fixed price, so decor never won that race.
			local decorOffer
			if Econ and Econ.V3 and plot.hq.level >= 2 and (player:GetAttribute("VibeStars") or 0) < 1 then
				local plant = FurnitureKit and FurnitureKit.BY_KEY and FurnitureKit.BY_KEY.pottedPlant
				if plant then decorOffer = { c = furniturePriceOf(plant, s, plot), k = "decor", t = "Decorate your office", at = nil, sub = "Tap DECOR: nicer office, rarer hires" } end
			end
			if nxtHq then
				offer(nxtCost, "hq", ((Econ and Econ.WAFERS) and "Build %s" or "Upgrade to %s"):format(nxtHq.name), posOf(plot.hqPad), hqTease())
			else
				offer(spinoffCostOf(s), "spin", "Spin off", posOf(plot.hqPad), ("Start a new company: x%s money"):format((string.format("%.1f", nextSpinMultOf(s))):gsub("%.0$", "")))
			end
			if empty and Econ and Econ.V3 then
				if built < (Econ.SLOTS_BY_HQ[plot.hq.level] or 6) then
					local r = CFG.ROOM_BY_ID[Econ.nextRoom(plot)]
					local wc = wingCostOf(r, plot, s.rate)
					offer(wc, "wing", ("Build %s %s"):format((r.name:match("^[AEIOU]") and "an" or "a"), (r.name:lower():gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end))), posOf(empty.pad), r.blurb)
				end
			elseif empty then
				local cheapest = math.huge
				for _, r in ipairs(CFG.ROOMS) do cheapest = math.min(cheapest, wingCostOf(r, plot, s.rate)) end
				offer(cheapest, "wing", "Build another building", posOf(empty.pad), "Walk to an empty lot")
			end
			if upWing then
				local uc = wingUpgradeCostOf(upWing.room, upWing.level or 1, plot, s.rate)
				offer(uc, "wingup", ("Upgrade your %s"):format(upWing.room and upWing.room.name or "building"), posOf(upWing.header or upWing.pad), "Tap its front door")
			end
			-- v2.6.3: holding enough for the next HQ beats "the cheapest thing".
			-- A player on $3.4M at HQ 1 was being sent to a $350 wing.
			local held = cashOf(player)
			-- v2.8 ROOMS FIRST: a new building is the most visible progress there
			-- is, and "cheapest" never picked it (a room is never the cheapest
			-- thing). Clean-run bot: 2 rooms by minute 10 with $110K unspent.
			if empty and Econ and Econ.V3 and held and built < (Econ.SLOTS_BY_HQ[plot.hq.level] or 6) then
				local r = CFG.ROOM_BY_ID[Econ.nextRoom(plot)]
				local wc = wingCostOf(r, plot, s.rate)
				if held.Value >= wc then
					best = { c = wc, k = "wing", t = ("Build %s %s"):format((r.name:match("^[AEIOU]") and "an" or "a"), (r.name:lower():gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end))), at = posOf(empty.pad), sub = r.blurb, roomsFirst = true }
				end
			end
			if nxtHq and held and held.Value >= nxtCost then
				best = { c = nxtCost, k = "hq", t = ((Econ and Econ.WAFERS) and "Build %s" or "Upgrade to %s"):format(nxtHq.name), at = posOf(plot.hqPad), sub = hqTease() }
			elseif nxtHq and held and Econ and Econ.V3 and (s.rate or 0) > 0 and not (best and best.roomsFirst)
				and (nxtCost - held.Value) / s.rate <= Econ.SAVE_WINDOW then
				-- v2.7.0: the big goal is close; stop spending on small things (the old guide never saved)
				best = { c = nxtCost, k = "hq", t = ("Save up for %s"):format(nxtHq.name), at = posOf(plot.hqPad), sub = hqTease() }
			end
			-- v2.8: at HQ 5 the spin-off is the big goal, with the same afford / save-up treatment
			if not nxtHq and held and Econ and Econ.V3 then
				local sc = spinoffCostOf(s)
				local why = ("Start a new company: x%s money"):format((string.format("%.1f", nextSpinMultOf(s))):gsub("%.0$", ""))
				if held.Value >= sc then
					best = { c = sc, k = "spin", t = "Spin off!", at = posOf(plot.hqPad), sub = why }
				elseif (s.rate or 0) > 0 and (sc - held.Value) / s.rate <= Econ.SAVE_WINDOW then
					best = { c = sc, k = "spin", t = "Save up to spin off", at = posOf(plot.hqPad), sub = why }
				end
			end
			-- a new building, the HQ and the spin-off stay first; otherwise, once you
			-- can afford a plant, the guide shows what DECOR is for
			-- (two minutes per session at most: a player who does not care is not nagged)
			if decorOffer and held and held.Value >= decorOffer.c and os.clock() < (s.decorTeachEnd or math.huge)
				and not (best and (best.roomsFirst or best.k == "hq" or best.k == "spin")) then
				s.decorTeachEnd = s.decorTeachEnd or (os.clock() + 120)
				best = decorOffer
			end
			if not best then best = { k = "wait", t = "Write code", at = nil, sub = "Tap WRITE CODE for cash" } end
			key, text, pos, sub, cost = best.k, best.t, best.at, best.sub, best.cost or best.c
		end
		end
	end
	-- v4.3: the BIG goal is always on screen (under the quest card), and one HUD
	-- tip at a time explains a button the first time it matters
	local m = Journey.milestone(st)
	-- v4.4: when the quest card IS the big goal (spin off / go public / the HQ
	-- upgrade itself), the big card hides instead of repeating it
	if Journey.sameStep(key, m) then m = {} end
	if player:GetAttribute("MilestoneTitle") ~= m.title then player:SetAttribute("MilestoneTitle", m.title) end
	if player:GetAttribute("MilestoneSub") ~= m.sub then player:SetAttribute("MilestoneSub", m.sub) end
	local mc = m.cost and math.floor(m.cost) or nil
	if player:GetAttribute("MilestoneCost") ~= mc then player:SetAttribute("MilestoneCost", mc) end
	if player:GetAttribute("MilestoneUnlock") ~= m.unlock then player:SetAttribute("MilestoneUnlock", m.unlock) end
	local tip = Journey.tip(st)
	local tipId = (tip and (player:GetAttribute("CoachTip") == tip.id or os.clock() - s.tipAt > 25)) and tip.id or nil
	if player:GetAttribute("CoachTip") ~= tipId then
		-- the words ride along (Journey lives on the server); the id goes last, it is what the client watches
		player:SetAttribute("CoachTitle", tipId and tip.title or nil)
		player:SetAttribute("CoachBody", tipId and tip.body or nil)
		player:SetAttribute("CoachTarget", tipId and tip.target or nil)
		player:SetAttribute("CoachTip", tipId)
	end
	local canIpo = plot.hq.level >= #CFG.HQ_LEVELS and not s.listed
	if Econ and Econ.WAFERS and plot.wafer then canIpo = plot.wafer.level >= Econ.Wafers.Plan.blueprint(s.spinoffs or 0) and not s.listed end
	if player:GetAttribute("CanGoPublic") ~= canIpo then player:SetAttribute("CanGoPublic", canIpo) end
	local res = s.jr.res == true or (s.apt or 0) > 0
	if player:GetAttribute("JrRes") ~= res then player:SetAttribute("JrRes", res) end
	-- clients hide verbs that do not exist yet (BUILD button, product bar)
	if player:GetAttribute("Shipped") ~= (s.shipped == true) then player:SetAttribute("Shipped", s.shipped == true) end
	if player:GetAttribute("BuildOpen") ~= (s.buildUnlocked == true) then player:SetAttribute("BuildOpen", s.buildUnlocked == true) end
	if player:GetAttribute("HQLevel") ~= plot.hq.level then player:SetAttribute("HQLevel", plot.hq.level) end   -- v3.1: DECOR unlocks at HQ 2
	if CampusArch and CampusArch.lotState then   -- v3.2: every empty lot's gate sign and crane
		pcall(CampusArch.lotState, plot, s.buildUnlocked == true, (Econ and Econ.V3 and Econ.SLOTS_BY_HQ[plot.hq.level]) or 6, plot.hq.level + 1)
	end
	if player:GetAttribute("Objective") ~= key then player:SetAttribute("Objective", key) end
	if player:GetAttribute("ObjectiveText") ~= text then player:SetAttribute("ObjectiveText", text) end
	if player:GetAttribute("ObjectivePos") ~= pos then player:SetAttribute("ObjectivePos", pos) end
	if player:GetAttribute("ObjectiveSub") ~= sub then player:SetAttribute("ObjectiveSub", sub) end
	cost = cost and math.floor(cost) or nil
	if player:GetAttribute("ObjectiveCost") ~= cost then player:SetAttribute("ObjectiveCost", cost) end
end

-- v4.3: a HUD tip was read (GOT IT, or the button it points at was used)
coachSeen.OnServerEvent:Connect(function(player, id)
	local s = sessions[player.UserId]
	if not s or type(id) ~= "string" or not Journey.tipById(id) then return end
	s.tips = s.tips or {}
	s.tips[id] = true
	s.tipAt = os.clock()
	player:SetAttribute("CoachTip", nil)
end)

-- v3.0: `recruit` = { floor, fee } when a Talent Row candidate reaches your
-- door (TalentDrop). The pad itself only hires the free first intern; every
-- hire after that is a recruit run. Returns true when someone was hired.
--[[ Forward-declared because hire() has to redraw the HQ pad the moment it
	awards momentum -- the price on that sign just changed. Same pattern this
	file already uses for refreshFacade and spinOff. ]]
local refreshHqPad

local function hire(player, plot, recruit)
	if plotOf(player) ~= plot then return false end
	local s = sessions[player.UserId]
	local cash = cashOf(player)
	if not s or not cash or not s.shipped then return false end
	if not recruit and s.staff >= 1 and Econ and Econ.RECRUIT and Econ.Drop then
		popup(plot.hirePad, "Recruit on the street  ·  candidates wait on the sidewalk", CFG.ACCENT)
		return false
	end
	if s.staff >= capacityOf(player) then
		popup(plot.hirePad, "No desks free", CFG.BAD)
		return false
	end
	local cost = recruit and recruit.fee or ((s.staff == 0) and 0 or hireCostOf(s, plot))
	if cash.Value < cost then
		popup(plot.hirePad, "Need $" .. fmt(cost), CFG.BAD)
		return false
	end
	cash.Value -= cost
	s.lastBuy = os.clock()
	s.staff += 1
	if cost > 0 then s.hireCost = math.floor(s.hireCost * hireGrowthAt(s.staff)) end
	Telemetry.step(player, "first_hire")
	local talent = (cost == 0) and 1 or CFG.TALENT.roll((player:GetAttribute("VibeLuck") or 1) * (recruit and recruit.luck or 1))   -- v3.2.1 vibe x v4.2 a Penthouse VIP
	if recruit then talent = math.max(talent, recruit.floor or 1) end   -- the tier they wore is a floor
	if recruit and (recruit.floor or 1) >= 4 then s.jr = s.jr or {}; s.jr.genius = true end   -- v4.3 the HQ 3 task
	if cost > 0 and Econ and Econ.Inv then talent = Econ.Inv.onHire(player, talent) end   -- v3.2: a Scout Report
	local indexBefore = 0
	for _ in pairs(s.index or {}) do indexBefore += 1 end
	local torso = spawnStaff(player, plot, s.staff, talent, recruit)
	local indexAfter = 0
	for _ in pairs(s.index or {}) do indexAfter += 1 end
	recompute(player)
	local t = CFG.TALENT[talent]
	if talent > 1 then
		-- v3.0: a recruited floor is a signing, not luck; only a roll ABOVE the floor says "1 in N"
		local lucky = not (recruit and talent <= (recruit.floor or 1))
		-- v3.1: the numbers live on the reveal card; the world marker just names it (say it once)
		popup(torso or plot.hirePad, t.name:upper() .. "!", t.color or CFG.GOLD)
		local r = s.rigs[#s.rigs]
		if r then
			talentReveal:FireClient(player, {
				tier = talent, name = t.name, odds = t.odds, mult = t.mult,
				color = { t.color.R, t.color.G, t.color.B },
				who = r.rig:GetAttribute("PersonName") or r.rig.Name:gsub("^Staff_", ""),
				role = (r.rig:GetAttribute("Role") or "engineer"):upper(),
				signed = not lucky,
				rig = r.rig,                                   -- v3.1: the card shows THIS person (a live portrait)
				newIndex = indexAfter > indexBefore, indexCount = indexAfter,
			})
			local head = r.rig:FindFirstChild("Head")
			if head then
				local pe = Instance.new("ParticleEmitter")
				pe.Color = ColorSequence.new(t.color)
				pe.LightEmission = 0.8
				pe.Size = NumberSequence.new(0.35, 0)
				pe.Speed = NumberRange.new(8, 14)
				pe.SpreadAngle = Vector2.new(180, 180)
				pe.Lifetime = NumberRange.new(0.6, 1.1)
				pe.Rate = 0
				pe.Parent = head
				pe:Emit(20 * talent)
				task.delay(2, function() pe:Destroy() end)
			end
		end
		if r and StaffRig then StaffRig.say(r.rig, lucky and ("I'm a %s. You got lucky."):format(t.name) or "Glad to be here. Let's build.", 4) end
		if talent >= 4 then   -- Genius+ is announced to the whole server
			local who = r and r.rig:GetAttribute("PersonName") or "someone"
			-- everyone else hears about it; the hirer already has the reveal
			for _, other in ipairs(Players:GetPlayers()) do
				if other ~= player then toast:FireClient(other, ("%s just hired a %s: %s!"):format(player.DisplayName, t.name:upper(), who), "news") end
			end
		end
	else
		popup(torso or plot.hirePad, (cost == 0) and "INTERN HIRED" or ("HIRED  -$" .. fmt(cost)), CFG.GOOD)
	end
	--[[ v5.0 MOMENTUM. Only a hire that WALKED IN pays -- recruit.kind is set
		by TalentDrop when a carry reaches your lot. The free intern off the
		pad and any internal rehire pay nothing, because the whole point is to
		reward the trip, not the transaction. ]]
	if recruit and recruit.kind then
		local before = s.momentum or 0
		-- the roll outranks the tier: a Unicorn carried home is the best trip
		-- there is, and the award table would otherwise never reach its top row
		s.momentum = Mom.add(before, (talent and talent >= 5) and "unicorn" or recruit.kind)
		local gained = s.momentum - before
		if gained > 0 then
			player:SetAttribute("Momentum", s.momentum)
			local d = Mom.discount(s.momentum)
			toast:FireClient(player, ("+%d MOMENTUM  ·  next build %d%% off"):format(gained, math.floor(d * 100 + 0.5)))
			refreshHqPad(plot)      -- the price just changed; the sign has to say so
		end
	end
	updateHirePad(player)
	return true
end

local spinOff   -- assigned below releasePlot (it needs it); forward-declared like refreshFacade
local goPublic  -- v4.3 assigned in the IPO section (it needs refreshSign / tickerOf)
function refreshHqPad(plot)      -- forward-declared above hire()
	local nxt = CFG.HQ_LEVELS[plot.hq.level + 1]
	local s = plot.owner and sessions[plot.owner]
	local owner = plot.owner and Players:GetPlayerByUserId(plot.owner)
	if owner and Econ and Econ.Daily and Econ.Daily.refresh then pcall(Econ.Daily.refresh, owner) end   -- v4.5 the goal moved
	if Econ and Econ.WAFERS and plot.wafer then
		-- v4.6 THE WAFERS: the pad (and the BUILD card) say what the next tap builds
		local WP = Econ.Wafers.Plan
		local L, last, price, momSpend
		if s then L, last, price, momSpend = wafersNext(s, plot) end
		local rec, allowed = "", ""
		if L then
			local list = WP.allowed(L)
			allowed = table.concat(list, ",")
			local bp = s and s.blueprint and s.blueprint[L]
			if L <= ((s and s.record) or 1) and bp then rec = bp
			elseif #list > 0 then rec = WP.recommend(L, Econ.Wafers.counts(plot), (owner and capacityOf(owner) or 1) - ((s and s.staff) or 0)) end
		end
		if owner then
			owner:SetAttribute("WaferLevel", plot.wafer.level)
			owner:SetAttribute("WaferCap", WP.blueprint((s and s.spinoffs) or 0))
			owner:SetAttribute("WaferNext", L or 0)
			owner:SetAttribute("WaferLast", last or 0)
			owner:SetAttribute("WaferPrice", price or 0)
			owner:SetAttribute("WaferRec", rec)
			owner:SetAttribute("WaferAllowed", allowed)
			owner:SetAttribute("WaferNeed", 0)   -- homes no longer gate a level; the client still reads the field
		end
		if L then
			--[[ v5.0: the pad SAYS the discount. Measured on the live game before
				this existed: the pad read $1.5M and the till took $1.2M, because
				the label is only redrawn on a few events and momentum had been
				earned since the last one. Paying less than the sign says is a
				pleasant bug and still a bug -- worse, it hides the discount at
				the exact moment the player is deciding whether to go out again. ]]
			local off = (momSpend or 0) * Mom.PER_POINT   -- what this tap spends, so a rebuild shows none
			local tail = off > 0 and ("  ·  %d%% OFF"):format(math.floor(off * 100 + 0.5)) or ""
			if last > L then
				plot.hqLabel.Text = ("REBUILD LEVELS %d-%d  ·  $%s%s"):format(L, last, fmt(price), tail)
				plot.hqPad.Color = CFG.GOLD
			else
				plot.hqLabel.Text = ("BUILD LEVEL %d%s  ·  $%s%s"):format(L, rec ~= "" and ("  ·  " .. (Econ.Wafers.NAME[rec] or rec)) or "", fmt(price), tail)
				plot.hqPad.Color = CFG.GOLD
			end
			return
		end
		nxt = nil   -- the top of the blueprint: GO PUBLIC, then SPIN OFF (below)
	end
	if nxt then
		plot.hqLabel.Text = ("UPGRADE HQ  ·  $%s"):format(fmt(hqCostOf(s, plot.hq.level + 1)))
		plot.hqPad.Color = CFG.GOLD
	elseif s and not s.listed then
		-- v4.3: HQ 5 first takes the company public; only a listed company spins off
		plot.hqLabel.Text = "GO PUBLIC  ·  ring the bell on the Valley Exchange"
		plot.hqPad.Color = CFG.GOLD
	elseif s then
		if plot.spinArmed then
			plot.hqLabel.Text = "TAP AGAIN TO SPIN OFF  ·  back to the garage, x" .. string.format("%.1f", nextSpinMultOf(s)) .. " forever"
			plot.hqPad.Color = Color3.fromRGB(255, 120, 60)
		else
			plot.hqLabel.Text = ("SPIN OFF  ·  $%s  ·  revenue x%.1f forever"):format(fmt(spinoffCostOf(s)), nextSpinMultOf(s))
			plot.hqPad.Color = CFG.GOLD
		end
	else
		plot.hqLabel.Text = "HQ MAXED"
		plot.hqPad.Color = Color3.fromRGB(120, 118, 110)
	end
end

-- lifetime-earnings ladder: +2% revenue per power of ten past $10K
local function checkMilestones(player, s)
	local want = milestonesFromEarned(s.earned or 0)
	if want <= (s.milestones or 0) then return end
	s.milestones = want
	recompute(player)
	local plot = plotOf(player)
	-- v3.1: a HUD chip where the money is, not a popup at a pad you may be 80 studs from
	if plot and Econ and Econ.celebrate then
		Econ.celebrate:FireClient(player, { kind = "milestone", earned = CFG.MILESTONE_BASE * 10 ^ (want - 1),
			bonus = math.floor(want * CFG.MILESTONE_STEP * 100 + 0.5) })
	end
end

-- v4.6 THE WAFERS: one BUILD tap. The next floor (the department you chose, else the
-- guide's pick), or below your record the rest of that storey as you had it last time.
-- A new stage (levels 5 / 9 / 13 / 18 = the old HQ 2-5) plays the old level-up: the
-- banner, the car, new recruit tiers; later decks get the banner too.
local WAFER_BANNERS = { [43] = true, [68] = true, [93] = true, [100] = true }
local function wafersBuild(player, plot, s, cash, chosen)
	local WP = Econ.Wafers.Plan
	local cap = WP.blueprint(s.spinoffs or 0)
	if plot.wafer.level >= cap then
		if not s.listed then if goPublic then goPublic(player, plot) end return end
		if spinOff then spinOff(player, plot) end
		return
	end
	if not s.shipped then popup(plot.hqPad, "Ship something first", CFG.BAD) return end
	if s.staff < 1 then popup(plot.hqPad, "Hire someone first", CFG.BAD) return end

	--[[ THE STYLE GATE (v7). The first floor above the garage is where the
	player chooses which of the three buildings their company is.

	It is gated HERE, in the build itself, rather than on the BUILD card. The
	card is one of three ways to start a build -- the HQ pad prompt and its
	ClickDetector are the others -- and a choice that only one of them offers is
	a choice most players never see. Nothing is charged and nothing is built;
	the client opens the picker, and its reply builds this same floor.

	Only on the very first one. After that the building is committed until a
	spin-off, because restyling 40 storeys mid-company is a silent hitch. ]]
	if not s.hqPath and (plot.wafer and plot.wafer.level or 1) <= 1 then
		local ev = ReplicatedStorage:FindFirstChild("SVRemotes")
		ev = ev and ev:FindFirstChild("AskPath")
		if ev then ev:FireClient(player) return end
		-- no client listening (a very old client): fall through and build as Wafers
	end

	local L, last, price, momSpend = wafersNext(s, plot)
	if not L then return end
	if cash.Value < price then popup(plot.hqPad, "Need $" .. fmt(price), CFG.BAD) return end
	plot.busy = true
	cash.Value -= price
	--[[ The stock is consumed by the build it paid for. Holding it instead
		would make it a stat that only goes up, and a stat that only goes up
		stops being a decision by minute ten. Spending it is what turns the
		street into a loop: go out, come back, build cheap, go out. ]]
	if (momSpend or 0) > 0 then
		s.momentum = math.max(0, (s.momentum or 0) - momSpend)
		if player then player:SetAttribute("Momentum", s.momentum) end
	end
	s.lastBuy = os.clock()
	local stageBefore = plot.hq.level
	s.blueprint = s.blueprint or {}
	local freeSeats = capacityOf(player) - (s.staff or 0)
	local firstDept
	Econ.Wafers.buildUpTo(plot, last, function(x)
		local ok = {}
		for _, d in ipairs(WP.allowed(x)) do ok[d] = true end
		local pick
		if x == L and chosen and ok[chosen] then pick = chosen
		elseif x <= (s.record or 1) and ok[s.blueprint[x] or ""] then pick = s.blueprint[x]
		else pick = WP.recommend(x, Econ.Wafers.counts(plot), freeSeats) end
		s.blueprint[x] = pick
		firstDept = firstDept or pick
		return pick
	end, true)
	s.record = math.max(s.record or 1, plot.wafer.level)
	plot.hq.level = Econ.Wafers.stage(plot.wafer.level)
	s.hqLevel = plot.hq.level
	-- anyone the new walls closed round goes to the door (the HQ death fix, same rule)
	task.delay(0.3, function()
		local solid = {}
		for x = L, last do
			local piece = plot.wafer.pieces[x]
			for _, d in ipairs(piece and piece.model:GetDescendants() or {}) do
				if d:IsA("BasePart") and d.CanCollide then solid[d] = true end
			end
		end
		for _, pl in ipairs(Players:GetPlayers()) do
			local root = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
			if root and plot.spawn then
				for _, hit in ipairs(workspace:GetPartsInPart(root)) do
					if solid[hit] then pl.Character:PivotTo(plot.spawn.CFrame + Vector3.new(0, 3, 0)) break end
				end
			end
		end
	end)
	assignDesks(player)
	refreshSign(plot)
	refreshHqPad(plot)
	updateHirePad(player)
	local stage = plot.hq.level
	local lvl = plot.wafer.level
	if stage ~= stageBefore or WAFER_BANNERS[lvl] then
		plot.hqUpAt = os.clock()   -- v4.3: the Series A text waits for the level-up moment to pass
		if stage == 2 and stageBefore < 2 and Econ.Cars then
			task.delay(3.5, function() pcall(Econ.Cars.grant, player, "hatch", "COMPANY CAR!") end)
		end
		local chips = { ("Money x%s"):format((string.format("%.1f", hqMultOf(plot))):gsub("%.0$", "")) }
		table.insert(chips, ("Up to %d staff"):format(WP.capAt(lvl)))
		for _, tier in ipairs(Econ.RECRUIT and Econ.TIERS or {}) do
			if tier.hq == stage and tier.hq > 1 and stage ~= stageBefore then table.insert(chips, tier.name .. " hires on the street") end
		end
		if Econ.celebrate then
			local head, task1
			if stage ~= stageBefore then head, task1 = Journey.headline(stage, { hasCar = Econ.Cars and Econ.Cars.hasCar(player) }) end
			Econ.celebrate:FireClient(player, { kind = "hq", level = stage, name = ("LEVEL %d"):format(lvl), chips = chips,
				headline = head or ((lvl == 100) and "THE CROWN" or "GARDEN DECK"), task = task1 })
		end
	else
		local what = (last > L) and ("LEVELS %d-%d REBUILT"):format(L, last)
			or ("LEVEL %d  ·  %s"):format(L, (firstDept and Econ.Wafers.NAME[firstDept]) or "")
		popup(plot.hqPad, what, CFG.GOLD)
	end
	task.delay(0.6, function() plot.busy = false end)
end

local function tryUpgrade(player, plot, chosen)
	if plotOf(player) ~= plot or plot.busy then return end
	local s = sessions[player.UserId]
	local cash = cashOf(player)
	if Econ and Econ.WAFERS and plot.wafer and s and cash then return wafersBuild(player, plot, s, cash, chosen) end
	local nxt = CFG.HQ_LEVELS[plot.hq.level + 1]
	if not s or not cash then return end
	if not nxt then
		if not s.listed then if goPublic then goPublic(player, plot) end return end   -- v4.3
		if spinOff then spinOff(player, plot) end
		return
	end
	if not s.shipped then popup(plot.hqPad, "Ship something first", CFG.BAD) return end
	if s.staff < 1 then popup(plot.hqPad, "Hire someone first", CFG.BAD) return end
	local cost = hqCostOf(s, plot.hq.level + 1)
	if cash.Value < cost then popup(plot.hqPad, "Need $" .. fmt(cost), CFG.BAD) return end
	plot.busy = true
	cash.Value -= cost
	s.lastBuy = os.clock()
	buildShell(plot, plot.hq.level + 1, true)
	-- the new shell grows around whoever is inside. v5: only someone actually
	-- caught INSIDE a new wall or slab is moved to the door. The old rule sent
	-- everyone more than 9 studs up (every upper floor) to the garage on every
	-- upgrade; the client no longer sweeps the rise through the player inside
	-- (WorldFxClient), so nobody is pushed onto the roof any more
	task.delay(0.3, function()
		local solid = {}
		for _, sp in ipairs(plot.hq.shell) do if sp.CanCollide and sp.Name ~= "GarageFloor" then solid[sp] = true end end
		for _, pl in ipairs(Players:GetPlayers()) do
			local root = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
			if root and plot.spawn then
				for _, hit in ipairs(workspace:GetPartsInPart(root)) do
					if solid[hit] then
						pl.Character:PivotTo(plot.spawn.CFrame + Vector3.new(0, 3, 0))
						break
					end
				end
			end
		end
	end)
	refreshSign(plot)
	refreshHqPad(plot)
	plot.hqUpAt = os.clock()   -- v4.3: the Series A text waits for the level-up moment to pass
	recompute(player)          -- a bigger HQ earns more per head and prices everything up
	if plot.hq.level == 2 and Econ and Econ.Cars then
		task.delay(3.5, function() pcall(Econ.Cars.grant, player, "hatch", "COMPANY CAR!") end)
	end
	updateHirePad(player)
	for _, sl in ipairs(plot.slots) do if sl.built then refreshWingPrompt(sl, plot, s) end end
	popup(plot.hqPad, nxt.name .. "!", CFG.GOLD)
	--[[ v3.1: ONE celebration banner with what the level unlocked. It replaces
	two world popups and two toasts, the second of which ("Your scooter is
	faster: speed 17") overwrote the one that mattered after 2.5 s. ]]
	do
		local chips = { ("Money x%s"):format((string.format("%.1f", hqMultOf(plot))):gsub("%.0$", "")) }
		if Econ and Econ.CAP_BY_HQ and Econ.CAP_BY_HQ[plot.hq.level] then
			table.insert(chips, ("Up to %d staff"):format(Econ.CAP_BY_HQ[plot.hq.level]))
		end
		for _, tier in ipairs(Econ and Econ.RECRUIT and Econ.TIERS or {}) do
			if tier.hq == plot.hq.level and tier.hq > 1 then table.insert(chips, tier.name .. " hires on the street") end
		end
		if Econ and Econ.celebrate then
			-- v4.3: the ONE thing this level hands you (none for a car you already own)
			local head, task1 = Journey.headline(plot.hq.level, { hasCar = Econ and Econ.Cars and Econ.Cars.hasCar(player) })
			Econ.celebrate:FireClient(player, { kind = "hq", level = plot.hq.level, name = nxt.name, chips = chips,
				headline = head, task = task1 })
		end
	end
	task.delay(1.4, function() plot.busy = false end)
end

local function openDoor(plot)
	if plot.doorOpened then return end
	plot.doorOpened = true
	for _, door in ipairs({ plot.hq.doorL, plot.hq.doorR }) do
		TweenService:Create(door, TweenInfo.new(2.2, Enum.EasingStyle.Quad),
			{ CFrame = door.CFrame * CFrame.new(0, 11, 0) }):Play()
	end
	task.delay(0.4, function() popup(plot.desk, "Your lot is outside. Build on it.", CFG.GOLD) end)
end

-- ============ ROOMS ============

local function buildRoom(plot, slot, room)
	local cf = slot.cf
	local m = Instance.new("Model")
	m.Name = "Room_" .. room.id .. "_" .. slot.index
	m.Parent = plot.rooms
	local function rp(name, size, off, colour, mat)
		return part({ Name = name, Size = size, CFrame = cf * CFrame.new(off),
			Color = colour or room.color, Material = mat or Enum.Material.SmoothPlastic }, m)
	end
	-- v2.8: a glass department pavilion (CampusArch) instead of the shed below
	local arch = CampusArch and select(1, pcall(CampusArch.wing, m, cf, room, CFG.SLOT_W, CFG.SLOT_D))
	if not arch then
	m:ClearAllChildren()
	rp("Floor", Vector3.new(CFG.SLOT_W, 1, CFG.SLOT_D), Vector3.new(0, 0.5, 0), CFG.FLOOR, Enum.Material.Concrete)
	rp("WallL", Vector3.new(1, 10, CFG.SLOT_D), Vector3.new(-CFG.SLOT_W / 2, 5, 0))
	rp("WallR", Vector3.new(1, 10, CFG.SLOT_D), Vector3.new(CFG.SLOT_W / 2, 5, 0))
	rp("WallBack", Vector3.new(CFG.SLOT_W, 10, 1), Vector3.new(0, 5, -CFG.SLOT_D / 2))
	rp("Roof", Vector3.new(CFG.SLOT_W + 1, 1, CFG.SLOT_D + 1), Vector3.new(0, 10, 0), CFG.TRIM)
	local dimmed = Color3.new(room.accent.R * 0.45, room.accent.G * 0.45, room.accent.B * 0.45)
	rp("Fascia", Vector3.new(CFG.SLOT_W + 1, 1.6, 0.8), Vector3.new(0, 9.2, CFG.SLOT_D / 2), dimmed, Enum.Material.Neon)
	-- a glass front with a doorway, not an open fourth wall: a wing reads as a
	-- room you enter, and the furniture inside shows from the campus
	local doorW = 7
	local sideW = (CFG.SLOT_W - doorW) / 2
	for _, side in ipairs({ -1, 1 }) do
		local gl = rp("FrontGlass", Vector3.new(sideW, 7.4, 0.4), Vector3.new(side * (doorW / 2 + sideW / 2), 4.7, CFG.SLOT_D / 2),
			Color3.fromRGB(150, 200, 220), Enum.Material.Glass)
		gl.Transparency = 0.45
		gl.CanCollide = false          -- see through, walk through the door only
		gl.CanCollide = true
	end
	rp("DoorHeader", Vector3.new(doorW + 0.4, 1.6, 0.6), Vector3.new(0, 7.6, CFG.SLOT_D / 2), CFG.TRIM)
	rp("CeilingLight", Vector3.new(CFG.SLOT_W * 0.6, 0.25, 1), Vector3.new(0, 9.4, 0),
		Color3.fromRGB(255, 244, 222), Enum.Material.Neon)
	end
	-- rooms are EMPTY SHELLS you furnish; the server room keeps its racks
	-- because racks are its identity and the furniture kit has no rack
	if room.id == "servers" then
		for k = 1, 6 do
			rp("Rack" .. k, Vector3.new(2.2, 6, 3), Vector3.new(-10 + (k - 1) * 4, 4, -4),
				Color3.fromRGB(40, 44, 52), Enum.Material.Metal)
			rp("Blink" .. k, Vector3.new(1.6, 0.25, 0.2), Vector3.new(-10 + (k - 1) * 4, 5.6, -2.4),
				room.accent, Enum.Material.Neon)
		end
	end
	-- v2.0: starter dressing from the Kenney Furniture Kit (wall pieces only:
	-- bookcases, plants, sofa, bar, fridge, a monitoring desk). The floor stays
	-- the player's to furnish. Runs on build AND on load, since both come here.
	if FurnitureKit and FurnitureKit.dressRoom then
		local ok, n = pcall(FurnitureKit.dressRoom, m, room.id, cf, room.accent)
		if not ok then warn("[SV] dressRoom failed for " .. room.id .. ": " .. tostring(n)) end
	end
	if not arch then
		local nameTag = label(m:FindFirstChild("Fascia"), room.name, 20, 2.2, 110, true)
		nameTag.TextColor3 = Color3.new(1, 1, 1)
	end
	local movers = {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Floor" then table.insert(movers, d) end
	end
	rise(movers, 11, 0.75)
	return m
end

-- one code path for a bought wing and a restored one (free = from the save)
local function upgradeWing(player, plot, slot)
	if plotOf(player) ~= plot then return end
	local s = sessions[player.UserId]
	local cash = cashOf(player)
	if not s or not cash or not slot.built or not slot.room then return end
	if wingMaxed(s, slot) then popup(slot.header or plot.hirePad, slot.room.name .. " is maxed", CFG.ACCENT) refreshWingPrompt(slot, plot, s) return end
	local cost = wingUpgradeCostOf(slot.room, slot.level or 1, plot, s.rate)
	if cash.Value < cost then popup(slot.header or plot.hirePad, "Need $" .. fmt(cost), CFG.BAD) return end
	cash.Value -= cost
	s.lastBuy = os.clock()
	slot.level = (slot.level or 1) + 1
	applyWingLevel(s, slot.room)
	if slot.room.id == "office" then
		officeDesk(slot, 2 * slot.level - 1)
		officeDesk(slot, 2 * slot.level)
		assignDesks(player)
	elseif Econ and Econ.V3 then
		Econ.furnish(FurnitureKit, slot)
		assignDesks(player)
	end
	recompute(player)
	updateHirePad(player)
	refreshWingPrompt(slot, plot, s)
	popup(slot.header or plot.hirePad, ("%s Lv%d  %s"):format(slot.room.name, slot.level, CFG.WING_LEVEL_TEXT[slot.room.id] or ""), CFG.GOOD)
	-- v3.2: the building itself grows (Lv 4 storey, Lv 7 terrace, Lv 10 crown)
	if CampusArch and CampusArch.grow and slot.model then
		local ok, parts = pcall(CampusArch.grow, slot.model, slot.cf, slot.room, CFG.SLOT_W, CFG.SLOT_D, slot.level)
		if ok and parts and #parts > 0 then rise(parts, 9, 0.8) elseif not ok then warn("[SV] grow: " .. tostring(parts)) end
	end
end

local function buildWing(player, plot, slotIndex, roomId, free)
	local s = sessions[player.UserId]
	local cash = cashOf(player)
	if not s or not plot or not cash then return false end
	if type(slotIndex) ~= "number" then return false end
	local slot = plot.slots[slotIndex]
	local room = CFG.ROOM_BY_ID[roomId]
	if not slot or not room or slot.built then return false end
	if not free then
		if not s.buildUnlocked then return false end
		if Econ and Econ.V3 and Econ.slotsBuilt(plot) >= (Econ.SLOTS_BY_HQ[plot.hq.level] or 6) then
			popup(slot.pad, "Upgrade your HQ to build more rooms", CFG.BAD)
			return false
		end
		local cost = wingCostOf(room, plot, s.rate)
		if cash.Value < cost then popup(slot.pad, "Need $" .. fmt(cost), CFG.BAD) return false end
		cash.Value -= cost
		s.lastBuy = os.clock()
	end
	slot.built = room.id
	slot.prompt.Enabled = false
	slot.text.Text = ""
	slot.pad.Transparency = 1
	for _, e in ipairs(plot.slotFolder:GetChildren()) do
		if e.Name == slot.pad.Name .. "Edge" then e:Destroy() end
	end
	local model = buildRoom(plot, slot, room)
	-- v3.1: the building goes up where the BUILD pad was, i.e. under whoever
	-- just pressed it; the 25 Sep test ended standing on the new roof. Anyone
	-- inside the footprint steps out to the front door, facing it.
	for _, pl in ipairs(Players:GetPlayers()) do
		local root = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local rel = slot.cf:PointToObjectSpace(root.Position)
			if math.abs(rel.X) < CFG.SLOT_W / 2 + 1.5 and math.abs(rel.Z) < CFG.SLOT_D / 2 + 1.5 and rel.Y > -2 and rel.Y < 20 then
				local out = slot.cf:PointToWorldSpace(Vector3.new(0, 3.2, CFG.SLOT_D / 2 + 8))
				pl.Character:PivotTo(CFrame.lookAt(out, Vector3.new(slot.cf.Position.X, out.Y, slot.cf.Position.Z)))
			end
		end
	end
	slot.model = model
	slot.room = room
	slot.level = 1
	-- the door header is the wing's upgrade button: prompt + click, one handler
	local header = model and model:FindFirstChild("DoorHeader")
	if header then
		slot.header = header
		slot.upPrompt = prompt(header, "UPGRADE", "", 14)
		slot.upPrompt.Triggered:Connect(function(pl) upgradeWing(pl, plot, slot) end)
		alsoClickable(header, 18, function(pl) upgradeWing(pl, plot, slot) end)
		-- v2.8: the level lives on the building's sign, not floating above it
		slot.levelTag = model:FindFirstChild("LevelText", true)
		if not slot.levelTag then
			slot.levelTag = label(header, "Lv1", 16, 1.6, 60, true)
			slot.levelTag.TextColor3 = CFG.GOLD
		end
		refreshWingPrompt(slot, plot, s)
	end
	if Econ and Econ.V3 then Econ.furnish(FurnitureKit, slot) end
	if CampusArch then pcall(CampusArch.links, plot, CFG.SLOT_W, CFG.SLOT_D) end
	s.desks += (room.desks or 0)
	s.quality = (s.quality or 0) + (room.quality or 0)
	s.morale = (s.morale or 0) + (room.morale or 0)
	s.compute = (s.compute or 0) + (room.compute or 0)
	if room.id == "office" or (Econ and Econ.V3) then assignDesks(player) end   -- people in the line take the new seats
	recompute(player)
	updateHirePad(player)
	if not free then
		Telemetry.step(player, "first_wing")
		popup(slot.pad, room.name .. " BUILT", CFG.GOOD)
	end
	return true
end

placeRoom.OnServerEvent:Connect(function(player, slotIndex, roomId)
	local plot = plotOf(player)
	if plot then buildWing(player, plot, slotIndex, roomId, false) end
end)

-- ============ FURNITURE PLACEMENT ============

local GRID = 0.5
local DESK_FAMILY = { desk = true, deskCorner = true, tableRound = true, tableCross = true, kitchenBar = true }

local function floorRects(plot)
	local L = CFG.HQ_LEVELS[plot.hq.level]
	local rects = { { cf = plot.pivot, w = L.w, d = L.d, top = 1.0 } }
	for _, slot in ipairs(plot.slots) do
		if slot.built then table.insert(rects, { cf = slot.cf, w = CFG.SLOT_W, d = CFG.SLOT_D, top = 1.0 }) end
	end
	return rects
end

local function rectsOverlap(ax, az, aw, ad, bx, bz, bw, bd)
	return math.abs(ax - bx) * 2 < (aw + bw) - 0.05 and math.abs(az - bz) * 2 < (ad + bd) - 0.05
end

local function roomBuilt(plot, roomId)
	for _, slot in ipairs(plot.slots) do
		if slot.built == roomId then return true end
	end
	return false
end

-- one code path for a bought item and a restored one (free = from the save)
local function placeAt(player, plot, key, px, pz, yawDeg, free, forcedPrice)
	local s = sessions[player.UserId]
	local cash = cashOf(player)
	if not s or not plot or not cash then return false end
	if not free and not s.shipped then return false end
	if not FurnitureKit or not FurnitureKit.BY_KEY then return false end
	if type(key) ~= "string" or type(px) ~= "number" or type(pz) ~= "number" or type(yawDeg) ~= "number" then return false end
	-- NaN fails every comparison and inf survives the rounding: either would be charged,
	-- pivoted to nowhere and written into the save
	for _, v in ipairs({ px, pz, yawDeg }) do
		if v ~= v or math.abs(v) == math.huge then return false end
	end
	local item = FurnitureKit.BY_KEY[key]
	if not item or not FurnitureKit.has(key) then return false end
	if item.needs and not roomBuilt(plot, item.needs) then
		if not free then
			local r = CFG.ROOM_BY_ID[item.needs]
			local nm = r and r.name or tostring(item.needs)
			popup(plot.hirePad, ("Build %s %s first"):format(nm:upper():match("^[AEIOU]") and "an" or "a", nm), CFG.BAD)
		end
		return false
	end

	local yaw = (math.floor((yawDeg / 90) + 0.5) % 4) * 90
	local x = math.floor(px / GRID + 0.5) * GRID
	local z = math.floor(pz / GRID + 0.5) * GRID
	local w, d = FurnitureKit.footprint(key, yaw)

	local floor
	for _, r in ipairs(floorRects(plot)) do
		local l = r.cf:PointToObjectSpace(Vector3.new(x, 0, z))
		if math.abs(l.X) + w / 2 <= r.w / 2 and math.abs(l.Z) + d / 2 <= r.d / 2 then floor = r break end
	end
	if not floor then if not free then popup(plot.hirePad, "Outside your floor", CFG.BAD) end return false end

	-- v2.6.0 ROOM ECONOMY: a station seats people only in its own room, up to
	-- that room's cap. A refused station from an old save is refunded, not lost.
	local st = Econ and Econ.STATIONS[key]
	local roomId, slotIdx
	if st then
		local L = CFG.HQ_LEVELS[plot.hq.level]
		roomId, slotIdx = Econ.roomAt(plot, x, z, L.w, L.d, CFG.SLOT_W, CFG.SLOT_D)
		local why
		if not (roomId == st.room or (roomId == "hq" and st.hq)) then
			why = ("%s only works in the %s"):format(item.name, st.hq and "HQ or an Open Office" or (Econ.ROOM_NAME[st.room] or st.room):lower())
		else
			local lvl = (roomId == "hq") and plot.hq.level or ((plot.slots[slotIdx] and plot.slots[slotIdx].level) or 1)
			if Econ.seatsUsed(s.placed, roomId, slotIdx) + st.seats > Econ.roomCap(roomId, lvl) then
				why = ("This %s is full  ·  upgrade it for more seats"):format((Econ.ROOM_NAME[roomId] or roomId):lower())
			end
		end
		if why then
			if free then cash.Value += (forcedPrice or item.price) else toast:FireClient(player, why) end
			return false
		end
	end

	local y = floor.top
	local onSurface = nil
	if item.surface then
		for _, e in ipairs(s.placed) do
			if e.surfaceTop and rectsOverlap(x, z, w, d, e.x, e.z, e.w, e.d) then
				y = floor.top + e.surfaceTop; onSurface = e; break
			end
		end
		if not onSurface then
			for _, e in ipairs(plot.fixed) do
				if rectsOverlap(x, z, w, d, e.x, e.z, e.w, e.d) then
					y = floor.top + e.top; onSurface = e; break
				end
			end
		end
	end

	for _, e in ipairs(plot.fixed) do
		if rectsOverlap(x, z, w, d, e.x, e.z, e.w, e.d) then
			if not (item.tuck or item.flat or onSurface == e or e.y ~= y) then
				if not free then popup(plot.hirePad, "The workbench is there", CFG.BAD) end
				return false
			end
		end
	end
	for _, e in ipairs(s.placed) do
		if rectsOverlap(x, z, w, d, e.x, e.z, e.w, e.d) then
			local tucking = item.tuck and DESK_FAMILY[e.key]
			local surfacePair = onSurface and (e == onSurface)
			local stacked = (e.y or 0) ~= y
			-- v4.4 a rug (flat) goes under anything, and anything may stand on it
			local rug = item.flat or (FurnitureKit.BY_KEY[e.key] and FurnitureKit.BY_KEY[e.key].flat)
			if not (tucking or surfacePair or stacked or rug) then
				if not free then popup(plot.hirePad, "Something is already there", CFG.BAD) end
				return false
			end
		end
	end
	-- v3.5: never on someone's seat (36 lamps around the office desks put three
	-- inside seated staff) and never inside a room's own furniture. A saved item
	-- that breaks either rule is refunded on load, like a refused station.
	-- (A rug is flat: it may lie under a seat or a room's table.)
	if not onSurface and not item.flat then
		local clash
		for _, h in ipairs(deskHomes(s, plot)) do
			local hp = h.cf.Position
			-- 4 studs: a seated avatar's arms reach ~2 either side (2.2 was the old block rig's width)
			if rectsOverlap(x, z, w, d, hp.X, hp.Z, 4.0, 4.0) then clash = "That's someone's seat" break end
		end
		if not clash and FurnitureKit.blocked and FurnitureKit.blocked(plot, x, z, w, d) then clash = "Something is already there" end
		if clash then
			if free then
				cash.Value += (forcedPrice or item.price)
				player:SetAttribute("SVRefunded", (player:GetAttribute("SVRefunded") or 0) + 1)   -- Studio audit reads this
			else
				popup(plot.hirePad, clash, CFG.BAD)
			end
			return false
		end
	end

	-- what was PAID is what refunds. On load the saved price is used; an old
	-- save without one falls back to the base price (never the inflated one:
	-- recomputing at a higher HQ level minted cash on every relog)
	local price = forcedPrice or (free and item.price) or furniturePriceOf(item, s, plot)
	if not free then
		if cash.Value < price then popup(plot.hirePad, "Need $" .. fmt(price), CFG.BAD) return false end
		cash.Value -= price
	end

	local m = FurnitureKit.put(key, CFrame.new(x, y, z), plot.placed, { yaw = yaw, canQuery = true })
	if not m then if not free then cash.Value += price end return false end
	m:SetAttribute("owner", player.UserId)
	m:SetAttribute("key", key)
	m:SetAttribute("px", x); m:SetAttribute("pz", z)
	m:SetAttribute("pw", w); m:SetAttribute("pd", d)
	m:SetAttribute("py", y)
	table.insert(s.placed, { model = m, key = key, price = price,
		x = x, z = z, w = w, d = d, y = y, yaw = yaw, surfaceTop = item.surfaceTop,
		room = roomId, slot = slotIdx })
	if item.desk then s.placedDesks += item.desk end
	if item.morale then s.placedMorale += item.morale end
	local starsBefore = player:GetAttribute("VibeStars") or 0
	recompute(player)
	-- a new Vibe star is a moment: say what it bought, where it was earned
	local starsAfter = player:GetAttribute("VibeStars") or 0
	if not free and starsAfter > starsBefore then
		local at = m:IsA("BasePart") and m or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
		if at then popup(at, ("VIBE UP! %d of 5 stars  ·  rare hires x%s"):format(starsAfter, (string.format("%.1f", player:GetAttribute("VibeLuck") or 1))), CFG.ACCENT) end
	end
	if item.desk then assignDesks(player) end
	updateHirePad(player)
	return true
end

placeItem.OnServerEvent:Connect(function(player, key, pos, yawDeg)
	local plot = plotOf(player)
	if not plot or typeof(pos) ~= "Vector3" then return end
	placeAt(player, plot, key, pos.X, pos.Z, yawDeg, false)
end)

removeItem.OnServerEvent:Connect(function(player, model)
	local s = sessions[player.UserId]
	local plot = plotOf(player)
	local cash = cashOf(player)
	if not s or not plot or not cash then return end
	if typeof(model) ~= "Instance" or model.Parent ~= plot.placed then return end
	if model:GetAttribute("owner") ~= player.UserId then return end

	local target
	for _, e in ipairs(s.placed) do
		if e.model == model then target = e break end
	end
	if not target then return end

	-- anything sitting ON this surface goes with it, refunded too
	if target.surfaceTop then
		for j = #s.placed, 1, -1 do
			local r = s.placed[j]
			if r ~= target and r.y > target.y and rectsOverlap(target.x, target.z, target.w, target.d, r.x, r.z, r.w, r.d) then
				local rit = FurnitureKit.BY_KEY[r.key]
				cash.Value += math.floor(r.price / 2)
				if rit and rit.desk then s.placedDesks -= rit.desk end
				if rit and rit.morale then s.placedMorale -= rit.morale end
				r.model:Destroy()
				table.remove(s.placed, j)
			end
		end
	end
	local it = FurnitureKit.BY_KEY[target.key]
	cash.Value += math.floor(target.price / 2)
	if it and it.desk then s.placedDesks -= it.desk end
	if it and it.morale then s.placedMorale -= it.morale end
	model:Destroy()
	for k, e in ipairs(s.placed) do
		if e == target then table.remove(s.placed, k) break end
	end
	recompute(player)
	assignDesks(player)     -- a hire whose desk just vanished walks to the line
	updateHirePad(player)   -- AFTER the reseat, so the pad can say who is waiting
end)

-- v2.7.0 the HUD WRITE CODE button: same handler as the laptop. Connected
-- HERE, below writeCode's definition (at the top of the file it would be nil).
remote("WriteCode").OnServerEvent:Connect(function(player)
	local plot = plotOf(player)
	if plot then writeCode(player, plot) end
end)

-- v3.0 TALENT INDEX: the client reads "IndexData" (role:talent keys) and the
-- "IndexNew" badge count; opening the Index sends IndexSeen, which clears it
if Econ then
	Econ.publishIndex = function(player, s)
		local keys = {}
		for k in pairs(s.index or {}) do table.insert(keys, k) end
		table.sort(keys)
		player:SetAttribute("IndexData", table.concat(keys, ","))
	end
	remote("IndexSeen").OnServerEvent:Connect(function(player) player:SetAttribute("IndexNew", 0) end)
end

-- v3.1: celebration events (HQ level, launch, milestone, spin-off) and the
-- spin-off confirm card's button. Stored on Econ: this file is at the 200-local limit.
if Econ then
	Econ.celebrate = remote("Celebrate")
	remote("SpinConfirm").OnServerEvent:Connect(function(player, msg)
		local plot = plotOf(player)
		if plot and plot.spinArmed and os.clock() - plot.spinArmed <= 30 and spinOff then
			--[[ Never trust the client with WHO survives. The pick is only a list of
				numbers; spinOff matches each against the offer THIS server built for
				the card (and the staff list as it is right now). Whatever does not
				match is dropped; nothing valid means the best `slots`. ]]
			local ids
			if type(msg) == "table" and type(msg.pick) == "table" then
				ids = {}
				for i = 1, math.min(#msg.pick, 32) do
					if type(msg.pick[i]) == "number" then ids[#ids + 1] = msg.pick[i] end
				end
			end
			plot.spinPickIds = ids
			plot.spinFromCard = true
			spinOff(player, plot)
			plot.spinPickIds = nil
			plot.spinFromCard = nil
		end
	end)
	remote("SpinCancel").OnServerEvent:Connect(function(player)
		local plot = plotOf(player)
		if plot and plot.spinArmed then plot.spinArmed = nil; plot.spinOffer = nil; refreshHqPad(plot) end
	end)
	Econ.Daily = tryRequire(ServerScriptService, "DailyReward")
	if Econ.Daily and Econ.Daily.init then
		local ok, err = pcall(Econ.Daily.init, {
			session = function(p) return sessions[p.UserId] end, cash = cashOf, remote = remote, fmt = fmt,
			nextGoal = function(p)   -- v4.5 the clock: windfalls are capped against this
				local ss, pl = sessions[p.UserId], plotOf(p)
				return ss and pl and nextGoalOf(ss, pl) or nil
			end,
			grant = function(p, id, n, why) return Econ.Inv and Econ.Inv.grant(p, id, n, why) end,   -- v3.2 (Inv loads later; read at claim time)
		})
		if not ok then warn("[SV] DailyReward init failed: " .. tostring(err)); Econ.Daily = nil end
	end
end

-- v3.0 TALENT ROW: stored on Econ (this file is at the 200-local limit)
if Econ and Econ.RECRUIT then
	Econ.Drop = tryRequire(ServerScriptService, "TalentDrop")
	if Econ.Drop and Econ.Drop.init then
		local ok, err = pcall(Econ.Drop.init, {
			plots = plots, TALENT = CFG.TALENT, RIVALS = CFG.RIVALS, BAD = CFG.BAD, fmt = fmt, popup = popup,
			session = function(p) return sessions[p.UserId] end,
			plotOf = plotOf, cash = cashOf, capacity = capacityOf,
			priceScale = function(p) return scaleOf(sessions[p.UserId]) end,   -- v4.5 recruit minimums follow the clock
			ladder = function(p)
				local ss, pl = sessions[p.UserId], plotOf(p)
				return ss and pl and hireCostOf(ss, pl) or nil
			end,
			hire = function(p, pl, r) return hire(p, pl, r) end,
		})
		if not ok then warn("[SV] TalentDrop init failed: " .. tostring(err)); Econ.Drop = nil end
	else
		Econ.Drop = nil
	end
end

-- v3.2 THE BAG and THE PHONE, also on Econ (this file is at the 200-local limit)
if Econ then
	Econ.Inv = tryRequire(ServerScriptService, "Inventory")
	if Econ.Inv and Econ.Inv.init then
		local ok, err = pcall(Econ.Inv.init, {
			session = function(p) return sessions[p.UserId] end,
			refreshSpeed = function(p) if Econ.Drop and Econ.Drop.refreshSpeed then Econ.Drop.refreshSpeed(p) end end,
			dismissHunter = function(p) return (Econ.Drop and Econ.Drop.dismissHunter and Econ.Drop.dismissHunter(p)) or false end,
		})
		if not ok then warn("[SV] Inventory init failed: " .. tostring(err)); Econ.Inv = nil end
	else
		Econ.Inv = nil
	end
	Econ.Phone = tryRequire(ServerScriptService, "Phone")
	if Econ.Phone and Econ.Phone.init then
		local ok, err = pcall(Econ.Phone.init, {
			session = function(p) return sessions[p.UserId] end,
			plotOf = plotOf, cash = cashOf, fmt = fmt, TALENT = CFG.TALENT,
			nextGoal = function(p)   -- v4.5 the clock: windfalls are capped against this
				local ss, pl = sessions[p.UserId], plotOf(p)
				return ss and pl and nextGoalOf(ss, pl) or nil
			end,
			grant = function(p, id, n, why) return Econ.Inv and Econ.Inv.grant(p, id, n, why) end,
			onSeriesA = function(p)   -- v4.3 the HQ 4 task
				local ss = sessions[p.UserId]
				if ss then ss.jr = ss.jr or {}; ss.jr.seriesA = true end
			end,
		})
		if not ok then warn("[SV] Phone init failed: " .. tostring(err)); Econ.Phone = nil end
	else
		Econ.Phone = nil
	end
	-- v4.0 APARTMENTS (a rung between HQ levels) and CARS (driving + the dealership)
	Econ.Apt = tryRequire(ServerScriptService, "Apartments")
	if Econ.Apt and Econ.Apt.init then
		local ok, err = pcall(Econ.Apt.init, {
			session = function(p) return sessions[p.UserId] end,
			plotOf = plotOf, cash = cashOf, fmt = fmt,
			recompute = function(p) recompute(p) end,
			refreshObjective = function(p) refreshObjective(p) end,
			refreshHqPad = function(pl) refreshHqPad(pl) end,
			telemetry = function(p, step) if Telemetry and Telemetry.event then Telemetry.event(p, step) end end,
		})
		if not ok then warn("[SV] Apartments init failed: " .. tostring(err)); Econ.Apt = nil end
	else
		Econ.Apt = nil
	end
	Econ.Cars = tryRequire(ServerScriptService, "Cars")
	if Econ.Cars and Econ.Cars.init then
		local ok, err = pcall(Econ.Cars.init, {
			session = function(p) return sessions[p.UserId] end,
			plotOf = plotOf, cash = cashOf, celebrate = Econ.celebrate,
			telemetry = function(p, step) if Telemetry and Telemetry.event then Telemetry.event(p, step) end end,
		})
		if not ok then warn("[SV] Cars init failed: " .. tostring(err)); Econ.Cars = nil end
	else
		Econ.Cars = nil
	end
	-- v4.6 THE WAFERS (docs/superpowers/specs/2026-09-30-wafers-hq-design.md): the one-building HQ
	Econ.Wafers = tryRequire(ServerScriptService, "Wafers")
	if Econ.Wafers and Econ.Wafers.init and Econ.V3 then
		local ok, err = pcall(Econ.Wafers.init, {
			part = part, rise = rise, FK = FurnitureKit, Palette = Pal, Sfx = tryRequire(ReplicatedStorage, "Sfx"), HQFloors = tryRequire(ServerScriptService, "HQFloors"),
			-- v7: floor stations need to talk back to the game
			prompt = prompt, popup = popup, session = function(pl) return sessions[pl.UserId] end,
			grant = function(pl, id, n) return Econ.Inv and Econ.Inv.grant(pl, id, n, "floor") end,
			plotOf = plotOf,
		})
		if ok then Econ.WAFERS = true else warn("[SV] Wafers init failed: " .. tostring(err)); Econ.Wafers = nil end
		-- v4.9: the finished tower's massing, for the opening flyover's ghost.
		-- It has to go HERE and not where plotsFolder is made: Econ.Wafers is
		-- required on this line, ~2100 lines later, so an earlier set was a
		-- pcall quietly swallowing "index nil".
		if Econ.WAFERS then
			pcall(function() plotsFolder:SetAttribute("TowerSpec", Econ.Wafers.towerSpec()) end)
		end
	else
		Econ.Wafers = nil
	end
	remote("WaferBuild").OnServerEvent:Connect(function(player, dept)
		local plot = plotOf(player)
		if plot and Econ.WAFERS then tryUpgrade(player, plot, type(dept) == "string" and dept or nil) end
	end)

	--[[ WaferPath: the player picks which of the three buildings their company
	is. Free, and only before the first floor above the garage goes up -- after
	that it is a spin-off decision, because rebuilding 40 storeys in a new skin
	mid-company would be a silent 30-second hitch.

	The server decides whether the choice is still open; the client's card is
	only ever an offer. ]]
	remote("AskPath")       -- server -> client: open the style picker
	remote("WaferPath").OnServerEvent:Connect(function(player, path)
		local plot = plotOf(player)
		local s = sessions[player.UserId]
		if not (plot and s and Econ.WAFERS and Econ.Wafers) then return end
		if type(path) ~= "string" or not Econ.Wafers.PATHS[path] then return end
		-- flipping styles costs a recompute and a broadcast each time: one a second
		if os.clock() < (s.pathNext or 0) then return end
		s.pathNext = os.clock() + 1
		-- only while the HQ is still just the garage
		if (plot.wafer and plot.wafer.level or 1) > 1 then
			popup(plot.hqPad, "Too late to restyle -- next company", CFG.BAD)
			return
		end
		if s.hqPath == path then return end
		s.hqPath = path
		plot.hqPath = path
		recompute(player)
		popup(plot.hqPad, Econ.Wafers.pathName(path) .. " it is", CFG.GOOD)
		-- the pick came from the gate in wafersBuild, so finish what they asked
		-- for: one tap, one choice, the floor goes up. Making them press BUILD a
		-- second time would read as the first tap having failed.
		task.defer(function() tryUpgrade(player, plot) end)
	end)
end

-- ============ WIRING + ASSIGNMENT ============

-- prompts are connected here, after every handler above exists
local function wirePlot(plot)
	local cp = prompt(plot.laptop, "WRITE CODE", "Your laptop", 14)
	cp.Triggered:Connect(function(player) writeCode(player, plot) end)
	alsoClickable(plot.laptop, 16, function(player) writeCode(player, plot) end)
	alsoClickable(plot.screen, 16, function(player) writeCode(player, plot) end)

	alsoClickable(plot.hirePad, 16, function(player) hire(player, plot) end)
	local hireDebounce = {}
	plot.hirePad.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if not player or hireDebounce[player.UserId] then return end
		hireDebounce[player.UserId] = true
		task.delay(0.9, function() hireDebounce[player.UserId] = nil end)
		hire(player, plot)
	end)

	local hp = prompt(plot.hqPad, "UPGRADE", "Headquarters", 12)
	plot.hqPrompt = hp
	hp.Enabled = false          -- updateHirePad turns it on once someone works here
	hp.Triggered:Connect(function(player) tryUpgrade(player, plot) end)
	alsoClickable(plot.hqPad, 16, function(player) tryUpgrade(player, plot) end)
	refreshHqPad(plot)
end

-- a vacated plot goes back to the exact state a new player expects
local function releasePlot(plot)
	plot.owner = nil
	for _, f in ipairs({ plot.placed, plot.rooms, plot.staff }) do
		for _, c in ipairs(f:GetChildren()) do c:Destroy() end
	end
	local prod = plot.garage:FindFirstChild("Product")
	if prod then prod:Destroy() end
	plot.doorOpened = false
	buildShell(plot, 1, false)
	if Econ and Econ.WAFERS then
		Econ.Wafers.clear(plot)
		plot.slots = {}
	else
		buildSlots(plot)
	end
	plot.hireLabel.Text = ""
	plot.hirePad.Color = CFG.TRIM
	refreshHqPad(plot)
	if plot.signTag then plot.signTag.Text = CFG.HQ_LEVELS[1].name end
	if plot.signPlate then plot.signPlate.Color = CFG.TRIM; plot.signPlate.Material = Enum.Material.SmoothPlastic end
end

spinOff = function(player, plot)
	local s = sessions[player.UserId]
	local cash = cashOf(player)
	if not s or not cash or plot.busy or plotOf(player) ~= plot then return end
	if not s.listed then popup(plot.hqPad, "GO PUBLIC first", CFG.BAD) return end   -- v4.3: every path, not just the pad
	local cost = spinoffCostOf(s)
	if cash.Value < cost then popup(plot.hqPad, "Need $" .. fmt(cost), CFG.BAD) return end
	-- two taps: a one-click reset of an hour of play is not a decision
	--[[ v3.1: the confirm is a card (what you keep vs what resets, SPIN OFF /
	NOT YET), not a fading 1-second sentence at the pad. An accidental reset of
	an hour of play is the quit event for your best players. The card's button
	fires SpinConfirm, which comes back here as the second tap. ]]
	if not plot.spinArmed or os.clock() - plot.spinArmed > 30 then
		plot.spinArmed = os.clock()
		refreshHqPad(plot)
		--[[ The home decides how many come with you; the player will decide which
			(the card lets them choose which). Eligibility is still KEEP_TALENT (Star
			and above). Best-first in a total order, so the card's default selection,
			the top `slots`, is exactly what the server falls back to. Each person is
			given an opaque id bound to their staff ENTRY (not their position in
			s.rigs, which can shift while the card is open); ids are never reused, so
			a pick left over from an older card cannot match this one. ]]
		local slots = Prog.keepSlots(s.apt)
		local offer = { byId = {} }
		local eligible = {}
		for _, k in ipairs(Prog.rankKeepers(s.rigs, (Econ and Econ.KEEP_TALENT) or 3)) do
			plot.spinSerial = (plot.spinSerial or 0) + 1
			offer.byId[plot.spinSerial] = k.entry
			table.insert(eligible, { id = plot.spinSerial, talent = k.talent,
				talentName = (CFG.TALENT[k.talent] or CFG.TALENT[1]).name,
				name = (k.entry.rig and k.entry.rig:GetAttribute("PersonName")) or "someone" })
		end
		offer.choose = slots > 0 and #eligible > slots      -- a real decision is pending: only the card may confirm it
		plot.spinOffer = offer
		if Econ and Econ.celebrate then
			Econ.celebrate:FireClient(player, { kind = "spinAsk", cost = cost, from = spinMultOf(s), to = nextSpinMultOf(s),
				keep = math.min(#eligible, slots), slots = slots, eligible = eligible, number = (s.spinoffs or 0) + 1 })
		end
		task.delay(30.5, function()
			if plot.spinArmed and os.clock() - plot.spinArmed >= 30 then plot.spinArmed = nil; plot.spinOffer = nil; refreshHqPad(plot) end
		end)
		return
	end
	--[[ The pad's second tap arrives here too, with no selection. When the player
		has more eligible people than seats, letting it through would silently keep
		the best N instead of the people whose chips they tapped, so while a choice
		is pending only the card's own button (plot.spinFromCard) may confirm. ]]
	if plot.spinOffer and plot.spinOffer.choose and not plot.spinFromCard then
		popup(plot.hqPad, "Choose who comes with you", CFG.BAD)
		return
	end
	plot.spinArmed = nil
	plot.busy = true
	-- v2.7.0: Star and above follow you to the next startup (the chase across runs)
	local keep = {}
	if Econ and Econ.V3 then
		-- recruiting makes Star+ common (the sim kept ~12), so the home you own decides how many come along,
		-- and the player decides which: their pick is matched against the CURRENT staff (see Prog.chooseKeepers)
		for _, r in ipairs(Prog.chooseKeepers(s.rigs, Econ.KEEP_TALENT, Prog.keepSlots(s.apt), plot.spinOffer, plot.spinPickIds)) do
			table.insert(keep, { talent = r.talent, who = r.who })
		end
	end
	plot.spinOffer = nil
	cash.Value = 0
	releasePlot(plot)                -- wipes rooms, furniture, staff; shell back to the garage
	plot.owner = player.UserId
	s.staff = 0; s.rigs = {}; s.desks = 0; s.hireCost = CFG.HIRE_BASE
	s.quality = 0; s.morale = 0; s.compute = 0
	s.placed = {}; s.placedDesks = 0; s.placedMorale = 0
	s.work = 0; s.runLaunches = 0; s.workNeed = CFG.WORK_FIRST   -- v4.5: each company's first product is quick again
	s.launch = nil; s.pressure = nil; s.share = 1; s.pendingOffer = nil
	s.listed = false                   -- v4.3: the new company goes public again at its own HQ 5
	if s.jr then s.jr.seriesA = nil end  -- ... and raises its own Series A at HQ 4
	-- v3.1: an app finished before the spin-off belongs to the old company; its
	-- LAUNCH card used to survive the reset showing the old payday
	s.pendingProduct = nil
	productReady:FireClient(player, nil)
	s.spinoffs = math.min((s.spinoffs or 0) + 1, Prog.SPIN_CAP)
	s.shipped = true; s.buildUnlocked = true
	plot.doorOpened = true
	for _, door in ipairs({ plot.hq.doorL, plot.hq.doorR }) do door.CFrame = door.CFrame * CFrame.new(0, 11, 0) end
	for _, slot in ipairs(plot.slots) do slot.prompt.Enabled = true; slot.text.Text = "BUILD HERE" end
	for i, k in ipairs(keep) do
		s.staff = i
		if i > 1 then s.hireCost = math.floor(s.hireCost * hireGrowthAt(i)) end   -- same ladder the loader rebuilds
		spawnStaff(player, plot, i, k.talent, k.who)
	end
	if #keep > 0 then
		task.delay(2.2, function() popup(plot.hirePad, ("%d rare hire%s came with you  ·  build %s to seat them"):format(#keep, #keep == 1 and "" or "s", (Econ and Econ.WAFERS) and "a floor" or "an office"), CFG.GOLD) end)
	end
	recompute(player)
	refreshSign(plot)
	refreshHqPad(plot)
	updateHirePad(player)
	local char = player.Character
	if char and plot.spawn then char:PivotTo(plot.spawn.CFrame + Vector3.new(0, 3, 0)) end
	popup(plot.hqPad, ("SPIN-OFF %s!"):format(CFG.ROMAN[s.spinoffs + 1] or ""), CFG.GOLD)
	if Econ and Econ.celebrate then
		Econ.celebrate:FireClient(player, { kind = "spin", number = s.spinoffs, mult = spinMultOf(s), kept = #keep })
	end
	task.delay(1.5, function() plot.busy = false end)
end

local function assignPlot(player)
	for _, plot in ipairs(plots) do
		if not plot.owner then
			plot.owner = player.UserId
			player:SetAttribute("Plot", plot.index)
			player.RespawnLocation = plot.spawn
			return plot
		end
	end
	return nil
end

for i, def in ipairs(CFG.PLOT_DEFS) do
	plots[i] = buildPlot(i, def)
	wirePlot(plots[i])
end

--[[ One last pass once every plot exists. Each plot fixes itself as it is
	built, but plot 1's lawn can run onto plot 2's promenade, and plot 2 is
	not poured yet when plot 1 checks. Three bushes survived exactly that way.
	A final sweep over the finished world costs one scan and closes the whole
	class of ordering bug, which is the thing this system exists to end. ]]
do
	local Place = tryRequire(ServerScriptService, "Placement")
	if Place and Place.pass then
		local okP, _, before, pits, moved, gone, left = pcall(Place.pass, world, { world })
		if okP and (before or 0) > 0 then
			print(("[SV] placement final: %d in paving -> %d pits, %d moved, %d removed | %d left")
				:format(before, pits, moved, gone, left))
		end
		if okP and (left or 0) > 0 then
			warn(("[SV] placement: %d greenery still standing in paving after the final pass"):format(left))
		end
	end
	--[[ The world-wide re-tint. Imported packs -- cars, furniture, meshes --
		are cloned straight into the world and never touch a builder helper, so
		they arrive carrying the pack's own colours. That is the single largest
		source of "five hands made this", and this sweep is the only thing in
		the project that can reach it. ]]
	if Pal then
		local n, washed, tagged = Pal.enforce(world)
		print(("[SV] palette: re-tinted %d parts, washed %d pack meshes, tagged %d emissives")
			:format(n, washed, tagged))
		-- and from here on, anything entering the world is mapped as it arrives
		Pal.watch(world)
	end
	do
		local Shapes = tryRequire(ServerScriptService, "Shapes")
		if Shapes and Shapes.apply then
			local okS, hosts, made = pcall(Shapes.apply, world)
			if okS then print(("[SV] motif: rounded %d lawn slabs with %d parts"):format(hosts, made)) end
		end
	end
end

-- ============ INCOME ============

task.spawn(function()
	while true do
		task.wait(1)
		for _, player in ipairs(Players:GetPlayers()) do
			local s = sessions[player.UserId]
			local cash = cashOf(player)
			if s then
				-- MARKET SHARE: slips under rival pressure while online and not
				-- in a launch buzz; only shipping restores it (launchProduct)
				-- v2.5.1: a launch only shields the market it launched in (the blanket
				-- buzz cancelled every rival hit, so share never moved in real play)
				local buzz = s.launch and s.launch.marketId == s.pressureMarket
					and (os.clock() - s.launch.t0) < s.launch.duration
				if s.pressure and os.clock() - s.pressure >= CFG.PRESSURE_SECONDS then
					s.pressure = nil
				elseif s.pressure and not buzz then
					s.share = math.max(CFG.SHARE_FLOOR, (s.share or 1) - CFG.SHARE_DECAY)
				end
				local shown = math.floor((s.share or 1) * 100 + 0.5)
				if shown ~= s.shareShown then
					s.shareShown = shown
					player:SetAttribute("MarketShare", shown)
				end
			end
			-- v2.6.3 AFK = OFFLINE: 5 min without moving earns the offline 25%
			local afk = 1
			if s and Econ then
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if hrp and (not s.lastPos or (hrp.Position - s.lastPos).Magnitude > 2) then
					s.lastPos = hrp.Position
					s.lastActive = os.clock()
				end
				s.lastActive = s.lastActive or os.clock()
				-- v2.7.2: tapping WRITE CODE and buying are activity too. Only
				-- walking counted, so a player standing at the laptop tapping the
				-- button went AWAY 25% at minute 5 (found by the clean-run bot).
				if s.lastCode and s.lastCode > s.lastActive then s.lastActive = s.lastCode end
				if s.lastBuy and s.lastBuy > s.lastActive then s.lastActive = s.lastBuy end
				if s.lastTap and s.lastTap > s.lastActive then s.lastActive = s.lastTap end
				local away = os.clock() - s.lastActive > Econ.AFK_SECONDS
				if away ~= (s.away == true) then
					s.away = away
					player:SetAttribute("Away", away)
				end
				if away then afk = Econ.AFK_RATE end
			end
			if s and cash and s.rate > 0 then
				local earned = math.floor(s.rate * boostOf(s) * (s.share or 1) * afk)
				cash.Value += earned
				s.valuation = (s.valuation or 0) + earned
				s.earned = (s.earned or 0) + earned
				if s.earned >= CFG.MILESTONE_BASE * 10 ^ (s.milestones or 0) then checkMilestones(player, s) end
				s.effective = earned
			elseif s then
				s.effective = 0
			end
			if s then
				-- WORK: seated people fill the product bar, tier-weighted
				local work = 0
				for _, r in ipairs(s.rigs or {}) do
					if r.seated then
						work += CFG.TIER_RATE[r.tier or 1] / 2
						r.seatedTime = (r.seatedTime or 0) + 1 + CFG.ALUMNI_STEP * math.min(s.alumni or 0, CFG.ALUMNI_CAP)
						local want = math.min(#CFG.TIER_TITLE, 1 + math.floor(r.seatedTime / CFG.PROMOTE_EVERY))
						if want > (r.tier or 1) then
							r.tier = want
							StaffRig.setTitle(r.rig, titleOf(r))
							StaffRig.say(r.rig, "Promoted to " .. CFG.TIER_TITLE[want] .. "!")
							recompute(player)
						end
					end
				end
				s.work = (s.work or 0) + work * afk * (1 + (Econ and Econ.WAFERS and (s.labs or 0) * 0.15 or 0))      -- AFK: products slow too; v4.6 AI Labs speed them
				s.workNeed = s.workNeed or CFG.WORK_FIRST
				player:SetAttribute("ProductProgress", math.clamp(s.work / s.workNeed, 0, 1))
				s.playtime = (s.playtime or 0) + 1
			end
		end
	end
end)

-- ============ COMPANY NAME ============

local TextService = game:GetService("TextService")

local function cleanName(player, raw)
	if type(raw) ~= "string" then return nil end
	raw = raw:gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 20)
	if #raw < 2 then return nil end
	local ok, filtered = pcall(function()
		local r = TextService:FilterStringAsync(raw, player.UserId)
		return r:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or not filtered then return nil end
	if filtered:find("#") then return nil end     -- a hashed word is a refused word
	return filtered
end

local function tickerOf(name)
	local letters = name:upper():gsub("[^A-Z]", "")
	if #letters < 3 then letters = (letters .. "XYZ"):sub(1, 3) end
	return "$" .. letters:sub(1, 4)
end

setName.OnServerEvent:Connect(function(player, raw)
	local s = sessions[player.UserId]
	local plot = plotOf(player)
	if not s or not plot then return end
	-- v3.1: LATER sends "" -- stop waiting for a name (the door used to wait 25 s)
	if raw == "" or raw == nil then s.nameSkipped = true return end
	--[[ A company is named once: the modal only opens while s.name is nil. One
		attempt in flight and one a second, because each one costs a text-filter
		call and a DataStore write, and the write budget is the whole server's:
		the 9 Oct fuzz drained it with renames (280 throttled writes), which is
		the budget every other player's save comes out of. ]]
	if s.name or s.naming or os.clock() < (s.nameNext or 0) then return end
	s.naming, s.nameNext = true, os.clock() + 1
	local name = cleanName(player, raw)                 -- yields
	s.naming = nil
	if plotOf(player) ~= plot or sessions[player.UserId] ~= s then return end
	if not name then askName:FireClient(player, "That name will not work. Try another.") return end
	s.name = name
	s.ticker = tickerOf(name)
	refreshSign(plot)
	popup(plot.desk, name .. " is born.", CFG.GOLD)
	pcall(function()
		if nameStore then nameStore:SetAsync(tostring(player.UserId), name) end
	end)
end)

-- ============ PRODUCTS ============

local function launchProduct(player, plot, market, mod, auto)
	local s = sessions[player.UserId]
	if not s or not plot then return end
	local name = market.names[math.random(1, #market.names)]
	local tier = 1 + (s.compute or 0)
	local spike = market.spike * (mod or 1) * (1 + math.min(s.quality or 0, CFG.QUALITY_CAP)) * (0.8 + 0.2 * tier)
	if s.lastMarket == market.id then s.marketRepeat = (s.marketRepeat or 1) + 1 else s.marketRepeat = 1 end
	s.lastMarket = market.id
	s.pendingMods = nil
	-- the launch only shields the market it was in (v2.5.1: a blanket 5-min
	-- shield plus a launch every ~100 s meant rivals never landed, 0 in 15 min)
	local shape = Econ and Econ.MARKET[market.id]
	if Econ and Econ.V3 then
		shape = nil
		s.launch = nil                   -- v2.7.0: a launch is a payday, not a revenue boost
	else
		s.launch = { t0 = os.clock(), spike = spike * (shape and shape.h or 1), duration = shape and shape.dur or CFG.LAUNCH_DURATION,
			curve = shape and shape.curve, slow = market.slow, marketId = market.id }
	end
	s.launches = (s.launches or 0) + 1
	s.runLaunches = (s.runLaunches or 0) + 1   -- v4.5: this company's launches (the work need)
	if not auto then s.jr = s.jr or {}; s.jr.launched = true end   -- v4.3: the LAUNCH lesson is learned
	--[[ v5.0: a launch you CHOSE pays momentum; the 60-second auto-ship does
		not. An auto-ship is what happens while you are not playing, and
		paying it would reward exactly the behaviour momentum exists to make
		less attractive. ]]
	if not auto then
		local before = s.momentum or 0
		s.momentum = Mom.add(before, "launch")
		if s.momentum > before then
			player:SetAttribute("Momentum", s.momentum)
			refreshHqPad(plot)      -- the price just changed; the pad and WaferPrice have to say so
		end
	end
	Telemetry.step(player, "first_product")
	s.markets[market.id] = true          -- now a rival can come for this market
	s.share = 1                          -- shipping takes the share back
	s.pressure = nil
	s.valuation = (s.valuation or 0) + math.floor(s.rate * 30 * spike)
	-- PAYDAY: a launch is cash, not only a valuation line
	local payday = math.floor(s.rate * (shape and shape.pay or CFG.PAYDAY_SECONDS) * spike * (auto and 0.5 or 1))
	if Econ and Econ.V3 then
		payday = math.floor(s.rate * Econ.LAUNCH_PAY * (1 + 0.1 * (s.compute or 0)) * (auto and 0.5 or 1))
		payday = Prog.capWindfall("launch", payday, nextGoalOf(s, plot))   -- v4.5 the clock
	end
	if Econ and Econ.Inv then payday = math.floor(payday * Econ.Inv.launchMult(player)) end   -- v3.2: a Front Page doubles it
	local cash = cashOf(player)
	if cash and payday > 0 then cash.Value += payday end
	if Econ and Econ.Inv then pcall(Econ.Inv.onLaunch, player, s) end
	s.pendingProduct = nil
	s.work = 0
	s.workNeed = math.floor(CFG.WORK_FIRST * (CFG.WORK_GROWTH ^ ((Econ and Econ.V3) and s.runLaunches or s.launches)))
	-- the room reacts: everyone cheers, one of them says something
	for i, r in ipairs(s.rigs or {}) do
		task.delay(0.1 * i, function() if StaffRig then StaffRig.cheer(r.rig) end end)
	end
	local speaker = s.rigs and s.rigs[math.random(1, math.max(1, #s.rigs))]
	if speaker and StaffRig then StaffRig.say(speaker.rig, "We shipped " .. name .. "!", 4) end
	productReady:FireClient(player, nil)      -- close the picker (auto-ship path too)

	-- v3.4 THE CEREMONY: the brand rocket lifts off this HQ's roof and every
	-- player in the server sees it (RocketClient). Was a neon box floating up.
	local L = CFG.HQ_LEVELS[plot.hq.level]
	local rl = remotes:FindFirstChild("RocketLaunch")
	if rl then
		rl:FireAllClients({ pos = plot.g(0, L.h + (plot.hq.level >= 5 and 1.7 or 0.6), -4).Position, name = name, market = market.name, owner = player.UserId, auto = auto == true })
	end
	popup(plot.hqPad, "LAUNCHED: " .. name, CFG.GOLD)
	if Econ and Econ.V3 then
		if Econ.celebrate then Econ.celebrate:FireClient(player, { kind = "launch", name = name, payday = payday, auto = auto == true }) end
	else toast:FireClient(player, ("%s%s launched! +$%s payday. Revenue x%.1f for %s."):format(
		auto and "AUTO-SHIPPED (half pay): " or "", name, fmt(payday), s.launch.spike + 1,
		s.launch.duration >= 120 and (math.floor(s.launch.duration / 60 + 0.5) .. " min") or (s.launch.duration .. " s"))) end
end

pickMarket.OnServerEvent:Connect(function(player, index)
	local s = sessions[player.UserId]
	local plot = plotOf(player)
	if not s or not plot or not s.pendingProduct then return end
	if type(index) ~= "number" then return end
	local market = s.pendingProduct[index]
	if not market then return end
	s.lastActive = os.clock()
	launchProduct(player, plot, market, s.pendingMods and s.pendingMods[index] or 1, false)
end)

local function offerProduct(player, plot)
	local s = sessions[player.UserId]
	if not s or s.pendingProduct then return end
	if Econ and Econ.V3 then
		-- v2.7.0 one button: the product is ready, launch it. No market picker.
		local m = CFG.MARKETS[math.random(1, #CFG.MARKETS)]
		local picks = { m }
		s.pendingProduct = picks
		s.pendingMods = { 1 }
		local payday = Prog.capWindfall("launch", math.floor((s.rate or 0) * Econ.LAUNCH_PAY * (1 + 0.1 * (s.compute or 0))), nextGoalOf(s, plot))
		-- v3.1: `autoAt` lets the button count down to the half-pay auto-launch
		productReady:FireClient(player, { { name = "LAUNCH!", blurb = m.name .. " app", launch = true, payday = payday, spike = 1,
			autoAt = (s.jr and s.jr.launched) and workspace:GetServerTimeNow() + 60 or nil } })
		-- v4.3: never auto-launch until the player has launched once (his run: five half-pay
		-- auto-launches in 19 min, the verb was never learned)
		task.delay(60, function()
			local s2 = sessions[player.UserId]
			if s2 and s2.pendingProduct == picks and s2.jr and s2.jr.launched then launchProduct(player, plot, m, 1, true) end
		end)
		return
	end
	-- three distinct markets, shuffled
	local pool = table.clone(CFG.MARKETS)
	local picks = {}
	for _ = 1, 3 do table.insert(picks, table.remove(pool, math.random(1, #pool))) end
	s.pendingProduct = picks
	--[[ v2.5.1 A PICK THAT IS A DECISION. The playtest showed GAMES at four
	stars twice: the highest base spike always won, so the menu was a
	correct answer, not a choice. Now each round one card is TRENDING
	(x1.6) and the market you shipped last is SATURATED (x0.7 per repeat),
	so the best card moves every round and farming one market decays. ]]
	local mods, tags = { 1, 1, 1 }, {}
	for i, m in ipairs(picks) do
		if m.id == s.lastMarket then
			mods[i] = 0.7 ^ math.max(1, s.marketRepeat or 1)
			tags[i] = ("SATURATED  x%.1f"):format(mods[i])
		end
	end
	local trendable = {}
	for i in ipairs(picks) do if not tags[i] then table.insert(trendable, i) end end
	if #trendable > 0 then
		local t = trendable[math.random(1, #trendable)]
		mods[t] = 1.6
		tags[t] = "TRENDING  x1.6"
	end
	-- v2.6.2 MARKET FIT: your seated team decides which card is best for you
	local fits = {}
	for i, m in ipairs(picks) do
		local count, fmult, ftext = 0, 1, ""
		if Econ then count, fmult, ftext = Econ.marketFit(m.id, s.rigs, s.compute) end
		mods[i] *= fmult
		fits[i] = { count = count, text = ftext }
	end
	s.pendingMods = mods
	local tier = 1 + (s.compute or 0)
	local grow = (1 + math.min(s.quality or 0, CFG.QUALITY_CAP)) * (0.8 + 0.2 * tier)
	local payload = {}
	for i, m in ipairs(picks) do
		local shape = Econ and Econ.MARKET[m.id]
		local sp = m.spike * mods[i] * grow
		payload[i] = { name = m.name, blurb = m.blurb, spike = mods[i], tag = tags[i],
			good = mods[i] > 1, fit = fits[i].text, fitCount = fits[i].count,
			shape = shape and shape.shape,
			payday = shape and math.floor((s.rate or 0) * shape.pay * sp) or nil,
			boost = shape and (1 + sp * shape.h) or nil,
			minutes = shape and (shape.dur / 60) or nil }
	end
	productReady:FireClient(player, payload)
	popup(plot.hqPad, "PRODUCT READY -- pick a market", CFG.GOLD)
	-- unanswered for 60s: it ships anyway, at half payday. Progress never
	-- waits on a menu, but choosing is worth more than ignoring.
	task.delay(60, function()
		local s2 = sessions[player.UserId]
		if s2 and s2.pendingProduct == picks then launchProduct(player, plot, picks[1], mods[1], true) end
	end)
end

local function productLoop(player, plot)
	task.spawn(function()
		while player.Parent and plotOf(player) == plot do
			local s = sessions[player.UserId]
			if s and not s.pendingProduct and (s.work or 0) >= (s.workNeed or CFG.WORK_FIRST) then
				offerProduct(player, plot)
			end
			task.wait(1)
		end
	end)
end

-- ============ RIVALS ============

-- a rival launches in a market somebody online is actually in; everyone
-- in that market who is not mid-buzz feels it. Returns how many were hit.
local function rivalLaunch(forced)
	if Econ and Econ.V3 and not forced then return 0 end   -- v2.7.0: off
	local inUse = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		local s = sessions[pl.UserId]
		if s and s.shipped then
			for _, m in ipairs(CFG.MARKETS) do
				if s.markets[m.id] then inUse[#inUse + 1] = m end
			end
		end
	end
	local market = forced or inUse[math.random(1, math.max(1, #inUse))]
	if not market then return 0 end
	local rival = CFG.RIVALS[math.random(1, #CFG.RIVALS)]
	local hit = 0
	for _, pl in ipairs(Players:GetPlayers()) do
		local s = sessions[pl.UserId]
		local buzz = s and s.launch and s.launch.marketId == market.id
			and (os.clock() - s.launch.t0) < s.launch.duration
		if s and s.shipped and s.markets[market.id] and pl:GetAttribute("MenuDone") == true and not buzz then
			s.pressure = os.clock()
			s.pressureMarket = market.id
			hit += 1
			Telemetry.step(pl, "first_rival")
			toast:FireClient(pl, ("%s just launched in %s. Your market share is slipping -- ship to take it back.")
				:format(rival, market.name))
			local plot = plotOf(pl)
			if plot then popup(plot.hqPad, "RIVAL LAUNCH: " .. market.name, Color3.fromRGB(255, 120, 120)) end
		end
	end
	return hit
end

task.spawn(function()
	while true do
		task.wait(math.random(CFG.RIVAL_EVERY[1], CFG.RIVAL_EVERY[2]))
		rivalLaunch()
	end
end)

--[[ THE TILT SWEEP (v7). A staff member turned up floating sideways in an
upper-floor ceiling. StaffRig.straighten puts any rig that is unanchored or
tilted back where it belongs; this walks every rig every 8 seconds and calls
it. It only acts when something is actually wrong, so the normal cost is two
property reads per staff member.

Logged on the first fix per server, because a guard that silently hides a bug
is how the bug survives. ]]
task.spawn(function()
	local warned = false
	while true do
		task.wait(8)
		if StaffRig and StaffRig.straighten then
			for _, sess in pairs(sessions) do
				for _, r in ipairs(sess.rigs or {}) do
					if r.rig and r.rig.Parent then
						local ok, fixed = pcall(StaffRig.straighten, r.rig, r.home)
						if ok and fixed and not warned then
							warned = true
							warn("[SV] straightened a tilted staff rig -- see StaffRig.straighten")
						end
					end
				end
			end
		end
	end
end)

-- ============ LIFE IN THE OFFICE ============

local CHATTER = {
	engineer = { "Compiling...", "Found the bug. It was me.", "One more test.", "Ship it.", "Coffee, then code." },
	designer = { "Needs more padding.", "What if it were blue?", "Pixel-perfect or nothing.", "Love this font." },
	sales    = { "Closing a deal!", "They said maybe. That's a yes.", "Big pipeline this week.", "Call me back!" },
	recruiter= { "Found a great candidate.", "Interviews all day.", "We need more desks.", "Culture fit: excellent." },
	research = { "Interesting result.", "Running the numbers.", "Hypothesis confirmed.", "Need more data." },
}
local function chatterLoop(player, plot)
	task.spawn(function()
		while player.Parent and plotOf(player) == plot do
			task.wait(math.random(18, 34))
			local s = sessions[player.UserId]
			if s and s.rigs and #s.rigs > 0 and StaffRig then
				local r = s.rigs[math.random(1, #s.rigs)]
				local pool = CHATTER[r.rig:GetAttribute("Role") or "engineer"] or CHATTER.engineer
				local line = r.seated and pool[math.random(1, #pool)] or "Could use a desk..."
				StaffRig.say(r.rig, line)
			end
		end
	end)
end

-- ============ ACQUISITION OFFERS ============

local function offerLoop(player, plot)
	task.spawn(function()
		while player.Parent and plotOf(player) == plot do
			task.wait(math.random(CFG.OFFER_EVERY[1], CFG.OFFER_EVERY[2]))
			local s = sessions[player.UserId]
			if Econ and Econ.V3 then continue end   -- v2.7.0: poach offers off
			-- v2.5.1: one decision at a time -- no poach offer while a product is waiting
			if not s or s.pendingOffer or s.pendingProduct or not s.rigs then continue end
			-- the best person, if anyone is worth buying
			local best
			for _, r in ipairs(s.rigs) do
				local worth = CFG.TIER_RATE[r.tier or 1] * talentMultOf(r)
				if (r.tier or 1) >= CFG.OFFER_MIN_TIER and (not best or worth > CFG.TIER_RATE[best.tier or 1] * talentMultOf(best)) then best = r end
			end
			if not best then continue end
			-- capped at rehire cost + 60s of the person's output: selling a Lead
			-- and rehiring an intern must never be a money printer (it was: quality
			-- scaled the offer but not the hire)
			local cashNow = cashOf(player)
			local amount = offerAmountOf(s, cashNow and cashNow.Value or 0)
			local loss = math.floor((CFG.TIER_RATE[best.tier] - CFG.TIER_RATE[1]) * hqMultOf(plot))
			local minutes = (s.rate or 0) > 0 and amount / s.rate / 60 or 0
			local id = (s.offerSerial or 0) + 1
			s.offerSerial = id
			s.pendingOffer = { id = id, entry = best, amount = amount, rival = CFG.RIVALS[math.random(1, #CFG.RIVALS)] }
			offerEvent:FireClient(player, {
				id = id, rival = s.pendingOffer.rival, who = best.rig:GetAttribute("PersonName") or "?",
				title = titleOf(best), amount = amount, tier = best.tier, loss = loss, minutes = minutes,
				alumni = math.min(s.alumni or 0, CFG.ALUMNI_CAP), step = CFG.ALUMNI_STEP,
			})
			StaffRig.say(best.rig, s.pendingOffer.rival .. " keeps calling me...", 5)
			task.delay(30, function()
				local s2 = sessions[player.UserId]
				if s2 and s2.pendingOffer and s2.pendingOffer.id == id then s2.pendingOffer = nil end
			end)
		end
	end)
end

answerOffer.OnServerEvent:Connect(function(player, id, accept)
	local s = sessions[player.UserId]
	local plot = plotOf(player)
	local cash = cashOf(player)
	if not s or not plot or not cash or not s.pendingOffer or s.pendingOffer.id ~= id then return end
	local o = s.pendingOffer
	s.pendingOffer = nil
	if accept ~= true then
		StaffRig.say(o.entry.rig, "Told them no. I like it here.", 4)
		return
	end
	-- the sale: money in, person out, the line re-seats
	for i, r in ipairs(s.rigs) do
		if r == o.entry then table.remove(s.rigs, i) break end
	end
	StaffRig.say(o.entry.rig, "It's been real. Off to " .. o.rival .. "!", 3)
	local rig = o.entry.rig
	task.delay(3, function() if rig.Parent then rig:Destroy() end end)
	s.staff = math.max(0, s.staff - 1)
	cash.Value += o.amount
	s.valuation = (s.valuation or 0) + math.floor(o.amount / 2)
	s.alumni = math.min((s.alumni or 0) + 1, CFG.ALUMNI_CAP)
	player:SetAttribute("Alumni", s.alumni)
	assignDesks(player)
	recompute(player)
	updateHirePad(player)
	toast:FireClient(player, ("+$%s from %s. ALUMNI x%d: your team gets promoted %d%% faster."):format(
		fmt(o.amount), o.rival, s.alumni, math.floor(s.alumni * CFG.ALUMNI_STEP * 100 + 0.5)))
end)

setMuted.OnServerEvent:Connect(function(player, v)
	local s = sessions[player.UserId]
	if s then s.muted = v == true end
end)

-- ============ IPO + THE TICKER ============

--[[ v4.3 GO PUBLIC: the capstone of every company. It used to happen silently
at a $250K valuation (early HQ 2), so "going public" was never a moment. Now
HQ 5 hands you a GO PUBLIC button: ring the bell, list on the Valley Exchange,
raise Journey.IPO_RAISE seconds of income, everyone in the server hears it,
and only THEN can the company spin off. Each new company goes public again. ]]
goPublic = function(player, plot)
	local s = sessions[player.UserId]
	if not s or not plot or plotOf(player) ~= plot or s.listed then return end
	if Econ and Econ.WAFERS and plot.wafer then
		if plot.wafer.level < Econ.Wafers.Plan.blueprint(s.spinoffs or 0) then return end   -- v4.6: the top of the blueprint
	elseif plot.hq.level < #CFG.HQ_LEVELS then return end
	s.listed = true
	s.ipo = true
	s.ticker = tickerOf(s.name or "Startup")
	local raise = Prog.capWindfall("gopublic", math.floor((s.rate or 0) * Journey.IPO_RAISE), spinoffCostOf(s))   -- v4.5 the clock
	local cash = cashOf(player)
	if cash then cash.Value += raise end
	refreshSign(plot)
	refreshHqPad(plot)
	toast:FireAllClients(("%s (%s) just went PUBLIC on the Valley Exchange!"):format(s.name or "A startup", s.ticker), "news")
	if Econ and Econ.celebrate then
		Econ.celebrate:FireClient(player, { kind = "ipo", ticker = s.ticker, name = s.name or "Your startup", raise = raise })
	end
	pcall(Telemetry.event, player, "ipo", s.spinoffs or 0)
	refreshObjective(player)
end
goPublicRemote.OnServerEvent:Connect(function(player)
	local plot = plotOf(player)
	if plot then goPublic(player, plot) end
end)

local function checkIPO(player, plot)
	local s = sessions[player.UserId]
	if not s or s.ipo or (s.valuation or 0) < CFG.IPO_AT then return end
	if not s.name then return end          -- a nameless company cannot list
	s.ipo = true
	s.ticker = tickerOf(s.name)
	refreshSign(plot)
	toast:FireAllClients(("%s (%s) just went PUBLIC at $%s valuation!"):format(s.name, s.ticker, fmt(s.valuation)), "news")
	popup(plot.hqPad, "PUBLICLY TRADED", CFG.GOLD)
end

local function pushTicker(player)
	-- v4.2: Ranks owns the boards (every company from $1K, plus the weekly board)
	if Econ and Econ.Ranks and Econ.Ranks.pushPlayer then Econ.Ranks.pushPlayer(player) return end
	-- Studio test saves (scenario cash) must never reach the live board
	if game:GetService("RunService"):IsStudio() then return end
	local s = sessions[player.UserId]
	if not s or not s.ipo then return end
	pcall(function()
		if tickerStore then tickerStore:SetAsync(tostring(player.UserId), math.floor(s.valuation or 0)) end
	end)
end

--[[ THE BOARD, two-sided, top ten public companies across all servers.

v9: it used to stand at (0, ROAD_Z + 30), which was beside the old straight
road. That spot is now the middle of the central park, so the board was planted
on top of the fountain and hid the monument completely. It stands on the
ARRIVAL axis instead, in the gap between the park kerb and the inner ring road,
so you read it on the walk in from the gate. ]]
local board
do
	local BOARD_R = ((CampusHub and CampusHub.R_PARK) or 162) + 23
	local boardCF = CFrame.new(BOARD_R, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
	local post = part({ Name = "TickerPost", Size = Vector3.new(1.2, 12, 1.2), CFrame = boardCF * CFrame.new(0, 6, 0),
		Color = CFG.TRIM }, world)
	board = part({ Name = "TickerBoard", Size = Vector3.new(30, 12, 0.8), CFrame = boardCF * CFrame.new(0, 16, 0),
		Color = Color3.fromRGB(16, 18, 24), Material = Enum.Material.SmoothPlastic }, world)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 24
		sg.Parent = board
		local head = Instance.new("TextLabel")
		head.Size = UDim2.new(1, 0, 0, 60)
		head.BackgroundTransparency = 1
		head.Text = "VALLEY EXCHANGE  ·  TOP COMPANIES"
		head.TextColor3 = CFG.GOLD
		head.TextSize = 34
		head.Font = Enum.Font.FredokaOne
		head.Parent = sg
		local list = Instance.new("TextLabel")
		list.Name = "List"
		list.Position = UDim2.new(0, 24, 0, 66)
		list.Size = UDim2.new(1, -48, 1, -76)
		list.BackgroundTransparency = 1
		list.Text = "No company has gone public yet. Reach HQ 5 and ring the bell."
		list.TextColor3 = Color3.fromRGB(236, 240, 246)
		list.TextSize = 26
		list.Font = Enum.Font.GothamMedium
		list.TextXAlignment = Enum.TextXAlignment.Left
		list.TextYAlignment = Enum.TextYAlignment.Top
		list.TextWrapped = true
		list.Parent = sg
	end
end

-- AI rivals grow with uptime but never run away: capped just above the best
-- human so the top of the board is always reachable
local function rivalValuation(r, bestHuman)
	local minutes = (os.clock() - serverStart) / 60
	local cap = math.max(bestHuman * CFG.RIVAL_CAP_MULT, CFG.PUBLIC_RIVALS[#CFG.PUBLIC_RIVALS].base)
	return math.floor(math.min(r.base * (CFG.RIVAL_GROWTH ^ minutes), cap))
end

local bestHumanSeen = 0
local function refreshBoard()
	-- v4.2: the Ranks cache when it is there: the same all-time top 10 as the
	-- RANKS panel, AI rivals tagged (no extra DataStore reads)
	local rc = Econ and Econ.Ranks and Econ.Ranks.board and Econ.Ranks.board.cache
	if rc and rc.all then
		local lines = {}
		for i, e in ipairs(rc.all) do
			if not e.ai then bestHumanSeen = math.max(bestHumanSeen, e.value) end
			if i <= 10 then lines[i] = ("%2d.  %-18s %s $%s"):format(i, e.name:sub(1, 18), e.ai and "AI" or "  ", fmt(e.value)) end
		end
		local txt = #lines > 0 and table.concat(lines, "\n") or "No companies yet. Yours could be first."
		for _, sg in ipairs(board:GetChildren()) do
			local l = sg:FindFirstChild("List")
			if l then l.Text = txt end
		end
		return
	end
	local entries = {}
	pcall(function()
		if not tickerStore then return end
		local page = tickerStore:GetSortedAsync(false, 10):GetCurrentPage()
		for _, entry in ipairs(page) do
			local nm = "?"
			pcall(function() nm = nameStore and nameStore:GetAsync(entry.key) or nm end)
			-- a live player's freshest name wins over the stored one
			for _, pl in ipairs(Players:GetPlayers()) do
				local s = sessions[pl.UserId]
				if tostring(pl.UserId) == entry.key and s and s.name then nm = s.name end
			end
			entries[#entries + 1] = { name = nm, ticker = tickerOf(nm), value = entry.value }
			bestHumanSeen = math.max(bestHumanSeen, entry.value)
		end
	end)
	for _, r in ipairs(CFG.PUBLIC_RIVALS) do
		entries[#entries + 1] = { name = r.name, ticker = r.ticker, value = rivalValuation(r, bestHumanSeen) }
	end
	table.sort(entries, function(a, b) return a.value > b.value end)
	local rows = {}
	for i = 1, math.min(10, #entries) do
		local e = entries[i]
		rows[i] = ("%2d.  %-18s %-6s  $%s"):format(i, e.name:sub(1, 18), e.ticker, fmt(e.value))
	end
	local text = table.concat(rows, "\n")
	for _, sg in ipairs(board:GetChildren()) do
		local l = sg:FindFirstChild("List")
		if l then l.Text = text end
	end
end

-- v4.2 RANKS (the HUD leaderboard, ServerScriptService.Ranks). Wired HERE, not
-- with the other modules: its rivals() closure needs rivalValuation and
-- bestHumanSeen, which are defined just above (a closure made earlier would
-- see nil globals). No new top-level locals: this file is at Luau's limit.
if Econ then
	Econ.Ranks = tryRequire(ServerScriptService, "Ranks")
	if Econ.Ranks and Econ.Ranks.init then
		local ok, err = pcall(Econ.Ranks.init, {
			session = function(p) return sessions[p.UserId] end,
			allStore = tickerStore,
			nameOf = function(key) return nameStore and nameStore:GetAsync(key) end,
			rivals = function()
				local t = {}
				for _, r in ipairs(CFG.PUBLIC_RIVALS) do table.insert(t, { name = r.name, value = rivalValuation(r, bestHumanSeen) }) end
				return t
			end,
			toast = function(p, text) toast:FireClient(p, text) end,
		})
		if not ok then warn("[SV] Ranks init failed: " .. tostring(err)); Econ.Ranks = nil end
	else
		Econ.Ranks = nil
	end
end

-- v4.9 THE VALLEY: the other five founders, made visible (see Valley.lua).
-- Lives here because this is where plotsFolder, sessions, plotOf, cashOf,
-- toast, fmt and Econ.Wafers are all in scope at once.
do
	local Valley = tryRequire(ServerScriptService, "Valley")
	if Valley and Valley.init then
		local ok, err = pcall(Valley.init, {
			plots = plotsFolder,
			session = function(p) return sessions[p.UserId] end,
			-- the save read is over (ok or failed), so the session's valuation is real, not the join-time 0
			loadDone = function(p) return not loading[p.UserId] end,
			plotOf = plotOf,
			cash = cashOf,
			fmt = fmt,
			toast = function(text, kind) toast:FireAllClients(text, kind or "news") end,
			level = function(plot) return Econ and Econ.Wafers and Econ.Wafers.level(plot) or 1 end,
		})
		if not ok then warn("[SV] Valley init failed: " .. tostring(err)) end
		-- no handle kept on purpose: SiliconCore is at the 200 top-level local
		-- limit, and require() is cached, so a test just requires Valley again.
	end
end

task.spawn(function()
	while true do
		for _, pl in ipairs(Players:GetPlayers()) do
			local plot = plotOf(pl)
			if plot then
				if not (Econ and Econ.Ranks) then pushTicker(pl) end   -- v4.2: the Ranks loop pushes every minute
			end
			-- OVERTAKE: the first time your valuation passes a rival, everyone hears
			local s = sessions[pl.UserId]
			if s then
				for _, r in ipairs(CFG.PUBLIC_RIVALS) do
					local v = rivalValuation(r, bestHumanSeen)
					if (s.valuation or 0) > v then
						if s.above[r.name] == nil and s.aboveInit then
							toast:FireAllClients(("%s just overtook %s on the Valley Exchange ($%s)."):format(
								s.name or (pl.Name .. "'s startup"), r.name, fmt(s.valuation)), "news")
						end
						s.above[r.name] = true
					end
				end
				s.aboveInit = true       -- rivals already below you on join do not toast
			end
		end
		refreshBoard()
		task.wait(45)
	end
end)

-- ============ SAVE / LOAD ============
-- v4.2: the code lives in SaveLoad.lua (moved out to free SiliconCore's top-level
-- locals). It still runs here, at the same point in the load order.
local SaveLoad = require(ServerScriptService:WaitForChild("SaveLoad"))({
	Journey = Journey,
	Prog = Prog,
	Mom = Mom,
	CFG = CFG,
	CampusArch = CampusArch,
	Econ = Econ,
	FurnitureKit = FurnitureKit,
	Players = Players,
	SPINOFF_BASE = SPINOFF_BASE,
	StaffRig = StaffRig,
	WING_MAX_LEVEL = WING_MAX_LEVEL,
	applyWingLevel = applyWingLevel,
	buildShell = buildShell,
	buildWing = buildWing,
	cashOf = cashOf,
	hireGrowthAt = hireGrowthAt,
	loaded = loaded,
	loading = loading,
	milestonesFromEarned = milestonesFromEarned,
	officeDesk = officeDesk,
	placeAt = placeAt,
	plotOf = plotOf,
	pushTicker = pushTicker,
	recompute = recompute,
	refreshHqPad = refreshHqPad,
	refreshSign = refreshSign,
	refreshWingPrompt = refreshWingPrompt,
	saveStore = saveStore,
	sessions = sessions,
	spawnStaff = spawnStaff,
	tickerOf = tickerOf,
	titleOf = titleOf,
	updateHirePad = updateHirePad,
})

-- ============ PLAYERS ============

-- v4.1: a do-block, so the handler has a name without a new top-level local
-- (this file sits at Luau's 200-local limit)
do
local function onJoin(player)
	Telemetry.joined(player)
	local plot = assignPlot(player)
	sessions[player.UserId] = {
		clicks = 0, shipped = false, rate = 0,
		staff = 0, desks = 0, hireCost = CFG.HIRE_BASE,
		quality = 0, morale = 0, compute = 0,
		buildUnlocked = false,
		placed = {}, placedDesks = 0, placedMorale = 0, rigs = {},
		share = 1, markets = {}, above = {},
		plot = plot,
	}
	if not plot then warn("[SV] no free plot for " .. player.Name) end

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	ls.Parent = player
	local cash = Instance.new("IntValue"); cash.Name = "Cash"; cash.Value = CFG.START_CASH; cash.Parent = ls
	local rate = Instance.new("IntValue"); rate.Name = "Per Sec"; rate.Parent = ls
	local staff = Instance.new("IntValue"); staff.Name = "Staff"; staff.Parent = ls
	local val = Instance.new("IntValue"); val.Name = "Valuation"; val.Parent = ls

	-- load BEFORE the beats so a returning player's campus is standing when
	-- the intro camera arrives
	if plot then SaveLoad.loadOnce(player, plot) end
	if plot then productLoop(player, plot); chatterLoop(player, plot); offerLoop(player, plot) end
	do
		local s = sessions[player.UserId]
		menuStats:FireClient(player, {
			cash = cash.Value, valuation = math.floor(s and s.valuation or 0), staff = s and s.staff or 0,
			launches = s and s.launches or 0, name = s and s.name, ipo = s and s.ipo or false,
			playtime = math.floor(s and s.playtime or 0), muted = s and s.muted or false,
			returning = player:GetAttribute("Returning") == true, hq = plot.hq.level,
		})
	end

	-- v2.5.1: the name modal is asked in the unlock sequence below, in the
	-- quiet beat after the first hire (it used to land on top of the new
	-- objective the instant the first product shipped)

	-- belt and braces: RespawnLocation handles it, and if the character got
	-- in first it is moved into the garage anyway
	local function toGarage(char)
		local p = plotOf(player)
		if p then
			task.wait()
			char:PivotTo(p.spawn.CFrame * CFrame.new(0, 3, 0))
		end
	end
	player.CharacterAdded:Connect(toGarage)
	-- v4.2: ...including the character that is ALREADY here. A player who
	-- arrives while the world is still building is caught up by onJoin after
	-- their first character spawned at the hub, and CharacterAdded never fires
	-- for it: a fresh save stood outside a garage whose door is shut until the
	-- first app ships (his report, 28 Sep).
	if player.Character then task.spawn(toGarage, player.Character) end

	task.spawn(function()
		while player.Parent do
			local s = sessions[player.UserId]
			if s then
				rate.Value = s.effective or s.rate
				staff.Value = s.staff
				val.Value = math.floor(s.valuation or 0)
				refreshObjective(player)
				updateHirePad(player)      -- v2.5.1: the pad price follows income (it went stale: $40 vs $60)
			end
			task.wait(0.4)
		end
	end)

	-- the beat driver: one verb at a time, each rewarded before the next
	task.spawn(function()
		if not plot then return end
		while player.Parent do
			local s = sessions[player.UserId]
			if s and s.shipped then break end
			task.wait(0.3)
		end
		if not player.Parent then return end
		updateHirePad(player)
		while player.Parent do
			local s = sessions[player.UserId]
			if s and s.staff >= 1 then break end
			task.wait(0.3)
		end
		if not player.Parent then return end
		task.wait(1.5)
		local s0 = sessions[player.UserId]
		if s0 and not s0.name then
			askName:FireClient(player, "")
			-- the door waits for the name (or 25 s), so nothing new appears under the modal
			local t0 = os.clock()
			while player.Parent and os.clock() - t0 < 25 do
				local s1 = sessions[player.UserId]
				if not s1 or s1.name or s1.nameSkipped then break end
				task.wait(0.3)
			end
			task.wait(1.5)
		else
			task.wait(4.5)
		end
		local s = sessions[player.UserId]
		if not s or plotOf(player) ~= plot then return end
		s.buildUnlocked = true
		openDoor(plot)
		for _, slot in ipairs(plot.slots) do
			if not slot.built then
				slot.prompt.Enabled = true
				slot.text.Text = "BUILD HERE"
			end
		end
		-- v3.1: no floating sentence; the guide card already says where to go
	end)
end
Players.PlayerAdded:Connect(onJoin)
-- v4.1: the world build yields (ValleyGen.buildLowPoly pauses every few rows so
-- the server never hitches), so a player can arrive before the line above runs,
-- and PlayerAdded never fires for them: no plot, no leaderstats, no game.
-- Measured in Studio Play, 28 Sep. Catch them up.
for _, pl in ipairs(Players:GetPlayers()) do task.spawn(onJoin, pl) end
end

Players.PlayerRemoving:Connect(function(player)
	local plot = plotOf(player)
	local mine = sessions[player.UserId]
	Telemetry.left(player)
	SaveLoad.saveNow(player)          -- yields (DataStore)
	pushTicker(player)       -- yields (DataStore)
	-- if the same user reconnected during those yields, PlayerAdded already
	-- built a new session; deleting it here would soft-lock them until relog
	if sessions[player.UserId] ~= mine then return end
	sessions[player.UserId] = nil
	loaded[player.UserId] = nil
	if plot then releasePlot(plot) end
end)

-- v1.3: the starter screen is gone (every top tycoon drops you straight in).
-- The client still fires this once on load; the server owns the attribute.
menuDone.OnServerEvent:Connect(function(player)
	if player:GetAttribute("MenuDone") then return end
	player:SetAttribute("MenuDone", true)
	Telemetry.step(player, "play")
end)

clientInfo.OnServerEvent:Connect(function(player, isMobile)
	Telemetry.platform(player, isMobile == true)
	-- v5: the journey words its instructions for the device ("Tap CAR" vs "Press C");
	-- it read st.touch, which nothing ever set, so every phone was told to press C
	player:SetAttribute("Touch", isMobile == true)
end)

-- ============ STUDIO-ONLY DEV HOOK ============
-- v4.2: the code lives in DevHook.lua. Studio only, same load point.
if game:GetService("RunService"):IsStudio() then
	require(ServerScriptService:WaitForChild("DevHook"))({
		coreScript = script,
		goPublic = function(p, pl) return goPublic(p, pl) end,
		CFG = CFG,
		Econ = Econ,
		SaveLoad = SaveLoad,
		StaffRig = StaffRig,
		boostOf = boostOf,
		buildWing = buildWing,
		capacityOf = capacityOf,
		cashOf = cashOf,
		checkIPO = checkIPO,
		checkMilestones = checkMilestones,
		deskHomes = deskHomes,
		hire = hire,
		hqMultOf = hqMultOf,
		hqCostOf = hqCostOf,
		wafersNext = wafersNext,
		refreshHqPad = refreshHqPad,
		launchProduct = launchProduct,
		loaded = loaded,
		offerAmountOf = offerAmountOf,
		offerEvent = offerEvent,
		offerProduct = offerProduct,
		placeAt = placeAt,
		plotOf = plotOf,
		recompute = recompute,
		refreshSign = refreshSign,
		rivalLaunch = rivalLaunch,
		saveStore = saveStore,
		sessions = sessions,
		spinOff = spinOff,
		spinoffCostOf = spinoffCostOf,
		tickerOf = tickerOf,
		titleOf = titleOf,
		tryUpgrade = tryUpgrade,
		updateHirePad = updateHirePad,
		upgradeWing = upgradeWing,
		wingMaxed = wingMaxed,
		writeCode = writeCode,
	})
end

-- ============ LIGHTING ============

local Lighting = game:GetService("Lighting")
Lighting.ClockTime = 15.2
Lighting.Brightness = 2.2
Lighting.Ambient = Color3.fromRGB(92, 90, 96)
Lighting.OutdoorAmbient = Color3.fromRGB(128, 132, 140)
do
	local old = Lighting:FindFirstChild("SVBloom")
	if old then old:Destroy() end
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "SVBloom"
	bloom.Intensity = 0.4
	bloom.Threshold = 1.6
	bloom.Size = 20
	bloom.Parent = Lighting
	for _, n in ipairs({ "Bloom", "SunRays", "ColorCorrection" }) do
		local e = Lighting:FindFirstChild(n)
		if e then e.Enabled = false end
	end
	--[[
		THE SKY. The template sky has a grey-white lower half that shows as a
		dead band wherever terrain is culled (low graphics quality). "Sunny Sky
		1" (Creator Store 14717594261, free, verified script-free on the card
		shop) has a real horizon. Faces written here so the place file cannot
		lose them.
	]]
	for _, oldSky in ipairs(Lighting:GetChildren()) do
		if oldSky:IsA("Sky") then oldSky:Destroy() end
	end
	-- v3.6 (PLAN v6 V6): the valley's own sky, rendered in Blender (blender/sky.py +
	-- sky_post.py): a clear California blue, a warm haze at the horizon, flat-bottomed
	-- cumulus riding just above the hills, no painted sun (the game's sun moves).
	-- Face slots were measured in Studio, not assumed: Rt is -X, Lf is +X.
	-- Rollback, "Sunny Sky 1": Up 14717581432 Dn 14717567172 Lf 14717573189
	-- Rt 14717577380 Ft 14717569115 Bk 14717565621
	-- v4.1 (style B): a clean gradient, no painted clouds (blender/lp_sky.py). Colour
	-- is a function of elevation only, so the four sides are one image. The faceted
	-- clouds are real objects (ValleyGen.buildLowPoly). Rollback, the v3.6 sky:
	-- Up 102168875629160 Dn 75343774974248 Lf 72836466733855 Rt 138882095629253
	-- Ft 75537082085995 Bk 121291280517397
	local sky = Instance.new("Sky")
	local SIDE = "rbxassetid://100786682614862"
	sky.SkyboxUp = "rbxassetid://118067508490888"
	sky.SkyboxDn = "rbxassetid://77470848635822"
	sky.SkyboxLf = SIDE
	sky.SkyboxRt = SIDE
	sky.SkyboxFt = SIDE
	sky.SkyboxBk = SIDE
	sky.CelestialBodiesShown = true

	--[[ THE BIG SUN (v8, cartoon). A flat yellow disc with a hard rim and a
	deeper-orange outline around it.

	It is the REAL sun, restyled, not a sun painted into the skybox. The game
	runs a 22-minute day/night cycle (SkyClient moves ClockTime), so a painted
	sun would sit still while the light moved and would still be hanging there
	at midnight. Restyling Roblox's own sun keeps the track across the sky, the
	set behind the hills, and the shadow direction, for free.

	SunAngularSize 11 -> 46. The default sun is a bright speck; at 46 degrees it
	is a landmark you compose shots against.

	v7 was the LA travel poster: pale cream, soft rim, wide halo. It read as
	NATURAL, which is what it was aimed at and the wrong target -- the rest of
	the world is flat-shaded with hard facets, so one photographic glow in the
	sky was the only soft thing on screen. v8 keeps the size and changes the
	three things that make a sun read as drawn: an OUTLINE (the strongest cue),
	a HARD edge instead of a falloff, and a flat saturated fill instead of
	cream. The halo survives, much tighter, because with no bleed at all the
	disc sits ON the sky rather than in it.

	Rays and a two-tone inner circle were both built and rejected: rays read as
	clipart once the sun tracks across the hills, and the inner circle is a
	second concentric shape that means nothing.

	THE SUN IS NOT DRAWN HERE ANY MORE. Measured in game: the celestial-body
	shader multiplies the texture up and clips, so the colour is discarded and
	only the alpha survives -- a four-quadrant test at 18/28/40/55% of the
	target yellow rendered identically, and the outline vanished. Bloom,
	SunRays and Atmosphere.Glare were all off for that test, so it is the sun
	shader, not post-processing. SkyClient draws both discs as BillboardGuis
	instead, placed along the real GetSunDirection()/GetMoonDirection() so they
	still track, still set behind the hills and still match the shadows.

	AngularSize 0 hides Roblox's own discs so there is only one sun. The light
	itself is unaffected: it comes from ClockTime and GeographicLatitude, not
	from the sprite. The texture ids stay here because they are the same images
	SkyClient uses, and because setting a size back above 0 is the one-line way
	to see the engine version again.
	Generated by art/sun.py -- see art/out/sun_variants.png for the three
	shapes that were compared. ]]
	sky.SunTextureId = "rbxassetid://124848074435225"
	sky.SunAngularSize = 0
	sky.MoonTextureId = "rbxassetid://135660990906962"
	sky.MoonAngularSize = 0
	sky.Parent = Lighting

	local atm = Lighting:FindFirstChild("Atmosphere")
	if atm then
		-- thin: the far range is ~1000 studs out and must READ from the road.
		-- 0.32 dissolved everything past 300 studs into blue (measured).
		-- measured: 0.11 still fogged the range flat at 800 studs. 0.045 keeps
		-- depth haze and lets the crests read from every garage door.
		atm.Density = 0.045
		atm.Haze = 0.7
		-- v3.3 a warm valley haze: golden hills fade into it instead of into blue-grey
		atm.Color = Color3.fromRGB(214, 210, 200)
		atm.Decay = Color3.fromRGB(140, 152, 172)
	end
end

if FlatLook then
	local flattened = FlatLook.sweep(workspace)
	FlatLook.watch(workspace)       -- plots rebuild all game, so a one-shot sweep goes stale
	print(("[SV] flat look: %d parts flattened, watching for more"):format(flattened))
end
print(("SILICON VALLEY TYCOON -- %d plots on the road, heightmap valley, downtown east."):format(#plots))
