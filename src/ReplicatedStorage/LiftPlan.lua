--[[ LiftPlan (15 Oct 2026, HQ project #1 part 1b): the lift's rules. Pure.
	Spec: silicon-startup/docs/superpowers/specs/2026-10-15-hq-lift-1b-design.md. Wafers builds
	the parts, LiftCab (server) runs one cab per tower from these rules, LiftClient animates it. ]]
local LiftPlan = {}

-- No pure module here requires a sibling (StaffAction.with): TowerPlan is passed in.
function LiftPlan.with(T)
	local LP = {}

	LP.PER_STOP, LP.CAP, LP.DOORS, LP.DWELL = 1.0, 4.0, 0.5, 3.0
	LP.MAX_RIDERS, LP.EVENT_ODDS, LP.QUIET_RIDES = 6, 1 / 12, 3
	LP.EVENT_TEXT = {
		calm = "PLEASE REMAIN CALM :)",
		pride = "THIS LIFT WAS BUILT BY %s",
		capacity = "MAXIMUM CAPACITY. SOMEONE HAS TO GO.",
	}
	LP.SHORT = { lobby = "LOBBY", eng = "ENG", studio = "STUDIO", cafe = "CAFE", servers = "SERVERS", labs = "AI LABS", board = "BOARD" }

	function LP.stopId(s)
		if s == 0 then return "L" end
		if s >= 14 then return "R" end
		return "F" .. s
	end

	function LP.stops(pieces, level)
		local out = {}
		for s = 0, T.TOP do
			if T.landable(pieces, level, s) then table.insert(out, { storey = s, id = LP.stopId(s), label = T.label(s) }) end
		end
		return out
	end

	function LP.sockets(pieces, level)
		local out = {}
		for s = 0, 14 do
			if not T.DECKS[s] then
				table.insert(out, { storey = s, id = LP.stopId(s), num = (s == 0 and "L") or (s == 14 and "R") or tostring(s),
					built = T.landable(pieces, level, s) == true })
			end
		end
		return out
	end

	function LP.rideTime(n)
		n = math.abs(n or 0)
		if n == 0 then return 0 end
		return math.min(n * LP.PER_STOP, LP.CAP)
	end

	function LP.ticks(n)
		n = math.abs(n or 0)
		local out, dur = {}, LP.rideTime(n)
		for k = 1, n do table.insert(out, { t = dur * k / n, loud = (k == n) }) end
		return out
	end

	function LP.alpha(t, dur)
		if dur <= 0 then return 1 end
		local x = math.clamp(t / dur, 0, 1)
		return x * x * (3 - 2 * x)
	end

	-- the call queue: `at` is the stop index the cab is at; picks (from inside) before calls (from landings)
	function LP.newCab(at) return { at = at or 1, calls = {}, picks = {}, rides = 0, lastEvent = false } end
	local function add(list, idx) if not table.find(list, idx) then table.insert(list, idx) end end
	function LP.call(cab, idx) add(cab.calls, idx) end
	function LP.pick(cab, idx) add(cab.picks, idx) end
	function LP.target(cab) return cab.picks[1] or cab.calls[1] end
	function LP.arrive(cab, idx)
		cab.at = idx
		for _, list in ipairs({ cab.calls, cab.picks }) do
			local i = table.find(list, idx)
			if i then table.remove(list, i) end
		end
	end
	function LP.prune(cab, nStops)
		cab.at = math.clamp(cab.at, 1, math.max(nStops, 1))
		for _, list in ipairs({ cab.calls, cab.picks }) do
			for i = #list, 1, -1 do if list[i] > nStops then table.remove(list, i) end end
		end
	end

	function LP.rareEvent(ridesBefore, lastWasEvent, riders, roll)
		if riders > LP.MAX_RIDERS then return "capacity" end
		if ridesBefore < LP.QUIET_RIDES or lastWasEvent then return nil end
		if roll < LP.EVENT_ODDS / 2 then return "calm" end
		if roll < LP.EVENT_ODDS then return "pride" end
		return nil
	end

	function LP.roomLabel(pieces, depts, level, storey)
		if storey == 0 then return "LOBBY" end
		if storey >= 14 then return "ROOF GARDEN" end
		local count, firstSeg = {}, {}
		for L = 2, level do
			local pc = pieces[L]
			local d = depts[L]
			if pc and pc.kind == "segment" and pc.storey == storey and d then
				count[d] = (count[d] or 0) + 1
				firstSeg[d] = math.min(firstSeg[d] or 99, pc.seg)
			end
		end
		local best
		for d, n in pairs(count) do
			if not best or n > count[best] or (n == count[best] and firstSeg[d] < firstSeg[best]) then best = d end
		end
		return best and (LP.SHORT[best] or string.upper(best)) or ("FLOOR " .. storey)
	end

	return LP
end

return LiftPlan
