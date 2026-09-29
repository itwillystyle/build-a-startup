--[[
	MusicClient v2 -- LocalScript in StarterPlayer -> StarterPlayerScripts.

	Owns the one Sound. Five licensed tracks from the Creator Store (APM and
	DistroKid: pre-moderated, free, no upload), picked in the menu's SETTINGS
	panel. The menu never touches the Sound; it sets player attributes and
	this script reacts:
	  MenuMuted (bool)   -> volume 0 / VOLUME, and SetMuted to the server (saved)
	  MusicTrack (int)   -> switch track (session only; not saved)
	This script publishes MusicTrackName and MusicTrackCount for the picker.

	A bad or moderated audio id plays SILENCE, not an error, so every track is
	preload-checked and one that fails is skipped.

	The small MUSIC button in the corner only appears after PLAY: on the menu
	the SETTINGS panel is the control.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("SVRemotes")
local setMuted = remotes:WaitForChild("SetMuted")

local TRACKS = {
	{ id = 1839486996, name = "Happy Whistling" },        -- APM, 93s, whistle + acoustic
	{ id = 1837768143, name = "Big League" },             -- APM, 122s, brassy/corporate
	{ id = 127423753792126, name = "Upbeat Corporate" },  -- DistroKid, 118s (the v1 track)
	{ id = 1841536347, name = "Charlie's Whistle" },      -- APM, 124s
	{ id = 105606954762358, name = "Cool Lofi" },         -- DistroKid, 169s, the chill option
}
local VOLUME = 0.16

local sound = Instance.new("Sound")
sound.Name = "Music"
sound.Looped = true
sound.Volume = VOLUME
sound.Parent = SoundService

local gui = Instance.new("ScreenGui")
gui.Name = "Music"
gui.ResetOnSpawn = false
gui.DisplayOrder = 7          -- v3.1: under every menu (at 21 it sat on the Index's close button)
gui.IgnoreGuiInset = true
gui.Enabled = player:GetAttribute("MenuDone") == true
player:GetAttributeChangedSignal("MenuDone"):Connect(function() gui.Enabled = true end)
gui.Parent = player:WaitForChild("PlayerGui")

local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
-- v2.8 (step 3): a small icon toggle under BUILD, no "MUSIC: ON" text box
-- v3.0: last in the shared left rail (hidden buttons above it take no space)
-- v3.1: a small round toggle in the top-right corner. It sat in the left
-- rail, moved three times in five minutes as buttons unlocked above it, and
-- was the only WHITE rail button (white means information everywhere else).
-- The rail now holds only game actions.
UIKit.safe(gui)
local btn, btnLabel, btnIcon = UIKit.iconButton(gui, "musicOn", nil, UIKit.CARD, {
	Name = "MuteButton", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10),
	Size = UDim2.new(0, 44, 0, 44),
}, { iconSize = 22, dark = true, radius = 22 })
-- v5: steps aside while a menu is open (the Index's close button sat on it)
UIKit.onMenuChange(function(open) btn.Visible = not open end)

local ok = {}          -- id -> true once preload confirmed a real TimeLength
local current = 0

local function muted() return player:GetAttribute("MenuMuted") == true end

local function applyVolume()
	sound.Volume = muted() and 0 or VOLUME
	if UIKit.ART and UIKit.ART.musicOn then
		-- v3.6: the rendered headphones; muted = faded, not a different glyph
		btnIcon.Image = UIKit.ART.musicOn
		btnIcon.ImageTransparency = muted() and 0.6 or 0
	else
		btnIcon.Image = UIKit.ICON[muted() and "musicOff" or "musicOn"]
		btnIcon.ImageColor3 = muted() and UIKit.CARD_MUTED or UIKit.CARD_TEXT
	end
end

local function play(i)
	local n = #TRACKS
	-- walk forward from i to the first track that preloaded; give up after n
	for k = 0, n - 1 do
		local j = ((i - 1 + k) % n) + 1
		if ok[TRACKS[j].id] then
			if current ~= j then
				current = j
				sound:Stop()
				sound.SoundId = "rbxassetid://" .. TRACKS[j].id
				sound.TimePosition = 0
				sound:Play()
			end
			player:SetAttribute("MusicTrack", j)
			player:SetAttribute("MusicTrackName", TRACKS[j].name)
			applyVolume()
			return
		end
	end
	player:SetAttribute("MusicTrackName", "unavailable")
	if UIKit.ART and UIKit.ART.musicOn then btnIcon.ImageTransparency = 0.6 else btnIcon.ImageColor3 = UIKit.CARD_MUTED end
end

btn.MouseButton1Click:Connect(function()
	player:SetAttribute("MenuMuted", not muted())
end)

player:GetAttributeChangedSignal("MenuMuted"):Connect(function()
	applyVolume()
	setMuted:FireServer(muted())
end)
player:GetAttributeChangedSignal("MusicTrack"):Connect(function()
	local i = player:GetAttribute("MusicTrack")
	if type(i) == "number" and i ~= current then play(i) end
end)

task.spawn(function()
	player:SetAttribute("MusicTrackCount", #TRACKS)
	local probes = {}
	for _, t in ipairs(TRACKS) do
		local s = Instance.new("Sound")
		s.SoundId = "rbxassetid://" .. t.id
		s.Parent = SoundService
		probes[#probes + 1] = s
	end
	pcall(function() ContentProvider:PreloadAsync(probes) end)
	for k, s in ipairs(probes) do
		if s.TimeLength > 0 then ok[TRACKS[k].id] = true end
		s:Destroy()
	end
	play(player:GetAttribute("MusicTrack") or 1)
end)
