--[[ doctor.spec.luau -- the game doctor's judging, checked offline.

	The doctor is only useful if its verdicts are right: a failed check must become
	a finding with the right severity, the same problem on four HQ levels must be
	ONE finding, "new" and "fixed" must compare like with like, and the Discord
	message must never pass Discord's 2,000-character limit. Plus the two
	per-frame rules the client probes count with (DoctorProbes). ]]
local D = require("../../tools/doctor_lib")
local P = require("../../src/ReplicatedStorage/DoctorProbes")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local function report(extra)
	local r = { steps = {
		{ name = "world", checks = { { name = "sinking surfaces", ok = true, measured = 0, expected = 0 } } },
		{ name = "hq:9", checks = {
			{ name = "cards over cards", ok = false, severity = "FEEL", measured = 2, expected = 0 },
			{ name = "lift lands you on a floor", ok = false, severity = "BUG", measured = 1, expected = 0, detail = "F8 fell" } } },
		{ name = "hq:18", checks = { { name = "lift lands you on a floor", ok = false, severity = "BUG", measured = 1, expected = 0 } } },
		{ name = "chase:genius", checks = {
			{ name = "the chase ran", ok = false, severity = "BLOCKER", measured = "no result" },
			{ name = "outcome (robot rides straight)", ok = true, info = true, measured = "caught" } } },
	} }
	for k, v in pairs(extra or {}) do r[k] = v end
	return r
end

test("failed checks become findings, worst first; infos are kept apart", function()
	local f, infos = D.findings(report())
	assert(#f == 4, ("want 4 findings, got %d"):format(#f))
	assert(f[1].severity == "BLOCKER" and f[#f].severity == "FEEL", "not sorted worst first")
	assert(#infos == 1 and infos[1].measured == "caught", "the chase outcome should be an info row, not a finding")
	local crashed = D.findings(report({ crashed = "boom" }))
	assert(crashed[1].key == "run / crashed", "a crashed run must be the first finding")
end)

test("the same problem on several HQ levels is one finding; new and fixed compare families", function()
	local f = D.findings(report())
	local d = D.diff({ "hq:5 / lift lands you on a floor", "hq:5 / stand on every storey" }, f)
	assert(#d.still == 1 and d.still[1].name == "lift lands you on a floor", "the lift drop on hq:9 and hq:18 is the same one as hq:5's")
	assert(#d.new == 2, ("want 2 new families (the chase, the cards), got %d"):format(#d.new))
	assert(#d.fixed == 1 and d.fixed[1] == "hq / stand on every storey", "standing was fixed since the last run")
end)

test("the Discord message stays under the limit and leads with the verdict", function()
	local f = D.findings(report())
	local long = {}
	for i = 1, 40 do
		table.insert(long, { key = "hq:" .. i .. " / thing " .. i, step = "hq:" .. i, name = "thing " .. i, severity = "BUG",
			measured = i, expected = 0, detail = string.rep("x", 300) })
	end
	local text = D.discord(long, D.diff({}, long), "Sun 11 Oct")
	assert(#text <= D.DISCORD_MAX, ("%d characters"):format(#text))
	local t2 = D.discord(f, D.diff({}, f), "Sun 11 Oct")
	assert(t2:find("^%*%*Game doctor%*%* RED"), "a BLOCKER makes the verdict RED")
	assert(D.discord({}, D.diff({}, {}), "x"):find("Nothing found", 1, true), "an empty run should say so")
end)

test("a camera cut and a hunter hitch, frame by frame", function()
	assert(P.isCut(12, 0) and P.isCut(0, 60), "a 12-stud jump or a 60 degree turn in one frame is a cut")
	assert(not P.isCut(1.2, 4), "following a runner at 20 studs/s is not a cut")
	assert(P.isStutter(0.3, 2.1), "a step that jumps from 0.3 to 2.1 studs is a visible hitch")
	assert(not P.isStutter(0.3, 0.4), "steady running is not a hitch")
end)

-- 3 Nov: the `input` step. The routine clicks each button by name through Studio's real input path and
-- presses Q; the client lists the visible buttons after each input. These rules turn that into verdicts.
local function with(list, extra)
	local out = table.clone(list)
	for _, v in ipairs(extra) do table.insert(out, v) end
	return out
end
local HUD = { "Hud.RateHit", "Rail.Column.BagButton", "Rail.Column.MoreButton", "Rail.Column.PhoneButton", "Quest.Holder.Quest.Hit" }
local TRAY = { "Rail.Tray.TeamButton", "Rail.Tray.IndexButton", "Rail.Tray.DailyButton" }
local BAG = { label = "BAG", path = "Rail.Column.BagButton" }
local TEAM = { label = "TEAM", path = "Rail.Tray.TeamButton", tray = true }
local function C(sig, top) return { kind = "click", sig = sig, top = top } end   -- one input the client saw
local function K(sig) return { kind = "key", key = "Q", sig = sig } end
local function find(checks, name)
	for _, c in ipairs(checks) do if c.name == name then return c end end
	return nil
end

test("input: the plan opens the tray first only when a tray button is hidden, and always ends on Q", function()
	local p = P.handsPlan(BAG, HUD)
	assert(#p == 2 and p[1].click == "Rail.Column.BagButton" and p[2].key == "Q", "BAG: click it, then Q")
	p = P.handsPlan(TEAM, HUD)
	assert(#p == 3 and p[1].click == "Rail.Column.MoreButton" and p[2].click == TEAM.path and p[3].key == "Q",
		"TEAM with the tray shut: MORE, TEAM, Q")
	p = P.handsPlan(TEAM, with(HUD, TRAY))
	assert(#p == 2 and p[1].click == TEAM.path, "TEAM with the tray already open: no MORE (it would shut the tray)")
end)

test("input: a button that opens its screen and Q that shuts it pass", function()
	local opened = with(HUD, { "Bag.Panel.Close", "Bag.Panel.Grid.Item_coffee" })
	local checks, left = P.judgeHands(BAG, P.handsPlan(BAG, HUD), HUD, { C(opened, BAG.path), K(HUD) })
	assert(find(checks, "BAG opens its screen").ok, "BAG opened two buttons")
	assert(find(checks, "Q closes BAG").ok, "Q took them away again")
	assert(#left == 0, "nothing left open")
end)

test("input: a covered button is a BUG that names what took the click", function()
	local checks = P.judgeHands(BAG, P.handsPlan(BAG, HUD), HUD,
		{ C(HUD, "TrialBlocker.TextButton"), K(HUD) })
	local c = find(checks, "BAG opens its screen")
	assert(c and not c.ok and c.severity == "BUG", "nothing opened: BUG")
	assert(c.detail and c.detail:find("TrialBlocker", 1, true), "the detail names what the click landed on")
	assert(find(checks, "Q closes BAG") == nil, "no Q verdict when nothing opened")
end)

test("input: Q that leaves the screen open is a FEEL, and the open buttons are handed back for cleanup", function()
	local opened = with(HUD, { "Bag.Panel.Close" })
	local checks, left = P.judgeHands(BAG, P.handsPlan(BAG, HUD), HUD, { C(opened, BAG.path), K(opened) })
	local c = find(checks, "Q closes BAG")
	assert(c and not c.ok and c.severity == "FEEL", "still open after Q: FEEL")
	assert(#left == 1 and left[1] == "Bag.Panel.Close", "the cleanup gets the button still open")
end)

test("input: through the tray, MORE opens it and the tray's own buttons do not count as TEAM's screen", function()
	local trayOpen = with(HUD, TRAY)
	local team = with(HUD, { "Team.Panel.Close", "Team.Panel.List.Row1" })
	local checks = P.judgeHands(TEAM, P.handsPlan(TEAM, HUD), HUD,
		{ C(trayOpen, P.MORE), C(team, TEAM.path), K(HUD) })
	assert(find(checks, "MORE opens the tray").ok, "the tray buttons appeared after MORE")
	local c = find(checks, "TEAM opens its screen")
	assert(c.ok and c.measured == 2, ("TEAM opened 2 buttons of its own, measured %s"):format(tostring(c.measured)))
	assert(find(checks, "Q closes TEAM").ok, "Q shut it")
	local onlyTray = P.judgeHands(TEAM, P.handsPlan(TEAM, HUD), HUD, { C(trayOpen, P.MORE), C(trayOpen, TEAM.path), K(HUD) })
	assert(not find(onlyTray, "TEAM opens its screen").ok, "the tray staying open is not TEAM opening")
end)

-- live run 3 Nov: the quest card steps aside while the tray is open and comes back with BUILD's screen;
-- it was counted as BUILD's own button, so "Q closes BUILD" failed with only the quest card "still open"
test("input: a button that was on screen before the round is never the screen's own", function()
	local noQuest = {}
	for _, v in ipairs(with(HUD, TRAY)) do if v ~= "Quest.Holder.Quest.Hit" then table.insert(noQuest, v) end end
	local build = with(HUD, { "BuildMode.CatalogBar.Header.Close" })
	local checks, left = P.judgeHands(TEAM, P.handsPlan(TEAM, HUD), HUD,
		{ C(noQuest, P.MORE), C(build, TEAM.path .. ".Icon"), K(HUD) })
	local c = find(checks, "TEAM opens its screen")
	assert(c.ok and c.measured == 1, ("only the catalog's button is new, measured %s"):format(tostring(c.measured)))
	assert(find(checks, "Q closes TEAM").ok and #left == 0, "the quest card coming back is not the screen left open")
end)

-- review round 1: a slow routine is the harness, not the game. It must not be a BUG (the PR gate fails
-- on a BUG main lacks), and the step must stop: a late input would land in the next round
-- gate run 3 Nov: after the doctor's fresh save the tray hides TEAM and BUILD, and DAILY and FEEDBACK
-- sit where they were. A click aimed at hidden TEAM opened DAILY and passed as "TEAM opens its screen"
test("input: a click that landed on another button fails, even when a screen opened", function()
	local trayOpen = with(HUD, TRAY)
	local daily = with(HUD, { "Daily.Panel.Header.Close", "Daily.Panel.Body.Claim" })
	local checks = P.judgeHands(TEAM, P.handsPlan(TEAM, HUD), HUD,
		{ C(trayOpen, P.MORE), C(daily, "Rail.Tray.DailyButton"), K(HUD) })
	local c = find(checks, "TEAM opens its screen")
	assert(c and not c.ok and c.severity == "BUG", "DAILY's screen is not TEAM's")
	assert(c.detail:find("Rail.Tray.DailyButton", 1, true), "the detail names the button it landed on")
end)

-- review round 2: the cleanup clicked Close by name seconds after it was last seen; a panel that closed
-- itself by then leaves that spot to another button (the TEAM -> DAILY mistake again)
test("input: a button is only clicked while it is on screen, and a click counts only on that button", function()
	local shown = with(HUD, { "Feedback.Panel.Header.Close" })
	assert(P.canClick("Feedback.Panel.Header.Close", shown, {}), "on screen and switched on: click it")
	assert(not P.canClick("Feedback.Panel.Header.Close", HUD, {}), "gone from the screen: do not click its spot")
	assert(not P.canClick("Feedback.Panel.Header.Close", shown, { "Feedback.Panel.Header.Close" }), "switched off: do not click")
	assert(P.landedOn("Rail.Tray.TeamButton.Icon", "Rail.Tray.TeamButton"), "its icon is the button")
	assert(not P.landedOn("Rail.Tray.TeamButtonX", "Rail.Tray.TeamButton"), "a name that only starts the same is not")
	assert(not P.landedOn(nil, "Rail.Tray.TeamButton"), "nothing under the mouse is not the button")
end)

test("input: inputs that did not all arrive stop the step as not checked, never as a game BUG", function()
	local checks, _, arrived = P.judgeHands(TEAM, P.handsPlan(TEAM, HUD), HUD, { C(with(HUD, TRAY)) })
	assert(arrived == false, "1 of 3 inputs is not a round that arrived")
	local c = find(checks, "the clicks and keys reached the game")
	assert(c and c.ok and c.info and c.severity == nil and c.measured == "1 of 3", "an info row, 1 of 3, no severity")
	assert(find(checks, "TEAM opens its screen") == nil, "no verdict on a click that never arrived")
end)

test("input: the last round's late Q arriving first is out of order, not this round's click", function()
	local _, _, arrived = P.judgeHands(BAG, P.handsPlan(BAG, HUD), HUD, { K(HUD), C(HUD) })
	assert(arrived == false, "a key where the plan has a click means the inputs are out of step")
	local _, _, ok = P.judgeHands(BAG, P.handsPlan(BAG, HUD), HUD, { C(with(HUD, { "Bag.Panel.Close" }), BAG.path), K(HUD) })
	assert(ok == true, "click then Q, as planned, arrived")
end)

-- 3 Nov (Luke's call): TELL US opens with the cursor in its box, so there Q is a letter, not a close.
-- The doctor checks that Q went to the box and the panel stayed; Q closing it mid-sentence, or Q
-- doing nothing with the cursor elsewhere (the box lost it, or no Q key), is a FEEL.
test("input: on a typing screen Q goes into the box and the panel stays, and that passes", function()
	local FB = { label = "FEEDBACK", path = "Rail.Tray.FeedbackButton", tray = true, types = true }
	local tray = with(HUD, { FB.path })
	local open = with(tray, { "Feedback.Panel.Header.Close", "Feedback.Panel.Send" })
	local typed = { kind = "key", key = "Q", sig = open, typing = true }
	local checks, left = P.judgeHands(FB, P.handsPlan(FB, tray), tray, { C(open, FB.path), typed })
	assert(find(checks, "Q types into FEEDBACK's box").ok, "the Q went to the box and the panel stayed")
	assert(find(checks, "Q closes FEEDBACK") == nil, "no close verdict on a typing screen")
	assert(#left == 2, "still open, so the cleanup clicks its Close")
	local shut = { kind = "key", key = "Q", sig = tray, typing = true }
	local c = find((P.judgeHands(FB, P.handsPlan(FB, tray), tray, { C(open, FB.path), shut })), "Q types into FEEDBACK's box")
	assert(not c.ok and c.severity == "FEEL", "Q shut the panel while the player was typing")
	local astray = { kind = "key", key = "Q", sig = open, typing = false }
	c = find((P.judgeHands(FB, P.handsPlan(FB, tray), tray, { C(open, FB.path), astray })), "Q types into FEEDBACK's box")
	assert(not c.ok and c.severity == "FEEL", "the cursor was not in the box, and Q did not close it either")
	assert(P.HANDS[7].label == "FEEDBACK" and P.HANDS[7].types == true, "TELL US is marked a typing screen")
end)

-- 24 Oct (art pass 4, Task 1): the C3 review room is built to order, so every entry must be a room
-- that department may really have at that level, and the camera must stand inside every room
local TP = require("../../src/ReplicatedStorage/TowerPlan")
local WP = require("../../src/ServerScriptService/WaferPlan")

test("C3: every review room is a real segment its department may have, built by its hq level", function()
	assert(type(P.REVIEW_ROOM) == "table", "Probes.REVIEW_ROOM is missing")
	local n = 0
	for dept, rr in pairs(P.REVIEW_ROOM) do
		n += 1
		local pc = WP.PIECES[rr.L]
		assert(pc and pc.kind == "segment", dept .. ": L" .. tostring(rr.L) .. " is not a segment")
		local ok = false
		for _, d in ipairs(WP.allowed(rr.L)) do if d == dept then ok = true end end
		assert(ok, ("%s is not allowed at L%d"):format(dept, rr.L))
		assert(rr.L <= rr.hq, dept .. ": the room is above the level the scenario builds")
		if dept ~= "lobby" then assert(pc.seg == 3, dept .. ": not a seg 3 room (the station must be in view)") end
	end
	assert(n == 7, "one review room per department (7), got " .. n)
end)

test("C3: the camera stands inside every office room, head high, and looks across toward +X", function()
	assert(type(P.roomCam) == "function", "Probes.roomCam is missing")
	for s = 0, 13 do
		if not TP.DECKS[s] then
			for seg = 1, 8 do
				local r = TP.room(s, seg)
				local inn = TP.inner(r)
				local eye, at = P.roomCam(r)
				assert(math.abs(eye.X) <= inn.x and math.abs(eye.Z) <= inn.z, ("storey %d seg %d: the eye is outside the room"):format(s, seg))
				assert(eye.Y >= 5 and eye.Y <= 8, ("storey %d seg %d: the eye is %.1f high"):format(s, seg, eye.Y))
				assert(math.abs(at.X) <= r.w / 2 and math.abs(at.Z) <= r.d / 2 and at.Y > 0, ("storey %d seg %d: looks out of the room"):format(s, seg))
				assert(at.X - eye.X > 0, ("storey %d seg %d: does not look toward +X (the glass on the right)"):format(s, seg))
			end
		end
	end
end)

return T
