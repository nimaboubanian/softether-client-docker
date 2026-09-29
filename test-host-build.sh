#!/bin/sh
set -eu

cd "$(dirname "$0")"
sh ./build-softether.sh

for artifact in vpnclient vpncmd hamcore.se2 ReadMeFirst_License.txt ReadMeFirst_Important_Notices_en.txt; do
    test -s "build/softether/$artifact"
done

ldd build/softether/vpnclient | grep -q 'libc.so.6'
ldd build/softether/vpncmd | grep -q 'libc.so.6'
