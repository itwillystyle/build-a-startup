--[[ publish_lib -- the pure half of `bas checkup publish` (27 Oct 2026): is Studio exactly main?

	Before Alt+P, every script Rojo manages must be in Studio once, with main's code, as the
	script type main says, switched on, and nothing else may be anywhere in the place. On 27 Oct
	Rojo served main while 7 Bob scripts from another branch stayed in Studio
	($ignoreUnknownInstances keeps what Rojo does not know) and SourceHash.compare passed, because
	it only checks file -> Studio. v2 (same day, after review): the fingerprint covers every
	service, records class and enabled state, and files this check cannot verify fail it.

	Both sides are keyed by instance path ("ServerScriptService/HQMeta/Dome", names joined with
	"/"), so two scripts with one name in different folders never mix. A Studio entry is
	{ h = hash, c = ClassName, e = enabled }. No fs, no net: tables in, tables out
	(tests/offline/publishcheck.spec.luau). ]]
local SourceHash = require("../src/ReplicatedStorage/SourceHash")

local P = {}

P.MAX_AGE = 10 * 60   -- a fingerprint older than this is not proof of what Alt+P will ship
P.SKEW = 60           -- seconds of clock difference allowed for a fingerprint "from the future"

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

local INIT = { ["init.lua"] = true, ["init.luau"] = true, ["init.server.lua"] = true, ["init.server.luau"] = true,
	["init.client.lua"] = true, ["init.client.luau"] = true }

-- Rojo's name for a script file: Foo.server.lua -> Foo, Foo.Bar.lua -> Foo.Bar
local function stemOf(file)
	return string.match(file, "^(.-)%.server%.luau?$") or string.match(file, "^(.-)%.client%.luau?$")
		or string.match(file, "^(.-)%.luau?$")
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
			local dir, file = string.match(rest, "^(.*)/([^/]+)$")
			file = file or rest
			local parts = { m.inst }
			if INIT[file] then   -- init.* IS its folder
				if dir then table.insert(parts, dir) end
			else
				if dir then table.insert(parts, dir) end
				local stem = stemOf(file)
				if not stem then return nil end
				table.insert(parts, stem)
			end
			return table.concat(parts, "/")
		end
	end
	return nil
end

-- the class Rojo makes from a script file's name
function P.classOf(path)
	if string.match(path, "%.server%.luau?$") then return "Script" end
	if string.match(path, "%.client%.luau?$") then return "LocalScript" end
	return "ModuleScript"
end

-- files Rojo turns into instances (some with scripts or properties inside) that this check does
-- not read: their presence fails it instead of passing unchecked
function P.unverifiable(path)
	path = string.lower(path)
	for _, ext in { "%.json$", "%.toml$", "%.rbxm$", "%.rbxmx$", "%.ya?ml$" } do
		if string.match(path, ext) then return true end
	end
	return false
end

function P.emptyAudit()
	return { changed = {}, missing = {}, extra = {}, doubled = {}, wrongType = {}, disabled = {} }
end

-- files { { inst, text, class } } vs Studio { [inst] = { { h, c, e }, ... } } -> what does not match
function P.audit(files, studio)
	local a = P.emptyAudit()
	local known = {}
	for _, f in files do
		known[f.inst] = true
		local have = studio[f.inst]
		if not have or #have == 0 then
			table.insert(a.missing, f.inst)
		elseif #have > 1 then
			table.insert(a.doubled, f.inst)
		else
			local s = have[1]
			if s.h ~= SourceHash.hash(f.text) then table.insert(a.changed, f.inst) end
			if s.c ~= (f.class or "ModuleScript") then table.insert(a.wrongType, ("%s (Studio %s, main %s)"):format(f.inst, tostring(s.c), tostring(f.class))) end
			if s.e == false then table.insert(a.disabled, f.inst) end
		end
	end
	for inst in studio do
		if not known[inst] then table.insert(a.extra, inst) end
	end
	for _, l in a do table.sort(l) end
	return a
end

function P.clean(a)
	for _, l in a do
		if #l > 0 then return false end
	end
	return true
end

local WHAT = {
	{ "changed", "changed (Studio has different code)" },
	{ "missing", "missing (in main, not in Studio)" },
	{ "extra", "extra (in Studio, not in main)" },
	{ "doubled", "doubled (two copies: one Rojo plugin too many)" },
	{ "wrongType", "the wrong script type" },
	{ "disabled", "switched off in Studio" },
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

-- is a fingerprint taken at `at` proof of what Alt+P will ship now?
function P.fresh(at, now, commitAt)
	if type(at) ~= "number" then return false, "the fingerprint has no time" end
	if at > now + P.SKEW then return false, "the fingerprint is from the future" end
	if at < commitAt then return false, "the fingerprint is older than the commit" end
	if now - at > P.MAX_AGE then return false, ("the fingerprint is %d min old (max %d)"):format(math.floor((now - at) / 60), P.MAX_AGE / 60) end
	return true, ("taken %d min ago"):format(math.floor((now - at) / 60))
end

return P
