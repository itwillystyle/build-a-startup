--[[ playtest.spec.luau -- reading a screen recording against the logs, checked offline.

	`bas playtest` decides which recordings are playtests of THIS game and puts what
	the game printed on the video's clock. Each rule is tested both ways: the 10 Oct
	night (live game in the Roblox app, place 105976291385232) is found, another game
	and a recording with nothing running are not. Log lines are in the exact shape
	Roblox writes them (copied from the 10 Oct logs). ]]
local P = require("../../tools/playtest_lib")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local function at(hms, rest) return ("2026-10-10T%s.962Z,2.96,83ac,6 %s"):format(hms, rest) end
local function app(hms, msg) return at(hms, "[FLog::Output] " .. msg) end
local function appErr(hms, msg) return at(hms, "[FLog::Error] " .. msg) end
local function studio(hms, msg) return ("2026-10-10T%s.540Z,112.5,5a90,6,Info [FLog::CreatorOutput] %s"):format(hms, msg) end
local function studioErr(hms, msg) return ("2026-10-10T%s.540Z,112.5,5a90,6,Error [FLog::CreatorError] %s"):format(hms, msg) end

-- 02:28:53 EDT = 06:28:53 UTC
local EDT = -4 * 3600
local REC = P.toUnix(P.stamp("2026-10-10 02-28-53.mp4"), EDT)

test("a recording's name is its local start time, turned into UTC", function()
	local st = P.stamp("2026-10-10 02-28-53.mp4")
	assert(st and st.hour == 2 and st.min == 28 and st.sec == 53, "did not read OBS's file name")
	assert(P.stamp("clip.mp4") == nil, "a name with no date was read as one")
	local live = P.toUnix(P.stamp("2026-10-10 06-28-53.mp4"), 0)
	assert(REC == live, ("02:28:53 EDT should be 06:28:53 UTC (off by %d s)"):format(REC - live))
end)

test("the Roblox app log: our live game is a playtest, another game is not", function()
	local log = table.concat({
		app("06:25:07", "Settings Date header was Sat, 10 Oct 2026 06:25:07 GMT"),
		app("06:25:09", "! Joining game '3737d8f9' place 105976291385232 at 10.37.7.147"),
		app("06:29:07", "Settings Date header was Sat, 10 Oct 2026 06:29:08 GMT"),
		app("06:38:19", "AppPlatformQoSEmergencyHandler was destroyed."),
	}, "\n")
	local s = P.playing(P.sessions(log, "Player"), REC, REC + 24)
	assert(s and s.where == "the live game", "missed the live game being played while he filmed")
	assert(REC - s.from == 224, ("joined 3:44 before the recording, got %d s"):format(REC - s.from))

	local other = app("06:25:09", "! Joining game 'a192ad14' place 127862272907196 at 10.37.4.6") .. "\n" .. app("06:38:19", "bye")
	assert(P.playing(P.sessions(other, "Player"), REC, REC + 24) == nil, "another game counted as a playtest")
	local before = app("05:00:00", "! Joining game 'x' place 105976291385232 at 1.2.3.4") .. "\n" .. app("05:10:00", "bye")
	assert(P.playing(P.sessions(before, "Player"), REC, REC + 24) == nil, "a session that ended an hour earlier counted")
end)

test("a Studio log: Play runs from 'Player added' to 'Player leaving'", function()
	local log = table.concat({
		studio("06:20:00", "Player 1688749216 added"),
		studio("06:22:00", "Player 1688749216 leaving"),
		studio("06:28:00", "Player 1688749216 added"),
		studio("06:31:00", "Player 1688749216 leaving"),
	}, "\n")
	local s = P.playing(P.sessions(log, "Studio"), REC, REC + 24)
	assert(s and s.where == "Studio Play" and s.from == REC - 53, "missed the Play run he filmed")
	assert(P.playing(P.sessions(log, "Studio"), REC + 600, REC + 620) == nil, "time after Play stopped counted as Play")
end)

test("the game's lines land on the video's clock; Studio chatter and the app's engine lines do not", function()
	local log = table.concat({
		studio("06:20:00", "[SV] long before: not in the window"),
		studio("06:28:45", "[SV] TalentDrop: candidate spawned"),
		studioErr("06:29:01", "ServerScriptService.TalentDrop:412: attempt to index nil"),
		studioErr("06:29:01", "ServerScriptService.TalentDrop:412: attempt to index nil"),
		("2026-10-10T06:29:02.000Z,1.0,5a90,6,Warning [FLog::StudioPluginRelay] hideForRestoreLater"),
	}, "\n")
	local w = P.window(log, REC, REC + 24, "Studio")
	assert(#w == 2, ("want 2 lines (the spawn, the error folded x2), got %d"):format(#w))
	assert(w[1].t == -8 and w[2].t == 8, ("times on the video's clock: want -8 and 8, got %d and %d"):format(w[1].t, w[2].t))
	assert(w[2].level == "ERROR" and w[2].n == 2, "the repeated error was not folded into one line x2")

	local appLog = app("06:29:07", "Settings Date header was Sat") .. "\n" .. appErr("06:29:08", 'Asset (Image) "rbxthumb://type=AvatarHeadShot&id=&w=48" load failed')
	local a = P.window(appLog, REC, REC + 24, "Player")
	assert(#a == 1 and a[1].level == "ERROR", "the app log should give its errors only")
end)

test("frames: one a second, fewer on a long recording; sheets of six", function()
	assert(P.step(24) == 1 and P.step(240) == 1, "a short recording should get a frame a second")
	assert(P.step(600) == 3, "a 10-minute recording should get a frame every 3 s (200 frames)")
	local sh = P.sheets(24, 1)
	assert(#sh == 4 and sh[4].from == 18 and sh[4].to == 23, "24 s at 1 fps is 4 sheets, the last 0:18 to 0:23")
	local odd = P.sheets(7.4, 1)
	assert(#odd == 2 and odd[2].from == 6 and odd[2].to == 7, "7.4 s is 8 frames: a full sheet and one of 2")
	assert(P.clock(89) == "1:29" and P.clock(-8) == "-0:08", "clock text")
end)

test("notes.md says when it is NOT a playtest, and leaves the findings table empty", function()
	local base = { name = "x.mp4", duration = 24, startUnix = REC, startLocal = "Sat", step = 1, sheets = P.sheets(24, 1), lines = {}, speech = {} }
	local md = P.notes(base)
	assert(md:find("Probably NOT a playtest", 1, true), "an unplayed recording was not called out")
	assert(md:find("| t | what I see | feature page | severity | repro | guard |", 1, true), "no findings table")
	base.session = { from = REC - 224, where = "the live game" }
	md = P.notes(base)
	assert(md:find("Playing: **the live game**, joined 3:44 before", 1, true), "the session line is wrong")
	assert(not md:find("NOT a playtest", 1, true), "a real playtest was called not one")
end)

return T
