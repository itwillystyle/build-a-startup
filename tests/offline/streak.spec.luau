-- streak.spec.luau: a doctor or health finding open 3 runs in a row must be fixed or given a
-- reason in docs/KNOWN-FINDINGS.md (7 Nov 2026). Bob's hip snap sat in 4 doctor runs and the
-- morning health run was RED 10 days running before either was acted on.
local S = require("../../tools/streak_lib")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local function count(t) local n = 0 for _ in t do n += 1 end return n end

test("advance counts runs in a row and forgets a finding the run did not see", function()
	local s = S.advance(nil, { "bob / snap", "rooms / screens" })
	assert(s["bob / snap"] == 1 and s["rooms / screens"] == 1, "s['bob / snap'] == 1 and s['rooms / screens'] == 1")
	s = S.advance(s, { "bob / snap" })
	assert(s["bob / snap"] == 2, "s['bob / snap'] == 2")
	assert(s["rooms / screens"] == nil, "a run without it resets it")
	s = S.advance(s, { "bob / snap", "rooms / screens" })
	assert(s["bob / snap"] == 3 and s["rooms / screens"] == 1, "s['bob / snap'] == 3 and s['rooms / screens'] == 1")
end)

test("advance ignores a key listed twice in one run", function()
	local s = S.advance({ a = 1 }, { "a", "a" })
	assert(s.a == 2, "s.a == 2")
end)

test("parseKnown reads `key`: reason lines and skips everything else", function()
	local k = S.parseKnown([[
# Known findings

Lines like the ones below. Anything else is ignored.

- `bob / bob intro: nothing snaps inside a shot`: fixed in #94, not live until Alt+P (7 Nov)
- `feature map / coverage`:    pages catch up in the docs pass (7 Nov)
- `no reason given`:
* `star bullet / also fine`: reason
- not a key: reason
]])
	assert(k["bob / bob intro: nothing snaps inside a shot"]:find("#94"), "k['bob / bob intro: nothing snaps inside a shot']:find('#94')")
	assert(k["feature map / coverage"] == "pages catch up in the docs pass (7 Nov)", "k['feature map / coverage'] == 'pages catch up in the docs pass (7 Nov)'")
	assert(k["star bullet / also fine"] == "reason", "k['star bullet / also fine'] == 'reason'")
	assert(k["no reason given"] == nil, "a key with no reason does not count as known")
	assert(count(k) == 3, "count(k) == 3")
end)

test("stale lists findings open 3+ runs with no reason, longest first", function()
	local streaks = { a = 5, b = 3, c = 2, d = 7 }
	local st = S.stale(streaks, { d = "waiting on the art pass" })
	assert(#st == 2, tostring(#st))
	assert(st[1].key == "a" and st[1].runs == 5, "st[1].key == 'a' and st[1].runs == 5")
	assert(st[2].key == "b" and st[2].runs == 3, "st[2].key == 'b' and st[2].runs == 3")
end)

test("stale takes a threshold", function()
	assert(#S.stale({ a = 2 }, {}, 2) == 1, "#S.stale({ a = 2 }, {}, 2) == 1")
	assert(#S.stale({ a = 2 }, {}) == 0, "#S.stale({ a = 2 }, {}) == 0")
	assert(S.THRESHOLD == 3, "S.THRESHOLD == 3")
end)

test("explained lists open known findings with their reason and runs", function()
	local ex = S.explained({ d = 7, a = 1 }, { d = "art pass", gone = "old" })
	assert(#ex == 1 and ex[1].key == "d" and ex[1].runs == 7 and ex[1].reason == "art pass", "#ex == 1 and ex[1].key == 'd' and ex[1].runs == 7 and ex[1].reason == 'art pass'")
end)

test("unused lists known entries no run reported any more (remove them)", function()
	local u = S.unused({ a = 1 }, { a = "x", gone = "old" })
	assert(#u == 1 and u[1] == "gone", "#u == 1 and u[1] == 'gone'")
end)

test("markdown says what to do, or says none", function()
	local md = S.markdown({ a = 4 }, {})
	assert(md:find("`a`") and md:find("4 runs") and md:find("KNOWN%-FINDINGS"), "md:find('`a`') and md:find('4 runs') and md:find('KNOWN%-FINDINGS')")
	local clean = S.markdown({ a = 1 }, {})
	assert(clean:find("none"), clean)
end)

test("the repo's KNOWN-FINDINGS.md parses and every entry has a reason", function()
	local fs = require("@lune/fs")
	local text = fs.readFile("docs/KNOWN-FINDINGS.md")
	local entries = 0
	for line in text:gmatch("[^\n]+") do
		if line:match("^%s*[%-%*]%s*`") then entries += 1 end
	end
	assert(count(S.parseKnown(text)) == entries, "an entry without a reason")
end)

return T
