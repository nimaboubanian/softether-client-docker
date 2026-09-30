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
- `hamcore.se2` — required runtime data file. The binary locates it via `/proc/self/exe`, so it MUST live in the same directory as the `vpnclient`/`vpncmd` binary (i.e. `/usr/local/bin/`), not somewhere on a different mount.

## Container gotchas
- **`vpnclient start` daemonizes and returns.** A naive `CMD ["./vpnclient","start"]` makes the container exit immediately. Keep it alive (e.g. `tail -f /dev/null`, `sleep infinity`, or `vpnclient exec` once configured).
- The runtime image copies the host-built `vpnclient` and `vpncmd`, `hamcore.se2`, and license docs.
- **Preserve license files** (`ReadMeFirst_License.txt`, `ReadMeFirst_Important_Notices_*.txt`) in the image for redistribution.

## Verification
- Host artifact check: `sh ./test-host-build.sh`.
- Host runtime smoke test: from `build/softether/`, `./vpnclient start && sleep 1 && ./vpnclient stop` should exit clean.

## Debugging lessons (general)
- **"file missing/broken" with the file provably present and bit-identical → the binary is looking in the wrong place.** Many pre-compiled tools resolve resources via `/proc/self/exe` (sibling-of-binary), not cwd. Bisect by moving just the binary, just the data file, or just the cwd — the variable that flips the error is the missing one. Do this bisect before chasing permissions, mounts, inodes, xattrs.
- **Exact error string + GitHub search beats local guessing.** Quoting the error verbatim in a web search often surfaces the root cause and known fix in one hit. Do this on the second failed attempt, not the tenth.
- **"Works on host, fails in container" with identical files → check the binary's path resolution model, not the filesystem.** Same SHA, same perms, same tmpfs/overlay — if it still differs, the binary is doing `/proc/self/exe`-style lookup, not `fopen(argv[0])` and not `fopen("hamcore.se2")`.
- **Tailscale MagicDNS makes the first `getent`/`nslookup` slow (often >30s).** Containers inheriting the host's DNS go through MagicDNS at `100.100.100.100`. Symptom: DNS-resolving commands time out at startup but work seconds later. Fix: drop the Tailscale exit node (or set `tailscale set --exit-node=`) before relying on startup-time DNS in containerized services.
- **Windows-edited config files have CRLF line endings.** `sed 's/...//p'` over a CRLF file returns `value\r` — `$()` strips `\n` but not `\r`. The trailing `\r` silently breaks regex matchers, exact-string comparisons, getent lookups, anything that does byte-level equality. Strip with `| tr -d '\r'` after every extraction, or convert the file with `dos2unix` / `sed -i 's/\r$//'` at copy time.
