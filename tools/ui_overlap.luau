--[[
	ui_overlap -- does anything print on top of anything else? (v4.9)

	WHY THIS EXISTS. On 4 Oct the phone's "a GENIUS is waiting" banner printed
	straight across the quest card. tests/notify_spec.luau was passing 17 of 17
	at the time and could never have caught it: that spec tests the director's
	LOGIC against fake elements, so it only sees cards that asked the director
	for a lane, and the quest card never did. Every card in the game is correct
	on its own. The bug only exists in the composition.

	UI Labs has the same blind spot for the same reason -- it renders one
	component at a time, which is exactly the case that was never broken.

	So this measures the real thing: every GUI the running game is actually
	painting, as screen rectangles, and reports any two that share pixels.

	HOW TO RUN. In a Play session, on the CLIENT datamodel:

		local src = -- the contents of this file
		loadstring(src)()

	or paste it into execute_luau with datamodel_type "Client". It returns a
	report string and never changes anything.

	THE RULES, and why each one is here. The first draft reported 110 hits and
	nearly all of them were noise, which made it useless:

	  * ONLY THINGS THAT PAINT. A letterbox or fade frame sitting at
	    transparency 1 is laid out over the whole screen and overlaps
	    everything. It draws nothing. Transparent containers are skipped.
	  * ONLY THINGS ON SCREEN. Cards are parked off the top edge at negative y
	    between uses. Off-screen rectangles are skipped.
	  * ONLY ACROSS DIFFERENT ScreenGuis. A badge drawn on its own button is
	    the author's intent. Two independent systems writing to the same pixels
	    is the bug. Within one ScreenGui, the layout is somebody's decision.
	  * NOT ANCESTOR vs DESCENDANT. A label inside its own card always overlaps
	    it, by definition.

	AND A SECOND CHECK, added the same day the first one was not enough.

	The quest card's X did not work and this tool said the screen was clean.
	It was: the thing eating the click was "Hit", a full-card TextButton at
	ZIndex 20 with a transparent background and no text. It paints NOTHING, so
	a paint-based check skips it by design -- and an invisible button is the
	worst thing to be blind to, because the only symptom is a control that
	silently does nothing.

	So the second pass asks the engine instead. For every button on screen it
	calls PlayerGui:GetGuiObjectsAtPosition at that button's own centre, and
	if the topmost interactive thing there is not that button, something is
	sitting on it. That check found the X in one call.
]]

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local viewport = workspace.CurrentCamera.ViewportSize

local MIN_SIDE = 8          -- ignore hairlines and spacers
local MIN_BITE = 6          -- an overlap thinner than this is a rounding seam

local function paints(o)
	if o:IsA("Frame") or o:IsA("TextButton") or o:IsA("TextLabel") or o:IsA("TextBox")
		or o:IsA("ImageLabel") or o:IsA("ImageButton") or o:IsA("ScrollingFrame") then
		if o.BackgroundTransparency < 0.95 then return true end
	end
	if (o:IsA("ImageLabel") or o:IsA("ImageButton")) and o.Image ~= "" and o.ImageTransparency < 0.95 then
		return true
	end
	if (o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox"))
		and o.Text ~= "" and o.TextTransparency < 0.95 then
		return true
	end
	return false
end

-- visible all the way up to its ScreenGui, and the ScreenGui enabled
local function onScreenChain(o)
	local n = o
	while n and n ~= pg do
		if n:IsA("GuiObject") and not n.Visible then return false end
		if n:IsA("ScreenGui") then return n.Enabled end
		n = n.Parent
	end
	return false
end

local function screenGuiOf(o)
	local n = o
	while n and n ~= pg do
		if n:IsA("ScreenGui") then return n end
		n = n.Parent
	end
	return nil
end

local function inside(p, s)
	return p.X + s.X > 0 and p.Y + s.Y > 0 and p.X < viewport.X and p.Y < viewport.Y
end

local items = {}
for _, g in ipairs(pg:GetChildren()) do
	if g:IsA("ScreenGui") and g.Enabled then
		for _, o in ipairs(g:GetDescendants()) do
			if o:IsA("GuiObject") and paints(o) and onScreenChain(o) then
				local p, s = o.AbsolutePosition, o.AbsoluteSize
				if s.X >= MIN_SIDE and s.Y >= MIN_SIDE and inside(p, s) then
					table.insert(items, { obj = o, gui = g, p = p, s = s })
				end
			end
		end
	end
end

local function path(it)
	local names, n = {}, it.obj
	while n and n ~= it.gui do
		table.insert(names, 1, n.Name)
		n = n.Parent
	end
	return it.gui.Name .. "." .. table.concat(names, ".")
end

local hits = {}
for i = 1, #items do
	for j = i + 1, #items do
		local a, b = items[i], items[j]
		if a.gui ~= b.gui then
			local ox = math.min(a.p.X + a.s.X, b.p.X + b.s.X) - math.max(a.p.X, b.p.X)
			local oy = math.min(a.p.Y + a.s.Y, b.p.Y + b.s.Y) - math.max(a.p.Y, b.p.Y)
			if ox > MIN_BITE and oy > MIN_BITE then
				table.insert(hits, {
					area = ox * oy,
					line = ("  %-44s over %-44s  %d x %d px"):format(path(a), path(b), ox, oy),
				})
			end
		end
	end
end
table.sort(hits, function(x, y) return x.area > y.area end)

local out = {
	("ui_overlap  ·  viewport %dx%d  ·  %d painted elements across %d screens")
		:format(viewport.X, viewport.Y, #items, #pg:GetChildren()),
}
for _, h in ipairs(hits) do table.insert(out, h.line) end
table.insert(out, ("OVERLAPS: %d"):format(#hits))

--[[ BUTTONS SOMETHING ELSE WILL SWALLOW. A control drawn in the wrong place
	is at least visible; a control that cannot be clicked fails silently. ]]
local function interactive(o)
	return o:IsA("GuiButton") or (o:IsA("GuiObject") and o.Active)
end

local blocked = 0
table.insert(out, "-- BUTTONS SOMETHING ELSE WILL SWALLOW --")
for _, it in ipairs(items) do
	local o = it.obj
	if o:IsA("GuiButton") then
		local x = math.floor(o.AbsolutePosition.X + o.AbsoluteSize.X / 2)
		local y = math.floor(o.AbsolutePosition.Y + o.AbsoluteSize.Y / 2)
		local ok, stack = pcall(function() return pg:GetGuiObjectsAtPosition(x, y) end)
		if ok then
			local top
			for _, candidate in ipairs(stack) do
				if interactive(candidate) then
					top = candidate
					break
				end
			end
			if top and top ~= o then
				local names, g = {}, top
				while g and g ~= pg do
					table.insert(names, 1, g.Name)
					g = g.Parent
				end
				blocked += 1
				table.insert(out, ("  %-40s covered at its centre by %s (ZIndex %d vs %d)")
					:format(path(it), table.concat(names, "."), top.ZIndex, o.ZIndex))
			end
		end
	end
end
table.insert(out, ("BLOCKED BUTTONS: %d"):format(blocked))

return table.concat(out, "\n")
