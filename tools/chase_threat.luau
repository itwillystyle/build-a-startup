--[[ chase_threat -- the 8 Oct table: who escapes, by tier, scooter speed and behaviour.

	    lune run tools/chase_threat
	    lune run tools/chase_threat -- --json --n 500   (machine-readable, for tools/bas)

	The spec (docs/superpowers/specs/2026-10-08-chase-threat-design.md) wants the
	straight-line W-holder and the BOOST spammer caught on a genius run, and the
	player who reads the tell (steers or boosts) to get away. Rows are escape
	rates over N seeded runs of the SAME ChaseRules code the server runs. ]]
local process = require("@lune/process")
local serde = require("@lune/serde")
local R = require("../src/ServerScriptService/ChaseRules")
local M = require("../tests/offline/chase_model")

local args = process.args
local JSON = table.find(args, "--json") ~= nil
local nAt = table.find(args, "--n")
local N = nAt and tonumber(args[nAt + 1]) or 2000

local SKILLS = { "straight", "spammer", "novice", "dodger", "good", "reader", "ace", "hesitant", "idle" }
local RUNS = {
	{ id = "skilled", D = 140, speeds = { 16, 20 } },
	{ id = "star", D = 280, speeds = { 17, 20 } },
	{ id = "genius", D = 300, speeds = { 18, 19, 20 } },
}
local rows = {}
for _, r in RUNS do
	for _, sp in r.speeds do
		local o = { D = r.D, speed = sp, deadline = 14 + (r.D + 40) * 0.11 }
		local rules = M.newRules(R, R.config(r.id, false, sp))
		local escape = {}
		for _, k in SKILLS do
			o.skill = k
			escape[k] = math.floor(M.rate(R, rules, o, N) * 1000 + 0.5) / 10 -- percent, 1 decimal
		end
		table.insert(rows, { tier = r.id, speed = sp, escape = escape })
	end
end

if JSON then
	print(serde.encode("json", { tool = "chase_threat", n = N, unit = "escape %", rows = rows }))
	return
end

local head = ("%-8s %5s |"):format("tier", "speed")
for _, k in SKILLS do head ..= (" %8s"):format(k) end
print(head)
for _, row in rows do
	local line = ("%-8s %5d |"):format(row.tier, row.speed)
	for _, k in SKILLS do line ..= (" %7.0f%%"):format(row.escape[k]) end
	print(line)
end
print(("escape rate per behaviour over %d seeded runs (higher = player got away)"):format(N))
