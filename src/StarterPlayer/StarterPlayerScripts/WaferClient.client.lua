--[[ WaferClient (v4.6, the Wafers HQ): the BUILD tile and the next-floor card.

The server says what the next BUILD tap is (player attributes WaferNext / Last /
Price / Rec / Allowed / Need, set with the HQ pad's label). The card shows it:
a new floor lets you pick its department (the guide's pick is pre-selected, so
one tap still builds); below your record it re-lays the rest of a storey the
way you had it, in one tap. The server checks everything (WaferBuild). ]]
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local UIKit = require(RS:WaitForChild("UIKit"))
local remotes = RS:WaitForChild("SVRemotes")
local buildRemote = remotes:WaitForChild("WaferBuild", 60)
if not buildRemote then return end

local DEPTS = {
	eng = { name = "ENGINEERING", short = "ENG", blurb = "+2 seats for engineers and researchers", tint = Color3.fromRGB(150, 188, 232) },
	studio = { name = "DESIGN STUDIO", short = "STUDIO", blurb = "+2 seats for designers, more money", tint = Color3.fromRGB(236, 164, 192) },
	cafe = { name = "CAFE", short = "CAFE", blurb = "+4 seats for sales and recruiters, more output", tint = Color3.fromRGB(246, 176, 116) },
	servers = { name = "SERVER ROOM", short = "SERVERS", blurb = "Bigger launch paydays", tint = Color3.fromRGB(70, 78, 96) },
	labs = { name = "AI LABS", short = "AI LABS", blurb = "+2 seats for researchers, products 15% faster", tint = Color3.fromRGB(122, 214, 198) },
	board = { name = "BOARDROOM", short = "BOARD", blurb = "Investors on your phone start keener (up to 2 boardrooms)", tint = Color3.fromRGB(236, 202, 112) },
	lobby = { name = "LOBBY", short = "LOBBY", blurb = "Your front door: +2 seats", tint = Color3.fromRGB(236, 214, 170) },
}
local ORDER = { "lobby", "eng", "studio", "cafe", "servers", "labs", "board" }
local HOMES = { "STUDIO", "LOFT", "PENTHOUSE" }

local function a(k) return player:GetAttribute(k) end
local function cash()
	local ls = player:FindFirstChild("leaderstats")
	local c = ls and ls:FindFirstChild("Cash")
	return c and c.Value or 0
end

-- ============ THE RAIL TILE ============
local railBtn = UIKit.railButton("build", "BUILD", UIKit.GREEN, {
	Name = "WaferButton", LayoutOrder = 0, Size = UDim2.new(0, UIKit.RAIL, 0, UIKit.RAIL), Visible = false,
}, { iconSize = 28 })

-- ============ THE CARD ============
local gui = Instance.new("ScreenGui")
gui.Name = "WaferBuild"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 12
gui.Enabled = false
UIKit.safe(gui)
gui.Parent = player:WaitForChild("PlayerGui")

local PW, PH = 580, 270
local panel, body, closeBtn = UIKit.menu(gui, "BUILD", UIKit.GREEN, {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 24, 0.5, 0), Size = UDim2.new(0, PW, 0, PH),
}, { headerHeight = 44 })
body.Position = UDim2.new(0, 14, 0, 52)
body.Size = UDim2.new(1, -28, 1, -62)
local fit = Instance.new("UIScale", panel)
UIKit.fitMenu(panel, PW, PH, fit)

local title = UIKit.label(body, "", 20, UIKit.INK, {
	Name = "Title", Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left,
}, UIKit.HEAD)

local row = Instance.new("Frame")
row.Name = "Depts"
row.BackgroundTransparency = 1
row.Position = UDim2.new(0, 0, 0, 34)
row.Size = UDim2.new(1, 0, 0, 92)
row.Parent = body
local rl = Instance.new("UIListLayout", row)
rl.FillDirection = Enum.FillDirection.Horizontal
rl.Padding = UDim.new(0, 8)
rl.SortOrder = Enum.SortOrder.LayoutOrder

local blurb = UIKit.label(body, "", 16, UIKit.INK_SOFT, {
	Name = "Blurb", Position = UDim2.new(0, 0, 0, 132), Size = UDim2.new(1, 0, 0, 40), TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
}, UIKit.BODY)

local buildBtn = UIKit.button(body, "BUILD", UIKit.GREEN, {
	Name = "BuildGo", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.new(0, 220, 0, 52),
}, { textSize = 22 })
local priceLabel = UIKit.label(body, "", 20, UIKit.INK, {
	Name = "Price", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -12), Size = UDim2.new(1, -240, 0, 28),
	TextXAlignment = Enum.TextXAlignment.Left,
}, UIKit.HEAD)

local picked
local tiles = {}

local function render()
	local L, last, price = a("WaferNext") or 0, a("WaferLast") or 0, a("WaferPrice") or 0
	if L <= 0 then return end
	local rebuild = last > L
	local allowed = {}
	for d in string.gmatch(a("WaferAllowed") or "", "[^,]+") do allowed[d] = true end
	for _, t in pairs(tiles) do t:Destroy() end
	tiles = {}
	if not allowed[picked or ""] then picked = a("WaferRec") ~= "" and a("WaferRec") or nil end
	if rebuild then
		title.Text = ("REBUILD LEVELS %d-%d"):format(L, last)
		blurb.Text = ("%d floors from your last company, laid out the way you had them. One tap, a fraction of the price."):format(last - L + 1)
		blurb.Position = UDim2.new(0, 0, 0, 40)
		row.Visible = false
	else
		title.Text = ("LEVEL %d"):format(L)
		row.Visible = next(allowed) ~= nil
		blurb.Position = UDim2.new(0, 0, 0, row.Visible and 132 or 40)
		local n = 0
		for _ in pairs(allowed) do n += 1 end
		local tileW = math.min(104, math.floor((PW - 28 - 8 * (n - 1)) / math.max(n, 1)))
		for i, id in ipairs(ORDER) do
			if allowed[id] then
				local d = DEPTS[id]
				local on = id == picked
				local b = UIKit.button(row, "", on and UIKit.light(UIKit.GREEN) or UIKit.SURFACE_2, {
					Name = "Dept_" .. id, LayoutOrder = i, Size = UDim2.new(0, tileW, 0, 88),
				}, { textSize = 14, silent = true })
				local sw = Instance.new("Frame")
				sw.Name = "Swatch"
				sw.BackgroundColor3 = d.tint
				sw.BorderSizePixel = 0
				sw.AnchorPoint = Vector2.new(0.5, 0)
				sw.Position = UDim2.new(0.5, 0, 0, 8)
				sw.Size = UDim2.new(0, 40, 0, 32)
				sw.ZIndex = b.ZIndex + 1
				sw.Parent = b
				Instance.new("UICorner", sw).CornerRadius = UDim.new(0, 8)
				UIKit.label(b, d.short, 15, UIKit.INK, {
					Name = "Name", Position = UDim2.new(0, 2, 0, 46), Size = UDim2.new(1, -4, 0, 30), ZIndex = b.ZIndex + 1,
					TextXAlignment = Enum.TextXAlignment.Center,
				}, UIKit.HEAD)
				local st = b:FindFirstChildOfClass("UIStroke")
				if st then st.Color = on and UIKit.GREEN or UIKit.INK_SOFT; st.Thickness = on and 3 or 2 end
				b.MouseButton1Click:Connect(function()
					picked = id
					UIKit.sfx("tap")
					render()
				end)
				tiles[id] = b
			end
		end
		local d = picked and DEPTS[picked]
		blurb.Text = d and (d.name .. ": " .. d.blurb .. ((picked == a("WaferRec")) and "  (the guide's pick for your team)" or "")) or "A new piece of your HQ."
	end
	local need = a("WaferNeed") or 0
	if need > 0 then
		priceLabel.Text = UIKit.money(price)
		buildBtn:FindFirstChild("Label").Text = ("NEEDS A %s"):format(HOMES[need] or "HOME")
		UIKit.setButtonColor(buildBtn, UIKit.SURFACE_2)
	elseif cash() < price then
		priceLabel.Text = UIKit.money(price)
		buildBtn:FindFirstChild("Label").Text = "NEED " .. UIKit.money(price - cash())
		UIKit.setButtonColor(buildBtn, UIKit.SURFACE_2)
	else
		priceLabel.Text = UIKit.money(price)
		buildBtn:FindFirstChild("Label").Text = rebuild and "REBUILD" or "BUILD"
		UIKit.setButtonColor(buildBtn, UIKit.GREEN)
	end
end

--[[ ============ THE STYLE PICKER ============

Three buildings, offered once, on the FIRST build -- not on a join screen.
Roblox's own onboarding guidance puts the cost of a join menu at roughly 2-3%
of the new-player cohort per second of non-gameplay, and a three-way choice
between three WORDS before a player has seen any of them is exactly that.

Here they have already spawned, shipped and hired. They tap BUILD, and the
card shows three buildings. The choice is made while looking at the thing it
changes, and the reward is immediate: the next floor goes up in that style.

The server owns whether the offer is still open (HQPathChosen); this card is
only ever an offer. ]]
--[[ Each path's colour is taken OFF THE BUILDING -- the Wafers' garden decks,
the Terrafab's wafer track, the Dome's lit clerestory -- not picked from a
palette. It appears as a thin bar under the name, never as a flood fill: the
building is the content, and a tile washed in colour buries it.

`tag` is one word of character. A sentence is for reading; one word is for
choosing, and this is a choice made in about two seconds. ]]
local PATHS = {
	{ key = "W_", name = "WAFERS",   tag = "GREEN",      blurb = "Stacked rings with garden floors between them",
	  col = Color3.fromRGB(122, 170, 80) },
	{ key = "T_", name = "TERRAFAB", tag = "INDUSTRIAL", blurb = "A chip fab. Your wafers ride the track outside",
	  col = Color3.fromRGB(236, 170, 70) },
	{ key = "D_", name = "DOME",     tag = "LIGHT",      blurb = "Layered canopies with a lit seam at every tier",
	  col = Color3.fromRGB(150, 166, 188) },
}

local pathGui = Instance.new("ScreenGui")
pathGui.Name = "WaferPath"
pathGui.ResetOnSpawn = false
pathGui.IgnoreGuiInset = true
pathGui.DisplayOrder = 13
pathGui.Enabled = false
UIKit.safe(pathGui)
pathGui.Parent = player:WaitForChild("PlayerGui")

local QW, QH = 620, 300
local qPanel, qBody, qClose = UIKit.menu(pathGui, "PICK YOUR BUILDING", UIKit.GOLD or UIKit.GREEN, {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, QW, 0, QH),
}, { headerHeight = 44 })
qBody.Position = UDim2.new(0, 14, 0, 52)
qBody.Size = UDim2.new(1, -28, 1, -62)
UIKit.fitMenu(qPanel, QW, QH, Instance.new("UIScale", qPanel))

UIKit.label(qBody, "You can change it when you spin off.", 15, UIKit.MUTED or UIKit.INK, {
	Name = "Sub", Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0, 0),
	TextXAlignment = Enum.TextXAlignment.Center,
})

local pickRemote = remotes:WaitForChild("WaferPath", 60)

local function openPicker()
	if not pickRemote then return end
	pathGui.Enabled = true
	UIKit.solo(pathGui)
end

for i, def in ipairs(PATHS) do
	local w = 1 / #PATHS
	local tile = UIKit.button(qBody, "", UIKit.PAPER, {
		Name = "Path_" .. def.key:sub(1, 1),
		Size = UDim2.new(w, -10, 0, 196),
		Position = UDim2.new((i - 1) * w, 5, 0, 24),
	})
	local lbl = tile:FindFirstChild("Label")
	if lbl then lbl.Text = "" end

	-- the building gets the top two thirds: it is what is being chosen
	local vpf = Instance.new("ViewportFrame")
	vpf.Name = "Shot"
	vpf.BackgroundColor3 = UIKit.SURFACE_2
	vpf.BackgroundTransparency = 0
	vpf.BorderSizePixel = 0
	vpf.Size = UDim2.new(1, -12, 0, 118)
	vpf.Position = UDim2.new(0, 6, 0, 6)
	vpf.ZIndex = tile.ZIndex + 1
	vpf.Parent = tile
	local vc = Instance.new("UICorner", vpf)
	vc.CornerRadius = UDim.new(0, 10)

	-- the accent bar: the building's own colour, a line not a wash
	local bar = Instance.new("Frame")
	bar.Name = "Accent"
	bar.BackgroundColor3 = def.col
	bar.BorderSizePixel = 0
	bar.Size = UDim2.new(1, -12, 0, 4)
	bar.Position = UDim2.new(0, 6, 0, 128)
	bar.ZIndex = tile.ZIndex + 2
	bar.Parent = tile
	local bc = Instance.new("UICorner", bar)
	bc.CornerRadius = UDim.new(1, 0)

	UIKit.label(tile, def.tag, 11, UIKit.MUTED_TEXT, {
		Name = "Tag", Size = UDim2.new(1, -10, 0, 14), Position = UDim2.new(0, 5, 0, 136),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	UIKit.label(tile, def.name, 19, UIKit.INK, {
		Name = "Name", Size = UDim2.new(1, -10, 0, 24), Position = UDim2.new(0, 5, 0, 150),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	UIKit.label(tile, def.blurb, 12, UIKit.MUTED_TEXT, {
		Name = "Blurb", Size = UDim2.new(1, -14, 0, 30), Position = UDim2.new(0, 7, 0, 172),
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center,
	})

	-- a press state. Without one the card just vanishes and the choice has no
	-- beat; the tile lifts, the accent floods for a moment, then the floor goes up.
	local lift = Instance.new("UIScale", tile)
	tile.MouseEnter:Connect(function()
		TweenService:Create(lift, TweenInfo.new(0.12), { Scale = 1.03 }):Play()
	end)
	tile.MouseLeave:Connect(function()
		TweenService:Create(lift, TweenInfo.new(0.12), { Scale = 1.0 }):Play()
	end)
	tile:SetAttribute("Accent", def.col)
	task.spawn(function()
		local lib = RS:WaitForChild("SVMeshes", 30)
		local tpl = lib and lib:FindFirstChild(def.key .. "Seg_1")
		if not tpl then return end
		local src = tpl:IsA("Model") and tpl:FindFirstChildWhichIsA("MeshPart", true) or tpl
		if not src then return end
		--[[ A segment mesh is centred on its PIECE-LOCAL frame, about 48 studs
		out along +Z -- the ring's radius. Rotating it about the origin without
		pushing it out first stacks all eight segments on top of each other,
		which is exactly what the first draft did: the preview was a speck.

		HQMeta lives in ServerScriptService, so the client cannot read it. These
		are the three Seg_1 offsets, and the camera frames whatever is actually
		built rather than a guessed distance, so a wrong number shows as a badly
		framed tower rather than an empty box. ]]
		local RADIUS = { W_ = 48.414, T_ = 46.194, D_ = 45.577 }
		local world = Instance.new("Model")
		for k = 0, 0 do
			for seg = 1, 8 do
				local c = src:Clone()
				c.Anchored = true
				c.CFrame = CFrame.Angles(0, math.rad((seg - 1) * 45), 0)
					* CFrame.new(0, k * 13, RADIUS[def.key] or 48)
				c.Parent = world
			end
		end

		--[[ THE DECK IS THE WHOLE POINT.

		The first version showed two storeys of plain wall and the three
		previews came out identical -- three grey rings. Everything that tells
		the paths apart lives on the DECK: the Wafers' garden, the Terrafab's
		wafer track, the Dome's canopy. A preview without one is a preview of
		the part they share, which is why it is ONE storey and then the deck:
		two courses of wall only dilute the piece doing the work.

		Deck meshes are centred on their own axis, so no radial push -- only the
		height of the two storeys under them, plus the piece's own y. ]]
		local DECK_Y = { W_ = 2.053, T_ = 5.650, D_ = 9.206 }
		local dtpl = lib:FindFirstChild(def.key .. "Deck_1")
		local dsrc = dtpl and (dtpl:IsA("Model") and dtpl:FindFirstChildWhichIsA("MeshPart", true) or dtpl)
		if dsrc then
			local dc = dsrc:Clone()
			dc.Anchored = true
			dc.CFrame = CFrame.new(0, 13 + (DECK_Y[def.key] or 2), 0)
			dc.Parent = world
		end
		world.Parent = vpf

		local _, size = world:GetBoundingBox()
		local cf = world:GetBoundingBox()
		local centre = cf.Position
		local reach = math.max(size.X, size.Y, size.Z)
		local cam = Instance.new("Camera")
		cam.Parent = vpf
		vpf.CurrentCamera = cam
		-- a slow orbit: a still render reads as a picture of a building, a
		-- turning one reads as the building itself
		-- low and close: a silhouette is read from near eye level. Looking down
		-- on a ring from above flattens every path into the same circle.
		local dist = reach * 0.92
		local t0 = os.clock() + i * 1.3        -- the three tiles are out of phase
		RunService.RenderStepped:Connect(function()
			if not vpf.Visible or not pathGui.Enabled then return end
			local a = (os.clock() - t0) * 0.36
			cam.CFrame = CFrame.lookAt(
				centre + Vector3.new(math.cos(a) * dist, reach * 0.34, math.sin(a) * dist), centre)
		end)
	end)

	tile.MouseButton1Click:Connect(function()
		pickRemote:FireServer(def.key)
		UIKit.sfx("ding", 1.1, 0.5)
		-- the beat: the chosen tile floods with its own colour and the other two
		-- fall back, so the choice is confirmed on screen before the card goes
		for _, other in ipairs(qBody:GetChildren()) do
			if other:IsA("GuiObject") and other.Name:match("^Path_") then
				local sc = other:FindFirstChildOfClass("UIScale")
				if other == tile then
					UIKit.setButtonColor(other, UIKit.light(def.col))
					if sc then TweenService:Create(sc, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.08 }):Play() end
				elseif sc then
					TweenService:Create(sc, TweenInfo.new(0.16), { Scale = 0.94 }):Play()
					other.BackgroundTransparency = 0.4
				end
			end
		end
		task.delay(0.42, function() pathGui.Enabled = false end)
		-- the server builds the floor off the back of this; opening the BUILD
		-- card here would flash a card for something already happening
	end)
end
if qClose then
	qClose.MouseButton1Click:Connect(function()
		-- closing is a choice too: take Wafers and build, so the tap that opened
		-- this still produces a floor. Dead-ending here would read as the BUILD
		-- button being broken.
		pathGui.Enabled = false
		pickRemote:FireServer("W_")
	end)
end

--[[ The SERVER decides when to ask. wafersBuild gates the first floor above
the garage on a style, and fires AskPath instead of charging and building, so
every route into a build gets the question -- the BUILD card, the HQ pad prompt
and its ClickDetector alike. The reply builds that same floor, so a player taps
BUILD once and gets a building.

The card no longer second-guesses it. ]]
local askRemote = remotes:WaitForChild("AskPath", 60)
if askRemote then
	askRemote.OnClientEvent:Connect(function()
		gui.Enabled = false
		openPicker()
	end)
end

local function setOpen(on)
	gui.Enabled = on and (a("WaferNext") or 0) > 0
	if gui.Enabled then
		picked = nil
		render()
		UIKit.solo(gui)
	end
end

buildBtn.MouseButton1Click:Connect(function()
	local L, price = a("WaferNext") or 0, a("WaferPrice") or 0
	if L <= 0 or (a("WaferNeed") or 0) > 0 or cash() < price then
		UIKit.sfx("thunk")
		return
	end
	buildRemote:FireServer(picked)
	UIKit.sfx("ding", 1.1, 0.5)
	gui.Enabled = false
end)
if closeBtn then closeBtn.MouseButton1Click:Connect(function() gui.Enabled = false end) end
railBtn.MouseButton1Click:Connect(function() setOpen(not gui.Enabled) end)
UIKit.bindRail(railBtn, gui)

-- the tile shows once there is a next floor to build; the card follows the server
local function refresh()
	railBtn.Visible = a("Shipped") == true and (a("WaferNext") or 0) > 0
	if not railBtn.Visible then gui.Enabled = false end
	if gui.Enabled then render() end
end
for _, k in ipairs({ "Shipped", "WaferNext", "WaferLast", "WaferPrice", "WaferRec", "WaferAllowed", "WaferNeed" }) do
	player:GetAttributeChangedSignal(k):Connect(refresh)
end
task.spawn(function()
	local ls = player:WaitForChild("leaderstats", 60)
	local c = ls and ls:WaitForChild("Cash", 30)
	if c then c.Changed:Connect(function() if gui.Enabled then render() end end) end
end)
refresh()
