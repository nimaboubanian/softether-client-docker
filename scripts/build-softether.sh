#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
archive="$root/softether-vpnclient-v4.44-9807-rtm-2025.04.16-linux-x64-64bit.tar.gz"
url="https://www.softether-download.com/files/softether/v4.44-9807-rtm-2025.04.16-tree/Linux/SoftEther_VPN_Client/64bit_-_Intel_x64_or_AMD64/softether-vpnclient-v4.44-9807-rtm-2025.04.16-linux-x64-64bit.tar.gz"
output="$root/build/softether"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [ ! -f "$archive" ]; then
    echo "Downloading SoftEther archive" >&2
    curl -fsSL -o "$archive" "$url"
    echo "ec18be1da49dfe6f4e05dfded46206de20a353055de0338a921eaf9a8a7c6fc6  $archive" | sha256sum -c -
fi

if [ "$(uname -m)" != x86_64 ]; then
    echo "SoftEther archive supports Linux x86_64 only" >&2
    exit 1
fi

rm -rf "$output"
tar -xzf "$archive" -C "$tmp"
make -C "$tmp/vpnclient" main
strip "$tmp/vpnclient/vpnclient" "$tmp/vpnclient/vpncmd"
mkdir -p "$output"
cp "$tmp/vpnclient/vpnclient" "$tmp/vpnclient/vpncmd" "$tmp/vpnclient/hamcore.se2" "$output/"
cp "$tmp/vpnclient/ReadMeFirst_License.txt" "$output/"
cp "$tmp/vpnclient/ReadMeFirst_Important_Notices_en.txt" "$output/"
cp "$tmp/vpnclient/ReadMeFirst_Important_Notices_ja.txt" "$output/"
cp "$tmp/vpnclient/ReadMeFirst_Important_Notices_cn.txt" "$output/"
