#!/usr/bin/env bash
# tests/test_config_validation.sh — SECURITY and FIREWALL_BACKEND must reject
# unknown values instead of silently falling back to the default.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HERE/bin/wifi-hotspot"
FAIL=0

run() { # run <env-assignment> ... ; expects non-zero exit
  local envstr="$1"
  set +e
  env WIFI_HOTSPOT_TEST_MODE=1 $envstr bash -c "source '$SRC'" >/dev/null 2>&1
  local rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then echo "  FAIL: expected failure for: $envstr"; FAIL=1
  else echo "  ok: rejected: $envstr"; fi
}

echo "=== test_config_validation.sh ==="
run "SECURITY=WPA3"
run "SECURITY=wap3"
run "SECURITY=foo"
run "FIREWALL_BACKEND=UFW"
run "FIREWALL_BACKEND=firewald"
run "FIREWALL_BACKEND=bar"

# valid values must be accepted
for v in "" wpa2 wpa3 mixed; do
  SECURITY="$v" WIFI_HOTSPOT_TEST_MODE=1 bash -c "source '$SRC'" >/dev/null 2>&1
  [ $? -eq 0 ] || { echo "  FAIL: valid SECURITY='$v' rejected"; FAIL=1; }
done
for v in "" auto raw firewalld ufw; do
  FIREWALL_BACKEND="$v" WIFI_HOTSPOT_TEST_MODE=1 bash -c "source '$SRC'" >/dev/null 2>&1
  [ $? -eq 0 ] || { echo "  FAIL: valid FIREWALL_BACKEND='$v' rejected"; FAIL=1; }
done
echo "  ok: valid values accepted"

if [ "$FAIL" = "1" ]; then echo "=== TESTS FAILED ==="; exit 1; fi
echo "=== ALL CONFIG VALIDATION TESTS PASSED ==="
