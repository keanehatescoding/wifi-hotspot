#!/bin/sh
# Convenience installer: copies files and enables the systemd unit.
set -eu

[ "$(id -u)" -eq 0 ] || { echo "run as root (sudo ./install.sh)"; exit 1; }

here="$(cd "$(dirname "$0")" && pwd)"

install -Dm755 "$here/bin/wifi-hotspot"               /usr/local/bin/wifi-hotspot
if [ -f /etc/wifi-hotspot.conf ]; then
  echo "keeping existing config: /etc/wifi-hotspot.conf"
else
  install -Dm644 "$here/config/wifi-hotspot.conf" /etc/wifi-hotspot.conf
  echo "installed default config: /etc/wifi-hotspot.conf"
fi
install -Dm644 "$here/systemd/wifi-hotspot.service"   /etc/systemd/system/wifi-hotspot.service
install -Dm755 "$here/NetworkManager/90-wifi-hotspot" /etc/NetworkManager/dispatcher.d/90-wifi-hotspot
install -Dm644 "$here/man/wifi-hotspot.8"             /usr/local/share/man/man8/wifi-hotspot.8
chown root:root /etc/NetworkManager/dispatcher.d/90-wifi-hotspot

systemctl daemon-reload

# Source the (possibly freshly installed) config to see whether the two
# required settings are present.  Do not start the service on a default
# config: with SSID/COUNTRY unset `up` fails and `enable --now` would
# abort this installer under `set -e` before printing any guidance.
SSID=""; COUNTRY=""
[ -r /etc/wifi-hotspot.conf ] && . /etc/wifi-hotspot.conf 2>/dev/null || true

if [ -n "${SSID:-}" ] && [ -n "${COUNTRY:-}" ]; then
  systemctl enable --now wifi-hotspot.service
  echo
  echo "Installed. Status:"
  /usr/local/bin/wifi-hotspot status || true
else
  systemctl enable wifi-hotspot.service
  echo
  echo "Installed, but NOT started: SSID and COUNTRY are not set yet."
  echo "Edit /etc/wifi-hotspot.conf to set SSID and COUNTRY (ISO 3166-1 alpha-2),"
  echo "then run:  sudo systemctl start wifi-hotspot"
fi
