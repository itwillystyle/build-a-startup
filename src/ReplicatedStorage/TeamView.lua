--[[ TeamView (14 Oct 2026, Manage Staff phase 3): what every part of the TEAM screen shows. Pure.

	TeamClient draws; this decides. The server owns every rule (StaffAction) and sends
	StaffData (one row per person: stats with level, cap and price) and StaffRooms (each
	pin room's free seats). Nothing here decides a price, a cap or a seat: it turns those
	into button states and words, so the screen's logic is tested offline (teamview.spec).
	Spec: docs/superpowers/specs/2026-10-13-manage-staff-design.md §2. ]]
local V = {}

V.ROOMS = {
	{ key = "hq", label = "Garage" },
	{ key = "lobby", label = "Lobby" },
	{ key = "eng", label = "Engineering" },
	{ key = "studio", label = "Design Studio" },
	{ key = "cafe", label = "Cafe" },
	{ key = "labs", label = "AI Labs" },
}
local LABEL = {}
for _, r in ipairs(V.ROOMS) do LABEL[r.key] = r.label end

V.TALENT = { "Regular", "Skilled", "Star", "Genius", "Unicorn" }
V.SENIORITY = { "Intern", "Junior", "Senior", "Lead" }   -- CoreConfig.TIER_TITLE

local function num(v)
	v = tonumber(v)
	if not v or v ~= v then return 0 end
	return v
end

local function pick(list, i)
	return list[math.clamp(math.floor(num(i)), 1, #list)]
end

function V.label(key) return LABEL[key] or (type(key) == "string" and key or "") end
function V.talent(t) return pick(V.TALENT, t) end
function V.seniority(t) return pick(V.SENIORITY, t) end

-- "rate": who earns most first; "talent": the rarest first. A new array; ties by id.
function V.sort(rows, by)
	local out = table.clone(rows or {})
	table.sort(out, function(a, b)
		local ra, rb, ta, tb = num(a.rate), num(b.rate), num(a.talent), num(b.talent)
		if by == "talent" then
			if ta ~= tb then return ta > tb end
			if ra ~= rb then return ra > rb end
		else
			if ra ~= rb then return ra > rb end
			if ta ~= tb then return ta > tb end
		end
		return num(a.id) < num(b.id)
	end)
	return out
end

-- one TRAIN button: "max" (at or over the cap), "poor" (cannot pay: dim, price shown), "ok"
function V.train(stat, cash)
	if type(stat) ~= "table" or num(stat.level) >= num(stat.cap) then return { state = "max", price = 0 } end
	local price = num(stat.price)
	return { state = num(cash) >= price and cash ~= nil and "ok" or "poor", price = price }
end

-- the MOVE TO chips: one per room the plot has, in StaffRooms' order
function V.chips(row, rooms)
	local fit = {}
	for _, k in ipairs(type(row.fits) == "table" and row.fits or {}) do fit[k] = true end
	local out = {}
	for _, r in ipairs(type(rooms) == "table" and rooms or {}) do
		local state = "ok"
		if row.pin == r.key then state = "here"
		elseif num(r.free) < 1 then state = "full" end
		table.insert(out, { key = r.key, label = V.label(r.key), free = num(r.free), best = fit[r.room] == true, state = state })
	end
	return out
end

-- the one line under a person: a pin the server could not honour, or the waiting line
function V.note(row)
	local pin = row.pin
	if type(pin) == "string" and pin ~= "" and row.room ~= pin then return "No free seat in " .. V.label(pin) end
	if row.room == nil then return "Waiting for a desk" end
	return nil
end

local WHY = {
	busy = "Busy right now. Try again in a moment.",
	["not yours"] = "That person is not on your team any more.",
	["at max"] = "At max for now. Grow your HQ to raise the limit.",
	["need cash"] = "Not enough cash yet.",
	["already there"] = "They are already pinned there.",
	["no free seat"] = "No free seat there.",
	["no plot"] = "Go to your lot first.",
}
function V.why(reason)
	return WHY[reason] or "That did not work. Try again."
end

function V.find(rows, id)
	for _, r in ipairs(type(rows) == "table" and rows or {}) do
		if r.id == id then return r end
	end
	return nil
end

-- phase 3b (the redesign, Luke's pick): the button's look. Only an affordable Skill is
-- loud (DESIGN.md: one loud thing), because it is the buy that makes money.
function V.look(statId, t)
	local st = type(t) == "table" and t.state or "max"
	if st == "max" then return "max" end
	if st == "poor" then return "dim" end
	return statId == "skill" and "go" or "paper"
end

-- the one line under the rooms row
function V.roomLine(row)
	local n = V.note(row)
	if n then return n end
	return (row.fit and "✓ " or "") .. V.label(row.room) .. (((row.pin or "") ~= "") and " · pinned" or "")
end

function V.glow(t)
	t = tonumber(t)
	return (t == 4 and "genius") or (t == 5 and "unicorn") or nil
end

-- the face tiles in view of the scrolling column, at most `cap` of them: only those show a
-- live character (ViewportFrames are costly on phones; spec §2 budget)
function V.visible(scrollY, viewH, tileH, gap, n, cap)
	if n < 1 then return 1, 0 end
	local step = tileH + gap
	local per = math.min(cap, math.ceil(num(viewH) / step) + 1)   -- +1: mid-scroll a sixth tile is mostly on screen (final review)
	local first = math.clamp(math.floor(num(scrollY) / step) + 1, 1, math.max(1, n - per + 1))
	return first, math.min(n, first + per - 1)
end

return V
