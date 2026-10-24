--[[
	OfficeCullClient (24 Oct 2026, art pass 4, Task 5) -- far offices are not drawn.

	Measured after 1d: the tower drew 537-550k triangles from the plaza at hq:100, already over the
	500k rule, and the dressing adds more. Past ~150 studs an office is a few pixels behind glass.
	So, on this client only: every room whose centre (the RoomCentre attribute Wafers sets) is farther
	than OfficeLayout.CULL.far from the camera hides its dressing (SVDressing) and its kit furniture
	(SVRoomKit, ruling 8); inside CULL.near it comes back. The racks, the fans, the station, the signs
	and the walls never hide. Checked twice a second; only rooms that change are touched.

	A SurfaceGui draws even on a hidden part, so a hidden room's screens and prints are switched off
	too, and put back as they were.
]]
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local OL = require(RS:WaitForChild("OfficeLayout")).with(require(RS:WaitForChild("TowerPlan")), require(RS:WaitForChild("ServerRack")))
local C = OL.CULL

local rooms = {}   -- [room Model] = { centre = Vector3, parts = { [BasePart] = true }, hidden = bool, guis = { [SurfaceGui] = was } }

-- the room model (Wafers names it L<level>_segment_<dept>); its RoomCentre may replicate a moment later
local function roomOf(part)
	local m = part:FindFirstAncestorWhichIsA("Model")
	while m and not m.Name:match("^L%d+_segment") do m = m:FindFirstAncestorWhichIsA("Model") end
	return m
end

local function setHidden(room, on)
	for part in pairs(room.parts) do
		if part.Parent then
			part.LocalTransparencyModifier = on and 1 or 0
			for _, g in ipairs(part:GetDescendants()) do
				if g:IsA("SurfaceGui") then
					if on then
						room.guis[g] = g.Enabled
						g.Enabled = false
					elseif room.guis[g] ~= nil then
						g.Enabled = room.guis[g]
					end
				end
			end
		else
			room.parts[part] = nil
		end
	end
	if not on then room.guis = {} end
	room.hidden = on
end

local function consider(part)
	if not part:IsA("BasePart") then return end
	local m = roomOf(part)
	if not m then return end
	local room = rooms[m]
	if not room then
		room = { centre = m:GetAttribute("RoomCentre"), parts = {}, hidden = false, guis = {} }
		rooms[m] = room
	end
	room.parts[part] = true
	if room.hidden then   -- a part that arrives in a hidden room (a re-dress) hides at once
		part.LocalTransparencyModifier = 1
		for _, g in ipairs(part:GetDescendants()) do
			if g:IsA("SurfaceGui") then room.guis[g] = g.Enabled; g.Enabled = false end
		end
	end
end

for _, tag in ipairs(C.tags) do
	for _, p in ipairs(CollectionService:GetTagged(tag)) do consider(p) end
	CollectionService:GetInstanceAddedSignal(tag):Connect(consider)
end

task.spawn(function()
	local cam = workspace.CurrentCamera
	while true do
		cam = workspace.CurrentCamera or cam
		local eye = cam.CFrame.Position
		for m, room in pairs(rooms) do
			if not m.Parent then
				rooms[m] = nil
			else
				room.centre = room.centre or m:GetAttribute("RoomCentre")
			end
			if m.Parent and typeof(room.centre) == "Vector3" then
				local want = OL.cullNext(room.hidden, (room.centre - eye).Magnitude)
				if want ~= room.hidden then setHidden(room, want) end
			end
		end
		task.wait(C.every)
	end
end)
