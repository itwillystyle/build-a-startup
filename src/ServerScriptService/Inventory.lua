--[[
	Inventory -- ModuleScript in ServerScriptService (v3.2). The bag.

	Counts per item (Items.LIST), saved as plain integers and clamped on load.
	Boosts are session-only. The client reads three kinds of attribute:
	  Items        "coffee=2;energy=1"        what you hold
	  ItemsNew     n                          the red badge on BAG
	  BoostCode / BoostEnergy  server time   when a timed boost ends
	  ArmedScout / ArmedPress  bool          a one-shot boost waiting to fire

	SiliconCore asks this module, never the other way round:
	  codeMult(player)      x3 while a Cold Brew runs
	  launchMult(player)    x2 once, when a Front Page is armed
	  onHire(player, t)     a talent one higher, once, when a Scout Report is armed
	  scooterBonus(player)  +5 while an Energy Drink runs (TalentDrop)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage:WaitForChild("Items"))

local Inventory = {}
local api
local itemEvent

local function now() return workspace:GetServerTimeNow() end

local function publish(player, s)
	player:SetAttribute("Items", Items.encode(s.items))
end

function Inventory.count(s, id) return (s and s.items and s.items[id]) or 0 end

-- saved counts -> the session (unknown ids dropped, counts clamped)
function Inventory.load(player, s, saved)
	if not s then return end
	s.items = {}
	if type(saved) == "table" then
		for id, n in pairs(saved) do
			if Items.BY_ID[id] and type(n) == "number" then
				s.items[id] = math.clamp(math.floor(n), 0, Items.MAX)
			end
		end
	end
	publish(player, s)
end

function Inventory.save(s)
	local t = {}
	for id, n in pairs(s and s.items or {}) do if n > 0 then t[id] = n end end
	return t
end

-- add n of an item and tell the client where it came from (it draws the card)
function Inventory.grant(player, id, n, source)
	local s = api and api.session(player)
	local it = Items.BY_ID[id]
	if not s or not it then return false end
	s.items = s.items or {}
	n = n or 1
	s.items[id] = math.clamp((s.items[id] or 0) + n, 0, Items.MAX)
	publish(player, s)
	player:SetAttribute("ItemsNew", (player:GetAttribute("ItemsNew") or 0) + n)
	if itemEvent then itemEvent:FireClient(player, { kind = "got", id = id, n = n, source = source }) end
	return true
end

local function refuse(player, text)
	if itemEvent then itemEvent:FireClient(player, { kind = "refused", text = text }) end
	return false
end

function Inventory.use(player, id)
	local s = api and api.session(player)
	local it = Items.BY_ID[id]
	if not s or not it or type(id) ~= "string" then return false end
	if (s.items and s.items[id] or 0) < 1 then return refuse(player, "You don't have one") end
	if s.lastUse and os.clock() - s.lastUse < 0.4 then return false end
	s.lastUse = os.clock()
	s.lastTap = s.lastUse       -- using an item counts as playing (AFK)

	if id == "coffee" then
		-- stacks by extending the clock, up to three at once
		local t = math.max(now(), player:GetAttribute("BoostCode") or 0)
		if t - now() > 120 then return refuse(player, "Your team can't drink more coffee right now") end
		player:SetAttribute("BoostCode", t + it.duration)
	elseif id == "energy" then
		local t = math.max(now(), player:GetAttribute("BoostEnergy") or 0)
		if t - now() > 90 then return refuse(player, "One can at a time") end
		player:SetAttribute("BoostEnergy", t + it.duration)
		if api.refreshSpeed then pcall(api.refreshSpeed, player) end
		task.delay(t + it.duration - now() + 0.1, function()
			if player.Parent and api.refreshSpeed then pcall(api.refreshSpeed, player) end
		end)
	elseif id == "noncompete" then
		if not (api.dismissHunter and api.dismissHunter(player)) then
			return refuse(player, "Use it while a headhunter is chasing you")
		end
	elseif id == "scout" then
		if player:GetAttribute("ArmedScout") then return refuse(player, "A Scout Report is already waiting for your next hire") end
		player:SetAttribute("ArmedScout", true)
	elseif id == "frontpage" then
		if player:GetAttribute("ArmedPress") then return refuse(player, "A Front Page is already waiting for your next launch") end
		player:SetAttribute("ArmedPress", true)
	end
	s.items[id] -= 1
	publish(player, s)
	if itemEvent then itemEvent:FireClient(player, { kind = "used", id = id }) end
	return true
end

-- ============ WHAT THE GAME ASKS ============

function Inventory.codeMult(player)
	return ((player:GetAttribute("BoostCode") or 0) > now()) and 3 or 1
end

function Inventory.scooterBonus(player)
	return ((player:GetAttribute("BoostEnergy") or 0) > now()) and 5 or 0
end

function Inventory.launchMult(player)
	if player:GetAttribute("ArmedPress") then
		player:SetAttribute("ArmedPress", nil)
		if itemEvent then itemEvent:FireClient(player, { kind = "fired", id = "frontpage" }) end
		return 2
	end
	return 1
end

function Inventory.onHire(player, talent)
	if player:GetAttribute("ArmedScout") then
		player:SetAttribute("ArmedScout", nil)
		if itemEvent then itemEvent:FireClient(player, { kind = "fired", id = "scout" }) end
		return math.clamp(math.max((talent or 1) + 1, 2), 1, 5)
	end
	return talent
end

-- a launch sometimes brings a coffee; the FIRST launch always does (it
-- teaches the bag with something you can use right away)
function Inventory.onLaunch(player, s)
	if not s then return end
	if not s.gotFirstCoffee and (s.launches or 0) <= 1 and Inventory.count(s, "coffee") == 0 then
		s.gotFirstCoffee = true
		Inventory.grant(player, "coffee", 1, "Launch day: your team made cold brew")
	elseif math.random() < 0.12 then
		Inventory.grant(player, "coffee", 1, "Launch party leftovers")
	end
end

function Inventory.init(a)
	api = a
	local folder = ReplicatedStorage:WaitForChild("SVRemotes")
	itemEvent = folder:FindFirstChild("ItemEvent") or Instance.new("RemoteEvent")
	itemEvent.Name = "ItemEvent"
	itemEvent.Parent = folder
	local useItem = folder:FindFirstChild("UseItem") or Instance.new("RemoteEvent")
	useItem.Name = "UseItem"
	useItem.Parent = folder
	useItem.OnServerEvent:Connect(function(player, id) Inventory.use(player, id) end)
	local seen = folder:FindFirstChild("ItemsSeen") or Instance.new("RemoteEvent")
	seen.Name = "ItemsSeen"
	seen.Parent = folder
	seen.OnServerEvent:Connect(function(player) player:SetAttribute("ItemsNew", 0) end)
end

return Inventory
