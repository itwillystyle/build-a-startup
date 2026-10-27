--[[ Journey: the guided core loop, as pure functions (v4.3).

No services, no requires, no Instances: tests/offline runs it in Lune.
SiliconCore builds a plain `st` table from the session every second and asks:

  Journey.task(st)       the story task that overrides the "cheapest next buy"
                         guide right now, or nil
  Journey.milestone(st)  the BIG goal, always shown under the quest card
                         (the next HQ level, then GO PUBLIC, then the
                         spin-off)
  Journey.tip(st)        the next one-time HUD explanation (LAUNCH, BAG, INDEX,
                         RANKS, PHONE), or nil
  Journey.LADDER[level]  what each HQ level unlocks: ONE headline + the task

WHY (his 29 Sep Wilz run, 19 min, measured): LAUNCH was never pressed (five
half-pay auto-launches), the company car arrived and nothing followed, the
daily card opened over it and sat for 1.5 min, "Buy a Studio" only showed at
7:40 and the Loft at 15:20, and the last 3 minutes were standing still with
the Loft affordable. Every HQ level now hands over one new thing AND the task
that uses it, and the next big goal is never off screen.

st fields (all plain values):
  hq, shipped, staff, cap, cash, rate, apt, listed, spinCost, nextMult, nextHqCost, nextHqName,
  keepers, keepSlots, aptNext = { name, price, slots } (the home-keeper suggestion, see the end of task()),
  hasCar, seated, nearRes, vipStanding, vipDone, geniusAvailable, geniusDone,
  seriesA, productReady, launched, items, indexCount, dailyReady, carrying,
  jr = { drove, res } and tips = { [id] = true } ]]

local J = {}

J.IPO_RAISE = 60   -- GO PUBLIC raises this many seconds of income (a moment, not a skip)
J.SPIN_NEAR = 0.5  -- a spin-off is "in reach" at this share of its cost (the home is suggested then, not at the last second)

-- ---------------------------------------------------------------- the ladder
-- One headline per level, each with a task you do right away (Tizzy: every
-- unlock is a new VERB, not a bigger number). Level 1 is the garage opening.
J.LADDER = {
	[2] = { headline = "COMPANY CAR", task = "Drive downtown to The Residences",
		blurb = "Your company car is parked at the lot. Take it downtown." },
	[3] = { headline = "GENIUS HIRES", task = "Recruit your first GENIUS",
		blurb = "The rarest people stand at the far end of the street." },
	[4] = { headline = "SERIES A", task = "Close your Series A on the PHONE",
		blurb = "A big investor wants in. Pitch them." },
	[5] = { headline = "GO PUBLIC", task = "Ring the bell: GO PUBLIC",
		blurb = "List your company on the Valley Exchange." },
}

local function money(n)
	n = math.floor(n or 0)
	for _, u in ipairs({ { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }) do
		if n >= u[1] then
			return ("$%s%s"):format((("%.1f"):format(n / u[1])):gsub("%.0$", ""), u[2])
		end
	end
	return "$" .. n
end
J.money = money

-- the headline a level hands you, or nil if you already have it (a spun-off
-- company reaching HQ 2 again already owns its car)
function J.headline(level, st)
	local l = J.LADDER[level]
	if not l then return nil end
	if level == 2 and st and st.hasCar then return nil end
	return l.headline, l.task
end

-- ---------------------------------------------------------------- tasks
-- returns { key, title, sub, target } (target: "car" | "residences" | "vip" | "lot" |
-- "genius" | "phone" | "gopublic" | nil) or nil to let the normal guide choose
function J.task(st)
	if not st.shipped or (st.staff or 0) < 1 or st.carrying or st.productReady then return nil end
	local hq = st.hq or 1
	local jr = st.jr or {}
	-- HQ 2: the car, then the drive, then the home
	if hq >= 2 and st.hasCar and not jr.drove then
		return { key = "car", title = "Hop in your car", sub = st.touch and "Tap CAR" or "Press C or click CAR", target = "car" }
	end
	-- 17 Oct (Luke's playtest): only once the next home is affordable; it sent a new player to
	-- a $40,000 home with $900 ("a waste of my time")
	local home = st.aptNext
	local canBuy = hq >= 2 and (st.apt or 0) == 0 and home and (st.cash or 0) >= (home.price or math.huge)
	-- 20 Oct (Luke's live run): arriving used to END the step (nearRes sets jr.res) with nothing
	-- after it, so the guide sent him back to the Design Studio: "you went to the residences for
	-- nothing". At the door with the money, the step is the purchase.
	if canBuy and st.nearRes then
		local name = tostring(home.name or "home")
		name = name:sub(1, 1):upper() .. name:sub(2):lower()
		return { key = "buyhome", title = ("Buy your %s at the front desk"):format(name), sub = money(home.price), target = "residences" }
	end
	if canBuy and not jr.res then
		return { key = "drive", title = "Drive to The Residences", sub = "On the ring, south-west of the park", target = "residences" }
	end
	-- the VIP that comes with your first home
	if (st.apt or 0) >= 1 and st.vipStanding and not st.vipDone then
		if (st.staff or 0) >= (st.cap or 0) then
			-- a VIP you can't seat would just refuse at the pickup: make room first
			return { key = "vipseat", title = "Make room for your VIP", sub = st.level and "Every seat is taken: BUILD a floor with desks" or "Every seat is taken: build or upgrade a room", target = "lot" }
		end
		return { key = "vip", title = "Pick up your VIP recruit", sub = "Outside The Residences. Bring them home!", target = "vip" }
	end
	-- HQ 3: the first Genius run
	if hq >= 3 and not st.geniusDone and st.geniusAvailable then
		return { key = "genius", title = "Recruit your first GENIUS", sub = "Far end of the street. Their headhunter is fast!", target = "genius" }
	end
	-- HQ 5: go public before anything else (a Series A you skipped is still in the phone)
	if hq >= 5 and not st.listed and st.atCap ~= false then   -- v4.6: the Wafers go public at the top of the blueprint
		return { key = "gopublic", title = "GO PUBLIC!", sub = "Tap GO PUBLIC and ring the bell", target = "gopublic" }
	end
	-- HQ 4: the Series A pitch. P-5: a save with Bob's story goes to Bob's office instead
	if J.bobPayoffDue(st) and hq == 4 then
		return { key = "bob", title = "Go to Bob's office", sub = "He wants to talk. Bring your numbers.", target = "bob" }
	end
	if hq == 4 and not st.seriesA then
		return { key = "seriesa", title = "Close your Series A", sub = "Open your PHONE: a big investor texted", target = "phone" }
	end
	--[[ A home is a SUGGESTION, never a gate. It appears only when a spin-off is in reach
		and more of your rare people would be lost than your home has seats for, and
		only when the next home is affordable right now. A home you can't afford, or
		already have enough of, is never mentioned. Fields (all optional, nil = no
		suggestion): keepers (Star+ staff who would qualify), keepSlots (seats your
		home has), aptNext = { name, price, slots } (the next home up, or nil at the top). ]]
	local nx = st.aptNext
	if st.listed and nx and (st.cash or 0) >= (st.spinCost or math.huge) * J.SPIN_NEAR
		and (st.keepers or 0) > (st.keepSlots or 0) and (st.cash or 0) >= (nx.price or math.huge) then
		local name = tostring(nx.name or "home")
		name = name:sub(1, 1):upper() .. name:sub(2):lower()
		return { key = "apartment", title = ("Buy a %s"):format(name),
			sub = nx.slots and ("Keeps %d of your people at a spin-off"):format(nx.slots) or "Keeps your people at a spin-off",
			target = "residences" }
	end
	return nil
end

-- 20 Oct (Luke): during the drive step a marker should hover over your car so you can find it,
-- without more words on screen. The goal marker is that marker: on the car while you are on
-- foot, on the sales desk once you sit down (or when no car is out yet).
function J.driveTarget(seated, carPos, deskPos)
	if not seated and carPos then return carPos end
	return deskPos
end

-- ---------------------------------------------------------------- the big goal
-- { title, sub, cost } always: what the whole run is working toward next
--[[ P-5 BOB, THE FIRST BOSS INVESTOR (spec docs/superpowers/specs/2026-10-25-bob-first-boss-investor-design.md).
A new save's intro shows Bob laughing you out; until floor 13 (the HQ 4 stage, WaferPlan.STAGE_AT[3])
the big goal is "PROVE BOB WRONG", and at HQ 4 his office replaces the phone Series A. ]]
J.BOB_FLOOR = 13

function J.bobPayoffDue(st)
	return st.bobArc == true and st.bobPaid ~= true and st.seriesA ~= true and (st.hq or 1) >= 4
end

-- why Bob's door can't play the payoff right now, or nil: the scene freezes you for 20 s, which would
-- lose a carried recruit to the headhunters or leave a car driving itself (review minor, 26 Oct)
function J.bobDoorBusy(who)
	if who.carrying then return "Drop off your recruit first" end
	if who.seated then return who.car and "Get out of the car first" or "Stand up first" end
	return nil
end

-- the goal card's Bob framing, or nil; keeps the replaced milestone's cost/unlock (one card, spec 3d)
function J.bobGoal(st)
	if st.bobArc ~= true or st.bobPaid == true then return nil end
	local floor = st.level or 1
	if floor >= J.BOB_FLOOR or (st.hq or 1) >= 4 then return nil end
	return { title = "PROVE BOB WRONG", sub = ("Floor %d of %d · his door opens at %d"):format(floor, J.BOB_FLOOR, J.BOB_FLOOR),
		bob = floor / J.BOB_FLOOR }
end

function J.milestone(st)
	local m = J.milestoneBase(st)
	local b = J.bobGoal(st)
	if b and m then
		return { title = b.title, sub = b.sub, bob = b.bob, cost = m.cost, unlock = m.unlock }
	end
	return m
end

function J.milestoneBase(st)
	local hq = st.hq or 1
	-- v4.6 THE WAFERS: the big goal is the next milestone LEVEL (5 / 9 / 13 / 18, then the top of the blueprint)
	if st.msLevel then
		local cost = st.msCost or 0
		local head = (hq < 5) and J.headline(hq + 1, st) or "GO PUBLIC"
		local sub = ("Build %d more floor%s: %s"):format(st.msLevel - (st.level or 1), (st.msLevel - (st.level or 1)) == 1 and "" or "s", money(cost))
		return { title = ("LEVEL %d: %s"):format(st.msLevel, head or "NEXT"), sub = sub, cost = cost, unlock = head }
	end
	if hq < 5 and st.nextHqCost then
		return { title = ("HQ %d: %s"):format(hq + 1, st.nextHqName or "NEXT HQ"),
			sub = "Upgrade your HQ: " .. money(st.nextHqCost), cost = st.nextHqCost,
			unlock = J.headline(hq + 1, st) }
	end
	if not st.listed then
		return { title = "GO PUBLIC", sub = "List your company on the Valley Exchange", cost = nil }
	end
	return { title = "SPIN OFF", sub = ("Start a new company: x%s money"):format(st.nextMult or "?"), cost = st.spinCost }
end

-- v4.4 his screenshot: NEXT GOAL "Save up to spin off" over BIG GOAL "SPIN OFF",
-- the same step twice. When the quest card already IS the big goal, the big card
-- hides. Takes the quest key (refreshObjective's `key`) and a milestone table.
function J.sameStep(key, m)
	if not (key and m and m.title) then return false end
	if key == "spin" then return m.title == "SPIN OFF" end
	if key == "gopublic" then return m.title == "GO PUBLIC" end
	if key == "hq" then return m.title:sub(1, 3) == "HQ " end
	return false
end

-- ---------------------------------------------------------------- HUD tips
-- One at a time, each once for life. The client points at `target` (a path
-- under PlayerGui) and reports it seen.
J.TIPS = {
	-- v5 (UI pass): the copy is one short line a 10-year-old reads at a glance,
	-- LAUNCH lives in the bottom slot, the Index tip waits for a SECOND kind of
	-- hire (at the first it landed on top of "walk to your lot"), and the daily
	-- reward has its own rail button
	-- 18 Oct (option A): LAUNCH! is its own button (Hud.Launch) since 16 Oct, and WRITE CODE
	-- is hidden away from the laptop now, so a tip pointed at it would never show
	{ id = "launch", target = "Hud.Launch", title = "LAUNCH",
		body = "Tap it for a big payday. Wait too long: half pay.",
		when = function(st) return st.productReady and not (st.jr and st.jr.launched) end },
	{ id = "bag", target = "Rail.Column.BagButton", title = "BAG",
		body = "Items you win live here. Coffee makes code 3x faster.",
		when = function(st) return (st.items or 0) > 0 end },
	{ id = "index", target = "Rail.Column.IndexButton", title = "INDEX",
		body = "Collect every kind of hire. Each full line: +5% money.",
		when = function(st) return (st.indexCount or 0) >= 2 end },
	{ id = "ranks", target = "RanksCorner.RanksButton", title = "RANKS",
		body = "See how your company ranks. New board every Monday.",
		when = function(st) return (st.hq or 1) >= 2 and st.jr and st.jr.drove end },
	{ id = "daily", target = "Rail.Column.DailyButton", title = "DAILY",
		body = "A gift every day you play. Day 7 is the biggest.",
		when = function(st) return st.dailyReady and (st.hq or 1) >= 2 and st.jr and st.jr.res end },
}

function J.tip(st)
	if st.carrying or st.seated then return nil end
	local seen = st.tips or {}
	for _, t in ipairs(J.TIPS) do
		-- v5: while an app waits to launch (its full-pay clock running) only the
		-- LAUNCH tip may speak: a DAILY tip over a ready LAUNCH was two loud things
		if not seen[t.id] and t.when(st) and (t.id == "launch" or not st.productReady) then return t end
	end
	return nil
end

function J.tipById(id)
	for _, t in ipairs(J.TIPS) do
		if t.id == id then return t end
	end
	return nil
end

-- the flags we save (anything else in a save is dropped on load)
-- P-5 (25 Oct): bobArc = this save got Bob's intro (new saves only); bobPaid = Bob's payoff
-- happened. Neither is cleared by a spin-off (spec 5b-3).
J.FLAGS = { "drove", "res", "launched", "genius", "seriesA", "bobArc", "bobPaid" }

function J.cleanFlags(raw)
	local out = {}
	if type(raw) ~= "table" then return out end
	for _, k in ipairs(J.FLAGS) do
		if raw[k] == true then out[k] = true end
	end
	return out
end

function J.cleanTips(raw)
	local out = {}
	if type(raw) ~= "table" then return out end
	for _, id in ipairs(raw) do
		if type(id) == "string" and J.tipById(id) then out[id] = true end
	end
	return out
end

function J.tipList(set)
	local out = {}
	for _, t in ipairs(J.TIPS) do
		if set and set[t.id] then table.insert(out, t.id) end
	end
	return out
end

return J
