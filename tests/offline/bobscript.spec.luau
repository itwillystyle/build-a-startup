-- bobscript.spec.luau: Bob's two cutscenes as data (BobScript), 25 Oct 2026.
-- spec: docs/superpowers/specs/2026-10-25-bob-first-boss-investor-design.md (3a, 3e, 5, 5b-1)
-- storyboard: ui/storyboards/p5-bob (option A, Luke's pick, and D, the payoff)
local B = require("../../src/ReplicatedStorage/BobScript")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local DT = 0.1
local function sweep(name, fn, reduced)
	local t = 0
	while t <= B.length(name) + 1e-9 do
		fn(B.at(name, t, reduced == true), t)
		t += DT
	end
end

test("intro is 15 to 17 s and payoff is at most 20 s", function()
	local a, d = B.length("intro"), B.length("payoff")
	assert(a >= 15 and a <= 17, "intro " .. a)
	assert(d <= 20, "payoff " .. d)
end)

test("intro words are exact, in order", function()
	local seen, order = {}, {}
	sweep("intro", function(f)
		for _, b in ipairs(f.bubbles) do
			if b.k > 0 and not seen[b.text] then seen[b.text] = true; table.insert(order, b.text) end
		end
	end)
	local want = { B.LINES.offer, B.LINES.haOffer, B.LINES.rue }
	assert(#order == #want, "got " .. table.concat(order, " | "))
	for i, w in ipairs(want) do assert(order[i] == w, ("%d: %s ~= %s"):format(i, order[i], w)) end
	assert(B.LINES.offer == "Can I get an offer?" and B.LINES.rue == "He will rue the day.", "exact copy")
end)

test("payoff words are exact", function()
	local seen = {}
	sweep("payoff", function(f)
		for _, b in ipairs(f.bubbles) do if b.k > 0 then seen[b.text] = true end end
		for _, x in ipairs(f.fx) do if x.k > 0 and x.text then seen[x.text] = true end end
	end)
	for _, w in ipairs({ "You AGAIN?", "I've got an offer for YOU.", "HAHAHA!", "W-WHAT?!", "TAKE IT ALL!", "Who's laughing now?" }) do
		assert(seen[w], "missing: " .. w)
	end
end)

test("hero's faces go hope, sad, shock, dizzy, sad, determined", function()
	local order = {}
	sweep("intro", function(f)
		local face = f.actors.hero.face
		if order[#order] ~= face then table.insert(order, face) end
	end)
	local want = { "hope", "sad", "shock", "dizzy", "sad", "determined" }
	assert(table.concat(order, ",") == table.concat(want, ","), table.concat(order, ","))
end)

test("shake only on the kick, and never reduced", function()
	local onKick, offKick = false, false
	sweep("intro", function(f, t)
		if f.shake > 0 then
			if t >= 6.3 and t <= 6.8 then onKick = true else offKick = true end
		end
	end)
	assert(onKick and not offKick, "shake on the kick only")
	sweep("intro", function(f) assert(f.shake == 0, "reduced: no shake") end, true)
	sweep("payoff", function(f) assert(f.shake == 0, "reduced: no shake (payoff)") end, true)
end)

test("reduced: the camera holds still inside a shot", function()
	for _, name in ipairs({ "intro", "payoff" }) do
		local first = {}
		sweep(name, function(f)
			local s = first[f.shot]
			if not s then first[f.shot] = f.cam return end
			assert(s.offset == f.cam.offset and s.look == f.cam.look and s.fov == f.cam.fov,
				("%s shot %d moved under Reduce Motion"):format(name, f.shot))
		end, true)
	end
end)

-- 25 Oct: the payoff's story grew in Luke's reviews (the iPad close-up, the laugh, the laugh dying): 11
test("hard cuts: shots run in order, 6 in the intro, 11 in the payoff", function()
	for name, n in pairs({ intro = 6, payoff = 11 }) do
		local last, count = 0, 0
		sweep(name, function(f)
			assert(f.shot >= last, name .. " shot went back")
			if f.shot ~= last then count += 1 end
			last = f.shot
		end)
		assert(count == n, ("%s has %d shots"):format(name, count))
	end
end)

test("the end frame is the hand-off", function()
	local a = B.at("intro", B.length("intro"), false)
	assert(a.handoff == 1 and a.actors.hero.face == "determined", "intro ends handed off, determined")
	local d = B.at("payoff", B.length("payoff"), false)
	assert(d.handoff == 1 and d.actors.hero.face == "grin", "payoff ends handed off, grinning")
	assert(B.at("intro", 0, false).handoff == 0, "starts not handed off")
end)

-- every cue, every bubble pop and every voice starts exactly once when the scene plays frame by frame
test("every sound fires once", function()
	for _, name in ipairs({ "intro", "payoff" }) do
		local fired, t, step = 0, 0, 1 / 60
		while t < B.length(name) do
			fired += #B.cues(name, t, t + step)
			t += step
		end
		local want = #B.cues(name, -1, B.length(name))
		assert(fired == want and want > 10, ("%s: %d fired, %d in the script"):format(name, fired, want))
	end
end)

-- Luke 25 Oct: "I've got an offer for you" sat on Bob's close-up after the cut. A line ends in its shot
test("no bubble runs across a cut", function()
	for _, name in ipairs({ "intro", "payoff" }) do
		local last = {}
		sweep(name, function(f, t)
			for _, b in ipairs(f.bubbles) do
				if b.k > 0 then
					if last[b.text] and last[b.text] ~= f.shot then
						error(("%s: %q runs from shot %d into shot %d at %.1f s"):format(name, b.text, last[b.text], f.shot, t))
					end
					last[b.text] = f.shot
				end
			end
		end)
	end
end)

-- every sound name the scenes use is wired to a real id in Sfx (a missing one is silent, not an error),
-- and carries what was measured from its file: where its sound starts (most library files open on
-- dead air: the laugh 0.5 s, the wah-wahs up to 1.2 s) and the trim that brings it to one loudness
test("every sound has an id, a start and a trim", function()
	local Sfx = require("../../src/ReplicatedStorage/Sfx")
	for _, name in ipairs({ "intro", "payoff" }) do
		local ids = {}
		for _, c in ipairs(B.cues(name, -1, B.length(name))) do ids[c.id] = true end
		for _, bed in ipairs(B.beds(name)) do ids[bed[1]] = true end
		for id in pairs(ids) do
			local s = B.SOUND[id]
			assert(s and Sfx.ID[s[1]], ("%s uses %q, which has no Sfx id"):format(name, id))
			assert(s.at and s.at >= 0 and s.len and s.len > 0, id .. ": no measured start and length")
			assert(s.gain and s.gain > 0 and s.gain <= 8, id .. ": no loudness trim")
		end
	end
end)

-- Luke 25 Oct ("sloppy"): in the payoff Bob and the investors laughed on screen from 5.4 to 9.6 s,
-- but the laugh SOUND ended at 6.8 and 7.8: two seconds of silent laughing, then a record scratch
-- that stopped nothing. A laugh is heard for as long as one is seen
local LAUGHS = { laughBig = true, laughBob = true, chuckleDeep = true, invLaughA = true, invLaughB = true, invLaughC = true }
test("a laugh is heard as long as one is seen", function()
	for _, span in ipairs({ { "intro", 3.7, 6.15 }, { "payoff", 5.7, 9.55 } }) do
		local name, t = span[1], span[2]
		while t <= span[3] do
			local heard = false
			for _, s in ipairs(B.sounding(name, t)) do if LAUGHS[s] then heard = true end end
			assert(heard, ("%s at %.2f s: they laugh on screen and nobody is heard"):format(name, t))
			t += 0.05
		end
	end
end)

-- the gag: the scratch kills the music and the laughing, the crickets play in silence, then the stab
test("the record scratch stops everything; the crickets play alone", function()
	local function has(t, id)
		for _, s in ipairs(B.sounding("payoff", t)) do if s == id then return true end end
		return false
	end
	assert(has(9.5, "music"), "the music plays up to the scratch")
	local t = 10.3   -- the scratch itself rings 0.63 s (measured from its file)
	while t <= 10.95 do
		for _, s in ipairs(B.sounding("payoff", t)) do
			assert(s == "crickets", ("%.2f s: %q plays over the crickets"):format(t, s))
		end
		assert(has(t, "crickets"), ("%.2f s: no crickets"):format(t))
		t += 0.05
	end
	assert(has(11.1, "shock"), "the stab lands on W-WHAT")
end)

-- talking pushes the music down (it sat 20 dB over the cartoon sounds, measured 25 Oct)
test("the music ducks under talking", function()
	local music
	for _, b in ipairs(B.beds("payoff")) do if b[1] == "music" then music = b end end
	local open, under = B.bedLevel("payoff", music, 1.0), B.bedLevel("payoff", music, 4.5)
	assert(open > 0 and under <= open * 0.6, ("music %.2f, under talk %.2f"):format(open, under))
end)

-- a voice fades out with its bubble (a hard stop chopped mid-note); only a laugh may run on
test("no voice outlasts its bubble, and none is chopped", function()
	for _, name in ipairs({ "intro", "payoff" }) do
		for _, c in ipairs(B.cues(name, -1, B.length(name))) do
			if c.bubble and not LAUGHS[c.id] then
				assert(c.dur and c.dur <= c.bubble + 1e-6, ("%s: %q runs %.2f s past a %.2f s bubble"):format(name, c.id, c.dur or -1, c.bubble))
			end
			if c.dur then assert(c.fade and c.fade > 0, ("%s: %q stops dead"):format(name, c.id)) end
		end
	end
end)

test("no tobacco words", function()
	for k, v in pairs(B.LINES) do
		local s = string.lower(v)
		for _, bad in ipairs({ "cigar", "cigarette", "smoke", "vape" }) do
			assert(not s:find(bad, 1, true), k .. " mentions " .. bad)
		end
	end
end)

test("every line in the spec is in LINES, verbatim", function()
	local want = {
		offer = "Can I get an offer?", haOffer = "HA! An OFFER?", haha = "HAHAHA!", rue = "He will rue the day.",
		text = "...Ok. I may have been hasty. Come to my office.", task = "Go to Bob's office",
		youAgain = "You AGAIN?", myOffer = "I've got an offer for YOU.", what = "W-WHAT?!", takeIt = "TAKE IT ALL!",
		laughing = "Who's laughing now?", toast = "SERIES A CLOSED · x3", taped = "Bob isn't taking meetings... yet.",
		trophy = "BOB'S TOOTHPICK",
	}
	for k, v in pairs(want) do assert(B.LINES[k] == v, k .. ": " .. tostring(B.LINES[k])) end
end)

-- 25 Oct (Luke: "inside the object"): nobody in the boardroom stands inside the table
-- (measured live: it covers x -9.6..1.6, z -8.1..-0.3 from the anchor); 1 stud of body radius
test("nobody stands inside the boardroom table", function()
	for _, name in ipairs({ "intro", "payoff" }) do
		sweep(name, function(f, t)
			for id, a in pairs(f.actors) do
				if a.anchor == "board" and a.visible then
					local p = a.pos
					local inside = p.X > -9.6 - 1 and p.X < 1.6 + 1 and p.Z > -8.1 - 1 and p.Z < -0.3 + 1
					assert(not inside, ("%s %s at %.1f s stands in the table (%.1f, %.1f)"):format(name, id, t, p.X, p.Z))
				end
			end
		end)
	end
end)

test("the payoff door falls flat and stays down; the snap zoom lands in under 0.3 s", function()
	assert(B.at("payoff", 0, false).doorDown == 0, "shut at the start")
	assert(B.at("payoff", 1.5, false).doorDown == 1, "flat after the kick")
	assert(B.at("payoff", 16, false).doorDown == 1, "still down at the end")
	local a, b = B.at("payoff", 11.0, false).cam.fov, B.at("payoff", 11.25, false).cam.fov
	assert(a > 45 and b < 32, ("zoom %.0f -> %.0f"):format(a, b))
end)

-- Luke 25 Oct: the laugh has to DIE before "W-WHAT?!" (the back-to-earth beat): Bob laughs at your
-- offer, is not laughing by the time the line has shot up, and is deadpan before the shock
test("the payoff: they laugh at your offer, the laugh dies after the iPad, then the shock", function()
	local function bob(t) return B.at("payoff", t, false).actors.bob end
	assert(bob(6.0).pose == "laugh", "laughing at the offer")
	assert(B.at("payoff", 9.4, false).vals.chart == 1, "the line is up by 9.4")
	assert(bob(10.6).pose == "laughdie" and bob(10.6).face == "deadpan", "deadpan before the shock")
	assert(bob(11.2).face == "shock", "then the shock")
end)

-- every boardroom camera stands inside the room (Luke 25 Oct: "it looks like a set" from outside the
-- cut-away wall; the front wall's inner face is 11 studs in front of the anchor)
test("boardroom cameras stand inside the room", function()
	for _, name in ipairs({ "intro", "payoff" }) do
		sweep(name, function(f, t)
			if f.cam.anchor == "board" then
				assert(f.cam.offset.Z < 11 and math.abs(f.cam.offset.X) < 13.5,
					("%s at %.1f s: camera at (%.1f, %.1f)"):format(name, t, f.cam.offset.X, f.cam.offset.Z))
			end
		end)
	end
end)

-- Luke 25 Oct: "too much text may be too much noise". One bubble on screen at a time, six words at
-- most, and each one up long enough to read (0.8 s + 0.04 s a character)
test("speech is short, one bubble at a time, and up long enough to read", function()
	for _, name in ipairs({ "intro", "payoff" }) do
		sweep(name, function(f, t)
			local on = 0
			for _, b in ipairs(f.bubbles) do if b.k > 0 then on += 1 end end
			assert(on <= 1, ("%s at %.1f s: %d bubbles at once"):format(name, t, on))
		end)
	end
	local B2 = require("../../src/ReplicatedStorage/BobScript")
	for _, name in ipairs({ "intro", "payoff" }) do
		local seen = {}
		local t = 0
		while t <= B2.length(name) do
			for _, b in ipairs(B2.at(name, t, false).bubbles) do
				if b.k > 0 then
					local s = seen[b.text] or { t0 = t, t1 = t }
					s.t1 = t
					seen[b.text] = s
				end
			end
			t += 0.05
		end
		for text, s in pairs(seen) do
			local words = select(2, text:gsub("%S+", ""))
			assert(words <= 6, ("%q has %d words"):format(text, words))
			local need = 0.8 + 0.04 * #text
			assert(s.t1 - s.t0 + 0.05 >= need, ("%q is up %.2f s, needs %.2f"):format(text, s.t1 - s.t0 + 0.05, need))
		end
	end
end)

return T
