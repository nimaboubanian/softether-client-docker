# SoftEther VPN Client — Docker

Containerized [SoftEther VPN Client](https://www.softether.org/) v4.44 with
tinyproxy (HTTP) + Dante (SOCKS5) running over the VPN tunnel.

## Quick start

The supplied `client-softether.vpn` profile is mounted read-only and imported
on startup. Link SoftEther on the host, then build and start:

```sh
sh ./build-softether.sh
docker compose up -d --build
```

Host build prerequisites are `gcc`, `make`, `binutils`, and Linux x86_64. The
generated artifacts stay in the ignored `build/` directory. Compose uses host
networking only while installing Ubuntu packages; the running service stays on
the dedicated `vpn-net` bridge. Run `sh ./test-host-build.sh` to verify the
host-built runtime artifacts.

Use the proxies at `localhost:8888` (HTTP) and `localhost:1080` (SOCKS5).
The container creates the SoftEther virtual adapter, connects the profile,
obtains its tunnel address via DHCP, and routes proxy egress through the VPN.

To use environment credentials instead, copy `.env.example` to `.env` and set
`SE_HOST`, `SE_HUB`, `SE_USER`, and `SE_PASSWORD`. Complete environment
credentials take priority over the profile.

`client-softether.vpn` contains authentication data and is excluded from Git.

## Networking

A dedicated bridge network `vpn-net` (172.30.0.0/24) is created. The container
gets a static IP `172.30.0.10`. Other services on the same network reach the
proxies at `vpn-client:8888` (HTTP) and `vpn-client:1080` (SOCKS5). The host
reaches them on `localhost`.

The VPN server must provide DHCP with a default gateway on the virtual network;
the entrypoint fails before starting the proxies if the VPN connection or
tunnel route is unavailable. The VPN server's route is pinned through Docker's
network so the tunnel transport stays reachable after the default route changes.

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
