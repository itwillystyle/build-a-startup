--[[ chase_edit -- print the EDIT a real chase produces, with its reasons.

	    lune run tools/chase_edit
	    lune run tools/chase_edit -- genius good

	WHY THIS EXISTS. "The angle switching has no reasoning" is a judgement
	about a sequence, and a recording cannot be argued with -- you can see
	that an edit is bad and not why. This runs the REAL hunter (ChaseRules,
	the same code TalentDrop steps every frame) against a human-like carry,
	feeds the distances into the REAL director (ChaseCam.direct), and prints
	the cut list with the sentence each cut is making.

	Read the output as prose. If the column of reasons reads like a
	description of a chase, the edit has an argument in it. If two lines in a
	row say the same thing, or a line says something the player could not have
	noticed, that is the bug -- and it is now visible without a playtest.

	The player model is deliberately the same shape as tests/offline/
	chase_model.luau: a start delay, imperfect steering, and BOOST on most
	tells. It is not a population estimate; it is one plausible run.
]]
local process = require("@lune/process")
require("../tests/offline/roblox_globals")

local R = require("../src/ServerScriptService/ChaseRules")
local C = require("../src/ReplicatedStorage/ChaseCam")

--[[ lune passes the `--` separator straight through, so drop it rather than
	silently reading it as the tier (which it did, and every tier printed the
	same run). ]]
local argv = {}
for _, a in ipairs(process.args) do
	if a ~= "--" then table.insert(argv, a) end
end
local tier = argv[1] or "star"
local skill = argv[2] or "good"
local D = ({ skilled = 140, star = 280, genius = 440 })[tier] or 280
local SPEED = ({ skilled = 16, star = 17, genius = 18 })[tier] or 17

local PROF = {
	novice = { weave = 0.95, boostChance = 0, react = 1.0 },
	good = { weave = 0.96, boostChance = 0.75, react = 0.25 },
}
local prof = PROF[skill] or PROF.good

local seed = 7919
local function rnd()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

local cfg = R.config(tier, false, SPEED)
local DT = 1 / 60

--[[ The route TalentDrop actually sets up: west along the road, then a 40-stud
	turn into the lot, where the carry counts as home. homeDist is what is left
	of it, which is exactly what ChaseCamClient computes from the plot pivot. ]]
local route = { { D, 0 }, { 0, 0 }, { 0, -40 } }
local px, pz, seg = D, 0, 2
local startDelay = 0.4 + rnd() * 0.3
local lastBoost, pendingBoost = nil, nil
local h = R.newHunter(D + R.START_BEHIND, 0, 0, 0)
local lastPhase = "chase"
local jitter, jitterAt = 1, 0

local dir, cuts, t = {}, {}, 0
local home, arrived = nil, nil

while t < 90 do
	t += DT
	local vx, vz, speed = 0, 0, 0
	if pendingBoost and t >= pendingBoost then
		if R.boostReady(lastBoost, t) then lastBoost = t end
		pendingBoost = nil
	end
	if t >= startDelay then
		local tx, tz = route[seg][1], route[seg][2]
		local dx, dz = tx - px, tz - pz
		local dl = math.sqrt(dx * dx + dz * dz)
		if t >= jitterAt then
			jitter, jitterAt = 0.97 + rnd() * 0.06, t + 1
		end
		speed = SPEED * prof.weave * jitter + R.boostAdd(lastBoost, t)
		if dl <= speed * DT then
			px, pz = tx, tz
			if seg == #route then
				arrived = t
				break
			end
			seg += 1
		else
			vx, vz = dx / dl * speed, dz / dl * speed
			px, pz = px + vx * DT, pz + vz * DT
		end
	end

	local phase, dist = R.step(cfg, h, px, pz, vx, vz, SPEED, DT, t)
	if dist <= R.CATCH then
		arrived = -t
		break
	end
	if phase == "windup" and lastPhase ~= "windup" and dist < 20
		and not pendingBoost and rnd() < prof.boostChance then
		pendingBoost = t + prof.react
	end
	lastPhase = phase

	-- what is left of the route: the second of the chase's two numbers
	home = 0
	local cx, cz = px, pz
	for i = seg, #route do
		home += math.sqrt((route[i][1] - cx) ^ 2 + (route[i][2] - cz) ^ 2)
		cx, cz = route[i][1], route[i][2]
	end

	local shot, cause, cut = C.direct(dir, {
		t = t,
		dt = DT,
		dist = dist,
		windup = phase == "windup",
		lunging = phase == "lunge",
		homeDist = home,
		speed = speed,
		carrySpeed = SPEED,
	})
	if cut then
		table.insert(cuts, {
			t = t, shot = shot, cause = cause, dist = dist, home = home,
			trend = dir.trend or 0,
		})
	end
end

print(("%s hunter, %s player, %d studs to carry\n"):format(tier:upper(), skill, D))
print("  time   gap  home   trend  shot       because")
print("  " .. string.rep("-", 74))
local prev = 0
for _, c in ipairs(cuts) do
	print(("%6.2f %5.1f %5.0f  %+6.2f  %-9s  %s"):format(
		c.t, c.dist, c.home, c.trend, c.shot, c.cause))
	prev = c.t
end
local secs = arrived and math.abs(arrived) or 90
print(("\n  %d cuts in %.1f s = one every %.1f s.  %s"):format(
	#cuts, secs, secs / math.max(#cuts, 1),
	arrived and (arrived > 0 and "Got home." or "CAUGHT.") or "ran out of time."))
print(("  longest single shot: %.1f s"):format(
	(function()
		local worst, last = 0, 0
		for _, c in ipairs(cuts) do
			worst = math.max(worst, c.t - last)
			last = c.t
		end
		return math.max(worst, secs - prev)
	end)()))
