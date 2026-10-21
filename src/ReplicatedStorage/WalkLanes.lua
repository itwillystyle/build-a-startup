--[[ WalkLanes (20 Oct): where LifeClient's pedestrians and cyclists go, in one pure module.

The lanes used to live inside LifeClient, so nothing else could check them. Luke's live
screenshot (20 Oct) showed a walker inside the glass wall of his HQ, and measured in Studio
the same day:
  * the drive pavements run 68.1-77.1 studs off each drive's axis, and the HQ's level 3-8
    wings put their glass at 70.0, ON the pavement; walkers on the inner side of the old lane
    (72.6, keeping right 1.3) swung their arms through it. The lamp posts stand on the
    pavement's middle (72.6, 0.6 thick), so the clear strip is lamp post to kerb: walkers
    now walk it, one step either side of 76.0.
  * the outer ring walk's lane went through all 6 monuments (plinths r 225.2-228.6) and the inner
    walk's through the ticker post (r 183.4-184.6): 12 chords bowed 7 studs off the circle.
    24 chords (bow under 2), lanes at r 234.5 and 190, clear of both and on the walk
    (the monuments' plinths reach r 228.6: the doctor's first sweep found them).
  * the bike loop crossed the 8 park ramps under their surface; LifeClient now lifts
    cyclists onto a ramp they cross (heights measured once the park is built).

Pure (no services): tests/offline/walklanes.spec.luau checks every lane against MEASURED,
and GameDoctor sweeps the same lanes through the real world at every HQ level. ]]
local W = {}

W.Y = 1.5                     -- walking height (the pavements' tops are 1.2)
W.R_RING, W.R_OUT = 208, 596  -- CampusHub.R_ROAD_IN / R_ROAD_OUT
W.RING_CHORDS = 24
W.RING_IN, W.RING_OUT, W.BIKE_LOOP = 190, 234.5, 174
W.ARM_WALK = 76.0             -- the drive pavement's lane, off the drive's axis
W.ARM_KEEP = 1.0              -- one step right of it each way (the strip is 4.7 wide)
W.RING_KEEP = 1.3

-- what stands beside the lanes, measured in Studio on 20 Oct (Plot1 at level 10)
W.MEASURED = {
	wingWall = 70.0,          -- the level 3-8 wings' glass, off the drive axis
	lampPostOuter = 72.9,     -- ParkLampPost (0.6 thick) at 72.6
	kerbOuter = 80.0,         -- the far side of the kerb: the road starts here
	monumentOuter = 228.6,    -- the 6 Grounds.MonumentBase plinths (8.8 x 3.4, top 2.8), r 226.9 +- 1.7
	outerWalkEdge = 238,      -- RingWalkOut, r 230 +- 8
	tickerOuter = 184.6,      -- TickerPost, r 184 +- 0.6
	innerWalkEdge = 194,      -- RingWalkIn, r 186 +- 8
}

local function finish(l)
	l.len = (l.b - l.a).Magnitude
	l.dir = (l.b - l.a).Unit
	l.side = Vector3.new(-l.dir.Z, 0, l.dir.X)   -- keep-right offset axis
	return l
end

function W.build()
	local lanes = {}
	local function chordRing(radius, ringName, foot)
		for i = 0, W.RING_CHORDS - 1 do
			local a0, a1 = i * 2 * math.pi / W.RING_CHORDS, (i + 1) * 2 * math.pi / W.RING_CHORDS
			table.insert(lanes, finish({
				name = ("%s%d"):format(ringName, i),
				a = Vector3.new(math.cos(a0) * radius, W.Y, math.sin(a0) * radius),
				b = Vector3.new(math.cos(a1) * radius, W.Y, math.sin(a1) * radius),
				foot = foot, bike = not foot, ring = true, ringName = ringName, keep = W.RING_KEEP,
			}))
		end
	end
	chordRing(W.RING_IN, "in", true)
	chordRing(W.RING_OUT, "out", true)
	chordRing(W.BIKE_LOOP, "bike", false)

	-- out to each plot along its drive, on the median-side pavement (CampusHub pass 4)
	for i = 0, 5 do
		local deg = 30 + i * 60
		local a = math.rad(deg)
		local ca, sa = math.cos(a), math.sin(a)
		local tx, tz = -sa, ca
		for _, side in ipairs({ -1, 1 }) do
			table.insert(lanes, finish({
				name = ("arm%d%s"):format(deg, side < 0 and "L" or "R"),
				a = Vector3.new(ca * (W.R_RING + 30) + tx * side * W.ARM_WALK, W.Y, sa * (W.R_RING + 30) + tz * side * W.ARM_WALK),
				b = Vector3.new(ca * (W.R_OUT - 30) + tx * side * W.ARM_WALK, W.Y, sa * (W.R_OUT - 30) + tz * side * W.ARM_WALK),
				foot = true, arm = true, armAngle = a, keep = W.ARM_KEEP,
			}))
		end
	end

	-- the east approach to downtown, the one straight road left
	for _, s in ipairs({ -1, 1 }) do
		table.insert(lanes, finish({ name = "east" .. s, a = Vector3.new(W.R_OUT + 20, W.Y, s * 19.5), b = Vector3.new(900, W.Y, s * 19.5),
			foot = true, keep = W.RING_KEEP }))
		table.insert(lanes, finish({ name = "eastBike" .. s, a = Vector3.new(W.R_OUT + 20, W.Y, s * 15), b = Vector3.new(900, W.Y, s * 15),
			bike = true, keep = W.RING_KEEP }))
	end
	return lanes
end

return W
