--[[ ChaseRules: the headhunter chase, as pure functions (v4.3).

No services, no Instances (plain x/z numbers): TalentDrop runs it every
server frame, and tests/offline/chase.spec.luau runs the SAME code against a
human-like player (tests/offline/chase_model.luau), so the escape rates are
measured, not guessed. `lune run tools/chase_sim` prints the table.

WHY (his 29 Sep verdict: "the chase should be a lot more fearful... it feels
too easy"). Measured on the old rules: the hunter AVERAGED 11.6 / 12.7 / 13.9
studs/s (SKILLED / STAR / GENIUS) against a 16-20 scooter, chased where you
WERE, came alone and started 30 studs back. In the simulation a player who
kept moving escaped 100% of the time, a careless one 95-98%.

A flat "make it faster" failed in the simulation too: every speed that
threatened a good player caught a casual one 100% of the time. So the new
hunter works a TENSION BAND:
  * far behind (> FAR studs): it sprints to close the gap (faster than you)
  * in the band: it jogs a little slower than you, so it hangs right behind
  * within LUNGE_RANGE: it crouches (the tell, 0.5 s), then LUNGES
    (faster than you, 0.8 s). Miss the tell or stop, and it has you.
  * it aims where you are GOING (lead pursuit), so turns cost you
  * the daily VIP run sends TWO hunters, the second from across the road
  * BOOST (Shift / the button): +8 speed for 1 s, 5 s cooldown. Boost in the
    crouch and the lunge misses: the skill that turns fear into a close call
Measured in the simulation (2,000 seeded runs per row, tools/chase_sim):
  a new player who holds forward and never boosts escapes ~99% / ~86% / ~33%
  (SKILLED / STAR / GENIUS); a player who boosts on the tell escapes 99-100%;
  freezing for 1.5 s with it behind you, or standing 3 s, gets you caught.
  GENIUS keeps it within 12 studs for ~39% of the run: that is the fear.
The old hunter: ~100% for everyone, and it was almost never within 12 studs.

v4.4 (8 Oct, his recording: "if you just go in a straight line, the thing cannot
catch you ... you just spam the shift"). Measured (tools/chase_threat): holding W
perfectly escaped 100% on every tier and scooter, BOOST-spamming 100%, and steering
on the tell was PUNISHED (genius 11%). Three causes, three changes:
  * speeds scaled to the tier's reference scooter, not the one you ride, so at HQ 4
    you out-rode the genius. Sprint and stalk now scale to the scooter you RIDE
    (never below the tier's); the lunge stays tier-scaled, so upgrades still help.
  * it hovered at FAR (20), outside lunge range (13): a dead band, no lunges ever.
    Now it STALKS inside the band, a touch faster than you, into range.
  * the lunge homed in on you, so only BOOST could beat it. Now the hunter COMMITS
    when it crouches: it picks the spot you will be at, and lunges at that spot.
    The crouch says "it has picked its line"; get off the line (steer) or outrun it
    (BOOST). Holding a straight line is exactly what it is aiming at. ]]

local C = {}

C.CATCH = 4.5            -- studs: caught
C.NEAR = 8               -- studs: a close call if you get away after this
C.FAR = 20               -- beyond this it sprints to catch up
C.LUNGE_RANGE = 14       -- it only lunges from this close
C.WINDUP = 0.5           -- the crouch before a lunge (the tell): the line is picked here
C.LUNGE_TIME = 1.0       -- the lunge itself, straight down the picked line
C.LUNGE_EVERY = 3.2      -- at most one lunge per this many seconds (a tier may set its own `every`)
C.FIRST_GRACE = 2.0      -- no lunge in the first seconds of a chase: let them get moving
C.LEAD_MAX = 0.8         -- lead pursuit looks at most this far ahead (s)
--[[ v4.4 fairness: only a LUNGE can catch you. Between lunges it never comes
	closer than this, so every catch had a tell in front of it. (The first v4.4
	pass caught 354 of 400 players who dodged correctly -- in plain pursuit,
	right after the dodge, with no crouch.) ]]
C.HOLD = 7
-- the lunge ends AT the spot it picked (plus a stride), then it stumbles: a miss
-- is visible, and getting off the line is a real escape (a 1 s lunge that kept
-- going swept the whole road ahead, and caught 311 of 400 correct dodges)
C.OVERSHOOT = 2
--[[ THE HOME STRETCH: inside this many studs of your lot it starts no new lunge.
	Measured: with lunges allowed everywhere, 389 of 400 SKILLED novices were caught
	at the last corner into the lot, where it cuts the corner; on the straight road
	it never got a lunge off at all. The danger belongs on the open road, and the
	door is the relief (the camera's homerun shot already says so). Needs
	cfg.homeDist(x, z) -> studs to the edge of your lot; without it there is no
	home stretch. ]]
C.HOME_SAFE = 45
C.RECOVER = 0.4
C.START_BEHIND = 22      -- hunter 1 starts this far behind the pickup
C.SECOND_DELAY = 3       -- hunter 2 (GENIUS / VIP) joins after this ...
C.SECOND_SIDE = 40       -- ... from this far across the road
C.BOOST = { add = 8, time = 1.0, cooldown = 5 }

-- speeds as multiples of the tier's REFERENCE speed: the scooter you have the
-- day the tier unlocks (SKILLED at HQ 1 = 16, STAR at HQ 2 = 17, GENIUS at HQ 3
-- = 18). A faster scooter later (HQ levels, an Energy Drink) is a real edge.
C.TIERS = {
	-- tuned in the simulation (tools/chase_sim): see the header for what each row does
	-- stalk: its speed inside the band, as a multiple of YOUR scooter (see v4.4)
	-- v4.4 roles (tools/chase_threat): SKILLED teaches the tell and rarely catches;
	-- STAR punishes a straight line; GENIUS wants nearly every tell read
	skilled = { ref = 16, sprint = 1.15, stalk = 1.05, jog = 0.94, lunge = 1.10, range = 8, every = 7.0, hunters = 1 },
	star = { ref = 17, sprint = 1.20, stalk = 1.02, jog = 0.97, lunge = 1.50, range = 10, every = 5.5, hunters = 1 },
	genius = { ref = 18, sprint = 1.25, stalk = 1.10, jog = 0.97, lunge = 1.90, range = 13, every = 5.0, hunters = 1 },
}
C.VIP_HUNTERS = 2
C.SECOND = { jog = 0.86, lunge = 1.35 }   -- the second VIP hunter is a junior: it herds, the first one hunts

-- vip: the daily VIP run is meant to stay the hardest run, so its hunters scale
-- to the scooter you ride TODAY (carrySpeed); street tiers you outgrow
function C.config(tierId, vip, carrySpeed)
	local t = C.TIERS[tierId] or C.TIERS.skilled
	return { ref = (vip and carrySpeed) or t.ref, sprint = t.sprint, stalk = t.stalk or t.jog, jog = t.jog, lunge = t.lunge, range = t.range or C.LUNGE_RANGE, every = t.every or C.LUNGE_EVERY, lead = C.LEAD_MAX,
		hunters = vip and math.max(t.hunters, C.VIP_HUNTERS) or t.hunters }
end

-- a hunter's state (plain table): position, and its lunge timer
function C.newHunter(x, z, t, stagger, second)
	return { x = x, z = z, phase = "chase", phaseEnd = 0, nextLunge = t + (stagger or 0) + C.FIRST_GRACE, second = second or nil }
end

--[[ Where a lunge at `speed` meets a player who holds their course: the player is
	at (rx, rz) relative to the hunter when the lunge starts, moving (vx, vz). Solve
	|r + v tau| = speed * tau for the first tau > 0; capped at `maxT` (beyond reach,
	it aims at where you will be when it runs out). Returns the aim point, relative. ]]
function C.intercept(rx, rz, vx, vz, speed, maxT)
	local a = vx * vx + vz * vz - speed * speed
	local b = 2 * (rx * vx + rz * vz)
	local c = rx * rx + rz * rz
	local tau
	if math.abs(a) < 1e-9 then
		tau = b < 0 and -c / b or maxT
	else
		local disc = b * b - 4 * a * c
		if disc < 0 then
			tau = maxT
		else
			local q = math.sqrt(disc)
			local t1, t2 = (-b - q) / (2 * a), (-b + q) / (2 * a)
			tau = math.huge
			if t1 > 0 then tau = t1 end
			if t2 > 0 and t2 < tau then tau = t2 end
			if tau == math.huge then tau = maxT end
		end
	end
	tau = math.min(tau, maxT)
	return rx + vx * tau, rz + vz * tau
end

-- one step. h is mutated; returns the phase ("chase" | "windup" | "lunge" | "recover")
-- and the distance to the player before the step. Speeds come from the tier's
-- reference speed (cfg.ref); pspeed is only the fallback for a config without one
function C.step(cfg, h, px, pz, vx, vz, pspeed, dt, t)
	local ref = cfg.ref or pspeed
	-- the scooter you RIDE, never below the tier's (v4.4): sprint and stalk follow it
	--[[ ...and the speed you are going RIGHT NOW, BOOST included: a boost away from
		a hunter that is not lunging buys nothing, because it matches you. BOOST is a
		dodge, not a lead. (Measured before this: pressing it whenever it was ready
		escaped 100% of genius runs.) ]]
	local ride = math.max(ref, pspeed or ref, math.sqrt(vx * vx + vz * vz))
	local dx, dz = px - h.x, pz - h.z
	local dist = math.sqrt(dx * dx + dz * dz)
	local lungeSpeed = ref * (h.second and C.SECOND.lunge or cfg.lunge)
	-- the lunge cycle
	if h.phase == "windup" and t >= h.phaseEnd then
		h.phase, h.phaseEnd = "lunge", t + C.LUNGE_TIME
	elseif h.phase == "lunge" and (t >= h.phaseEnd or (h.left and h.left <= 0)) then
		h.phase, h.phaseEnd = "recover", t + C.RECOVER
		h.nextLunge = t + (cfg.every or C.LUNGE_EVERY)
	elseif h.phase == "recover" and t >= h.phaseEnd then
		h.phase = "chase"
	elseif h.phase == "chase" and dist <= (cfg.range or C.LUNGE_RANGE) and t >= h.nextLunge
		and not (cfg.homeDist and cfg.homeDist(px, pz) < C.HOME_SAFE) then
		h.phase, h.phaseEnd = "windup", t + C.WINDUP
		--[[ THE LINE IS PICKED HERE, at the start of the crouch: the spot you will be
			at if you hold your course, when the lunge would arrive. From now on it does
			not steer. The crouch is the player's 0.5 s to get off that line. ]]
		--[[ It PACES you through the crouch, along your line at your speed, so the
			gap at the lunge is the gap at the tell. (Standing still for the tell gave
			you 9.5 free studs, more than a 1 s lunge could ever close: measured,
			a perfect W-holder escaped 98% of genius runs.) ]]
		h.px, h.pz = vx, vz
		local ax, az = C.intercept(dx, dz, vx, vz, lungeSpeed, C.LUNGE_TIME)
		local al = math.sqrt(ax * ax + az * az)
		if al > 1e-6 then h.lx, h.lz = ax / al, az / al
		elseif dist > 1e-6 then h.lx, h.lz = dx / dist, dz / dist
		else h.lx, h.lz = 0, 1 end
		h.left = al + C.OVERSHOOT
	end
	if h.phase == "lunge" and h.lx then
		-- committed: straight down the picked line to the picked spot, no homing
		local mv = math.min(lungeSpeed * dt, math.max(0, h.left or 0))
		h.x, h.z = h.x + h.lx * mv, h.z + h.lz * mv
		h.left = (h.left or 0) - mv
		return h.phase, dist
	end
	if h.phase == "windup" and h.px then
		h.x, h.z = h.x + h.px * dt, h.z + h.pz * dt
		return h.phase, dist
	end
	local speed
	if h.phase == "windup" or h.phase == "recover" then speed = 0
	elseif dist > C.FAR then speed = ride * cfg.sprint
	elseif h.second then speed = ride * C.SECOND.jog
	elseif dist > (cfg.range or C.LUNGE_RANGE) then speed = ride * (cfg.stalk or cfg.jog)   -- closing into range
	else speed = ride * cfg.jog end
	if speed <= 0 or dist < 1e-6 then return h.phase, dist end
	-- lead pursuit: aim where the player will be when it gets there (capped)
	local lead = math.min(cfg.lead or 0, dist / speed)
	local ax, az = px + vx * lead - h.x, pz + vz * lead - h.z
	local al = math.sqrt(ax * ax + az * az)
	if al < 1e-6 then return h.phase, dist end
	local move = math.min(speed * dt, math.max(0, dist - C.HOLD))
	h.x, h.z = h.x + ax / al * move, h.z + az / al * move
	return h.phase, dist
end

-- BOOST: can the player boost now, and the speed it adds at time t
function C.boostReady(lastBoost, t)
	return lastBoost == nil or t - lastBoost >= C.BOOST.cooldown
end
function C.boostAdd(lastBoost, t)
	if lastBoost and t - lastBoost < C.BOOST.time then return C.BOOST.add end
	return 0
end

return C
