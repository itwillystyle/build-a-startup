--[[
	TreeCullClient (v4.0) -- trees past a distance are not drawn.

	Measured 28 Sep: a wide valley view drew 1.36M triangles, and 950K of them
	were the 1,262 tree meshes (the valley's oaks, redwoods, orchards and the
	420 on the mesh hills). Phones budget ~1M for everything. Past ~650 studs a
	tree is a few pixels, and the hill meshes carry their woodland painted in,
	so they stay green without them. Checked twice a second on this client only
	(no server cost); a 60-stud band stops trees flickering at the edge.
]]
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FAR, NEAR = 680, 620
local TREE_NAMES = { "Oak_A", "Oak_B", "Redwood_A", "Eucalypt_A", "Palm_A", "Palm_B", "Orchard_A" }
-- v4.1: the low-poly set (SVMeshes.LowPoly). Its trees are ~100 facets, not ~750,
-- so they draw twice as far. The GROVES are never culled: they are the distant
-- woodland, one mesh per clump, and a bare far hill is what they exist to prevent.
local LP_NAMES = { "LP_Oak_A", "LP_Oak_B", "LP_Redwood_A", "LP_Redwood_B", "LP_Eucalypt",
	"LP_Palm_A", "LP_Palm_B", "LP_Orchard", "LP_Bush" }

local ids = {}
local lib = RS:WaitForChild("SVMeshes", 30)
if not lib then return end
for _, n in ipairs(TREE_NAMES) do
	local t = lib:FindFirstChild(n)
	local mp = t and (t:IsA("MeshPart") and t or t:FindFirstChildWhichIsA("MeshPart", true))
	if mp then ids[mp.MeshId] = true end
end
local lp = lib:FindFirstChild("LowPoly")
if lp then
	FAR, NEAR = 1000, 940
	for _, n in ipairs(LP_NAMES) do
		local t = lp:FindFirstChild(n)
		if t and t:IsA("MeshPart") then ids[t.MeshId] = true end
	end
end

local trees = {}           -- [MeshPart] = hidden?
local function consider(d)
	if d:IsA("MeshPart") and ids[d.MeshId] and not d:IsDescendantOf(lib) then trees[d] = false end
end
task.spawn(function()
	-- the world is built by the server a few seconds after join
	local world = workspace:WaitForChild("SiliconValley", 60)
	task.wait(2)
	for _, d in ipairs(workspace:GetDescendants()) do consider(d) end
	workspace.DescendantAdded:Connect(consider)
	local cam = workspace.CurrentCamera
	while true do
		local p = cam.CFrame.Position
		for part, hidden in pairs(trees) do
			if not part.Parent then
				trees[part] = nil
			else
				local d = (part.Position - p).Magnitude
				if not hidden and d > FAR then
					part.LocalTransparencyModifier = 1
					trees[part] = true
				elseif hidden and d < NEAR then
					part.LocalTransparencyModifier = 0
					trees[part] = false
				end
			end
		end
		task.wait(0.5)
	end
end)
local _ = RunService
