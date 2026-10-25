--[[
	BobDoorClient -- LocalScript in StarterPlayer -> StarterPlayerScripts. P-5 (25 Oct 2026).

	After you beat Bob (the server's BobPaid), YOUR view of Bob Capital changes and nobody
	else's does (spec 3f; Luke: "make that client-sided to the person who actually
	completed it"):
	  * the tape is gone and the door stands open (not solid, for you only),
	  * Bob sits dizzy on the curb outside, stars over his head, every time you pass.
	Everyone else still sees the taped door and collides with it: the server's world is
	never touched. Bob on the curb hides past 160 studs, like the offices (OfficeCullClient).
	Re-applied whenever a Bob cutscene ends (the scene puts the door back the way it found it).
]]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local BobFace = require(RS:WaitForChild("BobFace"))
local UIKit = require(RS:WaitForChild("UIKit"))

local FAR = 160
local applied, curbBob, stars, doorCF0 = false, nil, nil, nil

local function building()
	local sv = workspace:FindFirstChild("SiliconValley")
	return sv and sv:FindFirstChild("BobCapital")
end

local function apply()
	local bc = building()
	if not bc or player:GetAttribute("BobPaid") ~= true or player:GetAttribute("BobScenePlaying") == true then return end
	local door, tape = bc:FindFirstChild("Door"), bc:FindFirstChild("Tape")
	if tape then
		for _, p in ipairs(tape:GetChildren()) do if p:IsA("BasePart") then p.LocalTransparencyModifier = 1 end end
	end
	if door then
		doorCF0 = doorCF0 or door.CFrame
		local hinge = doorCF0 * CFrame.new(-door.Size.X / 2, 0, 0)
		door.CFrame = hinge * CFrame.Angles(0, math.rad(-100), 0) * CFrame.new(door.Size.X / 2, 0, 0)
		door.CanCollide = false
	end
	if not curbBob then
		local cast = RS:FindFirstChild("BobCast")
		local seat = door and door:FindFirstChild("CurbSeat")
		if cast and cast:FindFirstChild("Bob") and seat then
			curbBob = cast.Bob:Clone()
			curbBob.Name = "BobOnTheCurb"
			for _, d in ipairs(curbBob:GetDescendants()) do
				if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false end
			end
			local glasses = curbBob:FindFirstChild("Sunglasses")
			if glasses then glasses:Destroy() end   -- they flew off in the payoff
			local pick = curbBob:FindFirstChild("Toothpick")
			if pick then pick:Destroy() end         -- it's in your HQ now, on a stand
			local hum = curbBob:FindFirstChildOfClass("Humanoid")
			if hum then hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end
			curbBob:PivotTo(seat.WorldCFrame * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, math.rad(180), 0))
			curbBob.Parent = workspace
			BobFace.attach(curbBob).set("dizzy")
			local head = curbBob:FindFirstChild("Head")
			if head then
				stars = Instance.new("BillboardGui")
				stars.Size = UDim2.fromOffset(120, 40)
				stars.StudsOffset = Vector3.new(0, 1.8, 0)
				stars.LightInfluence = 0
				stars.Adornee = head
				local t = Instance.new("TextLabel")
				t.BackgroundTransparency = 1
				t.Size = UDim2.fromScale(1, 1)
				t.Font = UIKit.HEAD
				t.TextSize = UIKit.TYPE.headline
				t.Text = "* * *"
				t.TextColor3 = UIKit.GOLD
				t.Parent = stars
				stars.Parent = head
			end
		end
	end
	applied = true
end

-- far hiding + the stars turning (cheap: a few times a second)
task.spawn(function()
	while true do
		task.wait(0.25)
		if not applied then apply() end
		if curbBob then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local pivot = curbBob and curbBob:GetPivot()
			local near = root and pivot and (root.Position - pivot.Position).Magnitude < FAR
			do
				for _, d in ipairs(curbBob:GetDescendants()) do
					if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = near and 0 or 1 end
				end
				if stars then stars.Enabled = near == true; stars.TextLabel.Rotation = (os.clock() * 90) % 360 end
			end
		end
	end
end)

player:GetAttributeChangedSignal("BobPaid"):Connect(apply)
player:GetAttributeChangedSignal("BobScenePlaying"):Connect(function()
	if player:GetAttribute("BobScenePlaying") ~= true then
		applied = false
		doorCF0 = nil     -- the scene restored the server's closed door: measure it again
		apply()
	end
end)
