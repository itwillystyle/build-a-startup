-- tests/home_spec.luau: apartments as home turf, the pure rules (Edit datamodel)
local mod = game:GetService("ServerScriptService"):FindFirstChild("Apartments")
if not mod then return "FAIL: ServerScriptService.Apartments missing" end
local clone = mod:Clone()
local ok, A = pcall(require, clone)
if not ok then clone:Destroy() return "FAIL: require " .. tostring(A) end
if type(A.offline) ~= "function" or type(A.ladder) ~= "function" then clone:Destroy() return "FAIL: Apartments.offline / ladder missing" end
local fails = {}
local function expect(c, msg) if not c then table.insert(fails, msg) end end

local HQ = { 0, 3750, 37500, 225000, 1500000 }
local function hqCost(l) return HQ[l] end

-- 1 the ladder: the next two steps, with the apartment each HQ level needs
local n, a = A.ladder(2, 0, hqCost, 4e6)
expect(n == 37500 + 20000 and a == 225000 + 150000, "1a HQ 2, no apartment: HQ3+Studio, then HQ4+Loft")
n, a = A.ladder(2, 1, hqCost, 4e6)
expect(n == 37500 and a == 375000, "1b a Studio already owned is not charged again")
n, a = A.ladder(4, 3, hqCost, 4e6)
expect(n == 1500000 and a == 4e6, "1c HQ 4 with a Penthouse: HQ 5, then the spin-off")
n, a = A.ladder(5, 3, hqCost, 39062500)
expect(n == 39062500 and a == 3750, "1d HQ 5: the spin-off, then HQ 2 again")

-- 2 the payout
local H = 3600
local today = function(rate, away) return math.floor(math.min(rate * 0.25 * math.min(away, 8 * H), rate * 600)) end
expect(A.offline(1000, 8 * H, 0, 0, 5e6, 5e6) == today(1000, 8 * H), "2a no apartment = today")
expect(A.offline(1000, 8 * H, 3, 0, 50000, 1e6) == 600000, "2b a small next step never pays below today")
expect(A.offline(1000, 8 * H, 3, 0, 3e6, 3750) == 3e6, "2c a Penthouse night can cover a whole spin-off")
expect(A.offline(1000, 2 * H, 3, 0, 3e6, 3750) == 1800000, "2d two hours away pays less than eight")
expect(A.offline(1000, 8 * H, 1, 0, 3e6, 3750) == 1800000, "2e a Studio's window is 2 h")
local o = A.offline(10000, 8 * H, 3, 2e6, 1e6, 1.5e6)
expect(2e6 + o < 1e6 + 1.5e6, "2f never enough to buy two steps")
expect(A.offline(1000, -50, 3, 0, 3e6, 3750) == 0 and A.offline(0, 8 * H, 3, 0, 3e6, 3750) == 0, "2g no time away / no income = 0")

-- 3 property check over 3000 random returns
local rng = Random.new(42)
local bad = 0
for _ = 1, 3000 do
	local rate = rng:NextInteger(1, 200000)
	local away = rng:NextInteger(0, 48 * H)
	local apt = rng:NextInteger(0, 3)
	local nxt = rng:NextInteger(1000, 5e8)
	local aft = rng:NextInteger(1000, 5e8)
	local cash = rng:NextInteger(0, nxt - 1)                  -- you could not already afford it
	local v = A.offline(rate, away, apt, cash, nxt, aft)
	local floor = math.min(today(rate, away), math.max(0, nxt + aft - cash - 1))
	if v < 0 or cash + v >= nxt + aft or v < floor - 1 then bad += 1 end
end
expect(bad == 0, "3 property: >= today (unless that buys two steps), never two steps, never negative (" .. bad .. " bad)")

clone:Destroy()
return #fails == 0 and "PASS 3 groups" or ("FAIL " .. #fails .. "\n" .. table.concat(fails, "\n"))
