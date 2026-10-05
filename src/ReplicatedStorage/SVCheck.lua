--[[
	SVCheck -- one command that runs every check at once (v4.9).

	WHY THIS EXISTS. Four of the last five defects in this game were found the
	same way: Luke played, took a screenshot, sent it, and waited. The fixes
	were cheap. The ROUND TRIP was not.

	And each time, the check written afterwards immediately found the NEXT
	instance for free -- the overlap check found the quest card drawing over
	the Daily panel before he reported it, the blocked-button pass found a
	ProximityPrompt swallowed by the BAG tile, the footprint registry found 19
	more pieces of greenery on paving. The checks were never the expensive
	part. Having four of them, run by hand, in different datamodels, was.

	So this is all of them behind one line. In a Play session, CLIENT
	datamodel:

	    return require(game.ReplicatedStorage.SVCheck).run()

	Everything it reads is replicated to the client, so the UI and the world
	can be checked in the same call. It changes nothing except the camera,
	which it puts back.

	WHAT IT CANNOT SEE, stated here so nobody trusts it further than it goes:
	  * SERVER errors. LogService on the client only has the client's log.
	    Use get_console_output for the server side.
	  * Anything that needs a second player.
	  * Whether the game is any good.
]]

local SVCheck = {}

-- Roblox's documented low-end phone budget
local DRAW_CEIL, TRI_CEIL = 1000, 1000000
local MIN_SIDE, MIN_BITE = 8, 6
local CELL = 24

local VIEWS = {
	{ "hub across the ring", Vector3.new(0, 120, 430), Vector3.new(0, 20, 0) },
	{ "high over the campus", Vector3.new(0, 420, 700), Vector3.new(0, 40, 0) },
	{ "street by the districts", Vector3.new(220, 14, 300), Vector3.new(0, 20, 60) },
	{ "downtown", Vector3.new(600, 60, 120), Vector3.new(760, 30, 0) },
}

local GREEN = { "tree", "bush", "palm", "oak", "pine", "redwood", "eucalypt", "orchard", "grove", "shrub", "plant" }

local function isGreenery(inst)
	local n = inst.Name:lower()
	for _, w in ipairs(GREEN) do
		if string.find(n, w, 1, true) then return true end
	end
	return false
end

local function boxOf(inst)
	if inst:IsA("Model") then
		local ok, cf, ext = pcall(function()
			local a, b = inst:GetBoundingBox()
			return a, b
		end)
		if ok and ext then return cf.Position, ext end
	elseif inst:IsA("BasePart") then
		return inst.Position, inst.Size
	end
	return nil, nil
end

-- ---------------------------------------------------------------- 1. budget
local function checkBudget(say)
	local Stats = game:GetService("Stats")
	local RunService = game:GetService("RunService")
	local cam = workspace.CurrentCamera
	local wasType, wasCF, wasFov = cam.CameraType, cam.CFrame, cam.FieldOfView
	--[[ MEASURED: the first version of this reported identical numbers for all
		four views, which is the tell that the camera never moved. Setting
		CameraType once is not enough -- the default camera module takes it back.
		It has to be re-pinned every frame. ]]
	local pinTo, pinAt = wasCF.Position, wasCF.Position + wasCF.LookVector
	local hold = RunService.RenderStepped:Connect(function()
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = CFrame.lookAt(pinTo, pinAt)
		cam.Focus = CFrame.new(pinAt)
	end)
	local worstD, worstT, worstName = 0, 0, "?"
	local seenDraws = {}
	say("BUDGET   (ceiling %d draws / %dk triangles)", DRAW_CEIL, TRI_CEIL / 1000)
	for _, v in ipairs(VIEWS) do
		pinTo, pinAt = v[2], v[3]
		task.wait(1.6)
		local d, t = Stats.SceneDrawcallCount, Stats.SceneTriangleCount
		table.insert(seenDraws, d)
		if d > worstD then worstD, worstName = d, v[1] end
		worstT = math.max(worstT, t)
		say("   %-26s %4d draws   %7d tris", v[1], d, t)
	end
	hold:Disconnect()
	cam.CameraType, cam.CFrame, cam.FieldOfView = wasType, wasCF, wasFov
	--[[ THE TELL FOR FROZEN STATS. A minimised Studio window stops rendering and
		Stats keeps serving the last frame it drew, so four different cameras come
		back with the SAME number to the digit. Caught exactly that on 5 Oct: four
		views, 727 draws each, because the window was minimised. A low absolute
		number is not the signal -- identical numbers are. ]]
	local identical = true
	for _, d in ipairs(seenDraws) do
		if d ~= seenDraws[1] then identical = false break end
	end
	if identical and #seenDraws > 1 then
		say("   !! all %d views returned %d draws: the window is not rendering,", #seenDraws, worstD)
		say("      so these numbers are the last frame Studio drew, not a measurement")
		return false
	end
	local okD, okT = worstD <= DRAW_CEIL, worstT <= TRI_CEIL
	say("   worst: %d draws (%s), %d tris   %s", worstD, worstName, worstT,
		(okD and okT) and "OK" or "OVER BUDGET")
	-- a draw count of almost nothing means the window is minimised and these
	-- numbers are meaningless; say so rather than reporting a false pass
	if worstD < 40 then
		say("   !! the Studio window is not rendering -- these numbers are not real")
		return false
	end
	return okD and okT
end

-- ---------------------------------------------------------------- 2. the screen
local function checkUI(say)
	local pg = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then say("SCREEN   no PlayerGui"); return false end
	local viewport = workspace.CurrentCamera.ViewportSize

	local function paints(o)
		if (o:IsA("Frame") or o:IsA("TextButton") or o:IsA("TextLabel") or o:IsA("TextBox")
			or o:IsA("ImageLabel") or o:IsA("ImageButton") or o:IsA("ScrollingFrame"))
			and o.BackgroundTransparency < 0.95 then return true end
		if (o:IsA("ImageLabel") or o:IsA("ImageButton")) and o.Image ~= "" and o.ImageTransparency < 0.95 then return true end
		if (o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox"))
			and o.Text ~= "" and o.TextTransparency < 0.95 then return true end
		return false
	end
	local function chain(o)
		local n = o
		while n and n ~= pg do
			if n:IsA("GuiObject") and not n.Visible then return false end
			if n:IsA("ScreenGui") then return n.Enabled end
			n = n.Parent
		end
		return false
	end
	local function nameOf(o)
		local names, g = {}, o
		while g and g ~= pg do table.insert(names, 1, g.Name); g = g.Parent end
		return table.concat(names, ".")
	end

	local items = {}
	for _, g in ipairs(pg:GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled then
			for _, o in ipairs(g:GetDescendants()) do
				if o:IsA("GuiObject") and paints(o) and chain(o) then
					local p, s = o.AbsolutePosition, o.AbsoluteSize
					if s.X >= MIN_SIDE and s.Y >= MIN_SIDE
						and p.X + s.X > 0 and p.Y + s.Y > 0 and p.X < viewport.X and p.Y < viewport.Y then
						table.insert(items, { obj = o, gui = g, p = p, s = s })
					end
				end
			end
		end
	end

	-- drawn on top of each other, ACROSS different screens only: inside one
	-- ScreenGui the layout is somebody's decision, between two it is a bug
	local hits = {}
	for i = 1, #items do
		for j = i + 1, #items do
			local a, b = items[i], items[j]
			if a.gui ~= b.gui then
				local ox = math.min(a.p.X + a.s.X, b.p.X + b.s.X) - math.max(a.p.X, b.p.X)
				local oy = math.min(a.p.Y + a.s.Y, b.p.Y + b.s.Y) - math.max(a.p.Y, b.p.Y)
				if ox > MIN_BITE and oy > MIN_BITE then
					table.insert(hits, { area = ox * oy,
						line = ("      %s over %s  (%d x %d px)"):format(nameOf(a), nameOf(b), ox, oy) })
				end
			end
		end
	end
	table.sort(hits, function(x, y) return x.area > y.area end)

	--[[ And the one a paint-based check is blind to: a button covered by
		something invisible. "Hit" -- a transparent full-card TextButton -- ate
		every click on the quest card's X for a day, and the overlap pass said
		the screen was clean, because an invisible button paints nothing. ]]
	local blocked = {}
	for _, it in ipairs(items) do
		local o = it.obj
		if o:IsA("GuiButton") then
			local x = math.floor(o.AbsolutePosition.X + o.AbsoluteSize.X / 2)
			local y = math.floor(o.AbsolutePosition.Y + o.AbsoluteSize.Y / 2)
			local ok, stack = pcall(function() return pg:GetGuiObjectsAtPosition(x, y) end)
			if ok then
				local top
				for _, c in ipairs(stack) do
					if c:IsA("GuiButton") or (c:IsA("GuiObject") and c.Active) then top = c break end
				end
				if top and top ~= o then
					table.insert(blocked, ("      %s is covered by %s (ZIndex %d vs %d)")
						:format(nameOf(o), nameOf(top), top.ZIndex, o.ZIndex))
				end
			end
		end
	end

	say("SCREEN   %d painted elements, %dx%d", #items, viewport.X, viewport.Y)
	say("   drawn over each other: %d", #hits)
	for i = 1, math.min(6, #hits) do say(hits[i].line) end
	say("   buttons something will swallow: %d", #blocked)
	for i = 1, math.min(6, #blocked) do say(blocked[i]) end
	return #hits == 0 and #blocked == 0
end

-- ---------------------------------------------------------------- 3. the world
local function checkWorld(say)
	local HttpService = game:GetService("HttpService")
	local sv = workspace:FindFirstChild("SiliconValley")
	if not sv then say("WORLD    no SiliconValley folder"); return false end

	local zones = {}
	local raw = sv:GetAttribute("GroundZones")
	if raw then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok then
			for _, z in ipairs(decoded) do
				z.cf = CFrame.new(z.x, z.y, z.z) * CFrame.Angles(0, z.yaw, 0)
				table.insert(zones, z)
			end
		end
	end

	-- greenery standing on ground somebody paved
	local onPaving, byZone = 0, {}
	for _, rootName in ipairs({ "LowPolyWorld", "Valley" }) do
		local root = sv:FindFirstChild(rootName)
		if root then
			for _, inst in ipairs(root:GetDescendants()) do
				if (inst:IsA("Model") or inst:IsA("BasePart")) and isGreenery(inst)
					and not (inst.Parent and inst.Parent ~= root and isGreenery(inst.Parent)) then
					local pos, ext = boxOf(inst)
					if pos then
						local base = pos.Y - ext.Y / 2
						for _, z in ipairs(zones) do
							local lp = z.cf:PointToObjectSpace(pos)
							if math.abs(lp.X) <= z.hx and math.abs(lp.Z) <= z.hz
								and base >= z.y - 4 and base <= z.y + 10 then
								onPaving += 1
								byZone[z.n] = (byZone[z.n] or 0) + 1
								break
							end
						end
					end
				end
			end
		end
	end

	--[[ The early warning, and the only part of this that predicts rather than
		reports: paving nobody reserved. A registry only works if builders
		remember to call it, and remembering is not a mechanism. ]]
	local unclaimed, examples = 0, {}
	for _, folderName in ipairs({ "CampusDistricts", "CampusHub", "Downtown" }) do
		local folder = sv:FindFirstChild(folderName)
		if folder then
			for _, p in ipairs(folder:GetDescendants()) do
				if p:IsA("BasePart") and p.Size.X > 60 and p.Size.Z > 60 and p.Size.Y < 6 then
					local claimed = false
					for _, z in ipairs(zones) do
						if (Vector3.new(z.x, 0, z.z) - Vector3.new(p.Position.X, 0, p.Position.Z)).Magnitude < 6 then
							claimed = true
							break
						end
					end
					if not claimed then
						unclaimed += 1
						if #examples < 6 then
							table.insert(examples, ("      %s.%s at %.0f,%.0f  %.0f x %.0f")
								:format(folderName, p.Name, p.Position.X, p.Position.Z, p.Size.X, p.Size.Z))
						end
					end
				end
			end
		end
	end

	-- props grown into each other, on a grid so this stays a check somebody runs
	local cells, props = {}, {}
	for _, folderName in ipairs({ "CampusDistricts", "CampusHub", "Valley" }) do
		local folder = sv:FindFirstChild(folderName)
		if folder then
			local CS = game:GetService("CollectionService")
			for _, inst in ipairs(folder:GetDescendants()) do
				-- moving things pass through scenery constantly; that is traffic,
				-- not a build error
				local moves = CS:HasTag(inst, "TrafficCar") or CS:HasTag(inst, "SVStaff")
					or inst.Name:match("^RingCar") or inst.Name:match("^Walker")
				if inst:IsA("Model") and #inst:GetChildren() > 0 and inst.Parent == folder and not moves then
					local pos, ext = boxOf(inst)
					if pos and ext and ext.Y > 2 then
						local it = { inst = inst, pos = pos, ext = ext }
						table.insert(props, it)
						local key = ("%d:%d"):format(math.floor(pos.X / CELL), math.floor(pos.Z / CELL))
						cells[key] = cells[key] or {}
						table.insert(cells[key], it)
					end
				end
			end
		end
	end
	local grown, seen, shown = 0, {}, {}
	for _, a in ipairs(props) do
		local cx, cz = math.floor(a.pos.X / CELL), math.floor(a.pos.Z / CELL)
		for dx = -1, 1 do
			for dz = -1, 1 do
				for _, b in ipairs(cells[("%d:%d"):format(cx + dx, cz + dz)] or {}) do
					if a ~= b then
						local ka, kb = a.inst:GetDebugId(), b.inst:GetDebugId()
						local key = ka < kb and (ka .. kb) or (kb .. ka)
						if not seen[key] then
							local ox = (a.ext.X + b.ext.X) / 2 - math.abs(a.pos.X - b.pos.X)
							local oz = (a.ext.Z + b.ext.Z) / 2 - math.abs(a.pos.Z - b.pos.Z)
							local oy = (a.ext.Y + b.ext.Y) / 2 - math.abs(a.pos.Y - b.pos.Y)
							if ox > 2.5 and oz > 2.5 and oy > 2.5
								and ox > math.min(a.ext.X, b.ext.X) * 0.45
								and oz > math.min(a.ext.Z, b.ext.Z) * 0.45 then
								seen[key] = true
								grown += 1
								if #shown < 6 then
									table.insert(shown, ("      %s x %s at %.0f,%.0f")
										:format(a.inst.Name, b.inst.Name, a.pos.X, a.pos.Z))
								end
							end
						end
					end
				end
			end
		end
	end

	say("WORLD    %d reserved zones, %d props checked", #zones, #props)
	say("   greenery standing on paving: %d", onPaving)
	for k, v in pairs(byZone) do say("      %s %d", k, v) end
	say("   paving nobody reserved: %d", unclaimed)
	for _, l in ipairs(examples) do say(l) end
	say("   props grown into each other: %d", grown)
	for _, l in ipairs(shown) do say(l) end
	return onPaving == 0 and unclaimed == 0 and grown == 0
end

-- ---------------------------------------------------------------- 4. outlines
local function checkOutlines(say)
	local CS = game:GetService("CollectionService")
	local tagged = 0
	for _, t in ipairs({ "SVOutline", "SVOutline2", "SVStaff", "TrafficCar" }) do
		tagged += #CS:GetTagged(t)
	end
	local lit, parts, fading = 0, 0, 0
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Highlight") and d.Adornee then
			lit += 1
			if d.Adornee:IsA("BasePart") then parts += 1 end
			if d.OutlineTransparency > 0.05 and d.OutlineTransparency < 0.99 then fading += 1 end
		end
	end
	say("OUTLINES %d tagged objects, %d currently outlined (%d loose parts, %d mid-fade)",
		tagged, lit, parts, fading)
	--[[ The regression this guards: outlines once stopped dead at 240 studs and
		only 41 objects carried one, which is what "it only shows on half the
		objects" was. A fade band means the edge is never visible; no fade at all
		means something has gone back to a hard cutoff. ]]
	if lit < 200 then say("   !! coverage has collapsed -- it was 1,096"); return false end
	if fading == 0 and lit > 0 then say("   !! nothing is mid-fade: the edge may be hard again"); return false end
	return true
end

-- ---------------------------------------------------------------- 5. client errors
local function checkErrors(say)
	local ok, history = pcall(function() return game:GetService("LogService"):GetLogHistory() end)
	if not ok then say("ERRORS   LogService unavailable from here"); return true end
	local errs, warns, shown = 0, 0, {}
	for _, e in ipairs(history) do
		if e.messageType == Enum.MessageType.MessageError then
			errs += 1
			if #shown < 6 then table.insert(shown, "      " .. e.message:sub(1, 150)) end
		elseif e.messageType == Enum.MessageType.MessageWarning then
			warns += 1
		end
	end
	say("ERRORS   %d errors, %d warnings in the CLIENT log", errs, warns)
	for _, l in ipairs(shown) do say(l) end
	say("   (server log is not visible from here -- use get_console_output)")
	return errs == 0
end

-- ---------------------------------------------------------------- the visual sweep
--[[ EVERY CHECK ABOVE READS DATA. None of them can see "the boxes look
	awkward" or "this reads as slop", because those are not properties of the
	data -- they are properties of the rendered image, and until now the only
	thing in this project that ever looked at the rendered image was Luke,
	one screenshot at a time, after the fact.

	So: a fixed set of framings, the same ones every build, aimed at the places
	bugs actually live -- inside the garage where the furniture is, the lobby,
	the street, and a shot deliberately composed with something between the
	camera and an outlined object, because that is where the outline leaks.

	Usage, one shot at a time so the capture is reliable:
	    local C = require(game.ReplicatedStorage.SVCheck)
	    C.shot(1)        -- returns its name; screenshot; then C.shot(2) ...
	    C.endShots()     -- puts the camera, the character and the HUD back
]]
--[[ Framings found by hand on 5 Oct and frozen here. The first draft put the
	camera at z 26, which is OUTSIDE the garage door and looks straight into
	the tower ring -- it showed a wall of building and none of the furniture
	anybody was asking about. The garage interior is x +-18, z +-15, floor top
	y 1, roof y 14, so a camera has to live inside that box. ]]
SVCheck.SHOTS = {
	{ "garage: desk and laptop", { 0, 6, 11 }, { 0, 4.3, -15 }, 62, true },
	{ "garage: the box corner", { -8, 5.5, 7 }, { 16, 3, -14 }, 60, true },
	{ "garage: the pads and the floor", { 5, 3.2, 12 }, { -11, 1.2, 3 }, 68, true },
	{ "garage: from the seat", { 3, 4.6, -5 }, { 0, 4.0, -12 }, 55, true },
	{ "the plot from the street", { 0, 16, 110 }, { 0, 24, 0 }, 60, false },
	{ "street, props close", { -72, 7, 70 }, { -72, 5, -60 }, 70, false },
	{ "the hub, wide", { 0, 90, 360 }, { 0, 20, -40 }, 60, false },
}

local shotState = nil

function SVCheck.shot(i)
	local RunService = game:GetService("RunService")
	local player = game:GetService("Players").LocalPlayer
	local spec = SVCheck.SHOTS[i]
	if not spec then return "no shot " .. tostring(i) end
	local plots = workspace:FindFirstChild("SiliconValley")
	plots = plots and plots:FindFirstChild("Plots")
	local pf = plots and plots:FindFirstChild("Plot" .. tostring(player:GetAttribute("Plot")))
	local pivot = pf and pf:GetAttribute("Pivot")
	if not pivot then return "no plot yet" end

	if not shotState then
		local cam = workspace.CurrentCamera
		shotState = { cam = cam, type = cam.CameraType, cf = cam.CFrame, fov = cam.FieldOfView, gui = {} }
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		shotState.root = root and root.CFrame or nil
		for _, g in ipairs(player.PlayerGui:GetChildren()) do
			if g:IsA("ScreenGui") then shotState.gui[g] = g.Enabled end
		end
	end

	local name, from, to, fov, hideHud = spec[1], spec[2], spec[3], spec[4], spec[5]
	local P = function(v) return pivot:PointToWorldSpace(Vector3.new(v[1], v[2], v[3])) end
	local a, b = P(from), P(to)
	--[[ Outlines anchor on the CHARACTER, not the camera, so the character has to
		stand where the shot is taken or half the frame has no line. But standing
		them AT the camera fills the foreground with their own avatar -- the first
		sweep came back with a black mass across the bottom of every garage shot,
		and it was his own character at point-blank range. Stand them there and
		make them invisible locally. ]]
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then root.CFrame = CFrame.new(a - Vector3.new(0, 2, 0)) end
	if char then
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = 1 end
		end
		shotState.hidChar = true
	end
	for g, _ in pairs(shotState.gui) do
		if g.Parent then g.Enabled = not hideHud end
	end
	if shotState.conn then shotState.conn:Disconnect() end
	local cam = workspace.CurrentCamera
	shotState.conn = RunService.RenderStepped:Connect(function()
		cam.CameraType = Enum.CameraType.Scriptable
		cam.FieldOfView = fov
		cam.CFrame = CFrame.lookAt(a, b)
		cam.Focus = CFrame.new(b)
	end)
	task.wait(1.2)
	return ("shot %d/%d  %s"):format(i, #SVCheck.SHOTS, name)
end

function SVCheck.endShots()
	if not shotState then return "no sweep running" end
	if shotState.conn then shotState.conn:Disconnect() end
	local cam = shotState.cam
	cam.CameraType, cam.CFrame, cam.FieldOfView = shotState.type, shotState.cf, shotState.fov
	local player = game:GetService("Players").LocalPlayer
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and shotState.root then root.CFrame = shotState.root end
	if char and shotState.hidChar then
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = 0 end
		end
	end
	for g, on in pairs(shotState.gui) do
		if g.Parent then g.Enabled = on end
	end
	shotState = nil
	return "sweep ended, camera and HUD restored"
end

-- ---------------------------------------------------------------- run
function SVCheck.run()
	local out = {}
	local function say(f, ...)
		table.insert(out, select("#", ...) > 0 and string.format(f, ...) or f)
	end
	say("SVCheck  %s", os.date("%Y-%m-%d %H:%M"))
	say("")
	local results = {}
	for _, pass in ipairs({
		{ "budget", checkBudget }, { "screen", checkUI },
		{ "world", checkWorld }, { "outlines", checkOutlines }, { "errors", checkErrors },
	}) do
		local ok, res = pcall(pass[2], say)
		results[pass[1]] = ok and res or false
		if not ok then say("%s CHECK ITSELF FAILED: %s", pass[1]:upper(), tostring(res)) end
		say("")
	end
	local bad = {}
	for name, good in pairs(results) do
		if not good then table.insert(bad, name) end
	end
	table.sort(bad)
	say(#bad == 0 and "VERDICT  clean" or ("VERDICT  look at: " .. table.concat(bad, ", ")))
	return table.concat(out, "\n")
end

return SVCheck
