--[[ HunterSmoothClient -- draws the headhunters smoothly between server updates.

	WHY. TalentDrop moves every hunter with PivotTo on an ANCHORED rig, every
	server frame. Roblox interpolates the physics of unanchored parts for
	clients, but a property write on an anchored part arrives as it is, at the
	network rate. Measured live on 7 Oct: on the client the hunter's distance
	stepped about 1.2 studs every third frame (~20 Hz) while the player moved
	smoothly -- the hunter visibly hops across the road, and the chase camera,
	which frames it, hopped with it.

	HOW. Each server sample is held with the time it arrived. The rig is drawn
	between the last two samples, reaching the newest one just as the next is
	due: one network interval behind (~50 ms, about a stud at chase speed),
	and smooth. Only what this client DRAWS changes; the server still owns
	where the hunter is and when it catches you.

	A write from here is local, so the rig reads back what we wrote until the
	server sends something new -- that difference is how a new sample is seen.
]]
local RunService = game:GetService("RunService")

local SNAP = 8             -- studs between samples that means a teleport, not a run
local MAX_GAP = 0.25       -- seconds; a longer silence is not an interval to spread over

local state = setmetatable({}, { __mode = "k" })
local rigs = {}
local nextScan = 0

local function rescan()
	table.clear(rigs)
	local sv = workspace:FindFirstChild("SiliconValley")
	local row = sv and sv:FindFirstChild("TalentRow")
	if not row then return end
	for _, m in ipairs(row:GetDescendants()) do
		if m:IsA("Model") and m:GetAttribute("Chaser") and m.PrimaryPart then
			table.insert(rigs, m)
		end
	end
end

local function same(a, b)
	return (a.Position - b.Position).Magnitude < 1e-3 and a.LookVector:Dot(b.LookVector) > 0.99999
end

--[[ First in the frame, so every reader this frame -- the chase camera, the
	fear readout, the audio -- sees the drawn position, never the raw sample.
	The rescan is quick because a hunter spawns AT the start of a chase: at
	0.5 s the first half-second of every chase still hopped (measured). ]]
RunService:BindToRenderStep("HunterSmooth", Enum.RenderPriority.First.Value, function()
	local now = os.clock()
	if now > nextScan then
		nextScan = now + 0.1
		rescan()
	end
	for _, rig in ipairs(rigs) do
		if rig.Parent and rig.PrimaryPart then
			local cur = rig:GetPivot()
			local s = state[rig]
			if not s then
				s = { s1 = cur, t1 = now }
				state[rig] = s
			elseif not (s.written and same(cur, s.written)) then
				-- the server moved it since we last drew it: a new sample
				local jump = (cur.Position - s.s1.Position).Magnitude
				if jump > SNAP or now - s.t1 > MAX_GAP then
					s.s0, s.t0 = nil, nil
				else
					s.s0, s.t0 = s.s1, s.t1
				end
				s.s1, s.t1 = cur, now
			end
			local draw = s.s1
			if s.s0 then
				local span = math.max(s.t1 - s.t0, 1 / 120)
				draw = s.s0:Lerp(s.s1, math.clamp((now - s.t1) / span, 0, 1))
			end
			if not same(draw, cur) then rig:PivotTo(draw) end
			s.written = draw
		end
	end
end)
