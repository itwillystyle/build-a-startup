--[[ savecontract.spec.luau -- can a save lose a field? (Phase 2, 9 Oct 2026)

	The way a save actually gets lost is not a bad number, it is a field that one
	side forgets: written by serialize and never read back (it resets on every
	join), read by applySave and never written (it is always the default), or a
	field an old save carries that the loader no longer reads (that player's
	progress silently drops). All three are visible in SaveLoad.lua's own text,
	so this reads the source instead of standing up the 30 live game functions
	applySave needs.

	It does NOT check values (clamps, migrations): Momentum, Journey and
	home.spec cover their own sanitizers. A full load -> save -> load round trip
	needs SaveLoad split from the world building it does; that is a refactor,
	not a test. ]]
local fs = require("@lune/fs")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local SRC = fs.readFile("src/ServerScriptService/SaveLoad.lua")

-- the field names of a real v1 save (save_backup_11510645938.json, the main
-- account, 2026). Names only: the values are a player's and stay out of the repo.
local V1_FIELDS = { "wings", "lastSeen", "tiers", "hq", "placed", "ipo", "playtime", "shipped", "launches",
	"rate", "v", "name", "valuation", "work", "staff", "muted", "cash" }

-- applySave hands the save to these, and they read their own fields
local DELEGATES = {
	{ file = "src/ServerScriptService/Cars.lua", from = "function Cars.onLoad(", to = "\nend" },   -- cars, car
}

-- written on purpose and never read: each one says why
local WRITE_ONLY = {
	v = "format version; nothing branches on it yet",
}

local function between(src, a, b)
	local i = src:find(a, 1, true)
	local j = i and src:find(b, i, true)
	assert(i and j, ("SaveLoad.lua changed shape: could not find %q .. %q"):format(a, b))
	return src:sub(i, j)
end

-- -> written (set), read (set)
local function contract(src)
	local ser = between(src, "local function serialize(player)", "local function saveNow(")
	local body = ser:sub((ser:find("return {", 1, true)) or 1)
	local written = {}
	for key in body:gmatch("\n\t\t\t([%a_][%w_]*) = ") do written[key] = true end
	-- applySave and loadOnce (which passes data.items to the bag) to the end of the file
	local at = src:find("local function applySave(", 1, true)
	assert(at, "SaveLoad.lua changed shape: no applySave")
	local apply = src:sub(at)
	local read = {}
	for key in apply:gmatch("data%.([%a_][%w_]*)") do read[key] = true end
	for _, d in DELEGATES do
		for key in between(fs.readFile(d.file), d.from, d.to):gmatch("data%.([%a_][%w_]*)") do read[key] = true end
	end
	return written, read
end

local function gaps(src)
	local written, read = contract(src)
	local notRead, notWritten = {}, {}
	for k in written do if not read[k] and not WRITE_ONLY[k] then table.insert(notRead, k) end end
	for k in read do if not written[k] then table.insert(notWritten, k) end end
	table.sort(notRead)
	table.sort(notWritten)
	return notRead, notWritten, written, read
end

test("the contract parser finds the save (a parser that matches nothing passes everything)", function()
	local written, read = contract(SRC)
	local n, m = 0, 0
	for _ in written do n += 1 end
	for _ in read do m += 1 end
	assert(n >= 40, ("serialize writes only %d fields? the parser lost the table"):format(n))
	assert(m >= 40, ("applySave reads only %d fields? the parser lost the loader"):format(m))
	for _, k in { "cash", "staff", "mo", "apt", "hqPath", "spinoffs" } do
		assert(written[k] and read[k], "a known field was not found both ways: " .. k)
	end
end)

test("every field serialize writes is read back by applySave", function()
	local notRead = gaps(SRC)
	assert(#notRead == 0, "written but never loaded (resets every join): " .. table.concat(notRead, ", "))
end)

test("every field applySave reads is written by serialize", function()
	local _, notWritten = gaps(SRC)
	assert(#notWritten == 0, "loaded but never saved (always the default): " .. table.concat(notWritten, ", "))
end)

test("every field of a real v1 save is still read", function()
	local _, _, _, read = gaps(SRC)
	local lost = {}
	for _, k in V1_FIELDS do if not read[k] and not WRITE_ONLY[k] then table.insert(lost, k) end end
	assert(#lost == 0, "an old save carries fields the loader no longer reads: " .. table.concat(lost, ", "))
end)

test("removing a field from serialize on purpose is caught", function()
	-- the momentum bank, the newest field: drop the line that saves it
	local broken, n = SRC:gsub("\n\t\t\tmo = [^\n]*", "")
	assert(n == 1, "the planted fault could not be planted: the mo line moved")
	local _, notWritten = gaps(broken)
	assert(table.find(notWritten, "mo"), "a field that is no longer saved was not caught")
end)

test("renaming a field on the load side only is caught", function()
	local broken, n = SRC:gsub("data%.spinoffs", "data.spinOffs")
	assert(n >= 1, "the planted fault could not be planted")
	local notRead, notWritten = gaps(broken)
	assert(table.find(notRead, "spinoffs") and table.find(notWritten, "spinOffs"), "a one-sided rename was not caught")
end)

return T
