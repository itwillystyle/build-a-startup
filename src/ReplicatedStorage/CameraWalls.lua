--[[ CameraWalls (10 Oct 2026): the walls the camera cannot see.

	His playtest of 10 Oct: walking into the HQ, and mid-chase past it, the screen
	went blank white, orange (the timber ceiling) or green (the whole room seen
	through tinted glass) for seconds at a time. Measured the same day: from 240
	camera positions on the HQ's ground floor, 133 (55%) were behind a wall.

	Why. A building's LOOK is a mesh that raycasts cannot hit (CanQuery false, Box
	collision), and its COLLISION is invisible boxes (Wall, Floor, Partition, Rail,
	Deck, Roof... Transparency 1). Roblox's camera (Poppercam) only stops at parts
	that are opaque AND solid, so it sees neither. The chase camera skipped every
	invisible part on purpose (the valley's 1,232 hill wedges). Both cameras flew
	straight through every wall of every HQ and garage.

	The fix is one rule, used by both cameras: inside SiliconValley.Plots, an
	invisible solid part stands in for a visible wall, so the camera stops at it.
	  * the normal camera: CameraWallsClient pulls the lens in after Roblox's
	    camera has placed it (Poppercam still handles every visible wall)
	  * the chase camera: ChaseCamClient no longer skips these parts
	Outside the plots nothing changes (the hill wedges are still skipped). ]]
local CameraWalls = {}

CameraWalls.RADIUS = 0.75     -- the spherecast: wider than the near plane, so a grazing wall does not clip
CameraWalls.MARGIN = 0.25     -- stop this far short of the wall (on top of RADIUS)
CameraWalls.MIN = 0.5         -- never closer to the focus than this (first person takes over)

-- pure: does a part with these properties stand in for a wall you can see?
function CameraWalls.isStandIn(transparency, canCollide, canQuery, inPlots)
	return inPlots == true and canCollide == true and canQuery == true and transparency > 0.9
end

-- pure: the distance to keep from the focus, wanting `want`, with a wall `hit` studs away (or nil)
function CameraWalls.distance(want, hit)
	if not hit then return want end
	return math.min(want, math.max(CameraWalls.MIN, hit - CameraWalls.MARGIN))
end

-- ---------------------------------------------------------------- runtime (client)
local set = {}            -- part -> true
local list = {}
local dirty = false
local params        -- made in start(): the pure half above runs offline, where there is no RaycastParams
local plots

local function consider(d)
	if not d:IsA("BasePart") then return end
	local yes = CameraWalls.isStandIn(d.Transparency, d.CanCollide, d.CanQuery, true)
	if yes ~= (set[d] == true) then
		set[d] = yes or nil
		dirty = true
	end
end

-- is this part one of the stand-ins? (ChaseCamClient asks before skipping an invisible hit)
function CameraWalls.isSolid(part)
	return set[part] == true
end

-- the first stand-in wall from `origin` along `offset`: distance or nil
function CameraWalls.cast(origin, offset)
	if not (plots and params) then return nil end
	if dirty then
		dirty = false
		table.clear(list)
		for p in set do
			if p.Parent then table.insert(list, p) else set[p] = nil end
		end
		params.FilterDescendantsInstances = list
	end
	if #list == 0 then return nil end
	local hit = workspace:Spherecast(origin, CameraWalls.RADIUS, offset, params)
	return hit and hit.Distance or nil
end

function CameraWalls.start()
	if CameraWalls.started then return end
	CameraWalls.started = true
	params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {}
	task.spawn(function()
		local sv = workspace:WaitForChild("SiliconValley")
		plots = sv:WaitForChild("Plots")
		for _, d in ipairs(plots:GetDescendants()) do consider(d) end
		plots.DescendantAdded:Connect(consider)
		plots.DescendantRemoving:Connect(function(d)
			if set[d] then set[d] = nil dirty = true end
		end)
	end)
end

return CameraWalls
