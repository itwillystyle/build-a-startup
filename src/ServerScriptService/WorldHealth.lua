--[[ WorldHealth (10 Oct 2026): is the world you see the world you stand on?

	His recording, 10 Oct: he and the candidates stood waist-deep in the park. The
	lawn, walks and terraces were CanCollide and CanQuery false, floating up to 3.6
	studs above the one solid floor -- visible, walkable-looking, and not there.
	Nothing caught it because nothing looked.

	`sinking(root)` finds every surface like that: visible (Transparency < 0.5),
	flat and wide enough to stand on, near the ground, NOT solid, with its top more
	than SINK studs above the first solid thing under it. Things that are meant to be
	walked through (hedges, leaves, tents, the bus) are on ALLOW, each with why.
	Anything else it finds is a bug: make it solid, or put it on ALLOW with a reason.

	Run by the cloud smoke on every PR (tools/smoke_task.luau) and by the Studio
	scenario `health` (DevScenarios). ]]
local WorldHealth = {}

WorldHealth.SINK = 0.6          -- studs: deeper than this reads as sinking
WorldHealth.MAX_Y = 12          -- only surfaces near the ground (upper floors are the HQ's job)
WorldHealth.MAX_THICK = 2.5     -- a floor is a slab; anything taller is a wall, a tree or a building
WorldHealth.RADIUS = 620        -- the campus (outer ring road 596); the valley hills have their own wedges

-- walked through on purpose: name -> why (a part's own name, or its parent's)
WorldHealth.ALLOW = {
	ParkHedge = "a hedge: you push through it",
	ParkLeaf = "tree canopy", DistLeaf = "tree canopy",
	RoadVerge = "a grass strip 0.8 above the road edge; solid would snag cars",
	DropSoil = "planter soil, 0.8",
	SVP_Parasol = "a parasol", SVP_Bin = "a bin", SVP_Lamp = "a lamp", SVP_Bench = "a bench seat",
	Speaker = "stage speaker", TentCloth = "tent canvas", TentTable = "tent table",
	FoodShutter = "food truck", FoodCounter = "food truck", FoodCab = "food truck", FoodWheel = "food truck",
	BusBody = "the bus", BusRoof = "the bus", BusBand = "the bus", BusWheel = "the bus", body = "a parked car body",
	StopRoof = "bus stop roof", GateHutRoof = "gate hut roof",
	ParkPool = "water: PoolBed under it keeps it ankle-deep",
	FountainWater = "water", FountainBasin = "fountain basin (inside the solid lip)",
	-- the stand-ins built when a mesh pack is missing (the cloud smoke's build has no meshes)
	DistParasol = "a parasol (stand-in)", Leaf = "tree canopy (stand-in)",
	DistCarGlass = "a parked car's glass (stand-in)", DistTable = "a cafe table (stand-in)",
}

local function allowed(part)
	if part.Name:match("^LP_") then return "low-poly tree or bush: walked past, not on" end
	return WorldHealth.ALLOW[part.Name] or (part.Parent and WorldHealth.ALLOW[part.Parent.Name])
end

--[[ -> { found = n, checked = n, sinks = { { name, gap, x, z } } } (worst first).
	`skip` = instances the downward ray ignores (characters, the TalentRow). ]]
function WorldHealth.sinking(root, skip)
	local solid = RaycastParams.new()
	solid.FilterType = Enum.RaycastFilterType.Exclude
	solid.FilterDescendantsInstances = skip or {}
	solid.RespectCanCollide = true
	local worst, checked, i = {}, 0, 0
	for _, d in ipairs(root:GetDescendants()) do
		i += 1
		if i % 4000 == 0 then task.wait() end
		if d:IsA("BasePart") and not d.CanCollide and d.Transparency < 0.5 then
			local s, p = d.Size, d.Position
			local m = d:FindFirstAncestorWhichIsA("Model")
			local isChar = m and m:FindFirstChildOfClass("Humanoid")
			if not isChar and math.min(s.X, s.Z) >= 3 and s.Y <= WorldHealth.MAX_THICK and math.abs(d.CFrame.UpVector.Y) > 0.85
				and p.Y < WorldHealth.MAX_Y and Vector2.new(p.X, p.Z).Magnitude < WorldHealth.RADIUS and not allowed(d) then
				checked += 1
				local top = p.Y + s.Y / 2
				local hit = workspace:Raycast(Vector3.new(p.X, top + 0.05, p.Z), Vector3.new(0, -60, 0), solid)
				if hit and top - hit.Position.Y > WorldHealth.SINK then
					local key = d.Name
					local gap = math.floor((top - hit.Position.Y) * 10) / 10
					if not worst[key] or gap > worst[key].gap then
						worst[key] = { name = key, path = d:GetFullName(), gap = gap, x = math.floor(p.X), z = math.floor(p.Z) }
					end
				end
			end
		end
	end
	local list = {}
	for _, e in pairs(worst) do table.insert(list, e) end
	table.sort(list, function(a, b) return a.gap > b.gap end)
	return { checked = checked, found = #list, sinks = list }
end

return WorldHealth
