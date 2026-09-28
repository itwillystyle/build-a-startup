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
	plays the motion locally, so nothing a player can collide with is ever in
	a different place on the server.
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
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.new(0, 240, 0, 44)
		bb.StudsOffset = Vector3.new(0, 3.5, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = NEAR
		bb.Adornee = anchor
		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, 0, 1, 0)
		t.BackgroundTransparency = 1
		t.Text = tostring(text)
		t.TextColor3 = typeof(color) == "Color3" and color or GOOD
		t.TextStrokeTransparency = 0.15
		t.TextSize = 28
		t.Font = Enum.Font.FredokaOne
		t.Parent = bb
		bb.Parent = anchor
		TweenService:Create(bb, TweenInfo.new(1.1), { StudsOffset = Vector3.new(0, 6.5, 0) }):Play()
		TweenService:Create(t, TweenInfo.new(1.1), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.delay(1.2, function() bb:Destroy() end)
	end)
end

if riseRemote then
	riseRemote.OnClientEvent:Connect(function(parts, drop, seconds)
		if type(parts) ~= "table" then return end
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
