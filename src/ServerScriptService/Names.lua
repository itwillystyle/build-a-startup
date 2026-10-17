--[[ Names (16 Oct 2026): the company name a brand-new save starts with. Pure.

	The naming box used to open in the first minute, with the keyboard over the
	screen for 14 s (Luke's recording, 0:34-0:48). Now a new company gets a name
	from these lists, and the player can rename it later by tapping the sign.
	Our own words only, so nothing here needs the text filter.
	Tested by tests/offline/names.spec.luau. ]]
local Names = {}

local FIRST = { "Rocket", "Pixel", "Byte", "Turbo", "Nova", "Bright", "Cloud", "Spark", "Orbit", "Lucky",
	"Quantum", "Bolt", "Echo", "Neon", "Swift", "Atlas", "Comet", "Maple", "Zippy", "Cosmo", "Jolly", "Lemon" }
local SECOND = { "Labs", "Works", "Apps", "Studio", "Code", "Bits", "Logic", "Systems", "Dynamics", "Ventures",
	"Media", "Tech", "Soft", "Hub", "Forge", "Garage", "Digital", "Games", "Cloud", "Mind" }

function Names.generate(seed)
	local x = math.abs(math.floor(seed or 0)) % 2147483647
	x = (x * 48271) % 2147483647
	local a = FIRST[1 + x % #FIRST]
	x = (x * 48271) % 2147483647
	local b = SECOND[1 + x % #SECOND]
	if a == b then b = "Labs" end
	return a .. " " .. b
end

return Names
