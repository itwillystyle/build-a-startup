-- onevoice.spec.luau: one instruction on screen at a time (rule A, "one voice"), run outside Studio.
-- 24 Oct: the playtest 2026-10-20_04-46-03 had three asks at once at 7:44 (the card "Drive to The
-- Residences", the button HOLD TO CODE, a floating UPGRADE), LAUNCH! stacked on the job at 2:44,
-- and a card that changed every 2-6 s. Board: ui/animation-review/judge/ONE-INSTRUCTION-OPTIONS.md.
local V = require("../../src/ReplicatedStorage/OneVoice")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

test("the button you can press: GIVE by your client, HOLD TO CODE at the laptop with a job", function()
	assert(V.verbOf({ carrying = true, canGive = true }) == "give", "by your client with the app: GIVE")
	assert(V.verbOf({ carrying = true, canGive = false, jobWaiting = true, atLaptop = true }) == nil,
		"carrying an app you cannot code another; away from the client there is no button")
	assert(V.verbOf({ jobWaiting = true, atLaptop = true }) == "code", "at the laptop with a job: HOLD TO CODE")
	assert(V.verbOf({ jobWaiting = false, atLaptop = true }) == nil, "nothing to code: no button")
	assert(V.verbOf({ jobWaiting = true, atLaptop = false }) == nil, "a job but away from the laptop: no button")
	assert(V.verbOf({}) == nil, "nothing: no button")
end)

test("the ladder: a button beats the job, the job beats LAUNCH!, LAUNCH! beats the goal", function()
	local p = V.pick({ verb = "code", midJob = true, launch = true, goal = true })
	assert(p.voice == "verb" and p.verb == "code", "the button speaks")
	assert(p.goal == "icon" and p.launch == "chip" and p.marker == false, "the goal folds, LAUNCH waits as a chip, no marker")

	p = V.pick({ carrying = true, launch = true, goal = true })
	assert(p.voice == "job", "the app in your hands")
	assert(p.goal == "words", "the card names the job (the server's goal is give/finish mid-job)")
	assert(p.launch == "chip" and p.marker == true, "LAUNCH waits; the marker shows where the job goes")

	p = V.pick({ launch = true, goal = true })
	assert(p.voice == "launch" and p.launch == "button" and p.goal == "icon" and p.marker == false, "hands free: LAUNCH!")

	p = V.pick({ goal = true })
	assert(p.voice == "goal" and p.goal == "words" and p.launch == nil and p.marker == true, "nothing else: the goal")

	p = V.pick({})
	assert(p.voice == nil and p.goal == "hidden", "nothing at all")
end)

test("the goal card reads the voice: it folds to its icon under a button or LAUNCH!, never under the job", function()
	assert(V.folds("verb") and V.folds("launch"), "a button or LAUNCH! folds the card")
	assert(not V.folds("job") and not V.folds("goal") and not V.folds(nil), "the job and the goal speak through the card")
	for _, st in ipairs({ { verb = "code", goal = true }, { carrying = true, goal = true }, { launch = true, goal = true }, { goal = true } }) do
		local p = V.pick(st)
		assert(V.folds(p.voice) == (p.goal == "icon"), "folds() and pick() disagree for " .. tostring(p.voice))
	end
end)

test("a started job or a recruit you carry is a job in your hands too", function()
	assert(V.pick({ midJob = true, launch = true, goal = true }).voice == "job", "a started job is in your hands")
	assert(V.pick({ recruit = true, launch = true, goal = true }).voice == "job", "a recruit you walk home is in your hands")
end)

test("the clock pauses exactly when LAUNCH is folded by the job or the button", function()
	assert(V.launchHeld({ carrying = true }), "carrying an app")
	assert(V.launchHeld({ midJob = true }), "a job you started coding")
	assert(V.launchHeld({ recruit = true }), "walking a recruit home")
	assert(V.launchHeld({ jobWaiting = true, atLaptop = true }), "at the laptop with a job: HOLD TO CODE is up")
	assert(not V.launchHeld({}), "hands free: LAUNCH! is up and its clock runs")
	assert(not V.launchHeld({ atLaptop = true }), "at the laptop with nothing to code: LAUNCH! is up")
	-- the rule is one rule on both sides: wherever the HUD would show the chip, the server pauses
	for _, a in ipairs({ { carrying = true, canGive = true }, { jobWaiting = true, atLaptop = true }, { midJob = true }, {} }) do
		local p = V.pick({ verb = V.verbOf(a), carrying = a.carrying, midJob = a.midJob, recruit = a.recruit, launch = true, goal = true })
		assert((p.launch == "chip") == V.launchHeld(a), "chip and pause disagree")
	end
end)

test("prompts never repeat the HUD button and only the goal's own ask prompt draws", function()
	assert(V.promptRole("HOLD TO CODE") == "code" and V.promptRole("GIVE") == "give", "the HUD verbs")
	assert(V.promptRole("UPGRADE") == "ask" and V.promptRole("BUILD") == "ask", "the asks that compete with the goal")
	assert(V.promptRole("Take the lift") == "world" and V.promptRole("RENAME") == "world" and V.promptRole("Drive") == "world", "the way to the goal is the world")

	local verb = V.pick({ verb = "code", goal = true })
	assert(V.prompt(verb, "code", false) == "quiet", "the laptop prompt: the HUD is its look, E still codes")
	assert(V.prompt(verb, "ask", true) == "off", "playtest 7:44: no UPGRADE beside HOLD TO CODE")
	assert(V.prompt(verb, "world", false) == "off", "E belongs to the button while it is up")
	assert(V.prompt(V.pick({ verb = "give", carrying = true, goal = true }), "give", false) == "quiet", "the GIVE prompt: the HUD GIVE is its look")

	local goal = V.pick({ goal = true })
	assert(V.prompt(goal, "ask", true) == "draw", "the goal's own UPGRADE pad")
	assert(V.prompt(goal, "ask", false) == "off", "a wing door you walk past is not the goal")
	assert(V.prompt(goal, "world", false) == "draw", "the lift and the car stay: they are the way")
	assert(V.prompt(goal, "code", false) == "quiet", "no HOLD TO CODE card with nothing to code")

	local job = V.pick({ carrying = true, goal = true })
	assert(V.prompt(job, "ask", true) == "off" and V.prompt(job, "world", false) == "draw", "carrying: no ask prompt, the lift stays")
	assert(V.prompt(V.pick({ launch = true, goal = true }), "ask", true) == "off", "LAUNCH! is up: no UPGRADE")
end)

test("coach tips wait for a calm screen, except the LAUNCH tip beside LAUNCH!", function()
	assert(V.coachOk("goal", "Rail.Column.BagButton") and V.coachOk(nil, "Hud.Launch"), "a calm screen takes a tip")
	assert(not V.coachOk("verb", "Rail.Column.BagButton") and not V.coachOk("job", "Hud.Launch"), "no tip beside a live button or a job")
	assert(V.coachOk("launch", "Hud.Launch") and not V.coachOk("launch", "Rail.Column.BagButton"), "only the LAUNCH tip beside LAUNCH!")
end)

-- the mock's 10 s (scenes/7-one-instruction.html, `facts`): walk to the laptop past the Design
-- Studio door, code the to-do app, LAUNCH is ready at 3.0 s mid-job, carry it, GIVE at 6.6, LAUNCH at 8.0
local TT = { arrive = 1.2, started = 1.6, ready = 3.0, shipped = 4.3, walk2 = 4.4, atClient = 6.0, give = 6.6, launch = 8.0 }
local function facts(t)
	local carrying = t >= TT.shipped and t < TT.give
	return {
		atLaptop = t >= TT.arrive and t < TT.walk2,
		jobWaiting = t < TT.shipped,
		midJob = t >= TT.started and t < TT.shipped,
		carrying = carrying,
		canGive = t >= TT.atClient and t < TT.give,
		ready = t >= TT.ready and t < TT.launch,
		nearDoor = t < 4.7 and t < TT.walk2,
	}
end
-- the server's goal text (refreshObjective): the job first, then a ready app, then the drive
local function goalKey(f)
	if f.carrying then return "give" end
	if f.midJob then return "finish" end
	if f.ready then return "product" end
	return "drive"
end

test("the mock's 10 s under rule A: never more than 1 instruction, the card's words change 2x", function()
	local words, changes, maxCount = nil, 0, 0
	for i = 0, 100 do
		local t = i / 10
		local f = facts(t)
		local p = V.pick({ verb = V.verbOf(f), carrying = f.carrying, midJob = f.midJob, launch = f.ready, goal = true })
		local drawn = (f.nearDoor and V.prompt(p, "ask", false) == "draw") and 1 or 0
		drawn += (f.canGive and V.prompt(p, "give", false) == "draw") and 1 or 0
		drawn += (f.atLaptop and V.prompt(p, "code", false) == "draw") and 1 or 0
		local n = V.count(p, drawn)
		maxCount = math.max(maxCount, n)
		assert(n <= 1, ("%d instructions at %.1f s"):format(n, t))
		if p.goal == "words" then
			local k = goalKey(f)
			if words and k ~= words then changes += 1 end
			words = k
		end
	end
	assert(maxCount == 1, "something is always on screen")
	assert(changes == 2, "the card's words changed " .. changes .. "x, want 2 (today: 4)")
end)

test("the clock in the mock pauses from ready to the GIVE: full time left when the hands come free", function()
	local LC = require("../../src/ServerScriptService/LaunchClock")
	local c = LC.new(TT.ready)
	for i = 30, 79 do   -- the server checks the moment the app is ready, then every 0.25 s
		local t = i / 10
		local f = facts(t)
		LC.update(c, t, V.launchHeld({ carrying = f.carrying, canGive = f.canGive, jobWaiting = f.jobWaiting,
			atLaptop = f.atLaptop, midJob = f.midJob }))
	end
	-- held 3.0-6.6 (the job, then the app, then GIVE), ran 6.6-7.9
	assert(math.abs(LC.left(c, 7.9) - (60 - 1.3)) < 0.01, "left at 7.9 s: " .. LC.left(c, 7.9))
end)

return T
