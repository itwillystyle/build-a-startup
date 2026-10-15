-- lobbymoment.spec.luau: the garage-to-lobby moment's timeline (15 Oct 2026, HQ part 1c). Spec:
-- silicon-startup/docs/superpowers/specs/2026-10-15-hq-garage-1c-design.md
local LM = require("../../src/ReplicatedStorage/LobbyMoment")
local TT = {}
local function test(name, fn) table.insert(TT, { name = name, fn = fn }) end
local function near(a, b, e) return math.abs(a - b) < (e or 1e-6) end

test("the whole moment is at most 4.5 s and every step ends inside it", function()
	assert(LM.TOTAL <= 4.5, "4.5 s cap")
	for _, s in ipairs(LM.STEPS) do
		assert(s.from < s.to and s.to <= LM.TOTAL, s.group .. " inside the moment")
		if s.outFrom then assert(s.outFrom >= s.to and s.outTo <= LM.TOTAL, s.group .. " leaves inside the moment") end
	end
	for _, snd in ipairs(LM.SOUNDS) do assert(snd.t >= 0 and snd.t <= LM.TOTAL, "sound " .. snd.key .. " inside") end
end)

test("the order: scaffold, the garage folds, columns, glass, roof, canopy", function()
	local order = {}
	for _, s in ipairs(LM.STEPS) do order[s.group] = s.from end
	assert(order.scaffold < order.garage and order.garage < order.columns and order.columns < order.glass, "first half")
	assert(order.glass < order.roof and order.roof < order.canopy, "second half")
end)

test("the camera's shots add up to the moment and start and end on the player", function()
	local last = 0
	for i, s in ipairs(LM.SHOTS) do if i > 1 then assert(s.arrive > last, "shots in order"); last = s.arrive end end
	assert(near(last, LM.TOTAL), "the last shot arrives at TOTAL")
	assert(LM.SHOTS[1].at == "start" and LM.SHOTS[#LM.SHOTS].at == "player", "from the player and back")
end)

test("the sting is the loudest sound and lands as the roof lands", function()
	local roof, loudest
	for _, s in ipairs(LM.STEPS) do if s.group == "roof" then roof = s end end
	for _, snd in ipairs(LM.SOUNDS) do if not loudest or snd.volume > loudest.volume then loudest = snd end end
	assert(near(loudest.t, roof.to), "the sting is on the roof's landing")
end)

test("at(): nothing before its step, exactly in place after, a small overshoot on the way", function()
	for _, s in ipairs(LM.STEPS) do
		assert(LM.at(s.group, s.from - 0.01) == 0 or s.from == 0, s.group .. " not there before")
		if not s.outFrom then assert(LM.at(s.group, s.to) == 1 and LM.at(s.group, LM.TOTAL) == 1, s.group .. " in place after") end
		local peak = 0
		for k = 0, 100 do peak = math.max(peak, LM.at(s.group, s.from + (s.to - s.from) * k / 100)) end
		assert(peak <= 1.08, s.group .. " overshoots at most 8%")
	end
	assert(LM.ease(0) == 0 and near(LM.ease(1), 1), "ease ends")
end)

test("the scaffold comes and goes; skip (any time past the end) gives the end state", function()
	assert(LM.at("scaffold", 1.0) == 1, "scaffold up in the middle")
	assert(LM.at("scaffold", LM.TOTAL) == 0 and LM.at("scaffold", math.huge) == 0, "scaffold gone at the end")
	for _, g in ipairs({ "garage", "columns", "glass", "roof", "canopy" }) do
		assert(LM.at(g, math.huge) == 1, g .. " done")
	end
	assert(LM.at("floor", 0) == 1, "the floor never moves")
end)

test("groupOf: the lobby's parts by name", function()
	assert(LM.groupOf("Column") == "columns", "columns")
	assert(LM.groupOf("RoofBand") == "roof" and LM.groupOf("Ceiling") == "roof", "roof")
	assert(LM.groupOf("LobbyCanopy") == "canopy" and LM.groupOf("SignBoard") == "canopy", "canopy")
	assert(LM.groupOf("Floor") == "floor" and LM.groupOf("Deck") == "floor", "the floor stays")
	assert(LM.groupOf("Wall") == "glass" and LM.groupOf("EdgeGlass") == "glass", "everything else rises with the glass")
end)

test("foldSide: the garage's walls fold out on their own side; the roof, the shell and props lift away", function()
	local hw, hd = 11, 8
	assert(LM.foldSide(10.8, 0, 0.4, 10, 16, hw, hd) == "px", "right wall")
	assert(LM.foldSide(-10.8, 0, 0.4, 10, 16, hw, hd) == "nx", "left wall")
	assert(LM.foldSide(0, 7.8, 22, 10, 0.4, hw, hd) == "pz", "front wall")
	assert(LM.foldSide(0, -7.8, 22, 10, 0.4, hw, hd) == "nz", "back wall")
	assert(LM.foldSide(0, 0, 23, 0.6, 17, hw, hd) == "lift", "the roof (a thin slab) lifts away")
	-- look review (15 Oct): the garage's look is one shell mesh; lifting it read as "gone", not a fold
	assert(LM.foldSide(0, 0, 24, 11, 18, hw, hd) == "squash", "a shell spanning the whole garage collapses flat")
	assert(LM.foldSide(-8, 5, 1.8, 1.6, 1.6, hw, hd) == "lift", "a box")
end)

test("look: the garage falls (slow, then faster) once the wide shot has landed (about 1 s)", function()
	local g
	for _, st in ipairs(LM.STEPS) do if st.group == "garage" then g = st end end
	assert(g.from >= 0.9, "it waits for the camera (Cine reaches the wide shot at about 1.06 s)")
	assert(LM.at("garage", (g.from + g.to) / 2) < 0.5, "it eases in: under half way at half time")
	assert(LM.at("garage", g.to) == 1, "and lands flat")
end)

test("look: shots are planned by when they really arrive (Cine eases the whole flight)", function()
	assert(math.abs(LM.cineTime(1.0) - 0.6) < 0.05, "Cine reaches its 0.6 s mark at about 1.0 s (measured 1.06)")
	assert(LM.cineTime(0) == 0 and math.abs(LM.cineTime(LM.TOTAL) - LM.TOTAL) < 1e-6, "same ends")
	local roof
	for _, st in ipairs(LM.STEPS) do if st.group == "roof" then roof = st end end
	-- the wide shot holds until after the roof lands; the look-up arrives after the sting
	assert(LM.SHOTS[3].arrive >= roof.to + 0.1, "still wide when the roof lands")
	assert(LM.SHOTS[4].arrive > roof.to, "the look-up comes after the sting")
	local t = LM.shotTimes()
	local sum = 0
	for i = 2, #t do sum += t[i] end
	assert(near(sum, LM.TOTAL), "Cine's shot times add up to the moment")
end)

test("look: no camera shot is planned near the ground (Cine's curve dips below a shot: at 2 studs it went to 0)", function()
	for i, s in ipairs(LM.SHOTS) do
		if s.pos then assert(s.pos[2] >= 5, "shot " .. i .. " is at least 5 studs up") end
		if s.pos and s.pos[2] < 12 then assert(s.pos[3] <= 80, "low shot " .. i .. " is close enough to read the lobby (z <= 80)") end
	end
end)

test("I3: the garage copy leaves the floor out (it stays; it would flicker and rise through the desk)", function()
	assert(LM.inCopy("GarageFloor") == false, "the garage floor is not copied")
	assert(LM.inCopy("Wall") and LM.inCopy("Dressing") and LM.inCopy("Roof"), "walls, dressing and the roof are")
end)

return TT
