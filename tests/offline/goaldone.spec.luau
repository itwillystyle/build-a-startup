-- goaldone.spec.luau: when the goal card may stamp DONE! (GoalDone.finished), 18 Oct 2026.
-- Playtest 22-54-32, 0:44: "Upgrade your HQ" stepped aside for "Save up for level 2" after a
-- GIVE (the line went 2 -> 1) and the card said DONE! with a tick; nothing had been built.
local G = require("../../src/ReplicatedStorage/GoalDone")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

test("a goal that stepped aside unfinished is not DONE: upgrade -> hq with no new level", function()
	assert(G.finished("upgrade", "hq", { levelUp = false }) == false, "upgrade without a level is not done")
	assert(G.finished("upgrade", "hq", {}) == false, "no context: not done")
	assert(G.finished("upgrade", "recruit", { levelUp = true }) == true, "the level went up: done")
end)

test("the line going 1 -> 2 is not DONE for serve; the line emptied is", function()
	assert(G.finished("serve", "upgrade", { lineEmpty = false }) == false, "more clients came: not done")
	assert(G.finished("serve", "wait", { lineEmpty = true }) == true, "everyone served: done")
end)

test("hire and carry are DONE only when the team grew (a lost carry is not)", function()
	assert(G.finished("hire", "upgrade", { staffUp = true }) == true, "hired")
	assert(G.finished("hire", "serve", { staffUp = false }) == false, "hire goal went away, nobody hired")
	assert(G.finished("carry", "recruit", { staffUp = false }) == false, "LOST: not done")
	assert(G.finished("carry", "upgrade", { staffUp = true }) == true, "delivered: done")
end)

test("the tutorial steps are DONE when they move on", function()
	assert(G.finished("code", "deliver", {}) == true, "coded the to-do app")
	assert(G.finished("deliver", "serve", {}) == true, "took it to the client")
end)

test("a purchase goal is DONE when the money left your pocket", function()
	assert(G.finished("hq", "recruit", { cost = 100, spent = 90 }) == true, "paid")
	assert(G.finished("hq", "upgrade", { cost = 100, spent = 0 }) == false, "a goal swapped, nothing bought")
end)

test("passive goals, LAUNCH and missing keys never stamp", function()
	assert(G.finished("wait", "serve", {}) == false, "wait")
	assert(G.finished("watch", "hire", {}) == false, "watch")
	assert(G.finished("code", "product", {}) == false, "LAUNCH interrupts, it does not finish")
	assert(G.finished(nil, "code", {}) == false and G.finished("code", nil, {}) == false, "nil keys")
	assert(G.finished("code", "deliver", nil) == true, "nil context is allowed")
end)

return T
