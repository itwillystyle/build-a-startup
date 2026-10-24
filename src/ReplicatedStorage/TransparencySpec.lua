--[[ TransparencySpec (24 Oct 2026): Roblox's Background Transparency setting. Pure.

	GuiService.PreferredTransparency is the player's choice in Roblox's settings menu: 1 (the
	default) means "draw backgrounds as the game designed them", 0 means "make them fully solid
	so I can read the text". Roblox's accessibility guide
	(create.roblox.com/docs/production/publishing/accessibility):
	  "Multiplying a UI element's BackgroundTransparency with PreferredTransparency is the
	  recommended way to use this setting", and the change signal is
	  GuiService:GetPropertyChangedSignal("PreferredTransparency")
	(create.roblox.com/docs/reference/engine/classes/GuiService: read only, not replicated, so
	only a LocalScript sees the player's own value).

	The rules:
	  * bg(designed, preferred) = designed * preferred
	  * a solid background (0) stays solid, and a frame with NO background (1) stays without one:
	    1 * 0.5 would paint a box behind every layout frame and label
	  * only see-through surfaces (0 < t < 1) follow the setting (follows)
	  * the player attribute ForcePreferredTransparency (a number) beats the real setting, so the
	    doctor and Luke can test it without the settings menu (resolve)
	  * a live change only moves a surface that is at rest on its designed value; one mid-fade or
	    faded out is left to whatever is fading it (reapply)
	UIKit.preferredTransparency() / UIKit.translucent() apply this on the client.
	Tested by tests/offline/transparency.spec.luau. ]]
local TransparencySpec = {}

-- Roblox stores BackgroundTransparency as a 32-bit float (0.15 reads back as 0.1500000059604645)
local EPS = 1e-3

local function clamp01(x) return math.clamp(x, 0, 1) end

function TransparencySpec.bg(designed, preferred)
	if designed >= 1 then return 1 end
	if designed <= 0 then return 0 end
	if type(preferred) ~= "number" then preferred = 1 end
	return designed * clamp01(preferred)
end

function TransparencySpec.follows(designed)
	return type(designed) == "number" and designed > 0 and designed < 1
end

-- setting: GuiService.PreferredTransparency (or nil if unreadable); forced: the player attribute
function TransparencySpec.resolve(setting, forced)
	if type(forced) == "number" then return clamp01(forced) end
	if type(setting) == "number" then return clamp01(setting) end
	return 1
end

-- current: the frame's BackgroundTransparency now; was/now: the old and new preferred value.
-- Returns the new value to set, or nil to leave the frame alone.
function TransparencySpec.reapply(current, designed, was, now)
	if math.abs(current - TransparencySpec.bg(designed, was)) > EPS then return nil end
	return TransparencySpec.bg(designed, now)
end

return TransparencySpec
