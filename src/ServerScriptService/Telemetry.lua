--[[
	BUILD A STARTUP -- telemetry (funnel only)
	ModuleScript in ServerScriptService named "Telemetry".

	Ported from the card shop's Telemetry.lua. Two jobs:
	  1. Fire onboarding-funnel steps and custom events into Roblox's
	     AnalyticsService so they show in the Creator Dashboard. Every row is
	     tagged mobile / desktop / unknown -- the phone pass needs a before
	     and after, and Roblox's 2026 discovery scores D1 / D2-7 / D8-28.
	  2. Print the same facts to Output so they are visible in Studio.

	Nothing here touches a DataStore and nothing here stores text a player
	typed. Every analytics call is wrapped: if the API is off, the game
	runs exactly the same.

	TWO FUNNELS, read them differently:
	  - The ONBOARDING funnel is once per user FOR LIFE. Roblox keeps only
	    the first time a user ever reaches a step. It answers "where do new
	    players fall out?" and nothing else.
	  - The "session" custom funnel is once per JOIN (keyed by a GUID minted
	    at join). It answers "do returning players still reach X?".
	Studio records NOTHING to the dashboard -- only the [FUNNEL] prints.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")

local Telemetry = {}

-- In the order the game forces them. The gap between two steps is the
-- thing you actually fix.
local FUNNEL = {
	"joined",        -- 1  platform known (or 10s fallback)
	"play",          -- 2  pressed PLAY on the menu
	"first_code",    -- 3  clicked WRITE CODE once
	"first_ship",    -- 4  three clicks: the To-Do App shipped
	"first_hire",    -- 5  the free intern
	"first_wing",    -- 6  built a wing on the lot
	"first_product", -- 7  a market picked, a product launched
	"first_rival",   -- 8  felt a rival launch (share pressure)
	"ten_minutes",   -- 9  still here at 10:00
}
local STEP_INDEX = {}
for n, name in ipairs(FUNNEL) do STEP_INDEX[name] = n end

local sessions = {}   -- userId -> { joined, platform, steps = { name = true }, id }

local function fields(s)
	return { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = (s and s.platform) or "unknown" }
end

function Telemetry.joined(player)
	local s = { joined = os.clock(), platform = "unknown", steps = {},
		id = HttpService:GenerateGUID(false) }
	sessions[player.UserId] = s
	-- step 1 waits for the client's platform report; a step logged as
	-- "unknown" can never be re-tagged (the onboarding funnel keeps only
	-- the first instance). 10s fallback for a client that never reports.
	task.delay(10, function()
		if sessions[player.UserId] == s and player.Parent then
			Telemetry.step(player, "joined")
		end
	end)
	task.delay(600, function()
		if sessions[player.UserId] == s and player.Parent then
			Telemetry.step(player, "ten_minutes")
		end
	end)
end

-- the client reports this once, right after it loads
function Telemetry.platform(player, isMobile)
	local s = sessions[player.UserId]
	if not s then return end
	s.platform = isMobile and "mobile" or "desktop"
	Telemetry.step(player, "joined")
end

function Telemetry.step(player, name)
	local s = sessions[player.UserId]
	local n = STEP_INDEX[name]
	if not s or not n or s.steps[name] then return end
	-- v2.5.1: nothing is logged before step 1; early steps wait for it
	if name ~= "joined" and not s.steps.joined then
		s.queued = s.queued or {}
		for _, q in ipairs(s.queued) do if q == name then return end end
		table.insert(s.queued, name)
		return
	end
	s.steps[name] = true
	if name == "joined" and s.queued then
		local q = s.queued
		s.queued = nil
		task.defer(function() for _, qn in ipairs(q) do Telemetry.step(player, qn) end end)
	end
	print(string.format("[FUNNEL] %s  %d/%d %s  (%s, %ds)",
		player.Name, n, #FUNNEL, name, s.platform, math.floor(os.clock() - s.joined)))
	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, n, name, fields(s))
	end)
	pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, "session", s.id, n, name, fields(s))
	end)
end

-- extra is an ORDERED list of {key, value} pairs: pairs() order is not
-- stable, and a fact that wanders between dashboard columns is unusable.
function Telemetry.event(player, name, value, extra)
	local s = sessions[player.UserId]
	local f = fields(s)
	if type(extra) == "table" then
		local slots = { Enum.AnalyticsCustomFieldKeys.CustomField02.Name, Enum.AnalyticsCustomFieldKeys.CustomField03.Name }
		for k, pair in ipairs(extra) do
			if slots[k] and type(pair) == "table" then
				f[slots[k]] = tostring(pair[1]) .. "=" .. tostring(pair[2])
			end
		end
	end
	pcall(function()
		AnalyticsService:LogCustomEvent(player, name, tonumber(value) or 1, f)
	end)
end

function Telemetry.left(player)
	local s = sessions[player.UserId]
	if not s then return end
	local secs = math.floor(os.clock() - s.joined)
	local reached = 0
	for _ in pairs(s.steps) do reached += 1 end
	print(string.format("[LEFT] %s -- %ds, %d/%d funnel steps, %s", player.Name, secs, reached, #FUNNEL, s.platform))
	pcall(function()
		AnalyticsService:LogCustomEvent(player, "session_end", secs, {
			[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = s.platform,
			[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = "steps=" .. reached,
		})
	end)
	sessions[player.UserId] = nil
end

return Telemetry
