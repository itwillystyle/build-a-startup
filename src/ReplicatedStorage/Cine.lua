--[[
	Cine (v4.0) -- ReplicatedStorage ModuleScript: the game's camera cinematics.

	One tool for every "moment": the first-join flyover, the apartment move-in,
	the new-car reveal, the HQ level-up. A shot list is a list of camera
	positions and look-at points; the camera flies a Catmull-Rom spline through
	them (no stop-start between shots, which is what made the old intro read as
	a slideshow), eased in and out, with letterbox bars and a title card.

	  Cine.play(shots, opts)   shots = { { pos, look, t (seconds to get here), title, sub }, ... }
	                           opts  = { letterbox = true, skippable = true, fov = 60 }
	  Cine.fade(toBlack, seconds)
	  Cine.busy()              true while a cinematic owns the camera

	Rules kept from the card shop and the intro: never restore a Scriptable
	camera (always hand back Custom + the humanoid); touch skips only with the
	visible SKIP button (a drag is the phone camera); nothing blocks input.
]]
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")

local Cine = {}
local player = Players.LocalPlayer
local UIKit = require(RS:WaitForChild("UIKit"))
local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local gui, topBar, bottomBar, fade, card, titleL, subL, skipBtn
local playing = false
local skipped = false

local function ensure()
	if gui and gui.Parent then return end
	gui = Instance.new("ScreenGui")
	gui.Name = "Cinema"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30
	gui.Parent = player:WaitForChild("PlayerGui")
	local function bar(name, anchorY)
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundColor3 = Color3.fromRGB(8, 9, 12)
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0, anchorY)
		f.Position = UDim2.new(0, 0, anchorY, 0)
		f.Size = UDim2.new(1, 0, 0, 0)
		f.Parent = gui
		return f
	end
	topBar = bar("Top", 0)
	bottomBar = bar("Bottom", 1)
	fade = Instance.new("Frame")
	fade.Name = "Fade"
	fade.BackgroundColor3 = Color3.fromRGB(8, 9, 12)
	fade.BackgroundTransparency = 1
	fade.BorderSizePixel = 0
	fade.Size = UDim2.new(1, 0, 1, 0)
	fade.ZIndex = 20
	fade.Parent = gui
	card = Instance.new("Frame")
	card.Name = "Card"
	card.BackgroundTransparency = 1
	card.AnchorPoint = Vector2.new(0, 1)
	card.Position = UDim2.new(0, 48, 1, -26)
	card.Size = UDim2.new(0.7, 0, 0, 96)
	card.ZIndex = 5
	card.Parent = gui
	titleL = UIKit.outlined(card, "", 44, Color3.fromRGB(255, 255, 255), {
		Name = "Title", Size = UDim2.new(1, 0, 0, 52), Position = UDim2.new(0, 0, 0, 0), ZIndex = 6,
	})
	subL = UIKit.label(card, "", 20, Color3.fromRGB(236, 236, 230), {
		Name = "Sub", Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 2, 0, 54), ZIndex = 6, TextWrapped = true,
	}, UIKit.HEAD)
	subL.TextStrokeTransparency = 0.5
	skipBtn = UIKit.button(gui, "SKIP", Color3.fromRGB(240, 240, 236), {
		Name = "Skip", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -22), Size = UDim2.new(0, 104, 0, 44), Visible = false, ZIndex = 8,
	}, { textSize = 18, dark = true })
	skipBtn.MouseButton1Click:Connect(function() skipped = true end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not playing or isTouch or processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Keyboard then
			skipped = true
		end
	end)
end

function Cine.busy() return playing end

function Cine.fade(toBlack, seconds)
	ensure()
	TweenService:Create(fade, TweenInfo.new(seconds or 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = toBlack and 0 or 1 }):Play()
end

local function letterbox(on, seconds)
	local vp = workspace.CurrentCamera.ViewportSize
	local h = on and math.floor(vp.Y * 0.1) or 0
	for _, b in ipairs({ topBar, bottomBar }) do
		TweenService:Create(b, TweenInfo.new(seconds or 0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Size = UDim2.new(1, 0, 0, h) }):Play()
	end
end

local shownTitle
local function caption(title, sub)
	if title == shownTitle then return end
	shownTitle = title
	for _, l in ipairs({ titleL, subL }) do
		TweenService:Create(l, TweenInfo.new(0.2), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end
	local st = titleL:FindFirstChildOfClass("UIStroke")
	if st then TweenService:Create(st, TweenInfo.new(0.2), { Transparency = 1 }):Play() end
	task.delay(0.2, function()
		if shownTitle ~= title then return end
		titleL.Text = title or ""
		subL.Text = sub or ""
		titleL.Position = UDim2.new(0, 0, 0, 10)
		TweenService:Create(titleL, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ TextTransparency = 0, Position = UDim2.new(0, 0, 0, 0) }):Play()
		local st2 = titleL:FindFirstChildOfClass("UIStroke")
		if st2 then TweenService:Create(st2, TweenInfo.new(0.5), { Transparency = 0 }):Play() end
		TweenService:Create(subL, TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ TextTransparency = 0, TextStrokeTransparency = 0.5 }):Play()
	end)
end

-- Catmull-Rom through p0..p3 at u (0..1 between p1 and p2)
local function cr(p0, p1, p2, p3, u)
	local u2, u3 = u * u, u * u * u
	return 0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u2 + (-p0 + 3 * p1 - 3 * p2 + p3) * u3)
end

local function handBack()
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then cam.CameraSubject = hum end
end
Cine.handBack = handBack

function Cine.play(shots, opts)
	opts = opts or {}
	ensure()
	if playing or #shots < 2 then return false end
	playing = true
	skipped = false
	shownTitle = nil
	-- the HUD, any open menu and every E prompt step aside for the shot (restored after)
	local PPS = game:GetService("ProximityPromptService")
	local promptsWere = PPS.Enabled
	PPS.Enabled = false
	local hidden = {}
	for _, g in ipairs(player.PlayerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled and g ~= gui and g.Name ~= "LiftFade" then
			g.Enabled = false
			table.insert(hidden, g)
		end
	end
	local cam = workspace.CurrentCamera
	local oldFov = cam.FieldOfView
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = opts.fov or 60
	if opts.letterbox ~= false then letterbox(true) end
	skipBtn.Visible = opts.skippable ~= false
	-- cumulative times
	local times = { 0 }
	for i = 2, #shots do times[i] = times[i - 1] + (shots[i].t or 1.5) end
	local total = times[#shots]
	local P, L = {}, {}
	for i, s in ipairs(shots) do P[i] = s.pos; L[i] = s.look end
	local function at(list, i) return list[math.clamp(i, 1, #list)] end
	local t0 = os.clock()
	local lastTitleIdx = 0
	while true do
		if skipped and opts.skippable ~= false then break end
		local raw = math.clamp((os.clock() - t0) / total, 0, 1)
		-- ease the whole flight in and out (the middle keeps its pace)
		local e = raw < 0.5 and (4 * raw ^ 3) * 0.5 + raw * 0.5 or (1 - ((-2 * raw + 2) ^ 3) / 2) * 0.5 + raw * 0.5
		local tt = e * total
		local seg = 1
		while seg < #shots - 1 and tt > times[seg + 1] do seg += 1 end
		local span = times[seg + 1] - times[seg]
		local u = span > 0 and math.clamp((tt - times[seg]) / span, 0, 1) or 1
		local pos = cr(at(P, seg - 1), at(P, seg), at(P, seg + 1), at(P, seg + 2), u)
		local look = cr(at(L, seg - 1), at(L, seg), at(L, seg + 1), at(L, seg + 2), u)
		cam.CFrame = CFrame.lookAt(pos, look)
		-- captions: a shot's title shows from the moment the camera heads for it
		local idx = math.min(#shots, seg + (u > 0.15 and 1 or 0))
		if idx ~= lastTitleIdx then
			lastTitleIdx = idx
			local s = shots[idx]
			if s.title then caption(s.title, s.sub) end
		end
		if raw >= 1 then break end
		RunService.RenderStepped:Wait()
	end
	if opts.hold and not skipped then task.wait(opts.hold) end
	caption(nil, nil)
	letterbox(false, 0.35)
	skipBtn.Visible = false
	cam.FieldOfView = oldFov
	if opts.handBack ~= false then handBack() end
	-- menus stay closed (they were for the moment before); the HUD comes back
	for _, g in ipairs(hidden) do
		if g.Parent and not table.find(UIKit.MENUS or {}, g.Name) then g.Enabled = true end
	end
	PPS.Enabled = promptsWere
	playing = false
	return not skipped
end

return Cine
