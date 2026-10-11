#!/usr/bin/env bash
# routine.sh -- the only commands the scheduled routines run (11 Oct 2026).
#
# Every routine used to compose its own git and lune commands, so each run stopped
# at its first Bash call to ask for approval (the morning run sat there from 10:00
# on 10 and 11 Oct). One fixed script means one settings rule covers them all:
#     Bash(bash /c/Users/lukex/Downloads/silicon-startup/game-health/tools/routine.sh:*)
# It runs from the game-health worktree (always origin/main), so switching branches
# in the game folder never breaks a routine.
# Everything here reads, or writes only outside the repo (HEALTH.md, playtests/,
# DOCTOR.md) or posts the doctor's summary to Luke's own Discord channel.
# Never commits, pushes, merges or publishes.
#
#   routine.sh health                     the morning run (bas health on origin/main)
#   routine.sh playtest-list | playtest-prep
#   routine.sh playtest-done "<video>" [--skip] [--note "..."]
#   routine.sh checkup-report <report.json>   judge a game-doctor run -> DOCTOR.md
#   routine.sh checkup-post                   post DOCTOR's summary to Discord
#   routine.sh chase-tune [minutes]           start the chase tuner, detached (default 330 min)
#   routine.sh chase-tune-post                post the night's tuning to Discord
set -u
G=/c/Users/lukex/Downloads/silicon-startup/game
H=/c/Users/lukex/Downloads/silicon-startup/game-health
L="$USERPROFILE/.rokit/bin/lune.exe"

# a detached worktree on origin/main, so Luke's own checkout is never touched
fresh() {
	git -C "$G" fetch -q origin || return 1
	if [ ! -d "$H" ]; then git -C "$G" worktree add -q --detach "$H" origin/main || return 1; fi
	git -C "$H" checkout -q --detach origin/main || return 1
	mkdir -p "$H/.bas"
	if [ ! -f "$H/.bas/baseline.json" ] && [ -f "$G/.bas/baseline.json" ]; then cp "$G/.bas/baseline.json" "$H/.bas/"; fi
}

cmd="${1:-}"
[ $# -gt 0 ] && shift
case "$cmd" in
	health)         fresh && cd "$H" && "$L" run tools/bas health ;;
	playtest-list)  fresh && cd "$H" && "$L" run tools/bas playtest list ;;
	playtest-prep)  fresh && cd "$H" && "$L" run tools/bas playtest prep --new ;;
	playtest-done)  cd "$H" && "$L" run tools/bas playtest done "$@" ;;
	checkup-report) fresh && cd "$H" && "$L" run tools/bas checkup report "$@" ;;
	checkup-post)   cd "$H" && "$L" run tools/bas checkup post ;;
	# its own hidden process, so it outlives the routine's session; output in ../tuning/
	chase-tune)     fresh && mkdir -p "$H/../tuning" && powershell.exe -NoProfile -Command 	                  "Start-Process -WindowStyle Hidden -FilePath '$(cygpath -w "$L")' -WorkingDirectory '$(cygpath -w "$H")' -ArgumentList 'run','tools/chase_tune','--','--minutes','${1:-330}' -RedirectStandardOutput '$(cygpath -w "$H/../tuning")\chase-night.log' -RedirectStandardError '$(cygpath -w "$H/../tuning")\chase-night.err'" 	                  && echo "chase tuner started for ${1:-330} min: silicon-startup/tuning/chase-night.log" ;;
	chase-tune-post) cd "$H" && "$L" run tools/bas tune post ;;
	*) grep '^#   routine.sh' "$0"; exit 2 ;;
esac
