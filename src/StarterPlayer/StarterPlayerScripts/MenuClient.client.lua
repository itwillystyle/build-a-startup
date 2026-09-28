--[[
	MenuClient v3 -- LocalScript in StarterPlayer -> StarterPlayerScripts.

	v1.3: THE STARTER SCREEN IS GONE. His call, and the right one: every top
	tycoon (Sell Lemons, Restaurant Tycoon 2, Ghost Drivers) drops you into
	the world and points at the first thing to touch. The old rail + orbit
	camera lived here (v2, 468 lines); the guide arrow (GuideClient) is the
	replacement.

	What survives: the MenuDone handshake. Every HUD keys on the server-set
	MenuDone attribute, so this script fires it once as soon as it loads.
	The server owns the attribute (a client SetAttribute never replicates).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remotes = ReplicatedStorage:WaitForChild("SVRemotes")
local menuDone = remotes:WaitForChild("MenuDone")

menuDone:FireServer()
