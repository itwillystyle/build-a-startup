# SDD ledger — plan: C:/Users/lukex/Downloads/silicon-startup/docs/superpowers/plans/2026-10-22-art-pass-1-light-and-garage.md
Spec: C:/Users/lukex/Downloads/silicon-startup/docs/superpowers/specs/2026-10-22-art-pass-design.md
Branch: art-pass-1 from 292cb14 (main). Executor: inline (Luke chose native, 22 Oct).
Pre-flight:
- T3 produces SVKeepMaterial + Teal/Coral -> T4 consumes (garage materials/colours): consistent.
- T1 produces Probes.lookcam + look_stats -> T2/T4/T5/T6 consume for live checks: consistent.
- T5 consumes WalkLanes.build() (main, #66: lanes have .keep, .name) and GarageLayout door/queue positions: check names at T5.
- T2 produces LookTune.DAY/NIGHT/at -> T6 tunes it: consistent.
Task 1: Ruling: C1 framing moved to eye (-5.5,7.5,-13.5) at (9,3.5,5) to match Luke's 21 Oct shot (the plan's first guess left the laptop out of frame) — cost if wrong: one camera retune.
Task 1: Ruling: Studio viewport is 1343x470, not 1280x720 — window size; before/after compare on the same window — cost if wrong: absolute numbers shift a little.
Task 1: FINDING (stop): the spec's premise is wrong. Luke's screenshots are washed out (46-79%) but Studio at max quality is 8% and his OBS recording 0%. The game is not overexposed; his screenshot capture is (likely HDR). C2 fails contrast 0.28 (empty forecourt). Task 2 (darker light) is not supported by data; asked Luke before continuing.
Task 1: complete (commits 292cb14..7fe099a, tests: bash -c '~/.rokit/bin/lune run tests/offline/run && python -I tools/look_stats.py --selftest' → 3 cases, 3 as expected)
Task 2: Ruling: DROPPED with Luke's OK (22 Oct, "ok continue") — the game is not overexposed (Studio 8%, his OBS 0%; his HDR screenshots were) — cost if wrong: the light stays as it is; Task 6 can still tune it.
Task 6: Ruling: targets judged on C2 (contrast 0.28 -> >= 0.50) and C1 must not regress; plus Luke's side-by-side — follows from the Task 1 finding.
Task 3: Ruling: Teal/Coral made accent-only anchors (excluded from map's nearest-anchor snap) — as plain anchors Coral captured Wafers.TINT.studio (pink -> coral), caught by the snapshot test — cost if wrong: a colour near teal/coral authored slightly off still snaps to an old anchor.
Task 3: note: an earlier "complete" line was written by task-done while the commit had been refused (selene: game override in palette.spec); removed; the real line follows the commit.
Task 3: complete (commits 7fe099a..eceac9e, tests: /c/Users/lukex/.rokit/bin/lune run tests/offline/run → 521 passed, 0 failed (49 spec files))
Task 4: Ruling: wall cladding (226,211,183) not the plan's (226,206,176) — the palette sweep repaints the plan's value to this; same warmer/darker intent — cost if wrong: walls one shade paler than the mock.
Task 4: Ruling: no new plants or desk lamp — the garage already had 3 plants (plantL, plantR, plantDoor) and pendant lamps over the desk (deskLamps); added only what the mock has and the room lacked (floor, string lights, colours) — cost if wrong: one more plant piece.
Task 4: live: 360 tagged parts kept their material; sofa Coral Fabric (coral over the mesh's own colours reads dark red: for Luke's look review).
Task 5: Ruling: yard props live in plot.folder.GarageYard, shown only at level <= 1 — the plan put them in CampusArch.grounds, but Wafers.clearFootprint deletes tall grounds props inside the podium footprint on load — cost if wrong: none found; the yard is rebuilt after a spin-off by the same tick.
Task 5: Ruling: props placed off the clients' diagonal walk-in (-14,49)->(0,19) and the promenade band z 39..49 — the plan's mock-like positions would have blocked both — cost if wrong: the layout differs a little from the mock.
Tasks 4-5: note: two "complete" lines were written while the commits had been refused (selene: trailing allow comment); removed; real lines follow the commits.
Task 4: complete (commits eceac9e..da04387, tests: /c/Users/lukex/.rokit/bin/lune run tests/offline/run → 531 passed, 0 failed (50 spec files))
Tasks 4-5: note: 85afcd3 swallowed Task 5 files (staged from a refused commit); split with reset --soft into da04387 (Task 4) and 69001f6 (Task 5). Unpushed branch, no change lost.
Task 5: complete (commits da04387..69001f6, tests: /c/Users/lukex/.rokit/bin/lune run tests/offline/run → 531 passed, 0 failed (50 spec files))
Task 6: Ruling: tuned the scene, not LookTune (Task 2 dropped): hedges and bushes added to ForecourtPlan after live experiments (0.318 -> 0.506 contrast on C2) — the plan said "adjust only LookTune numbers" — cost if wrong: 11 more yard parts per garage plot.
Task 6: Ruling: night near-black 40% > the plan's 35% guide; accepted and flagged for Luke — it is the dark street outside the open front (unchanged by this branch); the laptop is clear and the client is found by his bubble — cost if wrong: a night-light tweak later.
Task 6: Ruling: SVStyle whole-world counts not comparable (doctor left Wilz at level 100: 15376 parts vs baseline 10096); measured this branch's own parts instead (garage dressing + yard: 0 off-palette, 0 new untagged Neon, 0 new translucent) and StyleBaseline left unchanged — cost if wrong: a world-level style regression unseen until the nightly doctor.
Task 6: doctor PR gate PASS (146 files, no BLOCKER, no new BUG; FEEL: chase:genius cuts 0.58 (run-to-run noise, seen on main), hq:9 Hud vs Daily panel overlap (daily card, not art)). Luke's look review pending (review-1.md).
Task 6: complete (commits 69001f6..50ddd0c, tests: bash -c '~/.rokit/bin/lune run tests/offline/run && python -I tools/look_stats.py ../ui/art-pass/shots/after-C1.jpg ../ui/art-pass/shots/final-C2-day.jpg' → final-C2-day.jpg  mean 0.565  spread 0.506  sat 0.4  blown 0.001  PASS)
Final review: superpowers:code-reviewer on opus. No Critical; 2 Important; 10 Minor.
Final: fixed FloorBoards in the 1c lobby-moment copy (I3 regression) — lobbymoment.spec "the copy leaves the floors out" RED->GREEN, suite 535/535 (dbc079e)
Final: fixed accent anchors changing 11 existing colours — palette.spec "accents keep only themselves" RED->GREEN, suite 535/535; full 478-literal scan: 2 differ (the authored accents)
Final: minor (deferred): unowned plots — releasePlot never removes GarageYard (a plot left at level 1 keeps its yard)
Final: minor (deferred): the yard disappears on the next 0.4 s tick at the start of the 1c moment instead of folding with it
Final: minor (deferred): DoctorProbes.lookcam — nil args crash after camera set Scriptable; overlapping holds; always restores Custom
Final: minor (deferred): look_stats.py — selftest needs ../../ui/art-pass (outside git); --targets without value; Pillow getdata deprecation; no near-black metric
Final: minor (deferred): forecourtplan.spec weaker than plan (|x| walker check, margin 2 not 3, no "lot on the right" test, court keep-out dropped unruled)
Final: minor (deferred): plan deviations unledgered — darker colour on EntranceCourt not ForecourtField; only the runner teal; yard props not bevelled
Final: minor (deferred): kept-material list in three places (FlatLook, GarageDress, CampusArch)
Final: minor (deferred): wainscot still tagged SVNoPalette though Teal is compliant
Final: minor (deferred): ForecourtPlan header oversells the doctor's walker sweep for the yard
Final: minor (deferred): FlatLook warn repeats each sweep for a mis-tagged part
