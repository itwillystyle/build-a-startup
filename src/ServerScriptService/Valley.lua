--[[
	Valley -- the other five founders, made visible (v4.9).

	THE PROBLEM, measured 4 Oct. "Six founders, one valley" has been the
	tagline since v0.8 and it was not true. The whole game had six
	FireAllClients calls and every one of them was a text toast. Rivals,
	market share and poach offers are all off under Econ.V3. Six people
	share one campus, stand in sight of each other's buildings, and cannot
	see, affect or race each other in any way.

	That matters beyond taste. Intentional co-play days are a published
	ranking signal, the hub board shows an ALL-TIME GLOBAL top ten pulled
	from a DataStore -- nothing anywhere tells you about the five people
	standing in the valley with you right now -- and a server where other
	people visibly exist is the only version of this game that is worth
	filming.

	Two pieces, both deliberately small:

	  PLOT ATTRIBUTES. Every two seconds each plot folder carries who owns
	  it, what their company is called, how tall they have built, what they
	  are worth and where they stand in THIS server. Attributes replicate on
	  their own, so the client draws the boards with no extra remotes.

	  THE MARKET BELL. Every few minutes a ninety-second window opens on
	  every client at once. Whoever grows their valuation most takes the
	  round, wins a payday and a gold crown on their tower until the next
	  bell. It needs no interaction, so it still works in a one-player
	  server (you win, modestly), and it gives six strangers one thing to
	  react to together.

	Server-authoritative throughout: the client only reads attributes.
]]

local Players = game:GetService("Players")
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))   -- the player loop: cash in and out

local Valley = {}

local BELL_EVERY = 330        -- seconds between bells
local BELL_WINDOW = 90        -- how long a round lasts
local BELL_FIRST = 150        -- the first bell of a server, so a new player meets one early
local BELL_PRIZE_SECONDS = 45 -- the winner's payday, in seconds of their own income
local PUBLISH = 2             -- how often plot attributes refresh

local api                     -- injected by SiliconCore
local bell = { on = false, startedAt = 0, base = {}, nextAt = 0 }

-- ---------------------------------------------------------------- helpers

local function sessionOf(player)
	return api.session and api.session(player) or nil
end

local function plotFolderOf(player)
	local plot = api.plotOf and api.plotOf(player)
	return plot and plot.folder, plot
end

local function valuationOf(s) return math.floor((s and s.valuation) or 0) end

-- false while the player's save is still being read: their valuation is a placeholder 0
local function settled(player)
	return not api.loadDone or api.loadDone(player)
end

--[[ Everyone in the server, richest first. Used for the live rank on each
	tower -- this is the standing the hub board does NOT show, because that
	board is the all-time global one. ]]
local function standing()
	local list = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		local s = sessionOf(pl)
		if s then table.insert(list, { player = pl, value = valuationOf(s) }) end
	end
	table.sort(list, function(a, b) return a.value > b.value end)
	local rank = {}
	for i, e in ipairs(list) do rank[e.player.UserId] = i end
	return rank, list
end

-- ---------------------------------------------------------------- attributes

local function publish()
	local rank = standing()
	local seen = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		local folder, plot = plotFolderOf(pl)
		local s = sessionOf(pl)
		if folder and s then
			seen[folder] = true
			folder:SetAttribute("OwnerId", pl.UserId)
			folder:SetAttribute("Company", s.name or "")
			folder:SetAttribute("Valuation", valuationOf(s))
			folder:SetAttribute("Listed", s.ipo == true)
			folder:SetAttribute("Rank", rank[pl.UserId] or 0)
			folder:SetAttribute("Level", (api.level and plot and api.level(plot)) or 1)
			folder:SetAttribute("BellGain", bell.on
				and math.max(0, valuationOf(s) - (bell.base[pl.UserId] or valuationOf(s))) or 0)
		end
	end
	-- a plot nobody owns says so, rather than keeping the last tenant's name
	for _, folder in ipairs(api.plots:GetChildren()) do
		if not seen[folder] and folder:GetAttribute("OwnerId") then
			for _, k in ipairs({ "OwnerId", "Company", "Valuation", "Listed", "Rank", "Level", "BellGain" }) do
				folder:SetAttribute(k, nil)
			end
		end
	end
end

-- ---------------------------------------------------------------- the bell

local function openBell()
	bell.on, bell.startedAt, bell.base = true, os.clock(), {}
	for _, pl in ipairs(Players:GetPlayers()) do
		local s = sessionOf(pl)
		-- a save still loading would "grow" by its whole valuation and win, so it sits this round out
		if s and settled(pl) then bell.base[pl.UserId] = valuationOf(s) end
	end
	api.plots:SetAttribute("BellOn", true)
	api.plots:SetAttribute("BellSeconds", BELL_WINDOW)
	api.toast(("THE MARKET BELL  ·  %d seconds  ·  fastest growth takes the round"):format(BELL_WINDOW), "news")
end

local function closeBell()
	bell.on = false
	api.plots:SetAttribute("BellOn", false)
	local best, bestGain = nil, 0
	for _, pl in ipairs(Players:GetPlayers()) do
		local s = sessionOf(pl)
		local base = bell.base[pl.UserId]
		if s and base then   -- no start value: joined or was still loading when the bell opened
			local gain = valuationOf(s) - base
			if gain > bestGain then best, bestGain = pl, gain end
		end
	end
	for _, folder in ipairs(api.plots:GetChildren()) do folder:SetAttribute("BellGain", 0) end
	if not best then
		api.plots:SetAttribute("BellWinner", 0)
		api.toast("The bell closed with nothing built. Next round soon.", "news")
		return
	end
	local s = sessionOf(best)
	local prize = math.floor((s.rate or 0) * BELL_PRIZE_SECONDS)
	local cash = api.cash(best)
	if cash and prize > 0 then cash.Value += prize; Telemetry.money(best, "source", prize, "bell") end
	s.valuation = valuationOf(s) + math.floor(prize / 2)
	local folder = plotFolderOf(best)
	api.plots:SetAttribute("BellWinner", folder and folder.Name or "")
	api.toast(("%s took the round  ·  grew $%s in 90 seconds  ·  +$%s"):format(
		s.name ~= "" and s.name or best.DisplayName, api.fmt(bestGain), api.fmt(prize)), "news")
end

-- ---------------------------------------------------------------- init

function Valley.init(given)
	api = given
	assert(api and api.plots, "Valley.init needs the Plots folder")
	api.plots:SetAttribute("BellOn", false)
	api.plots:SetAttribute("BellWinner", "")
	bell.nextAt = os.clock() + BELL_FIRST

	task.spawn(function()
		while true do
			task.wait(PUBLISH)
			pcall(publish)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			if bell.on then
				api.plots:SetAttribute("BellSeconds", math.max(0, math.ceil(BELL_WINDOW - (now - bell.startedAt))))
				if now - bell.startedAt >= BELL_WINDOW then
					pcall(closeBell)
					bell.nextAt = now + BELL_EVERY
				end
			elseif now >= bell.nextAt and #Players:GetPlayers() > 0 then
				pcall(openBell)
			end
		end
	end)
	return true
end

-- for tests and the dev hook
Valley.BELL_WINDOW = BELL_WINDOW
function Valley.forceBell() bell.nextAt = 0 end
function Valley.endBell() if bell.on then bell.startedAt = os.clock() - BELL_WINDOW end end

return Valley
