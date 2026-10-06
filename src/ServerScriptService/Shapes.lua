--[[
	Shapes -- the motif. (S5 of art/STYLE-SPEC.md)

	THE MOTIF: everything in this world is a rounded slab or a disc; nothing
	has a sharp corner. The disc is a silicon wafer, which is native to the
	subject, already present in the HQ ring and the dome, and reads from a
	500-stud tower down to a 16 px icon.

	WHY AN APRON AND NOT A REBUILD. Roblox has no rounded box, so a radiused
	slab is a smaller box plus four corner cylinders plus four edge fills --
	nine parts where there was one. The campus slab is also the floor people
	walk on and the surface Placement scans for paving, so rebuilding it would
	put a cosmetic change in the path of collision and placement.

	Instead the original keeps its size, its collision and its identity, and a
	rounded apron is laid on top at +0.02 studs, non-collidable and
	non-queryable. The silhouette from every approach becomes a rounded slab;
	nothing underneath moves. If the apron were deleted tomorrow the game would
	play identically.

	WHAT THIS DOES NOT DO. It does not round the architecture. Bevelling the
	HQ shells and the storey plates is Blender work on the mesh kit and an
	import, and it is recorded in STYLE-SPEC as the remainder of S5.
]]

local Shapes = {}

local CS = game:GetService("CollectionService")

Shapes.RADIUS = 14          -- corner radius in studs; ART.md asks for 3-6 on small plates, more on a 220-stud slab
Shapes.LIFT = 0.02          -- sit just above the host so there is no z-fight

local function piece(parent, name, size, cf, host)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = host.Material
	p.Color = host.Color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

--[[ Lay a rounded version of `host` on top of it. The apron is inset by the
	radius on all four sides, so its outline sits INSIDE the host's footprint
	and the square corners underneath are left showing only where the lawn
	already continues -- which is why the host is a lawn slab and not a wall. ]]
function Shapes.roundSlab(host, radius)
	if not host or not host:IsA("BasePart") then return 0 end
	if host:FindFirstChild("Apron") then return 0 end
	local r = math.min(radius or Shapes.RADIUS, host.Size.X / 2 - 1, host.Size.Z / 2 - 1)
	if r <= 1 then return 0 end

	local folder = Instance.new("Folder")
	folder.Name = "Apron"
	folder.Parent = host

	local th = 0.12
	local y = host.Size.Y / 2 + Shapes.LIFT
	local X, Z = host.Size.X, host.Size.Z
	local made = 0

	-- the cross: two boxes that cover everything except the four corners
	piece(folder, "ApronA", Vector3.new(X, th, Z - 2 * r), host.CFrame * CFrame.new(0, y, 0), host)
	piece(folder, "ApronB", Vector3.new(X - 2 * r, th, Z), host.CFrame * CFrame.new(0, y, 0), host)
	made += 2

	-- and a quarter disc at each corner. A Cylinder's axis is its X, so it is
	-- laid flat by rotating 90 degrees about Z.
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			piece(folder, "ApronCorner",
				Vector3.new(th, r * 2, r * 2),
				host.CFrame * CFrame.new(sx * (X / 2 - r), y, sz * (Z / 2 - r)) * CFrame.Angles(0, 0, math.rad(90)),
				host)
			made += 1
		end
	end
	for _, d in ipairs(folder:GetChildren()) do
		d.Shape = d.Name == "ApronCorner" and Enum.PartType.Cylinder or Enum.PartType.Block
		-- the apron is decoration laid on a host that is already in the palette
		CS:AddTag(d, "SVStructural")
	end
	return made
end

-- every lawn slab in the world, rounded in one pass
function Shapes.apply(root)
	local n, hosts = 0, 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "CampusSlab" or d.Name == "PadVerge") then
			local m = Shapes.roundSlab(d)
			if m > 0 then hosts += 1 end
			n += m
		end
	end
	return hosts, n
end

return Shapes
