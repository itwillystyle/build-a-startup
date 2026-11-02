---------------------------- MODULE JoinScreen ----------------------------
(* Who owns the player's screen around joining (2 Nov 2026).

   Idea from poteto (tibo.dog): model each system as states and events, and let
   TLC try every order of events. Every action below names the code it stands for
   (src/, at main b075433). C = StarterPlayer/StarterPlayerScripts.

   Parts that run at the same time:
     server load    SaveLoad.loadOnce: GetAsync, then Returning or BobNew (SaveLoad:422-439)
     IntroClient    waits MenuDone, reads Returning (:150), later BobNew (:295),
                    fires Bob's intro and waits up to 15 s for it (:298-307), else flies over (:312)
     Bob scene      BobSceneClient play(): loading -> playing -> done | failed (:590-980)
     Cine           the fly-over / welcome-back camera (ReplicatedStorage/Cine.lua:166-244)
     popups         Daily (DailyClient:305-316) and the phone ring (PhoneClient:1230-1243)
                    go through Notify, whose only idea of a cutscene is Cine.busy() (Notify:274)
     Guide          its gui turns on whenever it has a goal and no menu is open (GuideClient:714),
                    re-run when the one-voice changes (:730-736)
*)
EXTENDS FiniteSets

\* FIX = TRUE is the code after the 2 Nov fixes; FALSE is main at b075433. check.sh runs both:
\* with FIX off the five rules must break (the model still sees the bugs), with it on all six hold.
CONSTANT FIX

Guis  == {"Hud", "Guide", "Daily", "Ring"}
Menus == {"Daily"}                      \* UIKit.MENUS: Cine does not reopen these (Cine:240-242)

VARIABLES
    kind,        \* the save: "new" or "returning" (fixed for a run)
    data,        \* "pending" until GetAsync returns, then "loaded"
    menuDone,    \* MenuDone attribute (set when the client fires it, not tied to the load)
    intro,       \* IntroClient: "waitMenu" -> "build" -> "waitBob" -> "done"
    introOwns,   \* the intro's fire started a scene (play() returned false = no state, :590)
    bob,         \* "idle" | "loading" | "playing" | "done" | "failed"
    bobWhy,      \* "none" | "intro" | "payoff"
    cine,        \* "idle" | "fly" | "welcome"
    on,          \* ScreenGuis that are Enabled
    bobHidden,   \* the scene's `hidden` list (:748-750, grown per frame :1025-1030)
    cineHidden,  \* Cine's snapshot (:178-183)
    ringing,     \* the phone's ring sound loops (PhoneClient:1201-1209)
    dailyDone, ringDone, payoffFired,
    introBob,    \* Bob's intro reached "playing"
    flew,        \* the new-player fly-over played
    stale        \* guis still on right after the scene's per-frame hide ran

vars == <<kind, data, menuDone, intro, introOwns, bob, bobWhy, cine, on, bobHidden,
          cineHidden, ringing, dailyDone, ringDone, payoffFired, introBob, flew, stale>>

Init ==
    /\ kind \in {"new", "returning"}
    /\ data = "pending"
    /\ menuDone = FALSE
    /\ intro = "waitMenu" /\ introOwns = FALSE
    /\ bob = "idle" /\ bobWhy = "none"
    /\ cine = "idle"
    /\ on = {"Hud", "Guide"}
    /\ bobHidden = {} /\ cineHidden = {}
    /\ ringing = FALSE /\ dailyDone = FALSE /\ ringDone = FALSE /\ payoffFired = FALSE
    /\ introBob = FALSE /\ flew = FALSE /\ stale = {}

Loaded == data = "loaded"

\* Cine.play: refuses while it is already playing (:169), hides every Enabled gui (:178-183).
\* FIX: it also refuses while a Bob scene holds the screen (Cine.screenTaken)
CinePlay(why) ==
    IF cine = "idle" /\ ~(FIX /\ bob = "playing")
    THEN /\ cine' = why /\ cineHidden' = on /\ on' = {}
         /\ flew' = (flew \/ why = "fly")
    ELSE UNCHANGED <<cine, cineHidden, on, flew>>

\* ---------------------------------------------------------------- server and menu
ServerLoads ==
    /\ data = "pending" /\ data' = "loaded"
    /\ UNCHANGED <<stale, kind, menuDone, intro, introOwns, bob, bobWhy, cine, on, bobHidden,
                   cineHidden, ringing, dailyDone, ringDone, payoffFired, introBob, flew>>

MenuDone ==   \* SiliconCore:4396-4399, MenuClient:19
    /\ ~menuDone /\ menuDone' = TRUE
    /\ UNCHANGED <<stale, kind, data, intro, introOwns, bob, bobWhy, cine, on, bobHidden,
                   cineHidden, ringing, dailyDone, ringDone, payoffFired, introBob, flew>>

\* ---------------------------------------------------------------- IntroClient
IntroReadsReturning ==   \* :144-158: Returning read once; nil (not loaded yet) reads as false.
                         \* FIX: the intro first waits for the server's SaveLoaded
    /\ intro = "waitMenu" /\ menuDone
    /\ (FIX => Loaded)
    /\ IF kind = "returning" /\ Loaded
       THEN /\ CinePlay("welcome") /\ intro' = "done"
       ELSE /\ intro' = "build" /\ UNCHANGED <<cine, cineHidden, on, flew>>
    /\ UNCHANGED <<stale, kind, data, menuDone, introOwns, bob, bobWhy, bobHidden, ringing,
                   dailyDone, ringDone, payoffFired, introBob>>

IntroFiresBob ==   \* :295-312: BobNew read now; not true -> fly-over at once
    /\ intro = "build"
    /\ IF kind = "new" /\ Loaded
       THEN /\ intro' = "waitBob"
            /\ IF bob \in {"idle", "done", "failed"}
               THEN bob' = "loading" /\ bobWhy' = "intro" /\ introOwns' = TRUE
               ELSE UNCHANGED <<bob, bobWhy, introOwns>>      \* play() returns false, no state
            /\ UNCHANGED <<cine, cineHidden, on, flew>>
       ELSE /\ intro' = "done" /\ CinePlay("fly")
            /\ UNCHANGED <<bob, bobWhy, introOwns>>
    /\ UNCHANGED <<stale, kind, data, menuDone, bobHidden, ringing, dailyDone, ringDone,
                   payoffFired, introBob>>

IntroGivesUp ==   \* :301-312: no state, still "loading" after 15 s, or "failed" -> fly-over.
                  \* FIX: it keeps waiting while Bob loads (his loading ends by itself: cast 10 s + sounds 6 s)
    /\ intro = "waitBob"
    /\ IF FIX THEN (~introOwns \/ bob = "failed") ELSE (~introOwns \/ bob \in {"loading", "failed"})
    /\ intro' = "done" /\ CinePlay("fly")
    /\ UNCHANGED <<stale, kind, data, menuDone, introOwns, bob, bobWhy, bobHidden, ringing,
                   dailyDone, ringDone, payoffFired, introBob>>

IntroSeesBobDone ==   \* :303-310: it waited while "playing"; "done" skips the fly-over
    /\ intro = "waitBob" /\ introOwns /\ bob = "done"
    /\ intro' = "done"
    /\ UNCHANGED <<stale, kind, data, menuDone, introOwns, bob, bobWhy, cine, on, bobHidden,
                   cineHidden, ringing, dailyDone, ringDone, payoffFired, introBob, flew>>

\* ---------------------------------------------------------------- Bob scene
BobStarts ==   \* :730-750: playing; every Enabled gui is hidden into `hidden`. No Cine check.
               \* FIX: it waits for a Cine shot to end before it takes the screen
    /\ bob = "loading"
    /\ (FIX => cine = "idle")
    /\ bob' = "playing" /\ bobHidden' = on /\ on' = {} /\ stale' = {}
    /\ introBob' = (introBob \/ bobWhy = "intro")
    /\ UNCHANGED <<kind, data, menuDone, intro, introOwns, bobWhy, cine, cineHidden,
                   ringing, dailyDone, ringDone, payoffFired, flew>>

BobFails ==   \* :593-611, :689-695: flag off, cast missing, setup error
    /\ bob = "loading" /\ bob' = "failed"
    /\ UNCHANGED <<stale, kind, data, menuDone, intro, introOwns, bobWhy, cine, on, bobHidden,
                   cineHidden, ringing, dailyDone, ringDone, payoffFired, introBob, flew>>

BobFrame ==   \* :1025-1030: hides an Enabled gui only if it is NOT already in `hidden`.
              \* FIX: it hides every Enabled gui, listed or not
    /\ bob = "playing"
    /\ on /= {}
    /\ bobHidden' = bobHidden \cup on
    /\ on' = IF FIX THEN {} ELSE on \cap bobHidden
    /\ stale' = on'
    /\ UNCHANGED <<kind, data, menuDone, intro, introOwns, bob, bobWhy, cine, cineHidden,
                   ringing, dailyDone, ringDone, payoffFired, introBob, flew>>

BobEnds ==   \* putBack :718-727: every gui in `hidden` Enabled = true, menus included
    /\ bob = "playing"
    /\ bob' = "done" /\ on' = on \cup bobHidden /\ bobHidden' = {} /\ stale' = {}
    /\ UNCHANGED <<kind, data, menuDone, intro, introOwns, bobWhy, cine, cineHidden,
                   ringing, dailyDone, ringDone, payoffFired, introBob, flew>>

PayoffFires ==   \* the door (SiliconCore:4171-4193): server checks carrying/seated only.
                 \* Held back until the intro is over (the story's arc starts with the intro,
                 \* SiliconCore:4205-4216), so no trace leans on a payoff before you have played
    /\ ~payoffFired /\ Loaded /\ intro = "done"
    /\ (introBob \/ kind = "returning")   \* the payoff needs the story's arc: you saw the intro (now or before)
    /\ payoffFired' = TRUE
    /\ IF bob \in {"idle", "done", "failed"}
       THEN bob' = "loading" /\ bobWhy' = "payoff"
       ELSE UNCHANGED <<bob, bobWhy>>
    /\ UNCHANGED <<stale, kind, data, menuDone, intro, introOwns, cine, on, bobHidden, cineHidden,
                   ringing, dailyDone, ringDone, introBob, flew>>

\* ---------------------------------------------------------------- Cine ends
CineEnds ==   \* handBack + re-enable the snapshot except menus (:234-244)
    /\ cine /= "idle"
    /\ cine' = "idle" /\ on' = on \cup (cineHidden \ Menus) /\ cineHidden' = {}
    /\ UNCHANGED <<stale, kind, data, menuDone, intro, introOwns, bob, bobWhy, bobHidden,
                   ringing, dailyDone, ringDone, payoffFired, introBob, flew>>

\* ---------------------------------------------------------------- popups (via Notify)
DailyOpens ==   \* DailyClient:305-316: unlocked for a returning save; Notify waits only for Cine.
                \* FIX: Notify's cutscene is Cine.screenTaken(), so it waits for a Bob scene too
    /\ ~dailyDone /\ kind = "returning" /\ Loaded /\ cine = "idle"
    /\ (FIX => bob /= "playing")
    /\ dailyDone' = TRUE /\ on' = on \cup {"Daily"}
    /\ UNCHANGED <<stale, kind, data, menuDone, intro, introOwns, bob, bobWhy, cine, bobHidden,
                   cineHidden, ringing, ringDone, payoffFired, introBob, flew>>

DailyCloses ==
    /\ "Daily" \in on /\ on' = on \ {"Daily"}
    /\ UNCHANGED <<stale, kind, data, menuDone, intro, introOwns, bob, bobWhy, cine, bobHidden,
                   cineHidden, ringing, dailyDone, ringDone, payoffFired, introBob, flew>>

RingStarts ==   \* PhoneClient:1230-1243: the ring sound starts with the call; the card goes through Notify
    /\ ~ringDone /\ Loaded
    /\ ringDone' = TRUE /\ ringing' = TRUE /\ on' = on \cup {"Ring"}
    /\ UNCHANGED <<stale, kind, data, menuDone, intro, introOwns, bob, bobWhy, cine, bobHidden,
                   cineHidden, dailyDone, payoffFired, introBob, flew>>

RingEnds ==
    /\ ringing /\ ringing' = FALSE /\ on' = on \ {"Ring"} /\ bobHidden' = bobHidden \ {"Ring"}
    /\ UNCHANGED <<stale, kind, data, menuDone, intro, introOwns, bob, bobWhy, cine, cineHidden,
                   dailyDone, ringDone, payoffFired, introBob, flew>>

\* ---------------------------------------------------------------- Guide
GuideSyncs ==   \* GuideClient:714: Enabled = has a goal and no menu open; no scene check
    /\ LET want == "Daily" \notin on
       IN /\ want /= ("Guide" \in on)
          /\ on' = IF want THEN on \cup {"Guide"} ELSE on \ {"Guide"}
    /\ UNCHANGED <<stale, kind, data, menuDone, intro, introOwns, bob, bobWhy, cine, bobHidden,
                   cineHidden, ringing, dailyDone, ringDone, payoffFired, introBob, flew>>

Next ==
    \/ ServerLoads \/ MenuDone
    \/ IntroReadsReturning \/ IntroFiresBob \/ IntroGivesUp \/ IntroSeesBobDone
    \/ BobStarts \/ BobFails \/ BobFrame \/ BobEnds \/ PayoffFires
    \/ CineEnds
    \/ DailyOpens \/ DailyCloses \/ RingStarts \/ RingEnds
    \/ GuideSyncs

Spec == Init /\ [][Next]_vars

\* ================================================================ the rules
\* R1 one camera owner: a Bob scene and a Cine move never run together (both write the camera every frame)
OneScene == ~(bob = "playing" /\ cine /= "idle")

\* R2 the scene owns the screen: a gui that turns on during the scene is gone after the next frame
SceneOwnsScreen == bob = "playing" => stale = {}

\* R3 no phone ringing under a Bob scene (a sound cannot be hidden).
\* FIX: the ring loop skips its tones while a scene holds the screen (PhoneClient ring)
Audible == ringing /\ ~(FIX /\ (bob = "playing" \/ cine /= "idle"))
QuietScene == bob = "playing" => ~Audible

\* R4 one intro: never Bob's intro AND the new-player fly-over; a returning save never gets the fly-over
OneIntro == ~(introBob /\ flew) /\ (kind = "returning" => ~flew)

\* R5 a new save meets Bob, unless his scene could not play
NewMeetsBob == (kind = "new" /\ intro = "done" /\ bob /= "failed") => introBob

\* R6 the HUD comes back when nothing holds the screen
HudBack == (bob \notin {"loading", "playing"} /\ cine = "idle" /\ intro = "done") => "Hud" \in on
=============================================================================
