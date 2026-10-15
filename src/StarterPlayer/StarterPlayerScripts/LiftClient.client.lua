--[[
	LiftClient (v9, 15 Oct 2026, HQ part 1b): the lift's ride, on the client.
	The server (LiftCab) publishes each ride as attributes on the cab model; this script animates
	every cab from them so the ride is smooth for riders and watchers, carries its own character
	with the cab (the platform-delta method: the character keeps its offset from the cab each frame,
	so it never shakes or falls through), holds a steady camera inside for riders, plays the ticks
	and the ding, opens the big floor list when you step in, pops "NEW!" on the trophy panel, and
	flickers the light on the "calm" event. Spec: docs/superpowers/specs/2026-10-15-hq-lift-1b-design.md
]]
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local UIKit = require(RS:WaitForChild("UIKit"))
local T = require(RS:WaitForChild("TowerPlan"))
local LP = require(RS:WaitForChild("LiftPlan")).with(T)
local liftPick = RS:WaitForChild("SVRemotes"):WaitForChild("LiftPick")
local C = T.CAB

-- ------------------------------------------------------------ the floor list (phone first)
local gui = Instance.new("ScreenGui")
gui.Name = "Lift"
gui.ResetOnSpawn = false
gui.DisplayOrder = 12
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")
UIKit.safe(gui)
local ROW = 56
local menu, body, close = UIKit.menu(gui, "TAKE THE LIFT", UIKit.BLUE, {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 340, 0, 200),
})
-- a tall tower scrolls: rows never draw under 44 px (a short phone screen shrank 12 rows to 26 px)
local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.Size = UDim2.new(1, 0, 1, 0)
list.ScrollBarThickness = 5
list.Parent = body
local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 6)
layout.Parent = list
local fit = Instance.new("UIScale")
fit.Parent = menu
local FLOOR = 44 / ROW
local place = UIKit.fitMenu(menu, 340, nil, fit, 16, FLOOR)
menu:GetPropertyChangedSignal("Size"):Connect(function() place(menu.Position.Y.Scale, menu.Position.Y.Offset) end)
local listFor        -- the cab whose list is open
-- scrolled so "YOU ARE HERE" is in view (the lobby is the bottom row). CanvasPosition is in scaled
-- screen pixels, and the list's sizes settle a frame or more after it opens (measured 15 Oct), so
-- this runs again whenever they change; they only change on open or a refit, never mid-scroll
local hereAt = 0
local function scrollHere()
	local s = list.AbsoluteCanvasSize.Y / math.max(1, list.CanvasSize.Y.Offset)
	list.CanvasPosition = Vector2.new(0, math.max(0, (hereAt + 1) * (ROW + 6) * s - list.AbsoluteWindowSize.Y))
end
list:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(scrollHere)
list:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(scrollHere)
local function hide() gui.Enabled = false; listFor = nil end
if close then close.MouseButton1Click:Connect(hide) end

local function openList(cab)
	for _, c in ipairs(list:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
	local ok, stops = pcall(HttpService.JSONDecode, HttpService, cab:GetAttribute("Stops") or "[]")
	if not ok then return end
	local at = cab:GetAttribute("At")
	local hereRow = 0
	for k = #stops, 1, -1 do   -- top floor first, like a panel read from the top
		local st = stops[k]
		local here, locked = st.id == at, not st.built
		if here then hereRow = #stops - k end
		local b = UIKit.button(list, "", (here or locked) and UIKit.SURFACE_2 or UIKit.BLUE, {
			Name = "Stop_" .. st.id, Size = UDim2.new(1, -8, 0, ROW), LayoutOrder = #stops - k,
		}, { silent = here or locked })
		UIKit.label(b, st.num, UIKit.TYPE.title, (here or locked) and UIKit.MUTED_TEXT or UIKit.TEXT, {
			Position = UDim2.new(0, 10, 0, 0), Size = UDim2.new(0, 44, 1, 0),
		}, UIKit.HEAD)
		local name = locked and "Build to unlock" or (st.label ~= "" and st.label or ("FLOOR " .. st.num))
		UIKit.label(b, name, UIKit.TYPE.body, (here or locked) and UIKit.MUTED_TEXT or UIKit.TEXT, {
			Position = UDim2.new(0, 62, 0, 0), Size = UDim2.new(1, -150, 1, 0), TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, UIKit.HEAD)
		local sub = here and "YOU ARE HERE" or st.sub or ""
		if sub ~= "" then
			UIKit.label(b, sub, UIKit.TYPE.caption, UIKit.MUTED_TEXT, {
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.new(0, 84, 0, 18),
				TextXAlignment = Enum.TextXAlignment.Right,
			}, UIKit.BODY)
		end
		if not (here or locked) then
			b.MouseButton1Click:Connect(function()
				liftPick:FireServer(cab:GetAttribute("Plot"), st.id)
				UIKit.sfx("tap")
				hide()
			end)
		end
	end
	-- as many rows as fit on this screen at the 44 px floor; the rest scroll
	local room = math.max(3, math.floor(((gui.AbsoluteSize.Y - 32) / FLOOR - 72) / (ROW + 6)))
	menu.Size = UDim2.new(0, 340, 0, 72 + math.min(#stops, room) * (ROW + 6))
	list.CanvasSize = UDim2.new(0, 0, 0, #stops * (ROW + 6))
	hereAt = hereRow
	scrollHere()
	listFor = cab
	gui.Enabled = true
	UIKit.solo(gui)
end

-- ------------------------------------------------------------ the cab, animated from its attributes
local function insideBox(cab, pos, pad)
	local base = cab.PrimaryPart
	if not base then return false end
	local l = (base.CFrame * CFrame.new(0, 0.25 + C.h / 2, 0)):PointToObjectSpace(pos)
	pad = pad or 0
	return math.abs(l.X) <= C.w / 2 + pad and math.abs(l.Y) <= C.h / 2 + pad and math.abs(l.Z) <= C.d / 2 + pad
end

local rideState = {}     -- cab -> { start }
local seen, panelSeen = {}, {}
local camWas
local riderCab           -- the cab whose ride holds our camera
-- hand the camera back. Also when the cab is gone (a rebuild mid-ride replaced it) or we respawn:
-- RF3/RF5 (15 Oct) left the camera Scriptable for good, and the next ride saved that as "before"
local function release()
	if not riderCab then return end
	riderCab = nil
	workspace.CurrentCamera.CameraType = camWas or Enum.CameraType.Custom
	camWas = nil
end
player.CharacterAdded:Connect(release)

local function drawStep(cab, moving)   -- FromY/ToY are cabAt heights: the base sits 0.25 below
	local base = cab.PrimaryPart
	local t = workspace:GetServerTimeNow() - (cab:GetAttribute("Start") or 0)
	return LP.drawStep(moving, cab:GetAttribute("FromY") or 0, cab:GetAttribute("ToY") or 0, t,
		cab:GetAttribute("Dur") or 0, base.Position.Y + 0.25)
end

local function startRide(cab)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and insideBox(cab, root.Position, 0.5) then
		hide()
		-- the ticks, then the ding
		for _, tk in ipairs(LP.ticks(cab:GetAttribute("Floors") or 0)) do
			task.delay(tk.t, function() UIKit.sfx("tap", tk.loud and 1.25 or 1.7, tk.loud and 0.55 or 0.25) end)
		end
		task.delay(cab:GetAttribute("Dur") or 0, function() UIKit.sfx("ding", 1.05, 0.45) end)
		local cam = workspace.CurrentCamera
		if not riderCab then
			camWas = cam.CameraType ~= Enum.CameraType.Scriptable and cam.CameraType or Enum.CameraType.Custom
		end
		riderCab = cab
		cam.CameraType = Enum.CameraType.Scriptable
	end
	if cab:GetAttribute("Event") == "calm" then
		local light = cab:FindFirstChild("CabLight")
		if light then
			local was = light.Transparency
			light.Transparency = 1
			task.delay(0.5, function() light.Transparency = was end)
		end
	end
end

RunService.RenderStepped:Connect(function()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if riderCab and not riderCab:IsDescendantOf(workspace) then release() end
	for cab in pairs(rideState) do if not cab.Parent then rideState[cab] = nil end end
	for _, cab in ipairs(CollectionService:GetTagged("LiftCab")) do
		local base = cab.PrimaryPart
		if base then
			local rs = rideState[cab]
			if not rs then rs = { start = nil }; rideState[cab] = rs end
			local moving = cab:GetAttribute("State") == "moving"
			local start = cab:GetAttribute("Start")
			if moving and rs.start ~= start then
				rs.start = start
				startRide(cab)
			end
			-- draw the cab where the ride says (locally), and carry our character by the same step
			local step = drawStep(cab, moving)
			if math.abs(step) > 1e-4 then
				local carry = root and insideBox(cab, root.Position, 0.5)
				cab:PivotTo(cab:GetPivot() + Vector3.new(0, step, 0))
				if carry then
					root.CFrame = root.CFrame + Vector3.new(0, step, 0)
					root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
				end
			end
			-- the rider's camera: inside, facing the doors
			if riderCab == cab and moving then
				local cf = base.CFrame
				workspace.CurrentCamera.CFrame = CFrame.lookAt((cf * CFrame.new(0, 6.6, -C.d / 2 + 1.2)).Position, (cf * CFrame.new(0, 4.2, C.d / 2)).Position)
			elseif riderCab == cab then
				release()
			end
			-- stepping in opens the list (and pops NEW on the trophy panel)
			local state = cab:GetAttribute("State")
			if root and (state == "open" or state == "idle") and insideBox(cab, root.Position, 0) then
				if listFor ~= cab and not seen[cab] then
					seen[cab] = true
					openList(cab)
					local first = not panelSeen[cab]
					panelSeen[cab] = panelSeen[cab] or {}
					for _, b in ipairs(cab:GetChildren()) do
						if b.Name:match("^Btn_") and b:GetAttribute("Built") and not panelSeen[cab][b.Name] then
							panelSeen[cab][b.Name] = true
							if not first then
								local was = b.Color
								b.Color = Color3.fromRGB(255, 196, 60)   -- world colour: the trophy button flashes gold
								UIKit.sfx("star", 1.2, 0.35)
								TweenService:Create(b, TweenInfo.new(1.6), { Color = was }):Play()
							end
						end
					end
				end
			elseif root and not insideBox(cab, root.Position, 1.5) then
				seen[cab] = nil
				if listFor == cab then hide() end
			end
		end
	end
end)
