--[[ DropOffClient (10 Oct): where to take the hire you are carrying.

	His recording, 10 Oct: he carried a hire to his HQ, rode past the door into the
	building, stood on the yellow pad and was caught there. Nothing in the world said
	where "home" was. While you carry, this draws it at the server's CarryHome (your
	entrance court) at its real size (CarryHomeR, Chase.DELIVER_R):
	  a green ring on the ground, the delivery zone itself
	  a light beam you can see over the buildings, like the candidates' pillars
	  a DROP OFF sign with the distance, drawn on top of everything
	All local (this client only): no network, and nothing to collide with or hit.
	Gone the moment the carry ends, however it ends. ]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local COLOR = UIKit.GREEN
local BEAM_H = 90

local marker, label, conn

local function piece(parent, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = COLOR
	for k, v in pairs(props) do p[k] = v end
	p.Parent = parent
	return p
end

local function clear()
	if conn then conn:Disconnect() conn = nil end
	if marker then marker:Destroy() marker = nil end
	label = nil
end

local function build(at, radius)
	clear()
	marker = Instance.new("Model")
	marker.Name = "DropOff"
	-- the zone: a flat disc you can see through, and a brighter rim
	local disc = piece(marker, {
		Name = "Zone", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, radius * 2, radius * 2),
		CFrame = CFrame.new(at + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)), Transparency = 0.7,
	})
	local rim = piece(marker, {
		Name = "Rim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, radius * 2 + 1.2, radius * 2 + 1.2),
		CFrame = CFrame.new(at + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), Transparency = 0.35,
	})
	local beam = piece(marker, {
		Name = "Beam", Size = Vector3.new(1.6, BEAM_H, 1.6),
		CFrame = CFrame.new(at + Vector3.new(0, BEAM_H / 2, 0)), Transparency = 0.45,
	})
	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromOffset(170, 48)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 9, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = disc
	gui.Parent = marker
	label = Instance.new("TextLabel")
	label.BackgroundColor3 = COLOR
	label.BackgroundTransparency = 0.05
	label.Size = UDim2.fromScale(1, 1)
	label.Font = UIKit.HEAD
	label.TextScaled = true
	label.TextColor3 = UIKit.INK
	label.Text = "DROP OFF"
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = label
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 4), UDim.new(0, 4)
	pad.Parent = label
	marker.Parent = workspace
	-- the distance on the sign, and a slow pulse on the beam so it reads as "go here"
	local last = 0
	conn = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		beam.Transparency = 0.45 + 0.2 * math.sin(now * 3)
		rim.Transparency = 0.35 + 0.15 * math.sin(now * 3)
		if now - last < 0.2 then return end
		last = now
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp and label then
			local d = (Vector3.new(at.X, 0, at.Z) - Vector3.new(hrp.Position.X, 0, hrp.Position.Z)).Magnitude
			label.Text = d > radius and ("DROP OFF · %dm"):format(math.floor(d)) or "DROP OFF"
		end
	end)
end

local function refresh()
	local at = player:GetAttribute("CarryHome")
	if player:GetAttribute("Carrying") and typeof(at) == "Vector3" then
		build(at, tonumber(player:GetAttribute("CarryHomeR")) or 14)
	else
		clear()
	end
end

player:GetAttributeChangedSignal("Carrying"):Connect(refresh)
player:GetAttributeChangedSignal("CarryHome"):Connect(refresh)
refresh()
