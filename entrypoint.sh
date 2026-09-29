#!/bin/sh
set -eu

cd /vpnclient

cp /usr/share/softether/hamcore.se2 . 2>/dev/null || true

vpnclient start
sleep 1

if [ -n "${SE_HOST:-}" ] && [ -n "${SE_HUB:-}" ] && [ -n "${SE_USER:-}" ] && [ -n "${SE_PASSWORD:-}" ]; then
    SE_PORT="${SE_PORT:-443}"
    echo "[entrypoint] configuring account '$SE_USER' -> ${SE_HOST}:${SE_PORT} hub '$SE_HUB'"
    vpncmd /CLIENT localhost /CMD AccountDelete "$SE_USER" >/dev/null 2>&1 || true
    vpncmd /CLIENT localhost /CMD AccountCreate "$SE_USER" \
        /SERVER:"${SE_HOST}:${SE_PORT}" \
        /HUB:"$SE_HUB" \
        /USERNAME:"$SE_USER" \
        /PASSWORD:"$SE_PASSWORD" 2>&1 | sed 's/^/[vpncmd] /'
    vpncmd /CLIENT localhost /CMD AccountConnect "$SE_USER" 2>&1 | sed 's/^/[vpncmd] /'
    echo "[entrypoint] waiting for tunnel..."
    for i in 1 2 3 4 5 6 7 8 9 10; do
        if vpncmd /CLIENT localhost /CMD AccountStatusGet "$SE_USER" 2>/dev/null | grep -q "SessionStatus.*Connected"; then
            echo "[entrypoint] VPN connected"
            break
        fi
        sleep 2
    done
elif [ -f /vpnclient/vpn_client.config ]; then
    echo "[entrypoint] using mounted vpn_client.config"
else
    echo "[entrypoint] WARNING: no SE_* env and no mounted config — starting proxies only"
fi

echo "[entrypoint] starting tinyproxy on :8888"
tinyproxy -c /etc/tinyproxy/tinyproxy.conf 2>&1 | sed 's/^/[tinyproxy] /' &

echo "[entrypoint] starting microsocks on :1080"
microsocks -p 1080 2>&1 | sed 's/^/[microsocks] /' &

trap 'vpnclient stop; kill %1 %2 2>/dev/null; exit 0' TERM INT
wait
