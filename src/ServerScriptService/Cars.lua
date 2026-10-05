--[[
	Cars (v4.0) -- driving, a company car, and a dealership.

	His ask: "maybe you can drive there by adding driving mechanics, although I
	wouldn't want someone to be able to use a car in a headhunter chase."

	  - At HQ 2 the company gives you a car (the hatchback): it waits in a
	    parking bay by your campus's path, facing the road.
	  - Press E at it to drive. WASD / thumbstick / gamepad (the VehicleSeat
	    gives all three). Jump to get out. The CAR button calls it to you.
	  - VALLEY MOTORS (downtown) sells five more, each faster than the last.
	    Buying one plays a reveal and parks it on the forecourt, keys in.
	  - NO CARS IN A CHASE: you can't get in while carrying a recruit, and if a
	    carry starts while you're driving (you picked one up through the
	    window), you're put out of the car on the spot.

	Physics: the car is ONE unanchored chassis box owned by its driver; the
	client drives it (CarClient) by setting its velocity along its heading and
	an AlignOrientation that keeps it upright on the ground. The Kenney body
	and wheels ride on it (welds; the wheels on Motor6Ds so they can spin).
	Saved: `cars` (owned ids) and `car` (the one you drive).
]]
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Cars = {}

Cars.CATALOG = {
	{ id = "hatch", name = "HATCHBACK", model = "hatchback-sports", price = 0, speed = 64, accel = 38, blurb = "Your company car." },
	{ id = "sedan", name = "SEDAN", model = "sedan", price = 60000, speed = 74, accel = 44, blurb = "Room for the whole founding team." },
	{ id = "suv", name = "LUXURY SUV", model = "suv-luxury", fallback = "suv", price = 450000, speed = 80, accel = 48, blurb = "Arrive like you raised a Series A." },
	{ id = "sports", name = "SPORTS COUPE", model = "sedan-sports", price = 3000000, speed = 98, accel = 60, blurb = "Quick. Loud. Very Palo Alto." },
	{ id = "racer", name = "RACER", model = "race", fallback = "sedan-sports", price = 20000000, speed = 114, accel = 70, blurb = "Built for a track. Driven to standups." },
	{ id = "hyper", name = "HYPERCAR", model = "race-future", fallback = "sedan-sports", price = 90000000, speed = 132, accel = 82, blurb = "The unicorn of cars." },
}
local BY_ID = {}
for i, c in ipairs(Cars.CATALOG) do c.order = i; BY_ID[c.id] = c end
Cars.BY_ID = BY_ID

local CAR_SCALE = 0.05
Cars.RIDE = 0.8
local api
local remotes = {}
local spawned = {}          -- [userId] = Model

local function template(entry)
	local kit = RS:FindFirstChild("KenneyKit")
	return kit and (kit:FindFirstChild(entry.model) or (entry.fallback and kit:FindFirstChild(entry.fallback)))
end

local function part(parent, props)
	local p = Instance.new("Part")
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	p.Parent = parent
	return p
end

-- a static showroom copy (anchored, no seat)
function Cars.display(id, cf, parent)
	local entry = BY_ID[id]
	local t = entry and template(entry)
	if not t then return nil end
	local m = t:Clone()
	m.Name = "Display_" .. id
	m:ScaleTo(CAR_SCALE)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CastShadow = true end
	end
	local bb, size = m:GetBoundingBox()
	m:PivotTo(cf * CFrame.new(0, size.Y / 2 + 0.05 - (bb.Position.Y - m:GetPivot().Position.Y), 0))
	m.Parent = parent
	return m
end

-- build a drivable car at `cf` (its feet on cf's position, nose along cf's LookVector)
local function build(player, entry, cf)
	local t = template(entry)
	if not t then return nil end
	local m = Instance.new("Model")
	m.Name = "Car_" .. player.UserId
	local body = t:Clone()
	body:ScaleTo(CAR_SCALE)
	local bb, size = body:GetBoundingBox()
	local chassis = part(m, {
		Name = "Chassis", Size = Vector3.new(size.X * 0.92, 1.6, size.Z * 0.94),
		Transparency = 1, CanCollide = true, CanQuery = false, Massless = false, Anchored = false,
		CustomPhysicalProperties = PhysicalProperties.new(0.9, 0.02, 0, 100, 1),
	})
	m.PrimaryPart = chassis
	-- the chassis box rides RIDE studs over the ground (CarClient's hover spring
	-- holds it there, so kerbs and slopes don't stop it); the wheels touch down
	local RIDE = Cars.RIDE
	chassis.CFrame = cf * CFrame.new(0, RIDE + 0.8, 0)
	chassis.Anchored = true                      -- parked cars don't move; a driver unanchors it
	local rel = bb:ToObjectSpace(body:GetPivot())
	body:PivotTo(chassis.CFrame * CFrame.new(0, -0.8 - RIDE + size.Y / 2, 0) * rel)
	for _, d in ipairs(body:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.Massless = true
			d.CastShadow = true
			if d.Name:sub(1, 5) == "wheel" then
				local mot = Instance.new("Motor6D")
				mot.Name = "Axle"
				mot.Part0 = chassis
				mot.Part1 = d
				mot.C0 = chassis.CFrame:ToObjectSpace(d.CFrame)
				mot.C1 = CFrame.new()
				mot:SetAttribute("Front", chassis.CFrame:PointToObjectSpace(d.Position).Z < 0)
				mot.Parent = chassis
			else
				local w = Instance.new("WeldConstraint")
				w.Part0 = chassis
				w.Part1 = d
				w.Parent = d
			end
		end
	end
	body.Parent = m
	-- the seat: invisible, over the chassis, a little behind centre
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.4, 2)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanTouch = false
	seat.CanQuery = false
	seat.Massless = true
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.HeadsUpDisplay = false
	seat.CFrame = chassis.CFrame * CFrame.new(-size.X * 0.18, 0.6, size.Z * 0.08)
	seat.Parent = m
	local sw = Instance.new("WeldConstraint")
	sw.Part0 = chassis
	sw.Part1 = seat
	sw.Parent = seat
	-- upright keeper (the client steers its target)
	local att = Instance.new("Attachment")
	att.Name = "Align"
	att.Parent = chassis
	local ao = Instance.new("AlignOrientation")
	ao.Name = "Keep"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = 1e7
	ao.Responsiveness = 45
	ao.CFrame = chassis.CFrame.Rotation
	ao.Parent = chassis
	-- the prompt: owner drives; anyone else just sees whose it is
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Drive"
	pp.ObjectText = entry.name
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	pp.Parent = chassis
	pp.Triggered:Connect(function(p)
		if p ~= player then return end
		if p:GetAttribute("Carrying") then
			remotes.toast:FireClient(p, "Not with a recruit! Walk them home first.")
			return
		end
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then seat:Sit(hum) end
	end)
	-- a driver takes the physics; an empty car parks (anchors) where it stopped
	local parkToken = 0
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		parkToken += 1
		pp.Enabled = seat.Occupant == nil          -- the "Drive" prompt sat mid-screen the whole drive
		if seat.Occupant then
			chassis.Anchored = false
			local who = Players:GetPlayerFromCharacter(seat.Occupant.Parent)
			if who then pcall(function() chassis:SetNetworkOwner(who) end) end
		else
			local mine = parkToken
			task.delay(2, function()
				if mine == parkToken and not seat.Occupant and chassis.Parent then
					chassis.AssemblyLinearVelocity = Vector3.zero
					chassis.Anchored = true
				end
			end)
		end
	end)
	m:SetAttribute("Owner", player.UserId)
	m:SetAttribute("CarId", entry.id)
	m:SetAttribute("Speed", entry.speed)
	m:SetAttribute("Accel", entry.accel)
	CollectionService:AddTag(m, "SVCar")
	m.Parent = workspace
	return m
end

function Cars.despawn(player)
	local m = spawned[player.UserId]
	if m then m:Destroy() end
	spawned[player.UserId] = nil
end

function Cars.spawn(player, cf)
	local s = api.session(player)
	if not s or not s.car or not BY_ID[s.car] then return nil end
	Cars.despawn(player)
	local m = build(player, BY_ID[s.car], cf)
	spawned[player.UserId] = m
	player:SetAttribute("CarId", s.car)
	return m
end

-- the parking bay by a plot's path (plot-local), nose to the road
function Cars.bayOf(plot)
	return plot.pivot * CFrame.new(-13, 0.4, 92.5) * CFrame.Angles(0, math.pi, 0)
end

local function owns(s, id)
	for _, c in ipairs(s.cars or {}) do if c == id then return true end end
	return false
end
Cars.owns = owns

-- v4.3 (Journey): where your car is, and whether you are sitting in it
function Cars.carPos(player)
	local m = spawned[player.UserId]
	return m and m.PrimaryPart and m.PrimaryPart.Position or nil
end

function Cars.driving(player)
	local m = spawned[player.UserId]
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return (m and hum and hum.SeatPart and hum.SeatPart:IsDescendantOf(m)) and true or false
end

function Cars.hasCar(player)
	local s = api and api.session(player)
	return s and s.cars and #s.cars > 0
end

-- the company car at HQ 2 (and for saves that passed HQ 2 before cars existed)
function Cars.grant(player, id, why)
	local s = api.session(player)
	if not s or owns(s, id) then return false end
	s.cars = s.cars or {}
	table.insert(s.cars, id)
	s.car = s.car or id
	player:SetAttribute("CarOwned", true)
	local plot = api.plotOf(player)
	local m = plot and Cars.spawn(player, Cars.bayOf(plot))
	if why then
		remotes.cinema:FireClient(player, { kind = "car", name = BY_ID[id].name, speed = BY_ID[id].speed, title = why,
			focus = m and m.PrimaryPart and m.PrimaryPart.Position, delay = 3.2 })
	end
	return true
end

-- call the car to you: beside you, on open ground, nose where you look
local function callCar(player)
	if player:GetAttribute("Carrying") then
		remotes.toast:FireClient(player, "Not during a recruit run!")
		return
	end
	local s = api.session(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not s or not root or not s.car then return end
	local hum = player.Character:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart then return end
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.1 then look = Vector3.new(0, 0, -1) end
	look = look.Unit
	local right = look:Cross(Vector3.new(0, 1, 0))
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character, spawned[player.UserId] }
	for _, off in ipairs({ right * 10, -right * 10, look * 12, -look * 12 }) do
		local at = root.Position + off
		-- open sky above it (not inside the HQ), ground below it
		local up = workspace:Raycast(at + Vector3.new(0, 2, 0), Vector3.new(0, 60, 0), params)
		local down = workspace:Raycast(at + Vector3.new(0, 6, 0), Vector3.new(0, -30, 0), params)
		if not up and down then
			Cars.spawn(player, CFrame.lookAt(down.Position, down.Position + look))
			return
		end
	end
	remotes.toast:FireClient(player, "Step outside to call your car")
end

local function buyCar(player, id)
	local s = api.session(player)
	local entry = BY_ID[id]
	if not s or not entry then return end
	if owns(s, id) then
		-- already yours: make it the one you drive
		s.car = id
		Cars.spawn(player, Cars.forecourt or Cars.bayOf(api.plotOf(player)))
		remotes.toast:FireClient(player, entry.name .. " is on the forecourt")
		return
	end
	local cash = api.cash(player)
	if not cash or cash.Value < entry.price then
		remotes.dealer:FireClient(player, Cars.status(player))
		return
	end
	cash.Value -= entry.price
	s.lastBuy = os.clock()
	s.cars = s.cars or {}
	table.insert(s.cars, id)
	s.car = id
	player:SetAttribute("CarOwned", true)
	local m = Cars.spawn(player, Cars.forecourt or Cars.bayOf(api.plotOf(player)))
	remotes.cinema:FireClient(player, { kind = "car", name = entry.name, speed = entry.speed,
		focus = m and m.PrimaryPart and m.PrimaryPart.Position })
	if api.telemetry then pcall(api.telemetry, player, "car_" .. id) end
end

function Cars.status(player)
	local s = api.session(player)
	local list = {}
	for _, c in ipairs(Cars.CATALOG) do
		table.insert(list, { id = c.id, name = c.name, price = c.price, speed = c.speed, blurb = c.blurb,
			owned = s and owns(s, c.id) or false, driving = s and s.car == c.id or false })
	end
	return { cars = list, cash = api.cash(player) and api.cash(player).Value or 0, top = Cars.CATALOG[#Cars.CATALOG].speed }
end

function Cars.init(a)
	api = a
	local folder = RS:WaitForChild("SVRemotes")
	local function ev(name)
		local r = folder:FindFirstChild(name) or Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = folder
		return r
	end
	remotes.call = ev("CallCar")
	remotes.buy = ev("BuyCar")
	remotes.dealer = ev("DealerMenu")
	remotes.toast = ev("CarToast")
	remotes.cinema = ev("Cinema")
	remotes.call.OnServerEvent:Connect(callCar)
	remotes.buy.OnServerEvent:Connect(function(p, id) if typeof(id) == "string" then buyCar(p, id) end end)
	Players.PlayerRemoving:Connect(Cars.despawn)
	-- a painted parking bay by every campus path, so a parked car looks parked
	task.spawn(function()
		local sv = workspace:WaitForChild("SiliconValley", 30)
		local plots = sv and sv:WaitForChild("Plots", 30)
		if not plots then return end
		for _, pf in ipairs(plots:GetChildren()) do
			local pivot = pf:GetAttribute("Pivot")
			if typeof(pivot) == "CFrame" then
				local bay = pivot * CFrame.new(-13, 0, 92)
				part(pf, { Name = "ParkingBay", Size = Vector3.new(9, 0.4, 15), CFrame = bay * CFrame.new(0, 0.2, 0), Anchored = true,
					Color = Color3.fromRGB(70, 72, 78), Material = Enum.Material.Asphalt, CanQuery = true, CastShadow = false })
				for _, sx in ipairs({ -1, 1 }) do
					part(pf, { Name = "BayLine", Size = Vector3.new(0.35, 0.05, 14), CFrame = bay * CFrame.new(sx * 4.1, 0.42, 0), Anchored = true,
						Color = Color3.fromRGB(240, 240, 232), CanCollide = false, CanQuery = false, CastShadow = false })
				end
				part(pf, { Name = "BayStop", Size = Vector3.new(4, 0.4, 0.6), CFrame = bay * CFrame.new(0, 0.6, -6.6), Anchored = true,
					Color = Color3.fromRGB(226, 220, 208), Material = Enum.Material.Concrete, CanCollide = false, CastShadow = false })
			end
		end
	end)
	-- NO CARS IN A CHASE: a carry that starts in a car ends the drive
	local function watch(p)
		p:GetAttributeChangedSignal("Carrying"):Connect(function()
			if not p:GetAttribute("Carrying") then return end
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			local seat = hum and hum.SeatPart
			if seat and seat:IsA("VehicleSeat") and seat.Parent and CollectionService:HasTag(seat.Parent, "SVCar") then
				hum.Sit = false
				hum.Jump = true
				remotes.toast:FireClient(p, "Out of the car! Recruits walk.")
			end
		end)
	end
	for _, p in ipairs(Players:GetPlayers()) do watch(p) end
	Players.PlayerAdded:Connect(watch)
	-- the showroom: a car on each display pad, a prompt to look at it
	task.spawn(function()
		local SSS = game:GetService("ServerScriptService")
		local dm = SSS:FindFirstChild("Downtown")
		local ok, D = pcall(function() return dm and require(dm) end)
		if not ok or not D then return end
		for _ = 1, 60 do
			if D.dealerPads and D.folder then break end
			task.wait(0.5)
		end
		if not D.dealerPads then return end
		Cars.forecourt = D.dealerForecourt

		--[[ THE CAMPUS SHOWROOM (v7).

		His note: "the car dealership is awkwardly placed towards the end of the
		map". It is -- Valley Motors sits in downtown, past x 620, while the
		plots ring the origin. Buying a car meant a 600-stud drive to a place you
		had no other reason to visit, which is the opposite of how a reward
		should work.

		Downtown stays (it is a real destination, and the towers and apartments
		are there). What moves is the OFFER: one car on the campus green, by the
		promenade, with the same dealer menu on it. You can still drive out to see
		the full range; you no longer have to.

		The green itself already exists -- CampusArch's promenade loop rings a
		lawn. This puts something on it worth walking to. ]]
		-- v9: this was CFrame.new(0, 0.6, 66), which sat on CampusArch's old
		-- per-plot promenade. That spot is the middle of the CENTRAL PARK now,
		-- so the showroom car was parked in the fountain court. It stands in the
		-- gap between the park kerb and the inner ring road instead -- where a
		-- car can plausibly be, and on the walk in from the gate.
		local hub = game:GetService("ServerScriptService"):FindFirstChild("CampusHub")
		local okH, HUB = pcall(function() return hub and require(hub) end)
		local showR = ((okH and HUB and HUB.R_PARK) or 162) + 24
		local showA = math.rad(35)
		local show = CFrame.new(math.cos(showA) * showR, 0.6, math.sin(showA) * showR)
			* CFrame.Angles(0, math.atan2(-math.cos(showA), -math.sin(showA)), 0)
		local sm = Cars.display("sports", show, D.folder)
		if sm then
			local ap = sm.PrimaryPart or sm:FindFirstChildWhichIsA("BasePart")
			if ap then
				--[[ THE STAND (v5.0). Reported 5 Oct: "there is a Valley Motors
					car rotating in front of my building, and it's rotating when
					there's literally nothing else around it, which is not normal."

					He is right, and the rotation is not the fault. A car turning
					on a plinth under a sign is one of the most legible objects in
					any retail park; a car turning on a bare slab in the middle of
					a lawn is a glitch. What was missing was everything that says
					DISPLAY -- so the car had showroom BEHAVIOUR with no showroom
					around it, and the eye reads the odd one out as broken.

					So it gets the furniture the behaviour implies: a stepped
					plinth, a pylon sign, four posts with a rope between them, and
					two spots aimed down at the paint. Nothing here is decoration
					for its own sake -- each piece is one of the cues that tells
					you at a glance this is a thing on show and not a thing left
					behind. ]]
				local function sp(props)
					local q = Instance.new("Part")
					q.Anchored = true
					q.CanCollide = false
					q.CanQuery = false
					q.Material = Enum.Material.SmoothPlastic
					for k, v in pairs(props) do q[k] = v end
					q.Parent = D.folder
					return q
				end
				local STONE = Color3.fromRGB(214, 209, 198)
				local DARK  = Color3.fromRGB(58, 62, 70)
				local BRASS = Color3.fromRGB(198, 162, 86)

				--[[ v5.0b, after looking at the first attempt on screen rather
					than trusting the maths: the pylon stood on the approach axis
					so a black slab covered the car, the ropes were built from a
					hand-rolled angle and ran THROUGH it, and the plinth was the
					same stone as the paving it sat on, so there was no plinth to
					see. Rebuilt with the sign off to one side, the ropes aimed
					with CFrame.lookAt between their own posts, and a dark rim the
					disc can read against. ]]
				local R_DISC = 10.5

				-- plinth: dark rim, pale inlay, raised enough to throw a shadow
				sp({ Name = "ShowroomRim", Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(1.1, R_DISC * 2 + 1.6, R_DISC * 2 + 1.6), Color = DARK,
					CFrame = show * CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)) })
				sp({ Name = "ShowroomPad", Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(1.2, R_DISC * 2, R_DISC * 2), Color = STONE,
					CFrame = show * CFrame.new(0, 0.12, 0) * CFrame.Angles(0, 0, math.rad(90)) })
				sp({ Name = "ShowroomInlay", Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(1.24, R_DISC * 0.9, R_DISC * 0.9), Color = BRASS,
					Material = Enum.Material.Metal,
					CFrame = show * CFrame.new(0, 0.13, 0) * CFrame.Angles(0, 0, math.rad(90)) })

				-- four posts, and a rope aimed between its own two posts
				local R_POST = R_DISC + 2.6
				local post = {}
				for i = 0, 3 do
					local a = math.rad(45 + i * 90)
					post[i] = Vector3.new(math.cos(a) * R_POST, 0, math.sin(a) * R_POST)
					sp({ Name = "ShowroomPost", Size = Vector3.new(0.34, 2.9, 0.34),
						CFrame = show * CFrame.new(post[i] + Vector3.new(0, 1.45, 0)), Color = DARK })
					sp({ Name = "ShowroomPostCap", Shape = Enum.PartType.Ball,
						Size = Vector3.new(0.58, 0.58, 0.58),
						CFrame = show * CFrame.new(post[i] + Vector3.new(0, 3.05, 0)), Color = BRASS })
				end
				for i = 0, 3 do
					local a, b = post[i] + Vector3.new(0, 2.25, 0), post[(i + 1) % 4] + Vector3.new(0, 2.25, 0)
					local mid = (a + b) / 2 - Vector3.new(0, 0.28, 0)   -- a rope sags
					sp({ Name = "ShowroomRope", Size = Vector3.new(0.14, 0.14, (b - a).Magnitude),
						CFrame = show * CFrame.lookAt(mid, mid + (b - a).Unit),
						Color = Color3.fromRGB(150, 36, 40) })
				end

				--[[ The sign stands at the back-left quarter, clear of the sight
					line you approach on, so it labels the car instead of hiding
					it. ]]
				local signAt = Vector3.new(-12.4, 0, -12.4)
				sp({ Name = "ShowroomPylonFoot", Size = Vector3.new(2.8, 0.6, 2.8),
					CFrame = show * CFrame.new(signAt + Vector3.new(0, 0.3, 0)), Color = DARK })
				local mast = sp({ Name = "ShowroomPylon", Size = Vector3.new(0.75, 7.6, 0.75),
					CFrame = show * CFrame.new(signAt + Vector3.new(0, 4.1, 0)), Color = DARK })
				local blade = sp({ Name = "ShowroomBlade", Size = Vector3.new(6.4, 2.9, 0.4),
					CFrame = show * CFrame.new(signAt + Vector3.new(0, 9.3, 0)) * CFrame.Angles(0, math.rad(45), 0),
					Color = Color3.fromRGB(246, 244, 238) })
				for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
					local sg = Instance.new("SurfaceGui")
					sg.Face = face
					sg.PixelsPerStud = 42
					sg.Parent = blade
					local t = Instance.new("TextLabel")
					t.Size = UDim2.fromScale(1, 1)
					t.BackgroundTransparency = 1
					t.Font = Enum.Font.FredokaOne
					t.Text = "VALLEY MOTORS"
					t.TextColor3 = DARK
					t.TextScaled = true
					t.Parent = sg
				end

				--[[ Two spots raked in from the front corners. A lit car under a
					sign is the whole reason a turntable reads as a display rather
					than as something spinning for no reason. ]]
				for _, sx in ipairs({ -1, 1 }) do
					sp({ Name = "ShowroomSpot", Size = Vector3.new(0.26, 7.4, 0.26),
						CFrame = show * CFrame.new(sx * 12.2, 3.7, 11.6), Color = DARK })
					local head = sp({ Name = "ShowroomSpotHead", Size = Vector3.new(0.85, 0.55, 0.85),
						CFrame = show * CFrame.new(sx * 12.2, 7.3, 11.6), Color = Color3.fromRGB(255, 244, 214),
						Material = Enum.Material.Neon })
					local l = Instance.new("SpotLight")
					l.Angle = 78
					l.Range = 26
					l.Brightness = 1.6
					l.Face = Enum.NormalId.Bottom
					l.Color = Color3.fromRGB(255, 246, 224)
					l.Parent = head
				end
				mast.CanQuery = false
				CollectionService:AddTag(sm, "SVTurntable")
				local pp = Instance.new("ProximityPrompt")
				pp.ActionText = "Cars"
				pp.ObjectText = "Valley Motors"
				pp.HoldDuration = 0
				pp.MaxActivationDistance = 16
				pp.RequiresLineOfSight = false
				pp.Parent = ap
				pp.Triggered:Connect(function(p)
					local st = Cars.status(p)
					remotes.dealer:FireClient(p, st)
				end)
			end
		end
		local order = { "sedan", "suv", "sports", "racer", "hyper" }
		for i, cf in ipairs(D.dealerPads) do
			local id = order[i]
			local m = id and Cars.display(id, cf, D.folder)
			if m then
				if i == 5 then CollectionService:AddTag(m, "SVTurntable") end
				local anchorPart = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
				local pp = Instance.new("ProximityPrompt")
				pp.ActionText = "Look"
				pp.ObjectText = BY_ID[id].name
				pp.HoldDuration = 0
				pp.MaxActivationDistance = 14
				pp.RequiresLineOfSight = false
				pp.Parent = anchorPart
				pp.Triggered:Connect(function(p)
					local st = Cars.status(p)
					st.focus = id
					remotes.dealer:FireClient(p, st)
				end)
			end
		end
	end)
end

-- saves: ids only, validated against the catalog
function Cars.save(s)
	local t = {}
	for _, id in ipairs(s.cars or {}) do if BY_ID[id] then table.insert(t, id) end end
	return t
end

function Cars.onLoad(player, s, data, plot)
	s.cars = {}
	if type(data.cars) == "table" then
		for _, id in ipairs(data.cars) do
			if typeof(id) == "string" and BY_ID[id] and not owns(s, id) then table.insert(s.cars, id) end
		end
	end
	s.car = (typeof(data.car) == "string" and owns(s, data.car)) and data.car or s.cars[1]
	-- saves from before cars: past HQ 2 means the company car is theirs
	if #s.cars == 0 and plot and plot.hq and plot.hq.level >= 2 then
		table.insert(s.cars, "hatch")
		s.car = "hatch"
	end
	player:SetAttribute("CarOwned", #s.cars > 0)
	if s.car and plot then task.defer(Cars.spawn, player, Cars.bayOf(plot)) end
end

return Cars
