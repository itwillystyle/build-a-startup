--[[
	OutlineClient -- a black line round the things you care about (4 Oct).

	The cartoon A/B showed the lighting and material pass does most of the
	work, and that outlines add the last of it -- but only up close. Roblox
	gives no custom shaders, so the only outline without new assets is the
	`Highlight` instance, and it has two hard limits: no line-width control,
	and only a low number render at once.

	So this spends the budget on the things a player actually looks at, and
	nothing else: your own character, the people (candidates, headhunters,
	your staff) and the nearest traffic. The valley, the buildings and the
	trees get the flat-colour treatment instead and no line -- in the test
	they read fine without one at any distance you see them from.

	Same shape as SkyClient's lamps: pick the nearest N a few times a second,
	add to what came into range, drop what left. A Highlight is parented to
	the model it outlines, so a candidate who is recruited takes its outline
	with it and nothing leaks.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local MAX, RANGE = 18, 150
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
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = model
	return h
end

local near = {}
local function refresh()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local eye = cam.CFrame.Position
	table.clear(near)
	-- your own character always gets one: it is the thing on screen the most
	local char = player.Character
	if char and char.PrimaryPart then table.insert(near, { char, 0 }) end
	for _, tag in ipairs(TAGS) do
		for _, m in ipairs(CollectionService:GetTagged(tag)) do
			if m:IsA("Model") and m.Parent and m ~= char then
				local ok, pivot = pcall(function() return m:GetPivot().Position end)
				if ok then
					local d = (pivot - eye).Magnitude
					if d < RANGE then table.insert(near, { m, d }) end
				end
			end
		end
	end
	table.sort(near, function(a, b) return a[2] < b[2] end)
	local keep = {}
	for i = 1, math.min(MAX, #near) do
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
	if acc < 0.4 then return end        -- outlines do not need to be re-picked every frame
	acc = 0
	refresh()
end)
