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

return H
