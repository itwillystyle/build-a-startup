--[[
	IndexClient -- LocalScript in StarterPlayer -> StarterPlayerScripts.

	TALENT INDEX. Tizzy's last block is the long-term collection, and the
	collectible already exists (the rare hire). Steal An Egg puts its Index
	behind one button with a red count badge; this is that, for people.

	5 roles (rows) x 5 talents (columns) = 25 entries, filled when you have
	ever hired that role at that talent. The server owns the list (player
	attribute "IndexData", saved) and the badge ("IndexNew"); opening the Index
	clears the badge.

	v3.1 (25 Sep reviews): a collection needs a REASON and a NEXT STEP.
	  - every full row or column pays +5% money forever (RoomEconomy.indexMult,
	    10 lines = +50%); the bonus and the nearest line are on the panel
	  - column heads say what a talent is worth and how rare it is
	    ("STAR  x2.5  1 in 25"), because the odds ARE the chase
	  - rows use an icon and neutral text; the old role colours were the same
	    blue/green/gold as the talent colours, so a cell's colour meant two things
	  - locked cells show a faded silhouette, not a "?". Tap one to learn where
	    that hire comes from.
	  - light menu, 14 px minimum text
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local seen = ReplicatedStorage:WaitForChild("SVRemotes"):WaitForChild("IndexSeen", 30)

local LINE_BONUS = 5    -- % money per full row or column (RoomEconomy.INDEX_STEP)

local ROLES = {   -- StaffRig.ROLES
	{ key = "engineer",  name = "Engineer" },
	{ key = "designer",  name = "Designer" },
	{ key = "sales",     name = "Sales" },
	{ key = "recruiter", name = "Recruiter" },
	{ key = "research",  name = "Researcher" },
}
local TALENTS = {  -- SiliconCore TALENT (odds = 1 in N hires)
	{ name = "REGULAR", mult = "x1",   odds = "common",    color = Color3.fromRGB(172, 180, 196),
		where = "Every hire can be Regular." },
	{ name = "SKILLED", mult = "x1.5", odds = "1 in 5",    color = Color3.fromRGB(90, 210, 130),
		where = "1 in 5 hires. Or recruit from the SKILLED spot down the street." },
	{ name = "STAR",    mult = "x2.5", odds = "1 in 25",   color = Color3.fromRGB(90, 170, 255),
		where = "1 in 25 hires. The STAR spot down the street opens at HQ 2." },
	{ name = "GENIUS",  mult = "x5",   odds = "1 in 150",  color = Color3.fromRGB(190, 120, 255),
		where = "1 in 150 hires. The GENIUS spot at the far end opens at HQ 3." },
	{ name = "UNICORN", mult = "x12",  odds = "1 in 1,491", color = Color3.fromRGB(255, 208, 70),
		where = "1 in 1,491. Pure luck, on any hire." },
}

-- ============ THE BUTTON (left rail, second) ============

local btn = UIKit.railButton("grid", "INDEX", UIKit.BLUE, {
	Name = "IndexButton", LayoutOrder = 4, Size = UDim2.new(0, UIKit.RAIL, 0, UIKit.RAIL), Visible = false,
}, { iconSize = 28 })
local badge, badgeText = UIKit.badge(btn)

-- ============ THE PANEL ============

local gui = Instance.new("ScreenGui")
gui.Name = "TalentIndex"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 12
gui.Enabled = false
UIKit.safe(gui)
gui.Parent = player:WaitForChild("PlayerGui")

-- LANDSCAPE LAYOUT (v5). A phone held sideways is 360-390 px tall and every
-- menu taller than that is scaled down (the v4 Index shrank its 14 px words to
-- 11 px). So: 46 px rows, column heads that are the talent's own pill (sized so
-- the longest name fits at 14 px) with its worth under it, the odds on tap
-- instead of in a legend, and the reward in a short side column.
local CELL_W, CELL_H, GAP, ROW_W = 62, 46, 4, 124
local PILL_H, MULT_H = 24, 18
local COLHEAD_H = PILL_H + 2 + MULT_H + 6
local GRID_W = ROW_W + 5 * (CELL_W + GAP)
-- v5: 136 wide (measured: its widest line, "+5% money" at 24, is 109 px) so the
-- whole Index is 630 and fits beside a phone's 2-wide rail at full size (at 196
-- it had to shrink to 0.91, taking the 14 px words under 13)
local SIDE_W, SIDE_GAP = 136, 12
local HEAD_H = 48
local W = GRID_W + SIDE_GAP + SIDE_W + 28
local H = HEAD_H + 10 + COLHEAD_H + 5 * (CELL_H + GAP) + 10

local panel, body, close, title = UIKit.menu(gui, "TALENT INDEX", UIKit.BLUE, {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0, W, 0, H),
}, { headerHeight = HEAD_H })
body.Position = UDim2.new(0, 14, 0, HEAD_H + 10)
body.Size = UDim2.new(1, -28, 1, -(HEAD_H + 20))
local fit = Instance.new("UIScale", panel)   -- shrink to fit a small phone (only below ~360 px tall)
UIKit.fitMenu(panel, W, H, fit, 16)   -- v5: the shared rule (clears the rail, scales to fit)

local count = UIKit.label(panel:FindFirstChild("Header"), "0 / 25", 22, UIKit.TEXT, {
	Name = "Count", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -62, 0.5, -1), Size = UDim2.new(0, 90, 0, 28),
	TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3,
}, UIKit.HEAD)
UIKit.paintLabel(count, UIKit.BLUE)

-- column heads: the talent's pill, then what it is worth; a full column ticks its pill
local colChecks = {}
for c, t in ipairs(TALENTS) do
	local x = ROW_W + (c - 1) * (CELL_W + GAP)
	local pill = Instance.new("Frame")
	pill.Name = "Head_" .. t.name
	pill.Position = UDim2.new(0, x, 0, 0)
	pill.Size = UDim2.new(0, CELL_W, 0, PILL_H)
	pill.BackgroundColor3 = t.color
	pill.BorderSizePixel = 0
	pill.Parent = body
	Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)
	local ps = Instance.new("UIStroke", pill)
	ps.Color = UIKit.darker(t.color, 0.6)
	ps.Thickness = 2
	ps.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	UIKit.label(pill, t.name, 14, UIKit.INK, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center }, UIKit.HEAD)
	UIKit.label(body, t.mult .. " money", 14, UIKit.GREEN_DEEP, {
		Position = UDim2.new(0, x - 4, 0, PILL_H + 2), Size = UDim2.new(0, CELL_W + 8, 0, MULT_H), TextXAlignment = Enum.TextXAlignment.Center,
	}, UIKit.BODY)
	colChecks[c] = UIKit.art(pill, "check", 26, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -2, 0, 2), ZIndex = 3, Visible = false })
end

local cells = {}
local rowChecks = {}
local hint     -- assigned below; cell taps write to it
local showHint
for r, role in ipairs(ROLES) do
	local y = COLHEAD_H + (r - 1) * (CELL_H + GAP)
	UIKit.icon(body, UIKit.ROLE_ICON[role.key] or "person", 24, UIKit.INK_SOFT, {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0, y + CELL_H / 2),
	})
	UIKit.label(body, role.name, 16, UIKit.INK, {
		Position = UDim2.new(0, 30, 0, y), Size = UDim2.new(0, ROW_W - 34, 0, CELL_H), TextTruncate = Enum.TextTruncate.AtEnd,
	}, UIKit.HEAD)
	rowChecks[r] = UIKit.art(body, "check", 26, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, ROW_W - 12, 0, y + 10), ZIndex = 3, Visible = false,
	})
	for c, t in ipairs(TALENTS) do
		local cell = Instance.new("TextButton")
		cell.Name = role.key .. ":" .. c
		cell.Text = ""
		cell.AutoButtonColor = false
		cell.Position = UDim2.new(0, ROW_W + (c - 1) * (CELL_W + GAP), 0, y)
		cell.Size = UDim2.new(0, CELL_W, 0, CELL_H)
		cell.BackgroundColor3 = UIKit.SURFACE_2
		cell.BorderSizePixel = 0
		cell.Parent = body
		Instance.new("UICorner", cell).CornerRadius = UDim.new(0, UIKit.RADIUS.md)
		local st = Instance.new("UIStroke", cell)
		st.Thickness = 2
		st.Color = UIKit.CARD_LINE
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		local ic = UIKit.icon(cell, UIKit.ROLE_ICON[role.key] or "person", 26, UIKit.CARD_MUTED, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		})
		local sc = Instance.new("UIScale", cell)
		cells[cell.Name] = { frame = cell, stroke = st, icon = ic, talent = t, role = role }
		cell.MouseButton1Down:Connect(function()
			UIKit.sfx("tap")
			sc.Scale = 0.92
			TweenService:Create(sc, TweenInfo.new(0.18, Enum.EasingStyle.Quint), { Scale = 1 }):Play()
		end)
		cell.MouseButton1Click:Connect(function()
			local on = cells[cell.Name].on
			if on then
				showHint(("You have a %s %s. %s money."):format(t.name, string.upper(role.name), t.mult), t.color)
			else
				showHint(("%s %s: %s"):format(t.name, string.upper(role.name), t.where), t.color)
			end
		end)
	end
end

-- the side column: what the collection pays you now, and the next line to finish
local side = Instance.new("Frame")
side.Name = "Side"
side.Position = UDim2.new(0, GRID_W + SIDE_GAP, 0, 0)
side.Size = UDim2.new(0, SIDE_W, 1, 0)
side.BackgroundColor3 = UIKit.CARD
side.BorderSizePixel = 0
side.Parent = body
Instance.new("UICorner", side).CornerRadius = UDim.new(0, UIKit.RADIUS.md)
local sst = Instance.new("UIStroke", side)
sst.Color = UIKit.CARD_LINE
sst.Thickness = 2
local spad = Instance.new("UIPadding", side)
spad.PaddingLeft, spad.PaddingRight, spad.PaddingTop = UDim.new(0, 12), UDim.new(0, 12), UDim.new(0, 12)
UIKit.label(side, "EVERY FULL LINE", 14, UIKit.MUTED_TEXT, { Size = UDim2.new(1, 0, 0, 18) }, UIKit.HEAD)
UIKit.outlined(side, ("+%d%% money"):format(LINE_BONUS), 24, UIKit.MONEY, { Position = UDim2.new(0, 0, 0, 20), Size = UDim2.new(1, 0, 0, 32) })
local bonus = UIKit.label(side, "", 16, UIKit.GREEN_DEEP, {
	Name = "Bonus", Position = UDim2.new(0, 0, 0, 58), Size = UDim2.new(1, 0, 0, 22),
}, UIKit.HEAD)
local rule = Instance.new("Frame")
rule.BackgroundColor3 = UIKit.LINE_LIGHT
rule.BorderSizePixel = 0
rule.Position = UDim2.new(0, 0, 0, 88)
rule.Size = UDim2.new(1, 0, 0, 2)
rule.Parent = side
hint = UIKit.label(side, "", 16, UIKit.INK_SOFT, {
	Name = "Hint", Position = UDim2.new(0, 0, 0, 100), Size = UDim2.new(1, 0, 1, -112),
	TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
}, UIKit.BODY)

-- ============ STATE ============

local nextLine = ""
local hintSerial = 0
local hintActive = false
showHint = function(text, color)
	hintSerial += 1
	local mine = hintSerial
	hintActive = true
	hint.Text = text
	hint.TextColor3 = color and UIKit.darker(color, 0.55) or UIKit.BLUE_DEEP
	task.delay(5, function()
		if hintSerial == mine then
			hintActive = false
			hint.Text = nextLine
			hint.TextColor3 = UIKit.INK_SOFT
		end
	end)
end

local function refresh()
	local have = {}
	local n = 0
	for key in string.gmatch(player:GetAttribute("IndexData") or "", "[^,]+") do
		if not have[key] then have[key] = true; n += 1 end
	end
	for key, c in pairs(cells) do
		local on = have[key] == true
		c.on = on
		c.frame.BackgroundColor3 = on and c.talent.color or UIKit.SURFACE_2
		c.stroke.Color = on and UIKit.darker(c.talent.color, 0.6) or UIKit.CARD_LINE
		c.icon.ImageColor3 = on and UIKit.INK or UIKit.CARD_MUTED
		c.icon.ImageTransparency = on and 0 or 0.6
	end
	-- full rows and columns (the server counts the same way: RoomEconomy.indexLines)
	local lines = 0
	local best, bestMissing = nil, math.huge
	for r, role in ipairs(ROLES) do
		local missing = 0
		for c = 1, #TALENTS do if not have[role.key .. ":" .. c] then missing += 1 end end
		rowChecks[r].Visible = missing == 0
		if missing == 0 then lines += 1
		elseif missing < bestMissing then best, bestMissing = ("the %s row"):format(string.upper(role.name)), missing end
	end
	for c, t in ipairs(TALENTS) do
		local missing = 0
		for _, role in ipairs(ROLES) do if not have[role.key .. ":" .. c] then missing += 1 end end
		colChecks[c].Visible = missing == 0
		if missing == 0 then lines += 1
		elseif missing < bestMissing then best, bestMissing = ("the %s column"):format(t.name), missing end
	end
	count.Text = ("%d / 25"):format(n)
	bonus.Text = lines > 0 and ("You have +%d%%"):format(lines * LINE_BONUS) or "No full lines yet"
	nextLine = best and ("%d more to finish %s."):format(bestMissing, best)
		or "Every line is full. You found them all!"
	if not hintActive then hint.Text = nextLine end
	btn.Visible = n > 0
	local new = player:GetAttribute("IndexNew") or 0
	badge.Visible = new > 0 and not gui.Enabled
	badgeText.Text = new > 9 and "9+" or tostring(new)
end
refresh()
player:GetAttributeChangedSignal("IndexData"):Connect(refresh)
player:GetAttributeChangedSignal("IndexNew"):Connect(refresh)

local function setOpen(v)
	if v then UIKit.solo(gui) end
	gui.Enabled = v
	if v then
		if seen then seen:FireServer() end
	end
	refresh()
end
btn.MouseButton1Click:Connect(function() setOpen(not gui.Enabled) end)
if close then close.MouseButton1Click:Connect(function() setOpen(false) end) end
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Q and gui.Enabled then setOpen(false) end
end)

-- v5: the rail tile shows when this menu is open
UIKit.bindRail(btn, gui)
