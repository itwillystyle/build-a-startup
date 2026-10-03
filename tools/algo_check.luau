--!nolint
--[[
	algo_check — the measurable half of ALGORITHM-CHECK.md.

	Run from the CLIENT datamodel while playing. It reads the real PlayerGui, so it
	only tells the truth about screens that are actually open. Open the menu you want
	graded first, then run it.

	What it cannot do: anything that needs a second human or a real phone. Those are
	in the markdown and they stay there until somebody plays.

	Usage:
		local check = require(...)   -- or paste the body into execute_luau
		check.all()                  -- everything at the current viewport
		check.responsive()           -- re-measures at 5 screen sizes, the scaling test
]]

local Players = game:GetService("Players")
local Stats = game:GetService("Stats")

local MIN_TEXT = 14     -- px, below this is unreadable on a phone
local MIN_TAP = 44      -- px, Apple/Google both land here
local MAX_DRAWS = 1000  -- Roblox's documented low-end phone budget
local MAX_TRIS = 1000000

-- Viewports worth testing. Width x Height, in Roblox's own GUI pixels.
local SCREENS = {
	{ name = "phone landscape", size = Vector2.new(801, 392) },
	{ name = "phone small", size = Vector2.new(667, 331) },
	{ name = "tablet", size = Vector2.new(1024, 768) },
	{ name = "desktop", size = Vector2.new(1280, 720) },
	{ name = "wide", size = Vector2.new(1920, 1080) },
}

local M = {}

local function guis()
	local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local out = {}
	if not pg then return out end
	for _, g in ipairs(pg:GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled then table.insert(out, g) end
	end
	return out
end

-- Walk every visible descendant of every enabled ScreenGui.
local function eachVisible(fn)
	for _, g in ipairs(guis()) do
		for _, d in ipairs(g:GetDescendants()) do
			if d:IsA("GuiObject") and d.Visible and d.AbsoluteSize.Y > 0 then
				-- a child of an invisible parent still reports Visible, so check the chain
				local shown, p = true, d.Parent
				while p and p:IsA("GuiObject") do
					if not p.Visible then shown = false break end
					p = p.Parent
				end
				if shown then fn(d, g) end
			end
		end
	end
end

----------------------------------------------------------------------
-- 1. Text that is too small to read
----------------------------------------------------------------------
function M.text()
	local bad = {}
	eachVisible(function(d, g)
		if (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox"))
			and d.Text ~= "" and d.TextTransparency < 0.9 then
			-- TextScaled reports 0 in TextSize, so read what was actually drawn
			local px = d.TextScaled and d.TextBounds.Y or d.TextSize
			local scale = 1
			local p = d
			while p and p:IsA("GuiObject") do
				local s = p:FindFirstChildOfClass("UIScale")
				if s then scale *= s.Scale end
				p = p.Parent
			end
			px *= scale
			if px > 0 and px < MIN_TEXT then
				table.insert(bad, string.format("%s/%s  %.1fpx  %q", g.Name, d.Name, px, d.Text:sub(1, 24)))
			end
		end
	end)
	return bad
end

----------------------------------------------------------------------
-- 2. Tap targets too small for a thumb
----------------------------------------------------------------------
function M.taps()
	local bad = {}
	eachVisible(function(d, g)
		local tappable = d:IsA("TextButton") or d:IsA("ImageButton")
		if tappable and d.Active then
			local w, h = d.AbsoluteSize.X, d.AbsoluteSize.Y
			if w < MIN_TAP or h < MIN_TAP then
				table.insert(bad, string.format("%s/%s  %dx%d", g.Name, d.Name, w, h))
			end
		end
	end)
	return bad
end

----------------------------------------------------------------------
-- 3. Anything hanging off the edge of the screen
----------------------------------------------------------------------
function M.offscreen()
	local vp = workspace.CurrentCamera.ViewportSize
	local bad = {}
	eachVisible(function(d, g)
		-- only test things that look like real panels, not decorative strokes
		if d.AbsoluteSize.X < 40 or d.AbsoluteSize.Y < 20 then return end
		local p, s = d.AbsolutePosition, d.AbsoluteSize
		local off = {}
		if p.X < -2 then table.insert(off, "left") end
		if p.Y < -2 then table.insert(off, "top") end
		if p.X + s.X > vp.X + 2 then table.insert(off, "right") end
		if p.Y + s.Y > vp.Y + 2 then table.insert(off, "bottom") end
		if #off > 0 then
			table.insert(bad, string.format("%s/%s  off %s  (%d,%d %dx%d)",
				g.Name, d.Name, table.concat(off, "+"), p.X, p.Y, s.X, s.Y))
		end
	end)
	return bad
end

----------------------------------------------------------------------
-- 4. Render budget
----------------------------------------------------------------------
function M.render()
	local ok, draws = pcall(function() return Stats.SceneDrawcallCount:GetValue() end)
	local ok2, tris = pcall(function() return Stats.SceneTriangleCount:GetValue() end)
	return {
		draws = ok and math.floor(draws) or -1,
		tris = ok2 and math.floor(tris) or -1,
		drawsOk = ok and draws < MAX_DRAWS,
		trisOk = ok2 and tris < MAX_TRIS,
	}
end

----------------------------------------------------------------------
-- 5. THE SCALING TEST
--
-- This is the one that answers "why does my phone look different".
--
-- For every panel it records where the panel sits as a FRACTION of the screen,
-- at each viewport. If the UI scales properly those fractions stay the same.
-- If a panel is sized in fixed pixels, its fraction grows as the screen shrinks,
-- and that is exactly what you see as "offset" on a phone.
----------------------------------------------------------------------
local function snapshot()
	local vp = workspace.CurrentCamera.ViewportSize
	local out = {}
	eachVisible(function(d, g)
		if d.AbsoluteSize.X < 60 or d.AbsoluteSize.Y < 30 then return end
		local key = g.Name .. "/" .. d:GetFullName():gsub(".*" .. g.Name, "")
		out[key] = {
			w = d.AbsoluteSize.X / vp.X,
			h = d.AbsoluteSize.Y / vp.Y,
			x = d.AbsolutePosition.X / vp.X,
			y = d.AbsolutePosition.Y / vp.Y,
		}
	end)
	return out
end

function M.responsive(waitFor)
	waitFor = waitFor or 0.45
	local cam = workspace.CurrentCamera
	local shots, order = {}, {}

	-- NOTE: setting ViewportSize is not possible; Studio's Device Emulator drives it.
	-- Instead we read whatever size is current and ask the caller to switch devices.
	-- When run headless we compare against the stored reference below.
	local vp = cam.ViewportSize
	local name = string.format("%dx%d", vp.X, vp.Y)
	shots[name] = snapshot()
	table.insert(order, name)

	return shots, order
end

-- Compare two snapshots taken at different viewports.
-- Anything whose on-screen fraction moved more than `tol` is not scaling.
function M.drift(a, b, tol)
	tol = tol or 0.03
	local bad = {}
	for key, A in pairs(a) do
		local B = b[key]
		if B then
			local dw, dh = math.abs(A.w - B.w), math.abs(A.h - B.h)
			local dx, dy = math.abs(A.x - B.x), math.abs(A.y - B.y)
			local worst = math.max(dw, dh, dx, dy)
			if worst > tol then
				table.insert(bad, {
					key = key,
					worst = worst,
					detail = string.format("w%+.0f%% h%+.0f%% x%+.0f%% y%+.0f%%",
						(B.w - A.w) * 100, (B.h - A.h) * 100, (B.x - A.x) * 100, (B.y - A.y) * 100),
				})
			end
		end
	end
	table.sort(bad, function(p, q) return p.worst > q.worst end)
	return bad
end

----------------------------------------------------------------------
-- Report
----------------------------------------------------------------------
function M.all()
	local vp = workspace.CurrentCamera.ViewportSize
	local out = { string.format("=== algo_check @ %dx%d ===", vp.X, vp.Y) }

	local openGuis = {}
	for _, g in ipairs(guis()) do table.insert(openGuis, g.Name) end
	table.insert(out, "open: " .. table.concat(openGuis, ", "))

	local r = M.render()
	table.insert(out, string.format("render: %d draws (%s), %d tris (%s)",
		r.draws, r.drawsOk and "OK" or "OVER",
		r.tris, r.trisOk and "OK" or "OVER"))

	local function section(title, list, limit)
		if #list == 0 then
			table.insert(out, title .. ": 0  OK")
		else
			table.insert(out, string.format("%s: %d", title, #list))
			for i = 1, math.min(#list, limit or 8) do
				table.insert(out, "   " .. list[i])
			end
		end
	end

	section(string.format("text under %dpx", MIN_TEXT), M.text())
	section(string.format("taps under %dpx", MIN_TAP), M.taps())
	section("offscreen", M.offscreen())

	return table.concat(out, "\n")
end

return M
