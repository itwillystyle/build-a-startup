--[[
	BobSceneClient -- LocalScript in StarterPlayer -> StarterPlayerScripts. P-5 (25 Oct 2026).

	Plays Bob's two cutscenes from BobScript's data, on this client only:
	  "intro"   a new save meets Bob (IntroClient hands off via PlayerGui.SVBobScene)
	  "payoff"  the server paid you at Bob's door (SVRemotes.BobPayoff, money ALREADY paid)

	Spec: docs/superpowers/specs/2026-10-25-bob-first-boss-investor-design.md (3a, 3e, 5, 5b-1).
	Rules it keeps:
	  * SKIP from frame 1. Only the SKIP button, or a TAP on touch, skips; keys and clicks
	    do not (5b-1). The player cannot move while it plays.
	  * ONE finish() for skip and the end: clones gone, camera Custom + the humanoid, controls
	    on, the HUD back, BobScenePlaying false. Never a stored Scriptable camera.
	  * Reduce Motion is read EVERY frame (BobScript drops the shake and the pushes).
	  * It never touches the server's world: door, tape and front wall are local overrides
	    that finish() puts back.
	Actors are clones (Bob and the investors from ReplicatedStorage.BobCast; you from your own
	HumanoidDescription, or a plain stand-in if that fails or takes over 2 s), posed by code
	through Motor6D.Transform: no animation uploads.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local player = Players.LocalPlayer
local UIKit = require(RS:WaitForChild("UIKit"))
local BobScript = require(RS:WaitForChild("BobScript"))
local BobFace = require(RS:WaitForChild("BobFace"))
local BobClips = require(RS:WaitForChild("BobClips"))
local Sfx = require(RS:WaitForChild("Sfx"))
local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local SOUND = BobScript.SOUND   -- a scene's sound names -> { Sfx.ID key, at, len, gain }
local POSE_BLEND = 0.2   -- s: a change of pose inside a shot eases over this
local INK = UIKit.INK

-- a sound's volume down to 0 over `secs`, then it stops (an audio fade: not motion, so Reduce Motion
-- leaves it alone, and it is not a tween)
local function fadeOut(s, secs)
	task.spawn(function()
		local v0, t0 = s.Volume, os.clock()
		while s.Parent and os.clock() - t0 < secs do
			s.Volume = v0 * (1 - (os.clock() - t0) / secs)
			RunService.Heartbeat:Wait()
		end
		if s.Parent then s:Stop() end
	end)
end
local PAPER = UIKit.PAPER

local playing = false
local event = Instance.new("BindableEvent")
event.Name = "SVBobScene"
event.Parent = player:WaitForChild("PlayerGui")

-- ------------------------------------------------------------------ anchors
local function anchors()
	local sv = workspace:FindFirstChild("SiliconValley")
	local bc = sv and sv:FindFirstChild("BobCapital")
	if not bc then return nil end
	local a = { board = bc:GetAttribute("AnchorBoard"), door = bc:GetAttribute("AnchorDoor"), street = bc:GetAttribute("AnchorStreet") }
	local idx = player:GetAttribute("Plot")
	local pf = idx and sv:FindFirstChild("Plots") and sv.Plots:FindFirstChild("Plot" .. idx)
	local pivot = pf and pf:GetAttribute("Pivot")
	a.garage = pivot and pivot * CFrame.new(0, 0, -9) or a.street
	if not (a.board and a.door and a.street) then return nil end
	return a, bc
end

-- ------------------------------------------------------------------ actors
local function prep(model, name)
	model.Name = name
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = d.Name == "HumanoidRootPart"
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end
	-- review I-8: an Animator would overwrite the code-driven poses every frame
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Animator") or d:IsA("AnimationController") then d:Destroy() end
	end
	local motors = {}
	for _, m in ipairs(model:GetDescendants()) do
		if m:IsA("Motor6D") then
			motors[m.Name] = m
		elseif m:IsA("AnimationConstraint") then
			motors[m.Name] = m
			pcall(function() m.IsKinematic = true end)   -- a pose is a pose, not a spring
		end
	end
	return { model = model, root = model:FindFirstChild("HumanoidRootPart"), hum = hum, motors = motors,
		face = BobFace.attach(model), head = model:FindFirstChild("Head") }
end

local function heroModel()
	-- review I-2: Players:CreateHumanoidModelFromDescription is server-only; a client clones its
	-- own character instead (TalentRevealClient and RigPortrait do the same)
	local char = player.Character
	if char and char:FindFirstChildOfClass("Humanoid") then
		local was = char.Archivable
		char.Archivable = true
		local ok, m = pcall(function() return char:Clone() end)
		char.Archivable = was
		if ok and m and m:FindFirstChild("HumanoidRootPart") then
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("ForceField") or d:IsA("BillboardGui") then d:Destroy() end
			end
			return m
		end
	end
	-- the stand-in: a cast member in your-avatar colours (never a hang on a black screen)
	local cast = RS:FindFirstChild("BobCast")
	local m = cast and cast:FindFirstChild("Inv1") and cast.Inv1:Clone()
	if m then
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") then
				if p.Name:find("Torso") or p.Name:find("Arm") then p.Color = Color3.fromRGB(58, 134, 255)   -- world colour
				elseif p.Name:find("Leg") then p.Color = Color3.fromRGB(43, 58, 103)   -- world colour
				elseif p.Name == "Head" or p.Name:find("Hand") then p.Color = Color3.fromRGB(245, 205, 48) end   -- world colour
			elseif p:IsA("Shirt") or p:IsA("Pants") or p:IsA("Accessory") then p:Destroy() end
		end
	end
	return m
end

-- code-driven poses: Motor6D.Transform per joint (radians). t = scene time, for cycles
local R = math.rad
local function pose(a, name, t)
	local m = a.motors
	local function set(joint, cf) if m[joint] then m[joint].Transform = cf end end
	for _, j in pairs(m) do j.Transform = CFrame.new() end
	local breathe = math.sin(t * 2) * 0.03
	set("Waist", CFrame.Angles(breathe, 0, 0))
	if name == "gesture" then
		set("RightShoulder", CFrame.Angles(R(150), 0, R(-10)))
	elseif name == "laugh" then
		local b = math.abs(math.sin(t * 13))
		set("Waist", CFrame.Angles(R(-14 - 6 * b), 0, 0))
		set("Neck", CFrame.Angles(R(-18), 0, 0))
		set("RightShoulder", CFrame.Angles(R(40), 0, R(-25)))
		set("LeftShoulder", CFrame.Angles(R(40), 0, R(25)))
	elseif name == "walk" then
		local s = math.sin(t * 9)
		set("RightHip", CFrame.Angles(R(35 * s), 0, 0))
		set("LeftHip", CFrame.Angles(R(-35 * s), 0, 0))
		set("RightShoulder", CFrame.Angles(R(-25 * s), 0, 0))
		set("LeftShoulder", CFrame.Angles(R(25 * s), 0, 0))
		set("Neck", CFrame.Angles(R(10), 0, 0))
	elseif name == "kick" then
		set("RightHip", CFrame.Angles(R(80), 0, 0))
		set("Waist", CFrame.Angles(R(-15), 0, 0))
		set("RightShoulder", CFrame.Angles(0, 0, R(-40)))
		set("LeftShoulder", CFrame.Angles(0, 0, R(40)))
	elseif name == "fly" then
		set("RightShoulder", CFrame.Angles(0, 0, R(-110)))
		set("LeftShoulder", CFrame.Angles(0, 0, R(110)))
		set("RightHip", CFrame.Angles(0, 0, R(-30)))
		set("LeftHip", CFrame.Angles(0, 0, R(30)))
	elseif name == "lie" then
		set("RightShoulder", CFrame.Angles(0, 0, R(-60)))
		set("LeftShoulder", CFrame.Angles(0, 0, R(60)))
	elseif name == "sit" then
		set("RightHip", CFrame.Angles(R(80), 0, 0))
		set("LeftHip", CFrame.Angles(R(80), 0, 0))
	elseif name == "cheer" then
		local b = math.sin(t * 8) * 10
		set("RightShoulder", CFrame.Angles(R(170), 0, R(-15 + b)))
		set("LeftShoulder", CFrame.Angles(R(170), 0, R(15 - b)))
	elseif name == "holdChart" then
		set("RightShoulder", CFrame.Angles(R(165), 0, 0))
		set("LeftShoulder", CFrame.Angles(R(165), 0, 0))
	elseif name == "throw" then
		local s = math.sin(t * 16)
		set("RightShoulder", CFrame.Angles(R(110 + 50 * s), 0, 0))
		set("LeftShoulder", CFrame.Angles(R(110 - 50 * s), 0, 0))
	end
end

-- 25 Oct (Luke: "the emotive animations are very static"): the body moves by keyframed CLIPS
-- (BobClips, the shot list's clips as data). A clip starts when it first appears and runs on
-- through looks that share it (the vow is one 4.2 s take across "stand" and "gesture").
local function clipFor(scene, id, pose, t)
	if id == "hero" then
		if pose == "gesture" then return (scene == "intro" and t >= 12) and "hero_vow" or "hero_ask" end
		if pose == "stand" then
			if scene == "intro" and t >= 3.4 and t < 6.3 then return "hero_hurt" end
			if scene == "intro" and t >= 12 then return "hero_vow" end
			return "hero_idle"
		end
		return ({ fly = "hero_fly", lie = "hero_land", sit = "hero_situp", getup = "hero_getup", kick = "hero_kick", holdChart = "hero_ipad",
			cheer = "hero_cheer", walk = scene == "intro" and "hero_sadwalk" or "hero_strut" })[pose]
	elseif id == "bob" then
		if pose == "stand" then return scene == "payoff" and "bob_shock" or "bob_smug" end
		return ({ annoyed = "bob_smug", laugh = "bob_laugh", laughdie = "bob_laughdie", shock = "bob_shock", kick = "bob_kick",
			throw = "bob_throw", fly = "bob_fly", lie = "bob_dizzy", sit = "bob_dizzy" })[pose]
	end
	return ({ laugh = "inv_laugh", laughdie = "inv_laughdie", shock = "inv_shock" })[pose] or "inv_idle"
end

-- feet at pos (anchor space); rot 0 faces the camera (+Z), 90 faces +X; roll spins round Z
-- live 25 Oct (Luke: "phasing through the floor"): an anchor's height is not the floor's (the
-- garage floor sits above the lot), so each actor stands on the real floor under its feet
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function floorAt(world, ignore)
	local skip = table.clone(ignore)
	for _ = 1, 5 do
		rayParams.FilterDescendantsInstances = skip
		local hit = workspace:Raycast(world + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0), rayParams)
		if not hit then return nil end
		if hit.Position.Y <= world.Y + 1.2 then return hit.Position.Y end
		table.insert(skip, hit.Instance)   -- a desk, a table, a chair: not the floor
	end
	return nil
end
-- the lowest visible point of the body, relative to the root (last frame's pose: a joint's
-- Transform reaches its parts on the next step, so this lags one frame)
local function lowestBelowRoot(a)
	local low
	for _, p in ipairs(a.model:GetDescendants()) do
		if p:IsA("BasePart") and p ~= a.root and p.Transparency < 1 then
			local cf, h = p.CFrame, p.Size / 2
			local y = cf.Y - math.abs(cf.RightVector.Y) * h.X - math.abs(cf.UpVector.Y) * h.Y - math.abs(cf.LookVector.Y) * h.Z
			if not low or y < low then low = y end
		end
	end
	return low and low - a.root.Position.Y
end

local function place(a, anchorCF, pos, rot, roll, ignore)
	if not (a.root and anchorCF) then return end
	-- live 25 Oct: lying flat or sitting, an actor floated at standing height (2.4 studs over the
	-- street). On the ground, the body's lowest point goes on the floor, whatever the pose; in the
	-- air (pos.Y > 0), it blends from standing height to half a torso as it rolls flat
	local stand = (a.hum and a.hum.HipHeight or 2) + a.root.Size.Y / 2
	local torso = a.model:FindFirstChild("UpperTorso") or a.model:FindFirstChild("Torso")
	local lie = torso and torso.Size.Z / 2 + 0.1 or 0.6
	local lift = stand + (lie - stand) * math.abs(math.sin(R(roll or 0)))
	-- the last 0.6 studs of a fall blend the air's height into the ground's (lowest point on the floor),
	-- so a landing has no step (live 26 Oct: the two met 1 stud apart, a drop in one frame on impact)
	if pos.Y < 0.6 then
		local rel = lowestBelowRoot(a)
		if rel and rel < 0 then
			local w = math.clamp(pos.Y / 0.6, 0, 1)
			lift = -rel * (1 - w) + lift * w
		end
	end
	local at = (anchorCF * CFrame.new(pos.X, 0, pos.Z)).Position
	local floor = floorAt(at, ignore or {}) or at.Y
	local target = CFrame.new(at.X, floor + pos.Y + lift, at.Z) * anchorCF.Rotation * CFrame.Angles(0, 0, R(roll or 0))
		* CFrame.Angles(0, R(180 + (rot or 0)), 0)
	if (target.Position - a.root.Position).Magnitude > 5 then
		-- a jump (the first frame, a cut to another set): the limbs follow the root one physics step
		-- late, so for a frame the body was missing (live 25 Oct: Bob's tie floated alone). Move it all.
		a.model:PivotTo(target * a.root.CFrame:ToObjectSpace(a.model:GetPivot()))
	else
		a.root.CFrame = target
	end
end

local function setVisible(a, on)
	for _, d in ipairs(a.model:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = on and 0 or 1 end
	end
	for _, d in ipairs(a.model:GetDescendants()) do
		if d:IsA("SurfaceGui") or d:IsA("BillboardGui") then d.Enabled = on end
	end
end

-- ------------------------------------------------------------------ GUI
--[[ Speech (25 Oct, Luke's second review: the bubbles "don't fit the scene ... sans serif, sloppish").
	A comic speech bubble: Bangers lettering in capitals, a heavy ink outline, a hard ink shadow, and
	a tail that points at whoever is talking. A word the script shouts (written in capitals: YOU,
	AGAIN, TAKE IT ALL) is set in red. A bubble is 2D, placed over the speaker's head each frame and
	kept inside the frame; with no room above the head it sits beside it, tail pointing across. ]]
local function comicText(s)
	local out = {}
	for word in s:gmatch("%S+") do
		local letters = (word:gsub("[^%a]", ""))
		local w = (word:upper():gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
		if #letters >= 2 and letters == letters:upper() then w = ('<font color="#%s">%s</font>'):format(UIKit.RED:ToHex(), w) end
		table.insert(out, w)
	end
	return table.concat(out, " ")
end

local TAIL = 26   -- the tail is a turned square half under the card

-- a line's size in pixels at full scale, measured once and kept. (live 25 Oct: read off the label,
-- TextBounds includes the pop-in's UIScale, so on its first frame a bubble measured almost nothing
-- and locked itself tiny, the words spilling out)
local measured = {}
local function measure(text)
	if measured[text] then return measured[text] end
	local p = Instance.new("GetTextBoundsParams")
	p.Text = text:upper()
	p.Font = UIKit.COMIC
	p.Size = UIKit.TYPE.display
	p.Width = 4000
	local ok, v = pcall(TextService.GetTextBoundsAsync, TextService, p)
	measured[text] = ok and v or Vector2.new(#text * 17, UIKit.TYPE.display)
	return measured[text]
end
-- a bubble is drawn inside a CanvasGroup, so it fades as ONE picture. (live 25 Oct: fading each piece
-- on its own let them show through each other half-way: the ink shadow greyed the card and the tail
-- showed as a doubled diamond.) A CanvasGroup clips to its bounds, so it is padded round the card
-- for the tail and the shadow
local PAD = 32
local function bubbleFor(a)
	local group = Instance.new("CanvasGroup")
	group.Name = "Bubble"
	group.BackgroundTransparency = 1
	group.Visible = false
	local box = Instance.new("Frame")
	box.Name = "Card"
	box.BackgroundTransparency = 1
	box.Position = UDim2.fromOffset(PAD, PAD)
	box.Size = UDim2.fromOffset(200, 60)
	box.Parent = group
	local shadow = Instance.new("Frame")
	shadow.BackgroundColor3 = INK
	shadow.BorderSizePixel = 0
	shadow.Position, shadow.Size = UDim2.fromOffset(5, 6), UDim2.fromScale(1, 1)
	shadow.ZIndex = 6
	Instance.new("UICorner", shadow).CornerRadius = UDim.new(0, UIKit.RADIUS.xl)
	shadow.Parent = box
	local card = Instance.new("TextLabel")
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = PAPER
	card.TextColor3 = INK
	card.FontFace = UIKit.COMIC
	card.TextSize = UIKit.TYPE.display
	card.RichText = true
	card.ZIndex = 8
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, UIKit.RADIUS.xl)
	local s = Instance.new("UIStroke"); s.Thickness = 4; s.Color = INK; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = card
	card.Parent = box
	local tail = Instance.new("Frame")
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Size = UDim2.fromOffset(TAIL, TAIL)
	tail.Rotation = 45
	tail.BackgroundColor3 = PAPER
	tail.BorderSizePixel = 0
	tail.ZIndex = 7
	local ts = Instance.new("UIStroke"); ts.Thickness = 4; ts.Color = INK; ts.Parent = tail
	tail.Parent = box
	-- paper over the card's outline where the tail joins, so the tail opens into the bubble
	local patch = Instance.new("Frame")
	patch.AnchorPoint = Vector2.new(0.5, 0.5)
	patch.BackgroundColor3 = PAPER
	patch.BorderSizePixel = 0
	patch.ZIndex = 9
	patch.Parent = box
	local sc = Instance.new("UIScale"); sc.Parent = group
	return { group = group, box = box, card = card, tail = tail, patch = patch, scale = sc, head = a.head }
end

-- a clamp for screen positions that never errors: when the room is smaller than the thing (a
-- bubble's first frame, before its text is measured; a tiny window) it centres it instead
-- (the doctor, 25 Oct: math.clamp errored with max < min)
local function fit(v, lo, hi)
	if hi < lo then return (lo + hi) / 2 end
	return math.clamp(v, lo, hi)
end

-- where a bubble goes this frame, in viewport pixels (the scene's gui ignores the inset):
-- x, y = the bubble's bottom centre; side = nil above the head, 1 right of it, -1 left of it;
-- hx, hy = the head on screen, for the tail
local SKIP_ZONE = 150   -- the SKIP button's corner, top right
local function bubbleAt(cam, head, w, h)
	local vp = cam.ViewportSize
	local top = cam:WorldToViewportPoint(head.Position + Vector3.new(0, head.Size.Y / 2 + 0.5, 0))
	local mid, onScreen = cam:WorldToViewportPoint(head.Position)
	-- (live 25 Oct: a speaker off the frame got their bubble pinned to its edge, as if someone else spoke)
	if top.Z <= 0 or not onScreen then return nil end
	local safeTop, safeBot, edge = vp.Y * 0.1 + 12, vp.Y * 0.9 - 12, 16
	local x, y, side = top.X, top.Y - 6, nil
	if y - h < safeTop then
		-- no room above the head: beside it, on the side with more room
		local r = math.max(mid.Y - top.Y, 20)
		side = mid.X < vp.X / 2 and 1 or -1
		x = mid.X + side * (r + 24 + w / 2)
		y = math.max(mid.Y + h / 2, safeTop + h)
	end
	local right = (y - h < SKIP_ZONE * 0.6) and vp.X - SKIP_ZONE or vp.X - edge
	x = fit(x, edge + w / 2, right - w / 2)
	y = fit(y, safeTop + h, safeBot)
	return x, y, side, mid.X, mid.Y
end

-- lay a bubble out. Luke 25 Oct: "the text boxes keep glitching around when they're talking": placed
-- fresh every frame, a bubble chased a head that bobs while it laughs and talks. Now it is placed ONCE,
-- when its words have been measured, and holds still until the line ends or the shot cuts
local function placeBubble(cam, bb, shot)
	if bb.lockText ~= bb.text or bb.lockShot ~= shot then bb.lock = nil end
	if not bb.lock then
		local size = measured[bb.text]
		if not size then bb.group.Visible = false return end   -- still being measured: next frame
		local w = size.X + 46
		local h = math.max(60, size.Y + 24)
		local x, y, side, hx, hy = bubbleAt(cam, bb.head, w, h + 18)
		if not x then bb.group.Visible = false return end
		bb.lock = { x = x, y = y, side = side, hx = hx, hy = hy, w = w, h = h }
		bb.lockText, bb.lockShot = bb.text, shot
	end
	local L = bb.lock
	local x, y, side, hx, hy, w, h = L.x, L.y, L.side, L.hx, L.hy, L.w, L.h
	bb.group.Visible = true
	bb.group.Size = UDim2.fromOffset(w + 2 * PAD, h + 2 * PAD)
	bb.box.Size = UDim2.fromOffset(w, h)
	if side == nil then
		-- above the head: the tail hangs from the bottom edge toward the head. The box is anchored
		-- where the tail joins it, so the pop grows out of the tail, from the speaker
		local tx = fit(hx - x, -w / 2 + 30, w / 2 - 30)
		bb.group.AnchorPoint = Vector2.new((PAD + w / 2 + tx) / (w + 2 * PAD), (PAD + h) / (h + 2 * PAD))
		bb.group.Position = UDim2.fromOffset(x + tx, y - 16)
		bb.tail.Position = UDim2.new(0.5, tx, 1, 1)
		bb.patch.Size, bb.patch.Position = UDim2.fromOffset(TAIL + 8, 10), UDim2.new(0.5, tx, 1, -4)
	else
		-- beside the head: the tail sticks out of the side that faces it (and the pop grows from there)
		local ty = fit(hy - (y - h / 2), -h / 2 + 18, h / 2 - 18)
		local edgeX = side == 1 and 0 or 1
		bb.group.AnchorPoint = Vector2.new((PAD + edgeX * w) / (w + 2 * PAD), (PAD + h / 2 + ty) / (h + 2 * PAD))
		bb.group.Position = UDim2.fromOffset(x - w / 2 + edgeX * w, y - h / 2 + ty)
		bb.tail.Position = UDim2.new(edgeX, side == 1 and -1 or 1, 0.5, ty)
		bb.patch.Size, bb.patch.Position = UDim2.fromOffset(10, TAIL + 8), UDim2.new(edgeX, side == 1 and 4 or -4, 0.5, ty)
	end
end

--[[ A sound effect (BOING!), Luke 25 Oct: "it just looks like you put text on it". A comic impact: a
	jagged gold starburst with an ink edge (squares turned round one centre), the word in Luckiest Guy
	with a hard ink drop, and a springy wobble as it lands. Drawn in 2D at its point in the world. ]]
local function burstFor(text)
	local box = Instance.new("Frame")
	box.Name = "Burst"
	box.BackgroundTransparency = 1
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Size = UDim2.fromOffset(280, 200)
	box.Visible = false
	-- pointed spikes round a solid oval: each spike is a square turned so a corner points outward,
	-- big and small in turn (rectangles gave square teeth: a gear, live 25 Oct). Ink first, a little
	-- bigger, so it edges the gold
	for layer, colour in ipairs({ INK, UIKit.GOLD }) do
		local grow = layer == 1 and 12 or 0
		for k = 0, 13 do
			local a = math.rad(k * 360 / 14 + 7)
			local spike = Instance.new("Frame")
			spike.AnchorPoint = Vector2.new(0.5, 0.5)
			spike.Position = UDim2.new(0.5, math.cos(a) * 100, 0.5, math.sin(a) * 60)
			local px = (k % 2 == 0 and 66 or 46) + grow
			spike.Size = UDim2.fromOffset(px, px)
			spike.Rotation = math.deg(a) + 45
			spike.BackgroundColor3 = colour
			spike.BorderSizePixel = 0
			spike.ZIndex = 3 + layer
			spike.Parent = box
		end
		local core = Instance.new("Frame")
		core.AnchorPoint = Vector2.new(0.5, 0.5)
		core.Position = UDim2.fromScale(0.5, 0.5)
		core.Size = UDim2.fromOffset(196 + grow, 116 + grow)
		core.BackgroundColor3 = colour
		core.BorderSizePixel = 0
		core.ZIndex = 3 + layer
		Instance.new("UICorner", core).CornerRadius = UDim.new(1, 0)
		core.Parent = box
	end
	local function word(colour, dx, dy, z)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Position = UDim2.new(0.5, dx, 0.5, dy)
		t.Size = UDim2.fromScale(1, 1)
		t.FontFace = UIKit.IMPACT
		t.TextSize = UIKit.TYPE.money
		t.Text = text
		t.TextColor3 = colour
		t.Rotation = -8
		t.ZIndex = z
		local st = Instance.new("UIStroke"); st.Thickness = 4; st.Color = INK; st.Parent = t
		t.Parent = box
	end
	word(INK, 4, 5, 6)
	word(UIKit.RED, 0, 0, 7)
	local sc = Instance.new("UIScale"); sc.Parent = box
	return { box = box, scale = sc, burst = true }
end

--[[ The walk home (Luke 25 Oct: "those cartoons where there's a rain cloud over them"; three grey
	balls "looked like his balls"). A comic cloud like the bubbles: overlapping round puffs on a flat
	base, ink-edged, slate grey, with blue drops falling out of it onto your head. A billboard sized in
	studs, so it is cloud-sized at any distance. ]]
local function rainCloud(parent)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Transparency = true, false, false, false, 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Parent = parent
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(4.4, 3.4)   -- studs
	bb.LightInfluence = 0
	bb.Adornee = p
	bb.Enabled = false
	local box = Instance.new("Frame")
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromScale(1, 1)
	box.Parent = bb
	local sc = Instance.new("UIScale"); sc.Parent = box
	-- the puffs: { x, y, size } in the box (centre, fraction of its width); the base fills under them
	local puffs = { { 0.24, 0.3, 0.3 }, { 0.43, 0.2, 0.38 }, { 0.63, 0.24, 0.34 }, { 0.79, 0.33, 0.24 } }
	for layer, colour in ipairs({ INK, UIKit.SLATE }) do
		local grow = layer == 1 and 0.04 or 0
		for _, q in ipairs(puffs) do
			local c = Instance.new("Frame")
			c.AnchorPoint = Vector2.new(0.5, 0.5)
			c.Position = UDim2.fromScale(q[1], q[2])
			c.Size = UDim2.fromScale(q[3] + grow, (q[3] + grow) * 4.4 / 3.4)
			c.BackgroundColor3 = colour
			c.BorderSizePixel = 0
			c.ZIndex = layer
			Instance.new("UICorner", c).CornerRadius = UDim.new(1, 0)
			c.Parent = box
		end
		local base = Instance.new("Frame")
		base.AnchorPoint = Vector2.new(0.5, 0.5)
		base.Position = UDim2.fromScale(0.51, 0.38)
		base.Size = UDim2.fromScale(0.74 + grow, 0.16 + grow)
		base.BackgroundColor3 = colour
		base.BorderSizePixel = 0
		base.ZIndex = layer
		Instance.new("UICorner", base).CornerRadius = UDim.new(1, 0)
		base.Parent = box
	end
	local drops = {}
	for k = 1, 8 do
		local d = Instance.new("Frame")
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Size = UDim2.fromScale(0.035, 0.1)
		d.Rotation = 12
		d.BackgroundColor3 = UIKit.BLUE
		d.BorderSizePixel = 0
		d.ZIndex = 0
		Instance.new("UICorner", d).CornerRadius = UDim.new(1, 0)
		d.Parent = box
		drops[k] = d
	end
	bb.Parent = p
	return { part = p, gui = bb, scale = sc, drops = drops }
end

-- dizzy: little gold stars circling the head (in the world, so the head hides them as they pass behind)
local function starsFor(parent)
	local s = { stars = {} }
	for k = 1, 4 do
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Transparency = true, false, false, false, 1
		p.Size = Vector3.new(0.2, 0.2, 0.2)
		p.Parent = parent
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(56, 56)
		bb.LightInfluence = 0
		bb.Adornee = p
		bb.Enabled = false
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.FontFace = UIKit.IMPACT
		t.TextScaled = true
		t.Text = "\u{2605}"
		t.TextColor3 = UIKit.GOLD
		local st = Instance.new("UIStroke"); st.Thickness = 3; st.Color = INK; st.Parent = t
		t.Parent = bb
		bb.Parent = p
		s.stars[k] = { part = p, gui = bb }
	end
	return s
end

-- ------------------------------------------------------------------ one scene
local function play(name, info)
	if playing then return false end
	-- the kill switch (Flags.bobScenes, docs/ROLLBACK.md): no scene. "failed" sends the intro back to
	-- IntroClient's flyover; the payoff's money is already paid by the server, so say so
	if RS:GetAttribute("Flag_bobScenes") == false then
		if name == "payoff" and type(info) == "table" and tonumber(info.amount) then
			pcall(function()
				require(RS:WaitForChild("Notify")).toast(("Bob paid you %s · %s"):format(UIKit.money(tonumber(info.amount)), BobScript.LINES.toast))
			end)
		end
		player:SetAttribute("BobSceneState", "failed")
		return false
	end
	player:SetAttribute("BobSceneState", "loading")
	local A, bc = anchors()
	-- review I-3: build every actor BEFORE the scene takes the screen, so there is never a moment
	-- with the HUD gone and no SKIP, and a missing cast fails before anything has changed
	local cast = A and RS:WaitForChild("BobCast", 10)
	if not (A and cast) then
		warn("[Bob] no Bob Capital or BobCast in the world: scene skipped")
		player:SetAttribute("BobSceneState", "failed")
		return false
	end
	playing = true
	-- live 25 Oct: on a fresh join the AI meshes were not loaded yet, so for the first frames only Bob's
	-- tie and toothpick showed. Load the cast while still "loading" (at most 4 s; IntroClient waits 15)
	-- The scene's sounds too, as a BANK: one Sound per cue and per loop, made and loaded now and only
	-- played on cue. (live 25 Oct: a Sound made at its cue was still loading 0.12 s later, its playhead
	-- frozen, so nearly every sound came in late or not at all; only a repeat of one already heard
	-- played on time. Preloading the asset URL is not enough: each new Sound loads again)
	local bank = Instance.new("Folder")
	bank.Name = "BobSceneSounds"
	local cueSound, bedSound = {}, {}
	local function bankSound(id)
		local info = SOUND[id]
		local url = info and Sfx.url(info[1])
		if not url then return nil end
		local s = Instance.new("Sound")
		s.Name = id
		s.SoundId = url
		s.Volume = 0
		s.Parent = bank
		return s
	end
	for _, c in ipairs(BobScript.cues(name, -1, BobScript.length(name))) do
		cueSound[("%.3f|%s"):format(c.t, c.id)] = bankSound(c.id)
	end
	for i, b in ipairs(BobScript.beds(name)) do bedSound[i] = bankSound(b[1]) end
	bank.Parent = game:GetService("SoundService")
	local loaded = false
	task.spawn(function()
		local list = { cast }
		for _, s in ipairs(bank:GetChildren()) do table.insert(list, s) end
		pcall(function() game:GetService("ContentProvider"):PreloadAsync(list) end)
		loaded = true
	end)
	for _, b in ipairs(BobScript.at(name, 0, true).bubbles) do task.spawn(measure, b.text) end   -- every line's size, up front
	local tLoad = os.clock()
	local function allLoaded()
		for _, s in ipairs(bank:GetChildren()) do if not s.IsLoaded then return false end end
		return true
	end
	while not (loaded and allLoaded()) and os.clock() - tLoad < 6 do task.wait() end
	local folder = Instance.new("Folder")
	folder.Name = "BobScene"
	local actors = {}
	local function add(id, model)
		if not model then return end
		model.Parent = folder
		actors[id] = prep(model, id)
	end
	add("bob", cast and cast:FindFirstChild("Bob") and cast.Bob:Clone())
	add("inv1", cast and cast:FindFirstChild("Inv1") and cast.Inv1:Clone())
	add("inv2", cast and cast:FindFirstChild("Inv2") and cast.Inv2:Clone())
	add("hero", heroModel())
	local bubbles = {}
	for id, a in pairs(actors) do bubbles[id] = bubbleFor(a) end

	-- everything the scene changes, so finish() -- or a failure anywhere below -- puts it all back
	local restore, hidden, controls, gui, conn = {}, {}, nil, nil, nil
	local door, tape, front = bc:FindFirstChild("Door"), bc:FindFirstChild("Tape"), bc:FindFirstChild("FrontWall")
	local doorCF = door and door.CFrame
	local knob = bc:FindFirstChild("Knob")
	local knobRel = knob and doorCF and doorCF:ToObjectSpace(knob.CFrame)
	local char = player.Character
	local cam = workspace.CurrentCamera
	local fov0 = cam.FieldOfView
	local listeners = {}   -- input/attribute hooks: putBack drops them even when setup fails (review round 1)
	local function putBack()
		if conn then conn:Disconnect() end
		for _, c in ipairs(listeners) do c:Disconnect() end
		-- sounds still ringing (the victory sting, the street) fade out over the game instead of
		-- stopping dead with the scene (25 Oct: the sting was cut off at 20.0 s)
		for _, s in ipairs(bank:GetChildren()) do
			if s.IsPlaying and s.Volume > 0 then
				s.Parent = game:GetService("SoundService")
				fadeOut(s, 0.9)
				game:GetService("Debris"):AddItem(s, 1.2)
			end
		end
		bank:Destroy()
		folder:Destroy()
		for inst, props in pairs(restore) do
			for prop, v in pairs(props) do pcall(function() inst[prop] = v end) end
		end
		if door and doorCF then door.CFrame = doorCF end
		cam.CameraType = Enum.CameraType.Custom
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then cam.CameraSubject = hum end
		cam.FieldOfView = fov0
		if controls then controls:Enable() end
		for _, g in ipairs(hidden) do if g.Parent then g.Enabled = true end end
		player:SetAttribute("BobScenePlaying", false)
		playing = false
	end

	local okRun, result = pcall(function()
	player:SetAttribute("BobScenePlaying", true)
	player:SetAttribute("BobSceneState", "playing")
	folder.Parent = workspace
	local remotes = RS:FindFirstChild("SVRemotes")
	local tele = remotes and remotes:FindFirstChild("BobIntro")
	if name == "intro" and tele then tele:FireServer("start") end
	local function override(inst, prop, value)
		if not inst then return end
		if restore[inst] == nil then restore[inst] = {} end
		if restore[inst][prop] == nil then restore[inst][prop] = inst[prop] end
		inst[prop] = value
	end
	if char then
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Decal") then override(d, "LocalTransparencyModifier", 1) end
		end
	end
	-- the HUD steps aside (a cutscene owns the screen); the chosen ScreenGuis come back after
	for _, g in ipairs(player.PlayerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled and g.Name ~= "BobSceneGui" then g.Enabled = false; table.insert(hidden, g) end
	end
	pcall(function()
		local pm = player.PlayerScripts:FindFirstChild("PlayerModule")
		controls = pm and require(pm):GetControls()
	end)
	if controls then controls:Disable() end
	local myRoot = char and char:FindFirstChild("HumanoidRootPart")
	if myRoot then override(myRoot, "Anchored", true) end

	-- letterbox, SKIP, the money counter
	gui = Instance.new("ScreenGui")
	gui.Name = "BobSceneGui"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30
	gui.ResetOnSpawn = false
	gui.Parent = player.PlayerGui
	local function bar(top)
		local f = Instance.new("Frame")
		f.BackgroundColor3 = INK
		f.BorderSizePixel = 0
		f.Size = UDim2.new(1, 0, 0.1, 0)
		f.AnchorPoint = Vector2.new(0, top and 0 or 1)
		f.Position = UDim2.fromScale(0, top and 0 or 1)
		f.Parent = gui
		return f
	end
	local barT, barB = bar(true), bar(false)
	for _, bb in pairs(bubbles) do bb.group.Parent = gui end
	-- in from black (0.5 s): covers the first frames, when the cast's textures are still arriving
	-- (live 25 Oct: grey heads for about 0.15 s on a fresh join)
	local fadeIn = Instance.new("Frame")
	fadeIn.BackgroundColor3 = INK
	fadeIn.BorderSizePixel = 0
	fadeIn.Size = UDim2.fromScale(1, 1)
	fadeIn.ZIndex = 20
	fadeIn.Parent = gui
	local skipped = false
	local skip = UIKit.button(gui, "SKIP", PAPER, {
		Name = "Skip", AnchorPoint = Vector2.new(1, isTouch and 1 or 0),
		Position = isTouch and UDim2.new(1, -24, 1, -150) or UDim2.new(1, -24, 0, 24),
		Size = UDim2.new(0, 104, 0, 48), ZIndex = 8,
	}, { textSize = 18, dark = true })
	skip.MouseButton1Click:Connect(function() skipped = true end)
	-- the doctor's hand on the SKIP button (DoctorProbes.bobscene): it can only skip your own scene
	local c0 = player:GetAttributeChangedSignal("BobSkipNow"):Connect(function()
		if player:GetAttribute("BobSkipNow") == true then skipped = true end
	end)
	local tapAt, tapPos
	local padFrom = os.clock() + 0.5
	local c1 = UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then tapAt, tapPos = os.clock(), input.Position end
		-- B is also the chase sprint: a press already on its way as the scene opens does not count
		if input.UserInputType.Name:find("^Gamepad") and BobScript.skipsOn(input.KeyCode.Name) and os.clock() >= padFrom then skipped = true end
	end)
	-- the B glyph beside SKIP, only while a gamepad is what you last touched
	local padGlyph = Instance.new("ImageLabel")
	padGlyph.Name = "PadB"
	padGlyph.BackgroundTransparency = 1
	padGlyph.AnchorPoint = Vector2.new(1, 0.5)
	padGlyph.Position = UDim2.new(0, -8, 0.5, 0)
	padGlyph.Size = UDim2.fromOffset(32, 32)
	pcall(function() padGlyph.Image = UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonB) end)
	padGlyph.Parent = skip
	local function showGlyph()
		padGlyph.Visible = UserInputService:GetLastInputType().Name:find("^Gamepad") ~= nil and padGlyph.Image ~= ""
	end
	showGlyph()
	local c3 = UserInputService.LastInputTypeChanged:Connect(showGlyph)
	local c2 = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch or not tapAt then return end
		if os.clock() - tapAt < 0.4 and (input.Position - tapPos).Magnitude < 12 then skipped = true end
		tapAt = nil
	end)
	table.insert(listeners, c0); table.insert(listeners, c1); table.insert(listeners, c2); table.insert(listeners, c3)
	local money
	if name == "payoff" then
		money = Instance.new("TextLabel")
		money.BackgroundTransparency = 1
		money.AnchorPoint = Vector2.new(0, 1)
		money.Position = UDim2.new(0, 24, 0.88, 0)
		money.Size = UDim2.fromOffset(420, 48)
		money.Font = UIKit.HEAD
		money.TextSize = UIKit.TYPE.display
		money.TextXAlignment = Enum.TextXAlignment.Left
		money.TextColor3 = UIKit.MONEY
		local st = Instance.new("UIStroke"); st.Thickness = 2; st.Color = INK; st.Parent = money
		money.Visible = false
		money.Parent = gui
	end

	-- props: the chart, bills, the rain cloud / dizzy stars, BOING / x3 / PROVED WRONG
	local chart = cast and cast:FindFirstChild("Chart") and cast.Chart:Clone()
	if chart then chart.Parent = folder; chart.Transparency = 1 end
	-- Luke 25 Oct: "an iPad that I pull out from behind my back" (the paper board was "super bright").
	-- A dark screen: REVENUE, a green line that shoots up, and the number counting up with it
	local chartLine, chartNum = {}, nil
	if chart and chart:FindFirstChild("ChartGui") then
		local g = chart.ChartGui
		local W, H = chart.Size.X * g.PixelsPerStud, chart.Size.Y * g.PixelsPerStud
		local screen = Instance.new("Frame")
		screen.BorderSizePixel = 0
		screen.BackgroundColor3 = Color3.fromRGB(15, 21, 36)   -- world colour (the screen)
		screen.Position, screen.Size = UDim2.fromScale(0.05, 0.07), UDim2.fromScale(0.9, 0.86)
		local sr = Instance.new("UICorner"); sr.CornerRadius = UDim.new(0.04, 0); sr.Parent = screen
		screen.Parent = g
		for k = 1, 3 do
			local grid = Instance.new("Frame")
			grid.BorderSizePixel = 0
			grid.BackgroundColor3 = Color3.fromRGB(38, 48, 72)   -- world colour (grid line)
			grid.Position, grid.Size = UDim2.fromScale(0.06, 0.32 + k * 0.17), UDim2.new(0.88, 0, 0, 2)
			grid.Parent = screen
		end
		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Position, title.Size = UDim2.fromScale(0.12, 0.1), UDim2.fromScale(0.5, 0.13)   -- clear of the holding hand
		title.Font = UIKit.HEAD; title.TextScaled = true; title.TextXAlignment = Enum.TextXAlignment.Left
		title.Text = "REVENUE"; title.TextColor3 = Color3.fromRGB(148, 163, 184)   -- world colour (muted label)
		title.Parent = screen
		chartNum = Instance.new("TextLabel")
		chartNum.BackgroundTransparency = 1
		chartNum.Position, chartNum.Size = UDim2.fromScale(0.12, 0.22), UDim2.fromScale(0.6, 0.19)
		chartNum.Font = UIKit.HEAD; chartNum.TextScaled = true; chartNum.TextXAlignment = Enum.TextXAlignment.Left
		chartNum.TextColor3 = Color3.fromRGB(74, 222, 128)   -- world colour (money up)
		chartNum.Text = "+0%"
		chartNum.Parent = screen
		local pts = { { 0.06, 0.9 }, { 0.2, 0.87 }, { 0.34, 0.84 }, { 0.48, 0.78 }, { 0.62, 0.72 }, { 0.74, 0.6 }, { 0.84, 0.44 }, { 0.94, 0.26 } }
		local sw, sh = W * 0.9, H * 0.86
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundColor3 = Color3.fromRGB(34, 197, 94)   -- world colour (the line)
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			local dx, dy = (b[1] - a[1]) * sw, (b[2] - a[2]) * sh
			f.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + 3, 6)
			f.Position = UDim2.fromScale((a[1] + b[1]) / 2, (a[2] + b[2]) / 2)
			f.Rotation = math.deg(math.atan2(dy, dx))
			f.Visible = false
			f.Parent = screen
			chartLine[i] = f
		end
	end
	local bills = {}
	if name == "payoff" then
		for i = 1, 18 do
			local p = Instance.new("Part")
			p.Name = "Bill"
			p.Size = Vector3.new(0.9, 0.05, 0.5)
			p.Color = Color3.fromRGB(91, 227, 142)   -- world colour
			p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Transparency = true, false, false, false, 1
			p.Parent = folder
			bills[i] = p
		end
	end
	local cloud = rainCloud(folder)
	-- the scene's loops and music: each starts (from its `at`) when its span does, at the level
	-- BobScript.bedLevel gives (faded, ducked under talking), times its loudness trim
	local beds = {}
	for i, b in ipairs(BobScript.beds(name)) do
		local s = bedSound[i]
		if s and not (b[1] == "music" and player:GetAttribute("MenuMuted") == true) then
			s.Looped = b[1] ~= "music"
			table.insert(beds, { sound = s, bed = b, info = SOUND[b[1]] })
		end
	end
	local fxs = {}
	local f0 = BobScript.at(name, 0, true)
	for i, x in ipairs(f0.fx) do
		if x.kind == "text" then fxs[i] = burstFor(x.text); fxs[i].box.Parent = gui end
		if x.kind == "stars" then fxs[i] = starsFor(folder) end
		if x.kind == "debris" then
			-- the door coming down: wood splinters and a puff of dust out of the doorway
			local d = { splinters = {} }
			for k = 1, 10 do
				d.splinters[k] = Instance.new("Part")
				d.splinters[k].Size = Vector3.new(0.18, 0.18, 0.5 + (k % 3) * 0.3)
				d.splinters[k].Color = Color3.fromRGB(110, 74, 48)   -- world colour (the door's wood)
				d.splinters[k].Material = Enum.Material.Wood
			end
			for _, p in ipairs(d.splinters) do
				p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Transparency, p.CastShadow = true, false, false, false, 1, false
				p.Parent = folder
			end
			-- live 25 Oct: dust as balls read as soap bubbles; a burst of Roblox's own smoke instead
			local holder = Instance.new("Part")
			holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch, holder.Transparency = true, false, false, false, 1
			holder.Size = Vector3.new(4, 0.2, 0.4)
			holder.Parent = folder
			local puff = Instance.new("ParticleEmitter")
			puff.Texture = "rbxasset://textures/particles/smoke_main.dds"
			puff.Color = ColorSequence.new(Color3.fromRGB(205, 196, 180))   -- world colour (plaster dust)
			puff.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
			puff.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 5) })
			puff.Lifetime = NumberRange.new(0.7, 1.2)
			puff.Speed = NumberRange.new(3, 8)
			puff.SpreadAngle = Vector2.new(70, 25)
			puff.Drag = 3
			puff.Rate = 0
			puff.LightInfluence = 0.6
			puff.EmissionDirection = Enum.NormalId.Front
			puff.Parent = holder
			d.holder, d.puff = holder, puff
			fxs[i] = d
		end
	end

	-- the camera owns the view until finish()
	cam.CameraType = Enum.CameraType.Scriptable

	local t0, lastT, finished = os.clock(), 0, false
	local lastShot = 1
	local gone = {}   -- bystanders already stepped out of the shot
	-- everyone with a Humanoid: one scan now, then only the ones that arrive (a full scan a second hitched)
	local people = {}
	for _, d in ipairs(workspace:GetDescendants()) do if d:IsA("Humanoid") then people[d] = true end end
	local cPeople = workspace.DescendantAdded:Connect(function(d) if d:IsA("Humanoid") then people[d] = true end end)
	table.insert(listeners, cPeople)
	local length = BobScript.length(name)

	local function finish(wasSkipped)
		if finished then return end
		finished = true
		c0:Disconnect(); c1:Disconnect(); c2:Disconnect(); c3:Disconnect(); cPeople:Disconnect()
		local endT = os.clock() - t0
		-- a skipped intro still ends where the story ends: you at your laptop
		if name == "intro" and char and char.PrimaryPart and A.garage then
			local hero = BobScript.at(name, length, true).actors.hero
			pcall(function() char:PivotTo(A.garage * CFrame.new(hero.pos + Vector3.new(0, 3, 0)) * CFrame.Angles(0, R(180 + hero.rot), 0)) end)
		end
		putBack()
		player:SetAttribute("BobSceneState", "done")
		if tele and name == "intro" then tele:FireServer(wasSkipped and ("skip:" .. math.floor(endT)) or "end") end
		if name == "payoff" and money then
			-- the toast lingers 3 s over the game, it blocks nothing
			barT:Destroy(); barB:Destroy(); skip:Destroy()
			money.Text = BobScript.LINES.toast
			money.Visible = true
			task.delay(3, function() gui:Destroy() end)
		else
			gui:Destroy()
		end
	end

	conn = RunService.RenderStepped:Connect(function()
		-- live 25 Oct: a client walking into the garage stood in front of the camera. Anyone else near
		-- the set (staff, clients, other players) steps out of the shot. Every frame, from the first:
		-- checked once a second, a worker at the garage desk showed for a moment, then vanished.
		-- And held every frame: the game's own scripts show staff again, so a one-off hide flickered
		do
			for _, list in pairs(gone) do
				for _, d in ipairs(list) do
					if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = 1 else d.Enabled = false end
				end
			end
			for mdl in pairs(people) do
				if mdl.Parent and not gone[mdl] and not mdl:IsDescendantOf(folder) then
					local who = mdl.Parent
					local root = who:FindFirstChild("HumanoidRootPart") or who.PrimaryPart
					local near = false
					if root then
						for _, a in pairs(A) do
							if (root.Position - a.Position).Magnitude < 45 then near = true break end
						end
					end
					if near then
						local list = {}
						for _, d in ipairs(who:GetDescendants()) do
							if d:IsA("BasePart") or d:IsA("Decal") then override(d, "LocalTransparencyModifier", 1); table.insert(list, d)
							elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then override(d, "Enabled", false); table.insert(list, d) end
						end
						gone[mdl] = list
					end
				end
			end
		end
		for _, g in ipairs(player.PlayerGui:GetChildren()) do
			if g:IsA("ScreenGui") and g.Enabled and g ~= gui and not table.find(hidden, g) then
				g.Enabled = false
				table.insert(hidden, g)
			end
		end
		local t = os.clock() - t0
		-- Studio only: hold the scene at one moment (BobSceneHold = seconds) so each shot can be screenshotted
		local hold = RunService:IsStudio() and player:GetAttribute("BobSceneHold")
		if type(hold) == "number" then t = math.clamp(hold, 0, length - 0.01); t0 = os.clock() - t end
		if skipped or t >= length then finish(skipped) return end
		local reduced = UIKit.reducedMotion()
		local f = BobScript.at(name, t, reduced)
		-- actors
		for id, a in pairs(actors) do
			local st = f.actors[id]
			if st then
				setVisible(a, st.visible)
				place(a, A[st.anchor], st.pos, st.rot, st.roll, { folder, char, bc:FindFirstChild("Dressing") })
				local clip = clipFor(name, id, st.pose, t)
				if clip ~= a.clip or (not clip and st.pose ~= a.lastPose) then
					local began = t
					if a.clip == nil and t > 0 then
						-- the first frame of a scene started part-way (BobSceneHold, for screenshots): the clip
						-- began when its pose did, not now (a held sit-up showed him standing straight)
						while began > 0 and clipFor(name, id, BobScript.at(name, began - 1 / 30, true).actors[id].pose, began - 1 / 30) == clip do
							began -= 1 / 30
						end
					end
					a.clip, a.clipStart, a.lastPose = clip, began, st.pose
					-- a change of pose inside a shot blends from where the joints were (live 25 Oct: every
					-- pose change was a one-frame snap, sitting to standing among them); on a cut it snaps
					a.blendFrom = f.shot == lastShot and a.last or nil
				end
				if clip and BobClips.has(clip) then
					for _, j in pairs(a.motors) do j.Transform = CFrame.new() end
					for joint, cf in pairs(BobClips.sample(clip, math.max(0, t - a.clipStart))) do
						local j = a.motors[joint]
						if j then j.Transform = cf end
					end
				else
					pose(a, st.pose, t)
				end
				local k = a.blendFrom and math.clamp((t - a.clipStart) / POSE_BLEND, 0, 1) or 1
				a.last = {}
				for joint, j in pairs(a.motors) do
					if k < 1 then
						local e = 1 - (1 - k) ^ 3   -- ease-out: it answers at once, then settles
						j.Transform = (a.blendFrom[joint] or CFrame.new()):Lerp(j.Transform, e)
					end
					a.last[joint] = j.Transform
				end
				a.face.set(st.face)
				if st.visible then BobFace.facing(a.model, cam.CFrame.Position) end
			end
		end
		-- Bob's sunglasses fly off and the toothpick drops (payoff)
		local bob = actors.bob
		if bob then
			local g, pk = f.vals.glasses or 0, f.vals.pick or 0
			local sg, tp = bob.model:FindFirstChild("Sunglasses"), bob.model:FindFirstChild("Toothpick")
			-- review I-7: anchoring a welded part drags Bob with it, so unweld each one as it moves
			if sg and g > 0 and sg:FindFirstChildOfClass("WeldConstraint") then sg:FindFirstChildOfClass("WeldConstraint"):Destroy() end
			if tp and pk > 0 and tp:FindFirstChildOfClass("WeldConstraint") then tp:FindFirstChildOfClass("WeldConstraint"):Destroy() end
			if sg and g > 0 and bob.head then sg.Anchored = true; sg.CFrame = bob.head.CFrame * CFrame.new(g * 1.2, 1 + g * 3, -0.7) * CFrame.Angles(0, 0, g * 1.2) end
			if tp and pk > 0 and bob.head then tp.Anchored = true; tp.CFrame = bob.head.CFrame * CFrame.new(0.4, -0.6 - pk * 2.6, -0.8) * CFrame.Angles(0, 0, pk * 3) end
		end
		-- bubbles (placed after the camera moves, below)
		for id, bb in pairs(bubbles) do
			bb.on = nil
			for _, b in ipairs(f.bubbles) do
				if b.actor == id and b.k > 0 then bb.on = b end
			end
			if bb.on then
				if bb.text ~= bb.on.text then
					bb.text = bb.on.text
					bb.card.Text = comicText(bb.on.text)
					if not measured[bb.text] then task.spawn(measure, bb.text) end
				end
				local look = bb.on.look
				bb.scale.Scale = look.scale
				bb.group.GroupTransparency = 1 - look.alpha
				bb.card.MaxVisibleGraphemes = look.reveal >= 1 and -1 or math.floor(#bb.text * look.reveal)
				bb.group.Rotation = look.shake
			else
				bb.group.Visible = false
				bb.lock = nil
			end
		end
		-- fx: words, the rain cloud over you, stars over Bob
		for i, x in ipairs(f.fx) do
			local fx = fxs[i]
			if x.kind == "cloud" then
				local hero = actors.hero
				local on = x.k > 0 and hero ~= nil and hero.head ~= nil
				cloud.gui.Enabled = on
				if on then
					local age = x.age or 0
					-- it hangs over your head and bobs, a beat behind you
					cloud.part.CFrame = CFrame.new(hero.head.Position + Vector3.new(0, 2.2 + math.sin(age * 3) * 0.1, 0))
					cloud.scale.Scale = x.k
					for k, d in ipairs(cloud.drops) do
						local fall = (age * 1.7 + k * 0.37) % 1
						d.Position = UDim2.fromScale(0.2 + ((k * 0.29) % 0.62), 0.52 + fall * 0.42)
						d.BackgroundTransparency = fall > 0.8 and (fall - 0.8) * 5 or 0
					end
				end
			elseif x.kind == "debris" and fx then
				local base = A[x.anchor] and A[x.anchor] * CFrame.new(x.pos)
				local age = x.age or 0
				local on = x.k > 0 and base ~= nil
				for k, p in ipairs(fx.splinters) do
					if on then
						-- out of the doorway toward us and up, then down to the pavement
						local dir = Vector3.new(math.cos(k * 2.4) * 0.9, 1.1 + (k % 4) * 0.25, 0.9 + math.sin(k * 1.7) * 0.4)
						local s = dir * 9 * age - Vector3.new(0, 30 * age * age, 0)
						local pos = base * CFrame.new(math.cos(k) * 1.4, 1 + (k % 5) * 1.2, 0)
						local at = pos.Position + base:VectorToWorldSpace(Vector3.new(s.X, 0, s.Z)) + Vector3.new(0, s.Y, 0)
						at = Vector3.new(at.X, math.max(at.Y, base.Position.Y + 0.1), at.Z)
						p.CFrame = CFrame.new(at) * CFrame.Angles(age * (6 + k), age * 4, k)
						p.Transparency = age > 0.7 and math.clamp((age - 0.7) / 0.25, 0, 1) or 0
					else
						p.Transparency = 1
					end
				end
				if on and not fx.puffed then
					-- out of the doorway toward the street (the holder's front faces +Z, out of the building)
					fx.holder.CFrame = base * CFrame.new(0, 0.6, 0.4) * CFrame.Angles(0, math.pi, 0)
					fx.puff:Emit(30)
					fx.puffed = true
				end
			elseif x.kind == "stars" and fx then
				local who = x.follow and actors[x.follow]
				local head = who and who.head
				for k, st in ipairs(fx.stars) do
					st.gui.Enabled = x.k > 0 and head ~= nil
					if head and x.k > 0 then
						local a = (x.age or 0) * 4.2 + k * math.pi / 2
						local r = head.Size.X * 0.6 + 0.5
						st.part.CFrame = CFrame.new(head.Position + Vector3.new(math.cos(a) * r, head.Size.Y * 0.62 + math.sin(a * 2) * 0.15, math.sin(a) * r))
						local pulse = 1 + 0.18 * math.sin((x.age or 0) * 9 + k)
						st.gui.Size = UDim2.fromOffset(56 * pulse * x.k, 56 * pulse * x.k)
					end
				end
			elseif fx and fx.burst then
				fx.on, fx.world = x.k > 0, x.anchor and A[x.anchor] and (A[x.anchor] * CFrame.new(x.pos)).Position
				-- lands with a spring: a squash that wobbles out (a fade-free pop, like the bubbles)
				local age = x.age or 0
				local wob = math.sin(age * 28) * math.exp(-age * 5)
				fx.scale.Scale = x.k * (1 + 0.14 * wob)
				fx.box.Rotation = -4 + 9 * wob
			end
		end
		-- the iPad: out of sight behind your back, round in your right hand, then held in both
		if chart then
			local hero = actors.hero
			local clipT = hero and hero.clip == "hero_ipad" and (t - hero.clipStart) or -1
			local shown = (f.vals.chartShown or 0) > 0.5 and hero ~= nil and clipT >= BobClips.IPAD_IN_HAND
			chart.Transparency = shown and 0 or 1
			if chart:FindFirstChild("ChartGui") then chart.ChartGui.Enabled = shown end
			if shown then
				local m = hero.model
				local rh = m:FindFirstChild("RightHand")
				-- held out in front of the chest (live 25 Oct: placed between the hands it rode up over his
				-- face), screen to Bob, tipped up a little
				local torso = m:FindFirstChild("UpperTorso") or m:FindFirstChild("Torso") or hero.root
				local look = hero.root.CFrame.LookVector
				local at = torso.Position + look * (torso.Size.Z / 2 + 1.25) + Vector3.new(0, -0.1, 0)
				local held = CFrame.lookAt(at, at + look) * CFrame.Angles(R(12), 0, 0)
				if clipT < BobClips.IPAD_HELD and rh then
					local inHand = rh.CFrame * CFrame.new(0, -0.15, 0) * CFrame.Angles(R(90), 0, 0)
					chart.CFrame = inHand:Lerp(held, math.clamp((clipT - (BobClips.IPAD_HELD - 0.3)) / 0.3, 0, 1))
				else
					chart.CFrame = held
				end
			end
			local k = f.vals.chart or 0
			local n = math.floor(k * #chartLine + 0.5)
			for i, seg in ipairs(chartLine) do seg.Visible = i <= n end
			if chartNum then chartNum.Text = ("+%d%%"):format(math.floor(k * 312)) end
		end
		-- money flying from Bob to you, and the counter
		if #bills > 0 then
			local prog = f.vals.bills or 0
			local from = actors.bob and actors.bob.root and actors.bob.root.Position + Vector3.new(0, 1.5, 0)
			local to = actors.hero and actors.hero.root and actors.hero.root.Position + Vector3.new(0, 1, 0)
			for i, p in ipairs(bills) do
				local k = math.clamp(prog * 1.6 - (i - 1) * 0.035, 0, 1)
				if from and to and k > 0 and k < 1 then
					local pos = from:Lerp(to, k) + Vector3.new(math.sin(i * 7) * 1.2, 4 * 2.2 * k * (1 - k), math.cos(i * 5))
					p.CFrame = CFrame.new(pos) * CFrame.Angles(k * 9 + i, k * 7, i)
					p.Transparency = 0
				else
					p.Transparency = 1
				end
			end
			if money then
				money.Visible = prog > 0
				money.Text = ("+%s  SERIES A x3"):format(UIKit.money and UIKit.money(math.floor((info and info.amount or 0) * math.min(1, prog * 1.15)))
					or tostring(math.floor((info and info.amount or 0) * math.min(1, prog * 1.15))))
			end
		end
		-- Bob's door, the tape, and the front wall (hidden for the boardroom shots: a cutaway)
		if door and doorCF then
			if f.doorDown > 0 then
				-- Luke 25 Oct: "you slam the door down": it falls flat into the room about its bottom
				-- edge (the scene's door is -Z into the building) and lies there
				local edge = doorCF * CFrame.new(0, -door.Size.Y / 2 + door.Size.Z / 2, 0)
				door.CFrame = edge * CFrame.Angles(R(-90 * f.doorDown), 0, 0) * CFrame.new(0, door.Size.Y / 2 - door.Size.Z / 2, 0)
			else
				local hinge = doorCF * CFrame.new(-door.Size.X / 2, 0, 0)
				door.CFrame = hinge * CFrame.Angles(0, R(-100 * f.door), 0) * CFrame.new(door.Size.X / 2, 0, 0)
			end
			override(door, "CanCollide", false)
			if knob and knobRel then override(knob, "CFrame", door.CFrame * knobRel) end
		end
		if tape then
			-- the tape tears off as the door goes: each strip flies its own way and fades
			for i, p in ipairs(tape:GetChildren()) do
				if p:IsA("BasePart") then
					local side = i % 2 == 0 and 1 or -1
					local k = f.tape
					if restore[p] == nil or restore[p].CFrame == nil then override(p, "CFrame", p.CFrame) end
					local p0 = restore[p].CFrame
					p.CFrame = p0 * CFrame.new(side * k * 2.2, -k * 3.2, k * 1.6) * CFrame.Angles(k * 1.4, 0, side * k * 1.8)
					override(p, "LocalTransparencyModifier", math.clamp(k * 1.4 - 0.4, 0, 1))
				end
			end
		end
		-- the front wall is cut away only when the camera stands outside the room (z past the wall's inner
		-- face); live 25 Oct: the inside shots that look sideways saw the street through the gap
		local cutaway = (f.cam.anchor == "board" and f.cam.offset.Z > 11) and 1 or 0
		if front then
			for _, p in ipairs(front:GetDescendants()) do
				if p:IsA("BasePart") then override(p, "LocalTransparencyModifier", cutaway)
				elseif p:IsA("SurfaceGui") then override(p, "Enabled", cutaway == 0) end   -- a hidden part still draws its gui
			end
		end
		for _, n in ipairs({ "Door", "Knob", "Sign" }) do
			local p = bc:FindFirstChild(n)
			if p then override(p, "LocalTransparencyModifier", cutaway) end
		end
		local sign = bc:FindFirstChild("Sign")
		local sg = sign and sign:FindFirstChildOfClass("SurfaceGui")
		if sg then override(sg, "Enabled", cutaway == 0) end
		-- sounds started since the last frame: cues, bubble pops, voices. Each from its measured start,
		-- at its trimmed loudness; one with a dur fades out over `fade` and stops (no chopped notes)
		for _, cue in ipairs(BobScript.cues(name, lastT, t)) do
			local info, s = SOUND[cue.id], cueSound[("%.3f|%s"):format(cue.t, cue.id)]
			if s and not (cue.id == "victory" and player:GetAttribute("MenuMuted") == true) then
				s.Volume = cue.vol * info.gain
				s.PlaybackSpeed = cue.pitch or 1
				s.TimePosition = info.at
				s:Play()
				if cue.dur then
					local fade = cue.fade or 0.1
					task.delay(math.max(0, cue.dur - fade), function()
						if s.Parent then fadeOut(s, fade) end
					end)
				end
			end
		end
		for _, b in ipairs(beds) do
			local v = BobScript.bedLevel(name, b.bed, t)
			if v > 0 and not b.started then
				b.started = true
				b.sound.TimePosition = b.info.at
				b.sound:Play()
			end
			b.sound.Volume = v * b.info.gain
		end
		lastT = t
		lastShot = f.shot
		fadeIn.BackgroundTransparency = math.clamp((t - 0.2) / 0.3, 0, 1)   -- black 0.2 s, then a fade (kept under Reduce Motion)
		fadeIn.Visible = t < 0.5   -- gone after, so it never sits over SKIP
		-- letterbox out at the hand-off
		barT.Position = UDim2.new(0, 0, -0.1 * f.handoff, 0)
		barB.Position = UDim2.new(0, 0, 1 + 0.1 * f.handoff, 0)
		-- the camera: hard cuts between shots; pushes and shake are gone under Reduce Motion
		local base = A[f.cam.anchor]
		if base then
			local shake = f.shake > 0 and Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * 2 * f.shake or Vector3.zero
			-- motion: camera (reduced read above: BobScript.at(name, t, UIKit.reducedMotion()))
			if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end   -- anything that resets it loses
			cam.CFrame = CFrame.lookAt(base * f.cam.offset, base * f.cam.look) * CFrame.new(shake)
			cam.FieldOfView = f.cam.fov
			-- the iPad close-up: framed from the tablet itself, so it holds on any avatar's size
			if f.cam.aim == "tablet" and chart and chart.Transparency < 1 and f.cam.dist then
				local c = chart.CFrame
				local from = c.Position + c.LookVector * f.cam.dist + c.UpVector * 0.25 + c.RightVector * 0.35
				cam.CFrame = CFrame.lookAt(from, c.Position + c.UpVector * 0.1) * CFrame.new(shake)
			end
			-- Studio only: BobSceneLook = an actor id ("hero", "bob", "inv1", "inv2") frames that actor's head
			-- up close, from its front-left (BobSceneLookDist studs, default 9), so a held clip or a face
			-- can be checked by eye
			local look = RunService:IsStudio() and actors[player:GetAttribute("BobSceneLook") or ""]
			if look and look.root then
				local r = look.root.CFrame
				local d = player:GetAttribute("BobSceneLookDist") or 9
				local at = look.head and look.head.Position or r.Position + Vector3.new(0, 0.6, 0)
				cam.CFrame = CFrame.lookAt(at + r.LookVector * d - r.RightVector * d * 0.35 + Vector3.new(0, d * 0.12, 0), at)
				cam.FieldOfView = 50
			end
		end
		for _, bb in pairs(bubbles) do
			if bb.on and bb.head then placeBubble(cam, bb, f.shot) end
		end
		for _, fx in pairs(fxs) do
			if fx.burst then
				-- (the doctor, 25 Oct: "fx.on and ..." gave false, not nil, when off, and false.Z errored every frame)
				local p = (fx.on and fx.world) and cam:WorldToViewportPoint(fx.world) or nil
				fx.box.Visible = p ~= nil and p.Z > 0
				if fx.box.Visible then
					local vp = cam.ViewportSize
					fx.box.Position = UDim2.fromOffset(fit(p.X, 150, vp.X - 150), fit(p.Y, vp.Y * 0.1 + 110, vp.Y * 0.9 - 110))
				end
			end
		end
	end)

	while not finished do task.wait(0.1) end
	return not skipped
	end)
	if not okRun then
		warn("[Bob] the scene failed and was put back: " .. tostring(result))
		putBack()
		if gui then gui:Destroy() end
		player:SetAttribute("BobSceneState", "failed")
		return false
	end
	return result
end

event.Event:Connect(function(name, info)
	task.spawn(play, name, info)
end)

-- the server paid you at Bob's door: play the payoff (the money is already yours)
task.spawn(function()
	local remotes = RS:WaitForChild("SVRemotes", 60)
	local ev = remotes and remotes:WaitForChild("BobPayoff", 60)
	if ev then ev.OnClientEvent:Connect(function(info) task.spawn(play, "payoff", info) end) end
end)
