---
name: sound-design
description: Choose, replace, time or mix any sound in Build a Startup! (SFX, music, ambience, cutscene audio, voices). Use before adding or swapping an Sfx.ID, when Luke says a sound is wrong, sloppy, late, generic or too loud, and when wiring cutscene cues. Never pick a sound by its store name alone.
---

# sound-design

I cannot hear. Every choice here is made by MEASURING the file, and Luke judges by ear.
Born 25 Oct 2026 (Bob's cutscenes): Luke called the first pass "sloppy and very general".
Every cause was measurable and none was measured:

| What went wrong | The rule now |
|---|---|
| Picked by name: a bike horn for a gasp, a synth boink for "huh?", a crowd for 2 investors, a library desk with 41 conveyor clunks for an office | Search by role, read the full description, then measure (phrases, pitch shape) |
| Files open on dead air (laugh 0.52 s, door slam 0.44 s, wah-wahs up to 1.2 s): every hit landed late | Every sound has a measured `at` (where it starts) |
| Levels 31 dB apart; the music sat 20 dB over the cartoon sounds | Every sound has a `gain` (trim to -24 dB); beds sit 15 dB under events |
| A Sound made at its cue was still loading 0.12 s later: late or silent | Make every scene Sound up front and `PreloadAsync` the INSTANCES while loading |
| They laughed on screen to 9.6 s; the laugh sound ended at 7.8 | A sound covers the action it belongs to (a test checks it) |
| Voices chopped mid-note; the sting cut dead at the scene's end | `dur` always comes with a `fade`; ringing sounds fade out after the scene |
| The valley's birds sang inside the boardroom | World ambience is muted while a scene plays |

## Tools (from the game folder)

Python env: `C:\Users\lukex\.venvs\audio` (numpy, mutagen). Alias below: `PY=~/.venvs/audio/Scripts/python.exe`.

1. **Search, licensed libraries only** (Pro Sound Effects, APM: stable, no takedowns):
   `$PY tools/audio/sfx.py search "male laugh" --max-dur 6`. Search the library's own words:
   PSE names things like "Male Laugh", "Slide Whistle", "Record Scratch"; APM has comedy stings
   ("Shock Horror", "Trumpet Wah-Wah", album "MUSIC FOR COMEDY", "CLASSIC COMEDY"). Shortlist 3-6 per role.
2. **Load them in Studio** (Edit; this also makes Studio read each file) and save the result as
   `lengths.json`:
   ```lua
   local ids = { "9116452512", "9116452494" }   -- the shortlist
   local f, out, n = Instance.new("Folder", game:GetService("SoundService")), {}, 0
   for _, id in ipairs(ids) do
   	local s = Instance.new("Sound"); s.SoundId = "rbxassetid://" .. id; s.Parent = f; n += 1
   	task.spawn(function() local t = os.clock() while not s.IsLoaded and os.clock() - t < 15 do task.wait(0.05) end
   		out[id] = s.IsLoaded and s.TimeLength or nil; n -= 1 end)
   end
   while n > 0 do task.wait(0.1) end
   f:Destroy()
   return game:GetService("HttpService"):JSONEncode(out)
   ```
3. **Fetch** them from Studio's cache: `$PY tools/audio/sfx.py fetch lengths.json OUT --minutes 30`.
   It flags a guess. "newest of N read lately" means same-length files were loaded together: load
   that id ALONE and fetch again before trusting it.
4. **Measure**: `$PY tools/audio/sfx.py measure OUT <ids>` gives the phrases, pitch shape (rises/falls/level),
   loudness, and a ready line: `{ "<SfxKey>", at = .., len = .., gain = .. }`. For an impact use
   the printed hit time as `at`. Reject: a montage when you need one hit (many phrases), the wrong
   pitch shape (a "huh?" rises), an ambience with events in it (many phrases in a loop).
5. **Wire**: `Sfx.ID` gets the id with the recording's real name and what it is. `BobScript.SOUND`
   gets `{ key, at, len, gain }`. Cues are `{ t, name, vol, dur?, fade?, pitch? }`, beds
   `{ name, t0, t1, vol, fin?, fout?, duck? }`. A cue's `vol` is relative to the trimmed level.
6. **Check the mix**: `lune run tools/audio/plan_export plan.json` then
   `$PY tools/audio/sfx.py mixcheck plan.json OUT`. PASS = every event 5 dB or more over the
   beds and events within 15 dB of each other.
7. **Check it live**: the doctor's `bob` step (DoctorProbes.bobscene) fails if a scene sound is not
   loaded before it starts, if a playhead does not move on its cue, or if world ambience plays under it.

## Rules of a cartoon mix (what worked)

- Talking: one instrument voice for all (muted-trumpet wah-wah), a pitch per character, fade at the bubble's end.
- Music ducks under talking and STOPS on the gag beat (the record scratch); silence sells the next beat.
- One man's laugh per person on screen; the laugh lasts as long as the laughing pose.
- Stings (shock, cliffhanger) get the music out of the way first.

## Report honestly

Say which choices were measured and that none were heard. Ask Luke for the second a sound is wrong
("the laugh at 6 s") and fix that one.
