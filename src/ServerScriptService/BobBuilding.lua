--[[
	BobBuilding -- ModuleScript in ServerScriptService. P-5, Bob the first boss investor (25 Oct 2026).

	Spec: docs/superpowers/specs/2026-10-25-bob-first-boss-investor-design.md (3b, 3c, 3f).

	  BOB CAPITAL   a real building next door to The Residences (every player drives there
	                for the HQ 2 task, so everyone passes it early). Its door is taped shut
	                for the whole server; the player who beat Bob sees it open on their own
	                client only (BobDoorClient). Inside is the boardroom both cutscenes use.
	  BobCast       ReplicatedStorage templates the client clones for the cutscenes: Bob
	                (suit, belly, sunglasses, a GOLD TOOTHPICK, never tobacco), two investors,
	                and the REVENUE chart board.
	  trophy(plot)  BOB'S TOOTHPICK on a stand, for a save that beat him (everyone sees it).

	Anchors (attributes on the model, CFrames; BobScript's coordinates are relative to them):
	  AnchorBoard   the middle of the boardroom floor, -Z into the room (the camera side is +Z)
	  AnchorDoor    on the sidewalk at the front door, -Z into the building
	  AnchorStreet  a clear stretch of pavement beside it, -Z away from the road
]]

local CollectionService = game:GetService("CollectionService")
local RS = game:GetService("ReplicatedStorage")

local BobBuilding = {}

local Pal = require(RS:WaitForChild("PaletteLoad"))
local LINES = require(RS:WaitForChild("BobScript")).LINES

-- the building's frame: beside The Residences, front (+Z) facing the park like it (Downtown.RES)
BobBuilding.SIZE = { w = 30, d = 24, h = 30, room = 12 }
function BobBuilding.site()
	local Downtown = require(script.Parent:WaitForChild("Downtown"))
	return Downtown.RES * CFrame.new(65, 0, 4)   -- east of it: the kick throws you away from The Residences, not into it
end

local CHARCOAL = Color3.fromRGB(38, 41, 48)
local NAVY = Color3.fromRGB(38, 66, 108)
local STONE = Color3.fromRGB(196, 186, 170)
local GLASS = Color3.fromRGB(132, 172, 190)
local GOLD = Color3.fromRGB(224, 182, 90)
local OAK = Color3.fromRGB(192, 138, 85)
local DOORWOOD = Color3.fromRGB(110, 74, 48)
local TAPE = Color3.fromRGB(255, 200, 61)
local PAPER = Color3.fromRGB(243, 239, 230)
local RED = Color3.fromRGB(198, 72, 62)
local WALNUT = Color3.fromRGB(92, 60, 40)
local CEILING = Color3.fromRGB(232, 226, 214)
local RUG = Color3.fromRGB(120, 36, 44)
local DEVICE = Color3.fromRGB(28, 30, 36)

-- props.Keep = true: a boardroom piece whose colour IS the point (walnut, the red rug, a dark screen);
-- the palette would pull it to the world's tans, so it takes the palette's stated exemption instead
local function part(parent, props)
	local keep = props.Keep
	props.Keep = nil
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.CastShadow = false
	for k, v in pairs(props) do p[k] = v end
	if keep then CollectionService:AddTag(p, "SVNoPalette") elseif Pal then Pal.author(p, props) end
	p.Parent = parent
	return p
end

local function label(p, face, text, color, size)
	local g = Instance.new("SurfaceGui")
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.FredokaOne
	t.Text = text
	t.TextColor3 = color
	t.TextScaled = true
	if size then
		local c = Instance.new("UITextSizeConstraint")
		c.MaxTextSize = size
		c.Parent = t
	end
	t.Parent = g
	g.Parent = p
	return g
end

-- ------------------------------------------------------------------ the AI kit
--[[ 25 Oct (Luke: "everything is just so bad", "let's do these steps with AI"): Studio's mesh
	generator made Bob, two investors and the boardroom props. They live in the place itself, in
	ReplicatedStorage (Rojo leaves that folder's unknown children alone):
	  BobModel                 Bob (take C + a long tie). Luke may replace it with his own rig.
	  BobKit.Inv1 / Inv2       the two investors
	  BobKit.Table / Portrait / Safe / Plant
	A missing piece is simply not used: the old parts stand in, nothing breaks. ]]
local function kitPiece(name)
	local kit = RS:FindFirstChild("BobKit")
	return kit and kit:FindFirstChild(name)
end
-- clone a kit model, scale it, turn it (degrees), stand it with its base on cf
local function placeKit(name, parent, cf, scale, yaw)
	local src = kitPiece(name)
	if not src then return nil end
	local m = src:Clone()
	if scale and scale ~= 1 then m:ScaleTo(m:GetScale() * scale) end
	local box, size = m:GetBoundingBox()
	local base = cf * CFrame.Angles(0, math.rad(yaw or 0), 0)
	m:PivotTo(base * CFrame.new(0, size.Y / 2, 0) * box:Inverse() * m:GetPivot())
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CastShadow = true end
	end
	m.Parent = parent
	return m
end

-- ------------------------------------------------------------------ the boardroom's dressing
--[[ 25 Oct (Luke: "the room looks like a set ... a baseplate with a plain blue wall and nothing above
	it"): a real office. Wood panelling to rail height round three walls, a light ceiling with light
	panels, a rug under the table, bookcases, a display cabinet, a lamp, a wall screen with a ticker,
	and a city skyline in the window instead of a glowing panel. Flat pieces are either solid (the rug)
	or under 3 studs across (the light panels), so the doctor's sinking-surface check stays quiet. ]]
function BobBuilding.dressRoom(m, dress, at, W, front)
	local FK = require(RS:WaitForChild("FurnitureKit"))
	local inner = W / 2 - 1   -- the side walls' inner faces
	local back = -front + 1   -- the back wall's inner face
	-- wainscot: a panel to 3.6 studs with a rail on top, on the back and both side walls
	local PANEL, RAIL = 3.6, 3.75
	part(m, { Name = "Wainscot", Keep = true, Size = Vector3.new(W - 2, PANEL, 0.25), CFrame = at(0, 0.4 + PANEL / 2, back + 0.13), Color = WALNUT, Material = Enum.Material.Wood })
	part(m, { Name = "Rail", Keep = true, Size = Vector3.new(W - 2, 0.3, 0.45), CFrame = at(0, 0.4 + RAIL, back + 0.23), Color = GOLD, Material = Enum.Material.Wood })
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (inner - 0.13)
		part(m, { Name = "Wainscot", Keep = true, Size = Vector3.new(0.25, PANEL, front * 2 - 2), CFrame = at(x, 0.4 + PANEL / 2, 0), Color = WALNUT, Material = Enum.Material.Wood })
		part(m, { Name = "Rail", Keep = true, Size = Vector3.new(0.45, 0.3, front * 2 - 2), CFrame = at(sx * (inner - 0.23), 0.4 + RAIL, 0), Color = GOLD, Material = Enum.Material.Wood })
	end
	-- light panels set into the ceiling
	for _, xz in ipairs({ { -8, -4 }, { 4, -4 }, { -8, 5 }, { 4, 5 } }) do
		local p = part(m, { Name = "LightPanel", Keep = true, Size = Vector3.new(2.4, 0.1, 5), CFrame = at(xz[1], BobBuilding.SIZE.room - 0.22, xz[2]),
			Color = Color3.fromRGB(255, 250, 238), Material = Enum.Material.SmoothPlastic, CanCollide = false })
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Bottom
		light.Range, light.Brightness, light.Angle = 14, 0.8, 120
		light.Color = Color3.fromRGB(255, 240, 220)
		light.Parent = p
	end
	-- the rug under the table (solid, so it is floor: the cast stands on it)
	part(m, { Name = "RugEdge", Keep = true, Size = Vector3.new(15, 0.1, 11), CFrame = at(-4, 0.45, -3.6), Color = GOLD, Material = Enum.Material.Fabric })
	part(m, { Name = "Rug", Keep = true, Size = Vector3.new(14, 0.12, 10), CFrame = at(-4, 0.46, -3.6), Color = RUG, Material = Enum.Material.Fabric })
	-- the window: a city at dusk behind a framed pane, not a lit box
	local win = part(m, { Name = "Window", Keep = true, Size = Vector3.new(20, 6, 0.2), CFrame = at(-2, 7, back + 0.1), Color = Color3.fromRGB(60, 84, 128), CanCollide = false })
	local g = Instance.new("SurfaceGui")
	g.Face = Enum.NormalId.Back   -- the room side (+Z); live 25 Oct the Front face drew it into the wall
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 20
	g.LightInfluence = 0.15
	local sky = Instance.new("Frame")
	sky.BorderSizePixel = 0
	sky.Size = UDim2.fromScale(1, 1)
	sky.BackgroundColor3 = Color3.new(1, 1, 1)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(86, 120, 178)),   -- dusk sky, top
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(196, 150, 160)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(240, 170, 112)),   -- the glow at the horizon
	})
	grad.Parent = sky
	sky.Parent = g
	local heights = { 0.55, 0.8, 0.42, 0.66, 0.92, 0.5, 0.74, 0.38, 0.86, 0.6, 0.47, 0.78, 0.58, 0.7 }
	for i, h in ipairs(heights) do
		local b = Instance.new("Frame")
		b.BorderSizePixel = 0
		b.AnchorPoint = Vector2.new(0, 1)
		b.Position = UDim2.fromScale((i - 1) / #heights, 1)
		b.Size = UDim2.fromScale(1 / #heights * (0.8 + (i % 3) * 0.12), h * 0.7)
		b.BackgroundColor3 = i % 2 == 0 and Color3.fromRGB(46, 58, 88) or Color3.fromRGB(58, 70, 104)
		for k = 1, 6 do
			local lit = Instance.new("Frame")
			lit.BorderSizePixel = 0
			lit.Size = UDim2.fromScale(0.16, 0.05)
			lit.Position = UDim2.fromScale(0.2 + ((k * 3 + i) % 3) * 0.24, 0.12 + k * 0.13)
			lit.BackgroundColor3 = Color3.fromRGB(255, 214, 140)
			lit.BackgroundTransparency = (k + i) % 3 == 0 and 1 or 0.15
			lit.Parent = b
		end
		b.Parent = sky
	end
	g.Parent = win
	for _, x in ipairs({ -12, -7, -2, 3, 8 }) do
		part(m, { Name = "WindowFrame", Keep = true, Size = Vector3.new(0.35, 6.4, 0.3), CFrame = at(x, 7, back + 0.25), Color = CHARCOAL, CanCollide = false })
	end
	for _, y in ipairs({ 3.85, 10.15 }) do
		part(m, { Name = "WindowFrame", Keep = true, Size = Vector3.new(20.4, 0.35, 0.3), CFrame = at(-2, y + 0.05, back + 0.25), Color = CHARCOAL, CanCollide = false })
	end
	-- the wall screen on the right wall: a ticker going up (Bob's money)
	local screen = part(m, { Name = "WallScreen", Keep = true, Size = Vector3.new(0.2, 3.4, 6), CFrame = at(inner - 0.12, 6.6, -1), Color = DEVICE, CanCollide = false })
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Left
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0.2
	local bg = Instance.new("Frame")
	bg.BorderSizePixel = 0
	bg.Position, bg.Size = UDim2.fromScale(0.03, 0.05), UDim2.fromScale(0.94, 0.9)
	bg.BackgroundColor3 = Color3.fromRGB(15, 21, 36)
	bg.Parent = sg
	local bars = { 0.3, 0.38, 0.34, 0.46, 0.42, 0.55, 0.5, 0.62, 0.6, 0.72, 0.68, 0.8 }
	for i, h in ipairs(bars) do
		local c = Instance.new("Frame")
		c.BorderSizePixel = 0
		c.AnchorPoint = Vector2.new(0, 1)
		c.Position = UDim2.fromScale(0.05 + (i - 1) * 0.075, 0.9 - (h - 0.25) * 0.6)
		c.Size = UDim2.fromScale(0.045, 0.2 + (i % 3) * 0.05)
		c.BackgroundColor3 = (i % 4 == 3) and Color3.fromRGB(239, 68, 68) or Color3.fromRGB(34, 197, 94)
		c.Parent = bg
	end
	local tick = Instance.new("TextLabel")
	tick.BackgroundTransparency = 1
	tick.Position, tick.Size = UDim2.fromScale(0.05, 0.06), UDim2.fromScale(0.6, 0.16)
	tick.Font = Enum.Font.FredokaOne
	tick.TextScaled = true
	tick.TextXAlignment = Enum.TextXAlignment.Left
	tick.Text = "BOB CAPITAL  +4.2%"
	tick.TextColor3 = Color3.fromRGB(148, 163, 184)
	tick.Parent = bg
	sg.Parent = screen
	-- furniture from the game's own kit (+Z is a piece's front; yaw 90 faces +X)
	FK.put("bookcaseClosedDoors", at(-inner + 0.9, 0.4, 2.2), dress, { yaw = 90 })
	FK.put("bookcaseClosedDoors", at(-inner + 0.9, 0.4, 4.7), dress, { yaw = 90 })
	FK.put("cabinet_medium_decorated", at(inner - 1.1, 0.4, -5.5), dress, { yaw = -90 })
	FK.put("lamp_standing", at(inner - 1.2, 0.4, 2.4), dress, {})
	FK.put("shelf_B_small_decorated", at(-6, 0.4, back + 0.7), dress, {})
end

-- ------------------------------------------------------------------ the building
function BobBuilding.build(world)
	local old = world:FindFirstChild("BobCapital")
	if old then old:Destroy() end
	local S = BobBuilding.SIZE
	local site = BobBuilding.site()
	local m = Instance.new("Model")
	m.Name = "BobCapital"
	local function at(x, y, z) return site * CFrame.new(x, y, z) end
	local W, D, H = S.w, S.d, S.h
	local front = D / 2

	-- the shell: back and side walls solid; the front wall is three pieces round the door
	part(m, { Name = "Floor", Size = Vector3.new(W, 0.4, D), CFrame = at(0, 0.2, 0), Color = OAK, Material = Enum.Material.WoodPlanks })
	part(m, { Name = "BackWall", Size = Vector3.new(W, H, 1), CFrame = at(0, H / 2, -front + 0.5), Color = NAVY })
	part(m, { Name = "SideL", Size = Vector3.new(1, H, D), CFrame = at(-W / 2 + 0.5, H / 2, 0), Color = NAVY })
	part(m, { Name = "SideR", Size = Vector3.new(1, H, D), CFrame = at(W / 2 - 0.5, H / 2, 0), Color = NAVY })
	part(m, { Name = "Roof", Size = Vector3.new(W, 1, D), CFrame = at(0, H + 0.5, 0), Color = CHARCOAL })
	local ceiling = part(m, { Name = "RoomCeiling", Size = Vector3.new(W - 2, 0.4, D - 2), CFrame = at(0, S.room, 0), Color = CEILING })
	local doorX, doorW, doorH = 9, 4, 8
	local fw = Instance.new("Model")
	fw.Name = "FrontWall"   -- the client hides this during the boardroom shots (a cutaway)
	fw.Parent = m
	local leftW = (doorX - doorW / 2) - (-W / 2)
	part(fw, { Name = "FrontL", Size = Vector3.new(leftW, H, 1), CFrame = at(-W / 2 + leftW / 2, H / 2, front - 0.5), Color = NAVY })
	local rightW = W / 2 - (doorX + doorW / 2)
	part(fw, { Name = "FrontR", Size = Vector3.new(rightW, H, 1), CFrame = at(W / 2 - rightW / 2, H / 2, front - 0.5), Color = NAVY })
	part(fw, { Name = "Lintel", Size = Vector3.new(doorW, H - doorH, 1), CFrame = at(doorX, doorH + (H - doorH) / 2, front - 0.5), Color = NAVY })
	-- 25 Oct: a facade, not a blue box. Stone base, a framed glass curtain wall above the door line,
	-- a gold trim at the roof and a big sign. Every piece is vertical and touches the wall (no floating
	-- flat parts: the doctor reads those as sinking surfaces). All in FrontWall: cut away inside.
	local baseL = (doorX - doorW / 2) - (-W / 2 - 0.2)
	part(fw, { Name = "Base", Size = Vector3.new(baseL, 3, 0.4), CFrame = at(-W / 2 - 0.2 + baseL / 2, 1.5, front + 0.15), Color = STONE, Material = Enum.Material.Slate, CanCollide = false, CanQuery = false })
	local baseR = (W / 2 + 0.2) - (doorX + doorW / 2)
	part(fw, { Name = "Base", Size = Vector3.new(baseR, 3, 0.4), CFrame = at(W / 2 + 0.2 - baseR / 2, 1.5, front + 0.15), Color = STONE, Material = Enum.Material.Slate, CanCollide = false, CanQuery = false })
	part(fw, { Name = "CurtainGlass", Size = Vector3.new(W - 2, H - doorH - 3, 0.2), CFrame = at(0, doorH + 1 + (H - doorH - 3) / 2, front + 0.05),
		Color = GLASS, Material = Enum.Material.Glass, Transparency = 0.15, Reflectance = 0.25, CanCollide = false, CanQuery = false })
	for x = -W / 2 + 1, W / 2 - 1, 3.5 do
		part(fw, { Name = "Mullion", Size = Vector3.new(0.3, H - doorH - 3, 0.3), CFrame = at(x, doorH + 1 + (H - doorH - 3) / 2, front + 0.2), Color = CHARCOAL, CanCollide = false, CanQuery = false })
	end
	for y = doorH + 1, H - 2, 4 do
		part(fw, { Name = "Transom", Size = Vector3.new(W - 2, 0.3, 0.3), CFrame = at(0, y, front + 0.2), Color = CHARCOAL, CanCollide = false, CanQuery = false })
	end
	part(fw, { Name = "Trim", Size = Vector3.new(W + 0.4, 0.8, 0.5), CFrame = at(0, H - 0.4, front + 0.2), Color = GOLD, Material = Enum.Material.Metal, CanCollide = false, CanQuery = false })
	local big = part(fw, { Name = "BigSign", Size = Vector3.new(18, 3.2, 0.3), CFrame = at(-3, H - 3.4, front + 0.4), Color = CHARCOAL, CanCollide = false, CanQuery = false })
	label(big, Enum.NormalId.Front, "BOB CAPITAL", GOLD)
	placeKit("Plant", fw, at(doorX - 4.2, 0.4, front + 1.6), 2.2, 0)
	placeKit("Plant", fw, at(doorX + 4.2, 0.4, front + 1.6), 2.2, 0)
	local sign = part(m, { Name = "Sign", Size = Vector3.new(12, 2.2, 0.3), CFrame = at(doorX - 3, doorH + 1.6, front + 0.2), Color = GOLD, CanCollide = false })
	label(sign, Enum.NormalId.Front, "BOB CAPITAL", CHARCOAL)

	-- the door (server: always shut) and the tape across it
	local door = part(m, { Name = "Door", Size = Vector3.new(doorW, doorH, 0.4), CFrame = at(doorX, doorH / 2 + 0.4, front - 0.5), Color = DOORWOOD })
	-- 27 Oct: where "shut" is, for the clients. A client that already opened the door for you (BobDoorClient)
	-- must not read its own open door as shut (measured: a replayed payoff ended the door at 160 degrees)
	door:SetAttribute("ClosedCF", door.CFrame)
	part(m, { Name = "Knob", Shape = Enum.PartType.Ball, Size = Vector3.new(0.4, 0.4, 0.4), CFrame = at(doorX - 1.4, 4, front - 0.2), Color = GOLD, CanCollide = false })
	local tape = Instance.new("Model")
	tape.Name = "Tape"
	tape.Parent = m
	for _, a in ipairs({ 1, -1 }) do
		part(tape, { Name = "Strip", Size = Vector3.new(0.6, doorH + 1.2, 0.1), CFrame = at(doorX, doorH / 2 + 0.4, front + 0.05) * CFrame.Angles(0, 0, math.rad(32 * a)),
			Color = TAPE, CanCollide = false, CanQuery = false })
	end
	part(m, { Name = "Trigger", Size = Vector3.new(doorW + 2, 7, 4), CFrame = at(doorX, 3.5, front + 2), Transparency = 1,
		CanCollide = false, CanQuery = false, CanTouch = true })

	-- the boardroom (both cutscenes): a long table, chairs, a window, a plant, the name inside
	local dress = Instance.new("Model")
	dress.Name = "Dressing"
	dress.Parent = m
	if not placeKit("Table", dress, at(-4, 0.4, -4.2), 1.6, 90) then
		part(m, { Name = "Table", Size = Vector3.new(16, 0.6, 3.4), CFrame = at(-4, 3, -3), Color = OAK })
		for _, x in ipairs({ -10.5, 2.5 }) do part(m, { Name = "TableLeg", Size = Vector3.new(0.6, 2.7, 2.6), CFrame = at(x, 1.65, -3), Color = DOORWOOD }) end
		for _, x in ipairs({ -12, -7, -2.5 }) do part(m, { Name = "Chair", Size = Vector3.new(2, 4, 0.5), CFrame = at(x, 2.4, -5.6), Color = CHARCOAL }) end
	end
	placeKit("Portrait", dress, at(10.5, 4.6, -front + 1.3), 3, 180)
	placeKit("Safe", dress, at(-12, 0.4, -8.5), 1.3, 30)
	placeKit("Plant", dress, at(12.8, 0.4, -9.5), 2.4, 0)
	placeKit("Plant", dress, at(-13, 0.4, 8.5), 2.4, 0)
	BobBuilding.dressRoom(m, dress, at, W, front)
	-- live 25 Oct: a closed room is black without its own light (both cutscenes play in here).
	-- The lights hang off the ceiling part (a flat lamp part read as a sinking surface to the doctor)
	-- (25 Oct: a third over the front of the room, so faces are lit from the camera's side)
	for _, xz in ipairs({ { -8, 0 }, { 4, 0 }, { -2, 7 } }) do
		local a = Instance.new("Attachment")
		a.Name = "Lamp"
		a.Parent = ceiling
		a.WorldCFrame = at(xz[1], S.room - 0.6, xz[2])
		local light = Instance.new("PointLight")
		light.Range = 22
		light.Brightness = 1.6
		light.Color = Color3.fromRGB(255, 236, 210)
		light.Shadows = false
		light.Parent = a
	end
	local inner = part(m, { Name = "InnerSign", Size = Vector3.new(10, 1.4, 0.2), CFrame = at(-2, 10.8, -front + 1.1), Color = NAVY, CanCollide = false })
	label(inner, Enum.NormalId.Front, "BOB CAPITAL", GOLD)
	part(m, { Name = "Plant", Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3), CFrame = at(-13, 3.6, -9), Color = Color3.fromRGB(78, 168, 92), CanCollide = false })
	part(m, { Name = "Pot", Size = Vector3.new(2, 2, 2), CFrame = at(-13, 1.4, -9), Color = STONE })

	-- anchors (BobScript's coordinate frames) + where the winner sees Bob sit dizzy
	m:SetAttribute("AnchorBoard", at(0, 0.4, 0))
	m:SetAttribute("AnchorDoor", at(doorX, 0.4, front))
	m:SetAttribute("AnchorStreet", at(doorX + 36, 0.4, front + 14))
	-- where the winner sees Bob sit dizzy (BobDoorClient); facing the street (+Z)
	m:SetAttribute("AnchorCurb", at(doorX + 6, 0.4, front + 4))

	m.PrimaryPart = door
	m.Parent = world
	BobBuilding.model = m
	BobBuilding.buildCast()
	return m
end

-- ------------------------------------------------------------------ the cast
local function weldTo(base, p)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = base, p
	w.Parent = p
	p.Anchored = false
	p.CanCollide = false
	p.Massless = true
	p.Parent = base.Parent
end

local function faceGui(head)
	local g = Instance.new("SurfaceGui")
	g.Name = "Face"
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 100
	g.LightInfluence = 0.5
	g.Parent = head
	return g
end

local function castMember(name, index, shirt, pants)
	local StaffRig = require(script.Parent:WaitForChild("StaffRig"))
	local m = StaffRig.build("eng", index)
	m.Name = name
	StaffRig.setOutfit(m, shirt, pants)
	CollectionService:RemoveTag(m, StaffRig.TAG)   -- not staff: never counted, never tagged
	local head = m:FindFirstChild("Head")
	if head then
		local tag = head:FindFirstChild("Tag")
		if tag then tag:Destroy() end
		faceGui(head)
	end
	return m, head
end

-- an AI cast member: cloned, rigged (BobRig), given face cards (BobFace) while it stands in
-- the world for a moment (the cards are placed by raycasting the head), then stored
-- per-head face tuning (BobFace.ensureCards): measured live 25 Oct
local FACE_TUNE = { Inv2 = { mouthIn = 0.15 } }
local function aiMember(src, name, parent)
	if not src then return nil end
	local BobRig = require(RS:WaitForChild("BobRig"))
	local BobFace = require(RS:WaitForChild("BobFace"))
	local m = src:Clone()
	m.Name = name
	m:PivotTo(CFrame.new(0, -400, 0))
	m.Parent = workspace
	local ok = pcall(function()
		if not BobRig.ensure(m) then error("not six pieces") end
		BobFace.ensureCards(m, FACE_TUNE[name])
	end)
	if not ok then m:Destroy() return nil end
	m.Parent = parent
	return m
end

function BobBuilding.buildCast()
	local old = RS:FindFirstChild("BobCast")
	if old then old:Destroy() end
	local f = Instance.new("Folder")
	f.Name = "BobCast"
	-- 25 Oct: the AI cast (BobModel, BobKit.Inv1/Inv2) when the place has them
	local aiBob = aiMember(RS:FindFirstChild("BobModel"), "Bob", f)
	if aiBob then
		local head = aiBob:FindFirstChild("Head")
		local mouth = aiBob:FindFirstChild("MouthCard")
		if head and mouth then
			-- his gold toothpick, in the corner of his mouth (welded: it drops in the payoff)
			local pick = part(aiBob, { Name = "Toothpick", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.75, 0.07, 0.07),
				CFrame = mouth.CFrame * CFrame.new(mouth.Size.X * 0.42, 0.02, -0.12) * CFrame.Angles(0, math.rad(-25), math.rad(-15)),
				Color = GOLD, Material = Enum.Material.Metal })
			weldTo(head, pick)
		end
	end
	local aiInv1 = aiMember(kitPiece("Inv1"), "Inv1", f)
	local aiInv2 = aiMember(kitPiece("Inv2"), "Inv2", f)
	if aiBob and aiInv1 and aiInv2 then
		for _, d in ipairs(f:GetDescendants()) do
			if d:IsA("BasePart") then d.Anchored = true end
		end
		BobBuilding.buildChart(f)
		f.Parent = RS
		return f
	end
	for _, m in ipairs({ aiBob, aiInv1, aiInv2 }) do if m then m:Destroy() end end
	-- Bob: a dark suit, a red tie, a belly, slicked hair, black sunglasses and a GOLD TOOTHPICK
	local bob, head = castMember("Bob", 7001, CHARCOAL, CHARCOAL)
	for _, a in ipairs(bob:GetChildren()) do if a:IsA("Accessory") then a:Destroy() end end
	local torso = bob:FindFirstChild("UpperTorso")
	if torso then
		local belly = part(bob, { Name = "Belly", Shape = Enum.PartType.Ball, Size = Vector3.new(3.4, 3, 2.6), CFrame = torso.CFrame * CFrame.new(0, -0.5, -0.5), Color = CHARCOAL })
		weldTo(torso, belly)
		local tie = part(bob, { Name = "Tie", Size = Vector3.new(0.45, 1.5, 0.1), CFrame = torso.CFrame * CFrame.new(0, 0, -1.82), Color = RED })
		weldTo(torso, tie)
	end
	if head then
		local hs = head.Size
		local hair = part(bob, { Name = "Hair", Size = Vector3.new(hs.X * 1.02, 0.35, hs.Z * 1.02), CFrame = head.CFrame * CFrame.new(0, hs.Y / 2, 0), Color = Color3.fromRGB(59, 42, 30) })
		weldTo(head, hair)
		local glasses = part(bob, { Name = "Sunglasses", Size = Vector3.new(hs.X * 0.9, 0.3, 0.12), CFrame = head.CFrame * CFrame.new(0, hs.Y * 0.08, -hs.Z / 2 - 0.05), Color = Color3.fromRGB(17, 17, 17) })
		weldTo(head, glasses)
		local pick = part(bob, { Name = "Toothpick", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 0.08, 0.08),
			CFrame = head.CFrame * CFrame.new(hs.X * 0.28, -hs.Y * 0.28, -hs.Z / 2 - 0.15) * CFrame.Angles(0, math.rad(20), math.rad(18)),
			Color = GOLD, Material = Enum.Material.Metal })
		weldTo(head, pick)
	end
	bob.Parent = f
	local function noHats(m)
		for _, a in ipairs(m:GetChildren()) do
			if a:IsA("Accessory") and a.AccessoryType ~= Enum.AccessoryType.Hair then a:Destroy() end
		end
	end
	local inv1 = castMember("Inv1", 7002, Color3.fromRGB(74, 80, 104), Color3.fromRGB(47, 51, 66))
	noHats(inv1)
	inv1.Parent = f
	local inv2 = castMember("Inv2", 7003, Color3.fromRGB(94, 74, 110), Color3.fromRGB(47, 51, 66))
	noHats(inv2)
	inv2.Parent = f
	BobBuilding.buildChart(f)
	for _, d in ipairs(f:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end
	f.Parent = RS
	return f
end

-- the iPad the player pulls from behind their back in the payoff (25 Oct, Luke: not the bright paper
-- board). A dark tablet body; the client draws its screen (REVENUE, the line, the number)
function BobBuilding.buildChart(f)
	local chart = part(f, { Name = "Chart", Keep = true, Size = Vector3.new(2.7, 1.9, 0.14), CFrame = CFrame.new(), Color = DEVICE, CanCollide = false })
	local g = Instance.new("SurfaceGui")
	g.Name = "ChartGui"
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 120
	g.LightInfluence = 0.25
	g.Parent = chart
	return chart
end

-- ------------------------------------------------------------------ the trophy
-- BOB'S TOOTHPICK: a gold toothpick on a little stand, for a save that beat him. Everyone sees it.
function BobBuilding.trophy(parent, cf)
	local m = Instance.new("Model")
	m.Name = "BobTrophy"
	local base = part(m, { Name = "Stand", Size = Vector3.new(1.6, 3, 1.6), CFrame = cf * CFrame.new(0, 1.5, 0), Color = CHARCOAL })
	part(m, { Name = "Top", Size = Vector3.new(2, 0.2, 2), CFrame = cf * CFrame.new(0, 3.1, 0), Color = GOLD, Material = Enum.Material.Metal })
	part(m, { Name = "Toothpick", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 0.14, 0.14),
		CFrame = cf * CFrame.new(0, 3.5, 0) * CFrame.Angles(0, 0, math.rad(25)), Color = GOLD, Material = Enum.Material.Metal, CanCollide = false })
	local plate = part(m, { Name = "Plate", Size = Vector3.new(1.5, 0.5, 0.05), CFrame = cf * CFrame.new(0, 2.4, -0.83), Color = GOLD, CanCollide = false })
	label(plate, Enum.NormalId.Front, LINES.trophy, CHARCOAL)
	m.PrimaryPart = base
	m.Parent = parent
	return m
end

return BobBuilding
