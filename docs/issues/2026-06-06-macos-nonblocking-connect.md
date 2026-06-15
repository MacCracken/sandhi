# macOS non-blocking connect (+ SO_RCVTIMEO) uses Linux-only constants → spurious `SANDHI_ERR_CONNECT` on Darwin

**Status**: **RESOLVED at sandhi 1.6.1 / cyrius 6.2.9** for the reported IPv4
connect path. The non-blocking-connect and per-op-timeout helpers in
`src/http/conn.cyr` were re-pointed at the stdlib Darwin-correct primitives
(`net_connect_nb` / `sock_set_recv_timeout` / `sock_set_send_timeout`) per the
"compose, don't reimplement" fix below — retiring sandhi's Linux-hardcoded
duplicate. A **follow-on remains** for two raw-syscall sites that are still
Linux-only (the internal IPv6 sockaddr nb-connect + the server accept-loop listen
socket); tracked as a numbered roadmap entry ("IPv6 nb-connect + server listen
socket not Darwin-ported"). The agnos analogue of this was closed at sandhi 1.5.1
(Batch C1, `#ifdef CYRIUS_TARGET_AGNOS` guards). The TLS gaps closed at 1.6.0 are
unrelated — this is the plain transport (non-TLS connect) path.
**Filed**: 2026-06-06 by yantra (downstream consumer); tracked sandhi-side
2026-06-15 (was only filed against the cyrius repo at
`cyrius/docs/development/issues/2026-06-06-sandhi-nonblocking-connect-not-darwin-ported.md`).
**Affects**: `src/http/conn.cyr` (folds into `lib/sandhi.cyr`) on **aarch64
macOS** (Mach-O). Linux + AGNOS unaffected.
**Severity**: any `sandhi_http_*` with `connect_ms > 0` cannot connect on macOS,
even to a listening localhost server.

## Root cause

The non-blocking-connect path (`_sandhi_conn_connect_*_nb_a`) + the per-op
timeout (`_sandhi_conn_set_timeout_ms_a`) hardcode **Linux** socket constants:

```
var _SANDHI_O_NONBLOCK  = 2048;   # 0x800 Linux; Darwin O_NONBLOCK = 0x0004
var _SANDHI_EINPROGRESS = 115;    #        Linux; Darwin EINPROGRESS = 36
var _SANDHI_SO_RCVTIMEO = 20;     #        Linux; Darwin SO_RCVTIMEO = 0x1006
var _SANDHI_SO_SNDTIMEO = 21;     #        Linux; Darwin SO_SNDTIMEO = 0x1005
var _SANDHI_SO_ERROR    = 4;      #        Linux; Darwin SO_ERROR    = 0x1007
# SOL_SOCKET = 1 (Linux) vs 0xFFFF (Darwin); F_GETFL/F_SETFL=3/4 same
```

On Darwin: `fcntl(fd, F_SETFL, 0x800)` sets the wrong flag (the socket may not be
non-blocking), and the connect-in-progress `errno` is `36` not `115`, so sandhi
misreads it as a hard failure → `_SANDHI_CONN_NB_ERR` → `SANDHI_ERR_CONNECT`.
`SO_RCVTIMEO`/`SO_SNDTIMEO` are a latent second bug (same family + the Darwin
`struct timeval` `tv_usec` is 32-bit). Symptom: yantra's iOS Appium
`POST /session` (`connect_ms=15000`) fails with `errkind=2/CONNECT status=0` on
the macOS runner while `curl` to the identical URL returns 200; the same path
works 4/4 on Linux (Android e2e).

## Fix (sandhi-side, mirrors the 1.5.1 agnos C1 pattern)

Per-target the Darwin constants under `#ifdef CYRIUS_TARGET_MACOS` (the stdlib
`lib/net.cyr` already carries the correct Darwin `SockOpt` / `_NET_O_NONBLOCK` /
`_NET_EINPROGRESS` values — compose those rather than re-hardcoding where
possible), then re-fold into cyrius `lib/sandhi.cyr`. Composing the stdlib
`net_connect_nb` (which is already Darwin-correct + agnos-guarded) would retire
sandhi's duplicate of the fcntl/poll/getsockopt dance entirely — the cleanest
option (ADR 0001 "compose, don't reimplement").

## Acceptance

- A `sandhi_http_*` call with `connect_ms > 0` connects to a listening localhost
  server on aarch64 macOS (the yantra Appium `POST /session` repro returns 200).
- Linux + AGNOS unchanged; the four `.tcyr` suites stay green.

## Related

- `cyrius/docs/development/issues/2026-06-06-sandhi-nonblocking-connect-not-darwin-ported.md` — the original cyrius-side filing (full symptom + line refs).
- sandhi 1.5.1 Batch C1 — the agnos analogue (same Linux-constant gap, guarded).
- `lib/net.cyr` `SockOpt` (macOS branch) — the Darwin constant values to compose.

## Log

- **2026-06-06** — filed by yantra against the cyrius repo.
- **2026-06-15** — tracked sandhi-side (the cyrius `2026-05-22` native-TLS issue
  closed at cyrius 6.2.8 + sandhi 1.6.0; this plain-transport macOS gap is
  separate and remained untracked in this repo until now).
- **2026-06-15** — **RESOLVED (IPv4) at sandhi 1.6.1 / cyrius 6.2.9.**
  `_sandhi_conn_connect_nb_a` now delegates to stdlib `net_connect_nb` and
  `_sandhi_conn_set_timeout_ms_a` to stdlib `sock_set_recv_timeout` /
  `sock_set_send_timeout` — both already Darwin-branched + agnos-guarded. The
  Linux-hardcoded fcntl/poll/getsockopt dance and the hand-built `struct timeval`
  are gone from the v4 path. Four `.tcyr` suites green (1002 assertions; the one
  alloc-suite assertion that pinned the old arena-allocates-timeval behaviour was
  repurposed to assert the helper is now arena-independent); lint 0/0; `fmt
  --check` clean; macОS+aarch64+agnos cross-builds OK; `dist/sandhi.cyr`
  regenerated. Follow-on (IPv6 sockaddr nb-connect + server listen socket, both
  still Linux-only) filed as a roadmap entry.
