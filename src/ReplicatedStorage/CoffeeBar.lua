--[[ CoffeeBar (14 Oct 2026): the Dome cafe's coffee bar, as data. Pure.

	The look is an imported mesh, SV_CoffeeBar_cafe in ReplicatedStorage.SVMeshes, made by
	silicon-startup/art/blender/cafe_v3.py (+ rack_export.py, judged by rack_check.luau on a
	MEASURED 7,000-triangle budget, see the script's header): a walnut-slatted counter, a
	cream espresso machine, grinder, cups, a cake stand, pendant lamps, a slatted backsplash
	with a round menu, and a detailed back (it faces the tower's outer glass). It REPLACES the
	kitchenette run (two kitchenBars, the end cap and the small coffee machine); the fridge
	stays. Where a place has no mesh (the TEST experience) the room builds the run as before.

	The run's numbers live here so the fallback and the mesh share them, and the tests can
	prove the mesh stands where the run stood and clears the fridge:
	  RUN    the kitchenette's pieces (Kenney kit widths, measured 5 Oct; worktop 2.47)
	  pose   the mesh's FRONT is its +Z (the export turns it so), the counter faces the room
	         (local -Z, toward rm), so it is turned half a circle, like ServerRack; its BACK
	         sits where the run's back sat, so it clears the glass exactly as the run did. ]]
local CoffeeBar = {}

CoffeeBar.MESH = "SV_CoffeeBar_cafe"
CoffeeBar.NAME = "SV_CoffeeBar"            -- SV prefix: Palette leaves our meshes alone
CoffeeBar.SLOT = Vector3.new(5.8, 6, 1.9)  -- the run's width and a splash; the mesh is 5.74 x 5.07 x 1.895
CoffeeBar.MIN_HEIGHT = 0.8                 -- of the slot: shorter is a wrong-scale import

CoffeeBar.RUN = { BAR_W = 2.53, END_W = 0.60, FRIDGE_W = 2.53, DEPTH = 1.72, TOP = 2.47, FRIDGE_GAP = 0.2 }

-- the run laid out from a measured left edge, centred on the wedge (x along the wall)
function CoffeeBar.layout()
	local R = CoffeeBar.RUN
	local runW = R.BAR_W * 2 + R.END_W
	local left = -runW / 2
	local b1 = left + R.BAR_W / 2
	local b2 = b1 + R.BAR_W
	local cap = b2 + R.BAR_W / 2 + R.END_W / 2
	local fridgeX = cap + R.END_W / 2 + R.FRIDGE_GAP + R.FRIDGE_W / 2
	return { b1 = b1, b2 = b2, cap = cap, fridgeX = fridgeX, runLeft = left, runRight = cap + R.END_W / 2 }
end

-- the mesh's CFrame in the room's frame, given the run's z (its centre line): on the floor,
-- centred on the wedge, its back flush with the run's back, its front toward the room
function CoffeeBar.pose(z, meshSize)
	local back = z + CoffeeBar.RUN.DEPTH / 2
	return CFrame.new(0, meshSize.Y / 2, back - meshSize.Z / 2) * CFrame.Angles(0, math.pi, 0)
end

function CoffeeBar.fits(size)
	local s = CoffeeBar.SLOT
	return size.X <= s.X + 1e-3 and size.Y <= s.Y + 1e-3 and size.Z <= s.Z + 1e-3
		and size.Y >= s.Y * CoffeeBar.MIN_HEIGHT
end

return CoffeeBar
