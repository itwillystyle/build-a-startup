-- seating.spec.luau: pins are honoured first; with no pins, seating is exactly what it was (14 Oct 2026)
local Seat = require("../../src/ReplicatedStorage/Seating")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

-- Lune has no Roblox Random: Park-Miller, as savefuzz.spec
local R = {}; R.__index = R
local function rng(seed) return setmetatable({ s = (seed % 2147483646) + 1 }, R) end
function R:int(a, b) self.s = (self.s * 16807) % 2147483647; return a + math.floor(self.s / 2147483647 * (b - a + 1)) end

local ROLES = { "engineer", "designer", "sales", "research", "recruiter" }
local KEYS = { "hq", "lobby", "eng", "studio", "cafe", "labs", "servers" }
local ROOM_OF = { hq = "hq", lobby = "lobby", eng = "office", studio = "studio", cafe = "cafe", labs = "lab", servers = "servers" }
local FIT = { engineer = { office = true, lobby = true }, designer = { studio = true }, sales = { cafe = true },
	research = { lab = true, office = true }, recruiter = { cafe = true } }
local function fits(role, room) return (FIT[role] or {})[room] == true end

-- assignDesks before phase 2, verbatim in shape: list order, fit first, then any
local function oldAssign(people, homes)
	local used, seat = {}, {}
	for i, p in ipairs(people) do
		local pick
		for k, h in ipairs(homes) do if not used[k] and fits(p.role, h.room) then pick = k break end end
		if not pick then for k in ipairs(homes) do if not used[k] then pick = k break end end end
		if pick then used[pick] = true; seat[i] = pick end
	end
	return seat
end

local function world(g, pinShare)
	local homes, people = {}, {}
	for _ = 1, g:int(0, 30) do local key = KEYS[g:int(1, #KEYS)]; table.insert(homes, { room = ROOM_OF[key], key = key }) end
	for _ = 1, g:int(0, 30) do
		local pin = (g:int(1, 100) <= pinShare) and KEYS[g:int(1, 6)] or ""   -- KEYS[1..6]: the valid pins
		table.insert(people, { role = ROLES[g:int(1, #ROLES)], pin = pin })
	end
	return people, homes
end

test("no pins: exactly the old seating, over 3,000 random teams", function()
	local g = rng(1014)
	for case = 1, 3000 do
		local people, homes = world(g, 0)
		local a, b = Seat.assign(people, homes, fits), oldAssign(people, homes)
		for i = 1, #people do assert(a[i] == b[i], ("case %d person %d: %s vs old %s"):format(case, i, tostring(a[i]), tostring(b[i]))) end
	end
end)

test("with pins: no seat twice; as many seated as fit; pins filled up to their room's seats", function()
	local g = rng(2026)
	for case = 1, 3000 do
		local people, homes = world(g, 40)
		local seat, ok = Seat.assign(people, homes, fits)
		local used, seated = {}, 0
		for i = 1, #people do
			if seat[i] then
				assert(not used[seat[i]], ("case %d: seat %d used twice"):format(case, seat[i]))
				used[seat[i]] = true; seated += 1
				if ok[i] then assert(homes[seat[i]].key == people[i].pin, ("case %d: pinnedOk but in the wrong room"):format(case)) end
			end
		end
		assert(seated == math.min(#people, #homes), ("case %d: %d seated of %d people, %d seats"):format(case, seated, #people, #homes))
		local want, got, have = {}, {}, {}
		for _, h in ipairs(homes) do have[h.key] = (have[h.key] or 0) + 1 end
		for i, p in ipairs(people) do
			if p.pin ~= "" then want[p.pin] = (want[p.pin] or 0) + 1; if ok[i] then got[p.pin] = (got[p.pin] or 0) + 1 end end
		end
		for key, n in pairs(want) do
			local expect = math.min(n, have[key] or 0)
			assert((got[key] or 0) == expect, ("case %d: %s has %d pinned seated, want %d"):format(case, key, got[key] or 0, expect))
		end
	end
end)

test("moving one person's pin never moves another person SITTING IN THEIR PIN in a third room", function()
	local g = rng(77)
	for case = 1, 2000 do
		local people, homes = world(g, 50)
		if #people > 0 then
			local before, okBefore = Seat.assign(people, homes, fits)
			local who = g:int(1, #people)
			local old = people[who].pin
			people[who].pin = KEYS[g:int(1, 6)]
			local after = Seat.assign(people, homes, fits)
			for i, p in ipairs(people) do
				-- a pin whose room had no free seat sits as unpinned (spec 3.4) and may shift; only
				-- people actually sitting in their pinned room are promised their seat
				if i ~= who and okBefore[i] and p.pin ~= old and p.pin ~= people[who].pin then
					assert(before[i] == after[i], ("case %d: person %d (pinned %s) moved when %d changed %s -> %s"):format(case, i, p.pin, who, old, people[who].pin))
				end
			end
		end
	end
end)

test("deterministic: the same input seats the same way", function()
	local g = rng(5)
	for _ = 1, 500 do
		local people, homes = world(g, 30)
		local a, b = Seat.assign(people, homes, fits), Seat.assign(people, homes, fits)
		for i = 1, #people do assert(a[i] == b[i], "not deterministic") end
	end
end)

test("pin to a room with no seats: seated as unpinned, pin kept by the caller", function()
	local homes = { { room = "office", key = "eng" } }
	local people = { { role = "engineer", pin = "cafe" } }
	local seat, ok = Seat.assign(people, homes, fits)
	assert(seat[1] == 1 and not ok[1], "should sit in the only seat, not as pinned")
end)

test("no homes: nobody seated, no error", function()
	local seat = Seat.assign({ { role = "engineer", pin = "eng" } }, {}, fits)
	assert(seat[1] == nil, "seated with no seats")
end)

test("freeFor: seats of that room minus OTHER people pinned there", function()
	local homes = { { room = "cafe", key = "cafe" }, { room = "cafe", key = "cafe" }, { room = "office", key = "eng" } }
	local people = { { role = "sales", pin = "cafe" }, { role = "sales", pin = "cafe" }, { role = "engineer", pin = "" } }
	assert(Seat.freeFor(people, homes, "cafe", 3) == 0, "both cafe seats are pinned by others")
	assert(Seat.freeFor(people, homes, "cafe", 1) == 1, "person 1's own pin does not count against them")
	assert(Seat.freeFor(people, homes, "eng", 3) == 1, "one free eng seat")
	assert(Seat.freeFor(people, homes, "labs", 3) == 0, "no labs at all")
end)

return T
