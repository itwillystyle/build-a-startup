--[[
	UIKit -- ModuleScript in ReplicatedStorage.

	ONE look for every screen. Zero uploads: Frames, UICorner, UIStroke,
	UIGradient and two built-in fonts. This is literally what Sell Lemons'
	HUD is made of. Every client script builds through these helpers so the
	game stops looking like six different people drew it.

	Rules baked in:
	  - headings and numbers: FredokaOne (the tycoon font)
	  - body: Gotham
	  - buttons are CHUNKY: 3px darker bottom edge, stroke, 12px radius
	  - touch targets never under 44px tall
	  - one palette, below
]]

local UIKit = {}

--[[ v3.1 ONE PALETTE (the 25 Sep review counted three greens, two golds,
three greys and a dark panel base redefined in five files). Every client
reads colours from here; nothing defines its own. ]]
UIKit.INK = Color3.fromRGB(20, 22, 30)          -- outlines, dark text on light
UIKit.PANEL = Color3.fromRGB(30, 34, 46)
UIKit.LINE = Color3.fromRGB(58, 64, 84)
UIKit.TEXT = Color3.fromRGB(255, 255, 255)
UIKit.MUTED = Color3.fromRGB(160, 170, 190)
UIKit.GOLD = Color3.fromRGB(255, 208, 70)
UIKit.GREEN = Color3.fromRGB(70, 215, 110)
UIKit.RED = Color3.fromRGB(240, 80, 80)
UIKit.BLUE = Color3.fromRGB(70, 150, 255)
UIKit.ORANGE = Color3.fromRGB(255, 140, 60)     -- destructive / reset actions
UIKit.SURFACE = Color3.fromRGB(246, 247, 250)   -- menus: light and solid (the dark gold-rim panels were the anti-reference)
UIKit.SURFACE_2 = Color3.fromRGB(232, 236, 243) -- rows and cells inside a menu

--[[
	v3.0 HUD RULE, from gameplay frames (PLAN-v5-tizzy section 4):
	  - small HUD cards (objective, product bar, toasts, reveals) are WHITE
	    with dark text -- Run a Restaurant!'s level-up and quest cards
	  - money is big green OUTLINED text with no box -- Steal An Egg
	  - big menus (build catalog, pickers, the Index) stay dark translucent --
	    Run a Restaurant!'s build catalog
	  - nothing dark sits at top-centre
]]
UIKit.CARD = Color3.fromRGB(255, 255, 255)
UIKit.CARD_LINE = Color3.fromRGB(214, 219, 228)
UIKit.CARD_TEXT = Color3.fromRGB(28, 32, 42)
UIKit.CARD_MUTED = Color3.fromRGB(110, 118, 134)

UIKit.HEAD = Enum.Font.FredokaOne
UIKit.BODY = Enum.Font.Gotham
UIKit.BOLD = Enum.Font.GothamBold

local function darker(c, k)
	local h, s, v = c:ToHSV()
	return Color3.fromHSV(h, s, v * (k or 0.7))
end
UIKit.darker = darker

local function apply(inst, props)
	for k, v in pairs(props or {}) do inst[k] = v end
end

-- a rounded dark panel with a stroke
function UIKit.panel(parent, props, opts)
	opts = opts or {}
	local f = Instance.new("Frame")
	f.BackgroundColor3 = opts.color or UIKit.PANEL
	f.BorderSizePixel = 0
	apply(f, props)
	f.Parent = parent
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, opts.radius or 14)
	local st = Instance.new("UIStroke", f)
	st.Color = opts.stroke or UIKit.LINE
	st.Thickness = opts.strokeWidth or 2
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return f
end

-- a chunky cartoon button: bright face, darker bottom lip, dark stroke
function UIKit.button(parent, text, color, props, opts)
	opts = opts or {}
	color = color or UIKit.GOLD
	local b = Instance.new("TextButton")
	b.Text = ""
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	apply(b, props)
	b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, opts.radius or 12)
	local st = Instance.new("UIStroke", b)
	st.Color = darker(color, 0.45)
	st.Thickness = 2.5
	-- bottom lip: the thing that makes it read as pressable
	local lip = Instance.new("Frame")
	lip.Name = "Lip"
	lip.AnchorPoint = Vector2.new(0, 1)
	lip.Position = UDim2.new(0, 0, 1, 0)
	lip.Size = UDim2.new(1, 0, 0, 5)
	lip.BackgroundColor3 = darker(color, 0.6)
	lip.BorderSizePixel = 0
	lip.ZIndex = b.ZIndex
	lip.Parent = b
	Instance.new("UICorner", lip).CornerRadius = UDim.new(0, opts.radius or 12)
	local t = Instance.new("TextLabel")
	t.Name = "Label"
	t.Size = UDim2.new(1, -12, 1, -5)
	t.Position = UDim2.new(0, 6, 0, 0)
	t.BackgroundTransparency = 1
	t.Text = text
	t.Font = UIKit.HEAD
	t.TextSize = opts.textSize or 20
	t.TextColor3 = opts.textColor or (opts.dark and UIKit.INK or UIKit.TEXT)
	t.TextStrokeTransparency = opts.dark and 1 or 0.4
	t.TextStrokeColor3 = darker(color, 0.35)
	t.TextScaled = opts.scaled or false
	t.ZIndex = b.ZIndex + 1
	t.Parent = b
	-- press feedback: darken, squish, click (the same on every button in the game)
	local sc = Instance.new("UIScale")
	sc.Parent = b
	local TS = game:GetService("TweenService")
	--[[ v4.0 MOTION (his note: "revamp the ui click/scale animations"). Every
	button: hover lifts it (desktop), a press squashes it fast, a release pops it
	past full size and settles (0.9 -> 1.07 -> 1: the two-stage spring the top
	games use), and a rendered icon on it tips and rights itself. ]]
	local UIS = game:GetService("UserInputService")
	local pressed, hovered = false, false
	local seq = 0
	local function to(scale, t, style)
		TS:Create(sc, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = scale }):Play()
	end
	local function release()
		seq += 1
		local mine = seq
		to(1.07, 0.09)
		task.delay(0.09, function() if seq == mine then to(hovered and 1.04 or 1, 0.16, Enum.EasingStyle.Sine) end end)
	end
	local function iconTip(down)
		local ic = b:FindFirstChild("Icon")
		if ic and ic:IsA("ImageLabel") then
			TS:Create(ic, TweenInfo.new(down and 0.07 or 0.3, down and Enum.EasingStyle.Quad or Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Rotation = down and -9 or 0 }):Play()
		end
	end
	b.MouseEnter:Connect(function()
		if UIS.TouchEnabled and not UIS.MouseEnabled then return end
		hovered = true
		if not pressed then to(1.04, 0.12) end
	end)
	b.MouseButton1Down:Connect(function()
		pressed = true
		seq += 1
		b.BackgroundColor3 = darker(b:GetAttribute("Face") or color, 0.85)
		to(0.9, 0.06)
		iconTip(true)
		if not opts.silent then UIKit.sfx("tap") end
	end)
	b.MouseButton1Up:Connect(function()
		pressed = false
		b.BackgroundColor3 = b:GetAttribute("Face") or color
		release()
		iconTip(false)
	end)
	b.MouseLeave:Connect(function()
		hovered = false
		b.BackgroundColor3 = b:GetAttribute("Face") or color
		if pressed then pressed = false; iconTip(false) end
		seq += 1
		to(1, 0.14)
	end)
	return b, t
end

function UIKit.setButtonColor(b, color)
	b:SetAttribute("Face", color)
	b.BackgroundColor3 = color
	local st = b:FindFirstChildOfClass("UIStroke")
	if st then st.Color = darker(color, 0.45) end
	local lip = b:FindFirstChild("Lip")
	if lip then lip.BackgroundColor3 = darker(color, 0.6) end
	local t = b:FindFirstChild("Label")
	if t then t.TextStrokeColor3 = darker(color, 0.35) end
end

function UIKit.label(parent, text, size, color, props, font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size or 16
	l.TextColor3 = color or UIKit.TEXT
	l.Font = font or UIKit.BODY
	l.TextXAlignment = Enum.TextXAlignment.Left
	apply(l, props)
	l.Parent = parent
	return l
end

-- a white HUD card (see the v3.0 rule above)
function UIKit.card(parent, props, opts)
	opts = opts or {}
	return UIKit.panel(parent, props, { radius = opts.radius or 14, color = UIKit.CARD,
		stroke = opts.stroke or UIKit.CARD_LINE, strokeWidth = opts.strokeWidth or 1.5 })
end

-- big outlined display text (money): a real outline via UIStroke, not the thin TextStroke
function UIKit.outlined(parent, text, size, color, props)
	local l = UIKit.label(parent, text, size, color, props, UIKit.HEAD)
	l.TextStrokeTransparency = 1
	local st = Instance.new("UIStroke")
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	st.Color = UIKit.INK
	st.Thickness = math.max(2, math.floor((size or 20) / 10))
	st.Parent = l
	return l
end

-- heading text with the dark outline every tycoon uses
function UIKit.heading(parent, text, size, color, props)
	local l = UIKit.label(parent, text, size or 22, color or UIKit.TEXT, props, UIKit.HEAD)
	l.TextStrokeTransparency = 0.5
	l.TextStrokeColor3 = UIKit.INK
	return l
end

-- a pill with a coloured dot on the left (status lines, objectives)
function UIKit.pill(parent, props, opts)
	opts = opts or {}
	local p = UIKit.panel(parent, props, { radius = 999, stroke = opts.stroke or UIKit.GOLD, color = opts.color or UIKit.INK })
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.Size = UDim2.new(0, 14, 0, 14)
	dot.Position = UDim2.new(0, 16, 0.5, -7)
	dot.BackgroundColor3 = opts.dot or UIKit.GOLD
	dot.BorderSizePixel = 0
	dot.Parent = p
	Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
	local t = UIKit.heading(p, "", opts.textSize or 20, UIKit.TEXT, {
		Name = "Text", Position = UDim2.new(0, 40, 0, 0), Size = UDim2.new(1, -56, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	return p, t, dot
end

--[[
	ICONS (v2.8, step 3). Kenney "Game Icons" (CC0, kenney.nl), white 100px
	PNGs uploaded once; ImageColor3 tints them. "code" is a </> glyph drawn
	in the same stroke weight (Kenney has no code icon). One table, so a
	re-upload only changes ids here.
]]
UIKit.ICON = {
	build = "rbxassetid://123677578989129",     -- wrench
	musicOn = "rbxassetid://80674448407426",
	musicOff = "rbxassetid://94711642746808",
	star = "rbxassetid://91998219936128",
	trophy = "rbxassetid://121555741244101",
	team = "rbxassetid://82984031288077",       -- multiplayer
	person = "rbxassetid://125155152534934",    -- singleplayer
	target = "rbxassetid://105545446030983",
	up = "rbxassetid://119157825169334",
	alert = "rbxassetid://115052299831748",     -- exclamation
	check = "rbxassetid://92534747075776",
	cross = "rbxassetid://131921906660063",
	cart = "rbxassetid://128814542955789",
	gear = "rbxassetid://98392083351485",
	home = "rbxassetid://81179302514296",
	lock = "rbxassetid://117054030344795",
	plus = "rbxassetid://102384871102041",
	fast = "rbxassetid://98091498313961",
	code = "rbxassetid://76598832335621",
	rocket = "rbxassetid://87541273840200",     -- drawn to match (Kenney has no rocket)
	grid = "rbxassetid://111146043853925",      -- menuGrid: the Talent Index
	-- v3.1 (Kenney Game Icons, uploaded 25 Sep): one meaning per icon
	phone = "rbxassetid://112985130462169",     -- SALES
	zoom = "rbxassetid://122906407559312",      -- RESEARCHER
	contrast = "rbxassetid://93921338238935",   -- DESIGNER
	trash = "rbxassetid://94616352843234",      -- delete
	medal = "rbxassetid://121960760283695",     -- daily reward
	info = "rbxassetid://74390485575597",       -- hints
	bag = "rbxassetid://98865631824634",        -- v3.2 (Kenney shoppingBasket, uploaded 25 Sep): the BAG
}

-- the Index row icon for each role (engineer = code, recruiter = people)
UIKit.ROLE_ICON = { engineer = "code", designer = "contrast", sales = "phone", recruiter = "team", research = "zoom" }

--[[ v3.6 PLAN v6 V8: full-colour icons rendered in Blender from the game's own
models (blender/icons.py + icons_post.py): one light rig (warm key upper left,
cool rim), one clay style, a dark sticker outline so they read on any button
colour at 45 px. Keyed like ICON; a button whose key has ART shows it instead
of the flat white Kenney glyph (the "2019" tell ART.md names). ]]
UIKit.ART = {
	phone = "rbxassetid://128232440721885",
	bag = "rbxassetid://90659729692571",
	grid = "rbxassetid://133698283368126",     -- INDEX: fanned ID badges
	home = "rbxassetid://116370509300998",     -- DECOR: a potted plant (decor = vibe)
	musicOn = "rbxassetid://96665124039903",   -- headphones
	code = "rbxassetid://89647676644335",      -- WRITE CODE: a laptop showing </>
	rocket = "rbxassetid://96729487615613",    -- LAUNCH: the game's own rocket
	target = "rbxassetid://109948464998235",   -- the quest card
	coin = "rbxassetid://89306433625572",      -- the money counter
	-- v4.0: one per objective type (the quest card draws the goal's own icon)
	hire = "rbxassetid://101369288283742",
	hq = "rbxassetid://112919371322873",
	key = "rbxassetid://120031551852395",       -- the apartment
	car = "rbxassetid://80393195262605",
	office = "rbxassetid://111184319717430",
	studio = "rbxassetid://124278708700130",
	cafe = "rbxassetid://85094953360524",
	servers = "rbxassetid://85225022240505",
	check = "rbxassetid://73092520537968",
}

-- a rendered icon (never tinted: it carries its own colour); falls back to the glyph
function UIKit.art(parent, key, size, props)
	if not UIKit.ART[key] then return UIKit.icon(parent, key, size, nil, props) end
	local i = Instance.new("ImageLabel")
	i.Name = "Icon"
	i.BackgroundTransparency = 1
	i.Image = UIKit.ART[key]
	i.ImageColor3 = Color3.new(1, 1, 1)
	i.ScaleType = Enum.ScaleType.Fit
	i.Size = UDim2.new(0, size, 0, size)
	apply(i, props)
	i.Parent = parent
	return i
end

function UIKit.icon(parent, key, size, color, props)
	local i = Instance.new("ImageLabel")
	i.Name = "Icon"
	i.BackgroundTransparency = 1
	i.Image = UIKit.ICON[key] or key
	i.ImageColor3 = color or UIKit.TEXT
	i.ScaleType = Enum.ScaleType.Fit
	i.Size = UDim2.new(0, size or 28, 0, size or 28)
	apply(i, props)
	i.Parent = parent
	return i
end

-- a chunky square button: icon on top, one short word under it
function UIKit.iconButton(parent, key, caption, color, props, opts)
	opts = opts or {}
	local b, t = UIKit.button(parent, caption or "", color, props, opts)
	local ink = opts.dark and UIKit.INK or UIKit.TEXT
	local captioned = caption and caption ~= ""
	local ic
	if UIKit.ART[key] and not opts.glyph then
		-- v3.6: the rendered icon, bigger than the glyph and popping 9 px above the
		-- button's top edge like a sticker (Run a Restaurant!'s rail does the same)
		ic = UIKit.art(b, key, math.floor((opts.iconSize or 30) * 1.6), {
			AnchorPoint = Vector2.new(0.5, captioned and 0 or 0.5),
			Position = captioned and UDim2.new(0.5, 0, 0, -9) or UDim2.new(0.5, 0, 0.5, -2),
			ZIndex = b.ZIndex + 1,
		})
	else
		ic = UIKit.icon(b, key, opts.iconSize or 30, ink, {
			AnchorPoint = Vector2.new(0.5, captioned and 0 or 0.5),
			Position = captioned and UDim2.new(0.5, 0, 0, 7) or UDim2.new(0.5, 0, 0.5, -2),
			ZIndex = b.ZIndex + 1,
		})
	end
	if caption and caption ~= "" then
		t.AnchorPoint = Vector2.new(0.5, 1)
		t.Position = UDim2.new(0.5, 0, 1, -8)
		t.Size = UDim2.new(1, -6, 0, 16)
		t.TextSize = opts.captionSize or 14
		t.TextXAlignment = Enum.TextXAlignment.Center
	end
	return b, t, ic
end

--[[
	THE LEFT RAIL (v3.0). Run a Restaurant! and Steal An Egg both stack their
	few buttons in one column on the left edge. Every script that owns a
	button parents it here with a LayoutOrder (BUILD 1, INDEX 2, MUSIC 3); a
	hidden button takes no space, so nothing has to "dock" when another is
	not unlocked yet.
]]
-- v3.2: four rail buttons (PHONE, BAG, INDEX, DECOR) must fit a 390-tall
-- phone screen from y 64: 4 x (66 + 8) = 296
UIKit.RAIL = 66

function UIKit.rail()
	local pg = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	local g = pg:FindFirstChild("Rail")
	if not g then
		g = Instance.new("ScreenGui")
		g.Name = "Rail"
		g.ResetOnSpawn = false
		g.IgnoreGuiInset = true
		g.DisplayOrder = 5
		UIKit.safe(g)
		g.Parent = pg
		local f = Instance.new("Frame")
		f.Name = "Column"
		f.BackgroundTransparency = 1
		f.Position = UDim2.new(0, 12, 0, 64)
		f.Size = UDim2.new(0, 90, 1, -76)
		f.Parent = g
		local l = Instance.new("UIListLayout")
		l.Padding = UDim.new(0, 8)
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Parent = f
	end
	return g:WaitForChild("Column")
end

-- a red count badge on a button's top-right corner (both references use one)
function UIKit.badge(button)
	local b = Instance.new("Frame")
	b.Name = "Badge"
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = UDim2.new(1, -4, 0, 4)
	b.Size = UDim2.new(0, 24, 0, 24)
	b.BackgroundColor3 = UIKit.RED
	b.BorderSizePixel = 0
	b.Visible = false
	b.ZIndex = button.ZIndex + 5
	b.Parent = button
	Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
	local st = Instance.new("UIStroke", b)
	st.Color = Color3.new(1, 1, 1)
	st.Thickness = 2
	local t = UIKit.heading(b, "", 14, UIKit.TEXT, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 1, ZIndex = button.ZIndex + 6 })
	return b, t
end

-- a reward that pops out of a HUD element and floats away (paydays, sales)
function UIKit.popReward(parent, text, at, color)
	local TweenService = game:GetService("TweenService")
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = at
	l.Size = UDim2.new(0, 240, 0, 40)
	l.Font = UIKit.HEAD
	l.TextSize = 32
	l.Text = text
	l.TextColor3 = color or UIKit.GOLD
	l.TextStrokeColor3 = UIKit.INK
	l.TextStrokeTransparency = 0.2
	l.ZIndex = 20
	l.Parent = parent
	local sc = Instance.new("UIScale")
	sc.Scale = 0.3
	sc.Parent = l
	TweenService:Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	-- coins burst out of the same point
	for k = 1, 8 do
		local c = Instance.new("Frame")
		c.AnchorPoint = Vector2.new(0.5, 0.5)
		c.Position = at
		c.Size = UDim2.new(0, 12, 0, 12)
		c.BackgroundColor3 = UIKit.GOLD
		c.BorderSizePixel = 0
		c.ZIndex = 19
		c.Parent = parent
		Instance.new("UICorner", c).CornerRadius = UDim.new(1, 0)
		local st = Instance.new("UIStroke", c)
		st.Color = darker(UIKit.GOLD, 0.55)
		st.Thickness = 1.5
		local a = (k / 8) * math.pi * 2 + math.random() * 0.4
		local r = 70 + math.random() * 40
		local goal = at + UDim2.new(0, math.cos(a) * r, 0, math.sin(a) * r * 0.6)
		TweenService:Create(c, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = goal, BackgroundTransparency = 1 }):Play()
		TweenService:Create(st, TweenInfo.new(0.55), { Transparency = 1 }):Play()
		task.delay(0.6, function() c:Destroy() end)
	end
	task.delay(0.55, function()
		TweenService:Create(l, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = at - UDim2.new(0, 0, 0, 46), TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	task.delay(1.5, function() l:Destroy() end)
end

-- money formatting, one place
-- v3.1: ONE format everywhere (the build picker said "$1.5K" beside a HUD
-- "$2279"). Under 10K the exact number with a comma, so early +$5 taps stay
-- visible; above it one decimal, a trailing ".0" dropped ("$40K").
function UIKit.money(n)
	n = math.floor(tonumber(n) or 0)
	local function short(v, suf)
		local t = string.format("%.1f", v)
		if t:sub(-2) == ".0" then t = t:sub(1, -3) end
		return "$" .. t .. suf
	end
	if n >= 1e12 then return short(n / 1e12, "T") end
	if n >= 1e9 then return short(n / 1e9, "B") end
	if n >= 1e6 then return short(n / 1e6, "M") end
	if n >= 1e4 then return short(n / 1e3, "K") end
	local str = tostring(n)
	if n >= 1000 then str = str:sub(1, -4) .. "," .. str:sub(-3) end
	return "$" .. str
end

-- ============ SOUND (v3.1) ============
-- Every id below was preload-checked in Studio on 25 Sep (a bad id plays
-- silence, not an error). Engine sounds and licensed APM / Pro Sound Effects
-- only: no ripped game audio on a place that earns.
UIKit.SOUNDS = {
	tap = { "rbxasset://sounds/clickfast.wav", 0.35 },
	ding = { "rbxasset://sounds/electronicpingshort.wav", 0.4 },
	thunk = { "rbxasset://sounds/switch.wav", 0.5 },
	coins = { "rbxassetid://9113849583", 0.55 },           -- PSE Coin Throws 2, 2.2 s
	levelup = { "rbxassetid://1840076509", 0.6 },          -- APM Through the Roof (sting), 2.3 s
	star = { "rbxassetid://9043512321", 0.6 },             -- APM Mystery Mayhem (sting a), 2.5 s
	genius = { "rbxassetid://9045808811", 0.6 },           -- APM We Good (sting), 3.1 s
	unicorn = { "rbxassetid://92456794490177", 0.6 },      -- APM Go Hard Win Big (sting), 5.0 s
	rebirth = { "rbxassetid://1841980129", 0.6 },          -- APM Gonna Win (sting a), 5.4 s
}
local soundCache = {}
function UIKit.sfx(key, pitch, volume)
	local def = UIKit.SOUNDS[key]
	if not def then return end
	local SoundService = game:GetService("SoundService")
	local s = soundCache[key]
	if not s then
		s = Instance.new("Sound")
		s.Name = "UI_" .. key
		s.SoundId = def[1]
		s.Parent = SoundService
		soundCache[key] = s
	end
	local p = s:Clone()
	p.Volume = volume or def[2]
	p.PlaybackSpeed = pitch or 1
	p.Parent = SoundService
	p:Play()
	game:GetService("Debris"):AddItem(p, 6)
end

-- ============ LAYOUT (v3.1) ============
-- phone notches: HUD guis keep out of the device's unsafe area
function UIKit.safe(gui)
	pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)
	return gui
end

--[[ THE RIGHT COLUMN. The objective and the product card were separate
screens that overlapped at phone widths (review: strip x 137-577 over the
card at x 489-699, same DisplayOrder, undefined order). Now they are rows of
ONE vertical list: whatever is visible stacks, and nothing can overlap. ]]
function UIKit.column()
	local pg = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	local g = pg:FindFirstChild("RightColumn")
	if not g then
		g = Instance.new("ScreenGui")
		g.Name = "RightColumn"
		g.ResetOnSpawn = false
		g.IgnoreGuiInset = true
		g.DisplayOrder = 6
		UIKit.safe(g)
		g.Parent = pg
		local f = Instance.new("Frame")
		f.Name = "Column"
		f.BackgroundTransparency = 1
		f.AnchorPoint = Vector2.new(1, 0)
		f.Position = UDim2.new(1, -12, 0, 60)
		f.Size = UDim2.new(0, 250, 1, -200)
		f.Parent = g
		local l = Instance.new("UIListLayout")
		l.Padding = UDim.new(0, 8)
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.HorizontalAlignment = Enum.HorizontalAlignment.Right
		l.Parent = f
		-- never wider than a third of the screen, so the money always has room
		local cam = workspace.CurrentCamera
		local function fit() f.Size = UDim2.new(0, math.clamp(math.floor(cam.ViewportSize.X * 0.34), 200, 260), 1, -200) end
		fit()
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
	return g:WaitForChild("Column")
end

--[[ A MENU: light, solid, a coloured header bar and a round close button.
It replaces the dark translucent gold-rim panels (the review's
anti-reference: build picker, name box, Index, catalog, intro). Returns
panel, body (content area under the header), close button, title. ]]
function UIKit.menu(parent, title, accent, props, opts)
	opts = opts or {}
	accent = accent or UIKit.BLUE
	local HEAD_H = opts.headerHeight or 48
	local f = Instance.new("Frame")
	f.BackgroundColor3 = UIKit.SURFACE
	f.BorderSizePixel = 0
	apply(f, props)
	f.Parent = parent
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 16)
	local st = Instance.new("UIStroke", f)
	st.Color = darker(accent, 0.55)
	st.Thickness = 3
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local head = Instance.new("Frame")
	head.Name = "Header"
	head.BackgroundColor3 = accent
	head.BorderSizePixel = 0
	head.Size = UDim2.new(1, 0, 0, HEAD_H)
	head.Parent = f
	Instance.new("UICorner", head).CornerRadius = UDim.new(0, 16)
	local sq = Instance.new("Frame")          -- square off the header's bottom corners
	sq.BackgroundColor3 = accent
	sq.BorderSizePixel = 0
	sq.AnchorPoint = Vector2.new(0, 1)
	sq.Position = UDim2.new(0, 0, 1, 0)
	sq.Size = UDim2.new(1, 0, 0, 16)
	sq.Parent = head
	local t = UIKit.label(head, title or "", 24, UIKit.TEXT, {
		Name = "Title", Position = UDim2.new(0, 18, 0, 0), Size = UDim2.new(1, -80, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 2,
	}, UIKit.HEAD)
	t.TextStrokeTransparency = 0.3
	t.TextStrokeColor3 = darker(accent, 0.35)
	local close
	if not opts.noClose then
		close = Instance.new("TextButton")
		close.Name = "Close"
		close.Text = ""
		close.AutoButtonColor = false
		close.AnchorPoint = Vector2.new(1, 0.5)
		close.Position = UDim2.new(1, -8, 0.5, 0)
		close.Size = UDim2.new(0, 40, 0, 40)
		close.BackgroundColor3 = UIKit.TEXT
		close.ZIndex = 3
		close.Parent = head
		Instance.new("UICorner", close).CornerRadius = UDim.new(1, 0)
		UIKit.icon(close, "cross", 20, darker(accent, 0.5), { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), ZIndex = 4 })
		close.MouseButton1Down:Connect(function() UIKit.sfx("tap") end)
	end
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.new(0, 14, 0, HEAD_H + 12)
	body.Size = UDim2.new(1, -28, 1, -(HEAD_H + 24))
	body.Parent = f
	return f, body, close, t
end


-- one big menu at a time: opening one closes the others (the phone over the
-- daily card over the bag was three stacked panels)
UIKit.MENUS = { "Phone", "Daily", "Bag", "TalentIndex", "Lift", "Apartments", "Dealer", "Ranks" }

-- v4.0: a panel opens on a spring (0.86 -> 1, Back), never just appears
function UIKit.popIn(frame, from)
	if not (frame and frame:IsA("GuiObject")) then return end
	local sc = frame:FindFirstChild("PopScale") or Instance.new("UIScale")
	sc.Name = "PopScale"
	sc.Parent = frame
	sc.Scale = from or 0.86
	game:GetService("TweenService"):Create(sc, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- v4.0: the items in a grid or list arrive one after another (35 ms apart, capped)
function UIKit.stagger(container, step)
	if not container then return end
	local kids = {}
	for _, c in ipairs(container:GetChildren()) do
		if c:IsA("GuiObject") and c.Visible then table.insert(kids, c) end
	end
	table.sort(kids, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
	local TS = game:GetService("TweenService")
	for i, c in ipairs(kids) do
		if i > 24 then break end
		local sc = c:FindFirstChild("StaggerScale") or Instance.new("UIScale")
		sc.Name = "StaggerScale"
		sc.Parent = c
		sc.Scale = 0.55
		task.delay(math.min(0.5, (i - 1) * (step or 0.035)), function()
			TS:Create(sc, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)
	end
end

-- the menu frame of a ScreenGui (the one UIKit.menu built: it has a Header)
function UIKit.animateOpen(gui)
	if not gui then return end
	for _, d in ipairs(gui:GetDescendants()) do
		if d.Name == "Header" and d.Parent and d.Parent:IsA("Frame") then
			local menu = d.Parent
			UIKit.popIn(menu)
			local body = menu:FindFirstChild("Body")
			if body then
				for _, c in ipairs(body:GetDescendants()) do
					if (c:IsA("UIGridLayout") or c:IsA("UIListLayout")) and c.Parent then
						UIKit.stagger(c.Parent)
						break
					end
				end
			end
			return
		end
	end
end

function UIKit.solo(gui)
	local pg = gui and gui.Parent
	if not pg then return end
	for _, name in ipairs(UIKit.MENUS) do
		local g = pg:FindFirstChild(name)
		if g and g ~= gui and g:IsA("ScreenGui") and g.Enabled then g.Enabled = false end
	end
	task.defer(UIKit.animateOpen, gui)
end

return UIKit
