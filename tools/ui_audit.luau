--[[ ui_audit.luau: measure every visible GUI element in PlayerGui (Studio,
Client datamodel, paste into execute_luau). Deterministic half of the UI
critique: the same numbers before and after a pass.

Reports: text under MIN_TEXT px, tap targets under MIN_TAP px, text contrast
(WCAG ratio against the nearest opaque ancestor; floating text with no outline
is flagged), font and colour inventories, overlaps between separate HUD pieces,
anything under Roblox's own top bar, and anything off screen. ]]

local MIN_TEXT, MIN_TAP, MIN_CONTRAST = 14, 44, 4.5
local SKIP = { Freecam = true, ProximityPrompts = true, LiftFade = true, Cinema = true, BubbleChat = true, TouchGui = true }

local player = game:GetService("Players").LocalPlayer
local GuiService = game:GetService("GuiService")
local cam = workspace.CurrentCamera
local vp = cam.ViewportSize
local inset = GuiService:GetGuiInset()

local function lin(c)
	c = c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
	return c
end
local function lum(col) return 0.2126 * lin(col.R) + 0.7152 * lin(col.G) + 0.0722 * lin(col.B) end
local function ratio(a, b)
	local la, lb = lum(a), lum(b)
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end

local function visible(o)
	local x = o
	while x and not x:IsA("ScreenGui") do
		if x:IsA("GuiObject") and not x.Visible then return false end
		x = x.Parent
	end
	return x ~= nil and x.Enabled
end
local function scaleChain(o)
	local s, x = 1, o
	while x and not x:IsA("ScreenGui") do
		for _, c in ipairs(x:GetChildren()) do if c:IsA("UIScale") then s *= c.Scale end end
		x = x.Parent
	end
	return s
end
local function bgOf(o)
	local x = o
	while x and not x:IsA("ScreenGui") do
		if x:IsA("GuiObject") and x ~= o and x.BackgroundTransparency < 0.5 then return x.BackgroundColor3, x end
		if x == o and o.BackgroundTransparency < 0.5 then return o.BackgroundColor3, o end   -- a label with its own fill (a badge) sits on that fill
		x = x.Parent
	end
	return nil
end
local function outlined(t)
	if t.TextStrokeTransparency < 0.6 then return true end
	for _, c in ipairs(t:GetChildren()) do
		if c:IsA("UIStroke") and c.Enabled and c.Transparency < 0.6 then return true end
	end
	return false
end
local function short(o) return (o:GetFullName():gsub("^.-PlayerGui%.", "")) end
local function rect(o) return o.AbsolutePosition, o.AbsolutePosition + o.AbsoluteSize end

local R = { small = {}, tap = {}, contrast = {}, floating = {}, offscreen = {}, topbar = {}, fonts = {}, colors = {}, overlaps = {} }
local nText, nBtn = 0, 0
local pieces = {}

for _, g in ipairs(player.PlayerGui:GetChildren()) do
	if g:IsA("ScreenGui") and g.Enabled and not SKIP[g.Name] then
		-- AbsolutePosition is measured from below Roblox's top bar in EVERY gui
		-- (an IgnoreGuiInset gui just reports negative y up there), so screen y = abs + inset
		local yOff = inset.Y
		for _, o in ipairs(g:GetDescendants()) do
			if o:IsA("GuiObject") and visible(o) and o.AbsoluteSize.X > 1 and o.AbsoluteSize.Y > 1 then
				local p0, p1 = rect(o)
				p0 = p0 + Vector2.new(0, yOff); p1 = p1 + Vector2.new(0, yOff)
				if p1.X < 0 or p0.Y > vp.Y or p0.X > vp.X or p1.Y < 0 then
					-- off screen: ignore parked elements (tweened away), report the rest
					if o.Parent == g then table.insert(R.offscreen, short(o)) end
				else
					if p0.Y < inset.Y and p0.X < 196 and (o:IsA("GuiButton") or o:IsA("TextLabel")) then
						table.insert(R.topbar, ("%s at %d,%d"):format(short(o), p0.X, p0.Y))
					end
					if (o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox")) and o.Text ~= "" and o.TextTransparency < 0.9 then
						nText += 1
						local s = scaleChain(o)
						local px = o.TextScaled and o.TextBounds.Y / math.max(1, select(2, o.Text:gsub("\n", "")) + 1) or o.TextSize * s
						if o.TextScaled and o:FindFirstChildOfClass("UITextSizeConstraint") then
							px = math.min(px, o:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize * s)
						end
						if px < MIN_TEXT - 0.5 then table.insert(R.small, ("%.0fpx %q  %s"):format(px, o.Text:sub(1, 34), short(o))) end
						local fam = o.FontFace and o.FontFace.Family:match("([^/]+)%.json$") or tostring(o.Font)
						R.fonts[fam] = (R.fonts[fam] or 0) + 1
						local ck = ("%d,%d,%d"):format(o.TextColor3.R * 255, o.TextColor3.G * 255, o.TextColor3.B * 255)
						R.colors[ck] = (R.colors[ck] or 0) + 1
						local bg = bgOf(o)
						if bg then
							local cr = ratio(o.TextColor3, bg)
							if cr < MIN_CONTRAST and not outlined(o) then
								table.insert(R.contrast, ("%.1f:1 %q  %s"):format(cr, o.Text:sub(1, 30), short(o)))
							end
						elseif not outlined(o) then
							table.insert(R.floating, ("%q  %s"):format(o.Text:sub(1, 30), short(o)))
						end
					end
					if (o:IsA("GuiButton") or o:IsA("TextBox")) and o.Active ~= false then
						nBtn += 1
						local m = math.min(o.AbsoluteSize.X, o.AbsoluteSize.Y)
						if m < MIN_TAP - 0.5 then table.insert(R.tap, ("%dx%d  %s"):format(o.AbsoluteSize.X, o.AbsoluteSize.Y, short(o))) end
					end
				end
			end
		end
		-- HUD pieces for the overlap check: a gui's direct children, or the rows of the two columns
		local roots = {}
		for _, c in ipairs(g:GetChildren()) do
			if c:IsA("GuiObject") and visible(c) then
				if (g.Name == "Rail" or g.Name == "RightColumn") and c.Name == "Column" then
					for _, r in ipairs(c:GetChildren()) do if r:IsA("GuiObject") and r.Visible then table.insert(roots, r) end end
				elseif c.BackgroundTransparency < 0.95 or c:IsA("GuiButton") or c:IsA("TextLabel") or c:IsA("ImageLabel") then
					table.insert(roots, c)
				end
			end
		end
		for _, r in ipairs(roots) do
			local a0, a1 = rect(r)
			if a1.X > 0 and a1.Y > 0 and a0.X < vp.X and a0.Y < vp.Y and r.AbsoluteSize.X < vp.X * 0.95 then
				table.insert(pieces, { g = g.Name, n = short(r), a0 = a0 + Vector2.new(0, yOff), a1 = a1 + Vector2.new(0, yOff) })
			end
		end
	end
end

for i = 1, #pieces do
	for j = i + 1, #pieces do
		local a, b = pieces[i], pieces[j]
		if a.g ~= b.g then
			local w = math.min(a.a1.X, b.a1.X) - math.max(a.a0.X, b.a0.X)
			local h = math.min(a.a1.Y, b.a1.Y) - math.max(a.a0.Y, b.a0.Y)
			if w > 4 and h > 4 then table.insert(R.overlaps, ("%s  x  %s  (%dx%d)"):format(a.n, b.n, w, h)) end
		end
	end
end

local out = { ("viewport %dx%d  inset %d  texts %d  buttons %d"):format(vp.X, vp.Y, inset.Y, nText, nBtn) }
local function section(title, list, cap)
	table.insert(out, ("-- %s: %d"):format(title, #list))
	for i, l in ipairs(list) do if i > (cap or 40) then table.insert(out, "   ...") break end table.insert(out, "   " .. l) end
end
section("text under " .. MIN_TEXT .. "px", R.small)
section("tap targets under " .. MIN_TAP .. "px", R.tap)
section("contrast under " .. MIN_CONTRAST .. ":1 (no outline)", R.contrast)
section("floating text, no outline, no backing", R.floating)
section("under the Roblox top bar (top-left 196x58)", R.topbar)
section("overlapping HUD pieces", R.overlaps)
local f = {}
for k, v in pairs(R.fonts) do table.insert(f, k .. "=" .. v) end
table.sort(f)
table.insert(out, "-- fonts: " .. table.concat(f, "  "))
local c, n = {}, 0
for k, v in pairs(R.colors) do n += 1; table.insert(c, { k, v }) end
table.sort(c, function(a, b) return a[2] > b[2] end)
local top = {}
for i = 1, math.min(12, #c) do table.insert(top, c[i][1] .. "x" .. c[i][2]) end
table.insert(out, ("-- text colours: %d distinct; top: %s"):format(n, table.concat(top, "  ")))
return table.concat(out, "\n")
