# wifi-hotspot

Run a Wi-Fi **client** connection and a Wi-Fi **hotspot** at the same time on a
single-radio adapter — for example the Realtek **RTL8852BE** (`rtw89` driver)
found in many recent laptops.

On Windows the built-in Mobile Hotspot seems to "just work" while you stay
connected to Wi-Fi. That is not a different hardware capability: Windows silently
puts the hotspot on the **same channel as your uplink**. NetworkManager does not,
and it cannot drive both roles on its own. This tool does what Windows does, on
Linux — and, where the driver supports it and the uplink's channel genuinely
cannot host an AP, it can fall back to a **Wi-Fi Direct** group owner on a channel
of its own.

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

Some uplink channels also cannot host an AP at all — radar/DFS channels (where a
client card cannot do the required radar check), 5/6 GHz channels marked "no IR",
or 6 GHz generally. There, the second combination above is the answer: a
**group owner** (Wi-Fi Direct) may use a channel of its own, and the radio hops
between the two. The group is created by the `wpa_supplicant` that NetworkManager
already runs, which makes the group owner a real interface (`p2p-wlan0-0`) sitting
next to the client connection.

`wpa_supplicant` can drive Wi-Fi Direct in two layouts, and either one works:

| driver | where P2P lives | `iw phy` shows | control socket |
| ------ | --------------- | -------------- | -------------- |
| `iwlwifi` (Intel) | a dedicated P2P device | `P2P-device` under *Supported interface modes* | `/run/wpa_supplicant/p2p-dev-wlan0` |
| `rtw89` (Realtek, e.g. RTL8852BE) | the client interface itself | no `P2P-device` entry | `/run/wpa_supplicant/wlan0` |

A missing `P2P-device` interface only means `wpa_supplicant` never creates the
`p2p-dev-*` socket, and drives P2P over the client interface instead; it is not a
lack of Wi-Fi Direct support. What the driver really has to permit is a **group
owner next to a managed interface on a channel of its own** — the second
combination above. `wifi-hotspot detect` probes the running `wpa_supplicant` and
reports which layout you have.

Verified end to end on an RTL8852BE (`rtw89_8852be`): the client stayed connected
on 5 GHz channel 36 while the group owner ran as `p2p-wlan0-0` on 2.4 GHz channel
6, and a phone on the hotspot browsed through the uplink. So on this card the
Wi-Fi Direct path is not the same channel at all — it is a second channel, which
is what makes `MODE=auto` useful on a DFS uplink.

## What this does

- Creates a second virtual interface (`ap0`) on the same phy in AP mode.
- Runs **hostapd** on it, pinned to the **same channel as the client**.
- Gives it a **unique locally-administered MAC** (fixes the `ENOTUNIQ` failure).
- Adds **dnsmasq** (DHCP + DNS) and **NAT** so hotspot clients share the Wi-Fi uplink.
- Adds the **firewall** rules clients need. On hosts whose nftables ruleset has a
  `policy drop` on `INPUT`/`forward` (e.g. Arch's `/etc/nftables.conf`) that drops
  DHCP, it inserts a scoped `accept` for the AP interface into the existing
  `ip filter` chains and removes it again on `down`. Set `MANAGE_FIREWALL=0` to
  leave the host firewall alone.
- Falls back to a **Wi-Fi Direct group owner** (`MODE=auto`) when the uplink's
  channel cannot host an AP *and* the driver allows a group owner on a channel of
  its own, giving the hotspot a channel of its own.
- Ships a **NetworkManager dispatcher** that re-syncs the hotspot on reconnect or
  channel change (roaming), and tears it down when Wi-Fi disconnects.
- Ships a **systemd unit** so it comes up at boot.
- Has a **`detect`** command that reports what your hardware can actually do.

## Requirements

- Linux with: `iw`, `hostapd`, `dnsmasq`, `iptables`, `NetworkManager` (`nmcli`), `systemd`
- For Wi-Fi Direct mode: `wpa_cli`, a NetworkManager built with `wpa_supplicant`
  (the default), and a driver that allows a group owner next to a client
  connection (see the table above). Verify the whole picture with:

  ```sh
  wifi-hotspot detect
  ```

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
wifi-hotspot detect     # what can this machine do? (no root needed)
wifi-hotspot status     # show state (no root needed)
wifi-hotspot up         # create/ensure the hotspot
wifi-hotspot restart    # recreate (e.g. after changing config)
wifi-hotspot down       # tear it down
wifi-hotspot sync       # re-pin to the client's current channel
wifi-hotspot qr        # print a scannable QR code for the SSID/password
wifi-hotspot qr FILE   # ...and save it as a PNG
```

`up` accepts `--mode auto|same|p2p` to override the configured mode for one run.

`qr` needs `qrencode` (package `qrencode` / `libqrencode`); without it the
WiFi URI is printed instead of a scannable code.

Once installed, the hotspot follows your Wi-Fi automatically: connect to a network
and the AP comes up on that network's channel; roam and it re-pins.

`detect` and `status` never need root to run, but the `wpa_supplicant` control
socket is root-only, so `detect` can only *guess* the Wi-Fi Direct line as a normal
user; run it under `sudo` for a definite answer. The other actions re-exec
themselves as root via `pkexec` (falling back to `sudo`); set
`WIFI_HOTSPOT_ELEVATE=sudo` to force a particular elevator.

Full details are in [man/wifi-hotspot.8](man/wifi-hotspot.8) (`man wifi-hotspot`
after installing).

## Modes

| Mode | Interface | Channel | When |
| ---- | --------- | ------- | ---- |
| `same` | `ap0` (hostapd) | the uplink's channel | uplink channel can host an AP |
| `p2p`  | `p2p-wlan0-0` (Wi-Fi Direct GO) | a channel of its own | uplink channel cannot host an AP |
| `auto` | either of the above | — | default: `same`, else `p2p` |

`detect` prints which one your card and current connection will use. `p2p` is only
considered when the uplink's channel cannot host an AP **and** the driver allows a
group owner on its own channel; otherwise `auto` stays on `same`.

> **`p2p` mode is experimental.** It relies on the `wpa_supplicant` that
> NetworkManager runs, on the card/driver offering a `P2P-device` interface or
> driving P2P on the client interface, and on a group owner being permitted next to
> a client connection. `detect` tells you whether all of that is there; if not,
> `MODE=same` is used and nothing breaks. It also costs throughput: one radio hops
> between the two channels, which is worse than same-channel operation.

## Configuration

Edit `/etc/wifi-hotspot.conf`:

```sh
#CLIENT="wlan0"
#AP="ap0"
# SSID and COUNTRY are REQUIRED (no defaults are shipped on purpose).
#SSID="MyHotspot"
#COUNTRY="US"   # ISO 3166-1 alpha-2, e.g. US, GB, DE, KE
#AP_ADDR="10.42.0.1"
#AP_PREFIX="24"
#DHCP_RANGE="10.42.0.10,10.42.0.200,12h"
#MODE="auto"          # auto | same | p2p
#P2P_BAND="bg"        # group channel band when p2p: bg | a
#P2P_CHANNEL="auto"   # group channel, or a number
```

The Wi-Fi password is read once from your NetworkManager profile (or generated)
and stored in `/etc/hostapd/ap0.psk`. To change it, delete that file and run
`wifi-hotspot restart`.

## Limitations / notes

- **Same channel is mandatory for `MODE=same`.** It is a hardware limit of
  single-radio MACs, not a bug. The dispatcher keeps the AP on the client's channel
  for you.
- **Throughput is roughly halved** on both links, because one radio time-shares.
  In `p2p` mode the radio also hops between two channels, so it is worse. For full
  speed, share an *ethernet* uplink instead.
- **5 GHz DFS channels** (52–144) can add a CAC delay; non-DFS 5 GHz and 2.4 GHz
  start instantly. Set `COUNTRY` so 5 GHz AP is permitted by the regulatory domain.
- **`p2p` is experimental** (see above), only used when the uplink channel cannot
  host an AP, and needs a driver that allows a group owner on its own channel next
  to a client connection.

## Troubleshooting

- **Clients get a `169.254.x.x` (APIPA) address or no internet** — DHCP/the
  forward path is being dropped by a host firewall with a default-drop policy.
  The classic case is Arch's `/etc/nftables.conf`: its `INPUT` chain
  (`policy drop`) discards the DHCP `DISCOVER` before `dnsmasq` can answer, and
  its `forward` chain blocks NAT. The tool inserts a scoped `accept` for the AP
  interface automatically; if you manage the firewall yourself, allow UDP 67/53
  on the AP interface and forwarding between the AP and the uplink.
- **Uplink is on a DFS / "no IR" / 6 GHz channel** — `MODE=auto` switches to a
  Wi-Fi Direct group on its own channel if the driver supports one. If `detect`
  says Wi-Fi Direct is unavailable, connect on a 2.4 GHz or non-DFS 5 GHz network
  instead. To force the old behaviour, set `MODE=same`.
- **`Cannot enable IEEE 802.11h without IEEE 802.11d enabled`** / *`1 errors found
  in configuration file`* then *`Failed to set up interface`* — hostapd rejects the
  AP config. This happened on 5 GHz because every `hw_mode=a` channel got
  `ieee80211h=1`, which hostapd only accepts together with `ieee80211d=1` (and
  which is only *needed* on DFS channels). Current versions emit both only on DFS
  channels (5 GHz ch 52–64, 100–144).
- **`cannot use Wi-Fi Direct: wpa_supplicant is not running P2P`** — the running
  `wpa_supplicant` has no P2P device, so no group can be started. It comes up with
  the client interface, so check that `wlan0` is connected and that the supplicant
  was not started with `p2p_disabled=1`.
  `sudo wpa_cli -p /run/wpa_supplicant -i wlan0 status` prints a
  `p2p_device_address=` line while P2P is live.
- **`cannot use Wi-Fi Direct: no wpa_supplicant control socket in …`** — nothing to
  talk to. Look in `/run/wpa_supplicant/`: you should see the client's socket, plus a
  `p2p-dev-<client>` socket on drivers that provide a dedicated P2P device. As a
  non-root user that directory is unreadable and `detect` says "run as root to
  confirm" instead.
- **`cannot use Wi-Fi Direct: the driver cannot put a group owner on a channel of
  its own`** — the driver's interface combinations never allow `P2P-GO` next to
  `managed` on more than one channel, so a group owner would have to share the
  client's channel; `MODE=same` (hostapd) does that better.
- **`cannot share this connection: … cannot host an access point …`** — the
  uplink's channel is unusable for an AP (DFS/"no IR"/6 GHz) and Wi-Fi Direct is
  unavailable. Reconnect on a hostable channel.
- **`Error executing command as another user: No authentication agent found`**
  (pkexec) — no polkit agent was reachable from that shell (typical on a bare
  TTY). Run `sudo wifi-hotspot …`, keep a polkit agent running in your session, or
  set `WIFI_HOTSPOT_ELEVATE=sudo`.
- **`wpa_supplicant couldn't grab this interface`** — NetworkManager is trying to
  manage `ap0`. The tool sets it unmanaged (`nmcli device set ap0 managed no`);
  check `nmcli device status` if it recurs.
- **`Name not unique on network`** — the AP interface reused the client's MAC. The
  tool assigns a unique locally-administered MAC, so update if you see this.

## Uninstall

```sh
sudo systemctl disable --now wifi-hotspot.service
sudo make uninstall
```

## License

MIT — see [LICENSE](LICENSE).
