--[[ LobbyMomentClient (v9, 15 Oct 2026, HQ part 1c): the garage becomes the lobby.
	The server has already built the lobby (and stashed the garage) when LobbyMoment arrives. This
	plays the ~4.4 s moment on this screen only: scaffold up, the garage (a copy kept while we were at
	level 1) folds flat, the lobby's columns, glass and roof rise in steps with a tick each and a sting,
	the scaffold drops, a look-up, the camera back to you. Skip at any time. Every lobby part ends
	exactly where the server has it, whatever happens. Spec: docs/superpowers/specs/2026-10-15-hq-garage-1c-design.md ]]
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local T = require(RS:WaitForChild("TowerPlan"))
local LM = require(RS:WaitForChild("LobbyMoment"))
local Cine = require(RS:WaitForChild("Cine"))
local UIKit = require(RS:WaitForChild("UIKit"))
local Notify = require(RS:WaitForChild("Notify"))
local remote = RS:WaitForChild("SVRemotes"):WaitForChild("LobbyMoment")

-- ---------------------------------------------------------------- the garage, kept while we are in one
local copy           -- a Model: everything Wafers.garage will stash, never parented until the moment
local STRIP = { ProximityPrompt = true, ClickDetector = true, Script = true, LocalScript = true,
	ModuleScript = true, Sound = true, ParticleEmitter = true }
local function garageFolder()
	local sv = workspace:FindFirstChild("SiliconValley")
	local plots = sv and sv:FindFirstChild("Plots")
	local p = plots and plots:FindFirstChild("Plot" .. tostring(player:GetAttribute("Plot")))
	return p and p:FindFirstChild("Garage")
end
local function snapshot()
	if (player:GetAttribute("WaferLevel") or 1) > 1 then return end
	local g = garageFolder()
	if not g then return end
	local m = Instance.new("Model")
	m.Name = "GarageCopy"
	for _, c in ipairs(g:GetChildren()) do
		if not T.GARAGE_KEEP[c.Name] and not STRIP[c.ClassName] then
			local ok, k = pcall(function() return c:Clone() end)
			if ok and k then
				for _, d in ipairs(k:GetDescendants()) do if STRIP[d.ClassName] then d:Destroy() end end
				k.Parent = m
			end
		end
	end
	if #m:GetChildren() == 0 then m:Destroy() return end
	if copy then copy:Destroy() end
	copy = m
end
player:GetAttributeChangedSignal("WaferLevel"):Connect(function()
	if (player:GetAttribute("WaferLevel") or 1) <= 1 then task.delay(2, snapshot) end   -- a spin-off: a garage again
end)
task.delay(5, snapshot)

-- ---------------------------------------------------------------- the moment
local function vec(pivot, v) return (pivot * CFrame.new(v[1], v[2], v[3])).Position end

local function scaffoldAround(pivot, x0, x1, z0, z1, y0, h)
	local m = Instance.new("Model")
	m.Name = "MomentScaffold"
	local function bar(cf, size, color, transparency)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Size, p.CFrame, p.Color, p.Material = size, cf, color, Enum.Material.SmoothPlastic
		p.Transparency = transparency or 0
		p.Parent = m
	end
	local steel, band = Color3.fromRGB(150, 156, 166), Color3.fromRGB(40, 110, 230)   -- world colours
	x0, x1, z0, z1 = x0 - 2, x1 + 2, z0 - 2, z1 + 2
	for x = x0, x1, 6 do for _, z in ipairs({ z0, z1 }) do bar(pivot * CFrame.new(x, y0 + h / 2, z), Vector3.new(0.3, h, 0.3), steel) end end
	for z = z0, z1, 6 do for _, x in ipairs({ x0, x1 }) do bar(pivot * CFrame.new(x, y0 + h / 2, z), Vector3.new(0.3, h, 0.3), steel) end end
	for y = y0 + 4, y0 + h - 1, 6 do
		for _, z in ipairs({ z0, z1 }) do bar(pivot * CFrame.new((x0 + x1) / 2, y, z), Vector3.new(x1 - x0, 0.25, 0.25), steel) end
		for _, x in ipairs({ x0, x1 }) do bar(pivot * CFrame.new(x, y, (z0 + z1) / 2), Vector3.new(0.25, 0.25, z1 - z0), steel) end
	end
	-- the blue "still building" band round the top
	for _, z in ipairs({ z0 - 0.3, z1 + 0.3 }) do bar(pivot * CFrame.new((x0 + x1) / 2, y0 + h - 2, z), Vector3.new(x1 - x0, 4, 0.15), band, 0.25) end
	for _, x in ipairs({ x0 - 0.3, x1 + 0.3 }) do bar(pivot * CFrame.new(x, y0 + h - 2, (z0 + z1) / 2), Vector3.new(0.15, 4, z1 - z0), band, 0.25) end
	m.Parent = workspace
	return m
end

local playing = false
local function play(e)
	if playing or typeof(e) ~= "table" or typeof(e.pivot) ~= "CFrame" then return end
	playing = true
	local pivot = e.pivot
	local up = pivot.UpVector

	-- the lobby's parts by group, with where the server has them
	local groups = { columns = {}, glass = {}, roof = {}, canopy = {} }
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	local function add(p)
		if not p:IsA("BasePart") or p.Transparency >= 1 then return end
		local list = groups[LM.groupOf(p.Name)]
		if not list then return end   -- the floor stays put
		table.insert(list, { part = p, cf = p.CFrame })
		local l = pivot:PointToObjectSpace(p.Position)
		lo, hi = lo:Min(l), hi:Max(l)
	end
	for _, m in ipairs(e.models or {}) do
		if typeof(m) == "Instance" then for _, d in ipairs(m:GetDescendants()) do add(d) end end
	end
	for _, p in ipairs(e.core or {}) do if typeof(p) == "Instance" then add(p) end end
	if typeof(e.cab) == "Instance" then for _, d in ipairs(e.cab:GetDescendants()) do add(d) end end

	-- the garage copy: each part folds out on its side, or lifts away
	local garage = copy
	copy = nil
	local folds = {}
	if garage then
		garage.Parent = workspace
		local glo, ghi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
		local parts = {}
		for _, d in ipairs(garage:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false
				local l = pivot:PointToObjectSpace(d.Position)
				glo, ghi = glo:Min(l), ghi:Max(l)
				table.insert(parts, d)
			end
		end
		local c = (glo + ghi) / 2
		local hw, hd = (ghi.X - glo.X) / 2, (ghi.Z - glo.Z) / 2
		for _, d in ipairs(parts) do
			local l = pivot:PointToObjectSpace(d.Position)
			local side = LM.foldSide(l.X - c.X, l.Z - c.Z, d.Size.X, d.Size.Y, d.Size.Z, hw, hd)
			local hinge
			if side == "px" then hinge = Vector3.new(c.X + hw, glo.Y, l.Z)
			elseif side == "nx" then hinge = Vector3.new(c.X - hw, glo.Y, l.Z)
			elseif side == "pz" then hinge = Vector3.new(l.X, glo.Y, c.Z + hd)
			elseif side == "nz" then hinge = Vector3.new(l.X, glo.Y, c.Z - hd) end
			table.insert(folds, { part = d, cf = d.CFrame, side = side, hinge = hinge })
		end
	end

	-- the scaffold round the new build
	local scaffold
	if lo.X < math.huge then
		scaffold = scaffoldAround(pivot, lo.X, hi.X, lo.Z, hi.Z, lo.Y, (hi.Y - lo.Y) + 2)
	end
	local scaffoldCF = scaffold and scaffold:GetPivot()
	local scaffoldH = (hi.Y - lo.Y) + 2

	local function apply(t)
		for name, list in pairs(groups) do
			local p = LM.at(name, t)
			local off = up * (-LM.RISE * (1 - p))
			local hide = 1 - math.clamp(p, 0, 1)
			for _, it in ipairs(list) do
				it.part.CFrame = it.cf + off
				it.part.LocalTransparencyModifier = hide
			end
		end
		if scaffold then scaffold:PivotTo(scaffoldCF + up * (-scaffoldH * (1 - LM.at("scaffold", t)))) end
		local g = LM.at("garage", t)
		for _, f in ipairs(folds) do
			if f.side == "lift" then
				f.part.CFrame = f.cf + up * (LM.LIFT * g)
				f.part.LocalTransparencyModifier = math.clamp(g, 0, 1)
			else
				local a = math.rad(90) * math.clamp(g, 0, 1)
				local rot = (f.side == "px" and CFrame.Angles(0, 0, -a)) or (f.side == "nx" and CFrame.Angles(0, 0, a))
					or (f.side == "pz" and CFrame.Angles(a, 0, 0)) or CFrame.Angles(-a, 0, 0)
				local h = pivot * CFrame.new(f.hinge)
				f.part.CFrame = h * rot * h:Inverse() * f.cf
			end
		end
	end

	local done = false
	local function finish()
		if done then return end
		done = true
		for _, list in pairs(groups) do
			for _, it in ipairs(list) do
				if it.part.Parent then it.part.CFrame = it.cf; it.part.LocalTransparencyModifier = 0 end
			end
		end
		if scaffold then scaffold:Destroy() end
		if garage then garage:Destroy() end
	end

	-- hide the new lobby before the first frame, then run the clock beside Cine's camera
	apply(0)
	local t0 = os.clock()
	local soundIdx = 1
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		while LM.SOUNDS[soundIdx] and LM.SOUNDS[soundIdx].t <= t do
			local s = LM.SOUNDS[soundIdx]
			UIKit.sfx(s.key, s.pitch, s.volume)
			soundIdx += 1
		end
		if t >= LM.TOTAL or (t > 0.2 and not Cine.busy()) then
			conn:Disconnect()
			finish()
			return
		end
		apply(t)
	end)

	-- the camera
	local cam = workspace.CurrentCamera
	local shots = {}
	for _, s in ipairs(LM.SHOTS) do
		if s.at == "start" then
			table.insert(shots, { pos = cam.CFrame.Position, look = cam.CFrame.Position + cam.CFrame.LookVector * 20, t = 0 })
		elseif s.at == "player" then
			local head = player.Character and player.Character:FindFirstChild("Head")
			local look = head and head.Position or cam.Focus.Position
			table.insert(shots, { pos = cam.CFrame.Position, look = look, t = s.t })
		else
			table.insert(shots, { pos = vec(pivot, s.pos), look = vec(pivot, s.look), t = s.t })
		end
	end
	local ok, finished = pcall(Cine.play, shots, { letterbox = true, skippable = true, fov = 60 })
	if not (ok and finished) then
		-- skipped (or Cine refused): a short fade over the jump to the end state
		Cine.fade(true, LM.SKIP_FADE / 2)
		task.wait(LM.SKIP_FADE / 2)
		if conn.Connected then conn:Disconnect() end
		finish()
		Cine.handBack()
		Cine.fade(false, LM.SKIP_FADE / 2)
	else
		if conn.Connected then conn:Disconnect() end
		finish()
	end
	pcall(Notify.toast, "Your HQ is open! Next: floor 1.", { priority = 2, icon = "info" })
	playing = false
end

remote.OnClientEvent:Connect(function(e)
	local ok, err = pcall(play, e)
	if not ok then
		warn("[SV] lobby moment: " .. tostring(err))
		playing = false
	end
end)
