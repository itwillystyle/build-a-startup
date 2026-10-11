---
name: game-doctor
description: Run the game doctor on Build a Startup! -- Studio plays the game as Wilz and measures it (floors, lifts, camera, chase, UI, errors), then the report is judged and posted to Discord. Use for the nightly routine, or when asked to "run the doctor", "check the whole game", or "what is broken".
---

# The game doctor

Three layers. Each step in the game checks itself; this skill only drives them.
1. In the game: `GameDoctor.server.lua` plays (act, then measure against a number).
   `DoctorClient` + `DoctorProbes` measure what only the player's screen can see.
2. This routine (a Claude session with the Studio tools): Play, run, collect,
   stop, restore the save.
3. The judge: `routine.sh checkup-report` (doctor_lib) ranks, diffs with the last
   run, writes DOCTOR.md; `routine.sh checkup-post` posts to Discord.

Never publish, never save the place (no Ctrl+S, no Alt+P), never touch the main
account's save. The doctor changes Wilz's save; it is ALWAYS restored at the end.

## Steps
1. `list_roblox_studios`: the Build a Startup! place (105976291385232). None open:
   reply "Studio is not open, the doctor did not run" and stop.
2. `get_studio_state` must be Edit. If it is in Play, someone is using it: reply
   "Studio was busy (in Play), the doctor did not run" and stop.
3. `start_stop_play` true. Server datamodel: wait until a player, a character and
   `ServerScriptService.SiliconCore.SVDev` exist (up to 45 s), wait 5 s more, then
   `game.ServerScriptService.GameDoctor:SetAttribute("Request", "full/" .. os.clock())`.
4. Poll `GameDoctor:GetAttribute("Status")` in calls of ~110 s (`task.wait(1)` loop)
   until "done" (a full run is about 4 minutes; give up after 15 and go to 6).
5. Read `game.ServerStorage.DoctorReport.Value` and Write it, exactly, to
   `C:\Users\lukex\Downloads\silicon-startup\doctor\report-<YYYY-MM-DD>.json`.
6. `start_stop_play` false. Edit datamodel, after `task.wait(2)`:
   `return require(game.ServerScriptService.DevScenarios:Clone()).restore(1688749216)`
   It must return ok. If not, say so first, loudly.
7. `bash /c/Users/lukex/Downloads/silicon-startup/game-health/tools/routine.sh checkup-report /c/Users/lukex/Downloads/silicon-startup/doctor/report-<date>.json`
   then `... routine.sh checkup-post` (no webhook yet: say so, it is not a failure).
8. Reply in under 12 lines, plain words, no em dashes: the verdict line, each
   BLOCKER and BUG with what a player would see, the FEELs in one line, what got
   fixed since the last run, and that the save was restored.

## Reading it
BLOCKER = the loop breaks. BUG = wrong, playable. MISSING = an animation, sound or
feedback is not there. FEEL = works, feels janky. Thresholds marked provisional in
GameDoctor (camera cuts 0.5/s) are guesses to tune, not rules.
Not checked: cars, phones, two players, and how anything LOOKS.
