--[[
	RoomEconomy (v2.6.0) -- ModuleScript in ServerScriptService.

	HIS DESIGN, 18 Sep: "each building should have its own income-making
	resources that scale properly... desks for office... round tables in the
	cafeteria with more space as better than the office... your live income
	should show that."

	The runaway-money cause it fixes: seats came from desks, desks worked on
	any floor, so capacity was bounded only by floor area (dozens of desks)
	and every new seat paid for itself in minutes. Now:

	  1. STATIONS belong to a ROOM. A desk only seats someone inside an Open
	     Office (or the HQ). A round table only works in the Cafeteria. A work
	     table only in the Design Studio. Anywhere else, placement is refused
	     with a sentence that says where it goes.
	  2. Each room has a SEAT CAP that grows with its level. Seats are bought
	     by upgrading rooms, and room upgrades are priced in seconds of income,
	     so seats arrive on a steady ladder instead of compounding.
	  3. Bigger stations are more EFFICIENT per seat (his "more space is
	     better"): desk 1.0, corner desk 1.1, work table 1.15, round table 1.25.
	  4. ROLE FIT: someone seated in the room that matches their job earns
	     x1.5 (engineers/researchers in offices, designers in the studio, sales
	     and recruiters in the cafeteria). Building the other rooms now pays.
	  5. WAGES: every person costs a wage by seniority, whether seated or not,
	     and NOT by talent -- so a rare hire is pure upside and an empty seat
	     count is a real cost. People waiting for a seat earn nothing.
	  6. The live income line breaks down by building.

	Pure functions and tables only; SiliconCore owns state. It sits in its own
	module because SiliconCore is at ~192 of Luau's 200 top-level locals.
]]

local Econ = {}

-- station -> where it works, how many it seats, and how productive a seat is
Econ.STATIONS = {
	desk       = { room = "office", hq = true, seats = 1, eff = 1.00 },
	deskCorner = { room = "office", hq = true, seats = 1, eff = 1.10 },
	tableCross = { room = "studio",            seats = 2, eff = 1.15 },
	tableRound = { room = "cafe",              seats = 4, eff = 1.25 },
}

-- placed-station seats a room of this level can hold (built-in office seats
-- are extra: SiliconCore's OFFICE_DESKS give 2 per office level)
function Econ.roomCap(roomId, level)
	level = level or 1
	if roomId == "hq" then return 1 + level end           -- the HQ floor: 2 at the garage, 6 at campus
	if roomId == "office" then return 2 + 2 * level end   -- 4 .. 12 placed desks
	if roomId == "studio" then return 2 * level end        -- one work table per level
	if roomId == "cafe" then return 4 * level end          -- one round table per level
	return 0
end

Econ.ROOM_NAME = { hq = "HQ", office = "OFFICE", studio = "STUDIO", cafe = "CAFETERIA", servers = "SERVERS" }
Econ.STATION_HINT = {
	office = "place a DESK in your office",
	studio = "place a WORK TABLE in the studio",
	cafe = "place a ROUND TABLE in the cafeteria",
	hq = "place a DESK in your HQ",
}

-- which rooms a role belongs in
Econ.FIT = {
	engineer = { office = true, hq = true },
	research = { office = true, labs = true },   -- v4.6: AI LABS floors in the Wafers
	designer = { studio = true },
	sales = { cafe = true },
	recruiter = { cafe = true },
}
Econ.FIT_MULT = 1.5

-- wage per second by seniority (Intern, Junior, Senior, Lead), times the HQ multiplier.
-- About a quarter of a Regular's gross, so a team always nets, and talent is upside.
Econ.WAGE = { 0.5, 1.0, 1.8, 3.0 }
function Econ.wageOf(tier) return Econ.WAGE[tier or 1] or Econ.WAGE[1] end

-- which room a floor point is in: a built slot, else the HQ floor, else nil
function Econ.roomAt(plot, x, z, hqW, hqD, slotW, slotD)
	local p = Vector3.new(x, 0, z)
	for i, slot in ipairs(plot.slots or {}) do
		if slot.built then
			local l = slot.cf:PointToObjectSpace(p)
			if math.abs(l.X) <= slotW / 2 and math.abs(l.Z) <= slotD / 2 then return slot.built, i end
		end
	end
	local l = plot.pivot:PointToObjectSpace(p)
	if math.abs(l.X) <= hqW / 2 and math.abs(l.Z) <= hqD / 2 then return "hq", nil end
	return nil, nil
end

-- seats used by placed stations in one room instance
function Econ.seatsUsed(placed, roomId, slotIdx)
	local n = 0
	for _, e in ipairs(placed) do
		local st = Econ.STATIONS[e.key]
		if st and e.room == roomId and e.slot == slotIdx then n += st.seats end
	end
	return n
end

-- the seat CFrames a placed station provides (root height 3.4, facing the station)
function Econ.seatsFor(e)
	local st = Econ.STATIONS[e.key]
	if not st then return {} end
	local c = CFrame.new(e.x, 3.4, e.z) * CFrame.Angles(0, math.rad(e.yaw or 0), 0)
	if st.seats == 1 then
		-- Kenney desks front +Z at yaw 0; the seat is 2.6 in front, looking back at the desk
		return { c * CFrame.new(0.3, 0, 2.6) }
	end
	local out = {}
	local centre = c.Position
	local ring = (st.seats == 4) and { { 0, 2.6 }, { 0, -2.6 }, { 2.4, 0 }, { -2.4, 0 } }
		or { { 0, 2.3 }, { 0, -2.3 } }
	for _, o in ipairs(ring) do
		local pos = (c * CFrame.new(o[1], 0, o[2])).Position
		table.insert(out, CFrame.lookAt(pos, Vector3.new(centre.X, pos.Y, centre.Z)))
	end
	return out
end

-- the first room instance that still has station space, for the guide
function Econ.roomWithSpace(plot, placed, hqLevel)
	for i, slot in ipairs(plot.slots or {}) do
		if slot.built and Econ.roomCap(slot.built, slot.level) > Econ.seatsUsed(placed, slot.built, i) then
			return slot.built, i
		end
	end
	if Econ.roomCap("hq", hqLevel) > Econ.seatsUsed(placed, "hq", nil) then return "hq", nil end
	return nil, nil
end

-- "OFFICE +$40|CAFETERIA +$25|WAGES -$12" for the HUD (money formatted client-side)
function Econ.breakdown(perRoom, wages)
	local parts = {}
	for room, v in pairs(perRoom) do
		if v > 0 then table.insert(parts, { Econ.ROOM_NAME[room] or room, v }) end
	end
	table.sort(parts, function(a, b) return a[2] > b[2] end)
	local s = {}
	for _, p in ipairs(parts) do table.insert(s, p[1] .. "=" .. math.floor(p[2])) end
	if wages > 0 then table.insert(s, "WAGES=-" .. math.floor(wages)) end
	return table.concat(s, "|")
end

--[[ v2.6.2 MARKET FIT (his step 3). Every market is worth the SAME total at
base (payday + the area under its boost curve = ~195 seconds of income), so
no card is the right answer by size. They differ in SHAPE -- cash now, a
steady boost, or a long tail -- and in which people they want. Your team
decides which card is best for YOU: each matching person SEATED adds +20%
(cap +100%), and FINTECH / AI also count every compute point from servers.

  total = PAY + H * DUR * area(curve)   area: linear 0.5, flat 1, tail 2/3

  v2.6.4: every market totals ~80-95 s of income (was ~195). A launch is a
  bonus on top of the company, never the company: at minute 4 the old table
  paid $800 to a player holding $150, and building stopped mattering.
]]
Econ.MARKET = {
	games    = { roles = { designer = true },  label = "designers",   shape = "BIG PAYDAY",   pay = 40, h = 0.5,  dur = 150, curve = "linear" },
	delivery = { roles = { engineer = true },  label = "engineers",   shape = "FAST CASH",    pay = 30, h = 0.5,  dur = 210, curve = "linear" },
	social   = { roles = { sales = true },     label = "sales",       shape = "BALANCED",     pay = 15, h = 0.5,  dur = 300, curve = "linear" },
	health   = { roles = { recruiter = true }, label = "recruiters",  shape = "STEADY BOOST", pay = 15, h = 0.25, dur = 300, curve = "flat" },
	fintech  = { roles = { engineer = true },  label = "engineers",   shape = "STEADY BOOST", pay = 5,  h = 0.3,  dur = 300, curve = "flat", servers = true },
	ai       = { roles = { research = true },  label = "researchers", shape = "LONG TAIL",    pay = 5,  h = 0.25, dur = 540, curve = "tail", servers = true },
}
-- v2.6.4: a wing costs at least this many seconds of income (same rule as
-- furniture and wing upgrades), so the third-best building is never a
-- minute-five purchase once the company earns real money
Econ.WING_SECONDS = { office = 30, servers = 60, studio = 90, cafe = 120 }
Econ.FIT_STEP = 0.2
Econ.FIT_MAX = 5

-- how well this team fits a market: matching SEATED people (+ compute for
-- server markets), the multiplier, and the sentence the card shows
function Econ.marketFit(marketId, rigs, compute)
	local m = Econ.MARKET[marketId]
	if not m then return 0, 1, "" end
	local n = 0
	for _, r in ipairs(rigs or {}) do
		local role = r.rig and r.rig:GetAttribute("Role")
		if r.seated and role and m.roles[role] then n += 1 end
	end
	local servers = m.servers and (compute or 0) or 0
	local count = math.min(Econ.FIT_MAX, n + servers)
	local mult = 1 + Econ.FIT_STEP * count
	local text
	if n + servers == 0 then
		text = ("Needs %s"):format(m.label:upper())
	else
		text = ("Your %s: %d%s  ·  +%d%%"):format(m.label, n,
			servers > 0 and (" + %d server"):format(servers) or "", math.floor((mult - 1) * 100 + 0.5))
	end
	return count, mult, text
end

-- the boost height at fraction-remaining f (1 at launch, 0 at the end)
function Econ.curveAt(curve, f)
	if curve == "flat" then return 1 end
	if curve == "tail" then return math.sqrt(f) end
	return f
end

-- v2.6.3 AFK = OFFLINE. Standing still for AFK_SECONDS earns the offline rate
-- (the same 25% a logged-off player gets) until you move. Idling in a server
-- should never out-earn playing, and it is not a penalty: nothing is taken.
Econ.AFK_SECONDS = 300
Econ.AFK_RATE = 0.25

--[[ v2.7.0 THE CUT (Phase 1). Measured in sim/: the v2.6.4 game ran out of
content at ~25 min at every player speed, asked for 31-41 desk placements an
hour, took 36-38% of its money from launches, and priced late purchases in
seconds of income so the longest wait was always exactly 6 minutes. V3:
  - FIXED price ladders. HQ multiplies income, never prices: you outgrow them.
  - Each HQ unlocks the next batch: staff cap, room slots, max room level.
  - Rooms come furnished (seats per level). Furniture is decoration.
  - One LAUNCH button: a payday of LAUNCH_PAY seconds. No market picker.
  - WRITE CODE keeps filling the product bar forever (the active verb).
  - Off: wages, rivals/market share, poach offers, station seats.
  - Spin-off at $4M keeps your rare hires (Star and above).
Sim result at 20 s/purchase: run 1 to spin-off 25.5 min, longest wait 1.6 min
(worst 2.2), launches 20% of money. See sim/FINDINGS-session1.md. ]]
Econ.V3 = true
Econ.HIRE_GROWTH = 1.35
Econ.WING_GROWTH = 1.6
Econ.LEVEL_FIRST = 0.6
Econ.LEVEL_GROWTH = 2.0
Econ.HQ_COST = { 0, 3750, 37500, 225000, 1500000 }
Econ.CAP_BY_HQ = { 8, 14, 20, 26, 30 }
Econ.SLOTS_BY_HQ = { 2, 3, 4, 5, 6 }
Econ.LV_BY_HQ = { 3, 5, 7, 9, 10 }
Econ.MAX_LEVEL = 10
Econ.LAUNCH_PAY = 30
Econ.CODE_WORK = 0.15          -- product-bar work per click, x the team's summed seniority rate
Econ.SPINOFF_BASE = 4000000
Econ.KEEP_TALENT = 3           -- Star and above follow you to the next startup
Econ.SAVE_WINDOW = 120         -- the guide points at the HQ once it is this many seconds away
Econ.OFFLINE_CAP = 600         -- offline earnings never exceed 10 minutes of full income
Econ.ROOM_ORDER = { "office", "studio", "cafe", "servers" }
Econ.SEATS = { office = { 2, 10 }, studio = { 2, 6 }, cafe = { 4, 12 }, servers = { 0, 0 } }

function Econ.roomSeats(roomId, level)
	local s = Econ.SEATS[roomId]
	if not s then return 0 end
	return math.min(s[2], s[1] * (level or 1))
end

-- the garage bench + every furnished seat in every room
function Econ.seatCount(plot)
	local n = 1
	for _, slot in ipairs(plot.slots or {}) do
		if slot.built then n += Econ.roomSeats(slot.built, slot.level) end
	end
	return n
end

function Econ.capacity(plot)
	local hq = plot.hq and plot.hq.level or 1
	return math.min(Econ.CAP_BY_HQ[hq] or 30, Econ.seatCount(plot))
end

function Econ.slotsBuilt(plot)
	local n = 0
	for _, slot in ipairs(plot.slots or {}) do if slot.built then n += 1 end end
	return n
end

-- a room level still does something: office seats stop at 10
function Econ.levelUseful(slot)
	if slot.built == "office" then return Econ.roomSeats("office", (slot.level or 1) + 1) > Econ.roomSeats("office", slot.level or 1) end
	return true
end

-- the next room TYPE you do not own yet (the old guide built six offices)
function Econ.nextRoom(plot)
	local have = {}
	for _, slot in ipairs(plot.slots or {}) do if slot.built then have[slot.built] = (have[slot.built] or 0) + 1 end end
	for _, id in ipairs(Econ.ROOM_ORDER) do if not have[id] then return id end end
	local best, n = Econ.ROOM_ORDER[1], math.huge
	for _, id in ipairs(Econ.ROOM_ORDER) do
		if id ~= "servers" and (have[id] or 0) < n then best, n = id, have[id] or 0 end
	end
	return best
end

-- where seat k of a studio or cafe is (room-local x, z) and what it faces
local STUDIO_Z = { 2.4, -3.6, -9.0 }
local STUDIO_SEAT_X = 3.7
local CAFE_T = { { -7, 0.5 }, { 7, 0.5 }, { -7, 7 } }
local RING = { { 0, 2.6 }, { 0, -2.6 }, { 2.4, 0 }, { -2.4, 0 } }
function Econ.seatSpot(roomId, k)
	if roomId == "studio" then
		local z = STUDIO_Z[math.ceil(k / 2)]
		if not z then return nil end
		local side = (k % 2 == 1) and -1 or 1
		-- v3.0.3: 3.7, not 5.4 -- at 5.4 a seated designer typed on air 2.9 studs
		-- from the table's edge (measured on screen); 3.7 leaves 0.5 to the edge
		return side * STUDIO_SEAT_X, z + 0.4, 0, z + 0.4
	elseif roomId == "cafe" then
		local t = CAFE_T[math.ceil(k / 4)]
		if not t then return nil end
		local o = RING[((k - 1) % 4) + 1]
		return t[1] + o[1], t[2] + o[2], t[1], t[2]
	end
	return nil
end

-- the tables that go with those seats; idempotent, counted on the room model
-- (a rebuilt room is a new model, so a spin-off can never inherit a stale count)
function Econ.furnish(FK, slot)
	if not FK or not slot.model or not slot.built or not FK.onFloor then return end
	local id = slot.built
	if id ~= "studio" and id ~= "cafe" then return end
	local want = math.ceil(Econ.roomSeats(id, slot.level) / (id == "studio" and 2 or 4))
	local have = slot.model:GetAttribute("Tables") or (id == "studio" and 1 or 0)   -- dressRoom gives the studio its first table
	for t = have + 1, want do
		if id == "studio" then
			local z = STUDIO_Z[t]
			if z then
				pcall(FK.onFloor, "tableCross", slot.cf, 0, z, 1.0, slot.model)
				pcall(FK.onFloor, "chairModernCushion", slot.cf, -STUDIO_SEAT_X, z + 0.4, 1.0, slot.model, { yaw = 90 })
				pcall(FK.onFloor, "chairModernCushion", slot.cf, STUDIO_SEAT_X, z + 0.4, 1.0, slot.model, { yaw = -90 })
			end
		else
			local c = CAFE_T[t]
			if c then
				pcall(FK.onFloor, "tableRound", slot.cf, c[1], c[2], 1.0, slot.model, { canCollide = true })
				for j, o in ipairs(RING) do
					local yaw = ({ 180, 0, -90, 90 })[j]
					pcall(FK.onFloor, "chairModernCushion", slot.cf, c[1] + o[1], c[2] + o[2], 1.0, slot.model, { yaw = yaw })
				end
			end
		end
	end
	slot.model:SetAttribute("Tables", math.max(have, want))
end


--[[
	v3.0 TALENT ROW (PLAN-v5-tizzy Phase B): hiring is a recruit run.
	Simulated in sim/recruit_sim.py before any Lua: HQ 2/3/4/5 at
	4.1/7.1/10.9/19.5 min at 20 s per purchase (today 3.8/7.1/11.4/20.4),
	spin-off 26 min; slow walkers + double losses still reach HQ 5 at 21.8.
	east = studs east of your plot along your side's sidewalk; floor = the
	talent they are guaranteed (TALENT index, colours come from TALENT);
	fee = x the hire ladder, paid at your door; restock = seconds after one is
	taken or lost; chase = a headhunter follows you home.
]]
Econ.RECRUIT = true
-- v3.0.1: hq = the HQ level that puts this tier on the sidewalk, minFee = a fee
-- floor. Live bot 24 Sep: a STAR cost ~$430 at minute 1.5 because fees scale off
-- the tiny early hire ladder. Rarer hires are now an HQ unlock (sim: on target).
Econ.TIERS = {
	{ id = "walkin",  name = "WALK-IN", east = 20,  floor = 1, fee = 1,  restock = 2,   chase = false, pillar = 0,  hq = 1, minFee = 0 },
	{ id = "skilled", name = "SKILLED", east = 140, floor = 2, fee = 3,  restock = 45,  chase = true,  pillar = 10, hq = 1, minFee = 150,   hhSpeed = 11, hhDash = 17 },
	{ id = "star",    name = "STAR",    east = 280, floor = 3, fee = 8,  restock = 120, chase = true,  pillar = 16, hq = 2, minFee = 2500,  hhSpeed = 12, hhDash = 19 },
	{ id = "genius",  name = "GENIUS",  east = 440, floor = 4, fee = 20, restock = 300, chase = true,  pillar = 24, hq = 3, minFee = 25000, hhSpeed = 13, hhDash = 21 },
}
Econ.KEEP_MAX = 3              -- the spin-off keeps your 3 best (recruiting makes Star+ common: sim kept ~12)
Econ.OFFER_BASE = 14           -- offer timer: base seconds ...
Econ.OFFER_PER_STUD = 0.11     -- ... + this per stud from the candidate to your plot (~1.7x a steady walk)
-- v4.3: THE CHASE MOVED TO ChaseRules.lua (a tension band, lunges, lead pursuit, BOOST).
-- The HH_* values below are the v4.2 hunter; only tools/chase_sim uses their shape as a baseline.
Econ.HH_START = 30             -- the headhunter starts this many studs east of where you recruited
Econ.HH_SPEED = 13             -- studs/s (you walk 16)
Econ.HH_DASH = 21              -- a burst ...
Econ.HH_DASH_EVERY = 5         -- ... every 5 s ...
Econ.HH_DASH_TIME = 1.2        -- ... for 1.2 s: averages ~14.9, so only a player who stops gets caught
Econ.HH_CATCH = 4.5
-- v3.0.2 (his playtest: "the headhunter seems faster than my sprint"). He was
-- right: a 21 dash beat his 16 walk and nothing warned him. Now the chase is
-- losable but readable:
--   * speed per tier (TIERS hhSpeed/hhDash): the bigger prize has the faster hunter
--   * HH_WINDUP: the hunter stops, crouches and flashes red for 0.4 s before each dash
--   * CARRY_SPEED: you ride a scooter while carrying, faster with each HQ level
--     (STAR unlocks at HQ 2 = 17 vs a 19 dash; GENIUS at HQ 3 = 18 vs 21)
Econ.HH_WINDUP = 0.4

--[[ v3.1 TALENT INDEX REWARDS. Both reviews (25 Sep): an Index that pays
nothing gives nothing to chase. Every completed LINE pays +5% money forever:
a row is one role at all 5 talents, a column is one talent across all 5
roles. The Regular column comes early (a taste), the Unicorn column is the
long chase. Derived from the saved index at recompute, never stored. ]]
Econ.INDEX_ROLES = { "engineer", "designer", "sales", "recruiter", "research" }
Econ.INDEX_TALENTS = 5
Econ.INDEX_STEP = 0.05
function Econ.indexLines(index)
	index = index or {}
	local lines = 0
	for _, role in ipairs(Econ.INDEX_ROLES) do
		local full = true
		for t = 1, Econ.INDEX_TALENTS do if not index[role .. ":" .. t] then full = false break end end
		if full then lines += 1 end
	end
	for t = 1, Econ.INDEX_TALENTS do
		local full = true
		for _, role in ipairs(Econ.INDEX_ROLES) do if not index[role .. ":" .. t] then full = false break end end
		if full then lines += 1 end
	end
	return lines
end
function Econ.indexMult(index) return 1 + Econ.INDEX_STEP * Econ.indexLines(index) end
Econ.CARRY_SPEED = { 16, 17, 18, 19, 20 }   -- by HQ level; the default walk is 16

return Econ
