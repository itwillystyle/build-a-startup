--[[
	IntroClient -- LocalScript in StarterPlayer -> StarterPlayerScripts.

	THE WELCOME. His ask: "similar to Sell Lemons -- they have a lemon pop-up
	intro, a welcoming thing, almost like a cutscene."

	Five seconds, three shots, then the game:
	  1. high over the valley -- SIX campuses, YOUR name on the card
	  2. swoop to your lot -- "this one is yours"
	  3. through the garage door to the laptop -- "start here"
	Then the camera hands back and the laptop glows for ten seconds, so the
	first verb is the one lit object in the room.

	RULES LEARNED THE HARD WAY:
	  - never capture a Scriptable camera as "previous" (the card shop froze a
	    camera dead that way); always restore to Custom
	  - touch skips ONLY via the visible SKIP button -- a finger-drag is the
	    mobile camera and would skip everything on frame one
	  - nothing here dims or blocks; it is a camera and a caption, not a gate
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local GOLD = Color3.fromRGB(255, 208, 70)
local UIKit = require(game:GetService("ReplicatedStorage"):WaitForChild("UIKit"))

-- ============ FIND MY PLOT ============

local function myPlot()
	local idx = player:GetAttribute("Plot")
	local sv = workspace:FindFirstChild("SiliconValley")
	local pf = idx and sv and sv:FindFirstChild("Plots") and sv.Plots:FindFirstChild("Plot" .. idx)
	if not pf then return nil end
	return pf, pf:GetAttribute("Pivot")
end

-- ============ UI ============

local gui = Instance.new("ScreenGui")
gui.Name = "Intro"
gui.ResetOnSpawn = false
gui.DisplayOrder = 12
gui.IgnoreGuiInset = true
gui.Enabled = false
UIKit.safe(gui)
gui.Parent = player:WaitForChild("PlayerGui")

-- v3.1: a white card like every other HUD card (the dark gold-rim panel was
-- the anti-reference), the name in the game's display font
local card = UIKit.card(gui, {
	Name = "Card", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40),
	Size = UDim2.new(0.9, 0, 0, 112),
}, { radius = 18, strokeWidth = 3, stroke = UIKit.darker(UIKit.GOLD, 0.8) })
local cap = Instance.new("UISizeConstraint", card)
cap.MaxSize = Vector2.new(620, 112)

local title = UIKit.outlined(card, "BUILD A STARTUP!", 30, GOLD, {
	Position = UDim2.new(0, 20, 0, 12), Size = UDim2.new(1, -40, 0, 38),
})

local line = UIKit.label(card, "", 18, UIKit.CARD_TEXT, {
	Position = UDim2.new(0, 20, 0, 54), Size = UDim2.new(1, -150, 0, 46), TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
}, UIKit.HEAD)

local skip = UIKit.button(card, "SKIP", UIKit.SURFACE_2, {
	AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -14), Size = UDim2.new(0, 110, 0, 48),
}, { textSize = 18, dark = true })

-- ============ THE SHOTS ============

local skipped = false
skip.MouseButton1Click:Connect(function() skipped = true end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not gui.Enabled or isTouch then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Keyboard then
		skipped = true
	end
end)

local function glide(cam, fromCF, toCF, seconds)
	local t0 = os.clock()
	while true do
		if skipped then return end
		local a = math.clamp((os.clock() - t0) / seconds, 0, 1)
		local e = a * a * (3 - 2 * a)
		cam.CFrame = fromCF:Lerp(toCF, e)
		if a >= 1 then return end
		RunService.RenderStepped:Wait()
	end
end

local function say(text)
	line.Text = text
	line.TextTransparency = 1
	TweenService:Create(line, TweenInfo.new(0.35), { TextTransparency = 0 }):Play()
end

local function lightTheLaptop(pf)
	local laptop = pf and pf:FindFirstChild("Garage") and pf.Garage:FindFirstChild("Laptop")
	if not laptop then return end
	local hl = Instance.new("Highlight")
	hl.FillColor = GOLD
	hl.OutlineColor = GOLD
	hl.FillTransparency = 0.7
	hl.OutlineTransparency = 0
	hl.Parent = laptop
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 10 and hl.Parent do
			hl.FillTransparency = 0.55 + 0.35 * (0.5 + 0.5 * math.sin((os.clock() - t0) * 4))
			task.wait(0.05)
		end
		hl:Destroy()
	end)
end

--[[ v4.0 THE FLYOVER. The old intro was three straight glides that stopped
dead between them (a slideshow), over a static caption card. Now one
continuous spline flight (Cine.lua) with letterbox bars and title cards:
the valley from the Bay, the six campuses, DOWNTOWN (where your apartment
will be), your lot, through the garage door to the laptop. ~10 s, SKIP any
time; returning players get a 3-second "welcome back" over their campus. ]]
local Cine = require(game:GetService("ReplicatedStorage"):WaitForChild("Cine"))

local function runIntro()
	local pf, pivot
	local t0 = os.clock()
	repeat
		pf, pivot = myPlot()
		if not pf then task.wait(0.2) end
	until pf or os.clock() - t0 > 8
	if not pf then return end
	local char = player.Character or player.CharacterAdded:Wait()
	char:WaitForChild("Humanoid", 5)
	local t1 = os.clock()
	while player:GetAttribute("MenuDone") ~= true and os.clock() - t1 < 600 do task.wait(0.1) end
	task.wait(0.3)

	local P = function(x, y, z) return pivot:PointToWorldSpace(Vector3.new(x, y, z)) end
	local hq = P(0, 8, 0)
	local laptop = P(0, 4, -9)
	local returning = player:GetAttribute("Returning") == true
	if returning then
		local away = player:GetAttribute("OfflineEarned") or 0
		Cine.play({
			{ pos = P(95, 60, 130), look = hq, t = 0, title = ("WELCOME BACK, %s"):format(string.upper(player.DisplayName)),
				sub = away > 0 and "Your team kept working while you were away." or "Pick up where you left off." },
			{ pos = P(40, 26, 70), look = hq, t = 2.8 },
		}, { fov = 58 })
		return
	end
	-- v5: a first impression is never night. The flyover runs at bright afternoon
	-- (SkyClient's own clock override, client-side), then the sky eases back to the
	-- server's hour over 5 s (it reads as the sun going down, not a jump)
	local Lighting = game:GetService("Lighting")
	local realAt, realHour = os.clock(), Lighting.ClockTime
	local SHOW_HOUR = 13.5
	workspace:SetAttribute("SVClockOverride", SHOW_HOUR)
	--[[ v4.7 LAYER 1. The flyover was six shots, 10.5 s, before the camera came
	back -- and three of them (SILICON VALLEY / SIX FOUNDERS / DOWNTOWN) were mood
	and a promise about apartments the player cannot act on for half an hour. The
	playbook's first-minute rule is "spawn inside the world, no cutscene", and
	first-play bounce under 60 s is one of Roblox's top-tier ranking signals, so
	every second here is paid for twice. Now ONE continuous 3.3 s descent from the
	valley to the laptop, keeping only the two beats that teach: this is yours,
	start here. The scale shot is not cut, it is the start of the same move. ]]
	--[[ v4.9 THE OPENING FLIP. The flyover above opened on an empty lot and the
	caption said "a garage, a laptop, and zero dollars" -- the smallest thing in a
	game that contains a hundred-floor tower. Measured against the 2026 playbook
	that is backwards: the first ninety seconds have to carry a wow that also
	plays on video, and first-play bounce is a top-tier ranking signal.

	So shot one now opens on the DESTINATION, looking up:
	  * if another founder in this server has built past their lobby, theirs --
	    a real tower with a real name on it, which is social proof the game
	    cannot fake;
	  * otherwise a translucent ghost of the finished building standing on your
	    own lot, built from Wafers.towerSpec() so it is the real massing.
	Then the camera pulls back to your lot and down to the laptop, as before.
	Three beats became four and 3.3 s became ~3.8 s: half a second bought the
	only shot in the intro worth filming. ]]
	local ghost, hero, heroLook, heroName = nil, nil, nil, nil

	-- the tallest FINISHED-ENOUGH tower belonging to someone else, if there is one
	do
		local sv = workspace:FindFirstChild("SiliconValley")
		local plots = sv and sv:FindFirstChild("Plots")
		local best = 0
		for _, other in ipairs(plots and plots:GetChildren() or {}) do
			-- plot.Wafers is a FOLDER, not a Model: GetBoundingBox does not exist
			-- on it, so measure the parts. (The first draft tested IsA("Model")
			-- and therefore never found a neighbour at all.)
			local w = other ~= pf and other:FindFirstChild("Wafers")
			if w then
				local base = other:GetAttribute("Pivot")
				local top
				for _, d in ipairs(w:GetDescendants()) do
					if d:IsA("BasePart") then
						local y = d.Position.Y + d.Size.Y / 2
						if not top or y > top then top = y end
					end
				end
				local height = top and base and (top - base.Position.Y) or 0
				if base and height > 45 and height > best then
					best = height
					-- stand back on the road side, proportional to how tall it actually is
					local out = base.LookVector * (top * 1.25) + base.RightVector * (top * 0.35)
					hero = Vector3.new(base.Position.X, top * 0.62, base.Position.Z) + out
					heroLook = Vector3.new(base.Position.X, top * 0.45, base.Position.Z)
					heroName = other:GetAttribute("Company")
				end
			end
		end
	end

	-- nobody has built yet: show them their own finished building as a blueprint
	if not hero then
		local spec = pf.Parent and pf.Parent:GetAttribute("TowerSpec")
		if spec and spec ~= "" then
			ghost = Instance.new("Model")
			ghost.Name = "SVTowerGhost"
			local top = 0
			for band in string.gmatch(spec, "[^|]+") do
				local r, y0, y1 = string.match(band, "(%-?%d+):(%-?%d+):(%-?%d+)")
				r, y0, y1 = tonumber(r), tonumber(y0), tonumber(y1)
				if r and y1 and y1 > y0 then
					local c = Instance.new("Part")
					c.Shape = Enum.PartType.Cylinder
					c.Size = Vector3.new(y1 - y0, r * 2, r * 2)
					c.CFrame = CFrame.new(P(0, (y0 + y1) / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
					c.Anchored, c.CanCollide, c.CanQuery, c.CanTouch = true, false, false, false
					c.CastShadow = false
					--[[ MEASURED: ForceField at 0.62 was all but invisible against the
						afternoon sky the flyover forces -- it rendered as a faint sliver.
						Translucent SmoothPlastic plus the game's own Highlight outline
						reads as a blueprint and keeps the silhouette crisp. ]]
					c.Material = Enum.Material.SmoothPlastic
					c.Color = Color3.fromRGB(96, 170, 226)
					c.Transparency = 0.5
					c.Parent = ghost
					top = math.max(top, y1)
				end
			end
			if #ghost:GetChildren() > 0 then
				local hl = Instance.new("Highlight")
				hl.Adornee = ghost
				hl.FillTransparency = 1
				hl.OutlineColor = Color3.fromRGB(24, 44, 70)
				hl.DepthMode = Enum.HighlightDepthMode.Occluded
				hl.Parent = ghost
				ghost.Parent = workspace
				--[[ framing is a FRACTION of the tower's own height, not fixed studs:
					at a fixed 168 back the crown clipped off the top of frame. At
					1.25x height back and 0.62x up, a 205-stud tower fills about
					70% of a 16:9 frame at FOV 60 with the garage still in shot --
					the scale contrast is the whole point of the picture. ]]
				hero = P(top * 0.35, top * 0.62, top * 1.25)
				heroLook = P(0, top * 0.45, 0)
			else
				ghost:Destroy()
				ghost = nil
			end
		end
	end

	local shots = {}
	if hero then
		table.insert(shots, { pos = hero, look = heroLook, t = 0,
			title = heroName and heroName ~= "" and ("%s IS ALREADY BUILDING"):format(string.upper(heroName))
				or "ONE HUNDRED FLOORS",
			sub = heroName and heroName ~= "" and "Six founders share this valley. One lot is still empty."
				or "That is what you are here to build. It starts with a garage." })
	end
	-- framed by eye: at 260/150/330 the garage was one box among many and the
	-- caption lied; this height still shows the hills and the road but the lot
	-- is unmistakably the subject
	table.insert(shots, { pos = P(140, 80, 180), look = P(0, 10, 0), t = hero and 1.5 or 0,
		title = "THIS LOT IS YOURS", sub = "A garage, a laptop, and zero dollars." })
	table.insert(shots, { pos = P(50, 30, 78), look = hq, t = hero and 1.2 or 2.0 })
	table.insert(shots, { pos = P(6, 6.5, 6), look = laptop, t = hero and 1.1 or 1.3, title = "START HERE",
		sub = isTouch and "Tap the laptop to write your first app." or "Click the laptop to write your first app." })
	local ok = Cine.play(shots, { fov = 60, hold = 0.4 })
	if ghost then
		-- fade it out as the camera arrives, so it never stands over the real lot
		task.spawn(function()
			local parts = ghost:GetChildren()
			for k = 0, 1, 0.05 do
				for _, c in ipairs(parts) do
					if c:IsA("BasePart") then c.Transparency = 0.5 + 0.5 * k end
				end
				task.wait(0.03)
			end
			ghost:Destroy()
		end)
	end
	local _ = ok
	lightTheLaptop(pf)
	task.spawn(function()
		-- the day cycle is 22 minutes for 24 hours (SkyClient): where the real sun is now
		local target = (realHour + (os.clock() - realAt) * 24 / (22 * 60)) % 24
		local delta = ((target - SHOW_HOUR + 12) % 24) - 12       -- the short way round the clock
		local t0 = os.clock()
		while os.clock() - t0 < 5 do
			local k = (os.clock() - t0) / 5
			k = 1 - (1 - k) ^ 3
			workspace:SetAttribute("SVClockOverride", (SHOW_HOUR + delta * k) % 24)
			task.wait(0.1)
		end
		workspace:SetAttribute("SVClockOverride", nil)
	end)
end

task.spawn(runIntro)
