--[[ telemetry.spec.luau -- the player loop's names, checked against the code that sends them.

	A funnel step or money kind with a typo does not error: Telemetry.step drops a
	name it does not know, and a new money kind lands on the dashboard as its own
	SKU. Both fail silently for weeks. Telemetry.lua calls game:GetService at load,
	so this reads the source text instead of requiring it. ]]
local fs = require("@lune/fs")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local DIR = "src/ServerScriptService"
local TEL = fs.readFile(DIR .. "/Telemetry.lua")

local function sources()
	local out = {}
	for _, f in fs.readDir(DIR) do
		if f:match("%.lua$") and f ~= "Telemetry.lua" and not f:match("^Dev") then
			out[f] = fs.readFile(DIR .. "/" .. f)
		end
	end
	return out
end

local function funnel()
	local body = TEL:match("local FUNNEL = (%b{})")
	assert(body, "Telemetry.lua: FUNNEL table not found")
	local steps = {}
	for name in body:gmatch('"([%w_]+)"') do table.insert(steps, name) end
	return steps
end

-- the money kinds Telemetry knows how to file (SHOP, TIMED, SUMMED, and the Gameplay rest)
local KINDS = { floor = true, room = true, furniture = true, home = true, car = true, refund = true,
	daily = true, offline = true, income = true, code = true,
	hire = true, launch = true, investor = true, offer = true, ipo = true, bell = true, spinoff = true }

test("the funnel is the HQ ladder, in the order the game forces", function()
	local steps = table.concat(funnel(), " ")
	assert(steps == "joined play first_code first_ship first_hire hq_2 hq_3 hq_4 hq_5 public spinoff",
		"funnel changed: " .. steps .. " (a step that can come in any order auto-completes the ones before it)")
end)

test("every Telemetry.step name in the code is a funnel step", function()
	local known = {}
	for _, n in funnel() do known[n] = true end
	local bad, n = {}, 0
	for f, src in sources() do
		for name in src:gmatch('Telemetry%.step%([^,]+,%s*"([%w_]+)"') do
			n += 1
			-- "hq_" .. stage: a prefix, so the ladder steps it builds must exist
			local prefixOk = name:sub(-1) == "_" and known[name .. "2"] and known[name .. "5"]
			if not known[name] and not prefixOk then table.insert(bad, f .. ": " .. name) end
		end
	end
	assert(n >= 6, ("only %d Telemetry.step calls found: the pattern lost them"):format(n))
	assert(#bad == 0, "steps Telemetry would silently drop: " .. table.concat(bad, ", "))
end)

test("every Telemetry.money call names a known kind and a real flow", function()
	local bad, n = {}, 0
	for f, src in sources() do
		for flow, kind in src:gmatch('Telemetry%.money%([^,]+,%s*"(%a+)",[^,]+,%s*"([%w_]+)"%)') do
			n += 1
			if (flow ~= "source" and flow ~= "sink") or not KINDS[kind] then table.insert(bad, ("%s: %s %s"):format(f, flow, kind)) end
		end
	end
	assert(n >= 20, ("only %d Telemetry.money calls found: the pattern lost them"):format(n))
	assert(#bad == 0, "unknown money calls: " .. table.concat(bad, ", "))
end)

test("no cash change in the game code goes unlogged", function()
	-- every `cash.Value +=` / `-=` line is followed (or joined) by a Telemetry.money call
	local missing = {}
	for f, src in sources() do
		local lines = {}
		for l in (src .. "\n"):gmatch("([^\n]*)\n") do table.insert(lines, l) end
		for i, l in lines do
			if l:find("cash%.Value %-=") or l:find("cash%.Value %+=") then
				local near = l .. (lines[i + 1] or "") .. (lines[i + 2] or "")
				-- a failed furniture put refunds its own unlogged charge; that pair nets to zero
				local refundOfUnlogged = l:find("if not m then if not free then cash%.Value %+= price end")
				-- or the line says where it is logged instead ("-- telemetry: ...")
				local explained = l:find("%-%- telemetry: ")
				if not near:find("Telemetry.money", 1, true) and not refundOfUnlogged and not explained then
					table.insert(missing, ("%s:%d"):format(f, i))
				end
			end
		end
	end
	assert(#missing == 0, "cash changes with no Telemetry.money next to them: " .. table.concat(missing, ", "))
end)

return T
