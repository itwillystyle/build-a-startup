-- teamview.spec.luau: what every part of the TEAM screen shows, from StaffData and StaffRooms (14 Oct 2026)
local V = require("../../src/ReplicatedStorage/TeamView")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local function ids(rows)
	local out = {}
	for _, r in ipairs(rows) do table.insert(out, tostring(r.id)) end
	return table.concat(out, ",")
end

test("room labels are the spec's words, in the spec's order", function()
	local keys, labels = {}, {}
	for _, r in ipairs(V.ROOMS) do table.insert(keys, r.key); table.insert(labels, r.label) end
	assert(table.concat(keys, ",") == "hq,lobby,eng,studio,cafe,labs", table.concat(keys, ","))
	assert(table.concat(labels, ",") == "Garage,Lobby,Engineering,Design Studio,Cafe,AI Labs", table.concat(labels, ","))
	assert(V.label("eng") == "Engineering" and V.label("servers") == "servers" and V.label(nil) == "", "label")
end)

test("talent and seniority names, clamped", function()
	assert(V.talent(1) == "Regular" and V.talent(5) == "Unicorn" and V.talent(9) == "Unicorn" and V.talent(nil) == "Regular", "talent")
	assert(V.seniority(1) == "Intern" and V.seniority(4) == "Lead" and V.seniority(0) == "Intern", "seniority")
end)

test("sort by $/s: rate high to low, then talent, then id; a new array", function()
	local rows = { { id = 1, rate = 10, talent = 1 }, { id = 2, rate = 50, talent = 1 }, { id = 3, rate = 10, talent = 4 },
		{ id = 4, talent = 5 }, { id = 5, rate = 0 / 0, talent = 1 }, { id = 6, rate = 10, talent = 1 } }
	local out = V.sort(rows, "rate")
	assert(ids(out) == "2,3,1,6,4,5", ids(out))
	assert(rows[1].id == 1, "input untouched")
end)

test("sort by talent: talent, then rate, then id", function()
	local rows = { { id = 1, rate = 10, talent = 1 }, { id = 2, rate = 50, talent = 1 }, { id = 3, rate = 10, talent = 4 },
		{ id = 4, rate = 99, talent = 4 } }
	assert(ids(V.sort(rows, "talent")) == "4,3,2,1", ids(V.sort(rows, "talent")))
end)

test("train button: MAX at the cap, dim when you cannot pay, else the price", function()
	local s = { level = 3, cap = 3, price = 500 }
	assert(V.train(s, 1e9).state == "max", "at cap")
	assert(V.train({ level = 9, cap = 3, price = 1 }, 1e9).state == "max", "above cap (after a spin-off)")
	local poor = V.train({ level = 1, cap = 3, price = 500 }, 499)
	assert(poor.state == "poor" and poor.price == 500, "poor shows the price")
	assert(V.train({ level = 1, cap = 3, price = 500 }, 500).state == "ok", "exactly enough")
	assert(V.train(nil, 1e9).state == "max", "no stat: nothing to buy")
	assert(V.train({ level = 1, cap = 3, price = 500 }, nil).state == "poor", "unknown cash")
end)

test("move chips: one per room present, pinned = here, none free = full, fit rooms are best", function()
	local rooms = { { key = "hq", room = "hq", seats = 1, free = 1 }, { key = "eng", room = "office", seats = 4, free = 2 },
		{ key = "cafe", room = "cafe", seats = 2, free = 0 } }
	local chips = V.chips({ pin = "", fits = { "hq", "office" } }, rooms)
	assert(#chips == 3 and chips[1].key == "hq" and chips[2].label == "Engineering", "order and labels")
	assert(chips[1].best and chips[2].best and not chips[3].best, "best fit from fits")
	assert(chips[2].state == "ok" and chips[2].free == 2, "eng ok")
	assert(chips[3].state == "full", "cafe full")
	local pinned = V.chips({ pin = "cafe", fits = {} }, rooms)
	assert(pinned[3].state == "here", "their own pin is here, even with 0 free (it counts them)")
	assert(#V.chips({ pin = "" }, nil) == 0, "no rooms data yet")
end)

test("note: a pin the server could not honour, or the waiting line", function()
	assert(V.note({ pin = "cafe", room = "lobby" }) == "No free seat in Cafe", tostring(V.note({ pin = "cafe", room = "lobby" })))
	assert(V.note({ pin = "cafe", room = "cafe" }) == nil, "honoured")
	assert(V.note({ pin = "", room = nil }) == "Waiting for a desk", "unseated")
	assert(V.note({ pin = "eng" }) == "No free seat in Engineering", "pinned and unseated: the pin is the news")
	assert(V.note({ pin = "", room = "eng" }) == nil, "fine")
end)

test("why: every server reason has the player's words", function()
	for _, r in ipairs({ "busy", "not yours", "at max", "need cash", "already there", "no free seat", "bad stat", "bad room",
		"bad id", "unknown action", "no plot" }) do
		local w = V.why(r)
		assert(type(w) == "string" and #w > 0 and w ~= r, r)
	end
	assert(type(V.why(nil)) == "string" and type(V.why("something new")) == "string", "unknown reasons still read")
end)

test("find: the row with this id, or nil", function()
	local rows = { { id = 4 }, { id = 9 } }
	assert(V.find(rows, 9) == rows[2] and V.find(rows, 5) == nil and V.find(nil, 1) == nil, "find")
end)

return T
