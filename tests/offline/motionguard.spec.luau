--[[ motionguard.spec.luau: the motion layer's ratchet (23 Oct 2026).

	UIKit.tween (the motion layer: Reduce Motion, finish-not-freeze, one set of durations and
	curves) is how UI moves now. On 23 Oct, 80 lines in 27 files still built a tween by hand
	(TweenInfo.new / TweenService:Create), and migrating all of them at once would be a risky
	diff. So this is a ratchet, as the consensus plan agreed (ui/animation-review/judge/FINAL.md,
	architecture point 8):
	  * a file may not have MORE hand-built tween lines than BASELINE says (new UI motion goes
	    through UIKit.tween); lower BASELINE when a file migrates, never raise it
	  * a line that must build its own tween says why with a tag: "-- motion: progress" (a fill
	    that measures time; Reduce Motion must not touch it), "-- motion: camera", or
	    "-- motion: reward"; tagged lines are not counted
	  * a file with a camera tag must also read UIKit.reducedMotion( (a camera move is the
	    strongest motion trigger)
	UIKit.lua and MotionSpec.lua are the layer itself and are not read. ]]
local fs = require("@lune/fs")

local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local ROOTS = { "src/StarterPlayer/StarterPlayerScripts", "src/ReplicatedStorage" }
local EXEMPT = { UIKit = true, MotionSpec = true }

local BASELINE = {
	BuildClient = 2, BuildModeClient = 3, CarClient = 1, ChaseCamClient = 6, ChaseFxClient = 7, CoachClient = 1,
	DailyClient = 1, GarageMoodClient = 2, GuideClient = 2, HudClient = 1, IndexClient = 1, IntroClient = 1,
	InventoryClient = 4, IpoClient = 6, LiftClient = 1, PhoneClient = 4, ProductClient = 1, PromptClient = 3,
	RocketClient = 1, TalentRevealClient = 6, TalentRowClient = 2, TeamClient = 1, WaferClient = 4,
	WorldFxClient = 5, Cine = 7, Moment = 5, Notify = 2,
}

-- -> { { name, untagged count, has camera tag, reads reducedMotion } }
local function scan()
	local out = {}
	for _, root in ROOTS do
		for _, f in fs.readDir(root) do
			if f:match("%.lua$") then
				local name = f:gsub("%.client%.lua$", ""):gsub("%.lua$", "")
				if not EXEMPT[name] then
					local src = fs.readFile(root .. "/" .. f)
					local n = 0
					for line in src:gmatch("[^\n]+") do
						local tweenLine = line:find("TweenInfo.new", 1, true) or line:find("TweenService:Create(", 1, true)
						if tweenLine and not line:find("-- motion:", 1, true) then n += 1 end
					end
					table.insert(out, {
						name = name, n = n,
						camera = src:find("-- motion: camera", 1, true) ~= nil,
						reads = src:find("UIKit.reducedMotion(", 1, true) ~= nil,
					})
				end
			end
		end
	end
	return out
end

test("no file builds more tweens by hand than it did on 23 Oct (new UI motion goes through UIKit.tween)", function()
	local over = {}
	for _, f in scan() do
		local allowed = BASELINE[f.name] or 0
		if f.n > allowed then
			table.insert(over, ("%s: %d hand-built tween lines, baseline %d (use UIKit.tween, or tag the line '-- motion: progress|camera|reward')"):format(f.name, f.n, allowed))
		end
	end
	assert(#over == 0, table.concat(over, "\n"))
end)

test("the baseline only goes down: a file that migrated must lower its number", function()
	local loose = {}
	for _, f in scan() do
		local allowed = BASELINE[f.name]
		if allowed and f.n < allowed then
			table.insert(loose, ("%s: baseline %d but only %d left; lower BASELINE.%s to %d"):format(f.name, allowed, f.n, f.name, f.n))
		end
	end
	assert(#loose == 0, table.concat(loose, "\n"))
end)

test("a file that moves the camera reads Reduce Motion", function()
	local bad = {}
	for _, f in scan() do
		if f.camera and not f.reads then
			table.insert(bad, f.name .. " has a '-- motion: camera' line but never calls UIKit.reducedMotion(")
		end
	end
	assert(#bad == 0, table.concat(bad, "\n"))
end)

return T
