#!/bin/sh
# Convenience installer: copies files and enables the systemd unit.
set -eu

[ "$(id -u)" -eq 0 ] || { echo "run as root (sudo ./install.sh)"; exit 1; }

here="$(cd "$(dirname "$0")" && pwd)"

install -Dm755 "$here/bin/wifi-hotspot"               /usr/local/bin/wifi-hotspot
install -Dm644 "$here/config/wifi-hotspot.conf"       /etc/wifi-hotspot.conf
install -Dm644 "$here/systemd/wifi-hotspot.service"   /etc/systemd/system/wifi-hotspot.service
install -Dm755 "$here/NetworkManager/90-wifi-hotspot" /etc/NetworkManager/dispatcher.d/90-wifi-hotspot
chown root:root /etc/NetworkManager/dispatcher.d/90-wifi-hotspot

systemctl daemon-reload
systemctl enable --now wifi-hotspot.service

echo
echo "Installed. Status:"
/usr/local/bin/wifi-hotspot status || true
