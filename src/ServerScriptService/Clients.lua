--[[ Clients (16 Oct 2026): the clients who walk up to your door. Pure.

	Spec: silicon-startup/docs/superpowers/specs/2026-10-16-client-loop-design.md.
	Luke's recording (16 Oct): the main thing a new player did was tap a button,
	and nobody in the world wanted anything from them. Now a client walks up and
	asks for an app, you code it by holding WRITE CODE at your laptop, carry it
	out and get paid, with a tip for speed. The first client is the tutorial and
	the wow (Tizzy: the first feed made the pet 5x bigger "to teach that wow").

	This module is every rule and no Instance: the queue, patience, job progress,
	coders, pay. `ClientsServer` owns the people, the remote and the cash, and
	calls `tick` / `handOver`. Tested by tests/offline/clients.spec.luau.

	A queue Q = { line, carrying, t, nextAt, served, lost, first, tutorial, seed, nextId }
	A client  = { id, kind = "first"|"normal"|"big", ask, need, done, patience?, left?, by? } ]]
local Clients = {}

-- starting values; tuned against the pacing targets (plan Task 10), never in the tests
Clients.TUNE = {
	FLOOR = 5,            -- a job pays at least this ... (17 Oct Task 10: was 8; the $60 lobby came 2 s after the hire)
	SECONDS = 3,          -- ... or this many seconds of your income, whichever is more (5 put the lobby at 0:44)
	TIP = 0.35,           -- speed tip, as a share of the pay, when you hand over with half your patience left
	WOW = 5,              -- the first client pays this many normal jobs
	BIG_MULT = 5,         -- a BIG client pays this many
	BIG_NEED = 2.5,       -- and is this many jobs of work (18 Oct: was 3)
	BIG_CHANCE = 0.12,    -- chance a new client is BIG, from the lobby on
	PLAYER_SPEED = 1,     -- work per second while you hold at the laptop
	CODER_SPEED = 0.4,    -- a tier-1 engineer's work per second
	OFF_ROLE = 1 / 1.5,   -- other roles code this much slower (RoomEconomy.FIT_MULT)
	FIRST_NEED = 1.5,     -- the first job: about 1.5 s of holding (17 Oct: 3 s felt slow; 18 Oct: was 2)
	NEED = 1.75,          -- a normal job (17 Oct, Luke: "coding feels a little too slow"; was 4, then 2.5;
	                      -- 18 Oct playtest 22-54-32: still slow, every job about 30% shorter)
	PATIENCE = 30,
	BIG_PATIENCE = 45,
	CAP = 3,              -- never more than 3 waiting (phones)
	HIRE_AFTER = 4,       -- clients served before the hire is taught anyway (17 Oct: an attentive
	                      -- player never had two waiting, so "Too busy!" came at 1:20)
	-- 17 Oct, Luke's pick 3A: tiers like the hires (Skilled from the lobby, Star from HQ stage 3)
	SKILLED_CHANCE = 0.30,
	STAR_CHANCE = 0.12,
	TIER_PAY = { regular = 1, skilled = 2, star = 4 },
	TIER_NEED = { regular = 1, skilled = 1.3, star = 1.7 },   -- 18 Oct: was 1.4 / 2
	-- 17 Oct, Luke's pick 2A: stars for speed (share of patience left) and the tip follows them
	STAR3 = 0.6,
	STAR2 = 1 / 3,
	SPAWN_GARAGE = 9,
	SPAWN_LOBBY = 4,      -- 17 Oct Task 10: was 7; the early lobby earned a quarter of the old taps
	SPAWN_MIN = 4,
}
local TUNE = Clients.TUNE

local FIRST_ASK = "A to-do app!"
local ASKS = { "A chat app!", "A game!", "A shop site!", "A photo app!", "A map app!", "A music app!", "A weather app!", "A pet app!" }

-- a seeded generator kept in the queue, so the same seed gives the same clients
local function roll(Q)
	Q.seed = (Q.seed * 1103515245 + 12345) % 2147483648
	return Q.seed / 2147483648
end

function Clients.cap(level)
	return math.min(TUNE.CAP, (level or 1) <= 1 and 2 or 3)
end

function Clients.spawnEvery(level, stage)
	if (level or 1) <= 1 then return TUNE.SPAWN_GARAGE end
	return math.max(TUNE.SPAWN_MIN, TUNE.SPAWN_LOBBY - ((stage or 1) - 1))
end

function Clients.coderSpeed(tier, role)
	local s = TUNE.CODER_SPEED * (1 + 0.25 * ((tier or 1) - 1))
	if role ~= "engineer" then s *= TUNE.OFF_ROLE end
	return s
end

-- a new client of `kind` (and `tier` for a normal one); picks its ask from the queue's generator
function Clients.make(Q, kind, tier)
	local c = { id = Q.nextId, kind = kind, done = 0 }
	Q.nextId += 1
	if kind == "first" then
		c.ask, c.need = FIRST_ASK, TUNE.FIRST_NEED
	elseif kind == "big" then
		c.ask, c.need, c.patience = "BIG", TUNE.NEED * TUNE.BIG_NEED, TUNE.BIG_PATIENCE
	else
		c.tier = tier or "regular"
		c.ask, c.need, c.patience = ASKS[1 + math.floor(roll(Q) * #ASKS)], TUNE.NEED * TUNE.TIER_NEED[c.tier], TUNE.PATIENCE
	end
	c.left = c.patience
	return c
end

function Clients.new(opts)
	opts = opts or {}
	local Q = { line = {}, carrying = nil, t = 0, nextAt = 0, served = 0, lost = 0,
		first = opts.first == true, tutorial = opts.first == true, seed = (opts.seed or 1) % 2147483648, nextId = 1 }
	if Q.first then table.insert(Q.line, Clients.make(Q, "first")) end
	return Q
end

-- stars for a hand-over: 3 fast, 2 ok, 1 slow (the share of patience left); the
-- tutorial client and anyone without a clock always 3
local function starsFor(share)
	if share >= TUNE.STAR3 then return 3 end
	if share >= TUNE.STAR2 then return 2 end
	return 1
end
function Clients.stars(client)
	if client.kind == "first" or not client.patience then return 3 end
	return starsFor((client.left or 0) / client.patience)
end

-- pay for a finished job; `patienceLeft` is the share (0-1) of patience left at the hand-over.
-- The speed tip follows the stars: full at 3, half at 2, none at 1; yours only.
function Clients.pay(client, rate, patienceLeft)
	local base = math.max(TUNE.FLOOR, (rate or 0) * TUNE.SECONDS)
	local mult = client.kind == "first" and TUNE.WOW or client.kind == "big" and TUNE.BIG_MULT
		or TUNE.TIER_PAY[client.tier or "regular"] or 1
	local pay = math.floor(base * mult)
	local tip = 0
	if client.by == "you" and client.kind ~= "first" then
		local st = starsFor(patienceLeft or 0)
		tip = st == 3 and math.floor(base * TUNE.TIP) or st == 2 and math.floor(base * TUNE.TIP / 2) or 0
	end
	return pay, tip
end

local function remove(Q, c)
	for i, x in ipairs(Q.line) do
		if x == c then table.remove(Q.line, i) return end
	end
end

-- where in the line client `c` stands (1 = the front). A long tick can serve or lose a client in
-- the tick it arrives, so one already gone gets the back of the line, never 0 (23 Oct: spot 0 in
-- the lobby ended the client loop)
function Clients.spotOf(Q, c)
	return table.find(Q.line, c) or math.max(1, #Q.line)
end

--[[ One step of `dt` seconds. ctx = { level, stage, rate, holding, atLaptop, coders = {speed}, speedMult? }
	(speedMult: a Cold Brew codes x3, as it tapped x3).
	Returns a list of events { kind = "arrive"|"shipped"|"served"|"lost", client, pay?, tip? }. ]]
function Clients.tick(Q, dt, ctx)
	local events = {}
	Q.t += dt

	-- someone new walks up (not during the tutorial: the first client is alone)
	local newcomer
	if not Q.tutorial and #Q.line < Clients.cap(ctx.level) and Q.t >= Q.nextAt then
		local kind = ((ctx.level or 1) >= 2 and roll(Q) < TUNE.BIG_CHANCE) and "big" or "normal"
		local tier
		if kind == "normal" then
			local r = roll(Q)
			if (ctx.stage or 1) >= 3 and r < TUNE.STAR_CHANCE then tier = "star"
			elseif (ctx.level or 1) >= 2 and r < TUNE.STAR_CHANCE + TUNE.SKILLED_CHANCE then tier = "skilled"
			else tier = "regular" end
		end
		local c = Clients.make(Q, kind, tier)
		table.insert(Q.line, c)
		newcomer = c
		Q.nextAt = Q.t + Clients.spawnEvery(ctx.level, ctx.stage)
		table.insert(events, { kind = "arrive", client = c })
	end

	-- the jobs nobody has finished, front of the line first
	local open = {}
	for _, c in ipairs(Q.line) do
		if c ~= Q.carrying and c.done < c.need then table.insert(open, c) end
	end

	-- you: the front open job, while you hold at the laptop and carry nothing
	local mine = (ctx.holding and ctx.atLaptop and not Q.carrying) and open[1] or nil
	if mine then
		mine.by = "you"
		mine.yours = true   -- 18 Oct (option A): you started it; a coder taking `by` on a let-go does not undo that
		mine.done = math.min(mine.need, mine.done + TUNE.PLAYER_SPEED * (ctx.speedMult or 1) * dt)
		if mine.done >= mine.need then
			Q.carrying = mine
			table.insert(events, { kind = "shipped", client = mine })
		end
	end

	-- coders: one job each, front first, never yours, never BIG, never the tutorial's
	local ci = 1
	for _, c in ipairs(open) do
		local speed = ctx.coders and ctx.coders[ci]
		if not speed then break end
		if c ~= mine and c.kind == "normal" then
			c.by = "coder"
			c.done += speed * dt
			ci += 1
			if c.done >= c.need then
				remove(Q, c)
				Q.served += 1
				local pay, tip = Clients.pay(c, ctx.rate, 1)
				table.insert(events, { kind = "served", client = c, pay = pay, tip = tip })
			end
		end
	end

	-- patience: everyone waiting, except the job in your hands this tick, the app you carry and who just arrived
	for i = #Q.line, 1, -1 do
		local c = Q.line[i]
		if c.left and c ~= mine and c ~= Q.carrying and c ~= newcomer then
			c.left -= dt
			if c.left <= 0 then
				table.remove(Q.line, i)
				Q.lost += 1
				table.insert(events, { kind = "lost", client = c })
			end
		end
	end
	return events
end

--[[ The reception counter (Luke's pick B, 17 Oct). From the lobby on, clients do not
	queue at the old garage door: the lobby reaches 49 studs past it, so they stood in
	its walls and by its sofa (his playtest). They walk in through the entrance to a
	counter on the empty half of the lobby's back wall (the TV and the photo hang on the
	other half), the side nearest the hall desk, and queue from it toward the door.
	`room` is TowerPlan.room(0, 1), plot-local (x right, +z toward the road).
	Returns { counter = {x, z, w, d}, spots = {{x, z}...}, path = {{x, z}...} }. ]]
function Clients.counterLine(room)
	-- 17 Oct, Luke's pick 1A: the desk takes the middle, facing the door; you serve from
	-- behind it (the hall side), the line runs straight back to the entrance on a rug
	local cx = room.cx or (room.x0 + room.x1) / 2
	local counter = { x = cx, z = room.z0 + 8.5, w = 10, d = 2.2 }
	local spots = {}
	for i = 1, TUNE.CAP do
		table.insert(spots, { x = cx, z = counter.z + 3.4 + 4.3 * (i - 1) })
	end
	local path = { { x = cx, z = room.z1 + 14 }, { x = cx, z = room.z1 - 4 } }
	return { counter = counter, spots = spots, path = path, serve = { x = cx, z = counter.z - 2.6 } }
end

--[[ The goal line (spec: "Teaching the rest when it's needed"; Tizzy's contextual
	tutorial). One goal, the moment it is needed; nil = let Journey decide.
	st = { served, carrying, midJob, waiting, staff, cap, level, cash, upgradeCost, freeSeat,
	recruitTaught, tutorial }. Returns { key, title, target }; target is a place
	name the server turns into a position (laptop, client, hirePad, hqPad, sidewalk).

	18 Oct (option A, Luke's pick): the job in your hands comes first. While you carry an
	app, or have put code into a job (midJob, Clients.started), the card, the marker and
	the ground line all name that job, and "Build level 4" waits until you GIVE (playtest
	22-54-32, 3:44 and 4:04: the card and the line said build while you carried an app).
	Only mid-job: in the lobby a client arrives every 4 s, so "a job is waiting" would
	hide the build goals forever. ]]
function Clients.goal(st)
	if st.tutorial and (st.served or 0) == 0 then
		if st.carrying then return { key = "deliver", title = "Take it to your client", target = "client" } end
		return { key = "code", title = "Code the to-do app", target = "laptop" }
	end
	if st.carrying then return { key = "give", title = "Give it to your client", target = "client" } end
	if st.midJob then return { key = "finish", title = "Finish the app", target = "laptop" } end
	local busy = (st.waiting or 0) >= 2
	local staff = st.staff or 0
	if staff == 0 and (busy or (st.served or 0) >= TUNE.HIRE_AFTER) then
		return { key = "hire", title = "Too busy! Hire a coder", target = "hirePad" }
	end
	-- the HQ only builds with someone hired (wafersBuild: "Hire someone first")
	if staff >= 1 and (st.level or 1) <= 1 and ((staff >= (st.cap or 1) and busy) or (st.cash or 0) >= (st.upgradeCost or math.huge)) then
		return { key = "upgrade", title = "Upgrade your HQ", target = "hqPad" }
	end
	-- not gated on `busy`: it flipped with Journey's goal every few seconds as the line went 1-2-1
	if (st.level or 1) >= 2 and st.freeSeat and not st.recruitTaught then
		return { key = "recruit", title = "Recruit on the street", target = "sidewalk" }
	end
	return nil
end

--[[ 18 Oct (option A): the job you have started coding and not finished, or nil. "Started"
	means you put code into it (`yours`, set in `tick`), not who holds it this tick: let go
	for a moment with a coder in the room and the coder takes `by` for a tick, which would
	flip the goal card away from "Finish the app" and back. The app you carry is not
	"started" (it is the "give" goal). ]]
function Clients.started(Q)
	for _, c in ipairs(Q.line) do
		if c ~= Q.carrying and c.yours and c.done > 0 and c.done < c.need then return c end
	end
	return nil
end

-- when neither the client loop nor Journey has a goal: serve whoever is waiting
function Clients.fallback(st)
	if (st.waiting or 0) > 0 then return { key = "serve", title = "Serve your clients", target = "client" } end
	return nil
end

-- your own apps (the product bar, LAUNCH!) start at the lobby: in the garage the
-- clients are the whole game (Luke's playtest, 17 Oct: LAUNCH was never explained)
function Clients.productsOpen(level)
	return (level or 1) >= 2
end

--[[ the WRITE CODE hold, one remote event at a time: returns the new hold and the time of
	the last accepted press. A release always lets go (17 Oct review: a phone tap is 50-100 ms,
	and the old 0.1 s debounce dropped the release, so the server held forever); only a press
	inside 0.1 s of the last one is ignored, so a toggle spammer gains nothing. ]]
function Clients.holdEvent(on, hold, lastPress, now)
	if on ~= true then return false, lastPress end
	if now - (lastPress or -math.huge) < 0.1 then return hold, lastPress end
	return true, now
end

-- hand the carried app to its client; nil when you carry nothing
function Clients.handOver(Q, ctx)
	local c = Q.carrying
	if not c then return nil end
	remove(Q, c)
	Q.carrying = nil
	Q.served += 1
	local pay, tip = Clients.pay(c, ctx and ctx.rate, c.patience and (c.left / c.patience) or 1)
	if c.kind == "first" then
		Q.tutorial = false
		Q.nextAt = Q.t     -- the next client is already on the way
	end
	return { kind = "served", client = c, pay = pay, tip = tip }
end

return Clients
