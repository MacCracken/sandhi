# 2026-04-24 — `fdlopen_getaddrinfo` path blocked in current toolchain

**Status**: Resolved at cyrius v5.6.29-1 — see ✅ note at the bottom of the Log
(misdiagnosis on sandhi side; cyrius shipped a defensive ud2-placeholder fix
so the next missing-include footgun crashes loudly instead of looping).
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

- **2026-04-24 (post-5.6.29 regression surface)** — cyrius 5.6.29 landed the bootstrap-calls-in-`_tls_init` fix (CHANGELOG entry citing this issue doc directly — thank you). On the cyrius CI host + their `tests/tcyr/tls.tcyr` it passes 22/22. On sandhi's host (Arch Linux 6.18.22-lts + glibc 2.43) it does not. Sandhi's `tls-probe` SIGSEGVs in stage 1 (`tls_available()`); stage-by-stage bisection traces the failure back through `_tls_init` → `dynlib_bootstrap_cpu_features()` → `dynlib_open("/lib64/ld-linux-x86-64.so.2")`. The infinite-loop-through-main symptom is still present, just behind a different trigger.

  **Minimum repro (15 lines)** — `sandhi/programs/dynlib-ldso-probe.cyr`:
  ```cyr
  include "lib/alloc.cyr"
  include "lib/string.cyr"
  include "lib/syscalls.cyr"
  include "lib/dynlib.cyr"
  # (plus syscall imports)

  fn main() {
      alloc_init();
      syscall(1, 1, "ENTRY\n", 6);
      syscall(74, 1);  # fsync stdout
      var h = dynlib_open("/lib64/ld-linux-x86-64.so.2");
      syscall(1, 1, "POST-DYNLIB-OPEN\n", 17);
      return 0;
  }
  ```
  Output: "ENTRY\n" printed hundreds of times per second until killed; "POST-DYNLIB-OPEN\n" never prints. Same symptom shape as the original HTTPS loop but with a smaller trigger.

  **Why the cyrius test passed but sandhi's probe doesn't**: `tests/tcyr/tls.tcyr` does `dynlib_open("libcrypto.so.3")` *before* `tls_available()` — so by the time `_tls_init` runs and calls `bootstrap_cpu_features`, `dynlib_open` has already successfully processed libcrypto (which DT_NEEDED-depends-on ld-linux but the code at `lib/dynlib.cyr:816-819` explicitly **skips ld-linux** when resolving deps: `if (memeq(dep_name, "ld-linux", 8) == 0) { dynlib_open(dep_name); }`). So the test never opens ld-linux directly — only via DT_NEEDED skipping, which is a no-op. The new 5.6.29 bootstrap code however opens ld-linux *directly* (`lib/dynlib.cyr:914`), which is the untested path. Sandhi's probe calls `tls_available()` cold, hits the direct open, hits the re-entry.

  **Proposed investigation path** (for the cyrius agent to pick up when bandwidth allows):

  1. **The skip-ld-linux guard in DT_NEEDED resolution (`lib/dynlib.cyr:816-819`) is load-bearing** — it exists because ld-linux is already kernel-mapped and re-opening it via the normal `mmap(PROT_NONE) + MAP_FIXED` path fights the kernel's existing mappings. The bootstrap functions (`dynlib_bootstrap_cpu_features` / `_stack_end`) bypass this guard by calling `dynlib_open("/lib64/ld-linux-x86-64.so.2")` directly. That's the bug.

  2. **Two possible fixes, pick one:**

     A. **Add a fast path in `dynlib_open` for the kernel-loaded ld-linux.** Detect the path (match any `ld-linux*.so*` basename) and, instead of mmap'ing, discover ld-linux's already-loaded base via `/proc/self/maps` or via an auxv read (AT_BASE / AT_SYSINFO_EHDR is more portable), then construct the handle from the existing mappings without remapping. This would fix both the bootstrap callers and any other future consumer that tries to open ld-linux.

     B. **Change the bootstrap functions to not go through `dynlib_open` for ld-linux.** Introduce a private helper like `_dynlib_attach_ldso()` that uses `/proc/self/maps` to find the already-mapped ld-linux base, constructs a minimal handle, and caches it. `dynlib_bootstrap_cpu_features` / `_stack_end` use this helper instead of `dynlib_open`. Path A is more general; B is more surgical.

  3. **Regression test needed on sandhi's host-shape** — the existing `tests/tcyr/tls.tcyr` doesn't catch this because it's ordered such that libcrypto opens first. Adding a test that calls `tls_available()` as the very first dynlib action — cold, no prior `dynlib_open` — would cover the sandhi shape. Proposed:
     ```cyr
     # tests/tcyr/tls-cold-init.tcyr
     include "lib/alloc.cyr"
     include "lib/tls.cyr"
     alloc_init();
     # No prior dynlib_open — _tls_init runs bootstrap cold.
     var avail = tls_available();
     # On hosts with libssl: expect 1. Crash / hang / loop = regression.
     assert(avail == 0 || avail == 1, "tls_available didn't hang");
     ```

  4. **Host details for reproduction:**
     - Arch Linux x86_64 (rolling).
     - Kernel 6.18.22-1-lts.
     - glibc 2.43+r5+g856c426a7534-1.
     - ld-linux resolves `/lib64/ld-linux-x86-64.so.2` → `/usr/lib/ld-linux-x86-64.so.2` (size 234400 B).
     - libssl.so.3 and libcrypto.so.3 present at `/usr/lib/`.
     - `_dl_x86_get_cpu_features@@GLIBC_PRIVATE` is exported (verified via `nm -D /lib64/ld-linux-x86-64.so.2`).

  5. **Sandhi repro programs committed** for the cyrius agent to pull:
     - `sandhi/programs/dynlib-ldso-probe.cyr` — 15-line minimum repro (dynlib_open of ld-linux alone re-enters main).
     - `sandhi/programs/bootstrap-probe.cyr` — step-by-step bootstrap sequence, shows the failure is in step `[B]` (`dynlib_bootstrap_cpu_features`).
     - `sandhi/programs/cpu-features-probe.cyr` — inside `bootstrap_cpu_features`, isolates the failure to `dynlib_open("/lib64/ld-linux-x86-64.so.2")`.
     - `sandhi/programs/tls-probe.cyr` — stage-by-stage TLS flow (stage 1 `tls_available()` cores).

  This extends the issue rather than opening a new one: same root cause (statically-linked cyrius binary collides with kernel-already-loaded ld-linux on dynlib_open), just a new trigger now that the bootstrap sequence directly exercises the path. `5.6.29-1` is WIP on the cyrius side; sandhi's M2 HTTPS + M5 TLS-policy enforcement remain gated on a follow-up fix addressing the ld-linux re-open path specifically. Native DNS resolver workaround keeps everything else unblocked.

- **2026-04-24 (cyrius v5.6.29-1, ✅ resolved — but not the way this doc framed it)** —
  cyrius-side investigation found the diagnosis above is wrong on every count.
  Receipts:

  **`fdlopen_init_full` is not incomplete.** It has been complete since v5.5.34
  (`cyrius/CHANGELOG.md` v5.5.34 entry, `cyrius/lib/fdlopen.cyr:405-413` prot-bit
  comment). `tests/tcyr/fdlopen.tcyr` 40/40 PASS verified at v5.6.29-1, including
  the real `dlopen("libc.so.6") → dlsym("getpid") → fncall0(...) == syscall(39)`
  round-trip. The "STATUS (v5.5.29) KNOWN-INCOMPLETE" comment block at
  `lib/fdlopen.cyr:714-746` was stale text that v5.5.34 forgot to update — that
  comment block is what this issue read and assumed was current state. Replaced
  with current "complete since v5.5.34" text in v5.6.29-1.

  **There is no ld-linux MAP_FIXED collision.** The proposed A/B fixes
  (`_dynlib_attach_ldso` / fast-path) solve a problem that doesn't exist.
  Cold `dynlib_open("/lib64/ld-linux-x86-64.so.2")` returns a valid handle on
  cyrius main right now. The `dt_needed` skip at `lib/dynlib.cyr:816-819` is a
  GUARD AGAINST CIRCULAR DT_NEEDED (ld-linux is the loader, libcrypto's DT_NEEDED
  on it is structural, not because re-opening it would crash) — not load-bearing
  evidence that ld-linux can't be opened directly.

  **Sandhi's probes are missing the `lib/dynlib.cyr` include.** Every probe
  (`dynlib-ldso-probe.cyr`, `bootstrap-probe.cyr`, `cpu-features-probe.cyr`,
  `tls-probe.cyr`) `include`s sandhi modules + `src/main.cyr` and calls
  `dynlib_open` / `dynlib_bootstrap_*`. None of those includes pulls in
  `lib/dynlib.cyr`. Build output for every one of them prints:

  ```
  warning: undefined function 'dynlib_open'
  warning: undefined function 'dynlib_bootstrap_cpu_features'
  warning: undefined function 'dynlib_bootstrap_tls'
  warning: undefined function 'dynlib_bootstrap_stack_end'
  warning: undefined function '_dynlib_resolve_global'
  error: undefined function 'dynlib_open' (will crash at runtime)
  ...
  ```

  Cyrius non-`--strict` mode (the default) emits the binary anyway. The
  call-site `e8 XX XX XX XX` was patched with a placeholder disp32 that
  resolved to `call 0x400076` — exactly two bytes before the entry trampoline
  at `0x400078`. Bytes `00 00` at `0x76`-`0x77` decode as `add %al,(%rax)`
  (harmless byte writes to wherever rax pointed), then fall through into
  `jmp 0x4a720`, which is `_cyrius_init` / global var init / `var exit_code = main()`.
  Hence the perfect `ENTRY/ENTRY/ENTRY` loop with zero `open()` syscalls (the
  brk-extend pattern in strace is `alloc_init` running fresh on every iteration).

  Disassembly of the call site in `sandhi/build/dynlib-ldso-probe`:

  ```
  4a6e6: e8 8b 59 fb ff   call 0x76    # patched-as-call-to dynlib_open
     76: 00 00            add %al,(%rax)
     78: e9 a3 a6 04 00   jmp 0x4a720  # _cyrius_init re-entry
  ```

  Same loop fires with `dynlib_open("libcrypto.so.3")` and
  `dynlib_open("/this/does/not/exist.so")` substituted in — confirming the trigger
  is "any call to undef `dynlib_*`", not anything ld-linux-specific.

  **Sandhi-side fix:** add `include "lib/dynlib.cyr"` (and `lib/tls.cyr`,
  `lib/fdlopen.cyr`, `lib/alloc.cyr`, `lib/string.cyr`, `lib/syscalls.cyr`,
  `lib/mmap.cyr`, `lib/fnptr.cyr` as needed) to each probe. The probe shape
  works fine on cyrius main with the right includes — verified locally with
  a 15-line cold-init repro (alloc + dynlib_open of ld-linux + post-print)
  that prints `POST-DYNLIB-OPEN` and exits 0.

  **Cyrius-side fix shipped as v5.6.29-1:** even though this was a sandhi-side
  diagnosis error, the underlying ergonomic bug is real. A compile-time warning
  that produces a silent runtime infinite loop (instead of a crash) is a
  footgun. `src/backend/x86/fixup.cyr` ftype==2 (and aarch64 ftype==2 + ftype==4)
  now patches undef-fn call sites with `0F 0B 0F 0B 90` (ud2; ud2; nop) on x86,
  `0x00000000` (UDF #0) on aarch64. SIGILL at the call site, loud and
  localisable. Re-running `sandhi/build/dynlib-ldso-probe` against v5.6.29-1
  cyrius now prints one `ENTRY` and exits 132 (= 128 + 4 = SIGILL) instead of
  looping forever. cc5 +224 B; 3-step byte-identical fixpoint clean;
  check.sh 23/23 PASS; tests/tcyr/fdlopen.tcyr 40/40 PASS. Default-on `--strict`
  was considered but rejected for this slot — too disruptive for the slot shape;
  the ud2 treatment is purely additive.

  **Action items for sandhi:**
  1. Add the missing `include "lib/dynlib.cyr"` (et al) to every probe under
     `programs/` that calls `dynlib_*` / `tls_*` / `fdlopen_*`.
  2. Drop the `_dynlib_attach_ldso` proposal from the sandhi roadmap — there's
     nothing to attach; cold open works.
  3. Optionally retire `src/net/resolve.cyr` in favour of `fdlopen_getaddrinfo`
     (the original M2 plan) — the path was never blocked. Recommended once M2
     stabilises; the native UDP resolver is fine for now and removing it later
     is a backward-compat-safe one-direction migration.
  4. Bump `cyrius.cyml [package].cyrius` from `5.6.29` to `5.6.29-1` to pick
     up the ud2 placeholder so the next missing-include mistake fails loudly.

  No further cyrius-side action required. Closing this issue.
