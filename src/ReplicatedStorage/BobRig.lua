--[[
	BobRig -- ReplicatedStorage ModuleScript. P-5, Bob's cutscenes (25 Oct 2026).

	The cast are AI-made models (Studio's mesh generator, split into six pieces: Head, Torso,
	LeftArm, RightArm, LeftLeg, RightLeg). A model like that has no joints, so it cannot move.
	BobRig.ensure(model) gives it a rig the cutscene can pose:
	  * a HumanoidRootPart at the torso and a Humanoid (HipHeight from the feet)
	  * Motor6Ds named like R15's -- Root, Neck, LeftShoulder, RightShoulder, LeftHip, RightHip --
	    with their pivots at the neck, shoulders and hips, axis-aligned with the torso, so
	    BobSceneClient's poses (written for R15) bend them the same way
	A model that already has a Humanoid (Luke's own rig) is left exactly as it is.

	The pieces may sit inside sub-models (the generator's "HeadGroup" etc.); they are found by
	name anywhere in the model and moved to its root. The model must face -Z, as generated.
]]

local BobRig = {}

local PIECES = { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }

local function find(model, name)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == name then return d end
	end
	return nil
end

local function motor(name, part0, part1, worldPivot)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0, m.Part1 = part0, part1
	m.C0 = part0.CFrame:ToObjectSpace(worldPivot)
	m.C1 = part1.CFrame:ToObjectSpace(worldPivot)
	m.Parent = part1
	return m
end

-- returns the model (rigged), or nil if it lacks the six pieces
function BobRig.ensure(model)
	if not model or model:FindFirstChildOfClass("Humanoid") then return model end
	local p = {}
	for _, n in ipairs(PIECES) do
		p[n] = find(model, n)
		if not p[n] then return nil end
	end
	-- flatten: every part straight under the model (BobFace and the poses look there)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Parent ~= model then d.Parent = model end
	end
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("Model") and #d:GetChildren() == 0 then d:Destroy() end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("WeldConstraint") and (d.Part0 == nil or d.Part1 == nil) then d:Destroy() end
	end

	local torso = p.Torso
	local axes = torso.CFrame.Rotation   -- the torso's own axes: R15-like joints
	local function pivotAt(v) return CFrame.new(v) * axes end
	local function top(part) return part.Position + torso.CFrame.UpVector * (part.Size.Y / 2 - 0.15) end

	-- feet: the lowest point of either leg
	local footY = math.min(p.LeftLeg.Position.Y - p.LeftLeg.Size.Y / 2, p.RightLeg.Position.Y - p.RightLeg.Size.Y / 2)
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.CanCollide, root.CanQuery, root.CanTouch = false, false, false
	root.CFrame = pivotAt(torso.Position)
	root.Parent = model
	model.PrimaryPart = root

	motor("Root", root, torso, pivotAt(torso.Position))
	motor("Neck", torso, p.Head, pivotAt(p.Head.Position - torso.CFrame.UpVector * (p.Head.Size.Y / 2 - 0.1)))
	motor("LeftShoulder", torso, p.LeftArm, pivotAt(top(p.LeftArm)))
	motor("RightShoulder", torso, p.RightArm, pivotAt(top(p.RightArm)))
	motor("LeftHip", torso, p.LeftLeg, pivotAt(top(p.LeftLeg)))
	motor("RightHip", torso, p.RightLeg, pivotAt(top(p.RightLeg)))
	-- anything else welded on (Bob's tie, his toothpick, the face cards) follows its part as it was

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = d == root
			d.CanCollide = false
			d.Massless = d ~= root
		end
	end
	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.HipHeight = math.max(0, (root.Position.Y - root.Size.Y / 2) - footY)
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.BreakJointsOnDeath = false
	hum.Parent = model
	pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false) end)
	return model
end

return BobRig
