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
