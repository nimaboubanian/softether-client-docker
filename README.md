# SoftEther VPN Client — Docker

Containerized [SoftEther VPN Client](https://www.softether.org/) v4.44 with a
[gost](https://github.com/go-gost/gost) proxy serving HTTP and SOCKS5 on a
single port over the VPN tunnel.

## Requirements

- Linux x86_64 host with `gcc`, `make`, `binutils` (the SoftEther archive is
  pre-compiled x86_64 and links against glibc)
- Docker Engine + Compose plugin
- `/dev/net/tun` available
- The SoftEther server must be reachable and provide a DHCP lease on the
  virtual network; full-tunnel NAT on the server side makes proxy egress
  appear as the server's public IP

## Quick start

Drop a `*.vpn` SoftEther client profile into `vpn-profiles/` (the first one
found is imported on startup), then:

```sh
sh ./scripts/build-softether.sh
docker compose up -d --build
```

Proxy: `localhost:1080` — one port, both HTTP and SOCKS5 (gost auto-detects
per connection). The container creates the virtual adapter, connects, gets a
DHCP lease, replaces its default route through the VPN, and reconnects until
stopped.

Or use environment credentials instead of a profile (takes priority):

```sh
cp .env.example .env   # set SE_HOST, SE_HUB, SE_USER, SE_PASSWORD
docker compose up -d
```

With several profiles mounted, pick one by name (without `.vpn`):

```sh
echo 'VPN_PROFILE=DEFAULT-main' >> .env
```

`vpn-profiles/*.vpn` contain authentication data and are excluded from Git.

## Using a published image

```sh
docker pull <user>/softether-vpn-client:latest
```

Point `image:` at the tag, drop a profile into `vpn-profiles/`, and
`docker compose up -d`.

## Verify

```sh
curl -x http://localhost:1080 https://api.ipify.org
curl --socks5-hostname localhost:1080 https://api.ipify.org
```

Both should return the VPN server's public IP. One-shot diagnostics
report (daemons, session, egress IP):

```sh
docker exec softether-vpn-client report.sh
```

Logs: `docker compose logs -f vpn-client`. Account names containing spaces
must be quoted for `vpncmd`, e.g. `AccountStatusGet "DEFAULT - main"`.

## Files

| File | Purpose |
|---|---|
| `scripts/build-softether.sh` | Links the pre-compiled SoftEther libs, stages runtime artifacts in `build/softether/` |
| `scripts/test-host-build.sh` | Verifies host-built artifacts |
| `Dockerfile` | Ubuntu 26.04 runtime + host-built SoftEther binaries + pinned gost release |
| `compose.yaml` | NET_ADMIN + `/dev/net/tun`, host port mapping, env overrides, profile mount |
| `scripts/entrypoint.sh` | Adapter setup, connect, tunnel default route, proxy, keepalive |
| `scripts/report.sh` | Compact one-shot diagnostics report (`docker exec ... report.sh`) |

SoftEther license files (`ReadMeFirst_License.txt`,
`ReadMeFirst_Important_Notices_*.txt`) are preserved in the image for
redistribution.
