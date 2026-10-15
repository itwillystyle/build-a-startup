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
local function riders(c)
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root and inside(c, root.Position, 0) then table.insert(out, p) end
	end
	return out
end
-- someone standing across the door line (half in, half out) keeps the doors open
local function inDoorway(c)
	local C = T.CAB
	local cf = c.model.PrimaryPart.CFrame
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local l = cf:PointToObjectSpace(root.Position)
			if math.abs(l.X) <= C.door / 2 + 0.5 and l.Y > -1 and l.Y < C.doorH and math.abs(l.Z - C.d / 2) < 1.6 then return true end
		end
	end
	return false
end

local function doorsAt(c, id, open)
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

local function setDisplays(c, text, arrowUp)
	local arrow = arrowUp == nil and "" or (arrowUp and "^ " or "v ")
	local folder = c.model.Parent
	for _, d in ipairs(folder and folder:GetChildren() or {}) do
		if d.Name == "LiftDisplay" then
			local tl = d:FindFirstChildWhichIsA("SurfaceGui") and d:FindFirstChildWhichIsA("SurfaceGui"):FindFirstChild("Text")
			if tl then tl.Text = arrow .. text end
		end
	end
	local h = c.model:FindFirstChild("CabHeader")
	local tl = h and h:FindFirstChildWhichIsA("SurfaceGui") and h:FindFirstChildWhichIsA("SurfaceGui"):FindFirstChild("Text")
	if tl then tl.Text = arrow .. text end
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
			-- leave: wait out the doorway and the capacity rule, then close
			local n = #riders(c)
			while c.model.Parent and (inDoorway(c) or n > LP.MAX_RIDERS) do
				if n > LP.MAX_RIDERS then
					c.model:SetAttribute("Event", "capacity")
					sign(c, LP.EVENT_TEXT.capacity)
				end
				task.wait(0.5)
				n = #riders(c)
			end
			c.model:SetAttribute("State", "closing")
			doorsAt(c, here.id, false)
			task.wait(LP.DOORS)
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
			setDisplays(c, label(c, target), target > c.plan.at)
			task.wait(dur)
			if not c.model.Parent then break end
			c.model:PivotTo(toCF * CFrame.new(0, -0.25, 0))
			c.plan.rides += 1
			LP.arrive(c.plan, target)
			c.model:SetAttribute("At", dest.id)
			for _, p in ipairs(who) do if p.Parent then p:SetAttribute("LiftCab", nil) end end
			callLight(c, dest.id, false)
			setDisplays(c, label(c, target), nil)
			sign(c, label(c, target))
			c.model:SetAttribute("State", "opening")
			doorsAt(c, dest.id, true)
			task.wait(LP.DOORS)
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
	if c.model:GetAttribute("State") ~= "moving" then
		local here = stops[c.plan.at]
		c.model:PivotTo(W.cabAt(plot, here.storey) * CFrame.new(0, -0.25, 0))
		c.model:SetAttribute("At", here.id)
		doorsAt(c, here.id, true)
		c.model:SetAttribute("State", "open")
		setDisplays(c, label(c, c.plan.at), nil)
		sign(c, label(c, c.plan.at))
	end
	local here = stops[c.plan.at]
	for _, p in ipairs(stranded[plot.index] or {}) do
		local char = p.Parent and p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if hum and root and hum.Health > 0 then
			local stand = W.cabAt(plot, here.storey) * CFrame.new(0, hum.HipHeight + root.Size.Y / 2 + 0.1, 0)
			char:PivotTo(CFrame.new(stand.Position) * root.CFrame.Rotation)
		end
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
			table.insert(stranded[plot.index], p)
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
