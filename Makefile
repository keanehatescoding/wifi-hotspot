# wifi-hotspot - install a Wi-Fi hotspot that shares the client uplink
# (same-channel hostapd, or a Wi-Fi Direct group owner on its own channel).

PREFIX      ?= /usr/local
SYSCONFDIR  ?= /etc
DESTDIR     ?=
AP          ?= ap0

BINDIR      := $(DESTDIR)$(PREFIX)/bin
MANDIR      := $(DESTDIR)$(PREFIX)/share/man
UNITDIR     := $(DESTDIR)/etc/systemd/system
DISPDIR     := $(DESTDIR)/etc/NetworkManager/dispatcher.d

.PHONY: install uninstall check

check:
	@command -v hostapd  >/dev/null || { echo "missing: hostapd";  exit 1; }
	@command -v dnsmasq  >/dev/null || { echo "missing: dnsmasq";  exit 1; }
	@command -v iw       >/dev/null || { echo "missing: iw";       exit 1; }
	@command -v qrencode >/dev/null 2>&1 || echo "optional: qrencode (needed for 'wifi-hotspot qr')"
	@echo "dependencies OK"

install:
	install -Dm755 bin/wifi-hotspot                         $(BINDIR)/wifi-hotspot
	@if [ -f $(DESTDIR)$(SYSCONFDIR)/wifi-hotspot.conf ]; then \
	  echo "keeping existing config: $(DESTDIR)$(SYSCONFDIR)/wifi-hotspot.conf"; \
	else \
	  install -Dm644 config/wifi-hotspot.conf $(DESTDIR)$(SYSCONFDIR)/wifi-hotspot.conf; \
	  echo "installed default config: $(DESTDIR)$(SYSCONFDIR)/wifi-hotspot.conf"; \
	fi
	install -Dm644 systemd/wifi-hotspot.service             $(UNITDIR)/wifi-hotspot.service
	install -Dm755 NetworkManager/90-wifi-hotspot           $(DISPDIR)/90-wifi-hotspot
	install -Dm644 man/wifi-hotspot.8                       $(MANDIR)/man8/wifi-hotspot.8
	chown root:root $(DISPDIR)/90-wifi-hotspot
	@echo
	@echo "Installed. Enable with:"
	@echo "  systemctl daemon-reload"
	@echo "  systemctl enable --now wifi-hotspot.service"

uninstall:
	-rm -f $(BINDIR)/wifi-hotspot
	-rm -f $(DISPDIR)/90-wifi-hotspot
	-rm -f $(UNITDIR)/wifi-hotspot.service
	-rm -f $(MANDIR)/man8/wifi-hotspot.8
	-rm -f $(DESTDIR)$(SYSCONFDIR)/hostapd/$(AP).conf
	@echo "Removed. (config + password kept: $(DESTDIR)$(SYSCONFDIR)/wifi-hotspot.conf, $(DESTDIR)$(SYSCONFDIR)/hostapd/$(AP).psk)"
	@echo "Run: systemctl daemon-reload"
