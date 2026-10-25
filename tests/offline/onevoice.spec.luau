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

-- 24 Oct, live (HQ 5 save at the laptop, app ready): HOLD TO CODE and the folded LAUNCH chip were the
-- one voice, but IpoClient's GO PUBLIC! card ("Ring the bell on the Valley Exchange") stayed up beside
-- them, a second instruction. A milestone button is a goal-level ask: it shows only on a calm screen
test("GO PUBLIC (a milestone ask) shows only when the goal speaks or nothing does", function()
	assert(V.milestoneOk("goal") and V.milestoneOk(nil), "a calm screen, or the goal speaking: it shows")
	assert(not V.milestoneOk("verb") and not V.milestoneOk("job") and not V.milestoneOk("launch"), "a button, the job in hand or LAUNCH!: it waits")
end)

-- 24 Oct, live (at the laptop with a job waiting): HOLD TO CODE was the one voice, but an investor's
-- phone banner ("Hana · Paper Plane / Hey, it's Hana at Paper Plane...") slid in beside it for ~7 s,
-- a second voice. A banner waits under a button or the job in hand; it shows when the voice drops
test("a phone banner waits under a button or the job in hand, and shows beside the goal or LAUNCH!", function()
	assert(V.phoneOk(nil) and V.phoneOk("goal") and V.phoneOk("launch"), "a calm screen, the goal or LAUNCH!: it shows")
	assert(not V.phoneOk("verb") and not V.phoneOk("job"), "HOLD TO CODE / GIVE up, or the job in hand: it waits")
end)

test("held phone banners: the newest one per thread, at most PHONE_HELD in all, no burst", function()
	local held = {}
	V.holdBanner(held, 5, { text = "Hey, it's Hana at Paper Plane." })
	V.holdBanner(held, 5, { text = "Sent you a term sheet: $900" })
	assert(#held == 1 and held[1].text == "Sent you a term sheet: $900", "one per thread: the term sheet replaces the opener")
	V.holdBanner(held, "desk", { text = "Your VIP is here" })
	V.holdBanner(held, "call", { text = "Call ended" })
	assert(#held == V.PHONE_HELD and V.PHONE_HELD == 2, "at most " .. tostring(V.PHONE_HELD) .. " held")
	assert(held[1].key == "desk" and held[2].key == "call", "the oldest goes first (the badge still counts it)")
	V.holdBanner(held, "desk", { text = "Your VIP left" })
	assert(held[1].key == "call" and held[2].text == "Your VIP left", "a newer one moves to the back")
end)

-- 24 Oct (F-6, doctor FEEL "cards over cards" at HQ 18/43/100): coachOk let a tip show while the goal
-- spoke, so two instructions were on screen and the tip's card landed on the goal pill. A tip is an
-- instruction: while it shows it is the voice ("tip", under a button, the job and LAUNCH!, over the
-- goal) and the goal folds to its 44 px icon, as it does under a button or LAUNCH!
test("a coach tip on screen is the voice: the goal folds to its icon until GOT IT", function()
	local p = V.pick({ tip = true, goal = true })
	assert(p.voice == "tip", "the tip speaks over the goal")
	assert(p.goal == "icon" and p.marker == false, "the goal folds to its icon, no marker")
	assert(V.folds("tip"), "GuideClient folds the card under a tip")
	assert(V.count(p, 0) == 1, "one instruction: the tip (the goal's words are folded)")
	assert(V.pick({ verb = "code", tip = true, goal = true }).voice == "verb", "a button still beats a tip")
	assert(V.pick({ carrying = true, tip = true, goal = true }).voice == "job", "the job in hand still beats a tip")
	assert(V.pick({ launch = true, tip = true, goal = true }).voice == "launch", "LAUNCH! (with its own tip) stays the voice")
	assert(V.coachOk("tip", "Rail.Column.BagButton"), "the tip does not hide itself for being the voice")
	assert(not V.milestoneOk("tip"), "GO PUBLIC waits for GOT IT")
	assert(V.phoneOk("tip"), "a phone banner may come (the tip steps aside for any banner: Notify.busy)")
	assert(V.prompt(p, "ask", true) == "off" and V.prompt(p, "world", false) == "draw", "no ask beside a tip; the way stays")
end)

-- 24 Oct (doctor FEEL "cards over cards" at hq:5, 1074 x 376): Quest.Holder.Quest under PhoneNotify.Banner,
-- 1,936 px2. phoneOk lets a banner in beside the goal (and LAUNCH!), and both use the top row: two
-- things talking at once. A banner on screen is the voice "phone" (where a tip sits: under a button,
-- the job and LAUNCH!, over the tip and the goal); the goal folds to its icon until it leaves
test("a phone banner on screen is the voice: the goal folds to its icon until it leaves", function()
	local p = V.pick({ phone = true, goal = true })
	assert(p.voice == "phone", "the banner speaks over the goal")
	assert(p.goal == "icon" and p.marker == false, "the goal folds to its icon, no marker")
	assert(V.folds("phone"), "GuideClient folds the card under a banner")
	assert(V.count(p, 0) == 1, "one voice: the banner (the goal's words are folded)")
	assert(V.pick({ phone = true, tip = true, goal = true }).voice == "phone", "a tip steps aside for a banner (Notify.busy)")
	assert(V.pick({ verb = "code", phone = true, goal = true }).voice == "verb", "a button still beats a banner")
	assert(V.pick({ carrying = true, phone = true, goal = true }).voice == "job", "the job in hand still beats a banner")
	assert(V.pick({ launch = true, phone = true, goal = true }).voice == "launch", "LAUNCH! stays the voice beside a banner")
	assert(V.phoneOk("phone"), "the banner does not hide itself for being the voice (it would flicker out and back)")
	assert(not V.coachOk("phone", "Rail.Column.BagButton") and not V.milestoneOk("phone"), "a tip and GO PUBLIC wait for it")
	assert(V.prompt(p, "ask", true) == "off" and V.prompt(p, "world", false) == "draw", "no ask beside a banner; the way stays")
end)

-- the same finding, measured from the code: the pill's holder is fitted below the money line (UIKit.fitMenu
-- puts its top at y 106 on a 376 px screen), the banner slides to y 96 and is 78 tall, centred (380 wide).
-- The folded icon sat wholly under it: 44 x 44 = 1,936 px2, the doctor's number. So folding alone is not
-- enough; the banner drops below the goal card when its usual row would cover it
local function overlaps(a, b)   -- the doctor's rule (DoctorProbes.ui): > 6 px both ways
	local ox = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
	local oy = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
	return ox > 6 and oy > 6
end
test("a phone banner keeps off the goal card's icon (the doctor's > 6 px rule)", function()
	local banner = { x = 347, y = 96, w = 380, h = 78 }
	local icon = { x = 515, y = 106, w = 44, h = 44 }
	assert(overlaps(banner, icon), "the hq:5 finding: on its usual row the banner covers the icon")
	local y = V.bannerY(banner, icon)
	assert(not overlaps({ x = banner.x, y = y, w = banner.w, h = banner.h }, icon), "moved, it does not")
	assert(y == 106 + 44 + V.BANNER_GAP, "just below the icon, not further down the screen")
	assert(y + banner.h <= 376 - 118, "still above the bottom action slot (LAUNCH! / HOLD TO CODE)")
	local pill = { x = 387, y = 64, w = 300, h = 44 }
	assert(not overlaps({ x = banner.x, y = V.bannerY(banner, pill), w = banner.w, h = banner.h }, pill), "the open pill too")
	assert(V.bannerY(banner, nil) == 96, "no goal card on screen: the usual row")
	assert(V.bannerY(banner, { x = 20, y = 106, w = 44, h = 44 }) == 96, "a goal card off to the side: the usual row")
end)

-- 24 Oct: the incoming-call card (PhoneNotify.Incoming) rests on the banner's row (y 96) and lands on the
-- goal card the same way. While it rings it is the voice "phone" too (the goal folds), and its row keeps
-- clear by the same rule (bannerY). It still shows under a button or the job in hand: a call times out in
-- 25 s, so holding it would turn it into a missed call. The button stays the voice there (the order holds)
test("an incoming call on screen is the voice: the goal folds and its card keeps off the goal", function()
	local p = V.pick({ ring = true, goal = true })
	assert(p.voice == "phone", "the ringing card speaks over the goal")
	assert(p.goal == "icon" and p.marker == false, "the goal folds to its icon, no marker")
	assert(V.count(p, 0) == 1, "one voice: the call (the goal's words are folded)")
	assert(V.pick({ ring = true, tip = true, goal = true }).voice == "phone", "a tip steps aside for a call")
	assert(V.pick({ verb = "code", ring = true, goal = true }).voice == "verb", "a button still beats a call (the order holds)")
	assert(V.pick({ midJob = true, ring = true, goal = true }).voice == "job", "the job in hand still beats a call")
	local card = { x = 347, y = 96, w = 380, h = 80 }   -- centreOn(ringCard, 380, 320, 80, 96)
	local icon = { x = 515, y = 106, w = 44, h = 44 }
	assert(overlaps(card, icon), "on its usual row the call covers the folded icon")
	local y = V.bannerY(card, icon)
	assert(not overlaps({ x = card.x, y = y, w = card.w, h = card.h }, icon), "moved, it does not")
	assert(y + card.h <= 376 - 118, "still above the bottom action slot")
	assert(V.bannerY(card, nil) == 96, "no goal card on screen: the usual row")
end)

-- P-5 (25 Oct): while Bob's cutscene plays nothing else speaks (spec 5: "One voice")
test("nothing speaks while a Bob scene plays", function()
	local p = V.pick({ scene = true, verb = "code", carrying = true, launch = true, phone = true, tip = true, goal = true })
	assert(p.voice == "scene", tostring(p.voice))
	assert(p.goal == "hidden" and p.launch == nil and p.marker == false, "goal hidden, no LAUNCH, no marker")
	assert(V.phoneOk(p.voice) == false, "phone banners wait")
	assert(V.milestoneOk(p.voice) == false, "GO PUBLIC waits")
	assert(V.coachOk(p.voice, nil) == false, "coach tips wait")
	-- live 25 Oct: the goal's world marker and its "94m behind" edge arrow showed during the intro
	assert(V.folds(p.voice) == true, "the goal folds: no world marker, no edge arrow")
end)

return T
