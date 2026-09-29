--[[
	UIKit -- ModuleScript in ReplicatedStorage.

	ONE look for every screen: THE STICKER SHEET (DESIGN.md at the project
	root is the spec; this file is its code). Zero uploads: Frames, UICorner,
	UIStroke and two built-in font families. Every client script builds
	through these helpers so the game looks like one person drew it.

	v5 (29 Sep, the UI polish pass):
	  - palette = ROLES (go / gold / blue / orange / red / purple) on warm
	    paper and ink; old names kept as aliases so nothing breaks
	  - FredokaOne is the voice (numbers, titles, buttons); Nunito ExtraBold
	    is for reading (any sentence), replacing thin Gotham
	  - one type scale (UIKit.TYPE), three radii (UIKit.RADIUS)
	  - every piece has a lip: buttons, cards and menus alike
	  - text on a light fill turns ink automatically (no white on gold)
]]

local UIKit = {}

-- ============ COLOUR: roles, not decoration (DESIGN.md section 2) ============
local rgb = Color3.fromRGB
UIKit.INK = rgb(20, 22, 30)             -- every outline; text on paper
UIKit.INK_SOFT = rgb(42, 46, 58)
UIKit.PAPER = rgb(255, 252, 246)        -- HUD cards, rail buttons (never pure white)
UIKit.SURFACE = rgb(246, 242, 234)      -- menu bodies
UIKit.SURFACE_2 = rgb(236, 230, 218)    -- rows, wells, quiet buttons
UIKit.LINE_LIGHT = rgb(220, 212, 196)   -- dividers and card outlines on paper
UIKit.MUTED_TEXT = rgb(106, 100, 86)    -- secondary text on paper (5.6:1)

UIKit.GREEN = rgb(60, 203, 108)         -- GO: the next action, money gained, ready
UIKit.GREEN_DEEP = rgb(22, 118, 58)       -- 5:1 on the menu surface (29,134,69 was 4.1)
UIKit.GREEN_LIGHT = rgb(221, 247, 230)
UIKit.MONEY = rgb(91, 227, 142)         -- the cash number (always ink-outlined)
UIKit.GOLD = rgb(255, 200, 61)          -- rewards, goals, your own row
UIKit.GOLD_DEEP = rgb(138, 100, 0)
UIKit.GOLD_LIGHT = rgb(255, 241, 196)
UIKit.BLUE = rgb(59, 139, 255)          -- information, navigation
UIKit.BLUE_DEEP = rgb(27, 92, 196)
UIKit.BLUE_LIGHT = rgb(221, 235, 255)
UIKit.ORANGE = rgb(255, 138, 61)        -- resets and costs (spin-off, away)
UIKit.ORANGE_DEEP = rgb(160, 70, 20)      -- v5: 5:1 on the grey wells (176,80,26 was 4.2)
UIKit.ORANGE_LIGHT = rgb(255, 229, 208)
UIKit.RED = rgb(240, 78, 78)            -- badges and danger only
UIKit.RED_DEEP = rgb(160, 36, 36)
UIKit.PURPLE = rgb(165, 92, 255)        -- the rare (GENIUS)
UIKit.PURPLE_DEEP = rgb(106, 47, 192)
UIKit.PINK = rgb(236, 120, 170)         -- the design studio's colour

-- v3-v4 names, kept so every script still reads (values follow the v5 roles)
UIKit.TEXT = rgb(255, 252, 246)         -- text ON a coloured fill
UIKit.MUTED = UIKit.SURFACE_2           -- was a grey button fill: now the quiet button
UIKit.PANEL = rgb(30, 34, 46)
UIKit.LINE = rgb(58, 64, 84)
UIKit.CARD = UIKit.PAPER
UIKit.CARD_LINE = UIKit.LINE_LIGHT
UIKit.CARD_TEXT = UIKit.INK_SOFT
UIKit.CARD_MUTED = UIKit.MUTED_TEXT

local function darker(c, k)
	local h, s, v = c:ToHSV()
	return Color3.fromHSV(h, s, v * (k or 0.7))
end
UIKit.darker = darker

-- the deep shade of a role colour: its outline and its text on paper
-- (keyed by the colour's 0-255 triple: a Color3 is a new value every time)
local function key(c) return ("%d,%d,%d"):format(math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)) end
local DEEP, LIGHT = {}, {}
for _, pair in ipairs({ { UIKit.GREEN, UIKit.GREEN_DEEP, UIKit.GREEN_LIGHT }, { UIKit.GOLD, UIKit.GOLD_DEEP, UIKit.GOLD_LIGHT },
	{ UIKit.BLUE, UIKit.BLUE_DEEP, UIKit.BLUE_LIGHT }, { UIKit.ORANGE, UIKit.ORANGE_DEEP, UIKit.ORANGE_LIGHT },
	{ UIKit.RED, UIKit.RED_DEEP }, { UIKit.PURPLE, UIKit.PURPLE_DEEP }, { UIKit.MONEY, UIKit.GREEN_DEEP } }) do
	DEEP[key(pair[1])] = pair[2]
	LIGHT[key(pair[1])] = pair[3]
end
function UIKit.deep(c) return DEEP[key(c)] or darker(c, 0.55) end
function UIKit.light(c) return LIGHT[key(c)] or c:Lerp(UIKit.PAPER, 0.78) end

-- relative luminance (WCAG): a fill above 0.5 takes ink text, below it white
local function lin(x) return x <= 0.03928 and x / 12.92 or ((x + 0.055) / 1.055) ^ 2.4 end
function UIKit.luminance(c) return 0.2126 * lin(c.R) + 0.7152 * lin(c.G) + 0.0722 * lin(c.B) end
function UIKit.onColor(c) return UIKit.luminance(c) > 0.5 and UIKit.INK or UIKit.TEXT end

-- ============ TYPE (DESIGN.md section 3) ============
UIKit.HEAD = Enum.Font.FredokaOne                                        -- the voice
UIKit.BODY = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.ExtraBold)   -- for reading
UIKit.BOLD = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Heavy)
UIKit.TYPE = { caption = 14, body = 16, label = 18, title = 22, headline = 28, display = 36, money = 44 }
UIKit.RADIUS = { sm = 8, md = 12, lg = 16 }

-- a font argument may be an Enum.Font (FredokaOne) or a Font (Nunito with a weight)
function UIKit.setFont(obj, font)
	if typeof(font) == "Font" then obj.FontFace = font else obj.Font = font or UIKit.HEAD end
end

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

-- the three colours a button derives from its face (DESIGN.md: outline in the
-- deep shade, a lip under the face, ink text on light fills, white on the rest)
local function strokeFor(c)
	if UIKit.luminance(c) > 0.7 then return darker(c, 0.62) end
	return UIKit.deep(c)
end
local function lipFor(c)
	if UIKit.luminance(c) > 0.7 then return darker(c, 0.8) end
	return c:Lerp(UIKit.deep(c), 0.7)
end
UIKit.strokeFor, UIKit.lipFor = strokeFor, lipFor

-- text on a fill: ink on light, white with a crisp deep-shade outline on the rest
local function paintLabel(t, face, fixed)
	local st = t:FindFirstChild("Outline")
	local col = fixed or UIKit.onColor(face)
	t.TextColor3 = col
	t.TextStrokeTransparency = 1
	if col == UIKit.INK or UIKit.luminance(col) < 0.2 then
		if st then st.Enabled = false end
		return
	end
	if not st then
		st = Instance.new("UIStroke")
		st.Name = "Outline"
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		st.LineJoinMode = Enum.LineJoinMode.Round
		st.Parent = t
	end
	st.Enabled = true
	st.Color = UIKit.deep(face)
	st.Thickness = t.TextSize >= 20 and 2 or 1.5
end
UIKit.paintLabel = paintLabel

-- a chunky toy button: face, a lip under it, an outline in the deep shade
function UIKit.button(parent, text, color, props, opts)
	opts = opts or {}
	color = color or UIKit.GOLD
	local b = Instance.new("TextButton")
	b.Text = ""
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b:SetAttribute("Face", color)
	apply(b, props)
	b.Parent = parent
	local radius = opts.radius or UIKit.RADIUS.md
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, radius)
	local st = Instance.new("UIStroke", b)
	st.Color = opts.stroke or strokeFor(color)
	st.Thickness = 2.5
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	if opts.stroke then b:SetAttribute("FixedStroke", opts.stroke) end
	-- the lip: the thing that makes it read as pressable
	local lip = Instance.new("Frame")
	lip.Name = "Lip"
	lip.AnchorPoint = Vector2.new(0, 1)
	lip.Position = UDim2.new(0, 0, 1, 0)
	lip.Size = UDim2.new(1, 0, 0, 5)
	lip.BackgroundColor3 = lipFor(color)
	lip.BorderSizePixel = 0
	lip.ZIndex = b.ZIndex
	lip.Parent = b
	Instance.new("UICorner", lip).CornerRadius = UDim.new(0, radius)
	local t = Instance.new("TextLabel")
	t.Name = "Label"
	t.Size = UDim2.new(1, -12, 1, -5)
	t.Position = UDim2.new(0, 6, 0, 0)
	t.BackgroundTransparency = 1
	t.Text = text
	t.Font = UIKit.HEAD
	t.TextSize = opts.textSize or 20
	t.TextScaled = opts.scaled or false
	t.ZIndex = b.ZIndex + 1
	t.Parent = b
	local fixed = opts.textColor or (opts.dark and UIKit.INK) or nil
	if fixed then b:SetAttribute("FixedText", fixed) end
	paintLabel(t, color, fixed)
	-- press feedback: squash, click, spring back (the same on every button)
	local sc = Instance.new("UIScale")
	sc.Parent = b
	local TS = game:GetService("TweenService")
	--[[ v4.0 MOTION, v5 tuned: hover lifts it (desktop), a press squashes it
	fast, a release springs just past full size and settles (0.92 -> 1.04 -> 1),
	and a rendered icon on it tips and rights itself. ]]
	local UIS = game:GetService("UserInputService")
	local pressed, hovered = false, false
	local seq = 0
	local function to(scale, t, style)
		TS:Create(sc, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = scale }):Play()
	end
	local function release()
		seq += 1
		local mine = seq
		to(1.04, 0.08)
		task.delay(0.08, function() if seq == mine then to(hovered and 1.03 or 1, 0.18, Enum.EasingStyle.Quint) end end)
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
		if not pressed then to(1.03, 0.12) end
	end)
	b.MouseButton1Down:Connect(function()
		pressed = true
		seq += 1
		b.BackgroundColor3 = darker(b:GetAttribute("Face") or color, 0.9)
		to(0.92, 0.06)
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
	if st then st.Color = b:GetAttribute("FixedStroke") or strokeFor(color) end
	local lip = b:FindFirstChild("Lip")
	if lip then lip.BackgroundColor3 = lipFor(color) end
	local t = b:FindFirstChild("Label")
	if t then paintLabel(t, color, b:GetAttribute("FixedText")) end
end

function UIKit.label(parent, text, size, color, props, font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size or 16
	l.TextColor3 = color or UIKit.TEXT
	UIKit.setFont(l, font or UIKit.BODY)
	l.TextXAlignment = Enum.TextXAlignment.Left
	apply(l, props)
	l.Parent = parent
	return l
end

--[[ THE LIP on a panel (v5): the bottom `px` of the face drawn darker, like a
button's lip, so a paper card separates from a bright floor. A UIGradient on
the frame itself (a child band would be moved by a UIListLayout inside the
card), re-cut whenever the frame's height changes. ]]
function UIKit.lip(frame, px, shade)
	px = px or 4
	local g = frame:FindFirstChild("LipGradient") or Instance.new("UIGradient")
	g.Name = "LipGradient"
	g.Rotation = 90
	local k = shade or 0.86
	local low = Color3.new(k, k * 0.985, k * 0.955)
	local function cut()
		local h = frame.AbsoluteSize.Y
		if h <= px * 2 then g.Enabled = false return end
		g.Enabled = true
		local at = math.clamp(1 - px / h, 0.5, 0.995)
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(at - 0.001, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(at, low),
			ColorSequenceKeypoint.new(1, low),
		})
	end
	g.Parent = frame
	if not frame:GetAttribute("LipWired") then
		frame:SetAttribute("LipWired", true)
		frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(cut)
	end
	cut()
	return g
end

-- a paper HUD card: lg radius, a soft outline, a lip
function UIKit.card(parent, props, opts)
	opts = opts or {}
	local f = UIKit.panel(parent, props, { radius = opts.radius or UIKit.RADIUS.lg, color = UIKit.CARD,
		stroke = opts.stroke or UIKit.CARD_LINE, strokeWidth = opts.strokeWidth or 2 })
	if opts.lip ~= false then UIKit.lip(f, opts.lip or 4) end
	return f
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
	-- v5 (29 Sep UI pass): the two rail/corner buttons that were still flat glyphs
	gift = "rbxassetid://101002817721964",      -- DAILY
	trophy = "rbxassetid://110913338783631",    -- RANKS
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

--[[ v5 A RAIL BUTTON: a paper tile with an ink outline, the full-colour
rendered icon popping above it and an ink caption (Run a Restaurant!'s rail).
The rail used to be five saturated tiles in five colours, all as loud as the
one thing you should do next (DESIGN.md principle 1). The accent colour now
means one thing: this menu is open (UIKit.setRailActive). ]]
function UIKit.railButton(key, caption, accent, props, opts)
	opts = opts or {}
	opts.dark = true
	opts.stroke = opts.stroke or UIKit.INK_SOFT
	opts.iconSize = opts.iconSize or 30
	opts.captionSize = opts.captionSize or 14
	local b, t, ic = UIKit.iconButton(UIKit.rail(), key, caption, UIKit.PAPER, props, opts)
	b:SetAttribute("Accent", accent or UIKit.BLUE)
	return b, t, ic
end

function UIKit.setRailActive(b, on)
	if not b then return end
	local accent = b:GetAttribute("Accent") or UIKit.BLUE
	b:SetAttribute("RailActive", on == true)
	UIKit.setButtonColor(b, on and UIKit.light(accent) or UIKit.PAPER)
	local st = b:FindFirstChildOfClass("UIStroke")
	if st then st.Color = on and UIKit.deep(accent) or UIKit.INK_SOFT end
	-- the caption stays ink: the tint and the outline say "open" (a deep-orange
	-- caption on light orange measured 4.3:1)
	local t = b:FindFirstChild("Label")
	if t then t.TextColor3 = UIKit.INK end
end

-- the tile shows "open" exactly while its menu is (every close path, including
-- another menu opening via UIKit.solo, goes through gui.Enabled)
function UIKit.bindRail(b, gui)
	if not (b and gui) then return end
	gui:GetPropertyChangedSignal("Enabled"):Connect(function() UIKit.setRailActive(b, gui.Enabled) end)
	UIKit.setRailActive(b, gui.Enabled)
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

--[[ v4.4 FIT TO THE SCREEN. His screenshot (a short Studio window): the fifth
rail button (RANKS, added in v4.2) ran off the bottom, which the v3.2 sum above
never counted. A column now shrinks as one piece (UIScale) until everything
visible fits between `top` and `bottom` reserved pixels, never below minScale.
Measured from the children, so a button that appears later (DECOR at HQ 2,
RANKS once shipped) is counted when it shows. ]]
local function fitColumn(gui, frame, layout, top, bottom, minScale)
	local sc = Instance.new("UIScale")
	sc.Name = "FitScale"
	sc.Parent = frame
	task.spawn(function()
		while frame.Parent do
			local s = sc.Scale
			local total, n = 0, 0
			for _, c in ipairs(frame:GetChildren()) do
				if c:IsA("GuiObject") and c.Visible then
					total += c.AbsoluteSize.Y / s
					n += 1
				end
			end
			total += math.max(0, n - 1) * layout.Padding.Offset
			local room = gui.AbsoluteSize.Y - top - bottom
			local want = (total > 0 and room > 0) and math.clamp(room / total, minScale, 1) or 1
			if math.abs(want - s) > 0.01 then sc.Scale = want end
			task.wait(0.5)
		end
	end)
end

--[[ v5 THE RAIL ON A PHONE. Measured in Studio's iPhone XR simulator (801 x 392):
a single column of five tiles ran down to y 381 and shrank to 0.88 (12 px
captions), and its bottom tiles sat exactly on the movement thumbstick's resting
spot (x 29-103, y 299-373), where a thumb lands to walk. On a short screen the
rail is a 2-column grid at full size instead: three rows end at y ~262, clear of
the thumbstick. A tall screen keeps the single column. The layout follows the
screen (a phone can rotate, a desktop window can be resized). ]]
-- Tile order = the order they unlock (INDEX 1, BAG 2, PHONE 3, DECOR 4, DAILY 5):
-- a new tile is appended and a tile you have learned never moves (v5 critique:
-- INDEX was slot 1, then 3, then 4 as the others appeared ahead of it).
local RAIL_GRID_BELOW = 520     -- viewport height under which the rail becomes a grid
local function railLayout(g, f)
	local cam = workspace.CurrentCamera
	local grid = cam.ViewportSize.Y < RAIL_GRID_BELOW
	local want = grid and "UIGridLayout" or "UIListLayout"
	local cur = f:FindFirstChildWhichIsA("UIGridStyleLayout")
	if cur and cur.ClassName == want then return end
	if cur then cur:Destroy() end
	local fs = f:FindFirstChild("FitScale")
	if grid then
		local l = Instance.new("UIGridLayout")
		l.CellSize = UDim2.new(0, UIKit.RAIL - 2, 0, UIKit.RAIL - 2)
		l.CellPadding = UDim2.new(0, 8, 0, 8)
		l.FillDirectionMaxCells = 2
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Parent = f
		f.Size = UDim2.new(0, 2 * (UIKit.RAIL - 2) + 8, 1, -76)
		if fs then fs.Scale = 1 end
		f:SetAttribute("Grid", true)
	else
		local l = Instance.new("UIListLayout")
		l.Padding = UDim.new(0, 8)
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Parent = f
		f.Size = UDim2.new(0, 90, 1, -76)
		f:SetAttribute("Grid", false)
	end
end

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
		f.Position = UDim2.new(0, 12, 0, 66)      -- v5: 66, so a first-row badge clears the 58 px top bar
		f.Size = UDim2.new(0, 90, 1, -76)
		f.Parent = g
		railLayout(g, f)
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function() railLayout(g, f) end)
		-- the single column still shrinks as one piece if it runs out of room (never below 0.8);
		-- the grid never needs to
		local sc = Instance.new("UIScale")
		sc.Name = "FitScale"
		sc.Parent = f
		task.spawn(function()
			while f.Parent do
				local l = f:FindFirstChildWhichIsA("UIGridStyleLayout")
				if l and l:IsA("UIListLayout") then
					local s = sc.Scale
					local total, n = 0, 0
					for _, c in ipairs(f:GetChildren()) do
						if c:IsA("GuiObject") and c.Visible then total += c.AbsoluteSize.Y / s; n += 1 end
					end
					total += math.max(0, n - 1) * l.Padding.Offset
					local room = g.AbsoluteSize.Y - 64 - 10
					local want = (total > 0 and room > 0) and math.clamp(room / total, 0.8, 1) or 1
					if math.abs(want - s) > 0.01 then sc.Scale = want end
				elseif sc.Scale ~= 1 then
					sc.Scale = 1
				end
				task.wait(0.5)
			end
		end)
	end
	return g:WaitForChild("Column")
end

-- the rail's right edge in screen pixels (other pieces keep clear of it)
function UIKit.railRight()
	local pg = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
	local col = pg and pg:FindFirstChild("Rail") and pg.Rail:FindFirstChild("Column")
	if not col then return 12 + UIKit.RAIL end
	local sc = col:FindFirstChild("FitScale")
	local w = 0
	for _, c in ipairs(col:GetChildren()) do
		if c:IsA("GuiObject") and c.Visible then
			w = math.max(w, c.AbsolutePosition.X + c.AbsoluteSize.X - col.AbsolutePosition.X)
		end
	end
	if w == 0 then w = UIKit.RAIL * (sc and sc.Scale or 1) end
	return col.AbsolutePosition.X + w
end

--[[ v5 the free strip across the top of the HUD, between the left rail and the
right column, in screen x. A card that must not cover either one (the HQ
banner, a rare-hire reveal) sits here. Centred on the screen when it fits
(minCentred wide or more), otherwise centred in the gap. Returns the card's
centre x and its width, capped at maxW. Measured on a phone (801 wide): the
rail ends at 148 and the goal card starts at 529, so a 520-wide banner sat on
both. To place a card, subtract its ScreenGui's AbsolutePosition.X from cx. ]]
function UIKit.hudGap(maxW, minCentred, ignoreColumn)
	local pg = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
	local vpX = workspace.CurrentCamera.ViewportSize.X
	local rail = pg and pg:FindFirstChild("Rail")
	local l = (rail and rail.Enabled) and (UIKit.railRight() + 8) or 12
	local r = vpX - 12
	local col = pg and pg:FindFirstChild("RightColumn")
	local c = not ignoreColumn and col and col.Enabled and col:FindFirstChild("Column")
	if c and c.Visible then
		for _, row in ipairs(c:GetChildren()) do
			if row:IsA("GuiObject") and row.Visible and row.AbsoluteSize.X > 1 then
				r = math.min(r, row.AbsolutePosition.X - 8)
			end
		end
	end
	local centred = 2 * math.min(vpX / 2 - l, r - vpX / 2)
	if centred >= (minCentred or 340) then return vpX / 2, math.min(maxW, centred) end
	return (l + r) / 2, math.min(maxW, r - l)
end

--[[ v5 ONE RULE FOR WHERE A MENU GOES. Every menu had its own fit line
(vp.X - 24, vp.X - 130, a +24 or +30 nudge), and the ones written for a
one-column rail put the Bag 3.5 px over the phone's 2-wide rail, on the PHONE
badge. Now: centred on the screen, slid right just enough to clear the rail,
scaled down only when the free area is smaller than the menu. Refits when the
screen changes and every time the menu opens (the rail grows as tiles unlock).
The panel is centre-anchored and a child of its ScreenGui. Returns place(yScale,
yOffset) -> a UDim2 at the fitted x, for menus that slide in. ]]
function UIKit.fitMenu(panel, w, h, sc, vMargin)
	sc = sc or panel:FindFirstChildOfClass("UIScale")
	if not sc then
		sc = Instance.new("UIScale")
		sc.Parent = panel
	end
	local x, dy = nil, 0
	local base = panel.Position.Y
	local function refit()
		local parent = panel.Parent
		if not (parent and parent:IsA("GuiBase2d")) then return end
		local px, pw, ph = parent.AbsolutePosition.X, parent.AbsoluteSize.X, parent.AbsoluteSize.Y
		if pw <= 0 then return end
		local W, H = w or panel.Size.X.Offset, h or panel.Size.Y.Offset
		local left, right = px + 12, px + pw - 12
		local pg = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
		local rail = pg and pg:FindFirstChild("Rail")
		if rail and rail.Enabled then left = math.max(left, UIKit.railRight() + 10) end
		local s = math.min(1, (right - left) / W, (ph - (vMargin or 24)) / H)
		local half = W * s / 2
		x = math.clamp(px + pw / 2, left + half, math.max(left + half, right - half)) - px
		-- below the money line (screen y 64) when the menu fits there at this
		-- scale; a taller one stays centred rather than shrink (v5 critique: the
		-- BAG header cut the money in half)
		local hh = H * s / 2
		dy = (hh * 2 <= ph - 64 - 8) and math.max(0, (64 + hh) - ph / 2) or 0
		-- a menu mid pop-in tweens to its Rest scale; move that instead of fighting it
		if sc:GetAttribute("Rest") then
			sc:SetAttribute("Rest", s)
		elseif math.abs(sc.Scale - s) > 0.001 then
			sc.Scale = s
		end
		panel.Position = UDim2.new(0, x, base.Scale, base.Offset + dy)
	end
	refit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)
	local g = panel:FindFirstAncestorWhichIsA("ScreenGui")
	if g then g:GetPropertyChangedSignal("Enabled"):Connect(function() if g.Enabled then refit() end end) end
	return function(yScale, yOffset)
		refit()
		return UDim2.new(0, x or 0, yScale, yOffset + dy)
	end
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
		-- v4.4 and never taller than the screen: the WRITE CODE bar owns the bottom ~110
		fitColumn(g, f, l, 60, 110, 0.9)    -- v5: one goal card now, so it never has to shrink to 0.7
		-- v5 one thing at a time: a centred menu or decision card that reaches the
		-- goal card hides it until it closes. On a phone a 440-wide menu covered
		-- half the card and the cut-off half ("in off!") read as clutter. This loop
		-- owns the frame's Visible; the ScreenGui's Enabled stays with build mode.
		task.spawn(function()
			local function covers(mg, left, bottom, vpX)
				if not (mg and mg:IsA("ScreenGui") and mg.Enabled) then return false end
				for _, c in ipairs(mg:GetChildren()) do
					if c:IsA("GuiObject") and c.Visible and c.AbsoluteSize.X >= 240 and c.AbsoluteSize.X < vpX * 0.9
						and c.AbsoluteSize.Y >= 120 and c.AbsolutePosition.X + c.AbsoluteSize.X > left + 4
						and c.AbsolutePosition.Y < bottom then
						return true
					end
				end
				return false
			end
			while f.Parent do
				local left, bottom = math.huge, -math.huge
				for _, row in ipairs(f:GetChildren()) do
					if row:IsA("GuiObject") and row.Visible then
						left = math.min(left, row.AbsolutePosition.X)
						bottom = math.max(bottom, row.AbsolutePosition.Y + row.AbsoluteSize.Y)
					end
				end
				-- a celebration (HQ level-up, rare hire) is centred under the money and
				-- the goal card steps aside for its few seconds (v5 critique: the two
				-- side by side made a 580 px strip across the top third)
				local covered = game:GetService("Players").LocalPlayer:GetAttribute("Celebrating") == true
				if not covered and left < math.huge then
					local vpX = workspace.CurrentCamera.ViewportSize.X
					covered = covers(pg:FindFirstChild("Celebrate"), left, bottom, vpX)
					for _, name in ipairs(UIKit.MENUS or {}) do
						if covered then break end
						covered = covers(pg:FindFirstChild(name), left, bottom, vpX)
					end
				end
				if f.Visible == covered then f.Visible = not covered end
				task.wait(0.15)
			end
		end)
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
	local HEAD_H = opts.headerHeight or 52
	local R = UIKit.RADIUS.lg
	local f = Instance.new("Frame")
	f.BackgroundColor3 = UIKit.SURFACE
	f.BorderSizePixel = 0
	apply(f, props)
	f.Parent = parent
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, R)
	local st = Instance.new("UIStroke", f)
	st.Color = UIKit.deep(accent)
	st.Thickness = 3
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	UIKit.lip(f, 6, 0.9)
	local head = Instance.new("Frame")
	head.Name = "Header"
	head.BackgroundColor3 = accent
	head.BorderSizePixel = 0
	head.Size = UDim2.new(1, 0, 0, HEAD_H)
	head.Parent = f
	Instance.new("UICorner", head).CornerRadius = UDim.new(0, R)
	local sq = Instance.new("Frame")          -- square off the header's bottom corners
	sq.BackgroundColor3 = accent
	sq.BorderSizePixel = 0
	sq.AnchorPoint = Vector2.new(0, 1)
	sq.Position = UDim2.new(0, 0, 1, 0)
	sq.Size = UDim2.new(1, 0, 0, R)
	sq.Parent = head
	local rule = Instance.new("Frame")        -- a hard edge under the header, in the deep shade
	rule.Name = "Rule"
	rule.BackgroundColor3 = UIKit.deep(accent)
	rule.BorderSizePixel = 0
	rule.AnchorPoint = Vector2.new(0, 1)
	rule.Position = UDim2.new(0, 0, 1, 0)
	rule.Size = UDim2.new(1, 0, 0, 3)
	rule.Parent = head
	local t = UIKit.label(head, title or "", 24, UIKit.TEXT, {
		Name = "Title", Position = UDim2.new(0, 18, 0, 0), Size = UDim2.new(1, -84, 1, -3),
		TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 2,
	}, UIKit.HEAD)
	paintLabel(t, accent)
	--[[ v5: on a phone a full-height menu reaches the top of the screen, where
	Roblox draws its own logo / menu / chat buttons (top-left, ~170 x 58) above
	every game GUI. Shrinking the menu to dodge them would push its text under
	14 px, so instead the title steps right of that corner whenever the menu
	reaches it. ]]
	local GuiService = game:GetService("GuiService")
	local function dodge()
		local inset = GuiService:GetGuiInset().Y
		local pos = f.AbsolutePosition
		local sc = f:FindFirstChildOfClass("UIScale")
		local k = (sc and sc.Scale > 0) and sc.Scale or 1
		local shift = 0
		if pos.Y + inset < 58 and pos.X < 196 then shift = math.max(0, (196 - pos.X) / k - 6) end   -- phone top bar reaches x ~190
		t.Position = UDim2.new(0, 18 + shift, 0, 0)
		t.Size = UDim2.new(1, -(84 + shift), 1, -3)
	end
	f:GetPropertyChangedSignal("AbsolutePosition"):Connect(dodge)
	f:GetPropertyChangedSignal("AbsoluteSize"):Connect(dodge)
	task.defer(dodge)
	local close
	if not opts.noClose then
		close = Instance.new("TextButton")
		close.Name = "Close"
		close.Text = ""
		close.AutoButtonColor = false
		close.AnchorPoint = Vector2.new(1, 0.5)
		close.Position = UDim2.new(1, -8, 0.5, -1)
		close.Size = UDim2.new(0, 44, 0, 44)
		close.BackgroundColor3 = UIKit.PAPER
		close.ZIndex = 3
		close.Parent = head
		Instance.new("UICorner", close).CornerRadius = UDim.new(1, 0)
		local cs = Instance.new("UIStroke", close)
		cs.Color = UIKit.deep(accent)
		cs.Thickness = 2.5
		UIKit.icon(close, "cross", 20, UIKit.INK_SOFT, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), ZIndex = 4 })
		local csc = Instance.new("UIScale", close)
		local TS = game:GetService("TweenService")
		close.MouseButton1Down:Connect(function()
			UIKit.sfx("tap")
			TS:Create(csc, TweenInfo.new(0.06), { Scale = 0.88 }):Play()
		end)
		close.MouseButton1Up:Connect(function() TS:Create(csc, TweenInfo.new(0.16, Enum.EasingStyle.Quint), { Scale = 1 }):Play() end)
		close.MouseLeave:Connect(function() csc.Scale = 1 end)
	end
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.new(0, 14, 0, HEAD_H + 12)
	body.Size = UDim2.new(1, -28, 1, -(HEAD_H + 26))
	body.Parent = f
	return f, body, close, t
end


-- one big menu at a time: opening one closes the others (the phone over the
-- daily card over the bag was three stacked panels)
UIKit.MENUS = { "Phone", "Daily", "Bag", "TalentIndex", "Lift", "Apartments", "Dealer", "Ranks" }

-- v5: a panel opens by growing in (0.94 -> 1, Quint out, no overshoot: a menu
-- is a state change, not a celebration). A frame keeps ONE UIScale (Roblox only
-- honours one), so a menu that already fit-scales to the screen is animated
-- through that scale, from and back to its own value.
function UIKit.popIn(frame, from)
	if not (frame and frame:IsA("GuiObject")) then return end
	local sc = frame:FindFirstChildOfClass("UIScale")
	if not sc then
		sc = Instance.new("UIScale")
		sc.Name = "PopScale"
		sc.Parent = frame
	end
	local target = sc:GetAttribute("Rest") or sc.Scale
	sc:SetAttribute("Rest", target)
	sc.Scale = target * (from or 0.94)
	local tw = game:GetService("TweenService"):Create(sc, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Scale = target })
	tw:Play()
	tw.Completed:Connect(function() sc:SetAttribute("Rest", nil) end)
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
		-- one UIScale per frame: a button's press scale doubles as its stagger scale
		local sc = c:FindFirstChildOfClass("UIScale")
		if not sc then
			sc = Instance.new("UIScale")
			sc.Name = "StaggerScale"
			sc.Parent = c
		end
		if i > 12 then sc.Scale = 1 continue end
		sc.Scale = 0.8
		task.delay((i - 1) * (step or 0.03), function()
			TS:Create(sc, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Scale = 1 }):Play()
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
