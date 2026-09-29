# SoftEther VPN Client — Docker

Containerize the pre-compiled SoftEther VPN client v4.44 (Linux x86_64).

## Layout
- `softether-vpnclient-v4.44-9807-rtm-2025.04.16-linux-x64-64bit.tar.gz` — source artifact.
- Extracts to `vpnclient/`: pre-built static libs (`code/*.a`, `lib/*.a`), `Makefile`, license docs.
- `build-softether.sh` runs `make main` on the host and stages runtime files under ignored `build/softether/`.

## Build
- Host build needs `gcc`, `make`, `binutils` (`ranlib`/`strip`).
- `linux/amd64` only; no ARM / 32-bit variant in this directory.
- Use `make main`, not `make` / `.install.sh`, to skip the license-echo wall of text.
- Host-built binaries require glibc; the image uses Ubuntu 26.04 rather than Alpine/musl.

## Runtime (inside extracted `vpnclient/`)
- `./vpnclient start` / `./vpnclient stop` — daemon control.
- `./vpncmd` — management CLI; scriptable via stdin.
- `lang.config` — display language (ja / en / zh-cn).
- `hamcore.se2` — required runtime data file alongside the binary.

## Container gotchas
- **`vpnclient start` daemonizes and returns.** A naive `CMD ["./vpnclient","start"]` makes the container exit immediately. Keep it alive (e.g. `tail -f /dev/null`, `sleep infinity`, or `vpnclient exec` once configured).
- The runtime image copies the host-built `vpnclient` and `vpncmd`, `hamcore.se2`, and license docs.
- **Preserve license files** (`ReadMeFirst_License.txt`, `ReadMeFirst_Important_Notices_*.txt`) in the image for redistribution.

## Verification
- Host artifact check: `sh ./test-host-build.sh`.
- Host runtime smoke test: from `build/softether/`, `./vpnclient start && sleep 1 && ./vpnclient stop` should exit clean.
