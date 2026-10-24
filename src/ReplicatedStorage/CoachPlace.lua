--[[ CoachPlace (24 Oct 2026): where a coach tip's card goes. Pure; CoachClient calls it every frame.
	Moved out of CoachClient (its v5 `place`) so it can be tested: tests/offline/coachplace.spec.luau.

	v5: beside the target when there is room, else above or below it; always fully on screen, under
	Roblox's top bar (58 px), clear of the rail, and on a touch screen off the thumbstick and the jump
	button. Found on a phone: the LAUNCH tip went left of the centred button, ran off the screen
	("UNCH your app!") and sat on the thumbstick.

	tp, ts, vp: the target's position and size and the screen size ({ X, Y }, Vector2 works), in the
	Coach gui's space. opts = { railRight, touch, avoid = { {x, y, w, h}... } }.
	Returns side ("right"|"left"|"above"|"below"), x, y. ]]
local CoachPlace = {}

-- the game doctor's rule (DoctorProbes.ui): two rectangles overlap when they share more than 6 px both ways
function CoachPlace.overlaps(a, b)
	local ox = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
	local oy = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
	return ox > 6 and oy > 6
end

function CoachPlace.place(tp, ts, vp, W, H, opts)
	opts = opts or {}
	local cx, cy = tp.X + ts.X / 2, tp.Y + ts.Y / 2
	local function blocked(x, y)
		if x < 8 or y < 64 or x + W > vp.X - 8 or y + H > vp.Y - 8 then return true end
		if opts.touch then
			if x < 170 and y + H > vp.Y - 170 then return true end              -- the thumbstick
			if x + W > vp.X - 180 and y + H > vp.Y - 160 then return true end   -- the jump button
		end
		-- 24 Oct (F-6): never on the goal card (the doctor's "cards over cards": Coach.CoachCard on
		-- Quest.Holder.Quest on a 376 px tall screen, where the tip's row under the top bar is the pill's)
		for _, r in ipairs(opts.avoid or {}) do
			if CoachPlace.overlaps({ x = x, y = y, w = W, h = H }, r) then return true end
		end
		return false
	end
	local rr = opts.railRight or 0
	local midY = math.clamp(cy - H / 2, 64, math.max(64, vp.Y - H - 8))
	-- beside a target, the card also stays above the bottom action slot (WRITE CODE /
	-- LAUNCH and its caption own the bottom ~118 px of the screen)
	local sideY = math.min(midY, math.max(64, vp.Y - 118 - H))
	local midX = math.clamp(cx - W / 2, 8, math.max(8, vp.X - W - 8))
	local at = {
		right = function() return math.max(tp.X + ts.X + 40, tp.X < rr and rr + 30 or 0), sideY end,
		left = function() return tp.X - W - 40, sideY end,
		above = function() return midX, tp.Y - H - 40 end,
		below = function() return midX, tp.Y + ts.Y + 40 end,
	}
	local order
	if cy > vp.Y * 0.6 then
		order = { "above", cx < vp.X / 2 and "right" or "left", "below" }
	elseif cx < vp.X * 0.4 then
		order = { "right", "below", "above", "left" }
	elseif cx > vp.X * 0.6 then
		order = { "left", "below", "above", "right" }
	else
		order = { "below", "above", "right", "left" }
	end
	for _, side in ipairs(order) do
		local x, y = at[side]()
		if not blocked(x, y) then return side, x, y end
		-- 24 Oct (F-6): the same side, dropped just under whatever it would sit on
		for _, r in ipairs(opts.avoid or {}) do
			local y2 = r.y + r.h + 8
			if y2 > y and not blocked(x, y2) then return side, x, y2 end
		end
	end
	local x, y = at[order[1]]()
	return order[1], math.clamp(x, 8, math.max(8, vp.X - W - 8)), math.clamp(y, 64, math.max(64, vp.Y - H - 8))
end

return CoachPlace
