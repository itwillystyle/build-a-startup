--[[ DoctorProbes (11 Oct 2026): what the game doctor measures on the player's screen.

	GameDoctor (server) plays the game; some things only the client can see: where
	the camera is, what is painted on the screen, how the hunter looks while it
	runs. DoctorClient runs one of these when the server asks, and sends back
	numbers. Each probe only measures; none of them changes the game.

	  ui        every painted GUI rectangle that overlaps one from another screen,
	            and every button something else would swallow (tools/ui_overlap.luau,
	            made callable)
	  camera    from where you stand, 8 directions: how often the lens ends up
	            behind a building wall (CameraWalls' stand-ins)
	  chasecam  a whole carry, every frame: camera cuts, lens behind walls, the
	            hunter moving with no run animation, the hunter stuttering

	The judging numbers are pure (bottom of the file) and tested offline in
	tests/offline/doctor.spec.luau. ]]
local Probes = {}

-- ---------------------------------------------------------------- the rules (pure)
Probes.CUT_STUDS = 8          -- the lens moving this far in one frame is a cut, not a follow
Probes.CUT_DEG = 40           -- or turning this far in one frame
Probes.RUN_ID = "rbxassetid://129982348627259"   -- the hunter's run (StaffAnimClient HUNTER_ANIM.run)
Probes.MOVING = 4             -- studs/s: a hunter faster than this should be running
Probes.STUTTER = 1.5          -- studs: a frame-to-frame step change this big is a visible hitch
Probes.MIN_TEXT = 14          -- px on screen (DESIGN.md)
Probes.MIN_TEXT_PHONE = 12    -- on a phone-height screen (under 520 tall): UIKit.autoScale's floor 0.86 x 14
Probes.PHONE_BELOW = 520
Probes.MIN_TAP = 44           -- px on screen (DESIGN.md)

-- one frame of the camera: was it a cut?
function Probes.isCut(moved, turnedDeg)
	return moved > Probes.CUT_STUDS or turnedDeg > Probes.CUT_DEG
end

-- one frame of the hunter: did its step length jump (a hitch you can see)?
function Probes.isStutter(prevStep, step)
	return math.abs(step - prevStep) > Probes.STUTTER
end

-- ---------------------------------------------------------------- runtime (client)
local function standIns()
	local list = {}
	local plots = workspace:FindFirstChild("SiliconValley") and workspace.SiliconValley:FindFirstChild("Plots")
	for _, d in ipairs(plots and plots:GetDescendants() or {}) do
		if d:IsA("BasePart") and d.Transparency > 0.9 and d.CanCollide and d.CanQuery then table.insert(list, d) end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = list
	return params
end

-- is the lens behind a building wall, seen from the head?
local function behind(params, head, lens)
	return workspace:Raycast(head, lens - head, params) ~= nil
end

function Probes.ui()
	local Players = game:GetService("Players")
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local viewport = workspace.CurrentCamera.ViewportSize
	local function paints(o)
		-- a screen overlay drawn over everything on purpose (the chase's red edges,
		-- LOST!'s flash, the IPO's dim) is not a card over a card
		if o:GetAttribute("Overlay") then return false end
		if (o:IsA("Frame") or o:IsA("TextButton") or o:IsA("TextLabel") or o:IsA("TextBox") or o:IsA("ImageLabel")
			or o:IsA("ImageButton") or o:IsA("ScrollingFrame")) and o.BackgroundTransparency < 0.95 then return true end
		if (o:IsA("ImageLabel") or o:IsA("ImageButton")) and o.Image ~= "" and o.ImageTransparency < 0.95 then return true end
		if (o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox")) and o.Text ~= "" and o.TextTransparency < 0.95 then return true end
		return false
	end
	local function screenOf(o)
		local n = o
		while n and n ~= pg do
			if n:IsA("GuiObject") and not n.Visible then return nil end
			if n:IsA("ScreenGui") then return n.Enabled and n or nil end
			n = n.Parent
		end
		return nil
	end
	local function path(o, g)
		local names, n = {}, o
		while n and n ~= g do table.insert(names, 1, n.Name) n = n.Parent end
		return g.Name .. "." .. table.concat(names, ".")
	end
	local items = {}
	for _, g in ipairs(pg:GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled then
			for _, o in ipairs(g:GetDescendants()) do
				if o:IsA("GuiObject") and paints(o) and screenOf(o) == g then
					local p, s = o.AbsolutePosition, o.AbsoluteSize
					if s.X >= 8 and s.Y >= 8 and p.X + s.X > 0 and p.Y + s.Y > 0 and p.X < viewport.X and p.Y < viewport.Y then
						table.insert(items, { obj = o, gui = g, p = p, s = s })
					end
				end
			end
		end
	end
	local overlaps = {}
	for i = 1, #items do
		for j = i + 1, #items do
			local a, b = items[i], items[j]
			if a.gui ~= b.gui then
				local ox = math.min(a.p.X + a.s.X, b.p.X + b.s.X) - math.max(a.p.X, b.p.X)
				local oy = math.min(a.p.Y + a.s.Y, b.p.Y + b.s.Y) - math.max(a.p.Y, b.p.Y)
				if ox > 6 and oy > 6 then
					table.insert(overlaps, { a = path(a.obj, a.gui), b = path(b.obj, b.gui), area = math.floor(ox * oy) })
				end
			end
		end
	end
	table.sort(overlaps, function(x, y) return x.area > y.area end)
	-- collapse to one row per pair of screens: the deepest element pair is noise, the screens are the finding
	local byScreens, rows = {}, {}
	for _, o in ipairs(overlaps) do
		local key = o.a:match("^[^.]+") .. " / " .. o.b:match("^[^.]+")
		if not byScreens[key] then
			byScreens[key] = true
			table.insert(rows, { screens = key, a = o.a, b = o.b, area = o.area })
		end
	end
	local blocked = {}
	for _, it in ipairs(items) do
		local o = it.obj
		if o:IsA("GuiButton") then
			local x = math.floor(o.AbsolutePosition.X + o.AbsoluteSize.X / 2)
			local y = math.floor(o.AbsolutePosition.Y + o.AbsoluteSize.Y / 2)
			local ok, stack = pcall(function() return pg:GetGuiObjectsAtPosition(x, y) end)
			if ok then
				for _, c in ipairs(stack) do
					if c:IsA("GuiButton") or (c:IsA("GuiObject") and c.Active) then
						if c ~= o then table.insert(blocked, { button = path(o, it.gui), by = c:GetFullName() }) end
						break
					end
				end
			end
		end
	end
	--[[ DESIGN.md's two floors, as the player actually sees them: text under 14 px and
		taps under 44 px AFTER every UIScale (UIKit.autoScale shrinks the HUD on a short
		screen, so a 14 px label can land at 10). tools/ui_audit.luau, made a probe. ]]
	-- a frame honours ONE UIScale, the first child (measured 11 Oct: the rail column
	-- has FitScale 1 then SVAutoScale 0.68, and its 66 px tiles draw at 64 = the grid
	-- cell, unshrunk). Multiplying them all reported its 14 px captions as 10 px.
	local function scaleOf(o)
		local s, x = 1, o
		while x and not x:IsA("ScreenGui") do
			local first = x:FindFirstChildWhichIsA("UIScale")
			if first then s *= first.Scale end
			x = x.Parent
		end
		return s
	end
	local smallText, smallTaps = {}, {}
	local floorText = viewport.Y < Probes.PHONE_BELOW and Probes.MIN_TEXT_PHONE or Probes.MIN_TEXT
	for _, it in ipairs(items) do
		local o = it.obj
		if (o:IsA("TextLabel") or o:IsA("TextButton")) and o.Text ~= "" and o.TextTransparency < 0.9 then
			local px = o.TextScaled and o.TextBounds.Y or o.TextSize * scaleOf(o)
			if px < floorText - 0.5 then table.insert(smallText, ("%s %.0fpx"):format(path(o, it.gui), px)) end
		end
		if o:IsA("GuiButton") and o.Active then
			local m = math.min(o.AbsoluteSize.X, o.AbsoluteSize.Y)
			if m < Probes.MIN_TAP - 0.5 then table.insert(smallTaps, ("%s %dpx"):format(path(o, it.gui), m)) end
		end
	end
	-- v8 (14 Oct) composition: SlopRules (pure) judges what is gathered here
	local Slop = require(game:GetService("ReplicatedStorage"):WaitForChild("SlopRules"))
	local okUI, UIKit = pcall(require, game:GetService("ReplicatedStorage"):WaitForChild("UIKit"))
	local isMenu = {}
	for _, n in ipairs(okUI and UIKit.MENUS or {}) do isMenu[n] = true end
	local function rgb(c) return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) } end
	local function clipOf(o)
		local n = o.Parent
		while n and not n:IsA("ScreenGui") do
			if n:IsA("GuiObject") and n.ClipsDescendants then
				if n:IsA("ScrollingFrame") then return nil end
				return { n.AbsolutePosition.X, n.AbsolutePosition.Y, n.AbsoluteSize.X, n.AbsoluteSize.Y }
			end
			n = n.Parent
		end
		return nil
	end
	local buttons, labels, cut = {}, {}, {}
	for _, it in ipairs(items) do
		local o = it.obj
		if o:IsA("GuiButton") and o.Active and isMenu[it.gui.Name] then
			local face = o:GetAttribute("Face")
			table.insert(buttons, { menu = it.gui.Name, path = path(o, it.gui), rgb = rgb(typeof(face) == "Color3" and face or o.BackgroundColor3) })
		end
		if o:IsA("TextLabel") and not o:FindFirstAncestorWhichIsA("GuiButton") and o.TextTransparency < 0.9 then
			table.insert(labels, { gui = it.gui.Name, path = path(o, it.gui), text = o.Text })
		end
		if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("GuiButton") then
			table.insert(cut, { path = path(o, it.gui), fits = (o:IsA("TextLabel") or o:IsA("TextButton")) and o.Text ~= "" and o.TextFits or nil,
				rect = { it.p.X, it.p.Y, it.s.X, it.s.Y }, clip = o:IsA("GuiButton") and clipOf(o) or nil })
		end
	end
	return { painted = #items, overlaps = rows, blocked = blocked, smallText = smallText, smallTaps = smallTaps,
		viewport = ("%dx%d"):format(viewport.X, viewport.Y), textFloor = floorText,
		loud = Slop.loudButtons(buttons), twice = Slop.saidTwice(labels), cutOff = Slop.cutOff(cut) }
end

-- args.zoom (studs, default 12). From where the character stands now.
function Probes.camera(args)
	local RS = game:GetService("RunService")
	local player = game:GetService("Players").LocalPlayer
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local cam = workspace.CurrentCamera
	if not root then return { error = "no character" } end
	local zoom = (args and args.zoom) or 12
	local params = standIns()
	local samples, bad, closest = 0, 0, math.huge
	local min0, max0 = player.CameraMinZoomDistance, player.CameraMaxZoomDistance
	player.CameraMinZoomDistance, player.CameraMaxZoomDistance = zoom, zoom
	for yaw = 0, 315, 45 do
		cam.CameraType = Enum.CameraType.Custom
		local focus = root.Position + Vector3.new(0, 1.5, 0)
		local dir = CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(-20), 0, 0)
		cam.CFrame = CFrame.lookAt(focus - dir.LookVector * zoom, focus)
		for _ = 1, 8 do RS.RenderStepped:Wait() end
		local f = cam.Focus.Position
		samples += 1
		closest = math.min(closest, (cam.CFrame.Position - f).Magnitude)
		if behind(params, f, cam.CFrame.Position) then bad += 1 end
	end
	player.CameraMinZoomDistance, player.CameraMaxZoomDistance = min0, max0
	return { samples = samples, behind = bad, closest = math.floor(closest * 10) / 10 }
end

-- a whole carry: waits up to args.wait seconds for it to start, samples until it ends
function Probes.chasecam(args)
	local RS = game:GetService("RunService")
	local player = game:GetService("Players").LocalPlayer
	local cam = workspace.CurrentCamera
	local t0 = os.clock()
	while not player:GetAttribute("Carrying") and os.clock() - t0 < ((args and args.wait) or 40) do task.wait(0.1) end
	if not player:GetAttribute("Carrying") then return { error = "the carry never started" } end
	local params = standIns()
	local row = workspace.SiliconValley:FindFirstChild("TalentRow")
	local frames, cuts, walls, moving, noRun, stutters, dtSum = 0, 0, 0, 0, 0, 0, 0
	local lastCF, lastHunter, lastStep
	local start = os.clock()
	while player:GetAttribute("Carrying") and os.clock() - start < 120 do
		local dt = RS.RenderStepped:Wait()
		frames += 1
		dtSum += dt
		local cf = cam.CFrame
		if lastCF then
			local moved = (cf.Position - lastCF.Position).Magnitude
			local turned = math.deg(math.acos(math.clamp(cf.LookVector:Dot(lastCF.LookVector), -1, 1)))
			if Probes.isCut(moved, turned) then cuts += 1 end
		end
		lastCF = cf
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and behind(params, root.Position + Vector3.new(0, 1.5, 0), cf.Position) then walls += 1 end
		local hunter
		for _, d in ipairs(row and row:GetChildren() or {}) do
			if d.Name == "Headhunter" and d:GetAttribute("ChasingUserId") == player.UserId then hunter = d break end
		end
		if hunter then
			local hp = hunter:GetPivot().Position
			if lastHunter then
				local step = (Vector3.new(hp.X, 0, hp.Z) - Vector3.new(lastHunter.X, 0, lastHunter.Z)).Magnitude
				if dt > 0 and step / dt > Probes.MOVING then
					moving += 1
					local runs = false
					local hum = hunter:FindFirstChildOfClass("Humanoid") or hunter:FindFirstChildOfClass("AnimationController")
					local animator = hum and hum:FindFirstChildOfClass("Animator")
					for _, tr in ipairs(animator and animator:GetPlayingAnimationTracks() or {}) do
						if tr.Animation and tr.Animation.AnimationId == Probes.RUN_ID then runs = true end
					end
					if not runs and not (hunter:GetAttribute("Windup") or hunter:GetAttribute("Lunging")) then noRun += 1 end
				end
				if lastStep and Probes.isStutter(lastStep, step) then stutters += 1 end
				lastStep = step
			end
			lastHunter = hp
		end
	end
	local secs = os.clock() - start
	return {
		seconds = math.floor(secs * 10) / 10, frames = frames, fps = frames > 0 and math.floor(frames / math.max(dtSum, 1e-3)) or 0,
		cuts = cuts, cutsPerSec = math.floor(cuts / math.max(secs, 0.1) * 100) / 100,
		behindWall = walls, hunterMovingFrames = moving, hunterNoRunFrames = noRun, hunterStutters = stutters,
	}
end

--[[ v8 Manage Staff phase 3 (14 Oct): open the TEAM screen on the top row (TeamClient's
	Open event, the same code a tap runs), read what it drew, run the screen probes on it
	while it is open, and close it. ]]
function Probes.team()
	local pg = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	local gui = pg:WaitForChild("Team", 10)
	local open = gui and gui:FindFirstChild("Open")
	if not open then return { error = "no TEAM screen" } end
	-- measure the screen, not a notice still up from the step before (a LOST! card after
	-- the chase, a toast): those are 3-4.5 s and sit over every menu alike
	local Notify = require(game:GetService("ReplicatedStorage"):WaitForChild("Notify"))
	local vp = workspace.CurrentCamera.ViewportSize
	local t0 = os.clock()
	while os.clock() - t0 < 8 do
		local toast = pg:FindFirstChild("NotifyToast")
		local pill = toast and toast:FindFirstChild("Toast", true)
		local toastUp = pill and pill.Visible and pill.AbsolutePosition.Y < vp.Y
		if not Notify.busy() and not toastUp then break end
		task.wait(0.25)
	end
	open:Fire(1)
	task.wait(0.6)
	local rows, top = 0, nil
	for _, r in ipairs(gui.Panel.Body.List:GetChildren()) do
		if r:IsA("GuiButton") and r.Visible then
			rows += 1
			if r.LayoutOrder == 1 then top = r end
		end
	end
	local face = gui.Panel.Body.Card.Face
	local out = Probes.ui()
	out.rows = rows
	out.cardOpen = face.Visible
	local nameLabel = face:FindFirstChild("Name")   -- the child label (face.Name is the frame's own name)
	out.name = nameLabel and nameLabel.Text
	out.topName = top and top.PersonName.Text
	local tb = face:FindFirstChild("Train_skill")
	out.skillButton = tb and tb.Label.Text
	-- live character views while open (spec §2: at most 9 on a phone)
	local vpf = 0
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("ViewportFrame") and d:FindFirstChildWhichIsA("Model") then vpf += 1 end
	end
	out.viewports = vpf
	open:Fire(false)
	return out
end

return Probes
