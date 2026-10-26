-- saverescue.spec.luau: picking a save version to restore (26 Oct 2026, safety net part 3).
-- Roblox keeps every version of a DataStore key for 30 days; SaveRescue lists them and puts
-- one back (Studio only, after a backup). Choosing the version is the part that must be right.
local R = require("../../src/ServerScriptService/SaveRescue")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local V = {   -- newest first, as ListVersionsAsync(Descending) gives them; created in ms
	{ version = "v5", created = 5000000, deleted = false },
	{ version = "v4", created = 4000000, deleted = true },
	{ version = "v3", created = 3000000, deleted = false },
	{ version = "v1", created = 1000000, deleted = false },
}

test("pick: the newest version made at or before the time", function()
	assert(R.pick(V, 4500).version == "v3", "skips deleted v4")
	assert(R.pick(V, 5000).version == "v5", "exact time counts")
	assert(R.pick(V, 3999).version == "v3", "between")
end)

test("pick: nothing that old", function()
	assert(R.pick(V, 999) == nil, "too old")
end)

test("summary: the numbers that tell two saves apart", function()
	local s = R.summary({ cash = 120000, hq = 4, wl = 13, staff = 9, earned = 5e6, lastSeen = 1793000000, name = "Neon", jr = { bobPaid = true } })
	assert(s.cash == 120000 and s.hq == 4 and s.wl == 13 and s.staff == 9 and s.name == "Neon", "fields")
	assert(s.lastSeen == 1793000000 and s.bobPaid == true, "lastSeen, bob")
	assert(R.summary(nil) == nil and R.summary("x") == nil, "junk")
end)

test("restore needs the exact confirm words for that player", function()
	assert(R.confirmed(1688749216, "restore 1688749216") == true, "exact")
	assert(R.confirmed(1688749216, "restore 1") == false, "other id")
	assert(R.confirmed(1688749216, nil) == false, "nil")
	assert(R.confirmed(1688749216, "yes") == false, "yes")
end)

return T
