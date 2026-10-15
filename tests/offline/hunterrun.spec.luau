--[[ hunterrun.spec.luau -- the headhunter's run track survives a rig that arrives in pieces.

	Measured 14 Oct 2026: a hunter's Humanoid can reach the client 8 ms after its
	torso. The old loader cached "cannot run" on that first frame and the hunter
	never played its run for the whole chase. These stand-in rigs replay that order.
]]
local HunterRun = require("../../src/ReplicatedStorage/HunterRun")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local RUN = "rbxassetid://129982348627259"

-- a stand-in instance: children by class, and an Animator that loads tracks (or refuses)
local function inst(className, refuse)
	local o = { ClassName = className, children = {}, loads = 0 }
	function o:FindFirstChildOfClass(c)
		for _, ch in self.children do if ch.ClassName == c then return ch end end
		return nil
	end
	if className == "Animator" then
		function o:LoadAnimation(anim)
			if refuse then error("LoadAnimation refused") end
			self.loads += 1
			return { Animation = anim, Priority = nil, Looped = false }
		end
	end
	return o
end
local made = {}
local function new(className, parent)
	local o = inst(className)
	table.insert(made, className)
	if parent then table.insert(parent.children, o) end
	return o
end
local function rig(withHumanoid, withAnimator, refuse)
	local m = inst("Model")
	if withHumanoid then
		local hum = inst("Humanoid")
		table.insert(m.children, hum)
		if withAnimator then table.insert(hum.children, inst("Animator", refuse)) end
	end
	return m
end

test("a rig whose Humanoid has not arrived yet is asked again, not given up on", function()
	local m, st = rig(false), {}
	assert(HunterRun.trackFor(m, st, RUN, new) == nil, "no Humanoid: no track yet")
	assert(st.runTrack == nil, "must not cache 'cannot run' while the rig is still arriving (got " .. tostring(st.runTrack) .. ")")
	-- 8 ms later the Humanoid and its Animator replicate
	local hum = inst("Humanoid")
	table.insert(hum.children, inst("Animator"))
	table.insert(m.children, hum)
	local tr = HunterRun.trackFor(m, st, RUN, new)
	assert(tr ~= nil, "once the Humanoid is there the run loads")
	assert(tr.Animation.AnimationId == RUN, "it is the run")
	assert(tr.Looped == true and tr.Priority == Enum.AnimationPriority.Movement, "looped, under the Action windup and lunge")
	assert(st.runTrack == tr, "cached once loaded")
end)

test("the track is loaded once, then reused every frame", function()
	local m, st = rig(true, true), {}
	local a = HunterRun.trackFor(m, st, RUN, new)
	local b = HunterRun.trackFor(m, st, RUN, new)
	assert(a == b, "same track")
	assert(m.children[1].children[1].loads == 1, "LoadAnimation ran once")
end)

test("an avatar's own Animator is used; a second one is never made", function()
	table.clear(made)
	local m, st = rig(true, true), {}
	HunterRun.trackFor(m, st, RUN, new)
	assert(table.find(made, "Animator") == nil, "made an Animator although the rig had one")
	assert(#m.children[1].children == 1, "one Animator under the Humanoid")
end)

test("a block rig (a Humanoid with no Animator) gets one made locally", function()
	local m, st = rig(true, false), {}
	local tr = HunterRun.trackFor(m, st, RUN, new)
	assert(tr ~= nil, "block rigs run too")
	assert(m.children[1]:FindFirstChildOfClass("Animator") ~= nil, "an Animator now sits under the Humanoid")
end)

test("a real refusal (LoadAnimation errors) is cached, so it is not retried every frame", function()
	local m, st = rig(true, true, true), {}
	assert(HunterRun.trackFor(m, st, RUN, new) == nil, "no track")
	assert(st.runTrack == false, "cached as cannot run")
end)

test("no run id means the Lua pose for good", function()
	local m, st = rig(true, true), {}
	assert(HunterRun.trackFor(m, st, "", new) == nil, "no track")
	assert(st.runTrack == false, "cached")
end)

return T
