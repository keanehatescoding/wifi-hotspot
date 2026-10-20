#!/bin/sh
# Convenience installer: copies files and enables the systemd unit.
set -eu

[ "$(id -u)" -eq 0 ] || { echo "run as root (sudo ./install.sh)"; exit 1; }

here="$(cd "$(dirname "$0")" && pwd)"

# Validate any existing config before touching anything, so a malformed file
# fails here with a clear message instead of aborting mid-install.  Run the
# source in a subshell so a syntax error in the config can't kill this shell
# (dash exits the whole shell on a sourced syntax error).
if [ -r "${DESTDIR:-}/etc/wifi-hotspot.conf" ]; then
  # shellcheck disable=SC1091
  if ! ( . "${DESTDIR:-}/etc/wifi-hotspot.conf" ) >/dev/null 2>&1; then
    echo "error: ${DESTDIR:-}/etc/wifi-hotspot.conf has a syntax error" >&2
    exit 1
  fi
fi

install -Dm755 "$here/bin/wifi-hotspot"               "${DESTDIR:-}/usr/local/bin/wifi-hotspot"
if [ -f "${DESTDIR:-}/etc/wifi-hotspot.conf" ]; then
  echo "keeping existing config: ${DESTDIR:-}/etc/wifi-hotspot.conf"
else
  install -Dm644 "$here/config/wifi-hotspot.conf" "${DESTDIR:-}/etc/wifi-hotspot.conf"
  echo "installed default config: ${DESTDIR:-}/etc/wifi-hotspot.conf"
fi
install -Dm644 "$here/systemd/wifi-hotspot.service"   "${DESTDIR:-}/etc/systemd/system/wifi-hotspot.service"
install -Dm755 "$here/NetworkManager/90-wifi-hotspot" "${DESTDIR:-}/etc/NetworkManager/dispatcher.d/90-wifi-hotspot"
install -Dm644 "$here/man/wifi-hotspot.8"             "${DESTDIR:-}/usr/local/share/man/man8/wifi-hotspot.8"
if [ -z "${DESTDIR:-}" ]; then
  chown root:root /etc/NetworkManager/dispatcher.d/90-wifi-hotspot
fi

# Source the (possibly freshly installed) config to see whether the two
# required settings are present.  Do not start the service on a default
# config: with SSID/COUNTRY unset `up` fails and `enable --now` would
# abort this installer under `set -e` before printing any guidance.
SSID=""; COUNTRY=""
if [ -r "${DESTDIR:-}/etc/wifi-hotspot.conf" ]; then
  # shellcheck disable=SC1091
  if ! ( . "${DESTDIR:-}/etc/wifi-hotspot.conf" ) >/dev/null 2>&1; then
    echo "error: ${DESTDIR:-}/etc/wifi-hotspot.conf has a syntax error" >&2
    exit 1
  fi
fi

if [ -z "${DESTDIR:-}" ]; then
  systemctl daemon-reload
fi

if [ -n "${SSID:-}" ] && [ -n "${COUNTRY:-}" ]; then
  if [ -z "${DESTDIR:-}" ]; then
    systemctl enable --now wifi-hotspot.service
    echo
    echo "Installed. Status:"
    /usr/local/bin/wifi-hotspot status || true
  else
    echo "Installed (staged). Enable/start on the target system after setting SSID and COUNTRY."
  fi
else
  if [ -z "${DESTDIR:-}" ]; then
    systemctl enable wifi-hotspot.service
  fi
  echo
  echo "Installed, but NOT started: SSID and COUNTRY are not set yet."
  echo "Edit /etc/wifi-hotspot.conf to set SSID and COUNTRY (ISO 3166-1 alpha-2),"
  echo "then run:  sudo systemctl start wifi-hotspot"
fi
