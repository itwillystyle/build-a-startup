--[[ OneVoice (24 Oct 2026): one instruction on screen at a time. Pure.

	Rule A, "one voice" (Luke delegated the pick; board ui/animation-review/judge/
	ONE-INSTRUCTION-OPTIONS.md, mock scenes/7-one-instruction.html panel A). The playtest
	2026-10-20_04-46-03 had three asks at once at 7:44: the goal card "Drive to The Residences",
	the HUD's HOLD TO CODE and a floating UPGRADE. LAUNCH! sat on the job at 2:44 and 5:24.

	One strict order, the first that applies speaks:
	  1. "verb"   the button you can press here (HOLD TO CODE at the laptop, GIVE by your client)
	  2. "job"    the job in your hands (an app you carry, a job you started coding, a recruit)
	  3. "launch" LAUNCH! (an app is ready and your hands are free)
	  4. "phone"  a phone banner on screen (24 Oct: the doctor's hq:5 "cards over cards"; a tip steps aside for it),
	              or an incoming call (24 Oct: the call card sits on the same row)
	  5. "tip"    a coach tip on screen (24 Oct, F-6: a tip is an instruction, so the goal gives way)
	  6. "goal"   the goal card
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
-- 24 Oct (F-5): jobWaiting = a job no coder can take waits for you (Clients.waitingForYou, the
-- server's JobWaiting), so launchHeld below pauses the LAUNCH! clock by the same flag
function OneVoice.verbOf(a)
	if a.carrying then return a.canGive and "give" or nil end
	if a.jobWaiting and a.atLaptop then return "code" end
	return nil
end

-- does this voice fold the goal card to its icon (and hide its marker)? GuideClient reads the voice
-- 24 Oct (F-6): and under a coach tip, until GOT IT (the tip's card had landed on the goal pill)
-- 24 Oct: and under a phone banner, until it leaves (the banner sat on the goal pill at hq:5)
function OneVoice.folds(voice)
	return voice == "verb" or voice == "launch" or voice == "tip" or voice == "phone"
end

-- 24 Oct (live): may a milestone button (GO PUBLIC!) show? Only on a calm screen or while the goal
-- speaks; under a button, the job in hand or LAUNCH! it waits (it was a second instruction beside them)
function OneVoice.milestoneOk(voice)
	return voice == nil or voice == "goal"
end

-- 24 Oct (live): may a phone banner (an investor's text, a term sheet, a desk notice) slide in? Not
-- under a button or the job in hand: at the laptop an investor's opener sat ~7 s beside HOLD TO CODE.
-- It waits (PhoneClient holds it) and shows the moment the voice drops; the badge counts it at once
-- 24 Oct (F-6): beside a tip too: a banner is a Notify, and the tip steps aside for it (Notify.busy)
-- 24 Oct: and while a banner is the voice ("phone"): being the voice must not send it back to wait
function OneVoice.phoneOk(voice)
	return voice == nil or voice == "goal" or voice == "launch" or voice == "tip" or voice == "phone"
end

--[[ 24 Oct (doctor FEEL "cards over cards" at hq:5, 1074 x 376): the banner slides to its usual row
	(y 96), but on a short screen the goal card's holder is fitted below the money line (top y 106), so
	even the folded 44 px icon sat wholly under the banner (1,936 px2). banner = its rect on the usual
	row, goal = the goal card's rect or nil, both in one gui's space. Returns the banner's y: the usual
	row, or just below the goal card when that row would cover it (the doctor's rule, > 6 px both ways)
	24 Oct: the incoming-call card uses it too (same row, same rule); any top-row card's rect works ]]
OneVoice.BANNER_GAP = 8
function OneVoice.bannerY(banner, goal)
	if not goal then return banner.y end
	local ox = math.min(banner.x + banner.w, goal.x + goal.w) - math.max(banner.x, goal.x)
	local oy = math.min(banner.y + banner.h, goal.y + goal.h) - math.max(banner.y, goal.y)
	if ox > 6 and oy > 6 then return goal.y + goal.h + OneVoice.BANNER_GAP end
	return banner.y
end

-- the banners a waiting phone keeps: the newest one per thread (key), at most PHONE_HELD in all,
-- oldest out, so walking away replays one or two, never a burst. Item tables gain .key
OneVoice.PHONE_HELD = 2
function OneVoice.holdBanner(held, key, item)
	for i = #held, 1, -1 do
		if held[i].key == key then table.remove(held, i) end
	end
	item.key = key
	table.insert(held, item)
	while #held > OneVoice.PHONE_HELD do table.remove(held, 1) end
	return held
end

-- st = { scene, verb, carrying, midJob, recruit, launch, phone, ring, tip, goal } (scene: a Bob cutscene, BobScenePlaying; launch: an app waits; phone: a phone
-- banner is on screen, PhoneClient's PhoneBannerShowing; ring: an incoming call is on screen, PhoneClient's
-- PhoneRingShowing (24 Oct); tip: a coach tip is on screen, CoachClient's CoachShowing; goal: the card has a goal)
-- -> { voice, verb, goal = "words"|"icon"|"hidden", launch = "button"|"chip"|nil, marker }
function OneVoice.pick(st)
	-- P-5 (25 Oct): Bob's cutscene owns the screen; everything else is hidden or waits
	if st.scene then return { voice = "scene", goal = "hidden", launch = nil, marker = false } end
	local voice
	if st.verb then voice = "verb"
	elseif st.carrying or st.midJob or st.recruit then voice = "job"
	elseif st.launch then voice = "launch"
	elseif st.phone or st.ring then voice = "phone"   -- 24 Oct: a banner or a call talks; the goal folds until it leaves
	elseif st.tip then voice = "tip"
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

-- may a coach tip show? Only on a calm screen, or the LAUNCH tip beside LAUNCH! itself.
-- 24 Oct (F-6): once it shows it is the voice ("tip"), and that does not hide it
function OneVoice.coachOk(voice, tipTarget)
	if voice == nil or voice == "goal" or voice == "tip" then return true end
	return voice == "launch" and tipTarget == "Hud.Launch"
end

-- instructions on screen: the card's words, the button, LAUNCH! as a button, a coach tip, a phone banner
-- as the voice (24 Oct), drawn prompts
function OneVoice.count(pick, promptsDrawn)
	local n = promptsDrawn or 0
	if pick.goal == "words" then n += 1 end
	if pick.voice == "verb" then n += 1 end
	if pick.launch == "button" then n += 1 end
	if pick.voice == "tip" or pick.voice == "phone" then n += 1 end
	return n
end

return OneVoice
