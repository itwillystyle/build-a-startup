-- Gives the pure game modules the Roblox datatypes they build at load (CoreConfig's Color3s).
local roblox = require("@lune/roblox") :: any

--[[ LUNE'S "LOOK AT" CONSTRUCTORS FACE THE WRONG WAY.

	Measured 7 Oct 2026 (Lune 0.10.5): CFrame.lookAt((0,5,10), (0,5,0)) returns a
	LookVector of (0,0,+1) -- AWAY from the target. Roblox returns (0,0,-1), and
	that is the entire point of the constructor. CFrame.new(eye, target) has the
	same fault. identity, Angles and fromMatrix are all correct.

	So every offline test before this fix ran with a camera facing backwards.
	The chase-camera tests survived only because they asserted POSITIONS; the
	first test of orientation -- yaw, tilt, where something sits on screen --
	would have passed here and been wrong in the game.

	Fixed in the instrument rather than worked around in each test: both
	constructors are rebuilt from fromMatrix, which Lune gets right. Everything
	else on CFrame passes straight through to the real implementation, and the
	values returned are real Lune CFrames, so `*`, :Inverse() and friends behave
	exactly as before. ]]
local RealCF = roblox.CFrame

local function lookAt(at, target, up)
	up = up or roblox.Vector3.new(0, 1, 0)
	local look = target - at
	if look.Magnitude < 1e-9 then
		return RealCF.new(at)
	end
	look = look.Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		-- looking straight along `up`: any perpendicular will do, as in Roblox
		right = look:Cross(roblox.Vector3.new(0, 0, 1))
	end
	right = right.Unit
	local trueUp = right:Cross(look)
	return RealCF.fromMatrix(at, right, trueUp)
end

local CF = setmetatable({
	lookAt = lookAt,
	new = function(...)
		local a, b = ...
		if select("#", ...) == 2 and typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			return lookAt(a, b)
		end
		return RealCF.new(...)
	end,
}, { __index = RealCF })

local SHIM = { CFrame = CF }
for _, k in { "Color3", "Vector3", "CFrame", "UDim2", "UDim", "Enum", "Font", "BrickColor", "NumberRange", "ColorSequence", "NumberSequence" } do
	local v = SHIM[k] or roblox[k]
	pcall(function() (getfenv(0) :: any)[k] = v end)
	_G[k] = v
end

-- Prove the fix at load, so a Lune upgrade that changes the behaviour again
-- fails loudly here instead of silently inverting every orientation test.
do
	local cf = CF.lookAt(roblox.Vector3.new(0, 5, 10), roblox.Vector3.new(0, 5, 0))
	local lv = cf.LookVector
	assert(lv.Z < -0.999 and math.abs(lv.X) < 1e-6,
		"roblox_globals: CFrame.lookAt does not face its target; got LookVector " .. tostring(lv))
	local stepped = cf * roblox.Vector3.new(0, 0, -1)
	assert(math.abs(stepped.Z - 9) < 1e-6, "roblox_globals: -Z is not forward after the lookAt fix")
end
return nil
