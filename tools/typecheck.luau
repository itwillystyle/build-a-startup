--[[ The type-check gate (26 Oct 2026): luau-lsp over src/, against tests/types-baseline.txt.

	  lune run tools/typecheck            fail if any file gained a type error (CI + the pre-commit hook)
	  lune run tools/typecheck --update   write the baseline from today's errors (after fixing some)

	It needs the Roblox type definitions (globalTypes.d.luau, gitignored): fetched once from
	luau-lsp's own repo at the release rokit.toml pins, and refused unless its sha256 matches.
	A sourcemap from rojo tells luau-lsp which script is which instance. The rules for reading
	the output live in tools/typecheck_lib.luau (tested).

	What it does NOT catch (src/ is nonstrict, no --!strict anywhere): a typo'd Roblox member
	(part:Clonee(), part.Foo = 1), indexing a nil local, writing a read-only property. It does catch
	wrong argument counts and types, an annotated value of the wrong type, unknown globals, a typo'd
	field on a known module table, and every syntax error. Green here is not "no type bugs".
	A count ratchet: fixing one error and adding another with the same file + message passes.

	Offline: the hook skips with a warning when the definitions can't be fetched; CI (env CI set)
	fails instead, after 3 tries. ]]

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")
local task = require("@lune/task")
local L = require("./typecheck_lib")

local DEFS = "globalTypes.d.luau"
local DEFS_URL = "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/1.70.1/scripts/globalTypes.d.luau"
local DEFS_SHA = "2857efa8245485f8c25c19c018ee1ef9b46afab4efd2ea70fc3257cd3faf7080"   -- luau-lsp 1.70.1
local BASELINE = "tests/types-baseline.txt"
local update = table.find(process.args, "--update") ~= nil

local function tool(name)
	local home = process.env.HOME or process.env.USERPROFILE or ""
	for _, p in { home .. "/.rokit/bin/" .. name, home .. "/.rokit/bin/" .. name .. ".exe" } do
		if fs.isFile(p) then return p end
	end
	return name   -- on PATH (CI)
end

local function fail(msg)
	stdio.ewrite("typecheck: " .. msg .. "\n")
	process.exit(1)
end

local function exec(name, args)
	local ok, res = pcall(process.exec, tool(name), args)
	if not ok then fail(name .. " not found or would not start (" .. tostring(res) .. ")") end
	return res
end

-- the definitions: a wrong or half-downloaded file would make every check pass or fail for nothing
if not fs.isFile(DEFS) or serde.hash("sha256", fs.readFile(DEFS)) ~= DEFS_SHA then
	-- 3 tries: one flaky download must not turn a PR red (review round 1)
	local body, why
	for try = 1, 3 do
		local ok, res = pcall(net.request, DEFS_URL)
		if ok and res.ok then
			body = res.body
			break
		end
		why = if ok then "HTTP " .. tostring(res.statusCode) else tostring(res)
		if try < 3 then task.wait(2 * try) end
	end
	if not body then
		if process.env.CI then fail("could not download the Roblox type definitions: " .. why) end
		stdio.ewrite("typecheck: SKIPPED, could not download the Roblox type definitions (" .. why .. "); CI will still check\n")
		process.exit(0)
	end
	if serde.hash("sha256", body) ~= DEFS_SHA then fail("the downloaded type definitions do not match the pinned sha256") end
	fs.writeFile(DEFS, body)
end

local map = exec("rojo", { "sourcemap", "default.project.json", "--output", "sourcemap.json" })
if not map.ok then fail("rojo sourcemap failed: " .. map.stderr) end

local run = exec("luau-lsp", { "analyze", "--sourcemap=sourcemap.json", "--definitions=" .. DEFS, "--ignore=Packages/**", "src" })
local errors = L.parse(run.stdout .. "\n" .. run.stderr)
local now = L.tally(errors)
-- luau-lsp exits 0 (clean) or 1 (found errors); anything else is a crash partway, and fewer errors
-- than the baseline would read as "fixed" (review round 1)
if run.code ~= 0 and run.code ~= 1 then fail(("luau-lsp stopped with exit %d:\n%s"):format(run.code, run.stderr:sub(-2000))) end
if #errors == 0 and not run.ok and not (run.stdout .. run.stderr):find("%(%d+,%d+%)") then
	fail("luau-lsp did not run:\n" .. run.stderr)   -- no findings at all and a failure exit: the tool broke, not the code
end

if update then
	fs.writeFile(BASELINE, L.format(now))
	print(("typecheck: baseline written, %d type errors in %d names"):format(#errors, (function() local n = 0 for _ in now do n += 1 end return n end)()))
	process.exit(0)
end

local base = L.load(fs.isFile(BASELINE) and fs.readFile(BASELINE) or "")
local d = L.diff(base, now)
if #d.grew > 0 then
	print(("typecheck: %d new type error(s). Fix them, or if one is a false alarm, say why in the commit and run --update:"):format(#d.grew))
	for _, line in L.report(d, errors) do print("  " .. line) end
	process.exit(1)
end
if #d.shrank > 0 then
	print(("typecheck: ok, and %d error name(s) fixed. Lock it in: lune run tools/typecheck --update"):format(#d.shrank))
else
	print(("typecheck: ok (%d known type errors, none new)"):format(#errors))
end
