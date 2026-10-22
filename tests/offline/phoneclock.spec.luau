-- phoneclock.spec.luau: an investor waits while you can't answer, run outside Studio.
-- 20 Oct (Luke's live run, 5:58-6:00): he was driving, the investor's 180 s ran out, and the
-- thread closed with "Looks like you're busy. Another time!" -- a deal lost for using the car.
local C = require("../../src/ServerScriptService/PhoneClock")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local function thread(deadline) return { status = "wait", deadline = deadline } end

test("an investor who waits on you times out when you just ignore them", function()
	local th = thread(100)
	assert(C.tick(th, 101, 1, false) == "timeout", "past the deadline, not busy: the investor gives up")
end)

test("the clock stops while you drive: a 5-minute drive loses nothing", function()
	local th = thread(100)
	local now = 0
	for _ = 1, 300 do   -- 300 s at the wheel, ticking once a second
		now += 1
		assert(C.tick(th, now, 1, true) == nil, "timed out at " .. now .. " s while driving")
	end
	-- out of the car with the same 100 s the investor had when you got in
	assert(th.deadline - now == 100, "time left after the drive: " .. (th.deadline - now) .. " s, want 100")
end)

test("a term sheet on the table also waits while you are busy", function()
	local th = { status = "offer", deadline = 10 }
	for now = 1, 200 do assert(C.tick(th, now, 1, true) == nil, "offer withdrawn while driving at " .. now) end
end)

test("no new investor texts you while you are busy; they come once you are free", function()
	assert(not C.canStart(50, 40, true), "a new thread started mid-drive")
	assert(C.canStart(50, 40, false), "free and due: the next investor texts")
	assert(not C.canStart(30, 40, false), "not due yet")
end)

test("sitting in your own car counts as driving (live, 22 Oct: it never did)", function()
	-- Phone.driving() climbed to the TOP model above the seat, and Workspace IS a Model, so it
	-- always landed on "Workspace" and never on "Car_<id>": the clock never stood still
	local roblox = require("@lune/roblox") :: any
	local dm = roblox.Instance.new("DataModel")
	local ws = dm:GetService("Workspace")
	assert(ws:IsA("Model"), "the trap: Workspace is a Model")
	local car = roblox.Instance.new("Model"); car.Name = "Car_7"; car.Parent = ws
	local body = roblox.Instance.new("Model"); body.Name = "Body"; body.Parent = car
	local seat = roblox.Instance.new("VehicleSeat"); seat.Parent = body
	assert(C.inOwnCar(seat, 7) == true, "seated in Car_7 (seat nested in the car's body) is driving")
	assert(C.inOwnCar(seat, 8) == false, "someone else's car is not yours")
	local bench = roblox.Instance.new("Seat"); bench.Parent = ws
	assert(C.inOwnCar(bench, 7) == false, "a park bench is not driving")
	assert(C.inOwnCar(nil, 7) == false, "standing is not driving")
end)

test("busy means driving or carrying a recruit, nothing else", function()
	assert(C.busy({ driving = true }) and C.busy({ carrying = true }), "driving and carrying are busy")
	assert(not C.busy({}), "standing around is not busy")
end)

return T
