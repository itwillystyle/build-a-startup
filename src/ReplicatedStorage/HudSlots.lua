--[[ HudSlots (20 Oct): the bottom-centre HUD as numbers in ONE place.

Three scripts paint the bottom centre: HudClient (HOLD TO CODE / GIVE, LAUNCH!) and
CarClient (the speed panel while you drive). Each used to carry its own pixel offsets,
and when the speed panel grew to two rows (v5, 126 px) LAUNCH! still sat at 126 px up:
24 px of it, the pay line included, went under the panel. Luke's live run, 20 Oct
(5:52-5:56, 7:18): he never saw it and the app auto-launched at half pay.

Pure (no services): tests/offline/hudslots.spec.luau lays the slots out as rectangles. ]]
local H = {}

H.GAP = 12                                            -- between two things that can both be up
H.CODE = { bottom = 22, height = 64, width = 236 }    -- HOLD TO CODE / GIVE
H.LAUNCH = { height = 58, width = 164 }
H.SPEEDO = { bottom = 24, height = 126, width = 320 } -- CarClient's speed panel

-- how far up from the bottom edge LAUNCH! sits (its bottom edge, in px)
function H.launchBottom(inCar, codeShown)
	if inCar then return H.SPEEDO.bottom + H.SPEEDO.height + H.GAP end
	if codeShown then return H.CODE.bottom + H.CODE.height + 10 end
	return H.CODE.bottom
end

--[[ 23 Oct (doctor, every HQ step at 1074 x 376): the money texts in the bottom-left corner
	ran under an open menu: the income line with its momentum suffix (231 px) under DAILY, the
	"+$X" pop under DAILY and TEAM. The HUD draws below every menu (DisplayOrder 4 vs 12-14), so
	the player saw text cut off at a panel's edge. A money text steps aside while a menu PANEL
	covers it, the rule the goal card already keeps (UIKit.column's covers): a panel is at least
	240 x 120 and narrower than 90% of the screen (a full-screen layer or a chip is not one).
	rect and panels are { x, y, w, h } in screen px; touching edges is not under. ]]
H.PANEL_MIN = { w = 240, h = 120 }
function H.underMenu(rect, panels, vpX)
	if not rect or rect[3] <= 0 or rect[4] <= 0 then return false end
	for _, p in ipairs(panels) do
		if p[3] >= H.PANEL_MIN.w and p[4] >= H.PANEL_MIN.h and p[3] < vpX * 0.9 then
			local ox = math.min(rect[1] + rect[3], p[1] + p[3]) - math.max(rect[1], p[1])
			local oy = math.min(rect[2] + rect[4], p[2] + p[4]) - math.max(rect[2], p[2])
			if ox > 0 and oy > 0 then return true end
		end
	end
	return false
end

return H
