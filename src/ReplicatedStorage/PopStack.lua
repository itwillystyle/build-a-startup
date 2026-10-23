--[[ PopStack (23 Oct 2026): which line each pop over the cash sits on. Pure.

	The animation audit (finding 6): HudClient's popUnderCash drew every pop at the same spot, so on
	an auto-launch "+$X" and, 0.4 s later, "Auto-launched: half pay" landed on top of each other.
	Now the newest pop takes the bottom line (0) and pushes the older ones up; at most `max` lines,
	the oldest beyond that is evicted. Tested by tests/offline/popstack.spec.luau. ]]
local PopStack = {}

function PopStack.new(max)
	return { max = max or 2, ids = {} }   -- ids: newest first
end

-- -> the ids pushed past the top (to fade out now)
function PopStack.push(s, id)
	table.insert(s.ids, 1, id)
	local out = {}
	while #s.ids > s.max do table.insert(out, table.remove(s.ids)) end
	return out
end

function PopStack.remove(s, id)
	for i, v in ipairs(s.ids) do
		if v == id then
			table.remove(s.ids, i)
			return
		end
	end
end

-- 0 = the bottom line; nil = not on screen
function PopStack.line(s, id)
	for i, v in ipairs(s.ids) do
		if v == id then return i - 1 end
	end
	return nil
end

return PopStack
