#!/usr/bin/env bash
# Check every rule in JoinScreen.tla with TLC, one rule per run, and print each break's event order.
# One worker, so each break is the shortest order (TLC searches breadth-first).
# Needs Java and tla2tools.jar (TLA_JAR, default ~/Tools/tla/tla2tools.jar).
set -u
cd "$(dirname "$0")"
JAR="${TLA_JAR:-$HOME/Tools/tla/tla2tools.jar}"
WORK="$(mktemp -d)"
RULES="OneScene SceneOwnsScreen QuietScene OneIntro NewMeetsBob HudBack"
broken=0
for rule in $RULES; do
  printf 'SPECIFICATION Spec\nINVARIANT %s\n' "$rule" > "$WORK/$rule.cfg"
  java -XX:+UseParallelGC -cp "$JAR" tlc2.TLC -deadlock -workers 1 \
    -config "$WORK/$rule.cfg" -metadir "$WORK/meta-$rule" JoinScreen > "$WORK/$rule.txt" 2>&1
  if grep -q "is violated" "$WORK/$rule.txt"; then
    broken=$((broken + 1))
    steps=$(grep -oE "^State [0-9]+: <[A-Za-z]+" "$WORK/$rule.txt" | sed -E 's/State [0-9]+: <//' | tr '\n' ' ')
    echo "BROKEN  $rule: $steps"
  elif grep -q "No error has been found" "$WORK/$rule.txt"; then
    echo "holds   $rule ($(grep -oE "[0-9]+ distinct states found" "$WORK/$rule.txt" | tail -1))"
  else
    echo "ERROR   $rule: TLC did not finish, see $WORK/$rule.txt"; broken=$((broken + 1))
  fi
done
echo "full output: $WORK"
exit $broken
