--[[
	BobScript -- ReplicatedStorage ModuleScript. P-5, Bob the first boss investor (25 Oct 2026).

	Both of Bob's cutscenes as DATA, and a pure evaluator: BobScript.at(name, t, reduced)
	returns everything on screen at time t. BobSceneClient draws it every frame; the
	offline tests (tests/offline/bobscript.spec.luau) check it without Studio.

	  "intro"   option A "fast cuts" (Luke's pick from ui/storyboards/p5-bob): you ask Bob
	            for an offer, he and his investors laugh, he kicks you out of his door, you
	            walk home in the rain and vow at your laptop. New saves only. 16.2 s.
	  "payoff"  floor 13 (the HQ 4 stage): you walk into his office, show your REVENUE
	            chart, he throws the money (x3) and you kick HIM out. 17 s.

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
	whatHere = "What are YOU doing here?",
	what = "W-WHAT?!",
	takeIt = "Take it! TAKE IT ALL!",
	proved = "PROVED WRONG!",
	toast = "SERIES A CLOSED · x3",
	taped = "Bob isn't taking meetings... yet.",
	trophy = "BOB'S TOOTHPICK",
}
local L = BobScript.LINES

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
	shots   { { t0, t1, anchor, from = {offset, look, fov}, to = {...}?, follow = actorId? } }
	moves   [actor] = { { t, anchor?, p?, r?, roll?, move? ("linear"|"out"|"arc"), h? } }
	looks   [actor] = { { t, pose?, face?, vis? } }
	bubbles { { actor, text, t0, t1 } }
	fx      { { text?, kind?, anchor, p, t0, t1, follow? } }
	vals    [name] = { { t, v } }  (linear between keys)
	shakes  { { t0, t1, amp } }
	cues    { { t, id } } ]]

local WIDE = { offset = V(0, 5, 22), look = V(0, 3, 0), fov = 60 }
local ONBOB = { offset = V(-7, 4.5, 9), look = V(-7, 4.2, 0), fov = 50 }
local OUTSIDE = { offset = V(6, 4, 16), look = V(6, 3, 0), fov = 60 }

local SCENES = {}

SCENES.intro = {
	length = 16.2,
	shots = {
		{ 0, 3.4, "board", from = WIDE, to = { offset = V(1.5, 5, 20.5), look = V(1.5, 3, 0), fov = 60 } },
		{ 3.4, 6.2, "board", from = ONBOB, to = { offset = V(-7, 4.5, 8), look = V(-7, 4.4, 0), fov = 50 } },
		{ 6.2, 9.0, "door", from = OUTSIDE },
		{ 9.0, 10.4, "street", from = { offset = V(1.5, 4, 12), look = V(1.5, 3, 0), fov = 60 }, follow = "hero" },
		{ 10.4, 12.0, "garage", from = { offset = V(-3, 5, 15), look = V(-3, 3, 0), fov = 60 } },
		-- live 25 Oct: the vow fist sat under the top letterbox bar; aim higher, push in less
		{ 12.0, 16.2, "garage", from = { offset = V(0, 5, 13), look = V(-0.5, 4.4, 0), fov = 55 },
			to = { offset = V(-0.4, 5, 10), look = V(-0.8, 4.8, 0), fov = 55 } },
	},
	moves = {
		bob = {
			{ t = 0, anchor = "board", p = V(-7, 0, 0), r = 45 },
			{ t = 6.2, anchor = "door", p = V(0, 0, -1.5), r = 90 },
		},
		inv1 = { { t = 0, anchor = "board", p = V(-12, 0, -1.5), r = 30 } },
		inv2 = { { t = 0, anchor = "board", p = V(-2.5, 0, -1.5), r = 20 } },
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
		{ "hero", L.offer, 0.5, 3.4 },
		{ "bob", L.haOffer, 3.6, 6.2 },
		{ "inv2", L.haha, 4.4, 6.2 },
		{ "hero", L.rue, 13.2, 16.21 },
	},
	fx = {
		{ text = "BOING!", anchor = "door", p = V(11, 3.5, 3), t0 = 7.25, t1 = 8.25 },
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
	cues = { { 0.05, "music" }, { 3.6, "laugh" }, { 7.25, "boing" }, { 7.3, "thud" } },
}

SCENES.payoff = {
	length = 17.0,
	shots = {
		{ 0, 1.6, "door", from = { offset = V(4, 4, 15), look = V(2, 3, 0), fov = 60 } },
		{ 1.6, 3.8, "board", from = WIDE },
		-- live 25 Oct: the raised chart's top sat under the letterbox bar; aim higher
		{ 3.8, 6.6, "board", from = { offset = V(5, 5.8, 13), look = V(6, 5.3, 0), fov = 55 },
			to = { offset = V(5.5, 5.8, 12), look = V(6, 5.4, 0), fov = 55 } },
		{ 6.6, 9.0, "board", from = ONBOB, to = { offset = V(-7, 4.5, 7.5), look = V(-7, 4.4, 0), fov = 50 } },
		{ 9.0, 11.4, "board", from = WIDE },
		{ 11.4, 13.8, "door", from = OUTSIDE },
		{ 13.8, 17.0, "door", from = { offset = V(3, 4.5, 14), look = V(2, 3.5, 0), fov = 60 },
			to = { offset = V(2.5, 4.3, 12), look = V(2, 3.5, 0), fov = 60 } },
	},
	moves = {
		hero = {
			{ t = 0, anchor = "door", p = V(8, 0, 2), r = -90 },
			{ t = 1.6, p = V(0.5, 0, 0.5), move = "linear" },
			{ t = 1.61, anchor = "board", p = V(12, 0, 0), r = -90 },
			{ t = 2.4, p = V(7, 0, 0), move = "linear" },
			{ t = 2.41, r = -60 },
			{ t = 11.4, anchor = "door", p = V(0, 0, -1), r = 90 },
			-- live 25 Oct: side-on in the dark doorway the cheer's fists vanished; turn to us, step into the light
			{ t = 13.8, r = 90 },
			{ t = 14.15, p = V(0, 0, 0.8), r = 10, move = "out" },
		},
		bob = {
			{ t = 0, anchor = "board", p = V(-7, 0, 0), r = 45, roll = 0 },
			{ t = 11.4, anchor = "door", p = V(0.8, 1, 0), r = -90, roll = 0 },
			{ t = 12.35, p = V(11, 0, 3), roll = 450, move = "arc", h = 3.5 },
			{ t = 13.2, roll = 90 },
			{ t = 13.8, roll = 0, move = "out" },
		},
		inv1 = { { t = 0, anchor = "board", p = V(-12, 0, -1.5), r = 30 } },
		inv2 = { { t = 0, anchor = "board", p = V(-2.5, 0, -1.5), r = 20 } },
	},
	looks = {
		hero = {
			{ t = 0, pose = "walk", face = "determined", vis = true },
			{ t = 1.61, face = "smug" },
			{ t = 2.4, pose = "stand" },
			{ t = 3.8, pose = "holdChart" },
			{ t = 9.0, pose = "stand" },
			{ t = 11.4, pose = "kick", face = "determined" },
			{ t = 11.85, pose = "stand" },
			{ t = 13.8, pose = "cheer", face = "grin" },
		},
		bob = {
			{ t = 0, pose = "laugh", face = "laugh", vis = true },
			{ t = 6.6, pose = "stand", face = "shock" },
			{ t = 9.0, pose = "throw" },
			{ t = 11.4, pose = "fly" },
			{ t = 12.35, pose = "lie", face = "dizzy" },
			{ t = 13.2, pose = "sit" },
		},
		inv1 = { { t = 0, pose = "laugh", face = "laugh", vis = true }, { t = 6.6, pose = "stand", face = "shock" }, { t = 11.4, vis = false } },
		inv2 = { { t = 0, pose = "laugh", face = "laugh", vis = true }, { t = 6.6, pose = "stand", face = "shock" }, { t = 11.4, vis = false } },
	},
	bubbles = {
		{ "bob", L.whatHere, 2.0, 3.8 },
		{ "bob", L.what, 7.0, 9.0 },
		{ "bob", L.takeIt, 9.2, 11.3 },
	},
	fx = {
		{ text = "x3", anchor = "board", p = V(0, 7, -1), t0 = 9.5, t1 = 11.4 },
		{ text = "BOING!", anchor = "door", p = V(11, 3.5, 3), t0 = 12.35, t1 = 13.35 },
		{ text = L.proved, anchor = "door", p = V(4, 7.5, 0), t0 = 14.2, t1 = 17.01 },
		{ kind = "stars", follow = "bob", t0 = 12.35, t1 = 17.01 },
	},
	vals = {
		door = { { t = 0, v = 0 }, { t = 0.8, v = 0 }, { t = 1.0, v = 1 } },
		tape = { { t = 0, v = 0 }, { t = 0.45, v = 0 }, { t = 1.2, v = 1 } },
		lid = { { t = 0, v = 0 } },
		glow = { { t = 0, v = 0 } },
		chart = { { t = 0, v = 0 }, { t = 4.2, v = 0 }, { t = 5.6, v = 1 } },
		chartShown = { { t = 0, v = 0 }, { t = 3.79, v = 0 }, { t = 3.8, v = 1 }, { t = 9.19, v = 1 }, { t = 9.2, v = 0 } },
		glasses = { { t = 0, v = 0 }, { t = 6.7, v = 0 }, { t = 7.2, v = 1 } },
		pick = { { t = 0, v = 0 }, { t = 6.8, v = 0 }, { t = 7.4, v = 1 } },
		bills = { { t = 0, v = 0 }, { t = 9.2, v = 0 }, { t = 10.8, v = 1 } },
		confetti = { { t = 0, v = 0 }, { t = 13.8, v = 0 }, { t = 17.0, v = 1 } },
		handoff = { { t = 0, v = 0 }, { t = 15.8, v = 0 }, { t = 16.4, v = 1 } },
	},
	shakes = { { 11.4, 11.9, 0.6 } },
	cues = { { 0.05, "music" }, { 2.0, "laugh" }, { 9.2, "money" }, { 12.35, "boing" }, { 12.4, "thud" }, { 13.85, "victory" } },
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
	return { offset = a.offset:Lerp(b.offset, x), look = a.look:Lerp(b.look, x), fov = a.fov + (b.fov - a.fov) * x }
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
		cam = { offset = shot.from.offset, look = shot.from.look, fov = shot.from.fov }
	else
		cam = lerpCam(shot.from, shot.to, EASE.inout(clamp01((t - shot[1]) / (shot[2] - shot[1]))))
	end
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
		table.insert(f.fx, { text = x.text, kind = x.kind or "text", anchor = x.anchor, pos = x.p, follow = x.follow, k = k })
	end
	for k, keys in pairs(s.vals) do f.vals[k] = valAt(keys, t) end
	f.door, f.tape, f.lid, f.glow, f.handoff = f.vals.door or 0, f.vals.tape or 0, f.vals.lid or 0, f.vals.glow or 0, f.vals.handoff or 0

	if not reduced then
		for _, sh in ipairs(s.shakes) do
			if t >= sh[1] and t < sh[2] then f.shake = sh[3] * (1 - (t - sh[1]) / (sh[2] - sh[1])) end
		end
	end
	return f
end

-- sound cues whose time falls in (t0, t1]
function BobScript.cues(name, t0, t1)
	local out = {}
	for _, c in ipairs(scene(name).cues) do
		if c[1] > t0 and c[1] <= t1 then table.insert(out, c[2]) end
	end
	return out
end

return BobScript
