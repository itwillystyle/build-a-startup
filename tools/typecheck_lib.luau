--[[ typecheck_lib: reads luau-lsp's analyze output and compares it with the baseline (26 Oct 2026).
	Pure (no process, no files): tests/offline/typecheck.spec.luau.

	An error is named by its file and message, never its line: lines move with every edit.
	A sealed table's field list ("{| a: any, b: any |}") is cut to "{...}", so adding a field to
	that table does not rename every error that mentions it. The gate fails when a name's count
	grows; a count that shrinks is a fix, to be locked in with --update. ]]

local L = {}

-- each outermost "{| ... |}" becomes "{...}", by depth, so arrays, unions and nesting inside a
-- shape are cut with it (review rounds 1-2: two gsub loops missed `{number}` and `number | nil`)
local function clean(msg)
	local out, depth, i = {}, 0, 1
	while i <= #msg do
		local two = msg:sub(i, i + 1)
		if two == "{|" then
			if depth == 0 then table.insert(out, "{...}") end
			depth += 1
			i += 2
		elseif two == "|}" and depth > 0 then
			depth -= 1
			i += 2
		else
			if depth == 0 then table.insert(out, msg:sub(i, i)) end
			i += 1
		end
	end
	return (table.concat(out):gsub("%s+$", ""))
end

-- -> { {path, line, col, msg, key} }, TypeErrors and SyntaxErrors, exact duplicates dropped (luau-lsp
-- reports a module once per script that requires it)
function L.parse(out)
	local list, seen = {}, {}
	for raw in (out or ""):gmatch("[^\r\n]+") do
		local path, line, col, kind, msg = raw:match("^(.-)%s*%[[^%]]*%]%((%d+),(%d+)%): (%a+Error): (.*)$")
		if not path then path, line, col, kind, msg = raw:match("^(.-)%((%d+),(%d+)%): (%a+Error): (.*)$") end
		if path and kind ~= "TypeError" and kind ~= "SyntaxError" then path = nil end
		if path and kind == "SyntaxError" then msg = "SyntaxError: " .. msg end   -- a file that cannot parse is never type-checked
		if path then
			path = path:gsub("\\", "/")
			path = path:match("^(src/.*)$") or path:match(".*/(src/.*)$") or path   -- the LAST src/: the repo's
			local one = path .. ":" .. line .. ":" .. col .. ":" .. msg
			if not seen[one] then
				seen[one] = true
				msg = clean(msg)
				table.insert(list, { path = path, line = tonumber(line), col = tonumber(col), msg = msg, key = path .. "\t" .. msg })
			end
		end
	end
	return list
end

function L.tally(errors)
	local t = {}
	for _, e in errors do t[e.key] = (t[e.key] or 0) + 1 end
	return t
end

-- the baseline file: one "count<TAB>path<TAB>message" line per name, sorted, so a diff reads well
function L.format(t)
	local keys = {}
	for k in t do table.insert(keys, k) end
	table.sort(keys)
	local lines = { "# luau-lsp TypeErrors allowed per file + message. Written by: lune run tools/typecheck --update" }
	for _, k in keys do table.insert(lines, ("%d\t%s"):format(t[k], k)) end
	return table.concat(lines, "\n") .. "\n"
end

function L.load(text)
	local t = {}
	for line in (text or ""):gmatch("[^\r\n]+") do
		local n, key = line:match("^(%d+)\t(.+)$")
		if n then t[key] = tonumber(n) end
	end
	return t
end

-- -> { grew = { {key, was, now} }, shrank = { {key, was, now} } }
function L.diff(base, now)
	local d = { grew = {}, shrank = {} }
	for k, n in now do
		local was = base[k] or 0
		if n > was then table.insert(d.grew, { key = k, was = was, now = n }) end
	end
	for k, was in base do
		local n = now[k] or 0
		if n < was then table.insert(d.shrank, { key = k, was = was, now = n }) end
	end
	table.sort(d.grew, function(a, b) return a.key < b.key end)
	table.sort(d.shrank, function(a, b) return a.key < b.key end)
	return d
end

-- the lines to print for the new errors: every place the grown name occurs, as path:line
function L.report(d, errors)
	local grown = {}
	for _, g in d.grew do grown[g.key] = g end
	local out = {}
	for _, e in errors do
		if grown[e.key] then table.insert(out, ("%s:%d  %s"):format(e.path, e.line, e.msg)) end
	end
	return out
end

return L
