"""Used by hooks/pre-commit: reads file names (one per line) on stdin and prints
one line per file that is not valid UTF-8, with the offending byte and offset."""
import sys

bad = []
for name in sys.stdin.read().splitlines():
    name = name.strip()
    if not name:
        continue
    try:
        data = open(name, "rb").read()
    except OSError:
        continue
    try:
        data.decode("utf-8")
    except UnicodeDecodeError as e:
        bad.append("%s: invalid UTF-8 byte 0x%02X at offset %d" % (name, data[e.start], e.start))
print("\n".join(bad))
