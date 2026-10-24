--[[ ClientTimerClient (24 Oct 2026): the client's timer badge, drawn on each player's machine.

	Luke's 20 Oct ask ("sad + ticking effects when an app isn't given in time"), option C
	(ui/animation-review/judge/CLIENT-TIMER-OPTIONS.md, mock ui/animation-review/mp4/6-client-timer.mp4).
	The server builds the badge once in each client's speech bubble (ClientsServer timerBadge) and
	publishes the clock as attributes at 4 Hz: PatienceSecs, PatienceLeft (seconds) and Draining
	(patience pauses while you code that job or carry the app). This draws it every frame, so the
	pie is smooth and not a 4 Hz staircase:
	  * more than 8 s left: a pie in one calm colour (INK) that empties clockwise from 12
	  * the last 8 s: a red disc that counts 8, 7 ... 1. The number changing is the tick, so it reads
	    with no motion, no colour vision and no sound (Reduce Motion changes nothing here: the colour
	    is appearance and the 1.06 pop is a small press, both kept by MotionSpec)
	  * each whole second, the one client of YOURS nearest to running out pops and ticks; only you
	    hear it, and the last three ticks are higher
	Rules (stage, count, tick times, who ticks, the guess between draws): ClientMood, tested in
	tests/offline/clientmood.spec.luau. ]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local ClientMood = require(ReplicatedStorage:WaitForChild("ClientMood"))
local Sfx = require(ReplicatedStorage:WaitForChild("Sfx"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local TAG = "SVClient"
local RANGE = 90               -- the bubble's MaxDistance (ClientsServer): past it nothing shows
local TICK_VOLUME = 0.3        -- soft: it plays every second for 8 s

local rigs = {}                -- model -> state

local function add(model)
	if rigs[model] or not model:IsDescendantOf(workspace) then return end
	local st = { left = model:GetAttribute("PatienceLeft"), at = os.clock(), draining = model:GetAttribute("Draining") == true }
	model:GetAttributeChangedSignal("PatienceLeft"):Connect(function()
		st.left, st.at = model:GetAttribute("PatienceLeft"), os.clock()
	end)
	model:GetAttributeChangedSignal("Draining"):Connect(function()
		st.draining, st.at = model:GetAttribute("Draining") == true, os.clock()
	end)
	rigs[model] = st
end
for _, m in ipairs(CollectionService:GetTagged(TAG)) do add(m) end
CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(m) rigs[m] = nil end)

-- the badge's parts, found once (the bubble can replicate a frame after the rig)
local function partsOf(model, st)
	if st.timer and st.timer.Parent then return st end
	local timer = model:FindFirstChild("Timer", true)
	if not timer then return nil end
	local function sweep(half)
		local h = timer:FindFirstChild(half)
		local s = h and h:FindFirstChild("Sweep")
		return h, s and s:FindFirstChildOfClass("UIGradient")
	end
	st.timer = timer
	st.disc = timer:FindFirstChild("Disc")
	st.count = timer:FindFirstChild("Count")
	st.pop = timer:FindFirstChild("Pop")
	st.r, st.rg = sweep("R")
	st.l, st.lg = sweep("L")
	return st
end

local function drawCalm(st, left, secs)
	local a = ClientMood.sweep(left, secs)
	if st.rg then st.rg.Rotation = math.clamp(a, 0, 180) end
	if st.lg then st.lg.Rotation = math.clamp(a - 180, 0, 180) end
end

-- once, the moment 8 s are left: the pie goes, the red disc and the number come
local function turnRed(st)
	st.red = true
	if st.r then st.r.Visible = false end
	if st.l then st.l.Visible = false end
	if st.count then st.count.Visible = true end
	if st.disc then UIKit.tween(st.disc, UIKit.T.ui, { BackgroundColor3 = UIKit.RED }) end
end

local function tick(st, hi)
	Sfx.play(SoundService, "clientTick", { volume = TICK_VOLUME, pitch = hi and 1.25 or 1, life = 2 })
	local sc = st.pop
	if not sc then return end
	local P = ClientMood.POP
	UIKit.tween(sc, P.up, { Scale = P.to })
	task.delay(P.up, function()
		if sc.Parent then UIKit.tween(sc, P.down, { Scale = 1 }) end
	end)
end

RunService.RenderStepped:Connect(function()
	local camPos = camera.CFrame.Position
	local mine = {}
	for model, st in pairs(rigs) do
		st.now = nil
		local secs = model:GetAttribute("PatienceSecs")
		local root = model.Parent and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
		if not (root and secs and st.left) then
			if not model.Parent then rigs[model] = nil end
			continue
		end
		if (root.Position - camPos).Magnitude > RANGE or not partsOf(model, st) or not st.timer.Visible then
			st.prev = nil   -- back in view later: count from there, never a burst of missed ticks
			continue        -- far away, or they have said their line ("Too slow...", "Thanks!")
		end
		local left = ClientMood.estimate(st.left, os.clock() - st.at, st.draining)
		st.now = left
		-- patience never comes back, so red stays red (a guess corrected up cannot flip it)
		if not st.red and ClientMood.stage(left) ~= "calm" then turnRed(st) end
		if st.red then
			-- 24 Oct (live): never counts back up when a guess is corrected (ClientMood.shownCount)
			st.shown = ClientMood.shownCount(st.shown, ClientMood.count(left))
			local n = st.shown
			if n and st.count and st.count.Text ~= tostring(n) then st.count.Text = tostring(n) end
		else
			drawCalm(st, left, secs)
		end
		if model:GetAttribute("ClientOf") == player.UserId then table.insert(mine, { key = model, left = left }) end
	end
	local who = ClientMood.ticker(mine)
	for model, st in pairs(rigs) do
		if st.now then
			-- each whole second ticks once, even if a guess is corrected up and crosses it again;
			-- a long frame that crosses two seconds plays one tick, not two on top of each other
			local last
			for _, t in ipairs(ClientMood.ticks(st.prev or st.now, st.now)) do
				if t.n < (st.lowest or math.huge) then
					st.lowest, last = t.n, t
				end
			end
			if last and model == who then tick(st, last.hi) end
			st.prev = st.now
		end
	end
end)
