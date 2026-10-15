-- liftplan.spec.luau: the lift's rules (15 Oct 2026, HQ project #1 part 1b). Spec:
-- silicon-startup/docs/superpowers/specs/2026-10-15-hq-lift-1b-design.md
local T = require("../../src/ReplicatedStorage/TowerPlan")
local LP = require("../../src/ReplicatedStorage/LiftPlan").with(T)   -- pure modules take their sibling (StaffAction.with)
local W = require("../../src/ServerScriptService/WaferPlan")
local TT = {}
local function test(name, fn) table.insert(TT, { name = name, fn = fn }) end
local function near(a, b) return math.abs(a - b) < 1e-6 end

test("ride time: 1 s per floor, never over 4 s; no ride for no floors", function()
	assert(LP.rideTime(0) == 0, "0 floors")
	assert(near(LP.rideTime(1), 1) and near(LP.rideTime(3), 3), "1 s per floor")
	assert(near(LP.rideTime(4), 4) and near(LP.rideTime(11), 4), "capped at 4 s")
end)

test("ticks: one per floor passed, evenly spread, the last one loud", function()
	local tk = LP.ticks(3)
	assert(#tk == 3, "3 floors, 3 ticks")
	assert(not tk[1].loud and not tk[2].loud and tk[3].loud, "only the last is loud")
	assert(near(tk[3].t, LP.rideTime(3)), "the last tick lands on arrival")
	local long = LP.ticks(11)
	assert(#long == 11 and near(long[11].t, 4), "11 floors in 4 s")
	assert(#LP.ticks(0) == 0, "no ticks for no ride")
end)

test("easing: starts at 0, ends at 1, never leaves 0..1", function()
	assert(LP.alpha(0, 3) == 0 and LP.alpha(3, 3) == 1 and LP.alpha(9, 3) == 1 and LP.alpha(-1, 3) == 0, "ends")
	assert(LP.alpha(1, 0) == 1, "a zero-length ride is already there")
	local last = -1
	for i = 0, 30 do local a = LP.alpha(i / 10, 3); assert(a >= last, "monotone"); last = a end
end)

test("stops: exactly the landable storeys, bottom to top, with their ids", function()
	for _, level in ipairs({ 2, 9, 13, 18, 43, 100 }) do
		local stops = LP.stops(W.PIECES, level)
		local want = {}
		for s = 0, T.TOP do if T.landable(W.PIECES, level, s) then table.insert(want, s) end end
		assert(#stops == #want, ("level %d: %d stops, want %d"):format(level, #stops, #want))
		for i, st in ipairs(stops) do
			assert(st.storey == want[i], "order")
			assert(st.id == LP.stopId(st.storey), "id")
		end
	end
	assert(LP.stopId(0) == "L" and LP.stopId(14) == "R" and LP.stopId(7) == "F7", "ids")
	assert(#LP.stops(W.PIECES, 100) == 12, "the full tower has 12 stops")
end)

test("trophy sockets: every possible stop once; lit exactly where there is a stop, at every level", function()
	local all = LP.sockets(W.PIECES, 100)
	assert(#all == 12, "12 sockets")
	for _, sk in ipairs(all) do assert(not T.DECKS[sk.storey], "a garden is not a socket") end
	for level = 2, W.MAX do
		local lit = 0
		for _, sk in ipairs(LP.sockets(W.PIECES, level)) do
			if sk.built then lit += 1 end
			assert(sk.built == T.landable(W.PIECES, level, sk.storey), ("level %d storey %d"):format(level, sk.storey))
		end
		assert(lit == #LP.stops(W.PIECES, level), "lit sockets = stops at level " .. level)
	end
end)

test("queue: riders inside go first, then calls in order; arriving clears that stop", function()
	local cab = LP.newCab(1)
	LP.call(cab, 5); LP.call(cab, 3); LP.call(cab, 5)
	assert(#cab.calls == 2, "a repeated call is one call")
	assert(LP.target(cab) == 5, "calls in order")
	LP.pick(cab, 2)
	assert(LP.target(cab) == 2, "a pick from inside goes first")
	LP.arrive(cab, 2)
	assert(cab.at == 2 and LP.target(cab) == 5, "arrived, next call")
	LP.call(cab, 2)
	LP.arrive(cab, 5); LP.arrive(cab, 3)
	assert(LP.target(cab) == 2, "the call made while away is still served")
	LP.arrive(cab, 2)
	assert(LP.target(cab) == nil, "nothing left")
end)

test("calls for stops that no longer exist are dropped (a spin-off leaves only the lobby)", function()
	local cab = LP.newCab(7)
	LP.call(cab, 9); LP.pick(cab, 3); LP.call(cab, 1)
	LP.prune(cab, 1)
	assert(cab.at == 1, "the cab is moved onto a stop that exists")
	assert(#cab.calls == 1 and cab.calls[1] == 1 and #cab.picks == 0, "only stop 1 survives")
end)

test("rare events: never on the first 3 rides, never twice in a row, about 1 in 12, capacity always", function()
	assert(LP.rareEvent(0, false, 1, 0.0) == nil and LP.rareEvent(2, false, 1, 0.0) == nil, "quiet first rides")
	assert(LP.rareEvent(3, false, 1, 0.0) == "calm", "a low roll after 3 rides: calm")
	assert(LP.rareEvent(3, false, 1, LP.EVENT_ODDS * 0.75) == "pride", "a mid roll: pride")
	assert(LP.rareEvent(3, false, 1, LP.EVENT_ODDS) == nil, "a high roll: nothing")
	assert(LP.rareEvent(9, true, 1, 0.0) == nil, "never twice in a row")
	assert(LP.rareEvent(0, true, LP.MAX_RIDERS + 1, 0.9) == "capacity", "over capacity always says so")
	assert(LP.rareEvent(5, false, LP.MAX_RIDERS, 0.9) == nil, "6 riders is not over")
	assert(near(LP.EVENT_ODDS, 1 / 12) and LP.MAX_RIDERS == 6 and LP.QUIET_RIDES == 3, "the spec's numbers")
end)

test("drawStep: while moving the cab is drawn at an absolute height; once it stops the client never moves it", function()
	-- moving, halfway: from wherever the cab is drawn now, step to the eased height
	assert(near(LP.drawStep(true, 0, 90, 2, 4, 0), 45), "halfway from the start floor")
	assert(near(LP.drawStep(true, 0, 90, 2, 4, 40), 5), "already drawn at 40: only the rest")
	-- the server's final position replicated a frame early: the step is tiny, not a whole ride
	assert(math.abs(LP.drawStep(true, 0, 90, 3.99, 4, 90)) < 0.01, "server already at the top")
	-- arrived: the server's resting cab is the truth, whatever height it was drawn at
	assert(LP.drawStep(false, 0, 90, 5, 4, 90) == 0, "arrival never drags the cab back down")
	assert(LP.drawStep(false, 0, 90, 5, 4, 0) == 0, "idle cab is left alone")
end)

-- final review fixes (15 Oct). Positions are local to the cab: x across, y up from the cab floor,
-- z toward the doors (the door line is z = CAB.d / 2)
local C = T.CAB
local LINE = C.d / 2

test("I4 doorway: only a true straddle holds the doors; a rider a step inside does not", function()
	assert(LP.doorZone(0, 3.4, LINE) == "line", "on the door line")
	assert(LP.doorZone(0, 3.4, LINE - 0.5) == "line" and LP.doorZone(0, 3.4, LINE + 0.8) == "line", "within the band")
	assert(LP.doorZone(0, 3.4, LINE - 1.2) == "in", "a step inside is a rider, not a blocker (the old band held to 1.6)")
	assert(LP.doorZone(0, 3.4, LINE + 1.3) == "out", "a step out on the landing does not hold the cab")
	assert(LP.doorZone(0, 3.4, 0) == "in" and LP.doorZone(0, 3.4, -LINE) == "in", "the middle and the back")
	assert(LP.doorZone(C.door / 2 + 2, 3.4, LINE) == "out", "beside the doors on the landing")
	assert(LP.doorZone(0, 3.4 + 18, LINE) == "out" and LP.doorZone(0, 3.4 - 18, LINE) == "out", "another floor's doorway")
end)

test("I4 the list opens only well inside, so the tap that picks a floor is never a doorway hold", function()
	assert(not LP.listOpens(LINE - 0.5) and not LP.listOpens(LINE - 1.9), "near the doors: no list yet")
	assert(LP.listOpens(LINE - 2) and LP.listOpens(0), "2 studs in: the list")
	for z = -LINE, LINE - 2, 0.25 do assert(LP.doorZone(0, 3.4, z) == "in", "wherever the list is open, you are a rider") end
end)

test("I4 a hold has a limit, then the doors are cleared", function()
	assert(not LP.holdExpired(LP.HOLD_MAX - 0.1) and LP.holdExpired(LP.HOLD_MAX), "the limit")
	assert(LP.HOLD_MAX <= 10, "one player cannot keep a lift forever")
end)

test("I3 reseat: a rider left in the shaft (below the cab floor or on its roof) is put back; anyone else is not", function()
	assert(LP.reseat(0, -14, 0), "fell below the cab (a stalled client on a ride up)")
	assert(LP.reseat(1, C.h + 3.4, -2), "standing on the cab roof (a stalled client on a ride down)")
	assert(not LP.reseat(0, 3.4, 0), "standing in the cab")
	assert(not LP.reseat(0, 3.4, LINE + 1.5), "walked out onto the landing")
	assert(not LP.reseat(0, -14, LINE + 3), "below, but out on the landing side: not in the shaft")
end)

test("I2 stranded riders: only a cut-short ride from just now is re-seated, never one from minutes ago", function()
	local a, b = { name = "a" }, { name = "b" }
	local list = LP.fresh({ { player = a, t = 100 }, { player = b, t = 40 } }, 101, LP.STRANDED_MAX)
	assert(#list == 1 and list[1] == a, "the old entry is dropped")
	assert(#LP.fresh(nil, 101, LP.STRANDED_MAX) == 0, "no list")
	assert(LP.STRANDED_MAX <= 3, "a same-moment rebuild only")
end)

test("I1 a rebuild during a ride or a door cycle leaves the doors as the ride had them", function()
	local open, settle = LP.afterRebuild(false, nil, "F7")
	assert(open == "F7" and settle, "idle cab: open at its stop and settle there")
	open, settle = LP.afterRebuild(true, nil, "F7")
	assert(open == nil and not settle, "closing or moving: every door stays shut, nothing moves")
	open, settle = LP.afterRebuild(true, "F3", "F3")
	assert(open == "F3" and not settle, "dwelling with doors open: the new leaves open there")
end)

test("room label: the department with the most built rooms; ties to the lowest seg; the specials", function()
	local depts = {}
	local storey3 = {}
	for _, pc in ipairs(W.PIECES) do if pc.kind == "segment" and pc.storey == 3 then storey3[pc.seg] = pc.level end end
	depts[storey3[1]], depts[storey3[2]], depts[storey3[8]] = "studio", "eng", "eng"
	assert(LP.roomLabel(W.PIECES, depts, 100, 3) == "ENG", "two eng beat one studio")
	depts[storey3[8]] = "studio"
	assert(LP.roomLabel(W.PIECES, depts, 100, 3) == "STUDIO", "a tie goes to seg 1's department")
	assert(LP.roomLabel(W.PIECES, depts, storey3[1] - 1, 3) == "FLOOR 3", "no rooms built yet")
	assert(LP.roomLabel(W.PIECES, {}, 100, 0) == "LOBBY" and LP.roomLabel(W.PIECES, {}, 100, 14) == "ROOF GARDEN", "specials")
end)

return TT
