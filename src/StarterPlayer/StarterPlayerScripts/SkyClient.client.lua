--[[
	SkyClient -- LocalScript in StarterPlayer -> StarterPlayerScripts (v3.4 W1).

	THE VALLEY'S DAY. A static 3pm under one skybox is a screenshot, not a
	place. This runs a 22-minute day on every client from the server clock
	(workspace:GetServerTimeNow(), so everyone shares the same sunset and
	nothing replicates):

	  06:30 -> 19:30   17 min   day, with a golden hour at each end
	  19:30 -> 05:00    4 min   night: the campuses light up, crickets
	  05:00 -> 06:30    1 min   dawn

	The sun follows Mountain View's real latitude (37.4 N). A colour grade
	(ColorCorrection) and the Atmosphere shift with the hour: warm haze by
	day, orange at golden hour, navy at night. At night every glass pane on
	every campus glows warm (Material Neon), street lamps light, and the
	Caltrain's windows glow (LifeClient reads workspace attribute SVNight).
	Night is short on purpose: it is the moment, not the mode.
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local DAY_FROM, DAY_TO, DAY_S = 6.5, 19.5, 1020
local NIGHT_TO, NIGHT_S = 29.0, 240            -- 19:30 -> 05:00 (wraps midnight)
local DAWN_S = 60                              -- 05:00 -> 06:30
local TOTAL = DAY_S + NIGHT_S + DAWN_S

local function clockAt(t)
	local x = t % TOTAL
	if x < DAY_S then return DAY_FROM + (DAY_TO - DAY_FROM) * x / DAY_S end
	x -= DAY_S
	if x < NIGHT_S then return (DAY_TO + (NIGHT_TO - DAY_TO) * x / NIGHT_S) % 24 end
	x -= NIGHT_S
	return 5.0 + 1.5 * x / DAWN_S
end

local function smooth(a, b, x)
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end
local function lerpC(a, b, t) return a:Lerp(b, math.clamp(t, 0, 1)) end

-- daylight 0..1 and golden-hour 0..1 from the hour
local function lightFactors(h)
	-- (Mountain View's sun drops behind the western hills around 18:00, so the
	-- golden hour peaks at 17:24 and the valley is in shade by 18:30)
	local day = smooth(5.2, 7.2, h) * (1 - smooth(18.2, 19.8, h))
	local golden = math.max(1 - math.abs(h - 17.4) / 1.3, 1 - math.abs(h - 7.0) / 1.2, 0)
	return day, golden * day
end

Lighting.GeographicLatitude = 37.4             -- Mountain View

local grade = Lighting:FindFirstChild("SVGrade") or Instance.new("ColorCorrectionEffect")
grade.Name = "SVGrade"
grade.Parent = Lighting
local rays = Lighting:FindFirstChild("SVRays") or Instance.new("SunRaysEffect")
rays.Name = "SVRays"
rays.Intensity = 0.04
rays.Spread = 0.7
rays.Parent = Lighting
-- v3.6 (PLAN v6 V6): the architect's-model cue. Everything within ~230 studs (your
-- whole campus) stays sharp; only the far valley and the ridges soften a little.
-- Roblox drops post effects at low graphics quality, so a phone that cannot
-- afford it does not pay for it.
local depth = Lighting:FindFirstChild("SVDepth") or Instance.new("DepthOfFieldEffect")
depth.Name = "SVDepth"
depth.FarIntensity = 0.12
depth.FocusDistance = 60
depth.InFocusRadius = 170
depth.NearIntensity = 0
depth.Parent = Lighting
-- v4.1: style B has no blur. The soft far distance was half of "the hills are
-- blurry"; faceted hills read by their edges, and blurred edges read as mush.
depth.Enabled = false

-- v4.1: the faceted clouds (ValleyGen.buildLowPoly, tag SVCloud) drift with the
-- wind, here on the client so nothing replicates. They wrap at the world edge.
do
	local CS = game:GetService("CollectionService")
	local DRIFT = Vector3.new(4, 0, -1.6)            -- studs a second, along GlobalWind
	local clouds = {}
	local function add(p) if p:IsA("BasePart") then table.insert(clouds, p) end end
	for _, p in ipairs(CS:GetTagged("SVCloud")) do add(p) end
	CS:GetInstanceAddedSignal("SVCloud"):Connect(add)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(1 / 15)
			local now = os.clock()
			local dt = math.min(now - last, 0.5)
			last = now
			local parts, cfs = {}, {}
			for i = #clouds, 1, -1 do
				local p = clouds[i]
				if not p.Parent then
					table.remove(clouds, i)
				else
					local c = p.CFrame + DRIFT * dt
					if c.X > 2400 then c -= Vector3.new(4800, 0, 0) end
					if c.Z < -2400 then c += Vector3.new(0, 0, 4800) end
					table.insert(parts, p)
					table.insert(cfs, c)
				end
			end
			if #parts > 0 then workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged) end
		end
	end)
end

-- the daytime skybox is a painted day; at night it goes away so the engine's
-- own night sky (dark, stars, moon) shows through
local sky = Lighting:FindFirstChildOfClass("Sky")
local SKY_FACES = { "SkyboxUp", "SkyboxDn", "SkyboxLf", "SkyboxRt", "SkyboxFt", "SkyboxBk" }
local daySky = {}
if sky then for _, f in ipairs(SKY_FACES) do daySky[f] = sky[f] end end
local skyIsNight = false
local function setNightSky(on)
	if not sky or skyIsNight == on then return end
	skyIsNight = on
	for _, f in ipairs(SKY_FACES) do sky[f] = on and "" or daySky[f] end
	sky.StarCount = on and 3000 or 0
end

--[[ NIGHT LIGHT (pass 6). The old street-lamp block looked for a Model named
	"Lamp". Nothing in this game has ever built one -- CampusArch, CampusHub and
	CampusDistricts all make loose parts -- so no street lamp has ever cast
	light and the forecourts, the park and the districts were pitch black after
	sunset while the buildings glowed.

	Every lamp head is tagged SVLamp now, and this lights the NEAREST ones to
	the camera, up to MAX_LIT. Capping by distance instead of lighting all 68 is
	what keeps this inside the phone budget however many lamps the campus grows:
	a light you cannot see costs the same as one you can. ]]
local CollectionService = game:GetService("CollectionService")
local MAX_LIT, LIT_RANGE = 24, 230
local glowing = {}
local lampLights = {}
local nightOn = false
local function setNight(on)
	if nightOn == on then return end
	nightOn = on
	workspace:SetAttribute("SVNight", on)       -- client-local: LifeClient lights the train
	local plots = workspace:FindFirstChild("SiliconValley") and workspace.SiliconValley:FindFirstChild("Plots")
	if on and plots then
		for _, d in ipairs(plots:GetDescendants()) do
			if d:IsA("BasePart") and d.Material == Enum.Material.Glass and d.Transparency < 0.99 then   -- v3.6: hidden collision glass stays hidden
				glowing[d] = { d.Color, d.Transparency }
				d.Material = Enum.Material.Neon
				d.Color = Color3.fromRGB(236, 168, 96)
				d.Transparency = math.max(0.3, d.Transparency * 0.6)
			end
		end
	else
		for p, v in pairs(glowing) do
			if p.Parent then p.Material = Enum.Material.Glass; p.Color = v[1]; p.Transparency = v[2] end
		end
		glowing = {}
		for head, l in pairs(lampLights) do
			if l.Parent then l:Destroy() end
		end
		lampLights = {}
	end
end

--[[ the lamps the camera can actually see. Runs twice a second (lamps do not
	move, and a player cannot cross 230 studs in half a second), and only while
	it is dark. The PointLight is parented to the head itself: no helper parts
	to leak if a plot is torn down under it. ]]
local lampTick = 0
local function updateLamps(dt)
	lampTick -= dt
	if lampTick > 0 then return end
	lampTick = 0.5
	if not nightOn then return end
	local eye = workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position
	if not eye then return end
	local near = {}
	for _, head in ipairs(CollectionService:GetTagged("SVLamp")) do
		if head.Parent then
			local d = (head.Position - eye).Magnitude
			if d < LIT_RANGE then table.insert(near, { head, d }) end
		end
	end
	table.sort(near, function(a, b) return a[2] < b[2] end)
	local keep = {}
	for i = 1, math.min(MAX_LIT, #near) do
		local head = near[i][1]
		keep[head] = true
		if not lampLights[head] or not lampLights[head].Parent then
			local l = Instance.new("PointLight")
			l.Color = Color3.fromRGB(255, 206, 142)
			l.Range = 34
			l.Brightness = 1.5
			l.Shadows = false
			l.Parent = head
			lampLights[head] = l
		end
	end
	for head, l in pairs(lampLights) do
		if not keep[head] then
			if l.Parent then l:Destroy() end
			lampLights[head] = nil
		end
	end
end
-- a building that rises at night joins the glow
task.spawn(function()
	local sv = workspace:WaitForChild("SiliconValley")
	local plots = sv:WaitForChild("Plots")
	plots.DescendantAdded:Connect(function(d)
		if nightOn and d:IsA("BasePart") then
			task.defer(function()
				if nightOn and d.Parent and d.Material == Enum.Material.Glass and d.Transparency < 0.99 then
					glowing[d] = { d.Color, d.Transparency }
					d.Material = Enum.Material.Neon
					d.Color = Color3.fromRGB(236, 168, 96)
					d.Transparency = math.max(0.3, d.Transparency * 0.6)
				end
			end)
		end
	end)
end)

-- sound: birds by day, crickets by night (both Roblox Pro Sound Effects)
local crickets = Instance.new("Sound")
crickets.Name = "ValleyCrickets"
crickets.SoundId = "rbxassetid://9112765304"   -- PSE Crickets Night 1, loop
crickets.Looped = true
crickets.Volume = 0
crickets.Parent = SoundService
crickets:Play()

-- v3.5 (ART.md): warm key, cool shadow. The old fill (128,132,140) lifted
-- every shadow to grey, which is most of why daylight read flat.
local DAY_AMB, NIGHT_AMB = Color3.fromRGB(80, 82, 94), Color3.fromRGB(36, 40, 62)
local DAY_OUT, NIGHT_OUT = Color3.fromRGB(108, 118, 144), Color3.fromRGB(54, 60, 92)
local DAY_SHIFT, GOLD_SHIFT = Color3.fromRGB(34, 20, 4), Color3.fromRGB(96, 52, 14)   -- warmth on sunlit faces
local DAY_TINT, GOLD_TINT, NIGHT_TINT = Color3.fromRGB(255, 250, 242), Color3.fromRGB(255, 238, 214), Color3.fromRGB(196, 206, 255)
local DAY_ATM, GOLD_ATM, NIGHT_ATM = Color3.fromRGB(214, 210, 200), Color3.fromRGB(230, 208, 174), Color3.fromRGB(42, 50, 82)
local DAY_DECAY, GOLD_DECAY, NIGHT_DECAY = Color3.fromRGB(140, 152, 172), Color3.fromRGB(200, 130, 96), Color3.fromRGB(20, 24, 42)

--[[ ============ THE DRAWN SUN AND MOON (v8) ============

	Why these are BillboardGuis and not Sky.SunTextureId.

	Measured 3 Oct, in game: the celestial-body path multiplies the texture up
	and clips it, so the COLOUR is thrown away and only the alpha survives. A
	test texture split into four quadrants at 18 / 28 / 40 / 55 percent of the
	target yellow rendered as the same pale cream in all four, and a 14px
	near-black outline vanished completely. Turning off Bloom, SunRays and
	Atmosphere.Glare changed nothing -- it is the sun shader, not the
	post-processing.

	So a drawn sun cannot be made that way: you get a silhouette and nothing
	else. A BillboardGui is UI. It renders at the exact colour with no lighting,
	no bloom and no tone mapping, which is the only way to get a flat fill with
	an outline around it.

	What this keeps from the old approach: the discs are placed along the REAL
	Lighting:GetSunDirection() / GetMoonDirection() each frame, so they still
	track across the sky, still set behind the hills, and still agree with the
	shadow direction. AlwaysOnTop is false, so the terrain occludes them on the
	way down instead of letting the sun float over a mountain.

	Anchored to the camera at a fixed distance, so there is no parallax as the
	player walks -- the sun behaves as if it were infinitely far away, which it
	is. Parented to CurrentCamera: client-only, never replicates, and goes away
	with the camera. ]]
local SUN_IMG = "rbxassetid://124848074435225"
local MOON_IMG = "rbxassetid://135660990906962"
local DISC_DIST = 1400          -- beyond every hill in the valley, inside the far plane
local SUN_DEG, MOON_DEG = 32, 17   -- the sun is meant to be a landmark you compose shots against

local function discStuds(deg)
	return 2 * DISC_DIST * math.tan(math.rad(deg) / 2)
end

local function makeDisc(name, image, deg)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(1, 1, 1)
	p.Transparency = 1
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.CastShadow, p.Locked = false, true
	p.Parent = workspace.CurrentCamera

	local bb = Instance.new("BillboardGui")
	bb.Name = "Disc"
	bb.Adornee = p
	bb.Size = UDim2.fromScale(discStuds(deg), discStuds(deg))
	bb.AlwaysOnTop = false        -- so the hills cut it off at sunset
	bb.LightInfluence = 0         -- exact colour, no lighting, no bloom
	bb.MaxDistance = math.huge
	bb.Parent = p

	local img = Instance.new("ImageLabel")
	img.Name = "Img"
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.Image = image
	img.Parent = bb
	return p, img
end

local sunPart, sunImg = makeDisc("SVSunDisc", SUN_IMG, SUN_DEG)
local moonPart, moonImg = makeDisc("SVMoonDisc", MOON_IMG, MOON_DEG)

RunService.RenderStepped:Connect(function()
	local cam = workspace.CurrentCamera
	if not cam or not sunPart.Parent then return end
	local o = cam.CFrame.Position
	local sd, md = Lighting:GetSunDirection(), Lighting:GetMoonDirection()
	sunPart.CFrame = CFrame.new(o + sd * DISC_DIST)
	moonPart.CFrame = CFrame.new(o + md * DISC_DIST)
	-- fade each out as it drops under the horizon, so neither pops
	sunImg.ImageTransparency = 1 - math.clamp((sd.Y + 0.09) / 0.12, 0, 1)
	moonImg.ImageTransparency = 1 - math.clamp((md.Y + 0.09) / 0.12, 0, 1)
end)

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	updateLamps(dt)
	acc += dt
	if acc < 0.25 then return end                 -- the sun moves slowly; 4 Hz is smooth
	acc = 0
	local h = clockAt(workspace:GetServerTimeNow())
	local ov = workspace:GetAttribute("SVClockOverride")      -- Studio test hook: preview any hour
	if type(ov) == "number" then h = ov end
	Lighting.ClockTime = h
	local day, golden = lightFactors(h)
	Lighting.Brightness = 0.6 + 1.7 * day
	Lighting.Ambient = lerpC(NIGHT_AMB, DAY_AMB, day)
	Lighting.OutdoorAmbient = lerpC(NIGHT_OUT, DAY_OUT, day)
	grade.TintColor = lerpC(lerpC(NIGHT_TINT, DAY_TINT, day), GOLD_TINT, golden)
	grade.Saturation = 0.02 + 0.1 * day
	grade.Contrast = 0.08 + 0.04 * golden
	Lighting.ColorShift_Top = lerpC(lerpC(Color3.new(0, 0, 0), DAY_SHIFT, day), GOLD_SHIFT, golden)
	rays.Intensity = 0.02 + 0.08 * golden
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if atm then
		atm.Color = lerpC(lerpC(NIGHT_ATM, DAY_ATM, day), GOLD_ATM, golden * 0.8)
		atm.Decay = lerpC(lerpC(NIGHT_DECAY, DAY_DECAY, day), GOLD_DECAY, golden * 0.8)
		atm.Glare = 0.2 + 0.6 * golden
	end
	local isNight = day < 0.35
	setNight(isNight)
	setNightSky(day < 0.15)
	crickets.Volume = 0.25 * (1 - day)
	local birds = SoundService:FindFirstChild("ValleyBirds")
	if birds then birds.Volume = 0.22 * day end
end)
