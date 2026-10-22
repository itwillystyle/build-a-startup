--[[ ForecourtPlan (22 Oct 2026, art pass 1): what stands in front of the garage, as data.

Luke's picked mock (silicon-startup/ui/art-pass/garage-outside.png) fills the ground in front of
the garage: a bench, a bike rack, planters, a mailbox, and on the garage's right a fenced lot with
a crane, "you are about to grow". Measured 22 Oct (Studio, review camera C2): the live view had
contrast 0.28 against 0.60 in the mock, a pale empty court in front of a small bare garage.

Everything here is in the PLOT's frame (CampusArch.grounds: x across, z out from the garage door
at z 15 towards the road). The game moves through this ground, so `check` keeps every prop off:
  the main path      x +-5, z 14..98 (CampusArch.grounds `path`)
  the client line    ClientsServer doorLine: out of the door, 4 + 4.5 per client, +-1.5 sideways
  the walk-in        clients arrive from L.center + out*34 + side*14 (plot -14, 49) to the door
  the promenade      CampusArch.LOOP: the front straight at z 44, 10 wide
  the garage         HQ_1_Shell is 42 x 36 (HQMeta/V1)
  the drop-off       TalentDrop ENTRANCE_Z 66, its ring
  the company car    Cars spawns at (-13, 92.5)
and inside the plot's lawn slab. GameDoctor's walker sweep re-checks it against the real world.

Pure (no services): tests/offline/forecourtplan.spec.luau. ]]
local FP = {}

FP.COURT = { 190, 182, 170 }   -- the entrance court, a value step down from PATH (214, 208, 196)
FP.MARGIN = 2                  -- studs between a prop and anything the game moves through
-- 22 Oct (the look review): the frame's darkest green. With the yard in, the outside camera measured
-- contrast 0.32; dark hedges and bushes, tried live, took it to 0.495. The mock's contrast is its greens.
FP.HEDGE = { 38, 88, 50 }

-- name, kind, centre x/z (plot frame), footprint w x d, height h, yaw (degrees, about Y)
FP.PROPS = {
	{ name = "Bench", kind = "bench", x = -14, z = 27, w = 1.8, d = 5, h = 2.4, yaw = 0 },
	{ name = "BikeRack", kind = "bikerack", x = -15, z = 21.5, w = 4, d = 1.2, h = 2.2, yaw = 0 },
	{ name = "PlanterL", kind = "planter", x = -9, z = 22, w = 3, d = 3, h = 1.6, solid = true },
	{ name = "PlanterR1", kind = "planter", x = 9, z = 22, w = 3, d = 3, h = 1.6, solid = true },
	{ name = "PlanterR2", kind = "planter", x = 9, z = 34, w = 3, d = 3, h = 1.6, solid = true },
	{ name = "Mailbox", kind = "mailbox", x = 12.5, z = 27, w = 1.2, d = 1.2, h = 3.6 },
	{ name = "LotFence", kind = "lotFence", x = 34, z = 0, w = 18, d = 24, h = 3 },
	{ name = "Crane", kind = "crane", x = 38, z = -4, w = 4, d = 4, h = 18 },
	{ name = "ComingSoon", kind = "comingSoon", x = 34, z = 12.5, w = 6, d = 0.4, h = 4 },
	-- the dark greens: hedges down both sides of the court and either side of the path past the
	-- promenade, bushes on the lawn round the garage
	{ name = "HedgeCourtL", kind = "hedge", x = -19.5, z = 29, w = 2.4, d = 16, h = 3.0 },
	{ name = "HedgeCourtR", kind = "hedge", x = 19.5, z = 29, w = 2.4, d = 16, h = 3.0 },
	{ name = "HedgePathL", kind = "hedge", x = -9, z = 53, w = 2.4, d = 4, h = 3.0 },
	{ name = "HedgePathR", kind = "hedge", x = 9, z = 53, w = 2.4, d = 4, h = 3.0 },
	{ name = "BushL1", kind = "bush", x = -26, z = 20, w = 4.8, d = 4.8, h = 3.4 },
	{ name = "BushR1", kind = "bush", x = 26, z = 20, w = 4.8, d = 4.8, h = 3.4 },
	{ name = "BushL2", kind = "bush", x = -29, z = 13, w = 4.0, d = 4.0, h = 2.8 },
	{ name = "BushL3", kind = "bush", x = -31, z = 29, w = 5.2, d = 5.2, h = 3.6 },
	{ name = "BushR3", kind = "bush", x = 31, z = 29, w = 5.2, d = 5.2, h = 3.6 },
	{ name = "BushL4", kind = "bush", x = -26, z = 34, w = 4.4, d = 4.4, h = 3.0 },
	{ name = "BushR4", kind = "bush", x = 27, z = 34, w = 4.4, d = 4.4, h = 3.0 },
	-- 22 Oct (Luke's look review at night: "a little too dark" where the first client stands): a porch
	-- lamp either side of the door; the head is tagged SVLamp, so SkyClient lights it after dark
	{ name = "PorchLampL", kind = "lamp", x = -11.5, z = 20.8, w = 1, d = 1, h = 7 },
	{ name = "PorchLampR", kind = "lamp", x = 13, z = 21, w = 1, d = 1, h = 7 },
}

-- axis-aligned keep-out boxes { name, x0, x1, z0, z1 }
FP.KEEP = {
	{ "the main path", -5, 5, 14, 98 },
	{ "the client line", -4.5, 4.5, 15, 46 },
	{ "the promenade", -77, 77, 39, 49 },
	{ "the garage", -21, 21, -18, 18 },
	{ "the drop-off", -8, 8, 58, 74 },
	{ "the company car", -19, -7, 86.5, 98.5 },
}
FP.WALKIN = { a = { -14, 49 }, b = { 0, 19 } }   -- the clients' diagonal from the street to the door
FP.SLAB = { -120, 120, -128, 86 }                 -- CampusArch.grounds: 240 x 214 at z -21

-- the growth lot belongs to the garage levels (the garage itself owns -21..21)
local LOT = { lotFence = true, crane = true, comingSoon = true }

local function segDist(px, pz, a, b)
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local t = math.clamp(((px - a[1]) * dx + (pz - a[2]) * dz) / (dx * dx + dz * dz), 0, 1)
	local cx, cz = a[1] + dx * t, a[2] + dz * t
	return math.sqrt((px - cx) ^ 2 + (pz - cz) ^ 2)
end

-- -> { "problem", ... } (empty when every prop is clear)
function FP.check(props)
	local out = {}
	for _, p in props or FP.PROPS do
		local x0, x1, z0, z1 = p.x - p.w / 2, p.x + p.w / 2, p.z - p.d / 2, p.z + p.d / 2
		for _, k in FP.KEEP do
			local m = FP.MARGIN
			if x1 > k[2] - m and x0 < k[3] + m and z1 > k[4] - m and z0 < k[5] + m then
				table.insert(out, ("%s (%s) is on %s"):format(p.name, p.kind, k[1]))
			end
		end
		if not LOT[p.kind] then
			local reach = segDist(p.x, p.z, FP.WALKIN.a, FP.WALKIN.b) - math.max(p.w, p.d) / 2
			if reach < 3 then
				table.insert(out, ("%s (%s) is %.1f studs from the clients' walk-in"):format(p.name, p.kind, reach))
			end
		end
		local s = FP.SLAB
		if x0 < s[1] or x1 > s[2] or z0 < s[3] or z1 > s[4] then
			table.insert(out, ("%s (%s) is off the plot's slab"):format(p.name, p.kind))
		end
	end
	return out
end

return FP
