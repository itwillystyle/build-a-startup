#!/usr/bin/env bash
# Check every rule in JoinScreen.tla with TLC, one rule per run, and print each break's event order.
# Two passes: FIX=FALSE (main before the 2 Nov fixes) must break every rule but HudBack, so the model
# still sees the bugs; FIX=TRUE (the code now) must hold all six. Exit 0 only when both are true.
# One worker, so each break is the shortest order (TLC searches breadth-first).
# Needs Java and tla2tools.jar (TLA_JAR, default ~/Tools/tla/tla2tools.jar).
set -u
cd "$(dirname "$0")"
JAR="${TLA_JAR:-$HOME/Tools/tla/tla2tools.jar}"
WORK="$(mktemp -d)"
RULES="OneScene SceneOwnsScreen QuietScene OneIntro NewMeetsBob HudBack"
bad=0
for fix in FALSE TRUE; do
  echo "--- FIX=$fix"
  for rule in $RULES; do
    printf 'SPECIFICATION Spec
CONSTANT FIX = %s
INVARIANT %s
' "$fix" "$rule" > "$WORK/$rule-$fix.cfg"
    java -XX:+UseParallelGC -cp "$JAR" tlc2.TLC -deadlock -workers 1       -config "$WORK/$rule-$fix.cfg" -metadir "$WORK/meta-$rule-$fix" JoinScreen > "$WORK/$rule-$fix.txt" 2>&1
    if grep -q "is violated" "$WORK/$rule-$fix.txt"; then
      steps=$(grep -oE "^State [0-9]+: <[A-Za-z]+" "$WORK/$rule-$fix.txt" | sed -E 's/State [0-9]+: <//' | tr '
' ' ')
      echo "BROKEN  $rule: $steps"
      [ "$fix" = TRUE ] && bad=$((bad + 1))
      [ "$fix" = FALSE ] && [ "$rule" = HudBack ] && bad=$((bad + 1))
    elif grep -q "No error has been found" "$WORK/$rule-$fix.txt"; then
      echo "holds   $rule ($(grep -oE "[0-9]+ distinct states found" "$WORK/$rule-$fix.txt" | tail -1))"
      [ "$fix" = FALSE ] && [ "$rule" != HudBack ] && { echo "        (expected this rule to break with the fixes off)"; bad=$((bad + 1)); }
    else
      echo "ERROR   $rule: TLC did not finish, see $WORK/$rule-$fix.txt"; bad=$((bad + 1))
    fi
  done
done
echo "full output: $WORK"
exit $bad
