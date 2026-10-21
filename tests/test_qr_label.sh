#!/usr/bin/env bash
# tests/test_qr_label.sh — QR printed security label reflects the running mode.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HERE/bin/wifi-hotspot"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
FAIL=0

# Helper: run qr and capture the "Security:" line.
run_qr() { # $1 = SECURITY value, $2 = state mode (or empty)
  local sec="$1" mode="$2"
  local conf="$TMPROOT/conf" psk="$TMPROOT/psk" run="$TMPROOT/run" state="$TMPROOT/run/wifi-hotspot-ap0.state"
  mkdir -p "$run"
  rm -f "$state"
  if [ -n "$mode" ]; then printf 'MODE=%s\nAP_IF=ap0\n' "$mode" > "$state"; fi
  printf 'SSID="TestNet"\nCOUNTRY="US"\nSECURITY="%s"\nRUN_DIR="%s"\n' "$sec" "$run" > "$conf"
  printf 'secret' > "$psk"
  env WIFI_HOTSPOT_CONF="$conf" WIFI_HOTSPOT_PSKFILE="$psk" WIFI_HOTSPOT_TEST_MODE=1 \
      bash -c "source '$SRC' qr; cmd_qr" 2>/dev/null | grep -i '^Security:' || true
}

check() { # $1 = expected label, $2 = SECURITY, $3 = mode
  local got exp="$1"
  got="$(run_qr "$2" "$3")"
  if [ "$got" != "$exp" ]; then
    echo "  FAIL: SECURITY=$2 mode=$3 -> got '$got', expected '$exp'"; FAIL=1
  else
    echo "  ok: SECURITY=$2 mode=$3 -> $got"
  fi
}

echo "=== test_qr_label.sh ==="
check "Security: WPA3 (SAE)"        wpa3 ""
check "Security: WPA2 (WPA-PSK)"    wpa3 "p2p"
check "Security: WPA2+WPA3 (transition)" mixed ""
check "Security: WPA2 (WPA-PSK)"    mixed "p2p"
check "Security: WPA2 (WPA-PSK)"    wpa2 ""
check "Security: WPA2 (WPA-PSK)"    wpa2 "p2p"

if [ "$FAIL" = "1" ]; then echo "=== TESTS FAILED ==="; exit 1; fi
echo "=== ALL QR LABEL TESTS PASSED ==="
