#!/usr/bin/env bash
# tests/test_iw_parse.sh — exercise the awk parsers against a captured
# `iw phy info` sample (Realtek RTL8852BE).  Guards the parsing logic that
# differs between wireless cards.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HERE/bin/wifi-hotspot"
SAMPLE="$HERE/tests/samples/iw-phy-rtl8852be.txt"
[ -r "$SAMPLE" ] || { echo "missing sample: $SAMPLE"; exit 1; }

# Extract an awk script assigned as _NAME_AWK='...' (single-quoted, multi-line).
extract() {
  python3 - "$SRC" "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
name = sys.argv[2]
m = re.search(r"^" + name + r"='(.*?)'\n", src, re.M | re.S)
if not m:
    sys.exit("not found: " + name)
sys.stdout.write(m.group(1))
PY
}

COMBOS_AWK=$(extract _COMBOS_AWK)
RANGES_AWK=$(extract _RANGES_AWK)

echo "=== combos (APSTA P2PGO CHANNELS TOTAL) ==="
out=$(awk "$COMBOS_AWK" "$SAMPLE")
echo "$out"
# Each line: APSTA P2PGO CHANNELS TOTAL (four fields).
n=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  [[ "$line" =~ ^[01]\ [01]\ [0-9]+\ [0-9]+$ ]] || { echo "FAIL: bad combos line: $line"; exit 1; }
  n=$((n+1))
done <<< "$out"
[ "$n" -ge 1 ] || { echo "FAIL: no combos parsed"; exit 1; }
echo "ok: combos output well-formed ($n combo(s))"

echo
echo "=== host ranges ==="
out=$(awk "$RANGES_AWK" "$SAMPLE")
echo "$out"
# Each line: band first-last flag
[ -n "$out" ] || { echo "FAIL: no ranges parsed"; exit 1; }
while IFS= read -r line; do
  [[ "$line" =~ ^(bg|a|6g)\ [0-9]+-[0-9]+\ (DFS|-)$ ]] || { echo "FAIL: bad range line: $line"; exit 1; }
done <<< "$out"
echo "ok: ranges output well-formed"

echo
echo "=== freq_flags (2412 MHz) ==="
FREQFLAGS_AWK=$(extract _FREQFLAGS_AWK)
out=$(awk -v want=2412 "$FREQFLAGS_AWK" "$SAMPLE")
echo "  -> $out"
# Should mention the channel is usable (no 'disabled'/'no IR' would have skipped it)
[ -n "$out" ] || { echo "FAIL: no freq flags for 2412"; exit 1; }
echo "ok: freq_flags output non-empty"

echo
echo "=== ALL IW PARSE TESTS PASSED ==="