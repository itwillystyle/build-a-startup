--[[
	BobClips -- ReplicatedStorage ModuleScript. P-5, Bob's cutscenes (25 Oct 2026).

	The body animation for both cutscenes, as KEYFRAMES (what Moon Animator / the Animation
	Editor make), played by BobSceneClient on each actor's joints every frame. No uploads: a
	clip is data, so it works in the live game with no animation asset to own or share.
	Clip list and timings: research/p5-bob/SHOT-LIST.md.

	A clip = { length = s, loop = bool, keys = { { t = s, ease = "inout"|"out"|"in"|"linear",
	  [joint] = { x, y, z } (degrees) }, ... } }. Each joint is its own track: a key that leaves
	a joint out does not move it. Joints follow R15 names; the AI cast (BobRig) has six of them
	(Root, Neck, LeftShoulder, RightShoulder, LeftHip, RightHip), so a clip for them uses only
	those, and the hero's clips may also use Waist, elbows, wrists, knees and ankles.

	Axes as WRITTEN in the clips: +x on a shoulder or hip swings the limb FORWARD (and up); -z on the
	right shoulder / +z on the left raises the arm OUT to the side; +x on an elbow bends the forearm
	up; -x on a knee bends the shin back; +x on Root/Waist/Neck leans FORWARD. (Live on the rig the
	z of shoulders and hips, and the x of Root/Waist/Neck, are the other way round, measured 25 Oct
	with the hands and the head; sample() flips them, so the clips read the way they were written.)

	BobClips.sample(name, t) -> { [joint] = CFrame }    (t in seconds since the clip started)
]]

local BobClips = {}

local function E(kind, x)
	if kind == "linear" then return x end
	if kind == "out" then return 1 - (1 - x) ^ 3 end
	if kind == "in" then return x ^ 3 end
	return x < 0.5 and 4 * x ^ 3 or 1 - (-2 * x + 2) ^ 3 / 2   -- inout
end

local C = {}

-- ------------------------------------------------------------------ the hero (any R15 avatar)
C.hero_idle = { length = 2.4, loop = true, keys = {
	{ t = 0, Waist = { 0, 0, 0 }, Neck = { 0, 0, 0 }, RightShoulder = { 0, 0, -6 }, LeftShoulder = { 0, 0, 6 } },
	{ t = 1.2, Waist = { 2, 0, 0 }, Neck = { -3, 0, 0 }, RightShoulder = { 3, 0, -8 }, LeftShoulder = { 3, 0, 8 } },
	{ t = 2.4, Waist = { 0, 0, 0 }, Neck = { 0, 0, 0 }, RightShoulder = { 0, 0, -6 }, LeftShoulder = { 0, 0, 6 } },
} }

-- "Can I get an offer?": a step of hope, palms up, a little shrug, hold
C.hero_ask = { length = 2.9, keys = {
	{ t = 0, Waist = { 0, 0, 0 }, RightShoulder = { 0, 0, -5 }, LeftShoulder = { 0, 0, 5 }, RightElbow = { 0, 0, 0 }, LeftElbow = { 0, 0, 0 }, Neck = { 0, 0, 0 } },
	{ t = 0.35, ease = "out", Waist = { 8, 0, 0 }, RightShoulder = { 35, 0, -18 }, LeftShoulder = { 35, 0, 18 }, RightElbow = { 55, 0, 0 }, LeftElbow = { 55, 0, 0 },
		RightWrist = { 0, -40, 0 }, LeftWrist = { 0, 40, 0 }, Neck = { -6, 0, 0 } },
	{ t = 0.75, Waist = { 4, 0, 0 }, RightShoulder = { 40, 0, -24 }, LeftShoulder = { 40, 0, 24 }, Neck = { -10, 0, 8 } },
	{ t = 1.1, Waist = { 6, 0, 0 }, RightShoulder = { 34, 0, -18 }, LeftShoulder = { 34, 0, 18 }, Neck = { -4, 0, -4 } },
	{ t = 2.9, Waist = { 5, 0, 0 }, RightShoulder = { 36, 0, -20 }, LeftShoulder = { 36, 0, 20 }, Neck = { -6, 0, 0 } },
} }

-- they laugh at you: shoulders drop, look down, then back up
C.hero_hurt = { length = 2.6, keys = {
	{ t = 0, Waist = { 5, 0, 0 }, Neck = { -6, 0, 0 }, RightShoulder = { 36, 0, -20 }, LeftShoulder = { 36, 0, 20 }, RightElbow = { 55, 0, 0 }, LeftElbow = { 55, 0, 0 } },
	{ t = 0.4, ease = "out", Waist = { 14, 0, 0 }, Neck = { 22, 0, 0 }, RightShoulder = { 0, 0, -3 }, LeftShoulder = { 0, 0, 3 }, RightElbow = { 5, 0, 0 }, LeftElbow = { 5, 0, 0 } },
	{ t = 1.8, Waist = { 12, 0, 0 }, Neck = { 18, 0, 0 } },
	{ t = 2.6, Waist = { 8, 0, 0 }, Neck = { 2, 0, 0 } },
} }

-- kicked through the air: ragdoll flail (the code spins and arcs the body)
C.hero_fly = { length = 0.32, loop = true, keys = {
	{ t = 0, RightShoulder = { 20, 0, -120 }, LeftShoulder = { -30, 0, 100 }, RightElbow = { 60, 0, 0 }, LeftElbow = { 20, 0, 0 },
		RightHip = { 40, 0, -20 }, LeftHip = { -30, 0, 25 }, RightKnee = { -70, 0, 0 }, LeftKnee = { -20, 0, 0 }, Neck = { -20, 0, 10 } },
	{ t = 0.16, RightShoulder = { -30, 0, -90 }, LeftShoulder = { 30, 0, 125 }, RightElbow = { 20, 0, 0 }, LeftElbow = { 70, 0, 0 },
		RightHip = { -30, 0, -25 }, LeftHip = { 40, 0, 20 }, RightKnee = { -20, 0, 0 }, LeftKnee = { -75, 0, 0 }, Neck = { 15, 0, -10 } },
	{ t = 0.32, RightShoulder = { 20, 0, -120 }, LeftShoulder = { -30, 0, 100 }, RightElbow = { 60, 0, 0 }, LeftElbow = { 20, 0, 0 },
		RightHip = { 40, 0, -20 }, LeftHip = { -30, 0, 25 }, RightKnee = { -70, 0, 0 }, LeftKnee = { -20, 0, 0 }, Neck = { -20, 0, 10 } },
} }

-- flat on his back on the pavement, dazed: splayed, a twitch
C.hero_land = { length = 0.85, keys = {
	{ t = 0, RightShoulder = { 0, 0, -80 }, LeftShoulder = { 0, 0, 80 }, RightElbow = { 30, 0, 0 }, LeftElbow = { 30, 0, 0 }, RightHip = { 0, 0, -15 }, LeftHip = { 0, 0, 15 }, Neck = { 0, 0, 0 } },
	{ t = 0.12, ease = "out", RightShoulder = { 0, 0, -95 }, LeftShoulder = { 0, 0, 95 }, Neck = { 0, 30, 0 } },
	{ t = 0.5, RightHip = { 0, 0, -22 }, LeftKnee = { -25, 0, 0 } },
	{ t = 0.62, RightHip = { 0, 0, -15 }, LeftKnee = { 0, 0, 0 } },
	{ t = 0.85, Neck = { 0, 18, 0 } },
} }

-- sit up and rub your head. For 0.2 s he settles flat (the pose blend lands while he still lies on
-- the pavement); then the hips bend IN STEP with the body rolling upright (the scene rolls him 90
-- degrees over the same 0.35 s, same ease), so the legs stay flat and the body pivots up off them.
-- Last the knees come up, the thighs tilting up by half the knee bend, so the feet stay down.
-- (live 25 Oct: legs bent before the roll swung under him and lifted him over sitting height,
-- 1.0 -> 2.9 studs; a pose blend that lagged the roll did the same, 0.7 studs)
C.hero_situp = { length = 0.7, keys = {
	{ t = 0, RightHip = { 0, 0, 0 }, LeftHip = { 0, 0, 0 }, RightKnee = { 0, 0, 0 }, LeftKnee = { 0, 0, 0 },
		RightShoulder = { 20, 0, -40 }, LeftShoulder = { 20, 0, 40 }, RightElbow = { 10, 0, 0 }, Neck = { 0, 0, 0 } },
	{ t = 0.2, RightHip = { 0, 0, 0 }, LeftHip = { 0, 0, 0 }, RightKnee = { 0, 0, 0 }, LeftKnee = { 0, 0, 0 }, Neck = { 0, 0, 0 } },
	{ t = 0.4, RightShoulder = { 20, 0, -40 }, RightElbow = { 10, 0, 0 } },   -- the hand stays off the pavement until he is half up
	{ t = 0.55, ease = "out", RightHip = { 90, 0, 0 }, LeftHip = { 90, 0, 0 }, RightKnee = { 0, 0, 0 }, LeftKnee = { 0, 0, 0 }, Neck = { 14, 0, -10 } },
	{ t = 0.65, RightHip = { 105, 0, -8 }, LeftHip = { 105, 0, 8 }, RightKnee = { -30, 0, 0 }, LeftKnee = { -30, 0, 0 },
		RightShoulder = { 120, 0, -30 }, RightElbow = { 110, 0, 0 }, LeftShoulder = { 10, 0, 25 } },
	{ t = 0.7, RightShoulder = { 128, 0, -28 }, Neck = { 18, 0, -12 } },
} }

-- up off the pavement (Luke 25 Oct: "he gets up too quickly"; it was sitting, then standing the next
-- frame). From the sit-up's last pose: lean in, feet under, hands to the knees, then push up into
-- the idle's first pose. The feet stay on the floor (the client puts the lowest point there), so
-- the body rises as the legs straighten
C.hero_getup = { length = 0.55, keys = {
	{ t = 0, RightHip = { 105, 0, -8 }, LeftHip = { 105, 0, 8 }, RightKnee = { -30, 0, 0 }, LeftKnee = { -30, 0, 0 }, Waist = { 0, 0, 0 },
		RightShoulder = { 128, 0, -28 }, LeftShoulder = { 10, 0, 25 }, RightElbow = { 110, 0, 0 }, LeftElbow = { 0, 0, 0 }, Neck = { 18, 0, -12 } },
	{ t = 0.2, RightHip = { 105, 0, -6 }, LeftHip = { 105, 0, 6 }, RightKnee = { -115, 0, 0 }, LeftKnee = { -115, 0, 0 }, Waist = { 28, 0, 0 },
		RightShoulder = { 45, 0, -12 }, LeftShoulder = { 45, 0, 12 }, RightElbow = { 35, 0, 0 }, LeftElbow = { 35, 0, 0 }, Neck = { -8, 0, 0 } },
	{ t = 0.55, RightHip = { 0, 0, 0 }, LeftHip = { 0, 0, 0 }, RightKnee = { 0, 0, 0 }, LeftKnee = { 0, 0, 0 }, Waist = { 0, 0, 0 },
		RightShoulder = { 0, 0, -6 }, LeftShoulder = { 0, 0, 6 }, RightElbow = { 0, 0, 0 }, LeftElbow = { 0, 0, 0 }, Neck = { 0, 0, 0 } },
} }

-- the slumped walk home (in place: the code moves you)
C.hero_sadwalk = { length = 1.1, loop = true, keys = {
	{ t = 0, Waist = { 12, 0, 0 }, Neck = { 18, 0, 0 }, RightHip = { 22, 0, 0 }, LeftHip = { -20, 0, 0 }, RightKnee = { -5, 0, 0 }, LeftKnee = { -30, 0, 0 },
		RightShoulder = { -12, 0, -3 }, LeftShoulder = { 12, 0, 3 } },
	{ t = 0.275, LeftKnee = { -55, 0, 0 }, RightKnee = { -2, 0, 0 } },
	{ t = 0.55, RightHip = { -20, 0, 0 }, LeftHip = { 22, 0, 0 }, RightKnee = { -30, 0, 0 }, LeftKnee = { -5, 0, 0 }, RightShoulder = { 12, 0, -3 }, LeftShoulder = { -12, 0, 3 } },
	{ t = 0.825, RightKnee = { -55, 0, 0 }, LeftKnee = { -2, 0, 0 } },
	{ t = 1.1, Waist = { 12, 0, 0 }, Neck = { 18, 0, 0 }, RightHip = { 22, 0, 0 }, LeftHip = { -20, 0, 0 }, RightKnee = { -5, 0, 0 }, LeftKnee = { -30, 0, 0 },
		RightShoulder = { -12, 0, -3 }, LeftShoulder = { 12, 0, 3 } },
} }

-- at the laptop: open it, straighten up, raise a fist: "He will rue the day."
C.hero_vow = { length = 4.2, keys = {
	{ t = 0, Waist = { 14, 0, 0 }, Neck = { 16, 0, 0 }, RightShoulder = { 0, 0, -4 }, LeftShoulder = { 0, 0, 4 }, RightElbow = { 0, 0, 0 } },
	{ t = 0.25, Waist = { 26, 0, 0 }, RightShoulder = { 55, 0, -6 }, RightElbow = { 30, 0, 0 } },
	{ t = 0.75, ease = "out", RightShoulder = { 70, 0, -6 }, RightElbow = { 10, 0, 0 } },
	{ t = 1.0, Waist = { 6, 0, 0 }, Neck = { 0, 0, 0 }, RightShoulder = { 10, 0, -6 }, RightElbow = { 10, 0, 0 } },
	{ t = 1.2, ease = "out", Waist = { -4, 0, 0 }, Neck = { -8, 0, 0 }, RightShoulder = { 160, 0, -12 }, RightElbow = { 40, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 8, 0, 10 }, LeftElbow = { 70, 0, 0 } },
	{ t = 1.35, RightShoulder = { 150, 0, -12 } },
	{ t = 4.2, Waist = { -4, 0, 0 }, Neck = { -8, 0, 0 }, RightShoulder = { 152, 0, -12 }, RightElbow = { 42, 0, 0 } },
} }

-- payoff: the confident strut
C.hero_strut = { length = 0.9, loop = true, keys = {
	{ t = 0, Waist = { -6, 0, 0 }, Neck = { -6, 0, 0 }, RightHip = { 26, 0, 0 }, LeftHip = { -22, 0, 0 }, LeftKnee = { -25, 0, 0 }, RightKnee = { 0, 0, 0 },
		RightShoulder = { -28, 0, -8 }, LeftShoulder = { 28, 0, 8 }, RightElbow = { 20, 0, 0 }, LeftElbow = { 35, 0, 0 } },
	{ t = 0.225, LeftKnee = { -50, 0, 0 }, Waist = { -6, 12, 0 } },
	{ t = 0.45, RightHip = { -22, 0, 0 }, LeftHip = { 26, 0, 0 }, RightKnee = { -25, 0, 0 }, LeftKnee = { 0, 0, 0 },
		RightShoulder = { 28, 0, -8 }, LeftShoulder = { -28, 0, 8 }, RightElbow = { 35, 0, 0 }, LeftElbow = { 20, 0, 0 }, Waist = { -6, 0, 0 } },
	{ t = 0.675, RightKnee = { -50, 0, 0 }, Waist = { -6, -12, 0 } },
	{ t = 0.9, Waist = { -6, 0, 0 }, Neck = { -6, 0, 0 }, RightHip = { 26, 0, 0 }, LeftHip = { -22, 0, 0 }, LeftKnee = { -25, 0, 0 }, RightKnee = { 0, 0, 0 },
		RightShoulder = { -28, 0, -8 }, LeftShoulder = { 28, 0, 8 }, RightElbow = { 20, 0, 0 }, LeftElbow = { 35, 0, 0 } },
} }

-- payoff (Luke 25 Oct: "an iPad that I pull out from behind my back"): reach behind, bring it round,
-- hold it out to Bob in both hands, a smug lean. The client puts the tablet in the right hand while it
-- comes round (0.35-0.95 s) and between both hands after
C.hero_ipad = { length = 5.2, keys = {
	{ t = 0, RightShoulder = { 0, 0, -6 }, LeftShoulder = { 0, 0, 6 }, RightElbow = { 0, 0, 0 }, LeftElbow = { 0, 0, 0 }, Waist = { 0, 0, 0 }, Neck = { 0, 0, 0 } },
	{ t = 0.35, ease = "out", RightShoulder = { -45, 0, -12 }, RightElbow = { 70, 0, 0 }, Waist = { 0, -12, 0 }, Neck = { -6, 10, 0 } },
	{ t = 0.55, RightShoulder = { -40, 0, -12 } },
	-- live 25 Oct: held at chest height (higher, it hid his face): upper arms forward-down, forearms up
	{ t = 0.95, ease = "out", RightShoulder = { 52, 0, -10 }, RightElbow = { 62, 0, 0 }, LeftShoulder = { 50, 0, 12 }, LeftElbow = { 62, 0, 0 },
		Waist = { 0, 0, 0 }, Neck = { -4, 0, 0 } },
	{ t = 1.2, RightShoulder = { 56, 0, -10 }, LeftShoulder = { 54, 0, 12 } },
	{ t = 2.0, RightShoulder = { 52, 0, -10 }, LeftShoulder = { 50, 0, 12 }, Waist = { -5, 0, 0 } },
	{ t = 3.0, RightShoulder = { 55, 0, -10 }, LeftShoulder = { 53, 0, 12 }, Waist = { -3, 0, 0 } },
	{ t = 4.0, RightShoulder = { 52, 0, -10 }, LeftShoulder = { 50, 0, 12 }, Waist = { -5, 0, 0 } },
	{ t = 5.2, RightShoulder = { 53, 0, -10 }, LeftShoulder = { 51, 0, 12 }, Waist = { -4, 0, 0 } },
} }
BobClips.IPAD_IN_HAND, BobClips.IPAD_HELD = 0.35, 0.95   -- the tablet's beats inside hero_ipad (s)

-- your kick: wind up, SNAP, hold
C.hero_kick = { length = 0.45, keys = {
	{ t = 0, RightHip = { 0, 0, 0 }, RightKnee = { 0, 0, 0 }, Waist = { 0, 0, 0 } },
	{ t = 0.12, ease = "out", RightHip = { -35, 0, 0 }, RightKnee = { -70, 0, 0 }, Waist = { 8, 0, 0 }, RightShoulder = { 30, 0, -40 }, LeftShoulder = { -20, 0, 40 } },
	{ t = 0.2, ease = "out", RightHip = { 95, 0, 0 }, RightKnee = { 0, 0, 0 }, Waist = { -18, 0, 0 }, RightShoulder = { -20, 0, -60 }, LeftShoulder = { 30, 0, 60 } },
	{ t = 0.34, RightHip = { 92, 0, 0 } },
	{ t = 0.45, ease = "inout", RightHip = { 20, 0, 0 }, RightKnee = { -20, 0, 0 }, Waist = { -4, 0, 0 } },
} }

-- payoff: both fists pumping, a little hop
C.hero_cheer = { length = 0.8, loop = true, keys = {
	{ t = 0, RightShoulder = { 165, 0, -25 }, LeftShoulder = { 165, 0, 25 }, RightElbow = { 30, 0, 0 }, LeftElbow = { 30, 0, 0 }, RightKnee = { -20, 0, 0 }, LeftKnee = { -20, 0, 0 }, Neck = { -12, 0, 0 } },
	{ t = 0.4, ease = "out", RightShoulder = { 140, 0, -35 }, LeftShoulder = { 140, 0, 35 }, RightElbow = { 70, 0, 0 }, LeftElbow = { 70, 0, 0 }, RightKnee = { 0, 0, 0 }, LeftKnee = { 0, 0, 0 } },
	{ t = 0.8, RightShoulder = { 165, 0, -25 }, LeftShoulder = { 165, 0, 25 }, RightElbow = { 30, 0, 0 }, LeftElbow = { 30, 0, 0 }, RightKnee = { -20, 0, 0 }, LeftKnee = { -20, 0, 0 } },
} }

-- ------------------------------------------------------------------ Bob and the investors (six joints)
-- Bob is wide: his arms rest out round the belly (z), never through it
C.bob_smug = { length = 3.0, loop = true, keys = {
	{ t = 0, Root = { -4, 0, 0 }, Neck = { -10, 8, 0 }, RightShoulder = { 30, 0, -28 }, LeftShoulder = { 30, 0, 28 } },
	{ t = 1.5, Root = { -6, 0, 2 }, Neck = { -12, -6, 0 }, RightShoulder = { 34, 0, -30 }, LeftShoulder = { 34, 0, 30 } },
	{ t = 3.0, Root = { -4, 0, 0 }, Neck = { -10, 8, 0 }, RightShoulder = { 30, 0, -28 }, LeftShoulder = { 30, 0, 28 } },
} }

-- the belly laugh: back he goes, the belly bounces, one hand slaps it. Live 25 Oct (Luke: "bobbing
-- around like literally falling"): the lean is small and the head does the throwing back; the legs
-- stay planted (sample() counters any Root lean at the hips)
C.bob_laugh = { length = 0.6, loop = true, keys = {
	{ t = 0, Root = { -6, 0, 0 }, Neck = { -26, 0, 0 }, RightShoulder = { 45, 0, -30 }, LeftShoulder = { 20, 0, 50 } },
	{ t = 0.15, ease = "out", Root = { -10, 0, 2 }, Neck = { -34, 0, 4 }, RightShoulder = { 30, 0, -24 }, LeftShoulder = { 26, 0, 58 } },
	{ t = 0.3, Root = { -5, 0, 0 }, Neck = { -22, 0, 0 }, RightShoulder = { 50, 0, -32 }, LeftShoulder = { 18, 0, 46 } },
	{ t = 0.45, ease = "out", Root = { -10, 0, -2 }, Neck = { -34, 0, -4 }, RightShoulder = { 28, 0, -24 }, LeftShoulder = { 26, 0, 58 } },
	{ t = 0.6, Root = { -6, 0, 0 }, Neck = { -26, 0, 0 }, RightShoulder = { 45, 0, -30 }, LeftShoulder = { 20, 0, 50 } },
} }

-- payoff (Luke 25 Oct: "he stops laughing ... a coming to earth moment"): the laugh runs down. Each
-- bounce smaller and slower, the head comes forward, the arms sink, and he freezes, staring
C.bob_laughdie = { length = 1.4, keys = {
	{ t = 0, Root = { -6, 0, 0 }, Neck = { -26, 0, 0 }, RightShoulder = { 45, 0, -30 }, LeftShoulder = { 20, 0, 50 } },
	{ t = 0.18, ease = "out", Root = { -9, 0, 2 }, Neck = { -30, 0, 3 }, RightShoulder = { 32, 0, -26 }, LeftShoulder = { 24, 0, 54 } },
	{ t = 0.4, Root = { -5, 0, 0 }, Neck = { -18, 0, 0 }, RightShoulder = { 42, 0, -30 }, LeftShoulder = { 20, 0, 48 } },
	{ t = 0.65, ease = "out", Root = { -6, 0, -1 }, Neck = { -14, 0, -2 }, RightShoulder = { 36, 0, -28 }, LeftShoulder = { 22, 0, 44 } },
	{ t = 1.0, Root = { -2, 0, 0 }, Neck = { -4, 0, 0 }, RightShoulder = { 30, 0, -26 }, LeftShoulder = { 26, 0, 32 } },
	{ t = 1.4, ease = "out", Root = { 0, 0, 0 }, Neck = { 2, 0, 0 }, RightShoulder = { 26, 0, -24 }, LeftShoulder = { 26, 0, 26 } },
} }

-- THE KICK: wind up (the leg comes back), snap forward and up, hold, recover
C.bob_kick = { length = 0.55, keys = {
	{ t = 0, Root = { 0, 0, 0 }, RightHip = { 0, 0, 0 }, RightShoulder = { 30, 0, -28 }, LeftShoulder = { 30, 0, 28 } },
	{ t = 0.2, ease = "out", Root = { 10, 0, 0 }, RightHip = { -40, 0, 0 }, RightShoulder = { -10, 0, -55 }, LeftShoulder = { 40, 0, 50 } },
	{ t = 0.3, ease = "out", Root = { -22, 0, 0 }, RightHip = { 100, 0, 0 }, RightShoulder = { -30, 0, -70 }, LeftShoulder = { 20, 0, 70 }, Neck = { -15, 0, 0 } },
	{ t = 0.43, Root = { -20, 0, 0 }, RightHip = { 96, 0, 0 } },
	{ t = 0.55, ease = "inout", Root = { -8, 0, 0 }, RightHip = { 10, 0, 0 }, RightShoulder = { 40, 0, -30 }, LeftShoulder = { 30, 0, 40 } },
} }

-- payoff: the double take: jolt back, hands up by his face, frozen
C.bob_shock = { length = 2.4, keys = {
	{ t = 0, Root = { -14, 0, 0 }, Neck = { -24, 0, 0 }, RightShoulder = { 45, 0, -30 }, LeftShoulder = { 20, 0, 50 } },
	{ t = 0.1, Root = { 0, 0, 0 }, Neck = { 0, 0, 0 } },
	{ t = 0.28, ease = "out", Root = { -24, 0, 0 }, Neck = { 10, 0, 0 }, RightShoulder = { 150, 0, -40 }, LeftShoulder = { 150, 0, 40 } },
	{ t = 0.45, Root = { -18, 0, 0 } },
	{ t = 2.4, Root = { -19, 0, 0 }, RightShoulder = { 148, 0, -40 }, LeftShoulder = { 148, 0, 40 } },
} }

-- payoff: flinging cash, alternating arms, panicked
C.bob_throw = { length = 0.5, loop = true, keys = {
	{ t = 0, Root = { 8, 0, 0 }, RightShoulder = { 150, 0, -20 }, LeftShoulder = { 20, 0, 40 } },
	{ t = 0.12, ease = "out", RightShoulder = { 40, 0, -20 }, LeftShoulder = { 70, 0, 40 } },
	{ t = 0.25, Root = { 8, 0, 0 }, RightShoulder = { 20, 0, -40 }, LeftShoulder = { 150, 0, 20 } },
	{ t = 0.37, ease = "out", RightShoulder = { 70, 0, -40 }, LeftShoulder = { 40, 0, 20 } },
	{ t = 0.5, Root = { 8, 0, 0 }, RightShoulder = { 150, 0, -20 }, LeftShoulder = { 20, 0, 40 } },
} }

C.bob_fly = { length = 0.32, loop = true, keys = {
	{ t = 0, RightShoulder = { 20, 0, -130 }, LeftShoulder = { -20, 0, 110 }, RightHip = { 40, 0, -20 }, LeftHip = { -30, 0, 25 }, Neck = { -20, 0, 0 } },
	{ t = 0.16, RightShoulder = { -30, 0, -100 }, LeftShoulder = { 30, 0, 135 }, RightHip = { -30, 0, -25 }, LeftHip = { 40, 0, 20 }, Neck = { 15, 0, 0 } },
	{ t = 0.32, RightShoulder = { 20, 0, -130 }, LeftShoulder = { -20, 0, 110 }, RightHip = { 40, 0, -20 }, LeftHip = { -30, 0, 25 }, Neck = { -20, 0, 0 } },
} }

-- payoff: lying dazed, then sitting up at 0.85 s, swaying, head lolling
C.bob_dizzy = { length = 4.65, keys = {
	{ t = 0, RightShoulder = { 0, 0, -85 }, LeftShoulder = { 0, 0, 85 }, RightHip = { 0, 0, -20 }, LeftHip = { 0, 0, 20 }, Neck = { 0, 0, 0 } },
	{ t = 0.85, RightHip = { 0, 0, -20 }, LeftHip = { 0, 0, 20 } },
	{ t = 1.3, ease = "out", RightHip = { 85, 0, -15 }, LeftHip = { 85, 0, 15 }, RightShoulder = { 10, 0, -35 }, LeftShoulder = { 10, 0, 35 }, Neck = { 10, 0, 20 } },
	{ t = 2.0, Root = { 0, 0, 8 }, Neck = { 5, 0, -25 } },
	{ t = 2.7, Root = { 0, 0, -8 }, Neck = { 12, 0, 25 } },
	{ t = 3.4, Root = { 0, 0, 8 }, Neck = { 5, 0, -25 } },
	{ t = 4.1, Root = { 0, 0, -8 }, Neck = { 12, 0, 25 } },
	{ t = 4.65, Root = { 0, 0, 0 }, Neck = { 8, 0, 0 } },
} }

C.inv_idle = { length = 2.6, loop = true, keys = {
	{ t = 0, Root = { 0, 0, 0 }, Neck = { 0, 0, 0 }, RightShoulder = { 8, 0, -8 }, LeftShoulder = { 8, 0, 8 } },
	{ t = 1.3, Root = { 2, 0, 0 }, Neck = { -4, 6, 0 }, RightShoulder = { 12, 0, -10 }, LeftShoulder = { 12, 0, 10 } },
	{ t = 2.6, Root = { 0, 0, 0 }, Neck = { 0, 0, 0 }, RightShoulder = { 8, 0, -8 }, LeftShoulder = { 8, 0, 8 } },
} }

-- laughing along: hunched, one hand pointing at you, shoulders shaking
C.inv_laugh = { length = 0.5, loop = true, keys = {
	{ t = 0, Root = { 14, 0, 0 }, Neck = { -18, 0, 0 }, RightShoulder = { 95, 0, -8 }, LeftShoulder = { 30, 0, 30 } },
	{ t = 0.125, ease = "out", Root = { 20, 0, 0 }, Neck = { -10, 0, 0 }, LeftShoulder = { 40, 0, 36 } },
	{ t = 0.25, Root = { 12, 0, 0 }, Neck = { -20, 0, 0 }, RightShoulder = { 90, 0, -10 }, LeftShoulder = { 28, 0, 28 } },
	{ t = 0.375, ease = "out", Root = { 20, 0, 0 }, Neck = { -10, 0, 0 }, LeftShoulder = { 40, 0, 36 } },
	{ t = 0.5, Root = { 14, 0, 0 }, Neck = { -18, 0, 0 }, RightShoulder = { 95, 0, -8 }, LeftShoulder = { 30, 0, 30 } },
} }

-- payoff: the laugh along runs down too, then a stare
C.inv_laughdie = { length = 1.0, keys = {
	{ t = 0, Root = { 14, 0, 0 }, Neck = { -18, 0, 0 }, RightShoulder = { 95, 0, -8 }, LeftShoulder = { 30, 0, 30 } },
	{ t = 0.2, ease = "out", Root = { 16, 0, 0 }, Neck = { -12, 0, 0 }, LeftShoulder = { 36, 0, 32 } },
	{ t = 0.45, Root = { 8, 0, 0 }, Neck = { -6, 0, 0 }, RightShoulder = { 60, 0, -8 }, LeftShoulder = { 20, 0, 18 } },
	{ t = 1.0, ease = "out", Root = { 2, 0, 0 }, Neck = { 0, 0, 0 }, RightShoulder = { 12, 0, -8 }, LeftShoulder = { 10, 0, 10 } },
} }

-- payoff: a jolt back, hands up, frozen
C.inv_shock = { length = 1.0, keys = {
	{ t = 0, Root = { 14, 0, 0 }, Neck = { -18, 0, 0 }, RightShoulder = { 95, 0, -8 }, LeftShoulder = { 30, 0, 30 } },
	{ t = 0.22, ease = "out", Root = { -16, 0, 0 }, Neck = { 8, 0, 0 }, RightShoulder = { 140, 0, -30 }, LeftShoulder = { 140, 0, 30 } },
	{ t = 1.0, Root = { -12, 0, 0 }, RightShoulder = { 135, 0, -30 }, LeftShoulder = { 135, 0, 30 } },
} }

BobClips.CLIPS = C

local FLIP_Z = { LeftShoulder = true, RightShoulder = true, LeftHip = true, RightHip = true }
local FLIP_X = { Root = true, Waist = true, Neck = true }

-- build each joint's own track once: { joint = { {t, x, y, z, ease}, ... } }
local TRACKS = {}
for name, clip in pairs(C) do
	local tr = {}
	for _, k in ipairs(clip.keys) do
		for joint, v in pairs(k) do
			if type(v) == "table" then
				tr[joint] = tr[joint] or {}
				table.insert(tr[joint], { k.t, v[1], v[2], v[3], k.ease or "inout" })
			end
		end
	end
	TRACKS[name] = tr
end

function BobClips.has(name) return C[name] ~= nil end
function BobClips.length(name) return C[name] and C[name].length or 0 end

-- the joint rotations of clip `name` at t seconds (degrees in, CFrames out)
function BobClips.sample(name, t)
	local clip, tracks = C[name], TRACKS[name]
	if not clip then return {} end
	if clip.loop then t = t % clip.length else t = math.clamp(t, 0, clip.length) end
	local out = {}
	for joint, keys in pairs(tracks) do
		local a, b = keys[1], keys[#keys]
		for i = 1, #keys do
			if keys[i][1] <= t then a = keys[i] end
			if keys[i][1] >= t then b = keys[i]; break end
		end
		local x, y, z
		if a == b or b[1] == a[1] then
			x, y, z = a[2], a[3], a[4]
		else
			local k = E(b[5], (t - a[1]) / (b[1] - a[1]))
			x, y, z = a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k, a[4] + (b[4] - a[4]) * k
		end
		-- measured live 25 Oct: on the rig, +z swings a RIGHT limb out (and a left one in); the clips are
		-- written as "-z = right limb out", so shoulders and hips flip z here, once, for every clip
		if FLIP_Z[joint] then z = -z end
		if FLIP_X[joint] then x = -x end   -- measured 25 Oct: +x on the body joints leans BACK on the rig
		out[joint] = CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
	end
	-- live 25 Oct: on the six-joint rigs the legs hang off the torso, so a Root lean tipped the whole
	-- body over like a plank (Bob looked like he was falling). The hips take the lean back out, so the
	-- legs stay planted and only the body above them leans. (The hero's clips lean with Waist.)
	if out.Root then
		local undo = out.Root:Inverse()
		for _, hip in ipairs({ "LeftHip", "RightHip" }) do out[hip] = undo * (out[hip] or CFrame.new()) end
	end
	return out
end

return BobClips
