--[[
	HQFloors (v4.0) -- the HQ you can walk through.

	His note: "the floors should also be able to be travelled on, floor 2 3 4
	and 5 look like jewelry storefronts." They looked like display cases because
	they were: full-height glass with rows of lit wooden blocks behind it, and
	nobody could go up there. Now every storey above the lobby is a real floor
	with its own job, reached by a LIFT (a call panel on every floor, a floor
	picker, a short fade), and the top level has a ROOF GARDEN.

	  lobby   the company lobby (CampusArch.dressHQ) + the lift
	  2       ENGINEERING   workstation pods, bookcases, a stand-up table
	  3       DESIGN STUDIO lounges on rugs, work tables with stools, pinboard
	  4       BOARDROOM     a long table under pendants, a wall screen, two glass
	                        meeting rooms
	  5       SKY CAFE      a counter with a coffee bar, stools, round tables
	  roof    ROOF GARDEN   (HQ 5) sofas under the pergola, tables, plants

	Also here, because the building's plan is now a ROUNDED rectangle
	(blender/hq2.py): the box collision is trimmed off the corners and each
	corner gets an arc of invisible wall, so nobody stands outside the glass.

	Called from CampusArch.dressHQ with `add` (a tracked shell part: an HQ
	upgrade rebuilds everything). The lift is server-authoritative: the client
	only asks (LiftGo) and fades the screen.
]]
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local HQFloors = {}

local FK
do
	local ok, m = pcall(function() return require(RS:WaitForChild("FurnitureKit", 5)) end)
	if ok then FK = m end
end

-- the rounded plan's corner radius per level (blender/hq2.py LEVELS)
HQFloors.RADIUS = { [2] = 5, [3] = 7, [4] = 8, [5] = 8 }
HQFloors.LIFT_X = 22
local FLOOR_NAME = { [2] = "ENGINEERING", [3] = "DESIGN STUDIO", [4] = "BOARDROOM", [5] = "SKY CAFE" }
HQFloors.FLOOR_NAME = FLOOR_NAME

local WHITE = Color3.fromRGB(243, 239, 230)
local CHARCOAL = Color3.fromRGB(38, 41, 48)
local METAL = Color3.fromRGB(176, 178, 184)
local OAK = Color3.fromRGB(196, 160, 118)
local WALNUT = Color3.fromRGB(118, 86, 62)
local PANEL = Color3.fromRGB(252, 248, 238)
local LIGHT = Color3.fromRGB(255, 236, 210)

local CS = game:GetService("CollectionService")
-- decor chairs are not seats: StaffRig seats staff on tagged chairs (and turns them)
local function untag(m)
	if m then CS:RemoveTag(m, "SVChair") end
	return m
end
local function put(key, cf, parent, opts)
	if FK and FK.has and FK.has(key) then
		local ok, m = pcall(FK.put, key, cf, parent, opts or {})
		if ok then return untag(m) end
	end
	return nil
end

-- storey slabs the game builds (SiliconCore buildShell: range(16, h - 6, 12))
local function slabsFor(h)
	local t = {}
	if h >= 28 then
		for y = 16, h - 6, 12 do table.insert(t, y) end
	end
	return t
end
HQFloors.slabsFor = slabsFor

-- ============ LIFT REGISTRY + REMOTES ============
HQFloors.lifts = {}          -- [plot.index] = { plot = plot, stops = { {id, name, stand = CFrame, door = Vector3} } }
local liftMenu, liftGo
local lastGo = {}

local function initRemotes()
	if liftMenu then return end
	local folder = RS:FindFirstChild("SVRemotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "SVRemotes"
		folder.Parent = RS
	end
	liftMenu = folder:FindFirstChild("LiftMenu") or Instance.new("RemoteEvent")
	liftMenu.Name = "LiftMenu"
	liftMenu.Parent = folder
	liftGo = folder:FindFirstChild("LiftGo") or Instance.new("RemoteEvent")
	liftGo.Name = "LiftGo"
	liftGo.Parent = folder
	liftGo.OnServerEvent:Connect(function(player, plotIndex, stopId)
		if typeof(plotIndex) ~= "number" or typeof(stopId) ~= "string" then return end
		local reg = HQFloors.lifts[plotIndex]
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not reg or not root then return end
		if player:GetAttribute("Carrying") then return end
		if (lastGo[player] or 0) > os.clock() - 1.2 then return end
		-- the player must be standing at one of THIS building's lifts
		local near, dest = false, nil
		for _, st in ipairs(reg.stops) do
			if (st.stand.Position - root.Position).Magnitude < 16 then near = true end
			if st.id == stopId then dest = st end
		end
		if not near or not dest then return end
		lastGo[player] = os.clock()
		task.delay(0.28, function()
			if player.Character == char and char.Parent then
				char:PivotTo(dest.stand + Vector3.new(0, 3, 0))
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(p) lastGo[p] = nil end)
end

-- ============ SMALL BUILDERS ============
local function panelLight(add, g, x, y, z, w, d)
	return add({ Name = "LightPanel", Size = Vector3.new(w or 5, 0.12, d or 1.6), CFrame = g(x, y, z), Color = PANEL,
		Material = Enum.Material.SmoothPlastic, CastShadow = false, CanCollide = false, CanQuery = false })
end

local function lamp(add, g, x, y, z, range, bright)
	local p = add({ Name = "LampPoint", Size = Vector3.new(0.4, 0.4, 0.4), CFrame = g(x, y, z), Transparency = 1,
		CanCollide = false, CanQuery = false, CastShadow = false })
	local l = Instance.new("PointLight")
	l.Range = range or 30
	l.Brightness = bright or 0.8
	l.Color = LIGHT
	l.Shadows = false
	l.Parent = p
	return p
end

local function wallSign(add, g, x, y, z, w, text, sub)
	local board = add({ Name = "FloorSign", Size = Vector3.new(w, 1.6, 0.2), CFrame = g(x, y, z), Color = CHARCOAL,
		CanCollide = false, CanQuery = false, CastShadow = false })
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0
	sg.MaxDistance = 90
	sg.Parent = board
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(0.94, 0, 0.8, 0)
	t.Position = UDim2.new(0.03, 0, 0.1, 0)
	t.TextScaled = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold)
	t.TextColor3 = WHITE
	t.RichText = true
	t.Text = sub and (text .. '  <font color="#FFD046">' .. sub .. "</font>") or text
	t.Parent = sg
	return board
end

-- invisible wall
local function wall(add, cf, size)
	return add({ Name = "FloorWall", Size = size, CFrame = cf, Transparency = 1, CanQuery = false, CanTouch = false,
		CastShadow = false })
end

--[[ The envelope of one storey (y0..y1) on a rounded plan: four straights
inset 0.6 from the square line, and an arc of 5 panels at each corner.
`frontGap` leaves the lobby entrance open. ]]
local function envelope(add, g, w, d, R, y0, y1, frontGap)
	local hw, hd, H = w / 2, d / 2, y1 - y0
	local cy = y0 + H / 2
	local t, IN = 1, 0.9
	-- sides and back
	wall(add, g(-(hw - IN + t / 2), cy, 0), Vector3.new(t, H, d - 2 * R + 0.4))
	wall(add, g(hw - IN + t / 2, cy, 0), Vector3.new(t, H, d - 2 * R + 0.4))
	wall(add, g(0, cy, -(hd - IN + t / 2)), Vector3.new(w - 2 * R + 0.4, H, t))
	if frontGap then
		local seg = (hw - R) - frontGap
		if seg > 0.2 then
			for _, sx in ipairs({ -1, 1 }) do
				wall(add, g(sx * (frontGap + seg / 2), cy, hd - IN + t / 2), Vector3.new(seg + 0.4, H, t))
			end
		end
	else
		wall(add, g(0, cy, hd - IN + t / 2), Vector3.new(w - 2 * R + 0.4, H, t))
	end
	-- corners
	local r = R - IN + t / 2
	for _, c in ipairs({ { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }) do
		local ox, oz = c[1] * (hw - R), c[2] * (hd - R)
		local base = math.atan2(c[2], c[1])
		for k = 0, 4 do
			local a = base - math.rad(45) + math.rad(90) * (k + 0.5) / 5
			local px, pz = ox + math.cos(a) * r, oz + math.sin(a) * r
			local len = 2 * r * math.sin(math.rad(9)) + 0.5
			wall(add, g(px, cy, pz) * CFrame.Angles(0, -a, 0), Vector3.new(t, H, len))
		end
	end
end

HQFloors.envelope = envelope

-- ============ THE LIFT ============
--[[ A lift core against the back wall: brushed doors in a charcoal frame, a
lit call button, the floor's name over the doors. The prompt opens the floor
picker; the stop's `stand` is just in front of the doors. ]]
local function liftDoors(add, g, y, h, d, label, sub, stops, stopId, plotIndex)
	local X = HQFloors.LIFT_X
	local zBack = -d / 2 + 0.6
	local depth = 2.4
	local H = math.min(h, 12)
	local core = add({ Name = "LiftCore", Size = Vector3.new(10, H, depth), CFrame = g(X, y + H / 2, zBack + depth / 2), Color = WHITE })
	local zf = zBack + depth
	local DH = math.min(7.9, H - 0.8)
	add({ Name = "LiftFrame", Size = Vector3.new(5.6, DH + 0.5, 0.3), CFrame = g(X, y + (DH + 0.5) / 2, zf + 0.05), Color = CHARCOAL, CanCollide = false })
	for _, sx in ipairs({ -1, 1 }) do
		add({ Name = "LiftDoor", Size = Vector3.new(2.4, DH, 0.2), CFrame = g(X + sx * 1.22, y + DH / 2, zf + 0.22), Color = METAL,
			Material = Enum.Material.Metal, CanCollide = false })
	end
	local btn = add({ Name = "LiftButton", Size = Vector3.new(0.5, 0.9, 0.2), CFrame = g(X + 3.6, y + 4.3, zf + 0.12), Color = CHARCOAL, CanCollide = false })
	add({ Name = "LiftButtonLit", Shape = Enum.PartType.Ball, Size = Vector3.new(0.3, 0.3, 0.3), CFrame = g(X + 3.6, y + 4.3, zf + 0.25),
		Color = Color3.fromRGB(255, 208, 70), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
	if H >= 10.5 then
		wallSign(add, g, X, y + 9.4, zf + 0.12, 8, label, sub)
	else
		wallSign(add, g, X - 8.2, y + 4.6, -d / 2 + 0.95, 6, label, sub)
	end
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Take the lift"
	pp.ObjectText = sub or label
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 11
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.Parent = btn
	pp.Triggered:Connect(function(player)
		if player:GetAttribute("Carrying") then
			liftMenu:FireClient(player, { blocked = "Drop off your recruit first" })
			return
		end
		local list = {}
		for _, st in ipairs(stops) do table.insert(list, { id = st.id, name = st.name, sub = st.sub }) end
		liftMenu:FireClient(player, { plot = plotIndex, here = stopId, stops = list })
	end)
	table.insert(stops, { id = stopId, name = label, sub = sub, stand = g(X, y + 0.1, zf + 3.2) * CFrame.Angles(0, math.pi, 0) })
	return core
end

-- ============ FLOORS ============
local function floorFinish(add, g, w, d, R, y, color, material)
	-- a rounded finish: a centre slab plus the two end strips inside the corners
	add({ Name = "FloorFinish", Size = Vector3.new(w - 1.6, 0.06, d - 2 * R), CFrame = g(0, y + 0.03, 0), Color = color, Material = material,
		CastShadow = false, CanQuery = false })
	for _, sz in ipairs({ -1, 1 }) do
		add({ Name = "FloorFinish", Size = Vector3.new(w - 2 * R, 0.06, R - 0.8), CFrame = g(0, y + 0.03, sz * (d / 2 - R / 2 - 0.4)),
			Color = color, Material = material, CastShadow = false, CanQuery = false })
	end
end

local function ceiling(add, g, w, d, y, meshed)
	if not meshed then
		add({ Name = "Ceiling", Size = Vector3.new(w - 6, 0.2, d - 6), CFrame = g(0, y - 0.1, 0), Color = Color3.fromRGB(238, 236, 230),
			CastShadow = false, CanQuery = false, CanCollide = false })
	end
	for _, x in ipairs({ -w / 4, 0, w / 4 }) do
		for _, z in ipairs({ -d / 5, d / 5 }) do
			panelLight(add, g, x, y - 0.26, z, 6, 1.8)
		end
	end
end

local function engineering(add, g, anchor, w, d, top)
	local hw, hd = w / 2, d / 2
	-- pods of four: two desks facing two, in two rows; clear of the lift (x 15..29, back)
	local xs = {}
	local x = -hw + 12
	while x < hw - 10 do
		table.insert(xs, x)
		x += (w >= 84) and 18 or 15
	end
	for _, px in ipairs(xs) do
		for _, pz in ipairs({ -3, 11 }) do
			if FK and FK.workstation then
				for _, o in ipairs({ { -2.3, -1.6, 180 }, { 2.3, -1.6, 180 }, { -2.3, 1.6, 0 }, { 2.3, 1.6, 0 } }) do
					local ok, made = pcall(FK.workstation, g(0, 0, 0), px + o[1], pz + o[2], top, anchor, { yaw = o[3] })
					if ok and made then untag(made.chair) end
				end
			end
		end
	end
	-- bookcases along the side walls, plants at the ends
	for _, sx in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -8, -5.5, 14, 16.5 }) do
			put("bookcaseClosedDoors", g(sx * (hw - 2), top, z), anchor, { yaw = sx * -90 })
		end
		put("pottedPlant", g(sx * (hw - 3), top, 4), anchor)
	end
	-- a stand-up table by the front glass
	add({ Name = "StandTable", Size = Vector3.new(10, 0.3, 2.4), CFrame = g(-8, top + 3.6, hd - 5), Color = OAK, Material = Enum.Material.WoodPlanks })
	add({ Name = "StandLeg", Size = Vector3.new(0.4, 3.5, 1.6), CFrame = g(-12, top + 1.75, hd - 5), Color = CHARCOAL })
	add({ Name = "StandLeg", Size = Vector3.new(0.4, 3.5, 1.6), CFrame = g(-4, top + 1.75, hd - 5), Color = CHARCOAL })
end

local function rug(add, g, x, y, z, sx, sz, color)
	add({ Name = "Rug", Size = Vector3.new(sx, 0.05, sz), CFrame = g(x, y + 0.08, z), Color = color, Material = Enum.Material.Fabric,
		CastShadow = false, CanCollide = false, CanQuery = false })
end

local function design(add, g, anchor, w, d, top, ceil)
	local hw, hd = w / 2, d / 2
	-- two lounges on rugs
	for i, lx in ipairs({ -hw + 14, hw - 16 }) do
		local lz = 6
		rug(add, g, lx, top, lz, 12, 10, i == 1 and Color3.fromRGB(214, 110, 96) or Color3.fromRGB(92, 132, 180))
		put("loungeDesignSofa", g(lx, top, lz - 3.4), anchor, { yaw = 0 })
		put("loungeDesignSofa", g(lx, top, lz + 3.4), anchor, { yaw = 180 })
		add({ Name = "CoffeeTable", Size = Vector3.new(4, 0.3, 2.2), CFrame = g(lx, top + 1.3, lz), Color = OAK, Material = Enum.Material.WoodPlanks })
		add({ Name = "CoffeeTableBase", Size = Vector3.new(3.2, 1.1, 1.4), CFrame = g(lx, top + 0.6, lz), Color = CHARCOAL })
		put("lampSquareFloor", g(lx + 5, top, lz - 3.6), anchor)
		put("pottedPlant", g(lx - 5.2, top, lz + 3.8), anchor)
	end
	-- work tables with stools down the middle
	for _, tx in ipairs({ -8, 4 }) do
		for _, tz in ipairs({ -6, 2 }) do
			put("tableCross", g(tx, top, tz), anchor, { canCollide = true })
			for _, o in ipairs({ { -1.4, 1.7, 180 }, { 1.4, 1.7, 180 }, { -1.4, -1.7, 0 }, { 1.4, -1.7, 0 } }) do
				put("stoolBar", g(tx + o[1], top, tz + o[2]), anchor, { yaw = o[3] })
			end
		end
	end
	-- a pinboard wall with sketches (colored cards), free-standing
	local bx, bz = -hw + 22, -hd + 4
	add({ Name = "Pinboard", Size = Vector3.new(12, 6, 0.4), CFrame = g(bx, top + 4, bz), Color = Color3.fromRGB(210, 186, 150),
		Material = Enum.Material.Fabric })
	add({ Name = "PinboardFoot", Size = Vector3.new(12.4, 0.6, 1.6), CFrame = g(bx, top + 0.3, bz), Color = CHARCOAL })
	local rng = Random.new(3)
	local cols = { Color3.fromRGB(255, 208, 70), Color3.fromRGB(240, 110, 80), Color3.fromRGB(92, 170, 230), Color3.fromRGB(250, 250, 244), Color3.fromRGB(120, 196, 120) }
	for k = 1, 16 do
		local cx, cy = rng:NextNumber(-5.2, 5.2), rng:NextNumber(-2.2, 2.2)
		add({ Name = "Sketch", Size = Vector3.new(rng:NextNumber(1, 1.8), rng:NextNumber(0.8, 1.4), 0.06),
			CFrame = g(bx + cx, top + 4 + cy, bz + 0.23) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-8, 8))),
			Color = cols[rng:NextInteger(1, #cols)], CastShadow = false, CanCollide = false, CanQuery = false })
	end
	for _, sx in ipairs({ -1, 1 }) do
		put("bookcaseClosedDoors", g(sx * (hw - 2), top, -6), anchor, { yaw = sx * -90 })
		put("bookcaseClosedDoors", g(sx * (hw - 2), top, -3.6), anchor, { yaw = sx * -90 })
	end
end

local function boardroom(add, g, anchor, w, d, top, ceil)
	local hw, hd = w / 2, d / 2
	-- the long table under three pendants
	local tz = 4
	add({ Name = "BoardTable", Size = Vector3.new(22, 0.4, 5.4), CFrame = g(-6, top + 2.4, tz), Color = WALNUT, Material = Enum.Material.WoodPlanks })
	for _, lx in ipairs({ -14, 2 }) do
		add({ Name = "BoardLeg", Size = Vector3.new(1, 2.2, 3.6), CFrame = g(lx, top + 1.1, tz), Color = CHARCOAL })
	end
	for k = 0, 4 do
		local cx = -15 + k * 4.5
		put("chairModernCushion", g(cx, top, tz - 3.6), anchor, { yaw = 0 })
		put("chairModernCushion", g(cx, top, tz + 3.6), anchor, { yaw = 180 })
	end
	put("chairModernCushion", g(-18.8, top, tz), anchor, { yaw = 90 })
	for _, px in ipairs({ -13, -6, 1 }) do
		add({ Name = "PendantCord", Size = Vector3.new(0.08, ceil - top - 6.2, 0.08), CFrame = g(px, top + 6.2 + (ceil - top - 6.2) / 2, tz),
			Color = CHARCOAL, CanCollide = false, CastShadow = false, CanQuery = false })
		add({ Name = "Pendant", Size = Vector3.new(2.2, 0.5, 2.2), Shape = Enum.PartType.Cylinder, CFrame = g(px, top + 6.0, tz) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(255, 226, 170), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, CanQuery = false })
	end
	-- the wall screen at the table's head: a quarterly chart
	local screen = add({ Name = "BoardScreen", Size = Vector3.new(10, 5.6, 0.3), CFrame = g(-6, top + 5.2, -hd + 4.2), Color = Color3.fromRGB(20, 24, 32) })
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 24
	sg.LightInfluence = 0
	sg.MaxDistance = 80
	sg.Parent = screen
	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(18, 24, 38)
	bg.Parent = sg
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(0.9, 0, 0.16, 0)
	title.Position = UDim2.new(0.05, 0, 0.05, 0)
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold)
	title.TextColor3 = Color3.fromRGB(240, 240, 236)
	title.Text = "REVENUE  ·  THIS YEAR"
	title.Parent = bg
	for k, v in ipairs({ 0.22, 0.3, 0.38, 0.5, 0.62, 0.8 }) do
		local b = Instance.new("Frame")
		b.AnchorPoint = Vector2.new(0, 1)
		b.Position = UDim2.new(0.07 + (k - 1) * 0.145, 0, 0.9, 0)
		b.Size = UDim2.new(0.1, 0, v * 0.65, 0)
		b.BorderSizePixel = 0
		b.BackgroundColor3 = k == 6 and Color3.fromRGB(255, 208, 70) or Color3.fromRGB(70, 150, 255)
		b.Parent = bg
	end
	add({ Name = "ScreenStand", Size = Vector3.new(0.6, 2.4, 0.6), CFrame = g(-6, top + 1.2, -hd + 4.2), Color = CHARCOAL })
	-- two glass meeting rooms on the other side
	for i, mx in ipairs({ hw - 12, hw - 26 }) do
		local mz = 10
		local W, D, H = 12, 10, math.min(ceil - top, 9)
		for _, sz in ipairs({ -1, 1 }) do
			add({ Name = "MeetGlass", Size = Vector3.new(W, H, 0.2), CFrame = g(mx, top + H / 2, mz + sz * D / 2), Color = Color3.fromRGB(190, 214, 224),
				Material = Enum.Material.Glass, Transparency = 0.6, CastShadow = false })
		end
		for _, sx in ipairs({ -1, 1 }) do
			local len = sx == -1 and D or D - 4
			add({ Name = "MeetGlass", Size = Vector3.new(0.2, H, len), CFrame = g(mx + sx * W / 2, top + H / 2, mz + (sx == 1 and 2 or 0)),
				Color = Color3.fromRGB(190, 214, 224), Material = Enum.Material.Glass, Transparency = 0.6, CastShadow = false })
			add({ Name = "MeetFrame", Size = Vector3.new(0.3, 0.3, D), CFrame = g(mx + sx * W / 2, top + H, mz), Color = CHARCOAL, CanCollide = false })
		end
		put("tableRound", g(mx, top, mz), anchor, { canCollide = true })
		for _, o in ipairs({ { 0, 2.6, 180 }, { 0, -2.6, 0 }, { 2.4, 0, -90 }, { -2.4, 0, 90 } }) do
			put("chairModernCushion", g(mx + o[1], top, mz + o[2]), anchor, { yaw = o[3] })
		end
		wallSign(add, g, mx, top + H - 1.2, mz + D / 2 + 0.2, 5, i == 1 and "ROOM A" or "ROOM B")
	end
	for _, sx in ipairs({ -1, 1 }) do
		put("pottedPlant", g(sx * (hw - 3), top, -6), anchor)
		put("pottedPlant", g(sx * (hw - 3), top, hd - 6), anchor)
	end
end

local function cafe(add, g, anchor, w, d, top, ceil)
	local hw, hd = w / 2, d / 2
	-- the counter run on the left, the coffee bar on it
	local cx0 = -hw + 8
	for k = 0, 6 do
		put("kitchenBar", g(cx0 + k * 2.53, top, -hd + 5), anchor, { canCollide = true })
	end
	put("kitchenCoffeeMachine", g(cx0 + 2.6, top + 2.47, -hd + 5), anchor)
	put("kitchenCoffeeMachine", g(cx0 + 5.2, top + 2.47, -hd + 5), anchor)
	put("kitchenMicrowave", g(cx0 + 10.2, top + 2.47, -hd + 5), anchor)
	put("kitchenFridge", g(cx0 + 17.8, top, -hd + 4.6), anchor)
	for k = 0, 4 do
		put("stoolBar", g(cx0 + 1.3 + k * 3.1, top, -hd + 7.4), anchor, { yaw = 180 })
	end
	-- a window bar along the front glass with stools
	add({ Name = "WindowBar", Size = Vector3.new(w * 0.5, 0.3, 1.6), CFrame = g(0, top + 3.4, hd - 2.6), Color = OAK, Material = Enum.Material.WoodPlanks })
	for x = -w * 0.22, w * 0.22, 3.4 do
		put("stoolBar", g(x, top, hd - 4.6), anchor, { yaw = 0 })
	end
	-- round tables
	for _, p in ipairs({ { -14, 6 }, { -2, 8 }, { 10, 6 }, { hw - 12, -2 } }) do
		put("tableRound", g(p[1], top, p[2]), anchor, { canCollide = true })
		for _, o in ipairs({ { 0, 2.6, 180 }, { 2.3, -1.3, -60 }, { -2.3, -1.3, 60 } }) do
			put("chairModernCushion", g(p[1] + o[1], top, p[2] + o[2]), anchor, { yaw = o[3] })
		end
	end
	for _, px in ipairs({ -14, -2, 10 }) do
		add({ Name = "PendantCord", Size = Vector3.new(0.08, ceil - top - 5.6, 0.08), CFrame = g(px, top + 5.6 + (ceil - top - 5.6) / 2, 6),
			Color = CHARCOAL, CanCollide = false, CastShadow = false, CanQuery = false })
		add({ Name = "Pendant", Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 1.2), CFrame = g(px, top + 5.4, 6),
			Color = Color3.fromRGB(255, 226, 170), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, CanQuery = false })
	end
	for _, sx in ipairs({ -1, 1 }) do
		put("pottedPlant", g(sx * (hw - 3), top, 10), anchor)
		put("pottedPlant", g(sx * (hw - 3), top, -2), anchor)
	end
end

local function roofGarden(add, g, anchor, w, d, deck)
	local hw, hd = w / 2, d / 2
	-- the pergola lounge (hq2.py: pergola centred at game x -20, z 2)
	rug(add, g, -20, deck, 2, 13, 9, Color3.fromRGB(230, 220, 200))
	put("loungeDesignSofa", g(-20, deck, -1.6), anchor, { yaw = 0 })
	put("loungeDesignSofa", g(-20, deck, 5.8), anchor, { yaw = 180 })
	add({ Name = "CoffeeTable", Size = Vector3.new(4, 0.3, 2.2), CFrame = g(-20, deck + 1.3, 2.1), Color = OAK, Material = Enum.Material.WoodPlanks })
	add({ Name = "CoffeeTableBase", Size = Vector3.new(3.2, 1.1, 1.4), CFrame = g(-20, deck + 0.6, 2.1), Color = CHARCOAL })
	-- tables in the sun on the other side
	for _, p in ipairs({ { 6, 6 }, { 16, 0 }, { 30, 6 } }) do
		put("tableRound", g(p[1], deck, p[2]), anchor, { canCollide = true })
		for _, o in ipairs({ { 0, 2.6, 180 }, { 2.3, -1.3, -60 }, { -2.3, -1.3, 60 } }) do
			put("chairModernCushion", g(p[1] + o[1], deck, p[2] + o[2]), anchor, { yaw = o[3] })
		end
	end
	for _, p in ipairs({ { -34, 12 }, { -6, 14 }, { 38, 12 } }) do
		put("pottedPlant", g(p[1], deck, p[2]), anchor, { scale = 1.4 })
	end
	-- the garden's edge: invisible rail following the glass balustrade (hq2.py rail plan)
	return hw, hd
end

--[[ build(add, g, level, w, d, h, shell, plot)
	add   = tracked-part constructor (rebuilt with the HQ)
	shell = the HQ's part list (the old box collision is trimmed here) ]]
function HQFloors.build(add, g, level, w, d, h, shell, plot)
	initRemotes()
	if level < 2 then return end
	local R = HQFloors.RADIUS[level] or 6
	local hw, hd = w / 2, d / 2
	local slabs = slabsFor(h)
	local anchor = add({ Name = "FloorsAnchor", Size = Vector3.new(1, 1, 1), CFrame = g(0, -8, 0), Transparency = 1,
		CanCollide = false, CanQuery = false, CastShadow = false })

	-- is the rounded architecture (hq2.py) in? then the square visuals go
	local lib = RS:FindFirstChild("SVMeshes")
	local meshed = lib and lib:FindFirstChild("HQv2_" .. level .. "_Shell") ~= nil

	-- 1. the square box collision comes off the rounded corners
	for _, p in ipairs(shell) do
		if p.Name == "WallL" or p.Name == "WallR" or p.Name == "SideGlass" then
			p.Size = Vector3.new(p.Size.X, p.Size.Y, math.max(1, d - 2 * R))
		elseif p.Name == "WallBack" or p.Name == "EntranceHeader" then
			p.Size = Vector3.new(math.max(1, w - 2 * R), p.Size.Y, p.Size.Z)
		elseif p.Name == "FrontGlass" or p.Name == "FrontWall" then
			local rel = plot and plot.pivot:PointToObjectSpace(p.Position) or Vector3.zero
			local sx = rel.X >= 0 and 1 or -1
			local inner, outer = 7, hw - R
			p.Size = Vector3.new(math.max(1, outer - inner), p.Size.Y, p.Size.Z)
			p.CFrame = g(sx * (inner + (outer - inner) / 2), rel.Y, rel.Z)
		elseif meshed and p.Name == "StoreyBand" then
			-- the mesh draws a rounded floor plate; the square band stays as the floor you stand on
			p.Transparency = 1
			p.CastShadow = false
		elseif meshed and p.Name == "Ceiling" then
			p.Transparency = 1
			p.CanCollide = false
		end
	end
	-- the lobby floor on a rounded plan: a cross of two slabs and four corner discs
	if meshed then
		for _, p in ipairs(shell) do
			if p.Name == "GarageFloor" then
				p.Size = Vector3.new(w, p.Size.Y, math.max(1, d - 2 * R))
				add({ Name = "FloorPlate", Size = Vector3.new(math.max(1, w - 2 * R), p.Size.Y, d), CFrame = p.CFrame,
					Color = p.Color, Material = p.Material })
				for _, c in ipairs({ { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }) do
					add({ Name = "FloorCorner", Shape = Enum.PartType.Cylinder, Size = Vector3.new(p.Size.Y, 2 * R, 2 * R),
						CFrame = g(c[1] * (hw - R), p.Size.Y / 2, c[2] * (hd - R)) * CFrame.Angles(0, 0, math.rad(90)),
						Color = p.Color, Material = p.Material })
				end
				break
			end
		end
	end

	-- 2. the lobby: corner arcs, ceiling light (the neon strips go), the lift
	local lobbyTop = slabs[1] and (slabs[1] - 0.6) or (h - 0.5)
	envelope(add, g, w, d, R, 1.0, lobbyTop, 7)
	for _, p in ipairs(shell) do
		if p.Name == "CeilingLight" then
			p.Material = Enum.Material.SmoothPlastic
			p.Color = PANEL
		end
	end
	lamp(add, g, 0, lobbyTop - 2, 0, 44, 0.7)

	if #slabs == 0 then return end
	local stops = {}
	local index = plot and plot.index or 0
	HQFloors.lifts[index] = { plot = plot, stops = stops }
	liftDoors(add, g, 1.0, lobbyTop - 1.0, d, "LOBBY", nil, stops, "L", index)

	-- 3. every storey above the lobby
	for i, s in ipairs(slabs) do
		local n = i + 1
		local top = s + 0.6
		local ceil = (slabs[i + 1] and (slabs[i + 1] - 0.6)) or (h - 0.5)
		-- the floor that tops out the building is always a floor you'd want to reach
		local theme = n
		if level == 4 and n == 3 then theme = 3 end
		envelope(add, g, w, d, R, top, ceil, nil)
		local fin = ({ [2] = { Color3.fromRGB(74, 82, 98), Enum.Material.Fabric },
			[3] = { OAK, Enum.Material.WoodPlanks },
			[4] = { Color3.fromRGB(150, 118, 92), Enum.Material.WoodPlanks },
			[5] = { Color3.fromRGB(176, 168, 156), Enum.Material.Marble } })[theme]
		floorFinish(add, g, w, d, R, top, fin[1], fin[2])
		ceiling(add, g, w, d, ceil, meshed)
		lamp(add, g, 0, ceil - 1.6, 0, 42, 0.6)
		liftDoors(add, g, top, ceil - top, d, tostring(n), FLOOR_NAME[theme], stops, "F" .. n, index)
		local ok, err = pcall(function()
			if theme == 2 then engineering(add, g, anchor, w, d, top)
			elseif theme == 3 then design(add, g, anchor, w, d, top, ceil)
			elseif theme == 4 then boardroom(add, g, anchor, w, d, top, ceil)
			elseif theme == 5 then cafe(add, g, anchor, w, d, top, ceil) end
		end)
		if not ok then warn("[SV] HQ floor " .. n .. " failed: " .. tostring(err)) end
	end

	-- 4. the roof garden (HQ 5): its floor is the Parapet block (top h + 1.6)
	if level >= 5 then
		local deck = h + 1.6
		local over = 2.2
		-- the glass balustrade (hq2.py rail plan: half-size + over - 1.2, radius R + over - 1.2)
		local rw, rd, rr = w + 2 * (over - 1.2), d + 2 * (over - 1.2), R + over - 1.2
		envelope(add, g, rw + 1.2, rd + 1.2, rr + 0.6, deck, deck + 4.5, nil)
		-- the lift core on the roof is solid (hq2.py: game x 22, z -hd + 7, 10 x 8)
		add({ Name = "RoofCore", Size = Vector3.new(10, 9, 8), CFrame = g(HQFloors.LIFT_X, deck + 4.5, -hd + 7), Transparency = 1,
			CanQuery = false, CastShadow = false })
		local btn = add({ Name = "LiftButton", Size = Vector3.new(0.5, 0.9, 0.2), CFrame = g(HQFloors.LIFT_X + 3.4, deck + 4.3, -hd + 11.12),
			Color = CHARCOAL, CanCollide = false })
		add({ Name = "LiftButtonLit", Shape = Enum.PartType.Ball, Size = Vector3.new(0.3, 0.3, 0.3), CFrame = g(HQFloors.LIFT_X + 3.4, deck + 4.3, -hd + 11.25),
			Color = Color3.fromRGB(255, 208, 70), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
		local pp = Instance.new("ProximityPrompt")
		pp.ActionText = "Take the lift"
		pp.ObjectText = "ROOF GARDEN"
		pp.HoldDuration = 0
		pp.MaxActivationDistance = 11
		pp.RequiresLineOfSight = false
		pp.Parent = btn
		pp.Triggered:Connect(function(player)
			if player:GetAttribute("Carrying") then
				liftMenu:FireClient(player, { blocked = "Drop off your recruit first" })
				return
			end
			local list = {}
			for _, st in ipairs(stops) do table.insert(list, { id = st.id, name = st.name, sub = st.sub }) end
			liftMenu:FireClient(player, { plot = index, here = "R", stops = list })
		end)
		table.insert(stops, { id = "R", name = "R", sub = "ROOF GARDEN", stand = g(HQFloors.LIFT_X, deck + 0.1, -hd + 14) * CFrame.Angles(0, math.pi, 0) })
		pcall(roofGarden, add, g, anchor, w, d, deck)
	end
end

return HQFloors
