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

--[[ SOUND (25 Oct, Luke: "add the sounds"). Every sound the scenes use, by the name the data below
	uses -> its key in Sfx.ID (where the asset ids live, with what each recording is). Three kinds:
	  cues    one-shots at a time: { t, name, vol?, dur?, pitch? } (dur: stop it after that long)
	  beds    loops that fade in and out with their span: { name, t0, t1, vol }
	  voices  a bubble's sound: every bubble pops in ("pop") and plays its `voice` for as long as it
	          is up. Nobody speaks real words: cartoon nonsense talk, the rich "ho ho" laugh, a "huh?" ]]
BobScript.SOUND = {
	music = "bobMusic", victory = "victory",
	officeAmb = "bobOffice", streetAmb = "bobStreet", rain = "bobRain", dizzy = "bobDizzy",
	pop = "bobPop", talk = "bobTalk", laughRich = "bobLaugh", laughCrowd = "bobChuckle", huh = "bobHuh", gasp = "bobGasp",
	whoosh = "bobWhoosh", kick = "bobKick", fly = "bobFly", boing = "bobBoing", thud = "thud",
	doorSlam = "bobDoorSlam", doorBreak = "bobDoorBreak", sad = "bobSad", tbc = "bobTbc", laptop = "bobLaptop",
	riser = "bobRiser", ding = "bobDing", scratch = "bobScratch", crickets = "bobCrickets", realize = "bobRealize",
	money = "money", bills = "bobBills",
}

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
		{ "hero", L.offer, 0.5, 3.4, voice = "talk" },
		{ "bob", L.haOffer, 3.6, 6.2, voice = "laughRich", pitch = 0.85 },   -- deeper: a rich man's laugh   -- (one bubble at a time: the investors laugh without one)
		{ "hero", L.rue, 13.2, 16.21 },   -- (no voice: the to-be-continued sting says it)
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
		{ "officeAmb", 0, 6.2, 0.22 },     -- an investor's office, not an empty room
		{ "streetAmb", 6.2, 10.4, 0.2 },
		{ "rain", 9.0, 11.4, 0.3 },        -- under your cloud
		{ "dizzy", 7.35, 8.5, 0.3 },       -- seeing stars on the pavement
	},
	cues = {
		{ 0.05, "music", vol = 0.3 },
		{ 4.2, "laughCrowd", vol = 0.3, dur = 2.0 },  -- the investors join in
		{ 6.22, "whoosh", vol = 0.45 }, { 6.3, "kick", vol = 0.6 }, { 6.4, "fly", vol = 0.5 },
		{ 7.25, "boing", vol = 0.6 }, { 7.3, "thud", vol = 0.55 },
		{ 7.95, "doorSlam", vol = 0.5 },
		{ 9.05, "sad", vol = 0.45 },
		{ 12.25, "laptop", vol = 0.5 },
		{ 13.25, "tbc", vol = 0.55 },      -- "He will rue the day." ... to be continued
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
		{ "bob", L.youAgain, 2.1, 3.6, voice = "huh", pitch = 1.15 },
		{ "hero", L.myOffer, 3.75, 5.6, voice = "talk" },
		{ "bob", L.haha, 5.6, 6.8, voice = "laughRich", pitch = 0.85 },
		{ "bob", L.what, 11.15, 13.2, voice = "gasp" },
		{ "bob", L.takeIt, 13.4, 15.3, voice = "talk", pitch = 1.3 },   -- panicked: higher
		{ "hero", L.laughing, 17.9, 19.7, voice = "talk" },
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
	beds = {
		{ "streetAmb", 0, 1.7, 0.2 },
		{ "officeAmb", 1.7, 15.4, 0.22 },  -- minding their own business
		{ "streetAmb", 15.4, 20.0, 0.2 },
		{ "dizzy", 16.5, 20.0, 0.3 },      -- the stars round Bob's head
	},
	cues = {
		{ 0.05, "music", vol = 0.3 },
		{ 0.9, "whoosh", vol = 0.45 }, { 1.1, "kick", vol = 0.6 }, { 1.2, "doorBreak", vol = 0.6 }, { 1.26, "thud", vol = 0.5 },
		{ 5.8, "laughCrowd", vol = 0.3, dur = 2.0 },
		{ 6.95, "whoosh", vol = 0.35 },    -- the iPad comes out
		{ 8.5, "riser", vol = 0.5, dur = 0.95 }, { 9.4, "ding", vol = 0.55 },   -- the line shoots up: +312%
		{ 9.62, "scratch", vol = 0.55 },   -- the laugh stops dead
		{ 10.2, "crickets", vol = 0.4, dur = 0.8 },
		{ 11.0, "realize", vol = 0.6 },    -- it lands
		{ 13.4, "money", vol = 0.55 }, { 13.45, "ding", vol = 0.35 }, { 13.5, "bills", vol = 0.5 },   -- ka-ching
		{ 15.35, "whoosh", vol = 0.45 }, { 15.45, "kick", vol = 0.6 }, { 15.5, "fly", vol = 0.5 },
		{ 16.35, "boing", vol = 0.6 }, { 16.4, "thud", vol = 0.55 },
		{ 17.65, "victory", vol = 0.55 },
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

-- the sounds to start in (t0, t1]: { id, vol?, dur?, pitch? }. A scene's cues, and for every bubble
-- its pop and its voice (the voice stops when the bubble goes)
function BobScript.cues(name, t0, t1)
	local s, out = scene(name), {}
	for _, c in ipairs(s.cues) do
		if c[1] > t0 and c[1] <= t1 then table.insert(out, { id = c[2], vol = c.vol, dur = c.dur, pitch = c.pitch }) end
	end
	for _, b in ipairs(s.bubbles) do
		if b[3] > t0 and b[3] <= t1 then table.insert(out, { id = "pop", vol = 0.45 }) end
		local tv = b[3] + 0.04
		if b.voice and tv > t0 and tv <= t1 then
			table.insert(out, { id = b.voice, vol = b.vol or 0.6, dur = b[4] - tv, pitch = b.pitch })
		end
	end
	return out
end

-- the scene's loops: { { id, t0, t1, vol } }; the client fades each in and out with its span
function BobScript.beds(name) return scene(name).beds or {} end

return BobScript
