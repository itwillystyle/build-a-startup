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
--[[ P-5 (25 Oct): one Bob cutscene, end to end, on this client. args = { name = "intro"|"payoff",
	skipAt = seconds or nil }. Measures what the spec promises: it starts, it ends (or skips) into
	the same state -- camera Custom on the humanoid, no BobScene folder or BobSceneGui left, every
	ScreenGui that was on is on again, BobScenePlaying false -- and how long it ran. ]]
function Probes.bobscene(args)
	local player = game:GetService("Players").LocalPlayer
	local ev = player.PlayerGui:FindFirstChild("SVBobScene")
	if not ev then return { error = "no SVBobScene (BobSceneClient not running)" } end
	local before = {}
	for _, g in ipairs(player.PlayerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled then before[g] = true end
	end
	local name = args.name or "intro"
	ev:Fire(name, { amount = 0 })
	local t0 = os.clock()
	while player:GetAttribute("BobScenePlaying") ~= true and os.clock() - t0 < 3 do task.wait() end
	local started = player:GetAttribute("BobScenePlaying") == true
	local tStart = os.clock()
	--[[ 25 Oct guards: each is a mistake that reached Luke's screen that day, measured live.
		sounds   a Sound made at its cue was still loading 0.12 s later (late or silent): every scene
		         sound is loaded before the scene starts, and each one's playhead moves on its cue
		pops     poses switched in one frame (sitting to standing, 1.2 studs and 85 degrees at once): no
		         on-screen body jumps over 1 stud, no joint over 45 degrees (the snaps were 85-128; Bob's
		         kick, fast on purpose, turns 26), in a frame, out of near-stillness (3x its last frame's
		         move: a fall is fast but not a jump). A cut is where the camera jumps. Only STEADY frames
		         are judged: under 1/40 s and within 1.5x of the frame before (27 Oct: the gate failed once
		         on the hero spinning through the air, 2.30 studs at 6.87 s, not a snap. Measured: the
		         spin swings his root between 12 and 45 studs/s, so with uneven frames one frame's move is
		         3x the last; every other frame 13 ms late gave 3 false snaps. And the kick turns 47 in
		         a 0.03 s frame). Studio runs at 2-3 FPS while it is the focused window
		ambience the valley's birds sang under the boardroom (0.22): silent while a scene plays ]]
	local SS, RunService = game:GetService("SoundService"), game:GetService("RunService")
	local BobScript = require(game:GetService("ReplicatedStorage"):WaitForChild("BobScript"))
	-- a jump the script asks for (an actor moved to another set: the hero to Bob's door at 6.3 s) is
	-- not a pop. (The probe's clock runs a frame or two off the scene's, so look 0.1 s either side)
	local function moved(id, t)
		local function at(x) local a = BobScript.at(name, math.clamp(x, 0, BobScript.length(name) - 0.01), true).actors[id] return a and a.anchor end
		return at(t - 0.1) ~= at(t + 0.1)
	end
	local bank = SS:FindFirstChild("BobSceneSounds")
	local banked = bank and #bank:GetChildren() or 0
	local notLoaded, stuck, played = 0, {}, 0
	for _, s in ipairs(bank and bank:GetChildren() or {}) do
		if not s.IsLoaded then notLoaded += 1 end
		s.Played:Connect(function()
			played += 1
			local p0 = s.TimePosition
			task.wait(0.12)
			if s.Parent and s.IsPlaying and s.TimePosition < p0 + 0.05 then table.insert(stuck, s.Name) end
		end)
	end
	local folder, cam = workspace:FindFirstChild("BobScene"), workspace.CurrentCamera
	local last, lastCam, cutAt, pops = {}, nil, 0, {}
	local lastDt, steady = nil, 0
	local ambience = 0
	local conn = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - tStart
		if not (folder and folder.Parent) then return end
		local c = cam.CFrame
		if lastCam and ((c.Position - lastCam.Position).Magnitude > 3 or c.LookVector:Dot(lastCam.LookVector) < 0.94) then cutAt = t end
		lastCam = c
		local even = lastDt ~= nil and dt < 1 / 40 and dt < lastDt * 1.5 and lastDt < dt * 1.5
		lastDt = dt
		local settled = t - cutAt > 0.05 and t > 0.2 and even   -- (a cut moves everything at once)
		if settled then steady += 1 end
		for _, m in ipairs(folder:GetChildren()) do
			if m:IsA("Model") and m.PrimaryPart then
				local _, onScreen = cam:WorldToViewportPoint(m.PrimaryPart.Position)
				local j = {}
				for _, mo in ipairs(m:GetDescendants()) do if mo:IsA("Motor6D") then j[mo.Name] = mo.Transform end end
				local L = last[m]
				local d, turn = 0, {}
				if L then
					d = (m.PrimaryPart.Position - L.pos).Magnitude
					for jn, cf in pairs(j) do
						local o = L.j[jn]
						turn[jn] = o and math.deg(math.acos(math.clamp(cf.LookVector:Dot(o.LookVector), -1, 1))) or 0
					end
					if L.onScreen and onScreen and settled and not moved(m.Name, t) then
						if d > 1 and d > 3 * L.d then table.insert(pops, ("%.2f s %s moved %.2f studs"):format(t, m.Name, d)) end
						for jn, deg in pairs(turn) do
							if deg > 45 and deg > 3 * (L.turn[jn] or 0) then table.insert(pops, ("%.2f s %s %s %.0f deg"):format(t, m.Name, jn, deg)) end
						end
					end
				end
				last[m] = { pos = m.PrimaryPart.Position, j = j, onScreen = onScreen, d = d, turn = turn }
			end
		end
		if t > 1 then
			for _, n in ipairs({ "ValleyBirds", "ValleyCrickets" }) do
				local s = SS:FindFirstChild(n)
				if s and s.IsPlaying then ambience = math.max(ambience, s.Volume) end
			end
		end
	end)
	while player:GetAttribute("BobScenePlaying") == true and os.clock() - tStart < 30 do
		if args.skipAt and os.clock() - tStart >= args.skipAt then player:SetAttribute("BobSkipNow", true) end
		task.wait()
	end
	conn:Disconnect()
	local ran = os.clock() - tStart
	player:SetAttribute("BobSkipNow", nil)
	task.wait(0.3)
	local cam = workspace.CurrentCamera
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local lost = {}
	-- the Guide steps aside on purpose while a menu is open (GuideClient: Enabled = ... and not menu); on a
	-- fresh join the Daily reward opens as the intro ends. Measured 26 Oct: Guide back 0.05 s after Daily
	-- closed. So it is lost only if it is off with no menu up. Every other GUI must be back regardless.
	local menuUp = require(game:GetService("ReplicatedStorage"):WaitForChild("UIKit")).menuOpen()
	for g in pairs(before) do
		if g.Parent and not g.Enabled and not (g.Name == "Guide" and menuUp) then table.insert(lost, g.Name) end
	end
	local checks = {
		{ name = "bob " .. name .. ": started", ok = started, measured = started, expected = true },
		{ name = "bob " .. name .. ": camera Custom after", ok = cam.CameraType == Enum.CameraType.Custom, measured = tostring(cam.CameraType), expected = "Custom" },
		{ name = "bob " .. name .. ": camera on the humanoid", ok = hum ~= nil and cam.CameraSubject == hum, measured = cam.CameraSubject and cam.CameraSubject.ClassName or "nil", expected = "Humanoid" },
		-- (the payoff's toast keeps its gui 3 s on purpose; the actors and props must still be gone)
		{ name = "bob " .. name .. ": nothing left behind", ok = workspace:FindFirstChild("BobScene") == nil
			and (name == "payoff" or player.PlayerGui:FindFirstChild("BobSceneGui") == nil),
			measured = tostring(workspace:FindFirstChild("BobScene") ~= nil), expected = "false" },
		{ name = "bob " .. name .. ": HUD back", ok = #lost == 0, measured = #lost == 0 and 0 or table.concat(lost, ", "), expected = 0 },
		{ name = "bob " .. name .. ": playing flag cleared", ok = player:GetAttribute("BobScenePlaying") ~= true, measured = player:GetAttribute("BobScenePlaying"), expected = false },
		{ name = "bob " .. name .. ": every sound loaded before it starts", ok = banked > 0 and notLoaded == 0,
			measured = banked == 0 and "no sound bank" or (notLoaded .. " of " .. banked .. " not loaded"), expected = "0 not loaded" },
		-- (a skipped scene plays only its first sounds; a check that saw none proves nothing)
		{ name = "bob " .. name .. ": every sound plays on its cue", ok = played >= (args.skipAt and 1 or 10) and #stuck == 0,
			measured = #stuck == 0 and (played .. " played, all moving") or table.concat(stuck, ", "), expected = "all moving" },
		-- (a run with almost no steady frames proves nothing: say so, never pass it; a skipped scene is short)
		{ name = "bob " .. name .. ": nothing snaps inside a shot", ok = #pops == 0 and steady >= (args.skipAt and 30 or 200),
			measured = #pops > 0 and (#pops .. ": " .. table.concat(pops, "; ", 1, math.min(#pops, 3)))
				or (steady < (args.skipAt and 30 or 200) and ("only " .. steady .. " steady frames to judge (Studio lagging)") or "none"),
			expected = "none" },
		{ name = "bob " .. name .. ": the valley's ambience is silent under it", ok = ambience < 0.01, measured = ambience, expected = 0 },
	}
	return { checks = checks, ran = math.floor(ran * 100) / 100, steady = steady }
end

--[[ 27 Oct: a scene that breaks while it loads (here: a name BobScript has no scene for) must still
	let go. Before the fix the setup ran outside the scene's pcall, so a throw there left "loading" and
	`playing` on for good: Bob's door never came back and no Bob scene could play again that session. ]]
-- Three breaks: a scene name BobScript does not know (it throws at once); the Studio-only fault
-- BobSceneFailAt = "bubbles" (it throws with the sound bank already in SoundService, so a bank left
-- behind is caught; the cast is not in the world yet at that point, so it is not checked); then an
-- unknown name again, which only reaches "failed" if `playing` let go (a stuck scene returns early).
-- The fault clears itself and sets BobSceneFailHit, so a pass proves it was reached (review round 2).
function Probes.bobbroken()
	local player = game:GetService("Players").LocalPlayer
	local ev = player.PlayerGui:FindFirstChild("SVBobScene")
	if not ev then return { error = "no SVBobScene (BobSceneClient not running)" } end
	local SS = game:GetService("SoundService")
	local function breakOne(name, failAt, wait)
		player:SetAttribute("BobSceneState", nil)   -- a stale "failed" would pass at once (review round 1)
		player:SetAttribute("BobSceneFailHit", nil)
		player:SetAttribute("BobSceneFailAt", failAt)
		ev:Fire(name, { amount = 0 })
		local t0 = os.clock()
		while player:GetAttribute("BobSceneState") ~= "failed" and os.clock() - t0 < wait do task.wait() end
		player:SetAttribute("BobSceneFailAt", nil)   -- in case it was never reached
		return player:GetAttribute("BobSceneState")
	end
	local unknown = breakOne("doctor-no-such-scene", nil, 4)
	-- 20 s: the fault sits after the cast wait and the sound preload (up to 4 s, more on a cold join)
	local late = breakOne("intro", "bubbles", 20)
	local hit = player:GetAttribute("BobSceneFailHit") == true
	player:SetAttribute("BobSceneFailHit", nil)
	local bankLeft = SS:FindFirstChild("BobSceneSounds") ~= nil
	local again = breakOne("doctor-no-such-scene", nil, 4)
	return { checks = {
		{ name = "bob broken scene: an unknown scene lets go", ok = unknown == "failed", measured = tostring(unknown), expected = "failed" },
		{ name = "bob broken scene: a late break lets go", ok = hit and late == "failed",
			measured = (hit and "fault hit, " or "fault NOT reached, ") .. tostring(late), expected = "fault hit, failed" },
		{ name = "bob broken scene: no sound bank left behind", ok = not bankLeft, measured = bankLeft, expected = false },
		-- (only a late break that really happened proves `playing` let go: else this is not judged, and fails)
		{ name = "bob broken scene: a scene can start after", ok = hit and late == "failed" and again == "failed",
			measured = (hit and late == "failed") and tostring(again) or "not judged: the late break did not happen", expected = "failed" },
	} }
end

--[[ 27 Oct: after you beat Bob your door stands open (BobDoorClient: 100 degrees about its hinge).
	Measured from the server's shut door (the door's ClosedCF), never from where the door is now:
	before the fix a replayed payoff read the open door as shut and left it at 160 degrees. ]]
function Probes.bobdoor()
	local player = game:GetService("Players").LocalPlayer
	local sv = workspace:FindFirstChild("SiliconValley")
	local door = sv and sv:FindFirstChild("BobCapital") and sv.BobCapital:FindFirstChild("Door")
	local shut = door and door:GetAttribute("ClosedCF")
	if not shut then return { error = door and "the door has no ClosedCF" or "no Bob Capital door" } end
	local t0 = os.clock()
	while player:GetAttribute("BobSceneState") == "playing" and os.clock() - t0 < 30 do task.wait(0.2) end
	task.wait(1)
	local want = player:GetAttribute("BobPaid") == true and 100 or 0
	-- 27 Oct: the whole pose, not the turn alone (a door shoved off its hinge, or tipped, read as right):
	-- where BobDoorClient puts it, about the hinge at its left edge, and how far it is from there
	local hinge = shut * CFrame.new(-door.Size.X / 2, 0, 0)
	local should = want == 0 and shut or hinge * CFrame.Angles(0, math.rad(-want), 0) * CFrame.new(door.Size.X / 2, 0, 0)
	local off = should:ToObjectSpace(door.CFrame)
	local _, angle = off:ToAxisAngle()
	local studs, deg = off.Position.Magnitude, math.deg(math.abs(angle))
	return { checks = {
		{ name = "bob door: " .. (want == 100 and "open" or "shut") .. " as it should be", ok = studs < 0.1 and deg < 3,
			measured = ("%.2f studs, %d deg off"):format(studs, math.floor(deg + 0.5)), expected = "under 0.1 studs, 3 deg" },
	} }
end

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
-- 27 Oct: the doctor's own self-test (GameDoctor step "doctor"): an error printed on purpose, then an
-- answer only after `hold` seconds, so the server's probe times out first
function Probes.selftest(args)
	task.spawn(error, "[doctor self-test] a late client error, on purpose")
	task.wait(args.hold or 3)
	return { held = args.hold or 3 }
end

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
	-- 24 Oct: Roblox's Background Transparency setting, forced through ForcePreferredTransparency.
	-- A card drawn see-through (0.3) goes solid at 0, follows a live change, and comes back at 1.
	local ptBefore = player:GetAttribute("ForcePreferredTransparency")
	local function settle() for _ = 1, 3 do RunService.Heartbeat:Wait() end end
	local function r2(x) return math.floor(x * 100 + 0.5) / 100 end
	local ok3, err3 = pcall(function()
		player:SetAttribute("ForcePreferredTransparency", 0)
		settle()
		add("Background Transparency is forced to 0", UIKit.preferredTransparency() == 0, UIKit.preferredTransparency(), 0)
		local card = UIKit.card(gui, { Size = UDim2.new(0, 100, 0, 40), BackgroundTransparency = 0.3 })
		add("a see-through card is solid at 0", card.BackgroundTransparency == 0, r2(card.BackgroundTransparency), 0)
		player:SetAttribute("ForcePreferredTransparency", 0.5)
		settle()
		add("the card follows a live change", math.abs(card.BackgroundTransparency - 0.15) < 0.01, r2(card.BackgroundTransparency), 0.15)
		player:SetAttribute("ForcePreferredTransparency", 1)
		settle()
		add("the card is back to its design at 1", math.abs(card.BackgroundTransparency - 0.3) < 0.01, r2(card.BackgroundTransparency), 0.3)
		local plain = UIKit.card(gui, { Size = UDim2.new(0, 100, 0, 40) })
		player:SetAttribute("ForcePreferredTransparency", 0)
		settle()
		add("a solid card stays solid", plain.BackgroundTransparency == 0, r2(plain.BackgroundTransparency), 0)
		local box = UIKit.label(gui, "", UIKit.TYPE.body, UIKit.INK, {})
		add("a label gets no background", box.BackgroundTransparency == 1, r2(box.BackgroundTransparency), 1)
	end)
	player:SetAttribute("ForcePreferredTransparency", ptBefore)
	gui:Destroy()
	if not ok then add("the reduced-motion half ran", false, tostring(err), "no error") end
	if not ok2 then add("the motion-on half ran", false, tostring(err2), "no error") end
	if not ok3 then add("the background-transparency part ran", false, tostring(err3), "no error") end
	return { checks = checks }
end

return Probes
