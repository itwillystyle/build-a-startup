--[[ SV_StaffCheer: the launch cheer for the R15 staff avatars, as a KeyframeSequence.

Run in Studio (Edit, command bar or execute_luau). It builds
ServerStorage.SVAnimSource.SV_StaffCheer; publish it with right-click >
Save to Roblox, then put the id in StaffAnimClient's CHEER_ANIM.

Upper body only. Legs and the root stay procedural in StaffAnimClient, so a
seated engineer cheers from the chair and a wandering one keeps its place.

Joint conventions measured on these rigs (29 Sep 2026, preview in Play):
  shoulder +X = arm swings forward and up; elbow +X = forearm folds.
  Z on the LEFT shoulder: + tucks in, - splays out (mirror for the right).
  Arm swings over ~pi need an in-between key: a Pose interpolates the short
  way round, so -0.35 -> 2.85 in one step flipped the arm backwards.
Measured at the arms-up key (UpperTorso space): hands at x +-2.2, y 1.8.
]]
local ServerStorage = game:GetService("ServerStorage")

local function A(x, y, z) return CFrame.Angles(x or 0, y or 0, z or 0) end

-- time, waist, neck, lShoulder, lElbow, rShoulder, rElbow
local KEYS = {
	{ 0.00, A(0), A(0), A(0.05, 0, 0.12), A(0.15), A(0.05, 0, -0.12), A(0.15) },
	{ 0.16, A(0.12), A(0.18), A(-0.35, 0, 0.05), A(0.7), A(-0.35, 0, -0.05), A(0.7) },     -- gather
	{ 0.26, A(0.02), A(0), A(1.25, 0, -0.25), A(0.45), A(1.25, 0, 0.25), A(0.45) },        -- swing (in-between)
	{ 0.36, A(-0.14), A(-0.22), A(2.85, 0, -0.42), A(0.12), A(2.85, 0, 0.42), A(0.12) },  -- arms up
	{ 0.54, A(-0.06), A(-0.12), A(2.25, 0, -0.30), A(1.05), A(2.25, 0, 0.30), A(1.05) },  -- pump
	{ 0.72, A(-0.16), A(-0.25), A(2.95, 0, -0.46), A(0.08), A(2.95, 0, 0.46), A(0.08) },  -- up again
	{ 0.90, A(-0.08), A(-0.10), A(2.40, 0, -0.30), A(0.50), A(2.40, 0, 0.30), A(0.50) },
	{ 1.20, A(0), A(0), A(0.05, 0, 0.12), A(0.15), A(0.05, 0, -0.12), A(0.15) },
}

local function build()
	local kfs = Instance.new("KeyframeSequence")
	kfs.Name = "SV_StaffCheer"
	kfs.Loop = false
	kfs.Priority = Enum.AnimationPriority.Action
	for _, k in ipairs(KEYS) do
		local kf = Instance.new("Keyframe")
		kf.Time = k[1]
		local function pose(name, cf, parent)
			local p = Instance.new("Pose")
			p.Name = name
			p.CFrame = cf
			p.EasingStyle = Enum.PoseEasingStyle.Cubic
			p.EasingDirection = Enum.PoseEasingDirection.Out
			p.Parent = parent
			return p
		end
		local hrp = pose("HumanoidRootPart", CFrame.identity, kf)
		hrp.Weight = 0
		local lower = pose("LowerTorso", CFrame.identity, hrp)
		lower.Weight = 0
		local upper = pose("UpperTorso", k[2], lower)
		pose("Head", k[3], upper)
		local lua = pose("LeftUpperArm", k[4], upper)
		pose("LeftLowerArm", k[5], lua)
		local rua = pose("RightUpperArm", k[6], upper)
		pose("RightLowerArm", k[7], rua)
		kf.Parent = kfs
	end
	return kfs
end

local folder = ServerStorage:FindFirstChild("SVAnimSource") or Instance.new("Folder")
folder.Name = "SVAnimSource"
folder.Parent = ServerStorage
local old = folder:FindFirstChild("SV_StaffCheer")
if old then old:Destroy() end
local kfs = build()
kfs.Parent = folder
return kfs
