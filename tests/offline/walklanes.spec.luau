-- walklanes.spec.luau: where the pedestrians walk, against what stands beside them, outside Studio.
-- 20 Oct (Luke's screenshot, live): a walker inside the glass wall of his HQ. Measured in Studio
-- the same day: the HQ's level 3-8 wings put their glass 70.0 studs off the drive's axis, on the
-- pavement (68.1-77.1), and walkers on the inner half of the lane rubbed it with their arms.
-- They also walked through all 6 monuments (outer ring walk) and the ticker post (inner walk).
-- The live doctor re-measures this against the real world at every HQ level; this spec keeps
-- the plan honest between runs.
local W = require("../../src/ReplicatedStorage/WalkLanes")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

-- a walker's reach from its lane centre: keep-right offset, then the swinging arm's outer edge
local ARM = 1.45 + 0.45

local function lanesWhere(pred)
	local out = {}
	for _, l in W.build() do if pred(l) then table.insert(out, l) end end
	return out
end

-- distance of point p (XZ) from the line through the origin with unit direction d
local function offAxis(p, d) return math.abs(p.X * -d.Z + p.Z * d.X) end

test("drive pavements: walkers stay clear of the HQ's wing walls and the lamp posts", function()
	local arms = lanesWhere(function(l) return l.arm end)
	assert(#arms == 12, "expected 12 drive-pavement lanes, got " .. #arms)
	for _, l in arms do
		local d = Vector3.new(math.cos(l.armAngle), 0, math.sin(l.armAngle))
		local centre = offAxis(l.a, d)
		local inner = centre - l.keep - ARM
		assert(inner >= W.MEASURED.wingWall + 1, ("arm lane %s: an arm reaches %.2f, the wing wall stands at %.2f"):format(l.name, inner, W.MEASURED.wingWall))
		assert(inner >= W.MEASURED.lampPostOuter, ("arm lane %s: an arm reaches %.2f, a lamp post's edge is at %.2f"):format(l.name, inner, W.MEASURED.lampPostOuter))
		-- the outer feet stay on the kerb side of the road (legs are 0.95 wide around +-0.5)
		local feet = centre + l.keep + 0.975
		assert(feet <= W.MEASURED.kerbOuter, ("arm lane %s: feet at %.2f are in the road (%.2f)"):format(l.name, feet, W.MEASURED.kerbOuter))
	end
end)

-- a chord ring's closest approach to the centre is at the chord's middle
local function ringReach(l)
	local mid = (l.a + l.b) / 2
	local rMin = Vector3.new(mid.X, 0, mid.Z).Magnitude
	local rMax = Vector3.new(l.a.X, 0, l.a.Z).Magnitude
	return rMin - l.keep - ARM, rMax + l.keep + ARM
end

test("outer ring walk: walkers pass the monuments and stay on the walk", function()
	for _, l in lanesWhere(function(l) return l.ringName == "out" end) do
		local lo, hi = ringReach(l)
		assert(lo >= W.MEASURED.monumentOuter + 0.5, ("outer walk: an arm at r %.2f, the monuments reach r %.2f"):format(lo, W.MEASURED.monumentOuter))
		assert(hi <= W.MEASURED.outerWalkEdge, ("outer walk: an arm at r %.2f, off the walk (%.2f)"):format(hi, W.MEASURED.outerWalkEdge))
	end
end)

test("inner ring walk: walkers pass the ticker post and stay on the walk", function()
	for _, l in lanesWhere(function(l) return l.ringName == "in" end) do
		local lo, hi = ringReach(l)
		assert(lo >= W.MEASURED.tickerOuter + 0.5, ("inner walk: an arm at r %.2f, the ticker post reaches r %.2f"):format(lo, W.MEASURED.tickerOuter))
		assert(hi <= W.MEASURED.innerWalkEdge, ("inner walk: an arm at r %.2f, off the walk (%.2f)"):format(hi, W.MEASURED.innerWalkEdge))
	end
end)

test("every lane has a name, a length and a side, and the counts did not drift", function()
	local foot, bike = 0, 0
	for _, l in W.build() do
		assert(l.name and l.len > 0 and l.dir and l.side and l.keep, "lane missing fields: " .. tostring(l.name))
		if l.bike then bike += 1 else foot += 1 end
	end
	assert(foot == 2 * W.RING_CHORDS + 12 + 2, "foot lanes: " .. foot)
	assert(bike == W.RING_CHORDS + 2, "bike lanes: " .. bike)
end)

return T
