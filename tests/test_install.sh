#!/usr/bin/env bash
# tests/test_install.sh — exercise install.sh's branching logic.
#
# Runs as root (re-execs with sudo if needed) in a throwaway DESTDIR with a
# stub systemctl, covering every config state the installer can encounter.
set -euo pipefail

# Runs as the current user; systemctl and chown are stubbed below, and
# DESTDIR redirects all file writes into a throwaway tree.
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMPROOT="$(mktemp -d /tmp/whtest-install.XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

STUBDIR="$TMPROOT/stubbin"
mkdir -p "$STUBDIR"
STUB_LOG="$TMPROOT/systemctl.log"
: > "$STUB_LOG"

# Stub chown: no-op (real chown needs root; harmless to skip in tests).
cat > "$STUBDIR/chown" <<'STUB'
#!/bin/sh
exit 0
STUB
chmod +x "$STUBDIR/chown"

# Stub systemctl: records every invocation, always succeeds.
cat > "$STUBDIR/systemctl" <<'STUB'
#!/bin/sh
echo "$*" >> "${STUB_LOG:?}"
case "$1" in
  daemon-reload) exit 0 ;;
  enable)
    exit 0 ;;
  is-active) echo "inactive"; exit 0 ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$STUBDIR/systemctl"

export DESTDIR="$TMPROOT/root"
export PATH="$STUBDIR:$PATH"
export STUB_LOG

run_case() {
  # run_case <name> <config-content-or-empty> <expect-enable-now 0/1> <expect-guidance 0/1>
  local name="$1" cfg="$2" want_now="$3" want_guide="$4"
  local root="$TMPROOT/case_$name"
  rm -rf "$root"; mkdir -p "$root"
  export DESTDIR="$root"
  : > "$STUB_LOG"

  # Seed config if provided
  if [ -n "$cfg" ]; then
    mkdir -p "$root/etc"
    printf '%s\n' "$cfg" > "$root/etc/wifi-hotspot.conf"
  fi

  # Run installer
  set +e
  DESTDIR="$root" PATH="$STUBDIR:$PATH" sh "$HERE/install.sh" >"$TMPROOT/out_$name.txt" 2>&1
  local rc=$?
  set -e

  # Assertions
  local ok=1
  if [ "$rc" -ne 0 ]; then
    echo "  [$name] FAIL: installer exited $rc"; cat "$TMPROOT/out_$name.txt" | sed 's/^/    /'; ok=0
  fi
  local has_now has_enable
  has_now=$(grep -c 'enable --now' "$STUB_LOG" || true)
  has_enable=$(grep -c '^enable wifi-hotspot' "$STUB_LOG" || true)
  if [ "$want_now" = "1" ]; then
    [ "$has_now" -ge 1 ] || { echo "  [$name] FAIL: expected enable --now"; ok=0; }
  else
    [ "$has_now" -eq 0 ] || { echo "  [$name] FAIL: unexpected enable --now"; ok=0; }
    [ "$has_enable" -ge 1 ] || { echo "  [$name] FAIL: expected enable (no --now)"; ok=0; }
  fi
  if [ "$want_guide" = "1" ]; then
    grep -q "NOT started" "$TMPROOT/out_$name.txt" || { echo "  [$name] FAIL: missing guidance"; ok=0; }
  else
    grep -q "Installed. Status:" "$TMPROOT/out_$name.txt" || { echo "  [$name] FAIL: missing status"; ok=0; }
  fi
  if [ "$ok" = "1" ]; then
    echo "  [$name] PASS"
  else
    echo "  --- installer output ---"; cat "$TMPROOT/out_$name.txt" | sed 's/^/    /'
    echo "  --- systemctl log ---"; cat "$STUB_LOG" | sed 's/^/    /'
    FAIL=1
  fi
}

FAIL=0
echo "=== test_install.sh ==="

# Case 1: no config (fresh install)
run_case "no_config" "" 0 1

# Case 2: default config (everything commented out)
run_case "default_config" \
  '#SSID="MyHotspot"
#COUNTRY="US"' 0 1

# Case 3: only SSID set
run_case "only_ssid" 'SSID="MyNet"' 0 1

# Case 4: SSID and COUNTRY set
run_case "configured" 'SSID="MyNet"
COUNTRY="KE"' 1 0

# Case 5: existing config on upgrade (left untouched)
cfg='SSID="Existing"
COUNTRY="DE"'
root="$TMPROOT/case_upgrade"
mkdir -p "$root/etc"
printf '%s\n' "$cfg" > "$root/etc/wifi-hotspot.conf"
# record original content hash
orig=$(md5sum < "$root/etc/wifi-hotspot.conf")
export DESTDIR="$root"
: > "$STUB_LOG"
DESTDIR="$root" PATH="$STUBDIR:$PATH" sh "$HERE/install.sh" >$TMPROOT/out_upgrade.txt 2>&1
rc=$?
new=$(md5sum < "$root/etc/wifi-hotspot.conf")
if [ "$rc" -ne 0 ]; then echo "  [upgrade] FAIL: exit $rc"; FAIL=1
elif [ "$orig" != "$new" ]; then echo "  [upgrade] FAIL: config was modified"; FAIL=1
elif ! grep -q "Installed. Status:" $TMPROOT/out_upgrade.txt; then echo "  [upgrade] FAIL: no status"; FAIL=1
else echo "  [upgrade] PASS"; fi

# Case 6: staged install (switch set) -> no systemctl calls at all
root="$TMPROOT/case_staged"
mkdir -p "$root/etc"
printf 'SSID="Staged"
COUNTRY="US"
' > "$root/etc/wifi-hotspot.conf"
export DESTDIR="$root"
: > "$STUB_LOG"
set +e
DESTDIR="$root" WIFI_HOTSPOT_NO_SYSTEMCTL=1 PATH="$STUBDIR:$PATH" sh "$HERE/install.sh" >"$TMPROOT/out_staged.txt" 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ]; then echo "  [staged] FAIL: exit $rc"; FAIL=1
elif [ -s "$STUB_LOG" ]; then echo "  [staged] FAIL: systemctl was called: $(cat "$STUB_LOG")"; FAIL=1
else echo "  [staged] PASS (no systemctl calls)"; fi

# Case 7: malformed config -> non-zero exit, error message
root="$TMPROOT/case_malformed"
mkdir -p "$root/etc"
printf 'SSID="unterminated\nCOUNTRY="KE"\n' > "$root/etc/wifi-hotspot.conf"
export DESTDIR="$root"
: > "$STUB_LOG"
set +e
DESTDIR="$root" PATH="$STUBDIR:$PATH" sh "$HERE/install.sh" >$TMPROOT/out_malformed.txt 2>&1
rc=$?
set -e
if [ "$rc" -eq 0 ]; then echo "  [malformed] FAIL: expected non-zero exit"; FAIL=1
elif ! grep -q "syntax error" $TMPROOT/out_malformed.txt; then echo "  [malformed] FAIL: missing error message"; FAIL=1
else echo "  [malformed] PASS"; fi

if [ "$FAIL" = "1" ]; then
  echo "=== TESTS FAILED ==="
  exit 1
fi
echo "=== ALL INSTALL TESTS PASSED ==="