--[[
	TalentDrop (v3.0) -- ModuleScript in ServerScriptService. "Talent Row".

	PLAN-v5-tizzy, Phase B: hiring becomes "leave base, get thing".

	Each founder has their own candidates standing on THEIR side's sidewalk of
	the main road, further east the rarer they are (the road's real geometry:
	plots at x -360/0/360, road z = 0, sidewalks z = +-21). A candidate wears
	the colour of the talent they are guaranteed (the existing TALENT colours:
	walk-in / Skilled green / Star blue / Genius purple); their exact talent
	rolls at YOUR door (post-acquisition, the existing TalentReveal).

	Recruit (hold E) -> you carry them home over your head -> cross into your
	lot -> the signing fee is paid there and they join through hire(), the one
	code path every hire already uses. A loss costs time, never money.

	TENSION: an offer timer (they take another offer), a HEADHUNTER from a
	rival company who chases you for Skilled+ candidates (PvE, so it works in a
	1-player server), and other founders can poach what you carry (PvP).

	Simulated first (sim/recruit_sim.py): HQ 2/3/4/5 at 4.1/7.1/10.9/19.5 min
	at 20 s per purchase vs 3.8/7.1/11.4/20.4 today; robust to slow walkers.

	NETWORK (v2.8.1 rule): candidates stand still (anchored, zero traffic);
	a carried candidate is welded to the carrier, so it rides the character's
	own physics replication; motion/flailing is drawn by StaffAnimClient.
	Only a headhunter moves on the server (one anchored root, 20 Hz).
]]

local CollectionService = game:GetService("CollectionService")

local TalentDrop = {}

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Econ = require(ServerScriptService:WaitForChild("RoomEconomy"))
local StaffRig = require(ServerScriptService:WaitForChild("StaffRig"))
local Chase = require(ServerScriptService:WaitForChild("ChaseRules"))   -- v4.3 the chase (pure, simulated offline)

local api                        -- set by init: see SiliconCore's wiring section
local state = {}                 -- plot.index -> { owner, tiers = { [i] = { model, readyAt } } }
local carries = {}               -- player -> carry
local folder
local chaseFx                    -- v4.3 RemoteEvent: CLOSE CALL moments to the carrier

local ROLES = { "engineer", "engineer", "designer", "sales", "research", "recruiter" }
local LOT_X, LOT_Z1, LOT_Z2 = 110, -105, 65         -- CampusSlab: 220 x 170 centred at local z -20

local Pal = (function()
	local ok, m = pcall(require, game:GetService("ReplicatedStorage"):WaitForChild("Palette", 5))
	return ok and m or nil
end)()

local function now() return workspace:GetServerTimeNow() end

local function toast(player, text)
	local r = ReplicatedStorage:FindFirstChild("SVRemotes")
	r = r and r:FindFirstChild("Toast")
	if r and player and player.Parent then r:FireClient(player, text) end
end

local function tierColor(tier)
	local t = api.TALENT[tier.floor]
	return (t and t.color) or Color3.fromRGB(236, 236, 232)
end

local function groundY(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder }
	local hit = workspace:Raycast(Vector3.new(x, 60, z), Vector3.new(0, -120, 0), params)
	return hit and hit.Position.Y or 0.8
end

local function inLot(plot, pos)
	local p = plot.pivot:PointToObjectSpace(pos)
	return math.abs(p.X) <= LOT_X and p.Z >= LOT_Z1 and p.Z <= LOT_Z2
end

--[[ WHERE A CANDIDATE STANDS (fixed 4 Oct).

	This was written for the old campus -- "plots at x -360/0/360, road z = 0,
	sidewalks z = +-21" -- and never moved when the six plots went onto a ring.
	It put every founder's candidates on the downtown approach road at z 21,
	which for the plot at (291, 168) is 147 studs off its own site and roughly
	600 studs from its door. All six plots' candidates landed in one line on
	the same road. The quest reading "far end of the street" was pointing at a
	street that is not yours.

	They stand on the pavement of the player's OWN drive now, `east` studs
	further out from their building, so rarer still means a longer walk back.
	Capped at 236: the drive runs 388 studs from the inner ring to the outer
	one, and past 236 you are standing in the outer ring road. ]]
local DRIVE_WALK = 72.6        -- CampusHub: ARM_X 88, kerb face 77.6, pavement centred here

local DOOR_Z, DRIVE_MAX = 70, 300     -- the walk is measured from the door, and
                                      -- 300 out lands 8 studs short of the outer ring road

local function spotFor(plot, tier)
	-- the old straight road ran 440 studs out. This drive gives 300 from the
	-- door before the outer ring road, so the four tiers are mapped onto it in
	-- proportion: clamping instead put STAR and GENIUS on the same paving slab.
	local out = 20 + (tier.east - 20) * (DRIVE_MAX - 20) / (440 - 20)
	local cf = plot.pivot * CFrame.new(-DRIVE_WALK, 0, DOOR_Z - out)
	-- turned to face the carriageway, whichever way the plot itself faces
	local dir = (plot.pivot * CFrame.Angles(0, math.pi / 2, 0)).LookVector
	return cf.Position.X, cf.Position.Z, math.atan2(-dir.X, -dir.Z)
end

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	-- author in the palette: an unnamed Color used to inherit Roblox default grey
	if Pal then
		p.Color = props.Color and Pal.map(props.Color) or Pal.map(Color3.fromRGB(163, 162, 165))
	end
	p.Parent = parent
	return p
end

local function label(adornee, top, bottom, color, dist)
	local bb = Instance.new("BillboardGui")
	bb.Name = "CandidateTag"
	bb.Size = UDim2.new(0, 160, 0, 40)      -- v3.2.1: 200x50 filled a fifth of a phone screen
	bb.StudsOffset = Vector3.new(0, 3.6, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = dist or 140
	bb.Adornee = adornee
	local a = Instance.new("TextLabel")
	a.Name = "Top"
	a.BackgroundTransparency = 1
	a.Size = UDim2.new(1, 0, 0.56, 0)
	a.Font = Enum.Font.FredokaOne
	a.TextScaled = true
	a.TextColor3 = color
	a.TextStrokeTransparency = 0.2
	a.Text = top
	a.Parent = bb
	local b = Instance.new("TextLabel")
	b.Name = "Bottom"
	b.BackgroundTransparency = 1
	b.Position = UDim2.new(0, 0, 0.56, 0)
	b.Size = UDim2.new(1, 0, 0.44, 0)
	b.Font = Enum.Font.FredokaOne
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextStrokeTransparency = 0.3
	b.Text = bottom
	b.Parent = bb
	bb.Parent = adornee
	return bb
end

-- ============ CANDIDATES ============

local function feeFor(player, tier)
	local ladder = api.ladder(player)
	local scale = api.priceScale and api.priceScale(player) or 1   -- v4.5 the clock
	return ladder and math.max(math.floor(ladder * tier.fee), math.floor((tier.minFee or 0) * scale)) or nil
end

local function refreshTag(plot, entry, tier)
	local owner = plot.owner and Players:GetPlayerByUserId(plot.owner)
	local m = entry.model
	if not (owner and m and m.Parent) then return end
	local fee = feeFor(owner, tier) or 0
	local tag = m:FindFirstChild("CandidateTag", true)
	if tag then tag.Bottom.Text = ("%s  ·  $%s"):format(m:GetAttribute("RoleName") or "", api.fmt(fee)) end
	if entry.prompt then
		entry.prompt.ObjectText = ("%s  ·  pay $%s at your door"):format(tier.name, api.fmt(fee))
	end
end

local recruit   -- forward-declared: the prompt handler calls it

local function spawnCandidate(plot, i)
	local tier = Econ.TIERS[i]
	local st = state[plot.index]
	local x, z, face = spotFor(plot, tier)
	local y = groundY(x, z)
	local role = ROLES[math.random(1, #ROLES)]
	local seed = plot.index * 1000 + i * 97 + math.random(1, 9999)
	local rig, hum = StaffRig.build(role, seed)
	rig.Name = "Candidate_" .. tier.id
	rig:SetAttribute("RoleKey", role)
	rig:SetAttribute("Seed", seed)
	rig:PivotTo(CFrame.new(x, y + 2.62, z) * CFrame.Angles(0, face, 0))   -- root to sole is 2.61: feet ON the pavement
	rig:SetAttribute("Candidate", true)
	rig:SetAttribute("Tier", tier.id)
	rig:SetAttribute("Owner", plot.owner)
	rig:SetAttribute("Wander", Vector3.new(1.2, 0, 1.2))
	rig:SetAttribute("RoleName", (StaffRig.ROLES[role] and StaffRig.ROLES[role].name) or role:upper())
	local color = tierColor(tier)
	rig:SetAttribute("TierColor", color)
	rig:SetAttribute("TierName", tier.name)
	-- tier ring under the feet + a light pillar for the rare ones (seen from the lot)
	part({ Name = "TierRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 6, 6),
		CFrame = CFrame.new(x, y + 0.15, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color, Material = Enum.Material.Neon }, rig)
	if tier.pillar and tier.pillar > 0 then
		part({ Name = "TierPillar", Size = Vector3.new(0.45, tier.pillar, 0.45),
			CFrame = CFrame.new(x, y + 5 + tier.pillar / 2, z), Color = color, Material = Enum.Material.Neon }, rig)
	end
	local head = rig:FindFirstChild("Head")
	local old = head and head:FindFirstChild("Tag")
	if old then old.Enabled = false end             -- the staff name tag gives way to the candidate tag
	label(head or rig.PrimaryPart, tier.name, "", color, 140)
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "RecruitPrompt"
	pp.ActionText = "Recruit"
	pp.HoldDuration = 0.35
	pp.MaxActivationDistance = 10
	pp.RequiresLineOfSight = false
	pp.Parent = rig:FindFirstChild("UpperTorso") or rig.PrimaryPart
	rig.Parent = st.folder
	local entry = { model = rig, prompt = pp, readyAt = 0 }
	st.tiers[i] = entry
	pp.Triggered:Connect(function(player) recruit(player, plot, i) end)
	refreshTag(plot, entry, tier)
end

local function clearPlot(idx)
	local st = state[idx]
	if not st then return end
	for _, e in pairs(st.tiers) do if e.model then e.model:Destroy() end end
	st.tiers = {}
end

-- ============ THE SCOOTER (v3.0.2) ============
-- You ride one while carrying: faster with each HQ level (Econ.CARRY_SPEED),
-- coloured by that level, so the speed you have earned is something everyone
-- on the street can see. Welded to your root: it rides your own physics
-- replication, so it costs no network after it is built.

local SCOOTER_COLOR = {
	Color3.fromRGB(70, 76, 90), Color3.fromRGB(90, 170, 255), Color3.fromRGB(90, 210, 130),
	Color3.fromRGB(190, 120, 255), Color3.fromRGB(255, 208, 70),
}
local LIFT = 0.55               -- the deck lifts you this far off the ground
local PASSENGER_Z = 1.75        -- the hire stands this far behind you on the deck

local function scooterOff(player, c)
	if c.scooter then c.scooter:Destroy(); c.scooter = nil end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum and c.prevWalk then
		pcall(function()
			hum.WalkSpeed = c.prevWalk
			hum.HipHeight = c.prevHip
		end)
	end
	c.prevWalk, c.prevHip = nil, nil
	player:SetAttribute("CarrySpeed", nil)
end

local function scooterOn(player, c)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local plot = api.plotOf(player)
	if not (hum and hrp and plot) then return end
	local lv = math.clamp(plot.hq and plot.hq.level or 1, 1, #Econ.CARRY_SPEED)
	c.prevWalk, c.prevHip = hum.WalkSpeed, hum.HipHeight
	c.baseSpeed = Econ.CARRY_SPEED[lv]
	c.speed = c.baseSpeed + ((Econ.Inv and Econ.Inv.scooterBonus(player)) or 0)   -- v3.2: an Energy Drink
	local feet = -(hrp.Size.Y / 2 + c.prevHip)          -- your soles, relative to the root, before the lift
	local m = Instance.new("Model")
	m.Name = "Scooter"
	local color = SCOOTER_COLOR[lv]
	local function piece(props, offset)
		local p = part(props, m)
		p.Anchored = false
		p.Massless = true
		p.CFrame = hrp.CFrame * offset
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = hrp, p
		w.Parent = p
		return p
	end
	--[[ v3.0.3 THE SCOOTER, rebuilt (his note: it "sucks" -- it was a plank
	with a pole). A two-person e-scooter: long charcoal deck with grip tape
	and HQ-colour side rails, a glowing underline in the same colour, two
	wheels with hubs, a fork, a raked stem up to a T-bar with grips at hand
	height, a headlight, and a rear fender over the passenger's wheel. ]]
	local CHAR = Color3.fromRGB(34, 36, 42)
	local ALLOY = Color3.fromRGB(196, 200, 208)
	local deckY = feet - 0.12
	local L, Z0 = 4.5, 0.85                     -- deck length, centre: from just ahead of your toes to behind the passenger
	local zF, zR = Z0 - L / 2 - 0.25, Z0 + L / 2 + 0.05
	piece({ Name = "Deck", Size = Vector3.new(1.05, 0.2, L), Color = CHAR, Material = Enum.Material.SmoothPlastic }, CFrame.new(0, deckY, Z0))
	piece({ Name = "Grip", Size = Vector3.new(0.86, 0.03, L - 0.4), Color = Color3.fromRGB(22, 23, 27), Material = Enum.Material.Sand }, CFrame.new(0, deckY + 0.11, Z0))
	for _, sx in ipairs({ -1, 1 }) do
		piece({ Name = "Rail", Size = Vector3.new(0.08, 0.22, L - 0.2), Color = color, Material = Enum.Material.SmoothPlastic }, CFrame.new(sx * 0.53, deckY + 0.01, Z0))
	end
	piece({ Name = "Underglow", Size = Vector3.new(0.7, 0.04, L - 0.8), Color = color, Material = Enum.Material.Neon }, CFrame.new(0, deckY - 0.12, Z0))
	for _, z in ipairs({ zF, zR }) do
		piece({ Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.28, 0.76, 0.76),
			Color = CHAR, Material = Enum.Material.SmoothPlastic }, CFrame.new(0, feet - LIFT + 0.38, z))
		piece({ Name = "Hub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.32, 0.34, 0.34),
			Color = ALLOY, Material = Enum.Material.Metal }, CFrame.new(0, feet - LIFT + 0.38, z))
	end
	-- fork from the front axle up to the deck nose, then the raked stem
	piece({ Name = "Fork", Size = Vector3.new(0.5, 0.9, 0.14), Color = ALLOY, Material = Enum.Material.Metal },
		CFrame.new(0, feet - LIFT + 0.8, zF))
	local stemBase = Vector3.new(0, deckY + 0.1, zF + 0.05)
	-- the bar at hand height, raked back toward you so your arms reach it (first draft: 2.4 studs ahead, at head height)
	local stemTop = Vector3.new(0, deckY + 3.15, zF + 0.3)
	local mid = (stemBase + stemTop) / 2
	piece({ Name = "Stem", Size = Vector3.new(0.2, (stemTop - stemBase).Magnitude, 0.2), Color = color, Material = Enum.Material.SmoothPlastic },
		CFrame.lookAt(mid, mid + (stemTop - stemBase)) * CFrame.Angles(math.rad(-90), 0, 0))
	piece({ Name = "Bars", Size = Vector3.new(1.7, 0.16, 0.16), Color = ALLOY, Material = Enum.Material.Metal }, CFrame.new(stemTop))
	for _, sx in ipairs({ -1, 1 }) do
		piece({ Name = "GripBar", Size = Vector3.new(0.42, 0.22, 0.22), Color = CHAR, Material = Enum.Material.SmoothPlastic },
			CFrame.new(stemTop + Vector3.new(sx * 0.66, 0, 0)))
	end
	piece({ Name = "Headlight", Size = Vector3.new(0.34, 0.2, 0.08), Color = Color3.fromRGB(255, 250, 230), Material = Enum.Material.Neon },
		CFrame.new(stemTop + Vector3.new(0, -0.5, -0.16)))
	piece({ Name = "Fender", Size = Vector3.new(0.4, 0.08, 0.9), Color = CHAR, Material = Enum.Material.SmoothPlastic },
		CFrame.new(0, feet - LIFT + 0.86, zR + 0.15))
	m.Parent = char
	c.scooter = m
	pcall(function()
		hum.HipHeight = c.prevHip + LIFT
		hum.WalkSpeed = c.speed
	end)
	player:SetAttribute("CarrySpeed", c.speed)
end

-- ============ CARRY ============

-- v3.1: a lost hire is a moment (red flash + sound on the client), not a toast
local function lostSting(player, text)
	local r = ReplicatedStorage:FindFirstChild("SVRemotes")
	r = r and r:FindFirstChild("CarryLost")
	if r and player and player.Parent then r:FireClient(player, text) end
end

local function endCarry(player, reason, lost)
	local c = carries[player]
	if not c then return end
	carries[player] = nil
	scooterOff(player, c)
	if c.hunter then c.hunter:Destroy() end
	for _, H in ipairs(c.hunters or {}) do if H.rig and H.rig.Parent then H.rig:Destroy() end end
	player:SetAttribute("ChaseDist", nil)
	if c.model and c.model.Parent then c.model:Destroy() end
	player:SetAttribute("Carrying", nil)
	player:SetAttribute("CarryName", nil)
	player:SetAttribute("CarryDeadline", nil)
	-- the origin tier restocks only now (a slot stays empty while its candidate
	-- is in transit; re-arming it at recruit time spawned duplicates -- caught live)
	if c.entry then
		c.entry.readyAt = now() + (c.tier.restock or 0)
		local owner = c.originPlot and c.originPlot.owner and Players:GetPlayerByUserId(c.originPlot.owner)
		if owner and (c.tier.restock or 0) > 2 then owner:SetAttribute("Restock_" .. c.tier.id, c.entry.readyAt) end
	end
	if reason and reason ~= "" then
		if lost then lostSting(player, reason) else toast(player, reason) end
	end
end

local function attach(player, c)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local m = c.model
	if not (hrp and m and m.PrimaryPart) then return false end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = false; d.Massless = true; d.CanCollide = false end
		if d:IsA("WeldConstraint") and d.Name == "CarryWeld" then d:Destroy() end
	end
	for _, n in ipairs({ "TierRing", "TierPillar" }) do local p = m:FindFirstChild(n); if p then p:Destroy() end end
	-- v3.0.3: they ride home standing on the back of your scooter, hands on your
	-- shoulders (was: lying overhead like luggage -- his note: the carry "sucks").
	-- Their soles go on the deck, which is level with your soles.
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local soles = -(hrp.Size.Y / 2 + (hum and hum.HipHeight or 2))
	m:PivotTo(hrp.CFrame * CFrame.new(0, soles + 2.61 + 0.1, PASSENGER_Z))
	local w = Instance.new("WeldConstraint")
	w.Name = "CarryWeld"
	w.Part0 = hrp
	w.Part1 = m.PrimaryPart
	w.Parent = m.PrimaryPart
	m:SetAttribute("Candidate", nil)
	m:SetAttribute("Carried", true)
	m:SetAttribute("CarriedBy", player.UserId)
	return true
end

local function spawnHunter(player, c, fromPos, second)
	local rival = api.RIVALS[math.random(1, #api.RIVALS)]
	local rig = StaffRig.build("sales", math.random(1, 99999))
	rig.Name = "Headhunter"
	-- the dark suit: tints the shirt and trousers on an avatar, the torso on a block rig
	if StaffRig.setOutfit then
		StaffRig.setOutfit(rig, Color3.fromRGB(40, 42, 50), Color3.fromRGB(30, 32, 38))
	else
		for _, d in ipairs(rig:GetDescendants()) do
			if d:IsA("BasePart") and (d.Name == "UpperTorso" or d.Name == "LowerTorso") then d.Color = Color3.fromRGB(34, 36, 42) end
		end
	end
	local head = rig:FindFirstChild("Head")
	local old = head and head:FindFirstChild("Tag")
	if old then old.Enabled = false end
	label(head, second and ((c.hunterRival or rival):upper()) or rival:upper(), second and "JUNIOR HEADHUNTER" or "HEADHUNTER",
		Color3.fromRGB(240, 80, 80), 160)
	rig:SetAttribute("Chaser", true)
	rig:SetAttribute("ChasingUserId", player.UserId)
	local y = fromPos.Y
	rig:PivotTo(CFrame.new(fromPos))
	rig.Parent = folder
	-- v4.3: ChaseRules owns the movement (tension band, lunges, lead pursuit)
	c.hunters = c.hunters or {}
	table.insert(c.hunters, { rig = rig, h = Chase.newHunter(fromPos.X, fromPos.Z, os.clock(), second and 1.6 or 0, second) })
	if not second then
		c.hunter = rig
		c.hunterRival = rival
	end
	c.hunterY = c.hunterY or y
	c.chaseCfg = c.chaseCfg or Chase.config(c.tier.id, c.vip, c.speed)
	c.chaseT0 = c.chaseT0 or os.clock()
end

-- v4.2: the carry itself (scooter, offer timer, poach prompt, headhunter), shared
-- by the street candidates and the daily VIP so both runs play the same
local function startCarry(player, plot, c)
	if not attach(player, c) then c.model:Destroy() return end
	carries[player] = c
	scooterOn(player, c)
	-- the offer timer: enough to walk home steadily with room to spare
	local home = plot.pivot.Position
	local dist = (Vector3.new(home.X, 0, home.Z) - Vector3.new(c.from.X, 0, c.from.Z)).Magnitude
	c.deadline = now() + Econ.OFFER_BASE + dist * Econ.OFFER_PER_STUD
	player:SetAttribute("Carrying", c.tier.id)
	player:SetAttribute("CarryName", c.name)
	player:SetAttribute("CarryDeadline", c.deadline)
	-- poachable by other founders while in transit
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "PoachPrompt"
	pp.ActionText = "Poach"
	pp.ObjectText = c.tier.name
	pp.HoldDuration = 0.6
	pp.MaxActivationDistance = 9
	pp.RequiresLineOfSight = false
	pp.Parent = c.model:FindFirstChild("UpperTorso") or c.model.PrimaryPart
	pp.Triggered:Connect(function(thief) TalentDrop.poach(thief, player) end)
	-- v3.1 say it once: the quest card says "Bring X home! 44 seconds left" and
	-- the top-centre chip says how close the headhunter is; the toast that also
	-- said both is gone (the rival's name still lands in the LOST moment)
	if c.tier.chase then
		spawnHunter(player, c, Vector3.new(c.from.X + Chase.START_BEHIND, c.from.Y, c.from.Z))
	end
	if api.onRecruit then api.onRecruit(player) end
end

recruit = function(player, plot, i)
	local tier = Econ.TIERS[i]
	local st = state[plot.index]
	local entry = st and st.tiers[i]
	if not (entry and entry.model and entry.model.Parent) then return end
	if plot.owner ~= player.UserId then return end                    -- your candidates, not someone else's
	if (plot.hq and plot.hq.level or 1) < (tier.hq or 1) then       -- v4.5: the HQ gate, on the server
		api.popup(entry.model.PrimaryPart, ("Unlocks at HQ %d"):format(tier.hq), api.BAD)
		return
	end
	if carries[player] then api.popup(entry.model.PrimaryPart, "Take one home first", api.BAD) return end
	local s = api.session(player)
	if not s or not s.shipped or (s.staff or 0) < 1 then return end
	if (s.staff or 0) >= api.capacity(player) then
		api.popup(entry.model.PrimaryPart, "No free seat  ·  build or upgrade a room", api.BAD)
		return
	end
	local fee = feeFor(player, tier)
	local cash = api.cash(player)
	if not fee or not cash or cash.Value < fee then
		api.popup(entry.model.PrimaryPart, "Need $" .. api.fmt(fee or 0), api.BAD)
		return
	end
	local c = { model = entry.model, tier = tier, tierIndex = i, originPlot = plot, fee = fee, entry = entry,
		name = entry.model:GetAttribute("PersonName") or "them", from = entry.model:GetPivot().Position }
	entry.model = nil
	entry.readyAt = math.huge         -- empty until this carry ends (endCarry sets the restock)
	if entry.prompt then entry.prompt:Destroy(); entry.prompt = nil end
	local tag = c.model:FindFirstChild("CandidateTag", true)
	if tag then tag:Destroy() end
	startCarry(player, plot, c)
end

function TalentDrop.poach(thief, victim)
	local c = carries[victim]
	if not c or thief == victim or carries[thief] then return end
	local tplot = api.plotOf(thief)
	local s = api.session(thief)
	if not tplot or not s or (s.staff or 0) < 1 or (s.staff or 0) >= api.capacity(thief) then return end
	local a = thief.Character and thief.Character:FindFirstChild("HumanoidRootPart")
	local b = victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
	if not (a and b) or (a.Position - b.Position).Magnitude > 12 then return end
	carries[victim] = nil
	scooterOff(victim, c)
	victim:SetAttribute("Carrying", nil); victim:SetAttribute("CarryName", nil); victim:SetAttribute("CarryDeadline", nil)
	if not attach(thief, c) then c.model:Destroy() return end
	c.fee = feeFor(thief, c.tier) or c.fee
	local home = tplot.pivot.Position
	c.deadline = now() + Econ.OFFER_BASE + (Vector3.new(home.X, 0, home.Z) - Vector3.new(b.Position.X, 0, b.Position.Z)).Magnitude * Econ.OFFER_PER_STUD
	carries[thief] = c
	scooterOn(thief, c)
	thief:SetAttribute("Carrying", c.tier.id); thief:SetAttribute("CarryName", c.name); thief:SetAttribute("CarryDeadline", c.deadline)
	for _, H in ipairs(c.hunters or {}) do if H.rig then H.rig:SetAttribute("ChasingUserId", thief.UserId) end end
	toast(victim, ("%s poached %s from you!"):format(thief.DisplayName, c.name))
	toast(thief, ("You poached %s! Get them home."):format(c.name))
end

-- ============ THE LOOP ============

local function stepCarry(player, c, dt)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 or not c.model.Parent then
		endCarry(player, c.name .. " walked off", true)
		return
	end
	local plot = api.plotOf(player)
	if plot and inLot(plot, hrp.Position) then
		-- `kind` is what the trip was worth: it is set only here, on a carry that
		-- actually reached the lot, so no hire made from inside the garage pays
		local ok = api.hire(player, plot, { floor = c.tier.floor, fee = c.fee, luck = c.luck,
			kind = c.vip and "vip" or c.tier.id,
			role = c.model:GetAttribute("RoleKey"), seed = c.model:GetAttribute("Seed") })
		endCarry(player, ok and "" or ("Couldn't sign " .. c.name .. " (need $" .. api.fmt(c.fee) .. " and a free seat)"))
		return
	end
	if now() > c.deadline then
		endCarry(player, c.name .. " took another offer", true)
		return
	end
	-- v4.3 THE CHASE: ChaseRules (a tension band, telegraphed lunges, lead pursuit;
	-- measured in tools/chase_sim). The VIP's second, junior hunter joins from
	-- across the road after SECOND_DELAY.
	if c.hunters and #c.hunters > 0 then
		local t = os.clock()
		if c.vip and not c.secondSpawned and (c.chaseCfg.hunters or 1) >= 2 and t - (c.chaseT0 or t) >= Chase.SECOND_DELAY then
			c.secondSpawned = true
			local side = (hrp.Position.Z >= 0) and -1 or 1
			spawnHunter(player, c, Vector3.new(hrp.Position.X, c.hunterY, hrp.Position.Z + side * Chase.SECOND_SIDE), true)
		end
		local minD = math.huge
		for i = #c.hunters, 1, -1 do
			local H = c.hunters[i]
			local rig = H.rig
			if not rig.Parent or not rig.PrimaryPart then
				table.remove(c.hunters, i)
			else
				local target = Players:GetPlayerByUserId(rig:GetAttribute("ChasingUserId") or 0) or player
				local thrp = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
				if thrp then
					local tv = thrp.AssemblyLinearVelocity
					local ph, dist = Chase.step(c.chaseCfg, H.h, thrp.Position.X, thrp.Position.Z, tv.X, tv.Z, c.speed or 16, dt, t)
					if dist <= Chase.CATCH then
						endCarry(player, ("%s's headhunter got %s!"):format(c.hunterRival or "A rival", c.name), true)
						return
					end
					minD = math.min(minD, dist)
					-- TalentRowClient / StaffAnimClient / ChaseFxClient draw the tell and the lunge off these
					local wind, lung = ph == "windup", ph == "lunge"
					if (rig:GetAttribute("Windup") == true) ~= wind then rig:SetAttribute("Windup", wind) end
					if (rig:GetAttribute("Lunging") == true) ~= lung then rig:SetAttribute("Lunging", lung) end
					local np = Vector3.new(H.h.x, c.hunterY, H.h.z)
					local look = Vector3.new(thrp.Position.X - np.X, 0, thrp.Position.Z - np.Z)
					rig:PivotTo(look.Magnitude > 0.01 and CFrame.lookAt(np, np + look) or CFrame.new(np))
				end
			end
		end
		-- the fear readout (heartbeat, red edges) and CLOSE CALLs
		local cd = minD < math.huge and math.floor(minD * 2 + 0.5) / 2 or nil
		if player:GetAttribute("ChaseDist") ~= cd then player:SetAttribute("ChaseDist", cd) end
		if minD < Chase.NEAR then
			c.near = true
		elseif c.near and minD > Chase.NEAR * 1.8 then
			c.near = false
			if chaseFx then chaseFx:FireClient(player, { kind = "close" }) end
		end
	end
end

function TalentDrop.init(a)
	do
		local folder = ReplicatedStorage:FindFirstChild("SVRemotes")
		if folder and not folder:FindFirstChild("CarryLost") then
			local ev = Instance.new("RemoteEvent")
			ev.Name = "CarryLost"
			ev.Parent = folder
		end
	end
	do
		-- v4.3: BOOST (client -> server) and the chase moments (server -> client)
		local rf = ReplicatedStorage:FindFirstChild("SVRemotes")
		if rf then
			chaseFx = rf:FindFirstChild("ChaseFx") or Instance.new("RemoteEvent")
			chaseFx.Name = "ChaseFx"
			chaseFx.Parent = rf
			local boost = rf:FindFirstChild("CarryBoost") or Instance.new("RemoteEvent")
			boost.Name = "CarryBoost"
			boost.Parent = rf
			boost.OnServerEvent:Connect(function(player)
				local c = carries[player]
				if not c then return end
				local t = os.clock()
				if not Chase.boostReady(c.lastBoost, t) then return end
				c.lastBoost = t
				player:SetAttribute("BoostAt", workspace:GetServerTimeNow())
				local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if hum then hum.WalkSpeed = (c.speed or 16) + Chase.BOOST.add end
				task.delay(Chase.BOOST.time, function()
					if carries[player] == c and hum and hum.Parent then hum.WalkSpeed = c.speed or hum.WalkSpeed end
				end)
			end)
		end
	end
	api = a
	folder = Instance.new("Folder")
	folder.Name = "TalentRow"
	folder.Parent = workspace:FindFirstChild("SiliconValley") or workspace
	Players.PlayerRemoving:Connect(function(p) endCarry(p, nil); TalentDrop.clearVip(p) end)

	-- restock + ownership: 1 Hz
	task.spawn(function()
		while true do
			for _, plot in ipairs(api.plots) do
				local st = state[plot.index]
				if not st then
					st = { owner = nil, tiers = {}, folder = Instance.new("Folder") }
					st.folder.Name = "Plot" .. plot.index
					st.folder.Parent = folder
					state[plot.index] = st
				end
				if st.owner ~= plot.owner then
					clearPlot(plot.index)
					st.owner = plot.owner
				end
				local owner = plot.owner and Players:GetPlayerByUserId(plot.owner)
				local s = owner and api.session(owner)
				if owner and s and s.shipped then
					for i, tier in ipairs(Econ.TIERS) do
						local e = st.tiers[i]
						if (plot.hq and plot.hq.level or 1) < (tier.hq or 1) then
							-- locked until this HQ level (v3.0.1). v4.5: a spin-off drops you to HQ 1
							-- while last company's higher tiers still stand here: they leave
							if e and e.model then
								if e.prompt then e.prompt:Destroy(); e.prompt = nil end
								e.model:Destroy(); e.model = nil
								e.readyAt = 0
							end
						elseif not e or (not e.model and now() >= (e.readyAt or 0)) then
							local ok, err = pcall(spawnCandidate, plot, i)
							if not ok then warn("[SV] TalentDrop spawn: " .. tostring(err)) end
						elseif e.model then
							refreshTag(plot, e, tier)
						end
					end
				end
			end
			task.wait(1)
		end
	end)

	-- carries + headhunters: 20 Hz (a 10 Hz headhunter visibly stepped ~1.5 studs)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.05)
			local t = os.clock()
			local dt = t - last
			last = t
			for player, c in pairs(carries) do
				local ok, err = pcall(stepCarry, player, c, dt)
				if not ok then warn("[SV] TalentDrop carry: " .. tostring(err)); endCarry(player, nil) end
			end
		end
	end)
end

-- ============ THE VIP (v4.2 home turf) ============
--[[ Once a day a founder with an apartment finds a VIP waiting outside their
building downtown: the far end of the "rarer = further" lane, so the longest
run home. Same carry, same headhunter, same door roll as the street; the tier's
normal fee and a free seat. Only the owner can pick them up (other founders can
still poach during the run). Apartments.lua decides when; this spawns them. ]]
local vips = {}          -- player -> { model, prompt, tierIndex, luck, onPickup }

function TalentDrop.clearVip(player)
	local v = vips[player]
	vips[player] = nil
	if v and v.model and v.model.Parent then v.model:Destroy() end
end

function TalentDrop.hasVip(player) return vips[player] ~= nil end
function TalentDrop.vipPos(player)   -- v4.3 (Journey)
	local v = vips[player]
	return v and v.model and v.model.PrimaryPart and v.model.PrimaryPart.Position or nil
end

local VIP_GOLD = Color3.fromRGB(255, 208, 70)

local function recruitVip(player)
	local v = vips[player]
	if not (v and v.model and v.model.Parent) then return end
	local at = v.model.PrimaryPart
	local plot = api.plotOf(player)
	if not plot then return end
	if carries[player] then api.popup(at, "Take one home first", api.BAD) return end
	local s = api.session(player)
	if not s or not s.shipped or (s.staff or 0) < 1 then return end
	if (s.staff or 0) >= api.capacity(player) then
		api.popup(at, "No free seat  ·  build or upgrade a room", api.BAD)
		return
	end
	local tier = Econ.TIERS[v.tierIndex]
	local fee = feeFor(player, tier)
	local cash = api.cash(player)
	if not fee or not cash or cash.Value < fee then
		api.popup(at, "Need $" .. api.fmt(fee or 0), api.BAD)
		return
	end
	local c = { model = v.model, tier = tier, tierIndex = v.tierIndex, originPlot = nil, fee = fee, entry = nil,
		name = v.model:GetAttribute("PersonName") or "your VIP", from = v.model:GetPivot().Position,
		luck = v.luck, vip = true }
	vips[player] = nil
	if v.prompt then v.prompt:Destroy() end
	local tag = c.model:FindFirstChild("CandidateTag", true)
	if tag then tag:Destroy() end
	if v.onPickup then pcall(v.onPickup, player) end
	startCarry(player, plot, c)
end

function TalentDrop.spawnVip(player, pos, tierIndex, luck, onPickup)
	TalentDrop.clearVip(player)
	local tier = Econ.TIERS[tierIndex]
	if not (tier and folder) then return nil end
	local role = ROLES[math.random(1, #ROLES)]
	local seed = (player.UserId % 100000) + tierIndex * 131 + math.random(1, 9999)
	local rig = StaffRig.build(role, seed)
	rig.Name = "VIP_" .. tier.id
	rig:SetAttribute("RoleKey", role)
	rig:SetAttribute("Seed", seed)
	local y = groundY(pos.X, pos.Z)
	rig:PivotTo(CFrame.new(pos.X, y + 2.62, pos.Z))                -- faces -Z: the road
	rig:SetAttribute("Candidate", true)
	rig:SetAttribute("VIP", true)
	rig:SetAttribute("Tier", tier.id)
	rig:SetAttribute("Owner", player.UserId)
	rig:SetAttribute("Wander", Vector3.new(0.8, 0, 0.8))
	rig:SetAttribute("RoleName", (StaffRig.ROLES[role] and StaffRig.ROLES[role].name) or role:upper())
	rig:SetAttribute("TierColor", VIP_GOLD)
	rig:SetAttribute("TierName", tier.name)
	part({ Name = "TierRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 7, 7),
		CFrame = CFrame.new(pos.X, y + 0.15, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = VIP_GOLD, Material = Enum.Material.Neon }, rig)
	part({ Name = "TierPillar", Size = Vector3.new(0.5, 30, 0.5),
		CFrame = CFrame.new(pos.X, y + 5 + 15, pos.Z), Color = VIP_GOLD, Material = Enum.Material.Neon }, rig)
	local head = rig:FindFirstChild("Head")
	local old = head and head:FindFirstChild("Tag")
	if old then old.Enabled = false end
	label(head or rig.PrimaryPart, "VIP  ·  " .. tier.name, ("for %s"):format(player.DisplayName), VIP_GOLD, 220)
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "RecruitPrompt"
	pp.ActionText = "Recruit VIP"
	pp.ObjectText = ("%s  ·  pay $%s at your door"):format(tier.name, api.fmt(feeFor(player, tier) or 0))
	pp.HoldDuration = 0.35
	pp.MaxActivationDistance = 10
	pp.RequiresLineOfSight = false
	pp.Parent = rig:FindFirstChild("UpperTorso") or rig.PrimaryPart
	pp.Triggered:Connect(function(who)
		if who ~= player then
			if rig.PrimaryPart then api.popup(rig.PrimaryPart, ("%s's VIP"):format(player.DisplayName), api.BAD) end
			return
		end
		recruitVip(player)
	end)
	rig.Parent = folder
	vips[player] = { model = rig, prompt = pp, tierIndex = tierIndex, luck = luck or 1, onPickup = onPickup }
	return rig
end

-- ============ FOR THE GUIDE ============

-- v3.2 the bag: an Energy Drink changes the scooter's speed mid-carry
function TalentDrop.refreshSpeed(player)
	local c = carries[player]
	if not c or not c.baseSpeed then return end
	c.speed = c.baseSpeed + ((Econ.Inv and Econ.Inv.scooterBonus(player)) or 0)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = c.speed end
	player:SetAttribute("CarrySpeed", c.speed)
end

-- v3.2 the bag: a Non-Compete sends the headhunter chasing you home
function TalentDrop.dismissHunter(player)
	for _, c in pairs(carries) do
		local mine = c.hunter and c.hunter.Parent and c.hunter:GetAttribute("ChasingUserId") == player.UserId
		if mine then
			local rival = c.hunterRival or "The rival"
			for _, H in ipairs(c.hunters or {}) do
				local h = H.rig
				if h and h.Parent then
					if h.PrimaryPart then api.popup(h.PrimaryPart, "SIGNED A NON-COMPETE", api.BAD) end
					task.delay(0.4, function() if h.Parent then h:Destroy() end end)
				end
			end
			c.hunters = {}
			c.hunter = nil
			player:SetAttribute("ChaseDist", nil)
			toast(player, ("%s's headhunter gave up. Get them home!"):format(rival))
			return true
		end
	end
	return false
end

function TalentDrop.carrying(player)
	local c = carries[player]
	if not c then return nil end
	return { name = c.name, tier = c.tier, deadline = c.deadline, speed = c.speed }
end

-- v4.3 (Journey): a candidate of one tier (e.g. "genius") this player can recruit right now
function TalentDrop.candidate(player, tierId, cashValue)
	local plot = api.plotOf(player)
	local st = plot and state[plot.index]
	if not st then return nil end
	for i, tier in ipairs(Econ.TIERS) do
		if tier.id == tierId then
			local e = st.tiers[i]
			local fee = feeFor(player, tier)
			if e and e.model and e.model.PrimaryPart and fee and fee <= (cashValue or 0) then
				return { tier = tier, fee = fee, pos = e.model.PrimaryPart.Position }
			end
		end
	end
	return nil
end

-- the best candidate standing for this player that they can afford (spend <= 80% of cash)
function TalentDrop.bestFor(player, cashValue)
	local plot = api.plotOf(player)
	local st = plot and state[plot.index]
	if not st then return nil end
	local best
	for i, tier in ipairs(Econ.TIERS) do
		local e = st.tiers[i]
		local fee = feeFor(player, tier)
		if e and e.model and e.model.PrimaryPart and fee then
			if i == 1 or fee <= cashValue * 0.8 then
				best = { tier = tier, index = i, fee = fee, pos = e.model.PrimaryPart.Position }
			end
		end
	end
	return best
end

-- Studio test harness only: the VIP pickup the prompt calls (prompts need real input)
function TalentDrop.devPickVip(player)
	if not game:GetService("RunService"):IsStudio() then return end
	recruitVip(player)
end

-- Studio test harness only (SiliconCore's dev bot): the same recruit() the prompt calls
function TalentDrop.devRecruit(player, i)
	if not game:GetService("RunService"):IsStudio() then return end
	local plot = api.plotOf(player)
	if plot then recruit(player, plot, i) end
end

return TalentDrop
