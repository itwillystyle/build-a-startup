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
local Econ = tryRequire(ServerScriptService, "RoomEconomy")   -- v2.6.0 room economy (stations, caps, fit, wages)
if not Telemetry then
	local noop = function() end
	Telemetry = { joined = noop, step = noop, platform = noop, event = noop, left = noop }
end
if FurnitureKit then
	local have, missing = FurnitureKit.report()
	print(("[SV] FurnitureKit: %d/20 meshes present"):format(have))
	if #missing > 0 then print("[SV] not imported: " .. table.concat(missing, ", ")) end
end

-- ============ CONFIG ============

local START_CASH = 0
local CODE_REWARD = 5
local CLICKS_TO_SHIP = 3
local INTERN_RATE = 2
local GARAGE_DESKS = 1

local FLOOR = Color3.fromRGB(78, 76, 74)
local WALL = Color3.fromRGB(196, 190, 180)
local TRIM = Color3.fromRGB(52, 56, 66)
local ACCENT = Color3.fromRGB(90, 170, 255)
local GOOD = Color3.fromRGB(90, 210, 130)
local GOLD = Color3.fromRGB(255, 208, 70)
local BAD = Color3.fromRGB(255, 140, 140)

local ROLE_ORDER = { "engineer", "engineer", "designer", "sales", "engineer",
	"research", "designer", "recruiter" }

local ROOMS = {
	-- v2.8: blurbs say what the room does under the V3 economy (rooms come
	-- furnished; the old "(B)" and "unlocks KITCHEN" lines described build mode)
	{ id = "office", name = "OPEN OFFICE", cost = 100,
	  blurb = "Seats 2 more people", desks = 2,
	  color = Color3.fromRGB(206, 200, 190), accent = ACCENT },
	{ id = "servers", name = "SERVER ROOM", cost = 350,
	  blurb = "Bigger launch paydays", compute = 1,
	  color = Color3.fromRGB(70, 74, 86), accent = Color3.fromRGB(120, 240, 200) },
	{ id = "studio", name = "DESIGN STUDIO", cost = 800,
	  blurb = "+25% money for your company", quality = 0.25,
	  color = Color3.fromRGB(224, 196, 150), accent = Color3.fromRGB(255, 150, 190) },
	{ id = "cafe", name = "CAFETERIA", cost = 1500,
	  blurb = "+20% money, seats 4", morale = 0.20,
	  color = Color3.fromRGB(196, 150, 110), accent = GOLD },
}
local ROOM_BY_ID = {}
for _, r in ipairs(ROOMS) do ROOM_BY_ID[r.id] = r end
-- v2.7.0: HQ prices come from RoomEconomy when V3 is on (applied after the table below)

local HQ_LEVELS = {
	{ name = "GARAGE",         w = 36, d = 30, h = 14, cost = 0 },
	-- v4.0: the lots moved out to +-92 in v3.2, so the HQ can grow wider as it
	-- grows up (blender/hq2.py). Every level is a finished building.
	{ name = "STARTUP OFFICE", w = 56, d = 44, h = 20, cost = 2500 },
	{ name = "TECH HQ",        w = 72, d = 52, h = 28, cost = 25000 },
	{ name = "GLASS TOWER",    w = 84, d = 56, h = 44, cost = 150000 },
	{ name = "CAMPUS HQ",      w = 96, d = 56, h = 60, cost = 1000000 },
}
if Econ and Econ.V3 then for i, c in ipairs(Econ.HQ_COST) do if HQ_LEVELS[i] then HQ_LEVELS[i].cost = c end end end

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
local HQ_MULT = { 1, 1.6, 2.6, 4.2, 7 }   -- revenue AND price multiplier per HQ level
local HIRE_BASE = 40
local HIRE_GROWTH = 1.3                   -- was 1.6: hire 20 cost $487K, hire 25 $5M
local WING_STEP = 0.5                     -- each wing already built raises the next by 50%
local FURNITURE_INFLATION = 0.08          -- per item already placed
local PAYDAY_SECONDS = 45                 -- a launch pays this many seconds of income, x spike

local function hqMultOf(plot)
	return HQ_MULT[plot and plot.hq and plot.hq.level or 1] or 1
end
--[[
	v2.4 SPIN-OFF (prestige) + MILESTONE LADDER -- the sink after HQ 5.
	Spin-off: at HQ 5, pay SPINOFF_BASE x SPINOFF_GROWTH^n, reset to the
	garage with $0, keep a permanent +SPINOFF_STEP revenue multiplier per
	spin-off (Sell Lemons' Rebirth shape: the reset BUYS a multiplier).
	Milestones: every power of ten of lifetime earnings past MILESTONE_BASE
	is +MILESTONE_STEP revenue forever. Saved: spinoffs (int), earned (int).
	milestones is DERIVED from earned at load, never trusted from a save.
]]
local SPINOFF_BASE = (Econ and Econ.V3) and Econ.SPINOFF_BASE or 5000000
local SPINOFF_GROWTH = 2.5
local SPINOFF_STEP = 0.5
local SPINOFF_CAP = 20
local MILESTONE_BASE = 10000
local MILESTONE_STEP = 0.02
local MILESTONE_MAX = 12
local ROMAN = { "", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX", "XXI" }
local function spinMultOf(s) return 1 + SPINOFF_STEP * (s and s.spinoffs or 0) end
local function milestoneMultOf(s) return 1 + MILESTONE_STEP * (s and s.milestones or 0) end
local function spinoffCostOf(s) return math.floor(SPINOFF_BASE * (SPINOFF_GROWTH ^ (s and s.spinoffs or 0))) end
local function milestonesFromEarned(earned)
	if (earned or 0) < MILESTONE_BASE then return 0 end
	return math.min(MILESTONE_MAX, math.floor(math.log10(earned / MILESTONE_BASE)) + 1)
end
local function companyLabel(s)
	local n = s and s.name or ""
	local k = s and s.spinoffs or 0
	return k > 0 and (n .. " " .. (ROMAN[k + 1] or tostring(k + 1))) or n
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
	if Econ and Econ.V3 then return math.floor(s.hireCost) end   -- v2.7.0: a fixed ladder you outgrow
	return math.max(math.floor(s.hireCost * hqMultOf(plot)), math.floor((s.rate or 0) * 15))
end
local function wingCostOf(room, plot, rate)
	local built = 0
	for _, slot in ipairs(plot.slots or {}) do if slot.built then built += 1 end end
	if Econ and Econ.V3 then return math.floor(room.cost * (Econ.WING_GROWTH ^ built)) end
	local base = math.floor(room.cost * hqMultOf(plot) * (1 + WING_STEP * built))
	-- v2.6.4: never cheaper than N seconds of this company's income
	local secs = Econ and Econ.WING_SECONDS and Econ.WING_SECONDS[room.id] or 0
	return math.max(base, math.floor((rate or 0) * secs))
end
local function furniturePriceOf(item, s, plot)
	local mult = hqMultOf(plot) * (1 + FURNITURE_INFLATION * #(s.placed or {}))
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
local WING_UP_BASE = 0.6               -- first level = 60% of the wing's build price
local WING_UP_GROWTH = 1.35            -- per level
local WING_LEVEL_AMOUNT = { office = 2, servers = 1, studio = 0.10, cafe = 0.08 }
local WING_LEVEL_TEXT = { office = "+4 seats", servers = "+1 compute", studio = "+10% revenue, +2 seats", cafe = "+8% output, +4 seats" }
local HIRE_GROWTH_LATE = 1.12          -- after HIRE_TAPER_AT people
local QUALITY_CAP = 1.5                -- studio levels stop paying past +150% revenue
local MORALE_CAP = 0.8                 -- cafeteria levels stop paying past +80% output
local HIRE_TAPER_AT = 12
-- v2.3: wing levels END. Five levels, each priced in seconds of your CURRENT
-- income (the Sell Lemons shape: the ladder climbs with you, so "cheap and
-- infinite" cannot happen at HQ 5). The old flat formula is only a floor for
-- brand-new players whose rate is still tiny.
local WING_MAX_LEVEL = (Econ and Econ.V3) and Econ.MAX_LEVEL or 5
local WING_UP_SECONDS = { 45, 90, 180, 360 }   -- Lv1->2 ... Lv4->5

local function wingUpgradeCostOf(room, level, plot, rate)
	if Econ and Econ.V3 then return math.floor(room.cost * Econ.LEVEL_FIRST * (Econ.LEVEL_GROWTH ^ (level - 1))) end
	local base = math.floor(room.cost * WING_UP_BASE * (WING_UP_GROWTH ^ (level - 1)) * hqMultOf(plot))
	local secs = WING_UP_SECONDS[level] or WING_UP_SECONDS[#WING_UP_SECONDS]
	return math.max(base, math.floor((rate or 0) * secs))
end
local function hireGrowthAt(staff)
	if Econ and Econ.V3 then return Econ.HIRE_GROWTH end
	return staff <= HIRE_TAPER_AT and HIRE_GROWTH or HIRE_GROWTH_LATE
end

-- one more level of a wing: the effect applied again, no charge here
local function applyWingLevel(s, room)
	local amt = WING_LEVEL_AMOUNT[room.id] or 0
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
	if id == "studio" and (s.quality or 0) >= QUALITY_CAP then return true end
	if id == "cafe" and (s.morale or 0) >= MORALE_CAP then return true end
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
		slot.upPrompt.ObjectText = ("%s Lv%d  ·  $%s  ·  %s"):format(slot.room.name, lv, fmt(cost), WING_LEVEL_TEXT[slot.room.id] or "")
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
local WORK_FIRST = 90                 -- work units for the first product
local WORK_GROWTH = 1.35              -- each product needs this much more
local LAUNCH_DURATION = 300           -- the spike decays to zero over this

--[[
	SENIORITY. An employee seated at a desk grows: Intern -> Junior -> Senior
	-> Lead, one step every PROMOTE_EVERY seconds, and earns more at each.
	Standing in the waiting line does not count. This is the value a rival
	pays for, and the value you cannot buy back.
]]
local TIER_RATE = { 2, 4, 7, 12 }
local TIER_TITLE = { "Intern", "Junior", "Senior", "Lead" }
local PROMOTE_EVERY = 120

--[[
	v2.5 TALENT. Every hire rolls a talent tier ONCE, server-side, at the
	moment of hiring. Talent multiplies output for life and is visible from
	across the room (shirt colour, halo, "1/1491" on the tag). Seniority still
	promotes on top. This is the roll-to-chase loop: the person is the pull.
	Draws run rarest -> commonest so a Unicorn is exactly 1 in 1491 per hire.
]]
local TALENT = {
	{ name = "Regular", odds = 1,    mult = 1.0,  color = nil },
	{ name = "Skilled", odds = 5,    mult = 1.5,  color = Color3.fromRGB(90, 210, 130) },
	{ name = "Star",    odds = 25,   mult = 2.5,  color = Color3.fromRGB(90, 170, 255) },
	{ name = "Genius",  odds = 150,  mult = 5.0,  color = Color3.fromRGB(190, 120, 255) },
	{ name = "Unicorn", odds = 1491, mult = 12.0, color = Color3.fromRGB(255, 208, 70) },
}

-- v3.2.1: luck multiplies every rare tier's chance (Office Vibe, x1.0..x2.0)
TALENT.roll = function(luck)
	luck = math.clamp(tonumber(luck) or 1, 1, 3)
	for t = #TALENT, 2, -1 do
		if math.random() * TALENT[t].odds < luck then return t end
	end
	return 1
end

local function talentMultOf(r)
	local t = TALENT[r and r.talent or 1] or TALENT[1]
	return t.mult
end

--[[
	ACQUISITION OFFERS. Every few minutes a rival wants your best person. The
	money is real (three minutes of their output, plus a premium) and so is the
	loss: the replacement is an Intern again, hire cost never drops, and the
	next offer will not come for a while. You can rebuy the body, never the
	seniority -- that is the whole anti-abuse.
]]
local OFFER_EVERY = { 150, 240 }
local OFFER_MIN_TIER = 2
--[[
	v1.5 OFFERS THAT PAY. Measured: a sale paid <= 180s of output while the
	replacement Intern needed 6 min to become a Lead again (~4.6 min of Lead
	output lost, plus the rehire fee) -- every sale was a net loss, which is
	why it felt pointless. v2.3: a sale pays income time (offerAmountOf) instead of that person's
	output (cash now vs income later, the one trade-off a nine-year-old
	already understands) and every sale adds to ALUMNI: promotions run
	ALUMNI_STEP faster per sale, capped. Selling is a ladder, not a leak.
]]
-- v2.3: an offer is INCOME TIME, nothing else. 2.5 minutes of the whole
-- company's rate, capped at a quarter of what you are worth (cash + valuation),
-- floored at 1 minute. The old tier x 480 s floor handed a garage player a
-- $5,760 offer against a $2,500 HQ; the same formula gave $40K against $12M.
local OFFER_INCOME_SECONDS = 150
local OFFER_MIN_SECONDS = 60
local OFFER_WORTH_CAP = 0.25
local ALUMNI_STEP = 0.05           -- +5% promotion speed per sale

local function offerAmountOf(s, cashValue)
	local rate = s.rate or 0
	local worth = (cashValue or 0) + (s.valuation or 0)
	local amount = math.min(rate * OFFER_INCOME_SECONDS, worth * OFFER_WORTH_CAP)
	amount = math.max(amount, rate * OFFER_MIN_SECONDS, 25)
	return math.floor(amount)
end
local ALUMNI_CAP = 10              -- +50% max
local RIVALS = { "Buzzly Corp", "Cortex Labs", "Vaultly", "Zoomeats", "Skyfall Games", "Pulse Health",
	"Circlr", "Ledgerly", "Nudge AI", "Brainbox" }
local MARKETS = {
	-- v2.6.2: spike is 1.0 everywhere -- size is equal, SHAPE and FIT live in RoomEconomy.MARKET
	{ id = "social",  name = "SOCIAL",  blurb = "everyone shares it",   spike = 1.0,
	  names = { "Wavelength", "Buzzly", "Hangout", "Pingo", "Snapfeed", "Circlr" } },
	{ id = "games",   name = "GAMES",   blurb = "big spike, fades fast", spike = 1.0,
	  names = { "Blockquest", "Pocket Kart", "Dungeon Dash", "Skyfall", "Tiny Tycoon", "Brick Royale" } },
	{ id = "ai",      name = "AI",      blurb = "slow burn, long tail",  spike = 1.0,
	  names = { "Brainbox", "Autopilot", "Sage", "Cortex", "Whisper AI", "Nudge" } },
	{ id = "fintech", name = "FINTECH", blurb = "steady money",          spike = 1.0,
	  names = { "Coinjar", "Ledgerly", "Payflow", "Vaultly", "Splitwise Jr", "Tabby" } },
	{ id = "health",  name = "HEALTH",  blurb = "does good, pays fair",  spike = 1.0,
	  names = { "Stepcount", "Sleepwell", "Hydrate", "Pulse", "Mindful", "FitBuddy" } },
	{ id = "delivery", name = "DELIVERY", blurb = "everyone orders once", spike = 1.0,
	  names = { "Zoomeats", "Dropbox Jr", "Snackr", "Quickcart", "Doordrop", "Fetch" } },
}

--[[
	IPO. Valuation is cumulative revenue plus a premium per launch. Cross the
	threshold and the company goes PUBLIC: gold sign, a ticker symbol, and a
	permanent seat on the global ticker board at the road (OrderedDataStore).
	His ask: "a permanent leaderboard, like a stock ticker, shown globally."
]]
local IPO_AT = 250000

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
local RIVAL_EVERY = { 120, 200 }       -- seconds between rival launches
local PRESSURE_SECONDS = 60            -- how long a rival launch keeps biting
local SHARE_FLOOR = 0.5
local SHARE_DECAY = 0.004              -- per second under pressure (60s = -24%)
local PUBLIC_RIVALS = {
	{ name = "Cortex Labs",   ticker = "CRTX", base = 260000 },
	{ name = "Vaultly",       ticker = "VLTY", base = 330000 },
	{ name = "Zoomeats",      ticker = "ZOOM", base = 410000 },
	{ name = "Skyfall Games", ticker = "SKYF", base = 520000 },
	{ name = "Brainbox",      ticker = "BRNX", base = 680000 },
}
local RIVAL_GROWTH = 1.02              -- per minute of server uptime
local RIVAL_CAP_MULT = 1.2             -- never more than this x the best human
local serverStart = os.clock()

local SLOT_W, SLOT_D = 28, 24
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
local ROAD_Z = 0
local PLOT_DEFS = {
	{ pivot = CFrame.new(-360, 0, -130) },
	{ pivot = CFrame.new(0, 0, -130) },
	{ pivot = CFrame.new(360, 0, -130) },
	{ pivot = CFrame.new(-360, 0, 130) * CFrame.Angles(0, math.pi, 0) },
	{ pivot = CFrame.new(0, 0, 130) * CFrame.Angles(0, math.pi, 0) },
	{ pivot = CFrame.new(360, 0, 130) * CFrame.Angles(0, math.pi, 0) },
}

-- ============ HELPERS (above every caller, always) ============

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	for k, v in pairs(props) do p[k] = v end
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

local function popup(anchor, text, color)
	if not anchor then return end
	local fx = ReplicatedStorage:FindFirstChild("SVRemotes")
	fx = fx and fx:FindFirstChild("Popup")
	if fx then fx:FireAllClients(anchor, text, color or GOOD) return end
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
	t.TextColor3 = color or GOOD
	t.TextStrokeTransparency = 0.15
	t.TextSize = 28
	t.Font = Enum.Font.FredokaOne
	t.Parent = bb
	TweenService:Create(bb, TweenInfo.new(1.1), { StudsOffset = Vector3.new(0, 6.5, 0) }):Play()
	TweenService:Create(t, TweenInfo.new(1.1),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.2, function() bb:Destroy() end)
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

local sessions = {}   -- userId -> session
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
	for _, def in ipairs(PLOT_DEFS) do
		local c = def.pivot:PointToWorldSpace(Vector3.new(0, 0, -20))
		table.insert(flat, { x = c.X, z = c.Z, w = 240, d = 220 })
	end
	table.insert(flat, { x = 190, z = ROAD_Z, w = 1520, d = 74 })    -- the road
	table.insert(flat, { x = 780, z = ROAD_Z, w = 320, d = 200 })    -- downtown
	-- v1.6: the two cross streets and their building blocks (CityKit.CROSS_X)
	for _, cx in ipairs((CityKit and CityKit.CROSS_X) or { -185, 165 }) do
		table.insert(flat, { x = cx, z = ROAD_Z, w = 120, d = 2 * ((CityKit and CityKit.CROSS_LEN) or 250) + 40 })
	end
	if ValleyGen then
		-- v3.3 the Caltrain corridor behind the south campuses, from the Bay
		-- causeway (west) to a tunnel portal in the eastern hills
		local rail = { x1 = -915, x2 = 648, z = -330, station = 0 }
		table.insert(flat, { x = (rail.x1 + rail.x2) / 2, z = rail.z, w = rail.x2 - rail.x1, d = 40, kind = "rail" })
		local info = ValleyGen.build(world, {
			-- v3.3 the Santa Clara Valley: a forested ridge south, golden hills
			-- north, the Bay west. The hills start 160 studs past the plots and
			-- crest ~600 out: close enough to render at LOW graphics quality
			-- (low-end phones cull terrain past ~500-600 studs, measured)
			flatRects = flat, margin = 46, basin = 430, rim = 680, peakSouth = 190, peakNorth = 205,
			stretchX = 1.35, seed = 7, extentX = 1000, extentZ = 800, bayX = 640,
			-- the hills the line tunnels into at both ends
			mounds = { { x0 = rail.x2 - 18, z = rail.z, halfW = 22, h = 50, dir = 1 }, { x0 = rail.x1 + 18, z = rail.z, halfW = 22, h = 50, dir = -1 } },
			orchards = { { x = -360, z = 335, w = 120, d = 70 }, { x = 330, z = 335, w = 110, d = 70 } },
			rail = rail, crossX = (CityKit and CityKit.CROSS_X) or { -185, 165 }, plotX = { -360, 0, 360 },
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
	local _, made = CityKit.buildStreet(world, { groundY = 0, z = ROAD_Z, x1 = -560, x2 = roadEnd, towersX = 660, noTowers = okD and Downtown ~= nil })
	print(("[SV] street: %d buildings, %d props"):format(made.buildings, made.props))
	if CityKit.buildKenneyCity then
		local _, k = CityKit.buildKenneyCity(world, { groundY = 0, z = ROAD_Z, x1 = -560, x2 = roadEnd })
		if k then print(("[SV] kenney city: %d tiles, %d blocks, %d lamps, %d cars"):format(k.tiles, k.buildings, k.lamps, k.cars)) end
	end
	if okD and Downtown and Downtown.build then
		local okB, err = pcall(Downtown.build, world)
		print(okB and "[SV] downtown built" or ("[SV] downtown failed: " .. tostring(err)))
	end
else
	part({ Name = "Road", Size = Vector3.new(1500, 1, 26), Position = Vector3.new(190, 0.5, ROAD_Z),
		Color = Color3.fromRGB(58, 57, 58), Material = Enum.Material.Asphalt }, world)
end

-- hub spawn: only used before a plot is assigned, or by a 7th body
do
	local sp = Instance.new("SpawnLocation")
	sp.Name = "HubSpawn"
	sp.Size = Vector3.new(6, 1, 6)
	sp.CFrame = CFrame.new(0, 1.5, ROAD_Z)
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
	local L = HQ_LEVELS[level]
	local w, d, h = L.w, L.d, L.h

	shellPart(plot, { Name = "GarageFloor", Size = Vector3.new(w, 1, d), CFrame = g(0, 0.5, 0),
		Color = FLOOR, Material = Enum.Material.Concrete })
	shellPart(plot, { Name = "WallBack", Size = Vector3.new(w, h, 1), CFrame = g(0, h / 2, -d / 2), Color = WALL })
	shellPart(plot, { Name = "WallL", Size = Vector3.new(1, h, d), CFrame = g(-w / 2, h / 2, 0), Color = WALL })
	shellPart(plot, { Name = "WallR", Size = Vector3.new(1, h, d), CFrame = g(w / 2, h / 2, 0), Color = WALL })
	shellPart(plot, { Name = "Roof", Size = Vector3.new(w, 1, d + 1), CFrame = g(0, h, 0), Color = TRIM })

	-- the company name plate: on every level, readable from the road. Gold
	-- once the company is public.
	local plate = shellPart(plot, { Name = "NamePlate", Size = Vector3.new(math.min(w - 12, 26), 3.4, 0.5),
		CFrame = g(0, h + 2.2, d / 2 - 0.8), Color = TRIM, Material = Enum.Material.SmoothPlastic })
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
			CFrame = g(0, h - 1.5, d / 2), Color = TRIM })
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
				CFrame = g(side * (doorW / 2 + sideW / 2), 2, d / 2), Color = WALL })
			shellPart(plot, { Name = "FrontGlass", Size = Vector3.new(sideW - 2, h - 7, 0.4),
				CFrame = g(side * (doorW / 2 + sideW / 2), (h - 7) / 2 + 3, d / 2),
				Color = Color3.fromRGB(150, 200, 220), Material = Enum.Material.Glass, Transparency = 0.45 })
			shellPart(plot, { Name = "SideGlass", Size = Vector3.new(0.4, h - 9, d - 6),
				CFrame = g(side * (w / 2 + 0.31), (h - 9) / 2 + 4, 0),
				Color = Color3.fromRGB(150, 200, 220), Material = Enum.Material.Glass, Transparency = 0.45 })
		end
		shellPart(plot, { Name = "EntranceHeader", Size = Vector3.new(w, 4, 1),
			CFrame = g(0, h - 2, d / 2), Color = TRIM })
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
			CFrame = g(0, 8, -d / 2 + 0.8), Color = level >= 3 and Color3.fromRGB(38, 40, 48) or ACCENT,
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
			t.TextColor3 = level >= 3 and GOLD or Color3.new(1, 1, 1)
			t.Text = ""
			t.Parent = sg
			plot.logoTag = t
		end
		if level >= 3 then
			shellPart(plot, { Name = "Parapet", Size = Vector3.new(w + 2, 1.6, d + 2),
				CFrame = g(0, h + 0.8, 0), Color = WALL })
		end
		-- storey slabs every 12 studs: height reads as floors, and they are the
		-- floors CampusArch furnishes (v3.0.3: from level 3, whose 28-stud hall was one room)
		if level >= 3 then
			for y = 16, h - 6, 12 do
				shellPart(plot, { Name = "StoreyBand", Size = Vector3.new(w + 0.6, 1.2, d + 0.6),
					CFrame = g(0, y, 0), Color = TRIM })
			end
		end
		if level >= 4 then
			-- v3.5: was a 2x6x2 glowing Neon stick. Now a slim white mast; only the
			-- aviation light at its tip glows, which is what Neon is for (ART.md)
			shellPart(plot, { Name = "RoofBeacon", Size = Vector3.new(0.6, 8, 0.6),
				CFrame = g(0, h + 5.5, -d / 4), Color = Color3.fromRGB(243, 239, 230) })
			shellPart(plot, { Name = "RoofBeaconLight", Shape = Enum.PartType.Ball, Size = Vector3.new(1.1, 1.1, 1.1),
				CFrame = g(0, h + 9.9, -d / 4), Color = level >= 5 and GOLD or Color3.fromRGB(255, 96, 80), Material = Enum.Material.Neon })
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
			local ok, a1, a2 = pcall(CampusArch.lot, folder, cf, i, SLOT_W, SLOT_D)
			if ok then pad, t = a1, a2 else warn("[SV] lot " .. i .. " failed: " .. tostring(a1)) end
		end
		if not pad then
			pad = part({ Name = "Slot" .. i, Size = Vector3.new(SLOT_W, 0.4, SLOT_D), CFrame = cf * CFrame.new(0, 0.2, 0),
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
			for k, r in ipairs(ROOMS) do
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

	buildShell(plot, 1, false)
	buildSlots(plot)

	local garage = plot.garage
	part({ Name = "Shelf", Size = Vector3.new(6, 4, 1.2), CFrame = g(-14, 2.5, -13.5),
		Color = Color3.fromRGB(120, 92, 60), Material = Enum.Material.WoodPlanks }, garage)
	part({ Name = "Boxes", Size = Vector3.new(3, 3, 3), CFrame = g(14.5, 2, -13),
		Color = Color3.fromRGB(150, 118, 80), Material = Enum.Material.Cardboard }, garage)
	local desk = part({ Name = "Desk", Size = Vector3.new(7, 0.4, 3.4), CFrame = g(0, 3.2, -9),
		Color = Color3.fromRGB(150, 120, 86), Material = Enum.Material.WoodPlanks }, garage)
	part({ Name = "DeskLegL", Size = Vector3.new(0.4, 3, 0.4), CFrame = g(-3, 1.5, -9), Color = TRIM }, garage)
	part({ Name = "DeskLegR", Size = Vector3.new(0.4, 3, 0.4), CFrame = g(3, 1.5, -9), Color = TRIM }, garage)
	local laptop = part({ Name = "Laptop", Size = Vector3.new(2.6, 0.15, 1.8), CFrame = g(0, 3.5, -9),
		Color = Color3.fromRGB(60, 64, 74), Material = Enum.Material.Metal }, garage)
	local screen = part({ Name = "Screen", Size = Vector3.new(2.6, 1.7, 0.12),
		CFrame = g(0, 4.35, -9.8) * CFrame.Angles(math.rad(-15), 0, 0),
		Color = ACCENT, Material = Enum.Material.Neon }, garage)
	part({ Name = "Chair", Size = Vector3.new(2, 1.0, 2),
		CFrame = g(4.6, 1.5, -6.0) * CFrame.Angles(0, math.rad(-28), 0), Color = TRIM }, garage)
	part({ Name = "ChairBack", Size = Vector3.new(2, 1.8, 0.3),
		CFrame = g(4.6, 2.9, -5.15) * CFrame.Angles(0, math.rad(-28), 0), Color = TRIM }, garage)

	if FurnitureKit then
		local swapped = { desk = desk, laptop = laptop }
		FurnitureKit.dressGarage(garage, g, swapped)
		desk, laptop = swapped.desk, swapped.laptop
	end
	plot.desk, plot.laptop, plot.screen = desk, laptop, screen

	-- the workbench as placement surfaces, in WORLD coordinates for this plot
	plot.fixed = {}
	for _, lx in ipairs({ -2.16, 2.16 }) do
		local wp = def.pivot:PointToWorldSpace(Vector3.new(lx, 0, -9))
		table.insert(plot.fixed, { key = "desk", x = wp.X, z = wp.Z, w = 4.32, d = 2.31, top = 2.26, y = 1.0 })
	end

	plot.hirePad = part({ Name = "HirePad", Size = Vector3.new(7, 0.3, 7), CFrame = g(-11, 1.15, 4), Color = TRIM }, garage)
	plot.hireLabel = label(plot.hirePad, "", 20, 3, 34)

	plot.hqPad = part({ Name = "HQPad", Size = Vector3.new(6, 0.4, 6), CFrame = g(13, 1.2, 8),
		Color = GOLD, Material = Enum.Material.Neon }, garage)
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
	sp.CFrame = g(0, 1.1, 0)
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
	local L = HQ_LEVELS[plot.hq.level]
	if plot.logoTag and plot.logoTag.Parent then
		plot.logoTag.Text = (s and s.name) or ""
	end
	if plot.monumentTag then plot.monumentTag.Text = (s and s.name and s.name ~= "") and string.upper(s.name) or "" end
	if s and s.name and s.name ~= "" then
		if s.ipo then
			plot.signTag.Text = ("%s  ·  %s"):format(companyLabel(s), s.ticker or "")
			-- v3.5 (ART.md: Neon only for lights/screens): a painted gold plate, not a glowing bar
			plot.signPlate.Color = GOLD
			plot.signPlate.Material = Enum.Material.SmoothPlastic
		else
			plot.signTag.Text = companyLabel(s)
			plot.signPlate.Color = TRIM
			plot.signPlate.Material = Enum.Material.SmoothPlastic
		end
	else
		plot.signTag.Text = L.name
		plot.signPlate.Color = TRIM
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
	local q = math.min(s.quality or 0, QUALITY_CAP)
	local mo = math.min(s.morale or 0, MORALE_CAP)
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
	local base, wages, perRoom = 0, 0, {}
	for _, r in ipairs(s.rigs or {}) do
		if not (Econ and Econ.V3) then wages += Econ and Econ.wageOf(r.tier) or 0 end
		if r.seated then
			local v = TIER_RATE[r.tier or 1] * talentMultOf(r) * ((r.fit and Econ) and Econ.FIT_MULT or 1) * (r.eff or 1)
			base += v
			perRoom[r.room or "hq"] = (perRoom[r.room or "hq"] or 0) + v
		end
	end
	if #(s.rigs or {}) == 0 then base = s.staff * INTERN_RATE end   -- rigs missing (no StaffRig)
	local plot = plotOf(player)
	s.hqLevel = plot and plot.hq and plot.hq.level or 1
	local F = mult * hqMultOf(plot) * spinMultOf(s) * milestoneMultOf(s) * ((Econ and Econ.indexMult) and Econ.indexMult(s.index) or 1)
		* ((Econ and Econ.Apt) and Econ.Apt.mult(s) or 1)
	local wageTotal = wages * hqMultOf(plot)
	s.wages = wageTotal
	s.rate = math.max(0, math.floor(base * F - wageTotal))   -- never negative: absence is never punished
	if Econ then
		for k, v in pairs(perRoom) do perRoom[k] = v * F end
		player:SetAttribute("IncomeRooms", Econ.breakdown(perRoom, wageTotal))
	end
	player:SetAttribute("Prestige", math.floor(spinMultOf(s) * milestoneMultOf(s) * ((Econ and Econ.indexMult) and Econ.indexMult(s.index) or 1) * 100 + 0.5) / 100)
	player:SetAttribute("Spinoffs", s.spinoffs or 0)
	-- the client shows catalog prices; tell it what to multiply them by
	local priceMult = hqMultOf(plot) * (1 + FURNITURE_INFLATION * #(s.placed or {}))
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
	local title = (TIER_TITLE[r.tier or 1] or "Intern") .. " " .. roleName:sub(1, 1) .. roleName:sub(2):lower()
	local t = TALENT[r.talent or 1]
	if t and (r.talent or 1) > 1 then title = title .. ("  ·  1/%d"):format(t.odds) end
	return title
end

local function capacityOf(player)
	local s = sessions[player.UserId]
	if s and Econ and Econ.V3 then
		local plot = plotOf(player)
		return plot and Econ.capacity(plot) or 1
	end
	return s and (GARAGE_DESKS + s.desks + (s.placedDesks or 0)) or 0
end

local function shipFirstProduct(player, plot)
	local s = sessions[player.UserId]
	if not s or s.shipped then return end
	s.shipped = true
	Telemetry.step(player, "first_ship")
	local g = plot.g
	local prod = part({ Name = "Product", Size = Vector3.new(1.6, 2.2, 0.2),
		CFrame = g(0, 3.9, -9), Color = GOOD, Material = Enum.Material.Neon }, plot.garage)
	local tag = label(prod, "TO-DO APP", 22, 2.2, 60)
	tag.TextColor3 = GOOD
	TweenService:Create(prod, TweenInfo.new(1.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ CFrame = g(0, 9.2, -9) }):Play()
	task.delay(2.6, function()
		TweenService:Create(prod, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		TweenService:Create(tag, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		task.delay(0.6, function() prod:Destroy() end)
	end)
	popup(plot.desk, "SHIPPED!", GOLD)
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
	cash.Value += CODE_REWARD * brew
	Telemetry.step(player, "first_code")
	popup(plot.laptop, "+$" .. CODE_REWARD * brew)
	plot.screen.Color = GOOD
	task.delay(0.12, function() plot.screen.Color = ACCENT end)
	if s.clicks == CLICKS_TO_SHIP then shipFirstProduct(player, plot) end
	-- v2.7.0 the active verb: every click after the first ship pushes the product bar
	if Econ and Econ.V3 and s.shipped and s.clicks > CLICKS_TO_SHIP and not s.pendingProduct then
		local team = 0
		for _, r in ipairs(s.rigs or {}) do team += TIER_RATE[r.tier or 1] end
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
		if StaffRig.setSeated then StaffRig.setSeated(r.rig, r.seated) end
		if not home then
			-- no desk: stand in a line beside the hire pad, facing the room
			home = plot.g(-15 + waiting * 3, 3.62, 9) * CFrame.Angles(0, math.rad(180), 0)   -- floor top 1.0 + root-to-sole 2.61
			waiting += 1
		end
		StaffRig.rehome(r.rig, home)
	end
	s.waitingStaff = waiting
	recompute(player)   -- v2.6.0: who sits where IS the income now
end

local function spawnStaff(player, plot, n, talent, who)
	if not StaffRig then return nil end
	local s = sessions[player.UserId]
	local roleKey = ROLE_ORDER[((n - 1) % #ROLE_ORDER) + 1]
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
	local t = TALENT[entry.talent]
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
	if not s.shipped then
		plot.hireLabel.Text = ""
		plot.hirePad.Color = TRIM
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
		plot.hirePad.Color = GOLD
	elseif Econ and Econ.RECRUIT and Econ.Drop then
		plot.hireLabel.Text = "HIRING HAPPENS ON THE STREET  ·  candidates wait on the sidewalk"
		plot.hirePad.Color = TRIM
	else
		plot.hireLabel.Text = string.format("HIRE  ·  $%s  ·  rolls talent", fmt(hireCostOf(s, plot)))
		plot.hirePad.Color = GOLD
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
	local key, text, pos, sub, cost
	if not s.shipped then
		key, text, pos = "code", "Write your first app", posOf(plot.laptop)
		sub = ("Tap the laptop  (%d of %d)"):format(math.min(s.clicks or 0, CLICKS_TO_SHIP), CLICKS_TO_SHIP)
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
		local empty
		local built = 0
		for _, slot in ipairs(plot.slots) do
			if slot.built then built += 1 elseif not empty then empty = slot end
		end
		local cap = capacityOf(player)
		local nxtHq = HQ_LEVELS[plot.hq.level + 1]
		local upWing
		for _, slot in ipairs(plot.slots) do
			if slot.built and not wingMaxed(s, slot) then upWing = slot break end
		end
		-- what the next HQ level unlocks: the reason to save for it
		local function hqTease()
			if not nxtHq then return nil end
			for _, tier in ipairs(Econ and Econ.RECRUIT and Econ.TIERS or {}) do
				if tier.hq == plot.hq.level + 1 then return ("Unlocks %s hires"):format(tier.name) end
			end
			local capN = Econ and Econ.CAP_BY_HQ and Econ.CAP_BY_HQ[plot.hq.level + 1]
			return capN and ("Room for %d staff"):format(capN) or nil
		end
		if built == 0 and empty then
			local r = ROOM_BY_ID.office
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
				if s.staff < cap then
					local hc = hireCostOf(s, plot)
					-- v3.0: ranked at the walk-in fee (the sim's rule), pointed at the best
					-- candidate standing that you can afford
					local cand = Econ.Drop and Econ.Drop.bestFor(player, (cashOf(player) or { Value = 0 }).Value)
					if cand then
						offer(hc, "recruit", ("Recruit a %s hire"):format(cand.tier.name), cand.pos, "They wait on the sidewalk")
						best.cost = cand.fee
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
				if plant then decorOffer = { c = furniturePriceOf(plant, s, plot), k = "decor", t = "Decorate your office", at = nil, sub = "Tap DECOR. Better offices attract rare hires" } end
			end
			if nxtHq then
				offer(nxtHq.cost, "hq", ("Upgrade to %s"):format(nxtHq.name), posOf(plot.hqPad), hqTease())
			else
				offer(spinoffCostOf(s), "spin", "Spin off", posOf(plot.hqPad), ("Start over with x%s money forever"):format((string.format("%.1f", spinMultOf(s) + SPINOFF_STEP)):gsub("%.0$", "")))
			end
			if empty and Econ and Econ.V3 then
				if built < (Econ.SLOTS_BY_HQ[plot.hq.level] or 6) then
					local r = ROOM_BY_ID[Econ.nextRoom(plot)]
					local wc = wingCostOf(r, plot, s.rate)
					offer(wc, "wing", ("Build %s %s"):format((r.name:match("^[AEIOU]") and "an" or "a"), (r.name:lower():gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end))), posOf(empty.pad), r.blurb)
				end
			elseif empty then
				local cheapest = math.huge
				for _, r in ipairs(ROOMS) do cheapest = math.min(cheapest, wingCostOf(r, plot, s.rate)) end
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
				local r = ROOM_BY_ID[Econ.nextRoom(plot)]
				local wc = wingCostOf(r, plot, s.rate)
				if held.Value >= wc then
					best = { c = wc, k = "wing", t = ("Build %s %s"):format((r.name:match("^[AEIOU]") and "an" or "a"), (r.name:lower():gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end))), at = posOf(empty.pad), sub = r.blurb, roomsFirst = true }
				end
			end
			if nxtHq and held and held.Value >= nxtHq.cost then
				best = { c = nxtHq.cost, k = "hq", t = ("Upgrade to %s"):format(nxtHq.name), at = posOf(plot.hqPad), sub = hqTease() }
			elseif nxtHq and held and Econ and Econ.V3 and (s.rate or 0) > 0 and not (best and best.roomsFirst)
				and (nxtHq.cost - held.Value) / s.rate <= Econ.SAVE_WINDOW then
				-- v2.7.0: the big goal is close; stop spending on small things (the old guide never saved)
				best = { c = nxtHq.cost, k = "hq", t = ("Save up for %s"):format(nxtHq.name), at = posOf(plot.hqPad), sub = hqTease() }
			end
			-- v2.8: at HQ 5 the spin-off is the big goal, with the same afford / save-up treatment
			if not nxtHq and held and Econ and Econ.V3 then
				local sc = spinoffCostOf(s)
				local why = ("Start over with x%s money forever"):format((string.format("%.1f", spinMultOf(s) + SPINOFF_STEP)):gsub("%.0$", ""))
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
			-- v4.0 THE APARTMENT RUNG: whenever the guide would send you to the HQ pad
			-- and the next level needs a home, it sends you downtown instead
			if best and best.k == "hq" and Econ and Econ.Apt and (s.apt or 0) < Econ.Apt.need(plot.hq.level + 1) then
				local t = Econ.Apt.TIERS[(s.apt or 0) + 1] or Econ.Apt.TIERS[Econ.Apt.need(plot.hq.level + 1)]   -- the next rung you can buy
				local has = held and held.Value >= t.price
				local drive = Econ.Cars and Econ.Cars.hasCar(player)
				local deskAt = Econ.Apt.deskPosition()
				local rootP = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				local nearDesk = deskAt and rootP and (rootP.Position - deskAt).Magnitude < 180
				local nice = t.name:sub(1, 1) .. t.name:sub(2):lower()
				best = { c = t.price, k = "apartment", t = has and ("Buy a %s"):format(nice) or ("Save for a %s"):format(nice),
					at = deskAt, sub = nearDesk and "Sales desk, in the lobby" or (drive and "Drive downtown: CAR button" or "The Residences, downtown") }
			end
			if not best then best = { k = "wait", t = "Write code", at = nil, sub = "Tap WRITE CODE for cash" } end
			key, text, pos, sub, cost = best.k, best.t, best.at, best.sub, best.cost or best.c
		end
	end
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

-- v3.0: `recruit` = { floor, fee } when a Talent Row candidate reaches your
-- door (TalentDrop). The pad itself only hires the free first intern; every
-- hire after that is a recruit run. Returns true when someone was hired.
local function hire(player, plot, recruit)
	if plotOf(player) ~= plot then return false end
	local s = sessions[player.UserId]
	local cash = cashOf(player)
	if not s or not cash or not s.shipped then return false end
	if not recruit and s.staff >= 1 and Econ and Econ.RECRUIT and Econ.Drop then
		popup(plot.hirePad, "Recruit on the street  ·  candidates wait on the sidewalk", ACCENT)
		return false
	end
	if s.staff >= capacityOf(player) then
		popup(plot.hirePad, "No desks free", BAD)
		return false
	end
	local cost = recruit and recruit.fee or ((s.staff == 0) and 0 or hireCostOf(s, plot))
	if cash.Value < cost then
		popup(plot.hirePad, "Need $" .. fmt(cost), BAD)
		return false
	end
	cash.Value -= cost
	s.lastBuy = os.clock()
	s.staff += 1
	if cost > 0 then s.hireCost = math.floor(s.hireCost * hireGrowthAt(s.staff)) end
	Telemetry.step(player, "first_hire")
	local talent = (cost == 0) and 1 or TALENT.roll((player:GetAttribute("VibeLuck") or 1) * (recruit and recruit.luck or 1))   -- v3.2.1 vibe x v4.2 a Penthouse VIP
	if recruit then talent = math.max(talent, recruit.floor or 1) end   -- the tier they wore is a floor
	if cost > 0 and Econ and Econ.Inv then talent = Econ.Inv.onHire(player, talent) end   -- v3.2: a Scout Report
	local indexBefore = 0
	for _ in pairs(s.index or {}) do indexBefore += 1 end
	local torso = spawnStaff(player, plot, s.staff, talent, recruit)
	local indexAfter = 0
	for _ in pairs(s.index or {}) do indexAfter += 1 end
	recompute(player)
	local t = TALENT[talent]
	if talent > 1 then
		-- v3.0: a recruited floor is a signing, not luck; only a roll ABOVE the floor says "1 in N"
		local lucky = not (recruit and talent <= (recruit.floor or 1))
		-- v3.1: the numbers live on the reveal card; the world marker just names it (say it once)
		popup(torso or plot.hirePad, t.name:upper() .. "!", t.color or GOLD)
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
		popup(torso or plot.hirePad, (cost == 0) and "INTERN HIRED" or ("HIRED  -$" .. fmt(cost)), GOOD)
	end
	updateHirePad(player)
	return true
end

local spinOff   -- assigned below releasePlot (it needs it); forward-declared like refreshFacade
local function refreshHqPad(plot)
	local nxt = HQ_LEVELS[plot.hq.level + 1]
	local s = plot.owner and sessions[plot.owner]
	local needApt = nxt and s and Econ and Econ.Apt and (s.apt or 0) < Econ.Apt.need(plot.hq.level + 1)
	if needApt then
		plot.hqLabel.Text = ("UPGRADE HQ  ·  needs a %s downtown"):format(Econ.Apt.TIERS[Econ.Apt.need(plot.hq.level + 1)].name)
		plot.hqPad.Color = Color3.fromRGB(150, 146, 140)
	elseif nxt then
		plot.hqLabel.Text = ("UPGRADE HQ  ·  $%s"):format(fmt(nxt.cost))
		plot.hqPad.Color = GOLD
	elseif s then
		if plot.spinArmed then
			plot.hqLabel.Text = "TAP AGAIN TO SPIN OFF  ·  back to the garage, x" .. string.format("%.1f", spinMultOf(s) + SPINOFF_STEP) .. " forever"
			plot.hqPad.Color = Color3.fromRGB(255, 120, 60)
		else
			plot.hqLabel.Text = ("SPIN OFF  ·  $%s  ·  revenue x%.1f forever"):format(fmt(spinoffCostOf(s)), spinMultOf(s) + SPINOFF_STEP)
			plot.hqPad.Color = GOLD
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
		Econ.celebrate:FireClient(player, { kind = "milestone", earned = MILESTONE_BASE * 10 ^ (want - 1),
			bonus = math.floor(want * MILESTONE_STEP * 100 + 0.5) })
	end
end

local function tryUpgrade(player, plot)
	if plotOf(player) ~= plot or plot.busy then return end
	local s = sessions[player.UserId]
	local cash = cashOf(player)
	local nxt = HQ_LEVELS[plot.hq.level + 1]
	if not s or not cash then return end
	if not nxt then if spinOff then spinOff(player, plot) end return end
	if not s.shipped then popup(plot.hqPad, "Ship something first", BAD) return end
	if s.staff < 1 then popup(plot.hqPad, "Hire someone first", BAD) return end
	if Econ and Econ.Apt and (s.apt or 0) < Econ.Apt.need(plot.hq.level + 1) then
		local t = Econ.Apt.TIERS[Econ.Apt.need(plot.hq.level + 1)]
		popup(plot.hqPad, ("Buy your %s downtown first"):format(t.name), BAD)
		return
	end
	if cash.Value < nxt.cost then popup(plot.hqPad, "Need $" .. fmt(nxt.cost), BAD) return end
	plot.busy = true
	cash.Value -= nxt.cost
	s.lastBuy = os.clock()
	buildShell(plot, plot.hq.level + 1, true)
	-- the new shell grows around whoever is inside; anyone pushed onto the roof
	-- goes back to the garage floor (18 Sep playtest ended on the roof)
	task.delay(0.9, function()
		for _, pl in ipairs(Players:GetPlayers()) do
			local root = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
			if root and plot.spawn then
				local rel = plot.pivot:PointToObjectSpace(root.Position)
				if math.abs(rel.X) < 60 and math.abs(rel.Z) < 60 and root.Position.Y > plot.spawn.Position.Y + 9 then
					pl.Character:PivotTo(plot.spawn.CFrame + Vector3.new(0, 3, 0))
				end
			end
		end
	end)
	refreshSign(plot)
	refreshHqPad(plot)
	recompute(player)          -- a bigger HQ earns more per head and prices everything up
	if plot.hq.level == 2 and Econ and Econ.Cars then
		task.delay(3.5, function() pcall(Econ.Cars.grant, player, "hatch", "COMPANY CAR!") end)
	end
	updateHirePad(player)
	for _, sl in ipairs(plot.slots) do if sl.built then refreshWingPrompt(sl, plot, s) end end
	popup(plot.hqPad, nxt.name .. "!", GOLD)
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
			Econ.celebrate:FireClient(player, { kind = "hq", level = plot.hq.level, name = nxt.name, chips = chips })
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
	task.delay(0.4, function() popup(plot.desk, "Your lot is outside. Build on it.", GOLD) end)
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
	local arch = CampusArch and select(1, pcall(CampusArch.wing, m, cf, room, SLOT_W, SLOT_D))
	if not arch then
	m:ClearAllChildren()
	rp("Floor", Vector3.new(SLOT_W, 1, SLOT_D), Vector3.new(0, 0.5, 0), FLOOR, Enum.Material.Concrete)
	rp("WallL", Vector3.new(1, 10, SLOT_D), Vector3.new(-SLOT_W / 2, 5, 0))
	rp("WallR", Vector3.new(1, 10, SLOT_D), Vector3.new(SLOT_W / 2, 5, 0))
	rp("WallBack", Vector3.new(SLOT_W, 10, 1), Vector3.new(0, 5, -SLOT_D / 2))
	rp("Roof", Vector3.new(SLOT_W + 1, 1, SLOT_D + 1), Vector3.new(0, 10, 0), TRIM)
	local dimmed = Color3.new(room.accent.R * 0.45, room.accent.G * 0.45, room.accent.B * 0.45)
	rp("Fascia", Vector3.new(SLOT_W + 1, 1.6, 0.8), Vector3.new(0, 9.2, SLOT_D / 2), dimmed, Enum.Material.Neon)
	-- a glass front with a doorway, not an open fourth wall: a wing reads as a
	-- room you enter, and the furniture inside shows from the campus
	local doorW = 7
	local sideW = (SLOT_W - doorW) / 2
	for _, side in ipairs({ -1, 1 }) do
		local gl = rp("FrontGlass", Vector3.new(sideW, 7.4, 0.4), Vector3.new(side * (doorW / 2 + sideW / 2), 4.7, SLOT_D / 2),
			Color3.fromRGB(150, 200, 220), Enum.Material.Glass)
		gl.Transparency = 0.45
		gl.CanCollide = false          -- see through, walk through the door only
		gl.CanCollide = true
	end
	rp("DoorHeader", Vector3.new(doorW + 0.4, 1.6, 0.6), Vector3.new(0, 7.6, SLOT_D / 2), TRIM)
	rp("CeilingLight", Vector3.new(SLOT_W * 0.6, 0.25, 1), Vector3.new(0, 9.4, 0),
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
	if wingMaxed(s, slot) then popup(slot.header or plot.hirePad, slot.room.name .. " is maxed", ACCENT) refreshWingPrompt(slot, plot, s) return end
	local cost = wingUpgradeCostOf(slot.room, slot.level or 1, plot, s.rate)
	if cash.Value < cost then popup(slot.header or plot.hirePad, "Need $" .. fmt(cost), BAD) return end
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
	popup(slot.header or plot.hirePad, ("%s Lv%d  %s"):format(slot.room.name, slot.level, WING_LEVEL_TEXT[slot.room.id] or ""), GOOD)
	-- v3.2: the building itself grows (Lv 4 storey, Lv 7 terrace, Lv 10 crown)
	if CampusArch and CampusArch.grow and slot.model then
		local ok, parts = pcall(CampusArch.grow, slot.model, slot.cf, slot.room, SLOT_W, SLOT_D, slot.level)
		if ok and parts and #parts > 0 then rise(parts, 9, 0.8) elseif not ok then warn("[SV] grow: " .. tostring(parts)) end
	end
end

local function buildWing(player, plot, slotIndex, roomId, free)
	local s = sessions[player.UserId]
	local cash = cashOf(player)
	if not s or not plot or not cash then return false end
	if type(slotIndex) ~= "number" then return false end
	local slot = plot.slots[slotIndex]
	local room = ROOM_BY_ID[roomId]
	if not slot or not room or slot.built then return false end
	if not free then
		if not s.buildUnlocked then return false end
		if Econ and Econ.V3 and Econ.slotsBuilt(plot) >= (Econ.SLOTS_BY_HQ[plot.hq.level] or 6) then
			popup(slot.pad, "Upgrade your HQ to build more rooms", BAD)
			return false
		end
		local cost = wingCostOf(room, plot, s.rate)
		if cash.Value < cost then popup(slot.pad, "Need $" .. fmt(cost), BAD) return false end
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
			if math.abs(rel.X) < SLOT_W / 2 + 1.5 and math.abs(rel.Z) < SLOT_D / 2 + 1.5 and rel.Y > -2 and rel.Y < 20 then
				local out = slot.cf:PointToWorldSpace(Vector3.new(0, 3.2, SLOT_D / 2 + 8))
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
			slot.levelTag.TextColor3 = GOLD
		end
		refreshWingPrompt(slot, plot, s)
	end
	if Econ and Econ.V3 then Econ.furnish(FurnitureKit, slot) end
	if CampusArch then pcall(CampusArch.links, plot, SLOT_W, SLOT_D) end
	s.desks += (room.desks or 0)
	s.quality = (s.quality or 0) + (room.quality or 0)
	s.morale = (s.morale or 0) + (room.morale or 0)
	s.compute = (s.compute or 0) + (room.compute or 0)
	if room.id == "office" or (Econ and Econ.V3) then assignDesks(player) end   -- people in the line take the new seats
	recompute(player)
	updateHirePad(player)
	if not free then
		Telemetry.step(player, "first_wing")
		popup(slot.pad, room.name .. " BUILT", GOOD)
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
	local L = HQ_LEVELS[plot.hq.level]
	local rects = { { cf = plot.pivot, w = L.w, d = L.d, top = 1.0 } }
	for _, slot in ipairs(plot.slots) do
		if slot.built then table.insert(rects, { cf = slot.cf, w = SLOT_W, d = SLOT_D, top = 1.0 }) end
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
	local item = FurnitureKit.BY_KEY[key]
	if not item or not FurnitureKit.has(key) then return false end
	if item.needs and not roomBuilt(plot, item.needs) then
		if not free then
			local r = ROOM_BY_ID[item.needs]
			local nm = r and r.name or tostring(item.needs)
			popup(plot.hirePad, ("Build %s %s first"):format(nm:upper():match("^[AEIOU]") and "an" or "a", nm), BAD)
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
	if not floor then if not free then popup(plot.hirePad, "Outside your floor", BAD) end return false end

	-- v2.6.0 ROOM ECONOMY: a station seats people only in its own room, up to
	-- that room's cap. A refused station from an old save is refunded, not lost.
	local st = Econ and Econ.STATIONS[key]
	local roomId, slotIdx
	if st then
		local L = HQ_LEVELS[plot.hq.level]
		roomId, slotIdx = Econ.roomAt(plot, x, z, L.w, L.d, SLOT_W, SLOT_D)
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
			if not (item.tuck or onSurface == e or e.y ~= y) then
				if not free then popup(plot.hirePad, "The workbench is there", BAD) end
				return false
			end
		end
	end
	for _, e in ipairs(s.placed) do
		if rectsOverlap(x, z, w, d, e.x, e.z, e.w, e.d) then
			local tucking = item.tuck and DESK_FAMILY[e.key]
			local surfacePair = onSurface and (e == onSurface)
			local stacked = (e.y or 0) ~= y
			if not (tucking or surfacePair or stacked) then
				if not free then popup(plot.hirePad, "Something is already there", BAD) end
				return false
			end
		end
	end
	-- v3.5: never on someone's seat (36 lamps around the office desks put three
	-- inside seated staff) and never inside a room's own furniture. A saved item
	-- that breaks either rule is refunded on load, like a refused station.
	if not onSurface then
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
				popup(plot.hirePad, clash, BAD)
			end
			return false
		end
	end

	-- what was PAID is what refunds. On load the saved price is used; an old
	-- save without one falls back to the base price (never the inflated one:
	-- recomputing at a higher HQ level minted cash on every relog)
	local price = forcedPrice or (free and item.price) or furniturePriceOf(item, s, plot)
	if not free then
		if cash.Value < price then popup(plot.hirePad, "Need $" .. fmt(price), BAD) return false end
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
		if at then popup(at, ("VIBE UP! %d of 5 stars  ·  rare hires x%s"):format(starsAfter, (string.format("%.1f", player:GetAttribute("VibeLuck") or 1))), ACCENT) end
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
	remote("SpinConfirm").OnServerEvent:Connect(function(player)
		local plot = plotOf(player)
		if plot and plot.spinArmed and os.clock() - plot.spinArmed <= 30 and spinOff then spinOff(player, plot) end
	end)
	remote("SpinCancel").OnServerEvent:Connect(function(player)
		local plot = plotOf(player)
		if plot and plot.spinArmed then plot.spinArmed = nil; refreshHqPad(plot) end
	end)
	Econ.Daily = tryRequire(ServerScriptService, "DailyReward")
	if Econ.Daily and Econ.Daily.init then
		local ok, err = pcall(Econ.Daily.init, {
			session = function(p) return sessions[p.UserId] end, cash = cashOf, remote = remote, fmt = fmt,
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
			plots = plots, TALENT = TALENT, RIVALS = RIVALS, BAD = BAD, fmt = fmt, popup = popup,
			session = function(p) return sessions[p.UserId] end,
			plotOf = plotOf, cash = cashOf, capacity = capacityOf,
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
			plotOf = plotOf, cash = cashOf, fmt = fmt, TALENT = TALENT,
			grant = function(p, id, n, why) return Econ.Inv and Econ.Inv.grant(p, id, n, why) end,
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
	buildSlots(plot)
	plot.hireLabel.Text = ""
	plot.hirePad.Color = TRIM
	refreshHqPad(plot)
	if plot.signTag then plot.signTag.Text = HQ_LEVELS[1].name end
	if plot.signPlate then plot.signPlate.Color = TRIM; plot.signPlate.Material = Enum.Material.SmoothPlastic end
end

spinOff = function(player, plot)
	local s = sessions[player.UserId]
	local cash = cashOf(player)
	if not s or not cash or plot.busy or plotOf(player) ~= plot then return end
	local cost = spinoffCostOf(s)
	if cash.Value < cost then popup(plot.hqPad, "Need $" .. fmt(cost), BAD) return end
	-- two taps: a one-click reset of an hour of play is not a decision
	--[[ v3.1: the confirm is a card (what you keep vs what resets, SPIN OFF /
	NOT YET), not a fading 1-second sentence at the pad. An accidental reset of
	an hour of play is the quit event for your best players. The card's button
	fires SpinConfirm, which comes back here as the second tap. ]]
	if not plot.spinArmed or os.clock() - plot.spinArmed > 30 then
		plot.spinArmed = os.clock()
		refreshHqPad(plot)
		local keepN = 0
		for _, r in ipairs(s.rigs or {}) do if (r.talent or 1) >= ((Econ and Econ.KEEP_TALENT) or 3) then keepN += 1 end end
		keepN = math.min(keepN, (Econ and Econ.KEEP_MAX) or keepN)
		if Econ and Econ.celebrate then
			Econ.celebrate:FireClient(player, { kind = "spinAsk", cost = cost, from = spinMultOf(s), to = spinMultOf(s) + SPINOFF_STEP,
				keep = keepN, number = (s.spinoffs or 0) + 1 })
		end
		task.delay(30.5, function()
			if plot.spinArmed and os.clock() - plot.spinArmed >= 30 then plot.spinArmed = nil; refreshHqPad(plot) end
		end)
		return
	end
	plot.spinArmed = nil
	plot.busy = true
	-- v2.7.0: Star and above follow you to the next startup (the chase across runs)
	local keep = {}
	if Econ and Econ.V3 then
		for _, r in ipairs(s.rigs or {}) do
			if (r.talent or 1) >= Econ.KEEP_TALENT then table.insert(keep, { talent = r.talent, who = r.who }) end
		end
		-- v3.0: recruiting makes Star+ common (the sim kept ~12), so only the best few come along
		table.sort(keep, function(a, b) return a.talent > b.talent end)
		while Econ.KEEP_MAX and #keep > Econ.KEEP_MAX do table.remove(keep) end
	end
	cash.Value = 0
	releasePlot(plot)                -- wipes rooms, furniture, staff; shell back to the garage
	plot.owner = player.UserId
	s.staff = 0; s.rigs = {}; s.desks = 0; s.hireCost = HIRE_BASE
	s.quality = 0; s.morale = 0; s.compute = 0
	s.placed = {}; s.placedDesks = 0; s.placedMorale = 0
	s.work = 0; s.workNeed = math.floor(WORK_FIRST * (WORK_GROWTH ^ (s.launches or 0)))
	s.launch = nil; s.pressure = nil; s.share = 1; s.pendingOffer = nil
	-- v3.1: an app finished before the spin-off belongs to the old company; its
	-- LAUNCH card used to survive the reset showing the old payday
	s.pendingProduct = nil
	productReady:FireClient(player, nil)
	s.spinoffs = math.min((s.spinoffs or 0) + 1, SPINOFF_CAP)
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
		task.delay(2.2, function() popup(plot.hirePad, ("%d rare hire%s came with you  ·  build an office to seat them"):format(#keep, #keep == 1 and "" or "s"), GOLD) end)
	end
	recompute(player)
	refreshSign(plot)
	refreshHqPad(plot)
	updateHirePad(player)
	local char = player.Character
	if char and plot.spawn then char:PivotTo(plot.spawn.CFrame + Vector3.new(0, 3, 0)) end
	popup(plot.hqPad, ("SPIN-OFF %s!"):format(ROMAN[s.spinoffs + 1] or ""), GOLD)
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

for i, def in ipairs(PLOT_DEFS) do
	plots[i] = buildPlot(i, def)
	wirePlot(plots[i])
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
				if s.pressure and os.clock() - s.pressure >= PRESSURE_SECONDS then
					s.pressure = nil
				elseif s.pressure and not buzz then
					s.share = math.max(SHARE_FLOOR, (s.share or 1) - SHARE_DECAY)
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
				if s.earned >= MILESTONE_BASE * 10 ^ (s.milestones or 0) then checkMilestones(player, s) end
				s.effective = earned
			elseif s then
				s.effective = 0
			end
			if s then
				-- WORK: seated people fill the product bar, tier-weighted
				local work = 0
				for _, r in ipairs(s.rigs or {}) do
					if r.seated then
						work += TIER_RATE[r.tier or 1] / 2
						r.seatedTime = (r.seatedTime or 0) + 1 + ALUMNI_STEP * math.min(s.alumni or 0, ALUMNI_CAP)
						local want = math.min(#TIER_TITLE, 1 + math.floor(r.seatedTime / PROMOTE_EVERY))
						if want > (r.tier or 1) then
							r.tier = want
							StaffRig.setTitle(r.rig, titleOf(r))
							StaffRig.say(r.rig, "Promoted to " .. TIER_TITLE[want] .. "!")
							recompute(player)
						end
					end
				end
				s.work = (s.work or 0) + work * afk      -- AFK: products slow too (no free paydays)
				s.workNeed = s.workNeed or WORK_FIRST
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
	local name = cleanName(player, raw)                 -- yields
	if plotOf(player) ~= plot or sessions[player.UserId] ~= s then return end
	if not name then askName:FireClient(player, "That name will not work. Try another.") return end
	s.name = name
	s.ticker = tickerOf(name)
	refreshSign(plot)
	popup(plot.desk, name .. " is born.", GOLD)
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
	local spike = market.spike * (mod or 1) * (1 + math.min(s.quality or 0, QUALITY_CAP)) * (0.8 + 0.2 * tier)
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
		s.launch = { t0 = os.clock(), spike = spike * (shape and shape.h or 1), duration = shape and shape.dur or LAUNCH_DURATION,
			curve = shape and shape.curve, slow = market.slow, marketId = market.id }
	end
	s.launches = (s.launches or 0) + 1
	Telemetry.step(player, "first_product")
	s.markets[market.id] = true          -- now a rival can come for this market
	s.share = 1                          -- shipping takes the share back
	s.pressure = nil
	s.valuation = (s.valuation or 0) + math.floor(s.rate * 30 * spike)
	-- PAYDAY: a launch is cash, not only a valuation line
	local payday = math.floor(s.rate * (shape and shape.pay or PAYDAY_SECONDS) * spike * (auto and 0.5 or 1))
	if Econ and Econ.V3 then
		payday = math.floor(s.rate * Econ.LAUNCH_PAY * (1 + 0.1 * (s.compute or 0)) * (auto and 0.5 or 1))
	end
	if Econ and Econ.Inv then payday = math.floor(payday * Econ.Inv.launchMult(player)) end   -- v3.2: a Front Page doubles it
	local cash = cashOf(player)
	if cash and payday > 0 then cash.Value += payday end
	if Econ and Econ.Inv then pcall(Econ.Inv.onLaunch, player, s) end
	s.pendingProduct = nil
	s.work = 0
	s.workNeed = math.floor(WORK_FIRST * (WORK_GROWTH ^ s.launches))
	-- the room reacts: everyone cheers, one of them says something
	for i, r in ipairs(s.rigs or {}) do
		task.delay(0.1 * i, function() if StaffRig then StaffRig.cheer(r.rig) end end)
	end
	local speaker = s.rigs and s.rigs[math.random(1, math.max(1, #s.rigs))]
	if speaker and StaffRig then StaffRig.say(speaker.rig, "We shipped " .. name .. "!", 4) end
	productReady:FireClient(player, nil)      -- close the picker (auto-ship path too)

	-- v3.4 THE CEREMONY: the brand rocket lifts off this HQ's roof and every
	-- player in the server sees it (RocketClient). Was a neon box floating up.
	local L = HQ_LEVELS[plot.hq.level]
	local rl = remotes:FindFirstChild("RocketLaunch")
	if rl then
		rl:FireAllClients({ pos = plot.g(0, L.h + (plot.hq.level >= 5 and 1.7 or 0.6), -4).Position, name = name, market = market.name, owner = player.UserId, auto = auto == true })
	end
	popup(plot.hqPad, "LAUNCHED: " .. name, GOLD)
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
		local m = MARKETS[math.random(1, #MARKETS)]
		local picks = { m }
		s.pendingProduct = picks
		s.pendingMods = { 1 }
		local payday = math.floor((s.rate or 0) * Econ.LAUNCH_PAY * (1 + 0.1 * (s.compute or 0)))
		-- v3.1: `autoAt` lets the button count down to the half-pay auto-launch
		productReady:FireClient(player, { { name = "LAUNCH!", blurb = m.name .. " app", launch = true, payday = payday, spike = 1,
			autoAt = workspace:GetServerTimeNow() + 60 } })
		task.delay(60, function()
			local s2 = sessions[player.UserId]
			if s2 and s2.pendingProduct == picks then launchProduct(player, plot, m, 1, true) end
		end)
		return
	end
	-- three distinct markets, shuffled
	local pool = table.clone(MARKETS)
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
	local grow = (1 + math.min(s.quality or 0, QUALITY_CAP)) * (0.8 + 0.2 * tier)
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
	popup(plot.hqPad, "PRODUCT READY -- pick a market", GOLD)
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
			if s and not s.pendingProduct and (s.work or 0) >= (s.workNeed or WORK_FIRST) then
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
			for _, m in ipairs(MARKETS) do
				if s.markets[m.id] then inUse[#inUse + 1] = m end
			end
		end
	end
	local market = forced or inUse[math.random(1, math.max(1, #inUse))]
	if not market then return 0 end
	local rival = RIVALS[math.random(1, #RIVALS)]
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
		task.wait(math.random(RIVAL_EVERY[1], RIVAL_EVERY[2]))
		rivalLaunch()
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
			task.wait(math.random(OFFER_EVERY[1], OFFER_EVERY[2]))
			local s = sessions[player.UserId]
			if Econ and Econ.V3 then continue end   -- v2.7.0: poach offers off
			-- v2.5.1: one decision at a time -- no poach offer while a product is waiting
			if not s or s.pendingOffer or s.pendingProduct or not s.rigs then continue end
			-- the best person, if anyone is worth buying
			local best
			for _, r in ipairs(s.rigs) do
				local worth = TIER_RATE[r.tier or 1] * talentMultOf(r)
				if (r.tier or 1) >= OFFER_MIN_TIER and (not best or worth > TIER_RATE[best.tier or 1] * talentMultOf(best)) then best = r end
			end
			if not best then continue end
			-- capped at rehire cost + 60s of the person's output: selling a Lead
			-- and rehiring an intern must never be a money printer (it was: quality
			-- scaled the offer but not the hire)
			local cashNow = cashOf(player)
			local amount = offerAmountOf(s, cashNow and cashNow.Value or 0)
			local loss = math.floor((TIER_RATE[best.tier] - TIER_RATE[1]) * hqMultOf(plot))
			local minutes = (s.rate or 0) > 0 and amount / s.rate / 60 or 0
			local id = (s.offerSerial or 0) + 1
			s.offerSerial = id
			s.pendingOffer = { id = id, entry = best, amount = amount, rival = RIVALS[math.random(1, #RIVALS)] }
			offerEvent:FireClient(player, {
				id = id, rival = s.pendingOffer.rival, who = best.rig:GetAttribute("PersonName") or "?",
				title = titleOf(best), amount = amount, tier = best.tier, loss = loss, minutes = minutes,
				alumni = math.min(s.alumni or 0, ALUMNI_CAP), step = ALUMNI_STEP,
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
	s.alumni = math.min((s.alumni or 0) + 1, ALUMNI_CAP)
	player:SetAttribute("Alumni", s.alumni)
	assignDesks(player)
	recompute(player)
	updateHirePad(player)
	toast:FireClient(player, ("+$%s from %s. ALUMNI x%d: your team gets promoted %d%% faster."):format(
		fmt(o.amount), o.rival, s.alumni, math.floor(s.alumni * ALUMNI_STEP * 100 + 0.5)))
end)

setMuted.OnServerEvent:Connect(function(player, v)
	local s = sessions[player.UserId]
	if s then s.muted = v == true end
end)

-- ============ IPO + THE TICKER ============

local function checkIPO(player, plot)
	local s = sessions[player.UserId]
	if not s or s.ipo or (s.valuation or 0) < IPO_AT then return end
	if not s.name then return end          -- a nameless company cannot list
	s.ipo = true
	s.ticker = tickerOf(s.name)
	refreshSign(plot)
	toast:FireAllClients(("%s (%s) just went PUBLIC at $%s valuation!"):format(s.name, s.ticker, fmt(s.valuation)), "news")
	popup(plot.hqPad, "PUBLICLY TRADED", GOLD)
end

local function pushTicker(player)
	-- v4.2: Ranks owns the boards (every company from $1K, plus the weekly board)
	if Econ and Econ.Ranks and Econ.Ranks.pushPlayer then Econ.Ranks.pushPlayer(player) return end
	local s = sessions[player.UserId]
	if not s or not s.ipo then return end
	pcall(function()
		if tickerStore then tickerStore:SetAsync(tostring(player.UserId), math.floor(s.valuation or 0)) end
	end)
end

-- THE BOARD at the road, two-sided, top ten public companies across all servers
local board
do
	local post = part({ Name = "TickerPost", Size = Vector3.new(1.2, 12, 1.2), CFrame = CFrame.new(0, 6, ROAD_Z + 30),
		Color = TRIM }, world)
	board = part({ Name = "TickerBoard", Size = Vector3.new(30, 12, 0.8), CFrame = CFrame.new(0, 16, ROAD_Z + 30),
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
		head.TextColor3 = GOLD
		head.TextSize = 34
		head.Font = Enum.Font.FredokaOne
		head.Parent = sg
		local list = Instance.new("TextLabel")
		list.Name = "List"
		list.Position = UDim2.new(0, 24, 0, 66)
		list.Size = UDim2.new(1, -48, 1, -76)
		list.BackgroundTransparency = 1
		list.Text = "No company has gone public yet. First to $" .. fmt(IPO_AT) .. " valuation."
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
	local cap = math.max(bestHuman * RIVAL_CAP_MULT, PUBLIC_RIVALS[#PUBLIC_RIVALS].base)
	return math.floor(math.min(r.base * (RIVAL_GROWTH ^ minutes), cap))
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
	for _, r in ipairs(PUBLIC_RIVALS) do
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
				for _, r in ipairs(PUBLIC_RIVALS) do table.insert(t, { name = r.name, value = rivalValuation(r, bestHumanSeen) }) end
				return t
			end,
			toast = function(p, text) toast:FireClient(p, text) end,
		})
		if not ok then warn("[SV] Ranks init failed: " .. tostring(err)); Econ.Ranks = nil end
	else
		Econ.Ranks = nil
	end
end

task.spawn(function()
	while true do
		for _, pl in ipairs(Players:GetPlayers()) do
			local plot = plotOf(pl)
			if plot then
				checkIPO(pl, plot)
				if not (Econ and Econ.Ranks) then pushTicker(pl) end   -- v4.2: the Ranks loop pushes every minute
			end
			-- OVERTAKE: the first time your valuation passes a rival, everyone hears
			local s = sessions[pl.UserId]
			if s then
				for _, r in ipairs(PUBLIC_RIVALS) do
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

local function serialize(player)
	local s = sessions[player.UserId]
	local plot = plotOf(player)
	if not s or not plot then return nil end
	local _, plotYaw = plot.pivot:ToEulerAnglesYXZ()
	local plotYawDeg = math.floor(math.deg(plotYaw) + 0.5)
	local placed = {}
	for _, e in ipairs(s.placed) do
		local l = plot.pivot:PointToObjectSpace(Vector3.new(e.x, 0, e.z))
		placed[#placed + 1] = { k = e.key, x = l.X, z = l.Z, y = ((e.yaw or 0) - plotYawDeg) % 360, p = e.price }
	end
	local wings = {}
	for i, slot in ipairs(plot.slots) do
		if slot.built then wings[tostring(i)] = { id = slot.built, lv = slot.level or 1 } end
	end
	local cash = cashOf(player)
	return {
		v = 1,
		layout = (CampusArch and CampusArch.LAYOUT) or 2,   -- the lot layout the furniture coordinates are in
		cash = cash and cash.Value or 0,
		hq = plot.hq.level,
		wings = wings,
		placed = placed,
		staff = s.staff,
		shipped = s.shipped,
		name = s.name,
		valuation = math.floor(s.valuation or 0),
		weekId = s.weekId,                                  -- v4.2 the weekly board: which week, and the value it started at
		weekBase = s.weekBase and math.floor(s.weekBase) or nil,
		ipo = s.ipo or false,
		launches = s.launches or 0,
		rate = s.rate,
		lastSeen = os.time(),
		tiers = (function()
			local t = {}
			for i, r in ipairs(s.rigs or {}) do t[i] = r.tier or 1 end
			return t
		end)(),
		talents = (function()
			local t = {}
			for i, r in ipairs(s.rigs or {}) do t[i] = r.talent or 1 end
			return t
		end)(),
		index = (function()
			local t = {}
			for k in pairs(s.index or {}) do table.insert(t, k) end
			return t
		end)(),
		-- v3.0: who each recruit was ("role:seed"), so they look the same after a rejoin
		people = (function()
			local t = {}
			for i, r in ipairs(s.rigs or {}) do t[i] = r.who and (r.who.role .. ":" .. r.who.seed) or "" end
			return t
		end)(),
		playtime = math.floor(s.playtime or 0),
		muted = s.muted == true,
		dailyDay = s.dailyDay or 0,          -- v3.1 daily streak: two integers, clamped on load
		streak = s.streak or 0,
		alumni = math.min(s.alumni or 0, ALUMNI_CAP),
		work = math.floor(s.work or 0),
		spinoffs = math.min(s.spinoffs or 0, SPINOFF_CAP),
		earned = math.floor(s.earned or 0),
		items = Econ and Econ.Inv and Econ.Inv.save(s) or nil,   -- v3.2 the bag: counts only
		apt = s.apt or 0,                                            -- v4.0 the apartment rung (0-3)
		vipDay = s.vipDay,                                          -- v4.2 the UTC day the daily VIP was picked up
		cars = Econ and Econ.Cars and Econ.Cars.save(s) or nil,     -- v4.0 owned car ids
		car = s.car,
	}
end

local function saveNow(player)
	if not saveStore or not loaded[player.UserId] then return false end
	local data = serialize(player)
	if not data then return false end
	local ok, err = pcall(function()
		saveStore:UpdateAsync(tostring(player.UserId), function(old)
			-- never let an older session overwrite a newer one
			if type(old) == "table" and (old.lastSeen or 0) > data.lastSeen then return nil end
			return data
		end)
	end)
	if not ok then warn("[SV] save failed for " .. player.Name .. ": " .. tostring(err)) end
	return ok
end

local function clampInt(v, lo, hi, default)
	if type(v) ~= "number" then return default end
	return math.clamp(math.floor(v), lo, hi)
end

local function applySave(player, plot, data)
	local s = sessions[player.UserId]
	if not s or not plot or type(data) ~= "table" then return end
	local cash = cashOf(player)
	local _, plotYaw = plot.pivot:ToEulerAnglesYXZ()
	local plotYawDeg = math.floor(math.deg(plotYaw) + 0.5)

	if cash then cash.Value = clampInt(data.cash, 0, 1e12, 0) end
	s.shipped = data.shipped == true or clampInt(data.staff, 0, 200, 0) > 0
	s.name = type(data.name) == "string" and data.name:sub(1, 20) or nil
	s.ticker = s.name and tickerOf(s.name) or nil
	s.valuation = clampInt(data.valuation, 0, 1e13, 0)
	s.weekId = clampInt(data.weekId, 0, 1e7, 0)          -- v4.2 (Ranks.rollWeek resets a stale or nonsense base)
	s.weekBase = data.weekBase ~= nil and clampInt(data.weekBase, 0, 1e13, 0) or nil
	s.ipo = data.ipo == true and s.name ~= nil
	s.launches = clampInt(data.launches, 0, 1e6, 0)

	-- offline earnings: a quarter rate, capped at 8 hours. A returning player
	-- should find something waiting, not a fortune (Roblox 2026 discovery
	-- scores D1..D28 -- this is the come-back-tomorrow mechanic)
	local away = math.clamp(os.time() - clampInt(data.lastSeen, 0, 4e9, os.time()), 0, 8 * 3600)
	local offline = math.floor(clampInt(data.rate, 0, 1e9, 0) * 0.25 * away)
	-- v2.7.0: on fixed price ladders 2 hours of income skips a whole HQ tier;
	-- coming back should find something useful waiting, not the next building
	if Econ and Econ.V3 then offline = math.min(offline, clampInt(data.rate, 0, 1e9, 0) * Econ.OFFLINE_CAP) end
	-- v4.2 HOME TURF: your apartment decides how much of the wait for your next step
	-- a return covers (Apartments.offline: never below the line above, up to one
	-- whole step, never two). The late game is where it counts (sim/offline_sim3.py).
	if Econ and Econ.Apt and Econ.Apt.offline and Econ.Apt.ladder then
		local apt = clampInt(data.apt, 0, 3, 0)
		local spins = clampInt(data.spinoffs, 0, SPINOFF_CAP, 0)
		local nxt, aft = Econ.Apt.ladder(clampInt(data.hq, 1, #HQ_LEVELS, 1), apt,
			function(l) return HQ_LEVELS[l] and HQ_LEVELS[l].cost or 0 end,
			math.floor(SPINOFF_BASE * (SPINOFF_GROWTH ^ spins)))
		offline = Econ.Apt.offline(clampInt(data.rate, 0, 1e9, 0), away, apt, cash and cash.Value or 0, nxt, aft)
		player:SetAttribute("OfflineApt", apt)
	end
	if offline > 0 and cash then
		cash.Value += offline
		player:SetAttribute("OfflineEarned", offline)
	end

	local level = clampInt(data.hq, 1, #HQ_LEVELS, 1)
	if level > 1 then buildShell(plot, level, false) end
	s.hqLevel = level
	if s.shipped then
		s.buildUnlocked = true
		plot.doorOpened = true
		for _, door in ipairs({ plot.hq.doorL, plot.hq.doorR }) do
			door.CFrame = door.CFrame * CFrame.new(0, 11, 0)
		end
		for _, slot in ipairs(plot.slots) do
			slot.prompt.Enabled = true
			slot.text.Text = "BUILD HERE"
		end
	end
	if type(data.wings) == "table" then
		for k, w in pairs(data.wings) do
			local i = tonumber(k)
			local roomId = type(w) == "table" and w.id or w        -- v1 saves stored the id string
			local lv = type(w) == "table" and clampInt(w.lv, 1, WING_MAX_LEVEL, 1) or 1
			if i and ROOM_BY_ID[roomId] and buildWing(player, plot, i, roomId, true) then
				local slot = plot.slots[i]
				for _ = 2, lv do
					slot.level += 1
					applyWingLevel(s, ROOM_BY_ID[roomId])
					if roomId == "office" then
						officeDesk(slot, 2 * slot.level - 1)
						officeDesk(slot, 2 * slot.level)
					end
				end
				if Econ and Econ.V3 then Econ.furnish(FurnitureKit, slot) end
				if CampusArch and CampusArch.grow and slot.model then pcall(CampusArch.grow, slot.model, slot.cf, slot.room, SLOT_W, SLOT_D, slot.level) end
				refreshWingPrompt(slot, plot, s)
			end
		end
	end
	if type(data.placed) == "table" then
		for _, e in ipairs(data.placed) do
			if type(e) == "table" and type(e.k) == "string" then
				local lx, lz, ly = tonumber(e.x) or 0, tonumber(e.z) or 0, tonumber(e.y) or 0
				-- saved in an older layout: carried into the same room at its new place
				if CampusArch and CampusArch.migrate then lx, lz, ly = CampusArch.migrate(lx, lz, ly, data.layout, SLOT_W, SLOT_D) end
				local w = plot.pivot:PointToWorldSpace(Vector3.new(lx, 0, lz))
				placeAt(player, plot, e.k, w.X, w.Z, (ly + plotYawDeg) % 360, true, clampInt(e.p, 0, 1e9, nil))
			end
		end
	end
	-- v3.0 TALENT INDEX: sanitized; rebuilt staff below are rediscoveries, not news
	s.index = {}
	if type(data.index) == "table" then
		for _, k in ipairs(data.index) do
			-- v4.2: `x and k:match(...)` keeps only match's FIRST return, so `t` was
			-- always nil and no saved Index entry was ever restored (found by selene:
			-- unbalanced_assignments, the first time it ran on this code)
			local role, t
			if type(k) == "string" then role, t = k:match("^(%a+):(%d)$") end
			t = tonumber(t)
			if role and t and StaffRig and StaffRig.ROLES[role] and t >= 1 and t <= #TALENT then s.index[k] = true end
		end
	end
	s.indexQuiet = true
	local staffN = clampInt(data.staff, 0, 200, 0)
	s.hireCost = HIRE_BASE
	for i = 1, staffN do
		s.staff = i
		if i > 1 then s.hireCost = math.floor(s.hireCost * hireGrowthAt(i)) end
		local talent = type(data.talents) == "table" and clampInt(data.talents[i], 1, #TALENT, 1) or 1
		local who
		local pe = type(data.people) == "table" and data.people[i]
		if type(pe) == "string" then
			local role, seed = pe:match("^(%a+):(%d+)$")
			seed = tonumber(seed)
			if role and seed and StaffRig and StaffRig.ROLES[role] and seed >= 1 and seed <= 1e9 then who = { role = role, seed = seed } end
		end
		spawnStaff(player, plot, i, talent, who)
		local r = s.rigs[#s.rigs]
		local tier = type(data.tiers) == "table" and clampInt(data.tiers[i], 1, #TIER_TITLE, 1) or 1
		if r then
			r.tier = tier
			r.seatedTime = (tier - 1) * PROMOTE_EVERY
			StaffRig.setTitle(r.rig, titleOf(r))
		end
	end
	s.indexQuiet = false
	if Econ and Econ.publishIndex then Econ.publishIndex(player, s) end
	s.playtime = clampInt(data.playtime, 0, 1e9, 0)
	s.muted = data.muted == true
	s.alumni = clampInt(data.alumni, 0, ALUMNI_CAP, 0)
	player:SetAttribute("Alumni", s.alumni)
	s.work = clampInt(data.work, 0, 1e9, 0)
	s.workNeed = math.floor(WORK_FIRST * (WORK_GROWTH ^ (s.launches or 0)))
	s.spinoffs = clampInt(data.spinoffs, 0, SPINOFF_CAP, 0)
	-- pre-v2.4 saves have no `earned`; valuation is the closest honest proxy
	s.earned = data.earned ~= nil and clampInt(data.earned, 0, 1e15, 0) or clampInt(data.valuation, 0, 1e15, 0)
	s.milestones = milestonesFromEarned(s.earned)
	s.dailyDay = clampInt(data.dailyDay, 0, 1e6, 0)
	s.streak = clampInt(data.streak, 0, 7, 0)
	-- v4.0: the apartment (clamped) and the cars (validated against the catalog)
	s.apt = clampInt(data.apt, 0, 3, 0)
	s.vipDay = clampInt(data.vipDay, 0, 1e7, 0)
	if Econ and Econ.Apt then pcall(Econ.Apt.onLoad, player, s) end
	if Econ and Econ.Cars then pcall(Econ.Cars.onLoad, player, s, data, plot) end
	recompute(player)
	refreshSign(plot)
	refreshHqPad(plot)
	updateHirePad(player)
end

local function loadOnce(player, plot)
	if loading[player.UserId] then return end
	loading[player.UserId] = true
	local data, ok = nil, false
	if saveStore then
		ok, data = pcall(function() return saveStore:GetAsync(tostring(player.UserId)) end)
		if not ok then
			warn("[SV] load FAILED for " .. player.Name .. " -- this session will not save")
			data = nil
		end
	end
	loading[player.UserId] = nil
	if ok then loaded[player.UserId] = true end     -- a failed read never saves
	if data then
		player:SetAttribute("Returning", true)
		applySave(player, plot, data)
	end
	if Econ and Econ.Inv then pcall(Econ.Inv.load, player, sessions[player.UserId], data and data.items) end
	if Econ and Econ.Daily and Econ.Daily.refresh then pcall(Econ.Daily.refresh, player) end
end

game:BindToClose(function()
	for _, pl in ipairs(Players:GetPlayers()) do saveNow(pl); pushTicker(pl) end
	task.wait(1)
end)
task.spawn(function()
	while true do
		task.wait(120)
		for _, pl in ipairs(Players:GetPlayers()) do saveNow(pl) end
	end
end)

-- ============ PLAYERS ============

-- v4.1: a do-block, so the handler has a name without a new top-level local
-- (this file sits at Luau's 200-local limit)
do
local function onJoin(player)
	Telemetry.joined(player)
	local plot = assignPlot(player)
	sessions[player.UserId] = {
		clicks = 0, shipped = false, rate = 0,
		staff = 0, desks = 0, hireCost = HIRE_BASE,
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
	local cash = Instance.new("IntValue"); cash.Name = "Cash"; cash.Value = START_CASH; cash.Parent = ls
	local rate = Instance.new("IntValue"); rate.Name = "Per Sec"; rate.Parent = ls
	local staff = Instance.new("IntValue"); staff.Name = "Staff"; staff.Parent = ls
	local val = Instance.new("IntValue"); val.Name = "Valuation"; val.Parent = ls

	-- load BEFORE the beats so a returning player's campus is standing when
	-- the intro camera arrives
	if plot then loadOnce(player, plot) end
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
	saveNow(player)          -- yields (DataStore)
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
end)

-- ============ STUDIO-ONLY DEV HOOK ============

if game:GetService("RunService"):IsStudio() then
	local dev = Instance.new("BindableFunction")
	dev.Name = "SVDev"
	dev.Parent = script
	dev.OnInvoke = function(action, player, arg)
		local s = sessions[player.UserId]
		local plot = plotOf(player)
		if not s then return "no session" end
		if action == "ship" then
			s.shipped = true
			s.buildUnlocked = true
			updateHirePad(player)
			return "ok"
		elseif action == "cash" then
			local c = cashOf(player)
			if c then c.Value += (tonumber(arg) or 0) end
			return "ok"
		elseif action == "upgrade" then
			if plot then tryUpgrade(player, plot) end
			return "ok"
		elseif action == "spinoff" then
			if not plot then return "no plot" end
			plot.spinArmed = os.clock() - 1        -- skip the confirm tap
			spinOff(player, plot)
			return ("spinoffs=%d rate=%d"):format(s and s.spinoffs or -1, s and s.rate or -1)
		elseif action == "earned" then
			if s then s.earned = tonumber(arg) or 0; checkMilestones(player, s) end
			return ("earned=%d milestones=%d rate=%d"):format(s and s.earned or 0, s and s.milestones or 0, s and s.rate or 0)
		elseif action == "talent" then
			-- v2.5: set the LAST hire's talent (1..5) for testing; snapshot the record first
			local r = s and s.rigs and s.rigs[#s.rigs]
			if not r then return "no staff" end
			r.talent = clampInt(tonumber(arg), 1, #TALENT, 1)
			local t = TALENT[r.talent]
			if t.color and StaffRig.setTalent then StaffRig.setTalent(r.rig, r.talent, t.color, t.name) end
			StaffRig.setTitle(r.rig, titleOf(r))
			recompute(player)
			return ("talent=%s x%.1f rate=%d"):format(t.name, t.mult, s.rate)
		elseif action == "save" then
			return saveNow(player) and "saved" or "NOT saved"
		elseif action == "rival" then
			return "hit " .. rivalLaunch()
		elseif action == "launch" then
			local m = MARKETS[tonumber(arg) or 1]
			if plot and m then launchProduct(player, plot, m) end
			return "launched " .. (m and m.name or "?")
		elseif action == "buzzoff" then
			s.launch = nil
			return "buzz cleared"
		elseif action == "wingup" then
			local slot = plot and plot.slots[tonumber(arg) or 1]
			if not slot or not slot.built then return "no wing there" end
			upgradeWing(player, plot, slot)
			return ("%s lv%d desks=%d compute=%d quality=%.2f morale=%.2f"):format(slot.room.name, slot.level, s.desks, s.compute or 0, s.quality or 0, s.morale or 0)
		elseif action == "share" then
			s.share = math.clamp(tonumber(arg) or 1, SHARE_FLOOR, 1)
			return "share " .. s.share
		elseif action == "peek" then
			local ok, d = pcall(function() return saveStore and saveStore:GetAsync(tostring(player.UserId)) end)
			return ok and d or ("err " .. tostring(d))
		elseif action == "wipe" then
			pcall(function() saveStore:RemoveAsync(tostring(player.UserId)) end)
			return "wiped"
		elseif action == "offer" then
			-- fire one acquisition offer now (same code path as the loop)
			local best
			for _, r in ipairs(s.rigs or {}) do
				if (r.tier or 1) >= OFFER_MIN_TIER and (not best or r.tier > best.tier) then best = r end
			end
			if not best then return "nobody above tier " .. OFFER_MIN_TIER end
			-- capped at rehire cost + 60s of the person's output: selling a Lead
			-- and rehiring an intern must never be a money printer (it was: quality
			-- scaled the offer but not the hire)
			local cashNow = cashOf(player)
			local amount = offerAmountOf(s, cashNow and cashNow.Value or 0)
			local id = (s.offerSerial or 0) + 1
			s.offerSerial = id
			s.pendingOffer = { id = id, entry = best, amount = amount, rival = RIVALS[1] }
			offerEvent:FireClient(player, { id = id, rival = RIVALS[1], who = best.rig:GetAttribute("PersonName") or "?",
				title = titleOf(best), amount = amount, tier = best.tier,
				minutes = (s.rate or 0) > 0 and amount / s.rate / 60 or 0,
				loss = math.floor((TIER_RATE[best.tier] - TIER_RATE[1]) * hqMultOf(plot)),
				alumni = math.min(s.alumni or 0, ALUMNI_CAP), step = ALUMNI_STEP })
			return ("offered $%d for %s"):format(amount, tostring(best.rig:GetAttribute("PersonName")))
		elseif action == "tier" then
			local r = s.rigs and s.rigs[1]
			if r then r.tier = tonumber(arg) or 1; r.seatedTime = (r.tier - 1) * PROMOTE_EVERY
				StaffRig.setTitle(r.rig, titleOf(r)); recompute(player) end
			return "tier set"
		elseif action == "work" then
			s.work = tonumber(arg) or 0
			return "work set"
		elseif action == "product" then
			if plot then offerProduct(player, plot) end
			return "offered"
		elseif action == "name" then
			s.name = tostring(arg); s.ticker = tickerOf(s.name); if plot then refreshSign(plot) end
			return "named"
		elseif action == "valuation" then
			s.valuation = tonumber(arg) or 0
			if plot then checkIPO(player, plot) end
			return "ok"
		elseif action == "bot" then
			--[[ v2.7.2 CLEAN-RUN BOT. Plays the real handlers (the same ones the
			prompts, pads and remotes call) by following the on-screen guide:
			taps WRITE CODE once a second, launches a ready product after 2 s,
			and makes one guide purchase every `pace` seconds when it can afford
			it. Logs HQ times, spin-off, waits, and launch share. Read with
			"botlog". Studio only, like the rest of this hook. ]]
			local pace = tonumber(arg) or 20
			s.bot = { t0 = os.clock(), log = {}, pace = pace, paid = 0, earnedStart = s.earned or 0, lastBuy = os.clock(), longest = 0, buys = 0, fails = 0, running = true }
			local B = s.bot
			local function note(ev)
				local line = ("%5.1f min  %s"):format((os.clock() - B.t0) / 60, ev)
				table.insert(B.log, line)
				print("[BOT] " .. line)
			end
			note(("start  pace %ds  hq %d  cash %d"):format(pace, plot.hq.level, cashOf(player).Value))
			task.spawn(function()
				local lastTap, lastMin, lastHq = 0, -1, plot.hq.level
				while B.running and player.Parent and sessions[player.UserId] == s do
					local now = os.clock()
					local cash = cashOf(player)
					if now - lastTap >= 1 then lastTap = now; writeCode(player, plot) end
					if s.pendingProduct and not B.launchAt then B.launchAt = now + 2 end
					if B.launchAt and now >= B.launchAt then
						B.launchAt = nil
						if s.pendingProduct then
							local before = cash.Value
							launchProduct(player, plot, s.pendingProduct[1], 1, false)
							B.paid += cash.Value - before
						end
					end
					-- v3.0.2: log every carry's outcome (home or lost) per tier
					if B.carry and not player:GetAttribute("Carrying") then
						local ok = s.staff > B.carry.staff
						B.carries = B.carries or {}
						local k = B.carry.tier .. (ok and " home" or " LOST")
						B.carries[k] = (B.carries[k] or 0) + 1
						note(("carry %s %s after %.0f s"):format(B.carry.tier, ok and "home" or "LOST", now - B.carry.t0))
						B.carry = nil
					end
					local key = player:GetAttribute("Objective")
					-- v3.0: carrying a candidate home = walk there at the default 16 studs/s
					if key == "carry" then
						local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
						local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
						-- (the guide's objective lags delivery by up to 0.4 s: only a real carry counts)
						if root and hum and player:GetAttribute("Carrying") then
							-- v3.0.2: walk like a person, not a laser: your real (scooter) speed,
							-- a +-35 degree weave round lamps and cars, and one 1.5 s stop
							-- a third of the way home to look around
							B.carry = B.carry or { t0 = now, tier = player:GetAttribute("Carrying") or "?", staff = s.staff }
							local to = plot.hqPad.Position
							local d = Vector3.new(to.X - root.Position.X, 0, to.Z - root.Position.Z)
							B.carry.total = B.carry.total or d.Magnitude
							if not B.carry.stopAt and d.Magnitude < B.carry.total * 0.67 then B.carry.stopAt = now end
							local stopped = B.carry.stopAt and now - B.carry.stopAt < 1.5
							if d.Magnitude > 1 and not stopped then
								local dir = CFrame.Angles(0, math.sin((now - B.carry.t0) * 1.3) * math.rad(35), 0):VectorToWorldSpace(d.Unit)
								local np = root.Position + dir * math.min(d.Magnitude, hum.WalkSpeed * 0.25)
								player.Character:PivotTo(CFrame.lookAt(np, np + dir))
							end
						end
					elseif key == "recruit" and now - B.lastBuy >= pace and Econ.Drop then
						local cand = Econ.Drop.bestFor(player, cash.Value)
						local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
						if cand and root then
							-- walk out (time it like the sim: distance / 16), then recruit
							local walk = (Vector3.new(cand.pos.X, 0, cand.pos.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude / 16
							task.wait(walk)
							player.Character:PivotTo(CFrame.new(cand.pos + Vector3.new(0, 1, 3)))
							Econ.Drop.devRecruit(player, cand.index)
							B.recruits = (B.recruits or 0) + 1
							note(("recruit %s (walked %.0f s)"):format(cand.tier.name, walk))
							B.lastBuy = os.clock()
						end
					end
					if now - B.lastBuy >= pace then
						local before = cash.Value
						local did
						if key == "hire" or key == "hire2" then
							hire(player, plot); did = "hire"
						elseif key == "build" or key == "wing" then
							for i, slot in ipairs(plot.slots) do
								if not slot.built then
									local rid = (Econ and Econ.V3) and Econ.nextRoom(plot) or "office"
									if buildWing(player, plot, i, rid, false) then did = "build " .. rid end
									break
								end
							end
						elseif key == "wingup" then
							for _, slot in ipairs(plot.slots) do
								if slot.built and not wingMaxed(s, slot) then
									local lv = slot.level or 1
									upgradeWing(player, plot, slot)
									if (slot.level or 1) > lv then did = ("level %s -> %d"):format(slot.room.id, slot.level) end
									break
								end
							end
						elseif key == "decor" then
							-- v3.2.1: a guide-following player decorates until the first Vibe star
							local keys = { "pottedPlant", "lampSquareFloor", "cardboardBoxClosed" }
							local k = keys[(#s.placed % #keys) + 1]
							for gx = -12, 12, 4 do
								for gz = -10, 10, 4 do
									if not did then
										local at = plot.g(gx, 0, gz).Position
										if placeAt(player, plot, k, at.X, at.Z, 0, false) then did = "decor " .. k end
									end
								end
							end
						elseif key == "hq" then
							local nxt = HQ_LEVELS[plot.hq.level + 1]
							if nxt and cash.Value >= nxt.cost then tryUpgrade(player, plot); did = "hq" end
						elseif key == "apartment" and Econ and Econ.Apt and Econ.Apt.botBuy then
							if Econ.Apt.botBuy(player) then did = "apartment" end
						elseif key == "spin" then
							if cash.Value >= spinoffCostOf(s) then
								plot.spinArmed = os.clock() - 1
								spinOff(player, plot)
								note(("SPIN-OFF  (kept %d staff)  launch share %.0f%%"):format(s.staff or 0,
									100 * B.paid / math.max(1, (s.earned or 0) - B.earnedStart)))
								B.spun = (B.spun or 0) + 1
								if B.spun >= (tonumber(B.runs) or 1) then B.running = false end
								did = "spin"
							end
						end
						if did then
							local spent = before - cash.Value
							if spent > 0 or did == "spin" then
								local wait = now - B.lastBuy
								B.buys += 1
								if wait > B.longest and B.buys > 1 then B.longest = wait end
								if wait > pace + 45 then note(("long wait %.0f s before %s"):format(wait, did)) end
								B.lastBuy = now
								if did ~= "hq" and did ~= "spin" and did ~= "hire" then note(("%s  $%d"):format(did, spent)) end
							elseif did ~= "hq" and not (did == "hire" and s.staff == 1) then
								B.fails += 1
								if B.fails <= 12 then note(("REFUSED %s (guide said %s, cash %d)"):format(did, tostring(key), cash.Value)) end
							end
						end
					end
					if plot.hq.level ~= lastHq then
						lastHq = plot.hq.level
						note(("HQ %d  staff %d  rate %d/s  rooms %d"):format(lastHq, s.staff, s.rate or 0, Econ and Econ.slotsBuilt(plot) or 0))
					end
					local m = math.floor((now - B.t0) / 60)
					if m ~= lastMin then
						lastMin = m
						if m % 2 == 0 then
							note(("tick  cash %d  rate %d  staff %d/%d  guide %s: %s"):format(cash.Value, s.rate or 0, s.staff,
								capacityOf(player), tostring(key), tostring(player:GetAttribute("ObjectiveText"))))
						end
					end
					if now - B.t0 > 45 * 60 then note("TIMEOUT 45 min"); B.running = false end
					task.wait(0.25)
				end
				note(("end  buys %d  longest wait %.0f s  refused %d"):format(B.buys, B.longest, B.fails))
				for k, v in pairs(B.carries or {}) do note(("carries  %s x%d"):format(k, v)) end
			end)
			return "bot started"
		elseif action == "rolls" then
			-- v3.2.1 test hook: roll the door talent n times at this player's Vibe luck
			local n = math.clamp(tonumber(arg) or 20000, 1, 200000)
			local luck = player:GetAttribute("VibeLuck") or 1
			local counts = { 0, 0, 0, 0, 0 }
			for _ = 1, n do local t = TALENT.roll(luck); counts[t] += 1 end
			return ("luck %.1f  n %d  regular %d  skilled %d  star %d  genius %d  unicorn %d"):format(luck, n, counts[1], counts[2], counts[3], counts[4], counts[5])
		elseif action == "item" then
			-- v3.2 test hook: put an item in the bag (Items.LIST id)
			if not (Econ and Econ.Inv) then return "no Inventory" end
			return Econ.Inv.grant(player, tostring(arg), 1, "Dev") and "granted" or "unknown item"
		elseif action == "seats" then
			-- v3.5 audit hook: the seat homes the game seats people at (world x, z)
			local t = {}
			for _, h in ipairs(deskHomes(s, plot)) do table.insert(t, { h.cf.Position.X, h.cf.Position.Z, h.room }) end
			return t
		elseif action == "apt" then
			-- v4.2 test hook: set the apartment rung (0-3)
			s.apt = math.clamp(math.floor(tonumber(arg) or 0), 0, 3)
			recompute(player)
			return "apt=" .. s.apt
		elseif action == "vip" then
			-- v4.2 test hook: the daily VIP now, ignoring the day
			local okV = Econ and Econ.Apt and Econ.Apt.trySpawnVip and Econ.Apt.trySpawnVip(player, true)
			return okV and "vip spawned" or "no vip"
		elseif action == "vippick" then
			if not (Econ and Econ.Drop and Econ.Drop.devPickVip) then return "no TalentDrop" end
			Econ.Drop.devPickVip(player)
			return ("carrying=%s vipDay=%s"):format(tostring(player:GetAttribute("Carrying")), tostring(s.vipDay))
		elseif action == "recruit" then
			-- v3.0 test hook: recruit tier n (1 walk-in .. 4 genius) through the real recruit()
			if not (Econ and Econ.Drop) then return "no TalentDrop" end
			Econ.Drop.devRecruit(player, tonumber(arg) or 1)
			return ("carrying=%s"):format(tostring(player:GetAttribute("Carrying")))
		elseif action == "botlog" then
			return s.bot and table.concat(s.bot.log, "\n") or "no bot"
		elseif action == "botstop" then
			if s.bot then s.bot.running = false end
			return "stopping"
		elseif action == "state" then
			return { plot = plot and plot.index or 0, hqLevel = plot and plot.hq.level or 0,
				shipped = s.shipped, placedDesks = s.placedDesks, placedMorale = s.placedMorale,
				placed = #s.placed, capacity = capacityOf(player), rate = s.rate, staff = s.staff,
				name = s.name, valuation = s.valuation, ipo = s.ipo, launches = s.launches,
				boost = boostOf(s), loaded = loaded[player.UserId] == true,
				work = s.work, workNeed = s.workNeed, pendingOffer = s.pendingOffer ~= nil,
				tiers = (function() local t = {} for i, r in ipairs(s.rigs or {}) do t[i] = r.tier end return table.concat(t, ",") end)() }
		end
		return "unknown"
	end
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

print(("SILICON VALLEY TYCOON -- %d plots on the road, heightmap valley, downtown east."):format(#plots))
