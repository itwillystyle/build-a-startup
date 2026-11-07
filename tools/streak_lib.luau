--[[ streak_lib.luau -- how many runs in a row each finding has been open (7 Nov 2026). Pure.

	The Claude Code team's review rule (Theo, 7 Nov): every finding is fixed, or its thread is
	closed with a reason. Here the doctor's bob hip snap sat in 4 runs and the morning health
	run was RED 10 days in a row before anyone acted, so red stopped meaning anything.
	`bas checkup report` and `bas health` keep a streak per finding key; one open THRESHOLD runs
	or more with no reason in docs/KNOWN-FINDINGS.md is listed as "fix it or give a reason".
	A reason is a judge change (risk_lib: KNOWN-FINDINGS.md is "judge"), so Luke merges it.
	Tested by tests/offline/streak.spec.luau. ]]
local S = {}

S.THRESHOLD = 3
S.KNOWN_FILE = "docs/KNOWN-FINDINGS.md"

-- prev { [key] = runs } (or nil), keys open in this run -> new { [key] = runs }
function S.advance(prev, keys)
	local out = {}
	for _, k in keys or {} do
		if out[k] == nil then out[k] = ((prev or {})[k] or 0) + 1 end
	end
	return out
end

-- "- `key`: reason" lines -> { [key] = reason }; a key with no reason is not known
function S.parseKnown(text)
	local out = {}
	for line in ((text or "") .. "\n"):gmatch("([^\n]*)\n") do
		local key, reason = line:match("^%s*[%-%*]%s*`([^`]+)`%s*:%s*(.-)%s*$")
		if key and reason and reason ~= "" then out[key] = reason end
	end
	return out
end

local function sorted(list)
	table.sort(list, function(a, b)
		if a.runs ~= b.runs then return a.runs > b.runs end
		return a.key < b.key
	end)
	return list
end

-- open THRESHOLD+ runs and no reason -> { {key, runs} } longest first
function S.stale(streaks, known, threshold)
	threshold = threshold or S.THRESHOLD
	local out = {}
	for k, n in streaks or {} do
		if n >= threshold and not (known or {})[k] then table.insert(out, { key = k, runs = n }) end
	end
	return sorted(out)
end

-- still open and has a reason -> { {key, runs, reason} }
function S.explained(streaks, known)
	local out = {}
	for k, n in streaks or {} do
		local why = (known or {})[k]
		if why then table.insert(out, { key = k, runs = n, reason = why }) end
	end
	return sorted(out)
end

-- known entries no run reports any more: the reason can go
function S.unused(streaks, known)
	local out = {}
	for k in known or {} do
		if not (streaks or {})[k] then table.insert(out, k) end
	end
	table.sort(out)
	return out
end

-- the section both reports append
function S.markdown(streaks, known, threshold)
	threshold = threshold or S.THRESHOLD
	local md = { ("## Open %d+ runs: fix it, or give a reason in %s"):format(threshold, S.KNOWN_FILE) }
	local st = S.stale(streaks, known, threshold)
	if #st == 0 then table.insert(md, "- none") end
	for _, s in st do table.insert(md, ("- `%s`: %d runs"):format(s.key, s.runs)) end
	local ex = S.explained(streaks, known)
	if #ex > 0 then
		table.insert(md, "")
		table.insert(md, "Known, with a reason:")
		for _, e in ex do table.insert(md, ("- `%s` (%d runs): %s"):format(e.key, e.runs, e.reason)) end
	end
	local un = S.unused(streaks, known)
	if #un > 0 then
		table.insert(md, "")
		table.insert(md, "No longer seen, remove from " .. S.KNOWN_FILE .. ": " .. table.concat(un, ", "))
	end
	return table.concat(md, "\n")
end

return S
