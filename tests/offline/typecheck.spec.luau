-- typecheck.spec.luau: the type-check gate's pure half (26 Oct 2026).
-- tools/typecheck.luau runs luau-lsp over src/ and fails a commit or a PR only when a file
-- gains a type error it did not have (tests/types-baseline.txt). These tests pin how its
-- output is read, so a moved line or a renamed table field never reads as a new error.
local L = require("../../tools/typecheck_lib")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local OUT = table.concat({
	"[INFO] Loading definitions file: @roblox - globalTypes.d.luau",
	[[c:\Users\lukex\Downloads\game\src\ReplicatedStorage\CameraWalls.lua [game/ReplicatedStorage/CameraWalls](83,5): TypeError: Key 'started' not found in table 'CameraWalls']],
	[[c:\Users\lukex\Downloads\game\src\ReplicatedStorage\CameraWalls.lua [game/ReplicatedStorage/CameraWalls](83,5): TypeError: Key 'started' not found in table 'CameraWalls']],
	"src/ReplicatedStorage/CameraWalls.lua(94,32): SameLineStatement: A new statement is on the same line",
	"src/ServerScriptService/Phone.lua(141,9): TypeError: Key 'best' not found in table '{| best: any, company: any |}'",
	"src/ServerScriptService/Phone.lua(150,9): TypeError: Key 'best' not found in table '{| best: any, hq: any, rate: any |}'",
}, "\n")

test("reads TypeErrors only, with a repo path, and drops exact duplicates", function()
	local e = L.parse(OUT)
	assert(#e == 3, "got " .. #e)
	assert(e[1].path == "src/ReplicatedStorage/CameraWalls.lua", e[1].path)
	assert(e[1].line == 83 and e[1].col == 5, "line and column")
	assert(e[1].msg == "Key 'started' not found in table 'CameraWalls'", e[1].msg)
end)

test("a syntax error counts too (a file that cannot parse is never checked)", function()
	local e = L.parse([[c:\x\src\ReplicatedStorage\Palette.lua [game/ReplicatedStorage/Palette](373,1): SyntaxError: Expected <eof>, got 'local']])
	assert(#e == 1 and e[1].msg:find("SyntaxError", 1, true), "syntax error missed")
	assert(e[1].path == "src/ReplicatedStorage/Palette.lua", e[1].path)
end)

test("a table's field list is not part of the error's name", function()
	local e = L.parse(OUT)
	assert(e[2].key == e[3].key, e[2].key .. " ~= " .. e[3].key)
	assert(not e[2].key:find("company", 1, true), "shape leaked into the key")
end)

test("a nested table shape is cut whole (review round 1)", function()
	local a = L.parse("src/C.lua(1,1): TypeError: Key 'x' not found in table '{| a: {| b: any |}, sign: any |}'")
	local b = L.parse("src/C.lua(2,1): TypeError: Key 'x' not found in table '{| a: {| b: any, c: any |}, sign: any, more: any |}'")
	assert(a[1].key == b[1].key, a[1].key .. " ~= " .. b[1].key)
	assert(a[1].msg == "Key 'x' not found in table '{...}'", a[1].msg)
end)

test("the path is the last src/ in it, whatever folder the repo sits in (review round 1)", function()
	local e = L.parse([[/x/src/build-a-startup/src/ServerScriptService/A.lua [game/A](3,1): TypeError: boom]])
	assert(e[1].path == "src/ServerScriptService/A.lua", e[1].path)
end)

test("the baseline round-trips and counts each file + message", function()
	local base = L.tally(L.parse(OUT))
	local text = L.format(base)
	local back = L.load(text)
	for k, n in base do assert(back[k] == n, k) end
	local phone = "src/ServerScriptService/Phone.lua\tKey 'best' not found in table '{...}'"
	assert(back[phone] == 2, "phone twice: " .. tostring(back[phone]))
end)

test("a moved line is not new; a second copy of the same error is", function()
	local base = L.tally(L.parse(OUT))
	local moved = OUT:gsub("%(83,5%)", "(90,5)")
	local d = L.diff(base, L.tally(L.parse(moved)))
	assert(#d.grew == 0, "moved line read as new")
	local more = OUT .. "\nsrc/ServerScriptService/Phone.lua(160,9): TypeError: Key 'best' not found in table '{| x: any |}'"
	d = L.diff(base, L.tally(L.parse(more)))
	assert(#d.grew == 1 and d.grew[1].now == 3 and d.grew[1].was == 2, "third copy not caught")
end)

test("an error in a new file is new; a fixed one is reported as fixed", function()
	local base = L.tally(L.parse(OUT))
	local now = L.tally(L.parse(OUT .. "\nsrc/X.lua(1,1): TypeError: Type 'nil' could not be converted into 'number'"))
	local d = L.diff(base, now)
	assert(#d.grew == 1 and d.grew[1].was == 0, "new file's error")
	d = L.diff(base, L.tally(L.parse("")))
	assert(#d.grew == 0 and #d.shrank == 2, "both names fixed: " .. #d.shrank)   -- per name, not per copy
end)

test("the new errors are listed with their lines, so they can be found", function()
	local base = L.tally(L.parse(OUT))
	local more = OUT .. "\nsrc/X.lua(12,3): TypeError: boom"
	local lines = L.report(L.diff(base, L.tally(L.parse(more))), L.parse(more))
	assert(lines[1] and lines[1]:find("src/X.lua:12", 1, true), tostring(lines[1]))
end)

return T
