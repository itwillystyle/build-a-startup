--[[ chase_threat -- the 8 Oct table: who escapes, by tier, scooter speed and behaviour.

	    lune run tools/chase_threat

	The spec (docs/superpowers/specs/2026-10-08-chase-threat-design.md) wants the
	straight-line W-holder and the BOOST spammer caught on a genius run, and the
	player who reads the tell (steers or boosts) to get away. Rows are escape
	rates over N seeded runs of the SAME ChaseRules code the server runs. ]]
local R = require("../src/ServerScriptService/ChaseRules")
local M = require("../tests/offline/chase_model")
local N = 2000
local SKILLS = { "straight", "spammer", "novice", "dodger", "good", "reader", "ace", "hesitant", "idle" }
local RUNS = {
	{ id = "skilled", D = 140, speeds = { 16, 20 } },
	{ id = "star", D = 280, speeds = { 17, 20 } },
	{ id = "genius", D = 300, speeds = { 18, 19, 20 } },
}
local head = ("%-8s %5s |"):format("tier", "speed")
for _, k in SKILLS do head ..= (" %8s"):format(k) end
print(head .. " | lunges/run")
for _, r in RUNS do
	for _, sp in r.speeds do
		local o = { D = r.D, speed = sp, deadline = 14 + (r.D + 40) * 0.11 }
		local rules = M.newRules(R, R.config(r.id, false, sp))
		local line = ("%-8s %5d |"):format(r.id, sp)
		for _, k in SKILLS do
			o.skill = k
			local esc = M.rate(R, rules, o, N)
			line ..= (" %7.0f%%"):format(esc * 100)
		end
		o.skill = "straight"
		local _, lunges = M.lunges and M.lunges(R, rules, o, 200) or nil, nil
		print(line .. (lunges and (" | %.1f"):format(lunges) or ""))
	end
end
print("escape rate per behaviour (higher = player got away)")
