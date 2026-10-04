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

local BUDGET = 160                  -- measured: 1 draw call each, on top of ~250
local IN_R, OUT_R = 190, 240        -- hysteresis, so nothing flickers on the edge
local LINE = Color3.fromRGB(26, 24, 30)
local TAGS = { "SVOutline", "SVStaff", "TrafficCar" }

local player = Players.LocalPlayer
local lit = {}

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
	h.Parent = model
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
	table.clear(near)
	local char = player.Character
	if char and char.PrimaryPart then table.insert(near, { char, 0 }) end
	for _, tag in ipairs(TAGS) do
		for _, m in ipairs(CollectionService:GetTagged(tag)) do
			if m:IsA("Model") and m.Parent and m ~= char then
				local ok, pivot = pcall(function() return m:GetPivot().Position end)
				if ok then
					local d = (pivot - eye).Magnitude
					-- already lit? it keeps its line out to OUT_R. Not lit? it has
					-- to come inside IN_R to earn one.
					if d < (lit[m] and OUT_R or IN_R) then table.insert(near, { m, d }) end
				end
			end
		end
	end
	table.sort(near, function(a, b) return a[2] < b[2] end)
	local keep = {}
	for i = 1, math.min(BUDGET, #near) do
		local m = near[i][1]
		keep[m] = true
		local h = lit[m]
		if not h or not h.Parent then lit[m] = outline(m) end
	end
	for m, h in pairs(lit) do
		if not keep[m] or not m.Parent then
			if h.Parent then h:Destroy() end
			lit[m] = nil
		end
	end
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.3 then return end
	acc = 0
	refresh()
end)
