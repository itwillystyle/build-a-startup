--[[ SaveLoad: SiliconCore's save / load (serialize, saveNow, applySave,
loadOnce, the BindToClose flush and the 60 s autosave).
Moved out of SiliconCore on 28 Sep 2026 (v4.2) to free its top-level locals.
SiliconCore calls this once, at the same point in its load order the code
used to run, passing the SiliconCore locals it needs in `core`. Every one of
them is assigned before this point and never reassigned, so aliasing is safe. ]]
return function(core)
	local CFG = core.CFG
	local Prog = core.Prog
	local Journey = core.Journey
	local CampusArch = core.CampusArch
	local Econ = core.Econ
	local FurnitureKit = core.FurnitureKit
	local Players = core.Players
	local SPINOFF_BASE = core.SPINOFF_BASE
	local StaffRig = core.StaffRig
	local WING_MAX_LEVEL = core.WING_MAX_LEVEL
	local applyWingLevel = core.applyWingLevel
	local buildShell = core.buildShell
	local buildWing = core.buildWing
	local cashOf = core.cashOf
	local hireGrowthAt = core.hireGrowthAt
	local loaded = core.loaded
	local loading = core.loading
	local milestonesFromEarned = core.milestonesFromEarned
	local officeDesk = core.officeDesk
	local placeAt = core.placeAt
	local plotOf = core.plotOf
	local pushTicker = core.pushTicker
	local recompute = core.recompute
	local refreshHqPad = core.refreshHqPad
	local refreshSign = core.refreshSign
	local refreshWingPrompt = core.refreshWingPrompt
	local saveStore = core.saveStore
	local sessions = core.sessions
	local spawnStaff = core.spawnStaff
	local tickerOf = core.tickerOf
	local titleOf = core.titleOf
	local updateHirePad = core.updateHirePad


	-- v4.6 THE WAFERS: one letter per level ("-" for fixed pieces), both for the building
	-- (wd) and for the record building's departments (bp: a rebuild lays them out again)
	local DEPT_CODE = { lobby = "L", eng = "E", studio = "S", cafe = "C", servers = "V", labs = "A", board = "B" }
	local CODE_DEPT = {}
	for d, c in pairs(DEPT_CODE) do CODE_DEPT[c] = d end
	local function encodeDepts(t, n)
		local out = {}
		for L = 1, n do out[L] = DEPT_CODE[t[L] or ""] or "-" end
		return table.concat(out)
	end
	local function decodeDepts(str)
		local t = {}
		if type(str) ~= "string" then return t end
		for L = 1, math.min(#str, 100) do t[L] = CODE_DEPT[str:sub(L, L)] end
		return t
	end

	local function serialize(player)
		local s = sessions[player.UserId]
		local plot = plotOf(player)
		if not s or not plot then return nil end
		local _, plotYaw = plot.pivot:ToEulerAnglesYXZ()
		local plotYawDeg = math.floor(math.deg(plotYaw) + 0.5)
		local placed = {}
		for _, e in ipairs(s.placed) do
			local l = plot.pivot:PointToObjectSpace(Vector3.new(e.x, 0, e.z))
			placed[#placed + 1] = { k = e.key, x = l.X, z = l.Z, y = ((e.yaw or 0) - plotYawDeg) % 360, p = e.price }
		end
		local wings = {}
		for i, slot in ipairs(plot.slots) do
			if slot.built then wings[tostring(i)] = { id = slot.built, lv = slot.level or 1 } end
		end
		local cash = cashOf(player)
		return {
			v = 1,
			layout = (CampusArch and CampusArch.LAYOUT) or 2,   -- the lot layout the furniture coordinates are in
			cash = cash and cash.Value or 0,
			hq = plot.hq.level,
			wings = wings,
			wl = plot.wafer and plot.wafer.level or nil,                        -- v4.6 the Wafers: level,
			wd = plot.wafer and encodeDepts(plot.wafer.depts, plot.wafer.level) or nil,   -- its departments,
			rec = s.record,                                                     -- the record (lifetime),
			bp = s.blueprint and encodeDepts(s.blueprint, s.record or 1) or nil,   -- and the record's layout
			placed = placed,
			staff = s.staff,
			shipped = s.shipped,
			name = s.name,
			valuation = math.floor(s.valuation or 0),
			weekId = s.weekId,                                  -- v4.2 the weekly board: which week, and the value it started at
			weekBase = s.weekBase and math.floor(s.weekBase) or nil,
			ipo = s.ipo or false,
			launches = s.launches or 0,
			rl = s.runLaunches or 0,   -- v4.5: this company's launches (the work need)
			rate = s.rate,
			lastSeen = os.time(),
			tiers = (function()
				local t = {}
				for i, r in ipairs(s.rigs or {}) do t[i] = r.tier or 1 end
				return t
			end)(),
			talents = (function()
				local t = {}
				for i, r in ipairs(s.rigs or {}) do t[i] = r.talent or 1 end
				return t
			end)(),
			index = (function()
				local t = {}
				for k in pairs(s.index or {}) do table.insert(t, k) end
				return t
			end)(),
			-- v3.0: who each recruit was ("role:seed"), so they look the same after a rejoin
			people = (function()
				local t = {}
				for i, r in ipairs(s.rigs or {}) do t[i] = r.who and (r.who.role .. ":" .. r.who.seed) or "" end
				return t
			end)(),
			playtime = math.floor(s.playtime or 0),
			muted = s.muted == true,
			dailyDay = s.dailyDay or 0,          -- v3.1 daily streak: two integers, clamped on load
			streak = s.streak or 0,
			alumni = math.min(s.alumni or 0, CFG.ALUMNI_CAP),
			work = math.floor(s.work or 0),
			spinoffs = math.min(s.spinoffs or 0, Prog.SPIN_CAP),
			-- which of the three HQ styles this company is built in. One short
			-- string; the placer falls back to Wafers on anything unknown, so a
			-- corrupt value can never make a player's whole building vanish.
			hqPath = s.hqPath,
			earned = math.floor(s.earned or 0),
			items = Econ and Econ.Inv and Econ.Inv.save(s) or nil,   -- v3.2 the bag: counts only
			apt = s.apt or 0,                                            -- v4.0 the apartment rung (0-3)
			vipDay = s.vipDay,                                          -- v4.2 the UTC day the daily VIP was picked up
			jr = Journey.cleanFlags(s.jr),                              -- v4.3 journey flags (booleans, sanitized)
			tips = Journey.tipList(s.tips),                             -- v4.3 HUD tips already read
			listed = s.listed == true,                                  -- v4.3 this company went public
			cars = Econ and Econ.Cars and Econ.Cars.save(s) or nil,     -- v4.0 owned car ids
			car = s.car,
		}
	end

	local function saveNow(player)
		if not saveStore or not loaded[player.UserId] then return false end
		local data = serialize(player)
		if not data then return false end
		local ok, err = pcall(function()
			saveStore:UpdateAsync(tostring(player.UserId), function(old)
				-- never let an older session overwrite a newer one
				if type(old) == "table" and (old.lastSeen or 0) > data.lastSeen then return nil end
				return data
			end)
		end)
		if not ok then warn("[SV] save failed for " .. player.Name .. ": " .. tostring(err)) end
		return ok
	end

	local function clampInt(v, lo, hi, default)
		if type(v) ~= "number" then return default end
		return math.clamp(math.floor(v), lo, hi)
	end

	local function applySave(player, plot, data)
		local s = sessions[player.UserId]
		if not s or not plot or type(data) ~= "table" then return end
		local cash = cashOf(player)
		local _, plotYaw = plot.pivot:ToEulerAnglesYXZ()
		local plotYawDeg = math.floor(math.deg(plotYaw) + 0.5)

		if cash then cash.Value = clampInt(data.cash, 0, 1e12, 0) end
		s.shipped = data.shipped == true or clampInt(data.staff, 0, 200, 0) > 0
		s.name = type(data.name) == "string" and data.name:sub(1, 20) or nil
		s.ticker = s.name and tickerOf(s.name) or nil
		s.valuation = clampInt(data.valuation, 0, 1e13, 0)
		s.weekId = clampInt(data.weekId, 0, 1e7, 0)          -- v4.2 (Ranks.rollWeek resets a stale or nonsense base)
		s.weekBase = data.weekBase ~= nil and clampInt(data.weekBase, 0, 1e13, 0) or nil
		s.ipo = data.ipo == true and s.name ~= nil
		s.launches = clampInt(data.launches, 0, 1e6, 0)
		s.runLaunches = clampInt(data.rl, 0, 1e6, 0)

		-- offline earnings: a quarter rate, capped at 8 hours. A returning player
		-- should find something waiting, not a fortune (Roblox 2026 discovery
		-- scores D1..D28 -- this is the come-back-tomorrow mechanic)
		local away = math.clamp(os.time() - clampInt(data.lastSeen, 0, 4e9, os.time()), 0, 8 * 3600)
		local offline = math.floor(clampInt(data.rate, 0, 1e9, 0) * 0.25 * away)
		-- v2.7.0: on fixed price ladders 2 hours of income skips a whole HQ tier;
		-- coming back should find something useful waiting, not the next building
		if Econ and Econ.V3 then offline = math.min(offline, clampInt(data.rate, 0, 1e9, 0) * Econ.OFFLINE_CAP) end
		-- v4.2 HOME TURF: your apartment decides how much of the wait for your next step
		-- a return covers (Apartments.offline: never below the line above, up to one
		-- whole step, never two). The late game is where it counts (sim/offline_sim3.py).
		if Econ and Econ.Apt and Econ.Apt.offline and Econ.Apt.ladder then
			local apt = clampInt(data.apt, 0, 3, 0)
			local spins = clampInt(data.spinoffs, 0, Prog.SPIN_CAP, 0)
			local nxt, aft = Econ.Apt.ladder(clampInt(data.hq, 1, #CFG.HQ_LEVELS, 1), apt,
				function(l) return CFG.HQ_LEVELS[l] and Prog.scaled(CFG.HQ_LEVELS[l].cost, spins) or 0 end,   -- v4.5 the clock
				Prog.spinCost(spins, SPINOFF_BASE))
			if Econ.WAFERS and Econ.Wafers then   -- v4.6: the next two floors
				local WP = Econ.Wafers.Plan
				local capw = WP.blueprint(spins)
				local lvw = clampInt(data.wl, 1, WP.MAX, 0)
				if lvw == 0 then lvw = ({ 1, 5, 9, 13, 18 })[clampInt(data.hq, 1, 5, 1)] end
				local recw = math.max(clampInt(data.rec, 1, WP.MAX, 1), lvw)
				local function step(L) return L > capw and Prog.spinCost(spins, SPINOFF_BASE) or WP.price(L, Prog.runScale(spins), recw) end
				nxt, aft = step(lvw + 1), step(lvw + 2)
			end
			offline = Econ.Apt.offline(clampInt(data.rate, 0, 1e9, 0), away, apt, cash and cash.Value or 0, nxt, aft)
			player:SetAttribute("OfflineApt", apt)
		end
		if offline > 0 and cash then
			cash.Value += offline
			player:SetAttribute("OfflineEarned", offline)
		end

		local level = clampInt(data.hq, 1, #CFG.HQ_LEVELS, 1)
		if Econ and Econ.WAFERS and Econ.Wafers and plot.wafer then
			-- v4.6 THE WAFERS: rebuild the saved building (an old HQ 1-5 save becomes level 1/5/9/13/18)
			local WP = Econ.Wafers.Plan
			local spins = s.spinoffs or clampInt(data.spinoffs, 0, Prog.SPIN_CAP, 0)
			local capw = WP.blueprint(spins)
			local lvw = clampInt(data.wl, 1, WP.MAX, 0)
			if lvw == 0 then lvw = ({ 1, 5, 9, 13, 18 })[level] end
			lvw = math.min(lvw, capw)
			s.record = math.max(clampInt(data.rec, 1, WP.MAX, 1), lvw)
			s.blueprint = decodeDepts(data.bp)
			local saved = decodeDepts(data.wd)
			for L, d in pairs(saved) do s.blueprint[L] = s.blueprint[L] or d end
			Econ.Wafers.buildUpTo(plot, lvw, function(x)
				local ok = {}
				for _, d in ipairs(WP.allowed(x)) do ok[d] = true end
				local pick = (ok[saved[x] or ""] and saved[x]) or (ok[s.blueprint[x] or ""] and s.blueprint[x])
					or WP.recommend(x, Econ.Wafers.counts(plot), 99)
				s.blueprint[x] = pick
				return pick
			end, false)
			level = Econ.Wafers.stage(lvw)
			plot.hq.level = level
		elseif level > 1 then buildShell(plot, level, false) end
		s.hqLevel = level
		if s.shipped then
			s.buildUnlocked = true
			plot.doorOpened = true
			for _, door in ipairs({ plot.hq.doorL, plot.hq.doorR }) do
				door.CFrame = door.CFrame * CFrame.new(0, 11, 0)
			end
			for _, slot in ipairs(plot.slots) do
				slot.prompt.Enabled = true
				slot.text.Text = "BUILD HERE"
			end
		end
		if type(data.wings) == "table" then
			for k, w in pairs(data.wings) do
				local i = tonumber(k)
				local roomId = type(w) == "table" and w.id or w        -- v1 saves stored the id string
				local lv = type(w) == "table" and clampInt(w.lv, 1, WING_MAX_LEVEL, 1) or 1
				if i and CFG.ROOM_BY_ID[roomId] and buildWing(player, plot, i, roomId, true) then
					local slot = plot.slots[i]
					for _ = 2, lv do
						slot.level += 1
						applyWingLevel(s, CFG.ROOM_BY_ID[roomId])
						if roomId == "office" then
							officeDesk(slot, 2 * slot.level - 1)
							officeDesk(slot, 2 * slot.level)
						end
					end
					if Econ and Econ.V3 then Econ.furnish(FurnitureKit, slot) end
					if CampusArch and CampusArch.grow and slot.model then pcall(CampusArch.grow, slot.model, slot.cf, slot.room, CFG.SLOT_W, CFG.SLOT_D, slot.level) end
					refreshWingPrompt(slot, plot, s)
				end
			end
		end
		if type(data.placed) == "table" then
			for _, e in ipairs(data.placed) do
				if type(e) == "table" and type(e.k) == "string" then
					local lx, lz, ly = tonumber(e.x) or 0, tonumber(e.z) or 0, tonumber(e.y) or 0
					-- saved in an older layout: carried into the same room at its new place
					if CampusArch and CampusArch.migrate then lx, lz, ly = CampusArch.migrate(lx, lz, ly, data.layout, CFG.SLOT_W, CFG.SLOT_D) end
					local w = plot.pivot:PointToWorldSpace(Vector3.new(lx, 0, lz))
					placeAt(player, plot, e.k, w.X, w.Z, (ly + plotYawDeg) % 360, true, clampInt(e.p, 0, 1e9, nil))
				end
			end
		end
		-- v3.0 TALENT INDEX: sanitized; rebuilt staff below are rediscoveries, not news
		s.index = {}
		if type(data.index) == "table" then
			for _, k in ipairs(data.index) do
				-- v4.2: `x and k:match(...)` keeps only match's FIRST return, so `t` was
				-- always nil and no saved Index entry was ever restored (found by selene:
				-- unbalanced_assignments, the first time it ran on this code)
				local role, t
				if type(k) == "string" then role, t = k:match("^(%a+):(%d)$") end
				t = tonumber(t)
				if role and t and StaffRig and StaffRig.ROLES[role] and t >= 1 and t <= #CFG.TALENT then s.index[k] = true end
			end
		end
		s.indexQuiet = true
		local staffN = clampInt(data.staff, 0, 200, 0)
		s.hireCost = CFG.HIRE_BASE
		for i = 1, staffN do
			s.staff = i
			if i > 1 then s.hireCost = math.floor(s.hireCost * hireGrowthAt(i)) end
			local talent = type(data.talents) == "table" and clampInt(data.talents[i], 1, #CFG.TALENT, 1) or 1
			local who
			local pe = type(data.people) == "table" and data.people[i]
			if type(pe) == "string" then
				local role, seed = pe:match("^(%a+):(%d+)$")
				seed = tonumber(seed)
				if role and seed and StaffRig and StaffRig.ROLES[role] and seed >= 1 and seed <= 1e9 then who = { role = role, seed = seed } end
			end
			spawnStaff(player, plot, i, talent, who)
			local r = s.rigs[#s.rigs]
			local tier = type(data.tiers) == "table" and clampInt(data.tiers[i], 1, #CFG.TIER_TITLE, 1) or 1
			if r then
				r.tier = tier
				r.seatedTime = (tier - 1) * CFG.PROMOTE_EVERY
				StaffRig.setTitle(r.rig, titleOf(r))
			end
		end
		s.indexQuiet = false
		if Econ and Econ.publishIndex then Econ.publishIndex(player, s) end
		s.playtime = clampInt(data.playtime, 0, 1e9, 0)
		s.muted = data.muted == true
		s.alumni = clampInt(data.alumni, 0, CFG.ALUMNI_CAP, 0)
		player:SetAttribute("Alumni", s.alumni)
		s.work = clampInt(data.work, 0, 1e9, 0)
		s.workNeed = math.floor(CFG.WORK_FIRST * (CFG.WORK_GROWTH ^ ((Econ and Econ.V3) and s.runLaunches or s.launches or 0)))
		s.spinoffs = clampInt(data.spinoffs, 0, Prog.SPIN_CAP, 0)
		local path = type(data.hqPath) == "string" and data.hqPath or nil
		s.hqPath = (path == "T_" or path == "D_" or path == "W_") and path or nil
		-- pre-v2.4 saves have no `earned`; valuation is the closest honest proxy
		s.earned = data.earned ~= nil and clampInt(data.earned, 0, 1e15, 0) or clampInt(data.valuation, 0, 1e15, 0)
		s.milestones = milestonesFromEarned(s.earned)
		s.dailyDay = clampInt(data.dailyDay, 0, 1e6, 0)
		s.streak = clampInt(data.streak, 0, 7, 0)
		-- v4.0: the apartment (clamped) and the cars (validated against the catalog)
		s.apt = clampInt(data.apt, 0, 3, 0)
		s.vipDay = clampInt(data.vipDay, 0, 1e7, 0)
		s.jr = Journey.cleanFlags(data.jr)        -- v4.3 only known flags survive a load
		s.tips = Journey.cleanTips(data.tips)
		s.listed = data.listed == true
		if Econ and Econ.Apt then pcall(Econ.Apt.onLoad, player, s) end
		if Econ and Econ.Cars then pcall(Econ.Cars.onLoad, player, s, data, plot) end
		recompute(player)
		refreshSign(plot)
		refreshHqPad(plot)
		updateHirePad(player)
	end

	local function loadOnce(player, plot)
		if loading[player.UserId] then return end
		loading[player.UserId] = true
		local data, ok = nil, false
		if saveStore then
			ok, data = pcall(function() return saveStore:GetAsync(tostring(player.UserId)) end)
			if not ok then
				warn("[SV] load FAILED for " .. player.Name .. " -- this session will not save")
				data = nil
			end
		end
		loading[player.UserId] = nil
		if ok then loaded[player.UserId] = true end     -- a failed read never saves
		if data then
			player:SetAttribute("Returning", true)
			applySave(player, plot, data)
		end
		if Econ and Econ.Inv then pcall(Econ.Inv.load, player, sessions[player.UserId], data and data.items) end
		if Econ and Econ.Daily and Econ.Daily.refresh then pcall(Econ.Daily.refresh, player) end
	end

	game:BindToClose(function()
		for _, pl in ipairs(Players:GetPlayers()) do saveNow(pl); pushTicker(pl) end
		task.wait(1)
	end)
	task.spawn(function()
		while true do
			task.wait(120)
			for _, pl in ipairs(Players:GetPlayers()) do saveNow(pl) end
		end
	end)

	return {
		applySave = applySave,
		clampInt = clampInt,
		loadOnce = loadOnce,
		saveNow = saveNow,
		serialize = serialize,
	}
end
