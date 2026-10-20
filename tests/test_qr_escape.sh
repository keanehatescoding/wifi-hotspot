#!/usr/bin/env bash
# Regression tests for the WiFi-URI escaping used by `wifi-hotspot qr`.
set -euo pipefail

# Pull the helper straight out of the source so the test stays in sync.
eval "$(sed -n '/^wifi_qr_escape(){/,/^}/p' "$(dirname "$0")/../bin/wifi-hotspot")"

fail=0
check(){ # check <input> <expected>
  local got; got=$(wifi_qr_escape "$1")
  if [ "$got" != "$2" ]; then
    echo "FAIL: wifi_qr_escape('$1') = '$got', want '$2'"
    fail=1
  else
    echo "ok:   '$1' -> '$got'"
  fi
}

check "ArchHotspot"   "ArchHotspot"
check "plain"         "plain"
check "a;b"           'a\;b'
check "a:b"           'a\:b'
check "a,b"           'a\,b'
check 'a\b'           'a\\b'
check 'a"b'           'a\"b'
check 'a;b:c,d\e"f'  'a\;b\:c\,d\\e\"f'

# End-to-end: a WIFI: URI built from escaped values round-trips through qrencode.
if command -v qrencode >/dev/null 2>&1; then
  ssid='a;b' pass='x:y,z\w"q'
  s=$(wifi_qr_escape "$ssid"); p=$(wifi_qr_escape "$pass")
  uri="WIFI:T:WPA;S:${s};P:${p};H:false;;"
  tmp=$(mktemp /tmp/qrtest.XXXXXX.png)
  qrencode -o "$tmp" -s 4 -m 2 "$uri"
  if command -v zbarimg >/dev/null 2>&1; then
    dec=$(zbarimg "$tmp" 2>/dev/null)
    [ "$dec" = "QR-Code:$uri" ] && echo "ok:   round-trip decode matches" || { echo "FAIL: decode mismatch: $dec"; fail=1; }
  fi
  rm -f "$tmp"
fi

exit "$fail"
