--[[ HunterRun -- loads the headhunter's run track, once per rig (14 Oct 2026).

	Pure: no services at load, so tests/offline/hunterrun.spec.luau can drive it
	with stand-in rigs. StaffAnimClient's driveRun is the only caller.

	st.runTrack is nil while not loaded yet, false when this rig cannot take a
	track (no id, or LoadAnimation refused), and the track once it has one.

	A RIG STILL ARRIVING IS NOT A RIG THAT CANNOT RUN. A new rig reaches the
	client in pieces: measured 14 Oct (Studio, 10 chases), the torso and its
	joints came in one batch and the Humanoid and its Animator 8 ms later.
	StaffAnimClient registers a rig once the parts and joints exist, so the first
	frame could ask for a track before the Humanoid was there. That used to cache
	false for the whole chase: the hunter fell back to the Lua pose, and the doctor
	read "84% of moving frames had no run animation" (4 of ~40 chases, 12-14 Oct).
	Now a missing Humanoid returns nil WITHOUT caching, and the next frame asks again. ]]

local HunterRun = {}

-- new: the instance constructor (Instance.new in the game, a stand-in in tests)
function HunterRun.trackFor(model, st, runId, new)
	if st.runTrack ~= nil then return st.runTrack or nil end
	if runId == "" then st.runTrack = false return nil end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end   -- still replicating: ask again next frame
	-- a block rig has no Animator from the server; an avatar's comes with its Humanoid
	local animator = hum:FindFirstChildOfClass("Animator") or new("Animator", hum)
	local anim = new("Animation")
	anim.AnimationId = runId
	local ok, track = pcall(animator.LoadAnimation, animator, anim)
	if not ok then st.runTrack = false return nil end
	track.Priority = Enum.AnimationPriority.Movement
	track.Looped = true
	st.runTrack = track
	return track
end

return HunterRun
