# 2026-04-25 — `tls_connect` segfaults when invoked from a 7-arg Cyrius frame

**Status**: ✅ **RESOLVED** at cyrius v5.6.41. Sandhi pin bumped 5.6.40 → 5.6.41. Stdlib-only repro `programs/_min_repro_7arg_tls.cyr` now succeeds for both 6-arg and 7-arg variants. **Live HTTPS through `sandhi_http_get("https://example.com/")` returns 200 OK / 528 bytes** — the M2 acceptance gate that was open since project start is now closed end-to-end (DNS via fdlopen → TLS handshake → HTTP/1.1 → real HTML body).
**Reporter**: sandhi HTTPS retest after `cyrius.cyml [package].cyrius` bump 5.6.30 → 5.6.41.
**Toolchain pin**: `cyrius = "5.6.41"` in sandhi.
**Host**: Arch Linux x86_64, kernel 6.18.22-1-lts, glibc 2.43+r5, openssl 3.x at `/usr/lib/libssl.so.3`.

## Symptom

Calling `tls_connect(fd, sni)` from a Cyrius function whose **own** parameter list has 7 or more arguments (i.e. the 7th param sits on the stack per the SysV x86_64 ABI) causes a SIGSEGV inside the call. The same `tls_connect(fd, sni)` invocation from a function with ≤6 params returns a valid TLS context.

The crash happens AT `tls_connect`'s first instruction-or-two — `pre tls_connect` prints, the call enters, and the program dies before `post tls_connect`. No diagnostic from libssl. Just `dumped core` / SIGSEGV.

`sandhi_conn_open_fully_timed(addr, port, use_tls, sni_host, connect_ms, read_ms, write_ms)` has 7 params, so every HTTPS request through sandhi crashes here.

## Minimum repro — stdlib only, no sandhi

`sandhi/programs/_min_repro_7arg_tls.cyr`:

```cyr
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/syscalls.cyr"
include "lib/mmap.cyr"
include "lib/fnptr.cyr"
include "lib/dynlib.cyr"
include "lib/tagged.cyr"
include "lib/net.cyr"
include "lib/tls.cyr"

fn say(m) { syscall(1, 1, m, strlen(m)); return 0; }

fn six(addr, port, use_tls, sni, a, b) {
    var fd_r = tcp_socket();
    var fd = payload(fd_r);
    sock_connect(fd, addr, port);
    if (tls_available() == 0) { sock_close(fd); return 0; }
    say("  [6] pre tls_connect\n");
    var t = tls_connect(fd, sni);
    say("  [6] post tls_connect: "); fmt_int(t); say("\n");
    if (t != 0) { tls_close(t); }
    sock_close(fd);
    return 0;
}

fn seven(addr, port, use_tls, sni, a, b, c) {
    var fd_r = tcp_socket();
    var fd = payload(fd_r);
    sock_connect(fd, addr, port);
    if (tls_available() == 0) { sock_close(fd); return 0; }
    say("  [7] pre tls_connect\n");
    var t = tls_connect(fd, sni);                 # <-- SIGSEGV here
    say("  [7] post tls_connect: "); fmt_int(t); say("\n");
    if (t != 0) { tls_close(t); }
    sock_close(fd);
    return 0;
}

fn main() {
    alloc_init();
    var ip = 1 | (1 << 8) | (1 << 16) | (1 << 24);
    say("=== 6-arg ===\n"); six(ip, 443, 1, "one.one.one.one", 0, 0);
    say("=== 7-arg ===\n"); seven(ip, 443, 1, "one.one.one.one", 0, 0, 0);
    return 0;
}
var exit_code = main();
syscall(60, exit_code);
```

### Output

```
=== 6-arg ===
HELPER-MAIN-RAN
PRE-CB
  [6] pre tls_connect
  [6] post tls_connect: 836606704
=== 7-arg ===
  [7] pre tls_connect
[1]    PID  segmentation fault (core dumped)  ./build/_min_repro_7arg_tls
exit=139
```

The 6-arg call returns a real TLS ctx. The 7-arg call dies at the first instruction of `tls_connect` — same `fd`, same SNI string literal, same prior state.

## Why it's compiler not user code

- The 7th parameter is *unused* in `seven()`. Removing the body's reference to it doesn't change anything; just the presence of the 7th formal parameter is enough.
- The bodies of `six` and `seven` are byte-for-byte identical apart from the formal parameter list.
- `tls_connect` is reached via `lib/fnptr.cyr` indirect call (`_tls_connect_fn` resolved through fdlopen). The dispatcher's prologue must be touching a register/stack slot the caller's frame layout has invalidated.
- `fdlopen` uses setjmp/longjmp inside its own helper-callback dance. The longjmp restore is highly sensitive to the saved frame's stack layout. Any compiler bug at the SysV register/stack-arg boundary would manifest exactly as "indirect-call to extern symbol blows up at first instruction."
- Repro is stdlib-only. No sandhi code in the path.

## Sandhi-side impact

`sandhi_conn_open_fully_timed(addr, port, use_tls, sni_host, connect_ms, read_ms, write_ms)` is the only HTTPS entry point in sandhi. Its 7 params are the union of all timeout knobs callers might want — connect / read / write — plus the four base args. Every HTTPS request through `sandhi_http_get` ends up here.

All 634 sandhi tests stay green — the suite uses synthetic bytes for HTTP/2 and never opens a live TLS socket. Only live HTTPS through `sandhi_http_get` trips the bug.

## Workarounds considered

1. **Wait for upstream fix.** sandhi's surface is frozen at 0.9.2 per ADR 0005, so the public verbs that delegate here (`sandhi_http_get_opts`, `sandhi_http_post_opts`, redirect-following) all transitively touch the 7-arg function. Workarounds need to be invisible to callers.
2. **Pack the timeout knobs into a struct** — `sandhi_conn_open_fully_timed(addr, port, use_tls, sni_host, deadline_struct)` with deadline_struct being a heap-allocated `{ connect_ms, read_ms, write_ms }`. Brings the formal parameter count to 5. Trade-off: an extra alloc per request and a tiny indirection inside the function. **No public-surface impact** — callers still go through `sandhi_http_get` etc. Reversible the moment the compiler fix lands.
3. **Inline the body into each public verb.** Code duplication, hard to reverse. Rejected.

Recommendation: hold the workaround for now — it would land a struct-based parameter style for purely defensive reasons against a compiler regression that should resolve upstream. If the cyrius fix is more than a single point release out, ship the struct workaround behind the existing public surface so consumers see no change. **No sandhi public-surface change either way** — `sandhi_http_get` etc. are unaffected.

## What we DON'T know

- Whether the bug is at exactly 7 args or wider (e.g. crash also at 8, 9). Repro confirmed at 7 only.
- Whether it depends on the called-into function being an indirect/extern call (i.e. `tls_connect` via fnptr) or also affects calls into pure-Cyrius functions from a 7-arg frame. Reproducing only with `tls_connect` makes the SysV-boundary + indirect-call combination the prime suspect.
- Whether the regression is in 5.6.39 itself or somewhere between 5.6.30 and 5.6.39. (sandhi was pinned to 5.6.30 the entire 0.7.x → 0.9.2 run; HTTPS was gated on the libssl-pthread issue so we never exercised this path.)

## Cross-links

- **Predecessor**: `2026-04-24-libssl-pthread-deadlock.md` — resolved upstream at 5.6.39; this issue is the next-layer blocker that resolution surfaced.
- **Sibling open**: `2026-04-24-stdlib-tls-alpn-hook.md` — orthogonal (ALPN hook still missing); both must clear before sandhi can light up live HTTPS + h2 auto-selection.
- sandhi roadmap: `docs/development/roadmap.md` M2 (HTTPS live-verification gate) and the libssl-pthread + ALPN follow-on bullets.
- sandhi pin: `cyrius.cyml [package].cyrius = "5.6.41"`.

## Log

- **2026-04-25** — Bumped sandhi from 5.6.30 to 5.6.38. Raw `tls-raw-probe.cyr` succeeds (libssl-pthread-deadlock fixed upstream). Live `sandhi_http_get("https://1.1.1.1/")` segfaults despite raw probe working. Bisected via inline diagnostics inside `sandhi_conn_open_fully_timed` to the `tls_connect(fd, sni_host)` call. Reproduced in stdlib-only test (`programs/_min_repro_7arg_tls.cyr`): same call site, identical body, only the formal parameter count differs (6 → 7). 6-arg succeeds, 7-arg SIGSEGVs at `tls_connect`'s first instruction. Filed for cyrius-side investigation. No sandhi-side workaround applied yet — holding pending upstream triage.
- **2026-04-25 (later)** — Re-tested at cyrius v5.6.40 (after the ALPN-hook ship). Same repro, same SIGSEGV. v5.6.40 changes are localized to `lib/tls.cyr` (new `tls_connect_with_ctx_hook` + `tls_dlsym`) and don't touch the calling-convention path. Confirming the regression is not 5.6.39-only and persists at 5.6.40. Sandhi pin bumped 5.6.38 → 5.6.40 to consume the ALPN hook (orthogonal upstream fix); HTTPS through sandhi remains gated on this issue.
- **2026-04-25 (resolved)** — cyrius v5.6.41 fixes it. Stdlib-only repro: 7-arg variant now returns a valid TLS ctx (post-handshake `tls_connect: <ptr>` instead of SIGSEGV). Full sandhi path: `sandhi_http_get("https://example.com/")` → status 200, body_len 528, first 120 bytes are real `<!doctype html>...Example Domain...`. `sandhi_http_get("https://1.1.1.1/")` → status 301 (Cloudflare's redirect to `one.one.one.one`). All 634 tests stay green on the new pin. M2 acceptance gate closed.
