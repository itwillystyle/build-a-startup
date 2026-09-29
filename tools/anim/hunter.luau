--[[ The headhunter's WINDUP (0.5 s, ChaseRules.WINDUP) and LUNGE (0.8 s,
ChaseRules.LUNGE_TIME) as KeyframeSequences, full body.

Run in Studio (Edit). It builds ServerStorage.SVAnimSource.SV_HunterWindup and
SV_HunterLunge; publish each with right-click > Save / Export > Save to Roblox,
play once in Studio and click "Click to share access" in Output, then put the
ids in StaffAnimClient's HUNTER_ANIM.

Joint conventions on these rigs (Motor6D C0/C1 identity rotations, rig front
= -Z), checked in the 29 Sep preview (standing foot centre 2.45 below the root;
crouch coil 2.51 = grounded; lunge reach at drop -0.45 = 2.67, sunk, so -0.30):
  shoulder / hip +X   = the limb swings FORWARD (it hangs down, so +X moves it to -Z)
  elbow +X            = forearm folds up;  knee -X = shin folds back
  waist / root / neck: the part points UP, so +X tips it BACK; -X leans forward
  root (LowerTorso) translation Y = drop / hop (the server moves the anchored
  HumanoidRootPart; this only moves the body under it)
]]
local ServerStorage = game:GetService("ServerStorage")

local function A(x, y, z) return CFrame.Angles(x or 0, y or 0, z or 0) end

-- one pose = { t, rootY, rootX, waist, neck, lSh, lEl, rSh, rEl, lHip, lKnee, rHip, rKnee }
local WINDUP = {
	{ 0.00, 0.00, -0.10, -0.20, 0.10, 0.30, 1.00, -0.30, 1.00, 0.40, -0.40, -0.30, -0.80 },
	{ 0.14, -0.55, -0.25, -0.35, 0.35, -0.90, 0.55, -0.90, 0.55, 0.80, -1.40, 0.80, -1.40 },  -- drop into the crouch
	{ 0.30, -0.68, -0.30, -0.45, 0.40, -1.15, 0.45, -1.15, 0.45, 0.90, -1.55, 0.90, -1.55 },  -- coil
	{ 0.40, -0.62, -0.28, -0.42, 0.40, -1.05, 0.50, -1.05, 0.50, 0.86, -1.48, 0.86, -1.48 },  -- tremble
	{ 0.50, -0.70, -0.30, -0.46, 0.42, -1.20, 0.45, -1.20, 0.45, 0.92, -1.58, 0.92, -1.58 },  -- about to spring
}
local LUNGE = {
	{ 0.00, -0.70, -0.30, -0.46, 0.42, -1.20, 0.45, -1.20, 0.45, 0.92, -1.58, 0.92, -1.58 },  -- from the coil
	{ 0.10, -0.20, -0.40, -0.55, 0.45, 0.60, 0.60, 0.60, 0.60, 0.20, -0.60, -0.40, -0.20 },   -- spring (in-between: arms pass the hip)
	{ 0.30, -0.30, -0.50, -0.62, 0.50, 1.85, 0.08, 1.85, 0.08, 1.20, -0.50, -0.95, -0.10 },   -- full reach (drop -0.30: at -0.45 the front foot sank 0.22 into the floor)
	{ 0.50, -0.28, -0.42, -0.50, 0.40, 1.55, 1.25, 1.55, 1.25, 1.05, -0.60, -0.80, -0.30 },   -- grab
	{ 0.80, 0.00, -0.15, -0.22, 0.12, 0.30, 0.95, -0.30, 0.95, 0.35, -0.50, -0.30, -0.90 },   -- back to the run
}

local function build(name, keys)
	local kfs = Instance.new("KeyframeSequence")
	kfs.Name = name
	kfs.Loop = false
	kfs.Priority = Enum.AnimationPriority.Action
	for _, k in ipairs(keys) do
		local kf = Instance.new("Keyframe")
		kf.Time = k[1]
		local function pose(pname, cf, parent)
			local p = Instance.new("Pose")
			p.Name = pname
			p.CFrame = cf
			p.EasingStyle = Enum.PoseEasingStyle.Cubic
			p.EasingDirection = Enum.PoseEasingDirection.Out
			p.Parent = parent
			return p
		end
		local hrp = pose("HumanoidRootPart", CFrame.identity, kf)
		hrp.Weight = 0
		local lower = pose("LowerTorso", CFrame.new(0, k[2], 0) * A(k[3]), hrp)
		local upper = pose("UpperTorso", A(k[4]), lower)
		pose("Head", A(k[5]), upper)
		pose("LeftLowerArm", A(k[7]), pose("LeftUpperArm", A(k[6], 0, 0.1), upper))
		pose("RightLowerArm", A(k[9]), pose("RightUpperArm", A(k[8], 0, -0.1), upper))
		pose("LeftLowerLeg", A(k[11]), pose("LeftUpperLeg", A(k[10]), lower))
		pose("RightLowerLeg", A(k[13]), pose("RightUpperLeg", A(k[12]), lower))
		kf.Parent = kfs
	end
	return kfs
end

local folder = ServerStorage:FindFirstChild("SVAnimSource") or Instance.new("Folder")
folder.Name = "SVAnimSource"
folder.Parent = ServerStorage
for _, spec in ipairs({ { "SV_HunterWindup", WINDUP }, { "SV_HunterLunge", LUNGE } }) do
	local old = folder:FindFirstChild(spec[1])
	if old then old:Destroy() end
	build(spec[1], spec[2]).Parent = folder
end
return folder
