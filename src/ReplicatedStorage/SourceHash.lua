--[[ SourceHash (12 Oct 2026): proves which code a Studio test ran.

	The game doctor plays the game in Studio. A doctor verdict on a pull request is
	only worth something if Studio was running THAT pull request's code: Rojo may be
	disconnected, on another branch, or behind. So the routine fingerprints every
	script in Studio (Edit mode can read Source; a running game cannot) and
	`bas checkup pr` fingerprints every src file on the commit. Every file must
	match, or the verdict does not count.

	FNV-1a 32-bit over the text with carriage returns removed (Windows files, Studio
	text). The multiply is split so it stays exact in a double: prime = 2^24 + 403.
	Pure: the same module runs in Studio and in Lune (tests/offline/sourcehash.spec). ]]
local SourceHash = {}

local OFFSET = 2166136261
local TWO32 = 4294967296

function SourceHash.hash(text)
	text = string.gsub(text, "\r", "")
	local h = OFFSET
	local n = #text
	local i = 1
	while i <= n do
		local j = math.min(i + 3999, n)
		local bytes = { string.byte(text, i, j) }
		for _, b in bytes do
			h = bit32.bxor(h, b)
			h = (bit32.lshift(h, 24) + h * 403) % TWO32
		end
		i = j + 1
	end
	return string.format("%08x", h)
end

-- Studio side: { [name] = { hash, ... } } for every script under the given roots
function SourceHash.collect(roots)
	local out = {}
	for _, root in roots do
		for _, d in root:GetDescendants() do
			if d:IsA("LuaSourceContainer") then
				local ok, src = pcall(function() return d.Source end)
				if ok and type(src) == "string" then
					out[d.Name] = out[d.Name] or {}
					table.insert(out[d.Name], SourceHash.hash(src))
				end
			end
		end
	end
	return out
end

-- the instance name Rojo gives a file: Foo.server.lua -> Foo, Dir/init.lua -> Dir
function SourceHash.nameOf(path)
	path = string.gsub(path, "\\", "/")
	local dir, file = string.match(path, "^(.-)([^/]+)$")
	local stem = string.match(file, "^(.-)%.server%.luau?$") or string.match(file, "^(.-)%.client%.luau?$")
		or string.match(file, "^(.-)%.luau?$")
	if stem == "init" then
		return string.match(dir, "([^/]+)/$")
	end
	return stem
end

-- disk files { { path, text } } against a Studio collection -> list of mismatches (empty = same code)
function SourceHash.compare(files, studio)
	local bad = {}
	for _, f in files do
		local name = SourceHash.nameOf(f.path)
		local want = SourceHash.hash(f.text)
		local have = studio[name]
		local found = false
		for _, h in have or {} do
			if h == want then found = true break end
		end
		if not found then
			table.insert(bad, ("%s: %s"):format(f.path, have and "Studio has different code" or "not in Studio"))
		end
	end
	return bad
end

return SourceHash
