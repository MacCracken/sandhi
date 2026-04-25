# 2026-04-24 — `SSL_connect` deadlocks in libssl's pthread-lock path

**Status**: ✅ **RESOLVED** at cyrius v5.6.39 (sandhi pin now `5.6.41`; bumped 5.6.38 → 5.6.40 → 5.6.41 across the same day for the ALPN-hook ship and then the 7-arg-frame fix).
Stdlib-only `programs/tls-raw-probe.cyr` now completes a full HTTPS round-trip to `1.1.1.1:443` (handshake → request → 200 OK → first 60 bytes of response). Live `sandhi_http_get("https://example.com/")` returns 200 / 528 bytes since 5.6.41 cleared the last gating issue.
**Reporter**: sandhi M2 HTTPS re-verification
**Toolchain pin**: `cyrius = "5.6.41"` (sandhi `cyrius.cyml`) — fix appeared between 5.6.30 and 5.6.39.
**Host**: Arch Linux x86_64, kernel 6.18.22-1-lts, glibc 2.43+r5, openssl 3.x at `/usr/lib/libssl.so.3`
**Predecessor**: [`archive/2026-04-24-fdlopen-getaddrinfo-blocked.md`](archive/2026-04-24-fdlopen-getaddrinfo-blocked.md) — closed v5.6.29-1 with both sides fixing their respective bugs; **this is the next-layer blocker that closure revealed**, not a regression of that work.

## Symptom

`tls_connect(sock, host)` from stdlib `lib/tls.cyr` hangs forever inside `SSL_connect`. strace shows the process blocked on `futex(FUTEX_WAIT_PRIVATE, 2, NULL)` with no subsequent syscalls — not in a CPU-spin loop, not in a read/write, not in a poll. Classic pthread-mutex-wait-for-a-wakeup-that-never-comes shape.

## Minimum repro

`sandhi/programs/tls-raw-probe.cyr` — stdlib-only, no sandhi code, IP-literal target, no DNS:

```cyr
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/syscalls.cyr"
include "lib/mmap.cyr"
include "lib/fnptr.cyr"
include "lib/dynlib.cyr"
include "lib/tagged.cyr"
include "lib/net.cyr"
include "lib/tls.cyr"

fn main() {
    alloc_init();
    if (tls_available() == 0) { return 1; }         # prints: 1
    var fd = payload(tcp_socket());
    var ip = 1 | (1 << 8) | (1 << 16) | (1 << 24);  # 1.1.1.1
    sock_connect(fd, ip, 443);                       # returns 0
    var tls = tls_connect(fd, "one.one.one.one");    # <-- hangs here forever
    # unreachable...
}

var exit_code = main();
syscall(60, exit_code);
```

### strace of the hang

```
write(1, "[3] tls_connect ...\n", 20)     = 20
fsync(1)                                   = -1 EINVAL (Invalid argument)
futex(0x502c118, FUTEX_WAIT_PRIVATE, 2, NULL    # ← stuck here until SIGKILL
```

No network activity happens after the plain-TCP connect; the process never gets to any TLS handshake bytes on the wire. The deadlock is host-side, before openssl does any I/O.

### Control: same host is fine under normal processes

```
$ echo | openssl s_client -connect 1.1.1.1:443 -servername one.one.one.one
CONNECTED(00000003)
...
Verify return code: 0 (ok)
```

So: openssl CLI ✓, raw TCP from cyrius ✓, `tls_available()` ✓, `SSL_connect` from cyrius ✗.

## What we know

- `tls_available()` returns 1 — `_tls_init`'s bootstrap-then-dynlib-open-then-resolve-symbols path works post-v5.6.29.
- `sock_connect(fd, 0x01010101, 443)` succeeds cleanly — no network-layer issue.
- The hang is *inside* `SSL_connect`, before any bytes go on the wire (no write/read syscalls after the TCP connect).
- The hang is on a futex wait, not a CPU-bound loop — so it's a pthread-primitive waiting for a wakeup that a statically-linked cyrius binary never generates.
- libssl 3 uses internal locks (per `CRYPTO_THREAD_lock_new` / `CRYPTO_atomic_*`). On glibc, these resolve to pthread primitives that expect a pthread-initialised process. Static cyrius binaries bypass `__libc_start_main`, so `__libc_pthread_init` never runs.

## What we DON'T know

- Whether `dynlib_bootstrap_tls()`'s `%fs`/TCB install is sufficient for libssl's pthread usage or whether libssl needs a more complete pthread init.
- Whether this is reproducible on cyrius CI hosts or only on Arch/glibc 2.43.
- Whether a recent glibc/openssl version pulled in a new lock site that older versions didn't hit.
- Whether `fdlopen`-path libc could side-step this (since fdlopen-initialised libc IS pthread-ready via real ld.so entry).

Not proposing a fix path this round — last issue's "proposed fixes" were wrong on every count. Leaving the diagnosis to the cyrius agent who owns the full stack.

## Why sandhi cares

- **M2 HTTPS acceptance** — live `https://example.com/` round-trip doesn't pass until this resolves. Plain HTTP unaffected and works today.
- **M5 TLS-policy enforcement** — the M5 apply.cyr TODO (the real OpenSSL calls for cert pinning / mTLS) depends on `SSL_connect` working. Surface is shipped and unit-tested; enforcement stubbed until this blocker clears.
- All 291 sandhi tests stay green (no runtime TLS in the test suite). Downstream consumers that run against plain-HTTP endpoints (localhost geckodriver for yantra, localhost daimon, local MCP servers) are unaffected.

## Requested action

No urgency from sandhi — M2 HTTPS + M5 enforcement ship as "pending live verification" indefinitely if needed. Filing for visibility so the cyrius agent has a clean repro + strace capture when bandwidth allows.

One specific thing that would help on the cyrius side: **add a live-handshake test** to `tests/tcyr/tls.tcyr` (or a new `tls-live.tcyr` gated on a build flag so CI without network can skip it) — something like "open a TCP socket to one.one.one.one:443, call tls_connect, call tls_write a minimal GET, call tls_read". The existing test only covers init + symbol resolution and cannot catch this class of bug.

## Cross-links

- sandhi roadmap: `docs/development/roadmap.md` M2 (HTTPS) + M5 (TLS policy enforcement)
- sandhi issue owner: @MacCracken
- cyrius toolchain pin: `cyrius.cyml [package].cyrius = "5.6.30"`
- predecessor issue: `docs/issues/archive/2026-04-24-fdlopen-getaddrinfo-blocked.md`

## Log

- **2026-04-24** — Filed immediately after predecessor closed at v5.6.29-1. Both sides of that issue had real fixes; this is the next layer surfaced by getting past the previous one. No fix proposed — sandhi's track record on proposing cyrius-layer fixes is 0-for-1 (the previous issue's A/B fix proposals solved a non-existent collision). Leaving the root-cause analysis to the cyrius agent.
- **2026-04-24 (later)** — Re-tested against cyrius 5.6.30. Deadlock pattern identical (`futex(FUTEX_WAIT_PRIVATE, 2, NULL)` after tls_connect entry). 5.6.30 stdlib changes were doc-only in `fdlopen.cyr` (stale "KNOWN-INCOMPLETE v5.5.29" comment replaced with correct "complete since v5.5.34" text); no functional changes to tls/dynlib would have been expected to fix this. Confirming the blocker is unchanged and sandhi pin is now `5.6.30`.
- **2026-04-25** — **Resolved.** Bumped sandhi pin to `5.6.38` (CLI ships `5.6.39`). Stdlib-only `programs/tls-raw-probe.cyr` now runs to completion: `tls_available → 1`, `tls_connect → ctx`, `tls_write → 60`, `tls_read → 1369`, first 60 bytes are a real `HTTP/1.1 200 OK\r\nDate: …` response from 1.1.1.1. The futex-wait pattern is gone — handshake bytes hit the wire and a response comes back. No sandhi-side change was required for the unblock; the pthread/locale/TLS bootstrap that was missing is now in place upstream. **Followup blocker found, separate issue**: `tls_connect` segfaults when invoked from a Cyrius function whose 7th arg is on the stack (sandhi's own `sandhi_conn_open_fully_timed` has 7 params). See `2026-04-25-cyrius-7arg-frame-tls-connect-segfault.md` — sandhi-side workaround tracked there. Live HTTPS through `sandhi_http_get` is gated on that issue, not this one.
