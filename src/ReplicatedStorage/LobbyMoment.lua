--[[ LobbyMoment (15 Oct 2026, HQ project #1 part 1c): the garage-to-lobby moment's timeline. Pure.
	Spec: silicon-startup/docs/superpowers/specs/2026-10-15-hq-garage-1c-design.md. The server builds
	the real lobby at once; LobbyMomentClient plays this on the owner's screen and snaps every part
	back to where the server has it. Positions are plot space: x across, y up, z toward the street. ]]
local LobbyMoment = {}

LobbyMoment.TOTAL = 4.4
LobbyMoment.SKIP_FADE = 0.3
LobbyMoment.RISE = 8     -- studs a lobby group rises from
LobbyMoment.LIFT = 6     -- studs the garage's roof and props lift as they fade

-- each group moves from `from` to `to`; the scaffold also leaves (outFrom to outTo)
-- look review (15 Oct): the garage waits for the wide shot (Cine lands it at about 1.06 s) and falls
-- with an ease-in; everything after it moves on ~0.25 s
LobbyMoment.STEPS = {
	{ group = "scaffold", from = 0.0, to = 0.6, outFrom = 2.85, outTo = 3.3 },
	{ group = "garage", from = 0.95, to = 1.6, easeIn = true },
	{ group = "columns", from = 1.6, to = 2.1 },
	{ group = "glass", from = 2.0, to = 2.5 },
	{ group = "roof", from = 2.4, to = 2.7 },
	{ group = "canopy", from = 2.8, to = 3.15 },
}

-- existing UIKit.SOUNDS keys: a thunk as it starts and as the garage lands, a tick per step, the sting
LobbyMoment.SOUNDS = {
	{ t = 0.0, key = "thunk", pitch = 0.7, volume = 0.35 },
	{ t = 1.6, key = "thunk", pitch = 0.9, volume = 0.55 },
	{ t = 2.1, key = "tap", pitch = 1.2, volume = 0.5 },
	{ t = 2.5, key = "tap", pitch = 1.5, volume = 0.55 },
	{ t = 2.7, key = "levelup", pitch = 1.0, volume = 0.8 },
}

-- the camera (Cine shots), by when each should REALLY arrive (seconds into the moment): a wide shot that
-- holds past the roof's sting, a low look-up at the glass, then back to the player. Cine eases the whole
-- flight, so shotTimes() converts these into Cine's own times (look review, 15 Oct: planned at 0.6 s,
-- the wide shot landed at 1.06; the look-up left before the roof landed).
LobbyMoment.SHOTS = {
	{ at = "start", arrive = 0 },
	-- close on the garage while it falls (look review, 15 Oct: from the wide shot it was a small box
	-- half hidden by the floating sign); then the wide shot for the build and the roof's sting
	{ role = "garage", pos = { -30, 22, 45 }, look = { 0, 6, -4 }, arrive = 0.9 },
	{ role = "garage", pos = { -26, 20, 40 }, look = { 0, 6, -4 }, arrive = 1.7 },
	{ role = "wide", pos = { -40, 38, 100 }, look = { 0, 9, 10 }, arrive = 2.3 },
	{ role = "wide", pos = { -34, 34, 92 }, look = { 0, 10, 10 }, arrive = 2.95 },
	-- the look-up: low (Cine's curve dips below a shot; at 2 studs it went into the ground) and back far
	-- enough that the roofline fits (look review: at 22 studs off the front it clipped a prop)
	{ role = "lookup", pos = { 24, 7, 96 }, look = { -2, 18, 48 }, arrive = 3.45 },
	{ role = "lookup", pos = { 20, 7.5, 90 }, look = { -2, 19, 48 }, arrive = 3.85 },
	{ at = "player", arrive = 4.4 },
}

-- Cine.play's whole-flight easing (Cine.lua, the `e` in its loop): real time -> the time on its shot list
function LobbyMoment.cineTime(realT, total)
	total = total or LobbyMoment.TOTAL
	local raw = math.clamp(realT / total, 0, 1)
	local e = raw < 0.5 and (4 * raw ^ 3) * 0.5 + raw * 0.5 or (1 - ((-2 * raw + 2) ^ 3) / 2) * 0.5 + raw * 0.5
	return e * total
end

-- each shot's `t` for Cine.play (seconds from the shot before, on Cine's eased clock)
function LobbyMoment.shotTimes()
	local out, prev = {}, 0
	for i, s in ipairs(LobbyMoment.SHOTS) do
		local c = LobbyMoment.cineTime(s.arrive)
		out[i] = (i == 1) and 0 or (c - prev)
		prev = c
	end
	return out
end

-- back-out easing: 0 at 0, 1 at 1, about 5% past 1 on the way (each step "lands")
function LobbyMoment.ease(u)
	if u <= 0 then return 0 end   -- exact ends (the formula gives -2e-16 at 0)
	if u >= 1 then return 1 end
	local c1 = 1.2
	local c3 = c1 + 1
	local v = u - 1
	return 1 + c3 * v * v * v + c1 * v * v
end

local function step(group)
	for _, s in ipairs(LobbyMoment.STEPS) do if s.group == group then return s end end
	return nil
end

-- how far a group is at time t: 0 = not there yet (the garage: still standing), 1 = in place (the
-- garage: gone). The scaffold goes up and comes down again, so it ends at 0.
function LobbyMoment.at(group, t)
	local s = step(group)
	if not s then return 1 end
	local p
	if t <= s.from then p = 0
	elseif t >= s.to then p = 1
	else
		local u = (t - s.from) / (s.to - s.from)
		p = s.easeIn and u * u or LobbyMoment.ease(u)   -- easeIn: falls, slow then faster
	end
	if s.outFrom and t > s.outFrom then
		p = 1 - math.clamp((t - s.outFrom) / (s.outTo - s.outFrom), 0, 1)
	end
	return p
end

local GROUP = { Column = "columns", RoofBand = "roof", Ceiling = "roof", LobbyCanopy = "canopy", Floor = "floor", Deck = "floor" }
function LobbyMoment.groupOf(name)
	return GROUP[name] or (string.sub(name, 1, 4) == "Sign" and "canopy") or "glass"
end

-- what the client copies of the garage for the fold: everything the server stashes, except the floor
-- (it stays where it is: copied, it flickered on the lobby floor and rose through the desk; final review I3)
-- 22 Oct (art pass 1, final review): the oak FloorBoards (inside Dressing) are a floor too; the client
-- checks every descendant of the copy against this, not only the garage's direct children
local COPY_SKIP = { GarageFloor = true, FloorBoards = true }
function LobbyMoment.inCopy(name) return not COPY_SKIP[name] end

-- which way a garage part folds: a wall on a side folds out on that side; the roof, anything that
-- spans the whole garage (the shell mesh) and anything low (boxes, props) lifts away and fades.
-- x, z: the part's centre from the garage's centre; sx, sy, sz: its size; hw, hd: the garage's half size
function LobbyMoment.foldSide(x, z, sx, sy, sz, hw, hd)
	if sy < 3 then return "lift" end
	-- the garage's look is one shell mesh over the whole garage: it collapses flat to the floor (lifting
	-- it away read as "gone", not as a fold: look review, 15 Oct)
	if sx >= hw * 1.2 and sz >= hd * 1.2 then return "squash" end
	if math.abs(x) >= hw - 1.5 and sz > sx then return x > 0 and "px" or "nx" end
	if math.abs(z) >= hd - 1.5 and sx >= sz then return z > 0 and "pz" or "nz" end
	return "lift"
end

return LobbyMoment
