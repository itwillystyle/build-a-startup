--[[
	ShadowClient -- contact shadows on whatever is near you (v5.0).

	WHAT THIS REPLACED, and why the trade is worth making.

	The cartoon outline is gone. It was asked to do a job it could not do:
	a Highlight is one adornment per object, so the line could only ever
	reach the few hundred things the game tagged, and the hills, the roads
	and the 4,568 valley trees were never going to have one. Half-covered
	is worse than not covered -- it reads as a bug rather than a style.

	This spends the same budget on the thing that was actually missing.
	Measured on the live world before the change: 245 of 12,175 parts cast a
	shadow, which is 2%. Trees, lamps, benches, bollards, cars and people all
	had CastShadow off, turned off one perf pass at a time. The result is a
	world where nothing is attached to the ground -- objects read as stickers
	on a flat lawn, which is most of what "it looks blocky and cheap" is.

	A contact shadow is the single strongest cue that an object is standing
	in a place rather than drawn on top of one. It is also the cue a low-poly
	style can afford, because low-poly geometry is cheap to render into a
	shadow map.

	WHY IT IS DISTANCE-GATED. Shadow cost scales with the number of casters,
	and a shadow 400 studs away is a few pixels nobody looks at. So casting
	is switched on for what is near and off for what is not, on a 3 Hz pass
	with a hysteresis band so an object standing exactly on the boundary does
	not flicker on and off every pass.

	CastShadow set from a LocalScript is a client-only write: it never
	replicates, so each machine carries only the shadows it can see, and a
	phone on low graphics pays nothing for the far field.

	The budget is a hard count, not a radius: the radius adapts to keep the
	count under it, the same way the outline's did, so a dense plaza and an
	empty hillside both stay inside the frame cost.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ---------------------------------------------------------------- tuning
local BUDGET = 420               -- how many casters we are willing to pay for
local MAX_R, MIN_R = 230, 70     -- the radius the budget is allowed to move between
local HYSTERESIS = 1.12          -- drop at 1.12x the radius it was picked up at
local STEP = 0.33                -- seconds between passes
local MAX_SIZE = 90              -- a part bigger than this is scenery, not a prop

-- ---------------------------------------------------------------- candidates
--[[ Everything that should ground itself. Collected once from the built world
	and cached with its position, because these are static: a pass is then a
	distance test against a flat array rather than thousands of GetPivot
	calls. The ground, the hills, the sky and the building shells are left
	out -- they are what the shadows fall ON. ]]
local cand = {}                  -- { part, position }
local ready = false
local lit = {}                   -- part -> true, everything we switched on

local function wantPart(p)
	if not p:IsA("BasePart") then return false end
	if p.Transparency > 0.6 then return false end
	local s = p.Size
	if s.X > MAX_SIZE or s.Z > MAX_SIZE or s.Y > MAX_SIZE then return false end
	-- a broad thin horizontal slab is paving: it receives, it does not cast
	if s.Y <= 1.2 and s.X * s.Z > 400 then return false end
	return true
end

local function collect()
	local sv = workspace:FindFirstChild("SiliconValley")
	if not sv then return false end
	table.clear(cand)
	local roots = {}
	for _, name in ipairs({ "Valley", "CampusHub", "CampusDistricts", "Downtown",
		"KenneyCity", "City", "Plots", "TalentRow" }) do
		local f = sv:FindFirstChild(name)
		if f then table.insert(roots, f) end
	end
	local lp = sv:FindFirstChild("LowPolyWorld")
	local hills = lp and lp:FindFirstChild("HillTrees")
	if hills then table.insert(roots, hills) end

	for _, root in ipairs(roots) do
		for _, d in ipairs(root:GetDescendants()) do
			-- a part this script lit is still a candidate: without lit[d] each rescan
			-- would drop whatever is near you and it would never cast again
			if wantPart(d) and (not d.CastShadow or lit[d]) then
				table.insert(cand, { d, d.Position })
			end
		end
	end
	ready = #cand > 0
	return ready
end

--[[ The world is built at runtime and the build yields, so the cache cannot
	be made on load. Rescan until the count stops growing -- the first run
	after join reliably catches only part of it. The pass below flips a part
	and its lit[] entry together, so it never moves this count. ]]
task.spawn(function()
	local t0, last = os.clock(), -1
	while os.clock() - t0 < 150 do
		collect()
		if #cand > 0 and #cand == last then break end
		last = #cand
		task.wait(2)
	end
	if ready then
		print(("[SV] shadows: %d candidate props cached"):format(#cand))
	else
		warn("[SV] shadows: nothing found to ground")
	end
end)

-- ---------------------------------------------------------------- the pass
local reach = MAX_R
local acc = 0

--[[ Move the radius toward whatever keeps the count near the budget. Same
	shape as a thermostat: measure, then nudge, rather than recompute from
	scratch, so the radius never jumps and the shadow map is never asked to
	rebuild the whole scene in one frame. ]]
local function steer(count)
	if count > BUDGET then
		reach = math.max(MIN_R, reach * 0.93)
	elseif count < BUDGET * 0.8 then
		reach = math.min(MAX_R, reach * 1.05)
	end
end

RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < STEP or not ready then return end
	acc = 0

	local eye = camera.CFrame.Position
	local near = reach * reach
	local far = (reach * HYSTERESIS) ^ 2
	local count = 0

	-- drop what has gone out of range first, so the budget is spent on what is close
	for p in pairs(lit) do
		if not p.Parent then
			lit[p] = nil
		else
			local d = (p.Position - eye).Magnitude
			if d * d > far then
				p.CastShadow = false
				lit[p] = nil
			else
				count += 1
			end
		end
	end

	for _, entry in ipairs(cand) do
		if count >= BUDGET then break end
		local p = entry[1]
		if p.Parent and not lit[p] then
			local dx = entry[2] - eye
			if dx.X * dx.X + dx.Z * dx.Z + dx.Y * dx.Y < near then
				p.CastShadow = true
				lit[p] = true
				count += 1
			end
		end
	end
	steer(count)
end)

--[[ Respawning does not move the world, but it does move the camera a long
	way in one frame; clearing on death keeps the set honest rather than
	leaving shadows switched on across the map. ]]
player.CharacterAdded:Connect(function()
	for p in pairs(lit) do
		if p.Parent then p.CastShadow = false end
	end
	table.clear(lit)
	reach = MAX_R
end)

-- the player's own car and the staff standing beside you are always worth one
for _, tag in ipairs({ "SVCar", "SVStaff" }) do
	local function grab(m)
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 0.6 then d.CastShadow = true end
		end
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(grab)
	for _, m in ipairs(CollectionService:GetTagged(tag)) do grab(m) end
end
