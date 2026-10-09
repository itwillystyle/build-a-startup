--[[ fuzz_remotes.luau -- fire junk at every client->server remote and watch what moves.

	Studio only, Wilz (or a negative test id) only, CLIENT datamodel, in Play, after the
	`snapshot` scenario. Paste this whole file into execute_luau (datamodel Client).
	Set FROM / TO to run a slice (the bridge call times out on all 49 at once).
	Restore the save after Play stops (verify-game skill, step 10).

	What a pass means: no junk call changed a number it should not, and no number
	jumped further than the game moves it on its own. What it cannot see: changes
	only the server holds (it reads leaderstats and player attributes) and other
	players' state. Pair it with the server's own error log for the same window.

	Read the server side with tools/fuzz_watch_server.luau (paste it into the Server datamodel
	BEFORE this file, read ServerStorage.FuzzLog after). First run, 9 Oct 2026: 49 remotes,
	~22,500 calls, no duplication; SetName drained the DataStore write budget (280 throttled
	writes) and was fixed; the re-run had 0 server errors and a 19 ms worst frame.

	Not fired: PhoneAction with real action names (a real "text" or "call" can reach
	the AI Worker, which costs money). It still gets the junk-type round. ]]
local FROM, TO = 1, 99
local WATCH = 0.6           -- seconds to watch after each remote's barrage
local SPAM = 100            -- rapid fires per remote, last round

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local lp = Players.LocalPlayer

-- ============ what the client can see ============
local function snapshot()
	local s = {}
	local ls = lp:FindFirstChild("leaderstats")
	for _, v in ipairs(ls and ls:GetChildren() or {}) do s["ls." .. v.Name] = v.Value end
	for k, v in pairs(lp:GetAttributes()) do s["@" .. k] = v end
	return s
end
local function cash() local ls = lp:FindFirstChild("leaderstats") return ls and ls:FindFirstChild("Cash") and ls.Cash.Value or 0 end

-- ============ the junk ============
local deep = {}
do local t = deep for _ = 1, 40 do t.x = {} t = t.x end end
local JUNK = {
	{}, { 0 }, { -1 }, { 1e308 }, { -1e308 }, { 0 / 0 }, { math.huge }, { -math.huge }, { "" },
	{ string.rep("A", 20000) }, { true }, { {} }, { { 1, 2, 3 } }, { deep }, { workspace }, { lp },
	{ Vector3.new(1e9, -1e9, 0 / 0) }, { CFrame.new() }, { -1, -1, -1, -1 }, { 0 / 0, 0 / 0, 0 / 0, 0 / 0 },
	{ "", "", "" }, { { ids = { 1, 2, 3 } } }, { { -1, 0 / 0, 1e9 } },
}
-- names this game uses for things, each with bad numbers: reaches past the type checks
local WORDS = { "hatch", "sport", "supercar", "studio", "loft", "penthouse", "eng", "labs", "board", "lobby",
	"cafe", "servers", "T_", "D_", "W_", "energy", "coffee", "accept", "decline", "desk", "plant", "genius",
	"skilled", "star", "vip", "1", "Plot2" }
local NUMS = { -1, 1e9, 0 / 0, 3 }
local NO_WORDS = { PhoneAction = true }   -- see the header: real actions can spend money

local function fire(r, args)
	if r:IsA("RemoteFunction") then
		task.spawn(function() pcall(function() r:InvokeServer(table.unpack(args)) end) end)
	else
		pcall(function() r:FireServer(table.unpack(args)) end)
	end
end

-- ============ control: how the numbers move with nobody touching anything ============
local function watchWindow(seconds)
	local before = snapshot()
	local maxUp, down, last = 0, false, cash()
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		task.wait(0.05)
		local c = cash()
		if c > last then maxUp = math.max(maxUp, c - last) end
		if c < last then down = true end
		last = c
	end
	return before, snapshot(), maxUp, down
end

local c0, c1, ctrlUp = watchWindow(3)
-- these move on their own on a slower clock than the 3 s control window
local volatile = { ["@ProductProgress"] = true, ["@PhoneUnread"] = true }
for k, v in pairs(c1) do if c0[k] ~= v then volatile[k] = true end end

-- ============ the run ============
local remotes = {}
for _, d in ipairs(RS:GetDescendants()) do
	if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("UnreliableRemoteEvent") then table.insert(remotes, d) end
end
table.sort(remotes, function(a, b) return a.Name < b.Name end)

local report = { control = { cashStepMax = ctrlUp, volatile = {} }, flags = {}, fired = 0, remotes = 0 }
for k in pairs(volatile) do table.insert(report.control.volatile, k) end
table.sort(report.control.volatile)

for i = FROM, math.min(TO, #remotes) do
	local r = remotes[i]
	local before = snapshot()
	local last, worstUp, wentDown = cash(), 0, false
	local function sampleCash()
		local c = cash()
		if c > last then worstUp = math.max(worstUp, c - last) end
		if c < last then wentDown = true end
		last = c
	end
	local n = 0
	for _, a in ipairs(JUNK) do fire(r, a) n += 1 end
	if not NO_WORDS[r.Name] then
		for _, w in ipairs(WORDS) do
			fire(r, { w }) n += 1
			for _, x in ipairs(NUMS) do fire(r, { w, x }) fire(r, { w, x, x, x }) n += 2 end
		end
	end
	sampleCash()
	for _ = 1, SPAM do fire(r, {}) n += 1 end
	if not NO_WORDS[r.Name] then for _ = 1, SPAM do fire(r, { WORDS[1] }) n += 1 end end
	local t0 = os.clock()
	while os.clock() - t0 < WATCH do task.wait(0.05) sampleCash() end
	local after = snapshot()
	local moved = {}
	for k, v in pairs(after) do
		local was = before[k]
		if was ~= v and not volatile[k] then
			table.insert(moved, ("%s %s -> %s"):format(k, tostring(was), tostring(v)))
		end
	end
	for k in pairs(before) do if after[k] == nil then table.insert(moved, k .. " removed") end end
	if worstUp > ctrlUp * 3 + 1 then table.insert(moved, ("cash jumped %d in one step (normal max %d)"):format(worstUp, ctrlUp)) end
	if wentDown then table.insert(moved, "cash went DOWN") end
	if #moved > 0 then
		table.sort(moved)
		report.flags[r.Name] = table.concat(moved, "; ")
	end
	report.fired += n
	report.remotes += 1
	task.wait(0.1)
end
return report
