#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
archive="$root/softether-vpnclient-v4.44-9807-rtm-2025.04.16-linux-x64-64bit.tar.gz"
output="$root/build/softether"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

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
