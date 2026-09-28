--[[ Offline test runner: runs every *.spec.luau in this folder, outside Studio.
	From the game folder:  lune run tests/offline/run
A spec returns a list of { name, fn }; fn errors (assert) to fail. Exits 1 on any
failure, so the pre-commit hook can refuse the commit. Only PURE modules can be
tested here (no game:GetService at load): Progression, RoomEconomy, CoreConfig. ]]
local fs = require("@lune/fs")
local process = require("@lune/process")
require("./roblox_globals")

local dir = "tests/offline"
local files = {}
for _, f in fs.readDir(dir) do
	if f:match("%.spec%.luau$") then table.insert(files, f) end
end
table.sort(files)

local passed, failed = 0, 0
for _, f in files do
	local ok, cases = pcall(require, "./" .. f:gsub("%.luau$", ""))
	if not ok then
		print(("FAIL  %s: could not load (%s)"):format(f, tostring(cases)))
		failed += 1
		continue
	end
	for _, c in cases do
		local okc, err = pcall(c.fn)
		if okc then
			passed += 1
		else
			failed += 1
			print(("FAIL  %s > %s\n      %s"):format(f, c.name, tostring(err)))
		end
	end
end
print(("%d passed, %d failed (%d spec files)"):format(passed, failed, #files))
process.exit(failed == 0 and 0 or 1)
