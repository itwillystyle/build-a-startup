--[[ CoreConfig: SiliconCore's tuning constants.
Moved out of SiliconCore on 28 Sep 2026 (v4.2): the script was at 196 of
Luau's 200 top-level locals. Pure data, no requires. SiliconCore reads these
as CFG.NAME. Values that depend on RoomEconomy or CampusArch (SPINOFF_BASE,
WING_MAX_LEVEL, SLOT_LOCAL, ...) stay in SiliconCore, and SiliconCore may
overwrite fields at load (the V3 HQ costs). The spin-off curve lives in
Progression.lua (v4.3). ]]

local START_CASH = 0
local CODE_REWARD = 5
-- v4.3 WRITE CODE scales: a tap is worth this many seconds of income (never under
-- CODE_REWARD), and taps under 0.9 s apart build a combo (+10% each, up to +80%).
-- A flat $5 was nothing by HQ 2: his run stood still for minutes while saving.
local CODE_SECONDS = 0.18
local CODE_COMBO_STEP = 0.1
local CODE_COMBO_MAX = 8
local CLICKS_TO_SHIP = 3
local INTERN_RATE = 2
local GARAGE_DESKS = 1
local FLOOR = Color3.fromRGB(78, 76, 74)
local WALL = Color3.fromRGB(196, 190, 180)
local TRIM = Color3.fromRGB(52, 56, 66)
local ACCENT = Color3.fromRGB(90, 170, 255)
local GOOD = Color3.fromRGB(90, 210, 130)
local GOLD = Color3.fromRGB(255, 208, 70)
local BAD = Color3.fromRGB(255, 140, 140)
local ROLE_ORDER = { "engineer", "engineer", "designer", "sales", "engineer",
	"research", "designer", "recruiter" }
local ROOMS = {
	-- v2.8: blurbs say what the room does under the V3 economy (rooms come
	-- furnished; the old "(B)" and "unlocks KITCHEN" lines described build mode)
	{ id = "office", name = "OPEN OFFICE", cost = 100,
	  blurb = "Seats 2 more people", desks = 2,
	  color = Color3.fromRGB(206, 200, 190), accent = ACCENT },
	{ id = "servers", name = "SERVER ROOM", cost = 350,
	  blurb = "Bigger launch paydays", compute = 1,
	  color = Color3.fromRGB(70, 74, 86), accent = Color3.fromRGB(120, 240, 200) },
	{ id = "studio", name = "DESIGN STUDIO", cost = 800,
	  blurb = "+25% money for your company", quality = 0.25,
	  color = Color3.fromRGB(224, 196, 150), accent = Color3.fromRGB(255, 150, 190) },
	{ id = "cafe", name = "CAFETERIA", cost = 1500,
	  blurb = "+20% money, seats 4", morale = 0.20,
	  color = Color3.fromRGB(196, 150, 110), accent = GOLD },
}
local ROOM_BY_ID = {}
local HQ_LEVELS = {
	{ name = "GARAGE",         w = 36, d = 30, h = 14, cost = 0 },
	-- v4.0: the lots moved out to +-92 in v3.2, so the HQ can grow wider as it
	-- grows up (blender/hq2.py). Every level is a finished building.
	{ name = "STARTUP OFFICE", w = 56, d = 44, h = 20, cost = 2500 },
	{ name = "TECH HQ",        w = 72, d = 52, h = 28, cost = 25000 },
	{ name = "GLASS TOWER",    w = 84, d = 56, h = 44, cost = 150000 },
	{ name = "CAMPUS HQ",      w = 96, d = 56, h = 60, cost = 1000000 },
}
local HQ_MULT = { 1, 1.6, 2.6, 4.2, 7 }   -- revenue AND price multiplier per HQ level
local HIRE_BASE = 40
local HIRE_GROWTH = 1.3                   -- was 1.6: hire 20 cost $487K, hire 25 $5M
local WING_STEP = 0.5                     -- each wing already built raises the next by 50%
local FURNITURE_INFLATION = 0.08          -- per item already placed
local PAYDAY_SECONDS = 45                 -- a launch pays this many seconds of income, x spike
local MILESTONE_BASE = 10000
local MILESTONE_STEP = 0.02
local MILESTONE_MAX = 12
local ROMAN = { "", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX", "XXI" }
local WING_UP_BASE = 0.6               -- first level = 60% of the wing's build price
local WING_UP_GROWTH = 1.35            -- per level
local WING_LEVEL_AMOUNT = { office = 2, servers = 1, studio = 0.10, cafe = 0.08 }
local WING_LEVEL_TEXT = { office = "+4 seats", servers = "+1 compute", studio = "+10% revenue, +2 seats", cafe = "+8% output, +4 seats" }
local HIRE_GROWTH_LATE = 1.12          -- after HIRE_TAPER_AT people
local QUALITY_CAP = 1.5                -- studio levels stop paying past +150% revenue
local MORALE_CAP = 0.8                 -- cafeteria levels stop paying past +80% output
local HIRE_TAPER_AT = 12
local WING_UP_SECONDS = { 45, 90, 180, 360 }   -- Lv1->2 ... Lv4->5
local WORK_FIRST = 90                 -- work units for the first product
local WORK_GROWTH = 1.35              -- each product needs this much more
local LAUNCH_DURATION = 300           -- the spike decays to zero over this
local TIER_RATE = { 2, 4, 7, 12 }
local TIER_TITLE = { "Intern", "Junior", "Senior", "Lead" }
local PROMOTE_EVERY = 120
local TALENT = {
	{ name = "Regular", odds = 1,    mult = 1.0,  color = nil },
	{ name = "Skilled", odds = 5,    mult = 1.5,  color = Color3.fromRGB(90, 210, 130) },
	{ name = "Star",    odds = 25,   mult = 2.5,  color = Color3.fromRGB(90, 170, 255) },
	{ name = "Genius",  odds = 150,  mult = 5.0,  color = Color3.fromRGB(190, 120, 255) },
	{ name = "Unicorn", odds = 1491, mult = 12.0, color = Color3.fromRGB(255, 208, 70) },
}
local OFFER_EVERY = { 150, 240 }
local OFFER_MIN_TIER = 2
-- v2.3: an offer is INCOME TIME, nothing else. 2.5 minutes of the whole
-- company's rate, capped at a quarter of what you are worth (cash + valuation),
-- floored at 1 minute. The old tier x 480 s floor handed a garage player a
-- $5,760 offer against a $2,500 HQ; the same formula gave $40K against $12M.
local OFFER_INCOME_SECONDS = 150
local OFFER_MIN_SECONDS = 60
local OFFER_WORTH_CAP = 0.25
local ALUMNI_STEP = 0.05           -- +5% promotion speed per sale
local ALUMNI_CAP = 10              -- +50% max
local RIVALS = { "Buzzly Corp", "Cortex Labs", "Vaultly", "Zoomeats", "Skyfall Games", "Pulse Health",
	"Circlr", "Ledgerly", "Nudge AI", "Brainbox" }
local MARKETS = {
	-- v2.6.2: spike is 1.0 everywhere -- size is equal, SHAPE and FIT live in RoomEconomy.MARKET
	{ id = "social",  name = "SOCIAL",  blurb = "everyone shares it",   spike = 1.0,
	  names = { "Wavelength", "Buzzly", "Hangout", "Pingo", "Snapfeed", "Circlr" } },
	{ id = "games",   name = "GAMES",   blurb = "big spike, fades fast", spike = 1.0,
	  names = { "Blockquest", "Pocket Kart", "Dungeon Dash", "Skyfall", "Tiny Tycoon", "Brick Royale" } },
	{ id = "ai",      name = "AI",      blurb = "slow burn, long tail",  spike = 1.0,
	  names = { "Brainbox", "Autopilot", "Sage", "Cortex", "Whisper AI", "Nudge" } },
	{ id = "fintech", name = "FINTECH", blurb = "steady money",          spike = 1.0,
	  names = { "Coinjar", "Ledgerly", "Payflow", "Vaultly", "Splitwise Jr", "Tabby" } },
	{ id = "health",  name = "HEALTH",  blurb = "does good, pays fair",  spike = 1.0,
	  names = { "Stepcount", "Sleepwell", "Hydrate", "Pulse", "Mindful", "FitBuddy" } },
	{ id = "delivery", name = "DELIVERY", blurb = "everyone orders once", spike = 1.0,
	  names = { "Zoomeats", "Dropbox Jr", "Snackr", "Quickcart", "Doordrop", "Fetch" } },
}
local IPO_AT = 250000
local RIVAL_EVERY = { 120, 200 }       -- seconds between rival launches
local PRESSURE_SECONDS = 60            -- how long a rival launch keeps biting
local SHARE_FLOOR = 0.5
local SHARE_DECAY = 0.004              -- per second under pressure (60s = -24%)
local PUBLIC_RIVALS = {
	{ name = "Cortex Labs",   ticker = "CRTX", base = 260000 },
	{ name = "Vaultly",       ticker = "VLTY", base = 330000 },
	{ name = "Zoomeats",      ticker = "ZOOM", base = 410000 },
	{ name = "Skyfall Games", ticker = "SKYF", base = 520000 },
	{ name = "Brainbox",      ticker = "BRNX", base = 680000 },
}
local RIVAL_GROWTH = 1.02              -- per minute of server uptime
local RIVAL_CAP_MULT = 1.2             -- never more than this x the best human
local SLOT_W, SLOT_D = 28, 24
local ROAD_Z = 0

--[[ THE RING (v9). The six plots used to sit in two rows of three along a
straight road, which meant no plot faced any other and the middle of the map
was a carriageway. They now stand on a ring facing a shared centre, with the
central park inside it (CampusHub builds the park and the two ring roads).

Everything else in the game is PLOT-LOCAL -- plot.g(x, y, z) is
pivot * CFrame.new(x, y, z), and every building, pad, door and camera is
written in those coordinates -- so moving the campus is these six CFrames and
nothing else. That is the whole reason this was affordable.

FRONT IS LOCAL +Z, not LookVector. Downtown.lua and CampusArch both use that
convention (a plot's door, sign and forecourt are at positive local z). For a
plot at angle `a` on the ring, local +Z must point at the centre:

    after CFrame.Angles(0, yaw, 0), local +Z is (sin yaw, 0, cos yaw)
    inward is (-cos a, 0, -sin a)
    so  yaw = atan2(-cos a, -sin a)

Angles are the odd clock positions (30, 90, ... 330) so the six GAPS land on
the even ones, which is where the districts go. ]]
local PLOT_RING_R = 336
local PLOT_DEFS = {}
for i = 0, 5 do
	local a = math.rad(30 + i * 60)
	local yaw = math.atan2(-math.cos(a), -math.sin(a))
	table.insert(PLOT_DEFS, {
		pivot = CFrame.new(math.cos(a) * PLOT_RING_R, 0, math.sin(a) * PLOT_RING_R) * CFrame.Angles(0, yaw, 0),
	})
end

return {
	START_CASH = START_CASH,
	CODE_REWARD = CODE_REWARD,
	CODE_SECONDS = CODE_SECONDS,
	CODE_COMBO_STEP = CODE_COMBO_STEP,
	CODE_COMBO_MAX = CODE_COMBO_MAX,
	CLICKS_TO_SHIP = CLICKS_TO_SHIP,
	INTERN_RATE = INTERN_RATE,
	GARAGE_DESKS = GARAGE_DESKS,
	FLOOR = FLOOR,
	WALL = WALL,
	TRIM = TRIM,
	ACCENT = ACCENT,
	GOOD = GOOD,
	GOLD = GOLD,
	BAD = BAD,
	ROLE_ORDER = ROLE_ORDER,
	ROOMS = ROOMS,
	ROOM_BY_ID = ROOM_BY_ID,
	HQ_LEVELS = HQ_LEVELS,
	HQ_MULT = HQ_MULT,
	HIRE_BASE = HIRE_BASE,
	HIRE_GROWTH = HIRE_GROWTH,
	WING_STEP = WING_STEP,
	FURNITURE_INFLATION = FURNITURE_INFLATION,
	PAYDAY_SECONDS = PAYDAY_SECONDS,
	MILESTONE_BASE = MILESTONE_BASE,
	MILESTONE_STEP = MILESTONE_STEP,
	MILESTONE_MAX = MILESTONE_MAX,
	ROMAN = ROMAN,
	WING_UP_BASE = WING_UP_BASE,
	WING_UP_GROWTH = WING_UP_GROWTH,
	WING_LEVEL_AMOUNT = WING_LEVEL_AMOUNT,
	WING_LEVEL_TEXT = WING_LEVEL_TEXT,
	HIRE_GROWTH_LATE = HIRE_GROWTH_LATE,
	QUALITY_CAP = QUALITY_CAP,
	MORALE_CAP = MORALE_CAP,
	HIRE_TAPER_AT = HIRE_TAPER_AT,
	WING_UP_SECONDS = WING_UP_SECONDS,
	WORK_FIRST = WORK_FIRST,
	WORK_GROWTH = WORK_GROWTH,
	LAUNCH_DURATION = LAUNCH_DURATION,
	TIER_RATE = TIER_RATE,
	TIER_TITLE = TIER_TITLE,
	PROMOTE_EVERY = PROMOTE_EVERY,
	TALENT = TALENT,
	OFFER_EVERY = OFFER_EVERY,
	OFFER_MIN_TIER = OFFER_MIN_TIER,
	OFFER_INCOME_SECONDS = OFFER_INCOME_SECONDS,
	OFFER_MIN_SECONDS = OFFER_MIN_SECONDS,
	OFFER_WORTH_CAP = OFFER_WORTH_CAP,
	ALUMNI_STEP = ALUMNI_STEP,
	ALUMNI_CAP = ALUMNI_CAP,
	RIVALS = RIVALS,
	MARKETS = MARKETS,
	IPO_AT = IPO_AT,
	RIVAL_EVERY = RIVAL_EVERY,
	PRESSURE_SECONDS = PRESSURE_SECONDS,
	SHARE_FLOOR = SHARE_FLOOR,
	SHARE_DECAY = SHARE_DECAY,
	PUBLIC_RIVALS = PUBLIC_RIVALS,
	RIVAL_GROWTH = RIVAL_GROWTH,
	RIVAL_CAP_MULT = RIVAL_CAP_MULT,
	SLOT_W = SLOT_W,
	SLOT_D = SLOT_D,
	ROAD_Z = ROAD_Z,
	PLOT_DEFS = PLOT_DEFS,
	PLOT_RING_R = PLOT_RING_R,
}
