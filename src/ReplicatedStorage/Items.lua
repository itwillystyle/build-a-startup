--[[
	Items -- ModuleScript in ReplicatedStorage (v3.2).

	The bag's catalog, shared by the server (Inventory) and the client
	(InventoryClient). Five items, each with ONE job you can feel, in the
	place it matters:

	  Cold Brew     WRITE CODE earns x3 for 60 s       (the active verb)
	  Energy Drink  scooter +5 speed for 90 s          (the chase)
	  Non-Compete   the headhunter chasing you quits   (the chase, rescue)
	  Scout Report  your next hire rolls a talent up    (the rare-hire chase)
	  Front Page    your next LAUNCH pays double        (the payday)

	Where they come from: the daily streak, investor deals, and launches (a
	coffee on your first launch, then sometimes). Counts are saved as plain
	integers; boosts are session-only.

	Each item also knows how to build its own 3D icon from parts (no uploads),
	for the bag's ViewportFrames.
]]

local Items = {}

Items.RARITY = {
	{ name = "COMMON",   color = Color3.fromRGB(160, 170, 190) },
	{ name = "UNCOMMON", color = Color3.fromRGB(70, 200, 110) },
	{ name = "RARE",     color = Color3.fromRGB(70, 150, 255) },
	{ name = "EPIC",     color = Color3.fromRGB(180, 110, 255) },
}

Items.LIST = {
	{ id = "coffee", name = "Cold Brew", rarity = 1, use = "now", duration = 60,
		desc = "WRITE CODE earns 3x for 60 seconds.", short = "3x code" },
	{ id = "energy", name = "Energy Drink", rarity = 2, use = "now", duration = 90,
		desc = "Your scooter goes +5 faster for 90 seconds.", short = "+5 speed" },
	{ id = "noncompete", name = "Non-Compete", rarity = 3, use = "chase",
		desc = "Use it while a headhunter chases you. They give up.", short = "stop a headhunter" },
	{ id = "scout", name = "Scout Report", rarity = 3, use = "arm",
		desc = "Your next hire rolls one talent higher (SKILLED or better).", short = "next hire +1 talent" },
	{ id = "frontpage", name = "Front Page", rarity = 4, use = "arm",
		desc = "Your next LAUNCH pays double.", short = "next launch x2" },
}
Items.BY_ID = {}
for i, it in ipairs(Items.LIST) do it.order = i; Items.BY_ID[it.id] = it end
Items.MAX = 99

-- "coffee=2;energy=1" <-> { coffee = 2, energy = 1 } (the player attribute)
function Items.encode(t)
	local parts = {}
	for _, it in ipairs(Items.LIST) do
		local n = t and t[it.id] or 0
		if n > 0 then table.insert(parts, it.id .. "=" .. n) end
	end
	return table.concat(parts, ";")
end
function Items.decode(str)
	local t = {}
	for id, n in string.gmatch(str or "", "(%w+)=(%d+)") do
		if Items.BY_ID[id] then t[id] = tonumber(n) end
	end
	return t
end

-- ============ 3D ICONS ============
local function p(parent, props)
	local x = Instance.new("Part")
	x.Anchored = true
	x.CanCollide = false
	x.CastShadow = false
	x.TopSurface = Enum.SurfaceType.Smooth
	x.BottomSurface = Enum.SurfaceType.Smooth
	x.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do x[k] = v end
	x.Parent = parent
	return x
end
local function cyl(parent, dia, h, cf, color, mat)
	return p(parent, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, dia, dia),
		CFrame = cf * CFrame.Angles(0, 0, math.rad(90)), Color = color, Material = mat or Enum.Material.SmoothPlastic })
end

local BUILD = {}
BUILD.coffee = function(m)
	local c = CFrame.new()
	cyl(m, 1.5, 2.1, c, Color3.fromRGB(236, 232, 224))                              -- cup
	cyl(m, 1.53, 0.7, c * CFrame.new(0, -0.1, 0), Color3.fromRGB(196, 150, 98))       -- kraft sleeve
	cyl(m, 1.62, 0.22, c * CFrame.new(0, 1.12, 0), Color3.fromRGB(58, 46, 40))        -- lid
	p(m, { Size = Vector3.new(0.14, 1.6, 0.14), CFrame = c * CFrame.new(0.2, 1.8, 0) * CFrame.Angles(0, 0, math.rad(-12)),
		Color = Color3.fromRGB(70, 200, 110) })                                          -- straw
	p(m, { Size = Vector3.new(0.5, 0.06, 0.06), CFrame = c * CFrame.new(0, -0.1, -0.77), Color = Color3.fromRGB(120, 80, 50) })
end
BUILD.energy = function(m)
	local c = CFrame.new()
	cyl(m, 1.25, 2.3, c, Color3.fromRGB(60, 200, 110), Enum.Material.Metal)           -- can
	cyl(m, 1.1, 0.14, c * CFrame.new(0, 1.2, 0), Color3.fromRGB(200, 204, 210), Enum.Material.Metal)
	cyl(m, 1.1, 0.14, c * CFrame.new(0, -1.2, 0), Color3.fromRGB(200, 204, 210), Enum.Material.Metal)
	p(m, { Size = Vector3.new(0.9, 0.24, 0.06), CFrame = c * CFrame.new(0, 0.2, -0.63) * CFrame.Angles(0, 0, math.rad(-35)),
		Color = Color3.fromRGB(255, 236, 90), Material = Enum.Material.Neon })             -- the bolt
	p(m, { Size = Vector3.new(0.9, 0.24, 0.06), CFrame = c * CFrame.new(0.15, -0.35, -0.63) * CFrame.Angles(0, 0, math.rad(-35)),
		Color = Color3.fromRGB(255, 236, 90), Material = Enum.Material.Neon })
end
BUILD.noncompete = function(m)
	local c = CFrame.Angles(0, 0, math.rad(-6))
	p(m, { Size = Vector3.new(1.7, 2.3, 0.08), CFrame = c, Color = Color3.fromRGB(246, 242, 232) })        -- the contract
	for k = 0, 4 do
		p(m, { Size = Vector3.new(k == 0 and 1.0 or 1.3, 0.09, 0.02), CFrame = c * CFrame.new(k == 0 and -0.15 or 0, 0.85 - k * 0.3, -0.05),
			Color = Color3.fromRGB(70, 74, 86) })
	end
	cyl(m, 0.6, 0.12, c * CFrame.new(0.45, -0.75, -0.08) * CFrame.Angles(math.rad(90), 0, 0), Color3.fromRGB(210, 40, 50))  -- wax seal
	p(m, { Size = Vector3.new(0.14, 0.6, 0.02), CFrame = c * CFrame.new(0.35, -1.1, -0.07) * CFrame.Angles(0, 0, math.rad(15)), Color = Color3.fromRGB(210, 40, 50) })
	p(m, { Size = Vector3.new(0.14, 0.6, 0.02), CFrame = c * CFrame.new(0.55, -1.1, -0.07) * CFrame.Angles(0, 0, math.rad(-15)), Color = Color3.fromRGB(210, 40, 50) })
end
BUILD.scout = function(m)
	local c = CFrame.Angles(math.rad(-8), 0, math.rad(4))
	p(m, { Size = Vector3.new(2.2, 1.6, 0.14), CFrame = c, Color = Color3.fromRGB(70, 140, 240) })         -- folder back
	p(m, { Size = Vector3.new(1.9, 1.5, 0.05), CFrame = c * CFrame.new(0.05, 0.28, -0.08), Color = Color3.fromRGB(248, 248, 244) })  -- paper
	p(m, { Size = Vector3.new(2.2, 1.2, 0.1), CFrame = c * CFrame.new(0, -0.22, -0.14), Color = Color3.fromRGB(90, 160, 255) })    -- folder front
	p(m, { Size = Vector3.new(0.7, 0.24, 0.04), CFrame = c * CFrame.new(-0.7, 0.7, -0.14), Color = Color3.fromRGB(90, 160, 255) }) -- tab
	cyl(m, 0.5, 0.06, c * CFrame.new(0.6, -0.3, -0.2) * CFrame.Angles(math.rad(90), 0, 0), Color3.fromRGB(255, 208, 70), Enum.Material.Neon)  -- the star sticker
end
BUILD.frontpage = function(m)
	local c = CFrame.Angles(math.rad(-10), math.rad(10), 0)
	p(m, { Size = Vector3.new(2.3, 1.7, 0.08), CFrame = c, Color = Color3.fromRGB(240, 236, 226) })        -- the paper
	p(m, { Size = Vector3.new(2.3, 1.7, 0.08), CFrame = c * CFrame.new(0.06, -0.06, 0.08) * CFrame.Angles(0, 0, math.rad(3)),
		Color = Color3.fromRGB(222, 216, 204) })
	p(m, { Size = Vector3.new(2.0, 0.34, 0.02), CFrame = c * CFrame.new(0, 0.58, -0.05), Color = Color3.fromRGB(34, 36, 44) })   -- headline
	p(m, { Size = Vector3.new(0.9, 0.7, 0.02), CFrame = c * CFrame.new(-0.5, -0.12, -0.05), Color = Color3.fromRGB(180, 110, 255) }) -- the photo: you
	for k = 0, 2 do
		p(m, { Size = Vector3.new(0.85, 0.08, 0.02), CFrame = c * CFrame.new(0.55, 0.12 - k * 0.22, -0.05), Color = Color3.fromRGB(110, 114, 124) })
	end
	p(m, { Size = Vector3.new(2.0, 0.08, 0.02), CFrame = c * CFrame.new(0, -0.62, -0.05), Color = Color3.fromRGB(110, 114, 124) })
end

-- build an item's icon into a ViewportFrame (with its own camera); returns the model
function Items.icon(id, vpf)
	local f = BUILD[id]
	if not f then return nil end
	local m = Instance.new("Model")
	m.Name = id
	f(m)
	m.Parent = vpf
	local cf, size = m:GetBoundingBox()
	-- a level pivot at the centre: the first part is a cylinder turned on its
	-- side, and turning the model about THAT part's axis tumbled it end over end
	m.WorldPivot = CFrame.new(cf.Position)
	local r = math.max(size.X, size.Y, size.Z)
	local cam = vpf.CurrentCamera or Instance.new("Camera")
	cam.FieldOfView = 34
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(r * 0.55, r * 0.45, -r * 1.9), cf.Position)
	cam.Parent = vpf
	vpf.CurrentCamera = cam
	vpf.Ambient = Color3.fromRGB(190, 190, 196)
	vpf.LightColor = Color3.fromRGB(255, 250, 240)
	vpf.LightDirection = Vector3.new(-0.5, -1, 0.6)
	return m
end

return Items
