--[[ Movement (10 Oct 2026): where each player could actually have got to.

	A player's client owns their character's physics, so the server only sees where
	the client SAYS it is. The exploit audit (9 Oct) found three gains that read that
	position: delivering a hire (the drop-off radius), poaching (12 studs from the
	victim) and the lift (standing near it). A teleport exploit wins all three.

	The server samples every player's root 10 times a second and judges each move
	over the last half second: horizontally (falling is not teleporting) no further
	than the character's own WalkSpeed allows, x FACTOR, + SLACK for lag bursts.
	A move past that is a FLAG. Nothing kicks anyone: a false alarm (a car bump, a
	lag spike) must cost a few studs, never a game.
	  * during a carry, TalentDrop pulls you back to where you were (onFlag)
	  * `check(player)` judges the move NOW and is false for MEMORY seconds after a
	    flag: the delivery, the poach and the lift each ask it before paying out

	The game's own moves are not flags. A SERVER script setting the root's CFrame
	fires its CFrame-changed signal on the server; a client's move arrives as a
	physics update, which does not. So every PivotTo the game does (respawn, the
	lift, homes, HQ upgrades, spin-offs, Studio scenarios) resets the history by
	itself, including ones added later. Seated players (cars) are not judged.
	`judge` is pure (tests/offline/movement.spec.luau). ]]
local Movement = {}

Movement.HZ = 10
Movement.WINDOW = 0.5      -- seconds a move is judged over
Movement.FACTOR = 1.6      -- x the character's own WalkSpeed
Movement.SLACK = 8         -- studs: replication arrives in bursts
Movement.MEMORY = 2        -- seconds a flag counts against you
Movement.MIN_SPEED = 16

-- pure: is a move from (x1, z1) to (x2, z2) over dt seconds more than walkSpeed allows?
-- -> tooFar (bool), distance, allowance
function Movement.judge(x1, z1, x2, z2, dt, walkSpeed)
	local dx, dz = x2 - x1, z2 - z1
	local d = math.sqrt(dx * dx + dz * dz)
	local allow = math.max(walkSpeed or 0, Movement.MIN_SPEED) * math.max(dt, 0) * Movement.FACTOR + Movement.SLACK
	return d > allow, d, allow
end

local track = {}          -- userId -> { hist = { { t, cf } }, flaggedAt, flags }
local listeners = {}

local function reset(player)
	local tr = track[player.UserId]
	if tr then tr.hist = {} end
end
Movement.teleported = reset

function Movement.trusted(player)
	local tr = track[player.UserId]
	return not (tr and tr.flaggedAt and os.clock() - tr.flaggedAt < Movement.MEMORY)
end

function Movement.onFlag(fn) table.insert(listeners, fn) end

local function watchCharacter(player, char)
	reset(player)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if not root then return end
	-- fires for server-script moves only: see the header
	root:GetPropertyChangedSignal("CFrame"):Connect(function() reset(player) end)
end

-- judge one player's latest move now; flags (and tells the listeners) if it was too far
local function judgePlayer(player, now)
	local tr = track[player.UserId]
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (tr and root and hum and hum.Health > 0) then return end
	if hum.SeatPart then
		tr.hist = {}                      -- driving: a car is fast on purpose
		return
	end
	table.insert(tr.hist, { t = now, cf = root.CFrame })
	while #tr.hist > 1 and now - tr.hist[1].t > Movement.WINDOW + 0.15 do table.remove(tr.hist, 1) end
	local first = tr.hist[1]
	if #tr.hist < 2 then return end
	local p1, p2 = first.cf.Position, root.Position
	local tooFar, d = Movement.judge(p1.X, p1.Z, p2.X, p2.Z, now - first.t, hum.WalkSpeed)
	if tooFar then
		tr.flaggedAt, tr.flags = now, (tr.flags or 0) + 1
		local back = first.cf
		tr.hist = {}
		for _, fn in ipairs(listeners) do
			task.spawn(fn, player, { distance = d, seconds = now - first.t, back = back })
		end
	end
end

--[[ For a GAIN (the delivery, the poach, the lift): judge the move right now, then
	answer. Waiting for the 10 Hz sampler was a race the delivery won: measured 10
	Oct, a client teleport onto the drop-off delivered at 0 s and was flagged after. ]]
function Movement.check(player)
	judgePlayer(player, os.clock())
	return Movement.trusted(player)
end

local function step()
	local now = os.clock()
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		judgePlayer(player, now)
	end
end

function Movement.init()
	if Movement.started then return end
	Movement.started = true
	local Players = game:GetService("Players")
	local function added(player)
		track[player.UserId] = { hist = {} }
		player.CharacterAdded:Connect(function(c) watchCharacter(player, c) end)
		if player.Character then task.spawn(watchCharacter, player, player.Character) end
	end
	Players.PlayerAdded:Connect(added)
	for _, p in ipairs(Players:GetPlayers()) do added(p) end
	Players.PlayerRemoving:Connect(function(p) track[p.UserId] = nil end)
	local acc = 0
	game:GetService("RunService").Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 1 / Movement.HZ then return end
		acc = 0
		step()
	end)
end

return Movement
