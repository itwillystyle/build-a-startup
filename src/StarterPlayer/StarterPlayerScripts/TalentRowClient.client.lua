--[[
	TalentRowClient -- LocalScript in StarterPlayer -> StarterPlayerScripts.

	v3.0 Talent Row, the player's side of TalentDrop:
	  - Recruit prompts show only on YOUR candidates; the Poach prompt never
	    shows on the candidate you are carrying (the server checks both too).
	  - A countdown over every carried candidate, readable by everyone: the
	    offer timer is the tension, so it lives in the world where the chase
	    is (Ride A Pet shows the egg's timer on the egg).
	  - One small chip, bottom-right (Steal An Egg's "in 35s" restock chip):
	    while carrying, how close the headhunter is; otherwise when the next
	    rare candidate is back.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local Notify = require(ReplicatedStorage:WaitForChild("Notify"))
-- v4.2: the chip owns the top strip for the whole chase (a phone text used to land on it)
local holding = false
local function setDanger(v)
	if v == holding then return end
	holding = v
	if v then Notify.hold("top", "headhunter") else Notify.release("headhunter") end
end

local valley = workspace:WaitForChild("SiliconValley", 60)
local row = valley and valley:WaitForChild("TalentRow", 60)
if not row then return end

-- ============ PROMPTS ============

local function syncPrompt(pp)
	local m = pp:FindFirstAncestorOfClass("Model")
	if not m then return end
	if pp.Name == "RecruitPrompt" then
		pp.Enabled = m:GetAttribute("Owner") == player.UserId
	elseif pp.Name == "PoachPrompt" then
		pp.Enabled = m:GetAttribute("CarriedBy") ~= player.UserId
	end
end

-- ============ COUNTDOWN OVER CARRIED CANDIDATES ============

local timers = {}   -- model -> TextLabel

local function addTimer(m)
	if timers[m] or not m:GetAttribute("Carried") then return end
	local head = m:FindFirstChild("Head")
	if not head then return end
	local bb = Instance.new("BillboardGui")
	bb.Name = "CarryTimer"
	bb.Size = UDim2.new(0, 120, 0, 44)
	bb.StudsOffset = Vector3.new(0, 3.2, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 180
	bb.Adornee = head
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, 0, 1, 0)
	t.Font = UIKit.HEAD
	t.TextScaled = true
	t.TextStrokeTransparency = 0.1
	t.TextColor3 = m:GetAttribute("TierColor") or Color3.new(1, 1, 1)
	t.Parent = bb
	bb.Parent = head
	timers[m] = t
end

-- v3.0.2: a headhunter flashes red while it winds up a dash (server attribute "Windup")
local function watchHunter(m)
	if not m:GetAttribute("Chaser") or m:FindFirstChild("WindupFlash") then return end
	local hl = Instance.new("Highlight")
	hl.Name = "WindupFlash"
	hl.FillColor = UIKit.RED
	hl.OutlineColor = UIKit.RED
	hl.FillTransparency = 0.35
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Enabled = m:GetAttribute("Windup") == true
	hl.Parent = m
	m:GetAttributeChangedSignal("Windup"):Connect(function() hl.Enabled = m:GetAttribute("Windup") == true end)
end

local function watchModel(m)
	if not m:IsA("Model") then return end
	addTimer(m)
	watchHunter(m)
	m:GetAttributeChangedSignal("Carried"):Connect(function() addTimer(m) end)
	m:GetAttributeChangedSignal("CarriedBy"):Connect(function()
		for _, d in ipairs(m:GetDescendants()) do if d:IsA("ProximityPrompt") then syncPrompt(d) end end
	end)
end

for _, d in ipairs(row:GetDescendants()) do
	if d:IsA("ProximityPrompt") then syncPrompt(d) end
	if d:IsA("Model") then watchModel(d) end
end
row.DescendantAdded:Connect(function(d)
	if d:IsA("ProximityPrompt") then task.defer(syncPrompt, d) end
	if d:IsA("Model") then task.defer(watchModel, d) end
end)

-- ============ RIDING POSE (v3.0.3) ============
-- While a player carries a hire they ride the scooter, so their legs must stop
-- walking. Drawn on every client for every rider (PreSimulation runs after the
-- Animator, so these joint transforms win); nothing replicates.
local RIDE = {
	LeftHip = CFrame.Angles(0.28, 0, 0), LeftKnee = CFrame.Angles(-0.35, 0, 0),
	RightHip = CFrame.Angles(-0.22, 0, 0), RightKnee = CFrame.Angles(-0.25, 0, 0),
	LeftShoulder = CFrame.Angles(1.15, 0, 0.1), RightShoulder = CFrame.Angles(1.15, 0, -0.1),
	LeftElbow = CFrame.Angles(0.35, 0, 0), RightElbow = CFrame.Angles(0.35, 0, 0),
	Waist = CFrame.Angles(0.14, 0, 0),
}
local function ridingJoints(char)
	local out = {}
	for _, d in ipairs(char:GetDescendants()) do
		-- player avatars now use AnimationConstraint joints (measured 25 Sep); older rigs use Motor6D
		if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and RIDE[d.Name] then out[d] = RIDE[d.Name] end
	end
	return out
end
local riderCache = {}   -- character -> { [Motor6D] = CFrame }
RunService.PreSimulation:Connect(function()
	for _, pl in ipairs(Players:GetPlayers()) do
		local char = pl.Character
		if char and pl:GetAttribute("CarrySpeed") then
			local j = riderCache[char]
			if not j then j = ridingJoints(char); riderCache[char] = j end
			for m, cf in pairs(j) do if m.Parent then m.Transform = cf end end
		elseif char then
			riderCache[char] = nil
		end
	end
end)

-- ============ THE CHIPS (v3.1) ============
--[[ Two jobs, two places. While you carry someone, the headhunter warning is
the only thing that matters, so it sits top-centre under the money, big.
The restock clock is calm information, so it is a row in the right column
under the quest card. The old single chip sat bottom-right, which is where a
phone draws the JUMP button. Distance is metres (the guide arrow's unit),
never "studs". ]]

local gui = Instance.new("ScreenGui")
gui.Name = "TalentRow"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 9
UIKit.safe(gui)
gui.Parent = player:WaitForChild("PlayerGui")

local danger = UIKit.card(gui, {
	Name = "Danger", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 96),
	Size = UDim2.new(0, 330, 0, 50), Visible = false,
}, { radius = 999, strokeWidth = 3 })
local dangerStroke = danger:FindFirstChildOfClass("UIStroke")
local dangerIcon = UIKit.icon(danger, "alert", 28, UIKit.GOLD, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0) })
local dangerText = UIKit.label(danger, "", 20, UIKit.CARD_TEXT, {
	Position = UDim2.new(0, 50, 0, 0), Size = UDim2.new(1, -64, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd,
}, UIKit.HEAD)
local dangerScale = Instance.new("UIScale", danger)

local restock = UIKit.card(UIKit.column(), {
	Name = "Restock", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 44), Visible = false,
}, { radius = 14 })
UIKit.icon(restock, "person", 22, UIKit.CARD_MUTED, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0) })
local restockText = UIKit.label(restock, "", 16, UIKit.CARD_TEXT, {
	Position = UDim2.new(0, 42, 0, 0), Size = UDim2.new(1, -52, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd,
}, UIKit.HEAD)

-- LOST: the one bad outcome in the game gets its own moment (it used to be a toast)
local lostCard = UIKit.card(gui, {
	Name = "Lost", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 96),
	Size = UDim2.new(0.9, 0, 0, 74), Visible = false,
}, { radius = 16, strokeWidth = 4, stroke = UIKit.RED })
local lcap = Instance.new("UISizeConstraint", lostCard)
lcap.MaxSize = Vector2.new(440, 74)
local lostTitle = UIKit.outlined(lostCard, "LOST!", 26, UIKit.RED, {
	Position = UDim2.new(0, 16, 0, 6), Size = UDim2.new(1, -32, 0, 32),
})
local lostText = UIKit.label(lostCard, "", 17, UIKit.CARD_TEXT, {
	Position = UDim2.new(0, 16, 0, 40), Size = UDim2.new(1, -32, 0, 24), TextTruncate = Enum.TextTruncate.AtEnd,
}, UIKit.HEAD)
local lostEdges = {}
for _, e in ipairs({
	{ Vector2.new(0, 0), UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0.14, 0), 90 },
	{ Vector2.new(0, 1), UDim2.new(0, 0, 1, 0), UDim2.new(1, 0, 0.14, 0), -90 },
	{ Vector2.new(0, 0), UDim2.new(0, 0, 0, 0), UDim2.new(0.09, 0, 1, 0), 0 },
	{ Vector2.new(1, 0), UDim2.new(1, 0, 0, 0), UDim2.new(0.09, 0, 1, 0), 180 },
}) do
	local f = Instance.new("Frame")
	f.AnchorPoint, f.Position, f.Size = e[1], e[2], e[3]
	f.BackgroundColor3 = UIKit.RED
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Parent = gui
	local g = Instance.new("UIGradient", f)
	g.Rotation = e[4]
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	table.insert(lostEdges, f)
end

local TweenService = game:GetService("TweenService")
-- top-centre cards fit between the left rail and the right column
-- (centred when it fits; on a narrow screen, centred in the gap instead)
local function centreWidth(maxW, card)
	local pg = player.PlayerGui
	local railCol = pg:FindFirstChild("Rail") and pg.Rail:FindFirstChild("Column")
	local rightCol = pg:FindFirstChild("RightColumn") and pg.RightColumn:FindFirstChild("Column")
	local vpX = workspace.CurrentCamera.ViewportSize.X
	local l = railCol and (railCol.AbsolutePosition.X + 86) or 12
	local r = rightCol and rightCol.AbsolutePosition.X or vpX - 12
	local centred = 2 * math.min(vpX / 2 - l, r - vpX / 2) - 16
	local cx, w = vpX / 2, centred
	if centred < 300 then cx, w = (l + r) / 2, r - l - 16 end
	if card then card.Position = UDim2.new(0, cx, 0, card.Position.Y.Offset) end
	return math.clamp(w, 240, maxW)
end
local lostSerial = 0
local lostRemote = ReplicatedStorage:WaitForChild("SVRemotes"):WaitForChild("CarryLost", 30)
if lostRemote then
	lostRemote.OnClientEvent:Connect(function(text)
		danger.Visible = false
		setDanger(false)
		-- v4.2: danger (P0) in the top lane; it bumps anything that is not danger
		Notify.show({ lane = "top", priority = 0, key = "lost",
			close = function() lostCard.Visible = false end,
			open = function(done)
				lostSerial += 1
				local mine = lostSerial
				lostText.Text = tostring(text or "They got away")
				lostCard.Position = UDim2.new(0.5, 0, 0, 60)
				lostCard.Size = UDim2.new(0, centreWidth(440, lostCard), 0, 74)
				lostCard.Visible = true
				TweenService:Create(lostCard, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Position = UDim2.new(lostCard.Position.X.Scale, lostCard.Position.X.Offset, 0, 96) }):Play()
				UIKit.sfx("thunk", 0.55, 0.8)
				for _, f in ipairs(lostEdges) do
					f.BackgroundTransparency = 0.35
					TweenService:Create(f, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
				end
				task.delay(3, function()
					if lostSerial == mine then lostCard.Visible = false end
					done()
				end)
			end })
	end)
end

local TIER_IDS = { "skilled", "star", "genius" }
local TIER_NAMES = { skilled = "SKILLED", star = "STAR", genius = "GENIUS" }

local function clock(sec)
	sec = math.max(0, math.floor(sec))
	return ("%d:%02d"):format(sec // 60, sec % 60)
end

local acc = 0
local wasClose = false
RunService.RenderStepped:Connect(function(dt)
	local serverNow = workspace:GetServerTimeNow()
	-- countdowns over carried candidates (the carrier's CarryDeadline, replicated)
	for m, t in pairs(timers) do
		if not m.Parent or not m:GetAttribute("Carried") then
			if t.Parent and t.Parent.Parent then t.Parent:Destroy() end
			timers[m] = nil
		else
			local carrier = Players:GetPlayerByUserId(m:GetAttribute("CarriedBy") or 0)
			local deadline = carrier and carrier:GetAttribute("CarryDeadline")
			t.Text = deadline and clock(deadline - serverNow) or ""
		end
	end
	if danger.Visible then dangerScale.Scale = 1 + (wasClose and 0.04 * math.sin(os.clock() * 14) or 0) end
	acc += dt
	if acc < 0.2 then return end
	acc = 0
	-- carrying: the headhunter, and nothing else
	if player:GetAttribute("Carrying") and not lostCard.Visible then
		restock.Visible = false
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local nearest, dashing
		for _, m in ipairs(row:GetChildren()) do
			if m:IsA("Model") and m:GetAttribute("Chaser") and m:GetAttribute("ChasingUserId") == player.UserId and m.PrimaryPart and root then
				nearest = (m.PrimaryPart.Position - root.Position).Magnitude
				dashing = m:GetAttribute("Windup") == true
			end
		end
		if nearest then
			if not danger.Visible then danger.Size = UDim2.new(0, centreWidth(330, danger), 0, 50) end
			danger.Visible = true
			setDanger(true)
			local close = dashing or nearest < 20
			if close and not wasClose then UIKit.sfx("thunk", 1.4, 0.5) end
			wasClose = close
			local col = close and UIKit.RED or UIKit.GOLD
			dangerIcon.ImageColor3 = col
			dangerStroke.Color = col
			dangerText.TextColor3 = close and UIKit.RED or UIKit.CARD_TEXT
			dangerText.Text = dashing and "Headhunter DASH! Move!" or ("Headhunter %dm behind"):format(math.floor(nearest / 3.5 + 0.5))
		else
			danger.Visible = false
			setDanger(false)
			wasClose = false
		end
		return
	end
	danger.Visible = false
	setDanger(false)
	wasClose = false
	-- not carrying: when the next rare hire is back on the street
	local soonest, which
	for _, id in ipairs(TIER_IDS) do
		local at = player:GetAttribute("Restock_" .. id)
		if at and at > serverNow and (not soonest or at < soonest) then soonest, which = at, id end
	end
	if soonest then
		restock.Visible = true
		restockText.Text = ("%s hire back in %s"):format(TIER_NAMES[which], clock(soonest - serverNow))
	else
		restock.Visible = false
	end
end)
