--[[ ClientsServer (16 Oct 2026): the people at your door, the hold, the hand-over, the pay.

	Spec: silicon-startup/docs/superpowers/specs/2026-10-16-client-loop-design.md.
	Mocks Luke picked: 1A (speech bubble + patience bar), 2C (the button is the
	progress bar), 3A (pops + coins) and 3B (the first client's stamp).

	The rules are Clients.lua (pure, offline-tested). This module is the world:
	it walks client rigs up to the garage door, draws their bubble, reads whether
	you hold WRITE CODE at your laptop, hands the app over when you press GIVE next
	to the client (17 Oct, Luke's pick 2A), and adds the cash (with its Telemetry line). SiliconCore wires it from
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
local TowerPlan = require(ReplicatedStorage:WaitForChild("TowerPlan"))

local LAPTOP_RANGE = 12    -- studs: holding counts within this of your laptop
local HAND_RANGE = 10      -- studs: this close to your client, GIVE (or E) hands the app over
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
local BLUE_LIGHT = Color3.fromRGB(221, 235, 255)
local GO_DEEP = Color3.fromRGB(22, 118, 58)
local GO_LIGHT = Color3.fromRGB(214, 245, 224)

-- 17 Oct, Luke's pick 3A: a client's bubble wears its tier, in the recruit tiers' colours
-- (card, its outline, the app tile, the tile's outline)
local TIER_LOOK = {
	regular = { PAPER, INK, BLUE, BLUE_DEEP },
	skilled = { GO_LIGHT, GO_DEEP, GO, GO_DEEP },
	star = { BLUE_LIGHT, BLUE_DEEP, BLUE, BLUE_DEEP },
	big = { GOLD_LIGHT, GOLD_DEEP, GOLD, GOLD_DEEP },
}
local THANKS = { "Just what I needed!", "Thanks!", "Took a while..." }   -- by stars 3, 2, 1

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
	local clientPaid = remote("ClientPaid")  -- server -> client: { pay, tip, wow, at, who, stars, from }
	local giveApp = remote("GiveApp")        -- client -> server: GIVE pressed (the HUD button)

	-- ------------------------------------------------------------- the door line
	--[[ where the clients queue: straight out of the garage door, away from the
		laptop. Measured from the garage's DoorHeader, which only exists while the
		plot is a garage: every plot is one when the server starts, so init measures
		them all; a line measured without the header is never kept (a level-16 save
		loading first left the line beside the laptop, 16 Oct live check). ]]
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
		local line = { center = center, out = out, side = side }
		if header then plot.clientLine = line end
		return line
	end
	for _, plot in pairs(core.plots or {}) do pcall(doorLine, plot) end

	local function levelOf(plot)
		return (plot.wafer and plot.wafer.level) or (plot.hq and plot.hq.level) or 1
	end

	-- from the lobby on, the reception desk in the middle (Luke's pick 1A, Clients.counterLine)
	local LOBBY_LINE = Clients.counterLine(TowerPlan.room(0, 1))
	local function lobbyMode(plot) return levelOf(plot) >= 2 end
	local function localAt(plot, x, z)
		local p = plot.g(x, 0, z).Position
		return Vector3.new(p.X, plot.hqPad.Position.Y, p.Z)
	end

	-- 22 Oct: the ground's real height at a spot outside (the path is 0.6, the garage floor 1.0, the
	-- pad 1.2); people, clients and anything not solid are ignored
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.RespectCanCollide = true
	local function groundAt(plot, p)
		local skip = {}
		for _, pl in ipairs(game:GetService("Players"):GetPlayers()) do if pl.Character then table.insert(skip, pl.Character) end end
		local cf = plot.folder and plot.folder:FindFirstChild("Clients")
		if cf then table.insert(skip, cf) end
		groundParams.FilterDescendantsInstances = skip
		local hit = workspace:Raycast(Vector3.new(p.X, p.Y + 6, p.Z), Vector3.new(0, -14, 0), groundParams)
		return hit and Vector3.new(p.X, hit.Position.Y, p.Z) or p
	end

	local function spot(plot, i)
		if lobbyMode(plot) then
			local sp = LOBBY_LINE.spots[math.clamp(i, 1, #LOBBY_LINE.spots)]
			return localAt(plot, sp.x, sp.z)
		end
		local L = doorLine(plot)
		return groundAt(plot, L.center + L.out * (4 + 4.5 * (i - 1)) + L.side * ((i % 2 == 0) and 1.5 or -1.5))
	end

	-- where a waiting client looks: the counter, or the garage door
	local function lookAtOf(plot)
		if lobbyMode(plot) then return localAt(plot, LOBBY_LINE.counter.x, LOBBY_LINE.counter.z) end
		return doorLine(plot).center
	end

	-- the way in, from outside to just inside (the lobby's entrance; the garage has an open front)
	local function entryPath(plot)
		if lobbyMode(plot) then
			local out = {}
			for _, q in ipairs(LOBBY_LINE.path) do table.insert(out, localAt(plot, q.x, q.z)) end
			return out
		end
		local L = doorLine(plot)
		return { groundAt(plot, L.center + L.out * 34 + L.side * 14) }
	end

	--[[ the reception desk (1A): Oak top, PaperWhite body, a BrandGold stripe, round ends
		(the wafer rule), a CLIENTS sign on its door-facing side, and a CaliforniaGold rug
		under the line from the desk to the entrance. No rope line: the rug says where
		to stand (Palette anchors only). ]]
	local OAK, PAPER_W, BRAND, INK_C = Color3.fromRGB(192, 138, 85), Color3.fromRGB(243, 239, 230),
		Color3.fromRGB(255, 194, 61), Color3.fromRGB(30, 37, 48)
	local CAL_GOLD = Color3.fromRGB(224, 182, 90)
	local function setCounter(plot, on)
		if not on then
			if plot.clientCounter then plot.clientCounter:Destroy(); plot.clientCounter = nil end
			return
		end
		if plot.clientCounter and plot.clientCounter.Parent then return end
		local m = Instance.new("Model")
		m.Name = "HQ_ClientCounter"
		local y0 = plot.hqPad.Position.Y
		local function piece(name, shape, size, x, y, z, color, rot)
			local part = Instance.new("Part")
			part.Name, part.Anchored, part.Material = name, true, Enum.Material.SmoothPlastic
			part.Shape = shape or Enum.PartType.Block
			part.Size, part.Color = size, color
			local cf = plot.g(x, 0, z)
			part.CFrame = CFrame.new(cf.Position.X, y0 + y, cf.Position.Z) * (cf - cf.Position) * (rot or CFrame.new())
			part.Parent = m
			return part
		end
		local C0, cyl = LOBBY_LINE.counter, Enum.PartType.Cylinder
		local upright = CFrame.Angles(0, 0, math.pi / 2)
		local bodyW = C0.w - C0.d
		piece("Body", nil, Vector3.new(bodyW, 3.2, C0.d), C0.x, 1.6, C0.z, PAPER_W)
		piece("Stripe", nil, Vector3.new(bodyW + 0.02, 0.35, C0.d + 0.02), C0.x, 2.55, C0.z, BRAND)
		piece("Top", nil, Vector3.new(bodyW + 0.4, 0.3, C0.d + 0.5), C0.x, 3.35, C0.z, OAK)
		for _, sx in ipairs({ -1, 1 }) do
			local ex = C0.x + sx * bodyW / 2
			piece("End", cyl, Vector3.new(3.2, C0.d, C0.d), ex, 1.6, C0.z, PAPER_W, upright)
			piece("TopEnd", cyl, Vector3.new(0.3, C0.d + 0.5, C0.d + 0.5), ex, 3.35, C0.z, OAK, upright)
		end
		-- the rug: from the desk's front to past the last spot, under the whole line
		local first, last = LOBBY_LINE.spots[1], LOBBY_LINE.spots[#LOBBY_LINE.spots]
		local z0, z1 = C0.z + C0.d / 2 + 0.4, last.z + 2.4
		local rug = piece("Rug", nil, Vector3.new(4.6, 0.12, z1 - z0), first.x, 0.06, (z0 + z1) / 2, CAL_GOLD)
		rug.Material, rug.CanCollide = Enum.Material.Fabric, false
		local trim = piece("RugTrim", nil, Vector3.new(5.2, 0.08, z1 - z0 + 0.6), first.x, 0.04, (z0 + z1) / 2, OAK)
		trim.Material, trim.CanCollide = Enum.Material.Fabric, false
		-- the sign: a board on the body's door side, read from the entrance
		local board = piece("Sign", nil, Vector3.new(5.2, 1.5, 0.12), C0.x, 1.45, C0.z + C0.d / 2 + 0.07, INK_C)
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 40
		sg.LightInfluence = 0
		sg.Parent = board
		local word = Instance.new("TextLabel")
		word.BackgroundTransparency = 1
		word.Size = UDim2.fromScale(1, 1)
		word.Font = Enum.Font.FredokaOne
		word.TextScaled = true
		word.TextColor3 = BRAND
		word.Text = "CLIENTS"
		word.Parent = sg
		local wpad = Instance.new("UIPadding")
		wpad.PaddingTop, wpad.PaddingBottom = UDim.new(0.14, 0), UDim.new(0.14, 0)
		wpad.Parent = word
		-- the board faces the door (+z): turn it if plot.g's front points the other way
		local toDoor = (plot.g(C0.x, 0, C0.z + 10).Position - board.Position) * Vector3.new(1, 0, 1)
		if board.CFrame.LookVector:Dot(toDoor) < 0 then sg.Face = Enum.NormalId.Back end
		m.Parent = plot.garage.Parent
		plot.clientCounter = m
	end

	-- ------------------------------------------------------------- one client's body
	--[[ 22 Oct (Luke's look review: "the client is floating"; measured 1.01 studs above the path).
		Two causes. The rig was stood at half its bounding box above the spot, but the box includes the
		hair and accessories, so the pivot (the root) sat higher than the feet need; it now stands by
		the measured distance from the pivot down to its lowest part. And the garage's line spots were
		at the HQ pad's height (1.2) while outside the door the path is at 0.6: see groundAt. ]]
	local function footOffsetOf(model)
		local cf, size = model:GetBoundingBox()
		return model:GetPivot().Position.Y - (cf.Position.Y - size.Y / 2)
	end

	local function standAt(model, pos, facing)
		local off = model:GetAttribute("FootOff") or footOffsetOf(model)
		model:SetAttribute("FootOff", off)
		local p = pos + Vector3.new(0, off, 0)
		model:PivotTo(CFrame.lookAt(p, Vector3.new(facing.X, p.Y, facing.Z)))
	end

	-- slide a rig from where it is to `to` at WALK_SPEED (rigs are anchored, like staff)
	-- 17 Oct review: two walks on one rig fought frame by frame (a client walking in while the
	-- line moved up) and the older one could finish last, leaving them at the wrong spot. Each
	-- walk takes a token; a newer walk ends the older one.
	local function walk(model, to, faceAfter, done)
		local id = (model:GetAttribute("WalkId") or 0) + 1
		model:SetAttribute("WalkId", id)
		task.spawn(function()
			local start = model:GetPivot().Position
			local off = model:GetAttribute("FootOff") or footOffsetOf(model)
			local from = Vector3.new(start.X, start.Y - off, start.Z)
			local dist = (Vector3.new(to.X, from.Y, to.Z) - from).Magnitude
			local t, T = 0, math.max(0.2, dist / WALK_SPEED)
			while t < T and model.Parent and model:GetAttribute("WalkId") == id do
				t += task.wait()
				local a = math.min(1, t / T)
				standAt(model, from:Lerp(to, a), to + (to - from) * 10)
			end
			if model.Parent and model:GetAttribute("WalkId") == id then
				if faceAfter then standAt(model, to, faceAfter) end
				if done then done() end
			end
		end)
	end

	--[[ 17 Oct: the company name. New companies come named (Names.lua); from the lobby
		on, the entrance sign carries a RENAME prompt, said once by a world popup.
		17 Oct review: a style pick rebuilds the lobby and its sign, and the prompt went with
		it. The loop calls this about once a second in the lobby: a cached sign that still
		has its prompt costs nothing; a missing one is looked for at most every 5 s. ]]
	local function signPrompt(player, P)
		local sign = P.sign
		if sign and sign.Parent and sign:FindFirstChild("RenamePrompt") then return end
		if not (sign and sign.Parent) then
			if os.clock() < (P.signLookAt or 0) then return end
			P.signLookAt = os.clock() + 5
			sign = nil
			for _, d in ipairs(P.plot.garage.Parent:GetDescendants()) do
				if d.Name == "EntranceSign" and d:IsA("BasePart") then sign = d break end
			end
			P.sign = sign
		end
		if not sign or sign:FindFirstChild("RenamePrompt") then return end
		local pr = Instance.new("ProximityPrompt")
		pr.Name = "RenamePrompt"
		pr.ActionText, pr.ObjectText = "RENAME", "Your company"
		pr.MaxActivationDistance, pr.RequiresLineOfSight = 22, false
		pr.Triggered:Connect(function(who) if who == player and core.askRename then core.askRename(player) end end)
		pr.Parent = sign
		if not P.renameSaid then
			P.renameSaid = true
			task.delay(6, function() if sign.Parent then core.popup(sign, "Tap your sign to rename it.", GOLD) end end)
		end
	end

	local function walkPath(model, points, faceAfter, done)
		local i = 0
		local function nextLeg()
			i += 1
			if i > #points then if done then done() end return end
			walk(model, points[i], i == #points and faceAfter or nil, nextLeg)
		end
		nextLeg()
	end

	local function bubble(model, client)
		local head = model:FindFirstChild("Head") or model.PrimaryPart
		if not head then return end
		local look = TIER_LOOK[client.kind == "big" and "big" or client.tier or "regular"] or TIER_LOOK.regular
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
		card.BackgroundColor3 = look[1]
		card.Parent = bb
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2.5
		stroke.Color = look[2]
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
		icon.BackgroundColor3 = look[3]
		icon.Parent = card
		Instance.new("UICorner", icon).CornerRadius = UDim.new(0, 7)
		local istroke = Instance.new("UIStroke")
		istroke.Thickness = 2
		istroke.Color = look[4]
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
		if P.dead then return nil end   -- 17 Oct review: a cleared line never makes a rig
		local model = StaffRig.build(client.kind == "big" and "sales" or "designer", 900 + client.id * 13 + (player.UserId % 97))
		model.Name = "Client" .. client.id
		model:SetAttribute("ClientOf", player.UserId)
		model:SetAttribute("Ask", client.ask)
		model:SetAttribute("Tier", client.kind == "big" and "big" or client.tier or "regular")
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
		local gp = model:FindFirstChild("GivePrompt", true)
		if gp then gp:Destroy() end
		if line then say(model, line) end
		task.delay(line and 1.8 or 0, function()
			if not model.Parent then return end
			local path = entryPath(P.plot)
			local back = {}
			for k = #path, 1, -1 do table.insert(back, path[k]) end
			walkPath(model, back, nil, function() model:Destroy() end)
		end)
	end

	-- everyone in line walks to their spot (the line moves up when the front leaves)
	local function placeLine(P)
		for i, c in ipairs(P.Q.line) do
			local model = P.rigs[c.id]
			local want = spot(P.plot, i)
			if model and model.Parent and model:GetAttribute("Spot") ~= i then
				model:SetAttribute("Spot", i)
				walk(model, want, lookAtOf(P.plot))
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
		local tier = e.client.kind == "big" and "big" or e.client.tier or "regular"
		Telemetry.event(player, "client_served", 1, { { "who", who }, { "tier", tier } })
		if who == "big" then Telemetry.mark(player, "first_big_client") end
		P.lastWho = who
		-- 2A: stars for your own hand-overs (a coder's delivery is just the cash)
		local stars = who ~= "coder" and Clients.stars(e.client) or nil
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		clientPaid:FireClient(player, { pay = e.pay, tip = e.tip or 0, wow = e.client.kind == "first", at = at, who = who,
			stars = stars, from = root and root.Position or nil, tier = tier })
		if model then
			-- they open it (the card above them), then cheer: the FX takes about a second
			task.delay(stars and 0.45 or 0, function() if model.Parent then StaffRig.cheer(model) end end)
		end
		leave(P, e.client, THANKS[4 - (stars or 3)])
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

	local function start(player, forceFirst)
		local uid = player.UserId
		local t0 = os.clock()
		while player.Parent and not (sessions[uid] and plotOf(player) and player:GetAttribute("HQLevel") ~= nil) do
			if os.clock() - t0 > 60 then return end
			task.wait(0.25)
		end
		if not player.Parent then return end
		local s, plot = sessions[uid], plotOf(player)
		local first = forceFirst == true or (not s.shipped and (s.spinoffs or 0) == 0 and (s.launches or 0) == 0)
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
			-- 17 Oct review: a reset or a leave during the wait ends this loop before it acts
			-- (one more pass made orphan rigs and a stuck CarryingApp)
			if byUser[uid] ~= P then break end
			s = sessions[uid]
			if not s or plotOf(player) ~= P.plot then break end
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local atLaptop = root ~= nil and (root.Position - P.plot.laptop.Position).Magnitude <= LAPTOP_RANGE
			local holding = P.hold or os.clock() < P.tapUntil
			local level = levelOf(P.plot)
			local mode = level >= 2 and "lobby" or "garage"
			if mode ~= P.mode then
				P.mode = mode
				setCounter(P.plot, mode == "lobby")
				P.sign, P.signLookAt = nil, 0
				for i, c in ipairs(P.Q.line) do
					local model = P.rigs[c.id]
					if model then
						model:SetAttribute("WalkId", (model:GetAttribute("WalkId") or 0) + 1)   -- the teleport ends any walk
						standAt(model, spot(P.plot, i), lookAtOf(P.plot))
						model:SetAttribute("Spot", i)
					end
				end
			end
			local brew = (core.Econ and core.Econ.Inv and core.Econ.Inv.codeMult(player)) or 1
			local events = Clients.tick(P.Q, dt, { level = level, stage = stageOf(level), rate = s.effective or s.rate or 0,
				holding = holding, atLaptop = atLaptop, coders = codersOf(s), speedMult = brew })

			if holding and atLaptop and not P.Q.carrying and #P.Q.line > 0 then
				if not P.coded then P.coded = true; Telemetry.step(player, "first_code") end
				-- holding also pushes the product bar, about as two taps a second did
				local Econ = core.Econ
				if Econ and Econ.V3 and s.shipped and not s.pendingProduct and Clients.productsOpen(level) then
					local team = 0
					for _, r in ipairs(s.rigs or {}) do team += core.CFG.TIER_RATE[r.tier or 1] end
					s.work = (s.work or 0) + math.max(1, team * Econ.CODE_WORK) * brew * 2 * dt
				end
			end

			for _, e in ipairs(events) do
				if e.kind == "arrive" then
					local model = makeRig(player, P, e.client)
					if not model then continue end
					local path = entryPath(P.plot)
					standAt(model, path[1], lookAtOf(P.plot))
					local idx = Clients.spotOf(P.Q, e.client)
					model:SetAttribute("Spot", idx)
					local legs = {}
					for k = 2, #path do table.insert(legs, path[k]) end
					table.insert(legs, spot(P.plot, idx))
					walkPath(model, legs, lookAtOf(P.plot))
				elseif e.kind == "shipped" then
					player:SetAttribute("CarryingApp", true)
					core.popup(P.plot.laptop, "SHIPPED!", GO)
				elseif e.kind == "served" then
					-- 17 Oct review: the spec's teaching line, said where it happens, once a session
					local model = P.rigs[e.client.id]
					local at = model and (model:FindFirstChild("Head") or model.PrimaryPart)
					paid(player, P, e, "coder")
					placeLine(P)
					if at and not s.coderTaught and (s.staff or 0) == 1 then
						s.coderTaught = true
						core.popup(at, "Your coder takes the small jobs.", GO)
					end
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
					if model then
						standAt(model, spot(P.plot, i), lookAtOf(P.plot))
						model:SetAttribute("Spot", i)
					end
				end
			end

			--[[ hand-over (17 Oct, Luke's pick 2A): walking up no longer hands it over by
				itself. Near the client you coded for, the HUD button turns into a gold GIVE
				and a GIVE prompt (E) sits on them; one press and it is yours to give. ]]
			local carried = P.Q.carrying
			local cm = carried and P.rigs[carried.id]
			local near = cm ~= nil and root ~= nil and (root.Position - cm:GetPivot().Position).Magnitude <= HAND_RANGE
			if near ~= P.canGive then
				P.canGive = near
				player:SetAttribute("CanGive", near)
			end
			if cm and not cm:FindFirstChild("GivePrompt", true) then
				local at = cm:FindFirstChild("HumanoidRootPart") or cm.PrimaryPart
				if at then
					local pr = Instance.new("ProximityPrompt")
					pr.Name = "GivePrompt"
					pr.ActionText, pr.ObjectText = "GIVE", carried.ask or "Their app"
					pr.KeyboardKeyCode, pr.GamepadKeyCode = Enum.KeyCode.E, Enum.KeyCode.ButtonX
					pr.HoldDuration, pr.MaxActivationDistance, pr.RequiresLineOfSight = 0, HAND_RANGE, false
					pr.Style = Enum.ProximityPromptStyle.Custom   -- the HUD's GIVE is the look; E still works
					pr.Triggered:Connect(function(who) if who == player then api.give(player) end end)
					pr.Parent = at
				end
			end

			if os.clock() - lastDraw >= DRAW_EVERY then
				lastDraw = os.clock()
				if P.mode == "lobby" and os.clock() >= (P.signAt or 0) then
					P.signAt = os.clock() + 1
					signPrompt(player, P)
				end
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
				-- 24 Oct (F-5): only a job no coder can take waits for you (Clients.waitingForYou); a
				-- coder's job flipped HOLD TO CODE <-> LAUNCH! every 2-4 s with a big team. The HUD's
				-- button and the paused LAUNCH! clock (OneVoice.launchHeld) both read this one flag
				player:SetAttribute("JobWaiting", Clients.waitingForYou(P.Q, #codersOf(s)) ~= nil)
				-- 24 Oct (one instruction, rule A): a job you started coding is a job in your hands;
				-- HudClient folds LAUNCH! to its chip for it, as the server pauses its clock (OneVoice)
				player:SetAttribute("MidJob", Clients.started(P.Q) ~= nil)
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

	-- GIVE: hand the app you carry to its client, if you are next to them
	function api.give(player)
		local P = byUser[player.UserId]
		if not P or not P.Q.carrying then return nil end
		local cm = P.rigs[P.Q.carrying.id]
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not (cm and root) or (root.Position - cm:GetPivot().Position).Magnitude > HAND_RANGE + 2 then return nil end
		P.canGive = false
		player:SetAttribute("CanGive", false)
		return handOverNow(player, P)
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
	api.goal, api.fallback, api.productsOpen = Clients.goal, Clients.fallback, Clients.productsOpen

	function api.goalState(player)
		local st = api.state(player)
		local P = byUser[player.UserId]
		-- 18 Oct (option A): a job you started coding wins the goal line ("Finish the app")
		return { served = st.served, carrying = st.carrying, waiting = st.line, tutorial = st.tutorial,
			midJob = P ~= nil and Clients.started(P.Q) ~= nil }
	end

	local function clear(uid)
		local P = byUser[uid]
		byUser[uid] = nil
		if not P then return end
		P.dead = true
		for _, model in pairs(P.rigs) do if model.Parent then model:Destroy() end end
		P.rigs = {}
		-- clients walking off are no longer in P.rigs: anything of ours left in the folder goes too
		local holder = P.plot and P.plot.garage and P.plot.garage.Parent and P.plot.garage.Parent:FindFirstChild("Clients")
		if holder then
			for _, m in ipairs(holder:GetChildren()) do
				if m:GetAttribute("ClientOf") == uid then m:Destroy() end
			end
		end
		setCounter(P.plot, false)
	end

	-- a spin-off or a dev reset: new line, no tutorial unless asked
	function api.reset(player, first)
		local P = byUser[player.UserId]
		clear(player.UserId)
		player:SetAttribute("CarryingApp", false)
		player:SetAttribute("CanGive", false)
		player:SetAttribute("CodeProgress", 0)
		player:SetAttribute("MidJob", false)   -- 24 Oct: the line is gone, so is the job you started
		if P or first then
			task.spawn(function()
				if first then
					local s = sessions[player.UserId]
					if s then s.shipped = false end
				end
				start(player, first)
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

	giveApp.OnServerEvent:Connect(function(player)
		local P = byUser[player.UserId]
		if not P or os.clock() - (P.lastGive or 0) < 0.3 then return end
		P.lastGive = os.clock()
		api.give(player)
	end)

	codeHold.OnServerEvent:Connect(function(player, on)
		local P = byUser[player.UserId]
		if not P then return end
		P.hold, P.lastToggle = Clients.holdEvent(on, P.hold, P.lastToggle, os.clock())
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
