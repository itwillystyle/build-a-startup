--[[
	LifeClient -- LocalScript in StarterPlayer -> StarterPlayerScripts (v3.3).

	THE VALLEY MOVES. A friend's verdict was "it feels like a Minecraft
	superflat world", and the fix is not more static props: it is things
	that MOVE and SOUND, the way a real place does.

	  people     walkers, joggers and cyclists on the main-road and
	             cross-street sidewalks, keeping right, some with backpacks
	  birds      three flocks: gulls over the Bay, crows over the south
	             ridge, a flock over the northern hills
	  jets       an airliner crosses high over the valley every two minutes,
	             with a contrail and a distant rumble
	  Caltrain   a double-deck commuter train runs between the two tunnels,
	             stops at the Mountain View platform behind the middle campus,
	             horn and engine as it passes
	  sound      Northern California birdsong under everything

	Everything is built and moved HERE, on the client: zero server parts,
	zero replication (the lag lesson of v2.8.1). The train and the jet run on
	workspace:GetServerTimeNow(), so every player sees them in the same place
	at the same moment. People are per-client scenery.
	Audio: Roblox Pro Sound Effects (licensed, pre-moderated).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local rng = Random.new()

local folder = Instance.new("Folder")
folder.Name = "Life"
folder.Parent = workspace

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do p[k] = v end
	p.Parent = parent or folder
	return p
end

local function now() return workspace:GetServerTimeNow() end

-- ============ PEOPLE ============

local SKIN = { Color3.fromRGB(255, 219, 172), Color3.fromRGB(224, 172, 128), Color3.fromRGB(176, 122, 86), Color3.fromRGB(120, 80, 56), Color3.fromRGB(240, 200, 160) }
local HAIR = { Color3.fromRGB(40, 30, 24), Color3.fromRGB(90, 60, 36), Color3.fromRGB(200, 160, 90), Color3.fromRGB(20, 20, 22), Color3.fromRGB(150, 90, 60) }
local SHIRT = { Color3.fromRGB(70, 130, 220), Color3.fromRGB(230, 90, 90), Color3.fromRGB(80, 170, 110), Color3.fromRGB(245, 245, 240), Color3.fromRGB(60, 64, 76),
	Color3.fromRGB(240, 180, 60), Color3.fromRGB(150, 110, 200), Color3.fromRGB(40, 150, 170) }
local PANTS = { Color3.fromRGB(46, 58, 90), Color3.fromRGB(40, 40, 44), Color3.fromRGB(150, 130, 100), Color3.fromRGB(90, 94, 100) }
local BIKE = { Color3.fromRGB(220, 60, 50), Color3.fromRGB(60, 120, 220), Color3.fromRGB(250, 200, 40), Color3.fromRGB(40, 170, 110) }
local function pick(t) return t[rng:NextInteger(1, #t)] end

local function newPerson(kind)
	local skin, shirt, pants = pick(SKIN), pick(SHIRT), pick(PANTS)
	if kind == "jog" then shirt = pick({ Color3.fromRGB(255, 120, 60), Color3.fromRGB(60, 200, 230), Color3.fromRGB(230, 60, 150) }) end
	local p = { kind = kind }
	p.torso = part({ Name = "Torso", Size = Vector3.new(2, 2, 1), Color = shirt })
	p.head = part({ Name = "Head", Size = Vector3.new(1.2, 1.2, 1.2), Color = skin })
	p.hair = part({ Name = "Hair", Size = Vector3.new(1.28, 0.45, 1.28), Color = pick(HAIR) })
	p.armL = part({ Name = "Arm", Size = Vector3.new(0.9, 2, 0.9), Color = shirt })
	p.armR = part({ Name = "Arm", Size = Vector3.new(0.9, 2, 0.9), Color = shirt })
	p.legL = part({ Name = "Leg", Size = Vector3.new(0.95, 2, 0.95), Color = pants })
	p.legR = part({ Name = "Leg", Size = Vector3.new(0.95, 2, 0.95), Color = pants })
	if kind == "walk" and rng:NextNumber() < 0.35 then
		p.pack = part({ Name = "Backpack", Size = Vector3.new(1.5, 1.6, 0.7), Color = pick({ Color3.fromRGB(40, 44, 52), Color3.fromRGB(180, 60, 50), Color3.fromRGB(60, 90, 140) }) })
	end
	if kind == "bike" then
		local c = pick(BIKE)
		p.wheelF = part({ Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2.6, 2.6), Color = Color3.fromRGB(30, 30, 32) })
		p.wheelB = part({ Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2.6, 2.6), Color = Color3.fromRGB(30, 30, 32) })
		p.frame = part({ Name = "Frame", Size = Vector3.new(0.3, 0.35, 3.4), Color = c })
		p.post = part({ Name = "Post", Size = Vector3.new(0.3, 1.6, 0.3), Color = c })
		p.bar = part({ Name = "Bar", Size = Vector3.new(1.6, 0.25, 0.25), Color = Color3.fromRGB(40, 40, 44) })
	end
	return p
end

-- where people go: both sidewalks of the main road and of the two cross streets
local ROAD_Z, SIDEWALK, BIKELANE = 0, 19.5, 15
local CROSS_X = { -185, 165 }
local Y_WALK = 0.85
local lanes = {}
for _, s in ipairs({ -1, 1 }) do
	table.insert(lanes, { a = Vector3.new(-540, Y_WALK, ROAD_Z + s * SIDEWALK), b = Vector3.new(900, Y_WALK, ROAD_Z + s * SIDEWALK), foot = true })
	table.insert(lanes, { a = Vector3.new(-540, Y_WALK, ROAD_Z + s * BIKELANE), b = Vector3.new(900, Y_WALK, ROAD_Z + s * BIKELANE), bike = true })
	for _, cx in ipairs(CROSS_X) do
		table.insert(lanes, { a = Vector3.new(cx + s * SIDEWALK, Y_WALK, -240), b = Vector3.new(cx + s * SIDEWALK, Y_WALK, 240), foot = true })
	end
end
local footLanes, bikeLanes = {}, {}
for _, l in ipairs(lanes) do
	l.len = (l.b - l.a).Magnitude
	l.dir = (l.b - l.a).Unit
	l.side = Vector3.new(-l.dir.Z, 0, l.dir.X)          -- keep-right offset axis
	table.insert(l.foot and footLanes or bikeLanes, l)
end

local agents = {}
-- the main-road sidewalks are where players look: they get three times the people
local weighted = {}
for _, l in ipairs(footLanes) do
	for _ = 1, (math.abs(l.dir.X) > 0.5) and 3 or 1 do table.insert(weighted, l) end
end
local function spawnAgent(kind)
	local lane = (kind == "bike") and pick(bikeLanes) or pick(weighted)
	local a = newPerson(kind)
	a.lane = lane
	a.s = rng:NextNumber(0, lane.len)
	a.way = (rng:NextNumber() < 0.5) and 1 or -1
	a.speed = (kind == "walk" and rng:NextNumber(4.2, 5.8)) or (kind == "jog" and rng:NextNumber(10, 12.5)) or rng:NextNumber(16, 21)
	a.phase = rng:NextNumber(0, 6.28)
	table.insert(agents, a)
end
for _ = 1, 36 do spawnAgent("walk") end
for _ = 1, 6 do spawnAgent("jog") end
for _ = 1, 6 do spawnAgent("bike") end

local function poseAgent(a, parts, cfs)
	local lane = a.lane
	local pos = lane.a + lane.dir * a.s + lane.side * (a.way * 1.3)
	local root = CFrame.lookAt(pos, pos + lane.dir * a.way)
	local function put(p, cf) if p then table.insert(parts, p); table.insert(cfs, cf) end end
	if a.kind == "bike" then
		local body = root * CFrame.new(0, 2.7, 0.2) * CFrame.Angles(-0.35, 0, 0)
		put(a.wheelF, root * CFrame.new(0, 1.3, -1.7))
		put(a.wheelB, root * CFrame.new(0, 1.3, 1.7))
		put(a.frame, root * CFrame.new(0, 1.9, 0))
		put(a.post, root * CFrame.new(0, 2.4, -1.5))
		put(a.bar, root * CFrame.new(0, 3.2, -1.5))
		put(a.torso, body * CFrame.new(0, 1.3, 0))
		put(a.head, body * CFrame.new(0, 2.9, -0.2))
		put(a.hair, body * CFrame.new(0, 3.55, -0.2))
		put(a.armL, body * CFrame.new(-1.45, 1.8, 0) * CFrame.Angles(-1.1, 0, 0) * CFrame.new(0, -0.9, 0))
		put(a.armR, body * CFrame.new(1.45, 1.8, 0) * CFrame.Angles(-1.1, 0, 0) * CFrame.new(0, -0.9, 0))
		local pedal = math.sin(a.phase) * 0.7
		put(a.legL, root * CFrame.new(-0.5, 2.6, 0.3) * CFrame.Angles(-0.9 + pedal, 0, 0) * CFrame.new(0, -1, 0))
		put(a.legR, root * CFrame.new(0.5, 2.6, 0.3) * CFrame.Angles(-0.9 - pedal, 0, 0) * CFrame.new(0, -1, 0))
		return
	end
	local jog = a.kind == "jog"
	local swing = math.sin(a.phase) * (jog and 0.9 or 0.55)
	local bob = jog and math.abs(math.sin(a.phase)) * 0.25 or math.abs(math.sin(a.phase)) * 0.08
	local base = root * CFrame.new(0, bob, 0)
	put(a.torso, base * CFrame.new(0, 3, 0) * CFrame.Angles(jog and -0.12 or 0, 0, 0))
	put(a.head, base * CFrame.new(0, 4.6, jog and -0.2 or 0))
	put(a.hair, base * CFrame.new(0, 5.25, jog and -0.2 or 0))
	put(a.pack, base * CFrame.new(0, 3.1, 0.85))
	local armBend = jog and -0.6 or 0
	put(a.armL, base * CFrame.new(-1.45, 3.9, 0) * CFrame.Angles(swing + armBend, 0, 0) * CFrame.new(0, -0.95, 0))
	put(a.armR, base * CFrame.new(1.45, 3.9, 0) * CFrame.Angles(-swing + armBend, 0, 0) * CFrame.new(0, -0.95, 0))
	put(a.legL, base * CFrame.new(-0.5, 2, 0) * CFrame.Angles(-swing, 0, 0) * CFrame.new(0, -1, 0))
	put(a.legR, base * CFrame.new(0.5, 2, 0) * CFrame.Angles(swing, 0, 0) * CFrame.new(0, -1, 0))
end

-- ============ BIRDS ============

local flocks = {
	{ c = Vector3.new(-760, 38, 40), r = 90, alt = 38, w = 0.22, color = Color3.fromRGB(236, 236, 232), n = 7 },     -- gulls over the Bay
	{ c = Vector3.new(-80, 110, -470), r = 130, alt = 110, w = -0.15, color = Color3.fromRGB(34, 34, 38), n = 6 },    -- crows over the ridge
	{ c = Vector3.new(260, 90, 440), r = 150, alt = 90, w = 0.12, color = Color3.fromRGB(70, 60, 54), n = 6 },        -- over the northern hills
}
for _, f in ipairs(flocks) do
	f.birds = {}
	for i = 1, f.n do
		table.insert(f.birds, {
			body = part({ Name = "Bird", Size = Vector3.new(0.55, 0.45, 1.5), Color = f.color }),
			wl = part({ Name = "Wing", Size = Vector3.new(1.6, 0.1, 0.9), Color = f.color }),
			wr = part({ Name = "Wing", Size = Vector3.new(1.6, 0.1, 0.9), Color = f.color }),
			off = Vector3.new(rng:NextNumber(-9, 9), rng:NextNumber(-4, 4), rng:NextNumber(-9, 9)),
			phase = rng:NextNumber(0, 6.28),
			lag = i * 0.05,
		})
	end
end

local function poseBirds(t, parts, cfs)
	for _, f in ipairs(flocks) do
		for _, b in ipairs(f.birds) do
			local ang = (t - b.lag * 20) * f.w
			local p = f.c + Vector3.new(math.cos(ang) * f.r, math.sin(t * 0.3 + b.phase) * 4, math.sin(ang) * f.r) + b.off
			local ahead = f.c + Vector3.new(math.cos(ang + 0.05 * math.sign(f.w)) * f.r, 0, math.sin(ang + 0.05 * math.sign(f.w)) * f.r) + b.off
			local root = CFrame.lookAt(p, Vector3.new(ahead.X, p.Y, ahead.Z))
			local flap = math.sin(t * 9 + b.phase) * 0.55
			table.insert(parts, b.body); table.insert(cfs, root)
			table.insert(parts, b.wl); table.insert(cfs, root * CFrame.new(-0.25, 0, 0) * CFrame.Angles(0, 0, flap) * CFrame.new(-0.8, 0, 0))
			table.insert(parts, b.wr); table.insert(cfs, root * CFrame.new(0.25, 0, 0) * CFrame.Angles(0, 0, -flap) * CFrame.new(0.8, 0, 0))
		end
	end
end

-- ============ THE JET ============

local JET_PERIOD, JET_RUN, JET_ALT = 125, 60, 470
local jet = Instance.new("Model")
jet.Name = "Jet"
local jetBody = part({ Name = "Fuselage", Shape = Enum.PartType.Cylinder, Size = Vector3.new(44, 5, 5), Color = Color3.fromRGB(245, 245, 248) }, jet)
local trails = {}
local jetParts = {
	{ part({ Name = "Wing", Size = Vector3.new(8, 0.6, 44), Color = Color3.fromRGB(220, 224, 230) }, jet), CFrame.new(1, -0.6, 0) },
	{ part({ Name = "Tail", Size = Vector3.new(6, 7, 0.6), Color = Color3.fromRGB(40, 90, 170) }, jet), CFrame.new(19, 3.5, 0) },
	{ part({ Name = "Stab", Size = Vector3.new(4, 0.5, 14), Color = Color3.fromRGB(220, 224, 230) }, jet), CFrame.new(19, 0.5, 0) },
	{ part({ Name = "Nose", Shape = Enum.PartType.Ball, Size = Vector3.new(5, 5, 5), Color = Color3.fromRGB(245, 245, 248) }, jet), CFrame.new(-22, 0, 0) },
}
for _, zz in ipairs({ -9, 9 }) do
	local eng = part({ Name = "Engine", Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, 2.2, 2.2), Color = Color3.fromRGB(150, 154, 160) }, jet)
	table.insert(jetParts, { eng, CFrame.new(-1, -2, zz) })
	-- contrails: a trail per engine
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(2.5, 0.4, 0); a0.Parent = eng
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(2.5, -0.4, 0); a1.Parent = eng
	local tr = Instance.new("Trail")
	tr.Attachment0, tr.Attachment1 = a0, a1
	tr.Lifetime = 9
	tr.MinLength = 1
	tr.FaceCamera = true
	tr.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 5) })
	tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	tr.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	tr.LightEmission = 0.2
	tr.Enabled = false
	tr.Parent = eng
	table.insert(trails, tr)
end
jet.PrimaryPart = jetBody
jet.Parent = folder
local jetSound = Instance.new("Sound")
jetSound.SoundId = "rbxassetid://9113201092"      -- PSE Atmosphere Formation 2: a big airy rumble, jets overhead
jetSound.Volume = 0.35
jetSound.RollOffMinDistance = 250
jetSound.RollOffMaxDistance = 1600
jetSound.Parent = jetBody
local jetRun = -1
local jetFlying = false

local function poseJet(t, parts, cfs)
	local cycle = math.floor(t / JET_PERIOD)
	local tt = t % JET_PERIOD
	-- contrails only while flying: the jet parks underground between passes,
	-- and a trail left on would draw a streak from under the map to the sky
	local flying = tt < JET_RUN
	if flying ~= jetFlying then
		jetFlying = flying
		if flying then
			task.delay(0.2, function() if jetFlying then for _, tr in ipairs(trails) do tr.Enabled = true end end end)
		else
			for _, tr in ipairs(trails) do tr.Enabled = false; tr:Clear() end
		end
	end
	local root
	if tt < JET_RUN then
		local way = (cycle % 2 == 0) and 1 or -1
		local z = (cycle % 3 == 0) and -260 or 320
		local x = -1800 * way + way * (3600 * tt / JET_RUN)
		-- the model's nose is -X; face the way it flies
		root = CFrame.new(x, JET_ALT + (cycle % 2) * 60, z) * CFrame.Angles(0, (way > 0) and math.pi or 0, 0)
		if jetRun ~= cycle and tt > JET_RUN * 0.3 then
			jetRun = cycle
			jetSound:Play()
		end
	else
		root = CFrame.new(0, -800, 0)
	end
	table.insert(parts, jetBody); table.insert(cfs, root)
	for _, jp in ipairs(jetParts) do table.insert(parts, jp[1]); table.insert(cfs, root * jp[2]) end
end

-- ============ CALTRAIN ============

--[[ Double-deck push-pull, locomotive at the WEST end in both directions
(Caltrain runs that way). The line: a tunnel portal at each end of the
rail bed ValleyGen lays at z = -330; the Mountain View platform is centred
on x = 0 on the north side. Westbound, then eastbound, then quiet. ]]
local RAIL_Z, RAIL_W, RAIL_E, STATION = -330, -915, 648, 0
local CAR, CARS = 58, 6
local TRAIN_Y = 1.4 + 6.5
local V, ACC, DWELL = 36, 9, 9
local PERIOD = 175
local SILVER, RED, GLASS, ROOF = Color3.fromRGB(196, 200, 204), Color3.fromRGB(196, 34, 38), Color3.fromRGB(36, 42, 52), Color3.fromRGB(150, 152, 156)

--[[ v3.4 PHASE W: the Blender-modelled Caltrain (blender/caltrain.py), imported
into ReplicatedStorage.SVMeshes. One MeshPart per car. Modelled with 1 unit =
1 stud, the coach 58 long (= CAR), rail at the bottom of the wheels; the loco
cab faces -X (west, the way it leads), the cab car faces +X. Scaled here by the
coach's own length so any importer unit guess cancels out. If any of the three
is missing the part-built train below is used unchanged. ]]
local RS = game:GetService("ReplicatedStorage")
local MESHES = RS:FindFirstChild("SVMeshes") or RS:WaitForChild("SVMeshes", 2)
local function meshTemplate(name)
	local t = MESHES and MESHES:FindFirstChild(name)
	if t and t:IsA("Model") then
		local only
		for _, d in ipairs(t:GetDescendants()) do
			if d:IsA("BasePart") then if only then return nil end only = d end
		end
		t = only
	end
	return (t and t:IsA("BasePart")) and t or nil
end
local TCAR, TCAB, TLOCO = meshTemplate("Caltrain_Car"), meshTemplate("Caltrain_Cab"), meshTemplate("Caltrain_Loco")
local MESH_TRAIN = TCAR and TCAB and TLOCO
local MESH_BOTTOM = -0.2                           -- wheel bottoms, world y (the part train's bogies sit at -0.1)

local cars = {}
for i = 1, CARS do
	local c = { parts = {} }
	local function add(p, off) table.insert(c.parts, { p, off }) end
	if MESH_TRAIN then
		local t = (i == 1 and TLOCO) or (i == CARS and TCAB) or TCAR
		local k = CAR / TCAR.Size.X
		local p = t:Clone()
		p.Name = (i == 1) and "Loco" or "Coach"
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Size = t.Size * k
		p.Parent = folder
		local ox = 0
		if i == 1 then ox = CAR / 2 - p.Size.X / 2 elseif i == CARS then ox = -CAR / 2 + p.Size.X / 2 end
		-- measured after the import: Roblox brings the FBX in turned 180 degrees
		-- about Y (the cab car's nose arrived at -X, the loco's at +X), so the
		-- two end cars are turned back; the coaches are symmetric
		local turn = (i == 1 or i == CARS) and CFrame.Angles(0, math.pi, 0) or CFrame.new()
		add(p, CFrame.new(ox, MESH_BOTTOM + p.Size.Y / 2 - TRAIN_Y, 0) * turn)
		cars[i] = c
		continue
	end
	add(part({ Name = "Body", Size = Vector3.new(CAR - 2, 13, 9.5), Color = SILVER, Material = Enum.Material.Metal }), CFrame.new())
	add(part({ Name = "Stripe", Size = Vector3.new(CAR - 2.2, 1.3, 9.62), Color = RED }), CFrame.new(0, -3.4, 0))
	add(part({ Name = "WindowsLow", Size = Vector3.new(CAR - 8, 2.2, 9.64), Color = GLASS }), CFrame.new(0, -0.8, 0))
	add(part({ Name = "WindowsHigh", Size = Vector3.new(CAR - 8, 2.2, 9.64), Color = GLASS }), CFrame.new(0, 3.4, 0))
	add(part({ Name = "Roof", Size = Vector3.new(CAR - 2, 0.8, 8.6), Color = ROOF }), CFrame.new(0, 6.8, 0))
	add(part({ Name = "Bogie", Size = Vector3.new(8, 1.6, 8.4), Color = Color3.fromRGB(40, 40, 44) }), CFrame.new(-CAR / 2 + 8, -7.2, 0))
	add(part({ Name = "Bogie", Size = Vector3.new(8, 1.6, 8.4), Color = Color3.fromRGB(40, 40, 44) }), CFrame.new(CAR / 2 - 8, -7.2, 0))
	if i == 1 then
		-- the locomotive: a red nose and a windscreen facing west
		add(part({ Name = "Nose", Size = Vector3.new(3, 9, 9.7), Color = RED }), CFrame.new(-CAR / 2 + 0.5, -1.5, 0))
		add(part({ Name = "Windscreen", Size = Vector3.new(0.4, 2.6, 7), Color = GLASS }), CFrame.new(-CAR / 2 - 1.1, 3, 0))
	elseif i == CARS then
		-- the cab car at the east end
		add(part({ Name = "Cab", Size = Vector3.new(0.4, 2.6, 7), Color = GLASS }), CFrame.new(CAR / 2 - 0.8, 3, 0))
		add(part({ Name = "CabStripe", Size = Vector3.new(0.4, 3, 9.66), Color = RED }), CFrame.new(CAR / 2 - 0.8, -3, 0))
	end
	cars[i] = c
end
local loco = cars[1].parts[1][1]
local trainSound = Instance.new("Sound")
trainSound.SoundId = "rbxassetid://9120251432"    -- PSE Train Horn 2: two horn bursts, then the diesel passes
trainSound.Volume = 0.9
trainSound.RollOffMinDistance = 60
trainSound.RollOffMaxDistance = 900
trainSound.Parent = loco
local trainRun = -1

-- distance travelled along a run with a stop at distance D: cruise, brake, dwell, pull away
local function runDistance(t, D)
	local brake = V * V / (2 * ACC)         -- 72 studs
	local tb = V / ACC                       -- 4 s
	local tA = math.max(0, (D - brake) / V)
	if t < tA then return V * t end
	if t < tA + tb then local u = t - tA; return V * tA + V * u - 0.5 * ACC * u * u end
	if t < tA + tb + DWELL then return D end
	local u = t - tA - tb - DWELL
	if u < tb then return D + 0.5 * ACC * u * u end
	return D + brake + V * (u - tb)
end

local STOP_W = STATION - (CARS / 2) * CAR + CAR / 2      -- west end of the train when it is centred on the platform
local WEST_START_E = RAIL_E + 12                          -- westbound: starts wholly inside the east tunnel
local EAST_START_W = RAIL_W - CARS * CAR - 20             -- eastbound: starts wholly inside the west tunnel

local function trainWestEnd(t)
	local tt = t % PERIOD
	local cycle = math.floor(t / PERIOD)
	if tt < 80 then
		-- westbound: the loco (west end) leads out of the east tunnel
		local s = runDistance(tt, WEST_START_E - STOP_W)
		if trainRun ~= cycle * 2 then trainRun = cycle * 2; trainSound:Play() end
		return WEST_START_E - s, true
	elseif tt >= 88 and tt < 170 then
		local s = runDistance(tt - 88, STOP_W - EAST_START_W)
		if trainRun ~= cycle * 2 + 1 then trainRun = cycle * 2 + 1; trainSound:Play() end
		return EAST_START_W + s, true
	end
	return nil, false
end

local function poseTrain(t, parts, cfs)
	local w, running = trainWestEnd(t)
	for i, c in ipairs(cars) do
		local x = w and (w + (i - 1) * CAR + CAR / 2) or 0
		-- hidden underground between runs and anywhere past a portal (inside the hills)
		local visible = running and x > RAIL_W - CAR and x < RAIL_E + CAR
		local root = visible and CFrame.new(x, TRAIN_Y, RAIL_Z) or CFrame.new(0, -600, 0)
		for _, pp in ipairs(c.parts) do table.insert(parts, pp[1]); table.insert(cfs, root * pp[2]) end
	end
end

-- ============ SOUND ============

local ambience = Instance.new("Sound")
ambience.Name = "ValleyBirds"
ambience.SoundId = "rbxassetid://9112750044"      -- PSE Birds Quiet And Tranquil 1 (Northern California)
ambience.Volume = 0.22
ambience.Looped = true
ambience.Parent = SoundService
ambience:Play()

-- ============ THE LOOP ============

local NEAR = 320           -- people further than this are frozen (too small to read)
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 1 / 30 then return end                -- 30 Hz is plenty for scenery
	local step = acc
	acc = 0
	local t = now()
	local camPos = workspace.CurrentCamera.CFrame.Position
	local parts, cfs = {}, {}
	for _, a in ipairs(agents) do
		a.s += a.way * a.speed * step
		if a.s > a.lane.len then a.s = a.lane.len; a.way = -1 elseif a.s < 0 then a.s = 0; a.way = 1 end
		a.phase += step * a.speed * 1.1
		local pos = a.lane.a + a.lane.dir * a.s
		if (pos - camPos).Magnitude < NEAR then poseAgent(a, parts, cfs) end
	end
	poseBirds(t, parts, cfs)
	poseJet(t, parts, cfs)
	poseTrain(t, parts, cfs)
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end)
