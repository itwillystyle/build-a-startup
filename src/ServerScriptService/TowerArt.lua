--[[ TowerArt (16 Oct 2026, HQ tower part 1d): the tower's art, built from Parts.
	Spec: docs/superpowers/specs/2026-10-16-hq-art-1d-design.md. Mocks: ui/2026-10-16-art-1d/mocks.
	Wafers owns the building and calls in here; it injects its two part helpers (TowerArt.init), so every
	part still goes through SiliconCore's `part` (the palette at authoring time). Geometry is TowerPlan's
	(pure, tested); colours are TowerFinish's. Nothing here collides unless a player stands on it. ]]
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local T = require(RS:WaitForChild("TowerPlan"))
local TF = require(RS:WaitForChild("TowerFinish"))

local TowerArt = {}
local box, part   -- box(model, plot, name, x0, x1, z0, z1, y0, y1, props); part(props, parent)

function TowerArt.init(deps) box, part = deps.box, deps.part end

function TowerArt.c3(t) return TF.color(t) end
local c3 = TowerArt.c3
TowerArt.NOHIT = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
local NOHIT = TowerArt.NOHIT
function TowerArt.with(base, extra)
	local o = table.clone(base)
	for k, v in pairs(extra or {}) do o[k] = v end
	return o
end
local with = TowerArt.with

--[[ a light SkyClient switches at night (spec §2.7): tagged SVNightLight; `gate` = only from beyond 46
	studs (a room's ceiling: close up you see the room, not a glowing slab); `dark` = this room's lights
	stay off. The Neon finish's lines glow by day too (`Always`). Reviewed emissive: SVEmissive. ]]
function TowerArt.nightLight(p, fin, opts)
	if not p then return nil end
	opts = opts or {}
	CollectionService:AddTag(p, "SVNightLight")
	CollectionService:AddTag(p, "SVEmissive")
	if opts.gate then p:SetAttribute("Gate", true) end
	if opts.dark then p:SetAttribute("Dark", true) end
	if fin and fin.lineDay and not opts.gate then
		p:SetAttribute("Always", true)
		p.Material = Enum.Material.Neon
	end
	return p
end
local nightLight = TowerArt.nightLight

-- a panel from plot point a to b ({x, z}), y0..y1, t thick (one corner facet)
function TowerArt.panel(model, plot, name, a, b, y0, y1, t, props)
	local dx, dz = b.x - a.x, b.z - a.z
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 0.05 then return nil end
	local mx, mz, my = (a.x + b.x) / 2, (a.z + b.z) / 2, (y0 + y1) / 2
	local p = part(with(props, { Name = name, Size = Vector3.new(t, y1 - y0, len + 0.06) }), model)
	p.CFrame = plot.pivot * CFrame.lookAt(Vector3.new(mx, my, mz), Vector3.new(mx + dx, my, mz + dz))
	return p
end
local panel = TowerArt.panel

--[[ one room's facade (spec §2.1, §2.2): on every glass side, fins (office floors), the band with its lip
	(the next slab's edge), the light line tucked under it, Timber's planters; the corner's three glass
	panels and the band and line following them. The glass walls themselves are Wafers' (wallSide, cut
	short of the corner by T.cuts). y = the room's floor, h = its glass height. ]]
function TowerArt.facade(model, plot, storey, seg, y, h, fin, glassProps)
	local r = T.room(storey, seg)
	local cut = T.cuts(storey, seg)
	local office = storey > 0
	local top = y + h
	local finP = with(NOHIT, { Color = c3(fin.fin), Material = Enum.Material.SmoothPlastic })
	local bandP = with(NOHIT, { Color = c3(fin.band), Material = Enum.Material.SmoothPlastic })
	local lineP = with(NOHIT, { Color = c3(fin.line), Material = Enum.Material.SmoothPlastic })
	local leafP = with(NOHIT, { Color = c3(TF.LEAF), Material = Enum.Material.SmoothPlastic })
	local potP = with(NOHIT, { Color = c3(fin.planter), Material = Enum.Material.SmoothPlastic })
	-- the lobby's roof band is 1a's (RoofBand, top - 1.2 .. top + 0.6); its light line sits under it
	local lineY0, lineY1 = office and (top - 0.3) or (top - 1.5), office and top or (top - 1.2)
	for side, kind in pairs(r.sides) do
		if kind == "glass" then
			local alongX = (side == "pz" or side == "nz")
			local lo = (alongX and r.x0 or r.z0) + cut[side].lo
			local hi = (alongX and r.x1 or r.z1) - cut[side].hi
			local face = (side == "pz" and r.z1) or (side == "nz" and r.z0) or (side == "px" and r.x1) or r.x0
			local o = (side == "pz" or side == "px") and 1 or -1
			local function rect(a0, a1, d0, d1, y0, y1, name, props)
				local f0, f1 = face + o * d0, face + o * d1
				if f0 > f1 then f0, f1 = f1, f0 end
				if alongX then return box(model, plot, name, a0, a1, f0, f1, y0, y1, props) end
				return box(model, plot, name, f0, f1, a0, a1, y0, y1, props)
			end
			if office then
				local n = math.max(1, math.floor((hi - lo) / fin.finStep + 0.5))
				for k = 0, n - 1 do   -- each room owns its low end: no two fins on one seam
					local a = lo + (hi - lo) * k / n
					rect(a - fin.finW / 2, a + fin.finW / 2, 0, fin.finD, y, top, "Fin", finP)
				end
				rect(lo, hi, 0, T.LIP, top, top + T.SLAB, "Band", bandP)
				if fin.planters and alongX then
					for a = lo + 4, hi - 4, 7 do
						rect(a - 2.4, a + 2.4, T.LIP - 0.2, T.LIP + 1.0, top + T.SLAB, top + T.SLAB + 0.9, "Planter", potP)
						rect(a - 2.2, a + 2.2, T.LIP - 0.1, T.LIP + 0.9, top + T.SLAB + 0.9, top + T.SLAB + 1.6, "Plants", leafP)
						rect(a - 1.8, a + 1.8, T.LIP + 0.5, T.LIP + 0.9, top - 1.8, top + T.SLAB, "Plants", leafP)
					end
				end
			end
			nightLight(rect(lo, hi, 0.2, T.LIP - 0.3, lineY0, lineY1, "LightLine", lineP), fin)
		end
	end
	for _, cn in ipairs(T.corners(storey, seg)) do
		local R = T.CORNER
		local gl = T.arc(cn, R, T.WALL_T / 2)          -- the glass, on the wall line
		local band = T.arc(cn, R, -T.LIP / 2)         -- the band, face to lip
		local line = T.arc(cn, R, -(T.LIP - 0.1) / 2) -- the light line
		for k = 1, 3 do
			panel(model, plot, "Wall", gl[k], gl[k + 1], y, top, T.WALL_T, glassProps)
			if office then panel(model, plot, "Band", band[k], band[k + 1], top, top + T.SLAB, T.LIP, bandP) end
			nightLight(panel(model, plot, "LightLine", line[k], line[k + 1], lineY0, lineY1, T.LIP - 0.5, lineP), fin)
		end
	end
end

-- a room's ceiling light (spec §2.7): lit at night from beyond 46 studs; `dark` rooms stay off
function TowerArt.ceilingStrip(model, plot, r, y, h, dark)
	local p = box(model, plot, "CeilingStrip", r.x0 + 2.5, r.x1 - 2.5, r.z0 + 2.5, r.z1 - 2.5, y + h - 0.75, y + h - 0.4,
		with(NOHIT, { Color = c3(TF.STRIP), Material = Enum.Material.SmoothPlastic }))
	return nightLight(p, nil, { gate = true, dark = dark })
end

return TowerArt
