#!/bin/sh
# vpn-status.sh - single-shot tunnel status. Re-runnable, read-only.
set -u

PROFILE=/vpnclient/client-softether.vpn
hr() { printf '%s\n' "========================================"; }
sec() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }
field() { awk -v k="$1" 'BEGIN{RS="\r?\n"} $2==k && NF>=3 {print $NF; exit}' "$PROFILE" 2>/dev/null; }

if [ -f "$PROFILE" ]; then
    ACCT=$(field AccountName | sed 's/\$20/ /g')
fi
[ -z "${ACCT:-}" ] && ACCT="${SE_USER:-}"

hr
sec "Tunnel properties (from $PROFILE)"
if [ -f "$PROFILE" ]; then
    h=$(field Hostname); p=$(field Port); hub=$(field HubName); nic=$(field DeviceName)
    mx=$(field MaxConnection); enc=$(field UseEncrypt); cmp=$(field UseCompress)
    nudp=$(field NoUdpAcceleration); qos=$(field DisableQoS)
    pxt=$(field ProxyType); pxn=$(field ProxyName); pxp=$(field ProxyPort)
    case "${pxt:-0}" in
        0) pxr="none";;
        1) pxr="SOCKS4 ${pxn:-}:${pxp:-}";;
        3) pxr="SOCKS5 ${pxn:-}:${pxp:-}";;
        *) pxr="type=$pxt ${pxn:-}:${pxp:-}";;
    esac
    printf "  Account:        %s\n  Server:         %s:%s\n  Hub:            %s\n  NIC:            %s\n  MaxConn:        %s\n  Encrypt:        %s\n  Compress:       %s\n  NoUDPAccel:     %s\n  DisableQoS:     %s\n  UpstreamProxy:  %s\n" \
        "$ACCT" "$h" "$p" "$hub" "$nic" "$mx" "$enc" "$cmp" "$nudp" "$qos" "$pxr"
else
    printf "  (no .vpn) account=%s server=%s:%s hub=%s nic=VPN\n" \
        "$ACCT" "${SE_HOST:-?}" "${SE_PORT:-443}" "${SE_HUB:-?}"
fi

sec "Daemons"
for p in vpnclient tinyproxy danted; do
    pid=$(pgrep -x "$p" 2>/dev/null | head -1)
    if [ -n "$pid" ]; then printf "  %-10s UP   pid=%s\n" "$p" "$pid"
    else printf "  %-10s DOWN\n" "$p"; fi
done

sec "VPN session (AccountStatusGet)"
if [ -n "$ACCT" ] && have vpncmd; then
    out=$(vpncmd /CLIENT localhost /CMD AccountStatusGet "$ACCT" 2>&1)
    if printf '%s\n' "$out" | grep -q 'Connection Completed'; then
        printf '%s\n' "$out" | grep -E \
            'Session Status|Server Name|Hub Name|VPN Client IP|VPN Client Port|Virtual MAC|Established Session|Number of (TCP|UDP) Connections|Total Bytes' \
            | sed 's/^/  /'
    else
        echo "  state: NOT CONNECTED"
        printf '%s\n' "$out" | grep -E '^Error|^Item|Status' | head -10 | sed 's/^/  /'
    fi
else
    echo "  (skipped: no account or no vpncmd)"
fi

sec "Sessions"
if have vpncmd; then
    vpncmd /CLIENT localhost /CMD SessionList 2>/dev/null \
        | sed -n '/Session Name/,/^The command completed/p' \
        | sed 's/^/  /'
fi

sec "Interfaces & routes"
ip -br addr 2>/dev/null | sed 's/^/  /'
echo "  --- routes ---"
ip -4 route 2>/dev/null | sed 's/^/  /'
echo "  --- default-route egress ---"
ip -4 route show default 2>/dev/null | sed 's/^/  /'

sec "DNS"
if [ -f /etc/resolv.conf ]; then
    sed 's/^/  /' /etc/resolv.conf
fi
if [ -f "$PROFILE" ]; then
    h=$(field Hostname)
    printf "  resolve %-30s -> " "$h"
    getent ahostsv4 "$h" 2>/dev/null | awk 'NR==1{print $1; exit}'
fi
if have nslookup; then
    printf "  nslookup example.com (system):  "
    nslookup -timeout=2 example.com 2>/dev/null | awk '/^Address: /{print $2; exit}' | sed 's/^/  /'
fi

sec "Egress IPs (what the world sees through each proxy)"
if have curl; then
    printf "  via HTTP  :8888  -> "
    curl -sS --max-time 5 --proxy http://127.0.0.1:8888 https://ifconfig.co 2>/dev/null || echo "(failed)"
    printf "  via SOCKS :1080  -> "
    curl -sS --max-time 5 --proxy socks5h://127.0.0.1:1080 https://ifconfig.co 2>/dev/null || echo "(failed)"
fi

sec "TCP/UDP sockets"
if have ss; then
    echo "  --- listening ---"
    ss -tulpn 2>/dev/null | sed 's/^/    /'
    echo "  --- by state ---"
    ss -tan 2>/dev/null | awk 'NR>1{c[$1]++} END{for(k in c) print c[k], k}' | sort -rn | sed 's/^/    /'
fi

sec "Speed test (ping + download + upload via SOCKS → speed.cloudflare.com)"
if have curl; then
    PX="--proxy socks5h://127.0.0.1:1080"

    # --- Ping: TCP + TLS handshake time to a real CDN edge ---
    printf "  ping      "
    p=$(curl -sS -o /dev/null --max-time 10 $PX \
        -w '%{time_connect}|%{time_appconnect}' \
        "https://speed.cloudflare.com/__down?bytes=0" 2>/dev/null)
    if [ -n "$p" ]; then
        tc=$(printf '%s' "$p" | cut -d'|' -f1)
        tt=$(printf '%s' "$p" | cut -d'|' -f2)
        awk -v tc="$tc" -v tt="$tt" \
            'BEGIN{printf "TCP %.1fms  TLS %.1fms\n", tc*1000, tt*1000}'
    else
        echo "FAILED"
    fi

    # --- Download: 25 MB through SOCKS, prefer Cloudflare, fall back to OVH ---
    printf "  download  "
    dl_ok=0
    for url in \
        "https://speed.cloudflare.com/__down?bytes=26214400" \
        "http://proof.ovh.net/files/25Mb.dat"; do
        r=$(curl -sS -o /dev/null --max-time 30 $PX \
            -w '%{size_download}|%{time_total}' "$url" 2>/dev/null)
        b=$(printf '%s' "$r" | cut -d'|' -f1)
        s=$(printf '%s' "$r" | cut -d'|' -f2)
        if [ -n "$b" ] && [ "$b" -gt 0 ] 2>/dev/null && [ -n "$s" ]; then
            awk -v b="$b" -v s="$s" \
                'BEGIN{printf "%d bytes in %.2fs = %.2f Mbps\n", b, s, (b*8/1e6)/s}'
            dl_ok=1; break
        fi
    done
    [ "$dl_ok" = 0 ] && echo "FAILED"

    # --- Upload: 4 MB POST to Cloudflare /__up ---
    printf "  upload    "
    tmp=$(mktemp)
    dd if=/dev/urandom of="$tmp" bs=1024 count=4096 2>/dev/null
    r=$(curl -sS -o /dev/null --max-time 30 $PX \
        -w '%{size_upload}|%{time_total}' \
        -X POST --data-binary @"$tmp" \
        "https://speed.cloudflare.com/__up" 2>/dev/null)
    rm -f "$tmp"
    b=$(printf '%s' "$r" | cut -d'|' -f1)
    s=$(printf '%s' "$r" | cut -d'|' -f2)
    if [ -n "$b" ] && [ "$b" -gt 0 ] 2>/dev/null && [ -n "$s" ]; then
        awk -v b="$b" -v s="$s" \
            'BEGIN{printf "%d bytes in %.2fs = %.2f Mbps\n", b, s, (b*8/1e6)/s}'
    else
        echo "FAILED (cloudflare /__up unreachable through tunnel)"
    fi
fi

sec "Proxy liveness"
for hp in "8888 HTTP" "1080 SOCKS"; do
    port=${hp% *}; name=${hp#* }
    if have nc; then
        if nc -z -w2 127.0.0.1 "$port" 2>/dev/null; then
            printf "  %-5s :%-5s UP\n" "$name" "$port"
        else
            printf "  %-5s :%-5s DOWN\n" "$name" "$port"
        fi
    fi
done

hr
echo "Re-run: $0  |  loop:  while sleep 5; do $0; done"