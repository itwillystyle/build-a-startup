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
local MenuFit = require(script.Parent:WaitForChild("MenuFit"))   -- v8 (14 Oct): fitMenu's pure half
local MotionSpec = require(script.Parent:WaitForChild("MotionSpec"))   -- 23 Oct: the motion layer's rules
local TransparencySpec = require(script.Parent:WaitForChild("TransparencySpec"))   -- 24 Oct: Background Transparency rules

-- ============ MOTION: one layer every UI tween goes through (23 Oct 2026) ============
--[[ The consensus plan (silicon-startup/ui/animation-review/judge/FINAL.md). MotionSpec (pure,
	tested) decides; this applies it. Measured in Studio before it was built (M1-M8 there):
	  * a property set directly while a tween runs on it is overwritten by that tween next frame,
	    so instant props Cancel() the tween UIKit tracks on that object first, then set directly
	    (same frame), then play a 0 s tween to the same values, which also cancels any tween UIKit
	    does not know about and gives callers a real Tween whose Completed fires (~3 frames later)
	  * a cancelled tween's other goals are SET, not left half way (finish, never freeze)
	UIKit.tween always returns one real Tween. UIKit.set is the direct write for a property UIKit
	may be tweening. UIKit.reducedMotion() is Roblox's Reduce Motion setting, or the player
	attribute ForceReducedMotion (so the doctor and Luke can test it); loops call it each frame. ]]
local TweenService = game:GetService("TweenService")
UIKit.T = MotionSpec.T
local reducedSetting = false
pcall(function()
	local GuiService = game:GetService("GuiService")
	reducedSetting = GuiService.ReducedMotionEnabled == true
	GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(function()
		reducedSetting = GuiService.ReducedMotionEnabled == true
	end)
end)
function UIKit.reducedMotion()
	local p = game:GetService("Players").LocalPlayer
	if p and p:GetAttribute("ForceReducedMotion") == true then return true end
	return reducedSetting
end

local running = setmetatable({}, { __mode = "k" })   -- object -> { { tween, goal } }
local function live(tw)
	local s = tw.PlaybackState
	return s == Enum.PlaybackState.Playing or s == Enum.PlaybackState.Begin or s == Enum.PlaybackState.Delayed
end
-- cancel the tracked tweens on `obj` that share a property with `props`, landing their other goals
local function finishOverlapping(obj, props)
	local list = running[obj]
	if not list then return end
	local keep = {}
	for _, e in ipairs(list) do
		if live(e.tween) and MotionSpec.overlaps(e.goal, props) then
			e.tween:Cancel()
			for k, v in pairs(e.goal) do
				if props[k] == nil then pcall(function() obj[k] = v end) end
			end
		elseif live(e.tween) then
			table.insert(keep, e)
		end
	end
	running[obj] = keep
end
local function track(obj, tw, goal)
	local list = running[obj] or {}
	table.insert(list, { tween = tw, goal = goal })
	running[obj] = list
end

local TWEENABLE = { number = true, UDim2 = true, UDim = true, Color3 = true, Vector2 = true, Vector3 = true, CFrame = true }
function UIKit.set(obj, props)
	finishOverlapping(obj, props)
	for k, v in pairs(props) do obj[k] = v end
	-- review of the layer: a tween UIKit is not tracking (or lost track of) would still overwrite the
	-- direct write next frame (M2); a 0 s tween to the same values cancels it and holds (M3, M8).
	-- Only values TweenService can tween go in it (Text or Visible would make Create throw)
	local tweenable = {}
	for k, v in pairs(props) do
		if TWEENABLE[typeof(v)] then tweenable[k] = v end
	end
	if next(tweenable) then
		local ok, hold = pcall(TweenService.Create, TweenService, obj, TweenInfo.new(0), tweenable)
		if ok then
			hold:Play()
			track(obj, hold, tweenable)
		end
	end
end

-- opts: { kind = "progress" } for a fill that measures time (never changed by Reduce Motion)
function UIKit.tween(obj, seconds, props, style, dir, opts)
	local current = {}
	if props.Scale ~= nil then pcall(function() current.Scale = obj.Scale end) end
	local plan = MotionSpec.plan(props, current, UIKit.reducedMotion(), opts)
	finishOverlapping(obj, props)
	local instant
	if next(plan.instant) then
		for k, v in pairs(plan.instant) do obj[k] = v end
		instant = TweenService:Create(obj, TweenInfo.new(0), plan.instant)
		instant:Play()
		track(obj, instant, plan.instant)
	end
	if next(plan.tween) then
		local tw = TweenService:Create(obj, TweenInfo.new(seconds, style or Enum.EasingStyle.Quint,
			dir or Enum.EasingDirection.Out), plan.tween)
		tw:Play()
		track(obj, tw, plan.tween)
		return tw
	end
	if instant then return instant end
	-- everything was an exit's dropped drift: still hand back a real tween that completes
	local none = TweenService:Create(obj, TweenInfo.new(0), {})
	none:Play()
	return none
end

-- ============ BACKGROUND TRANSPARENCY: Roblox's accessibility setting (24 Oct 2026) ============
--[[ Board item P-4. GuiService.PreferredTransparency: 1 = backgrounds as designed, 0 = fully solid.
	TransparencySpec (pure, tested) holds the rule (designed * preferred); this applies it.
	UIKit.preferredTransparency() is the setting, or the player attribute ForcePreferredTransparency
	(a number, so the doctor and Luke can test it). UIKit.translucent(frame, designed) draws a
	see-through surface at designed * preferred and keeps it following the setting: ONE shared
	watch (the setting's change signal + the attribute) moves every registered frame that is at
	rest on its value, and leaves one that something is fading. UIKit.panel / card / pill register
	themselves when given a see-through BackgroundTransparency. World (3D) transparency, text,
	images, and effects (washes, glows, dims) are not backgrounds and do not follow it. ]]
local preferredSetting = nil
pcall(function()
	preferredSetting = game:GetService("GuiService").PreferredTransparency
end)
function UIKit.preferredTransparency()
	local p = game:GetService("Players").LocalPlayer
	local forced = p and p:GetAttribute("ForcePreferredTransparency")
	return TransparencySpec.resolve(preferredSetting, forced)
end
local translucents = setmetatable({}, { __mode = "k" })   -- frame -> its designed BackgroundTransparency
local drawnWith = UIKit.preferredTransparency()          -- the value the registered frames show now
local function followTransparency()
	local now = UIKit.preferredTransparency()
	local was = drawnWith
	drawnWith = now
	if was == now then return end
	for obj, designed in pairs(translucents) do
		local v = TransparencySpec.reapply(obj.BackgroundTransparency, designed, was, now)
		if v then UIKit.set(obj, { BackgroundTransparency = v }) end
	end
end
pcall(function()
	local GuiService = game:GetService("GuiService")
	GuiService:GetPropertyChangedSignal("PreferredTransparency"):Connect(function()
		preferredSetting = GuiService.PreferredTransparency
		followTransparency()
	end)
end)
do
	local p = game:GetService("Players").LocalPlayer
	if p then p:GetAttributeChangedSignal("ForcePreferredTransparency"):Connect(followTransparency) end
end
-- what a see-through surface designed at `designed` should show right now (for a caller fading one in)
function UIKit.bg(designed)
	return TransparencySpec.bg(designed, drawnWith)
end
function UIKit.translucent(obj, designed)
	if not TransparencySpec.follows(designed) then return obj end
	translucents[obj] = designed
	obj.BackgroundTransparency = TransparencySpec.bg(designed, drawnWith)
	return obj
end

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
UIKit.SLATE = rgb(126, 136, 156)        -- the server room's colour (cool grey, never a button)
UIKit.SILVER = rgb(96, 104, 120)        -- 2nd place (readable on paper)
UIKit.BRONZE = rgb(158, 92, 40)         -- 3rd place (readable on paper)
UIKit.BLACK = rgb(8, 9, 12)             -- letterbox bars and fades only: the screen going dark

--[[ v6 (11 Oct): ONE place for the colours that mean something in the game. They
	were typed out again in each script (IndexClient's tiers, WaferClient's and
	GuideClient's departments, HomeClient's home tiers), 57 different hand-picked
	colours in all, so the same GENIUS was three purples. tests/offline/uistyle.spec
	now fails on a Color3.fromRGB in UI code that is not marked as a world colour. ]]
UIKit.TIER = { regular = rgb(172, 180, 196), skilled = UIKit.GREEN, star = UIKit.BLUE, genius = UIKit.PURPLE, unicorn = UIKit.GOLD }
-- the HQ's floors: the SAME tints the building is painted with (Wafers.TINT, server side)
UIKit.DEPT = {
	lobby = rgb(236, 214, 170), eng = rgb(150, 188, 232), studio = rgb(236, 164, 192), cafe = rgb(246, 176, 116),
	servers = rgb(70, 78, 96), labs = rgb(122, 214, 198), board = rgb(236, 202, 112),
}
-- the three HQ styles on the picker
UIKit.PATH = { W_ = rgb(122, 170, 80), T_ = rgb(236, 170, 70), D_ = rgb(150, 166, 188) }

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
UIKit.RADIUS = { sm = 8, md = 12, lg = 16, xl = 24, pill = 999 }   -- xl: a device's outline (the phone); pill: fully round

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
	-- 24 Oct: a see-through panel (and so a card or pill) follows Background Transparency
	if props then UIKit.translucent(f, props.BackgroundTransparency) end
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
			TS:Create(ic, TweenInfo.new(down and 0.07 or 0.3, down and Enum.EasingStyle.Quad or Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
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
	-- v9 (12 Oct, the frameless rail): the last three tiles that were flat glyphs or drawn
	build = "rbxassetid://126943084369880",     -- BUILD: a gold hard hat
	more = "rbxassetid://108704449117094",      -- MORE: a 2 x 2 of the rail's accents
	info = "rbxassetid://123981684632859",      -- TELL US: a pink speech bubble
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

--[[ v9 (12 Oct) FRAMELESS. My Restaurant!'s hotbar is just its 3D icons, each with a
	key, the name only on the one you are on. Our tiles were paper boxes with a caption
	each: a menu's look, not a game's. A frameless tile is its icon (a render, or a
	ViewportFrame model), bigger; the name shows on hover or while active, and always
	on a touch screen (no hover there, and a new player needs the word); active = a
	soft disc in the tile's accent behind the icon. Used by the rail (railButton) and
	the bottom row (COFFEE, CAR). b: the button (UIKit.button / iconButton), t: its
	name label, ic: its icon. opts.key: a keyboard letter shown on a key cap. ]]
function UIKit.frameless(b, t, ic, accent, opts)
	opts = opts or {}
	accent = accent or UIKit.BLUE
	b:SetAttribute("Accent", accent)
	b.BackgroundTransparency = 1
	local st = b:FindFirstChildOfClass("UIStroke")
	if st then st.Enabled = false end
	local lip = b:FindFirstChild("Lip")
	if lip then lip.Visible = false end
	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.new(0.5, 0, 0.5, -4)
	glow.Size = UDim2.new(0, 58, 0, 58)
	glow.BackgroundColor3 = UIKit.light(accent)
	glow.BorderSizePixel = 0
	glow.Visible = false
	glow.ZIndex = b.ZIndex
	glow.Parent = b
	Instance.new("UICorner", glow).CornerRadius = UDim.new(1, 0)
	local gs = Instance.new("UIStroke", glow)
	gs.Color = UIKit.deep(accent)
	gs.Thickness = 2
	if ic and ic:IsA("GuiObject") then
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.new(0.5, 0, 0.5, -4)
		ic.Size = UDim2.new(0, 56, 0, 56)
		ic.ZIndex = b.ZIndex + 1
		if ic.Name ~= "Icon" and ic:IsA("ViewportFrame") then ic.Name = "Icon" end
	end
	if t then
		t.AnchorPoint = Vector2.new(0.5, 0)
		t.Position = UDim2.new(0.5, 0, 1, -16)
		t.Size = UDim2.new(1, 16, 0, 18)
		t.ZIndex = b.ZIndex + 2
		t.TextColor3 = UIKit.TEXT
		b:SetAttribute("FixedText", UIKit.TEXT)
		local ts = t:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke", t)
		ts.Enabled = true
		ts.Color = UIKit.INK
		ts.Thickness = 2
		ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	end
	local UIS = game:GetService("UserInputService")
	local touchOnly = UIS.TouchEnabled and not UIS.MouseEnabled
	local hovered = false
	local function syncCaption()
		if t then t.Visible = touchOnly or hovered or b:GetAttribute("RailActive") == true end
	end
	b.MouseEnter:Connect(function() hovered = true; syncCaption() end)
	b.MouseLeave:Connect(function() hovered = false; syncCaption() end)
	b:GetAttributeChangedSignal("RailActive"):Connect(syncCaption)
	syncCaption()
	if opts.key and not touchOnly then
		local cap = UIKit.panel(b, { Name = "LetterKey", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 8, 0, 8),
			Size = UDim2.new(0, 22, 0, 22), ZIndex = b.ZIndex + 4 },
			{ radius = UIKit.RADIUS.sm, color = UIKit.PAPER, stroke = UIKit.INK_SOFT, strokeWidth = 2 })
		UIKit.label(cap, opts.key, UIKit.TYPE.caption, UIKit.INK, { Name = "N", Size = UDim2.new(1, 0, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Center, ZIndex = b.ZIndex + 5 }, UIKit.HEAD)
	end
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
	-- v8: a tile you open now and then lives in the MORE tray (UIKit.railTray)
	local home = opts.tray and UIKit.railTray() or UIKit.rail()
	local b, t, ic = UIKit.iconButton(home, key, caption, UIKit.PAPER, props, opts)
	accent = accent or UIKit.BLUE
	b:SetAttribute("Accent", accent)
	if opts.plotOnly then b:SetAttribute("PlotOnly", true) end

	-- v9: the frameless look (UIKit.frameless), shared with the bottom row
	UIKit.frameless(b, t, ic, accent)
	local UIS = game:GetService("UserInputService")
	local touchOnly = UIS.TouchEnabled and not UIS.MouseEnabled
	-- the number key (desktop): the tile's place in the column, set by UIKit.rail
	if not opts.tray and not touchOnly then
		local cap = UIKit.panel(b, { Name = "NumKey", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 8, 0, 8),
			Size = UDim2.new(0, 22, 0, 22), ZIndex = b.ZIndex + 4, Visible = false },
			{ radius = UIKit.RADIUS.sm, color = UIKit.PAPER, stroke = UIKit.INK_SOFT, strokeWidth = 2 })
		UIKit.label(cap, "", UIKit.TYPE.caption, UIKit.INK, { Name = "N", Size = UDim2.new(1, 0, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Center, ZIndex = b.ZIndex + 5 }, UIKit.HEAD)
	end
	-- a key press opens it the same way a click does (UIKit.onRailPress)
	local press = Instance.new("BindableEvent")
	press.Name = "Press"
	press.Parent = b

	return b, t, ic
end

function UIKit.setRailActive(b, on)
	if not b then return end
	b:SetAttribute("RailActive", on == true)
	-- v9 frameless: open = the accent disc behind the icon, the name shown, the icon up a touch
	local glow = b:FindFirstChild("Glow")
	if glow then glow.Visible = on == true end
	local ic = b:FindFirstChild("Icon")
	if ic and ic:IsA("ImageLabel") then
		game:GetService("TweenService"):Create(ic, TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Size = on and UDim2.new(0, 62, 0, 62) or UDim2.new(0, 56, 0, 56) }):Play()
	end
end

-- connect a rail tile's action: a click or tap, and its number key (both fire fn)
function UIKit.onRailPress(b, fn)
	b.MouseButton1Click:Connect(fn)
	local press = b:FindFirstChild("Press")
	if press then press.Event:Connect(fn) end
end

-- a plot-only tile (railButton opts.plotOnly) shows when its script wants it AND you
-- are on your lot (LotClient's OnLot); scripts call this instead of setting Visible
function UIKit.setRailVisible(b, want)
	b:SetAttribute("Want", want == true)
	local player = game:GetService("Players").LocalPlayer
	local onLot = not b:GetAttribute("PlotOnly") or player:GetAttribute("OnLot") == true
	b.Visible = want == true and onLot
	if not b:GetAttribute("LotWired") and b:GetAttribute("PlotOnly") then
		b:SetAttribute("LotWired", true)
		player:GetAttributeChangedSignal("OnLot"):Connect(function() UIKit.setRailVisible(b, b:GetAttribute("Want")) end)
	end
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

local numbered, relabel   -- set when the rail is made (UIKit.rail)
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
		-- v5 critique: a tile never moves once shown. At join, the tiles take their
		-- unlock-order slots; one that appears later in the session goes after every
		-- tile already showing (in a 2-wide grid an insert shifted every tile after it)
		local t0 = os.clock()
		local function watch(c)
			if not c:IsA("GuiObject") then return end
			c:GetPropertyChangedSignal("Visible"):Connect(function()
				if not c.Visible or os.clock() - t0 < 8 or c:GetAttribute("Appended") then return end
				local last = 0
				for _, o in ipairs(f:GetChildren()) do
					if o ~= c and o:IsA("GuiObject") and o.Visible then last = math.max(last, o.LayoutOrder) end
				end
				if c.LayoutOrder < last then c.LayoutOrder = last + 1 end
				c:SetAttribute("Appended", true)
			end)
		end
		f.ChildAdded:Connect(watch)
		-- the column's visible tiles in the order they are drawn, and their number keys
		function numbered()
			local tiles = {}
			for _, c in ipairs(f:GetChildren()) do
				if c:IsA("GuiButton") and c.Visible then table.insert(tiles, c) end
			end
			table.sort(tiles, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
			return tiles
		end
		function relabel()
			for i, c in ipairs(numbered()) do
				local k = c:FindFirstChild("NumKey")
				if k then
					k.Visible = i <= 9
					local lbl = k:FindFirstChild("N")
					if lbl then lbl.Text = tostring(i) end
				end
			end
		end
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
				relabel()
				task.wait(0.5)
			end
		end)
		-- v9 (12 Oct): the number keys open the column's tiles in order (My Restaurant!'s
		-- hotbar); a key fires the tile's Press, the same action as a click (onRailPress)
		local KEYS = { [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4,
			[Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6, [Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.Nine] = 9 }
		game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
			local n = KEYS[input.KeyCode]
			if processed or not n or not g.Enabled then return end
			local tile = numbered()[n]
			local press = tile and tile:FindFirstChild("Press")
			if press then press:Fire() end
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
yOffset) -> a UDim2 at the fitted x, for menus that slide in.
v8 (14 Oct): the scale and x are MenuFit.place (pure, tested); minScale is the
smallest the menu may draw (TEAM: 44 / its 52 px taps), see MenuFit. ]]
function UIKit.fitMenu(panel, w, h, sc, vMargin, minScale)
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
		local right = px + pw - 12
		local pg = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
		local rail = pg and pg:FindFirstChild("Rail")
		local s
		s, x = MenuFit.place({ w = W, h = H, px = px, pw = pw, ph = ph, vMargin = vMargin, floor = minScale,
			railRight = rail and rail.Enabled and UIKit.railRight() or nil })
		local half = W * s / 2
		-- below the money line (screen y 64) when the menu fits there at this
		-- scale; a taller one stays centred rather than shrink (v5 critique: the
		-- BAG header cut the money in half)
		local hh = H * s / 2
		dy = (hh * 2 <= ph - 64 - 8) and math.max(0, (64 + hh) - (ph * base.Scale + base.Offset)) or 0
		-- still reaching above the money line: it slides right, clear of Roblox's
		-- own buttons (top-left, about 196 x 58 on a phone), when it fits there
		if ph * base.Scale + base.Offset + dy - hh < 62 and px + x - half < 204 and 204 + 2 * half <= right then
			x = 204 + half - px
		end
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
	-- v8 (11 Oct, step 5): and when the parent itself resizes. ViewportSize changes
	-- first and the ScreenGui's AbsoluteSize a frame later, so a refit on the first
	-- alone measured the OLD width: after a window resize (1074 to 1917 wide, in
	-- Studio's simulator) the quest card stayed centred on x 532, not 958.
	local par = panel.Parent
	if par and par:IsA("GuiBase2d") then par:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit) end
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
	local t = UIKit.heading(b, "", UIKit.TYPE.caption, UIKit.TEXT, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 1, ZIndex = button.ZIndex + 6 })
	return b, t
end

--[[ v8 (11 Oct) ONE LOUD THING ON THE RAIL.

The UI audit's first screenshot: seven identical tiles down the left, four
of them flagged at once (BAG 2, PHONE 5, DAILY !, and DECOR's "B" key cap,
which read as a fourth badge). When everything is flagged, nothing is.

Two rules now.
  * The rail holds four tiles: BUILD, BAG, PHONE and MORE. The tiles you open
    now and then (INDEX, DECOR, DAILY, TELL US) sit in a tray that MORE opens:
    railButton(..., { tray = true }). MORE shows while any of them would.
  * A red badge means "you can do something here right now", and only ONE
    shows at a time: the most urgent (lowest rank). Another tile with
    something to do gets a small ink dot instead. News you can only look at
    (a new Index entry, kind "look") never reaches the rail: it shows on its
    tile inside the tray. A tray tile's "act" badge lifts onto MORE.
A rail badge is made with UIKit.railBadge(tile, kind, rank) and switched with
UIKit.setBadge(badge, on, text), never by setting Visible: the referee decides
what actually shows. ]]
local railBadges = {}      -- badge -> { tile, text, kind, rank, want, label }
local moreBadge, moreBadgeText
local arbitrate            -- forward: the tray and the badges call each other

local function trayOf()
	local pg = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
	local g = pg and pg:FindFirstChild("Rail")
	return g and g:FindFirstChild("Tray"), g
end

local function setOpenTray(on)
	local tray, g = trayOf()
	if not tray then return end
	local more = g.Column:FindFirstChild("MoreButton")
	if on and more then
		-- beside MORE, top edges level, in the rail gui's own space
		local a = more.AbsolutePosition - g.AbsolutePosition
		tray.Position = UDim2.fromOffset(a.X + more.AbsoluteSize.X + 10, a.Y - 8)
	end
	tray.Visible = on == true
	-- open, it is the thing you are using: above the quest card (DisplayOrder 9),
	-- and the quest card steps aside (on a phone the tray reaches across it)
	g.DisplayOrder = tray.Visible and 11 or 5
	game:GetService("Players").LocalPlayer:SetAttribute("RailTrayOpen", tray.Visible or nil)
	if more then UIKit.setRailActive(more, tray.Visible) end
	arbitrate()
end
UIKit.setTrayOpen = setOpenTray

function UIKit.railTray()
	local col = UIKit.rail()
	local g = col.Parent
	local tray = g:FindFirstChild("Tray")
	if tray then return tray end
	-- ZIndex stays 1: this gui sorts globally, and a higher card drew over its own tiles.
	-- NoAutoScale: its tiles match the rail column's (which its FitScale already keeps at 1)
	tray = UIKit.card(g, {
		Name = "Tray", Size = UDim2.new(0, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.XY, Visible = false,
	}, { radius = UIKit.RADIUS.lg, stroke = UIKit.INK_SOFT })
	tray:SetAttribute("NoAutoScale", true)
	local pad = Instance.new("UIPadding", tray)
	pad.PaddingLeft = UDim.new(0, 8); pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 16); pad.PaddingBottom = UDim.new(0, 12)    -- 16: room for the icons that pop above a tile
	local row = Instance.new("UIListLayout", tray)
	row.FillDirection = Enum.FillDirection.Horizontal
	row.Padding = UDim.new(0, 14)   -- a badge pokes 8 px right of a tile, DECOR's key cap 6 px left
	row.SortOrder = Enum.SortOrder.LayoutOrder

	local more = UIKit.railButton("more", "MORE", UIKit.INK_SOFT, {
		Name = "MoreButton", LayoutOrder = 90, Size = UDim2.new(0, UIKit.RAIL, 0, UIKit.RAIL), Visible = false,
	})
	moreBadge, moreBadgeText = UIKit.badge(more)
	UIKit.onRailPress(more, function() setOpenTray(not tray.Visible) end)

	-- MORE shows while any tile in the tray does; a tile tapped closes the tray
	local function syncMore()
		local any = false
		for _, c in ipairs(tray:GetChildren()) do
			if c:IsA("GuiButton") and c.Visible then any = true break end
		end
		more.Visible = any
		if not any and tray.Visible then setOpenTray(false) end
		arbitrate()
	end
	tray.ChildAdded:Connect(function(c)
		if not c:IsA("GuiButton") then return end
		c:GetPropertyChangedSignal("Visible"):Connect(syncMore)
		c.Activated:Connect(function() setOpenTray(false) end)
		syncMore()
	end)
	-- a menu opening, or a tap anywhere else, closes it
	UIKit.onMenuChange(function(open) if open and tray.Visible then setOpenTray(false) end end)
	game:GetService("UserInputService").InputBegan:Connect(function(input)
		if not tray.Visible then return end
		local t = input.UserInputType
		if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
		local p = Vector2.new(input.Position.X, input.Position.Y)   -- the same space as AbsolutePosition
		local function inside(o)
			local a, s = o.AbsolutePosition, o.AbsoluteSize
			return p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y
		end
		if not inside(tray) and not inside(more) then setOpenTray(false) end
	end)
	return tray
end

-- the tile to point at for a rail button by name: the tile itself, or MORE
-- while it sits in the closed tray (the coach's arrow, a hire flying to INDEX)
function UIKit.railTarget(name)
	local tray, g = trayOf()
	if not g then return nil end
	local tile = g:FindFirstChild(name, true)
	if not (tile and tile:IsA("GuiObject")) then return nil end
	if tray and tile:IsDescendantOf(tray) and not tray.Visible then
		local more = g.Column:FindFirstChild("MoreButton")
		return (tile.Visible and more and more.Visible) and more or nil
	end
	return tile
end

-- a short wiggle of a tile's icon (or MORE's, while the tile is in the closed
-- tray): "something new is here", without a badge
function UIKit.railNudge(tile, seconds)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < (seconds or 3) do
			local tray = trayOf()
			local on = (tray and tile:IsDescendantOf(tray) and not tray.Visible) and UIKit.railTarget(tile.Name) or tile
			local ic = on and on:FindFirstChild("Icon")
			if ic then ic.Rotation = 10 * math.sin((os.clock() - t0) * 18) * (((os.clock() - t0) % 1) < 0.5 and 1 or 0) end
			task.wait()
		end
		for _, o in ipairs({ tile, UIKit.railTarget(tile.Name) }) do
			local ic = o and o:FindFirstChild("Icon")
			if ic and not (o.Name == "MoreButton" and o:GetAttribute("RailActive")) then ic.Rotation = 0 end
		end
	end)
end

function UIKit.railBadge(tile, kind, rank)
	local b, t = UIKit.badge(tile)
	railBadges[b] = { tile = tile, text = t, kind = kind or "act", rank = rank or 5, want = false, label = "" }
	tile:GetPropertyChangedSignal("Visible"):Connect(function() arbitrate() end)
	return b, t
end

function UIKit.setBadge(b, on, text)
	local e = railBadges[b]
	if not e then
		b.Visible = on == true
		local t = b:FindFirstChildWhichIsA("TextLabel")
		if t and text then t.Text = text end
		return
	end
	e.want, e.label = on == true, text or e.label
	arbitrate()
end

-- full: the red count badge; dot: the quiet "also here" mark
local function paintBadge(b, t, mode, label)
	b.Visible = mode ~= nil
	if not mode then return end
	local dot = mode == "dot"
	b.Size = dot and UDim2.new(0, 12, 0, 12) or UDim2.new(0, 24, 0, 24)
	b.Position = dot and UDim2.new(1, -8, 0, 8) or UDim2.new(1, -4, 0, 4)
	b.BackgroundColor3 = dot and UIKit.INK_SOFT or UIKit.RED
	t.Visible = not dot
	t.Text = label or ""
end

arbitrate = function()
	local tray = trayOf()
	local function inTray(e) return tray ~= nil and e.tile:IsDescendantOf(tray) end
	-- what MORE carries: the most urgent "act" badge among the tray's tiles
	local lift
	for _, e in pairs(railBadges) do
		if inTray(e) and e.want and e.kind == "act" and e.tile.Visible and (not lift or e.rank < lift.rank) then lift = e end
	end
	-- the one red badge on the rail
	local best
	for _, e in pairs(railBadges) do
		if not inTray(e) and e.want and e.kind == "act" and e.tile.Visible and (not best or e.rank < best.rank) then best = e end
	end
	if lift and not (tray and tray.Visible) and (not best or lift.rank < best.rank) then best = lift end
	for b, e in pairs(railBadges) do
		if inTray(e) then
			-- inside the open tray every tile tells its own news
			paintBadge(b, e.text, (e.want and tray.Visible) and "full" or nil, e.label)
		elseif e.want and e.kind == "act" and e.tile.Visible then
			paintBadge(b, e.text, (e == best) and "full" or "dot", e.label)
		else
			paintBadge(b, e.text, nil)
		end
	end
	if moreBadge then
		local mode = (lift and not tray.Visible) and ((best == lift) and "full" or "dot") or nil
		paintBadge(moreBadge, moreBadgeText, mode, lift and lift.label)
	end
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
	local t = UIKit.label(head, title or "", UIKit.TYPE.title, UIKit.TEXT, {
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
		--[[ v8 (11 Oct, UI step 5): the tap target is 52 px, the round button you
			see is 44 inside it. On a phone a menu shrinks to fit (fitMenu) and a
			44 px close measured 41-42 px (Daily, Apartments): under the floor. ]]
		close.AnchorPoint = Vector2.new(1, 0.5)
		close.Position = UDim2.new(1, -4, 0.5, -1)
		close.Size = UDim2.new(0, 52, 0, 52)
		close.BackgroundTransparency = 1
		close.ZIndex = 3
		close.Parent = head
		local disc = Instance.new("Frame")
		disc.Name = "Disc"
		disc.AnchorPoint = Vector2.new(0.5, 0.5)
		disc.Position = UDim2.new(0.5, 0, 0.5, 0)
		disc.Size = UDim2.new(0, 44, 0, 44)
		disc.BackgroundColor3 = UIKit.PAPER
		disc.ZIndex = 3
		disc.Parent = close
		Instance.new("UICorner", disc).CornerRadius = UDim.new(1, 0)
		local cs = Instance.new("UIStroke", disc)
		cs.Color = UIKit.deep(accent)
		cs.Thickness = 2.5
		UIKit.icon(disc, "cross", 20, UIKit.INK_SOFT, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), ZIndex = 4 })
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
UIKit.MENUS = { "Phone", "Daily", "Bag", "TalentIndex", "Lift", "Apartments", "Dealer", "Ranks", "WaferBuild", "Team" }

-- v5: is a menu, or a decision card (ModalOpen: spin-off, while-away), on
-- screen? The HUD's own buttons step aside for it: one thing at a time, and a
-- tap can't land on a button showing through under the menu
function UIKit.menuOpen()
	local p = game:GetService("Players").LocalPlayer
	if p:GetAttribute("ModalOpen") then return true end
	local pg = p:FindFirstChild("PlayerGui")
	for _, n in ipairs(UIKit.MENUS) do
		local g = pg and pg:FindFirstChild(n)
		if g and g:IsA("ScreenGui") and g.Enabled then return true end
	end
	return false
end
-- fn(open) runs whenever that changes (one shared watch for every script)
local menuWatchers
function UIKit.onMenuChange(fn)
	if not menuWatchers then
		menuWatchers = {}
		task.spawn(function()
			local was = false
			while true do
				task.wait(0.15)
				local now = UIKit.menuOpen()
				if now ~= was then
					was = now
					for _, f in ipairs(menuWatchers) do task.spawn(f, now) end
				end
			end
		end)
	end
	table.insert(menuWatchers, fn)
end

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


-- ============ ONE SCALE FOR EVERY SCREEN (v7) ============
--[[
	Why this exists. The UI was authored in fixed pixels: 331 hardcoded sizes
	against 131 proportional ones. A 440-pixel panel is 34% of a 1280 desktop and
	55% of an 801 phone, so the layout genuinely was a different layout per device,
	and the per-menu fit hacks only kicked in once something already overflowed.

	This puts ONE scale on every screen, driven by the viewport, so the whole UI
	shrinks and grows as a single piece.

	The curve is deliberately not linear. Straight proportional scaling would put
	phone text at 8px, so small screens get proportionally larger UI -- which is
	what every shipped mobile game does. The goal is not zero drift between
	devices (that is unreachable without unreadable text); it is that everything
	drifts TOGETHER instead of some elements moving and others staying put.

	REF is the resolution the UI is authored at. Do not change it without
	re-measuring every screen.
]]
local REF_Y = 720
--[[ v8 (11 Oct, UI step 5): the floor was 0.66, so on a phone (381 tall in the
	simulator) a 14 px label drew at 9.7 px and the bottom toast at 10.9. 0.86 keeps
	the smallest text (TYPE.caption 14) at 12 px on a phone, which the doctor checks.
	Most of the HUD carries its own UIScale first and never took this one anyway:
	a frame honours one UIScale, the first child. ]]
local AUTO_MIN, AUTO_MAX = 0.86, 1.30
local AUTO_TAG = "SVAutoScale"

-- set false to turn the whole system off and get v5 behaviour back
UIKit.AUTO_SCALE = true

function UIKit.scaleFor(vp)
	vp = vp or workspace.CurrentCamera.ViewportSize
	local raw = vp.Y / REF_Y
	-- ^0.6 bends the curve: a half-height screen gets 0.66x UI, not 0.5x
	local s = raw ^ 0.6
	-- a narrow screen still has to fit the widest panel, so width can veto
	s = math.min(s, vp.X / 1000)
	return math.clamp(s, AUTO_MIN, AUTO_MAX)
end

-- A full-screen child (letterbox bars, fades, the touch reticle layer) must NOT
-- scale: shrinking a 1x1 black frame leaves the world showing around the edges.
-- v8 (11 Oct): or one that spans the whole width or height, a letterbox bar or an
-- edge band. Measured: the cutscene's letterbox bars ended at 70% of the screen
-- width (750 of 1074 px) and the chase's red edges were cut short the same way.
-- A band is sized in scale only (no pixel offsets): the rail and the right column
-- are full height too, but in pixels, and they still scale.
local function fullScreen(o)
	local w, h = o.Size.Width.Scale, o.Size.Height.Scale
	local band = o.Size.Width.Offset == 0 and o.Size.Height.Offset == 0 and (w >= 0.99 or h >= 0.99)
	return (w >= 0.9 and h >= 0.9) or band
end

local function applyTo(child, s)
	if not child:IsA("GuiObject") or child:GetAttribute("NoAutoScale") then return end
	if fullScreen(child) then
		local old = child:FindFirstChild(AUTO_TAG)
		if old then old:Destroy() end
		return
	end
	local sc = child:FindFirstChild(AUTO_TAG)
	if not sc then
		sc = Instance.new("UIScale")
		sc.Name = AUTO_TAG
		sc.Parent = child
	end
	sc.Scale = s
end

local function applyGui(gui, s)
	if not gui:IsA("ScreenGui") then return end
	for _, c in ipairs(gui:GetChildren()) do applyTo(c, s) end
	if not gui:GetAttribute("SVAutoWired") then
		gui:SetAttribute("SVAutoWired", true)
		gui.ChildAdded:Connect(function(c)
			task.defer(applyTo, c, UIKit.scaleFor())
		end)
	end
end

local autoStarted = false
function UIKit.autoScale()
	if autoStarted or not UIKit.AUTO_SCALE then return end
	autoStarted = true

	local pg = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	local cam = workspace.CurrentCamera

	local function sweep()
		local s = UIKit.scaleFor()
		for _, g in ipairs(pg:GetChildren()) do applyGui(g, s) end
	end

	sweep()
	pg.ChildAdded:Connect(function() task.defer(sweep) end)
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(sweep)
	-- a device rotation fires ViewportSize before the safe-insets settle
	task.delay(0.5, sweep)
end

-- start it as soon as anything requires UIKit on the client
if game:GetService("RunService"):IsClient() then
	task.defer(UIKit.autoScale)
end

return UIKit
