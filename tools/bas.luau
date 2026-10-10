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
	    lune run tools/bas ship | world | health   the morning run (Phase 2)
    lune run tools/bas playtest list | prep <video>|--new | done <video>   review a screen recording
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
local VALUE_FLAGS = { ["--n"] = true, ["--tol"] = true, ["--kind"] = true, ["--log"] = true, ["--dir"] = true, ["--note"] = true, ["--days"] = true }
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
	local old, seen = {}, {}
	for _, r in (base.chase and base.chase.rows) or {} do old[key(r)] = r end
	for _, r in (now.chase and now.chase.rows) or {} do
		local o = old[key(r)]
		seen[key(r)] = r
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
	-- the other direction: a row or play style the new run no longer reports is drift too
	for k, o in old do
		local r = seen[k]
		if not r then
			add({ what = "chase", row = k, detail = "row " .. k .. " missing from the new run" })
		else
			for skill, was in o.escape do
				if r.escape[skill] == nil then
					add({ what = "chase", row = k, skill = skill, from = was,
						detail = ("%s %s escape %s%% -> missing"):format(k, skill, tostring(was)) })
				end
			end
		end
	end
	local lo, ls = {}, {}
	for _, r in (base.late and base.late.rows) or {} do lo[r.spin] = r end
	for _, r in (now.late and now.late.rows) or {} do
		local o = lo[r.spin]
		ls[r.spin] = true
		if not o or o.price ~= r.price or o.waitSec ~= r.waitSec or table.concat(o.nightCover, ",") ~= table.concat(r.nightCover, ",") then
			add({ what = "economy", spin = r.spin, detail = ("spin %d: price %s -> %s, wait %ss -> %ss"):format(r.spin,
				tostring(o and o.price), tostring(r.price), tostring(o and o.waitSec), tostring(r.waitSec)) })
		end
	end
	for spin in lo do
		if not ls[spin] then
			add({ what = "economy", spin = spin, detail = ("spin %d missing from the new run"):format(spin) })
		end
	end
	local wasMax = base.late and base.late.maxPrestigeSec
	local nowMax = now.late and now.late.maxPrestigeSec
	if (wasMax ~= nil or nowMax ~= nil) and wasMax ~= nowMax then
		add({ what = "economy", from = wasMax, to = nowMax,
			detail = ("max prestige time %ss -> %ss"):format(tostring(wasMax), tostring(nowMax)) })
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
		local lastCheck
		for _, f in m.files or {} do
			kinds[f.kind] = true
			if f.kind == "check" then lastCheck = f.file end
		end
		local hasNotVerified = false
		for _, n in m.notes or {} do
			if n:lower():match("^not verified") then hasNotVerified = true end
		end
		-- a filed check only counts if it passed: read the newest one and look at its ok
		local checkOk, checkDetail = false, "bas check --json --save"
		if lastCheck then
			local filed = readJson(dir .. "/" .. lastCheck)
			if not filed then
				checkDetail = lastCheck .. " is missing or not JSON"
			elseif filed.ok ~= true then
				checkDetail = lastCheck .. " is filed but failed: fix and re-run bas check --save"
			else
				checkOk, checkDetail = true, lastCheck .. " passed"
			end
		end
		local checks = {
			{ name = "check result", ok = checkOk, ms = 0, detail = checkDetail },
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
			-- GitHub's rebase and squash merges rewrite commit ids, so a stamp made on a
			-- branch is not in main's history. Then the page counts as checked when it
			-- last changed: the commit that landed it along with the code it describes.
			if commit and git({ "merge-base", "--is-ancestor", commit, "HEAD" }) == nil then
				local landed = git({ "log", "-1", "--format=%h", "--", mapDir .. "/" .. f })
				if landed and landed ~= "" then commit = landed end
			end
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
-- ============ the morning run (Phase 2): ship, world, health ============
local Health = require("./health_lib")
local WORLD_GOOD = ".bas/world.json"     -- the last Play run with no failure
local HEALTH_LAST = ".bas/health.json"   -- the last morning run, for "changed since"
local HEALTH_MD = "../HEALTH.md"         -- silicon-startup/HEALTH.md: outside the repo, so it never makes a commit

-- Studio's own log files, newest first (the file name carries the start time)
local function studioLogs()
	local dir = (process.env.LOCALAPPDATA or "") .. "/Roblox/logs"
	if not fs.isDir(dir) then return {} end
	local out = {}
	for _, f in fs.readDir(dir) do
		local stamp = f:match("_(%d+T%d+Z)_Studio_")
		if stamp then table.insert(out, { path = dir .. "/" .. f, stamp = stamp }) end
	end
	table.sort(out, function(a, b) return a.stamp > b.stamp end)
	return out
end

-- patch ids of a diff or a `git log -p` (one per commit), as a set
local function patchIds(text)
	local ok, r = pcall(process.exec, "git", { "patch-id", "--stable" }, { stdio = { stdin = text } })   -- Lune 0.10: stdin lives under stdio
	local ids = {}
	if ok and r.ok then
		for _, l in lines(r.stdout) do
			local id = l:match("^(%x+)")
			if id then ids[id] = true end
		end
	end
	return ids
end

--[[ Is every change on `branch` already in main? GitHub's rebase and squash merges
	give the commits new ids, and main may have edited the same lines again since,
	so neither the ids nor a test merge can say. The patches can:
	  1. merging it changes nothing (a branch main simply contains)
	  2. rebase merge: every one of its patches is on main (git cherry)
	  3. squash merge: its whole diff is one commit on main ]]
local function onMain(branch, mainTree)
	local merged = git({ "merge-tree", "--write-tree", "origin/main", branch })
	if merged ~= nil and lines(merged)[1] == mainTree then return true end
	local cherry = git({ "cherry", "origin/main", branch })
	if cherry ~= nil and not ("\n" .. cherry):find("\n%+") then return true end
	local base = git({ "merge-base", "origin/main", branch })
	if not base then return false end
	-- raw output: git() trims, and a trimmed diff loses its last context line (a new patch id)
	local mine = patchIds(run("git", { "diff", base, branch }).stdout or "")
	local theirs = patchIds(run("git", { "log", "-p", base .. "..origin/main" }).stdout or "")
	for id in mine do
		if theirs[id] then return true end
	end
	return false
end

local function cmdShip()
	run("git", { "fetch", "-q", "origin" })   -- read-only; offline, origin/main is as of the last fetch
	local now = os.time()
	local lastSave, lastPublish
	for _, l in studioLogs() do
		local s, p = Health.saveAndPublish(fs.readFile(l.path))
		lastSave = lastSave or (s and Health.isoToUnix(s))
		lastPublish = lastPublish or (p and Health.isoToUnix(p))
		if lastSave and lastPublish then break end
	end
	local mainSince = {}
	for _, l in lines(git({ "log", "origin/main", "-200", "--format=%h %ct %s" }) or "") do
		local sha, ct, subject = l:match("^(%x+) (%d+) (.*)$")
		if sha and lastPublish and tonumber(ct) > lastPublish then
			table.insert(mainSince, { sha = sha, unix = tonumber(ct), subject = subject })
		end
	end
	local mainTree = git({ "rev-parse", "origin/main^{tree}" })
	local branches = {}
	for _, l in lines(git({ "for-each-ref", "refs/heads", "--format=%(refname:short) %(committerdate:unix)" }) or "") do
		local name, ct = l:match("^(%S+) (%d+)$")
		if name and name ~= "main" and not onMain(name, mainTree) then
			local ahead = tonumber(git({ "rev-list", "--count", "origin/main.." .. name }) or "0") or 0
			table.insert(branches, { name = name, ahead = ahead, lastUnix = tonumber(ct) })
		end
	end
	local checks = Health.ship({ now = now, lastSave = lastSave, lastPublish = lastPublish, mainSince = mainSince, branches = branches })
	for _, c in checks do c.ms = 0 end
	return result("ship", checks, { mainSince = mainSince, branches = branches })
end

-- the newest Play run in the Studio logs (or in --log <file>)
local function newestRun()
	local only = flag("--log")
	if only then return Health.lastRun(fs.readFile(only)), only end
	for _, l in studioLogs() do
		local r = Health.lastRun(fs.readFile(l.path))
		if r then return r, l.path end
	end
	return nil, nil
end

local function cmdWorld()
	local sub = pos[1] == "world" and pos[2] or "check"
	ensureDir(".bas")
	local r, from = newestRun()
	if not r then
		return result("world", { { name = "log", ok = false, level = "warn", ms = 0, detail = "no Play run in any Studio log" } })
	end
	if sub == "save" then
		writeJson(WORLD_GOOD, r)
		return result("world save", { { name = "saved", ok = true, ms = 0, detail = ("the run of %s is now the good one"):format(tostring(r.startIso)) } })
	end
	local age = (os.time() - (r.startUnix or 0)) / 3600
	local checks = { { name = "log", ok = age <= 24, level = "warn", ms = 0,
		detail = ("last Play run %s UTC, %.0f h ago%s"):format(tostring(r.startIso), age,
			age > 24 and " (not fresh: Play once to check the world)" or "") } }
	local good = readJson(WORLD_GOOD)
	local flags = Health.compareWorld(good, r)
	local fails = 0
	for _, f in flags do
		table.insert(checks, { name = "world", ok = false, level = f.level == "warn" and "warn" or nil, ms = 0, detail = f.text })
		if f.level == "fail" then fails += 1 end
	end
	if #flags == 0 then
		local m = r.metrics
		table.insert(checks, { name = "world", ok = true, ms = 0, detail = ("%s/%s meshes, %s hill trees, %s avatars, 0 script errors%s"):format(
			tostring(m.furnitureMeshes), tostring(m.furnitureTotal), tostring(m.hillTrees), tostring(m.avatars),
			good and "; nothing dropped since the last good run" or "; no good run saved yet") })
	end
	return result("world", checks, { run = r, from = from, failures = fails })
end

local function cmdHealth()
	ensureDir(".bas")
	local started = os.time()   -- wall clock: os.clock counts this process only, not git or the tests
	local sections = {
		{ title = "lint", res = result("lint", { checkSelene() }) },
		{ title = "tests, sims, drift", res = cmdBaseline() },
		{ title = "feature map", res = cmdMap() },
		{ title = "ship", res = cmdShip() },
		{ title = "world", res = cmdWorld() },
	}
	-- a clean world run becomes the good one, so tomorrow compares with today
	local w = sections[5].res
	if w.run and (w.failures or 0) == 0 then writeJson(WORLD_GOOD, w.run) end

	local all, ok = {}, true
	for _, s in sections do
		if not s.res.ok then ok = false end
		for _, c in s.res.checks do
			table.insert(all, { section = s.title, name = c.name, ok = c.ok, level = c.level, detail = c.detail })
		end
	end
	local prev = readJson(HEALTH_LAST)
	local seen = {}
	for _, c in (prev and prev.checks) or {} do seen[c.section .. "/" .. c.name .. "/" .. tostring(c.detail)] = true end
	local function mark(c) return c.ok and "PASS" or (c.level == "warn" and "WARN" or "FAIL") end

	local md = {}
	table.insert(md, ("# Game health: %s"):format(ok and "GREEN" or "RED"))
	table.insert(md, "")
	table.insert(md, ("%s · branch `%s` · %d s · `lune run tools/bas health`"):format(os.date("%a %d %b %Y, %H:%M"),
		tostring(git({ "rev-parse", "--abbrev-ref", "HEAD" })), os.time() - started))
	table.insert(md, "")
	for _, s in sections do
		table.insert(md, ("## %s %s"):format(s.res.ok and "PASS" or "FAIL", s.title))
		for _, c in s.res.checks do table.insert(md, ("- %s %s: %s"):format(mark(c), c.name, tostring(c.detail))) end
		for _, d in s.res.drift or {} do table.insert(md, "  - moved: " .. d.detail) end
		for _, u in s.res.uncovered or {} do table.insert(md, "  - not on any page: " .. u.module) end
		for _, st in s.res.stale or {} do table.insert(md, "  - stale: " .. st.page .. " (" .. st.why .. ")") end
		table.insert(md, "")
	end
	table.insert(md, "## Changed since the last run")
	if not prev then
		table.insert(md, "- first run")
	else
		local any = false
		for _, c in all do
			if not seen[c.section .. "/" .. c.name .. "/" .. tostring(c.detail)] then
				table.insert(md, ("- %s %s / %s: %s"):format(mark(c), c.section, c.name, tostring(c.detail)))
				any = true
			end
		end
		if not any then table.insert(md, "- nothing") end
	end
	table.insert(md, "")
	table.insert(md, "## Open findings")
	local open = 0
	for _, c in all do
		if not c.ok then
			table.insert(md, ("- %s %s / %s: %s"):format(mark(c), c.section, c.name, tostring(c.detail)))
			open += 1
		end
	end
	if open == 0 then table.insert(md, "- none") end
	table.insert(md, "")
	table.insert(md, "Report only: this run never commits, pushes or publishes. Not checked here: how the game")
	table.insert(md, "feels, anything that needs Studio open, and WHICH commit is live (only when it was published).")
	fs.writeFile(HEALTH_MD, table.concat(md, "\n") .. "\n")
	writeJson(HEALTH_LAST, { at = os.time(), checks = all })
	return result("health", { { name = "HEALTH.md", ok = ok, ms = 0,
		detail = ("%s, %d open finding(s), written to %s"):format(ok and "GREEN" or "RED", open, HEALTH_MD) } })
end

-- ============ playtest videos: review a screen recording the same way every time ============
local Playtest = require("./playtest_lib")
local PLAYTESTS = "../playtests"                 -- silicon-startup/playtests: outside the repo (frames are big)
local LEDGER = PLAYTESTS .. "/reviewed.json"     -- name -> { verdict, at, note }

local function videoDir() return flag("--dir") or (HOME .. "/Videos") end

-- the machine's offset from UTC in seconds (EDT = -14400); Luau's os.time(table) reads the table as UTC
local function utcOffset()
	local now = os.time()
	return os.time(os.date("*t", now) :: any) - now
end

local function unixToLocal(unix)
	return os.date("%a %d %b %H:%M:%S", unix)
end

-- recordings named by start time, newest first -> { { name, path, startUnix } }
local function recordings()
	local dir, out = videoDir(), {}
	if not fs.isDir(dir) then return out end
	local off = utcOffset()
	for _, f in fs.readDir(dir) do
		local ext = f:lower():match("%.(%w+)$")
		local st = (ext == "mp4" or ext == "mkv" or ext == "mov") and Playtest.stamp(f)
		if st then table.insert(out, { name = f, path = dir .. "/" .. f, startUnix = Playtest.toUnix(st, off) }) end
	end
	table.sort(out, function(a, b) return a.startUnix > b.startUnix end)
	return out
end

local function duration(path)
	local r = run("ffprobe", { "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path })
	return r.ok and tonumber(trim(r.stdout)) or nil
end

--[[ Every Roblox log (Studio and the Roblox app) that could cover [startUnix, endUnix]:
	started before it ended and was still being written when it began. The second test
	matters: 1,263 recordings and a 5.8 GB Studio log (4 Oct) on this machine, 10 Oct. ]]
local function robloxLogs(startUnix, endUnix)
	local dir = (process.env.LOCALAPPDATA or "") .. "/Roblox/logs"
	local out = {}
	if not fs.isDir(dir) then return out end
	for _, f in fs.readDir(dir) do
		local stamp, kind = f:match("_(%d+T%d+Z)_(%a+)_%x+_last%.log$")
		if stamp and (kind == "Studio" or kind == "Player") then
			local iso = stamp:gsub("^(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)Z$", "%1-%2-%3T%4:%5:%6")
			local u = Health.isoToUnix(iso)
			local path = dir .. "/" .. f
			local ok, meta = pcall(fs.metadata, path)
			local last = ok and meta.modifiedAt and meta.modifiedAt.unixTimestamp or math.huge
			if u and u <= endUnix and last >= startUnix then table.insert(out, { path = path, name = f, unix = u, kind = kind }) end
		end
	end
	table.sort(out, function(a, b) return a.unix > b.unix end)
	return out
end

local logText = {}   -- path -> text: list and prep --new read the same logs once per recording
local function readLog(path)
	logText[path] = logText[path] or fs.readFile(path)
	return logText[path]
end

-- what the logs say about a recording: was our game being played, and what did it print?
-- -> lines, log kinds, session or nil
local function gameLines(rec, dur)
	local found, from, session = {}, {}, nil
	for _, l in robloxLogs(rec.startUnix, rec.startUnix + dur) do
		local text = readLog(l.path)
		session = session or Playtest.playing(Playtest.sessions(text, l.kind), rec.startUnix, rec.startUnix + dur)
		local w = Playtest.window(text, rec.startUnix, rec.startUnix + dur, l.kind)
		if #w > 0 then
			table.insert(from, l.kind)
			for _, x in w do table.insert(found, x) end
		end
	end
	table.sort(found, function(a, b) return a.t < b.t end)
	return found, from, session
end

local function stemDir(name)
	return PLAYTESTS .. "/" .. (name:gsub("%.%w+$", ""):gsub("%s", "_"))
end

local function prep(rec)
	local dur = duration(rec.path)
	if not dur then return { name = "prep", ok = false, ms = 0, detail = rec.name .. ": ffprobe could not read it (is ffmpeg on PATH?)" } end
	local dir = stemDir(rec.name)
	ensureDir(PLAYTESTS)
	ensureDir(dir)
	for _, f in fs.readDir(dir) do
		if f:match("^sheet_%d+%.jpg$") then fs.removeFile(dir .. "/" .. f) end
	end
	local step = Playtest.step(dur)
	-- each frame gets its time burned in, so a finding can cite the second it happened
	local vf = ("fps=1/%d,scale=960:-2,drawtext=fontfile='C\\:/Windows/Fonts/arialbd.ttf':text='%%{pts\\:hms}'"
		.. ":x=14:y=14:fontsize=44:fontcolor=yellow:box=1:boxcolor=black@0.65:boxborderw=8,tile=3x2"):format(step)
	local ff = run("ffmpeg", { "-v", "error", "-y", "-i", rec.path, "-vf", vf, dir .. "/sheet_%02d.jpg" })
	if not ff.ok then return { name = "prep", ok = false, ms = ff.ms, detail = rec.name .. ": ffmpeg failed: " .. trim(ff.stderr):sub(1, 200) } end
	local speech = {}
	if not table.find(A, "--no-speech") then
		local sp = run("python", { "tools/playtest_speech.py", rec.path })
		if sp.ok then speech = lines(sp.stdout) else table.insert(speech, "(speech step failed: " .. trim(sp.stderr):sub(-160) .. ")") end
	end
	local gl, from, session = gameLines(rec, dur)
	local info = { name = rec.name, duration = dur, startUnix = rec.startUnix, startLocal = unixToLocal(rec.startUnix), step = step,
		sheets = Playtest.sheets(dur, step), lines = gl, speech = speech, logs = from, session = session }
	-- never overwrite a review in progress: a fresh skeleton goes beside it
	local notes = dir .. "/notes.md"
	local wrote = fs.isFile(notes) and (dir .. "/notes.new.md") or notes
	fs.writeFile(wrote, Playtest.notes(info))
	local errs = 0
	for _, l in gl do if l.level == "ERROR" then errs += 1 end end
	return { name = "prep", ok = true, ms = ff.ms, detail = ("%s: %s, %s, %d sheet(s), %d spoken line(s), %d game line(s) (%d error(s)) -> %s"):format(
		rec.name, Playtest.clock(dur), session and session.where or "NOT our game", #info.sheets, #speech, #gl, errs, wrote) }
end

local function cmdPlaytest()
	local sub = pos[2] or "list"
	local ledger = readJson(LEDGER) or {}
	if sub == "list" then
		local checks = {}
		for i, rec in recordings() do
			if i > 15 then break end
			local dur = duration(rec.path) or 0
			local gl, _, session = gameLines(rec, dur)
			local seen = ledger[rec.name]
			table.insert(checks, { name = seen and seen.verdict or (session and "new" or "not ours"), ok = true, ms = 0,
				detail = ("%s  %5s  %s, %d game line(s)"):format(rec.name, Playtest.clock(dur), session and session.where or "-", #gl) })
		end
		if #checks == 0 then table.insert(checks, { name = "none", ok = true, ms = 0, detail = "no recordings named by date in " .. videoDir() }) end
		return result("playtest list", checks)
	elseif sub == "prep" then
		local want, checks = pos[3], {}
		local days = tonumber(flag("--days")) or 3
		for _, rec in recordings() do
			local pick
			if want then
				pick = rec.name == want or rec.name:gsub("%.%w+$", "") == want
			else
				-- --new: the last --days (3) of recordings not yet in the ledger, made while our game ran
				pick = rec.startUnix >= os.time() - days * 86400 and not ledger[rec.name]
					and select(3, gameLines(rec, duration(rec.path) or 0)) ~= nil
			end
			if pick then table.insert(checks, prep(rec)) end
		end
		if #checks == 0 then
			table.insert(checks, { name = "prep", ok = want == nil, ms = 0,
				detail = want and ("no recording called " .. want .. " in " .. videoDir()) or "nothing new to review" })
		end
		return result("playtest prep", checks)
	elseif sub == "done" then
		local name = pos[3]
		if not name then return nil end
		for _, rec in recordings() do
			if rec.name == name or rec.name:gsub("%.%w+$", "") == name then name = rec.name end
		end
		local verdict = table.find(A, "--skip") and "skipped" or "reviewed"
		ensureDir(PLAYTESTS)
		ledger[name] = { verdict = verdict, at = os.date("!%Y-%m-%dT%H:%M:%SZ"), note = flag("--note") }
		writeJson(LEDGER, ledger)
		return result("playtest done", { { name = verdict, ok = true, ms = 0, detail = name .. " filed in " .. LEDGER } })
	end
	return nil
end

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
  lune run tools/bas ship                  is the live game behind main? unmerged branches?
  lune run tools/bas world [save] [--log f]  world health from Studio's log vs the last good run
  lune run tools/bas health                all of it, written to ../HEALTH.md (the morning run)
  lune run tools/bas playtest list         screen recordings, which are playtests, which are reviewed
  lune run tools/bas playtest prep <name>|--new [--days 3]   sheets + speech + game log -> ../playtests/<name>/notes.md
  lune run tools/bas playtest done <name> [--skip] [--note "..."]   file it as reviewed

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
elseif cmd == "ship" then
	res = cmdShip()
elseif cmd == "world" then
	res = cmdWorld()
elseif cmd == "health" then
	res = cmdHealth()
elseif cmd == "playtest" then
	res = cmdPlaytest()
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
