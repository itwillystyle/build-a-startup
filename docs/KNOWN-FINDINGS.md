# Known findings

A doctor or morning-health finding that is open 3 runs in a row is listed in DOCTOR.md and
HEALTH.md under "fix it, or give a reason". Fix it, or add one line under Entries, with the
key in backticks exactly as the report prints it. A line looks like this (without "Example:"):

Example: - `bob / bob intro: nothing snaps inside a shot`: fixed in #94, live at the next Alt+P (7 Nov)

A line here silences that finding in the "fix it" list (it still shows, with its reason and
run count). That is as strong as editing a check, so this file is a judge (`bas risk` says
needs Luke) and Luke merges every change to it. When a finding stops showing up, the reports
say so: delete its line. Read by `tools/streak_lib.luau`; tested by `tests/offline/streak.spec.luau`.

## Entries

(none yet)
