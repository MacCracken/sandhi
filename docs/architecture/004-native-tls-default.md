# 004 — Native TLS is the default; libssl is a deprecated opt-in (1.4.5)

As of **1.4.5**, sandhi defaults to Cyrius's sovereign **native** TLS
backend (`lib/tls_native.cyr`) and treats the **libssl.so.3 fdlopen
bridge** as a deprecated, explicit opt-in.

## Why

The libssl backend loads `libssl.so.3` + `libcrypto.so.3` through
`lib/fdlopen.cyr`, which bootstraps the **real glibc** loader. All of
libssl's internal allocations then go through **glibc malloc**, whose
main arena is managed via the process `brk`/`sbrk`. Cyrius's
`lib/alloc.cyr` bump allocator *also* grows via raw `brk(2)`. Two
independent managers, one program break.

While the cyrius heap stays inside its initial 1 MB reservation the two
don't interact. The first time the cyrius heap grows, it collides with
glibc malloc's arena and corrupts it — a subsequent libssl call
dereferences clobbered memory and the **process SIGSEGVs inside
libssl**. For sandhi's high-level client (which leaks ~256 KB/request
into `default_alloc()`), that first grow lands on **the 4th sequential
HTTPS request** — deterministically.

Root cause is upstream (cyrius), filed as
`cyrius/docs/development/issues/2026-06-09-brk-bump-heap-vs-fdlopen-libssl-malloc.md`.
It reproduces with zero sandhi code. The native stack loads no
libssl/glibc, so there is no brk contention — and the same repeated-
request loop runs crash-free on native (verified, `ok=6/6` against
`one.one.one.one`).

This is the long-tracked direction (CLAUDE.md "No FFI"; roadmap
"Native TLS in cyrius `lib/tls.cyr` gates sit adoption"). 1.4.5 makes it
the default rather than a someday.

## How it works

- **Build default (flag polarity inverted past 1.4.7).** The native
  stack is compiled in and is the stdlib default backend
  (`_tls_backend = 1`) with **no flag**. `-D CYRIUS_TLS_LIBSSL` is the
  explicit opt-in for the deprecated libssl bridge. This inverts the
  1.4.5–1.4.7 convention, where `-D CYRIUS_TLS_NATIVE` was required to
  *get* native and a no-flag build fell back to libssl.

  - sandhi's own builds, CI, and Quick Start build native with **no flag**.
  - **Consumers get native by default** and pass `-D CYRIUS_TLS_LIBSSL`
    only to fall back to the deprecated libssl path.

  > **Upstream dependency.** This inversion requires the cyrius-side
  > inverted-default build (native compiled in by default; `-D
  > CYRIUS_TLS_LIBSSL` as the opt-out). Until that ships in a pinned
  > cyrius release, a no-flag `cyrius build` still resolves to libssl and
  > sandhi's native gates will not pass — the sandhi-side switch is
  > staged ahead of the upstream flip. The previous blocker (no
  > `[build].defines` key in `cyrius.cyml`, so the define had to be on
  > the command line) is resolved by making native the compiled-in
  > default rather than a define-gated opt-in.

- **Runtime surface** (`src/tls_policy/mod.cyr`):
  - `sandhi_tls_backend()` — active backend (0 = libssl, 1 = native).
  - `sandhi_tls_native_available()` — 1 if native was compiled in.
  - `sandhi_tls_use_libssl()` — opt out to the libssl bridge.
  - `sandhi_tls_use_native()` — opt back in (returns -1 if not compiled in).

## The libssl escape hatch

`sandhi_tls_use_libssl()` remains as a backend override. Its initial
caveats were retired by **cyrius 6.1.19** (pinned at 1.4.5):

- The native stack now **handshakes the public host set** (example.com and
  other Cloudflare-fronted hosts, not just 1.1.1.1) — the cert-chain /
  intermediate-ordering gap was fixed upstream.
- The libssl opt-in is **no longer a process-killer** — cyrius moved
  `lib/alloc.cyr`'s Linux heap onto anonymous `mmap` (no more brk-vs-glibc
  contention), so repeated requests on the libssl path don't SIGSEGV.
  (Verified: 6/6 sequential `sandhi_http_get` to example.com on *both*
  backends, no crash.)

The one remaining reason a connection still implies libssl: TLS **policy**
enforcement (cert pinning / mTLS / trust-store in `tls_policy/apply.cyr`)
still resolves several `SSL_CTX_*` symbols via `tls_dlsym` (libssl-only)
and is not yet wired for the native backend. Plain HTTPS (no custom
policy) is the native-default path; policy-bearing connections still use
libssl.

## Exit criteria for full libssl retirement

1. ~~Upstream native-handshake gap closed~~ ✅ cyrius 6.1.19.
2. TLS policy enforcement (pinning / mTLS / trust-store) wired for the
   native backend — **the only remaining blocker.**
3. ~~Upstream brk/fdlopen allocator fix~~ ✅ cyrius 6.1.19 (anonymous-mmap
   heap) — the residual libssl opt-in is no longer a process-killer.

Once (2) lands, the libssl opt-in can be removed entirely. The
`-D CYRIUS_TLS_NATIVE` *requirement* is gone: **cyrius 6.1.21 inverted the
`lib/tls.cyr` default** (native compiled in + selected with no flag;
`-D CYRIUS_TLS_LIBSSL` opts out; legacy `-D CYRIUS_TLS_NATIVE` is a no-op
alias), and sandhi 1.4.9 re-pinned to it + dropped the interim flag from
CI/release. The remaining libssl coupling is native TLS-policy
*enforcement* (2), not the build default. Tracked in the roadmap cross-repo
dependencies + the 1.5.x reshape.
