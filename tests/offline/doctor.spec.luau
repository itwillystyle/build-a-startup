--[[ doctor.spec.luau -- the game doctor's judging, checked offline.

	The doctor is only useful if its verdicts are right: a failed check must become
	a finding with the right severity, the same problem on four HQ levels must be
	ONE finding, "new" and "fixed" must compare like with like, and the Discord
	message must never pass Discord's 2,000-character limit. Plus the two
	per-frame rules the client probes count with (DoctorProbes). ]]
local D = require("../../tools/doctor_lib")
local P = require("../../src/ReplicatedStorage/DoctorProbes")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local function report(extra)
	local r = { steps = {
		{ name = "world", checks = { { name = "sinking surfaces", ok = true, measured = 0, expected = 0 } } },
		{ name = "hq:9", checks = {
			{ name = "cards over cards", ok = false, severity = "FEEL", measured = 2, expected = 0 },
			{ name = "lift lands you on a floor", ok = false, severity = "BUG", measured = 1, expected = 0, detail = "F8 fell" } } },
		{ name = "hq:18", checks = { { name = "lift lands you on a floor", ok = false, severity = "BUG", measured = 1, expected = 0 } } },
		{ name = "chase:genius", checks = {
			{ name = "the chase ran", ok = false, severity = "BLOCKER", measured = "no result" },
			{ name = "outcome (robot rides straight)", ok = true, info = true, measured = "caught" } } },
	} }
	for k, v in pairs(extra or {}) do r[k] = v end
	return r
end

test("failed checks become findings, worst first; infos are kept apart", function()
	local f, infos = D.findings(report())
	assert(#f == 4, ("want 4 findings, got %d"):format(#f))
	assert(f[1].severity == "BLOCKER" and f[#f].severity == "FEEL", "not sorted worst first")
	assert(#infos == 1 and infos[1].measured == "caught", "the chase outcome should be an info row, not a finding")
	local crashed = D.findings(report({ crashed = "boom" }))
	assert(crashed[1].key == "run / crashed", "a crashed run must be the first finding")
end)

test("the same problem on several HQ levels is one finding; new and fixed compare families", function()
	local f = D.findings(report())
	local d = D.diff({ "hq:5 / lift lands you on a floor", "hq:5 / stand on every storey" }, f)
	assert(#d.still == 1 and d.still[1].name == "lift lands you on a floor", "the lift drop on hq:9 and hq:18 is the same one as hq:5's")
	assert(#d.new == 2, ("want 2 new families (the chase, the cards), got %d"):format(#d.new))
	assert(#d.fixed == 1 and d.fixed[1] == "hq / stand on every storey", "standing was fixed since the last run")
end)

test("the Discord message stays under the limit and leads with the verdict", function()
	local f = D.findings(report())
	local long = {}
	for i = 1, 40 do
		table.insert(long, { key = "hq:" .. i .. " / thing " .. i, step = "hq:" .. i, name = "thing " .. i, severity = "BUG",
			measured = i, expected = 0, detail = string.rep("x", 300) })
	end
	local text = D.discord(long, D.diff({}, long), "Sun 11 Oct")
	assert(#text <= D.DISCORD_MAX, ("%d characters"):format(#text))
	local t2 = D.discord(f, D.diff({}, f), "Sun 11 Oct")
	assert(t2:find("^%*%*Game doctor%*%* RED"), "a BLOCKER makes the verdict RED")
	assert(D.discord({}, D.diff({}, {}), "x"):find("Nothing found", 1, true), "an empty run should say so")
end)

test("a camera cut and a hunter hitch, frame by frame", function()
	assert(P.isCut(12, 0) and P.isCut(0, 60), "a 12-stud jump or a 60 degree turn in one frame is a cut")
	assert(not P.isCut(1.2, 4), "following a runner at 20 studs/s is not a cut")
	assert(P.isStutter(0.3, 2.1), "a step that jumps from 0.3 to 2.1 studs is a visible hitch")
	assert(not P.isStutter(0.3, 0.4), "steady running is not a hitch")
end)

return T
