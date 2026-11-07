-- intent.spec.luau: `bas intent` reads a PR's intent card and refuses one that is missing,
-- still the template, or says "routine" when `bas risk` says Luke must look (7 Nov 2026).
-- CONSTRAINTS.md rule 6 was prose for a month and 0 of PRs #65-#94 carried the card.
local I = require("../../tools/intent_lib")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local GAMEPLAY = { needsLuke = true, counts = { gameplay = 2 } }
local ROUTINE = { needsLuke = false, counts = { docs = 1, tooling = 1 } }

local FULL = [[
**What a player sees:** the leg sweeps at a steady speed.

**Should do:** both kick snaps turn the hip under 45 deg per frame.
**Must not break:** the contact times and the poses.
**Measured:** bobclips.spec 12/12; doctor bob step "nothing snaps": none.
**Not measured:** how the kick feels to Luke.
**Evidence:** ../doctor/pr-bob-kick-snap.md (doctor run, 0 findings)
**Review:** fresh review, 1 round: 2 findings, 2 fixed.
**Risk:** needs Luke (gameplay)
**Undo:** revert this PR; nothing saved changes.
]]

local function has(problems, needle)
	for _, p in problems do
		if p:lower():find(needle:lower(), 1, true) then return true end
	end
	return false
end

test("a full card on a gameplay PR passes", function()
	local r = I.check(FULL, GAMEPLAY)
	assert(r.ok, table.concat(r.problems, "; "))
end)

test("no body at all fails and names the card", function()
	local r = I.check("", GAMEPLAY)
	assert(not r.ok, "not r.ok")
	assert(has(r.problems, "should do"), table.concat(r.problems, "; "))
end)

test("a missing field is named", function()
	local body = FULL:gsub("%*%*Must not break:%*%*[^\n]*\n", "")
	local r = I.check(body, GAMEPLAY)
	assert(not r.ok, "not r.ok")
	assert(has(r.problems, "must not break"), table.concat(r.problems, "; "))
	assert(#r.problems == 1, table.concat(r.problems, "; "))
end)

test("the untouched template fails (hints are HTML comments)", function()
	local template = [[
**Should do:** <!-- one line: what changes for a player -->
**Must not break:** <!-- what nearby still has to work -->
**Measured:** <!-- tests, doctor steps, numbers -->
**Not measured:** <!-- say it plainly -->
**Evidence:** <!-- screenshot, clip or doctor report -->
**Review:** <!-- fresh review: rounds, findings, fixed / answered -->
**Risk:** <!-- paste the bas risk verdict -->
**Undo:** <!-- flag, revert, or place version -->
]]
	local r = I.check(template, GAMEPLAY)
	assert(not r.ok, "not r.ok")
	assert(#r.problems >= 8, ("want every field named, got %d: %s"):format(#r.problems, table.concat(r.problems, "; ")))
end)

test("a placeholder like <...> or TODO is not an answer", function()
	local body = FULL:gsub("%*%*Undo:%*%*[^\n]*", "**Undo:** TODO")
	assert(not I.check(body, GAMEPLAY).ok, "not I.check(body, GAMEPLAY).ok")
	body = FULL:gsub("%*%*Undo:%*%*[^\n]*", "**Undo:** <how to undo>")
	assert(not I.check(body, GAMEPLAY).ok, "not I.check(body, GAMEPLAY).ok")
end)

test("Risk says routine but bas risk says Luke must look: fails", function()
	local body = FULL:gsub("%*%*Risk:%*%*[^\n]*", "**Risk:** routine")
	local r = I.check(body, GAMEPLAY)
	assert(not r.ok, "not r.ok")
	assert(has(r.problems, "bas risk"), table.concat(r.problems, "; "))
end)

test("Risk must be one of the two verdicts", function()
	local body = FULL:gsub("%*%*Risk:%*%*[^\n]*", "**Risk:** low")
	assert(not I.check(body, GAMEPLAY).ok, "not I.check(body, GAMEPLAY).ok")
end)

test("saying needs Luke on a routine PR is allowed (careful is fine)", function()
	local body = FULL
	assert(I.check(body, ROUTINE).ok, "I.check(body, ROUTINE).ok")
end)

test("a gameplay PR needs Evidence; a docs/tooling PR does not", function()
	local body = FULL:gsub("%*%*Evidence:%*%*[^\n]*\n", ""):gsub("needs Luke %(gameplay%)", "routine")
	local r = I.check(body, GAMEPLAY)
	assert(not r.ok and has(r.problems, "evidence"), table.concat(r.problems, "; "))
	local r2 = I.check(body, ROUTINE)
	assert(r2.ok, table.concat(r2.problems, "; "))
end)

test("labels work without bold, in any case, and with the answer on the next line", function()
	local body = [[
should do: the pill shrinks after 4 s
MUST NOT BREAK:
  the goal text stays readable
Measured: goalcard.spec 9/9
Not measured: phone width
Evidence: doctor goal step screenshot
Review: fresh review, 1 round, 0 findings
Risk: needs Luke (gameplay)
Undo: Flags.set("goalPill", false, "live")
]]
	local r = I.check(body, GAMEPLAY)
	assert(r.ok, table.concat(r.problems, "; "))
end)

test("the PR template in the repo is exactly what the check refuses until filled", function()
	local fs = require("@lune/fs")
	local text = fs.readFile(".github/pull_request_template.md")
	local r = I.check(text, GAMEPLAY)
	assert(not r.ok, "not r.ok")
	for _, label in I.FIELDS do
		assert(text:lower():find("**" .. label:lower() .. ":**", 1, true), "template is missing " .. label)
	end
end)

test("text after a blank line does not fill an empty field (the attribution line, review round 1)", function()
	local body = FULL:gsub("%*%*Undo:%*%*[^\n]*", "**Undo:** <!-- a flag, a revert, or a place version -->")
		.. "\n\nGenerated with [Claude Code](https://claude.com/claude-code)\n"
	local r = I.check(body, GAMEPLAY)
	assert(not r.ok and has(r.problems, "undo"), table.concat(r.problems, "; "))
end)

test("a save-only or economy-only change still needs Evidence (review round 1)", function()
	local body = FULL:gsub("%*%*Evidence:%*%*[^\n]*\n", "")
	for _, kind in { "save", "economy" } do
		local r = I.check(body, { needsLuke = true, counts = { [kind] = 1 } })
		assert(not r.ok and has(r.problems, "evidence"), kind .. ": " .. table.concat(r.problems, "; "))
	end
end)

return T
