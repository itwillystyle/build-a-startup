--[[ smoke_core.luau: refactor guard for SiliconCore (v4.2).
Run in the SERVER datamodel during Play, with a loaded save and $1M+ cash.
Drives the real code through the Studio dev hook (SVDev) and returns only
deterministic numbers: costs, multipliers, rates, pad/prompt texts, and the
saved record minus its clock fields. Run it before and after a refactor and
diff the two outputs: any line that changed is a behaviour change.
It MUTATES the save (apt, HQ, spin-off): snapshot the record first, restore after. ]]
local Players = game:GetService("Players")
local SSS = game:GetService("ServerScriptService")
local p = Players:GetPlayers()[1]
local dev = SSS:WaitForChild("SiliconCore"):WaitForChild("SVDev", 20)
local out = {}
local function add(k, v) table.insert(out, k .. "=" .. tostring(v)) end

local t0 = os.clock()
repeat task.wait(0.5) until (p:GetAttribute("Plot") and dev:Invoke("state", p).loaded) or os.clock() - t0 > 40
task.wait(2)

local function snap(tag)
	local st = dev:Invoke("state", p)
	for _, k in ipairs({ "hqLevel", "rate", "capacity", "staff", "boost", "tiers", "shipped", "placed", "name" }) do
		add(tag .. "." .. k, st[k])
	end
	for _, a in ipairs({ "PriceMult", "Prestige", "Spinoffs", "VibeStars", "VibeLuck", "Objective", "ObjectiveText", "IncomeRate", "CarrySpeed" }) do
		add(tag .. "@" .. a, p:GetAttribute(a))
	end
	local plot = workspace.SiliconValley.Plots:FindFirstChild("Plot" .. st.plot)
	local texts = {}
	for _, d in plot:GetDescendants() do
		if (d:IsA("TextLabel") and d.Text:find("%$")) then table.insert(texts, d.Text) end
		if d:IsA("ProximityPrompt") and d.Enabled then table.insert(texts, "[" .. d.ActionText .. "|" .. d.ObjectText .. "]") end
	end
	table.sort(texts)
	add(tag .. ".texts", table.concat(texts, " ; "))
end

snap("load")
add("apt", dev:Invoke("apt", p, 3))
for lv = 1, 3 do
	-- an upgrade is refused while the last one's rise animation plays: retry until the level moves
	local before = dev:Invoke("state", p).hqLevel
	for _ = 1, 4 do
		dev:Invoke("upgrade", p)
		local t1 = os.clock()
		repeat task.wait(0.25) until dev:Invoke("state", p).hqLevel ~= before or os.clock() - t1 > 3
		if dev:Invoke("state", p).hqLevel ~= before then break end
	end
	task.wait(1)
	snap("up" .. lv)
end
add("tier", dev:Invoke("tier", p, 3))
add("offer", dev:Invoke("offer", p))
add("launch", dev:Invoke("launch", p, 1))
task.wait(1)
add("spinoff", dev:Invoke("spinoff", p))
task.wait(2)
snap("spin1")
add("save", dev:Invoke("save", p))
local rec = dev:Invoke("peek", p)
if type(rec) == "table" then
	local keys = {}
	for k in pairs(rec) do table.insert(keys, k) end
	table.sort(keys)
	add("rec.keys", table.concat(keys, ","))
	for _, k in ipairs({ "hq", "spinoffs", "apt", "name", "tiers", "talents", "wings", "people", "index", "items", "cars", "car", "weekId", "vipDay", "layout", "shipped", "streak" }) do
		local v = rec[k]
		if type(v) == "table" then
			local ok, j = pcall(function() return game:GetService("HttpService"):JSONEncode(v) end)
			v = ok and j or "table"
		end
		add("rec." .. k, v)
	end
end
return table.concat(out, "\n")
