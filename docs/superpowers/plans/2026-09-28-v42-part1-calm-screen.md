# v4.2 Part 1: Calm Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One notification per screen area at a time. Danger always wins. Nothing ambient appears while driving, carrying or in a cutscene.

**Architecture:** A client ModuleScript `ReplicatedStorage.Notify` holds one queue and three lanes (top, centre, bottom). Every transient in the game asks it first instead of showing itself. The director is a pure class (`Notify.new(env)`) with an injected clock and state, so its rules are unit-tested in Studio without a running game. The shared default instance uses the real player state.

**Tech Stack:** Roblox Luau (LocalScripts + ModuleScripts), Roblox Studio MCP (`execute_luau`, `start_stop_play`, `screen_capture`), a localhost file server for installs (`python -m http.server 8731` in `silicon-startup/`).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-09-28-v42-calm-ranks-home-design.md`, Part 1. Its tables are the contract.
- Priorities: 0 danger, 1 earned, 2 progress, 3 ambient.
- P3: at most 1 every **20 s**; drops after waiting **15 s**.
- Calm moment: centre and top lanes idle **≥ 5 s**, and not driving, carrying, in a cutscene or in a menu.
- Safety net: a lane frees itself after **8 s** (top, bottom) or **30 s** (centre) if an item never calls `done()`.
- SiliconCore sits at Luau's 200-top-level-local limit: add **no** new top-level locals to it.
- Every install goes through `tools/install.luau` (compile check + forward-use check). Disk == Studio after each task.
- Studio in **Edit** for installs. Leave Studio in Edit at the end. Snapshot the DataStore record before any live test that plays on his account; restore after.
- There is no git repo here. "Commit" = the backup copies `<File>_pre_v42.lua` made before the first edit, plus the disk == Studio check.

## File map

| File | Responsibility |
|---|---|
| `Notify.lua` → RS `Notify` (new) | the director: queue, lanes, rules, `toast()` |
| `tools/install.luau` (new) | fetch from localhost, compile check, forward-use check, write Source |
| `tests/notify_spec.luau` (new) | unit tests for the director's rules |
| `tests/notify_live_client.luau`, `tests/notify_live_server.luau` (new) | live check: fire everything at once, count what's visible per lane |
| `HudClient.lua` | HQ banner (P1 top), milestone (P2 top), While You Were Away (P2 centre, calm), WRITE CODE hides in a car |
| `TalentRevealClient.lua` | rare-hire card (P1 top) |
| `TalentRowClient.lua` | headhunter chip holds the top lane; LOST (P0 top) |
| `PhoneClient.lua` | text banner (P3, opener only), term sheet (P2), ring (P0), call pill beside the PHONE button |
| `InventoryClient.lua` | item card (P2 centre) |
| `DailyClient.lua` | auto-open (P2 centre, calm) |
| `NameClient.lua` | name prompt (P2 centre, calm) |
| `ProductClient.lua`, `CarClient.lua`, `LiftClient.lua` | all toasts go through `Notify.toast` (bottom lane) |
| `SiliconCore.lua` | the three "other players' news" toasts carry a `"news"` tag |

---

### Task 1: The director, with unit tests

**Files:**
- Create: `silicon-startup/tools/install.luau`
- Create: `silicon-startup/tests/notify_spec.luau`
- Create: `silicon-startup/Notify.lua` (installed as `ReplicatedStorage.Notify`, ModuleScript)

**Interfaces:**
- Produces (used by every later task):
  - `local Notify = require(ReplicatedStorage:WaitForChild("Notify"))`
  - `Notify.show(item) -> item`. `item = { lane = "top"|"centre"|"bottom", priority = 0..3, key = string, open = function(done) end, close = function()?, ttl = number?, fallback = function()?, calm = boolean?, valid = function(): boolean?, delay = number?, maxHold = number? }`
  - `Notify.hold(lane, key)`, `Notify.release(key)`
  - `Notify.state() -> { driving, carrying, cutscene, menu }`
  - `Notify.new(env) -> director`, with methods `:show`, `:hold`, `:release`, `:pump`. `env = { now = function(): number, state = function(): table }`

- [ ] **Step 1: Write the install tool**

`tools/install.luau`. It runs in the Edit datamodel via `execute_luau`; the caller prepends a `FILES` table.

```lua
-- tools/install.luau: prepend  local FILES = { {src="Notify.lua", path="ReplicatedStorage.Notify", class="ModuleScript"}, ... }
local HS = game:GetService("HttpService")
local function resolve(path)
	local cur = game
	local parts = string.split(path, ".")
	for i = 1, #parts - 1 do
		cur = cur:FindFirstChild(parts[i]) or game:GetService(parts[i])
		if not cur then return nil end
	end
	return cur, parts[#parts]
end
local out = {}
for _, f in ipairs(FILES) do
	local ok, src = pcall(HS.GetAsync, HS, "http://127.0.0.1:8731/" .. f.src, true)
	if not ok then table.insert(out, f.src .. ": FETCH FAILED " .. tostring(src)) continue end
	local fn, err = loadstring(src)
	if not fn then table.insert(out, f.src .. ": COMPILE FAIL " .. tostring(err)) continue end
	-- forward-use: a `local function X` called on an earlier non-comment line
	local lines = string.split(src, "\n")
	local defs, sus = {}, {}
	for i, l in ipairs(lines) do
		local n = l:match("^%s*local%s+function%s+([%w_]+)")
		if n and not defs[n] then defs[n] = i end
	end
	for n, d in pairs(defs) do
		for i = 1, d - 1 do
			local l = lines[i]
			if not l:match("^%s*%-%-") and l:find("%f[%w_]" .. n .. "%s*%(") then table.insert(sus, n .. "@" .. i); break end
		end
	end
	local parent, name = resolve(f.path)
	if not parent then table.insert(out, f.src .. ": NO PARENT " .. f.path) continue end
	local inst = parent:FindFirstChild(name)
	local created = false
	if not inst then inst = Instance.new(f.class); inst.Name = name; inst.Parent = parent; created = true end
	inst.Source = src
	table.insert(out, ("%s -> %s %d lines%s%s"):format(f.src, f.path, #lines, created and " CREATED" or "",
		#sus > 0 and (" SUSPECT " .. table.concat(sus, ",")) or ""))
end
return table.concat(out, "\n")
```

- [ ] **Step 2: Write the failing unit tests**

`tests/notify_spec.luau`. It requires a *clone*, because Studio caches `require` per module instance and a re-installed Source would otherwise run stale code.

```lua
local mod = game:GetService("ReplicatedStorage"):FindFirstChild("Notify")
if not mod then return "FAIL: ReplicatedStorage.Notify missing" end
local clone = mod:Clone()
local Notify = require(clone)
local t, st, log, fails = 0, nil, nil, {}
local function env() return { now = function() return t end, state = function() return st end } end
local function reset()
	t = 0
	st = { driving = false, carrying = false, cutscene = false, menu = false }
	log = {}
	return Notify.new(env())
end
local function item(lane, p, key, extra)
	local it = { lane = lane, priority = p, key = key }
	it.open = function(done) table.insert(log, "open " .. key); it.done = done end
	it.close = function() table.insert(log, "close " .. key) end
	it.fallback = function() table.insert(log, "fallback " .. key) end
	for k, v in pairs(extra or {}) do it[k] = v end
	return it
end
local function count(s) local n = 0 for _, l in ipairs(log) do if l == s then n += 1 end end return n end
local function expect(c, msg) if not c then table.insert(fails, msg .. "  log=" .. table.concat(log, ",")) end end

do -- 1 one per lane, next after done
	local d = reset()
	local a, b = item("top", 2, "a"), item("top", 2, "b")
	d:show(a); d:show(b)
	expect(count("open a") == 1 and count("open b") == 0, "1a one per lane")
	a.done()
	expect(count("open b") == 1, "1b next after done")
end
do -- 2 lanes are independent
	local d = reset()
	d:show(item("top", 2, "a")); d:show(item("bottom", 2, "b"))
	expect(count("open a") == 1 and count("open b") == 1, "2 top and bottom together")
end
do -- 3 priority order, then FIFO
	local d = reset()
	local a = item("bottom", 2, "a"); d:show(a)
	d:show(item("bottom", 3, "amb")); d:show(item("bottom", 2, "p2")); d:show(item("bottom", 1, "p1"))
	a.done()
	expect(count("open p1") == 1 and count("open p2") == 0, "3 P1 first")
end
do -- 4 P0 bumps a P2 (dropped, fallback) and a P1 (re-queued, shown again)
	local d = reset()
	local a = item("top", 2, "a"); d:show(a)
	local z = item("top", 0, "z"); d:show(z)
	expect(count("close a") == 1 and count("fallback a") == 1 and count("open z") == 1, "4a P0 bumps P2")
	z.done()
	local r = item("top", 1, "r"); d:show(r)
	local stale = r.done
	local z2 = item("top", 0, "z2"); d:show(z2)
	expect(count("close r") == 1 and count("fallback r") == 0, "4b P1 closed, not dropped")
	z2.done()
	expect(count("open r") == 2, "4c P1 shown again after the danger")
	stale()                                   -- the first run's late done must not end the second run
	d:show(item("top", 2, "after"))
	expect(count("open after") == 0, "4d stale done ignored")
end
do -- 5 driving: P3 dropped at once, P1 waits (never dropped), P0 shows
	local d = reset(); st.driving = true
	d:show(item("top", 3, "text")); d:show(item("top", 1, "rev"))
	expect(count("fallback text") == 1 and count("open rev") == 0, "5a driving holds P1, drops P3")
	local z = item("bottom", 0, "danger"); d:show(z)
	expect(count("open danger") == 1, "5b P0 shows while driving")
	t = 100; st.driving = false; d:pump()
	expect(count("open rev") == 1, "5c P1 after driving")
end
do -- 6 cutscene: everything waits, P3 dropped
	local d = reset(); st.cutscene = true
	d:show(item("top", 0, "z")); d:show(item("bottom", 3, "amb")); d:show(item("centre", 2, "c"))
	expect(count("open z") == 0 and count("fallback amb") == 1 and count("open c") == 0, "6a cutscene holds")
	st.cutscene = false; d:pump()
	expect(count("open z") == 1 and count("open c") == 1, "6b after cutscene")
end
do -- 7 carrying / menu hold P2, allow P1
	local d = reset(); st.carrying = true
	d:show(item("bottom", 2, "p2")); d:show(item("top", 1, "p1"))
	expect(count("open p2") == 0 and count("open p1") == 1, "7a carrying")
	st.carrying = false; st.menu = true; d:pump()
	expect(count("open p2") == 0, "7b menu holds P2")
	st.menu = false; d:pump()
	expect(count("open p2") == 1, "7c released")
end
do -- 8 P3 spacing 20 s, TTL 15 s
	local d = reset()
	local a = item("bottom", 3, "a"); d:show(a); a.done()
	d:show(item("bottom", 3, "b"))
	expect(count("open b") == 0, "8a gap holds the second ambient")
	t = 14; d:pump(); expect(count("open b") == 0, "8b still waiting at 14 s")
	t = 16; d:pump(); expect(count("fallback b") == 1, "8c dropped after 15 s")
	t = 40; local c = item("bottom", 3, "c"); d:show(c)
	expect(count("open c") == 1, "8d allowed after the gap")
end
do -- 9 hold / release
	local d = reset()
	d:hold("top", "hh")
	d:show(item("top", 2, "a")); d:show(item("top", 0, "z"))
	expect(count("open a") == 0 and count("open z") == 0, "9a hold blocks everything")
	d:release("hh")
	expect(count("open z") == 1, "9b P0 first after release")
	local d2 = reset()
	local b = item("top", 2, "b"); d2:show(b)
	d2:hold("top", "hh")
	expect(count("close b") == 1, "9c hold bumps what is showing")
end
do -- 10 safety net
	local d = reset()
	d:show(item("top", 2, "stuck")); d:show(item("top", 2, "next"))
	t = 7; d:pump(); expect(count("open next") == 0, "10a before 8 s")
	t = 8.5; d:pump(); expect(count("close stuck") == 1 and count("open next") == 1, "10b freed after 8 s")
end
do -- 11 calm needs 5 s idle in centre and top
	local d = reset()
	d:show(item("centre", 2, "calm", { calm = true }))
	expect(count("open calm") == 0, "11a not calm at 0 s")
	t = 5.1; d:pump(); expect(count("open calm") == 1, "11b calm at 5 s")
	local d2 = reset(); t = 10
	local x = item("top", 2, "x"); d2:show(x)
	d2:show(item("centre", 2, "calm2", { calm = true }))
	t = 12; x.done(); t = 14; d2:pump()
	expect(count("open calm2") == 0, "11c top was busy 2 s ago")
	t = 17.1; d2:pump(); expect(count("open calm2") == 1, "11d calm 5 s after top freed")
end
do -- 12 centre and top exclude each other (a phone's centre card reaches the top strip)
	local d = reset()
	local c = item("centre", 2, "card"); d:show(c)
	d:show(item("top", 1, "rev")); d:show(item("top", 0, "z"))
	expect(count("open rev") == 0 and count("open z") == 1, "12a centre blocks top except P0")
	local d2 = reset()
	d2:show(item("top", 2, "strip")); d2:show(item("centre", 2, "card2"))
	expect(count("open card2") == 0, "12b top blocks centre")
end
do -- 13 valid() and delay
	local d = reset()
	local ok = false
	d:show(item("centre", 2, "v", { valid = function() return ok end }))
	expect(count("open v") == 0 and count("fallback v") == 0, "13a invalid dropped quietly")
	d:show(item("top", 1, "late", { delay = 1.6 }))
	expect(count("open late") == 0, "13b delay holds")
	t = 1.7; d:pump(); expect(count("open late") == 1, "13c after delay")
end

clone:Destroy()
return #fails == 0 and "PASS 13 groups" or ("FAIL " .. #fails .. "\n" .. table.concat(fails, "\n"))
```

- [ ] **Step 3: Run the tests to see them fail**

Start the file server (`cd /c/Users/lukex/Downloads/silicon-startup && python -m http.server 8731 --bind 127.0.0.1`, background). Run `tests/notify_spec.luau` through `execute_luau` (Edit).
Expected: `FAIL: ReplicatedStorage.Notify missing`

- [ ] **Step 4: Write the director**

`Notify.lua`:

```lua
--[[
	Notify -- ModuleScript in ReplicatedStorage. Client-side only.

	v4.2 THE CALM SCREEN. His note (28 Sep): "every interaction in the game
	shouldn't all pop up at once ... notifications from your phone, build
	notifications ... when you're driving there's also another UI pop-up."
	The audit counted 24 separate screen notifications with no shared queue:
	a phone text landed exactly on the headhunter warning mid-chase.

	One referee. Every transient asks here first:
	  Notify.show{ lane, priority, key, open(done), close?, ttl?, fallback?,
	               calm?, valid?, delay?, maxHold? }
	    lane      "top" | "centre" | "bottom"; one item per lane at a time
	    priority  0 danger · 1 earned · 2 progress · 3 ambient
	    open      draws it; call done() when it has gone
	    close     hides it early (danger needed the lane)
	    fallback  runs instead when it is dropped (e.g. the phone badge)
	    calm      only at a calm moment: centre and top idle 5 s, not busy
	    valid     checked before showing; false = drop quietly
	    delay     seconds before it may show
	  Notify.hold(lane, key) / Notify.release(key)   a live status owns a lane
	  Notify.state()   { driving, carrying, cutscene, menu }
	  Notify.toast(text, opts)   the one bottom toast (see Task 4)
	The rules are the table in docs/superpowers/specs/2026-09-28-v42-calm-ranks-home-design.md.
]]
local Notify = {}

local LANES = { "centre", "top", "bottom" }     -- centre first: top checks it
local MAX_HOLD = { top = 8, centre = 30, bottom = 8 }
local P3_GAP = 20
local P3_TTL = 15
local CALM_IDLE = 5

local Director = {}
Director.__index = Director

function Notify.new(env)
	local self = setmetatable({}, Director)
	self.env = env
	self.lanes = {}
	local now = env.now()
	for _, name in ipairs(LANES) do
		self.lanes[name] = { name = name, current = nil, hold = nil, idleSince = now }
	end
	self.queue = {}
	self.seq = 0
	self.lastAmbient = -math.huge
	return self
end

-- "wait", "drop" or nil (allowed now)
function Director:_rule(it, st)
	local p = it.priority
	if st.cutscene then return p == 3 and "drop" or "wait" end
	if p == 0 then return nil end
	if st.driving then return p == 3 and "drop" or "wait" end
	if p == 1 then return nil end
	if st.carrying or st.menu then return p == 3 and "drop" or "wait" end
	return nil
end

function Director:_canUse(it)
	local lane = self.lanes[it.lane]
	if lane.current or lane.hold then return false end
	-- a centre card reaches up into the top strip on a phone: only danger shares
	if it.lane == "top" and it.priority > 0 and self.lanes.centre.current then return false end
	if it.lane == "centre" and self.lanes.top.current and self.lanes.top.current.priority > 0 then return false end
	return true
end

function Director:_ready(it, st, now)
	if self:_rule(it, st) then return false end
	if it.delay and now - it.t0 < it.delay then return false end
	if it.priority == 3 and now - self.lastAmbient < P3_GAP then return false end
	if it.calm then
		local c, tp = self.lanes.centre, self.lanes.top
		if c.current or tp.current or tp.hold then return false end
		if now - c.idleSince < CALM_IDLE or now - tp.idleSince < CALM_IDLE then return false end
	end
	return self:_canUse(it)
end

function Director:_open(it, now)
	local lane = self.lanes[it.lane]
	lane.current = it
	it.shownAt = now
	if it.priority == 3 then self.lastAmbient = now end
	local run = {}
	it.run = run
	local function done() if it.run == run then self:_finish(it) end end
	task.spawn(function()
		local ok, err = pcall(it.open, done)
		if not ok then
			warn(("[Notify] %s failed to open: %s"):format(tostring(it.key), tostring(err)))
			done()
		end
	end)
end

function Director:_finish(it, forced)
	local lane = self.lanes[it.lane]
	if lane.current ~= it then return end
	lane.current = nil
	it.run = nil
	lane.idleSince = self.env.now()
	if forced and it.close then pcall(it.close) end
	self:pump()
end

-- take the lane from whatever shows: earned moments come back, the rest drop
function Director:_bump(lane)
	local cur = lane.current
	if not cur then return end
	lane.current = nil
	cur.run = nil
	lane.idleSince = self.env.now()
	if cur.close then pcall(cur.close) end
	if cur.priority == 1 then
		cur.t0 = self.env.now()
		cur.delay = nil
		table.insert(self.queue, cur)
	elseif cur.fallback then
		pcall(cur.fallback)
	end
end

function Director:show(it)
	assert(type(it) == "table" and self.lanes[it.lane], "Notify.show: bad lane " .. tostring(it and it.lane))
	assert(type(it.open) == "function", "Notify.show: open() required")
	self.seq += 1
	it.seq = self.seq
	it.t0 = self.env.now()
	it.priority = it.priority or 2
	if it.priority == 3 and it.ttl == nil then it.ttl = P3_TTL end
	local lane = self.lanes[it.lane]
	if it.priority == 0 and lane.current and lane.current.priority > 0 and not lane.hold then self:_bump(lane) end
	table.insert(self.queue, it)
	self:pump()
	return it
end

function Director:hold(laneName, key)
	local lane = self.lanes[laneName]
	if not lane or lane.hold == key then return end
	lane.hold = key
	self:_bump(lane)
end

function Director:release(key)
	for _, lane in pairs(self.lanes) do
		if lane.hold == key then
			lane.hold = nil
			lane.idleSince = self.env.now()
		end
	end
	self:pump()
end

function Director:pump()
	if self.pumping then self.again = true return end
	self.pumping = true
	repeat
		self.again = false
		local now = self.env.now()
		local st = self.env.state()
		-- the safety net: a card that never said done frees its lane
		for name, lane in pairs(self.lanes) do
			local cur = lane.current
			if cur and now - cur.shownAt > (cur.maxHold or MAX_HOLD[name]) then
				lane.current = nil
				cur.run = nil
				lane.idleSince = now
				if cur.close then pcall(cur.close) end
			end
		end
		-- drop what is not allowed now, expired or no longer valid
		for i = #self.queue, 1, -1 do
			local it = self.queue[i]
			local invalid = it.valid and not it.valid()
			local expired = it.ttl and now - it.t0 > it.ttl
			if invalid or expired or self:_rule(it, st) == "drop" then
				table.remove(self.queue, i)
				if it.fallback and not invalid then pcall(it.fallback) end
			end
		end
		-- one per lane: the most urgent ready item, oldest first
		for _, name in ipairs(LANES) do
			local best, bi
			for i, it in ipairs(self.queue) do
				if it.lane == name and self:_ready(it, st, now) then
					if not best or it.priority < best.priority or (it.priority == best.priority and it.seq < best.seq) then
						best, bi = it, i
					end
				end
			end
			if best then
				table.remove(self.queue, bi)
				self:_open(best, now)
			end
		end
	until not self.again
	self.pumping = false
end

-- ============ THE SHARED INSTANCE (the running game) ============

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

local default
local function realEnv(player)
	local okU, UIKit = pcall(function() return require(RS:WaitForChild("UIKit", 10)) end)
	local okC, Cine = pcall(function() return require(RS:WaitForChild("Cine", 10)) end)
	return {
		now = os.clock,
		state = function()
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			local seat = hum and hum.SeatPart
			local menu = player:GetAttribute("BuildModeOpen") == true or player:GetAttribute("NamingOpen") == true
			local pg = player:FindFirstChild("PlayerGui")
			if not menu and okU and UIKit and UIKit.MENUS and pg then
				for _, n in ipairs(UIKit.MENUS) do
					local g = pg:FindFirstChild(n)
					if g and g:IsA("ScreenGui") and g.Enabled then menu = true break end
				end
			end
			return {
				driving = seat ~= nil and seat:IsA("VehicleSeat"),
				carrying = player:GetAttribute("Carrying") ~= nil,
				cutscene = okC and Cine and Cine.busy() or false,
				menu = menu,
			}
		end,
	}
end

local function get()
	if default then return default end
	local player = Players.LocalPlayer
	assert(RunService:IsClient() and player, "Notify is client-side")
	default = Notify.new(realEnv(player))
	task.spawn(function()
		while true do
			task.wait(0.2)
			default:pump()
		end
	end)
	return default
end

function Notify.show(it) return get():show(it) end
function Notify.hold(lane, key) get():hold(lane, key) end
function Notify.release(key) get():release(key) end
function Notify.state() return get().env.state() end

return Notify
```

- [ ] **Step 5: Install and run the tests**

Run `tools/install.luau` with `FILES = { {src="Notify.lua", path="ReplicatedStorage.Notify", class="ModuleScript"} }`.
Expected: `Notify.lua -> ReplicatedStorage.Notify NNN lines CREATED`, with no SUSPECT.
Then run `tests/notify_spec.luau`. Expected: `PASS 13 groups`.

- [ ] **Step 6: Checkpoint**

Byte-compare `ReplicatedStorage.Notify.Source` with `Notify.lua` on disk (CRLF-normalised). Expected: SAME.

---

### Task 2: The top lane (phone, rare hire, headhunter, HQ, milestone) and WRITE CODE in the car

**Files:**
- Modify: `TalentRowClient.lua` (danger chip → hold; LOST → P0)
- Modify: `TalentRevealClient.lua` (card → P1)
- Modify: `PhoneClient.lua` (banner, ring, pill)
- Modify: `HudClient.lua` (HQ banner P1 with a 1.6 s delay; milestone P2; WRITE CODE hidden in a VehicleSeat)
- Backups first: `<File>_pre_v42.lua` for each.

**Interfaces:**
- Consumes: `Notify.show`, `Notify.hold`, `Notify.release` (Task 1)

- [ ] **Step 1: Back up the four files**

```bash
cd /c/Users/lukex/Downloads/silicon-startup && for f in TalentRowClient TalentRevealClient PhoneClient HudClient; do cp -n $f.lua ${f}_pre_v42.lua; done
```

- [ ] **Step 2: TalentRowClient**

After `local UIKit = require(...)` add:

```lua
local Notify = require(ReplicatedStorage:WaitForChild("Notify"))
-- v4.2: the chip owns the top strip for the whole chase (a phone text used to land on it)
local holding = false
local function setDanger(v)
	if v == holding then return end
	holding = v
	if v then Notify.hold("top", "headhunter") else Notify.release("headhunter") end
end
```

Replace the body of `lostRemote.OnClientEvent` with a P0 item:

```lua
	lostRemote.OnClientEvent:Connect(function(text)
		danger.Visible = false
		setDanger(false)
		Notify.show({ lane = "top", priority = 0, key = "lost",
			close = function() lostCard.Visible = false end,
			open = function(done)
				lostSerial += 1
				local mine = lostSerial
				lostText.Text = tostring(text or "They got away")
				lostCard.Position = UDim2.new(0.5, 0, 0, 60)
				lostCard.Size = UDim2.new(0, centreWidth(440, lostCard), 0, 74)
				lostCard.Visible = true
				TweenService:Create(lostCard, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Position = UDim2.new(lostCard.Position.X.Scale, lostCard.Position.X.Offset, 0, 96) }):Play()
				UIKit.sfx("thunk", 0.55, 0.8)
				for _, f in ipairs(lostEdges) do
					f.BackgroundTransparency = 0.35
					TweenService:Create(f, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
				end
				task.delay(3, function()
					if lostSerial == mine then lostCard.Visible = false end
					done()
				end)
			end })
	end)
```

In the `RenderStepped` handler, every path that sets `danger.Visible` is followed by `setDanger(danger.Visible)`:
- after `danger.Visible = true` (in the `if nearest` branch)
- after the `danger.Visible = false` inside the `else` of `if nearest`
- after `danger.Visible = false` just below the carrying block

- [ ] **Step 3: TalentRevealClient**

After `local UIKit = require(...)` add `local Notify = require(ReplicatedStorage:WaitForChild("Notify"))`.

`hide(mine)` reports done:

```lua
local doneFor = {}
local function hide(mine)
	if serial ~= mine or not card.Visible then
		local f = doneFor[mine]; doneFor[mine] = nil
		if f then f() end
		return
	end
	local tw = TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.new(0, cardX, 0, -CARD_H - 20) })
	tw:Play()
	tw.Completed:Wait()
	if serial == mine then
		card.Visible = false
		player:SetAttribute("RevealShowing", false)
	end
	local f = doneFor[mine]; doneFor[mine] = nil
	if f then f() end
end
```

In `remote.OnClientEvent`:
- keep the `WelcomeDone` wait
- move everything from `serial += 1` to the final `task.delay(HOLD[tier] ...)` into a local `local function showCard(d, done)`, adding `doneFor[mine] = done` right after `local mine = serial`
- end the handler with:

```lua
	Notify.show({ lane = "top", priority = 1, key = "reveal",
		open = function(done) showCard(d, done) end,
		close = function() task.spawn(hide, serial) end })
```

- [ ] **Step 4: PhoneClient**

After `local UIKit = require(...)` add `local Notify = require(ReplicatedStorage:WaitForChild("Notify"))`.

1. Delete `REVEAL_BOTTOM`, `topY` and the `RevealShowing` handler near the end (the lanes keep them apart now).
2. Rename the existing `showBanner(th, text)` to `showBannerNow(th, text, done)`:
   - use `topY()` → `96`
   - in its 7 s `task.delay`, call `done()` after `banner.Visible = false`
   - the tap handler calls `if bannerDone then bannerDone() end` (store `bannerDone = done` inside `showBannerNow`)
   - add `local bannerDone` above it

   Then add:

```lua
-- v4.2: every banner asks the director; only a thread's FIRST text and a term
-- sheet raise one (a reply used to raise two banners two seconds apart). The
-- rest are counted by the server on the PHONE button (PhoneUnread).
local function showBanner(th, text, priority)
	Notify.show({ lane = "top", priority = priority or 3, key = "phone",
		close = function() bannerSerial += 1; banner.Visible = false end,
		open = function(done) showBannerNow(th, text, done) end })
end
```

3. In the `msg` branch, replace `elseif e.notify then showBanner(th, e.msg.text)` with:

```lua
		elseif e.notify and not th.bannered then
			th.bannered = true
			showBanner(th, e.msg.text, 3)
```

4. In the `offer` branch, use `showBanner(th, "Sent you a term sheet: " .. UIKit.money(e.amount), 2)`.
5. The two call-note banners (`showBanner(nil, ...)` followed by `bnTitle.Text = "Call"`): pass the title through as a field instead. Change `showBannerNow` to accept `th` as a table `{ first = "Call", firm = "" }` when `th` is nil and the text comes from a call, and call `showBanner({ call = true }, e.reason, 3)`. In `showBannerNow`, `if th and th.call then` keep avatar off and set `bnTitle.Text = "Call"`.
6. The ring card becomes P0:

```lua
local ringDone
local function showRing(e)
	Notify.show({ lane = "top", priority = 0, key = "ring",
		close = function() ringCard.Visible = false end,
		valid = function() return call.state == "ringing" end,
		open = function(done)
			ringDone = done
			for _, c in ipairs(ringHolder:GetChildren()) do c:Destroy() end
			headshot(ringHolder, e.with or 0, 48)
			ringText.Text = e.name or "Someone"
			centreOn(ringCard, 380, 320, 80, 96)
			ringCard.Visible = true
		end })
end
local function ringOver()
	ringCard.Visible = false
	if ringDone then local f = ringDone; ringDone = nil; f() end
end
```

   Replace the `else` branch of `if gui.Enabled then` under `e.state == "ringing"` with `showRing(e)`. Replace each `ringCard.Visible = false` in the call handler with `ringOver()`.
7. The call pill moves beside the PHONE rail button. In the Heartbeat handler, replace `centreOn(pill, 260, 240, 50, topY())` with `placePill()`, defined above it:

```lua
local function placePill()
	local a = railBtn.AbsolutePosition - notify.AbsolutePosition
	pill.AnchorPoint = Vector2.new(0, 0.5)
	pill.Size = UDim2.new(0, 250, 0, 50)
	pill.Position = UDim2.new(0, a.X + railBtn.AbsoluteSize.X + 10, 0, a.Y + railBtn.AbsoluteSize.Y / 2)
end
```

- [ ] **Step 5: HudClient**

After `local UIKit = require(...)` add `local Notify = require(ReplicatedStorage:WaitForChild("Notify"))`.

WRITE CODE hides in a car:

```lua
local function seated()
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local s = hum and hum.SeatPart
	return s ~= nil and s:IsA("VehicleSeat")
end
local function syncCode()
	codeBtn.Visible = player:GetAttribute("Shipped") == true and player:GetAttribute("BuildModeOpen") ~= true and not seated()
end
syncCode()
player:GetAttributeChangedSignal("Shipped"):Connect(syncCode)
player:GetAttributeChangedSignal("BuildModeOpen"):Connect(syncCode)
-- v4.2: in a car the speedometer owns the bottom centre (it sat on top of WRITE CODE)
local function watchSeat(char)
	local hum = char:WaitForChild("Humanoid", 10)
	if hum then hum:GetPropertyChangedSignal("SeatPart"):Connect(syncCode) end
	syncCode()
end
if player.Character then task.spawn(watchSeat, player.Character) end
player.CharacterAdded:Connect(watchSeat)
```

`hqBanner(e)` becomes `hqBanner(e, done)`; it returns `card`, and the final delay calls `done()` after `card:Destroy()`.

In the Celebrate handler:

```lua
		elseif e.kind == "hq" then
			-- v4.2: the orbit shot (HomeClient, at 1.4 s) goes first; the banner
			-- waits for it instead of being hidden by it after 1.4 s
			local hqCard
			Notify.show({ lane = "top", priority = 1, key = "hq", delay = 1.6,
				close = function() if hqCard then hqCard:Destroy() end end,
				open = function(done) hqCard = hqBanner(e, done) end })
		elseif e.kind == "milestone" then
			Notify.show({ lane = "top", priority = 2, key = "milestone",
				open = function(done)
					UIKit.sfx("ding")
					popUnderCash(("%s earned!  +%d%% money forever"):format(UIKit.money(e.earned or 0), e.bonus or 2), UIKit.GOLD, 2.4)
					task.delay(2.9, done)
				end })
```

- [ ] **Step 6: Install and smoke-check**

Install the four files with `tools/install.luau` (paths `StarterPlayer.StarterPlayerScripts.<Name>`, class `LocalScript`). Expected: 4 lines, no COMPILE FAIL, no new SUSPECT.

---

### Task 3: The centre lane (While You Were Away, item card, Daily, Name)

**Files:**
- Modify: `HudClient.lua` (While You Were Away)
- Modify: `InventoryClient.lua`, `DailyClient.lua`, `NameClient.lua`
- Backups: `InventoryClient_pre_v42.lua`, `DailyClient_pre_v42.lua`, `NameClient_pre_v42.lua`

**Interfaces:**
- Consumes: `Notify.show` (Task 1)

- [ ] **Step 1: HudClient, While You Were Away**

Replace the lines from `-- wait for the intro camera to hand back` through `task.wait(0.4)` (the dead Intro wait). Wrap the card build in:

```lua
	Notify.show({ lane = "centre", priority = 2, key = "welcome", calm = true, maxHold = 25,
		open = function(done)
			-- (the existing card build, unchanged, from `local w = ...` to `btn.MouseButton1Click:Connect(collect)`)
			-- collect() ends with done()
			-- task.delay(20, collect) stays
		end })
```

`collect()` gains `done()` as its last line. `pendingOffline = away` stays before `Notify.show`, so the money is held until COLLECT.

- [ ] **Step 2: InventoryClient**

After `local UIKit = require(...)` add `local Notify = require(ReplicatedStorage:WaitForChild("Notify"))`.
- `gotCard(id, n, source)` becomes `gotCard(id, n, source, done)`:
  - it calls `done()` on the early return (unknown id)
  - it calls `done()` after `card:Destroy()`
- Replace the `queue, busy` block's `got` branch with:

```lua
	if e.kind == "got" then
		Notify.show({ lane = "centre", priority = 2, key = "item",
			open = function(done) gotCard(e.id, e.n, e.source, done) end })
```

  Delete `local queue, busy = {}, false`.

- [ ] **Step 3: DailyClient**

After `local UIKit = require(...)` add `local Notify = require(ReplicatedStorage:WaitForChild("Notify"))`.

Replace the `OPEN BY ITSELF, ONCE` block with:

```lua
-- ============ OPEN BY ITSELF, ONCE ============
-- v4.2: at a calm moment only (the director waits for 5 quiet seconds, and
-- never while driving, carrying, in a cutscene or with another menu open)
task.spawn(function()
	local t0 = os.clock()
	while os.clock() - t0 < 3600 do
		task.wait(1)
		local returning = player:GetAttribute("Returning") == true
		local settled = not returning or player:GetAttribute("WelcomeDone") == true
		if player:GetAttribute("DailyReady") == true and unlocked() and settled then
			Notify.show({ lane = "centre", priority = 2, key = "daily", calm = true,
				valid = function() return player:GetAttribute("DailyReady") == true and not gui.Enabled end,
				open = function(done)
					setOpen(true)
					local conn
					conn = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
						if not gui.Enabled then conn:Disconnect(); done() end
					end)
				end })
			return
		end
	end
end)
```

- [ ] **Step 4: NameClient**

After `local UIKit = require(...)` add `local Notify = require(ReplicatedStorage:WaitForChild("Notify"))`.

In `askName.OnClientEvent`, keep the `Returning`/`WelcomeDone` wait and the hint text. Wrap from `gui.Enabled = true` to the auto-skip delay in:

```lua
	Notify.show({ lane = "centre", priority = 2, key = "name", calm = true, maxHold = 60,
		open = function(done)
			gui.Enabled = true
			-- (existing UIScale pop + openSerial + 25 s auto-skip, unchanged)
			local conn
			conn = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
				if not gui.Enabled then conn:Disconnect(); done() end
			end)
		end })
```

- [ ] **Step 5: Install**

Install `HudClient`, `InventoryClient`, `DailyClient`, `NameClient`. Expected: no COMPILE FAIL, no new SUSPECT.

---

### Task 4: The bottom lane (one toast) and the news tag

**Files:**
- Modify: `Notify.lua` (add `Notify.toast`)
- Modify: `ProductClient.lua`, `CarClient.lua`, `LiftClient.lua`
- Modify: `SiliconCore.lua:1676`, `:2876`, `:2979`
- Backups: `ProductClient_pre_v42.lua`, `CarClient_pre_v42.lua`, `LiftClient_pre_v42.lua`, `SiliconCore_pre_v42.lua`

**Interfaces:**
- Produces: `Notify.toast(text: string, opts: { priority: number?, hold: number?, sfx: string?, untilCarryEnds: boolean? })`

- [ ] **Step 1: Add a toast test to `tests/notify_spec.luau`**

It checks that the module exports `toast` (it can't draw in Edit):

```lua
expect(type(Notify.toast) == "function", "14 toast exported")
```

(Insert it before `clone:Destroy()`, and change the PASS line to `PASS 14 groups`.) Run it. Expected: `FAIL 1 ... 14 toast exported`.

- [ ] **Step 2: Add `Notify.toast` to `Notify.lua`** (above `return Notify`)

```lua
-- ============ THE ONE TOAST (bottom lane) ============
-- v4.2: three toasts (Product, Car, Lift) drew in three places, one of them on
-- top of another. Now one white pill just above WRITE CODE, one at a time.
local toastGui, toastPill, toastSerial
local function toastParts()
	if toastPill and toastPill.Parent then return toastPill end
	local player = Players.LocalPlayer
	local UIKit = require(RS:WaitForChild("UIKit"))
	toastGui = Instance.new("ScreenGui")
	toastGui.Name = "NotifyToast"
	toastGui.ResetOnSpawn = false
	toastGui.IgnoreGuiInset = true
	toastGui.DisplayOrder = 13
	UIKit.safe(toastGui)
	toastGui.Parent = player:WaitForChild("PlayerGui")
	local pill = Instance.new("TextLabel")
	pill.Name = "Toast"
	pill.AnchorPoint = Vector2.new(0.5, 1)
	pill.Position = UDim2.new(0.5, 0, 1, 60)
	pill.Size = UDim2.new(0.9, 0, 0, 44)
	pill.BackgroundColor3 = UIKit.CARD
	pill.Text = ""
	pill.TextColor3 = UIKit.CARD_TEXT
	pill.TextSize = 17
	pill.Font = UIKit.HEAD
	pill.TextTruncate = Enum.TextTruncate.AtEnd
	pill.Parent = toastGui
	Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)
	local st = Instance.new("UIStroke", pill)
	st.Color = UIKit.CARD_LINE
	st.Thickness = 1.5
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local pad = Instance.new("UIPadding", pill)
	pad.PaddingLeft = UDim.new(0, 46); pad.PaddingRight = UDim.new(0, 18)
	UIKit.icon(pill, "info", 24, UIKit.BLUE, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -34, 0.5, 0) })
	local cap = Instance.new("UISizeConstraint", pill)
	cap.MaxSize = Vector2.new(480, 44)
	toastPill = pill
	toastSerial = 0
	return pill
end

function Notify.toast(text, opts)
	opts = opts or {}
	local TweenService = game:GetService("TweenService")
	local player = Players.LocalPlayer
	local function away(pill)
		TweenService:Create(pill, TweenInfo.new(0.25), { Position = UDim2.new(0.5, 0, 1, 60) }):Play()
	end
	return Notify.show({ lane = "bottom", priority = opts.priority or 2, key = "toast",
		close = function() if toastPill then toastSerial += 1; away(toastPill) end end,
		open = function(done)
			local pill = toastParts()
			toastSerial += 1
			local mine = toastSerial
			pill.Text = tostring(text)
			if opts.sfx then require(RS:WaitForChild("UIKit")).sfx(opts.sfx) end
			TweenService:Create(pill, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 1, -98) }):Play()
			local conn
			local function finish()
				if conn then conn:Disconnect(); conn = nil end
				if toastSerial == mine then away(pill) end
				task.delay(0.3, done)
			end
			if opts.untilCarryEnds then
				-- a "Get home!" line leaves with the carry (25 Sep test: it sat under LOST!)
				conn = player:GetAttributeChangedSignal("Carrying"):Connect(function()
					if player:GetAttribute("Carrying") == nil then finish() end
				end)
			end
			task.delay(opts.hold or 4.5, function() if toastSerial == mine then finish() end end)
		end })
end
```

- [ ] **Step 3: Install Notify and run the spec**

Expected: `PASS 14 groups`.

- [ ] **Step 4: ProductClient**

After `local UIKit = require(...)` add `local Notify = require(ReplicatedStorage:WaitForChild("Notify"))`. Delete the whole `-- ============ TOASTS ============` block (the pill, `serial`, the Carrying handler and `toast.OnClientEvent`) and put in its place:

```lua
-- ============ TOASTS ============
-- v4.2: through the director (Notify.toast). Other players' news is ambient
-- (P3, dropped while you are busy); your own lines are progress (P2), or
-- earned (P1) while you carry a recruit, and those leave with the carry.
toast.OnClientEvent:Connect(function(text, kind)
	local news = kind == "news"
	local carrying = player:GetAttribute("Carrying") ~= nil
	Notify.toast(tostring(text), {
		priority = news and 3 or (carrying and 1 or 2),
		untilCarryEnds = carrying and not news,
	})
end)
```

- [ ] **Step 5: CarClient**

After `local UIKit = require(...)` add `local Notify = require(ReplicatedStorage:WaitForChild("Notify"))`. Replace the "toasts from the car system" block with:

```lua
-- toasts from the car system: the shared toast (v4.2), answers to what you just did
carToast.OnClientEvent:Connect(function(text)
	Notify.toast(tostring(text), { priority = 1, hold = 2.6, sfx = "thunk" })
end)
```

- [ ] **Step 6: LiftClient**

After `local UIKit = require(...)` add `local Notify = require(ReplicatedStorage:WaitForChild("Notify"))`. Replace the `toastGui` / `toast` / `toastText` creation and `say` with:

```lua
local function say(text)
	Notify.toast(text, { priority = 1, hold = 2.2, sfx = "thunk" })
end
```

(If `ReplicatedStorage` isn't a local in LiftClient, use `game:GetService("ReplicatedStorage")`.)

- [ ] **Step 7: SiliconCore news tags** (no new locals)

- `:1676` → `toast:FireClient(other, (...):format(...), "news")`
- `:2876` → `toast:FireAllClients((...):format(...), "news")`
- `:2979` → `toast:FireAllClients((...):format(...), "news")`

- [ ] **Step 8: Install**

Install Notify, ProductClient, CarClient, LiftClient (`StarterPlayer.StarterPlayerScripts`) and SiliconCore (`ServerScriptService.SiliconCore`, class `Script`). Expected: no COMPILE FAIL. The only SUSPECTs are the known SiliconCore false positives: `wirePlot@25`, `plotOf@24`, `releasePlot@1686`.

---

### Task 5: Live verification, bot run, report

**Files:**
- Create: `tests/notify_live_client.luau`, `tests/notify_live_server.luau`
- Create: `silicon-startup/V42-CALM-REPORT.md`
- Modify: `C:\Users\lukex\CLAUDE.md` (append a v4.2 part 1 note)

- [ ] **Step 1: Client watcher** (`tests/notify_live_client.luau`, run on the Client datamodel)

It samples every 0.25 s for `DURATION` seconds and records the most items visible at once per lane.

```lua
local DURATION = DURATION or 14
local pg = game.Players.LocalPlayer.PlayerGui
local function vis(path)
	local cur = pg
	for _, n in ipairs(string.split(path, ".")) do cur = cur and cur:FindFirstChild(n) end
	return cur and cur.Visible
end
local function onScreen(gui)
	return gui and gui:IsA("GuiObject") and gui.Visible and gui.AbsolutePosition.Y < workspace.CurrentCamera.ViewportSize.Y - 10 and gui.AbsolutePosition.Y > -20
end
_G.NotifyLive = { max = { top = 0, centre = 0, bottom = 0 }, seen = {}, samples = 0 }
local R = _G.NotifyLive
task.spawn(function()
	local t0 = os.clock()
	while os.clock() - t0 < DURATION do
		local top, centre, bottom = 0, 0, 0
		local function mark(name, lane)
			R.seen[name] = true
			if lane == "top" then top += 1 elseif lane == "centre" then centre += 1 else bottom += 1 end
		end
		if vis("PhoneNotify.Banner") and onScreen(pg.PhoneNotify.Banner) then mark("phone", "top") end
		if vis("PhoneNotify.Incoming") then mark("ring", "top") end
		local tr = pg:FindFirstChild("TalentReveal")
		for _, c in ipairs(tr and tr:GetChildren() or {}) do if c:IsA("TextButton") and onScreen(c) then mark("reveal", "top") end end
		if vis("TalentRow.Danger") then mark("headhunter", "top") end
		if vis("TalentRow.Lost") then mark("lost", "top") end
		local fx = pg:FindFirstChild("Celebrate")
		for _, c in ipairs(fx and fx:GetChildren() or {}) do
			if c:IsA("Frame") and c.Size.Y.Offset == 132 and onScreen(c) then mark("hq", "top") end
			if c:IsA("Frame") and c.Size.Y.Offset == 200 then mark("welcome", "centre") end
		end
		local ifx = pg:FindFirstChild("ItemFx")
		for _, c in ipairs(ifx and ifx:GetChildren() or {}) do if c:IsA("Frame") and c.Size.Y.Offset == 96 then mark("item", "centre") end end
		if pg:FindFirstChild("Daily") and pg.Daily.Enabled then mark("daily", "centre") end
		if pg:FindFirstChild("CompanyName") and pg.CompanyName.Enabled then mark("name", "centre") end
		local tp = pg:FindFirstChild("NotifyToast") and pg.NotifyToast:FindFirstChild("Toast")
		if tp and tp.Position.Y.Offset < 0 then mark("toast", "bottom") end
		R.max.top = math.max(R.max.top, top); R.max.centre = math.max(R.max.centre, centre); R.max.bottom = math.max(R.max.bottom, bottom)
		R.samples += 1
		task.wait(0.25)
	end
	R.done = true
end)
return "watching"
```

- [ ] **Step 2: Server burst** (`tests/notify_live_server.luau`, run on the Server datamodel)

```lua
local p = game.Players:GetPlayers()[1]
local R = game.ReplicatedStorage.SVRemotes
R.TalentReveal:FireClient(p, { tier = 4, name = "Genius", color = {0.9, 0.6, 0.1}, role = "engineer", who = "Test Person", mult = 5, odds = 150, newIndex = false })
R.Celebrate:FireClient(p, { kind = "hq", level = 3, name = "TEST HQ", chips = { "one", "two" } })
R.Celebrate:FireClient(p, { kind = "milestone", earned = 1000000, bonus = 2 })
R.PhoneEvent:FireClient(p, { kind = "msg", id = "t_live", name = "Tess", firm = "Test Ventures", notify = true, msg = { from = "them", text = "Live notify test" } })
R.Toast:FireClient(p, "Your own line")
R.Toast:FireClient(p, "Somebody else's news", "news")
R.ItemEvent:FireClient(p, { kind = "got", id = "coffee", n = 1, source = "Live test" })
return "fired 7"
```

- [ ] **Step 3: Run it on foot**

1. Snapshot the record: `SVSave_v1:SetAsync("11510645938_pre_v42", GetAsync("11510645938"))` in Edit.
2. `start_stop_play` true, then wait for plot + leaderstats.
3. Run the client watcher with `DURATION = 14`, then the server burst.
4. After 15 s, read `_G.NotifyLive` on the client.

Expected:
- `max.top == 1`, `max.centre <= 1`, `max.bottom == 1`
- `seen` includes reveal, hq, milestone(top), item, toast, and phone or its badge
- zero console errors

- [ ] **Step 4: Run it seated**

On the server:
- make a temporary `VehicleSeat` next to the player and `seat:Sit(humanoid)`
- run the watcher and the burst again

Expected:
- no top/centre items while seated
- the phone banner is not shown (badge instead)
- `WriteCode.Visible == false` on the client

Then `humanoid.Sit = false`. Within ~2 s the held P1 items (reveal, hq) appear one at a time.

- [ ] **Step 5: A real chase**

- SVDev `recruit` spawns a candidate. Walk to it (`character_navigation` or PivotTo) and pick it up (dev path) so a headhunter chases.
- During the chase, fire the phone message from Step 2.

Expected: while `TalentRow.Danger` is visible, `PhoneNotify.Banner` never is.

If a chase can't be triggered in-harness, record that it wasn't verified live (unit test 9 covers the hold).

- [ ] **Step 6: Bot run**

Fresh session, SVDev `bot 20`. Expected: HQ 2/3/4/5 within 1 min of 4.0/7.6/12.3/19.5 and the spin-off near 25, with 0 errors. Stop and restore the record from `11510645938_pre_v42`.

- [ ] **Step 7: Disk == Studio, report, memory**

- Byte-compare all changed scripts with disk.
- Write `V42-CALM-REPORT.md`: what changed, the measured `max` per lane on foot and seated, and the chase result.
- Append the CLAUDE.md note.
- Kill the 8731 server. Leave Studio in Edit.
