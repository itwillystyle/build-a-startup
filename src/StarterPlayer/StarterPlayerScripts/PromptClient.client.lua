--[[ PromptClient (11 Oct 2026): every "press E" prompt, drawn in the game's own style.

	Roblox's default prompt is a dark grey slab in Gotham. Next to the paper cards,
	ink outlines and Fredoka of everything else, it was the one piece of UI that
	looked like a different game (the UI audit, 11 Oct: four visual languages on
	one screen). The 13 prompts in the game ("Take the lift", "Recruit", "UPGRADE",
	"WRITE CODE", "Drive"...) keep their server logic untouched: this script only
	switches each one to Style = Custom on this client and draws it.

	The card: paper, a 2 px ink-soft outline and a lip (UIKit.card); an ink key cap
	(E, or the gamepad button) on the left; the thing in small muted Nunito
	(ObjectText) over the action in Fredoka (ActionText). A prompt you hold fills a
	green bar along its bottom while you hold. On touch, or any clickable prompt,
	the whole card is the button (44 px tall at least: DESIGN.md's tap rule). ]]
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local OneVoice = require(ReplicatedStorage:WaitForChild("OneVoice"))   -- 24 Oct: one instruction at a time (rule A)
local player = Players.LocalPlayer

local HEIGHT = 58
local CAP = 38
local PAD = 10

-- take over every prompt this client can see, now and later
local function own(prompt)
	if prompt:IsA("ProximityPrompt") and prompt.Style == Enum.ProximityPromptStyle.Default then
		prompt.Style = Enum.ProximityPromptStyle.Custom
	end
end
for _, d in ipairs(workspace:GetDescendants()) do own(d) end
workspace.DescendantAdded:Connect(own)

local function keyText(prompt, inputType)
	if inputType == Enum.ProximityPromptInputType.Gamepad then
		local name = prompt.GamepadKeyCode.Name
		return (name:gsub("^Button", ""))
	end
	local name = prompt.KeyboardKeyCode.Name
	return #name <= 3 and name or name:sub(1, 3)
end

local function textWidth(text, size, font)
	return TextService:GetTextSize(text, size, font, Vector2.new(1000, 100)).X
end

local shown = {}   -- prompt -> { gui, cleanup }

local function hide(prompt)
	local s = shown[prompt]
	if not s then return end
	shown[prompt] = nil
	for _, c in ipairs(s.conns) do c:Disconnect() end
	s.gui:Destroy()
end

local function show(prompt, inputType)
	hide(prompt)
	local touch = inputType == Enum.ProximityPromptInputType.Touch
	local bb = Instance.new("BillboardGui")
	bb.Name = "Prompt"
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Active = true
	bb.ResetOnSpawn = false
	bb.Adornee = prompt.Parent
	bb.SizeOffset = Vector2.new(0, 0)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)

	local card = UIKit.card(bb, { Name = "Card", Size = UDim2.fromScale(1, 1) }, { radius = UIKit.RADIUS.md })
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = card

	local capW = touch and 0 or CAP
	if not touch then
		local cap = Instance.new("Frame")
		cap.Name = "KeyCap"
		cap.AnchorPoint = Vector2.new(0, 0.5)
		cap.Position = UDim2.new(0, PAD, 0.5, -2)
		cap.Size = UDim2.fromOffset(CAP, CAP)
		cap.BackgroundColor3 = UIKit.INK
		cap.BorderSizePixel = 0
		cap.Parent = card
		Instance.new("UICorner", cap).CornerRadius = UDim.new(0, UIKit.RADIUS.sm)
		UIKit.label(cap, keyText(prompt, inputType), UIKit.TYPE.label, UIKit.TEXT, {
			Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
		}, UIKit.HEAD)
	end
	local left = PAD + capW + (touch and 4 or 10)
	local object = UIKit.label(card, prompt.ObjectText, UIKit.TYPE.caption, UIKit.MUTED_TEXT, {
		Name = "Object", Position = UDim2.new(0, left, 0, 7), Size = UDim2.new(1, -left - PAD, 0, 18),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local action = UIKit.label(card, prompt.ActionText, UIKit.TYPE.title, UIKit.INK, {
		Name = "Action", Position = UDim2.new(0, left, 0, 23), Size = UDim2.new(1, -left - PAD, 0, 26),
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, UIKit.HEAD)

	-- the hold: a green bar along the bottom edge, inside the lip
	local bar
	if prompt.HoldDuration > 0 then
		bar = Instance.new("Frame")
		bar.Name = "Hold"
		bar.AnchorPoint = Vector2.new(0, 1)
		bar.Position = UDim2.new(0, 6, 1, -6)
		bar.Size = UDim2.new(0, 0, 0, 5)
		bar.BackgroundColor3 = UIKit.GREEN
		bar.BorderSizePixel = 0
		bar.Parent = card
		Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
	end

	local function resize()
		object.Text, action.Text = prompt.ObjectText, prompt.ActionText
		local w = math.max(textWidth(prompt.ActionText, UIKit.TYPE.title, UIKit.HEAD),
			textWidth(prompt.ObjectText, UIKit.TYPE.caption, UIKit.HEAD))   -- Fredoka runs a touch wider than Nunito: the card errs wide
		local total = math.clamp(left + w + PAD + 6, 150, 340)
		bb.Size = UDim2.fromOffset(total, math.max(HEIGHT, 44))
		bb.SizeOffset = Vector2.new(prompt.UIOffset.X / total, prompt.UIOffset.Y / HEIGHT)
	end
	resize()

	local conns = {}
	table.insert(conns, prompt:GetPropertyChangedSignal("ActionText"):Connect(resize))
	table.insert(conns, prompt:GetPropertyChangedSignal("ObjectText"):Connect(resize))

	local holdTween
	table.insert(conns, prompt.PromptButtonHoldBegan:Connect(function()
		if not bar then return end
		bar.Size = UDim2.new(0, 0, 0, 5)
		holdTween = TweenService:Create(bar, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), { Size = UDim2.new(1, -12, 0, 5) })   -- motion: progress
		holdTween:Play()
	end))
	table.insert(conns, prompt.PromptButtonHoldEnded:Connect(function()
		if holdTween then holdTween:Cancel() holdTween = nil end
		if bar then TweenService:Create(bar, TweenInfo.new(0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Size = UDim2.new(0, 0, 0, 5) }):Play() end
	end))
	-- pressed: a short press-in, no bounce (DESIGN.md: overshoot is for rewards)
	table.insert(conns, prompt.Triggered:Connect(function()
		uiScale.Scale = 0.94
		TweenService:Create(uiScale, TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end))

	-- the whole card is the button on touch (and for a mouse when the prompt allows a click)
	if touch or prompt.ClickablePrompt then
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = 10
		hit.Parent = card
		local down = false
		table.insert(conns, hit.InputBegan:Connect(function(input)
			if (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1)
				and input.UserInputState ~= Enum.UserInputState.Change then
				down = true
				prompt:InputHoldBegin()
			end
		end))
		table.insert(conns, hit.InputEnded:Connect(function(input)
			if down and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1) then
				down = false
				prompt:InputHoldEnd()
			end
		end))
	end

	bb.Parent = player:WaitForChild("PlayerGui")
	shown[prompt] = { gui = bb, conns = conns }
	-- arrive: a quick fade and rise, Quint out
	card.Position = UDim2.new(0, 0, 0, 6)
	TweenService:Create(card, TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = UDim2.new(0, 0, 0, 0) }):Play()
end

--[[ 24 Oct (one instruction, rule A; ui/animation-review/judge/ONE-INSTRUCTION-OPTIONS.md): a prompt
	is drawn only when it is not a second voice (OneVoice.prompt). The playtest's 7:44: a floating
	UPGRADE by the laptop while the HUD said HOLD TO CODE and the card said Drive.
	  quiet: HOLD TO CODE / GIVE, the HUD button is their look; E still works (nothing drawn)
	  off:   an UPGRADE / BUILD that is not the goal's own pad, or anything else while a button is
	         up. Its reach goes to 0 on THIS client only, so the camera cannot hand E to an ask
	         nobody can see; the server never rewrites a prompt's reach after making it, so the
	         saved reach comes back intact. Every ask keeps its click on the part (alsoClickable).
	  draw:  as before ]]
local live = setmetatable({}, { __mode = "k" })  -- prompt -> inputType, while the engine shows it
local reach = setmetatable({}, { __mode = "k" }) -- prompt -> its own reach, while we hold it at 0
local GOAL_NEAR = 10                             -- studs: a prompt this close to the goal is its target

local function posOf(inst)
	local par = inst.Parent
	if not par then return nil end
	if par:IsA("BasePart") then return par.Position end
	if par:IsA("Attachment") then return par.WorldPosition end
	if par:IsA("Model") then return par:GetPivot().Position end
	return nil
end
local function decide(prompt)
	local voice = player:GetAttribute("OneVoice")
	local pick = { voice = voice }
	local goal = player:GetAttribute("ObjectivePos")
	local at = posOf(prompt)
	local near = typeof(goal) == "Vector3" and at ~= nil
		and Vector3.new(at.X - goal.X, 0, at.Z - goal.Z).Magnitude <= GOAL_NEAR
	return OneVoice.prompt(pick, OneVoice.promptRole(prompt.ActionText), near)
end
local function setOff(prompt, off)
	if off and reach[prompt] == nil then
		reach[prompt] = prompt.MaxActivationDistance
		prompt.MaxActivationDistance = 0
	elseif not off and reach[prompt] ~= nil then
		prompt.MaxActivationDistance = reach[prompt]
		reach[prompt] = nil
	end
end
local function apply(prompt)
	local d = decide(prompt)
	setOff(prompt, d == "off")
	if d == "draw" and live[prompt] ~= nil then
		if not shown[prompt] then show(prompt, live[prompt]) end
	else
		hide(prompt)
	end
end
local function reapply()
	for prompt in pairs(reach) do if prompt.Parent then apply(prompt) end end
	for prompt in pairs(live) do if prompt.Parent then apply(prompt) end end
end
player:GetAttributeChangedSignal("OneVoice"):Connect(reapply)
player:GetAttributeChangedSignal("ObjectivePos"):Connect(reapply)

ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
	if prompt.Style ~= Enum.ProximityPromptStyle.Custom then return end
	live[prompt] = inputType
	apply(prompt)
end)
ProximityPromptService.PromptHidden:Connect(function(prompt)
	live[prompt] = nil
	hide(prompt)
end)
