--[[ GarageMoodClient (12 Oct 2026): a warm grade while the camera is inside a garage.

	His target for the garage ("image 5") is golden and cosy; the room under the
	valley's daylight renders white and flat. Measured 12 Oct: props, walls and lamps
	got it most of the way, and a gentle warm grade is the last step. It is applied
	only while the CAMERA is inside a garage (any plot's: you can visit), and eases
	in and out so walking through the door does not snap.

	Garage-local box from GarageLayout (+-17.5 across, -14.5..15 deep, floor 0 to the
	beams), read off each plot folder's Pivot attribute. ]]
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local RS = game:GetService("ReplicatedStorage")

local L = require(RS:WaitForChild("GarageLayout"))
local plots = workspace:WaitForChild("SiliconValley"):WaitForChild("Plots")

local cc = Instance.new("ColorCorrectionEffect")
cc.Name = "GarageMood"
cc.Parent = Lighting

local WARM = { TintColor = Color3.fromRGB(255, 236, 214), Contrast = 0.08, Saturation = 0.1, Brightness = -0.02 }   -- world colour
local NEUTRAL = { TintColor = Color3.new(1, 1, 1), Contrast = 0, Saturation = 0, Brightness = 0 }   -- world colour
local EASE = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function cameraInGarage()
	local cam = workspace.CurrentCamera
	if not cam then return false end
	local pos = cam.CFrame.Position
	for _, plot in plots:GetChildren() do
		local pv = plot:GetAttribute("Pivot")
		if typeof(pv) == "CFrame" then
			local l = pv:PointToObjectSpace(pos)
			if math.abs(l.X) < L.HALF_X and l.Z > L.BACK and l.Z < L.FRONT + 0.5 and l.Y > 0 and l.Y < L.CEIL + 0.8 then
				return true
			end
		end
	end
	return false
end

local inside = false
while true do
	task.wait(0.25)
	local now = cameraInGarage()
	if now ~= inside then
		inside = now
		TweenService:Create(cc, EASE, now and WARM or NEUTRAL):Play()
	end
end
