--[[
	CLIENT INFO -- LocalScript in StarterPlayer -> StarterPlayerScripts.

	One message, once: is this a touch device? Every telemetry row gets
	tagged with the answer, so the phone pass has a before and after.
	"Mobile" here means touch without a keyboard -- a tablet with a keyboard
	case plays like a desktop and is counted as one.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local remotes = ReplicatedStorage:WaitForChild("SVRemotes")
local clientInfo = remotes:WaitForChild("ClientInfo")

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
clientInfo:FireServer(isMobile)
