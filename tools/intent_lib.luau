--[[ intent_lib.luau -- read a PR's intent card and say what is missing (7 Nov 2026). Pure.

	CONSTRAINTS.md rule 6 ("every PR opens with the intent card") was prose from 13 Oct, and
	0 of PRs #65-#94 carried it: a rule nobody checks drifts (Theo on the Claude Code team's
	review post, 7 Nov: fix it in the code, then in a check, prose last). `bas intent` runs
	this in CI on every PR (.github/workflows/intent.yml); tests/offline/intent.spec.luau.

	The card is one "Label: answer" per field (bold or not, any case; the answer may start on
	the next line). Hints in the template are HTML comments, so an untouched template is empty.
	  Should do / Must not break / Measured / Not measured   rule 6, as written
	  Evidence   what Luke looks at instead of the diff (a screenshot, a clip, a doctor report).
	             Needed when game code changed; docs and tooling PRs may leave it out.
	  Review     the fresh-context review before the PR: rounds, findings, fixed or answered
	  Risk       "needs Luke (...)" or "routine". Must say needs Luke when `bas risk` does.
	  Undo       a flag, a revert, or a place version ]]
local I = {}

I.FIELDS = { "Should do", "Must not break", "Measured", "Not measured", "Evidence", "Review", "Risk", "Undo" }
local OPTIONAL_UNLESS_GAME = { Evidence = true }

local function trim(s) return (s or ""):match("^%s*(.-)%s*$") end

-- a bullet ("- ", "* ", "> ") or heading marks in front of a label are fine; "**" bold is not a bullet
local function stripLead(line)
	local l = line:gsub("^%s+", "")
	l = l:gsub("^[%-%*>]%s+", "")
	l = l:gsub("^#+%s*", "")
	return l
end

-- the label a line starts with, and the rest of the line; nil when it starts with none
local function labelOf(line, lowerLabels)
	local body = stripLead(line)
	local l = body:lower()
	for _, label in lowerLabels do
		for _, form in { "**" .. label .. ":**", "**" .. label .. "**:", label .. ":" } do
			if l:sub(1, #form) == form then
				return label, trim(body:sub(#form + 1))   -- lower() keeps byte offsets for ASCII labels
			end
		end
	end
	return nil
end

-- body -> { [lower label] = answer }
function I.parse(body)
	body = (body or ""):gsub("<!%-%-.-%-%->", "")   -- template hints
	local lowerLabels = {}
	for _, f in I.FIELDS do table.insert(lowerLabels, f:lower()) end
	-- longest first, so "not measured" is not read as "measured"
	table.sort(lowerLabels, function(a, b) return #a > #b end)
	local out, current = {}, nil
	for line in (body .. "\n"):gmatch("([^\n]*)\n") do
		line = line:gsub("\r$", "")
		local label, rest = labelOf(line, lowerLabels)
		if label then
			current = label
			out[label] = rest
		elseif trim(line) == "" or line:match("^%s*#") then
			-- a blank line or a heading ends the field: a later paragraph (the attribution line
			-- every PR ends with) must not fill an empty Undo (review round 1, 7 Nov)
			current = nil
		elseif current then
			out[current] = trim(out[current] .. " " .. trim(line))
		end
	end
	return out
end

local function isPlaceholder(v)
	v = trim(v)
	if v == "" then return true end
	local l = v:lower()
	if l == "todo" or l == "tbd" or l == "..." or l == "-" or l == "n/a?" then return true end
	if v:match("^<[^>]*>$") then return true end
	return false
end

-- body, risk = { needsLuke, counts } (from risk_lib.classify) -> { ok, problems, fields }
function I.check(body, risk)
	local f = I.parse(body)
	local problems = {}
	-- game code = anything under src/: gameplay, and the save and economy files risk_lib splits out
	local c = (risk and risk.counts) or {}
	local game = ((c.gameplay or 0) + (c.save or 0) + (c.economy or 0)) > 0
	for _, label in I.FIELDS do
		local v = f[label:lower()]
		if OPTIONAL_UNLESS_GAME[label] and not game and (v == nil or isPlaceholder(v)) then
			continue
		end
		if v == nil then
			table.insert(problems, label .. ": missing (see .github/pull_request_template.md)")
		elseif isPlaceholder(v) then
			table.insert(problems, label .. ": still the template, write the answer")
		end
	end
	local rv = f["risk"]
	if rv and not isPlaceholder(rv) then
		local l = rv:lower()
		local saysLuke = l:find("needs luke", 1, true) ~= nil
		local saysRoutine = l:sub(1, 7) == "routine"
		if not saysLuke and not saysRoutine then
			table.insert(problems, 'Risk: say "needs Luke (<kinds>)" or "routine", as `bas risk` prints it')
		elseif risk and risk.needsLuke and not saysLuke then
			local kinds = {}
			for k, n in risk.counts or {} do
				if n > 0 and k ~= "docs" and k ~= "tooling" then table.insert(kinds, k) end
			end
			table.sort(kinds)
			table.insert(problems, ("Risk: says routine, but bas risk says needs Luke (%s)"):format(table.concat(kinds, ", ")))
		end
	end
	return { ok = #problems == 0, problems = problems, fields = f }
end

return I
