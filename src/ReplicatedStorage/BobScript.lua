--[[
	BobScript -- ReplicatedStorage ModuleScript. P-5, Bob the first boss investor (25 Oct 2026).

	Both of Bob's cutscenes as DATA, and a pure evaluator: BobScript.at(name, t, reduced)
	returns everything on screen at time t. BobSceneClient draws it every frame; the
	offline tests (tests/offline/bobscript.spec.luau) check it without Studio.

	  "intro"   option A "fast cuts" (Luke's pick from ui/storyboards/p5-bob): you ask Bob
	            for an offer, he and his investors laugh, he kicks you out of his door, you
	            walk home in the rain and vow at your laptop. New saves only. 16.2 s.
	  "payoff"  floor 13 (the HQ 4 stage): you kick his door down, pull an iPad with your
	            REVENUE on it from behind your back, he throws the money (x3) and you kick HIM
	            out. 17 s.

	Shot times come from the storyboard's cartoon.js. Spec:
	docs/superpowers/specs/2026-10-25-bob-first-boss-investor-design.md (3a, 3e).

	COORDINATES. Every position is relative to an ANCHOR the client resolves:
	  board   Bob's boardroom (the middle of the floor, facing the camera side)
	  door    just outside Bob's front door, on the sidewalk
	  street  the road beside his building
	  garage  the floor under your laptop (your plot)
	An anchor's -Z is "into the scene" (away from the camera), +X is screen-right, Y is
	up, in studs. An actor's rot is its yaw in degrees: 0 faces the camera (+Z), 90 faces
	+X (right), -90 faces -X. roll spins it around the camera's view axis (the flight).

	REDUCE MOTION (reduced = true): no shake, and a shot's camera holds at its first
	framing (no push, no follow). Hard cuts are not motion, so they stay.
]]

local BobScript = {}

BobScript.LINES = {
	offer = "Can I get an offer?",
	haOffer = "HA! An OFFER?",
	haha = "HAHAHA!",
	rue = "He will rue the day.",
	text = "...Ok. I may have been hasty. Come to my office.",
	task = "Go to Bob's office",
	youAgain = "You AGAIN?",                         -- 25 Oct (Luke): the payoff opens on Bob's sneer,
	myOffer = "I've got an offer for YOU.",         -- you turn his line round, they laugh, the iPad lands
	what = "W-WHAT?!",
	takeIt = "TAKE IT ALL!",   -- Luke 25 Oct: fewer words on screen (was "Take it! TAKE IT ALL!")
	laughing = "Who's laughing now?",   -- Luke 25 Oct: "PROVED WRONG!" read as out of place; a line he'd say
	toast = "SERIES A CLOSED · x3",
	taped = "Bob isn't taking meetings... yet.",
	trophy = "BOB'S TOOTHPICK",
}
local L = BobScript.LINES

--[[ SOUND (25 Oct, Luke: "add the sounds"; second pass the same day: "they sound very sloppy and
	very general"). Every sound the scenes use, by the name the data below uses:
	  { Sfx.ID key, at = s, len = s, gain = x }
	at    where the sound starts in its file. Library files open on dead air (the old laugh 0.5 s, the
	      door slam 0.44 s, the wah-wahs up to 1.2 s): played from 0 every hit landed late
	len   how long it plays from `at` (to its end, or to the end of the phrase it is cut to)
	gain  the trim that brings its loud part to -24 dB, so a cue's vol means the same for every
	      sound (they were 31 dB apart: the music at -12 dB, the door slam at -45). Capped at 8
	All three MEASURED from the files (Studio's cache, decoded, 25 Oct): segments over -32 dB of the
	peak, the loudness of the frames over -20 dB. Re-measure if an id changes.
	Three kinds of sound:
	  cues    one-shots: { t, name, vol?, dur?, pitch?, fade? } (dur: fade out over `fade` and stop)
	  beds    loops and the music: { name, t0, t1, vol, fin?, fout?, duck? } (duck: lower under talking)
	  voices  a bubble's sound: it pops in ("pop", a little higher or lower each time) and plays its
	          `voice` until it goes (a laugh may run on: `free`). Nobody says real words: everyone talks
	          in muted-trumpet wah-wah (the Charlie Brown grown-ups), each at their own pitch ]]
BobScript.SOUND = {
	-- the voices: APM "Trumpet Wah-Wah" (KPM, muted trumpet phrases) and "Trumpet Talk" (MUSIC FOR COMEDY)
	wahA = { "bobWahA", at = 0.94, len = 0.57, gain = 0.72 },     -- one short "wah"
	wahN = { "bobWahN", at = 0.90, len = 2.65, gain = 0.77 },     -- a level phrase
	wahQ = { "bobWahQ", at = 0.64, len = 2.52, gain = 0.9 },      -- a phrase that falls
	wahS = { "bobWahS", at = 1.94, len = 1.91, gain = 0.81 },     -- its second, level phrase
	trumpetTalk = { "bobTrumpetTalk", at = 6.18, len = 2.42, gain = 0.25 },   -- the bright middle link
	-- the laughs: one man each (the old investors' laugh was a reverberant crowd)
	laughBig = { "bobLaughBig", at = 0.14, len = 1.76, gain = 1.4 },          -- Bob: the deepest, 206 > 122 Hz
	laughBob = { "bobLaugh", at = 0.31, len = 1.8, gain = 1.82 },             -- Bob, still going
	chuckleDeep = { "bobChuckleDeep", at = 0.24, len = 2.29, gain = 2.54 },   -- Bob, closed-mouth, at you
	invLaughA = { "bobInvLaughA", at = 0.24, len = 1.07, gain = 1.32 },
	invLaughB = { "bobInvLaughB", at = 0.0, len = 1.0, gain = 1.35 },
	invLaughC = { "bobInvLaughC", at = 2.58, len = 2.11, gain = 2.14 },
	huh = { "bobHuh", at = 0.01, len = 1.03, gain = 2.69 },        -- a slide whistle going UP: "huh?"
	-- hits and gags
	pop = { "bobPop", at = 0, len = 0.32, gain = 3.27 },
	whoosh = { "bobWhoosh", at = 0, len = 0.27, gain = 5.31 },
	kick = { "bobKick", at = 0, len = 1.0, gain = 0.68 },
	fly = { "bobFly", at = 0, len = 1.32, gain = 3.89 },
	boing = { "bobBoing", at = 0.01, len = 0.7, gain = 1.1 },
	thud = { "thud", at = 0.10, len = 0.27, gain = 0.69 },
	doorSlam = { "bobDoorSlam", at = 0.40, len = 0.85, gain = 8 },
	doorBreak = { "bobDoorBreak", at = 0.28, len = 1.86, gain = 1.06 },
	laptop = { "bobLaptop", at = 0, len = 0.25, gain = 8 },
	riser = { "bobRiser", at = 0.02, len = 1.31, gain = 0.95 },
	ding = { "bobDing", at = 0.10, len = 1.06, gain = 1.97 },
	scratch = { "bobScratch", at = 0.28, len = 0.65, gain = 0.33 },
	money = { "money", at = 0.40, len = 0.96, gain = 2.85 },
	bills = { "bobBills", at = 0, len = 0.7, gain = 0.57 },
	-- stings
	sad = { "bobSad", at = 0.43, len = 3.16, gain = 0.51 },        -- the descending sad trombone
	tbc = { "bobTbc", at = 0.45, len = 1.98, gain = 0.7 },         -- "He will rue the day." DUN DUN DUNNN
	shock = { "bobShock", at = 0.24, len = 3.89, gain = 0.25 },    -- W-WHAT?!: a melodramatic orchestra stab
	victory = { "victory", at = 0.10, len = 6.76, gain = 0.33 },
	-- music and loops
	music = { "bobMusic", at = 0, len = 16.9, gain = 0.29 },
	officeAmb = { "bobOffice", at = 0, len = 36.0, gain = 8 },
	streetAmb = { "bobStreet", at = 0, len = 36.0, gain = 8 },
	rain = { "bobRain", at = 0, len = 61.6, gain = 6.38 },
	crickets = { "bobCrickets", at = 0, len = 36.0, gain = 8 },
	dizzy = { "bobDizzy", at = 0, len = 3.3, gain = 8 },
}
local DUCK = 0.45   -- the music under talking
local POP_PITCH = { 1, 1.08, 0.94, 1.12, 0.97, 1.05 }   -- every bubble's pop a little different

local V = Vector3.new

-- ------------------------------------------------------------------ easing
local function clamp01(x) return math.clamp(x, 0, 1) end
local EASE = {
	linear = function(x) return x end,
	out = function(x) return 1 - (1 - x) ^ 3 end,
	inout = function(x) return x < 0.5 and 4 * x ^ 3 or 1 - (-2 * x + 2) ^ 3 / 2 end,
	back = function(x) local c = 1.70158; return 1 + (c + 1) * (x - 1) ^ 3 + c * (x - 1) ^ 2 end,
}
local function pop(t, t0) return EASE.back(clamp01((t - t0) / 0.35)) end

--[[ A scene:
	length
	shots   { { t0, t1, anchor, from = {offset, look, fov, dist?}, to = {...}?, follow = actorId?,
	          zoom = s? (reach `to` in this many seconds, then hold: a snap zoom),
	          aim = "tablet"? (the client frames the iPad's screen from `dist` studs; offset/look are
	          the fallback when it is not out) } }
	moves   [actor] = { { t, anchor?, p?, r?, roll?, move? ("linear"|"out"|"arc"), h? } }
	looks   [actor] = { { t, pose?, face?, vis? } }
	bubbles { { actor, text, t0, t1 } }
	fx      { { text?, kind?, anchor, p, t0, t1, follow? } }
	vals    [name] = { { t, v } }  (linear between keys)
	shakes  { { t0, t1, amp } }
	cues    { { t, id } } ]]

-- live 25 Oct (Luke: "the room looks like a set"): the wide shot stood OUTSIDE the cut-away front
-- wall and saw the floor's edge, the grass and the tops of the walls. It stands inside now, against
-- the front wall (z 11.5), a wide lens that keeps the investor at the far end in frame.
local WIDE = { offset = V(0, 6.5, 10.9), look = V(0, 3, -3), fov = 58 }
local ONBOB = { offset = V(-7, 4.5, 10), look = V(-7, 4.2, 1), fov = 50 }
local OUTSIDE = { offset = V(6, 4, 16), look = V(6, 3, 0), fov = 60 }
-- where the boardroom cast stands: clear of the table (measured 25 Oct: it covers x -9.6..1.6,
-- z -8.1..-0.3 from the anchor; the short investor stood inside it, Bob's belly in its edge).
-- The tall investor stands at the table's far end, where Bob does not hide him from the wide shot
-- (and the short one out of the sightline from your shoulder to Bob's face, live 25 Oct)
local BOB_AT, INV1_AT, INV2_AT = V(-7, 0, 1), V(3.2, 0, -5), V(-3.6, 0, 2.6)
local INV1_ROT = 32   -- turned to you

local SCENES = {}

SCENES.intro = {
	length = 16.2,
	shots = {
		{ 0, 3.4, "board", from = WIDE, to = { offset = V(0.8, 6.3, 10.6), look = V(0.8, 3, -3), fov = 57 } },
		{ 3.4, 6.2, "board", from = ONBOB, to = { offset = V(-7, 4.5, 9), look = V(-7, 4.4, 1), fov = 50 } },
		{ 6.2, 9.0, "door", from = OUTSIDE },
		{ 9.0, 10.4, "street", from = { offset = V(1.5, 4.6, 12), look = V(1.5, 3.9, 0), fov = 60 }, follow = "hero" },   -- room for the rain cloud
		{ 10.4, 12.0, "garage", from = { offset = V(-3, 5, 15), look = V(-3, 3, 0), fov = 60 } },
		-- live 25 Oct: the vow fist sat under the top letterbox bar; aim higher, push in less
		{ 12.0, 16.2, "garage", from = { offset = V(0, 5, 13), look = V(-0.5, 4.4, 0), fov = 55 },
			to = { offset = V(-0.4, 5, 10), look = V(-0.8, 4.8, 0), fov = 55 } },
	},
	moves = {
		bob = {
			{ t = 0, anchor = "board", p = BOB_AT, r = 45 },
			{ t = 6.2, anchor = "door", p = V(0, 0, -1.5), r = 90 },
		},
		inv1 = { { t = 0, anchor = "board", p = INV1_AT, r = INV1_ROT } },
		inv2 = { { t = 0, anchor = "board", p = INV2_AT, r = 20 } },
		hero = {
			{ t = 0, anchor = "board", p = V(7, 0, 0), r = -60, roll = 0 },
			{ t = 6.3, anchor = "door", p = V(0.8, 1, 0), r = 90, roll = 0 },
			{ t = 7.25, p = V(11, 0, 3), roll = -450, move = "arc", h = 3.5 },
			{ t = 8.1, roll = -90 },
			{ t = 8.7, roll = 0, move = "out" },
			{ t = 9.0, anchor = "street", p = V(-4, 0, 0), r = 90 },
			{ t = 10.4, p = V(4, 0, 0), move = "linear" },
			{ t = 10.41, anchor = "garage", p = V(-9, 0, 0), r = 90 },
			-- live 25 Oct: he stood side-on inside the desk. The laptop faces the camera, so he stands
			-- on our side of the desk, turns to it, then turns round to us for the vow
			{ t = 12.0, p = V(-1.2, 0, 2.3), move = "linear" },
			{ t = 12.35, r = 180, move = "out" },
			{ t = 12.9, r = 180 },
			{ t = 13.2, r = 15, move = "out" },
		},
	},
	looks = {
		bob = {
			{ t = 0, pose = "stand", face = "smug", vis = true },
			{ t = 3.5, pose = "laugh", face = "laugh" },
			{ t = 6.2, pose = "kick" },
			{ t = 6.75, pose = "laugh" },
			{ t = 8.0, vis = false },
		},
		inv1 = { { t = 0, pose = "stand", face = "neutral", vis = true }, { t = 4.2, pose = "laugh", face = "laugh" }, { t = 6.2, vis = false } },
		inv2 = { { t = 0, pose = "stand", face = "neutral", vis = true }, { t = 4.2, pose = "laugh", face = "laugh" }, { t = 6.2, vis = false } },
		hero = {
			{ t = 0, pose = "stand", face = "hope", vis = true },
			{ t = 0.5, pose = "gesture" },
			{ t = 3.4, pose = "stand" },
			{ t = 3.6, face = "sad" },
			{ t = 6.3, pose = "fly", face = "shock" },
			{ t = 7.25, pose = "lie", face = "dizzy" },
			{ t = 8.1, pose = "sit" },
			{ t = 8.5, face = "sad" },
			{ t = 8.7, pose = "stand" },
			{ t = 9.0, pose = "walk" },
			{ t = 12.0, pose = "stand" },
			{ t = 13.0, face = "determined" },
			{ t = 13.2, pose = "gesture" },
		},
	},
	bubbles = {
		{ "hero", L.offer, 0.5, 3.4, voice = "wahN", pitch = 1.1 },   -- you: a little higher than Bob
		{ "bob", L.haOffer, 3.6, 6.2, voice = "laughBig", pitch = 0.9, vol = 0.65, free = true },   -- one bubble at a time: the investors laugh without one
		{ "hero", L.rue, 13.2, 16.21 },   -- (no voice: the DUN DUN DUNNN says it)
	},
	fx = {
		{ text = "BOING!", anchor = "door", p = V(10, 6.5, 3), t0 = 7.25, t1 = 8.25 },   -- above the landing, not on it
		{ kind = "cloud", follow = "hero", t0 = 9.0, t1 = 11.4 },
	},
	vals = {
		door = { { t = 0, v = 0 }, { t = 6.2, v = 0 }, { t = 6.3, v = 1 }, { t = 7.9, v = 1 }, { t = 8.1, v = 0 } },
		tape = { { t = 0, v = 1 } },   -- the intro is before the tape: Bob's door is open for business
		lid = { { t = 0, v = 0 }, { t = 12.2, v = 0 }, { t = 12.8, v = 1 } },
		glow = { { t = 0, v = 0 }, { t = 12.5, v = 0 }, { t = 13.1, v = 1 } },
		handoff = { { t = 0, v = 0 }, { t = 15.2, v = 0 }, { t = 15.8, v = 1 } },
	},
	shakes = { { 6.3, 6.8, 0.6 } },
	beds = {
		{ "music", 0.05, 13.25, 0.25, fin = 0.02, fout = 0.5, duck = true },   -- out for the vow's sting
		{ "officeAmb", 0, 6.2, 0.18 },     -- carpet, phones, a printer: an investor's office
		{ "streetAmb", 6.2, 9.0, 0.15 },
		{ "rain", 9.0, 11.4, 0.3 },        -- pattering on you, under your cloud
		{ "dizzy", 7.35, 8.5, 0.4 },       -- seeing stars on the pavement
	},
	cues = {
		-- Bob laughs from 3.5 to the kick; his investors join in, one man each, one after the other
		{ 4.2, "invLaughA", vol = 0.6, pitch = 1.05 },
		{ 4.9, "invLaughB", vol = 0.55, pitch = 0.95 },
		{ 5.45, "laughBob", vol = 0.7, pitch = 0.9, dur = 0.75, fade = 0.25 },
		{ 6.22, "whoosh", vol = 0.5 }, { 6.3, "kick", vol = 0.9 }, { 6.4, "fly", vol = 0.6 },
		{ 6.8, "chuckleDeep", vol = 0.55, dur = 1.15, fade = 0.3 },   -- still laughing at you from his door
		{ 7.25, "boing", vol = 0.8 }, { 7.3, "thud", vol = 0.95 },
		{ 7.95, "doorSlam", vol = 0.8 },
		{ 9.05, "sad", vol = 0.8 },
		{ 12.25, "laptop", vol = 0.4 },
		{ 13.25, "tbc", vol = 0.9 },       -- "He will rue the day." DUN DUN DUNNN
	},
}

SCENES.payoff = {
	length = 20.0,
	--[[ 25 Oct, Luke's second review. You SLAM his door down. "You AGAIN?" -- "I've come to make YOU
		an offer." They roar laughing; you calmly pull the iPad from behind your back; the line shoots up;
		the laughing dies (the back-to-earth beat, over your shoulder); then the snap zoom on "W-WHAT?!".
		The money, the kick out, "Who's laughing now?" ]]
	shots = {
		{ 0, 1.7, "door", from = { offset = V(5.5, 4.2, 14), look = V(1, 3.2, 0), fov = 58 } },
		{ 1.7, 3.7, "board", from = WIDE },
		{ 3.7, 5.6, "board", from = { offset = V(0, 6.2, 10.9), look = V(0, 3.5, -2), fov = 56 },
			to = { offset = V(0, 6, 10.4), look = V(0, 3.5, -2), fov = 55 } },
		{ 5.6, 6.8, "board", from = ONBOB, to = { offset = V(-7, 4.5, 9), look = V(-7, 4.4, 1), fov = 50 } },
		{ 6.8, 8.4, "board", from = { offset = V(2.5, 6, 10.5), look = V(1, 3.5, -2), fov = 56 },
			to = { offset = V(2.5, 5.8, 9.8), look = V(1, 3.5, -2), fov = 54 } },
		{ 8.4, 9.6, "board", aim = "tablet", from = { offset = V(2.7, 3.8, 2.6), look = V(5.7, 3.4, 1.5), fov = 38, dist = 5.4 },
			to = { offset = V(3.2, 3.75, 2.4), look = V(5.7, 3.4, 1.5), fov = 34, dist = 4.6 } },
		-- over your shoulder at Bob while his laugh dies
		-- (live 25 Oct: from lower down the short investor's hair hid Bob's mouth: high, looking down on him)
		{ 9.6, 11.0, "board", from = { offset = V(9.6, 6.8, -2.2), look = V(-7, 4.6, 1), fov = 30 },
			to = { offset = V(9.4, 6.7, -2.1), look = V(-7, 4.6, 1), fov = 27 } },
		{ 11.0, 13.2, "board", zoom = 0.22, from = { offset = V(-7, 4.6, 10.5), look = V(-7, 4.3, 1), fov = 52 },
			to = { offset = V(-7, 4.6, 10.5), look = V(-7, 4.45, 1), fov = 30 } },
		{ 13.2, 15.4, "board", from = WIDE },
		{ 15.4, 17.6, "door", from = OUTSIDE },
		{ 17.6, 20.0, "door", from = { offset = V(3, 4.5, 14), look = V(2, 3.5, 0), fov = 60 },
			to = { offset = V(2.5, 4.3, 12), look = V(2, 3.5, 0), fov = 60 } },
	},
	moves = {
		hero = {
			{ t = 0, anchor = "door", p = V(9, 0, 3.5), r = -90 },
			{ t = 0.8, p = V(0.4, 0, 2.0), move = "linear" },
			{ t = 0.92, r = 180, move = "out" },   -- square up to the door
			{ t = 1.35, r = 180 },
			{ t = 1.7, p = V(0.2, 0, -2.5), move = "linear" },   -- in over the fallen door
			{ t = 1.71, anchor = "board", p = V(9, 0, 9.5), r = 190 },
			{ t = 2.6, p = V(7, 0, 1), move = "linear" },
			{ t = 2.8, r = -70, move = "out" },   -- face Bob
			{ t = 15.4, anchor = "door", p = V(0, 0, -1), r = 90 },
			-- live 25 Oct: side-on in the dark doorway the cheer's fists vanished; turn to us, step into the light
			{ t = 17.6, r = 90 },
			{ t = 17.95, p = V(0, 0, 0.8), r = 10, move = "out" },
		},
		bob = {
			{ t = 0, anchor = "board", p = BOB_AT, r = 45, roll = 0 },
			-- over your shoulder he faces you square, staring at the iPad (turned on the cuts, unseen)
			{ t = 9.6, r = 80 },
			{ t = 11.0, r = 45 },
			{ t = 15.4, anchor = "door", p = V(0.8, 1, 0), r = -90, roll = 0 },
			{ t = 16.35, p = V(11, 0, 3), roll = 450, move = "arc", h = 3.5 },
			{ t = 17.2, roll = 90 },
			{ t = 17.8, roll = 0, move = "out" },
		},
		inv1 = { { t = 0, anchor = "board", p = INV1_AT, r = INV1_ROT } },
		inv2 = { { t = 0, anchor = "board", p = INV2_AT, r = 20 } },
	},
	looks = {
		hero = {
			{ t = 0, pose = "walk", face = "determined", vis = true },
			{ t = 0.85, pose = "kick" },
			{ t = 1.35, pose = "walk" },
			{ t = 1.71, face = "smug" },
			{ t = 2.6, pose = "stand" },
			{ t = 6.9, pose = "holdChart" },
			{ t = 13.2, pose = "stand" },
			{ t = 15.4, pose = "kick", face = "determined" },
			{ t = 15.85, pose = "stand" },
			{ t = 17.6, pose = "cheer", face = "grin" },
		},
		bob = {
			{ t = 0, pose = "annoyed", face = "smug", vis = true },
			{ t = 5.4, pose = "laugh", face = "laugh" },
			{ t = 9.6, pose = "laughdie" },
			{ t = 10.1, face = "grin" },
			{ t = 10.45, face = "deadpan" },
			{ t = 11.0, pose = "shock", face = "shock" },
			{ t = 13.2, pose = "throw" },
			{ t = 15.4, pose = "fly" },
			{ t = 16.35, pose = "lie", face = "dizzy" },
			{ t = 17.2, pose = "sit" },
		},
		inv1 = { { t = 0, pose = "stand", face = "neutral", vis = true }, { t = 5.6, pose = "laugh", face = "laugh" },
			{ t = 9.8, pose = "laughdie" }, { t = 10.5, face = "deadpan" }, { t = 11.0, pose = "shock", face = "shock" }, { t = 15.4, vis = false } },
		inv2 = { { t = 0, pose = "stand", face = "neutral", vis = true }, { t = 5.6, pose = "laugh", face = "laugh" },
			{ t = 9.7, pose = "laughdie" }, { t = 10.4, face = "deadpan" }, { t = 11.0, pose = "shock", face = "shock" }, { t = 15.4, vis = false } },
	},
	bubbles = {
		{ "bob", L.youAgain, 2.1, 3.6, voice = "huh" },   -- "huh?" ... then he grumbles (cue 2.95)
		{ "hero", L.myOffer, 3.75, 5.6, voice = "wahS", pitch = 1.1 },
		{ "bob", L.haha, 5.6, 6.8, voice = "laughBig", pitch = 0.9, vol = 0.65, free = true },   -- he laughs on until 9.6
		{ "bob", L.what, 11.15, 13.2, voice = "wahA", pitch = 1.35 },   -- a strangled little "WAH?!"
		{ "bob", L.takeIt, 13.4, 15.3, voice = "wahQ", pitch = 1.3 },   -- panicked: high and fast
		{ "hero", L.laughing, 17.9, 19.7, voice = "trumpetTalk", pitch = 1.1 },
	},
	fx = {
		{ kind = "debris", anchor = "door", p = V(0, 0, -0.6), t0 = 1.25, t1 = 2.2 },
		{ text = "BOING!", anchor = "door", p = V(10, 6.5, 3), t0 = 16.35, t1 = 17.35 },   -- above the landing, not on it
		{ kind = "stars", follow = "bob", t0 = 16.35, t1 = 20.01 },
	},
	vals = {
		-- the door falls flat into the room (0 = shut, 1 = flat), with a bounce; it lies there after
		doorDown = { { t = 0, v = 0 }, { t = 1.08, v = 0 }, { t = 1.2, v = 0.35 }, { t = 1.28, v = 1 }, { t = 1.36, v = 0.9 }, { t = 1.44, v = 1 } },
		tape = { { t = 0, v = 0 }, { t = 1.08, v = 0 }, { t = 1.55, v = 1 } },
		lid = { { t = 0, v = 0 } },
		glow = { { t = 0, v = 0 } },
		chart = { { t = 0, v = 0 }, { t = 8.5, v = 0 }, { t = 9.4, v = 1 } },
		chartShown = { { t = 0, v = 0 }, { t = 6.89, v = 0 }, { t = 6.9, v = 1 }, { t = 13.19, v = 1 }, { t = 13.2, v = 0 } },
		glasses = { { t = 0, v = 0 }, { t = 11.1, v = 0 }, { t = 11.6, v = 1 } },
		pick = { { t = 0, v = 0 }, { t = 11.2, v = 0 }, { t = 11.8, v = 1 } },
		bills = { { t = 0, v = 0 }, { t = 13.4, v = 0 }, { t = 15.0, v = 1 } },
		confetti = { { t = 0, v = 0 }, { t = 17.6, v = 0 }, { t = 20.0, v = 1 } },
		handoff = { { t = 0, v = 0 }, { t = 19.2, v = 0 }, { t = 19.8, v = 1 } },
	},
	shakes = { { 1.25, 1.55, 0.45 }, { 11.0, 11.25, 0.3 }, { 15.4, 15.9, 0.6 } },
	--[[ The gag's sound (Luke 25 Oct, second pass): the laughing is heard for as long as it is seen
		(it went silent at 7.8 while they laughed on to 9.6); at 9.62 the record scratch kills the music,
		the office and every laugh at once; a second of crickets in silence; then the stab on W-WHAT ]]
	beds = {
		{ "streetAmb", 0, 1.7, 0.15 },
		{ "music", 0.05, 9.62, 0.25, fin = 0.02, fout = 0.04, duck = true },
		{ "officeAmb", 1.7, 9.62, 0.18, fout = 0.04 },   -- minding their own business
		{ "crickets", 10.25, 11.0, 0.55, fin = 0.15, fout = 0.1 },
		{ "officeAmb", 11.0, 15.4, 0.18 },
		{ "streetAmb", 15.4, 20.0, 0.15 },
		{ "dizzy", 16.5, 20.0, 0.4 },      -- the stars round Bob's head
	},
	cues = {
		{ 0.9, "whoosh", vol = 0.5 }, { 1.1, "kick", vol = 0.9 }, { 1.18, "doorBreak", vol = 0.9 }, { 1.28, "thud", vol = 0.85 },
		{ 2.95, "wahA", vol = 0.8, pitch = 0.8, dur = 0.62, fade = 0.12 },   -- Bob grumbles "...AGAIN"
		-- the laugh: Bob's (the bubble's voice from 5.64, then this), his investors one after the other
		{ 7.5, "laughBob", vol = 0.75, pitch = 0.9, dur = 2.12, fade = 0.03 },
		{ 5.75, "invLaughA", vol = 0.6, pitch = 1.05 },
		{ 6.6, "invLaughB", vol = 0.55 },
		{ 7.6, "invLaughC", vol = 0.55, dur = 2.02, fade = 0.03 },
		{ 6.95, "whoosh", vol = 0.4 },     -- the iPad comes out
		{ 8.5, "riser", vol = 0.6, dur = 0.95, fade = 0.1 }, { 9.4, "ding", vol = 0.7, dur = 0.22, fade = 0.04 },   -- the line shoots up: +312%
		{ 9.62, "scratch", vol = 0.8 },    -- ...and everything stops
		{ 11.0, "shock", vol = 0.85 },     -- it lands
		{ 13.4, "money", vol = 0.8 }, { 13.45, "ding", vol = 0.45 }, { 13.5, "bills", vol = 0.6 },   -- ka-ching
		{ 15.35, "whoosh", vol = 0.5 }, { 15.45, "kick", vol = 0.9 }, { 15.5, "fly", vol = 0.6 },
		{ 16.35, "boing", vol = 0.8 }, { 16.4, "thud", vol = 0.95 },
		{ 17.65, "victory", vol = 0.7 },
	},
}

-- ------------------------------------------------------------------ evaluator
local function scene(name)
	local s = SCENES[name]
	assert(s, "BobScript: no scene " .. tostring(name))
	return s
end

function BobScript.length(name) return scene(name).length end

-- moves: carry anchor/p/r/roll forward; interpolate into a key that has `move`
local function moveAt(keys, t)
	local cur = { anchor = nil, p = V(0, 0, 0), r = 0, roll = 0 }
	local prev
	for _, k in ipairs(keys) do
		if k.t > t then
			if k.move and prev then
				local x = clamp01((t - prev.t) / (k.t - prev.t))
				local e = (k.move == "out") and EASE.out(x) or x
				if k.p then
					cur.p = cur.p:Lerp(k.p, e)
					if k.move == "arc" then cur.p += V(0, 4 * (k.h or 0) * x * (1 - x), 0) end
				end
				if k.r then cur.r += (k.r - cur.r) * e end
				if k.roll then cur.roll += (k.roll - cur.roll) * e end
			end
			break
		end
		cur.anchor = k.anchor or cur.anchor
		cur.p = k.p or cur.p
		cur.r = k.r or cur.r
		cur.roll = k.roll or cur.roll
		prev = { t = k.t }
	end
	return cur
end

local function lookAt(keys, t)
	local cur = { pose = "stand", face = "neutral", vis = false }
	for _, k in ipairs(keys) do
		if k.t > t then break end
		if k.pose then cur.pose = k.pose end
		if k.face then cur.face = k.face end
		if k.vis ~= nil then cur.vis = k.vis end
	end
	return cur
end

local function valAt(keys, t)
	local v = keys[1].v
	for i, k in ipairs(keys) do
		if k.t > t then
			local p = keys[i - 1]
			if p then v = p.v + (k.v - p.v) * clamp01((t - p.t) / (k.t - p.t)) end
			return v
		end
		v = k.v
	end
	return v
end

local function lerpCam(a, b, x)
	return { offset = a.offset:Lerp(b.offset, x), look = a.look:Lerp(b.look, x), fov = a.fov + (b.fov - a.fov) * x,
		dist = a.dist and (a.dist + ((b.dist or a.dist) - a.dist) * x) }
end

function BobScript.at(name, t, reduced)
	local s = scene(name)
	t = math.clamp(t, 0, s.length)
	local f = { actors = {}, bubbles = {}, fx = {}, vals = {}, shake = 0 }

	for id, keys in pairs(s.moves) do
		local m, l = moveAt(keys, t), lookAt(s.looks[id] or {}, t)
		f.actors[id] = { anchor = m.anchor, pos = m.p, rot = m.r, roll = m.roll, pose = l.pose, face = l.face, visible = l.vis }
	end

	-- the shot: the last one that has started
	local shotN, shot = 1, s.shots[1]
	for i, sh in ipairs(s.shots) do if t >= sh[1] then shotN, shot = i, sh end end
	f.shot = shotN
	local cam
	if reduced or not shot.to then
		cam = { offset = shot.from.offset, look = shot.from.look, fov = shot.from.fov, dist = shot.from.dist }
	elseif shot.zoom then
		cam = lerpCam(shot.from, shot.to, EASE.out(clamp01((t - shot[1]) / shot.zoom)))
	else
		cam = lerpCam(shot.from, shot.to, EASE.inout(clamp01((t - shot[1]) / (shot[2] - shot[1]))))
	end
	cam.aim = shot.aim
	if shot.follow then
		-- follow the actor's x; under Reduce Motion hold where it is halfway through the shot
		local who = reduced and moveAt(s.moves[shot.follow], (shot[1] + shot[2]) / 2) or f.actors[shot.follow]
		local px = (who.pos or who.p).X
		cam = { offset = cam.offset + V(px, 0, 0), look = cam.look + V(px, 0, 0), fov = cam.fov }
	end
	cam.anchor = shot[3]
	f.cam = cam

	for _, b in ipairs(s.bubbles) do
		local k = (t >= b[3] and t < b[4]) and pop(t, b[3]) or 0
		table.insert(f.bubbles, { actor = b[1], text = b[2], k = k })
	end
	for _, x in ipairs(s.fx) do
		local k = (t >= x.t0 and t < x.t1) and pop(t, x.t0) or 0
		table.insert(f.fx, { text = x.text, kind = x.kind or "text", anchor = x.anchor, pos = x.p, follow = x.follow, k = k, age = t - x.t0 })
	end
	for k, keys in pairs(s.vals) do f.vals[k] = valAt(keys, t) end
	f.door, f.tape, f.lid, f.glow, f.handoff = f.vals.door or 0, f.vals.tape or 0, f.vals.lid or 0, f.vals.glow or 0, f.vals.handoff or 0
	f.doorDown = f.vals.doorDown or 0

	if not reduced then
		for _, sh in ipairs(s.shakes) do
			if t >= sh[1] and t < sh[2] then f.shake = sh[3] * (1 - (t - sh[1]) / (sh[2] - sh[1])) end
		end
	end
	return f
end

-- the sounds to start in (t0, t1]: { t, id, vol, dur?, pitch?, fade?, bubble? }. A scene's cues, and
-- for every bubble its pop and its voice (the voice fades out as the bubble goes, unless `free`;
-- `bubble` is how long the bubble is up)
local VOICE_FADE = 0.15
function BobScript.cues(name, t0, t1)
	local s, out = scene(name), {}
	for _, c in ipairs(s.cues) do
		if c[1] > t0 and c[1] <= t1 then
			table.insert(out, { t = c[1], id = c[2], vol = c.vol or 0.6, dur = c.dur, pitch = c.pitch, fade = c.fade })
		end
	end
	for i, b in ipairs(s.bubbles) do
		if b[3] > t0 and b[3] <= t1 then
			table.insert(out, { t = b[3], id = "pop", vol = 0.3, pitch = POP_PITCH[(i - 1) % #POP_PITCH + 1] })
		end
		local tv = b[3] + 0.04
		if b.voice and tv > t0 and tv <= t1 then
			table.insert(out, { t = tv, id = b.voice, vol = b.vol or 0.9, pitch = b.pitch, bubble = b[4] - b[3],
				dur = not b.free and (b[4] - tv) or nil, fade = not b.free and VOICE_FADE or nil })
		end
	end
	return out
end

-- the scene's loops and music: { { id, t0, t1, vol, fin?, fout?, duck? } }
function BobScript.beds(name) return scene(name).beds or {} end

-- a bed's volume at t (before its trim): faded in over `fin` and out over `fout` (0.35 s unless
-- set), and under DUCK while a bubble is up if it ducks (the dip ramps over 0.15 s, no jump)
function BobScript.bedLevel(name, b, t)
	if t < b[2] or t >= b[3] then return 0 end
	local fin, fout = b.fin or 0.35, b.fout or 0.35
	local k = math.min(fin > 0 and (t - b[2]) / fin or 1, fout > 0 and (b[3] - t) / fout or 1)
	k = clamp01(k)
	if b.duck then
		local under = 0
		for _, bb in ipairs(scene(name).bubbles) do
			if t >= bb[3] and t < bb[4] then under = math.max(under, clamp01(math.min((t - bb[3]) / 0.15, (bb[4] - t) / 0.15))) end
		end
		k *= 1 - (1 - DUCK) * under
	end
	return b[4] * k
end

-- every sound heard at t, by name: a cue from its start for its length (cut by dur, sped by pitch,
-- and nothing outlives the scene) and every bed above zero. What the tests and the offline mix use
function BobScript.sounding(name, t)
	local s, out = scene(name), {}
	if t >= s.length then return out end
	for _, c in ipairs(BobScript.cues(name, -1, s.length)) do
		local info = BobScript.SOUND[c.id]
		local len = (info and info.len or 0) / (c.pitch or 1)
		if c.dur then len = math.min(len, c.dur) end
		if t >= c.t and t < c.t + len then table.insert(out, c.id) end
	end
	for _, b in ipairs(BobScript.beds(name)) do
		if BobScript.bedLevel(name, b, t) > 0 then table.insert(out, b[1]) end
	end
	return out
end

return BobScript
