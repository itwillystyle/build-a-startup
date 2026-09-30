-- wafer.spec.luau: the Wafers plan (WaferPlan.lua) against the sim's golden file.
-- The sim (sim/wafer_plan.py) owns the numbers; this proves the game module says the same.
local W = require("../../src/ServerScriptService/WaferPlan")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local G = serde.decode("json", fs.readFile("tests/offline/wafer_golden.json"))

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end
local function near(a, b) return math.abs(a - b) <= 1e-9 * math.max(1, math.abs(b)) end

test("100 pieces, each the sim's kind, wafer, storey and segment", function()
	assert(#W.PIECES == 100 and #G.pieces == 100, "100 pieces")
	for i, g in ipairs(G.pieces) do
		local p = W.PIECES[i]
		assert(p.level == g.level and p.kind == g.kind and p.wafer == g.wafer and p.storey == g.storey and p.seg == g.seg,
			("piece %d: %s w%d st%d seg%d vs %s w%d st%d seg%d"):format(i, p.kind, p.wafer, p.storey, p.seg, g.kind, g.wafer, g.storey, g.seg))
	end
end)

test("prices, money and staff caps match the sim's tables", function()
	assert(W.REBUILD == G.rebuild, "rebuild share")
	for L = 1, 100 do
		assert(W.basePrice(L) == G.base[L], ("base price L%d: %s vs %s"):format(L, W.basePrice(L), G.base[L]))
		assert(near(W.multAt(L), G.mult[L]), ("money x L%d"):format(L))
		assert(W.capAt(L) == G.cap[L], ("staff cap L%d"):format(L))
	end
end)

test("departments allowed and homes needed, per level", function()
	for L = 1, 100 do
		local a, g = W.allowed(L), G.allowed[L]
		assert(#a == #g, ("allowed L%d: %d vs %d"):format(L, #a, #g))
		for i = 1, #g do assert(a[i] == g[i], ("allowed L%d #%d: %s vs %s"):format(L, i, a[i], g[i])) end
		assert(W.aptRequired(L) == G.apt[L], ("homes needed L%d"):format(L))
	end
end)

test("the guide's department pick matches the sim at every segment", function()
	for _, s in ipairs(G.recommend) do
		local pick = W.recommend(s.level, s.counts, s.free)
		assert(pick == s.pick, ("L%d free %d: %s vs %s"):format(s.level, s.free, pick, s.pick))
	end
end)

test("department effects match the sim", function()
	for i, e in ipairs(G.effects) do
		local got = W.effects(e.counts)
		assert(near(got.quality, e.quality) and near(got.morale, e.morale), ("effects case %d"):format(i))
		assert(got.compute == e.compute and got.labs == e.labs and got.board == e.board, ("counts case %d"):format(i))
	end
end)

test("price: the company's scale, and 25% at or below your record", function()
	for _, c in ipairs(G.prices) do
		local got = W.price(c.level, c.scale, c.record)
		assert(got == c.price, ("L%d scale %s record %d: %s vs %s"):format(c.level, c.scale, c.record, got, c.price))
	end
end)

test("a rebuild buys the rest of a storey in one tap (never past the record)", function()
	for _, b in ipairs(G.batches) do
		assert(W.rebuildLast(b.level, b.record) == b.last, ("L%d record %d: last %d vs %d"):format(b.level, b.record, W.rebuildLast(b.level, b.record), b.last))
	end
end)

test("the price of one BUILD tap matches the sim (a storey below the record)", function()
	for _, b in ipairs(G.batches) do
		assert(W.batchPrice(b.level, b.scale, b.record) == b.price, ("L%d record %d: %s vs %s"):format(b.level, b.record, W.batchPrice(b.level, b.scale, b.record), b.price))
	end
end)

test("blueprint: 18, 30, 43 ... 100, and 100 after that", function()
	for n = 0, 9 do
		assert(W.blueprint(n) == G.blueprint[math.min(n + 1, #G.blueprint)], ("company %d"):format(n + 1))
	end
	assert(W.blueprint(-1) == 18, "never below the first blueprint")
end)

return T
