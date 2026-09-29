--[[
	DailyReward -- ModuleScript in ServerScriptService.

	v3.1 THE REASON TO COME BACK TOMORROW. The 25 Sep retention review found
	nothing in the game that brings a player back the next day, and Roblox's
	discovery scores exactly that (day-1, day-2-to-7, day-8-to-28 retention).

	A 7-day streak. Claim once per UTC day; claiming on consecutive days climbs
	the ladder, missing a day starts it again at day 1 (never below: absence is
	never punished beyond losing the streak). Rewards are seconds of your own
	income, so they matter at every stage, with a floor so a brand-new company
	still gets real money.

	Saved as TWO integers on the session (s.dailyDay = UTC day of the last
	claim, s.streak = 0..7), clamped by SiliconCore on load. Nothing else.

	Player attributes (read by DailyClient):
	  DailyReady  bool     a reward is waiting
	  DailyStreak int      the day you will claim next (1..7)
	  DailyLast   number   the amount just paid (drives the coin burst)
]]

local DailyReward = {}

-- seconds of income per streak day, and the floor for a company with no income yet
DailyReward.SECONDS = { 60, 120, 180, 300, 450, 600, 900 }
DailyReward.FLOOR = { 100, 200, 300, 500, 800, 1200, 2000 }
-- v3.2: from day 2 each day also puts something in your bag (Items.LIST ids),
-- so the ladder is worth more than a bigger number
DailyReward.ITEMS = { false, "coffee", "energy", "scout", "coffee", "noncompete", "frontpage" }

local api

local function today() return math.floor(os.time() / 86400) end

-- which day of the ladder the next claim is (1..7)
local function nextDay(s)
	local last = s.dailyDay or 0
	local streak = s.streak or 0
	if last == today() then return nil end                       -- already claimed today
	if last == today() - 1 then return (streak % 7) + 1 end       -- kept the streak
	return 1                                                       -- first ever, or a missed day
end

-- v4.5 THE ECONOMY CLOCK: day d pays at most DAILY_SHARE[d] of the next goal (5% .. 35%)
local Prog = require(script.Parent:WaitForChild("Progression"))
function DailyReward.amountFor(s, day, goal)
	local rate = s.rate or 0
	local raw = math.max(DailyReward.FLOOR[day] or 0, math.floor(rate * (DailyReward.SECONDS[day] or 60)))
	return Prog.capWindfall("daily", raw, goal, day)
end

function DailyReward.refresh(player)
	local s = api and api.session(player)
	if not s then return end
	local day = nextDay(s)
	player:SetAttribute("DailyReady", day ~= nil)
	player:SetAttribute("DailyStreak", day or math.max(1, s.streak or 1))
	-- the whole ladder, so the card can show every day's reward
	local amounts = {}
	local goal = api.nextGoal and api.nextGoal(player)
	for d = 1, 7 do amounts[d] = DailyReward.amountFor(s, d, goal) end
	player:SetAttribute("DailyAmounts", table.concat(amounts, ","))
	local items = {}
	for d = 1, 7 do items[d] = DailyReward.ITEMS[d] or "" end
	player:SetAttribute("DailyItems", table.concat(items, ","))
end

function DailyReward.claim(player)
	local s = api and api.session(player)
	local cash = api and api.cash(player)
	if not s or not cash or not s.shipped then return end
	local day = nextDay(s)
	if not day then return end
	local amount = DailyReward.amountFor(s, day, api.nextGoal and api.nextGoal(player))
	s.dailyDay = today()
	s.streak = day
	cash.Value += amount
	player:SetAttribute("DailyLast", amount)
	local item = DailyReward.ITEMS[day]
	if item and api.grant then pcall(api.grant, player, item, 1, ("Day %d reward"):format(day)) end
	DailyReward.refresh(player)
end

function DailyReward.init(a)
	api = a
	local claim = a.remote("ClaimDaily")
	claim.OnServerEvent:Connect(function(player) DailyReward.claim(player) end)
	-- the day rolls over while people play: re-check every minute
	task.spawn(function()
		while true do
			task.wait(60)
			for _, p in ipairs(game:GetService("Players"):GetPlayers()) do pcall(DailyReward.refresh, p) end
		end
	end)
end

return DailyReward
