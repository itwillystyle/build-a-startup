--[[
	BUILD A STARTUP -- telemetry (the player loop, v2: 9 Oct 2026)
	ModuleScript in ServerScriptService named "Telemetry". Other server modules
	require it directly; every analytics call is wrapped, so with the API off the
	game runs exactly the same.

	What reaches the Creator Dashboard (published servers only; Studio sends
	nothing, it prints the same facts instead):
	  1. The ONBOARDING funnel: once per user FOR LIFE, Roblox keeps only the
	     first time a user reaches a step. v2 follows the HQ ladder, because
	     each level needs the one before it: a skipped step auto-completes the
	     earlier ones, so a step that can come in any order (the old
	     first_product, first_rival, ten_minutes, first_wing) lies. Those are
	     session milestones now. Read the funnel from the v2 publish date on.
	  2. Session milestones: custom event "m_<name>" once per JOIN, value =
	     seconds into the session. Against session_end's count, the share of
	     sessions that launch, recruit, get chased, deliver, build.
	  3. carry_start / carry_end: every recruit run by tier, and how it ended
	     (signed, caught, timeout, walked_off, poached, left, no_seat, error);
	     value = seconds. The chase's live win rate, by tier.
	  4. Economy: every cash source and sink, currency "Cash", the kind as the
	     item SKU. Income and code taps arrive every second, so they are summed
	     and logged every 5 minutes and on leave (AnalyticsService allows about
	     120 + 20 per player calls a minute).

	Custom fields stay low-cardinality (Roblox keeps ~20 values per field):
	platform, tier, outcome. Nothing here stores text a player typed.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Telemetry = {}

local STUDIO = RunService:IsStudio()

-- In the order the game forces them. The gap between two steps is the
-- thing you actually fix.
local FUNNEL = {
	"joined",      -- 1  platform known (or 10s fallback)
	"play",        -- 2  pressed PLAY on the menu
	"first_code",  -- 3  clicked WRITE CODE once
	"first_ship",  -- 4  three clicks: the To-Do App shipped
	"first_hire",  -- 5  the free intern
	"hq_2",        -- 6  the HQ ladder: each level needs the one before
	"hq_3",        -- 7
	"hq_4",        -- 8
	"hq_5",        -- 9
	"public",      -- 10 rang the bell (needs the top of the ladder)
	"spinoff",     -- 11 started the next company (needs public)
}
local STEP_INDEX = {}
for n, name in ipairs(FUNNEL) do STEP_INDEX[name] = n end
Telemetry.FUNNEL = FUNNEL

local SHOP = { floor = true, room = true, furniture = true, home = true, car = true, refund = true }
local TIMED = { daily = true, offline = true }
local SUMMED = { income = true, code = true }
local FLUSH_EVERY = 300

local sessions = {}   -- userId -> { joined, platform, steps = { name = true }, marks = { name = true }, id, sums }

local function fields(s)
	return { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = (s and s.platform) or "unknown" }
end

local function balanceOf(player)
	local ls = player:FindFirstChild("leaderstats")
	local c = ls and ls:FindFirstChild("Cash")
	return c and c.Value or 0
end

local function logMoney(player, flow, amount, kind)
	local tt = SHOP[kind] and "Shop" or (TIMED[kind] and "TimedReward" or "Gameplay")
	if STUDIO then print(("[MONEY] %s %s %s %d"):format(player.Name, flow, kind, amount)) end
	pcall(function()
		AnalyticsService:LogEconomyEvent(player,
			flow == "sink" and Enum.AnalyticsEconomyFlowType.Sink or Enum.AnalyticsEconomyFlowType.Source,
			"Cash", amount, balanceOf(player), Enum.AnalyticsEconomyTransactionType[tt].Name, kind)
	end)
end

local function flush(player, s)
	for kind, amount in pairs(s.sums) do
		if amount > 0 then logMoney(player, "source", amount, kind) end
	end
	s.sums = {}
end

function Telemetry.joined(player)
	local s = { joined = os.clock(), platform = "unknown", steps = {}, marks = {}, sums = {},
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
			Telemetry.mark(player, "ten_minutes")
		end
	end)
	task.spawn(function()
		while true do
			task.wait(FLUSH_EVERY)
			if sessions[player.UserId] ~= s then return end
			flush(player, s)
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
end

--[[ A returning player is already somewhere up the ladder. Log the furthest
	step they hold (Roblox completes the ones before it), so the funnel counts
	the players who got far, not only the ones who got far THIS time. ]]
function Telemetry.reached(player, st)
	if not st then return end
	-- a spin-off needs the top of the ladder and the bell first, and every new
	-- company starts back at the garage, so a spun-off player has done it all once
	local spun = (st.spinoffs or 0) > 0
	if st.shipped or spun then Telemetry.step(player, "first_code"); Telemetry.step(player, "first_ship") end
	if (st.staff or 0) > 0 or spun then Telemetry.step(player, "first_hire") end
	for lv = 2, spun and 5 or math.min(st.hq or 1, 5) do Telemetry.step(player, "hq_" .. lv) end
	if st.listed or spun then Telemetry.step(player, "public") end
	if spun then Telemetry.step(player, "spinoff") end
end

-- extra is an ORDERED list of {key, value} pairs: pairs() order is not
-- stable, and a fact that wanders between dashboard columns is unusable.
function Telemetry.event(player, name, value, extra)
	local s = sessions[player.UserId]
	local f = fields(s)
	local shown = {}
	if type(extra) == "table" then
		local slots = { Enum.AnalyticsCustomFieldKeys.CustomField02.Name, Enum.AnalyticsCustomFieldKeys.CustomField03.Name }
		for k, pair in ipairs(extra) do
			if slots[k] and type(pair) == "table" then
				f[slots[k]] = tostring(pair[1]) .. "=" .. tostring(pair[2])
				table.insert(shown, f[slots[k]])
			end
		end
	end
	if STUDIO then print(("[EVENT] %s %s %s %s"):format(player.Name, name, tostring(value), table.concat(shown, " "))) end
	pcall(function()
		AnalyticsService:LogCustomEvent(player, name, tonumber(value) or 1, f)
	end)
end

-- a session milestone: once per join, value = seconds into the session
function Telemetry.mark(player, name)
	local s = sessions[player.UserId]
	if not s or s.marks[name] then return end
	s.marks[name] = true
	Telemetry.event(player, "m_" .. name, math.floor(os.clock() - s.joined))
end

--[[ Cash in or out. flow = "source" | "sink", amount > 0, kind = what it was
	(the item SKU on the dashboard). Income and code taps are summed. ]]
function Telemetry.money(player, flow, amount, kind)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 or (flow ~= "source" and flow ~= "sink") then return end
	local s = sessions[player.UserId]
	if flow == "source" and SUMMED[kind] then
		if s then s.sums[kind] = (s.sums[kind] or 0) + amount end
		return
	end
	logMoney(player, flow, amount, kind)
end

-- a recruit run, start and end (tier: walkin / skilled / star / genius / vip)
function Telemetry.carryStart(player, tier, chased)
	Telemetry.event(player, "carry_start", 1, { { "tier", tier } })
	Telemetry.mark(player, "recruit")
	if chased then Telemetry.mark(player, "chase") end
end

function Telemetry.carryEnd(player, tier, outcome, seconds)
	Telemetry.event(player, "carry_end", math.floor(seconds or 0), { { "tier", tier }, { "out", outcome } })
	if outcome == "signed" then Telemetry.mark(player, "delivery") end
end

function Telemetry.left(player)
	local s = sessions[player.UserId]
	if not s then return end
	flush(player, s)
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
