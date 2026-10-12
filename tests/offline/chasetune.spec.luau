--[[ chasetune.spec.luau -- the overnight chase tuner's own bookkeeping (11 Oct 2026).
	The search is judged by chase.spec and chasecam.spec themselves (tools/chase_tune_lib);
	what is tested here is that the tuner cannot leave the game's tables changed, that
	the director's own rules survive any step it takes, and that the edits it reports
	name only what moved, in the file a person edits. ]]
local L = require("../../tools/chase_tune_lib")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

test("apply then restore leaves ChaseRules and ChaseCam exactly as loaded", function()
	local before = L.read()
	local moved = table.clone(before)
	for _, d in L.PARAMS do moved[d.key] = d.hi end
	L.apply(moved)
	assert(L.R.TIERS.genius.lunge == 2.20 and L.C.DIR.MIN_HOLD == 2.6, "apply did not reach the module tables")
	L.restore()
	for k, v in L.read() do assert(v == before[k], k .. " was not restored") end
end)

test("every knob is in its box and every step keeps the director's rules", function()
	local rnd = L.rng(42)
	local p = L.read()
	for _ = 1, 500 do
		p = L.neighbour(p, rnd, 1)
		for _, d in L.PARAMS do
			if d.key ~= "cam.MIN_HOLD" and d.key ~= "cam.EPISODE" and d.key ~= "cam.CLOSE_OUT" and d.key ~= "cam.AWAY_OUT" then
				assert(p[d.key] >= d.lo - 1e-9 and p[d.key] <= d.hi + 1e-9, d.key .. " left its box")
			end
		end
		assert(p["cam.CLOSE_OUT"] >= p["cam.CLOSE_IN"] + 0.3 - 1e-9, "closing lost its hysteresis")
		assert(p["cam.AWAY_OUT"] <= p["cam.AWAY_IN"] - 0.3 + 1e-9, "gaining lost its hysteresis")
		assert(p["cam.MIN_HOLD"] >= p.WINDUP + p.LUNGE_TIME - 0.2 - 1e-9, "the tell's shot can be cut mid-strike")
	end
end)

test("the edits name only what moved, rounded, in the file a person edits", function()
	local base = L.read()
	local p = table.clone(base)
	p["genius.lunge"] = 1.8734
	p["cam.EPISODE"] = 4.21
	local edits = L.diff(base, p)
	assert(#edits == 2, ("%d edits for 2 moved knobs"):format(#edits))
	for _, e in edits do
		if e.key == "genius.lunge" then
			assert(e.to == 1.87 and e.file == "src/ServerScriptService/ChaseRules.lua" and e.name == "C.TIERS.genius.lunge", "genius.lunge edit")
		else
			assert(e.to == 4.21 and e.file == "src/ReplicatedStorage/ChaseCam.lua" and e.name == "ChaseCam.DIR.EPISODE", "EPISODE edit")
		end
	end
	assert(#L.diff(base, base) == 0, "no move, no edit")
end)

test("the knobs it may turn are read live (none baked in when the module loads)", function()
	-- BEHIND_DEG is baked into a cosine at load, so it must never be on the list
	for _, d in L.PARAMS do assert(d.key ~= "BEHIND_DEG", "BEHIND_DEG cannot be tuned at runtime") end
end)

test("every tier is judged at a fast scooter too: the star's exploit ceilings are in the score", function()
	local seen = {}
	for _, t in L.TARGETS do if t[5] == "most" then seen[t[2] .. "@" .. t[3] .. ":" .. t[4]] = true end end
	assert(seen["star@20:straight"] and seen["star@20:spammer"], "the star at 20 studs/s must be scored (night of 11 Oct: 100% escapes)")
end)

return T
