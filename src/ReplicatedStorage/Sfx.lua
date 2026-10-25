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

	-- clients
	-- 24 Oct: the client timer's tick in the last 8 s (ClientTimerClient). No tick recording was
	-- uploaded (no asset uploads on this pass), so it REUSES keyTap's id, the closest soft short
	-- click in the library; the last three ticks play it higher. Swap the id here for a real tick.
	clientTick = 9113145647,    -- = keyTap (Apple Keyboard 72, 0.40s)

	-- P-5 (25 Oct): Bob's cutscenes (BobSceneClient plays them at BobScript's cues). Creator Store
	-- audio only (spec 4). Pro Sound Effects / APM are Roblox's licensed libraries; the two marked
	-- "Creator Store upload" are free public uploads (no partner library had a boing or coins).
	bobLaugh = 9116452672,      -- Pro Sound Effects, "Male Laugh 3 (SFX)", 3.0s
	boing = 2772396665,         -- Creator Store upload (Dizzota), "Cartoon Jump Sound [HQ] - BOING"
	thud = 9113480917,          -- Pro Sound Effects, "Body Fall Thud 1 (SFX)", 0.5s
	money = 1319346243,         -- Creator Store upload (codes4breakfast), "Money, Coins, Drop In Cash Register"
	victory = 115889148511042,  -- APM, "To the Victor (Sting)"

	-- 25 Oct (Luke: "add the sounds"), redone the same day ("sloppy and very general": a bike horn for
	-- the gasp, a synth boink for "huh?", a library desk with conveyor clunks for the office, a disco
	-- stab for the cliffhanger). All Pro Sound Effects (PSE) or APM, each picked by role and then
	-- MEASURED from its file (BobScript.SOUND has where each starts, how long, how loud)
	bobMusic = 9045130736,      -- APM, Red Handed - 15, 17s: mischievous, sneaky pizzicato and a funky beat
	bobOffice = 9112744171,     -- PSE, Bank Ambience 1, 36s loop: carpet, voices, printer, typing, distant phones
	bobStreet = 9112874053,     -- PSE, Small Town Ambience 1, 36s loop (birds, light cars)
	bobRain = 9118033254,       -- PSE, Rain On Umbrella Small Needle Drops 1, 62s: close patter, not a room's drizzle
	bobDizzy = 9116394756,      -- PSE, Magic Glows Soft Clusters Of Chiming Hits 3, 3.9s (seeing stars)
	bobPop = 9119669618,        -- PSE, Suction Pop 6 (toy pop), 0.5s: a bubble appearing
	bobWahA = 1840568121,       -- APM, Trumpet Wah-Wah (A): the talking, muted trumpet (Charlie Brown's grown-ups)
	bobWahN = 1840568386,       -- APM, Trumpet Wah-Wah (N)
	bobWahQ = 1840568433,       -- APM, Trumpet Wah-Wah (Q)
	bobWahS = 1840568564,       -- APM, Trumpet Wah-Wah (S)
	bobTrumpetTalk = 1841456899, -- APM, Trumpet Talk: three trumpet wah-wah links (KPM, MUSIC FOR COMEDY)
	bobLaughBig = 9116452512,   -- PSE, Male Laugh 1, 2.5s: the deepest of the library's laughs (Bob)
	bobChuckleDeep = 9116452741, -- PSE, Male Laugh Reaction 1: closed-mouth laughs (Bob, at you)
	bobInvLaughA = 9116452494,  -- PSE, Male Laugh 2 (an investor)
	bobInvLaughB = 9116452853,  -- PSE, Male Laugh Reaction 3 (the other)
	bobInvLaughC = 9116455856,  -- PSE, Males Laughing Hooting Cracking Up 1
	bobHuh = 9119198150,        -- PSE, Slide Whistle 6: a slide UP, a cartoon "huh?"
	bobWhoosh = 9126047581,     -- PSE, Synth Air Whoosh Cheesy Karate Style Swishes 13, 0.4s
	bobKick = 9113564643,       -- PSE, Boxing Hits 1: one hard whump (the old one was a montage of hits)
	bobFly = 9119198140,        -- PSE, Slide Whistle 4 (classic cartoon riffs), 1.4s: tumbling through the air
	bobBoing = 9113854388,      -- PSE, Comic Boinks 3 (springy cartoon), 1.0s: licensed, replaces the upload
	bobDoorSlam = 9114153398,   -- PSE, Door Slams 7, 1.2s
	bobDoorBreak = 9113647302,  -- PSE, Bust Door Open 3, 2.1s: the door kicked in
	bobSad = 1842248431,        -- APM, Linking Trombone (1), 3s: descending sad trombone
	bobTbc = 1842342980,        -- APM, Shock Horror (c), "horrible discovery", 2s: DUN DUN DUNNN
	bobShock = 1841061158,      -- APM, Shock Horror (A), "melodramatic exclamation" (KPM, CLASSIC COMEDY)
	bobLaptop = 9113140784,     -- PSE, Apple Keyboard 4, 0.3s
	bobRiser = 9120733055,      -- PSE, Whoosh Rising Swish Airy Various Pitches 1, 1.7s: the line shooting up
	bobDing = 9126073001,       -- PSE, Synth Sparkle Tone High Pitch Bell Tone Ding 4, 1.2s: +312%
	bobScratch = 9118090423,    -- PSE, Record Scratch Variety Pack 4, 0.9s: everything stops
	bobCrickets = 9112764546,   -- PSE, Crickets Night 1, 36s loop (a second of it)
	bobBills = 9113726379,      -- PSE, Cash Drop 1, 1.3s
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
