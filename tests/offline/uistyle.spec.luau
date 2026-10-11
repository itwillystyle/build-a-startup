--[[ uistyle.spec.luau -- one visual language, enforced (11 Oct 2026).

	DESIGN.md (the Sticker Sheet) has had the rules since v5: 7 text sizes, 4 corner
	sizes, a role palette, two fonts. The code did not follow them: on 11 Oct the UI
	scan found 57 hand-picked colours, sizes from 3 to 56 px (seven under the 14 px
	floor), 31 hand-typed corners and Gotham, which DESIGN.md bans. Every one of those
	now comes from UIKit, and this test keeps it that way: it reads the client UI
	source and fails on
	  * a font named directly (Enum.Font.X / Font.fromName) instead of UIKit.HEAD/BODY/BOLD
	  * a text size typed as a number instead of UIKit.TYPE.x
	  * a corner typed as pixels instead of UIKit.RADIUS.x (UDim.new(1, 0) pills are fine)
	  * a Color3.fromRGB / Color3.new in UI code; a 3D-world colour (a light, a
	    particle, a part) says so with a "world colour" comment on its line, and
	    a colour the server sends as data with "server colour"
	UIKit.lua itself (where the tokens are made) and the purely-3D client scripts
	are not UI and are not read. ]]
local fs = require("@lune/fs")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local DIR = "src/StarterPlayer/StarterPlayerScripts"
local EXTRA = { "src/ReplicatedStorage/Notify.lua", "src/ReplicatedStorage/Cine.lua", "src/ReplicatedStorage/Moment.lua" }
-- client scripts that draw only the 3D world (or are Studio test harnesses), no UI
local NOT_UI = {
	LifeClient = true, TrafficClient = true, TreeCullClient = true, SkyClient = true, StaffAnimClient = true,
	RocketClient = true, ClientInfoClient = true, DevRobot = true, DoctorClient = true, CameraWallsClient = true,
	HunterSmoothClient = true, ShadowClient = true, MotionClient = true, ChaseAudioClient = true, MusicClient = true,
}

local function files()
	local out = {}
	for _, f in fs.readDir(DIR) do
		local name = f:gsub("%.client%.lua$", ""):gsub("%.lua$", "")
		if f:match("%.lua$") and not NOT_UI[name] then table.insert(out, { path = DIR .. "/" .. f, name = name }) end
	end
	for _, p in EXTRA do table.insert(out, { path = p, name = p:match("([%w_]+)%.lua$") }) end
	return out
end

-- every code line (comments and block comments stripped), with its line number
local function codeLines(src)
	local out, inBlock = {}, false
	local n = 0
	for line in (src .. "\n"):gmatch("(.-)\r?\n") do
		n += 1
		local code = line
		if inBlock then
			local e = code:find("]]", 1, true)
			if e then code = code:sub(e + 2) inBlock = false else code = "" end
		end
		local b = code:find("--[[", 1, true)
		if b then
			local e = code:find("]]", b + 4, true)
			if e then code = code:sub(1, b - 1) .. code:sub(e + 2) else code = code:sub(1, b - 1) inBlock = true end
		end
		local c = code:find("--", 1, true)
		local comment = c and code:sub(c) or ""
		if c then code = code:sub(1, c - 1) end
		table.insert(out, { n = n, code = code, comment = comment })
	end
	return out
end

local function scan(rule)
	local bad = {}
	for _, f in files() do
		for _, l in codeLines(fs.readFile(f.path)) do
			local why = rule(l.code, l.comment)
			if why then table.insert(bad, ("%s:%d %s"):format(f.name, l.n, why)) end
		end
	end
	return bad
end

local function report(bad)
	return ("%d found:\n  %s"):format(#bad, table.concat(bad, "\n  ", 1, math.min(#bad, 15)))
end

test("fonts come from UIKit (FredokaOne via UIKit.HEAD, Nunito via BODY/BOLD), never Gotham", function()
	local bad = scan(function(code)
		local f = code:match("Enum%.Font%.(%w+)") or code:match("Font%.fromName%(%s*\"(%w+)")
		return f and ("names the font " .. f) or nil
	end)
	assert(#bad == 0, report(bad))
end)

test("text sizes come from UIKit.TYPE (14 16 18 22 28 36 44), never a typed number", function()
	local bad = scan(function(code)
		local n = code:match("TextSize%s*=%s*(%d+)")
		-- the three text helpers: UIKit.label / heading / outlined(parent, text, SIZE, ...)
		-- (UIKit.art and UIKit.icon take an image size in pixels: not text)
		for fn, size in code:gmatch("UIKit%.(%a+)%([^,]+,[^,]+,%s*(%d+)%s*[,)]") do
			if fn == "label" or fn == "heading" or fn == "outlined" then n = n or size end
		end
		return n and ("text size " .. n .. " typed in") or nil
	end)
	assert(#bad == 0, report(bad))
end)

test("corners come from UIKit.RADIUS (or are pills), never typed pixels", function()
	local bad = scan(function(code)
		local px = code:match("CornerRadius%s*=%s*UDim%.new%(%s*0%s*,%s*(%d+)%s*%)") or code:match("[{,]%s*radius%s*=%s*(%d+)")
		return px and ("corner " .. px .. " px typed in") or nil
	end)
	assert(#bad == 0, report(bad))
end)

--[[ v8 (11 Oct, step 4) MOTION. DESIGN.md: overshoot is for rewards. On 11 Oct 24 tweens
	used EasingStyle.Back, most on routine things (a phone banner, the cash bump, a coach tip),
	so a paycheck tick moved like a level-up and nothing felt bigger than anything else. Now
	Back / Elastic / Bounce is allowed only on a line that says "reward" (the four Moment
	sequences, the DONE stamp, a building rising); everything else eases out (Quint). ]]
test("overshoot (Back, Elastic, Bounce) only on a line marked as a reward", function()
	local bad = {}
	local all = files()
	table.insert(all, { path = "src/ReplicatedStorage/UIKit.lua", name = "UIKit" })   -- its buttons move too
	for _, f in all do
		for _, l in codeLines(fs.readFile(f.path)) do
			local style = l.code:match("EasingStyle%.(Back)") or l.code:match("EasingStyle%.(Elastic)") or l.code:match("EasingStyle%.(Bounce)")
			if style and not l.comment:find("reward", 1, true) then
				table.insert(bad, ("%s:%d %s on a routine tween (use Quint, or mark it '-- reward')"):format(f.name, l.n, style))
			end
		end
	end
	assert(#bad == 0, report(bad))
end)

test("UI colours come from the palette; a 3D-world colour is marked as one", function()
	local bad = scan(function(code, comment)
		if not (code:match("Color3%.fromRGB%(") or code:match("Color3%.new%(")) then return nil end
		if comment:find("world colour", 1, true) or comment:find("server colour", 1, true) then return nil end
		return "a hand-picked colour (use a UIKit role, or mark a 3D colour '-- world colour')"
	end)
	assert(#bad == 0, report(bad))
end)

return T
