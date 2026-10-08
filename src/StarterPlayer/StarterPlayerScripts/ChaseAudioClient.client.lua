--[[
	ChaseAudioClient -- the wind and the footsteps, for the player on a carry.

	The maths is in ReplicatedStorage.ChaseAudio (pure, tested offline). This
	script only applies it: reads the player's speed and the hunter's position,
	and plays two sounds. The camera is not touched here, on purpose.

	It is client-only and uses no remotes. The server moves the hunter with
	PivotTo, which leaves its AssemblyLinearVelocity at zero, so this script
	measures the hunter's speed itself from its position over time.
]]
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local ChaseAudio = require(RS:WaitForChild("ChaseAudio"))

local player = Players.LocalPlayer

-- Built-in engine sounds, shipped with every Roblox client, so they cannot be
-- moderated away or fail to load. UNVERIFIED until heard in Studio: an audio id
-- that cannot load plays SILENTLY with no error, so if the wind or the steps
-- are quiet, check these two ids first.
local WIND_ID = "rbxasset://sounds/action_falling.mp3"
local STEP_ID = "rbxasset://sounds/action_footsteps_plastic.mp3"

local SCAN_EVERY = 0.4      -- seconds between hunter rescans; a scan walks TalentRow
local SPEED_WINDOW = 0.2    -- seconds per hunter speed sample; smooths the 20 Hz PivotTo steps
local EASE_RATE = 4         -- how fast the wind follows its target, per second
local PITCH_REST = 0.9      -- ChaseAudio.windPitch(0): the pitch the wind starts from

-- The wind bed: one looping sound, not positional, so it is the same everywhere.
local wind = Instance.new("Sound")
wind.Name = "ChaseWind"
wind.SoundId = WIND_ID
wind.Looped = true
wind.Volume = 0
wind.Parent = SoundService

--[[ The footsteps: ONE positional sound on an attachment under Terrain, and
	the attachment is moved to the nearest hunter every frame.

	The first version parented the sound INTO the hunter's part. The server
	destroys hunters mid-chase (a catch, a delivery, a Non-Compete), and a
	sound parented inside a destroyed model is destroyed with it -- after
	which every frame's `step.Parent = ...` throws, forever. Terrain is never
	destroyed, so nothing the server does can take the sound away. Roblox
	still pans and rolls it off from the attachment's position. ]]
local stepAnchor = Instance.new("Attachment")
stepAnchor.Name = "ChaseStepAnchor"
stepAnchor.Parent = workspace.Terrain
local step = Instance.new("Sound")
step.Name = "ChaseStep"
step.SoundId = STEP_ID
step.Volume = 0
step.Parent = stepAnchor

local active = false
local windVol = 0
local windPitch = PITCH_REST
local records = {}          -- [hunter Model] = { part, lastPos, sampleT, speed, stepT }
local nearestRec = nil      -- the record whose position the step sound is following
local scanT = 0
local rescanNow = true

local function flat(v)
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

local function parkStep()
	step:Stop()
	nearestRec = nil
end

local function dropRecord(model)
	local rec = records[model]
	if not rec then return end
	if nearestRec == rec then parkStep() end
	records[model] = nil
end

local function track(model, part)
	records[model] = {
		part = part,
		lastPos = part.Position,
		sampleT = 0,
		speed = 0,
		stepT = 0,
	}
end

-- Find this player's hunters: Models directly under TalentRow, marked as
-- chasing them. Keeps the records in step with the world.
local function rescan()
	local sv = workspace:FindFirstChild("SiliconValley")
	local row = sv and sv:FindFirstChild("TalentRow")
	local seen = {}
	if row then
		for _, m in row:GetChildren() do
			if m:IsA("Model")
				and m:GetAttribute("Chaser") == true
				and m:GetAttribute("ChasingUserId") == player.UserId
				and m.PrimaryPart
			then
				seen[m] = true
				if not records[m] then
					track(m, m.PrimaryPart)
				end
				records[m].part = m.PrimaryPart
			end
		end
	end
	-- Collect first, then drop: removing keys while walking the table is unsafe.
	local gone = {}
	for m in records do
		if not seen[m] then table.insert(gone, m) end
	end
	for _, m in gone do
		dropRecord(m)
	end
end

local function updateWind(dt, hrp)
	local speed = flat(hrp.AssemblyLinearVelocity)
	local carry = player:GetAttribute("CarrySpeed")
	local targetVol = ChaseAudio.windVolume(speed, carry)
	local targetPitch = ChaseAudio.windPitch(speed, carry)
	-- Ease toward the target rather than snap, so a boost swells instead of clicking.
	local a = 1 - math.exp(-EASE_RATE * dt)
	windVol += (targetVol - windVol) * a
	windPitch += (targetPitch - windPitch) * a
	wind.Volume = windVol
	wind.PlaybackSpeed = windPitch
end

local function updateHunters(dt, hrp)
	-- Measure each hunter's speed from its own position, since the server
	-- sets its position and nothing reports a velocity.
	for _, rec in records do
		if rec.part.Parent then
			rec.sampleT += dt
			if rec.sampleT >= SPEED_WINDOW then
				local pos = rec.part.Position
				rec.speed = flat(pos - rec.lastPos) / rec.sampleT
				rec.lastPos = pos
				rec.sampleT = 0
			end
		end
	end

	-- Only the nearest hunter makes footsteps.
	local best, bestDist = nil, math.huge
	for _, rec in records do
		if rec.part.Parent then
			local dist = (rec.part.Position - hrp.Position).Magnitude
			if dist < bestDist then
				best, bestDist = rec, dist
			end
		end
	end
	if not best then
		if nearestRec then parkStep() end
		return
	end
	if best ~= nearestRec then
		nearestRec = best
		step:Stop()
		best.stepT = 0
	end
	stepAnchor.WorldPosition = best.part.Position

	-- A still hunter makes no sound (interval is math.huge). Reset the clock so
	-- its first step after moving is not delayed by time spent standing still.
	local interval = ChaseAudio.stepInterval(best.speed)
	if interval == math.huge then
		best.stepT = 0
	else
		best.stepT += dt
		if best.stepT >= interval then
			best.stepT = math.max(0, best.stepT - interval)
			step.Volume = ChaseAudio.stepVolume(bestDist)
			step:Play()
		end
	end
end

-- Stop everything and clear it, so the next carry starts from silence.
local function reset()
	active = false
	wind:Stop()
	windVol = 0
	windPitch = PITCH_REST
	wind.Volume = 0
	records = {}
	parkStep()
	scanT = 0
	rescanNow = true
end

RunService.Heartbeat:Connect(function(dt)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local carrying = player:GetAttribute("Carrying") ~= nil

	if not carrying or not hrp then
		if active then reset() end
		return
	end

	if not active then
		active = true
		wind:Play()
		rescanNow = true
	end

	updateWind(dt, hrp)

	scanT += dt
	if rescanNow or scanT >= SCAN_EVERY then
		scanT = 0
		rescanNow = false
		rescan()
	end

	updateHunters(dt, hrp)
end)

-- Carry ended: silence now, not on the next frame.
player:GetAttributeChangedSignal("Carrying"):Connect(function()
	if player:GetAttribute("Carrying") == nil then
		reset()
	end
end)

player.CharacterAdded:Connect(reset)
