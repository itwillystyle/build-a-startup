# P-5 · Bob, the first boss investor: design

**Status:** draft for Luke's review, 25 Oct 2026.

**Inputs:**
- Brainstorm record: `research/p5-bob/BRAINSTORM.md`. Luke's answers are in his words.
- References: `research/p5-bob/REFERENCES.md`.
- Storyboards: `ui/storyboards/p5-bob/mp4/ALL-bob-storyboards.mp4`, built from `ui/storyboards/p5-bob/cartoon.js`.
  - Luke picked **option A, fast cuts** for the intro.
  - The payoff storyboard (D) was shown with no changes asked.
- Seminar notes that started this: `research/video-2026-10-24/NOTES.md`.

## 1. Why

- A Roblox game-review seminar (Tizzy Talk, 24 Oct) said three things again and again:
  - A cutscene in the first 60 s lowers bounce rate, the share of players who leave in 0-60 s and 60-180 s. Low bounce is how a game reaches Home recommendations.
  - Kids play longer when they have a reason, a story or a goal.
  - Curiosity (a locked door) keeps them going.
- Today's new-player intro (`IntroClient`, v4.9) is a 3-5 s camera descent with no story. The game gives no reason why you build the company.
- Luke's hook: "to prove that you can make it big in silicon valley and prove the people who abandoned you wrong."

**Success:**
- Luke watches the live intro and says it is funny and not slow.
- Creator Hub bounce rate (0-60 s) for new players goes down, compared over 14 days before and after the publish. Weekends run high, so compare full weeks.
- Most new players watch the intro instead of skipping it. Measured by our own telemetry: the second they pressed SKIP, or "watched to the end".

## 2. Goals, non-goals, anti-goals

**Goals**
1. A story intro for new players, 15-17 s, option A, that ends with the player at their own laptop in control.
2. Bob, a recurring villain kids remember:
   - a fat guy in a suit
   - sunglasses
   - a gold toothpick
   - the name "Bob"
3. Bob's building is a real place in the world. It's locked (taped door) until the payoff, for curiosity.
4. The goal card at HQ 1-3 frames the goal as "PROVE BOB WRONG", with progress to HQ 4.
5. The payoff at HQ 4 replaces how the Series A opens. Bob's door opens and a 17 s cutscene plays. You show your REVENUE chart, Bob throws triple money, you kick him out, and victory music plays. You get the Series A money.

**Non-goals (not in this project)**
- The investor ladder after Bob, with harder investors and perks. That is P-8, a separate project.
- Voices. Speech bubbles only.
- Replaying the intro from a menu. Leave room for it, but don't build it.
- Changing the returning-player WELCOME BACK card.

**Anti-goals (a failure even if it works)**
- An intro that feels slow, or runs over 20 s. Luke skips at "about 15 to 20 seconds".
- Anything that blocks the player. SKIP must work from the first frame, on phone and PC.
- Tobacco of any kind. Roblox's Community Standards ban depicting tobacco. The gold toothpick replaced Luke's cigar on purpose.
- Bob looking like a parody of a real, named person.
- A second goal on screen next to the HQ goal. The one-instruction rule (#80) allows one voice.
- The intro replaying on death, respawn or rejoin.

## 3. What the player sees

### 3a. The intro (new players only), option A, about 16 s

It shows after PLAY (the attribute `MenuDone`). It never shows when `Returning` is true, the same gate the current flyover uses. It replaces the v4.9 flyover for new players.

| # | Time | Shot | Words (bubbles) | Faces |
|---|---|---|---|---|
| 1 | 0-3.4 s | Wide, Bob's boardroom: Bob and two investors behind a long table, a city window behind them. The player stands across the room. | Player: "Can I get an offer?" | player hopeful; Bob smug |
| 2 | 3.4-6.2 s | Close on Bob, slow push in | Bob: "HA! An OFFER?" Then the investors: "HAHAHA!" | Bob and the investors laughing, shaking |
| 3 | 6.2-9.0 s | Outside Bob's door. The door bursts open, Bob kicks, the player flies out spinning and lands on the sidewalk. A "BOING!" pops, the door slams, and the player sits up. | (none) | Bob laughing; player shocked, then dizzy, then sad |
| 4 | 9.0-12.0 s | Two quick cuts: the player walks the street sad under a small rain cloud, then walks into their own garage | (none) | sad |
| 5 | 12.0-16.2 s | Garage: the laptop opens and glows, the player turns determined, slow push in. The letterbox slides away, the goal card drops in, and control hands over. | Player: "He will rue the day." | determined |

- Hard cuts between shots. A short screen shake on the kick, and none under Reduce Motion (see 5).
- The hero is **the player's own avatar**. It must also look right for avatars with dynamic heads, classic heads, layered clothing and unusual body scales.
- Faces change through the shots: hopeful, sad, shocked, dizzy, determined.

### 3b. Bob

- Body: a fat man in a dark suit with a red tie, black sunglasses, slicked dark hair, a gold toothpick in the corner of his mouth.
- He's built for this game, not a catalog avatar of a real person.
- Expressions he needs: smug, laughing, shocked (sunglasses fly off, the toothpick drops, the jaw drops), dizzy.
- His two investors are plain suits. They laugh in the intro and are shocked in the payoff.
- Name shown in bubbles and the goal card: "Bob".

### 3c. Bob's building

- A real building in the world. *My call:* downtown, beside the road the HQ 2 "Drive downtown to The Residences" task uses, so every player passes it early.
- A gold "BOB CAPITAL" sign over the door.
- The door is taped shut, yellow X tape, until the player reaches HQ 4. Touching it does nothing, or shows "Bob isn't taking meetings... yet."
- The intro's boardroom and the payoff's boardroom are the same room. *My call:* it's the inside of this building, so the payoff happens in the real place. The builder may instead use a hidden set if the real interior costs too much; see section 6.

### 3d. The goal card, HQ 1-3

- Today the big goal reads "HQ 2: COMPANY CAR / Upgrade your HQ: $X" (`Journey.milestone`).
- While HQ < 4 and the payoff hasn't happened, the card leads with **"PROVE BOB WRONG"**:
  - Bob's face icon
  - a bar showing HQ level N of 4
  - the next HQ step and its cost kept as the second line, so the player still knows what to do
- This **replaces** the milestone line. It does not add a second one (anti-goal).
- From HQ 4 on, the card is the normal goal again.

### 3e. The payoff, at HQ 4, about 17 s (storyboard D)

**Today:** at HQ 4 the Journey task is "seriesa". An investor texts you, you pitch on the phone, and the deal pays a Series A (boost x3). See `Phone.seriesA` and `SiliconCore` around line 1725.

**New, for the first time a save reaches HQ 4:**
1. The Series A text comes from **Bob**: "...Ok. I may have been hasty. Come to my office."
2. The goal says "Go to Bob's office", with the usual pin and beam.
3. Bob's tape is gone.
4. Walking into his door plays the payoff. **There is no choice and no pitch step** (Luke: "no choice, you take triple").

| # | Time | Shot | Words | Faces |
|---|---|---|---|---|
| 1 | 0-1.6 s | Outside: the tape rips off, the door opens, and the player walks in | (none) | player determined |
| 2 | 1.6-3.8 s | Wide boardroom: the player enters, Bob laughs | Bob: "What are YOU doing here?" | Bob laughing; player smug |
| 3 | 3.8-6.6 s | The player holds up a REVENUE chart, and the line draws upward | (none) | player smug |
| 4 | 6.6-9.0 s | Close on Bob: the sunglasses fly off, the toothpick drops | Bob: "W-WHAT?!" | Bob and the investors shocked |
| 5 | 9.0-11.4 s | Wide: Bob throws money at the player, a big "x3" shows, the cash pill counts up | Bob: "Take it! TAKE IT ALL!" | Bob shocked |
| 6 | 11.4-13.8 s | Outside: the player kicks Bob out of his own door. He flies, lands, "BOING!", the door slams, and he sits up dizzy. | (none) | player determined; Bob dizzy |
| 7 | 13.8-17 s | The player cheers in the doorway, with confetti, "PROVED WRONG!" and victory music. Then the letterbox goes and a toast shows "SERIES A CLOSED · x3". | (none) | player grinning |

- The money paid is the existing Series A amount: the same formula and the same caps (`capped(player, "series", ...)`). The cutscene doesn't decide money; the server does.
- The chart says **REVENUE**, not stock, because the company isn't public until HQ 5. Its shape is drawn and doesn't need real data. *My call:* if it's cheap, it uses the player's real income history.
- The payoff plays **once per save**. *My call:* a spun-off company that reaches HQ 4 again gets the old phone Series A. Later investors are P-8.

### 3f. After the payoff (Luke, 25 Oct)

- **The trophy, seen by everyone.**
  - Bob's gold toothpick on a small stand with the label **"BOB'S TOOTHPICK"**.
  - It sits in the player's own HQ, where visiting friends can see it. Luke: "in my HQ so friends can see it".
  - It's server-built from the saved `bobPaid` flag, so it replicates to everyone.
  - It must stay on every HQ rebuild and tower floor change.
  - It must pass the existing dressing checks: it never blocks a door, seat, station or glass (`OfficeLayout`).
  - *Left to the builder:* exactly where. Somewhere seen soon after walking in, e.g. the lobby.
- **Bob's building, client-side, only for the player who beat him.** Luke: "make that client-sided to the person who actually completed it."
  - For that player: the door stays open, the boardroom is empty, and Bob sits dizzy on the curb outside, with stars over his head.
  - Every other player sees the taped door and no Bob.
  - The local client changes only its own copy: the door's look, whether it's solid for that player, and Bob on the curb. The server's world is unchanged.
  - Two players at the door can see different things. That is intended.

## 4. Sound

| Moment | Sound |
|---|---|
| Intro under the shots | short, bouncy cartoon music |
| Shot 2 | Bob's laugh |
| The kick | a big "boing" |
| The landing | a thud |
| Payoff shot 5 | money whoosh / coins |
| Payoff shot 7 | victory music |

- Use only sounds the game is allowed to use: Roblox Creator Store audio, or the game's own uploads.
- Every sound obeys the game's existing volume settings.

## 5. Rules the build must keep

These come from the existing code, the references and Luke.
- **Skippable from frame 1.** Use `Cine`'s SKIP behaviour: on touch it sits above the jump button, and a tap anywhere skips. The reference research suggests top-right; Cine's tested placement wins unless the builder finds it hidden. Skipping jumps to the exact end state: the player at the laptop with control, and the goal card up. For the payoff, it skips to the money paid and Bob gone.
- **Hand the camera back as Custom + the humanoid,** never a stored Scriptable camera (Cine's rule).
- **Reduce Motion** (`UIKit.reducedMotion()`, `MotionSpec.camera`):
  - no screen shake
  - no slow camera pushes; each shot holds still
  - hard cuts stay
  - the motion guard spec must pass (`-- motion: camera` lines)
- **Client-only show.** Each player sees their own cutscene. Nothing about it replicates or changes other players' view. FaceControls are not replicated, so faces are driven on the client.
- **The server owns the money and the "payoff seen" flag** (saved in the session/DataStore). A client can't trigger a payout.
- **Nothing blocks the game.** No input lock beyond the camera while it plays; the game keeps running.
- **One voice.** The goal card and phone banners stay quiet during a cutscene (OneVoice / `Cine.busy()`).
- **First impression is never night.** Keep the v5 clock override for the intro.
- **Performance.** Bob's building and its dressing stay inside the plaza triangle and draw budgets (500k tris / 400 draws, see #81) and use the far-hiding rule.

## 5b. Settled after the builder check (Claude's calls, 25 Oct; Luke can overrule)

1. **Keys and clicks don't skip the story intro.** Today Cine skips on any keyboard or mouse input (Cine.lua around lines 100-103). For this intro only:
   - Only the SKIP button (and a tap on touch) skips.
   - The character can't move for its ~16 s.

   Why: a new player pressing W in second one would end the story they never saw, and the "most players watch it" measure would only count key presses. This narrows "nothing blocks" in section 5 to "nothing blocks after the cutscene, and SKIP always works".
2. **The payoff pays the best Series A the phone could have given:** interest 8, the `seriesPush` cap (35% of the next goal), and the "frontpage" item that interest 8 earns. Why: Bob "throws the money", so it should feel like the best deal, and these numbers are the top of a range the sim already tuned. The offline test pins this amount to `Phone`'s own formula with those inputs.
3. **Only new saves get Bob.** A save created after this ships gets a saved flag (`bobArc`, added to `Journey.J.FLAGS`) when its intro plays or is skipped. Only saves with that flag see:
   - "PROVE BOB WRONG"
   - Bob's tape
   - Bob's text
   - the payoff

   Every older save, and every spun-off company, keeps today's phone Series A. Bob's building still stands for them, taped shut. A second saved flag, `bobPaid`, marks the payoff done; it is never cleared by a spin-off. Why: a returning player never saw the intro, so Bob would make no sense to them, and `jr.seriesA` is cleared on spin-off.
4. **The goal card counts floors, not "HQ".** The live game shows floors (`Econ.WAFERS`), and HQ 4 = floor 13 (`WaferPlan.STAGE_AT = {5, 9, 13, 18}`).
   - The card reads "PROVE BOB WRONG", with the second line "Floor N of 13 · his door opens at 13".
   - The bar fills with every floor built.

   Everywhere this document says "HQ 4", read "floor 13 / the HQ 4 stage".
5. **Release order (Luke's call, since publishing is his):** publish today's main (#72-#82) before this ships. That gives a clean baseline for the 14-day bounce-rate comparison.

## 6. Left to the builder

- How the player's avatar is staged:
  - a clone made with `Players:CreateHumanoidModelFromDescription` or `CreateHumanoidModelFromUserId`, or
  - the real character, moved and hidden

  It must handle every body type.
- How faces change:
  - classic heads: swap the face decal
  - dynamic heads: a facial animation or FaceControls on the client

  Pick what works, and test both kinds of head.
- How the kick, the laugh, the walk and the fall move: uploaded animations or code-driven poses. Animations owned by Wilz need "share access" the first time.
- Whether the boardroom is the real interior or a hidden set (section 3c), and where exactly Bob's building stands.
- Exact camera positions, exact bubble wording beyond the lines above, and the music tracks.
- How the goal card shows Bob, as long as it stays one card (section 3d).

## 7. How it is checked

- Offline tests (pure modules):
  - the intro gate: new = plays, returning = never
  - the goal-card text at HQ 1, 2, 3, then normal at 4
  - the payoff runs once per save
  - money comes from the server formula
- The game doctor gets a step: a new save plays the intro to the end and skips it once, with 0 script errors and the camera back to Custom. Same for the payoff at HQ 4.
- Live check in Studio: a fresh Wilz save watches the whole intro; a save at HQ 4 walks into Bob's door.
- Telemetry: intro started / skipped at second N / finished; payoff played.
- Luke's look check on the live build: "funny, not slow", option A as storyboarded.
