--[[ LotClient (12 Oct 2026): sets the client-local player attribute OnLot -- true
	while you stand on your own lot (LotZone), nil elsewhere. The rail shows its
	plot-only tiles (BUILD, DECOR) only then. Checked twice a second: walking, a car
	or a teleport all just move the root. Before you own a plot, nothing is plot-only. ]]
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local LotZone = require(RS:WaitForChild("LotZone"))

local player = Players.LocalPlayer
local valley = workspace:WaitForChild("SiliconValley", 60)
local plots = valley and valley:WaitForChild("Plots", 60)
if not plots then return end

local function myPivot()
	for _, f in ipairs(plots:GetChildren()) do
		if f:GetAttribute("OwnerId") == player.UserId then return f:GetAttribute("Pivot") end
	end
	return nil
end

local on = nil
while true do
	local pivot = myPivot()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local now
	if typeof(pivot) ~= "CFrame" then
		now = true             -- no plot yet: nothing to hide
	elseif root then
		now = LotZone.contains(pivot, root.Position, on == true)
	else
		now = on               -- respawning: keep the last answer
	end
	if now ~= on then
		on = now
		player:SetAttribute("OnLot", on or nil)
	end
	task.wait(0.5)
end
