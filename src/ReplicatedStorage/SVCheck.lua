--[[
	SVCheck -- one command that runs every check at once (v4.9).

	WHY THIS EXISTS. Four of the last five defects in this game were found the
	same way: Luke played, took a screenshot, sent it, and waited. The fixes
	were cheap. The ROUND TRIP was not.

	And each time, the check written afterwards immediately found the NEXT
	instance for free -- the overlap check found the quest card drawing over
	the Daily panel before he reported it, the blocked-button pass found a
	ProximityPrompt swallowed by the BAG tile, the footprint registry found 19
	more pieces of greenery on paving. The checks were never the expensive
	part. Having four of them, run by hand, in different datamodels, was.

	So this is all of them behind one line. In a Play session, CLIENT
	datamodel:

	    return require(game.ReplicatedStorage.SVCheck).run()

	Everything it reads is replicated to the client, so the UI and the world
	can be checked in the same call. It changes nothing except the camera,
	which it puts back.

	WHAT IT CANNOT SEE, stated here so nobody trusts it further than it goes:
	  * SERVER errors. LogService on the client only has the client's log.
	    Use get_console_output for the server side.
	  * Anything that needs a second player.
	  * Whether the game is any good.
]]

local SVCheck = {}

-- Roblox's documented low-end phone budget
local DRAW_CEIL, TRI_CEIL = 1000, 1000000
local MIN_SIDE, MIN_BITE = 8, 6
local CELL = 24

local VIEWS = {
	{ "hub across the ring", Vector3.new(0, 120, 430), Vector3.new(0, 20, 0) },
	{ "high over the campus", Vector3.new(0, 420, 700), Vector3.new(0, 40, 0) },
	{ "street by the districts", Vector3.new(220, 14, 300), Vector3.new(0, 20, 60) },
	{ "downtown", Vector3.new(600, 60, 120), Vector3.new(760, 30, 0) },
}

local GREEN = { "tree", "bush", "palm", "oak", "pine", "redwood", "eucalypt", "orchard", "grove", "shrub", "plant" }

local function isGreenery(inst)
	local n = inst.Name:lower()
	for _, w in ipairs(GREEN) do
		if string.find(n, w, 1, true) then return true end
	end
	return false
end

local function boxOf(inst)
	if inst:IsA("Model") then
		local ok, cf, ext = pcall(function()
			local a, b = inst:GetBoundingBox()
			return a, b
		end)
		if ok and ext then return cf.Position, ext end
	elseif inst:IsA("BasePart") then
		return inst.Position, inst.Size
	end
	return nil, nil
end

-- ---------------------------------------------------------------- 1. budget
local function checkBudget(say)
	local Stats = game:GetService("Stats")
	local RunService = game:GetService("RunService")
	local cam = workspace.CurrentCamera
	local wasType, wasCF, wasFov = cam.CameraType, cam.CFrame, cam.FieldOfView
	--[[ MEASURED: the first version of this reported identical numbers for all
		four views, which is the tell that the camera never moved. Setting
		CameraType once is not enough -- the default camera module takes it back.
		It has to be re-pinned every frame. ]]
	local pinTo, pinAt = wasCF.Position, wasCF.Position + wasCF.LookVector
	local hold = RunService.RenderStepped:Connect(function()
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = CFrame.lookAt(pinTo, pinAt)
		cam.Focus = CFrame.new(pinAt)
	end)
	local worstD, worstT, worstName = 0, 0, "?"
	local seenDraws = {}
	say("BUDGET   (ceiling %d draws / %dk triangles)", DRAW_CEIL, TRI_CEIL / 1000)
	for _, v in ipairs(VIEWS) do
		pinTo, pinAt = v[2], v[3]
		task.wait(1.6)
		local d, t = Stats.SceneDrawcallCount, Stats.SceneTriangleCount
		table.insert(seenDraws, d)
		if d > worstD then worstD, worstName = d, v[1] end
		worstT = math.max(worstT, t)
		say("   %-26s %4d draws   %7d tris", v[1], d, t)
	end
	hold:Disconnect()
	cam.CameraType, cam.CFrame, cam.FieldOfView = wasType, wasCF, wasFov
	--[[ THE TELL FOR FROZEN STATS. A minimised Studio window stops rendering and
		Stats keeps serving the last frame it drew, so four different cameras come
		back with the SAME number to the digit. Caught exactly that on 5 Oct: four
		views, 727 draws each, because the window was minimised. A low absolute
		number is not the signal -- identical numbers are. ]]
	local identical = true
	for _, d in ipairs(seenDraws) do
		if d ~= seenDraws[1] then identical = false break end
	end
	if identical and #seenDraws > 1 then
		say("   !! all %d views returned %d draws: the window is not rendering,", #seenDraws, worstD)
		say("      so these numbers are the last frame Studio drew, not a measurement")
		return false
	end
	local okD, okT = worstD <= DRAW_CEIL, worstT <= TRI_CEIL
	say("   worst: %d draws (%s), %d tris   %s", worstD, worstName, worstT,
		(okD and okT) and "OK" or "OVER BUDGET")
	-- a draw count of almost nothing means the window is minimised and these
	-- numbers are meaningless; say so rather than reporting a false pass
	if worstD < 40 then
		say("   !! the Studio window is not rendering -- these numbers are not real")
		return false
	end
	return okD and okT
end

-- ---------------------------------------------------------------- 2. the screen
local function checkUI(say)
	local pg = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then say("SCREEN   no PlayerGui"); return false end
	local viewport = workspace.CurrentCamera.ViewportSize

	local function paints(o)
		if (o:IsA("Frame") or o:IsA("TextButton") or o:IsA("TextLabel") or o:IsA("TextBox")
			or o:IsA("ImageLabel") or o:IsA("ImageButton") or o:IsA("ScrollingFrame"))
			and o.BackgroundTransparency < 0.95 then return true end
		if (o:IsA("ImageLabel") or o:IsA("ImageButton")) and o.Image ~= "" and o.ImageTransparency < 0.95 then return true end
		if (o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox"))
			and o.Text ~= "" and o.TextTransparency < 0.95 then return true end
		return false
	end
	local function chain(o)
		local n = o
		while n and n ~= pg do
			if n:IsA("GuiObject") and not n.Visible then return false end
			if n:IsA("ScreenGui") then return n.Enabled end
			n = n.Parent
		end
		return false
	end
	local function nameOf(o)
		local names, g = {}, o
		while g and g ~= pg do table.insert(names, 1, g.Name); g = g.Parent end
		return table.concat(names, ".")
	end

	local items = {}
	for _, g in ipairs(pg:GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled then
			for _, o in ipairs(g:GetDescendants()) do
				if o:IsA("GuiObject") and paints(o) and chain(o) then
					local p, s = o.AbsolutePosition, o.AbsoluteSize
					if s.X >= MIN_SIDE and s.Y >= MIN_SIDE
						and p.X + s.X > 0 and p.Y + s.Y > 0 and p.X < viewport.X and p.Y < viewport.Y then
						table.insert(items, { obj = o, gui = g, p = p, s = s })
					end
				end
			end
		end
	end

	-- drawn on top of each other, ACROSS different screens only: inside one
	-- ScreenGui the layout is somebody's decision, between two it is a bug
	local hits = {}
	for i = 1, #items do
		for j = i + 1, #items do
			local a, b = items[i], items[j]
			if a.gui ~= b.gui then
				local ox = math.min(a.p.X + a.s.X, b.p.X + b.s.X) - math.max(a.p.X, b.p.X)
				local oy = math.min(a.p.Y + a.s.Y, b.p.Y + b.s.Y) - math.max(a.p.Y, b.p.Y)
				if ox > MIN_BITE and oy > MIN_BITE then
					table.insert(hits, { area = ox * oy,
						line = ("      %s over %s  (%d x %d px)"):format(nameOf(a), nameOf(b), ox, oy) })
				end
			end
		end
	end
	table.sort(hits, function(x, y) return x.area > y.area end)

	--[[ And the one a paint-based check is blind to: a button covered by
		something invisible. "Hit" -- a transparent full-card TextButton -- ate
		every click on the quest card's X for a day, and the overlap pass said
		the screen was clean, because an invisible button paints nothing. ]]
	local blocked = {}
	for _, it in ipairs(items) do
		local o = it.obj
		if o:IsA("GuiButton") then
			local x = math.floor(o.AbsolutePosition.X + o.AbsoluteSize.X / 2)
			local y = math.floor(o.AbsolutePosition.Y + o.AbsoluteSize.Y / 2)
			local ok, stack = pcall(function() return pg:GetGuiObjectsAtPosition(x, y) end)
			if ok then
				local top
				for _, c in ipairs(stack) do
					if c:IsA("GuiButton") or (c:IsA("GuiObject") and c.Active) then top = c break end
				end
				if top and top ~= o then
					table.insert(blocked, ("      %s is covered by %s (ZIndex %d vs %d)")
						:format(nameOf(o), nameOf(top), top.ZIndex, o.ZIndex))
				end
			end
		end
	end

	say("SCREEN   %d painted elements, %dx%d", #items, viewport.X, viewport.Y)
	say("   drawn over each other: %d", #hits)
	for i = 1, math.min(6, #hits) do say(hits[i].line) end
	say("   buttons something will swallow: %d", #blocked)
	for i = 1, math.min(6, #blocked) do say(blocked[i]) end
	return #hits == 0 and #blocked == 0
end

-- ---------------------------------------------------------------- 3. the world
local function checkWorld(say)
	local HttpService = game:GetService("HttpService")
	local sv = workspace:FindFirstChild("SiliconValley")
	if not sv then say("WORLD    no SiliconValley folder"); return false end

	local zones = {}
	local raw = sv:GetAttribute("GroundZones")
	if raw then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok then
			for _, z in ipairs(decoded) do
				z.cf = CFrame.new(z.x, z.y, z.z) * CFrame.Angles(0, z.yaw, 0)
				table.insert(zones, z)
			end
		end
	end

	-- greenery standing on ground somebody paved
	local onPaving, byZone = 0, {}
	for _, rootName in ipairs({ "LowPolyWorld", "Valley" }) do
		local root = sv:FindFirstChild(rootName)
		if root then
			for _, inst in ipairs(root:GetDescendants()) do
				if (inst:IsA("Model") or inst:IsA("BasePart")) and isGreenery(inst)
					and not (inst.Parent and inst.Parent ~= root and isGreenery(inst.Parent)) then
					local pos, ext = boxOf(inst)
					if pos then
						local base = pos.Y - ext.Y / 2
						for _, z in ipairs(zones) do
							local lp = z.cf:PointToObjectSpace(pos)
							if math.abs(lp.X) <= z.hx and math.abs(lp.Z) <= z.hz
								and base >= z.y - 4 and base <= z.y + 10 then
								onPaving += 1
								byZone[z.n] = (byZone[z.n] or 0) + 1
								break
							end
						end
					end
				end
			end
		end
	end

	--[[ The early warning, and the only part of this that predicts rather than
		reports: paving nobody reserved. A registry only works if builders
		remember to call it, and remembering is not a mechanism. ]]
	local unclaimed, examples = 0, {}
	for _, folderName in ipairs({ "CampusDistricts", "CampusHub", "Downtown" }) do
		local folder = sv:FindFirstChild(folderName)
		if folder then
			for _, p in ipairs(folder:GetDescendants()) do
				if p:IsA("BasePart") and p.Size.X > 60 and p.Size.Z > 60 and p.Size.Y < 6 then
					local claimed = false
					for _, z in ipairs(zones) do
						if (Vector3.new(z.x, 0, z.z) - Vector3.new(p.Position.X, 0, p.Position.Z)).Magnitude < 6 then
							claimed = true
							break
						end
					end
					if not claimed then
						unclaimed += 1
						if #examples < 6 then
							table.insert(examples, ("      %s.%s at %.0f,%.0f  %.0f x %.0f")
								:format(folderName, p.Name, p.Position.X, p.Position.Z, p.Size.X, p.Size.Z))
						end
					end
				end
			end
		end
	end

	-- props grown into each other, on a grid so this stays a check somebody runs
	local cells, props = {}, {}
	for _, folderName in ipairs({ "CampusDistricts", "CampusHub", "Valley" }) do
		local folder = sv:FindFirstChild(folderName)
		if folder then
			local CS = game:GetService("CollectionService")
			for _, inst in ipairs(folder:GetDescendants()) do
				-- moving things pass through scenery constantly; that is traffic,
				-- not a build error
				local moves = CS:HasTag(inst, "TrafficCar") or CS:HasTag(inst, "SVStaff")
					or inst.Name:match("^RingCar") or inst.Name:match("^Walker")
				if inst:IsA("Model") and #inst:GetChildren() > 0 and inst.Parent == folder and not moves then
					local pos, ext = boxOf(inst)
					if pos and ext and ext.Y > 2 then
						local it = { inst = inst, pos = pos, ext = ext }
						table.insert(props, it)
						local key = ("%d:%d"):format(math.floor(pos.X / CELL), math.floor(pos.Z / CELL))
						cells[key] = cells[key] or {}
						table.insert(cells[key], it)
					end
				end
			end
		end
	end
	local grown, seen, shown = 0, {}, {}
	for _, a in ipairs(props) do
		local cx, cz = math.floor(a.pos.X / CELL), math.floor(a.pos.Z / CELL)
		for dx = -1, 1 do
			for dz = -1, 1 do
				for _, b in ipairs(cells[("%d:%d"):format(cx + dx, cz + dz)] or {}) do
					if a ~= b then
						local ka, kb = a.inst:GetDebugId(), b.inst:GetDebugId()
						local key = ka < kb and (ka .. kb) or (kb .. ka)
						if not seen[key] then
							local ox = (a.ext.X + b.ext.X) / 2 - math.abs(a.pos.X - b.pos.X)
							local oz = (a.ext.Z + b.ext.Z) / 2 - math.abs(a.pos.Z - b.pos.Z)
							local oy = (a.ext.Y + b.ext.Y) / 2 - math.abs(a.pos.Y - b.pos.Y)
							if ox > 2.5 and oz > 2.5 and oy > 2.5
								and ox > math.min(a.ext.X, b.ext.X) * 0.45
								and oz > math.min(a.ext.Z, b.ext.Z) * 0.45 then
								seen[key] = true
								grown += 1
								if #shown < 6 then
									table.insert(shown, ("      %s x %s at %.0f,%.0f")
										:format(a.inst.Name, b.inst.Name, a.pos.X, a.pos.Z))
								end
							end
						end
					end
				end
			end
		end
	end

	say("WORLD    %d reserved zones, %d props checked", #zones, #props)
	say("   greenery standing on paving: %d", onPaving)
	for k, v in pairs(byZone) do say("      %s %d", k, v) end
	say("   paving nobody reserved: %d", unclaimed)
	for _, l in ipairs(examples) do say(l) end
	say("   props grown into each other: %d", grown)
	for _, l in ipairs(shown) do say(l) end
	return onPaving == 0 and unclaimed == 0 and grown == 0
end

-- ---------------------------------------------------------------- 4. placement
--[[ THE PASS THAT REPLACED THE OUTLINE CHECK (v5.0).

	The outline is gone -- it never covered everything, and where it did land
	it did not earn its pixels. What took its place as the thing worth
	checking every build is the fault it kept being asked about instead: a
	tree standing in a road.

	This pass finds paving by SHAPE, not by name: broad, thin, horizontal and
	not green. That matters more than it sounds. The previous check read a
	list of reserved zone names, so it kept returning "clean" while the world
	grew paving it had never heard of -- 8 zones known out of 967 paved parts.
	A geometric test cannot go stale when somebody adds a builder.

	It runs on the CLIENT, so it cannot require ServerScriptService.Placement;
	the classifier is small enough to state twice, and stating it twice means
	the check is an independent witness rather than the same code grading its
	own homework. ]]
local function checkPlacement(say)
	local sv = workspace:FindFirstChild("SiliconValley")
	if not sv then say("PLACE    no SiliconValley"); return false end

	local SOFT = {
		[Enum.Material.Grass] = true, [Enum.Material.LeafyGrass] = true,
		[Enum.Material.Ground] = true, [Enum.Material.Mud] = true,
		[Enum.Material.Sand] = true, [Enum.Material.Snow] = true,
		[Enum.Material.Water] = true,
	}
	local function soft(p)
		if SOFT[p.Material] then return true end
		local c = p.Color
		return c.G > c.R + 0.06 and c.G > c.B + 0.06
	end

	local CS = game:GetService("CollectionService")
	local CELL = 16
	local hard, grid = {}, {}
	for _, d in ipairs(sv:GetDescendants()) do
		-- terrain is ground, not paving; it is tagged where it is built
		if d:IsA("BasePart") and not CS:HasTag(d, "SVTerrain") and d.Transparency <= 0.9
			and d.Size.Y <= 5 and d.Size.X * d.Size.Z >= 60
			and d.CFrame.UpVector.Y >= 0.9 and not soft(d) then
			table.insert(hard, d)
			local i, pos = #hard, d.Position
			local reach = math.max(d.Size.X, d.Size.Z) / 2
			for gx = math.floor((pos.X - reach) / CELL), math.floor((pos.X + reach) / CELL) do
				for gz = math.floor((pos.Z - reach) / CELL), math.floor((pos.Z + reach) / CELL) do
					local k = gx .. "," .. gz
					grid[k] = grid[k] or {}
					table.insert(grid[k], i)
				end
			end
		end
	end

	local WORDS = { "tree", "bush", "palm", "oak", "pine", "redwood", "eucalypt",
		"orchard", "grove", "shrub", "plant", "hedge" }
	--[[ whole words only: "RingStreet" contains "tree" as a substring, which
		is how the first version of this check reported the ring road as a
		tree standing in itself ]]
	local function green(n)
		local spaced = n:gsub("(%l)(%u)", "%1_%2"):gsub("(%a)(%d)", "%1_%2"):lower()
		local w = {}
		for x in spaced:gmatch("[%a]+") do
			if x == "pit" or x == "soil" then return false end   -- a TreePit is not a tree
			w[#w + 1] = x
		end
		for _, x in ipairs(w) do
			for _, p in ipairs(WORDS) do
				if x == p or x == p .. "s" then return true end
			end
		end
		return false
	end

	local checked, bad, worst, worstN, pits, elevated = 0, 0, 0, "", 0, 0
	for _, d in ipairs(sv:GetDescendants()) do
		if d.Name == "TreePit" then pits += 1 end
		if (d:IsA("Model") or d:IsA("BasePart")) and green(d.Name)
			and not d:GetAttribute("SVPitted")
			and not (d.Parent and green(d.Parent.Name)) then
			local pos, sz
			if d:IsA("Model") then
				local ok, c, e = pcall(function() local a, b = d:GetBoundingBox() return a, b end)
				if ok and e then pos, sz = c.Position, e end
			else
				pos, sz = d.Position, d.Size
			end
			-- a plant with a roof over it is in a room, not in a road
			local indoor = false
			if pos and sz then
				local rp = RaycastParams.new()
				rp.FilterType = Enum.RaycastFilterType.Exclude
				rp.FilterDescendantsInstances = { d }
				indoor = workspace:Raycast(pos + Vector3.new(0, sz.Y / 2 + 0.5, 0),
					Vector3.new(0, 40, 0), rp) ~= nil
			end
			--[[ nothing in the landscape stands 12 studs up, so anything that
				does is on a floor, a terrace or a roof: deliberate decor, and
				counted separately from the thing this gate is for ]]
			local up = pos and sz and (pos.Y - sz.Y / 2) > 12
			if up and not indoor then elevated += 1 end
			if pos and sz and sz.Y > 0.6 and not indoor and not up then
				checked += 1
				local base = pos.Y - sz.Y / 2
				local cell = grid[math.floor(pos.X / CELL) .. "," .. math.floor(pos.Z / CELL)]
				if cell then
					for _, i in ipairs(cell) do
						local p = hard[i]
						local top = p.Position.Y + p.Size.Y / 2
						if top >= base - 8 and top <= base + 10 then
							--[[ the TRUNK has to be inside the paving. A crown
								leaning over a footpath is what a street looks
								like, not a defect. ]]
							local lp = p.CFrame:PointToObjectSpace(Vector3.new(pos.X, p.CFrame.Position.Y, pos.Z))
							local dx = p.Size.X / 2 - math.abs(lp.X)
							local dz = p.Size.Z / 2 - math.abs(lp.Z)
							-- 0.3: a trunk on the kerb line is kerbside, not in the road
							if dx > 0.3 and dz > 0.3 then
								bad += 1
								local pen = math.min(dx, dz)
								if pen > worst then worst, worstN = pen, d.Name .. " on " .. p.Name end
								break
							end
						end
					end
				end
			end
		end
	end

	--[[ FURNITURE IN FURNITURE (added 5 Oct). The greenery gate above caught a
		tree in a road; it said nothing about a coffee machine in a counter,
		which is the same fault one storey up. Both of this room's faults were
		measurable and neither was measured, so they shipped.

		Two overlaps are MEANT to happen and are excluded by shape rather than
		by name: a seat tucked under a table, and anything standing ON another
		piece (its base at about the other's top). Everything else that shares
		volume is a mistake. ]]
	--[[ FURNITURE IN FURNITURE.

		The first version of this gate compared axis-aligned sizes against
		world-axis distances, which is simply wrong for anything rotated: a
		bookcase turned 90 degrees has its depth measured as its width. Tested
		against the penthouse it reported a bookcase 1.16 studs inside the TV
		cabinet; the exact test says they are 3.3 studs apart and never touch.
		A gate that invents faults is worse than no gate, because the next
		person spends an hour moving furniture that was already right.

		So it is a real separating-axis test now, on the oriented boxes. Two
		overlaps are MEANT to happen and are excluded by shape rather than by
		name: a seat tucked under a table, and anything standing ON another
		piece. It also covers the whole valley, not just Plots -- the
		apartments live downtown and the first version never looked at them. ]]
	local SEAT = { chair = 1, stool = 1, sofa = 1, bench = 1, lounge = 1, lounger = 1, bed = 1 }
	local TABLE = { table = 1, desk = 1, bar = 1, counter = 1, island = 1 }
	local function anyOf(n, set)
		for w in n:gsub("(%l)(%u)", "%1_%2"):lower():gmatch("[%a]+") do
			if set[w] then return true end
		end
		return false
	end

	-- separation along the 15 candidate axes; 0 means they do not touch
	local function sat(a, b)
		local as, bs = a.Size / 2, b.Size / 2
		local R = a.CFrame:ToObjectSpace(b.CFrame)
		local m = { R.XVector, R.YVector, R.ZVector }
		local best = math.huge
		local function axis(ax, ra, rb)
			local dd = math.abs(R.Position:Dot(ax))
			if dd > ra + rb then return false end
			best = math.min(best, ra + rb - dd)
			return true
		end
		for _, ax in ipairs({ Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }) do
			local ra = math.abs(as.X * ax.X) + math.abs(as.Y * ax.Y) + math.abs(as.Z * ax.Z)
			local rb = math.abs(bs.X * m[1]:Dot(ax)) + math.abs(bs.Y * m[2]:Dot(ax)) + math.abs(bs.Z * m[3]:Dot(ax))
			if not axis(ax, ra, rb) then return 0 end
		end
		for i, ax in ipairs(m) do
			local ra = math.abs(as.X * ax.X) + math.abs(as.Y * ax.Y) + math.abs(as.Z * ax.Z)
			local rb = (i == 1 and bs.X) or (i == 2 and bs.Y) or bs.Z
			if not axis(ax, ra, rb) then return 0 end
		end
		return best
	end

	--[[ WHAT COUNTS AS FURNITURE: WHERE IT WAS PLACED, not how big it is.

		The size bound was the second wrong answer in a row here. Bounding by
		name let a tower into a furniture check; bounding by size (<=10 studs)
		then let CampusDistricts' DistCar in -- ONE Model holding 94 cars' parts
		-- so the gate compared one car's wheel to another car's wheel and
		reported 859 faults out of 891 pieces.

		Worse, it had reported ONE fault for the same world a minute earlier,
		because the districts had not finished building when I read it. An
		instrument whose answer depends on WHEN you run it is not an instrument,
		and it is why three reports in a row said clean.

		Every fault he has photographed has been furniture INSIDE a building. So
		the set is the interiors, named by the folders the placers actually write
		into: a plot's Garage, Rooms, Placed and Wafers, plus the downtown
		apartments. Street decor, traffic and campus grounds are not furniture
		and have their own gates above. ]]
	local interiors = {}
	do
		local plots = sv:FindFirstChild("Plots")
		if plots then
			for _, plot in ipairs(plots:GetChildren()) do
				for _, n in ipairs({ "Garage", "Rooms", "Placed", "Wafers" }) do
					local f = plot:FindFirstChild(n)
					if f then interiors[#interiors + 1] = f end
				end
			end
		end
		local dt = sv:FindFirstChild("Downtown")
		if dt then
			for _, d in ipairs(dt:GetChildren()) do
				if d.Name:sub(1, 4) == "Apt_" then interiors[#interiors + 1] = d end
			end
		end
	end

	-- a loose sanity guard, not the definition: the largest real piece in the
	-- game is a 7.6-stud double bed, so anything past 12 spans a room
	local FURN_MAX = 12

	--[[ PROP OR STRUCTURE -- one predicate, so nothing can be neither.

		Restricting this gate to MeshParts was the THIRD version of the same
		blindness. A Terrafab studio floor holds zero MeshParts and seventeen
		kinds of Part -- Metrology, Scope, FOUP, Stool, the OHT rail -- so the
		pass read "clean" for that format while checking none of its interior.
		Measured, not assumed: 0 meshes, 17 Part types.

		So the split is by shape. Structure is a Part taller than two studs
		that is not something props stand on; everything else inside a
		building, mesh or Part, is a prop. The two sets are complements, which
		is the property that stops a whole asset family falling through the
		gap between them again. ]]
	local SKIP_STRUCT = { Floor = 1, FloorPlate = 1, FloorCorner = 1, AptFloor = 1,
		ContactShadow = 1, HirePad = 1, HQPad = 1, Path = 1, CampusSlab = 1, Deck = 1 }
	local function structural(d)
		return not d:IsA("MeshPart") and d.Size.Y > 2 and not SKIP_STRUCT[d.Name]
	end

	local furn, walls = {}, {}
	for _, root in ipairs(interiors) do
		for _, d in ipairs(root:GetDescendants()) do
			-- the class test has to come FIRST: a Folder has no Size, and reading
			-- it threw the whole pass away on the first run
			if d:IsA("BasePart")
				and d.Name:sub(1, 2) ~= "D_" and d.Name:sub(1, 2) ~= "W_" and d.Name:sub(1, 2) ~= "T_"
				and d.Name:sub(1, 3) ~= "LP_" and d.Name:sub(1, 2) ~= "HQ"
			then
				-- a person is not furniture; a rig may sit under a Folder, so the
				-- ancestor lookup has to tolerate there being no Model at all
				local m = d:FindFirstAncestorOfClass("Model")
				if not (m and m:FindFirstChildOfClass("Humanoid")) then
					if structural(d) then
						walls[#walls + 1] = d
					elseif d.Size.Y > 0.3 and math.max(d.Size.X, d.Size.Y, d.Size.Z) <= FURN_MAX then
						furn[#furn + 1] = d
					end
				end
			end
		end
	end

	--[[ Parts of ONE object are allowed to interpenetrate -- that is how the
		object is built, and a desk's drawer inside its own carcass is not a
		fault. A piece belongs to its nearest Model, EXCEPT where that Model is
		the room itself: a wafer storey holds every piece on that floor flat, so
		treating it as one object would blind the gate completely. ]]
	local function objectOf(p)
		local m = p:FindFirstAncestorOfClass("Model")
		if not m or m.Name:match("^L%d+_") then return nil end
		return m
	end

	local jam, worstJam, worstJamN = 0, 0, ""
	for i = 1, #furn do
		for j = i + 1, #furn do
			local a, b = furn[i], furn[j]
			local oa, ob = objectOf(a), objectOf(b)
			if (a.Position - b.Position).Magnitude < 12 and not (oa and oa == ob) then
				local stacked = math.abs((a.Position.Y - a.Size.Y / 2) - (b.Position.Y + b.Size.Y / 2)) < 0.4
					or math.abs((b.Position.Y - b.Size.Y / 2) - (a.Position.Y + a.Size.Y / 2)) < 0.4
				local tuck = (anyOf(a.Name, SEAT) and anyOf(b.Name, TABLE))
					or (anyOf(b.Name, SEAT) and anyOf(a.Name, TABLE))
				if not stacked and not tuck then
					local pen = sat(a, b)
					if pen > 0.4 then
						jam += 1
						if pen > worstJam then worstJam, worstJamN = pen, a.Name .. " in " .. b.Name end
					end
				end
			end
		end
	end

	--[[ FURNITURE BURIED IN STRUCTURE -- the test that should have existed
		three days ago, and the reason three reports in a row said "clean"
		while he was looking at furniture in a wall.

		Everything I wrote tested furniture against OTHER FURNITURE. The faults
		were furniture against WALLS, and two separate mistakes hid them:

		  1. The collision walls are INVISIBLE (Transparency 1 once the shell
		     mesh is present), and every sweep I wrote skipped transparent
		     parts. So in the only configuration that ships, the walls were
		     not in the comparison set at all.

		  2. I judged depth in absolute studs and called 0.82 "minor". On a
		     1.47-deep bookcase that is 56% of it inside the glass. The number
		     that matters is the FRACTION of the piece that is buried, not the
		     stud count.

		Floors, pads and rugs are excluded because things stand on them, and
		ContactShadow is excluded because it is a fake-AO disc deliberately
		placed under a prop. ]]
	local buried, worstB, worstBN = 0, 0, ""
	for _, f in ipairs(furn) do
		local thin = math.min(f.Size.X, f.Size.Y, f.Size.Z)
		local of = objectOf(f)
		for _, w in ipairs(walls) do
			-- a load port bolted to its own tool is the machine, not a burial:
			-- the same-object rule has to apply here too, or grouping a
			-- machine silences the jam gate and leaves this one shouting
			if (f.Position - w.Position).Magnitude < 14 and not (of and of == objectOf(w)) then
				local pen = sat(f, w)
				if pen > 0.3 and pen / thin > 0.2 then
					buried += 1
					if pen > worstB then
						worstB = pen
						worstBN = ("%s %.0f%% into %s"):format(f.Name, pen / thin * 100, w.Name)
					end
				end
			end
		end
	end

	--[[ FURNITURE THROUGH THE GLASS -- the check that would have caught the
		fault he photographed three times while every other pass read clean.

		Nothing inside the game can see where a building's glass is. It is
		baked into the shell mesh, which ships CanQuery = false with Box
		collision, so raycasts miss it, collision misses it, and part-versus-
		part sweeps have nothing to compare against. Every test I wrote before
		this one was therefore asking a question the geometry could not answer.

		The glass line is an arithmetic fact instead: a wafer's radius minus
		the path's inset, which WaferPlan now owns. So the assertion is that
		every furniture corner lies between the inner glass and the outer
		glass of its own wafer -- no collision needed, and it is exact. ]]
	local glassOut, glassIn, glassWorst, glassWorstN = 0, 0, 0, ""
	do
		local okP, WP = pcall(function()
			return require(game:GetService("ReplicatedStorage"):FindFirstChild("WaferPlan")
				or game:GetService("ServerScriptService"):FindFirstChild("WaferPlan"))
		end)
		local plots = sv:FindFirstChild("Plots")
		if okP and WP and WP.INSET and plots then
			for _, plot in ipairs(plots:GetChildren()) do
				local wf = plot:FindFirstChild("Wafers")
				local pv = plot:GetAttribute("Pivot")
				if wf and pv then
					-- which path is this plot built in? read it off a shell mesh
					local path
					for _, seg in ipairs(wf:GetChildren()) do
						for _, d in ipairs(seg:GetDescendants()) do
							if d:IsA("MeshPart") and WP.INSET[d.Name:sub(1, 2)] then
								path = d.Name:sub(1, 2)
								break
							end
						end
						if path then break end
					end
					if path then
						for _, seg in ipairs(wf:GetChildren()) do
							local L = tonumber(seg.Name:match("^L(%d+)"))
							local pc = L and WP.PIECES[L]
							if pc and pc.kind == "segment" then
								local R = WP.GEO.WAFER[pc.wafer].r
								local rout = R - WP.INSET[path] - WP.GLASS_BAND
								local rin = R - WP.GEO.DEPTH + 0.6
								for _, d in ipairs(seg:GetDescendants()) do
									if d:IsA("MeshPart") and d.Name:sub(1, 2) ~= path
										and d.Size.Y > 0.3
										and math.max(d.Size.X, d.Size.Y, d.Size.Z) <= 10 then
										local far, near = 0, math.huge
										for ix = -1, 1, 2 do
											for iz = -1, 1, 2 do
												local q = pv:PointToObjectSpace(
													d.CFrame * Vector3.new(ix * d.Size.X / 2, 0, iz * d.Size.Z / 2))
												local rr = math.sqrt(q.X * q.X + q.Z * q.Z)
												far = math.max(far, rr)
												near = math.min(near, rr)
											end
										end
										if far > rout + 0.05 then
											glassOut += 1
											if far - rout > glassWorst then
												glassWorst = far - rout
												glassWorstN = d.Name .. " out of " .. seg.Name
											end
										elseif near < rin - 0.05 then
											glassIn += 1
											if rin - near > glassWorst then
												glassWorst = rin - near
												glassWorstN = d.Name .. " through the courtyard glass in " .. seg.Name
											end
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end

	say("PLACE    %d hard surfaces found by shape, %d greenery checked, %d tree pits",
		#hard, checked, pits)
	say("   furniture inside furniture: %d  (of %d pieces)", jam, #furn)
	if jam > 0 then say("      worst %.2f studs: %s", worstJam, worstJamN) end
	say("   furniture buried in a wall: %d", buried)
	if buried > 0 then say("      worst %.2f studs: %s", worstB, worstBN) end
	say("   furniture through the glass: %d out, %d in", glassOut, glassIn)
	if glassOut + glassIn > 0 then say("      worst %.2f studs: %s", glassWorst, glassWorstN) end
	say("   greenery standing in paving: %d", bad)
	if bad > 0 then say("      worst %.1f studs: %s", worst, worstN) end
	if elevated > 0 then say("   (%d on terraces and interior floors, not counted)", elevated) end
	return bad == 0 and jam == 0 and buried == 0 and glassOut == 0 and glassIn == 0
end

-- ---------------------------------------------------------------- 5. client errors
local function checkErrors(say)
	local ok, history = pcall(function() return game:GetService("LogService"):GetLogHistory() end)
	if not ok then say("ERRORS   LogService unavailable from here"); return true end
	local errs, warns, shown = 0, 0, {}
	for _, e in ipairs(history) do
		if e.messageType == Enum.MessageType.MessageError then
			errs += 1
			if #shown < 6 then table.insert(shown, "      " .. e.message:sub(1, 150)) end
		elseif e.messageType == Enum.MessageType.MessageWarning then
			warns += 1
		end
	end
	say("ERRORS   %d errors, %d warnings in the CLIENT log", errs, warns)
	for _, l in ipairs(shown) do say(l) end
	say("   (server log is not visible from here -- use get_console_output)")
	return errs == 0
end

-- ---------------------------------------------------------------- the visual sweep
--[[ EVERY CHECK ABOVE READS DATA. None of them can see "the boxes look
	awkward" or "this reads as slop", because those are not properties of the
	data -- they are properties of the rendered image, and until now the only
	thing in this project that ever looked at the rendered image was Luke,
	one screenshot at a time, after the fact.

	So: a fixed set of framings, the same ones every build, aimed at the places
	bugs actually live -- inside the garage where the furniture is, the lobby,
	the street, and a shot deliberately composed with something between the
	camera and an outlined object, because that is where the outline leaks.

	Usage, one shot at a time so the capture is reliable:
	    local C = require(game.ReplicatedStorage.SVCheck)
	    C.shot(1)        -- returns its name; screenshot; then C.shot(2) ...
	    C.endShots()     -- puts the camera, the character and the HUD back
]]
--[[ Framings found by hand on 5 Oct and frozen here. The first draft put the
	camera at z 26, which is OUTSIDE the garage door and looks straight into
	the tower ring -- it showed a wall of building and none of the furniture
	anybody was asking about. The garage interior is x +-18, z +-15, floor top
	y 1, roof y 14, so a camera has to live inside that box. ]]
SVCheck.SHOTS = {
	{ "garage: desk and laptop", { 0, 6, 11 }, { 0, 4.3, -15 }, 62, true },
	{ "garage: the box corner", { -8, 5.5, 7 }, { 16, 3, -14 }, 60, true },
	{ "garage: the pads and the floor", { 5, 3.2, 12 }, { -11, 1.2, 3 }, 68, true },
	{ "garage: from the seat", { 3, 4.6, -5 }, { 0, 4.0, -12 }, 55, true },
	{ "the plot from the street", { 0, 16, 110 }, { 0, 24, 0 }, 60, false },
	{ "street, props close", { -72, 7, 70 }, { -72, 5, -60 }, 70, false },
	{ "the hub, wide", { 0, 90, 360 }, { 0, 20, -40 }, 60, false },
}

local shotState = nil

function SVCheck.shot(i)
	local RunService = game:GetService("RunService")
	local player = game:GetService("Players").LocalPlayer
	local spec = SVCheck.SHOTS[i]
	if not spec then return "no shot " .. tostring(i) end
	local plots = workspace:FindFirstChild("SiliconValley")
	plots = plots and plots:FindFirstChild("Plots")
	local pf = plots and plots:FindFirstChild("Plot" .. tostring(player:GetAttribute("Plot")))
	local pivot = pf and pf:GetAttribute("Pivot")
	if not pivot then return "no plot yet" end

	if not shotState then
		local cam = workspace.CurrentCamera
		shotState = { cam = cam, type = cam.CameraType, cf = cam.CFrame, fov = cam.FieldOfView, gui = {} }
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		shotState.root = root and root.CFrame or nil
		for _, g in ipairs(player.PlayerGui:GetChildren()) do
			if g:IsA("ScreenGui") then shotState.gui[g] = g.Enabled end
		end
	end

	local name, from, to, fov, hideHud = spec[1], spec[2], spec[3], spec[4], spec[5]
	local P = function(v) return pivot:PointToWorldSpace(Vector3.new(v[1], v[2], v[3])) end
	local a, b = P(from), P(to)
	--[[ Outlines anchor on the CHARACTER, not the camera, so the character has to
		stand where the shot is taken or half the frame has no line. But standing
		them AT the camera fills the foreground with their own avatar -- the first
		sweep came back with a black mass across the bottom of every garage shot,
		and it was his own character at point-blank range. Stand them there and
		make them invisible locally. ]]
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then root.CFrame = CFrame.new(a - Vector3.new(0, 2, 0)) end
	if char then
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = 1 end
		end
		shotState.hidChar = true
	end
	for g, _ in pairs(shotState.gui) do
		if g.Parent then g.Enabled = not hideHud end
	end
	if shotState.conn then shotState.conn:Disconnect() end
	local cam = workspace.CurrentCamera
	shotState.conn = RunService.RenderStepped:Connect(function()
		cam.CameraType = Enum.CameraType.Scriptable
		cam.FieldOfView = fov
		cam.CFrame = CFrame.lookAt(a, b)
		cam.Focus = CFrame.new(b)
	end)
	task.wait(1.2)
	return ("shot %d/%d  %s"):format(i, #SVCheck.SHOTS, name)
end

function SVCheck.endShots()
	if not shotState then return "no sweep running" end
	if shotState.conn then shotState.conn:Disconnect() end
	local cam = shotState.cam
	cam.CameraType, cam.CFrame, cam.FieldOfView = shotState.type, shotState.cf, shotState.fov
	local player = game:GetService("Players").LocalPlayer
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and shotState.root then root.CFrame = shotState.root end
	if char and shotState.hidChar then
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = 0 end
		end
	end
	for g, on in pairs(shotState.gui) do
		if g.Parent then g.Enabled = on end
	end
	shotState = nil
	return "sweep ended, camera and HUD restored"
end

-- ---------------------------------------------------------------- run
function SVCheck.run()
	local out = {}
	local function say(f, ...)
		table.insert(out, select("#", ...) > 0 and string.format(f, ...) or f)
	end
	say("SVCheck  %s", os.date("%Y-%m-%d %H:%M"))
	say("")
	local results = {}
	for _, pass in ipairs({
		{ "budget", checkBudget }, { "screen", checkUI },
		{ "world", checkWorld }, { "placement", checkPlacement }, { "errors", checkErrors },
	}) do
		local ok, res = pcall(pass[2], say)
		results[pass[1]] = ok and res or false
		if not ok then say("%s CHECK ITSELF FAILED: %s", pass[1]:upper(), tostring(res)) end
		say("")
	end
	local bad = {}
	for name, good in pairs(results) do
		if not good then table.insert(bad, name) end
	end
	table.sort(bad)
	say(#bad == 0 and "VERDICT  clean" or ("VERDICT  look at: " .. table.concat(bad, ", ")))
	return table.concat(out, "\n")
end

return SVCheck
