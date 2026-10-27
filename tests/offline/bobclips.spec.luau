-- bobclips.spec.luau: Bob's keyframed body clips (BobClips), 25 Oct 2026.
-- Shot list: research/p5-bob/SHOT-LIST.md. The scene picks clips by name (BobSceneClient.clipFor).
local B = require("../../src/ReplicatedStorage/BobClips")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local NEEDED = {
	"hero_idle", "hero_ask", "hero_hurt", "hero_fly", "hero_land", "hero_situp", "hero_sadwalk", "hero_vow",
	"hero_strut", "hero_ipad", "hero_kick", "hero_cheer", "hero_getup",
	"bob_smug", "bob_laugh", "bob_kick", "bob_shock", "bob_throw", "bob_fly", "bob_dizzy",
	"inv_idle", "inv_laugh", "inv_shock", "bob_laughdie", "inv_laughdie",
}
local SIX = { Root = true, Neck = true, LeftShoulder = true, RightShoulder = true, LeftHip = true, RightHip = true }

test("every clip the scene asks for exists", function()
	for _, n in ipairs(NEEDED) do assert(B.has(n), "missing clip " .. n) end
end)

test("a looping clip ends where it starts (no pop at the loop)", function()
	for name, clip in pairs(B.CLIPS) do
		if clip.loop then
			local a, b = B.sample(name, 0), B.sample(name, clip.length - 1e-6)
			for joint, cf in pairs(a) do
				local other = b[joint]
				assert(other, name .. ": " .. joint .. " missing at the end")
				local diff = (cf.LookVector - other.LookVector).Magnitude + (cf.UpVector - other.UpVector).Magnitude
				assert(diff < 0.02, ("%s: %s jumps at the loop (%.3f)"):format(name, joint, diff))
			end
		end
	end
end)

test("Bob's and the investors' clips only use their six joints", function()
	for name, clip in pairs(B.CLIPS) do
		if name:sub(1, 4) == "bob_" or name:sub(1, 4) == "inv_" then
			for _, k in ipairs(clip.keys) do
				for joint, v in pairs(k) do
					if type(v) == "table" then assert(SIX[joint], name .. " uses " .. joint .. ", which the AI rig does not have") end
				end
			end
		end
	end
end)

test("keys are in time order inside the clip's length", function()
	for name, clip in pairs(B.CLIPS) do
		local last = -1
		for _, k in ipairs(clip.keys) do
			assert(k.t >= last, name .. " keys out of order at " .. k.t)
			assert(k.t <= clip.length + 1e-9, name .. " has a key past its end")
			last = k.t
		end
	end
end)

test("the kick snaps: the hip goes from behind to high in under 0.15 s", function()
	-- the leg's own angle: the hip on top of the Root lean (the hips take a Root lean back out)
	local function leg(t) local s = B.sample("bob_kick", t) return select(1, (s.Root * s.RightHip):ToEulerAnglesXYZ()) end
	local back, up = leg(0.2), leg(0.3)
	assert(math.deg(back) < -30 and math.deg(up) > 90, ("%.0f -> %.0f"):format(math.deg(back), math.deg(up)))
end)

test("sampling past the end of a one-shot holds its last pose", function()
	local a = B.sample("hero_vow", 4.2).RightShoulder
	local b = B.sample("hero_vow", 9).RightShoulder
	assert(a == b, "held")
end)

test("a Root lean keeps the legs planted (Luke: Bob looked like he was falling)", function()
	for _, name in ipairs({ "bob_laugh", "inv_laugh", "bob_shock" }) do
		for _, t in ipairs({ 0, 0.15, 0.3 }) do
			local s = B.sample(name, t)
			for _, hip in ipairs({ "LeftHip", "RightHip" }) do
				local leg = (s.Root * s[hip]).UpVector
				assert(leg.Y > 0.99, ("%s at %.2f: %s tilts (%.3f)"):format(name, t, hip, leg.Y))
			end
		end
	end
end)

-- Luke 25 Oct: after the kick "he resets extremely quick": sitting, then standing the next frame
-- (measured: root 2.2 -> 3.4 studs in one frame at 8.74 s). The get-up is a clip that starts in the
-- sit-up's last pose and ends in the idle's first, so neither seam can jump
local function same(a, b, tag)
	for joint, cf in pairs(a) do
		local o = b[joint] or CFrame.new()
		local d = (cf.LookVector - o.LookVector).Magnitude + (cf.UpVector - o.UpVector).Magnitude
		assert(d < 0.02, ("%s: %s jumps (%.3f)"):format(tag, joint, d))
	end
	for joint, cf in pairs(b) do
		if not a[joint] then
			local d = (cf.LookVector - Vector3.new(0, 0, -1)).Magnitude + (cf.UpVector - Vector3.new(0, 1, 0)).Magnitude
			assert(d < 0.02, ("%s: %s jumps from rest (%.3f)"):format(tag, joint, d))
		end
	end
end
test("the get-up starts where the sit-up ends and ends in the idle's first pose", function()
	same(B.sample("hero_situp", B.length("hero_situp")), B.sample("hero_getup", 0), "sit-up > get-up")
	same(B.sample("hero_getup", B.length("hero_getup")), B.sample("hero_idle", 0), "get-up > idle")
	assert(B.length("hero_getup") >= 0.4, "a get-up under 0.4 s reads as a snap")
end)

return T
