--[[ LiftCab (15 Oct 2026, HQ project #1 part 1b): the server side of the tower's lift. One cab per
	tower. The rules are LiftPlan's (tested); this module keeps each cab's queue, opens and closes
	the landing doors, and publishes the ride as attributes on the cab model. It never moves the cab
	frame by frame: every client animates it from (FromY, ToY, Start, Dur) and carries its own
	character with it (LiftClient), then the server sets the cab's resting place on arrival. ]]
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local T = require(RS:WaitForChild("TowerPlan"))
local LP = require(RS:WaitForChild("LiftPlan")).with(T)
local Movement = require(game:GetService("ServerScriptService"):WaitForChild("Movement"))

local LiftCab = {}
local api = {}
local cabs = {}          -- plot.index -> { plot, model, plan, stops, busy }
-- riders whose ride a rebuild cut short: sync puts them back in the new cab (RF3, 15 Oct: with a
-- solid ceiling they fell down the shaft onto the cab's roof and were stuck between floors)
local stranded = {}
local lastCall = {}      -- player -> os.clock()
local rng = Random.new()

local function stopIndex(c, id)
	for i, s in ipairs(c.stops) do if s.id == id then return i end end
	return nil
end

local function cabBox(c)
	local C = T.CAB
	return c.model.PrimaryPart.CFrame * CFrame.new(0, C.h / 2, 0), Vector3.new(C.w, C.h, C.d)
end
local function inside(c, pos, pad)
	local cf, size = cabBox(c)
	local l = cf:PointToObjectSpace(pos)
	pad = pad or 0
	return math.abs(l.X) <= size.X / 2 + pad and math.abs(l.Y) <= size.Y / 2 + pad and math.abs(l.Z) <= size.Z / 2 + pad
end
-- a position in the cab's own frame: x across, y up from the cab floor, z toward the doors
local function floorCF(c) return c.model.PrimaryPart.CFrame * CFrame.new(0, 0.25, 0) end
local function localOf(c, pos) return floorCF(c):PointToObjectSpace(pos) end
local function riders(c)
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root and inside(c, root.Position, LP.RIDER_PAD) then table.insert(out, p) end
	end
	return out
end
-- the players standing across the door line (half in, half out): they keep the doors open
local function blockers(c)
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local l = localOf(c, root.Position)
			if LP.doorZone(l.X, l.Y, l.Z) == "line" then table.insert(out, p) end
		end
	end
	return out
end
-- put a character down standing at a point in the cab's frame (a server PivotTo also resets Movement)
local function standAt(c, char, x, z)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if not (hum and root) then return end
	local at = floorCF(c) * CFrame.new(x, hum.HipHeight + root.Size.Y / 2 + 0.1, z)
	char:PivotTo(CFrame.new(at.Position) * root.CFrame.Rotation)
end

local function doorsAt(c, id, open)
	if open then c.doorsOpen = id elseif c.doorsOpen == id then c.doorsOpen = nil end   -- what a rebuild re-applies (I1)
	local folder = c.model.Parent
	if not folder then return end
	local C = T.CAB
	for _, side in ipairs({ "L", "R" }) do
		for _, leaf in ipairs(folder:GetChildren()) do
			if leaf.Name == "LiftDoor" .. side and leaf:GetAttribute("Stop") == id then
				local home = leaf:GetAttribute("Home") or leaf.CFrame
				leaf:SetAttribute("Home", home)
				local shift = (side == "L" and -1 or 1) * (C.door / 2 - 0.2) * (open and 1 or 0)
				leaf.CanCollide = not open
				TweenService:Create(leaf, TweenInfo.new(LP.DOORS, Enum.EasingStyle.Quad), { CFrame = home * CFrame.new(shift, 0, 0) }):Play()
			end
		end
	end
end

-- every display (each landing's and the cab's): the fat number, then the arrow and the room
local function setDisplays(c, idx, arrowUp)
	local st = c.stops[idx]
	if not st then return end
	local w = api.Wafers.stateOf(c.plot)
	local num = (st.id == "L" and "L") or (st.id == "R" and "R") or tostring(st.storey)
	local room = LP.roomLabel(api.Wafers.Plan.PIECES, w.depts, w.level, st.storey)
	local arrow = arrowUp == nil and "" or (arrowUp and "UP  " or "DOWN  ")
	local function put(part)
		local sg = part and part:FindFirstChildWhichIsA("SurfaceGui")
		if not sg then return end
		if sg:FindFirstChild("Num") then sg.Num.Text = num end
		if sg:FindFirstChild("Label") then sg.Label.Text = arrow .. room end
	end
	local folder = c.model.Parent
	for _, d in ipairs(folder and folder:GetChildren() or {}) do
		if d.Name == "LiftDisplay" then put(d) end
	end
	put(c.model:FindFirstChild("CabHeader"))
end
local function sign(c, text)
	local s = c.model:FindFirstChild("Sign")
	local tl = s and s:FindFirstChildWhichIsA("SurfaceGui") and s:FindFirstChildWhichIsA("SurfaceGui"):FindFirstChild("Text")
	if tl then tl.Text = text end
end
local function label(c, idx)
	local st = c.stops[idx]
	if not st then return "" end
	local w = api.Wafers.stateOf(c.plot)
	local num = (st.id == "L" and "L") or (st.id == "R" and "R") or tostring(st.storey)
	return num .. "  " .. LP.roomLabel(api.Wafers.Plan.PIECES, w.depts, w.level, st.storey)
end
-- the pick lights above the doors inside: "did it take my tap?" (spec 2.4)
local function showNext(c, idx)
	local h = c.model:FindFirstChild("CabHeader")
	local sg = h and h:FindFirstChildWhichIsA("SurfaceGui")
	if sg and sg:FindFirstChild("Label") then sg.Label.Text = "TO  " .. label(c, idx) end
end
local function callLight(c, id, on)
	local folder = c.model.Parent
	for _, p in ipairs(folder and folder:GetChildren() or {}) do
		if p.Name == "LiftCallLit" and p:GetAttribute("Stop") == id then
			p.Color = on and Color3.fromRGB(255, 160, 40) or Color3.fromRGB(255, 194, 61)
			p.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
		end
	end
end

-- one ride or one door cycle, then loop while there is work
local function run(c)
	if c.busy then return end
	c.busy = true
	task.spawn(function()
		while c.model.Parent do
			local target = LP.target(c.plan)
			if not target then break end
			local here = c.stops[c.plan.at]
			if target == c.plan.at then
				LP.arrive(c.plan, target)
				callLight(c, here.id, false)
				if c.model:GetAttribute("State") ~= "open" then
					c.model:SetAttribute("State", "opening")
					doorsAt(c, here.id, true)
					task.wait(LP.DOORS)
					c.model:SetAttribute("State", "open")
				end
				task.wait(LP.DWELL)
				continue
			end
			-- leave: wait out the doorway (at most HOLD_MAX, then whoever blocks it is stood on the
			-- landing) and the capacity rule, then close
			c.holdSince = c.holdSince or os.clock()
			local n = #riders(c)
			local block = blockers(c)
			while c.model.Parent and (#block > 0 or n > LP.MAX_RIDERS) do
				if n > LP.MAX_RIDERS then
					c.model:SetAttribute("Event", "capacity")
					sign(c, LP.EVENT_TEXT.capacity)
				elseif LP.holdExpired(os.clock() - c.holdSince) then
					for _, p in ipairs(block) do
						if p.Character then standAt(c, p.Character, 0, T.CAB.d / 2 + 2.5) end
					end
				else
					sign(c, LP.EVENT_TEXT.doors)
				end
				task.wait(0.5)
				if not c.model.Parent then break end
				n, block = #riders(c), blockers(c)
			end
			if not c.model.Parent then break end
			c.model:SetAttribute("State", "closing")
			doorsAt(c, here.id, false)
			task.wait(LP.DOORS)
			if not c.model.Parent then break end
			if #blockers(c) > 0 then   -- someone stepped into the closing doors (M2): open again, wait again
				c.model:SetAttribute("State", "opening")
				doorsAt(c, here.id, true)
				task.wait(LP.DOORS)
				c.model:SetAttribute("State", "open")
				continue
			end
			c.holdSince = nil
			local who = riders(c)
			local dest = c.stops[target]
			local floors = math.abs(target - c.plan.at)
			local dur = LP.rideTime(floors)
			local ev = LP.rareEvent(c.plan.rides, c.plan.lastEvent, #who, rng:NextNumber())
			c.plan.lastEvent = ev ~= nil
			local text = (target > c.plan.at) and "GOING UP!" or "GOING DOWN!"
			if ev == "calm" then text = LP.EVENT_TEXT.calm
			elseif ev == "pride" then
				local s = who[1] and api.session and api.session(who[1])
				text = LP.EVENT_TEXT.pride:format(string.upper((s and s.name ~= "" and s.name) or "YOU"))
			end
			sign(c, text)
			for _, p in ipairs(who) do p:SetAttribute("LiftCab", c.plot.index) end
			local fromY = c.model.PrimaryPart.Position.Y + 0.25
			local toCF = api.Wafers.cabAt(c.plot, dest.storey)
			c.model:SetAttribute("Event", ev or "")
			c.model:SetAttribute("FromY", fromY)
			c.model:SetAttribute("ToY", toCF.Position.Y)
			c.model:SetAttribute("Floors", floors)
			c.model:SetAttribute("Dur", dur)
			c.model:SetAttribute("Start", workspace:GetServerTimeNow())
			c.model:SetAttribute("To", dest.id)
			c.model:SetAttribute("State", "moving")
			setDisplays(c, target, target > c.plan.at)
			task.wait(dur)
			if not c.model.Parent then break end
			c.model:PivotTo(toCF * CFrame.new(0, -0.25, 0))
			c.plan.rides += 1
			LP.arrive(c.plan, target)
			c.model:SetAttribute("At", dest.id)
			for _, p in ipairs(who) do if p.Parent then p:SetAttribute("LiftCab", nil) end end
			callLight(c, dest.id, false)
			setDisplays(c, target, nil)
			sign(c, label(c, target))
			c.model:SetAttribute("State", "opening")
			doorsAt(c, dest.id, true)
			task.wait(LP.DOORS)
			if not c.model.Parent then break end
			-- a rider whose client stalled over the arrival is still in the shaft: put them back (I3)
			for _, p in ipairs(who) do
				local root = p.Parent and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if root then
					local l = localOf(c, root.Position)
					if LP.reseat(l.X, l.Y, l.Z) then standAt(c, p.Character, 0, 0) end
				end
			end
			c.model:SetAttribute("State", "open")
			c.model:SetAttribute("Event", "")
			task.wait(LP.DWELL)
		end
		c.busy = false
	end)
end

function LiftCab.sync(plot)
	local W = api.Wafers
	if not W then return end
	local st = W.stateOf(plot)
	local stops = LP.stops(W.Plan.PIECES, st.level)
	local c = cabs[plot.index]
	if #stops == 0 then LiftCab.reset(plot) return end
	if not c or not (c.model and c.model.Parent) then
		c = { plot = plot, model = W.cab(plot), plan = LP.newCab(1), stops = stops, busy = false }
		cabs[plot.index] = c
	end
	c.stops = stops
	LP.prune(c.plan, #stops)
	W.refreshPanel(plot, function(player, id) LiftCab.pick(player, plot.index, id) end)
	-- a rebuild (every BUILD tap) made new door leaves: while the ride loop runs it owns the doors and
	-- the cab, so only re-apply what it had; an idle cab settles at its stop, doors open (I1)
	local here = stops[c.plan.at]
	local openAt, settle = LP.afterRebuild(c.busy, c.doorsOpen, here.id)
	if settle then
		c.model:PivotTo(W.cabAt(plot, here.storey) * CFrame.new(0, -0.25, 0))
		c.model:SetAttribute("At", here.id)
		c.model:SetAttribute("State", "open")
		setDisplays(c, c.plan.at, nil)
		sign(c, label(c, c.plan.at))
	end
	if openAt then doorsAt(c, openAt, true) end
	-- riders a clear + rebuild cut short just now go back in the cab; older entries are dropped (I2)
	for _, p in ipairs(LP.fresh(stranded[plot.index], os.clock(), LP.STRANDED_MAX)) do
		local char = p.Parent and p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then standAt(c, char, 0, 0) end
	end
	stranded[plot.index] = nil
	local list = {}
	for _, sk in ipairs(LP.sockets(W.Plan.PIECES, st.level)) do
		table.insert(list, { id = sk.id, num = sk.num, built = sk.built, label = sk.built and LP.roomLabel(W.Plan.PIECES, st.depts, st.level, sk.storey) or "",
			sub = T.DECKS[sk.storey - 1] and "TERRACE" or "" })
	end
	c.model:SetAttribute("Stops", HttpService:JSONEncode(list))
end

function LiftCab.reset(plot)
	cabs[plot.index] = nil
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("LiftCab") == plot.index then
			p:SetAttribute("LiftCab", nil)
			stranded[plot.index] = stranded[plot.index] or {}
			table.insert(stranded[plot.index], { player = p, t = os.clock() })
		end
	end
end

local function check(player)
	if player:GetAttribute("Carrying") then return false, "Drop off your recruit first" end
	if (lastCall[player] or 0) > os.clock() - 1.2 then return false, "busy" end
	if not Movement.check(player) then return false, "moving" end   -- standing at the lift, honestly
	return true
end

function LiftCab.call(player, plotIndex, stopId)
	local c = cabs[plotIndex]
	local idx = c and stopIndex(c, stopId)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (c and idx and root) then return false, "no lift" end
	local ok, why = check(player)
	if not ok then return false, why end
	local stand = api.Wafers.cabAt(c.plot, c.stops[idx].storey)
	if (stand.Position - root.Position).Magnitude > 16 then return false, "too far" end
	lastCall[player] = os.clock()
	LP.call(c.plan, idx)
	callLight(c, stopId, true)
	run(c)
	return true
end

function LiftCab.pick(player, plotIndex, stopId)
	local c = cabs[plotIndex]
	local idx = c and stopIndex(c, stopId)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (c and idx and root) then return false, "no lift" end
	if not inside(c, root.Position, 0.5) then return false, "not in the lift" end
	local ok, why = check(player)
	if not ok then return false, why end
	lastCall[player] = os.clock()
	LP.pick(c.plan, idx)
	if c.model:GetAttribute("State") ~= "moving" then showNext(c, LP.target(c.plan)) end
	run(c)
	return true
end

function LiftCab.init(a)
	api = a or {}
	local folder = RS:WaitForChild("SVRemotes")
	local ev = folder:FindFirstChild("LiftPick") or Instance.new("RemoteEvent")
	ev.Name = "LiftPick"
	ev.Parent = folder
	ev.OnServerEvent:Connect(function(player, plotIndex, stopId)
		if typeof(plotIndex) ~= "number" or typeof(stopId) ~= "string" then return end
		LiftCab.pick(player, plotIndex, stopId)
	end)
	Players.PlayerRemoving:Connect(function(p) lastCall[p] = nil end)
end
LiftCab.cabs = cabs   -- the doctor reads the live state

return LiftCab
