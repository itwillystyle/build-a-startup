--[[
	FlatLook -- the cartoon pass (4 Oct).

	He asked for a cartoonish feel and whether that was assets or a filter.
	Neither: Roblox has no custom shaders, so nothing can post-process a
	realistic render into a cartoon one. What reads as cartoon is FLAT COLOUR
	and FLAT LIGHT. Measured in the A/B before this went in:

	  * 3,797 parts carried real surface grain -- Grass 485, Concrete 402,
	    Metal 379, Wood 227, Asphalt 142, WoodPlanks 80 and the rest. Texture
	    noise is the loudest "photographed" signal after shadows.
	  * every surface had a specular highlight (EnvironmentSpecularScale 1.0).

	Two jobs live here.

	`sweep` / `watch` flatten materials. SmoothPlastic everywhere, with three
	exceptions that carry meaning rather than detail -- Glass, Neon,
	ForceField -- and one that is not noise: a part with a MaterialVariant
	keeps its material, because SV_CampusPavers is the one texture in this
	game that was drawn for it and the blanket sweep in the test flattened the
	forecourt's herringbone along with everything else.

	`contact` replaces what turning GlobalShadows off takes away. With no cast
	shadows nothing is grounded -- in the test the tower floated. A dark disc
	under an object puts it back. It is OPAQUE, tinted off the colour of the
	ground it is actually standing on, because v28 measured that translucent
	parts are the single largest fill-rate cost on a phone and the right
	answer there was to delete all 68 of them, not to add 250 more.
]]

local FlatLook = {}

local KEEP = {
	[Enum.Material.Glass] = true,
	[Enum.Material.Neon] = true,
	[Enum.Material.ForceField] = true,
}

local FLAT = Enum.Material.SmoothPlastic

local function flatten(p)
	if p.Material == FLAT or KEEP[p.Material] then return false end
	if p.MaterialVariant ~= "" then return false end     -- SV_CampusPavers and anything like it
	p.Material = FLAT
	return true
end

function FlatLook.sweep(root)
	local n = 0
	for _, d in ipairs((root or workspace):GetDescendants()) do
		if d:IsA("BasePart") and flatten(d) then n = n + 1 end
	end
	return n
end

--[[ Plots are built and rebuilt all game -- every storey, every room, every
	candidate -- so a one-shot sweep goes stale the first time somebody
	upgrades. This queues new parts and flushes them a few times a second:
	bounded work, no per-frame cost, and nothing to remember to call from
	fourteen builders. ]]
function FlatLook.watch(root)
	root = root or workspace
	local queue, n = {}, 0
	root.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			n = n + 1
			queue[n] = d
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			if n > 0 then
				local batch, count = queue, n
				queue, n = {}, 0
				for i = 1, count do
					local d = batch[i]
					if d.Parent then flatten(d) end
				end
			end
		end
	end)
end

--[[ A PROP. Street furniture is built as loose parts -- a lamp is a pole and
	a head, a bench is nine slats and legs -- so each helper wraps its output
	in a Model. That grouping was introduced for the outline (one line round
	the whole object instead of one per slat); the outline is gone as of
	v5.0, but the grouping is worth keeping on its own merits: it is what
	lets a prop be moved, scaled or culled as one thing. ]]
function FlatLook.prop(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

--[[ A MODELLED PROP (v4.8, the Blender geometry pass).

	Roblox has no bevel, so every script-built prop has a hard 90-degree edge
	at every corner. Flat colour on a razor-edged box reads as a render of a
	box. blender/props.py models the same objects with fat rounded edges and
	exaggerated proportions, and this swaps them in.

	It returns nil when the kit has not been imported, and EVERY caller falls
	back to the parts it built before -- so the import can land late, or never,
	without the campus losing its street furniture.

	The pivot handling is ValleyGen.svMesh's, for the same reason: the FBX
	importer hands a Blender (Z-up) mesh a pivot turned 90 degrees about X, and
	placed by that pivot a lamp lies on its side. ]]
local PROP_YAW = math.pi          -- the importer also turns the mesh 180 about Y

function FlatLook.propMesh(parent, name, cf, height)
	local lib = game:GetService("ReplicatedStorage"):FindFirstChild("SVProps")
	local t = lib and lib:FindFirstChild(name)
	if not t then return nil end
	local c = t:Clone()
	local m = c
	if not c:IsA("Model") then m = Instance.new("Model"); m.Name = name; c.Parent = m end
	local only
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.CastShadow = false
			only = (only == nil) and d or false
		end
	end
	if only then
		only.PivotOffset = CFrame.new()
		m.PrimaryPart = only
		m.WorldPivot = only.CFrame
	end
	local _, ext = m:GetBoundingBox()
	if ext.Y < 0.01 then m:Destroy() return nil end
	m:ScaleTo(m:GetScale() * height / ext.Y)
	local _, yaw = cf:ToEulerAnglesYXZ()
	m:PivotTo(CFrame.Angles(0, yaw + PROP_YAW, 0))
	local at, e2 = m:GetBoundingBox()
	m:PivotTo(m:GetPivot() + (cf.Position - (at.Position - Vector3.new(0, e2.Y / 2, 0))))
	m.Parent = parent
	return m
end

local SHADOW_RAY = RaycastParams.new()
SHADOW_RAY.RespectCanCollide = false

--[[ A contact shadow at (x, z). `radius` is the object's footprint, `strength`
	how far the ground colour is pulled toward dark (0.26 by default: a hint,
	not a hole). Returns nil if there is no ground under the point, so a caller
	never has to check. ]]
function FlatLook.contact(parent, x, z, radius, strength)
	local hit = workspace:Raycast(Vector3.new(x, 90, z), Vector3.new(0, -200, 0), SHADOW_RAY)
	if not hit then return nil end
	local p = Instance.new("Part")
	p.Name = "ContactShadow"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.08, radius * 2, radius * 2)
	p.CFrame = CFrame.new(x, hit.Position.Y + 0.05, z) * CFrame.Angles(0, 0, math.rad(90))
	p.Color = hit.Instance.Color:Lerp(Color3.fromRGB(26, 30, 44), strength or 0.26)
	p.Material = FLAT
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

return FlatLook
