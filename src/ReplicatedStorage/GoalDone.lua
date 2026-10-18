--[[ GoalDone (18 Oct 2026): may the goal card stamp DONE! when the goal changes? Pure.

	GuideClient used to stamp DONE on any free goal that moved on. The client loop's goals
	(Clients.goal) come and go with the line: "Upgrade your HQ" shows while the garage is
	full AND busy, so one GIVE (the line 2 -> 1) swapped it for "Save up for level 2" and the
	card said DONE! with a tick while nothing had been built (playtest 22-54-32, 0:44). Now a
	goal whose finish can be seen is DONE only when it was: a new level, a new hire, the line
	served. Tested by tests/offline/goaldone.spec.luau.

	ctx = { cost?, spent?, levelUp?, staffUp?, lineEmpty? }, all read by GuideClient:
	  cost / spent   the old goal's price and how much cash left since it showed
	  levelUp        the HQ level (WaferLevel) rose while the old goal showed
	  staffUp        the team (leaderstats Staff) grew while the old goal showed
	  lineEmpty      nobody is waiting now (ClientsWaiting 0) ]]
local GoalDone = {}

-- goals you wait on: they end, nobody finished them
GoalDone.PASSIVE = { wait = true, watch = true, product = true }

-- goals with a finish the client can see, and which one
GoalDone.NEEDS = {
	upgrade = "levelUp",   -- "Upgrade your HQ"
	hire = "staffUp",      -- "Too busy! Hire a coder"
	carry = "staffUp",     -- "Bring X home!": delivered, not LOST
	serve = "lineEmpty",   -- "Serve your clients"
}

function GoalDone.finished(prevKey, newKey, ctx)
	ctx = ctx or {}
	if not prevKey or not newKey then return false end
	-- the LAUNCH interruption never stamps DONE on the goal underneath
	if GoalDone.PASSIVE[prevKey] or newKey == "product" then return false end
	if ctx.cost and ctx.cost > 0 then
		-- a purchase goal is done when the money for it left your pocket
		return (ctx.spent or 0) >= ctx.cost * 0.8
	end
	local need = GoalDone.NEEDS[prevKey]
	if need then return ctx[need] == true end
	return true
end

return GoalDone
