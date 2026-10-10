--[[ feedback.spec.luau -- what the TELL US box stores, checked offline.
	Feedback.clean is the only thing between a client's string and a DataStore
	write: junk must be refused, and the 300-character cut must never split a
	character (a broken UTF-8 string can fail the write). ]]
local F = require("../../src/ServerScriptService/Feedback")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

test("junk is refused, with a reason", function()
	for _, bad in { 42, true, {}, "", "  ", "ab", "\n\t\n" } do
		assert(F.clean(bad) == nil, "accepted junk: " .. tostring(bad))
	end
	assert(F.clean("\255\254 not utf8") == nil, "accepted invalid UTF-8")
end)

test("text is trimmed and control characters become spaces", function()
	assert(F.clean("  the chase is too hard  ") == "the chase is too hard", "not trimmed")
	assert(F.clean("line one\nline two") == "line one line two", "a newline survived")
end)

test("the cut is at 300 characters, never inside one", function()
	local long = string.rep("a", 500)
	assert(#F.clean(long) == 300, "plain text not cut at 300")
	local emoji = string.rep("😀", 400)            -- 4 bytes each
	local out = F.clean(emoji)
	assert(utf8.len(out) == 300, ("emoji cut to %s characters"):format(tostring(utf8.len(out))))
	assert(#out == 1200, "a character was split")
end)

test("keys sort by time as text", function()
	local a, b = F.key(999999999, 5), F.key(1791588063, 1688749216)
	assert(a < b, "an older message sorts after a newer one: " .. a .. " vs " .. b)
end)

return T
