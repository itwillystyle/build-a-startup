# TEAM Screen Redesign + Anti-Slop System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace PR #55's sloppy TEAM drawing with Luke's pick (Option 2, the showroom, no tabs), and give the doctor three composition checks plus a written process rule so sloppy UI stops shipping.

**Architecture:** Server data stays (StaffData, StaffRooms, StaffAction); recompute also stamps each rig with `StaffId`/`StaffOwner` so the client can draw real characters. Pure modules decide everything testable: `TeamView` (what each part shows, extended) and a new `SlopRules` (the three slop checks' cores). `DoctorProbes.ui` gathers inputs for `SlopRules`; `GameDoctor` reports them. `TeamClient` is rewritten to draw the mock, with a small pure-ish `RigPortrait` helper for ViewportFrame clones.

**Tech Stack:** Roblox Luau, Rojo 7.7, Lune offline tests (`lune run tests/offline/run`), selene, `tools/bas`, Studio MCP, headless Edge for mock screenshots.

**Spec:** `docs/superpowers/specs/2026-10-14-team-screen-redesign-design.md` (silicon-startup, outside git). Mock: `ui/2026-10-14-team/mockups.html#o2`, `mock-o2.png`. References: `ui/references/` Board A.

## Global Constraints

- Branch `staff-phase3`; the PR is #55 (update it, don't open a new one).
- UIKit tokens only (`uistyle.spec`); overshoot only on `-- reward` lines; "world colour" comment on any 3D-only Color3.
- Every tap ≥ 52 px drawn; text ≥ 14 px; one loud thing per menu (only the affordable Skill price is green).
- Menu 744 x 368 drawn, right of the rail, `UIKit.fitMenu`; faces column 80 wide (56 px tiles); right TRAIN column 300 wide; rooms 52 x 52, 6 px apart.
- ≤ 9 live ViewportFrames while TEAM is open; none while closed.
- SiliconCore is at the 200-local limit: no new top-level locals.
- Doctor gate: commit docs BEFORE the fingerprint; snapshot only right after a restore; restore Wilz's save after every Play test (clean save: cash 1,437,329,148, staff skill all 0).

## Review Focus

1. A person whose rig is missing or not yet replicated (just hired, mid spin-off): the tile and body fall back to a talent-coloured disc with the role icon, never an empty box or an error. → Task 4 live check "hire while open".
2. A team bigger than the column (20+): scrolling the faces keeps ≤ 9 live ViewportFrames and the selected person stays drawn. → TeamView.visible test (Task 1) + doctor VPF count (Task 3/5).
3. Another player's rigs in the server with the same StaffId (ids are per save): the screen must draw YOUR person (StaffOwner match). → Task 4 rig lookup uses both attributes; Task 1 server stamp.
4. The slop checks on screens that are not TEAM (HQ level-up cards, HUD) may flag real old slop: the gate must not be silently weakened to pass. → Task 3 records any pre-existing finding in the PR and the ledger as a ruling; thresholds stay as the spec says.
5. A price change while the screen is open (promotion, F change) moves which button is green or MAX: the look follows StaffData every refresh. → TeamView.look test (Task 1).

---

### Task 1: TeamView additions + the rig stamp

**Files:**
- Modify: `src/ReplicatedStorage/TeamView.lua`
- Modify: `src/ServerScriptService/SiliconCore.server.lua` (recompute's StaffData loop, ~:1283)
- Test: `tests/offline/teamview.spec.luau`

**Interfaces (Produces):**
- `TeamView.look(statId, trainResult) -> "go" | "paper" | "dim" | "max"`: "go" only for skill when state "ok".
- `TeamView.roomLine(row) -> string`: note if any (`V.note`), else `"✓ AI Labs · pinned"` style (✓ only when `row.fit`, "· pinned" only when `row.pin ~= ""`).
- `TeamView.glow(talent) -> "genius" | "unicorn" | nil` (talent 4 / 5).
- `TeamView.visible(scrollY, viewH, tileH, gap, n, cap) -> first, last` (1-based, inclusive, at most `cap` tiles, clamped to 1..n; n = 0 → 1, 0).
- Rig attributes `StaffId` (number) and `StaffOwner` (UserId) set in recompute.

- [ ] **Step 1: Write the failing tests** (append before `return T` in teamview.spec):

```lua
test("look: only an affordable Skill is loud", function()
	assert(V.look("skill", { state = "ok" }) == "go", "skill ok")
	assert(V.look("speed", { state = "ok" }) == "paper" and V.look("loyalty", { state = "ok" }) == "paper", "others quiet")
	assert(V.look("skill", { state = "poor" }) == "dim" and V.look("speed", { state = "poor" }) == "dim", "poor")
	assert(V.look("skill", { state = "max" }) == "max", "max")
end)

test("roomLine: the note wins, else room with ✓ and pinned", function()
	assert(V.roomLine({ pin = "cafe", room = "lobby" }) == "No free seat in Cafe", "note")
	assert(V.roomLine({ pin = "", room = "labs", fit = true }) == "✓ AI Labs", tostring(V.roomLine({ pin = "", room = "labs", fit = true })))
	assert(V.roomLine({ pin = "labs", room = "labs", fit = true }) == "✓ AI Labs · pinned", "pinned")
	assert(V.roomLine({ pin = "", room = "cafe", fit = false }) == "Cafe", "no fit")
	assert(V.roomLine({ pin = "" }) == "Waiting for a desk", "unseated")
end)

test("glow: Genius and Unicorn only", function()
	assert(V.glow(4) == "genius" and V.glow(5) == "unicorn" and V.glow(3) == nil and V.glow(nil) == nil, "glow")
end)

test("visible: which face tiles get a live character (never more than cap)", function()
	local a, b = V.visible(0, 300, 56, 8, 20, 8)
	assert(a == 1 and b == 5, ("top %d..%d"):format(a, b))         -- 300 / 64 = 4.7 -> tiles 1..5
	a, b = V.visible(640, 300, 56, 8, 20, 8)
	assert(a == 11 and b == 15, ("scrolled %d..%d"):format(a, b))
	a, b = V.visible(0, 2000, 56, 8, 20, 8)
	assert(a == 1 and b == 8, "capped at 8")
	a, b = V.visible(5000, 300, 56, 8, 3, 8)
	assert(a == 1 and b == 3, "clamped to the team")
	a, b = V.visible(0, 300, 56, 8, 0, 8)
	assert(a == 1 and b == 0, "empty team")
end)
```

- [ ] **Step 2: Run** `lune run tests/offline/run` → Expected: 4 FAILs (attempt to call a nil value).
- [ ] **Step 3: Implement** (in TeamView.lua, before `return V`):

```lua
-- the button's look: only an affordable Skill is loud (DESIGN.md: one loud thing)
function V.look(statId, t)
	local st = type(t) == "table" and t.state or "max"
	if st == "max" then return "max" end
	if st == "poor" then return "dim" end
	return statId == "skill" and "go" or "paper"
end

-- the one line under the rooms row
function V.roomLine(row)
	local n = V.note(row)
	if n then return n end
	return (row.fit and "✓ " or "") .. V.label(row.room) .. (((row.pin or "") ~= "") and " · pinned" or "")
end

function V.glow(t)
	t = tonumber(t)
	return (t == 4 and "genius") or (t == 5 and "unicorn") or nil
end

-- face tiles in view of a scrolling column, at most `cap` of them (the rest show no character)
function V.visible(scrollY, viewH, tileH, gap, n, cap)
	if n < 1 then return 1, 0 end
	local step = tileH + gap
	local per = math.min(cap, math.ceil(num(viewH) / step))
	local first = math.clamp(math.floor(num(scrollY) / step) + 1, 1, math.max(1, n - per + 1))
	return first, math.min(n, first + per - 1)
end
```

- [ ] **Step 4: Run** → Expected: all pass (356+).
- [ ] **Step 5: Server stamp.** In recompute's StaffData loop (`for _, r in ipairs(s.rigs or {}) do` that builds `rows`), first line inside the loop:

```lua
			if r.rig and r.rig:GetAttribute("StaffId") ~= r.id then r.rig:SetAttribute("StaffId", r.id) end   -- phase 3b: the TEAM screen finds this rig
			if r.rig and r.rig:GetAttribute("StaffOwner") ~= player.UserId then r.rig:SetAttribute("StaffOwner", player.UserId) end
```

- [ ] **Step 6:** selene clean on both files; commit `TEAM redesign: TeamView look/roomLine/glow/visible, rigs carry StaffId and StaffOwner`.

### Task 2: SlopRules (the three checks, pure and tested)

**Files:** Create `src/ReplicatedStorage/SlopRules.lua`; Test `tests/offline/sloprules.spec.luau`.

**Interfaces (Produces):**
- `SlopRules.LOUD`: `{ {60,203,108}, {59,139,255}, {255,138,61}, {240,78,78}, {165,92,255}, {255,200,61} }` (GREEN, BLUE, ORANGE, RED, PURPLE, GOLD from DESIGN.md).
- `SlopRules.isLoud(rgb) -> boolean` (each channel within 3).
- `SlopRules.loudButtons(buttons) -> findings`: buttons = `{ {menu = string, path = string, rgb = {r,g,b}} }`; a finding per menu with more than 1 loud: `{ menu, count, paths }`.
- `SlopRules.saidTwice(labels) -> findings`: labels = `{ {gui, path, text} }`; trimmed text of 4+ chars containing a letter, seen twice in one gui → `{ gui, text, paths }`.
- `SlopRules.cutOff(items) -> findings`: items = `{ {path, fits = boolean|nil, rect = {x,y,w,h}, clip = {x,y,w,h}|nil} }`; finding `{ path, why = "text does not fit" | "outside its frame" }` when `fits == false`, or rect not inside clip (1 px tolerance).

- [ ] **Step 1: Write the failing tests:**

```lua
-- sloprules.spec.luau: the composition checks the doctor runs on every screen (14 Oct 2026)
local R = require("../../src/ReplicatedStorage/SlopRules")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

test("LOUD is DESIGN.md's six role colours", function()
	assert(#R.LOUD == 6 and R.isLoud({ 60, 203, 108 }) and R.isLoud({ 61, 205, 107 }), "green, within 3")
	assert(not R.isLoud({ 221, 247, 230 }) and not R.isLoud({ 255, 252, 246 }) and not R.isLoud({ 236, 230, 218 }), "light tints, paper, surface are calm")
end)

test("loudButtons: the old TEAM card (3 green TRAIN) is one finding; one green is fine", function()
	local g, p = { 60, 203, 108 }, { 255, 252, 246 }
	local old = { { menu = "Team", path = "a", rgb = g }, { menu = "Team", path = "b", rgb = g }, { menu = "Team", path = "c", rgb = g }, { menu = "Team", path = "d", rgb = p } }
	local f = R.loudButtons(old)
	assert(#f == 1 and f[1].menu == "Team" and f[1].count == 3 and #f[1].paths == 3, "3 loud")
	assert(#R.loudButtons({ { menu = "Team", path = "a", rgb = g }, { menu = "Team", path = "d", rgb = p } }) == 0, "one loud")
	assert(#R.loudButtons({ { menu = "Team", path = "a", rgb = g }, { menu = "Index", path = "b", rgb = g } }) == 0, "per menu")
	assert(#R.loudButtons({}) == 0, "none")
end)

test("saidTwice: the same fact twice in one screen (4+ characters with a letter), trimmed", function()
	local f = R.saidTwice({ { gui = "Team", path = "row", text = "$12.9K/s" }, { gui = "Team", path = "card", text = " $12.9K/s " }, { gui = "Team", path = "x", text = "0/13" }, { gui = "Team", path = "y", text = "0/13" } })
	assert(#f == 1 and f[1].text == "$12.9K/s", "one repeat (Speed 0/13 and Loyalty 0/13 are two facts): " .. #f)
	assert(#R.saidTwice({ { gui = "Team", path = "a", text = "MAX" }, { gui = "Team", path = "b", text = "MAX" } }) == 0, "3 chars: too short to be a fact")
	assert(#R.saidTwice({ { gui = "Team", path = "a", text = "Noor" }, { gui = "Hud", path = "b", text = "Noor" } }) == 0, "different screens")
	assert(#R.saidTwice({ { gui = "Team", path = "a", text = "" }, { gui = "Team", path = "b", text = "" } }) == 0, "empty")
end)

test("cutOff: text that does not fit, or a button outside its clipping frame", function()
	local f = R.cutOff({
		{ path = "t", fits = false, rect = { 0, 0, 10, 10 } },
		{ path = "chip", fits = true, rect = { 0, 300, 50, 50 }, clip = { 0, 0, 400, 320 } },
		{ path = "ok", fits = true, rect = { 10, 10, 50, 50 }, clip = { 0, 0, 400, 320 } },
		{ path = "edge", rect = { 0, 0, 400.6, 320.6 }, clip = { 0, 0, 400, 320 } },
	})
	assert(#f == 2 and f[1].path == "t" and f[1].why == "text does not fit" and f[2].path == "chip" and f[2].why == "outside its frame", "two cut off")
end)

return T
```

- [ ] **Step 2: Run** → Expected: FAIL (module missing).
- [ ] **Step 3: Implement** `SlopRules.lua`:

```lua
--[[ SlopRules (14 Oct 2026): the composition checks the game doctor runs on every screen it
	probes. The PR #55 TEAM screen passed every size check and was still sloppy: three green
	buttons at once, facts said twice, a row of chips cut off. These are DESIGN.md's rules made
	measurable. Pure (DoctorProbes gathers the inputs on the player's screen); tested in
	tests/offline/sloprules.spec. Spec: docs/superpowers/specs/2026-10-14-team-screen-redesign-design.md §3. ]]
local R = {}

R.LOUD = { { 60, 203, 108 }, { 59, 139, 255 }, { 255, 138, 61 }, { 240, 78, 78 }, { 165, 92, 255 }, { 255, 200, 61 } }

function R.isLoud(rgb)
	for _, c in R.LOUD do
		if math.abs(rgb[1] - c[1]) <= 3 and math.abs(rgb[2] - c[2]) <= 3 and math.abs(rgb[3] - c[3]) <= 3 then return true end
	end
	return false
end

-- more than one loud button in one open menu: nothing leads
function R.loudButtons(buttons)
	local by, order = {}, {}
	for _, b in buttons do
		if R.isLoud(b.rgb) then
			if not by[b.menu] then by[b.menu] = {}; table.insert(order, b.menu) end
			table.insert(by[b.menu], b.path)
		end
	end
	local out = {}
	for _, m in order do
		if #by[m] > 1 then table.insert(out, { menu = m, count = #by[m], paths = by[m] }) end
	end
	return out
end

-- the same fact twice on one screen
function R.saidTwice(labels)
	local seen, out, reported = {}, {}, {}
	for _, l in labels do
		local text = (tostring(l.text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
		if #text >= 4 and text:find("%a") then   -- a number alone ("0/13") is not a fact
			local key = tostring(l.gui) .. "\0" .. text
			if seen[key] and not reported[key] then
				reported[key] = true
				table.insert(out, { gui = l.gui, text = text, paths = { seen[key], l.path } })
			elseif not seen[key] then
				seen[key] = l.path
			end
		end
	end
	return out
end

-- text that does not fit, or a button hanging outside the frame that clips it
function R.cutOff(items)
	local out = {}
	for _, it in items do
		if it.fits == false then
			table.insert(out, { path = it.path, why = "text does not fit" })
		elseif it.clip then
			local r, c = it.rect, it.clip
			if r[1] < c[1] - 1 or r[2] < c[2] - 1 or r[1] + r[3] > c[1] + c[3] + 1 or r[2] + r[4] > c[2] + c[4] + 1 then
				table.insert(out, { path = it.path, why = "outside its frame" })
			end
		end
	end
	return out
end

return R
```

- [ ] **Step 4: Run** → all pass. selene clean. Commit `SlopRules: loud buttons, said twice, cut off (the doctor's composition checks), tested`.

### Task 3: The doctor measures slop (and proves it on the old screen)

**Files:** Modify `src/ReplicatedStorage/DoctorProbes.lua` (`Probes.ui`, `Probes.team`), `src/ServerScriptService/GameDoctor.server.lua` (hq steps' ui block ~:236-246 and the team step ~:386-405).

- [ ] **Step 1: Probes.ui gathers SlopRules inputs.** After `items` is built, add:

```lua
	-- v8 (14 Oct) composition: SlopRules (pure) judges what is gathered here
	local Slop = require(game:GetService("ReplicatedStorage"):WaitForChild("SlopRules"))
	local okUI, UIKit = pcall(require, game:GetService("ReplicatedStorage"):WaitForChild("UIKit"))
	local isMenu = {}
	for _, n in ipairs(okUI and UIKit.MENUS or {}) do isMenu[n] = true end
	local function rgb(c) return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) } end
	local function clipOf(o)
		local n = o.Parent
		while n and not n:IsA("ScreenGui") do
			if n:IsA("GuiObject") and n.ClipsDescendants then
				if n:IsA("ScrollingFrame") then return nil end
				return { n.AbsolutePosition.X, n.AbsolutePosition.Y, n.AbsoluteSize.X, n.AbsoluteSize.Y }
			end
			n = n.Parent
		end
		return nil
	end
	local buttons, labels, cut = {}, {}, {}
	for _, it in ipairs(items) do
		local o = it.obj
		if o:IsA("GuiButton") and o.Active and isMenu[it.gui.Name] then
			local face = o:GetAttribute("Face")
			table.insert(buttons, { menu = it.gui.Name, path = path(o, it.gui), rgb = rgb(typeof(face) == "Color3" and face or o.BackgroundColor3) })
		end
		if o:IsA("TextLabel") and not o:FindFirstAncestorWhichIsA("GuiButton") and o.TextTransparency < 0.9 then
			table.insert(labels, { gui = it.gui.Name, path = path(o, it.gui), text = o.Text })
		end
		if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("GuiButton") then
			table.insert(cut, { path = path(o, it.gui), fits = (o:IsA("TextLabel") or o:IsA("TextButton")) and o.Text ~= "" and o.TextFits or nil,
				rect = { it.p.X, it.p.Y, it.s.X, it.s.Y }, clip = o:IsA("GuiButton") and clipOf(o) or nil })
		end
	end
```

and add to the returned table: `loud = Slop.loudButtons(buttons), twice = Slop.saidTwice(labels), cutOff = Slop.cutOff(cut)`.

- [ ] **Step 2: Probes.team counts live ViewportFrames:** before `open:Fire(false)`, `local vpf = 0; for _, d in ipairs(gui:GetDescendants()) do if d:IsA("ViewportFrame") and d:FindFirstChildWhichIsA("Model") then vpf += 1 end end; out.viewports = vpf`.
- [ ] **Step 3: GameDoctor reports** (a helper used by both the hq ui block and the team step, defined beside `short`):

```lua
local function slopChecks(ui)
	check("loud buttons in one menu", #(ui.loud or {}) == 0, "FEEL", #(ui.loud or {}), 0, short(ui.loud or {}))
	check("the same fact twice", #(ui.twice or {}) == 0, "FEEL", #(ui.twice or {}), 0, short(ui.twice or {}))
	check("cut off", #(ui.cutOff or {}) == 0, "BUG", #(ui.cutOff or {}), 0, short(ui.cutOff or {}, 4))
end
```

Call `slopChecks(ui)` after the existing four ui checks in the hq steps and in the team step; in the team step also `check("live character views", (ui.viewports or 0) <= 9, "FEEL", ui.viewports or 0, "<= 9")`.

- [ ] **Step 4: Prove it on the OLD screen** (TeamClient not yet replaced). Restore save → Play → snapshot → run `require(DoctorProbes).team()` from the Client: Expected `loud` has one finding with count ≥ 3 (the three TRAIN buttons). Record the numbers. Also note any finding on non-TEAM screens from a full doctor run (Review Focus 4): pre-existing slop is listed in the PR, never hidden by a threshold change. Stop, restore.
- [ ] **Step 5:** tests + selene; commit `Doctor: composition checks on every probed screen (proved: the old TEAM card has 3 loud buttons)`.

### Task 4: TeamClient, rebuilt to the mock

**Files:** Create `src/ReplicatedStorage/RigPortrait.lua`; Rewrite the drawing in `src/StarterPlayer/StarterPlayerScripts/TeamClient.client.lua` (keep: the remote, `send`, pending, reply/`say`, cash watch, `Open` BindableEvent, the tile, Q to close, StaffData/StaffRooms decode).

**Interfaces:**
- Consumes: TeamView (`sort`, `train`, `look`, `chips`, `roomLine`, `glow`, `visible`, `talent`, `seniority`, `label`, `why`, `find`); rig attributes `StaffId`, `StaffOwner`; `Seating.ORDER` order via StaffRooms.
- Produces: `RigPortrait.find(userId, id) -> Model?` (a SVStaff-tagged rig with both attributes); `RigPortrait.show(vpf, rig, framing) -> boolean` where framing = `"head"` or `"body"` (clone as TalentRevealClient does: strip BillboardGui/ParticleEmitter/Light/scripts, zero LocalTransparencyModifier, remove the SVStaff tag, camera FOV 40; head: target = head − (0, 0.55, 0), 4.6 studs; body: target = HumanoidRootPart, 11 studs, slightly above); `RigPortrait.clear(vpf)`.

Layout (drawn px, from the spec; DoctorProbes and the match-the-mock review compare against `mock-o2.png`):
- Menu `UIKit.menu(gui, "TEAM", UIKit.BLUE, { Size = 744 x 368 })`, `fitMenu(panel, 744, 368, ...)`, header count "N people".
- Faces: ScrollingFrame x 0, w 80, full body height, `SURFACE_2` background, 2 px LINE right edge; tiles 56 x 56, 8 px gap, centred; tile = TextButton (Text "") with PAPER fill, 3 px UIStroke in `UIKit.TIER[talent]`, a ViewportFrame child only when its index is within `TeamView.visible(...)` (else a role icon in the talent colour); selected: stroke GOLD, 2 px lift. Rebind visible tiles on `CanvasPosition` change.
- Middle (x 80 → 444): a glow Frame (radial UIGradient from `PURPLE_LIGHT`-ish token for genius, `GOLD_LIGHT` for unicorn, PAPER otherwise) behind a body ViewportFrame 150 tall; name (HEAD 26), a row with the talent pill (TIER colour, ink text on gold) + role · seniority (BODY 14 MUTED); $/s (`UIKit.outlined`, MONEY, 24); rooms row: one 52 x 52 button per StaffRooms entry, 6 px gap, centred, room icon (UIKit.ICON keys: house→hq, sofa→lobby, code→eng, contrast→studio, cup→cafe, zoom→labs; use UIKit icon keys that exist, else `person`), GOLD stroke = `row.room == key`, BLUE_LIGHT fill = pinned there, GREEN ✓ badge (UIKit.art "check" 20) = best fit, 45% faded = full; then `TeamView.roomLine(row)` (HEAD 14) or the 4 s reply.
- Right (x 444 → 744, PAPER, 2 px LINE left edge, padding 10/12): "TRAIN" caption (HEAD 14 MUTED); per stat a 52 px row: 30 px stat icon tile (coin/bolt/heart: UIKit icon keys or `UIKit.art`), name (HEAD 15), "level/cap" (HEAD 14) right-aligned, price button 96 x 52 (`TeamView.look`: go = GREEN, paper = PAPER, dim = SURFACE_2 with MUTED text, max = GOLD_LIGHT with "MAX"); under it a block meter: `cap` Frames in a UIListLayout (horizontal, 3 px gap), filled BLUE (GOLD when at cap), empty SURFACE_2 with LINE stroke, 14 px tall.
- Feedback: on a TRAIN reply ok → `Moment.ring` at the button, the new block scales 1.6 → 1 (Quint), `countRate` on the $/s; MOVE ok → `UIKit.sfx("thunk")`.

- [ ] **Step 1:** Write RigPortrait.lua and the new drawing; `lune run tests/offline/run` (uistyle.spec covers the file) → pass; selene clean.
- [ ] **Step 2: Live, real clicks** (restore → Play → snapshot): open via MORE → TEAM; screenshot. Expected: the screen matches `mock-o2.png`'s layout; heads and body show real characters. Click Skill price → cash falls by exactly the shown price, a block fills, $/s ×1.065. Click a non-fit room → the person walks there, gold outline moves, line says "· pinned". Click it again → unpinned. Set cash 0 → Skill dims. Hire one more person while open (`dev:Invoke("hire", ...)` or the HIRE pad) → a new tile appears, no error (Review Focus 1). Count ViewportFrames with a Model under `Team` → ≤ 9 (Review Focus 2). Stop, restore.
- [ ] **Step 3: Match-the-mock review.** Save the in-game screenshot to `ui/2026-10-14-team/built-o2.jpg`. Dispatch a fresh reviewer (most capable model) with `mock-o2.png`, `built-o2.jpg`, the spec §2 and UI School's 5 rules; it must name each concrete difference or rule break. Fix every real one, re-screenshot once.
- [ ] **Step 4:** commit `TEAM screen rebuilt to Luke's pick (Option 2, no tabs): real characters, block meters, one loud button`.

### Task 5: The rules, the docs, the gate

**Files:** Modify `CONSTRAINTS.md` (add rule 17), `../DESIGN.md` (outside git: §5 Menu width, §6 checklist), `docs/features/hiring-talent.md`, `docs/features/dev-tools.md`, `docs/features/ui-hud.md` (SlopRules).

- [ ] **Step 1: CONSTRAINTS.md**, a new section before "Secrets":

```markdown
**UI (14 Oct: the TEAM screen shipped sloppy because it was built straight in code)**
17. **A new or changed screen goes references → mocks → Luke's pick → code.** A board of real
    games in `../ui/references/`, clickable mocks at 844 x 390 in `../ui/<date>-<screen>/`,
    Luke's pick written into the spec, then code. Before Luke sees it, a fresh reviewer compares
    the built screen with the picked mock and the five rules (one loud thing, show don't write,
    say it once, big and solid, space not boxes). The PR shows both side by side.
```

- [ ] **Step 2: DESIGN.md:** §5 Menu line → "Menu: centred, max 560 wide (a full character screen such as TEAM: max 760, the rail stays visible)…"; §6 Do's gains "Check every screen against the five rules: one loud thing, show don't write, say it once, big and solid, space not boxes (the doctor measures the first, third and cut-off text)."
- [ ] **Step 3: feature docs** (line refs by content, map check 0 stale), commit docs.
- [ ] **Step 4: Gate:** fingerprint (Edit, `SourceHash.collect` over ServerScriptService, ReplicatedStorage, StarterPlayer, StarterGui) → Play → snapshot → full doctor → save report → stop → restore → `bas checkup pr ... --post`. Expected: all team checks pass including loud ≤ 1, twice 0, cut off 0, live views ≤ 9.
- [ ] **Step 5:** final whole-branch fresh review (executing-plans), fix pass, push, update PR #55's description (side-by-side mock vs built, the slop numbers before/after), restore save, checkpoint.
