# 2026-06-09 — `sandhi_http_get`/`_post` SIGSEGV on repeated HTTPS requests to the same host

> **RESOLVED (2026-06-09, sandhi 1.4.5 / cyrius 6.1.19).** NOT a sandhi
> conn-lifecycle bug. The crash was **cyrius `lib/alloc.cyr`'s `brk(2)` bump heap
> colliding with glibc malloc's brk arena**, pulled in by `lib/fdlopen.cyr`
> loading libssl. Two brk managers share one program break; once cyrius's heap
> first grows past its initial 1 MB (sandhi leaks ~256 KB/request into
> `default_alloc()`, so request #4) they clobber each other and the process
> SIGSEGVs *inside libssl*. Reproduces with **zero sandhi code**; switching the
> per-iter leak from `brk` `alloc()` to `mmap` made it vanish (the smoking gun).
>
> **Fixed in cyrius 6.1.19** (pinned at sandhi 1.4.5), both upstream issues:
> the alloc heap moved off `brk` onto an anonymous-`mmap` chunk-bump allocator
> ([`brk-bump-heap-vs-fdlopen-libssl-malloc.md`](https://github.com/MacCracken/cyrius/blob/main/docs/development/issues/2026-06-09-brk-bump-heap-vs-fdlopen-libssl-malloc.md)),
> and native cert-chain ordering fixed so native handshakes public hosts
> ([`native-tls-handshake-gap-public-servers.md`](https://github.com/MacCracken/cyrius/blob/main/docs/development/issues/2026-06-09-native-tls-handshake-gap-public-servers.md)).
> sandhi also default-switched to the **native** backend (no libssl/glibc loaded).
> **Verified at 6.1.19:** native AND libssl `sandhi_http_get` ×6 to example.com
> both → 6/6 status 200, no crash. See
> [architecture/004](../architecture/004-native-tls-default.md).

**Status:** RESOLVED — sandhi 1.4.5 (native default) + cyrius 6.1.19 (both upstream root fixes). Verified crash-free on both backends.
**Severity:** **P1 / Critical** — crashes the process; blocks any consumer making
more than a few sequential HTTPS requests. No workaround from the consumer side.
**Reporter:** hoosh (AI inference gateway, v2.1.4 — wiring remote provider
transport, the v2.2.0 criticals)
**Sandhi version at time of report:** **1.4.4** (bundled at cyrius **6.1.18** as
`lib/sandhi.cyr`)
**Affects:** every consumer of the high-level HTTPS client
(`sandhi_http_get` / `_post` / `_put` / … and the `_auto` / `_opts` variants)
that makes repeated requests in one process.
**Blast radius:** process-fatal. hoosh forwards LLM requests to remote providers
(OpenAI/Anthropic/…) over `sandhi_http_post`; the gateway crashes after a handful
of requests, taking down all in-flight connections.

## Summary

A process that calls the sandhi high-level HTTPS client repeatedly against the
same host **SIGSEGVs after ~3 successful requests** — deterministically on the
**4th call** in an isolated standalone, and intermittently (1st–2nd call) inside
a larger consumer where other allocations shift the heap. The first few requests
return correct responses; then the process dies.

## Minimal reproducer (no consumer code)

Built in any cyrius project whose `cyrius.cyml` `[deps]` auto-includes the stdlib
(`sandhi`/`tls`/`net`/`fdlopen`/`mmap`/`dynlib`), at cyrius 6.1.18 / sandhi 1.4.4:

```cyr
fn _say(m, n) { sys_write(1, m, n); return 0; }
fn main() {
    var i = 0;
    while (i < 6) {
        _say("start\n", 6);
        var r = sandhi_http_get("https://example.com", 0);
        if (r != 0) {
            if (sandhi_http_err_kind(r) == 0) { _say("ok\n", 3); }
            else { _say("err\n", 4); }
        }
        i = i + 1;
    }
    _say("DONE\n", 5);
    return 0;
}
var r = main();
sys_exit(r);
```

Observed output (identical across 3 runs):

```
start
ok
start
ok
start
ok
start            <-- 4th call
Segmentation fault   (exit 139 / SIGSEGV)
```

`DONE` is never reached. The crash is in the 4th `sandhi_http_get`, before it
returns.

## Diagnosis so far

- **Consumer-independent.** The standalone above contains zero hoosh code — only
  the stdlib client — and crashes the same way. (In hoosh the crash lands earlier
  and intermittently, 1st–2nd request, because the gateway's other allocations
  change the heap layout — the signature of heap/stack corruption, not a logic
  bug in the caller.)
- **Count-based, not host-specific.** Deterministically the 4th sequential call
  to the same host (`example.com`); session cache is **off by default**
  (`_sandhi_session_cache_enabled = 0`), so this is not the resumption path.
- **Fault is in the TLS transport.** `gdb` puts `#0` inside a dlopen'd library
  region (`0x00007ffff7325397`) with a **corrupt call stack** above it
  (`#1 0x0000000000000034`, `#3 0x0`) — i.e. a smashed return address / stack,
  consistent with a buffer overflow or use-after-free in the per-connection TLS
  setup/teardown that only manifests once a few connections have been
  opened+closed.
- ~~Likely area: per-request connection open/close in `_sandhi_http_exchange_a` /
  `_sandhi_conn_finalize_a` / `sandhi_conn_close`~~ — **this speculation was
  wrong** (see the confirmed root cause banner at the top). The conn lifecycle is
  fine; reproducing it required a `brk`-heap leak crossing 1 MB while libssl is
  loaded, with NO sandhi code. Note also: despite the 1.4.2 CHANGELOG wording,
  sandhi was still running on the **libssl** backend by default at report time
  (`tls_set_backend` is never called; the stdlib default is libssl unless built
  with `-D CYRIUS_TLS_NATIVE`) — which 1.4.5 fixes.

## Impact on hoosh

hoosh v2.2.0 remote provider transport (`https://` routes → `sandhi_http_post`)
is **implemented and verified working for individual requests** — a live call to
Anthropic returns correctly (`content[].text` + `usage` tokens extracted). But
the gateway cannot be used in production until this is fixed: a few requests in
and the server process dies. hoosh has marked its v2.2.0 remote path **blocked on
this issue**.

## Fix direction (confirmed)

1. **Upstream (cyrius), root fix** — make `lib/alloc.cyr`'s Linux heap
   **mmap-backed** instead of `brk(2)`-backed, so it never contends with glibc
   malloc's brk arena. Independent of TLS; future-proofs any `fdlopen` of a
   glibc library. Filed:
   `cyrius/docs/development/issues/2026-06-09-brk-bump-heap-vs-fdlopen-libssl-malloc.md`.
2. **Upstream (cyrius), unblock libssl retirement** — close the native-TLS
   handshake gap so native reaches the standard public host set. Filed:
   `cyrius/docs/development/issues/2026-06-09-native-tls-handshake-gap-public-servers.md`.
3. **sandhi 1.4.5 (shipped)** — default to the native backend (no libssl/glibc →
   no brk contention); libssl is an opt-in (`sandhi_tls_use_libssl()`). Also
   stopped an unconditional `tls_get_session` session-ref leak on the libssl path
   (`conn.cyr`). Regression gate added: `programs/_https_native_loop_gate.cyr`
   (N≥4 sequential native `sandhi_http_get`, must not crash; 6/6 verified).

Both upstream fixes landed in cyrius **6.1.19**; sandhi 1.4.5 re-pinned to it
and verified native + libssl both reach example.com crash-free (6/6).
