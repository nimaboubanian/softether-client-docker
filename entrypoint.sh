#!/bin/sh
set -eu

cd /vpnclient

cp /usr/share/softether/hamcore.se2 . 2>/dev/null || true

ensure_nic() {
    if ! vpncmd /CLIENT localhost /CMD NicList | grep -Fq "$1"; then
        vpncmd /CLIENT localhost /CMD NicCreate "$1"
    fi
}

pin_vpn_server_route() {
    server_ip=$(getent ahostsv4 "$1" | awk 'NR == 1 { print $1 }')
    docker_gateway=$(ip -4 route show default | awk '$1 == "default" && $2 == "via" { print $3; exit }')
    if [ -z "$server_ip" ] || [ -z "$docker_gateway" ]; then
        echo "[entrypoint] cannot resolve VPN server or Docker gateway" >&2
        return 1
    fi
    ip -4 route replace "$server_ip/32" via "$docker_gateway" dev eth0
}

connect_vpn() {
    account_name=$1
    server_host=$2
    nic_name=$3
    vpn_interface="vpn_$(printf '%s' "$nic_name" | tr '[:upper:]' '[:lower:]')"

    pin_vpn_server_route "$server_host"
    vpncmd /CLIENT localhost /CMD AccountConnect "$account_name"

    echo "[entrypoint] waiting for VPN connection..."
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        status=$(vpncmd /CLIENT localhost /CMD AccountStatusGet "$account_name" 2>/dev/null || true)
        if printf '%s\n' "$status" | grep -Eq 'Session Status[[:space:]]*\|[[:space:]]*Connection Completed'; then
            echo "[entrypoint] VPN connected; requesting tunnel address"
            udhcpc -i "$vpn_interface" -q -n
            vpn_gateway=$(ip -4 route show default dev "$vpn_interface" | awk '$1 == "default" && $2 == "via" { print $3; exit }')
            if [ -z "$vpn_gateway" ]; then
                echo "[entrypoint] VPN DHCP did not install a default route" >&2
                return 1
            fi
            ip -4 route flush default
            ip -4 route replace default via "$vpn_gateway" dev "$vpn_interface"
            return 0
        fi
        sleep 2
    done

    echo "[entrypoint] VPN did not connect" >&2
    return 1
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
    connect_vpn "$SE_USER" "$SE_HOST" VPN
elif [ -f /client-softether.vpn ]; then
    cp /client-softether.vpn ./client-softether.vpn
    space_escape="\$20"
    account_name=$(sed -n 's/^[[:space:]]*string AccountName //p' client-softether.vpn | sed "s/$space_escape/ /g")
    server_host=$(sed -n 's/^[[:space:]]*string Hostname //p' client-softether.vpn)
    nic_name=$(sed -n 's/^[[:space:]]*string DeviceName //p' client-softether.vpn)
    if [ -z "$account_name" ] || [ -z "$server_host" ] || [ -z "$nic_name" ]; then
        echo "[entrypoint] invalid SoftEther profile: missing account, hostname, or device name" >&2
        exit 1
    fi
    ensure_nic "$nic_name"
    vpncmd /CLIENT localhost /CMD AccountDelete "$account_name" >/dev/null 2>&1 || true
    vpncmd /CLIENT localhost /CMD AccountImport client-softether.vpn
    connect_vpn "$account_name" "$server_host" "$nic_name"
else
    echo "[entrypoint] no VPN profile or complete SE_* credentials configured" >&2
    exit 1
fi

echo "[entrypoint] starting tinyproxy on :8888"
tinyproxy -c /etc/tinyproxy/tinyproxy.conf 2>&1 | sed 's/^/[tinyproxy] /' &

echo "[entrypoint] starting microsocks on :1080"
microsocks -p 1080 2>&1 | sed 's/^/[microsocks] /' &

trap 'vpnclient stop; kill %1 %2 2>/dev/null; exit 0' TERM INT
wait
