#!/usr/bin/env bash
# tests/test_mode_selection.sh — verify choose_mode picks the right mode
# especially that it only uses p2p when the channel truly cannot host an AP
# (not when it can host but needs DFS).
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HERE/bin/wifi-hotspot"
SAMPLE="$HERE/tests/samples/iw-phy-rtl8852be.txt"
export WIFI_HOTSPOT_IW_PHY_FILE="$SAMPLE"
FAIL=0

echo "=== test_mode_selection.sh ==="

# 1. When channel CAN host without DFS, choose same mode.
out=$(WIFI_HOTSPOT_TEST_MODE=1 bash -c '
  source "'"$SRC"'"
  MODE=auto
  CAN_HOST=1; HAVE_DFS=0; CAP_APSTA=1; CAP_P2PGO=1
  p2p_ready(){ return 0; }
  choose_mode
  echo "MODE_CHOSEN=$MODE_CHOSEN"
' 2>/dev/null)
if [ "$out" = "MODE_CHOSEN=same" ]; then
  echo "  ok: channel can host -> same mode"
else
  echo "  FAIL: expected same, got: $out"
  FAIL=1
fi

# 2. When channel CAN host but needs DFS, choose same mode (not p2p).
out=$(WIFI_HOTSPOT_TEST_MODE=1 bash -c '
  source "'"$SRC"'"
  MODE=auto
  CAN_HOST=1; HAVE_DFS=1; CAP_APSTA=1; CAP_P2PGO=1
  p2p_ready(){ return 0; }
  choose_mode
  echo "MODE_CHOSEN=$MODE_CHOSEN"
' 2>/dev/null)
if [ "$out" = "MODE_CHOSEN=same" ]; then
  echo "  ok: DFS channel can still host -> same mode (not p2p)"
else
  echo "  FAIL: expected same, got: $out"
  FAIL=1
fi

# 3. When channel CANNOT host and p2p is ready, choose p2p mode.
out=$(WIFI_HOTSPOT_TEST_MODE=1 bash -c '
  source "'"$SRC"'"
  MODE=auto
  CAN_HOST=0; HAVE_DFS=0; CAP_APSTA=1; CAP_P2PGO=1
  p2p_ready(){ return 0; }
  choose_mode
  echo "MODE_CHOSEN=$MODE_CHOSEN"
' 2>/dev/null)
if [ "$out" = "MODE_CHOSEN=p2p" ]; then
  echo "  ok: channel cannot host + p2p ready -> p2p mode"
else
  echo "  FAIL: expected p2p, got: $out"
  FAIL=1
fi

# 4. When channel CANNOT host but p2p is NOT ready, choose same mode
#    (but up_same will later die because CAN_HOST=0).
out=$(WIFI_HOTSPOT_TEST_MODE=1 bash -c '
  source "'"$SRC"'"
  MODE=auto
  CAN_HOST=0; HAVE_DFS=0; CAP_APSTA=1; CAP_P2PGO=1
  p2p_ready(){ return 1; }
  choose_mode
  echo "MODE_CHOSEN=$MODE_CHOSEN"
' 2>/dev/null)
if [ "$out" = "MODE_CHOSEN=same" ]; then
  echo "  ok: channel cannot host + p2p not ready -> same mode (will fail in cmd_up)"
else
  echo "  FAIL: expected same, got: $out"
  FAIL=1
fi

# 5. When WPA3, always choose same mode (even if channel cannot host).
out=$(WIFI_HOTSPOT_TEST_MODE=1 bash -c '
  source "'"$SRC"'"
  MODE=auto; SECURITY=wpa3
  CAN_HOST=0; HAVE_DFS=0; CAP_APSTA=1; CAP_P2PGO=1
  p2p_ready(){ return 0; }
  choose_mode
  echo "MODE_CHOSEN=$MODE_CHOSEN"
' 2>/dev/null)
if [ "$out" = "MODE_CHOSEN=same" ]; then
  echo "  ok: WPA3 -> same mode always"
else
  echo "  FAIL: expected same, got: $out"
  FAIL=1
fi

# 6. When channel CANNOT host, P2P not available, choose same mode
#    (but up_same will later die).
out=$(WIFI_HOTSPOT_TEST_MODE=1 bash -c '
  source "'"$SRC"'"
  MODE=auto
  CAN_HOST=0; HAVE_DFS=0; CAP_APSTA=1; CAP_P2PGO=0
  p2p_ready(){ return 0; }
  choose_mode
  echo "MODE_CHOSEN=$MODE_CHOSEN"
' 2>/dev/null)
if [ "$out" = "MODE_CHOSEN=same" ]; then
  echo "  ok: channel cannot host + no P2P -> same mode (will fail in cmd_up)"
else
  echo "  FAIL: expected same, got: $out"
  FAIL=1
fi

if [ "$FAIL" = "1" ]; then
  echo "=== TESTS FAILED ==="
  exit 1
fi
echo "=== ALL MODE SELECTION TESTS PASSED ==="
