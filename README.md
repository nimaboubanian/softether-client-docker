# SoftEther VPN Client — Docker

Containerized [SoftEther VPN Client](https://www.softether.org/) v4.44 with
tinyproxy (HTTP) + microsocks (SOCKS5) running over the VPN tunnel.

## Quick start

1. Copy and edit credentials:
   ```sh
   cp .env.example .env
   $EDITOR .env
   ```
2. Build and start:
   ```sh
   docker compose up -d --build
   ```
3. Use the proxies:
   - HTTP: `localhost:8888`
   - SOCKS5: `localhost:1080`

## Networking

A dedicated bridge network `vpn-net` (172.30.0.0/24) is created. The container
gets a static IP `172.30.0.10`. Other services on the same network reach the
proxies at `vpn-client:8888` (HTTP) and `vpn-client:1080` (SOCKS5). The host
reaches them on `localhost`.

## Mounting a pre-baked config

To skip the `AccountCreate` step, generate the config once on the host with
`vpncmd`, then mount it:

```sh
docker compose cp ./vpn_client.config vpn-client:/vpnclient/vpn_client.config
docker compose exec vpn-client vpncmd /CLIENT localhost /CMD AccountConnect myacct
```

The container's entrypoint will see `/vpnclient/vpn_client.config` on the
`vpnconfig` volume and skip the env-var setup.

## Logs

```sh
docker compose logs -f vpn-client
```

Prefixes `[vpncmd]`, `[tinyproxy]`, `[microsocks]` are added by the entrypoint.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Multi-stage build: links `vpnclient`/`vpncmd` from prebuilt archive, copies runtime bits + proxies |
| `compose.yaml` | `vpn-net` bridge network, service with `NET_ADMIN` + `/dev/net/tun`, host port mapping, env, `vpnconfig` volume |
| `entrypoint.sh` | Starts `vpnclient`, configures/connects account from env or mounted config, starts proxies |
| `tinyproxy.conf` | HTTP proxy bound to `0.0.0.0:8888`, allows RFC1918 + loopback |
