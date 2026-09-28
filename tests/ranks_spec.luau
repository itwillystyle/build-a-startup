-- tests/ranks_spec.luau: the Ranks rules and board, against fake stores (Edit datamodel)
local mod = game:GetService("ServerScriptService"):FindFirstChild("Ranks")
if not mod then return "FAIL: ServerScriptService.Ranks missing" end
local clone = mod:Clone()
local R = require(clone)
local fails = {}
local function expect(c, msg) if not c then table.insert(fails, msg) end end

-- 1 weeks start Monday 00:00 UTC
local mon = os.time({ year = 2026, month = 9, day = 28, hour = 0, min = 0, sec = 0 })   -- local time
-- build Monday 28 Sep 2026 00:00 UTC exactly: 2026-09-28 is a Monday
local t = 1790553600      -- 2026-09-28T00:00:00Z
expect(R.weekId(t) == R.weekId(t + 6 * 86400 + 86399), "1a same week through Sunday 23:59:59")
expect(R.weekId(t - 1) == R.weekId(t) - 1, "1b Sunday night is the previous week")
expect(R.weekStart(t + 12345) == t, "1c weekStart is Monday 00:00")
expect(math.abs(R.weekFraction(t + 302400) - 0.5) < 1e-9, "1d half a week")
local _ = mon

-- 2 rollWeek
local w, b = R.rollWeek(10, 500, 900, 10); expect(w == 10 and b == 500, "2a same week keeps the base")
w, b = R.rollWeek(9, 500, 900, 10); expect(b == 900, "2b new week resets to today's value")
w, b = R.rollWeek(10, 2000, 900, 10); expect(b == 900, "2c a base above the value is nonsense: reset")
w, b = R.rollWeek(nil, nil, 50, 10); expect(w == 10 and b == 50, "2d a new player starts at their value")

-- 3 merge: sorted, ranked, AI tagged, capped at n
local rows = R.merge({ { key = "1", value = 500, name = "A" }, { key = "2", value = 3000, name = "B" } },
	{ { name = "Bot", value = 1000 } }, 2)
expect(#rows == 2 and rows[1].name == "B" and rows[1].rank == 1 and rows[2].name == "Bot" and rows[2].ai == true, "3 merge order, rank, AI tag, cap")

-- 4 mine
local board = R.merge({ { key = "a", value = 9000, name = "Nine" }, { key = "me", value = 4000, name = "Me" },
	{ key = "b", value = 5000, name = "Five" } }, { { name = "Bot", value = 7000 } }, 25)
local m = R.mine(board, "me", 4200)
expect(m.rank == 3 + 1 and m.gapName == "Five" and m.gapNeed == 801, "4a rank from the live value + gap to the row above")
m = R.mine(board, "me", 9500)
expect(m.rank == 1 and m.gapName == nil, "4b first place has no gap")
m = R.mine(board, "me", 500)
expect(m.unranked and m.need == 500, "4c under $1,000 is unranked")
local full = {}
for i = 1, 25 do table.insert(full, { key = "k" .. i, value = 100000 - i, name = "C" .. i }) end
local fr = R.merge(full, {}, 25)
m = R.mine(fr, "me", 5000)
expect(m.rank == nil and m.needTop == (100000 - 25) - 5000 + 1, "4d outside the top 25: what it takes to get in")

-- 5 the board against fake stores
local function fakeStore(fail)
	local s = { data = {}, sets = 0 }
	function s:SetAsync(k, v) if fail then error("down") end self.sets += 1; self.data[k] = v end
	function s:GetSortedAsync(asc, n)
		if fail then error("down") end
		local list = {}
		for k, v in pairs(self.data) do table.insert(list, { key = k, value = v }) end
		table.sort(list, function(a, b) return a.value > b.value end)
		local page = {}
		for i = 1, math.min(n, #list) do page[i] = list[i] end
		return { GetCurrentPage = function() return page end }
	end
	return s
end
local all, weeks = fakeStore(), {}
local bd = R.newBoard({ allStore = all, weekStoreFor = function(id) weeks[id] = weeks[id] or fakeStore(); return weeks[id] end,
	nameOf = function(key) return "Named " .. key end, top = 25 })
local wk = R.weekId(t)
for i = 1, 40 do bd:push(tostring(1000 + i), 1000 * i, 1000 * i - 500 * i, wk) end   -- week value = 500 * i
expect(all.sets == 40, "5a 40 all-time writes")
bd:push("1040", 40000, 20000, wk)
expect(all.sets == 40, "5b an unchanged value is not rewritten")
bd:push("1005", 900, 900, wk)
expect(all.data["1005"] == 5000, "5c under $1,000 is not written")
local ok = bd:refresh({ ["1040"] = "Live Name" }, { { name = "Bot", value = 30500 } }, t + 302400)
expect(ok and #bd.cache.all == 25 and bd.cache.all[1].name == "Live Name" and bd.cache.all[1].value == 40000, "5d refresh: top 25, live name wins")
local botRow
for _, r in ipairs(bd.cache.all) do if r.ai then botRow = r end end
expect(botRow and botRow.value == 30500, "5e AI rival on the all-time board")
local botWeek
for _, r in ipairs(bd.cache.week) do if r.ai then botWeek = r end end
expect(botWeek and botWeek.value == 15250, "5f AI rival grows through the week (half a week = half)")
expect(bd.cache.week[1].value == 20000 and bd.cache.week[1].key == "1040", "5g weekly board ranks value gained")
local named = 0
for _, r in ipairs(bd.cache.all) do if r.name:find("^Named") then named += 1 end end
expect(named <= R.NAME_BUDGET, "5h at most " .. R.NAME_BUDGET .. " name lookups per refresh")

-- 6 a failed read serves the last good boards, marked stale
local failing = fakeStore(true)
bd.opts.allStore = failing
local ok2 = bd:refresh({}, {}, t + 302500)
expect(not ok2 and bd.cache.stale == true and #bd.cache.all == 25, "6a stale cache served")
local bd2 = R.newBoard({ allStore = fakeStore(true), weekStoreFor = function() return fakeStore(true) end, top = 25 })
bd2:refresh({}, { { name = "Bot", value = 5000 } }, t)
expect(bd2.cache.stale and #bd2.cache.all == 1 and bd2.cache.all[1].ai, "6b nothing read yet: AI rivals only, stale")

clone:Destroy()
return #fails == 0 and "PASS 6 groups" or ("FAIL " .. #fails .. "\n" .. table.concat(fails, "\n"))
