--[[ ServerRack (13 Oct 2026): the Servers room's rack, as data. Pure.

	The look is an imported mesh, SV_Rack_servers in ReplicatedStorage.SVMeshes, made by
	silicon-startup/art/blender/rack_v6.py (+ rack_export.py, judged by rack_check.luau):
	a cream rounded shell, walnut slats, rails, patch cables and a silicon wafer crown,
	all palette vertex colour. Where a place has no mesh (the TEST experience, a fresh
	copy) the room builds the plain box it always had, in the same slot.

	Two facts the room builders must not guess, so they live here and are tested:
	  SLOT  the plain rack's box; the mesh is built to fit inside it (2.74 x 6.71 x 2.18)
	  pose  the mesh's FRONT is its +Z (measured 13 Oct: the export turns it so), while a
	        room's racks face local -Z, toward the room (rm + 3 is the back, the light
	        strip sat at rm + 1.85). So the mesh is turned half a circle. The first import
	        faced the wrong way and showed its cables; this is that lesson, pinned.
	The plain rack's pulsing light strip is NOT built with the mesh, on purpose: at y 5.6
	it would cross the mesh's porthole and stickers, and the mesh carries its own
	department-colour light lines. The room's fans still turn. ]]
local ServerRack = {}

ServerRack.MESH = "SV_Rack_servers"
-- in-game name: Palette leaves a mesh alone only with an SV prefix (Palette.OWN_PREFIX);
-- a bare "Rack" would be washed warm like a third-party pack
ServerRack.NAME = "SV_Rack"
ServerRack.SLOT = Vector3.new(3, 7, 2.2)
ServerRack.XS = { -6, -2, 2, 6 }          -- the four racks along a room, as before
ServerRack.BACK = 3                        -- z offset from the room's midline (rm + 3)

-- the mesh's CFrame in the room's frame: standing on the floor (y = 0), its front to -Z
function ServerRack.pose(x, rm, meshHeight)
	return CFrame.new(x, meshHeight / 2, rm + ServerRack.BACK) * CFrame.Angles(0, math.pi, 0)
end

-- does a mesh of this size fit the plain rack's slot? Too big would poke into the fans
-- and the glass; too SMALL is a wrong-scale import (review, 13 Oct: four specks a room
-- and no fallback), so it must also stand at least MIN_HEIGHT of the slot
ServerRack.MIN_HEIGHT = 0.8
function ServerRack.fits(size)
	local s = ServerRack.SLOT
	return size.X <= s.X + 1e-3 and size.Y <= s.Y + 1e-3 and size.Z <= s.Z + 1e-3
		and size.Y >= s.Y * ServerRack.MIN_HEIGHT
end

return ServerRack
