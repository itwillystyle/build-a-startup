-- names.spec.luau: the company name a new save starts with (no naming popup; spec 2026-10-16-client-loop-design.md).
local Names = require("../../src/ServerScriptService/Names")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

test("same seed, same name", function()
	assert(Names.generate(1688749216) == Names.generate(1688749216), "a player keeps one name")
end)

test("two words, 3 to 20 characters", function()
	for seed = 1, 200 do
		local n = Names.generate(seed * 7919)
		assert(#n >= 3 and #n <= 20, ("'%s' is %d characters"):format(n, #n))
		local words = 0
		for _ in n:gmatch("%S+") do words += 1 end
		assert(words == 2, ("'%s' is not two words"):format(n))
	end
end)

test("100 seeds give at least 40 different names", function()
	local seen, n = {}, 0
	for seed = 1, 100 do
		local name = Names.generate(seed * 104729 + 17)
		if not seen[name] then seen[name] = true; n += 1 end
	end
	assert(n >= 40, "only " .. n .. " different names")
end)

return T
