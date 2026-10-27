--[[ Flags (26 Oct 2026, safety net part 2): the kill switch. Turns a feature off on every live
	server within a minute, with no publish.

	The record is one DataStore key (SVFlags_v1 / "live"; Studio reads "studio", so a test never
	turns anything off for players). Every server reads it at start and every POLL seconds and
	copies each flag to ReplicatedStorage as an attribute "Flag_<name>", which clients read:
	  RS:GetAttribute("Flag_bobScenes") ~= false     -- on unless switched off

	Only names in DEFAULTS exist, and only a real boolean changes one: a missing, broken or
	half-written record leaves every feature at its default (on).

	Flip one from Studio's command bar or the Studio MCP (Edit datamodel):
	  require(game.ServerScriptService.Flags:Clone()).set("bobScenes", false, "live")
	See docs/ROLLBACK.md. tests/offline/flags.spec.luau ]]

local Flags = {}

Flags.STORE = "SVFlags_v1"
Flags.POLL = 60
Flags.DEFAULTS = {
	bobScenes = true,   -- P-5: Bob's two cutscenes (off: the intro is the old flyover; the payoff still pays)
}

function Flags.parse(raw)
	local out = {}
	for name, default in Flags.DEFAULTS do
		local v = if type(raw) == "table" then raw[name] else nil   -- not `and`: a missing record gave `false` = OFF
		out[name] = if type(v) == "boolean" then v else default
	end
	return out
end

-- -> true, or false + why
function Flags.check(name, value)
	if Flags.DEFAULTS[name] == nil then return false, "no flag named " .. tostring(name) end
	if type(value) ~= "boolean" then return false, "a flag is true or false" end
	return true
end

function Flags.key(studio)
	return studio and "studio" or "live"
end

local function store()
	return game:GetService("DataStoreService"):GetDataStore(Flags.STORE)
end

-- server: read now and every POLL seconds; publish to ReplicatedStorage attributes
function Flags.init()
	local RS = game:GetService("ReplicatedStorage")
	local key = Flags.key(game:GetService("RunService"):IsStudio())
	local function apply(raw)
		for name, on in Flags.parse(raw) do
			if RS:GetAttribute("Flag_" .. name) ~= on then
				RS:SetAttribute("Flag_" .. name, on)
				if on == false then print(("[SV] flag %s is OFF (%s)"):format(name, key)) end
			end
		end
	end
	apply(nil)   -- defaults first: a slow or failed read never leaves a client guessing
	task.spawn(function()
		while true do
			local ok, raw = pcall(function() return store():GetAsync(key) end)
			if ok then apply(raw) end   -- a failed read keeps the last good values
			task.wait(Flags.POLL)
		end
	end)
end

-- Studio (Edit): the stored record for a scope ("live" / "studio")
function Flags.get(scope)
	local ok, raw = pcall(function() return store():GetAsync(scope or "live") end)
	if not ok then return { ok = false, err = tostring(raw) } end
	return { ok = true, flags = Flags.parse(raw), raw = raw }
end

-- Studio (Edit): switch one flag; servers pick it up within POLL seconds
function Flags.set(name, value, scope)
	local good, why = Flags.check(name, value)
	if not good then return { ok = false, err = why } end
	scope = scope or "live"
	local ok, err = pcall(function()
		store():UpdateAsync(scope, function(old)
			local t = type(old) == "table" and old or {}
			t[name] = value
			t.updated = os.time()
			return t
		end)
	end)
	return { ok = ok, err = (not ok) and tostring(err) or nil, scope = scope, name = name, value = value }
end

return Flags
