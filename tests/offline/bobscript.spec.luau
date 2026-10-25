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
	local want = { B.LINES.offer, B.LINES.haOffer, B.LINES.haha, B.LINES.rue }
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
	for _, w in ipairs({ "What are YOU doing here?", "W-WHAT?!", "Take it! TAKE IT ALL!", "Who's laughing now?" }) do
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

-- 25 Oct: the payoff gained the iPad close-up (Luke's review): 8 shots
test("hard cuts: shots run in order, 6 in the intro, 8 in the payoff", function()
	for name, n in pairs({ intro = 6, payoff = 8 }) do
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

test("cues fire once", function()
	local n = {}
	local t, step = 0, 1 / 60
	while t < B.length("intro") do
		for _, c in ipairs(B.cues("intro", t, t + step)) do n[c] = (n[c] or 0) + 1 end
		t += step
	end
	for _, id in ipairs({ "music", "laugh", "boing", "thud" }) do
		assert(n[id] == 1, id .. " fired " .. tostring(n[id]))
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
		whatHere = "What are YOU doing here?", what = "W-WHAT?!", takeIt = "Take it! TAKE IT ALL!",
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
	local a, b = B.at("payoff", 6.6, false).cam.fov, B.at("payoff", 6.85, false).cam.fov
	assert(a > 45 and b < 32, ("zoom %.0f -> %.0f"):format(a, b))
end)

return T
