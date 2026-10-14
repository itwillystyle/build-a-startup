--[[ StaffAction (14 Oct 2026, Manage Staff phase 2): what a TRAIN or MOVE request may do. Pure.

	Every rule the StaffAction remote enforces lives here, so the abuse-case table in the
	phase 2 plan is a list of offline tests (staffaction.spec), not a hope. The server only
	looks the person up in the CALLER's own staff list, calls validate, debits the price it
	returns, and calls apply; it must not yield in between (two TRAINs in one frame).
	No pure module here requires a sibling, so StaffStats is passed in: StaffAction.with(S). ]]
local StaffAction = {}

StaffAction.RATE = 4          -- actions a second per player (spec §5)
StaffAction.BURST = 4
StaffAction.MAX_ID = 1e9

function StaffAction.with(S)
	local A = {}
	local STAT = {}
	for _, st in S.STATS do STAT[st.id] = true end

	function A.parse(kind, a, b)
		if kind ~= "train" and kind ~= "move" then return nil, "unknown action" end
		if type(a) ~= "number" or a ~= a or a < 1 or a > StaffAction.MAX_ID or a ~= math.floor(a) then return nil, "bad id" end
		if kind == "train" then
			if type(b) ~= "string" or not STAT[b] then return nil, "bad stat" end
			return { kind = "train", id = a, stat = b }
		end
		if not S.validPin(b) then return nil, "bad room" end
		return { kind = "move", id = a, dept = b }
	end

	function A.price(p, stat) return S.price(p[stat] or 0, p.priceRate or 0) end

	function A.validate(ctx, act)
		if ctx.busy then return false, "busy" end
		local p = ctx.person
		if not p then return false, "not yours" end
		if act.kind == "train" then
			if not S.canTrain(p[act.stat] or 0, ctx.stage, p.talent) then return false, "at max" end
			local price = A.price(p, act.stat)
			local cash = tonumber(ctx.cash) or 0
			if cash ~= cash or cash < price then return false, "need cash", price end
			return true, nil, price
		end
		if act.dept == (p.pin or "") then return false, "already there" end
		if act.dept ~= "" and (tonumber(ctx.freeSeats) or 0) < 1 then return false, "no free seat" end
		return true
	end

	function A.apply(p, act)
		if act.kind == "train" then
			p[act.stat] = S.clampLevel(p[act.stat]) + 1
		else
			p.pin = act.dept
		end
	end

	-- a token bucket: BURST at once, then RATE a second; a corrupt bucket starts fresh
	function A.allow(bucket, now)
		local tokens = StaffAction.BURST
		if type(bucket) == "table" and type(bucket.tokens) == "number" and bucket.tokens == bucket.tokens
			and type(bucket.at) == "number" and bucket.at == bucket.at then
			tokens = math.min(StaffAction.BURST, bucket.tokens + math.max(0, now - bucket.at) * StaffAction.RATE)
		end
		if tokens < 1 then return false, { tokens = tokens, at = now } end
		return true, { tokens = tokens - 1, at = now }
	end

	-- what a keeper starts the new company with (Loyalty kept, clamped like the rest)
	function A.carryKeeper(k, newStage)
		local loyalty = S.clampLevel(k.loyalty)
		return {
			skill = S.carried(k.skill, loyalty, newStage, k.talent),
			speed = S.carried(k.speed, loyalty, newStage, k.talent),
			loyalty = math.min(loyalty, S.cap(newStage, k.talent)),
			pin = "",
		}
	end

	-- one row of the StaffData attribute (the TEAM screen, phase 3, reads it)
	function A.row(p, stage)
		local stats = {}
		for _, st in S.STATS do
			stats[st.id] = { level = S.clampLevel(p[st.id]), cap = S.cap(stage, p.talent), price = A.price(p, st.id) }
		end
		return { id = p.id, name = p.name, role = p.role, talent = p.talent, tier = p.tier, room = p.room,
			fit = p.fit == true, rate = p.rate, pin = p.pin or "", stats = stats }
	end

	return A
end

return StaffAction
