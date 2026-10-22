--[[ GoalCard (22 Oct 2026): is the goal card full, or a slim pill? Pure.

	Luke, 22 Oct: "I'm also manually pressing the X, which is kind of annoying." The card
	sat full-size over the top of the screen until he closed it, and the client loop swaps
	the goal every few seconds (code, deliver, give), so it came back each time. Option A,
	his pick: a new goal shows full for FULL_FOR seconds, then shrinks to a pill (icon and
	title); tapping the pill opens it again. The X is gone.

	"New" means not seen in the last REPEAT_AFTER seconds, so the loop's goals open once and
	then stay pills. A goal that arrives while the card is hidden (a level-up holds the
	screen) gets its seconds when it shows. Tested by tests/offline/goalcard.spec.luau.

	GuideClient calls goal() when the key changes, shown() on every render the card is
	visible, tap() on a tap, and full() to pick the shape. ]]
local GoalCard = {}

GoalCard.FULL_FOR = 4
GoalCard.REPEAT_AFTER = 90

function GoalCard.new()
	return { seen = {}, fullUntil = -math.huge, owed = false }
end

function GoalCard.goal(s, key, now)
	if key == nil then return end
	local last = s.seen[key]
	if last == nil or now - last > GoalCard.REPEAT_AFTER then s.owed = true end
	s.seen[key] = now
end

function GoalCard.shown(s, now)
	if s.owed then
		s.owed = false
		s.fullUntil = now + GoalCard.FULL_FOR
	end
end

function GoalCard.tap(s, now)
	s.owed = false
	s.fullUntil = now + GoalCard.FULL_FOR
end

function GoalCard.full(s, now)
	return now < s.fullUntil
end

return GoalCard
