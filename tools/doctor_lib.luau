--[[ doctor_lib -- the pure half of `bas checkup` (11 Oct 2026): judge a game-doctor run.

	GameDoctor (in Studio) writes a report: steps, and in each step checks that are
	ok or not, with a severity, what it measured and what it expected. This turns
	that into findings ranked worst first, says which are NEW since the last run and
	which got FIXED, and writes DOCTOR.md and the short Discord summary.

	No fs, no net: tables in, tables and text out (tests/offline/doctor.spec.luau). ]]
local D = {}

D.ORDER = { BLOCKER = 1, BUG = 2, MISSING = 3, FEEL = 4 }
D.MEANS = {
	BLOCKER = "the loop breaks: a player gets stuck or loses what they worked for",
	BUG = "wrong, but you can play on",
	MISSING = "works, but something a player expects (an animation, a sound, feedback) is not there",
	FEEL = "works, feels janky",
}
D.DISCORD_MAX = 1900      -- Discord's limit is 2000 characters a message
D.TOP = 6

local function str(v)
	if v == nil then return "-" end
	return tostring(v)
end

-- -> findings (failed checks, worst first) and infos (the measured-only rows)
function D.findings(report)
	local out, infos = {}, {}
	for _, st in ipairs(report.steps or {}) do
		for _, c in ipairs(st.checks or {}) do
			if c.info then
				table.insert(infos, { step = st.name, name = c.name, measured = c.measured, detail = c.detail })
			elseif not c.ok then
				table.insert(out, { key = st.name .. " / " .. c.name, step = st.name, name = c.name,
					severity = c.severity or "BUG", measured = c.measured, expected = c.expected, detail = c.detail })
			end
		end
	end
	table.sort(out, function(a, b)
		local x, y = D.ORDER[a.severity] or 9, D.ORDER[b.severity] or 9
		if x ~= y then return x < y end
		return a.key < b.key
	end)
	-- a run that did not finish outranks everything it did find
	if report.aborted then
		table.insert(out, 1, { key = "run / aborted", step = "run", name = "aborted", severity = "BLOCKER", detail = report.aborted })
	end
	if report.crashed then
		table.insert(out, 1, { key = "run / crashed", step = "run", name = "the doctor crashed", severity = "BLOCKER", detail = report.crashed })
	end
	return out, infos
end

-- the same problem on several HQ levels is one finding: "hq:9 / x" and "hq:18 / x" share "hq / x"
function D.family(key)
	return (key:gsub("^(%a+):%w+", "%1"))
end

-- prev = list of keys from the last run -> { new = {finding}, still = {finding}, fixed = {key} }
function D.diff(prevKeys, findings)
	local prev, now = {}, {}
	for _, k in ipairs(prevKeys or {}) do prev[D.family(k)] = true end
	local out = { new = {}, still = {}, fixed = {} }
	for _, f in ipairs(findings) do
		local fam = D.family(f.key)
		if not now[fam] then
			now[fam] = true
			table.insert(prev[fam] and out.still or out.new, f)
		end
	end
	for fam in pairs(prev) do
		if not now[fam] then table.insert(out.fixed, fam) end
	end
	table.sort(out.fixed)
	return out
end

function D.counts(findings)
	local c = { BLOCKER = 0, BUG = 0, MISSING = 0, FEEL = 0 }
	for _, f in ipairs(findings) do c[f.severity] = (c[f.severity] or 0) + 1 end
	return c
end

local function verdict(c)
	if c.BLOCKER > 0 then return "RED" end
	if c.BUG > 0 then return "AMBER" end
	return "GREEN"
end

local function countLine(c)
	local parts = {}
	for _, s in ipairs({ "BLOCKER", "BUG", "MISSING", "FEEL" }) do
		if c[s] > 0 then table.insert(parts, ("%d %s"):format(c[s], s)) end
	end
	return #parts > 0 and table.concat(parts, ", ") or "nothing found"
end

-- DOCTOR.md
function D.markdown(report, findings, infos, diff, when)
	local c = D.counts(findings)
	local md = {}
	local function add(s) table.insert(md, s) end
	add(("# Game doctor: %s"):format(verdict(c)))
	add("")
	add(("%s · %s · %d new, %d still open, %d fixed since the last posted run"):format(when or "", countLine(c), #diff.new, #diff.still, #diff.fixed))
	if report.start then
		add(("Played as Wilz from HQ level %s; the save is restored afterwards."):format(str(report.start.hqLevel)))
	end
	add("")
	add("## Findings, worst first")
	if #findings == 0 then add("- none") end
	local isNew = {}
	for _, f in ipairs(diff.new) do isNew[D.family(f.key)] = true end
	for _, f in ipairs(findings) do
		add(("- **%s** %s%s: measured %s, want %s%s"):format(f.severity, isNew[D.family(f.key)] and "NEW " or "", f.key,
			str(f.measured), str(f.expected), f.detail and (". " .. f.detail) or ""))
	end
	add("")
	add("## Fixed since the last posted run")
	if #diff.fixed == 0 then add("- none") end
	for _, k in ipairs(diff.fixed) do add("- " .. k) end
	add("")
	add("## Measured")
	for _, i in ipairs(infos) do add(("- %s / %s: %s%s"):format(i.step, i.name, str(i.measured), i.detail and (" (" .. i.detail .. ")") or "")) end
	add("")
	add("## Steps")
	for _, st in ipairs(report.steps or {}) do
		local fails = 0
		for _, ch in ipairs(st.checks or {}) do if not ch.ok then fails += 1 end end
		add(("- %s: %d checks, %d failed, %s s"):format(st.name, #(st.checks or {}), fails, str(st.seconds)))
	end
	add("")
	add("## Not checked")
	for _, n in ipairs(report.notChecked or {}) do add("- " .. n) end
	add("")
	add("Severity: " .. table.concat({
		"BLOCKER = " .. D.MEANS.BLOCKER, "BUG = " .. D.MEANS.BUG, "MISSING = " .. D.MEANS.MISSING, "FEEL = " .. D.MEANS.FEEL }, "; ") .. ".")
	return table.concat(md, "\n") .. "\n"
end

-- the Discord message: the verdict, the worst few, what got fixed; never over DISCORD_MAX
function D.discord(findings, diff, when)
	local c = D.counts(findings)
	local lines = { ("**Game doctor** %s · %s · %s"):format(verdict(c), when or "", countLine(c)) }
	local isNew = {}
	for _, f in ipairs(diff.new) do isNew[D.family(f.key)] = true end
	local shown, fams = 0, {}
	for _, f in ipairs(findings) do
		local fam = D.family(f.key)
		if not fams[fam] and shown < D.TOP then
			fams[fam] = true
			shown += 1
			local d = f.detail and (" · " .. tostring(f.detail):sub(1, 140)) or ""
			table.insert(lines, ("• `%s` %s%s: %s (want %s)%s"):format(f.severity, isNew[fam] and "🆕 " or "", f.key, str(f.measured), str(f.expected), d))
		end
	end
	local rest = 0
	for _, f in ipairs(findings) do if not fams[D.family(f.key)] then rest += 1 end end
	if rest > 0 then table.insert(lines, ("…and %d more in DOCTOR.md"):format(rest)) end
	if #diff.fixed > 0 then table.insert(lines, "✅ fixed since last run: " .. table.concat(diff.fixed, ", ")) end
	if #findings == 0 then table.insert(lines, "Nothing found. Not checked: cars, phones, two players, how it looks.") end
	local text = table.concat(lines, "\n")
	if #text > D.DISCORD_MAX then text = text:sub(1, D.DISCORD_MAX - 1) .. "…" end
	return text
end

return D
