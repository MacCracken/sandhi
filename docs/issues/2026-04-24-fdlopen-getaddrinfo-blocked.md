# 2026-04-24 — `fdlopen_getaddrinfo` path blocked in current toolchain

**Status**: Open — awaiting cyrius-lang-agent review
**Reporter**: sandhi M2 design pass
**Toolchain pin**: `cyrius = 5.6.22`
**Impact**: sandhi's M2 HTTP client cannot resolve hostnames via `fdlopen_getaddrinfo`; forced to write a native UDP DNS resolver (`src/net/resolve.cyr`) instead.

## Summary

While planning sandhi's M2 (`sandhi::http::client` real implementation), the natural approach for `https://example.com/...` acceptance would be: use stdlib's `fdlopen_getaddrinfo` (`lib/fdlopen.cyr:788`), compose it into a tiny sandhi resolver, done. That path is currently blocked two layers down. Documenting here so the cyrius agent can pick it up when bandwidth allows — not asking for a fix on any particular timeline.

## What we tried and why it's blocked

### 1. Direct `dynlib_open("libc.so.6")` + `dlsym("getaddrinfo")`

Same pattern `lib/tls.cyr` uses for libssl (`lib/tls.cyr:47-87`). Doesn't work for `getaddrinfo` because NSS module-table walk crashes in a different libc layer than the one `dynlib_bootstrap_*` initialises. Documented in stdlib itself:

> What this does NOT fix: NSS dispatch (`getpwuid` / `getgrouplist` / `pam_authenticate` / `getaddrinfo`). Those crash in a different libc layer (NSS module-table walk).
> — `lib/dynlib.cyr:951-953`

### 2. `fdlopen_init` + `fdlopen_getaddrinfo`

The intended path. `fdlopen.cyr` exists precisely to solve this — spawn a real libc-initialised helper via ld.so entry, get working fn pointers for `getaddrinfo` et al. Blocked because `fdlopen_init` explicitly returns `FDL_ERR_UNINIT` (-8) at the 5.6.22 pin:

```cyr
# lib/fdlopen.cyr:683-706
# As of v5.5.29 this returns FDL_ERR_UNINIT (-8) after the helper
# probe — the full ld.so-entry orchestration lives in
# `fdlopen_init_full` and is opt-in while the investigation continues
fn fdlopen_init(state) {
    ...
    store64(state + 216, 0 - 8);
    return 0 - 8;
}
```

`fdlopen_init_full` (the opt-in orchestration) is explicitly flagged KNOWN-INCOMPLETE with a pinned next-steps list. Three v5.5.29 probe attempts didn't reach helper `main`:

```
# lib/fdlopen.cyr:714-725
# STATUS (v5.5.29): this path is KNOWN-INCOMPLETE. Three probe
# attempts during v5.5.29 confirmed:
#   Attempt 1 (plain prot translation):   SIGSEGV after jmp
#   Attempt 2 (fixed R/W/X extraction):   exit=0, no helper output
#   Attempt 3 (added AT_UID/EUID/GID/
#              EGID/HWCAP/SECURE/FLAGS):  exit=0, no helper output
```

Pinned-in-source next steps (`lib/fdlopen.cyr:726-739`) include verifying `AT_PHDR` points at a walkable mapping, confirming `AT_ENTRY == 0` isn't a "no main" signal, exploring file-backed vs anon+copy PT_LOAD mapping (Cosmopolitan reference noted), and a side-by-side strace against a working invocation.

## Reproduction

Minimal repro (one-file Cyrius program, runs against the 5.6.22 toolchain):

```cyr
include "lib/alloc.cyr"
include "lib/fdlopen.cyr"
include "lib/fmt.cyr"

fn main() {
    alloc_init();
    var state = alloc(FDL_STATE_SIZE);
    var rc = fdlopen_init(state);
    fmt_int(rc);  # expect -8 (FDL_ERR_UNINIT)
    return 0;
}
```

Expected output: `-8`. That's the blocker.

## Why sandhi's M2 cares

sandhi's M2 acceptance line (`docs/development/roadmap.md`) includes:

> `sandhi_http_post("https://example.com/api/...", headers, body, len)` round-trips cleanly

That requires hostname → IPv4 resolution. With fdlopen unavailable, the clean stdlib-composing path is unavailable too. Options that remain:

1. **Native UDP DNS resolver in sandhi** — ~150-200 lines, RFC 1035 baseline (A records, UDP only, `/etc/resolv.conf` parser, Linux-first). Chosen for M2; lives at `src/net/resolve.cyr`.
2. **Accept IP-literal-only clients in v0.3.0** — concedes acceptance; rejected.
3. **Wait for fdlopen** — blocks M2 indefinitely; rejected.

The native-resolver path ships v1-quality for AGNOS consumers today and can retire when `fdlopen_init_full` lands. Noting in sandhi's state.md so the migration happens opportunistically.

## Requested action (cyrius-lang-agent)

No urgency — sandhi is unblocked via the native-resolver workaround. When cyrius's agent picks up the `fdlopen_init_full` orchestration work, the pinned next-steps list in `lib/fdlopen.cyr:726-739` is the starting point. Once `fdlopen_init` returns 0 successfully on Linux x86_64, sandhi can optionally retire `src/net/resolve.cyr` in favour of a ~20-line wrapper around `fdlopen_getaddrinfo`.

Cross-links:
- sandhi roadmap: `docs/development/roadmap.md` M2
- sandhi issue owner: @MacCracken (repo handle `MacCracken/sandhi`)
- cyrius toolchain pin: `cyrius.cyml [package].cyrius = "5.6.22"`

## Log

- **2026-04-24** — Filed during sandhi M2 design pass. No follow-up expected until cyrius agent picks up fdlopen orchestration work.
- **2026-04-24 (later)** — Separate symptom worth logging under the same date-case: during M2's response-parser implementation, a function with 15+ locals (`sandhi_http_response_parse`) saw its `var headers` slot silently zeroed by an unrelated downstream `sandhi_headers_get(...)` call. The call-site ran, the local got clobbered, no warning, no crash — just silent data corruption. Declaring one extra `var hdr_backup = headers;` in the same scope *fixed* it, which implicated stack-slot aliasing rather than anything in the sandhi source. Worked around by extracting the body-framing logic into `_sandhi_resp_frame` so each function stays under whatever the threshold is (empirically somewhere between 13 and 15 locals — not pinned down). Minimal repro would be a fn with ~15 sequential `var` declarations making two calls to the same fn-ptr-taking helper; slot count + helper-return-value pattern both seem to matter. Cross-link for the cyrius agent when they investigate.

- **2026-04-24 (P8)** — Third symptom, same date-case. HTTPS round-trips via `tls.cyr` produce a pathological state: `./build/http-probe https://example.com/` prints "GET https://example.com/" repeatedly (hundreds of times per second) until killed, with no subsequent progress. Plain HTTP to the same host (either via hostname or resolved IP) works fine. Same program against IP-literal plain URL produces a clean single status-200/403 response and exits 0. So: DNS ✓, plain-TCP connect ✓, response parse ✓. Only the TLS path misbehaves. Candidate cause: `lib/tls.cyr::_tls_init` calls `dynlib_open("libcrypto.so.3")` / `dynlib_open("libssl.so.3")` without first running `dynlib_bootstrap_cpu_features()` / `dynlib_bootstrap_tls()` / `dynlib_bootstrap_stack_end()` as `lib/dynlib.cyr:939-946` documents for `libc.so.6` consumers. If the same bootstrap sequence is required for libssl (which depends on libc), the unbootstrapped path may jump into TLS-initialization code with uninitialized %fs / missing auxv / stale stack end, and re-entry through ld.so would explain the "main appears to run many times" symptom. Sandhi's M2 ships v0.3.0 with HTTPS flagged as needs-further-investigation; all compilation + tls_policy module surface stays green. Minimal repro: `programs/http-probe.cyr` in this repo, run against any `https://` URL.
