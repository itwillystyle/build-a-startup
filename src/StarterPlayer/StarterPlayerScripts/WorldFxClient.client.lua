--[[
	WorldFxClient -- LocalScript in StarterPlayer -> StarterPlayerScripts.

	v2.8.1: the world's short effects, drawn on each player's own machine.

	The server used to tween these itself, which sends every frame of the
	animation to every player. Measured on a full server: one WRITE CODE tap a
	second = 13.7 KB/s (idle 0.49), a room build ~199 KB, an HQ upgrade
	~266 KB. Now the server sends one small event and this script animates it.

	Popup (anchor, text, color): the floating "+$5" / "HIRED" / "LAUNCHED" text.
	Rise (parts, drop, seconds): new rooms and HQ levels growing out of the
	ground. The server has already put every part at its final place; this only
	plays the motion locally.

	v5 FIX, "when you upgrade an HQ you get stuck in the floor and die": your
	own character is simulated on YOUR machine, against the parts where this
	script has put them. A rise swept the building's walls and full-width storey
	slabs up through whoever stood inside; the solver shoved them (measured:
	y 4.4 -> 3.7 -> 7.7 at HQ 3), sometimes down through the 1-stud garage floor,
	with nothing under it but void (-500 kills). Now a rise is not played for a
	building you are standing in (you are in the level-up flyover anyway), and
	a character that ever drops far below the valley is put back at your door.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local remotes = ReplicatedStorage:WaitForChild("SVRemotes")
local popupRemote = remotes:WaitForChild("Popup", 30)
local riseRemote = remotes:WaitForChild("Rise", 30)

local GOOD = Color3.fromRGB(90, 220, 130)
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local NEAR = 70      -- studs from the camera

-- v3.1: popups go to every client, and the 25 Sep review watched a neighbour's
-- "Need $2,500" float over someone else's lot. A red popup is a refusal, and
-- a refusal is private: it only draws on your own plot. Everything else only
-- draws near your camera.
local function myPlot()
	local idx = player:GetAttribute("Plot")
	local sv = workspace:FindFirstChild("SiliconValley")
	local plots = sv and sv:FindFirstChild("Plots")
	return idx and plots and plots:FindFirstChild("Plot" .. idx) or nil
end
local function isRefusal(c)
	return typeof(c) == "Color3" and c.R > 0.9 and c.G < 0.6 and c.B < 0.6   -- BAD = (255, 140, 140)
end
local function anchorPos(a)
	if a:IsA("BasePart") then return a.Position end
	if a:IsA("Model") then return a:GetPivot().Position end
	if a:IsA("Attachment") then return a.WorldPosition end
	return nil
end

if popupRemote then
	popupRemote.OnClientEvent:Connect(function(anchor, text, color)
		if typeof(anchor) ~= "Instance" or not anchor.Parent then return end
		if isRefusal(color) then
			local mine = myPlot()
			-- v4.2: your recruits stand on the sidewalk, OUTSIDE your lot, so "No free
			-- seat" on your own candidate was thrown away and pressing E looked dead
			-- (his report). A refusal on something you own (Owner = you) is yours too.
			local m = anchor:FindFirstAncestorWhichIsA("Model")
			local owned = m and m:GetAttribute("Owner") == player.UserId
			if not ((mine and anchor:IsDescendantOf(mine)) or owned) then return end
		end
		local at = anchorPos(anchor)
		local cam = workspace.CurrentCamera
		if at and cam and (cam.CFrame.Position - at).Magnitude > NEAR then return end
		-- v5: a sticker outline (a 1 px TextStroke vanished over a bright floor), and
		-- room for a whole sentence ("No free seat · build or upgrade a room" was cut off at 240 px)
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.new(0, 420, 0, 72)
		bb.StudsOffset = Vector3.new(0, 3.5, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = NEAR
		bb.Adornee = anchor
		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, 0, 1, 0)
		t.BackgroundTransparency = 1
		t.Text = tostring(text)
		t.TextColor3 = typeof(color) == "Color3" and color or GOOD
		t.TextStrokeTransparency = 1
		t.TextSize = 28
		t.TextWrapped = true
		t.Font = Enum.Font.FredokaOne
		t.Parent = bb
		local st = Instance.new("UIStroke")
		st.Color = Color3.fromRGB(20, 22, 30)
		st.Thickness = 3
		st.LineJoinMode = Enum.LineJoinMode.Round
		st.Parent = t
		bb.Parent = anchor
		TweenService:Create(bb, TweenInfo.new(1.1), { StudsOffset = Vector3.new(0, 6.5, 0) }):Play()
		TweenService:Create(t, TweenInfo.new(1.1), { TextTransparency = 1 }):Play()
		TweenService:Create(st, TweenInfo.new(1.1), { Transparency = 1 }):Play()
		task.delay(1.2, function() bb:Destroy() end)
	end)
end

-- is the local character inside (or on top of) the footprint of these parts?
local function standingIn(parts)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	local lo, hi
	for _, p in ipairs(parts) do
		if typeof(p) == "Instance" and p:IsA("BasePart") and p.Parent then
			local h = p.Size / 2
			local c = p.Position
			local a = Vector3.new(c.X - math.max(h.X, h.Z), c.Y - h.Y, c.Z - math.max(h.X, h.Z))   -- rotation-safe box
			local b = Vector3.new(c.X + math.max(h.X, h.Z), c.Y + h.Y, c.Z + math.max(h.X, h.Z))
			lo = lo and lo:Min(a) or a
			hi = hi and hi:Max(b) or b
		end
	end
	if not lo then return false end
	local r, m = root.Position, 6
	return r.X > lo.X - m and r.X < hi.X + m and r.Z > lo.Z - m and r.Z < hi.Z + m and r.Y < hi.Y + 12
end

if riseRemote then
	riseRemote.OnClientEvent:Connect(function(parts, drop, seconds)
		if type(parts) ~= "table" then return end
		if standingIn(parts) then return end      -- never sweep a building through the player inside it
		drop = tonumber(drop) or 10
		seconds = tonumber(seconds) or 0.8
		local info = TweenInfo.new(seconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		for _, p in ipairs(parts) do
			if typeof(p) == "Instance" and p:IsA("BasePart") and p.Parent then
				local final = p.CFrame
				p.CFrame = final * CFrame.new(0, -drop, 0)
				TweenService:Create(p, info, { CFrame = final }):Play()
			end
		end
	end)
end

-- the catch: nowhere in the valley is below y -40, so a character down there has
-- fallen through something. Put it back at its company's door instead of letting
-- it drop to the -500 kill height.
task.spawn(function()
	while true do
		task.wait(0.5)
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 and root.Position.Y < -40 then
			local plot = myPlot()
			local sp = plot and plot:FindFirstChild("Spawn", true)
			if sp then
				root.AssemblyLinearVelocity = Vector3.zero
				char:PivotTo(sp.CFrame + Vector3.new(0, 3, 0))
			end
		end
	end
end)
