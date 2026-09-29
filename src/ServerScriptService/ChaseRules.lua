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
The old hunter: ~100% for everyone, and it was almost never within 12 studs. ]]

local C = {}

C.CATCH = 4.5            -- studs: caught
C.NEAR = 8               -- studs: a close call if you get away after this
C.FAR = 20               -- beyond this it sprints to catch up
C.LUNGE_RANGE = 14       -- it only lunges from this close
C.WINDUP = 0.5           -- the crouch before a lunge (the tell)
C.LUNGE_TIME = 0.8       -- the lunge itself
C.LUNGE_EVERY = 3.2      -- at most one lunge per this many seconds
C.LEAD_MAX = 0.8         -- lead pursuit looks at most this far ahead (s)
C.START_BEHIND = 22      -- hunter 1 starts this far behind the pickup
C.SECOND_DELAY = 3       -- hunter 2 (GENIUS / VIP) joins after this ...
C.SECOND_SIDE = 40       -- ... from this far across the road
C.BOOST = { add = 8, time = 1.0, cooldown = 5 }

-- speeds as multiples of the tier's REFERENCE speed: the scooter you have the
-- day the tier unlocks (SKILLED at HQ 1 = 16, STAR at HQ 2 = 17, GENIUS at HQ 3
-- = 18). A faster scooter later (HQ levels, an Energy Drink) is a real edge.
C.TIERS = {
	-- tuned in the simulation (tools/chase_sim): see the header for what each row does
	skilled = { ref = 16, sprint = 1.15, jog = 0.94, lunge = 1.4, range = 13, hunters = 1 },
	star = { ref = 17, sprint = 1.20, jog = 0.97, lunge = 1.4, range = 16, hunters = 1 },
	genius = { ref = 18, sprint = 1.25, jog = 0.94, lunge = 1.6, range = 13, hunters = 1 },
}
C.VIP_HUNTERS = 2
C.SECOND = { jog = 0.86, lunge = 1.35 }   -- the second VIP hunter is a junior: it herds, the first one hunts

-- vip: the daily VIP run is meant to stay the hardest run, so its hunters scale
-- to the scooter you ride TODAY (carrySpeed); street tiers you outgrow
function C.config(tierId, vip, carrySpeed)
	local t = C.TIERS[tierId] or C.TIERS.skilled
	return { ref = (vip and carrySpeed) or t.ref, sprint = t.sprint, jog = t.jog, lunge = t.lunge, range = t.range or C.LUNGE_RANGE, lead = C.LEAD_MAX,
		hunters = vip and math.max(t.hunters, C.VIP_HUNTERS) or t.hunters }
end

-- a hunter's state (plain table): position, and its lunge timer
function C.newHunter(x, z, t, stagger, second)
	return { x = x, z = z, phase = "chase", phaseEnd = 0, nextLunge = t + (stagger or 0), second = second or nil }
end

-- one step. h is mutated; returns the phase ("chase" | "windup" | "lunge")
-- and the distance to the player before the step. Speeds come from the tier's
-- reference speed (cfg.ref); pspeed is only the fallback for a config without one
function C.step(cfg, h, px, pz, vx, vz, pspeed, dt, t)
	pspeed = cfg.ref or pspeed
	local dx, dz = px - h.x, pz - h.z
	local dist = math.sqrt(dx * dx + dz * dz)
	-- the lunge cycle
	if h.phase == "windup" and t >= h.phaseEnd then
		h.phase, h.phaseEnd = "lunge", t + C.LUNGE_TIME
	elseif h.phase == "lunge" and t >= h.phaseEnd then
		h.phase = "chase"
		h.nextLunge = t + C.LUNGE_EVERY
	elseif h.phase == "chase" and dist <= (cfg.range or C.LUNGE_RANGE) and t >= h.nextLunge then
		h.phase, h.phaseEnd = "windup", t + C.WINDUP
	end
	local speed
	if h.phase == "windup" then speed = 0
	elseif h.phase == "lunge" then speed = pspeed * (h.second and C.SECOND.lunge or cfg.lunge)
	elseif dist > C.FAR then speed = pspeed * cfg.sprint
	else speed = pspeed * (h.second and C.SECOND.jog or cfg.jog) end
	if speed <= 0 or dist < 1e-6 then return h.phase, dist end
	-- lead pursuit: aim where the player will be when it gets there (capped)
	local lead = math.min(cfg.lead or 0, dist / speed)
	local ax, az = px + vx * lead - h.x, pz + vz * lead - h.z
	local al = math.sqrt(ax * ax + az * az)
	if al < 1e-6 then return h.phase, dist end
	local move = math.min(speed * dt, math.max(0, dist - C.CATCH * 0.5))
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
