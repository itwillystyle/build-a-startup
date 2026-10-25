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

function BobFace.attach(model)
	local head = model and model:FindFirstChild("Head")
	local h = { current = nil }
	if not head then
		function h.set() end
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
