--[[ Moment (v8, 11 Oct 2026, UI de-slop step 4): how the game says "you earned that".

	Four rewards get a designed sequence: a hire delivered (TalentRevealClient),
	a level-up (HudClient.hqBanner), going public (IpoClient) and a spin-off
	(HudClient.spinCeremony). Before this each one improvised: the level-up
	rained 40 confetti pieces over the whole screen every time, the IPO number
	just appeared, and routine banners used the same overshoot as the rewards,
	so nothing felt bigger than anything else. They now share four beats:

	  1. HIT     the sound, and a ring that opens behind the card (ring)
	  2. ENTER   the card arrives with the one overshoot the game allows (enter)
	  3. PAYOFF  the number counts up instead of appearing (countUp)
	  4. LAND    the reward goes where it lives: money into the cash coin
	             (_G.SVCoinStream), a hire into the Index (TalentRevealClient)

	Confetti is a burst from the card (burst), sized by the moment. Only going
	public, once per company, also rains over the whole screen.

	Everything else in the HUD is calm: Quint ease-out, no overshoot. The
	overshoot (EasingStyle.Back) is allowed only on a line marked "reward";
	tests/offline/uistyle.spec.luau checks it. ]]
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local UIKit = require(RS:WaitForChild("UIKit"))

local Moment = {}

-- a point in screen space (AbsolutePosition space) -> an offset inside `gui`
local function local2(gui, abs)
	local o = gui.AbsolutePosition
	return UDim2.new(0, abs.X - o.X, 0, abs.Y - o.Y)
end

function Moment.centreOf(frame)
	return frame.AbsolutePosition + frame.AbsoluteSize / 2
end

-- 2. the one overshoot: scale `sc` (a UIScale) from `from` to 1
function Moment.enter(sc, from, seconds)
	sc.Scale = from or 0.6
	-- 23 Oct: through the motion layer; under Reduce Motion a big pop lands at once, a small one still plays
	UIKit.tween(sc, seconds or 0.45, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)   -- reward
end

-- 1. a ring that opens behind the card and fades: the "hit"
function Moment.ring(gui, at, colour, size)
	if UIKit.reducedMotion() then return end   -- 23 Oct: Reduce Motion: no expanding ring
	size = size or 260
	local r = Instance.new("Frame")
	r.Name = "MomentRing"
	r.AnchorPoint = Vector2.new(0.5, 0.5)
	r.Position = local2(gui, at)
	r.Size = UDim2.new(0, size * 0.35, 0, size * 0.35)
	r.BackgroundTransparency = 1
	r.ZIndex = 0
	r.Parent = gui
	Instance.new("UICorner", r).CornerRadius = UDim.new(1, 0)
	local st = Instance.new("UIStroke", r)
	st.Color = colour or UIKit.GOLD
	st.Thickness = 10
	local info = TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	TweenService:Create(r, info, { Size = UDim2.new(0, size, 0, size) }):Play()
	TweenService:Create(st, info, { Transparency = 1, Thickness = 2 }):Play()
	task.delay(0.65, function() r:Destroy() end)
end

-- confetti that bursts out of a point and falls a short way: it stays around the card
function Moment.burst(gui, at, count, spread)
	if UIKit.reducedMotion() then return end   -- 23 Oct: Reduce Motion skips particles
	spread = spread or 220
	local colours = { UIKit.GOLD, UIKit.GREEN, UIKit.BLUE, UIKit.ORANGE, UIKit.PINK }
	local base = local2(gui, at)
	for i = 1, count or 24 do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = colours[(i % #colours) + 1]
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.new(0, math.random(7, 11), 0, math.random(9, 15))
		f.Rotation = math.random(0, 360)
		f.Position = base
		f.ZIndex = 30
		f.Parent = gui
		local a = math.random() * math.pi * 2
		local r = spread * (0.45 + math.random() * 0.55)
		local out = base + UDim2.new(0, math.cos(a) * r, 0, math.sin(a) * r * 0.6 - 30)
		TweenService:Create(f, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Position = out, Rotation = f.Rotation + math.random(-180, 180) }):Play()
		task.delay(0.45, function()
			if not f.Parent then return end
			TweenService:Create(f, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = out + UDim2.new(0, math.random(-20, 20), 0, 90 + math.random(0, 60)),
				BackgroundTransparency = 1, Rotation = f.Rotation + math.random(-200, 200),
			}):Play()
		end)
		task.delay(1.3, function() f:Destroy() end)
	end
end

-- 3. a number that counts up to `to` over `seconds` (Quint out: fast, then it settles)
function Moment.countUp(label, from, to, fmt, seconds)
	seconds = seconds or 0.9
	local t0 = os.clock()
	local conn
	label.Text = fmt(from)
	conn = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - t0) / seconds, 0, 1)
		local e = 1 - (1 - k) ^ 5
		label.Text = fmt(from + (to - from) * e)
		if k >= 1 or not label.Parent then conn:Disconnect() end
	end)
end

-- 4. money lands in the cash: HudClient's coin stream, from a point on screen
function Moment.landMoney(at, coins)
	local stream = rawget(_G, "SVCoinStream")
	if type(stream) == "function" then stream(at, coins or 12) end
end

return Moment
