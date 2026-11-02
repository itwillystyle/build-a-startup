--[[ RigJoints -- a staff rig's joints, looked up again until every one is there (2 Nov 2026). Pure.

	StaffAnimClient writes each staff rig's joints every frame. It used to look each joint up ONCE,
	when the rig registered, and keep what it found for the whole session. A rig reaches the client
	in pieces (the 14 Oct HunterRun lesson, again): measured 2 Nov, 5 of 144 rig arrivals registered
	before their hip or knee joints had replicated. Those fields stayed nil, nothing wrote those
	joints, and the server's R15 idle track bent them: Ada at hq:100 sat with her hips at 27 / 40 deg
	and her right knee at -46, perched over the cushion, while her left knee (there in time) was flat.

	resolve fills every field that is missing, or that holds a joint no longer on this rig, and is
	cheap to call again: StaffAnimClient calls it at registration and whenever a Motor6D lands on
	the rig. The shoulders and neck are not here: registration still waits for them. ]]
local RigJoints = {}

-- field -> { the parts that may hold it (first hit wins), the joint's name }
RigJoints.FIELDS = {
	-- StaffRig parents each Motor6D to its Part0: Root lives on the HumanoidRootPart
	root = { { "HumanoidRootPart", "LowerTorso" }, "Root" },
	-- v3.0.3 elbows and knees (older rigs without them still animate their shoulders)
	lE = { { "LeftUpperArm" }, "LeftElbow" },
	rE = { { "RightUpperArm" }, "RightElbow" },
	lH = { { "LowerTorso" }, "LeftHip" },
	rH = { { "LowerTorso" }, "RightHip" },
	lK = { { "LeftUpperLeg" }, "LeftKnee" },
	rK = { { "RightUpperLeg" }, "RightKnee" },
	waist = { { "LowerTorso", "UpperTorso" }, "Waist" },   -- 24 Oct: the slump's lean
}

-- a joint we hold is still good while it sits on a part of this rig
local function onRig(model, j)
	local part = j.Parent
	return part ~= nil and part.Parent == model
end

-- fills st's joint fields from model; returns how many are still missing
function RigJoints.resolve(model, st)
	local missing = 0
	for field, spec in pairs(RigJoints.FIELDS) do
		local j = st[field]
		if not (j and onRig(model, j)) then
			j = nil
			for _, partName in ipairs(spec[1]) do
				local part = model:FindFirstChild(partName)
				j = part and part:FindFirstChild(spec[2])
				if j then break end
			end
			st[field] = j
		end
		if not st[field] then missing += 1 end
	end
	return missing
end

return RigJoints
