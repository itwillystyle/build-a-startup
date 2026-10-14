--[[ Seating (14 Oct 2026, Manage Staff phase 2): who sits where. Pure.

	Pass 1, PINS: in list order, each pinned person takes a free seat whose key (the Wafers
	department, or "hq" for the garage bench) is their pin, a seat that fits their job first.
	Pass 2, EVERYONE ELSE, exactly as assignDesks always did: list order, a free seat that
	fits their job, else any free seat. A pinned person whose room had no free seat is
	seated here as unpinned; the caller keeps their pin (spec §3.4).

	Proved offline (seating.spec): with no pins this is the old seating, seat for seat;
	no seat is used twice; pins are filled up to their room's seats; moving one person's
	pin never moves a pinned person in a third room. Unpinned people CAN shift when a pin
	takes their seat: that is the cost of a pin, and they were never promised a room. ]]
local Seating = {}

function Seating.assign(people, homes, fits)
	local used, seat, pinnedOk = {}, {}, {}
	for i, p in ipairs(people) do
		local pin = p.pin
		if type(pin) == "string" and pin ~= "" then
			local pick
			for k, h in ipairs(homes) do if not used[k] and h.key == pin and fits(p.role, h.room) then pick = k break end end
			if not pick then for k, h in ipairs(homes) do if not used[k] and h.key == pin then pick = k break end end end
			if pick then used[pick] = true; seat[i] = pick; pinnedOk[i] = true end
		end
	end
	for i, p in ipairs(people) do
		if not seat[i] then
			local pick
			for k, h in ipairs(homes) do if not used[k] and fits(p.role, h.room) then pick = k break end end
			if not pick then for k in ipairs(homes) do if not used[k] then pick = k break end end end
			if pick then used[pick] = true; seat[i] = pick end
		end
	end
	return seat, pinnedOk
end

-- how many seats of `key` person `index` could still take if they pinned there:
-- every seat of that room, minus the OTHER people already pinned to it
function Seating.freeFor(people, homes, key, index)
	local seats, taken = 0, 0
	for _, h in ipairs(homes) do if h.key == key then seats += 1 end end
	for i, p in ipairs(people) do if i ~= index and p.pin == key then taken += 1 end end
	return seats - taken
end

-- phase 3: every pin room the plot has, in the TEAM screen's order, with its seats and
-- how many are free to pin to (freeFor with nobody excluded: what MOVE will accept)
Seating.ORDER = { "hq", "lobby", "eng", "studio", "cafe", "labs" }
function Seating.rooms(people, homes)
	local seats, kind = {}, {}
	for _, h in ipairs(homes) do
		seats[h.key] = (seats[h.key] or 0) + 1
		kind[h.key] = kind[h.key] or h.room
	end
	local out = {}
	for _, key in ipairs(Seating.ORDER) do
		if seats[key] then
			table.insert(out, { key = key, room = kind[key], seats = seats[key], free = Seating.freeFor(people, homes, key, nil) })
		end
	end
	return out
end

return Seating
