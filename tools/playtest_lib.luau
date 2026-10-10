--[[ playtest_lib -- the pure half of `bas playtest` (10 Oct 2026).

	His screen recording of 10 Oct found the two worst bugs of the week (no drop-off,
	sinking through the park) in 23 seconds. No check we had saw either. This makes a
	recording reviewable the same way every time: time-stamped contact sheets, what
	he said, and what the game printed WHILE he was filming, on the video's clock.

	No fs, no process: names, numbers and log text in, tables and markdown out, so
	tests/offline/playtest.spec.luau can check it. bas.luau runs ffmpeg and whisper. ]]
local Health = require("./health_lib")

local P = {}

P.TILES = 6            -- a contact sheet is 3 x 2 frames
P.MAX_FRAMES = 240     -- a long recording gets a frame every few seconds, not 900 sheets
P.MARGIN = 15          -- seconds of log before the recording starts (what led up to it)

-- "2026-10-10 02-28-53.mp4" (OBS's default name: the LOCAL time recording started) -> parts or nil
function P.stamp(name)
	local y, mo, d, h, mi, s = name:match("(%d%d%d%d)%-(%d%d)%-(%d%d)[ _T](%d%d)%-(%d%d)%-(%d%d)")
	if not y then return nil end
	return { year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = tonumber(s) }
end

-- local parts + the machine's offset from UTC (seconds, e.g. -14400 for EDT) -> unix seconds
function P.toUnix(parts, offset)
	local iso = ("%04d-%02d-%02dT%02d:%02d:%02d"):format(parts.year, parts.month, parts.day, parts.hour, parts.min, parts.sec)
	return Health.isoToUnix(iso) - (offset or 0)
end

-- seconds between frames: 1, or more for a recording past MAX_FRAMES seconds
function P.step(duration)
	return math.max(1, math.ceil((duration or 0) / P.MAX_FRAMES))
end

-- 75 -> "1:15"; -4 -> "-0:04"
function P.clock(t)
	local sign = t < 0 and "-" or ""
	t = math.floor(math.abs(t) + 0.5)
	return ("%s%d:%02d"):format(sign, t // 60, t % 60)
end

-- which seconds of the video each sheet covers -> { { n, from, to } }
function P.sheets(duration, step)
	local frames = math.max(1, math.ceil(duration / step))
	local out = {}
	for n = 1, math.ceil(frames / P.TILES) do
		local first = (n - 1) * P.TILES
		local last = math.min(frames, n * P.TILES) - 1
		table.insert(out, { n = n, from = first * step, to = last * step })
	end
	return out
end

P.PLACES = { ["105976291385232"] = "the live game", ["104511165501086"] = "the TEST place" }

--[[ When was this game being played, per log? A Studio log: Play from "Player <id>
	added" to "Player <id> leaving". A Roblox app log: from "! Joining game ... place
	<id>" to the next join or the log's last line (the place says WHICH game: he plays
	other games too, and those are not playtests).
	-> { { from, to, where, ours } } (unix seconds) ]]
function P.sessions(text, kind)
	local out, open, lastUnix = {}, nil, nil
	local function close(at)
		if open then open.to = at; table.insert(out, open); open = nil end
	end
	for line in text:gmatch("[^\r\n]+") do
		local p = Health.parseLine(line)
		if p then
			lastUnix = p.unix
			if kind == "Studio" then
				if p.msg:match("^Player %d+ added") then
					close(p.unix)
					open = { from = p.unix, where = "Studio Play", ours = true }
				elseif p.msg:match("^Player %d+ leaving") then
					close(p.unix)
				end
			else
				local place = p.msg:match("^! Joining game '[^']*' place (%d+)")
				if place then
					close(p.unix)
					open = { from = p.unix, where = P.PLACES[place] or ("another game (place " .. place .. ")"), ours = P.PLACES[place] ~= nil }
				end
			end
		end
	end
	close(lastUnix)
	return out
end

-- the session of OUR game that overlaps [from, to], or nil
function P.playing(sessions, from, to)
	for _, s in sessions do
		if s.ours and s.from <= to and s.to >= from then return s end
	end
	return nil
end

-- the channels the GAME writes to. Studio logs carry its prints; the Roblox app's log
-- carries only engine chatter there, so from it only errors (a failed image, a crash) count
local GAME = {
	Studio = { ["FLog::CreatorOutput"] = "out", ["FLog::CreatorWarning"] = "warn", ["FLog::CreatorError"] = "ERROR" },
	Player = { ["FLog::Error"] = "ERROR" },
}

--[[ The game's lines in a log between `from` and `to` (unix), on the video's clock.
	-> { { t, level, msg, n } } where t = seconds after the recording started (negative
	= before) and n counts identical lines in a row, folded into one. ]]
function P.window(text, startUnix, endUnix, kind, margin)
	local out = {}
	local from, to = startUnix - (margin or P.MARGIN), endUnix + 1
	local channels = GAME[kind or "Studio"] or GAME.Studio
	for line in text:gmatch("[^\r\n]+") do
		local p = Health.parseLine(line)
		local level = p and channels[p.channel]
		if level and p.unix >= from and p.unix <= to and not Health.isNoise(p.msg) then
			local msg = p.msg:sub(1, 220)
			local last = out[#out]
			if last and last.msg == msg and last.level == level then
				last.n += 1
			else
				table.insert(out, { t = p.unix - startUnix, level = level, msg = msg, n = 1 })
			end
		end
	end
	return out
end

--[[ notes.md: everything the reviewer needs on one page, and the findings table to fill.
	info = { name, duration, startUnix, startLocal, step, sheets, lines, speech, logs } ]]
function P.notes(info)
	local md = {}
	local function add(s) table.insert(md, s) end
	add(("# Playtest: %s"):format(info.name))
	add("")
	add(("%s long · started %s local · a frame every %d s · %d sheet(s)"):format(
		P.clock(info.duration), info.startLocal or "?", info.step, #info.sheets))
	add("")
	if info.session then
		add(("Playing: **%s**, joined %s before the recording started."):format(info.session.where, P.clock(info.startUnix - info.session.from)))
	else
		add("Playing: **nothing of ours** (no Studio Play or Roblox app session of this game overlaps). Probably NOT a playtest.")
	end
	add("")
	add("## Sheets (each frame has its time burned in, top left)")
	for _, s in info.sheets do
		add(("- `sheet_%02d.jpg`  %s to %s"):format(s.n, P.clock(s.from), P.clock(s.to)))
	end
	add("")
	add("## What he said")
	if info.speech and #info.speech > 0 then
		for _, l in info.speech do add("- " .. l) end
	else
		add("- (no speech found)")
	end
	add("")
	add(("## What the game printed while he filmed (from %d s before)"):format(P.MARGIN))
	if #info.lines == 0 then
		add("- nothing (the Roblox app logs only errors; Studio Play logs every print)")
	else
		local errors, warns = 0, 0
		for _, l in info.lines do
			if l.level == "ERROR" then errors += 1 elseif l.level == "warn" then warns += 1 end
		end
		add(("- %d line(s): %d error(s), %d warning(s). From: %s"):format(#info.lines, errors, warns, table.concat(info.logs or {}, ", ")))
		for _, l in info.lines do
			add(("- `%s` %s%s %s"):format(P.clock(l.t), l.level == "out" and "" or (l.level .. " "), l.msg, l.n > 1 and (" (x%d)"):format(l.n) or ""))
		end
	end
	add("")
	add("## Findings")
	add("One row per thing that is wrong or feels wrong. Severity: BLOCKER (stops the loop),")
	add("BUG (wrong, playable), FEEL (works, feels bad). Guard = the check that would have")
	add("caught it, so it cannot come back unseen (a test, a WorldHealth rule, a smoke step).")
	add("")
	add("| t | what I see | feature page | severity | repro | guard |")
	add("|---|---|---|---|---|---|")
	add("")
	add("## Verdict")
	add("- reviewed: (no)")
	return table.concat(md, "\n") .. "\n"
end

return P
