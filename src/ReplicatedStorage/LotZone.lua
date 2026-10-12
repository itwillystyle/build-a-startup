--[[ LotZone (12 Oct 2026): are you on your own lot? Pure, so it can be tested offline.

	WHY. My Restaurant! shows its restaurant-management buttons only on your own plot
	and puts them away on the street: on the street you are recruiting or driving,
	and BUILD or DECOR there is a button for a place you are not standing in. The rail
	does the same now (UIKit.railButton opts.plotOnly; LotClient sets OnLot).

	A plot is a square around its Pivot. Measured 12 Oct, Plot1: every part of the lot
	(HQ, forecourt, lawns, pads) lies within x -117..115, z -119..116 of the Pivot, and
	neighbouring pivots are 336 studs apart, so the zones never touch. Hysteresis:
	you are ON once inside HALF_IN, and stay on until past HALF_OUT, so walking the
	edge does not blink the buttons. ]]
local LotZone = {}

LotZone.HALF_IN = 122
LotZone.HALF_OUT = 132

-- pivot: the plot's CFrame; pos: a Vector3; wasOn: the last answer (for hysteresis)
function LotZone.contains(pivot, pos, wasOn)
	local l = pivot:PointToObjectSpace(pos)
	local half = wasOn and LotZone.HALF_OUT or LotZone.HALF_IN
	return math.abs(l.X) <= half and math.abs(l.Z) <= half
end

return LotZone
