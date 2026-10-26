-- errorbook.spec.luau: the live error log's pure half (26 Oct 2026, safety net part 1).
-- ErrorLog (server) notes every server error and every rate-limited client report into a
-- pending batch, then merges it into one DataStore record per UTC day. A new error on live
-- must show up the next morning; a flood must not grow the record or the server's memory.
local B = require("../../src/ServerScriptService/ErrorBook")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

test("one bug in two players' scripts is one signature", function()
	local a = B.signature("client", "Players.alice.PlayerScripts.HudClient:120: attempt to index nil with 'Text'", "Players.alice.PlayerScripts.HudClient, line 120")
	local b = B.signature("client", "Players.bob99.PlayerScripts.HudClient:120: attempt to index nil with 'Text'", "Players.bob99.PlayerScripts.HudClient, line 120")
	assert(a == b, a .. " ~= " .. b)
end)

test("a different line, side or message is a different signature", function()
	local base = B.signature("server", "ServerScriptService.SiliconCore:4157: boom", "x")
	assert(B.signature("server", "ServerScriptService.SiliconCore:4158: boom", "x") ~= base, "line")
	assert(B.signature("client", "ServerScriptService.SiliconCore:4157: boom", "x") ~= base, "side")
	assert(B.signature("server", "ServerScriptService.SiliconCore:4157: bang", "x") ~= base, "message")
end)

test("big numbers (ids, cash) fold together; line numbers do not", function()
	local a = B.signature("server", "Core:12: no plot for 1688749216 with $120000", "")
	local b = B.signature("server", "Core:12: no plot for 2200001234 with $999999", "")
	assert(a == b, "ids/cash should fold")
	assert(B.signature("server", "Core:1234: x", "") ~= B.signature("server", "Core:1235: x", ""), "4-digit lines stay apart")
end)

test("noting counts repeats and keeps the first sample", function()
	local p = B.batch()
	B.note(p, "server", "A:1: x", "Script A, line 1\nfrom here", 100)   -- same first stack line = same bug
	B.note(p, "server", "A:1: x", "Script A, line 1\nfrom there", 160)
	local sig, e = next(p.sigs)
	assert(p.count == 1 and e.n == 2, "one sig, n 2")
	assert(e.first == 100 and e.last == 160, "first/last")
	assert(e.sample:find("from here", 1, true), "first sample kept")
	assert(#sig <= 300, "signature length bounded")
end)

test("a flood of distinct errors stops growing the batch", function()
	local p = B.batch()
	for i = 1, 500 do B.note(p, "client", ("Script:%d: unique %d"):format(i, i), "", 1) end
	assert(p.count <= B.MAX_SIGS * 2, "pending capped at " .. p.count)
	assert(p.dropped > 0, "the overflow is counted, not lost silently")
end)

test("merge adds counts into the day's record and remembers the place version", function()
	local p1 = B.batch(); B.note(p1, "server", "A:1: x", "", 100); B.note(p1, "server", "A:1: x", "", 101)
	local rec = B.merge(nil, p1, 600, 110)
	local p2 = B.batch(); B.note(p2, "server", "A:1: x", "", 200); B.note(p2, "client", "B:2: y", "", 201)
	rec = B.merge(rec, p2, 607, 210)
	assert(rec.total == 4, "total " .. tostring(rec.total))
	local s = B.summary(rec)
	assert(#s == 2 and s[1].n == 3, "most frequent first")
	assert(s[1].v0 == 600 and s[1].v == 607, "first and last place version")
	assert(s[2].side == "client" and s[2].v0 == 607, "a new error carries the version it appeared in")
end)

test("merge keeps only the most frequent signatures", function()
	local p = B.batch()
	for i = 1, B.MAX_SIGS + 20 do
		for _ = 1, i do B.note(p, "server", ("S:%d: e"):format(i), "", 1) end
	end
	local rec = B.merge(nil, p, 1, 2)
	local n = 0
	for _ in rec.sigs do n += 1 end
	assert(n == B.MAX_SIGS, "kept " .. n)
	assert(rec.dropped > 0, "dropped counted")
	assert(B.summary(rec)[1].n == B.MAX_SIGS + 20, "the biggest survives")
end)

test("a broken stored record does not stop the merge", function()
	local p = B.batch(); B.note(p, "server", "A:1: x", "", 1)
	for _, old in { "junk", 5, { sigs = "no" }, { sigs = { bad = "x" } } } do
		local rec = B.merge(old, p, 1, 2)
		assert(B.summary(rec)[1].n == 1, "merged over " .. typeof(old))
	end
end)

test("a batch whose write failed goes back into the next one under the same names", function()
	local failed = B.batch(); B.note(failed, "server", "A:1: x", "s", 100); B.note(failed, "server", "A:1: x", "s", 101)
	local next1 = B.batch(); B.note(next1, "server", "A:1: x", "s", 150); B.note(next1, "client", "B:2: y", "t", 151)
	B.absorb(next1, failed)
	assert(next1.count == 2, "kinds " .. next1.count)
	local e = next1.sigs[B.signature("server", "A:1: x", "s")]
	assert(e.n == 3 and e.first == 100 and e.last == 150, "counts and times merged")
end)

test("a player can report 10 client errors a minute, then waits", function()
	local bucket = {}
	for i = 1, 10 do assert(B.allow(bucket, i * 0.1), "report " .. i) end
	assert(not B.allow(bucket, 5), "11th within the minute")
	assert(B.allow(bucket, 61), "next minute")
end)

test("live and Studio errors go to different keys, one per UTC day", function()
	assert(B.key(1793001600, false) == "live/2026-10-26", B.key(1793001600, false))
	assert(B.key(1793001600, true) == "studio/2026-10-26", "studio key")
end)

return T
