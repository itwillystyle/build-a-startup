--[[
	StaffAnimClient -- LocalScript in StarterPlayer -> StarterPlayerScripts.

	v2.8.1: staff motion, drawn on each player's own machine.

	Measured on a full server (6 plots x 30 staff) before this existed: the
	server wrote 3 joints per staff member every 0.06 s and every write was
	sent to every player -- 8,637 joint updates/s, 246.5 KB/s per player. The
	same rigs without server motion: 10.0 KB/s. Roblox's performance guide says
	the same thing: play NPC animations on the client, and drive
	Motor6D.Transform (local, never replicated) instead of C0/C1.

	What it draws (the same motion the server used to send):
	  - typing: shoulders bob out of phase at 3.1 Hz
	  - head glances: two slow, incommensurate frequencies (0.41 / 0.27 Hz),
	    so the room never visibly loops -- Bran's knight trick
	  - wandering (rigs with a "Wander" attribute that are not "Seated"):
	    walk a few studs, pause, walk back, every 9-20 s
	  - the launch cheer when "CheerAt" changes: arms up and a hop
	Wander and the hop move the body through the Root joint's Transform, so
	the anchored HumanoidRootPart never moves and nothing is written to a
	replicated property.

	Only rigs within RANGE of the camera are animated (the guide's "cull when
	out of range"); name tags only show inside 24 studs anyway.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local TAG = "SVStaff"
local RANGE = 170
local camera = workspace.CurrentCamera

local WALK_TIME = 1.7          -- seconds out, same pace as the old 34 x 0.05 s steps
local CHEER_TIME = 0.7

local rigs = {}                -- model -> state
local hidden = {}              -- model -> true while culled by distance (v3.5)
local KEEP = { TierRing = true, TierPillar = true }

local function motor(parent, name)
	return parent and parent:FindFirstChild(name)
end

local function add(model)
	if rigs[model] then return end
	if not model:IsDescendantOf(workspace) then return end   -- v3.5: a UI portrait copy is not a staff member
	task.spawn(function()
		local hrp = model:WaitForChild("HumanoidRootPart", 10)
		local torso = model:WaitForChild("UpperTorso", 10)
		local lower = model:WaitForChild("LowerTorso", 10)
		if not (hrp and torso and lower) or not model.Parent then return end
		local st = {
			hrp = hrp,
			lS = torso:WaitForChild("LeftShoulder", 5),
			rS = torso:WaitForChild("RightShoulder", 5),
			neck = torso:WaitForChild("Neck", 5),
			-- StaffRig parents each Motor6D to its Part0: Root lives on the HumanoidRootPart
			root = motor(hrp, "Root") or motor(lower, "Root"),
			-- v3.0.3 elbows and knees (older rigs without them still animate their shoulders)
			lE = motor(model:FindFirstChild("LeftUpperArm"), "LeftElbow"),
			rE = motor(model:FindFirstChild("RightUpperArm"), "RightElbow"),
			lH = motor(lower, "LeftHip"), rH = motor(lower, "RightHip"),
			lK = motor(model:FindFirstChild("LeftUpperLeg"), "LeftKnee"),
			rK = motor(model:FindFirstChild("RightUpperLeg"), "RightKnee"),
			seed = math.random() * 100,
			cheerAt = model:GetAttribute("CheerAt") or 0,
			-- wander state machine: idle -> out -> hold -> back -> idle
			phase = "idle",
			nextAt = os.clock() + math.random(9, 20),
			offset = Vector3.zero,
			yaw = 0,
			t0 = 0,
		}
		if not (st.lS and st.rS and st.neck) then return end
		model:GetAttributeChangedSignal("CheerAt"):Connect(function()
			st.cheerAt = model:GetAttribute("CheerAt") or 0
		end)
		-- a halo or accessory added while the body is culled stays hidden with it
		model.DescendantAdded:Connect(function(d)
			if hidden[model] and d:IsA("BasePart") and not KEEP[d.Name] then d.LocalTransparencyModifier = 1 end
		end)
		rigs[model] = st
	end)
end

for _, m in ipairs(CollectionService:GetTagged(TAG)) do add(m) end
CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(m) rigs[m] = nil end)

local function wander(model, st, now)
	local bounds = model:GetAttribute("Wander")
	if typeof(bounds) ~= "Vector3" or model:GetAttribute("Seated") == true or model:GetAttribute("Carried") then
		st.phase, st.offset = "idle", Vector3.zero
		return CFrame.identity
	end
	if st.phase == "idle" then
		if now >= st.nextAt then
			st.target = Vector3.new(math.random(-bounds.X * 10, bounds.X * 10) / 10, 0, math.random(-bounds.Z * 10, bounds.Z * 10) / 10)
			st.from = st.offset
			st.yaw = (st.target - st.from).Magnitude > 0.1 and math.atan2(-(st.target.X - st.from.X), -(st.target.Z - st.from.Z)) or st.yaw
			st.phase, st.t0 = "out", now
		end
	elseif st.phase == "out" then
		local a = math.min(1, (now - st.t0) / WALK_TIME)
		st.offset = st.from:Lerp(st.target, a)
		if a >= 1 then st.phase, st.t0, st.hold = "hold", now, math.random(4, 9) end
	elseif st.phase == "hold" then
		if now - st.t0 >= st.hold then
			st.from = st.offset
			st.yaw = math.atan2(st.from.X, st.from.Z)   -- face home
			st.phase, st.t0 = "back", now
		end
	elseif st.phase == "back" then
		local a = math.min(1, (now - st.t0) / WALK_TIME)
		st.offset = st.from:Lerp(Vector3.zero, a)
		if a >= 1 then
			st.phase, st.offset, st.yaw = "idle", Vector3.zero, 0
			st.nextAt = now + math.random(9, 20)
		end
	end
	if st.offset.Magnitude < 1e-3 and st.phase == "idle" then return CFrame.identity end
	return CFrame.new(st.offset) * CFrame.Angles(0, st.yaw, 0)
end

--[[ v3.5 DISTANCE CULL. Real avatars (StaffRig v3.5) cost ~3.3k triangles
each against ~400 for the block rig. Measured with 180 staff on a full
server, wide view: 724 draw calls / 1.51M triangles, over the ~1M phone
budget; with the far ones hidden, 449 / 901k. Beyond HIDE studs a person is a
speck anyway, so their body and hair are hidden locally (LocalTransparencyModifier,
never replicated). Tier rings and light pillars are NOT hidden: they are how
you find a rare candidate down the road. Hysteresis stops flicker at the edge. ]]
local HIDE, SHOW = 210, 190

local function setBody(model, v)
	for _, d in ipairs(model:GetDescendants()) do
		if (d:IsA("BasePart") and not KEEP[d.Name] and d.Name ~= "HumanoidRootPart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = v
		end
	end
end

--[[ v3.6 LABEL DECLUTTER. Rare staff wear a 70-stud name tag (StaffRig.setTalent)
and tags are a fixed size in pixels, so two rares standing 3 studs apart stack
into one unreadable smear from across the lot (seen 27 Sep: "Rosa · GENIUS"
over "Cole · GENIUS" in the garage waiting line). Four times a second the
visible tags claim screen space rarest first, then nearest; a tag that would
overlap one already placed fades out. Only TEXT transparency is touched, and
only here: the server owns Enabled (it hides a tag while a speech bubble
shows), so the two never fight. ]]
local faded = {}          -- tag -> { [label] = { textT, strokeT } }
local function fadeTag(tag, on)
	if on then
		if faded[tag] then return end
		local keep = {}
		for _, t in ipairs(tag:GetDescendants()) do
			if t:IsA("TextLabel") then
				keep[t] = { t.TextTransparency, t.TextStrokeTransparency }
				t.TextTransparency, t.TextStrokeTransparency = 1, 1
			end
		end
		faded[tag] = keep
	elseif faded[tag] then
		for t, v in pairs(faded[tag]) do
			if t.Parent then t.TextTransparency, t.TextStrokeTransparency = v[1], v[2] end
		end
		faded[tag] = nil
	end
end
local function tagWidth(tag)
	local w = 0
	for _, t in ipairs(tag:GetDescendants()) do
		if t:IsA("TextLabel") then w = math.max(w, t.TextBounds.X) end
	end
	return w + 10
end
-- candidates on the Talent Row wear a CandidateTag (TalentDrop) at 140 studs; seen
-- from down the road their STAR / SKILLED signs stacked the same way
local TIER_RANK = { walkin = 1, skilled = 2, star = 3, genius = 4 }
local function declutter(camPos)
	local list = {}
	for model in pairs(rigs) do
		local head = model.Parent and not hidden[model] and model:FindFirstChild("Head")
		for _, tagName in ipairs({ "Tag", "CandidateTag" }) do
			local tag = head and head:FindFirstChild(tagName)
			if tag and tag.Enabled then
				local d = (head.Position - camPos).Magnitude
				-- Roblox measures a billboard's MaxDistance from the camera FOCUS, not the
				-- camera (measured: a 140-stud tag drawn 187 studs from the camera); and a tag
				-- the engine is not drawing reports AbsoluteSize 0
				local df = (head.Position - camera.Focus.Position).Magnitude
				local p, onScreen = camera:WorldToViewportPoint(head.Position + tag.StudsOffset)
				if onScreen and df <= tag.MaxDistance and tag.AbsoluteSize.Y > 0 then
					local rank = tonumber(model:GetAttribute("Talent")) or TIER_RANK[model:GetAttribute("Tier")] or 1
					table.insert(list, { tag = tag, x = p.X, y = p.Y, w = tagWidth(tag), h = tag.AbsoluteSize.Y, pri = rank * 10000 - d })
				else
					fadeTag(tag, false)
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.pri > b.pri end)
	local placed = {}
	for _, e in ipairs(list) do
		local clash = false
		for _, q in ipairs(placed) do
			if math.abs(e.x - q.x) < (e.w + q.w) / 2 and math.abs(e.y - q.y) < (e.h + q.h) / 2 - 6 then
				clash = true
				break
			end
		end
		fadeTag(e.tag, clash)
		if not clash then table.insert(placed, e) end
	end
	for tag in pairs(faded) do if not tag.Parent then faded[tag] = nil end end
end

local cullAcc = 0
RunService.Heartbeat:Connect(function(dt)
	cullAcc += dt
	if cullAcc < 0.25 then return end
	cullAcc = 0
	local camPos = camera.CFrame.Position
	for model, st in pairs(rigs) do
		if model.Parent and st.hrp then
			local d = (st.hrp.Position - camPos).Magnitude
			if not hidden[model] and d > HIDE then
				hidden[model] = true
				setBody(model, 1)
			elseif hidden[model] and d < SHOW then
				hidden[model] = nil
				setBody(model, 0)
			end
		end
	end
	for model in pairs(hidden) do if not model.Parent then hidden[model] = nil end end
	declutter(camPos)
end)

-- after the Animator has posed the rig for this frame, so this motion wins
RunService.PreSimulation:Connect(function()
	local camPos = camera.CFrame.Position
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	for model, st in pairs(rigs) do
		if not model.Parent then
			rigs[model] = nil
		elseif (st.hrp.Position - camPos).Magnitude <= RANGE then
			local t = now + st.seed
			--[[ v3.0.3 POSES, with elbows and knees. Sign convention (measured on
			these rigs): +X on a shoulder or hip swings the limb FORWARD, -X on a
			knee folds the shin back, +X on an elbow folds the forearm up. ]]
			local sh, el, hip, knee = { 0.05, 0.05 }, { 0.15, 0.15 }, { 0, 0 }, { 0, 0 }
			local hop = 0
			local seated = model:GetAttribute("Seated") == true
			if model:GetAttribute("Carried") then
				-- riding home on the scooter behind whoever recruited them: hands on their shoulders
				local w = math.sin(t * 6) * 0.05
				sh, el = { 1.3 + w, 1.3 - w }, { 0.45, 0.45 }
				knee = { -0.12, -0.12 }
			elseif model:GetAttribute("Chaser") and model:GetAttribute("Lunging") then
				-- v4.3 the lunge: flat out, both arms reaching for you
				sh, el, hip, knee = { 1.7, 1.7 }, { 0.1, 0.1 }, { -0.6, 0.9 }, { -0.2, -1.4 }
				hop = 0.15
			elseif model:GetAttribute("Chaser") and model:GetAttribute("Windup") then
				-- the tell before a dash: a crouch, arms thrown back
				sh, el, hip, knee = { -0.9, -0.9 }, { 0.5, 0.5 }, { 0.7, 0.7 }, { -1.3, -1.3 }
				hop = -0.55
			elseif model:GetAttribute("Chaser") then
				local s1 = math.sin(t * 11)
				sh, el = { s1 * 0.9, -s1 * 0.9 }, { 1.3, 1.3 }
				hip = { -s1 * 0.8, s1 * 0.8 }
				knee = { -math.max(0, s1) * 1.1 - 0.2, -math.max(0, -s1) * 1.1 - 0.2 }
			elseif model:GetAttribute("Candidate") then
				sh = { math.sin(t * 0.9) * 0.05, math.sin(t * 0.9 + 1) * 0.05 }
			elseif seated then
				-- typing: upper arms forward and down, forearms level over the keyboard
				sh = { 0.55 + math.sin(t * 3.1) * 0.05, 0.55 + math.sin(t * 3.1 + 1.6) * 0.05 }
				el = { 1.05 + math.sin(t * 6.2) * 0.08, 1.05 + math.sin(t * 6.2 + 2) * 0.08 }
			elseif st.phase == "out" or st.phase == "back" then
				local s1 = math.sin(t * 7)
				sh, el = { -s1 * 0.4, s1 * 0.4 }, { 0.35, 0.35 }
				hip = { s1 * 0.5, -s1 * 0.5 }
				knee = { -math.max(0, -s1) * 0.7, -math.max(0, s1) * 0.7 }
			end
			local ce = serverNow - st.cheerAt
			if ce >= 0 and ce < CHEER_TIME then
				local k = math.sin(ce / CHEER_TIME * math.pi)
				sh, el = { 2.7 * k, 2.7 * k }, { 0.2, 0.2 }
				if not seated then hop = 1.2 * k end
			end
			local armL = CFrame.Angles(sh[1], 0, 0.12)
			local armR = CFrame.Angles(sh[2], 0, -0.12)
			if st.lE then st.lE.Transform = CFrame.Angles(el[1], 0, 0) end
			if st.rE then st.rE.Transform = CFrame.Angles(el[2], 0, 0) end
			if not seated then
				if st.lH then st.lH.Transform = CFrame.Angles(hip[1], 0, 0) end
				if st.rH then st.rH.Transform = CFrame.Angles(hip[2], 0, 0) end
				if st.lK then st.lK.Transform = CFrame.Angles(knee[1], 0, 0) end
				if st.rK then st.rK.Transform = CFrame.Angles(knee[2], 0, 0) end
			end
			st.lS.Transform = armL
			st.rS.Transform = armR
			st.neck.Transform = CFrame.Angles(math.sin(t * 0.41) * 0.10, math.sin(t * 0.27) * 0.30, 0)
			if st.root then
				st.root.Transform = CFrame.new(0, hop, 0) * wander(model, st, now)
			end
		end
	end
end)
