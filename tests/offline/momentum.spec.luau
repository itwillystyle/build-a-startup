-- momentum.spec.luau: the stock you can only earn outside the base, run outside Studio.
local M = require("../../src/ServerScriptService/Momentum")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

test("a rarer candidate is worth more to bring home", function()
	assert(M.award("walkin") < M.award("genius"), "walkin should pay less than genius")
	assert(M.award("genius") < M.award("unicorn"), "genius should pay less than unicorn")
	assert(M.award("vip") > M.award("star"), "a VIP run should beat an ordinary star")
end)

test("an unknown kind pays nothing rather than erroring", function()
	assert(M.award("nonsense") == 0, "unknown kind should be 0")
end)

test("the stock cannot exceed the ceiling", function()
	local p = 0
	for _ = 1, 50 do p = M.add(p, "unicorn") end
	assert(p == M.MAX, "stock should cap at MAX, got " .. tostring(p))
end)

test("no stock means no discount, and the price is untouched", function()
	assert(M.discount(0) == 0, "0 points should be 0 discount")
	assert(M.priceAfter(1000, 0) == 1000, "price should be unchanged at 0 points")
end)

--[[ THE LOAD-BEARING PROMISE: a player who never leaves the garage must not be
	worse off than before this file existed. If this ever fails, the feature
	has quietly become a tax. ]]
test("the discount never raises a price", function()
	for p = 0, M.MAX do
		assert(M.priceAfter(10000, p) <= 10000, "price went up at " .. p .. " points")
	end
end)

test("one build cannot spend more than the cap", function()
	assert(M.spend(M.MAX) == M.SPEND_CAP, "spend should cap at SPEND_CAP")
	assert(M.discount(M.MAX) == M.SPEND_CAP * M.PER_POINT, "discount should cap with the spend")
end)

test("the best discount is 36 percent", function()
	local d = M.discount(M.MAX)
	assert(math.abs(d - 0.36) < 1e-9, "expected 0.36, got " .. tostring(d))
end)

test("more stock is never worth less", function()
	local last = -1
	for p = 0, M.MAX do
		local d = M.discount(p)
		assert(d >= last, "discount went down between " .. (p - 1) .. " and " .. p)
		last = d
	end
end)

test("a crafted save cannot mint discount", function()
	assert(M.sanitize(9999) == M.MAX, "huge value should clamp to MAX")
	assert(M.sanitize(-5) == 0, "negative should clamp to 0")
	assert(M.sanitize("12") == 0, "a string should sanitize to 0")
	assert(M.sanitize(nil) == 0, "nil should sanitize to 0")
	assert(M.sanitize(0 / 0) == 0, "nan should sanitize to 0")
end)

--[[ The decision the whole mechanic exists to create: build now, or run one
	more recruit and build cheaper. If a second genius does not beat building
	immediately, there is no decision and the loop is decorative. ]]
test("waiting for one more genius beats building now", function()
	local price = 100000
	local now = M.priceAfter(price, 4)
	local later = M.priceAfter(price, M.add(4, "genius"))
	assert(later < now, "one more genius should make the build cheaper")
end)

return T
