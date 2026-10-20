#!/usr/bin/env bash
# Regression test: a long-lived child (simulating hostapd -B / dnsmasq) must
# NOT keep the wifi-hotspot lock held after the parent exits.  This is the
# class of bug fixed by closing fd 9 in those children (9>&-).
set -euo pipefail

LOCK=$(mktemp /tmp/whtest-lock.XXXXXX)
rm -f "$LOCK"

# Reproduce the BROKEN pattern: child inherits fd 9 -> lock stays held.
(
  exec 9>"$LOCK"
  flock -w 2 9 || exit 1
  ( sleep 30 ) &          # no 9>&- : inherits the lock
  disown
  exit 0
)
sleep 0.5
if ( exec 9>"$LOCK"; flock -w 1 9 ); then
  echo "FAIL: broken pattern released the lock (unexpected)"; rm -f "$LOCK"; exit 1
else
  echo "ok:   broken pattern keeps the lock held (bug reproduced)"
fi

# Reproduce the FIXED pattern: child closes fd 9 -> lock releases.
rm -f "$LOCK"
(
  exec 9>"$LOCK"
  flock -w 2 9 || exit 1
  ( sleep 30 ) 9>&- &    # closes fd 9
  disown
  exit 0
)
sleep 0.5
if ( exec 9>"$LOCK"; flock -w 2 9 ); then
  echo "ok:   fixed pattern releases the lock"
else
  echo "FAIL: fixed pattern still holds the lock"; rm -f "$LOCK"; exit 1
fi

# cleanup any leftover sleepers
pkill -f "sleep 30" 2>/dev/null || true
rm -f "$LOCK"
