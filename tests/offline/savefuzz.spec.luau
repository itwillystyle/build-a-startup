--[[ savefuzz.spec.luau -- throw broken saves at the save loader's sanitizers (13 Oct 2026)

	From the Anthropic source-control article (13 Oct): fuzzing found what the hand-
	written cases did not. A save is the one input a player can corrupt (an old
	version, a half-written key, an exploit) and a bad value there costs someone their
	progress, so every PURE function SaveLoad passes raw saved data through gets random
	garbage here, and rules that must hold for ANY input:

	  StaffStats.clampLevel   always an integer 0..MAX_LEVEL, never NaN, never errors
	  StaffStats.validPin     always a boolean; true only for "" or a real room type
	  StaffStats.fixIds       n ids, all distinct whole numbers > 0; the counter is at
	                          least every id; loading its own output again changes nothing
	  Momentum.sanitize       always an integer 0..Momentum.MAX
	  Journey.cleanFlags/Tips only known keys, only `true`, never errors

	NOT covered: SaveLoad's own local clampInt and the parts of applySave that build
	the world (not pure; savecontract.spec explains). Seeded, so a failure repeats:
	the message prints the seed and the input. ]]
local S = require("../../src/ReplicatedStorage/StaffStats")
local Mom = require("../../src/ServerScriptService/Momentum")
local J = require("../../src/ServerScriptService/Journey")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local SEED = 20261013
local N = 4000

-- Lune has no Roblox `Random`: a small seeded generator with the same two calls
-- (Park-Miller minimal standard, exact in doubles)
local Random = {}
Random.__index = Random
function Random.new(seed) return setmetatable({ s = (seed % 2147483646) + 1 }, Random) end
function Random:next()
	self.s = (self.s * 16807) % 2147483647
	return self.s / 2147483647
end
function Random:NextInteger(a, b) return a + math.floor(self:next() * (b - a + 1)) end
function Random:NextNumber(a, b) return a + self:next() * (b - a) end

-- ---------------------------------------------------------------- the garbage
local NAN = 0 / 0
local ATOMS = {
	0, 1, -1, 0.5, -0.5, 1.5, 29.9, 30, 31, 100, 1e9, 1e9 + 1, 1e12, -1e12, math.huge, -math.huge, NAN,
	"", "0", "1", "30", "1e9", "-5", "nan", "abc", "hq", "cafe", "servers", "board", "HQ", " hq",
	"launch", "bag", "LAUNCH",   -- real tip ids (and a near miss), or cleanTips only ever sees junk
	true, false,
}
local function fmt(v, depth)
	depth = depth or 0
	if type(v) == "table" then
		if depth > 2 then return "{...}" end
		local parts = {}
		for k, x in v do
			table.insert(parts, tostring(k) .. "=" .. fmt(x, depth + 1))
			if #parts > 6 then table.insert(parts, "...") break end
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	if type(v) == "string" then return ("%q"):format(v) end
	return tostring(v)
end

local function gen(rng, depth)
	depth = depth or 0
	local r = rng:NextInteger(1, 10)
	if r <= 5 or depth >= 2 then return ATOMS[rng:NextInteger(1, #ATOMS)] end
	if r == 6 then return nil end
	if r == 7 then return rng:NextNumber(-1e6, 1e6) end
	local t = {}
	local len = rng:NextInteger(0, 8)
	for i = 1, len do t[i] = gen(rng, depth + 1) end
	if r >= 9 then   -- a dict part too: string keys, some of them real flag / tip names
		for _ = 1, rng:NextInteger(0, 4) do
			local keys = { "drove", "res", "launched", "genius", "seriesA", "evil", "1", "__index" }
			t[keys[rng:NextInteger(1, #keys)]] = gen(rng, depth + 1)
		end
	end
	return t
end

local function isInt(v) return type(v) == "number" and v == v and v == math.floor(v) and v ~= math.huge and v ~= -math.huge end

-- run `prop(input)` N times; prop errors (assert) to fail
local function fuzz(label, make, prop)
	local rng = Random.new(SEED)
	for i = 1, N do
		local input = make(rng)
		local ok, err = pcall(prop, input)
		if not ok then
			error(("%s: case %d (seed %d) input %s: %s"):format(label, i, SEED, fmt(input), tostring(err)), 0)
		end
	end
end

-- ---------------------------------------------------------------- StaffStats
test("clampLevel: any saved value becomes a whole level 0..MAX_LEVEL", function()
	fuzz("clampLevel", function(rng) return gen(rng) end, function(v)
		local out = S.clampLevel(v)
		assert(isInt(out) and out >= 0 and out <= S.MAX_LEVEL, "got " .. tostring(out))
	end)
end)

test("validPin: a boolean, and true only for no pin or a real room type", function()
	fuzz("validPin", function(rng) return gen(rng) end, function(v)
		local out = S.validPin(v)
		assert(type(out) == "boolean", "not a boolean: " .. tostring(out))
		if out then assert(v == "" or (type(v) == "string" and S.PINS[v] == true), "accepted " .. fmt(v)) end
	end)
end)

test("fixIds: n distinct whole ids, the counter covers them, and a reload changes nothing", function()
	fuzz("fixIds", function(rng)
		return { saved = gen(rng), nsid = gen(rng), n = rng:NextInteger(0, 200) }
	end, function(c)
		local ids, top = S.fixIds(c.saved, c.nsid, c.n)
		assert(type(ids) == "table" and isInt(top) and top >= 0, "bad return: top " .. tostring(top))
		local seen = {}
		for i = 1, c.n do
			local v = ids[i]
			assert(isInt(v) and v > 0, ("id %d is %s"):format(i, tostring(v)))
			assert(not seen[v], ("id %s given twice"):format(tostring(v)))
			seen[v] = true
			assert(v <= top, ("id %s above the counter %s: the next hire could reuse it"):format(tostring(v), tostring(top)))
		end
		assert(ids[c.n + 1] == nil, "more ids than staff")
		-- a GOOD saved id stays put (a fixIds that renumbered everyone passed the rules above;
		-- review of #52): the first time a whole number 1..1e9 appears, it is kept
		if type(c.saved) == "table" then
			local first = {}
			for i = 1, c.n do
				local v = tonumber(c.saved[i])
				if v and v == v and v >= 1 and v <= 1e9 and v == math.floor(v) and not first[v] then
					first[v] = true
					assert(ids[i] == v, ("valid saved id %s at %d was renumbered to %s"):format(tostring(v), i, tostring(ids[i])))
				end
			end
		end
		local ids2, top2 = S.fixIds(ids, top, c.n)
		for i = 1, c.n do assert(ids2[i] == ids[i], ("reload moved id %d: %s -> %s"):format(i, tostring(ids[i]), tostring(ids2[i]))) end
		assert(top2 == top, ("reload moved the counter: %s -> %s"):format(tostring(top), tostring(top2)))
	end)
end)

-- ---------------------------------------------------------------- Momentum
test("Momentum.sanitize: any saved value becomes whole points 0..MAX", function()
	fuzz("Momentum.sanitize", function(rng) return gen(rng) end, function(v)
		local out = Mom.sanitize(v)
		assert(isInt(out) and out >= 0 and out <= Mom.MAX, "got " .. tostring(out))
	end)
end)

-- ---------------------------------------------------------------- Journey
local FLAG = {}
for _, k in J.FLAGS do FLAG[k] = true end

test("Journey.cleanFlags: only known flags, only true", function()
	fuzz("cleanFlags", function(rng) return gen(rng) end, function(v)
		local out = J.cleanFlags(v)
		assert(type(out) == "table", "not a table")
		for k, x in out do
			assert(FLAG[k], "unknown flag kept: " .. tostring(k))
			assert(x == true, ("flag %s is %s"):format(tostring(k), tostring(x)))
		end
	end)
end)

test("Journey.cleanTips: only real tip ids, only true; tipList returns them as strings", function()
	fuzz("cleanTips", function(rng) return gen(rng) end, function(v)
		local out = J.cleanTips(v)
		assert(type(out) == "table", "not a table")
		for k, x in out do
			assert(type(k) == "string" and J.tipById(k), "unknown tip kept: " .. tostring(k))
			assert(x == true, "not true")
		end
		for _, id in J.tipList(out) do assert(out[id], "tipList invented " .. tostring(id)) end
	end)
end)

-- ---------------------------------------------------------------- the fuzzer itself
test("the fuzzer reaches the nasty cases (NaN, infinities, strings, nested tables, nil) and real tip ids", function()
	local rng = Random.new(SEED)
	local saw = { nan = false, inf = false, str = false, nested = false, nilv = false, tipKept = false }
	for _ = 1, N do
		local v = gen(rng)
		if v ~= v then saw.nan = true end
		if v == math.huge or v == -math.huge then saw.inf = true end
		if type(v) == "string" then saw.str = true end
		if v == nil then saw.nilv = true end
		if type(v) == "table" then
			for _, x in v do if type(x) == "table" then saw.nested = true end end
			if next(J.cleanTips(v)) ~= nil then saw.tipKept = true end
		end
	end
	for k, ok in saw do assert(ok, "the generator never produced: " .. k) end
end)

return T
