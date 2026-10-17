--[[ ClientsServer (16 Oct 2026): the people at your door, the hold, the hand-over, the pay.

	Spec: silicon-startup/docs/superpowers/specs/2026-10-16-client-loop-design.md.
	Mocks Luke picked: 1A (speech bubble + patience bar), 2C (the button is the
	progress bar), 3A (pops + coins) and 3B (the first client's stamp).

	The rules are Clients.lua (pure, offline-tested). This module is the world:
	it walks client rigs up to the garage door, draws their bubble, reads whether
	you hold WRITE CODE at your laptop, hands the app over when you walk up to the
	client, and adds the cash (with its Telemetry line). SiliconCore wires it from
	one do-block and keeps the returned table at Econ.Clients.

	Per player: byUser[userId] = { Q, plot, rigs = {[clientId] = model}, hold, tapUntil,
	lastToggle, lastWho, frontPos, coded }. ]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Clients = require(ServerScriptService:WaitForChild("Clients"))
local StaffRig = require(ServerScriptService:WaitForChild("StaffRig"))
local Telemetry = require(ServerScriptService:WaitForChild("Telemetry"))
local WaferPlan = require(ServerScriptService:WaitForChild("WaferPlan"))

local LAPTOP_RANGE = 12    -- studs: holding counts within this of your laptop
local HAND_RANGE = 9       -- studs: walk this close to your client and the app changes hands
local WALK_SPEED = 10      -- studs a second, the walk up and away
local TICK = 0.1
local DRAW_EVERY = 0.25    -- bubbles and attributes at 4 Hz, not every frame (phones)

-- DESIGN.md tokens (the 1A bubble)
local INK = Color3.fromRGB(20, 22, 30)
local PAPER = Color3.fromRGB(255, 252, 246)
local WELL = Color3.fromRGB(236, 230, 218)
local GO = Color3.fromRGB(60, 203, 108)
local GOLD = Color3.fromRGB(255, 200, 61)
local GOLD_DEEP = Color3.fromRGB(138, 100, 0)
local GOLD_LIGHT = Color3.fromRGB(255, 241, 196)
local RED = Color3.fromRGB(240, 78, 78)
local BLUE = Color3.fromRGB(59, 139, 255)
local BLUE_DEEP = Color3.fromRGB(27, 92, 196)

return function(core)
	local sessions, plotOf, cashOf = core.sessions, core.plotOf, core.cashOf
	local api = {}
	local byUser = {}

	local folder = ReplicatedStorage:WaitForChild("SVRemotes")
	local function remote(name)
		local r = folder:FindFirstChild(name) or Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = folder
		return r
	end
	local codeHold = remote("CodeHold")      -- client -> server: true while the button is held
	local clientPaid = remote("ClientPaid")  -- server -> client: { pay, tip, wow, at, who }

	-- ------------------------------------------------------------- the door line
	-- where the clients queue: straight out of the garage door, away from the laptop
	local function doorLine(plot)
		if plot.clientLine then return plot.clientLine end
		local header = plot.garage and plot.garage:FindFirstChild("DoorHeader", true)
		local floorY = plot.hqPad.Position.Y
		local center, out
		if header then
			center = Vector3.new(header.Position.X, floorY, header.Position.Z)
			local look = Vector3.new(header.CFrame.LookVector.X, 0, header.CFrame.LookVector.Z).Unit
			local toLaptop = Vector3.new(plot.laptop.Position.X - center.X, 0, plot.laptop.Position.Z - center.Z)
			out = look:Dot(toLaptop) > 0 and -look or look
		else
			center = Vector3.new(plot.laptop.Position.X, floorY, plot.laptop.Position.Z)
			out = Vector3.new(0, 0, -1)
		end
		local side = out:Cross(Vector3.yAxis)
		plot.clientLine = { center = center, out = out, side = side }
		return plot.clientLine
	end

	local function spot(plot, i)
		local L = doorLine(plot)
		return L.center + L.out * (4 + 4.5 * (i - 1)) + L.side * ((i % 2 == 0) and 1.5 or -1.5)
	end

	local function farPoint(plot)
		local L = doorLine(plot)
		return L.center + L.out * 34 + L.side * 14
	end

	-- ------------------------------------------------------------- one client's body
	local function heightOf(model)
		local _, size = model:GetBoundingBox()
		return size.Y
	end

	local function standAt(model, pos, facing)
		local h = model:GetAttribute("StandH") or heightOf(model)
		model:SetAttribute("StandH", h)
		local p = pos + Vector3.new(0, h / 2, 0)
		model:PivotTo(CFrame.lookAt(p, Vector3.new(facing.X, p.Y, facing.Z)))
	end

	-- slide a rig from where it is to `to` at WALK_SPEED (rigs are anchored, like staff)
	local function walk(model, to, faceAfter, done)
		task.spawn(function()
			local start = model:GetPivot().Position
			local h = model:GetAttribute("StandH") or heightOf(model)
			local from = Vector3.new(start.X, start.Y - h / 2, start.Z)
			local dist = (Vector3.new(to.X, from.Y, to.Z) - from).Magnitude
			local t, T = 0, math.max(0.2, dist / WALK_SPEED)
			while t < T and model.Parent do
				t += task.wait()
				local a = math.min(1, t / T)
				standAt(model, from:Lerp(to, a), to + (to - from) * 10)
			end
			if model.Parent then
				if faceAfter then standAt(model, to, faceAfter) end
				if done then done() end
			end
		end)
	end

	local function bubble(model, client)
		local head = model:FindFirstChild("Head") or model.PrimaryPart
		if not head then return end
		local big = client.kind == "big"
		local bb = Instance.new("BillboardGui")
		bb.Name = "ClientBubble"
		bb.Size = UDim2.fromOffset(190, client.patience and 74 or 50)
		bb.StudsOffset = Vector3.new(0, 3.6, 0)
		bb.MaxDistance = 90
		bb.AlwaysOnTop = false
		bb.Parent = head

		local card = Instance.new("Frame")
		card.Name = "Card"
		card.AnchorPoint = Vector2.new(0.5, 0)
		card.Position = UDim2.fromScale(0.5, 0)
		card.Size = UDim2.fromOffset(0, 40)
		card.AutomaticSize = Enum.AutomaticSize.X
		card.BackgroundColor3 = big and GOLD_LIGHT or PAPER
		card.Parent = bb
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2.5
		stroke.Color = big and GOLD_DEEP or INK
		stroke.Parent = card
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 10)
		pad.Parent = card
		local row = Instance.new("UIListLayout")
		row.FillDirection = Enum.FillDirection.Horizontal
		row.VerticalAlignment = Enum.VerticalAlignment.Center
		row.Padding = UDim.new(0, 8)
		row.Parent = card

		-- the app icon: a rounded tile with three lines (the mock's .app)
		local icon = Instance.new("Frame")
		icon.Name = "Icon"
		icon.Size = UDim2.fromOffset(26, 26)
		icon.BackgroundColor3 = big and GOLD or BLUE
		icon.Parent = card
		Instance.new("UICorner", icon).CornerRadius = UDim.new(0, 7)
		local istroke = Instance.new("UIStroke")
		istroke.Thickness = 2
		istroke.Color = big and GOLD_DEEP or BLUE_DEEP
		istroke.Parent = icon
		for i = 0, 2 do
			local line = Instance.new("Frame")
			line.BorderSizePixel = 0
			line.BackgroundColor3 = PAPER
			line.Position = UDim2.fromOffset(7, 6 + i * 5)
			line.Size = UDim2.fromOffset(12, 3)
			line.Parent = icon
		end

		local text = Instance.new("TextLabel")
		text.Name = "Ask"
		text.BackgroundTransparency = 1
		text.AutomaticSize = Enum.AutomaticSize.X
		text.Size = UDim2.fromOffset(0, 30)
		text.Font = Enum.Font.FredokaOne
		text.TextSize = 18
		text.TextColor3 = INK
		text.Text = client.ask
		text.Parent = card

		if client.patience then
			local bar = Instance.new("Frame")
			bar.Name = "Patience"
			bar.AnchorPoint = Vector2.new(0.5, 0)
			bar.Position = UDim2.new(0.5, 0, 0, 50)
			bar.Size = UDim2.fromOffset(120, 14)
			bar.BackgroundColor3 = WELL
			bar.Parent = bb
			Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
			local bstroke = Instance.new("UIStroke")
			bstroke.Thickness = 2
			bstroke.Color = INK
			bstroke.Parent = bar
			local fill = Instance.new("Frame")
			fill.Name = "Fill"
			fill.BorderSizePixel = 0
			fill.Size = UDim2.fromScale(1, 1)
			fill.BackgroundColor3 = GO
			fill.Parent = bar
			Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
		end
	end

	local function say(model, text)
		local bb = model:FindFirstChild("ClientBubble", true)
		local ask = bb and bb:FindFirstChild("Ask", true)
		if ask then ask.Text = text end
		local bar = bb and bb:FindFirstChild("Patience")
		if bar then bar.Visible = false end
		local icon = bb and bb:FindFirstChild("Icon", true)
		if icon then icon.Visible = false end
	end

	local function makeRig(player, P, client)
		local model = StaffRig.build(client.kind == "big" and "sales" or "designer", 900 + client.id * 13 + (player.UserId % 97))
		model.Name = "Client" .. client.id
		model:SetAttribute("ClientOf", player.UserId)
		model:SetAttribute("Ask", client.ask)
		model:SetAttribute("Patience", 1)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then d.CanCollide = false; d.CanTouch = false; d.CanQuery = false end
		end
		local holder = P.plot.garage.Parent:FindFirstChild("Clients")
		if not holder then
			holder = Instance.new("Folder")
			holder.Name = "Clients"
			holder.Parent = P.plot.garage.Parent
		end
		model.Parent = holder
		bubble(model, client)
		P.rigs[client.id] = model
		return model
	end

	-- the rig walks off and is gone
	local function leave(P, client, line)
		local model = P.rigs[client.id]
		P.rigs[client.id] = nil
		if not model then return end
		if line then say(model, line) end
		task.delay(line and 1.4 or 0, function()
			if model.Parent then walk(model, farPoint(P.plot), nil, function() model:Destroy() end) end
		end)
	end

	-- everyone in line walks to their spot (the line moves up when the front leaves)
	local function placeLine(P)
		for i, c in ipairs(P.Q.line) do
			local model = P.rigs[c.id]
			local want = spot(P.plot, i)
			if model and model.Parent and model:GetAttribute("Spot") ~= i then
				model:SetAttribute("Spot", i)
				walk(model, want, doorLine(P.plot).center)
			end
		end
	end

	-- ------------------------------------------------------------- money
	local function paid(player, P, e, who)
		local cash = cashOf(player)
		if not cash then return end
		local model = P.rigs[e.client.id]
		local at = model and model:GetPivot().Position or P.plot.laptop.Position
		cash.Value += e.pay
		Telemetry.money(player, "source", e.pay, "client")
		if (e.tip or 0) > 0 then
			cash.Value += e.tip
			Telemetry.money(player, "source", e.tip, "client_tip")
		end
		Telemetry.event(player, "client_served", 1, { { "who", who } })
		if who == "big" then Telemetry.mark(player, "first_big_client") end
		P.lastWho = who
		clientPaid:FireClient(player, { pay = e.pay, tip = e.tip or 0, wow = e.client.kind == "first", at = at, who = who })
		if model then StaffRig.cheer(model) end
		leave(P, e.client, "Just what I needed!")
	end

	local function handOverNow(player, P)
		local e = Clients.handOver(P.Q, { rate = (sessions[player.UserId] or {}).rate or 0 })
		if not e then return nil end
		if e.client.kind == "first" then core.shipFirstProduct(player, P.plot) end
		paid(player, P, e, e.client.kind == "big" and "big" or "you")
		player:SetAttribute("CarryingApp", false)
		placeLine(P)
		return e
	end

	-- ------------------------------------------------------------- the loop
	local function stageOf(level)
		local n = 1
		for _, at in ipairs(WaferPlan.STAGE_AT) do if level >= at then n += 1 end end
		return n
	end

	local function levelOf(plot)
		return (plot.wafer and plot.wafer.level) or (plot.hq and plot.hq.level) or 1
	end

	local function codersOf(s)
		local out = {}
		for _, r in ipairs(s.rigs or {}) do
			if r.seated and r.rig then
				table.insert(out, Clients.coderSpeed(r.tier or 1, r.rig:GetAttribute("Role")))
			end
		end
		table.sort(out, function(a, b) return a > b end)
		return out
	end

	local function start(player)
		local uid = player.UserId
		local t0 = os.clock()
		while player.Parent and not (sessions[uid] and plotOf(player) and player:GetAttribute("HQLevel") ~= nil) do
			if os.clock() - t0 > 60 then return end
			task.wait(0.25)
		end
		if not player.Parent then return end
		local s, plot = sessions[uid], plotOf(player)
		local first = not s.shipped and (s.spinoffs or 0) == 0 and (s.launches or 0) == 0
		local P = { Q = Clients.new({ first = first, seed = uid % 100000 + 17 }), plot = plot, rigs = {},
			hold = false, tapUntil = 0, lastToggle = 0, coded = false }
		byUser[uid] = P
		if first then
			-- the first client knocks and the door rolls up for them (spec call 9)
			core.openDoor(plot, true)
		end
		local lastDraw = 0
		while player.Parent and byUser[uid] == P do
			local dt = task.wait(TICK)
			s = sessions[uid]
			if not s or plotOf(player) ~= P.plot then break end
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local atLaptop = root ~= nil and (root.Position - P.plot.laptop.Position).Magnitude <= LAPTOP_RANGE
			local holding = P.hold or os.clock() < P.tapUntil
			local level = levelOf(P.plot)
			local brew = (core.Econ and core.Econ.Inv and core.Econ.Inv.codeMult(player)) or 1
			local events = Clients.tick(P.Q, dt, { level = level, stage = stageOf(level), rate = s.effective or s.rate or 0,
				holding = holding, atLaptop = atLaptop, coders = codersOf(s), speedMult = brew })

			if holding and atLaptop and not P.Q.carrying and #P.Q.line > 0 then
				if not P.coded then P.coded = true; Telemetry.step(player, "first_code") end
				-- holding also pushes the product bar, about as two taps a second did
				local Econ = core.Econ
				if Econ and Econ.V3 and s.shipped and not s.pendingProduct then
					local team = 0
					for _, r in ipairs(s.rigs or {}) do team += core.CFG.TIER_RATE[r.tier or 1] end
					s.work = (s.work or 0) + math.max(1, team * Econ.CODE_WORK) * brew * 2 * dt
				end
			end

			for _, e in ipairs(events) do
				if e.kind == "arrive" then
					local model = makeRig(player, P, e.client)
					standAt(model, farPoint(P.plot), doorLine(P.plot).center)
					placeLine(P)
				elseif e.kind == "shipped" then
					player:SetAttribute("CarryingApp", true)
					core.popup(P.plot.laptop, "SHIPPED!", GO)
				elseif e.kind == "served" then
					paid(player, P, e, "coder")
					placeLine(P)
				elseif e.kind == "lost" then
					Telemetry.event(player, "client_lost", 1)
					leave(P, e.client, "Too slow...")
					placeLine(P)
				end
			end

			-- the first client is placed at the door at once (no walk-up wait)
			for i, c in ipairs(P.Q.line) do
				if not P.rigs[c.id] then
					local model = makeRig(player, P, c)
					standAt(model, spot(P.plot, i), doorLine(P.plot).center)
					model:SetAttribute("Spot", i)
				end
			end

			-- hand-over: walk up to the client you coded for
			local carried = P.Q.carrying
			local cm = carried and P.rigs[carried.id]
			if cm and root and (root.Position - cm:GetPivot().Position).Magnitude <= HAND_RANGE then
				handOverNow(player, P)
			end

			if os.clock() - lastDraw >= DRAW_EVERY then
				lastDraw = os.clock()
				local front
				for _, c in ipairs(P.Q.line) do
					if c ~= P.Q.carrying and c.done < c.need then front = front or c end
					local model = P.rigs[c.id]
					if model and c.patience then
						local f = math.clamp(c.left / c.patience, 0, 1)
						model:SetAttribute("Patience", f)
						local fill = model:FindFirstChild("Fill", true)
						if fill then
							fill.Size = UDim2.fromScale(f, 1)
							fill.BackgroundColor3 = f > 0.5 and GO or f > 0.25 and GOLD or RED
						end
					end
				end
				local mine = holding and atLaptop and not P.Q.carrying and front
				player:SetAttribute("CodeProgress", mine and (front.done / front.need) or (front and front.done > 0 and front.by == "you" and front.done / front.need) or 0)
				player:SetAttribute("AtLaptop", atLaptop)
				player:SetAttribute("ClientsWaiting", #P.Q.line)
				player:SetAttribute("JobWaiting", front ~= nil)
				local target = carried and P.rigs[carried.id] or (P.Q.line[1] and P.rigs[P.Q.line[1].id])
				P.frontPos = target and target.Parent and target:GetPivot().Position or nil
			end
		end
	end

	-- ------------------------------------------------------------- what others call
	function api.hold(player, on)
		local P = byUser[player.UserId]
		if P then P.hold = on == true end
	end

	-- an old tap (the WriteCode remote, a click on the laptop): a short hold
	function api.tap(player)
		local P = byUser[player.UserId]
		if P then P.tapUntil = os.clock() + 0.35 end
	end

	function api.state(player)
		local P = byUser[player.UserId]
		if not P then return { carrying = false, waiting = 0, served = 0 } end
		local waiting = 0
		for _, c in ipairs(P.Q.line) do if c ~= P.Q.carrying and c.done < c.need then waiting += 1 end end
		return { carrying = P.Q.carrying ~= nil, waiting = waiting, front = P.Q.line[1], frontPos = P.frontPos,
			served = P.Q.served, lost = P.Q.lost, lastWho = P.lastWho, tutorial = P.Q.tutorial, line = #P.Q.line }
	end

	-- the plain table Clients.goal reads (Task 7 adds the HQ fields from SiliconCore)
	function api.goalState(player)
		local st = api.state(player)
		return { served = st.served, carrying = st.carrying, waiting = st.line, tutorial = st.tutorial }
	end

	local function clear(uid)
		local P = byUser[uid]
		byUser[uid] = nil
		if not P then return end
		for _, model in pairs(P.rigs) do if model.Parent then model:Destroy() end end
	end

	-- a spin-off or a dev reset: new line, no tutorial unless asked
	function api.reset(player, first)
		local P = byUser[player.UserId]
		clear(player.UserId)
		player:SetAttribute("CarryingApp", false)
		player:SetAttribute("CodeProgress", 0)
		if P or first then
			task.spawn(function()
				if first then
					local s = sessions[player.UserId]
					if s then s.shipped = false end
				end
				start(player)
			end)
		end
	end

	-- dev hook: finish the job at the door and hand it over now (doctor, scenarios)
	function api.devServe(player)
		local P = byUser[player.UserId]
		if not P then return { ok = false, err = "no client loop for this player" } end
		local c = P.Q.carrying
		if not c then
			for _, x in ipairs(P.Q.line) do if x.done < x.need then c = x break end end
			if not c then return { ok = false, err = "nobody waiting" } end
			c.done, c.by = c.need, "you"
			P.Q.carrying = c
		end
		local e = handOverNow(player, P)
		return { ok = e ~= nil, pay = e and e.pay, tip = e and e.tip, kind = e and e.client.kind }
	end

	codeHold.OnServerEvent:Connect(function(player, on)
		local P = byUser[player.UserId]
		if not P then return end
		if os.clock() - P.lastToggle < 0.1 then return end   -- a toggle spammer gains nothing
		P.lastToggle = os.clock()
		P.hold = on == true
	end)

	Players.PlayerAdded:Connect(function(player) task.spawn(start, player) end)
	for _, player in ipairs(Players:GetPlayers()) do task.spawn(start, player) end
	Players.PlayerRemoving:Connect(function(player) clear(player.UserId) end)
	local function onChar(player)
		player.CharacterRemoving:Connect(function()
			local P = byUser[player.UserId]
			if P then P.hold = false end
		end)
	end
	Players.PlayerAdded:Connect(onChar)
	for _, player in ipairs(Players:GetPlayers()) do onChar(player) end

	return api
end
