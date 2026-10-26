-- flags.spec.luau: the kill switch's pure half (26 Oct 2026, safety net part 2).
-- Every live server reads the SVFlags_v1 record each minute; a flag turns a feature off with
-- no publish. A bad record must never turn a feature off by accident.
local F = require("../../src/ServerScriptService/Flags")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

test("no record means every feature on (its default)", function()
	assert(F.parse(nil).bobScenes == true, "bobScenes default on")
end)

test("a stored false turns a feature off", function()
	assert(F.parse({ bobScenes = false }).bobScenes == false, "off")
end)

test("junk never turns a feature off", function()
	for _, raw in { "off", 0, { bobScenes = "false" }, { bobScenes = 0 }, { bobScenes = {} } } do
		assert(F.parse(raw).bobScenes == true, "junk turned it off")
	end
end)

test("unknown names are ignored", function()
	assert(F.parse({ nope = false, bobScenes = true }).nope == nil, "unknown kept")
end)

test("set refuses an unknown flag or a non-boolean value", function()
	assert(F.check("nope", false) == false, "unknown")
	assert(F.check("bobScenes", "off") == false, "not a boolean")
	assert(F.check("bobScenes", false) == true, "valid")
end)

test("live and Studio read different keys", function()
	assert(F.key(false) == "live" and F.key(true) == "studio", "keys")
end)

return T
