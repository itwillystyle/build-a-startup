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
LobbyMoment.STEPS = {
	{ group = "scaffold", from = 0.0, to = 0.6, outFrom = 2.6, outTo = 3.1 },
	{ group = "garage", from = 0.6, to = 1.2 },
	{ group = "columns", from = 1.2, to = 1.8 },
	{ group = "glass", from = 1.8, to = 2.4 },
	{ group = "roof", from = 2.2, to = 2.5 },
	{ group = "canopy", from = 2.6, to = 3.0 },
}

-- existing UIKit.SOUNDS keys: a thunk as it starts and as the garage lands, a tick per step, the sting
LobbyMoment.SOUNDS = {
	{ t = 0.0, key = "thunk", pitch = 0.7, volume = 0.35 },
	{ t = 1.2, key = "thunk", pitch = 0.9, volume = 0.55 },
	{ t = 1.8, key = "tap", pitch = 1.2, volume = 0.5 },
	{ t = 2.4, key = "tap", pitch = 1.5, volume = 0.55 },
	{ t = 2.5, key = "levelup", pitch = 1.0, volume = 0.8 },
}

-- the camera (Cine shots): from where it is, a wide shot that drifts (and holds as the roof lands),
-- a low look-up at the glass, then back to the player. t = seconds to reach that shot.
LobbyMoment.SHOTS = {
	{ at = "start", t = 0 },
	{ pos = { -40, 38, 100 }, look = { 0, 9, 10 }, t = 0.6 },
	{ pos = { -34, 34, 92 }, look = { 0, 10, 10 }, t = 2.05 },
	{ pos = { 22, 2, 88 }, look = { -4, 18, 30 }, t = 0.6 },
	{ pos = { 18, 2.5, 82 }, look = { -4, 19, 30 }, t = 0.35 },
	{ at = "player", t = 0.8 },
}

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
	else p = LobbyMoment.ease((t - s.from) / (s.to - s.from)) end
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
local COPY_SKIP = { GarageFloor = true }
function LobbyMoment.inCopy(name) return not COPY_SKIP[name] end

-- which way a garage part folds: a wall on a side folds out on that side; the roof, anything that
-- spans the whole garage (the shell mesh) and anything low (boxes, props) lifts away and fades.
-- x, z: the part's centre from the garage's centre; sx, sy, sz: its size; hw, hd: the garage's half size
function LobbyMoment.foldSide(x, z, sx, sy, sz, hw, hd)
	if sy < 3 or (sx >= hw * 1.2 and sz >= hd * 1.2) then return "lift" end
	if math.abs(x) >= hw - 1.5 and sz > sx then return x > 0 and "px" or "nx" end
	if math.abs(z) >= hd - 1.5 and sx >= sz then return z > 0 and "pz" or "nz" end
	return "lift"
end

return LobbyMoment
