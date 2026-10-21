#!/usr/bin/env bash
# tests/test_config_validation.sh — SECURITY and FIREWALL_BACKEND must reject
# unknown values instead of silently falling back to the default, but only for
# the commands that act on them (up/restart/sync/qr), not for teardown.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HERE/bin/wifi-hotspot"
FAIL=0

# Source the script with $1=up so load-time validation runs, but dispatch is
# skipped (TEST_MODE), avoiding any privileged side effects.
src_up() { # $1 = env string
  env WIFI_HOTSPOT_TEST_MODE=1 $1 bash -c 'source "$1" up' _ "$SRC" >/dev/null 2>&1
}

echo "=== test_config_validation.sh ==="

# Invalid values must be rejected (non-zero exit).
for envstr in \
  "WIFI_HOTSPOT_SECURITY=WPA3" \
  "WIFI_HOTSPOT_SECURITY=wap3" \
  "WIFI_HOTSPOT_SECURITY=foo" \
  "WIFI_HOTSPOT_FIREWALL_BACKEND=UFW" \
  "WIFI_HOTSPOT_FIREWALL_BACKEND=firewald" \
  "WIFI_HOTSPOT_FIREWALL_BACKEND=bar"; do
  set +e
  src_up "$envstr"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then echo "  FAIL: expected failure for: $envstr"; FAIL=1
  else echo "  ok: rejected: $envstr"; fi
done

# Invalid values must NOT block teardown/read-only commands (no validation).
for envstr in \
  "WIFI_HOTSPOT_SECURITY=WPA3" \
  "WIFI_HOTSPOT_FIREWALL_BACKEND=UFW"; do
  set +e
  env WIFI_HOTSPOT_TEST_MODE=1 $envstr "$SRC" --version >/dev/null 2>&1
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then echo "  FAIL: --version blocked by: $envstr"; FAIL=1
  else echo "  ok: --version allowed with: $envstr"; fi
done

# Valid values must be accepted (no "must be one of" error).
for v in "" wpa2 wpa3 mixed; do
  out=$(env WIFI_HOTSPOT_TEST_MODE=1 WIFI_HOTSPOT_SECURITY="$v" bash -c 'source "$1" up' _ "$SRC" 2>&1)
  if echo "$out" | grep -q "must be one of"; then
    echo "  FAIL: valid SECURITY='$v' rejected"; FAIL=1
  else echo "  ok: valid SECURITY='$v' accepted"; fi
done
for v in "" auto raw firewalld ufw; do
  out=$(env WIFI_HOTSPOT_TEST_MODE=1 WIFI_HOTSPOT_FIREWALL_BACKEND="$v" bash -c 'source "$1" up' _ "$SRC" 2>&1)
  if echo "$out" | grep -q "must be one of"; then
    echo "  FAIL: valid FIREWALL_BACKEND='$v' rejected"; FAIL=1
  else echo "  ok: valid FIREWALL_BACKEND='$v' accepted"; fi
done

if [ "$FAIL" = "1" ]; then echo "=== TESTS FAILED ==="; exit 1; fi
echo "=== ALL CONFIG VALIDATION TESTS PASSED ==="
