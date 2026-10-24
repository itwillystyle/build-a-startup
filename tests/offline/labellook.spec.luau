-- labellook.spec.luau: the in-world labels against the picked mock (24 Oct 2026, look pass L3)
local fs = require("@lune/fs")
local LL = require("../../src/ReplicatedStorage/LabelLook")
local CFG = require("../../src/ServerScriptService/CoreConfig")
local V1 = require("../../src/ServerScriptService/HQMeta/V1")
local GL = require("../../src/ReplicatedStorage/GarageLayout")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end
local function near(a, b, tol) return math.abs(a - b) <= tol end
local function src(p) return fs.readFile(p) end

-- the body of one function in a source file, from its header to the next top-level `end`
local function body(text, header)
	local i = text:find(header, 1, true)
	assert(i, "not found: " .. header)
	local j = text:find("\nend\n", i, true)
	return text:sub(i, j)
end

-- ------------------------------------------------------------------ 1. bubble vs nameplate

test("claim: a client's bubble wins its space and a staff tag touching it fades", function()
	-- after-C1.jpg: the bubble card x 745..925, "Noor · STAR" tag from x 925, same row
	local bubble = { x = 835, y = 145, w = 180, h = 74, solid = true }
	local noor = { x = 1010, y = 150, w = 170, h = 44, pri = 30000 }
	local f = LL.claim({ noor, bubble })
	assert(f[noor], "a STAR tag touching the bubble must fade")
	assert(not f[bubble], "the bubble never fades")
end)

test("claim: a tag well clear of the bubble stays, and tags still fade for each other (v3.6 rule)", function()
	local bubble = { x = 835, y = 145, w = 180, h = 74, solid = true }
	local ada = { x = 617, y = 70, w = 110, h = 44, pri = 20000 }
	local f = LL.claim({ bubble, ada })
	assert(not f[ada], "Ada's tag is 40 px clear of the bubble")
	local rosa = { x = 400, y = 300, w = 120, h = 44, pri = 40000 }
	local cole = { x = 420, y = 310, w = 120, h = 44, pri = 39000 }
	f = LL.claim({ cole, rosa })
	assert(f[cole] and not f[rosa], "the rarer, nearer tag keeps its place")
end)

test("stackClear: a client's own staff tag cannot share its head with the bubble", function()
	-- ClientsServer bubble: 3.6 studs, 74 px box; StaffRig avatar tag: 2.9 studs, 44 px, MaxDistance 14
	local bubble, tag = { offset = 3.6, px = 74 }, { offset = 2.9, px = 44 }
	local okFar = LL.stackClear(bubble, tag, 14)
	local okMid = LL.stackClear(bubble, tag, 8)
	assert(not okFar and not okMid, "0.7 studs apart they overlap from 8 to 14 studs away")
	local cs = src("src/ServerScriptService/ClientsServer.lua")
	local b = cs:match("local function bubble%(model, client%)(.-)\n\tend\n")
	assert(b, "ClientsServer bubble() not found")
	assert(b:find('FindFirstChild%("Tag"%)') and b:find(":Destroy%(%)"),
		"bubble() must remove the client's own staff tag (it says DESIGNER over a stranger, under the bubble)")
end)

test("StaffAnimClient's declutter claims client bubbles first, through LabelLook.claim", function()
	local s = src("src/StarterPlayer/StarterPlayerScripts/StaffAnimClient.client.lua")
	assert(s:find("LabelLook.claim(", 1, true), "declutter must use LabelLook.claim")
	assert(s:find('"ClientBubble"', 1, true), "declutter must put the client bubbles in the claim")
	assert(s:find("solid = true", 1, true), "the bubbles claim as solid")
end)

-- ------------------------------------------------------------------ 2. night nameplates

local function roleColours()
	local s = src("src/ServerScriptService/StaffRig.lua")
	local block = s:match("StaffRig%.ROLES = (%b{})")
	local out = {}
	for name, r, g, b in block:gmatch('name = "(%u+)",%s*color = Color3%.fromRGB%((%d+), (%d+), (%d+)%)') do
		out[name] = Color3.fromRGB(tonumber(r), tonumber(g), tonumber(b))
	end
	return out
end

local function talentColours()
	local out = {}
	for _, t in CFG.TALENT do if t.color then out[t.name] = t.color end end
	return out
end

test("oklab: white 1, black 0, sRGB red 0.628 (Ottosson's reference)", function()
	assert(near((LL.oklab(Color3.new(1, 1, 1))), 1, 1e-3), "white")
	assert(near((LL.oklab(Color3.new(0, 0, 0))), 0, 1e-6), "black")
	assert(near((LL.oklab(Color3.new(1, 0, 0))), 0.628, 2e-3), "red")
end)

test("reads: the measured night shot -- 'Ada' (white, stroke 0.25) reads, 'Lead Researcher' does not", function()
	local back = LL.BACKDROPS.nightStreet
	local adaOk = LL.reads(Color3.new(1, 1, 1), Color3.new(0, 0, 0), 0.25, back, "night")
	local resOk = LL.reads(roleColours().RESEARCHER, Color3.new(0, 0, 0), 0.4, back, "night")
	assert(adaOk, "the white name line reads at night in final-C1-night.jpg")
	assert(not resOk, "the old role-coloured sub line must fail the rule (it is unreadable in the shot)")
end)

test("every old nameplate colour fails at night; every plateText one reads on all four backdrops", function()
	local all = {}
	for k, c in roleColours() do all["role " .. k] = c end
	for k, c in talentColours() do all["talent " .. k] = c end
	local n = 0
	for name, c in all do
		n += 1
		assert(not LL.reads(c, Color3.new(0, 0, 0), 0.4, LL.BACKDROPS.nightStreet, "night"),
			name .. ": the old look (raw colour, stroke 0.4) should fail at night")
		local fill = LL.plateText(c)
		for bname, back in LL.BACKDROPS do
			local when = bname:sub(1, 5) == "night" and "night" or "day"
			local ok, edge, ground = LL.reads(fill, LL.PLATE.stroke, LL.PLATE.strokeT, back, when)
			assert(ok, ("%s on %s: edge %.2f, ground %.2f"):format(name, bname, edge, ground))
		end
	end
	assert(n >= 9, "5 roles and 4 talents, got " .. n)
end)

test("plateText keeps the hue (a role is still its colour) and leaves light colours alone", function()
	for name, c in roleColours() do
		local _, a0, b0 = LL.oklab(c)
		local L1, a1, b1 = LL.oklab(LL.plateText(c))
		assert(near(L1, LL.TEXT_L, 0.01), name .. " lifted to TEXT_L")
		local dh = math.abs(math.atan2(b1, a1) - math.atan2(b0, a0))
		dh = math.min(dh, 2 * math.pi - dh)
		assert(dh < math.rad(12), ("%s hue moved %.1f degrees"):format(name, math.deg(dh)))
		assert(math.sqrt(a1 * a1 + b1 * b1) > 0.02, name .. " keeps some colour")
	end
	local white = Color3.new(1, 1, 1)
	assert(LL.plateText(white) == white, "white stays white")
end)

test("StaffRig's nameplate wears the plate look: lifted colours, opaque outline, unlit, 14 px floor", function()
	local s = src("src/ServerScriptService/StaffRig.lua")
	local tag = body(s, "local function nameTag(")
	assert(tag:find("LightInfluence = 0", 1, true), "nameTag: LightInfluence 0, like every other world label")
	assert(tag:find("LabelLook.plateText(color)", 1, true), "nameTag: the sub line in plateText")
	assert(tag:find("LabelLook.PLATE.strokeT", 1, true), "nameTag: the plate's opaque outline")
	assert(tag:find("LabelLook.PLATE.subSize", 1, true), "nameTag: the sub line at the plate size")
	assert(not tag:find("TextStrokeTransparency = 0.4", 1, true), "the 0.4 outline is the night failure")
	local talent = body(s, "function StaffRig.setTalent(")
	assert(talent:find("LabelLook.plateText(color)", 1, true), "setTalent: the talent-coloured name in plateText")
	assert(LL.PLATE.subSize >= 14, "DESIGN.md's 14 px text floor")
end)

-- ------------------------------------------------------------------ 3. the board over the garage

test("the garage numbers are the game's own (CoreConfig, GarageLayout, HQMeta)", function()
	local G = CFG.HQ_LEVELS[1]
	assert(G.name == "GARAGE", "HQ level 1 is the garage")
	assert(LL.GARAGE.door == G.w - 1 and LL.GARAGE.door == GL.HALF_X * 2, "door = the inner opening")
	local sh = V1.HQ_1_Shell
	assert(near(LL.GARAGE.roofTop, sh.c.Y + sh.s.Y / 2, 0.01), "roof top = the garage shell's top")
	assert(near(LL.GARAGE.front, sh.c.Z + sh.s.Z / 2, 0.01), "front = the shell's front face")
end)

test("garageBoard: as wide as the mock's sign over the door, both rows kept, sitting on the roof", function()
	local b = LL.garageBoard()
	local door = LL.GARAGE.door
	-- measured: mock sign / door 0.68; live board / door 1.20 (final-C2-day.jpg)
	assert(near(b.w / door, 0.68, 0.02), ("board / door %.2f, mock 0.68"):format(b.w / door))
	assert(not near(58 / door, 0.68, 0.3), "the old 58-stud board is far off the mock")
	assert(near(b.w / b.h, 58 / 19, 1e-6), "the board keeps its own shape")
	assert(b.y - b.h / 2 >= LL.GARAGE.roofTop + 0.5, "the board clears the roof")
	assert(b.y - b.h / 2 <= LL.GARAGE.roofTop + 2, "and sits on it, not floating over the plot")
	assert(b.w * b.h < 58 * 19 / 4, "under a quarter of the old board's area")
	assert(LL.isGarage(1) and LL.isGarage(nil) and not LL.isGarage(2), "towers keep the big board")
end)

test("ValleyClient sizes the board through LabelLook while the plot is the garage", function()
	local s = src("src/StarterPlayer/StarterPlayerScripts/ValleyClient.client.lua")
	assert(s:find("LabelLook.garageBoard()", 1, true), "ValleyClient must call LabelLook.garageBoard()")
	assert(s:find("LabelLook.isGarage(", 1, true), "ValleyClient must switch on LabelLook.isGarage")
end)

return T
