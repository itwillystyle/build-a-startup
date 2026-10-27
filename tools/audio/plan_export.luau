-- plan_export.luau: Bob's cutscene sound plan as JSON, for `python tools/audio/sfx.py mixcheck`.
-- From the game folder:  lune run tools/audio/plan_export <out.json>
-- (every cue, every bed's level 100 times a second, and each sound's id, start, length and trim)
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
require("../../tests/offline/roblox_globals")
local B = require("../../src/ReplicatedStorage/BobScript")
local Sfx = require("../../src/ReplicatedStorage/Sfx")

local out = { SOUND = {}, scenes = {} }
for name, s in B.SOUND do
	out.SOUND[name] = { key = s[1], id = tostring(Sfx.ID[s[1]]), at = s.at, len = s.len, gain = s.gain }
end
for _, name in { "intro", "payoff" } do
	local L = B.length(name)
	local beds = {}
	for _, b in B.beds(name) do
		local level = {}
		for k = 0, math.floor(L * 100) do table.insert(level, B.bedLevel(name, b, k / 100)) end
		table.insert(beds, { id = b[1], level = level })
	end
	out.scenes[name] = { length = L, cues = B.cues(name, -1, L), beds = beds }
end
local path = process.args[1] or "plan.json"
fs.writeFile(path, serde.encode("json", out))
print("wrote " .. path)
