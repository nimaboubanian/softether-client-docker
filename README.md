# SoftEther VPN Client — Docker

Containerized [SoftEther VPN Client](https://www.softether.org/) v4.44 with
tinyproxy (HTTP) + Dante (SOCKS5) running over the VPN tunnel.

## Requirements

**Host (for building the image):**

| Requirement | Why |
|---|---|
| Linux x86_64 | Pre-compiled SoftEther archive is x86_64-only |
| Docker Engine + Compose plugin | Build and run |
| `gcc`, `make`, `binutils` (`strip`) | Compile the SoftEther binary against the host glibc |
| glibc toolchain | Ubuntu 26.04 runtime image requires glibc, not musl |

**Host (for running the published image, no build needed):**

| Requirement | Why |
|---|---|
| Docker Engine + Compose plugin | Run the container |
| `/dev/net/tun` available | SoftEther virtual adapter |
| Ports `8888` and `1080` free on the host | HTTP and SOCKS5 proxy listeners |
| Outbound TCP `443` (or whatever the SoftEther server uses) | Reach the VPN server |

**Server side:**

The SoftEther server must be reachable from the container's bridge network and
provide a DHCP lease on the virtual network. The container derives the tunnel
gateway from the assigned IP and replaces its default route through it. Full-
tunnel NAT on the server side is required for proxy egress to appear as the
server's public IP.

## Quick start (build from source)

Drop one or more `*.vpn` SoftEther client profiles into `vpn-profiles/`
(the first one found is imported on startup). Link SoftEther on the host,
then build and start:

```sh
sh ./build-softether.sh
docker compose up -d --build
```

Compose uses host networking only while installing Ubuntu packages; the
running service stays on the dedicated `vpn-net` bridge. Run
`sh ./test-host-build.sh` to verify the host-built runtime artifacts.

Use the proxies at `localhost:8888` (HTTP) and `localhost:1080` (SOCKS5).
The container creates the SoftEther virtual adapter, connects the profile,
obtains its tunnel address via DHCP, replaces the container's default route
through the VPN, and keeps reconnecting until the daemon stops or the
container is stopped.

To use environment credentials instead, copy `.env.example` to `.env` and set
`SE_HOST`, `SE_HUB`, `SE_USER`, and `SE_PASSWORD`. Complete environment
credentials take priority over the profile.

`vpn-profiles/*.vpn` contain authentication data and are excluded from Git.

## Using the published image (Docker Hub)

Pull from Docker Hub instead of building locally:

```sh
docker pull <your-dockerhub-username>/softether-vpn-client:latest
```

Create a working directory anywhere:

```sh
mkdir softether-client && cd softether-client
```

Download `compose.yaml` from the GitHub repo (or copy it locally). Edit the
`image:` line so it matches the published tag:

```yaml
image: <your-dockerhub-username>/softether-vpn-client:latest
```

Drop your profile in:

```sh
mkdir vpn-profiles
cp /path/to/your-profile.vpn vpn-profiles/main.vpn
```

Start:

```sh
docker compose up -d
```

Verify proxy egress:

```sh
curl -x http://localhost:8888 https://api.ipify.org
curl --socks5-hostname localhost:1080 https://api.ipify.org
```

Both should return the VPN server's public IP.

### Using environment credentials instead of a profile file

```sh
cp .env.example .env
$EDITOR .env   # set SE_HOST, SE_HUB, SE_USER, SE_PASSWORD
docker compose up -d
```

## Routing all host traffic through the tunnel (tun2proxy)

The container exposes two proxies: HTTP on `:8888` and SOCKS5 on `:1080`. Apps
that respect `http_proxy` / `SOCKS5_PROXY` env vars, or that let you configure
a SOCKS5 endpoint directly, can use them and route through the tunnel. The
rest of the system — desktop apps, system services, anything that doesn't
honor proxy env vars — bypasses the tunnel entirely.

**Use this section if you want every byte leaving the host (TCP, UDP, DNS,
every app) to go through the VPN tunnel.** It adds a userspace TUN interface
on the host that intercepts all IP traffic and forwards it through the
container's SOCKS5 endpoint into the SoftEther tunnel.

### When to set this up

- You want system-wide tunneling without reconfiguring each app.
- You want UDP and DNS to go through the tunnel too (the proxies themselves
  don't cover arbitrary app traffic — only what you point at them).
- You're okay with a small CPU/latency overhead from userspace packet
  processing.

Skip it if you only need browsers or a handful of CLI tools to use the VPN
— point those at `localhost:1080` directly and leave the rest of the system
alone.

### How it fits

```
app ──► tun0 ──► tun2proxy ──► SOCKS5 localhost:1080 ──► danted (container)
   │                                                          │
   └─ eth0 (loopback, Docker bridge, SoftEther server IP)     │
                                                              ▼
                                              SoftEther tunnel ──► internet
```

Three routing rules on the host:

| Rule | Why |
|---|---|
| `to 127.0.0.0/8 → main` | Don't route loopback through the TUN — `localhost:1080` itself must remain reachable directly |
| `to 172.30.0.0/24 → main` | Keep the Docker bridge reachable so the SOCKS5 connection itself can complete |
| `default → 10.0.0.2 via tun0` | Everything else enters the TUN |

The container already pins the SoftEther server IP (`202.61.228.196`) via
`eth0` (see `pin_vpn_server_route` in `entrypoint.sh`), so the tunnel
transport stays reachable even after the host's default route flips to
`tun0`. No conflict.

### Prerequisites

| Requirement | Why |
|---|---|
| `tun2proxy` binary | Userspace TUN → SOCKS5 forwarder. Rust, single static binary, no deps. |
| `iproute2` (`ip` command) | Manage TUN interface and routing rules |
| Root or `CAP_NET_ADMIN` | Create TUN, change routes |

Install `tun2proxy`:

```sh
# Linux x86_64 binary release
curl -L https://github.com/tun2proxy/tun2proxy/releases/latest/download/tun2proxy-x86_64-unknown-linux-gnu -o /usr/local/bin/tun2proxy
chmod +x /usr/local/bin/tun2proxy
```

### One-shot setup

Run as root. The container must already be up so `localhost:1080` is
listening.

```sh
# 1. Bring up the TUN device with a static peer (tun2proxy acts as 10.0.0.2)
ip tuntap add dev tun0 mode tun
ip addr add 10.0.0.1/30 dev tun0
ip link set tun0 up

# 2. Run tun2proxy in the background; it owns tun0 and forwards via SOCKS5
tun2proxy --tun tun0 --proxy socks5h://127.0.0.1:1080 &

# 3. Keep loopback and Docker bridge on the original interface
ip rule add to 127.0.0.0/8 pref 100 lookup main
ip rule add to 172.30.0.0/24 pref 100 lookup main

# 4. Send everything else through the TUN
ip route replace default via 10.0.0.2 dev tun0
```

### Verification

```sh
ip route show default                  # → "default via 10.0.0.2 dev tun0"
curl https://api.ipify.org             # → 202.61.228.196 (the VPN server)
nslookup google.com                    # resolves via SOCKS5 → tunnel
traceroute 1.1.1.1                     # first hop is tun0, no direct eth0 leak
```

If `curl` still returns your real ISP IP, the `lookup main` rules aren't
matching — check `ip rule show` order. Rules with lower `pref` win; the
loopback and Docker bridge rules must come before the default.

### Teardown (restore direct internet)

```sh
ip route replace default via 192.168.156.203 dev wlp3s0   # your real gateway
ip rule del to 127.0.0.0/8 pref 100 lookup main
ip rule del to 172.30.0.0/24 pref 100 lookup main
pkill tun2proxy
ip link del tun0
```

Replace `192.168.156.203 dev wlp3s0` with your actual default gateway and
physical interface (`ip route show default` shows it before tun2proxy was
set up).

### Running tun2proxy as a systemd service

`/etc/systemd/system/tun2proxy.service`:

```ini
[Unit]
Description=tun2proxy — TUN-to-SOCKS5 forwarder into SoftEther VPN
After=docker.service
Wants=docker.service

[Service]
Type=simple
ExecStartPre=/usr/sbin/ip tuntap add dev tun0 mode tun
ExecStartPre=/usr/sbin/ip addr add 10.0.0.1/30 dev tun0
ExecStartPre=/usr/sbin/ip link set tun0 up
ExecStartPre=/usr/sbin/ip rule add to 127.0.0.0/8 pref 100 lookup main
ExecStartPre=/usr/sbin/ip rule add to 172.30.0.0/24 pref 100 lookup main
ExecStartPre=/usr/sbin/ip route replace default via 10.0.0.2 dev tun0
ExecStart=/usr/local/bin/tun2proxy --tun tun0 --proxy socks5h://127.0.0.1:1080
ExecStopPost=/usr/sbin/ip route replace default via 192.168.156.203 dev wlp3s0
ExecStopPost=/usr/sbin/ip rule del to 127.0.0.0/8 pref 100 lookup main
ExecStopPost=/usr/sbin/ip rule del to 172.30.0.0/24 pref 100 lookup main
ExecStopPost=/usr/sbin/ip link del tun0
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Then:

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now tun2proxy
```

Update the gateway/iface values in `ExecStopPost` to match your host before
enabling.

### Caveats

- **Latency**: userspace packet processing adds ~5–20 ms. For high-throughput
  workloads, prefer running `vpnclient` directly on the host (option 1 in
  this conversation) instead of proxying through a container.
- **IPv6**: tun2proxy handles IPv6, but your network stack may not be ready
  for "all traffic" v6 routing. Test before relying on it.
- **SoftEther server public IP must stay reachable**: if `202.61.228.196`
  isn't pinned through `eth0`, the tunnel transport dies the moment the
  default route flips to `tun0`. The container's `pin_vpn_server_route`
  handles this for you.
- **Docker containers on the same host**: containers on other bridges
  (`172.17.0.0/16`, custom subnets) need their own `ip rule add to ... lookup
  main` lines, or they get caught in the TUN and break.

## Networking

A dedicated bridge network `vpn-net` (172.30.0.0/24) is created. The container
gets a static IP `172.30.0.10`. Other services on the same network reach the
proxies at `vpn-client:8888` (HTTP) and `vpn-client:1080` (SOCKS5). The host
reaches them on `localhost`.

The VPN server must provide a DHCP lease on the virtual network (the
entrypoint derives the tunnel gateway from the assigned IP and replaces the
container's default route through it). The VPN server's transport IP is pinned
through Docker's network so the tunnel stays reachable after the default route
changes. The container keeps reconnecting until the daemon stops or the
container is stopped.

## Logs

```sh
docker compose logs -f vpn-client
```

Use `docker compose logs` for entrypoint, SoftEther, and SOCKS output. Tinyproxy
writes to `/var/log/tinyproxy.log` inside the container.

## Files

| File | Purpose |
|---|---|
| `build-softether.sh` | Links the precompiled SoftEther libraries with the host's glibc toolchain and stages runtime artifacts |
| `Dockerfile` | Installs Ubuntu 26.04 runtime packages and copies the host-built SoftEther artifacts |
| `compose.yaml` | `vpn-net` bridge network, `NET_ADMIN` + `/dev/net/tun`, host port mapping, optional env overrides, profile and `vpnconfig` mounts |
| `entrypoint.sh` | Creates the virtual adapter, imports/connects the profile or configures an env account, gets a tunnel lease, starts proxies |
| `tinyproxy.conf` | HTTP proxy bound to `0.0.0.0:8888`, allows RFC1918 + loopback |
| `danted.conf` | Dante SOCKS5 listener on `:1080`, restricted to local clients and VPN egress |
