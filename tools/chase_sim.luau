--[[ The chase table: escape rates by tier and behaviour, old hunter vs new,
from the SAME ChaseRules code TalentDrop runs.   lune run tools/chase_sim ]]
local R = require("../src/ServerScriptService/ChaseRules")
local M = require("../tests/offline/chase_model")
local N = 2000
local RUNS = {
	{ id = "skilled", name = "SKILLED", D = 140, speed = 16, old = { 11, 17 } },
	{ id = "star", name = "STAR", D = 280, speed = 17, old = { 12, 19 } },
	{ id = "genius", name = "GENIUS", D = 440, speed = 18, old = { 13, 21 } },
	{ id = "star", name = "VIP (Studio)", D = 600, speed = 17, vip = true, old = { 12, 19 } },
	{ id = "genius", name = "VIP (Loft+)", D = 600, speed = 19, vip = true, old = { 13, 21 } },
}
print(("%-13s | %-24s | %-44s"):format("run", "OLD novice / danger", "NEW novice / good / freeze 1.5s / stand 3s / danger"))
for _, r in RUNS do
	local o = { D = r.D, speed = r.speed, deadline = 14 + (r.D + 40) * 0.11 }
	local old = M.oldRules(r.old[1], r.old[2])
	local new = M.newRules(R, R.config(r.id, r.vip, r.speed))
	o.skill = "novice"
	local on, _, od = M.rate(R, old, o, N)
	local nn, _, nd = M.rate(R, new, o, N)
	o.skill = "good"; local ng = M.rate(R, new, o, N)
	o.skill = "hesitant"; local nh = M.rate(R, new, o, N)
	o.skill = "idle"; local ni = M.rate(R, new, o, N)
	print(("%-13s | %5.0f%% / %3.0f%%            | %5.0f%% / %5.0f%% / %5.0f%% / %5.0f%% / %3.0f%%"):format(
		r.name, on * 100, od * 100, nn * 100, ng * 100, nh * 100, ni * 100, nd * 100))
end
