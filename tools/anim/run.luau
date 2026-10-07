--[[ SV_HunterRun: the headhunter's sprint, as a looping KeyframeSequence.

The chase already has a windup and a lunge (tools/anim/hunter.luau). What it
has never had is a RUN -- the hunter closes the gap with its legs driven from
Lua pose code, which is why a thing sprinting at you reads as a thing sliding
at you. This is the missing one, and it is the animation you see for most of
the chase.

Run in Studio (Edit). It builds ServerStorage.SVAnimSource.SV_HunterRun;
publish with right-click > Save / Export > Save to Roblox, play it once in
Studio and click "Click to share access" in the Output, then put the id in
StaffAnimClient's HUNTER_ANIM.run.

Joint conventions on these rigs, same as hunter.luau (Motor6D C0/C1 identity
rotations, rig front = -Z):
  shoulder / hip +X   = the limb swings FORWARD
  elbow +X            = forearm folds up;  knee -X = shin folds back
  waist / root / neck: the part points UP, so +X tips it BACK; -X leans forward
  root (LowerTorso) translation Y = drop / hop

WHY IT LOOKS LIKE A SPRINT RATHER THAN A JOG, which is the whole point:

  * the body is pitched forward (root -0.30, waist -0.30) and the neck tips
    BACK the same amount, so the head stays level and the eyes stay on you.
    A runner who leans without lifting their head is falling, not chasing.
  * there is a FLIGHT PHASE. rootY rises +0.12 at the passing poses and drops
    -0.10 at each contact, so both feet leave the ground between strides. That
    bob is most of what sells speed.
  * the arms are bent hard (elbow ~1.4) and swing opposite the legs. A sprint
    drives from the arms; straight arms read as a jog.
  * the trailing shin folds right up (knee -1.70 at passing) instead of
    trailing behind. Heel-to-backside is the silhouette of a sprint.

TIMING. One full cycle is 0.56 s -- two strides, so a stride every 0.28 s.
ChaseRules has the hunter at sprint = ref x 1.15..1.25 (roughly 18-22 studs/s),
and a stride is about 6 studs, which lands near three strides a second. Played
back at rate 1.0 the feet will not skate badly at chase speed; StaffAnimClient
scales the rate by actual speed anyway.
]]
local ServerStorage = game:GetService("ServerStorage")

local function A(x, y, z) return CFrame.Angles(x or 0, y or 0, z or 0) end

-- one pose = { t, rootY, rootX, waist, neck, lSh, lEl, rSh, rEl, lHip, lKnee, rHip, rKnee }
local RUN = {
	-- LEFT foot strikes, right leg trailing. Arms opposite the legs.
	{ 0.00, -0.10, -0.30, -0.30, 0.26, -0.95, 1.35, 0.95, 1.45, 0.75, -0.25, -0.70, -1.05 },
	-- drive and flight: right knee swings through, both feet off the ground
	{ 0.14, 0.12, -0.34, -0.34, 0.28, -0.35, 1.30, 0.35, 1.40, 0.10, -0.35, 0.15, -1.70 },
	-- RIGHT foot strikes (the mirror of the first pose)
	{ 0.28, -0.10, -0.30, -0.30, 0.26, 0.95, 1.45, -0.95, 1.35, -0.70, -1.05, 0.75, -0.25 },
	-- drive and flight again, mirrored
	{ 0.42, 0.12, -0.34, -0.34, 0.28, 0.35, 1.40, -0.35, 1.30, 0.15, -1.70, 0.10, -0.35 },
	-- close the loop exactly on the first pose, or the cycle hitches every stride
	{ 0.56, -0.10, -0.30, -0.30, 0.26, -0.95, 1.35, 0.95, 1.45, 0.75, -0.25, -0.70, -1.05 },
}

local function build(name, keys, loop, priority)
	local kfs = Instance.new("KeyframeSequence")
	kfs.Name = name
	kfs.Loop = loop and true or false
	kfs.Priority = priority or Enum.AnimationPriority.Action
	for _, k in ipairs(keys) do
		local kf = Instance.new("Keyframe")
		kf.Time = k[1]
		local function pose(pname, cf, parent)
			local p = Instance.new("Pose")
			p.Name = pname
			p.CFrame = cf
			--[[ Linear between keys, not Cubic. A run is a continuous cycle and
				cubic ease-out settles into every key, which reads as a trot --
				the body pausing four times a cycle. ]]
			p.EasingStyle = Enum.PoseEasingStyle.Linear
			p.EasingDirection = Enum.PoseEasingDirection.InOut
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

--[[ Movement priority, not Action: the windup and the lunge are Action, so
	they play OVER the run without it having to be stopped and restarted. The
	run is the thing underneath the whole chase. ]]
local old = folder:FindFirstChild("SV_HunterRun")
if old then old:Destroy() end
build("SV_HunterRun", RUN, true, Enum.AnimationPriority.Movement).Parent = folder

return folder
