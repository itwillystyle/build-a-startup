--[[ DevHook: the Studio-only SVDev BindableFunction (test actions: cash,
upgrade, spinoff, bot, peek, wipe, ...). Moved out of SiliconCore on 28 Sep
2026 (v4.2). SiliconCore calls it at the same load point, Studio only, and
passes its own script (SVDev stays under SiliconCore, where tools look). ]]
return function(core)
	local coreScript = core.coreScript
	local goPublic = core.goPublic
	local CFG = core.CFG
	local Econ = core.Econ
	local SaveLoad = core.SaveLoad
	local StaffRig = core.StaffRig
	local boostOf = core.boostOf
	local buildWing = core.buildWing
	local capacityOf = core.capacityOf
	local cashOf = core.cashOf
	local checkIPO = core.checkIPO
	local checkMilestones = core.checkMilestones
	local deskHomes = core.deskHomes
	local hire = core.hire
	local hqMultOf = core.hqMultOf
	local launchProduct = core.launchProduct
	local loaded = core.loaded
	local offerAmountOf = core.offerAmountOf
	local offerEvent = core.offerEvent
	local offerProduct = core.offerProduct
	local placeAt = core.placeAt
	local plotOf = core.plotOf
	local recompute = core.recompute
	local refreshSign = core.refreshSign
	local rivalLaunch = core.rivalLaunch
	local saveStore = core.saveStore
	local sessions = core.sessions
	local spinOff = core.spinOff
	local spinoffCostOf = core.spinoffCostOf
	local tickerOf = core.tickerOf
	local titleOf = core.titleOf
	local tryUpgrade = core.tryUpgrade
	local updateHirePad = core.updateHirePad
	local upgradeWing = core.upgradeWing
	local wingMaxed = core.wingMaxed
	local writeCode = core.writeCode

	local dev = Instance.new("BindableFunction")
	dev.Name = "SVDev"
	dev.Parent = coreScript
	dev.OnInvoke = function(action, player, arg)
		local s = sessions[player.UserId]
		local plot = plotOf(player)
		if not s then return "no session" end
		if action == "ship" then
			s.shipped = true
			s.buildUnlocked = true
			updateHirePad(player)
			return "ok"
		elseif action == "cash" then
			local c = cashOf(player)
			if c then c.Value += (tonumber(arg) or 0) end
			return "ok"
		elseif action == "upgrade" then
			if plot then tryUpgrade(player, plot) end
			return "ok"
		elseif action == "spinoff" then
			if not plot then return "no plot" end
			plot.spinArmed = os.clock() - 1        -- skip the confirm tap
			spinOff(player, plot)
			return ("spinoffs=%d rate=%d"):format(s and s.spinoffs or -1, s and s.rate or -1)
		elseif action == "earned" then
			if s then s.earned = tonumber(arg) or 0; checkMilestones(player, s) end
			return ("earned=%d milestones=%d rate=%d"):format(s and s.earned or 0, s and s.milestones or 0, s and s.rate or 0)
		elseif action == "talent" then
			-- v2.5: set the LAST hire's talent (1..5) for testing; snapshot the record first
			local r = s and s.rigs and s.rigs[#s.rigs]
			if not r then return "no staff" end
			r.talent = SaveLoad.clampInt(tonumber(arg), 1, #CFG.TALENT, 1)
			local t = CFG.TALENT[r.talent]
			if t.color and StaffRig.setTalent then StaffRig.setTalent(r.rig, r.talent, t.color, t.name) end
			StaffRig.setTitle(r.rig, titleOf(r))
			recompute(player)
			return ("talent=%s x%.1f rate=%d"):format(t.name, t.mult, s.rate)
		elseif action == "save" then
			return SaveLoad.saveNow(player) and "saved" or "NOT saved"
		elseif action == "rival" then
			return "hit " .. rivalLaunch()
		elseif action == "launch" then
			local m = CFG.MARKETS[tonumber(arg) or 1]
			if plot and m then launchProduct(player, plot, m) end
			return "launched " .. (m and m.name or "?")
		elseif action == "buzzoff" then
			s.launch = nil
			return "buzz cleared"
		elseif action == "wingup" then
			local slot = plot and plot.slots[tonumber(arg) or 1]
			if not slot or not slot.built then return "no wing there" end
			upgradeWing(player, plot, slot)
			return ("%s lv%d desks=%d compute=%d quality=%.2f morale=%.2f"):format(slot.room.name, slot.level, s.desks, s.compute or 0, s.quality or 0, s.morale or 0)
		elseif action == "share" then
			s.share = math.clamp(tonumber(arg) or 1, CFG.SHARE_FLOOR, 1)
			return "share " .. s.share
		elseif action == "peek" then
			local ok, d = pcall(function() return saveStore and saveStore:GetAsync(tostring(player.UserId)) end)
			return ok and d or ("err " .. tostring(d))
		elseif action == "wipe" then
			pcall(function() saveStore:RemoveAsync(tostring(player.UserId)) end)
			return "wiped"
		elseif action == "offer" then
			-- fire one acquisition offer now (same code path as the loop)
			local best
			for _, r in ipairs(s.rigs or {}) do
				if (r.tier or 1) >= CFG.OFFER_MIN_TIER and (not best or r.tier > best.tier) then best = r end
			end
			if not best then return "nobody above tier " .. CFG.OFFER_MIN_TIER end
			-- capped at rehire cost + 60s of the person's output: selling a Lead
			-- and rehiring an intern must never be a money printer (it was: quality
			-- scaled the offer but not the hire)
			local cashNow = cashOf(player)
			local amount = offerAmountOf(s, cashNow and cashNow.Value or 0)
			local id = (s.offerSerial or 0) + 1
			s.offerSerial = id
			s.pendingOffer = { id = id, entry = best, amount = amount, rival = CFG.RIVALS[1] }
			offerEvent:FireClient(player, { id = id, rival = CFG.RIVALS[1], who = best.rig:GetAttribute("PersonName") or "?",
				title = titleOf(best), amount = amount, tier = best.tier,
				minutes = (s.rate or 0) > 0 and amount / s.rate / 60 or 0,
				loss = math.floor((CFG.TIER_RATE[best.tier] - CFG.TIER_RATE[1]) * hqMultOf(plot)),
				alumni = math.min(s.alumni or 0, CFG.ALUMNI_CAP), step = CFG.ALUMNI_STEP })
			return ("offered $%d for %s"):format(amount, tostring(best.rig:GetAttribute("PersonName")))
		elseif action == "tier" then
			local r = s.rigs and s.rigs[1]
			if r then r.tier = tonumber(arg) or 1; r.seatedTime = (r.tier - 1) * CFG.PROMOTE_EVERY
				StaffRig.setTitle(r.rig, titleOf(r)); recompute(player) end
			return "tier set"
		elseif action == "phone" then
			-- v4.3 test hook: the live investor thread (Series A check)
			local a = Econ and Econ.Phone and Econ.Phone.devActive and Econ.Phone.devActive(player)
			return a or "no active thread"
		elseif action == "phoneoffer" then
			local amount, id = Econ.Phone.devOffer(player, tonumber(arg) or 8)
			return { amount = amount, id = id, rate = s.rate }
		elseif action == "gopublic" then
			-- v4.3 test hook: the GO PUBLIC button
			if plot then goPublic(player, plot) end
			return ("listed=%s ticker=%s"):format(tostring(s.listed), tostring(s.ticker))
		elseif action == "hire" then
			-- v4.3 test hook: one hire through the real hire() (after a spin-off the HQ needs staff)
			if plot then hire(player, plot) end
			return ("staff=%d"):format(s.staff or 0)
		elseif action == "work" then
			s.work = tonumber(arg) or 0
			return "work set"
		elseif action == "product" then
			if plot then offerProduct(player, plot) end
			return "offered"
		elseif action == "name" then
			s.name = tostring(arg); s.ticker = tickerOf(s.name); if plot then refreshSign(plot) end
			return "named"
		elseif action == "valuation" then
			s.valuation = tonumber(arg) or 0
			if plot then checkIPO(player, plot) end
			return "ok"
		elseif action == "bot" then
			--[[ v2.7.2 CLEAN-RUN BOT. Plays the real handlers (the same ones the
			prompts, pads and remotes call) by following the on-screen guide:
			taps WRITE CODE once a second, launches a ready product after 2 s,
			and makes one guide purchase every `pace` seconds when it can afford
			it. Logs HQ times, spin-off, waits, and launch share. Read with
			"botlog". Studio only, like the rest of this hook. ]]
			local pace = tonumber(arg) or 20
			s.bot = { t0 = os.clock(), log = {}, pace = pace, paid = 0, earnedStart = s.earned or 0, lastBuy = os.clock(), longest = 0, buys = 0, fails = 0, running = true }
			local B = s.bot
			local function note(ev)
				local line = ("%5.1f min  %s"):format((os.clock() - B.t0) / 60, ev)
				table.insert(B.log, line)
				print("[BOT] " .. line)
			end
			note(("start  pace %ds  hq %d  cash %d"):format(pace, plot.hq.level, cashOf(player).Value))
			task.spawn(function()
				local lastTap, lastMin, lastHq = 0, -1, plot.hq.level
				while B.running and player.Parent and sessions[player.UserId] == s do
					local now = os.clock()
					local cash = cashOf(player)
					if now - lastTap >= 1 then lastTap = now; writeCode(player, plot) end
					if s.pendingProduct and not B.launchAt then B.launchAt = now + 2 end
					if B.launchAt and now >= B.launchAt then
						B.launchAt = nil
						if s.pendingProduct then
							local before = cash.Value
							launchProduct(player, plot, s.pendingProduct[1], 1, false)
							B.paid += cash.Value - before
						end
					end
					-- v3.0.2: log every carry's outcome (home or lost) per tier
					if B.carry and not player:GetAttribute("Carrying") then
						local ok = s.staff > B.carry.staff
						B.carries = B.carries or {}
						local k = B.carry.tier .. (ok and " home" or " LOST")
						B.carries[k] = (B.carries[k] or 0) + 1
						note(("carry %s %s after %.0f s"):format(B.carry.tier, ok and "home" or "LOST", now - B.carry.t0))
						B.carry = nil
					end
					local key = player:GetAttribute("Objective")
					-- v3.0: carrying a candidate home = walk there at the default 16 studs/s
					if key == "carry" then
						local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
						local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
						-- (the guide's objective lags delivery by up to 0.4 s: only a real carry counts)
						if root and hum and player:GetAttribute("Carrying") then
							-- v3.0.2: walk like a person, not a laser: your real (scooter) speed,
							-- a +-35 degree weave round lamps and cars, and one 1.5 s stop
							-- a third of the way home to look around
							B.carry = B.carry or { t0 = now, tier = player:GetAttribute("Carrying") or "?", staff = s.staff }
							local to = plot.hqPad.Position
							local d = Vector3.new(to.X - root.Position.X, 0, to.Z - root.Position.Z)
							B.carry.total = B.carry.total or d.Magnitude
							if not B.carry.stopAt and d.Magnitude < B.carry.total * 0.67 then B.carry.stopAt = now end
							local stopped = B.carry.stopAt and now - B.carry.stopAt < 1.5
							if d.Magnitude > 1 and not stopped then
								local dir = CFrame.Angles(0, math.sin((now - B.carry.t0) * 1.3) * math.rad(35), 0):VectorToWorldSpace(d.Unit)
								local np = root.Position + dir * math.min(d.Magnitude, hum.WalkSpeed * 0.25)
								player.Character:PivotTo(CFrame.lookAt(np, np + dir))
							end
						end
					elseif key == "recruit" and now - B.lastBuy >= pace and Econ.Drop then
						local cand = Econ.Drop.bestFor(player, cash.Value)
						local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
						if cand and root then
							-- walk out (time it like the sim: distance / 16), then recruit
							local walk = (Vector3.new(cand.pos.X, 0, cand.pos.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude / 16
							task.wait(walk)
							player.Character:PivotTo(CFrame.new(cand.pos + Vector3.new(0, 1, 3)))
							Econ.Drop.devRecruit(player, cand.index)
							B.recruits = (B.recruits or 0) + 1
							note(("recruit %s (walked %.0f s)"):format(cand.tier.name, walk))
							B.lastBuy = os.clock()
						end
					end
					--[[ v4.4 THE v4.3 JOURNEY, played like a person. Before this the bot
					stood still on every Journey key (car, drive, vip, genius, gopublic,
					seriesa), so the first hour after v4.3 was never measured. Travel is
					timed from real distances: walking 16 studs/s, driving ~50 (the
					hatchback tops out at 64; corners and parking eat the rest). ]]
					local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					local desk = Econ and Econ.Apt and Econ.Apt.deskPosition and Econ.Apt.deskPosition()
					local farFromDesk = not (root and desk) or (root.Position - desk).Magnitude > 120
					if key == "car" then
						local cp = Econ.Cars and Econ.Cars.carPos and Econ.Cars.carPos(player)
						if not B.carAt then
							B.carAt = now + ((root and cp) and (cp - root.Position).Magnitude / 16 or 4) + 1.5
						elseif now >= B.carAt then
							B.carAt = nil
							s.jr = s.jr or {}
							s.jr.drove = true
							note("car: walked over and got in")
						end
					elseif (key == "drive" or (key == "apartment" and farFromDesk)) and desk and root then
						if not B.driveAt then
							B.driveAt = now + (desk - root.Position).Magnitude / 50 + 5
						elseif now >= B.driveAt then
							B.driveAt = nil
							player.Character:PivotTo(CFrame.new(desk + Vector3.new(0, 3, 10)))
							note(("drove downtown (%s)"):format(key))
						end
					elseif key == "vip" and Econ.Drop and Econ.Drop.vipPos and root then
						local vp = Econ.Drop.vipPos(player)
						if vp and not B.vipAt then
							B.vipAt = now + (vp - root.Position).Magnitude / 16 + 1
						elseif vp and now >= B.vipAt then
							B.vipAt = nil
							player.Character:PivotTo(CFrame.new(vp + Vector3.new(0, 1, 3)))
							Econ.Drop.devPickVip(player)
							note("picked up the VIP")
						end
					elseif key == "genius" and Econ.Drop and Econ.Drop.candidate and root and now - B.lastBuy >= pace then
						local cand = Econ.Drop.candidate(player, "genius", cash.Value)
						local gi
						for i, t in ipairs(Econ.TIERS or {}) do if t.id == "genius" then gi = i end end
						if cand and gi then
							local walk = (Vector3.new(cand.pos.X, 0, cand.pos.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude / 16
							task.wait(walk)
							player.Character:PivotTo(CFrame.new(cand.pos + Vector3.new(0, 1, 3)))
							Econ.Drop.devRecruit(player, gi)
							note(("recruit GENIUS (walked %.0f s)"):format(walk))
							B.lastBuy = os.clock()
						end
					elseif key == "gopublic" and goPublic then
						if not B.ipoAt then
							B.ipoAt = now + 3
						elseif now >= B.ipoAt then
							B.ipoAt = nil
							goPublic(player, plot)
							note("GO PUBLIC")
						end
					elseif root and plot.hqPad and key ~= "carry" and key ~= "recruit"
						and (root.Position - plot.hqPad.Position).Magnitude > 300 then
						-- anything else happens at home: drive back first
						if not B.homeAt then
							B.homeAt = now + (root.Position - plot.hqPad.Position).Magnitude / 50 + 3
						elseif now >= B.homeAt then
							B.homeAt = nil
							player.Character:PivotTo(plot.hqPad.CFrame + Vector3.new(0, 4, 0))
							note("drove home")
						end
					end
					-- the phone: read the investor's texts (~25 s), then take the term sheet
					if Econ and Econ.Phone and Econ.Phone.devActive then
						local a = Econ.Phone.devActive(player)
						if a and a.status ~= "closed" and a.status ~= "busy" then
							B.phoneSince = B.phoneSince or now
							if now - B.phoneSince >= 25 then
								local paid, series = Econ.Phone.devTake(player, 6)
								if paid then
									note(("phone deal%s  +$%d"):format(series and " (SERIES A)" or "", paid))
									B.phoneSince = nil
								end
							end
						else
							B.phoneSince = nil
						end
					end
					if now - B.lastBuy >= pace then
						local before = cash.Value
						local did
						if key == "hire" or key == "hire2" then
							hire(player, plot); did = "hire"
						elseif key == "build" or key == "wing" or key == "vipseat" then
							for i, slot in ipairs(plot.slots) do
								if not slot.built then
									local rid = (Econ and Econ.V3) and Econ.nextRoom(plot) or "office"
									if buildWing(player, plot, i, rid, false) then did = "build " .. rid end
									break
								end
							end
							-- v4.4 "make room for your VIP": every open lot is built, so a level adds the seats
							if not did and key == "vipseat" then
								for _, slot in ipairs(plot.slots) do
									if slot.built and not wingMaxed(s, slot) then
										local lv = slot.level or 1
										upgradeWing(player, plot, slot)
										if (slot.level or 1) > lv then did = ("level %s -> %d (VIP seat)"):format(slot.room.id, slot.level) end
										break
									end
								end
							end
						elseif key == "wingup" then
							for _, slot in ipairs(plot.slots) do
								if slot.built and not wingMaxed(s, slot) then
									local lv = slot.level or 1
									upgradeWing(player, plot, slot)
									if (slot.level or 1) > lv then did = ("level %s -> %d"):format(slot.room.id, slot.level) end
									break
								end
							end
						elseif key == "decor" then
							-- v3.2.1: a guide-following player decorates until the first Vibe star
							local keys = { "pottedPlant", "lampSquareFloor", "cardboardBoxClosed" }
							local k = keys[(#s.placed % #keys) + 1]
							for gx = -12, 12, 4 do
								for gz = -10, 10, 4 do
									if not did then
										local at = plot.g(gx, 0, gz).Position
										if placeAt(player, plot, k, at.X, at.Z, 0, false) then did = "decor " .. k end
									end
								end
							end
						elseif key == "hq" then
							local nxt = CFG.HQ_LEVELS[plot.hq.level + 1]
							if nxt and cash.Value >= nxt.cost then tryUpgrade(player, plot); did = "hq" end
						elseif key == "apartment" and Econ and Econ.Apt and Econ.Apt.botBuy and not farFromDesk then
							if Econ.Apt.botBuy(player) then did = "apartment" end
						elseif key == "spin" then
							if cash.Value >= spinoffCostOf(s) then
								plot.spinArmed = os.clock() - 1
								spinOff(player, plot)
								note(("SPIN-OFF  (kept %d staff)  launch share %.0f%%"):format(s.staff or 0,
									100 * B.paid / math.max(1, (s.earned or 0) - B.earnedStart)))
								B.spun = (B.spun or 0) + 1
								if B.spun >= (tonumber(B.runs) or 1) then B.running = false end
								did = "spin"
							end
						end
						if did then
							local spent = before - cash.Value
							if spent > 0 or did == "spin" then
								local wait = now - B.lastBuy
								B.buys += 1
								if wait > B.longest and B.buys > 1 then B.longest = wait end
								if wait > pace + 45 then note(("long wait %.0f s before %s"):format(wait, did)) end
								B.lastBuy = now
								if did ~= "hq" and did ~= "spin" and did ~= "hire" then note(("%s  $%d"):format(did, spent)) end
							elseif did ~= "hq" and not (did == "hire" and s.staff == 1) then
								B.fails += 1
								if B.fails <= 12 then note(("REFUSED %s (guide said %s, cash %d)"):format(did, tostring(key), cash.Value)) end
							end
						end
					end
					if plot.hq.level ~= lastHq then
						lastHq = plot.hq.level
						note(("HQ %d  staff %d  rate %d/s  rooms %d"):format(lastHq, s.staff, s.rate or 0, Econ and Econ.slotsBuilt(plot) or 0))
					end
					local m = math.floor((now - B.t0) / 60)
					if m ~= lastMin then
						lastMin = m
						if m % 2 == 0 then
							note(("tick  cash %d  rate %d  staff %d/%d  guide %s: %s"):format(cash.Value, s.rate or 0, s.staff,
								capacityOf(player), tostring(key), tostring(player:GetAttribute("ObjectiveText"))))
						end
					end
					if now - B.t0 > 45 * 60 then note("TIMEOUT 45 min"); B.running = false end
					task.wait(0.25)
				end
				note(("end  buys %d  longest wait %.0f s  refused %d"):format(B.buys, B.longest, B.fails))
				for k, v in pairs(B.carries or {}) do note(("carries  %s x%d"):format(k, v)) end
			end)
			return "bot started"
		elseif action == "rolls" then
			-- v3.2.1 test hook: roll the door talent n times at this player's Vibe luck
			local n = math.clamp(tonumber(arg) or 20000, 1, 200000)
			local luck = player:GetAttribute("VibeLuck") or 1
			local counts = { 0, 0, 0, 0, 0 }
			for _ = 1, n do local t = CFG.TALENT.roll(luck); counts[t] += 1 end
			return ("luck %.1f  n %d  regular %d  skilled %d  star %d  genius %d  unicorn %d"):format(luck, n, counts[1], counts[2], counts[3], counts[4], counts[5])
		elseif action == "item" then
			-- v3.2 test hook: put an item in the bag (Items.LIST id)
			if not (Econ and Econ.Inv) then return "no Inventory" end
			return Econ.Inv.grant(player, tostring(arg), 1, "Dev") and "granted" or "unknown item"
		elseif action == "seats" then
			-- v3.5 audit hook: the seat homes the game seats people at (world x, z)
			local t = {}
			for _, h in ipairs(deskHomes(s, plot)) do table.insert(t, { h.cf.Position.X, h.cf.Position.Z, h.room }) end
			return t
		elseif action == "apt" then
			-- v4.2 test hook: set the apartment rung (0-3)
			s.apt = math.clamp(math.floor(tonumber(arg) or 0), 0, 3)
			recompute(player)
			return "apt=" .. s.apt
		elseif action == "vip" then
			-- v4.2 test hook: the daily VIP now, ignoring the day
			local okV = Econ and Econ.Apt and Econ.Apt.trySpawnVip and Econ.Apt.trySpawnVip(player, true)
			return okV and "vip spawned" or "no vip"
		elseif action == "vippick" then
			if not (Econ and Econ.Drop and Econ.Drop.devPickVip) then return "no TalentDrop" end
			Econ.Drop.devPickVip(player)
			return ("carrying=%s vipDay=%s"):format(tostring(player:GetAttribute("Carrying")), tostring(s.vipDay))
		elseif action == "recruit" then
			-- v3.0 test hook: recruit tier n (1 walk-in .. 4 genius) through the real recruit()
			if not (Econ and Econ.Drop) then return "no TalentDrop" end
			Econ.Drop.devRecruit(player, tonumber(arg) or 1)
			return ("carrying=%s"):format(tostring(player:GetAttribute("Carrying")))
		elseif action == "botlog" then
			return s.bot and table.concat(s.bot.log, "\n") or "no bot"
		elseif action == "botstop" then
			if s.bot then s.bot.running = false end
			return "stopping"
		elseif action == "state" then
			return { plot = plot and plot.index or 0, hqLevel = plot and plot.hq.level or 0,
				shipped = s.shipped, placedDesks = s.placedDesks, placedMorale = s.placedMorale,
				placed = #s.placed, capacity = capacityOf(player), rate = s.rate, staff = s.staff,
				name = s.name, valuation = s.valuation, ipo = s.ipo, launches = s.launches,
				boost = boostOf(s), loaded = loaded[player.UserId] == true,
				work = s.work, workNeed = s.workNeed, pendingOffer = s.pendingOffer ~= nil,
				tiers = (function() local t = {} for i, r in ipairs(s.rigs or {}) do t[i] = r.tier end return table.concat(t, ",") end)() }
		end
		return "unknown"
	end
end
