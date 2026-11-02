--[[ bugrules.spec.luau: every bug with a code shape becomes a rule here (2 Nov 2026).

	Idea from poteto (@lauren on X, tibo.dog): "every time i found an issue in the code i asked bot to
	make a lint rule against it". The doctor already gets a live check for every bug Luke sees; this
	file is the static half. When a bug's cause is a line you could have spotted by reading, add a
	rule: what the bug was (date, PR, what the player saw), how to spot the line, and the few places
	that look the same but are safe (each with why). A rule must fail on the code that had the bug
	before it goes in: put that code in the rule's `old` sample.

	Rules:
	  remember-once  2 Nov, PR #87: monitors dark after a room hid and came back. OfficeCullClient
	                 saved each screen's Enabled into a table every time it met that screen; met
	                 twice in one hide, the second save read the "off" it had just written, and the
	                 room came back with its screens off. Save a value to restore later with a
	                 remember-once helper (OfficeLayout.cullRemember), not a bare assignment. ]]
local fs = require("@lune/fs")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local PROPS = { "Enabled", "Visible", "Transparency", "LocalTransparencyModifier" }

local RULES = {
	{
		id = "remember-once",
		find = function(line)
			for _, p in PROPS do
				if line:match("%[[%w_]+%]%s*=%s*[%w_%.]+%." .. p .. "%f[^%w_]") then return true end
			end
			return false
		end,
		old = "\t\t\t\t\t\troom.guis[g] = g.Enabled",
		new = "\t\t\t\t\t\tOL.cullRemember(room.guis, g, g.Enabled)",
		allow = {
			{ file = "src/ReplicatedStorage/SVCheck.lua", line = "shotState.gui[g] = g.Enabled",
				why = "runs once: inside 'if not shotState then', so a second shot never saves again" },
		},
	},
}

local function walk(dir, out)
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			walk(path, out)
		elseif name:match("%.lua$") or name:match("%.luau$") then
			table.insert(out, path)
		end
	end
	return out
end

local function allowed(rule, file, line)
	for _, a in rule.allow do
		if a.file == file and line:find(a.line, 1, true) then return true end
	end
	return false
end

-- -> list of "file:line: rule-id: text"
local function hits(rule)
	local out = {}
	for _, file in walk("src", {}) do
		local n = 0
		for line in (fs.readFile(file) .. "\n"):gmatch("([^\n]*)\n") do
			n += 1
			local code = line:gsub("%-%-.*$", "")
			if rule.find(code) and not allowed(rule, file, line) then
				table.insert(out, ("%s:%d: %s: %s"):format(file, n, rule.id, (line:gsub("^%s+", ""))))
			end
		end
	end
	return out
end

for _, rule in RULES do
	test(rule.id .. ": no line in src has the shape of the bug", function()
		local found = hits(rule)
		assert(#found == 0, table.concat(found, "\n"))
	end)

	test(rule.id .. ": the rule catches the line that had the bug, and passes its fix", function()
		assert(rule.find(rule.old), "the rule misses the old line: " .. rule.old)
		assert(not rule.find(rule.new), "the rule flags the fixed line: " .. rule.new)
	end)

	test(rule.id .. ": every allowed place still exists (a stale allow hides nothing)", function()
		for _, a in rule.allow do
			assert(fs.isFile(a.file), "allowed file is gone: " .. a.file)
			assert(fs.readFile(a.file):find(a.line, 1, true), "allowed line is gone from " .. a.file .. ": " .. a.line)
			assert(#a.why > 0, "an allow needs a reason")
		end
	end)
end

test("remember-once: other look properties count too, and a lowercase local does not", function()
	local find = RULES[1].find
	assert(find("saved[f] = f.Visible"), "Visible")
	assert(find("was[p] = p.LocalTransparencyModifier"), "LocalTransparencyModifier")
	assert(not find("memo[gui] = enabled"), "a plain local is how the helper itself stores")
	assert(not find("x.Enabled = saved[x]"), "restoring is fine")
	assert(not find("t[k] = v.EnabledAt"), "a longer name is a different field")
end)

return T
