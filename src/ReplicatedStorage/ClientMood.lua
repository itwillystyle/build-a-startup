--[[ ClientMood (24 Oct 2026): the client's timer and the sad walk-off. Pure.

	Luke's 20 Oct ask: "sad + ticking effects when an app isn't given in time". He let the
	agent pick, and the pick is option C (ui/animation-review/judge/CLIENT-TIMER-OPTIONS.md,
	mock ui/animation-review/mp4/6-client-timer.mp4): a pie badge at the end of the speech
	bubble that drains in one calm colour, and in the last 8 s turns into a red disc that
	counts 8, 7 ... 1. The number changing is the tick, so it reads with no motion, no colour
	vision and no sound. A soft tick sound plays each second for the one client nearest to
	running out. When they run out they say "Too slow...", the pay you lost rises as a grey
	coin, and they walk off slumped and slower.

	The old bar was a traffic light (green over half, gold over a quarter, red): a client was
	"warning" for half of their wait. Red now means seconds, not a share, so a BIG client
	(45 s) goes red at 8 s like everyone else.

	Used by ClientsServer (the walk-off, the held spot, the looks), ClientTimerClient (the
	badge, the tick), StaffAnimClient (the slump) and ClientFxClient (the grey coin).
	Tested by tests/offline/clientmood.spec.luau. ]]
local ClientMood = {}

ClientMood.WARN = 8          -- seconds left when the badge turns red and starts to count and tick
ClientMood.SAY = 1.8         -- seconds a leaving client stands and says their line ("Thanks!", "Too slow...")
ClientMood.WALK = 10         -- studs a second, the walk up and away (ClientsServer's WALK_SPEED)
ClientMood.SAD_WALK = 7      -- a lost client walks off at 0.7x (a sad walk is 32-40 frames to a normal 24)
ClientMood.CLEAR = 2.5       -- studs the leaver walks before the next client steps onto their spot
ClientMood.GUESS = 0.5       -- the most the client counts down past the last server draw (4 Hz: two draws)
ClientMood.SLUMP_IN = 0.4    -- seconds the slump eases in (a held pose at once under Reduce Motion)

-- the tick pop (1.00 -> 1.06 over MotionSpec T.press, back over T.fast: a SMALL_SCALE press,
-- so Reduce Motion keeps it) and the lost-pay chip (fade in over T.ui, hold, rise and fade)
ClientMood.POP = { to = 1.06, up = 0.12, down = 0.15 }
ClientMood.LOST = { enter = 0.2, hold = 1.2, leave = 0.3, rise = 16 }

function ClientMood.leftOf(share, patience)
	return (share or 0) * (patience or 0)
end

-- "calm" | "worried" | "lost", from seconds left
function ClientMood.stage(left)
	if left <= 0 then return "lost" end
	if left <= ClientMood.WARN then return "worried" end
	return "calm"
end

-- the number on the red badge: 8 .. 1, nil outside the last 8 s
function ClientMood.count(left)
	if left <= 0 or left > ClientMood.WARN then return nil end
	return math.clamp(math.ceil(left - 1e-9), 1, ClientMood.WARN)
end

-- 24 Oct (live): what the badge shows, given what it showed: never back up. The client's guess runs
-- ahead between the server's 4 Hz updates and a correction can put it back a second (8, 7, 8, 7 ...)
function ClientMood.shownCount(shown, n)
	if n == nil then return shown end
	if shown == nil then return n end
	return math.min(shown, n)
end

-- the whole seconds n (8 .. 1) the clock reached between two reads: prev > n >= now.
-- Time going back (a guess corrected up) crosses nothing.
function ClientMood.ticks(prev, now)
	local out = {}
	if now >= prev then return out end
	for n = ClientMood.WARN, 1, -1 do
		if prev > n and now <= n then table.insert(out, { n = n, hi = n <= 3 }) end
	end
	return out
end

-- degrees of the pie already gone, clockwise from 12 o'clock
function ClientMood.sweep(left, patience)
	if not patience or patience <= 0 then return 0 end
	return (1 - math.clamp(left / patience, 0, 1)) * 360
end

-- seconds left now, from the last server value and how long ago it came. Patience pauses
-- while you code that job or carry the app, so the client only counts down while it drains.
function ClientMood.estimate(left, since, draining)
	if not draining then return left end
	return math.max(0, left - math.clamp(since, 0, ClientMood.GUESS))
end

-- which client ticks: list of { key, left }; the lowest in (0, WARN], or nil
function ClientMood.ticker(list)
	local best, bestLeft
	for _, e in ipairs(list) do
		if e.left > 0 and e.left <= ClientMood.WARN and (not bestLeft or e.left < bestLeft) then
			best, bestLeft = e.key, e.left
		end
	end
	return best
end

-- how slumped (0..1) a lost client is `since` seconds after running out (Quint Out)
function ClientMood.slump(since, reduced)
	if reduced then return 1 end
	if since <= 0 then return 0 end
	local a = math.min(1, since / ClientMood.SLUMP_IN)
	return 1 - (1 - a) ^ 5
end

--[[ 24 Oct: the next client walked into spot 1 while the served one still stood there saying
	"Thanks!" (placeLine ran the moment they were paid; they leave 1.8 s later). A leaver now
	holds their spot until they have said their line and walked CLEAR studs off it. ]]
function ClientMood.freeAt(leftAt, say, speed)
	return leftAt + (say or 0) + ClientMood.CLEAR / math.max(0.1, speed or ClientMood.WALK)
end

function ClientMood.walkDelay(now, freeAt)
	if not freeAt then return 0 end
	return math.max(0, freeAt - now)
end

--[[ Client looks (Plan 2: "client looks never match the player's avatar"). A look is
	{ skin = index into StaffRig.SKIN, hair = accessory id }; the avatar is { skin = index of
	the nearest tone, hair = { [id] = true } } read off the player's character. A look that
	shares the skin tone or the hair is a look-alike. ]]
function ClientMood.lookOk(look, avatar)
	if not avatar then return true end
	if avatar.skin and look.skin == avatar.skin then return false end
	if avatar.hair and look.hair and avatar.hair[look.hair] then return false end
	return true
end

-- the first index from `base` up whose look passes, or `base` after `tries` misses
function ClientMood.pickIndex(base, lookOf, avatar, tries)
	for k = 0, (tries or 12) - 1 do
		if ClientMood.lookOk(lookOf(base + k), avatar) then return base + k end
	end
	return base
end

-- the palette entry ({ r, g, b }, 0-255) closest to rgb
function ClientMood.nearest(rgb, palette)
	local best, bestD = 1, math.huge
	for i, c in ipairs(palette) do
		local d = (rgb[1] - c[1]) ^ 2 + (rgb[2] - c[2]) ^ 2 + (rgb[3] - c[3]) ^ 2
		if d < bestD then best, bestD = i, d end
	end
	return best
end

return ClientMood
