--[[ ChaseFxClient (v4.3): the fear, and the one button that answers it.

His verdict: "the chase should be a lot more fearful for the player." The new
hunter (ChaseRules) hangs right behind you and lunges; this makes you FEEL it:
  * a heartbeat that gets louder and faster as it closes (ChaseDist)
  * red edges that close in with it
  * a camera punch when it lunges at you
  * the BOOST button (Shift, or the button above CAR on a phone), which pulses
    "NOW!" while a hunter crouches: boost in the crouch and the lunge misses
  * CLOSE CALL! when it got within 8 studs and you still got away

v4.4 (8 Oct, his three 01:35-01:37 recordings, night, both chases lost). The new
hunter commits to a line when it crouches, and that only works if you can SEE
the crouch. In the recordings you could not: a black suit on a black avatar on a
dark road, the two silhouettes overlapping, red edges that glowed the WHOLE chase
so the tell changed nothing on screen, and the camera barely turned. So:
  * THE LANE: the line it picked is painted on the road the moment it crouches
    (LungeFrom / LungeTo, set by TalentDrop) -- get off the red, or BOOST
  * the hunter wears a red outline for the whole chase, day or night
  * the red edges are quiet until it crouches, then they flash, with a sting
The server owns the chase (TalentDrop + ChaseRules); this only reads the
attributes it writes and sends one remote (CarryBoost). ]]
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local UIKit = require(RS:WaitForChild("UIKit"))
local remotes = RS:WaitForChild("SVRemotes")
local boostRemote = remotes:WaitForChild("CarryBoost", 30)
local chaseFx = remotes:WaitForChild("ChaseFx", 30)

local HEART = "rbxassetid://1839090417"      -- APM "Heart Beat OL" (licensed)
local WHOOSH = "rbxassetid://9126229255"     -- PSE "Whoosh By Fast"
local BOOST_SND = "rbxassetid://9126228631"  -- PSE "Whoosh Back Zoom"
local COOLDOWN = 5                           -- mirrors ChaseRules.BOOST.cooldown (server enforces it)
local LANE_WIDTH = 9                         -- studs: two catch radii, the space you have to clear
local LANE = Color3.fromRGB(235, 40, 50)

local gui = Instance.new("ScreenGui")
gui.Name = "ChaseFx"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 9
gui.Parent = player:WaitForChild("PlayerGui")

-- ============ RED EDGES ============
local edges = {}
for i, spec in ipairs({
	{ UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0.22, 0), 90 },
	{ UDim2.new(0, 0, 0.78, 0), UDim2.new(1, 0, 0.22, 0), -90 },
	{ UDim2.new(0, 0, 0, 0), UDim2.new(0.16, 0, 1, 0), 0 },
	{ UDim2.new(0.84, 0, 0, 0), UDim2.new(0.16, 0, 1, 0), 180 },
}) do
	local f = Instance.new("Frame")
	f.Name = "Edge" .. i
	f.Position, f.Size = spec[1], spec[2]
	f.BackgroundColor3 = Color3.fromRGB(200, 20, 30)
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 1
	f.Parent = gui
	local g = Instance.new("UIGradient", f)
	g.Rotation = spec[3]
	g.Transparency = NumberSequence.new(0, 1)
	edges[i] = f
end

-- ============ THE HEARTBEAT ============
local heart = Instance.new("Sound")
heart.SoundId = HEART
heart.Looped = true
heart.Volume = 0
heart.Parent = SoundService

local function play(id, vol, pitch)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol or 0.6
	s.PlaybackSpeed = pitch or 1
	s.Parent = SoundService
	s:Play()
	task.delay(4, function() s:Destroy() end)
end

-- ============ BOOST ============
local btn = UIKit.button(gui, "", UIKit.ORANGE, {
	Name = "Boost", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -190, 1, -118), Size = UDim2.new(0, 120, 0, 84),
	Visible = false,
}, { textSize = 24 })
local btnText = UIKit.outlined(btn, "BOOST", 26, UIKit.TEXT, {
	Position = UDim2.new(0, 0, 0, 10), Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = btn.ZIndex + 2,
})
UIKit.label(btn, UserInputService.KeyboardEnabled and "SHIFT" or "TAP", 14, UIKit.INK, {
	Position = UDim2.new(0, 0, 0, 46), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = btn.ZIndex + 2,
}, UIKit.HEAD)
local cdFill = Instance.new("Frame")
cdFill.Name = "Cooldown"
cdFill.BackgroundColor3 = UIKit.INK
cdFill.BackgroundTransparency = 0.45
cdFill.BorderSizePixel = 0
cdFill.AnchorPoint = Vector2.new(0, 1)
cdFill.Position = UDim2.new(0, 0, 1, 0)
cdFill.Size = UDim2.new(1, 0, 0, 0)
cdFill.ZIndex = btn.ZIndex + 3
cdFill.Parent = btn
Instance.new("UICorner", cdFill).CornerRadius = UDim.new(0, 12)
local btnScale = Instance.new("UIScale", btn)

local lastBoostSent = -math.huge
local function boost()
	if not player:GetAttribute("Carrying") then return end
	if os.clock() - lastBoostSent < COOLDOWN then return end
	lastBoostSent = os.clock()
	if boostRemote then boostRemote:FireServer() end
	play(BOOST_SND, 0.5, 1.1)
	local cam = workspace.CurrentCamera
	TweenService:Create(cam, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { FieldOfView = 84 }):Play()
	task.delay(0.9, function() TweenService:Create(cam, TweenInfo.new(0.4), { FieldOfView = 70 }):Play() end)
end
btn.Activated:Connect(boost)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift or input.KeyCode == Enum.KeyCode.ButtonB then
		boost()
	end
end)

-- ============ CLOSE CALL ============
local function closeCall()
	play(WHOOSH, 0.7, 1)
	local lbl = UIKit.outlined(gui, "CLOSE CALL!", 46, UIKit.GOLD, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.36, 0), Size = UDim2.new(0, 520, 0, 60),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local sc = Instance.new("UIScale", lbl)
	sc.Scale = 0.3
	TweenService:Create(sc, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(1.1, function()
		TweenService:Create(lbl, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		local st = lbl:FindFirstChildOfClass("UIStroke")
		if st then TweenService:Create(st, TweenInfo.new(0.4), { Transparency = 1 }):Play() end
		task.delay(0.45, function() lbl:Destroy() end)
	end)
end
if chaseFx then
	chaseFx.OnClientEvent:Connect(function(e)
		if type(e) == "table" and e.kind == "close" then closeCall() end
	end)
end

-- ============ THE LANE, AND THE OUTLINE ============
local lanes, outlines = {}, {}
local function laneFor(m)
	local p = lanes[m]
	if p and p.Parent then return p end
	p = Instance.new("Part")
	p.Name = "LungeLane"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = LANE
	p.Size = Vector3.new(LANE_WIDTH, 0.15, 1)
	p.Parent = workspace
	-- an arrowhead where it lands: the spot not to be
	local tip = Instance.new("Part")
	tip.Name = "Tip"
	tip.Anchored, tip.CanCollide, tip.CanQuery, tip.CanTouch, tip.CastShadow = true, false, false, false, false
	tip.Material = Enum.Material.Neon
	tip.Color = LANE
	tip.Shape = Enum.PartType.Cylinder
	tip.Size = Vector3.new(0.16, LANE_WIDTH + 3, LANE_WIDTH + 3)
	tip.Parent = p
	lanes[m] = p
	return p
end
local function dropLane(m)
	if lanes[m] then lanes[m]:Destroy(); lanes[m] = nil end
end
local function outline(m, on)
	local h = outlines[m]
	if on and not (h and h.Parent) then
		h = Instance.new("Highlight")
		h.Name = "HunterOutline"
		h.FillColor, h.FillTransparency = LANE, 0.75
		h.OutlineColor, h.OutlineTransparency = LANE, 0
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = m
		outlines[m] = h
	elseif not on and h then
		h:Destroy(); outlines[m] = nil
	end
end
local ground = RaycastParams.new()
ground.FilterType = Enum.RaycastFilterType.Exclude
-- canopies and props are non-collide; the road is not. (Cast from 4 studs up, the
-- first live lane landed in a tree's crown and was invisible.)
ground.RespectCanCollide = true

-- ============ PER FRAME ============
local row = workspace:WaitForChild("SiliconValley", 30)
local lungeSeen = {}
local crouchSeen = {}
local live = {}
RunService.RenderStepped:Connect(function()
	local carrying = player:GetAttribute("Carrying") ~= nil
	local dist = player:GetAttribute("ChaseDist")
	local chasing = carrying and dist ~= nil
	btn.Visible = chasing
	-- 0 (far) .. 1 (on top of you)
	local fear = chasing and math.clamp(1 - (dist - 4.5) / 24, 0, 1) or 0
	-- quiet until it crouches (see v4.4 above): a faint wash for distance, a flash for the tell
	local tell = false
	local trow = row and row:FindFirstChild("TalentRow")
	if chasing and trow then
		for _, m in ipairs(trow:GetChildren()) do
			if m:IsA("Model") and m:GetAttribute("Chaser") and m:GetAttribute("ChasingUserId") == player.UserId
				and (m:GetAttribute("Windup") or m:GetAttribute("Lunging")) then tell = true end
		end
	end
	for _, e in ipairs(edges) do
		local a = tell and (0.55 + 0.25 * math.sin(os.clock() * 22)) or (fear * 0.18)
		e.BackgroundTransparency = 1 - a
	end
	if chasing then
		if not heart.IsPlaying then heart:Play() end
		heart.Volume = 0.15 + 0.75 * fear
		heart.PlaybackSpeed = 0.9 + 0.7 * fear
	elseif heart.IsPlaying then
		heart:Stop()
	end
	-- the cooldown shade, and "NOW!" while a hunter crouches
	local left = math.max(0, COOLDOWN - (os.clock() - lastBoostSent))
	cdFill.Size = UDim2.new(1, 0, left / COOLDOWN, 0)
	local crouch = false
	local tr = row and row:FindFirstChild("TalentRow")
	table.clear(live)
	if chasing and tr then
		for _, m in ipairs(tr:GetChildren()) do
			if m:IsA("Model") and m:GetAttribute("Chaser") and m:GetAttribute("ChasingUserId") == player.UserId then
				live[m] = true
				outline(m, true)
				crouch = crouch or m:GetAttribute("Windup") == true
				-- the sting, once per crouch
				if m:GetAttribute("Windup") == true then
					if not crouchSeen[m] then crouchSeen[m] = true; play(WHOOSH, 0.8, 0.55) end
				else
					crouchSeen[m] = nil
				end
				-- the lane: pulses through the crouch, solid while it lunges
				local from, to = m:GetAttribute("LungeFrom"), m:GetAttribute("LungeTo")
				if typeof(from) == "Vector3" and typeof(to) == "Vector3" and (to - from).Magnitude > 0.5 then
					local lane = laneFor(m)
					ground.FilterDescendantsInstances = { m, lane, player.Character }
					local mid = (from + to) / 2
					local hit = workspace:Raycast(mid + Vector3.new(0, 0.5, 0), Vector3.new(0, -8, 0), ground)
					local y = hit and hit.Position.Y + 0.12 or (from.Y - 2.5)
					local a, b = Vector3.new(from.X, y, from.Z), Vector3.new(to.X, y, to.Z)
					lane.Size = Vector3.new(LANE_WIDTH, 0.15, (b - a).Magnitude)
					lane.CFrame = CFrame.lookAt((a + b) / 2, b)
					local tip = lane:FindFirstChild("Tip")
					if tip then tip.CFrame = CFrame.new(b) * CFrame.Angles(0, 0, math.rad(90)) end
					local tr2 = m:GetAttribute("Lunging") and 0.15 or (0.25 + 0.3 * (0.5 + 0.5 * math.sin(os.clock() * 24)))
					lane.Transparency = tr2
					if tip then tip.Transparency = tr2 end
				else
					dropLane(m)
				end
				if m:GetAttribute("Lunging") == true then
					if not lungeSeen[m] then
						lungeSeen[m] = true
						--[[ Only when nothing else owns the lens. The chase camera
							sets its own FOV every frame from speed and the shot;
							tweening against that fights it every frame and reads
							as the picture flickering. ]]
						if not player:GetAttribute("ChaseCamOwns") then
							local cam = workspace.CurrentCamera
							TweenService:Create(cam, TweenInfo.new(0.08), { FieldOfView = 62 }):Play()
							task.delay(0.12, function() TweenService:Create(cam, TweenInfo.new(0.35), { FieldOfView = 70 }):Play() end)
						end
					end
				else
					lungeSeen[m] = nil
				end
			end
		end
	end
	-- a hunter that left (caught you, gave up, or the carry ended): no lane, no outline
	for m in pairs(lanes) do if not live[m] then dropLane(m) end end
	for m in pairs(outlines) do if not live[m] then outline(m, false) end end
	btnText.Text = (crouch and left <= 0) and "NOW!" or "BOOST"
	btnScale.Scale = (crouch and left <= 0) and (1.08 + 0.06 * math.sin(os.clock() * 18)) or 1
end)
