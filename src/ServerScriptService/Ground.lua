--[[
	Ground -- who owns which patch of dirt (v4.9).

	THE BUG THIS EXISTS FOR, reported 4 Oct with a screenshot: Kenney bushes
	standing in the middle of the new parking district. Measured: 32 pieces of
	valley greenery inside a district slab, 18 on a pad verge and 14 standing
	on shop ROOFS.

	THE CAUSE IS BUILD ORDER, not placement. The live log says it plainly:
	valley -> street -> city -> downtown -> campus hub -> districts. ValleyGen
	plants 4,568 trees first, and the district builder paves on top of them
	twenty seconds later without clearing anything. ValleyGen's own spacing
	registry (claimTree) only ever stopped a tree overlapping ANOTHER TREE --
	it has no idea a car park is coming.

	The pattern already existed and the districts just did not use it: Wafers
	has clearFootprint, which destroys anything taller than paving inside the
	building's footprint. This generalises that one-off into something every
	builder can call, and -- the part that matters -- makes it ORDER
	INDEPENDENT. A builder reserves the ground it paves whenever it runs, and
	ONE sweep at the end of the world build removes the greenery left standing
	on reserved ground. It no longer matters who ran first.

	A builder's own decor is never touched: the sweep is pointed only at the
	greenery roots (the valley), never at what a district planted on purpose.

	Ground.publish writes the zones onto the world as an attribute so
	tools/world_overlap.luau can check them from outside, which is how a
	builder that forgets to reserve gets caught.
]]

local HttpService = game:GetService("HttpService")

local Ground = {}

local zones = {}

--[[ How far above a reserved surface something has to be before it counts as
	standing ON it. A tree planted on the ground has its base at the surface; a
	tree far below (a valley floor under a raised roof) is somebody else's. ]]
local BAND_DOWN, BAND_UP = 4, 10
local MARGIN = 1.5                -- a little slack at the kerb

function Ground.reset()
	table.clear(zones)
end

--[[ Reserve the top face of a slab that was just built. Taking the PART rather
	than numbers is deliberate: the caller cannot get the maths wrong, and a
	later change to the slab's size or angle carries over for free. ]]
function Ground.reservePart(part, name)
	if not (part and part:IsA("BasePart")) then return nil end
	local zone = {
		name = name or part.Name,
		cf = part.CFrame,
		hx = part.Size.X / 2 + MARGIN,
		hz = part.Size.Z / 2 + MARGIN,
		surface = part.Position.Y + part.Size.Y / 2,
	}
	table.insert(zones, zone)
	return zone
end

function Ground.zones() return zones end

local function insideXZ(zone, pos)
	local lp = zone.cf:PointToObjectSpace(pos)
	return math.abs(lp.X) <= zone.hx and math.abs(lp.Z) <= zone.hz
end

-- the zone this object is standing on, if any
function Ground.zoneAt(pos, baseY)
	for _, z in ipairs(zones) do
		if insideXZ(z, pos) and baseY >= z.surface - BAND_DOWN and baseY <= z.surface + BAND_UP then
			return z
		end
	end
	return nil
end

--[[ What counts as clearable greenery. Named rather than tagged because the
	valley's trees come from four different generations of this project and
	nothing tags them consistently; the names, at least, have always been
	descriptive. ]]
local GREEN = { "tree", "bush", "palm", "oak", "pine", "redwood", "eucalypt", "orchard", "grove", "shrub", "plant" }

local function isGreenery(inst)
	local n = inst.Name:lower()
	for _, w in ipairs(GREEN) do
		if string.find(n, w, 1, true) then return true end
	end
	return false
end

local function baseOf(inst)
	if inst:IsA("Model") then
		local ok, cf, ext = pcall(function()
			local a, b = inst:GetBoundingBox()
			return a, b
		end)
		if ok and ext then return cf.Position, cf.Position.Y - ext.Y / 2 end
		return nil, nil
	elseif inst:IsA("BasePart") then
		return inst.Position, inst.Position.Y - inst.Size.Y / 2
	end
	return nil, nil
end

--[[ Remove greenery standing on reserved ground. `roots` are the folders whose
	contents may be cleared -- the valley only. Returns how many went, and a
	per-zone tally, because a silent sweep is how you end up not noticing it
	deleted the wrong thing. ]]
function Ground.sweep(roots)
	local removed, byZone = 0, {}
	for _, root in ipairs(roots) do
		if root then
			local doomed = {}
			for _, inst in ipairs(root:GetDescendants()) do
				if (inst:IsA("Model") or inst:IsA("BasePart")) and isGreenery(inst) then
					-- a model's parts are handled by the model; do not count twice
					local parentIsGreen = inst.Parent and inst.Parent ~= root and isGreenery(inst.Parent)
					if not parentIsGreen then
						local pos, base = baseOf(inst)
						if pos then
							local z = Ground.zoneAt(pos, base)
							if z then
								table.insert(doomed, inst)
								byZone[z.name] = (byZone[z.name] or 0) + 1
							end
						end
					end
				end
			end
			for _, inst in ipairs(doomed) do
				inst:Destroy()
				removed += 1
			end
		end
	end
	return removed, byZone
end

--[[ Write the zones onto the world so a check running outside this module can
	read them. Attributes cannot hold tables, so it is JSON, and the CFrame is
	reduced to a position and a yaw because every zone is a flat slab. ]]
function Ground.publish(container)
	if not container then return end
	local out = {}
	for _, z in ipairs(zones) do
		local _, y = z.cf:ToEulerAnglesYXZ()
		table.insert(out, {
			n = z.name,
			x = math.floor(z.cf.Position.X * 10) / 10,
			z = math.floor(z.cf.Position.Z * 10) / 10,
			y = math.floor(z.surface * 10) / 10,
			hx = math.floor(z.hx * 10) / 10,
			hz = math.floor(z.hz * 10) / 10,
			yaw = math.floor(y * 1000) / 1000,
		})
	end
	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, out)
	if ok then container:SetAttribute("GroundZones", encoded) end
end

return Ground
