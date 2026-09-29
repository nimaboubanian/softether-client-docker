# SoftEther VPN Client — Docker

Containerize the pre-compiled SoftEther VPN client v4.44 (Linux x86_64).

## Layout
- `softether-vpnclient-v4.44-9807-rtm-2025.04.16-linux-x64-64bit.tar.gz` — only source artifact.
- Extracts to `vpnclient/`: pre-built static libs (`code/*.a`, `lib/*.a`), `Makefile`, license docs.
- `make` only `ranlib`s the libs and links them into `vpnclient` / `vpncmd`. No actual compilation.

## Build
- Needs `gcc`, `make`, `binutils` (`ranlib`) — linking still happens.
- `linux/amd64` only; no ARM / 32-bit variant in this directory.
- Use `make main`, not `make` / `.install.sh`, to skip the license-echo wall of text.

## Runtime (inside extracted `vpnclient/`)
- `./vpnclient start` / `./vpnclient stop` — daemon control.
- `./vpncmd` — management CLI; scriptable via stdin.
- `lang.config` — display language (ja / en / zh-cn).
- `hamcore.se2` — required runtime data file alongside the binary.

## Container gotchas
- **`vpnclient start` daemonizes and returns.** A naive `CMD ["./vpnclient","start"]` makes the container exit immediately. Keep it alive (e.g. `tail -f /dev/null`, `sleep infinity`, or `vpnclient exec` once configured).
- **Multi-stage is worth it.** Build stage needs gcc/make; runtime stage only needs the linked `vpnclient`, `vpncmd`, `lang.config`, `hamcore.se2`. Distroless / alpine works for runtime.
- **Preserve license files** (`ReadMeFirst_License.txt`, `ReadMeFirst_Important_Notices_*.txt`) in the image for redistribution.

## Verification
- No test suite. Smoke test: `./vpnclient start && sleep 1 && ./vpnclient stop` should exit clean.
