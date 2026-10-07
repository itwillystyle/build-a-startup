--[[
	VoiceCheck -- reports the state of each player's voice chain, because a
	live server cannot be inspected by hand.

	THE PROBLEM THIS EXISTS FOR. Calls connect and carry no sound, and no
	microphone button appears in the live client, while every setting that can
	be measured is correct: the universe has voice on, the account is eligible,
	VoiceChatService has UseAudioApi = Enabled and EnableDefaultVoice = true,
	and the place is published. There is nothing left to read from the outside.

	WHAT I GOT WRONG FIRST, recorded so it is not repeated. A playtest scan
	found ZERO AudioEmitters in the datamodel and I took that for the fault --
	a microphone wired to nothing. It was not. The engine's default setup
	builds the input and the emitter ON THE SERVER and that pair does NOT
	replicate to clients; a client only ever holds its own
	AudioListener -> AudioDeviceOutput. Scanning from the client was scanning
	the one place the emitter could never appear. Measured both ways in one
	session to be sure:

	  server datamodel   AudioDeviceInput -> AudioEmitter   (on the character)
	  client datamodel   AudioListener    -> AudioDeviceOutput

	Both halves are present and correct. So the default voice setup is NOT the
	fault, and anything built to "fix" it would have been dead code wrapped in
	a false explanation.

	WHY A REPORT AND NOT A FIX. The remaining unknown is only observable in a
	real server: whether the engine ever starts the microphone. That is
	AudioDeviceInput.Active, which Roblox's own core scripts set and which is
	always false in Studio because no voice session exists there. Studio
	therefore cannot test voice at all -- an earlier claim that it had was
	wrong, and rested on the input OBJECT existing, which proves nothing.

	So each player gets a VoiceState attribute naming the state of every link,
	and the phone's Calls screen prints it. One screenshot of that line in a
	live server distinguishes the two remaining causes:

	  "mic: live"           the engine started the microphone, so voice works
	                        and the missing button is cosmetic -- the silence
	                        is then in the call wiring or the proximity fade
	  "mic: not recording"  the engine never started it, which is account or
	                        client side and not something the place controls

	This file only reads. It changes nothing about how voice behaves.
]]

local Players = game:GetService("Players")

local VoiceCheck = {}

local state = {}                  -- [player] = report string

--[[ The emitter the engine makes lives on the server only, so this must run
	on the server to see it. It is the character it hangs off, not the Player. ]]
local function emitterOf(char)
	if not char then return nil end
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("AudioEmitter") then return d end
	end
	return nil
end

--[[ An emitter alone is not enough: it has to be fed by this player's input.
	A wire is what makes the pair a chain. ]]
local function wiredFrom(input, emitter)
	if not (input and emitter) then return false end
	for _, d in ipairs(emitter:GetChildren()) do
		if d:IsA("Wire") and d.SourceInstance == input and d.TargetInstance == emitter then
			return true
		end
	end
	-- the engine is free to parent its wire elsewhere, so fall back to a sweep
	for _, d in ipairs(game:GetDescendants()) do
		if d:IsA("Wire") and d.SourceInstance == input and d.TargetInstance == emitter then
			return true
		end
	end
	return false
end

local function report(player)
	local input = player:FindFirstChildOfClass("AudioDeviceInput")
	local emitter = emitterOf(player.Character)
	local bits = {}

	--[[ Active is the one fact that only a live server has. Muted is the
		player's own choice and is shown only when it is on, so it cannot be
		mistaken for a fault. ]]
	if not input then
		bits[#bits + 1] = "mic: MISSING"
	elseif input.Muted then
		bits[#bits + 1] = input.Active and "mic: live, muted" or "mic: not recording, muted"
	else
		bits[#bits + 1] = input.Active and "mic: live" or "mic: not recording"
	end

	if not player.Character then
		bits[#bits + 1] = "voice: no body yet"
	elseif emitter and wiredFrom(input, emitter) then
		bits[#bits + 1] = "voice: wired"
	elseif emitter then
		bits[#bits + 1] = "voice: emitter NOT WIRED"
	else
		bits[#bits + 1] = "voice: NO EMITTER"
	end

	bits[#bits + 1] = "eligible: " .. tostring(player:GetAttribute("HasVoice") == true)

	local s = table.concat(bits, " · ")
	if state[player] ~= s then
		state[player] = s
		player:SetAttribute("VoiceState", s)
	end
	return s
end

function VoiceCheck.init()
	Players.PlayerRemoving:Connect(function(p) state[p] = nil end)

	task.spawn(function()
		while true do
			for _, p in ipairs(Players:GetPlayers()) do
				pcall(report, p)
			end
			task.wait(2)
		end
	end)
end

function VoiceCheck.stateOf(player)
	return state[player]
end

return VoiceCheck
