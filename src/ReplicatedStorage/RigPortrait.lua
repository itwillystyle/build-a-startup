--[[ RigPortrait (14 Oct 2026, TEAM redesign): a staff member's real character inside a
	ViewportFrame, as a head (the face tiles) or the whole body (the person in the middle).

	The clone is made the way the hire reveal makes its portrait (TalentRevealClient, found
	live in v3.5): name tags, particles, lights and scripts stripped, the distance cull undone,
	and the SVStaff tag removed so StaffAnimClient does not adopt the copy. Client only.
	Spec: docs/superpowers/specs/2026-10-14-team-screen-redesign-design.md §2. ]]
local CollectionService = game:GetService("CollectionService")

local P = {}

-- YOUR person with this id: ids are per save, so another player's rig can share it
function P.find(userId, id)
	for _, m in ipairs(CollectionService:GetTagged("SVStaff")) do
		if m:GetAttribute("StaffId") == id and m:GetAttribute("StaffOwner") == userId and m:IsDescendantOf(workspace) then
			return m
		end
	end
	return nil
end

function P.clear(vpf)
	for _, c in ipairs(vpf:GetChildren()) do
		if not (c:IsA("Camera") or c:IsA("UICorner") or c:IsA("UIStroke")) then c:Destroy() end
	end
end

local function cameraOf(vpf)
	local cam = vpf:FindFirstChildOfClass("Camera")
	if not cam then
		cam = Instance.new("Camera")
		cam.FieldOfView = 40
		cam.Parent = vpf
	end
	vpf.CurrentCamera = cam
	return cam
end

-- framing: "head" (head and shoulders) or "body" (the whole character). false = nothing drawn
function P.show(vpf, rig, framing)
	P.clear(vpf)
	if not (rig and rig:IsA("Model") and rig:FindFirstChild("Head")) then return false end
	local ok, clone = pcall(function()
		local was = rig.Archivable
		rig.Archivable = true
		local c = rig:Clone()
		rig.Archivable = was
		return c
	end)
	if not ok or not clone then return false end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BillboardGui") or d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = 0
		end
	end
	local hum = clone:FindFirstChildOfClass("Humanoid")
	if hum then hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end
	CollectionService:RemoveTag(clone, "SVStaff")
	clone.Parent = vpf
	local cam = cameraOf(vpf)
	local head = clone:FindFirstChild("Head")
	if framing == "body" then
		local root = clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart or head
		local look = root.CFrame.LookVector
		local target = root.Position + Vector3.new(0, 0.5, 0)   -- room above the head (the review saw it clipped)
		cam.CFrame = CFrame.lookAt(target + look * 10.8 + Vector3.new(0, 0.9, 0), target)
	else
		local look = head.CFrame.LookVector
		local target = head.Position - Vector3.new(0, 0.35, 0)
		cam.CFrame = CFrame.lookAt(target + look * 3.6 + Vector3.new(0, 0.3, 0), target)
	end
	return true
end

return P
