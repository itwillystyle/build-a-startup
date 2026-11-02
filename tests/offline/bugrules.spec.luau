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
	                 remember-once helper (OfficeLayout.cullRemember), not a bare assignment.
	  save-first     2 Nov, the TLA+ join model (models/tla): IntroClient read Returning and BobNew
	                 before the server had loaded the save (MenuDone does not wait for GetAsync), so
	                 a returning player could get the new-player fly-over and a new one never met
	                 Bob. A join script waits for SaveLoaded before it reads what the save says.
	  joint-once     2 Nov: a seated staff member perched over her chair, one run in two. StaffAnimClient
	                 looked each joint up once, when the rig registered (`lH = motor(lower, "LeftHip")`);
	                 a rig reaches the client in pieces, so a hip still on its way stayed nil all session
	                 and the idle track bent it (5 of 144 arrivals). A client script keeps a rig's joints
	                 through RigJoints.resolve, called again when a Motor6D lands, not a one-shot
	                 FindFirstChild of a joint by name.
	A rule is a line rule (`find`, run on every line of src, or only on the paths matching `only`) or a
	file rule (`files` + `scan`, which gets a file's text and returns the 1-based lines that break it). ]]
local fs = require("@lune/fs")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local PROPS = { "Enabled", "Visible", "Transparency", "LocalTransparencyModifier" }
local JOINT = { "Hip", "Knee", "Elbow", "Shoulder", "Neck", "Waist", "Root", "Ankle", "Wrist" }

-- a joint looked up by name, once, and kept: `x = <...>FindFirstChild("LeftHip")` or `x = motor(p, "Root")`
local function jointOnce(line)
	if not line:match("[%w_]+%s*=%s*") then return false end
	for _, j in JOINT do
		if line:match("FindFirstChild%(%s*\"%a*" .. j .. "\"%s*%)") or line:match("motor%([^\n]-\"%a*" .. j .. "\"%s*%)") then
			return true
		end
	end
	return false
end

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
	{
		id = "save-first",
		files = { "src/StarterPlayer/StarterPlayerScripts/IntroClient.client.lua" },
		scan = function(src)
			local waited, out, n = false, {}, 0
			for line in (src .. "\n"):gmatch("([^\n]*)\n") do
				n += 1
				local code = line:gsub("%-%-.*$", "")
				if code:find('GetAttribute("SaveLoaded")', 1, true) then waited = true end
				if not waited and (code:find('GetAttribute("Returning")', 1, true) or code:find('GetAttribute("BobNew")', 1, true)) then
					table.insert(out, n)
				end
			end
			return out
		end,
		old = 'local returning = player:GetAttribute("Returning") == true',
		new = 'while player:GetAttribute("SaveLoaded") ~= true do task.wait(0.1) end\nlocal returning = player:GetAttribute("Returning") == true',
		allow = {},
	},
	{
		id = "joint-once",
		only = "%.client%.lua$",   -- the server builds a rig whole; only a client sees one arrive in pieces
		find = jointOnce,
		old = "\t\t\tlH = motor(lower, \"LeftHip\"), rH = motor(lower, \"RightHip\"),",
		new = "\t\tRigJoints.resolve(model, st)",
		allow = {},
	},
}

local function rule(id)
	for _, r in RULES do if r.id == id then return r end end
	error("no rule " .. id)
end

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

local function lineRule(rule) return rule.find ~= nil end
local function flags(rule, text)
	if lineRule(rule) then return rule.find(text) end
	return #rule.scan(text) > 0
end

-- -> list of "file:line: rule-id: text"
local function hits(rule)
	local out = {}
	if not lineRule(rule) then
		for _, file in rule.files do
			local src = fs.readFile(file)
			local lines = src:split("\n")
			for _, n in rule.scan(src) do
				table.insert(out, ("%s:%d: %s: %s"):format(file, n, rule.id, ((lines[n] or ""):gsub("^%s+", ""))))
			end
		end
		return out
	end
	for _, file in walk("src", {}) do
		if rule.only and not file:match(rule.only) then continue end
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
		assert(flags(rule, rule.old), "the rule misses the old line: " .. rule.old)
		assert(not flags(rule, rule.new), "the rule flags the fixed line: " .. rule.new)
		for _, file in rule.files or {} do assert(fs.isFile(file), "the rule's file is gone: " .. file) end
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
	local find = rule("remember-once").find
	assert(find("saved[f] = f.Visible"), "Visible")
	assert(find("was[p] = p.LocalTransparencyModifier"), "LocalTransparencyModifier")
	assert(not find("memo[gui] = enabled"), "a plain local is how the helper itself stores")
	assert(not find("x.Enabled = saved[x]"), "restoring is fine")
	assert(not find("t[k] = v.EnabledAt"), "a longer name is a different field")
end)

test("joint-once: every one-shot shape of the old lookup, and none of the safe ones", function()
	local find = rule("joint-once").find
	assert(find("\t\t\troot = motor(hrp, \"Root\") or motor(lower, \"Root\"),"), "Root through the helper")
	assert(find("\t\t\tlK = motor(model:FindFirstChild(\"LeftUpperLeg\"), \"LeftKnee\"),"), "a knee through a part lookup")
	assert(find("local neck = torso:FindFirstChild(\"Neck\")"), "a direct FindFirstChild")
	assert(not find("local leg = model:FindFirstChild(\"LeftUpperLeg\")"), "a part, not a joint")
	assert(not find("set(\"RightHip\", CFrame.Angles(R(80), 0, 0))"), "looked up fresh each frame (BobSceneClient)")
	assert(not find("lS = torso:WaitForChild(\"LeftShoulder\", 5),"), "WaitForChild waits for it")
	-- the rule walks client scripts only
	local only = rule("joint-once").only
	assert(only and ("src/StarterPlayer/StarterPlayerScripts/StaffAnimClient.client.lua"):match(only), "StaffAnimClient is walked")
	assert(not ("src/ServerScriptService/StaffRig.lua"):match(only), "the server builds a rig whole")
end)

return T
