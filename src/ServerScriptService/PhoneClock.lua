--[[ PhoneClock (20 Oct): an investor's patience, as pure functions.

Phone.lua gives an investor 180 s for your reply (and a term sheet 120 s more), then
closes the thread: "Looks like you're busy. Another time!". Luke's live run, 20 Oct
(5:58-6:00): he was DRIVING, could not answer, and lost the deal for using the car the
game had just told him to use. The clock now stands still while you can't answer
(driving, or carrying a recruit home), and no new investor starts texting then.

Pure (no services): tests/offline/phoneclock.spec.luau. ]]
local C = {}

C.OFFER_GRACE = 120   -- a term sheet stays on the table this long past the reply deadline

-- ctx: { driving = bool, carrying = bool }
function C.busy(ctx)
	return (ctx and (ctx.driving or ctx.carrying)) and true or false
end

-- one tick of `dt` seconds for the active thread `th` ({ status, deadline }).
-- -> "timeout" (stopped waiting for a reply), "withdrawn" (the offer is off), or nil
function C.tick(th, now, dt, busy)
	if not th or not th.deadline then return nil end
	if busy then
		th.deadline += dt   -- frozen: you get back exactly the time you had
		return nil
	end
	if th.status == "wait" and now > th.deadline then return "timeout" end
	if th.status == "offer" and now > th.deadline + C.OFFER_GRACE then return "withdrawn" end
	return nil
end

-- may the next investor start a thread now?
function C.canStart(now, nextAt, busy)
	return not busy and now >= nextAt
end

return C
