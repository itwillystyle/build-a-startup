--[[
	Apartments (v4.0) -- a home downtown, and a rung on the ladder.

	His ask: "the person should be able to go back to their apartment and buy
	their own apartment similar to GTA V... it would cost money and I would
	like the apartment to be a progress point between HQ's so you HAVE to buy it
	in order to progress, something like a couple million."

	THE LADDER (each one is required before the HQ level after it):
	  STUDIO     $20K   buyable from HQ 2, needed for HQ 3
	  LOFT       $150K  buyable from HQ 3, needed for HQ 4
	  PENTHOUSE  $2M    buyable from HQ 4, needed for HQ 5
	Each adds +10% money for good, and they survive spin-offs (it is YOUR
	home, not the company's). One saved integer: `apt` (0-3).

	THE HOME is a real floor of THE RESIDENCES (Downtown.lua), so the windows
	look out over the actual valley and city. Studios are floors 1-6, lofts
	7-12, penthouses 13-18 (the wrap-around balconies); the plot number picks
	the floor, so six players never share one. You get in through the lobby's
	residents' lift (or straight after buying: the move-in shot), and leave by
	the lift in the unit.
]]
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local SSS = game:GetService("ServerScriptService")

local Apartments = {}

-- v4.3: the tier table and the pure rules below live in Progression.lua (tested
-- offline in Lune); these names stay so every caller keeps working.
local Prog = require(SSS:WaitForChild("Progression"))
Apartments.TIERS = Prog.APARTMENTS

-- the apartment you must own before building HQ `level`
Apartments.need = Prog.aptNeeded

function Apartments.mult(s)
	local m = 1
	for _, t in ipairs(Apartments.TIERS) do
		if (s and s.apt or 0) >= t.id then m += t.bonus end
	end
	return m
end

--[[ v4.2 HOME TURF (1): your home keeps the business running while you are away.
The spec's first rule (cap = one next step) paid LESS than today at 3 of 4 tiers
(sim/offline_sim.py: 10,440 returns; the economy is fast, so the next step is
often only minutes of income). The rule that shipped (sim/offline_sim2/3.py):
	offline = min( rate x 0.25 x min(away, WINDOW[apt]),     the time your home covers
	               max(10 min of income, your next step),     never below today; up to one step
	               next + the step after - cash - 1 )          never two steps in one return
Where it matters is the late game. v4.3 capped the wait at HQ 5 at 2 h (it
reached 20 h), which is exactly what one Penthouse night pays; at the cap a Studio
night covers 25% and a Loft 50% (tests/offline/progression.spec.luau). ]]
Apartments.WINDOW = Prog.WINDOW
Apartments.OFFLINE_RATE = Prog.OFFLINE_RATE
Apartments.OFFLINE_FLOOR = Prog.OFFLINE_FLOOR
Apartments.ladder = Prog.ladder       -- your next two steps (HQ + its apartment, then the spin-off, then HQ 2)
Apartments.offline = Prog.offline

local api
local Downtown
local okFK, FK = pcall(function() return require(RS:WaitForChild("FurnitureKit", 5)) end)
if not okFK then FK = nil end
local units = {}             -- [userId] = Model
local remotes = {}

local Pal = (function()
	local ok, m = pcall(require, game:GetService("ReplicatedStorage"):WaitForChild("Palette", 5))
	return ok and m or nil
end)()

local function hqMod()
	local m = SSS:FindFirstChild("HQFloors")
	local ok, mod = pcall(function() return m and require(m) end)
	return ok and mod or nil
end

local function put(key, cf, parent, opts)
	if FK and FK.has and FK.has(key) then
		local ok, m = pcall(FK.put, key, cf, parent, opts or {})
		if ok and m then
			game:GetService("CollectionService"):RemoveTag(m, "SVChair")
			return m
		end
	end
	return nil
end

local function part(parent, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.CastShadow = false
	for k, v in pairs(props) do p[k] = v end
	-- author in the palette: an unnamed Color used to inherit Roblox default grey
	if Pal then
		p.Color = props.Color and Pal.map(props.Color) or Pal.map(Color3.fromRGB(163, 162, 165))
	end
	p.Parent = parent
	return p
end

local WHITE = Color3.fromRGB(243, 239, 230)
local CHARCOAL = Color3.fromRGB(38, 41, 48)

-- the floor (0-17) a player's unit is on
function Apartments.floorOf(player, tier)
	local plot = api and api.plotOf(player)
	local idx = math.clamp((plot and plot.index) or 1, 1, 6)
	return (tier - 1) * 6 + (idx - 1)
end

-- ============ THE UNITS ============
--[[ Local space of a unit: x across (+-25), z front (+z = the road side, +-20),
y = 0 on the floor. Rounded plan radius 7 (blender/city2.py RES). ]]
local function roundFloor(parent, g, w, d, R, color, material)
	part(parent, { Name = "AptFloor", Size = Vector3.new(w - 1.2, 0.3, d - 2 * R), CFrame = g(0, -0.11, 0), Color = color, Material = material })
	part(parent, { Name = "AptFloor", Size = Vector3.new(w - 2 * R, 0.3, d - 1.2), CFrame = g(0, -0.11, 0), Color = color, Material = material })
	for _, c in ipairs({ { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }) do
		part(parent, { Name = "AptFloor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2 * R - 1.2, 2 * R - 1.2),
			CFrame = g(c[1] * (w / 2 - R), -0.11, c[2] * (d / 2 - R)) * CFrame.Angles(0, 0, math.rad(90)), Color = color, Material = material })
	end
end

local function wallPiece(parent, g, x, z, sx, sz, h, color)
	return part(parent, { Name = "AptWall", Size = Vector3.new(sx, h or 8.6, sz), CFrame = g(x, (h or 8.6) / 2, z), Color = color or WHITE })
end

local function art(parent, g, x, y, z, yaw, w, h, color)
	local frame = part(parent, { Name = "ArtFrame", Size = Vector3.new(w + 0.3, h + 0.3, 0.12), CFrame = g(x, y, z) * CFrame.Angles(0, math.rad(yaw), 0), Color = CHARCOAL, CanCollide = false })
	part(parent, { Name = "Art", Size = Vector3.new(w, h, 0.14), CFrame = g(x, y, z) * CFrame.Angles(0, math.rad(yaw), 0), Color = color, CanCollide = false })
	return frame
end

local function lamp(parent, g, x, y, z, range, bright)
	local p = part(parent, { Name = "AptLamp", Size = Vector3.new(0.3, 0.3, 0.3), CFrame = g(x, y, z), Transparency = 1, CanCollide = false, CanQuery = false })
	local l = Instance.new("PointLight")
	l.Range = range or 28
	l.Brightness = bright or 0.7
	l.Color = Color3.fromRGB(255, 230, 196)
	l.Shadows = false
	l.Parent = p
end

--[[ v4.0.2 LAYOUTS, REDONE after his report: "the fridge is next to the glass
window and couches are backwards". Both were real:
  1. The Residences are glass on all four sides, so the old kitchens, toilet and
     bedheads all stood against windows. Every unit now has a SOLID BACK WALL
     (the building's service side, the lift in it): kitchens, the bathroom and
     bedheads stand against walls, and the glass is left for the view.
  2. The coloured furniture fronted the wrong way (FurnitureKit VERTEX_FLIP).
Every yaw below means: 0 = front toward +Z (the city), 90 = +X, -90 = -X,
180 = -Z (the back wall). A sofa faces its TV; a chair faces its table.
Local space: x across (+-25), z front (+z = the road, +-20), y = 0 on the floor. ]]
local LAYOUT = {}
local BACK = -16.6                                        -- the room face of the solid back wall
local function wallZ(depth) return BACK + depth / 2 + 0.05 end   -- a piece standing against it

-- the kitchen run on the back wall, right of the lift (its frame ends at x 2.7):
-- the fridge first, then 2.53-wide counters
local function kitchenRun(m, g, fridge, fridgeW, fridgeD, keys, uppers)
	put(fridge, g(2.9 + fridgeW / 2, 0, wallZ(fridgeD)), m)
	local x0 = 2.9 + fridgeW + 0.1 + 2.53 / 2
	for k, key in ipairs(keys) do
		local x = x0 + (k - 1) * 2.53
		put(key, g(x, 0, wallZ(2.65)), m)
		if key == "kitchenStove" then
			put("hoodModern", g(x, 4.3, wallZ(1.68)), m)
		elseif uppers and key ~= "kitchenSink" then
			put("kitchenCabinetUpper", g(x, 4.6, wallZ(1.29)), m)
		end
	end
	put("kitchenCoffeeMachine", g(x0, 2.65, BACK + 1.1), m)
end

LAYOUT.studio = function(m, g)
	-- the bathroom, back-left, walled on every side; its door opens to the bed
	wallPiece(m, g, -22.6, -12.5, 0.4, 8.2)                 -- outer side
	wallPiece(m, g, -12.5, -6.8, 0.4, 19.6)                 -- inner side, running on as the bed wing
	wallPiece(m, g, -18.75, -8.4, 7.7, 0.4)                 -- front, door gap x -14.9..-12.7
	put("shower", g(-20.75, 0, wallZ(3.42)), m)
	put("toilet", g(-16.9, 0, wallZ(2.81)), m)
	put("bathroomSink", g(-13.6, 0, -11.6), m, { yaw = -90 })
	put("bathroomMirror", g(-13.2, 3.6, -11.6), m, { yaw = -90 })
	-- the bed: headboard on the bathroom wall, looking out at the city
	put("bedDouble", g(-19.5, 0, -8.2 + 3.36), m)
	put("rugSquare", g(-19.5, 0, -0.8), m)
	for _, x in ipairs({ -23.2, -15.9 }) do
		put("cabinetBedDrawerTable", g(x, 0, -7.51), m)
		put("lampRoundTable", g(x, 1.55, -7.51), m)
	end
	art(m, g, -19.5, 5.4, -8.13, 0, 4, 2.4, Color3.fromRGB(240, 110, 80))
	-- a reading chair in the front-left corner, facing the view
	put("loungeChair", g(-18.5, 0, 12), m)
	put("lampRoundFloor", g(-21.5, 0, 12.6), m)
	put("pottedPlant", g(-13.5, 0, 16), m)
	-- living: TV on the bed wing, the sofa facing it
	put("cabinetTelevision", g(-11.51, 0, -3), m, { yaw = 90 })
	put("televisionModern", g(-11.51, 1.82, -3), m, { yaw = 90 })
	put("rugRounded", g(-6.5, 0, -3), m, { yaw = 90 })
	put("tableCoffee", g(-7, 0, -3), m, { yaw = 90 })
	put("loungeSofa", g(-2.5, 0, -3), m, { yaw = -90 })
	put("lampRoundFloor", g(-2.5, 0, 1.3), m)
	put("pottedPlant", g(-11.2, 0, 1.6), m)
	-- the kitchen on the back wall, a table for two by the front-right window
	kitchenRun(m, g, "kitchenFridge", 2.53, 1.72, { "kitchenCabinet", "kitchenSink", "kitchenCabinet", "kitchenStove", "kitchenCabinet" }, true)
	put("tableRound", g(15, 0, 8), m, { canCollide = true })
	put("chairCushion", g(15, 0, 5.2), m)
	put("chairCushion", g(15, 0, 10.8), m, { yaw = 180 })
	put("pottedPlant", g(21.5, 0, 13.5), m, { scale = 1.2 })
	-- a bookcase left of the lift
	put("bookcaseOpen", g(-6.5, 0, wallZ(1.47)), m)
	put("pottedPlant", g(-9.8, 0, wallZ(1.42)), m)
	lamp(m, g, -5, 7.8, -3, 28, 0.65)
	lamp(m, g, 12, 7.8, -10, 26, 0.6)
	lamp(m, g, -19, 7.8, -2, 20, 0.5)
	lamp(m, g, -17.5, 7.8, -12.5, 12, 0.45)
	lamp(m, g, 15, 7.8, 8, 20, 0.5)
end

LAYOUT.loft = function(m, g)
	-- the bedroom: the left third, a wall with a door between it and the lounge
	wallPiece(m, g, -10, -9.05, 0.4, 15.1)                  -- door gap z -1.5..1.0
	wallPiece(m, g, -10, 9.95, 0.4, 17.9)
	put("bedDouble", g(-17.2, 0, wallZ(6.62)), m)
	for _, x in ipairs({ -21.2, -13.2 }) do
		put("cabinetBedDrawerTable", g(x, 0, wallZ(1.28)), m)
		put("lampRoundTable", g(x, 1.55, wallZ(1.28)), m)
	end
	put("rugSquare", g(-17.2, 0, -8.5), m)
	art(m, g, -17.2, 5.4, BACK + 0.07, 0, 5, 2.6, Color3.fromRGB(92, 132, 180))
	put("bookcaseClosedWide", g(-10.985, 0, -6), m, { yaw = -90 })
	put("loungeChair", g(-17, 0, 13), m)
	put("lampRoundFloor", g(-20.5, 0, 13.6), m)
	put("pottedPlant", g(-12.5, 0, 16.5), m)
	-- the lounge: TV on the bedroom wall, a sofa facing it, two chairs at the table
	put("cabinetTelevisionDoors", g(-8.985, 0, 9), m, { yaw = 90 })
	put("televisionModern", g(-8.985, 1.82, 9), m, { yaw = 90, scale = 1.25 })
	put("speaker", g(-9.3, 0, 5.6), m, { yaw = 90 })
	put("speaker", g(-9.3, 0, 12.4), m, { yaw = 90 })
	put("rugRounded", g(-3.5, 0, 9), m, { yaw = 90, scale = 1.3 })
	put("tableCoffeeGlass", g(-3.5, 0, 9), m, { yaw = 90 })
	put("loungeSofaLong", g(2.6, 0, 9), m, { yaw = -90 })
	put("loungeChair", g(-3.5, 0, 14.6), m, { yaw = 180 })
	put("loungeChair", g(-3.5, 0, 3.4), m)
	put("lampRoundFloor", g(2.6, 0, 13.4), m)
	art(m, g, -9.73, 5.2, -5.5, 90, 4, 2.6, Color3.fromRGB(255, 208, 70))
	-- the kitchen: a full run on the back wall, an island with stools facing it
	kitchenRun(m, g, "kitchenFridgeLarge", 3.06, 2.38, { "kitchenCabinet", "kitchenSink", "kitchenCabinet", "kitchenStove", "kitchenCabinet" }, true)
	for k = 0, 3 do
		put("kitchenBar", g(7.5 + k * 2.53, 0, -9), m, { yaw = 180, canCollide = true })
		put("stoolBar", g(7.5 + k * 2.53, 0, -7.5), m, { yaw = 180 })
	end
	-- dining by the window, the desk looking out of the right side
	put("tableGlass", g(17, 0, 6), m, { canCollide = true, scale = 1.2 })
	for _, o in ipairs({ { -1.5, 2.4, 180 }, { 1.5, 2.4, 180 }, { -1.5, -2.4, 0 }, { 1.5, -2.4, 0 } }) do
		put("chairModernFrameCushion", g(17 + o[1], 0, 6 + o[2]), m, { yaw = o[3] })
	end
	put("desk", g(22.6, 0, -3), m, { yaw = -90, canCollide = true })
	put("laptop", g(22.6, 2.26, -3), m, { yaw = -90 })
	put("chairDesk", g(20.1, 0, -3), m, { yaw = 90 })
	put("pottedPlant", g(-6.5, 0, wallZ(1.42)), m, { scale = 1.2 })
	put("pottedPlant", g(22, 0, 14.5), m, { scale = 1.2 })
	lamp(m, g, -2, 7.8, 9, 30, 0.65)
	lamp(m, g, 12, 7.8, -11, 26, 0.6)
	lamp(m, g, 17, 7.8, 6, 18, 0.45)
	lamp(m, g, -17, 7.8, -3, 26, 0.55)
end

LAYOUT.penthouse = function(m, g)
	-- the master suite: the left third behind a wood wall, bed facing the view,
	-- a tub at the window
	local WOOD = Color3.fromRGB(150, 108, 72)
	part(m, { Name = "AptWall", Size = Vector3.new(0.5, 8.6, 7.1), CFrame = g(-11, 4.3, -13.05), Color = WOOD, Material = Enum.Material.WoodPlanks })
	part(m, { Name = "AptWall", Size = Vector3.new(0.5, 8.6, 25.7), CFrame = g(-11, 4.3, 6.05), Color = WOOD, Material = Enum.Material.WoodPlanks })
	put("bedDouble", g(-17.5, 0, wallZ(6.62 * 1.15)), m, { scale = 1.15 })
	for _, x in ipairs({ -22.1, -12.9 }) do
		put("cabinetBedDrawerTable", g(x, 0, wallZ(1.28)), m)
		put("lampRoundTable", g(x, 1.55, wallZ(1.28)), m)
	end
	put("rugSquare", g(-17.5, 0, -7.5), m, { scale = 1.2 })
	art(m, g, -17.5, 5.6, BACK + 0.07, 0, 5.5, 2.8, Color3.fromRGB(240, 110, 80))
	put("loungeDesignChair", g(-17.5, 0, 8), m)
	put("bathtub", g(-17.5, 0, 16), m)
	put("bookcaseClosedWide", g(-12.035, 0, 1), m, { yaw = -90 })
	put("pottedPlant", g(-12.8, 0, 11), m, { scale = 1.35 })
	put("pottedPlant", g(-22.5, 0, 2), m, { scale = 1.35 })
	-- the grand lounge: the TV on the suite wall, a sofa facing it, two chairs
	put("cabinetTelevisionDoors", g(-9.705, 0, 3), m, { yaw = 90, scale = 1.3 })
	put("televisionModern", g(-9.705, 1.82 * 1.3, 3), m, { yaw = 90, scale = 1.8 })
	art(m, g, -10.68, 5.4, -3.5, 90, 3, 3.6, Color3.fromRGB(255, 208, 70))
	art(m, g, -10.68, 5.4, 9.5, 90, 3, 3.6, Color3.fromRGB(240, 110, 80))
	put("rugRounded", g(-3.5, 0, 3), m, { yaw = 90, scale = 1.6 })
	put("tableCoffeeGlass", g(-3.5, 0, 3), m, { yaw = 90 })
	put("loungeDesignSofa", g(3, 0, 3), m, { yaw = -90 })
	put("loungeDesignChair", g(-3.5, 0, 8.6), m, { yaw = 180 })
	put("loungeDesignChair", g(-3.5, 0, -2.6), m)
	put("lampRoundFloor", g(3, 0, 7.6), m)
	put("lampRoundFloor", g(-8.5, 0, 12), m)
	-- the pool along the front glass, loungers facing it
	part(m, { Name = "PoolEdge", Size = Vector3.new(20, 0.5, 7), CFrame = g(7, 0.1, 15), Color = Color3.fromRGB(226, 220, 208), Material = Enum.Material.Marble })
	part(m, { Name = "PoolWater", Size = Vector3.new(18, 0.2, 5), CFrame = g(7, 0.32, 15), Color = Color3.fromRGB(70, 170, 220),
		Material = Enum.Material.Glass, Transparency = 0.25, CanCollide = false })
	part(m, { Name = "PoolGlow", Size = Vector3.new(18, 0.05, 5), CFrame = g(7, 0.24, 15), Color = Color3.fromRGB(60, 200, 255),
		Material = Enum.Material.Neon, Transparency = 0.6, CanCollide = false })
	for _, x in ipairs({ 8, 12.5 }) do put("loungeChairRelax", g(x, 0, 8.8), m) end
	-- the kitchen: a full run, an island of five, dining for six at the right window
	kitchenRun(m, g, "kitchenFridgeLarge", 3.06, 2.38, { "kitchenCabinet", "kitchenSink", "kitchenCabinet", "kitchenStove", "kitchenCabinet", "kitchenCabinet" }, true)
	for k = 0, 4 do
		put("kitchenBar", g(7 + k * 2.53, 0, -9), m, { yaw = 180, canCollide = true })
		put("stoolBarSquare", g(7 + k * 2.53, 0, -7.7), m, { yaw = 180 })
	end
	put("tableGlass", g(17, 0, -0.5), m, { canCollide = true, scale = 1.5 })
	for _, o in ipairs({ { -2.2, 2.6, 180 }, { 0, 2.6, 180 }, { 2.2, 2.6, 180 }, { -2.2, -2.6, 0 }, { 0, -2.6, 0 }, { 2.2, -2.6, 0 } }) do
		put("chairModernFrameCushion", g(17 + o[1], 0, -0.5 + o[2]), m, { yaw = o[3] })
	end
	-- the entry gallery left of the lift
	put("bookcaseClosedWide", g(-6.8, 0, wallZ(1.47)), m)
	put("pottedPlant", g(-9.8, 0, wallZ(1.42)), m, { scale = 1.35 })
	put("pottedPlant", g(21.5, 0, 14), m, { scale = 1.35 })
	lamp(m, g, -2, 7.8, 3, 34, 0.75)
	lamp(m, g, 12, 7.8, -11, 28, 0.6)
	lamp(m, g, 17, 7.8, -0.5, 20, 0.5)
	lamp(m, g, 7, 7.8, 15, 20, 0.5)
	lamp(m, g, -17.5, 7.8, -4, 28, 0.55)
	lamp(m, g, -17.5, 7.8, 12, 20, 0.45)
end

local FINISH = {
	studio = { Color3.fromRGB(200, 166, 124), Enum.Material.WoodPlanks },
	loft = { Color3.fromRGB(146, 108, 80), Enum.Material.WoodPlanks },
	penthouse = { Color3.fromRGB(226, 222, 214), Enum.Material.Marble },
}

function Apartments.destroyUnit(player)
	local u = units[player.UserId]
	if u then u:Destroy() end
	units[player.UserId] = nil
end

-- where the unit's lift door stand is (for arrival)
function Apartments.homeStand(player)
	local u = units[player.UserId]
	return u and u:GetAttribute("Stand")
end

function Apartments.buildUnit(player, tier)
	Apartments.destroyUnit(player)
	if not Downtown or not Downtown.RES then return nil end
	local t = Apartments.TIERS[tier]
	if not t then return nil end
	local R = Downtown.RES_SIZE
	local n = Apartments.floorOf(player, tier)
	local y0 = R.lobby + n * R.floor + 0.6
	local base = Downtown.RES * CFrame.new(0, y0, 0)
	local g = function(x, y, z) return base * CFrame.new(x, y, z) end
	local m = Instance.new("Model")
	m.Name = "Apt_" .. player.UserId
	m:SetAttribute("Owner", player.UserId)
	m:SetAttribute("Tier", tier)
	m.Parent = Downtown.folder
	local fin = FINISH[t.key]
	roundFloor(m, g, R.w, R.d, R.R, fin[1], fin[2])
	local hq = hqMod()
	if hq and hq.envelope then
		hq.envelope(function(props) return part(m, props) end, g, R.w, R.d, R.R, 0, R.floor - 1.3, nil)
	end
	-- the solid back wall (the building's service side: kitchens, the bathroom and
	-- bedheads stand against it, not against glass) with the lift you leave by in it
	local ch = R.floor - 1.3
	part(m, { Name = "AptBackWall", Size = Vector3.new(44.8, ch, 0.6), CFrame = g(0, ch / 2, BACK - 0.3), Color = WHITE })
	part(m, { Name = "AptLiftFrame", Size = Vector3.new(5.4, 8, 0.3), CFrame = g(0, 4, BACK + 0.15), Color = CHARCOAL, CanCollide = false })
	part(m, { Name = "AptLiftDoor", Size = Vector3.new(4.8, 7.6, 0.2), CFrame = g(0, 3.8, BACK + 0.3), Color = Color3.fromRGB(176, 178, 184),
		Material = Enum.Material.Metal, CanCollide = false })
	-- (left of the door: the fridge stands on the right)
	local btn = part(m, { Name = "AptLiftButton", Size = Vector3.new(0.5, 0.9, 0.2), CFrame = g(-3.4, 4.3, BACK + 0.1), Color = CHARCOAL, CanCollide = false })
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Go down"
	pp.ObjectText = "Lobby"
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 10
	pp.RequiresLineOfSight = false
	pp.Parent = btn
	pp.Triggered:Connect(function(p)
		if p ~= player then return end
		remotes.fade:FireClient(p, "out")
		task.delay(0.3, function()
			if p.Character then p.Character:PivotTo(Downtown.resLobbyStand + Vector3.new(0, 3, 0)) end
			remotes.fade:FireClient(p, "in")
		end)
	end)
	local ok, err = pcall(LAYOUT[t.key], m, g)
	if not ok then warn("[SV] apartment layout failed: " .. tostring(err)) end
	-- (0.04 over the tower's own floor plate, or the two z-fight; arrive well clear
	-- of the lift wall, or the camera settles inside it)
	m:SetAttribute("Stand", g(0, 3, -R.d / 2 + 12) * CFrame.Angles(0, math.pi, 0))
	-- local +Z is the tower's front (the road, the city): the view looks that way
	m:SetAttribute("View", g(0, 5.5, -R.d / 2 + 9) * CFrame.Angles(0, math.pi, 0))
	units[player.UserId] = m
	return m
end

-- ============ SELLING + GOING HOME ============
local function statusFor(player)
	local s = api.session(player)
	local plot = api.plotOf(player)
	local hq = plot and plot.hq and plot.hq.level or 1
	local owned = s and s.apt or 0
	local list = {}
	for _, t in ipairs(Apartments.TIERS) do
		local state, why = "buy", nil
		if owned >= t.id then state = "owned"
		elseif t.id > owned + 1 then state = "locked"; why = "Buy the " .. Apartments.TIERS[t.id - 1].name .. " first"
		elseif hq < t.minHQ then state = "locked"; why = "Unlocks at HQ level " .. t.minHQ end
		table.insert(list, { id = t.id, name = t.name, price = t.price, blurb = t.blurb, state = state, why = why,
			gate = t.gateHQ, bonus = math.floor(t.bonus * 100 + 0.5) })
	end
	return { tiers = list, apt = owned, cash = api.cash(player) and api.cash(player).Value or 0 }
end

local function goHome(player)
	local s = api.session(player)
	if not s or (s.apt or 0) < 1 then return false end
	if not units[player.UserId] then Apartments.buildUnit(player, s.apt) end
	local stand = Apartments.homeStand(player)
	if not stand then return false end
	remotes.fade:FireClient(player, "out")
	task.delay(0.3, function()
		if player.Character then player.Character:PivotTo(stand) end
		remotes.fade:FireClient(player, "in")
	end)
	return true
end
Apartments.goHome = goHome

local function buy(player, tierId)
	local s = api.session(player)
	local plot = api.plotOf(player)
	local t = Apartments.TIERS[tierId]
	if not (s and plot and t) then return end
	if (s.apt or 0) ~= t.id - 1 then return end
	if (plot.hq and plot.hq.level or 1) < t.minHQ then return end
	local cash = api.cash(player)
	if not cash or cash.Value < t.price then
		remotes.menu:FireClient(player, statusFor(player))
		return
	end
	cash.Value -= t.price
	s.apt = t.id
	s.lastBuy = os.clock()
	player:SetAttribute("Apt", s.apt)
	api.recompute(player)
	if api.refreshObjective then pcall(api.refreshObjective, player) end
	if api.refreshHqPad then pcall(api.refreshHqPad, plot) end
	local unit = Apartments.buildUnit(player, t.id)
	-- THE MOVE-IN: the camera rises up the tower to your floor, then you're home
	local R = Downtown.RES_SIZE
	local n = Apartments.floorOf(player, t.id)
	local floorY = (Downtown.RES * CFrame.new(0, R.lobby + n * R.floor + 5, 0)).Position.Y
	remotes.cinema:FireClient(player, {
		kind = "movein", name = t.name, bonus = math.floor(t.bonus * 100 + 0.5),
		tower = Downtown.RES.Position, facing = -Downtown.RES.LookVector, floorY = floorY,
		view = unit and unit:GetAttribute("View"), stand = unit and unit:GetAttribute("Stand"),
		gate = t.gateHQ,
	})
	task.delay(2.6, function()
		local stand = Apartments.homeStand(player)
		if stand and player.Character then player.Character:PivotTo(stand) end
	end)
	if api.telemetry then pcall(api.telemetry, player, "apartment_" .. t.key) end
end

-- ============ THE VIP (v4.2 home turf, 2) ============
-- once a day (UTC) an apartment owner finds a VIP outside the Residences. The
-- floor rises with the home: Studio STAR, Loft GENIUS, Penthouse GENIUS with
-- the talent roll at luck x2. `vipDay` is set at PICKUP, so an unclaimed VIP
-- just waits for your next visit that day; nothing piles up across days.
Apartments.VIP_FLOOR = { 3, 4, 4 }
Apartments.VIP_LUCK = { 1, 1, 2 }
local function today() return math.floor(os.time() / 86400) end
local vipAnnounced = {}          -- player -> the day we last texted them about a VIP
local function lib(name)
	local m = SSS:FindFirstChild(name)
	local ok, mod = pcall(function() return m and require(m) end)
	return ok and mod or nil
end
function Apartments.vipSpot(plotIndex)
	-- outside the Residences on the road side, one step apart per plot
	return Vector3.new(640 + 9 * (plotIndex or 1), 0, 36)
end
function Apartments.trySpawnVip(player, force)
	local s = api and api.session(player)
	if not s or not s.shipped or (s.apt or 0) < 1 then return false end
	if not force and s.vipDay == today() then return false end
	if player:GetAttribute("Carrying") then return false end
	local TD = lib("TalentDrop")
	if not (TD and TD.spawnVip) or TD.hasVip(player) then return false end
	local plot = api.plotOf(player)
	local apt = math.clamp(s.apt, 1, 3)
	local model = TD.spawnVip(player, Apartments.vipSpot(plot and plot.index), Apartments.VIP_FLOOR[apt], Apartments.VIP_LUCK[apt],
		function(p)
			local ss = api.session(p)
			if ss then ss.vipDay = today() end
			if api.telemetry then api.telemetry(p, "vip_pickup") end
		end)
	if model and vipAnnounced[player] ~= today() then
		vipAnnounced[player] = today()
		local ph = lib("Phone")
		if ph and ph.notice then
			ph.notice(player, "vip_desk", "Front desk", "The Residences",
				("A %s candidate is waiting outside your building downtown. Get them home before a headhunter does."):format(
					model:GetAttribute("TierName") or "VIP"))
		end
	end
	return model ~= nil
end

function Apartments.init(a)
	api = a
	task.spawn(function()
		while true do
			task.wait(20)
			for _, p in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(Apartments.trySpawnVip, p)
				if not ok then warn("[SV] VIP: " .. tostring(err)) end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p) vipAnnounced[p] = nil end)
	local m = SSS:FindFirstChild("Downtown")
	local ok, mod = pcall(function() return m and require(m) end)
	Downtown = ok and mod or nil
	local folder = RS:WaitForChild("SVRemotes")
	local function ev(name)
		local r = folder:FindFirstChild(name) or Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = folder
		return r
	end
	remotes.menu = ev("AptMenu")
	remotes.buy = ev("AptBuy")
	remotes.fade = ev("ScreenFade")
	remotes.cinema = ev("Cinema")
	remotes.buy.OnServerEvent:Connect(function(player, tierId)
		if typeof(tierId) == "number" then buy(player, tierId) end
	end)
	-- the sales desk and the residents' lift (built by Downtown.build)
	task.spawn(function()
		for _ = 1, 60 do
			if Downtown and Downtown.salesDesk and Downtown.resLiftButton then break end
			task.wait(0.5)
		end
		if not (Downtown and Downtown.salesDesk) then return end
		local pp = Instance.new("ProximityPrompt")
		pp.ActionText = "Buy an apartment"
		pp.ObjectText = "The Residences"
		pp.HoldDuration = 0
		pp.MaxActivationDistance = 12
		pp.RequiresLineOfSight = false
		pp.Parent = Downtown.salesDesk
		pp.Triggered:Connect(function(player) remotes.menu:FireClient(player, statusFor(player)) end)
		local lift = Instance.new("ProximityPrompt")
		lift.ActionText = "Go home"
		lift.ObjectText = "Residents' lift"
		lift.HoldDuration = 0
		lift.MaxActivationDistance = 11
		lift.RequiresLineOfSight = false
		lift.Parent = Downtown.resLiftButton
		lift.Triggered:Connect(function(player)
			if not goHome(player) then
				remotes.menu:FireClient(player, statusFor(player))
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(p) Apartments.destroyUnit(p) end)
end

-- the bot (SVDev "bot"): buy the next rung without the camera or the walk
function Apartments.botBuy(player)
	local s = api.session(player)
	local plot = api.plotOf(player)
	if not s or not plot then return false end
	local t = Apartments.TIERS[(s.apt or 0) + 1]
	local cash = api.cash(player)
	if not t or not cash or cash.Value < t.price or (plot.hq.level or 1) < t.minHQ then return false end
	cash.Value -= t.price
	s.apt = t.id
	player:SetAttribute("Apt", s.apt)
	api.recompute(player)
	if api.refreshHqPad then pcall(api.refreshHqPad, plot) end
	return true
end

-- after a save loads: publish the attribute and build the home
function Apartments.onLoad(player, s)
	s.apt = math.clamp(math.floor(tonumber(s.apt) or 0), 0, #Apartments.TIERS)
	player:SetAttribute("Apt", s.apt)
	if s.apt > 0 then task.defer(Apartments.buildUnit, player, s.apt) end
end

-- the sales desk, for the guide arrow
function Apartments.deskPosition()
	return Downtown and Downtown.salesDesk and Downtown.salesDesk.Position or nil
end

return Apartments
