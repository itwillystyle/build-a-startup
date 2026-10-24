--[[ OneVoice (24 Oct 2026): one instruction on screen at a time. Pure.

	Rule A, "one voice" (Luke delegated the pick; board ui/animation-review/judge/
	ONE-INSTRUCTION-OPTIONS.md, mock scenes/7-one-instruction.html panel A). The playtest
	2026-10-20_04-46-03 had three asks at once at 7:44: the goal card "Drive to The Residences",
	the HUD's HOLD TO CODE and a floating UPGRADE. LAUNCH! sat on the job at 2:44 and 5:24.

	One strict order, the first that applies speaks:
	  1. "verb"   the button you can press here (HOLD TO CODE at the laptop, GIVE by your client)
	  2. "job"    the job in your hands (an app you carry, a job you started coding, a recruit)
	  3. "launch" LAUNCH! (an app is ready and your hands are free)
	  4. "goal"   the goal card
	What folds: under a verb or LAUNCH! the goal card is its 44 px icon (no words, still a tap
	to look) and its world marker hides; under the job the card names the job (the server's
	goal is give / finish mid-job, Clients.goal) and LAUNCH! waits as a small chip whose
	half-pay clock is paused (LaunchClock; launchHeld is the same rule, used by the server).

	HudClient picks and publishes the voice (the client-local attribute OneVoice); GuideClient
	folds the card, PromptClient hides prompts, CoachClient holds tips. Tested by
	tests/offline/onevoice.spec.luau. ]]
local OneVoice = {}

-- the button you can press right now (HudClient's rule since 18 Oct, option A)
-- a = { carrying, canGive, jobWaiting, atLaptop }
function OneVoice.verbOf(a)
	if a.carrying then return a.canGive and "give" or nil end
	if a.jobWaiting and a.atLaptop then return "code" end
	return nil
end

-- does this voice fold the goal card to its icon (and hide its marker)? GuideClient reads the voice
function OneVoice.folds(voice)
	return voice == "verb" or voice == "launch"
end

-- st = { verb, carrying, midJob, recruit, launch, goal } (launch: an app waits; goal: the card has a goal)
-- -> { voice, verb, goal = "words"|"icon"|"hidden", launch = "button"|"chip"|nil, marker }
function OneVoice.pick(st)
	local voice
	if st.verb then voice = "verb"
	elseif st.carrying or st.midJob or st.recruit then voice = "job"
	elseif st.launch then voice = "launch"
	elseif st.goal then voice = "goal" end
	local folded = OneVoice.folds(voice)
	local launch
	if st.launch then launch = voice == "launch" and "button" or "chip" end
	return {
		voice = voice, verb = st.verb,
		goal = not st.goal and "hidden" or folded and "icon" or "words",
		launch = launch,
		marker = st.goal == true and not folded,
	}
end

-- is LAUNCH! folded to its chip (so its clock pauses)? The server's rule, from server state only:
-- a = { carrying, canGive, jobWaiting, atLaptop, midJob, recruit }
function OneVoice.launchHeld(a)
	local p = OneVoice.pick({ verb = OneVoice.verbOf(a), carrying = a.carrying, midJob = a.midJob,
		recruit = a.recruit, launch = true, goal = true })
	return p.launch == "chip"
end

-- what a floating E prompt is: the HUD's two verbs, an ask that competes with the goal, or the world
local ROLE = { ["HOLD TO CODE"] = "code", GIVE = "give", UPGRADE = "ask", BUILD = "ask" }
function OneVoice.promptRole(actionText)
	return ROLE[actionText] or "world"
end

--[[ a prompt under this pick: "draw" it, keep it "quiet" (E still works, nothing drawn: the HUD
	button is its look), or "off" (not reachable on this client, so the camera cannot hand E to
	an ask nobody is showing). An ask (UPGRADE, BUILD) draws only when the goal is the voice and
	the prompt is the goal's own target; every ask keeps its click on the part. World prompts
	(the lift, the car, recruits) are the way to the goal and stay, except under a button. ]]
function OneVoice.prompt(pick, role, nearGoal)
	if role == "code" or role == "give" then return "quiet" end
	if role == "ask" then return (pick.voice == "goal" and nearGoal) and "draw" or "off" end
	return pick.voice == "verb" and "off" or "draw"
end

-- may a coach tip show? Only on a calm screen, or the LAUNCH tip beside LAUNCH! itself
function OneVoice.coachOk(voice, tipTarget)
	if voice == nil or voice == "goal" then return true end
	return voice == "launch" and tipTarget == "Hud.Launch"
end

-- instructions on screen: the card's words, the button, LAUNCH! as a button, drawn prompts
function OneVoice.count(pick, promptsDrawn)
	local n = promptsDrawn or 0
	if pick.goal == "words" then n += 1 end
	if pick.voice == "verb" then n += 1 end
	if pick.launch == "button" then n += 1 end
	return n
end

return OneVoice
