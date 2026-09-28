local mod = game:GetService("ReplicatedStorage"):FindFirstChild("Notify")
if not mod then return "FAIL: ReplicatedStorage.Notify missing" end
local clone = mod:Clone()
local Notify = require(clone)
local t, st, log, fails = 0, nil, nil, {}
local function env() return { now = function() return t end, state = function() return st end } end
local function reset()
	t = 0
	st = { driving = false, carrying = false, cutscene = false, menu = false }
	log = {}
	return Notify.new(env())
end
local function item(lane, p, key, extra)
	local it = { lane = lane, priority = p, key = key }
	it.open = function(done) table.insert(log, "open " .. key); it.done = done end
	it.close = function() table.insert(log, "close " .. key) end
	it.fallback = function() table.insert(log, "fallback " .. key) end
	for k, v in pairs(extra or {}) do it[k] = v end
	return it
end
local function count(s) local n = 0 for _, l in ipairs(log) do if l == s then n += 1 end end return n end
local function expect(c, msg) if not c then table.insert(fails, msg .. "  log=" .. table.concat(log, ",")) end end

do -- 1 one per lane, next after done
	local d = reset()
	local a, b = item("top", 2, "a"), item("top", 2, "b")
	d:show(a); d:show(b)
	expect(count("open a") == 1 and count("open b") == 0, "1a one per lane")
	a.done()
	expect(count("open b") == 1, "1b next after done")
end
do -- 2 lanes are independent
	local d = reset()
	d:show(item("top", 2, "a")); d:show(item("bottom", 2, "b"))
	expect(count("open a") == 1 and count("open b") == 1, "2 top and bottom together")
end
do -- 3 priority order, then FIFO
	local d = reset()
	local a = item("bottom", 2, "a"); d:show(a)
	d:show(item("bottom", 3, "amb")); d:show(item("bottom", 2, "p2")); d:show(item("bottom", 1, "p1"))
	a.done()
	expect(count("open p1") == 1 and count("open p2") == 0, "3 P1 first")
end
do -- 4 P0 bumps a P2 (dropped, fallback) and a P1 (re-queued, shown again)
	local d = reset()
	local a = item("top", 2, "a"); d:show(a)
	local z = item("top", 0, "z"); d:show(z)
	expect(count("close a") == 1 and count("fallback a") == 1 and count("open z") == 1, "4a P0 bumps P2")
	z.done()
	local r = item("top", 1, "r"); d:show(r)
	local stale = r.done
	local z2 = item("top", 0, "z2"); d:show(z2)
	expect(count("close r") == 1 and count("fallback r") == 0, "4b P1 closed, not dropped")
	z2.done()
	expect(count("open r") == 2, "4c P1 shown again after the danger")
	stale()                                   -- the first run's late done must not end the second run
	d:show(item("top", 2, "after"))
	expect(count("open after") == 0, "4d stale done ignored")
end
do -- 5 driving: P3 dropped at once, P1 waits (never dropped), P0 shows
	local d = reset(); st.driving = true
	d:show(item("top", 3, "text")); d:show(item("top", 1, "rev"))
	expect(count("fallback text") == 1 and count("open rev") == 0, "5a driving holds P1, drops P3")
	local z = item("bottom", 0, "danger"); d:show(z)
	expect(count("open danger") == 1, "5b P0 shows while driving")
	t = 100; st.driving = false; d:pump()
	expect(count("open rev") == 1, "5c P1 after driving")
end
do -- 6 cutscene: everything waits, P3 dropped
	local d = reset(); st.cutscene = true
	d:show(item("top", 0, "z")); d:show(item("bottom", 3, "amb")); d:show(item("centre", 2, "c"))
	expect(count("open z") == 0 and count("fallback amb") == 1 and count("open c") == 0, "6a cutscene holds")
	st.cutscene = false; d:pump()
	expect(count("open z") == 1 and count("open c") == 1, "6b after cutscene")
end
do -- 7 carrying / menu hold P2, allow P1
	local d = reset(); st.carrying = true
	d:show(item("bottom", 2, "p2")); d:show(item("top", 1, "p1"))
	expect(count("open p2") == 0 and count("open p1") == 1, "7a carrying")
	st.carrying = false; st.menu = true; d:pump()
	expect(count("open p2") == 0, "7b menu holds P2")
	st.menu = false; d:pump()
	expect(count("open p2") == 1, "7c released")
end
do -- 8 P3 spacing 20 s, TTL 15 s
	local d = reset()
	local a = item("bottom", 3, "a"); d:show(a); a.done()
	d:show(item("bottom", 3, "b"))
	expect(count("open b") == 0, "8a gap holds the second ambient")
	t = 14; d:pump(); expect(count("open b") == 0, "8b still waiting at 14 s")
	t = 16; d:pump(); expect(count("fallback b") == 1, "8c dropped after 15 s")
	t = 40; local c = item("bottom", 3, "c"); d:show(c)
	expect(count("open c") == 1, "8d allowed after the gap")
end
do -- 9 hold / release
	local d = reset()
	d:hold("top", "hh")
	d:show(item("top", 2, "a")); d:show(item("top", 0, "z"))
	expect(count("open a") == 0 and count("open z") == 0, "9a hold blocks everything")
	d:release("hh")
	expect(count("open z") == 1, "9b P0 first after release")
	local d2 = reset()
	local b = item("top", 2, "b"); d2:show(b)
	d2:hold("top", "hh")
	expect(count("close b") == 1, "9c hold bumps what is showing")
end
do -- 10 safety net
	local d = reset()
	d:show(item("top", 2, "stuck")); d:show(item("top", 2, "next"))
	t = 7; d:pump(); expect(count("open next") == 0, "10a before 8 s")
	t = 8.5; d:pump(); expect(count("close stuck") == 1 and count("open next") == 1, "10b freed after 8 s")
end
do -- 11 calm needs 5 s idle in centre and top
	local d = reset()
	d:show(item("centre", 2, "calm", { calm = true }))
	expect(count("open calm") == 0, "11a not calm at 0 s")
	t = 5.1; d:pump(); expect(count("open calm") == 1, "11b calm at 5 s")
	local d2 = reset(); t = 10
	local x = item("top", 2, "x"); d2:show(x)
	d2:show(item("centre", 2, "calm2", { calm = true }))
	t = 12; x.done(); t = 14; d2:pump()
	expect(count("open calm2") == 0, "11c top was busy 2 s ago")
	t = 17.1; d2:pump(); expect(count("open calm2") == 1, "11d calm 5 s after top freed")
end
do -- 12 centre and top exclude each other (a phone's centre card reaches the top strip)
	local d = reset()
	local c = item("centre", 2, "card"); d:show(c)
	d:show(item("top", 1, "rev")); d:show(item("top", 0, "z"))
	expect(count("open rev") == 0 and count("open z") == 1, "12a centre blocks top except P0")
	local d2 = reset()
	d2:show(item("top", 2, "strip")); d2:show(item("centre", 2, "card2"))
	expect(count("open card2") == 0, "12b top blocks centre")
end
do -- 13 valid() and delay
	local d = reset()
	local ok = false
	d:show(item("centre", 2, "v", { valid = function() return ok end }))
	expect(count("open v") == 0 and count("fallback v") == 0, "13a invalid dropped quietly")
	d:show(item("top", 1, "late", { delay = 1.6 }))
	expect(count("open late") == 0, "13b delay holds")
	t = 1.7; d:pump(); expect(count("open late") == 1, "13c after delay")
end

do -- 15 a cutscene that starts mid-show takes the lanes back: P0-P2 return after it, P3 drops
	local d = reset()
	local r = item("top", 1, "rev"); d:show(r)
	local c = item("centre", 0, "c0")
	local b = item("bottom", 2, "b2"); d:show(b)
	local a = item("bottom", 3, "amb")
	st.cutscene = true; d:pump()
	expect(count("close rev") == 1 and count("close b2") == 1, "15a closed when the cutscene starts")
	expect(count("fallback b2") == 0, "15b progress kept, not dropped")
	st.cutscene = false; d:pump()
	expect(count("open rev") == 2 and count("open b2") == 2, "15c shown again after the cutscene")
	local d2 = reset()
	local x = item("bottom", 3, "x"); d2:show(x)
	st.cutscene = true; d2:pump()
	expect(count("close x") == 1 and count("fallback x") == 1, "15d ambient dropped")
end
do -- 16 across lanes the most urgent goes first (after a cutscene, the rare hire beats the item card)
	local d = reset(); st.cutscene = true
	d:show(item("centre", 2, "itemcard")); d:show(item("top", 1, "rev"))
	st.cutscene = false; d:pump()
	expect(count("open rev") == 1 and count("open itemcard") == 0, "16 P1 top before P2 centre")
end
expect(type(Notify.toast) == "function", "14 toast exported")

clone:Destroy()
return #fails == 0 and "PASS 16 groups" or ("FAIL " .. #fails .. "\n" .. table.concat(fails, "\n"))
