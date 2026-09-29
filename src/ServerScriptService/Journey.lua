--[[ Journey: the guided core loop, as pure functions (v4.3).

No services, no requires, no Instances: tests/offline runs it in Lune.
SiliconCore builds a plain `st` table from the session every second and asks:

  Journey.task(st)       the story task that overrides the "cheapest next buy"
                         guide right now, or nil
  Journey.milestone(st)  the BIG goal, always shown under the quest card
                         (the next HQ level with the apartment it needs, then
                         GO PUBLIC, then the spin-off)
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
  need = { tier, name, price } (the apartment the NEXT HQ level needs, from Progression)
  hasCar, seated, nearRes, vipStanding, vipDone, geniusAvailable, geniusDone,
  seriesA, productReady, launched, items, indexCount, dailyReady, carrying,
  jr = { drove, res } and tips = { [id] = true } ]]

local J = {}

J.IPO_RAISE = 60   -- GO PUBLIC raises this many seconds of income (a moment, not a skip)

-- ---------------------------------------------------------------- the ladder
-- One headline per level, each with a task you do right away (Tizzy: every
-- unlock is a new VERB, not a bigger number). Level 1 is the garage opening.
J.LADDER = {
	[2] = { headline = "COMPANY CAR", task = "Drive downtown to The Residences",
		blurb = "Your first home is downtown. It unlocks HQ 3." },
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
		return { key = "car", title = "Hop in your company car", sub = st.touch and "Tap CAR" or "Press C or click CAR", target = "car" }
	end
	if hq >= 2 and (st.apt or 0) == 0 and not jr.res then
		return { key = "drive", title = "Drive to The Residences", sub = "Downtown, the east end of the road", target = "residences" }
	end
	-- the VIP that comes with your first home
	if (st.apt or 0) >= 1 and st.vipStanding and not st.vipDone then
		if (st.staff or 0) >= (st.cap or 0) then
			-- a VIP you can't seat would just refuse at the pickup: make room first
			return { key = "vipseat", title = "Make room for your VIP", sub = "Every seat is taken: build or upgrade a room", target = "lot" }
		end
		return { key = "vip", title = "Pick up your VIP recruit", sub = "Outside The Residences. Bring them home!", target = "vip" }
	end
	-- HQ 3: the first Genius run
	if hq >= 3 and not st.geniusDone and st.geniusAvailable then
		return { key = "genius", title = "Recruit your first GENIUS", sub = "Far end of the street. Their headhunter is fast!", target = "genius" }
	end
	-- HQ 5: go public before anything else (a Series A you skipped is still in the phone)
	if hq >= 5 and not st.listed then
		return { key = "gopublic", title = "GO PUBLIC!", sub = "Tap GO PUBLIC and ring the bell", target = "gopublic" }
	end
	-- HQ 4: the Series A pitch
	if hq == 4 and not st.seriesA then
		return { key = "seriesa", title = "Close your Series A", sub = "Open your PHONE: a big investor texted", target = "phone" }
	end
	-- then the apartment the NEXT level needs, the moment you can afford it (after this
	-- level's own story task, which the level-up banner just promised)
	local need = st.need               -- { tier, name, price } the next HQ needs, or nil
	if need and (st.apt or 0) < need.tier and (st.cash or 0) >= need.price then
		return { key = "apartment", title = ("Buy a %s"):format(need.name),
			sub = st.nearRes and "Sales desk, in the lobby" or "The Residences, downtown", target = "residences" }
	end
	return nil
end

-- ---------------------------------------------------------------- the big goal
-- { title, sub, cost } always: what the whole run is working toward next
function J.milestone(st)
	local hq = st.hq or 1
	if hq < 5 and st.nextHqCost then
		local need = st.need
		local owns = not need or (st.apt or 0) >= need.tier
		local cost = st.nextHqCost + (owns and 0 or need.price)
		local sub = owns and ("Upgrade your HQ: " .. money(st.nextHqCost))
			or ("Needs a %s (%s) + %s"):format(need.name, money(need.price), money(st.nextHqCost))
		return { title = ("HQ %d: %s"):format(hq + 1, st.nextHqName or "NEXT HQ"), sub = sub, cost = cost,
			unlock = J.headline(hq + 1, st) }
	end
	if not st.listed then
		return { title = "GO PUBLIC", sub = "List your company on the Valley Exchange", cost = nil }
	end
	return { title = "SPIN OFF", sub = ("Start again with x%s money forever"):format(st.nextMult or "?"), cost = st.spinCost }
end

-- ---------------------------------------------------------------- HUD tips
-- One at a time, each once for life. The client points at `target` (a path
-- under PlayerGui) and reports it seen.
J.TIPS = {
	{ id = "launch", target = "RightColumn.Column.Launch", title = "LAUNCH your app!",
		body = "Tap it (or press L) for a big payday. Once you know how, a forgotten app launches itself at HALF pay.",
		when = function(st) return st.productReady and not (st.jr and st.jr.launched) end },
	{ id = "bag", target = "Rail.Column.BagButton", title = "Your BAG",
		body = "Items you earn live here. Coffee makes your code 3x faster. Tap to use it.",
		when = function(st) return (st.items or 0) > 0 end },
	{ id = "index", target = "Rail.Column.IndexButton", title = "Talent INDEX",
		body = "Every new kind of hire fills a line. Each line pays +5% money forever.",
		when = function(st) return (st.indexCount or 0) > 0 end },
	{ id = "ranks", target = "Rail.Column.RanksButton", title = "RANKS",
		body = "Every founder's company, ranked. The weekly board resets on Monday.",
		when = function(st) return (st.hq or 1) >= 2 and st.jr and st.jr.drove end },
	{ id = "daily", target = "Rail.Column.PhoneButton", title = "Daily reward",
		body = "Come back every day: each day pays more, day 7 the most. It's in your PHONE.",
		when = function(st) return st.dailyReady and (st.hq or 1) >= 2 and st.jr and st.jr.res end },
}

function J.tip(st)
	if st.carrying or st.seated then return nil end
	local seen = st.tips or {}
	for _, t in ipairs(J.TIPS) do
		if not seen[t.id] and t.when(st) then return t end
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
J.FLAGS = { "drove", "res", "launched", "genius", "seriesA" }

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
