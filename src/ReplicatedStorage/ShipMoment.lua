--[[ ShipMoment (22 Oct 2026): the first-ship celebration's beats. Pure.

	Luke, 22 Oct: "the celebration of the yellow stripes when you ship first is really ugly".
	Those were 16 Oct's 3B: gold rays turning in the middle of the screen, a tilted
	"SHIPPED!" stamp, and a "+$X" counting up on its own clock while the event happened at
	the door. His pick (ui/2026-10-22-celebration/mocks.html, A, "the client's moment"):

	  0.0 s   the box lifts out of your hands and glows; a rising tone
	  0.4 s   handoff: everything freezes for 80 ms, the box shakes (the screen does not)
	  0.5 s   the client reacts (the server's cheer) and a "!" pops over them
	  0.6 s   coins burst from the client and fly one by one into your cash; the "+$X"
	          by the coins counts in step with them, and the cash takes each coin
	  ~2.3 s  done (no skip: 22 Oct, Luke)

	COIN mirrors HudClient's coinStream (the HUD flies the coins and moves the money into
	the counter coin by coin). Tested by tests/offline/shipmoment.spec.luau. ]]
local ShipMoment = {}

ShipMoment.BEATS = { lift = 0, handoff = 0.4, hitstop = 0.08, react = 0.5, coins = 0.6 }
ShipMoment.COINS = 12
-- HudClient coinStream: burst, hold, the stagger between coins, the longest flight
ShipMoment.COIN = { burst = 0.24, hold = 0.08, stagger = 0.045, fly = 0.5 }
ShipMoment.FADE = 0.38   -- the "+$X" leaves after the last coin

function ShipMoment.duration(n)
	local c = ShipMoment.COIN
	return ShipMoment.BEATS.coins + c.burst + c.hold + (n - 1) * c.stagger + c.fly + ShipMoment.FADE
end

-- what the "+$X" by the coins says once k of n coins have landed
function ShipMoment.given(total, k, n)
	if k >= n then return total end
	return math.floor(total * k / n + 0.5)
end

--[[ one call per coin that LANDS -> (what the number says now, was that the last one).
	Found live 22 Oct: each coin's flight is 0.42-0.50 s, so coin 12 can land before coin 11.
	Counting by the coin's index made the number go backwards and end on +$275 of $300. ]]
function ShipMoment.lander(total, n)
	local landed = 0
	return function()
		landed = math.min(n, landed + 1)
		-- 23 Oct: never "+$0": a small total over 12 coins rounded the first coin down to nothing
		local shown = math.max(ShipMoment.given(total, landed, n), math.min(total, 1))
		return shown, landed == n
	end
end

function ShipMoment.plays(d)
	return type(d) == "table" and d.wow == true
end

function ShipMoment.total(d)
	return (tonumber(d.pay) or 0) + (tonumber(d.tip) or 0)
end

return ShipMoment
