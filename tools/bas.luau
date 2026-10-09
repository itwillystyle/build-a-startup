--[[ bas -- one command for every check this game has (v5.1, 9 Oct 2026).

	From the game folder:
	    lune run tools/bas help
	    lune run tools/bas check            lint + offline tests (~7 s)
	    lune run tools/bas doctor           tools, git, Rojo, Studio
	    lune run tools/bas sim list | <name> | all
	    lune run tools/bas baseline save | diff [--tol 5]
	    lune run tools/bas evidence new <slug> | add <file> [--kind k] | note <text> | show | done
	    lune run tools/bas scenario list    the Studio one-liners for a live check
	    lune run tools/bas map check        feature-map coverage + staleness
	Add --json to any command for one machine-readable object on stdout.
	Add --save to check / sim / baseline diff to file the result in the current evidence folder.
	Exit codes: 0 ok, 1 a check failed, 2 usage error.

	WHY. The checks already existed (selene, 218 offline tests, six Lune sims, SVDev,
	smoke_core, SVCheck) but each was run by hand, printed prose, and forgot
	yesterday's numbers. This is the single entry point an agent (or you) calls after
	every change, plus a memory (.bas/baseline.json) and a proof folder (.evidence/).
	Both folders are git-ignored. Spec: docs/superpowers/specs/2026-10-09-verify-loop-phase1-design.md
	(in the silicon-startup folder, outside this repo). ]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local net = require("@lune/net")

-- ============ args ============
local A = {}
for _, a in process.args do
	if a ~= "--" then table.insert(A, a) end
end
local VALUE_FLAGS = { ["--n"] = true, ["--tol"] = true, ["--kind"] = true }
local JSON = table.find(A, "--json") ~= nil
local SAVE = table.find(A, "--save") ~= nil
local function flag(name)
	local i = table.find(A, name)
	return i and A[i + 1] or nil
end
local pos = {}
do
	local skip = false
	for _, a in A do
		if skip then
			skip = false
		elseif a:sub(1, 2) == "--" then
			skip = VALUE_FLAGS[a] == true
		else
			table.insert(pos, a)
		end
	end
end

-- ============ helpers ============
local HOME = process.env.USERPROFILE or process.env.HOME or ""
local function tool(name)
	local base = HOME .. "/.rokit/bin/" .. name
	if fs.isFile(base .. ".exe") then return base .. ".exe" end
	if fs.isFile(base) then return base end
	return name
end

local function run(prog, params)
	local t = os.clock()
	local ok, r = pcall(process.exec, prog, params)
	local dt = math.floor((os.clock() - t) * 1000)
	if not ok then
		return { ok = false, code = -1, stdout = "", stderr = tostring(r), ms = dt }
	end
	-- process.exec returns a frozen table: copy what we use
	return { ok = r.ok, code = r.code, stdout = r.stdout, stderr = r.stderr, ms = dt }
end

local function lines(s)
	local t = {}
	for l in (s or ""):gmatch("[^\r\n]+") do table.insert(t, l) end
	return t
end

local function trim(s) return (s or ""):match("^%s*(.-)%s*$") end

local function git(params)
	local r = run("git", params)
	return r.ok and trim(r.stdout) or nil
end

local function readJson(path)
	if not fs.isFile(path) then return nil end
	local ok, v = pcall(serde.decode, "json", fs.readFile(path))
	return ok and v or nil
end

local function writeJson(path, v)
	fs.writeFile(path, serde.encode("json", v, true))
end

local function ensureDir(path)
	if not fs.isDir(path) then fs.writeDir(path) end
end

local function result(command, checks, extra)
	local ok, total = true, 0
	for _, c in checks do
		if c.ok == false and c.level ~= "warn" then ok = false end
		total += c.ms or 0
	end
	local out = { ok = ok, command = command, checks = checks, ms = total }
	for k, v in extra or {} do out[k] = v end
	return out
end

-- ============ evidence (used by --save) ============
local CURRENT = ".bas/current"
local function currentEvidence()
	local p = fs.isFile(CURRENT) and trim(fs.readFile(CURRENT)) or nil
	if p and fs.isDir(p) then return p end
	return nil
end

local function manifestAdd(dir, entry)
	local m = readJson(dir .. "/manifest.json") or { files = {}, notes = {} }
	m.files = m.files or {}
	table.insert(m.files, entry)
	writeJson(dir .. "/manifest.json", m)
end

local function saveToEvidence(name, kind, value)
	local dir = currentEvidence()
	if not dir then return nil end
	local file = name .. ".json"
	writeJson(dir .. "/" .. file, value)
	manifestAdd(dir, { file = file, kind = kind, at = os.date("!%Y-%m-%dT%H:%M:%SZ") })
	return dir .. "/" .. file
end

-- ============ check ============
local function checkSelene()
	local r = run(tool("selene"), { "--allow-warnings", "src", "tests", "tools" })
	local out = (r.stdout or "") .. (r.stderr or "")
	local errs = out:match("(%d+) errors?") or "?"
	local warns = out:match("(%d+) warnings?") or "?"
	local c = { name = "selene", ok = r.code == 0, ms = r.ms, detail = ("%s errors, %s warnings"):format(errs, warns) }
	if not c.ok then
		local tailL = lines(out)
		c.output = table.concat(tailL, "\n", math.max(1, #tailL - 30))
	end
	return c
end

local function checkTests()
	local r = run(tool("lune"), { "run", "tests/offline/run" })
	local out = (r.stdout or "") .. (r.stderr or "")
	local passed, failed, files = out:match("(%d+) passed, (%d+) failed %((%d+) spec files%)")
	local c = {
		name = "offline tests",
		ok = r.code == 0 and passed ~= nil,
		ms = r.ms,
		passed = tonumber(passed),
		failed = tonumber(failed),
		detail = passed and ("%s passed, %s failed, %s spec files"):format(passed, failed, files) or "runner did not report",
	}
	if not c.ok then
		local fails = {}
		for _, l in lines(out) do
			if l:match("^FAIL") or l:match("^%s%s%s%s%s%s") then table.insert(fails, l) end
		end
		c.output = table.concat(fails, "\n")
	end
	return c
end

local function cmdCheck()
	return result("check", { checkSelene(), checkTests() })
end

-- ============ doctor ============
local function cmdDoctor()
	local checks = {}
	for _, t in { "rojo", "selene", "lune", "stylua" } do
		local r = run(tool(t), { "--version" })
		table.insert(checks, { name = t, ok = r.code == 0, ms = r.ms, detail = r.code == 0 and trim(r.stdout) or trim(r.stderr) })
	end
	local branch = git({ "rev-parse", "--abbrev-ref", "HEAD" })
	local dirty = git({ "status", "--porcelain" })
	local nDirty = dirty and #lines(dirty) or 0
	table.insert(checks, { name = "git", ok = branch ~= nil, ms = 0, detail = ("branch %s, %d changed files"):format(tostring(branch), nDirty) })
	if branch == "main" then
		table.insert(checks, { name = "branch", ok = false, level = "warn", ms = 0, detail = "on main: agents work on a branch" })
	end
	-- Rojo serve answers on 34872 by default (serve.cmd uses the default)
	local okNet, res = pcall(net.request, "http://localhost:34872/api/rojo")
	local rojoUp = okNet and res and res.statusCode == 200
	table.insert(checks, { name = "rojo serve", ok = rojoUp, level = "warn", ms = 0,
		detail = rojoUp and "answering on :34872" or "not running (double-click serve.cmd, then Studio > Plugins > Rojo > Connect)" })
	if process.os == "windows" then
		local r = run("tasklist", { "/FI", "IMAGENAME eq RobloxStudioBeta.exe", "/NH" })
		local up = (r.stdout or ""):find("RobloxStudioBeta") ~= nil
		table.insert(checks, { name = "studio", ok = up, level = "warn", ms = r.ms,
			detail = up and "running (live checks possible)" or "not running (offline checks only)" })
	end
	return result("doctor", checks)
end

-- ============ sims ============
local SIMS = {
	chase_threat = { file = "tools/chase_threat", json = true, about = "escape % by tier, scooter speed and play style (2,000 seeded runs)" },
	late_game = { file = "tools/late_game", json = true, about = "spin-off prices, waits and offline cover per home" },
	chase_sim = { file = "tools/chase_sim", about = "the chase from ChaseRules, text table" },
	chase_edit = { file = "tools/chase_edit", about = "chase tuning probe, text" },
	turn_probe = { file = "tools/turn_probe", about = "camera turn probe, text" },
	curve_check = { file = "tools/curve_check", about = "home prices vs the spin-off, text" },
}
local STUDIO_TOOLS = {
	{ name = "SVCheck", how = "Play, CLIENT: return require(game.ReplicatedStorage.SVCheck).run()" },
	{ name = "smoke_core", how = "Play, SERVER, after a snapshot: paste tests/smoke_core.luau; diff its output before/after" },
	{ name = "ui_audit", how = "Play, CLIENT: paste tools/ui_audit.luau" },
	{ name = "algo_check", how = "Play, CLIENT: paste tools/algo_check.luau, then check.all()" },
	{ name = "world_overlap", how = "Play: paste tools/world_overlap.luau" },
	{ name = "chase_lab", how = "EDIT command bar: paste tools/chase_lab.luau" },
}
local SIM_ORDER = { "chase_threat", "late_game", "chase_sim", "chase_edit", "turn_probe", "curve_check" }

local function runSim(name, n)
	local s = SIMS[name]
	if not s then return { name = name, ok = false, ms = 0, detail = "unknown sim (try: sim list)" } end
	local params = { "run", s.file }
	if s.json then
		table.insert(params, "--")
		table.insert(params, "--json")
		if n then
			table.insert(params, "--n")
			table.insert(params, tostring(n))
		end
	end
	local r = run(tool("lune"), params)
	local c = { name = name, ok = r.code == 0, ms = r.ms }
	if s.json and r.code == 0 then
		local okD, data = pcall(serde.decode, "json", r.stdout)
		c.ok = okD
		c.data = okD and data or nil
		c.detail = okD and (("%d rows"):format(#(data.rows or {}))) or "bad JSON"
	else
		c.text = r.stdout
		c.detail = r.code == 0 and (("%d lines"):format(#lines(r.stdout))) or trim(r.stderr)
	end
	return c
end

local function cmdSim()
	local which = pos[2] or "list"
	if which == "list" then
		local t = {}
		for _, k in SIM_ORDER do table.insert(t, { name = k, json = SIMS[k].json == true, about = SIMS[k].about }) end
		return result("sim list", {}, { sims = t, studio = STUDIO_TOOLS })
	end
	local n = tonumber(flag("--n"))
	local checks = {}
	if which == "all" then
		for _, k in SIM_ORDER do table.insert(checks, runSim(k, n)) end
	else
		table.insert(checks, runSim(which, n))
	end
	return result("sim " .. which, checks)
end

-- ============ baseline ============
local BASELINE = ".bas/baseline.json"
local function collect()
	local tests = checkTests()
	local chase = runSim("chase_threat", 2000)
	local late = runSim("late_game")
	return {
		at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
		commit = git({ "rev-parse", "--short", "HEAD" }),
		branch = git({ "rev-parse", "--abbrev-ref", "HEAD" }),
		tests = { passed = tests.passed, failed = tests.failed },
		chase = chase.data,
		late = late.data,
	}, { tests, chase, late }
end

local function diffBaseline(base, now, tol)
	local flags = {}
	local function add(f) table.insert(flags, f) end
	if (now.tests.failed or 0) > 0 then add({ what = "tests", detail = now.tests.failed .. " failing" }) end
	if (now.tests.passed or 0) < (base.tests.passed or 0) then
		add({ what = "tests", detail = ("passed went %d -> %d"):format(base.tests.passed or 0, now.tests.passed or 0) })
	end
	local function key(r) return r.tier .. "@" .. r.speed end
	local old = {}
	for _, r in (base.chase and base.chase.rows) or {} do old[key(r)] = r end
	for _, r in (now.chase and now.chase.rows) or {} do
		local o = old[key(r)]
		if not o then
			add({ what = "chase", detail = "new row " .. key(r) })
		else
			for skill, v in r.escape do
				local was = o.escape[skill]
				if was == nil or math.abs(v - was) > tol then
					add({ what = "chase", row = key(r), skill = skill, from = was, to = v,
						detail = ("%s %s escape %s%% -> %s%%"):format(key(r), skill, tostring(was), tostring(v)) })
				end
			end
		end
	end
	local lo = {}
	for _, r in (base.late and base.late.rows) or {} do lo[r.spin] = r end
	for _, r in (now.late and now.late.rows) or {} do
		local o = lo[r.spin]
		if not o or o.price ~= r.price or o.waitSec ~= r.waitSec or table.concat(o.nightCover, ",") ~= table.concat(r.nightCover, ",") then
			add({ what = "economy", spin = r.spin, detail = ("spin %d: price %s -> %s, wait %ss -> %ss"):format(r.spin,
				tostring(o and o.price), tostring(r.price), tostring(o and o.waitSec), tostring(r.waitSec)) })
		end
	end
	return flags
end

local function cmdBaseline()
	local sub = pos[2] or "diff"
	ensureDir(".bas")
	if sub == "save" then
		local snap, checks = collect()
		writeJson(BASELINE, snap)
		return result("baseline save", checks, { saved = BASELINE, commit = snap.commit })
	elseif sub == "diff" then
		local base = readJson(BASELINE)
		if not base then
			return result("baseline diff", { { name = "baseline", ok = false, ms = 0, detail = "no baseline yet: run `bas baseline save` on a known-good tree" } })
		end
		local tol = tonumber(flag("--tol")) or 5
		local now, checks = collect()
		local flags = diffBaseline(base, now, tol)
		table.insert(checks, { name = "drift", ok = #flags == 0, ms = 0,
			detail = (#flags == 0 and "no drift" or (#flags .. " numbers moved")) .. (" (tolerance %s pts, baseline %s)"):format(tol, tostring(base.commit)) })
		return result("baseline diff", checks, { drift = flags, baselineCommit = base.commit, tol = tol })
	end
	return nil
end

-- ============ evidence ============
local function cmdEvidence()
	local sub = pos[2] or "show"
	ensureDir(".bas")
	ensureDir(".evidence")
	if sub == "new" then
		local slug = (pos[3] or "task"):gsub("[^%w%-]", "-")
		local dir = (".evidence/%s-%s"):format(os.date("%Y-%m-%d"), slug)
		ensureDir(dir)
		local m = {
			task = slug,
			created = os.date("!%Y-%m-%dT%H:%M:%SZ"),
			branch = git({ "rev-parse", "--abbrev-ref", "HEAD" }),
			commit = git({ "rev-parse", "--short", "HEAD" }),
			files = {},
			notes = {},
		}
		writeJson(dir .. "/manifest.json", m)
		fs.writeFile(CURRENT, dir)
		return result("evidence new", {}, { dir = dir })
	end
	local dir = currentEvidence()
	if not dir then
		return result("evidence " .. sub, { { name = "evidence", ok = false, ms = 0, detail = "no current evidence folder: run `bas evidence new <slug>`" } })
	end
	local m = readJson(dir .. "/manifest.json") or { files = {}, notes = {} }
	if sub == "add" then
		local src = pos[3]
		if not (src and fs.isFile(src)) then
			return result("evidence add", { { name = "add", ok = false, ms = 0, detail = "no such file: " .. tostring(src) } })
		end
		local base = src:match("([^/\\]+)$")
		fs.copy(src, dir .. "/" .. base, true)
		manifestAdd(dir, { file = base, kind = flag("--kind") or "file", at = os.date("!%Y-%m-%dT%H:%M:%SZ") })
		return result("evidence add", {}, { dir = dir, file = base })
	elseif sub == "shot" then
		-- Studio MCP's screen_capture hands the image to the agent, not to disk, so the
		-- proof folder takes its own: the whole desktop (Studio must be in front). Windows only.
		if process.os ~= "windows" then
			return result("evidence shot", { { name = "shot", ok = false, ms = 0, detail = "Windows only" } })
		end
		local n = 1
		for _, f in m.files or {} do
			if f.kind == "screenshot" then n += 1 end
		end
		local base = ("%s-%d.png"):format((pos[3] or "shot"):gsub("[^%w%-]", "-"), n)
		local full = (process.cwd .. "/" .. dir .. "/" .. base):gsub("/", "\\")
		local ps = table.concat({
			"Add-Type -AssemblyName System.Windows.Forms, System.Drawing",
			"$b = [System.Windows.Forms.SystemInformation]::VirtualScreen",
			"$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height",
			"$g = [System.Drawing.Graphics]::FromImage($bmp)",
			"$g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)",
			("$bmp.Save('%s', [System.Drawing.Imaging.ImageFormat]::Png)"):format(full),
		}, "; ")
		local r = run("powershell", { "-NoProfile", "-Command", ps })
		local ok = r.code == 0 and fs.isFile(dir .. "/" .. base)
		if ok then manifestAdd(dir, { file = base, kind = "screenshot", at = os.date("!%Y-%m-%dT%H:%M:%SZ") }) end
		return result("evidence shot", { { name = "shot", ok = ok, ms = r.ms, detail = ok and base or trim(r.stderr) } }, { dir = dir })
	elseif sub == "note" then
		local text = table.concat(pos, " ", 3)
		m.notes = m.notes or {}
		table.insert(m.notes, text)
		writeJson(dir .. "/manifest.json", m)
		return result("evidence note", {}, { dir = dir })
	elseif sub == "done" then
		-- the "done" contract from the verify-game skill: proof, not a claim
		local kinds = {}
		for _, f in m.files or {} do kinds[f.kind] = true end
		local hasNotVerified = false
		for _, n in m.notes or {} do
			if n:lower():match("^not verified") then hasNotVerified = true end
		end
		local checks = {
			{ name = "check result", ok = kinds.check == true, ms = 0, detail = "bas check --json --save" },
			{ name = "screenshot", ok = kinds.screenshot == true, ms = 0, detail = "evidence add <png> --kind screenshot" },
			{ name = "console log", ok = kinds.console == true, ms = 0, detail = "evidence add <txt> --kind console (server + client errors)" },
			{ name = "not-verified list", ok = hasNotVerified, ms = 0, detail = "evidence note \"not verified: ...\"" },
		}
		return result("evidence done", checks, { dir = dir })
	end
	return result("evidence show", {}, { dir = dir, manifest = m })
end

-- ============ scenarios ============
local function cmdScenario()
	local src = fs.isFile("src/ServerScriptService/DevScenarios.lua") and fs.readFile("src/ServerScriptService/DevScenarios.lua") or ""
	local block = src:match("Scen%.LIST = (%b{})") or "{}"
	local names = {}
	for n in block:gmatch('"([^"]+)"') do table.insert(names, n) end
	local call = 'local p = game.Players:GetPlayers()[1] return game.ServerScriptService.SiliconCore.SVDev:Invoke("scenario", p, "%s")'
	local t = {}
	for _, n in names do table.insert(t, { name = n, server = call:format(n) }) end
	return result("scenario list", {}, {
		scenarios = t,
		restoreAfterStop = 'return require(game.ServerScriptService.DevScenarios).restore(1688749216)  -- EDIT datamodel, after Play stops',
	})
end

-- ============ feature map ============
local function walk(dir, out)
	for _, name in fs.readDir(dir) do
		local p = dir .. "/" .. name
		if fs.isDir(p) then
			walk(p, out)
		elseif name:match("%.luau?$") then
			table.insert(out, p)
		end
	end
	return out
end

local function cmdMap()
	local mapDir = "docs/features"
	if not fs.isDir(mapDir) then
		return result("map check", { { name = "map", ok = false, ms = 0, detail = "no docs/features yet" } })
	end
	local pages, text = {}, {}
	for _, f in fs.readDir(mapDir) do
		if f:match("%.md$") then
			local body = fs.readFile(mapDir .. "/" .. f)
			pages[f] = body
			table.insert(text, body)
		end
	end
	local all = table.concat(text, "\n")
	-- every module name under src must be named on some page
	local seen, uncovered, total = {}, {}, 0
	for _, p in walk("src", {}) do
		local base = p:match("([^/]+)$"):gsub("%.server%.luau?$", ""):gsub("%.client%.luau?$", ""):gsub("%.luau?$", "")
		if base == "init" then base = p:match("([^/]+)/[^/]+$") end
		if not seen[base] then
			seen[base] = true
			total += 1
			if not all:find("%f[%w_]" .. base:gsub("%p", "%%%0") .. "%f[^%w_]") then table.insert(uncovered, { module = base, path = p }) end
		end
	end
	-- a page is stale when a file it cites changed after its "Last verified" commit
	local stale = {}
	for f, body in pages do
		if f ~= "README.md" then
			local commit = body:match("Last verified:[^\n]-(%x%x%x%x%x%x%x+)")
			if not commit then
				table.insert(stale, { page = f, why = "no 'Last verified: <date> <commit>' line" })
			else
				local cited, uniq = {}, {}
				for path in body:gmatch("(src/[%w_/%.%-]+%.luau?)") do
					if not uniq[path] then uniq[path] = true table.insert(cited, path) end
				end
				if #cited > 0 then
					local params = { "diff", "--name-only", commit, "HEAD", "--" }
					for _, c in cited do table.insert(params, c) end
					local changed = git(params)
					if changed == nil then
						table.insert(stale, { page = f, why = "commit " .. commit .. " not found" })
					elseif changed ~= "" then
						table.insert(stale, { page = f, why = "changed since " .. commit .. ": " .. changed:gsub("\n", ", ") })
					end
				end
			end
		end
	end
	table.sort(uncovered, function(a, b) return a.module < b.module end)
	local covered = total - #uncovered
	return result("map check", {
		{ name = "coverage", ok = #uncovered == 0, ms = 0, detail = ("%d/%d src modules named on a page"):format(covered, total) },
		{ name = "staleness", ok = #stale == 0, ms = 0, detail = ("%d stale pages"):format(#stale) },
	}, { uncovered = uncovered, stale = stale })
end

-- ============ output ============
local HELP = [[
bas -- one command for every check this game has. Run from the game folder.

  lune run tools/bas check                 lint + offline tests (~7 s)
  lune run tools/bas doctor                tools, git, Rojo serve, Studio
  lune run tools/bas sim list|<name>|all   the Lune sims [--n N]
  lune run tools/bas baseline save|diff    remember / compare the numbers [--tol 5]
  lune run tools/bas evidence new <slug>   start a proof folder (.evidence/<date>-<slug>)
  lune run tools/bas evidence add <file> --kind screenshot|console|table|file
  lune run tools/bas evidence shot <name>   desktop screenshot into the folder (Studio in front)
  lune run tools/bas evidence note "not verified: ..."
  lune run tools/bas evidence show|done    done = the proof contract is met
  lune run tools/bas scenario list         Studio one-liners (SVDev scenarios)
  lune run tools/bas map check             feature map coverage + staleness

  --json   one JSON object on stdout     --save   also file it in the evidence folder
  exit 0 ok, 1 a check failed, 2 usage error]]

local function show(res)
	if JSON then
		print(serde.encode("json", res))
		return
	end
	print(("%s  %s"):format(res.ok and "OK  " or "FAIL", res.command))
	for _, c in res.checks do
		local tag = c.ok and "  pass" or (c.level == "warn" and "  warn" or "  FAIL")
		print(("%s  %-14s %s%s"):format(tag, c.name, c.detail or "", c.ms and c.ms > 0 and ("  (%d ms)"):format(c.ms) or ""))
		if not c.ok and c.output then print(c.output) end
	end
	if res.drift and #res.drift > 0 then
		for _, f in res.drift do print("    moved: " .. f.detail) end
	end
	if res.sims then
		for _, s in res.sims do print(("  %-13s %s%s"):format(s.name, s.about, s.json and "  [json]" or "")) end
		print("  Studio-only checks:")
		for _, s in res.studio do print(("  %-13s %s"):format(s.name, s.how)) end
	end
	if res.scenarios then
		for _, s in res.scenarios do print(("  %-20s %s"):format(s.name, s.server)) end
		print("  after Play stops:  " .. res.restoreAfterStop)
	end
	if res.uncovered then
		for _, u in res.uncovered do print("    not on any page: " .. u.module .. "  (" .. u.path .. ")") end
		for _, st in res.stale do print("    stale: " .. st.page .. "  " .. st.why) end
	end
	if res.dir then print("  folder: " .. res.dir) end
	if res.manifest then print(serde.encode("json", res.manifest, true)) end
	if res.saved then print("  saved " .. res.saved .. " at " .. tostring(res.commit)) end
	if res.savedTo then print("  filed in " .. res.savedTo) end
	for _, c in res.checks do
		if c.text then print(c.text) end
	end
end

if not fs.isFile("default.project.json") then
	print("bas: run from the game folder (where default.project.json is)")
	process.exit(2)
end

local cmd = pos[1] or "help"
local res
if cmd == "check" then
	res = cmdCheck()
elseif cmd == "doctor" then
	res = cmdDoctor()
elseif cmd == "sim" then
	res = cmdSim()
elseif cmd == "baseline" then
	res = cmdBaseline()
elseif cmd == "evidence" then
	res = cmdEvidence()
elseif cmd == "scenario" then
	res = cmdScenario()
elseif cmd == "map" then
	res = cmdMap()
end

if not res then
	print(HELP)
	process.exit(cmd == "help" and 0 or 2)
end

if SAVE and (cmd == "check" or cmd == "sim" or cmd == "baseline") then
	local kind = cmd == "check" and "check" or "table"
	res.savedTo = saveToEvidence(cmd .. (pos[2] and ("-" .. pos[2]) or ""), kind, res)
end

show(res)
process.exit(res.ok and 0 or 1)
