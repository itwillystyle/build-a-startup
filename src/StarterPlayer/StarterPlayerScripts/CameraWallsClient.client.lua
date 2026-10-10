--[[ CameraWallsClient (10 Oct 2026): the normal camera stops at the HQ's walls.

	Roblox's camera places the lens first (RenderPriority.Camera); this runs right
	after and, if a building wall it cannot see stands between your head and the
	lens, slides the lens in along the same line (CameraWalls.lua says why it
	cannot see them). Sliding along the line keeps the look direction, so Roblox's
	camera, which reads it back next frame, does not drift. Only the Custom
	camera: the chase camera (Scriptable) does its own walls, cutscenes own theirs. ]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraWalls = require(ReplicatedStorage:WaitForChild("CameraWalls"))
CameraWalls.start()

local player = Players.LocalPlayer

RunService:BindToRenderStep("SVCameraWalls", Enum.RenderPriority.Camera.Value + 1, function()
	local camera = workspace.CurrentCamera
	if not camera or camera.CameraType ~= Enum.CameraType.Custom then return end
	if player:GetAttribute("CameraWalls") == false then return end   -- QA: compare with it off
	local focus = camera.Focus.Position
	local cf = camera.CFrame
	local off = cf.Position - focus
	local want = off.Magnitude
	if want <= CameraWalls.MIN then return end       -- first person
	local keep = CameraWalls.distance(want, CameraWalls.cast(focus, off))
	if keep < want then camera.CFrame = cf - off.Unit * (want - keep) end
end)
