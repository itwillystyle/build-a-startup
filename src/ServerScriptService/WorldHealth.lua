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

--[[ THROUGH THE FLOORS (11 Oct 2026). His screenshot: on floor 7 he stood waist-deep
	in a blue floor with "a cone in it" -- the deck below's tent mesh, 3.9 studs up
	through floor 7, where the lift lets you off. `sinking` cannot see that: it looks
	for slabs near the ground, and this was a picture of one storey standing in the
	next, 90 studs up.

	For every HQ (each plot's Wafers folder), the floors you walk on are the tops of
	its Floor and Deck colliders. A visible mesh that starts well below one of those
	floors (a storey under it) and ends above it, over the floor's footprint, is
	poking through it. Pure rule: `pokes`. ]]
WorldHealth.POKE = 0.5          -- studs above a floor that count as through it
WorldHealth.BELOW = 2           -- a mesh starting this far under a floor belongs to a lower storey

function WorldHealth.pokes(meshBottom, meshTop, floorTop)
	return meshBottom < floorTop - WorldHealth.BELOW and meshTop > floorTop + WorldHealth.POKE
end

-- -> { checked = n floors, found = n, through = { { plot, mesh, floor, by } } } (worst first)
function WorldHealth.throughFloors(plots)
	local through, checked = {}, 0
	for _, plot in ipairs(plots:GetChildren()) do
		local hq = plot:FindFirstChild("Wafers")
		if hq then
			local floors, meshes = {}, {}
			for _, d in ipairs(hq:GetDescendants()) do
				if d:IsA("BasePart") then
					if (d.Name == "Floor" or d.Name == "Deck") and d.CanCollide then
						table.insert(floors, d)
					elseif d:IsA("MeshPart") and d.Transparency < 0.5 then
						table.insert(meshes, d)
					end
				end
			end
			checked += #floors
			local seen = {}
			for _, f in ipairs(floors) do
				local top = f.Position.Y + f.Size.Y / 2
				for _, m in ipairs(meshes) do
					local lo, hi = m.Position.Y - m.Size.Y / 2, m.Position.Y + m.Size.Y / 2
					local key = m:GetFullName() .. "@" .. math.floor(top)
					if not seen[key] and WorldHealth.pokes(lo, hi, top) then
						-- over the floor's footprint: the floor's centre inside the mesh's box, seen from above
						local l = m.CFrame:PointToObjectSpace(f.Position)
						if math.abs(l.X) <= m.Size.X / 2 and math.abs(l.Z) <= m.Size.Z / 2 then
							seen[key] = true
							table.insert(through, { plot = plot.Name, mesh = m.Parent.Name .. "." .. m.Name,
								floor = math.floor(top * 10) / 10, by = math.floor((hi - top) * 10) / 10 })
						end
					end
				end
			end
		end
	end
	table.sort(through, function(a, b) return a.by > b.by end)
	return { checked = checked, found = #through, through = through }
end

--[[ LIFT LANDINGS (11 Oct 2026). The lift to floor 8 put you down over nothing and
	you fell 13 studs (half-built storey, Wafers.lua `landable`). For every lift stop
	HQFloors knows ([plot] = { stops = { { id, stand = CFrame } } }), something solid
	must be under the spot it puts you, within FEET studs.
	-> { checked = n, found = n, bad = { { plot, stop, drop } } } ]]
WorldHealth.FEET = 2.5

function WorldHealth.liftLandings(lifts)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local skip = {}
	for _, pl in ipairs(game:GetService("Players"):GetPlayers()) do if pl.Character then table.insert(skip, pl.Character) end end
	params.FilterDescendantsInstances = skip
	local bad, checked = {}, 0
	for plotIndex, reg in pairs(lifts or {}) do
		for _, st in ipairs(reg.stops or {}) do
			checked += 1
			local from = st.stand.Position + Vector3.new(0, 1, 0)
			local hit = workspace:Raycast(from, Vector3.new(0, -60, 0), params)
			local drop = hit and (st.stand.Position.Y - hit.Position.Y) or 60
			if drop > WorldHealth.FEET then
				table.insert(bad, { plot = plotIndex, stop = st.id, drop = math.floor(drop * 10) / 10 })
			end
		end
	end
	return { checked = checked, found = #bad, bad = bad }
end

return WorldHealth
