"""Used by hooks/pre-commit: reads staged file names (one per line) on stdin and
checks the bytes that are STAGED (the index blob), not the working-tree copy, so
a file fixed in the editor but not re-added is still caught, and the reverse.

Exit 0: all valid. Exit 1: invalid UTF-8 found (one line per file on stdout).
Exit 2: could not read a staged blob (reported on stderr); the hook must fail."""
import subprocess
import sys

bad = []
errors = []
for name in sys.stdin.read().splitlines():
    name = name.strip()
    if not name:
        continue
    r = subprocess.run(["git", "show", ":" + name], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if r.returncode != 0:
        errors.append("%s: could not read staged blob (%s)" % (name, r.stderr.decode("utf-8", "replace").strip()))
        continue
    data = r.stdout
    try:
        data.decode("utf-8")
    except UnicodeDecodeError as e:
        bad.append("%s: invalid UTF-8 byte 0x%02X at offset %d" % (name, data[e.start], e.start))

if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(2)
if bad:
    print("\n".join(bad))
    sys.exit(1)
