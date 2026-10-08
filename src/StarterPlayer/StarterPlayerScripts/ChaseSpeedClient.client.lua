--[[
	ChaseSpeedClient -- speed lines at the screen edge during a carry.

	WHY. The chase camera is deliberately still: it reads better than a camera
	that shakes at speed, and a steady frame is what keeps the hunter legible.
	So "you are going fast" has to come from things passing THROUGH the frame.
	These thin streaks do that. They sit only in the outer band of the screen,
	move outward along their own ray, and fade in with speed.

	WHAT IT NEVER DOES. It never reads or writes the camera's CFrame or
	FieldOfView. Another script owns the camera during a chase, and two owners
	of one property is a flicker bug this project has already shipped once.

	The geometry (how many, where they may sit, the ring that keeps the centre
	clear) is in ReplicatedStorage.ChaseSpeed, so the rule is tested offline.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChaseSpeed = require(ReplicatedStorage:WaitForChild("ChaseSpeed"))

local player = Players.LocalPlayer

-- The pool is built once. Nothing is created per frame.
local POOL = 24
local ANGLE_STEP = 360 / POOL -- 15 degrees between rays
local THICKNESS = 2           -- px
local MAX_ALPHA = 0.7         -- opacity at full intensity; never fully solid
local TRAVEL_MIN = 60         -- px per second at the threshold
local TRAVEL_MAX = 900        -- px per second at full intensity

-- Golden-ratio offsets spread the lengths and starting phases, so the streaks
-- never line up into a visible pattern.
local SPREAD_A = 0.618034
local SPREAD_B = 0.381966

local gui = Instance.new("ScreenGui")
gui.Name = "ChaseSpeed"
gui.DisplayOrder = 8
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Enabled = false

local pool = {}
for i = 1, POOL do
	local angle = (i - 1) * ANGLE_STEP
	local rad = math.rad(angle)
	local length = 40 + 50 * ((i * SPREAD_A) % 1) -- 40..90 px
	local frame = Instance.new("Frame")
	frame.Name = "Streak" .. i
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 1
	-- a horizontal bar, turned to lie along its own ray from the centre
	frame.Size = UDim2.fromOffset(length, THICKNESS)
	frame.Rotation = angle
	frame.Visible = false
	frame.Parent = gui
	pool[i] = {
		frame = frame,
		angle = angle,
		length = length,
		dx = math.cos(rad),
		dy = math.sin(rad),
		phase = (i * SPREAD_B) % 1, -- 0 = at the ring, 1 = off the edge
	}
end
gui.Parent = player:WaitForChild("PlayerGui")

--[[ Reveal order. `streaks()` says HOW MANY to show; showing the first N by
	index would light rays 0..N in order -- at low speed, one side of the
	screen only. Bit-reversed order spreads any N evenly around the circle. ]]
local order = {}
do
	local bits = 0
	while (2 ^ bits) < POOL do bits += 1 end
	for v = 0, (2 ^ bits) - 1 do
		local r, x = 0, v
		for _ = 1, bits do r = r * 2 + (x % 2); x = math.floor(x / 2) end
		if r < POOL then table.insert(order, r + 1) end
	end
end
local rank = {}
for i, idx in ipairs(order) do rank[idx] = i end

-- Flat speed on the ground plane. Vertical motion (jumps, drops) is not "fast".
local function groundSpeed(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then return 0 end
	local v = root.AssemblyLinearVelocity
	return math.sqrt(v.X * v.X + v.Z * v.Z)
end

RunService.RenderStepped:Connect(function(dt)
	local active = player:GetAttribute("Carrying") ~= nil and player:GetAttribute("ChaseCamOwns") == true
	if gui.Enabled ~= active then gui.Enabled = active end
	if not active then return end

	local size = gui.AbsoluteSize
	local hw, hh = size.X / 2, size.Y / 2
	if hw <= 0 or hh <= 0 then return end

	local carry = player:GetAttribute("CarrySpeed") or 16
	local k = ChaseSpeed.intensity(groundSpeed(player.Character), carry)
	local shown = ChaseSpeed.streaks(k, POOL)
	local travel = TRAVEL_MIN + (TRAVEL_MAX - TRAVEL_MIN) * k

	for i, s in ipairs(pool) do
		local inner, outer = ChaseSpeed.band(hw, hh, s.angle)
		local frame = s.frame
		if rank[i] > shown or not inner then
			frame.Visible = false
		else
			-- the streak's centre runs from (ring + half a streak) to (edge + half a
			-- streak), so its INNER end stops at the ring and its tail leaves the frame
			local from = inner + s.length / 2
			local to = outer + s.length / 2
			s.phase = (s.phase + travel * dt / (to - from)) % 1
			local r = from + s.phase * (to - from)
			frame.Position = UDim2.fromOffset(hw + s.dx * r, hh + s.dy * r)
			frame.BackgroundTransparency = 1 - MAX_ALPHA * k
			frame.Visible = true
		end
	end
end)
