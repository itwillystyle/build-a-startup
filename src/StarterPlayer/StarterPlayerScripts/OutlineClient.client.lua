--[[
	OutlineClient -- the black line round discrete objects (v4.7.1).

	THREE THINGS WERE WRONG, reported 4 Oct ("the model doesn't render the
	shape... multiple objects that don't have the filter on it... depending
	whether I zoom my camera in and out"). All three were mine, and the first
	was an assumption I never measured.

	1. THE BUDGET WAS 18. I wrote that from a half-remembered claim that Roblox
	   only renders about thirty Highlights at once. Benched it: 240 Highlights
	   on 240 models all drew, with no dropouts. There is no cap worth
	   designing around at this scale.

	   What there IS, measured the same run: each Highlight costs EXACTLY ONE
	   EXTRA DRAW CALL (242 on = 288 draw calls, 242 off = 46). The campus
	   already spends ~250 of the ~1000 a phone can afford, so the real ceiling
	   is a couple of hundred, not eighteen. BUDGET is 160.

	2. THE SET MOVED WITH THE CAMERA. Nearest-to-camera inside 150 studs means
	   zooming out re-picks everything, so lines popped on and off as he moved
	   the camera without moving. It is anchored to the CHARACTER now, and uses
	   hysteresis -- in at IN_R, out at OUT_R -- so an object on the boundary
	   cannot flicker between frames either.

	3. IT ONLY KNEW ABOUT PEOPLE AND TRAFFIC, so the world around them had no
	   line and the few that did looked like a glitch rather than a style.
	   Trees, parked cars, the player's own car and the street props are tagged
	   SVOutline at build time now.

	WHAT STILL CANNOT BE DONE, and it is worth writing down because it is the
	reason this is not simply "on for everything":

	  * A Highlight outlines a SILHOUETTE, not edges. On a 200-part building it
	    draws one line round the whole thing and nothing round its features --
	    useless up close, which is why architecture is not in the set.
	  * It is per-object. There is no post-process outline in Roblox at all, so
	    "a filter over everything" is not a thing the engine offers. 13,217
	    parts would be 13,217 draw calls.

	So the rule is: things you could pick up, walk round or run over get a
	line. The ground and the buildings they stand on do not.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

--[[ v4.9 THE CUTOFF WAS THE BUG, and my own cost estimate was why it existed.

	Reported 4 Oct with a screenshot: outlines stop at a visible ring and the far
	half of the view is drawn plain. Measured live at that moment: 556 objects
	tagged, 41 outlined, 527 tagged objects IN FRAME past the 240-stud cutoff.

	That cutoff came from my own measurement of "1 draw call per Highlight".
	Re-measured by outlining every tagged object and reading the counter:

	    street level, districts   425 -> 609 draws   (+184 for 513 outlines)
	    hub, across the ring      530 -> 744         (+214)
	    high over the campus      570 -> 877         (+307)

	0.61 draw calls each, not 1.0 -- occluded and off-screen adornees cost
	nothing. The worst view found lands at 877 against Roblox's documented
	1000-call phone budget, so the cutoff was buying headroom nobody needed.
	Triangles barely moved: 839k -> 909k.

	So the reach goes out to MAX_R, and -- the part that actually answers the
	complaint -- the outline FADES over the last stretch instead of stopping
	dead. There is no visible ring at any reach.

	The reach is adaptive too. That 877 was a ONE-player server; six players at
	thirty staff each adds ~180 tagged objects, about +110 calls, which is on
	the ceiling rather than under it. So rather than guess a safe constant, the
	reach watches the real draw count and pulls in when the frame gets dear.
	Because of the fade, pulling in is invisible: those outlines had already
	faded to nothing. ]]
local BUDGET = 1100                 -- the reach and the draw ceiling are the real limiters
local MAX_R, MIN_R = 820, 200
local FADE = 0.26                   -- the outer quarter of the reach fades away
local DRAW_CEIL = 880
local DRAW_EASE = 120
local reach = MAX_R
local LINE = Color3.fromRGB(26, 24, 30)
--[[ TWO TIERS, and the order matters. Tier 1 is what you are looking at and
	chasing -- people, vehicles, trees. Tier 2 is the street itself: lamps,
	benches, bins, bollards, parasols. Tier 1 fills the budget first, so a
	street full of benches can never take the line off the candidate you are
	carrying home. ]]
local TIER1 = { "SVOutline", "SVStaff", "TrafficCar" }
local TIER2 = { "SVOutline2" }

--[[ TIER 3, THE SCENERY -- and the answer to "it is still not on everything".

	Measured 5 Oct. Two reasons things had no line, and neither was the budget:

	  1. THE 4,568 HILL TREES ARE BasePARTS, not Models. They live as loose
	     parts under LowPolyWorld.HillTrees, and every gather in this file
	     tested m:IsA("Model"), so all 4,568 were skipped silently. A Highlight
	     adorns a BasePart perfectly well; nobody had ever pointed one at them.
	  2. 454 MODELS WERE NEVER TAGGED AT ALL -- 327 in Valley (palms, orchard,
	     the landmarks), 124 in Plots (campus architecture), plus Downtown and
	     KenneyCity. CampusHub and CampusDistricts were already complete, which
	     is why the campus looked right and nothing else did.

	Both are fixed here rather than in five builder files, because this list is
	purely a rendering concern and the objects are STATIC. Their positions are
	read once and cached, so a refresh is a cheap distance test against an
	array instead of thousands of GetPivot calls. ]]
local scenery = {}               -- { instance, position } for everything static
local sceneryReady = false

local function cachePos(inst)
	if inst:IsA("BasePart") then return inst.Position end
	local ok, cf = pcall(function() return inst:GetPivot().Position end)
	return ok and cf or nil
end

local function buildScenery()
	local sv = workspace:FindFirstChild("SiliconValley")
	if not sv then return false end
	local hills = sv:FindFirstChild("LowPolyWorld")
	hills = hills and hills:FindFirstChild("HillTrees")
	if not hills then return false end
	table.clear(scenery)
	-- the hill trees: loose parts, the whole reason the far hills were bare
	for _, part in ipairs(hills:GetChildren()) do
		if part:IsA("BasePart") then
			table.insert(scenery, { part, part.Position })
		end
	end
	-- and every model nobody tagged
	for _, name in ipairs({ "Valley", "Plots", "Downtown", "KenneyCity" }) do
		local folder = sv:FindFirstChild(name)
		if folder then
			for _, m in ipairs(folder:GetDescendants()) do
				if m:IsA("Model") and #m:GetChildren() > 0
					and not CollectionService:HasTag(m, "SVOutline")
					and not CollectionService:HasTag(m, "SVOutline2")
					and not CollectionService:HasTag(m, "SVStaff")
					and not CollectionService:HasTag(m, "TrafficCar") then
					local pos = cachePos(m)
					if pos then table.insert(scenery, { m, pos }) end
				end
			end
		end
	end
	sceneryReady = #scenery > 0
	return sceneryReady
end

local player = Players.LocalPlayer
local lit = {}

-- the adornee can be a Model OR a BasePart; the hill trees are parts
local function outline(model)
	local h = Instance.new("Highlight")
	h.Adornee = model
	h.FillTransparency = 1
	h.OutlineTransparency = 0
	h.OutlineColor = LINE
	-- Occluded, not AlwaysOnTop: a line that draws through a wall is a wallhack,
	-- not a cartoon. An object half behind something is half outlined, which is
	-- what it should be.
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	--[[ Parented to the adornee when it is a Model so nothing leaks, but a
		BasePart cannot hold a Highlight in every case, so those go on the
		camera and are cleaned up by the same keep/sweep below. ]]
	h.Parent = model:IsA("Model") and model or workspace.CurrentCamera
	return h
end

local near = {}

local function anchor()
	-- the CHARACTER, not the camera: anchoring on the camera meant zooming
	-- re-picked the whole set without the player having moved
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then return root.Position end
	local cam = workspace.CurrentCamera
	return cam and cam.CFrame.Position
end

local function refresh()
	local eye = anchor()
	if not eye then return end
	local char = player.Character
	local function gather(tags, out)
		table.clear(out)
		for _, tag in ipairs(tags) do
			for _, m in ipairs(CollectionService:GetTagged(tag)) do
				if m:IsA("Model") and m.Parent and m ~= char then
					local ok, pivot = pcall(function() return m:GetPivot().Position end)
					if ok then
						local d = (pivot - eye).Magnitude
						-- already lit? its line reaches a little further, so nothing
						-- flickers on the boundary
						if d < reach * (lit[m] and 1.08 or 1.0) then table.insert(out, { m, d }) end
					end
				end
			end
		end
		table.sort(out, function(a, b) return a[2] < b[2] end)
	end
	local keep, spent = {}, 0
	if char and char.PrimaryPart then
		keep[char] = true
		spent = 1
		if not lit[char] or not lit[char].Parent then lit[char] = outline(char) end
	end
	--[[ Scenery is gathered from the cached array rather than from tags: 4,568
		distance tests against a flat table, three times a second, which is far
		cheaper than asking CollectionService for them and calling GetPivot on
		each. ]]
	local function gatherScenery(out)
		table.clear(out)
		for _, entry in ipairs(scenery) do
			local m = entry[1]
			if m.Parent then
				local d = (entry[2] - eye).Magnitude
				if d < reach * (lit[m] and 1.08 or 1.0) then table.insert(out, { m, d }) end
			end
		end
		table.sort(out, function(a, b) return a[2] < b[2] end)
	end

	for _, tags in ipairs({ TIER1, TIER2, "scenery" }) do
		if tags == "scenery" then gatherScenery(near) else gather(tags, near) end
		for i = 1, math.min(BUDGET - spent, #near) do
			local m, d = near[i][1], near[i][2]
			keep[m] = true
			spent = spent + 1
			local h = lit[m]
			if not h or not h.Parent then
				h = outline(m)
				lit[m] = h
			end
			--[[ THE FADE. Solid until the last quarter of the reach, then eased out
				to nothing. A line that thins away reads as distance; a line that stops
				dead reads as a bug, which is what he saw. ]]
			local k = (d - reach * (1 - FADE)) / (reach * FADE)
			h.OutlineTransparency = k <= 0 and 0 or (k >= 1 and 1 or k * k)
		end
		if spent >= BUDGET then break end
	end
	for m, h in pairs(lit) do
		if not keep[m] or not m.Parent then
			if h.Parent then h:Destroy() end
			lit[m] = nil
		end
	end
end

--[[ Steer the reach by what the frame actually costs rather than by a constant
	I guessed. It moves 8% a step at most, four times a second, so it cannot
	oscillate visibly -- and the fade means the boundary is never on screen to be
	seen moving. ]]
local Stats = game:GetService("Stats")

local function steer()
	local ok, draws = pcall(function() return Stats.SceneDrawcallCount end)
	if not ok or type(draws) ~= "number" or draws <= 0 then return end
	if draws > DRAW_CEIL then
		reach = math.max(MIN_R, reach * 0.92)
	elseif draws < DRAW_CEIL - DRAW_EASE then
		reach = math.min(MAX_R, reach * 1.04)
	end
end

--[[ The world is built at runtime, so the scenery cache cannot be made on
	load. Try until it is there, then stop. ]]
task.spawn(function()
	--[[ MEASURED THE FIRST TIME THIS RAN: it cached 2,346 objects and the log
		line landed BEFORE "[SV] low-poly valley", i.e. it scanned while the
		valley was still being built and caught about half the hill trees. The
		world has no "finished" signal, so rescan on a decaying schedule until
		the count stops growing, then stop. ]]
	local t0, best, settled = os.clock(), 0, 0
	while os.clock() - t0 < 150 do
		buildScenery()
		if #scenery > best then
			best = #scenery
			settled = 0
		else
			settled += 1
			if settled >= 3 and best > 0 then break end
		end
		task.wait(os.clock() - t0 < 30 and 3 or 10)
	end
	if sceneryReady then
		print(("[SV] outlines: %d scenery objects cached (hill trees + untagged models)"):format(#scenery))
	else
		warn("[SV] outlines: no scenery found; hills and towers will have no line")
	end
end)

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.3 then return end
	acc = 0
	steer()
	refresh()
end)
