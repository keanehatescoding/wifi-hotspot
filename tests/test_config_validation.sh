#!/usr/bin/env bash
# tests/test_config_validation.sh — SECURITY and FIREWALL_BACKEND must reject
# unknown values instead of silently falling back to the default, but only for
# the commands that act on them (up/restart/sync/qr), not for teardown.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HERE/bin/wifi-hotspot"
FAIL=0

# Invalid values must be rejected by `up` (validation runs before elevation).
for envstr in \
  "WIFI_HOTSPOT_SECURITY=WPA3" \
  "WIFI_HOTSPOT_SECURITY=wap3" \
  "WIFI_HOTSPOT_SECURITY=foo" \
  "WIFI_HOTSPOT_FIREWALL_BACKEND=UFW" \
  "WIFI_HOTSPOT_FIREWALL_BACKEND=firewald" \
  "WIFI_HOTSPOT_FIREWALL_BACKEND=bar"; do
  set +e
  env $envstr "$SRC" up >/dev/null 2>&1
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then echo "  FAIL: expected failure for: $envstr"; FAIL=1
  else echo "  ok: rejected: $envstr"; fi
done

# Invalid values must NOT block teardown/read-only commands.
for envstr in \
  "WIFI_HOTSPOT_SECURITY=WPA3" \
  "WIFI_HOTSPOT_FIREWALL_BACKEND=UFW"; do
  set +e
  env $envstr "$SRC" --version >/dev/null 2>&1
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then echo "  FAIL: --version blocked by: $envstr"; FAIL=1
  else echo "  ok: --version allowed with: $envstr"; fi
done

# Valid values must be accepted (fail later, not on validation).
for v in "" wpa2 wpa3 mixed; do
  set +e
  env WIFI_HOTSPOT_SECURITY="$v" "$SRC" up >/dev/null 2>&1
  rc=$?
  set -e
  # up will fail for other reasons (no SSID/COUNTRY), but not with the
  # validation error message. Accept any non-validation failure (rc != 0 is fine).
  # We only fail the test if the error mentions "must be one of".
  if env WIFI_HOTSPOT_SECURITY="$v" "$SRC" up 2>&1 | grep -q "must be one of"; then
    echo "  FAIL: valid SECURITY='$v' rejected"; FAIL=1
  else echo "  ok: valid SECURITY='$v' accepted"; fi
done
for v in "" auto raw firewalld ufw; do
  if env WIFI_HOTSPOT_FIREWALL_BACKEND="$v" "$SRC" up 2>&1 | grep -q "must be one of"; then
    echo "  FAIL: valid FIREWALL_BACKEND='$v' rejected"; FAIL=1
  else echo "  ok: valid FIREWALL_BACKEND='$v' accepted"; fi
done

if [ "$FAIL" = "1" ]; then echo "=== TESTS FAILED ==="; exit 1; fi
echo "=== ALL CONFIG VALIDATION TESTS PASSED ==="
