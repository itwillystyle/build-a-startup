--[[ ErrorBook (26 Oct 2026, safety net part 1): the live error log's rules. Pure.
	ErrorLog notes every server error (ScriptContext.Error) and every client report into a
	batch, and once a minute merges the batch into one DataStore record per UTC day
	("live/2026-10-26"; Studio writes "studio/..." so dev runs never pollute live). The
	doctor routine reads the last days back (ErrorLog.read) into its morning report.

	One bug is one SIGNATURE: side + message + first stack line, with player names and big
	numbers (ids, cash) folded, so a bug every player hits counts up instead of filling the
	record. Both a batch and a record keep at most MAX_SIGS kinds; the rest are counted as
	dropped. tests/offline/errorbook.spec.luau ]]

local ErrorBook = {}

ErrorBook.STORE = "SVErrors_v1"
ErrorBook.MAX_SIGS = 60       -- kinds kept per day record (the most frequent)
ErrorBook.SAMPLE_LEN = 240    -- characters of message + stack kept as the example
ErrorBook.PER_MIN = 10        -- client reports one player may send a minute

local function fold(s)
	s = tostring(s or ""):gsub("%c", " ")
	s = s:gsub("Players%.[^%.%s]+%.", "Players.<p>.")   -- whose PlayerScripts
	s = s:gsub("%d%d%d%d%d+", "#")                       -- ids, cash; line numbers (<= 4 digits) stay
	return s
end

function ErrorBook.signature(side, message, stack)
	local first = tostring(stack or ""):match("^[^\n]*") or ""
	return (tostring(side) .. "|" .. fold(message):sub(1, 160) .. "|" .. fold(first):sub(1, 120))
end

function ErrorBook.batch()
	return { sigs = {}, count = 0, dropped = 0 }
end

-- one error into a batch; past MAX_SIGS * 2 kinds a new kind is only counted as dropped
function ErrorBook.note(b, side, message, stack, now)
	local sig = ErrorBook.signature(side, message, stack)
	local e = b.sigs[sig]
	if not e then
		if b.count >= ErrorBook.MAX_SIGS * 2 then
			b.dropped += 1
			return nil
		end
		local sample = (tostring(message or "") .. " | " .. tostring(stack or "")):gsub("%c", " "):sub(1, ErrorBook.SAMPLE_LEN)
		e = { n = 0, side = side, sample = sample, first = now, last = now }
		b.sigs[sig] = e
		b.count += 1
	end
	e.n += 1
	e.last = now
	return sig
end

-- a batch whose write failed, folded into the next one under the same signatures
function ErrorBook.absorb(into, from)
	for sig, e in from.sigs do
		local o = into.sigs[sig]
		if o then
			o.n += e.n
			o.first = math.min(o.first, e.first)
			o.last = math.max(o.last, e.last)
		elseif into.count < ErrorBook.MAX_SIGS * 2 then
			into.sigs[sig] = e
			into.count += 1
		else
			into.dropped += e.n
		end
	end
	into.dropped += from.dropped or 0
end

-- the stored day record plus a batch -> the new record (UpdateAsync's transform: never errors)
function ErrorBook.merge(old, b, version, now)
	local rec = { sigs = {}, total = 0, dropped = 0 }
	if type(old) == "table" then
		rec.total = tonumber(old.total) or 0
		rec.dropped = tonumber(old.dropped) or 0
		if type(old.sigs) == "table" then
			for sig, o in old.sigs do
				if type(sig) == "string" and type(o) == "table" and tonumber(o.n) then rec.sigs[sig] = o end
			end
		end
	end
	for sig, e in b.sigs do
		local o = rec.sigs[sig]
		if o then
			o.n = (tonumber(o.n) or 0) + e.n
			o.last = math.max(tonumber(o.last) or 0, e.last)
			o.v = version
		else
			rec.sigs[sig] = { n = e.n, side = e.side, sample = e.sample, first = e.first, last = e.last, v0 = version, v = version }
		end
		rec.total += e.n
	end
	rec.dropped += b.dropped or 0
	local kinds = {}
	for sig, o in rec.sigs do table.insert(kinds, { sig = sig, n = o.n }) end
	if #kinds > ErrorBook.MAX_SIGS then
		table.sort(kinds, function(a, c) return a.n > c.n end)
		for i = ErrorBook.MAX_SIGS + 1, #kinds do
			rec.dropped += kinds[i].n
			rec.sigs[kinds[i].sig] = nil
		end
	end
	rec.v, rec.updated = version, now
	return rec
end

-- a record -> its kinds, most frequent first: { {sig, n, side, sample, first, last, v0, v} }
function ErrorBook.summary(rec)
	local out = {}
	if type(rec) ~= "table" or type(rec.sigs) ~= "table" then return out end
	for sig, o in rec.sigs do
		table.insert(out, { sig = sig, n = o.n, side = o.side, sample = o.sample, first = o.first, last = o.last, v0 = o.v0, v = o.v })
	end
	table.sort(out, function(a, b) return a.n > b.n end)
	return out
end

-- a per-player token bucket: PER_MIN reports a minute (now = os.clock())
function ErrorBook.allow(bucket, now)
	if not bucket.t0 or now - bucket.t0 >= 60 then bucket.t0, bucket.n = now, 0 end
	if bucket.n >= ErrorBook.PER_MIN then return false end
	bucket.n += 1
	return true
end

function ErrorBook.key(t, studio)
	return (studio and "studio/" or "live/") .. os.date("!%Y-%m-%d", t)
end

return ErrorBook
