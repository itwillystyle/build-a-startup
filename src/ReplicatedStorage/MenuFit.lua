--[[ MenuFit: the pure half of UIKit.fitMenu -- how small a menu draws and where
its centre goes (14 Oct 2026). No game services, so the offline tests load it.

v8 (14 Oct): a floor. The doctor measured TEAM's 52 px taps at 42 px on a 1074 x
395 window: its gui measured 712.8 wide, the rail one 66 px tile wide, and the
free strip beside the rail (612.8 px) shrank the 744 px panel to 0.8237. A menu
may now say how small it may go (TEAM: 44 / 52, so a tap never draws under 44).
At the floor and still too wide for the strip, it sits on the right margin and
reaches back over the rail (covering as little of it as it can) rather than shrink
further; on a screen narrower than that it starts at the left margin.

a = { w, h, px, pw, ph, railRight (nil = no rail), vMargin, floor (nil = none) }
Returns s, cx: the scale and the centre x relative to the parent. ]]
local MenuFit = {}

function MenuFit.place(a)
	local left, right = a.px + 12, a.px + a.pw - 12
	if a.railRight then left = math.max(left, a.railRight + 10) end
	local s = math.min(1, (right - left) / a.w, (a.ph - (a.vMargin or 24)) / a.h)
	if a.floor and s < a.floor then s = math.min(1, a.floor) end
	local half = a.w * s / 2
	local cx = math.clamp(a.px + a.pw / 2, left + half, math.max(left + half, right - half))
	if left + 2 * half > right then
		cx = math.max(a.px + 12 + half, right - half)
	end
	return s, cx - a.px
end

return MenuFit
