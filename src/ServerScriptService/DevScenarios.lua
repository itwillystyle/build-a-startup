--[[ DevScenarios: one call puts the game in a known state for a live check (v5.1, 9 Oct 2026).

	WHY. Every live test used to rebuild its own setup by hand: ship, cash, a first
	hire, enough HQ for the tier, walk to the candidate, recruit. Each step has a way
	to fail quietly (genius needs HQ stage 3, recruit() has no distance check, a
	candidate may be restocking). A scenario does the setup the same way every time
	and says which step failed.

	HOW TO CALL (Studio, Play, SERVER datamodel):
	    local p = game.Players:GetPlayers()[1]
	    local dev = game.ServerScriptService.SiliconCore.SVDev
	    return dev:Invoke("scenario", p, "chase:genius")

	It must go through SVDev. A require() from execute_luau returns a FRESH copy of a
	module, so it would drive an unused copy of the game (DevHook.lua, "bell").

	The save helpers snapshot()/restore() only touch the DataStore, so they also work
	from the EDIT datamodel. restore() must run after Play stops: the stop's
	save-on-leave would overwrite anything written before it.
	    require(game.ServerScriptService.DevScenarios).restore(1688749216)

	SAFETY. Studio only, and only for test accounts: Wilz (the alt Studio plays as)
	and negative ids (Studio's local test players). The main account's save is never
	touched. Destructive scenarios refuse to run until a snapshot exists. ]]

local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local Scen = {}

Scen.TEST_USERS = { [1688749216] = true } -- Wilz (devmeistah)
local SAVE_STORE, SNAP_STORE = "SVSave_v1", "SVSnap_v1"
local TIER_INDEX = { walkin = 1, skilled = 2, star = 3, genius = 4 }
local snapped = {} -- userId -> true once a snapshot was taken in THIS server

Scen.LIST = {
	"snapshot", "rich", "ready", "chase:skilled", "chase:star", "chase:genius",
	"vip-chase", "hq:<n>", "home:<0-3>", "spinoff", "tp:hq", "tp:apt", "tp:car",
	"tp:candidate:<tier>", "tp:vip", "list",
}

local function allowed(userId)
	return RunService:IsStudio() and (Scen.TEST_USERS[userId] == true or userId < 0)
end

local function short(v)
	if type(v) == "table" then
		local ok, j = pcall(function() return HttpService:JSONEncode(v) end)
		v = ok and j or "table"
	end
	v = tostring(v)
	return #v > 160 and (v:sub(1, 157) .. "...") or v
end

function Scen.snapshot(userId)
	if not allowed(userId) then return { ok = false, err = "not a test account" } end
	local key = tostring(userId)
	local okGet, rec = pcall(function() return DataStoreService:GetDataStore(SAVE_STORE):GetAsync(key) end)
	if not okGet then return { ok = false, err = "read failed: " .. tostring(rec) } end
	if type(rec) ~= "table" then return { ok = false, err = "no save to snapshot" } end
	local okSet, e = pcall(function()
		DataStoreService:GetDataStore(SNAP_STORE):SetAsync(key, { at = os.time(), rec = rec })
	end)
	if not okSet then return { ok = false, err = "write failed: " .. tostring(e) } end
	snapped[userId] = true
	return { ok = true, lastSeen = rec.lastSeen }
end

function Scen.restore(userId)
	if not allowed(userId) then return { ok = false, err = "not a test account" } end
	local key = tostring(userId)
	local okGet, snap = pcall(function() return DataStoreService:GetDataStore(SNAP_STORE):GetAsync(key) end)
	if not okGet then return { ok = false, err = "read failed: " .. tostring(snap) } end
	if type(snap) ~= "table" or type(snap.rec) ~= "table" then return { ok = false, err = "no snapshot" } end
	local rec = snap.rec
	-- a stale clock would pay offline earnings for however long the test took
	rec.lastSeen = os.time()
	local okSet, e = pcall(function() DataStoreService:GetDataStore(SAVE_STORE):SetAsync(key, rec) end)
	if not okSet then return { ok = false, err = "write failed: " .. tostring(e) } end
	return { ok = true, snapAt = snap.at }
end

-- ctx comes from DevHook: { handle = <the SVDev handler>, Econ = Econ, cashOf = cashOf, plotOf = plotOf }
function Scen.run(ctx, player, name)
	if not allowed(player.UserId) then
		return { ok = false, err = "scenarios only run in Studio, on a test account" }
	end
	name = tostring(name or "list")
	local did = {}
	local function step(action, arg)
		local r = ctx.handle(action, player, arg)
		table.insert(did, ("%s%s -> %s"):format(action, arg ~= nil and (" " .. tostring(arg)) or "", short(r)))
		return r
	end
	local function state() return ctx.handle("state", player) end
	local function done(ok, err, extra)
		local out = { ok = ok, err = err, scenario = name, did = did, state = state() }
		for k, v in pairs(extra or {}) do out[k] = v end
		return out
	end
	local Econ = ctx.Econ or {}
	local function root()
		local c = player.Character
		return c and c:FindFirstChild("HumanoidRootPart")
	end
	local function goTo(pos)
		if not (pos and player.Character) then return false end
		player.Character:PivotTo(CFrame.new(pos + Vector3.new(0, 1, 3)))
		return true
	end

	-- ship, money, one person, and an HQ stage of at least `needStage`
	local function ready(needStage)
		step("ship")
		local cash = ctx.cashOf(player)
		if cash and cash.Value < 1e8 then step("cash", 1e9) end
		if (state().staff or 0) < 1 then step("hire") end
		local st = state()
		if (st.hqLevel or 0) < needStage then
			local W = Econ.Wafers
			if not (W and W.stage) then return false, "HQ is stage " .. tostring(st.hqLevel) .. " and Wafers is off" end
			local target
			for n = 1, 40 do
				if W.stage(n) >= needStage then target = n break end
			end
			if not target then return false, "no Wafers level reaches stage " .. needStage end
			step("wlevel", target)
			st = state()
			if (st.hqLevel or 0) < needStage then
				return false, ("HQ stage %s after wlevel %d, need %d (blueprint cap?)"):format(tostring(st.hqLevel), target, needStage)
			end
		end
		st = state()
		if (st.capacity or 0) <= (st.staff or 0) then
			return false, ("no free seat (capacity %s, staff %s)"):format(tostring(st.capacity), tostring(st.staff))
		end
		return true
	end

	local kind, rest = name:match("^([%w%-]+):?(.*)$")
	kind = kind or name

	if kind == "list" then
		return { ok = true, scenarios = Scen.LIST }
	elseif kind == "snapshot" then
		local r = Scen.snapshot(player.UserId)
		table.insert(did, "snapshot -> " .. short(r))
		return done(r.ok, r.err)
	elseif kind == "rich" then
		step("cash", 1e9)
		return done(true)
	elseif kind == "ready" then
		local ok, err = ready(1)
		return done(ok, err)
	elseif kind == "chase" then
		local tierId = rest ~= "" and rest or "genius"
		local i = TIER_INDEX[tierId]
		local tier = i and Econ.TIERS and Econ.TIERS[i]
		if not (tier and tier.chase) then return done(false, "no chase tier '" .. tierId .. "'") end
		if not (Econ.Drop and Econ.Drop.candidate) then return done(false, "TalentDrop is not running") end
		local ok, err = ready(tier.hq or 1)
		if not ok then return done(false, err) end
		local cash = ctx.cashOf(player)
		local cand = Econ.Drop.candidate(player, tierId, cash and cash.Value or 0)
		if not cand then
			return done(false, ("no %s candidate standing (restock is %ss) or the fee is unaffordable"):format(tierId, tostring(tier.restock)))
		end
		-- recruit() has no distance check: without this the hunter spawns at the candidate, far away
		goTo(cand.pos)
		task.wait(0.3)
		step("recruit", i)
		task.wait(0.5)
		local hunters = 0
		for _, d in workspace:GetDescendants() do
			if d.Name == "Headhunter" and d:IsA("Model") then hunters += 1 end
		end
		local carrying = player:GetAttribute("Carrying")
		return done(carrying ~= nil and carrying ~= false and hunters > 0,
			(carrying and hunters > 0) and nil or "recruit did not start a chase",
			{ carrying = carrying, hunters = hunters, fee = cand.fee })
	elseif kind == "vip-chase" then
		local ok, err = ready(1)
		if not ok then return done(false, err) end
		step("apt", 1)
		step("vip")
		local vp = Econ.Drop and Econ.Drop.vipPos and Econ.Drop.vipPos(player)
		if not vp then return done(false, "no VIP spawned") end
		goTo(vp)
		task.wait(0.3)
		step("vippick")
		return done(player:GetAttribute("Carrying") ~= nil, nil, { carrying = player:GetAttribute("Carrying") })
	elseif kind == "hq" then
		local n = tonumber(rest)
		if not n then return done(false, "usage: hq:<wafer level>") end
		step("wlevel", n)
		return done(true)
	elseif kind == "home" then
		local n = tonumber(rest)
		if not n then return done(false, "usage: home:<0-3>") end
		step("apt", n)
		return done(true)
	elseif kind == "spinoff" then
		if not snapped[player.UserId] then
			return done(false, "destructive: run the 'snapshot' scenario first")
		end
		step("gopublic")
		task.wait(1)
		step("spinoff")
		return done(true)
	elseif kind == "tp" then
		local plot = ctx.plotOf(player)
		local where, tierId = rest:match("^(%w+):?(.*)$")
		local pos
		if where == "hq" then
			pos = plot and plot.hqPad and plot.hqPad.Position
		elseif where == "apt" then
			pos = Econ.Apt and Econ.Apt.deskPosition and Econ.Apt.deskPosition()
		elseif where == "car" then
			pos = Econ.Cars and Econ.Cars.carPos and Econ.Cars.carPos(player)
		elseif where == "candidate" then
			local cash = ctx.cashOf(player)
			local cand = Econ.Drop and Econ.Drop.candidate and Econ.Drop.candidate(player, tierId ~= "" and tierId or "genius", cash and cash.Value or 0)
			pos = cand and cand.pos
		elseif where == "vip" then
			pos = Econ.Drop and Econ.Drop.vipPos and Econ.Drop.vipPos(player)
		end
		if typeof(pos) == "CFrame" then pos = pos.Position end
		if typeof(pos) ~= "Vector3" then return done(false, "no position for '" .. tostring(rest) .. "'") end
		goTo(pos)
		table.insert(did, ("tp -> %.0f, %.0f, %.0f"):format(pos.X, pos.Y, pos.Z))
		local r = root()
		return done(r ~= nil, r and nil or "no character")
	end
	return done(false, "unknown scenario '" .. name .. "' (try 'list')")
end

return Scen
