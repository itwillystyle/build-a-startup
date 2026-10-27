--[[ publish_lib -- the pure half of `bas checkup publish` (27 Oct 2026): is Studio exactly main?

	Before Alt+P, every script Rojo manages must be in Studio once, with main's code, and
	nothing else may sit in the folders Rojo manages. On 27 Oct Rojo served main while 7 Bob
	scripts from another branch stayed in Studio ($ignoreUnknownInstances keeps what Rojo
	does not know) and SourceHash.compare passed, because it only checks file -> Studio.

	Both sides are keyed by instance path ("ServerScriptService/HQMeta/Dome", names joined
	with "/"), so two scripts with one name in different folders never mix.
	No fs, no net: tables in, tables out (tests/offline/publishcheck.spec.luau). ]]
local SourceHash = require("../src/ReplicatedStorage/SourceHash")

local P = {}

local function norm(p) return (string.gsub(p, "\\", "/")) end

-- the project tree -> { { dir, inst } } for every node with a $path, deepest first
function P.mounts(tree)
	local out = {}
	local function walk(node, inst)
		if type(node) ~= "table" then return end
		if node["$path"] then table.insert(out, { dir = norm(node["$path"]), inst = inst }) end
		for k, v in node do
			if type(k) == "string" and string.sub(k, 1, 1) ~= "$" then
				walk(v, inst == "" and k or (inst .. "/" .. k))
			end
		end
	end
	walk(tree, "")
	table.sort(out, function(a, b) return #a.dir > #b.dir end)
	return out
end

-- a file path -> the instance path Rojo gives it, or nil when no mount syncs it.
-- nested: { { dir, sub } } for folders holding their own default.project.json ($path = sub)
function P.instancePath(path, mounts, nested)
	path = norm(path)
	for _, n in nested or {} do
		local pre = n.dir .. "/" .. n.sub .. "/"
		if string.sub(path, 1, #pre) == pre then
			path = n.dir .. "/" .. string.sub(path, #pre + 1)
			break
		end
	end
	for _, m in mounts do
		local pre = m.dir .. "/"
		if string.sub(path, 1, #pre) == pre then
			local rest = string.sub(path, #pre + 1)
			local name = SourceHash.nameOf(rest)
			local dir = string.match(rest, "^(.*)/[^/]+$")
			local stem = string.match(rest, "([^/]+)$")
			local isInit = string.match(stem, "^init%.") ~= nil
			local parentDir = dir
			if isInit then parentDir = string.match(dir or "", "^(.*)/[^/]+$") end   -- init.lua IS its folder
			local parts = { m.inst }
			if parentDir and parentDir ~= "" then table.insert(parts, parentDir) end
			if name then table.insert(parts, name) end
			return table.concat(parts, "/")
		end
	end
	return nil
end

-- files { { inst, text } } vs Studio { [inst] = { hash, ... } } -> what does not match
function P.audit(files, studio)
	local a = { changed = {}, missing = {}, extra = {}, doubled = {} }
	local known = {}
	for _, f in files do
		known[f.inst] = true
		local have = studio[f.inst]
		if not have or #have == 0 then
			table.insert(a.missing, f.inst)
		elseif #have > 1 then
			table.insert(a.doubled, f.inst)
		elseif have[1] ~= SourceHash.hash(f.text) then
			table.insert(a.changed, f.inst)
		end
	end
	for inst in studio do
		if not known[inst] then table.insert(a.extra, inst) end
	end
	for _, l in a do table.sort(l) end
	return a
end

function P.clean(a)
	return #a.changed == 0 and #a.missing == 0 and #a.extra == 0 and #a.doubled == 0
end

local WHAT = {
	{ "changed", "changed (Studio has different code)" },
	{ "missing", "missing (in main, not in Studio)" },
	{ "extra", "extra (in Studio, not in main: delete them)" },
	{ "doubled", "doubled (two copies: one Rojo plugin too many)" },
}

-- one line per kind that has entries, naming up to `max` of them
function P.describe(a, max)
	local lines = {}
	for _, w in WHAT do
		local l = a[w[1]]
		if #l > 0 then
			local shown = {}
			for i = 1, math.min(max, #l) do shown[i] = l[i] end
			local more = #l > max and (", and " .. (#l - max) .. " more") or ""
			table.insert(lines, ("%d %s: %s%s"):format(#l, w[2], table.concat(shown, ", "), more))
		end
	end
	return lines
end

return P
