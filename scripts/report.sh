#!/bin/sh
# report.sh — quick diagnostics. Invoked via `docker exec softether-vpn-client report.sh`.
set -u

ACCT=$(sed -n 's/^[[:space:]]*string AccountName //p' /vpnclient/client-softether.vpn 2>/dev/null | sed 's/\$20/ /g' | tr -d '\r')
ACCT=${ACCT:-${SE_USER:-}}

echo "== Process =="
for p in vpnclient gost; do
    pid=$(pgrep -x "$p" 2>/dev/null | head -1)
    [ -n "$pid" ] && echo "  $p UP   pid=$pid" || echo "  $p NOT RUNNING"
done

echo
echo "== VPN session =="
if [ -n "$ACCT" ]; then
    status=$(vpncmd /CLIENT localhost /CMD AccountStatusGet "$ACCT" 2>/dev/null || true)
    if printf '%s\n' "$status" | grep -q 'Connection Completed'; then
        printf '%s\n' "$status" | grep -E 'Session Status|Server Name|Hub Name|VPN Client IP' | sed 's/^/  /'
    else
        echo "  NOT CONNECTED (account: $ACCT)"
    fi
else
    echo "  (no account — profile not imported yet; see docker logs)"
fi

echo
echo "== Egress IP (via proxy 127.0.0.1:1080) =="
ip=$(curl -s --max-time 10 --proxy http://127.0.0.1:1080 'https://api.ipify.org' 2>/dev/null) \
    && echo "  $ip" || echo "  unreachable"
