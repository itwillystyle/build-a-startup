--[[
	MotionClient -- the things on a building that move.

	WHY. A campus with nothing moving on it reads as a model of a campus. The
	world already has people, cars, a train and birds; the BUILDINGS were
	completely static, so the one object the player spends the whole game
	growing was the one object that never did anything.

	WHY TAGS AND NOT A SCRIPT PER OBJECT. A storey is built and rebuilt
	constantly -- every level bought, every spin-off, every rejoin. Anything
	that holds a reference to a part goes stale. CollectionService hands this
	script the live set instead, and a destroyed part simply stops being in it.

	WHY ON THE CLIENT. Animating on the server replicates a CFrame per part per
	frame to every player; the lag pass measured that at 246 KB/s for animated
	staff alone and moving it client-side took it to 0.5. Motion that is purely
	cosmetic should never touch the wire.

	TAGS
	  SVSpin    spins about its own local axis.  Attributes: Rpm, Axis ("X"|"Y"|"Z")
	  SVPulse   breathes its emissive brightness. Attributes: Hz, Depth
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

--[[ Nothing animates past this. A full server is six towers of up to a hundred
	storeys; without a distance gate this would be thousands of CFrame writes a
	frame for details nobody can resolve. ]]
local RANGE = 190
local RESCAN = 1.0

local spinners, pulsers = {}, {}
local nextScan = 0

--[[ THE RESTING STATE OF EACH PART, REMEMBERED ONCE.

	The first version re-read Transparency and rotation on every rescan, which
	means it read back its OWN last frame as the new baseline. Transparency
	ratcheted a little further open every second until the rack lights were
	fully invisible -- measured 1.000, a light that had deleted itself.

	The same shape of bug as the palette one: a value that is both the input
	and the output of a loop has to be captured once, outside it. Weak keys so
	a destroyed part does not keep its entry alive. ]]
local rest = setmetatable({}, { __mode = "k" })

local function restOf(d, key, value)
	local r = rest[d]
	if not r then
		r = {}
		rest[d] = r
	end
	if r[key] == nil then r[key] = value end
	return r[key]
end

local function axisOf(d)
	local a = d:GetAttribute("Axis")
	if a == "X" then return Vector3.new(1, 0, 0) end
	if a == "Z" then return Vector3.new(0, 0, 1) end
	return Vector3.new(0, 1, 0)
end

local function eye()
	local c = workspace.CurrentCamera
	return c and c.CFrame.Position or Vector3.zero
end

local function rescan()
	local p = eye()
	spinners, pulsers = {}, {}
	for _, d in ipairs(CollectionService:GetTagged("SVSpin")) do
		if d:IsA("BasePart") and (d.Position - p).Magnitude < RANGE then
			spinners[#spinners + 1] = {
				part = d,
				axis = axisOf(d),
				rate = math.rad((d:GetAttribute("Rpm") or 40) * 6),   -- rpm -> rad/s
				base = restOf(d, "rot", d.CFrame.Rotation),
			}
		end
	end
	for _, d in ipairs(CollectionService:GetTagged("SVPulse")) do
		if d:IsA("BasePart") and (d.Position - p).Magnitude < RANGE then
			pulsers[#pulsers + 1] = {
				part = d,
				hz = d:GetAttribute("Hz") or 0.5,
				depth = d:GetAttribute("Depth") or 0.25,
				-- phase off the position, so a wall of screens never blinks in unison
				phase = (d.Position.X * 0.37 + d.Position.Y * 0.11) % 6.283,
				base = restOf(d, "tr", d.Transparency),
			}
		end
	end
end

local spin = 0
RunService.RenderStepped:Connect(function(dt)
	local t = workspace:GetServerTimeNow()
	if t > nextScan then
		nextScan = t + RESCAN
		rescan()
	end

	spin += dt
	for i = #spinners, 1, -1 do
		local s = spinners[i]
		local d = s.part
		if not d.Parent then
			table.remove(spinners, i)
		else
			--[[ Rotate about the part's OWN centre by writing a rotation onto its
				stored position. Driving CFrame directly from the current CFrame
				accumulates float error over a long session and the fan slowly
				drifts off its mounting. ]]
			local pos = d.Position
			d.CFrame = CFrame.new(pos) * s.base * CFrame.fromAxisAngle(s.axis, spin * s.rate)
		end
	end

	for i = #pulsers, 1, -1 do
		local u = pulsers[i]
		local d = u.part
		if not d.Parent then
			table.remove(pulsers, i)
		else
			local k = 0.5 + 0.5 * math.sin(t * u.hz * 6.283 + u.phase)
			d.Transparency = math.clamp(u.base + (1 - u.base) * u.depth * (1 - k), 0, 1)
		end
	end
end)

if player then
	-- a rejoin or a respawn rebuilds the world around you; scan again
	player.CharacterAdded:Connect(function() nextScan = 0 end)
end
