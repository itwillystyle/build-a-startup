-- Gives the pure game modules the Roblox datatypes they build at load (CoreConfig's Color3s).
local roblox = require("@lune/roblox") :: any
for _, k in { "Color3", "Vector3", "CFrame", "UDim2", "UDim", "Enum", "Font", "BrickColor", "NumberRange", "ColorSequence", "NumberSequence" } do
	pcall(function() (getfenv(0) :: any)[k] = roblox[k] end)
	_G[k] = roblox[k]
end
return nil
