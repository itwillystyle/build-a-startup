--[[
	ValleyClient -- the other five founders, drawn (v4.9).

	Reads the plot attributes Valley.lua publishes and puts ONE board over
	every occupied tower: the company's name, how tall they have built, what
	they are worth, and where they stand in this server right now.

	Why a world board and not a menu. The hub already has a ticker, but it
	shows the ALL-TIME GLOBAL top ten out of a DataStore -- it answers "who
	is the best player of this game ever", which is a question nobody in a
	six-person server is asking. The question they are asking is "how am I
	doing against the five people I can see", and the honest place to answer
	that is on the buildings themselves, because the buildings are already
	the scoreboard: a tower's height IS its owner's progress. All this does
	is put a number and a name on something the player can already see.

	Sized in STUDS (BillboardGui's Scale component is studs, not pixels) so
	it stays readable from across the campus instead of shrinking to a dot.

	Note for future me: BillboardGui.MaxDistance is measured from
	camera.Focus, not the camera -- a detached Scriptable camera makes these
	appear and vanish at the wrong range during a cutscene. That is expected.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local PAPER = Color3.fromRGB(243, 239, 230)
local INK = Color3.fromRGB(30, 37, 48)
local GOLD = Color3.fromRGB(255, 194, 61)
local GREEN = Color3.fromRGB(64, 170, 96)
local MUTED = Color3.fromRGB(120, 126, 136)

local boards = {}             -- plot folder -> { part, gui, ... }
local crown                   -- the current round winner's marker

local function money(n)
	n = math.floor(tonumber(n) or 0)
	for _, u in ipairs({ { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }) do
		if n >= u[1] then
			return ("$%s%s"):format((("%.1f"):format(n / u[1])):gsub("%.0$", ""), u[2])
		end
	end
	return "$" .. n
end

--[[ The top of what this founder has actually built. The Wafers model is the
	building; before anything is built it is just the garage, so fall back to a
	height that clears the roof rather than burying the board in it. ]]
local function towerTop(folder)
	--[[ MEASURED THE HARD WAY: plot.Wafers is a FOLDER, not a Model, so an
		IsA("Model") test is false and GetBoundingBox does not exist on it.
		The first draft silently fell through to the garage-roof fallback, which
		would have pinned every board at 16 studs no matter how tall the tower
		got. Walk the parts instead. ]]
	local w = folder:FindFirstChild("Wafers")
	local top
	if w then
		for _, d in ipairs(w:GetDescendants()) do
			if d:IsA("BasePart") then
				local y = d.Position.Y + d.Size.Y / 2
				if not top or y > top then top = y end
			end
		end
	end
	local pivot = folder:GetAttribute("Pivot")
	local floor = (pivot and pivot.Position.Y or 0)
	return math.max(top or 0, floor + 16)
end

local function makeBoard(folder)
	local part = Instance.new("Part")
	part.Name = "SVFounderBoard"
	part.Size = Vector3.new(1, 1, 1)
	part.Transparency = 1
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.CastShadow = false
	part.Parent = workspace

	local gui = Instance.new("BillboardGui")
	gui.Name = "FounderBoard"
	gui.Size = UDim2.fromScale(58, 19)        -- studs, not pixels
	gui.StudsOffsetWorldSpace = Vector3.new(0, 14, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 1400
	gui.LightInfluence = 0
	gui.Parent = part

	local card = Instance.new("Frame")
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = PAPER
	card.BorderSizePixel = 0
	card.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 3
	stroke.Transparency = 0.15
	stroke.Parent = card

	local rank = Instance.new("TextLabel")
	rank.Size = UDim2.fromScale(0.2, 0.52)
	rank.Position = UDim2.fromScale(0.035, 0.1)
	rank.BackgroundColor3 = GOLD
	rank.BorderSizePixel = 0
	rank.Font = Enum.Font.FredokaOne
	rank.TextScaled = true
	rank.TextColor3 = INK
	rank.Text = "#1"
	rank.Parent = card
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(0, 12)
	rc.Parent = rank

	local name = Instance.new("TextLabel")
	name.Size = UDim2.fromScale(0.73, 0.5)
	name.Position = UDim2.fromScale(0.25, 0.08)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextColor3 = INK
	name.Text = ""
	name.Parent = card

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.fromScale(0.93, 0.34)
	sub.Position = UDim2.fromScale(0.035, 0.6)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextColor3 = MUTED
	sub.Text = ""
	sub.Parent = card

	return { part = part, gui = gui, card = card, rank = rank, name = name, sub = sub }
end

local function redraw(folder)
	local owner = folder:GetAttribute("OwnerId")
	local b = boards[folder]
	if not owner then
		if b then b.part:Destroy(); boards[folder] = nil end
		return
	end
	if not b then
		b = makeBoard(folder)
		boards[folder] = b
	end
	local pivot = folder:GetAttribute("Pivot")
	if pivot then
		b.part.CFrame = CFrame.new(pivot.Position.X, towerTop(folder), pivot.Position.Z)
	end
	local company = folder:GetAttribute("Company")
	if not company or company == "" then company = "A NEW STARTUP" end
	local mine = owner == player.UserId
	b.name.Text = string.upper(company)
	b.name.TextColor3 = mine and Color3.fromRGB(28, 96, 168) or INK
	local r = folder:GetAttribute("Rank") or 0
	b.rank.Text = r > 0 and ("#" .. r) or "--"
	b.rank.BackgroundColor3 = r == 1 and GOLD or Color3.fromRGB(214, 210, 200)

	local lvl = folder:GetAttribute("Level") or 1
	local val = folder:GetAttribute("Valuation") or 0
	local gain = folder:GetAttribute("BellGain") or 0
	if gain > 0 then
		b.sub.Text = ("LEVEL %d     %s     +%s"):format(lvl, money(val), money(gain))
		b.sub.TextColor3 = GREEN
	else
		b.sub.Text = ("LEVEL %d     %s%s"):format(lvl, money(val), folder:GetAttribute("Listed") and "     PUBLIC" or "")
		b.sub.TextColor3 = MUTED
	end
end

--[[ The round winner wears it until the next bell. One Neon part and a label:
	the point is that you can see from your own lot who took the last round. ]]
local function setCrown(plots, name)
	if crown then crown:Destroy(); crown = nil end
	if not name or name == "" then return end
	local folder = plots:FindFirstChild(name)
	local pivot = folder and folder:GetAttribute("Pivot")
	if not pivot then return end
	crown = Instance.new("Part")
	crown.Name = "SVRoundCrown"
	crown.Shape = Enum.PartType.Ball
	crown.Size = Vector3.new(7, 7, 7)
	crown.Material = Enum.Material.Neon
	crown.Color = GOLD
	crown.Anchored, crown.CanCollide, crown.CanQuery, crown.CanTouch = true, false, false, false
	crown.CastShadow = false
	crown.CFrame = CFrame.new(pivot.Position.X, towerTop(folder) + 30, pivot.Position.Z)
	crown.Parent = workspace
	local g = Instance.new("BillboardGui")
	g.Size = UDim2.fromScale(44, 9)
	g.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
	g.MaxDistance = 1400
	g.LightInfluence = 0
	g.Parent = crown
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = GOLD
	t.Text = "ROUND WINNER"
	t.Parent = g
	local st = Instance.new("UIStroke")
	st.Color = INK
	st.Thickness = 3
	st.Parent = t
end

task.spawn(function()
	local sv = workspace:WaitForChild("SiliconValley", 60)
	local plots = sv and sv:WaitForChild("Plots", 60)
	if not plots then return end

	local function watch(folder)
		for _, attr in ipairs({ "OwnerId", "Company", "Valuation", "Rank", "Level", "Listed", "BellGain" }) do
			folder:GetAttributeChangedSignal(attr):Connect(function() redraw(folder) end)
		end
		redraw(folder)
	end
	for _, folder in ipairs(plots:GetChildren()) do watch(folder) end
	plots.ChildAdded:Connect(watch)

	plots:GetAttributeChangedSignal("BellWinner"):Connect(function()
		setCrown(plots, plots:GetAttribute("BellWinner"))
	end)
	setCrown(plots, plots:GetAttribute("BellWinner"))

	-- the board sits on top of a building that grows, so follow it
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 2 then return end
		acc = 0
		for folder, b in pairs(boards) do
			local pivot = folder:GetAttribute("Pivot")
			if pivot and b.part.Parent then
				b.part.CFrame = CFrame.new(pivot.Position.X, towerTop(folder), pivot.Position.Z)
			end
		end
		if crown then crown.CFrame = crown.CFrame * CFrame.Angles(0, math.rad(12), 0) end
	end)
end)
