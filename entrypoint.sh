#!/bin/sh
set -eu

cd /vpnclient

cp /usr/share/softether/hamcore.se2 . 2>/dev/null || true

ensure_nic() {
    if vpncmd /CLIENT localhost /CMD NicList 2>/dev/null | grep -Eq "^[A-Za-z0-9._-]+\\|[[:space:]]*$1\$"; then
        return 0
    fi
    vpncmd /CLIENT localhost /CMD NicCreate "$1" >/dev/null 2>&1 || true
}

wait_for() {
    for _ in $(seq 1 30); do
        if "$@"; then return 0; fi
        sleep 1
    done
    return 1
}

pin_vpn_server_route() {
    server_host=$1
    if printf '%s' "$server_host" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        server_ip=$server_host
    else
        if ! wait_for getent ahostsv4 "$server_host"; then
            echo "[entrypoint] DNS did not resolve $server_host after 30s" >&2
            return 1
        fi
        server_ip=$(getent ahostsv4 "$server_host" | awk 'NR == 1 { print $1 }')
    fi
    if ! wait_for sh -c 'ip -4 route show default | grep -q "^default via "'; then
        echo "[entrypoint] no default route after 30s" >&2
        return 1
    fi
    docker_gateway=$(ip -4 route show default | awk '$1 == "default" && $2 == "via" { print $3; exit }')
    ip -4 route replace "$server_ip/32" via "$docker_gateway" dev eth0
    ip -4 route del default via "$docker_gateway" dev eth0 2>/dev/null || true
}

ensure_vpn_route() {
    vpn_interface=$(ip -4 -o link show 2>/dev/null | awk -F': ' '/vpn_/ {print $2; exit}')
    [ -n "$vpn_interface" ] || return 1
    if ip -4 route show default | grep -q "dev $vpn_interface"; then
        return 0
    fi
    vpn_ip=$(ip -4 -o addr show dev "$vpn_interface" 2>/dev/null | awk '{print $4}' | head -1 | cut -d/ -f1)
    if [ -z "$vpn_ip" ]; then
        dhclient -4 -1 "$vpn_interface" >/dev/null 2>&1 || true
        vpn_ip=$(ip -4 -o addr show dev "$vpn_interface" 2>/dev/null | awk '{print $4}' | head -1 | cut -d/ -f1)
    fi
    [ -n "$vpn_ip" ] || return 1
    vpn_gateway=$(echo "$vpn_ip" | awk -F. '{printf "%s.%s.%s.1", $1, $2, $3}')
    echo "[entrypoint] default route via $vpn_gateway dev $vpn_interface"
    ip -4 route replace default via "$vpn_gateway" dev "$vpn_interface"
}

connect_vpn() {
    account_name=$1
    server_host=$2
    nic_name=$3

    pin_vpn_server_route "$server_host"
    vpncmd /CLIENT localhost /CMD AccountConnect "$account_name" >/dev/null 2>&1 || true

    echo "[entrypoint] waiting for VPN connection..."
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        status=$(vpncmd /CLIENT localhost /CMD AccountStatusGet "$account_name" 2>/dev/null || true)
        if printf '%s\n' "$status" | grep -Eq 'Session Status[[:space:]]*\|[[:space:]]*Connection Completed'; then
            echo "[entrypoint] VPN connected; requesting tunnel address"
            ensure_vpn_route || true
            return 0
        fi
        sleep 2
    done

    echo "[entrypoint] VPN did not connect yet" >&2
    return 1
}

vpn_keepalive() {
    account_name=$1
    while true; do
        if ! pgrep -f 'vpnclient execsvc' >/dev/null 2>&1; then
            echo "[entrypoint] vpnclient daemon is no longer running; exiting" >&2
            kill %1 %2 2>/dev/null
            exit 0
        fi
        status=$(vpncmd /CLIENT localhost /CMD AccountStatusGet "$account_name" 2>/dev/null || true)
        if ! printf '%s\n' "$status" | grep -Eq 'Session Status[[:space:]]*\|[[:space:]]*Connection Completed'; then
            vpncmd /CLIENT localhost /CMD AccountConnect "$account_name" >/dev/null 2>&1 || true
        else
            ensure_vpn_route || true
        fi
        sleep 5
    done
}

vpnclient start
sleep 1

if [ -n "${SE_HOST:-}${SE_HUB:-}${SE_USER:-}${SE_PASSWORD:-}" ]; then
    : "${SE_HOST:?SE_HOST is required for environment-based VPN setup}"
    : "${SE_HUB:?SE_HUB is required for environment-based VPN setup}"
    : "${SE_USER:?SE_USER is required for environment-based VPN setup}"
    : "${SE_PASSWORD:?SE_PASSWORD is required for environment-based VPN setup}"
    SE_PORT="${SE_PORT:-443}"
    echo "[entrypoint] configuring account '$SE_USER' -> ${SE_HOST}:${SE_PORT} hub '$SE_HUB'"
    ensure_nic VPN
    vpncmd /CLIENT localhost /CMD AccountDelete "$SE_USER" >/dev/null 2>&1 || true
    vpncmd /CLIENT localhost /CMD AccountCreate "$SE_USER" \
        /SERVER:"${SE_HOST}:${SE_PORT}" \
        /HUB:"$SE_HUB" \
        /USERNAME:"$SE_USER" \
        /NICNAME:VPN
    vpncmd /CLIENT localhost /CMD AccountPasswordSet "$SE_USER" \
        /PASSWORD:"$SE_PASSWORD" /TYPE:standard
    sleep 5
    connect_vpn "$SE_USER" "$SE_HOST" VPN || true
elif [ -d /vpn-profiles ]; then
    set -- /vpn-profiles/*.vpn
    if [ ! -f "$1" ]; then
        echo "[entrypoint] no .vpn profile found in /vpn-profiles" >&2
        exit 1
    fi
    if [ -n "${VPN_PROFILE:-}" ]; then
        profile="/vpn-profiles/${VPN_PROFILE}.vpn"
        if [ ! -f "$profile" ]; then
            echo "[entrypoint] VPN_PROFILE='${VPN_PROFILE}' but '${profile}' not found in /vpn-profiles" >&2
            exit 1
        fi
        echo "[entrypoint] VPN_PROFILE='${VPN_PROFILE}' -> '$profile'"
    else
        profile=$(ls /vpn-profiles/*.vpn | head -1)
        if [ "$(ls /vpn-profiles/*.vpn | wc -l)" -gt 1 ]; then
            echo "[entrypoint] multiple .vpn profiles found; using '$profile'" >&2
        fi
    fi
    cp "$profile" ./client-softether.vpn
    space_escape="\$20"
    account_name=$(sed -n 's/^[[:space:]]*string AccountName //p' client-softether.vpn | sed "s/$space_escape/ /g" | tr -d '\r')
    server_host=$(sed -n 's/^[[:space:]]*string Hostname //p' client-softether.vpn | tr -d '\r')
    nic_name=$(sed -n 's/^[[:space:]]*string DeviceName //p' client-softether.vpn | tr -d '\r')
    if [ -z "$account_name" ] || [ -z "$server_host" ] || [ -z "$nic_name" ]; then
        echo "[entrypoint] invalid SoftEther profile: missing account, hostname, or device name" >&2
        exit 1
    fi
    ensure_nic "$nic_name"
    vpncmd /CLIENT localhost /CMD AccountDelete "$account_name" >/dev/null 2>&1 || true
    vpncmd /CLIENT localhost /CMD AccountImport client-softether.vpn
    sleep 5
    connect_vpn "$account_name" "$server_host" "$nic_name" || true
else
    echo "[entrypoint] no VPN profile or complete SE_* credentials configured" >&2
    exit 1
fi

echo "[entrypoint] starting tinyproxy on :8888"
tinyproxy -c /etc/tinyproxy/tinyproxy.conf 2>&1 | sed 's/^/[tinyproxy] /' &

echo "[entrypoint] starting SOCKS5 proxy on :1080"
danted -f /etc/danted.conf 2>&1 | sed 's/^/[danted] /' &

if [ -n "${account_name:-}" ]; then
    echo "[entrypoint] starting VPN keepalive (unlimited reconnect)"
    vpn_keepalive "$account_name" &
elif [ -n "${SE_USER:-}" ]; then
    echo "[entrypoint] starting VPN keepalive (unlimited reconnect)"
    vpn_keepalive "$SE_USER" &
fi

trap 'vpnclient stop; kill %1 %2 %3 2>/dev/null; exit 0' TERM INT
wait
