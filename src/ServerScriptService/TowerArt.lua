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
	if opts.hide then   -- look review: by day a ceiling strip read as a black bar through the glass
		p:SetAttribute("Hide", true)
		p.Transparency = 1
	end
	if fin and fin.lineDay and not opts.gate and not opts.hide then
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

-- a room's ceiling light (spec §2.7): lit at night from beyond 46 studs; `dark` rooms stay off. Look review
-- (16 Oct): a whole-ceiling panel made the top half of every floor glow and showed as a black bar by day; it
-- is a 2-stud bar down the room's long axis now, invisible until it lights
function TowerArt.ceilingStrip(model, plot, r, y, h, dark)
	local cx, cz = (r.x0 + r.x1) / 2, (r.z0 + r.z1) / 2
	local x0, x1, z0, z1
	if (r.x1 - r.x0) >= (r.z1 - r.z0) then
		x0, x1, z0, z1 = r.x0 + 4, r.x1 - 4, cz - 1, cz + 1
	else
		x0, x1, z0, z1 = cx - 1, cx + 1, r.z0 + 4, r.z1 - 4
	end
	local p = box(model, plot, "CeilingStrip", x0, x1, z0, z1, y + h - 0.75, y + h - 0.4,
		with(NOHIT, { Color = c3(TF.STRIP), Material = Enum.Material.SmoothPlastic }))
	return nightLight(p, nil, { gate = true, dark = dark, hide = true })
end

-- a name on a part's face, readable from the plaza (the entrance sign, the crown plate)
function TowerArt.nameText(p, face)
	local sg = Instance.new("SurfaceGui")
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.Face, sg.PixelsPerStud, sg.LightInfluence, sg.MaxDistance = face, 30, 0, 600
	sg.Parent = p
	local tl = Instance.new("TextLabel")
	tl.Name, tl.Size, tl.Position = "Text", UDim2.fromScale(0.92, 0.76), UDim2.fromScale(0.04, 0.12)
	tl.BackgroundTransparency, tl.TextScaled, tl.Font = 1, true, Enum.Font.FredokaOne
	tl.TextColor3, tl.Text = c3(TF.GOLD), "YOUR STARTUP"
	tl.Parent = sg
	return tl
end

--[[ the lobby's entrance (spec §2.3): door frames round the 14-wide doorway, a lit strip under the
	canopy (y+10..y+11, z1..z1+10, 1a's LobbyCanopy), and a sign board on the canopy's front edge with the
	company's name. Returns the name's label (Wafers keeps it fresh). ]]
function TowerArt.entrance(model, plot, r, y, fin)
	local bandP = with(NOHIT, { Color = c3(fin.frame), Material = Enum.Material.SmoothPlastic })   -- look review: white on white vanished
	local w = r.entrance.width
	box(model, plot, "DoorFrame", r.cx - w / 2 - 0.6, r.cx - w / 2, r.z1 - 0.2, r.z1 + 0.6, y, y + 10, bandP)
	box(model, plot, "DoorFrame", r.cx + w / 2, r.cx + w / 2 + 0.6, r.z1 - 0.2, r.z1 + 0.6, y, y + 10, bandP)
	box(model, plot, "DoorFrame", r.cx - w / 2 - 0.6, r.cx + w / 2 + 0.6, r.z1 - 0.2, r.z1 + 0.6, y + 9.4, y + 10, bandP)
	-- two strips, not one panel: a 9-deep non-solid panel near the ground reads to WorldHealth as a
	-- surface you sink through (doctor, 16 Oct); the spec asks for a lit strip anyway
	local lineP = with(NOHIT, { Color = c3(fin.line), Material = Enum.Material.SmoothPlastic })
	for _, z in ipairs({ r.z1 + 1.0, r.z1 + 8.4 }) do
		nightLight(box(model, plot, "LightLine", r.cx - 10.5, r.cx + 10.5, z, z + 1.0, y + 9.7, y + 10, lineP), fin)
	end
	local board = box(model, plot, "EntranceSign", r.cx - 11, r.cx + 11, r.z1 + 9.4, r.z1 + 9.9, y + 11, y + 14,
		with(NOHIT, { Color = c3(fin.plate), Material = Enum.Material.SmoothPlastic }))
	return TowerArt.nameText(board, Enum.NormalId.Back)   -- +Z: toward the street
end

-- planters on the podium roof (spec §2.3): along this lobby room's glass sides, where floor 1 does not stand
function TowerArt.podium(model, plot, r, y, h, fin)
	local up = T.rect(1)
	local top = y + h + 0.6   -- 1a's RoofBand top
	local potP = { Color = c3(fin.planter), Material = Enum.Material.SmoothPlastic, CastShadow = false }
	local leafP = with(NOHIT, { Color = c3(TF.LEAF), Material = Enum.Material.SmoothPlastic })
	local function under(x, z) return x > -up.hx and x < up.hx and z > up.zb and z < up.zf end
	for side, kind in pairs(r.sides) do
		if kind == "glass" then
			local alongX = (side == "pz" or side == "nz")
			local lo, hi = alongX and r.x0 or r.z0, alongX and r.x1 or r.z1
			local face = (side == "pz" and r.z1) or (side == "nz" and r.z0) or (side == "px" and r.x1) or r.x0
			local o = (side == "pz" or side == "px") and 1 or -1
			for a = lo + 6, hi - 6, 10 do
				local d0, d1 = face - o * 3.5, face - o * 1.5
				if d0 > d1 then d0, d1 = d1, d0 end
				local x, z = alongX and a or (d0 + d1) / 2, alongX and (d0 + d1) / 2 or a
				if not under(x, z) then
					if alongX then
						box(model, plot, "Planter", a - 3, a + 3, d0, d1, top, top + 1.2, potP)
						box(model, plot, "Plants", a - 2.7, a + 2.7, d0 + 0.2, d1 - 0.2, top + 1.2, top + 1.8, leafP)
					else
						box(model, plot, "Planter", d0, d1, a - 3, a + 3, top, top + 1.2, potP)
						box(model, plot, "Plants", d0 + 0.2, d1 - 0.2, a - 2.7, a + 2.7, top + 1.2, top + 1.8, leafP)
					end
				end
			end
		end
	end
end

--[[ a terrace strip (spec §2.4; Bosco Verticale, Oasia): a planter edge along the outer edge with the
	glass rail standing on it and a wood handrail; on the main strip (`full`) four trees taller than the
	rail, two benches by the glass, two lamps. t = TowerPlan.terraces' strip, side "front"/"back". ]]
function TowerArt.terrace(model, plot, t, side, y, fin, full)
	local out = (side == "front") and 1 or -1
	local edge = (side == "front") and t.z1 or t.z0
	local inner = (side == "front") and t.z0 or t.z1
	local function zs(a, b)   -- a..b studs in from the edge -> z0, z1
		local z0, z1 = edge - out * a, edge - out * b
		if z0 > z1 then z0, z1 = z1, z0 end
		return z0, z1
	end
	local potP = { Color = c3(fin.planter), Material = Enum.Material.SmoothPlastic }
	local leafP = with(NOHIT, { Color = c3(TF.LEAF), Material = Enum.Material.SmoothPlastic })
	local x0, x1 = t.x0 + 1, t.x1 - 1
	local a, b = zs(0.3, 2.1)
	box(model, plot, "PlanterEdge", x0, x1, a, b, y, y + 1.6, potP)
	a, b = zs(0.5, 1.9)
	box(model, plot, "Plants", x0 + 0.3, x1 - 0.3, a, b, y + 1.6, y + 2.3, leafP)
	a, b = zs(1.9, 2.1)
	box(model, plot, "Rail", x0, x1, a, b, y + 1.6, y + 3.9,
		{ Color = c3(fin.glass), Material = Enum.Material.Glass, Transparency = 0.4, CastShadow = false })
	a, b = zs(1.8, 2.2)
	box(model, plot, "Handrail", x0, x1, a, b, y + 3.9, y + 4.2, potP)
	if not full then return end
	local mid = (edge + inner) / 2 - out * 0.9   -- between the planter edge and the glass
	local span = t.x1 - t.x0
	for _, x in ipairs({ t.x0 + 6, t.x1 - 6, -span * 0.22, span * 0.22 }) do
		box(model, plot, "Trunk", x - 0.35, x + 0.35, mid - 0.35, mid + 0.35, y, y + 5.2, potP)
		local ball = part(with(leafP, { Name = "TreeLeaf", Shape = Enum.PartType.Ball, Size = Vector3.new(4, 4, 4) }), model)
		ball.CFrame = plot.pivot * CFrame.new(x, y + 6.6, mid)
		local ball2 = part(with(leafP, { Name = "TreeLeaf", Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3) }), model)
		ball2.CFrame = plot.pivot * CFrame.new(x + 1.1, y + 8.0, mid)
	end
	local bz = inner + out * 1.6
	for _, x in ipairs({ -6, 6 }) do
		box(model, plot, "Bench", x - 2, x + 2, bz - 0.5, bz + 0.5, y + 0.9, y + 1.15, potP)
		box(model, plot, "BenchLeg", x - 1.8, x - 1.5, bz - 0.4, bz + 0.4, y, y + 0.9, potP)
		box(model, plot, "BenchLeg", x + 1.5, x + 1.8, bz - 0.4, bz + 0.4, y, y + 0.9, potP)
	end
	for _, x in ipairs({ -12, 12 }) do
		box(model, plot, "LampPost", x - 0.15, x + 0.15, mid - 0.15, mid + 0.15, y, y + 3.6,
			{ Color = c3(TF.INK), Material = Enum.Material.SmoothPlastic })
		local lamp = box(model, plot, "Lamp", x - 0.45, x + 0.45, mid - 0.45, mid + 0.45, y + 3.6, y + 4.1,
			with(NOHIT, { Color = c3(TF.GOLD), Material = Enum.Material.Neon }))
		CollectionService:AddTag(lamp, "SVEmissive")
	end
end

--[[ the crown ring (spec §2.5; the `halo` piece's new look): a 12-tall glass screen round the roof's edge,
	1 stud in, rounded corners, fins every 4 on the front, a band with a light line on top, and the dark
	name plate on its front. The mocks showed why: from the plaza the roof edge hides the lantern. ]]
function TowerArt.crownRing(model, plot, roofY, fin)
	local roof = T.deck(14)
	local x0, x1, z0, z1 = roof.x0 + 1, roof.x1 - 1, roof.z0 + 1, roof.z1 - 1
	local R, H, t = T.CORNER, 12, 0.4
	local y0, y1 = roofY, roofY + H
	local glass = { Color = c3(fin.glass), Material = Enum.Material.Glass, Transparency = 0.4, CastShadow = false, CanCollide = false, CanQuery = false }
	local bandP = with(NOHIT, { Color = c3(fin.band), Material = Enum.Material.SmoothPlastic })
	local lineP = with(NOHIT, { Color = c3(fin.line), Material = Enum.Material.SmoothPlastic })
	local finP = with(NOHIT, { Color = c3(fin.fin), Material = Enum.Material.SmoothPlastic })
	local glowP = with(NOHIT, { Color = c3(TF.STRIP), Material = Enum.Material.SmoothPlastic })
	local walls = { { x0 + R, x1 - R, z1 - t, z1, 0, -1 }, { x0 + R, x1 - R, z0, z0 + t, 0, 1 }, { x1 - t, x1, z0 + R, z1 - R, -1, 0 }, { x0, x0 + t, z0 + R, z1 - R, 1, 0 } }
	for _, q in ipairs(walls) do
		box(model, plot, "CrownGlass", q[1], q[2], q[3], q[4], y0, y1, glass)
		box(model, plot, "Band", q[1] - 0.3, q[2] + 0.3, q[3] - 0.3, q[4] + 0.3, y1, y1 + 1.2, bandP)
		nightLight(box(model, plot, "LightLine", q[1], q[2], q[3] - 0.1, q[4] + 0.1, y1 - 0.3, y1, lineP), fin)
		nightLight(box(model, plot, "LightLine", q[1], q[2], q[3] - 0.1, q[4] + 0.1, y0, y0 + 0.3, lineP), fin)
		-- look review: the crown must be the brightest thing at night (research: light the top, Salesforce):
		-- a band behind the ring's glass that lights at night, hidden by day
		local ox, oz = q[5] * 0.5, q[6] * 0.5
		nightLight(box(model, plot, "CrownGlow", q[1] + ox, q[2] + ox, q[3] + oz, q[4] + oz, y0 + 3, y0 + 9, glowP), nil, { hide = true })
	end
	for _, c in ipairs({ { x = x1, z = z1, sx = 1, sz = 1 }, { x = x1, z = z0, sx = 1, sz = -1 }, { x = x0, z = z1, sx = -1, sz = 1 }, { x = x0, z = z0, sx = -1, sz = -1 } }) do
		local p = T.arc(c, R, t / 2)
		for k = 1, 3 do panel(model, plot, "CrownGlass", p[k], p[k + 1], y0, y1, t, glass) end
	end
	for x = x0 + R + 2, x1 - R - 2, 4 do
		box(model, plot, "Fin", x - 0.2, x + 0.2, z1, z1 + 0.5, y0, y1, finP)
	end
	local plate = box(model, plot, "CrownPlate", -12, 12, z1 + 0.5, z1 + 1.1, y0 + 2, y0 + 10,
		with(NOHIT, { Color = c3(fin.plate), Material = Enum.Material.SmoothPlastic }))
	return TowerArt.nameText(plate, Enum.NormalId.Back)
end

-- the light on top of the mast (spec §2.5; BrandGold: the palette has no red)
function TowerArt.beacon(model, plot, x, z, y)
	local b = part(with(NOHIT, { Name = "Beacon", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4),
		Color = c3(TF.GOLD), Material = Enum.Material.Neon }), model)
	b.CFrame = plot.pivot * CFrame.new(x, y + 0.7, z)
	CollectionService:AddTag(b, "SVEmissive")
	return b
end

-- a frame round the lift doors on one landing (spec §2.6); the call button sits in front of its right jamb
function TowerArt.liftFrame(folder, plot, y, fin)
	local S, C = T.SHAFT, T.CAB
	local mid = (S.x0 + S.x1) / 2
	local p = with(NOHIT, { Color = c3(fin.frame), Material = Enum.Material.SmoothPlastic })   -- look review: it vanished on the band
	local hw = C.door / 2
	return {
		box(folder, plot, "LiftFrame", mid - hw - 0.3, mid - hw, S.z1, S.z1 + 0.15, y, y + C.doorH, p),
		box(folder, plot, "LiftFrame", mid + hw, mid + hw + 0.3, S.z1, S.z1 + 0.15, y, y + C.doorH, p),
		box(folder, plot, "LiftFrame", mid - hw - 0.3, mid + hw + 0.3, S.z1, S.z1 + 0.15, y + C.doorH, y + C.doorH + 0.3, p),
	}
end

--[[ the top of the core (spec §2.6): a roof over the top storey's centre hall (the 1c "hole over the
	lobby"), a tidy cap on the shaft, and while that storey is unfinished a small crane on the cap and a
	safety rail on the open roof edges where the next rooms go. Rebuilt with the core, so nothing lingers. ]]
function TowerArt.coreTop(folder, plot, pieces, level, fin)
	local out = {}
	local capY = T.shaftCapY(pieces, level)
	if not capY then return out end
	local S = T.SHAFT
	local top = T.topStorey(pieces, level)
	local bandP = { Color = c3(fin.band), Material = Enum.Material.SmoothPlastic }
	if top < 14 then
		for _, q in ipairs(T.hallRoofRects(top)) do
			table.insert(out, box(folder, plot, "HallRoof", q.x0, q.x1, q.z0, q.z1, capY, capY + T.SLAB, bandP))
		end
	end
	table.insert(out, box(folder, plot, "ShaftCap", S.x0 - 0.6, S.x1 + 0.6, S.z0 - 0.6, S.z1 + 0.6, capY, capY + 5, bandP))
	table.insert(out, box(folder, plot, "ShaftCap", S.x0 - 1.0, S.x1 + 1.0, S.z0 - 1.0, S.z1 + 1.0, capY + 5, capY + 5.6,
		{ Color = c3(fin.fin), Material = Enum.Material.SmoothPlastic }))
	local mid = (S.x0 + S.x1) / 2
	table.insert(out, box(folder, plot, "ShaftCapDoor", mid - 1.2, mid + 1.2, S.z1 + 0.6, S.z1 + 0.75, capY, capY + 4,
		with(NOHIT, { Color = c3(TF.INK), Material = Enum.Material.SmoothPlastic })))
	local s = T.unfinished(pieces, level)
	if s and s > 0 then
		local gold = with(NOHIT, { Color = c3(TF.GOLD), Material = Enum.Material.SmoothPlastic })
		local ink = with(NOHIT, { Color = c3(TF.INK), Material = Enum.Material.SmoothPlastic })
		local cz = (S.z0 + S.z1) / 2
		local cy = capY + 5.6
		table.insert(out, box(folder, plot, "Crane", mid - 0.8, mid + 0.8, cz - 0.8, cz + 0.8, cy, cy + 20, gold))
		table.insert(out, box(folder, plot, "Crane", mid - 8, mid + 26, cz - 0.6, cz + 0.6, cy + 19, cy + 20.4, gold))
		table.insert(out, box(folder, plot, "Crane", mid - 9.5, mid - 4.5, cz - 1.4, cz + 1.4, cy + 16.5, cy + 19, ink))
		table.insert(out, box(folder, plot, "Crane", mid + 21.9, mid + 22.1, cz - 0.1, cz + 0.1, cy + 9, cy + 19, ink))
		table.insert(out, box(folder, plot, "Crane", mid + 21.2, mid + 22.8, cz - 0.8, cz + 0.8, cy + 7.8, cy + 9, gold))
		local edges = T.railEdges(pieces, level)
		local ry = T.DECKS[s - 1] and T.floorY(s) or (T.floorY(s) - T.SLAB)
		local white = with(NOHIT, { Color = c3(TF.STRIP), Material = Enum.Material.SmoothPlastic })
		for _, e in ipairs(edges) do
			local alongX = (e.z0 == e.z1)
			local a0, a1 = alongX and e.x0 or e.z0, alongX and e.x1 or e.z1
			local at = alongX and e.z0 or e.x0
			local function bar(b0, b1, y0, y1, props)
				if alongX then return box(folder, plot, "SafetyRail", b0, b1, at - 0.15, at + 0.15, y0, y1, props) end
				return box(folder, plot, "SafetyRail", at - 0.15, at + 0.15, b0, b1, y0, y1, props)
			end
			table.insert(out, bar(a0, a1, ry + 2.2, ry + 2.5, gold))
			table.insert(out, bar(a0, a1, ry + 1.1, ry + 1.35, white))
			local n = math.max(1, math.floor((a1 - a0) / 6))
			for k = 0, n do
				local a = a0 + (a1 - a0) * k / n
				table.insert(out, bar(a - 0.15, a + 0.15, ry, ry + 2.5, gold))
			end
		end
	end
	return out
end

return TowerArt
