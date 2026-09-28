--[[ The late-game loop table, from the SAME Progression code the game runs.
	From the game folder:  lune run tools/late_game
Model inputs (not game code): R5 = income at HQ 5 on the first loop (16,650/s, the
V3 sim's minute-60 median); climb = garage to HQ 5 (19.5 min on loop 0, never under
7.5 min: ~22 buys at a 20 s pace). ]]
local P = require("../src/ServerScriptService/Progression")
local E = require("../src/ServerScriptService/RoomEconomy")
local R5 = 16650
local BASE = E.SPINOFF_BASE
local function old(k) return math.floor(BASE * 2.5 ^ k) end
local function dur(sec)
	if sec >= 86400 * 365 then return ("%.0f yr"):format(sec / 86400 / 365) end
	if sec >= 86400 then return ("%.1f d"):format(sec / 86400) end
	if sec >= 3600 then return ("%.1f h"):format(sec / 3600) end
	return ("%.1f min"):format(sec / 60)
end
local function money(n)
	for _, u in { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } } do
		if n >= u[1] then return ("$%.1f%s"):format(n / u[1], u[2]) end
	end
	return "$" .. n
end
print("spin | mult | old price  old wait | new price  new wait | one night pays: none studio loft penthouse")
local tOld, tNew = 0, 0
for k = 0, P.SPIN_CAP do
	local rate = R5 * P.spinMult(k)
	local wOld, wNew = old(k) / rate, P.spinCost(k, BASE) / rate
	local cover = {}
	for apt = 0, 3 do
		local paid = P.offline(rate, 8 * 3600, apt, 0, P.spinCost(k, BASE), E.HQ_COST[2])
		table.insert(cover, ("%3.0f%%"):format(paid / P.spinCost(k, BASE) * 100))
	end
	if k < P.SPIN_CAP then
		local climb = (7.5 + 12 / P.spinMult(k)) * 60
		tOld += climb + wOld; tNew += climb + wNew
	end
	print(("%4d | x%4.1f | %9s  %8s | %9s  %8s | %s"):format(k, P.spinMult(k), money(old(k)), dur(wOld),
		money(P.spinCost(k, BASE)), dur(wNew), table.concat(cover, "  ")))
end
print(("play time to max prestige (20 spin-offs): old %s, new %s"):format(dur(tOld), dur(tNew)))
