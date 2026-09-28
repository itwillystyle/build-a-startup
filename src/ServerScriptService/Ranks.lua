--[[
	Ranks -- ModuleScript in ServerScriptService.

	v4.2 RANKS. His ask (28 Sep): "a global leaderboard that shows the net worth
	of every person's company that started, to create a competitive aspect".
	The Valley Exchange board already existed, but it only listed companies
	past $250K (IPO), sat in the world where he never noticed it, and mixed in
	five AI companies with no label.

	THE NUMBER is company value: the lifetime valuation. It never drops when you
	spend or spin off (spinOff resets cash only), so ranking never punishes
	playing. Cash-based "net worth" would drop on every purchase.

	TWO BOARDS, both OrderedDataStores keyed by userId:
	  ALL TIME   SVTicker_v1 (the existing store), every company from $1,000
	  THIS WEEK  SVWeek_<weekId>, value gained since Monday 00:00 UTC, so a new
	             player can make the top 10 in their first week
	The five AI rivals stay so no board is ever empty, and carry an AI tag.

	Budget: one write per board per player per minute, only when the number
	changed (Roblox allows 60 + 10 x players a minute); one read per board per
	server per minute, cached; GetRanks never touches a DataStore.

	The rules are pure functions (weekId, rollWeek, merge, mine) and the board
	takes its stores as arguments, so tests/ranks_spec.luau runs them against
	fake stores in Edit.
]]
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RS = game:GetService("ReplicatedStorage")

local Ranks = {}
Ranks.TOP = 25            -- rows per board
Ranks.MIN = 1000          -- a company joins the board from $1,000 of value
Ranks.WEEK = 604800
Ranks.REFRESH = 60        -- seconds between board reads
Ranks.NAME_BUDGET = 10    -- new name lookups per refresh

-- weeks start Monday 00:00 UTC (the Unix epoch was a Thursday: +3 days)
function Ranks.weekId(t) return math.floor((t + 3 * 86400) / Ranks.WEEK) end
function Ranks.weekStart(t) return Ranks.weekId(t) * Ranks.WEEK - 3 * 86400 end
function Ranks.weekFraction(t) return math.clamp((t - Ranks.weekStart(t)) / Ranks.WEEK, 0, 1) end

-- the week's starting value: kept within the same week, reset to today's value
-- in a new one (or when the saved base is nonsense)
function Ranks.rollWeek(savedWeek, savedBase, valuation, nowWeek)
	valuation = valuation or 0
	if savedWeek == nowWeek and type(savedBase) == "number" and savedBase >= 0 and savedBase <= valuation then
		return nowWeek, savedBase
	end
	return nowWeek, valuation
end

-- humans { {key, value, name} } + rivals { {name, value} } -> the top n, ranked
function Ranks.merge(humans, rivals, n)
	local all = {}
	for _, h in ipairs(humans or {}) do
		table.insert(all, { key = h.key, name = h.name or "Startup", value = math.floor(h.value or 0), ai = false })
	end
	for _, r in ipairs(rivals or {}) do
		table.insert(all, { name = r.name, value = math.floor(r.value or 0), ai = true })
	end
	table.sort(all, function(a, b)
		if a.value ~= b.value then return a.value > b.value end
		return (a.name or "") < (b.name or "")
	end)
	local rows = {}
	for i = 1, math.min(n or Ranks.TOP, #all) do
		all[i].rank = i
		rows[i] = all[i]
	end
	return rows
end

-- where you stand, from your LIVE value (your stored row may be a minute old):
--   { unranked, need }         under $1,000
--   { rank, gapName, gapNeed } in the top n (gap = what it takes to pass the row above)
--   { needTop }                outside it (an OrderedDataStore page cannot give an exact rank)
function Ranks.mine(rows, key, value, n)
	n = n or Ranks.TOP
	value = math.floor(value or 0)
	local out = { value = value }
	if value < Ranks.MIN then
		out.unranked = true
		out.need = Ranks.MIN - value
		return out
	end
	local others, above, nearest = {}, 0, nil
	for _, r in ipairs(rows or {}) do
		if r.key == nil or r.key ~= key then
			table.insert(others, r)
			if r.value > value then
				above += 1
				if not nearest or r.value < nearest.value then nearest = r end
			end
		end
	end
	local rank = above + 1
	if rank <= n then
		out.rank = rank
		if nearest then
			out.gapName = nearest.name
			out.gapNeed = nearest.value - value + 1
		end
	else
		local cutoff = others[n]
		out.needTop = cutoff and (cutoff.value - value + 1) or 0
	end
	return out
end

-- ============ THE BOARD (stores passed in) ============
-- opts = { allStore, weekStoreFor(weekId), nameOf(key)?, top? }
function Ranks.newBoard(opts)
	local b = { opts = opts, cache = nil, names = {}, last = {}, lastWeek = {} }

	function b:nameFor(key, live, budget)
		if live[key] then self.names[key] = live[key] return live[key] end
		if self.names[key] then return self.names[key] end
		if budget.n > 0 and opts.nameOf then
			budget.n -= 1
			local ok, nm = pcall(opts.nameOf, key)
			if ok and type(nm) == "string" and nm ~= "" then
				self.names[key] = nm
				return nm
			end
		end
		return "Startup #" .. string.sub(key, -4)
	end

	-- write only what changed; a failure is retried next time
	function b:push(key, valuation, weekBase, weekId)
		local ok = true
		valuation = math.floor(valuation or 0)
		if valuation >= Ranks.MIN and self.last[key] ~= valuation then
			local okA = pcall(function() opts.allStore:SetAsync(key, valuation) end)
			if okA then self.last[key] = valuation else ok = false end
		end
		local wv = math.max(0, valuation - math.floor(weekBase or valuation))
		local wkKey = key .. "@" .. tostring(weekId)
		if wv > 0 and self.lastWeek[wkKey] ~= wv then
			local okW = pcall(function() opts.weekStoreFor(weekId):SetAsync(key, wv) end)
			if okW then self.lastWeek[wkKey] = wv else ok = false end
		end
		return ok
	end

	function b:read(store, live, budget)
		local page = store:GetSortedAsync(false, opts.top or Ranks.TOP):GetCurrentPage()
		local out = {}
		for _, e in ipairs(page) do
			table.insert(out, { key = e.key, value = e.value, name = self:nameFor(e.key, live, budget) })
		end
		return out
	end

	-- live = { [key] = current company name }, rivals = { {name, value} }
	function b:refresh(live, rivals, now)
		live = live or {}
		local wk = Ranks.weekId(now)
		local frac = Ranks.weekFraction(now)
		local allR, weekR = {}, {}
		for _, r in ipairs(rivals or {}) do
			table.insert(allR, { name = r.name, value = r.value })
			table.insert(weekR, { name = r.name, value = r.value * frac })
		end
		local budget = { n = Ranks.NAME_BUDGET }
		local ok, res = pcall(function()
			local allH = self:read(opts.allStore, live, budget)
			local weekH = self:read(opts.weekStoreFor(wk), live, budget)
			return { all = Ranks.merge(allH, allR, opts.top), week = Ranks.merge(weekH, weekR, opts.top) }
		end)
		local ends = Ranks.weekStart(now) + Ranks.WEEK
		if ok then
			self.cache = { all = res.all, week = res.week, updated = now, weekId = wk, weekEnds = ends, stale = false }
		elseif self.cache then
			self.cache.stale = true        -- keep serving the last good boards
		else
			-- nothing read yet: the AI rivals alone, marked stale
			self.cache = { all = Ranks.merge({}, allR, opts.top), week = Ranks.merge({}, weekR, opts.top),
				updated = now, weekId = wk, weekEnds = ends, stale = true }
		end
		if not ok then warn("[Ranks] refresh failed: " .. tostring(res)) end
		return ok
	end

	return b
end

-- ============ THE LIVE GAME ============
-- api = { session(player), allStore?, nameOf(key)?, rivals() -> { {name, value} }, toast(player, text) }
function Ranks.init(api)
	local board = Ranks.newBoard({
		allStore = api.allStore or DataStoreService:GetOrderedDataStore("SVTicker_v1"),
		weekStoreFor = function(w) return DataStoreService:GetOrderedDataStore("SVWeek_" .. w) end,
		nameOf = api.nameOf,
		top = Ranks.TOP,
	})
	Ranks.board = board

	local folder = RS:WaitForChild("SVRemotes")
	local rf = folder:FindFirstChild("GetRanks") or Instance.new("RemoteFunction")
	rf.Name = "GetRanks"
	rf.Parent = folder
	rf.OnServerInvoke = function(player)
		local c = board.cache
		if not c then return { all = {}, week = {}, pending = true } end
		local s = api.session(player)
		local key = tostring(player.UserId)
		local val = s and s.valuation or 0
		local base = s and s.weekBase or val
		return {
			all = c.all, week = c.week, updated = c.updated, stale = c.stale, weekEnds = c.weekEnds, now = os.time(),
			mine = { all = Ranks.mine(c.all, key, val), week = Ranks.mine(c.week, key, val - base) },
		}
	end

	function Ranks.pushPlayer(player)
		local s = api.session(player)
		if not s then return end
		local wk = Ranks.weekId(os.time())
		s.weekId, s.weekBase = Ranks.rollWeek(s.weekId, s.weekBase, s.valuation or 0, wk)
		board:push(tostring(player.UserId), s.valuation or 0, s.weekBase, wk)
	end

	task.spawn(function()
		while true do
			local now = os.time()
			local live = {}
			for _, p in ipairs(Players:GetPlayers()) do
				local s = api.session(p)
				if s then
					Ranks.pushPlayer(p)
					if s.name then live[tostring(p.UserId)] = s.name end
				end
			end
			board:refresh(live, api.rivals and api.rivals() or {}, now)
			-- the first time each week you reach the weekly top 10, you hear about it
			local c = board.cache
			for _, p in ipairs(Players:GetPlayers()) do
				local s = api.session(p)
				if s and c and not c.stale then
					local m = Ranks.mine(c.week, tostring(p.UserId), (s.valuation or 0) - (s.weekBase or s.valuation or 0))
					if m.rank and m.rank <= 10 and s.ranksToastWeek ~= c.weekId then
						s.ranksToastWeek = c.weekId
						if api.toast then api.toast(p, ("You're #%d this week on the Valley Exchange. Tap RANKS."):format(m.rank)) end
					end
				end
			end
			task.wait(Ranks.REFRESH)
		end
	end)
end

return Ranks
