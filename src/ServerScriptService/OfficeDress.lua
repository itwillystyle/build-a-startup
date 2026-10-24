--[[ OfficeDress (24 Oct 2026, art pass 4, Task 4): builds a tower office's dressing from OfficeLayout.

	Luke's pick (ui/art-pass/tower-office.png): a navy rug with a coral edge under the furniture group,
	a navy base along the oak feature wall, a framed print in the department's colour, and plants. The
	data and its checks are OfficeLayout's (tests/offline/officelayout.spec); this only makes parts.

	Everything goes in one Model, "Dressing", inside the room's model, so a re-dress (the company reaching
	level 13, ruling 1) can take it away in one go. Every part is tagged SVDressing (OfficeCullClient hides
	it in far rooms) and never collides, never blocks the camera and casts no shadow. The rugs keep their
	Fabric (SVKeepMaterial: the one grain spec section 5 allows). ]]
local CollectionService = game:GetService("CollectionService")

local OfficeDress = {}
OfficeDress.TAG = "SVDressing"

local function rgb(c) return Color3.fromRGB(c[1], c[2], c[3]) end

local function tagAll(inst, tag)
	local list = inst:IsA("BasePart") and { inst } or inst:GetDescendants()
	for _, d in ipairs(list) do
		if d:IsA("BasePart") then CollectionService:AddTag(d, tag) end
	end
end
OfficeDress.tagAll = tagAll

-- the print on the wall: no text, no logo; lit by the room (LightInfluence 1), so it never reads as a screen
local function drawPrint(art, tint, C)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "Print"
	sg.Face = Enum.NormalId.Back             -- the part's +Z: into the room
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 1
	sg.MaxDistance = 90
	sg.Parent = art
	local function box(color, x, y, w, h, parent)
		local f = Instance.new("Frame")
		f.BackgroundColor3, f.BorderSizePixel = color, 0
		f.Position, f.Size = UDim2.fromScale(x, y), UDim2.fromScale(w, h)
		f.Parent = parent or sg
		return f
	end
	local mat = box(rgb(C.paper), 0.05, 0.05, 0.9, 0.9)         -- the mat inside the ink frame
	box(tint, 0.08, 0.08, 0.84, 0.54, mat)                       -- the top 60%: the department's colour
	box(rgb(C.navy), 0.08, 0.62, 0.84, 0.30, mat)                -- the bottom 30%: navy
	local sun = box(rgb(C.coral), 0.62, 0.16, 0.2, 0.2 * art.Size.X / art.Size.Y, mat)   -- a coral circle
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = sun
end

--[[ build the dressing of one room. deps: { OL = OfficeLayout (with), FK = FurnitureKit, part = the
	part maker (SiliconCore's: anchored, palette-authored), tint = the department's Color3 }.
	Returns the Dressing model and how many BaseParts it holds. ]]
function OfficeDress.build(model, anchor, r, dept, company, storey, seg, deps)
	local OL, FK, part = deps.OL, deps.FK, deps.part
	local C = OL.COLORS
	local dress = Instance.new("Model")
	dress.Name = "Dressing"
	dress.Parent = model
	local face = -r.d / 2 + (deps.wallT or 0.4)
	local flat = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
	local function make(props)
		local p = table.clone(flat)
		for k, v in pairs(props) do p[k] = v end
		return part(p, dress)
	end
	for _, pc in ipairs(OL.dressing(dept, r, company, storey, seg)) do
		if pc.kind == "rug" or pc.kind == "border" then
			local p = make({ Name = pc.id, Size = Vector3.new(pc.w, pc.y1, pc.d), CFrame = anchor * CFrame.new(pc.x, pc.y1 / 2, pc.z),
				Color = rgb(pc.color), Material = Enum.Material.Fabric })
			CollectionService:AddTag(p, "SVKeepMaterial")
		elseif pc.kind == "base" or pc.kind == "art" then
			local p = make({ Name = pc.id, Size = Vector3.new(pc.w, pc.y1 - pc.y0, pc.depth),
				CFrame = anchor * CFrame.new(pc.x, (pc.y0 + pc.y1) / 2, face + pc.depth / 2),
				Color = rgb(pc.color), Material = Enum.Material.SmoothPlastic })
			if pc.kind == "art" then drawPrint(p, deps.tint or rgb(C.oak), C) end
		elseif pc.kind == "plant" then
			if FK and FK.has and FK.has(pc.key) then
				pcall(FK.onFloor, pc.key, anchor, pc.x, pc.z, 0, dress, { yaw = pc.yaw, name = pc.id })
			end
		end
	end
	tagAll(dress, OfficeDress.TAG)
	local n = 0
	for _, d in ipairs(dress:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
	return dress, n
end

return OfficeDress
