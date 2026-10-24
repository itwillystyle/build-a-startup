-- clientmood.spec.luau: the client's timer and the sad walk-off (ClientMood), 24 Oct 2026.
-- Luke's 20 Oct ask ("sad + ticking effects when an app isn't given in time"), option C:
-- ui/animation-review/judge/CLIENT-TIMER-OPTIONS.md. Red and a tick only in the last 8 s.
local M = require("../../src/ReplicatedStorage/ClientMood")
local MotionSpec = require("../../src/ReplicatedStorage/MotionSpec")
local Clients = require("../../src/ServerScriptService/Clients")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

test("red starts at exactly 8.0 s left, lost at 0", function()
	assert(M.stage(30) == "calm", "full")
	assert(M.stage(8.01) == "calm", "8.01 s is still calm")
	assert(M.stage(8.0) == "worried", "8.0 s is red")
	assert(M.stage(0.01) == "worried", "0.01 s is red")
	assert(M.stage(0) == "lost", "0 is lost")
	assert(M.stage(-0.1) == "lost", "below 0 is lost")
end)

test("red is seconds, not a share: a BIG client (45 s) goes red at 8 s too", function()
	local P, BIG = Clients.TUNE.PATIENCE, Clients.TUNE.BIG_PATIENCE
	assert(P == 30 and BIG == 45, "the real numbers moved: re-read the spec")
	assert(M.stage(M.leftOf(0.18, BIG)) == "calm", "0.18 of 45 = 8.1 s: calm")
	assert(M.stage(M.leftOf(0.17, BIG)) == "worried", "0.17 of 45 = 7.65 s: red")
	assert(M.stage(M.leftOf(0.27, P)) == "calm", "0.27 of 30 = 8.1 s: calm")
	assert(M.stage(M.leftOf(0.26, P)) == "worried", "0.26 of 30 = 7.8 s: red")
	assert(M.stage(M.leftOf(0.5, P)) == "calm", "half time left is calm (the old bar was gold here)")
end)

test("the badge counts 8, 7 ... 1 and shows nothing outside the last 8 s", function()
	assert(M.count(8.01) == nil, "no number before red")
	assert(M.count(8.0) == 8, "8.0 -> 8")
	assert(M.count(7.99) == 8, "7.99 -> 8")
	assert(M.count(7.0) == 7, "7.0 -> 7")
	assert(M.count(1.0) == 1, "1.0 -> 1")
	assert(M.count(0.01) == 1, "0.01 -> 1 (never 0 on screen)")
	assert(M.count(0) == nil, "lost: no number")
end)

test("a full 30 s wait ticks 8 times, at 8 .. 1, the last three high", function()
	local all = {}
	local left = 30
	for _ = 1, 400 do
		local now = left - 0.1
		for _, t in M.ticks(left, now) do table.insert(all, t) end
		left = now
		if left <= 0 then break end
	end
	assert(#all == 8, "ticks: " .. #all)
	for i, t in all do
		assert(t.n == 9 - i, ("tick %d was %d"):format(i, t.n))
		assert(t.hi == (t.n <= 3), ("tick %d hi"):format(t.n))
	end
end)

test("ticks: a big step crosses several seconds in order; time going back never ticks", function()
	local list = M.ticks(8.3, 6.5)
	assert(#list == 2 and list[1].n == 8 and list[2].n == 7, "8 then 7")
	assert(#M.ticks(7.5, 7.6) == 0, "a pause that corrects the guess up does not tick")
	assert(#M.ticks(9.5, 8.2) == 0, "nothing above 8")
	assert(#M.ticks(0.5, -0.2) == 0, "no tick at 0 (that is the leave)")
end)

test("the pie: 0 degrees gone at full, 180 at half, 360 at the end", function()
	assert(M.sweep(30, 30) == 0, "full")
	assert(math.abs(M.sweep(15, 30) - 180) < 1e-9, "half")
	assert(M.sweep(0, 30) == 360, "end")
	assert(M.sweep(40, 30) == 0 and M.sweep(-1, 30) == 360, "clamped")
	assert(M.sweep(10, 0) == 0, "no clock: nothing gone")
end)

test("the client guesses between server draws only while patience drains, by at most GUESS", function()
	assert(M.estimate(10, 0.2, true) == 10 - 0.2, "draining: counts down")
	assert(M.estimate(10, 3, true) == 10 - M.GUESS, "a missed update never runs the clock away")
	assert(M.estimate(10, 3, false) == 10, "paused (you are coding it, or carry it): holds")
	assert(M.estimate(0.1, 1, true) == 0, "never below 0")
	assert(M.GUESS <= 0.5, "two server draws at most")
end)

test("only one client ticks: the one nearest to running out", function()
	assert(M.ticker({ { key = "a", left = 6 }, { key = "b", left = 3 } }) == "b", "lowest wins")
	assert(M.ticker({ { key = "a", left = 12 }, { key = "b", left = 9 } }) == nil, "nobody red")
	assert(M.ticker({ { key = "a", left = 0 }, { key = "b", left = 7 } }) == "b", "a lost one does not tick")
	assert(M.ticker({}) == nil, "empty")
end)

test("the slump eases in over 0.4 s; under Reduce Motion it is held at once", function()
	assert(M.slump(0, false) == 0, "starts upright")
	assert(M.slump(M.SLUMP_IN, false) == 1, "fully slumped at 0.4 s")
	assert(M.slump(5, false) == 1, "held")
	local mid = M.slump(M.SLUMP_IN / 2, false)
	assert(mid > 0.5 and mid < 1, "eases out (fast, then settles): " .. mid)
	assert(M.slump(0, true) == 1, "Reduce Motion: a held pose, no motion")
	assert(M.slump(-1, false) == 0, "clock skew: upright")
end)

test("the sad walk is 0.7x the game's walk", function()
	assert(M.WALK == 10 and M.SAD_WALK == 7, "10 and 7 studs a second")
end)

test("the next client waits until the one leaving has said their line and stepped off the spot", function()
	local free = M.freeAt(100, M.SAY, M.WALK)
	assert(math.abs(free - (100 + 1.8 + M.CLEAR / 10)) < 1e-9, "say 1.8 s, then CLEAR studs at 10/s")
	local sad = M.freeAt(100, M.SAY, M.SAD_WALK)
	assert(sad > free, "a slow walk-off holds the spot longer")
	assert(M.walkDelay(100, free) > 1.8, "the moment after a hand-over: wait")
	assert(M.walkDelay(free + 1, free) == 0, "after: go at once")
	assert(M.walkDelay(100, nil) == 0, "a spot nobody held")
end)

test("client looks: a skin or hair the player wears is never picked", function()
	local avatar = { skin = 2, hair = { [111] = true } }
	assert(M.lookOk({ skin = 1, hair = 222 }, avatar), "different")
	assert(not M.lookOk({ skin = 2, hair = 222 }, avatar), "same skin")
	assert(not M.lookOk({ skin = 1, hair = 111 }, avatar), "same hair")
	assert(M.lookOk({ skin = 2, hair = 111 }, {}), "no avatar read: anything goes")
	local looks = { [50] = { skin = 2, hair = 9 }, [51] = { skin = 2, hair = 9 }, [52] = { skin = 4, hair = 9 } }
	local function lookOf(i) return looks[i] or { skin = 2, hair = 9 } end
	assert(M.pickIndex(50, lookOf, { skin = 2 }) == 52, "skips the two that match")
	assert(M.pickIndex(52, lookOf, { skin = 2 }) == 52, "keeps a good one")
	assert(M.pickIndex(60, lookOf, { skin = 2 }, 3) == 60, "gives up after `tries`, keeps the base")
end)

test("nearest skin tone", function()
	local pal = { { 234, 194, 158 }, { 120, 84, 56 }, { 90, 62, 44 } }
	assert(M.nearest({ 230, 190, 150 }, pal) == 1, "light")
	assert(M.nearest({ 95, 60, 40 }, pal) == 3, "dark")
end)

test("the beats follow MotionSpec: tick pop, colour, lost chip (UI moves <= 0.3 s)", function()
	local T0 = MotionSpec.T
	assert(M.POP.up == T0.press and M.POP.down == T0.fast, "pop over T.press, back over T.fast")
	assert(M.POP.to - 1 <= MotionSpec.SMALL_SCALE + 1e-9, "a small pop: Reduce Motion keeps it")
	assert(M.LOST.enter == T0.ui, "the chip fades in over T.ui")
	assert(M.LOST.enter <= 0.3 and M.LOST.leave <= 0.3, "UI moves stay under 300 ms")
	assert(M.LOST.hold >= 1, "the lost pay stays long enough to read")
end)

-- 24 Oct, live (hurry to 9 s): the badge read 8, 7, 8, 7, 6 ... The client's guess between the
-- server's 4 Hz updates ran ahead and a correction put it back up a second. The shown number
-- never goes back up (patience never comes back)
test("the badge's number never counts back up when a guess is corrected", function()
	local shown = nil
	for _, left in ipairs({ 8.0, 7.3, 6.95, 7.05, 6.2 }) do shown = M.shownCount(shown, M.count(left)) end
	assert(shown == 7, "8, 8, 7, then 7.05 (corrected up, would read 8) stays 7, 6.2 is 7; got " .. tostring(shown))
	assert(M.shownCount(7, 8) == 7, "a corrected-up guess does not bring 8 back")
	assert(M.shownCount(7, 6) == 6, "it still counts down")
	assert(M.shownCount(nil, 8) == 8, "the first number shows")
	assert(M.shownCount(3, nil) == 3, "no number (a read past 0 or before red) keeps what is shown")
end)

return T
