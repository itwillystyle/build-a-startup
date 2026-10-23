--[[ GameDoctor (11 Oct 2026): plays the game like a new player and measures it.

	Luke, 11 Oct: "me having to find the errors while playing ... I can only attack
	so many things at once. I want to pinpoint these things before." Every bug of the
	last three days (no drop-off, sinking through the park, the camera inside walls,
	the deck through floor 7, the lift dropping you) was found by him, playing. Each
	one is now a measurement here, and every STEP checks itself: it does something a
	player does, then measures the result against a number it expects.

	  world   sinking surfaces, meshes through floors, lift stops over nothing, the
	          chase routes (WorldHealth, TalentDrop.health)
	  hq:N    for N = 5, 9, 13, 18: build the HQ to that level, then check the drop-off
	          is on the ground, stand on every
	          storey, ride the lift to every stop, sweep the camera on the ground and
	          top floors, and look at the screen (overlapping cards)
	  chase   one carry per tier with DevRobot riding the route: the outcome, and
	          on the player's screen camera cuts per second, the lens behind walls,
	          the hunter moving with no run animation, the hunter stuttering
	  errors  every script error printed on the server or the client during the run

	LAYERS. This script (in the game) acts and measures; DoctorClient/DoctorProbes
	measure what only the player's screen can see; the game-doctor routine (a
	scheduled Claude session with the Studio tools) starts Play, takes the save
	snapshot, runs this, stops Play and restores the save; tools/doctor_lib.luau
	(`bas checkup`) judges the report, compares it with the last run and writes
	DOCTOR.md and the Discord summary.

	RUN (Studio, Play, SERVER datamodel, Wilz only):
	    game.ServerScriptService.GameDoctor:SetAttribute("Request", "full/" .. os.clock())
	    -- poll game.ServerScriptService.GameDoctor:GetAttribute("Status") until "done"
	    -- read game.ServerStorage.DoctorReport.Value (JSON)
	It changes the test save (HQ level, staff): take the snapshot first (it refuses
	without one) and restore after Play stops (DevScenarios.restore). ]]
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

local WH = require(SSS:WaitForChild("WorldHealth"))
local HQF = require(SSS:WaitForChild("HQFloors"))
local WalkLanes = require(ReplicatedStorage:WaitForChild("WalkLanes"))   -- 20 Oct: the pedestrians' lanes

local LEVELS = { 5, 9, 13, 18, 43, 100 }   -- v9 (14 Oct): the tower is checked at its top too (spec §8.2)
local TIERS = { "skilled", "star", "genius" }
local STAND_TOL = 0.35        -- studs: resting this far off a floor's top is standing in it (or floating)
local CAMERA_BEHIND = 0       -- camera samples behind a wall: anything over this is a bug
local CUTS_PER_SEC = 0.5      -- chase camera cuts a second before it reads as jumpy (provisional, 11 Oct)
local NO_RUN = 0.15           -- share of moving hunter frames with no run animation
local STUTTER = 0.05          -- share of hunter frames with a visible hitch

local remote = Instance.new("RemoteEvent")
remote.Name = "DoctorResult"
remote.Parent = ReplicatedStorage

local pending = {}
remote.OnServerEvent:Connect(function(player, nonce, data)
	if player.UserId ~= 1688749216 and player.UserId >= 0 then return end   -- Wilz or a local test player
	if type(nonce) == "string" and pending[nonce] == false then pending[nonce] = data end
end)

local serverErrors = {}
local collecting = false
LogService.MessageOut:Connect(function(msg, kind)
	if not collecting or kind ~= Enum.MessageType.MessageError then return end
	if msg:find("Assistant", 1, true) then return end   -- the Studio bridge's own errors, not the game's
	if #serverErrors < 50 then table.insert(serverErrors, msg:sub(1, 220)) end
end)

-- ---------------------------------------------------------------- the report
local report, current

local function check(name, ok, severity, measured, expected, detail)
	table.insert(current.checks, { name = name, ok = ok == true, severity = ok and nil or severity,
		measured = measured, expected = expected, detail = detail })
end

local function info(name, measured, detail)
	table.insert(current.checks, { name = name, ok = true, info = true, measured = measured, detail = detail })
end

local function step(name, fn)
	current = { name = name, checks = {} }
	script:SetAttribute("Status", "step " .. name)
	local t0 = os.clock()
	local ok, err = pcall(fn)
	if not ok then check("ran", false, "BLOCKER", nil, nil, "the step stopped with an error: " .. tostring(err)) end
	current.seconds = math.floor((os.clock() - t0) * 10) / 10
	table.insert(report.steps, current)
end

-- ask the client to measure something; nil after `timeout` seconds
local clientErrors = {}
local function probe(player, name, args, timeout)
	local nonce = HttpService:GenerateGUID(false)
	pending[nonce] = false
	player:SetAttribute("DoctorProbe", HttpService:JSONEncode({ name = name, nonce = nonce, args = args or {} }))
	local t0 = os.clock()
	while pending[nonce] == false and os.clock() - t0 < (timeout or 30) do task.wait(0.1) end
	local res = pending[nonce]
	pending[nonce] = nil
	player:SetAttribute("DoctorProbe", nil)
	if type(res) == "table" then
		for _, e in ipairs(res.clientErrors or {}) do table.insert(clientErrors, e) end
		res.clientErrors = nil
		return res
	end
	return nil
end

-- ---------------------------------------------------------------- helpers
local function dev() return SSS:FindFirstChild("SiliconCore") and SSS.SiliconCore:FindFirstChild("SVDev") end

local function standHeight(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	return hum.HipHeight + root.Size.Y / 2
end

local function groundUnder(char, pos)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	params.RespectCanCollide = true
	return workspace:Raycast(pos, Vector3.new(0, -40, 0), params)
end

-- put the character at `cf` like the game does (a server PivotTo), let it settle,
-- -> how far it rests above the solid thing under it, and what that is
local function settleAt(char, cf)
	char:PivotTo(cf)
	task.wait(1.2)
	local root = char:FindFirstChild("HumanoidRootPart")
	local hit = groundUnder(char, root.Position)
	return hit and (root.Position.Y - hit.Position.Y) or nil, hit and hit.Instance.Name or "nothing", root.Position.Y
end

-- one collider per storey of this plot's HQ: { { top, part } } low to high
local function storeys(plotFolder)
	local hq = plotFolder and plotFolder:FindFirstChild("Wafers")
	local byTop = {}
	for _, d in ipairs(hq and hq:GetDescendants() or {}) do
		if d:IsA("BasePart") and (d.Name == "Floor" or d.Name == "Deck") and d.CanCollide then
			local top = math.floor((d.Position.Y + d.Size.Y / 2) * 10 + 0.5) / 10
			byTop[top] = byTop[top] or {}
			table.insert(byTop[top], d)
		end
	end
	local out = {}
	for top, parts in pairs(byTop) do table.insert(out, { top = top, parts = parts }) end
	table.sort(out, function(a, b) return a.top < b.top end)
	return out
end

local function short(list, n)
	local out = {}
	for i, v in ipairs(list) do
		if i > (n or 3) then break end
		table.insert(out, type(v) == "table" and HttpService:JSONEncode(v) or tostring(v))
	end
	return table.concat(out, "; ")
end

-- v8 (14 Oct) composition (SlopRules): what the TEAM screen got wrong while passing every size check
local function slopChecks(ui)
	check("loud buttons in one menu", #(ui.loud or {}) == 0, "FEEL", #(ui.loud or {}), 0, short(ui.loud or {}))
	check("the same fact twice", #(ui.twice or {}) == 0, "FEEL", #(ui.twice or {}), 0, short(ui.twice or {}))
	check("cut off", #(ui.cutOff or {}) == 0, "BUG", #(ui.cutOff or {}), 0, short(ui.cutOff or {}, 4))
end

--[[ 20 Oct (Luke's live screenshot: a walker inside his HQ's glass). Every pedestrian and
	cyclist lane (WalkLanes, the same table LifeClient walks) swept through the real world: a box
	as wide as a walker's swinging arms, from the knees to the shoulders, both keep-right sides.
	Ground does not count (the box starts above kerbs and pavements; the park ramps are ridden),
	and nothing that moves does (players, cars, candidates, clients).
	-> list of "Part.Name at (x, z)" for every distinct thing a lane walks through ]]
local function walkerSweep()
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	local skip = {}
	for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(skip, p.Character) end end
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Model") and (d.Name:match("^Car_") or d:FindFirstChildOfClass("Humanoid")) then table.insert(skip, d) end
	end
	op.FilterDescendantsInstances = skip
	local hits, seen = {}, {}
	for _, l in ipairs(WalkLanes.build()) do
		for s = 0, l.len, 1.5 do
			for _, way in ipairs({ -1, 1 }) do
				local p = l.a + l.dir * s + l.side * (way * l.keep)
				local box = CFrame.lookAt(p + Vector3.new(0, 2.1, 0), p + Vector3.new(0, 2.1, 0) + l.dir)
				for _, q in ipairs(workspace:GetPartBoundsInBox(box, Vector3.new(3.8, 2.8, 1), op)) do
					if q.Transparency < 1 and q.Name ~= "ParkRamp" then
						local k = q:GetFullName():gsub("^Workspace%.SiliconValley%.", "")
						if not seen[k] then
							seen[k] = true
							table.insert(hits, ("%s (lane %s) at (%d, %d)"):format(k, l.name, p.X, p.Z))
						end
					end
				end
			end
		end
	end
	return hits
end

-- ---------------------------------------------------------------- the journey
local function run()
	report = { version = 1, startedAt = os.time(), placeId = game.PlaceId, steps = {}, notChecked = {
		"cars (driving, parking, getting out at speed)", "phones and small screens", "two players (poaching, shared streets)",
		"how anything LOOKS (no screenshots yet): the doctor measures, it does not see",
	} }
	collecting, serverErrors, clientErrors = true, {}, {}
	local player = Players:GetPlayers()[1]
	local sv = dev()
	if not (player and player.Character and sv) then
		report.aborted = "no player, character or SVDev"
		return
	end
	local char = player.Character
	local plotFolder

	step("setup", function()
		local snap = sv:Invoke("scenario", player, "snapshot")
		check("save snapshot", snap and snap.ok, "BLOCKER", snap and snap.ok and "taken" or tostring(snap and snap.err), "taken",
			"the doctor changes the test save; it will not run without a snapshot to restore")
		if not (snap and snap.ok) then error("no snapshot") end
		local st = sv:Invoke("state", player)
		plotFolder = workspace.SiliconValley.Plots:FindFirstChild("Plot" .. tostring(st.plot))
		info("start", ("HQ level %s, %s staff, plot %s"):format(tostring(st.hqLevel), tostring(st.staff), tostring(st.plot)))
		report.start = { hqLevel = st.hqLevel, staff = st.staff, plot = st.plot }
	end)
	if report.steps[1].checks[1] and not report.steps[1].checks[1].ok then report.aborted = "no snapshot" return end

	step("world", function()
		local h = sv:Invoke("scenario", player, "health")
		local world, floors, lifts, chase = h.world, h.floors, h.lifts, h.chase
		check("sinking surfaces", world and world.found == 0, "BUG", world and world.found, 0, world and short(world.sinks))
		check("meshes through a floor", floors and floors.found == 0, "BUG", floors and floors.found, 0, floors and short(floors.through))
		check("lift stops over nothing", lifts and lifts.found == 0, "BUG", lifts and lifts.found, 0, lifts and short(lifts.bad))
		local noRoute = {}
		for _, pl in ipairs(chase and chase.plots or {}) do
			if pl.door ~= nil and not tostring(pl.door):match("^ok") then table.insert(noRoute, pl.index) end
		end
		check("drop-off reaches the street", #noRoute == 0, "BLOCKER", #noRoute, 0, #noRoute > 0 and ("plots " .. table.concat(noRoute, ", ")) or nil)
		-- 20 Oct: the pedestrians walk clear of everything the world has built (see walkerSweep)
		local walk = walkerSweep()
		check("walkers through walls and props", #walk == 0, "BUG", #walk, 0, short(walk, 5))
		--[[ 20 Oct: the VIP stood at the OLD downtown address, ~1,000 studs from the Residences
			v9 moved onto the ring. Every plot's spot must be at the building, on the ground, clear. ]]
		local Apt = require(SSS:WaitForChild("Apartments"))
		local desk = Apt.deskPosition and Apt.deskPosition()
		local far, blocked = {}, {}
		for i = 1, 6 do
			local spot = Apt.vipSpot(i)
			local dist = (spot and desk) and (Vector3.new(spot.X, 0, spot.Z) - Vector3.new(desk.X, 0, desk.Z)).Magnitude or math.huge
			if dist > 45 then table.insert(far, ("plot %d: %s studs"):format(i, dist == math.huge and "no spot" or math.floor(dist))) end
			if spot then
				for _, q in ipairs(workspace:GetPartBoundsInBox(CFrame.new(spot + Vector3.new(0, 3.5, 0)), Vector3.new(3, 5, 3))) do
					if q.CanCollide and q.Transparency < 1 then table.insert(blocked, ("plot %d: %s"):format(i, q.Name)) end
				end
			end
		end
		check("VIP waits at the Residences", #far == 0, "BUG", #far, 0, #far > 0 and short(far, 6) or nil)
		check("VIP spot is clear", #blocked == 0, "BUG", #blocked, 0, #blocked > 0 and short(blocked, 6) or nil)
		--[[ 22 Oct (art pass 1): parts tagged SVKeepMaterial keep real wood, fabric or metal. Only those
			four, and never on lawn-coloured ground (FlatLook keeps lawns flat on purpose). ]]
		local FL = require(SSS:WaitForChild("FlatLook"))
		local CS = game:GetService("CollectionService")
		local wrongMat, kept = {}, 0
		for _, p in ipairs(CS:GetTagged("SVKeepMaterial")) do
			if p:IsA("BasePart") then
				kept += 1
				local hue, sat = p.Color:ToHSV()
				local lawn = p.Size.X * p.Size.Z >= 60 and p.Size.Y <= 5 and sat > 0.18 and hue > 0.20 and hue < 0.45
				if not FL.KEEP_TAGGED[p.Material] or lawn then
					table.insert(wrongMat, ("%s (%s%s)"):format(p.Name, p.Material.Name, lawn and ", lawn" or ""))
				end
			end
		end
		check("kept materials", #wrongMat == 0, "BUG", #wrongMat, 0, #wrongMat > 0 and short(wrongMat, 5) or ("%d tagged parts"):format(kept))
		--[[ Two scripts with one name. 11 Oct: two Rojo plugins (the local one and the
			Creator Store copy, auto-reconnect on) were both syncing, so every file made
			since 10 Oct existed twice -- and was published twice. Here it split the
			doctor's own reply channel and every probe went unanswered. ]]
		local dupes = {}
		for _, svc in ipairs({ SSS, ReplicatedStorage, game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"),
			game:GetService("StarterGui"), ServerStorage }) do
			local seen = {}
			for _, c in ipairs(svc and svc:GetChildren() or {}) do
				if c:IsA("LuaSourceContainer") or c:IsA("Folder") then
					local k = c.Name .. "|" .. c.ClassName
					if seen[k] then table.insert(dupes, svc.Name .. "." .. c.Name) else seen[k] = true end
				end
			end
		end
		check("scripts that exist twice", #dupes == 0, "BUG", #dupes, 0, #dupes > 0 and (table.concat(dupes, ", ") ..
			": two Rojo plugins syncing at once? keep one (Plugins > Manage Plugins)") or nil)
	end)

	--[[ The first client (16 Oct, the client loop): a brand-new save meets one client
		at the door asking for a to-do app, and serving it pays the wow (spec:
		2026-10-16-client-loop-design.md). Builds without the client loop have no
		"fresh" scenario: the step says so and passes, so this judge can land first. ]]
	step("first client", function()
		local r = sv:Invoke("scenario", player, "fresh")
		if not (r and r.ok) and tostring(r and r.err):find("unknown scenario", 1, true) then
			info("first client", "skipped", "no client loop on this build")
			return
		end
		check("fresh save", r and r.ok, "BLOCKER", r and (r.ok and "ok" or r.err), "ok")
		-- 18 Oct: a brand-new save in the garage (product work nil) threw inside the once-a-second
		-- economy loop and stopped it for the whole server: no staff income, no product bar
		local core = game:GetService("ServerScriptService"):WaitForChild("SiliconCore")
		local tick0 = core:GetAttribute("EconTick") or 0
		task.wait(3.5)
		local tick1 = core:GetAttribute("EconTick") or 0
		check("economy loop alive", tick1 >= tick0 + 2, "BLOCKER", tick1 - tick0 .. " ticks in 3.5 s", ">= 2")
		local Clients = require(game:GetService("ServerScriptService"):WaitForChild("Clients"))
		local t0 = os.clock()
		local rig
		repeat
			for _, d in ipairs(workspace:GetDescendants()) do
				if d:GetAttribute("ClientOf") == player.UserId then rig = d break end
			end
			if not rig then task.wait(0.5) end
		until rig or os.clock() - t0 > 20
		check("client arrives", rig ~= nil, "BUG", rig and "at the door" or "none in 20 s", "at the door")
		--[[ 22 Oct (Luke's look review: "the client is floating"; measured 1.01 studs over the path):
			once they have walked to their spot, their lowest part rests on the ground (+-0.3). ]]
		if rig then
			task.wait(4)
			local lowest = math.huge
			for _, d in ipairs(rig:GetDescendants()) do
				if d:IsA("BasePart") and d.Transparency < 1 and d.Name ~= "HumanoidRootPart" then
					lowest = math.min(lowest, d.Position.Y - d.Size.Y / 2)
				end
			end
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.RespectCanCollide = true
			params.FilterDescendantsInstances = { rig, char }
			local at = rig:GetPivot().Position
			local hit = workspace:Raycast(at + Vector3.new(0, 1, 0), Vector3.new(0, -14, 0), params)
			local gap = hit and (lowest - hit.Position.Y) or nil
			check("client stands on the ground", gap ~= nil and math.abs(gap) <= 0.3, "BUG",
				gap and ("%.2f studs"):format(gap) or "no ground under them", "within 0.30",
				hit and ("on " .. hit.Instance.Name) or nil)
		end
		local cash = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Cash")
		local before = cash and cash.Value or 0
		local s = sv:Invoke("clients", player, "serve")
		local gained = (cash and cash.Value or 0) - before
		local want = Clients.TUNE.FLOOR * Clients.TUNE.WOW
		check("first client pays the wow", gained >= want, "BUG", gained, ">= " .. want, s and s.err)
		-- 17 Oct: the Shipped attribute is copied from the session by refreshObjective every
		-- 0.4 s; reading it right after the serve raced that (measured: 0.40 s late, 1 run in 3)
		local t0 = os.clock()
		while player:GetAttribute("Shipped") ~= true and os.clock() - t0 < 1 do task.wait(0.05) end
		check("first app shipped", player:GetAttribute("Shipped") == true, "BUG", player:GetAttribute("Shipped"), true)
	end)

	for _, level in ipairs(LEVELS) do
		step("hq:" .. level, function()
			local r = sv:Invoke("scenario", player, "hq:" .. level)
			-- the level it really reached (14 Oct: a save at 55 with a blueprint cap of 55 "checked"
			-- levels 5, 9, 13, 18, 43 and 100 as 55, six times, and every one passed)
			check("built", r and r.ok and r.level == level, "BLOCKER",
				r and r.ok and ("level " .. tostring(r.level)) or tostring(r and r.err), "level " .. level)
			task.wait(4)
			-- the drop-off is on the forecourt's ground, not on whatever the HQ hangs over it
			-- (11 Oct: from level 18 it sat 18.4 studs up, on the entrance arch)
			local geo = sv:Invoke("scenario", player, "geo")
			local door = geo and geo.door
			check("drop-off on the ground", door ~= nil and door.Y < 3, "BUG", door and math.floor(door.Y * 10) / 10 or "none",
				"under 3 (the forecourt)", "the drop-off ring, beam and sign are drawn there, and routes home start there")
			-- 20 Oct: the wings grow sideways with the levels; walkers must clear them at every one
			local walk = walkerSweep()
			check("walkers through walls and props", #walk == 0, "BUG", #walk, 0, short(walk, 5))
			-- the level-up cards are on screen now: anything printed over anything else?
			local ui = probe(player, "ui", {}, 15)
			if ui then
				check("cards over cards", #ui.overlaps == 0, "FEEL", #ui.overlaps, 0, short(ui.overlaps))
				check("buttons something covers", #ui.blocked == 0, "BUG", #ui.blocked, 0, short(ui.blocked))
				check("text under 14 px on screen", #(ui.smallText or {}) == 0, "FEEL", #(ui.smallText or {}), 0,
					("at %s (floor %s px; 12 on a phone-height screen): %s"):format(tostring(ui.viewport), tostring(ui.textFloor or 14),
						short(ui.smallText or {}, 4)))
				check("taps under 44 px on screen", #(ui.smallTaps or {}) == 0, "BUG", #(ui.smallTaps or {}), 0,
					("at %s: %s"):format(tostring(ui.viewport), short(ui.smallTaps or {}, 4)))
				slopChecks(ui)
			else
				check("ui probe answered", false, "BUG", "no answer", "answer")
			end
			local floors = WH.throughFloors(workspace.SiliconValley.Plots)
			check("meshes through a floor", floors.found == 0, "BUG", floors.found, 0, short(floors.through))
			-- stand on every storey
			local want = standHeight(char)
			local bad = {}
			local list = storeys(plotFolder)
			for _, s in ipairs(list) do
				local part = s.parts[math.max(1, math.floor(#s.parts / 2))]
				local h, on = settleAt(char, CFrame.new(part.Position + Vector3.new(0, part.Size.Y / 2 + 4, 0)))
				if not h or math.abs(h - want) > STAND_TOL then
					table.insert(bad, { floor = s.top, rest = h and math.floor(h * 100) / 100, on = on })
				end
			end
			check("stand on every storey", #bad == 0, "BUG", #bad, 0, ("%d storeys; want %.2f above the floor; %s"):format(#list, want, short(bad)))
			-- ride the lift to every stop
			local reg = HQF.lifts[tonumber(plotFolder.Name:match("%d+"))]
			local drops = {}
			for _, st in ipairs(reg and reg.stops or {}) do
				local h, on, y = settleAt(char, st.stand + Vector3.new(0, 3, 0))
				local fell = y < st.stand.Position.Y + want - 1.5
				if fell or not h or math.abs(h - want) > STAND_TOL then
					table.insert(drops, { stop = st.id, rest = h and math.floor(h * 100) / 100, on = on, fell = fell })
				end
			end
			check("lift lands you on a floor", #drops == 0, "BUG", #drops, 0, ("%d stops; %s"):format(reg and #reg.stops or 0, short(drops)))
			-- the camera, on the ground floor and the top floor
			local behind, samples, closest = 0, 0, math.huge
			for _, idx in ipairs({ 1, #list }) do
				local s = list[idx]
				if s then
					for k = 1, math.min(3, #s.parts) do
						local part = s.parts[k]
						settleAt(char, CFrame.new(part.Position + Vector3.new(0, part.Size.Y / 2 + 4, 0)))
						local c = probe(player, "camera", { zoom = 12 }, 20)
						if c and c.samples then
							behind += c.behind
							samples += c.samples
							closest = math.min(closest, c.closest)
						end
					end
				end
			end
			check("camera behind a wall", samples > 0 and behind <= CAMERA_BEHIND, "BUG", ("%d/%d"):format(behind, samples), "0",
				samples > 0 and ("closest the lens came to your head: %.1f studs"):format(closest) or "the camera probe never answered")
		end)
	end

	-- v9 (15 Oct, HQ part 1b): ride the lift at the top level (the loop above ends at hq:100)
	step("lift:ride", function()
		local LiftCab = require(SSS:WaitForChild("LiftCab"))
		local LP = require(ReplicatedStorage:WaitForChild("LiftPlan")).with(require(ReplicatedStorage:WaitForChild("TowerPlan")))
		local idx = tonumber(plotFolder.Name:match("%d+"))
		local c = LiftCab.cabs[idx]
		check("lift exists", c ~= nil, "BLOCKER", c and "yes" or "no", "yes")
		if not c then return end
		local want = standHeight(char)
		local route = { "F7", "R", "L" }
		local slips, falls, lands, times = {}, {}, {}, {}
		local at = c.model:GetAttribute("At")
		for _, id in ipairs(route) do
			-- stand in the cab where it is, then pick
			settleAt(char, c.model.PrimaryPart.CFrame * CFrame.new(0, 3.5, 0))
			local fromIdx, toIdx
			for i, s in ipairs(c.stops) do if s.id == at then fromIdx = i end; if s.id == id then toIdx = i end end
			local dur = LP.rideTime(math.abs((toIdx or 1) - (fromIdx or 1)))
			local res
			task.spawn(function() res = probe(player, "liftride", { plot = idx, seconds = dur + 2.5 }, dur + 10) end)
			task.wait(0.3)
			LiftCab.pick(player, idx, id)
			local t0 = os.clock()
			while res == nil and os.clock() - t0 < dur + 12 do task.wait(0.2) end
			res = res or {}
			table.insert(slips, res.maxSlip or -1)
			if res.fell then table.insert(falls, id) end
			if math.abs((res.rideSeconds or -1) - dur) > 0.25 then table.insert(times, ("%s %.2f/%.2f"):format(id, res.rideSeconds or -1, dur)) end
			task.wait(LP.DOORS + 0.3)
			-- arrived: resting on the cab's floor, which is the stop's floor when the cab is at rest
			local root = char:FindFirstChild("HumanoidRootPart")
			local ok = root and math.abs((root.Position.Y - (c.model.PrimaryPart.Position.Y + 0.25)) - want) <= STAND_TOL + 0.15
			if not ok then table.insert(lands, id) end
			at = id
		end
		local worst = 0
		for _, s in ipairs(slips) do worst = math.max(worst, s) end
		check("lift ride holds the rider", worst >= 0 and worst <= 0.3 and #falls == 0, "BUG", ("max %.2f, falls %d"):format(worst, #falls), "<= 0.30, 0 falls")
		check("lift arrives on the floor", #lands == 0, "BUG", #lands, 0, short(lands))
		check("lift ride time", #times == 0, "FEEL", #times, 0, short(times))
		-- doors solid wherever the cab is not
		local open = {}
		for _, d in ipairs(plotFolder.Wafers:GetChildren()) do
			if d.Name:match("^LiftDoor") and d:GetAttribute("Stop") ~= c.model:GetAttribute("At") and not d.CanCollide then table.insert(open, d:GetAttribute("Stop")) end
		end
		check("lift doors solid when away", #open == 0, "BUG", #open, 0, short(open))
	end)

	for _, tier in ipairs(TIERS) do
		step("chase:" .. tier, function()
			local rec = SSS:FindFirstChild("DevRecorder")
			if not rec then error("DevRecorder is missing") end
			local box = ServerStorage:FindFirstChild("ChaseRun")
			if box then box.Value = "" end
			local cam
			task.spawn(function() cam = probe(player, "chasecam", { wait = 45 }, 170) end)
			rec:SetAttribute("Request", ("%s/straight/%s"):format(tier, tostring(os.clock())))
			local t0 = os.clock()
			repeat
				task.wait(0.5)
				box = ServerStorage:FindFirstChild("ChaseRun")
			until (box and box.Value ~= "") or os.clock() - t0 > 160
			local t1 = os.clock()
			while cam == nil and os.clock() - t1 < 10 do task.wait(0.2) end
			local ok, ride = pcall(HttpService.JSONDecode, HttpService, box and box.Value or "")
			ride = ok and ride or nil
			check("the chase ran", ride and ride.result ~= "error", "BLOCKER", ride and ride.result or "no result", "home/caught/timeout",
				ride and ride.err or nil)
			if ride and ride.result ~= "error" then
				info("outcome (robot rides straight)", ride.result, ("%.1f s, %s lunges, closest %s studs, route %s studs"):format(
					ride.time or 0, tostring(ride.lunges), tostring(ride.closest), tostring(ride.pathLen)))
			end
			if cam and not cam.error then
				check("camera cuts", cam.cutsPerSec <= CUTS_PER_SEC, "FEEL", cam.cutsPerSec, "<= " .. CUTS_PER_SEC,
					("%d cuts in %.1f s"):format(cam.cuts, cam.seconds))
				check("lens behind a wall", cam.behindWall == 0, "BUG", cam.behindWall, 0, ("of %d frames"):format(cam.frames))
				local moving = math.max(cam.hunterMovingFrames, 1)
				check("hunter runs with its run animation", cam.hunterNoRunFrames / moving <= NO_RUN, "MISSING",
					("%d%%"):format(math.floor(100 * cam.hunterNoRunFrames / moving)), "<= " .. math.floor(NO_RUN * 100) .. "%",
					("%d of %d moving frames had no run animation playing"):format(cam.hunterNoRunFrames, cam.hunterMovingFrames))
				check("hunter moves smoothly", cam.hunterStutters / math.max(cam.frames, 1) <= STUTTER, "FEEL",
					("%d%%"):format(math.floor(100 * cam.hunterStutters / math.max(cam.frames, 1))), "<= " .. math.floor(STUTTER * 100) .. "%",
					("%d hitches in %d frames (a step change over 1.5 studs)"):format(cam.hunterStutters, cam.frames))
				info("frame rate in Studio", cam.fps, "Studio runs at 2-3 FPS while it is the focused window: not the players' FPS")
			else
				check("chase camera probe answered", false, "BUG", cam and cam.error or "no answer", "answer")
			end
		end)
	end

	-- v8 Manage Staff phase 2 (14 Oct): train and move through the REAL action code
	-- (DevHook staffact -> Econ.staffAction). The setup snapshot restores the save after.
	step("team", function()
		local st = sv:Invoke("state", player) or {}   -- a direct DevHook action, not a scenario (caught live 14 Oct)
		check("someone to train", (st.staff or 0) >= 1, "BLOCKER", st.staff or 0, ">= 1")
		if (st.staff or 0) < 1 then return end
		sv:Invoke("cash", player, 1e12)
		sv:Invoke("staffstat", player, "1:skill:0")
		-- strengthened 14 Oct (final review): a lost price rate makes every level cost MIN_PRICE,
		-- which ">= 10" passed; and the income rise the spec's gate names (x mult(skill, 1), +-1%)
		local SS = require(game:GetService("ReplicatedStorage"):WaitForChild("StaffStats"))
		local function rateOf(id)
			local ok, rows = pcall(function() return HttpService:JSONDecode(player:GetAttribute("StaffData") or "[]") end)
			for _, row in ipairs(ok and rows or {}) do if row.id == id then return row.rate end end
			return nil
		end
		local firstId = (sv:Invoke("staffact", player, "move:1:") or {}).id   -- a no-op read of person 1's id
		local before = rateOf(firstId)
		local t = sv:Invoke("staffact", player, "train:1:skill")
		local after = rateOf(firstId)
		local want = SS.mult("skill", 1)
		local ratio = (before and after and before > 0) and after / before or nil
		check("train charges and raises", type(t) == "table" and t.ok == true and t.skill == 1 and t.cashSpent == t.price and (t.price or 0) > SS.MIN_PRICE, "BUG",
			type(t) == "table" and ("ok=%s skill=%s spent=%s price=%s"):format(tostring(t.ok), tostring(t.skill), tostring(t.cashSpent), tostring(t.price)) or tostring(t),
			"ok, level 1, spent = price > " .. SS.MIN_PRICE .. " (the person's own rate, not the floor)")
		check("income rises by the Skill step", ratio ~= nil and math.abs(ratio - want) <= want * 0.01, "BUG",
			ratio and ("x%.4f ($%s -> $%s/s)"):format(ratio, tostring(before), tostring(after)) or "no rate", ("x%.4f +-1%%"):format(want))
		sv:Invoke("staffstat", player, "1:skill:30")
		local m = sv:Invoke("staffact", player, "train:1:skill")
		check("refused past the cap", type(m) == "table" and m.ok == false and m.why == "at max" and m.cashSpent == 0, "BUG",
			type(m) == "table" and ("why=%s spent=%s"):format(tostring(m.why), tostring(m.cashSpent)) or tostring(m), "at max, nothing spent")
		sv:Invoke("staffstat", player, "1:skill:0")
		local u = sv:Invoke("staffact", player, "move:1:hq")
		local back = sv:Invoke("staffact", player, "move:1:")
		-- the garage bench is always a seat (deskHomes), so "no free seat" is not an acceptable answer (final review)
		local moved = type(u) == "table" and u.ok == true and u.pin == "hq" and u.room == "hq"
		check("move pins and seats", moved and type(back) == "table" and back.pin == "", "BUG",
			type(u) == "table" and ("ok=%s why=%s pin=%s room=%s, then pin=%s"):format(tostring(u.ok), tostring(u.why), tostring(u.pin), tostring(u.room), type(back) == "table" and tostring(back.pin) or "?") or tostring(u),
			"pinned to hq and sitting there, then unpinned")
		local junk = sv:Invoke("staffact", player, "train:1:money")
		check("junk refused", type(junk) == "table" and junk.ok == false and junk.cashSpent == 0, "BUG",
			type(junk) == "table" and tostring(junk.why) or tostring(junk), "refused, nothing spent")
		local data = player:GetAttribute("StaffData")
		local okJson, rows = pcall(function() return game:GetService("HttpService"):JSONDecode(data) end)
		check("StaffData published", okJson and type(rows) == "table" and #rows == (st.staff or 0) and rows[1].stats ~= nil, "BUG",
			okJson and type(rows) == "table" and (#rows .. " rows") or "missing", (st.staff or 0) .. " rows with stats")

		-- phase 3: the TEAM screen, opened the way a tap opens it, measured on the player's screen
		local ui = probe(player, "team", {}, 15)
		check("TEAM screen answered", type(ui) == "table" and ui.error == nil, "BUG", type(ui) == "table" and (ui.error or "ok") or "no answer", "ok")
		if type(ui) ~= "table" or ui.error then return end
		-- StaffData as the screen saw it: the probe waits up to 8 s for notices to clear, and a
		-- promotion in that time changes prices (review: comparing the old copy was a false BUG)
		okJson, rows = pcall(function() return game:GetService("HttpService"):JSONDecode(player:GetAttribute("StaffData")) end)
		check("TEAM lists everyone", okJson and ui.rows == #rows, "BUG", ui.rows, okJson and #rows or "?")
		-- the card shows the person on top of the list (most $/s) and the SERVER's price for their
		-- Skill, in whichever of the three states your cash puts it (MAX / dim price / TRAIN price)
		local RS = game:GetService("ReplicatedStorage")
		local View = require(RS:WaitForChild("TeamView"))
		local top = okJson and View.sort(rows, "rate")[1]
		local sk = top and top.stats and top.stats.skill
		local UIKit = require(RS:WaitForChild("UIKit"))
		local ls = player:FindFirstChild("leaderstats")
		local tr = View.train(sk, ls and ls:FindFirstChild("Cash") and ls.Cash.Value)
		local wantBtn = not sk and "?" or (tr.state == "max" and "MAX") or UIKit.money(tr.price)   -- v2: the price alone, in every state but MAX
		check("card shows the server's price", ui.cardOpen and ui.name == (top and top.name) and ui.skillButton == wantBtn, "BUG",
			("%s: %s"):format(tostring(ui.name), tostring(ui.skillButton)), ("%s: %s"):format(tostring(top and top.name), wantBtn))
		check("cards over cards", #ui.overlaps == 0, "FEEL", #ui.overlaps, 0, short(ui.overlaps))
		check("buttons something covers", #ui.blocked == 0, "BUG", #ui.blocked, 0, short(ui.blocked))
		check("text under 14 px on screen", #(ui.smallText or {}) == 0, "FEEL", #(ui.smallText or {}), 0,
			("at %s (floor %s px): %s"):format(tostring(ui.viewport), tostring(ui.textFloor or 14), short(ui.smallText or {}, 4)))
		check("taps under 44 px on screen", #(ui.smallTaps or {}) == 0, "BUG", #(ui.smallTaps or {}), 0,
			("at %s: %s"):format(tostring(ui.viewport), short(ui.smallTaps or {}, 4)))
		slopChecks(ui)
		check("live character views", (ui.viewports or 0) <= 9, "FEEL", ui.viewports or 0, "<= 9")
	end)

	--[[ 19 Oct (Luke's playtest: "head pokes through the hatchback roof"): every dealer car, built
		the real way, with the player in the seat. A closed car's roof must clear the head; the
		open race cars show it by design. ]]
	step("cars", function()
		local rows = sv:Invoke("carfit", player)
		if type(rows) ~= "table" or rows.err then
			check("cars built", false, "BUG", rows and rows.err or "no answer", "every dealer car")
			return
		end
		for _, r in ipairs(rows) do
			if r.err then
				check(r.id .. ": built", false, "BUG", r.err, "a model")
			elseif r.open then
				info(r.id .. ": open top", r.seated and "seated" or "NOT seated", ("head %.2f, body top %.2f"):format(r.headTop or 0, r.roof or 0))
			else
				check(r.id .. ": roof clears the head", r.seated and r.clear ~= nil and r.clear >= 0.1, "BUG",
					r.clear and ("%.2f studs"):format(r.clear) or "no roof found", ">= 0.10",
					("seated %s, head top %.2f, roof %.2f above the ground"):format(tostring(r.seated), r.headTop or 0, r.roof or 0))
			end
		end
	end)

	-- 23 Oct: the motion layer, Reduce Motion forced on for the probe (DoctorProbes.motion)
	step("motion", function()
		local res = probe(player, "motion", {}, 20)
		if not res or res.error then
			check("motion probe answered", false, "BUG", res and res.error or "no answer", "answer")
			return
		end
		for _, c in ipairs(res.checks or {}) do
			check(c.name, c.ok, "BUG", c.measured, c.expected)
		end
	end)

	step("errors", function()
		task.wait(1)
		local seen, uniq = {}, {}
		for _, e in ipairs(serverErrors) do
			local k = e:gsub("%d+", "#")
			if not seen[k] then seen[k] = true table.insert(uniq, "server: " .. e) end
		end
		for _, e in ipairs(clientErrors) do
			local k = e:gsub("%d+", "#")
			if not seen[k] then seen[k] = true table.insert(uniq, "client: " .. e) end
		end
		check("script errors during the run", #uniq == 0, "BUG", #uniq, 0, short(uniq, 5))
		report.errors = uniq
	end)
	collecting = false
end

script:GetAttributeChangedSignal("Request"):Connect(function()
	if script:GetAttribute("Status") and tostring(script:GetAttribute("Status")):match("^step") then return end   -- one at a time
	local box = ServerStorage:FindFirstChild("DoctorReport") or Instance.new("StringValue")
	box.Name = "DoctorReport"
	box.Value = ""
	box.Parent = ServerStorage
	task.spawn(function()
		local ok, err = pcall(run)
		if not ok then report = report or { steps = {} } report.crashed = tostring(err) end
		report.finishedAt = os.time()
		box.Value = HttpService:JSONEncode(report)
		script:SetAttribute("Status", "done")
	end)
end)
script:SetAttribute("Status", "idle")
