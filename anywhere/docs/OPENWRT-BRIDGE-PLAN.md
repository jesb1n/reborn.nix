# OpenWrt bridge-mode migration — eliminating double NAT

Goal: stop `oracle-in-arm1` (and any future peer) from falling back to the
Tailscale DERP relay by removing one of the two NAT layers at the home site.

Status: **planned, not executed.**

## Why

`tailscale netcheck` on s145 and nuc7i3 reports:

```
UDP: true
IPv4: yes, <HOME-WAN-IP>:64736 / :62142 / :64654   ← different port every probe
MappingVariesByDestIP: true                         ← symmetric NAT
PortMapping:                                        ← no UPnP, no NAT-PMP
```

A fresh external port per probe is symmetric NAT. Tailscale cannot predict the
mapping, so hole-punching fails and traffic falls back to DERP `blr`.

Measured cost (iperf3, 8s single-stream TCP over `tailscale0`):

| path | type | throughput |
|---|---|---|
| s145 ↔ oracle-eu-arm1 | direct | ~40 Mbit/s |
| oracle-in-arm1 ↔ oracle-eu-arm1 | direct | ~41 Mbit/s |
| s145 ↔ oracle-in-arm1 | **relay "blr"** | ~23 Mbit/s |
| nuc7i3 ↔ oracle-in-arm1 | **relay "blr"** | ~23 Mbit/s |

Roughly half throughput on relayed paths, plus an extra hop. s145 has already
pushed 13.6 GB to oracle-in-arm1 over the relay.

### Root cause

Two sequential NAT layers. `ttl=62` from s145 to ISP transit `172.24.32.1`
confirms exactly two routing devices:

```
s145 ──wired── jidu6811-openwrt ──── main router (ISP) ──── ISP
               44:fa:66:a0:04:11     b4:86:18:a2:0c:d6      172.24.32.1
               192.168.10.1 (LAN)    192.168.1.1 (LAN)      <HOME-WAN-IP>
               192.168.1.33 (WAN)
```

Each layer rewrites the source port; the outer one allocates randomly. That is
what produces `MappingVariesByDestIP: true`.

**Not CGNAT.** `api.ipify.org` returns `<HOME-WAN-IP>` from both hosts, matching
Tailscale's STUN view, and hop 3 is RFC1918 ISP transit rather than `100.64/10`.
A real port forward is therefore achievable.

### Already fixed (2026-10-06)

The OpenWrt LAN originally used `192.168.1.0/24` — the *same* subnet as its own
WAN side, with both gateways answering to `192.168.1.1`. LAN has since been
renumbered to `192.168.10.0/24`. This removed a genuine routing ambiguity but
did **not** change the NAT behaviour, which is confirmed still symmetric. The
collision was a separate bug.

### Why UPnP alone will not work

```
upnpc -s            (OpenWrt segment)  → No IGD UPnP Device found
natpmpc                                → gateway does not support nat-pmp
upnpc -m wlp2s0 -s  (main router seg.) → No IGD UPnP Device found
```

Neither router runs a port-mapping daemon. Installing `miniupnpd` on OpenWrt
would map ports on `192.168.1.33` — a private address behind the main router —
which is useless from the internet. Bridge mode must come first.

## Main router

```
Server: Boa/0.93.15
Location: /admin/login.asp
ports: 80 open, 443 open, 22 filtered, 23 closed
MAC: b4:86:18:a2:0c:d6
```

Boa + `/admin/login.asp` is typical ISP-supplied GPON/ONT firmware (Asianet).
Exact model unconfirmed — the login page exposes nothing but `logo.jpg`.

**Blocker to resolve before starting: admin credentials for this device.**
Step 3 cannot be completed without them. If the ISP has locked the admin
account, stop and use the fallback in "If bridge mode is not possible".

## Safety net

All work is driven over Tailscale, never the LAN:

```bash
ssh duck@100.69.231.117     # s145 — verified working, do NOT use `ssh duck@s145`
```

`ssh duck@s145` resolves via MagicDNS/LAN and may break mid-migration. Use the
literal `100.69.231.117`.

Why this holds: `tailscaled` is `enabled` + `active`, state persists in
`/var/lib/tailscale/tailscaled.state`, and the tunnel re-establishes over
whatever path exists — including a DHCP renumber. Tailscale is the out-of-band
channel precisely because it does not depend on the LAN addressing being stable.

k3s is unaffected: `--flannel-iface=tailscale0` and `nodeIP` is the tailnet
address. Cluster traffic never touches `192.168.x.x`.

**Do not** run these steps from a LAN-attached SSH session.

## Pre-flight

1. **Get OpenWrt SSH access working from s145.** Currently password-only:
   ```
   root@192.168.10.1: Permission denied (publickey,password)
   ```
   Install a key so the migration is non-interactive and survives a dropped
   session:
   ```bash
   ssh duck@100.69.231.117
   ssh-copy-id root@192.168.10.1        # one-time, needs the router password
   ssh root@192.168.10.1 'echo REACHED' # must print REACHED
   ```

2. **Record the current state** for rollback:
   ```bash
   ssh root@192.168.10.1 'uci export network > /root/network.backup.$(date +%F)'
   ssh root@192.168.10.1 'uci export dhcp    > /root/dhcp.backup.$(date +%F)'
   ssh root@192.168.10.1 'uci export firewall > /root/firewall.backup.$(date +%F)'
   ```

3. **Confirm physical access to the OpenWrt box.** If bridging goes wrong the
   only recovery is the reset button / failsafe mode. Do not attempt remotely
   without someone able to reach the hardware.

4. **Note the OpenWrt version** to pick the right package name later:
   ```bash
   ssh root@192.168.10.1 'ubus call system board'
   ```
   22.03+ uses `miniupnpd-nftables`; older `fw3` builds use `miniupnpd`.

## Step 1 — disable the s145 WiFi leg

s145 is currently dual-homed and the WiFi path is **dead**: `curl --interface
wlp2s0 https://api.ipify.org` times out, while the wired path returns
`<HOME-WAN-IP>`. After bridging, both legs would land on `192.168.1.0/24`,
creating an asymmetric-routing hazard and giving Tailscale a bogus path
candidate.

Edit `anywhere/hosts/s145/configuration.nix` — set the WiFi profile's
`autoconnect = false` (keep the credentials and the profile; this is a laptop
and the WiFi is genuine fallback hardware).

**Also review `anywhere/hosts/s145/wifi-watchdog.nix`.** Its header states
"s145 is a laptop with no ethernet port — WiFi (wlp2s0) is the single network
path", which is no longer true: it has a USB ethernet adapter and the wired link
is now the default route at metric 100. The watchdog pings the *default route's*
gateway, so post-change it will test the wired path and bounce the WiFi radio on
failure — wrong remedy for the wrong interface. Either scope it to the wired
link or disable it. Do not leave it as-is.

Deploy and verify before touching any router:

```bash
cd anywhere/
nix flake check
nix develop -c deploy .#s145
ssh duck@100.69.231.117 'ip -4 -o addr show | grep 192.168'   # expect wired only
```

## Step 2 — bridge the OpenWrt box

Converts it from a NATing router to a pure AP/switch. **This drops the LAN.**
Run it from the Tailscale session on s145.

Choose a static address on the main router's subnet, outside its DHCP pool —
`192.168.1.2` below. Confirm the pool range in the main router's admin UI first.

```sh
# on the OpenWrt box, via: ssh duck@100.69.231.117 → ssh root@192.168.10.1
# Single pasted block — connectivity drops partway through.

# 1. stop serving DHCP (main router takes over)
uci set dhcp.lan.ignore='1'

# 2. remove the WAN interfaces and their firewall zone
uci delete network.wan
uci delete network.wan6
uci delete firewall.@zone[1]        # verify index first: uci show firewall | grep wan

# 3. fold the former WAN port into the LAN bridge
#    port name is device-specific — check `uci show network` output
uci add_list network.@device[0].ports='wan'

# 4. static LAN address on the MAIN router's subnet, no NAT
uci set network.lan.proto='static'
uci set network.lan.ipaddr='192.168.1.2'
uci set network.lan.netmask='255.255.255.0'
uci set network.lan.gateway='192.168.1.1'
uci set network.lan.dns='192.168.1.1'

uci commit
reload_config
```

Then force DHCP renewal on both hosts (over Tailscale):

```bash
ssh duck@100.69.231.117 'sudo nmcli con down s145-wired && sudo nmcli con up s145-wired'
ssh duck@100.119.33.56  'sudo nmcli con down "$(nmcli -t -f NAME,DEVICE con show --active | grep eno1 | cut -d: -f1)" && sudo nmcli con up ...'
```

Expected after: both hosts hold `192.168.1.x` leases from the main router, and
LuCI answers at `192.168.1.2`.

## Step 3 — static port forward on the main router

Bridge mode gives single NAT but **not** port mapping — the main router runs no
UPnP either. One forward per host; they cannot share a port.

1. DHCP reservation for s145 and nuc7i3 (by MAC) so the leases are stable:
   - s145 wired: `enp3s0f3u2`, adapter is a TP-Link UE300 (`r8152`)
   - nuc7i3: `94:C6:91:1D:19:89`
2. Forward `UDP 41641 → s145`, `UDP 41642 → nuc7i3`.
3. Pin the ports in Nix so Tailscale stops choosing randomly:

```nix
# anywhere/hosts/s145/configuration.nix
services.tailscale.extraUpFlags = [ "--hostname=s145" "--accept-dns=false" "--port=41641" ];

# anywhere/hosts/nuc7i3/configuration.nix
services.tailscale.extraUpFlags = [ ... "--port=41642" ];
```

Deploy nuc7i3 first, s145 (control-plane) last, one host per invocation.

## Step 4 — verify

```bash
# symmetric NAT should be gone
ssh duck@100.69.231.117 'tailscale netcheck | grep -E "UDP:|IPv4:|MappingVaries|PortMapping"'
#   want: MappingVariesByDestIP: false   and a STABLE port across repeated runs

# the relayed peer should go direct
ssh duck@100.69.231.117 'tailscale status | grep arm1'
#   want: oracle-in-arm1 ... direct <ORACLE-IN-WAN-IP>:41641   (not: relay "blr")

# re-measure
ssh duck@100.69.231.117 'nix-shell -p iperf3 --run "iperf3 -c 100.117.227.112 -t 8"'
#   want: ~40 Mbit/s, up from ~23
```

Run `netcheck` at least 3 times — a single `false` is not proof.

## Rollback

```sh
ssh root@192.168.1.2 'uci import network < /root/network.backup.YYYY-MM-DD'
ssh root@192.168.1.2 'uci import dhcp    < /root/dhcp.backup.YYYY-MM-DD'
ssh root@192.168.1.2 'uci import firewall < /root/firewall.backup.YYYY-MM-DD'
ssh root@192.168.1.2 'uci commit && reboot'
```

If the box is unreachable: OpenWrt failsafe mode (power on, press reset when the
LED flashes) exposes `192.168.1.1` with no config applied.

Revert the Nix changes with `git revert` and redeploy; or on a host that lost
its path, `sudo nixos-rebuild switch --rollback` locally.

## If bridge mode is not possible

If the main router's admin is locked by the ISP, fall back in this order:

1. **DMZ** the OpenWrt WAN IP (`192.168.1.33`) on the main router, then run
   `miniupnpd` on OpenWrt — it becomes effectively edge.
2. **Chained forward**: main router `UDP 41641 → 192.168.1.33`, OpenWrt
   `UDP 41641 → s145`, plus `--port=41641`. Now configurable since the subnet
   collision is resolved.
3. Accept DERP for `oracle-in-arm1` and move latency-sensitive workloads onto
   s145/nuc7i3/oracle-eu-arm1.

## Unrelated but worth doing at the same time

s145's TP-Link UE300 is a **gigabit** adapter currently enumerated on a USB 2.0
bus:

```
Bus 001.Port 001: root_hub, xhci_hcd/4p, 480M
    |__ Port 002: Dev 002, Driver=r8152, 480M      ← UE300 here
Bus 002.Port 001: root_hub, xhci_hcd/4p, 10000M    ← free SuperSpeed, 4 ports
Bus 004.Port 001: root_hub, xhci_hcd/1p, 10000M    ← free SuperSpeed, 1 port
```

`ethtool` shows the switch offering `1000baseT/Full` while the adapter only
advertises 10/100 — the `r8152` driver drops gigabit when not on a SuperSpeed
link. Result: s145's busiest interface is capped at 100 Mb/s (measured 89 Mbit/s
to nuc7i3, ~95% of line rate).

Move it to a blue USB 3.0 port. Expect `5000M` in `lsusb -t` and `1000` in
`/sys/class/net/*/speed`.

**Caution:** the interface name `enp3s0f3u2` encodes the USB topology path, so a
different port yields a different name. Grep the repo for the old name before
moving, and expect the NetworkManager `s145-wired` profile (which matches on
type, not name) to still work.
