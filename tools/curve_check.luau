local P = require("../src/ServerScriptService/Progression")
local SPIN_BASE = 4000000
local spin1 = P.spinCost(0, SPIN_BASE)
print(("spin-off 1 costs $%d"):format(spin1))
print("")
print("home prices as a share of the spin-off they compete with:")
for _, t in ipairs(P.APARTMENTS) do
	print(("  %-10s $%-9d = %5.1f%% of a spin-off   gateHQ=%s"):format(
		t.name, t.price, t.price / spin1 * 100, tostring(t.gateHQ)))
end
print("")
print("at ~$3M in 20 min, what is already affordable:")
local cash = 3000000
for _, t in ipairs(P.APARTMENTS) do
	print(("  %-10s %s"):format(t.name, cash >= t.price and "AFFORDABLE" or "out of reach"))
end
