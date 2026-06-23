# 2026-06-15 — cyrius `lib/net.cyr` IPv6 surface not Darwin-ported (blocks sandhi's macOS v6 nb-connect + server listen-socket port)

**Status**: ✅ **RESOLVED — cyrius 6.2.10 (primitives) + sandhi 1.6.2 (adoption).**
6.2.10 shipped exactly the surface requested below — per-target `SockDomain.AF_INET6`
(Linux 10 / Darwin 30), a Darwin-branched `sockaddr_in6(addr16, port)` builder, the
generic `net_connect_sa_nb(fd, sa, salen, timeout_ms)` + convenience
`net_connect_nb6(fd, addr16, port, timeout_ms)`, and `sock_set_nonblocking(fd)` /
`sock_clear_nonblocking(fd, saved)` (the cyrius source cites this filing). sandhi
1.6.2 adopted them: the IPv6 open paths in `src/http/conn.cyr` now create the
socket with the per-target `AF_INET6` and compose `sockaddr_in6` +
`net_connect_sa_nb`; the server accept-loop listen socket in `src/server/mod.cyr`
composes `sock_set_nonblocking`. sandhi's hand-rolled `_sandhi_conn_sockaddr_in6*`
/ `_sandhi_conn_connect_sa_nb*` shims and all eight Linux-only raw socket constants
were deleted. Built + tested green on the 6.2.10 pin; macОS+aarch64+agnos
cross-builds OK. Archived.

_(History) Filed by sandhi while closing the IPv4 half of
[`2026-06-06-macos-nonblocking-connect.md`](2026-06-06-macos-nonblocking-connect.md)
at sandhi 1.6.1 / cyrius 6.2.9. The IPv4 connect path was fixed first (sandhi
composes `net_connect_nb` / `sock_set_*_timeout`); the **IPv6** path couldn't be
fixed sandhi-side because stdlib exposed no Darwin-correct v6 surface to compose.
Per ADR 0001 (compose, don't reimplement) and the No-FFI / "primitive depth is a
stdlib patch" rule, that was a cyrius-side enhancement, not a sandhi slot — hence
this upstream filing.
**Affects**: stdlib `lib/net.cyr` on **aarch64 macOS** (Mach-O). Linux + AGNOS
unaffected. Downstream: sandhi `src/http/conn.cyr` (`_sandhi_conn_connect_sa_nb_a`,
`_sandhi_conn_sockaddr_in6_a`) + `src/server/mod.cyr` (the non-blocking listen
socket).
**Severity**: low — masked today (an IPv6 connect fails on macOS → the sandhi HTTP
client falls back to IPv4). The sharper edge is the server listen socket, which
hardcodes a Linux `O_NONBLOCK` value because there's no stdlib helper to compose.

## Root cause

`lib/net.cyr` was Darwin-ported for the **IPv4** + sockopt surface (v6.0.59, per
the cyrius-repo doc `cyrius/.../2026-06-04-macos-net-socket-syscalls-unported.md`,
cited at `lib/net.cyr:5`; the `SockOpt` / `_NET_O_NONBLOCK` / `_NET_EINPROGRESS` constants and
`net_connect_nb` are `#ifdef CYRIUS_TARGET_MACOS`-branched and "verified on arm64
macOS"). The **IPv6** surface was not carried along:

1. **`SockDomain.AF_INET6 = 10` is unbranched** (`lib/net.cyr:25`). That's the
   Linux value; Darwin's `AF_INET6` is **30** (xnu `sys/socket.h`). Any v6 socket
   built with this constant is wrong on Mach-O.
2. **No `sockaddr_in6` builder.** The only sockaddr helper is `sockaddr_in`
   (IPv4, 16 bytes). The Darwin `sockaddr_in6` needs the BSD `sin6_len` byte at
   offset 0 + `sin6_family=30` at offset 1 (vs Linux's `u16 sin6_family=10` at
   offset 0) — the same length-byte split `sockaddr_in` already handles for v4.
3. **No v6 non-blocking connect.** `net_connect_nb` (the primitive sandhi 1.6.1
   now composes for v4) builds a `sockaddr_in` inline and is IPv4-only. There's no
   `net_connect_nb6` / generic `net_connect_sa_nb` for an already-built sockaddr,
   so sandhi hand-rolls `_sandhi_conn_connect_sa_nb_a` with Linux-only
   `O_NONBLOCK=0x800` / `EINPROGRESS=115` / `SO_ERROR=4` literals.
4. **No standalone non-blocking helper.** `net_connect_nb` sets/clears
   `O_NONBLOCK` internally, but there's no exported `sock_set_nonblocking(fd)` /
   `sock_clear_nonblocking(fd, saved)`. So sandhi's server accept loop hardcodes
   `syscall(F_SETFL, fd, lflags | 0x800)` — Linux O_NONBLOCK — with nothing to
   compose.

On Mach-O the backend SYSXLAT translates the `SYS_*` syscall **numbers**
(`fcntl`/`poll`/`getsockopt`/`connect`) but **not** the flag/option **values** or
the `AF_INET6` constant — those are passed verbatim — so (1)–(3) all misbehave.

## Proposed fix (cyrius `lib/net.cyr`)

Mirror the existing v4 Darwin-port pattern:

- **Per-target `SockDomain.AF_INET6`** (Linux 10 / Darwin 30) — same `#ifdef
  CYRIUS_TARGET_MACOS` split the SockOpt enum already uses.
- **`sockaddr_in6(addr16, port)` builder** — Darwin-branched `sin6_len` + family,
  28-byte struct (parallels `sockaddr_in`).
- **A v6 non-blocking connect** — either `net_connect_nb6(fd, addr16, port,
  timeout_ms)` or a generic `net_connect_sa_nb(fd, sa, salen, timeout_ms)` that
  takes an already-built sockaddr, reusing the v4 fcntl/poll/getsockopt body with
  the platform-branched flag/opt values. Returns the same `_NET_CONN_NB_*`
  sentinels.
- **(enables the server fix) `sock_set_nonblocking(fd)` / `sock_clear_nonblocking(fd, saved)`** —
  so the sandhi server listen socket composes instead of hardcoding `O_NONBLOCK`.

With these, sandhi retires `_sandhi_conn_connect_sa_nb_a` + `_sandhi_conn_sockaddr_in6_a`
+ the server's raw `O_NONBLOCK` fcntl the same way 1.6.1 retired the v4 dance.

## Acceptance

- A v6 `sandhi_http_*` connect (and the sandhi server accept loop) works on
  aarch64 macOS by composing stdlib — no Linux constants left in sandhi's v6 /
  listen paths.
- Linux + AGNOS unchanged; sandhi's four `.tcyr` suites stay green.

## Related

- [`2026-06-06-macos-nonblocking-connect.md`](2026-06-06-macos-nonblocking-connect.md)
  — the sandhi-side issue whose IPv4 + per-op-timeout halves landed at 1.6.1; this
  is its IPv6 / listen-socket follow-on.
- cyrius-repo `2026-06-04-macos-net-socket-syscalls-unported.md` (cited at
  `lib/net.cyr:5`) — the v6.0.59 IPv4 Darwin port of `lib/net.cyr` this extends to v6.
- sandhi roadmap "IPv6 nb-connect + server listen socket not Darwin-ported" — the
  downstream tracking entry.

## Log

- **2026-06-15** — Filed by sandhi at 1.6.1 / cyrius 6.2.9 while closing the IPv4
  half of the macOS nb-connect defect. The v6 + listen-socket halves are blocked on
  this stdlib surface; cross-cutting (a `lib/net.cyr` v6-on-Darwin pass), so filed
  upstream rather than worked around sandhi-side (No-FFI / compose-don't-reimplement).
- **2026-06-15** — ✅ **RESOLVED.** cyrius 6.2.10 shipped all five requested
  primitives (per-target `AF_INET6`, `sockaddr_in6`, `net_connect_sa_nb`,
  `net_connect_nb6`, `sock_set_nonblocking`/`_clear`). sandhi 1.6.2 adopted them
  (`src/http/conn.cyr` v6 paths + `src/server/mod.cyr` listen socket), deleting its
  hand-rolled v6 shims + 8 Linux-only socket constants. 1002 assertions green on
  the 6.2.10 pin; lint 0/0; `fmt --check` clean; aarch64+agnos cross-builds OK;
  `dist/sandhi.cyr` regenerated at v1.6.2. Archived.
