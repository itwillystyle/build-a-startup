-- sloprules.spec.luau: the composition checks the doctor runs on every screen (14 Oct 2026)
local R = require("../../src/ReplicatedStorage/SlopRules")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

test("LOUD is DESIGN.md's six role colours", function()
	assert(#R.LOUD == 6 and R.isLoud({ 60, 203, 108 }) and R.isLoud({ 61, 205, 107 }), "green, within 3")
	assert(not R.isLoud({ 221, 247, 230 }) and not R.isLoud({ 255, 252, 246 }) and not R.isLoud({ 236, 230, 218 }), "light tints, paper, surface are calm")
end)

test("loudButtons: the old TEAM card (3 green TRAIN) is one finding; one green is fine", function()
	local g, p = { 60, 203, 108 }, { 255, 252, 246 }
	local old = { { menu = "Team", path = "a", rgb = g }, { menu = "Team", path = "b", rgb = g }, { menu = "Team", path = "c", rgb = g }, { menu = "Team", path = "d", rgb = p } }
	local f = R.loudButtons(old)
	assert(#f == 1 and f[1].menu == "Team" and f[1].count == 3 and #f[1].paths == 3, "3 loud")
	assert(#R.loudButtons({ { menu = "Team", path = "a", rgb = g }, { menu = "Team", path = "d", rgb = p } }) == 0, "one loud")
	assert(#R.loudButtons({ { menu = "Team", path = "a", rgb = g }, { menu = "Index", path = "b", rgb = g } }) == 0, "per menu")
	assert(#R.loudButtons({}) == 0, "none")
end)

test("saidTwice: the same fact twice in one screen (4+ characters with a letter), trimmed", function()
	local f = R.saidTwice({ { gui = "Team", path = "row", text = "$12.9K/s" }, { gui = "Team", path = "card", text = " $12.9K/s " }, { gui = "Team", path = "x", text = "0/13" }, { gui = "Team", path = "y", text = "0/13" } })
	assert(#f == 1 and f[1].text == "$12.9K/s", "one repeat (Speed 0/13 and Loyalty 0/13 are two facts): " .. #f)
	assert(#R.saidTwice({ { gui = "Team", path = "a", text = "MAX" }, { gui = "Team", path = "b", text = "MAX" } }) == 0, "3 chars: too short to be a fact")
	assert(#R.saidTwice({ { gui = "Team", path = "a", text = "Noor" }, { gui = "Hud", path = "b", text = "Noor" } }) == 0, "different screens")
	assert(#R.saidTwice({ { gui = "Team", path = "a", text = "" }, { gui = "Team", path = "b", text = "" } }) == 0, "empty")
end)

test("cutOff: text that does not fit, or a button outside its clipping frame", function()
	local f = R.cutOff({
		{ path = "t", fits = false, rect = { 0, 0, 10, 10 } },
		{ path = "chip", fits = true, rect = { 0, 300, 50, 50 }, clip = { 0, 0, 400, 320 } },
		{ path = "ok", fits = true, rect = { 10, 10, 50, 50 }, clip = { 0, 0, 400, 320 } },
		{ path = "edge", rect = { 0, 0, 400.6, 320.6 }, clip = { 0, 0, 400, 320 } },
	})
	assert(#f == 2 and f[1].path == "t" and f[1].why == "text does not fit" and f[2].path == "chip" and f[2].why == "outside its frame", "two cut off")
end)

return T
