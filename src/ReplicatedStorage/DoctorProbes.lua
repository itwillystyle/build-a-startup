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
	  lookcam   (22 Oct, art pass) holds the camera on a named review spot so a
	            screenshot can be measured by tools/look_stats.py. The one probe
	            that moves the camera; it hands it back when the hold ends.

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
			local isText = o:IsA("TextLabel") or o:IsA("TextButton")
			table.insert(cut, { path = path(o, it.gui), fits = Slop.fitsOf(isText, isText and o.Text or nil, isText and o.TextFits or nil),
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
	-- v2 layout (the redesign): the faces column, the person in the middle, TRAIN on the right
	local rows = 0
	local faces = gui:FindFirstChild("Faces", true)
	for _, r in ipairs(faces and faces:GetChildren() or {}) do
		if r:IsA("GuiButton") and r.Visible then rows += 1 end
	end
	local person = gui:FindFirstChild("Person", true)
	local out = Probes.ui()
	out.rows = rows
	out.cardOpen = person ~= nil and person.Visible
	local nameLabel = person and person:FindFirstChild("PersonName")
	out.name = nameLabel and nameLabel.Text
	local tb = gui:FindFirstChild("Train_skill", true)
	out.skillButton = tb and tb:FindFirstChild("Label") and tb.Label.Text
	-- live character views while open (spec §2: at most 9 on a phone)
	local vpf = 0
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("ViewportFrame") and d:FindFirstChildWhichIsA("Model") then vpf += 1 end
	end
	out.viewports = vpf
	open:Fire(false)
	return out
end

--[[ v9 (15 Oct, HQ part 1b): ride along. Samples the local character against the lift cab every
	frame for args.seconds: the biggest frame-to-frame change of its offset from the cab while the
	cab moves (a shake), whether it ever dropped below the cab floor (a fall), and the measured ride
	time (first to last frame the cab's State was "moving"). ]]
function Probes.liftride(args)
	local RS = game:GetService("RunService")
	local CS = game:GetService("CollectionService")
	local player = game:GetService("Players").LocalPlayer
	local cab
	for _, m in ipairs(CS:GetTagged("LiftCab")) do if m:GetAttribute("Plot") == args.plot then cab = m end end
	if not cab then return { error = "no cab" } end
	local t0, last, maxSlip, fell, movedFrom, movedTo = os.clock(), nil, 0, false, nil, nil
	while os.clock() - t0 < (args.seconds or 8) do
		RS.RenderStepped:Wait()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local base = cab.PrimaryPart
		if root and base then
			local off = base.CFrame:PointToObjectSpace(root.Position)
			local moving = cab:GetAttribute("State") == "moving"
			if moving then
				movedFrom = movedFrom or os.clock()
				movedTo = os.clock()
				if last then maxSlip = math.max(maxSlip, (off - last).Magnitude) end
				if off.Y < 0.5 then fell = true end
			end
			last = off
		end
	end
	return { maxSlip = math.floor(maxSlip * 100) / 100, fell = fell, rideSeconds = movedFrom and math.floor((movedTo - movedFrom) * 100) / 100 or -1 }
end

--[[ 22 Oct (art pass 1, spec section 6): the review cameras, in the garage's own
	frame (SiliconCore buildShell: GarageFloor sits at g(0, -2, 0); the desk at z -9,
	the door at z +14.5). C1 matches Luke's 21 Oct shot from beside the laptop; C2 is
	the garage-outside mock's view of the forecourt. C3/C4 belong to plans 3 and 4. ]]
Probes.LOOK_CAMS = {
	C1 = { eye = Vector3.new(-5.5, 7.5, -13.5), at = Vector3.new(9, 3.5, 5) },
	C2 = { eye = Vector3.new(0, 9, 52), at = Vector3.new(0, 5, 10) },
}
--[[ 24 Oct (art pass 4, Task 1): C3, the tower office. The doctor's own department mix has no desk
	room at level 13 or above (WaferPlan.recommend), so the scenario office:<dept> builds the room it
	needs: it pins that department at L, then rebuilds to hq. Each L except the lobby is a seg 3 room,
	so the floor station is in the view. ]]
Probes.REVIEW_ROOM = {
	eng = { L = 13, hq = 18 }, studio = { L = 13, hq = 18 }, cafe = { L = 13, hq = 18 },
	servers = { L = 13, hq = 18 }, labs = { L = 22, hq = 26 }, board = { L = 72, hq = 72 },
	lobby = { L = 2, hq = 18 },
}
-- the C3 pose in a room's own frame (origin at the room centre on the floor, +Z out to the facade):
-- the front-left corner, head high, looking across the room and a little back, so the glass is on the
-- right and the feature wall ahead, as in the mock (ui/art-pass/tower-office.png)
function Probes.roomCam(r)
	return Vector3.new(-r.w / 2 + 3.5, 6.5, r.d / 2 - 7), Vector3.new(r.w / 2 - 4, 3, -r.d / 6)
end

-- C3: the plot's L<level> room, from its Storey/Seg attributes and the plot folder's Pivot
local function roomFrame(plot, level)
	local wf = plot:FindFirstChild("Wafers")
	local pv = plot:GetAttribute("Pivot")
	if not (wf and typeof(pv) == "CFrame") then return nil, "no tower on this plot" end
	local prefix = ("L%03d_segment"):format(level)
	for _, m in ipairs(wf:GetChildren()) do
		if m.Name:sub(1, #prefix) == prefix then
			local storey, seg = m:GetAttribute("Storey"), m:GetAttribute("Seg")
			if not (storey and seg) then return nil, m.Name .. " has no Storey/Seg" end
			local T = require(script.Parent:WaitForChild("TowerPlan"))
			local f = T.frame({ kind = "segment", storey = storey, seg = seg })
			local anchor = pv * CFrame.new(f.x, T.floorY(storey), f.z) * CFrame.Angles(0, f.yaw, 0)   -- as Wafers.anchor
			return anchor, T.room(storey, seg)
		end
	end
	return nil, ("no room at L%d (run office:<dept> first)"):format(level)
end

function Probes.lookcam(args)
	args = args or {}
	local name = args.cam or "C1"
	local player = game:GetService("Players").LocalPlayer
	local plotNo = player:GetAttribute("Plot")
	local plot = plotNo and workspace:FindFirstChild("SiliconValley") and workspace.SiliconValley.Plots:FindFirstChild("Plot" .. plotNo)
	if name == "C3" then
		if not plot then return { ok = false, why = "no plot" } end
		local level = tonumber(args.level) or Probes.REVIEW_ROOM.eng.L
		local anchor, r = roomFrame(plot, level)
		if not anchor then return { ok = false, why = r } end
		local eye, at = Probes.roomCam(r)
		local cam = workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = CFrame.lookAt(anchor:PointToWorldSpace(eye), anchor:PointToWorldSpace(at))
		task.delay(tonumber(args.hold) or 6, function() cam.CameraType = Enum.CameraType.Custom end)
		return { ok = true, cam = name, level = level }
	end
	local spot = Probes.LOOK_CAMS[name]
	if not spot then return { ok = false, why = "no camera " .. tostring(name) .. " yet (plan 3)" } end
	local floor = plot and plot:FindFirstChild("GarageFloor", true)
	if not floor then return { ok = false, why = "no garage (the review cameras are for the garage levels)" } end
	local g = floor.CFrame * CFrame.new(0, 2, 0)
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CFrame.lookAt(g:PointToWorldSpace(spot.eye), g:PointToWorldSpace(spot.at))
	task.delay(tonumber(args.hold) or 6, function() cam.CameraType = Enum.CameraType.Custom end)
	return { ok = true, cam = name }
end

--[[ 23 Oct: the motion layer under Reduce Motion, measured on the client (the consensus plan's
	reduced-motion check, FINAL.md point 9: the server cannot hold a button, so the layer itself is
	driven here). Forces ForceReducedMotion for the run and puts it back. Every number is read
	from the real instances UIKit.tween moved. ]]
function Probes.motion()
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local UIKit = require(script.Parent:WaitForChild("UIKit"))
	local player = Players.LocalPlayer
	local before = player:GetAttribute("ForceReducedMotion")
	player:SetAttribute("ForceReducedMotion", true)
	local gui = Instance.new("ScreenGui")
	gui.Name = "DoctorMotionProbe"
	gui.Enabled = false   -- nothing on screen
	gui.Parent = player:WaitForChild("PlayerGui")
	local checks = {}
	local function add(name, ok, measured, expected)
		table.insert(checks, { name = name, ok = ok == true, measured = measured, expected = expected })
	end
	local function frame()
		local f = Instance.new("Frame")
		f.Size = UDim2.new(0, 0, 0, 10)
		f.Position = UDim2.new(0, 0, 0, 0)
		f.Parent = gui
		return f
	end
	local function completes(tw, within)
		if tw.PlaybackState == Enum.PlaybackState.Completed then return true end
		local done = false
		local c = tw.Completed:Connect(function() done = true end)
		local t0 = os.clock()
		while not done and os.clock() - t0 < within do RunService.Heartbeat:Wait() end
		c:Disconnect()
		return done
	end
	--[[ 23 Oct (phase 2, the camera): a 1.2 s three-shot cutscene where the camera already is, sampled
		every frame -> how many frames sat on one of the shots, how many were between them (a flight) ]]
	local MotionSpec = require(script.Parent:WaitForChild("MotionSpec"))
	local function flight()
		local Cine = require(script.Parent:WaitForChild("Cine"))
		local cam = workspace.CurrentCamera
		if cam.CameraType ~= Enum.CameraType.Custom or Cine.busy() then return nil end
		local p0 = cam.CFrame.Position
		local fwd = cam.CFrame.LookVector
		local shots = {
			{ pos = p0, look = p0 + fwd * 60, t = 0 },
			{ pos = p0 + Vector3.new(0, 12, 0), look = p0 + fwd * 60, t = 0.6 },
			{ pos = p0 + Vector3.new(0, 24, 0), look = p0 + fwd * 60, t = 0.6 },
		}
		local on, between, done = 0, 0, false
		local conn = RunService.RenderStepped:Connect(function()
			if not Cine.busy() then return end
			local at = cam.CFrame.Position
			local near = false
			for _, sh in ipairs(shots) do
				if (at - sh.pos).Magnitude < 0.05 then near = true end
			end
			if near then on += 1 else between += 1 end
		end)
		task.spawn(function()
			Cine.play(shots, { letterbox = false, skippable = false })
			done = true
		end)
		local t0 = os.clock()
		while not done and os.clock() - t0 < 4 do task.wait() end
		conn:Disconnect()
		return { on = on, between = between, done = done, back = cam.CameraType == Enum.CameraType.Custom }
	end
	local ok, err = pcall(function()
		add("Reduce Motion is on for the probe", UIKit.reducedMotion() == true, UIKit.reducedMotion(), true)
		-- 23 Oct (phase 2): the camera policy is the reduced one
		local lens = MotionSpec.camera(UIKit.reducedMotion())
		add("the camera policy is still: no shake, no punch, no speed zoom, cuts",
			lens.shake == 0 and not lens.punch and not lens.zoom and lens.speedFov == 0 and lens.flight == "cut" and not lens.turn,
			("shake %s punch %s zoom %s speedFov %s flight %s turn %s"):format(tostring(lens.shake), tostring(lens.punch),
				tostring(lens.zoom), tostring(lens.speedFov), lens.flight, tostring(lens.turn)), "0 false false 0 cut false")
		local fl = flight()
		if fl then
			add("a cutscene under Reduce Motion cuts (every frame sits on a shot)", fl.done and fl.on > 0 and fl.between == 0,
				("%d on a shot, %d between"):format(fl.on, fl.between), "0 frames between shots")
			add("the cut cutscene hands the camera back", fl.back, fl.back and "Custom" or "not Custom", "Custom")
		else
			add("a cutscene could run (camera Custom, no cutscene playing)", false, tostring(workspace.CurrentCamera.CameraType), "Enum.CameraType.Custom")
		end
		-- a fill that measures time keeps its time (the spin-off hold, the coding bar)
		local a = frame()
		local ta = UIKit.tween(a, 1, { Size = UDim2.new(0, 100, 0, 10) }, Enum.EasingStyle.Linear, nil, { kind = "progress" })
		task.wait(0.5)
		local half = a.Size.X.Offset
		add("a progress fill still takes its time", half >= 30 and half <= 70, half, "about 50 of 100 at 0.5 s")
		add("the progress tween completes", completes(ta, 1.5), ta.PlaybackState.Name, "Completed")
		-- movement lands on the same frame
		local b = frame()
		local tb = UIKit.tween(b, 1, { Position = UDim2.new(0, 77, 0, 0) })
		add("movement lands at once", b.Position.X.Offset == 77, b.Position.X.Offset, 77)
		add("an instant tween still completes", completes(tb, 0.6), tb.PlaybackState.Name, "Completed")
		-- a fade still plays
		local c = frame()
		c.BackgroundTransparency = 0
		-- linear, so the halfway value is unambiguous (Quint Out is already at 97% halfway: the first
		-- live run read 0.77 and called a playing fade "not playing")
		UIKit.tween(c, 0.4, { BackgroundTransparency = 0.8 }, Enum.EasingStyle.Linear)
		task.wait(0.2)
		local mid = c.BackgroundTransparency
		add("a fade still plays", mid > 0.2 and mid < 0.6, math.floor(mid * 100) / 100, "about 0.4 at 0.2 s (linear 0 -> 0.8 over 0.4 s)")
		-- an exit fades in place: its drift is dropped
		local d = frame()
		local te = UIKit.tween(d, 0.3, { Position = UDim2.new(0, 0, 0, -40), BackgroundTransparency = 1 })
		task.wait(0.05)
		add("an exit stays put", d.Position.Y.Offset == 0, d.Position.Y.Offset, 0)
		add("the exit's fade completes", completes(te, 0.8), te.PlaybackState.Name, "Completed")
		-- small scale feedback keeps playing; a big pop lands at once
		local sc = Instance.new("UIScale")
		sc.Scale = 0.94
		sc.Parent = frame()
		UIKit.tween(sc, 0.4, { Scale = 1 })
		task.wait(0.05)
		add("a small press/pop still plays", sc.Scale > 0.94 and sc.Scale < 1, math.floor(sc.Scale * 1000) / 1000, "between 0.94 and 1")
		local big = Instance.new("UIScale")
		big.Scale = 0.4
		big.Parent = frame()
		UIKit.tween(big, 0.4, { Scale = 1 })
		add("a big pop lands at once", big.Scale == 1, big.Scale, 1)
		-- the HUD's coin stream under Reduce Motion (23 Oct review of the layer, items 1-2): every coin
		-- is reported (the first-ship count is driven by these calls) and the moment keeps its length
		local stream = rawget(_G, "SVCoinStream")
		if type(stream) == "function" then
			local calls, doneAt = 0, nil
			local t0 = os.clock()
			stream(Vector2.new(200, 200), 12, function() doneAt = os.clock() - t0 end, 0, {
				onCoin = function() calls += 1 end,
			})
			local w = os.clock()
			while not doneAt and os.clock() - w < 3 do task.wait() end
			add("a reduced coin stream reports every coin", calls == 12, calls, 12)
			add("a reduced coin stream keeps its length", doneAt ~= nil and doneAt >= 0.8, doneAt and math.floor(doneAt * 100) / 100 or "never", ">= 0.8 s")
		else
			add("the HUD coin stream exists", false, "missing", "_G.SVCoinStream")
		end
	end)
	-- motion back on: UIKit.set beats a running tween, and a replaced tween finishes instead of freezing
	player:SetAttribute("ForceReducedMotion", false)
	local ok2, err2 = pcall(function()
		-- 23 Oct (phase 2): the same session, the setting turned off: the same cutscene flies again
		local fl = flight()
		if fl then
			add("with motion on the cutscene flies (frames between the shots)", fl.done and fl.between > 0,
				("%d on a shot, %d between"):format(fl.on, fl.between), "> 0 frames between shots")
		end
		local e = frame()
		UIKit.tween(e, 1, { Size = UDim2.new(0, 1000, 0, 10) }, Enum.EasingStyle.Linear)
		task.wait(0.2)
		UIKit.set(e, { Size = UDim2.new(0, 5, 0, 10) })
		task.wait(0.3)
		add("UIKit.set holds against a running tween", e.Size.X.Offset == 5, e.Size.X.Offset, 5)
		local f = frame()
		f.BackgroundTransparency = 0
		UIKit.tween(f, 1, { Size = UDim2.new(0, 300, 0, 10), BackgroundTransparency = 0.6 }, Enum.EasingStyle.Linear)
		task.wait(0.2)
		UIKit.tween(f, 0.2, { Size = UDim2.new(0, 10, 0, 10) })
		add("a replaced tween finishes its other goals (no half fade)", math.abs(f.BackgroundTransparency - 0.6) < 0.01,
			math.floor(f.BackgroundTransparency * 100) / 100, 0.6)
	end)
	player:SetAttribute("ForceReducedMotion", before)
	gui:Destroy()
	if not ok then add("the reduced-motion half ran", false, tostring(err), "no error") end
	if not ok2 then add("the motion-on half ran", false, tostring(err2), "no error") end
	return { checks = checks }
end

return Probes
