--[[
	BobFace -- ReplicatedStorage ModuleScript (client). P-5, Bob's cutscenes (25 Oct 2026).

	Faces for the cutscene actors, with no uploads: speech bubbles carry the words, faces carry
	the feeling (spec 3a, 3b: "facial expressions"). Two kinds of head:
	  * a CLASSIC head (a `face` Decal): the decal is hidden and a cartoon face is drawn on a
	    front SurfaceGui (Frames: eyes, brows, mouth), the storyboard's faces;
	  * a DYNAMIC head (it has FaceControls): its FaceControls are set per expression. They
	    are not replicated, which is fine: the cutscene only exists on this client.

	  local h = BobFace.attach(model)   -- once per actor
	  h.set("laugh")                    -- neutral hope laugh shock sad determined smug dizzy grin
]]

local BobFace = {}

local INK = Color3.fromRGB(20, 22, 30)
local MOUTH = Color3.fromRGB(107, 31, 31)
local WHITE = Color3.fromRGB(255, 255, 255)

-- FaceControls targets per expression (0..1); unknown names are skipped (pcall)
local CONTROLS = {
	neutral = {},
	hope = { LeftOuterBrowRaiser = 0.6, RightOuterBrowRaiser = 0.6, LeftLipCornerPuller = 0.3, RightLipCornerPuller = 0.3 },
	laugh = { JawDrop = 0.6, LeftLipCornerPuller = 1, RightLipCornerPuller = 1, LeftEyeClosed = 0.8, RightEyeClosed = 0.8 },
	shock = { JawDrop = 1, LeftUpperLidRaiser = 1, RightUpperLidRaiser = 1, LeftOuterBrowRaiser = 1, RightOuterBrowRaiser = 1 },
	sad = { LeftLipCornerDown = 0.8, RightLipCornerDown = 0.8, LeftInnerBrowRaiser = 0.8, RightInnerBrowRaiser = 0.8 },
	determined = { LeftBrowLowerer = 1, RightBrowLowerer = 1, LipPresser = 0.6 },
	smug = { LeftLipCornerPuller = 0.7, LeftEyeClosed = 0.4, RightEyeClosed = 0.4 },
	dizzy = { JawDrop = 0.2, LeftEyeClosed = 0.5, RightEyeClosed = 0.9 },
	grin = { LeftLipCornerPuller = 1, RightLipCornerPuller = 1, LeftCheekRaiser = 1, RightCheekRaiser = 1 },
}
local ALL = {}
for _, t in pairs(CONTROLS) do for k in pairs(t) do ALL[k] = true end end

local function frame(parent, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	for k, v in pairs(props) do f[k] = v end
	f.Parent = parent
	return f
end
local function round(f, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(r or 1, 0)
	c.Parent = f
	return f
end

-- the cartoon face on a SurfaceGui: all positions are fractions of the head's front
local function draw(gui, expr)
	gui:ClearAllChildren()
	local function eye(x)
		if expr == "laugh" or expr == "grin" then        -- ^ ^
			frame(gui, { Position = UDim2.fromScale(x - 0.035, 0.4), Size = UDim2.fromScale(0.09, 0.03), Rotation = -35, BackgroundColor3 = INK })
			frame(gui, { Position = UDim2.fromScale(x + 0.035, 0.4), Size = UDim2.fromScale(0.09, 0.03), Rotation = 35, BackgroundColor3 = INK })
		elseif expr == "shock" then
			local w = round(frame(gui, { Position = UDim2.fromScale(x, 0.42), Size = UDim2.fromScale(0.16, 0.16), BackgroundColor3 = WHITE }))
			local st = Instance.new("UIStroke"); st.Thickness = 2; st.Color = INK; st.Parent = w
			round(frame(gui, { Position = UDim2.fromScale(x, 0.42), Size = UDim2.fromScale(0.06, 0.06), BackgroundColor3 = INK }))
		elseif expr == "dizzy" then                       -- X
			frame(gui, { Position = UDim2.fromScale(x, 0.42), Size = UDim2.fromScale(0.12, 0.03), Rotation = 45, BackgroundColor3 = INK })
			frame(gui, { Position = UDim2.fromScale(x, 0.42), Size = UDim2.fromScale(0.12, 0.03), Rotation = -45, BackgroundColor3 = INK })
		elseif expr == "smug" then
			frame(gui, { Position = UDim2.fromScale(x, 0.42), Size = UDim2.fromScale(0.11, 0.03), BackgroundColor3 = INK })
		else
			round(frame(gui, { Position = UDim2.fromScale(x, 0.42), Size = UDim2.fromScale(0.08, 0.08), BackgroundColor3 = INK }))
		end
		local brow = ({ hope = { 0.27, x < 0.5 and 10 or -10 }, sad = { 0.29, x < 0.5 and -18 or 18 },
			determined = { 0.3, x < 0.5 and 20 or -20 }, shock = { 0.22, 0 } })[expr]
		if brow then
			frame(gui, { Position = UDim2.fromScale(x, brow[1]), Size = UDim2.fromScale(0.14, 0.035), Rotation = brow[2], BackgroundColor3 = INK })
		end
	end
	eye(0.36)
	eye(0.64)
	if expr == "laugh" or expr == "grin" then
		local m = round(frame(gui, { Position = UDim2.fromScale(0.5, 0.66), Size = UDim2.fromScale(0.34, 0.16),
			BackgroundColor3 = expr == "laugh" and MOUTH or WHITE }), 0.5)
		local st = Instance.new("UIStroke"); st.Thickness = 2; st.Color = INK; st.Parent = m
	elseif expr == "shock" then
		round(frame(gui, { Position = UDim2.fromScale(0.5, 0.7), Size = UDim2.fromScale(0.14, 0.2), BackgroundColor3 = MOUTH }))
	elseif expr == "sad" then
		frame(gui, { Position = UDim2.fromScale(0.5, 0.7), Size = UDim2.fromScale(0.2, 0.035), Rotation = 0, BackgroundColor3 = INK })
		frame(gui, { Position = UDim2.fromScale(0.39, 0.72), Size = UDim2.fromScale(0.06, 0.035), Rotation = 40, BackgroundColor3 = INK })
		frame(gui, { Position = UDim2.fromScale(0.61, 0.72), Size = UDim2.fromScale(0.06, 0.035), Rotation = -40, BackgroundColor3 = INK })
	elseif expr == "determined" then
		frame(gui, { Position = UDim2.fromScale(0.5, 0.68), Size = UDim2.fromScale(0.26, 0.045), Rotation = -4, BackgroundColor3 = INK })
	elseif expr == "smug" then
		frame(gui, { Position = UDim2.fromScale(0.55, 0.67), Size = UDim2.fromScale(0.22, 0.035), Rotation = -10, BackgroundColor3 = INK })
	elseif expr == "hope" then
		frame(gui, { Position = UDim2.fromScale(0.5, 0.67), Size = UDim2.fromScale(0.16, 0.035), BackgroundColor3 = INK })
	else
		frame(gui, { Position = UDim2.fromScale(0.5, 0.68), Size = UDim2.fromScale(0.14, 0.035), BackgroundColor3 = INK })
	end
end


-- ------------------------------------------------------------------ card mode (AI mesh heads)
--[[ 25 Oct (Luke: "generate the head with no mouth or eyebrows"): the AI cast have blank faces
	under their glasses. A decal cannot follow a curved mesh head, so each head carries two small
	invisible cards, welded to it, sitting on the skin: MouthCard below the nose and BrowCard above
	the glasses. The expression is drawn on their SurfaceGuis. ensureCards places them by measuring
	the head (raycasts from the front), so any blank-faced head works, not just Bob's. ]]
BobFace.MOUTH_AT = -0.27   -- fractions of the head's height from its centre (Bob, measured 25 Oct)
BobFace.BROW_AT = 0.25
local SKIN_GAP = 0.04

local function cardPart(head, name, cf, size)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Transparency = 1
	p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow, p.Massless = false, false, false, false, true
	p.Anchored = head.Anchored
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = head, p
	w.Parent = p
	local g = Instance.new("SurfaceGui")
	g.Name = "Draw"
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 200
	g.LightInfluence = 0.6
	g.Parent = p
	p.Parent = head.Parent
	return p
end

-- needs the head in a WorldRoot (raycasts); the model must face -Z of its torso.
-- tune (optional): { mouthIn = studs } sets the mouth deeper into the face. The raycast meets the
-- head's collision shell, which on some AI heads bulges in front of the drawn face (live 25 Oct: the
-- short investor's mouth stood 0.2 studs proud and showed past his cheek from the side)
function BobFace.ensureCards(model, tune)
	local head = model and model:FindFirstChild("Head", true)
	if not head or model:FindFirstChild("MouthCard", true) then return end
	local torso = model:FindFirstChild("Torso", true) or head
	local front = torso.CFrame.LookVector
	local up = torso.CFrame.UpVector
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { head }
	local world = head:FindFirstAncestorWhichIsA("WorldRoot")
	if not world then return end
	local function skin(k)
		local at = head.Position + up * (k * head.Size.Y)
		local from = at + front * (head.Size.Z + 4)
		local hit = world:Raycast(from, -front * (head.Size.Z + 8), params)
		return hit and hit.Position or (at + front * head.Size.Z / 2)
	end
	local w = head.Size.X
	local m = skin(BobFace.MOUTH_AT) - front * ((tune and tune.mouthIn) or 0)
	cardPart(head, "MouthCard", CFrame.lookAt(m + front * SKIN_GAP, m + front * 2, up), Vector3.new(w * 0.36, w * 0.18, 0.02))
	-- the brow card leans back with the forehead: aim it along the surface normal between two samples
	local b, b2 = skin(BobFace.BROW_AT), skin(BobFace.BROW_AT + 0.08)
	local slope = (b2 - b).Unit
	local normal = slope:Cross(torso.CFrame.RightVector).Unit
	if normal:Dot(front) < 0 then normal = -normal end
	cardPart(head, "BrowCard", CFrame.lookAt(b + normal * SKIN_GAP, b + normal * 2, slope), Vector3.new(w * 0.62, w * 0.14, 0.02))
end

-- a drawn face is only drawn where it can be seen: a card turned more than about 65 degrees from the
-- camera stands out past the cheek like a sticker, so it hides until the face turns back
function BobFace.facing(model, camPos)
	for _, n in ipairs({ "MouthCard", "BrowCard" }) do
		local c = model:FindFirstChild(n, true)
		local g = c and c:FindFirstChild("Draw")
		if g then
			local toCam = camPos - c.Position
			local face = toCam.Magnitude > 0 and c.CFrame.LookVector:Dot(toCam.Unit) or 1
			if face < 0.42 then g.Enabled = false end
		end
	end
end

local MOUTH_RED = Color3.fromRGB(110, 28, 34)
local TONGUE = Color3.fromRGB(232, 92, 100)
local TEETH = Color3.fromRGB(250, 248, 240)

local function dShape(gui, x, y, w, h, fill, inner)   -- an open "D" mouth: the bottom half of an oval
	local box = frame(gui, { Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w, h / 2), BackgroundTransparency = 1, ClipsDescendants = true })
	box.AnchorPoint = Vector2.new(0.5, 0)
	local o = round(frame(box, { Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(1, 2), BackgroundColor3 = fill }), 0.5)
	local st = Instance.new("UIStroke"); st.Thickness = 5; st.Color = INK; st.Parent = o
	frame(gui, { Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w + 0.02, 0.07), BackgroundColor3 = INK })
	if inner then round(frame(o, { Position = UDim2.fromScale(0.5, 0.82), Size = UDim2.fromScale(0.5, 0.28), BackgroundColor3 = inner }), 0.5) end
end

local function drawMouth(gui, expr)
	gui:ClearAllChildren()
	if expr == "laugh" then dShape(gui, 0.5, 0.18, 0.72, 1.3, MOUTH_RED, TONGUE)
	elseif expr == "grin" then dShape(gui, 0.5, 0.25, 0.66, 0.95, TEETH)
	elseif expr == "hope" then dShape(gui, 0.5, 0.35, 0.36, 0.5, MOUTH_RED)
	elseif expr == "shock" then
		local o = round(frame(gui, { Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.26, 0.9), BackgroundColor3 = MOUTH_RED }), 0.5)
		local st = Instance.new("UIStroke"); st.Thickness = 5; st.Color = INK; st.Parent = o
	elseif expr == "sad" then
		frame(gui, { Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromScale(0.3, 0.1), BackgroundColor3 = INK })
		frame(gui, { Position = UDim2.fromScale(0.33, 0.58), Size = UDim2.fromScale(0.1, 0.1), Rotation = 40, BackgroundColor3 = INK })
		frame(gui, { Position = UDim2.fromScale(0.67, 0.58), Size = UDim2.fromScale(0.1, 0.1), Rotation = -40, BackgroundColor3 = INK })
	elseif expr == "smug" then
		frame(gui, { Position = UDim2.fromScale(0.55, 0.5), Size = UDim2.fromScale(0.42, 0.1), Rotation = -9, BackgroundColor3 = INK })
		frame(gui, { Position = UDim2.fromScale(0.78, 0.38), Size = UDim2.fromScale(0.1, 0.1), Rotation = -40, BackgroundColor3 = INK })
	elseif expr == "determined" then
		frame(gui, { Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.42, 0.13), BackgroundColor3 = INK })
	elseif expr == "dizzy" then
		for i, r in ipairs({ 30, -30, 30 }) do
			frame(gui, { Position = UDim2.fromScale(0.34 + (i - 1) * 0.16, 0.5), Size = UDim2.fromScale(0.18, 0.09), Rotation = r, BackgroundColor3 = INK })
		end
	else
		frame(gui, { Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.34, 0.09), BackgroundColor3 = INK })
	end
end

-- brows: { left y, left rotation, right y, right rotation }
local BROWS = {
	neutral = { 0.55, 0, 0.55, 0 }, hope = { 0.42, -8, 0.42, 8 }, laugh = { 0.38, -14, 0.38, 14 },
	shock = { 0.22, -6, 0.22, 6 }, sad = { 0.45, -18, 0.45, 18 }, determined = { 0.6, 22, 0.6, -22 },
	smug = { 0.6, 6, 0.32, 14 }, dizzy = { 0.5, -12, 0.35, 26 }, grin = { 0.4, -10, 0.4, 10 },
}
local function drawBrows(gui, expr)
	gui:ClearAllChildren()
	local b = BROWS[expr] or BROWS.neutral
	frame(gui, { Position = UDim2.fromScale(0.27, b[1]), Size = UDim2.fromScale(0.3, 0.24), Rotation = b[2], BackgroundColor3 = INK })
	frame(gui, { Position = UDim2.fromScale(0.73, b[3]), Size = UDim2.fromScale(0.3, 0.24), Rotation = b[4], BackgroundColor3 = INK })
end

function BobFace.attach(model)
	local head = model and model:FindFirstChild("Head")
	local h = { current = nil }
	if not head then
		function h.set() end
		return h
	end
	-- an AI mesh head with its face cards: draw on the cards
	local mouthCard, browCard = model:FindFirstChild("MouthCard", true), model:FindFirstChild("BrowCard", true)
	if mouthCard and browCard then
		local mg, bg = mouthCard:FindFirstChild("Draw"), browCard:FindFirstChild("Draw")
		function h.set(expr)
			if h.current == expr then return end
			h.current = expr
			if mg then drawMouth(mg, expr) end
			if bg then drawBrows(bg, expr) end
		end
		return h
	end
	local fc = head:FindFirstChildOfClass("FaceControls")
	if fc then
		function h.set(expr)
			if h.current == expr then return end
			h.current = expr
			local want = CONTROLS[expr] or {}
			for name in pairs(ALL) do pcall(function() fc[name] = want[name] or 0 end) end
		end
		return h
	end
	-- classic: hide the decal, draw on our own SurfaceGui
	for _, d in ipairs(head:GetChildren()) do
		if d:IsA("Decal") then d.Transparency = 1 end
	end
	local gui = head:FindFirstChild("Face")
	if not (gui and gui:IsA("SurfaceGui")) then
		gui = Instance.new("SurfaceGui")
		gui.Name = "Face"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 100
		gui.LightInfluence = 0.5
		gui.Parent = head
	end
	function h.set(expr)
		if h.current == expr then return end
		h.current = expr
		draw(gui, expr)
	end
	return h
end

return BobFace
