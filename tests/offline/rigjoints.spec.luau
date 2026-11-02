--[[ rigjoints.spec.luau -- a staff rig's joints are found even when they arrive after the rig (2 Nov 2026).

	Measured live 2 Nov: 5 of 144 staff rigs registered in StaffAnimClient before their hip or knee
	joints had replicated. The old one-shot lookup kept nil for those joints all session, and the
	idle track bent them (Ada: hips 27 / 40 deg, right knee -46, left knee flat). These stand-in
	rigs replay that order.
]]
local RigJoints = require("../../src/ReplicatedStorage/RigJoints")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

-- a stand-in instance: a name, a parent, children found by name
local function inst(name, parent)
	local o = { Name = name, Parent = nil, children = {} }
	function o:FindFirstChild(n)
		for _, ch in self.children do if ch.Name == n then return ch end end
		return nil
	end
	function o:add(child)
		child.Parent = self
		table.insert(self.children, child)
		return child
	end
	function o:remove(child)
		for i, ch in self.children do if ch == child then table.remove(self.children, i) break end end
		child.Parent = nil
	end
	if parent then parent:add(o) end
	return o
end

local PARTS = { "HumanoidRootPart", "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg" }
local JOINTS = {
	{ "HumanoidRootPart", "Root" }, { "LeftUpperArm", "LeftElbow" }, { "RightUpperArm", "RightElbow" },
	{ "LowerTorso", "LeftHip" }, { "LowerTorso", "RightHip" }, { "LeftUpperLeg", "LeftKnee" },
	{ "RightUpperLeg", "RightKnee" }, { "UpperTorso", "Waist" },
}

-- a rig with every part, and every joint except the ones named in `late`
local function rig(late)
	local m = inst("Staff_Ada")
	for _, p in PARTS do inst(p, m) end
	local held = {}
	for _, pair in JOINTS do
		local j = inst(pair[2])
		if late and late[pair[2]] then held[pair[2]] = { part = m:FindFirstChild(pair[1]), j = j }
		else m:FindFirstChild(pair[1]):add(j) end
	end
	return m, held
end

test("a rig whose legs arrive late: nil at registration, filled once they land (Ada, 2 Nov)", function()
	local m, held = rig({ LeftHip = true, RightHip = true, RightKnee = true })
	local st = {}
	local missing = RigJoints.resolve(m, st)
	assert(missing == 3, "three joints have not arrived: " .. missing)
	assert(st.lH == nil and st.rH == nil and st.rK == nil, "nothing to hold yet")
	assert(st.lK and st.lK.Name == "LeftKnee", "the left knee was there in time")
	for _, h in held do h.part:add(h.j) end
	assert(RigJoints.resolve(m, st) == 0, "every joint found once it lands")
	assert(st.lH == held.LeftHip.j and st.rH == held.RightHip.j and st.rK == held.RightKnee.j, "the joints that arrived")
end)

test("a joint replaced after registration: the dead one is dropped for the new one", function()
	local m = rig()
	local st = {}
	RigJoints.resolve(m, st)
	local old = st.lH
	local lower = m:FindFirstChild("LowerTorso")
	lower:remove(old)
	local new = lower:add(inst("LeftHip"))
	RigJoints.resolve(m, st)
	assert(st.lH == new, "still writing the joint that left the rig")
end)

test("a joint already held is kept, not looked up again", function()
	local m = rig()
	local st = {}
	RigJoints.resolve(m, st)
	local held = st.rK
	m:FindFirstChild("RightUpperLeg").FindFirstChild = function() error("looked up a joint it already had") end
	RigJoints.resolve(m, st)
	assert(st.rK == held, "the held knee was swapped")
end)

test("Root on the HumanoidRootPart, else on the LowerTorso; Waist on the LowerTorso, else the UpperTorso", function()
	local m = inst("Staff_Kai")
	for _, p in PARTS do inst(p, m) end
	local root = inst("Root", m:FindFirstChild("LowerTorso"))
	local waist = inst("Waist", m:FindFirstChild("UpperTorso"))
	local st = {}
	RigJoints.resolve(m, st)
	assert(st.root == root, "Root on the LowerTorso")
	assert(st.waist == waist, "Waist on the UpperTorso")
end)

test("an older rig with no elbows or knees: those stay nil, the rest are found", function()
	local m, _ = rig({ LeftElbow = true, RightElbow = true, LeftKnee = true, RightKnee = true })
	local st = {}
	assert(RigJoints.resolve(m, st) == 4, "two elbows and two knees missing")
	assert(st.lH and st.rH and st.root and st.waist, "hips, root and waist found")
end)

return T
