#!/bin/sh
# vpn-status.sh - one-shot tunnel status. Re-runnable, read-only.
set -u

hr() { printf '%s\n' "========================================"; }
sec() { printf '\n=== %s ===\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

ACCT=$(sed -n 's/^[[:space:]]*string AccountName //p' /vpnclient/client-softether.vpn 2>/dev/null | sed 's/\$20/ /g' | tr -d '\r')
ACCT=${ACCT:-${SE_USER:-}}

hr
sec "Daemons"
for p in vpnclient gost; do
    pid=$(pgrep -x "$p" 2>/dev/null | head -1)
    if [ -n "$pid" ]; then printf "  %-10s UP   pid=%s\n" "$p" "$pid"
    else printf "  %-10s DOWN\n" "$p"; fi
done

sec "VPN session"
if [ -n "$ACCT" ] && have vpncmd; then
    out=$(vpncmd /CLIENT localhost /CMD AccountStatusGet "$ACCT" 2>&1)
    if printf '%s\n' "$out" | grep -q 'Connection Completed'; then
        printf '%s\n' "$out" | grep -E \
            'Session Status|Server Name|Hub Name|VPN Client IP|Virtual MAC|Established Session|Number of (TCP|UDP) Connections|Total Bytes' \
            | sed 's/^/  /'
    else
        echo "  state: NOT CONNECTED"
    fi
else
    echo "  (skipped: no account or no vpncmd)"
fi

sec "Interfaces & routes"
ip -br addr 2>/dev/null | sed 's/^/  /'
echo "  --- default ---"
ip -4 route show default 2>/dev/null | sed 's/^/  /'

sec "Egress IP via :1080 (what the world sees)"
if have curl; then
    printf "  http  -> "
    curl -sS --max-time 5 --proxy http://127.0.0.1:1080 https://ifconfig.co || echo "(failed)"
    printf "  socks -> "
    curl -sS --max-time 5 --proxy socks5h://127.0.0.1:1080 https://ifconfig.co || echo "(failed)"
fi

hr
