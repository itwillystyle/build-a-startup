--[[ DoctorClient (11 Oct 2026): the game doctor's hands on the player's side.

	Studio only, and inert until GameDoctor (server) sets the player attribute
	DoctorProbe = JSON { name, nonce, args }. It then runs DoctorProbes[name] and
	sends the numbers back on ReplicatedStorage.DoctorResult, with any script
	errors this client printed since the last probe (the server's LogService does
	not see the client's). A real LocalScript, not bridge code: probes sample every
	frame, and code run through the Studio bridge is only resumed about every
	0.39 s (DevRobot.client.lua). ]]
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Probes = require(ReplicatedStorage:WaitForChild("DoctorProbes"))
local player = Players.LocalPlayer

local errors = {}
LogService.MessageOut:Connect(function(msg, kind)
	if kind == Enum.MessageType.MessageError and #errors < 50 then table.insert(errors, msg:sub(1, 220)) end
end)

player:GetAttributeChangedSignal("DoctorProbe"):Connect(function()
	local raw = player:GetAttribute("DoctorProbe")
	if type(raw) ~= "string" then return end
	local ok, req = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(req) ~= "table" or not Probes[req.name] then return end
	task.spawn(function()
		local fine, res = pcall(Probes[req.name], req.args or {})
		if not fine then res = { error = tostring(res) } end
		res.clientErrors = errors
		errors = {}
		local remote = ReplicatedStorage:WaitForChild("DoctorResult", 10)
		if remote then remote:FireServer(req.nonce, res) end
	end)
end)
