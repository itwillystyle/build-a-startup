--[[
	world_overlap -- is anything standing where something else was built? (v4.9)

	THE SIBLING OF tools/ui_overlap.luau, for the same reason and after the
	same kind of bug. On 4 Oct a screenshot showed Kenney bushes standing in
	the middle of the new parking district. Measured: 32 pieces of valley
	greenery inside a district slab, including 14 on shop ROOFS.

	The cause was build order -- the valley plants 4,568 trees before the
	districts pave over them -- and the fix is Ground.lua, a footprint registry
	with one sweep at the end of the world build. But a registry only works if
	builders remember to call it, and "remember" is not a mechanism. This is
	the mechanism: it reads the zones Ground published and fails if anything is
	still standing on them, so a new district that forgets to reserve its
	ground gets caught here instead of in a screenshot three weeks later.

	It also catches props grown into each other, which is the same family of
	bug one level down.

	HOW TO RUN. In a Play session, on the SERVER datamodel. It changes nothing.

	WHAT IT REPORTS
	  1. GREENERY ON PAVING -- anything leafy standing on a reserved slab.
	     Should be 0 after Ground.sweep. Anything here is a builder that
	     reserved its ground too late, or not at all.
	  2. ZONES THAT NOBODY RESERVED -- large flat slabs in the campus folders
	     that are NOT in the registry. These are the ones that will grow this
	     bug next, and they are the real early warning.
	  3. PROPS INSIDE PROPS -- two pieces of decor sharing space. Checked on a
	     grid, because comparing 4,500 trees pairwise is not a check anybody
	     will run twice.
]]

local HttpService = game:GetService("HttpService")

local sv = workspace:FindFirstChild("SiliconValley")
assert(sv, "no SiliconValley folder: run this in a Play session")

local out = {}
local function say(f, ...) table.insert(out, string.format(f, ...)) end

-- ---------------------------------------------------------------- the registry
local zones = {}
do
	local raw = sv:GetAttribute("GroundZones")
	if raw then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok then
			for _, z in ipairs(decoded) do
				z.cf = CFrame.new(z.x, z.y, z.z) * CFrame.Angles(0, z.yaw, 0)
				table.insert(zones, z)
			end
		end
	end
end
say("world_overlap  -  %d reserved zones", #zones)

local GREEN = { "tree", "bush", "palm", "oak", "pine", "redwood", "eucalypt", "orchard", "grove", "shrub", "plant" }
local function isGreenery(inst)
	local n = inst.Name:lower()
	for _, w in ipairs(GREEN) do
		if string.find(n, w, 1, true) then return true end
	end
	return false
end

local function boxOf(inst)
	if inst:IsA("Model") then
		local ok, cf, ext = pcall(function()
			local a, b = inst:GetBoundingBox()
			return a, b
		end)
		if ok and ext then return cf.Position, ext end
	elseif inst:IsA("BasePart") then
		return inst.Position, inst.Size
	end
	return nil, nil
end

-- ---------------------------------------------------------------- 1. greenery on paving
local offenders, byZone = 0, {}
for _, rootName in ipairs({ "LowPolyWorld", "Valley" }) do
	local root = sv:FindFirstChild(rootName)
	if root then
		for _, inst in ipairs(root:GetDescendants()) do
			if (inst:IsA("Model") or inst:IsA("BasePart")) and isGreenery(inst)
				and not (inst.Parent and inst.Parent ~= root and isGreenery(inst.Parent)) then
				local pos, ext = boxOf(inst)
				if pos then
					local base = pos.Y - ext.Y / 2
					for _, z in ipairs(zones) do
						local lp = z.cf:PointToObjectSpace(pos)
						if math.abs(lp.X) <= z.hx and math.abs(lp.Z) <= z.hz
							and base >= z.y - 4 and base <= z.y + 10 then
							offenders += 1
							byZone[z.n] = (byZone[z.n] or 0) + 1
							break
						end
					end
				end
			end
		end
	end
end
say("")
say("1. GREENERY STANDING ON RESERVED PAVING: %d", offenders)
for k, v in pairs(byZone) do say("     %-22s %d", k, v) end

-- ---------------------------------------------------------------- 2. unreserved paving
local unclaimed = 0
say("")
say("2. LARGE FLAT SLABS NOBODY RESERVED")
for _, folderName in ipairs({ "CampusDistricts", "CampusHub", "Downtown" }) do
	local folder = sv:FindFirstChild(folderName)
	if folder then
		for _, p in ipairs(folder:GetDescendants()) do
			if p:IsA("BasePart") and p.Size.X > 60 and p.Size.Z > 60 and p.Size.Y < 6 then
				local claimed = false
				for _, z in ipairs(zones) do
					if (Vector3.new(z.x, 0, z.z) - Vector3.new(p.Position.X, 0, p.Position.Z)).Magnitude < 6 then
						claimed = true
						break
					end
				end
				if not claimed then
					unclaimed += 1
					if unclaimed <= 14 then
						say("     %-18s %-16s at %6.0f,%6.0f  %3.0f x %3.0f",
							folderName, p.Name, p.Position.X, p.Position.Z, p.Size.X, p.Size.Z)
					end
				end
			end
		end
	end
end
say("   UNRESERVED: %d  (each one can grow the same bug)", unclaimed)

-- ---------------------------------------------------------------- 3. props inside props
--[[ On a 24-stud grid: a prop is only compared with props in its own cell and
	the eight around it. Pairwise over the whole valley would be ~10 million
	comparisons and nobody would run it twice. ]]
local CELL = 24
local cells, props = {}, {}
for _, folderName in ipairs({ "CampusDistricts", "CampusHub", "Valley" }) do
	local folder = sv:FindFirstChild(folderName)
	if folder then
		for _, inst in ipairs(folder:GetDescendants()) do
			if inst:IsA("Model") and #inst:GetChildren() > 0 and inst.Parent == folder then
				local pos, ext = boxOf(inst)
				if pos and ext and ext.Y > 2 then
					local it = { inst = inst, pos = pos, ext = ext, folder = folderName }
					table.insert(props, it)
					local key = ("%d:%d"):format(math.floor(pos.X / CELL), math.floor(pos.Z / CELL))
					cells[key] = cells[key] or {}
					table.insert(cells[key], it)
				end
			end
		end
	end
end

local pairsHit, shown = 0, 0
say("")
say("3. PROPS GROWN INTO EACH OTHER  (%d props checked)", #props)
local seen = {}
for _, a in ipairs(props) do
	local cx, cz = math.floor(a.pos.X / CELL), math.floor(a.pos.Z / CELL)
	for dx = -1, 1 do
		for dz = -1, 1 do
			for _, b in ipairs(cells[("%d:%d"):format(cx + dx, cz + dz)] or {}) do
				if a ~= b then
					local key = a.inst:GetDebugId() < b.inst:GetDebugId()
						and (a.inst:GetDebugId() .. b.inst:GetDebugId())
						or (b.inst:GetDebugId() .. a.inst:GetDebugId())
					if not seen[key] then
						local ox = (a.ext.X + b.ext.X) / 2 - math.abs(a.pos.X - b.pos.X)
						local oz = (a.ext.Z + b.ext.Z) / 2 - math.abs(a.pos.Z - b.pos.Z)
						local oy = (a.ext.Y + b.ext.Y) / 2 - math.abs(a.pos.Y - b.pos.Y)
						-- a real interpenetration, not two canopies brushing
						if ox > 2.5 and oz > 2.5 and oy > 2.5
							and ox > math.min(a.ext.X, b.ext.X) * 0.45
							and oz > math.min(a.ext.Z, b.ext.Z) * 0.45 then
							seen[key] = true
							pairsHit += 1
							if shown < 12 then
								shown += 1
								say("     %-16s x %-16s at %6.0f,%6.0f  (%0.0f x %0.0f studs deep)",
									a.inst.Name, b.inst.Name, a.pos.X, a.pos.Z, ox, oz)
							end
						end
					end
				end
			end
		end
	end
end
say("   INTERPENETRATING PAIRS: %d", pairsHit)

say("")
say("VERDICT: %s", (offenders == 0 and unclaimed == 0 and pairsHit == 0) and "clean"
	or ("%d on paving, %d unreserved slabs, %d prop pairs"):format(offenders, unclaimed, pairsHit))
return table.concat(out, "\n")
