--[[
	TalentRevealClient -- LocalScript, StarterPlayerScripts.

	A rare hire is the roll-to-chase moment, so it gets a moment. Rarer =
	longer hold, bigger sound, stronger edge glow: the ceremony length IS the
	information (the card shop's Rip rule). Non-blocking: no input sink, no
	camera, nothing dimmed; tap the card to put it away early.

	v3.1 (25 Sep reviews):
	  - it showed nobody. The card now holds a live portrait of THE person you
	    hired (a clone of their rig in a ViewportFrame)
	  - "STAR ENGINEER!" / "Dana · x2.5 money forever": the person first, the
	    reward in money, not "output"
	  - one sound per tier (licensed APM stings, preload-checked) and a
	    screen-edge glow in the talent colour
	  - a NEW Index entry flies into the INDEX button, so the collection is
	    discovered by watching it fill, not by reading a badge
	  - IgnoreGuiInset + safe insets: it used to land 56 px low, over WRITE CODE
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local Notify = require(ReplicatedStorage:WaitForChild("Notify"))
local remote = ReplicatedStorage:WaitForChild("SVRemotes"):WaitForChild("TalentReveal", 30)
if not remote then return end

local HOLD = { [2] = 2.6, [3] = 3.4, [4] = 4.2, [5] = 5.5 }
local SOUND = { [2] = "ding", [3] = "star", [4] = "genius", [5] = "unicorn" }
local TOP = 96          -- under the money and the income line
local CARD_H = 124

local gui = Instance.new("ScreenGui")
gui.Name = "TalentReveal"
gui.ResetOnSpawn = false
gui.DisplayOrder = 13
gui.IgnoreGuiInset = true
UIKit.safe(gui)
gui.Parent = player:WaitForChild("PlayerGui")

-- ============ EDGE GLOW ============
-- four gradients on the screen edges, in the talent colour, fading out
local edges = {}
local function edge(name, anchor, pos, size, rot)
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = anchor
	f.Position = pos
	f.Size = size
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 1
	f.Parent = gui
	local g = Instance.new("UIGradient")
	g.Rotation = rot
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = f
	table.insert(edges, f)
end
edge("Top", Vector2.new(0, 0), UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0.16, 0), 90)
edge("Bottom", Vector2.new(0, 1), UDim2.new(0, 0, 1, 0), UDim2.new(1, 0, 0.16, 0), -90)
edge("Left", Vector2.new(0, 0), UDim2.new(0, 0, 0, 0), UDim2.new(0.1, 0, 1, 0), 0)
edge("Right", Vector2.new(1, 0), UDim2.new(1, 0, 0, 0), UDim2.new(0.1, 0, 1, 0), 180)

local function glow(color, strength, seconds)
	for _, f in ipairs(edges) do
		f.BackgroundColor3 = color
		f.BackgroundTransparency = 1 - strength
		TweenService:Create(f, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
	end
end

-- ============ THE CARD ============

local card = Instance.new("TextButton")
card.Name = "Card"
card.Text = ""
card.AutoButtonColor = false
card.AnchorPoint = Vector2.new(0.5, 0)
card.Position = UDim2.new(0.5, 0, 0, -CARD_H - 20)
card.Size = UDim2.new(0.9, 0, 0, CARD_H)
card.BackgroundColor3 = UIKit.CARD
card.Visible = false
card.Parent = gui
Instance.new("UICorner", card).CornerRadius = UDim.new(0, 18)
local cap = Instance.new("UISizeConstraint", card)
cap.MaxSize = Vector2.new(480, CARD_H)
local stroke = Instance.new("UIStroke", card)
stroke.Thickness = 4
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

-- the portrait: the person you just hired, on a disc in the talent colour
local disc = Instance.new("Frame")
disc.Name = "Portrait"
disc.Position = UDim2.new(0, 12, 0.5, -46)
disc.Size = UDim2.new(0, 92, 0, 92)
disc.BorderSizePixel = 0
disc.Parent = card
Instance.new("UICorner", disc).CornerRadius = UDim.new(1, 0)
local vpf = Instance.new("ViewportFrame")
vpf.BackgroundTransparency = 1
vpf.Size = UDim2.new(1, 0, 1, 0)
vpf.Ambient = Color3.fromRGB(210, 210, 215)
vpf.LightColor = Color3.fromRGB(255, 250, 240)
vpf.LightDirection = Vector3.new(-0.4, -1, -0.6)
vpf.Parent = disc
Instance.new("UICorner", vpf).CornerRadius = UDim.new(1, 0)
local fallback = UIKit.icon(disc, "person", 56, UIKit.INK, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Visible = false })

local TEXT_X = 116
local title = UIKit.outlined(card, "", 30, UIKit.TEXT, {
	Name = "Title", Position = UDim2.new(0, TEXT_X, 0, 12), Size = UDim2.new(1, -(TEXT_X + 12), 0, 36),
	TextScaled = true,
})
local tsc = Instance.new("UITextSizeConstraint", title)
tsc.MaxTextSize = 30
tsc.MinTextSize = 18
local titleScale = Instance.new("UIScale", title)

local who = UIKit.label(card, "", 20, UIKit.INK, {
	Name = "Who", Position = UDim2.new(0, TEXT_X, 0, 50), Size = UDim2.new(1, -(TEXT_X + 12), 0, 24),
	TextScaled = true,
}, UIKit.HEAD)
local wsc = Instance.new("UITextSizeConstraint", who)
wsc.MaxTextSize = 20
wsc.MinTextSize = 14
local odds = UIKit.label(card, "", 16, UIKit.MUTED_TEXT, {
	Name = "Odds", Position = UDim2.new(0, TEXT_X, 0, 76), Size = UDim2.new(1, -(TEXT_X + 12), 0, 18),
	TextTruncate = Enum.TextTruncate.AtEnd,
}, UIKit.HEAD)

-- "NEW IN INDEX 7/25", a blue chip on the bottom edge
local chip = Instance.new("Frame")
chip.Name = "NewIndex"
chip.Position = UDim2.new(0, TEXT_X, 1, -28)
chip.Size = UDim2.new(0, 170, 0, 22)
chip.BackgroundColor3 = UIKit.BLUE
chip.BorderSizePixel = 0
chip.Visible = false
chip.Parent = card
Instance.new("UICorner", chip).CornerRadius = UDim.new(1, 0)
local chipText = UIKit.label(chip, "", 14, UIKit.TEXT, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center }, UIKit.HEAD)

-- ============ PORTRAIT ============

-- one camera for the life of the card (ClearAllChildren destroyed it, and the
-- second reveal errored on "Parent property of Camera is locked" and never showed)
local portraitCam = Instance.new("Camera")
portraitCam.FieldOfView = 40
portraitCam.Parent = vpf
vpf.CurrentCamera = portraitCam

local function portrait(rig)
	for _, ch in ipairs(vpf:GetChildren()) do
		if ch ~= portraitCam and not ch:IsA("UICorner") then ch:Destroy() end
	end
	if not (rig and rig:IsA("Model") and rig:FindFirstChild("Head")) then return false end
	local ok, clone = pcall(function()
		local was = rig.Archivable
		rig.Archivable = true
		local c = rig:Clone()
		rig.Archivable = was
		return c
	end)
	if not ok or not clone then return false end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BillboardGui") or d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = 0     -- v3.5: never inherit StaffAnimClient's distance cull
		end
	end
	local hum = clone:FindFirstChildOfClass("Humanoid")
	if hum then hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end
	-- v3.5: the copy must not carry the staff tag, or StaffAnimClient adopts it
	-- as a staff member and its distance cull hides the portrait (found live:
	-- the card showed an empty disc)
	game:GetService("CollectionService"):RemoveTag(clone, "SVStaff")
	clone.Parent = vpf
	local head = clone:FindFirstChild("Head")
	local look = head.CFrame.LookVector
	-- head and shoulders: the face is who you hired
	local target = head.Position - Vector3.new(0, 0.55, 0)
	portraitCam.CFrame = CFrame.lookAt(target + look * 4.6 + Vector3.new(0, 0.5, 0), target)
	return true
end

-- ============ FLY TO THE INDEX ============

local function flyToIndex(color, roleKey)
	local rail = player.PlayerGui:FindFirstChild("Rail")
	local target = rail and rail:FindFirstChild("IndexButton", true)
	if not (target and target.Visible) then
		-- the INDEX button appears with the first entry; give it a frame to lay out
		task.wait(0.3)
		target = rail and rail:FindFirstChild("IndexButton", true)
		if not (target and target.Visible) then return end
	end
	local token = Instance.new("Frame")
	token.AnchorPoint = Vector2.new(0.5, 0.5)
	token.Size = UDim2.new(0, 46, 0, 46)
	token.BackgroundColor3 = color
	token.BorderSizePixel = 0
	token.ZIndex = 30
	local from = disc.AbsolutePosition + disc.AbsoluteSize / 2
	token.Position = UDim2.new(0, from.X, 0, from.Y)
	token.Parent = gui
	Instance.new("UICorner", token).CornerRadius = UDim.new(1, 0)
	local st = Instance.new("UIStroke", token)
	st.Color = UIKit.TEXT
	st.Thickness = 3
	UIKit.icon(token, UIKit.ROLE_ICON[roleKey] or "person", 26, UIKit.INK, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), ZIndex = 31,
	})
	local to = target.AbsolutePosition + target.AbsoluteSize / 2
	local tw = TweenService:Create(token, TweenInfo.new(0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut),
		{ Position = UDim2.new(0, to.X, 0, to.Y), Size = UDim2.new(0, 28, 0, 28) })
	tw:Play()
	tw.Completed:Wait()
	token:Destroy()
	UIKit.sfx("ding", 1.3)
	local sc = target:FindFirstChildOfClass("UIScale")
	if sc then
		sc.Scale = 1.25
		TweenService:Create(sc, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

-- ============ SHOW ============

local serial = 0
local cardX = 0
local doneFor = {}      -- v4.2: serial -> the director's done() for that showing
local function hide(mine)
	if serial ~= mine or not card.Visible then
		local f = doneFor[mine]; doneFor[mine] = nil
		if f then f() end
		return
	end
	local tw = TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.new(0, cardX, 0, -CARD_H - 20) })
	tw:Play()
	tw.Completed:Wait()
	if serial == mine then
		card.Visible = false
		player:SetAttribute("RevealShowing", false)
	end
	local f = doneFor[mine]; doneFor[mine] = nil
	if f then f() end
end
card.MouseButton1Click:Connect(function() task.spawn(hide, serial) end)

-- v4.2: the card is an earned moment (P1) in the top lane; the director keeps
-- it from landing on the phone banner, the HQ banner or the headhunter chip
local function showCard(d, done)
	serial += 1
	local mine = serial
	doneFor[mine] = done
	local tier = d.tier or 2
	local col = Color3.new(d.color[1], d.color[2], d.color[3])
	local role = string.upper(tostring(d.role or "hire"))
	local roleKey = string.lower(tostring(d.role or ""))
	title.Text = ("%s %s!"):format(string.upper(tostring(d.name)), role == "RESEARCH" and "RESEARCHER" or role)
	title.TextColor3 = col
	stroke.Color = UIKit.darker(col, 0.8)
	disc.BackgroundColor3 = col
	local mult = tostring(d.mult):gsub("%.0$", "")
	who.Text = ("%s  ·  x%s money forever"):format(tostring(d.who or "New hire"), mult)
	odds.Text = d.signed and "Signed from the street" or ("Lucky! 1 in %s hires"):format(tostring(d.odds))
	chip.Visible = d.newIndex == true
	chipText.Text = ("NEW IN INDEX  %d / 25"):format(tonumber(d.indexCount) or 0)
	local okP, shown = pcall(portrait, d.rig)
	fallback.Visible = not (okP and shown)

	-- fit between the left rail and the right column (the goal card), so neither
	-- is covered: centred when it fits, else centred in the gap (UIKit.hudGap)
	local cx, w = UIKit.hudGap(480)
	cardX = cx - gui.AbsolutePosition.X
	card.Size = UDim2.new(0, math.max(260, w), 0, CARD_H)
	card.Visible = true
	player:SetAttribute("RevealShowing", true)       -- client-local: PhoneClient moves its banner below this card
	card.Position = UDim2.new(0, cardX, 0, -CARD_H - 20)
	TweenService:Create(card, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0, cardX, 0, TOP) }):Play()
	titleScale.Scale = 0.3
	TweenService:Create(titleScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	UIKit.sfx(SOUND[tier] or "ding", tier == 2 and 1.15 or 1)
	glow(col, ({ [2] = 0.35, [3] = 0.5, [4] = 0.65, [5] = 0.8 })[tier] or 0.4, 0.8 + tier * 0.3)

	if d.newIndex then
		task.delay(1.2, function() if serial == mine then flyToIndex(col, roleKey) end end)
	end
	task.delay(HOLD[tier] or 2.6, function() hide(mine) end)
end

remote.OnClientEvent:Connect(function(d)
	if type(d) ~= "table" then return end
	-- v3.6: never under the WHILE YOU WERE AWAY card. HudClient sets WelcomeDone within ~20 s.
	local t0 = os.clock()
	while player:GetAttribute("WelcomeDone") ~= true and os.clock() - t0 < 25 do task.wait(0.2) end
	Notify.show({ lane = "top", priority = 1, key = "reveal",
		open = function(done) showCard(d, done) end,
		close = function() task.spawn(hide, serial) end })
end)
