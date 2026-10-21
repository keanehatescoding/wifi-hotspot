#!/usr/bin/env bash
# tests/test_wpa3_mode.sh — guard the WPA3-specific branches.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HERE/bin/wifi-hotspot"
FAIL=0

echo "=== test_wpa3_mode.sh ==="

# 1. choose_mode prefers hostapd when SECURITY=wpa3.
out=$(WIFI_HOTSPOT_SECURITY=wpa3 WIFI_HOTSPOT_TEST_MODE=1 bash -c '
  source "'"$SRC"'" 
  SECURITY=wpa3
  MODE=auto
  CAN_HOST=0; HAVE_DFS=1; CAP_APSTA=1; CAP_P2PGO=1
  p2p_ready(){ return 0; }
  choose_mode
  echo "MODE_CHOSEN=$MODE_CHOSEN"
' 2>/dev/null)
if [ "$out" = "MODE_CHOSEN=same" ]; then echo "  ok: choose_mode wpa3 -> same"; else echo "  FAIL: $out"; FAIL=1; fi

# wpa2/mixed still allow p2p fallback on a DFS uplink.
for sec in wpa2 mixed; do
  out=$(WIFI_HOTSPOT_SECURITY="$sec" WIFI_HOTSPOT_TEST_MODE=1 bash -c '
    source "'"$SRC"'"
    SECURITY="'"$sec"'"
    MODE=auto
    CAN_HOST=0; HAVE_DFS=1; CAP_APSTA=1; CAP_P2PGO=1
    p2p_ready(){ return 0; }
    choose_mode
    echo "MODE_CHOSEN=$MODE_CHOSEN"
  ' 2>/dev/null)
  if [ "$out" = "MODE_CHOSEN=p2p" ]; then echo "  ok: choose_mode $sec -> p2p"; else echo "  FAIL ($sec): $out"; FAIL=1; fi
done

# 2. up_p2p refuses wpa3 before touching dnsmasq.
set +e
out=$(WIFI_HOTSPOT_SECURITY=wpa3 WIFI_HOTSPOT_TEST_MODE=1 bash -c '
  source "'"$SRC"'" 
  SECURITY=wpa3
  up_p2p
' 2>&1)
rc=$?
set -e
if echo "$out" | grep -q "Wi-Fi Direct mode does not support WPA3"; then
  echo "  ok: up_p2p refuses wpa3"
else
  echo "  FAIL: up_p2p did not refuse wpa3 (rc=$rc): $out"; FAIL=1
fi

# 3. Test-mode gate: path overrides ignored without TEST_MODE.
out=$(WIFI_HOTSPOT_CONF=/nonexistent/path.conf bash -c 'source "'"$SRC"'"; echo "CONF_PATH=$CONF_PATH"' 2>/dev/null | grep '^CONF_PATH=')
if [ "$out" = "CONF_PATH=/etc/wifi-hotspot.conf" ]; then
  echo "  ok: path override ignored without TEST_MODE"
else
  echo "  FAIL: gate not working: $out"; FAIL=1
fi
# With TEST_MODE, override applies.
out=$(WIFI_HOTSPOT_TEST_MODE=1 WIFI_HOTSPOT_CONF=/nonexistent/path.conf bash -c 'source "'"$SRC"'"; echo "CONF_PATH=$CONF_PATH"' 2>/dev/null | grep '^CONF_PATH=')
if [ "$out" = "CONF_PATH=/nonexistent/path.conf" ]; then
  echo "  ok: path override applies in TEST_MODE"
else
  echo "  FAIL: gate broken: $out"; FAIL=1
fi

if [ "$FAIL" = "1" ]; then echo "=== TESTS FAILED ==="; exit 1; fi
echo "=== ALL WPA3 MODE TESTS PASSED ==="
