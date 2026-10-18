# wifi-hotspot

Run a Wi-Fi **client** connection and a Wi-Fi **hotspot** at the same time on a
single-radio adapter that only supports *same-channel* STA+AP concurrency — for
example the Realtek **RTL8852BE** (`rtw89` driver) found in many recent laptops.

On Windows the built-in Mobile Hotspot seems to "just work" while you stay
connected to Wi-Fi. That is not a different hardware capability: Windows silently
puts the hotspot on the **same channel as your uplink**. NetworkManager does not,
and it cannot drive both roles on its own. This tool does what Windows does, on
Linux.

## The problem

`iw list` reports that the card *can* run both roles, but only on **one channel**:

```
valid interface combinations:
    * #{ managed } <= 1, #{ AP, P2P-client, P2P-GO } <= 1, total <= 2, #channels <= 1
    * #{ managed } <= 1, #{ P2P-client, P2P-GO } <= 1,       total <= 2, #channels <= 2
```

So client + AP is allowed, **but they must share a channel**. Two things then get
in the way on Linux:

1. NetworkManager reuses the single interface, so activating a hotspot disconnects
   the client; and its `wpa_supplicant` cannot grab a second interface
   (`wpa_supplicant couldn't grab this interface`).
2. A hand-created second interface inherits the primary's MAC address, so the
   kernel refuses to bring it up (`Name not unique on network`).

## What this does

- Creates a second virtual interface (`ap0`) on the same phy in AP mode.
- Runs **hostapd** on it, pinned to the **same channel as the client**.
- Gives it a **unique locally-administered MAC** (fixes the `ENOTUNIQ` failure).
- Adds **dnsmasq** (DHCP + DNS) and **NAT** so hotspot clients share the Wi-Fi uplink.
- Ships a **NetworkManager dispatcher** that re-syncs the hotspot on reconnect or
  channel change (roaming), and tears it down when Wi-Fi disconnects.
- Ships a **systemd unit** so it comes up at boot.

## Requirements

- Linux with: `iw`, `hostapd`, `dnsmasq`, `iptables`, `NetworkManager` (`nmcli`), `systemd`
- A Wi-Fi card with same-channel STA+AP concurrency. Verify with:

  ```sh
  iw list | sed -n '/valid interface combinations/,/^$/p'
  ```

  Look for a line allowing `managed` **and** `AP` with `#channels <= 1`.

## Install

```sh
git clone https://github.com/keanehatescoding/wifi-hotspot
cd wifi-hotspot
sudo make install
sudo systemctl daemon-reload
sudo systemctl enable --now wifi-hotspot.service
```

or simply:

```sh
sudo ./install.sh
```

## Usage

```sh
wifi-hotspot status     # show state (no root needed)
wifi-hotspot up         # create/ensure the hotspot
wifi-hotspot restart    # recreate (e.g. after changing config)
wifi-hotspot down       # tear it down
wifi-hotspot sync       # re-pin to the client's current channel
```

Once installed, the hotspot follows your Wi-Fi automatically: connect to a network
and the AP comes up on that network's channel; roam and it re-pins.

## Configuration

Edit `/etc/wifi-hotspot.conf`:

```sh
#CLIENT="wlan0"
#AP="ap0"
#SSID="ArchHotspot"
#COUNTRY="KE"
#AP_ADDR="10.42.0.1"
#AP_PREFIX="24"
#DHCP_RANGE="10.42.0.10,10.42.0.200,12h"
```

The Wi-Fi password is read once from your NetworkManager profile (or generated)
and stored in `/etc/hostapd/ap0.psk`. To change it, delete that file and run
`wifi-hotspot restart`.

## Limitations / notes

- **Same channel is mandatory.** It is a hardware limit of single-radio MACs, not
  a bug. The dispatcher keeps the AP on the client's channel for you.
- **Throughput is roughly halved** on both links, because one radio time-shares.
  For full speed, share an *ethernet* uplink instead.
- **5 GHz DFS channels** (52–144) can add a CAC delay; non-DFS 5 GHz and 2.4 GHz
  start instantly. Set `COUNTRY` so 5 GHz AP is permitted by the regulatory domain.
- Not related to Wi-Fi Direct / P2P; this uses a plain AP interface.

## Uninstall

```sh
sudo systemctl disable --now wifi-hotspot.service
sudo make uninstall
```

## License

MIT — see [LICENSE](LICENSE).
