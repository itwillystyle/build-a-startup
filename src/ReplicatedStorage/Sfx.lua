--[[
	Sfx -- every sound id in the game, in one place.

	WHY A TABLE AND NOT LITERALS. Sound ids were scattered as bare strings
	across eight files, each with a comment naming the recording. That is fine
	until you want to know what the game sounds like, or swap a sound, or check
	that an id still loads -- and a dead audio id is SILENT, not an error, so a
	broken sound is invisible until someone notices the quiet.

	EVERY ID HERE IS PRO SOUND EFFECTS, Roblox's licensed library: free,
	pre-moderated, no upload and no moderation queue. Nothing in this file is
	owned by one account, which matters because the game's meshes and
	animations already are.

	All 15 new ids were load-checked before they were wired (TimeLength > 0),
	which is the only honest test -- ContentProvider reports success for assets
	that never play.
]]

local Sfx = {}

Sfx.ID = {
	-- vehicles
	engineLow = 9119386548,     -- Spacecraft Engine Idle Constant Mild Roar 1, 36.0s
	engineDeep = 9119386571,    -- Spacecraft Engine Idle Constant Mild Roar 2, 63.7s
	engineRumble = 9118747824,  -- Rumble Constant Roar Energy Building 1, 27.0s
	whoosh = 9114545105,        -- Futuristic Vehicle Accelerating Pass By 1, 10.2s
	rev = 9114833082,           -- Hot Rod Fast Maneuvers 2, 1.2s
	horn = 9114402619,          -- Ferrari 308 Dual Air Horns 9, 1.8s
	carDoor = 9113204879,       -- Audi Car Door Movement Opening Closing 1, 0.6s
	tyres = 9112887000,         -- Tires Constant On Bridge 1, 27.0s
	skid = 9120399077,          -- Vehicle Skids Long Heavy Tire Squeal 3 (already in use)

	-- rooms
	office = 9112838161,        -- Office Hallway Ambience 1, 56.4s
	studio = 9125716185,        -- Office Ambience Interior Library Reference D, 39.2s
	cafe = 9112745712,          -- Bar Crowd Loud Bar Walla 1, 36.0s
	servers = 9112812234,       -- Landing Craft Interior 2, 36.0s -- a machine-room hum
	crowd = 9112767169,         -- Crowd Walla 1, 36.0s

	-- objects
	keyboard = 9113874782,      -- Computer Keyboard 1, 0.25s
	keyTap = 9113145647,        -- Apple Keyboard 72, 0.40s
}

function Sfx.url(key)
	local id = Sfx.ID[key]
	return id and ("rbxassetid://" .. id) or nil
end

--[[ THE CAR TIERS.

	He asked for the cheap car and the expensive car to sound different, and
	the licensed library does not contain six separate car recordings -- it has
	a handful of constant engine tones and some one-shots. So the tier is built
	the way games actually build it: one base loop, shifted in pitch and
	weight, plus a second high "whine" layer that only the fast cars get, plus
	a rev bark on hard acceleration.

	Reading down the table you can hear the ladder: the hatchback is a thin
	high hum with no whine at all; the hypercar is a deep base, a loud whine
	and a whoosh when the boost fires.

	  base    which loop
	  pitch   playback speed at rest; speed adds to it while driving
	  vol     how loud the base sits
	  whine   volume of the high layer, 0 = none
	  wpitch  playback speed of that layer
	  bark    a one-shot on hard acceleration, nil for the quiet cars
]]
Sfx.CAR = {
	hatch = { base = "engineLow", pitch = 0.70, vol = 0.16, whine = 0.00, wpitch = 1.00, bark = nil },
	sedan = { base = "engineLow", pitch = 0.62, vol = 0.20, whine = 0.00, wpitch = 1.00, bark = nil },
	suv = { base = "engineDeep", pitch = 0.52, vol = 0.26, whine = 0.05, wpitch = 1.35, bark = nil },
	sports = { base = "engineDeep", pitch = 0.58, vol = 0.28, whine = 0.14, wpitch = 1.70, bark = "rev" },
	racer = { base = "engineRumble", pitch = 0.64, vol = 0.32, whine = 0.20, wpitch = 1.95, bark = "rev" },
	hyper = { base = "engineRumble", pitch = 0.50, vol = 0.36, whine = 0.26, wpitch = 2.20, bark = "whoosh" },
}

function Sfx.car(id)
	return Sfx.CAR[id or ""] or Sfx.CAR.hatch
end

--[[ Which room ambience a wafer storey gets. The dept is already a choice the
	player makes on every level, so the building sounds like what they built:
	a floor of engineers murmurs, a server floor hums, the cafe has a room
	full of people in it. ]]
Sfx.ROOM = {
	eng = { key = "office", volume = 0.14, pitch = 1.0 },
	labs = { key = "office", volume = 0.11, pitch = 0.92 },
	studio = { key = "studio", volume = 0.12, pitch = 1.0 },
	cafe = { key = "cafe", volume = 0.13, pitch = 0.95 },
	servers = { key = "servers", volume = 0.16, pitch = 1.15 },
	lobby = { key = "crowd", volume = 0.09, pitch = 1.0 },
}

--[[ A looping positional emitter. Defaults are tuned for a room: audible
	inside and gone a few studs past the glass, so walking in and out of a
	building is something you can hear. ]]
function Sfx.emitter(parent, key, opts)
	opts = opts or {}
	local url = Sfx.url(key)
	if not url or not parent then return nil end
	local s = Instance.new("Sound")
	s.Name = opts.name or ("Amb_" .. key)
	s.SoundId = url
	s.Looped = true
	s.Volume = opts.volume or 0.12
	s.PlaybackSpeed = opts.pitch or 1
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = opts.min or 12
	s.RollOffMaxDistance = opts.max or 70
	s.Parent = parent
	s.TimePosition = opts.offset or 0
	s:Play()
	return s
end

-- a one-shot at a point, cleaned up after itself
function Sfx.play(parent, key, opts)
	opts = opts or {}
	local url = Sfx.url(key)
	if not url or not parent then return nil end
	local s = Instance.new("Sound")
	s.SoundId = url
	s.Volume = opts.volume or 0.5
	s.PlaybackSpeed = opts.pitch or 1
	s.RollOffMaxDistance = opts.max or 90
	s.Parent = parent
	s:Play()
	task.delay(math.max(opts.life or 6, 1), function()
		if s then s:Destroy() end
	end)
	return s
end

return Sfx
